from std.math import sqrt
from std.testing import assert_equal, assert_true, assert_raises, TestSuite
from std.utils.numerics import inf, nan
from wireless_dsp.core import Complex64, Span
from wireless_dsp.dsp import (
    complex_divide,
    ls_channel_estimate,
    linear_interpolate_complex,
    estimate_pilot_noise_variance,
    zero_forcing_equalize_siso,
    mmse_equalize_siso,
    common_phase_error,
    rectangular_window,
    hann_window,
    hamming_window,
    blackman_window,
    apply_window_complex,
    generate_nco,
    mix_complex,
    linear_resample_real,
    linear_resample_complex,
    rational_resample_real,
    rational_resample_complex,
)
from wireless_dsp.synchronization import detect_repetition_start


def _assert_complex_close(actual: Complex64, expected: Complex64, tolerance: Float64) raises:
    assert_true(abs(actual.re - expected.re) <= tolerance)
    assert_true(abs(actual.im - expected.im) <= tolerance)


def test_shared_ls_interpolation_and_equalization() raises:
    var known: List[Complex64] = [Complex64(1.0), Complex64(0.0, 1.0), Complex64(-1.0)]
    var channel_pilots: List[Complex64] = [
        Complex64(1.0, 0.5), Complex64(2.0, 0.0), Complex64(3.0, -0.5)
    ]
    var received = List[Complex64](capacity=3)
    for i in range(3):
        received.append(channel_pilots[i] * known[i])
    var estimates = ls_channel_estimate(Span(received), Span(known))
    assert_equal(estimates, channel_pilots)
    var positions: List[Int] = [1, 3, 5]
    var interpolated = linear_interpolate_complex(Span(estimates), Span(positions), 7)
    _assert_complex_close(interpolated[0], channel_pilots[0], 1.0e-12)
    _assert_complex_close(interpolated[2], Complex64(1.5, 0.25), 1.0e-12)
    _assert_complex_close(interpolated[4], Complex64(2.5, -0.25), 1.0e-12)
    _assert_complex_close(interpolated[6], channel_pilots[2], 1.0e-12)

    var symbols: List[Complex64] = [Complex64(1.0, 1.0), Complex64(-1.0, 0.5)]
    var channels: List[Complex64] = [Complex64(2.0, -1.0), Complex64(0.5, 0.5)]
    var observations = List[Complex64](capacity=2)
    for i in range(2):
        observations.append(channels[i] * symbols[i])
    var equalized = zero_forcing_equalize_siso(Span(observations), Span(channels))
    for i in range(2):
        _assert_complex_close(equalized[i], symbols[i], 1.0e-12)
    var mmse = mmse_equalize_siso(Span(observations), Span(channels), 0.0)
    for i in range(2):
        _assert_complex_close(mmse[i], symbols[i], 1.0e-12)


def test_noise_and_common_phase_estimators() raises:
    var known: List[Complex64] = [Complex64(1.0), Complex64(0.0, 1.0)]
    var channel: List[Complex64] = [Complex64(2.0), Complex64(2.0)]
    var received: List[Complex64] = [Complex64(2.1, 0.0), Complex64(0.0, 1.9)]
    assert_true(abs(estimate_pilot_noise_variance(Span(received), Span(known), Span(channel)) - 0.01) < 1.0e-12)
    var rotated: List[Complex64] = [Complex64(0.0, 1.0), Complex64(-1.0, 0.0)]
    assert_true(abs(common_phase_error(Span(rotated), Span(known)) - 1.5707963267948966) < 1.0e-12)

    var huge_known: List[Complex64] = [Complex64(1.0e200)]
    var huge_rotated: List[Complex64] = [Complex64(0.0, 1.0e200)]
    assert_true(
        abs(
            common_phase_error(Span(huge_rotated), Span(huge_known))
            - 1.5707963267948966
        )
        < 1.0e-12
    )
    var tiny_residual_received: List[Complex64] = [Complex64(2.0e-150)]
    var tiny_residual_known: List[Complex64] = [Complex64(1.0)]
    var tiny_residual_channel: List[Complex64] = [Complex64(1.0e-150)]
    var tiny_variance = estimate_pilot_noise_variance(
        Span(tiny_residual_received),
        Span(tiny_residual_known),
        Span(tiny_residual_channel),
    )
    assert_true(abs(tiny_variance - 1.0e-300) <= 1.0e-312)


def test_standard_windows_and_application() raises:
    assert_equal(rectangular_window(3), [1.0, 1.0, 1.0])
    var hann = hann_window(5)
    assert_true(abs(hann[0]) < 1.0e-15)
    assert_true(abs(hann[1] - 0.5) < 1.0e-12)
    assert_true(abs(hann[2] - 1.0) < 1.0e-12)
    assert_true(abs(hann[4]) < 1.0e-15)
    var hamming = hamming_window(3)
    assert_true(abs(hamming[0] - 0.08) < 1.0e-12)
    assert_true(abs(hamming[1] - 1.0) < 1.0e-12)
    var blackman = blackman_window(5)
    assert_true(abs(blackman[2] - 1.0) < 1.0e-12)
    var samples: List[Complex64] = [Complex64(1.0, -1.0), Complex64(2.0, 3.0)]
    var weights: List[Float64] = [0.5, 2.0]
    var applied = apply_window_complex(Span(samples), Span(weights))
    _assert_complex_close(applied[0], Complex64(0.5, -0.5), 1.0e-12)
    _assert_complex_close(applied[1], Complex64(4.0, 6.0), 1.0e-12)


def test_nco_and_mixer_cancel_frequency_offset() raises:
    var oscillator = generate_nco(4, 0.25)
    var expected: List[Complex64] = [
        Complex64(1.0, 0.0), Complex64(0.0, 1.0),
        Complex64(-1.0, 0.0), Complex64(0.0, -1.0),
    ]
    for i in range(4):
        _assert_complex_close(oscillator[i], expected[i], 1.0e-12)
    var baseband: List[Complex64] = [
        Complex64(1.0, 0.5), Complex64(1.0, 0.5),
        Complex64(1.0, 0.5), Complex64(1.0, 0.5),
    ]
    var upconverted = mix_complex(Span(baseband), 0.25)
    var restored = mix_complex(Span(upconverted), -0.25)
    for i in range(4):
        _assert_complex_close(restored[i], baseband[i], 1.0e-12)

    # Every representable Float64 this large is an integer cycle count.  Phase
    # generation must reduce in cycles before constructing a radian increment.
    var huge_frequency = generate_nco(4, 1.0e308)
    for value in huge_frequency:
        assert_equal(value, Complex64(1.0, 0.0))
    var huge_mixed = mix_complex(Span(baseband), 1.0e308)
    assert_equal(huge_mixed, baseband)


def test_linear_and_rational_resamplers_known_vectors() raises:
    var real: List[Float64] = [0.0, 2.0]
    assert_equal(linear_resample_real(Span(real), 5), [0.0, 0.5, 1.0, 1.5, 2.0])
    var complex_values: List[Complex64] = [Complex64(0.0), Complex64(2.0, 4.0)]
    var complex_linear = linear_resample_complex(Span(complex_values), 3)
    assert_equal(complex_linear, [Complex64(0.0), Complex64(1.0, 2.0), Complex64(2.0, 4.0)])

    # Upsample by two with [1, 1] makes each input occupy both new samples.
    var taps: List[Float64] = [1.0, 1.0]
    var input_values: List[Float64] = [1.0, 2.0, 3.0]
    assert_equal(rational_resample_real(Span(input_values), Span(taps), 2, 1), [1.0, 1.0, 2.0, 2.0, 3.0, 3.0])
    var complex_input: List[Complex64] = [Complex64(1.0, -1.0), Complex64(2.0, -2.0)]
    assert_equal(
        rational_resample_complex(Span(complex_input), Span(taps), 2, 1),
        [Complex64(1.0, -1.0), Complex64(1.0, -1.0), Complex64(2.0, -2.0), Complex64(2.0, -2.0)],
    )

    # The exact output is tiny even though the unreduced time products exceed
    # Int.  This exercises the wide length and polyphase-index arithmetic.
    var extreme_taps: List[Float64] = [1.0, 0.5]
    var extreme_real: List[Float64] = [1.0, 2.0]
    assert_equal(
        rational_resample_real(
            Span(extreme_real), Span(extreme_taps), Int.MAX, Int.MAX
        ),
        [1.0, 2.0],
    )
    var extreme_complex: List[Complex64] = [
        Complex64(1.0, -1.0), Complex64(2.0, -2.0)
    ]
    assert_equal(
        rational_resample_complex(
            Span(extreme_complex), Span(extreme_taps), Int.MAX, Int.MAX
        ),
        [Complex64(1.0, -1.0), Complex64(2.0, -2.0)],
    )


def test_extended_dsp_input_validation() raises:
    var empty = List[Complex64]()
    var positions: List[Int] = [0]
    with assert_raises():
        _ = linear_interpolate_complex(Span(empty), Span(positions), 1)
    with assert_raises():
        _ = generate_nco(-1, 0.0)
    var real: List[Float64] = [1.0]
    var no_taps = List[Float64]()
    with assert_raises():
        _ = rational_resample_real(Span(real), Span(no_taps), 1, 1)
    var one: List[Complex64] = [Complex64(1.0)]
    var unit_channel: List[Complex64] = [Complex64(1.0)]
    with assert_raises():
        _ = mmse_equalize_siso(
            Span(one), Span(unit_channel), nan[DType.float64]()
        )
    with assert_raises():
        _ = mmse_equalize_siso(
            Span(one), Span(unit_channel), inf[DType.float64]()
        )
    var repeated: List[Complex64] = [Complex64(1.0), Complex64(1.0)]
    with assert_raises():
        _ = detect_repetition_start(
            Span(repeated), 1, 1, nan[DType.float64]()
        )

    # Opposite extreme endpoints have a finite exact midpoint.  The
    # interpolation must not form the overflowing difference first.
    var extreme_pilots: List[Complex64] = [
        Complex64(1.0e308, -1.0e308),
        Complex64(-1.0e308, 1.0e308),
    ]
    var extreme_positions: List[Int] = [0, 2]
    var extreme = linear_interpolate_complex(
        Span(extreme_pilots), Span(extreme_positions), 3
    )
    assert_equal(extreme[1], Complex64(0.0, 0.0))
    extreme_pilots[0] = Complex64(inf[DType.float64](), 0.0)
    with assert_raises():
        _ = linear_interpolate_complex(
            Span(extreme_pilots), Span(extreme_positions), 3
        )


def test_siso_equalizers_are_scale_safe_at_float64_extremes() raises:
    _assert_complex_close(
        complex_divide(Complex64(1.0e-200), Complex64(1.0e-200)),
        Complex64(1.0),
        1.0e-15,
    )
    _assert_complex_close(
        complex_divide(
            Complex64(1.0e200, -1.0e200),
            Complex64(1.0e200, 1.0e200),
        ),
        Complex64(0.0, -1.0),
        1.0e-15,
    )
    var tiny_channel: List[Complex64] = [Complex64(1.0e-200)]
    var tiny_received: List[Complex64] = [Complex64(1.5e-200)]
    var tiny_zf = zero_forcing_equalize_siso(
        Span(tiny_received), Span(tiny_channel)
    )
    _assert_complex_close(tiny_zf[0], Complex64(1.5), 1.0e-15)

    # |h|^2 underflows in a naive implementation, but N0 keeps the exact MMSE
    # result finite: (1e-200 * 1e-200) / 1e-300 = 1e-100.
    var tiny_mmse = mmse_equalize_siso(
        Span(tiny_received), Span(tiny_channel), 1.5e-300
    )
    assert_true(abs(tiny_mmse[0].re - 1.0e-100) <= 1.0e-112)
    assert_true(abs(tiny_mmse[0].im) <= 1.0e-112)

    var huge_channel: List[Complex64] = [Complex64(1.0e200)]
    var huge_received: List[Complex64] = [Complex64(5.0e199)]
    var huge_mmse = mmse_equalize_siso(
        Span(huge_received), Span(huge_channel), 1.0e300
    )
    _assert_complex_close(huge_mmse[0], Complex64(0.5), 1.0e-15)

    # Results below Float64's minimum subnormal must underflow to zero, never
    # accept finite garbage from an out-of-domain ldexp call.
    var underflow_received: List[Complex64] = [Complex64(1.0e-300)]
    var underflow_channel: List[Complex64] = [Complex64(1.0e-150)]
    var underflow_mmse = mmse_equalize_siso(
        Span(underflow_received), Span(underflow_channel), 1.0e300
    )
    assert_equal(underflow_mmse[0], Complex64(0.0, 0.0))
    var minimum_subnormal = 5.0e-324
    var minimum_received: List[Complex64] = [
        Complex64(minimum_subnormal)
    ]
    var unit_for_subnormal: List[Complex64] = [Complex64(1.0)]
    var minimum_mmse = mmse_equalize_siso(
        Span(minimum_received),
        Span(unit_for_subnormal),
        minimum_subnormal,
    )
    assert_equal(minimum_mmse[0], Complex64(minimum_subnormal, 0.0))
    var maximum_finite = 1.7976931348623157e308
    var maximum_received: List[Complex64] = [Complex64(maximum_finite)]
    var maximum_mmse = mmse_equalize_siso(
        Span(maximum_received), Span(unit_for_subnormal), minimum_subnormal
    )
    assert_equal(maximum_mmse[0], Complex64(maximum_finite, 0.0))
    var unit_reference: List[Complex64] = [Complex64(1.0)]
    var zero_channel: List[Complex64] = [Complex64(0.0)]
    var tiny_residual = estimate_pilot_noise_variance(
        Span(underflow_received), Span(unit_reference), Span(zero_channel)
    )
    assert_equal(tiny_residual, 0.0)
    var minimum_residual: List[Complex64] = [
        Complex64(sqrt(minimum_subnormal), 0.0)
    ]
    assert_equal(
        estimate_pilot_noise_variance(
            Span(minimum_residual), Span(unit_reference), Span(zero_channel)
        ),
        minimum_subnormal,
    )

    with assert_raises():
        _ = complex_divide(Complex64(1.0e308), Complex64(1.0e-308))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
