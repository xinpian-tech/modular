"""Rel-17 RedCap half-duplex FDD scheduling reference algorithms.

This module implements the finite, decoded-configuration decisions introduced
for a reduced-capability half-duplex UE in paired FR1 spectrum.  The normative
baselines are 3GPP TS 38.213 V17.13.0 clause 17.2, TS 38.214 V17.16.0 clauses
6.1.2.1, 6.1.2.3.1, 6.1.2.3.3, 6.1.7, and 6.4, and TS 38.211 V17.10.0
Table 4.3.2-3.

All times use integer ``T_c`` units or absolute OFDM-symbol indexes supplied by
the caller.  RF switching, DCI decoding, RRC ASN.1, and scheduler policy are
outside this module.  Where clause 17.2 deliberately leaves a higher-layer
PRACH/MsgA conflict to the implementation, the API requires an explicit policy
and can return ``AMBIGUOUS`` instead of inventing a normative priority.
"""


comptime NR_REDCAP_HD_FDD_ACTION_RECEIVE_DOWNLINK = 0
comptime NR_REDCAP_HD_FDD_ACTION_TRANSMIT_UPLINK = 1
comptime NR_REDCAP_HD_FDD_ACTION_DROP_OR_CANCEL = 2
comptime NR_REDCAP_HD_FDD_ACTION_AMBIGUOUS = 3

comptime NR_REDCAP_HD_FDD_UPLINK_PUSCH_PUCCH = 0
comptime NR_REDCAP_HD_FDD_UPLINK_SRS = 1

comptime NR_REDCAP_HD_FDD_RA_POLICY_AMBIGUOUS = 0
comptime NR_REDCAP_HD_FDD_RA_POLICY_PREFER_UPLINK = 1
comptime NR_REDCAP_HD_FDD_RA_POLICY_PREFER_DOWNLINK = 2

comptime NR_REDCAP_HD_FDD_RA_TRIGGER_DCI_PRACH = 0
comptime NR_REDCAP_HD_FDD_RA_TRIGGER_HIGHER_LAYER_PRACH = 1
comptime NR_REDCAP_HD_FDD_RA_TRIGGER_HIGHER_LAYER_MSGA_PUSCH = 2

comptime NR_REDCAP_HD_FDD_RA_DECISION_CLEAR = 0
comptime NR_REDCAP_HD_FDD_RA_DECISION_DCI_PRACH_BLOCKED_BY_SSB = 1
comptime NR_REDCAP_HD_FDD_RA_DECISION_DCI_PRACH_PREEMPTS_DL = 2
comptime NR_REDCAP_HD_FDD_RA_DECISION_HIGHER_LAYER_DL_CHOICE = 3
comptime NR_REDCAP_HD_FDD_RA_DECISION_HIGHER_LAYER_SSB_CHOICE = 4
comptime NR_REDCAP_HD_FDD_RA_DECISION_HIGHER_LAYER_DL_SSB_CHOICE = 5
comptime NR_REDCAP_HD_FDD_RA_DECISION_HIGHER_LAYER_GUARD_CHOICE = 6

comptime NR_REDCAP_HD_PUSCH_TIMING_CAPABILITY_1 = 1
comptime NR_REDCAP_HD_PUSCH_TIMING_CAPABILITY_2 = 2

comptime NR_REDCAP_HD_PUSCH_TYPE_A_DCI_0_1_0_2 = 0
comptime NR_REDCAP_HD_PUSCH_TYPE_A_CONFIGURED_GRANT = 1
comptime NR_REDCAP_HD_PUSCH_TYPE_A_RAR_OR_TC_RNTI = 2
comptime NR_REDCAP_HD_PUSCH_TBMS_DCI_0_1_0_2 = 3
comptime NR_REDCAP_HD_PUSCH_TBMS_TYPE2_CONFIGURED_GRANT = 4

# TS 38.211 V17.10.0 Table 4.3.2-3.  Rel-17 RedCap HD-FDD Type A is
# restricted to FR1, so the FR2 value is intentionally not accepted here.
comptime NR_REDCAP_HD_FDD_FR1_RX_TO_TX_TC = 25600
comptime NR_REDCAP_HD_FDD_FR1_TX_TO_RX_TC = 25600


def _validate_uplink_kind(kind: Int) raises:
    if (
        kind != NR_REDCAP_HD_FDD_UPLINK_PUSCH_PUCCH
        and kind != NR_REDCAP_HD_FDD_UPLINK_SRS
    ):
        raise Error("RedCap HD-FDD uplink kind must be PUSCH/PUCCH or SRS")


def _validate_ra_policy(policy: Int) raises:
    if (
        policy != NR_REDCAP_HD_FDD_RA_POLICY_AMBIGUOUS
        and policy != NR_REDCAP_HD_FDD_RA_POLICY_PREFER_UPLINK
        and policy != NR_REDCAP_HD_FDD_RA_POLICY_PREFER_DOWNLINK
    ):
        raise Error("invalid RedCap HD-FDD higher-layer RA conflict policy")


def _validate_ra_trigger(trigger: Int) raises:
    if (
        trigger != NR_REDCAP_HD_FDD_RA_TRIGGER_DCI_PRACH
        and trigger != NR_REDCAP_HD_FDD_RA_TRIGGER_HIGHER_LAYER_PRACH
        and trigger
        != NR_REDCAP_HD_FDD_RA_TRIGGER_HIGHER_LAYER_MSGA_PUSCH
    ):
        raise Error("invalid RedCap HD-FDD random-access trigger")


def nr_redcap_rel17_clause_6_4_n2_twice_symbols(
    processing_capability: Int,
    mu: Int,
) raises -> Int:
    """Return exact ``2*N2`` from TS 38.214 Tables 6.4-1 and 6.4-2.

    Returning twice the symbol count represents the capability-2 value 5.5
    without floating-point arithmetic.  Capability 1 accepts every published
    table row, ``mu`` 0, 1, 2, 3, 5, and 6.  Capability 2 accepts ``mu`` 0,
    1, and 2; its ``mu=2`` row is specified for frequency range 1.  This
    module's Rel-17 RedCap HD-FDD decision profile is FR1, while the additional
    capability-1 rows are exposed only to reproduce the complete normative
    table.
    """
    if processing_capability == NR_REDCAP_HD_PUSCH_TIMING_CAPABILITY_1:
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
        raise Error("unsupported capability-1 PUSCH timing table row")
    if processing_capability == NR_REDCAP_HD_PUSCH_TIMING_CAPABILITY_2:
        if mu == 0:
            return 10
        if mu == 1:
            return 11
        if mu == 2:
            return 22
        raise Error("unsupported capability-2 PUSCH timing table row")
    raise Error("invalid PUSCH timing processing capability")


def _clause_6_4_t_proc2_for_mu_tc(
    processing_capability: Int,
    mu: Int,
    first_symbol_dmrs_only: Bool,
    d2_symbols: Int,
    text_tc: Int,
    switching_gap_tc: Int,
    bwp_switching_time_tc: Int,
) raises -> Int:
    var twice_n2 = nr_redcap_rel17_clause_6_4_n2_twice_symbols(
        processing_capability, mu
    )
    if (
        d2_symbols < 0
        or text_tc < 0
        or switching_gap_tc < 0
        or bwp_switching_time_tc < 0
    ):
        raise Error("negative TS 38.214 clause-6.4 timing term")

    # TS 38.211 clause 4.1 defines kappa=64.  Working in twice-symbol
    # units keeps Table 6.4-2's 5.5-symbol entry exact:
    # (2*N2 + 2*d2,1 + 2*d2) * (2048+144) * 64 / 2^(mu+1).
    var twice_symbol_count = Int128(twice_n2) + Int128(d2_symbols) * 2
    if not first_symbol_dmrs_only:
        twice_symbol_count += 2
    var numerator_tc = twice_symbol_count * Int128(2192 * 64)
    var denominator = Int128(1 << (mu + 1))
    if numerator_tc % denominator != 0:
        raise Error("PUSCH preparation time is not an exact T_c integer")
    var formula_tc = (
        numerator_tc // denominator
        + Int128(text_tc)
        + Int128(switching_gap_tc)
    )
    var result_tc = formula_tc
    if Int128(bwp_switching_time_tc) > result_tc:
        result_tc = Int128(bwp_switching_time_tc)
    if result_tc > Int128(Int.MAX):
        raise Error("PUSCH preparation time overflows Int T_c units")
    return Int(result_tc)


def nr_redcap_rel17_clause_6_4_t_proc2_tc(
    processing_capability: Int,
    mu_dl: Int,
    mu_ul: Int,
    *,
    first_symbol_dmrs_only: Bool = False,
    d2_symbols: Int = 0,
    text_tc: Int = 0,
    switching_gap_tc: Int = 0,
    bwp_switching_time_tc: Int = 0,
) raises -> Int:
    """Derive exact TS 38.214 clause-6.4 ``T_proc,2`` in ``T_c``.

    The result is the larger preparation time obtained with ``mu_dl`` and
    ``mu_ul``.  ``d2,1`` is zero only when the first PUSCH symbol consists of
    DM-RS alone, and is one otherwise.  ``d2_symbols`` is the separately
    reported priority-overlap term.  ``text_tc``, ``switching_gap_tc``, and
    ``bwp_switching_time_tc`` represent ``T_ext``, ``T_switch``, and
    ``d2,2`` respectively.  All non-symbol terms are already-decoded exact
    nonnegative ``T_c`` integers; carrier timing and RRC decoding remain
    outside this finite arithmetic API.
    """
    var dl_tc = _clause_6_4_t_proc2_for_mu_tc(
        processing_capability,
        mu_dl,
        first_symbol_dmrs_only,
        d2_symbols,
        text_tc,
        switching_gap_tc,
        bwp_switching_time_tc,
    )
    var ul_tc = _clause_6_4_t_proc2_for_mu_tc(
        processing_capability,
        mu_ul,
        first_symbol_dmrs_only,
        d2_symbols,
        text_tc,
        switching_gap_tc,
        bwp_switching_time_tc,
    )
    return dl_tc if dl_tc >= ul_tc else ul_tc


def nr_redcap_rel17_hd_t_proc2_tc(
    mu_pdcch: Int,
    mu_uplink: Int,
) raises -> Int:
    """Return the exact clause-17.2 HD-FDD cancellation threshold.

    TS 38.213 V17.13.0 clause 17.2 requires UE processing capability 1,
    ``d2,1=1``, and the smaller SCS configuration of the PDCCH and the
    SRS/PUCCH/PUSCH.  The declared Rel-17 RedCap paired-FR1 profile supports
    ``mu`` 0 through 2 and has no shared-spectrum extension, UL switching gap,
    priority-overlap report, or DCI-triggered BWP switch in this threshold, so
    the corresponding clause-6.4 terms are zero.
    """
    if (
        mu_pdcch < 0
        or mu_pdcch > 2
        or mu_uplink < 0
        or mu_uplink > 2
    ):
        raise Error("RedCap HD-FDD clause-17.2 supports FR1 mu 0 through 2")
    var mu = mu_pdcch if mu_pdcch <= mu_uplink else mu_uplink
    return _clause_6_4_t_proc2_for_mu_tc(
        NR_REDCAP_HD_PUSCH_TIMING_CAPABILITY_1,
        mu,
        False,
        0,
        0,
        0,
        0,
    )


def nr_redcap_rel17_hd_validate_schedule_overlap(
    dci_scheduled_dl_ul_overlap: Bool,
    dedicated_rx_tx_overlap: Bool,
    css_tx_overlap: Bool,
    *,
    css_is_type2: Bool = False,
    tx_is_clause19_1_cg_pusch: Bool = False,
    has_nonoverlap_paging_occasion_per_si_period: Bool = False,
) raises -> Bool:
    """Validate the two clause-17.2 schedule-overlap constraints.

    A UE does not expect opposing DCI-scheduled directions in the same symbol.
    Dedicated higher-layer DL and UL configurations cannot overlap.  The only
    separate exception represented here is a Type-2 PDCCH CSS overlapping the
    clause-19.1 configured-grant PUSCH when every SI modification period still
    has a nonoverlapping paging occasion, as delegated to TS 38.133 clause
    5.1B.2.6.  The three explicit flags prevent that exception from silently
    weakening the dedicated-configuration rule.
    """
    if dci_scheduled_dl_ul_overlap:
        raise Error("HD-FDD UE cannot receive opposing DCI schedules")
    if dedicated_rx_tx_overlap:
        raise Error("HD-FDD dedicated downlink and uplink overlap")
    if css_tx_overlap and not (
        css_is_type2
        and tx_is_clause19_1_cg_pusch
        and has_nonoverlap_paging_occasion_per_si_period
    ):
        raise Error("invalid Type-2 CSS and configured-grant overlap")
    return True


def nr_redcap_rel17_hd_configured_downlink_action(
    dci_scheduled_uplink_overlap: Bool,
) -> Int:
    """Resolve configured DL reception against an overlapping DCI UL grant."""
    if dci_scheduled_uplink_overlap:
        return NR_REDCAP_HD_FDD_ACTION_DROP_OR_CANCEL
    return NR_REDCAP_HD_FDD_ACTION_RECEIVE_DOWNLINK


def nr_redcap_rel17_hd_configured_uplink_action(
    uplink_kind: Int,
    elapsed_after_later_pdcch_end_tc: Int,
    t_proc2_tc: Int,
    dci_scheduled_downlink_overlap: Bool,
) raises -> Int:
    """Resolve configured PUSCH/PUCCH/SRS against DCI-scheduled downlink.

    Both time values are exact integer ``T_c`` units.  The elapsed interval is
    measured from the end of the later-ending PDCCH candidate to the CP start
    of the configured PUSCH/PUCCH occasion.  For SRS, pass the distance to the
    individual SRS symbol being evaluated.  ``t_proc2_tc`` is supplied by an
    upstream exact TS 38.214 clause-6.4 derivation.  A distance strictly below
    the threshold is the not-expected-to-cancel processing window; equality
    means processing time is available and cancellation applies.
    """
    _validate_uplink_kind(uplink_kind)
    if elapsed_after_later_pdcch_end_tc < 0 or t_proc2_tc < 1:
        raise Error("invalid RedCap HD-FDD PDCCH processing interval")
    if not dci_scheduled_downlink_overlap:
        return NR_REDCAP_HD_FDD_ACTION_TRANSMIT_UPLINK
    if elapsed_after_later_pdcch_end_tc < t_proc2_tc:
        return NR_REDCAP_HD_FDD_ACTION_TRANSMIT_UPLINK
    return NR_REDCAP_HD_FDD_ACTION_DROP_OR_CANCEL


def nr_redcap_rel17_hd_ssb_guard_action(
    uplink_kind: Int,
    uplink_start_tc: Int,
    uplink_end_tc: Int,
    *,
    previous_ssb_end_tc: Int = -1,
    next_ssb_start_tc: Int = -1,
    configured_by_higher_layers: Bool = True,
) raises -> Int:
    """Apply clause-17.2 SS/PBCH overlap and FR1 transition guards.

    Intervals are half-open ``[start,end)`` in ``T_c`` units.  Use ``-1`` when
    no previous or next SS/PBCH block exists.  For a configured PUSCH/PUCCH,
    call once for the whole occasion; for configured SRS, call once for every
    SRS symbol so only guard-violating symbols are removed.  A DCI-triggered
    occasion is rejected only on actual overlap, as specified separately in
    clause 17.2.
    """
    _validate_uplink_kind(uplink_kind)
    if uplink_start_tc < 0 or uplink_end_tc <= uplink_start_tc:
        raise Error("invalid RedCap HD-FDD uplink interval")
    if previous_ssb_end_tc < -1 or next_ssb_start_tc < -1:
        raise Error("invalid RedCap HD-FDD SS/PBCH boundary")
    if (
        previous_ssb_end_tc >= 0
        and next_ssb_start_tc >= 0
        and previous_ssb_end_tc > next_ssb_start_tc
    ):
        raise Error("RedCap HD-FDD SS/PBCH boundaries are reversed")

    if previous_ssb_end_tc >= 0:
        if uplink_start_tc < previous_ssb_end_tc:
            return NR_REDCAP_HD_FDD_ACTION_DROP_OR_CANCEL
        if configured_by_higher_layers and (
            uplink_start_tc - previous_ssb_end_tc
            < NR_REDCAP_HD_FDD_FR1_RX_TO_TX_TC
        ):
            return NR_REDCAP_HD_FDD_ACTION_DROP_OR_CANCEL
    if next_ssb_start_tc >= 0:
        if uplink_end_tc > next_ssb_start_tc:
            return NR_REDCAP_HD_FDD_ACTION_DROP_OR_CANCEL
        if configured_by_higher_layers and (
            next_ssb_start_tc - uplink_end_tc
            < NR_REDCAP_HD_FDD_FR1_TX_TO_RX_TC
        ):
            return NR_REDCAP_HD_FDD_ACTION_DROP_OR_CANCEL
    return NR_REDCAP_HD_FDD_ACTION_TRANSMIT_UPLINK


def nr_redcap_rel17_hd_ra_conflict_category(
    trigger: Int,
    overlaps_configured_downlink: Bool,
    overlaps_ssb: Bool,
    violates_transition_guard: Bool,
) raises -> Int:
    """Classify the distinct TS 38.213 clause-17.2 RA conflicts.

    ``DCI_PRACH`` represents only PRACH based on a detected DCI; clause 17.2
    defines no DCI-triggered MsgA PUSCH category.  Such PRACH is suppressed by
    actual SS/PBCH overlap, but otherwise an overlapping higher-layer
    configured DL reception is not received under the earlier DCI-priority
    rule.  Higher-layer PRACH and MsgA PUSCH instead leave DL/SSB overlap and
    the adjacent transition-guard conflict to UE implementation.  Separate
    categories preserve whether the implementation choice was caused by DL,
    SSB, both, or only a transition guard.
    """
    _validate_ra_trigger(trigger)
    if trigger == NR_REDCAP_HD_FDD_RA_TRIGGER_DCI_PRACH:
        if violates_transition_guard:
            raise Error("DCI-triggered PRACH has no clause-17.2 guard choice")
        if overlaps_ssb:
            return NR_REDCAP_HD_FDD_RA_DECISION_DCI_PRACH_BLOCKED_BY_SSB
        if overlaps_configured_downlink:
            return NR_REDCAP_HD_FDD_RA_DECISION_DCI_PRACH_PREEMPTS_DL
        return NR_REDCAP_HD_FDD_RA_DECISION_CLEAR

    if overlaps_configured_downlink and overlaps_ssb:
        return NR_REDCAP_HD_FDD_RA_DECISION_HIGHER_LAYER_DL_SSB_CHOICE
    if overlaps_configured_downlink:
        return NR_REDCAP_HD_FDD_RA_DECISION_HIGHER_LAYER_DL_CHOICE
    if overlaps_ssb:
        return NR_REDCAP_HD_FDD_RA_DECISION_HIGHER_LAYER_SSB_CHOICE
    if violates_transition_guard:
        return NR_REDCAP_HD_FDD_RA_DECISION_HIGHER_LAYER_GUARD_CHOICE
    return NR_REDCAP_HD_FDD_RA_DECISION_CLEAR


def nr_redcap_rel17_hd_ra_action(
    trigger: Int,
    overlaps_configured_downlink: Bool,
    overlaps_ssb: Bool,
    violates_transition_guard: Bool,
    *,
    policy: Int = NR_REDCAP_HD_FDD_RA_POLICY_AMBIGUOUS,
) raises -> Int:
    """Resolve an explicit clause-17.2 RA conflict category to an action.

    ``policy`` is consulted only for a higher-layer PRACH/MsgA implementation
    choice.  ``RECEIVE_DOWNLINK`` also means observing the indicated SS/PBCH
    block when the corresponding category contains SSB overlap.
    """
    _validate_ra_policy(policy)
    var category = nr_redcap_rel17_hd_ra_conflict_category(
        trigger,
        overlaps_configured_downlink,
        overlaps_ssb,
        violates_transition_guard,
    )
    if category == NR_REDCAP_HD_FDD_RA_DECISION_CLEAR:
        return NR_REDCAP_HD_FDD_ACTION_TRANSMIT_UPLINK
    if category == NR_REDCAP_HD_FDD_RA_DECISION_DCI_PRACH_PREEMPTS_DL:
        return NR_REDCAP_HD_FDD_ACTION_TRANSMIT_UPLINK
    if category == NR_REDCAP_HD_FDD_RA_DECISION_DCI_PRACH_BLOCKED_BY_SSB:
        return NR_REDCAP_HD_FDD_ACTION_DROP_OR_CANCEL
    if policy == NR_REDCAP_HD_FDD_RA_POLICY_AMBIGUOUS:
        return NR_REDCAP_HD_FDD_ACTION_AMBIGUOUS
    if policy == NR_REDCAP_HD_FDD_RA_POLICY_PREFER_UPLINK:
        return NR_REDCAP_HD_FDD_ACTION_TRANSMIT_UPLINK
    return NR_REDCAP_HD_FDD_ACTION_RECEIVE_DOWNLINK


def nr_redcap_rel17_hd_higher_layer_ra_action(
    overlaps_downlink_or_ssb: Bool,
    violates_transition_guard: Bool,
    *,
    policy: Int = NR_REDCAP_HD_FDD_RA_POLICY_AMBIGUOUS,
) raises -> Int:
    """Resolve the clause-17.2 implementation choice for PRACH/MsgA PUSCH.

    This compatibility API preserves its original combined overlap input.  Use
    :func:`nr_redcap_rel17_hd_ra_conflict_category` when DL and SS/PBCH
    overlap provenance must remain explicit.
    """
    return nr_redcap_rel17_hd_ra_action(
        NR_REDCAP_HD_FDD_RA_TRIGGER_HIGHER_LAYER_PRACH,
        overlaps_downlink_or_ssb,
        False,
        violates_transition_guard,
        policy=policy,
    )


def _validate_ssb_intervals(
    ssb_start_tc: Span[Int, ...], ssb_end_tc: Span[Int, ...]
) raises:
    if len(ssb_start_tc) != len(ssb_end_tc):
        raise Error("SS/PBCH interval arrays must have equal length")
    for index in range(len(ssb_start_tc)):
        if ssb_start_tc[index] < 0 or ssb_end_tc[index] <= ssb_start_tc[index]:
            raise Error("invalid SS/PBCH interval")


def _validate_pusch_profile(profile: Int) raises:
    if (
        profile != NR_REDCAP_HD_PUSCH_TYPE_A_DCI_0_1_0_2
        and profile != NR_REDCAP_HD_PUSCH_TYPE_A_CONFIGURED_GRANT
        and profile != NR_REDCAP_HD_PUSCH_TYPE_A_RAR_OR_TC_RNTI
        and profile != NR_REDCAP_HD_PUSCH_TBMS_DCI_0_1_0_2
        and profile != NR_REDCAP_HD_PUSCH_TBMS_TYPE2_CONFIGURED_GRANT
    ):
        raise Error("invalid RedCap HD-FDD PUSCH grant profile")


def _allocation_has_ssb_guard(
    allocation_start_tc: Int128,
    allocation_end_tc: Int128,
    ssb_start_tc: Span[Int, ...],
    ssb_end_tc: Span[Int, ...],
) -> Bool:
    for index in range(len(ssb_start_tc)):
        var ssb_start = Int128(ssb_start_tc[index])
        var ssb_end = Int128(ssb_end_tc[index])
        if allocation_end_tc <= ssb_start:
            if (
                ssb_start - allocation_end_tc
                < Int128(NR_REDCAP_HD_FDD_FR1_TX_TO_RX_TC)
            ):
                return False
        elif allocation_start_tc >= ssb_end:
            if (
                allocation_start_tc - ssb_end
                < Int128(NR_REDCAP_HD_FDD_FR1_RX_TO_TX_TC)
            ):
                return False
        else:
            return False
    return True


def nr_redcap_rel17_hd_tbms_required_slot_count(
    number_of_slots_tboms: Int,
    number_of_repetitions: Int = 1,
) raises -> Int:
    """Derive the bounded ``N*K`` TBMS slot count from clause 6.1.2.1.

    ``N`` is the decoded ``numberOfSlotsTBoMS`` value and must be greater than
    one for the TB-processing-over-multiple-slots procedure.  ``K`` is the
    decoded ``numberOfRepetitions`` value, or one when that field is absent.
    This declared repetition-capable Rel-17 profile enforces the normative
    expectation ``N*K <= 32`` and performs the product in ``Int128`` before
    returning an ``Int``.
    """
    if number_of_slots_tboms <= 1 or number_of_repetitions < 1:
        raise Error("invalid TBMS N or K configuration")
    var product = (
        Int128(number_of_slots_tboms) * Int128(number_of_repetitions)
    )
    if product > 32:
        raise Error("TBMS repetition-capable profile requires N*K <= 32")
    return Int(product)


def nr_redcap_rel17_hd_select_pusch_slots(
    start_slot: Int,
    candidate_slot_count: Int,
    required_slot_count: Int,
    slot_duration_tc: Int,
    allocation_start_tc_in_slot: Int,
    allocation_end_tc_in_slot: Int,
    ssb_start_tc: Span[Int, ...],
    ssb_end_tc: Span[Int, ...],
    *,
    pusch_profile: Int = NR_REDCAP_HD_PUSCH_TYPE_A_DCI_0_1_0_2,
    available_slot_counting: Bool = False,
    repetition_count: Int = 1,
    transmission_layers: Int = 1,
) raises -> List[Int]:
    """Select Rel-17 HD-RedCap PUSCH slots in paired spectrum.

    Candidate slots are consecutive from ``start_slot``.  Filtering is active
    for dynamic-DCI or configured-grant Type-A repetition only when
    ``AvailableSlotCounting`` is enabled and ``repetition_count > 1``.  RAR or
    TC-RNTI Type-A scheduling always remains consecutive even if the global
    feature is configured.  Both TB-processing-over-multiple-slots profiles
    always filter; for them ``required_slot_count`` is the already decoded
    ``N*K`` and ``repetition_count`` must remain one.  A candidate is skipped
    when its fixed symbol allocation lacks either FR1 transition guard around
    an SS/PBCH block.  Later clause-17.2 cancellation does not remove an
    already selected slot from the count.
    """
    _validate_ssb_intervals(ssb_start_tc, ssb_end_tc)
    _validate_pusch_profile(pusch_profile)
    if (
        start_slot < 0
        or candidate_slot_count < 1
        or required_slot_count < 1
        or required_slot_count > candidate_slot_count
        or slot_duration_tc < 1
        or allocation_start_tc_in_slot < 0
        or allocation_end_tc_in_slot <= allocation_start_tc_in_slot
        or allocation_end_tc_in_slot > slot_duration_tc
        or repetition_count < 1
        or transmission_layers != 1
    ):
        raise Error("invalid RedCap HD-FDD PUSCH slot-selection profile")
    var is_tbms = (
        pusch_profile == NR_REDCAP_HD_PUSCH_TBMS_DCI_0_1_0_2
        or pusch_profile == NR_REDCAP_HD_PUSCH_TBMS_TYPE2_CONFIGURED_GRANT
    )
    if not is_tbms and required_slot_count != repetition_count:
        raise Error("Type-A required slot count must equal repetition count")
    if is_tbms and repetition_count != 1:
        raise Error("TBMS uses predecoded N*K and the default repetition count")
    if is_tbms and required_slot_count > 32:
        raise Error("TBMS repetition-capable profile requires N*K <= 32")
    if start_slot > Int.MAX - (candidate_slot_count - 1):
        raise Error("RedCap HD-FDD candidate slot index overflows Int")

    var supports_available_slot_counting = (
        pusch_profile == NR_REDCAP_HD_PUSCH_TYPE_A_DCI_0_1_0_2
        or pusch_profile == NR_REDCAP_HD_PUSCH_TYPE_A_CONFIGURED_GRANT
    )
    var filter_slots = is_tbms or (
        supports_available_slot_counting
        and available_slot_counting
        and repetition_count > 1
    )
    var selected = List[Int](capacity=required_slot_count)
    for offset in range(candidate_slot_count):
        var slot_index = start_slot + offset
        var slot_base = Int128(slot_index) * Int128(slot_duration_tc)
        var allocation_start = (
            slot_base + Int128(allocation_start_tc_in_slot)
        )
        var allocation_end = slot_base + Int128(allocation_end_tc_in_slot)
        if allocation_end > Int128(Int.MAX):
            raise Error("RedCap HD-FDD allocation time overflows Int")
        if filter_slots and not _allocation_has_ssb_guard(
            allocation_start,
            allocation_end,
            ssb_start_tc,
            ssb_end_tc,
        ):
            continue
        selected.append(slot_index)
        if len(selected) == required_slot_count:
            break
    if len(selected) != required_slot_count:
        raise Error("insufficient RedCap HD-FDD PUSCH candidate slots")
    return selected^


def _interval_overlaps(
    first_start: Int,
    first_end: Int,
    second_start: Int,
    second_end: Int,
) -> Bool:
    return first_start < second_end and second_start < first_end


def nr_redcap_rel17_hd_dmrs_bundling_window_ids(
    transmission_start_symbols: Span[Int, ...],
    transmission_end_symbols: Span[Int, ...],
    dropped_or_cancelled: Span[UInt8, ...],
    downlink_start_symbols: Span[Int, ...],
    downlink_end_symbols: Span[Int, ...],
    *,
    window_restart_enabled: Bool = True,
) raises -> List[Int]:
    """Return actual-TDW IDs after the RedCap-specific clause-6.1.7 events.

    Intervals are half-open absolute symbol ranges.  A result of ``-1`` means
    that a dropped/cancelled transmission, or a post-event transmission when
    window restart is disabled, belongs to no actual TDW.  The function splits
    on clause-17.2 drops/cancellations and when the gap between consecutive
    transmitted occasions overlaps any DL reception/monitoring symbol.  Other
    generic clause-6.1.7 events must be supplied as pre-existing boundaries by
    invoking this function per nominal segment.
    """
    if (
        len(transmission_start_symbols) != len(transmission_end_symbols)
        or len(transmission_start_symbols) != len(dropped_or_cancelled)
        or len(downlink_start_symbols) != len(downlink_end_symbols)
    ):
        raise Error("RedCap DM-RS bundling interval arrays have unequal length")
    for index in range(len(downlink_start_symbols)):
        if (
            downlink_start_symbols[index] < 0
            or downlink_end_symbols[index] <= downlink_start_symbols[index]
        ):
            raise Error("invalid downlink reception/monitoring interval")

    var result = List[Int](capacity=len(transmission_start_symbols))
    var have_actual_window = False
    var restart_pending = False
    var current_window = -1
    var previous_actual_end = -1
    for index in range(len(transmission_start_symbols)):
        var start = transmission_start_symbols[index]
        var end = transmission_end_symbols[index]
        if start < 0 or end <= start:
            raise Error("invalid RedCap DM-RS transmission interval")
        if index > 0 and start < transmission_end_symbols[index - 1]:
            raise Error("RedCap DM-RS transmissions must be ordered and disjoint")
        if dropped_or_cancelled[index] > 1:
            raise Error("RedCap DM-RS drop flags must be binary")

        var overlaps_downlink = False
        for dl_index in range(len(downlink_start_symbols)):
            if _interval_overlaps(
                start,
                end,
                downlink_start_symbols[dl_index],
                downlink_end_symbols[dl_index],
            ):
                overlaps_downlink = True
                break
        if dropped_or_cancelled[index] == 1:
            result.append(-1)
            if have_actual_window:
                restart_pending = True
            continue
        if overlaps_downlink:
            raise Error("transmitted RedCap DM-RS occasion overlaps downlink")

        if have_actual_window and previous_actual_end >= 0:
            for dl_index in range(len(downlink_start_symbols)):
                if _interval_overlaps(
                    previous_actual_end,
                    start,
                    downlink_start_symbols[dl_index],
                    downlink_end_symbols[dl_index],
                ):
                    restart_pending = True
                    break

        if not have_actual_window:
            current_window = 0
            have_actual_window = True
        elif restart_pending:
            if not window_restart_enabled:
                result.append(-1)
                previous_actual_end = end
                continue
            current_window += 1
        result.append(current_window)
        restart_pending = False
        previous_actual_end = end
    return result^
