"""Deterministic property and independent-formula differential checks."""

from std.testing import assert_equal, assert_true, TestSuite
from wireless_dsp.core import Complex64
from wireless_dsp.numerics import Fixed

comptime Q4_4 = Fixed[4, 8]


def clamp_i8(value: Int64) -> Int64:
    if value > 127:
        return 127
    if value < -128:
        return -128
    return value


def round_q4_product(lhs: Int64, rhs: Int64) -> Int64:
    var product = lhs * rhs
    if product >= 0:
        return clamp_i8((product + 8) >> 4)
    return clamp_i8(-(((-product) + 8) >> 4))


def test_complex_differential_grid() raises:
    # A small deterministic grid catches sign/conjugation mistakes without
    # sharing the Complex multiplication implementation.
    for ar_i in range(-4, 5):
        for ai_i in range(-4, 5):
            for br_i in range(-3, 4):
                var ar = Float64(ar_i) * 0.25
                var ai = Float64(ai_i) * 0.25
                var br = Float64(br_i) * 0.5
                var bi = Float64(ar_i - br_i) * 0.125
                var got = Complex64(ar, ai) * Complex64(br, bi)
                assert_equal(got.re, ar * br - ai * bi)
                assert_equal(got.im, ar * bi + ai * br)


def test_fixed_exhaustive_local_domain() raises:
    for lhs_i in range(-32, 33):
        for rhs_i in range(-32, 33):
            var lhs_raw = Int64(lhs_i)
            var rhs_raw = Int64(rhs_i)
            var lhs = Q4_4(raw=lhs_raw)
            var rhs = Q4_4(raw=rhs_raw)
            assert_equal((lhs + rhs).raw, clamp_i8(lhs_raw + rhs_raw))
            assert_equal((lhs * rhs).raw, round_q4_product(lhs_raw, rhs_raw))


def test_complex_normalization_property() raises:
    for i in range(1, 100):
        var value = Complex64(Float64(i) * 0.125, Float64(101 - i) * -0.0625)
        var normalized = value.normalized()
        assert_true(abs(normalized.magnitude() - 1.0) < 1.0e-12)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
