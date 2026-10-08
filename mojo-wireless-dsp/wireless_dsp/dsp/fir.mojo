"""Finite impulse response and full linear convolution references."""

from std.collections import Span
from std.math import isfinite
from wireless_dsp.core import Complex64


def _require_finite_real(values: Span[Float64, ...], label: StringSlice) raises:
    for index in range(len(values)):
        if not isfinite(values[index]):
            raise Error(String(label) + " values must be finite")


def _require_finite_complex(
    values: Span[Complex64, ...], label: StringSlice
) raises:
    for index in range(len(values)):
        if not isfinite(values[index].re) or not isfinite(values[index].im):
            raise Error(String(label) + " values must be finite")


def fir_real(
    signal: Span[Float64, ...], taps: Span[Float64, ...]
) raises -> List[Float64]:
    """Causal FIR with zero initial state and output length equal to signal."""
    _require_finite_real(signal, "real FIR input")
    _require_finite_real(taps, "real FIR tap")
    var output = List[Float64](capacity=len(signal))
    for n in range(len(signal)):
        var acc = 0.0
        var k_max = min(n + 1, len(taps))
        for k in range(k_max):
            acc += taps[k] * signal[n - k]
        if not isfinite(acc):
            raise Error("real FIR accumulation must remain finite")
        output.append(acc)
    return output^


def fir_complex(
    signal: Span[Complex64, ...], taps: Span[Complex64, ...]
) raises -> List[Complex64]:
    _require_finite_complex(signal, "complex FIR input")
    _require_finite_complex(taps, "complex FIR tap")
    var output = List[Complex64](capacity=len(signal))
    for n in range(len(signal)):
        var acc = Complex64(0.0, 0.0)
        var k_max = min(n + 1, len(taps))
        for k in range(k_max):
            var tap = Complex64(taps[k].re, taps[k].im)
            var sample = Complex64(signal[n - k].re, signal[n - k].im)
            acc = acc + tap * sample
        if not isfinite(acc.re) or not isfinite(acc.im):
            raise Error("complex FIR accumulation must remain finite")
        output.append(acc)
    return output^


def convolve_real(
    lhs: Span[Float64, ...], rhs: Span[Float64, ...]
) raises -> List[Float64]:
    _require_finite_real(lhs, "real convolution lhs")
    _require_finite_real(rhs, "real convolution rhs")
    if len(lhs) == 0 or len(rhs) == 0:
        return List[Float64]()
    if len(lhs) > Int.MAX - len(rhs) + 1:
        raise Error("real convolution output length exceeds the Int range")
    var output = List[Float64](length=len(lhs) + len(rhs) - 1, fill=0.0)
    for i in range(len(lhs)):
        for j in range(len(rhs)):
            output[i + j] += lhs[i] * rhs[j]
    _require_finite_real(Span(output), "real convolution output")
    return output^


def convolve_complex(
    lhs: Span[Complex64, ...], rhs: Span[Complex64, ...]
) raises -> List[Complex64]:
    _require_finite_complex(lhs, "complex convolution lhs")
    _require_finite_complex(rhs, "complex convolution rhs")
    if len(lhs) == 0 or len(rhs) == 0:
        return List[Complex64]()
    if len(lhs) > Int.MAX - len(rhs) + 1:
        raise Error("complex convolution output length exceeds the Int range")
    var output = List[Complex64](
        length=len(lhs) + len(rhs) - 1, fill=Complex64(0.0, 0.0)
    )
    for i in range(len(lhs)):
        for j in range(len(rhs)):
            var a = Complex64(lhs[i].re, lhs[i].im)
            var b = Complex64(rhs[j].re, rhs[j].im)
            output[i + j] = output[i + j] + a * b
    _require_finite_complex(Span(output), "complex convolution output")
    return output^


def fir_real_chunk(
    signal: Span[Float64, ...], taps: Span[Float64, ...], mut history: List[Float64]
) raises -> List[Float64]:
    """Streaming FIR block; history is the oldest-to-newest prior M-1 samples."""
    _require_finite_real(signal, "streaming real FIR input")
    _require_finite_real(taps, "streaming real FIR tap")
    _require_finite_real(Span(history), "streaming real FIR history")
    var required = max(0, len(taps) - 1)
    if len(history) != required:
        raise Error("FIR history length must equal tap count minus one")
    if required > Int.MAX - len(signal):
        raise Error("streaming real FIR combined length exceeds the Int range")
    var combined = List[Float64](capacity=required + len(signal))
    for i in range(required):
        combined.append(history[i])
    for i in range(len(signal)):
        combined.append(signal[i])
    var output = List[Float64](capacity=len(signal))
    for n in range(len(signal)):
        var acc = 0.0
        var end = required + n
        for k in range(len(taps)):
            acc += taps[k] * combined[end - k]
        if not isfinite(acc):
            raise Error("streaming real FIR accumulation must remain finite")
        output.append(acc)
    var next_history = List[Float64](capacity=required)
    for i in range(required):
        next_history.append(combined[len(combined) - required + i])
    history = next_history^
    return output^


def fir_complex_chunk(
    signal: Span[Complex64, ...], taps: Span[Complex64, ...],
    mut history: List[Complex64],
) raises -> List[Complex64]:
    """Complex streaming FIR with oldest-to-newest M-1 sample history."""
    _require_finite_complex(signal, "streaming complex FIR input")
    _require_finite_complex(taps, "streaming complex FIR tap")
    _require_finite_complex(Span(history), "streaming complex FIR history")
    var required = max(0, len(taps) - 1)
    if len(history) != required:
        raise Error("FIR history length must equal tap count minus one")
    if required > Int.MAX - len(signal):
        raise Error("streaming complex FIR combined length exceeds the Int range")
    var combined = List[Complex64](capacity=required + len(signal))
    for i in range(required):
        combined.append(Complex64(history[i].re, history[i].im))
    for i in range(len(signal)):
        combined.append(Complex64(signal[i].re, signal[i].im))
    var output = List[Complex64](capacity=len(signal))
    for n in range(len(signal)):
        var acc = Complex64(0.0, 0.0)
        var end = required + n
        for k in range(len(taps)):
            var tap = Complex64(taps[k].re, taps[k].im)
            var sample = Complex64(combined[end - k].re, combined[end - k].im)
            acc = acc + tap * sample
        if not isfinite(acc.re) or not isfinite(acc.im):
            raise Error("streaming complex FIR accumulation must remain finite")
        output.append(acc)
    var next_history = List[Complex64](capacity=required)
    for i in range(required):
        var sample = combined[len(combined) - required + i]
        next_history.append(Complex64(sample.re, sample.im))
    history = next_history^
    return output^
