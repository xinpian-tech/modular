from std.collections import Span
from std.testing import assert_equal, assert_true, assert_raises, TestSuite
from std.utils.numerics import inf, nan
from wireless_dsp.fec import (
    syndrome_ok,
    ldpc_decode_min_sum,
    ldpc_decode_layered_min_sum,
)


def test_layered_decoder_corrects_toy_code_and_terminates_early() raises:
    # H = [[1,1,0], [0,1,1]]; valid words are 000 and 111.
    var offsets: List[Int] = [0, 2, 4]
    var columns: List[Int] = [0, 1, 1, 2]
    var llrs: List[Float64] = [5.0, -1.0, 5.0]
    var decoded = ldpc_decode_layered_min_sum(
        Span(llrs), Span(offsets), Span(columns),
        max_iterations=10, normalization=0.8,
    )
    assert_true(decoded.converged)
    assert_true(decoded.iterations < 10)
    assert_equal(decoded.bits, [UInt8(0), UInt8(0), UInt8(0)])
    assert_true(syndrome_ok(Span(decoded.bits), Span(offsets), Span(columns)))


def test_layered_and_flooding_agree_on_deterministic_sparse_code() raises:
    # Four checks over a six-bit all-zero word, with two unreliable bits.
    var offsets: List[Int] = [0, 3, 6, 9, 12]
    var columns: List[Int] = [
        0,1,3,  1,2,4,  2,3,5,  0,4,5,
    ]
    var llrs: List[Float64] = [6.0, -0.5, 6.0, 6.0, -0.25, 6.0]
    var flooding = ldpc_decode_min_sum(
        Span(llrs), Span(offsets), Span(columns),
        max_iterations=20, normalization=0.8,
    )
    var layered = ldpc_decode_layered_min_sum(
        Span(llrs), Span(offsets), Span(columns),
        max_iterations=20, normalization=0.8,
    )
    assert_true(flooding.converged and layered.converged)
    assert_equal(layered.bits, flooding.bits)
    assert_equal(layered.bits, [UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0)])


def test_layered_numeric_validation() raises:
    var offsets: List[Int] = [0, 2]
    var columns: List[Int] = [0, 1]
    var llrs: List[Float64] = [1.0, 1.0]
    with assert_raises():
        _ = ldpc_decode_layered_min_sum(
            Span(llrs), Span(offsets), Span(columns), max_iterations=0
        )
    with assert_raises():
        _ = ldpc_decode_layered_min_sum(
            Span(llrs), Span(offsets), Span(columns),
            max_iterations=1, normalization=1.1,
        )
    with assert_raises():
        _ = ldpc_decode_layered_min_sum(
            Span(llrs), Span(offsets), Span(columns),
            max_iterations=1, normalization=nan[DType.float64](),
        )
    with assert_raises():
        _ = ldpc_decode_layered_min_sum(
            Span(llrs), Span(offsets), Span(columns),
            max_iterations=1, clip=inf[DType.float64](),
        )
    var invalid_llrs: List[Float64] = [1.0, nan[DType.float64]()]
    with assert_raises():
        _ = ldpc_decode_layered_min_sum(
            Span(invalid_llrs), Span(offsets), Span(columns),
            max_iterations=1,
        )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
