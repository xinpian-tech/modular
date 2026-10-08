"""Attributable batched CPU benchmarks for Wi-Fi FTM range arithmetic."""

from std.benchmark import black_box, keep
from std.time import global_perf_counter_ns
from wireless_dsp.benchmarking import (
    print_benchmark_metadata,
    report_timing_samples,
)
from wireless_dsp.wireless.wifi.ftm_ranging import (
    WifiFTMExchangeTimestamps,
    wifi_ftm_exchange_intervals_ps,
    wifi_ftm_corrected_round_trip_ps,
    wifi_ftm_link_delay_seconds,
    wifi_ftm_range_m,
    wifi_ftm_range_result,
)


comptime _WARMUPS = 3
comptime _SAMPLES = 9
comptime _BATCH = 4096


def _mix(checksum: UInt64, value: UInt64) -> UInt64:
    return (checksum ^ value) * UInt64(1099511628211)


def _exchange(operation: Int, salt: Int) raises -> WifiFTMExchangeTimestamps:
    var t1 = 1000000 + ((operation + salt) & 0xFFFF)
    var t2 = 7000000 + ((operation * 3 + salt) & 0xFFFF)
    var turnaround = 15000000 + ((operation * 5 + salt) & 0x3FF)
    var rtt = turnaround + 2000000 + ((operation + salt) & 0x1FF)
    return WifiFTMExchangeTimestamps(t1, t2, t2 + turnaround, t1 + rtt)


@no_inline
def _intervals_workload(iterations: Int, salt: Int) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for operation in range(iterations):
        var value = wifi_ftm_exchange_intervals_ps(
            black_box(_exchange(operation, salt))
        )
        checksum = _mix(
            checksum,
            UInt64(value.responder_round_trip_ps)
            ^ UInt64(value.initiator_turnaround_ps),
        )
        keep(value)
    return checksum


@no_inline
def _corrected_workload(iterations: Int, salt: Int) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for operation in range(iterations):
        var value = wifi_ftm_corrected_round_trip_ps(
            black_box(_exchange(operation, salt))
        )
        checksum = _mix(checksum, UInt64(value))
        keep(value)
    return checksum


@no_inline
def _delay_workload(iterations: Int, salt: Int) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for operation in range(iterations):
        var ratio = 0.9999 + Float64((operation + salt) & 7) * 0.00001
        var value = wifi_ftm_link_delay_seconds(
            black_box(_exchange(operation, salt)), black_box(ratio)
        )
        checksum = _mix(checksum, UInt64(value * 1.0e15))
        keep(value)
    return checksum


@no_inline
def _range_workload(iterations: Int, salt: Int) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for operation in range(iterations):
        var ratio = 0.9999 + Float64((operation + salt) & 7) * 0.00001
        var value = wifi_ftm_range_m(
            black_box(_exchange(operation, salt)), black_box(ratio)
        )
        checksum = _mix(checksum, UInt64(value * 1.0e6))
        keep(value)
    return checksum


@no_inline
def _result_workload(iterations: Int, salt: Int) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for operation in range(iterations):
        var ratio = 0.9999 + Float64((operation + salt) & 7) * 0.00001
        var value = wifi_ftm_range_result(
            black_box(_exchange(operation, salt)), black_box(ratio)
        )
        checksum = _mix(
            checksum,
            UInt64(value.corrected_round_trip_ps)
            ^ UInt64(value.distance_m * 1.0e6),
        )
        keep(value)
    return checksum


def main() raises:
    for warmup in range(_WARMUPS):
        var salt = 324508639 + warmup
        keep(_intervals_workload(_BATCH, salt))
        keep(_corrected_workload(_BATCH, salt))
        keep(_delay_workload(_BATCH, salt))
        keep(_range_workload(_BATCH, salt))
        keep(_result_workload(_BATCH, salt))

    var intervals_samples = List[UInt64](capacity=_SAMPLES)
    var corrected_samples = List[UInt64](capacity=_SAMPLES)
    var delay_samples = List[UInt64](capacity=_SAMPLES)
    var range_samples = List[UInt64](capacity=_SAMPLES)
    var result_samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for sample in range(_SAMPLES):
        var salt = 324508639 + sample
        var start = global_perf_counter_ns()
        var value = _intervals_workload(_BATCH, salt)
        intervals_samples.append(global_perf_counter_ns() - start)
        checksum = _mix(checksum, value)
        keep(value)

        start = global_perf_counter_ns()
        value = _corrected_workload(_BATCH, salt)
        corrected_samples.append(global_perf_counter_ns() - start)
        checksum = _mix(checksum, value)
        keep(value)

        start = global_perf_counter_ns()
        value = _delay_workload(_BATCH, salt)
        delay_samples.append(global_perf_counter_ns() - start)
        checksum = _mix(checksum, value)
        keep(value)

        start = global_perf_counter_ns()
        value = _range_workload(_BATCH, salt)
        range_samples.append(global_perf_counter_ns() - start)
        checksum = _mix(checksum, value)
        keep(value)

        start = global_perf_counter_ns()
        value = _result_workload(_BATCH, salt)
        result_samples.append(global_perf_counter_ns() - start)
        checksum = _mix(checksum, value)
        keep(value)

    print_benchmark_metadata()
    print("wifi_ftm_ranging_backend: scalar-cpu-reference")
    print("wifi_ftm_ranging_baseline: IEEE Std 802.11-2024")
    report_timing_samples(
        "wifi_ftm_exchange_intervals_ps",
        intervals_samples,
        _WARMUPS,
        _BATCH,
        "ftm_exchange",
    )
    report_timing_samples(
        "wifi_ftm_corrected_round_trip_ps",
        corrected_samples,
        _WARMUPS,
        _BATCH,
        "ftm_exchange",
    )
    report_timing_samples(
        "wifi_ftm_link_delay_seconds",
        delay_samples,
        _WARMUPS,
        _BATCH,
        "ftm_exchange",
    )
    report_timing_samples(
        "wifi_ftm_range_m",
        range_samples,
        _WARMUPS,
        _BATCH,
        "ftm_exchange",
    )
    report_timing_samples(
        "wifi_ftm_range_result",
        result_samples,
        _WARMUPS,
        _BATCH,
        "ftm_exchange",
    )
    print("wifi_ftm_retained_checksum:", checksum)
    keep(checksum)
