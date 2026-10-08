"""3GPP TS 38.212 small-block channel-code reference.

This module contains the protocol-independent (32, K) binary linear code used
by NR control information for 3 <= K <= 11, its circular rate matcher, and a
maximum-likelihood soft decoder.  The scalar exhaustive decoder is deliberate:
it is a readable golden oracle for future fast Walsh or SIMD decoders.
"""

from std.collections import Span
from std.math import isfinite


struct SmallBlockDecodeResult(Movable):
    """Decoded information bits and the ML decision margin."""

    var bits: List[UInt8]
    var metric: Float64
    var margin: Float64

    def __init__(
        out self, var bits: List[UInt8], metric: Float64, margin: Float64
    ):
        self.bits = bits^
        self.metric = metric
        self.margin = margin


def _small_block_column_masks() -> List[UInt32]:
    """Columns M[:, k] of TS 38.212 Table 5.3.3.3-1, MSB first."""
    return [
        UInt32(0xFFFFFFFF),
        UInt32(0xCC95A5D2),
        UInt32(0x5A7089BE),
        UInt32(0x39CC64B6),
        UInt32(0x07C3E38E),
        UInt32(0x003FF07E),
        UInt32(0x2671B8CE),
        UInt32(0x0DAF22D6),
        UInt32(0x371843BE),
        UInt32(0x62ED85B2),
        UInt32(0xFFFF0F42),
    ]


def nr_small_block_basis_bit(index: Int, information_index: Int) raises -> UInt8:
    """Return M[index, information_index] from the normative 32x11 table."""
    if index < 0 or index >= 32 or information_index < 0 or information_index >= 11:
        raise Error("small-block basis index is out of range")
    var masks = _small_block_column_masks()
    return UInt8((masks[information_index] >> UInt32(31 - index)) & UInt32(1))


def nr_small_block_encode(bits: Span[UInt8, ...]) raises -> List[UInt8]:
    """Encode 3--11 information bits into the normative 32-bit codeword."""
    if len(bits) < 3 or len(bits) > 11:
        raise Error("small-block information length must be in [3,11]")
    for index in range(len(bits)):
        if bits[index] > 1:
            raise Error("small-block input must contain only zero and one")
    var result = List[UInt8](length=32, fill=UInt8(0))
    for index in range(32):
        var value = UInt8(0)
        for information_index in range(len(bits)):
            value ^= bits[information_index] * nr_small_block_basis_bit(
                index, information_index
            )
        result[index] = value
    return result^


def nr_small_block_rate_match(
    codeword: Span[UInt8, ...], output_length: Int
) raises -> List[UInt8]:
    """Circular repetition/puncturing from TS 38.212 clause 5.4.3."""
    if len(codeword) != 32 or output_length < 1:
        raise Error("small-block rate matching requires N=32 and E>0")
    var result = List[UInt8](capacity=output_length)
    for index in range(output_length):
        if codeword[index % 32] > 1:
            raise Error("small-block codeword must contain only zero and one")
        result.append(codeword[index % 32])
    return result^


def nr_small_block_rate_recover_llrs(
    llrs: Span[Float64, ...]
) raises -> List[Float64]:
    """Combine circular repetitions into 32 mother-code LLRs."""
    if len(llrs) < 1:
        raise Error("small-block rate recovery requires at least one LLR")
    var result = List[Float64](length=32, fill=0.0)
    for index in range(len(llrs)):
        if not isfinite(llrs[index]):
            raise Error("small-block rate-recovery LLRs must be finite")
        result[index % 32] += llrs[index]
        if not isfinite(result[index % 32]):
            raise Error("small-block combined LLR must remain finite")
    return result^


def _candidate_bits(candidate: Int, information_length: Int) -> List[UInt8]:
    var bits = List[UInt8](capacity=information_length)
    for index in range(information_length):
        bits.append(UInt8(
            (candidate >> (information_length - index - 1)) & 1
        ))
    return bits^


def nr_small_block_decode_ml(
    llrs: Span[Float64, ...], information_length: Int
) raises -> SmallBlockDecodeResult:
    """Soft maximum-likelihood decode an arbitrary rate-matched observation.

    LLRs use the common convention ``log(P(bit=0)/P(bit=1))``.  The returned
    margin is the best correlation metric minus the runner-up metric.
    """
    if information_length < 3 or information_length > 11 or len(llrs) < 1:
        raise Error("invalid small-block decoder dimensions")
    for index in range(len(llrs)):
        if not isfinite(llrs[index]):
            raise Error("small-block decoder LLRs must be finite")
    var metric_scale = 0.0
    for index in range(len(llrs)):
        metric_scale = max(metric_scale, abs(llrs[index]))
    if metric_scale == 0.0:
        metric_scale = 1.0
    var best_metric_normalized = 0.0
    var second_metric_normalized = 0.0
    var initialized = False
    var best_bits = List[UInt8](length=information_length, fill=UInt8(0))
    for candidate in range(1 << information_length):
        var bits = _candidate_bits(candidate, information_length)
        var codeword = nr_small_block_encode(Span(bits))
        var metric = 0.0
        for index in range(len(llrs)):
            metric += (
                1.0 - 2.0 * Float64(codeword[index % 32])
            ) * (llrs[index] / metric_scale)
        if not initialized:
            best_metric_normalized = metric
            best_bits = bits^
            initialized = True
        elif candidate == 1:
            if metric > best_metric_normalized:
                second_metric_normalized = best_metric_normalized
                best_metric_normalized = metric
                best_bits = bits^
            else:
                second_metric_normalized = metric
        elif metric > best_metric_normalized:
            second_metric_normalized = best_metric_normalized
            best_metric_normalized = metric
            best_bits = bits^
        elif metric > second_metric_normalized:
            second_metric_normalized = metric
    var best_metric = best_metric_normalized * metric_scale
    var margin = (
        best_metric_normalized - second_metric_normalized
    ) * metric_scale
    if not isfinite(best_metric) or not isfinite(margin):
        raise Error("small-block ML metric is not representable")
    return SmallBlockDecodeResult(
        best_bits^, best_metric, margin
    )
