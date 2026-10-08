from std.collections import Span
from std.math import cos, sin
from std.testing import assert_equal, assert_true, assert_raises, TestSuite
from std.utils.numerics import nan
from wireless_dsp.core import Complex64
from wireless_dsp.dsp import (
    make_fft_plan,
    fft_in_place_with_plan,
    fft,
    ifft,
    fft_batch,
    dft_reference,
    fft_radix4,
    ifft_radix4,
)


def _values(length: Int) -> List[Complex64]:
    var result = List[Complex64](capacity=length)
    for i in range(length):
        result.append(Complex64(
            Float64((17 * i + 3) % 29) / 29.0,
            Float64((11 * i + 5) % 31) / 31.0,
        ))
    return result^


def _assert_vectors_close(
    actual: Span[Complex64, ...], expected: Span[Complex64, ...], tolerance: Float64
) raises:
    assert_equal(len(actual), len(expected))
    for i in range(len(actual)):
        assert_true(abs(actual[i].re - expected[i].re) <= tolerance)
        assert_true(abs(actual[i].im - expected[i].im) <= tolerance)


def test_reusable_plan_matches_reference_and_can_be_reapplied() raises:
    var first = _values(128)
    var second = _values(128)
    for i in range(128):
        second[i] = Complex64(-second[i].im, second[i].re)
    var first_oracle = fft(Span(first))
    var second_oracle = fft(Span(second))
    var plan = make_fft_plan(128)
    fft_in_place_with_plan(first, plan)
    fft_in_place_with_plan(second, plan)
    _assert_vectors_close(Span(first), Span(first_oracle), 1.0e-10)
    _assert_vectors_close(Span(second), Span(second_oracle), 1.0e-10)


def test_radix4_matches_radix2_and_roundtrips() raises:
    for length in [1, 4, 16, 64, 256]:
        var values = _values(length)
        var radix2 = fft(Span(values))
        var radix4 = fft_radix4(Span(values))
        _assert_vectors_close(Span(radix4), Span(radix2), 2.0e-10)
        var restored = ifft_radix4(Span(radix4))
        _assert_vectors_close(Span(restored), Span(values), 2.0e-10)


def test_radix2_all_required_ofdm_sizes_against_impulse_formula() raises:
    comptime two_pi = 6.283185307179586476925286766559
    for length in [64, 128, 256, 512, 1024, 2048, 4096]:
        var impulse = List[Complex64](
            length=length, fill=Complex64(0.0, 0.0)
        )
        impulse[1] = Complex64(1.0, 0.0)
        var spectrum = fft(Span(impulse))
        for index in range(length):
            var phase = -two_pi * Float64(index) / Float64(length)
            assert_true(abs(spectrum[index].re - cos(phase)) <= 2.0e-11)
            assert_true(abs(spectrum[index].im - sin(phase)) <= 2.0e-11)
        var restored = ifft(Span(spectrum))
        _assert_vectors_close(Span(restored), Span(impulse), 2.0e-11)


def test_arbitrary_dft_and_batched_fft_normalization() raises:
    var twelve = _values(12)
    var spectrum = dft_reference(Span(twelve))
    var restored = dft_reference(Span(spectrum), inverse=True)
    _assert_vectors_close(Span(restored), Span(twelve), 1.0e-10)

    var first = _values(64)
    var second = _values(64)
    var batches = first.copy()
    for value in second:
        batches.append(value)
    var transformed = fft_batch(Span(batches), 64)
    var expected_first = fft(Span(first))
    var expected_second = fft(Span(second))
    for i in range(64):
        assert_true(abs(transformed[i].re - expected_first[i].re) < 1.0e-10)
        assert_true(abs(transformed[64 + i].im - expected_second[i].im) < 1.0e-10)


def test_fft_variant_validation() raises:
    var eight = _values(8)
    with assert_raises():
        _ = fft_radix4(Span(eight))
    var four = _values(4)
    var wrong_plan = make_fft_plan(8)
    with assert_raises():
        fft_in_place_with_plan(four, wrong_plan)
    var short_plan = make_fft_plan(4)
    short_plan.twiddles = List[Complex64]()
    with assert_raises():
        fft_in_place_with_plan(four, short_plan)
    var nonfinite_plan = make_fft_plan(4)
    nonfinite_plan.twiddles[0] = Complex64(nan[DType.float64](), 0.0)
    with assert_raises():
        fft_in_place_with_plan(four, nonfinite_plan)
    var wrong_direction = make_fft_plan(4)
    wrong_direction.inverse = True
    with assert_raises():
        fft_in_place_with_plan(four, wrong_direction)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
