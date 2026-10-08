"""Bounded CPU HE/EHT SIGNAL waveforms and signal-driven DATA receive.

This module closes the on-waveform boundary for three deliberately narrow
20 MHz, one-spatial-stream profiles:

* HE SU and 242-tone HE ER SU HE-SIG-A;
* the U-SIG of a nonpunctured EHT SU transmission; and
* one 42-bit EHT SU Common encoding block containing its first User field,
  using EHT-SIG MCS 0 (BPSK, rate 1/2) in two OFDM symbols.

Each 52-bit HE-SIG-A/U-SIG/EHT-SIG block is encoded by the K=7, 133/171
octal BCC, split into 52-bit symbol blocks, interleaved with the 13 by 4
HE-SIG interleaver, BPSK mapped, placed on the 52 data plus four pilot tones,
and transformed by a 64-point IFFT with a 16-sample guard interval.  HE ER SU
emits HE-SIG-A1, HE-SIG-A1-R, HE-SIG-A2, HE-SIG-A2-R: the repeated parts are
not interleaved and HE-SIG-A1-R uses QBPSK.  EHT-SIG applies the specified
PAPR phase row to its upper 26 data-tone positions.

Receivers normalize finite input symbols before the FFT, estimate a common
complex SISO gain from all four pilots, undo repetition/phase rules, perform
soft Viterbi decoding, and invoke the existing CRC/fixed/tail parsers.  The
decoded fields create a real ``WifiSignalDataProfile`` through the public MCS
tables.  The two signal-driven LDPC entry points then pass the decoded family,
MCS, and coding profile to the existing RU-242 DATA receiver; the DATA profile
is not supplied independently by the caller.

The EHT U-SIG type/compression code used here is shared with an EHT sounding
NDP.  ``wifi_eht_u_sig_waveform_rx_20mhz`` therefore requires and retains an
explicit caller acquisition context.  The complete SU DATA receiver rejects
the sounding-NDP context instead of inferring SU from the raw U-SIG bits.

The waveform is a retained SIGNAL-field slice, not an interoperable complete
PPDU.  L-STF/L-LTF/L-SIG/RL-SIG, HE/EHT-STF/LTF construction, packet
extensions, MU/TB/Trigger, Doppler/midambles, puncturing, 40--320 MHz,
multi-stream spatial mapping, EHT-SIG MCS 1/3/DCM, arbitrary Common/User
blocks, and DATA transmit geometry remain outside this bounded module.

Normative sources: IEEE Std 802.11-2024 Clause 27 and IEEE Std 802.11be-2024
Clause 36.  Working-group records used only to cross-check the published
standard, never as normative authority, are 11-20/1875r2 (U-SIG),
11-20/1276r8 (EHT-SIG encoding/waveform), 11-22/0472r0 and
11-23/0446r1 (U-SIG), and 11-23/0319r1 plus 11-24/0260r1 (EHT-SIG Common
encoding blocks and final ballot examples).
"""

from std.collections import Span
from std.math import isfinite, sqrt
from wireless_dsp.core import Complex64
from wireless_dsp.dsp import complex_divide, ofdm_demodulate, ofdm_modulate
from wireless_dsp.fec import convolutional_encode, viterbi_decode_soft
from wireless_dsp.modem import qam_map
from wireless_dsp.testing.checkpoint import (
    CheckpointMetadata,
    checkpoint_metadata_1d,
)
from wireless_dsp.wireless.wifi.coding import (
    WifiBCCInterleaverProfile,
    wifi_bcc_interleave_block,
)
from wireless_dsp.wireless.wifi.he_eht_sig_fields import (
    WIFI_EHT_SIG_BLOCK_COMMON,
    WIFI_HE_EHT_SIG_CODING_BCC,
    WIFI_HE_EHT_SIG_CODING_LDPC,
    WifiEhtSigBlockProfile,
    WifiEhtUSigSU20Config,
    WifiEhtUSigSU20Fields,
    WifiHeSigASUConfig,
    WifiHeSigASUFields,
    wifi_eht_sig_block_pack,
    wifi_eht_sig_block_parse,
    wifi_eht_u_sig_su_20_pack,
    wifi_eht_u_sig_su_20_parse,
    wifi_he_sig_a_su_pack,
    wifi_he_sig_a_su_parse,
)
from wireless_dsp.wireless.wifi.legacy import wifi_pilot_polarity
from wireless_dsp.wireless.wifi.phy_chain import (
    WifiLDPCRx20MHz,
    wifi_ldpc_rx_20mhz,
)
from wireless_dsp.wireless.wifi.profiles import (
    WIFI_PHY_EHT,
    WIFI_PHY_HE,
    wifi_mcs_profile,
)


comptime WIFI_HE_EHT_SIG_WAVEFORM_FFT_SIZE = 64
comptime WIFI_HE_EHT_SIG_WAVEFORM_CP_SAMPLES = 16
comptime WIFI_HE_EHT_SIG_WAVEFORM_SYMBOL_SAMPLES = 80
comptime WIFI_HE_EHT_SIG_WAVEFORM_DATA_TONES = 52
comptime WIFI_HE_EHT_SIG_WAVEFORM_PILOT_TONES = 4
comptime WIFI_HE_SIG_A_SU_WAVEFORM_SAMPLES = 160
comptime WIFI_HE_SIG_A_ER_SU_WAVEFORM_SAMPLES = 320
comptime WIFI_EHT_U_SIG_WAVEFORM_SAMPLES = 160
comptime WIFI_EHT_SU_SIGNAL_WAVEFORM_SAMPLES = 320

comptime WIFI_EHT_ACQUISITION_SU_DATA = 0
comptime WIFI_EHT_ACQUISITION_SOUNDING_NDP = 1

comptime _SIGNAL_MODE_ORDINARY = 0
comptime _SIGNAL_MODE_HE_ER = 1
comptime _SIGNAL_MODE_EHT_SIG = 2
comptime _EHT_SU_CONTENT_BITS = 42
comptime _SIGNAL_TONES = 56
comptime _SIGNAL_TONE_SCALE = 1.0690449676496976  # sqrt(64 / 56)


def _append_unsigned_lsb(mut output: List[UInt8], value: Int, width: Int):
    for index in range(width):
        output.append(UInt8((value >> index) & 1))


def _read_unsigned_lsb(
    bits: Span[UInt8, ...], offset: Int, width: Int
) -> Int:
    var value = 0
    for index in range(width):
        value |= Int(bits[offset + index]) << index
    return value


def _validate_context(acquisition_context: Int) raises:
    if (
        acquisition_context != WIFI_EHT_ACQUISITION_SU_DATA
        and acquisition_context != WIFI_EHT_ACQUISITION_SOUNDING_NDP
    ):
        raise Error("unknown EHT acquisition context")


struct WifiSignalDataProfile(ImplicitlyCopyable):
    """DATA parameters derived from decoded HE/EHT SIGNAL fields."""

    var family: Int
    var bandwidth_mhz: Int
    var mcs_index: Int
    var coding: Int
    var spatial_streams: Int
    var dcm: Bool
    var bits_per_subcarrier: Int
    var code_rate_numerator: Int
    var code_rate_denominator: Int
    var ldpc_only: Bool

    def __init__(
        out self,
        family: Int,
        bandwidth_mhz: Int,
        mcs_index: Int,
        coding: Int,
        spatial_streams: Int,
        dcm: Bool,
        bits_per_subcarrier: Int,
        code_rate_numerator: Int,
        code_rate_denominator: Int,
        ldpc_only: Bool,
    ):
        self.family = family
        self.bandwidth_mhz = bandwidth_mhz
        self.mcs_index = mcs_index
        self.coding = coding
        self.spatial_streams = spatial_streams
        self.dcm = dcm
        self.bits_per_subcarrier = bits_per_subcarrier
        self.code_rate_numerator = code_rate_numerator
        self.code_rate_denominator = code_rate_denominator
        self.ldpc_only = ldpc_only


def _make_data_profile(
    family: Int,
    mcs_index: Int,
    coding: Int,
    spatial_streams: Int,
    dcm: Bool,
) raises -> WifiSignalDataProfile:
    if (
        coding != WIFI_HE_EHT_SIG_CODING_BCC
        and coding != WIFI_HE_EHT_SIG_CODING_LDPC
    ):
        raise Error("decoded SIGNAL contains an unknown DATA coding value")
    if spatial_streams != 1:
        raise Error("bounded SIGNAL waveform supports one DATA spatial stream")
    var mcs = wifi_mcs_profile(
        family,
        mcs_index,
        spatial_streams=spatial_streams,
        dcm=dcm,
    )
    if mcs.ldpc_only and coding != WIFI_HE_EHT_SIG_CODING_LDPC:
        raise Error("decoded DATA MCS requires LDPC coding")
    if family == WIFI_PHY_EHT and mcs.duplicate_mode:
        raise Error("EHT MCS 14 duplicate mode is not defined for 20 MHz")
    return WifiSignalDataProfile(
        family,
        20,
        mcs_index,
        coding,
        spatial_streams,
        mcs.dcm,
        mcs.bits_per_subcarrier,
        mcs.code_rate_numerator,
        mcs.code_rate_denominator,
        mcs.ldpc_only,
    )


def _he_data_profile(fields: WifiHeSigASUFields) raises -> WifiSignalDataProfile:
    if fields.bandwidth_mhz != 20:
        raise Error("bounded HE-SIG-A waveform requires a 20 MHz DATA profile")
    if fields.space_time_streams != 1 or fields.stbc:
        raise Error("bounded HE-SIG-A waveform excludes multi-stream and STBC DATA")
    return _make_data_profile(
        WIFI_PHY_HE,
        fields.mcs_index,
        fields.coding,
        1,
        fields.dcm,
    )


struct WifiEhtSigSU20Config(ImplicitlyCopyable):
    """Mutable one-user EHT-SIG Common encoding-block configuration.

    The first 20 bits are U-SIG Overflow/Number Of Non-OFDMA Users and the
    following 22 bits are the first non-MU-MIMO User field.  This exact
    42-bit content produces a 52-bit CRC/tail block and, with EHT-SIG MCS 0,
    exactly two OFDM symbols.
    """

    var spatial_reuse: Int
    var gi_ltf_code: Int
    var eht_ltf_symbols: Int
    var ldpc_extra_symbol: Bool
    var pre_fec_padding_factor: Int
    var pe_disambiguity: Bool
    var sta_id: Int
    var mcs_index: Int
    var spatial_streams: Int
    var beamformed: Bool
    var coding: Int

    def __init__(
        out self,
        mcs_index: Int,
        *,
        sta_id: Int = 0,
        spatial_reuse: Int = 0,
        gi_ltf_code: Int = 0,
        eht_ltf_symbols: Int = 1,
        ldpc_extra_symbol: Bool = False,
        pre_fec_padding_factor: Int = 0,
        pe_disambiguity: Bool = False,
        spatial_streams: Int = 1,
        beamformed: Bool = False,
        coding: Int = WIFI_HE_EHT_SIG_CODING_LDPC,
    ):
        self.spatial_reuse = spatial_reuse
        self.gi_ltf_code = gi_ltf_code
        self.eht_ltf_symbols = eht_ltf_symbols
        self.ldpc_extra_symbol = ldpc_extra_symbol
        self.pre_fec_padding_factor = pre_fec_padding_factor
        self.pe_disambiguity = pe_disambiguity
        self.sta_id = sta_id
        self.mcs_index = mcs_index
        self.spatial_streams = spatial_streams
        self.beamformed = beamformed
        self.coding = coding


def _eht_ltf_count_code(symbols: Int) raises -> Int:
    if symbols == 1:
        return 0
    if symbols == 2:
        return 1
    if symbols == 4:
        return 2
    if symbols == 6:
        return 3
    if symbols == 8:
        return 4
    raise Error("EHT-SIG LTF count must be 1, 2, 4, 6, or 8")


def _eht_ltf_count_from_code(code: Int) raises -> Int:
    if code == 0:
        return 1
    if code == 1:
        return 2
    if code == 2:
        return 4
    if code == 3:
        return 6
    if code == 4:
        return 8
    raise Error("EHT-SIG LTF count contains a reserved value")


def _validate_eht_sig_su_20_config(
    config: WifiEhtSigSU20Config,
) raises -> WifiSignalDataProfile:
    if config.spatial_reuse < 0 or config.spatial_reuse > 15:
        raise Error("EHT-SIG Spatial Reuse must be in [0,15]")
    if config.gi_ltf_code < 0 or config.gi_ltf_code > 3:
        raise Error("EHT-SIG GI/LTF code must be in [0,3]")
    _ = _eht_ltf_count_code(config.eht_ltf_symbols)
    if config.eht_ltf_symbols != 1:
        raise Error("bounded one-stream EHT SU uses exactly one EHT-LTF symbol")
    if (
        config.pre_fec_padding_factor < 0
        or config.pre_fec_padding_factor > 3
    ):
        raise Error("EHT-SIG pre-FEC padding factor must be in [0,3]")
    if config.sta_id < 0 or config.sta_id > 2045:
        raise Error("bounded EHT SU STA-ID excludes reserved 2046/2047")
    if config.spatial_streams != 1:
        raise Error("bounded EHT SU EHT-SIG supports exactly one stream")
    if (
        config.ldpc_extra_symbol
        and config.coding != WIFI_HE_EHT_SIG_CODING_LDPC
    ):
        raise Error("EHT-SIG LDPC extra symbol requires LDPC DATA coding")
    return _make_data_profile(
        WIFI_PHY_EHT,
        config.mcs_index,
        config.coding,
        config.spatial_streams,
        False,
    )


struct WifiEhtSigSU20Fields(ImplicitlyCopyable):
    """Decoded fields from the bounded 42-bit EHT SU Common block."""

    var spatial_reuse: Int
    var gi_ltf_code: Int
    var eht_ltf_symbols: Int
    var ldpc_extra_symbol: Bool
    var pre_fec_padding_factor: Int
    var pe_disambiguity: Bool
    var sta_id: Int
    var mcs_index: Int
    var spatial_streams: Int
    var beamformed: Bool
    var coding: Int
    var crc: Int

    def __init__(out self, config: WifiEhtSigSU20Config, crc: Int):
        self.spatial_reuse = config.spatial_reuse
        self.gi_ltf_code = config.gi_ltf_code
        self.eht_ltf_symbols = config.eht_ltf_symbols
        self.ldpc_extra_symbol = config.ldpc_extra_symbol
        self.pre_fec_padding_factor = config.pre_fec_padding_factor
        self.pe_disambiguity = config.pe_disambiguity
        self.sta_id = config.sta_id
        self.mcs_index = config.mcs_index
        self.spatial_streams = config.spatial_streams
        self.beamformed = config.beamformed
        self.coding = config.coding
        self.crc = crc


def wifi_eht_sig_su_20_pack(config: WifiEhtSigSU20Config) raises -> List[UInt8]:
    """Pack the exact bounded one-user EHT-SIG Common encoding block."""
    _ = _validate_eht_sig_su_20_config(config)
    var content = List[UInt8](capacity=_EHT_SU_CONTENT_BITS)
    _append_unsigned_lsb(content, config.spatial_reuse, 4)
    _append_unsigned_lsb(content, config.gi_ltf_code, 2)
    _append_unsigned_lsb(content, _eht_ltf_count_code(config.eht_ltf_symbols), 3)
    content.append(UInt8(1 if config.ldpc_extra_symbol else 0))
    _append_unsigned_lsb(content, config.pre_fec_padding_factor, 2)
    content.append(UInt8(1 if config.pe_disambiguity else 0))
    for _ in range(4):
        content.append(UInt8(1))  # Disregard.
    _append_unsigned_lsb(content, 0, 3)  # One non-OFDMA user: Nusers - 1.

    _append_unsigned_lsb(content, config.sta_id, 11)
    _append_unsigned_lsb(content, config.mcs_index, 4)
    content.append(UInt8(1))  # Reserved.
    _append_unsigned_lsb(content, config.spatial_streams - 1, 4)
    content.append(UInt8(1 if config.beamformed else 0))
    content.append(UInt8(config.coding))
    var profile = WifiEhtSigBlockProfile(
        WIFI_EHT_SIG_BLOCK_COMMON, _EHT_SU_CONTENT_BITS
    )
    return wifi_eht_sig_block_pack(profile, Span(content))


def wifi_eht_sig_su_20_parse(
    bits: Span[UInt8, ...],
) raises -> WifiEhtSigSU20Fields:
    """Parse and validate the bounded one-user EHT-SIG Common block."""
    var profile = WifiEhtSigBlockProfile(
        WIFI_EHT_SIG_BLOCK_COMMON, _EHT_SU_CONTENT_BITS
    )
    var block = wifi_eht_sig_block_parse(profile, bits)
    var content = block.content.copy()
    for index in range(13, 17):
        if content[index] != 1:
            raise Error("bounded EHT-SIG Disregard bits must be one")
    if _read_unsigned_lsb(Span(content), 17, 3) != 0:
        raise Error("bounded EHT-SIG requires exactly one non-OFDMA user")
    if content[35] != 1:
        raise Error("bounded EHT-SIG User reserved bit must be one")
    var config = WifiEhtSigSU20Config(
        _read_unsigned_lsb(Span(content), 31, 4),
        sta_id=_read_unsigned_lsb(Span(content), 20, 11),
        spatial_reuse=_read_unsigned_lsb(Span(content), 0, 4),
        gi_ltf_code=_read_unsigned_lsb(Span(content), 4, 2),
        eht_ltf_symbols=_eht_ltf_count_from_code(
            _read_unsigned_lsb(Span(content), 6, 3)
        ),
        ldpc_extra_symbol=content[9] != 0,
        pre_fec_padding_factor=_read_unsigned_lsb(Span(content), 10, 2),
        pe_disambiguity=content[12] != 0,
        spatial_streams=_read_unsigned_lsb(Span(content), 36, 4) + 1,
        beamformed=content[40] != 0,
        coding=Int(content[41]),
    )
    _ = _validate_eht_sig_su_20_config(config)
    return WifiEhtSigSU20Fields(config, block.crc)


def _signal_interleaver(family: Int) -> WifiBCCInterleaverProfile:
    # Table 27-35, HE-SIG-A/HE-SIG-B 56-tone column, no DCM.
    return WifiBCCInterleaverProfile(family, 52, 13, 4, 0, 1, False)


def _data_subcarriers() -> List[Int]:
    var result = List[Int](capacity=WIFI_HE_EHT_SIG_WAVEFORM_DATA_TONES)
    for subcarrier in range(-28, 29):
        if (
            subcarrier == 0
            or subcarrier == -21
            or subcarrier == -7
            or subcarrier == 7
            or subcarrier == 21
        ):
            continue
        result.append(subcarrier)
    return result^


def _fft_bin(subcarrier: Int) -> Int:
    return subcarrier if subcarrier >= 0 else 64 + subcarrier


def _pilots(symbol_index: Int) raises -> List[Complex64]:
    var polarity = wifi_pilot_polarity(symbol_index)
    return [
        Complex64(polarity),
        Complex64(polarity),
        Complex64(polarity),
        Complex64(-polarity),
    ]


def _map_signal_spectrum(
    data: Span[Complex64, ...], pilots: Span[Complex64, ...]
) raises -> List[Complex64]:
    if (
        len(data) != WIFI_HE_EHT_SIG_WAVEFORM_DATA_TONES
        or len(pilots) != WIFI_HE_EHT_SIG_WAVEFORM_PILOT_TONES
    ):
        raise Error("HE/EHT SIGNAL symbol has invalid tone geometry")
    var spectrum = List[Complex64](
        length=WIFI_HE_EHT_SIG_WAVEFORM_FFT_SIZE,
        fill=Complex64(0.0, 0.0),
    )
    var indices = _data_subcarriers()
    for index in range(len(indices)):
        var data_value = data[index]
        spectrum[_fft_bin(indices[index])] = data_value * Complex64(
            _SIGNAL_TONE_SCALE
        )
    var pilot_indices: List[Int] = [-21, -7, 7, 21]
    for index in range(len(pilot_indices)):
        var pilot_value = pilots[index]
        spectrum[_fft_bin(pilot_indices[index])] = pilot_value * Complex64(
            _SIGNAL_TONE_SCALE
        )
    return spectrum^


struct _EncodedSignalWaveform(Movable):
    var bits: List[UInt8]
    var coded_bits: List[UInt8]
    var transmitted_bits: List[UInt8]
    var data_symbols: List[Complex64]
    var spectra: List[Complex64]
    var waveform: List[Complex64]

    def __init__(
        out self,
        var bits: List[UInt8],
        var coded_bits: List[UInt8],
        var transmitted_bits: List[UInt8],
        var data_symbols: List[Complex64],
        var spectra: List[Complex64],
        var waveform: List[Complex64],
    ):
        self.bits = bits^
        self.coded_bits = coded_bits^
        self.transmitted_bits = transmitted_bits^
        self.data_symbols = data_symbols^
        self.spectra = spectra^
        self.waveform = waveform^


def _encode_signal_waveform(
    bits: Span[UInt8, ...],
    family: Int,
    mode: Int,
    pilot_start: Int,
) raises -> _EncodedSignalWaveform:
    if len(bits) != 52:
        raise Error("bounded HE/EHT SIGNAL field must contain 52 bits")
    var owned_bits = List[UInt8](capacity=52)
    for index in range(52):
        if bits[index] > 1:
            raise Error("bounded HE/EHT SIGNAL field must be binary")
        owned_bits.append(bits[index])
    var generators: List[Int] = [0o133, 0o171]
    var coded = convolutional_encode(
        bits, Span(generators), 7, terminate=False
    )
    if len(coded) != 104:
        raise Error("internal HE/EHT SIGNAL BCC length mismatch")
    var symbol_count = 4 if mode == _SIGNAL_MODE_HE_ER else 2
    if (
        mode != _SIGNAL_MODE_ORDINARY
        and mode != _SIGNAL_MODE_HE_ER
        and mode != _SIGNAL_MODE_EHT_SIG
    ):
        raise Error("unknown HE/EHT SIGNAL waveform mode")
    var transmitted = List[UInt8](capacity=symbol_count * 52)
    var data_symbols = List[Complex64](capacity=symbol_count * 52)
    var spectra = List[Complex64](capacity=symbol_count * 64)
    var waveform = List[Complex64](capacity=symbol_count * 80)
    var interleaver = _signal_interleaver(family)
    for emitted_symbol in range(symbol_count):
        var source_symbol = emitted_symbol
        var interleaved = True
        var qbPSK = False
        if mode == _SIGNAL_MODE_HE_ER:
            source_symbol = emitted_symbol // 2
            interleaved = emitted_symbol == 0 or emitted_symbol == 2
            qbPSK = emitted_symbol == 1
        var block = List[UInt8](capacity=52)
        for index in range(52):
            block.append(coded[source_symbol * 52 + index])
        if interleaved:
            block = wifi_bcc_interleave_block(
                Span(block), 1, interleaver
            )
        for bit in block:
            transmitted.append(bit)
        var mapped = qam_map(Span(block), 1)
        if qbPSK:
            for index in range(len(mapped)):
                mapped[index] = Complex64(-mapped[index].im, mapped[index].re)
        if mode == _SIGNAL_MODE_EHT_SIG:
            for index in range(26, 52):
                if index % 2 != 0:
                    mapped[index] = -mapped[index]
        for symbol in mapped:
            data_symbols.append(symbol)
        var pilots = _pilots(pilot_start + emitted_symbol)
        var spectrum = _map_signal_spectrum(Span(mapped), Span(pilots))
        for value in spectrum:
            spectra.append(value)
        var ofdm = ofdm_modulate(
            Span(spectrum), WIFI_HE_EHT_SIG_WAVEFORM_CP_SAMPLES
        )
        for value in ofdm:
            waveform.append(value)
    return _EncodedSignalWaveform(
        owned_bits^,
        coded^,
        transmitted^,
        data_symbols^,
        spectra^,
        waveform^,
    )


def _normalized_symbol(
    samples: Span[Complex64, ...], offset: Int
) raises -> List[Complex64]:
    if (
        offset < 0
        or offset > len(samples)
        or len(samples) - offset < WIFI_HE_EHT_SIG_WAVEFORM_SYMBOL_SAMPLES
    ):
        raise Error("HE/EHT SIGNAL OFDM symbol lies outside the input")
    var scale = 0.0
    for index in range(WIFI_HE_EHT_SIG_WAVEFORM_SYMBOL_SAMPLES):
        var value = samples[offset + index]
        if not isfinite(value.re) or not isfinite(value.im):
            raise Error("HE/EHT SIGNAL samples must be finite")
        scale = max(scale, max(abs(value.re), abs(value.im)))
    if scale == 0.0:
        raise Error("HE/EHT SIGNAL OFDM symbol has zero energy")
    var result = List[Complex64](
        capacity=WIFI_HE_EHT_SIG_WAVEFORM_SYMBOL_SAMPLES
    )
    for index in range(WIFI_HE_EHT_SIG_WAVEFORM_SYMBOL_SAMPLES):
        var value = samples[offset + index]
        result.append(Complex64(value.re / scale, value.im / scale))
    return result^


def _estimate_common_channel(
    spectrum: Span[Complex64, ...], pilot_symbol_index: Int
) raises -> Complex64:
    if len(spectrum) != 64:
        raise Error("HE/EHT SIGNAL spectrum must contain 64 bins")
    var known = _pilots(pilot_symbol_index)
    var indices: List[Int] = [-21, -7, 7, 21]
    var estimate = Complex64(0.0, 0.0)
    for index in range(4):
        var received = spectrum[_fft_bin(indices[index])]
        # Divide each contribution before accumulation to prevent a finite
        # four-pilot sum from overflowing.
        estimate = estimate + received * known[index].conjugate() * Complex64(
            1.0 / (4.0 * _SIGNAL_TONE_SCALE)
        )
    var magnitude = estimate.magnitude()
    if not isfinite(magnitude) or magnitude == 0.0:
        raise Error("HE/EHT SIGNAL pilot channel estimate is unusable")
    return estimate


def _deinterleave_signal_llrs(
    llrs: Span[Float64, ...]
) raises -> List[Float64]:
    if len(llrs) != 52:
        raise Error("HE/EHT SIGNAL deinterleaver requires 52 LLRs")
    var result = List[Float64](length=52, fill=0.0)
    for source in range(52):
        var destination = 4 * (source % 13) + source // 13
        result[source] = llrs[destination]
    return result^


struct _DecodedSignalWaveform(Movable):
    var spectra: List[Complex64]
    var channel_estimates: List[Complex64]
    var equalized_data_symbols: List[Complex64]
    var coded_llrs: List[Float64]
    var hard_coded_bits: List[UInt8]
    var decoded_bits: List[UInt8]
    var repetition_disagreements: Int

    def __init__(
        out self,
        var spectra: List[Complex64],
        var channel_estimates: List[Complex64],
        var equalized_data_symbols: List[Complex64],
        var coded_llrs: List[Float64],
        var hard_coded_bits: List[UInt8],
        var decoded_bits: List[UInt8],
        repetition_disagreements: Int,
    ):
        self.spectra = spectra^
        self.channel_estimates = channel_estimates^
        self.equalized_data_symbols = equalized_data_symbols^
        self.coded_llrs = coded_llrs^
        self.hard_coded_bits = hard_coded_bits^
        self.decoded_bits = decoded_bits^
        self.repetition_disagreements = repetition_disagreements


def _decode_signal_waveform(
    samples: Span[Complex64, ...],
    family: Int,
    mode: Int,
    pilot_start: Int,
) raises -> _DecodedSignalWaveform:
    var symbol_count = 4 if mode == _SIGNAL_MODE_HE_ER else 2
    if (
        mode != _SIGNAL_MODE_ORDINARY
        and mode != _SIGNAL_MODE_HE_ER
        and mode != _SIGNAL_MODE_EHT_SIG
    ):
        raise Error("unknown HE/EHT SIGNAL receive mode")
    if len(samples) != symbol_count * 80:
        raise Error("HE/EHT SIGNAL waveform has an invalid sample length")
    if family != WIFI_PHY_HE and family != WIFI_PHY_EHT:
        raise Error("HE/EHT SIGNAL waveform has an unknown PHY family")
    var spectra = List[Complex64](capacity=symbol_count * 64)
    var channels = List[Complex64](capacity=symbol_count)
    var equalized_data = List[Complex64](capacity=symbol_count * 52)
    var coded_llrs = List[Float64](length=104, fill=0.0)
    var primary_hard = List[UInt8](length=104, fill=UInt8(0))
    var repeat_hard = List[UInt8](length=104, fill=UInt8(0))
    var repeat_present = List[Bool](length=104, fill=False)
    var data_indices = _data_subcarriers()
    for emitted_symbol in range(symbol_count):
        var normalized = _normalized_symbol(samples, emitted_symbol * 80)
        var spectrum = ofdm_demodulate(
            Span(normalized), 64, WIFI_HE_EHT_SIG_WAVEFORM_CP_SAMPLES
        )
        for value in spectrum:
            spectra.append(value)
        var channel = _estimate_common_channel(
            Span(spectrum), pilot_start + emitted_symbol
        )
        channels.append(channel)
        var symbol_llrs = List[Float64](capacity=52)
        for tone in range(52):
            var equalized = complex_divide(
                spectrum[_fft_bin(data_indices[tone])], channel
            )
            if mode == _SIGNAL_MODE_EHT_SIG and tone >= 26 and tone % 2 != 0:
                equalized = -equalized
            if not isfinite(equalized.re) or not isfinite(equalized.im):
                raise Error("HE/EHT SIGNAL equalized data must be finite")
            equalized_data.append(equalized)
            var llr = equalized.re
            if mode == _SIGNAL_MODE_HE_ER and emitted_symbol == 1:
                llr = equalized.im
            symbol_llrs.append(llr)
        var source_symbol = emitted_symbol
        var interleaved = True
        if mode == _SIGNAL_MODE_HE_ER:
            source_symbol = emitted_symbol // 2
            interleaved = emitted_symbol == 0 or emitted_symbol == 2
        var source_llrs = symbol_llrs^
        if interleaved:
            source_llrs = _deinterleave_signal_llrs(Span(source_llrs))
        for index in range(52):
            var position = source_symbol * 52 + index
            coded_llrs[position] += source_llrs[index]
            var hard = UInt8(0 if source_llrs[index] >= 0.0 else 1)
            if interleaved:
                primary_hard[position] = hard
            else:
                repeat_hard[position] = hard
                repeat_present[position] = True
    var disagreements = 0
    for index in range(104):
        if repeat_present[index] and primary_hard[index] != repeat_hard[index]:
            disagreements += 1
    var hard_coded = List[UInt8](capacity=104)
    for llr in coded_llrs:
        hard_coded.append(UInt8(0 if llr >= 0.0 else 1))
    var generators: List[Int] = [0o133, 0o171]
    var decoded = viterbi_decode_soft(
        Span(coded_llrs), Span(generators), 7, terminate=False
    )
    if len(decoded) != 52:
        raise Error("internal HE/EHT SIGNAL Viterbi length mismatch")
    return _DecodedSignalWaveform(
        spectra^,
        channels^,
        equalized_data^,
        coded_llrs^,
        hard_coded^,
        decoded^,
        disagreements,
    )


def _tx_metadata(
    testcase_id: StringSlice,
    bits: Int,
    coded_bits: Int,
    transmitted_bits: Int,
    data_symbols: Int,
    spectra: Int,
    waveform: Int,
) raises -> List[CheckpointMetadata]:
    var result = List[CheckpointMetadata](capacity=6)
    for stage, length in [
        ("bits", bits),
        ("coded-bits", coded_bits),
        ("transmitted-bits", transmitted_bits),
    ]:
        result.append(
            checkpoint_metadata_1d(
                testcase_id,
                stage,
                "uint8",
                length,
                q_format="binary-u1",
                layout="bit-per-byte",
            )
        )
    for stage, length in [
        ("data-symbols", data_symbols),
        ("spectra", spectra),
        ("waveform", waveform),
    ]:
        result.append(
            checkpoint_metadata_1d(
                testcase_id,
                stage,
                "complex64",
                length,
                layout="iq-interleaved",
            )
        )
    return result^


def _rx_metadata(
    testcase_id: StringSlice,
    waveform: Int,
    spectra: Int,
    channel_estimates: Int,
    equalized_data_symbols: Int,
    coded_llrs: Int,
    hard_coded_bits: Int,
    decoded_bits: Int,
) raises -> List[CheckpointMetadata]:
    var result = List[CheckpointMetadata](capacity=7)
    for stage, length in [
        ("waveform", waveform),
        ("spectra", spectra),
        ("channel-estimates", channel_estimates),
        ("equalized-data-symbols", equalized_data_symbols),
    ]:
        result.append(
            checkpoint_metadata_1d(
                testcase_id,
                stage,
                "complex64",
                length,
                layout="iq-interleaved",
            )
        )
    result.append(
        checkpoint_metadata_1d(
            testcase_id,
            "coded-llrs",
            "float64",
            coded_llrs,
            layout="contiguous",
        )
    )
    for stage, length in [
        ("hard-coded-bits", hard_coded_bits),
        ("decoded-bits", decoded_bits),
    ]:
        result.append(
            checkpoint_metadata_1d(
                testcase_id,
                stage,
                "uint8",
                length,
                q_format="binary-u1",
                layout="bit-per-byte",
            )
        )
    return result^


struct WifiHeSigAWaveformTx20MHz(Movable):
    """HE-SIG-A transmit waveform and real intermediate checkpoints."""

    var extended_range: Bool
    var bits: List[UInt8]
    var coded_bits: List[UInt8]
    var transmitted_bits: List[UInt8]
    var data_symbols: List[Complex64]
    var spectra: List[Complex64]
    var waveform: List[Complex64]
    var data_profile: WifiSignalDataProfile
    var checkpoint_metadata: List[CheckpointMetadata]

    def __init__(
        out self,
        extended_range: Bool,
        var encoded: _EncodedSignalWaveform,
        data_profile: WifiSignalDataProfile,
        var checkpoint_metadata: List[CheckpointMetadata],
    ):
        self.extended_range = extended_range
        self.bits = encoded.bits.copy()
        self.coded_bits = encoded.coded_bits.copy()
        self.transmitted_bits = encoded.transmitted_bits.copy()
        self.data_symbols = encoded.data_symbols.copy()
        self.spectra = encoded.spectra.copy()
        self.waveform = encoded.waveform.copy()
        self.data_profile = data_profile
        self.checkpoint_metadata = checkpoint_metadata^


def wifi_he_sig_a_waveform_tx_20mhz(
    config: WifiHeSigASUConfig,
    *,
    testcase_id: StringSlice = "wifi-he-sig-a-waveform-tx-20mhz",
) raises -> WifiHeSigAWaveformTx20MHz:
    """Encode and modulate bounded one-stream 20 MHz HE SU/ER-SU HE-SIG-A."""
    var bits = wifi_he_sig_a_su_pack(config)
    var fields = wifi_he_sig_a_su_parse(
        Span(bits), extended_range=config.extended_range
    )
    var profile = _he_data_profile(fields)
    var mode = (
        _SIGNAL_MODE_HE_ER if config.extended_range else _SIGNAL_MODE_ORDINARY
    )
    var encoded = _encode_signal_waveform(
        Span(bits), WIFI_PHY_HE, mode, 2
    )
    var metadata = _tx_metadata(
        testcase_id,
        len(encoded.bits),
        len(encoded.coded_bits),
        len(encoded.transmitted_bits),
        len(encoded.data_symbols),
        len(encoded.spectra),
        len(encoded.waveform),
    )
    return WifiHeSigAWaveformTx20MHz(
        config.extended_range, encoded^, profile, metadata^
    )


struct WifiHeSigAWaveformRx20MHz(Movable):
    """Decoded HE-SIG-A waveform, profile, and receive checkpoints."""

    var fields: WifiHeSigASUFields
    var data_profile: WifiSignalDataProfile
    var spectra: List[Complex64]
    var channel_estimates: List[Complex64]
    var equalized_data_symbols: List[Complex64]
    var coded_llrs: List[Float64]
    var hard_coded_bits: List[UInt8]
    var decoded_bits: List[UInt8]
    var repetition_disagreements: Int
    var checkpoint_metadata: List[CheckpointMetadata]

    def __init__(
        out self,
        fields: WifiHeSigASUFields,
        data_profile: WifiSignalDataProfile,
        var decoded: _DecodedSignalWaveform,
        var checkpoint_metadata: List[CheckpointMetadata],
    ):
        self.fields = fields
        self.data_profile = data_profile
        self.spectra = decoded.spectra.copy()
        self.channel_estimates = decoded.channel_estimates.copy()
        self.equalized_data_symbols = decoded.equalized_data_symbols.copy()
        self.coded_llrs = decoded.coded_llrs.copy()
        self.hard_coded_bits = decoded.hard_coded_bits.copy()
        self.decoded_bits = decoded.decoded_bits.copy()
        self.repetition_disagreements = decoded.repetition_disagreements
        self.checkpoint_metadata = checkpoint_metadata^


def wifi_he_sig_a_waveform_rx_20mhz(
    samples: Span[Complex64, ...],
    *,
    extended_range: Bool = False,
    testcase_id: StringSlice = "wifi-he-sig-a-waveform-rx-20mhz",
) raises -> WifiHeSigAWaveformRx20MHz:
    """Extract, soft-decode, CRC-check, and profile HE SU/ER-SU HE-SIG-A."""
    var mode = _SIGNAL_MODE_HE_ER if extended_range else _SIGNAL_MODE_ORDINARY
    var decoded = _decode_signal_waveform(
        samples, WIFI_PHY_HE, mode, 2
    )
    var fields = wifi_he_sig_a_su_parse(
        Span(decoded.decoded_bits), extended_range=extended_range
    )
    var profile = _he_data_profile(fields)
    var metadata = _rx_metadata(
        testcase_id,
        len(samples),
        len(decoded.spectra),
        len(decoded.channel_estimates),
        len(decoded.equalized_data_symbols),
        len(decoded.coded_llrs),
        len(decoded.hard_coded_bits),
        len(decoded.decoded_bits),
    )
    return WifiHeSigAWaveformRx20MHz(
        fields, profile, decoded^, metadata^
    )


struct WifiEhtUSigWaveformTx20MHz(Movable):
    """EHT U-SIG waveform and retained transmit checkpoints."""

    var bits: List[UInt8]
    var coded_bits: List[UInt8]
    var transmitted_bits: List[UInt8]
    var data_symbols: List[Complex64]
    var spectra: List[Complex64]
    var waveform: List[Complex64]
    var checkpoint_metadata: List[CheckpointMetadata]

    def __init__(
        out self,
        var encoded: _EncodedSignalWaveform,
        var checkpoint_metadata: List[CheckpointMetadata],
    ):
        self.bits = encoded.bits.copy()
        self.coded_bits = encoded.coded_bits.copy()
        self.transmitted_bits = encoded.transmitted_bits.copy()
        self.data_symbols = encoded.data_symbols.copy()
        self.spectra = encoded.spectra.copy()
        self.waveform = encoded.waveform.copy()
        self.checkpoint_metadata = checkpoint_metadata^


def wifi_eht_u_sig_waveform_tx_20mhz(
    config: WifiEhtUSigSU20Config,
    *,
    testcase_id: StringSlice = "wifi-eht-u-sig-waveform-tx-20mhz",
) raises -> WifiEhtUSigWaveformTx20MHz:
    """Encode and modulate the two-symbol nonpunctured 20 MHz EHT U-SIG."""
    var bits = wifi_eht_u_sig_su_20_pack(config)
    var encoded = _encode_signal_waveform(
        Span(bits), WIFI_PHY_EHT, _SIGNAL_MODE_ORDINARY, 2
    )
    var metadata = _tx_metadata(
        testcase_id,
        len(encoded.bits),
        len(encoded.coded_bits),
        len(encoded.transmitted_bits),
        len(encoded.data_symbols),
        len(encoded.spectra),
        len(encoded.waveform),
    )
    return WifiEhtUSigWaveformTx20MHz(encoded^, metadata^)


struct WifiEhtUSigWaveformRx20MHz(Movable):
    """Decoded U-SIG plus explicit caller-provided SU/NDP acquisition context."""

    var acquisition_context: Int
    var fields: WifiEhtUSigSU20Fields
    var spectra: List[Complex64]
    var channel_estimates: List[Complex64]
    var equalized_data_symbols: List[Complex64]
    var coded_llrs: List[Float64]
    var hard_coded_bits: List[UInt8]
    var decoded_bits: List[UInt8]
    var checkpoint_metadata: List[CheckpointMetadata]

    def __init__(
        out self,
        acquisition_context: Int,
        fields: WifiEhtUSigSU20Fields,
        var decoded: _DecodedSignalWaveform,
        var checkpoint_metadata: List[CheckpointMetadata],
    ):
        self.acquisition_context = acquisition_context
        self.fields = fields
        self.spectra = decoded.spectra.copy()
        self.channel_estimates = decoded.channel_estimates.copy()
        self.equalized_data_symbols = decoded.equalized_data_symbols.copy()
        self.coded_llrs = decoded.coded_llrs.copy()
        self.hard_coded_bits = decoded.hard_coded_bits.copy()
        self.decoded_bits = decoded.decoded_bits.copy()
        self.checkpoint_metadata = checkpoint_metadata^


def wifi_eht_u_sig_waveform_rx_20mhz(
    samples: Span[Complex64, ...],
    acquisition_context: Int,
    *,
    testcase_id: StringSlice = "wifi-eht-u-sig-waveform-rx-20mhz",
) raises -> WifiEhtUSigWaveformRx20MHz:
    """Decode U-SIG while retaining the independent SU/sounding-NDP context."""
    _validate_context(acquisition_context)
    var decoded = _decode_signal_waveform(
        samples, WIFI_PHY_EHT, _SIGNAL_MODE_ORDINARY, 2
    )
    var fields = wifi_eht_u_sig_su_20_parse(Span(decoded.decoded_bits))
    var metadata = _rx_metadata(
        testcase_id,
        len(samples),
        len(decoded.spectra),
        len(decoded.channel_estimates),
        len(decoded.equalized_data_symbols),
        len(decoded.coded_llrs),
        len(decoded.hard_coded_bits),
        len(decoded.decoded_bits),
    )
    return WifiEhtUSigWaveformRx20MHz(
        acquisition_context, fields, decoded^, metadata^
    )


struct WifiEhtSUSignalTx20MHz(Movable):
    """U-SIG plus EHT-SIG transmit slice and decoded DATA contract."""

    var u_sig: WifiEhtUSigWaveformTx20MHz
    var eht_sig_bits: List[UInt8]
    var eht_sig_coded_bits: List[UInt8]
    var eht_sig_transmitted_bits: List[UInt8]
    var eht_sig_data_symbols: List[Complex64]
    var eht_sig_spectra: List[Complex64]
    var eht_sig_waveform: List[Complex64]
    var waveform: List[Complex64]
    var data_profile: WifiSignalDataProfile
    var checkpoint_metadata: List[CheckpointMetadata]

    def __init__(
        out self,
        var u_sig: WifiEhtUSigWaveformTx20MHz,
        var eht_sig: _EncodedSignalWaveform,
        var waveform: List[Complex64],
        data_profile: WifiSignalDataProfile,
        var checkpoint_metadata: List[CheckpointMetadata],
    ):
        self.u_sig = u_sig^
        self.eht_sig_bits = eht_sig.bits.copy()
        self.eht_sig_coded_bits = eht_sig.coded_bits.copy()
        self.eht_sig_transmitted_bits = eht_sig.transmitted_bits.copy()
        self.eht_sig_data_symbols = eht_sig.data_symbols.copy()
        self.eht_sig_spectra = eht_sig.spectra.copy()
        self.eht_sig_waveform = eht_sig.waveform.copy()
        self.waveform = waveform^
        self.data_profile = data_profile
        self.checkpoint_metadata = checkpoint_metadata^


def wifi_eht_su_signal_tx_20mhz(
    u_sig_config: WifiEhtUSigSU20Config,
    eht_sig_config: WifiEhtSigSU20Config,
    *,
    testcase_id: StringSlice = "wifi-eht-su-signal-tx-20mhz",
) raises -> WifiEhtSUSignalTx20MHz:
    """Build U-SIG then a two-symbol MCS-0 EHT-SIG from one SU profile."""
    if (
        u_sig_config.eht_sig_mcs_code != 0
        or u_sig_config.eht_sig_symbols != 2
    ):
        raise Error("bounded EHT SU signal requires EHT-SIG MCS code 0 and two symbols")
    var profile = _validate_eht_sig_su_20_config(eht_sig_config)
    var u_sig = wifi_eht_u_sig_waveform_tx_20mhz(
        u_sig_config, testcase_id="eht-su-u-sig-tx"
    )
    var eht_bits = wifi_eht_sig_su_20_pack(eht_sig_config)
    var eht_sig = _encode_signal_waveform(
        Span(eht_bits), WIFI_PHY_EHT, _SIGNAL_MODE_EHT_SIG, 4
    )
    var waveform = List[Complex64](
        capacity=len(u_sig.waveform) + len(eht_sig.waveform)
    )
    for value in u_sig.waveform:
        waveform.append(value)
    for value in eht_sig.waveform:
        waveform.append(value)
    var metadata = List[CheckpointMetadata](capacity=1)
    metadata.append(
        checkpoint_metadata_1d(
            testcase_id,
            "u-sig-plus-eht-sig-waveform",
            "complex64",
            len(waveform),
            layout="iq-interleaved",
        )
    )
    return WifiEhtSUSignalTx20MHz(
        u_sig^, eht_sig^, waveform^, profile, metadata^
    )


struct WifiEhtSUSignalRx20MHz(Movable):
    """U-SIG-driven EHT-SIG decode and EHT DATA profile."""

    var u_sig: WifiEhtUSigWaveformRx20MHz
    var eht_sig_fields: WifiEhtSigSU20Fields
    var eht_sig_spectra: List[Complex64]
    var eht_sig_channel_estimates: List[Complex64]
    var eht_sig_equalized_data_symbols: List[Complex64]
    var eht_sig_coded_llrs: List[Float64]
    var eht_sig_hard_coded_bits: List[UInt8]
    var eht_sig_decoded_bits: List[UInt8]
    var data_profile: WifiSignalDataProfile
    var checkpoint_metadata: List[CheckpointMetadata]

    def __init__(
        out self,
        var u_sig: WifiEhtUSigWaveformRx20MHz,
        eht_sig_fields: WifiEhtSigSU20Fields,
        var eht_sig: _DecodedSignalWaveform,
        data_profile: WifiSignalDataProfile,
        var checkpoint_metadata: List[CheckpointMetadata],
    ):
        self.u_sig = u_sig^
        self.eht_sig_fields = eht_sig_fields
        self.eht_sig_spectra = eht_sig.spectra.copy()
        self.eht_sig_channel_estimates = eht_sig.channel_estimates.copy()
        self.eht_sig_equalized_data_symbols = eht_sig.equalized_data_symbols.copy()
        self.eht_sig_coded_llrs = eht_sig.coded_llrs.copy()
        self.eht_sig_hard_coded_bits = eht_sig.hard_coded_bits.copy()
        self.eht_sig_decoded_bits = eht_sig.decoded_bits.copy()
        self.data_profile = data_profile
        self.checkpoint_metadata = checkpoint_metadata^


def wifi_eht_su_signal_rx_20mhz(
    samples: Span[Complex64, ...],
    acquisition_context: Int,
    *,
    testcase_id: StringSlice = "wifi-eht-su-signal-rx-20mhz",
) raises -> WifiEhtSUSignalRx20MHz:
    """Let decoded U-SIG geometry drive EHT-SIG and DATA-profile decoding."""
    _validate_context(acquisition_context)
    if len(samples) < WIFI_EHT_U_SIG_WAVEFORM_SAMPLES:
        raise Error("EHT SU SIGNAL slice is shorter than U-SIG")
    var u_sig = wifi_eht_u_sig_waveform_rx_20mhz(
        samples[0:WIFI_EHT_U_SIG_WAVEFORM_SAMPLES],
        acquisition_context,
        testcase_id="eht-su-u-sig-rx",
    )
    if acquisition_context == WIFI_EHT_ACQUISITION_SOUNDING_NDP:
        raise Error("sounding-NDP context cannot be interpreted as an EHT SU DATA PPDU")
    # These values are decoded from U-SIG, not supplied again by the caller.
    if u_sig.fields.eht_sig_mcs_code != 0:
        raise Error("bounded EHT-SIG receiver supports only MCS code 0")
    if u_sig.fields.eht_sig_symbols != 2:
        raise Error("bounded EHT-SIG receiver requires two decoded symbols")
    var expected_samples = (
        WIFI_EHT_U_SIG_WAVEFORM_SAMPLES
        + u_sig.fields.eht_sig_symbols * WIFI_HE_EHT_SIG_WAVEFORM_SYMBOL_SAMPLES
    )
    if len(samples) != expected_samples:
        raise Error("EHT-SIG sample length disagrees with decoded U-SIG geometry")
    var eht_sig = _decode_signal_waveform(
        samples[WIFI_EHT_U_SIG_WAVEFORM_SAMPLES:expected_samples],
        WIFI_PHY_EHT,
        _SIGNAL_MODE_EHT_SIG,
        4,
    )
    var fields = wifi_eht_sig_su_20_parse(Span(eht_sig.decoded_bits))
    var config = WifiEhtSigSU20Config(
        fields.mcs_index,
        sta_id=fields.sta_id,
        spatial_reuse=fields.spatial_reuse,
        gi_ltf_code=fields.gi_ltf_code,
        eht_ltf_symbols=fields.eht_ltf_symbols,
        ldpc_extra_symbol=fields.ldpc_extra_symbol,
        pre_fec_padding_factor=fields.pre_fec_padding_factor,
        pe_disambiguity=fields.pe_disambiguity,
        spatial_streams=fields.spatial_streams,
        beamformed=fields.beamformed,
        coding=fields.coding,
    )
    var profile = _validate_eht_sig_su_20_config(config)
    var metadata = List[CheckpointMetadata](capacity=1)
    metadata.append(
        checkpoint_metadata_1d(
            testcase_id,
            "u-sig-driven-eht-sig-waveform",
            "complex64",
            len(samples),
            layout="iq-interleaved",
        )
    )
    return WifiEhtSUSignalRx20MHz(
        u_sig^, fields, eht_sig^, profile, metadata^
    )


struct WifiHeSignalDrivenLDPCRx20MHz(Movable):
    """HE-SIG-A decode followed by DATA RX using its decoded profile."""

    var signal: WifiHeSigAWaveformRx20MHz
    var data: WifiLDPCRx20MHz

    def __init__(
        out self,
        var signal: WifiHeSigAWaveformRx20MHz,
        var data: WifiLDPCRx20MHz,
    ):
        self.signal = signal^
        self.data = data^


def wifi_he_signal_driven_ldpc_rx_20mhz(
    signal_samples: Span[Complex64, ...],
    data_samples: Span[Complex64, ...],
    ltf_samples: Span[Complex64, ...],
    payload_bit_count: Int,
    noise_variance: Float64,
    *,
    scrambler_seed: UInt8 = UInt8(0x5D),
    data_symbol_index: Int = 0,
    testcase_id: StringSlice = "wifi-he-signal-driven-ldpc-rx-20mhz",
) raises -> WifiHeSignalDrivenLDPCRx20MHz:
    """Decode HE-SIG-A, then use its family/MCS/coding to receive DATA."""
    var signal = wifi_he_sig_a_waveform_rx_20mhz(
        signal_samples, testcase_id="signal-driven-he-sig-a-rx"
    )
    if (
        signal.data_profile.coding != WIFI_HE_EHT_SIG_CODING_LDPC
        or signal.data_profile.mcs_index != 10
    ):
        raise Error("bounded HE LDPC DATA chain requires decoded MCS 10/LDPC")
    var data = wifi_ldpc_rx_20mhz(
        data_samples,
        ltf_samples,
        signal.data_profile.family,
        signal.data_profile.mcs_index,
        payload_bit_count,
        noise_variance,
        scrambler_seed=scrambler_seed,
        symbol_index=data_symbol_index,
        testcase_id=testcase_id,
    )
    return WifiHeSignalDrivenLDPCRx20MHz(signal^, data^)


struct WifiEhtSignalDrivenLDPCRx20MHz(Movable):
    """U-SIG/EHT-SIG decode followed by DATA RX using decoded fields."""

    var signal: WifiEhtSUSignalRx20MHz
    var data: WifiLDPCRx20MHz

    def __init__(
        out self,
        var signal: WifiEhtSUSignalRx20MHz,
        var data: WifiLDPCRx20MHz,
    ):
        self.signal = signal^
        self.data = data^


def wifi_eht_signal_driven_ldpc_rx_20mhz(
    signal_samples: Span[Complex64, ...],
    data_samples: Span[Complex64, ...],
    ltf_samples: Span[Complex64, ...],
    payload_bit_count: Int,
    noise_variance: Float64,
    acquisition_context: Int,
    *,
    scrambler_seed: UInt8 = UInt8(0x5D),
    data_symbol_index: Int = 0,
    testcase_id: StringSlice = "wifi-eht-signal-driven-ldpc-rx-20mhz",
) raises -> WifiEhtSignalDrivenLDPCRx20MHz:
    """Decode U/EHT-SIG, then use decoded family/MCS/coding for DATA RX."""
    var signal = wifi_eht_su_signal_rx_20mhz(
        signal_samples,
        acquisition_context,
        testcase_id="signal-driven-eht-signal-rx",
    )
    if (
        signal.data_profile.coding != WIFI_HE_EHT_SIG_CODING_LDPC
        or signal.data_profile.mcs_index != 13
    ):
        raise Error("bounded EHT LDPC DATA chain requires decoded MCS 13/LDPC")
    var data = wifi_ldpc_rx_20mhz(
        data_samples,
        ltf_samples,
        signal.data_profile.family,
        signal.data_profile.mcs_index,
        payload_bit_count,
        noise_variance,
        scrambler_seed=scrambler_seed,
        symbol_index=data_symbol_index,
        testcase_id=testcase_id,
    )
    return WifiEhtSignalDrivenLDPCRx20MHz(signal^, data^)
