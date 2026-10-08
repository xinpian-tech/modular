"""Independent exact, edge, and property evidence for Rel-17 NR MBS."""

from std.testing import assert_equal, assert_raises, TestSuite
from wireless_dsp.wireless.nr.mbs_rel17 import (
    NR_MBS_PROFILE_ORDINARY_NR,
    NR_MBS_PROFILE_LATER_RELEASE,
    NR_MBS_REL17_MAX_RESOURCE_BLOCKS,
    NR_MBS_REL17_LOCATION_AND_BANDWIDTH_MAX,
    NR_MBS_REL17_MCCH_RNTI,
    NR_MBS_BROADCAST_CFR_ABSENT_CORESET0,
    NR_MBS_BROADCAST_CFR_SAME_AS_INITIAL_BWP,
    NR_MBS_BROADCAST_CFR_EXPLICIT_RIV,
    NRMBSRel17CFR,
    nr_mbs_rel17_multicast_cfr,
    nr_mbs_rel17_broadcast_cfr,
    nr_mbs_rel17_dci_4_0_payload_bits,
    nr_mbs_rel17_dci_4_1_payload_bits,
    nr_mbs_rel17_mcch_change_notification,
    nr_mbs_rel17_nack_only_pucch_resource,
    nr_mbs_rel17_sps_occasion_slot,
    nr_mbs_rel17_sps_harq_process_id,
)


def _encode_riv_exhaustive_integer_oracle(
    start_prb: Int, size_prbs: Int
) -> Int:
    # Independent transmitter-side integer transcription of the TS 38.214 RIV
    # equation; production implements receiver-side inversion instead.  The
    # test exhausts every legal allocation rather than loading a static fixture.
    if size_prbs - 1 <= NR_MBS_REL17_MAX_RESOURCE_BLOCKS // 2:
        return (
            NR_MBS_REL17_MAX_RESOURCE_BLOCKS * (size_prbs - 1)
            + start_prb
        )
    return (
        NR_MBS_REL17_MAX_RESOURCE_BLOCKS
        * (NR_MBS_REL17_MAX_RESOURCE_BLOCKS - size_prbs + 1)
        + (NR_MBS_REL17_MAX_RESOURCE_BLOCKS - 1 - start_prb)
    )


def _assert_cfr(
    value: NRMBSRel17CFR, expected_start: Int, expected_size: Int
) raises:
    assert_equal(value.start_prb, expected_start)
    assert_equal(value.size_prbs, expected_size)
    assert_equal(value.end_prb_exclusive(), expected_start + expected_size)


def test_cfr_all_37950_riv_allocations_and_presence_choices() raises:
    var visited = List[UInt8](
        length=NR_MBS_REL17_LOCATION_AND_BANDWIDTH_MAX + 1, fill=0
    )
    var allocation_count = 0
    for size_prbs in range(1, NR_MBS_REL17_MAX_RESOURCE_BLOCKS + 1):
        for start_prb in range(
            NR_MBS_REL17_MAX_RESOURCE_BLOCKS - size_prbs + 1
        ):
            var riv = _encode_riv_exhaustive_integer_oracle(
                start_prb, size_prbs
            )
            assert_equal(visited[riv], 0)
            visited[riv] = 1
            var decoded = nr_mbs_rel17_multicast_cfr(
                True,
                riv,
                0,
                NR_MBS_REL17_MAX_RESOURCE_BLOCKS,
            )
            _assert_cfr(decoded, start_prb, size_prbs)
            allocation_count += 1
    assert_equal(allocation_count, 37950)
    for riv in range(len(visited)):
        assert_equal(visited[riv], 1)

    _assert_cfr(nr_mbs_rel17_multicast_cfr(False, 0, 20, 80), 20, 80)
    _assert_cfr(
        nr_mbs_rel17_multicast_cfr(
            True, _encode_riv_exhaustive_integer_oracle(32, 48), 20, 80
        ),
        32,
        48,
    )

    _assert_cfr(
        nr_mbs_rel17_broadcast_cfr(
            NR_MBS_BROADCAST_CFR_ABSENT_CORESET0,
            0,
            40,
            48,
            48,
            24,
        ),
        48,
        24,
    )
    _assert_cfr(
        nr_mbs_rel17_broadcast_cfr(
            NR_MBS_BROADCAST_CFR_SAME_AS_INITIAL_BWP,
            0,
            40,
            48,
            48,
            24,
        ),
        40,
        48,
    )
    _assert_cfr(
        nr_mbs_rel17_broadcast_cfr(
            NR_MBS_BROADCAST_CFR_EXPLICIT_RIV,
            _encode_riv_exhaustive_integer_oracle(32, 80),
            40,
            48,
            48,
            24,
        ),
        32,
        80,
    )


def test_cfr_mutation_presence_containment_and_integer_edges() raises:
    var value = NRMBSRel17CFR(274, 1)
    assert_equal(value.end_prb_exclusive(), 275)
    value.size_prbs = Int.MAX
    with assert_raises():
        _ = value.end_prb_exclusive()
    value = NRMBSRel17CFR(0, 1)
    value.start_prb = Int.MIN
    with assert_raises():
        value.validate()

    with assert_raises():
        _ = nr_mbs_rel17_multicast_cfr(False, 1, 0, 275)
    with assert_raises():
        _ = nr_mbs_rel17_multicast_cfr(True, Int.MIN, 0, 275)
    with assert_raises():
        _ = nr_mbs_rel17_multicast_cfr(True, Int.MAX, 0, 275)
    with assert_raises():
        _ = nr_mbs_rel17_multicast_cfr(
            True, _encode_riv_exhaustive_integer_oracle(0, 20), 10, 40
        )
    with assert_raises():
        _ = nr_mbs_rel17_broadcast_cfr(99, 0, 40, 48, 48, 24)
    with assert_raises():
        _ = nr_mbs_rel17_broadcast_cfr(
            NR_MBS_BROADCAST_CFR_SAME_AS_INITIAL_BWP,
            1,
            40,
            48,
            48,
            24,
        )
    with assert_raises():
        _ = nr_mbs_rel17_broadcast_cfr(
            NR_MBS_BROADCAST_CFR_EXPLICIT_RIV,
            _encode_riv_exhaustive_integer_oracle(40, 48),
            40,
            48,
            48,
            24,
        )
    with assert_raises():
        _ = nr_mbs_rel17_broadcast_cfr(
            NR_MBS_BROADCAST_CFR_EXPLICIT_RIV,
            _encode_riv_exhaustive_integer_oracle(32, 64),
            40,
            48,
            90,
            16,
        )


def test_dci_4_0_and_4_1_clause_static_boundaries() raises:
    # Independent exact boundary values for ceil(log2(N*(N+1)/2)) + 28.
    var sizes: List[Int] = [
        1, 2, 3, 4, 5, 6, 10, 11, 15, 16, 22, 23, 31, 32, 44, 45,
        63, 64, 90, 91, 127, 128, 180, 181, 255, 256, 275,
    ]
    var expected: List[Int] = [
        28, 30, 31, 32, 32, 33, 34, 35, 35, 36, 36, 37, 37, 38,
        38, 39, 39, 40, 40, 41, 41, 42, 42, 43, 43, 44, 44,
    ]
    for index in range(len(sizes)):
        assert_equal(
            nr_mbs_rel17_dci_4_0_payload_bits(False, 0, sizes[index]),
            expected[index],
        )
        assert_equal(
            nr_mbs_rel17_dci_4_1_payload_bits(True, sizes[index], 275),
            expected[index],
        )

    var previous = 0
    for size_prbs in range(1, 276):
        var bits = nr_mbs_rel17_dci_4_0_payload_bits(
            True, size_prbs, 275
        )
        assert_equal(bits >= previous, True)
        assert_equal(bits >= 28 and bits <= 44, True)
        assert_equal(
            nr_mbs_rel17_dci_4_1_payload_bits(True, size_prbs, 275), bits
        )
        previous = bits

    with assert_raises():
        _ = nr_mbs_rel17_dci_4_0_payload_bits(False, 1, 20)
    with assert_raises():
        _ = nr_mbs_rel17_dci_4_1_payload_bits(True, 0, 20)
    with assert_raises():
        _ = nr_mbs_rel17_dci_4_0_payload_bits(True, 276, 20)
    with assert_raises():
        _ = nr_mbs_rel17_dci_4_1_payload_bits(False, 0, Int.MAX)


def _check_pucch_literal_table(expected: Span[Int, ...]) raises:
    var bit_count = 0
    var entries = len(expected)
    while (1 << bit_count) < entries:
        bit_count += 1
    for pattern in range(entries):
        var bits = List[Int](capacity=bit_count)
        for bit_index in range(bit_count):
            bits.append((pattern >> bit_index) & 1)
        assert_equal(
            nr_mbs_rel17_nack_only_pucch_resource(bits, True),
            expected[pattern],
        )


def test_mcch_bitmap_and_table_18_1_all_rows_exact() raises:
    var notification = nr_mbs_rel17_mcch_change_notification(0)
    assert_equal(notification.new_service_started, False)
    assert_equal(notification.other_mcch_information_modified, False)
    notification = nr_mbs_rel17_mcch_change_notification(1)
    assert_equal(notification.new_service_started, False)
    assert_equal(notification.other_mcch_information_modified, True)
    notification = nr_mbs_rel17_mcch_change_notification(2)
    assert_equal(notification.new_service_started, True)
    assert_equal(notification.other_mcch_information_modified, False)
    notification = nr_mbs_rel17_mcch_change_notification(3)
    assert_equal(notification.new_service_started, True)
    assert_equal(notification.other_mcch_information_modified, True)
    assert_equal(NR_MBS_REL17_MCCH_RNTI, 0xFFFD)

    # Literal Table 18-1 rows in pattern order; the all-ACK final entry for
    # each width is the normative no-transmission result zero.
    var one: List[Int] = [1, 0]
    var two: List[Int] = [1, 2, 3, 0]
    var three: List[Int] = [1, 2, 3, 4, 5, 6, 7, 0]
    var four: List[Int] = [
        1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 0,
    ]
    _check_pucch_literal_table(one)
    _check_pucch_literal_table(two)
    _check_pucch_literal_table(three)
    _check_pucch_literal_table(four)

    with assert_raises():
        _ = nr_mbs_rel17_mcch_change_notification(-1)
    with assert_raises():
        _ = nr_mbs_rel17_mcch_change_notification(Int.MAX)
    with assert_raises():
        _ = nr_mbs_rel17_mcch_change_notification(0, 0x1234)
    var empty = List[Int]()
    with assert_raises():
        _ = nr_mbs_rel17_nack_only_pucch_resource(empty, True)
    var too_many: List[Int] = [0, 0, 0, 0, 0]
    with assert_raises():
        _ = nr_mbs_rel17_nack_only_pucch_resource(too_many, True)
    var invalid: List[Int] = [0, 2]
    with assert_raises():
        _ = nr_mbs_rel17_nack_only_pucch_resource(invalid, True)
    var valid: List[Int] = [0]
    with assert_raises():
        _ = nr_mbs_rel17_nack_only_pucch_resource(valid, False)


def test_sps_occurrence_and_harq_static_clause_oracles() raises:
    assert_equal(nr_mbs_rel17_sps_occasion_slot(0, 0, 0, 10, 10), 0)
    assert_equal(nr_mbs_rel17_sps_occasion_slot(7, 3, 5, 20, 16), 223)
    assert_equal(
        nr_mbs_rel17_sps_occasion_slot(1023, 19, 1, 20, 20), 19
    )
    assert_equal(
        nr_mbs_rel17_sps_occasion_slot(1023, 19, 1024, 20, 20), 20479
    )

    # CURRENT_slot=2005, floor(2005/20)=100, 100 mod 8=4.
    assert_equal(nr_mbs_rel17_sps_harq_process_id(100, 5, 20, 20, 8), 4)
    assert_equal(
        nr_mbs_rel17_sps_harq_process_id(100, 5, 20, 20, 8, 8), 12
    )
    assert_equal(nr_mbs_rel17_sps_harq_process_id(1023, 79, 80, 1, 32), 31)


def test_sps_seeded_properties_against_independent_integer_oracle() raises:
    var allowed_slots_per_frame: List[Int] = [10, 20, 40, 80]
    var seed = UInt64(0x243F6A8885A308D3)
    for _ in range(513):
        seed = seed * UInt64(6364136223846793005) + UInt64(1)
        var slots_per_frame = allowed_slots_per_frame[
            Int(seed % UInt64(len(allowed_slots_per_frame)))
        ]
        var sfn = Int((seed >> 8) % UInt64(1024))
        var slot = Int((seed >> 20) % UInt64(slots_per_frame))
        var period = 1 + Int((seed >> 32) % UInt64(64 * slots_per_frame))
        var occurrence = Int((seed >> 48) & UInt64(0xFFFF))
        var cycle = 1024 * slots_per_frame

        # Independent bounded UInt64 transmitter-side modular arithmetic.
        var expected_slot = Int(
            (
                UInt64(sfn * slots_per_frame + slot)
                + UInt64(occurrence) * UInt64(period)
            ) % UInt64(cycle)
        )
        assert_equal(
            nr_mbs_rel17_sps_occasion_slot(
                sfn, slot, occurrence, slots_per_frame, period
            ),
            expected_slot,
        )

        var processes = 1 + Int((seed >> 12) % UInt64(32))
        var offset = Int((seed >> 4) % UInt64(33 - processes))
        var current_slot = sfn * slots_per_frame + slot
        # Float64 division is exact over this bounded integer domain and is
        # independent of production's integer quotient implementation.
        var quotient = Int(Float64(current_slot) / Float64(period))
        var expected_process = quotient % processes + offset
        assert_equal(
            nr_mbs_rel17_sps_harq_process_id(
                sfn,
                slot,
                slots_per_frame,
                period,
                processes,
                offset,
            ),
            expected_process,
        )


def test_all_public_profile_and_sps_extreme_edges() raises:
    var nack: List[Int] = [0]
    with assert_raises():
        _ = nr_mbs_rel17_multicast_cfr(
            False, 0, 0, 20, profile=NR_MBS_PROFILE_ORDINARY_NR
        )
    with assert_raises():
        _ = nr_mbs_rel17_broadcast_cfr(
            NR_MBS_BROADCAST_CFR_ABSENT_CORESET0,
            0,
            0,
            20,
            0,
            20,
            profile=NR_MBS_PROFILE_LATER_RELEASE,
        )
    with assert_raises():
        _ = nr_mbs_rel17_dci_4_0_payload_bits(
            False, 0, 20, profile=NR_MBS_PROFILE_ORDINARY_NR
        )
    with assert_raises():
        _ = nr_mbs_rel17_dci_4_1_payload_bits(
            False, 0, 20, profile=NR_MBS_PROFILE_LATER_RELEASE
        )
    with assert_raises():
        _ = nr_mbs_rel17_mcch_change_notification(
            0, profile=NR_MBS_PROFILE_ORDINARY_NR
        )
    with assert_raises():
        _ = nr_mbs_rel17_nack_only_pucch_resource(
            nack, True, profile=NR_MBS_PROFILE_LATER_RELEASE
        )
    with assert_raises():
        _ = nr_mbs_rel17_sps_occasion_slot(
            0, 0, 0, 10, 10, profile=NR_MBS_PROFILE_ORDINARY_NR
        )
    with assert_raises():
        _ = nr_mbs_rel17_sps_harq_process_id(
            0, 0, 10, 10, 1, profile=NR_MBS_PROFILE_LATER_RELEASE
        )

    with assert_raises():
        _ = nr_mbs_rel17_sps_occasion_slot(0, 0, -1, 10, 10)
    with assert_raises():
        _ = nr_mbs_rel17_sps_occasion_slot(0, 0, 0, 160, 10)
    with assert_raises():
        _ = nr_mbs_rel17_sps_occasion_slot(1024, 0, 0, 10, 10)
    with assert_raises():
        _ = nr_mbs_rel17_sps_occasion_slot(0, 10, 0, 10, 10)
    with assert_raises():
        _ = nr_mbs_rel17_sps_occasion_slot(0, 0, 0, 10, 641)
    with assert_raises():
        _ = nr_mbs_rel17_sps_harq_process_id(0, 0, 10, 1, 0)
    with assert_raises():
        _ = nr_mbs_rel17_sps_harq_process_id(0, 0, 10, 1, 33)
    with assert_raises():
        _ = nr_mbs_rel17_sps_harq_process_id(0, 0, 10, 1, 8, 25)

    var expected = Int(
        (
            Int128(Int.MAX) * Int128(80)
        ) % Int128(1024 * 80)
    )
    assert_equal(
        nr_mbs_rel17_sps_occasion_slot(0, 0, Int.MAX, 80, 80),
        expected,
    )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
