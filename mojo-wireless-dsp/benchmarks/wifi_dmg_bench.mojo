"""Attributable CPU timings for bounded Clause-20 DMG Golay APIs.

Every public algorithm is measured as its own batched family after three
untimed warmups with nine odd samples.  A fixed salt selects reproducible legal
sequence rows, members, lags, or phase starts.  Complete returned objects are
retained with an O(1) endpoint fingerprint, avoiding a second timed O(N) scan;
no RF or accelerator path is involved.
"""

from std.benchmark import black_box, keep
from std.collections import Span
from std.time import global_perf_counter_ns
from wireless_dsp.benchmarking import (
    print_benchmark_metadata,
    report_timing_samples,
)
from wireless_dsp.core import Complex64
from wireless_dsp.wireless.wifi.dmg import (
    wifi_dmg_golay_sequence,
    wifi_dmg_pi_over_2_bpsk_modulate,
    wifi_dmg_pi_over_2_bpsk_demodulate_exact,
    wifi_dmg_control_stf_chips,
    wifi_dmg_golay_complementary_autocorrelation,
)


comptime _WARMUPS = 3
comptime _SAMPLES = 9
comptime _SEQUENCE_BATCH = 1024
comptime _MODULATE_BATCH = 256
comptime _DEMODULATE_BATCH = 256
comptime _STF_BATCH = 16
comptime _CORRELATION_BATCH = 4096
comptime _FIXED_SALT = 0x11AD2024


def _mix(checksum: UInt64, value: Int) -> UInt64:
    return (checksum ^ UInt64(value + 257)) * UInt64(1099511628211)


def _mix_int_endpoints(checksum: UInt64, values: Span[Int, ...]) -> UInt64:
    return _mix(
        checksum,
        len(values) * 17 + values[0] * 5 + values[len(values) - 1] * 11,
    )


def _mix_symbol_endpoints(
    checksum: UInt64, values: Span[Complex64, ...]
) -> UInt64:
    var result = _mix(checksum, len(values))
    for index in [0, len(values) - 1]:
        var real_code = 1
        var imag_code = 1
        if values[index].re < -0.5:
            real_code = 0
        elif values[index].re > 0.5:
            real_code = 2
        if values[index].im < -0.5:
            imag_code = 0
        elif values[index].im > 0.5:
            imag_code = 2
        result = _mix(result, real_code + 3 * imag_code + 11 * index)
    return result


def _length(selector: Int) -> Int:
    var row = selector % 3
    if row == 0:
        return 32
    if row == 1:
        return 64
    return 128


@no_inline
def _sequence_workload(iterations: Int, salt: Int) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for operation in range(iterations):
        var selector = operation + salt
        var chips = wifi_dmg_golay_sequence(
            black_box(_length(selector)), black_box((selector & 1) == 0)
        )
        checksum = _mix_int_endpoints(checksum, Span(chips))
        keep(chips)
    return checksum


@no_inline
def _modulate_workload(
    iterations: Int,
    salt: Int,
    first: Span[Int, ...],
    second: Span[Int, ...],
) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for operation in range(iterations):
        var selector = operation + salt
        var symbols: List[Complex64]
        if (selector & 1) == 0:
            symbols = wifi_dmg_pi_over_2_bpsk_modulate(
                black_box(first),
                start_chip_index=black_box(selector & 0x7FFFFFFF),
            )
        else:
            symbols = wifi_dmg_pi_over_2_bpsk_modulate(
                black_box(second),
                start_chip_index=black_box(selector & 0x7FFFFFFF),
            )
        checksum = _mix_symbol_endpoints(checksum, Span(symbols))
        keep(symbols)
    return checksum


@no_inline
def _demodulate_workload(
    iterations: Int,
    salt: Int,
    first: Span[Complex64, ...],
    second: Span[Complex64, ...],
) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for operation in range(iterations):
        var chips: List[Int]
        if ((operation + salt) & 1) == 0:
            chips = wifi_dmg_pi_over_2_bpsk_demodulate_exact(
                black_box(first), start_chip_index=0
            )
        else:
            chips = wifi_dmg_pi_over_2_bpsk_demodulate_exact(
                black_box(second), start_chip_index=1
            )
        checksum = _mix_int_endpoints(checksum, Span(chips))
        keep(chips)
    return checksum


@no_inline
def _control_stf_workload(iterations: Int) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for operation in range(iterations):
        var chips = wifi_dmg_control_stf_chips()
        checksum = _mix_int_endpoints(checksum, Span(chips))
        checksum = _mix(checksum, operation)
        keep(chips)
    return checksum


@no_inline
def _correlation_workload(
    iterations: Int,
    salt: Int,
    ga: Span[Int, ...],
    gb: Span[Int, ...],
) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for operation in range(iterations):
        var lag = (operation + salt) & 127
        var value = wifi_dmg_golay_complementary_autocorrelation(
            black_box(ga), black_box(gb), black_box(lag)
        )
        checksum = _mix(checksum, value + lag)
    return checksum


def main() raises:
    var ga128 = wifi_dmg_golay_sequence(128, True)
    var gb128 = wifi_dmg_golay_sequence(128, False)
    var ga_waveform_0 = wifi_dmg_pi_over_2_bpsk_modulate(Span(ga128))
    var gb_waveform_1 = wifi_dmg_pi_over_2_bpsk_modulate(
        Span(gb128), start_chip_index=1
    )

    for _ in range(_WARMUPS):
        var salt = _FIXED_SALT
        keep(_sequence_workload(_SEQUENCE_BATCH, salt))
        keep(
            _modulate_workload(
                _MODULATE_BATCH, salt, Span(ga128), Span(gb128)
            )
        )
        keep(
            _demodulate_workload(
                _DEMODULATE_BATCH,
                salt,
                Span(ga_waveform_0),
                Span(gb_waveform_1),
            )
        )
        keep(_control_stf_workload(_STF_BATCH))
        keep(
            _correlation_workload(
                _CORRELATION_BATCH, salt, Span(ga128), Span(gb128)
            )
        )

    var sequence_samples = List[UInt64](capacity=_SAMPLES)
    var modulate_samples = List[UInt64](capacity=_SAMPLES)
    var demodulate_samples = List[UInt64](capacity=_SAMPLES)
    var stf_samples = List[UInt64](capacity=_SAMPLES)
    var correlation_samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var salt = _FIXED_SALT
        var start = global_perf_counter_ns()
        var sequence_checksum = _sequence_workload(_SEQUENCE_BATCH, salt)
        sequence_samples.append(global_perf_counter_ns() - start)
        checksum = _mix(
            checksum, Int(sequence_checksum & UInt64(Int.MAX))
        )
        keep(sequence_checksum)

        start = global_perf_counter_ns()
        var modulate_checksum = _modulate_workload(
            _MODULATE_BATCH, salt, Span(ga128), Span(gb128)
        )
        modulate_samples.append(global_perf_counter_ns() - start)
        checksum = _mix(
            checksum, Int(modulate_checksum & UInt64(Int.MAX))
        )
        keep(modulate_checksum)

        start = global_perf_counter_ns()
        var demodulate_checksum = _demodulate_workload(
            _DEMODULATE_BATCH,
            salt,
            Span(ga_waveform_0),
            Span(gb_waveform_1),
        )
        demodulate_samples.append(global_perf_counter_ns() - start)
        checksum = _mix(
            checksum, Int(demodulate_checksum & UInt64(Int.MAX))
        )
        keep(demodulate_checksum)

        start = global_perf_counter_ns()
        var stf_checksum = _control_stf_workload(_STF_BATCH)
        stf_samples.append(global_perf_counter_ns() - start)
        checksum = _mix(checksum, Int(stf_checksum & UInt64(Int.MAX)))
        keep(stf_checksum)

        start = global_perf_counter_ns()
        var correlation_checksum = _correlation_workload(
            _CORRELATION_BATCH, salt, Span(ga128), Span(gb128)
        )
        correlation_samples.append(global_perf_counter_ns() - start)
        checksum = _mix(
            checksum, Int(correlation_checksum & UInt64(Int.MAX))
        )
        keep(correlation_checksum)

    print_benchmark_metadata()
    print("wifi_dmg_backend:", "scalar-cpu-reference")
    print(
        "wifi_dmg_baseline:",
        "IEEE-802.11-2024-Clause-20.4.3.1.2-and-20.11-bounded",
    )
    report_timing_samples(
        "wifi_dmg_golay_sequence",
        sequence_samples,
        _WARMUPS,
        _SEQUENCE_BATCH,
        "sequence",
    )
    report_timing_samples(
        "wifi_dmg_pi_over_2_bpsk_modulate",
        modulate_samples,
        _WARMUPS,
        _MODULATE_BATCH * 128,
        "chip",
    )
    report_timing_samples(
        "wifi_dmg_pi_over_2_bpsk_demodulate_exact",
        demodulate_samples,
        _WARMUPS,
        _DEMODULATE_BATCH * 128,
        "symbol",
    )
    report_timing_samples(
        "wifi_dmg_control_stf_chips",
        stf_samples,
        _WARMUPS,
        _STF_BATCH,
        "stf",
    )
    report_timing_samples(
        "wifi_dmg_golay_complementary_autocorrelation",
        correlation_samples,
        _WARMUPS,
        _CORRELATION_BATCH,
        "lag",
    )
    keep(checksum)
    print("wifi_dmg_retained_checksum:", checksum)
