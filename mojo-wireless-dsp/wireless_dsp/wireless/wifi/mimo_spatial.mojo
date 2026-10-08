"""Bounded HT/VHT/HE spatial parsing and direct CSD mapping.

This scalar CPU reference implements a deliberately narrow part of IEEE Std
802.11-2024.  For equal modulation on one through four spatial streams it
implements the single-FEC-encoder stream parser of 19.3.11.8.2,
21.3.10.6, and 27.3.12.6: consecutive blocks of
``s = max(1, N_BPSCS/2)`` bits are assigned round-robin to the streams.  It
also implements the one-through-four-stream rows of Table 19-10 and Table
21-11, reused for HE-modulated fields by 27.3.11.2.2, and applies those
cyclic shifts before the explicitly direct ``Q = I`` spatial mapping.

Normative publication: https://standards.ieee.org/ieee/802.11/10548/ .
IEEE 802.11 WG adopted material 11-11/0663r1 records the VHT stream-parser
rule and 11-17/0714r4 records that HE per-stream CSD precedes A/Q spatial
mapping.  These working-group documents corroborate the published standard;
they do not replace it.

The profile is limited to one encoder, equal modulation, 1--4 NSS/STS,
ordered tones, no STBC, and ``N_TX = N_STS`` with identity spatial mapping.
The caller owns enclosing TXVECTOR/MCS, code-rate, encoder-count, tone-set,
and field-applicability checks; acceptance here is not complete PPDU
admissibility.
Multiple encoders, 160 MHz segment parsing, unequal modulation, DCM-specific
tone mapping, STBC, arbitrary/beamformed Q matrices, channel sounding,
feedback compression, SU/MU scheduling, channel estimation, equalization,
and RF antenna behavior remain outside this module.  Consequently this is
not a complete HT/VHT/HE MIMO PHY.
"""

from std.collections import Span
from std.math import cos, isfinite, sin
from wireless_dsp.core import Complex64
from wireless_dsp.wireless.wifi.profiles import (
    WIFI_PHY_HT,
    WIFI_PHY_VHT,
    WIFI_PHY_HE,
)


comptime _TWO_PI = 6.283185307179586476925286766559
comptime WIFI_MIMO_MAX_BOUNDED_SPATIAL_STREAMS = 4


struct WifiMIMOSpatialConfig(ImplicitlyCopyable):
    """Mutable equal-modulation, single-encoder direct-mapping profile.

    ``fft_size`` identifies a published contiguous-bandwidth numerology and
    bounds every supplied signed tone index.  Public algorithms revalidate
    every field so mutation cannot bypass the constructor contract.
    """

    var family: Int
    var spatial_streams: Int
    var bits_per_subcarrier: Int
    var fft_size: Int

    def __init__(
        out self,
        family: Int,
        spatial_streams: Int,
        bits_per_subcarrier: Int,
        fft_size: Int,
    ) raises:
        self.family = family
        self.spatial_streams = spatial_streams
        self.bits_per_subcarrier = bits_per_subcarrier
        self.fft_size = fft_size
        self.validate()

    def validate(self) raises:
        """Revalidate the bounded family, NSS, modulation, and NFFT."""
        if (
            self.spatial_streams < 1
            or self.spatial_streams
            > WIFI_MIMO_MAX_BOUNDED_SPATIAL_STREAMS
        ):
            raise Error(
                "bounded Wi-Fi spatial processing requires 1..4 streams"
            )

        var valid_bpsc = (
            self.bits_per_subcarrier == 1
            or self.bits_per_subcarrier == 2
            or self.bits_per_subcarrier == 4
            or self.bits_per_subcarrier == 6
        )
        if self.family == WIFI_PHY_HT:
            if not valid_bpsc:
                raise Error(
                    "HT equal modulation supports 1, 2, 4, or 6 bits/tone"
                )
            if self.fft_size != 64 and self.fft_size != 128:
                raise Error("HT NFFT must be 64 or 128")
            return

        if self.family == WIFI_PHY_VHT:
            valid_bpsc = valid_bpsc or self.bits_per_subcarrier == 8
            if not valid_bpsc:
                raise Error(
                    "VHT equal modulation supports 1, 2, 4, 6, or 8 bits/tone"
                )
            if (
                self.fft_size != 64
                and self.fft_size != 128
                and self.fft_size != 256
                and self.fft_size != 512
            ):
                raise Error("VHT NFFT must be 64, 128, 256, or 512")
            return

        if self.family == WIFI_PHY_HE:
            valid_bpsc = (
                valid_bpsc
                or self.bits_per_subcarrier == 8
                or self.bits_per_subcarrier == 10
            )
            if not valid_bpsc:
                raise Error(
                    "HE equal modulation supports BPSC 1, 2, 4, 6, 8, or 10"
                )
            if (
                self.fft_size != 256
                and self.fft_size != 512
                and self.fft_size != 1024
                and self.fft_size != 2048
            ):
                raise Error("HE NFFT must be 256, 512, 1024, or 2048")
            return

        raise Error("bounded Wi-Fi spatial processing supports HT, VHT, or HE")


def wifi_mimo_parser_block_bits(config: WifiMIMOSpatialConfig) raises -> Int:
    """Return the normative equal-modulation parser block size ``s``."""
    config.validate()
    if config.bits_per_subcarrier < 2:
        return 1
    return config.bits_per_subcarrier // 2


def _validate_binary_bits(bits: Span[UInt8, ...]) raises:
    if len(bits) == 0:
        raise Error("Wi-Fi spatial parser input must be nonempty")
    for index in range(len(bits)):
        if bits[index] > 1:
            raise Error("Wi-Fi spatial parser accepts binary bits only")


def wifi_mimo_spatial_parse(
    config: WifiMIMOSpatialConfig, bits: Span[UInt8, ...]
) raises -> List[UInt8]:
    """Parse one FEC-encoder block into a flattened stream-major buffer.

    The returned layout is ``[stream 0 bits, stream 1 bits, ...]``.  Every
    stream has ``len(bits)/NSS`` bits.  The input must end at a complete
    ``NSS*s`` round-robin cycle; residue and multiple-encoder rules are not
    silently guessed.
    """
    config.validate()
    _validate_binary_bits(bits)
    var block_bits = wifi_mimo_parser_block_bits(config)
    var cycle_bits = config.spatial_streams * block_bits
    if len(bits) % cycle_bits != 0:
        raise Error("spatial parser input must contain complete NSS*s cycles")

    var bits_per_stream = len(bits) // config.spatial_streams
    var output = List[UInt8](length=len(bits), fill=0)
    var groups = len(bits) // block_bits
    for group in range(groups):
        var stream = group % config.spatial_streams
        var stream_group = group // config.spatial_streams
        var source = group * block_bits
        var destination = stream * bits_per_stream + stream_group * block_bits
        for offset in range(block_bits):
            output[destination + offset] = bits[source + offset]
    return output^


def wifi_mimo_spatial_deparse(
    config: WifiMIMOSpatialConfig, stream_major_bits: Span[UInt8, ...]
) raises -> List[UInt8]:
    """Invert the bounded stream parser from a stream-major bit buffer."""
    config.validate()
    _validate_binary_bits(stream_major_bits)
    var block_bits = wifi_mimo_parser_block_bits(config)
    var cycle_bits = config.spatial_streams * block_bits
    if len(stream_major_bits) % cycle_bits != 0:
        raise Error("spatial deparser input must contain complete NSS*s cycles")

    var bits_per_stream = len(stream_major_bits) // config.spatial_streams
    var output = List[UInt8](length=len(stream_major_bits), fill=0)
    var groups = len(stream_major_bits) // block_bits
    for group in range(groups):
        var stream = group % config.spatial_streams
        var stream_group = group // config.spatial_streams
        var destination = group * block_bits
        var source = stream * bits_per_stream + stream_group * block_bits
        for offset in range(block_bits):
            output[destination + offset] = stream_major_bits[source + offset]
    return output^


def wifi_mimo_cyclic_shift_ns(
    config: WifiMIMOSpatialConfig, stream_index: Int
) raises -> Int:
    """Return the 1--4 STS modulated-field CSD table value in ns.

    ``stream_index`` is zero-based.  HT uses Table 19-10; VHT uses Table
    21-11.  Clause 27.3.11.2.2 reuses the VHT per-stream values for HE.
    """
    config.validate()
    if stream_index < 0 or stream_index >= config.spatial_streams:
        raise Error("Wi-Fi CSD stream index is outside the configured STS set")
    if stream_index == 0:
        return 0
    if stream_index == 1:
        return -400
    if stream_index == 2:
        return -200
    return -600


def _validate_tone_grid(
    config: WifiMIMOSpatialConfig,
    symbols: Span[Complex64, ...],
    tone_indices: Span[Int, ...],
) raises:
    config.validate()
    if len(tone_indices) == 0:
        raise Error("Wi-Fi direct spatial mapper requires at least one tone")
    if len(tone_indices) > Int.MAX // config.spatial_streams:
        raise Error("Wi-Fi spatial grid shape overflows Int")
    if len(symbols) != config.spatial_streams * len(tone_indices):
        raise Error("Wi-Fi spatial grid must be NSS by tone-count")
    var minimum_tone = -(config.fft_size // 2)
    var maximum_tone = config.fft_size // 2 - 1
    for tone in range(len(tone_indices)):
        if (
            tone_indices[tone] < minimum_tone
            or tone_indices[tone] > maximum_tone
        ):
            raise Error("Wi-Fi tone index is outside the configured NFFT")
        if tone > 0 and tone_indices[tone] <= tone_indices[tone - 1]:
            raise Error("Wi-Fi tone indices must be strictly increasing")
    for index in range(len(symbols)):
        if not isfinite(symbols[index].re) or not isfinite(symbols[index].im):
            raise Error("Wi-Fi spatial symbols must be finite")


def _direct_csd_transform(
    config: WifiMIMOSpatialConfig,
    symbols: Span[Complex64, ...],
    tone_indices: Span[Int, ...],
    inverse: Bool,
) raises -> List[Complex64]:
    _validate_tone_grid(config, symbols, tone_indices)
    var useful_symbol_ns = 12_800 if config.family == WIFI_PHY_HE else 3_200
    var tones = len(tone_indices)
    var output = List[Complex64](capacity=len(symbols))
    for stream in range(config.spatial_streams):
        var shift_ns = wifi_mimo_cyclic_shift_ns(config, stream)
        for tone in range(tones):
            var value = symbols[stream * tones + tone]
            if shift_ns == 0 or tone_indices[tone] == 0:
                output.append(value)
                continue
            var angle = (
                -_TWO_PI
                * Float64(tone_indices[tone])
                * Float64(shift_ns)
                / Float64(useful_symbol_ns)
            )
            if inverse:
                angle = -angle
            var rotated = value * Complex64(cos(angle), sin(angle))
            if not isfinite(rotated.re) or not isfinite(rotated.im):
                raise Error("Wi-Fi CSD rotation result is not representable")
            output.append(rotated)
    return output^


def wifi_mimo_direct_csd_map(
    config: WifiMIMOSpatialConfig,
    stream_major_symbols: Span[Complex64, ...],
    tone_indices: Span[Int, ...],
) raises -> List[Complex64]:
    """Apply per-STS CSD and direct ``Q=I`` spatial mapping.

    Input streams and output transmit chains are both flattened stream-major.
    This API requires ``N_TX=N_STS`` and intentionally does not accept an
    arbitrary matrix, so it cannot be mistaken for beamforming or MU-MIMO.
    """
    return _direct_csd_transform(
        config, stream_major_symbols, tone_indices, False
    )


def wifi_mimo_direct_csd_unmap(
    config: WifiMIMOSpatialConfig,
    chain_major_symbols: Span[Complex64, ...],
    tone_indices: Span[Int, ...],
) raises -> List[Complex64]:
    """Remove bounded per-STS CSD from an identity-mapped tone grid."""
    return _direct_csd_transform(
        config, chain_major_symbols, tone_indices, True
    )
