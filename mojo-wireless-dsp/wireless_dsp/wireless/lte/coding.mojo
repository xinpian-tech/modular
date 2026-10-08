"""LTE channel-coding primitives from 3GPP TS 36.212 V18.1.0.

The module implements the frozen Release-18 algorithms in clauses 5.1.1 through
5.1.4.1: LTE CRCs, code-block segmentation/concatenation, the K=7 rate-1/3
tail-biting convolutional code, the complete 188-row QPP interleaver table,
the 8-state turbo encoder with trellis termination, and turbo-code
circular-buffer rate matching/recovery.

Positive soft values consistently mean that bit zero is more likely.  Dummy
``<NULL>`` entries are represented by a separate binary mask, never by a
magic bit or floating-point value.  The segmentation API consumes the generic
clause-5.1.2 ``B`` sequence: callers select/attach the transport-channel outer
CRC first, and allocate each code block's final rate-matched ``E`` separately.
"""

from std.collections import Span
from std.math import isfinite
from std.utils.numerics import inf
from wireless_dsp.modem.crc import crc_append, crc_bits, crc_check


comptime LTE_QPP_BLOCK_SIZE_COUNT = 188
comptime LTE_TAIL_BITING_CONSTRAINT_LENGTH = 7
comptime LTE_TAIL_BITING_RATE_DENOMINATOR = 3
comptime LTE_TURBO_MAX_CODE_BLOCK_BITS = 6144
comptime LTE_CODE_BLOCK_CRC_BITS = 24


struct LTEQPPParameters(ImplicitlyCopyable):
    """One row of TS 36.212 Table 5.1.3-3."""

    var block_size: Int
    var f1: Int
    var f2: Int

    def __init__(out self, block_size: Int, f1: Int, f2: Int):
        self.block_size = block_size
        self.f1 = f1
        self.f2 = f2


struct LTECodeBlockSegmentationProfile(ImplicitlyCopyable):
    """Exact clause 5.1.2 dimensions for one input sequence.

    ``small_block_bits`` is zero when no second segmentation size exists.
    ``total_segmented_bits`` includes filler positions and per-block CRC24B
    bits.  A filler bit is represented as value zero plus an explicit mask;
    its zero value is the one used by the normative CRC calculation and turbo
    encoder.
    """

    var input_bits: Int
    var code_blocks: Int
    var code_block_crc_bits: Int
    var segmented_bits_with_crc: Int
    var small_block_bits: Int
    var large_block_bits: Int
    var small_blocks: Int
    var large_blocks: Int
    var filler_bits: Int
    var total_segmented_bits: Int

    def __init__(
        out self,
        input_bits: Int,
        code_blocks: Int,
        code_block_crc_bits: Int,
        segmented_bits_with_crc: Int,
        small_block_bits: Int,
        large_block_bits: Int,
        small_blocks: Int,
        large_blocks: Int,
        filler_bits: Int,
        total_segmented_bits: Int,
    ):
        self.input_bits = input_bits
        self.code_blocks = code_blocks
        self.code_block_crc_bits = code_block_crc_bits
        self.segmented_bits_with_crc = segmented_bits_with_crc
        self.small_block_bits = small_block_bits
        self.large_block_bits = large_block_bits
        self.small_blocks = small_blocks
        self.large_blocks = large_blocks
        self.filler_bits = filler_bits
        self.total_segmented_bits = total_segmented_bits

    def validate(self) raises:
        var expected = lte_code_block_segmentation_profile(self.input_bits)
        if (
            self.code_blocks != expected.code_blocks
            or self.code_block_crc_bits != expected.code_block_crc_bits
            or self.segmented_bits_with_crc
            != expected.segmented_bits_with_crc
            or self.small_block_bits != expected.small_block_bits
            or self.large_block_bits != expected.large_block_bits
            or self.small_blocks != expected.small_blocks
            or self.large_blocks != expected.large_blocks
            or self.filler_bits != expected.filler_bits
            or self.total_segmented_bits != expected.total_segmented_bits
        ):
            raise Error("LTE code-block segmentation profile is inconsistent")


struct LTECodeBlockSegments(Movable):
    """Flattened code blocks, filler mask, and their normative dimensions."""

    var bits: List[UInt8]
    var null_mask: List[UInt8]
    var profile: LTECodeBlockSegmentationProfile

    def __init__(
        out self,
        var bits: List[UInt8],
        var null_mask: List[UInt8],
        profile: LTECodeBlockSegmentationProfile,
    ):
        self.bits = bits^
        self.null_mask = null_mask^
        self.profile = profile


struct LTECodeBlockConcatenationResult(Movable):
    """Reassembled input sequence and aggregate code-block CRC status."""

    var bits: List[UInt8]
    var code_block_crc_ok: Bool

    def __init__(
        out self, var bits: List[UInt8], code_block_crc_ok: Bool
    ):
        self.bits = bits^
        self.code_block_crc_ok = code_block_crc_ok


struct LTETurboCodeword(Movable):
    """The three turbo streams and the leading clause-5.1.3.2.1 fillers.

    The stored stream values remain binary so that filler zeros participate in
    the constituent encoders.  ``filler_bits`` carries their normative
    ``<NULL>`` identity into circular-buffer construction and rate matching.
    """

    var systematic: List[UInt8]
    var parity1: List[UInt8]
    var parity2: List[UInt8]
    var filler_bits: Int

    def __init__(
        out self,
        var systematic: List[UInt8],
        var parity1: List[UInt8],
        var parity2: List[UInt8],
        filler_bits: Int,
    ):
        self.systematic = systematic^
        self.parity1 = parity1^
        self.parity2 = parity2^
        self.filler_bits = filler_bits


struct LTESubblockBits(Movable):
    """One turbo sub-block output and its explicit ``<NULL>`` mask."""

    var bits: List[UInt8]
    var null_mask: List[UInt8]
    var input_bits: Int
    var rows: Int

    def __init__(
        out self,
        var bits: List[UInt8],
        var null_mask: List[UInt8],
        input_bits: Int,
        rows: Int,
    ):
        self.bits = bits^
        self.null_mask = null_mask^
        self.input_bits = input_bits
        self.rows = rows


struct LTETurboRateRecovery(Movable):
    """Recovered soft values in the turbo encoder's three stream orders."""

    var systematic: List[Float64]
    var parity1: List[Float64]
    var parity2: List[Float64]

    def __init__(
        out self,
        var systematic: List[Float64],
        var parity1: List[Float64],
        var parity2: List[Float64],
    ):
        self.systematic = systematic^
        self.parity1 = parity1^
        self.parity2 = parity2^


struct LTETurboDecodeResult(Movable):
    """Max-log decoded bits and final a-posteriori LLRs."""

    var bits: List[UInt8]
    var posterior_llrs: List[Float64]
    var iterations: Int

    def __init__(
        out self,
        var bits: List[UInt8],
        var posterior_llrs: List[Float64],
        iterations: Int,
    ):
        self.bits = bits^
        self.posterior_llrs = posterior_llrs^
        self.iterations = iterations


def _validate_binary(bits: Span[UInt8, ...], name: StringSlice) raises:
    for index in range(len(bits)):
        if bits[index] > 1:
            raise Error(String(name) + " must contain only zero and one")


def _checked_product(lhs: Int, rhs: Int, name: StringSlice) raises -> Int:
    if lhs < 0 or rhs < 0 or (rhs != 0 and lhs > Int.MAX // rhs):
        raise Error(String(name) + " dimensions overflow Int")
    return lhs * rhs


def _checked_sum(lhs: Int, rhs: Int, name: StringSlice) raises -> Int:
    if lhs < 0 or rhs < 0 or lhs > Int.MAX - rhs:
        raise Error(String(name) + " dimensions overflow Int")
    return lhs + rhs


# TS 36.212 clause 5.1.1 generator polynomials, with the x^width term
# omitted as required by the generic unreflected MSB-first CRC engine.
def lte_crc24a(bits: Span[UInt8, ...]) raises -> UInt64:
    """Compute the LTE CRC24A remainder (transport-block polynomial)."""
    return crc_bits(bits, width=24, polynomial=UInt64(0x864CFB))


def lte_crc24a_append(bits: Span[UInt8, ...]) raises -> List[UInt8]:
    """Append an MSB-first LTE CRC24A remainder."""
    return crc_append(bits, width=24, polynomial=UInt64(0x864CFB))


def lte_crc24a_check(codeword: Span[UInt8, ...]) raises -> Bool:
    """Return whether a CRC24A codeword has zero syndrome."""
    return crc_check(codeword, width=24, polynomial=UInt64(0x864CFB))


def lte_crc24b(bits: Span[UInt8, ...]) raises -> UInt64:
    """Compute the LTE CRC24B remainder (code-block polynomial)."""
    return crc_bits(bits, width=24, polynomial=UInt64(0x800063))


def lte_crc24b_append(bits: Span[UInt8, ...]) raises -> List[UInt8]:
    """Append an MSB-first LTE CRC24B remainder."""
    return crc_append(bits, width=24, polynomial=UInt64(0x800063))


def lte_crc24b_check(codeword: Span[UInt8, ...]) raises -> Bool:
    """Return whether a CRC24B codeword has zero syndrome."""
    return crc_check(codeword, width=24, polynomial=UInt64(0x800063))


def lte_crc16(bits: Span[UInt8, ...]) raises -> UInt64:
    """Compute the LTE 16-bit CRC remainder."""
    return crc_bits(bits, width=16, polynomial=UInt64(0x1021))


def lte_crc16_append(bits: Span[UInt8, ...]) raises -> List[UInt8]:
    """Append an MSB-first LTE 16-bit CRC remainder."""
    return crc_append(bits, width=16, polynomial=UInt64(0x1021))


def lte_crc16_check(codeword: Span[UInt8, ...]) raises -> Bool:
    """Return whether an LTE CRC16 codeword has zero syndrome."""
    return crc_check(codeword, width=16, polynomial=UInt64(0x1021))


def lte_crc8(bits: Span[UInt8, ...]) raises -> UInt64:
    """Compute the LTE 8-bit CRC remainder."""
    return crc_bits(bits, width=8, polynomial=UInt64(0x9B))


def lte_crc8_append(bits: Span[UInt8, ...]) raises -> List[UInt8]:
    """Append an MSB-first LTE 8-bit CRC remainder."""
    return crc_append(bits, width=8, polynomial=UInt64(0x9B))


def lte_crc8_check(codeword: Span[UInt8, ...]) raises -> Bool:
    """Return whether an LTE CRC8 codeword has zero syndrome."""
    return crc_check(codeword, width=8, polynomial=UInt64(0x9B))


def _parity(value: Int) -> UInt8:
    var remaining = value
    var result = UInt8(0)
    while remaining != 0:
        result ^= UInt8(remaining & 1)
        remaining >>= 1
    return result


def _lte_tail_biting_initial_state(bits: Span[UInt8, ...]) raises -> Int:
    if len(bits) < 6:
        raise Error("LTE tail-biting input must contain at least six bits")
    _validate_binary(bits, "LTE tail-biting input")
    var state = 0
    for index in range(len(bits) - 6, len(bits)):
        state = (state << 1) | Int(bits[index])
    return state


def lte_tail_biting_convolutional_encode(
    bits: Span[UInt8, ...]
) raises -> List[UInt8]:
    """Encode serialized ``[d0[k], d1[k], d2[k]]`` triples.

    The initial six-bit state is the final six information bits, so the
    encoder starts and ends in the same state without appending a zero tail.
    The three octal generators are 133, 171, and 165.
    """
    var state = _lte_tail_biting_initial_state(bits)
    var output_size = _checked_product(
        len(bits), LTE_TAIL_BITING_RATE_DENOMINATOR, "LTE tail-biting output"
    )
    var result = List[UInt8](capacity=output_size)
    var generators: List[Int] = [0o133, 0o171, 0o165]
    for index in range(len(bits)):
        var register = (state << 1) | Int(bits[index])
        state = register & 0x3F
        for generator in generators:
            result.append(_parity(register & generator))
    return result^


def _lte_tail_biting_viterbi_soft(
    llrs: Span[Float64, ...]
) raises -> List[UInt8]:
    if len(llrs) % 3 != 0:
        raise Error("LTE tail-biting LLRs must contain complete triples")
    var steps = len(llrs) // 3
    if steps < 6:
        raise Error("LTE tail-biting trellis must contain at least six steps")
    _ = _checked_product(steps, 64, "LTE Viterbi traceback")
    var scale = 1.0
    for index in range(len(llrs)):
        if not isfinite(llrs[index]):
            raise Error("LTE tail-biting LLRs must be finite")
        var magnitude = abs(llrs[index])
        if magnitude > scale:
            scale = magnitude

    var generators: List[Int] = [0o133, 0o171, 0o165]
    var infinity = inf[DType.float64]()
    var best_metric = infinity
    var best_bits = List[UInt8]()

    # An exact tail-biting Viterbi search: evaluate every possible initial
    # state and retain only paths that return to that same state.
    for initial_state in range(64):
        var metrics = List[Float64](length=64, fill=infinity)
        metrics[initial_state] = 0.0
        var predecessors = List[Int](length=steps * 64, fill=-1)
        var decisions = List[UInt8](length=steps * 64, fill=UInt8(0))
        for step in range(steps):
            var next_metrics = List[Float64](length=64, fill=infinity)
            for previous in range(64):
                if not isfinite(metrics[previous]):
                    continue
                for input_bit in range(2):
                    var register = (previous << 1) | input_bit
                    var next_state = register & 0x3F
                    var cost = 0.0
                    for stream in range(3):
                        var expected = _parity(register & generators[stream])
                        var llr = llrs[step * 3 + stream] / scale
                        cost += (
                            max(0.0, -llr)
                            if expected == 0
                            else max(0.0, llr)
                        )
                    var candidate = metrics[previous] + cost
                    if candidate < next_metrics[next_state]:
                        next_metrics[next_state] = candidate
                        predecessors[step * 64 + next_state] = previous
                        decisions[step * 64 + next_state] = UInt8(input_bit)
            metrics = next_metrics^
        if metrics[initial_state] < best_metric:
            var decoded = List[UInt8](length=steps, fill=UInt8(0))
            var state = initial_state
            for reverse_step in range(steps):
                var step = steps - reverse_step - 1
                decoded[step] = decisions[step * 64 + state]
                state = predecessors[step * 64 + state]
                if state < 0:
                    raise Error("LTE tail-biting Viterbi traceback is unreachable")
            if state != initial_state:
                raise Error("LTE tail-biting Viterbi path does not close")
            best_metric = metrics[initial_state]
            best_bits = decoded^
    if not isfinite(best_metric):
        raise Error("LTE tail-biting Viterbi trellis has no closed path")
    return best_bits^


def lte_tail_biting_convolutional_decode_soft(
    llrs: Span[Float64, ...]
) raises -> List[UInt8]:
    """Exact soft Viterbi decode; positive LLR denotes bit zero."""
    return _lte_tail_biting_viterbi_soft(llrs)


def lte_tail_biting_convolutional_decode_hard(
    encoded: Span[UInt8, ...]
) raises -> List[UInt8]:
    """Hard-decision Viterbi decode with the LTE closed-state constraint."""
    _validate_binary(encoded, "LTE tail-biting encoded input")
    var llrs = List[Float64](capacity=len(encoded))
    for index in range(len(encoded)):
        llrs.append(1.0 if encoded[index] == 0 else -1.0)
    return _lte_tail_biting_viterbi_soft(Span(llrs))


def lte_qpp_block_size(table_index: Int) raises -> Int:
    """Return Table 5.1.3-3 block size for a zero-based row index."""
    if table_index < 0 or table_index >= LTE_QPP_BLOCK_SIZE_COUNT:
        raise Error("LTE QPP table index must be in [0,187]")
    if table_index < 60:
        return 40 + 8 * table_index
    if table_index < 92:
        return 528 + 16 * (table_index - 60)
    if table_index < 124:
        return 1056 + 32 * (table_index - 92)
    return 2112 + 64 * (table_index - 124)


def _lte_qpp_table_index(block_size: Int) raises -> Int:
    if block_size >= 40 and block_size <= 512 and block_size % 8 == 0:
        return (block_size - 40) // 8
    if block_size >= 528 and block_size <= 1024 and block_size % 16 == 0:
        return 60 + (block_size - 528) // 16
    if block_size >= 1056 and block_size <= 2048 and block_size % 32 == 0:
        return 92 + (block_size - 1056) // 32
    if block_size >= 2112 and block_size <= 6144 and block_size % 64 == 0:
        return 124 + (block_size - 2112) // 64
    raise Error("LTE turbo block size is absent from Table 5.1.3-3")


def lte_qpp_parameters(block_size: Int) raises -> LTEQPPParameters:
    """Look up all 188 normative QPP rows without interpolation."""
    var index = _lte_qpp_table_index(block_size)
    var f1_values: List[Int] = [
        3, 7, 19, 7, 7, 11, 5, 11, 7, 41, 103, 15,
        9, 17, 9, 21, 101, 21, 57, 23, 13, 27, 11, 27,
        85, 29, 33, 15, 17, 33, 103, 19, 19, 37, 19, 21,
        21, 115, 193, 21, 133, 81, 45, 23, 243, 151, 155, 25,
        51, 47, 91, 29, 29, 247, 29, 89, 91, 157, 55, 31,
        17, 35, 227, 65, 19, 37, 41, 39, 185, 43, 21, 155,
        79, 139, 23, 217, 25, 17, 127, 25, 239, 17, 137, 215,
        29, 15, 147, 29, 59, 65, 55, 31, 17, 171, 67, 35,
        19, 39, 19, 199, 21, 211, 21, 43, 149, 45, 49, 71,
        13, 17, 25, 183, 55, 127, 27, 29, 29, 57, 45, 31,
        59, 185, 113, 31, 17, 171, 209, 253, 367, 265, 181, 39,
        27, 127, 143, 43, 29, 45, 157, 47, 13, 111, 443, 51,
        51, 451, 257, 57, 313, 271, 179, 331, 363, 375, 127, 31,
        33, 43, 33, 477, 35, 233, 357, 337, 37, 71, 71, 37,
        39, 127, 39, 39, 31, 113, 41, 251, 43, 21, 43, 45,
        45, 161, 89, 323, 47, 23, 47, 263,
    ]
    var f2_values: List[Int] = [
        10, 12, 42, 16, 18, 20, 22, 24, 26, 84, 90, 32,
        34, 108, 38, 120, 84, 44, 46, 48, 50, 52, 36, 56,
        58, 60, 62, 32, 198, 68, 210, 36, 74, 76, 78, 120,
        82, 84, 86, 44, 90, 46, 94, 48, 98, 40, 102, 52,
        106, 72, 110, 168, 114, 58, 118, 180, 122, 62, 84, 64,
        66, 68, 420, 96, 74, 76, 234, 80, 82, 252, 86, 44,
        120, 92, 94, 48, 98, 80, 102, 52, 106, 48, 110, 112,
        114, 58, 118, 60, 122, 124, 84, 64, 66, 204, 140, 72,
        74, 76, 78, 240, 82, 252, 86, 88, 60, 92, 846, 48,
        28, 80, 102, 104, 954, 96, 110, 112, 114, 116, 354, 120,
        610, 124, 420, 64, 66, 136, 420, 216, 444, 456, 468, 80,
        164, 504, 172, 88, 300, 92, 188, 96, 28, 240, 204, 104,
        212, 192, 220, 336, 228, 232, 236, 120, 244, 248, 168, 64,
        130, 264, 134, 408, 138, 280, 142, 480, 146, 444, 120, 152,
        462, 234, 158, 80, 96, 902, 166, 336, 170, 86, 174, 176,
        178, 120, 182, 184, 186, 94, 190, 480,
    ]
    return LTEQPPParameters(block_size, f1_values[index], f2_values[index])


def lte_code_block_segmentation_profile(
    input_bits: Int
) raises -> LTECodeBlockSegmentationProfile:
    """Calculate every TS 36.212 clause 5.1.2 segmentation parameter.

    ``input_bits`` is ``B``: it normally already includes the transport-block
    CRC selected by the transport-channel procedure.  This generic routine
    deliberately does not infer or attach that outer CRC.
    """
    if input_bits <= 0:
        raise Error("LTE code-block segmentation input B must be positive")
    var code_blocks = 1
    var code_block_crc_bits = 0
    if input_bits > LTE_TURBO_MAX_CODE_BLOCK_BITS:
        code_block_crc_bits = LTE_CODE_BLOCK_CRC_BITS
        # ceil(B / (Z-L)) without forming the potentially overflowing B+6119.
        code_blocks = 1 + (input_bits - 1) // (
            LTE_TURBO_MAX_CODE_BLOCK_BITS - LTE_CODE_BLOCK_CRC_BITS
        )
    var crc_total = _checked_product(
        code_blocks, code_block_crc_bits, "LTE segmentation CRC"
    )
    var segmented_bits_with_crc = _checked_sum(
        input_bits, crc_total, "LTE segmentation B-prime"
    )
    var required_block_bits = segmented_bits_with_crc // code_blocks
    if segmented_bits_with_crc % code_blocks != 0:
        required_block_bits += 1

    var large_table_index = -1
    for table_index in range(LTE_QPP_BLOCK_SIZE_COUNT):
        if lte_qpp_block_size(table_index) >= required_block_bits:
            large_table_index = table_index
            break
    if large_table_index < 0:
        raise Error("LTE segmentation requires a turbo block larger than 6144")
    var large_block_bits = lte_qpp_block_size(large_table_index)
    var small_block_bits = 0
    var small_blocks = 0
    var large_blocks = 1
    if code_blocks > 1:
        if large_table_index == 0:
            raise Error("LTE segmented turbo blocks have no smaller QPP size")
        small_block_bits = lte_qpp_block_size(large_table_index - 1)
        var size_delta = large_block_bits - small_block_bits
        var all_large_bits = _checked_product(
            code_blocks, large_block_bits, "LTE all-large segmentation"
        )
        small_blocks = (
            all_large_bits - segmented_bits_with_crc
        ) // size_delta
        large_blocks = code_blocks - small_blocks

    var small_total = _checked_product(
        small_blocks, small_block_bits, "LTE small code blocks"
    )
    var large_total = _checked_product(
        large_blocks, large_block_bits, "LTE large code blocks"
    )
    var total_segmented_bits = _checked_sum(
        small_total, large_total, "LTE flattened code blocks"
    )
    var filler_bits = total_segmented_bits - segmented_bits_with_crc
    return LTECodeBlockSegmentationProfile(
        input_bits,
        code_blocks,
        code_block_crc_bits,
        segmented_bits_with_crc,
        small_block_bits,
        large_block_bits,
        small_blocks,
        large_blocks,
        filler_bits,
        total_segmented_bits,
    )


def lte_code_block_bit_range(
    profile: LTECodeBlockSegmentationProfile, code_block: Int
) raises -> Tuple[Int, Int]:
    """Return the half-open flattened range for one segmented code block."""
    profile.validate()
    if code_block < 0 or code_block >= profile.code_blocks:
        raise Error("LTE code-block index is out of range")
    var start: Int
    if code_block < profile.small_blocks:
        start = _checked_product(
            code_block, profile.small_block_bits, "LTE code-block offset"
        )
        return (start, start + profile.small_block_bits)
    var small_total = _checked_product(
        profile.small_blocks,
        profile.small_block_bits,
        "LTE code-block offset",
    )
    var large_index = code_block - profile.small_blocks
    start = _checked_sum(
        small_total,
        _checked_product(
            large_index, profile.large_block_bits, "LTE code-block offset"
        ),
        "LTE code-block offset",
    )
    return (start, start + profile.large_block_bits)


def lte_code_block_segment(
    input: Span[UInt8, ...]
) raises -> LTECodeBlockSegments:
    """Segment ``B`` bits, insert leading filler, and attach CB CRC24B.

    The returned blocks are flattened in increasing ``r`` order.  Every
    block length is a Table 5.1.3-3 QPP size and can therefore be passed to
    ``lte_turbo_encode`` after slicing its range.  Filler positions have bit
    value zero for CRC/turbo evaluation and ``null_mask=1`` so a later
    rate-matching layer can suppress their systematic observations.
    """
    _validate_binary(input, "LTE code-block segmentation input")
    var profile = lte_code_block_segmentation_profile(len(input))
    var result = List[UInt8](
        length=profile.total_segmented_bits, fill=UInt8(0)
    )
    var null_mask = List[UInt8](
        length=profile.total_segmented_bits, fill=UInt8(0)
    )
    var source = 0
    for block in range(profile.code_blocks):
        var block_range = lte_code_block_bit_range(profile, block)
        var block_bits = block_range[1] - block_range[0]
        var data_bits = block_bits - profile.code_block_crc_bits
        var block_data = List[UInt8](length=data_bits, fill=UInt8(0))
        for position in range(data_bits):
            var destination = block_range[0] + position
            if block == 0 and position < profile.filler_bits:
                null_mask[destination] = UInt8(1)
                continue
            if source >= len(input):
                raise Error("LTE segmentation exhausted its input early")
            block_data[position] = input[source]
            result[destination] = input[source]
            source += 1
        if profile.code_block_crc_bits == LTE_CODE_BLOCK_CRC_BITS:
            var with_crc = lte_crc24b_append(Span(block_data))
            for position in range(data_bits, block_bits):
                result[block_range[0] + position] = with_crc[position]
    if source != len(input):
        raise Error("LTE segmentation did not consume its complete input")
    return LTECodeBlockSegments(result^, null_mask^, profile)


def lte_code_block_concatenate(
    decoded_blocks: Span[UInt8, ...],
    profile: LTECodeBlockSegmentationProfile,
) raises -> LTECodeBlockConcatenationResult:
    """Check CB CRC24B, remove filler/CB CRC, and concatenate the ``B`` bits."""
    profile.validate()
    if len(decoded_blocks) != profile.total_segmented_bits:
        raise Error("decoded LTE code blocks have invalid flattened length")
    _validate_binary(decoded_blocks, "decoded LTE code blocks")
    var result = List[UInt8](capacity=profile.input_bits)
    var all_crc_ok = True
    for block in range(profile.code_blocks):
        var block_range = lte_code_block_bit_range(profile, block)
        var block_bits = block_range[1] - block_range[0]
        var data_bits = block_bits - profile.code_block_crc_bits
        if block == 0:
            for position in range(profile.filler_bits):
                if decoded_blocks[block_range[0] + position] != 0:
                    raise Error("decoded LTE filler bits must have value zero")
        if profile.code_block_crc_bits == LTE_CODE_BLOCK_CRC_BITS:
            var one_block = List[UInt8](capacity=block_bits)
            for position in range(block_bits):
                one_block.append(decoded_blocks[block_range[0] + position])
            if not lte_crc24b_check(Span(one_block)):
                all_crc_ok = False
        var first_payload = profile.filler_bits if block == 0 else 0
        for position in range(first_payload, data_bits):
            if len(result) < profile.input_bits:
                result.append(decoded_blocks[block_range[0] + position])
    if len(result) != profile.input_bits:
        raise Error("LTE concatenation did not reconstruct B input bits")
    return LTECodeBlockConcatenationResult(result^, all_crc_ok)


def lte_qpp_index(index: Int, parameters: LTEQPPParameters) raises -> Int:
    """Evaluate ``(f1*i + f2*i^2) mod K`` with checked public bounds."""
    if index < 0 or index >= parameters.block_size:
        raise Error("LTE QPP index is outside its code block")
    var canonical = lte_qpp_parameters(parameters.block_size)
    if parameters.f1 != canonical.f1 or parameters.f2 != canonical.f2:
        raise Error("LTE QPP parameters do not match the normative table")
    # K <= 6144 and f2 <= 954 make this product safely representable in Int64.
    return _lte_qpp_index_unchecked(index, parameters)


def _lte_qpp_index_unchecked(
    index: Int, parameters: LTEQPPParameters
) -> Int:
    return (
        parameters.f1 * index + parameters.f2 * index * index
    ) % parameters.block_size


def lte_qpp_interleave(bits: Span[UInt8, ...]) raises -> List[UInt8]:
    """Apply the normative QPP output-to-input permutation to one block."""
    var parameters = lte_qpp_parameters(len(bits))
    _validate_binary(bits, "LTE QPP input")
    var result = List[UInt8](length=len(bits), fill=UInt8(0))
    for output_index in range(len(bits)):
        result[output_index] = bits[
            _lte_qpp_index_unchecked(output_index, parameters)
        ]
    return result^


def lte_qpp_deinterleave(bits: Span[UInt8, ...]) raises -> List[UInt8]:
    """Invert the normative QPP permutation for one block."""
    var parameters = lte_qpp_parameters(len(bits))
    _validate_binary(bits, "LTE QPP input")
    var result = List[UInt8](length=len(bits), fill=UInt8(0))
    for output_index in range(len(bits)):
        result[_lte_qpp_index_unchecked(output_index, parameters)] = bits[
            output_index
        ]
    return result^


def _lte_qpp_interleave_soft(
    values: Span[Float64, ...]
) raises -> List[Float64]:
    var parameters = lte_qpp_parameters(len(values))
    var result = List[Float64](length=len(values), fill=0.0)
    for output_index in range(len(values)):
        if not isfinite(values[output_index]):
            raise Error("LTE QPP soft input must be finite")
        result[output_index] = values[
            _lte_qpp_index_unchecked(output_index, parameters)
        ]
    return result^


def _lte_qpp_deinterleave_soft(
    values: Span[Float64, ...]
) raises -> List[Float64]:
    var parameters = lte_qpp_parameters(len(values))
    var result = List[Float64](length=len(values), fill=0.0)
    for output_index in range(len(values)):
        if not isfinite(values[output_index]):
            raise Error("LTE QPP soft input must be finite")
        result[_lte_qpp_index_unchecked(output_index, parameters)] = values[
            output_index
        ]
    return result^


def _lte_rsc_step(state: Int, input_bit: UInt8) -> Tuple[Int, UInt8]:
    # g0(D)=1+D^2+D^3 and g1(D)=1+D+D^3.  State bit zero is D.
    var feedback = Int(input_bit) ^ ((state >> 1) & 1) ^ ((state >> 2) & 1)
    var parity = feedback ^ (state & 1) ^ ((state >> 2) & 1)
    return (((state << 1) & 0x6) | feedback, UInt8(parity))


def _lte_rsc_tail(state: Int) -> Tuple[List[UInt8], List[UInt8]]:
    var systematic = List[UInt8](capacity=3)
    var parity = List[UInt8](capacity=3)
    var current = state
    for _ in range(3):
        # This input makes the recursive feedback bit zero; three shifts flush
        # an arbitrary 8-state constituent encoder to the all-zero state.
        var input_bit = UInt8(((current >> 1) ^ (current >> 2)) & 1)
        var transition = _lte_rsc_step(current, input_bit)
        systematic.append(input_bit)
        parity.append(transition[1])
        current = transition[0]
    return (systematic^, parity^)


def lte_turbo_encode(
    bits: Span[UInt8, ...], *, filler_bits: Int = 0
) raises -> LTETurboCodeword:
    """Encode one standardized QPP block and retain leading filler metadata."""
    _ = lte_qpp_parameters(len(bits))
    _validate_binary(bits, "LTE turbo input")
    if filler_bits < 0 or filler_bits >= len(bits):
        raise Error("LTE turbo filler count must be in [0,K)")
    for index in range(filler_bits):
        if bits[index] != 0:
            raise Error("LTE turbo filler inputs must have value zero")
    var interleaved = lte_qpp_interleave(bits)
    var parity1_data = List[UInt8](capacity=len(bits))
    var parity2_data = List[UInt8](capacity=len(bits))
    var state1 = 0
    var state2 = 0
    for index in range(len(bits)):
        var first = _lte_rsc_step(state1, bits[index])
        state1 = first[0]
        parity1_data.append(first[1])
        var second = _lte_rsc_step(state2, interleaved[index])
        state2 = second[0]
        parity2_data.append(second[1])
    var tail1 = _lte_rsc_tail(state1)
    var tail2 = _lte_rsc_tail(state2)

    var systematic = List[UInt8](capacity=len(bits) + 4)
    var parity1 = List[UInt8](capacity=len(bits) + 4)
    var parity2 = List[UInt8](capacity=len(bits) + 4)
    for index in range(len(bits)):
        systematic.append(bits[index])
        parity1.append(parity1_data[index])
        parity2.append(parity2_data[index])

    systematic.append(tail1[0][0])
    parity1.append(tail1[1][0])
    parity2.append(tail1[0][1])
    systematic.append(tail1[1][1])
    parity1.append(tail1[0][2])
    parity2.append(tail1[1][2])
    systematic.append(tail2[0][0])
    parity1.append(tail2[1][0])
    parity2.append(tail2[0][1])
    systematic.append(tail2[1][1])
    parity1.append(tail2[0][2])
    parity2.append(tail2[1][2])
    return LTETurboCodeword(systematic^, parity1^, parity2^, filler_bits)


def _lte_subblock_column_permutation() -> List[Int]:
    return [
        0, 16, 8, 24, 4, 20, 12, 28,
        2, 18, 10, 26, 6, 22, 14, 30,
        1, 17, 9, 25, 5, 21, 13, 29,
        3, 19, 11, 27, 7, 23, 15, 31,
    ]


def lte_turbo_subblock_interleave(
    bits: Span[UInt8, ...], *, third_stream: Bool = False,
    leading_null_bits: Int = 0,
) raises -> LTESubblockBits:
    """Apply clause 5.1.4.1.1 and preserve leading ``<NULL>`` inputs."""
    if len(bits) < 1:
        raise Error("LTE turbo sub-block input cannot be empty")
    _validate_binary(bits, "LTE turbo sub-block input")
    if leading_null_bits < 0 or leading_null_bits > len(bits):
        raise Error("LTE turbo sub-block NULL count is outside its input")
    if len(bits) > Int.MAX - 31:
        raise Error("LTE turbo sub-block dimensions overflow Int")
    var rows = (len(bits) + 31) // 32
    var output_bits = _checked_product(rows, 32, "LTE turbo sub-block")
    var dummy_bits = output_bits - len(bits)
    var padded = List[UInt8](length=output_bits, fill=UInt8(0))
    var padded_null = List[UInt8](length=output_bits, fill=UInt8(0))
    for index in range(dummy_bits):
        padded_null[index] = 1
    for index in range(len(bits)):
        padded[dummy_bits + index] = bits[index]
        if index < leading_null_bits:
            padded_null[dummy_bits + index] = UInt8(1)

    var permutation = _lte_subblock_column_permutation()
    var result = List[UInt8](length=output_bits, fill=UInt8(0))
    var null_mask = List[UInt8](length=output_bits, fill=UInt8(0))
    if third_stream:
        for output_index in range(output_bits):
            var source = (
                permutation[output_index // rows]
                + 32 * (output_index % rows)
                + 1
            ) % output_bits
            result[output_index] = padded[source]
            null_mask[output_index] = padded_null[source]
    else:
        var output_index = 0
        for permuted_column in range(32):
            var source_column = permutation[permuted_column]
            for row in range(rows):
                var source = row * 32 + source_column
                result[output_index] = padded[source]
                null_mask[output_index] = padded_null[source]
                output_index += 1
    return LTESubblockBits(result^, null_mask^, len(bits), rows)


def _lte_turbo_subblock_deinterleave_soft(
    values: Span[Float64, ...], input_bits: Int, *, third_stream: Bool = False
) raises -> List[Float64]:
    if input_bits < 1 or input_bits > Int.MAX - 31:
        raise Error("invalid LTE turbo deinterleaver input size")
    var rows = (input_bits + 31) // 32
    var padded_bits = _checked_product(rows, 32, "LTE turbo deinterleaver")
    if len(values) != padded_bits:
        raise Error("LTE turbo deinterleaver length is inconsistent")
    var padded = List[Float64](length=padded_bits, fill=0.0)
    var permutation = _lte_subblock_column_permutation()
    if third_stream:
        for output_index in range(padded_bits):
            if not isfinite(values[output_index]):
                raise Error("LTE turbo recovered LLRs must be finite")
            var source = (
                permutation[output_index // rows]
                + 32 * (output_index % rows)
                + 1
            ) % padded_bits
            padded[source] = values[output_index]
    else:
        var output_index = 0
        for permuted_column in range(32):
            var source_column = permutation[permuted_column]
            for row in range(rows):
                if not isfinite(values[output_index]):
                    raise Error("LTE turbo recovered LLRs must be finite")
                padded[row * 32 + source_column] = values[output_index]
                output_index += 1
    var dummy_bits = padded_bits - input_bits
    var result = List[Float64](capacity=input_bits)
    for index in range(dummy_bits, padded_bits):
        result.append(padded[index])
    return result^


def _lte_validate_turbo_streams(
    systematic: Span[UInt8, ...],
    parity1: Span[UInt8, ...],
    parity2: Span[UInt8, ...],
) raises:
    if (
        len(systematic) != len(parity1)
        or len(systematic) != len(parity2)
        or len(systematic) < 5
    ):
        raise Error("LTE turbo streams must have equal K+4 lengths")
    _ = lte_qpp_parameters(len(systematic) - 4)
    _validate_binary(systematic, "LTE turbo systematic stream")
    _validate_binary(parity1, "LTE turbo first parity stream")
    _validate_binary(parity2, "LTE turbo second parity stream")


def lte_turbo_circular_buffer(
    systematic: Span[UInt8, ...],
    parity1: Span[UInt8, ...],
    parity2: Span[UInt8, ...],
    filler_bits: Int = 0,
) raises -> LTESubblockBits:
    """Collect streams while masking systematic and first-parity filler outputs."""
    _lte_validate_turbo_streams(systematic, parity1, parity2)
    var block_size = len(systematic) - 4
    if filler_bits < 0 or filler_bits >= block_size:
        raise Error("LTE turbo filler count must be in [0,K)")
    for index in range(filler_bits):
        if systematic[index] != 0:
            raise Error("LTE turbo systematic filler inputs must have value zero")
    var stream0 = lte_turbo_subblock_interleave(
        systematic, leading_null_bits=filler_bits
    )
    var stream1 = lte_turbo_subblock_interleave(
        parity1, leading_null_bits=filler_bits
    )
    var stream2 = lte_turbo_subblock_interleave(
        parity2, third_stream=True
    )
    var k_pi = len(stream0.bits)
    var buffer_bits = _checked_product(k_pi, 3, "LTE turbo circular buffer")
    var bits = List[UInt8](length=buffer_bits, fill=UInt8(0))
    var null_mask = List[UInt8](length=buffer_bits, fill=UInt8(0))
    for index in range(k_pi):
        bits[index] = stream0.bits[index]
        null_mask[index] = stream0.null_mask[index]
        bits[k_pi + 2 * index] = stream1.bits[index]
        null_mask[k_pi + 2 * index] = stream1.null_mask[index]
        bits[k_pi + 2 * index + 1] = stream2.bits[index]
        null_mask[k_pi + 2 * index + 1] = stream2.null_mask[index]
    return LTESubblockBits(bits^, null_mask^, len(systematic), stream0.rows)


def lte_turbo_k0(
    stream_bits: Int,
    redundancy_version: Int,
    circular_buffer_bits: Int = 0,
) raises -> Int:
    """Return the clause 5.1.4.1.2 circular-buffer start index."""
    if stream_bits < 5 or stream_bits > 6148:
        raise Error("LTE turbo stream length must be a standardized K+4")
    _ = lte_qpp_parameters(stream_bits - 4)
    if redundancy_version < 0 or redundancy_version > 3:
        raise Error("LTE turbo redundancy version must be in [0,3]")
    var rows = (stream_bits + 31) // 32
    var k_pi = _checked_product(rows, 32, "LTE turbo sub-block")
    var k_w = _checked_product(k_pi, 3, "LTE turbo circular buffer")
    var n_cb = k_w if circular_buffer_bits == 0 else circular_buffer_bits
    if n_cb < 1 or n_cb > k_w:
        raise Error("invalid LTE turbo circular-buffer length")
    var denominator = _checked_product(8, rows, "LTE turbo k0")
    var groups = (n_cb + denominator - 1) // denominator
    return (
        rows * (2 * groups * redundancy_version + 2)
    ) % n_cb


def lte_turbo_rate_match(
    systematic: Span[UInt8, ...],
    parity1: Span[UInt8, ...],
    parity2: Span[UInt8, ...],
    redundancy_version: Int,
    output_bits: Int,
    circular_buffer_bits: Int = 0,
    filler_bits: Int = 0,
) raises -> List[UInt8]:
    """Select ``E`` non-NULL bits for redundancy versions zero through three."""
    if output_bits < 0:
        raise Error("LTE turbo rate-matching length cannot be negative")
    var circular = lte_turbo_circular_buffer(
        systematic, parity1, parity2, filler_bits
    )
    var n_cb = (
        len(circular.bits)
        if circular_buffer_bits == 0
        else circular_buffer_bits
    )
    var k0 = lte_turbo_k0(
        len(systematic), redundancy_version, n_cb
    )
    var usable = 0
    for index in range(n_cb):
        if circular.null_mask[index] == 0:
            usable += 1
    if output_bits > 0 and usable == 0:
        raise Error("LTE turbo circular buffer contains only NULL entries")
    var result = List[UInt8](capacity=output_bits)
    var position = k0
    while len(result) < output_bits:
        if circular.null_mask[position] == 0:
            result.append(circular.bits[position])
        position = (position + 1) % n_cb
    return result^


def lte_turbo_rate_recover(
    received: Span[Float64, ...],
    block_size: Int,
    redundancy_version: Int,
    circular_buffer_bits: Int = 0,
    filler_bits: Int = 0,
) raises -> LTETurboRateRecovery:
    """Undo circular selection and sub-block permutations, combining repeats."""
    _ = lte_qpp_parameters(block_size)
    var stream_bits = block_size + 4
    var zeros0 = List[UInt8](length=stream_bits, fill=UInt8(0))
    var zeros1 = List[UInt8](length=stream_bits, fill=UInt8(0))
    var zeros2 = List[UInt8](length=stream_bits, fill=UInt8(0))
    var circular = lte_turbo_circular_buffer(
        Span(zeros0), Span(zeros1), Span(zeros2), filler_bits
    )
    var n_cb = (
        len(circular.bits)
        if circular_buffer_bits == 0
        else circular_buffer_bits
    )
    var k0 = lte_turbo_k0(stream_bits, redundancy_version, n_cb)
    var usable = 0
    for index in range(n_cb):
        if circular.null_mask[index] == 0:
            usable += 1
    if len(received) > 0 and usable == 0:
        raise Error("LTE turbo circular buffer contains only NULL entries")
    var buffer = List[Float64](length=len(circular.bits), fill=0.0)
    var position = k0
    for received_index in range(len(received)):
        if not isfinite(received[received_index]):
            raise Error("LTE turbo rate-recovery LLRs must be finite")
        while circular.null_mask[position] != 0:
            position = (position + 1) % n_cb
        var combined = buffer[position] + received[received_index]
        if not isfinite(combined):
            raise Error("LTE turbo repeated LLR accumulation overflows")
        buffer[position] = combined
        position = (position + 1) % n_cb

    var k_pi = len(circular.bits) // 3
    var stream0 = List[Float64](capacity=k_pi)
    var stream1 = List[Float64](capacity=k_pi)
    var stream2 = List[Float64](capacity=k_pi)
    for index in range(k_pi):
        stream0.append(buffer[index])
        stream1.append(buffer[k_pi + 2 * index])
        stream2.append(buffer[k_pi + 2 * index + 1])
    var systematic = _lte_turbo_subblock_deinterleave_soft(
        Span(stream0), stream_bits
    )
    var parity1 = _lte_turbo_subblock_deinterleave_soft(
        Span(stream1), stream_bits
    )
    var parity2 = _lte_turbo_subblock_deinterleave_soft(
        Span(stream2), stream_bits, third_stream=True
    )
    return LTETurboRateRecovery(systematic^, parity1^, parity2^)


def _lte_max_log_constituent(
    systematic: Span[Float64, ...],
    parity: Span[Float64, ...],
    apriori: Span[Float64, ...],
) raises -> Tuple[List[Float64], List[Float64]]:
    """Readable terminated 8-state max-log-MAP constituent decoder."""
    var information_bits = len(apriori)
    var trellis_steps = information_bits + 3
    if len(systematic) != trellis_steps or len(parity) != trellis_steps:
        raise Error("LTE max-log constituent streams have invalid lengths")
    var state_columns = _checked_product(
        trellis_steps + 1, 8, "LTE max-log state metrics"
    )
    var positive_infinity = inf[DType.float64]()
    var negative_infinity = -positive_infinity
    var alpha = List[Float64](length=state_columns, fill=negative_infinity)
    var beta = List[Float64](length=state_columns, fill=negative_infinity)
    alpha[0] = 0.0

    for step in range(trellis_steps):
        var row_max = negative_infinity
        var apriori_value = apriori[step] if step < information_bits else 0.0
        if (
            not isfinite(systematic[step])
            or not isfinite(parity[step])
            or not isfinite(apriori_value)
        ):
            raise Error("LTE max-log inputs must be finite")
        for previous in range(8):
            var previous_metric = alpha[step * 8 + previous]
            if not isfinite(previous_metric):
                continue
            for input_bit in range(2):
                var transition = _lte_rsc_step(previous, UInt8(input_bit))
                var next_state = transition[0]
                var parity_bit = Int(transition[1])
                var branch = 0.5 * (
                    Float64(1 - 2 * input_bit)
                    * (systematic[step] + apriori_value)
                    + Float64(1 - 2 * parity_bit) * parity[step]
                )
                var candidate = previous_metric + branch
                var offset = (step + 1) * 8 + next_state
                if candidate > alpha[offset]:
                    alpha[offset] = candidate
                    if candidate > row_max:
                        row_max = candidate
        if not isfinite(row_max):
            raise Error("LTE max-log forward trellis is unreachable")
        for state in range(8):
            var offset = (step + 1) * 8 + state
            if isfinite(alpha[offset]):
                alpha[offset] -= row_max

    # LTE trellis termination constrains both constituent encoders to state 0.
    beta[trellis_steps * 8] = 0.0
    for reverse_step in range(trellis_steps):
        var step = trellis_steps - reverse_step - 1
        var row_max = negative_infinity
        var apriori_value = apriori[step] if step < information_bits else 0.0
        for previous in range(8):
            var best = negative_infinity
            for input_bit in range(2):
                var transition = _lte_rsc_step(previous, UInt8(input_bit))
                var next_metric = beta[(step + 1) * 8 + transition[0]]
                if not isfinite(next_metric):
                    continue
                var parity_bit = Int(transition[1])
                var branch = 0.5 * (
                    Float64(1 - 2 * input_bit)
                    * (systematic[step] + apriori_value)
                    + Float64(1 - 2 * parity_bit) * parity[step]
                )
                var candidate = next_metric + branch
                if candidate > best:
                    best = candidate
            beta[step * 8 + previous] = best
            if best > row_max:
                row_max = best
        if not isfinite(row_max):
            raise Error("LTE max-log backward trellis is unreachable")
        for state in range(8):
            var offset = step * 8 + state
            if isfinite(beta[offset]):
                beta[offset] -= row_max

    var extrinsic = List[Float64](length=information_bits, fill=0.0)
    var posterior = List[Float64](length=information_bits, fill=0.0)
    for step in range(information_bits):
        var best_zero = negative_infinity
        var best_one = negative_infinity
        for previous in range(8):
            var forward = alpha[step * 8 + previous]
            if not isfinite(forward):
                continue
            for input_bit in range(2):
                var transition = _lte_rsc_step(previous, UInt8(input_bit))
                var backward = beta[(step + 1) * 8 + transition[0]]
                if not isfinite(backward):
                    continue
                var parity_bit = Int(transition[1])
                var branch = 0.5 * (
                    Float64(1 - 2 * input_bit)
                    * (systematic[step] + apriori[step])
                    + Float64(1 - 2 * parity_bit) * parity[step]
                )
                var candidate = forward + branch + backward
                if input_bit == 0 and candidate > best_zero:
                    best_zero = candidate
                elif input_bit == 1 and candidate > best_one:
                    best_one = candidate
        if not isfinite(best_zero) or not isfinite(best_one):
            raise Error("LTE max-log bit decision is unreachable")
        posterior[step] = best_zero - best_one
        extrinsic[step] = (
            posterior[step] - systematic[step] - apriori[step]
        )
        if not isfinite(extrinsic[step]):
            raise Error("LTE max-log extrinsic information overflows")
    return (extrinsic^, posterior^)


def lte_turbo_decode_max_log(
    systematic: Span[Float64, ...],
    parity1: Span[Float64, ...],
    parity2: Span[Float64, ...],
    *,
    iterations: Int = 6,
) raises -> LTETurboDecodeResult:
    """Iteratively decode one rate-recovered LTE turbo code block.

    This is a deliberately direct max-log-MAP reference implementation.  It
    favors auditability over throughput and uses the transmitted termination
    bit packing from clause 5.1.3.2.2 exactly.
    """
    if (
        len(systematic) != len(parity1)
        or len(systematic) != len(parity2)
        or len(systematic) < 5
    ):
        raise Error("LTE max-log turbo streams must have equal K+4 lengths")
    var block_size = len(systematic) - 4
    _ = lte_qpp_parameters(block_size)
    if iterations < 1 or iterations > 32:
        raise Error("LTE max-log iteration count must be in [1,32]")

    # Uniform scaling is decision invariant and prevents finite but extreme
    # caller LLRs from overflowing path-metric additions.
    var scale = 1.0
    for index in range(len(systematic)):
        if (
            not isfinite(systematic[index])
            or not isfinite(parity1[index])
            or not isfinite(parity2[index])
        ):
            raise Error("LTE max-log turbo LLRs must be finite")
        scale = max(scale, abs(systematic[index]))
        scale = max(scale, abs(parity1[index]))
        scale = max(scale, abs(parity2[index]))

    var first_systematic = List[Float64](capacity=block_size + 3)
    var first_parity = List[Float64](capacity=block_size + 3)
    var original_systematic = List[Float64](capacity=block_size)
    var second_parity = List[Float64](capacity=block_size + 3)
    for index in range(block_size):
        original_systematic.append(systematic[index] / scale)
        first_systematic.append(systematic[index] / scale)
        first_parity.append(parity1[index] / scale)
        second_parity.append(parity2[index] / scale)
    first_systematic.append(systematic[block_size] / scale)
    first_systematic.append(parity2[block_size] / scale)
    first_systematic.append(parity1[block_size + 1] / scale)
    first_parity.append(parity1[block_size] / scale)
    first_parity.append(systematic[block_size + 1] / scale)
    first_parity.append(parity2[block_size + 1] / scale)

    var second_systematic_data = _lte_qpp_interleave_soft(
        Span(original_systematic)
    )
    var second_systematic = List[Float64](capacity=block_size + 3)
    for value in second_systematic_data:
        second_systematic.append(value)
    second_systematic.append(systematic[block_size + 2] / scale)
    second_systematic.append(parity2[block_size + 2] / scale)
    second_systematic.append(parity1[block_size + 3] / scale)
    second_parity.append(parity1[block_size + 2] / scale)
    second_parity.append(systematic[block_size + 3] / scale)
    second_parity.append(parity2[block_size + 3] / scale)

    var apriori_first = List[Float64](length=block_size, fill=0.0)
    var posterior_second = List[Float64](length=block_size, fill=0.0)
    for _ in range(iterations):
        var first = _lte_max_log_constituent(
            Span(first_systematic), Span(first_parity), Span(apriori_first)
        )
        var apriori_second = _lte_qpp_interleave_soft(Span(first[0]))
        var second = _lte_max_log_constituent(
            Span(second_systematic), Span(second_parity), Span(apriori_second)
        )
        apriori_first = _lte_qpp_deinterleave_soft(Span(second[0]))
        posterior_second = second[1].copy()

    var posterior = _lte_qpp_deinterleave_soft(Span(posterior_second))
    var bits = List[UInt8](capacity=block_size)
    for value in posterior:
        bits.append(UInt8(0) if value >= 0.0 else UInt8(1))
    return LTETurboDecodeResult(bits^, posterior^, iterations)
