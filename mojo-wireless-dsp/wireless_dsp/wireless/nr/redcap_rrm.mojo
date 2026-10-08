"""Rel-17 RedCap RLM/BFD timing and L1-indication algorithms.

This CPU reference implements the finite arithmetic in 3GPP TS 38.133
V17.22.0 clauses 8.1B and 8.5B: RLM and beam-failure evaluation periods,
resource-set indication aggregation, and minimum L1 reporting intervals.
The formulas are evaluated in integer microseconds.  The measurement-
availability factor ``P`` is supplied as an exact positive rational, so every
normative ``Ceil`` is performed without a floating-point tie convention.

The APIs consume already decoded configuration and already derived link-
quality scalars/states.  They do not acquire RF samples, derive Qout/Qin from
hypothetical PDCCH BLER, construct measurement gaps/SMTC overlap, or apply the
TS 38.331 layer-3 filters.  All floating inputs are confined to the optional
scalar classifier and are rejected when non-finite.  Ordinary NR, Rel-17
RedCap, and Rel-18 eRedCap have explicit, non-interchangeable profile tags;
only the Rel-17 tag is accepted by this module's normative functions.
"""

from std.math import isfinite


comptime NR_REDCAP_RRM_PROFILE_ORDINARY_NR = 0
comptime NR_REDCAP_RRM_PROFILE_REDCAP_REL17 = 1
comptime NR_REDCAP_RRM_PROFILE_EREDCAP_REL18 = 2

comptime NR_REDCAP_RRM_FR1 = 1
comptime NR_REDCAP_RRM_FR2 = 2

comptime NR_REDCAP_RRM_RS_SSB = 0
comptime NR_REDCAP_RRM_RS_CSI_RS = 1

comptime NR_REDCAP_RRM_QUALITY_WORSE_THAN_QOUT = 0
comptime NR_REDCAP_RRM_QUALITY_BETWEEN_THRESHOLDS = 1
comptime NR_REDCAP_RRM_QUALITY_BETTER_THAN_QIN = 2

comptime NR_REDCAP_RRM_L1_NO_INDICATION = 0
comptime NR_REDCAP_RRM_L1_OUT_OF_SYNC = 1
comptime NR_REDCAP_RRM_L1_IN_SYNC = 2
comptime NR_REDCAP_RRM_L1_BEAM_FAILURE_INSTANCE = 3


def _validate_rel17_profile(profile: Int) raises:
    if profile != NR_REDCAP_RRM_PROFILE_REDCAP_REL17:
        raise Error("TS 38.133 clause 8.1B/8.5B API requires Rel-17 RedCap")


def _validate_frequency_range(frequency_range: Int) raises:
    if frequency_range != NR_REDCAP_RRM_FR1 and (
        frequency_range != NR_REDCAP_RRM_FR2
    ):
        raise Error("RedCap RRM frequency range must be FR1 or FR2")


def _validate_rx_branches(frequency_range: Int, rx_branches: Int) raises:
    if rx_branches != 1 and rx_branches != 2:
        raise Error("RedCap RRM Rx branch count must be one or two")
    if frequency_range == NR_REDCAP_RRM_FR2 and rx_branches != 2:
        raise Error("Rel-17 RedCap FR2 RLM/BFD tables require two Rx branches")


def _validate_rs_type(rs_type: Int) raises:
    if rs_type != NR_REDCAP_RRM_RS_SSB and (
        rs_type != NR_REDCAP_RRM_RS_CSI_RS
    ):
        raise Error("RedCap RRM reference signal must be SSB or CSI-RS")


def _is_valid_drx_cycle_us(drx_cycle_us: Int) -> Bool:
    # TS 38.331 LongDRX-CycleStartOffset cycle choices, expressed in us.
    return (
        drx_cycle_us == 10000
        or drx_cycle_us == 20000
        or drx_cycle_us == 32000
        or drx_cycle_us == 40000
        or drx_cycle_us == 60000
        or drx_cycle_us == 64000
        or drx_cycle_us == 70000
        or drx_cycle_us == 80000
        or drx_cycle_us == 128000
        or drx_cycle_us == 160000
        or drx_cycle_us == 256000
        or drx_cycle_us == 320000
        or drx_cycle_us == 512000
        or drx_cycle_us == 640000
        or drx_cycle_us == 1024000
        or drx_cycle_us == 1280000
        or drx_cycle_us == 2048000
        or drx_cycle_us == 2560000
        or drx_cycle_us == 5120000
        or drx_cycle_us == 10240000
    )


def _validate_drx(drx_enabled: Bool, drx_cycle_us: Int) raises:
    if drx_enabled:
        if not _is_valid_drx_cycle_us(drx_cycle_us):
            raise Error("invalid NR long-DRX cycle for RedCap RRM")
    elif drx_cycle_us != 0:
        raise Error("no-DRX RedCap RRM profile requires a zero DRX cycle")


def _is_valid_ssb_periodicity_us(periodicity_us: Int) -> Bool:
    return (
        periodicity_us == 5000
        or periodicity_us == 10000
        or periodicity_us == 20000
        or periodicity_us == 40000
        or periodicity_us == 80000
        or periodicity_us == 160000
    )


def _is_valid_rlm_csi_rs_periodicity_us(periodicity_us: Int) -> Bool:
    # TS 38.133 8.1B.3.2 limits this bounded CSI-RS RLM profile to these
    # four periodicities.  Clause 8.5B does not impose the same restriction.
    return (
        periodicity_us == 5000
        or periodicity_us == 10000
        or periodicity_us == 20000
        or periodicity_us == 40000
    )


def _validate_rlm_rs_periodicity(rs_type: Int, periodicity_us: Int) raises:
    _validate_rs_type(rs_type)
    if rs_type == NR_REDCAP_RRM_RS_SSB:
        if not _is_valid_ssb_periodicity_us(periodicity_us):
            raise Error("invalid SSB periodicity for RedCap RLM/BFD")
    elif not _is_valid_rlm_csi_rs_periodicity_us(periodicity_us):
        raise Error("RedCap CSI-RS RLM periodicity must be 5/10/20/40 ms")


def _validate_bfd_rs_periodicity(rs_type: Int, periodicity_us: Int) raises:
    _validate_rs_type(rs_type)
    if rs_type == NR_REDCAP_RRM_RS_SSB:
        if not _is_valid_ssb_periodicity_us(periodicity_us):
            raise Error("invalid SSB periodicity for RedCap BFD")
    elif periodicity_us <= 0:
        raise Error("RedCap CSI-RS BFD periodicity must be positive")


def _validate_csi_rs_table_profile(
    frequency_range: Int,
    rs_type: Int,
    csi_rs_density: Int,
    csi_rs_bandwidth_prbs: Int,
    csi_rs_repetition_on: Bool,
) raises:
    if rs_type == NR_REDCAP_RRM_RS_SSB:
        if (
            csi_rs_density != 0
            or csi_rs_bandwidth_prbs != 0
            or csi_rs_repetition_on
        ):
            raise Error("SSB RRM profile cannot carry CSI-RS parameters")
        return
    # Clauses 8.1B.3.2 and 8.5B.3.2 define the represented M values only for
    # density 3 and bandwidth at least 24 PRBs.  The upper limits are the
    # widest PRB grids possible within the Rel-17 RedCap maximum channel
    # bandwidth: 106 PRBs for FR1/20 MHz and 132 PRBs for FR2/100 MHz.  A
    # caller that knows the SCS must additionally enforce its narrower grid.
    if csi_rs_density != 3:
        raise Error("RedCap CSI-RS RLM/BFD table profile requires density 3")
    var maximum_prbs = 106 if frequency_range == NR_REDCAP_RRM_FR1 else 132
    if csi_rs_bandwidth_prbs < 24 or (
        csi_rs_bandwidth_prbs > maximum_prbs
    ):
        raise Error("RedCap CSI-RS RLM/BFD bandwidth exceeds its FR envelope")
    if csi_rs_repetition_on:
        raise Error("RedCap CSI-RS evaluation requirement excludes repetition ON")


def _validate_availability_factor(
    p_numerator: Int, p_denominator: Int
) raises:
    if (
        p_numerator < 1
        or p_denominator < 1
        or p_numerator < p_denominator
    ):
        raise Error("RedCap RRM availability factor P must be a rational >= 1")


def _max_int(lhs: Int, rhs: Int) -> Int:
    return lhs if lhs >= rhs else rhs


def _three_halves_us(value_us: Int) raises -> Int:
    var wide = Int128(3) * Int128(value_us)
    if wide % Int128(2) != 0:
        raise Error("RedCap RRM microsecond input cannot represent exact 1.5x")
    wide //= Int128(2)
    if wide > Int128(Int.MAX):
        raise Error("RedCap RRM 1.5x time exceeds Int")
    return Int(wide)


def _evaluation_period_us(
    coefficient_numerator: Int,
    coefficient_denominator: Int,
    p_numerator: Int,
    p_denominator: Int,
    frequency_scaling: Int,
    base_period_us: Int,
    minimum_period_us: Int,
) raises -> Int:
    # Exact Ceil(coefficient * P * N), followed by the table's period product.
    var numerator = (
        Int128(coefficient_numerator)
        * Int128(p_numerator)
        * Int128(frequency_scaling)
    )
    var denominator = (
        Int128(coefficient_denominator) * Int128(p_denominator)
    )
    var count = numerator // denominator
    if numerator % denominator != 0:
        count += Int128(1)
    var period_wide = count * Int128(base_period_us)
    if period_wide > Int128(Int.MAX):
        raise Error("RedCap RRM evaluation period exceeds Int")
    var period_us = Int(period_wide)
    return _max_int(minimum_period_us, period_us)


def _evaluation_mode(
    drx_enabled: Bool, drx_cycle_us: Int, force_no_drx: Bool
) -> Int:
    if force_no_drx or not drx_enabled:
        return 0
    return 1 if drx_cycle_us <= 320000 else 2


def _evaluation_base_period_us(
    mode: Int, rs_periodicity_us: Int, drx_cycle_us: Int
) -> Int:
    if mode == 0:
        return rs_periodicity_us
    if mode == 1:
        return _max_int(drx_cycle_us, rs_periodicity_us)
    return drx_cycle_us


def nr_redcap_rel17_classify_link_quality(
    quality: Float64,
    qout: Float64,
    qin: Float64,
    *,
    profile: Int = NR_REDCAP_RRM_PROFILE_REDCAP_REL17,
) raises -> Int:
    """Classify an already derived scalar for clause-8.1B aggregation.

    The scalar must use a monotonically higher-is-better scale.  Equality to
    either threshold is deliberately neither "worse" nor "better", matching
    the strict wording in clauses 8.1B.2.2 and 8.1B.3.2.
    """
    _validate_rel17_profile(profile)
    if not isfinite(quality) or not isfinite(qout) or not isfinite(qin):
        raise Error("RedCap RLM quality and thresholds must be finite")
    if qout >= qin:
        raise Error("RedCap RLM requires Qout below Qin")
    if quality < qout:
        return NR_REDCAP_RRM_QUALITY_WORSE_THAN_QOUT
    if quality > qin:
        return NR_REDCAP_RRM_QUALITY_BETTER_THAN_QIN
    return NR_REDCAP_RRM_QUALITY_BETWEEN_THRESHOLDS


def nr_redcap_rel17_rlm_evaluation_periods_us(
    frequency_range: Int,
    rx_branches: Int,
    rs_type: Int,
    rs_periodicity_us: Int,
    drx_enabled: Bool,
    drx_cycle_us: Int,
    p_numerator: Int,
    p_denominator: Int,
    *,
    csi_rs_density: Int = 0,
    csi_rs_bandwidth_prbs: Int = 0,
    csi_rs_repetition_on: Bool = False,
    t310_running: Bool = False,
    profile: Int = NR_REDCAP_RRM_PROFILE_REDCAP_REL17,
) raises -> Tuple[Int, Int]:
    """Return ``(TEvaluate_out, TEvaluate_in)`` in integer microseconds.

    This is Tables 8.1B.2.2-1..3 and 8.1B.3.2-1..3.  For SSB, FR2 uses
    ``N=8``; for CSI-RS, ``N=1``.  While T310 runs, clause 8.1B.6 selects the
    no-DRX evaluation profile even if DRX remains configured.
    """
    _validate_rel17_profile(profile)
    _validate_frequency_range(frequency_range)
    _validate_rx_branches(frequency_range, rx_branches)
    _validate_rlm_rs_periodicity(rs_type, rs_periodicity_us)
    _validate_drx(drx_enabled, drx_cycle_us)
    _validate_availability_factor(p_numerator, p_denominator)
    _validate_csi_rs_table_profile(
        frequency_range,
        rs_type,
        csi_rs_density,
        csi_rs_bandwidth_prbs,
        csi_rs_repetition_on,
    )

    var mode = _evaluation_mode(drx_enabled, drx_cycle_us, t310_running)
    var base_period_us = _evaluation_base_period_us(
        mode, rs_periodicity_us, drx_cycle_us
    )
    var scaling = (
        8
        if frequency_range == NR_REDCAP_RRM_FR2
        and rs_type == NR_REDCAP_RRM_RS_SSB
        else 1
    )
    var out_samples = 10
    var in_samples = 5
    if rs_type == NR_REDCAP_RRM_RS_SSB:
        if rx_branches == 1:
            out_samples = 20
    else:
        out_samples = 40 if rx_branches == 1 else 20
        in_samples = 10

    var coefficient_multiplier = 3 if mode == 1 else 1
    var coefficient_denominator = 2 if mode == 1 else 1
    var out_minimum_us = 0
    var in_minimum_us = 0
    if mode != 2:
        out_minimum_us = 400000 if rx_branches == 1 else 200000
        in_minimum_us = 100000

    return (
        _evaluation_period_us(
            out_samples * coefficient_multiplier,
            coefficient_denominator,
            p_numerator,
            p_denominator,
            scaling,
            base_period_us,
            out_minimum_us,
        ),
        _evaluation_period_us(
            in_samples * coefficient_multiplier,
            coefficient_denominator,
            p_numerator,
            p_denominator,
            scaling,
            base_period_us,
            in_minimum_us,
        ),
    )


def nr_redcap_rel17_bfd_evaluation_period_us(
    frequency_range: Int,
    rx_branches: Int,
    rs_type: Int,
    rs_periodicity_us: Int,
    drx_enabled: Bool,
    drx_cycle_us: Int,
    p_numerator: Int,
    p_denominator: Int,
    *,
    csi_rs_density: Int = 0,
    csi_rs_bandwidth_prbs: Int = 0,
    csi_rs_repetition_on: Bool = False,
    profile: Int = NR_REDCAP_RRM_PROFILE_REDCAP_REL17,
) raises -> Int:
    """Return the clause-8.5B BFD evaluation period in microseconds.

    This evaluates Tables 8.5B.2.2-1..2 and 8.5B.3.2-1..2.  The represented
    CSI-RS profile has ``M_BFD=10`` and ``P_BFD=1`` as specified in 8.5B.3.2.
    """
    _validate_rel17_profile(profile)
    _validate_frequency_range(frequency_range)
    _validate_rx_branches(frequency_range, rx_branches)
    _validate_bfd_rs_periodicity(rs_type, rs_periodicity_us)
    _validate_drx(drx_enabled, drx_cycle_us)
    _validate_availability_factor(p_numerator, p_denominator)
    _validate_csi_rs_table_profile(
        frequency_range,
        rs_type,
        csi_rs_density,
        csi_rs_bandwidth_prbs,
        csi_rs_repetition_on,
    )

    var mode = _evaluation_mode(drx_enabled, drx_cycle_us, False)
    var base_period_us = _evaluation_base_period_us(
        mode, rs_periodicity_us, drx_cycle_us
    )
    var samples = 5 if rs_type == NR_REDCAP_RRM_RS_SSB else 10
    if rx_branches == 1:
        samples *= 2
    var coefficient_multiplier = 3 if mode == 1 else 1
    var coefficient_denominator = 2 if mode == 1 else 1
    var scaling = (
        8
        if frequency_range == NR_REDCAP_RRM_FR2
        and rs_type == NR_REDCAP_RRM_RS_SSB
        else 1
    )
    return _evaluation_period_us(
        samples * coefficient_multiplier,
        coefficient_denominator,
        p_numerator,
        p_denominator,
        scaling,
        base_period_us,
        0 if mode == 2 else 50000,
    )


def nr_redcap_rel17_rlm_l1_indication(
    quality_states: Span[Int, ...],
    *,
    profile: Int = NR_REDCAP_RRM_PROFILE_REDCAP_REL17,
) raises -> Int:
    """Aggregate all configured RLM-RS states per clause 8.1B.6."""
    _validate_rel17_profile(profile)
    if len(quality_states) == 0:
        raise Error("RedCap RLM indication requires at least one RLM-RS")
    var all_worse = True
    var any_better = False
    for index in range(len(quality_states)):
        var state = quality_states[index]
        if (
            state != NR_REDCAP_RRM_QUALITY_WORSE_THAN_QOUT
            and state != NR_REDCAP_RRM_QUALITY_BETWEEN_THRESHOLDS
            and state != NR_REDCAP_RRM_QUALITY_BETTER_THAN_QIN
        ):
            raise Error("invalid RedCap RLM quality state")
        if state != NR_REDCAP_RRM_QUALITY_WORSE_THAN_QOUT:
            all_worse = False
        if state == NR_REDCAP_RRM_QUALITY_BETTER_THAN_QIN:
            any_better = True
    if any_better:
        return NR_REDCAP_RRM_L1_IN_SYNC
    if all_worse:
        return NR_REDCAP_RRM_L1_OUT_OF_SYNC
    return NR_REDCAP_RRM_L1_NO_INDICATION


def nr_redcap_rel17_bfd_l1_indication(
    worse_than_qout: Span[UInt8, ...],
    *,
    profile: Int = NR_REDCAP_RRM_PROFILE_REDCAP_REL17,
) raises -> Int:
    """Return a BFI only when every configured BFD-RS is worse than Qout."""
    _validate_rel17_profile(profile)
    if len(worse_than_qout) == 0:
        raise Error("RedCap BFD indication requires at least one BFD-RS")
    var all_worse = True
    for index in range(len(worse_than_qout)):
        var flag = worse_than_qout[index]
        if flag > 1:
            raise Error("RedCap BFD threshold flags must be binary")
        if flag == 0:
            all_worse = False
    if all_worse:
        return NR_REDCAP_RRM_L1_BEAM_FAILURE_INSTANCE
    return NR_REDCAP_RRM_L1_NO_INDICATION


def nr_redcap_rel17_rlm_indication_interval_us(
    rs_types: Span[Int, ...],
    rs_periodicities_us: Span[Int, ...],
    drx_enabled: Bool,
    drx_cycle_us: Int,
    *,
    t310_running: Bool = False,
    hd_fdd: Bool = False,
    hd_fdd_dl_sample_condition_met: Bool = True,
    profile: Int = NR_REDCAP_RRM_PROFILE_REDCAP_REL17,
) raises -> Int:
    """Return ``TIndication_interval,RedCap`` from clause 8.1B.6.

    ``TRLM-RS,M`` is computed as the shortest periodicity across the supplied
    mixed SSB/CSI-RS set.  The HD-FDD boolean records the clause condition that
    every configuration has a sample in a DL occasion; scheduling those
    occasions remains outside this arithmetic API.
    """
    _validate_rel17_profile(profile)
    _validate_drx(drx_enabled, drx_cycle_us)
    if len(rs_types) == 0 or len(rs_types) != len(rs_periodicities_us):
        raise Error("RedCap RLM-RS type/period arrays must be equal and non-empty")
    if hd_fdd and not hd_fdd_dl_sample_condition_met:
        raise Error("HD-FDD RLM interval requires one DL-occasion sample per RS")
    var shortest_us = Int.MAX
    for index in range(len(rs_types)):
        _validate_rlm_rs_periodicity(
            rs_types[index], rs_periodicities_us[index]
        )
        if rs_periodicities_us[index] < shortest_us:
            shortest_us = rs_periodicities_us[index]

    var mode = _evaluation_mode(drx_enabled, drx_cycle_us, t310_running)
    if mode == 0:
        return _max_int(10000, shortest_us)
    if mode == 2:
        return drx_cycle_us
    return _max_int(
        10000,
        _max_int(
            _three_halves_us(drx_cycle_us),
            _three_halves_us(shortest_us),
        ),
    )


def nr_redcap_rel17_bfd_indication_interval_us(
    rs_type: Int,
    shortest_rs_periodicity_us: Int,
    drx_enabled: Bool,
    drx_cycle_us: Int,
    *,
    hd_fdd: Bool = False,
    hd_fdd_dl_sample_condition_met: Bool = True,
    profile: Int = NR_REDCAP_RRM_PROFILE_REDCAP_REL17,
) raises -> Int:
    """Return ``TIndication_interval_BFD_Redcap`` from clause 8.5B.4.

    The clause states SSB and CSI-RS intervals separately, so ``rs_type``
    explicitly identifies the resource family whose shortest period is used.
    """
    _validate_rel17_profile(profile)
    _validate_bfd_rs_periodicity(rs_type, shortest_rs_periodicity_us)
    _validate_drx(drx_enabled, drx_cycle_us)
    if hd_fdd and not hd_fdd_dl_sample_condition_met:
        raise Error("HD-FDD BFD interval requires one DL-occasion sample per RS")
    var mode = _evaluation_mode(drx_enabled, drx_cycle_us, False)
    if mode == 0:
        return _max_int(2000, shortest_rs_periodicity_us)
    if mode == 2:
        return drx_cycle_us
    return _max_int(
        _three_halves_us(drx_cycle_us),
        _three_halves_us(shortest_rs_periodicity_us),
    )


def nr_redcap_rel17_next_l1_indication_time_us(
    candidate_time_us: Int,
    minimum_interval_us: Int,
    *,
    previous_time_us: Int = -1,
    profile: Int = NR_REDCAP_RRM_PROFILE_REDCAP_REL17,
) raises -> Int:
    """Enforce the minimum separation between successive L1 indications.

    ``previous_time_us=-1`` denotes the first indication.  Otherwise the
    result is ``max(candidate, previous + minimum_interval)`` with the sum
    evaluated in ``Int128`` and checked before narrowing.
    """
    _validate_rel17_profile(profile)
    if candidate_time_us < 0 or minimum_interval_us < 1:
        raise Error("invalid RedCap L1 indication time or interval")
    if previous_time_us < -1:
        raise Error("invalid previous RedCap L1 indication time")
    if previous_time_us == -1:
        return candidate_time_us
    var earliest_wide = (
        Int128(previous_time_us) + Int128(minimum_interval_us)
    )
    if earliest_wide > Int128(Int.MAX):
        raise Error("RedCap L1 indication time exceeds Int")
    return _max_int(candidate_time_us, Int(earliest_wide))
