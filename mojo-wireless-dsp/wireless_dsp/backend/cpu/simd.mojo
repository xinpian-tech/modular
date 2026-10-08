"""Native-width SIMD CPU kernels validated against scalar golden references."""

from std.collections import Span
from std.sys.info import simd_width_of
from wireless_dsp.core import Complex32


def simd_sum_f32(values: Span[Float32, ...]) -> Float32:
    comptime width = simd_width_of[DType.float32]()
    var vectors = SIMD[DType.float32, width](0.0)
    var index = 0
    while index + Int(width) <= len(values):
        vectors += values.unsafe_ptr().unsafe_load[width=width](index)
        index += Int(width)
    var total = vectors.reduce_add()
    while index < len(values):
        total += values[index]
        index += 1
    return total


def simd_dot_f32(
    lhs: Span[Float32, ...], rhs: Span[Float32, ...]
) raises -> Float32:
    if len(lhs) != len(rhs):
        raise Error("SIMD dot operands must have equal length")
    comptime width = simd_width_of[DType.float32]()
    var vectors = SIMD[DType.float32, width](0.0)
    var index = 0
    while index + Int(width) <= len(lhs):
        var a = lhs.unsafe_ptr().unsafe_load[width=width](index)
        var b = rhs.unsafe_ptr().unsafe_load[width=width](index)
        vectors += a * b
        index += Int(width)
    var total = vectors.reduce_add()
    while index < len(lhs):
        total += lhs[index] * rhs[index]
        index += 1
    return total


def simd_energy_f32(values: Span[Float32, ...]) -> Float32:
    comptime width = simd_width_of[DType.float32]()
    var vectors = SIMD[DType.float32, width](0.0)
    var index = 0
    while index + Int(width) <= len(values):
        var loaded = values.unsafe_ptr().unsafe_load[width=width](index)
        vectors += loaded * loaded
        index += Int(width)
    var total = vectors.reduce_add()
    while index < len(values):
        total += values[index] * values[index]
        index += 1
    return total


def simd_complex_dot_split_f32(
    lhs_re: Span[Float32, ...],
    lhs_im: Span[Float32, ...],
    rhs_re: Span[Float32, ...],
    rhs_im: Span[Float32, ...],
) raises -> Complex32:
    """Hermitian split-IQ dot product ``sum(conj(lhs) * rhs)``."""
    var length = len(lhs_re)
    if len(lhs_im) != length or len(rhs_re) != length or len(rhs_im) != length:
        raise Error("split-IQ vectors must have equal length")
    comptime width = simd_width_of[DType.float32]()
    var real_vectors = SIMD[DType.float32, width](0.0)
    var imag_vectors = SIMD[DType.float32, width](0.0)
    var index = 0
    while index + Int(width) <= length:
        var ar = lhs_re.unsafe_ptr().unsafe_load[width=width](index)
        var ai = lhs_im.unsafe_ptr().unsafe_load[width=width](index)
        var br = rhs_re.unsafe_ptr().unsafe_load[width=width](index)
        var bi = rhs_im.unsafe_ptr().unsafe_load[width=width](index)
        real_vectors += ar * br + ai * bi
        imag_vectors += ar * bi - ai * br
        index += Int(width)
    var real = real_vectors.reduce_add()
    var imag = imag_vectors.reduce_add()
    while index < length:
        real += lhs_re[index] * rhs_re[index] + lhs_im[index] * rhs_im[index]
        imag += lhs_re[index] * rhs_im[index] - lhs_im[index] * rhs_re[index]
        index += 1
    return Complex32(real, imag)
