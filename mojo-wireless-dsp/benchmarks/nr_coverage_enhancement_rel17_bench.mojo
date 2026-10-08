"""Attributable CPU benchmarks for Rel-17 NR coverage enhancement.

Every public API has an independent ``@no_inline`` workload.  Decoded lists,
Span views, and mutable configuration fixtures are constructed before warmup
or timing.  List-returning APIs retain the complete owned result and feed only
an O(1) length/endpoint fingerprint into the checksum.  Each fixed workload is
also executed twice consecutively before timing and must return the same
checksum.
"""

from std.benchmark import black_box, keep
from std.collections import Span
from std.time import global_perf_counter_ns
from wireless_dsp.benchmarking import (
    print_benchmark_metadata,
    report_timing_samples,
)
from wireless_dsp.wireless.nr.coverage_enhancement_rel17 import (
    NR_COV_ENH_MAPPING_TYPE_B,
    NR_COV_ENH_CP_NORMAL,
    NR_COV_ENH_REPETITION_TYPE_B,
    NR_COV_ENH_SPECTRUM_UNPAIRED,
    NRCoverageEnhancementTBMSProfile,
    nr_cov_enh_rel17_valid_pusch_allocation,
    nr_cov_enh_rel17_msg3_repetition_count,
    nr_cov_enh_rel17_tbms_profile,
    nr_cov_enh_rel17_select_tbms_slots,
    nr_cov_enh_rel17_pusch_nominal_tdw_length_slots,
    nr_cov_enh_rel17_pusch_nominal_tdw_ids,
    nr_cov_enh_rel17_dmrs_bundling_gap_event,
)


comptime _WARMUPS = 3
comptime _SAMPLES = 9
comptime _SCALAR_BATCH = 4096
comptime _LIST_BATCH = 1024


def _mix(checksum: UInt64, value: Int) -> UInt64:
    return (checksum ^ UInt64(value + 4096)) * UInt64(1099511628211)


def _require_repeat(first: UInt64, second: UInt64) raises:
    if first != second:
        raise Error("coverage-enhancement fixed workload is nondeterministic")
    keep(first)
    keep(second)


@no_inline
def _valid_pusch_allocation_workload(iterations: Int) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for operation in range(iterations):
        var valid = nr_cov_enh_rel17_valid_pusch_allocation(
            black_box(NR_COV_ENH_MAPPING_TYPE_B),
            black_box(NR_COV_ENH_CP_NORMAL),
            black_box(NR_COV_ENH_REPETITION_TYPE_B),
            black_box(3),
            black_box(14),
        )
        checksum = _mix(checksum, (1 if valid else 0) + operation)
        keep(valid)
    return checksum


@no_inline
def _msg3_repetition_count_workload(
    iterations: Int, configured_repetitions: Span[Int, ...]
) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for operation in range(iterations):
        var count = nr_cov_enh_rel17_msg3_repetition_count(
            black_box(2), configured_repetitions
        )
        checksum = _mix(checksum, count + operation)
        keep(count)
    return checksum


@no_inline
def _tbms_profile_workload(iterations: Int) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for operation in range(iterations):
        var profile = nr_cov_enh_rel17_tbms_profile(
            black_box(4), black_box(2)
        )
        checksum = _mix(checksum, profile.number_of_slots + operation)
        checksum = _mix(checksum, profile.number_of_repetitions)
        checksum = _mix(checksum, profile.required_slot_count)
        keep(profile)
    return checksum


@no_inline
def _select_tbms_slots_workload(
    iterations: Int,
    eligibility: Span[UInt8, ...],
    profile: NRCoverageEnhancementTBMSProfile,
) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for operation in range(iterations):
        var slots = nr_cov_enh_rel17_select_tbms_slots(
            black_box(128),
            eligibility,
            black_box(profile),
            NR_COV_ENH_SPECTRUM_UNPAIRED,
        )
        var count = len(slots)
        checksum = _mix(checksum, count + operation)
        checksum = _mix(checksum, slots[0])
        checksum = _mix(checksum, slots[count - 1])
        keep(slots)
    return checksum


@no_inline
def _pusch_nominal_tdw_length_workload(iterations: Int) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for operation in range(iterations):
        var length = nr_cov_enh_rel17_pusch_nominal_tdw_length_slots(
            black_box(0), black_box(8), black_box(128), black_box(139)
        )
        checksum = _mix(checksum, length + operation)
        keep(length)
    return checksum


@no_inline
def _pusch_nominal_tdw_ids_workload(
    iterations: Int, selected_slots: Span[Int, ...]
) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for operation in range(iterations):
        var ids = nr_cov_enh_rel17_pusch_nominal_tdw_ids(
            selected_slots, black_box(3)
        )
        var count = len(ids)
        checksum = _mix(checksum, count + operation)
        checksum = _mix(checksum, ids[0])
        checksum = _mix(checksum, ids[count - 1])
        keep(ids)
    return checksum


@no_inline
def _dmrs_bundling_gap_event_workload(iterations: Int) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for operation in range(iterations):
        var event = nr_cov_enh_rel17_dmrs_bundling_gap_event(
            black_box(NR_COV_ENH_CP_NORMAL),
            black_box(13),
            black_box(True),
            black_box(True),
        )
        checksum = _mix(checksum, (1 if event else 0) + operation)
        keep(event)
    return checksum


def main() raises:
    # All decoded input containers, views, and configurations precede every
    # warmup and timed call.
    var configured_repetitions: List[Int] = [2, 4, 8, 16]
    var eligibility: List[UInt8] = [1, 0, 1, 1, 0, 1, 1, 1]
    var selected_slots: List[Int] = [128, 130, 131, 133]
    var configured_repetitions_span = Span(configured_repetitions)
    var eligibility_span = Span(eligibility)
    var selected_slots_span = Span(selected_slots)
    var selection_profile = nr_cov_enh_rel17_tbms_profile(2, 2)

    _require_repeat(
        _valid_pusch_allocation_workload(_SCALAR_BATCH),
        _valid_pusch_allocation_workload(_SCALAR_BATCH),
    )
    _require_repeat(
        _msg3_repetition_count_workload(
            _SCALAR_BATCH, configured_repetitions_span
        ),
        _msg3_repetition_count_workload(
            _SCALAR_BATCH, configured_repetitions_span
        ),
    )
    _require_repeat(
        _tbms_profile_workload(_SCALAR_BATCH),
        _tbms_profile_workload(_SCALAR_BATCH),
    )
    _require_repeat(
        _select_tbms_slots_workload(
            _LIST_BATCH, eligibility_span, selection_profile
        ),
        _select_tbms_slots_workload(
            _LIST_BATCH, eligibility_span, selection_profile
        ),
    )
    _require_repeat(
        _pusch_nominal_tdw_length_workload(_SCALAR_BATCH),
        _pusch_nominal_tdw_length_workload(_SCALAR_BATCH),
    )
    _require_repeat(
        _pusch_nominal_tdw_ids_workload(
            _LIST_BATCH, selected_slots_span
        ),
        _pusch_nominal_tdw_ids_workload(
            _LIST_BATCH, selected_slots_span
        ),
    )
    _require_repeat(
        _dmrs_bundling_gap_event_workload(_SCALAR_BATCH),
        _dmrs_bundling_gap_event_workload(_SCALAR_BATCH),
    )

    for _ in range(_WARMUPS):
        keep(_valid_pusch_allocation_workload(_SCALAR_BATCH))
        keep(
            _msg3_repetition_count_workload(
                _SCALAR_BATCH, configured_repetitions_span
            )
        )
        keep(_tbms_profile_workload(_SCALAR_BATCH))
        keep(
            _select_tbms_slots_workload(
                _LIST_BATCH, eligibility_span, selection_profile
            )
        )
        keep(_pusch_nominal_tdw_length_workload(_SCALAR_BATCH))
        keep(
            _pusch_nominal_tdw_ids_workload(
                _LIST_BATCH, selected_slots_span
            )
        )
        keep(_dmrs_bundling_gap_event_workload(_SCALAR_BATCH))

    var allocation_samples = List[UInt64](capacity=_SAMPLES)
    var msg3_samples = List[UInt64](capacity=_SAMPLES)
    var profile_samples = List[UInt64](capacity=_SAMPLES)
    var selection_samples = List[UInt64](capacity=_SAMPLES)
    var tdw_length_samples = List[UInt64](capacity=_SAMPLES)
    var tdw_ids_samples = List[UInt64](capacity=_SAMPLES)
    var gap_samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var start = global_perf_counter_ns()
        var allocation = _valid_pusch_allocation_workload(_SCALAR_BATCH)
        allocation_samples.append(global_perf_counter_ns() - start)
        checksum = (checksum ^ allocation) * UInt64(1099511628211)
        keep(allocation)

        start = global_perf_counter_ns()
        var msg3 = _msg3_repetition_count_workload(
            _SCALAR_BATCH, configured_repetitions_span
        )
        msg3_samples.append(global_perf_counter_ns() - start)
        checksum = (checksum ^ msg3) * UInt64(1099511628211)
        keep(msg3)

        start = global_perf_counter_ns()
        var profile = _tbms_profile_workload(_SCALAR_BATCH)
        profile_samples.append(global_perf_counter_ns() - start)
        checksum = (checksum ^ profile) * UInt64(1099511628211)
        keep(profile)

        start = global_perf_counter_ns()
        var selection = _select_tbms_slots_workload(
            _LIST_BATCH, eligibility_span, selection_profile
        )
        selection_samples.append(global_perf_counter_ns() - start)
        checksum = (checksum ^ selection) * UInt64(1099511628211)
        keep(selection)

        start = global_perf_counter_ns()
        var tdw_length = _pusch_nominal_tdw_length_workload(_SCALAR_BATCH)
        tdw_length_samples.append(global_perf_counter_ns() - start)
        checksum = (checksum ^ tdw_length) * UInt64(1099511628211)
        keep(tdw_length)

        start = global_perf_counter_ns()
        var tdw_ids = _pusch_nominal_tdw_ids_workload(
            _LIST_BATCH, selected_slots_span
        )
        tdw_ids_samples.append(global_perf_counter_ns() - start)
        checksum = (checksum ^ tdw_ids) * UInt64(1099511628211)
        keep(tdw_ids)

        start = global_perf_counter_ns()
        var gap = _dmrs_bundling_gap_event_workload(_SCALAR_BATCH)
        gap_samples.append(global_perf_counter_ns() - start)
        checksum = (checksum ^ gap) * UInt64(1099511628211)
        keep(gap)

    print_benchmark_metadata()
    print("nr_coverage_enhancement_backend: scalar-cpu-reference")
    report_timing_samples(
        "nr_cov_enh_rel17_valid_pusch_allocation",
        allocation_samples,
        _WARMUPS,
        _SCALAR_BATCH,
        "allocation",
    )
    report_timing_samples(
        "nr_cov_enh_rel17_msg3_repetition_count",
        msg3_samples,
        _WARMUPS,
        _SCALAR_BATCH,
        "codepoint",
    )
    report_timing_samples(
        "nr_cov_enh_rel17_tbms_profile",
        profile_samples,
        _WARMUPS,
        _SCALAR_BATCH,
        "configuration",
    )
    report_timing_samples(
        "nr_cov_enh_rel17_select_tbms_slots",
        selection_samples,
        _WARMUPS,
        _LIST_BATCH,
        "slot_selection",
    )
    report_timing_samples(
        "nr_cov_enh_rel17_pusch_nominal_tdw_length_slots",
        tdw_length_samples,
        _WARMUPS,
        _SCALAR_BATCH,
        "window",
    )
    report_timing_samples(
        "nr_cov_enh_rel17_pusch_nominal_tdw_ids",
        tdw_ids_samples,
        _WARMUPS,
        _LIST_BATCH,
        "assignment",
    )
    report_timing_samples(
        "nr_cov_enh_rel17_dmrs_bundling_gap_event",
        gap_samples,
        _WARMUPS,
        _SCALAR_BATCH,
        "gap",
    )
    keep(configured_repetitions)
    keep(eligibility)
    keep(selected_slots)
    keep(selection_profile)
    keep(checksum)
    print("nr_coverage_enhancement_retained_checksum:", checksum)
