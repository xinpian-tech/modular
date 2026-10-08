"""Attributable CPU timings for Rel-17 RedCap relaxation decisions."""

from std.benchmark import black_box, keep
from std.time import global_perf_counter_ns
from wireless_dsp.benchmarking import (
    print_benchmark_metadata,
    report_timing_samples,
)
from wireless_dsp.wireless.nr.redcap_relaxation import (
    NR_REDCAP_RELAXATION_FR1,
    NR_REDCAP_RELAXATION_COMBINE_AND,
    NR_REDCAP_RELAXATION_COMBINE_OR,
    NR_REDCAP_RESELECTION_EXCLUSION_MAX_US,
    NR_REDCAP_STATIONARY_NO_MEASUREMENT_LIMIT_US,
    NRRedCapStationaryRelaxationState,
    nr_redcap_rel17_stationary_delta_met,
    nr_redcap_rel17_stationary_update,
    nr_redcap_rel17_stationary_not_at_cell_edge_met,
    nr_redcap_rel17_combine_relaxed_measurement_conditions,
    nr_redcap_rel17_stationary_no_measurement_allowed,
    nr_redcap_rel17_reselection_exclusion_active,
)


comptime _WARMUPS = 3
comptime _SAMPLES = 9
comptime _BATCH = 4096


def _mix(checksum: UInt64, value: Int) -> UInt64:
    return checksum * UInt64(1099511628211) ^ UInt64(value + 1)


@no_inline
def _stationary_delta_workload(iterations: Int, salt: Int) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for iteration in range(iterations):
        var current = -82.999 if ((iteration + salt) & 1) == 0 else -83.0
        var met = nr_redcap_rel17_stationary_delta_met(
            black_box(-80.0),
            black_box(current),
            black_box(3.0),
        )
        checksum = _mix(checksum, (1 if met else 0) + iteration)
    return checksum


@no_inline
def _stationary_update_workload(
    iterations: Int,
    salt: Int,
    mut state: NRRedCapStationaryRelaxationState,
) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for iteration in range(iterations):
        var selector = (iteration + salt) & 31
        var current = -79.0 if selector == 0 else -81.0
        var ready = nr_redcap_rel17_stationary_update(
            state,
            black_box(current),
            black_box(state.last_update_us + 1000),
            black_box(10000),
            black_box(3.0),
        )
        checksum = _mix(
            checksum,
            (1 if ready else 0) + iteration + Int(state.reference_srxlev_db),
        )
    return checksum


@no_inline
def _not_at_cell_edge_workload(iterations: Int, salt: Int) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for iteration in range(iterations):
        var selector = (iteration + salt) % 3
        var srxlev = -69.0 if selector != 0 else -70.0
        var squal = -4.0 if selector != 1 else -5.0
        var met = nr_redcap_rel17_stationary_not_at_cell_edge_met(
            black_box(True),
            black_box(srxlev),
            black_box(squal),
            black_box(-70.0),
            black_box(-5.0),
        )
        checksum = _mix(checksum, (1 if met else 0) + iteration)
    return checksum


@no_inline
def _combine_workload(iterations: Int, salt: Int) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for iteration in range(iterations):
        var stationary = ((iteration + salt) & 3) != 0
        var at_edge = ((iteration + salt) & 1) == 0
        var not_at_edge_ready = stationary and not at_edge
        var policy = (
            NR_REDCAP_RELAXATION_COMBINE_AND
            if ((iteration + salt) & 1) == 0
            else NR_REDCAP_RELAXATION_COMBINE_OR
        )
        var met = nr_redcap_rel17_combine_relaxed_measurement_conditions(
            black_box(stationary),
            black_box(not_at_edge_ready),
            black_box(policy),
        )
        checksum = _mix(checksum, (1 if met else 0) + iteration)
    return checksum


@no_inline
def _no_measurement_workload(iterations: Int, salt: Int) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for iteration in range(iterations):
        var elapsed = (
            NR_REDCAP_STATIONARY_NO_MEASUREMENT_LIMIT_US - 1
            if ((iteration + salt) & 1) == 0
            else NR_REDCAP_STATIONARY_NO_MEASUREMENT_LIMIT_US
        )
        var allowed = nr_redcap_rel17_stationary_no_measurement_allowed(
            black_box(True), black_box(elapsed)
        )
        checksum = _mix(checksum, (1 if allowed else 0) + iteration)
    return checksum


@no_inline
def _exclusion_workload(iterations: Int, salt: Int) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for iteration in range(iterations):
        var elapsed = (
            NR_REDCAP_RESELECTION_EXCLUSION_MAX_US - 1
            if ((iteration + salt) & 1) == 0
            else NR_REDCAP_RESELECTION_EXCLUSION_MAX_US
        )
        var active = nr_redcap_rel17_reselection_exclusion_active(
            black_box(1000000),
            black_box(1000000 + elapsed),
        )
        checksum = _mix(checksum, (1 if active else 0) + iteration)
    return checksum


def main() raises:
    var state = NRRedCapStationaryRelaxationState(
        NR_REDCAP_RELAXATION_FR1, 2, -80.0, 0
    )

    for _ in range(_WARMUPS):
        var salt = 324508639
        keep(_stationary_delta_workload(_BATCH, salt))
        keep(_stationary_update_workload(_BATCH, salt, state))
        keep(_not_at_cell_edge_workload(_BATCH, salt))
        keep(_combine_workload(_BATCH, salt))
        keep(_no_measurement_workload(_BATCH, salt))
        keep(_exclusion_workload(_BATCH, salt))

    var delta_samples = List[UInt64](capacity=_SAMPLES)
    var update_samples = List[UInt64](capacity=_SAMPLES)
    var edge_samples = List[UInt64](capacity=_SAMPLES)
    var combine_samples = List[UInt64](capacity=_SAMPLES)
    var no_measurement_samples = List[UInt64](capacity=_SAMPLES)
    var exclusion_samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)

    for _ in range(_SAMPLES):
        var salt = 324508639
        var start = global_perf_counter_ns()
        var delta = _stationary_delta_workload(_BATCH, salt)
        delta_samples.append(global_perf_counter_ns() - start)
        checksum = checksum * UInt64(1099511628211) ^ delta
        keep(delta)

        start = global_perf_counter_ns()
        var update = _stationary_update_workload(_BATCH, salt, state)
        update_samples.append(global_perf_counter_ns() - start)
        checksum = checksum * UInt64(1099511628211) ^ update
        keep(update)

        start = global_perf_counter_ns()
        var edge = _not_at_cell_edge_workload(_BATCH, salt)
        edge_samples.append(global_perf_counter_ns() - start)
        checksum = checksum * UInt64(1099511628211) ^ edge
        keep(edge)

        start = global_perf_counter_ns()
        var combine = _combine_workload(_BATCH, salt)
        combine_samples.append(global_perf_counter_ns() - start)
        checksum = checksum * UInt64(1099511628211) ^ combine
        keep(combine)

        start = global_perf_counter_ns()
        var no_measurement = _no_measurement_workload(_BATCH, salt)
        no_measurement_samples.append(global_perf_counter_ns() - start)
        checksum = checksum * UInt64(1099511628211) ^ no_measurement
        keep(no_measurement)

        start = global_perf_counter_ns()
        var exclusion = _exclusion_workload(_BATCH, salt)
        exclusion_samples.append(global_perf_counter_ns() - start)
        checksum = checksum * UInt64(1099511628211) ^ exclusion
        keep(exclusion)

    print_benchmark_metadata()
    print("nr_redcap_relaxation_backend: scalar-cpu-reference")
    report_timing_samples(
        "nr_redcap_rel17_stationary_delta_met",
        delta_samples,
        _WARMUPS,
        _BATCH,
        "stationary_delta_decision",
    )
    report_timing_samples(
        "nr_redcap_rel17_stationary_update",
        update_samples,
        _WARMUPS,
        _BATCH,
        "stationary_state_transition",
    )
    report_timing_samples(
        "nr_redcap_rel17_stationary_not_at_cell_edge_met",
        edge_samples,
        _WARMUPS,
        _BATCH,
        "stationary_edge_decision",
    )
    report_timing_samples(
        "nr_redcap_rel17_combine_relaxed_measurement_conditions",
        combine_samples,
        _WARMUPS,
        _BATCH,
        "combine_policy_decision",
    )
    report_timing_samples(
        "nr_redcap_rel17_stationary_no_measurement_allowed",
        no_measurement_samples,
        _WARMUPS,
        _BATCH,
        "four_hour_gate_decision",
    )
    report_timing_samples(
        "nr_redcap_rel17_reselection_exclusion_active",
        exclusion_samples,
        _WARMUPS,
        _BATCH,
        "exclusion_timer_decision",
    )
    print("nr_redcap_relaxation_retained_checksum:", checksum)
