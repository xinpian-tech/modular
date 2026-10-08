"""Attributable CPU timings for Rel-17 RedCap RLM/BFD arithmetic."""

from std.benchmark import black_box, keep
from std.time import global_perf_counter_ns
from wireless_dsp.benchmarking import (
    print_benchmark_metadata,
    report_timing_samples,
)
from wireless_dsp.wireless.nr.redcap_rrm import (
    NR_REDCAP_RRM_FR1,
    NR_REDCAP_RRM_FR2,
    NR_REDCAP_RRM_RS_SSB,
    NR_REDCAP_RRM_RS_CSI_RS,
    NR_REDCAP_RRM_QUALITY_WORSE_THAN_QOUT,
    NR_REDCAP_RRM_QUALITY_BETTER_THAN_QIN,
    nr_redcap_rel17_classify_link_quality,
    nr_redcap_rel17_rlm_evaluation_periods_us,
    nr_redcap_rel17_bfd_evaluation_period_us,
    nr_redcap_rel17_rlm_l1_indication,
    nr_redcap_rel17_bfd_l1_indication,
    nr_redcap_rel17_rlm_indication_interval_us,
    nr_redcap_rel17_bfd_indication_interval_us,
    nr_redcap_rel17_next_l1_indication_time_us,
)


comptime _WARMUPS = 3
comptime _SAMPLES = 9
comptime _BATCH = 4096


def _mix(checksum: UInt64, value: Int) -> UInt64:
    return checksum * UInt64(1099511628211) ^ UInt64(value + 1)


@no_inline
def _quality_workload(iterations: Int, salt: Int) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for iteration in range(iterations):
        var quality = 6 * (((iteration + salt) % 3) - 1)
        var value = nr_redcap_rel17_classify_link_quality(
            black_box(Float64(quality)),
            black_box(-5.0),
            black_box(5.0),
        )
        checksum = _mix(checksum, value + iteration)
    return checksum


@no_inline
def _rlm_evaluation_workload(iterations: Int, salt: Int) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for iteration in range(iterations):
        var p_numerator = 3 + ((iteration + salt) & 1)
        var periods = nr_redcap_rel17_rlm_evaluation_periods_us(
            black_box(NR_REDCAP_RRM_FR1),
            black_box(2),
            black_box(NR_REDCAP_RRM_RS_CSI_RS),
            black_box(10000),
            black_box(True),
            black_box(320000),
            black_box(p_numerator),
            black_box(3),
            csi_rs_density=black_box(3),
            csi_rs_bandwidth_prbs=black_box(48),
        )
        checksum = _mix(_mix(checksum, periods[0]), periods[1] + iteration)
    return checksum


@no_inline
def _bfd_evaluation_workload(iterations: Int, salt: Int) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for iteration in range(iterations):
        var periodicity = 20000 + 20000 * ((iteration + salt) & 1)
        var period = nr_redcap_rel17_bfd_evaluation_period_us(
            black_box(NR_REDCAP_RRM_FR2),
            black_box(2),
            black_box(NR_REDCAP_RRM_RS_SSB),
            black_box(periodicity),
            black_box(False),
            black_box(0),
            black_box(1),
            black_box(1),
        )
        checksum = _mix(checksum, period + iteration)
    return checksum


@no_inline
def _rlm_aggregation_workload(
    iterations: Int,
    salt: Int,
    all_out: Span[Int, ...],
    one_in: Span[Int, ...],
) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for iteration in range(iterations):
        var value: Int
        if ((iteration + salt) & 1) == 0:
            value = nr_redcap_rel17_rlm_l1_indication(black_box(all_out))
        else:
            value = nr_redcap_rel17_rlm_l1_indication(black_box(one_in))
        checksum = _mix(checksum, value + iteration)
    return checksum


@no_inline
def _bfd_aggregation_workload(
    iterations: Int,
    salt: Int,
    all_failed: Span[UInt8, ...],
    one_good: Span[UInt8, ...],
) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for iteration in range(iterations):
        var value: Int
        if ((iteration + salt) & 1) == 0:
            value = nr_redcap_rel17_bfd_l1_indication(black_box(all_failed))
        else:
            value = nr_redcap_rel17_bfd_l1_indication(black_box(one_good))
        checksum = _mix(checksum, value + iteration)
    return checksum


@no_inline
def _rlm_interval_workload(
    iterations: Int,
    salt: Int,
    rs_types: Span[Int, ...],
    rs_periods: Span[Int, ...],
) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for iteration in range(iterations):
        var drx_enabled = ((iteration + salt) & 1) == 0
        var cycle = 320000 if drx_enabled else 0
        var value = nr_redcap_rel17_rlm_indication_interval_us(
            black_box(rs_types),
            black_box(rs_periods),
            black_box(drx_enabled),
            black_box(cycle),
        )
        checksum = _mix(checksum, value + iteration)
    return checksum


@no_inline
def _bfd_interval_workload(iterations: Int, salt: Int) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for iteration in range(iterations):
        var drx_enabled = ((iteration + salt) & 1) == 0
        var cycle = 320000 if drx_enabled else 0
        var value = nr_redcap_rel17_bfd_indication_interval_us(
            black_box(NR_REDCAP_RRM_RS_SSB),
            black_box(20000),
            black_box(drx_enabled),
            black_box(cycle),
        )
        checksum = _mix(checksum, value + iteration)
    return checksum


@no_inline
def _next_time_workload(iterations: Int, salt: Int) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for iteration in range(iterations):
        var value = nr_redcap_rel17_next_l1_indication_time_us(
            black_box(110000 + ((iteration + salt) & 31)),
            black_box(20000),
            previous_time_us=black_box(100000),
        )
        checksum = _mix(checksum, value + iteration)
    return checksum


def main() raises:
    var quality_all_out: List[Int] = [
        NR_REDCAP_RRM_QUALITY_WORSE_THAN_QOUT,
        NR_REDCAP_RRM_QUALITY_WORSE_THAN_QOUT,
    ]
    var quality_one_in: List[Int] = [
        NR_REDCAP_RRM_QUALITY_WORSE_THAN_QOUT,
        NR_REDCAP_RRM_QUALITY_BETTER_THAN_QIN,
    ]
    var bfd_all_failed: List[UInt8] = [1, 1]
    var bfd_one_good: List[UInt8] = [1, 0]
    var rlm_rs_types: List[Int] = [
        NR_REDCAP_RRM_RS_SSB, NR_REDCAP_RRM_RS_CSI_RS
    ]
    var rlm_rs_periods: List[Int] = [20000, 5000]

    for _ in range(_WARMUPS):
        var salt = 324508639
        keep(_quality_workload(_BATCH, salt))
        keep(_rlm_evaluation_workload(_BATCH, salt))
        keep(_bfd_evaluation_workload(_BATCH, salt))
        keep(_rlm_aggregation_workload(
            _BATCH,
            salt,
            Span(quality_all_out),
            Span(quality_one_in),
        ))
        keep(_bfd_aggregation_workload(
            _BATCH,
            salt,
            Span(bfd_all_failed),
            Span(bfd_one_good),
        ))
        keep(_rlm_interval_workload(
            _BATCH, salt, Span(rlm_rs_types), Span(rlm_rs_periods)
        ))
        keep(_bfd_interval_workload(_BATCH, salt))
        keep(_next_time_workload(_BATCH, salt))

    var quality_samples = List[UInt64](capacity=_SAMPLES)
    var rlm_evaluation_samples = List[UInt64](capacity=_SAMPLES)
    var bfd_evaluation_samples = List[UInt64](capacity=_SAMPLES)
    var rlm_aggregation_samples = List[UInt64](capacity=_SAMPLES)
    var bfd_aggregation_samples = List[UInt64](capacity=_SAMPLES)
    var rlm_interval_samples = List[UInt64](capacity=_SAMPLES)
    var bfd_interval_samples = List[UInt64](capacity=_SAMPLES)
    var next_time_samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)

    for _ in range(_SAMPLES):
        var salt = 324508639
        var start = global_perf_counter_ns()
        var quality = _quality_workload(_BATCH, salt)
        quality_samples.append(global_perf_counter_ns() - start)
        checksum = checksum * UInt64(1099511628211) ^ quality
        keep(quality)

        start = global_perf_counter_ns()
        var rlm_periods = _rlm_evaluation_workload(_BATCH, salt)
        rlm_evaluation_samples.append(global_perf_counter_ns() - start)
        checksum = checksum * UInt64(1099511628211) ^ rlm_periods
        keep(rlm_periods)

        start = global_perf_counter_ns()
        var bfd_period = _bfd_evaluation_workload(_BATCH, salt)
        bfd_evaluation_samples.append(global_perf_counter_ns() - start)
        checksum = checksum * UInt64(1099511628211) ^ bfd_period
        keep(bfd_period)

        start = global_perf_counter_ns()
        var rlm_indication = _rlm_aggregation_workload(
            _BATCH,
            salt,
            Span(quality_all_out),
            Span(quality_one_in),
        )
        rlm_aggregation_samples.append(global_perf_counter_ns() - start)
        checksum = checksum * UInt64(1099511628211) ^ rlm_indication
        keep(rlm_indication)

        start = global_perf_counter_ns()
        var bfd_indication = _bfd_aggregation_workload(
            _BATCH,
            salt,
            Span(bfd_all_failed),
            Span(bfd_one_good),
        )
        bfd_aggregation_samples.append(global_perf_counter_ns() - start)
        checksum = checksum * UInt64(1099511628211) ^ bfd_indication
        keep(bfd_indication)

        start = global_perf_counter_ns()
        var rlm_interval = _rlm_interval_workload(
            _BATCH, salt, Span(rlm_rs_types), Span(rlm_rs_periods)
        )
        rlm_interval_samples.append(global_perf_counter_ns() - start)
        checksum = checksum * UInt64(1099511628211) ^ rlm_interval
        keep(rlm_interval)

        start = global_perf_counter_ns()
        var bfd_interval = _bfd_interval_workload(_BATCH, salt)
        bfd_interval_samples.append(global_perf_counter_ns() - start)
        checksum = checksum * UInt64(1099511628211) ^ bfd_interval
        keep(bfd_interval)

        start = global_perf_counter_ns()
        var next_time = _next_time_workload(_BATCH, salt)
        next_time_samples.append(global_perf_counter_ns() - start)
        checksum = checksum * UInt64(1099511628211) ^ next_time
        keep(next_time)

    print_benchmark_metadata()
    print("nr_redcap_rrm_backend: scalar-cpu-reference")
    report_timing_samples(
        "nr_redcap_rel17_classify_link_quality",
        quality_samples,
        _WARMUPS,
        _BATCH,
        "quality_classification",
    )
    report_timing_samples(
        "nr_redcap_rel17_rlm_evaluation_periods_us",
        rlm_evaluation_samples,
        _WARMUPS,
        _BATCH,
        "rlm_period_pair",
    )
    report_timing_samples(
        "nr_redcap_rel17_bfd_evaluation_period_us",
        bfd_evaluation_samples,
        _WARMUPS,
        _BATCH,
        "bfd_period",
    )
    report_timing_samples(
        "nr_redcap_rel17_rlm_l1_indication",
        rlm_aggregation_samples,
        _WARMUPS,
        _BATCH,
        "resource_set_aggregation",
    )
    report_timing_samples(
        "nr_redcap_rel17_bfd_l1_indication",
        bfd_aggregation_samples,
        _WARMUPS,
        _BATCH,
        "resource_set_aggregation",
    )
    report_timing_samples(
        "nr_redcap_rel17_rlm_indication_interval_us",
        rlm_interval_samples,
        _WARMUPS,
        _BATCH,
        "rlm_reporting_interval",
    )
    report_timing_samples(
        "nr_redcap_rel17_bfd_indication_interval_us",
        bfd_interval_samples,
        _WARMUPS,
        _BATCH,
        "bfd_reporting_interval",
    )
    report_timing_samples(
        "nr_redcap_rel17_next_l1_indication_time_us",
        next_time_samples,
        _WARMUPS,
        _BATCH,
        "indication_release_time",
    )
    print("nr_redcap_rrm_retained_checksum:", checksum)
