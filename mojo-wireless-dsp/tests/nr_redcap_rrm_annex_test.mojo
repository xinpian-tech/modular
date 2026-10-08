"""External-static evidence for TS 38.133 V17.22.0 RedCap Annex tables.

The literals below were transcribed independently from the table cells in the
official 3GPP ``38133-hm0.zip`` archive.  Production lookup helpers are never
used to derive expected values.  All dB values are compared exactly as signed
tenths, including every published row and symbolic base expression.
"""

from std.testing import assert_equal, assert_raises, TestSuite
from wireless_dsp.wireless.nr.redcap_rrm_annex import (
    NR_REDCAP_ANNEX_PROFILE_ORDINARY_NR,
    NR_REDCAP_ANNEX_PROFILE_REDCAP_REL17,
    NR_REDCAP_ANNEX_PROFILE_EREDCAP_REL18,
    NR_REDCAP_ANNEX_FR1,
    NR_REDCAP_ANNEX_FR2,
    NR_REDCAP_ANNEX_BWP_DOWNLINK,
    NR_REDCAP_ANNEX_BWP_UPLINK,
    NR_REDCAP_ANNEX_SSB_LOCATION_CELL_RASTER,
    NR_REDCAP_ANNEX_SSB_LOCATION_ASSOCIATED_BWP_NON_RASTER,
    NR_REDCAP_ANNEX_SOURCE_NR,
    NR_REDCAP_ANNEX_SOURCE_EUTRA,
    NR_REDCAP_ANNEX_TEST_CLAUSE_A16,
    NR_REDCAP_ANNEX_TEST_CLAUSE_A17,
    NR_REDCAP_ANNEX_TEST_CLAUSE_A18,
    NR_REDCAP_ANNEX_CONDITION_CELL_RESELECTION,
    NR_REDCAP_ANNEX_CONDITION_CONNECTED_MEASUREMENT,
    NR_REDCAP_ANNEX_RELATION_INTRA_FREQUENCY,
    NR_REDCAP_ANNEX_RELATION_INTER_FREQUENCY,
    NR_REDCAP_ANNEX_TABLE_B1_4,
    NR_REDCAP_ANNEX_TABLE_B1_5,
    NR_REDCAP_ANNEX_TABLE_B2_15,
    NR_REDCAP_ANNEX_TABLE_B2_16,
    NR_REDCAP_ANNEX_TABLE_B1_4_3,
    NR_REDCAP_ANNEX_TABLE_B2_15_3,
    NR_REDCAP_ANNEX_TABLE_B2_16_2_AS_PUBLISHED,
    NR_REDCAP_ANNEX_TABLE_B2_16_3,
    NR_REDCAP_ANNEX_AOA_RX_BEAM_PEAK,
    NR_REDCAP_ANNEX_AOA_SPHERICAL_COVERAGE,
    NR_REDCAP_ANNEX_ADJUSTMENT_NONE,
    NR_REDCAP_ANNEX_ADJUSTMENT_Y,
    NR_REDCAP_ANNEX_ADJUSTMENT_Z,
    NR_REDCAP_ANNEX_MULTIBAND_MBP,
    NR_REDCAP_ANNEX_MULTIBAND_MBS,
    nr_redcap_rel17_annex_bwp_configuration,
    nr_redcap_rel17_annex_ssb_configuration,
    nr_redcap_rel17_annex_smtc_configuration,
    nr_redcap_rel17_annex_test_scope,
    nr_redcap_rel17_annex_fr1_condition,
    nr_redcap_rel17_annex_fr2_condition,
    nr_redcap_rel17_annex_resolve_fr2_minimum_ssb_rp_tenth_dbm,
)


def _ssb_scs(index: Int) -> Int:
    if index == 0:
        return 15
    if index == 1:
        return 30
    if index == 2:
        return 120
    return 240


def test_a_3_9a_all_24_bwp_rows_exact() raises:
    var scs_values = [15, 30, 120, 240]
    var bandwidths = [25, 25, 32, 16]
    var row_count = 0
    for direction in range(2):
        for pattern in range(1, 4):
            for scs_index in range(4):
                var config = nr_redcap_rel17_annex_bwp_configuration(
                    direction, pattern, scs_values[scs_index]
                )
                config.validate()
                assert_equal(config.profile, 1)
                assert_equal(config.direction, direction)
                assert_equal(config.pattern, pattern)
                assert_equal(config.bandwidth_prbs, bandwidths[scs_index])
                assert_equal(config.starting_prb_rule, pattern)
                row_count += 1
    assert_equal(row_count, 24)


def test_a_3_10b_all_ssb_patterns_and_case_b_rows_exact() raises:
    # Seven literal FR1 table rows.  Table A.3.10B.1.7-1's caption says
    # 40 MHz, but its normative Channel-bandwidth cell says 20 MHz.
    var fr1_channel = [20, 20, 20, 10, 20, 10, 20]
    var fr1_scs = [30, 30, 30, 15, 30, 15, 30]
    var fr1_period = [20, 20, 20, 20, 20, 80, 80]
    var fr1_count = [1, 2, 1, 1, 1, 1, 1]
    var fr1_second = [-1, 8, -1, -1, -1, -1, -1]
    var fr1_remainder = [0, 0, 1, 0, 0, 0, 0]
    var fr1_location = [0, 0, 0, 0, 0, 1, 1]
    var row_count = 0
    for pattern in range(1, 8):
        var config = nr_redcap_rel17_annex_ssb_configuration(
            NR_REDCAP_ANNEX_FR1, pattern
        )
        config.validate()
        assert_equal(
            config.channel_bandwidth_mhz,
            fr1_channel[pattern - 1],
        )
        assert_equal(
            config.ssb_scs_khz, fr1_scs[pattern - 1]
        )
        assert_equal(
            config.periodicity_ms,
            fr1_period[pattern - 1],
        )
        assert_equal(
            config.number_of_ssbs,
            fr1_count[pattern - 1],
        )
        assert_equal(config.first_symbol_start, 2)
        assert_equal(
            config.second_symbol_start,
            fr1_second[pattern - 1],
        )
        assert_equal(config.slot_number, 0)
        assert_equal(config.sfn_modulus, config.periodicity_ms // 10)
        assert_equal(
            config.sfn_remainder,
            fr1_remainder[pattern - 1],
        )
        assert_equal(config.ssb_prbs, 20)
        assert_equal(
            config.location_rule,
            fr1_location[pattern - 1],
        )
        row_count += 1

    # The five 30-kHz patterns have a literal Case-B alternative of symbols
    # 4-7; pattern 2's second SSB remains at symbols 8-11.
    for pattern in [1, 2, 3, 5, 7]:
        var case_b = nr_redcap_rel17_annex_ssb_configuration(
            NR_REDCAP_ANNEX_FR1, pattern, True
        )
        assert_equal(case_b.first_symbol_start, 4)
        assert_equal(case_b.second_symbol_start, 8 if pattern == 2 else -1)
        row_count += 1

    var fr2_scs = [120, 120, 120, 240, 240]
    var fr2_period = [20, 40, 80, 40, 80]
    var fr2_symbol = [4, 4, 4, 8, 8]
    var fr2_location = [0, 0, 1, 0, 1]
    for pattern in range(1, 6):
        var config = nr_redcap_rel17_annex_ssb_configuration(
            NR_REDCAP_ANNEX_FR2, pattern
        )
        config.validate()
        assert_equal(config.channel_bandwidth_mhz, 100)
        assert_equal(config.ssb_scs_khz, fr2_scs[pattern - 1])
        assert_equal(config.periodicity_ms, fr2_period[pattern - 1])
        assert_equal(config.number_of_ssbs, 1)
        assert_equal(config.first_symbol_start, fr2_symbol[pattern - 1])
        assert_equal(config.second_symbol_start, -1)
        assert_equal(config.sfn_modulus, config.periodicity_ms // 10)
        assert_equal(config.sfn_remainder, 0)
        assert_equal(config.location_rule, fr2_location[pattern - 1])
        row_count += 1
    assert_equal(row_count, 17)


def test_a_3_11a_and_a_3_35_complete_literal_tables() raises:
    var periods = [40, 80, 40, 80]
    var offsets = [0, 0, 20, 0]
    var durations = [1, 1, 1, 5]
    for pattern in range(1, 5):
        var config = nr_redcap_rel17_annex_smtc_configuration(pattern)
        config.validate()
        assert_equal(config.periodicity_ms, periods[pattern - 1])
        assert_equal(config.offset_ms, offsets[pattern - 1])
        assert_equal(config.duration_ms, durations[pattern - 1])

    for rx in range(1, 3):
        var fr1 = nr_redcap_rel17_annex_test_scope(
            NR_REDCAP_ANNEX_SOURCE_NR, NR_REDCAP_ANNEX_FR1, rx
        )
        assert_equal(fr1.annex_clause, NR_REDCAP_ANNEX_TEST_CLAUSE_A16)
        var eutra_fr1 = nr_redcap_rel17_annex_test_scope(
            NR_REDCAP_ANNEX_SOURCE_EUTRA, NR_REDCAP_ANNEX_FR1, rx
        )
        assert_equal(
            eutra_fr1.annex_clause, NR_REDCAP_ANNEX_TEST_CLAUSE_A18
        )
    var fr2 = nr_redcap_rel17_annex_test_scope(
        NR_REDCAP_ANNEX_SOURCE_NR, NR_REDCAP_ANNEX_FR2, 2
    )
    assert_equal(fr2.annex_clause, NR_REDCAP_ANNEX_TEST_CLAUSE_A17)
    var eutra_fr2 = nr_redcap_rel17_annex_test_scope(
        NR_REDCAP_ANNEX_SOURCE_EUTRA, NR_REDCAP_ANNEX_FR2, 2
    )
    assert_equal(eutra_fr2.annex_clause, NR_REDCAP_ANNEX_TEST_CLAUSE_A18)


def _assert_fr1_condition(
    family: Int,
    relation: Int,
    rx: Int,
    group: Int,
    scs_khz: Int,
    source_table: Int,
    expected_tenth_dbm: Int,
    expected_es_iot_tenth_db: Int,
) raises:
    var condition = nr_redcap_rel17_annex_fr1_condition(
        family, relation, rx, group, scs_khz
    )
    condition.validate()
    assert_equal(condition.source_table, source_table)
    assert_equal(condition.minimum_ssb_rp_tenth_dbm, expected_tenth_dbm)
    assert_equal(
        condition.minimum_ssb_es_iot_tenth_db, expected_es_iot_tenth_db
    )


def test_annex_b_all_112_usable_fr1_rows_exact() raises:
    var b14_15 = [
        -1240, -1235, -1230, -1225, -1220, -1215, -1210, -1205
    ]
    var b215_15 = [
        -1270, -1265, -1260, -1255, -1250, -1245, -1240, -1235
    ]
    var b216_15 = [
        -1250, -1245, -1240, -1245, -1230, -1225, -1220, -1215
    ]
    var b216_30 = [
        -1220, -1215, -1210, -1205, -1200, -1195, -1190, -1185
    ]
    var row_count = 0
    for relation in range(2):
        for rx in range(1, 3):
            for group in range(8):
                for scs_index in range(2):
                    var scs_khz = 15 if scs_index == 0 else 30
                    var scs_offset = 0 if scs_khz == 15 else 30
                    _assert_fr1_condition(
                        NR_REDCAP_ANNEX_CONDITION_CELL_RESELECTION,
                        relation,
                        rx,
                        group,
                        scs_khz,
                        (
                            NR_REDCAP_ANNEX_TABLE_B1_4
                            if relation == 0
                            else NR_REDCAP_ANNEX_TABLE_B1_5
                        ),
                        b14_15[group] + scs_offset,
                        -40,
                    )
                    row_count += 1

    for rx in range(1, 3):
        for group in range(8):
            for scs_index in range(2):
                var scs_khz = 15 if scs_index == 0 else 30
                var scs_offset = 0 if scs_khz == 15 else 30
                _assert_fr1_condition(
                    NR_REDCAP_ANNEX_CONDITION_CONNECTED_MEASUREMENT,
                    NR_REDCAP_ANNEX_RELATION_INTRA_FREQUENCY,
                    rx,
                    group,
                    scs_khz,
                    NR_REDCAP_ANNEX_TABLE_B2_15,
                    b215_15[group] + scs_offset,
                    -60,
                )
                row_count += 1

    for group in range(8):
        for scs_index in range(2):
            var scs_khz = 15 if scs_index == 0 else 30
            _assert_fr1_condition(
                NR_REDCAP_ANNEX_CONDITION_CONNECTED_MEASUREMENT,
                NR_REDCAP_ANNEX_RELATION_INTER_FREQUENCY,
                1,
                group,
                scs_khz,
                NR_REDCAP_ANNEX_TABLE_B2_16,
                b216_15[group] if scs_khz == 15 else b216_30[group],
                -40,
            )
            row_count += 1
    assert_equal(row_count, 112)


def _power_class(index: Int) -> Int:
    if index < 5:
        return index + 1
    return 7


def _oracle_fr2_base(
    source_table: Int, angle: Int, band: Int, power_class: Int
) -> Int:
    var column = power_class - 1 if power_class <= 5 else 5
    var beam = angle == NR_REDCAP_ANNEX_AOA_RX_BEAM_PEAK
    if source_table == NR_REDCAP_ANNEX_TABLE_B1_4_3:
        var beam_values = [-1073, -1108, -1091, -1248, -1204, -1131]
        var sphere_values = [-993, -998, -982, -1158, -1124, -1022]
        if band == 258 and power_class == 5:
            return -1206 if beam else -1126
        return beam_values[column] if beam else sphere_values[column]
    if source_table == NR_REDCAP_ANNEX_TABLE_B2_15_3:
        var beam_values = [-1103, -1138, -1121, -1278, -1234, -1161]
        var sphere_values = [-1023, -1028, -1012, -1188, -1154, -1052]
        if band == 258 and power_class == 5:
            return -1236 if beam else -1156
        return beam_values[column] if beam else sphere_values[column]
    if source_table == NR_REDCAP_ANNEX_TABLE_B2_16_2_AS_PUBLISHED:
        var beam_values = [-1263, -1118, -1101, -1258, -1214, -1141]
        var sphere_values = [-1183, -1008, -992, -1168, -1134, -1032]
        if band == 258 and power_class == 5:
            return -1216 if beam else -1136
        return beam_values[column] if beam else sphere_values[column]
    var beam_values = [-1083, -1118, -1101, -1258, -1214, -1141]
    var sphere_values = [-1003, -1008, -992, -1168, -1134, -1032]
    if band == 258 and power_class == 5:
        return -1216 if beam else -1136
    return beam_values[column] if beam else sphere_values[column]


def test_annex_b_all_254_published_fr2_expression_rows_exact() raises:
    var tables = [1043, 2153, 2162, 2163]
    var bands = [257, 258, 261]
    var row_count = 0
    for source_table in tables:
        for angle in range(2):
            for band in bands:
                for power_index in range(6):
                    var power_class = _power_class(power_index)
                    if band == 261 and power_class == 5:
                        continue
                    for scs_index in range(2):
                        var scs_khz = 120 if scs_index == 0 else 240
                        if scs_khz == 240 and power_class == 7 and (
                            source_table != NR_REDCAP_ANNEX_TABLE_B1_4_3
                        ):
                            continue
                        var condition = nr_redcap_rel17_annex_fr2_condition(
                            source_table,
                            angle,
                            band,
                            power_class,
                            scs_khz,
                        )
                        condition.validate()
                        var expected_base = _oracle_fr2_base(
                            source_table, angle, band, power_class
                        )
                        if scs_khz == 240:
                            expected_base += 30
                        assert_equal(
                            condition.minimum_ssb_rp_base_tenth_dbm,
                            expected_base,
                        )
                        assert_equal(
                            condition.minimum_ssb_es_iot_tenth_db,
                            -60 if source_table == 2153 else -40,
                        )
                        var symbolic = power_class >= 4
                        if source_table == 2162 and power_class == 1:
                            symbolic = True
                        var expected_kind = 0
                        if symbolic:
                            expected_kind = 1 if angle == 0 else 2
                        assert_equal(
                            condition.rough_fine_adjustment_kind,
                            expected_kind,
                        )
                        assert_equal(
                            condition.multiband_adjustment_kind,
                            1 if angle == 0 else 2,
                        )
                        var rough_fine = 11 if symbolic else 0
                        var resolved = (
                            nr_redcap_rel17_annex_resolve_fr2_minimum_ssb_rp_tenth_dbm(
                                condition, rough_fine, 7
                            )
                        )
                        assert_equal(
                            resolved, expected_base + rough_fine + 7
                        )
                        row_count += 1
    assert_equal(row_count, 254)


def test_public_invalid_mutable_and_overflow_edges() raises:
    with assert_raises():
        _ = nr_redcap_rel17_annex_bwp_configuration(2, 1, 15)
    with assert_raises():
        _ = nr_redcap_rel17_annex_bwp_configuration(0, 0, 15)
    with assert_raises():
        _ = nr_redcap_rel17_annex_bwp_configuration(0, 4, 15)
    with assert_raises():
        _ = nr_redcap_rel17_annex_bwp_configuration(0, 1, 60)
    with assert_raises():
        _ = nr_redcap_rel17_annex_bwp_configuration(
            0, 1, 15, profile=NR_REDCAP_ANNEX_PROFILE_ORDINARY_NR
        )

    with assert_raises():
        _ = nr_redcap_rel17_annex_ssb_configuration(0, 1)
    with assert_raises():
        _ = nr_redcap_rel17_annex_ssb_configuration(1, 0)
    with assert_raises():
        _ = nr_redcap_rel17_annex_ssb_configuration(1, 8)
    with assert_raises():
        _ = nr_redcap_rel17_annex_ssb_configuration(2, 6)
    with assert_raises():
        _ = nr_redcap_rel17_annex_ssb_configuration(1, 4, True)
    with assert_raises():
        _ = nr_redcap_rel17_annex_ssb_configuration(2, 1, True)
    with assert_raises():
        _ = nr_redcap_rel17_annex_ssb_configuration(
            1, 1, profile=NR_REDCAP_ANNEX_PROFILE_EREDCAP_REL18
        )
    with assert_raises():
        _ = nr_redcap_rel17_annex_smtc_configuration(0)
    with assert_raises():
        _ = nr_redcap_rel17_annex_smtc_configuration(5)
    with assert_raises():
        _ = nr_redcap_rel17_annex_smtc_configuration(
            1, profile=NR_REDCAP_ANNEX_PROFILE_ORDINARY_NR
        )

    with assert_raises():
        _ = nr_redcap_rel17_annex_test_scope(2, 1, 1)
    with assert_raises():
        _ = nr_redcap_rel17_annex_test_scope(0, 2, 1)
    with assert_raises():
        _ = nr_redcap_rel17_annex_test_scope(
            0, 1, 1, profile=NR_REDCAP_ANNEX_PROFILE_EREDCAP_REL18
        )

    with assert_raises():
        _ = nr_redcap_rel17_annex_fr1_condition(2, 0, 1, 0, 15)
    with assert_raises():
        _ = nr_redcap_rel17_annex_fr1_condition(0, 2, 1, 0, 15)
    with assert_raises():
        _ = nr_redcap_rel17_annex_fr1_condition(0, 0, 0, 0, 15)
    with assert_raises():
        _ = nr_redcap_rel17_annex_fr1_condition(0, 0, 1, -1, 15)
    with assert_raises():
        _ = nr_redcap_rel17_annex_fr1_condition(0, 0, 1, 8, 15)
    with assert_raises():
        _ = nr_redcap_rel17_annex_fr1_condition(0, 0, 1, 0, 60)
    with assert_raises():
        _ = nr_redcap_rel17_annex_fr1_condition(1, 1, 2, 0, 15)
    with assert_raises():
        _ = nr_redcap_rel17_annex_fr1_condition(
            0,
            0,
            1,
            0,
            15,
            profile=NR_REDCAP_ANNEX_PROFILE_EREDCAP_REL18,
        )

    with assert_raises():
        _ = nr_redcap_rel17_annex_fr2_condition(0, 0, 257, 1, 120)
    with assert_raises():
        _ = nr_redcap_rel17_annex_fr2_condition(1043, 2, 257, 1, 120)
    with assert_raises():
        _ = nr_redcap_rel17_annex_fr2_condition(1043, 0, 260, 1, 120)
    with assert_raises():
        _ = nr_redcap_rel17_annex_fr2_condition(1043, 0, 257, 6, 120)
    with assert_raises():
        _ = nr_redcap_rel17_annex_fr2_condition(1043, 0, 261, 5, 120)
    with assert_raises():
        _ = nr_redcap_rel17_annex_fr2_condition(2153, 0, 257, 7, 240)
    with assert_raises():
        _ = nr_redcap_rel17_annex_fr2_condition(1043, 0, 257, 1, 60)
    with assert_raises():
        _ = nr_redcap_rel17_annex_fr2_condition(
            1043,
            0,
            257,
            1,
            120,
            profile=NR_REDCAP_ANNEX_PROFILE_ORDINARY_NR,
        )

    var bwp = nr_redcap_rel17_annex_bwp_configuration(0, 1, 15)
    bwp.bandwidth_prbs = 24
    with assert_raises():
        bwp.validate()
    var ssb = nr_redcap_rel17_annex_ssb_configuration(1, 2)
    ssb.number_of_ssbs = 1
    with assert_raises():
        ssb.validate()
    var smtc = nr_redcap_rel17_annex_smtc_configuration(3)
    smtc.offset_ms = 0
    with assert_raises():
        smtc.validate()
    var scope = nr_redcap_rel17_annex_test_scope(0, 1, 1)
    scope.annex_clause = 18
    with assert_raises():
        scope.validate()
    var fr1 = nr_redcap_rel17_annex_fr1_condition(0, 0, 1, 0, 15)
    fr1.minimum_ssb_rp_tenth_dbm += 1
    with assert_raises():
        fr1.validate()
    var fr2 = nr_redcap_rel17_annex_fr2_condition(1043, 0, 257, 4, 120)
    fr2.rough_fine_adjustment_kind = 0
    with assert_raises():
        fr2.validate()
    with assert_raises():
        _ = nr_redcap_rel17_annex_resolve_fr2_minimum_ssb_rp_tenth_dbm(
            fr2, 10, 0
        )

    var numeric = nr_redcap_rel17_annex_fr2_condition(
        1043, 0, 257, 1, 120
    )
    with assert_raises():
        _ = nr_redcap_rel17_annex_resolve_fr2_minimum_ssb_rp_tenth_dbm(
            numeric, 1, 0
        )
    with assert_raises():
        _ = nr_redcap_rel17_annex_resolve_fr2_minimum_ssb_rp_tenth_dbm(
            numeric, 0, -1
        )
    var symbolic = nr_redcap_rel17_annex_fr2_condition(
        1043, 0, 257, 4, 120
    )
    with assert_raises():
        _ = nr_redcap_rel17_annex_resolve_fr2_minimum_ssb_rp_tenth_dbm(
            symbolic, Int.MAX, Int.MAX
        )


def test_seeded_properties_exact_scs_delta_and_checked_resolution() raises:
    var state = UInt64(0x38_133_17_22)
    for iteration in range(2048):
        state = state * UInt64(6364136223846793005) + UInt64(1442695040888963407)
        var direction = Int((state >> 7) & UInt64(1))
        var pattern = Int((state >> 11) % UInt64(3)) + 1
        var scs_index = Int((state >> 17) & UInt64(3))
        var config = nr_redcap_rel17_annex_bwp_configuration(
            direction, pattern, _ssb_scs(scs_index)
        )
        assert_equal(config.starting_prb_rule, pattern)

        var frequency_range = (
            NR_REDCAP_ANNEX_FR1
            if ((state >> 19) & UInt64(1)) == 0
            else NR_REDCAP_ANNEX_FR2
        )
        var ssb_pattern = (
            Int((state >> 21) % UInt64(7)) + 1
            if frequency_range == NR_REDCAP_ANNEX_FR1
            else Int((state >> 21) % UInt64(5)) + 1
        )
        var ssb = nr_redcap_rel17_annex_ssb_configuration(
            frequency_range, ssb_pattern
        )
        assert_equal(ssb.sfn_modulus, ssb.periodicity_ms // 10)
        assert_equal(ssb.sfn_remainder < ssb.sfn_modulus, True)

        var smtc = nr_redcap_rel17_annex_smtc_configuration(
            Int((state >> 25) & UInt64(3)) + 1
        )
        assert_equal(smtc.offset_ms < smtc.periodicity_ms, True)
        assert_equal(smtc.duration_ms <= 5, True)

        var source_rat = Int((state >> 29) & UInt64(1))
        var scope_rx = (
            2
            if frequency_range == NR_REDCAP_ANNEX_FR2
            else 1 + Int((state >> 30) & UInt64(1))
        )
        var scope = nr_redcap_rel17_annex_test_scope(
            source_rat, frequency_range, scope_rx
        )
        assert_equal(
            scope.annex_clause,
            (
                18
                if source_rat == NR_REDCAP_ANNEX_SOURCE_EUTRA
                else (16 if frequency_range == NR_REDCAP_ANNEX_FR1 else 17)
            ),
        )

        var group = Int((state >> 23) & UInt64(7))
        var fr1_15 = nr_redcap_rel17_annex_fr1_condition(
            NR_REDCAP_ANNEX_CONDITION_CELL_RESELECTION,
            NR_REDCAP_ANNEX_RELATION_INTER_FREQUENCY,
            1 + Int((state >> 31) & UInt64(1)),
            group,
            15,
        )
        var fr1_30 = nr_redcap_rel17_annex_fr1_condition(
            NR_REDCAP_ANNEX_CONDITION_CELL_RESELECTION,
            NR_REDCAP_ANNEX_RELATION_INTER_FREQUENCY,
            fr1_15.rx_branches,
            group,
            30,
        )
        assert_equal(
            fr1_30.minimum_ssb_rp_tenth_dbm,
            fr1_15.minimum_ssb_rp_tenth_dbm + 30,
        )

        var source_table = 1043 + 1110 * Int((state >> 37) & UInt64(1))
        var angle = Int((state >> 41) & UInt64(1))
        var band = 257 if ((state >> 43) & UInt64(1)) == 0 else 258
        var fr2_120 = nr_redcap_rel17_annex_fr2_condition(
            source_table, angle, band, 2, 120
        )
        var fr2_240 = nr_redcap_rel17_annex_fr2_condition(
            source_table, angle, band, 2, 240
        )
        assert_equal(
            fr2_240.minimum_ssb_rp_base_tenth_dbm,
            fr2_120.minimum_ssb_rp_base_tenth_dbm + 30,
        )
        var multiband = Int((state >> 47) & UInt64(127))
        var resolved = (
            nr_redcap_rel17_annex_resolve_fr2_minimum_ssb_rp_tenth_dbm(
                fr2_120, 0, multiband
            )
        )
        assert_equal(
            resolved,
            fr2_120.minimum_ssb_rp_base_tenth_dbm + multiband,
        )
        assert_equal(iteration >= 0, True)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
