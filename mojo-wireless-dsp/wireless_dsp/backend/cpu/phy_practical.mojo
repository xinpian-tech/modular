"""Allocation-controlled Float32 OFDM and SISO PHY kernels.

This module extends :mod:`wireless_dsp.backend.cpu.practical` with the PHY
operations that sit around its radix-2 FFT.  The public ``*_into`` functions
write caller-owned, exactly sized ``List[Complex32]`` storage; the convenience
functions allocate fresh owning results.  Successful OFDM ``*_into`` calls do
not allocate and reuse both an ``FFTPlanF32`` and an ``OFDMWorkspaceF32``.

The supported production transform sizes are 64, 128, 256, 512, 1024, 2048,
and 4096.  Forward transforms are unscaled and inverse transforms have exactly
one ``1/N`` normalization, inherited from ``FFTPlanF32``.  Inputs, plans,
workspaces, and every public arithmetic boundary are validated.  A positive
common scale is removed before FFT butterflies and restored afterward, so an
extreme finite symbol is rejected only if the final Float32 component is not
representable, rather than because an avoidable intermediate overflowed.

Mojo's exclusivity rules require the read-only spans, mutable workspace, and
mutable output passed to an ``*_into`` function to be non-aliasing.  The
owning wrappers always return fresh storage.  Workspaces support sequential
reuse and must not be shared by concurrent calls.

SISO division uses common scaling plus Smith's complex-division form.  Scalar
intermediates are widened after binary32 input validation; this preserves the
mathematical Float32 API at extreme finite scales while every returned value
is narrowed with explicit overflow and non-zero-underflow checks.
"""

from std.collections import Span
from std.math import atan2, cos, isfinite, sin
from wireless_dsp.core import Complex32
from wireless_dsp.backend.cpu.practical import (
    FFTPlanF32,
    fft_in_place_f32_with_plan,
    make_fft_plan_f32,
)


struct OFDMWorkspaceF32(Movable):
    """Reusable exactly-sized scratch storage for one Float32 OFDM size."""

    var size: Int
    var scratch: List[Complex32]

    def __init__(out self, size: Int) raises:
        _validate_ofdm_size_f32(size)
        self.size = size
        self.scratch = List[Complex32](
            length=size, fill=Complex32(0.0, 0.0)
        )


def make_ofdm_workspace_f32(size: Int) raises -> OFDMWorkspaceF32:
    """Allocate reusable scratch for one supported Float32 OFDM FFT size."""
    return OFDMWorkspaceF32(size)


def _validate_ofdm_size_f32(size: Int) raises:
    if (
        size != 64
        and size != 128
        and size != 256
        and size != 512
        and size != 1024
        and size != 2048
        and size != 4096
    ):
        raise Error("Float32 OFDM FFT size must be 64..4096 power-of-two")


def _is_finite_complex_f32(value: Complex32) -> Bool:
    return isfinite(value.re) and isfinite(value.im)


def _require_finite_complex_f32(
    values: Span[Complex32, ...], message: StringLiteral
) raises:
    for index in range(len(values)):
        var value = Complex32(values[index].re, values[index].im)
        if not _is_finite_complex_f32(value):
            raise Error(message)


def _validate_ofdm_plan_f32(
    plan: FFTPlanF32, size: Int, inverse: Bool
) raises:
    _validate_ofdm_size_f32(size)
    if plan.size != size or plan.inverse != inverse:
        raise Error("Float32 OFDM FFT plan size/direction mismatch")
    if len(plan.twiddles) != size // 2:
        raise Error("Float32 OFDM FFT plan has invalid twiddle storage")
    _require_finite_complex_f32(
        Span(plan.twiddles), "Float32 OFDM FFT twiddles must be finite"
    )


def _validate_ofdm_workspace_f32(
    workspace: OFDMWorkspaceF32, size: Int
) raises:
    _validate_ofdm_size_f32(size)
    if workspace.size != size or len(workspace.scratch) != size:
        raise Error("Float32 OFDM workspace size/storage mismatch")


def _validate_output_f32(output: List[Complex32], length: Int) raises:
    if length < 0 or len(output) != length:
        raise Error("Float32 PHY output storage has the wrong length")


def _narrow_finite_f32(value: Float64) raises -> Float32:
    """Narrow a finite real result, rejecting overflow and nonzero underflow."""
    if not isfinite(value):
        raise Error("Float32 PHY result is not finite")
    var result = Float32(value)
    if not isfinite(result) or (result == 0.0 and value != 0.0):
        raise Error("Float32 PHY result is outside the representable range")
    return result


def _narrow_complex_f32(real: Float64, imaginary: Float64) raises -> Complex32:
    return Complex32(_narrow_finite_f32(real), _narrow_finite_f32(imaginary))


def _copy_scaled_input_f32(
    values: Span[Complex32, ...], mut workspace: OFDMWorkspaceF32
) raises -> Float32:
    """Copy finite values divided by their largest absolute component."""
    var scale = Float32(0.0)
    for index in range(len(values)):
        var value = Complex32(values[index].re, values[index].im)
        if not _is_finite_complex_f32(value):
            raise Error("Float32 OFDM input samples must be finite")
        scale = max(scale, max(abs(value.re), abs(value.im)))
    if scale == 0.0:
        for index in range(len(values)):
            workspace.scratch[index] = Complex32(0.0, 0.0)
        return scale
    for index in range(len(values)):
        workspace.scratch[index] = Complex32(
            values[index].re / scale, values[index].im / scale
        )
    return scale


def _restore_fft_scale_f32(
    scale: Float32, mut workspace: OFDMWorkspaceF32
) raises:
    if scale == 0.0:
        return
    # Float64 multiplication cannot overflow for two binary32 inputs.  The
    # explicit narrowing check defines the public output boundary.
    for index in range(workspace.size):
        var value = workspace.scratch[index]
        workspace.scratch[index] = _narrow_complex_f32(
            Float64(value.re) * Float64(scale),
            Float64(value.im) * Float64(scale),
        )


def ofdm_modulate_f32_into(
    spectrum: Span[Complex32, ...],
    cyclic_prefix: Int,
    inverse_plan: FFTPlanF32,
    mut workspace: OFDMWorkspaceF32,
    mut output: List[Complex32],
) raises:
    """Write one CP-OFDM symbol using reusable plan, scratch, and output.

    ``spectrum`` has ``N`` elements and ``output`` must have exactly
    ``N + cyclic_prefix`` elements.  ``inverse_plan`` must be an inverse plan
    for the same supported size.  The IFFT applies exactly ``1/N``.  Inputs,
    workspace, and output are non-aliasing under Mojo's exclusivity rule.
    """
    var size = len(spectrum)
    _validate_ofdm_size_f32(size)
    if cyclic_prefix < 0 or cyclic_prefix > size:
        raise Error("Float32 OFDM cyclic prefix must be in [0, FFT size]")
    # The supported maximum is 4096, nevertheless keep the allocation
    # arithmetic contract explicit before forming N + CP.
    if cyclic_prefix > Int.MAX - size:
        raise Error("Float32 OFDM symbol length overflows Int")
    _validate_ofdm_plan_f32(inverse_plan, size, True)
    _validate_ofdm_workspace_f32(workspace, size)
    _validate_output_f32(output, size + cyclic_prefix)

    var scale = _copy_scaled_input_f32(spectrum, workspace)
    fft_in_place_f32_with_plan(workspace.scratch, inverse_plan)
    _restore_fft_scale_f32(scale, workspace)
    for index in range(cyclic_prefix):
        var value = workspace.scratch[size - cyclic_prefix + index]
        output[index] = Complex32(value.re, value.im)
    for index in range(size):
        var value = workspace.scratch[index]
        output[cyclic_prefix + index] = Complex32(value.re, value.im)


def ofdm_modulate_f32(
    spectrum: Span[Complex32, ...], cyclic_prefix: Int
) raises -> List[Complex32]:
    """Return a fresh ``1/N``-normalized Float32 CP-OFDM symbol."""
    var size = len(spectrum)
    _validate_ofdm_size_f32(size)
    if cyclic_prefix < 0 or cyclic_prefix > size:
        raise Error("Float32 OFDM cyclic prefix must be in [0, FFT size]")
    if cyclic_prefix > Int.MAX - size:
        raise Error("Float32 OFDM symbol length overflows Int")
    var plan = make_fft_plan_f32(size, inverse=True)
    var workspace = make_ofdm_workspace_f32(size)
    var output = List[Complex32](
        length=size + cyclic_prefix, fill=Complex32(0.0, 0.0)
    )
    ofdm_modulate_f32_into(
        spectrum, cyclic_prefix, plan, workspace, output
    )
    return output^


def ofdm_demodulate_f32_into(
    samples: Span[Complex32, ...],
    transform_size: Int,
    cyclic_prefix: Int,
    forward_plan: FFTPlanF32,
    mut workspace: OFDMWorkspaceF32,
    mut output: List[Complex32],
) raises:
    """Remove one cyclic prefix and write an unscaled Float32 FFT.

    ``samples`` must contain exactly ``transform_size + cyclic_prefix``
    elements and ``output`` exactly ``transform_size``.  The forward plan and
    workspace are reusable sequentially and must match the supported size.
    """
    _validate_ofdm_size_f32(transform_size)
    if cyclic_prefix < 0 or cyclic_prefix > transform_size:
        raise Error("Float32 OFDM cyclic prefix must be in [0, FFT size]")
    if cyclic_prefix > Int.MAX - transform_size:
        raise Error("Float32 OFDM symbol length overflows Int")
    if len(samples) != transform_size + cyclic_prefix:
        raise Error("Float32 OFDM symbol length does not match FFT and CP")
    _validate_ofdm_plan_f32(forward_plan, transform_size, False)
    _validate_ofdm_workspace_f32(workspace, transform_size)
    _validate_output_f32(output, transform_size)

    # Copy just the useful symbol to a scale-normalized workspace.  This also
    # validates every consumed sample, including the CP for a fully finite
    # public symbol contract.
    _require_finite_complex_f32(
        samples, "Float32 OFDM input samples must be finite"
    )
    var scale = Float32(0.0)
    for index in range(transform_size):
        var value = samples[cyclic_prefix + index]
        scale = max(scale, max(abs(value.re), abs(value.im)))
    if scale == 0.0:
        for index in range(transform_size):
            workspace.scratch[index] = Complex32(0.0, 0.0)
    else:
        for index in range(transform_size):
            var value = samples[cyclic_prefix + index]
            workspace.scratch[index] = Complex32(
                value.re / scale, value.im / scale
            )
    fft_in_place_f32_with_plan(workspace.scratch, forward_plan)
    _restore_fft_scale_f32(scale, workspace)
    for index in range(transform_size):
        var value = workspace.scratch[index]
        output[index] = Complex32(value.re, value.im)


def ofdm_demodulate_f32(
    samples: Span[Complex32, ...], transform_size: Int, cyclic_prefix: Int
) raises -> List[Complex32]:
    """Return a fresh unscaled Float32 FFT after cyclic-prefix removal."""
    _validate_ofdm_size_f32(transform_size)
    var plan = make_fft_plan_f32(transform_size)
    var workspace = make_ofdm_workspace_f32(transform_size)
    var output = List[Complex32](
        length=transform_size, fill=Complex32(0.0, 0.0)
    )
    ofdm_demodulate_f32_into(
        samples,
        transform_size,
        cyclic_prefix,
        plan,
        workspace,
        output,
    )
    return output^


def complex_divide_f32(lhs: Complex32, rhs: Complex32) raises -> Complex32:
    """Divide finite binary32 scalars with common scaling and Smith's form.

    A zero divisor, a non-finite operand, or a quotient component that
    overflows or underflows to zero in Float32 is rejected.  Exact zero
    quotient components remain valid.
    """
    if not _is_finite_complex_f32(lhs) or not _is_finite_complex_f32(rhs):
        raise Error("Float32 complex division operands must be finite")
    if rhs.re == 0.0 and rhs.im == 0.0:
        raise Error("Float32 complex divisor must be non-zero")

    var scale = max(
        max(abs(Float64(lhs.re)), abs(Float64(lhs.im))),
        max(abs(Float64(rhs.re)), abs(Float64(rhs.im))),
    )
    var a = Float64(lhs.re) / scale
    var b = Float64(lhs.im) / scale
    var c = Float64(rhs.re) / scale
    var d = Float64(rhs.im) / scale
    var real: Float64
    var imaginary: Float64
    if abs(c) >= abs(d):
        var ratio = d / c
        var denominator = c + d * ratio
        real = (a + b * ratio) / denominator
        imaginary = (b - a * ratio) / denominator
    else:
        var ratio = c / d
        var denominator = d + c * ratio
        real = (a * ratio + b) / denominator
        imaginary = (b * ratio - a) / denominator
    return _narrow_complex_f32(real, imaginary)


def ls_channel_estimate_f32_into(
    received: Span[Complex32, ...],
    known: Span[Complex32, ...],
    mut output: List[Complex32],
) raises:
    """Write per-pilot least-squares estimates ``received / known``."""
    if len(received) == 0 or len(received) != len(known):
        raise Error("Float32 LS pilot vectors must be non-empty/equal length")
    _validate_output_f32(output, len(received))
    for index in range(len(received)):
        output[index] = complex_divide_f32(
            Complex32(received[index].re, received[index].im),
            Complex32(known[index].re, known[index].im),
        )


def ls_channel_estimate_f32(
    received: Span[Complex32, ...], known: Span[Complex32, ...]
) raises -> List[Complex32]:
    """Return fresh owning per-pilot Float32 least-squares estimates."""
    if len(received) == 0 or len(received) != len(known):
        raise Error("Float32 LS pilot vectors must be non-empty/equal length")
    var output = List[Complex32](
        length=len(received), fill=Complex32(0.0, 0.0)
    )
    ls_channel_estimate_f32_into(received, known, output)
    return output^


def zero_forcing_equalize_siso_f32_into(
    received: Span[Complex32, ...],
    channel: Span[Complex32, ...],
    mut output: List[Complex32],
) raises:
    """Write per-subcarrier SISO zero-forcing estimates ``received / h``."""
    if len(received) != len(channel):
        raise Error("Float32 ZF samples/channel dimensions must match")
    _validate_output_f32(output, len(received))
    for index in range(len(received)):
        output[index] = complex_divide_f32(
            Complex32(received[index].re, received[index].im),
            Complex32(channel[index].re, channel[index].im),
        )


def zero_forcing_equalize_siso_f32(
    received: Span[Complex32, ...], channel: Span[Complex32, ...]
) raises -> List[Complex32]:
    """Return fresh owning Float32 SISO zero-forcing estimates."""
    if len(received) != len(channel):
        raise Error("Float32 ZF samples/channel dimensions must match")
    var output = List[Complex32](
        length=len(received), fill=Complex32(0.0, 0.0)
    )
    zero_forcing_equalize_siso_f32_into(received, channel, output)
    return output^


def _mmse_one_f32(
    received: Complex32, channel: Complex32, noise_variance: Float32
) raises -> Complex32:
    if not _is_finite_complex_f32(received) or not _is_finite_complex_f32(channel):
        raise Error("Float32 MMSE samples and channel estimates must be finite")
    if noise_variance == 0.0:
        return complex_divide_f32(received, channel)
    var yr = Float64(received.re)
    var yi = Float64(received.im)
    var hr = Float64(channel.re)
    var hi = Float64(channel.im)
    var denominator = hr * hr + hi * hi + Float64(noise_variance)
    var real = (hr * yr + hi * yi) / denominator
    var imaginary = (hr * yi - hi * yr) / denominator
    return _narrow_complex_f32(real, imaginary)


def mmse_equalize_siso_f32_into(
    received: Span[Complex32, ...],
    channel: Span[Complex32, ...],
    noise_variance: Float32,
    mut output: List[Complex32],
) raises:
    """Write unit-power SISO MMSE values ``conj(h)y/(|h|^2+N0)``."""
    if (
        len(received) != len(channel)
        or not isfinite(noise_variance)
        or noise_variance < 0.0
    ):
        raise Error("Float32 MMSE dimensions/noise variance are invalid")
    _validate_output_f32(output, len(received))
    for index in range(len(received)):
        output[index] = _mmse_one_f32(
            Complex32(received[index].re, received[index].im),
            Complex32(channel[index].re, channel[index].im),
            noise_variance,
        )


def mmse_equalize_siso_f32(
    received: Span[Complex32, ...],
    channel: Span[Complex32, ...],
    noise_variance: Float32,
) raises -> List[Complex32]:
    """Return fresh owning unit-power Float32 SISO MMSE estimates."""
    if len(received) != len(channel):
        raise Error("Float32 MMSE samples/channel dimensions must match")
    var output = List[Complex32](
        length=len(received), fill=Complex32(0.0, 0.0)
    )
    mmse_equalize_siso_f32_into(
        received, channel, noise_variance, output
    )
    return output^


def estimate_pilot_noise_variance_f32(
    received: Span[Complex32, ...],
    known: Span[Complex32, ...],
    channel: Span[Complex32, ...],
) raises -> Float32:
    """Return mean pilot residual power ``mean(|y-h*x|^2)`` in Float32.

    Complex products and residual accumulation are widened after finite input
    validation.  A positive value outside the normal/subnormal Float32 range
    is rejected rather than silently becoming infinity or zero.
    """
    if (
        len(received) == 0
        or len(received) != len(known)
        or len(received) != len(channel)
    ):
        raise Error("Float32 pilot residual vectors must be non-empty/equal")
    var scale = Float64(0.0)
    for index in range(len(received)):
        var y = Complex32(received[index].re, received[index].im)
        var x = Complex32(known[index].re, known[index].im)
        var h = Complex32(channel[index].re, channel[index].im)
        if (
            not _is_finite_complex_f32(y)
            or not _is_finite_complex_f32(x)
            or not _is_finite_complex_f32(h)
        ):
            raise Error("Float32 pilot residual inputs must be finite")
        var residual_re = (
            Float64(y.re)
            - (Float64(h.re) * Float64(x.re) - Float64(h.im) * Float64(x.im))
        )
        var residual_im = (
            Float64(y.im)
            - (Float64(h.re) * Float64(x.im) + Float64(h.im) * Float64(x.re))
        )
        scale = max(scale, max(abs(residual_re), abs(residual_im)))
    if scale == 0.0:
        return Float32(0.0)

    var normalized_energy = Float64(0.0)
    for index in range(len(received)):
        var residual_re = (
            Float64(received[index].re)
            - (
                Float64(channel[index].re) * Float64(known[index].re)
                - Float64(channel[index].im) * Float64(known[index].im)
            )
        ) / scale
        var residual_im = (
            Float64(received[index].im)
            - (
                Float64(channel[index].re) * Float64(known[index].im)
                + Float64(channel[index].im) * Float64(known[index].re)
            )
        ) / scale
        normalized_energy += residual_re * residual_re + residual_im * residual_im
    var result = (
        scale
        * scale
        * (normalized_energy / Float64(len(received)))
    )
    return _narrow_finite_f32(result)


def common_phase_error_f32(
    received_pilots: Span[Complex32, ...],
    expected_pilots: Span[Complex32, ...],
) raises -> Float32:
    """Estimate CPE as ``arg(sum(received * conj(expected)))``.

    Independent positive scaling of each pilot vector leaves the result
    unchanged.  Compensated Float64 accumulation prevents avoidable binary32
    overflow and limits cancellation error before the Float32 result boundary.
    """
    if (
        len(received_pilots) == 0
        or len(received_pilots) != len(expected_pilots)
    ):
        raise Error("Float32 CPE pilot vectors must be non-empty/equal")
    var received_scale = Float64(0.0)
    var expected_scale = Float64(0.0)
    for index in range(len(received_pilots)):
        var received = Complex32(
            received_pilots[index].re, received_pilots[index].im
        )
        var expected = Complex32(
            expected_pilots[index].re, expected_pilots[index].im
        )
        if not _is_finite_complex_f32(received) or not _is_finite_complex_f32(expected):
            raise Error("Float32 CPE pilot inputs must be finite")
        received_scale = max(
            received_scale,
            max(abs(Float64(received.re)), abs(Float64(received.im))),
        )
        expected_scale = max(
            expected_scale,
            max(abs(Float64(expected.re)), abs(Float64(expected.im))),
        )
    if received_scale == 0.0 or expected_scale == 0.0:
        raise Error("Float32 CPE is undefined at zero coherent energy")

    var coherent_re = Float64(0.0)
    var coherent_im = Float64(0.0)
    var correction_re = Float64(0.0)
    var correction_im = Float64(0.0)
    for index in range(len(received_pilots)):
        var rr = Float64(received_pilots[index].re) / received_scale
        var ri = Float64(received_pilots[index].im) / received_scale
        var er = Float64(expected_pilots[index].re) / expected_scale
        var ei = Float64(expected_pilots[index].im) / expected_scale
        var product_re = rr * er + ri * ei
        var product_im = ri * er - rr * ei
        var adjusted_re = product_re - correction_re
        var next_re = coherent_re + adjusted_re
        correction_re = (next_re - coherent_re) - adjusted_re
        coherent_re = next_re
        var adjusted_im = product_im - correction_im
        var next_im = coherent_im + adjusted_im
        correction_im = (next_im - coherent_im) - adjusted_im
        coherent_im = next_im
    if coherent_re == 0.0 and coherent_im == 0.0:
        raise Error("Float32 CPE is undefined at zero coherent energy")
    return _narrow_finite_f32(atan2(coherent_im, coherent_re))


def correct_common_phase_error_f32_into(
    samples: Span[Complex32, ...],
    phase_error: Float32,
    mut output: List[Complex32],
) raises:
    """Write ``samples * exp(-j*phase_error)`` into exact caller storage."""
    if not isfinite(phase_error):
        raise Error("Float32 CPE correction phase must be finite")
    _validate_output_f32(output, len(samples))
    var cosine = cos(Float64(phase_error))
    var sine = sin(Float64(phase_error))
    for index in range(len(samples)):
        var sample = Complex32(samples[index].re, samples[index].im)
        if not _is_finite_complex_f32(sample):
            raise Error("Float32 CPE correction samples must be finite")
        output[index] = _narrow_complex_f32(
            Float64(sample.re) * cosine + Float64(sample.im) * sine,
            Float64(sample.im) * cosine - Float64(sample.re) * sine,
        )


def correct_common_phase_error_f32(
    samples: Span[Complex32, ...], phase_error: Float32
) raises -> List[Complex32]:
    """Return fresh owning samples rotated by ``-phase_error``."""
    var output = List[Complex32](
        length=len(samples), fill=Complex32(0.0, 0.0)
    )
    correct_common_phase_error_f32_into(samples, phase_error, output)
    return output^
