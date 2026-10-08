"""Independent evidence for Matter 1.6 anonymous integer TLV elements.

The six static integer vectors are transcribed from Appendix A, Table 127 of
the official June 16, 2026 Matter R1.6 PDF (SHA-256
``48b3b117569f72558ba71813360d77abdfa11fcf28747bd269148104936b52b7``).
Test-local base-256 writers are independent of production.  Production
encode/decode round trips appear only as a property check, never as the oracle
for an example, boundary, or differential assertion.
"""

from std.collections import Span
from std.testing import TestSuite, assert_equal, assert_raises
from wireless_dsp.wireless.matter.tlv_integer import (
    matter_tlv_encode_signed_integer,
    matter_tlv_decode_signed_integer,
    matter_tlv_encode_unsigned_integer,
    matter_tlv_decode_unsigned_integer,
)


def _width_code(width: Int) -> UInt8:
    if width == 1:
        return UInt8(0)
    if width == 2:
        return UInt8(1)
    if width == 4:
        return UInt8(2)
    return UInt8(3)


def _control_width(control: Int) -> Int:
    var code = control & 3
    if code == 0:
        return 1
    if code == 1:
        return 2
    if code == 2:
        return 4
    return 8


def _oracle_base256(value: UInt64, width: Int, control: UInt8) -> List[UInt8]:
    # Repeated Euclidean base-256 decomposition, deliberately distinct from
    # production's shifted word writer.
    var result = List[UInt8](capacity=width + 1)
    result.append(control)
    var remaining = value
    for _ in range(width):
        var quotient = remaining // UInt64(256)
        result.append(UInt8(remaining - quotient * UInt64(256)))
        remaining = quotient
    return result^


def _oracle_signed(value: Int64, width: Int) -> List[UInt8]:
    return _oracle_base256(UInt64(value), width, _width_code(width))


def _oracle_unsigned(value: UInt64, width: Int) -> List[UInt8]:
    return _oracle_base256(value, width, UInt8(4) + _width_code(width))


def _prefix(values: Span[UInt8, ...], length: Int) -> List[UInt8]:
    var result = List[UInt8](capacity=length)
    for index in range(length):
        result.append(values[index])
    return result^


def _assert_signed_static(
    value: Int64, width: Int, expected: List[UInt8]
) raises:
    assert_equal(matter_tlv_encode_signed_integer(value, width), expected)
    var decoded = matter_tlv_decode_signed_integer(Span(expected))
    assert_equal(decoded.value, value)
    assert_equal(decoded.width, width)


def _assert_unsigned_static(
    value: UInt64, width: Int, expected: List[UInt8]
) raises:
    assert_equal(matter_tlv_encode_unsigned_integer(value, width), expected)
    var decoded = matter_tlv_decode_unsigned_integer(Span(expected))
    assert_equal(decoded.value, value)
    assert_equal(decoded.width, width)


def _assert_signed_oracle(value: Int64, width: Int) raises:
    var oracle = _oracle_signed(value, width)
    assert_equal(matter_tlv_encode_signed_integer(value, width), oracle)
    var decoded = matter_tlv_decode_signed_integer(Span(oracle))
    assert_equal(decoded.value, value)
    assert_equal(decoded.width, width)


def _assert_unsigned_oracle(value: UInt64, width: Int) raises:
    var oracle = _oracle_unsigned(value, width)
    assert_equal(matter_tlv_encode_unsigned_integer(value, width), oracle)
    var decoded = matter_tlv_decode_unsigned_integer(Span(oracle))
    assert_equal(decoded.value, value)
    assert_equal(decoded.width, width)


def test_appendix_a_table_127_all_six_integer_vectors() raises:
    var signed_42_1: List[UInt8] = [0x00, 0x2A]
    var signed_minus_17: List[UInt8] = [0x00, 0xEF]
    var unsigned_42: List[UInt8] = [0x04, 0x2A]
    var signed_42_2: List[UInt8] = [0x01, 0x2A, 0x00]
    var signed_minus_170000: List[UInt8] = [0x02, 0xF0, 0x67, 0xFD, 0xFF]
    var signed_40000000000: List[UInt8] = [
        0x03,
        0x00,
        0x90,
        0x2F,
        0x50,
        0x09,
        0x00,
        0x00,
        0x00,
    ]
    _assert_signed_static(Int64(42), 1, signed_42_1)
    _assert_signed_static(Int64(-17), 1, signed_minus_17)
    _assert_unsigned_static(UInt64(42), 1, unsigned_42)
    _assert_signed_static(Int64(42), 2, signed_42_2)
    _assert_signed_static(Int64(-170000), 4, signed_minus_170000)
    _assert_signed_static(Int64(40000000000), 8, signed_40000000000)


def test_one_octet_signed_and_unsigned_full_domains() raises:
    for numeric in range(-128, 128):
        _assert_signed_oracle(Int64(numeric), 1)
    for numeric in range(256):
        _assert_unsigned_oracle(UInt64(numeric), 1)


def test_all_width_endpoints_and_nonminimal_encodings() raises:
    _assert_signed_oracle(Int64(-128), 1)
    _assert_signed_oracle(Int64(127), 1)
    _assert_signed_oracle(Int64(-32768), 2)
    _assert_signed_oracle(Int64(32767), 2)
    _assert_signed_oracle(Int64(-2147483648), 4)
    _assert_signed_oracle(Int64(2147483647), 4)
    _assert_signed_oracle(Int64.MIN_FINITE, 8)
    _assert_signed_oracle(Int64.MAX_FINITE, 8)

    _assert_unsigned_oracle(UInt64(0), 1)
    _assert_unsigned_oracle(UInt64(0xFF), 1)
    _assert_unsigned_oracle(UInt64(0), 2)
    _assert_unsigned_oracle(UInt64(0xFFFF), 2)
    _assert_unsigned_oracle(UInt64(0), 4)
    _assert_unsigned_oracle(UInt64(0xFFFFFFFF), 4)
    _assert_unsigned_oracle(UInt64(0), 8)
    _assert_unsigned_oracle(UInt64.MAX, 8)

    # A.11.1 makes width a sender choice.  These legal non-minimal forms must
    # retain their actual encoded width instead of being rejected or shrunk.
    for width in [2, 4, 8]:
        _assert_signed_oracle(Int64(42), width)
        _assert_signed_oracle(Int64(-17), width)
        _assert_unsigned_oracle(UInt64(42), width)


def test_all_256_control_octets_exact_type_and_anonymous_tag_domain() raises:
    for raw_control in range(256):
        var width = _control_width(raw_control)
        var candidate = List[UInt8](capacity=width + 1)
        candidate.append(UInt8(raw_control))
        for _ in range(width):
            candidate.append(UInt8(0))

        if raw_control < 4:
            var signed = matter_tlv_decode_signed_integer(Span(candidate))
            assert_equal(signed.value, Int64(0))
            assert_equal(signed.width, width)
        else:
            with assert_raises():
                _ = matter_tlv_decode_signed_integer(Span(candidate))

        if raw_control >= 4 and raw_control < 8:
            var unsigned = matter_tlv_decode_unsigned_integer(Span(candidate))
            assert_equal(unsigned.value, UInt64(0))
            assert_equal(unsigned.width, width)
        else:
            with assert_raises():
                _ = matter_tlv_decode_unsigned_integer(Span(candidate))


def test_exact_length_truncation_trailing_and_cross_type_rejection() raises:
    var empty = List[UInt8]()
    with assert_raises():
        _ = matter_tlv_decode_signed_integer(Span(empty))
    with assert_raises():
        _ = matter_tlv_decode_unsigned_integer(Span(empty))

    for width in [1, 2, 4, 8]:
        var signed = _oracle_signed(Int64(-1), width)
        var signed_truncated = _prefix(Span(signed), len(signed) - 1)
        var signed_trailing = signed.copy()
        signed_trailing.append(UInt8(0))
        with assert_raises():
            _ = matter_tlv_decode_signed_integer(Span(signed_truncated))
        with assert_raises():
            _ = matter_tlv_decode_signed_integer(Span(signed_trailing))
        with assert_raises():
            _ = matter_tlv_decode_unsigned_integer(Span(signed))

        var unsigned = _oracle_unsigned(UInt64(1), width)
        var unsigned_truncated = _prefix(Span(unsigned), len(unsigned) - 1)
        var unsigned_trailing = unsigned.copy()
        unsigned_trailing.append(UInt8(0))
        with assert_raises():
            _ = matter_tlv_decode_unsigned_integer(Span(unsigned_truncated))
        with assert_raises():
            _ = matter_tlv_decode_unsigned_integer(Span(unsigned_trailing))
        with assert_raises():
            _ = matter_tlv_decode_signed_integer(Span(unsigned))


def test_encode_width_and_value_domains_include_integer_extrema() raises:
    for invalid_width in [0, 3, 5, 7, 9, Int.MIN, Int.MAX]:
        with assert_raises():
            _ = matter_tlv_encode_signed_integer(Int64(0), invalid_width)
        with assert_raises():
            _ = matter_tlv_encode_unsigned_integer(UInt64(0), invalid_width)

    with assert_raises():
        _ = matter_tlv_encode_signed_integer(Int64(-129), 1)
    with assert_raises():
        _ = matter_tlv_encode_signed_integer(Int64(128), 1)
    with assert_raises():
        _ = matter_tlv_encode_signed_integer(Int64(-32769), 2)
    with assert_raises():
        _ = matter_tlv_encode_signed_integer(Int64(32768), 2)
    with assert_raises():
        _ = matter_tlv_encode_signed_integer(Int64(-2147483649), 4)
    with assert_raises():
        _ = matter_tlv_encode_signed_integer(Int64(2147483648), 4)
    with assert_raises():
        _ = matter_tlv_encode_unsigned_integer(UInt64(0x100), 1)
    with assert_raises():
        _ = matter_tlv_encode_unsigned_integer(UInt64(0x10000), 2)
    with assert_raises():
        _ = matter_tlv_encode_unsigned_integer(UInt64(0x100000000), 4)

    _assert_signed_oracle(Int64.MIN_FINITE, 8)
    _assert_signed_oracle(Int64.MAX_FINITE, 8)
    _assert_unsigned_oracle(UInt64.MAX, 8)


def test_mutable_input_is_revalidated_on_every_decode() raises:
    var signed = _oracle_signed(Int64(-17), 1)
    var decoded_signed = matter_tlv_decode_signed_integer(Span(signed))
    assert_equal(decoded_signed.value, Int64(-17))
    signed[0] = UInt8(0x20)
    with assert_raises():
        _ = matter_tlv_decode_signed_integer(Span(signed))
    signed[0] = UInt8(0x00)
    signed.append(UInt8(0))
    with assert_raises():
        _ = matter_tlv_decode_signed_integer(Span(signed))

    var unsigned = _oracle_unsigned(UInt64(42), 1)
    var decoded_unsigned = matter_tlv_decode_unsigned_integer(Span(unsigned))
    assert_equal(decoded_unsigned.value, UInt64(42))
    unsigned[0] = UInt8(0x24)
    with assert_raises():
        _ = matter_tlv_decode_unsigned_integer(Span(unsigned))
    unsigned[0] = UInt8(0x04)
    unsigned.append(UInt8(0))
    with assert_raises():
        _ = matter_tlv_decode_unsigned_integer(Span(unsigned))


def test_seeded_production_roundtrip_property_only() raises:
    var state = UInt64(0xD1B54A32D192ED03)
    for index in range(128):
        state = state * UInt64(6364136223846793005) + UInt64(
            1442695040888963407
        )
        var magnitude = Int64(state & UInt64(0x7FFFFFFFFFFFFFFF))
        var signed_value = -magnitude if index & 1 else magnitude
        var signed_encoded = matter_tlv_encode_signed_integer(signed_value, 8)
        var signed_decoded = matter_tlv_decode_signed_integer(
            Span(signed_encoded)
        )
        assert_equal(signed_decoded.value, signed_value)
        assert_equal(signed_decoded.width, 8)

        var unsigned_encoded = matter_tlv_encode_unsigned_integer(state, 8)
        var unsigned_decoded = matter_tlv_decode_unsigned_integer(
            Span(unsigned_encoded)
        )
        assert_equal(unsigned_decoded.value, state)
        assert_equal(unsigned_decoded.width, 8)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
