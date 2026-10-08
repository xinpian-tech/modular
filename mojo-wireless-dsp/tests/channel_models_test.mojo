from std.math import atan2, cos, log, sin, sqrt
from std.testing import assert_equal, assert_true, assert_raises, TestSuite
from std.utils.numerics import inf, nan
from wireless_dsp.core import Complex64, Span
from wireless_dsp.channel import (
    apply_integer_timing_offset,
    apply_multipath,
    apply_rayleigh_fading,
    apply_rician_fading,
    apply_doppler,
    apply_phase_noise,
    apply_iq_imbalance,
    apply_sample_clock_offset,
)


def test_timing_and_multipath_known_vectors() raises:
    var signal: List[Complex64] = [Complex64(1.0), Complex64(2.0), Complex64(3.0)]
    assert_equal(
        apply_integer_timing_offset(Span(signal), 1),
        [Complex64(0.0), Complex64(1.0), Complex64(2.0)],
    )
    var taps: List[Complex64] = [Complex64(1.0), Complex64(0.5)]
    assert_equal(
        apply_multipath(Span(signal), Span(taps)),
        [Complex64(1.0), Complex64(2.5), Complex64(4.0), Complex64(1.5)],
    )


def test_seeded_fading_reproducibility_and_power() raises:
    var ones = List[Complex64](capacity=20000)
    for _ in range(20000):
        ones.append(Complex64(1.0))
    var first = apply_rayleigh_fading(Span(ones), seed=UInt64(123))
    var second = apply_rayleigh_fading(Span(ones), seed=UInt64(123))
    assert_equal(first, second)
    var power = 0.0
    for sample in first:
        power += sample.magnitude_squared()
    power /= Float64(len(first))
    assert_true(abs(power - 1.0) < 0.03)
    var rician = apply_rician_fading(
        Span(ones), 10.0, seed=UInt64(8), block_fading=True
    )
    for i in range(1, len(rician)):
        assert_equal(rician[i], rician[0])
    with assert_raises():
        _ = apply_rician_fading(
            Span(ones), nan[DType.float64](), seed=UInt64(8)
        )
    with assert_raises():
        _ = apply_rician_fading(
            Span(ones), inf[DType.float64](), seed=UInt64(8)
        )


def test_doppler_phase_noise_iq_and_clock() raises:
    var ones: List[Complex64] = [Complex64(1.0), Complex64(1.0), Complex64(1.0)]
    var doppler = apply_doppler(Span(ones), 0.25)
    assert_true(abs(doppler[1].im - 1.0) < 1.0e-12)
    var huge_doppler = apply_doppler(Span(ones), 1.0e308)
    assert_equal(huge_doppler, ones)
    var phase_a = apply_phase_noise(Span(ones), 0.01, seed=UInt64(99))
    var phase_b = apply_phase_noise(Span(ones), 0.01, seed=UInt64(99))
    assert_equal(phase_a, phase_b)
    # Reconstruct the first standard-normal draw directly from the documented
    # LCG and Box-Muller equations, independent of the channel helper.
    var unit_phase = apply_phase_noise(
        Span(ones), 1.0, seed=UInt64(99)
    )
    var state = UInt64(99)
    state = state * UInt64(6364136223846793005) + UInt64(1442695040888963407)
    var uniform_radius = (
        Float64(state >> 11) + 0.5
    ) / 9007199254740992.0
    state = state * UInt64(6364136223846793005) + UInt64(1442695040888963407)
    var uniform_angle = (
        Float64(state >> 11) + 0.5
    ) / 9007199254740992.0
    var expected_phase = sqrt(-2.0 * log(uniform_radius)) * cos(
        6.283185307179586476925286766559 * uniform_angle
    )
    assert_true(abs(unit_phase[0].re - cos(expected_phase)) < 2.0e-15)
    assert_true(abs(unit_phase[0].im - sin(expected_phase)) < 2.0e-15)

    # A seeded ensemble also locks the parameter's standard-deviation meaning,
    # rather than merely its deterministic replay.
    var phase_samples = List[Complex64](length=20000, fill=Complex64(1.0))
    var phase_noise = apply_phase_noise(
        Span(phase_samples), 0.02, seed=UInt64(0x5068_4153)
    )
    var previous = Complex64(1.0)
    var innovation_power = 0.0
    for current in phase_noise:
        var relative_re = current.re * previous.re + current.im * previous.im
        var relative_im = current.im * previous.re - current.re * previous.im
        var innovation = atan2(relative_im, relative_re)
        innovation_power += innovation * innovation
        previous = current
    var measured_variance = innovation_power / Float64(len(phase_noise))
    assert_true(abs(measured_variance - 0.0004) < 0.00002)
    var iq = apply_iq_imbalance(Span(ones), 0.1, 0.0)
    assert_equal(iq[0], Complex64(1.1, 0.0))

    var ramp: List[Complex64] = [Complex64(0.0), Complex64(1.0), Complex64(2.0)]
    var clocked = apply_sample_clock_offset(Span(ramp), 500000.0)
    assert_true(abs(clocked[1].re - 1.5) < 1.0e-12)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
