"""Strict attributable timings for Rel-17 RedCap low-mobility APIs."""

from std.benchmark import keep
from std.time import global_perf_counter_ns
from wireless_dsp.benchmarking import (
    print_benchmark_metadata,
    report_timing_samples,
)
from wireless_dsp.wireless.nr.redcap_low_mobility import (
    NR_REDCAP_LOW_MOBILITY_FR1,
    NR_REDCAP_LOW_MOBILITY_FR2,
    NR_REDCAP_RELAXED_FAMILY_INTRA_NR,
    NR_REDCAP_RELAXED_FAMILY_INTER_NR,
    NR_REDCAP_RELAXED_CRITERION_LOW_MOBILITY,
    NR_REDCAP_LOW_MOBILITY_COMBINE_REQUIRE_BOTH,
    NR_REDCAP_SCENARIO_NORMAL,
    NR_REDCAP_SCENARIO_LOW_MOBILITY,
    NRRedCapLowMobilityState,
    NRRedCapMeasurementScenarioState,
    NRRedCapTimingRequirementTransitionState,
    nr_redcap_rel17_low_mobility_delta_met,
    nr_redcap_rel17_low_mobility_update,
    nr_redcap_rel17_not_at_cell_edge_met,
    nr_redcap_rel17_combine_low_mobility_cell_edge_conditions,
    nr_redcap_rel17_low_mobility_cell_edge_no_measurement_allowed,
    nr_redcap_rel17_low_mobility_high_priority_search_interval_us,
    nr_redcap_rel17_idle_low_mobility_or_cell_edge_timing,
    nr_redcap_rel17_inactive_low_mobility_or_cell_edge_timing,
    nr_redcap_rel17_start_measurement_scenario_transition,
    nr_redcap_rel17_measurement_scenario_update,
    nr_redcap_rel17_timing_requirement_transition_update,
)


comptime _WARMUPS = 3
comptime _SAMPLES = 9
comptime _SEED = UInt64(1469598103934665603)


def _mix(checksum: UInt64, value: UInt64) -> UInt64:
    return (checksum ^ value) * UInt64(1099511628211)


def _signed_fingerprint(value: Int) -> UInt64:
    return _mix(
        UInt64(abs(value)), UInt64(1 if value < 0 else 0)
    )


def _run[
    workload: def() thin raises -> Tuple[UInt64, UInt64]
](name: StringSlice) raises -> UInt64:
    var first = workload()
    var second = workload()
    if first[1] != second[1]:
        raise Error("RedCap low-mobility benchmark is nondeterministic")
    keep(first)
    keep(second)
    for _ in range(_WARMUPS):
        keep(workload())
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = _SEED
    for _ in range(_SAMPLES):
        var sample = workload()
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    report_timing_samples(name, samples, _WARMUPS, 1, "api_call")
    keep(samples)
    return checksum


@no_inline
def _delta_workload() raises -> Tuple[UInt64, UInt64]:
    var reference_srxlev_db = -80.0
    var current_srxlev_db = -82.5
    var threshold_db = 3.0
    var start = global_perf_counter_ns()
    var result = nr_redcap_rel17_low_mobility_delta_met(
        reference_srxlev_db, current_srxlev_db, threshold_db
    )
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, UInt64(1 if result else 0))


@no_inline
def _state_update_workload() raises -> Tuple[UInt64, UInt64]:
    var state = NRRedCapLowMobilityState(-80.0, 0)
    var current_srxlev_db = -81.0
    var current_time_us = 10000
    var dwell_us = 10000
    var threshold_db = 3.0
    var start = global_perf_counter_ns()
    var result = nr_redcap_rel17_low_mobility_update(
        state,
        current_srxlev_db,
        current_time_us,
        dwell_us,
        threshold_db,
    )
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    keep(state)
    var fingerprint = UInt64(1 if result else 0)
    fingerprint = _mix(
        fingerprint, _signed_fingerprint(state.last_update_us)
    )
    return (elapsed, fingerprint)


@no_inline
def _not_at_edge_workload() raises -> Tuple[UInt64, UInt64]:
    var srxlev_db = -69.0
    var squal_db = -4.0
    var threshold_p_db = -70.0
    var threshold_q_db = -5.0
    var start = global_perf_counter_ns()
    var result = nr_redcap_rel17_not_at_cell_edge_met(
        srxlev_db, squal_db, threshold_p_db, threshold_q_db
    )
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, UInt64(1 if result else 0))


@no_inline
def _combine_conditions_workload() raises -> Tuple[UInt64, UInt64]:
    var low_mobility_ready = True
    var not_at_cell_edge_ready = True
    var policy = NR_REDCAP_LOW_MOBILITY_COMBINE_REQUIRE_BOTH
    var start = global_perf_counter_ns()
    var result = nr_redcap_rel17_combine_low_mobility_cell_edge_conditions(
        low_mobility_ready, not_at_cell_edge_ready, policy
    )
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, UInt64(1 if result else 0))


@no_inline
def _no_measurement_workload() raises -> Tuple[UInt64, UInt64]:
    var low_mobility_ready = True
    var not_at_cell_edge_ready = True
    var elapsed_since_measurement_us = 3599999999
    var start = global_perf_counter_ns()
    var result = (
        nr_redcap_rel17_low_mobility_cell_edge_no_measurement_allowed(
            low_mobility_ready,
            not_at_cell_edge_ready,
            elapsed_since_measurement_us,
        )
    )
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, UInt64(1 if result else 0))


@no_inline
def _high_priority_interval_workload() raises -> Tuple[UInt64, UInt64]:
    var base_interval_us = 1000000
    var start = global_perf_counter_ns()
    var result = (
        nr_redcap_rel17_low_mobility_high_priority_search_interval_us(
            base_interval_us,
            high_priority_meas_relax_configured=True,
            low_mobility_ready=True,
            serving_above_non_intra_thresholds=True,
        )
    )
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, UInt64(result))


@no_inline
def _idle_timing_workload() raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_redcap_rel17_idle_low_mobility_or_cell_edge_timing(
        NR_REDCAP_RELAXED_FAMILY_INTER_NR,
        NR_REDCAP_RELAXED_CRITERION_LOW_MOBILITY,
        NR_REDCAP_LOW_MOBILITY_FR1,
        1,
        40000,
        640000,
    )
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = UInt64(result.detect_us)
    fingerprint = _mix(fingerprint, UInt64(result.measure_us))
    fingerprint = _mix(fingerprint, UInt64(result.evaluate_us))
    return (elapsed, fingerprint)


@no_inline
def _inactive_timing_workload() raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_redcap_rel17_inactive_low_mobility_or_cell_edge_timing(
        NR_REDCAP_RELAXED_FAMILY_INTRA_NR,
        NR_REDCAP_RELAXED_CRITERION_LOW_MOBILITY,
        NR_REDCAP_LOW_MOBILITY_FR2,
        2,
        40000,
        20480000,
        5120000,
    )
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = UInt64(result.detect_cycles)
    fingerprint = _mix(fingerprint, UInt64(result.measure_cycles))
    fingerprint = _mix(fingerprint, UInt64(result.evaluate_cycles))
    return (elapsed, fingerprint)


@no_inline
def _scenario_transition_start_workload() raises -> Tuple[UInt64, UInt64]:
    var state = NRRedCapMeasurementScenarioState(
        NR_REDCAP_SCENARIO_NORMAL, 0
    )
    var target = NR_REDCAP_SCENARIO_LOW_MOBILITY
    var current_time_us = 0
    var transition_period_us = 1000
    var start = global_perf_counter_ns()
    var result = nr_redcap_rel17_start_measurement_scenario_transition(
        state,
        target,
        current_time_us,
        selected_tnormal_us=transition_period_us,
    )
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    keep(state)
    var fingerprint = UInt64(result + 1)
    fingerprint = _mix(
        fingerprint, UInt64(1 if state.transition_active else 0)
    )
    return (elapsed, fingerprint)


@no_inline
def _scenario_update_workload() raises -> Tuple[UInt64, UInt64]:
    var state = NRRedCapMeasurementScenarioState(
        NR_REDCAP_SCENARIO_NORMAL, 0
    )
    state.target_scenario = NR_REDCAP_SCENARIO_LOW_MOBILITY
    state.transition_started_us = 0
    state.transition_period_us = 1000
    state.last_update_us = 0
    state.transition_active = True
    var current_time_us = 1000
    var start = global_perf_counter_ns()
    var result = nr_redcap_rel17_measurement_scenario_update(
        state, current_time_us
    )
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    keep(state)
    var fingerprint = UInt64(result + 1)
    fingerprint = _mix(
        fingerprint, UInt64(1 if state.transition_active else 0)
    )
    return (elapsed, fingerprint)


@no_inline
def _timing_transition_workload() raises -> Tuple[UInt64, UInt64]:
    var state = NRRedCapTimingRequirementTransitionState(1000, 2000, 0)
    var current_time_us = 2000
    var start = global_perf_counter_ns()
    var result = nr_redcap_rel17_timing_requirement_transition_update(
        state, current_time_us
    )
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    keep(state)
    var fingerprint = UInt64(result)
    fingerprint = _mix(
        fingerprint, UInt64(1 if state.transition_active else 0)
    )
    return (elapsed, fingerprint)


def main() raises:
    print_benchmark_metadata()
    print("nr_redcap_low_mobility_backend: scalar-cpu-reference")
    var checksum = _SEED
    checksum = _mix(
        checksum,
        _run[_delta_workload]("nr_redcap_rel17_low_mobility_delta_met"),
    )
    checksum = _mix(
        checksum,
        _run[_state_update_workload]("nr_redcap_rel17_low_mobility_update"),
    )
    checksum = _mix(
        checksum,
        _run[_not_at_edge_workload]("nr_redcap_rel17_not_at_cell_edge_met"),
    )
    checksum = _mix(
        checksum,
        _run[_combine_conditions_workload](
            "nr_redcap_rel17_combine_low_mobility_cell_edge_conditions"
        ),
    )
    checksum = _mix(
        checksum,
        _run[_no_measurement_workload](
            "nr_redcap_rel17_low_mobility_cell_edge_no_measurement_allowed"
        ),
    )
    checksum = _mix(
        checksum,
        _run[_high_priority_interval_workload](
            "nr_redcap_rel17_low_mobility_high_priority_search_interval_us"
        ),
    )
    checksum = _mix(
        checksum,
        _run[_idle_timing_workload](
            "nr_redcap_rel17_idle_low_mobility_or_cell_edge_timing"
        ),
    )
    checksum = _mix(
        checksum,
        _run[_inactive_timing_workload](
            "nr_redcap_rel17_inactive_low_mobility_or_cell_edge_timing"
        ),
    )
    checksum = _mix(
        checksum,
        _run[_scenario_transition_start_workload](
            "nr_redcap_rel17_start_measurement_scenario_transition"
        ),
    )
    checksum = _mix(
        checksum,
        _run[_scenario_update_workload](
            "nr_redcap_rel17_measurement_scenario_update"
        ),
    )
    checksum = _mix(
        checksum,
        _run[_timing_transition_workload](
            "nr_redcap_rel17_timing_requirement_transition_update"
        ),
    )
    keep(checksum)
    print("nr_redcap_low_mobility_retained_checksum:", checksum)
