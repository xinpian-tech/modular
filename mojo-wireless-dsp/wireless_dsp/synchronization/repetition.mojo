"""Repeated-preamble packet detection, timing, and CFO primitives."""

from std.collections import Span
from std.math import atan2, isfinite
from wireless_dsp.core import Complex64

comptime _TWO_PI = 6.283185307179586476925286766559


def _repetition_correlation(
    samples: Span[Complex64, ...], offset: Int, period: Int, window: Int
) raises -> Tuple[Complex64, Float64, Float64]:
    if period < 1 or window < 1 or offset < 0 or offset > len(samples):
        raise Error("invalid repeated-preamble window")
    var remaining = len(samples) - offset
    if period > remaining or window > remaining - period:
        raise Error("invalid repeated-preamble window")

    # The metric and correlation phase are invariant to a common positive
    # scale.  Normalize the two windows before accumulating so finite
    # near-limit and subnormal samples do not overflow or underflow the
    # products and energy sums.
    var scale = 0.0
    for i in range(window):
        var first = samples[offset + i]
        var second = samples[offset + period + i]
        if (
            not isfinite(first.re)
            or not isfinite(first.im)
            or not isfinite(second.re)
            or not isfinite(second.im)
        ):
            raise Error("repeated-preamble samples must be finite")
        scale = max(scale, abs(first.re))
        scale = max(scale, abs(first.im))
        scale = max(scale, abs(second.re))
        scale = max(scale, abs(second.im))
    if scale == 0.0:
        return (Complex64(0.0, 0.0), 0.0, 0.0)

    var correlation = Complex64(0.0, 0.0)
    var first_energy = 0.0
    var second_energy = 0.0
    for i in range(window):
        var first = Complex64(
            samples[offset + i].re / scale,
            samples[offset + i].im / scale,
        )
        var second = Complex64(
            samples[offset + period + i].re / scale,
            samples[offset + period + i].im / scale,
        )
        correlation = correlation + second * first.conjugate()
        first_energy += first.magnitude_squared()
        second_energy += second.magnitude_squared()
    return (correlation, first_energy, second_energy)


def repetition_metric(
    samples: Span[Complex64, ...], offset: Int, period: Int, window: Int
) raises -> Float64:
    var correlation, first_energy, second_energy = _repetition_correlation(
        samples, offset, period, window
    )
    var denominator = first_energy * second_energy
    if denominator <= 0.0:
        return 0.0
    return min(1.0, correlation.magnitude_squared() / denominator)


def detect_repetition_start(
    samples: Span[Complex64, ...], period: Int, window: Int, threshold: Float64
) raises -> Int:
    """Return first threshold crossing, or -1 when no repeated preamble exists."""
    if not isfinite(threshold) or threshold < 0.0 or threshold > 1.0:
        raise Error("repetition threshold must be finite and between zero and one")
    if period < 1 or window < 1 or period > len(samples):
        raise Error("invalid repeated-preamble window")
    if window > len(samples) - period:
        raise Error("invalid repeated-preamble window")
    var last_offset = len(samples) - period - window
    for offset in range(last_offset + 1):
        if repetition_metric(samples, offset, period, window) >= threshold:
            return offset
    return -1


def estimate_repetition_cfo(
    samples: Span[Complex64, ...], offset: Int, period: Int, window: Int
) raises -> Float64:
    """Estimate CFO in cycles/sample from phase across repeated segments."""
    var correlation, _, _ = _repetition_correlation(samples, offset, period, window)
    return atan2(correlation.im, correlation.re) / (_TWO_PI * Float64(period))
