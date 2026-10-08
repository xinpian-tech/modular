"""Independent exact evidence for deterministic IEEE 802.11-2024 MAC math.

Static vectors are hand-evaluated from the Clause 9--11 integer equations and
field layouts.  The seeded properties use separate scalar transcriptions;
production TX/RX round trips are not used as an oracle.  Every result is
integral, so the declared tolerance is exact (zero).
"""

from std.collections import Span
from std.testing import assert_equal, assert_true, assert_raises, TestSuite
from wireless_dsp.wireless.wifi.mac_algorithms import (
    WIFI_SEQUENCE_MODULUS,
    WIFI_BLOCK_ACK_OLD,
    WIFI_BLOCK_ACK_IN_WINDOW,
    WIFI_BLOCK_ACK_ADVANCE_WINDOW,
    WIFI_AMSDU_SUBFRAME_HEADER_OCTETS,
    WIFI_AMPDU_DELIMITER_OCTETS,
    WIFI_AMPDU_DELIMITER_SIGNATURE,
    WifiContentionConfig,
    WifiContentionState,
    wifi_aifs_duration,
    wifi_backoff_select_slots,
    wifi_backoff_after_idle_slots,
    wifi_retry_contention_after_failure,
    wifi_retry_contention_after_success,
    wifi_nav_update_end,
    wifi_nav_remaining,
    wifi_sequence_control_pack,
    wifi_sequence_control_unpack,
    wifi_sequence_number_add,
    wifi_sequence_number_distance,
    wifi_block_ack_reorder_plan,
    wifi_amsdu_plan,
    wifi_ampdu_maximum_octets,
    wifi_ampdu_plan,
)


def _oracle_padding(length: Int) -> Int:
    var remainder = length % 4
    return 0 if remainder == 0 else 4 - remainder


def _oracle_forward_distance(start: Int, sequence: Int) -> Int:
    var distance = sequence - start
    if distance < 0:
        distance += 4096
    return distance


def _oracle_amsdu_total(lengths: Span[Int, ...]) -> Int:
    var total = 0
    for index in range(len(lengths)):
        var subframe = 14 + lengths[index]
        total += subframe
        if index + 1 != len(lengths):
            total += _oracle_padding(subframe)
    return total


def _oracle_ampdu_total(lengths: Span[Int, ...]) -> Int:
    var total = 0
    for index in range(len(lengths)):
        total += 4 + lengths[index]
        if index + 1 != len(lengths):
            total += _oracle_padding(lengths[index])
    return total


def test_mac_static_clause_vectors() raises:
    # DIFS = SIFS + 2*slot; the second row is an explicit EDCA AIFSN.
    assert_equal(wifi_aifs_duration(16, 9, 2), 34)
    assert_equal(wifi_aifs_duration(16, 9, 7), 79)
    assert_equal(
        wifi_aifs_duration(16, 9, 1, is_access_point=True), 25
    )
    var config = WifiContentionConfig(15, 1023, 7)
    var initial = WifiContentionState(15, 0)
    assert_equal(wifi_backoff_select_slots(config, initial, 11), 11)
    assert_equal(wifi_backoff_after_idle_slots(11, 4), 7)
    assert_equal(wifi_backoff_after_idle_slots(11, 12), 0)

    var failed = wifi_retry_contention_after_failure(config, initial)
    assert_equal(failed.contention_window, 31)
    assert_equal(failed.retry_count, 1)
    assert_true(not failed.discarded)
    var reset = wifi_retry_contention_after_success(config, failed)
    assert_equal(reset.contention_window, 15)
    assert_equal(reset.retry_count, 0)
    assert_true(not reset.discarded)
    var at_limit = WifiContentionState(1023, 6)
    var discarded = wifi_retry_contention_after_failure(config, at_limit)
    assert_equal(discarded.contention_window, 15)
    assert_equal(discarded.retry_count, 0)
    assert_true(discarded.discarded)

    assert_equal(wifi_nav_update_end(1000, 900, 200), 1100)
    assert_equal(wifi_nav_update_end(1200, 900, 200), 1200)
    assert_equal(wifi_nav_remaining(1000, 1100), 100)
    assert_equal(wifi_nav_remaining(1200, 1100), 0)

    assert_equal(wifi_sequence_control_pack(0xABC, 0xD), 0xABCD)
    var fields = wifi_sequence_control_unpack(0xABCD)
    assert_equal(fields.sequence_number, 0xABC)
    assert_equal(fields.fragment_number, 0xD)
    assert_equal(wifi_sequence_number_add(4094, 3), 1)
    assert_equal(wifi_sequence_number_distance(4094, 1), 3)

    var in_window = wifi_block_ack_reorder_plan(4090, 64, 2)
    assert_equal(in_window.action, WIFI_BLOCK_ACK_IN_WINDOW)
    assert_equal(in_window.previous_window_start, 4090)
    assert_equal(in_window.next_window_start, 4090)
    assert_equal(in_window.buffer_index, 8)
    var advance = wifi_block_ack_reorder_plan(4090, 64, 100)
    assert_equal(advance.action, WIFI_BLOCK_ACK_ADVANCE_WINDOW)
    assert_equal(advance.next_window_start, 37)
    assert_equal(advance.buffer_index, 63)
    var old = wifi_block_ack_reorder_plan(4090, 64, 4089)
    assert_equal(old.action, WIFI_BLOCK_ACK_OLD)
    assert_equal(old.next_window_start, 4090)
    assert_equal(old.buffer_index, -1)

    var msdu_lengths: List[Int] = [100, 101, 2304]
    var amsdu = wifi_amsdu_plan(Span(msdu_lengths), 3839)
    assert_equal(amsdu.subframe_header_offsets, [0, 116, 232])
    assert_equal(amsdu.msdu_offsets, [14, 130, 246])
    assert_equal(amsdu.padding_octets, [2, 1, 0])
    assert_equal(amsdu.total_octets, 2550)

    assert_equal(wifi_ampdu_maximum_octets(0), 8191)
    assert_equal(wifi_ampdu_maximum_octets(7), 1048575)
    var mpdu_lengths: List[Int] = [100, 101, 11454]
    var ampdu = wifi_ampdu_plan(Span(mpdu_lengths), 1)
    assert_equal(ampdu.delimiter_offsets, [0, 104, 212])
    assert_equal(ampdu.mpdu_offsets, [4, 108, 216])
    assert_equal(ampdu.padding_octets, [0, 3, 0])
    assert_equal(ampdu.delimiter_length_low_12, [100, 101, 3262])
    assert_equal(ampdu.delimiter_length_high_2, [0, 0, 2])
    assert_equal(ampdu.maximum_octets, 16383)
    assert_equal(ampdu.total_octets, 11670)
    assert_equal(WIFI_SEQUENCE_MODULUS, 4096)
    assert_equal(WIFI_AMSDU_SUBFRAME_HEADER_OCTETS, 14)
    assert_equal(WIFI_AMPDU_DELIMITER_OCTETS, 4)
    assert_equal(WIFI_AMPDU_DELIMITER_SIGNATURE, 0x4E)


def test_mac_edge_and_mutable_boundary_rejection() raises:
    with assert_raises():
        _ = wifi_aifs_duration(16, 9, 1)
    with assert_raises():
        _ = wifi_aifs_duration(16, 9, 0, is_access_point=True)
    with assert_raises():
        _ = wifi_aifs_duration(Int.MAX, Int.MAX, 15)

    var config = WifiContentionConfig(15, 1023, 7)
    var state = WifiContentionState(15, 0)
    with assert_raises():
        _ = wifi_backoff_select_slots(config, state, 16)
    config.cw_max = 1000
    with assert_raises():
        _ = wifi_backoff_select_slots(config, state, 0)
    with assert_raises():
        _ = wifi_retry_contention_after_failure(config, state)
    with assert_raises():
        _ = wifi_retry_contention_after_success(config, state)
    config.cw_max = 1023
    state.contention_window = 1000
    with assert_raises():
        _ = wifi_retry_contention_after_failure(config, state)
    state.contention_window = 15
    state.discarded = True
    state.retry_count = 1
    with assert_raises():
        _ = wifi_retry_contention_after_success(config, state)
    with assert_raises():
        _ = wifi_backoff_after_idle_slots(-1, 0)

    with assert_raises():
        _ = wifi_nav_update_end(0, Int.MAX, 1)
    with assert_raises():
        _ = wifi_nav_update_end(0, 0, 32768)
    with assert_raises():
        _ = wifi_nav_remaining(-1, 0)

    with assert_raises():
        _ = wifi_sequence_control_pack(4096, 0)
    with assert_raises():
        _ = wifi_sequence_control_pack(0, 16)
    with assert_raises():
        _ = wifi_sequence_control_unpack(65536)
    with assert_raises():
        _ = wifi_sequence_number_add(0, -1)
    with assert_raises():
        _ = wifi_sequence_number_distance(-1, 0)
    with assert_raises():
        _ = wifi_block_ack_reorder_plan(0, 0, 0)
    var half_space = wifi_block_ack_reorder_plan(0, 64, 2048)
    assert_equal(half_space.action, WIFI_BLOCK_ACK_OLD)
    assert_equal(half_space.buffer_index, -1)

    var empty = List[Int]()
    with assert_raises():
        _ = wifi_amsdu_plan(Span(empty), 3839)
    var one: List[Int] = [1]
    with assert_raises():
        _ = wifi_amsdu_plan(Span(one), 4095)
    var invalid_msdu: List[Int] = [2305]
    with assert_raises():
        _ = wifi_amsdu_plan(Span(invalid_msdu), 3839)
    var too_many_msdus: List[Int] = [2304, 2304]
    with assert_raises():
        _ = wifi_amsdu_plan(Span(too_many_msdus), 3839)

    with assert_raises():
        _ = wifi_ampdu_maximum_octets(8)
    with assert_raises():
        _ = wifi_ampdu_plan(Span(empty), 0)
    var invalid_mpdu: List[Int] = [0]
    with assert_raises():
        _ = wifi_ampdu_plan(Span(invalid_mpdu), 0)
    var over_limit: List[Int] = [8190]
    with assert_raises():
        _ = wifi_ampdu_plan(Span(over_limit), 0)


def test_seeded_mac_integer_properties() raises:
    var seed = UInt64(0x802112024C0DEC0D)
    var config = WifiContentionConfig(15, 1023, 7)
    var contention = WifiContentionState(15, 0)
    for iteration in range(257):
        seed = (
            seed * UInt64(6364136223846793005)
            + UInt64(1442695040888963407)
        )
        var sifs = Int((seed >> 8) % UInt64(1000))
        var slot = 1 + Int((seed >> 20) % UInt64(1000))
        var aifsn = 1 + Int((seed >> 32) % UInt64(15))
        assert_equal(
            wifi_aifs_duration(
                sifs, slot, aifsn, is_access_point=aifsn == 1
            ),
            sifs + aifsn * slot,
        )

        var draw = Int(seed % UInt64(contention.contention_window + 1))
        assert_equal(
            wifi_backoff_select_slots(config, contention, draw), draw
        )
        var idle = Int((seed >> 16) % UInt64(2048))
        var expected_backoff = max(0, draw - min(draw, idle))
        assert_equal(
            wifi_backoff_after_idle_slots(draw, idle), expected_backoff
        )

        var expected_retry = contention.retry_count + 1
        var expected_cw = min(2 * contention.contention_window + 1, 1023)
        var failed = wifi_retry_contention_after_failure(config, contention)
        if expected_retry == 7:
            assert_true(failed.discarded)
            assert_equal(failed.contention_window, 15)
            assert_equal(failed.retry_count, 0)
        else:
            assert_true(not failed.discarded)
            assert_equal(failed.contention_window, expected_cw)
            assert_equal(failed.retry_count, expected_retry)
        if iteration % 11 == 0:
            contention = wifi_retry_contention_after_success(config, failed)
            assert_equal(contention.contention_window, 15)
            assert_equal(contention.retry_count, 0)
        else:
            contention = failed

        var frame_start = Int((seed >> 4) % UInt64(1000000))
        var duration = Int((seed >> 40) % UInt64(32768))
        var previous_end = Int((seed >> 12) % UInt64(1000000))
        var candidate = frame_start + duration
        var nav_end = wifi_nav_update_end(
            previous_end, frame_start, duration
        )
        assert_equal(nav_end, max(previous_end, candidate))
        var now = Int((seed >> 28) % UInt64(1000000))
        assert_equal(wifi_nav_remaining(now, nav_end), max(0, nav_end - now))

        var sequence = Int((seed >> 3) & UInt64(0xFFF))
        var fragment = Int((seed >> 23) & UInt64(0xF))
        var packed = wifi_sequence_control_pack(sequence, fragment)
        assert_equal(packed, sequence * 16 + fragment)
        var unpacked = wifi_sequence_control_unpack(packed)
        assert_equal(unpacked.sequence_number, sequence)
        assert_equal(unpacked.fragment_number, fragment)
        var delta = Int((seed >> 7) % UInt64(1000000))
        var advanced = wifi_sequence_number_add(sequence, delta)
        assert_equal(advanced, (sequence + delta % 4096) % 4096)
        assert_equal(
            wifi_sequence_number_distance(sequence, advanced),
            delta % 4096,
        )

        var window_size = 1 + Int((seed >> 17) % UInt64(1024))
        var distance = Int((seed >> 29) % UInt64(2048))
        if distance == 2048:
            distance = 2047
        var received = (sequence + distance) % 4096
        var decision = wifi_block_ack_reorder_plan(
            sequence, window_size, received
        )
        if distance < window_size:
            assert_equal(decision.action, WIFI_BLOCK_ACK_IN_WINDOW)
            assert_equal(decision.buffer_index, distance)
            assert_equal(decision.next_window_start, sequence)
        else:
            assert_equal(decision.action, WIFI_BLOCK_ACK_ADVANCE_WINDOW)
            assert_equal(decision.buffer_index, window_size - 1)
            assert_equal(
                decision.next_window_start,
                (received + 4096 - (window_size - 1)) % 4096,
            )

        var msdu_lengths: List[Int] = [
            Int(seed % UInt64(512)),
            Int((seed >> 9) % UInt64(512)),
            Int((seed >> 18) % UInt64(512)),
        ]
        var amsdu = wifi_amsdu_plan(Span(msdu_lengths), 3839)
        assert_equal(amsdu.total_octets, _oracle_amsdu_total(Span(msdu_lengths)))
        for index in range(2):
            assert_equal(
                amsdu.padding_octets[index],
                _oracle_padding(14 + msdu_lengths[index]),
            )
        assert_equal(amsdu.padding_octets[2], 0)

        var mpdu_lengths: List[Int] = [
            1 + Int(seed % UInt64(1000)),
            1 + Int((seed >> 11) % UInt64(1000)),
            1 + Int((seed >> 22) % UInt64(1000)),
        ]
        assert_equal(
            wifi_ampdu_maximum_octets(iteration % 8),
            (1 << (13 + iteration % 8)) - 1,
        )
        var ampdu = wifi_ampdu_plan(Span(mpdu_lengths), 0)
        assert_equal(ampdu.total_octets, _oracle_ampdu_total(Span(mpdu_lengths)))
        for index in range(3):
            assert_equal(
                ampdu.delimiter_length_low_12[index],
                mpdu_lengths[index] & 0xFFF,
            )
            assert_equal(ampdu.delimiter_length_high_2[index], 0)


def test_independent_oracles_with_exact_zero_tolerance() raises:
    # Each assertion is bit/integer exact: tolerance_mode=exact, tolerance=0.
    var config = WifiContentionConfig(3, 15, 3)
    var state = WifiContentionState(3, 0)
    assert_equal(wifi_aifs_duration(10, 20, 3), 70)
    assert_equal(wifi_backoff_select_slots(config, state, 3), 3)
    assert_equal(wifi_backoff_after_idle_slots(3, 2), 1)
    var first_failure = wifi_retry_contention_after_failure(config, state)
    assert_equal(first_failure.contention_window, 7)
    assert_equal(first_failure.retry_count, 1)
    var success = wifi_retry_contention_after_success(config, first_failure)
    assert_equal(success.contention_window, 3)
    assert_equal(success.retry_count, 0)

    assert_equal(wifi_nav_update_end(50, 40, 15), 55)
    assert_equal(wifi_nav_remaining(51, 55), 4)
    assert_equal(wifi_sequence_control_pack(291, 4), 4660)
    var fields = wifi_sequence_control_unpack(4660)
    assert_equal(fields.sequence_number, 291)
    assert_equal(fields.fragment_number, 4)
    assert_equal(wifi_sequence_number_add(4095, 4097), 0)
    assert_equal(wifi_sequence_number_distance(4095, 0), 1)

    var plan = wifi_block_ack_reorder_plan(100, 8, 110)
    assert_equal(plan.action, WIFI_BLOCK_ACK_ADVANCE_WINDOW)
    assert_equal(plan.next_window_start, 103)
    assert_equal(plan.buffer_index, 7)

    var msdus: List[Int] = [0, 1, 2, 3]
    var amsdu = wifi_amsdu_plan(Span(msdus), 3839)
    # (14+0)+2 + (14+1)+1 + (14+2)+0 + (14+3) = 65.
    assert_equal(amsdu.padding_octets, [2, 1, 0, 0])
    assert_equal(amsdu.total_octets, 65)

    assert_equal(wifi_ampdu_maximum_octets(2), 32767)
    var mpdus: List[Int] = [1, 2, 3, 4]
    var ampdu = wifi_ampdu_plan(Span(mpdus), 0)
    # Delimiter+MPDU+non-final pad: 8 + 8 + 8 + 8 = 32 octets.
    assert_equal(ampdu.delimiter_offsets, [0, 8, 16, 24])
    assert_equal(ampdu.mpdu_offsets, [4, 12, 20, 28])
    assert_equal(ampdu.padding_octets, [3, 2, 1, 0])
    assert_equal(ampdu.total_octets, 32)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
