"""Deterministic real windows and window-application primitives."""

from std.collections import Span
from std.math import cos
from wireless_dsp.core import Complex64

comptime _TWO_PI = 6.283185307179586476925286766559


def rectangular_window(length: Int) raises -> List[Float64]:
    if length < 0:
        raise Error("window length must be non-negative")
    return List[Float64](length=length, fill=1.0)


def hann_window(length: Int) raises -> List[Float64]:
    """Symmetric Hann window; the single-sample definition is one."""
    if length < 0:
        raise Error("window length must be non-negative")
    if length == 0:
        return List[Float64]()
    if length == 1:
        return List[Float64](length=1, fill=1.0)
    var result = List[Float64](capacity=length)
    for n in range(length):
        result.append(0.5 - 0.5 * cos(_TWO_PI * Float64(n) / Float64(length - 1)))
    return result^


def hamming_window(length: Int) raises -> List[Float64]:
    if length < 0:
        raise Error("window length must be non-negative")
    if length == 0:
        return List[Float64]()
    if length == 1:
        return List[Float64](length=1, fill=1.0)
    var result = List[Float64](capacity=length)
    for n in range(length):
        result.append(0.54 - 0.46 * cos(_TWO_PI * Float64(n) / Float64(length - 1)))
    return result^


def blackman_window(length: Int) raises -> List[Float64]:
    if length < 0:
        raise Error("window length must be non-negative")
    if length == 0:
        return List[Float64]()
    if length == 1:
        return List[Float64](length=1, fill=1.0)
    var result = List[Float64](capacity=length)
    for n in range(length):
        var angle = _TWO_PI * Float64(n) / Float64(length - 1)
        result.append(0.42 - 0.5 * cos(angle) + 0.08 * cos(2.0 * angle))
    return result^


def apply_window_real(
    values: Span[Float64, ...], window: Span[Float64, ...]
) raises -> List[Float64]:
    if len(values) != len(window):
        raise Error("signal and window lengths must match")
    var result = List[Float64](capacity=len(values))
    for i in range(len(values)):
        result.append(values[i] * window[i])
    return result^


def apply_window_complex(
    values: Span[Complex64, ...], window: Span[Float64, ...]
) raises -> List[Complex64]:
    if len(values) != len(window):
        raise Error("signal and window lengths must match")
    var result = List[Complex64](capacity=len(values))
    for i in range(len(values)):
        result.append(Complex64(values[i].re * window[i], values[i].im * window[i]))
    return result^
