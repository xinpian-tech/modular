from std.collections import Span
from std.testing import assert_equal, assert_true, assert_raises, TestSuite
from wireless_dsp.fec import (
    polar_5g_parity_construction,
    polar_5g_encode,
    polar_5g_encode_with_parity,
    polar_5g_decode_sc_with_parity,
)


def _information_18() -> List[UInt8]:
    var result = List[UInt8](capacity=18)
    for index in range(18):
        result.append(UInt8((index * 7 + index // 3 + 1) & 1))
    return result^


def _pack_first_64(bits: Span[UInt8, ...]) -> UInt64:
    var result = UInt64(0)
    for index in range(64):
        result = (result << UInt64(1)) | UInt64(bits[index])
    return result


def _parity_positions(mask: Span[UInt8, ...]) -> List[Int]:
    var result = List[Int]()
    for index in range(len(mask)):
        if mask[index] == 1:
            result.append(index)
    return result^


def test_dynamic_pc_positions_and_independent_vectors() raises:
    var ordinary = polar_5g_parity_construction(
        18, 96, n_pc=3, n_pc_wm=0
    )
    var ordinary_expected: List[Int] = [62, 93, 103]
    assert_equal(
        _parity_positions(Span(ordinary.parity_check)),
        ordinary_expected,
    )
    var row_weight = polar_5g_parity_construction(
        18, 256, n_pc=3, n_pc_wm=1
    )
    var row_weight_expected: List[Int] = [190, 221, 252]
    assert_equal(
        _parity_positions(Span(row_weight.parity_check)),
        row_weight_expected,
    )

    var information = _information_18()
    var e96 = polar_5g_encode_with_parity(
        Span(information), 96, n_pc=3, bit_interleave=True
    )
    assert_equal(_pack_first_64(Span(e96)), UInt64(0x2EA47B5B3357F2F3))
    var e256 = polar_5g_encode_with_parity(
        Span(information), 256, n_pc=3, n_pc_wm=1,
        bit_interleave=True,
    )
    assert_equal(_pack_first_64(Span(e256)), UInt64(0x0A154A674AE04128))


def test_dynamic_pc_noiseless_sc_roundtrip() raises:
    var information = _information_18()
    for output_length in [96, 256]:
        var row_weight = 1 if output_length == 256 else 0
        var coded = polar_5g_encode_with_parity(
            Span(information), output_length, n_pc=3,
            n_pc_wm=row_weight, bit_interleave=True,
        )
        var llrs = List[Float64](capacity=len(coded))
        for bit in coded:
            llrs.append(30.0 if bit == 0 else -30.0)
        var decoded = polar_5g_decode_sc_with_parity(
            Span(llrs), len(information), n_pc=3,
            n_pc_wm=row_weight, bit_interleave=True,
        )
        assert_equal(decoded.bits, information)
        assert_true(decoded.parity_ok)


def test_zero_pc_path_is_backward_compatible() raises:
    var information: List[UInt8] = [
        1, 1, 0, 0, 1, 0, 1, 1, 0, 1, 0, 0, 1, 1, 1, 0,
        1, 0, 0, 1, 0, 1, 1, 0, 0, 1, 1, 1, 0, 1, 0, 1,
    ]
    assert_equal(
        polar_5g_encode(Span(information), 128, bit_interleave=True),
        polar_5g_encode_with_parity(
            Span(information), 128, n_pc=0, bit_interleave=True
        ),
    )


def test_dynamic_pc_validation() raises:
    with assert_raises():
        _ = polar_5g_parity_construction(18, 20, n_pc=3)
    with assert_raises():
        _ = polar_5g_parity_construction(18, 96, n_pc=3, n_pc_wm=4)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
