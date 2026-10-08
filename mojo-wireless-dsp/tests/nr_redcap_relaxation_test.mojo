"""Static, edge, property, and differential evidence for RedCap relaxation."""

from std.testing import assert_equal, assert_raises, TestSuite
from std.utils.numerics import inf, nan
from wireless_dsp.wireless.nr.redcap_relaxation import (
    NR_REDCAP_RELAXATION_PROFILE_ORDINARY_NR,
    NR_REDCAP_RELAXATION_PROFILE_EREDCAP_REL18,
    NR_REDCAP_RELAXATION_FR1,
    NR_REDCAP_RELAXATION_FR2,
    NR_REDCAP_RELAXATION_COMBINE_AND,
    NR_REDCAP_RELAXATION_COMBINE_OR,
    NR_REDCAP_RESELECTION_EXCLUSION_MAX_US,
    NR_REDCAP_STATIONARY_NO_MEASUREMENT_LIMIT_US,
    NRRedCapStationaryRelaxationState,
    nr_redcap_rel17_stationary_delta_met,
    nr_redcap_rel17_stationary_update,
    nr_redcap_rel17_stationary_not_at_cell_edge_met,
    nr_redcap_rel17_combine_relaxed_measurement_conditions,
    nr_redcap_rel17_stationary_no_measurement_allowed,
    nr_redcap_rel17_reselection_exclusion_active,
)


def test_stationary_reference_reset_and_timer_literal_trace() raises:
    # Literal trace derived directly from 38.304 5.2.4.9.0/.3.  T=10 s and
    # delta=3 dB make every strict boundary visible without rounding.
    var state = NRRedCapStationaryRelaxationState(
        NR_REDCAP_RELAXATION_FR1, 1, -80.0, 0
    )
    assert_equal(state.reference_srxlev_db, -80.0)
    assert_equal(
        nr_redcap_rel17_stationary_update(
            state, -82.0, 9999999, 10000000, 3.0
        ),
        False,
    )
    assert_equal(
        nr_redcap_rel17_stationary_update(
            state, -82.0, 10000000, 10000000, 3.0
        ),
        True,
    )

    # Equality is not stationary: (reference-current) == threshold.
    assert_equal(
        nr_redcap_rel17_stationary_update(
            state, -83.0, 10000000, 10000000, 3.0
        ),
        False,
    )
    assert_equal(state.reference_srxlev_db, -80.0)
    assert_equal(state.stationary_unmet_since_us, 10000000)
    assert_equal(
        nr_redcap_rel17_stationary_update(
            state, -83.0, 19999999, 10000000, 3.0
        ),
        False,
    )
    assert_equal(state.reference_srxlev_db, -80.0)

    # At the exact unmet-timer boundary the reference resets to current.
    assert_equal(
        nr_redcap_rel17_stationary_update(
            state, -83.0, 20000000, 10000000, 3.0
        ),
        False,
    )
    assert_equal(state.reference_srxlev_db, -83.0)
    assert_equal(state.stationary_met_since_us, 20000000)
    assert_equal(state.stationary_unmet_since_us, -1)

    # A strict improvement resets the reference but does not interrupt an
    # already continuously met criterion.
    assert_equal(
        nr_redcap_rel17_stationary_update(
            state, -82.0, 21000000, 10000000, 3.0
        ),
        False,
    )
    assert_equal(state.reference_srxlev_db, -82.0)
    assert_equal(state.stationary_met_since_us, 20000000)
    assert_equal(
        nr_redcap_rel17_stationary_update(
            state, -82.0, 30000000, 10000000, 3.0
        ),
        True,
    )

    # Cell reselection resets reference, normal-measurement time, and the
    # stationary timer.  A later gap in normal measurements restarts only its
    # own timer.
    assert_equal(
        nr_redcap_rel17_stationary_update(
            state,
            -70.0,
            31000000,
            10000000,
            3.0,
            cell_selected_or_reselected=True,
        ),
        False,
    )
    assert_equal(state.reference_srxlev_db, -70.0)
    assert_equal(state.cell_selected_at_us, 31000000)
    assert_equal(
        nr_redcap_rel17_stationary_update(
            state,
            -70.5,
            32000000,
            10000000,
            3.0,
            normal_measurements_active=False,
        ),
        False,
    )
    assert_equal(
        nr_redcap_rel17_stationary_update(
            state, -70.5, 33000000, 10000000, 3.0
        ),
        False,
    )
    assert_equal(
        nr_redcap_rel17_stationary_update(
            state, -70.5, 43000000, 10000000, 3.0
        ),
        True,
    )


def test_stationary_edge_and_combine_literal_table() raises:
    assert_equal(
        nr_redcap_rel17_stationary_delta_met(-80.0, -82.999, 3.0), True
    )
    assert_equal(
        nr_redcap_rel17_stationary_delta_met(-80.0, -83.0, 3.0), False
    )
    assert_equal(
        nr_redcap_rel17_stationary_delta_met(-80.0, -79.0, 3.0), True
    )

    assert_equal(
        nr_redcap_rel17_stationary_not_at_cell_edge_met(
            False, -69.0, -4.0, -70.0, -5.0
        ),
        False,
    )
    assert_equal(
        nr_redcap_rel17_stationary_not_at_cell_edge_met(
            True, -70.0, -4.0, -70.0, -5.0
        ),
        False,
    )
    assert_equal(
        nr_redcap_rel17_stationary_not_at_cell_edge_met(
            True, -69.0, -5.0, -70.0, -5.0
        ),
        False,
    )
    assert_equal(
        nr_redcap_rel17_stationary_not_at_cell_edge_met(
            True, -69.0, -4.0, -70.0, -5.0
        ),
        True,
    )
    assert_equal(
        nr_redcap_rel17_stationary_not_at_cell_edge_met(
            True,
            -69.0,
            -100.0,
            -70.0,
            -5.0,
            s_search_threshold_q2_configured=False,
        ),
        True,
    )

    # Literal valid-domain combineRelaxedMeasCondition2 table.
    assert_equal(
        nr_redcap_rel17_combine_relaxed_measurement_conditions(
            False, False, NR_REDCAP_RELAXATION_COMBINE_AND
        ),
        False,
    )
    assert_equal(
        nr_redcap_rel17_combine_relaxed_measurement_conditions(
            False, False, NR_REDCAP_RELAXATION_COMBINE_OR
        ),
        False,
    )
    assert_equal(
        nr_redcap_rel17_combine_relaxed_measurement_conditions(
            True, False, NR_REDCAP_RELAXATION_COMBINE_AND
        ),
        False,
    )
    assert_equal(
        nr_redcap_rel17_combine_relaxed_measurement_conditions(
            True, False, NR_REDCAP_RELAXATION_COMBINE_OR
        ),
        True,
    )
    assert_equal(
        nr_redcap_rel17_combine_relaxed_measurement_conditions(
            True, True, NR_REDCAP_RELAXATION_COMBINE_AND
        ),
        True,
    )
    assert_equal(
        nr_redcap_rel17_combine_relaxed_measurement_conditions(
            True, True, NR_REDCAP_RELAXATION_COMBINE_OR
        ),
        True,
    )

    assert_equal(
        nr_redcap_rel17_stationary_no_measurement_allowed(
            True, NR_REDCAP_STATIONARY_NO_MEASUREMENT_LIMIT_US - 1
        ),
        True,
    )
    assert_equal(
        nr_redcap_rel17_stationary_no_measurement_allowed(
            True, NR_REDCAP_STATIONARY_NO_MEASUREMENT_LIMIT_US
        ),
        False,
    )
    assert_equal(
        nr_redcap_rel17_stationary_no_measurement_allowed(False, 0), False
    )


def test_reselection_exclusion_static_expiry_and_cancel_table() raises:
    var start_us = 1000000
    assert_equal(
        nr_redcap_rel17_reselection_exclusion_active(start_us, start_us), True
    )
    assert_equal(
        nr_redcap_rel17_reselection_exclusion_active(
            start_us,
            start_us + NR_REDCAP_RESELECTION_EXCLUSION_MAX_US - 1,
        ),
        True,
    )
    assert_equal(
        nr_redcap_rel17_reselection_exclusion_active(
            start_us,
            start_us + NR_REDCAP_RESELECTION_EXCLUSION_MAX_US,
        ),
        False,
    )
    assert_equal(
        nr_redcap_rel17_reselection_exclusion_active(
            start_us,
            start_us + 100000000,
            highest_ranked_cell_changed=True,
        ),
        False,
    )
    assert_equal(
        nr_redcap_rel17_reselection_exclusion_active(
            start_us,
            start_us + 100000000,
            entered_any_cell_selection=True,
        ),
        False,
    )
    assert_equal(
        nr_redcap_rel17_reselection_exclusion_active(
            start_us,
            start_us + 100000000,
            redirected_to_frequency=True,
        ),
        False,
    )
    assert_equal(
        nr_redcap_rel17_reselection_exclusion_active(
            start_us,
            start_us + 99999999,
            exclusion_duration_us=100000000,
        ),
        True,
    )
    assert_equal(
        nr_redcap_rel17_reselection_exclusion_active(
            start_us,
            start_us + 100000000,
            exclusion_duration_us=100000000,
        ),
        False,
    )

    # Wide times stay subtraction-safe and expire exactly without wraparound.
    assert_equal(
        nr_redcap_rel17_reselection_exclusion_active(
            Int.MAX - NR_REDCAP_RESELECTION_EXCLUSION_MAX_US,
            Int.MAX,
        ),
        False,
    )


def test_relaxation_property_and_independent_literal_oracles() raises:
    # Exercise the public combiner directly over its complete valid Boolean
    # domain.  The second predicate cannot be true unless stationary is true.
    assert_equal(
        nr_redcap_rel17_combine_relaxed_measurement_conditions(
            False, False, NR_REDCAP_RELAXATION_COMBINE_AND
        ),
        False,
    )
    assert_equal(
        nr_redcap_rel17_combine_relaxed_measurement_conditions(
            False, False, NR_REDCAP_RELAXATION_COMBINE_OR
        ),
        False,
    )
    assert_equal(
        nr_redcap_rel17_combine_relaxed_measurement_conditions(
            True, False, NR_REDCAP_RELAXATION_COMBINE_AND
        ),
        False,
    )
    assert_equal(
        nr_redcap_rel17_combine_relaxed_measurement_conditions(
            True, False, NR_REDCAP_RELAXATION_COMBINE_OR
        ),
        True,
    )
    assert_equal(
        nr_redcap_rel17_combine_relaxed_measurement_conditions(
            True, True, NR_REDCAP_RELAXATION_COMBINE_AND
        ),
        True,
    )
    assert_equal(
        nr_redcap_rel17_combine_relaxed_measurement_conditions(
            True, True, NR_REDCAP_RELAXATION_COMBINE_OR
        ),
        True,
    )

    var references: List[Float64] = [-100.0, -80.0, -60.0]
    var currents: List[Float64] = [-104.0, -83.0, -82.999, -79.0]
    var deltas: List[Float64] = [1.0, 3.0, 6.0]
    for reference in references:
        for current in currents:
            for delta in deltas:
                var literal = reference - current < delta
                assert_equal(
                    nr_redcap_rel17_stationary_delta_met(
                        reference, current, delta
                    ),
                    literal,
                )

    var levels: List[Float64] = [-71.0, -70.0, -69.0]
    var qualities: List[Float64] = [-6.0, -5.0, -4.0]
    for level in levels:
        for quality in qualities:
            var literal = level > -70.0 and quality > -5.0
            assert_equal(
                nr_redcap_rel17_stationary_not_at_cell_edge_met(
                    True, level, quality, -70.0, -5.0
                ),
                literal,
            )

    # Adding an arbitrary dB offset to reference and observations must not
    # change a delta-based timer decision.
    var offsets: List[Float64] = [-20.0, 0.0, 20.0]
    for offset in offsets:
        var state = NRRedCapStationaryRelaxationState(
            NR_REDCAP_RELAXATION_FR1, 2, -80.0 + offset, 0
        )
        assert_equal(
            nr_redcap_rel17_stationary_update(
                state, -81.0 + offset, 9999999, 10000000, 3.0
            ),
            False,
        )
        assert_equal(
            nr_redcap_rel17_stationary_update(
                state, -81.0 + offset, 10000000, 10000000, 3.0
            ),
            True,
        )
        assert_equal(state.reference_srxlev_db, -80.0 + offset)

    var durations: List[Int] = [1, 100000000, 300000000]
    var elapsed_values: List[Int] = [0, 1, 99999999, 299999999, 300000000]
    for duration in durations:
        for elapsed in elapsed_values:
            var literal = elapsed < duration
            assert_equal(
                nr_redcap_rel17_reselection_exclusion_active(
                    0, elapsed, exclusion_duration_us=duration
                ),
                literal,
            )

    # Independent literal oracle for the 38.133 "less than 4 hours" gate.
    var four_hour_elapsed: List[Int] = [
        0, 14399999999, 14400000000, 14400000001
    ]
    for elapsed in four_hour_elapsed:
        var literal = elapsed < 14400000000
        assert_equal(
            nr_redcap_rel17_stationary_no_measurement_allowed(True, elapsed),
            literal,
        )


def test_public_invalid_nan_profile_and_state_edges() raises:
    with assert_raises():
        _ = NRRedCapStationaryRelaxationState(
            NR_REDCAP_RELAXATION_FR1,
            1,
            nan[DType.float64](),
            0,
        )
    with assert_raises():
        _ = NRRedCapStationaryRelaxationState(
            NR_REDCAP_RELAXATION_FR1,
            1,
            inf[DType.float64](),
            0,
        )
    with assert_raises():
        _ = NRRedCapStationaryRelaxationState(3, 1, -80.0, 0)
    with assert_raises():
        _ = NRRedCapStationaryRelaxationState(
            NR_REDCAP_RELAXATION_FR2, 1, -80.0, 0
        )
    with assert_raises():
        _ = NRRedCapStationaryRelaxationState(
            NR_REDCAP_RELAXATION_FR1, 3, -80.0, 0
        )
    with assert_raises():
        _ = NRRedCapStationaryRelaxationState(
            NR_REDCAP_RELAXATION_FR1,
            1,
            -80.0,
            0,
            profile=NR_REDCAP_RELAXATION_PROFILE_ORDINARY_NR,
        )
    with assert_raises():
        _ = NRRedCapStationaryRelaxationState(
            NR_REDCAP_RELAXATION_FR1,
            1,
            -80.0,
            0,
            profile=NR_REDCAP_RELAXATION_PROFILE_EREDCAP_REL18,
        )

    with assert_raises():
        _ = nr_redcap_rel17_stationary_delta_met(
            nan[DType.float64](), -80.0, 3.0
        )
    with assert_raises():
        _ = nr_redcap_rel17_stationary_delta_met(-80.0, -81.0, 0.0)
    with assert_raises():
        _ = nr_redcap_rel17_stationary_delta_met(
            -80.0,
            -81.0,
            3.0,
            profile=NR_REDCAP_RELAXATION_PROFILE_ORDINARY_NR,
        )

    var state = NRRedCapStationaryRelaxationState(
        NR_REDCAP_RELAXATION_FR2, 2, -80.0, 10
    )
    with assert_raises():
        _ = nr_redcap_rel17_stationary_update(
            state, -80.0, 9, 10000000, 3.0
        )
    with assert_raises():
        _ = nr_redcap_rel17_stationary_update(
            state, -80.0, 10, 0, 3.0
        )
    with assert_raises():
        _ = nr_redcap_rel17_stationary_update(
            state, -80.0, 10, 1, nan[DType.float64]()
        )
    state.profile = NR_REDCAP_RELAXATION_PROFILE_EREDCAP_REL18
    with assert_raises():
        _ = nr_redcap_rel17_stationary_update(
            state, -80.0, 10, 1, 3.0
        )

    var mutated_timer_state = NRRedCapStationaryRelaxationState(
        NR_REDCAP_RELAXATION_FR1, 1, -80.0, 10
    )
    mutated_timer_state.normal_measurements_since_us = 9
    with assert_raises():
        mutated_timer_state.validate()

    with assert_raises():
        _ = nr_redcap_rel17_stationary_not_at_cell_edge_met(
            True, nan[DType.float64](), -4.0, -70.0, -5.0
        )
    with assert_raises():
        _ = nr_redcap_rel17_stationary_not_at_cell_edge_met(
            True, -69.0, inf[DType.float64](), -70.0, -5.0
        )
    with assert_raises():
        _ = nr_redcap_rel17_stationary_not_at_cell_edge_met(
            True,
            -69.0,
            -4.0,
            -70.0,
            -5.0,
            profile=NR_REDCAP_RELAXATION_PROFILE_ORDINARY_NR,
        )
    with assert_raises():
        _ = nr_redcap_rel17_combine_relaxed_measurement_conditions(
            True, False, 9
        )
    with assert_raises():
        _ = nr_redcap_rel17_combine_relaxed_measurement_conditions(
            False, True, NR_REDCAP_RELAXATION_COMBINE_OR
        )
    with assert_raises():
        _ = nr_redcap_rel17_combine_relaxed_measurement_conditions(
            True,
            False,
            NR_REDCAP_RELAXATION_COMBINE_OR,
            profile=NR_REDCAP_RELAXATION_PROFILE_EREDCAP_REL18,
        )
    with assert_raises():
        _ = nr_redcap_rel17_stationary_no_measurement_allowed(True, -1)
    with assert_raises():
        _ = nr_redcap_rel17_stationary_no_measurement_allowed(
            True,
            0,
            profile=NR_REDCAP_RELAXATION_PROFILE_ORDINARY_NR,
        )
    assert_equal(
        nr_redcap_rel17_stationary_no_measurement_allowed(True, Int.MAX),
        False,
    )

    with assert_raises():
        _ = nr_redcap_rel17_reselection_exclusion_active(10, 9)
    with assert_raises():
        _ = nr_redcap_rel17_reselection_exclusion_active(
            0, 0, exclusion_duration_us=0
        )
    with assert_raises():
        _ = nr_redcap_rel17_reselection_exclusion_active(
            0,
            0,
            exclusion_duration_us=(
                NR_REDCAP_RESELECTION_EXCLUSION_MAX_US + 1
            ),
        )
    with assert_raises():
        _ = nr_redcap_rel17_reselection_exclusion_active(
            0,
            0,
            profile=NR_REDCAP_RELAXATION_PROFILE_EREDCAP_REL18,
        )

    var maximum_time_state = NRRedCapStationaryRelaxationState(
        NR_REDCAP_RELAXATION_FR1, 1, -80.0, Int.MAX
    )
    assert_equal(
        nr_redcap_rel17_stationary_update(
            maximum_time_state, -80.0, Int.MAX, 1, 3.0
        ),
        False,
    )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
