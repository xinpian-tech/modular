from std.testing import assert_equal, assert_true, assert_raises, TestSuite
from wireless_dsp.core import Span
from wireless_dsp.backend.cpu import (
    simd_sum_f32,
    simd_dot_f32,
    simd_energy_f32,
    simd_complex_dot_split_f32,
)


def test_simd_reductions_match_independent_scalar_loops() raises:
    var lhs = List[Float32](capacity=1031)
    var rhs = List[Float32](capacity=1031)
    var sum_reference = Float32(0.0)
    var dot_reference = Float32(0.0)
    var energy_reference = Float32(0.0)
    for i in range(1031):
        var a = Float32((i % 31) - 15) * 0.03125
        var b = Float32((i % 17) - 8) * 0.0625
        lhs.append(a)
        rhs.append(b)
        sum_reference += a
        dot_reference += a * b
        energy_reference += a * a
    assert_true(abs(simd_sum_f32(Span(lhs)) - sum_reference) < 2.0e-5)
    assert_true(abs(simd_dot_f32(Span(lhs), Span(rhs)) - dot_reference) < 2.0e-5)
    assert_true(abs(simd_energy_f32(Span(lhs)) - energy_reference) < 2.0e-5)


def test_simd_split_complex_dot_matches_known_vector() raises:
    var ar: List[Float32] = [1.0, 2.0, -1.0, 0.5, 3.0]
    var ai: List[Float32] = [2.0, -1.0, 0.5, 1.5, -2.0]
    var br: List[Float32] = [-1.0, 0.5, 2.0, 1.0, -0.5]
    var bi: List[Float32] = [0.5, 2.0, -1.0, 0.0, 1.0]
    var reference_re = Float32(0.0)
    var reference_im = Float32(0.0)
    for i in range(len(ar)):
        reference_re += ar[i] * br[i] + ai[i] * bi[i]
        reference_im += ar[i] * bi[i] - ai[i] * br[i]
    var actual = simd_complex_dot_split_f32(Span(ar), Span(ai), Span(br), Span(bi))
    assert_true(abs(actual.re - reference_re) < 1.0e-5)
    assert_true(abs(actual.im - reference_im) < 1.0e-5)


def test_simd_reduction_edges_and_validation() raises:
    var empty = List[Float32]()
    assert_equal(simd_sum_f32(Span(empty)), Float32(0.0))
    assert_equal(simd_energy_f32(Span(empty)), Float32(0.0))
    var one: List[Float32] = [1.0]
    with assert_raises():
        _ = simd_dot_f32(Span(empty), Span(one))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
