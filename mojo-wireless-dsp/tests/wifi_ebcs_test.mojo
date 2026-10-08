"""Independent exact evidence for the bounded IEEE 802.11 EBCS core.

Literal complete-element vectors pin the unambiguous Mode-1 representation,
its strict-size endpoints, Element ID Extension 112, and Content-ID order.
A separate seeded oracle assembles every wire octet without calling the
serializer and checks every possible Content ID after parsing.  Timing state
is exhaustively compared with modular arithmetic.  Adversarial vectors lock
Mode 0 and equal-size choices out because the adopted Mode-0 Length clauses
conflict by one octet.  All evidence is integer/byte exact (zero tolerance).
"""

from std.collections import Span
from std.testing import assert_equal, assert_raises, assert_true, TestSuite
from wireless_dsp.wireless.wifi.ebcs import (
    WIFI_EBCS_TIM_ELEMENT_ID,
    WIFI_EBCS_TIM_ELEMENT_ID_EXTENSION,
    WIFI_EBCS_TIM_BITMAP_MODE,
    WIFI_EBCS_TIM_CONTENT_ID_LIST_MODE,
    WIFI_EBCS_CONTENT_ID_MIN,
    WIFI_EBCS_CONTENT_ID_MAX,
    WIFI_EBCS_CONTENT_ID_COUNT,
    WIFI_EBCS_TIM_VIRTUAL_BITMAP_OCTETS,
    WIFI_EBCS_TIM_MIN_CONTENT_OCTETS,
    WIFI_EBCS_TIM_MAX_CONTENT_OCTETS,
    WIFI_EBCS_TIM_MIN_STRICT_MODE_ONE_CONTENT_OCTETS,
    WIFI_EBCS_TIM_MAX_STRICT_MODE_ONE_CONTENT_OCTETS,
    WIFI_EBCS_TIM_MIN_ELEMENT_OCTETS,
    WIFI_EBCS_TIM_MAX_ELEMENT_OCTETS,
    WifiEBCSTIMConfig,
    WifiEBCSTIMContent,
    wifi_ebcs_tim_content_id_list_from_ids,
    wifi_ebcs_dtim_next_count,
    wifi_ebcs_tim_element_serialize_mode_one,
    wifi_ebcs_tim_element_parse_mode_one,
    wifi_ebcs_tim_mode_one_content_id_buffered,
)


def _assert_octets_equal(
    actual: Span[UInt8, ...], expected: Span[UInt8, ...]
) raises:
    assert_equal(len(actual), len(expected))
    for index in range(len(actual)):
        assert_equal(actual[index], expected[index])


def _copy_octets(values: Span[UInt8, ...]) -> List[UInt8]:
    var result = List[UInt8](capacity=len(values))
    for index in range(len(values)):
        result.append(values[index])
    return result^


def _oracle_contains(ids: Span[Int, ...], target: Int) -> Bool:
    for index in range(len(ids)):
        if ids[index] == target:
            return True
    return False


def _oracle_mode_one_element(
    count: Int, period: Int, ids: Span[Int, ...]
) -> List[UInt8]:
    # Direct field assembly is independent of every production serializer.
    var result = List[UInt8](capacity=6 + len(ids))
    result.append(UInt8(255))
    result.append(UInt8(4 + len(ids)))
    result.append(UInt8(112))
    result.append(UInt8(count))
    result.append(UInt8(period))
    result.append(UInt8(1))
    for index in range(len(ids)):
        result.append(UInt8(ids[index]))
    return result^


def _next_seed(seed: UInt64) -> UInt64:
    return (
        seed * UInt64(6364136223846793005)
        + UInt64(1442695040888963407)
    )


def test_static_mode_one_complete_element_vector_exact() raises:
    assert_equal(WIFI_EBCS_TIM_ELEMENT_ID, 255)
    assert_equal(WIFI_EBCS_TIM_ELEMENT_ID_EXTENSION, 112)
    assert_equal(WIFI_EBCS_TIM_BITMAP_MODE, 0)
    assert_equal(WIFI_EBCS_TIM_CONTENT_ID_LIST_MODE, 1)
    assert_equal(WIFI_EBCS_CONTENT_ID_MIN, 1)
    assert_equal(WIFI_EBCS_CONTENT_ID_MAX, 255)
    assert_equal(WIFI_EBCS_CONTENT_ID_COUNT, 255)
    assert_equal(WIFI_EBCS_TIM_VIRTUAL_BITMAP_OCTETS, 32)
    assert_equal(WIFI_EBCS_TIM_MIN_CONTENT_OCTETS, 1)
    assert_equal(WIFI_EBCS_TIM_MAX_CONTENT_OCTETS, 32)
    assert_equal(WIFI_EBCS_TIM_MIN_STRICT_MODE_ONE_CONTENT_OCTETS, 2)
    assert_equal(WIFI_EBCS_TIM_MAX_STRICT_MODE_ONE_CONTENT_OCTETS, 31)
    assert_equal(WIFI_EBCS_TIM_MIN_ELEMENT_OCTETS, 8)
    assert_equal(WIFI_EBCS_TIM_MAX_ELEMENT_OCTETS, 37)

    var ids: List[Int] = [255, 1]
    var content = wifi_ebcs_tim_content_id_list_from_ids(Span(ids))
    assert_equal(content.bitmap_mode, WIFI_EBCS_TIM_CONTENT_ID_LIST_MODE)
    assert_equal(content.bitmap_offset, 0)
    var expected_payload: List[UInt8] = [255, 1]
    _assert_octets_equal(
        Span(content.content_id_bitmap), Span(expected_payload)
    )

    var element = wifi_ebcs_tim_element_serialize_mode_one(
        WifiEBCSTIMConfig(2, 5), content
    )
    var expected: List[UInt8] = [255, 6, 112, 2, 5, 1, 255, 1]
    _assert_octets_equal(Span(element), Span(expected))

    var parsed = wifi_ebcs_tim_element_parse_mode_one(Span(element))
    assert_equal(parsed.dtim_count, 2)
    assert_equal(parsed.dtim_period, 5)
    assert_equal(parsed.bitmap_mode, 1)
    assert_equal(parsed.bitmap_offset, 0)
    _assert_octets_equal(
        Span(parsed.content_id_bitmap), Span(expected_payload)
    )
    assert_true(wifi_ebcs_tim_mode_one_content_id_buffered(parsed, 255))
    assert_true(wifi_ebcs_tim_mode_one_content_id_buffered(parsed, 1))
    assert_equal(
        wifi_ebcs_tim_mode_one_content_id_buffered(parsed, 127), False
    )


def test_strict_mode_one_length_endpoints_exact() raises:
    var minimum_ids: List[Int] = [1, 16]
    var minimum_content = wifi_ebcs_tim_content_id_list_from_ids(
        Span(minimum_ids)
    )
    var minimum_element = wifi_ebcs_tim_element_serialize_mode_one(
        WifiEBCSTIMConfig(0, 1), minimum_content
    )
    assert_equal(len(minimum_element), 8)
    assert_equal(minimum_element[1], UInt8(6))

    var maximum_ids = List[Int](capacity=31)
    maximum_ids.append(1)
    for octet_index in range(1, 30):
        maximum_ids.append(octet_index * 8)
    maximum_ids.append(255)
    assert_equal(len(maximum_ids), 31)
    var maximum_content = wifi_ebcs_tim_content_id_list_from_ids(
        Span(maximum_ids)
    )
    var maximum_element = wifi_ebcs_tim_element_serialize_mode_one(
        WifiEBCSTIMConfig(254, 255), maximum_content
    )
    assert_equal(len(maximum_element), 37)
    assert_equal(maximum_element[1], UInt8(35))
    var parsed = wifi_ebcs_tim_element_parse_mode_one(
        Span(maximum_element)
    )
    for content_id in range(1, 256):
        assert_equal(
            wifi_ebcs_tim_mode_one_content_id_buffered(
                parsed, content_id
            ),
            _oracle_contains(Span(maximum_ids), content_id),
        )


def test_countdown_exhaustive_fixed_period_oracle() raises:
    for period in range(1, 256):
        for count in range(period):
            var config = WifiEBCSTIMConfig(count, period)
            var expected = (count + period - 1) % period
            assert_equal(wifi_ebcs_dtim_next_count(config), expected)


def test_seeded_mode_one_wire_and_membership_differential() raises:
    var seed = UInt64(0x80211BC2023)
    for iteration in range(128):
        seed = _next_seed(seed)
        var target_count = 2 + Int(seed % UInt64(20))
        var selected = List[UInt8](length=256, fill=UInt8(0))
        selected[1] = 1
        selected[255] = 1
        var ids = List[Int](capacity=target_count)
        ids.append(1)
        ids.append(255)
        while len(ids) < target_count:
            seed = _next_seed(seed)
            var candidate = 2 + Int((seed >> UInt64(19)) % UInt64(253))
            if selected[candidate] == 0:
                selected[candidate] = 1
                ids.append(candidate)

        seed = _next_seed(seed)
        var period = 1 + Int(seed % UInt64(255))
        var count = Int((seed >> UInt64(17)) % UInt64(period))
        var expected = _oracle_mode_one_element(
            count, period, Span(ids)
        )
        var content = wifi_ebcs_tim_content_id_list_from_ids(Span(ids))
        var actual = wifi_ebcs_tim_element_serialize_mode_one(
            WifiEBCSTIMConfig(count, period), content
        )
        _assert_octets_equal(Span(actual), Span(expected))

        var parsed = wifi_ebcs_tim_element_parse_mode_one(Span(actual))
        assert_equal(parsed.dtim_count, count)
        assert_equal(parsed.dtim_period, period)
        for content_id in range(1, 256):
            assert_equal(
                wifi_ebcs_tim_mode_one_content_id_buffered(
                    parsed, content_id
                ),
                _oracle_contains(Span(ids), content_id),
            )
        assert_true(iteration >= 0)


def test_conflict_mutable_length_reserved_and_integer_edges() raises:
    var empty = List[Int]()
    var singleton: List[Int] = [1]
    var dense_mode_zero: List[Int] = [1, 2]
    var equal_size: List[Int] = [1, 8]
    var thirty_two_tie = List[Int](capacity=32)
    thirty_two_tie.append(1)
    for octet_index in range(1, 32):
        thirty_two_tie.append(octet_index * 8)
    var too_many = List[Int](capacity=33)
    for content_id in range(1, 34):
        too_many.append(content_id)
    with assert_raises():
        _ = wifi_ebcs_tim_content_id_list_from_ids(Span(empty))
    with assert_raises():
        _ = wifi_ebcs_tim_content_id_list_from_ids(Span(singleton))
    with assert_raises():
        _ = wifi_ebcs_tim_content_id_list_from_ids(
            Span(dense_mode_zero)
        )
    with assert_raises():
        _ = wifi_ebcs_tim_content_id_list_from_ids(Span(equal_size))
    with assert_raises():
        _ = wifi_ebcs_tim_content_id_list_from_ids(
            Span(thirty_two_tie)
        )
    with assert_raises():
        _ = wifi_ebcs_tim_content_id_list_from_ids(Span(too_many))

    var duplicate: List[Int] = [1, 255, 1]
    var zero_invalid: List[Int] = [1, 0]
    var low_invalid: List[Int] = [1, Int.MIN]
    var high_invalid: List[Int] = [1, Int.MAX]
    with assert_raises():
        _ = wifi_ebcs_tim_content_id_list_from_ids(Span(duplicate))
    with assert_raises():
        _ = wifi_ebcs_tim_content_id_list_from_ids(Span(zero_invalid))
    with assert_raises():
        _ = wifi_ebcs_tim_content_id_list_from_ids(Span(low_invalid))
    with assert_raises():
        _ = wifi_ebcs_tim_content_id_list_from_ids(Span(high_invalid))

    var mutable_ids: List[Int] = [1, 255]
    var owned = wifi_ebcs_tim_content_id_list_from_ids(Span(mutable_ids))
    mutable_ids[0] = 7
    assert_equal(owned.content_id_bitmap[0], UInt8(1))
    owned.bitmap_mode = WIFI_EBCS_TIM_BITMAP_MODE
    with assert_raises():
        _ = wifi_ebcs_tim_element_serialize_mode_one(
            WifiEBCSTIMConfig(0, 1), owned
        )
    owned.bitmap_mode = WIFI_EBCS_TIM_CONTENT_ID_LIST_MODE
    owned.bitmap_offset = 1
    with assert_raises():
        _ = wifi_ebcs_tim_element_serialize_mode_one(
            WifiEBCSTIMConfig(0, 1), owned
        )
    owned.bitmap_offset = 0
    owned.content_id_bitmap[1] = 1
    with assert_raises():
        _ = wifi_ebcs_tim_element_serialize_mode_one(
            WifiEBCSTIMConfig(0, 1), owned
        )
    owned.content_id_bitmap[1] = 0
    with assert_raises():
        _ = wifi_ebcs_tim_element_serialize_mode_one(
            WifiEBCSTIMConfig(0, 1), owned
        )

    var explicit_mode_zero: List[UInt8] = [1]
    with assert_raises():
        _ = WifiEBCSTIMContent(
            WIFI_EBCS_TIM_BITMAP_MODE, 0, explicit_mode_zero^
        )
    var explicit_tie: List[UInt8] = [1, 8]
    with assert_raises():
        _ = WifiEBCSTIMContent(
            WIFI_EBCS_TIM_CONTENT_ID_LIST_MODE, 0, explicit_tie^
        )

    for invalid_period in [Int.MIN, -1, 0, 256, Int.MAX]:
        with assert_raises():
            _ = WifiEBCSTIMConfig(0, invalid_period)
    for invalid_count in [Int.MIN, -1, 1, 256, Int.MAX]:
        with assert_raises():
            _ = WifiEBCSTIMConfig(invalid_count, 1)
    var mutable_config = WifiEBCSTIMConfig(0, 1)
    mutable_config.dtim_period = 0
    with assert_raises():
        _ = wifi_ebcs_dtim_next_count(mutable_config)

    # Both possible one-octet Mode-0 Length interpretations are rejected:
    # L=5 follows CID2068's payload=L-4; L=4 follows CID5138's formula.
    var mode_zero_l5: List[UInt8] = [255, 5, 112, 0, 1, 0, 2]
    var mode_zero_l4: List[UInt8] = [255, 4, 112, 0, 1, 0, 2]
    var mode_zero_empty_l4: List[UInt8] = [255, 4, 112, 0, 1, 0]
    # This wire has the strict Mode-1 minimum shape and an internally
    # consistent Length, so rejection must reach the explicit Mode-0 guard.
    var mode_zero_valid_shape: List[UInt8] = [255, 6, 112, 0, 1, 0, 1, 255]
    with assert_raises():
        _ = wifi_ebcs_tim_element_parse_mode_one(Span(mode_zero_l5))
    with assert_raises():
        _ = wifi_ebcs_tim_element_parse_mode_one(Span(mode_zero_l4))
    with assert_raises():
        _ = wifi_ebcs_tim_element_parse_mode_one(
            Span(mode_zero_empty_l4)
        )
    with assert_raises():
        _ = wifi_ebcs_tim_element_parse_mode_one(
            Span(mode_zero_valid_shape)
        )

    var valid: List[UInt8] = [255, 6, 112, 0, 1, 1, 1, 255]
    var parsed = wifi_ebcs_tim_element_parse_mode_one(Span(valid))
    parsed.bitmap_mode = WIFI_EBCS_TIM_BITMAP_MODE
    with assert_raises():
        _ = wifi_ebcs_tim_mode_one_content_id_buffered(parsed, 1)
    parsed.bitmap_mode = WIFI_EBCS_TIM_CONTENT_ID_LIST_MODE
    parsed.content_id_bitmap[0] = 0
    with assert_raises():
        _ = wifi_ebcs_tim_mode_one_content_id_buffered(parsed, 1)
    parsed.content_id_bitmap[0] = 1
    parsed.dtim_count = Int.MAX
    with assert_raises():
        _ = wifi_ebcs_tim_mode_one_content_id_buffered(parsed, 1)
    parsed.dtim_count = 0
    parsed.dtim_period = 0
    with assert_raises():
        _ = wifi_ebcs_tim_mode_one_content_id_buffered(parsed, 1)
    parsed.dtim_period = 1
    with assert_raises():
        _ = wifi_ebcs_tim_mode_one_content_id_buffered(parsed, 0)
    with assert_raises():
        _ = wifi_ebcs_tim_mode_one_content_id_buffered(parsed, Int.MIN)
    with assert_raises():
        _ = wifi_ebcs_tim_mode_one_content_id_buffered(parsed, Int.MAX)

    var too_short = List[UInt8](length=7, fill=UInt8(0))
    var too_long = List[UInt8](length=38, fill=UInt8(0))
    with assert_raises():
        _ = wifi_ebcs_tim_element_parse_mode_one(Span(too_short))
    with assert_raises():
        _ = wifi_ebcs_tim_element_parse_mode_one(Span(too_long))

    var wrong_id = _copy_octets(Span(valid))
    wrong_id[0] = 254
    with assert_raises():
        _ = wifi_ebcs_tim_element_parse_mode_one(Span(wrong_id))
    var wrong_length = _copy_octets(Span(valid))
    wrong_length[1] = 7
    with assert_raises():
        _ = wifi_ebcs_tim_element_parse_mode_one(Span(wrong_length))
    var wrong_extension = _copy_octets(Span(valid))
    wrong_extension[2] = 111
    with assert_raises():
        _ = wifi_ebcs_tim_element_parse_mode_one(Span(wrong_extension))
    for control in [3, 65, 129, 193]:
        var invalid_control = _copy_octets(Span(valid))
        invalid_control[5] = UInt8(control)
        with assert_raises():
            _ = wifi_ebcs_tim_element_parse_mode_one(
                Span(invalid_control)
            )

    var zero_period: List[UInt8] = [255, 6, 112, 0, 0, 1, 1, 255]
    var count_not_less: List[UInt8] = [
        255, 6, 112, 2, 2, 1, 1, 255
    ]
    var duplicate_wire: List[UInt8] = [
        255, 7, 112, 0, 1, 1, 1, 255, 1
    ]
    var mode_one_not_shorter: List[UInt8] = [
        255, 6, 112, 0, 1, 1, 1, 2
    ]
    var zero_content_id: List[UInt8] = [
        255, 6, 112, 0, 1, 1, 0, 255
    ]
    with assert_raises():
        _ = wifi_ebcs_tim_element_parse_mode_one(Span(zero_period))
    with assert_raises():
        _ = wifi_ebcs_tim_element_parse_mode_one(Span(count_not_less))
    with assert_raises():
        _ = wifi_ebcs_tim_element_parse_mode_one(Span(duplicate_wire))
    with assert_raises():
        _ = wifi_ebcs_tim_element_parse_mode_one(Span(zero_content_id))
    with assert_raises():
        _ = wifi_ebcs_tim_element_parse_mode_one(
            Span(mode_one_not_shorter)
        )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
