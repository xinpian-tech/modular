"""Attributable CPU timings for Rel-17 RedCap HD-FDD decisions."""

from std.benchmark import black_box, keep
from std.time import global_perf_counter_ns
from wireless_dsp.benchmarking import (
    print_benchmark_metadata,
    report_timing_samples,
)
from wireless_dsp.wireless.nr.redcap_hd_fdd import (
    NR_REDCAP_HD_FDD_UPLINK_PUSCH_PUCCH,
    NR_REDCAP_HD_FDD_RA_POLICY_AMBIGUOUS,
    NR_REDCAP_HD_FDD_RA_TRIGGER_DCI_PRACH,
    NR_REDCAP_HD_FDD_RA_TRIGGER_HIGHER_LAYER_PRACH,
    NR_REDCAP_HD_FDD_RA_TRIGGER_HIGHER_LAYER_MSGA_PUSCH,
    NR_REDCAP_HD_PUSCH_TIMING_CAPABILITY_1,
    NR_REDCAP_HD_PUSCH_TIMING_CAPABILITY_2,
    NR_REDCAP_HD_PUSCH_TYPE_A_DCI_0_1_0_2,
    NR_REDCAP_HD_PUSCH_TYPE_A_CONFIGURED_GRANT,
    NR_REDCAP_HD_PUSCH_TYPE_A_RAR_OR_TC_RNTI,
    nr_redcap_rel17_clause_6_4_n2_twice_symbols,
    nr_redcap_rel17_clause_6_4_t_proc2_tc,
    nr_redcap_rel17_hd_t_proc2_tc,
    nr_redcap_rel17_hd_validate_schedule_overlap,
    nr_redcap_rel17_hd_configured_downlink_action,
    nr_redcap_rel17_hd_configured_uplink_action,
    nr_redcap_rel17_hd_ssb_guard_action,
    nr_redcap_rel17_hd_ra_conflict_category,
    nr_redcap_rel17_hd_ra_action,
    nr_redcap_rel17_hd_higher_layer_ra_action,
    nr_redcap_rel17_hd_tbms_required_slot_count,
    nr_redcap_rel17_hd_select_pusch_slots,
    nr_redcap_rel17_hd_dmrs_bundling_window_ids,
)


comptime _WARMUPS = 3
comptime _SAMPLES = 9
comptime _SCALAR_BATCH = 4096
comptime _LIST_BATCH = 1024


def _int_list_checksum(values: List[Int]) -> UInt64:
    var checksum = UInt64(len(values) + 1)
    for index in range(len(values)):
        checksum = (
            checksum * UInt64(1099511628211)
            ^ UInt64(values[index] + 2 + 17 * index)
        )
    return checksum


@no_inline
def _n2_workload(iterations: Int, salt: Int) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for iteration in range(iterations):
        var row = (iteration + salt) % 9
        var capability = NR_REDCAP_HD_PUSCH_TIMING_CAPABILITY_1
        var mu = 0
        if row == 1:
            mu = 1
        elif row == 2:
            mu = 2
        elif row == 3:
            mu = 3
        elif row == 4:
            mu = 5
        elif row == 5:
            mu = 6
        elif row >= 6:
            capability = NR_REDCAP_HD_PUSCH_TIMING_CAPABILITY_2
            mu = row - 6
        var value = nr_redcap_rel17_clause_6_4_n2_twice_symbols(
            black_box(capability), black_box(mu)
        )
        checksum = checksum * UInt64(1099511628211) ^ UInt64(
            value + iteration
        )
    return checksum


@no_inline
def _t_proc2_workload(iterations: Int, salt: Int) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for iteration in range(iterations):
        var value = nr_redcap_rel17_clause_6_4_t_proc2_tc(
            black_box(NR_REDCAP_HD_PUSCH_TIMING_CAPABILITY_1),
            black_box((iteration + salt) % 3),
            black_box((iteration + salt + 1) % 3),
            first_symbol_dmrs_only=black_box((iteration & 1) == 0),
            d2_symbols=black_box(iteration & 1),
            text_tc=black_box(iteration & 7),
            switching_gap_tc=black_box((iteration + 3) & 7),
        )
        checksum = checksum * UInt64(1099511628211) ^ UInt64(
            value + iteration
        )
    return checksum


@no_inline
def _hd_t_proc2_workload(iterations: Int, salt: Int) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for iteration in range(iterations):
        var value = nr_redcap_rel17_hd_t_proc2_tc(
            black_box((iteration + salt) % 3),
            black_box((iteration + salt + 2) % 3),
        )
        checksum = checksum * UInt64(1099511628211) ^ UInt64(
            value + iteration
        )
    return checksum


@no_inline
def _ra_category_workload(iterations: Int, salt: Int) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for iteration in range(iterations):
        var selector = (iteration + salt) % 3
        var trigger = NR_REDCAP_HD_FDD_RA_TRIGGER_DCI_PRACH
        if selector == 1:
            trigger = NR_REDCAP_HD_FDD_RA_TRIGGER_HIGHER_LAYER_PRACH
        elif selector == 2:
            trigger = NR_REDCAP_HD_FDD_RA_TRIGGER_HIGHER_LAYER_MSGA_PUSCH
        var value = nr_redcap_rel17_hd_ra_conflict_category(
            black_box(trigger),
            black_box((iteration & 1) != 0),
            black_box((iteration & 2) != 0),
            black_box(trigger != NR_REDCAP_HD_FDD_RA_TRIGGER_DCI_PRACH
                and (iteration & 4) != 0),
        )
        checksum = checksum * UInt64(1099511628211) ^ UInt64(
            value + iteration
        )
    return checksum


@no_inline
def _ra_explicit_action_workload(iterations: Int, salt: Int) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for iteration in range(iterations):
        var trigger = NR_REDCAP_HD_FDD_RA_TRIGGER_HIGHER_LAYER_PRACH
        if ((iteration + salt) & 1) != 0:
            trigger = NR_REDCAP_HD_FDD_RA_TRIGGER_HIGHER_LAYER_MSGA_PUSCH
        var value = nr_redcap_rel17_hd_ra_action(
            black_box(trigger),
            black_box((iteration & 1) != 0),
            black_box((iteration & 2) != 0),
            black_box((iteration & 4) != 0),
            policy=black_box(NR_REDCAP_HD_FDD_RA_POLICY_AMBIGUOUS),
        )
        checksum = checksum * UInt64(1099511628211) ^ UInt64(
            value + iteration
        )
    return checksum


@no_inline
def _tbms_count_workload(iterations: Int, salt: Int) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for iteration in range(iterations):
        var n = 2 + ((iteration + salt) % 3)
        var k = 1 + (((iteration + salt) // 3) % 3)
        var value = nr_redcap_rel17_hd_tbms_required_slot_count(
            black_box(n), black_box(k)
        )
        checksum = checksum * UInt64(1099511628211) ^ UInt64(
            value + iteration
        )
    return checksum


@no_inline
def _validate_workload(iterations: Int, salt: Int) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for iteration in range(iterations):
        var css_overlap = ((iteration + salt) & 1) == 1
        var value = nr_redcap_rel17_hd_validate_schedule_overlap(
            black_box(False),
            black_box(False),
            black_box(css_overlap),
            css_is_type2=black_box(True),
            tx_is_clause19_1_cg_pusch=black_box(True),
            has_nonoverlap_paging_occasion_per_si_period=black_box(True),
        )
        checksum = checksum * UInt64(1099511628211) ^ UInt64(
            iteration + 1 if value else 0
        )
    return checksum


@no_inline
def _downlink_workload(iterations: Int, salt: Int) -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for iteration in range(iterations):
        var value = nr_redcap_rel17_hd_configured_downlink_action(
            black_box(((iteration + salt) & 1) == 1)
        )
        checksum = checksum * UInt64(1099511628211) ^ UInt64(
            value + 1 + iteration
        )
    return checksum


@no_inline
def _uplink_workload(iterations: Int, salt: Int) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for iteration in range(iterations):
        var value = nr_redcap_rel17_hd_configured_uplink_action(
            black_box(NR_REDCAP_HD_FDD_UPLINK_PUSCH_PUCCH),
            black_box(999 + ((iteration + salt) & 1)),
            black_box(1000),
            black_box(True),
        )
        checksum = checksum * UInt64(1099511628211) ^ UInt64(
            value + 1 + iteration
        )
    return checksum


@no_inline
def _guard_workload(iterations: Int, salt: Int) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for iteration in range(iterations):
        var value = nr_redcap_rel17_hd_ssb_guard_action(
            black_box(NR_REDCAP_HD_FDD_UPLINK_PUSCH_PUCCH),
            black_box(125599 + ((iteration + salt) & 1)),
            black_box(150000),
            previous_ssb_end_tc=black_box(100000),
            next_ssb_start_tc=black_box(175600),
        )
        checksum = checksum * UInt64(1099511628211) ^ UInt64(
            value + 1 + iteration
        )
    return checksum


@no_inline
def _ra_workload(iterations: Int, salt: Int) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for iteration in range(iterations):
        var value = nr_redcap_rel17_hd_higher_layer_ra_action(
            black_box(((iteration + salt) & 1) == 1),
            black_box(((iteration + salt) & 2) == 2),
            policy=black_box(NR_REDCAP_HD_FDD_RA_POLICY_AMBIGUOUS),
        )
        checksum = checksum * UInt64(1099511628211) ^ UInt64(
            value + 1 + iteration
        )
    return checksum


@no_inline
def _slot_workload(
    iterations: Int,
    ssb_starts: Span[Int, ...],
    ssb_ends: Span[Int, ...],
) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for iteration in range(iterations):
        var profile = NR_REDCAP_HD_PUSCH_TYPE_A_DCI_0_1_0_2
        if iteration % 3 == 1:
            profile = NR_REDCAP_HD_PUSCH_TYPE_A_CONFIGURED_GRANT
        elif iteration % 3 == 2:
            profile = NR_REDCAP_HD_PUSCH_TYPE_A_RAR_OR_TC_RNTI
        var slots = nr_redcap_rel17_hd_select_pusch_slots(
            0,
            8,
            2,
            100000,
            30000,
            70000,
            ssb_starts,
            ssb_ends,
            pusch_profile=profile,
            available_slot_counting=True,
            repetition_count=2,
        )
        checksum ^= _int_list_checksum(slots) + UInt64(iteration)
    return checksum


@no_inline
def _tdw_workload(
    iterations: Int,
    tx_starts: Span[Int, ...],
    tx_ends: Span[Int, ...],
    dropped: Span[UInt8, ...],
    dl_starts: Span[Int, ...],
    dl_ends: Span[Int, ...],
) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for iteration in range(iterations):
        var windows = nr_redcap_rel17_hd_dmrs_bundling_window_ids(
            tx_starts,
            tx_ends,
            dropped,
            dl_starts,
            dl_ends,
            window_restart_enabled=(iteration & 1) == 0,
        )
        checksum ^= _int_list_checksum(windows) + UInt64(iteration)
    return checksum


def main() raises:
    var ssb_starts: List[Int] = [95000, 395000]
    var ssb_ends: List[Int] = [105000, 405000]
    var tx_starts: List[Int] = [0, 20, 40, 60, 80]
    var tx_ends: List[Int] = [10, 30, 50, 70, 90]
    var dropped: List[UInt8] = [0, 0, 1, 0, 0]
    var dl_starts: List[Int] = [72]
    var dl_ends: List[Int] = [78]

    for _ in range(_WARMUPS):
        var salt = 324508639
        keep(_n2_workload(_SCALAR_BATCH, salt))
        keep(_t_proc2_workload(_SCALAR_BATCH, salt))
        keep(_hd_t_proc2_workload(_SCALAR_BATCH, salt))
        keep(_ra_category_workload(_SCALAR_BATCH, salt))
        keep(_ra_explicit_action_workload(_SCALAR_BATCH, salt))
        keep(_tbms_count_workload(_SCALAR_BATCH, salt))
        keep(_validate_workload(_SCALAR_BATCH, salt))
        keep(_downlink_workload(_SCALAR_BATCH, salt))
        keep(_uplink_workload(_SCALAR_BATCH, salt))
        keep(_guard_workload(_SCALAR_BATCH, salt))
        keep(_ra_workload(_SCALAR_BATCH, salt))
        keep(_slot_workload(
            _LIST_BATCH, Span(ssb_starts), Span(ssb_ends)
        ))
        keep(_tdw_workload(
            _LIST_BATCH,
            Span(tx_starts),
            Span(tx_ends),
            Span(dropped),
            Span(dl_starts),
            Span(dl_ends),
        ))

    var n2_samples = List[UInt64](capacity=_SAMPLES)
    var t_proc2_samples = List[UInt64](capacity=_SAMPLES)
    var hd_t_proc2_samples = List[UInt64](capacity=_SAMPLES)
    var ra_category_samples = List[UInt64](capacity=_SAMPLES)
    var ra_explicit_action_samples = List[UInt64](capacity=_SAMPLES)
    var tbms_count_samples = List[UInt64](capacity=_SAMPLES)
    var validate_samples = List[UInt64](capacity=_SAMPLES)
    var downlink_samples = List[UInt64](capacity=_SAMPLES)
    var uplink_samples = List[UInt64](capacity=_SAMPLES)
    var guard_samples = List[UInt64](capacity=_SAMPLES)
    var ra_samples = List[UInt64](capacity=_SAMPLES)
    var slot_samples = List[UInt64](capacity=_SAMPLES)
    var tdw_samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)

    for sample in range(_SAMPLES):
        var salt = 324508639
        var start = global_perf_counter_ns()
        var n2 = _n2_workload(_SCALAR_BATCH, salt)
        n2_samples.append(global_perf_counter_ns() - start)
        checksum ^= n2 + UInt64(sample)
        keep(n2)

        start = global_perf_counter_ns()
        var t_proc2 = _t_proc2_workload(_SCALAR_BATCH, salt)
        t_proc2_samples.append(global_perf_counter_ns() - start)
        checksum = checksum * UInt64(1099511628211) ^ t_proc2
        keep(t_proc2)

        start = global_perf_counter_ns()
        var hd_t_proc2 = _hd_t_proc2_workload(_SCALAR_BATCH, salt)
        hd_t_proc2_samples.append(global_perf_counter_ns() - start)
        checksum = checksum * UInt64(1099511628211) ^ hd_t_proc2
        keep(hd_t_proc2)

        start = global_perf_counter_ns()
        var ra_category = _ra_category_workload(_SCALAR_BATCH, salt)
        ra_category_samples.append(global_perf_counter_ns() - start)
        checksum = checksum * UInt64(1099511628211) ^ ra_category
        keep(ra_category)

        start = global_perf_counter_ns()
        var ra_explicit = _ra_explicit_action_workload(_SCALAR_BATCH, salt)
        ra_explicit_action_samples.append(global_perf_counter_ns() - start)
        checksum = checksum * UInt64(1099511628211) ^ ra_explicit
        keep(ra_explicit)

        start = global_perf_counter_ns()
        var tbms_count = _tbms_count_workload(_SCALAR_BATCH, salt)
        tbms_count_samples.append(global_perf_counter_ns() - start)
        checksum = checksum * UInt64(1099511628211) ^ tbms_count
        keep(tbms_count)

        start = global_perf_counter_ns()
        var schedule_ok = _validate_workload(_SCALAR_BATCH, salt)
        validate_samples.append(global_perf_counter_ns() - start)
        checksum ^= schedule_ok + UInt64(sample)
        keep(schedule_ok)

        start = global_perf_counter_ns()
        var downlink = _downlink_workload(_SCALAR_BATCH, salt)
        downlink_samples.append(global_perf_counter_ns() - start)
        checksum = checksum * UInt64(1099511628211) ^ downlink
        keep(downlink)

        start = global_perf_counter_ns()
        var uplink = _uplink_workload(_SCALAR_BATCH, salt)
        uplink_samples.append(global_perf_counter_ns() - start)
        checksum = checksum * UInt64(1099511628211) ^ uplink
        keep(uplink)

        start = global_perf_counter_ns()
        var guard = _guard_workload(_SCALAR_BATCH, salt)
        guard_samples.append(global_perf_counter_ns() - start)
        checksum = checksum * UInt64(1099511628211) ^ guard
        keep(guard)

        start = global_perf_counter_ns()
        var ra = _ra_workload(_SCALAR_BATCH, salt)
        ra_samples.append(global_perf_counter_ns() - start)
        checksum = checksum * UInt64(1099511628211) ^ ra
        keep(ra)

        start = global_perf_counter_ns()
        var slots = _slot_workload(
            _LIST_BATCH, Span(ssb_starts), Span(ssb_ends)
        )
        slot_samples.append(global_perf_counter_ns() - start)
        checksum ^= slots + UInt64(sample)
        keep(slots)

        start = global_perf_counter_ns()
        var windows = _tdw_workload(
            _LIST_BATCH,
            Span(tx_starts),
            Span(tx_ends),
            Span(dropped),
            Span(dl_starts),
            Span(dl_ends),
        )
        tdw_samples.append(global_perf_counter_ns() - start)
        checksum ^= windows + UInt64(31 * sample)
        keep(windows)

    print_benchmark_metadata()
    print("nr_redcap_hd_fdd_backend: scalar-cpu-reference")
    report_timing_samples(
        "nr_redcap_rel17_clause_6_4_n2_twice_symbols",
        n2_samples,
        _WARMUPS,
        _SCALAR_BATCH,
        "table_lookup_api_call",
    )
    report_timing_samples(
        "nr_redcap_rel17_clause_6_4_t_proc2_tc",
        t_proc2_samples,
        _WARMUPS,
        _SCALAR_BATCH,
        "exact_t_proc2_derivation_api_call",
    )
    report_timing_samples(
        "nr_redcap_rel17_hd_t_proc2_tc",
        hd_t_proc2_samples,
        _WARMUPS,
        _SCALAR_BATCH,
        "hd_fdd_threshold_derivation_api_call",
    )
    report_timing_samples(
        "nr_redcap_rel17_hd_ra_conflict_category",
        ra_category_samples,
        _WARMUPS,
        _SCALAR_BATCH,
        "ra_conflict_classification_api_call",
    )
    report_timing_samples(
        "nr_redcap_rel17_hd_ra_action",
        ra_explicit_action_samples,
        _WARMUPS,
        _SCALAR_BATCH,
        "explicit_ra_action_api_call",
    )
    report_timing_samples(
        "nr_redcap_rel17_hd_tbms_required_slot_count",
        tbms_count_samples,
        _WARMUPS,
        _SCALAR_BATCH,
        "tbms_slot_count_api_call",
    )
    report_timing_samples(
        "nr_redcap_rel17_hd_validate_schedule_overlap",
        validate_samples,
        _WARMUPS,
        _SCALAR_BATCH,
        "schedule_validation_api_call",
    )
    report_timing_samples(
        "nr_redcap_rel17_hd_configured_downlink_action",
        downlink_samples,
        _WARMUPS,
        _SCALAR_BATCH,
        "downlink_conflict_decision_api_call",
    )
    report_timing_samples(
        "nr_redcap_rel17_hd_configured_uplink_action",
        uplink_samples,
        _WARMUPS,
        _SCALAR_BATCH,
        "uplink_conflict_decision_api_call",
    )
    report_timing_samples(
        "nr_redcap_rel17_hd_ssb_guard_action",
        guard_samples,
        _WARMUPS,
        _SCALAR_BATCH,
        "ssb_guard_decision_api_call",
    )
    report_timing_samples(
        "nr_redcap_rel17_hd_higher_layer_ra_action",
        ra_samples,
        _WARMUPS,
        _SCALAR_BATCH,
        "ra_policy_decision_api_call",
    )
    report_timing_samples(
        "nr_redcap_rel17_hd_select_pusch_slots",
        slot_samples,
        _WARMUPS,
        _LIST_BATCH,
        "slot_selection_api_call",
    )
    report_timing_samples(
        "nr_redcap_rel17_hd_dmrs_bundling_window_ids",
        tdw_samples,
        _WARMUPS,
        _LIST_BATCH,
        "bundling_window_segmentation_api_call",
    )
    print("nr_redcap_hd_fdd_retained_checksum:", checksum)
