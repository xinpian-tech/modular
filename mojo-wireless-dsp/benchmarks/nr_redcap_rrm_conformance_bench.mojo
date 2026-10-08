"""Attributable CPU timings for bounded TS 38.533 RedCap verdict APIs.

Each public API has an independent ``@no_inline`` fixed-input workload.
Every mutable state consumed by ``update`` or ``start_next_phase`` is fully
constructed in a run-specific fixture bank before warmup or timing; no state
constructor or template copy is timed.  Returned rows and mutated states are
retained with O(1) field fingerprints.  Consecutive untimed executions over
equivalent fixed fixtures must produce identical checksums.
"""

from std.benchmark import black_box, keep
from std.time import global_perf_counter_ns
from wireless_dsp.benchmarking import (
    print_benchmark_metadata,
    report_timing_samples,
)
from wireless_dsp.wireless.nr.redcap_rrm_conformance import (
    NR_REDCAP_RRM_CONFORMANCE_TC_16_1_1_1,
    NR_REDCAP_RRM_CONFORMANCE_TC_18_2_2_1,
    NR_REDCAP_RRM_CONFORMANCE_VERDICT_PASS,
    NRRedCapRRMConformanceRow,
    NRRedCapRRMConformanceState,
    nr_redcap_rel17_rrm_conformance_row,
    nr_redcap_rel17_rrm_conformance_delay_verdict,
    nr_redcap_rel17_rrm_conformance_update,
    nr_redcap_rel17_rrm_conformance_start_next_phase,
)


comptime _WARMUPS = 3
comptime _SAMPLES = 9
comptime _BATCH = 4096
comptime _STATE_RUNS = 2 + _WARMUPS + _SAMPLES


def _mix(checksum: UInt64, value: Int) -> UInt64:
    return (checksum ^ UInt64(value + 4096)) * UInt64(1099511628211)


def _require_repeat(first: UInt64, second: UInt64) raises:
    if first != second:
        raise Error("RedCap RRM fixed workload is nondeterministic")
    keep(first)
    keep(second)


def _build_update_states() raises -> List[NRRedCapRRMConformanceState]:
    var states = List[NRRedCapRRMConformanceState](
        capacity=_STATE_RUNS * _BATCH
    )
    for _ in range(_STATE_RUNS * _BATCH):
        states.append(
            NRRedCapRRMConformanceState(
                NR_REDCAP_RRM_CONFORMANCE_TC_18_2_2_1, 0
            )
        )
    return states^


def _build_awaiting_states() raises -> List[NRRedCapRRMConformanceState]:
    var states = List[NRRedCapRRMConformanceState](
        capacity=_STATE_RUNS * _BATCH
    )
    for _ in range(_STATE_RUNS * _BATCH):
        var state = NRRedCapRRMConformanceState(
            NR_REDCAP_RRM_CONFORMANCE_TC_16_1_1_1, 0
        )
        var verdict = nr_redcap_rel17_rrm_conformance_update(
            state, 1, True, 2
        )
        if verdict != NR_REDCAP_RRM_CONFORMANCE_VERDICT_PASS:
            raise Error("unexpected RedCap benchmark fixture verdict")
        states.append(state)
    return states^


@no_inline
def _row_workload(
    iterations: Int, test_case: Int, phase_index: Int
) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for operation in range(iterations):
        var row = nr_redcap_rel17_rrm_conformance_row(
            black_box(test_case), black_box(phase_index)
        )
        checksum = _mix(checksum, row.strict_limit_us + operation)
        checksum = _mix(checksum, row.expected_cell)
        checksum = _mix(checksum, row.test_period)
        checksum = _mix(checksum, row.event_kind)
        keep(row)
    return checksum


@no_inline
def _verdict_workload(
    iterations: Int,
    row: NRRedCapRRMConformanceRow,
    response_seen: Bool,
    observed_cell: Int,
    delay_ms: Float64,
) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for operation in range(iterations):
        var verdict = nr_redcap_rel17_rrm_conformance_delay_verdict(
            black_box(row),
            black_box(response_seen),
            black_box(observed_cell),
            black_box(delay_ms),
        )
        checksum = _mix(checksum, verdict + operation)
        keep(verdict)
    return checksum


@no_inline
def _update_workload(
    iterations: Int,
    start_index: Int,
    mut states: List[NRRedCapRRMConformanceState],
) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for operation in range(iterations):
        var index = start_index + operation
        var verdict = nr_redcap_rel17_rrm_conformance_update(
            states[index], black_box(1), black_box(True), black_box(1)
        )
        checksum = _mix(checksum, verdict + operation)
        checksum = _mix(checksum, states[index].state)
        checksum = _mix(checksum, states[index].phase_index)
    return checksum


@no_inline
def _start_next_phase_workload(
    iterations: Int,
    start_index: Int,
    mut states: List[NRRedCapRRMConformanceState],
) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for operation in range(iterations):
        var index = start_index + operation
        var active_state = nr_redcap_rel17_rrm_conformance_start_next_phase(
            states[index], black_box(2)
        )
        checksum = _mix(checksum, active_state + operation)
        checksum = _mix(checksum, states[index].phase_index)
        checksum = _mix(checksum, states[index].phase_started_us)
    return checksum


def main() raises:
    # All row and state fixtures, including every run-specific mutable state,
    # are complete before any workload invocation.
    var row_test_case = NR_REDCAP_RRM_CONFORMANCE_TC_18_2_2_1
    var row_phase_index = 0
    var verdict_row = nr_redcap_rel17_rrm_conformance_row(
        row_test_case, row_phase_index
    )
    var response_seen = True
    var observed_cell = 2
    var delay_ms = 2239.999
    var update_states = _build_update_states()
    var awaiting_states = _build_awaiting_states()
    var state_run = 0

    _require_repeat(
        _row_workload(_BATCH, row_test_case, row_phase_index),
        _row_workload(_BATCH, row_test_case, row_phase_index),
    )
    _require_repeat(
        _verdict_workload(
            _BATCH,
            verdict_row,
            response_seen,
            observed_cell,
            delay_ms,
        ),
        _verdict_workload(
            _BATCH,
            verdict_row,
            response_seen,
            observed_cell,
            delay_ms,
        ),
    )
    var update_first = _update_workload(
        _BATCH, state_run * _BATCH, update_states
    )
    var phase_first = _start_next_phase_workload(
        _BATCH, state_run * _BATCH, awaiting_states
    )
    state_run += 1
    var update_second = _update_workload(
        _BATCH, state_run * _BATCH, update_states
    )
    var phase_second = _start_next_phase_workload(
        _BATCH, state_run * _BATCH, awaiting_states
    )
    state_run += 1
    _require_repeat(update_first, update_second)
    _require_repeat(phase_first, phase_second)
    keep(update_states[0])
    keep(awaiting_states[0])

    for _ in range(_WARMUPS):
        keep(_row_workload(_BATCH, row_test_case, row_phase_index))
        keep(
            _verdict_workload(
                _BATCH,
                verdict_row,
                response_seen,
                observed_cell,
                delay_ms,
            )
        )
        keep(
            _update_workload(
                _BATCH, state_run * _BATCH, update_states
            )
        )
        keep(update_states[state_run * _BATCH])
        keep(
            _start_next_phase_workload(
                _BATCH, state_run * _BATCH, awaiting_states
            )
        )
        keep(awaiting_states[state_run * _BATCH])
        state_run += 1

    var row_samples = List[UInt64](capacity=_SAMPLES)
    var verdict_samples = List[UInt64](capacity=_SAMPLES)
    var update_samples = List[UInt64](capacity=_SAMPLES)
    var start_samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var start = global_perf_counter_ns()
        var row_value = _row_workload(
            _BATCH, row_test_case, row_phase_index
        )
        row_samples.append(global_perf_counter_ns() - start)
        checksum = (checksum ^ row_value) * UInt64(1099511628211)
        keep(row_value)

        start = global_perf_counter_ns()
        var verdict_value = _verdict_workload(
            _BATCH,
            verdict_row,
            response_seen,
            observed_cell,
            delay_ms,
        )
        verdict_samples.append(global_perf_counter_ns() - start)
        checksum = (checksum ^ verdict_value) * UInt64(1099511628211)
        keep(verdict_value)

        var state_offset = state_run * _BATCH
        start = global_perf_counter_ns()
        var update_value = _update_workload(
            _BATCH, state_offset, update_states
        )
        update_samples.append(global_perf_counter_ns() - start)
        checksum = (checksum ^ update_value) * UInt64(1099511628211)
        keep(update_value)
        keep(update_states[state_offset])

        start = global_perf_counter_ns()
        var phase_value = _start_next_phase_workload(
            _BATCH, state_offset, awaiting_states
        )
        start_samples.append(global_perf_counter_ns() - start)
        checksum = (checksum ^ phase_value) * UInt64(1099511628211)
        keep(phase_value)
        keep(awaiting_states[state_offset])
        state_run += 1

    if state_run != _STATE_RUNS:
        raise Error("RedCap benchmark state fixture accounting mismatch")

    print_benchmark_metadata()
    print("nr_redcap_rrm_conformance_backend: scalar-cpu-reference")
    report_timing_samples(
        "nr_redcap_rel17_rrm_conformance_row",
        row_samples,
        _WARMUPS,
        _BATCH,
        "exact_phase_row_lookup",
    )
    report_timing_samples(
        "nr_redcap_rel17_rrm_conformance_delay_verdict",
        verdict_samples,
        _WARMUPS,
        _BATCH,
        "float_delay_verdict",
    )
    report_timing_samples(
        "nr_redcap_rel17_rrm_conformance_update",
        update_samples,
        _WARMUPS,
        _BATCH,
        "validated_state_update",
    )
    report_timing_samples(
        "nr_redcap_rel17_rrm_conformance_start_next_phase",
        start_samples,
        _WARMUPS,
        _BATCH,
        "validated_awaiting_state_phase_start",
    )
    keep(verdict_row)
    keep(update_states)
    keep(awaiting_states)
    keep(checksum)
    print("nr_redcap_rrm_conformance_retained_checksum:", checksum)
