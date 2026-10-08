"""Independent exact and property evidence for bounded Rel-16 NR-U."""

from std.testing import assert_equal, assert_raises, TestSuite
from wireless_dsp.wireless.nr.nr_u_rel16 import (
    NR_U_REL16_DOWNLINK,
    NR_U_REL16_UPLINK,
    NRURel16PriorityClass,
    NRURel16ContentionWindowState,
    nr_u_rel16_priority_class,
    nr_u_rel16_defer_duration_us,
    nr_u_rel16_contention_window_allowed,
    nr_u_rel16_backoff_draw,
    nr_u_rel16_backoff_after_decrements,
    nr_u_rel16_next_higher_contention_window,
    nr_u_rel16_record_contention_window_draw,
    nr_u_rel16_channel_occupancy_allowed,
)


def _oracle_cw_allowed(value: Int, cw_min: Int, cw_max: Int) -> Bool:
    var candidate = cw_min
    while candidate <= cw_max:
        if value == candidate:
            return True
        candidate = 2 * candidate + 1
    return False


def _oracle_note2_gap_extension_allowed(
    occupancy_duration_us: Int,
    first_gap_start_us: Int,
    minimum_gap_duration_us: Int,
) -> Bool:
    # Independent addition-form transcription of Table 4.2.1-1 Note 2 for
    # bounded positive test inputs.  Production uses subtraction-safe checks.
    return (
        occupancy_duration_us > 6000
        and occupancy_duration_us <= 8000
        and first_gap_start_us >= 0
        and first_gap_start_us <= 6000
        and minimum_gap_duration_us >= 100
        and first_gap_start_us + minimum_gap_duration_us
        < occupancy_duration_us
    )


def _oracle_table_value(
    direction: Int,
    priority: Int,
    other_technology_absent: Bool,
    field: Int,
) -> Int:
    # Literal transcription of TS 37.213 V16.14.0 Tables 4.1.1-1/4.2.1-1.
    var dl_m: List[Int] = [1, 1, 3, 7]
    var ul_m: List[Int] = [2, 2, 3, 7]
    var cw_min: List[Int] = [3, 7, 15, 15]
    var dl_cw_max: List[Int] = [7, 15, 63, 1023]
    var ul_cw_max: List[Int] = [7, 15, 1023, 1023]
    var dl_cot: List[Int] = [2000, 3000, 8000, 8000]
    var ul_cot: List[Int] = [2000, 4000, 6000, 6000]
    var index = priority - 1
    if field == 0:
        return dl_m[index] if direction == NR_U_REL16_DOWNLINK else ul_m[index]
    if field == 1:
        return cw_min[index]
    if field == 2:
        return (
            dl_cw_max[index]
            if direction == NR_U_REL16_DOWNLINK
            else ul_cw_max[index]
        )
    var result = (
        dl_cot[index]
        if direction == NR_U_REL16_DOWNLINK
        else ul_cot[index]
    )
    if priority >= 3 and other_technology_absent:
        return 10000
    return result


def test_complete_dl_ul_capc_tables_external_static() raises:
    for direction in range(2):
        for priority in range(1, 5):
            for absence_int in range(2):
                var absence = absence_int == 1
                var profile = nr_u_rel16_priority_class(
                    direction, priority, absence
                )
                assert_equal(profile.direction, direction)
                assert_equal(profile.priority_class, priority)
                assert_equal(profile.other_technology_absent, absence)
                assert_equal(
                    profile.defer_slot_count,
                    _oracle_table_value(direction, priority, absence, 0),
                )
                assert_equal(
                    profile.cw_min,
                    _oracle_table_value(direction, priority, absence, 1),
                )
                assert_equal(
                    profile.cw_max,
                    _oracle_table_value(direction, priority, absence, 2),
                )
                assert_equal(
                    profile.maximum_channel_occupancy_us,
                    _oracle_table_value(direction, priority, absence, 3),
                )
                assert_equal(
                    nr_u_rel16_defer_duration_us(profile),
                    16
                    + 9
                    * _oracle_table_value(
                        direction, priority, absence, 0
                    ),
                )


def test_all_cw_sizes_backoff_and_advancement_exact() raises:
    for direction in range(2):
        for priority in range(1, 5):
            var profile = nr_u_rel16_priority_class(direction, priority)
            for candidate in range(0, 1025):
                assert_equal(
                    nr_u_rel16_contention_window_allowed(
                        profile, candidate
                    ),
                    _oracle_cw_allowed(
                        candidate, profile.cw_min, profile.cw_max
                    ),
                )
            var current = profile.cw_min
            while True:
                assert_equal(
                    nr_u_rel16_backoff_draw(profile, current, current),
                    current,
                )
                assert_equal(
                    nr_u_rel16_backoff_after_decrements(
                        profile, current, current, current // 2
                    ),
                    current - current // 2,
                )
                var expected = (
                    current if current == profile.cw_max else 2 * current + 1
                )
                assert_equal(
                    nr_u_rel16_next_higher_contention_window(
                        profile, current
                    ),
                    expected,
                )
                if current == profile.cw_max:
                    break
                current = expected


def test_maximum_cw_reset_and_cot_boundaries() raises:
    for direction in range(2):
        for priority in range(1, 5):
            for absence_int in range(2):
                var profile = nr_u_rel16_priority_class(
                    direction, priority, absence_int == 1
                )
                assert_equal(
                    nr_u_rel16_channel_occupancy_allowed(profile, 0), True
                )
                assert_equal(
                    nr_u_rel16_channel_occupancy_allowed(
                        profile, profile.maximum_channel_occupancy_us
                    ),
                    True,
                )
                assert_equal(
                    nr_u_rel16_channel_occupancy_allowed(
                        profile, profile.maximum_channel_occupancy_us + 1
                    ),
                    False,
                )

                if (
                    direction == NR_U_REL16_UPLINK
                    and priority >= 3
                    and absence_int == 0
                ):
                    assert_equal(
                        nr_u_rel16_channel_occupancy_allowed(
                            profile, 8000, 6000, 100
                        ),
                        True,
                    )
                    assert_equal(
                        nr_u_rel16_channel_occupancy_allowed(
                            profile, 8001, 6000, 100
                        ),
                        False,
                    )
                    assert_equal(
                        nr_u_rel16_channel_occupancy_allowed(
                            profile, 8000, 6001, 100
                        ),
                        False,
                    )
                    assert_equal(
                        nr_u_rel16_channel_occupancy_allowed(
                            profile, 8000, 6000, 99
                        ),
                        False,
                    )
                    assert_equal(
                        nr_u_rel16_channel_occupancy_allowed(
                            profile, 6100, 6000, 100
                        ),
                        False,
                    )
                    assert_equal(
                        nr_u_rel16_channel_occupancy_allowed(
                            profile, 6101, 6000, 100
                        ),
                        True,
                    )
                    assert_equal(
                        nr_u_rel16_channel_occupancy_allowed(
                            profile, 6101, 6000, 101
                        ),
                        False,
                    )

                for reset_count in range(1, 9):
                    var state = NRURel16ContentionWindowState(
                        profile.cw_max, 0
                    )
                    for draw_index in range(reset_count):
                        state = nr_u_rel16_record_contention_window_draw(
                            profile, state, reset_count
                        )
                        if draw_index + 1 < reset_count:
                            assert_equal(
                                state.contention_window, profile.cw_max
                            )
                            assert_equal(
                                state.consecutive_maximum_draws,
                                draw_index + 1,
                            )
                        else:
                            assert_equal(
                                state.contention_window, profile.cw_min
                            )
                            assert_equal(state.consecutive_maximum_draws, 0)


def test_note2_gap_applicability_short_gaps_and_integer_extremes() raises:
    # Non-default gap geometry belongs only to the UL p=3/4, 6-to-8-ms
    # Table-4.2.1-1 Note-2 extension.  Nominal COT checks use (-1, 0).
    var downlink = nr_u_rel16_priority_class(NR_U_REL16_DOWNLINK, 3)
    assert_equal(
        nr_u_rel16_channel_occupancy_allowed(
            downlink, 7000, 5000, 100
        ),
        False,
    )
    var uplink_p1 = nr_u_rel16_priority_class(NR_U_REL16_UPLINK, 1)
    assert_equal(
        nr_u_rel16_channel_occupancy_allowed(
            uplink_p1, 7000, 5000, 100
        ),
        False,
    )
    var uplink_p2 = nr_u_rel16_priority_class(NR_U_REL16_UPLINK, 2)
    assert_equal(
        nr_u_rel16_channel_occupancy_allowed(
            uplink_p2, 7000, 5000, 100
        ),
        False,
    )
    var absence_profile = nr_u_rel16_priority_class(
        NR_U_REL16_UPLINK, 3, True
    )
    assert_equal(
        nr_u_rel16_channel_occupancy_allowed(
            absence_profile, 8000, 6000, 100
        ),
        False,
    )

    var eligible = nr_u_rel16_priority_class(NR_U_REL16_UPLINK, 3)
    assert_equal(
        nr_u_rel16_channel_occupancy_allowed(eligible, 6000, 5000, 100),
        False,
    )
    for short_gap_us in [1, 25, 99]:
        assert_equal(
            nr_u_rel16_channel_occupancy_allowed(
                eligible, 7000, 5000, short_gap_us
            ),
            False,
        )
    assert_equal(
        nr_u_rel16_channel_occupancy_allowed(eligible, 7000, 5000, 100),
        True,
    )

    with assert_raises():
        _ = nr_u_rel16_channel_occupancy_allowed(
            eligible, Int.MIN, 5000, 100
        )
    assert_equal(
        nr_u_rel16_channel_occupancy_allowed(
            eligible, Int.MAX, 5000, 100
        ),
        False,
    )
    with assert_raises():
        _ = nr_u_rel16_channel_occupancy_allowed(
            eligible, 7000, Int.MIN, 100
        )
    assert_equal(
        nr_u_rel16_channel_occupancy_allowed(
            eligible, 7000, Int.MAX, 100
        ),
        False,
    )
    with assert_raises():
        _ = nr_u_rel16_channel_occupancy_allowed(
            eligible, 7000, 5000, Int.MIN
        )
    assert_equal(
        nr_u_rel16_channel_occupancy_allowed(
            eligible, 7000, 5000, Int.MAX
        ),
        False,
    )


def test_public_mutation_invalid_and_integer_extremes() raises:
    with assert_raises():
        _ = nr_u_rel16_priority_class(-1, 1)
    with assert_raises():
        _ = nr_u_rel16_priority_class(2, 1)
    with assert_raises():
        _ = nr_u_rel16_priority_class(0, 0)
    with assert_raises():
        _ = nr_u_rel16_priority_class(0, 5)

    var profile = nr_u_rel16_priority_class(NR_U_REL16_DOWNLINK, 3)
    profile.direction = 9
    with assert_raises():
        _ = nr_u_rel16_defer_duration_us(profile)
    profile = nr_u_rel16_priority_class(NR_U_REL16_DOWNLINK, 3)
    profile.priority_class = 4
    with assert_raises():
        _ = nr_u_rel16_channel_occupancy_allowed(profile, 1)
    profile = nr_u_rel16_priority_class(NR_U_REL16_DOWNLINK, 3)
    profile.other_technology_absent = True
    with assert_raises():
        _ = nr_u_rel16_contention_window_allowed(profile, 15)
    profile = nr_u_rel16_priority_class(NR_U_REL16_DOWNLINK, 3)
    profile.defer_slot_count = Int.MAX
    with assert_raises():
        _ = nr_u_rel16_defer_duration_us(profile)
    profile = nr_u_rel16_priority_class(NR_U_REL16_DOWNLINK, 3)
    profile.cw_min = 3
    with assert_raises():
        _ = nr_u_rel16_backoff_draw(profile, 15, 0)
    profile = nr_u_rel16_priority_class(NR_U_REL16_DOWNLINK, 3)
    profile.cw_max = Int.MAX
    with assert_raises():
        _ = nr_u_rel16_next_higher_contention_window(profile, 15)
    profile = nr_u_rel16_priority_class(NR_U_REL16_DOWNLINK, 3)
    profile.maximum_channel_occupancy_us = Int.MAX
    with assert_raises():
        _ = nr_u_rel16_channel_occupancy_allowed(profile, 1)

    profile = nr_u_rel16_priority_class(NR_U_REL16_UPLINK, 4)
    assert_equal(
        nr_u_rel16_contention_window_allowed(profile, Int.MIN), False
    )
    assert_equal(
        nr_u_rel16_contention_window_allowed(profile, Int.MAX), False
    )
    with assert_raises():
        _ = nr_u_rel16_backoff_draw(profile, profile.cw_min, Int.MIN)
    with assert_raises():
        _ = nr_u_rel16_backoff_draw(profile, profile.cw_min, Int.MAX)
    with assert_raises():
        _ = nr_u_rel16_backoff_after_decrements(
            profile, profile.cw_min, 0, Int.MIN
        )
    with assert_raises():
        _ = nr_u_rel16_backoff_after_decrements(
            profile, profile.cw_min, profile.cw_min, Int.MAX
        )
    with assert_raises():
        _ = nr_u_rel16_backoff_after_decrements(
            profile,
            profile.cw_min,
            profile.cw_min,
            profile.cw_min + 1,
        )
    assert_equal(
        nr_u_rel16_backoff_after_decrements(
            profile, profile.cw_min, profile.cw_min, profile.cw_min
        ),
        0,
    )
    with assert_raises():
        _ = nr_u_rel16_next_higher_contention_window(profile, 5)
    with assert_raises():
        _ = nr_u_rel16_channel_occupancy_allowed(profile, Int.MIN)
    assert_equal(
        nr_u_rel16_channel_occupancy_allowed(profile, Int.MAX), False
    )
    with assert_raises():
        _ = nr_u_rel16_channel_occupancy_allowed(profile, 6000, -2, 100)
    with assert_raises():
        _ = nr_u_rel16_channel_occupancy_allowed(profile, 6000, -1, 100)
    with assert_raises():
        _ = nr_u_rel16_channel_occupancy_allowed(profile, 6000, 1000, 0)
    with assert_raises():
        _ = nr_u_rel16_channel_occupancy_allowed(profile, 6000, 1000, -1)

    var bad_state = NRURel16ContentionWindowState(5, 0)
    with assert_raises():
        _ = nr_u_rel16_record_contention_window_draw(
            profile, bad_state, 1
        )
    bad_state = NRURel16ContentionWindowState(profile.cw_min, 1)
    with assert_raises():
        _ = nr_u_rel16_record_contention_window_draw(
            profile, bad_state, 1
        )
    bad_state = NRURel16ContentionWindowState(profile.cw_max, 8)
    with assert_raises():
        _ = nr_u_rel16_record_contention_window_draw(
            profile, bad_state, 8
        )
    bad_state = NRURel16ContentionWindowState(profile.cw_max, 1)
    with assert_raises():
        _ = nr_u_rel16_record_contention_window_draw(
            profile, bad_state, 1
        )
    var valid_state = NRURel16ContentionWindowState(profile.cw_max, 0)
    with assert_raises():
        _ = nr_u_rel16_record_contention_window_draw(
            profile, valid_state, 0
        )
    with assert_raises():
        _ = nr_u_rel16_record_contention_window_draw(
            profile, valid_state, 9
        )


def test_seeded_properties_against_independent_integer_oracle() raises:
    var seed = UInt64(0xA4093822299F31D0)
    for _ in range(1025):
        seed = seed * UInt64(6364136223846793005) + UInt64(1)
        var direction = Int((seed >> 3) & UInt64(1))
        var priority = 1 + Int((seed >> 9) & UInt64(3))
        var absence = ((seed >> 15) & UInt64(1)) == UInt64(1)
        var profile = nr_u_rel16_priority_class(
            direction, priority, absence
        )
        var expected_min = _oracle_table_value(
            direction, priority, absence, 1
        )
        var expected_max = _oracle_table_value(
            direction, priority, absence, 2
        )
        var expected_cot = _oracle_table_value(
            direction, priority, absence, 3
        )
        assert_equal(
            nr_u_rel16_defer_duration_us(profile),
            16
            + 9
            * _oracle_table_value(direction, priority, absence, 0),
        )

        var current = expected_min
        var advances = Int((seed >> 21) & UInt64(7))
        for _ in range(advances):
            if current < expected_max:
                current = min(2 * current + 1, expected_max)
        var draw = Int((seed >> 32) % UInt64(current + 1))
        var decrements = Int((seed >> 48) % UInt64(draw + 1))
        var expected_remaining = draw - decrements
        assert_equal(
            nr_u_rel16_contention_window_allowed(profile, current), True
        )
        assert_equal(
            nr_u_rel16_backoff_draw(profile, current, draw), draw
        )
        assert_equal(
            nr_u_rel16_backoff_after_decrements(
                profile, current, draw, decrements
            ),
            expected_remaining,
        )
        assert_equal(
            nr_u_rel16_next_higher_contention_window(profile, current),
            min(2 * current + 1, expected_max),
        )

        var occupancy = Int((seed >> 24) % UInt64(10002))
        var expected_occupancy_allowed = occupancy <= expected_cot
        assert_equal(
            nr_u_rel16_channel_occupancy_allowed(profile, occupancy),
            expected_occupancy_allowed,
        )

        if (
            direction == NR_U_REL16_UPLINK
            and priority >= 3
            and not absence
        ):
            var note2_occupancy = 6001 + Int(
                (seed >> 20) % UInt64(2000)
            )
            var note2_gap_start = Int((seed >> 5) % UInt64(6502))
            var note2_gap_duration = 1 + Int(
                (seed >> 37) % UInt64(2500)
            )
            assert_equal(
                nr_u_rel16_channel_occupancy_allowed(
                    profile,
                    note2_occupancy,
                    note2_gap_start,
                    note2_gap_duration,
                ),
                _oracle_note2_gap_extension_allowed(
                    note2_occupancy,
                    note2_gap_start,
                    note2_gap_duration,
                ),
            )

        var reset_count = 1 + Int((seed >> 12) & UInt64(7))
        var previous = Int((seed >> 5) % UInt64(reset_count))
        var state = NRURel16ContentionWindowState(expected_max, previous)
        var result = nr_u_rel16_record_contention_window_draw(
            profile, state, reset_count
        )
        if previous + 1 >= reset_count:
            assert_equal(result.contention_window, expected_min)
            assert_equal(result.consecutive_maximum_draws, 0)
        else:
            assert_equal(result.contention_window, expected_max)
            assert_equal(result.consecutive_maximum_draws, previous + 1)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
