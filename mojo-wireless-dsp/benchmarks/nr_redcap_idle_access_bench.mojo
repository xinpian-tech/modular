"""Attributable CPU timings for Rel-17 RedCap idle/access decisions."""

from std.benchmark import black_box, keep
from std.time import global_perf_counter_ns
from wireless_dsp.benchmarking import (
    print_benchmark_metadata,
    report_timing_samples,
)
from wireless_dsp.wireless.nr.redcap_idle_access import (
    NR_REDCAP_IDLE_ACCESS_RRC_IDLE,
    NR_REDCAP_IDLE_ACCESS_RRC_INACTIVE,
    NR_REDCAP_CANDIDATE_CURRENT_CELL,
    NR_REDCAP_CANDIDATE_SAME_FREQUENCY_PEER,
    NR_REDCAP_IDLE_ACCESS_EXCLUSION_MAX_US,
    NRRedCapIdleAccessContext,
    NRRedCapBarringPlan,
    NRRedCapBarringTimerState,
    nr_redcap_rel17_ifri_status,
    nr_redcap_rel17_matching_rx_barred,
    nr_redcap_rel17_sib1_barring_cause,
    nr_redcap_rel17_idle_inactive_barring_cause,
    nr_redcap_rel17_barring_plan,
    nr_redcap_rel17_start_barring_exclusions,
    nr_redcap_rel17_barring_exclusion_active,
    nr_redcap_rel17_candidate_allowed,
    nr_redcap_rel17_inter_frequency_candidate_allowed,
)


comptime _WARMUPS = 3
comptime _SAMPLES = 9
comptime _BATCH = 4096


def _mix(checksum: UInt64, value: Int) -> UInt64:
    return checksum * UInt64(1099511628211) ^ UInt64(value + 1)


@no_inline
def _ifri_workload(
    iterations: Int, salt: Int, mut context: NRRedCapIdleAccessContext
) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for iteration in range(iterations):
        context.intra_freq_reselection_redcap_allowed = (
            ((iteration + salt) & 1) == 0
        )
        var status = nr_redcap_rel17_ifri_status(black_box(context))
        checksum = _mix(checksum, status + iteration)
    return checksum


@no_inline
def _matching_rx_workload(
    iterations: Int, salt: Int, mut context: NRRedCapIdleAccessContext
) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for iteration in range(iterations):
        context.cell_barred_redcap_1rx = ((iteration + salt) & 1) == 0
        var barred = nr_redcap_rel17_matching_rx_barred(black_box(context))
        checksum = _mix(checksum, (1 if barred else 0) + iteration)
    return checksum


@no_inline
def _sib1_cause_workload(
    iterations: Int, salt: Int, mut context: NRRedCapIdleAccessContext
) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for iteration in range(iterations):
        context.cell_barred_redcap_2rx = ((iteration + salt) & 1) == 0
        var cause = nr_redcap_rel17_sib1_barring_cause(black_box(context))
        checksum = _mix(checksum, cause + iteration)
    return checksum


@no_inline
def _full_cause_workload(
    iterations: Int, salt: Int, mut context: NRRedCapIdleAccessContext
) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for iteration in range(iterations):
        context.mib_cell_barred = ((iteration + salt) & 1) == 0
        var cause = nr_redcap_rel17_idle_inactive_barring_cause(
            black_box(context)
        )
        checksum = _mix(checksum, cause + iteration)
    return checksum


@no_inline
def _plan_workload(
    iterations: Int, salt: Int, mut context: NRRedCapIdleAccessContext
) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for iteration in range(iterations):
        context.intra_freq_reselection_redcap_allowed = (
            ((iteration + salt) & 1) == 0
        )
        var plan = nr_redcap_rel17_barring_plan(black_box(context))
        checksum = _mix(
            checksum,
            plan.cause
                + plan.current_cell_exclusion_us
                + plan.same_frequency_exclusion_us
                + (1 if plan.same_frequency_candidate_allowed else 0),
        )
    return checksum


@no_inline
def _start_timer_workload(
    iterations: Int,
    salt: Int,
    plan: NRRedCapBarringPlan,
    mut state: NRRedCapBarringTimerState,
) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for iteration in range(iterations):
        var next_time = state.last_update_us + 1 + ((iteration + salt) & 1)
        var applied = nr_redcap_rel17_start_barring_exclusions(
            state, black_box(plan), black_box(next_time)
        )
        checksum = _mix(
            checksum,
            (1 if applied else 0)
                + state.current_cell_exclusion_duration_us
                + iteration,
        )
    return checksum


@no_inline
def _timer_query_workload(
    iterations: Int, salt: Int, state: NRRedCapBarringTimerState
) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for iteration in range(iterations):
        var elapsed = (
            NR_REDCAP_IDLE_ACCESS_EXCLUSION_MAX_US - 1
            if ((iteration + salt) & 1) == 0
            else NR_REDCAP_IDLE_ACCESS_EXCLUSION_MAX_US
        )
        var active = nr_redcap_rel17_barring_exclusion_active(
            black_box(state),
            black_box(state.last_update_us + elapsed),
            black_box(NR_REDCAP_CANDIDATE_CURRENT_CELL),
        )
        checksum = _mix(checksum, (1 if active else 0) + iteration)
    return checksum


@no_inline
def _candidate_workload(
    iterations: Int,
    salt: Int,
    context: NRRedCapIdleAccessContext,
    state: NRRedCapBarringTimerState,
) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for iteration in range(iterations):
        var scope = (
            NR_REDCAP_CANDIDATE_CURRENT_CELL
            if ((iteration + salt) & 1) == 0
            else NR_REDCAP_CANDIDATE_SAME_FREQUENCY_PEER
        )
        var allowed = nr_redcap_rel17_candidate_allowed(
            black_box(context),
            black_box(state),
            black_box(state.last_update_us),
            black_box(scope),
        )
        checksum = _mix(checksum, (1 if allowed else 0) + iteration)
    return checksum


@no_inline
def _inter_frequency_workload(
    iterations: Int, salt: Int, context: NRRedCapIdleAccessContext
) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for iteration in range(iterations):
        var selector = (iteration + salt) % 3
        var extension_present = selector != 0
        var allowed_present = selector == 2
        var allowed = nr_redcap_rel17_inter_frequency_candidate_allowed(
            black_box(context),
            inter_freq_carrier_v1700_present=black_box(extension_present),
            redcap_access_allowed_present=black_box(allowed_present),
        )
        checksum = _mix(checksum, (1 if allowed else 0) + iteration)
    return checksum


def main() raises:
    var ifri_context = NRRedCapIdleAccessContext(
        NR_REDCAP_IDLE_ACCESS_RRC_IDLE, 1
    )
    var one_rx_context = NRRedCapIdleAccessContext(
        NR_REDCAP_IDLE_ACCESS_RRC_IDLE,
        1,
        rx_specific_barring_present=True,
    )
    var two_rx_context = NRRedCapIdleAccessContext(
        NR_REDCAP_IDLE_ACCESS_RRC_INACTIVE,
        2,
        rx_specific_barring_present=True,
    )
    var cause_context = NRRedCapIdleAccessContext(
        NR_REDCAP_IDLE_ACCESS_RRC_IDLE, 1
    )
    var plan_context = NRRedCapIdleAccessContext(
        NR_REDCAP_IDLE_ACCESS_RRC_IDLE,
        1,
        mib_cell_barred=True,
        intra_freq_reselection_redcap_allowed=False,
    )
    var fixed_plan = nr_redcap_rel17_barring_plan(plan_context)
    var timer_state = NRRedCapBarringTimerState(0)
    var query_state = NRRedCapBarringTimerState(1000000)
    _ = nr_redcap_rel17_start_barring_exclusions(
        query_state, fixed_plan, 1000000
    )
    var clean_context = NRRedCapIdleAccessContext(
        NR_REDCAP_IDLE_ACCESS_RRC_INACTIVE, 2
    )
    var clean_state = NRRedCapBarringTimerState(0)

    for _ in range(_WARMUPS):
        var salt = 324508639
        keep(_ifri_workload(_BATCH, salt, ifri_context))
        keep(_matching_rx_workload(_BATCH, salt, one_rx_context))
        keep(_sib1_cause_workload(_BATCH, salt, two_rx_context))
        keep(_full_cause_workload(_BATCH, salt, cause_context))
        keep(_plan_workload(_BATCH, salt, plan_context))
        keep(_start_timer_workload(_BATCH, salt, fixed_plan, timer_state))
        keep(_timer_query_workload(_BATCH, salt, query_state))
        keep(_candidate_workload(_BATCH, salt, clean_context, clean_state))
        keep(_inter_frequency_workload(_BATCH, salt, clean_context))

    var ifri_samples = List[UInt64](capacity=_SAMPLES)
    var matching_samples = List[UInt64](capacity=_SAMPLES)
    var sib1_cause_samples = List[UInt64](capacity=_SAMPLES)
    var full_cause_samples = List[UInt64](capacity=_SAMPLES)
    var plan_samples = List[UInt64](capacity=_SAMPLES)
    var start_samples = List[UInt64](capacity=_SAMPLES)
    var query_samples = List[UInt64](capacity=_SAMPLES)
    var candidate_samples = List[UInt64](capacity=_SAMPLES)
    var inter_frequency_samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)

    for _ in range(_SAMPLES):
        var salt = 324508639
        var start = global_perf_counter_ns()
        var value = _ifri_workload(_BATCH, salt, ifri_context)
        ifri_samples.append(global_perf_counter_ns() - start)
        checksum = checksum * UInt64(1099511628211) ^ value
        keep(value)

        start = global_perf_counter_ns()
        value = _matching_rx_workload(_BATCH, salt, one_rx_context)
        matching_samples.append(global_perf_counter_ns() - start)
        checksum = checksum * UInt64(1099511628211) ^ value
        keep(value)

        start = global_perf_counter_ns()
        value = _sib1_cause_workload(_BATCH, salt, two_rx_context)
        sib1_cause_samples.append(global_perf_counter_ns() - start)
        checksum = checksum * UInt64(1099511628211) ^ value
        keep(value)

        start = global_perf_counter_ns()
        value = _full_cause_workload(_BATCH, salt, cause_context)
        full_cause_samples.append(global_perf_counter_ns() - start)
        checksum = checksum * UInt64(1099511628211) ^ value
        keep(value)

        start = global_perf_counter_ns()
        value = _plan_workload(_BATCH, salt, plan_context)
        plan_samples.append(global_perf_counter_ns() - start)
        checksum = checksum * UInt64(1099511628211) ^ value
        keep(value)

        start = global_perf_counter_ns()
        value = _start_timer_workload(_BATCH, salt, fixed_plan, timer_state)
        start_samples.append(global_perf_counter_ns() - start)
        checksum = checksum * UInt64(1099511628211) ^ value
        keep(value)

        start = global_perf_counter_ns()
        value = _timer_query_workload(_BATCH, salt, query_state)
        query_samples.append(global_perf_counter_ns() - start)
        checksum = checksum * UInt64(1099511628211) ^ value
        keep(value)

        start = global_perf_counter_ns()
        value = _candidate_workload(
            _BATCH, salt, clean_context, clean_state
        )
        candidate_samples.append(global_perf_counter_ns() - start)
        checksum = checksum * UInt64(1099511628211) ^ value
        keep(value)

        start = global_perf_counter_ns()
        value = _inter_frequency_workload(_BATCH, salt, clean_context)
        inter_frequency_samples.append(global_perf_counter_ns() - start)
        checksum = checksum * UInt64(1099511628211) ^ value
        keep(value)

    print_benchmark_metadata()
    print("nr_redcap_idle_access_backend: scalar-cpu-reference")
    report_timing_samples(
        "nr_redcap_rel17_ifri_status",
        ifri_samples,
        _WARMUPS,
        _BATCH,
        "decoded_sib1_ifri_projection",
    )
    report_timing_samples(
        "nr_redcap_rel17_matching_rx_barred",
        matching_samples,
        _WARMUPS,
        _BATCH,
        "matching_rx_barring_decision",
    )
    report_timing_samples(
        "nr_redcap_rel17_sib1_barring_cause",
        sib1_cause_samples,
        _WARMUPS,
        _BATCH,
        "ordered_sib1_barring_cause",
    )
    report_timing_samples(
        "nr_redcap_rel17_idle_inactive_barring_cause",
        full_cause_samples,
        _WARMUPS,
        _BATCH,
        "mib_sib1_barring_composition",
    )
    report_timing_samples(
        "nr_redcap_rel17_barring_plan",
        plan_samples,
        _WARMUPS,
        _BATCH,
        "candidate_and_exclusion_plan",
    )
    report_timing_samples(
        "nr_redcap_rel17_start_barring_exclusions",
        start_samples,
        _WARMUPS,
        _BATCH,
        "barring_timer_start",
    )
    report_timing_samples(
        "nr_redcap_rel17_barring_exclusion_active",
        query_samples,
        _WARMUPS,
        _BATCH,
        "barring_timer_query",
    )
    report_timing_samples(
        "nr_redcap_rel17_candidate_allowed",
        candidate_samples,
        _WARMUPS,
        _BATCH,
        "composed_candidate_decision",
    )
    report_timing_samples(
        "nr_redcap_rel17_inter_frequency_candidate_allowed",
        inter_frequency_samples,
        _WARMUPS,
        _BATCH,
        "sib4_redcap_frequency_gate",
    )
    print("nr_redcap_idle_access_retained_checksum:", checksum)
