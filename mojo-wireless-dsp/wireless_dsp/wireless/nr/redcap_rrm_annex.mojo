"""Rel-17 RedCap RRM Annex A/B static configuration oracles.

This CPU-only module transcribes the finite published configuration tables in
3GPP TS 38.133 V17.22.0 (2026-06), clauses A.3.9A, A.3.10B, A.3.11A,
A.3.35, B.1.4-B.1.5, and B.2.15-B.2.16.  The official source archive is
``38133-hm0.zip`` (SHA-256
``bfe1a68a6e67db48d96540e2567359ffdcc1e78759a62b77448bf7f4294e678d``).

All powers use signed tenths of a decibel, avoiding floating-point ambiguity.
FR2 rows containing the published symbolic ``+Y`` or ``+Z`` terms expose the
literal base and adjustment kind separately.  Callers may resolve those rows
only by supplying the corresponding external TS 38.101-2 adjustment; this
module does not invent values marked FFS by TS 38.133.

The V17.22.0 caption for Table B.2.16-2 says FR1/2Rx, while its actual columns
are AoA, FR2 band, and FR2 power class.  It is therefore represented under an
explicit ``AS_PUBLISHED`` source-table tag.  No FR1 band-group row is inferred
from that inconsistent table.  RF generation, fading/AWGN apparatus,
conformance verdicts, and the thousands of test-case-specific Annex A.16-A.18
parameters remain outside this bounded static lookup module.
"""


comptime NR_REDCAP_ANNEX_PROFILE_ORDINARY_NR = 0
comptime NR_REDCAP_ANNEX_PROFILE_REDCAP_REL17 = 1
comptime NR_REDCAP_ANNEX_PROFILE_EREDCAP_REL18 = 2

comptime NR_REDCAP_ANNEX_FR1 = 1
comptime NR_REDCAP_ANNEX_FR2 = 2

comptime NR_REDCAP_ANNEX_BWP_DOWNLINK = 0
comptime NR_REDCAP_ANNEX_BWP_UPLINK = 1
comptime NR_REDCAP_ANNEX_BWP_START_RBA = 1
comptime NR_REDCAP_ANNEX_BWP_START_RBB = 2
comptime NR_REDCAP_ANNEX_BWP_START_RBC = 3

comptime NR_REDCAP_ANNEX_SSB_LOCATION_CELL_RASTER = 0
comptime NR_REDCAP_ANNEX_SSB_LOCATION_ASSOCIATED_BWP_NON_RASTER = 1

comptime NR_REDCAP_ANNEX_SOURCE_NR = 0
comptime NR_REDCAP_ANNEX_SOURCE_EUTRA = 1
comptime NR_REDCAP_ANNEX_TEST_CLAUSE_A16 = 16
comptime NR_REDCAP_ANNEX_TEST_CLAUSE_A17 = 17
comptime NR_REDCAP_ANNEX_TEST_CLAUSE_A18 = 18

comptime NR_REDCAP_ANNEX_CONDITION_CELL_RESELECTION = 0
comptime NR_REDCAP_ANNEX_CONDITION_CONNECTED_MEASUREMENT = 1
comptime NR_REDCAP_ANNEX_RELATION_INTRA_FREQUENCY = 0
comptime NR_REDCAP_ANNEX_RELATION_INTER_FREQUENCY = 1

comptime NR_REDCAP_ANNEX_FR1_GROUP_A = 0
comptime NR_REDCAP_ANNEX_FR1_GROUP_B = 1
comptime NR_REDCAP_ANNEX_FR1_GROUP_C = 2
comptime NR_REDCAP_ANNEX_FR1_GROUP_D = 3
comptime NR_REDCAP_ANNEX_FR1_GROUP_E = 4
comptime NR_REDCAP_ANNEX_FR1_GROUP_F = 5
comptime NR_REDCAP_ANNEX_FR1_GROUP_G = 6
comptime NR_REDCAP_ANNEX_FR1_GROUP_H = 7

comptime NR_REDCAP_ANNEX_TABLE_B1_4 = 104
comptime NR_REDCAP_ANNEX_TABLE_B1_5 = 105
comptime NR_REDCAP_ANNEX_TABLE_B2_15 = 215
comptime NR_REDCAP_ANNEX_TABLE_B2_16 = 216
comptime NR_REDCAP_ANNEX_TABLE_B1_4_3 = 1043
comptime NR_REDCAP_ANNEX_TABLE_B2_15_3 = 2153
comptime NR_REDCAP_ANNEX_TABLE_B2_16_2_AS_PUBLISHED = 2162
comptime NR_REDCAP_ANNEX_TABLE_B2_16_3 = 2163

comptime NR_REDCAP_ANNEX_AOA_RX_BEAM_PEAK = 0
comptime NR_REDCAP_ANNEX_AOA_SPHERICAL_COVERAGE = 1
comptime NR_REDCAP_ANNEX_ADJUSTMENT_NONE = 0
comptime NR_REDCAP_ANNEX_ADJUSTMENT_Y = 1
comptime NR_REDCAP_ANNEX_ADJUSTMENT_Z = 2
comptime NR_REDCAP_ANNEX_MULTIBAND_MBP = 1
comptime NR_REDCAP_ANNEX_MULTIBAND_MBS = 2


def _validate_rel17_profile(profile: Int) raises:
    if profile != NR_REDCAP_ANNEX_PROFILE_REDCAP_REL17:
        raise Error("TS 38.133 Annex lookup requires Rel-17 RedCap")


def _validate_frequency_range(frequency_range: Int) raises:
    if frequency_range != NR_REDCAP_ANNEX_FR1 and (
        frequency_range != NR_REDCAP_ANNEX_FR2
    ):
        raise Error("RedCap Annex frequency range must be FR1 or FR2")


def _validate_rx_branches(frequency_range: Int, rx_branches: Int) raises:
    if rx_branches != 1 and rx_branches != 2:
        raise Error("RedCap Annex Rx branch count must be one or two")
    if frequency_range == NR_REDCAP_ANNEX_FR2 and rx_branches != 2:
        raise Error("Rel-17 RedCap FR2 Annex tests require two Rx branches")


struct _BWPValues(ImplicitlyCopyable):
    var bandwidth_prbs: Int
    var starting_prb_rule: Int

    def __init__(out self, bandwidth_prbs: Int, starting_prb_rule: Int):
        self.bandwidth_prbs = bandwidth_prbs
        self.starting_prb_rule = starting_prb_rule


def _bwp_values(
    direction: Int, pattern: Int, ssb_scs_khz: Int, profile: Int
) raises -> _BWPValues:
    _validate_rel17_profile(profile)
    if direction != NR_REDCAP_ANNEX_BWP_DOWNLINK and (
        direction != NR_REDCAP_ANNEX_BWP_UPLINK
    ):
        raise Error("RedCap Annex BWP direction must be downlink or uplink")
    if pattern < 1 or pattern > 3:
        raise Error("RedCap Annex dedicated BWP pattern must be 1 through 3")
    var bandwidth_prbs: Int
    if ssb_scs_khz == 15 or ssb_scs_khz == 30:
        bandwidth_prbs = 25
    elif ssb_scs_khz == 120:
        bandwidth_prbs = 32
    elif ssb_scs_khz == 240:
        bandwidth_prbs = 16
    else:
        raise Error("RedCap Annex BWP SSB SCS must be 15/30/120/240 kHz")
    return _BWPValues(bandwidth_prbs, pattern)


struct NRRedCapAnnexBWPConfiguration(ImplicitlyCopyable):
    """One literal A.3.9A downlink or uplink dedicated-BWP row."""

    var profile: Int
    var direction: Int
    var pattern: Int
    var ssb_scs_khz: Int
    var bandwidth_prbs: Int
    var starting_prb_rule: Int

    def __init__(
        out self,
        direction: Int,
        pattern: Int,
        ssb_scs_khz: Int,
        *,
        profile: Int = NR_REDCAP_ANNEX_PROFILE_REDCAP_REL17,
    ) raises:
        self.profile = profile
        self.direction = direction
        self.pattern = pattern
        self.ssb_scs_khz = ssb_scs_khz
        var expected = _bwp_values(direction, pattern, ssb_scs_khz, profile)
        self.bandwidth_prbs = expected.bandwidth_prbs
        self.starting_prb_rule = expected.starting_prb_rule
        self.validate()

    def validate(self) raises:
        """Re-read the published row and reject mutated public state."""
        var expected = _bwp_values(
            self.direction, self.pattern, self.ssb_scs_khz, self.profile
        )
        if self.bandwidth_prbs != expected.bandwidth_prbs or (
            self.starting_prb_rule != expected.starting_prb_rule
        ):
            raise Error("mutated RedCap Annex BWP configuration")


def nr_redcap_rel17_annex_bwp_configuration(
    direction: Int,
    pattern: Int,
    ssb_scs_khz: Int,
    *,
    profile: Int = NR_REDCAP_ANNEX_PROFILE_REDCAP_REL17,
) raises -> NRRedCapAnnexBWPConfiguration:
    """Return one exact A.3.9A BWP pattern/SCS row."""
    return NRRedCapAnnexBWPConfiguration(
        direction, pattern, ssb_scs_khz, profile=profile
    )


struct _SSBValues(ImplicitlyCopyable):
    var channel_bandwidth_mhz: Int
    var ssb_scs_khz: Int
    var periodicity_ms: Int
    var number_of_ssbs: Int
    var first_symbol_start: Int
    var second_symbol_start: Int
    var sfn_modulus: Int
    var sfn_remainder: Int
    var location_rule: Int

    def __init__(
        out self,
        channel_bandwidth_mhz: Int,
        ssb_scs_khz: Int,
        periodicity_ms: Int,
        number_of_ssbs: Int,
        first_symbol_start: Int,
        second_symbol_start: Int,
        sfn_modulus: Int,
        sfn_remainder: Int,
        location_rule: Int,
    ):
        self.channel_bandwidth_mhz = channel_bandwidth_mhz
        self.ssb_scs_khz = ssb_scs_khz
        self.periodicity_ms = periodicity_ms
        self.number_of_ssbs = number_of_ssbs
        self.first_symbol_start = first_symbol_start
        self.second_symbol_start = second_symbol_start
        self.sfn_modulus = sfn_modulus
        self.sfn_remainder = sfn_remainder
        self.location_rule = location_rule


def _ssb_values(
    frequency_range: Int,
    pattern: Int,
    use_case_b_symbols: Bool,
    profile: Int,
) raises -> _SSBValues:
    _validate_rel17_profile(profile)
    _validate_frequency_range(frequency_range)
    if frequency_range == NR_REDCAP_ANNEX_FR1:
        if pattern < 1 or pattern > 7:
            raise Error("RedCap Annex FR1 SSB pattern must be 1 through 7")
        var scs_khz = 15 if pattern == 4 or pattern == 6 else 30
        if scs_khz == 15 and use_case_b_symbols:
            raise Error("Case-B symbol selection only applies to 30-kHz FR1 SSB")
        var channel_bandwidth_mhz = 10 if scs_khz == 15 else 20
        var periodicity_ms = 80 if pattern == 6 or pattern == 7 else 20
        var number_of_ssbs = 2 if pattern == 2 else 1
        var first_symbol_start = 4 if use_case_b_symbols else 2
        if scs_khz == 15:
            first_symbol_start = 2
        var second_symbol_start = 8 if pattern == 2 else -1
        var sfn_remainder = 1 if pattern == 3 else 0
        var location_rule = (
            NR_REDCAP_ANNEX_SSB_LOCATION_ASSOCIATED_BWP_NON_RASTER
            if pattern == 6 or pattern == 7
            else NR_REDCAP_ANNEX_SSB_LOCATION_CELL_RASTER
        )
        return _SSBValues(
            channel_bandwidth_mhz,
            scs_khz,
            periodicity_ms,
            number_of_ssbs,
            first_symbol_start,
            second_symbol_start,
            periodicity_ms // 10,
            sfn_remainder,
            location_rule,
        )

    if pattern < 1 or pattern > 5:
        raise Error("RedCap Annex FR2 SSB pattern must be 1 through 5")
    if use_case_b_symbols:
        raise Error("Case-B symbol selection does not apply to FR2 Annex rows")
    var scs_khz = 120 if pattern <= 3 else 240
    var periodicity_ms: Int
    if pattern == 1:
        periodicity_ms = 20
    elif pattern == 2 or pattern == 4:
        periodicity_ms = 40
    else:
        periodicity_ms = 80
    var location_rule = (
        NR_REDCAP_ANNEX_SSB_LOCATION_ASSOCIATED_BWP_NON_RASTER
        if pattern == 3 or pattern == 5
        else NR_REDCAP_ANNEX_SSB_LOCATION_CELL_RASTER
    )
    return _SSBValues(
        100,
        scs_khz,
        periodicity_ms,
        1,
        4 if scs_khz == 120 else 8,
        -1,
        periodicity_ms // 10,
        0,
        location_rule,
    )


struct NRRedCapAnnexSSBConfiguration(ImplicitlyCopyable):
    """One A.3.10B FR1/FR2 SSB configuration row."""

    var profile: Int
    var frequency_range: Int
    var pattern: Int
    var use_case_b_symbols: Bool
    var channel_bandwidth_mhz: Int
    var ssb_scs_khz: Int
    var periodicity_ms: Int
    var number_of_ssbs: Int
    var first_symbol_start: Int
    var second_symbol_start: Int
    var slot_number: Int
    var sfn_modulus: Int
    var sfn_remainder: Int
    var ssb_prbs: Int
    var location_rule: Int

    def __init__(
        out self,
        frequency_range: Int,
        pattern: Int,
        use_case_b_symbols: Bool = False,
        *,
        profile: Int = NR_REDCAP_ANNEX_PROFILE_REDCAP_REL17,
    ) raises:
        self.profile = profile
        self.frequency_range = frequency_range
        self.pattern = pattern
        self.use_case_b_symbols = use_case_b_symbols
        var expected = _ssb_values(
            frequency_range, pattern, use_case_b_symbols, profile
        )
        self.channel_bandwidth_mhz = expected.channel_bandwidth_mhz
        self.ssb_scs_khz = expected.ssb_scs_khz
        self.periodicity_ms = expected.periodicity_ms
        self.number_of_ssbs = expected.number_of_ssbs
        self.first_symbol_start = expected.first_symbol_start
        self.second_symbol_start = expected.second_symbol_start
        self.slot_number = 0
        self.sfn_modulus = expected.sfn_modulus
        self.sfn_remainder = expected.sfn_remainder
        self.ssb_prbs = 20
        self.location_rule = expected.location_rule
        self.validate()

    def validate(self) raises:
        """Re-read the published pattern and reject mutated public state."""
        var expected = _ssb_values(
            self.frequency_range,
            self.pattern,
            self.use_case_b_symbols,
            self.profile,
        )
        if self.channel_bandwidth_mhz != expected.channel_bandwidth_mhz or (
            self.ssb_scs_khz != expected.ssb_scs_khz
        ) or self.periodicity_ms != expected.periodicity_ms or (
            self.number_of_ssbs != expected.number_of_ssbs
        ) or self.first_symbol_start != expected.first_symbol_start or (
            self.second_symbol_start != expected.second_symbol_start
        ) or self.slot_number != 0 or (
            self.sfn_modulus != expected.sfn_modulus
        ) or self.sfn_remainder != expected.sfn_remainder or (
            self.ssb_prbs != 20
        ) or self.location_rule != expected.location_rule:
            raise Error("mutated RedCap Annex SSB configuration")


def nr_redcap_rel17_annex_ssb_configuration(
    frequency_range: Int,
    pattern: Int,
    use_case_b_symbols: Bool = False,
    *,
    profile: Int = NR_REDCAP_ANNEX_PROFILE_REDCAP_REL17,
) raises -> NRRedCapAnnexSSBConfiguration:
    """Return one exact A.3.10B SSB pattern."""
    return NRRedCapAnnexSSBConfiguration(
        frequency_range,
        pattern,
        use_case_b_symbols,
        profile=profile,
    )


struct _SMTCValues(ImplicitlyCopyable):
    var periodicity_ms: Int
    var offset_ms: Int
    var duration_ms: Int

    def __init__(
        out self, periodicity_ms: Int, offset_ms: Int, duration_ms: Int
    ):
        self.periodicity_ms = periodicity_ms
        self.offset_ms = offset_ms
        self.duration_ms = duration_ms


def _smtc_values(pattern: Int, profile: Int) raises -> _SMTCValues:
    _validate_rel17_profile(profile)
    if pattern == 1:
        return _SMTCValues(40, 0, 1)
    if pattern == 2:
        return _SMTCValues(80, 0, 1)
    if pattern == 3:
        return _SMTCValues(40, 20, 1)
    if pattern == 4:
        return _SMTCValues(80, 0, 5)
    raise Error("RedCap Annex SMTC pattern must be 1 through 4")


struct NRRedCapAnnexSMTCConfiguration(ImplicitlyCopyable):
    """One exact A.3.11A SMTC pattern in integer milliseconds."""

    var profile: Int
    var pattern: Int
    var periodicity_ms: Int
    var offset_ms: Int
    var duration_ms: Int

    def __init__(
        out self,
        pattern: Int,
        *,
        profile: Int = NR_REDCAP_ANNEX_PROFILE_REDCAP_REL17,
    ) raises:
        self.profile = profile
        self.pattern = pattern
        var expected = _smtc_values(pattern, profile)
        self.periodicity_ms = expected.periodicity_ms
        self.offset_ms = expected.offset_ms
        self.duration_ms = expected.duration_ms
        self.validate()

    def validate(self) raises:
        """Re-read the published pattern and reject mutated public state."""
        var expected = _smtc_values(self.pattern, self.profile)
        if self.periodicity_ms != expected.periodicity_ms or (
            self.offset_ms != expected.offset_ms
        ) or self.duration_ms != expected.duration_ms:
            raise Error("mutated RedCap Annex SMTC configuration")


def nr_redcap_rel17_annex_smtc_configuration(
    pattern: Int,
    *,
    profile: Int = NR_REDCAP_ANNEX_PROFILE_REDCAP_REL17,
) raises -> NRRedCapAnnexSMTCConfiguration:
    """Return one exact A.3.11A SMTC pattern."""
    return NRRedCapAnnexSMTCConfiguration(pattern, profile=profile)


def _test_annex_clause(
    source_rat: Int,
    target_frequency_range: Int,
    rx_branches: Int,
    profile: Int,
) raises -> Int:
    _validate_rel17_profile(profile)
    _validate_frequency_range(target_frequency_range)
    _validate_rx_branches(target_frequency_range, rx_branches)
    if source_rat == NR_REDCAP_ANNEX_SOURCE_NR:
        return (
            NR_REDCAP_ANNEX_TEST_CLAUSE_A16
            if target_frequency_range == NR_REDCAP_ANNEX_FR1
            else NR_REDCAP_ANNEX_TEST_CLAUSE_A17
        )
    if source_rat == NR_REDCAP_ANNEX_SOURCE_EUTRA:
        return NR_REDCAP_ANNEX_TEST_CLAUSE_A18
    raise Error("RedCap Annex source RAT must be NR or E-UTRA")


struct NRRedCapAnnexTestScope(ImplicitlyCopyable):
    """A.3.35 selection of A.16, A.17, or A.18 test families."""

    var profile: Int
    var source_rat: Int
    var target_frequency_range: Int
    var rx_branches: Int
    var annex_clause: Int

    def __init__(
        out self,
        source_rat: Int,
        target_frequency_range: Int,
        rx_branches: Int,
        *,
        profile: Int = NR_REDCAP_ANNEX_PROFILE_REDCAP_REL17,
    ) raises:
        self.profile = profile
        self.source_rat = source_rat
        self.target_frequency_range = target_frequency_range
        self.rx_branches = rx_branches
        self.annex_clause = _test_annex_clause(
            source_rat, target_frequency_range, rx_branches, profile
        )
        self.validate()

    def validate(self) raises:
        """Re-apply A.3.35 and reject mutated public state."""
        var expected = _test_annex_clause(
            self.source_rat,
            self.target_frequency_range,
            self.rx_branches,
            self.profile,
        )
        if self.annex_clause != expected:
            raise Error("mutated RedCap Annex test scope")


def nr_redcap_rel17_annex_test_scope(
    source_rat: Int,
    target_frequency_range: Int,
    rx_branches: Int,
    *,
    profile: Int = NR_REDCAP_ANNEX_PROFILE_REDCAP_REL17,
) raises -> NRRedCapAnnexTestScope:
    """Return A.3.35's applicable A.16/A.17/A.18 family selector."""
    return NRRedCapAnnexTestScope(
        source_rat,
        target_frequency_range,
        rx_branches,
        profile=profile,
    )


struct _FR1ConditionValues(ImplicitlyCopyable):
    var source_table: Int
    var minimum_ssb_rp_tenth_dbm: Int
    var minimum_ssb_es_iot_tenth_db: Int

    def __init__(
        out self,
        source_table: Int,
        minimum_ssb_rp_tenth_dbm: Int,
        minimum_ssb_es_iot_tenth_db: Int,
    ):
        self.source_table = source_table
        self.minimum_ssb_rp_tenth_dbm = minimum_ssb_rp_tenth_dbm
        self.minimum_ssb_es_iot_tenth_db = minimum_ssb_es_iot_tenth_db


def _fr1_group_offset_tenth_db(group: Int) raises -> Int:
    if group < NR_REDCAP_ANNEX_FR1_GROUP_A or (
        group > NR_REDCAP_ANNEX_FR1_GROUP_H
    ):
        raise Error("RedCap Annex FR1 operating-band group must be A through H")
    return group * 5


def _fr1_condition_values(
    condition_family: Int,
    frequency_relation: Int,
    rx_branches: Int,
    band_group: Int,
    ssb_scs_khz: Int,
    profile: Int,
) raises -> _FR1ConditionValues:
    _validate_rel17_profile(profile)
    _validate_rx_branches(NR_REDCAP_ANNEX_FR1, rx_branches)
    if frequency_relation != NR_REDCAP_ANNEX_RELATION_INTRA_FREQUENCY and (
        frequency_relation != NR_REDCAP_ANNEX_RELATION_INTER_FREQUENCY
    ):
        raise Error("RedCap Annex frequency relation must be intra or inter")
    if ssb_scs_khz != 15 and ssb_scs_khz != 30:
        raise Error("RedCap Annex FR1 condition SSB SCS must be 15 or 30 kHz")
    var scs_offset = 30 if ssb_scs_khz == 30 else 0
    var group_offset = _fr1_group_offset_tenth_db(band_group)
    if condition_family == NR_REDCAP_ANNEX_CONDITION_CELL_RESELECTION:
        var source_table = (
            NR_REDCAP_ANNEX_TABLE_B1_4
            if frequency_relation == NR_REDCAP_ANNEX_RELATION_INTRA_FREQUENCY
            else NR_REDCAP_ANNEX_TABLE_B1_5
        )
        return _FR1ConditionValues(
            source_table, -1240 + group_offset + scs_offset, -40
        )
    if condition_family != NR_REDCAP_ANNEX_CONDITION_CONNECTED_MEASUREMENT:
        raise Error("invalid RedCap Annex condition family")
    if frequency_relation == NR_REDCAP_ANNEX_RELATION_INTRA_FREQUENCY:
        return _FR1ConditionValues(
            NR_REDCAP_ANNEX_TABLE_B2_15,
            -1270 + group_offset + scs_offset,
            -60,
        )
    if rx_branches != 1:
        raise Error(
            "published B.2.16-2 has FR2 dimensions, not FR1 2Rx group rows"
        )
    var base_tenth_dbm: Int
    if band_group == NR_REDCAP_ANNEX_FR1_GROUP_D:
        # Table B.2.16-1 uniquely publishes -124.5/-120.5 dBm for
        # 15/30 kHz, a 4-dB rather than 3-dB separation.
        base_tenth_dbm = -1205 if ssb_scs_khz == 30 else -1245
        scs_offset = 0
    else:
        base_tenth_dbm = -1250 + group_offset
    return _FR1ConditionValues(
        NR_REDCAP_ANNEX_TABLE_B2_16,
        base_tenth_dbm + scs_offset,
        -40,
    )


struct NRRedCapAnnexFR1Condition(ImplicitlyCopyable):
    """Exact FR1 Annex-B SSB_RP/Es-Iot condition in tenths of dB."""

    var profile: Int
    var condition_family: Int
    var frequency_relation: Int
    var rx_branches: Int
    var band_group: Int
    var ssb_scs_khz: Int
    var source_table: Int
    var minimum_ssb_rp_tenth_dbm: Int
    var minimum_ssb_es_iot_tenth_db: Int

    def __init__(
        out self,
        condition_family: Int,
        frequency_relation: Int,
        rx_branches: Int,
        band_group: Int,
        ssb_scs_khz: Int,
        *,
        profile: Int = NR_REDCAP_ANNEX_PROFILE_REDCAP_REL17,
    ) raises:
        self.profile = profile
        self.condition_family = condition_family
        self.frequency_relation = frequency_relation
        self.rx_branches = rx_branches
        self.band_group = band_group
        self.ssb_scs_khz = ssb_scs_khz
        var expected = _fr1_condition_values(
            condition_family,
            frequency_relation,
            rx_branches,
            band_group,
            ssb_scs_khz,
            profile,
        )
        self.source_table = expected.source_table
        self.minimum_ssb_rp_tenth_dbm = expected.minimum_ssb_rp_tenth_dbm
        self.minimum_ssb_es_iot_tenth_db = (
            expected.minimum_ssb_es_iot_tenth_db
        )
        self.validate()

    def validate(self) raises:
        """Re-read the Annex-B row and reject mutated public state."""
        var expected = _fr1_condition_values(
            self.condition_family,
            self.frequency_relation,
            self.rx_branches,
            self.band_group,
            self.ssb_scs_khz,
            self.profile,
        )
        if self.source_table != expected.source_table or (
            self.minimum_ssb_rp_tenth_dbm
            != expected.minimum_ssb_rp_tenth_dbm
        ) or self.minimum_ssb_es_iot_tenth_db != (
            expected.minimum_ssb_es_iot_tenth_db
        ):
            raise Error("mutated RedCap Annex FR1 condition")


def nr_redcap_rel17_annex_fr1_condition(
    condition_family: Int,
    frequency_relation: Int,
    rx_branches: Int,
    band_group: Int,
    ssb_scs_khz: Int,
    *,
    profile: Int = NR_REDCAP_ANNEX_PROFILE_REDCAP_REL17,
) raises -> NRRedCapAnnexFR1Condition:
    """Return an exact B.1.4/B.1.5/B.2.15/B.2.16 FR1 row."""
    return NRRedCapAnnexFR1Condition(
        condition_family,
        frequency_relation,
        rx_branches,
        band_group,
        ssb_scs_khz,
        profile=profile,
    )


struct _FR2ConditionValues(ImplicitlyCopyable):
    var base_tenth_dbm: Int
    var es_iot_tenth_db: Int
    var rough_fine_adjustment_kind: Int
    var multiband_adjustment_kind: Int

    def __init__(
        out self,
        base_tenth_dbm: Int,
        es_iot_tenth_db: Int,
        rough_fine_adjustment_kind: Int,
        multiband_adjustment_kind: Int,
    ):
        self.base_tenth_dbm = base_tenth_dbm
        self.es_iot_tenth_db = es_iot_tenth_db
        self.rough_fine_adjustment_kind = rough_fine_adjustment_kind
        self.multiband_adjustment_kind = multiband_adjustment_kind


def _fr2_power_column(power_class: Int) raises -> Int:
    if power_class == 1:
        return 0
    if power_class == 2:
        return 1
    if power_class == 3:
        return 2
    if power_class == 4:
        return 3
    if power_class == 5:
        return 4
    if power_class == 7:
        return 5
    raise Error("RedCap Annex FR2 power class must be 1/2/3/4/5/7")


def _fr2_condition_values(
    source_table: Int,
    angle_of_arrival: Int,
    nr_band: Int,
    power_class: Int,
    ssb_scs_khz: Int,
    profile: Int,
) raises -> _FR2ConditionValues:
    _validate_rel17_profile(profile)
    if source_table != NR_REDCAP_ANNEX_TABLE_B1_4_3 and (
        source_table != NR_REDCAP_ANNEX_TABLE_B2_15_3
    ) and source_table != (
        NR_REDCAP_ANNEX_TABLE_B2_16_2_AS_PUBLISHED
    ) and source_table != NR_REDCAP_ANNEX_TABLE_B2_16_3:
        raise Error("invalid RedCap Annex FR2 source table")
    if angle_of_arrival != NR_REDCAP_ANNEX_AOA_RX_BEAM_PEAK and (
        angle_of_arrival != NR_REDCAP_ANNEX_AOA_SPHERICAL_COVERAGE
    ):
        raise Error("RedCap Annex FR2 AoA must be beam peak or spherical")
    if nr_band != 257 and nr_band != 258 and nr_band != 261:
        raise Error("RedCap Annex FR2 band must be n257, n258, or n261")
    var column = _fr2_power_column(power_class)
    if nr_band == 261 and power_class == 5:
        raise Error("published RedCap Annex FR2 tables have no n261/PC5 row")
    if ssb_scs_khz != 120 and ssb_scs_khz != 240:
        raise Error("RedCap Annex FR2 condition SSB SCS must be 120/240 kHz")
    if ssb_scs_khz == 240 and power_class == 7 and (
        source_table != NR_REDCAP_ANNEX_TABLE_B1_4_3
    ):
        raise Error("published connected FR2 240-kHz header excludes PC7")

    var beam_peak = angle_of_arrival == NR_REDCAP_ANNEX_AOA_RX_BEAM_PEAK
    var base_tenth_dbm: Int
    if source_table == NR_REDCAP_ANNEX_TABLE_B1_4_3:
        if beam_peak:
            if column == 0:
                base_tenth_dbm = -1073
            elif column == 1:
                base_tenth_dbm = -1108
            elif column == 2:
                base_tenth_dbm = -1091
            elif column == 3:
                base_tenth_dbm = -1248
            elif column == 4:
                base_tenth_dbm = -1206 if nr_band == 258 else -1204
            else:
                base_tenth_dbm = -1131
        else:
            if column == 0:
                base_tenth_dbm = -993
            elif column == 1:
                base_tenth_dbm = -998
            elif column == 2:
                base_tenth_dbm = -982
            elif column == 3:
                base_tenth_dbm = -1158
            elif column == 4:
                base_tenth_dbm = -1126 if nr_band == 258 else -1124
            else:
                base_tenth_dbm = -1022
    elif source_table == NR_REDCAP_ANNEX_TABLE_B2_15_3:
        if beam_peak:
            if column == 0:
                base_tenth_dbm = -1103
            elif column == 1:
                base_tenth_dbm = -1138
            elif column == 2:
                base_tenth_dbm = -1121
            elif column == 3:
                base_tenth_dbm = -1278
            elif column == 4:
                base_tenth_dbm = -1236 if nr_band == 258 else -1234
            else:
                base_tenth_dbm = -1161
        else:
            if column == 0:
                base_tenth_dbm = -1023
            elif column == 1:
                base_tenth_dbm = -1028
            elif column == 2:
                base_tenth_dbm = -1012
            elif column == 3:
                base_tenth_dbm = -1188
            elif column == 4:
                base_tenth_dbm = -1156 if nr_band == 258 else -1154
            else:
                base_tenth_dbm = -1052
    elif source_table == NR_REDCAP_ANNEX_TABLE_B2_16_2_AS_PUBLISHED:
        if beam_peak:
            if column == 0:
                base_tenth_dbm = -1263
            elif column == 1:
                base_tenth_dbm = -1118
            elif column == 2:
                base_tenth_dbm = -1101
            elif column == 3:
                base_tenth_dbm = -1258
            elif column == 4:
                base_tenth_dbm = -1216 if nr_band == 258 else -1214
            else:
                base_tenth_dbm = -1141
        else:
            if column == 0:
                base_tenth_dbm = -1183
            elif column == 1:
                base_tenth_dbm = -1008
            elif column == 2:
                base_tenth_dbm = -992
            elif column == 3:
                base_tenth_dbm = -1168
            elif column == 4:
                base_tenth_dbm = -1136 if nr_band == 258 else -1134
            else:
                base_tenth_dbm = -1032
    else:
        if beam_peak:
            if column == 0:
                base_tenth_dbm = -1083
            elif column == 1:
                base_tenth_dbm = -1118
            elif column == 2:
                base_tenth_dbm = -1101
            elif column == 3:
                base_tenth_dbm = -1258
            elif column == 4:
                base_tenth_dbm = -1216 if nr_band == 258 else -1214
            else:
                base_tenth_dbm = -1141
        else:
            if column == 0:
                base_tenth_dbm = -1003
            elif column == 1:
                base_tenth_dbm = -1008
            elif column == 2:
                base_tenth_dbm = -992
            elif column == 3:
                base_tenth_dbm = -1168
            elif column == 4:
                base_tenth_dbm = -1136 if nr_band == 258 else -1134
            else:
                base_tenth_dbm = -1032

    if ssb_scs_khz == 240:
        base_tenth_dbm += 30
    var symbolic = column >= 3
    if source_table == NR_REDCAP_ANNEX_TABLE_B2_16_2_AS_PUBLISHED and (
        column == 0
    ):
        symbolic = True
    var rough_fine_kind = NR_REDCAP_ANNEX_ADJUSTMENT_NONE
    if symbolic:
        rough_fine_kind = (
            NR_REDCAP_ANNEX_ADJUSTMENT_Y
            if beam_peak
            else NR_REDCAP_ANNEX_ADJUSTMENT_Z
        )
    var multiband_kind = (
        NR_REDCAP_ANNEX_MULTIBAND_MBP
        if beam_peak
        else NR_REDCAP_ANNEX_MULTIBAND_MBS
    )
    var es_iot_tenth_db = (
        -60 if source_table == NR_REDCAP_ANNEX_TABLE_B2_15_3 else -40
    )
    return _FR2ConditionValues(
        base_tenth_dbm,
        es_iot_tenth_db,
        rough_fine_kind,
        multiband_kind,
    )


struct NRRedCapAnnexFR2Condition(ImplicitlyCopyable):
    """Exact published FR2-shaped Annex-B condition expression."""

    var profile: Int
    var source_table: Int
    var angle_of_arrival: Int
    var nr_band: Int
    var power_class: Int
    var ssb_scs_khz: Int
    var minimum_ssb_rp_base_tenth_dbm: Int
    var minimum_ssb_es_iot_tenth_db: Int
    var rough_fine_adjustment_kind: Int
    var multiband_adjustment_kind: Int

    def __init__(
        out self,
        source_table: Int,
        angle_of_arrival: Int,
        nr_band: Int,
        power_class: Int,
        ssb_scs_khz: Int,
        *,
        profile: Int = NR_REDCAP_ANNEX_PROFILE_REDCAP_REL17,
    ) raises:
        self.profile = profile
        self.source_table = source_table
        self.angle_of_arrival = angle_of_arrival
        self.nr_band = nr_band
        self.power_class = power_class
        self.ssb_scs_khz = ssb_scs_khz
        var expected = _fr2_condition_values(
            source_table,
            angle_of_arrival,
            nr_band,
            power_class,
            ssb_scs_khz,
            profile,
        )
        self.minimum_ssb_rp_base_tenth_dbm = expected.base_tenth_dbm
        self.minimum_ssb_es_iot_tenth_db = expected.es_iot_tenth_db
        self.rough_fine_adjustment_kind = (
            expected.rough_fine_adjustment_kind
        )
        self.multiband_adjustment_kind = expected.multiband_adjustment_kind
        self.validate()

    def validate(self) raises:
        """Re-read the published expression and reject mutated state."""
        var expected = _fr2_condition_values(
            self.source_table,
            self.angle_of_arrival,
            self.nr_band,
            self.power_class,
            self.ssb_scs_khz,
            self.profile,
        )
        if self.minimum_ssb_rp_base_tenth_dbm != expected.base_tenth_dbm or (
            self.minimum_ssb_es_iot_tenth_db != expected.es_iot_tenth_db
        ) or self.rough_fine_adjustment_kind != (
            expected.rough_fine_adjustment_kind
        ) or self.multiband_adjustment_kind != (
            expected.multiband_adjustment_kind
        ):
            raise Error("mutated RedCap Annex FR2 condition")


def nr_redcap_rel17_annex_fr2_condition(
    source_table: Int,
    angle_of_arrival: Int,
    nr_band: Int,
    power_class: Int,
    ssb_scs_khz: Int,
    *,
    profile: Int = NR_REDCAP_ANNEX_PROFILE_REDCAP_REL17,
) raises -> NRRedCapAnnexFR2Condition:
    """Return an exact FR2-shaped B.1.4/B.2.15/B.2.16 expression."""
    return NRRedCapAnnexFR2Condition(
        source_table,
        angle_of_arrival,
        nr_band,
        power_class,
        ssb_scs_khz,
        profile=profile,
    )


def nr_redcap_rel17_annex_resolve_fr2_minimum_ssb_rp_tenth_dbm(
    condition: NRRedCapAnnexFR2Condition,
    rough_fine_adjustment_tenth_db: Int,
    multiband_relaxation_tenth_db: Int,
) raises -> Int:
    """Resolve a symbolic FR2 row with caller-owned TS 38.101-2 terms."""
    condition.validate()
    if rough_fine_adjustment_tenth_db < 0 or (
        multiband_relaxation_tenth_db < 0
    ):
        raise Error("RedCap Annex FR2 adjustments must be non-negative")
    if condition.rough_fine_adjustment_kind == (
        NR_REDCAP_ANNEX_ADJUSTMENT_NONE
    ) and rough_fine_adjustment_tenth_db != 0:
        raise Error("numeric RedCap Annex FR2 row cannot carry a Y/Z term")
    var resolved = (
        Int128(condition.minimum_ssb_rp_base_tenth_dbm)
        + Int128(rough_fine_adjustment_tenth_db)
        + Int128(multiband_relaxation_tenth_db)
    )
    if resolved > Int128(Int.MAX) or resolved < Int128(Int.MIN):
        raise Error("resolved RedCap Annex FR2 minimum SSB_RP exceeds Int")
    return Int(resolved)
