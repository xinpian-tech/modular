"""Numerically controlled oscillator and complex mixer references."""

from std.collections import Span
from std.math import cos, isfinite, remainder, sin
from wireless_dsp.core import Complex64

comptime _TWO_PI = 6.283185307179586476925286766559


def generate_nco(
    sample_count: Int,
    cycles_per_sample: Float64,
    *,
    initial_phase: Float64 = 0.0,
) raises -> List[Complex64]:
    """Generate ``exp(j*(initial_phase + 2*pi*f*n))`` samples."""
    if (
        sample_count < 0
        or not isfinite(cycles_per_sample)
        or not isfinite(initial_phase)
    ):
        raise Error("NCO count, frequency, and initial phase must be valid")
    var result = List[Complex64](capacity=sample_count)
    var phase = remainder(initial_phase, _TWO_PI)
    var increment = _TWO_PI * remainder(cycles_per_sample, 1.0)
    for _ in range(sample_count):
        result.append(Complex64(cos(phase), sin(phase)))
        phase = remainder(phase + increment, _TWO_PI)
    return result^


def mix_complex(
    values: Span[Complex64, ...],
    cycles_per_sample: Float64,
    *,
    initial_phase: Float64 = 0.0,
) raises -> List[Complex64]:
    """Mix by a positive-frequency unit phasor; use negative ``f`` to downconvert."""
    if not isfinite(cycles_per_sample) or not isfinite(initial_phase):
        raise Error("mixer frequency and initial phase must be finite")
    var result = List[Complex64](capacity=len(values))
    var phase = remainder(initial_phase, _TWO_PI)
    var increment = _TWO_PI * remainder(cycles_per_sample, 1.0)
    for i in range(len(values)):
        if not isfinite(values[i].re) or not isfinite(values[i].im):
            raise Error("mixer input samples must be finite")
        var value = Complex64(values[i].re, values[i].im)
        var output = value * Complex64(cos(phase), sin(phase))
        if not isfinite(output.re) or not isfinite(output.im):
            raise Error("mixer output samples must remain finite")
        result.append(output)
        phase = remainder(phase + increment, _TWO_PI)
    return result^
