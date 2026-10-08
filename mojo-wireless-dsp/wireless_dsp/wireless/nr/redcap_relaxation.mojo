"""Rel-17 RedCap stationary relaxed-measurement state decisions.

This CPU reference implements a decoded-configuration subset of 3GPP
TS 38.304 V17.11.0 clauses 5.2.4.9.0, 5.2.4.9.3, and 5.2.4.9.4, together with
the corresponding TS 38.133 V17.22.0 scenario gates in clauses 4.2B.2.9--11.
It also implements the bounded 300-second reselection-exclusion timer from
TS 38.304 clause 5.2.4.4 because that timer controls whether a decoded
candidate remains eligible.

Times are non-negative integer microseconds and link levels are finite dB
scalars already derived by the measurement layer.  RF acquisition, RRC ASN.1,
selection of a relaxation method, and the large 38.133 measurement-period
tables remain outside this module.  Ordinary NR, Rel-17 RedCap, and Rel-18
eRedCap use explicit profile tags; only the Rel-17 tag is accepted here.
"""

from std.math import isfinite


comptime NR_REDCAP_RELAXATION_PROFILE_ORDINARY_NR = 0
comptime NR_REDCAP_RELAXATION_PROFILE_REDCAP_REL17 = 1
comptime NR_REDCAP_RELAXATION_PROFILE_EREDCAP_REL18 = 2

comptime NR_REDCAP_RELAXATION_FR1 = 1
comptime NR_REDCAP_RELAXATION_FR2 = 2

# combineRelaxedMeasCondition2 configured means both predicates are required.
# When it is absent, 38.304 clause 5.2.4.9.0 permits the stationary-only path.
comptime NR_REDCAP_RELAXATION_COMBINE_AND = 0
comptime NR_REDCAP_RELAXATION_COMBINE_OR = 1

comptime NR_REDCAP_RESELECTION_EXCLUSION_MAX_US = 300000000
comptime NR_REDCAP_STATIONARY_NO_MEASUREMENT_LIMIT_US = 14400000000


def _validate_rel17_profile(profile: Int) raises:
    if profile != NR_REDCAP_RELAXATION_PROFILE_REDCAP_REL17:
        raise Error("stationary relaxed measurement requires Rel-17 RedCap")


def _validate_frequency_range_and_rx(
    frequency_range: Int, rx_branches: Int
) raises:
    if frequency_range != NR_REDCAP_RELAXATION_FR1 and (
        frequency_range != NR_REDCAP_RELAXATION_FR2
    ):
        raise Error("RedCap relaxation frequency range must be FR1 or FR2")
    if rx_branches != 1 and rx_branches != 2:
        raise Error("RedCap relaxation Rx branch count must be one or two")
    if frequency_range == NR_REDCAP_RELAXATION_FR2 and rx_branches != 2:
        raise Error("Rel-17 RedCap FR2 relaxation requires two Rx branches")


def _validate_finite(value: Float64, name: StringSlice) raises:
    if not isfinite(value):
        raise Error(String(name) + " must be finite")


def _elapsed_us(start_us: Int, current_us: Int) raises -> Int:
    if start_us < 0 or current_us < start_us:
        raise Error("RedCap relaxation time must be monotonic and non-negative")
    # Because both values are non-negative and ordered, subtraction cannot
    # overflow a signed Int.
    return current_us - start_us


struct NRRedCapStationaryRelaxationState(ImplicitlyCopyable):
    """State for the clause-5.2.4.9.3 stationary reference and timers.

    A non-negative ``*_since_us`` value denotes a continuously active
    condition.  ``-1`` denotes inactive.  Public updates revalidate the whole
    record so a caller cannot silently use a mutated ordinary-NR/eRedCap state
    as Rel-17 evidence.
    """

    var profile: Int
    var frequency_range: Int
    var rx_branches: Int
    var reference_srxlev_db: Float64
    var cell_selected_at_us: Int
    var last_update_us: Int
    var normal_measurements_since_us: Int
    var stationary_met_since_us: Int
    var stationary_unmet_since_us: Int

    def __init__(
        out self,
        frequency_range: Int,
        rx_branches: Int,
        current_srxlev_db: Float64,
        current_time_us: Int,
        *,
        normal_measurements_active: Bool = True,
        profile: Int = NR_REDCAP_RELAXATION_PROFILE_REDCAP_REL17,
    ) raises:
        self.profile = profile
        self.frequency_range = frequency_range
        self.rx_branches = rx_branches
        self.reference_srxlev_db = current_srxlev_db
        self.cell_selected_at_us = current_time_us
        self.last_update_us = current_time_us
        self.normal_measurements_since_us = (
            current_time_us if normal_measurements_active else -1
        )
        # For every valid positive SSearchDeltaP-Stationary, a freshly reset
        # reference satisfies (reference-current) < threshold at this instant.
        self.stationary_met_since_us = current_time_us
        self.stationary_unmet_since_us = -1
        self.validate()

    def validate(self) raises:
        _validate_rel17_profile(self.profile)
        _validate_frequency_range_and_rx(
            self.frequency_range, self.rx_branches
        )
        _validate_finite(self.reference_srxlev_db, "stationary reference Srxlev")
        if self.cell_selected_at_us < 0 or (
            self.last_update_us < self.cell_selected_at_us
        ):
            raise Error("invalid RedCap stationary cell/update time")
        if self.normal_measurements_since_us < -1 or (
            self.normal_measurements_since_us > self.last_update_us
        ) or (
            self.normal_measurements_since_us >= 0
            and self.normal_measurements_since_us < self.cell_selected_at_us
        ):
            raise Error("invalid RedCap normal-measurement timer state")
        if self.stationary_met_since_us < -1 or (
            self.stationary_met_since_us > self.last_update_us
        ) or (
            self.stationary_met_since_us >= 0
            and self.stationary_met_since_us < self.cell_selected_at_us
        ):
            raise Error("invalid RedCap stationary-met timer state")
        if self.stationary_unmet_since_us < -1 or (
            self.stationary_unmet_since_us > self.last_update_us
        ) or (
            self.stationary_unmet_since_us >= 0
            and self.stationary_unmet_since_us < self.cell_selected_at_us
        ):
            raise Error("invalid RedCap stationary-unmet timer state")
        if (
            self.stationary_met_since_us >= 0
            and self.stationary_unmet_since_us >= 0
        ):
            raise Error("RedCap stationary met/unmet timers are mutually exclusive")
        if (
            self.stationary_met_since_us == -1
            and self.stationary_unmet_since_us == -1
        ):
            raise Error("RedCap stationary state must track met or unmet time")


def nr_redcap_rel17_stationary_delta_met(
    reference_srxlev_db: Float64,
    current_srxlev_db: Float64,
    s_search_delta_p_stationary_db: Float64,
    *,
    profile: Int = NR_REDCAP_RELAXATION_PROFILE_REDCAP_REL17,
) raises -> Bool:
    """Evaluate the strict 38.304 clause-5.2.4.9.3 Srxlev delta gate."""
    _validate_rel17_profile(profile)
    _validate_finite(reference_srxlev_db, "stationary reference Srxlev")
    _validate_finite(current_srxlev_db, "current Srxlev")
    _validate_finite(
        s_search_delta_p_stationary_db,
        "SSearchDeltaP-Stationary",
    )
    if s_search_delta_p_stationary_db <= 0.0:
        raise Error("SSearchDeltaP-Stationary must be positive")
    return (
        reference_srxlev_db - current_srxlev_db
        < s_search_delta_p_stationary_db
    )


def nr_redcap_rel17_stationary_update(
    mut state: NRRedCapStationaryRelaxationState,
    current_srxlev_db: Float64,
    current_time_us: Int,
    t_search_delta_p_stationary_us: Int,
    s_search_delta_p_stationary_db: Float64,
    *,
    normal_measurements_active: Bool = True,
    cell_selected_or_reselected: Bool = False,
) raises -> Bool:
    """Advance the stationary reference/timers and return relaxation readiness.

    The reference resets on cell selection/reselection, on a strict Srxlev
    improvement, or at the exact instant the criterion has continuously not
    been met for ``TSearchDeltaP-Stationary``.  Readiness additionally requires
    continuous normal measurements and a continuously met stationary criterion
    for that same period, as required by clause 5.2.4.9.0.
    """
    state.validate()
    _validate_finite(current_srxlev_db, "current Srxlev")
    _validate_finite(
        s_search_delta_p_stationary_db,
        "SSearchDeltaP-Stationary",
    )
    if t_search_delta_p_stationary_us < 1:
        raise Error("TSearchDeltaP-Stationary must be positive")
    if s_search_delta_p_stationary_db <= 0.0:
        raise Error("SSearchDeltaP-Stationary must be positive")
    if current_time_us < state.last_update_us:
        raise Error("RedCap stationary updates must be time ordered")

    if cell_selected_or_reselected:
        state.reference_srxlev_db = current_srxlev_db
        state.cell_selected_at_us = current_time_us
        state.last_update_us = current_time_us
        state.normal_measurements_since_us = (
            current_time_us if normal_measurements_active else -1
        )
        state.stationary_met_since_us = current_time_us
        state.stationary_unmet_since_us = -1
        state.validate()
        return False

    if current_srxlev_db - state.reference_srxlev_db > 0.0:
        state.reference_srxlev_db = current_srxlev_db

    if normal_measurements_active:
        if state.normal_measurements_since_us == -1:
            state.normal_measurements_since_us = current_time_us
    else:
        state.normal_measurements_since_us = -1

    var criterion_met = nr_redcap_rel17_stationary_delta_met(
        state.reference_srxlev_db,
        current_srxlev_db,
        s_search_delta_p_stationary_db,
    )
    if criterion_met:
        if state.stationary_met_since_us == -1:
            state.stationary_met_since_us = current_time_us
        state.stationary_unmet_since_us = -1
    else:
        state.stationary_met_since_us = -1
        if state.stationary_unmet_since_us == -1:
            state.stationary_unmet_since_us = current_time_us
        if _elapsed_us(
            state.stationary_unmet_since_us, current_time_us
        ) >= t_search_delta_p_stationary_us:
            state.reference_srxlev_db = current_srxlev_db
            state.stationary_met_since_us = current_time_us
            state.stationary_unmet_since_us = -1
            criterion_met = True

    state.last_update_us = current_time_us
    state.validate()
    if not criterion_met or state.normal_measurements_since_us == -1:
        return False
    return (
        _elapsed_us(
            state.stationary_met_since_us, current_time_us
        ) >= t_search_delta_p_stationary_us
        and _elapsed_us(
            state.normal_measurements_since_us, current_time_us
        ) >= t_search_delta_p_stationary_us
    )


def nr_redcap_rel17_stationary_not_at_cell_edge_met(
    stationary_held_for_timer: Bool,
    srxlev_db: Float64,
    squal_db: Float64,
    s_search_threshold_p2_db: Float64,
    s_search_threshold_q2_db: Float64,
    *,
    s_search_threshold_q2_configured: Bool = True,
    profile: Int = NR_REDCAP_RELAXATION_PROFILE_REDCAP_REL17,
) raises -> Bool:
    """Evaluate clause-5.2.4.9.4 with strict P2 and optional Q2 gates."""
    _validate_rel17_profile(profile)
    _validate_finite(srxlev_db, "current Srxlev")
    _validate_finite(squal_db, "current Squal")
    _validate_finite(s_search_threshold_p2_db, "SSearchThresholdP2")
    _validate_finite(s_search_threshold_q2_db, "SSearchThresholdQ2")
    if not stationary_held_for_timer:
        return False
    if srxlev_db <= s_search_threshold_p2_db:
        return False
    if s_search_threshold_q2_configured and (
        squal_db <= s_search_threshold_q2_db
    ):
        return False
    return True


def nr_redcap_rel17_combine_relaxed_measurement_conditions(
    stationary_ready: Bool,
    stationary_not_at_cell_edge_ready: Bool,
    combine_policy: Int,
    *,
    profile: Int = NR_REDCAP_RELAXATION_PROFILE_REDCAP_REL17,
) raises -> Bool:
    """Apply the explicit ``combineRelaxedMeasCondition2`` AND/OR policy.

    The second predicate is the complete clause-5.2.4.9.4 result and therefore
    cannot be true unless the stationary timer is ready.  ``AND`` corresponds
    to the parameter being configured.  ``OR`` corresponds to it being absent
    and preserves the stationary-only fallback in clause 5.2.4.9.0.
    """
    _validate_rel17_profile(profile)
    if (
        combine_policy != NR_REDCAP_RELAXATION_COMBINE_AND
        and combine_policy != NR_REDCAP_RELAXATION_COMBINE_OR
    ):
        raise Error("invalid RedCap relaxed-measurement combine policy")
    if stationary_not_at_cell_edge_ready and not stationary_ready:
        raise Error("not-at-cell-edge-while-stationary requires stationary ready")
    if combine_policy == NR_REDCAP_RELAXATION_COMBINE_AND:
        return stationary_ready and stationary_not_at_cell_edge_ready
    return stationary_ready or stationary_not_at_cell_edge_ready


def nr_redcap_rel17_stationary_no_measurement_allowed(
    stationary_not_at_cell_edge_ready: Bool,
    elapsed_since_reselection_measurement_us: Int,
    *,
    profile: Int = NR_REDCAP_RELAXATION_PROFILE_REDCAP_REL17,
) raises -> Bool:
    """Apply the common strict less-than-four-hours 38.133 scenario gate.

    The same boundary appears in clauses 4.2B.2.9.3, 4.2B.2.10.3, and
    4.2B.2.11.3 for intra-NR, inter-NR, and inter-RAT E-UTRAN measurements.
    """
    _validate_rel17_profile(profile)
    if elapsed_since_reselection_measurement_us < 0:
        raise Error("elapsed reselection-measurement time must be non-negative")
    return stationary_not_at_cell_edge_ready and (
        elapsed_since_reselection_measurement_us
        < NR_REDCAP_STATIONARY_NO_MEASUREMENT_LIMIT_US
    )


def nr_redcap_rel17_reselection_exclusion_active(
    exclusion_start_us: Int,
    current_time_us: Int,
    *,
    exclusion_duration_us: Int = NR_REDCAP_RESELECTION_EXCLUSION_MAX_US,
    highest_ranked_cell_changed: Bool = False,
    entered_any_cell_selection: Bool = False,
    redirected_to_frequency: Bool = False,
    profile: Int = NR_REDCAP_RELAXATION_PROFILE_REDCAP_REL17,
) raises -> Bool:
    """Return whether a clause-5.2.4.4 reselection exclusion is still active.

    The configured implementation duration must be in ``(0,300 s]`` because
    the clause specifies a maximum of 300 seconds.  Activity uses a half-open
    interval, so it is false exactly at expiry.  The three explicit early
    removal events from clause 5.2.4.4 also clear the limitation.
    """
    _validate_rel17_profile(profile)
    if exclusion_duration_us < 1 or (
        exclusion_duration_us > NR_REDCAP_RESELECTION_EXCLUSION_MAX_US
    ):
        raise Error("RedCap reselection exclusion must not exceed 300 seconds")
    var elapsed_us = _elapsed_us(exclusion_start_us, current_time_us)
    if (
        highest_ranked_cell_changed
        or entered_any_cell_selection
        or redirected_to_frequency
    ):
        return False
    return elapsed_us < exclusion_duration_us
