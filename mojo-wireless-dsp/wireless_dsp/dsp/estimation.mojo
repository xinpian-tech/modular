"""Protocol-independent SISO channel-estimation and equalization references."""

from std.collections import Span
from std.math import atan2, frexp, isfinite, ldexp, sqrt
from wireless_dsp.core import Complex64


def _safe_frexp64(value: Float64) -> Tuple[Float64, Int32]:
    """Work around the pinned stdlib's subnormal ``frexp`` decomposition."""
    if value == 0.0:
        return (value, Int32(0))
    if abs(value) < 2.2250738585072014e-308:
        var scaled = frexp(value * 18014398509481984.0)
        return (
            scaled[0], scaled[1].cast[DType.int32]() - Int32(54)
        )
    var parts = frexp(value)
    return (parts[0], parts[1].cast[DType.int32]())


def complex_divide(lhs: Complex64, rhs: Complex64) raises -> Complex64:
    """Divide finite complex scalars without avoidable square overflow."""
    if (
        not isfinite(lhs.re)
        or not isfinite(lhs.im)
        or not isfinite(rhs.re)
        or not isfinite(rhs.im)
    ):
        raise Error("complex division operands must be finite")
    # Scaling both operands by the same value preserves the quotient and keeps
    # the Smith division intermediates inside [-2, 2].  This supports every
    # non-zero finite divisor, including normal/subnormal values whose raw
    # squared magnitude would underflow or overflow.
    var scale = abs(lhs.re)
    if abs(lhs.im) > scale:
        scale = abs(lhs.im)
    if abs(rhs.re) > scale:
        scale = abs(rhs.re)
    if abs(rhs.im) > scale:
        scale = abs(rhs.im)
    if rhs.re == 0.0 and rhs.im == 0.0:
        raise Error("complex divisor must be non-zero")
    if scale == 0.0:
        raise Error("complex divisor must be non-zero")

    var a = lhs.re / scale
    var b = lhs.im / scale
    var c = rhs.re / scale
    var d = rhs.im / scale
    var real: Float64
    var imag: Float64
    if abs(c) >= abs(d):
        var ratio = d / c
        var denominator = c + d * ratio
        real = (a + b * ratio) / denominator
        imag = (b - a * ratio) / denominator
    else:
        var ratio = c / d
        var denominator = d + c * ratio
        real = (a * ratio + b) / denominator
        imag = (b * ratio - a) / denominator
    if not isfinite(real) or not isfinite(imag):
        raise Error("complex quotient is outside the finite Float64 range")
    return Complex64(real, imag)


def _scaled_multiply_divide(
    value: Float64, factor: Float64, divisor: Float64
) raises -> Float64:
    """Return ``value * factor / divisor`` with exponent-safe ordering."""
    if value == 0.0 or factor == 0.0:
        return value * factor / divisor
    var value_parts = _safe_frexp64(value)
    var factor_parts = _safe_frexp64(factor)
    var divisor_parts = _safe_frexp64(divisor)
    var mantissa = value_parts[0] * factor_parts[0] / divisor_parts[0]
    var exponent = (
        value_parts[1] + factor_parts[1] - divisor_parts[1]
    )
    return _restore_scaled_float64(mantissa, exponent)


def _restore_scaled_float64(
    mantissa: Float64, exponent: Int32,
) raises -> Float64:
    """Restore a finite scaled result within Float64's exponent domain."""
    if mantissa == 0.0:
        return mantissa
    if not isfinite(mantissa):
        raise Error("scaled result is outside the finite Float64 range")
    var parts = _safe_frexp64(mantissa)
    var restored_mantissa = parts[0]
    var restored_exponent = exponent + parts[1]
    if restored_exponent < -1074:
        return -0.0 if restored_mantissa < 0.0 else 0.0
    if restored_exponent > 1024:
        raise Error("scaled result is outside the finite Float64 range")
    var result: Float64
    if restored_exponent <= -1022:
        result = (
            ldexp(restored_mantissa, restored_exponent + Int32(1022))
            * 2.2250738585072014e-308
        )
    elif restored_exponent == 1024:
        result = ldexp(restored_mantissa, Int32(1023)) * 2.0
    else:
        result = ldexp(restored_mantissa, restored_exponent)
    if not isfinite(result):
        raise Error("scaled result is outside the finite Float64 range")
    return result


def _scaled_square_times(value: Float64, factor: Float64) raises -> Float64:
    """Return ``value * value * factor`` without intermediate overflow."""
    if value == 0.0 or factor == 0.0:
        return value * value * factor
    var value_parts = _safe_frexp64(value)
    var factor_parts = _safe_frexp64(factor)
    var mantissa = (
        value_parts[0] * value_parts[0] * factor_parts[0]
    )
    var exponent = (
        2 * value_parts[1] + factor_parts[1]
    )
    return _restore_scaled_float64(mantissa, exponent)


def ls_channel_estimate(
    received: Span[Complex64, ...], known: Span[Complex64, ...]
) raises -> List[Complex64]:
    """Return per-pilot least-squares estimates ``received / known``."""
    if len(received) != len(known) or len(known) == 0:
        raise Error("received and known pilot vectors must be non-empty and equal length")
    var result = List[Complex64](capacity=len(received))
    for i in range(len(received)):
        var received_value = Complex64(received[i].re, received[i].im)
        var known_value = Complex64(known[i].re, known[i].im)
        result.append(complex_divide(received_value, known_value))
    return result^


def linear_interpolate_complex(
    pilots: Span[Complex64, ...],
    positions: Span[Int, ...],
    output_length: Int,
) raises -> List[Complex64]:
    """Linearly interpolate ordered complex pilots and hold both edge values."""
    if len(pilots) == 0 or len(pilots) != len(positions) or output_length < 1:
        raise Error("pilot values/positions must match and output must be non-empty")
    if positions[0] < 0 or positions[len(positions) - 1] >= output_length:
        raise Error("pilot position lies outside interpolation range")
    for i in range(1, len(positions)):
        if positions[i] <= positions[i - 1]:
            raise Error("pilot positions must be strictly increasing")
    for i in range(len(pilots)):
        if not isfinite(pilots[i].re) or not isfinite(pilots[i].im):
            raise Error("pilot values must be finite")

    var result = List[Complex64](capacity=output_length)
    var right = 0
    for position in range(output_length):
        while right < len(positions) and positions[right] < position:
            right += 1
        if right == 0:
            result.append(Complex64(pilots[0].re, pilots[0].im))
        elif right == len(positions):
            result.append(Complex64(pilots[len(pilots) - 1].re, pilots[len(pilots) - 1].im))
        elif positions[right] == position:
            result.append(Complex64(pilots[right].re, pilots[right].im))
        else:
            var left = right - 1
            var fraction = Float64(position - positions[left]) / Float64(
                positions[right] - positions[left]
            )
            var left_weight = 1.0 - fraction
            var real = (
                left_weight * pilots[left].re
                + fraction * pilots[right].re
            )
            var imag = (
                left_weight * pilots[left].im
                + fraction * pilots[right].im
            )
            if not isfinite(real) or not isfinite(imag):
                raise Error("interpolated pilot must remain finite")
            result.append(Complex64(real, imag))
    return result^


def estimate_pilot_noise_variance(
    received: Span[Complex64, ...],
    known: Span[Complex64, ...],
    channel: Span[Complex64, ...],
) raises -> Float64:
    """Mean squared residual ``|y - h*x|^2`` over known pilot positions."""
    if len(received) == 0 or len(received) != len(known) or len(received) != len(channel):
        raise Error("pilot residual vectors must be non-empty and equal length")
    var errors = List[Complex64](capacity=len(received))
    var scale = 0.0
    for i in range(len(received)):
        var channel_value = Complex64(channel[i].re, channel[i].im)
        var known_value = Complex64(known[i].re, known[i].im)
        var received_value = Complex64(received[i].re, received[i].im)
        if (
            not isfinite(channel_value.re)
            or not isfinite(channel_value.im)
            or not isfinite(known_value.re)
            or not isfinite(known_value.im)
            or not isfinite(received_value.re)
            or not isfinite(received_value.im)
        ):
            raise Error("pilot residual inputs must be finite")
        var prediction = channel_value * known_value
        if not isfinite(prediction.re) or not isfinite(prediction.im):
            raise Error("pilot prediction is outside the finite Float64 range")
        var error = received_value - prediction
        if not isfinite(error.re) or not isfinite(error.im):
            raise Error("pilot residual is outside the finite Float64 range")
        errors.append(error)
        if abs(error.re) > scale:
            scale = abs(error.re)
        if abs(error.im) > scale:
            scale = abs(error.im)
    if scale == 0.0:
        return 0.0
    var normalized_energy = 0.0
    for error in errors:
        var re = error.re / scale
        var im = error.im / scale
        normalized_energy += re * re + im * im
    return _scaled_square_times(
        scale, normalized_energy / Float64(len(received))
    )


def zero_forcing_equalize_siso(
    received: Span[Complex64, ...], channel: Span[Complex64, ...]
) raises -> List[Complex64]:
    """Per-subcarrier zero-forcing equalizer."""
    if len(received) != len(channel):
        raise Error("received samples and channel estimates must have equal length")
    var result = List[Complex64](capacity=len(received))
    for i in range(len(received)):
        var received_value = Complex64(received[i].re, received[i].im)
        var channel_value = Complex64(channel[i].re, channel[i].im)
        result.append(complex_divide(received_value, channel_value))
    return result^


def mmse_equalize_siso(
    received: Span[Complex64, ...],
    channel: Span[Complex64, ...],
    noise_variance: Float64,
) raises -> List[Complex64]:
    """Unit-symbol-power SISO MMSE equalizer ``conj(h)y/(|h|^2+N0)``."""
    if (
        len(received) != len(channel)
        or not isfinite(noise_variance)
        or noise_variance < 0.0
    ):
        raise Error(
            "MMSE dimensions must match and noise variance must be finite/non-negative"
        )
    var result = List[Complex64](capacity=len(received))
    for i in range(len(received)):
        var channel_value = Complex64(channel[i].re, channel[i].im)
        var received_value = Complex64(received[i].re, received[i].im)
        if (
            not isfinite(channel_value.re)
            or not isfinite(channel_value.im)
            or not isfinite(received_value.re)
            or not isfinite(received_value.im)
        ):
            raise Error("MMSE samples and channel estimates must be finite")
        if noise_variance == 0.0:
            result.append(complex_divide(received_value, channel_value))
            continue

        # Normalize h and sqrt(N0) together so the denominator is in [1, 3].
        # Normalize y separately, then combine exponents only at the final
        # scalar boundary.  This avoids both |h|^2 overflow and h*y underflow.
        var root_noise = sqrt(noise_variance)
        var scale = root_noise
        if abs(channel_value.re) > scale:
            scale = abs(channel_value.re)
        if abs(channel_value.im) > scale:
            scale = abs(channel_value.im)
        var h_re = channel_value.re / scale
        var h_im = channel_value.im / scale
        var noise_ratio = root_noise / scale
        var denominator = (
            h_re * h_re + h_im * h_im + noise_ratio * noise_ratio
        )

        var received_scale = abs(received_value.re)
        if abs(received_value.im) > received_scale:
            received_scale = abs(received_value.im)
        if received_scale == 0.0:
            result.append(Complex64(0.0, 0.0))
            continue
        var y_re = received_value.re / received_scale
        var y_im = received_value.im / received_scale
        var real_factor = (h_re * y_re + h_im * y_im) / denominator
        var imag_factor = (h_re * y_im - h_im * y_re) / denominator
        result.append(Complex64(
            _scaled_multiply_divide(received_scale, real_factor, scale),
            _scaled_multiply_divide(received_scale, imag_factor, scale),
        ))
    return result^


def common_phase_error(
    received_pilots: Span[Complex64, ...],
    expected_pilots: Span[Complex64, ...],
) raises -> Float64:
    """Estimate common phase error from a coherent pilot dot product."""
    if len(received_pilots) == 0 or len(received_pilots) != len(expected_pilots):
        raise Error("pilot vectors must be non-empty and equal length")
    var received_scale = 0.0
    var expected_scale = 0.0
    for i in range(len(received_pilots)):
        var received_value = Complex64(received_pilots[i].re, received_pilots[i].im)
        var expected_value = Complex64(expected_pilots[i].re, expected_pilots[i].im)
        if (
            not isfinite(received_value.re)
            or not isfinite(received_value.im)
            or not isfinite(expected_value.re)
            or not isfinite(expected_value.im)
        ):
            raise Error("pilot phase inputs must be finite")
        if abs(received_value.re) > received_scale:
            received_scale = abs(received_value.re)
        if abs(received_value.im) > received_scale:
            received_scale = abs(received_value.im)
        if abs(expected_value.re) > expected_scale:
            expected_scale = abs(expected_value.re)
        if abs(expected_value.im) > expected_scale:
            expected_scale = abs(expected_value.im)
    if received_scale == 0.0 or expected_scale == 0.0:
        raise Error("pilot phase is undefined at zero coherent energy")

    # A positive global scale on either vector leaves the coherent phase
    # unchanged.  Kahan accumulation limits cancellation error after scaling.
    var coherent_re = 0.0
    var coherent_im = 0.0
    var correction_re = 0.0
    var correction_im = 0.0
    for i in range(len(received_pilots)):
        var received_re = received_pilots[i].re / received_scale
        var received_im = received_pilots[i].im / received_scale
        var expected_re = expected_pilots[i].re / expected_scale
        var expected_im = expected_pilots[i].im / expected_scale
        var product_re = (
            received_re * expected_re + received_im * expected_im
        )
        var product_im = (
            received_im * expected_re - received_re * expected_im
        )
        var adjusted_re = product_re - correction_re
        var next_re = coherent_re + adjusted_re
        correction_re = (next_re - coherent_re) - adjusted_re
        coherent_re = next_re
        var adjusted_im = product_im - correction_im
        var next_im = coherent_im + adjusted_im
        correction_im = (next_im - coherent_im) - adjusted_im
        coherent_im = next_im
    if coherent_re == 0.0 and coherent_im == 0.0:
        raise Error("pilot phase is undefined at zero coherent energy")
    return atan2(coherent_im, coherent_re)
