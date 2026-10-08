"""Readable linear and rational sample-rate conversion references."""

from std.collections import Span
from wireless_dsp.core import Complex64


def linear_resample_real(
    values: Span[Float64, ...], output_length: Int
) raises -> List[Float64]:
    """Resample a finite real vector while preserving both endpoint samples."""
    if output_length < 0 or (len(values) == 0 and output_length != 0):
        raise Error("invalid linear-resampler dimensions")
    if output_length == 0:
        return List[Float64]()
    if len(values) == 1:
        return List[Float64](length=output_length, fill=values[0])
    if output_length == 1:
        return List[Float64](length=1, fill=values[0])
    var result = List[Float64](capacity=output_length)
    for i in range(output_length):
        var numerator = i * (len(values) - 1)
        var left = numerator // (output_length - 1)
        var remainder = numerator % (output_length - 1)
        if left == len(values) - 1:
            result.append(values[left])
        else:
            var fraction = Float64(remainder) / Float64(output_length - 1)
            result.append(values[left] + fraction * (values[left + 1] - values[left]))
    return result^


def linear_resample_complex(
    values: Span[Complex64, ...], output_length: Int
) raises -> List[Complex64]:
    if output_length < 0 or (len(values) == 0 and output_length != 0):
        raise Error("invalid linear-resampler dimensions")
    if output_length == 0:
        return List[Complex64]()
    if len(values) == 1:
        var result = List[Complex64](capacity=output_length)
        for _ in range(output_length):
            result.append(Complex64(values[0].re, values[0].im))
        return result^
    if output_length == 1:
        var result = List[Complex64](capacity=1)
        result.append(Complex64(values[0].re, values[0].im))
        return result^
    var result = List[Complex64](capacity=output_length)
    for i in range(output_length):
        var numerator = i * (len(values) - 1)
        var left = numerator // (output_length - 1)
        var remainder = numerator % (output_length - 1)
        if left == len(values) - 1:
            result.append(Complex64(values[left].re, values[left].im))
        else:
            var fraction = Float64(remainder) / Float64(output_length - 1)
            result.append(Complex64(
                values[left].re + fraction * (values[left + 1].re - values[left].re),
                values[left].im + fraction * (values[left + 1].im - values[left].im),
            ))
    return result^


def rational_resample_real(
    values: Span[Float64, ...],
    taps: Span[Float64, ...],
    up: Int,
    down: Int,
) raises -> List[Float64]:
    """Direct ``upfirdn`` golden reference without materializing inserted zeros."""
    if up < 1 or down < 1 or len(taps) == 0:
        raise Error("rational resampler requires positive factors and non-empty taps")
    if len(values) == 0:
        return List[Float64]()
    # Int128 is wide enough for the product of any two non-negative Int
    # values.  Keep both the length equation and the polyphase time indices
    # in that domain so large, cancelling up/down ratios cannot wrap Int.
    var final_time = (
        Int128(len(values) - 1) * Int128(up) + Int128(len(taps) - 1)
    )
    var output_length_wide = final_time // Int128(down) + Int128(1)
    if output_length_wide > Int128(Int.MAX):
        raise Error("rational-resampler output length exceeds Int")
    var output_length = Int(output_length_wide)
    var result = List[Float64](capacity=output_length)
    for m in range(output_length):
        var time = Int128(m) * Int128(down)
        var acc = 0.0
        for n in range(len(values)):
            var tap_index = time - Int128(n) * Int128(up)
            if tap_index >= Int128(0) and tap_index < Int128(len(taps)):
                acc += values[n] * taps[Int(tap_index)]
        result.append(acc)
    return result^


def rational_resample_complex(
    values: Span[Complex64, ...],
    taps: Span[Float64, ...],
    up: Int,
    down: Int,
) raises -> List[Complex64]:
    if up < 1 or down < 1 or len(taps) == 0:
        raise Error("rational resampler requires positive factors and non-empty taps")
    if len(values) == 0:
        return List[Complex64]()
    var final_time = (
        Int128(len(values) - 1) * Int128(up) + Int128(len(taps) - 1)
    )
    var output_length_wide = final_time // Int128(down) + Int128(1)
    if output_length_wide > Int128(Int.MAX):
        raise Error("rational-resampler output length exceeds Int")
    var output_length = Int(output_length_wide)
    var result = List[Complex64](capacity=output_length)
    for m in range(output_length):
        var time = Int128(m) * Int128(down)
        var acc = Complex64(0.0, 0.0)
        for n in range(len(values)):
            var tap_index = time - Int128(n) * Int128(up)
            if tap_index >= Int128(0) and tap_index < Int128(len(taps)):
                var value = Complex64(values[n].re, values[n].im)
                acc = acc + Complex64(
                    value.re * taps[Int(tap_index)],
                    value.im * taps[Int(tap_index)],
                )
        result.append(acc)
    return result^
