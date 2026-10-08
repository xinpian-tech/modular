from std.testing import assert_equal, assert_raises, assert_true, TestSuite
from std.math import isfinite
from std.utils.numerics import inf, nan
from wireless_dsp.core import (
    Complex32,
    Complex64,
    LLRBuffer,
    Span,
    StridedSpan,
    complex_mac,
)


def test_complex_arithmetic() raises:
    var a = Complex64(3.0, 4.0)
    var b = Complex64(1.0, -2.0)
    var product = a * b
    assert_equal(product.re, 11.0)
    assert_equal(product.im, -2.0)
    assert_equal(a.conjugate(), Complex64(3.0, -4.0))
    assert_equal(a.magnitude_squared(), 25.0)
    assert_equal(a.magnitude(), 5.0)


def test_complex_edge_cases() raises:
    assert_equal(Complex32(0.0, 0.0).normalized(), Complex32(0.0, 0.0))
    var unit = Complex64(3.0, 4.0).normalized()
    assert_true(abs(unit.magnitude() - 1.0) < 1.0e-12)
    assert_equal(
        complex_mac(Complex64(2.0, 1.0), Complex64(3.0, 4.0), Complex64(1.0, -2.0)),
        Complex64(13.0, -1.0),
    )


def test_complex_normalization_extreme_finite_scales() raises:
    var inverse_root_two = 0.7071067811865475244

    # Both direct squared magnitudes are respectively infinite and zero.  The
    # normalized direction remains exactly representable in either case.
    var huge = Complex64(1.0e308, -1.0e308).normalized()
    assert_true(abs(huge.re - inverse_root_two) <= 2.0e-16)
    assert_true(abs(huge.im + inverse_root_two) <= 2.0e-16)
    assert_true(abs(huge.magnitude() - 1.0) <= 2.0e-16)

    var tiny = Complex64(1.0e-308, 1.0e-308).normalized()
    assert_true(abs(tiny.re - inverse_root_two) <= 2.0e-16)
    assert_true(abs(tiny.im - inverse_root_two) <= 2.0e-16)
    assert_true(abs(tiny.magnitude() - 1.0) <= 2.0e-16)

    # Normalization is invariant to every finite, representable common scale.
    var baseline = Complex64(3.0, -4.0).normalized()
    var enlarged = Complex64(3.0e250, -4.0e250).normalized()
    var reduced = Complex64(3.0e-250, -4.0e-250).normalized()
    assert_true(abs(enlarged.re - baseline.re) <= 1.0e-15)
    assert_true(abs(enlarged.im - baseline.im) <= 1.0e-15)
    assert_true(abs(reduced.re - baseline.re) <= 1.0e-15)
    assert_true(abs(reduced.im - baseline.im) <= 1.0e-15)


def test_complex_normalization_rejects_non_finite_direction() raises:
    with assert_raises():
        _ = Complex64(nan[DType.float64](), 1.0).normalized()
    with assert_raises():
        _ = Complex64(1.0, nan[DType.float64]()).normalized()
    with assert_raises():
        _ = Complex64(inf[DType.float64](), 0.0).normalized()
    with assert_raises():
        _ = Complex64(0.0, -inf[DType.float64]()).normalized()


def test_complex_magnitude_extreme_finite_scales() raises:
    var root_two = 1.4142135623730950488
    var huge = Complex64(1.0e308, -1.0e308).magnitude()
    var tiny = Complex64(1.0e-308, -1.0e-308).magnitude()
    assert_true(isfinite(huge))
    assert_true(huge > 1.0e308)
    assert_true(abs(huge / 1.0e308 - root_two) <= 3.0e-16)
    assert_true(tiny > 1.0e-308)
    assert_true(abs(tiny / 1.0e-308 - root_two) <= 3.0e-16)

    # Squared energy has a different codomain: these exact squares cannot be
    # represented even though each corresponding Euclidean norm can be.
    assert_true(not isfinite(Complex64(1.0e308, 0.0).magnitude_squared()))
    assert_equal(Complex64(1.0e-308, 0.0).magnitude_squared(), 0.0)

    # If the norm itself exceeds Float64, magnitude preserves IEEE overflow.
    assert_true(
        not isfinite(
            Complex64(1.7976931348623157e308, 1.7976931348623157e308).magnitude()
        )
    )
    assert_true(
        not isfinite(Complex64(inf[DType.float64](), 1.0).magnitude())
    )
    assert_true(
        not isfinite(Complex64(nan[DType.float64](), 1.0).magnitude())
    )


def test_strided_span_zero_copy() raises:
    var values: List[Int] = [1, 10, 2, 20, 3, 30]
    var view = StridedSpan(unsafe_ptr=values.unsafe_ptr(), length=3, stride=2)
    assert_equal(len(view), 3)
    assert_equal(view[0], 1)
    assert_equal(view[1], 2)
    assert_equal(view[2], 3)
    view[1] = 99
    assert_equal(values[2], 99)

    var reversed = StridedSpan(
        unsafe_ptr=values.unsafe_ptr().unsafe_offset(4),
        length=3,
        stride=-2,
    )
    assert_equal(reversed[0], 3)
    assert_equal(reversed[1], 99)
    assert_equal(reversed[2], 1)

    with assert_raises():
        _ = StridedSpan(
            unsafe_ptr=values.unsafe_ptr(), length=-1, stride=1
        )
    with assert_raises():
        _ = StridedSpan(
            unsafe_ptr=values.unsafe_ptr(), length=1, stride=0
        )
    with assert_raises():
        _ = StridedSpan(
            unsafe_ptr=values.unsafe_ptr(), length=3, stride=Int.MAX
        )
    with assert_raises():
        _ = StridedSpan(
            unsafe_ptr=values.unsafe_ptr(), length=2, stride=Int.MIN
        )


def test_contiguous_span_zero_copy() raises:
    var values: List[Int] = [5, 6, 7]
    var view = Span(values)
    assert_equal(len(view), 3)
    view[1] = 42
    assert_equal(values[1], 42)


def test_llr_buffer_requires_finite_positive_scale() raises:
    var valid_values: List[Int] = [-2, 0, 2]
    var valid = LLRBuffer(valid_values^, 2.0, 2)
    var dequantized = valid.dequantize()
    assert_equal(len(dequantized), 3)
    assert_equal(dequantized[0], -1.0)
    assert_equal(dequantized[1], 0.0)
    assert_equal(dequantized[2], 1.0)

    var zero_values: List[Int] = [0]
    with assert_raises():
        _ = LLRBuffer(zero_values^, 0.0, 1)
    var negative_values: List[Int] = [0]
    with assert_raises():
        _ = LLRBuffer(negative_values^, -1.0, 1)
    var nan_values: List[Int] = [0]
    with assert_raises():
        _ = LLRBuffer(nan_values^, nan[DType.float64](), 1)
    var infinite_values: List[Int] = [0]
    with assert_raises():
        _ = LLRBuffer(infinite_values^, inf[DType.float64](), 1)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
