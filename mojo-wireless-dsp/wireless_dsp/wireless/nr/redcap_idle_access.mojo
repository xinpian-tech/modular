"""Rel-17 RedCap idle/inactive access and barring decisions.

This scalar CPU reference implements the decoded-input subset of:

* 3GPP TS 38.300 V17.17.0 clause 16.13.3;
* 3GPP TS 38.304 V17.11.0 clause 5.3.1; and
* 3GPP TS 38.331 V17.17.0 clauses 5.2.2.4.1, 5.2.2.4.2,
  5.2.2.4.5 and 5.2.2.5, plus the SIB1/SIB4 field descriptions.

The module preserves the normative distinction between a discretionary
exclusion of *up to* 300 seconds and a mandatory exclusion for exactly
300 seconds.  The caller explicitly chooses the former duration.  Timer
activity uses subtraction and half-open intervals, so a timestamp near
``Int.MAX`` never requires an overflowing expiry-time addition.

All inputs are already-decoded MIB/SIB1/SIB4 state.  Ordinary cell
suitability, PLMN/SNPN/CAG reservation rules, RF acquisition, ASN.1,
selection/reselection measurements and network policy remain with the
caller.  Only RRC_IDLE and RRC_INACTIVE Rel-17 RedCap are accepted; ordinary
NR, Rel-18 eRedCap and RRC_CONNECTED/T311 behavior are not interchangeable
profiles in this bounded module.
"""


comptime NR_REDCAP_IDLE_ACCESS_PROFILE_ORDINARY_NR = 0
comptime NR_REDCAP_IDLE_ACCESS_PROFILE_REDCAP_REL17 = 1
comptime NR_REDCAP_IDLE_ACCESS_PROFILE_EREDCAP_REL18 = 2

comptime NR_REDCAP_IDLE_ACCESS_RRC_IDLE = 0
comptime NR_REDCAP_IDLE_ACCESS_RRC_INACTIVE = 1

comptime NR_REDCAP_IFRI_SIB1_UNAVAILABLE = 0
comptime NR_REDCAP_IFRI_ABSENT_REDCAP_UNSUPPORTED = 1
comptime NR_REDCAP_IFRI_ALLOWED = 2
comptime NR_REDCAP_IFRI_NOT_ALLOWED = 3

comptime NR_REDCAP_BARRING_CAUSE_NONE = 0
comptime NR_REDCAP_BARRING_CAUSE_MIB_ACQUISITION_FAILURE = 1
comptime NR_REDCAP_BARRING_CAUSE_SIB1_ACQUISITION_FAILURE = 2
comptime NR_REDCAP_BARRING_CAUSE_MIB_BARRED_SIB1_FAILURE = 3
comptime NR_REDCAP_BARRING_CAUSE_REDCAP_UNSUPPORTED = 4
comptime NR_REDCAP_BARRING_CAUSE_MATCHING_RX_BARRED = 5
comptime NR_REDCAP_BARRING_CAUSE_HALF_DUPLEX_NOT_ALLOWED = 6
comptime NR_REDCAP_BARRING_CAUSE_MIB_CELL_BARRED = 7

comptime NR_REDCAP_EXCLUSION_NONE = 0
comptime NR_REDCAP_EXCLUSION_DISCRETIONARY = 1
comptime NR_REDCAP_EXCLUSION_MANDATORY = 2

comptime NR_REDCAP_CANDIDATE_CURRENT_CELL = 0
comptime NR_REDCAP_CANDIDATE_SAME_FREQUENCY_PEER = 1

comptime NR_REDCAP_IDLE_ACCESS_EXCLUSION_MAX_US = 300000000


def _validate_rel17_profile(profile: Int) raises:
    if profile != NR_REDCAP_IDLE_ACCESS_PROFILE_REDCAP_REL17:
        raise Error("idle/inactive access requires Rel-17 RedCap")


def _validate_rrc_state(rrc_state: Int) raises:
    if (
        rrc_state != NR_REDCAP_IDLE_ACCESS_RRC_IDLE
        and rrc_state != NR_REDCAP_IDLE_ACCESS_RRC_INACTIVE
    ):
        raise Error("RedCap access state must be RRC_IDLE or RRC_INACTIVE")


def _validate_barring_cause(cause: Int) raises:
    if cause < NR_REDCAP_BARRING_CAUSE_NONE or (
        cause > NR_REDCAP_BARRING_CAUSE_MIB_CELL_BARRED
    ):
        raise Error("invalid RedCap barring cause")


def _validate_exclusion_kind(kind: Int) raises:
    if kind < NR_REDCAP_EXCLUSION_NONE or (
        kind > NR_REDCAP_EXCLUSION_MANDATORY
    ):
        raise Error("invalid RedCap exclusion kind")


def _validate_candidate_scope(scope: Int) raises:
    if scope != NR_REDCAP_CANDIDATE_CURRENT_CELL and (
        scope != NR_REDCAP_CANDIDATE_SAME_FREQUENCY_PEER
    ):
        raise Error("invalid RedCap candidate scope")


struct NRRedCapIdleAccessContext(ImplicitlyCopyable):
    """Decoded RedCap MIB/SIB1 state for one candidate cell.

    Optional ASN.1 fields use an explicit ``*_present`` Boolean.  A value bit
    cannot be set when its containing field or SIB was not acquired.  The
    network-identity flag is true for the exact TS 38.304 clause-5.3.1 union:
    an equivalent/registered/selected PLMN, or a registered/selected SNPN.
    """

    var profile: Int
    var rrc_state: Int
    var rx_branches: Int
    var half_duplex_fdd_only: Bool
    var mib_acquired: Bool
    var mib_cell_barred: Bool
    var sib1_acquired: Bool
    var intra_freq_reselection_redcap_present: Bool
    var intra_freq_reselection_redcap_allowed: Bool
    var rx_specific_barring_present: Bool
    var cell_barred_redcap_1rx: Bool
    var cell_barred_redcap_2rx: Bool
    var half_duplex_redcap_allowed_present: Bool
    var spectrum_is_licensed: Bool
    var same_registered_or_selected_network: Bool

    def __init__(
        out self,
        rrc_state: Int,
        rx_branches: Int,
        *,
        half_duplex_fdd_only: Bool = False,
        mib_acquired: Bool = True,
        mib_cell_barred: Bool = False,
        sib1_acquired: Bool = True,
        intra_freq_reselection_redcap_present: Bool = True,
        intra_freq_reselection_redcap_allowed: Bool = True,
        rx_specific_barring_present: Bool = False,
        cell_barred_redcap_1rx: Bool = False,
        cell_barred_redcap_2rx: Bool = False,
        half_duplex_redcap_allowed_present: Bool = False,
        spectrum_is_licensed: Bool = True,
        same_registered_or_selected_network: Bool = True,
        profile: Int = NR_REDCAP_IDLE_ACCESS_PROFILE_REDCAP_REL17,
    ) raises:
        self.profile = profile
        self.rrc_state = rrc_state
        self.rx_branches = rx_branches
        self.half_duplex_fdd_only = half_duplex_fdd_only
        self.mib_acquired = mib_acquired
        self.mib_cell_barred = mib_cell_barred
        self.sib1_acquired = sib1_acquired
        self.intra_freq_reselection_redcap_present = (
            intra_freq_reselection_redcap_present
        )
        self.intra_freq_reselection_redcap_allowed = (
            intra_freq_reselection_redcap_allowed
        )
        self.rx_specific_barring_present = rx_specific_barring_present
        self.cell_barred_redcap_1rx = cell_barred_redcap_1rx
        self.cell_barred_redcap_2rx = cell_barred_redcap_2rx
        self.half_duplex_redcap_allowed_present = (
            half_duplex_redcap_allowed_present
        )
        self.spectrum_is_licensed = spectrum_is_licensed
        self.same_registered_or_selected_network = (
            same_registered_or_selected_network
        )
        self.validate()

    def validate(self) raises:
        _validate_rel17_profile(self.profile)
        _validate_rrc_state(self.rrc_state)
        if self.rx_branches != 1 and self.rx_branches != 2:
            raise Error("Rel-17 RedCap access requires one or two Rx branches")
        if not self.mib_acquired:
            if self.mib_cell_barred or self.sib1_acquired:
                raise Error("MIB-unavailable state cannot contain MIB/SIB1 data")
        if not self.sib1_acquired and (
            self.intra_freq_reselection_redcap_present
            or self.intra_freq_reselection_redcap_allowed
            or self.rx_specific_barring_present
            or self.cell_barred_redcap_1rx
            or self.cell_barred_redcap_2rx
            or self.half_duplex_redcap_allowed_present
        ):
            raise Error("SIB1-unavailable state cannot contain decoded SIB1 data")
        if (
            not self.intra_freq_reselection_redcap_present
            and self.intra_freq_reselection_redcap_allowed
        ):
            raise Error("absent intraFreqReselectionRedCap has no value")
        if not self.rx_specific_barring_present and (
            self.cell_barred_redcap_1rx or self.cell_barred_redcap_2rx
        ):
            raise Error("absent cellBarredRedCap group has no Rx values")


def nr_redcap_rel17_ifri_status(
    context: NRRedCapIdleAccessContext,
) raises -> Int:
    """Return the four-state RedCap-specific IFRI projection.

    Absence after an acquired SIB1 is deliberately different from SIB1 not
    being acquired: TS 38.331 defines absence as lack of RedCap support.
    """
    context.validate()
    if not context.sib1_acquired:
        return NR_REDCAP_IFRI_SIB1_UNAVAILABLE
    if not context.intra_freq_reselection_redcap_present:
        return NR_REDCAP_IFRI_ABSENT_REDCAP_UNSUPPORTED
    if context.intra_freq_reselection_redcap_allowed:
        return NR_REDCAP_IFRI_ALLOWED
    return NR_REDCAP_IFRI_NOT_ALLOWED


def nr_redcap_rel17_matching_rx_barred(
    context: NRRedCapIdleAccessContext,
) raises -> Bool:
    """Apply only the one-/two-Rx SIB1 barring bit matching this UE."""
    context.validate()
    if not context.sib1_acquired:
        raise Error("Rx-specific barring requires an acquired SIB1")
    if not context.rx_specific_barring_present:
        return False
    if context.rx_branches == 1:
        return context.cell_barred_redcap_1rx
    return context.cell_barred_redcap_2rx


def nr_redcap_rel17_sib1_barring_cause(
    context: NRRedCapIdleAccessContext,
) raises -> Int:
    """Evaluate the ordered TS 38.331 clause-5.2.2.4.2 RedCap gates."""
    context.validate()
    if not context.sib1_acquired:
        raise Error("SIB1 barring cause requires an acquired SIB1")
    if not context.intra_freq_reselection_redcap_present:
        return NR_REDCAP_BARRING_CAUSE_REDCAP_UNSUPPORTED
    if nr_redcap_rel17_matching_rx_barred(context):
        return NR_REDCAP_BARRING_CAUSE_MATCHING_RX_BARRED
    if (
        context.half_duplex_fdd_only
        and not context.half_duplex_redcap_allowed_present
    ):
        return NR_REDCAP_BARRING_CAUSE_HALF_DUPLEX_NOT_ALLOWED
    return NR_REDCAP_BARRING_CAUSE_NONE


def nr_redcap_rel17_idle_inactive_barring_cause(
    context: NRRedCapIdleAccessContext,
) raises -> Int:
    """Compose MIB, essential-SI and RedCap SIB1 barring causes."""
    context.validate()
    if not context.mib_acquired:
        return NR_REDCAP_BARRING_CAUSE_MIB_ACQUISITION_FAILURE
    if not context.sib1_acquired:
        if context.mib_cell_barred:
            return NR_REDCAP_BARRING_CAUSE_MIB_BARRED_SIB1_FAILURE
        return NR_REDCAP_BARRING_CAUSE_SIB1_ACQUISITION_FAILURE
    var sib1_cause = nr_redcap_rel17_sib1_barring_cause(context)
    if sib1_cause != NR_REDCAP_BARRING_CAUSE_NONE:
        return sib1_cause
    if context.mib_cell_barred:
        return NR_REDCAP_BARRING_CAUSE_MIB_CELL_BARRED
    return NR_REDCAP_BARRING_CAUSE_NONE


struct NRRedCapBarringPlan(ImplicitlyCopyable):
    """Clause-5.3.1 candidate and exclusion result for one barred event."""

    var cause: Int
    var current_cell_candidate: Bool
    var same_frequency_candidate_allowed: Bool
    var current_cell_exclusion_kind: Int
    var current_cell_exclusion_us: Int
    var same_frequency_exclusion_kind: Int
    var same_frequency_exclusion_us: Int

    def __init__(
        out self,
        cause: Int,
        current_cell_candidate: Bool,
        same_frequency_candidate_allowed: Bool,
        current_cell_exclusion_kind: Int,
        current_cell_exclusion_us: Int,
        same_frequency_exclusion_kind: Int,
        same_frequency_exclusion_us: Int,
    ) raises:
        self.cause = cause
        self.current_cell_candidate = current_cell_candidate
        self.same_frequency_candidate_allowed = (
            same_frequency_candidate_allowed
        )
        self.current_cell_exclusion_kind = current_cell_exclusion_kind
        self.current_cell_exclusion_us = current_cell_exclusion_us
        self.same_frequency_exclusion_kind = same_frequency_exclusion_kind
        self.same_frequency_exclusion_us = same_frequency_exclusion_us
        self.validate()

    def validate(self) raises:
        _validate_barring_cause(self.cause)
        _validate_exclusion_kind(self.current_cell_exclusion_kind)
        _validate_exclusion_kind(self.same_frequency_exclusion_kind)
        if self.current_cell_exclusion_us < 0 or (
            self.current_cell_exclusion_us
            > NR_REDCAP_IDLE_ACCESS_EXCLUSION_MAX_US
        ):
            raise Error("current-cell RedCap exclusion exceeds 300 seconds")
        if self.same_frequency_exclusion_us < 0 or (
            self.same_frequency_exclusion_us
            > NR_REDCAP_IDLE_ACCESS_EXCLUSION_MAX_US
        ):
            raise Error("same-frequency RedCap exclusion exceeds 300 seconds")
        if self.current_cell_exclusion_kind == NR_REDCAP_EXCLUSION_NONE and (
            self.current_cell_exclusion_us != 0
        ):
            raise Error("no current-cell exclusion must have zero duration")
        if self.same_frequency_exclusion_kind == NR_REDCAP_EXCLUSION_NONE and (
            self.same_frequency_exclusion_us != 0
        ):
            raise Error("no same-frequency exclusion must have zero duration")
        if (
            self.current_cell_exclusion_kind == NR_REDCAP_EXCLUSION_MANDATORY
            and self.current_cell_exclusion_us
            != NR_REDCAP_IDLE_ACCESS_EXCLUSION_MAX_US
        ):
            raise Error("mandatory current-cell exclusion is exactly 300 seconds")
        if (
            self.same_frequency_exclusion_kind
            == NR_REDCAP_EXCLUSION_MANDATORY
            and self.same_frequency_exclusion_us
            != NR_REDCAP_IDLE_ACCESS_EXCLUSION_MAX_US
        ):
            raise Error("mandatory same-frequency exclusion is exactly 300 seconds")
        if self.cause == NR_REDCAP_BARRING_CAUSE_NONE:
            if (
                not self.current_cell_candidate
                or not self.same_frequency_candidate_allowed
                or self.current_cell_exclusion_kind
                != NR_REDCAP_EXCLUSION_NONE
                or self.same_frequency_exclusion_kind
                != NR_REDCAP_EXCLUSION_NONE
            ):
                raise Error("unbarred RedCap plan cannot exclude candidates")
            return
        if self.current_cell_candidate:
            raise Error("barred RedCap cell cannot remain a candidate")
        if (
            self.cause == NR_REDCAP_BARRING_CAUSE_MIB_ACQUISITION_FAILURE
            or self.cause
            == NR_REDCAP_BARRING_CAUSE_SIB1_ACQUISITION_FAILURE
        ):
            if (
                self.current_cell_exclusion_kind
                != NR_REDCAP_EXCLUSION_DISCRETIONARY
                or not self.same_frequency_candidate_allowed
                or self.same_frequency_exclusion_kind
                != NR_REDCAP_EXCLUSION_NONE
            ):
                raise Error("SI acquisition failure requires optional cell-only exclusion")
            return
        if self.current_cell_exclusion_kind != NR_REDCAP_EXCLUSION_MANDATORY:
            raise Error("normative RedCap barring requires 300-second cell exclusion")
        if self.same_frequency_candidate_allowed:
            if self.same_frequency_exclusion_kind != NR_REDCAP_EXCLUSION_NONE:
                raise Error("allowed same-frequency candidates cannot be excluded")
        elif self.same_frequency_exclusion_kind != NR_REDCAP_EXCLUSION_MANDATORY:
            raise Error("blocked same-frequency candidates require 300-second exclusion")


def nr_redcap_rel17_barring_plan(
    context: NRRedCapIdleAccessContext,
    *,
    discretionary_exclusion_us: Int = 0,
) raises -> NRRedCapBarringPlan:
    """Return the exact bounded TS 38.304 clause-5.3.1 barring action.

    ``discretionary_exclusion_us`` is consumed only for a MIB acquisition
    failure or a SIB1 acquisition failure when MIB did not indicate barred.
    It may be zero and must not exceed 300 seconds.  All other exclusions are
    mandatory and ignore no caller-selected policy.
    """
    context.validate()
    if discretionary_exclusion_us < 0 or (
        discretionary_exclusion_us
        > NR_REDCAP_IDLE_ACCESS_EXCLUSION_MAX_US
    ):
        raise Error("discretionary RedCap exclusion must be in [0,300 s]")

    var cause = nr_redcap_rel17_idle_inactive_barring_cause(context)
    if cause == NR_REDCAP_BARRING_CAUSE_NONE:
        if discretionary_exclusion_us != 0:
            raise Error("unbarred RedCap cell has no discretionary exclusion")
        return NRRedCapBarringPlan(
            cause,
            True,
            True,
            NR_REDCAP_EXCLUSION_NONE,
            0,
            NR_REDCAP_EXCLUSION_NONE,
            0,
        )

    if (
        cause == NR_REDCAP_BARRING_CAUSE_MIB_ACQUISITION_FAILURE
        or cause == NR_REDCAP_BARRING_CAUSE_SIB1_ACQUISITION_FAILURE
    ):
        return NRRedCapBarringPlan(
            cause,
            False,
            True,
            NR_REDCAP_EXCLUSION_DISCRETIONARY,
            discretionary_exclusion_us,
            NR_REDCAP_EXCLUSION_NONE,
            0,
        )

    if discretionary_exclusion_us != 0:
        raise Error("mandatory RedCap barring does not consume policy duration")

    # Clause 5.3.1 explicitly lets another same-frequency cell remain a
    # candidate when MIB-barred SIB1 cannot be acquired or the acquired SIB1
    # lacks the RedCap-specific IFRI (the cell does not support RedCap).
    if (
        cause == NR_REDCAP_BARRING_CAUSE_MIB_BARRED_SIB1_FAILURE
        or cause == NR_REDCAP_BARRING_CAUSE_REDCAP_UNSUPPORTED
    ):
        return NRRedCapBarringPlan(
            cause,
            False,
            True,
            NR_REDCAP_EXCLUSION_MANDATORY,
            NR_REDCAP_IDLE_ACCESS_EXCLUSION_MAX_US,
            NR_REDCAP_EXCLUSION_NONE,
            0,
        )

    var ifri_status = nr_redcap_rel17_ifri_status(context)
    if (
        ifri_status != NR_REDCAP_IFRI_ALLOWED
        and ifri_status != NR_REDCAP_IFRI_NOT_ALLOWED
    ):
        raise Error("decoded mandatory barring action requires an available IFRI")
    var same_frequency_blocked = (
        ifri_status == NR_REDCAP_IFRI_NOT_ALLOWED
        and (
            context.spectrum_is_licensed
            or context.same_registered_or_selected_network
        )
    )
    return NRRedCapBarringPlan(
        cause,
        False,
        not same_frequency_blocked,
        NR_REDCAP_EXCLUSION_MANDATORY,
        NR_REDCAP_IDLE_ACCESS_EXCLUSION_MAX_US,
        (
            NR_REDCAP_EXCLUSION_MANDATORY
            if same_frequency_blocked
            else NR_REDCAP_EXCLUSION_NONE
        ),
        (
            NR_REDCAP_IDLE_ACCESS_EXCLUSION_MAX_US
            if same_frequency_blocked
            else 0
        ),
    )


struct NRRedCapBarringTimerState(ImplicitlyCopyable):
    """Subtraction-safe timers for one barred cell and its frequency."""

    var profile: Int
    var last_update_us: Int
    var current_cell_exclusion_start_us: Int
    var current_cell_exclusion_duration_us: Int
    var same_frequency_exclusion_start_us: Int
    var same_frequency_exclusion_duration_us: Int

    def __init__(
        out self,
        current_time_us: Int,
        *,
        profile: Int = NR_REDCAP_IDLE_ACCESS_PROFILE_REDCAP_REL17,
    ) raises:
        self.profile = profile
        self.last_update_us = current_time_us
        self.current_cell_exclusion_start_us = -1
        self.current_cell_exclusion_duration_us = 0
        self.same_frequency_exclusion_start_us = -1
        self.same_frequency_exclusion_duration_us = 0
        self.validate()

    def validate(self) raises:
        _validate_rel17_profile(self.profile)
        if self.last_update_us < 0:
            raise Error("RedCap barring time must be non-negative")
        self._validate_timer_pair(
            self.current_cell_exclusion_start_us,
            self.current_cell_exclusion_duration_us,
        )
        self._validate_timer_pair(
            self.same_frequency_exclusion_start_us,
            self.same_frequency_exclusion_duration_us,
        )

    def _validate_timer_pair(self, start_us: Int, duration_us: Int) raises:
        if start_us == -1:
            if duration_us != 0:
                raise Error("inactive RedCap exclusion must have zero duration")
            return
        if start_us < 0 or start_us > self.last_update_us:
            raise Error("invalid RedCap exclusion start time")
        if duration_us < 1 or (
            duration_us > NR_REDCAP_IDLE_ACCESS_EXCLUSION_MAX_US
        ):
            raise Error("active RedCap exclusion must be in (0,300 s]")


def nr_redcap_rel17_start_barring_exclusions(
    mut state: NRRedCapBarringTimerState,
    plan: NRRedCapBarringPlan,
    current_time_us: Int,
) raises -> Bool:
    """Apply one barred event to the current-cell/frequency timer state."""
    state.validate()
    plan.validate()
    if current_time_us < state.last_update_us:
        raise Error("RedCap barring events must be time ordered")
    if plan.cause == NR_REDCAP_BARRING_CAUSE_NONE:
        raise Error("cannot start barring timers for an unbarred cell")

    if plan.current_cell_exclusion_us == 0:
        state.current_cell_exclusion_start_us = -1
        state.current_cell_exclusion_duration_us = 0
    else:
        state.current_cell_exclusion_start_us = current_time_us
        state.current_cell_exclusion_duration_us = (
            plan.current_cell_exclusion_us
        )
    if plan.same_frequency_exclusion_us == 0:
        state.same_frequency_exclusion_start_us = -1
        state.same_frequency_exclusion_duration_us = 0
    else:
        state.same_frequency_exclusion_start_us = current_time_us
        state.same_frequency_exclusion_duration_us = (
            plan.same_frequency_exclusion_us
        )
    state.last_update_us = current_time_us
    state.validate()
    return True


def nr_redcap_rel17_barring_exclusion_active(
    state: NRRedCapBarringTimerState,
    current_time_us: Int,
    candidate_scope: Int,
) raises -> Bool:
    """Return timer activity on a half-open interval at exact expiry."""
    state.validate()
    _validate_candidate_scope(candidate_scope)
    if current_time_us < state.last_update_us:
        raise Error("RedCap barring query must not move backwards in time")
    var start_us = state.current_cell_exclusion_start_us
    var duration_us = state.current_cell_exclusion_duration_us
    if candidate_scope == NR_REDCAP_CANDIDATE_SAME_FREQUENCY_PEER:
        start_us = state.same_frequency_exclusion_start_us
        duration_us = state.same_frequency_exclusion_duration_us
    if start_us == -1:
        return False
    # Ordered non-negative operands make subtraction safe even at Int.MAX.
    return current_time_us - start_us < duration_us


def nr_redcap_rel17_candidate_allowed(
    context: NRRedCapIdleAccessContext,
    state: NRRedCapBarringTimerState,
    current_time_us: Int,
    candidate_scope: Int,
    *,
    ordinary_candidate_eligible: Bool = True,
) raises -> Bool:
    """Compose RedCap access gates, exclusions and caller-owned base rules."""
    context.validate()
    state.validate()
    _validate_candidate_scope(candidate_scope)
    if not ordinary_candidate_eligible:
        return False
    if nr_redcap_rel17_barring_exclusion_active(
        state, current_time_us, candidate_scope
    ):
        return False
    var plan = nr_redcap_rel17_barring_plan(context)
    if candidate_scope == NR_REDCAP_CANDIDATE_CURRENT_CELL:
        return plan.current_cell_candidate
    return plan.same_frequency_candidate_allowed


def nr_redcap_rel17_inter_frequency_candidate_allowed(
    context: NRRedCapIdleAccessContext,
    *,
    inter_freq_carrier_v1700_present: Bool,
    redcap_access_allowed_present: Bool,
    ordinary_candidate_eligible: Bool = True,
) raises -> Bool:
    """Apply TS 38.331 clause-5.2.2.4.5 ``redCapAccessAllowed``.

    Rel-17 RedCap processes the carrier when the v1700 extension is absent,
    or when that extension is present and carries ``redCapAccessAllowed``.
    Presence of the inner field without its extension is rejected as an
    impossible decoded projection.
    """
    context.validate()
    if redcap_access_allowed_present and not (
        inter_freq_carrier_v1700_present
    ):
        raise Error("redCapAccessAllowed requires the SIB4 v1700 extension")
    if not ordinary_candidate_eligible:
        return False
    return (
        not inter_freq_carrier_v1700_present
        or redcap_access_allowed_present
    )
