"""Arikan polar transform and frozen-position encoder reference."""

from std.collections import Span
from std.math import isfinite


def polar_transform(mut values: List[UInt8]) raises:
    var size = len(values)
    if size < 1 or (size & (size - 1)) != 0:
        raise Error("polar transform size must be a positive power of two")
    for index in range(size):
        if values[index] > 1:
            raise Error("polar transform input must contain zero or one")
    var stage = 1
    while stage < size:
        var base = 0
        while base < size:
            for offset in range(stage):
                values[base + offset] ^= values[base + offset + stage]
            base += 2 * stage
        stage *= 2


def polar_encode(
    information: Span[UInt8, ...], frozen: Span[UInt8, ...]
) raises -> List[UInt8]:
    """Place information in entries where frozen=0, then apply F^tensor-n."""
    var expected_information = 0
    for i in range(len(frozen)):
        if frozen[i] == 0:
            expected_information += 1
        elif frozen[i] != 1:
            raise Error("frozen mask entries must be zero or one")
    if len(information) != expected_information:
        raise Error("information count does not match frozen mask")
    var values = List[UInt8](length=len(frozen), fill=UInt8(0))
    var information_index = 0
    for i in range(len(frozen)):
        if frozen[i] == 0:
            if information[information_index] > 1:
                raise Error("information bits must be zero or one")
            values[i] = information[information_index]
            information_index += 1
    polar_transform(values)
    return values^


def _f_llr(a: Float64, b: Float64) -> Float64:
    var sign = -1.0 if (a < 0.0) != (b < 0.0) else 1.0
    return sign * min(abs(a), abs(b))


def _sc_node(
    llrs: Span[Float64, ...],
    frozen: Span[UInt8, ...],
    offset: Int,
    mut decisions: List[UInt8],
) raises -> List[UInt8]:
    var size = len(llrs)
    if size == 1:
        var bit = UInt8(0) if frozen[offset] == 1 or llrs[0] >= 0.0 else UInt8(1)
        decisions[offset] = bit
        var leaf = List[UInt8](capacity=1)
        leaf.append(bit)
        return leaf^
    var half = size // 2
    var left_llrs = List[Float64](capacity=half)
    for i in range(half):
        left_llrs.append(_f_llr(llrs[i], llrs[i + half]))
    var left = _sc_node(Span(left_llrs), frozen, offset, decisions)
    var right_llrs = List[Float64](capacity=half)
    for i in range(half):
        right_llrs.append(llrs[i + half] + (1.0 - 2.0 * Float64(left[i])) * llrs[i])
    var right = _sc_node(Span(right_llrs), frozen, offset + half, decisions)
    var partial = List[UInt8](capacity=size)
    for i in range(half):
        partial.append(left[i] ^ right[i])
    for i in range(half):
        partial.append(right[i])
    return partial^


def polar_decode_sc(
    llrs: Span[Float64, ...], frozen: Span[UInt8, ...]
) raises -> List[UInt8]:
    """Successive-cancellation decode using min-sum f and exact g updates."""
    if len(llrs) != len(frozen) or len(llrs) < 1 or (len(llrs) & (len(llrs) - 1)) != 0:
        raise Error("polar decoder inputs must have equal power-of-two length")
    var maximum_magnitude = 0.0
    for index in range(len(llrs)):
        if not isfinite(llrs[index]):
            raise Error("polar decoder LLRs must be finite")
        if frozen[index] > 1:
            raise Error("frozen mask entries must be zero or one")
        maximum_magnitude = max(maximum_magnitude, abs(llrs[index]))
    var normalized = List[Float64](capacity=len(llrs))
    if maximum_magnitude == 0.0:
        for _ in range(len(llrs)):
            normalized.append(0.0)
    else:
        for index in range(len(llrs)):
            normalized.append(llrs[index] / maximum_magnitude)
    var decisions = List[UInt8](length=len(llrs), fill=UInt8(0))
    _ = _sc_node(Span(normalized), frozen, 0, decisions)
    var result = List[UInt8]()
    for i in range(len(frozen)):
        if frozen[i] == 0:
            result.append(decisions[i])
        elif frozen[i] != 1:
            raise Error("frozen mask entries must be zero or one")
    return result^
