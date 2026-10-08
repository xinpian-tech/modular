"""Readable scalar reductions used as CPU golden references."""

from std.collections import Span
from std.math import isfinite
from wireless_dsp.core import Complex


def sum_real[dtype: DType](values: Span[Scalar[dtype], ...]) -> Scalar[dtype]:
    var total = Scalar[dtype](0)
    for i in range(len(values)):
        total += values[i]
    return total


def dot_real[dtype: DType](
    lhs: Span[Scalar[dtype], ...], rhs: Span[Scalar[dtype], ...]
) raises -> Scalar[dtype]:
    if len(lhs) != len(rhs):
        raise Error("dot operands must have equal length")
    var total = Scalar[dtype](0)
    for i in range(len(lhs)):
        total += lhs[i] * rhs[i]
    return total


def energy_real[dtype: DType](values: Span[Scalar[dtype], ...]) -> Scalar[dtype]:
    var total = Scalar[dtype](0)
    for i in range(len(values)):
        total += values[i] * values[i]
    return total


def sum_complex[dtype: DType](values: Span[Complex[dtype], ...]) -> Complex[dtype]:
    var total = Complex[dtype](0, 0)
    for i in range(len(values)):
        total = total + Complex[dtype](values[i].re, values[i].im)
    return total


def dot_complex[dtype: DType](
    lhs: Span[Complex[dtype], ...], rhs: Span[Complex[dtype], ...]
) raises -> Complex[dtype]:
    """Hermitian dot product ``sum(conj(lhs[i]) * rhs[i])``."""
    if len(lhs) != len(rhs):
        raise Error("dot operands must have equal length")
    var total = Complex[dtype](0, 0)
    for i in range(len(lhs)):
        var a = Complex[dtype](lhs[i].re, lhs[i].im)
        var b = Complex[dtype](rhs[i].re, rhs[i].im)
        total = total + a.conjugate() * b
    return total


def energy_complex[dtype: DType](values: Span[Complex[dtype], ...]) -> Scalar[dtype]:
    var total = Scalar[dtype](0)
    for i in range(len(values)):
        total += values[i].re * values[i].re + values[i].im * values[i].im
    return total


def argmax_real[dtype: DType](values: Span[Scalar[dtype], ...]) raises -> Int:
    if len(values) == 0:
        raise Error("argmax requires non-empty input")
    var best = 0
    for i in range(1, len(values)):
        if values[i] > values[best]:
            best = i
    return best


def min_real[dtype: DType](values: Span[Scalar[dtype], ...]) raises -> Scalar[dtype]:
    if len(values) == 0:
        raise Error("minimum requires non-empty input")
    var result = values[0]
    for i in range(1, len(values)):
        result = min(result, values[i])
    return result


def max_real[dtype: DType](values: Span[Scalar[dtype], ...]) raises -> Scalar[dtype]:
    if len(values) == 0:
        raise Error("maximum requires non-empty input")
    var result = values[0]
    for i in range(1, len(values)):
        result = max(result, values[i])
    return result


def min1_min2(values: Span[Float64, ...]) raises -> Tuple[Float64, Float64, Int]:
    """Return smallest value, second smallest value, and smallest index."""
    if len(values) < 2:
        raise Error("min1/min2 requires at least two values")
    if not isfinite(values[0]) or not isfinite(values[1]):
        raise Error("min1/min2 inputs must be finite")
    var first = values[0]
    var second = values[1]
    var first_index = 0
    if second < first:
        first = values[1]
        second = values[0]
        first_index = 1
    for i in range(2, len(values)):
        if not isfinite(values[i]):
            raise Error("min1/min2 inputs must be finite")
        if values[i] < first:
            second = first
            first = values[i]
            first_index = i
        elif values[i] < second:
            second = values[i]
    return (first, second, first_index)


def sign_product(values: Span[Float64, ...]) -> Int:
    """Return -1 for an odd number of negative inputs, otherwise +1."""
    var result = 1
    for i in range(len(values)):
        if values[i] < 0.0:
            result = -result
    return result
