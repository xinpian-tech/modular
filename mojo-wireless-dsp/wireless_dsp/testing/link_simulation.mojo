"""Deterministic CPU link-level Monte-Carlo reference execution."""

from std.math import isfinite
from wireless_dsp.core import Span
from wireless_dsp.modem import (
    qam_map, qam_demapper_llr_maxlog, qam_demapper_llr_piecewise,
    hard_bits_from_llr,
)
from wireless_dsp.channel import add_awgn
from wireless_dsp.channel.impairments import _add_awgn_with_fingerprint
from wireless_dsp.fec import convolutional_encode, viterbi_decode_hard
from wireless_dsp.wireless.wifi import (
    wifi_scramble, wifi_interleave, wifi_deinterleave,
    wifi_map_legacy_symbol, wifi_extract_legacy_symbol,
)


# Non-normative resource ceilings for these deterministic CPU reference
# simulations.  They bound allocation and loop work; they are not limits from
# a radio specification.
comptime _MAX_QAM_LINK_BITS = 131072
comptime _MAX_QAM_SWEEP_POINTS = 1024
comptime _MAX_QAM_SWEEP_SYMBOLS = 131072
comptime _MAX_WIFI_LEGACY_PACKETS = 512
comptime _TRACE_FNV1A64_OFFSET = UInt64(14695981039346656037)
comptime _TRACE_FNV1A64_PRIME = UInt64(1099511628211)


def _trace_fnv1a_byte(mut checksum: UInt64, value: UInt8):
    checksum ^= UInt64(value)
    checksum *= _TRACE_FNV1A64_PRIME


def _trace_fnv1a_bits(mut checksum: UInt64, values: Span[UInt8, ...]):
    for index in range(len(values)):
        _trace_fnv1a_byte(checksum, values[index])


def _trace_fnv1a_int64_be(mut checksum: UInt64, value: Int):
    var word = UInt64(value)
    for byte_index in range(8):
        var shift = UInt64(56 - 8 * byte_index)
        _trace_fnv1a_byte(
            checksum, UInt8((word >> shift) & UInt64(0xFF))
        )


struct LinkResult(ImplicitlyCopyable):
    var bit_count: Int
    var bit_errors: Int
    var ber: Float64

    def __init__(out self, bit_count: Int, bit_errors: Int):
        self.bit_count = bit_count
        self.bit_errors = bit_errors
        self.ber = Float64(bit_errors) / Float64(bit_count) if bit_count > 0 else 0.0


struct PacketLinkResult(ImplicitlyCopyable):
    """Aggregate packet result plus non-normative regression diagnostics.

    ``noise_fingerprint`` is FNV-1a64 over signed big-endian Q12 samples from
    the actual production-path AWGN stream. ``discrete_fingerprint`` is an
    independent FNV-1a64 transcript of retained discrete link stages. These
    diagnostics are deterministic bug detectors, not cryptographic digests
    or radio-standard fields.
    """
    var bit_count: Int
    var bit_errors: Int
    var packet_count: Int
    var packet_errors: Int
    var ber: Float64
    var per: Float64
    var bler: Float64
    var noise_fingerprint: UInt64
    var discrete_fingerprint: UInt64

    def __init__(
        out self, bit_count: Int, bit_errors: Int,
        packet_count: Int, packet_errors: Int,
        noise_fingerprint: UInt64 = UInt64(0),
        discrete_fingerprint: UInt64 = UInt64(0),
    ):
        self.bit_count = bit_count
        self.bit_errors = bit_errors
        self.packet_count = packet_count
        self.packet_errors = packet_errors
        self.ber = Float64(bit_errors) / Float64(bit_count) if bit_count > 0 else 0.0
        self.per = Float64(packet_errors) / Float64(packet_count) if packet_count > 0 else 0.0
        self.bler = self.per
        self.noise_fingerprint = noise_fingerprint
        self.discrete_fingerprint = discrete_fingerprint


struct QAMLinkSweepPoint(ImplicitlyCopyable):
    """One deterministic modulation/noise/seed point in a Cartesian sweep."""

    var bits_per_symbol: Int
    var noise_variance: Float64
    var seed: UInt64
    var result: LinkResult

    def __init__(
        out self,
        bits_per_symbol: Int,
        noise_variance: Float64,
        seed: UInt64,
        result: LinkResult,
    ):
        self.bits_per_symbol = bits_per_symbol
        self.noise_variance = noise_variance
        self.seed = seed
        self.result = result


def _next_bit(mut state: UInt64) -> UInt8:
    state = state * UInt64(6364136223846793005) + UInt64(1442695040888963407)
    return UInt8((state >> 63) & 1)


def _supported_modulation(bits_per_symbol: Int) -> Bool:
    return (
        bits_per_symbol == 1
        or bits_per_symbol == 2
        or bits_per_symbol == 4
        or bits_per_symbol == 6
        or bits_per_symbol == 8
        or bits_per_symbol == 10
        or bits_per_symbol == 12
    )


def simulate_qam_awgn(
    bits_per_symbol: Int, symbol_count: Int, noise_variance: Float64, *, seed: UInt64
) raises -> LinkResult:
    """Run a deterministic scalar QAM/AWGN reference, up to 131072 bits."""
    if not _supported_modulation(bits_per_symbol):
        raise Error("link simulation modulation order is unsupported")
    if (
        symbol_count < 1
        or symbol_count > Int.MAX // bits_per_symbol
        or symbol_count > _MAX_QAM_LINK_BITS // bits_per_symbol
    ):
        raise Error("link simulation symbol or bit count is invalid")
    if not isfinite(noise_variance) or noise_variance < 0.0:
        raise Error("link simulation noise variance must be finite/non-negative")
    var bit_count = symbol_count * bits_per_symbol
    var bit_seed = seed ^ UInt64(0xD1B54A32D192ED03)
    var bits = List[UInt8](capacity=bit_count)
    for _ in range(bit_count):
        bits.append(_next_bit(bit_seed))
    var symbols = qam_map(Span(bits), bits_per_symbol)
    var received = add_awgn(Span(symbols), noise_variance, seed=seed)
    var llrs = qam_demapper_llr_piecewise(
        Span(received), bits_per_symbol, max(noise_variance, 1.0e-15)
    )
    var recovered = hard_bits_from_llr(Span(llrs))
    var errors = 0
    for i in range(len(bits)):
        if bits[i] != recovered[i]:
            errors += 1
    return LinkResult(len(bits), errors)


def simulate_qam_awgn_sweep(
    modulation_orders: Span[Int, ...],
    noise_variances: Span[Float64, ...],
    seeds: Span[UInt64, ...],
    symbols_per_point: Int,
) raises -> List[QAMLinkSweepPoint]:
    """Run a stable MCS/noise/seed Cartesian sweep for backend comparison.

    Points are ordered modulation-major, then noise-major, then seed-major.
    This CPU Float64 path is the deterministic oracle for a batched GPU
    implementation; every point regenerates bits from its explicit seed.
    """
    if (
        len(modulation_orders) == 0
        or len(noise_variances) == 0
        or len(seeds) == 0
        or symbols_per_point < 1
    ):
        raise Error("QAM link sweep axes and symbol count must be non-empty")
    for noise_index in range(len(noise_variances)):
        if (
            not isfinite(noise_variances[noise_index])
            or noise_variances[noise_index] < 0.0
        ):
            raise Error("QAM link sweep noise variance must be finite/non-negative")
    for modulation_index in range(len(modulation_orders)):
        if not _supported_modulation(modulation_orders[modulation_index]):
            raise Error("QAM link sweep modulation order is unsupported")
        if symbols_per_point > Int.MAX // modulation_orders[modulation_index]:
            raise Error("QAM link sweep bit count is unrepresentable")
    if len(modulation_orders) > Int.MAX // len(noise_variances):
        raise Error("QAM link sweep point count is unrepresentable")
    var modulation_noise_points = (
        len(modulation_orders) * len(noise_variances)
    )
    if modulation_noise_points > Int.MAX // len(seeds):
        raise Error("QAM link sweep point count is unrepresentable")
    var point_count = modulation_noise_points * len(seeds)
    if (
        point_count > _MAX_QAM_SWEEP_POINTS
        or symbols_per_point > _MAX_QAM_SWEEP_SYMBOLS // point_count
    ):
        raise Error("QAM link sweep exceeds the CPU reference capacity")
    var points = List[QAMLinkSweepPoint](
        capacity=point_count
    )
    for modulation_index in range(len(modulation_orders)):
        for noise_index in range(len(noise_variances)):
            for seed_index in range(len(seeds)):
                var result = simulate_qam_awgn(
                    modulation_orders[modulation_index],
                    symbols_per_point,
                    noise_variances[noise_index],
                    seed=seeds[seed_index],
                )
                points.append(
                    QAMLinkSweepPoint(
                        modulation_orders[modulation_index],
                        noise_variances[noise_index],
                        seeds[seed_index],
                        result,
                    )
                )
    return points^


def simulate_wifi_legacy_bpsk_awgn(
    packet_count: Int, noise_variance: Float64, *, seed: UInt64
) raises -> PacketLinkResult:
    """Run at most 512 legacy packets through the CPU reference chain."""
    if (
        packet_count < 1
        or packet_count > Int.MAX // 18
        or packet_count > _MAX_WIFI_LEGACY_PACKETS
    ):
        raise Error("Wi-Fi link simulation packet count is invalid")
    if not isfinite(noise_variance) or noise_variance < 0.0:
        raise Error("Wi-Fi link noise variance must be finite/non-negative")
    var bit_state = seed ^ UInt64(0x94D049BB133111EB)
    var generators: List[Int] = [0o133, 0o171]
    var total_errors = 0
    var failed_packets = 0
    var noise_fingerprint = _TRACE_FNV1A64_OFFSET
    var discrete_fingerprint = _TRACE_FNV1A64_OFFSET
    for packet in range(packet_count):
        var payload = List[UInt8](capacity=18)
        for _ in range(18):
            payload.append(_next_bit(bit_state))
        var scrambled = wifi_scramble(Span(payload), UInt8(0x5D))
        var coded = convolutional_encode(Span(scrambled), Span(generators), 7)
        var interleaved = wifi_interleave(Span(coded), 1)
        var symbols = qam_map(Span(interleaved), 1)
        var waveform = wifi_map_legacy_symbol(Span(symbols))
        var noisy = _add_awgn_with_fingerprint(
            Span(waveform), noise_variance, noise_fingerprint,
            seed=seed + UInt64(packet) * UInt64(0x9E3779B97F4A7C15),
        )
        var received = wifi_extract_legacy_symbol(Span(noisy))
        var hard = hard_bits_from_llr(
            Span(qam_demapper_llr_maxlog(
                Span(received), 1, max(noise_variance, 1.0e-15)
            ))
        )
        var deinterleaved = wifi_deinterleave(Span(hard), 1)
        var decoded = viterbi_decode_hard(
            Span(deinterleaved), Span(generators), 7
        )
        var recovered = wifi_scramble(Span(decoded), UInt8(0x5D))
        _trace_fnv1a_bits(discrete_fingerprint, Span(payload))
        _trace_fnv1a_bits(discrete_fingerprint, Span(scrambled))
        _trace_fnv1a_bits(discrete_fingerprint, Span(coded))
        _trace_fnv1a_bits(discrete_fingerprint, Span(interleaved))
        _trace_fnv1a_bits(discrete_fingerprint, Span(hard))
        _trace_fnv1a_bits(discrete_fingerprint, Span(deinterleaved))
        _trace_fnv1a_bits(discrete_fingerprint, Span(decoded))
        _trace_fnv1a_bits(discrete_fingerprint, Span(recovered))
        var packet_failed = False
        for i in range(18):
            if recovered[i] != payload[i]:
                total_errors += 1
                packet_failed = True
        if packet_failed:
            failed_packets += 1
    return PacketLinkResult(
        18 * packet_count,
        total_errors,
        packet_count,
        failed_packets,
        noise_fingerprint,
        discrete_fingerprint,
    )
