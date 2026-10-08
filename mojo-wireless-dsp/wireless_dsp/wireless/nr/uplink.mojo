"""NR uplink primitives for PUSCH transform precoding and PRACH."""

from std.collections import Span
from std.math import cos, isfinite, sin
from wireless_dsp.core import Complex64
from wireless_dsp.dsp import dft_reference, normalized_correlation_at
from .sequences import nr_gold_bits, nr_qpsk_sequence

comptime _PI = 3.1415926535897932384626433832795


def nr_pusch_scramble(
    bits: Span[UInt8, ...], rnti: Int, codeword: Int, n_id: Int
) raises -> List[UInt8]:
    """TS 38.211 6.3.1.1 ordinary PUSCH data-bit scrambling.

    UCI placeholder tags are intentionally outside this bit-only primitive;
    callers resolve them before passing a binary vector.
    """
    if rnti < 0 or rnti > 0xFFFF or codeword < 0 or codeword > 1 or n_id < 0 or n_id > 1023:
        raise Error("invalid PUSCH scrambling configuration")
    var c_init = UInt32((rnti << 15) + (codeword << 14) + n_id)
    var sequence = nr_gold_bits(c_init, len(bits))
    var result = List[UInt8](capacity=len(bits))
    for i in range(len(bits)):
        if bits[i] > 1:
            raise Error("PUSCH input must contain only zero and one")
        result.append(bits[i] ^ sequence[i])
    return result^


def nr_pusch_descramble_llrs(
    llrs: Span[Float64, ...], rnti: Int, codeword: Int, n_id: Int
) raises -> List[Float64]:
    if rnti < 0 or rnti > 0xFFFF or codeword < 0 or codeword > 1 or n_id < 0 or n_id > 1023:
        raise Error("invalid PUSCH scrambling configuration")
    var c_init = UInt32((rnti << 15) + (codeword << 14) + n_id)
    var sequence = nr_gold_bits(c_init, len(llrs))
    var result = List[Float64](capacity=len(llrs))
    for i in range(len(llrs)):
        if not isfinite(llrs[i]):
            raise Error("PUSCH descrambling LLRs must be finite")
        result.append(llrs[i] if sequence[i] == 0 else -llrs[i])
    return result^


def _validate_finite_transform_samples(
    symbols: Span[Complex64, ...]
) raises:
    for index in range(len(symbols)):
        if not isfinite(symbols[index].re) or not isfinite(symbols[index].im):
            raise Error("PUSCH transform samples must be finite")


def _validate_finite_transform_result(
    symbols: Span[Complex64, ...]
) raises:
    for index in range(len(symbols)):
        if not isfinite(symbols[index].re) or not isfinite(symbols[index].im):
            raise Error("PUSCH transform result must remain finite")


def nr_pusch_transform_precoding(
    symbols: Span[Complex64, ...]
) raises -> List[Complex64]:
    """Unitary M-point DFT spreading for one PUSCH OFDM symbol."""
    if len(symbols) % 12 != 0:
        raise Error("PUSCH transform-precoding length must span whole resource blocks")
    _validate_finite_transform_samples(symbols)
    var result = dft_reference(symbols, unitary=True)
    _validate_finite_transform_result(Span(result))
    return result^


def nr_pusch_transform_deprecoding(
    symbols: Span[Complex64, ...]
) raises -> List[Complex64]:
    if len(symbols) % 12 != 0:
        raise Error("PUSCH transform-deprecoding length must span whole resource blocks")
    _validate_finite_transform_samples(symbols)
    var result = dft_reference(symbols, inverse=True, unitary=True)
    _validate_finite_transform_result(Span(result))
    return result^


def nr_pusch_dmrs_c_init(
    slot: Int, symbol: Int, n_id: Int, n_scid: Int,
) raises -> UInt32:
    """TS 38.211 6.4.1.1.1.1 transform-precoding-disabled c_init."""
    if slot < 0 or symbol < 0 or symbol > 13 or n_id < 0 or n_id > 65535 or n_scid < 0 or n_scid > 1:
        raise Error("invalid PUSCH DM-RS initialization fields")
    # Reduce each factor modulo 2^31 before multiplying.  This preserves the
    # exact Gold-sequence initialization for every non-negative Int slot and
    # avoids overflowing the signed ``14 * slot`` intermediate.
    var modulus = UInt64(1) << 31
    var time_term = (
        UInt64(14) * (UInt64(slot) % modulus) + UInt64(symbol + 1)
    ) % modulus
    var value = (
        (((UInt64(1) << 17) * time_term) % modulus)
        * UInt64(2 * n_id + 1)
        + UInt64(2 * n_id + n_scid)
    ) % modulus
    return UInt32(value)


def nr_pusch_dmrs(
    slot: Int, symbol: Int, n_id: Int, n_scid: Int, length: Int,
) raises -> List[Complex64]:
    return nr_qpsk_sequence(
        nr_pusch_dmrs_c_init(slot, symbol, n_id, n_scid), length
    )


def _greatest_common_divisor(lhs: Int, rhs: Int) -> Int:
    var a = abs(lhs)
    var b = abs(rhs)
    while b != 0:
        var remainder = a % b
        a = b
        b = remainder
    return a


def nr_prach_root_sequence(
    root: Int, sequence_length: Int
) raises -> List[Complex64]:
    """Generate a long (839) or short (139) root Zadoff-Chu sequence."""
    if sequence_length != 839 and sequence_length != 139:
        raise Error("NR PRACH sequence length must be 839 or 139")
    if root < 1 or root >= sequence_length or _greatest_common_divisor(root, sequence_length) != 1:
        raise Error("PRACH root must be coprime and inside the sequence length")
    var result = List[Complex64](capacity=sequence_length)
    for n in range(sequence_length):
        var angle = -_PI * Float64(root * n * (n + 1)) / Float64(sequence_length)
        result.append(Complex64(cos(angle), sin(angle)))
    return result^


def nr_prach_sequence(
    root: Int,
    sequence_length: Int,
    cyclic_shift: Int,
) raises -> List[Complex64]:
    """Apply the unrestricted-set PRACH cyclic shift to a root sequence."""
    if cyclic_shift < 0 or cyclic_shift >= sequence_length:
        raise Error("PRACH cyclic shift is outside the sequence")
    var root_sequence = nr_prach_root_sequence(root, sequence_length)
    var result = List[Complex64](capacity=sequence_length)
    for n in range(sequence_length):
        result.append(root_sequence[(n + cyclic_shift) % sequence_length])
    return result^


def nr_prach_unrestricted_cyclic_shift(
    preamble_index: Int, n_cs: Int, sequence_length: Int
) raises -> Int:
    """C_v=v*N_CS for unrestricted sets on one logical root."""
    if sequence_length != 839 and sequence_length != 139:
        raise Error("NR PRACH sequence length must be 839 or 139")
    if preamble_index < 0 or n_cs < 0 or n_cs >= sequence_length:
        raise Error("invalid unrestricted PRACH cyclic-shift configuration")
    if n_cs == 0:
        if preamble_index != 0:
            raise Error("N_CS=0 provides one preamble per root")
        return 0
    if preamble_index >= sequence_length // n_cs:
        raise Error("preamble index requires the next logical PRACH root")
    return preamble_index * n_cs


struct NRPRACHDetection(ImplicitlyCopyable):
    var preamble_index: Int
    var cyclic_shift: Int
    var metric: Float64

    def __init__(out self, preamble_index: Int, cyclic_shift: Int, metric: Float64):
        self.preamble_index = preamble_index
        self.cyclic_shift = cyclic_shift
        self.metric = metric


def nr_detect_prach_unrestricted(
    received: Span[Complex64, ...],
    root: Int,
    n_cs: Int,
    preamble_count: Int,
) raises -> NRPRACHDetection:
    """Exhaustive normalized detector for preambles carried by one root."""
    var sequence_length = len(received)
    if preamble_count < 1:
        raise Error("PRACH detector requires at least one candidate")
    var maximum_component = 0.0
    for index in range(sequence_length):
        if not isfinite(received[index].re) or not isfinite(received[index].im):
            raise Error("PRACH detector samples must be finite")
        maximum_component = max(
            maximum_component,
            max(abs(received[index].re), abs(received[index].im)),
        )
    # Normalized correlation is scale-invariant.  Scaling first prevents the
    # energy and cross-product accumulators from overflowing on large but
    # otherwise valid finite observations (and rescues subnormal inputs).
    var scaled_received = List[Complex64](capacity=sequence_length)
    var scale = maximum_component if maximum_component > 0.0 else 1.0
    for index in range(sequence_length):
        scaled_received.append(Complex64(
            received[index].re / scale, received[index].im / scale
        ))
    var best_index = 0
    var best_shift = 0
    var best_metric = -1.0
    for candidate in range(preamble_count):
        var shift = nr_prach_unrestricted_cyclic_shift(
            candidate, n_cs, sequence_length
        )
        var reference = nr_prach_sequence(root, sequence_length, shift)
        var correlation = normalized_correlation_at(
            Span(scaled_received), Span(reference), 0
        )
        var metric = correlation.magnitude_squared()
        if (
            not isfinite(correlation.re)
            or not isfinite(correlation.im)
            or not isfinite(metric)
        ):
            raise Error("PRACH detector correlation must remain finite")
        if metric > best_metric:
            best_index = candidate
            best_shift = shift
            best_metric = metric
    return NRPRACHDetection(best_index, best_shift, best_metric)
