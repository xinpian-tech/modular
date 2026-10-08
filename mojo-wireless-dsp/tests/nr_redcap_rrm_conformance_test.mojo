"""Independent evidence for bounded TS 38.533 RedCap RRM verdicts.

The 13 expected rows below are a direct, test-only transcription from TS
38.533 V18.8.0 clauses 16.1.1.1--16.1.1.4, 17.1.1.1--17.1.1.2, and
18.2.2.1.  They are not generated through the production lookup.
"""

from std.testing import assert_equal, assert_raises, TestSuite
from std.utils.numerics import inf, nan
from wireless_dsp.wireless.nr.redcap_rrm_conformance import (
    NR_REDCAP_RRM_CONFORMANCE_PROFILE_ORDINARY_NR,
    NR_REDCAP_RRM_CONFORMANCE_PROFILE_REDCAP_REL17,
    NR_REDCAP_RRM_CONFORMANCE_PROFILE_EREDCAP_REL18,
    NR_REDCAP_RRM_CONFORMANCE_SOURCE_NR,
    NR_REDCAP_RRM_CONFORMANCE_SOURCE_EUTRA,
    NR_REDCAP_RRM_CONFORMANCE_FR1,
    NR_REDCAP_RRM_CONFORMANCE_FR2,
    NR_REDCAP_RRM_CONFORMANCE_EVENT_INTRA_NEW,
    NR_REDCAP_RRM_CONFORMANCE_EVENT_INTRA_ALREADY_DETECTED,
    NR_REDCAP_RRM_CONFORMANCE_EVENT_INTER_LOWER_PRIORITY,
    NR_REDCAP_RRM_CONFORMANCE_EVENT_INTER_HIGHER_PRIORITY,
    NR_REDCAP_RRM_CONFORMANCE_EVENT_EUTRA_TO_NR_REDIRECTION,
    NR_REDCAP_RRM_CONFORMANCE_TC_16_1_1_1,
    NR_REDCAP_RRM_CONFORMANCE_TC_16_1_1_2,
    NR_REDCAP_RRM_CONFORMANCE_TC_16_1_1_3,
    NR_REDCAP_RRM_CONFORMANCE_TC_16_1_1_4,
    NR_REDCAP_RRM_CONFORMANCE_TC_17_1_1_1,
    NR_REDCAP_RRM_CONFORMANCE_TC_17_1_1_2,
    NR_REDCAP_RRM_CONFORMANCE_TC_18_2_2_1,
    NR_REDCAP_RRM_CONFORMANCE_VERDICT_PENDING,
    NR_REDCAP_RRM_CONFORMANCE_VERDICT_PASS,
    NR_REDCAP_RRM_CONFORMANCE_VERDICT_FAIL_LATE,
    NR_REDCAP_RRM_CONFORMANCE_STATE_ACTIVE,
    NR_REDCAP_RRM_CONFORMANCE_STATE_AWAITING_NEXT_PHASE,
    NR_REDCAP_RRM_CONFORMANCE_STATE_PASSED,
    NR_REDCAP_RRM_CONFORMANCE_STATE_FAILED,
    NRRedCapRRMConformanceState,
    nr_redcap_rel17_rrm_conformance_row,
    nr_redcap_rel17_rrm_conformance_delay_verdict,
    nr_redcap_rel17_rrm_conformance_update,
    nr_redcap_rel17_rrm_conformance_start_next_phase,
)


def _cases() -> List[Int]:
    return [
        1601111,
        1601111,
        1601112,
        1601112,
        1601113,
        1601113,
        1601114,
        1601114,
        1701111,
        1701111,
        1701112,
        1701112,
        1802201,
    ]


def _phases() -> List[Int]:
    return [0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0]


def _clauses() -> List[Int]:
    return [16, 16, 16, 16, 16, 16, 16, 16, 17, 17, 17, 17, 18]


def _sources() -> List[Int]:
    return [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1]


def _frequency_ranges() -> List[Int]:
    return [1, 1, 1, 1, 1, 1, 1, 1, 2, 2, 2, 2, 1]


def _rx_branches() -> List[Int]:
    return [1, 1, 2, 2, 1, 1, 2, 2, 2, 2, 2, 2, 2]


def _phase_counts() -> List[Int]:
    return [2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 1]


def _periods() -> List[Int]:
    return [2, 3, 2, 3, 1, 3, 1, 3, 2, 3, 1, 3, 2]


def _events() -> List[Int]:
    return [0, 1, 0, 1, 2, 3, 2, 3, 0, 1, 2, 3, 4]


def _expected_cells() -> List[Int]:
    return [2, 1, 2, 1, 1, 2, 1, 2, 2, 1, 1, 2, 2]


def _limits_us() -> List[Int]:
    return [
        34_000_000,
        8_000_000,
        34_000_000,
        8_000_000,
        8_000_000,
        68_000_000,
        8_000_000,
        68_000_000,
        130_000_000,
        27_000_000,
        27_000_000,
        87_000_000,
        2_240_000,
    ]


def _independent_verdict(
    expected_cell: Int,
    strict_limit_us: Int,
    response_seen: Bool,
    observed_cell: Int,
    elapsed_us: Int,
) -> Int:
    # Test-only closed form.  It consumes literal expected cells and limits,
    # never a production row or production state transition.
    if elapsed_us >= strict_limit_us:
        return NR_REDCAP_RRM_CONFORMANCE_VERDICT_FAIL_LATE
    if not response_seen:
        return NR_REDCAP_RRM_CONFORMANCE_VERDICT_PENDING
    if observed_cell != expected_cell:
        return NR_REDCAP_RRM_CONFORMANCE_VERDICT_PENDING
    return NR_REDCAP_RRM_CONFORMANCE_VERDICT_PASS


def test_all_13_official_phase_rows_exact_static_oracle() raises:
    var cases = _cases()
    var phases = _phases()
    var clauses = _clauses()
    var sources = _sources()
    var ranges = _frequency_ranges()
    var branches = _rx_branches()
    var counts = _phase_counts()
    var periods = _periods()
    var events = _events()
    var cells = _expected_cells()
    var limits = _limits_us()
    for index in range(13):
        var row = nr_redcap_rel17_rrm_conformance_row(
            cases[index], phases[index]
        )
        row.validate()
        assert_equal(row.profile, 1)
        assert_equal(row.test_case, cases[index])
        assert_equal(row.phase_index, phases[index])
        assert_equal(row.clause_major, clauses[index])
        assert_equal(row.source_rat, sources[index])
        assert_equal(row.target_frequency_range, ranges[index])
        assert_equal(row.rx_branches, branches[index])
        assert_equal(row.phase_count, counts[index])
        assert_equal(row.test_period, periods[index])
        assert_equal(row.event_kind, events[index])
        assert_equal(row.expected_cell, cells[index])
        assert_equal(row.strict_limit_us, limits[index])

    assert_equal(NR_REDCAP_RRM_CONFORMANCE_SOURCE_NR, 0)
    assert_equal(NR_REDCAP_RRM_CONFORMANCE_SOURCE_EUTRA, 1)
    assert_equal(NR_REDCAP_RRM_CONFORMANCE_FR1, 1)
    assert_equal(NR_REDCAP_RRM_CONFORMANCE_FR2, 2)
    assert_equal(NR_REDCAP_RRM_CONFORMANCE_EVENT_INTRA_NEW, 0)
    assert_equal(
        NR_REDCAP_RRM_CONFORMANCE_EVENT_INTRA_ALREADY_DETECTED, 1
    )
    assert_equal(NR_REDCAP_RRM_CONFORMANCE_EVENT_INTER_LOWER_PRIORITY, 2)
    assert_equal(NR_REDCAP_RRM_CONFORMANCE_EVENT_INTER_HIGHER_PRIORITY, 3)
    assert_equal(
        NR_REDCAP_RRM_CONFORMANCE_EVENT_EUTRA_TO_NR_REDIRECTION, 4
    )


def test_strict_float_timer_endpoints_wrong_cell_and_nonfinite() raises:
    var row = nr_redcap_rel17_rrm_conformance_row(
        NR_REDCAP_RRM_CONFORMANCE_TC_18_2_2_1, 0
    )
    assert_equal(
        nr_redcap_rel17_rrm_conformance_delay_verdict(
            row, True, 2, 2239.999
        ),
        NR_REDCAP_RRM_CONFORMANCE_VERDICT_PASS,
    )
    assert_equal(
        nr_redcap_rel17_rrm_conformance_delay_verdict(
            row, True, 2, 2240.0
        ),
        NR_REDCAP_RRM_CONFORMANCE_VERDICT_FAIL_LATE,
    )
    assert_equal(
        nr_redcap_rel17_rrm_conformance_delay_verdict(
            row, False, -1, 2239.999
        ),
        NR_REDCAP_RRM_CONFORMANCE_VERDICT_PENDING,
    )
    assert_equal(
        nr_redcap_rel17_rrm_conformance_delay_verdict(
            row, False, -1, 2240.0
        ),
        NR_REDCAP_RRM_CONFORMANCE_VERDICT_FAIL_LATE,
    )
    assert_equal(
        nr_redcap_rel17_rrm_conformance_delay_verdict(
            row, True, 1, 1.0
        ),
        NR_REDCAP_RRM_CONFORMANCE_VERDICT_PENDING,
    )
    # Every published row uses the same strict less-than boundary.  Exercise
    # one microsecond below, exactly at, and one microsecond above all 13
    # limits rather than relying on random sampling to hit endpoints.
    var cases = _cases()
    var phases = _phases()
    var cells = _expected_cells()
    var limits = _limits_us()
    for index in range(13):
        var endpoint_row = nr_redcap_rel17_rrm_conformance_row(
            cases[index], phases[index]
        )
        assert_equal(
            nr_redcap_rel17_rrm_conformance_delay_verdict(
                endpoint_row,
                True,
                cells[index],
                Float64(limits[index] - 1) / 1000.0,
            ),
            NR_REDCAP_RRM_CONFORMANCE_VERDICT_PASS,
        )
        for delta in range(2):
            assert_equal(
                nr_redcap_rel17_rrm_conformance_delay_verdict(
                    endpoint_row,
                    True,
                    cells[index],
                    Float64(limits[index] + delta) / 1000.0,
                ),
                NR_REDCAP_RRM_CONFORMANCE_VERDICT_FAIL_LATE,
            )
    with assert_raises():
        _ = nr_redcap_rel17_rrm_conformance_delay_verdict(
            row, True, 2, nan[DType.float64]()
        )
    with assert_raises():
        _ = nr_redcap_rel17_rrm_conformance_delay_verdict(
            row, True, 2, inf[DType.float64]()
        )
    with assert_raises():
        _ = nr_redcap_rel17_rrm_conformance_delay_verdict(
            row, True, 2, -inf[DType.float64]()
        )
    with assert_raises():
        _ = nr_redcap_rel17_rrm_conformance_delay_verdict(
            row, True, 2, -1.0
        )
    with assert_raises():
        _ = nr_redcap_rel17_rrm_conformance_delay_verdict(
            row, False, 2, 0.0
        )
    with assert_raises():
        _ = nr_redcap_rel17_rrm_conformance_delay_verdict(
            row, True, 3, 0.0
        )
    for observed_cell in [Int.MIN, Int.MAX]:
        with assert_raises():
            _ = nr_redcap_rel17_rrm_conformance_delay_verdict(
                row, True, observed_cell, 0.0
            )
    assert_equal(
        nr_redcap_rel17_rrm_conformance_delay_verdict(
            row, True, 2, 5.0e-324
        ),
        NR_REDCAP_RRM_CONFORMANCE_VERDICT_PASS,
    )
    assert_equal(
        nr_redcap_rel17_rrm_conformance_delay_verdict(
            row, True, 2, 1.7976931348623157e308
        ),
        NR_REDCAP_RRM_CONFORMANCE_VERDICT_FAIL_LATE,
    )


def test_two_phase_state_machine_and_exact_integer_expiry() raises:
    var state = NRRedCapRRMConformanceState(
        NR_REDCAP_RRM_CONFORMANCE_TC_16_1_1_1, 1_000_000
    )
    assert_equal(state.state, NR_REDCAP_RRM_CONFORMANCE_STATE_ACTIVE)
    assert_equal(
        nr_redcap_rel17_rrm_conformance_update(
            state, 34_999_998, False, -1
        ),
        NR_REDCAP_RRM_CONFORMANCE_VERDICT_PENDING,
    )
    assert_equal(
        nr_redcap_rel17_rrm_conformance_update(
            state, 34_999_999, True, 2
        ),
        NR_REDCAP_RRM_CONFORMANCE_VERDICT_PASS,
    )
    assert_equal(
        state.state,
        NR_REDCAP_RRM_CONFORMANCE_STATE_AWAITING_NEXT_PHASE,
    )
    assert_equal(state.phase_index, 1)
    assert_equal(
        nr_redcap_rel17_rrm_conformance_start_next_phase(
            state, 40_000_000
        ),
        NR_REDCAP_RRM_CONFORMANCE_STATE_ACTIVE,
    )
    assert_equal(
        nr_redcap_rel17_rrm_conformance_update(
            state, 47_999_999, True, 1
        ),
        NR_REDCAP_RRM_CONFORMANCE_VERDICT_PASS,
    )
    assert_equal(state.state, NR_REDCAP_RRM_CONFORMANCE_STATE_PASSED)
    assert_equal(state.phase_index, 2)
    assert_equal(
        state.terminal_verdict, NR_REDCAP_RRM_CONFORMANCE_VERDICT_PASS
    )
    state.validate()

    var exact_expiry = NRRedCapRRMConformanceState(
        NR_REDCAP_RRM_CONFORMANCE_TC_16_1_1_3, 5
    )
    assert_equal(
        nr_redcap_rel17_rrm_conformance_update(
            exact_expiry, 8_000_005, True, 1
        ),
        NR_REDCAP_RRM_CONFORMANCE_VERDICT_FAIL_LATE,
    )
    assert_equal(
        exact_expiry.state, NR_REDCAP_RRM_CONFORMANCE_STATE_FAILED
    )

    var wrong_then_target = NRRedCapRRMConformanceState(
        NR_REDCAP_RRM_CONFORMANCE_TC_17_1_1_1, 0
    )
    assert_equal(
        nr_redcap_rel17_rrm_conformance_update(
            wrong_then_target, 1, True, 1
        ),
        NR_REDCAP_RRM_CONFORMANCE_VERDICT_PENDING,
    )
    assert_equal(
        wrong_then_target.state, NR_REDCAP_RRM_CONFORMANCE_STATE_ACTIVE
    )
    assert_equal(
        nr_redcap_rel17_rrm_conformance_update(
            wrong_then_target, 129_999_999, True, 2
        ),
        NR_REDCAP_RRM_CONFORMANCE_VERDICT_PASS,
    )
    assert_equal(
        wrong_then_target.state,
        NR_REDCAP_RRM_CONFORMANCE_STATE_AWAITING_NEXT_PHASE,
    )

    # No start+limit addition is performed: Int.MAX is a valid monotonic
    # timestamp when no later representable observation is requested.
    var maximum_time = NRRedCapRRMConformanceState(
        NR_REDCAP_RRM_CONFORMANCE_TC_18_2_2_1, Int.MAX
    )
    assert_equal(
        nr_redcap_rel17_rrm_conformance_update(
            maximum_time, Int.MAX, False, -1
        ),
        NR_REDCAP_RRM_CONFORMANCE_VERDICT_PENDING,
    )


def test_profile_case_time_and_mutable_public_edges() raises:
    assert_equal(
        NR_REDCAP_RRM_CONFORMANCE_PROFILE_ORDINARY_NR, 0
    )
    assert_equal(
        NR_REDCAP_RRM_CONFORMANCE_PROFILE_REDCAP_REL17, 1
    )
    assert_equal(
        NR_REDCAP_RRM_CONFORMANCE_PROFILE_EREDCAP_REL18, 2
    )
    with assert_raises():
        _ = nr_redcap_rel17_rrm_conformance_row(
            NR_REDCAP_RRM_CONFORMANCE_TC_16_1_1_1,
            0,
            profile=NR_REDCAP_RRM_CONFORMANCE_PROFILE_ORDINARY_NR,
        )
    with assert_raises():
        _ = nr_redcap_rel17_rrm_conformance_row(
            NR_REDCAP_RRM_CONFORMANCE_TC_16_1_1_1,
            0,
            profile=NR_REDCAP_RRM_CONFORMANCE_PROFILE_EREDCAP_REL18,
        )
    with assert_raises():
        _ = nr_redcap_rel17_rrm_conformance_row(999, 0)
    with assert_raises():
        _ = nr_redcap_rel17_rrm_conformance_row(
            NR_REDCAP_RRM_CONFORMANCE_TC_18_2_2_1, 1
        )
    with assert_raises():
        _ = nr_redcap_rel17_rrm_conformance_row(
            NR_REDCAP_RRM_CONFORMANCE_TC_17_1_1_1, -1
        )
    for profile in [Int.MIN, Int.MAX]:
        with assert_raises():
            _ = nr_redcap_rel17_rrm_conformance_row(
                NR_REDCAP_RRM_CONFORMANCE_TC_16_1_1_1,
                0,
                profile=profile,
            )
    for test_case in [Int.MIN, Int.MAX]:
        with assert_raises():
            _ = nr_redcap_rel17_rrm_conformance_row(test_case, 0)
        with assert_raises():
            _ = NRRedCapRRMConformanceState(test_case, 0)
    for phase in [Int.MIN, Int.MAX]:
        with assert_raises():
            _ = nr_redcap_rel17_rrm_conformance_row(
                NR_REDCAP_RRM_CONFORMANCE_TC_16_1_1_1, phase
            )
    with assert_raises():
        _ = NRRedCapRRMConformanceState(
            NR_REDCAP_RRM_CONFORMANCE_TC_16_1_1_1, -1
        )

    var mutated_row = nr_redcap_rel17_rrm_conformance_row(
        NR_REDCAP_RRM_CONFORMANCE_TC_17_1_1_2, 1
    )
    mutated_row.strict_limit_us += 1
    with assert_raises():
        mutated_row.validate()
    with assert_raises():
        _ = nr_redcap_rel17_rrm_conformance_delay_verdict(
            mutated_row, True, 2, 1.0
        )

    var mutated_state = NRRedCapRRMConformanceState(
        NR_REDCAP_RRM_CONFORMANCE_TC_16_1_1_2, 0
    )
    mutated_state.phase_count = 1
    with assert_raises():
        mutated_state.validate()
    with assert_raises():
        _ = nr_redcap_rel17_rrm_conformance_update(
            mutated_state, 0, False, -1
        )

    var expired_mutation = NRRedCapRRMConformanceState(
        NR_REDCAP_RRM_CONFORMANCE_TC_18_2_2_1, 0
    )
    expired_mutation.last_update_us = 2_240_000
    with assert_raises():
        expired_mutation.validate()
    with assert_raises():
        _ = nr_redcap_rel17_rrm_conformance_update(
            expired_mutation, 2_240_000, False, -1
        )

    var time_order = NRRedCapRRMConformanceState(
        NR_REDCAP_RRM_CONFORMANCE_TC_16_1_1_2, 100
    )
    with assert_raises():
        _ = nr_redcap_rel17_rrm_conformance_update(
            time_order, 99, False, -1
        )
    with assert_raises():
        _ = nr_redcap_rel17_rrm_conformance_start_next_phase(
            time_order, 100
        )
    assert_equal(
        nr_redcap_rel17_rrm_conformance_update(time_order, 101, True, 2),
        NR_REDCAP_RRM_CONFORMANCE_VERDICT_PASS,
    )
    with assert_raises():
        _ = nr_redcap_rel17_rrm_conformance_start_next_phase(
            time_order, 100
        )


def test_seeded_independent_timing_and_state_oracle() raises:
    var cases = _cases()
    var phases = _phases()
    var cells = _expected_cells()
    var limits = _limits_us()
    var random_state = UInt64(0x385331718)
    for _ in range(384):
        random_state = (
            random_state * UInt64(6364136223846793005)
            + UInt64(1442695040888963407)
        )
        var index = Int(random_state % UInt64(13))
        var seen = ((random_state >> 8) & UInt64(1)) == UInt64(1)
        var expected_cell = cells[index]
        var observed_cell = (
            (3 - expected_cell)
            if ((random_state >> 9) & UInt64(1)) == UInt64(1)
            else expected_cell
        )
        if not seen:
            observed_cell = -1
        var elapsed_us = Int(
            (random_state >> 10) % UInt64(limits[index] + 2)
        )
        var expected = _independent_verdict(
            expected_cell,
            limits[index],
            seen,
            observed_cell,
            elapsed_us,
        )
        var row = nr_redcap_rel17_rrm_conformance_row(
            cases[index], phases[index]
        )
        assert_equal(
            nr_redcap_rel17_rrm_conformance_delay_verdict(
                row,
                seen,
                observed_cell,
                Float64(elapsed_us) / 1000.0,
            ),
            expected,
        )

    # Seed-driven independent state model over every two-phase case.  The
    # literal arrays, not production rows, determine each expected transition.
    var state_cases: List[Int] = [
        NR_REDCAP_RRM_CONFORMANCE_TC_16_1_1_1,
        NR_REDCAP_RRM_CONFORMANCE_TC_16_1_1_2,
        NR_REDCAP_RRM_CONFORMANCE_TC_16_1_1_3,
        NR_REDCAP_RRM_CONFORMANCE_TC_16_1_1_4,
        NR_REDCAP_RRM_CONFORMANCE_TC_17_1_1_1,
        NR_REDCAP_RRM_CONFORMANCE_TC_17_1_1_2,
    ]
    for _ in range(384):
        random_state = (
            random_state * UInt64(6364136223846793005)
            + UInt64(1442695040888963407)
        )
        var case_index = Int(random_state % UInt64(6))
        var first_index = case_index * 2
        var start_us = Int((random_state >> 8) % UInt64(1024))
        var first_limit = limits[first_index]
        var first_cell = cells[first_index]
        var first_mode = Int((random_state >> 19) & UInt64(3))
        var first_seen = first_mode != 0
        var first_observed = first_cell
        var first_elapsed = first_limit - 1
        if first_mode == 0:
            first_observed = -1
            first_elapsed = first_limit // 2
        elif first_mode == 1:
            first_observed = 3 - first_cell
            first_elapsed = first_limit // 2
        elif first_mode == 3:
            first_elapsed = first_limit

        var state = NRRedCapRRMConformanceState(
            state_cases[case_index], start_us
        )
        var first_expected = _independent_verdict(
            first_cell,
            first_limit,
            first_seen,
            first_observed,
            first_elapsed,
        )
        assert_equal(
            nr_redcap_rel17_rrm_conformance_update(
                state,
                start_us + first_elapsed,
                first_seen,
                first_observed,
            ),
            first_expected,
        )
        if first_expected == NR_REDCAP_RRM_CONFORMANCE_VERDICT_FAIL_LATE:
            assert_equal(
                state.state, NR_REDCAP_RRM_CONFORMANCE_STATE_FAILED
            )
            continue
        if first_expected == NR_REDCAP_RRM_CONFORMANCE_VERDICT_PENDING:
            assert_equal(
                state.state, NR_REDCAP_RRM_CONFORMANCE_STATE_ACTIVE
            )
            assert_equal(
                nr_redcap_rel17_rrm_conformance_update(
                    state,
                    start_us + first_limit - 1,
                    True,
                    first_cell,
                ),
                NR_REDCAP_RRM_CONFORMANCE_VERDICT_PASS,
            )
        assert_equal(
            state.state,
            NR_REDCAP_RRM_CONFORMANCE_STATE_AWAITING_NEXT_PHASE,
        )

        var next_started_us = state.last_update_us + 17
        assert_equal(
            nr_redcap_rel17_rrm_conformance_start_next_phase(
                state, next_started_us
            ),
            NR_REDCAP_RRM_CONFORMANCE_STATE_ACTIVE,
        )
        assert_equal(state.phase_index, 1)
        var second_index = first_index + 1
        var second_limit = limits[second_index]
        var second_cell = cells[second_index]
        var second_mode = Int((random_state >> 27) & UInt64(3))
        var second_seen = second_mode != 0
        var second_observed = second_cell
        var second_elapsed = second_limit - 1
        if second_mode == 0:
            second_observed = -1
            second_elapsed = second_limit // 3
        elif second_mode == 1:
            second_observed = 3 - second_cell
            second_elapsed = second_limit // 3
        elif second_mode == 3:
            second_elapsed = second_limit
        var second_expected = _independent_verdict(
            second_cell,
            second_limit,
            second_seen,
            second_observed,
            second_elapsed,
        )
        assert_equal(
            nr_redcap_rel17_rrm_conformance_update(
                state,
                next_started_us + second_elapsed,
                second_seen,
                second_observed,
            ),
            second_expected,
        )
        if second_expected == NR_REDCAP_RRM_CONFORMANCE_VERDICT_FAIL_LATE:
            assert_equal(
                state.state, NR_REDCAP_RRM_CONFORMANCE_STATE_FAILED
            )
        elif second_expected == NR_REDCAP_RRM_CONFORMANCE_VERDICT_PENDING:
            assert_equal(
                state.state, NR_REDCAP_RRM_CONFORMANCE_STATE_ACTIVE
            )
            assert_equal(
                nr_redcap_rel17_rrm_conformance_update(
                    state,
                    next_started_us + second_limit - 1,
                    True,
                    second_cell,
                ),
                NR_REDCAP_RRM_CONFORMANCE_VERDICT_PASS,
            )
            assert_equal(
                state.state, NR_REDCAP_RRM_CONFORMANCE_STATE_PASSED
            )
        else:
            assert_equal(
                state.state, NR_REDCAP_RRM_CONFORMANCE_STATE_PASSED
            )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
