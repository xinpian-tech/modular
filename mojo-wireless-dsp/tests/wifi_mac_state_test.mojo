"""Independent exact evidence for bounded IEEE 802.11-2024 MAC state.

The static TIM vectors are assembled directly from the Method-A octet/AID
mapping in 9.4.2.5.1.  Seeded tests use scalar modulo and full-bitmap
oracles that do not call the production encoder.  The legacy power-save
tests cover 11.2.3 ListenInterval/ReceiveDTIMs and PS-Poll consequences.
All comparisons are discrete, so tolerance_mode is exact and tolerance is
zero.
"""

from std.collections import Span
from std.testing import assert_equal, assert_true, assert_raises, TestSuite
from wireless_dsp.wireless.wifi.mac_state import (
    WIFI_TIM_MIN_AID,
    WIFI_TIM_MAX_AID,
    WIFI_TIM_METHOD_A_MAX_OCTETS,
    WIFI_PS_LISTEN_INTERVAL_MAX,
    WIFI_PS_POLL_AID_MASK,
    WifiLegacyPowerSaveProfile,
    wifi_dtim_count_advance,
    wifi_tim_method_a_encode,
    wifi_tim_aid_buffered,
    wifi_tim_indication,
    wifi_legacy_ps_listen_required,
    wifi_legacy_ps_next_listen_tbtt,
    wifi_ps_poll_duration_id_encode,
    wifi_ps_poll_duration_id_decode,
    wifi_legacy_ps_tim_decision,
)


def _oracle_dtim_advance(count: Int, period: Int, steps: Int) -> Int:
    var result = count
    for _ in range(steps):
        result = period - 1 if result == 0 else result - 1
    return result


def _oracle_aid_bit(
    bitmap_offset: Int,
    partial_virtual_bitmap: List[UInt8],
    association_id: Int,
) -> Bool:
    # Reconstruct a complete 251-octet virtual bitmap first.  This is
    # intentionally a different organization from the production lookup.
    var complete = List[UInt8](
        length=WIFI_TIM_METHOD_A_MAX_OCTETS, fill=UInt8(0)
    )
    for index in range(len(partial_virtual_bitmap)):
        complete[bitmap_offset + index] = partial_virtual_bitmap[index]
    var octet = association_id // 8
    var bit = association_id % 8
    return (Int(complete[octet]) // (1 << bit)) % 2 == 1


def test_tim_method_a_static_clause_vectors() raises:
    var low_aids: List[Int] = [1, 7]
    var low = wifi_tim_method_a_encode(
        Span(low_aids), 0, 3, group_addressed_buffered=True
    )
    assert_equal(low.dtim_count, 0)
    assert_equal(low.dtim_period, 3)
    assert_equal(low.bitmap_control, 1)
    assert_equal(low.partial_virtual_bitmap, [UInt8(0x82)])
    assert_true(
        wifi_tim_aid_buffered(
            low.bitmap_control, Span(low.partial_virtual_bitmap), 1
        )
    )
    assert_true(
        wifi_tim_aid_buffered(
            low.bitmap_control, Span(low.partial_virtual_bitmap), 7
        )
    )
    assert_true(
        not wifi_tim_aid_buffered(
            low.bitmap_control, Span(low.partial_virtual_bitmap), 2
        )
    )

    # AID 42 is octet 5/bit 2, so even N1 is octet 4.  AID 90 is
    # octet 11/bit 2 and determines the final transmitted octet.
    var middle_aids: List[Int] = [42, 90]
    var middle = wifi_tim_method_a_encode(Span(middle_aids), 1, 4)
    assert_equal(middle.bitmap_control, 4)
    assert_equal(len(middle.partial_virtual_bitmap), 8)
    assert_equal(middle.partial_virtual_bitmap[0], 0)
    assert_equal(middle.partial_virtual_bitmap[1], 4)
    assert_equal(middle.partial_virtual_bitmap[7], 4)
    assert_true(
        wifi_tim_aid_buffered(
            middle.bitmap_control,
            Span(middle.partial_virtual_bitmap),
            42,
        )
    )
    assert_true(
        wifi_tim_aid_buffered(
            middle.bitmap_control,
            Span(middle.partial_virtual_bitmap),
            90,
        )
    )

    var final_aid: List[Int] = [2007]
    var final = wifi_tim_method_a_encode(Span(final_aid), 2, 3)
    assert_equal(final.bitmap_control, 250)
    assert_equal(final.partial_virtual_bitmap, [UInt8(0x80)])
    assert_true(
        wifi_tim_aid_buffered(
            final.bitmap_control, Span(final.partial_virtual_bitmap), 2007
        )
    )

    var none: List[Int] = []
    var empty = wifi_tim_method_a_encode(Span(none), 2, 3)
    assert_equal(empty.bitmap_control, 0)
    assert_equal(empty.partial_virtual_bitmap, [UInt8(0)])


def test_dtim_listen_and_next_tbtt_static_vectors() raises:
    assert_equal(wifi_dtim_count_advance(2, 3), 1)
    assert_equal(wifi_dtim_count_advance(1, 3), 0)
    assert_equal(wifi_dtim_count_advance(0, 3), 2)
    assert_equal(wifi_dtim_count_advance(2, 3, 4), 1)
    assert_equal(
        wifi_dtim_count_advance(2, 3, Int.MAX),
        _oracle_dtim_advance(2, 3, Int.MAX % 3),
    )

    var profile = WifiLegacyPowerSaveProfile(42, 3, 2, True)
    assert_true(not wifi_legacy_ps_listen_required(profile, 1, 1, 3))
    assert_true(wifi_legacy_ps_listen_required(profile, 2, 2, 3))
    assert_true(wifi_legacy_ps_listen_required(profile, 4, 0, 3))
    assert_true(wifi_legacy_ps_listen_required(profile, 5, 2, 3))
    assert_true(not wifi_legacy_ps_listen_required(profile, 6, 1, 3))
    assert_equal(wifi_legacy_ps_next_listen_tbtt(profile, 3, 1, 3), 4)
    assert_equal(wifi_legacy_ps_next_listen_tbtt(profile, 5, 2, 3), 5)

    profile.receive_dtims = False
    assert_true(not wifi_legacy_ps_listen_required(profile, 4, 0, 3))
    assert_equal(wifi_legacy_ps_next_listen_tbtt(profile, 3, 1, 3), 5)
    assert_equal(wifi_legacy_ps_next_listen_tbtt(profile, 6, 1, 3), 8)


def test_legacy_ps_tim_and_ps_poll_static_vectors() raises:
    var profile = WifiLegacyPowerSaveProfile(42, 3, 2, True)
    var pvb: List[UInt8] = [UInt8(0), UInt8(4)]
    var indication = wifi_tim_indication(0, 3, 5, Span(pvb), 42)
    assert_true(indication.is_dtim)
    assert_equal(indication.next_dtim_count, 2)
    assert_true(indication.individually_addressed_buffered)
    assert_true(indication.group_addressed_buffered)

    var decision = wifi_legacy_ps_tim_decision(
        profile, 4, 0, 3, 5, Span(pvb)
    )
    assert_true(decision.listen_required)
    assert_true(decision.is_dtim)
    assert_true(decision.individually_addressed_buffered)
    assert_true(decision.group_addressed_buffered)
    assert_true(decision.ps_poll_trigger_eligible)
    assert_true(decision.delivery_awake_required)
    assert_true(not decision.tim_allows_doze)

    var empty: List[UInt8] = [UInt8(0)]
    var quiet = wifi_legacy_ps_tim_decision(
        profile, 4, 0, 3, 0, Span(empty)
    )
    assert_true(quiet.listen_required)
    assert_true(not quiet.ps_poll_trigger_eligible)
    assert_true(not quiet.delivery_awake_required)
    assert_true(quiet.tim_allows_doze)

    assert_equal(wifi_ps_poll_duration_id_encode(42), 0xC02A)
    assert_equal(wifi_ps_poll_duration_id_decode(0xC02A), 42)
    assert_equal(wifi_ps_poll_duration_id_encode(2007), 0xC7D7)
    assert_equal(wifi_ps_poll_duration_id_decode(0xC7D7), 2007)


def test_mac_state_edges_overflow_and_mutable_revalidation() raises:
    with assert_raises():
        _ = wifi_dtim_count_advance(0, 0)
    with assert_raises():
        _ = wifi_dtim_count_advance(3, 3)
    with assert_raises():
        _ = wifi_dtim_count_advance(0, 1, -1)

    var none: List[Int] = []
    with assert_raises():
        _ = wifi_tim_method_a_encode(
            Span(none), 1, 3, group_addressed_buffered=True
        )
    var invalid_aids: List[Int] = [0]
    with assert_raises():
        _ = wifi_tim_method_a_encode(Span(invalid_aids), 0, 1)

    var no_octets: List[UInt8] = []
    with assert_raises():
        _ = wifi_tim_aid_buffered(0, Span(no_octets), 1)
    var too_many = List[UInt8](length=252, fill=UInt8(0))
    with assert_raises():
        _ = wifi_tim_aid_buffered(0, Span(too_many), 1)
    var beyond_end: List[UInt8] = [UInt8(0), UInt8(2)]
    with assert_raises():
        _ = wifi_tim_aid_buffered(250, Span(beyond_end), 2007)
    var aid_zero_in_pvb: List[UInt8] = [UInt8(1)]
    with assert_raises():
        _ = wifi_tim_aid_buffered(0, Span(aid_zero_in_pvb), 1)
    var empty_wrong_offset: List[UInt8] = [UInt8(0)]
    with assert_raises():
        _ = wifi_tim_aid_buffered(2, Span(empty_wrong_offset), 16)
    var leading_noncanonical: List[UInt8] = [
        UInt8(0), UInt8(0), UInt8(2)
    ]
    with assert_raises():
        _ = wifi_tim_aid_buffered(0, Span(leading_noncanonical), 17)
    var trailing_noncanonical: List[UInt8] = [UInt8(2), UInt8(0)]
    with assert_raises():
        _ = wifi_tim_aid_buffered(0, Span(trailing_noncanonical), 1)
    var canonical_empty: List[UInt8] = [UInt8(0)]
    with assert_raises():
        _ = wifi_tim_indication(1, 3, 1, Span(canonical_empty), 1)
    with assert_raises():
        _ = wifi_tim_aid_buffered(-1, Span(canonical_empty), 1)
    with assert_raises():
        _ = wifi_tim_aid_buffered(0, Span(canonical_empty), 2008)

    with assert_raises():
        _ = wifi_ps_poll_duration_id_encode(0)
    with assert_raises():
        _ = wifi_ps_poll_duration_id_decode(0x802A)
    with assert_raises():
        _ = wifi_ps_poll_duration_id_decode(0xFFFF)
    with assert_raises():
        _ = wifi_ps_poll_duration_id_decode(65536)

    var profile = WifiLegacyPowerSaveProfile(42, 3, 2, False)
    profile.association_id = 0
    with assert_raises():
        _ = wifi_legacy_ps_listen_required(profile, 2, 0, 3)
    with assert_raises():
        _ = wifi_legacy_ps_tim_decision(
            profile, 2, 0, 3, 0, Span(canonical_empty)
        )
    profile.association_id = 42
    profile.listen_interval_beacons = 0
    with assert_raises():
        _ = wifi_legacy_ps_next_listen_tbtt(profile, 2, 0, 3)
    profile.listen_interval_beacons = WIFI_PS_LISTEN_INTERVAL_MAX + 1
    with assert_raises():
        _ = wifi_legacy_ps_listen_required(profile, 2, 0, 3)
    profile.listen_interval_beacons = 3
    profile.listen_anchor_tbtt = -1
    with assert_raises():
        _ = wifi_legacy_ps_listen_required(profile, 2, 0, 3)
    profile.listen_anchor_tbtt = Int.MAX - 1
    with assert_raises():
        _ = wifi_legacy_ps_next_listen_tbtt(profile, Int.MAX, 0, 3)
    profile.listen_anchor_tbtt = 0
    with assert_raises():
        _ = wifi_legacy_ps_listen_required(profile, -1, 0, 3)


def test_seeded_tim_dtim_and_listen_properties() raises:
    var seed = UInt64(0xA0761D6478BD642F)
    for iteration in range(512):
        seed ^= seed << 13
        seed ^= seed >> 7
        seed ^= seed << 17
        var association_id = 1 + Int(seed % UInt64(WIFI_TIM_MAX_AID))
        var aids: List[Int] = [association_id, association_id]
        var element = wifi_tim_method_a_encode(
            Span(aids), iteration % 5, 5
        )
        var global_octet = association_id // 8
        var expected_offset = global_octet & ~1
        assert_equal(element.bitmap_control, expected_offset)
        assert_equal(
            len(element.partial_virtual_bitmap),
            global_octet - expected_offset + 1,
        )
        assert_true(
            wifi_tim_aid_buffered(
                element.bitmap_control,
                Span(element.partial_virtual_bitmap),
                association_id,
            )
        )
        var other = 1 + (association_id % WIFI_TIM_MAX_AID)
        assert_equal(
            wifi_tim_aid_buffered(
                element.bitmap_control,
                Span(element.partial_virtual_bitmap),
                other,
            ),
            other == association_id,
        )

        var period = 1 + Int((seed >> 11) % UInt64(31))
        var count = Int((seed >> 19) % UInt64(period))
        var steps = Int((seed >> 27) % UInt64(256))
        assert_equal(
            wifi_dtim_count_advance(count, period, steps),
            _oracle_dtim_advance(count, period, steps),
        )

        var interval = 1 + Int((seed >> 35) % UInt64(63))
        var anchor = Int((seed >> 43) % UInt64(256))
        var tbtt = Int((seed >> 51) % UInt64(512))
        var receive_dtims = (seed & 1) != 0
        var profile = WifiLegacyPowerSaveProfile(
            association_id, interval, anchor, receive_dtims
        )
        var expected = (
            (receive_dtims and count == 0)
            or (tbtt >= anchor and (tbtt - anchor) % interval == 0)
        )
        assert_equal(
            wifi_legacy_ps_listen_required(
                profile, tbtt, count, period
            ),
            expected,
        )

        var periodic = anchor
        if tbtt > anchor:
            var delta = tbtt - anchor
            var intervals = delta // interval
            if delta % interval != 0:
                intervals += 1
            periodic = anchor + intervals * interval
        var expected_next = periodic
        if receive_dtims and tbtt + count < expected_next:
            expected_next = tbtt + count
        assert_equal(
            wifi_legacy_ps_next_listen_tbtt(
                profile, tbtt, count, period
            ),
            expected_next,
        )

        var indication = wifi_tim_indication(
            element.dtim_count,
            element.dtim_period,
            element.bitmap_control,
            Span(element.partial_virtual_bitmap),
            association_id,
        )
        assert_equal(indication.is_dtim, element.dtim_count == 0)
        assert_equal(
            indication.next_dtim_count,
            _oracle_dtim_advance(
                element.dtim_count, element.dtim_period, 1
            ),
        )
        assert_true(indication.individually_addressed_buffered)
        assert_true(not indication.group_addressed_buffered)

        var decision = wifi_legacy_ps_tim_decision(
            profile,
            tbtt,
            element.dtim_count,
            element.dtim_period,
            element.bitmap_control,
            Span(element.partial_virtual_bitmap),
        )
        var decision_listen = (
            (receive_dtims and element.dtim_count == 0)
            or (tbtt >= anchor and (tbtt - anchor) % interval == 0)
        )
        assert_equal(decision.listen_required, decision_listen)
        assert_equal(decision.is_dtim, element.dtim_count == 0)
        assert_true(decision.individually_addressed_buffered)
        assert_true(not decision.group_addressed_buffered)
        assert_true(decision.ps_poll_trigger_eligible)
        assert_true(decision.delivery_awake_required)
        assert_true(not decision.tim_allows_doze)


def test_independent_full_bitmap_and_exhaustive_exact_oracles() raises:
    # Full-bitmap reconstruction is independent of the production's direct
    # offset-window lookup.  First and last octets are nonzero, making this
    # a canonical maximum-size Method-A PVB.
    var pvb = List[UInt8](
        length=WIFI_TIM_METHOD_A_MAX_OCTETS, fill=UInt8(0)
    )
    for index in range(WIFI_TIM_METHOD_A_MAX_OCTETS):
        pvb[index] = UInt8((37 * index + 0x5A) & 0xFF)
    pvb[0] &= UInt8(0xFE)
    pvb[WIFI_TIM_METHOD_A_MAX_OCTETS - 1] |= UInt8(0x80)
    for association_id in range(WIFI_TIM_MIN_AID, WIFI_TIM_MAX_AID + 1):
        assert_equal(
            wifi_tim_aid_buffered(0, Span(pvb), association_id),
            _oracle_aid_bit(0, pvb, association_id),
        )
        var duration_id = WIFI_PS_POLL_AID_MASK + association_id
        assert_equal(
            wifi_ps_poll_duration_id_encode(association_id), duration_id
        )
        assert_equal(
            wifi_ps_poll_duration_id_decode(duration_id), association_id
        )

    for period in range(1, 33):
        for count in range(period):
            for steps in range(2 * period + 1):
                assert_equal(
                    wifi_dtim_count_advance(count, period, steps),
                    _oracle_dtim_advance(count, period, steps),
                )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
