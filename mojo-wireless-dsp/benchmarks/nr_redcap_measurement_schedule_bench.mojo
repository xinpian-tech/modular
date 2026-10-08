"""Attributable CPU timings for Rel-17 RedCap measurement schedules."""

from std.benchmark import black_box, keep
from std.time import global_perf_counter_ns
from wireless_dsp.benchmarking import (
    print_benchmark_metadata,
    report_timing_samples,
)
from wireless_dsp.wireless.nr.redcap_measurement_schedule import (
    NR_REDCAP_MEASUREMENT_FR1,
    NR_REDCAP_MEASUREMENT_FR2,
    NRRedCapServingMeasurementSchedule,
    nr_redcap_rel17_measurement_capability,
    nr_redcap_rel17_idle_serving_measurement_schedule,
    nr_redcap_rel17_inactive_serving_measurement_schedule,
    nr_redcap_rel17_all_neighbour_measurements_required,
)


comptime _WARMUPS = 3
comptime _SAMPLES = 9
comptime _BATCH = 4096


def _mix(checksum: UInt64, value: Int) -> UInt64:
    return checksum * UInt64(1099511628211) ^ UInt64(value + 1)


def _drx_cycle_us(selector: Int) -> Int:
    if selector == 0:
        return 320000
    if selector == 1:
        return 640000
    if selector == 2:
        return 1280000
    return 2560000


def _inactive_t_us(selector: Int) -> Int:
    if selector < 4:
        return _drx_cycle_us(selector)
    if selector == 4:
        return 5120000
    return 10240000


@no_inline
def _capability_workload(iterations: Int, salt: Int) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for iteration in range(iterations):
        var rx_branches = 1 if ((iteration + salt) & 1) == 0 else 2
        var capability = nr_redcap_rel17_measurement_capability(
            black_box(NR_REDCAP_MEASUREMENT_FR1), black_box(rx_branches)
        )
        checksum = _mix(
            checksum,
            capability.minimum_nr_inter_frequency_carriers
                + capability.minimum_total_frequency_layers
                + iteration,
        )
    return checksum


@no_inline
def _idle_schedule_workload(iterations: Int, salt: Int) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for iteration in range(iterations):
        var selector = (iteration + salt) & 3
        var frequency_range = (
            NR_REDCAP_MEASUREMENT_FR1
            if ((iteration + salt) & 4) == 0
            else NR_REDCAP_MEASUREMENT_FR2
        )
        var rx_branches = (
            1 if frequency_range == NR_REDCAP_MEASUREMENT_FR1 else 2
        )
        var schedule = nr_redcap_rel17_idle_serving_measurement_schedule(
            black_box(frequency_range),
            black_box(rx_branches),
            black_box(40000),
            black_box(_drx_cycle_us(selector)),
            edrx_idle_cycle_us=black_box(20480000),
        )
        checksum = _mix(
            checksum,
            schedule.nserv
                + schedule.minimum_ptw_us
                + schedule.failure_window_us
                + iteration,
        )
    return checksum


@no_inline
def _inactive_schedule_workload(iterations: Int, salt: Int) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for iteration in range(iterations):
        var selector = (iteration + salt) % 6
        var frequency_range = (
            NR_REDCAP_MEASUREMENT_FR1
            if ((iteration + salt) & 1) == 0
            else NR_REDCAP_MEASUREMENT_FR2
        )
        var rx_branches = (
            1 if frequency_range == NR_REDCAP_MEASUREMENT_FR1 else 2
        )
        var schedule = nr_redcap_rel17_inactive_serving_measurement_schedule(
            black_box(frequency_range),
            black_box(rx_branches),
            black_box(40000),
            black_box(2560000),
            black_box(_inactive_t_us(selector)),
        )
        checksum = _mix(
            checksum,
            schedule.m1
                + schedule.n1
                + schedule.nserv
                + schedule.failure_window_us
                + iteration,
        )
    return checksum


@no_inline
def _activation_workload(
    iterations: Int,
    salt: Int,
    schedule: NRRedCapServingMeasurementSchedule,
) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for iteration in range(iterations):
        var failures = schedule.nserv - 1 + ((iteration + salt) & 1)
        var required = nr_redcap_rel17_all_neighbour_measurements_required(
            schedule, black_box(failures)
        )
        checksum = _mix(checksum, (1 if required else 0) + iteration)
    return checksum


def main() raises:
    var activation_schedule = (
        nr_redcap_rel17_idle_serving_measurement_schedule(
            NR_REDCAP_MEASUREMENT_FR2,
            2,
            40000,
            320000,
            edrx_idle_cycle_us=20480000,
        )
    )

    for _ in range(_WARMUPS):
        var salt = 324508639
        keep(_capability_workload(_BATCH, salt))
        keep(_idle_schedule_workload(_BATCH, salt))
        keep(_inactive_schedule_workload(_BATCH, salt))
        keep(_activation_workload(_BATCH, salt, activation_schedule))

    var capability_samples = List[UInt64](capacity=_SAMPLES)
    var idle_samples = List[UInt64](capacity=_SAMPLES)
    var inactive_samples = List[UInt64](capacity=_SAMPLES)
    var activation_samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)

    for _ in range(_SAMPLES):
        var salt = 324508639
        var start = global_perf_counter_ns()
        var capability = _capability_workload(_BATCH, salt)
        capability_samples.append(global_perf_counter_ns() - start)
        checksum = checksum * UInt64(1099511628211) ^ capability
        keep(capability)

        start = global_perf_counter_ns()
        var idle = _idle_schedule_workload(_BATCH, salt)
        idle_samples.append(global_perf_counter_ns() - start)
        checksum = checksum * UInt64(1099511628211) ^ idle
        keep(idle)

        start = global_perf_counter_ns()
        var inactive = _inactive_schedule_workload(_BATCH, salt)
        inactive_samples.append(global_perf_counter_ns() - start)
        checksum = checksum * UInt64(1099511628211) ^ inactive
        keep(inactive)

        start = global_perf_counter_ns()
        var activation = _activation_workload(
            _BATCH, salt, activation_schedule
        )
        activation_samples.append(global_perf_counter_ns() - start)
        checksum = checksum * UInt64(1099511628211) ^ activation
        keep(activation)

    print_benchmark_metadata()
    print("nr_redcap_measurement_schedule_backend: scalar-cpu-reference")
    report_timing_samples(
        "nr_redcap_rel17_measurement_capability",
        capability_samples,
        _WARMUPS,
        _BATCH,
        "capability_lookup",
    )
    report_timing_samples(
        "nr_redcap_rel17_idle_serving_measurement_schedule",
        idle_samples,
        _WARMUPS,
        _BATCH,
        "idle_schedule_lookup",
    )
    report_timing_samples(
        "nr_redcap_rel17_inactive_serving_measurement_schedule",
        inactive_samples,
        _WARMUPS,
        _BATCH,
        "inactive_schedule_lookup",
    )
    report_timing_samples(
        "nr_redcap_rel17_all_neighbour_measurements_required",
        activation_samples,
        _WARMUPS,
        _BATCH,
        "nserv_threshold_decision",
    )
    print("nr_redcap_measurement_schedule_retained_checksum:", checksum)
