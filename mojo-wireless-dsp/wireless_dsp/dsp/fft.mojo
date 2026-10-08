"""Radix-2 FFT/IFFT readable reference implementation."""

from std.collections import Span
from std.math import cos, sin, sqrt
from std.utils.numerics import isfinite
from wireless_dsp.core import Complex64

comptime _TWO_PI = 6.283185307179586476925286766559


struct FFTPlan(Movable):
    """Reusable radix-2 twiddle table for one transform size/direction."""

    var size: Int
    var inverse: Bool
    var twiddles: List[Complex64]

    def __init__(
        out self, size: Int, inverse: Bool, var twiddles: List[Complex64]
    ) raises:
        _validate_fft_size(size)
        if len(twiddles) != size // 2:
            raise Error("FFT plan has the wrong number of twiddles")
        self.size = size
        self.inverse = inverse
        self.twiddles = twiddles^


def _validate_fft_size(size: Int) raises:
    if size < 1 or (size & (size - 1)) != 0:
        raise Error("FFT length must be a positive power of two")


def _validate_fft_plan(plan: FFTPlan) raises:
    """Reject mutated or caller-constructed plans before unsafe indexing."""
    _validate_fft_size(plan.size)
    if len(plan.twiddles) != plan.size // 2:
        raise Error("FFT plan has the wrong number of twiddles")
    var direction = _TWO_PI if plan.inverse else -_TWO_PI
    for k in range(len(plan.twiddles)):
        var value = plan.twiddles[k]
        if not isfinite(value.re) or not isfinite(value.im):
            raise Error("FFT plan twiddles must be finite")
        var angle = direction * Float64(k) / Float64(plan.size)
        if (
            abs(value.re - cos(angle)) > 1.0e-12
            or abs(value.im - sin(angle)) > 1.0e-12
        ):
            raise Error("FFT plan twiddles do not match its size and direction")


def make_fft_plan(size: Int, *, inverse: Bool = False) raises -> FFTPlan:
    _validate_fft_size(size)
    var twiddles = List[Complex64](capacity=size // 2)
    var direction = _TWO_PI if inverse else -_TWO_PI
    for k in range(size // 2):
        var angle = direction * Float64(k) / Float64(size)
        twiddles.append(Complex64(cos(angle), sin(angle)))
    return FFTPlan(size, inverse, twiddles^)


def fft_in_place_with_plan(mut data: List[Complex64], plan: FFTPlan) raises:
    """Radix-2 transform using a caller-reusable full-length twiddle table."""
    _validate_fft_plan(plan)
    if len(data) != plan.size:
        raise Error("FFT data length does not match its plan")
    var size = plan.size
    var j = 0
    for i in range(1, size):
        var bit = size >> 1
        while (j & bit) != 0:
            j ^= bit
            bit >>= 1
        j ^= bit
        if i < j:
            var temporary = data[i]
            data[i] = data[j]
            data[j] = temporary

    var length = 2
    while length <= size:
        var base = 0
        while base < size:
            for offset in range(length // 2):
                var twiddle = plan.twiddles[offset * size // length]
                var even = data[base + offset]
                var odd = data[base + offset + length // 2] * twiddle
                data[base + offset] = even + odd
                data[base + offset + length // 2] = even - odd
            base += length
        length <<= 1
    if plan.inverse:
        var scale = 1.0 / Float64(size)
        for i in range(size):
            data[i] = Complex64(data[i].re * scale, data[i].im * scale)


def fft_in_place(mut data: List[Complex64], *, inverse: Bool = False) raises:
    """Transform ``data`` in place; inverse applies exactly one ``1/N`` scale."""
    var size = len(data)
    _validate_fft_size(size)

    # Bit-reversal permutation.
    var j = 0
    for i in range(1, size):
        var bit = size >> 1
        while (j & bit) != 0:
            j ^= bit
            bit >>= 1
        j ^= bit
        if i < j:
            var tmp = data[i]
            data[i] = data[j]
            data[j] = tmp

    var length = 2
    while length <= size:
        var angle = (_TWO_PI if inverse else -_TWO_PI) / Float64(length)
        var stage_step = Complex64(cos(angle), sin(angle))
        var base = 0
        while base < size:
            var twiddle = Complex64(1.0, 0.0)
            for offset in range(length // 2):
                var even = data[base + offset]
                var odd = data[base + offset + length // 2] * twiddle
                data[base + offset] = even + odd
                data[base + offset + length // 2] = even - odd
                twiddle = twiddle * stage_step
            base += length
        length <<= 1

    if inverse:
        var scale = 1.0 / Float64(size)
        for i in range(size):
            data[i] = Complex64(data[i].re * scale, data[i].im * scale)


def fft(values: Span[Complex64, ...]) raises -> List[Complex64]:
    var result = List[Complex64](capacity=len(values))
    for i in range(len(values)):
        result.append(values[i])
    fft_in_place(result)
    return result^


def ifft(values: Span[Complex64, ...]) raises -> List[Complex64]:
    var result = List[Complex64](capacity=len(values))
    for i in range(len(values)):
        result.append(values[i])
    fft_in_place(result, inverse=True)
    return result^


def fft_batch(
    values: Span[Complex64, ...], transform_size: Int, *, inverse: Bool = False
) raises -> List[Complex64]:
    """Transform contiguous batches without changing the single-FFT semantics."""
    _validate_fft_size(transform_size)
    if len(values) % transform_size != 0:
        raise Error("batch length must be divisible by transform size")
    var result = List[Complex64](capacity=len(values))
    for batch in range(len(values) // transform_size):
        var one = List[Complex64](capacity=transform_size)
        for i in range(transform_size):
            var index = batch * transform_size + i
            one.append(Complex64(values[index].re, values[index].im))
        fft_in_place(one, inverse=inverse)
        for i in range(transform_size):
            result.append(one[i])
    return result^


def dft_reference(
    values: Span[Complex64, ...], *, inverse: Bool = False,
    unitary: Bool = False,
) raises -> List[Complex64]:
    """Readable O(N²) DFT for arbitrary positive lengths.

    The default matches ``fft``/``ifft`` normalization: the forward transform
    is unscaled and the inverse has one ``1/N`` factor.  ``unitary=True`` uses
    ``1/sqrt(N)`` in both directions, as required by NR transform precoding.
    """
    if len(values) < 1:
        raise Error("DFT length must be positive")
    var result = List[Complex64](capacity=len(values))
    var scale = 1.0
    if unitary:
        scale = 1.0 / sqrt(Float64(len(values)))
    elif inverse:
        scale = 1.0 / Float64(len(values))
    var direction = 1.0 if inverse else -1.0
    for k in range(len(values)):
        var acc = Complex64(0.0, 0.0)
        for n in range(len(values)):
            var angle = direction * _TWO_PI * Float64(k * n) / Float64(len(values))
            var sample = Complex64(values[n].re, values[n].im)
            acc = acc + sample * Complex64(cos(angle), sin(angle))
        result.append(Complex64(acc.re * scale, acc.im * scale))
    return result^


def _validate_radix4_size(size: Int) raises:
    if size < 1:
        raise Error("radix-4 FFT length must be positive")
    var remaining = size
    while remaining > 1:
        if remaining % 4 != 0:
            raise Error("radix-4 FFT length must be a power of four")
        remaining //= 4


def _fft_radix4_unscaled(
    values: Span[Complex64, ...], inverse: Bool
) raises -> List[Complex64]:
    var size = len(values)
    if size == 1:
        var base = List[Complex64](capacity=1)
        base.append(Complex64(values[0].re, values[0].im))
        return base^
    var quarter = size // 4
    var decimated0 = List[Complex64](capacity=quarter)
    var decimated1 = List[Complex64](capacity=quarter)
    var decimated2 = List[Complex64](capacity=quarter)
    var decimated3 = List[Complex64](capacity=quarter)
    for i in range(quarter):
        decimated0.append(Complex64(values[4 * i].re, values[4 * i].im))
        decimated1.append(Complex64(values[4 * i + 1].re, values[4 * i + 1].im))
        decimated2.append(Complex64(values[4 * i + 2].re, values[4 * i + 2].im))
        decimated3.append(Complex64(values[4 * i + 3].re, values[4 * i + 3].im))
    var transform0 = _fft_radix4_unscaled(Span(decimated0), inverse)
    var transform1 = _fft_radix4_unscaled(Span(decimated1), inverse)
    var transform2 = _fft_radix4_unscaled(Span(decimated2), inverse)
    var transform3 = _fft_radix4_unscaled(Span(decimated3), inverse)
    var result = List[Complex64](length=size, fill=Complex64(0.0, 0.0))
    var direction = _TWO_PI if inverse else -_TWO_PI
    var imaginary_sign = 1.0 if inverse else -1.0
    for k in range(quarter):
        var angle = direction * Float64(k) / Float64(size)
        var twiddle1 = Complex64(cos(angle), sin(angle))
        var twiddle2 = Complex64(cos(2.0 * angle), sin(2.0 * angle))
        var twiddle3 = Complex64(cos(3.0 * angle), sin(3.0 * angle))
        var a = transform0[k]
        var b = transform1[k] * twiddle1
        var c = transform2[k] * twiddle2
        var d = transform3[k] * twiddle3
        var j_b = Complex64(-imaginary_sign * b.im, imaginary_sign * b.re)
        var j_d = Complex64(-imaginary_sign * d.im, imaginary_sign * d.re)
        result[k] = a + b + c + d
        result[k + quarter] = a + j_b - c - j_d
        result[k + 2 * quarter] = a - b + c - d
        result[k + 3 * quarter] = a - j_b - c + j_d
    return result^


def fft_radix4(
    values: Span[Complex64, ...], *, inverse: Bool = False
) raises -> List[Complex64]:
    """Out-of-place radix-4 reference for power-of-four lengths."""
    _validate_radix4_size(len(values))
    var result = _fft_radix4_unscaled(values, inverse)
    if inverse:
        var scale = 1.0 / Float64(len(result))
        for i in range(len(result)):
            result[i] = Complex64(result[i].re * scale, result[i].im * scale)
    return result^


def ifft_radix4(values: Span[Complex64, ...]) raises -> List[Complex64]:
    return fft_radix4(values, inverse=True)
