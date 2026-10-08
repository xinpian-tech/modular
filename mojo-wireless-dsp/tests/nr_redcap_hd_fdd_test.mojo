"""Clause and property evidence for Rel-17 RedCap HD-FDD scheduling."""

from std.testing import assert_equal, assert_true, assert_raises, TestSuite
from wireless_dsp.wireless.nr.redcap_hd_fdd import (
    NR_REDCAP_HD_FDD_ACTION_RECEIVE_DOWNLINK,
    NR_REDCAP_HD_FDD_ACTION_TRANSMIT_UPLINK,
    NR_REDCAP_HD_FDD_ACTION_DROP_OR_CANCEL,
    NR_REDCAP_HD_FDD_ACTION_AMBIGUOUS,
    NR_REDCAP_HD_FDD_UPLINK_PUSCH_PUCCH,
    NR_REDCAP_HD_FDD_UPLINK_SRS,
    NR_REDCAP_HD_FDD_RA_POLICY_AMBIGUOUS,
    NR_REDCAP_HD_FDD_RA_POLICY_PREFER_UPLINK,
    NR_REDCAP_HD_FDD_RA_POLICY_PREFER_DOWNLINK,
    NR_REDCAP_HD_FDD_RA_TRIGGER_DCI_PRACH,
    NR_REDCAP_HD_FDD_RA_TRIGGER_HIGHER_LAYER_PRACH,
    NR_REDCAP_HD_FDD_RA_TRIGGER_HIGHER_LAYER_MSGA_PUSCH,
    NR_REDCAP_HD_FDD_RA_DECISION_CLEAR,
    NR_REDCAP_HD_FDD_RA_DECISION_DCI_PRACH_BLOCKED_BY_SSB,
    NR_REDCAP_HD_FDD_RA_DECISION_DCI_PRACH_PREEMPTS_DL,
    NR_REDCAP_HD_FDD_RA_DECISION_HIGHER_LAYER_DL_CHOICE,
    NR_REDCAP_HD_FDD_RA_DECISION_HIGHER_LAYER_SSB_CHOICE,
    NR_REDCAP_HD_FDD_RA_DECISION_HIGHER_LAYER_DL_SSB_CHOICE,
    NR_REDCAP_HD_FDD_RA_DECISION_HIGHER_LAYER_GUARD_CHOICE,
    NR_REDCAP_HD_PUSCH_TIMING_CAPABILITY_1,
    NR_REDCAP_HD_PUSCH_TIMING_CAPABILITY_2,
    NR_REDCAP_HD_FDD_FR1_RX_TO_TX_TC,
    NR_REDCAP_HD_FDD_FR1_TX_TO_RX_TC,
    NR_REDCAP_HD_PUSCH_TYPE_A_DCI_0_1_0_2,
    NR_REDCAP_HD_PUSCH_TYPE_A_CONFIGURED_GRANT,
    NR_REDCAP_HD_PUSCH_TYPE_A_RAR_OR_TC_RNTI,
    NR_REDCAP_HD_PUSCH_TBMS_DCI_0_1_0_2,
    NR_REDCAP_HD_PUSCH_TBMS_TYPE2_CONFIGURED_GRANT,
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


def _select_static_slots(
    ssb_starts: List[Int], ssb_ends: List[Int]
) raises -> List[Int]:
    return nr_redcap_rel17_hd_select_pusch_slots(
        0,
        8,
        2,
        100000,
        30000,
        70000,
        Span(ssb_starts),
        Span(ssb_ends),
        available_slot_counting=True,
        repetition_count=2,
    )


def _independent_slot_oracle(
    ssb_starts: Span[Int, ...],
    ssb_ends: Span[Int, ...],
    required: Int,
) -> List[Int]:
    # Independent bounded formulation: expand each SSB interval by the two
    # transition guards and reject an allocation that intersects the expansion.
    var result = List[Int](capacity=required)
    for slot in range(8):
        var allocation_start = slot * 100000 + 30000
        var allocation_end = slot * 100000 + 70000
        var eligible = True
        for index in range(len(ssb_starts)):
            # Frozen Table 4.3.2-3 literal, deliberately independent of the
            # production constants.
            var forbidden_start = ssb_starts[index] - 25600
            var forbidden_end = ssb_ends[index] + 25600
            if allocation_start < forbidden_end and (
                forbidden_start < allocation_end
            ):
                eligible = False
        if eligible:
            result.append(slot)
            if len(result) == required:
                break
    return result^


def _independent_twice_n2(capability: Int, mu: Int) raises -> Int:
    # Frozen ETSI TS 138 214 V17.16.0 Tables 6.4-1/2 literals.  This oracle
    # deliberately does not call the production table function.
    if capability == 1:
        if mu == 0:
            return 20
        if mu == 1:
            return 24
        if mu == 2:
            return 46
        if mu == 3:
            return 72
        if mu == 5:
            return 288
        if mu == 6:
            return 576
    elif capability == 2:
        if mu == 0:
            return 10
        if mu == 1:
            return 11
        if mu == 2:
            return 22
    raise Error("invalid independent N2 table lookup")


def _independent_symbol_duration_tc(mu: Int) raises -> Int:
    # Frozen analytic expansion of (2048+144)*kappa*2^-mu, kappa=64.
    if mu == 0:
        return 140288
    if mu == 1:
        return 70144
    if mu == 2:
        return 35072
    if mu == 3:
        return 17536
    if mu == 5:
        return 4384
    if mu == 6:
        return 2192
    raise Error("invalid independent symbol duration")


def _independent_t_proc2_for_mu_tc(
    capability: Int,
    mu: Int,
    dmrs_only: Bool,
    d2: Int,
    text: Int,
    switching_gap: Int,
    bwp_switch: Int,
) raises -> Int:
    var symbol_tc = _independent_symbol_duration_tc(mu)
    var duration = (
        _independent_twice_n2(capability, mu) * symbol_tc // 2
        + d2 * symbol_tc
        + text
        + switching_gap
    )
    if not dmrs_only:
        duration += symbol_tc
    return bwp_switch if bwp_switch > duration else duration


def _independent_t_proc2_tc(
    capability: Int,
    mu_dl: Int,
    mu_ul: Int,
    dmrs_only: Bool,
    d2: Int,
    text: Int,
    switching_gap: Int,
    bwp_switch: Int,
) raises -> Int:
    var dl = _independent_t_proc2_for_mu_tc(
        capability, mu_dl, dmrs_only, d2, text, switching_gap, bwp_switch
    )
    var ul = _independent_t_proc2_for_mu_tc(
        capability, mu_ul, dmrs_only, d2, text, switching_gap, bwp_switch
    )
    return dl if dl >= ul else ul


def _independent_tbms_slot_count(n: Int, k: Int) -> Int:
    var total = 0
    for _ in range(k):
        total += n
    return total


def test_clause_6_4_complete_n2_tables_and_exact_tc_formula() raises:
    # Every row of Tables 6.4-1 and 6.4-2, including the half-symbol row.
    assert_equal(nr_redcap_rel17_clause_6_4_n2_twice_symbols(
        NR_REDCAP_HD_PUSCH_TIMING_CAPABILITY_1, 0
    ), 20)
    assert_equal(nr_redcap_rel17_clause_6_4_n2_twice_symbols(
        NR_REDCAP_HD_PUSCH_TIMING_CAPABILITY_1, 1
    ), 24)
    assert_equal(nr_redcap_rel17_clause_6_4_n2_twice_symbols(
        NR_REDCAP_HD_PUSCH_TIMING_CAPABILITY_1, 2
    ), 46)
    assert_equal(nr_redcap_rel17_clause_6_4_n2_twice_symbols(
        NR_REDCAP_HD_PUSCH_TIMING_CAPABILITY_1, 3
    ), 72)
    assert_equal(nr_redcap_rel17_clause_6_4_n2_twice_symbols(
        NR_REDCAP_HD_PUSCH_TIMING_CAPABILITY_1, 5
    ), 288)
    assert_equal(nr_redcap_rel17_clause_6_4_n2_twice_symbols(
        NR_REDCAP_HD_PUSCH_TIMING_CAPABILITY_1, 6
    ), 576)
    assert_equal(nr_redcap_rel17_clause_6_4_n2_twice_symbols(
        NR_REDCAP_HD_PUSCH_TIMING_CAPABILITY_2, 0
    ), 10)
    assert_equal(nr_redcap_rel17_clause_6_4_n2_twice_symbols(
        NR_REDCAP_HD_PUSCH_TIMING_CAPABILITY_2, 1
    ), 11)
    assert_equal(nr_redcap_rel17_clause_6_4_n2_twice_symbols(
        NR_REDCAP_HD_PUSCH_TIMING_CAPABILITY_2, 2
    ), 22)

    assert_equal(
        nr_redcap_rel17_clause_6_4_t_proc2_tc(
            NR_REDCAP_HD_PUSCH_TIMING_CAPABILITY_1, 0, 2
        ),
        1543168,
    )
    assert_equal(
        nr_redcap_rel17_clause_6_4_t_proc2_tc(
            NR_REDCAP_HD_PUSCH_TIMING_CAPABILITY_1,
            2,
            3,
            first_symbol_dmrs_only=True,
            d2_symbols=2,
            text_tc=17,
            switching_gap_tc=19,
            bwp_switching_time_tc=1,
        ),
        876836,
    )
    # Capability-2 mu=1 N2=5.5 and mu=2 N2=11 both equal 385792 Tc.
    assert_equal(
        nr_redcap_rel17_clause_6_4_t_proc2_tc(
            NR_REDCAP_HD_PUSCH_TIMING_CAPABILITY_2,
            1,
            2,
            first_symbol_dmrs_only=True,
        ),
        385792,
    )
    assert_equal(
        nr_redcap_rel17_clause_6_4_t_proc2_tc(
            NR_REDCAP_HD_PUSCH_TIMING_CAPABILITY_2,
            1,
            2,
            bwp_switching_time_tc=2000000,
        ),
        2000000,
    )


def test_clause_6_4_t_proc2_matches_independent_seeded_grid() raises:
    var capability1_mus: List[Int] = [0, 1, 2, 3, 5, 6]
    var capability2_mus: List[Int] = [0, 1, 2]
    for left_index in range(len(capability1_mus)):
        for right_index in range(len(capability1_mus)):
            var mu_dl = capability1_mus[left_index]
            var mu_ul = capability1_mus[right_index]
            var d2 = (3 * left_index + right_index) % 4
            var text = 17 * left_index + right_index
            var switching_gap = 19 * right_index + left_index
            var bwp_switch = 1000 * ((left_index + right_index) % 3)
            var dmrs_only = ((left_index + right_index) & 1) == 0
            assert_equal(
                nr_redcap_rel17_clause_6_4_t_proc2_tc(
                    NR_REDCAP_HD_PUSCH_TIMING_CAPABILITY_1,
                    mu_dl,
                    mu_ul,
                    first_symbol_dmrs_only=dmrs_only,
                    d2_symbols=d2,
                    text_tc=text,
                    switching_gap_tc=switching_gap,
                    bwp_switching_time_tc=bwp_switch,
                ),
                _independent_t_proc2_tc(
                    1,
                    mu_dl,
                    mu_ul,
                    dmrs_only,
                    d2,
                    text,
                    switching_gap,
                    bwp_switch,
                ),
            )
    for left_index in range(len(capability2_mus)):
        for right_index in range(len(capability2_mus)):
            var mu_dl = capability2_mus[left_index]
            var mu_ul = capability2_mus[right_index]
            assert_equal(
                nr_redcap_rel17_clause_6_4_t_proc2_tc(
                    NR_REDCAP_HD_PUSCH_TIMING_CAPABILITY_2,
                    mu_dl,
                    mu_ul,
                    first_symbol_dmrs_only=False,
                    d2_symbols=left_index,
                    text_tc=right_index,
                ),
                _independent_t_proc2_tc(
                    2,
                    mu_dl,
                    mu_ul,
                    False,
                    left_index,
                    right_index,
                    0,
                    0,
                ),
            )


def test_clause_17_2_exact_t_proc2_profile_and_boundaries() raises:
    assert_equal(nr_redcap_rel17_hd_t_proc2_tc(0, 0), 1543168)
    assert_equal(nr_redcap_rel17_hd_t_proc2_tc(1, 1), 911872)
    assert_equal(nr_redcap_rel17_hd_t_proc2_tc(2, 2), 841728)
    assert_equal(nr_redcap_rel17_hd_t_proc2_tc(2, 0), 1543168)
    assert_equal(nr_redcap_rel17_hd_t_proc2_tc(2, 1), 911872)
    assert_equal(nr_redcap_rel17_hd_t_proc2_tc(1, 2), 911872)

    var threshold = nr_redcap_rel17_hd_t_proc2_tc(1, 2)
    assert_equal(
        nr_redcap_rel17_hd_configured_uplink_action(
            NR_REDCAP_HD_FDD_UPLINK_PUSCH_PUCCH,
            threshold - 1,
            threshold,
            True,
        ),
        NR_REDCAP_HD_FDD_ACTION_TRANSMIT_UPLINK,
    )
    assert_equal(
        nr_redcap_rel17_hd_configured_uplink_action(
            NR_REDCAP_HD_FDD_UPLINK_PUSCH_PUCCH,
            threshold,
            threshold,
            True,
        ),
        NR_REDCAP_HD_FDD_ACTION_DROP_OR_CANCEL,
    )


def test_clause_17_2_explicit_ra_conflict_categories_and_actions() raises:
    assert_equal(
        nr_redcap_rel17_hd_ra_conflict_category(
            NR_REDCAP_HD_FDD_RA_TRIGGER_DCI_PRACH,
            False,
            False,
            False,
        ),
        NR_REDCAP_HD_FDD_RA_DECISION_CLEAR,
    )
    assert_equal(
        nr_redcap_rel17_hd_ra_conflict_category(
            NR_REDCAP_HD_FDD_RA_TRIGGER_DCI_PRACH,
            True,
            False,
            False,
        ),
        NR_REDCAP_HD_FDD_RA_DECISION_DCI_PRACH_PREEMPTS_DL,
    )
    assert_equal(
        nr_redcap_rel17_hd_ra_conflict_category(
            NR_REDCAP_HD_FDD_RA_TRIGGER_DCI_PRACH,
            True,
            True,
            False,
        ),
        NR_REDCAP_HD_FDD_RA_DECISION_DCI_PRACH_BLOCKED_BY_SSB,
    )
    assert_equal(
        nr_redcap_rel17_hd_ra_conflict_category(
            NR_REDCAP_HD_FDD_RA_TRIGGER_HIGHER_LAYER_PRACH,
            True,
            False,
            False,
        ),
        NR_REDCAP_HD_FDD_RA_DECISION_HIGHER_LAYER_DL_CHOICE,
    )
    assert_equal(
        nr_redcap_rel17_hd_ra_conflict_category(
            NR_REDCAP_HD_FDD_RA_TRIGGER_HIGHER_LAYER_MSGA_PUSCH,
            False,
            True,
            False,
        ),
        NR_REDCAP_HD_FDD_RA_DECISION_HIGHER_LAYER_SSB_CHOICE,
    )
    assert_equal(
        nr_redcap_rel17_hd_ra_conflict_category(
            NR_REDCAP_HD_FDD_RA_TRIGGER_HIGHER_LAYER_MSGA_PUSCH,
            True,
            True,
            True,
        ),
        NR_REDCAP_HD_FDD_RA_DECISION_HIGHER_LAYER_DL_SSB_CHOICE,
    )
    assert_equal(
        nr_redcap_rel17_hd_ra_conflict_category(
            NR_REDCAP_HD_FDD_RA_TRIGGER_HIGHER_LAYER_PRACH,
            False,
            False,
            True,
        ),
        NR_REDCAP_HD_FDD_RA_DECISION_HIGHER_LAYER_GUARD_CHOICE,
    )

    assert_equal(
        nr_redcap_rel17_hd_ra_action(
            NR_REDCAP_HD_FDD_RA_TRIGGER_DCI_PRACH,
            True,
            False,
            False,
            policy=NR_REDCAP_HD_FDD_RA_POLICY_PREFER_DOWNLINK,
        ),
        NR_REDCAP_HD_FDD_ACTION_TRANSMIT_UPLINK,
    )
    assert_equal(
        nr_redcap_rel17_hd_ra_action(
            NR_REDCAP_HD_FDD_RA_TRIGGER_DCI_PRACH,
            True,
            True,
            False,
            policy=NR_REDCAP_HD_FDD_RA_POLICY_PREFER_UPLINK,
        ),
        NR_REDCAP_HD_FDD_ACTION_DROP_OR_CANCEL,
    )
    for trigger in range(
        NR_REDCAP_HD_FDD_RA_TRIGGER_HIGHER_LAYER_PRACH,
        NR_REDCAP_HD_FDD_RA_TRIGGER_HIGHER_LAYER_MSGA_PUSCH + 1,
    ):
        for mask in range(1, 8):
            assert_equal(
                nr_redcap_rel17_hd_ra_action(
                    trigger,
                    (mask & 1) != 0,
                    (mask & 2) != 0,
                    (mask & 4) != 0,
                ),
                NR_REDCAP_HD_FDD_ACTION_AMBIGUOUS,
            )
            assert_equal(
                nr_redcap_rel17_hd_ra_action(
                    trigger,
                    (mask & 1) != 0,
                    (mask & 2) != 0,
                    (mask & 4) != 0,
                    policy=NR_REDCAP_HD_FDD_RA_POLICY_PREFER_UPLINK,
                ),
                NR_REDCAP_HD_FDD_ACTION_TRANSMIT_UPLINK,
            )
            assert_equal(
                nr_redcap_rel17_hd_ra_action(
                    trigger,
                    (mask & 1) != 0,
                    (mask & 2) != 0,
                    (mask & 4) != 0,
                    policy=NR_REDCAP_HD_FDD_RA_POLICY_PREFER_DOWNLINK,
                ),
                NR_REDCAP_HD_FDD_ACTION_RECEIVE_DOWNLINK,
            )


def test_tbms_n_times_k_checked_derivation_property() raises:
    for n in range(2, 33):
        for k in range(1, 17):
            var expected = _independent_tbms_slot_count(n, k)
            if expected <= 32:
                assert_equal(
                    nr_redcap_rel17_hd_tbms_required_slot_count(n, k),
                    expected,
                )
            else:
                with assert_raises():
                    _ = nr_redcap_rel17_hd_tbms_required_slot_count(n, k)


def test_hd_fdd_clause_17_2_static_action_table() raises:
    assert_true(nr_redcap_rel17_hd_validate_schedule_overlap(
        False, False, False
    ))
    assert_true(nr_redcap_rel17_hd_validate_schedule_overlap(
        False,
        False,
        True,
        css_is_type2=True,
        tx_is_clause19_1_cg_pusch=True,
        has_nonoverlap_paging_occasion_per_si_period=True,
    ))
    with assert_raises():
        _ = nr_redcap_rel17_hd_validate_schedule_overlap(
            True,
            False,
            True,
            css_is_type2=True,
            tx_is_clause19_1_cg_pusch=True,
            has_nonoverlap_paging_occasion_per_si_period=True,
        )
    with assert_raises():
        _ = nr_redcap_rel17_hd_validate_schedule_overlap(
            False,
            True,
            False,
            css_is_type2=True,
            tx_is_clause19_1_cg_pusch=True,
            has_nonoverlap_paging_occasion_per_si_period=True,
        )
    with assert_raises():
        _ = nr_redcap_rel17_hd_validate_schedule_overlap(
            False, False, True,
        )
    with assert_raises():
        _ = nr_redcap_rel17_hd_validate_schedule_overlap(
            False,
            False,
            True,
            tx_is_clause19_1_cg_pusch=True,
            has_nonoverlap_paging_occasion_per_si_period=True,
        )
    with assert_raises():
        _ = nr_redcap_rel17_hd_validate_schedule_overlap(
            False,
            False,
            True,
            css_is_type2=True,
            has_nonoverlap_paging_occasion_per_si_period=True,
        )
    with assert_raises():
        _ = nr_redcap_rel17_hd_validate_schedule_overlap(
            False,
            False,
            True,
            css_is_type2=True,
            tx_is_clause19_1_cg_pusch=True,
        )

    assert_equal(
        nr_redcap_rel17_hd_configured_downlink_action(False),
        NR_REDCAP_HD_FDD_ACTION_RECEIVE_DOWNLINK,
    )
    assert_equal(
        nr_redcap_rel17_hd_configured_downlink_action(True),
        NR_REDCAP_HD_FDD_ACTION_DROP_OR_CANCEL,
    )

    for kind in range(2):
        assert_equal(
            nr_redcap_rel17_hd_configured_uplink_action(
                kind, 999, 1000, True
            ),
            NR_REDCAP_HD_FDD_ACTION_TRANSMIT_UPLINK,
        )
        assert_equal(
            nr_redcap_rel17_hd_configured_uplink_action(
                kind, 1000, 1000, True
            ),
            NR_REDCAP_HD_FDD_ACTION_DROP_OR_CANCEL,
        )
        assert_equal(
            nr_redcap_rel17_hd_configured_uplink_action(
                kind, 1001, 1000, False
            ),
            NR_REDCAP_HD_FDD_ACTION_TRANSMIT_UPLINK,
        )
        assert_equal(
            nr_redcap_rel17_hd_configured_uplink_action(
                kind, 1001, 1000, True
            ),
            NR_REDCAP_HD_FDD_ACTION_DROP_OR_CANCEL,
        )

    assert_equal(
        nr_redcap_rel17_hd_higher_layer_ra_action(False, False),
        NR_REDCAP_HD_FDD_ACTION_TRANSMIT_UPLINK,
    )
    assert_equal(
        nr_redcap_rel17_hd_higher_layer_ra_action(
            True,
            False,
            policy=NR_REDCAP_HD_FDD_RA_POLICY_AMBIGUOUS,
        ),
        NR_REDCAP_HD_FDD_ACTION_AMBIGUOUS,
    )
    assert_equal(
        nr_redcap_rel17_hd_higher_layer_ra_action(
            True,
            False,
            policy=NR_REDCAP_HD_FDD_RA_POLICY_PREFER_UPLINK,
        ),
        NR_REDCAP_HD_FDD_ACTION_TRANSMIT_UPLINK,
    )
    assert_equal(
        nr_redcap_rel17_hd_higher_layer_ra_action(
            False,
            True,
            policy=NR_REDCAP_HD_FDD_RA_POLICY_PREFER_DOWNLINK,
        ),
        NR_REDCAP_HD_FDD_ACTION_RECEIVE_DOWNLINK,
    )


def test_hd_fdd_ssb_guard_exact_transition_boundaries() raises:
    assert_equal(NR_REDCAP_HD_FDD_FR1_RX_TO_TX_TC, 25600)
    assert_equal(NR_REDCAP_HD_FDD_FR1_TX_TO_RX_TC, 25600)
    assert_equal(
        nr_redcap_rel17_hd_ssb_guard_action(
            NR_REDCAP_HD_FDD_UPLINK_PUSCH_PUCCH,
            125600,
            150000,
            previous_ssb_end_tc=100000,
            next_ssb_start_tc=175600,
        ),
        NR_REDCAP_HD_FDD_ACTION_TRANSMIT_UPLINK,
    )
    assert_equal(
        nr_redcap_rel17_hd_ssb_guard_action(
            NR_REDCAP_HD_FDD_UPLINK_PUSCH_PUCCH,
            125599,
            150000,
            previous_ssb_end_tc=100000,
            next_ssb_start_tc=175600,
        ),
        NR_REDCAP_HD_FDD_ACTION_DROP_OR_CANCEL,
    )
    assert_equal(
        nr_redcap_rel17_hd_ssb_guard_action(
            NR_REDCAP_HD_FDD_UPLINK_SRS,
            125600,
            150001,
            previous_ssb_end_tc=100000,
            next_ssb_start_tc=175600,
        ),
        NR_REDCAP_HD_FDD_ACTION_DROP_OR_CANCEL,
    )
    # A DCI-triggered occasion is not subject to the configured guard, but an
    # actual SSB overlap is still forbidden.
    assert_equal(
        nr_redcap_rel17_hd_ssb_guard_action(
            NR_REDCAP_HD_FDD_UPLINK_PUSCH_PUCCH,
            100001,
            174999,
            previous_ssb_end_tc=100000,
            next_ssb_start_tc=175000,
            configured_by_higher_layers=False,
        ),
        NR_REDCAP_HD_FDD_ACTION_TRANSMIT_UPLINK,
    )
    assert_equal(
        nr_redcap_rel17_hd_ssb_guard_action(
            NR_REDCAP_HD_FDD_UPLINK_SRS,
            99999,
            100001,
            previous_ssb_end_tc=100000,
            configured_by_higher_layers=False,
        ),
        NR_REDCAP_HD_FDD_ACTION_DROP_OR_CANCEL,
    )


def test_hd_pusch_available_slot_counting_static_clause_oracle() raises:
    var ssb_starts: List[Int] = [95000, 395000]
    var ssb_ends: List[Int] = [105000, 405000]
    assert_equal(_select_static_slots(ssb_starts, ssb_ends), [2, 5])

    var consecutive = nr_redcap_rel17_hd_select_pusch_slots(
        0,
        8,
        2,
        100000,
        30000,
        70000,
        Span(ssb_starts),
        Span(ssb_ends),
        pusch_profile=NR_REDCAP_HD_PUSCH_TYPE_A_DCI_0_1_0_2,
        available_slot_counting=False,
        repetition_count=2,
    )
    assert_equal(consecutive, [0, 1])

    var single = nr_redcap_rel17_hd_select_pusch_slots(
        0,
        8,
        1,
        100000,
        30000,
        70000,
        Span(ssb_starts),
        Span(ssb_ends),
        available_slot_counting=True,
        repetition_count=1,
    )
    assert_equal(single, [0])

    var multi_slot_tb = nr_redcap_rel17_hd_select_pusch_slots(
        0,
        8,
        2,
        100000,
        30000,
        70000,
        Span(ssb_starts),
        Span(ssb_ends),
        pusch_profile=NR_REDCAP_HD_PUSCH_TBMS_DCI_0_1_0_2,
    )
    assert_equal(multi_slot_tb, [2, 5])

    var configured = nr_redcap_rel17_hd_select_pusch_slots(
        0,
        8,
        2,
        100000,
        30000,
        70000,
        Span(ssb_starts),
        Span(ssb_ends),
        pusch_profile=NR_REDCAP_HD_PUSCH_TYPE_A_CONFIGURED_GRANT,
        available_slot_counting=True,
        repetition_count=2,
    )
    assert_equal(configured, [2, 5])

    # AvailableSlotCounting may be configured globally, but it does not
    # filter a RAR/DCI-0_0-with-TC-RNTI grant.
    var rar_or_tc_rnti = nr_redcap_rel17_hd_select_pusch_slots(
        0,
        8,
        2,
        100000,
        30000,
        70000,
        Span(ssb_starts),
        Span(ssb_ends),
        pusch_profile=NR_REDCAP_HD_PUSCH_TYPE_A_RAR_OR_TC_RNTI,
        available_slot_counting=True,
        repetition_count=2,
    )
    assert_equal(rar_or_tc_rnti, [0, 1])

    var type2_tbms = nr_redcap_rel17_hd_select_pusch_slots(
        0,
        8,
        2,
        100000,
        30000,
        70000,
        Span(ssb_starts),
        Span(ssb_ends),
        pusch_profile=NR_REDCAP_HD_PUSCH_TBMS_TYPE2_CONFIGURED_GRANT,
    )
    assert_equal(type2_tbms, [2, 5])


def test_hd_pusch_selection_matches_independent_expanded_interval_property() raises:
    var first_starts: List[Int] = [95000, 395000]
    var first_ends: List[Int] = [105000, 405000]
    var second_starts: List[Int] = [395000, 95000]
    var second_ends: List[Int] = [405000, 105000]
    var expected = _independent_slot_oracle(
        Span(first_starts), Span(first_ends), 2
    )
    assert_equal(_select_static_slots(first_starts, first_ends), expected)
    assert_equal(_select_static_slots(second_starts, second_ends), expected)

    for shift in range(5):
        var starts: List[Int] = [95000 + 100000 * shift]
        var ends: List[Int] = [105000 + 100000 * shift]
        var shifted_expected = _independent_slot_oracle(
            Span(starts), Span(ends), 2
        )
        assert_equal(_select_static_slots(starts, ends), shifted_expected)

    # Equality at both transition boundaries is admissible.
    var exact_starts: List[Int] = [95600]
    var exact_ends: List[Int] = [104400]
    var exact = nr_redcap_rel17_hd_select_pusch_slots(
        0,
        4,
        2,
        100000,
        30000,
        70000,
        Span(exact_starts),
        Span(exact_ends),
        available_slot_counting=True,
        repetition_count=2,
    )
    assert_equal(exact, [0, 1])


def test_hd_dmrs_bundling_windows_static_redcap_events() raises:
    var starts: List[Int] = [0, 20, 40, 60, 80]
    var ends: List[Int] = [10, 30, 50, 70, 90]
    var dropped: List[UInt8] = [0, 0, 1, 0, 0]
    var dl_starts: List[Int] = [72]
    var dl_ends: List[Int] = [78]
    var windows = nr_redcap_rel17_hd_dmrs_bundling_window_ids(
        Span(starts),
        Span(ends),
        Span(dropped),
        Span(dl_starts),
        Span(dl_ends),
    )
    assert_equal(windows, [0, 0, -1, 1, 2])
    var no_restart = nr_redcap_rel17_hd_dmrs_bundling_window_ids(
        Span(starts),
        Span(ends),
        Span(dropped),
        Span(dl_starts),
        Span(dl_ends),
        window_restart_enabled=False,
    )
    assert_equal(no_restart, [0, 0, -1, -1, -1])

    var no_drop: List[UInt8] = [0, 0, 0, 0, 0]
    var only_gap = nr_redcap_rel17_hd_dmrs_bundling_window_ids(
        Span(starts),
        Span(ends),
        Span(no_drop),
        Span(dl_starts),
        Span(dl_ends),
    )
    assert_equal(only_gap, [0, 0, 0, 0, 1])

    var short_starts: List[Int] = [0, 20, 40]
    var short_ends: List[Int] = [10, 30, 50]
    var leading_drops: List[UInt8] = [1, 1, 0]
    var no_dl_starts: List[Int] = []
    var no_dl_ends: List[Int] = []
    assert_equal(
        nr_redcap_rel17_hd_dmrs_bundling_window_ids(
            Span(short_starts),
            Span(short_ends),
            Span(leading_drops),
            Span(no_dl_starts),
            Span(no_dl_ends),
        ),
        [-1, -1, 0],
    )

    var fourth_starts: List[Int] = [0, 20, 40, 60]
    var fourth_ends: List[Int] = [10, 30, 50, 70]
    var fourth_drops: List[UInt8] = [0, 1, 1, 0]
    assert_equal(
        nr_redcap_rel17_hd_dmrs_bundling_window_ids(
            Span(fourth_starts),
            Span(fourth_ends),
            Span(fourth_drops),
            Span(no_dl_starts),
            Span(no_dl_ends),
        ),
        [0, -1, -1, 1],
    )

    # A nonempty DL interval beginning exactly at the previous actual end is
    # a gap event and splits the actual TDW.
    var gap_dl_starts: List[Int] = [10]
    var gap_dl_ends: List[Int] = [11]
    var two_starts: List[Int] = [0, 20]
    var two_ends: List[Int] = [10, 30]
    var two_no_drop: List[UInt8] = [0, 0]
    assert_equal(
        nr_redcap_rel17_hd_dmrs_bundling_window_ids(
            Span(two_starts),
            Span(two_ends),
            Span(two_no_drop),
            Span(gap_dl_starts),
            Span(gap_dl_ends),
        ),
        [0, 1],
    )


def test_hd_fdd_public_invalid_and_overflow_edges() raises:
    with assert_raises():
        _ = nr_redcap_rel17_clause_6_4_n2_twice_symbols(0, 0)
    with assert_raises():
        _ = nr_redcap_rel17_clause_6_4_n2_twice_symbols(
            NR_REDCAP_HD_PUSCH_TIMING_CAPABILITY_1, 4
        )
    with assert_raises():
        _ = nr_redcap_rel17_clause_6_4_n2_twice_symbols(
            NR_REDCAP_HD_PUSCH_TIMING_CAPABILITY_2, 3
        )
    with assert_raises():
        _ = nr_redcap_rel17_clause_6_4_t_proc2_tc(
            NR_REDCAP_HD_PUSCH_TIMING_CAPABILITY_1,
            0,
            1,
            d2_symbols=-1,
        )
    with assert_raises():
        _ = nr_redcap_rel17_clause_6_4_t_proc2_tc(
            NR_REDCAP_HD_PUSCH_TIMING_CAPABILITY_1,
            0,
            1,
            text_tc=Int.MAX,
            switching_gap_tc=Int.MAX,
        )
    with assert_raises():
        _ = nr_redcap_rel17_hd_t_proc2_tc(-1, 0)
    with assert_raises():
        _ = nr_redcap_rel17_hd_t_proc2_tc(0, 3)
    with assert_raises():
        _ = nr_redcap_rel17_hd_ra_conflict_category(99, False, False, False)
    with assert_raises():
        _ = nr_redcap_rel17_hd_ra_conflict_category(
            NR_REDCAP_HD_FDD_RA_TRIGGER_DCI_PRACH,
            False,
            False,
            True,
        )
    with assert_raises():
        _ = nr_redcap_rel17_hd_ra_action(
            NR_REDCAP_HD_FDD_RA_TRIGGER_HIGHER_LAYER_PRACH,
            True,
            False,
            False,
            policy=99,
        )
    with assert_raises():
        _ = nr_redcap_rel17_hd_tbms_required_slot_count(1, 1)
    with assert_raises():
        _ = nr_redcap_rel17_hd_tbms_required_slot_count(2, 0)
    with assert_raises():
        _ = nr_redcap_rel17_hd_tbms_required_slot_count(Int.MAX, Int.MAX)
    with assert_raises():
        _ = nr_redcap_rel17_hd_configured_uplink_action(9, 1, 1, True)
    with assert_raises():
        _ = nr_redcap_rel17_hd_configured_uplink_action(
            NR_REDCAP_HD_FDD_UPLINK_SRS, -1, 1, True
        )
    with assert_raises():
        _ = nr_redcap_rel17_hd_higher_layer_ra_action(
            True, False, policy=99
        )
    with assert_raises():
        _ = nr_redcap_rel17_hd_ssb_guard_action(
            9, 0, 1
        )
    with assert_raises():
        _ = nr_redcap_rel17_hd_ssb_guard_action(
            NR_REDCAP_HD_FDD_UPLINK_PUSCH_PUCCH,
            1,
            2,
            previous_ssb_end_tc=10,
            next_ssb_start_tc=9,
        )

    var empty_starts: List[Int] = []
    var empty_ends: List[Int] = []
    var one: List[Int] = [1]
    with assert_raises():
        _ = nr_redcap_rel17_hd_select_pusch_slots(
            0, 1, 1, 10, 1, 2, Span(empty_starts), Span(one)
        )
    with assert_raises():
        _ = nr_redcap_rel17_hd_select_pusch_slots(
            Int.MAX,
            2,
            1,
            10,
            1,
            2,
            Span(empty_starts),
            Span(empty_ends),
        )
    with assert_raises():
        _ = nr_redcap_rel17_hd_select_pusch_slots(
            2,
            1,
            1,
            Int.MAX,
            0,
            1,
            Span(empty_starts),
            Span(empty_ends),
        )
    var blocking_starts: List[Int] = [95000]
    var blocking_ends: List[Int] = [105000]
    with assert_raises():
        _ = nr_redcap_rel17_hd_select_pusch_slots(
            0,
            1,
            1,
            100000,
            30000,
            70000,
            Span(blocking_starts),
            Span(blocking_ends),
            pusch_profile=NR_REDCAP_HD_PUSCH_TBMS_DCI_0_1_0_2,
        )
    with assert_raises():
        _ = nr_redcap_rel17_hd_select_pusch_slots(
            0,
            2,
            1,
            10,
            1,
            2,
            Span(empty_starts),
            Span(empty_ends),
            pusch_profile=99,
        )
    with assert_raises():
        _ = nr_redcap_rel17_hd_select_pusch_slots(
            0,
            2,
            2,
            10,
            1,
            2,
            Span(empty_starts),
            Span(empty_ends),
            repetition_count=2,
            transmission_layers=2,
        )
    with assert_raises():
        _ = nr_redcap_rel17_hd_select_pusch_slots(
            0,
            33,
            33,
            10,
            1,
            2,
            Span(empty_starts),
            Span(empty_ends),
            pusch_profile=NR_REDCAP_HD_PUSCH_TBMS_DCI_0_1_0_2,
        )

    var starts: List[Int] = [0, 10]
    var ends: List[Int] = [5, 15]
    var short_flags: List[UInt8] = [0]
    var no_dl_starts: List[Int] = []
    var no_dl_ends: List[Int] = []
    with assert_raises():
        _ = nr_redcap_rel17_hd_dmrs_bundling_window_ids(
            Span(starts),
            Span(ends),
            Span(short_flags),
            Span(no_dl_starts),
            Span(no_dl_ends),
        )
    var invalid_flags: List[UInt8] = [0, 2]
    with assert_raises():
        _ = nr_redcap_rel17_hd_dmrs_bundling_window_ids(
            Span(starts),
            Span(ends),
            Span(invalid_flags),
            Span(no_dl_starts),
            Span(no_dl_ends),
        )
    var transmitted: List[UInt8] = [0, 0]
    var dl_starts: List[Int] = [11]
    var dl_ends: List[Int] = [12]
    with assert_raises():
        _ = nr_redcap_rel17_hd_dmrs_bundling_window_ids(
            Span(starts),
            Span(ends),
            Span(transmitted),
            Span(dl_starts),
            Span(dl_ends),
        )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
