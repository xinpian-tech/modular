"""Independent exact evidence for Rel-17 RedCap idle/inactive access."""

from std.testing import assert_equal, assert_raises, TestSuite
from wireless_dsp.wireless.nr.redcap_idle_access import (
    NR_REDCAP_IDLE_ACCESS_PROFILE_ORDINARY_NR,
    NR_REDCAP_IDLE_ACCESS_PROFILE_REDCAP_REL17,
    NR_REDCAP_IDLE_ACCESS_PROFILE_EREDCAP_REL18,
    NR_REDCAP_IDLE_ACCESS_RRC_IDLE,
    NR_REDCAP_IDLE_ACCESS_RRC_INACTIVE,
    NR_REDCAP_IFRI_SIB1_UNAVAILABLE,
    NR_REDCAP_IFRI_ABSENT_REDCAP_UNSUPPORTED,
    NR_REDCAP_IFRI_ALLOWED,
    NR_REDCAP_IFRI_NOT_ALLOWED,
    NR_REDCAP_BARRING_CAUSE_NONE,
    NR_REDCAP_BARRING_CAUSE_MIB_ACQUISITION_FAILURE,
    NR_REDCAP_BARRING_CAUSE_SIB1_ACQUISITION_FAILURE,
    NR_REDCAP_BARRING_CAUSE_MIB_BARRED_SIB1_FAILURE,
    NR_REDCAP_BARRING_CAUSE_REDCAP_UNSUPPORTED,
    NR_REDCAP_BARRING_CAUSE_MATCHING_RX_BARRED,
    NR_REDCAP_BARRING_CAUSE_HALF_DUPLEX_NOT_ALLOWED,
    NR_REDCAP_BARRING_CAUSE_MIB_CELL_BARRED,
    NR_REDCAP_EXCLUSION_NONE,
    NR_REDCAP_EXCLUSION_DISCRETIONARY,
    NR_REDCAP_EXCLUSION_MANDATORY,
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


def _clean_context(
    *,
    rrc_state: Int = NR_REDCAP_IDLE_ACCESS_RRC_IDLE,
    rx_branches: Int = 1,
    half_duplex_fdd_only: Bool = False,
    mib_cell_barred: Bool = False,
    ifri_allowed: Bool = True,
    spectrum_is_licensed: Bool = True,
    same_network: Bool = True,
) raises -> NRRedCapIdleAccessContext:
    return NRRedCapIdleAccessContext(
        rrc_state,
        rx_branches,
        half_duplex_fdd_only=half_duplex_fdd_only,
        mib_cell_barred=mib_cell_barred,
        intra_freq_reselection_redcap_allowed=ifri_allowed,
        half_duplex_redcap_allowed_present=half_duplex_fdd_only,
        spectrum_is_licensed=spectrum_is_licensed,
        same_registered_or_selected_network=same_network,
    )


def _literal_ifri_status(context: NRRedCapIdleAccessContext) -> Int:
    # Independent transcription of the SIB1 field description.  Production
    # uses early-return state projection; this oracle is a literal truth table.
    if not context.sib1_acquired:
        return NR_REDCAP_IFRI_SIB1_UNAVAILABLE
    if context.intra_freq_reselection_redcap_present:
        return (
            NR_REDCAP_IFRI_ALLOWED
            if context.intra_freq_reselection_redcap_allowed
            else NR_REDCAP_IFRI_NOT_ALLOWED
        )
    return NR_REDCAP_IFRI_ABSENT_REDCAP_UNSUPPORTED


def _literal_sib1_cause(context: NRRedCapIdleAccessContext) -> Int:
    # Clause 5.2.2.4.2 ordering is material: absent IFRI ends the procedure
    # before Rx-specific or half-duplex bits are considered.
    if not context.intra_freq_reselection_redcap_present:
        return NR_REDCAP_BARRING_CAUSE_REDCAP_UNSUPPORTED
    var matching_barred = (
        context.rx_specific_barring_present
        and (
            (
                context.rx_branches == 1
                and context.cell_barred_redcap_1rx
            )
            or (
                context.rx_branches == 2
                and context.cell_barred_redcap_2rx
            )
        )
    )
    if matching_barred:
        return NR_REDCAP_BARRING_CAUSE_MATCHING_RX_BARRED
    if (
        context.half_duplex_fdd_only
        and not context.half_duplex_redcap_allowed_present
    ):
        return NR_REDCAP_BARRING_CAUSE_HALF_DUPLEX_NOT_ALLOWED
    return NR_REDCAP_BARRING_CAUSE_NONE


def _literal_full_cause(context: NRRedCapIdleAccessContext) -> Int:
    if not context.mib_acquired:
        return NR_REDCAP_BARRING_CAUSE_MIB_ACQUISITION_FAILURE
    if not context.sib1_acquired:
        return (
            NR_REDCAP_BARRING_CAUSE_MIB_BARRED_SIB1_FAILURE
            if context.mib_cell_barred
            else NR_REDCAP_BARRING_CAUSE_SIB1_ACQUISITION_FAILURE
        )
    var cause = _literal_sib1_cause(context)
    if cause != NR_REDCAP_BARRING_CAUSE_NONE:
        return cause
    return (
        NR_REDCAP_BARRING_CAUSE_MIB_CELL_BARRED
        if context.mib_cell_barred
        else NR_REDCAP_BARRING_CAUSE_NONE
    )


def test_official_sib1_ifri_rx_and_half_duplex_static_table() raises:
    # Static rows transcribed from TS 38.331 V17.17.0 clause 5.2.2.4.2 and
    # the SIB1 field descriptions.  Both Rx bits are deliberately opposite in
    # two rows to prove that only the matching branch is consumed.
    var absent_ifri = NRRedCapIdleAccessContext(
        NR_REDCAP_IDLE_ACCESS_RRC_IDLE,
        1,
        intra_freq_reselection_redcap_present=False,
        intra_freq_reselection_redcap_allowed=False,
        rx_specific_barring_present=True,
        cell_barred_redcap_1rx=True,
        cell_barred_redcap_2rx=True,
    )
    assert_equal(
        nr_redcap_rel17_ifri_status(absent_ifri),
        NR_REDCAP_IFRI_ABSENT_REDCAP_UNSUPPORTED,
    )
    assert_equal(
        nr_redcap_rel17_sib1_barring_cause(absent_ifri),
        NR_REDCAP_BARRING_CAUSE_REDCAP_UNSUPPORTED,
    )

    var one_rx = NRRedCapIdleAccessContext(
        NR_REDCAP_IDLE_ACCESS_RRC_IDLE,
        1,
        rx_specific_barring_present=True,
        cell_barred_redcap_1rx=False,
        cell_barred_redcap_2rx=True,
    )
    assert_equal(nr_redcap_rel17_matching_rx_barred(one_rx), False)
    assert_equal(
        nr_redcap_rel17_sib1_barring_cause(one_rx),
        NR_REDCAP_BARRING_CAUSE_NONE,
    )
    one_rx.cell_barred_redcap_1rx = True
    assert_equal(nr_redcap_rel17_matching_rx_barred(one_rx), True)
    assert_equal(
        nr_redcap_rel17_sib1_barring_cause(one_rx),
        NR_REDCAP_BARRING_CAUSE_MATCHING_RX_BARRED,
    )

    var two_rx = NRRedCapIdleAccessContext(
        NR_REDCAP_IDLE_ACCESS_RRC_INACTIVE,
        2,
        rx_specific_barring_present=True,
        cell_barred_redcap_1rx=True,
        cell_barred_redcap_2rx=False,
    )
    assert_equal(nr_redcap_rel17_matching_rx_barred(two_rx), False)
    two_rx.cell_barred_redcap_2rx = True
    assert_equal(nr_redcap_rel17_matching_rx_barred(two_rx), True)

    var half_duplex = NRRedCapIdleAccessContext(
        NR_REDCAP_IDLE_ACCESS_RRC_INACTIVE,
        1,
        half_duplex_fdd_only=True,
        half_duplex_redcap_allowed_present=False,
    )
    assert_equal(
        nr_redcap_rel17_sib1_barring_cause(half_duplex),
        NR_REDCAP_BARRING_CAUSE_HALF_DUPLEX_NOT_ALLOWED,
    )
    half_duplex.half_duplex_redcap_allowed_present = True
    assert_equal(
        nr_redcap_rel17_sib1_barring_cause(half_duplex),
        NR_REDCAP_BARRING_CAUSE_NONE,
    )


def test_official_clause_5_3_1_barring_plan_static_table() raises:
    var mib_missing = NRRedCapIdleAccessContext(
        NR_REDCAP_IDLE_ACCESS_RRC_IDLE,
        1,
        mib_acquired=False,
        mib_cell_barred=False,
        sib1_acquired=False,
        intra_freq_reselection_redcap_present=False,
        intra_freq_reselection_redcap_allowed=False,
    )
    var plan = nr_redcap_rel17_barring_plan(
        mib_missing, discretionary_exclusion_us=123456789
    )
    assert_equal(
        nr_redcap_rel17_idle_inactive_barring_cause(mib_missing),
        NR_REDCAP_BARRING_CAUSE_MIB_ACQUISITION_FAILURE,
    )
    assert_equal(plan.cause, NR_REDCAP_BARRING_CAUSE_MIB_ACQUISITION_FAILURE)
    assert_equal(plan.current_cell_exclusion_kind, NR_REDCAP_EXCLUSION_DISCRETIONARY)
    assert_equal(plan.current_cell_exclusion_us, 123456789)
    assert_equal(plan.same_frequency_candidate_allowed, True)

    var sib1_missing = NRRedCapIdleAccessContext(
        NR_REDCAP_IDLE_ACCESS_RRC_INACTIVE,
        2,
        sib1_acquired=False,
        intra_freq_reselection_redcap_present=False,
        intra_freq_reselection_redcap_allowed=False,
    )
    assert_equal(
        nr_redcap_rel17_ifri_status(sib1_missing),
        NR_REDCAP_IFRI_SIB1_UNAVAILABLE,
    )
    with assert_raises():
        _ = nr_redcap_rel17_matching_rx_barred(sib1_missing)
    with assert_raises():
        _ = nr_redcap_rel17_sib1_barring_cause(sib1_missing)
    plan = nr_redcap_rel17_barring_plan(sib1_missing)
    assert_equal(plan.cause, NR_REDCAP_BARRING_CAUSE_SIB1_ACQUISITION_FAILURE)
    assert_equal(plan.current_cell_exclusion_kind, NR_REDCAP_EXCLUSION_DISCRETIONARY)
    assert_equal(plan.current_cell_exclusion_us, 0)

    var barred_sib1_missing = NRRedCapIdleAccessContext(
        NR_REDCAP_IDLE_ACCESS_RRC_IDLE,
        1,
        mib_cell_barred=True,
        sib1_acquired=False,
        intra_freq_reselection_redcap_present=False,
        intra_freq_reselection_redcap_allowed=False,
    )
    plan = nr_redcap_rel17_barring_plan(barred_sib1_missing)
    assert_equal(plan.cause, NR_REDCAP_BARRING_CAUSE_MIB_BARRED_SIB1_FAILURE)
    assert_equal(plan.current_cell_exclusion_kind, NR_REDCAP_EXCLUSION_MANDATORY)
    assert_equal(plan.current_cell_exclusion_us, 300000000)
    assert_equal(plan.same_frequency_candidate_allowed, True)

    var unsupported = NRRedCapIdleAccessContext(
        NR_REDCAP_IDLE_ACCESS_RRC_IDLE,
        1,
        intra_freq_reselection_redcap_present=False,
        intra_freq_reselection_redcap_allowed=False,
    )
    plan = nr_redcap_rel17_barring_plan(unsupported)
    assert_equal(plan.cause, NR_REDCAP_BARRING_CAUSE_REDCAP_UNSUPPORTED)
    assert_equal(plan.current_cell_exclusion_us, 300000000)
    assert_equal(plan.same_frequency_candidate_allowed, True)

    var ifri_allowed_barred = _clean_context(mib_cell_barred=True)
    plan = nr_redcap_rel17_barring_plan(ifri_allowed_barred)
    assert_equal(plan.cause, NR_REDCAP_BARRING_CAUSE_MIB_CELL_BARRED)
    assert_equal(plan.current_cell_exclusion_us, 300000000)
    assert_equal(plan.same_frequency_candidate_allowed, True)
    assert_equal(plan.same_frequency_exclusion_kind, NR_REDCAP_EXCLUSION_NONE)

    var licensed_not_allowed = _clean_context(
        mib_cell_barred=True, ifri_allowed=False
    )
    plan = nr_redcap_rel17_barring_plan(licensed_not_allowed)
    assert_equal(plan.same_frequency_candidate_allowed, False)
    assert_equal(plan.same_frequency_exclusion_kind, NR_REDCAP_EXCLUSION_MANDATORY)
    assert_equal(plan.same_frequency_exclusion_us, 300000000)

    var shared_same_network = _clean_context(
        mib_cell_barred=True,
        ifri_allowed=False,
        spectrum_is_licensed=False,
        same_network=True,
    )
    plan = nr_redcap_rel17_barring_plan(shared_same_network)
    assert_equal(plan.same_frequency_candidate_allowed, False)

    var shared_other_network = _clean_context(
        mib_cell_barred=True,
        ifri_allowed=False,
        spectrum_is_licensed=False,
        same_network=False,
    )
    plan = nr_redcap_rel17_barring_plan(shared_other_network)
    assert_equal(plan.same_frequency_candidate_allowed, True)
    assert_equal(plan.same_frequency_exclusion_us, 0)


def test_barring_timer_exact_expiry_wide_time_and_candidate_composition() raises:
    var barred = _clean_context(mib_cell_barred=True, ifri_allowed=False)
    var plan = nr_redcap_rel17_barring_plan(barred)
    var start_us = Int.MAX - NR_REDCAP_IDLE_ACCESS_EXCLUSION_MAX_US
    var state = NRRedCapBarringTimerState(0)
    assert_equal(
        nr_redcap_rel17_start_barring_exclusions(state, plan, start_us), True
    )
    assert_equal(
        nr_redcap_rel17_barring_exclusion_active(
            state, start_us, NR_REDCAP_CANDIDATE_CURRENT_CELL
        ),
        True,
    )
    assert_equal(
        nr_redcap_rel17_barring_exclusion_active(
            state, Int.MAX - 1, NR_REDCAP_CANDIDATE_CURRENT_CELL
        ),
        True,
    )
    assert_equal(
        nr_redcap_rel17_barring_exclusion_active(
            state, Int.MAX, NR_REDCAP_CANDIDATE_CURRENT_CELL
        ),
        False,
    )
    assert_equal(
        nr_redcap_rel17_barring_exclusion_active(
            state, Int.MAX - 1, NR_REDCAP_CANDIDATE_SAME_FREQUENCY_PEER
        ),
        True,
    )

    # A newly decoded unbarred SIB1 cannot bypass an already-active timer; it
    # becomes eligible at exact expiry and still obeys the caller's ordinary
    # suitability result.
    var clean = _clean_context()
    assert_equal(
        nr_redcap_rel17_candidate_allowed(
            clean,
            state,
            Int.MAX - 1,
            NR_REDCAP_CANDIDATE_CURRENT_CELL,
        ),
        False,
    )
    assert_equal(
        nr_redcap_rel17_candidate_allowed(
            clean, state, Int.MAX, NR_REDCAP_CANDIDATE_CURRENT_CELL
        ),
        True,
    )
    assert_equal(
        nr_redcap_rel17_candidate_allowed(
            clean,
            state,
            Int.MAX,
            NR_REDCAP_CANDIDATE_CURRENT_CELL,
            ordinary_candidate_eligible=False,
        ),
        False,
    )

    var no_timer_plan = nr_redcap_rel17_barring_plan(
        NRRedCapIdleAccessContext(
            NR_REDCAP_IDLE_ACCESS_RRC_IDLE,
            1,
            mib_acquired=False,
            sib1_acquired=False,
            intra_freq_reselection_redcap_present=False,
            intra_freq_reselection_redcap_allowed=False,
        )
    )
    var no_timer_state = NRRedCapBarringTimerState(10)
    _ = nr_redcap_rel17_start_barring_exclusions(
        no_timer_state, no_timer_plan, 10
    )
    assert_equal(
        nr_redcap_rel17_barring_exclusion_active(
            no_timer_state, 10, NR_REDCAP_CANDIDATE_CURRENT_CELL
        ),
        False,
    )


def test_sib4_redcap_access_allowed_complete_static_table() raises:
    var context = _clean_context(rrc_state=NR_REDCAP_IDLE_ACCESS_RRC_INACTIVE)
    assert_equal(
        nr_redcap_rel17_inter_frequency_candidate_allowed(
            context,
            inter_freq_carrier_v1700_present=False,
            redcap_access_allowed_present=False,
        ),
        True,
    )
    assert_equal(
        nr_redcap_rel17_inter_frequency_candidate_allowed(
            context,
            inter_freq_carrier_v1700_present=True,
            redcap_access_allowed_present=False,
        ),
        False,
    )
    assert_equal(
        nr_redcap_rel17_inter_frequency_candidate_allowed(
            context,
            inter_freq_carrier_v1700_present=True,
            redcap_access_allowed_present=True,
        ),
        True,
    )
    assert_equal(
        nr_redcap_rel17_inter_frequency_candidate_allowed(
            context,
            inter_freq_carrier_v1700_present=True,
            redcap_access_allowed_present=True,
            ordinary_candidate_eligible=False,
        ),
        False,
    )


def test_seeded_property_and_independent_differential_oracle() raises:
    var seed = UInt64(0x38_304_5_3_1_5EED)
    for _ in range(512):
        seed = (
            seed * UInt64(6364136223846793005)
            + UInt64(1442695040888963407)
        )
        var rrc_state = Int((seed >> 1) & UInt64(1))
        var rx_branches = 1 + Int((seed >> 2) & UInt64(1))
        var half_only = ((seed >> 3) & UInt64(1)) == UInt64(1)
        var mib_barred = ((seed >> 4) & UInt64(1)) == UInt64(1)
        var ifri_present = ((seed >> 5) & UInt64(1)) == UInt64(1)
        var ifri_allowed = (
            ifri_present and ((seed >> 6) & UInt64(1)) == UInt64(1)
        )
        var rx_group = ((seed >> 7) & UInt64(1)) == UInt64(1)
        var one_barred = (
            rx_group and ((seed >> 8) & UInt64(1)) == UInt64(1)
        )
        var two_barred = (
            rx_group and ((seed >> 9) & UInt64(1)) == UInt64(1)
        )
        var half_allowed = ((seed >> 10) & UInt64(1)) == UInt64(1)
        var licensed = ((seed >> 11) & UInt64(1)) == UInt64(1)
        var same_network = ((seed >> 12) & UInt64(1)) == UInt64(1)
        var context = NRRedCapIdleAccessContext(
            rrc_state,
            rx_branches,
            half_duplex_fdd_only=half_only,
            mib_cell_barred=mib_barred,
            intra_freq_reselection_redcap_present=ifri_present,
            intra_freq_reselection_redcap_allowed=ifri_allowed,
            rx_specific_barring_present=rx_group,
            cell_barred_redcap_1rx=one_barred,
            cell_barred_redcap_2rx=two_barred,
            half_duplex_redcap_allowed_present=half_allowed,
            spectrum_is_licensed=licensed,
            same_registered_or_selected_network=same_network,
        )
        assert_equal(
            nr_redcap_rel17_ifri_status(context),
            _literal_ifri_status(context),
        )
        var expected_matching_rx_barred = (
            rx_group
            and (
                (rx_branches == 1 and one_barred)
                or (rx_branches == 2 and two_barred)
            )
        )
        assert_equal(
            nr_redcap_rel17_matching_rx_barred(context),
            expected_matching_rx_barred,
        )
        assert_equal(
            nr_redcap_rel17_sib1_barring_cause(context),
            _literal_sib1_cause(context),
        )
        var expected_cause = _literal_full_cause(context)
        assert_equal(
            nr_redcap_rel17_idle_inactive_barring_cause(context),
            expected_cause,
        )
        var plan = nr_redcap_rel17_barring_plan(context)
        assert_equal(
            plan.current_cell_candidate,
            expected_cause == NR_REDCAP_BARRING_CAUSE_NONE,
        )
        if expected_cause == NR_REDCAP_BARRING_CAUSE_NONE:
            assert_equal(plan.current_cell_exclusion_kind, NR_REDCAP_EXCLUSION_NONE)
            assert_equal(plan.same_frequency_candidate_allowed, True)
        else:
            assert_equal(plan.current_cell_exclusion_kind, NR_REDCAP_EXCLUSION_MANDATORY)
            assert_equal(plan.current_cell_exclusion_us, 300000000)
            var expected_block = False
            if expected_cause != NR_REDCAP_BARRING_CAUSE_REDCAP_UNSUPPORTED:
                expected_block = (
                    not ifri_allowed and (licensed or same_network)
                )
            assert_equal(
                plan.same_frequency_candidate_allowed, not expected_block
            )

            # Seeded timer/state differential: the oracle is the direct
            # half-open elapsed-duration relation, independent of the
            # production planner and timer helper.
            var start_us = Int((seed >> 16) & UInt64(0xFFFFF))
            var elapsed_us = Int(
                (seed >> 28)
                % UInt64(NR_REDCAP_IDLE_ACCESS_EXCLUSION_MAX_US + 1)
            )
            var timer_state = NRRedCapBarringTimerState(start_us)
            assert_equal(
                nr_redcap_rel17_start_barring_exclusions(
                    timer_state, plan, start_us
                ),
                True,
            )
            var expected_current_active = (
                plan.current_cell_exclusion_us > 0
                and elapsed_us < plan.current_cell_exclusion_us
            )
            var expected_frequency_active = (
                plan.same_frequency_exclusion_us > 0
                and elapsed_us < plan.same_frequency_exclusion_us
            )
            assert_equal(
                nr_redcap_rel17_barring_exclusion_active(
                    timer_state,
                    start_us + elapsed_us,
                    NR_REDCAP_CANDIDATE_CURRENT_CELL,
                ),
                expected_current_active,
            )
            assert_equal(
                nr_redcap_rel17_barring_exclusion_active(
                    timer_state,
                    start_us + elapsed_us,
                    NR_REDCAP_CANDIDATE_SAME_FREQUENCY_PEER,
                ),
                expected_frequency_active,
            )
            var newly_unbarred = _clean_context(
                rrc_state=rrc_state, rx_branches=rx_branches
            )
            assert_equal(
                nr_redcap_rel17_candidate_allowed(
                    newly_unbarred,
                    timer_state,
                    start_us + elapsed_us,
                    NR_REDCAP_CANDIDATE_CURRENT_CELL,
                ),
                not expected_current_active,
            )
            assert_equal(
                nr_redcap_rel17_candidate_allowed(
                    newly_unbarred,
                    timer_state,
                    start_us + elapsed_us,
                    NR_REDCAP_CANDIDATE_SAME_FREQUENCY_PEER,
                ),
                not expected_frequency_active,
            )

        var extension_present = ((seed >> 13) & UInt64(1)) == UInt64(1)
        var access_present = (
            extension_present
            and ((seed >> 14) & UInt64(1)) == UInt64(1)
        )
        assert_equal(
            nr_redcap_rel17_inter_frequency_candidate_allowed(
                context,
                inter_freq_carrier_v1700_present=extension_present,
                redcap_access_allowed_present=access_present,
            ),
            not extension_present or access_present,
        )

        # Flipping the non-matching Rx bit is a metamorphic no-op.
        var before = nr_redcap_rel17_sib1_barring_cause(context)
        if context.rx_branches == 1:
            context.cell_barred_redcap_2rx = (
                not context.cell_barred_redcap_2rx
                if context.rx_specific_barring_present
                else False
            )
        else:
            context.cell_barred_redcap_1rx = (
                not context.cell_barred_redcap_1rx
                if context.rx_specific_barring_present
                else False
            )
        assert_equal(nr_redcap_rel17_sib1_barring_cause(context), before)


def test_public_mutation_profile_integer_and_presence_edges() raises:
    with assert_raises():
        _ = NRRedCapIdleAccessContext(2, 1)
    with assert_raises():
        _ = NRRedCapIdleAccessContext(NR_REDCAP_IDLE_ACCESS_RRC_IDLE, 0)
    with assert_raises():
        _ = NRRedCapIdleAccessContext(
            NR_REDCAP_IDLE_ACCESS_RRC_IDLE,
            1,
            profile=NR_REDCAP_IDLE_ACCESS_PROFILE_ORDINARY_NR,
        )
    with assert_raises():
        _ = NRRedCapIdleAccessContext(
            NR_REDCAP_IDLE_ACCESS_RRC_IDLE,
            1,
            profile=NR_REDCAP_IDLE_ACCESS_PROFILE_EREDCAP_REL18,
        )
    with assert_raises():
        _ = NRRedCapIdleAccessContext(
            NR_REDCAP_IDLE_ACCESS_RRC_IDLE,
            1,
            mib_acquired=False,
        )
    with assert_raises():
        _ = NRRedCapIdleAccessContext(
            NR_REDCAP_IDLE_ACCESS_RRC_IDLE,
            1,
            sib1_acquired=False,
        )
    with assert_raises():
        _ = NRRedCapIdleAccessContext(
            NR_REDCAP_IDLE_ACCESS_RRC_IDLE,
            1,
            intra_freq_reselection_redcap_present=False,
            intra_freq_reselection_redcap_allowed=True,
        )
    with assert_raises():
        _ = NRRedCapIdleAccessContext(
            NR_REDCAP_IDLE_ACCESS_RRC_IDLE,
            1,
            rx_specific_barring_present=False,
            cell_barred_redcap_1rx=True,
        )

    var mutated = _clean_context()
    mutated.profile = NR_REDCAP_IDLE_ACCESS_PROFILE_EREDCAP_REL18
    with assert_raises():
        _ = nr_redcap_rel17_ifri_status(mutated)
    with assert_raises():
        _ = nr_redcap_rel17_matching_rx_barred(mutated)
    with assert_raises():
        _ = nr_redcap_rel17_sib1_barring_cause(mutated)
    var invalid_candidate_state = NRRedCapBarringTimerState(0)
    with assert_raises():
        _ = nr_redcap_rel17_candidate_allowed(
            mutated,
            invalid_candidate_state,
            0,
            NR_REDCAP_CANDIDATE_CURRENT_CELL,
        )
    mutated = _clean_context()
    mutated.sib1_acquired = False
    with assert_raises():
        _ = nr_redcap_rel17_idle_inactive_barring_cause(mutated)

    var mib_missing = NRRedCapIdleAccessContext(
        NR_REDCAP_IDLE_ACCESS_RRC_IDLE,
        1,
        mib_acquired=False,
        sib1_acquired=False,
        intra_freq_reselection_redcap_present=False,
        intra_freq_reselection_redcap_allowed=False,
    )
    with assert_raises():
        _ = nr_redcap_rel17_barring_plan(
            mib_missing, discretionary_exclusion_us=-1
        )
    with assert_raises():
        _ = nr_redcap_rel17_barring_plan(
            mib_missing,
            discretionary_exclusion_us=(
                NR_REDCAP_IDLE_ACCESS_EXCLUSION_MAX_US + 1
            ),
        )
    with assert_raises():
        _ = nr_redcap_rel17_barring_plan(
            _clean_context(), discretionary_exclusion_us=1
        )
    with assert_raises():
        _ = nr_redcap_rel17_barring_plan(
            _clean_context(mib_cell_barred=True),
            discretionary_exclusion_us=1,
        )

    var plan = nr_redcap_rel17_barring_plan(
        _clean_context(mib_cell_barred=True)
    )
    plan.current_cell_exclusion_us -= 1
    with assert_raises():
        plan.validate()
    var unbarred_plan = nr_redcap_rel17_barring_plan(_clean_context())
    unbarred_plan.current_cell_candidate = False
    with assert_raises():
        unbarred_plan.validate()

    var timer_state = NRRedCapBarringTimerState(10)
    timer_state.current_cell_exclusion_duration_us = 1
    with assert_raises():
        timer_state.validate()
    timer_state = NRRedCapBarringTimerState(10)
    timer_state.profile = NR_REDCAP_IDLE_ACCESS_PROFILE_ORDINARY_NR
    with assert_raises():
        _ = nr_redcap_rel17_barring_exclusion_active(
            timer_state, 10, NR_REDCAP_CANDIDATE_CURRENT_CELL
        )
    timer_state = NRRedCapBarringTimerState(10)
    with assert_raises():
        _ = nr_redcap_rel17_barring_exclusion_active(
            timer_state, 9, NR_REDCAP_CANDIDATE_CURRENT_CELL
        )
    with assert_raises():
        _ = nr_redcap_rel17_barring_exclusion_active(timer_state, 10, 7)
    with assert_raises():
        _ = nr_redcap_rel17_start_barring_exclusions(
            timer_state, nr_redcap_rel17_barring_plan(_clean_context()), 10
        )

    with assert_raises():
        _ = nr_redcap_rel17_inter_frequency_candidate_allowed(
            _clean_context(),
            inter_freq_carrier_v1700_present=False,
            redcap_access_allowed_present=True,
        )

    var maximum_state = NRRedCapBarringTimerState(Int.MAX)
    assert_equal(
        nr_redcap_rel17_barring_exclusion_active(
            maximum_state, Int.MAX, NR_REDCAP_CANDIDATE_CURRENT_CELL
        ),
        False,
    )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
