"""Attributable CPU timings for bounded HT/VHT/HE spatial APIs.

Each public algorithm has its own no-inline batched workload, three untimed
warmups, and nine independent odd samples.  Variable-size owned results use an
O(1) endpoint fingerprint plus ``keep`` so the timed region retains the result
without adding a second O(N) scan.  The benchmark uses the scalar CPU reference
directly; there is no heterogeneous dispatcher, RF path, accelerator,
arbitrary matrix multiply, or bundled timing family.
"""

from std.benchmark import black_box, keep
from std.collections import Span
from std.time import global_perf_counter_ns
from wireless_dsp.benchmarking import (
    print_benchmark_metadata,
    report_timing_samples,
)
from wireless_dsp.core import Complex64
from wireless_dsp.wireless.wifi.profiles import WIFI_PHY_VHT
from wireless_dsp.wireless.wifi.mimo_spatial import (
    WifiMIMOSpatialConfig,
    wifi_mimo_parser_block_bits,
    wifi_mimo_spatial_parse,
    wifi_mimo_spatial_deparse,
    wifi_mimo_cyclic_shift_ns,
    wifi_mimo_direct_csd_map,
    wifi_mimo_direct_csd_unmap,
)


comptime _WARMUPS = 3
comptime _SAMPLES = 9
comptime _TABLE_BATCH = 65_536
comptime _BIT_BATCH = 256
comptime _MAP_BATCH = 256


def _mix(checksum: UInt64, value: Int) -> UInt64:
    return (checksum ^ UInt64(value + 16_777_217)) * UInt64(1099511628211)


def _fingerprint_bits(checksum: UInt64, values: Span[UInt8, ...]) -> UInt64:
    var count = len(values)
    var result = _mix(checksum, count)
    if count == 0:
        return result
    result = _mix(result, Int(values[0]))
    result = _mix(result, Int(values[count // 2]) + count)
    return _mix(result, Int(values[count - 1]) + 2 * count)


def _fingerprint_symbols(
    checksum: UInt64, values: Span[Complex64, ...]
) -> UInt64:
    var count = len(values)
    var result = _mix(checksum, count)
    if count == 0:
        return result
    for index in [0, count // 2, count - 1]:
        var real_code = Int(values[index].re * 1_000_000.0)
        var imag_code = Int(values[index].im * 1_000_000.0)
        result = _mix(result, real_code + 2_000_003 * index)
        result = _mix(result, imag_code + 3_000_017 * index)
    return result


@no_inline
def _parser_block_workload(
    iterations: Int, config: WifiMIMOSpatialConfig
) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for operation in range(iterations):
        var value = wifi_mimo_parser_block_bits(black_box(config))
        checksum = _mix(checksum, value + operation)
    return checksum


@no_inline
def _spatial_parse_workload(
    iterations: Int,
    config: WifiMIMOSpatialConfig,
    bits: Span[UInt8, ...],
) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for operation in range(iterations):
        var parsed = wifi_mimo_spatial_parse(
            black_box(config), black_box(bits)
        )
        checksum = _fingerprint_bits(checksum, Span(parsed))
        checksum = _mix(checksum, operation)
        keep(parsed)
    return checksum


@no_inline
def _spatial_deparse_workload(
    iterations: Int,
    config: WifiMIMOSpatialConfig,
    stream_major_bits: Span[UInt8, ...],
) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for operation in range(iterations):
        var bits = wifi_mimo_spatial_deparse(
            black_box(config), black_box(stream_major_bits)
        )
        checksum = _fingerprint_bits(checksum, Span(bits))
        checksum = _mix(checksum, operation)
        keep(bits)
    return checksum


@no_inline
def _cyclic_shift_workload(
    iterations: Int, config: WifiMIMOSpatialConfig, salt: Int
) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for operation in range(iterations):
        var stream = (operation + salt) & 3
        var shift = wifi_mimo_cyclic_shift_ns(
            black_box(config), black_box(stream)
        )
        checksum = _mix(checksum, shift + stream + operation)
    return checksum


@no_inline
def _direct_map_workload(
    iterations: Int,
    config: WifiMIMOSpatialConfig,
    symbols: Span[Complex64, ...],
    tones: Span[Int, ...],
) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for operation in range(iterations):
        var mapped = wifi_mimo_direct_csd_map(
            black_box(config), black_box(symbols), black_box(tones)
        )
        checksum = _fingerprint_symbols(checksum, Span(mapped))
        checksum = _mix(checksum, operation)
        keep(mapped)
    return checksum


@no_inline
def _direct_unmap_workload(
    iterations: Int,
    config: WifiMIMOSpatialConfig,
    symbols: Span[Complex64, ...],
    tones: Span[Int, ...],
) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for operation in range(iterations):
        var unmapped = wifi_mimo_direct_csd_unmap(
            black_box(config), black_box(symbols), black_box(tones)
        )
        checksum = _fingerprint_symbols(checksum, Span(unmapped))
        checksum = _mix(checksum, operation)
        keep(unmapped)
    return checksum


def _make_bits(length: Int) -> List[UInt8]:
    var result = List[UInt8](capacity=length)
    var state = UInt64(0x80211AC4D494D4F)
    for _ in range(length):
        state = (
            state * UInt64(6364136223846793005)
            + UInt64(1442695040888963407)
        )
        result.append(UInt8((state >> 31) & UInt64(1)))
    return result^


def _make_tones() -> List[Int]:
    var result = List[Int](capacity=52)
    for tone in range(-26, 0):
        result.append(tone)
    for tone in range(1, 27):
        result.append(tone)
    return result^


def _make_symbols(streams: Int, tones: Span[Int, ...]) -> List[Complex64]:
    var result = List[Complex64](capacity=streams * len(tones))
    for stream in range(streams):
        for tone in range(len(tones)):
            var real = Float64(((stream + 1) * 17 + tone * 7) % 31 - 15) / 16.0
            var imag = Float64(((stream + 1) * 11 + tone * 5) % 29 - 14) / 16.0
            result.append(Complex64(real, imag))
    return result^


def main() raises:
    var config = WifiMIMOSpatialConfig(WIFI_PHY_VHT, 4, 8, 64)
    var bits = _make_bits(4 * 4 * 64)
    var bits_span = Span(bits)
    var parsed_bits = wifi_mimo_spatial_parse(config, bits_span)
    var parsed_bits_span = Span(parsed_bits)
    var tones = _make_tones()
    var tones_span = Span(tones)
    var symbols = _make_symbols(4, tones_span)
    var symbols_span = Span(symbols)
    var mapped_symbols = wifi_mimo_direct_csd_map(
        config, symbols_span, tones_span
    )
    var mapped_symbols_span = Span(mapped_symbols)

    for warmup in range(_WARMUPS):
        var salt = 0x11AC2024 + warmup
        keep(_parser_block_workload(_TABLE_BATCH, config))
        keep(_spatial_parse_workload(_BIT_BATCH, config, bits_span))
        keep(
            _spatial_deparse_workload(
                _BIT_BATCH, config, parsed_bits_span
            )
        )
        keep(_cyclic_shift_workload(_TABLE_BATCH, config, salt))
        keep(
            _direct_map_workload(
                _MAP_BATCH, config, symbols_span, tones_span
            )
        )
        keep(
            _direct_unmap_workload(
                _MAP_BATCH, config, mapped_symbols_span, tones_span
            )
        )

    var parser_block_samples = List[UInt64](capacity=_SAMPLES)
    var parse_samples = List[UInt64](capacity=_SAMPLES)
    var deparse_samples = List[UInt64](capacity=_SAMPLES)
    var shift_samples = List[UInt64](capacity=_SAMPLES)
    var map_samples = List[UInt64](capacity=_SAMPLES)
    var unmap_samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for sample in range(_SAMPLES):
        var salt = 0x11AC2024 + sample
        var start = global_perf_counter_ns()
        var parser_block_checksum = _parser_block_workload(
            _TABLE_BATCH, config
        )
        parser_block_samples.append(global_perf_counter_ns() - start)
        checksum = _mix(
            checksum, Int(parser_block_checksum & UInt64(Int.MAX))
        )
        keep(parser_block_checksum)

        start = global_perf_counter_ns()
        var parse_checksum = _spatial_parse_workload(
            _BIT_BATCH, config, bits_span
        )
        parse_samples.append(global_perf_counter_ns() - start)
        checksum = _mix(checksum, Int(parse_checksum & UInt64(Int.MAX)))
        keep(parse_checksum)

        start = global_perf_counter_ns()
        var deparse_checksum = _spatial_deparse_workload(
            _BIT_BATCH, config, parsed_bits_span
        )
        deparse_samples.append(global_perf_counter_ns() - start)
        checksum = _mix(checksum, Int(deparse_checksum & UInt64(Int.MAX)))
        keep(deparse_checksum)

        start = global_perf_counter_ns()
        var shift_checksum = _cyclic_shift_workload(
            _TABLE_BATCH, config, salt
        )
        shift_samples.append(global_perf_counter_ns() - start)
        checksum = _mix(checksum, Int(shift_checksum & UInt64(Int.MAX)))
        keep(shift_checksum)

        start = global_perf_counter_ns()
        var map_checksum = _direct_map_workload(
            _MAP_BATCH, config, symbols_span, tones_span
        )
        map_samples.append(global_perf_counter_ns() - start)
        checksum = _mix(checksum, Int(map_checksum & UInt64(Int.MAX)))
        keep(map_checksum)

        start = global_perf_counter_ns()
        var unmap_checksum = _direct_unmap_workload(
            _MAP_BATCH, config, mapped_symbols_span, tones_span
        )
        unmap_samples.append(global_perf_counter_ns() - start)
        checksum = _mix(checksum, Int(unmap_checksum & UInt64(Int.MAX)))
        keep(unmap_checksum)

    print_benchmark_metadata()
    print("wifi_mimo_spatial_backend:", "scalar-cpu-reference")
    print(
        "wifi_mimo_spatial_baseline:",
        "IEEE-802.11-2024-bounded;",
        "19.3.11.8.2;21.3.8.3.2;21.3.10.6;27.3.11.2.2;27.3.12.6",
    )
    report_timing_samples(
        "wifi_mimo_parser_block_bits",
        parser_block_samples,
        _WARMUPS,
        _TABLE_BATCH,
        "profile",
    )
    report_timing_samples(
        "wifi_mimo_spatial_parse",
        parse_samples,
        _WARMUPS,
        _BIT_BATCH * len(bits),
        "coded_bit",
    )
    report_timing_samples(
        "wifi_mimo_spatial_deparse",
        deparse_samples,
        _WARMUPS,
        _BIT_BATCH * len(parsed_bits),
        "stream_bit",
    )
    report_timing_samples(
        "wifi_mimo_cyclic_shift_ns",
        shift_samples,
        _WARMUPS,
        _TABLE_BATCH,
        "lookup",
    )
    report_timing_samples(
        "wifi_mimo_direct_csd_map",
        map_samples,
        _WARMUPS,
        _MAP_BATCH * len(symbols),
        "tone_symbol",
    )
    report_timing_samples(
        "wifi_mimo_direct_csd_unmap",
        unmap_samples,
        _WARMUPS,
        _MAP_BATCH * len(mapped_symbols),
        "tone_symbol",
    )
    keep(checksum)
    print("wifi_mimo_spatial_retained_checksum:", checksum)
