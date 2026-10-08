"""Literal-table, edge, property, and exact-boundary RedCap schedule tests.

The expected rows below are an independent static transcription of 3GPP
TS 38.133 V17.22.0 Tables 4.2B.2.2-1..3 and 5.1B.2.2-1..2.  They do not call
production helpers to derive the expected ``M1``, ``N1``, ``Nserv_RedCap``,
filter spacing, or PTW lower bounds.
"""

from std.testing import assert_equal, assert_raises, TestSuite
from wireless_dsp.wireless.nr.redcap_measurement_schedule import (
    NR_REDCAP_MEASUREMENT_PROFILE_ORDINARY_NR,
    NR_REDCAP_MEASUREMENT_PROFILE_EREDCAP_REL18,
    NR_REDCAP_MEASUREMENT_FR1,
    NR_REDCAP_MEASUREMENT_FR2,
    NR_REDCAP_MEASUREMENT_STATE_IDLE,
    NR_REDCAP_MEASUREMENT_STATE_INACTIVE,
    NR_REDCAP_MEASUREMENT_COUNT_DRX,
    NR_REDCAP_MEASUREMENT_COUNT_EDRX,
    NR_REDCAP_MEASUREMENT_COUNT_EFFECTIVE_T,
    NRRedCapServingMeasurementSchedule,
    nr_redcap_rel17_measurement_capability,
    nr_redcap_rel17_idle_serving_measurement_schedule,
    nr_redcap_rel17_inactive_serving_measurement_schedule,
    nr_redcap_rel17_all_neighbour_measurements_required,
)


def _assert_schedule(
    schedule: NRRedCapServingMeasurementSchedule,
    state: Int,
    expected_m1: Int,
    expected_n1: Int,
    expected_nserv: Int,
    expected_unit: Int,
    expected_cycle_us: Int,
    expected_filter_spacing_us: Int,
    expected_ptw_us: Int,
    expected_window_us: Int,
) raises:
    schedule.validate()
    assert_equal(schedule.rrc_state, state)
    assert_equal(schedule.m1, expected_m1)
    assert_equal(schedule.n1, expected_n1)
    assert_equal(schedule.nserv, expected_nserv)
    assert_equal(schedule.count_unit, expected_unit)
    assert_equal(schedule.count_cycle_us, expected_cycle_us)
    assert_equal(
        schedule.minimum_filter_spacing_us, expected_filter_spacing_us
    )
    assert_equal(schedule.minimum_ptw_us, expected_ptw_us)
    assert_equal(schedule.failure_window_us, expected_window_us)


def _literal_drx_cycle_us(index: Int) -> Int:
    if index == 0:
        return 320000
    if index == 1:
        return 640000
    if index == 2:
        return 1280000
    return 2560000


def _literal_short_edrx_cycle_us(index: Int) -> Int:
    if index == 0:
        return 2560000
    if index == 1:
        return 5120000
    return 10240000


def _literal_inactive_t_us(index: Int) -> Int:
    if index < 4:
        return _literal_drx_cycle_us(index)
    if index == 4:
        return 5120000
    return 10240000


def _literal_fr2_n1(index: Int) -> Int:
    if index == 0:
        return 8
    if index == 1:
        return 5
    if index == 2:
        return 4
    return 3


def test_capability_and_idle_static_clause_tables() raises:
    # Clause 4.2B.2.1.1 versus inherited 4.2.2.1 for two-Rx RedCap.
    var one_rx = nr_redcap_rel17_measurement_capability(
        NR_REDCAP_MEASUREMENT_FR1, 1
    )
    assert_equal(one_rx.minimum_intra_frequency_carriers, 1)
    assert_equal(one_rx.minimum_nr_inter_frequency_carriers, 6)
    assert_equal(one_rx.minimum_fdd_eutra_inter_rat_carriers, 6)
    assert_equal(one_rx.minimum_tdd_eutra_inter_rat_carriers, 6)
    assert_equal(one_rx.minimum_total_frequency_layers, 11)

    var two_rx = nr_redcap_rel17_measurement_capability(
        NR_REDCAP_MEASUREMENT_FR1, 2
    )
    assert_equal(two_rx.minimum_intra_frequency_carriers, 1)
    assert_equal(two_rx.minimum_nr_inter_frequency_carriers, 7)
    assert_equal(two_rx.minimum_fdd_eutra_inter_rat_carriers, 7)
    assert_equal(two_rx.minimum_tdd_eutra_inter_rat_carriers, 7)
    assert_equal(two_rx.minimum_total_frequency_layers, 14)

    var fr2 = nr_redcap_rel17_measurement_capability(
        NR_REDCAP_MEASUREMENT_FR2, 2
    )
    assert_equal(fr2.minimum_nr_inter_frequency_carriers, 7)
    assert_equal(fr2.minimum_total_frequency_layers, 14)

    # Table 4.2B.2.2-1, all no-eDRX rows at an SMTC of 40 ms.
    var fr1_320 = nr_redcap_rel17_idle_serving_measurement_schedule(
        NR_REDCAP_MEASUREMENT_FR1, 1, 40000, 320000
    )
    _assert_schedule(
        fr1_320,
        NR_REDCAP_MEASUREMENT_STATE_IDLE,
        2,
        1,
        8,
        NR_REDCAP_MEASUREMENT_COUNT_DRX,
        320000,
        160000,
        0,
        2560000,
    )
    var fr1_640 = nr_redcap_rel17_idle_serving_measurement_schedule(
        NR_REDCAP_MEASUREMENT_FR1, 2, 40000, 640000
    )
    _assert_schedule(
        fr1_640,
        NR_REDCAP_MEASUREMENT_STATE_IDLE,
        2,
        1,
        8,
        NR_REDCAP_MEASUREMENT_COUNT_DRX,
        640000,
        320000,
        0,
        5120000,
    )
    var fr1_1280 = nr_redcap_rel17_idle_serving_measurement_schedule(
        NR_REDCAP_MEASUREMENT_FR1, 1, 40000, 1280000
    )
    _assert_schedule(
        fr1_1280,
        NR_REDCAP_MEASUREMENT_STATE_IDLE,
        1,
        1,
        2,
        NR_REDCAP_MEASUREMENT_COUNT_DRX,
        1280000,
        640000,
        0,
        2560000,
    )
    var fr1_2560 = nr_redcap_rel17_idle_serving_measurement_schedule(
        NR_REDCAP_MEASUREMENT_FR1, 2, 40000, 2560000
    )
    _assert_schedule(
        fr1_2560,
        NR_REDCAP_MEASUREMENT_STATE_IDLE,
        1,
        1,
        2,
        NR_REDCAP_MEASUREMENT_COUNT_DRX,
        2560000,
        1280000,
        0,
        5120000,
    )

    var fr2_320 = nr_redcap_rel17_idle_serving_measurement_schedule(
        NR_REDCAP_MEASUREMENT_FR2, 2, 40000, 320000
    )
    _assert_schedule(
        fr2_320,
        NR_REDCAP_MEASUREMENT_STATE_IDLE,
        2,
        8,
        64,
        NR_REDCAP_MEASUREMENT_COUNT_DRX,
        320000,
        160000,
        0,
        20480000,
    )
    var fr2_640 = nr_redcap_rel17_idle_serving_measurement_schedule(
        NR_REDCAP_MEASUREMENT_FR2, 2, 40000, 640000
    )
    _assert_schedule(
        fr2_640,
        NR_REDCAP_MEASUREMENT_STATE_IDLE,
        2,
        5,
        40,
        NR_REDCAP_MEASUREMENT_COUNT_DRX,
        640000,
        320000,
        0,
        25600000,
    )
    var fr2_1280 = nr_redcap_rel17_idle_serving_measurement_schedule(
        NR_REDCAP_MEASUREMENT_FR2, 2, 40000, 1280000
    )
    _assert_schedule(
        fr2_1280,
        NR_REDCAP_MEASUREMENT_STATE_IDLE,
        1,
        4,
        8,
        NR_REDCAP_MEASUREMENT_COUNT_DRX,
        1280000,
        640000,
        0,
        10240000,
    )
    var fr2_2560 = nr_redcap_rel17_idle_serving_measurement_schedule(
        NR_REDCAP_MEASUREMENT_FR2, 2, 40000, 2560000
    )
    _assert_schedule(
        fr2_2560,
        NR_REDCAP_MEASUREMENT_STATE_IDLE,
        1,
        3,
        6,
        NR_REDCAP_MEASUREMENT_COUNT_DRX,
        2560000,
        1280000,
        0,
        15360000,
    )


def test_idle_edrx_static_clause_tables() raises:
    # Tables 4.2B.2.2-2/-3 short-eDRX rows count eDRX cycles.
    for index in range(3):
        var edrx_us = _literal_short_edrx_cycle_us(index)
        var fr1 = nr_redcap_rel17_idle_serving_measurement_schedule(
            NR_REDCAP_MEASUREMENT_FR1,
            1,
            40000,
            0,
            edrx_idle_cycle_us=edrx_us,
        )
        _assert_schedule(
            fr1,
            NR_REDCAP_MEASUREMENT_STATE_IDLE,
            1,
            1,
            2,
            NR_REDCAP_MEASUREMENT_COUNT_EDRX,
            edrx_us,
            edrx_us // 2,
            0,
            edrx_us * 2,
        )
        var fr2 = nr_redcap_rel17_idle_serving_measurement_schedule(
            NR_REDCAP_MEASUREMENT_FR2,
            2,
            40000,
            0,
            edrx_idle_cycle_us=edrx_us,
        )
        _assert_schedule(
            fr2,
            NR_REDCAP_MEASUREMENT_STATE_IDLE,
            1,
            3,
            6,
            NR_REDCAP_MEASUREMENT_COUNT_EDRX,
            edrx_us,
            edrx_us // 2,
            0,
            edrx_us * 6,
        )

    # Long-eDRX rows: every expected Nserv/PTW value is a literal table row.
    var fr1_320 = nr_redcap_rel17_idle_serving_measurement_schedule(
        NR_REDCAP_MEASUREMENT_FR1,
        1,
        40000,
        320000,
        edrx_idle_cycle_us=20480000,
    )
    _assert_schedule(
        fr1_320,
        NR_REDCAP_MEASUREMENT_STATE_IDLE,
        2,
        1,
        4,
        NR_REDCAP_MEASUREMENT_COUNT_DRX,
        320000,
        160000,
        1280000,
        1280000,
    )
    var fr1_640 = nr_redcap_rel17_idle_serving_measurement_schedule(
        NR_REDCAP_MEASUREMENT_FR1,
        2,
        40000,
        640000,
        edrx_idle_cycle_us=20480000,
    )
    _assert_schedule(
        fr1_640,
        NR_REDCAP_MEASUREMENT_STATE_IDLE,
        2,
        1,
        4,
        NR_REDCAP_MEASUREMENT_COUNT_DRX,
        640000,
        320000,
        2560000,
        2560000,
    )
    var fr1_1280 = nr_redcap_rel17_idle_serving_measurement_schedule(
        NR_REDCAP_MEASUREMENT_FR1,
        1,
        40000,
        1280000,
        edrx_idle_cycle_us=20480000,
    )
    _assert_schedule(
        fr1_1280,
        NR_REDCAP_MEASUREMENT_STATE_IDLE,
        1,
        1,
        2,
        NR_REDCAP_MEASUREMENT_COUNT_DRX,
        1280000,
        640000,
        2560000,
        2560000,
    )
    var fr1_2560 = nr_redcap_rel17_idle_serving_measurement_schedule(
        NR_REDCAP_MEASUREMENT_FR1,
        2,
        40000,
        2560000,
        edrx_idle_cycle_us=20480000,
    )
    _assert_schedule(
        fr1_2560,
        NR_REDCAP_MEASUREMENT_STATE_IDLE,
        1,
        1,
        2,
        NR_REDCAP_MEASUREMENT_COUNT_DRX,
        2560000,
        1280000,
        5120000,
        5120000,
    )

    var fr2_320 = nr_redcap_rel17_idle_serving_measurement_schedule(
        NR_REDCAP_MEASUREMENT_FR2,
        2,
        40000,
        320000,
        edrx_idle_cycle_us=20480000,
    )
    _assert_schedule(
        fr2_320,
        NR_REDCAP_MEASUREMENT_STATE_IDLE,
        2,
        8,
        16,
        NR_REDCAP_MEASUREMENT_COUNT_DRX,
        320000,
        160000,
        5120000,
        5120000,
    )
    var fr2_640 = nr_redcap_rel17_idle_serving_measurement_schedule(
        NR_REDCAP_MEASUREMENT_FR2,
        2,
        40000,
        640000,
        edrx_idle_cycle_us=20480000,
    )
    _assert_schedule(
        fr2_640,
        NR_REDCAP_MEASUREMENT_STATE_IDLE,
        2,
        5,
        10,
        NR_REDCAP_MEASUREMENT_COUNT_DRX,
        640000,
        320000,
        6400000,
        6400000,
    )
    var fr2_1280 = nr_redcap_rel17_idle_serving_measurement_schedule(
        NR_REDCAP_MEASUREMENT_FR2,
        2,
        40000,
        1280000,
        edrx_idle_cycle_us=20480000,
    )
    _assert_schedule(
        fr2_1280,
        NR_REDCAP_MEASUREMENT_STATE_IDLE,
        1,
        4,
        8,
        NR_REDCAP_MEASUREMENT_COUNT_DRX,
        1280000,
        640000,
        10240000,
        10240000,
    )
    var fr2_2560 = nr_redcap_rel17_idle_serving_measurement_schedule(
        NR_REDCAP_MEASUREMENT_FR2,
        2,
        40000,
        2560000,
        edrx_idle_cycle_us=10485760000,
    )
    _assert_schedule(
        fr2_2560,
        NR_REDCAP_MEASUREMENT_STATE_IDLE,
        1,
        3,
        6,
        NR_REDCAP_MEASUREMENT_COUNT_DRX,
        2560000,
        1280000,
        15360000,
        15360000,
    )


def test_inactive_static_clause_table() raises:
    # Tables 5.1B.2.2-1/-2, exhaustive over all six effective-T rows.
    for index in range(6):
        var effective_t_us = _literal_inactive_t_us(index)
        var expected_m1 = 2 if index < 2 else 1
        var expected_fr1_nserv = 8 if index < 2 else 2
        var fr1 = nr_redcap_rel17_inactive_serving_measurement_schedule(
            NR_REDCAP_MEASUREMENT_FR1,
            1,
            40000,
            2560000,
            effective_t_us,
        )
        _assert_schedule(
            fr1,
            NR_REDCAP_MEASUREMENT_STATE_INACTIVE,
            expected_m1,
            1,
            expected_fr1_nserv,
            NR_REDCAP_MEASUREMENT_COUNT_EFFECTIVE_T,
            effective_t_us,
            effective_t_us // 2,
            0,
            effective_t_us * expected_fr1_nserv,
        )

        var expected_n1 = _literal_fr2_n1(index)
        var expected_fr2_nserv = (
            expected_n1 * 4 if index < 2 else expected_n1 * 2
        )
        var fr2 = nr_redcap_rel17_inactive_serving_measurement_schedule(
            NR_REDCAP_MEASUREMENT_FR2,
            2,
            40000,
            10485760000,
            effective_t_us,
        )
        _assert_schedule(
            fr2,
            NR_REDCAP_MEASUREMENT_STATE_INACTIVE,
            expected_m1,
            expected_n1,
            expected_fr2_nserv,
            NR_REDCAP_MEASUREMENT_COUNT_EFFECTIVE_T,
            effective_t_us,
            effective_t_us // 2,
            0,
            effective_t_us * expected_fr2_nserv,
        )


def test_exact_m1_ptw_and_failure_threshold_boundaries() raises:
    # Exact SMTC boundary: the clause says greater than, not greater/equal.
    var at_20_ms = nr_redcap_rel17_idle_serving_measurement_schedule(
        NR_REDCAP_MEASUREMENT_FR1,
        1,
        20000,
        640000,
        edrx_idle_cycle_us=20480000,
    )
    assert_equal(at_20_ms.m1, 1)
    assert_equal(at_20_ms.nserv, 2)
    assert_equal(at_20_ms.minimum_ptw_us, 1280000)

    var above_20_ms = nr_redcap_rel17_idle_serving_measurement_schedule(
        NR_REDCAP_MEASUREMENT_FR1,
        1,
        40000,
        640000,
        edrx_idle_cycle_us=20480000,
    )
    assert_equal(above_20_ms.m1, 2)
    assert_equal(above_20_ms.nserv, 4)
    assert_equal(above_20_ms.minimum_ptw_us, 2560000)

    assert_equal(
        nr_redcap_rel17_all_neighbour_measurements_required(
            above_20_ms, above_20_ms.nserv - 1
        ),
        False,
    )
    assert_equal(
        nr_redcap_rel17_all_neighbour_measurements_required(
            above_20_ms, above_20_ms.nserv
        ),
        True,
    )
    assert_equal(
        nr_redcap_rel17_all_neighbour_measurements_required(
            above_20_ms, Int.MAX
        ),
        True,
    )


def test_seeded_schedule_properties_and_independent_literal_oracle() raises:
    # Seeded row selection compares production output with independent literal
    # table arrays.  The loop also checks 1Rx/2Rx invariance in FR1.
    var state = UInt64(0x9E3779B97F4A7C15)
    for iteration in range(512):
        state = state * UInt64(6364136223846793005) + UInt64(1)
        var index = Int((state >> 32) & UInt64(3))
        var drx_us = _literal_drx_cycle_us(index)
        var expected_m1 = 2 if index < 2 else 1
        var expected_n1 = _literal_fr2_n1(index)
        var expected_nserv = (
            expected_m1 * expected_n1 * 4
            if index < 2
            else expected_n1 * 2
        )
        var schedule = nr_redcap_rel17_idle_serving_measurement_schedule(
            NR_REDCAP_MEASUREMENT_FR2, 2, 40000, drx_us
        )
        assert_equal(schedule.m1, expected_m1)
        assert_equal(schedule.n1, expected_n1)
        assert_equal(schedule.nserv, expected_nserv)
        assert_equal(schedule.minimum_filter_spacing_us * 2, drx_us)
        assert_equal(schedule.failure_window_us, expected_nserv * drx_us)
        var failures = (iteration + Int(state & UInt64(31))) % 65
        assert_equal(
            nr_redcap_rel17_all_neighbour_measurements_required(
                schedule, failures
            ),
            failures >= expected_nserv,
        )

        var rx_branches = 1 if ((state >> 8) & UInt64(1)) == 0 else 2
        var capability = nr_redcap_rel17_measurement_capability(
            NR_REDCAP_MEASUREMENT_FR1, rx_branches
        )
        assert_equal(capability.rx_branches, rx_branches)
        assert_equal(
            capability.minimum_total_frequency_layers,
            11 if rx_branches == 1 else 14,
        )
        var fr1 = nr_redcap_rel17_idle_serving_measurement_schedule(
            NR_REDCAP_MEASUREMENT_FR1,
            rx_branches,
            40000,
            drx_us,
        )
        assert_equal(fr1.n1, 1)
        assert_equal(
            fr1.nserv, expected_m1 * 4 if index < 2 else 2
        )
        assert_equal(fr1.rx_branches, rx_branches)

        var inactive_index = Int((state >> 40) % UInt64(6))
        var effective_t_us = _literal_inactive_t_us(inactive_index)
        var inactive_n1 = _literal_fr2_n1(inactive_index)
        var inactive_nserv = (
            inactive_n1 * 4 if inactive_index < 2 else inactive_n1 * 2
        )
        var inactive = (
            nr_redcap_rel17_inactive_serving_measurement_schedule(
                NR_REDCAP_MEASUREMENT_FR2,
                2,
                40000,
                2560000,
                effective_t_us,
            )
        )
        assert_equal(inactive.n1, inactive_n1)
        assert_equal(inactive.nserv, inactive_nserv)
        assert_equal(
            inactive.failure_window_us, inactive_nserv * effective_t_us
        )


def test_public_profile_geometry_and_mutation_edges() raises:
    with assert_raises():
        _ = nr_redcap_rel17_measurement_capability(0, 1)
    with assert_raises():
        _ = nr_redcap_rel17_measurement_capability(
            NR_REDCAP_MEASUREMENT_FR1, 0
        )
    with assert_raises():
        _ = nr_redcap_rel17_measurement_capability(
            NR_REDCAP_MEASUREMENT_FR2, 1
        )
    with assert_raises():
        _ = nr_redcap_rel17_measurement_capability(
            NR_REDCAP_MEASUREMENT_FR1,
            1,
            profile=NR_REDCAP_MEASUREMENT_PROFILE_ORDINARY_NR,
        )
    with assert_raises():
        _ = nr_redcap_rel17_measurement_capability(
            NR_REDCAP_MEASUREMENT_FR1,
            1,
            profile=NR_REDCAP_MEASUREMENT_PROFILE_EREDCAP_REL18,
        )

    with assert_raises():
        _ = nr_redcap_rel17_idle_serving_measurement_schedule(
            NR_REDCAP_MEASUREMENT_FR1, 1, 30000, 320000
        )
    with assert_raises():
        _ = nr_redcap_rel17_idle_serving_measurement_schedule(
            NR_REDCAP_MEASUREMENT_FR1, 1, 40000, 319999
        )
    with assert_raises():
        _ = nr_redcap_rel17_idle_serving_measurement_schedule(
            NR_REDCAP_MEASUREMENT_FR1,
            1,
            40000,
            320000,
            edrx_idle_cycle_us=2560000,
        )
    with assert_raises():
        _ = nr_redcap_rel17_idle_serving_measurement_schedule(
            NR_REDCAP_MEASUREMENT_FR1,
            1,
            40000,
            0,
            edrx_idle_cycle_us=10240001,
        )
    with assert_raises():
        _ = nr_redcap_rel17_idle_serving_measurement_schedule(
            NR_REDCAP_MEASUREMENT_FR1,
            1,
            40000,
            320000,
            edrx_idle_cycle_us=10485760001,
        )
    with assert_raises():
        _ = nr_redcap_rel17_idle_serving_measurement_schedule(
            NR_REDCAP_MEASUREMENT_FR2, 1, 40000, 320000
        )
    with assert_raises():
        _ = nr_redcap_rel17_idle_serving_measurement_schedule(
            NR_REDCAP_MEASUREMENT_FR1,
            1,
            40000,
            320000,
            profile=NR_REDCAP_MEASUREMENT_PROFILE_EREDCAP_REL18,
        )

    with assert_raises():
        _ = nr_redcap_rel17_inactive_serving_measurement_schedule(
            NR_REDCAP_MEASUREMENT_FR1, 1, 40000, 2559999, 320000
        )
    with assert_raises():
        _ = nr_redcap_rel17_inactive_serving_measurement_schedule(
            NR_REDCAP_MEASUREMENT_FR1,
            1,
            40000,
            10485760001,
            320000,
        )
    with assert_raises():
        _ = nr_redcap_rel17_inactive_serving_measurement_schedule(
            NR_REDCAP_MEASUREMENT_FR1, 1, 40000, 2560000, 1000000
        )

    var capability = nr_redcap_rel17_measurement_capability(
        NR_REDCAP_MEASUREMENT_FR1, 1
    )
    capability.minimum_total_frequency_layers = 12
    with assert_raises():
        capability.validate()

    var schedule = nr_redcap_rel17_idle_serving_measurement_schedule(
        NR_REDCAP_MEASUREMENT_FR1, 1, 40000, 320000
    )
    schedule.nserv += 1
    with assert_raises():
        schedule.validate()
    with assert_raises():
        _ = nr_redcap_rel17_all_neighbour_measurements_required(schedule, 8)

    var valid = nr_redcap_rel17_idle_serving_measurement_schedule(
        NR_REDCAP_MEASUREMENT_FR1, 1, 40000, 320000
    )
    with assert_raises():
        _ = nr_redcap_rel17_all_neighbour_measurements_required(valid, -1)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
