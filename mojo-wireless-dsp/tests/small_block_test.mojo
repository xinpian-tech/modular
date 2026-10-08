from std.collections import Span
from std.testing import assert_equal, assert_true, assert_raises, TestSuite
from wireless_dsp.fec import (
    nr_small_block_basis_bit,
    nr_small_block_encode,
    nr_small_block_rate_match,
    nr_small_block_rate_recover_llrs,
    nr_small_block_decode_ml,
)


def _pack32(bits: Span[UInt8, ...]) -> UInt32:
    var result = UInt32(0)
    for index in range(len(bits)):
        result = (result << UInt32(1)) | UInt32(bits[index])
    return result


def _pattern(length: Int, salt: Int) -> List[UInt8]:
    var result = List[UInt8](capacity=length)
    for index in range(length):
        result.append(UInt8(((index * 5 + salt * 3 + index * salt) >> 1) & 1))
    return result^


def test_normative_basis_and_static_codewords() raises:
    # Direct rows from TS 38.212 Table 5.3.3.3-1.
    var first: List[UInt8] = [1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 1]
    var last: List[UInt8] = [1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
    for column in range(11):
        assert_equal(nr_small_block_basis_bit(0, column), first[column])
        assert_equal(nr_small_block_basis_bit(31, column), last[column])

    var three: List[UInt8] = [1, 0, 1]
    assert_equal(_pack32(Span(nr_small_block_encode(Span(three)))), UInt32(0xA58F7641))
    var seven: List[UInt8] = [1, 0, 1, 1, 0, 1, 0]
    assert_equal(_pack32(Span(nr_small_block_encode(Span(seven)))), UInt32(0x9C7CE289))
    var eleven: List[UInt8] = [1, 0, 1, 1, 0, 1, 0, 0, 1, 1, 1]
    assert_equal(_pack32(Span(nr_small_block_encode(Span(eleven)))), UInt32(0x36762BC7))


def test_linearity_for_all_supported_information_lengths() raises:
    for length in range(3, 12):
        var a = _pattern(length, 1)
        var b = _pattern(length, 4)
        var ab = List[UInt8](capacity=length)
        for index in range(length):
            ab.append(a[index] ^ b[index])
        var encoded_a = nr_small_block_encode(Span(a))
        var encoded_b = nr_small_block_encode(Span(b))
        var encoded_ab = nr_small_block_encode(Span(ab))
        for index in range(32):
            assert_equal(encoded_ab[index], encoded_a[index] ^ encoded_b[index])


def test_rate_matching_recovery_and_soft_ml_decode() raises:
    var information: List[UInt8] = [1, 0, 1, 1, 0, 0, 1, 0, 1]
    var codeword = nr_small_block_encode(Span(information))
    var matched = nr_small_block_rate_match(Span(codeword), 77)
    for index in range(77):
        assert_equal(matched[index], codeword[index % 32])
    var llrs = List[Float64](capacity=77)
    for index in range(77):
        var magnitude = 2.0 + Float64(index % 5) * 0.25
        llrs.append(magnitude if matched[index] == 0 else -magnitude)
    # One deliberately wrong soft sample must be corrected by code distance.
    llrs[9] = -llrs[9]
    var decoded = nr_small_block_decode_ml(Span(llrs), len(information))
    assert_equal(decoded.bits, information)
    assert_true(decoded.margin > 0.0)

    var recovered = nr_small_block_rate_recover_llrs(Span(llrs))
    for index in range(32):
        var expected = 0.0
        var source = index
        while source < len(llrs):
            expected += llrs[source]
            source += 32
        assert_equal(recovered[index], expected)


def test_deterministic_property_decode_across_k() raises:
    for length in range(3, 12):
        for salt in range(5):
            var information = _pattern(length, salt)
            var codeword = nr_small_block_encode(Span(information))
            var llrs = List[Float64](capacity=32)
            for bit in codeword:
                llrs.append(7.0 if bit == 0 else -7.0)
            var decoded = nr_small_block_decode_ml(Span(llrs), length)
            assert_equal(decoded.bits, information)
            assert_true(decoded.margin > 0.0)


def test_small_block_validation() raises:
    var too_short: List[UInt8] = [0, 1]
    with assert_raises():
        _ = nr_small_block_encode(Span(too_short))
    var invalid: List[UInt8] = [0, 2, 1]
    with assert_raises():
        _ = nr_small_block_encode(Span(invalid))
    var valid: List[UInt8] = [0, 1, 1]
    var codeword = nr_small_block_encode(Span(valid))
    with assert_raises():
        _ = nr_small_block_rate_match(Span(codeword), 0)
    var empty = List[Float64]()
    with assert_raises():
        _ = nr_small_block_decode_ml(Span(empty), 3)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
