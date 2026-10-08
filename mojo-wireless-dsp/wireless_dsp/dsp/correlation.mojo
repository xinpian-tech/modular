"""Complex cross-correlation and normalized detection primitives."""

from std.collections import Span
from std.math import atan2, isfinite, sqrt
from wireless_dsp.core import Complex64


def _restore_scaled_bilinear(
    value: Float64, lhs_scale: Float64, rhs_scale: Float64
) raises -> Float64:
    """Restore ``value * lhs_scale * rhs_scale`` without a fixed order."""
    if value == 0.0:
        return 0.0

    # Trying all three association orders matters when one scale is extremely
    # large and the other extremely small.  Return the first finite, non-zero
    # representation; if none exists, the Float64 result is not representable.
    var restored = (value * lhs_scale) * rhs_scale
    if isfinite(restored) and restored != 0.0:
        return restored
    restored = (value * rhs_scale) * lhs_scale
    if isfinite(restored) and restored != 0.0:
        return restored
    restored = (lhs_scale * rhs_scale) * value
    if isfinite(restored) and restored != 0.0:
        return restored
    raise Error("correlation result is not representable as Float64")


def cross_correlate_complex(
    signal: Span[Complex64, ...], reference: Span[Complex64, ...]
) raises -> List[Complex64]:
    """Sliding ``sum(signal[offset+k] * conj(reference[k]))``.

    Ordinary inputs retain their direct operation order.  If that path
    overflows, a component-scaled recomputation can recover representable
    results such as exact cancellation; unrepresentable results and non-finite
    inputs are rejected rather than returning ``Inf``/``NaN``.
    """
    if len(reference) == 0 or len(signal) < len(reference):
        return List[Complex64]()

    var reference_scale = 0.0
    for k in range(len(reference)):
        if not isfinite(reference[k].re) or not isfinite(reference[k].im):
            raise Error("cross correlation requires finite samples")
        reference_scale = max(
            reference_scale,
            abs(reference[k].re),
            abs(reference[k].im),
        )
    for i in range(len(signal)):
        if not isfinite(signal[i].re) or not isfinite(signal[i].im):
            raise Error("cross correlation requires finite samples")

    var count = len(signal) - len(reference) + 1
    var result = List[Complex64](capacity=count)
    for offset in range(count):
        var acc = Complex64(0.0, 0.0)
        var direct_is_finite = True
        var signal_scale = 0.0
        for k in range(len(reference)):
            var sample = Complex64(signal[offset + k].re, signal[offset + k].im)
            var reference_value = Complex64(reference[k].re, reference[k].im)
            acc = acc + sample * reference_value.conjugate()
            if not isfinite(acc.re) or not isfinite(acc.im):
                direct_is_finite = False
            signal_scale = max(
                signal_scale, abs(sample.re), abs(sample.im)
            )
        if direct_is_finite and (acc.re != 0.0 or acc.im != 0.0):
            result.append(acc)
            continue
        if signal_scale == 0.0 or reference_scale == 0.0:
            result.append(Complex64(0.0, 0.0))
            continue

        var scaled_real = 0.0
        var scaled_imaginary = 0.0
        for k in range(len(reference)):
            var signal_real = signal[offset + k].re / signal_scale
            var signal_imaginary = signal[offset + k].im / signal_scale
            var reference_real = reference[k].re / reference_scale
            var reference_imaginary = reference[k].im / reference_scale
            scaled_real += (
                signal_real * reference_real
                + signal_imaginary * reference_imaginary
            )
            scaled_imaginary += (
                signal_imaginary * reference_real
                - signal_real * reference_imaginary
            )
        result.append(Complex64(
            _restore_scaled_bilinear(
                scaled_real, signal_scale, reference_scale
            ),
            _restore_scaled_bilinear(
                scaled_imaginary, signal_scale, reference_scale
            ),
        ))
    return result^


def normalized_correlation_at(
    signal: Span[Complex64, ...],
    reference: Span[Complex64, ...],
    offset: Int,
) raises -> Complex64:
    """Return a scale-invariant normalized complex correlation.

    Each vector is first divided by its largest absolute component.  This
    preserves the normalized result while preventing finite inputs from being
    lost to overflow or underflow in products and energy sums.  An all-zero
    vector has zero correlation; non-finite samples are rejected explicitly.
    """
    if (
        len(reference) == 0
        or offset < 0
        or len(reference) > len(signal)
        or offset > len(signal) - len(reference)
    ):
        raise Error("invalid normalized-correlation window")

    var signal_scale = 0.0
    var reference_scale = 0.0
    for k in range(len(reference)):
        var sample = Complex64(signal[offset + k].re, signal[offset + k].im)
        var reference_value = Complex64(reference[k].re, reference[k].im)
        if (
            not isfinite(sample.re)
            or not isfinite(sample.im)
            or not isfinite(reference_value.re)
            or not isfinite(reference_value.im)
        ):
            raise Error("normalized correlation requires finite samples")
        signal_scale = max(signal_scale, abs(sample.re), abs(sample.im))
        reference_scale = max(
            reference_scale,
            abs(reference_value.re),
            abs(reference_value.im),
        )

    if signal_scale == 0.0 or reference_scale == 0.0:
        return Complex64(0.0, 0.0)

    var accumulated_real = 0.0
    var accumulated_imaginary = 0.0
    var signal_energy = 0.0
    var reference_energy = 0.0
    for k in range(len(reference)):
        var signal_real = signal[offset + k].re / signal_scale
        var signal_imaginary = signal[offset + k].im / signal_scale
        var reference_real = reference[k].re / reference_scale
        var reference_imaginary = reference[k].im / reference_scale
        accumulated_real += (
            signal_real * reference_real
            + signal_imaginary * reference_imaginary
        )
        accumulated_imaginary += (
            signal_imaginary * reference_real
            - signal_real * reference_imaginary
        )
        signal_energy += (
            signal_real * signal_real
            + signal_imaginary * signal_imaginary
        )
        reference_energy += (
            reference_real * reference_real
            + reference_imaginary * reference_imaginary
        )

    var denominator = sqrt(signal_energy) * sqrt(reference_energy)
    if not isfinite(denominator) or denominator <= 0.0:
        raise Error("normalized-correlation norm is not representable")
    var result = Complex64(
        accumulated_real / denominator,
        accumulated_imaginary / denominator,
    )
    if not isfinite(result.re) or not isfinite(result.im):
        raise Error("normalized-correlation result is not representable")
    return result


def normalized_cross_correlate_complex(
    signal: Span[Complex64, ...], reference: Span[Complex64, ...]
) raises -> List[Complex64]:
    """Normalized valid sliding cross-correlation at every possible offset."""
    if len(reference) == 0 or len(signal) < len(reference):
        return List[Complex64]()
    var result = List[Complex64](capacity=len(signal) - len(reference) + 1)
    for offset in range(len(signal) - len(reference) + 1):
        result.append(normalized_correlation_at(signal, reference, offset))
    return result^


def correlation_peak(values: Span[Complex64, ...]) raises -> Int:
    """Return the first maximum-magnitude index using overflow-safe ranking."""
    if len(values) == 0:
        raise Error("correlation peak requires non-empty input")
    var scale = 0.0
    for i in range(len(values)):
        if not isfinite(values[i].re) or not isfinite(values[i].im):
            raise Error("correlation peak requires finite values")
        scale = max(scale, abs(values[i].re), abs(values[i].im))
    if scale == 0.0:
        return 0

    var best = 0
    var first_real = values[0].re / scale
    var first_imaginary = values[0].im / scale
    var best_energy = (
        first_real * first_real + first_imaginary * first_imaginary
    )
    for i in range(1, len(values)):
        var candidate_real = values[i].re / scale
        var candidate_imaginary = values[i].im / scale
        var candidate = (
            candidate_real * candidate_real
            + candidate_imaginary * candidate_imaginary
        )
        if candidate > best_energy:
            best = i
            best_energy = candidate
    return best


def autocorrelate_complex(values: Span[Complex64, ...], lag: Int) raises -> Complex64:
    """Return finite, representable unnormalized autocorrelation at ``lag``."""
    if lag < 0 or lag >= len(values):
        raise Error("autocorrelation lag is out of range")

    var acc = Complex64(0.0, 0.0)
    var direct_is_finite = True
    var scale = 0.0
    for i in range(len(values) - lag):
        var lhs = Complex64(values[i + lag].re, values[i + lag].im)
        var rhs = Complex64(values[i].re, values[i].im)
        if (
            not isfinite(lhs.re)
            or not isfinite(lhs.im)
            or not isfinite(rhs.re)
            or not isfinite(rhs.im)
        ):
            raise Error("autocorrelation requires finite samples")
        scale = max(
            scale,
            abs(lhs.re),
            abs(lhs.im),
            abs(rhs.re),
            abs(rhs.im),
        )
        acc = acc + lhs * rhs.conjugate()
        if not isfinite(acc.re) or not isfinite(acc.im):
            direct_is_finite = False
    if direct_is_finite and (acc.re != 0.0 or acc.im != 0.0):
        return acc
    if scale == 0.0:
        return Complex64(0.0, 0.0)

    var scaled_real = 0.0
    var scaled_imaginary = 0.0
    for i in range(len(values) - lag):
        var lhs_real = values[i + lag].re / scale
        var lhs_imaginary = values[i + lag].im / scale
        var rhs_real = values[i].re / scale
        var rhs_imaginary = values[i].im / scale
        scaled_real += lhs_real * rhs_real + lhs_imaginary * rhs_imaginary
        scaled_imaginary += lhs_imaginary * rhs_real - lhs_real * rhs_imaginary
    return Complex64(
        _restore_scaled_bilinear(scaled_real, scale, scale),
        _restore_scaled_bilinear(scaled_imaginary, scale, scale),
    )


def autocorrelation_sequence(
    values: Span[Complex64, ...], max_lag: Int, *, normalized: Bool = False
) raises -> List[Complex64]:
    """Autocorrelation for lags ``0...max_lag``, optionally normalized by R(0)."""
    if len(values) == 0 or max_lag < 0 or max_lag >= len(values):
        raise Error("invalid autocorrelation sequence range")
    var result = List[Complex64](capacity=max_lag + 1)
    if not normalized:
        for lag in range(max_lag + 1):
            result.append(autocorrelate_complex(values, lag))
        return result^

    var scale = 0.0
    for i in range(len(values)):
        if not isfinite(values[i].re) or not isfinite(values[i].im):
            raise Error("autocorrelation requires finite samples")
        scale = max(scale, abs(values[i].re), abs(values[i].im))
    if scale == 0.0:
        raise Error("zero-energy input cannot have normalized autocorrelation")

    var denominator = 0.0
    for i in range(len(values)):
        var real = values[i].re / scale
        var imaginary = values[i].im / scale
        denominator += real * real + imaginary * imaginary
    if not isfinite(denominator) or denominator <= 0.0:
        raise Error("normalized autocorrelation energy is not representable")

    for lag in range(max_lag + 1):
        if lag == 0:
            # R(0) / R(0) is exactly real one.  Stating that identity directly
            # also avoids a tiny imaginary FMA residual on some targets.
            result.append(Complex64(1.0, 0.0))
            continue
        var real = 0.0
        var imaginary = 0.0
        for i in range(len(values) - lag):
            var lhs_real = values[i + lag].re / scale
            var lhs_imaginary = values[i + lag].im / scale
            var rhs_real = values[i].re / scale
            var rhs_imaginary = values[i].im / scale
            real += lhs_real * rhs_real + lhs_imaginary * rhs_imaginary
            imaginary += lhs_imaginary * rhs_real - lhs_real * rhs_imaginary
        var value = Complex64(real / denominator, imaginary / denominator)
        if not isfinite(value.re) or not isfinite(value.im):
            raise Error("normalized autocorrelation result is not representable")
        result.append(value)
    return result^


def window_energy(values: Span[Complex64, ...], offset: Int, length: Int) raises -> Float64:
    """Return window energy or reject a non-finite/unrepresentable result."""
    if (
        offset < 0
        or length < 0
        or offset > len(values)
        or length > len(values) - offset
    ):
        raise Error("energy window is out of range")
    var result = 0.0
    var scale = 0.0
    var has_nonzero = False
    for i in range(offset, offset + length):
        if not isfinite(values[i].re) or not isfinite(values[i].im):
            raise Error("window energy requires finite samples")
        if values[i].re != 0.0 or values[i].im != 0.0:
            has_nonzero = True
        scale = max(scale, abs(values[i].re), abs(values[i].im))
        result += values[i].re * values[i].re + values[i].im * values[i].im
    if not isfinite(result):
        raise Error("window energy is not representable as Float64")
    if result != 0.0 or not has_nonzero:
        return result

    # Direct products underflowed.  A scaled retry can still recover a
    # representable aggregate when many individually tiny powers add up.
    var scaled_energy = 0.0
    for i in range(offset, offset + length):
        var real = values[i].re / scale
        var imaginary = values[i].im / scale
        scaled_energy += real * real + imaginary * imaginary
    return _restore_scaled_bilinear(scaled_energy, scale, scale)


def sliding_window_energy(
    values: Span[Complex64, ...], length: Int
) raises -> List[Float64]:
    """Energy of every valid window with independent checked accumulation.

    Re-evaluating each reference window avoids catastrophic information loss
    when a very large departing sample previously masked small samples that
    remain in the next window.  Optimized backends may use a wider accumulator
    or a periodically rebased running sum while preserving these semantics.
    """
    if length < 1 or length > len(values):
        raise Error("invalid sliding-energy window length")
    var result = List[Float64](capacity=len(values) - length + 1)
    for offset in range(len(values) - length + 1):
        result.append(window_energy(values, offset, length))
    return result^


def correlation_phase(value: Complex64) -> Float64:
    return atan2(value.im, value.re)
