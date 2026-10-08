"""Rel-17 RedCap low-mobility criteria, timing tables, and transitions.

This scalar CPU reference covers the decoded-input subset of 3GPP
TS 38.304 V17.11.0 clauses 5.2.4.9.0--5.2.4.9.2 and 3GPP TS 38.133
V17.22.0 clauses 4.2B.2.8, 4.2B.2.9.9--11, 4.2B.2.10.9--11,
4.2B.2.11.9--11, and 5.1B.2.8--11.

The idle timing lookup implements every no-eDRX and short-eDRX (at most
10.24 seconds) K1 row for the low-mobility and ordinary not-at-cell-edge
criteria.  The inactive lookup implements every effective-T row of the
long-eDRX K4 tables.  The long-eDRX idle/PTW tables are deliberately not
approximated here: their cross-PTW placement remains a separate missing
orchestration layer.

All inputs are already decoded RRC/RRM values.  The caller owns Srxlev/Squal
derivation, selection of the applicable measurement family and SMTC, TS 24.008
eDRX encoding legality, effective-T selection under TS 38.304 clause 7.1,
PTW placement, RF acquisition, and the choice between Tmeasure and Tevaluate
when starting a clause-4.2B.2.8 scenario transition.  Times are exact,
non-negative integer microseconds.  Ordinary NR, Rel-17 RedCap, and Rel-18
eRedCap have explicit, non-interchangeable profile tags.
"""

from std.math import isfinite


comptime NR_REDCAP_LOW_MOBILITY_PROFILE_ORDINARY_NR = 0
comptime NR_REDCAP_LOW_MOBILITY_PROFILE_REDCAP_REL17 = 1
comptime NR_REDCAP_LOW_MOBILITY_PROFILE_EREDCAP_REL18 = 2

comptime NR_REDCAP_LOW_MOBILITY_FR1 = 1
comptime NR_REDCAP_LOW_MOBILITY_FR2 = 2

comptime NR_REDCAP_RELAXED_FAMILY_INTRA_NR = 0
comptime NR_REDCAP_RELAXED_FAMILY_INTER_NR = 1
comptime NR_REDCAP_RELAXED_FAMILY_EUTRA = 2

comptime NR_REDCAP_RELAXED_CRITERION_LOW_MOBILITY = 0
comptime NR_REDCAP_RELAXED_CRITERION_NOT_AT_CELL_EDGE = 1

comptime NR_REDCAP_LOW_MOBILITY_COMBINE_REQUIRE_BOTH = 0
comptime NR_REDCAP_LOW_MOBILITY_COMBINE_ALLOW_EITHER = 1

comptime NR_REDCAP_RELAXED_STATE_IDLE = 0
comptime NR_REDCAP_RELAXED_STATE_INACTIVE = 1

comptime NR_REDCAP_RELAXED_COUNT_DRX = 0
comptime NR_REDCAP_RELAXED_COUNT_EDRX_IDLE = 1
comptime NR_REDCAP_RELAXED_COUNT_EFFECTIVE_T = 2

comptime NR_REDCAP_SCENARIO_NORMAL = 0
comptime NR_REDCAP_SCENARIO_LOW_MOBILITY = 1
comptime NR_REDCAP_SCENARIO_STATIONARY = 2
comptime NR_REDCAP_SCENARIO_STATIONARY_NOT_AT_CELL_EDGE = 3

comptime NR_REDCAP_LOW_MOBILITY_K1 = 3
comptime NR_REDCAP_LOW_MOBILITY_K4 = 3
comptime NR_REDCAP_LOW_MOBILITY_HIGH_PRIORITY_K2 = 60
comptime NR_REDCAP_LOW_MOBILITY_CELL_EDGE_NO_MEASUREMENT_LIMIT_US = 3600000000

comptime _US_320_MS = 320000
comptime _US_640_MS = 640000
comptime _US_1280_MS = 1280000
comptime _US_2560_MS = 2560000
comptime _US_5120_MS = 5120000
comptime _US_10240_MS = 10240000
comptime _US_20480_MS = 20480000
comptime _US_10485760_MS = 10485760000


def _validate_rel17_profile(profile: Int) raises:
    if profile != NR_REDCAP_LOW_MOBILITY_PROFILE_REDCAP_REL17:
        raise Error("low-mobility algorithms require Rel-17 RedCap")


def _validate_finite(value: Float64, name: StringSlice) raises:
    if not isfinite(value):
        raise Error(String(name) + " must be finite")


def _elapsed_us(start_us: Int, current_us: Int) raises -> Int:
    if start_us < 0 or current_us < start_us:
        raise Error("RedCap low-mobility time must be monotonic and non-negative")
    return current_us - start_us


def _checked_positive_product(lhs: Int, rhs: Int, name: StringSlice) raises -> Int:
    if lhs < 1 or rhs < 1 or lhs > Int.MAX // rhs:
        raise Error(String(name) + " overflows positive Int microseconds")
    return lhs * rhs


def _validate_frequency_range_and_rx(
    frequency_range: Int, rx_branches: Int
) raises:
    if frequency_range != NR_REDCAP_LOW_MOBILITY_FR1 and (
        frequency_range != NR_REDCAP_LOW_MOBILITY_FR2
    ):
        raise Error("RedCap low-mobility frequency range must be FR1 or FR2")
    if rx_branches != 1 and rx_branches != 2:
        raise Error("RedCap low-mobility Rx branch count must be one or two")
    if frequency_range == NR_REDCAP_LOW_MOBILITY_FR2 and rx_branches != 2:
        raise Error("Rel-17 RedCap FR2 low-mobility tables require two Rx")


def _validate_family(family: Int, frequency_range: Int) raises:
    if family != NR_REDCAP_RELAXED_FAMILY_INTRA_NR and (
        family != NR_REDCAP_RELAXED_FAMILY_INTER_NR
    ) and family != NR_REDCAP_RELAXED_FAMILY_EUTRA:
        raise Error("invalid RedCap relaxed-measurement family")
    if family == NR_REDCAP_RELAXED_FAMILY_EUTRA and (
        frequency_range != NR_REDCAP_LOW_MOBILITY_FR1
    ):
        raise Error("bounded RedCap E-UTRA timing tables apply in FR1")


def _validate_relaxed_criterion(criterion: Int) raises:
    if criterion != NR_REDCAP_RELAXED_CRITERION_LOW_MOBILITY and (
        criterion != NR_REDCAP_RELAXED_CRITERION_NOT_AT_CELL_EDGE
    ):
        raise Error("invalid RedCap K1/K4 relaxed-measurement criterion")


def _is_valid_smtc_periodicity_us(periodicity_us: Int) -> Bool:
    return (
        periodicity_us == 5000
        or periodicity_us == 10000
        or periodicity_us == 20000
        or periodicity_us == 40000
        or periodicity_us == 80000
        or periodicity_us == 160000
    )


def _validate_smtc_periodicity_us(periodicity_us: Int) raises:
    if not _is_valid_smtc_periodicity_us(periodicity_us):
        raise Error("invalid decoded RedCap SMTC periodicity")


def _is_idle_drx_cycle_us(cycle_us: Int) -> Bool:
    return (
        cycle_us == _US_320_MS
        or cycle_us == _US_640_MS
        or cycle_us == _US_1280_MS
        or cycle_us == _US_2560_MS
    )


def _is_short_idle_edrx_cycle_us(cycle_us: Int) -> Bool:
    return (
        cycle_us == _US_2560_MS
        or cycle_us == _US_5120_MS
        or cycle_us == _US_10240_MS
    )


def _is_effective_t_us(cycle_us: Int) -> Bool:
    return _is_idle_drx_cycle_us(cycle_us) or cycle_us == _US_5120_MS or (
        cycle_us == _US_10240_MS
    )


def _fr2_n1(cycle_us: Int) -> Int:
    if cycle_us == _US_320_MS:
        return 8
    if cycle_us == _US_640_MS:
        return 5
    if cycle_us == _US_1280_MS:
        return 4
    return 3


def _base_counts(cycle_us: Int) raises -> Tuple[Int, Int, Int]:
    if cycle_us == _US_320_MS:
        return (36, 4, 16)
    if cycle_us == _US_640_MS:
        return (28, 2, 8)
    if cycle_us == _US_1280_MS:
        return (25, 1, 5)
    if cycle_us == _US_2560_MS:
        return (23, 1, 3)
    if cycle_us == _US_5120_MS or cycle_us == _US_10240_MS:
        return (23, 1, 3)
    raise Error("invalid RedCap relaxed-measurement count cycle")


struct NRRedCapLowMobilityState(ImplicitlyCopyable):
    """Decoded Srxlev reference and dwell state for 38.304 clause 5.2.4.9.1."""

    var profile: Int
    var reference_srxlev_db: Float64
    var cell_selected_at_us: Int
    var last_update_us: Int
    var normal_measurements_since_us: Int
    var criterion_met_since_us: Int
    var criterion_unmet_since_us: Int

    def __init__(
        out self,
        current_srxlev_db: Float64,
        current_time_us: Int,
        *,
        normal_measurements_active: Bool = True,
        profile: Int = NR_REDCAP_LOW_MOBILITY_PROFILE_REDCAP_REL17,
    ) raises:
        self.profile = profile
        self.reference_srxlev_db = current_srxlev_db
        self.cell_selected_at_us = current_time_us
        self.last_update_us = current_time_us
        self.normal_measurements_since_us = (
            current_time_us if normal_measurements_active else -1
        )
        self.criterion_met_since_us = current_time_us
        self.criterion_unmet_since_us = -1
        self.validate()

    def validate(self) raises:
        """Reject a mutated profile, reference, or impossible timer record."""
        _validate_rel17_profile(self.profile)
        _validate_finite(self.reference_srxlev_db, "reference Srxlev")
        if self.cell_selected_at_us < 0 or (
            self.last_update_us < self.cell_selected_at_us
        ):
            raise Error("invalid RedCap low-mobility cell/update time")
        if self.normal_measurements_since_us < -1 or (
            self.normal_measurements_since_us > self.last_update_us
        ) or (
            self.normal_measurements_since_us >= 0
            and self.normal_measurements_since_us < self.cell_selected_at_us
        ):
            raise Error("invalid RedCap normal-measurement timer state")
        if self.criterion_met_since_us < -1 or (
            self.criterion_met_since_us > self.last_update_us
        ) or (
            self.criterion_met_since_us >= 0
            and self.criterion_met_since_us < self.cell_selected_at_us
        ):
            raise Error("invalid RedCap low-mobility met timer")
        if self.criterion_unmet_since_us < -1 or (
            self.criterion_unmet_since_us > self.last_update_us
        ) or (
            self.criterion_unmet_since_us >= 0
            and self.criterion_unmet_since_us < self.cell_selected_at_us
        ):
            raise Error("invalid RedCap low-mobility unmet timer")
        if self.criterion_met_since_us >= 0 and (
            self.criterion_unmet_since_us >= 0
        ):
            raise Error("RedCap low-mobility met/unmet timers are exclusive")
        if self.criterion_met_since_us == -1 and (
            self.criterion_unmet_since_us == -1
        ):
            raise Error("RedCap low-mobility state must track met or unmet")


def nr_redcap_rel17_low_mobility_delta_met(
    reference_srxlev_db: Float64,
    current_srxlev_db: Float64,
    s_search_delta_p_db: Float64,
    *,
    profile: Int = NR_REDCAP_LOW_MOBILITY_PROFILE_REDCAP_REL17,
) raises -> Bool:
    """Evaluate the strict 38.304 clause-5.2.4.9.1 Srxlev delta gate."""
    _validate_rel17_profile(profile)
    _validate_finite(reference_srxlev_db, "reference Srxlev")
    _validate_finite(current_srxlev_db, "current Srxlev")
    _validate_finite(s_search_delta_p_db, "SSearchDeltaP")
    if s_search_delta_p_db <= 0.0:
        raise Error("SSearchDeltaP must be positive")
    return reference_srxlev_db - current_srxlev_db < s_search_delta_p_db


def nr_redcap_rel17_low_mobility_update(
    mut state: NRRedCapLowMobilityState,
    current_srxlev_db: Float64,
    current_time_us: Int,
    t_search_delta_p_us: Int,
    s_search_delta_p_db: Float64,
    *,
    normal_measurements_active: Bool = True,
    cell_selected_or_reselected: Bool = False,
) raises -> Bool:
    """Advance the low-mobility reference/timers and return relaxation readiness.

    The reference resets on cell (re)selection, a strict Srxlev improvement,
    or the exact TSearchDeltaP unmet boundary.  Readiness additionally applies
    the normal-measurement and continuous-criterion dwell gates in clause
    5.2.4.9.0.  Srxlev itself is a caller-owned decoded measurement.
    """
    state.validate()
    _validate_finite(current_srxlev_db, "current Srxlev")
    _validate_finite(s_search_delta_p_db, "SSearchDeltaP")
    if t_search_delta_p_us < 1:
        raise Error("TSearchDeltaP must be positive")
    if s_search_delta_p_db <= 0.0:
        raise Error("SSearchDeltaP must be positive")
    if current_time_us < state.last_update_us:
        raise Error("RedCap low-mobility updates must be time ordered")

    if cell_selected_or_reselected:
        state.reference_srxlev_db = current_srxlev_db
        state.cell_selected_at_us = current_time_us
        state.last_update_us = current_time_us
        state.normal_measurements_since_us = (
            current_time_us if normal_measurements_active else -1
        )
        state.criterion_met_since_us = current_time_us
        state.criterion_unmet_since_us = -1
        state.validate()
        return False

    if current_srxlev_db - state.reference_srxlev_db > 0.0:
        state.reference_srxlev_db = current_srxlev_db

    if normal_measurements_active:
        if state.normal_measurements_since_us == -1:
            state.normal_measurements_since_us = current_time_us
    else:
        state.normal_measurements_since_us = -1

    var criterion_met = nr_redcap_rel17_low_mobility_delta_met(
        state.reference_srxlev_db,
        current_srxlev_db,
        s_search_delta_p_db,
    )
    if criterion_met:
        if state.criterion_met_since_us == -1:
            state.criterion_met_since_us = current_time_us
        state.criterion_unmet_since_us = -1
    else:
        state.criterion_met_since_us = -1
        if state.criterion_unmet_since_us == -1:
            state.criterion_unmet_since_us = current_time_us
        if _elapsed_us(
            state.criterion_unmet_since_us, current_time_us
        ) >= t_search_delta_p_us:
            state.reference_srxlev_db = current_srxlev_db
            state.criterion_met_since_us = current_time_us
            state.criterion_unmet_since_us = -1
            criterion_met = True

    state.last_update_us = current_time_us
    state.validate()
    if not criterion_met or state.normal_measurements_since_us == -1:
        return False
    return (
        _elapsed_us(state.criterion_met_since_us, current_time_us)
        >= t_search_delta_p_us
        and _elapsed_us(
            state.normal_measurements_since_us, current_time_us
        ) >= t_search_delta_p_us
    )


def nr_redcap_rel17_not_at_cell_edge_met(
    srxlev_db: Float64,
    squal_db: Float64,
    s_search_threshold_p_db: Float64,
    s_search_threshold_q_db: Float64,
    *,
    s_search_threshold_q_configured: Bool = True,
    profile: Int = NR_REDCAP_LOW_MOBILITY_PROFILE_REDCAP_REL17,
) raises -> Bool:
    """Evaluate the strict P/Q gates in 38.304 clause 5.2.4.9.2."""
    _validate_rel17_profile(profile)
    _validate_finite(srxlev_db, "current Srxlev")
    _validate_finite(squal_db, "current Squal")
    _validate_finite(s_search_threshold_p_db, "SSearchThresholdP")
    _validate_finite(s_search_threshold_q_db, "SSearchThresholdQ")
    if srxlev_db <= s_search_threshold_p_db:
        return False
    if s_search_threshold_q_configured and (
        squal_db <= s_search_threshold_q_db
    ):
        return False
    return True


def nr_redcap_rel17_combine_low_mobility_cell_edge_conditions(
    low_mobility_ready: Bool,
    not_at_cell_edge_ready: Bool,
    combine_policy: Int,
    *,
    profile: Int = NR_REDCAP_LOW_MOBILITY_PROFILE_REDCAP_REL17,
) raises -> Bool:
    """Apply decoded combineRelaxedMeasCondition AND/OR semantics exactly."""
    _validate_rel17_profile(profile)
    if combine_policy != NR_REDCAP_LOW_MOBILITY_COMBINE_REQUIRE_BOTH and (
        combine_policy != NR_REDCAP_LOW_MOBILITY_COMBINE_ALLOW_EITHER
    ):
        raise Error("invalid RedCap low-mobility combine policy")
    if combine_policy == NR_REDCAP_LOW_MOBILITY_COMBINE_REQUIRE_BOTH:
        return low_mobility_ready and not_at_cell_edge_ready
    return low_mobility_ready or not_at_cell_edge_ready


def nr_redcap_rel17_low_mobility_cell_edge_no_measurement_allowed(
    low_mobility_ready: Bool,
    not_at_cell_edge_ready: Bool,
    elapsed_since_reselection_measurement_us: Int,
    *,
    profile: Int = NR_REDCAP_LOW_MOBILITY_PROFILE_REDCAP_REL17,
) raises -> Bool:
    """Apply the strict one-hour combined-condition gate in 4.2B.2.9--11."""
    _validate_rel17_profile(profile)
    if elapsed_since_reselection_measurement_us < 0:
        raise Error("elapsed reselection-measurement time must be non-negative")
    return (
        low_mobility_ready
        and not_at_cell_edge_ready
        and elapsed_since_reselection_measurement_us
        < NR_REDCAP_LOW_MOBILITY_CELL_EDGE_NO_MEASUREMENT_LIMIT_US
    )


def nr_redcap_rel17_low_mobility_high_priority_search_interval_us(
    t_higher_priority_search_us: Int,
    *,
    high_priority_meas_relax_configured: Bool,
    low_mobility_ready: Bool,
    serving_above_non_intra_thresholds: Bool,
    profile: Int = NR_REDCAP_LOW_MOBILITY_PROFILE_REDCAP_REL17,
) raises -> Int:
    """Return T or K2*T for the low-mobility higher-priority search branch.

    This bounded API only accepts the clause-4.2B.2.10.9/.11.9 branch where
    low mobility is fulfilled and both serving non-intra thresholds are
    exceeded.  Other priority/threshold branches require a different table.
    """
    _validate_rel17_profile(profile)
    if t_higher_priority_search_us < 1:
        raise Error("Thigher_priority_search must be positive")
    if not low_mobility_ready or not serving_above_non_intra_thresholds:
        raise Error("inputs are outside the low-mobility higher-priority branch")
    if not high_priority_meas_relax_configured:
        return t_higher_priority_search_us
    return _checked_positive_product(
        t_higher_priority_search_us,
        NR_REDCAP_LOW_MOBILITY_HIGH_PRIORITY_K2,
        "K2 times Thigher_priority_search",
    )


struct _NRRedCapTimingValues(ImplicitlyCopyable):
    var n1: Int
    var m2_numerator: Int
    var relaxation_factor: Int
    var count_unit: Int
    var count_cycle_us: Int
    var detect_cycles: Int
    var measure_cycles: Int
    var evaluate_cycles: Int
    var detect_us: Int
    var measure_us: Int
    var evaluate_us: Int

    def __init__(
        out self,
        n1: Int,
        m2_numerator: Int,
        relaxation_factor: Int,
        count_unit: Int,
        count_cycle_us: Int,
        detect_cycles: Int,
        measure_cycles: Int,
        evaluate_cycles: Int,
    ) raises:
        self.n1 = n1
        self.m2_numerator = m2_numerator
        self.relaxation_factor = relaxation_factor
        self.count_unit = count_unit
        self.count_cycle_us = count_cycle_us
        self.detect_cycles = detect_cycles
        self.measure_cycles = measure_cycles
        self.evaluate_cycles = evaluate_cycles
        self.detect_us = _checked_positive_product(
            detect_cycles, count_cycle_us, "Tdetect"
        )
        self.measure_us = _checked_positive_product(
            measure_cycles, count_cycle_us, "Tmeasure"
        )
        self.evaluate_us = _checked_positive_product(
            evaluate_cycles, count_cycle_us, "Tevaluate"
        )


def _derive_timing_values(
    rrc_state: Int,
    family: Int,
    criterion: Int,
    frequency_range: Int,
    rx_branches: Int,
    smtc_periodicity_us: Int,
    drx_cycle_us: Int,
    edrx_idle_cycle_us: Int,
    effective_t_us: Int,
    profile: Int,
) raises -> _NRRedCapTimingValues:
    _validate_rel17_profile(profile)
    _validate_frequency_range_and_rx(frequency_range, rx_branches)
    _validate_family(family, frequency_range)
    _validate_relaxed_criterion(criterion)

    var count_unit: Int
    var count_cycle_us: Int
    var relaxation_factor: Int
    var m2_numerator = 2
    var n1 = 1

    if rrc_state == NR_REDCAP_RELAXED_STATE_IDLE:
        relaxation_factor = NR_REDCAP_LOW_MOBILITY_K1
        if effective_t_us != 0:
            raise Error("idle K1 timing cannot carry inactive effective T")
        if edrx_idle_cycle_us == 0:
            if not _is_idle_drx_cycle_us(drx_cycle_us):
                raise Error("invalid idle DRX cycle for K1 timing tables")
            count_unit = NR_REDCAP_RELAXED_COUNT_DRX
            count_cycle_us = drx_cycle_us
            if family != NR_REDCAP_RELAXED_FAMILY_EUTRA:
                _validate_smtc_periodicity_us(smtc_periodicity_us)
                if drx_cycle_us == _US_320_MS and (
                    smtc_periodicity_us > 20000
                ):
                    m2_numerator = 3
            elif smtc_periodicity_us != 0:
                raise Error("idle E-UTRA K1 table does not consume SMTC")
            if frequency_range == NR_REDCAP_LOW_MOBILITY_FR2:
                n1 = _fr2_n1(drx_cycle_us)
        else:
            if drx_cycle_us != 0:
                raise Error("short idle eDRX K1 tables mark DRX as N/A")
            if not _is_short_idle_edrx_cycle_us(edrx_idle_cycle_us):
                raise Error("idle K1 eDRX subset is exactly 2.56--10.24 s")
            count_unit = NR_REDCAP_RELAXED_COUNT_EDRX_IDLE
            count_cycle_us = edrx_idle_cycle_us
            if family != NR_REDCAP_RELAXED_FAMILY_EUTRA:
                _validate_smtc_periodicity_us(smtc_periodicity_us)
            elif smtc_periodicity_us != 0:
                raise Error("idle E-UTRA K1 table does not consume SMTC")
            if frequency_range == NR_REDCAP_LOW_MOBILITY_FR2:
                n1 = 3
    elif rrc_state == NR_REDCAP_RELAXED_STATE_INACTIVE:
        relaxation_factor = NR_REDCAP_LOW_MOBILITY_K4
        if drx_cycle_us != 0:
            raise Error("inactive K4 table consumes effective T, not DRX")
        if edrx_idle_cycle_us < _US_20480_MS or (
            edrx_idle_cycle_us > _US_10485760_MS
        ):
            raise Error("inactive K4 table requires long eDRX_IDLE")
        if not _is_effective_t_us(effective_t_us):
            raise Error("invalid effective T for inactive K4 timing")
        _validate_smtc_periodicity_us(smtc_periodicity_us)
        count_unit = NR_REDCAP_RELAXED_COUNT_EFFECTIVE_T
        count_cycle_us = effective_t_us
        if effective_t_us == _US_320_MS and smtc_periodicity_us > 20000:
            m2_numerator = 3
        if frequency_range == NR_REDCAP_LOW_MOBILITY_FR2:
            n1 = _fr2_n1(effective_t_us)
    else:
        raise Error("RedCap relaxed timing state must be IDLE or INACTIVE")

    var base = _base_counts(count_cycle_us)
    var base_detect = base[0]
    var base_measure = base[1]
    var base_evaluate = base[2]
    # The short-IDLE eDRX tables use two eDRX cycles for evaluation at
    # 5.12/10.24 s, while the INACTIVE effective-T tables use three cycles.
    if rrc_state == NR_REDCAP_RELAXED_STATE_IDLE and (
        count_unit == NR_REDCAP_RELAXED_COUNT_EDRX_IDLE
    ) and count_cycle_us >= _US_5120_MS:
        base_evaluate = 2
    var apply_m2 = (
        m2_numerator == 3
        and (
            rrc_state == NR_REDCAP_RELAXED_STATE_INACTIVE
            or family != NR_REDCAP_RELAXED_FAMILY_EUTRA
        )
        and count_cycle_us == _US_320_MS
    )
    var detect_cycles = base_detect * n1 * relaxation_factor
    var measure_cycles = base_measure * n1 * relaxation_factor
    var evaluate_cycles = base_evaluate * n1 * relaxation_factor
    if apply_m2:
        detect_cycles = detect_cycles * 3 // 2
        measure_cycles = measure_cycles * 3 // 2
        evaluate_cycles = evaluate_cycles * 3 // 2

    return _NRRedCapTimingValues(
        n1,
        m2_numerator if apply_m2 else 2,
        relaxation_factor,
        count_unit,
        count_cycle_us,
        detect_cycles,
        measure_cycles,
        evaluate_cycles,
    )


struct NRRedCapLowMobilityCellEdgeTiming(ImplicitlyCopyable):
    """Exact K1/K4 detect, measure, and evaluate integer table row."""

    var profile: Int
    var rrc_state: Int
    var family: Int
    var criterion: Int
    var frequency_range: Int
    var rx_branches: Int
    var smtc_periodicity_us: Int
    var drx_cycle_us: Int
    var edrx_idle_cycle_us: Int
    var effective_t_us: Int
    var n1: Int
    var m2_numerator: Int
    var relaxation_factor: Int
    var count_unit: Int
    var count_cycle_us: Int
    var detect_cycles: Int
    var measure_cycles: Int
    var evaluate_cycles: Int
    var detect_us: Int
    var measure_us: Int
    var evaluate_us: Int

    def __init__(
        out self,
        rrc_state: Int,
        family: Int,
        criterion: Int,
        frequency_range: Int,
        rx_branches: Int,
        smtc_periodicity_us: Int,
        drx_cycle_us: Int,
        edrx_idle_cycle_us: Int,
        effective_t_us: Int,
        *,
        profile: Int = NR_REDCAP_LOW_MOBILITY_PROFILE_REDCAP_REL17,
    ) raises:
        self.profile = profile
        self.rrc_state = rrc_state
        self.family = family
        self.criterion = criterion
        self.frequency_range = frequency_range
        self.rx_branches = rx_branches
        self.smtc_periodicity_us = smtc_periodicity_us
        self.drx_cycle_us = drx_cycle_us
        self.edrx_idle_cycle_us = edrx_idle_cycle_us
        self.effective_t_us = effective_t_us
        var expected = _derive_timing_values(
            rrc_state,
            family,
            criterion,
            frequency_range,
            rx_branches,
            smtc_periodicity_us,
            drx_cycle_us,
            edrx_idle_cycle_us,
            effective_t_us,
            profile,
        )
        self.n1 = expected.n1
        self.m2_numerator = expected.m2_numerator
        self.relaxation_factor = expected.relaxation_factor
        self.count_unit = expected.count_unit
        self.count_cycle_us = expected.count_cycle_us
        self.detect_cycles = expected.detect_cycles
        self.measure_cycles = expected.measure_cycles
        self.evaluate_cycles = expected.evaluate_cycles
        self.detect_us = expected.detect_us
        self.measure_us = expected.measure_us
        self.evaluate_us = expected.evaluate_us
        self.validate()

    def validate(self) raises:
        """Recompute the formal table row and reject mutated public state."""
        var expected = _derive_timing_values(
            self.rrc_state,
            self.family,
            self.criterion,
            self.frequency_range,
            self.rx_branches,
            self.smtc_periodicity_us,
            self.drx_cycle_us,
            self.edrx_idle_cycle_us,
            self.effective_t_us,
            self.profile,
        )
        if self.n1 != expected.n1 or (
            self.m2_numerator != expected.m2_numerator
        ) or self.relaxation_factor != expected.relaxation_factor or (
            self.count_unit != expected.count_unit
        ) or self.count_cycle_us != expected.count_cycle_us or (
            self.detect_cycles != expected.detect_cycles
        ) or self.measure_cycles != expected.measure_cycles or (
            self.evaluate_cycles != expected.evaluate_cycles
        ) or self.detect_us != expected.detect_us or (
            self.measure_us != expected.measure_us
        ) or self.evaluate_us != expected.evaluate_us:
            raise Error("mutated RedCap K1/K4 relaxed-measurement timing row")


def nr_redcap_rel17_idle_low_mobility_or_cell_edge_timing(
    family: Int,
    criterion: Int,
    frequency_range: Int,
    rx_branches: Int,
    smtc_periodicity_us: Int,
    drx_cycle_us: Int,
    *,
    edrx_idle_cycle_us: Int = 0,
    profile: Int = NR_REDCAP_LOW_MOBILITY_PROFILE_REDCAP_REL17,
) raises -> NRRedCapLowMobilityCellEdgeTiming:
    """Return an exact 4.2B.2.9--11 no/short-eDRX K1 table row."""
    return NRRedCapLowMobilityCellEdgeTiming(
        NR_REDCAP_RELAXED_STATE_IDLE,
        family,
        criterion,
        frequency_range,
        rx_branches,
        smtc_periodicity_us,
        drx_cycle_us,
        edrx_idle_cycle_us,
        0,
        profile=profile,
    )


def nr_redcap_rel17_inactive_low_mobility_or_cell_edge_timing(
    family: Int,
    criterion: Int,
    frequency_range: Int,
    rx_branches: Int,
    smtc_periodicity_us: Int,
    edrx_idle_cycle_us: Int,
    effective_t_us: Int,
    *,
    profile: Int = NR_REDCAP_LOW_MOBILITY_PROFILE_REDCAP_REL17,
) raises -> NRRedCapLowMobilityCellEdgeTiming:
    """Return an exact 5.1B.2.9--11 long-eDRX K4 effective-T row."""
    return NRRedCapLowMobilityCellEdgeTiming(
        NR_REDCAP_RELAXED_STATE_INACTIVE,
        family,
        criterion,
        frequency_range,
        rx_branches,
        smtc_periodicity_us,
        0,
        edrx_idle_cycle_us,
        effective_t_us,
        profile=profile,
    )


def _validate_scenario(scenario: Int) raises:
    if scenario < NR_REDCAP_SCENARIO_NORMAL or (
        scenario > NR_REDCAP_SCENARIO_STATIONARY_NOT_AT_CELL_EDGE
    ):
        raise Error("invalid RedCap measurement scenario")


def _is_delayed_scenario_pair(source: Int, target: Int) -> Bool:
    return (
        source == NR_REDCAP_SCENARIO_NORMAL
        and target != NR_REDCAP_SCENARIO_NORMAL
    ) or (
        source == NR_REDCAP_SCENARIO_LOW_MOBILITY
        and (
            target == NR_REDCAP_SCENARIO_STATIONARY
            or target == NR_REDCAP_SCENARIO_STATIONARY_NOT_AT_CELL_EDGE
        )
    )


def _is_immediate_scenario_pair(source: Int, target: Int) -> Bool:
    return (
        target == NR_REDCAP_SCENARIO_NORMAL
        and source != NR_REDCAP_SCENARIO_NORMAL
    ) or (
        target == NR_REDCAP_SCENARIO_LOW_MOBILITY
        and (
            source == NR_REDCAP_SCENARIO_STATIONARY
            or source == NR_REDCAP_SCENARIO_STATIONARY_NOT_AT_CELL_EDGE
        )
    )


struct NRRedCapMeasurementScenarioState(ImplicitlyCopyable):
    """Single-transition state for TS 38.133 clause 4.2B.2.8.

    ``selected_tnormal_us`` or ``selected_trelaxed_us`` is caller-owned and
    must be one applicable Tmeasure/Tevaluate value returned by a formal table.
    The clause defines no requirement for a second transition while a delayed
    transition is active, so the public start operation rejects it.
    """

    var profile: Int
    var current_scenario: Int
    var target_scenario: Int
    var transition_started_us: Int
    var transition_period_us: Int
    var last_update_us: Int
    var transition_active: Bool

    def __init__(
        out self,
        initial_scenario: Int,
        current_time_us: Int,
        *,
        profile: Int = NR_REDCAP_LOW_MOBILITY_PROFILE_REDCAP_REL17,
    ) raises:
        self.profile = profile
        self.current_scenario = initial_scenario
        self.target_scenario = initial_scenario
        self.transition_started_us = current_time_us
        self.transition_period_us = 0
        self.last_update_us = current_time_us
        self.transition_active = False
        self.validate()

    def validate(self) raises:
        """Reject mutated profiles, scenarios, and impossible pending state."""
        _validate_rel17_profile(self.profile)
        _validate_scenario(self.current_scenario)
        _validate_scenario(self.target_scenario)
        if self.transition_started_us < 0 or (
            self.last_update_us < self.transition_started_us
        ):
            raise Error("invalid RedCap scenario transition time")
        if self.transition_active:
            if self.transition_period_us < 1 or not _is_delayed_scenario_pair(
                self.current_scenario, self.target_scenario
            ):
                raise Error("invalid active RedCap scenario transition")
            if _elapsed_us(
                self.transition_started_us, self.last_update_us
            ) >= self.transition_period_us:
                raise Error("expired RedCap scenario transition was not settled")
        elif self.transition_period_us != 0 or (
            self.current_scenario != self.target_scenario
        ):
            raise Error("invalid settled RedCap scenario transition")


def nr_redcap_rel17_measurement_scenario_update(
    mut state: NRRedCapMeasurementScenarioState, current_time_us: Int
) raises -> Int:
    """Advance one scenario transition and return the applicable requirement."""
    state.validate()
    if current_time_us < state.last_update_us:
        raise Error("RedCap scenario updates must be time ordered")
    if state.transition_active and _elapsed_us(
        state.transition_started_us, current_time_us
    ) >= state.transition_period_us:
        state.current_scenario = state.target_scenario
        state.transition_started_us = current_time_us
        state.transition_period_us = 0
        state.transition_active = False
    state.last_update_us = current_time_us
    state.validate()
    return state.current_scenario


def nr_redcap_rel17_start_measurement_scenario_transition(
    mut state: NRRedCapMeasurementScenarioState,
    target_scenario: Int,
    current_time_us: Int,
    *,
    selected_tnormal_us: Int = 0,
    selected_trelaxed_us: Int = 0,
) raises -> Int:
    """Start one exact 4.2B.2.8 normal/low/stationary transition.

    Normal-to-relaxed transitions retain normal requirements for Tnormal.
    Low-mobility-to-stationary transitions retain low-mobility requirements
    for Trelaxed.  The enumerated reverse transitions are immediate.  Pairs
    absent from clause 4.2B.2.8 are rejected rather than inferred.
    """
    _validate_scenario(target_scenario)
    # Work on a copy so an invalid period/pair cannot partially advance the
    # caller-visible state before raising.
    var next = state
    _ = nr_redcap_rel17_measurement_scenario_update(next, current_time_us)
    if next.transition_active:
        raise Error("multiple scenario transitions in one period are undefined")
    if target_scenario == next.current_scenario:
        raise Error("scenario transition target must differ from current")

    var source_scenario = next.current_scenario
    if _is_delayed_scenario_pair(source_scenario, target_scenario):
        var period_us: Int
        if source_scenario == NR_REDCAP_SCENARIO_NORMAL:
            if selected_tnormal_us < 1 or selected_trelaxed_us != 0:
                raise Error("normal transition requires only selected Tnormal")
            period_us = selected_tnormal_us
        else:
            if selected_trelaxed_us < 1 or selected_tnormal_us != 0:
                raise Error("stationary transition requires only selected Trelaxed")
            period_us = selected_trelaxed_us
        next.target_scenario = target_scenario
        next.transition_started_us = current_time_us
        next.transition_period_us = period_us
        next.last_update_us = current_time_us
        next.transition_active = True
    elif _is_immediate_scenario_pair(source_scenario, target_scenario):
        if selected_tnormal_us != 0 or selected_trelaxed_us != 0:
            raise Error("immediate scenario transition does not consume a period")
        next.current_scenario = target_scenario
        next.target_scenario = target_scenario
        next.transition_started_us = current_time_us
        next.transition_period_us = 0
        next.last_update_us = current_time_us
        next.transition_active = False
    else:
        raise Error("scenario pair has no 4.2B.2.8 transition requirement")
    next.validate()
    state = next
    return state.current_scenario


struct NRRedCapTimingRequirementTransitionState(ImplicitlyCopyable):
    """Less-stringent-period transition for eDRX/PTW configuration changes.

    TS 38.133 4.2B/5.1B requires the less stringent of the first and second
    timing requirements during a transition interval equal to that transition
    requirement, followed by the second requirement.  For positive maximum
    periods, less stringent means the larger integer-microsecond period.
    """

    var profile: Int
    var first_requirement_us: Int
    var second_requirement_us: Int
    var transition_requirement_us: Int
    var effective_requirement_us: Int
    var transition_started_us: Int
    var last_update_us: Int
    var transition_active: Bool

    def __init__(
        out self,
        first_requirement_us: Int,
        second_requirement_us: Int,
        current_time_us: Int,
        *,
        profile: Int = NR_REDCAP_LOW_MOBILITY_PROFILE_REDCAP_REL17,
    ) raises:
        self.profile = profile
        self.first_requirement_us = first_requirement_us
        self.second_requirement_us = second_requirement_us
        self.transition_requirement_us = max(
            first_requirement_us, second_requirement_us
        )
        self.effective_requirement_us = self.transition_requirement_us
        self.transition_started_us = current_time_us
        self.last_update_us = current_time_us
        self.transition_active = True
        self.validate()

    def validate(self) raises:
        """Reject mutated periods, profile, time, or effective requirement."""
        _validate_rel17_profile(self.profile)
        if self.first_requirement_us < 1 or self.second_requirement_us < 1:
            raise Error("timing transition requirements must be positive")
        var expected_transition = max(
            self.first_requirement_us, self.second_requirement_us
        )
        if self.transition_requirement_us != expected_transition:
            raise Error("mutated RedCap timing transition requirement")
        if self.transition_started_us < 0 or (
            self.last_update_us < self.transition_started_us
        ):
            raise Error("invalid RedCap timing transition time")
        var elapsed = _elapsed_us(
            self.transition_started_us, self.last_update_us
        )
        if self.transition_active:
            if elapsed >= self.transition_requirement_us or (
                self.effective_requirement_us != self.transition_requirement_us
            ):
                raise Error("invalid active RedCap timing transition")
        elif elapsed < self.transition_requirement_us or (
            self.effective_requirement_us != self.second_requirement_us
        ):
            raise Error("invalid completed RedCap timing transition")


def nr_redcap_rel17_timing_requirement_transition_update(
    mut state: NRRedCapTimingRequirementTransitionState,
    current_time_us: Int,
) raises -> Int:
    """Return max(first, second) before expiry and second at exact expiry."""
    state.validate()
    if current_time_us < state.last_update_us:
        raise Error("RedCap timing transition updates must be time ordered")
    if state.transition_active and _elapsed_us(
        state.transition_started_us, current_time_us
    ) >= state.transition_requirement_us:
        state.effective_requirement_us = state.second_requirement_us
        state.transition_active = False
    state.last_update_us = current_time_us
    state.validate()
    return state.effective_requirement_us
