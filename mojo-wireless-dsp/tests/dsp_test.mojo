from std.testing import assert_equal, assert_true, assert_raises, TestSuite
from std.utils.numerics import inf, nan
from std.utils.numerics import inf, nan
from wireless_dsp.core import Complex64, Span
from wireless_dsp.dsp import (
    sum_real,
    dot_real,
    energy_real,
    dot_complex,
    energy_complex,
    argmax_real,
    min_real,
    max_real,
    min1_min2,
    sign_product,
    fft,
    ifft,
    fir_real,
    fir_complex,
    fir_real_chunk,
    fir_complex_chunk,
    convolve_real,
    cross_correlate_complex,
    normalized_correlation_at,
    normalized_cross_correlate_complex,
    correlation_peak,
    autocorrelate_complex,
    autocorrelation_sequence,
    window_energy,
    sliding_window_energy,
    correlation_phase,
)


def assert_complex_close(actual: Complex64, expected: Complex64, tolerance: Float64) raises:
    assert_true(abs(actual.re - expected.re) <= tolerance)
    assert_true(abs(actual.im - expected.im) <= tolerance)


def test_reductions() raises:
    var real: List[Float64] = [1.0, -2.0, 3.0, 4.0]
    var real_copy: List[Float64] = [1.0, -2.0, 3.0, 4.0]
    assert_equal(sum_real(Span(real)), 6.0)
    assert_equal(dot_real(Span(real), Span(real_copy)), 30.0)
    assert_equal(energy_real(Span(real)), 30.0)
    assert_equal(argmax_real(Span(real)), 3)
    assert_equal(min_real(Span(real)), -2.0)
    assert_equal(max_real(Span(real)), 4.0)
    var first, second, index = min1_min2(Span(real))
    assert_equal(first, -2.0)
    assert_equal(second, 1.0)
    assert_equal(index, 1)
    assert_equal(sign_product(Span(real)), -1)

    var huge: List[Float64] = [1.5e308, 1.0e308, 1.25e308]
    var huge_first, huge_second, huge_index = min1_min2(Span(huge))
    assert_equal(huge_first, 1.0e308)
    assert_equal(huge_second, 1.25e308)
    assert_equal(huge_index, 1)

    var equal: List[Float64] = [3.0, 3.0, 4.0]
    var equal_first, equal_second, equal_index = min1_min2(Span(equal))
    assert_equal(equal_first, 3.0)
    assert_equal(equal_second, 3.0)
    assert_equal(equal_index, 0)

    var nonfinite: List[Float64] = [1.0, inf[DType.float64]()]
    with assert_raises():
        _ = min1_min2(Span(nonfinite))
    nonfinite[1] = nan[DType.float64]()
    with assert_raises():
        _ = min1_min2(Span(nonfinite))
    var complex: List[Complex64] = [Complex64(1.0, 2.0), Complex64(3.0, -1.0)]
    var complex_copy: List[Complex64] = [Complex64(1.0, 2.0), Complex64(3.0, -1.0)]
    assert_complex_close(dot_complex(Span(complex), Span(complex_copy)), Complex64(15.0, 0.0), 1.0e-12)
    assert_equal(energy_complex(Span(complex)), 15.0)


def test_reduction_errors() raises:
    var one: List[Float64] = [1.0]
    var two: List[Float64] = [1.0, 2.0]
    with assert_raises():
        _ = dot_real(Span(one), Span(two))
    var empty = List[Float64]()
    with assert_raises():
        _ = argmax_real(Span(empty))


def test_fft_impulse_and_roundtrip() raises:
    var impulse: List[Complex64] = [
        Complex64(1.0, 0.0),
        Complex64(0.0, 0.0),
        Complex64(0.0, 0.0),
        Complex64(0.0, 0.0),
    ]
    var spectrum = fft(Span(impulse))
    for i in range(4):
        assert_complex_close(spectrum[i], Complex64(1.0, 0.0), 1.0e-12)
    var restored = ifft(Span(spectrum))
    for i in range(4):
        assert_complex_close(restored[i], impulse[i], 1.0e-12)


def test_fft_rejects_non_power_of_two() raises:
    var values: List[Complex64] = [Complex64(1.0), Complex64(2.0), Complex64(3.0)]
    with assert_raises():
        _ = fft(Span(values))


def test_fir_and_convolution() raises:
    var signal: List[Float64] = [1.0, 2.0, 3.0]
    var taps: List[Float64] = [1.0, -1.0]
    var filtered = fir_real(Span(signal), Span(taps))
    assert_equal(filtered, [1.0, 1.0, 1.0])
    var convolution = convolve_real(Span(signal), Span(taps))
    assert_equal(convolution, [1.0, 1.0, 1.0, -3.0])
    var first_input: List[Float64] = [1.0, 2.0]
    var second_input: List[Float64] = [3.0]
    var initial_history: List[Float64] = [0.0]
    var first_output = fir_real_chunk(Span(first_input), Span(taps), initial_history)
    var second_output = fir_real_chunk(Span(second_input), Span(taps), initial_history)
    assert_equal(first_output, [1.0, 1.0])
    assert_equal(second_output, [1.0])


def test_complex_fir() raises:
    var signal: List[Complex64] = [Complex64(1.0, 1.0), Complex64(2.0, 0.0)]
    var taps: List[Complex64] = [Complex64(0.0, 1.0)]
    var output = fir_complex(Span(signal), Span(taps))
    assert_complex_close(output[0], Complex64(-1.0, 1.0), 1.0e-12)
    assert_complex_close(output[1], Complex64(0.0, 2.0), 1.0e-12)
    var history: List[Complex64] = []
    var streamed = fir_complex_chunk(Span(signal), Span(taps), history)
    assert_equal(streamed, output)


def test_correlation_peak_and_normalization() raises:
    var reference: List[Complex64] = [Complex64(1.0, 0.0), Complex64(0.0, 1.0)]
    var signal: List[Complex64] = [
        Complex64(0.0, 0.0),
        Complex64(2.0, 0.0),
        Complex64(0.0, 2.0),
        Complex64(0.0, 0.0),
    ]
    var correlation = cross_correlate_complex(Span(signal), Span(reference))
    assert_equal(correlation_peak(Span(correlation)), 1)
    assert_complex_close(correlation[1], Complex64(4.0, 0.0), 1.0e-12)
    assert_complex_close(
        normalized_correlation_at(Span(signal), Span(reference), 1),
        Complex64(1.0, 0.0),
        1.0e-12,
    )
    assert_equal(window_energy(Span(signal), 1, 2), 8.0)
    assert_complex_close(autocorrelate_complex(Span(reference), 0), Complex64(2.0), 1.0e-12)
    assert_true(abs(correlation_phase(Complex64(0.0, 1.0)) - 1.5707963267948966) < 1.0e-12)
    var normalized = normalized_cross_correlate_complex(
        Span(signal), Span(reference)
    )
    assert_equal(correlation_peak(Span(normalized)), 1)
    assert_complex_close(normalized[1], Complex64(1.0), 1.0e-12)
    var auto_sequence = autocorrelation_sequence(
        Span(reference), 1, normalized=True
    )
    assert_complex_close(auto_sequence[0], Complex64(1.0), 1.0e-12)
    assert_equal(sliding_window_energy(Span(signal), 2), [4.0, 8.0, 4.0])


def test_normalized_correlation_extreme_finite_scales() raises:
    # These closed-form one-sample cases exercise both overflow and underflow
    # paths without deriving the expectation through production arithmetic.
    var huge_signal: List[Complex64] = [Complex64(1.0e200, 1.0e200)]
    var huge_reference: List[Complex64] = [Complex64(1.0e200, 1.0e200)]
    assert_complex_close(
        normalized_correlation_at(
            Span(huge_signal), Span(huge_reference), 0
        ),
        Complex64(1.0, 0.0),
        2.0e-15,
    )

    var tiny_signal: List[Complex64] = [Complex64(1.0e-300, 1.0e-300)]
    var tiny_reference: List[Complex64] = [Complex64(1.0e-300, -1.0e-300)]
    assert_complex_close(
        normalized_correlation_at(
            Span(tiny_signal), Span(tiny_reference), 0
        ),
        Complex64(0.0, 1.0),
        2.0e-15,
    )

    var zero: List[Complex64] = [
        Complex64(0.0, 0.0), Complex64(-0.0, 0.0)
    ]
    var finite: List[Complex64] = [
        Complex64(2.0, -3.0), Complex64(-1.0, 4.0)
    ]
    assert_equal(
        normalized_correlation_at(Span(zero), Span(finite), 0),
        Complex64(0.0, 0.0),
    )
    assert_equal(
        normalized_correlation_at(Span(finite), Span(zero), 0),
        Complex64(0.0, 0.0),
    )


def test_normalized_correlation_amplitude_and_phase_invariance() raises:
    var signal: List[Complex64] = [
        Complex64(1.0, 2.0),
        Complex64(-3.0, 0.5),
        Complex64(0.25, -1.5),
    ]
    var reference: List[Complex64] = [
        Complex64(-0.5, 1.0),
        Complex64(2.0, -0.75),
        Complex64(1.25, 0.5),
    ]
    var baseline = normalized_correlation_at(
        Span(signal), Span(reference), 0
    )

    var rescaled_signal: List[Complex64] = [
        Complex64(1.0e200, 2.0e200),
        Complex64(-3.0e200, 0.5e200),
        Complex64(0.25e200, -1.5e200),
    ]
    var rescaled_reference: List[Complex64] = [
        Complex64(-0.5e-200, 1.0e-200),
        Complex64(2.0e-200, -0.75e-200),
        Complex64(1.25e-200, 0.5e-200),
    ]
    var rescaled = normalized_correlation_at(
        Span(rescaled_signal), Span(rescaled_reference), 0
    )
    assert_complex_close(rescaled, baseline, 2.0e-15)

    # Rotating only the signal by +pi/2 rotates the complex correlation by
    # the same amount: (a + jb) -> (-b + ja).
    var rotated_signal: List[Complex64] = [
        Complex64(-2.0, 1.0),
        Complex64(-0.5, -3.0),
        Complex64(1.5, 0.25),
    ]
    var rotated = normalized_correlation_at(
        Span(rotated_signal), Span(reference), 0
    )
    assert_complex_close(
        rotated, Complex64(-baseline.im, baseline.re), 2.0e-15
    )


def test_normalized_correlation_rejects_non_finite_samples() raises:
    var valid: List[Complex64] = [Complex64(1.0, -1.0)]
    var nan_signal: List[Complex64] = [
        Complex64(nan[DType.float64](), 0.0)
    ]
    var nan_reference: List[Complex64] = [
        Complex64(0.0, nan[DType.float64]())
    ]
    var infinite_signal: List[Complex64] = [
        Complex64(inf[DType.float64](), 0.0)
    ]
    var infinite_reference: List[Complex64] = [
        Complex64(0.0, -inf[DType.float64]())
    ]
    with assert_raises():
        _ = normalized_correlation_at(Span(nan_signal), Span(valid), 0)
    with assert_raises():
        _ = normalized_correlation_at(Span(valid), Span(nan_reference), 0)
    with assert_raises():
        _ = normalized_correlation_at(Span(infinite_signal), Span(valid), 0)
    with assert_raises():
        _ = normalized_correlation_at(Span(valid), Span(infinite_reference), 0)


def test_unnormalized_correlation_extreme_contracts() raises:
    var huge = 1.0e200

    # The individual direct products overflow with opposite signs, but the
    # exact cross-correlation cancels and is representable as zero.
    var cancelling_signal: List[Complex64] = [
        Complex64(huge, 0.0), Complex64(-huge, 0.0)
    ]
    var huge_reference: List[Complex64] = [
        Complex64(huge, 0.0), Complex64(huge, 0.0)
    ]
    var cancelled = cross_correlate_complex(
        Span(cancelling_signal), Span(huge_reference)
    )
    assert_equal(cancelled, [Complex64(0.0, 0.0)])

    # A non-cancelling 1e400 result has no Float64 representation.
    var one_huge: List[Complex64] = [Complex64(huge, 0.0)]
    var one_huge_reference: List[Complex64] = [Complex64(huge, 0.0)]
    with assert_raises():
        _ = cross_correlate_complex(
            Span(one_huge), Span(one_huge_reference)
        )

    var invalid: List[Complex64] = [
        Complex64(nan[DType.float64](), 0.0)
    ]
    with assert_raises():
        _ = cross_correlate_complex(Span(invalid), Span(one_huge))


def test_correlation_peak_extreme_scale_ranking() raises:
    var huge_values: List[Complex64] = [
        Complex64(1.0e308, 0.0),
        Complex64(1.0e308, 1.0e308),
        Complex64(0.5e308, 0.5e308),
    ]
    assert_equal(correlation_peak(Span(huge_values)), 1)

    var tiny_values: List[Complex64] = [
        Complex64(1.0e-308, 0.0),
        Complex64(1.0e-308, 1.0e-308),
    ]
    assert_equal(correlation_peak(Span(tiny_values)), 1)

    var invalid: List[Complex64] = [
        Complex64(1.0, 0.0), Complex64(inf[DType.float64](), 0.0)
    ]
    with assert_raises():
        _ = correlation_peak(Span(invalid))


def test_autocorrelation_extreme_scale_contracts() raises:
    var huge = 1.0e200
    var cancellation: List[Complex64] = [
        Complex64(huge, 0.0),
        Complex64(huge, 0.0),
        Complex64(-huge, 0.0),
    ]
    assert_equal(
        autocorrelate_complex(Span(cancellation), 1),
        Complex64(0.0, 0.0),
    )
    with assert_raises():
        _ = autocorrelate_complex(Span(cancellation), 0)

    var alternating: List[Complex64] = [
        Complex64(huge, 0.0), Complex64(-huge, 0.0)
    ]
    var normalized = autocorrelation_sequence(
        Span(alternating), 1, normalized=True
    )
    assert_complex_close(normalized[0], Complex64(1.0, 0.0), 0.0)
    assert_complex_close(normalized[1], Complex64(-0.5, 0.0), 0.0)

    var all_zero: List[Complex64] = [Complex64(0.0), Complex64(0.0)]
    with assert_raises():
        _ = autocorrelation_sequence(Span(all_zero), 1, normalized=True)

    var invalid: List[Complex64] = [
        Complex64(1.0, 0.0), Complex64(nan[DType.float64](), 0.0)
    ]
    with assert_raises():
        _ = autocorrelate_complex(Span(invalid), 1)
    with assert_raises():
        _ = autocorrelation_sequence(Span(invalid), 1, normalized=True)


def test_window_energy_extreme_scale_contracts() raises:
    var representable: List[Complex64] = [
        Complex64(1.0e150, 0.0), Complex64(2.0e150, 0.0)
    ]
    var energies = sliding_window_energy(Span(representable), 1)
    assert_true(abs(energies[0] / 1.0e300 - 1.0) <= 2.0e-16)
    assert_true(abs(energies[1] / 1.0e300 - 4.0) <= 8.0e-16)
    assert_true(
        abs(window_energy(Span(representable), 0, 2) / 1.0e300 - 5.0)
        <= 1.0e-15
    )

    # A running subtract/add loses the unit energy hidden beside 1e200 in the
    # first window.  Every reference window must instead retain its own scale.
    var cancellation: List[Complex64] = [
        Complex64(1.0e100, 0.0),
        Complex64(1.0, 0.0),
        Complex64(1.0, 0.0),
    ]
    assert_equal(
        sliding_window_energy(Span(cancellation), 2),
        [1.0e200, 2.0],
    )

    var overflow: List[Complex64] = [Complex64(1.0e200, 0.0)]
    with assert_raises():
        _ = window_energy(Span(overflow), 0, 1)
    with assert_raises():
        _ = sliding_window_energy(Span(overflow), 1)

    var underflow: List[Complex64] = [Complex64(1.0e-200, 0.0)]
    with assert_raises():
        _ = window_energy(Span(underflow), 0, 1)
    with assert_raises():
        _ = sliding_window_energy(Span(underflow), 1)

    var invalid: List[Complex64] = [
        Complex64(inf[DType.float64](), 0.0)
    ]
    with assert_raises():
        _ = window_energy(Span(invalid), 0, 1)
    with assert_raises():
        _ = sliding_window_energy(Span(invalid), 1)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
