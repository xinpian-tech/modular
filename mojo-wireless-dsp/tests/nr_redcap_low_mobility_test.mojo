"""Exact static, edge, property, and transition evidence for RedCap K1/K4.

Literal expectations are independently transcribed from 3GPP TS 38.133
V17.22.0 Tables 4.2B.2.9.9-1..4, 4.2B.2.10.9-1..4,
4.2B.2.11.9-1..2, and 5.1B.2.9-1..2, 5.1B.2.10-1..2,
5.1B.2.11-1.  They do not call production derivation helpers.
"""

from std.testing import assert_equal, assert_raises, TestSuite
from std.utils.numerics import inf, nan
from wireless_dsp.wireless.nr.redcap_low_mobility import (
    NR_REDCAP_LOW_MOBILITY_PROFILE_ORDINARY_NR,
    NR_REDCAP_LOW_MOBILITY_PROFILE_REDCAP_REL17,
    NR_REDCAP_LOW_MOBILITY_PROFILE_EREDCAP_REL18,
    NR_REDCAP_LOW_MOBILITY_FR1,
    NR_REDCAP_LOW_MOBILITY_FR2,
    NR_REDCAP_RELAXED_FAMILY_INTRA_NR,
    NR_REDCAP_RELAXED_FAMILY_INTER_NR,
    NR_REDCAP_RELAXED_FAMILY_EUTRA,
    NR_REDCAP_RELAXED_CRITERION_LOW_MOBILITY,
    NR_REDCAP_RELAXED_CRITERION_NOT_AT_CELL_EDGE,
    NR_REDCAP_LOW_MOBILITY_COMBINE_REQUIRE_BOTH,
    NR_REDCAP_LOW_MOBILITY_COMBINE_ALLOW_EITHER,
    NR_REDCAP_RELAXED_STATE_IDLE,
    NR_REDCAP_RELAXED_STATE_INACTIVE,
    NR_REDCAP_RELAXED_COUNT_DRX,
    NR_REDCAP_RELAXED_COUNT_EDRX_IDLE,
    NR_REDCAP_RELAXED_COUNT_EFFECTIVE_T,
    NR_REDCAP_SCENARIO_NORMAL,
    NR_REDCAP_SCENARIO_LOW_MOBILITY,
    NR_REDCAP_SCENARIO_STATIONARY,
    NR_REDCAP_SCENARIO_STATIONARY_NOT_AT_CELL_EDGE,
    NR_REDCAP_LOW_MOBILITY_K1,
    NR_REDCAP_LOW_MOBILITY_K4,
    NR_REDCAP_LOW_MOBILITY_HIGH_PRIORITY_K2,
    NR_REDCAP_LOW_MOBILITY_CELL_EDGE_NO_MEASUREMENT_LIMIT_US,
    NRRedCapLowMobilityState,
    NRRedCapLowMobilityCellEdgeTiming,
    NRRedCapMeasurementScenarioState,
    NRRedCapTimingRequirementTransitionState,
    nr_redcap_rel17_low_mobility_delta_met,
    nr_redcap_rel17_low_mobility_update,
    nr_redcap_rel17_not_at_cell_edge_met,
    nr_redcap_rel17_combine_low_mobility_cell_edge_conditions,
    nr_redcap_rel17_low_mobility_cell_edge_no_measurement_allowed,
    nr_redcap_rel17_low_mobility_high_priority_search_interval_us,
    nr_redcap_rel17_idle_low_mobility_or_cell_edge_timing,
    nr_redcap_rel17_inactive_low_mobility_or_cell_edge_timing,
    nr_redcap_rel17_start_measurement_scenario_transition,
    nr_redcap_rel17_measurement_scenario_update,
    nr_redcap_rel17_timing_requirement_transition_update,
)


def _literal_cycle_us(index: Int) -> Int:
    if index == 0:
        return 320000
    if index == 1:
        return 640000
    if index == 2:
        return 1280000
    if index == 3:
        return 2560000
    if index == 4:
        return 5120000
    return 10240000


def _literal_base_detect(index: Int) -> Int:
    if index == 0:
        return 36
    if index == 1:
        return 28
    if index == 2:
        return 25
    return 23


def _literal_base_measure(index: Int) -> Int:
    if index == 0:
        return 4
    if index == 1:
        return 2
    return 1


def _literal_base_evaluate(index: Int) -> Int:
    if index == 0:
        return 16
    if index == 1:
        return 8
    if index == 2:
        return 5
    return 3


def _literal_fr2_n1(index: Int) -> Int:
    if index == 0:
        return 8
    if index == 1:
        return 5
    if index == 2:
        return 4
    return 3


def _assert_timing(
    timing: NRRedCapLowMobilityCellEdgeTiming,
    expected_state: Int,
    expected_n1: Int,
    expected_m2_numerator: Int,
    expected_factor: Int,
    expected_unit: Int,
    expected_cycle_us: Int,
    expected_detect_cycles: Int,
    expected_measure_cycles: Int,
    expected_evaluate_cycles: Int,
) raises:
    timing.validate()
    assert_equal(timing.rrc_state, expected_state)
    assert_equal(timing.n1, expected_n1)
    assert_equal(timing.m2_numerator, expected_m2_numerator)
    assert_equal(timing.relaxation_factor, expected_factor)
    assert_equal(timing.count_unit, expected_unit)
    assert_equal(timing.count_cycle_us, expected_cycle_us)
    assert_equal(timing.detect_cycles, expected_detect_cycles)
    assert_equal(timing.measure_cycles, expected_measure_cycles)
    assert_equal(timing.evaluate_cycles, expected_evaluate_cycles)
    assert_equal(timing.detect_us, expected_detect_cycles * expected_cycle_us)
    assert_equal(
        timing.measure_us, expected_measure_cycles * expected_cycle_us
    )
    assert_equal(
        timing.evaluate_us, expected_evaluate_cycles * expected_cycle_us
    )


def test_low_mobility_reference_and_combined_static_clause_trace() raises:
    # Literal 38.304 5.2.4.9.0/.1 trace, with strict 3 dB and 10 s edges.
    var state = NRRedCapLowMobilityState(-80.0, 0)
    assert_equal(
        nr_redcap_rel17_low_mobility_update(
            state, -82.999, 9999999, 10000000, 3.0
        ),
        False,
    )
    assert_equal(
        nr_redcap_rel17_low_mobility_update(
            state, -82.999, 10000000, 10000000, 3.0
        ),
        True,
    )

    # Equality is not low mobility.  The reference resets only when the
    # continuously-unmet timer reaches its exact endpoint.
    assert_equal(
        nr_redcap_rel17_low_mobility_update(
            state, -83.0, 10000000, 10000000, 3.0
        ),
        False,
    )
    assert_equal(state.reference_srxlev_db, -80.0)
    assert_equal(
        nr_redcap_rel17_low_mobility_update(
            state, -83.0, 19999999, 10000000, 3.0
        ),
        False,
    )
    assert_equal(state.reference_srxlev_db, -80.0)
    assert_equal(
        nr_redcap_rel17_low_mobility_update(
            state, -83.0, 20000000, 10000000, 3.0
        ),
        False,
    )
    assert_equal(state.reference_srxlev_db, -83.0)
    assert_equal(state.criterion_met_since_us, 20000000)

    # A strict improvement resets the reference.  Cell reselection resets the
    # reference and both readiness dwell origins.
    assert_equal(
        nr_redcap_rel17_low_mobility_update(
            state, -82.0, 21000000, 10000000, 3.0
        ),
        False,
    )
    assert_equal(state.reference_srxlev_db, -82.0)
    assert_equal(
        nr_redcap_rel17_low_mobility_update(
            state,
            -70.0,
            22000000,
            10000000,
            3.0,
            cell_selected_or_reselected=True,
        ),
        False,
    )
    assert_equal(state.reference_srxlev_db, -70.0)
    assert_equal(state.cell_selected_at_us, 22000000)

    assert_equal(
        nr_redcap_rel17_low_mobility_delta_met(-80.0, -82.999, 3.0), True
    )
    assert_equal(
        nr_redcap_rel17_low_mobility_delta_met(-80.0, -83.0, 3.0), False
    )

    # Literal strict P/Q boundaries from 5.2.4.9.2.
    assert_equal(
        nr_redcap_rel17_not_at_cell_edge_met(
            -70.0, -4.0, -70.0, -5.0
        ),
        False,
    )
    assert_equal(
        nr_redcap_rel17_not_at_cell_edge_met(
            -69.0, -5.0, -70.0, -5.0
        ),
        False,
    )
    assert_equal(
        nr_redcap_rel17_not_at_cell_edge_met(
            -69.0, -4.0, -70.0, -5.0
        ),
        True,
    )
    assert_equal(
        nr_redcap_rel17_not_at_cell_edge_met(
            -69.0,
            -100.0,
            -70.0,
            -5.0,
            s_search_threshold_q_configured=False,
        ),
        True,
    )

    # Complete Boolean-domain combineRelaxedMeasCondition truth table.
    for low in range(2):
        for edge in range(2):
            var low_ready = low == 1
            var edge_ready = edge == 1
            assert_equal(
                nr_redcap_rel17_combine_low_mobility_cell_edge_conditions(
                    low_ready,
                    edge_ready,
                    NR_REDCAP_LOW_MOBILITY_COMBINE_REQUIRE_BOTH,
                ),
                low_ready and edge_ready,
            )
            assert_equal(
                nr_redcap_rel17_combine_low_mobility_cell_edge_conditions(
                    low_ready,
                    edge_ready,
                    NR_REDCAP_LOW_MOBILITY_COMBINE_ALLOW_EITHER,
                ),
                low_ready or edge_ready,
            )

    assert_equal(
        nr_redcap_rel17_low_mobility_cell_edge_no_measurement_allowed(
            True,
            True,
            NR_REDCAP_LOW_MOBILITY_CELL_EDGE_NO_MEASUREMENT_LIMIT_US - 1,
        ),
        True,
    )
    assert_equal(
        nr_redcap_rel17_low_mobility_cell_edge_no_measurement_allowed(
            True,
            True,
            NR_REDCAP_LOW_MOBILITY_CELL_EDGE_NO_MEASUREMENT_LIMIT_US,
        ),
        False,
    )
    assert_equal(
        nr_redcap_rel17_low_mobility_high_priority_search_interval_us(
            1000000,
            high_priority_meas_relax_configured=True,
            low_mobility_ready=True,
            serving_above_non_intra_thresholds=True,
        ),
        60000000,
    )
    assert_equal(
        nr_redcap_rel17_low_mobility_high_priority_search_interval_us(
            1000000,
            high_priority_meas_relax_configured=False,
            low_mobility_ready=True,
            serving_above_non_intra_thresholds=True,
        ),
        1000000,
    )


def test_idle_k1_drx_and_short_edrx_static_tables() raises:
    # Exhaust every K1 row for both criteria, all three families, 1/2 Rx FR1,
    # and the applicable 2 Rx FR2 geometry.  SMTC=40 ms activates M2=1.5 in
    # the 320 ms NR rows.  E-UTRA has no M2 in the idle tables.
    for criterion in range(2):
        for family in range(3):
            var maximum_geometry = 3 if family != 2 else 2
            for geometry in range(maximum_geometry):
                var frequency_range = (
                    NR_REDCAP_LOW_MOBILITY_FR2
                    if geometry == 2
                    else NR_REDCAP_LOW_MOBILITY_FR1
                )
                var rx_branches = 2 if geometry != 0 else 1
                var smtc_us = 0 if family == 2 else 40000

                for index in range(4):
                    var cycle_us = _literal_cycle_us(index)
                    var n1 = (
                        _literal_fr2_n1(index)
                        if frequency_range == NR_REDCAP_LOW_MOBILITY_FR2
                        else 1
                    )
                    var m2_numerator = (
                        3 if index == 0 and family != 2 else 2
                    )
                    var detect = (
                        _literal_base_detect(index)
                        * n1
                        * NR_REDCAP_LOW_MOBILITY_K1
                        * m2_numerator
                        // 2
                    )
                    var measure = (
                        _literal_base_measure(index)
                        * n1
                        * NR_REDCAP_LOW_MOBILITY_K1
                        * m2_numerator
                        // 2
                    )
                    var evaluate = (
                        _literal_base_evaluate(index)
                        * n1
                        * NR_REDCAP_LOW_MOBILITY_K1
                        * m2_numerator
                        // 2
                    )
                    var timing = (
                        nr_redcap_rel17_idle_low_mobility_or_cell_edge_timing(
                            family,
                            criterion,
                            frequency_range,
                            rx_branches,
                            smtc_us,
                            cycle_us,
                        )
                    )
                    _assert_timing(
                        timing,
                        NR_REDCAP_RELAXED_STATE_IDLE,
                        n1,
                        m2_numerator,
                        NR_REDCAP_LOW_MOBILITY_K1,
                        NR_REDCAP_RELAXED_COUNT_DRX,
                        cycle_us,
                        detect,
                        measure,
                        evaluate,
                    )

                for short_index in range(3):
                    var index = short_index + 3
                    var cycle_us = _literal_cycle_us(index)
                    var n1 = (
                        3
                        if frequency_range == NR_REDCAP_LOW_MOBILITY_FR2
                        else 1
                    )
                    var timing = (
                        nr_redcap_rel17_idle_low_mobility_or_cell_edge_timing(
                            family,
                            criterion,
                            frequency_range,
                            rx_branches,
                            smtc_us,
                            0,
                            edrx_idle_cycle_us=cycle_us,
                        )
                    )
                    _assert_timing(
                        timing,
                        NR_REDCAP_RELAXED_STATE_IDLE,
                        n1,
                        2,
                        NR_REDCAP_LOW_MOBILITY_K1,
                        NR_REDCAP_RELAXED_COUNT_EDRX_IDLE,
                        cycle_us,
                        23 * n1 * NR_REDCAP_LOW_MOBILITY_K1,
                        n1 * NR_REDCAP_LOW_MOBILITY_K1,
                        (3 if short_index == 0 else 2)
                        * n1
                        * NR_REDCAP_LOW_MOBILITY_K1,
                    )


def test_inactive_k4_effective_t_static_tables() raises:
    # Exhaust all six effective-T rows for low-mobility and cell-edge K4=3.
    for criterion in range(2):
        for family in range(3):
            var maximum_geometry = 3 if family != 2 else 2
            for geometry in range(maximum_geometry):
                var frequency_range = (
                    NR_REDCAP_LOW_MOBILITY_FR2
                    if geometry == 2
                    else NR_REDCAP_LOW_MOBILITY_FR1
                )
                var rx_branches = 2 if geometry != 0 else 1
                for index in range(6):
                    var effective_t_us = _literal_cycle_us(index)
                    var n1 = (
                        _literal_fr2_n1(index)
                        if frequency_range == NR_REDCAP_LOW_MOBILITY_FR2
                        else 1
                    )
                    var m2_numerator = 3 if index == 0 else 2
                    var detect = (
                        _literal_base_detect(index)
                        * n1
                        * NR_REDCAP_LOW_MOBILITY_K4
                        * m2_numerator
                        // 2
                    )
                    var measure = (
                        _literal_base_measure(index)
                        * n1
                        * NR_REDCAP_LOW_MOBILITY_K4
                        * m2_numerator
                        // 2
                    )
                    var evaluate = (
                        _literal_base_evaluate(index)
                        * n1
                        * NR_REDCAP_LOW_MOBILITY_K4
                        * m2_numerator
                        // 2
                    )
                    var timing = (
                        nr_redcap_rel17_inactive_low_mobility_or_cell_edge_timing(
                            family,
                            criterion,
                            frequency_range,
                            rx_branches,
                            40000,
                            20480000,
                            effective_t_us,
                        )
                    )
                    _assert_timing(
                        timing,
                        NR_REDCAP_RELAXED_STATE_INACTIVE,
                        n1,
                        m2_numerator,
                        NR_REDCAP_LOW_MOBILITY_K4,
                        NR_REDCAP_RELAXED_COUNT_EFFECTIVE_T,
                        effective_t_us,
                        detect,
                        measure,
                        evaluate,
                    )


def test_scenario_and_timing_transition_exact_boundaries() raises:
    var scenario = NRRedCapMeasurementScenarioState(
        NR_REDCAP_SCENARIO_NORMAL, 0
    )
    assert_equal(
        nr_redcap_rel17_start_measurement_scenario_transition(
            scenario,
            NR_REDCAP_SCENARIO_LOW_MOBILITY,
            0,
            selected_tnormal_us=100,
        ),
        NR_REDCAP_SCENARIO_NORMAL,
    )
    assert_equal(
        nr_redcap_rel17_measurement_scenario_update(scenario, 99),
        NR_REDCAP_SCENARIO_NORMAL,
    )
    assert_equal(
        nr_redcap_rel17_measurement_scenario_update(scenario, 100),
        NR_REDCAP_SCENARIO_LOW_MOBILITY,
    )

    assert_equal(
        nr_redcap_rel17_start_measurement_scenario_transition(
            scenario,
            NR_REDCAP_SCENARIO_STATIONARY_NOT_AT_CELL_EDGE,
            100,
            selected_trelaxed_us=80,
        ),
        NR_REDCAP_SCENARIO_LOW_MOBILITY,
    )
    assert_equal(
        nr_redcap_rel17_measurement_scenario_update(scenario, 179),
        NR_REDCAP_SCENARIO_LOW_MOBILITY,
    )
    assert_equal(
        nr_redcap_rel17_measurement_scenario_update(scenario, 180),
        NR_REDCAP_SCENARIO_STATIONARY_NOT_AT_CELL_EDGE,
    )
    assert_equal(
        nr_redcap_rel17_start_measurement_scenario_transition(
            scenario, NR_REDCAP_SCENARIO_LOW_MOBILITY, 180
        ),
        NR_REDCAP_SCENARIO_LOW_MOBILITY,
    )
    assert_equal(
        nr_redcap_rel17_start_measurement_scenario_transition(
            scenario, NR_REDCAP_SCENARIO_NORMAL, 181
        ),
        NR_REDCAP_SCENARIO_NORMAL,
    )

    # Configuration transition uses max(first, second) until exact expiry.
    var to_stricter = NRRedCapTimingRequirementTransitionState(300, 100, 10)
    assert_equal(to_stricter.transition_requirement_us, 300)
    assert_equal(
        nr_redcap_rel17_timing_requirement_transition_update(
            to_stricter, 309
        ),
        300,
    )
    assert_equal(
        nr_redcap_rel17_timing_requirement_transition_update(
            to_stricter, 310
        ),
        100,
    )

    var to_looser = NRRedCapTimingRequirementTransitionState(100, 300, 20)
    assert_equal(
        nr_redcap_rel17_timing_requirement_transition_update(to_looser, 319),
        300,
    )
    assert_equal(
        nr_redcap_rel17_timing_requirement_transition_update(to_looser, 320),
        300,
    )


def test_low_mobility_public_edges_mutation_nan_inf_overflow() raises:
    with assert_raises():
        _ = NRRedCapLowMobilityState(
            -80.0,
            0,
            profile=NR_REDCAP_LOW_MOBILITY_PROFILE_ORDINARY_NR,
        )
    with assert_raises():
        _ = NRRedCapLowMobilityState(
            -80.0,
            0,
            profile=NR_REDCAP_LOW_MOBILITY_PROFILE_EREDCAP_REL18,
        )
    with assert_raises():
        _ = NRRedCapLowMobilityState(nan[DType.float64](), 0)
    with assert_raises():
        _ = NRRedCapLowMobilityState(-80.0, -1)
    with assert_raises():
        _ = nr_redcap_rel17_low_mobility_delta_met(
            inf[DType.float64](), -80.0, 3.0
        )
    with assert_raises():
        _ = nr_redcap_rel17_low_mobility_delta_met(-80.0, -81.0, 0.0)

    var state = NRRedCapLowMobilityState(-80.0, 10)
    with assert_raises():
        _ = nr_redcap_rel17_low_mobility_update(
            state, -80.0, 9, 1, 3.0
        )
    with assert_raises():
        _ = nr_redcap_rel17_low_mobility_update(
            state, -80.0, 10, 0, 3.0
        )
    with assert_raises():
        _ = nr_redcap_rel17_low_mobility_update(
            state, nan[DType.float64](), 10, 1, 3.0
        )
    state.criterion_met_since_us = -1
    state.criterion_unmet_since_us = -1
    with assert_raises():
        state.validate()

    with assert_raises():
        _ = nr_redcap_rel17_not_at_cell_edge_met(
            -69.0, inf[DType.float64](), -70.0, -5.0
        )
    with assert_raises():
        _ = nr_redcap_rel17_combine_low_mobility_cell_edge_conditions(
            True, True, 9
        )
    with assert_raises():
        _ = nr_redcap_rel17_low_mobility_cell_edge_no_measurement_allowed(
            True, True, -1
        )
    assert_equal(
        nr_redcap_rel17_low_mobility_cell_edge_no_measurement_allowed(
            True, True, Int.MAX
        ),
        False,
    )
    with assert_raises():
        _ = nr_redcap_rel17_low_mobility_high_priority_search_interval_us(
            1,
            high_priority_meas_relax_configured=True,
            low_mobility_ready=False,
            serving_above_non_intra_thresholds=True,
        )
    with assert_raises():
        _ = nr_redcap_rel17_low_mobility_high_priority_search_interval_us(
            Int.MAX // NR_REDCAP_LOW_MOBILITY_HIGH_PRIORITY_K2 + 1,
            high_priority_meas_relax_configured=True,
            low_mobility_ready=True,
            serving_above_non_intra_thresholds=True,
        )

    with assert_raises():
        _ = nr_redcap_rel17_idle_low_mobility_or_cell_edge_timing(
            9, 0, NR_REDCAP_LOW_MOBILITY_FR1, 1, 40000, 320000
        )
    with assert_raises():
        _ = nr_redcap_rel17_idle_low_mobility_or_cell_edge_timing(
            NR_REDCAP_RELAXED_FAMILY_INTRA_NR,
            9,
            NR_REDCAP_LOW_MOBILITY_FR1,
            1,
            40000,
            320000,
        )
    with assert_raises():
        _ = nr_redcap_rel17_idle_low_mobility_or_cell_edge_timing(
            NR_REDCAP_RELAXED_FAMILY_INTRA_NR,
            NR_REDCAP_RELAXED_CRITERION_LOW_MOBILITY,
            NR_REDCAP_LOW_MOBILITY_FR2,
            1,
            40000,
            320000,
        )
    with assert_raises():
        _ = nr_redcap_rel17_idle_low_mobility_or_cell_edge_timing(
            NR_REDCAP_RELAXED_FAMILY_EUTRA,
            NR_REDCAP_RELAXED_CRITERION_LOW_MOBILITY,
            NR_REDCAP_LOW_MOBILITY_FR2,
            2,
            0,
            320000,
        )
    with assert_raises():
        _ = nr_redcap_rel17_idle_low_mobility_or_cell_edge_timing(
            NR_REDCAP_RELAXED_FAMILY_INTER_NR,
            NR_REDCAP_RELAXED_CRITERION_LOW_MOBILITY,
            NR_REDCAP_LOW_MOBILITY_FR1,
            1,
            30000,
            320000,
        )
    with assert_raises():
        _ = nr_redcap_rel17_idle_low_mobility_or_cell_edge_timing(
            NR_REDCAP_RELAXED_FAMILY_INTRA_NR,
            NR_REDCAP_RELAXED_CRITERION_LOW_MOBILITY,
            NR_REDCAP_LOW_MOBILITY_FR1,
            1,
            40000,
            320000,
            edrx_idle_cycle_us=2560000,
        )
    with assert_raises():
        _ = nr_redcap_rel17_idle_low_mobility_or_cell_edge_timing(
            NR_REDCAP_RELAXED_FAMILY_INTRA_NR,
            NR_REDCAP_RELAXED_CRITERION_LOW_MOBILITY,
            NR_REDCAP_LOW_MOBILITY_FR1,
            1,
            40000,
            0,
            edrx_idle_cycle_us=20480000,
        )
    with assert_raises():
        _ = nr_redcap_rel17_inactive_low_mobility_or_cell_edge_timing(
            NR_REDCAP_RELAXED_FAMILY_INTRA_NR,
            NR_REDCAP_RELAXED_CRITERION_LOW_MOBILITY,
            NR_REDCAP_LOW_MOBILITY_FR1,
            1,
            40000,
            20479999,
            320000,
        )
    with assert_raises():
        _ = nr_redcap_rel17_inactive_low_mobility_or_cell_edge_timing(
            NR_REDCAP_RELAXED_FAMILY_INTRA_NR,
            NR_REDCAP_RELAXED_CRITERION_LOW_MOBILITY,
            NR_REDCAP_LOW_MOBILITY_FR1,
            1,
            40000,
            20480000,
            1000000,
        )

    var timing = nr_redcap_rel17_idle_low_mobility_or_cell_edge_timing(
        NR_REDCAP_RELAXED_FAMILY_INTRA_NR,
        NR_REDCAP_RELAXED_CRITERION_LOW_MOBILITY,
        NR_REDCAP_LOW_MOBILITY_FR1,
        1,
        40000,
        320000,
    )
    timing.detect_cycles += 1
    with assert_raises():
        timing.validate()

    var scenario = NRRedCapMeasurementScenarioState(
        NR_REDCAP_SCENARIO_NORMAL, 0
    )
    with assert_raises():
        _ = nr_redcap_rel17_start_measurement_scenario_transition(
            scenario,
            NR_REDCAP_SCENARIO_LOW_MOBILITY,
            0,
            selected_tnormal_us=0,
        )
    _ = nr_redcap_rel17_start_measurement_scenario_transition(
        scenario,
        NR_REDCAP_SCENARIO_STATIONARY,
        0,
        selected_tnormal_us=10,
    )
    with assert_raises():
        _ = nr_redcap_rel17_start_measurement_scenario_transition(
            scenario,
            NR_REDCAP_SCENARIO_LOW_MOBILITY,
            9,
        )
    with assert_raises():
        _ = nr_redcap_rel17_measurement_scenario_update(scenario, -1)

    var undefined_pair = NRRedCapMeasurementScenarioState(
        NR_REDCAP_SCENARIO_STATIONARY, 0
    )
    with assert_raises():
        _ = nr_redcap_rel17_start_measurement_scenario_transition(
            undefined_pair,
            NR_REDCAP_SCENARIO_STATIONARY_NOT_AT_CELL_EDGE,
            0,
        )
    undefined_pair.current_scenario = 9
    with assert_raises():
        undefined_pair.validate()

    with assert_raises():
        _ = NRRedCapTimingRequirementTransitionState(0, 1, 0)
    with assert_raises():
        _ = NRRedCapTimingRequirementTransitionState(1, 1, -1)
    var transition = NRRedCapTimingRequirementTransitionState(10, 20, 0)
    with assert_raises():
        _ = nr_redcap_rel17_timing_requirement_transition_update(
            transition, -1
        )
    transition.transition_requirement_us = 21
    with assert_raises():
        transition.validate()

    # No signed addition is needed at Int.MAX; elapsed subtraction stays safe.
    var extreme_state = NRRedCapLowMobilityState(-80.0, Int.MAX)
    assert_equal(
        nr_redcap_rel17_low_mobility_update(
            extreme_state, -80.0, Int.MAX, 1, 3.0
        ),
        False,
    )
    var extreme_scenario = NRRedCapMeasurementScenarioState(
        NR_REDCAP_SCENARIO_NORMAL, Int.MAX
    )
    assert_equal(
        nr_redcap_rel17_start_measurement_scenario_transition(
            extreme_scenario,
            NR_REDCAP_SCENARIO_LOW_MOBILITY,
            Int.MAX,
            selected_tnormal_us=1,
        ),
        NR_REDCAP_SCENARIO_NORMAL,
    )


def test_seeded_low_mobility_state_and_transition_properties() raises:
    var random_state = UInt64(0xD1B54A32D192ED03)
    var state = NRRedCapLowMobilityState(-80.0, 0)
    var now_us = 0
    for iteration in range(512):
        random_state = (
            random_state * UInt64(6364136223846793005)
            + UInt64(1442695040888963407)
        )
        now_us += 1000
        var selector = Int((random_state >> 32) & UInt64(7))
        var current_srxlev = -80.0 - Float64(selector) * 0.5
        var expected_delta = (
            state.reference_srxlev_db - current_srxlev < 3.0
        )
        assert_equal(
            nr_redcap_rel17_low_mobility_delta_met(
                state.reference_srxlev_db, current_srxlev, 3.0
            ),
            expected_delta,
        )
        var cell_reset = iteration > 0 and iteration % 113 == 0
        var normal_active = iteration % 47 != 0
        var ready = nr_redcap_rel17_low_mobility_update(
            state,
            current_srxlev,
            now_us,
            5000,
            3.0,
            normal_measurements_active=normal_active,
            cell_selected_or_reselected=cell_reset,
        )
        state.validate()
        if ready:
            assert_equal(normal_active, True)
            assert_equal(state.criterion_unmet_since_us, -1)
            assert_equal(
                now_us - state.criterion_met_since_us >= 5000, True
            )
            assert_equal(
                now_us - state.normal_measurements_since_us >= 5000, True
            )

        var srxlev = -72.0 + Float64(Int(random_state & UInt64(7)))
        var squal = -7.0 + Float64(Int((random_state >> 3) & UInt64(7)))
        var edge_ready = nr_redcap_rel17_not_at_cell_edge_met(
            srxlev, squal, -70.0, -5.0
        )
        assert_equal(edge_ready, srxlev > -70.0 and squal > -5.0)
        assert_equal(
            nr_redcap_rel17_combine_low_mobility_cell_edge_conditions(
                ready,
                edge_ready,
                NR_REDCAP_LOW_MOBILITY_COMBINE_ALLOW_EITHER,
            ),
            ready or edge_ready,
        )
        var elapsed = Int(random_state % UInt64(7200000000))
        assert_equal(
            nr_redcap_rel17_low_mobility_cell_edge_no_measurement_allowed(
                ready, edge_ready, elapsed
            ),
            ready
                and edge_ready
                and elapsed
                < NR_REDCAP_LOW_MOBILITY_CELL_EDGE_NO_MEASUREMENT_LIMIT_US,
        )

        var table_index = Int((random_state >> 11) % UInt64(4))
        var table_cycle = _literal_cycle_us(table_index)
        var table = nr_redcap_rel17_idle_low_mobility_or_cell_edge_timing(
            NR_REDCAP_RELAXED_FAMILY_INTER_NR,
            NR_REDCAP_RELAXED_CRITERION_LOW_MOBILITY,
            NR_REDCAP_LOW_MOBILITY_FR2,
            2,
            40000,
            table_cycle,
        )
        var expected_n1 = _literal_fr2_n1(table_index)
        assert_equal(table.n1, expected_n1)
        assert_equal(table.detect_us, table.detect_cycles * table_cycle)

        var inactive_index = Int((random_state >> 17) % UInt64(6))
        var inactive_cycle = _literal_cycle_us(inactive_index)
        var inactive = (
            nr_redcap_rel17_inactive_low_mobility_or_cell_edge_timing(
                NR_REDCAP_RELAXED_FAMILY_INTRA_NR,
                NR_REDCAP_RELAXED_CRITERION_NOT_AT_CELL_EDGE,
                NR_REDCAP_LOW_MOBILITY_FR1,
                1,
                20000,
                10485760000,
                inactive_cycle,
            )
        )
        assert_equal(inactive.m2_numerator, 2)
        assert_equal(
            inactive.measure_us, inactive.measure_cycles * inactive_cycle
        )

        var base_search = 1 + Int((random_state >> 24) & UInt64(0xFFFF))
        var configured = (random_state & UInt64(1)) == UInt64(1)
        assert_equal(
            nr_redcap_rel17_low_mobility_high_priority_search_interval_us(
                base_search,
                high_priority_meas_relax_configured=configured,
                low_mobility_ready=True,
                serving_above_non_intra_thresholds=True,
            ),
            (
                base_search * NR_REDCAP_LOW_MOBILITY_HIGH_PRIORITY_K2
                if configured
                else base_search
            ),
        )

    # Seeded transition periods independently check max-before/exact-new-after.
    for _ in range(128):
        random_state = (
            random_state * UInt64(2862933555777941757)
            + UInt64(3037000493)
        )
        var first = 1 + Int(random_state & UInt64(0x3FFF))
        var second = 1 + Int((random_state >> 16) & UInt64(0x3FFF))
        var transition = NRRedCapTimingRequirementTransitionState(
            first, second, 0
        )
        var expected = max(first, second)
        assert_equal(
            nr_redcap_rel17_timing_requirement_transition_update(
                transition, expected - 1
            ),
            expected,
        )
        assert_equal(
            nr_redcap_rel17_timing_requirement_transition_update(
                transition, expected
            ),
            second,
        )

    # Direct seeded use of the scenario APIs preserves structural evidence.
    var scenario = NRRedCapMeasurementScenarioState(
        NR_REDCAP_SCENARIO_NORMAL, 0
    )
    assert_equal(
        nr_redcap_rel17_start_measurement_scenario_transition(
            scenario,
            NR_REDCAP_SCENARIO_STATIONARY,
            0,
            selected_tnormal_us=17,
        ),
        NR_REDCAP_SCENARIO_NORMAL,
    )
    assert_equal(
        nr_redcap_rel17_measurement_scenario_update(scenario, 17),
        NR_REDCAP_SCENARIO_STATIONARY,
    )


def test_independent_literal_oracles_exact_tolerance() raises:
    # A few easily auditable literal rows exercise exact zero-tolerance values
    # independently of the exhaustive loops above.
    var fr1_320 = nr_redcap_rel17_idle_low_mobility_or_cell_edge_timing(
        NR_REDCAP_RELAXED_FAMILY_INTRA_NR,
        NR_REDCAP_RELAXED_CRITERION_LOW_MOBILITY,
        NR_REDCAP_LOW_MOBILITY_FR1,
        1,
        40000,
        320000,
    )
    # 36/4/16 cycles x M2=1.5 x K1=3.
    _assert_timing(
        fr1_320,
        NR_REDCAP_RELAXED_STATE_IDLE,
        1,
        3,
        3,
        NR_REDCAP_RELAXED_COUNT_DRX,
        320000,
        162,
        18,
        72,
    )

    var fr2_short = nr_redcap_rel17_idle_low_mobility_or_cell_edge_timing(
        NR_REDCAP_RELAXED_FAMILY_INTER_NR,
        NR_REDCAP_RELAXED_CRITERION_NOT_AT_CELL_EDGE,
        NR_REDCAP_LOW_MOBILITY_FR2,
        2,
        20000,
        0,
        edrx_idle_cycle_us=5120000,
    )
    # 23/1/2 eDRX cycles x N1=3 x K1=3.
    _assert_timing(
        fr2_short,
        NR_REDCAP_RELAXED_STATE_IDLE,
        3,
        2,
        3,
        NR_REDCAP_RELAXED_COUNT_EDRX_IDLE,
        5120000,
        207,
        9,
        18,
    )

    var inactive = nr_redcap_rel17_inactive_low_mobility_or_cell_edge_timing(
        NR_REDCAP_RELAXED_FAMILY_INTRA_NR,
        NR_REDCAP_RELAXED_CRITERION_LOW_MOBILITY,
        NR_REDCAP_LOW_MOBILITY_FR2,
        2,
        40000,
        20480000,
        640000,
    )
    # 28/2/8 effective-T cycles x N1=5 x K4=3.
    _assert_timing(
        inactive,
        NR_REDCAP_RELAXED_STATE_INACTIVE,
        5,
        2,
        3,
        NR_REDCAP_RELAXED_COUNT_EFFECTIVE_T,
        640000,
        420,
        30,
        120,
    )

    assert_equal(NR_REDCAP_LOW_MOBILITY_K1, 3)
    assert_equal(NR_REDCAP_LOW_MOBILITY_K4, 3)
    assert_equal(NR_REDCAP_LOW_MOBILITY_HIGH_PRIORITY_K2, 60)
    assert_equal(
        NR_REDCAP_LOW_MOBILITY_PROFILE_REDCAP_REL17,
        1,
    )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
