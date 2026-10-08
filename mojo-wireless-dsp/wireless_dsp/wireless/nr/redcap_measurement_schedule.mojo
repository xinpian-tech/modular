"""Rel-17 RedCap idle/inactive serving-cell measurement schedules.

This CPU reference transcribes the bounded integer tables in 3GPP
TS 38.133 V17.22.0 clauses 4.2B.2.1, 4.2B.2.2, 5.1B.2.1, and 5.1B.2.2.
It covers the minimum carrier-layer capability for one- and two-Rx RedCap,
the serving-cell ``Nserv_RedCap`` schedules for RRC_IDLE with and without
``eDRX_IDLE``, and the corresponding RRC_INACTIVE schedule when an effective
``T`` has already been selected according to TS 38.304 V17.11.0 clause 7.1.

All times use exact integer microseconds.  Inputs model already decoded
configuration; the module does not decode RRC/NAS, choose effective ``T``
among CN/RAN paging configurations, acquire RF measurements, implement the
neighbour-cell detection tables, or approximate the clause-4.2B/5.1B
transition requirement.  Ordinary NR, Rel-17 RedCap, and Rel-18 eRedCap are
explicit, non-interchangeable profiles.
"""


comptime NR_REDCAP_MEASUREMENT_PROFILE_ORDINARY_NR = 0
comptime NR_REDCAP_MEASUREMENT_PROFILE_REDCAP_REL17 = 1
comptime NR_REDCAP_MEASUREMENT_PROFILE_EREDCAP_REL18 = 2

comptime NR_REDCAP_MEASUREMENT_FR1 = 1
comptime NR_REDCAP_MEASUREMENT_FR2 = 2

comptime NR_REDCAP_MEASUREMENT_STATE_IDLE = 0
comptime NR_REDCAP_MEASUREMENT_STATE_INACTIVE = 1

comptime NR_REDCAP_MEASUREMENT_COUNT_DRX = 0
comptime NR_REDCAP_MEASUREMENT_COUNT_EDRX = 1
comptime NR_REDCAP_MEASUREMENT_COUNT_EFFECTIVE_T = 2

comptime _US_320_MS = 320000
comptime _US_640_MS = 640000
comptime _US_1280_MS = 1280000
comptime _US_2560_MS = 2560000
comptime _US_5120_MS = 5120000
comptime _US_10240_MS = 10240000
comptime _US_20480_MS = 20480000
comptime _US_10485760_MS = 10485760000


def _validate_rel17_profile(profile: Int) raises:
    if profile != NR_REDCAP_MEASUREMENT_PROFILE_REDCAP_REL17:
        raise Error("measurement scheduling requires Rel-17 RedCap")


def _validate_frequency_range_and_rx(
    frequency_range: Int, rx_branches: Int
) raises:
    if frequency_range != NR_REDCAP_MEASUREMENT_FR1 and (
        frequency_range != NR_REDCAP_MEASUREMENT_FR2
    ):
        raise Error("RedCap measurement frequency range must be FR1 or FR2")
    if rx_branches != 1 and rx_branches != 2:
        raise Error("RedCap measurement Rx branch count must be one or two")
    if frequency_range == NR_REDCAP_MEASUREMENT_FR2 and rx_branches != 2:
        raise Error("Rel-17 RedCap FR2 measurement requires two Rx branches")


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
        raise Error("invalid RedCap SMTC periodicity")


def _is_idle_table_drx_cycle_us(cycle_us: Int) -> Bool:
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


def _is_long_idle_edrx_cycle_us(cycle_us: Int) -> Bool:
    # Clause 4.2B.2.2 groups all decoded values in this inclusive range into
    # the same table branch.  Encoding legality remains with TS 24.008.
    return cycle_us >= _US_20480_MS and cycle_us <= _US_10485760_MS


def _is_inactive_effective_t_us(effective_t_us: Int) -> Bool:
    return (
        effective_t_us == _US_320_MS
        or effective_t_us == _US_640_MS
        or effective_t_us == _US_1280_MS
        or effective_t_us == _US_2560_MS
        or effective_t_us == _US_5120_MS
        or effective_t_us == _US_10240_MS
    )


def _m1(smtc_periodicity_us: Int, cycle_us: Int) -> Int:
    return 2 if smtc_periodicity_us > 20000 and cycle_us <= 640000 else 1


def _fr2_n1(cycle_us: Int) -> Int:
    if cycle_us == _US_320_MS:
        return 8
    if cycle_us == _US_640_MS:
        return 5
    if cycle_us == _US_1280_MS:
        return 4
    return 3


struct _NRRedCapScheduleValues(ImplicitlyCopyable):
    var m1: Int
    var n1: Int
    var nserv: Int
    var count_unit: Int
    var count_cycle_us: Int
    var minimum_filter_spacing_us: Int
    var minimum_ptw_us: Int
    var failure_window_us: Int

    def __init__(
        out self,
        m1: Int,
        n1: Int,
        nserv: Int,
        count_unit: Int,
        count_cycle_us: Int,
        minimum_filter_spacing_us: Int,
        minimum_ptw_us: Int,
    ):
        self.m1 = m1
        self.n1 = n1
        self.nserv = nserv
        self.count_unit = count_unit
        self.count_cycle_us = count_cycle_us
        self.minimum_filter_spacing_us = minimum_filter_spacing_us
        self.minimum_ptw_us = minimum_ptw_us
        self.failure_window_us = nserv * count_cycle_us


def _idle_schedule_values(
    frequency_range: Int,
    smtc_periodicity_us: Int,
    drx_cycle_us: Int,
    edrx_idle_cycle_us: Int,
) raises -> _NRRedCapScheduleValues:
    if edrx_idle_cycle_us == 0:
        if not _is_idle_table_drx_cycle_us(drx_cycle_us):
            raise Error("invalid RedCap idle DRX cycle for table 4.2B.2.2-1")
        var m1 = _m1(smtc_periodicity_us, drx_cycle_us)
        var n1 = (
            1
            if frequency_range == NR_REDCAP_MEASUREMENT_FR1
            else _fr2_n1(drx_cycle_us)
        )
        var nserv = n1 * (4 * m1 if drx_cycle_us <= 640000 else 2)
        return _NRRedCapScheduleValues(
            m1,
            n1,
            nserv,
            NR_REDCAP_MEASUREMENT_COUNT_DRX,
            drx_cycle_us,
            drx_cycle_us // 2,
            0,
        )

    if _is_short_idle_edrx_cycle_us(edrx_idle_cycle_us):
        if drx_cycle_us != 0:
            raise Error("short RedCap idle eDRX table requires DRX to be N/A")
        var n1 = (
            1 if frequency_range == NR_REDCAP_MEASUREMENT_FR1 else 3
        )
        return _NRRedCapScheduleValues(
            1,
            n1,
            n1 * 2,
            NR_REDCAP_MEASUREMENT_COUNT_EDRX,
            edrx_idle_cycle_us,
            edrx_idle_cycle_us // 2,
            0,
        )

    if not _is_long_idle_edrx_cycle_us(edrx_idle_cycle_us):
        raise Error("invalid RedCap idle eDRX cycle for clause 4.2B.2.2")
    if not _is_idle_table_drx_cycle_us(drx_cycle_us):
        raise Error("long RedCap idle eDRX requires a table DRX cycle")

    var m1 = _m1(smtc_periodicity_us, drx_cycle_us)
    var n1 = (
        1
        if frequency_range == NR_REDCAP_MEASUREMENT_FR1
        else _fr2_n1(drx_cycle_us)
    )
    var nserv = n1 * 2
    var minimum_ptw_us: Int
    if frequency_range == NR_REDCAP_MEASUREMENT_FR1:
        if drx_cycle_us <= 640000:
            nserv *= m1
        if drx_cycle_us == _US_320_MS:
            minimum_ptw_us = _US_1280_MS
        elif drx_cycle_us == _US_640_MS:
            minimum_ptw_us = _US_1280_MS * m1
        elif drx_cycle_us == _US_1280_MS:
            minimum_ptw_us = _US_2560_MS
        else:
            minimum_ptw_us = _US_5120_MS
    else:
        if drx_cycle_us == _US_320_MS:
            minimum_ptw_us = _US_5120_MS
        elif drx_cycle_us == _US_640_MS:
            minimum_ptw_us = 6400000
        elif drx_cycle_us == _US_1280_MS:
            minimum_ptw_us = _US_10240_MS
        else:
            minimum_ptw_us = 15360000

    return _NRRedCapScheduleValues(
        m1,
        n1,
        nserv,
        NR_REDCAP_MEASUREMENT_COUNT_DRX,
        drx_cycle_us,
        drx_cycle_us // 2,
        minimum_ptw_us,
    )


def _inactive_schedule_values(
    frequency_range: Int,
    smtc_periodicity_us: Int,
    edrx_idle_cycle_us: Int,
    effective_t_us: Int,
) raises -> _NRRedCapScheduleValues:
    # Table 5.1B.2.2-1/-2 states this inclusive applicability range.  The
    # separate TS 24.008 encoded-value check remains outside this table API.
    if edrx_idle_cycle_us < _US_2560_MS or (
        edrx_idle_cycle_us > _US_10485760_MS
    ):
        raise Error("inactive RedCap schedule requires configured eDRX_IDLE")
    if not _is_inactive_effective_t_us(effective_t_us):
        raise Error("invalid effective T for RedCap inactive measurement")

    var m1 = _m1(smtc_periodicity_us, effective_t_us)
    var n1 = (
        1
        if frequency_range == NR_REDCAP_MEASUREMENT_FR1
        else _fr2_n1(effective_t_us)
    )
    var nserv: Int
    if effective_t_us <= _US_640_MS:
        nserv = 4 * (
            m1
            if frequency_range == NR_REDCAP_MEASUREMENT_FR1
            else n1
        )
    else:
        nserv = 2 * n1
    return _NRRedCapScheduleValues(
        m1,
        n1,
        nserv,
        NR_REDCAP_MEASUREMENT_COUNT_EFFECTIVE_T,
        effective_t_us,
        effective_t_us // 2,
        0,
    )


def _derive_schedule_values(
    rrc_state: Int,
    frequency_range: Int,
    rx_branches: Int,
    smtc_periodicity_us: Int,
    drx_cycle_us: Int,
    edrx_idle_cycle_us: Int,
    effective_t_us: Int,
    profile: Int,
) raises -> _NRRedCapScheduleValues:
    _validate_rel17_profile(profile)
    _validate_frequency_range_and_rx(frequency_range, rx_branches)
    _validate_smtc_periodicity_us(smtc_periodicity_us)
    if rrc_state == NR_REDCAP_MEASUREMENT_STATE_IDLE:
        if effective_t_us != 0:
            raise Error("idle RedCap schedule cannot carry inactive T")
        return _idle_schedule_values(
            frequency_range,
            smtc_periodicity_us,
            drx_cycle_us,
            edrx_idle_cycle_us,
        )
    if rrc_state == NR_REDCAP_MEASUREMENT_STATE_INACTIVE:
        if drx_cycle_us != 0:
            raise Error("inactive RedCap table consumes effective T, not DRX")
        return _inactive_schedule_values(
            frequency_range,
            smtc_periodicity_us,
            edrx_idle_cycle_us,
            effective_t_us,
        )
    raise Error("RedCap measurement state must be RRC_IDLE or RRC_INACTIVE")


struct NRRedCapMeasurementLayerCapability(ImplicitlyCopyable):
    """Minimum carrier-layer monitoring capability from clause 4.2B.2.1."""

    var profile: Int
    var frequency_range: Int
    var rx_branches: Int
    var minimum_intra_frequency_carriers: Int
    var minimum_nr_inter_frequency_carriers: Int
    var minimum_fdd_eutra_inter_rat_carriers: Int
    var minimum_tdd_eutra_inter_rat_carriers: Int
    var minimum_total_frequency_layers: Int

    def __init__(
        out self,
        frequency_range: Int,
        rx_branches: Int,
        *,
        profile: Int = NR_REDCAP_MEASUREMENT_PROFILE_REDCAP_REL17,
    ) raises:
        self.profile = profile
        self.frequency_range = frequency_range
        self.rx_branches = rx_branches
        self.minimum_intra_frequency_carriers = 1
        var per_family = 6 if rx_branches == 1 else 7
        self.minimum_nr_inter_frequency_carriers = per_family
        self.minimum_fdd_eutra_inter_rat_carriers = per_family
        self.minimum_tdd_eutra_inter_rat_carriers = per_family
        self.minimum_total_frequency_layers = 11 if rx_branches == 1 else 14
        self.validate()

    def validate(self) raises:
        """Revalidate profile and every literal capability field."""
        _validate_rel17_profile(self.profile)
        _validate_frequency_range_and_rx(
            self.frequency_range, self.rx_branches
        )
        var per_family = 6 if self.rx_branches == 1 else 7
        var total_layers = 11 if self.rx_branches == 1 else 14
        if self.minimum_intra_frequency_carriers != 1 or (
            self.minimum_nr_inter_frequency_carriers != per_family
        ) or self.minimum_fdd_eutra_inter_rat_carriers != per_family or (
            self.minimum_tdd_eutra_inter_rat_carriers != per_family
        ) or self.minimum_total_frequency_layers != total_layers:
            raise Error("mutated RedCap measurement capability table")


struct NRRedCapServingMeasurementSchedule(ImplicitlyCopyable):
    """Exact serving-cell failure schedule for clauses 4.2B.2.2/5.1B.2.2.

    ``nserv`` consecutive failed S-criterion evaluations, counted in
    ``count_cycle_us`` units, require all indicated neighbour measurements.
    For long idle eDRX those DRX cycles must occur within one PTW, whose table
    lower bound is ``minimum_ptw_us``.  The product ``failure_window_us`` is
    exact arithmetic evidence, not a substitute for checking PTW membership.
    """

    var profile: Int
    var rrc_state: Int
    var frequency_range: Int
    var rx_branches: Int
    var smtc_periodicity_us: Int
    var drx_cycle_us: Int
    var edrx_idle_cycle_us: Int
    var effective_t_us: Int
    var m1: Int
    var n1: Int
    var nserv: Int
    var count_unit: Int
    var count_cycle_us: Int
    var minimum_filter_spacing_us: Int
    var minimum_ptw_us: Int
    var failure_window_us: Int

    def __init__(
        out self,
        rrc_state: Int,
        frequency_range: Int,
        rx_branches: Int,
        smtc_periodicity_us: Int,
        drx_cycle_us: Int,
        edrx_idle_cycle_us: Int,
        effective_t_us: Int,
        *,
        profile: Int = NR_REDCAP_MEASUREMENT_PROFILE_REDCAP_REL17,
    ) raises:
        self.profile = profile
        self.rrc_state = rrc_state
        self.frequency_range = frequency_range
        self.rx_branches = rx_branches
        self.smtc_periodicity_us = smtc_periodicity_us
        self.drx_cycle_us = drx_cycle_us
        self.edrx_idle_cycle_us = edrx_idle_cycle_us
        self.effective_t_us = effective_t_us
        var expected = _derive_schedule_values(
            rrc_state,
            frequency_range,
            rx_branches,
            smtc_periodicity_us,
            drx_cycle_us,
            edrx_idle_cycle_us,
            effective_t_us,
            profile,
        )
        self.m1 = expected.m1
        self.n1 = expected.n1
        self.nserv = expected.nserv
        self.count_unit = expected.count_unit
        self.count_cycle_us = expected.count_cycle_us
        self.minimum_filter_spacing_us = expected.minimum_filter_spacing_us
        self.minimum_ptw_us = expected.minimum_ptw_us
        self.failure_window_us = expected.failure_window_us
        self.validate()

    def validate(self) raises:
        """Recompute the normative table row and reject mutated state."""
        var expected = _derive_schedule_values(
            self.rrc_state,
            self.frequency_range,
            self.rx_branches,
            self.smtc_periodicity_us,
            self.drx_cycle_us,
            self.edrx_idle_cycle_us,
            self.effective_t_us,
            self.profile,
        )
        if self.m1 != expected.m1 or self.n1 != expected.n1 or (
            self.nserv != expected.nserv
        ) or self.count_unit != expected.count_unit or (
            self.count_cycle_us != expected.count_cycle_us
        ) or self.minimum_filter_spacing_us != (
            expected.minimum_filter_spacing_us
        ) or self.minimum_ptw_us != expected.minimum_ptw_us or (
            self.failure_window_us != expected.failure_window_us
        ):
            raise Error("mutated RedCap serving-cell measurement schedule")


def nr_redcap_rel17_measurement_capability(
    frequency_range: Int,
    rx_branches: Int,
    *,
    profile: Int = NR_REDCAP_MEASUREMENT_PROFILE_REDCAP_REL17,
) raises -> NRRedCapMeasurementLayerCapability:
    """Return the clause-4.2B.2.1 one-/two-Rx monitoring minima."""
    return NRRedCapMeasurementLayerCapability(
        frequency_range, rx_branches, profile=profile
    )


def nr_redcap_rel17_idle_serving_measurement_schedule(
    frequency_range: Int,
    rx_branches: Int,
    smtc_periodicity_us: Int,
    drx_cycle_us: Int,
    *,
    edrx_idle_cycle_us: Int = 0,
    profile: Int = NR_REDCAP_MEASUREMENT_PROFILE_REDCAP_REL17,
) raises -> NRRedCapServingMeasurementSchedule:
    """Return the exact RRC_IDLE clause-4.2B.2.2 ``Nserv_RedCap`` row.

    Pass ``edrx_idle_cycle_us=0`` for Table 4.2B.2.2-1.  For the short
    2.56/5.12/10.24-second eDRX rows, ``drx_cycle_us`` must be zero because
    the table marks it N/A.  Long eDRX rows require one of the four explicit
    0.32/0.64/1.28/2.56-second DRX values used within the PTW.
    """
    return NRRedCapServingMeasurementSchedule(
        NR_REDCAP_MEASUREMENT_STATE_IDLE,
        frequency_range,
        rx_branches,
        smtc_periodicity_us,
        drx_cycle_us,
        edrx_idle_cycle_us,
        0,
        profile=profile,
    )


def nr_redcap_rel17_inactive_serving_measurement_schedule(
    frequency_range: Int,
    rx_branches: Int,
    smtc_periodicity_us: Int,
    edrx_idle_cycle_us: Int,
    effective_t_us: Int,
    *,
    profile: Int = NR_REDCAP_MEASUREMENT_PROFILE_REDCAP_REL17,
) raises -> NRRedCapServingMeasurementSchedule:
    """Return the exact RRC_INACTIVE clause-5.1B.2.2 ``Nserv_RedCap`` row.

    ``effective_t_us`` must already be selected under TS 38.304 clause 7.1;
    accepting it explicitly avoids inventing policy across decoded CN and RAN
    paging configurations that are outside this bounded table lookup.
    """
    return NRRedCapServingMeasurementSchedule(
        NR_REDCAP_MEASUREMENT_STATE_INACTIVE,
        frequency_range,
        rx_branches,
        smtc_periodicity_us,
        0,
        edrx_idle_cycle_us,
        effective_t_us,
        profile=profile,
    )


def nr_redcap_rel17_all_neighbour_measurements_required(
    schedule: NRRedCapServingMeasurementSchedule,
    consecutive_s_failures: Int,
) raises -> Bool:
    """Return whether the exact ``Nserv_RedCap`` failure threshold is met."""
    schedule.validate()
    if consecutive_s_failures < 0:
        raise Error("consecutive RedCap serving-cell failures must be non-negative")
    return consecutive_s_failures >= schedule.nserv
