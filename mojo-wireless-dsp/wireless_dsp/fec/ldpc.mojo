"""Protocol-independent LDPC iterative-decoder primitives."""

from std.collections import Span
from std.math import isfinite


struct LDPCDecodeResult(Movable):
    var bits: List[UInt8]
    var iterations: Int
    var converged: Bool

    def __init__(
        out self, var bits: List[UInt8], iterations: Int, converged: Bool
    ):
        self.bits = bits^
        self.iterations = iterations
        self.converged = converged


def _check_node(values: Span[Float64, ...], scale: Float64, offset: Float64) raises -> List[Float64]:
    if len(values) < 2:
        raise Error("check node requires degree of at least two")
    for i in range(len(values)):
        if not isfinite(values[i]):
            raise Error("check-node inputs must be finite")
    var minimum = abs(values[0])
    var second = abs(values[1])
    var minimum_index = 0
    if second < minimum:
        minimum = abs(values[1])
        second = abs(values[0])
        minimum_index = 1
    for i in range(2, len(values)):
        var magnitude = abs(values[i])
        if magnitude < minimum:
            second = minimum
            minimum = magnitude
            minimum_index = i
        elif magnitude < second:
            second = magnitude
    var all_sign = 1
    for i in range(len(values)):
        if values[i] < 0.0:
            all_sign = -all_sign
    var result = List[Float64](capacity=len(values))
    for i in range(len(values)):
        var magnitude = second if i == minimum_index else minimum
        magnitude = max(0.0, magnitude * scale - offset)
        var sign = -all_sign if values[i] < 0.0 else all_sign
        result.append(magnitude if sign > 0 else -magnitude)
    return result^


def check_node_min_sum(values: Span[Float64, ...]) raises -> List[Float64]:
    return _check_node(values, 1.0, 0.0)


def check_node_normalized_min_sum(
    values: Span[Float64, ...], normalization: Float64
) raises -> List[Float64]:
    if (
        not isfinite(normalization)
        or normalization <= 0.0
        or normalization > 1.0
    ):
        raise Error("normalization must be finite and in (0, 1]")
    return _check_node(values, normalization, 0.0)


def check_node_offset_min_sum(
    values: Span[Float64, ...], offset: Float64
) raises -> List[Float64]:
    if not isfinite(offset) or offset < 0.0:
        raise Error("offset must be finite and non-negative")
    return _check_node(values, 1.0, offset)


def variable_node_sum(channel_llr: Float64, messages: Span[Float64, ...], clip: Float64) raises -> Float64:
    if not isfinite(channel_llr) or not isfinite(clip) or clip <= 0.0:
        raise Error("variable-node inputs and positive clip must be finite")
    var scale = abs(channel_llr)
    for i in range(len(messages)):
        if not isfinite(messages[i]):
            raise Error("variable-node messages must be finite")
        scale = max(scale, abs(messages[i]))
    if scale == 0.0:
        return 0.0

    # Preserve the ordinary-domain result (including exact binary-fraction
    # sums) whenever every intermediate is representable.  Neumaier's
    # correction also retains a small residual across large cancellation.
    var direct_total = channel_llr
    var direct_correction = 0.0
    var direct_ok = True
    for i in range(len(messages)):
        var term = messages[i]
        var candidate = direct_total + term
        if not isfinite(candidate):
            direct_ok = False
            break
        var increment = (
            (direct_total - candidate) + term
            if abs(direct_total) >= abs(term)
            else (term - candidate) + direct_total
        )
        var corrected = direct_correction + increment
        if not isfinite(corrected):
            direct_ok = False
            break
        direct_correction = corrected
        direct_total = candidate
    if direct_ok:
        var direct_result = direct_total + direct_correction
        if isfinite(direct_result):
            return max(-clip, min(clip, direct_result))

    # If an ordinary intermediate overflowed, repeat in a unit-scaled domain.
    # Compare before rescaling so clipping never overflows.
    var total = channel_llr / scale
    var correction = 0.0
    for i in range(len(messages)):
        var term = messages[i] / scale
        var candidate = total + term
        if abs(total) >= abs(term):
            correction += (total - candidate) + term
        else:
            correction += (term - candidate) + total
        total = candidate
    var normalized = total + correction
    var normalized_clip = clip / scale
    if normalized >= normalized_clip:
        return clip
    if normalized <= -normalized_clip:
        return -clip
    var result = normalized * scale
    if not isfinite(result):
        raise Error("variable-node result is not representable")
    return result


def _validate_sparse_parity_graph(
    variable_count: Int,
    row_offsets: Span[Int, ...],
    columns: Span[Int, ...],
) raises:
    if (
        variable_count <= 0
        or len(row_offsets) < 2
        or row_offsets[0] != 0
        or row_offsets[len(row_offsets) - 1] != len(columns)
    ):
        raise Error("invalid sparse parity-check representation")
    for row in range(len(row_offsets) - 1):
        var start = row_offsets[row]
        var end = row_offsets[row + 1]
        if start < 0 or end < start or end > len(columns):
            raise Error("parity-check row offsets must be ordered and in range")
        if end - start < 2:
            raise Error("LDPC check degree must be at least two")
        for edge in range(start, end):
            var column = columns[edge]
            if column < 0 or column >= variable_count:
                raise Error("parity-check column out of range")
            for other in range(edge + 1, end):
                if columns[other] == column:
                    raise Error("parity-check row contains a duplicate column")


def syndrome_ok(
    bits: Span[UInt8, ...], row_offsets: Span[Int, ...], columns: Span[Int, ...]
) raises -> Bool:
    _validate_sparse_parity_graph(len(bits), row_offsets, columns)
    for index in range(len(bits)):
        if bits[index] > 1:
            raise Error("syndrome input must contain zero or one")
    return _syndrome_ok_unchecked(bits, row_offsets, columns)


def _syndrome_ok_unchecked(
    bits: Span[UInt8, ...],
    row_offsets: Span[Int, ...],
    columns: Span[Int, ...],
) -> Bool:
    for row in range(len(row_offsets) - 1):
        var parity = UInt8(0)
        for edge in range(row_offsets[row], row_offsets[row + 1]):
            parity ^= bits[columns[edge]]
        if parity != 0:
            return False
    return True


def cyclic_shift(
    values: Span[Float64, ...], shift: Int
) raises -> List[Float64]:
    if len(values) == 0:
        return List[Float64]()
    for index in range(len(values)):
        if not isfinite(values[index]):
            raise Error("cyclic-shift values must be finite")
    var normalized = shift % len(values)
    if normalized < 0:
        normalized += len(values)
    var result = List[Float64](capacity=len(values))
    for i in range(len(values)):
        result.append(values[(i - normalized + len(values)) % len(values)])
    return result^


def ldpc_decode_min_sum(
    channel_llrs: Span[Float64, ...],
    row_offsets: Span[Int, ...],
    columns: Span[Int, ...],
    *,
    max_iterations: Int,
    normalization: Float64 = 1.0,
    offset: Float64 = 0.0,
    clip: Float64 = 50.0,
) raises -> LDPCDecodeResult:
    """Flooding normalized/offset min-sum over a sparse parity-check matrix."""
    if (
        max_iterations < 1
        or not isfinite(normalization)
        or normalization <= 0.0
        or normalization > 1.0
    ):
        raise Error("invalid LDPC decoder configuration")
    if (
        not isfinite(offset)
        or offset < 0.0
        or not isfinite(clip)
        or clip <= 0.0
    ):
        raise Error("invalid LDPC numeric configuration")
    _validate_sparse_parity_graph(
        len(channel_llrs), row_offsets, columns
    )
    var edge_count = len(columns)
    var variable_to_check = List[Float64](length=edge_count, fill=0.0)
    var check_to_variable = List[Float64](length=edge_count, fill=0.0)
    for variable in range(len(channel_llrs)):
        if not isfinite(channel_llrs[variable]):
            raise Error("LDPC channel LLRs must be finite")
    for edge in range(edge_count):
        variable_to_check[edge] = max(
            -clip, min(clip, channel_llrs[columns[edge]])
        )
    var posterior = List[Float64](length=len(channel_llrs), fill=0.0)
    var hard = List[UInt8](length=len(channel_llrs), fill=UInt8(0))
    for iteration in range(max_iterations):
        for row in range(len(row_offsets) - 1):
            var start = row_offsets[row]
            var end = row_offsets[row + 1]
            var minimum = abs(variable_to_check[start])
            var second = abs(variable_to_check[start + 1])
            var minimum_edge = start
            if second < minimum:
                minimum = abs(variable_to_check[start + 1])
                second = abs(variable_to_check[start])
                minimum_edge = start + 1
            var all_sign = 1
            for edge in range(start, end):
                if variable_to_check[edge] < 0.0:
                    all_sign = -all_sign
            for edge in range(start + 2, end):
                var magnitude = abs(variable_to_check[edge])
                if magnitude < minimum:
                    second = minimum
                    minimum = magnitude
                    minimum_edge = edge
                elif magnitude < second:
                    second = magnitude
            for edge in range(start, end):
                var magnitude = second if edge == minimum_edge else minimum
                magnitude = max(0.0, normalization * magnitude - offset)
                var sign = -all_sign if variable_to_check[edge] < 0.0 else all_sign
                check_to_variable[edge] = magnitude if sign > 0 else -magnitude
        for variable in range(len(channel_llrs)):
            posterior[variable] = channel_llrs[variable]
        for edge in range(edge_count):
            posterior[columns[edge]] += check_to_variable[edge]
        for variable in range(len(channel_llrs)):
            posterior[variable] = max(-clip, min(clip, posterior[variable]))
            hard[variable] = UInt8(0) if posterior[variable] >= 0.0 else UInt8(1)
        if _syndrome_ok_unchecked(Span(hard), row_offsets, columns):
            return LDPCDecodeResult(hard^, iteration + 1, True)
        for edge in range(edge_count):
            variable_to_check[edge] = max(
                -clip,
                min(clip, posterior[columns[edge]] - check_to_variable[edge]),
            )
    return LDPCDecodeResult(hard^, max_iterations, False)


def ldpc_decode_layered_min_sum(
    channel_llrs: Span[Float64, ...],
    row_offsets: Span[Int, ...],
    columns: Span[Int, ...],
    *,
    max_iterations: Int,
    normalization: Float64 = 1.0,
    offset: Float64 = 0.0,
    clip: Float64 = 50.0,
) raises -> LDPCDecodeResult:
    """Layered normalized/offset min-sum with immediate posterior updates."""
    if (
        max_iterations < 1
        or not isfinite(normalization)
        or normalization <= 0.0
        or normalization > 1.0
    ):
        raise Error("invalid layered LDPC decoder configuration")
    if (
        not isfinite(offset)
        or offset < 0.0
        or not isfinite(clip)
        or clip <= 0.0
    ):
        raise Error("invalid layered LDPC numeric configuration")
    _validate_sparse_parity_graph(
        len(channel_llrs), row_offsets, columns
    )

    var posterior = List[Float64](capacity=len(channel_llrs))
    for i in range(len(channel_llrs)):
        if not isfinite(channel_llrs[i]):
            raise Error("layered LDPC channel LLRs must be finite")
        posterior.append(max(-clip, min(clip, channel_llrs[i])))
    var check_to_variable = List[Float64](length=len(columns), fill=0.0)
    var hard = List[UInt8](length=len(channel_llrs), fill=UInt8(0))

    for iteration in range(max_iterations):
        for row in range(len(row_offsets) - 1):
            var start = row_offsets[row]
            var end = row_offsets[row + 1]
            var all_sign = 1
            var extrinsic = List[Float64](capacity=end - start)
            for edge in range(start, end):
                var value = max(
                    -clip,
                    min(
                        clip,
                        posterior[columns[edge]] - check_to_variable[edge],
                    ),
                )
                extrinsic.append(value)
                if value < 0.0:
                    all_sign = -all_sign
            var minimum = abs(extrinsic[0])
            var second = abs(extrinsic[1])
            var minimum_edge = start
            if second < minimum:
                minimum = abs(extrinsic[1])
                second = abs(extrinsic[0])
                minimum_edge = start + 1
            for local in range(2, len(extrinsic)):
                var magnitude = abs(extrinsic[local])
                if magnitude < minimum:
                    second = minimum
                    minimum = magnitude
                    minimum_edge = start + local
                elif magnitude < second:
                    second = magnitude

            for edge in range(start, end):
                var local = edge - start
                var magnitude = second if edge == minimum_edge else minimum
                magnitude = max(0.0, normalization * magnitude - offset)
                var sign = -all_sign if extrinsic[local] < 0.0 else all_sign
                var message = magnitude if sign > 0 else -magnitude
                check_to_variable[edge] = message
                posterior[columns[edge]] = max(
                    -clip, min(clip, extrinsic[local] + message)
                )

        for variable in range(len(channel_llrs)):
            hard[variable] = UInt8(0) if posterior[variable] >= 0.0 else UInt8(1)
        if _syndrome_ok_unchecked(Span(hard), row_offsets, columns):
            return LDPCDecodeResult(hard^, iteration + 1, True)
    return LDPCDecodeResult(hard^, max_iterations, False)
