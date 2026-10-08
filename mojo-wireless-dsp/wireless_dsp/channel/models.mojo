"""Seeded fading and RF/sample-clock impairment golden references."""

from std.collections import Span
from std.math import cos, isfinite, log, remainder, sin, sqrt
from wireless_dsp.core import Complex64
from wireless_dsp.dsp import convolve_complex

comptime _TWO_PI = 6.283185307179586476925286766559
comptime _SQRT_TWO = 1.414213562373095048801688724210


def _uniform(mut state: UInt64) -> Float64:
    state = state * UInt64(6364136223846793005) + UInt64(1442695040888963407)
    return (Float64(state >> 11) + 0.5) / 9007199254740992.0


def _complex_gaussian(mut state: UInt64) -> Complex64:
    var radius = sqrt(-log(_uniform(state)))
    var angle = _TWO_PI * _uniform(state)
    return Complex64(radius * cos(angle), radius * sin(angle))


def apply_integer_timing_offset(
    samples: Span[Complex64, ...], offset: Int
) raises -> List[Complex64]:
    """Shift within a fixed-size observation; positive offset delays the signal."""
    var result = List[Complex64](capacity=len(samples))
    for index in range(len(samples)):
        if not isfinite(samples[index].re) or not isfinite(samples[index].im):
            raise Error("timing-offset input samples must be finite")
    # Avoid ``n - offset`` overflowing for Int.MIN/Int.MAX.  Any shift whose
    # magnitude spans the observation has an exactly all-zero result.
    if offset >= len(samples) or offset <= -len(samples):
        for _ in range(len(samples)):
            result.append(Complex64(0.0, 0.0))
        return result^
    for n in range(len(samples)):
        var source = n - offset
        if source >= 0 and source < len(samples):
            result.append(Complex64(samples[source].re, samples[source].im))
        else:
            result.append(Complex64(0.0, 0.0))
    return result^


def apply_multipath(
    samples: Span[Complex64, ...], taps: Span[Complex64, ...]
) raises -> List[Complex64]:
    """Full linear complex convolution with explicit channel impulse response."""
    for index in range(len(samples)):
        if not isfinite(samples[index].re) or not isfinite(samples[index].im):
            raise Error("multipath input samples must be finite")
    for index in range(len(taps)):
        if not isfinite(taps[index].re) or not isfinite(taps[index].im):
            raise Error("multipath taps must be finite")
    return convolve_complex(samples, taps)


def apply_rayleigh_fading(
    samples: Span[Complex64, ...], *, seed: UInt64, block_fading: Bool = False
) raises -> List[Complex64]:
    """Unit-power circular Rayleigh coefficient per sample or per block."""
    var state = seed
    var block = _complex_gaussian(state)
    var result = List[Complex64](capacity=len(samples))
    for i in range(len(samples)):
        if not isfinite(samples[i].re) or not isfinite(samples[i].im):
            raise Error("Rayleigh input samples must be finite")
        var coefficient = block if block_fading else _complex_gaussian(state)
        var sample = Complex64(samples[i].re, samples[i].im)
        var output = sample * coefficient
        if not isfinite(output.re) or not isfinite(output.im):
            raise Error("Rayleigh output samples must remain finite")
        result.append(output)
    return result^


def apply_rician_fading(
    samples: Span[Complex64, ...], k_factor: Float64, *, seed: UInt64,
    los_phase: Float64 = 0.0, block_fading: Bool = False,
) raises -> List[Complex64]:
    """Unit-mean-power Rician fading with linear K factor."""
    if (
        not isfinite(k_factor)
        or k_factor < 0.0
        or not isfinite(los_phase)
    ):
        raise Error("Rician K factor and LOS phase must be finite and valid")
    var state = seed
    var los_scale = sqrt(k_factor / (k_factor + 1.0))
    var scatter_scale = sqrt(1.0 / (k_factor + 1.0))
    var los = Complex64(los_scale * cos(los_phase), los_scale * sin(los_phase))
    var block_scatter = _complex_gaussian(state)
    var result = List[Complex64](capacity=len(samples))
    for i in range(len(samples)):
        if not isfinite(samples[i].re) or not isfinite(samples[i].im):
            raise Error("Rician input samples must be finite")
        var scatter = block_scatter if block_fading else _complex_gaussian(state)
        var coefficient = los + Complex64(
            scatter_scale * scatter.re, scatter_scale * scatter.im
        )
        var sample = Complex64(samples[i].re, samples[i].im)
        var output = sample * coefficient
        if not isfinite(output.re) or not isfinite(output.im):
            raise Error("Rician output samples must remain finite")
        result.append(output)
    return result^


def apply_doppler(
    samples: Span[Complex64, ...], normalized_doppler: Float64,
    *, initial_phase: Float64 = 0.0,
) raises -> List[Complex64]:
    """Apply a deterministic single-path Doppler phase ramp, cycles/sample."""
    if not isfinite(normalized_doppler) or not isfinite(initial_phase):
        raise Error("Doppler frequency and initial phase must be finite")
    var result = List[Complex64](capacity=len(samples))
    var phase = remainder(initial_phase, _TWO_PI)
    var increment = _TWO_PI * remainder(normalized_doppler, 1.0)
    for i in range(len(samples)):
        if not isfinite(samples[i].re) or not isfinite(samples[i].im):
            raise Error("Doppler input samples must be finite")
        var coefficient = Complex64(cos(phase), sin(phase))
        var sample = Complex64(samples[i].re, samples[i].im)
        var output = sample * coefficient
        if not isfinite(output.re) or not isfinite(output.im):
            raise Error("Doppler output samples must remain finite")
        result.append(output)
        phase = remainder(phase + increment, _TWO_PI)
    return result^


def apply_phase_noise(
    samples: Span[Complex64, ...], innovation_stddev: Float64, *, seed: UInt64,
    initial_phase: Float64 = 0.0,
) raises -> List[Complex64]:
    """Wiener phase-noise process with Gaussian radian innovations."""
    if (
        not isfinite(innovation_stddev)
        or innovation_stddev < 0.0
        or not isfinite(initial_phase)
    ):
        raise Error("phase-noise deviation and initial phase must be finite")
    var state = seed
    var phase = initial_phase
    var result = List[Complex64](capacity=len(samples))
    for i in range(len(samples)):
        if not isfinite(samples[i].re) or not isfinite(samples[i].im):
            raise Error("phase-noise input samples must be finite")
        var normal = _complex_gaussian(state)
        # ``_complex_gaussian`` is unit-power circular CN(0, 1), so each
        # component has variance 1/2.  Convert its real component to N(0, 1)
        # before applying the caller's requested innovation standard deviation.
        phase += innovation_stddev * _SQRT_TWO * normal.re
        if not isfinite(phase):
            raise Error("phase-noise state must remain finite")
        var rotation = Complex64(cos(phase), sin(phase))
        var sample = Complex64(samples[i].re, samples[i].im)
        var output = sample * rotation
        if not isfinite(output.re) or not isfinite(output.im):
            raise Error("phase-noise output samples must remain finite")
        result.append(output)
    return result^


def apply_iq_imbalance(
    samples: Span[Complex64, ...], gain_imbalance: Float64,
    phase_imbalance: Float64,
) raises -> List[Complex64]:
    """Direct I/Q branch model; gain is fractional and phase is radians."""
    if (
        not isfinite(gain_imbalance)
        or abs(gain_imbalance) >= 1.0
        or not isfinite(phase_imbalance)
    ):
        raise Error("IQ gain/phase imbalance must be finite and gain below one")
    var i_gain = 1.0 + gain_imbalance
    var q_gain = 1.0 - gain_imbalance
    var result = List[Complex64](capacity=len(samples))
    for i in range(len(samples)):
        if not isfinite(samples[i].re) or not isfinite(samples[i].im):
            raise Error("IQ-imbalance input samples must be finite")
        var input_i = samples[i].re
        var input_q = samples[i].im
        var output = Complex64(
            i_gain * input_i,
            q_gain * (cos(phase_imbalance) * input_q + sin(phase_imbalance) * input_i),
        )
        if not isfinite(output.re) or not isfinite(output.im):
            raise Error("IQ-imbalance output samples must remain finite")
        result.append(output)
    return result^


def apply_sample_clock_offset(
    samples: Span[Complex64, ...], offset_ppm: Float64
) raises -> List[Complex64]:
    """Fixed-length linear interpolation at t=n*(1+offset_ppm*1e-6)."""
    if not isfinite(offset_ppm) or abs(offset_ppm) >= 1.0e6:
        raise Error("sample-clock offset must be finite and below one million ppm")
    var ratio = 1.0 + offset_ppm * 1.0e-6
    var result = List[Complex64](capacity=len(samples))
    for n in range(len(samples)):
        if not isfinite(samples[n].re) or not isfinite(samples[n].im):
            raise Error("sample-clock input samples must be finite")
        var position = Float64(n) * ratio
        var left = Int(position)
        if left < 0 or left >= len(samples):
            result.append(Complex64(0.0, 0.0))
        elif left == len(samples) - 1:
            result.append(Complex64(samples[left].re, samples[left].im))
        else:
            var fraction = position - Float64(left)
            var output = Complex64(
                (1.0 - fraction) * samples[left].re + fraction * samples[left + 1].re,
                (1.0 - fraction) * samples[left].im + fraction * samples[left + 1].im,
            )
            if not isfinite(output.re) or not isfinite(output.im):
                raise Error("sample-clock output samples must remain finite")
            result.append(output)
    return result^
