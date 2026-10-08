"""Attributable CPU timings for bounded Rel-17 RedCap MAC algorithms."""

from std.benchmark import black_box, keep
from std.time import global_perf_counter_ns
from wireless_dsp.benchmarking import (
    print_benchmark_metadata,
    report_timing_samples,
)
from wireless_dsp.wireless.nr.redcap_mac import (
    NR_REDCAP_RA_FEATURE_REDCAP,
    NR_REDCAP_RA_FEATURE_SLICING,
    NR_REDCAP_RA_FEATURE_SMALL_DATA,
    NR_REDCAP_RA_FEATURE_MSG3_REPETITION,
    NR_REDCAP_RA_TYPE_4_STEP,
    NR_REDCAP_RA_TYPE_2_STEP,
    nr_redcap_rel17_msg3_repetition_applicable,
    nr_redcap_rel17_ra_resource_set_available,
    nr_redcap_rel17_select_ra_resource_set_group,
    nr_redcap_rel17_select_ra_resource_set,
    nr_redcap_rel17_random_access_uplink_bwp_source,
    nr_redcap_rel17_random_access_downlink_bwp_source,
    nr_redcap_rel17_bwp_inactivity_target,
    nr_redcap_rel17_ul_ccch_lcid,
)


comptime _WARMUPS = 3
comptime _SAMPLES = 9
comptime _BATCH = 4096


def _mix(checksum: UInt64, value: Int) -> UInt64:
    return (checksum ^ UInt64(value + 1)) * UInt64(1099511628211)


@no_inline
def _msg3_applicability_workload(iterations: Int, salt: Int) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for iteration in range(iterations):
        var selector = (iteration + salt) & 3
        var repetition_sets = selector != 1
        var non_repetition_sets = selector != 0
        var rsrp = -101.0 if selector == 2 else -100.0
        var result = nr_redcap_rel17_msg3_repetition_applicable(
            black_box(repetition_sets),
            black_box(non_repetition_sets),
            black_box(rsrp),
            black_box(-100.0),
        )
        checksum = _mix(checksum, (1 if result else 0) + iteration)
    return checksum


@no_inline
def _availability_workload(iterations: Int, salt: Int) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for iteration in range(iterations):
        var selector = (iteration + salt) % 6
        var configured = NR_REDCAP_RA_FEATURE_REDCAP
        var applicable = NR_REDCAP_RA_FEATURE_REDCAP
        var nsag_list_configured = False
        var nsag_matches = False
        if selector == 1 or selector == 2:
            configured = NR_REDCAP_RA_FEATURE_SLICING
            applicable = NR_REDCAP_RA_FEATURE_SLICING
            nsag_list_configured = True
            nsag_matches = selector == 1
        elif selector == 3:
            configured = NR_REDCAP_RA_FEATURE_SMALL_DATA
            applicable = NR_REDCAP_RA_FEATURE_SMALL_DATA
        elif selector == 4:
            configured = NR_REDCAP_RA_FEATURE_MSG3_REPETITION
            applicable = 0
        elif selector == 5:
            configured = 0
            applicable = 0
        var result = nr_redcap_rel17_ra_resource_set_available(
            black_box(configured),
            black_box(applicable),
            nsag_list_configured=black_box(nsag_list_configured),
            nsag_matches=black_box(nsag_matches),
        )
        checksum = _mix(checksum, (1 if result else 0) + iteration)
    return checksum


@no_inline
def _group_selection_workload(
    iterations: Int,
    masks: Span[Int, ...],
    ra_types: Span[Int, ...],
    available: Span[UInt8, ...],
    priorities: Span[Int, ...],
) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for iteration in range(iterations):
        var selected = nr_redcap_rel17_select_ra_resource_set_group(
            black_box(masks),
            black_box(ra_types),
            black_box(available),
            black_box(
                NR_REDCAP_RA_FEATURE_REDCAP
                | NR_REDCAP_RA_FEATURE_SLICING
                | NR_REDCAP_RA_FEATURE_SMALL_DATA
            ),
            black_box(priorities),
        )
        checksum = _mix(
            checksum,
            selected.configured_features
            + selected.four_step_index
            + selected.two_step_index
            + iteration,
        )
    return checksum


@no_inline
def _single_selection_workload(
    iterations: Int,
    masks: Span[Int, ...],
    available: Span[UInt8, ...],
    priorities: Span[Int, ...],
) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for iteration in range(iterations):
        var selected = nr_redcap_rel17_select_ra_resource_set(
            black_box(masks),
            black_box(available),
            black_box(
                NR_REDCAP_RA_FEATURE_REDCAP
                | NR_REDCAP_RA_FEATURE_SMALL_DATA
            ),
            black_box(priorities),
        )
        checksum = _mix(checksum, selected + iteration)
    return checksum


@no_inline
def _uplink_bwp_workload(iterations: Int, salt: Int) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for iteration in range(iterations):
        var value = nr_redcap_rel17_random_access_uplink_bwp_source(
            black_box(((iteration + salt) & 1) == 0)
        )
        checksum = _mix(checksum, value + iteration)
    return checksum


@no_inline
def _downlink_bwp_workload(iterations: Int, salt: Int) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for iteration in range(iterations):
        var use_exception = ((iteration + salt) & 1) == 0
        var value = nr_redcap_rel17_random_access_downlink_bwp_source(
            black_box(True),
            si_request=black_box(use_exception),
            explicit_si_request_resources=black_box(use_exception),
            # The other half deliberately covers valid non-SI SUL selection.
            selected_sul_carrier=black_box(True),
        )
        checksum = _mix(checksum, value + iteration)
    return checksum


@no_inline
def _inactivity_workload(iterations: Int, salt: Int) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for iteration in range(iterations):
        var selector = (iteration + salt) % 3
        var value = nr_redcap_rel17_bwp_inactivity_target(
            black_box(selector == 0), black_box(selector != 2)
        )
        checksum = _mix(checksum, value + iteration)
    return checksum


@no_inline
def _ccch_lcid_workload(iterations: Int, salt: Int) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for iteration in range(iterations):
        var payload_bits = 48 if ((iteration + salt) & 1) == 0 else 64
        var value = nr_redcap_rel17_ul_ccch_lcid(black_box(payload_bits))
        checksum = _mix(checksum, value + iteration)
    return checksum


def main() raises:
    # This valid configuration has one set per (RA type, combination), no
    # all-feature combination, and requires two levels of clause-5.1.1d
    # filtering.  Both RA-type members of the winning combination are live.
    var group_masks: List[Int] = [
        0,
        0,
        NR_REDCAP_RA_FEATURE_REDCAP | NR_REDCAP_RA_FEATURE_SLICING,
        NR_REDCAP_RA_FEATURE_REDCAP | NR_REDCAP_RA_FEATURE_SLICING,
        NR_REDCAP_RA_FEATURE_REDCAP | NR_REDCAP_RA_FEATURE_SMALL_DATA,
        NR_REDCAP_RA_FEATURE_REDCAP | NR_REDCAP_RA_FEATURE_SMALL_DATA,
        NR_REDCAP_RA_FEATURE_SLICING | NR_REDCAP_RA_FEATURE_SMALL_DATA,
        NR_REDCAP_RA_FEATURE_SLICING | NR_REDCAP_RA_FEATURE_SMALL_DATA,
        NR_REDCAP_RA_FEATURE_REDCAP,
        NR_REDCAP_RA_FEATURE_REDCAP,
    ]
    var group_ra_types: List[Int] = [
        NR_REDCAP_RA_TYPE_4_STEP,
        NR_REDCAP_RA_TYPE_2_STEP,
        NR_REDCAP_RA_TYPE_4_STEP,
        NR_REDCAP_RA_TYPE_2_STEP,
        NR_REDCAP_RA_TYPE_4_STEP,
        NR_REDCAP_RA_TYPE_2_STEP,
        NR_REDCAP_RA_TYPE_4_STEP,
        NR_REDCAP_RA_TYPE_2_STEP,
        NR_REDCAP_RA_TYPE_4_STEP,
        NR_REDCAP_RA_TYPE_2_STEP,
    ]
    var group_available = List[UInt8](length=len(group_masks), fill=1)
    var group_priorities: List[Int] = [
        NR_REDCAP_RA_FEATURE_REDCAP,
        NR_REDCAP_RA_FEATURE_SLICING,
        NR_REDCAP_RA_FEATURE_SMALL_DATA,
    ]
    var single_masks: List[Int] = [
        0, NR_REDCAP_RA_FEATURE_REDCAP, NR_REDCAP_RA_FEATURE_SMALL_DATA
    ]
    var single_available: List[UInt8] = [1, 1, 1]
    var single_priorities: List[Int] = [
        NR_REDCAP_RA_FEATURE_REDCAP, NR_REDCAP_RA_FEATURE_SMALL_DATA
    ]

    for _ in range(_WARMUPS):
        var salt = 324508639
        keep(_msg3_applicability_workload(_BATCH, salt))
        keep(_availability_workload(_BATCH, salt))
        keep(_group_selection_workload(
            _BATCH,
            Span(group_masks),
            Span(group_ra_types),
            Span(group_available),
            Span(group_priorities),
        ))
        keep(_single_selection_workload(
            _BATCH,
            Span(single_masks),
            Span(single_available),
            Span(single_priorities),
        ))
        keep(_uplink_bwp_workload(_BATCH, salt))
        keep(_downlink_bwp_workload(_BATCH, salt))
        keep(_inactivity_workload(_BATCH, salt))
        keep(_ccch_lcid_workload(_BATCH, salt))

    var msg3_samples = List[UInt64](capacity=_SAMPLES)
    var availability_samples = List[UInt64](capacity=_SAMPLES)
    var group_selection_samples = List[UInt64](capacity=_SAMPLES)
    var single_selection_samples = List[UInt64](capacity=_SAMPLES)
    var uplink_samples = List[UInt64](capacity=_SAMPLES)
    var downlink_samples = List[UInt64](capacity=_SAMPLES)
    var inactivity_samples = List[UInt64](capacity=_SAMPLES)
    var lcid_samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var salt = 324508639
        var start = global_perf_counter_ns()
        var result = _msg3_applicability_workload(_BATCH, salt)
        msg3_samples.append(global_perf_counter_ns() - start)
        checksum ^= result

        start = global_perf_counter_ns()
        result = _availability_workload(_BATCH, salt)
        availability_samples.append(global_perf_counter_ns() - start)
        checksum ^= result

        start = global_perf_counter_ns()
        result = _group_selection_workload(
            _BATCH,
            Span(group_masks),
            Span(group_ra_types),
            Span(group_available),
            Span(group_priorities),
        )
        group_selection_samples.append(global_perf_counter_ns() - start)
        checksum ^= result

        start = global_perf_counter_ns()
        result = _single_selection_workload(
            _BATCH,
            Span(single_masks),
            Span(single_available),
            Span(single_priorities),
        )
        single_selection_samples.append(global_perf_counter_ns() - start)
        checksum ^= result

        start = global_perf_counter_ns()
        result = _uplink_bwp_workload(_BATCH, salt)
        uplink_samples.append(global_perf_counter_ns() - start)
        checksum ^= result

        start = global_perf_counter_ns()
        result = _downlink_bwp_workload(_BATCH, salt)
        downlink_samples.append(global_perf_counter_ns() - start)
        checksum ^= result

        start = global_perf_counter_ns()
        result = _inactivity_workload(_BATCH, salt)
        inactivity_samples.append(global_perf_counter_ns() - start)
        checksum ^= result

        start = global_perf_counter_ns()
        result = _ccch_lcid_workload(_BATCH, salt)
        lcid_samples.append(global_perf_counter_ns() - start)
        checksum ^= result

    print_benchmark_metadata()
    print("nr_redcap_mac_backend: scalar-cpu-reference")
    report_timing_samples(
        "nr_redcap_msg3_repetition_applicable",
        msg3_samples,
        _WARMUPS,
        _BATCH,
        "decoded_applicability",
    )
    report_timing_samples(
        "nr_redcap_ra_resource_set_available",
        availability_samples,
        _WARMUPS,
        _BATCH,
        "decoded_resource_set",
    )
    report_timing_samples(
        "nr_redcap_select_ra_resource_set_group",
        group_selection_samples,
        _WARMUPS,
        _BATCH,
        "decoded_group_selection",
    )
    report_timing_samples(
        "nr_redcap_select_ra_resource_set_single_type",
        single_selection_samples,
        _WARMUPS,
        _BATCH,
        "decoded_selection",
    )
    report_timing_samples(
        "nr_redcap_random_access_uplink_bwp",
        uplink_samples,
        _WARMUPS,
        _BATCH,
        "decoded_bwp_decision",
    )
    report_timing_samples(
        "nr_redcap_random_access_downlink_bwp",
        downlink_samples,
        _WARMUPS,
        _BATCH,
        "decoded_bwp_decision",
    )
    report_timing_samples(
        "nr_redcap_bwp_inactivity_target",
        inactivity_samples,
        _WARMUPS,
        _BATCH,
        "decoded_bwp_decision",
    )
    report_timing_samples(
        "nr_redcap_ul_ccch_lcid",
        lcid_samples,
        _WARMUPS,
        _BATCH,
        "decoded_ccch_mapping",
    )
    keep(checksum)
    print("nr_redcap_mac_retained_checksum:", checksum)
