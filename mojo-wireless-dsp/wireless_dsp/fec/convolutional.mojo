"""Generic rate-1/N convolutional encoder and hard Viterbi decoder."""

from std.collections import Span
from std.math import isfinite
from std.utils.numerics import inf


def _parity(value: Int) -> UInt8:
    var x = value
    var result = UInt8(0)
    while x != 0:
        result ^= UInt8(x & 1)
        x >>= 1
    return result


def _validate_convolutional_configuration(
    generators: Span[Int, ...], constraint_length: Int
) raises:
    if constraint_length < 2 or constraint_length > 12 or len(generators) == 0:
        raise Error("unsupported convolutional-code configuration")
    var mask = (1 << constraint_length) - 1
    for index in range(len(generators)):
        if generators[index] < 1 or generators[index] > mask:
            raise Error("convolutional generator must fit the constraint length")


def convolutional_encode(
    bits: Span[UInt8, ...], generators: Span[Int, ...], constraint_length: Int,
    *, terminate: Bool = True,
) raises -> List[UInt8]:
    _validate_convolutional_configuration(generators, constraint_length)
    var state = 0
    var steps = len(bits) + (constraint_length - 1 if terminate else 0)
    var result = List[UInt8](capacity=steps * len(generators))
    var mask = (1 << constraint_length) - 1
    for i in range(steps):
        var bit = Int(bits[i]) if i < len(bits) else 0
        if bit != 0 and bit != 1:
            raise Error("bits must be zero or one")
        state = ((state << 1) | bit) & mask
        for j in range(len(generators)):
            result.append(_parity(state & generators[j]))
    return result^


def viterbi_decode_hard(
    encoded: Span[UInt8, ...], generators: Span[Int, ...], constraint_length: Int,
    *, terminate: Bool = True,
) raises -> List[UInt8]:
    _validate_convolutional_configuration(generators, constraint_length)
    if len(generators) == 0 or len(encoded) % len(generators) != 0:
        raise Error("encoded length must contain complete trellis symbols")
    var state_count = 1 << (constraint_length - 1)
    var steps = len(encoded) // len(generators)
    if terminate and steps < constraint_length - 1:
        raise Error("terminated trellis is shorter than its tail")
    for index in range(len(encoded)):
        if encoded[index] > 1:
            raise Error("encoded bits must be zero or one")
    var infinity = 1_000_000_000
    var metrics = List[Int](length=state_count, fill=infinity)
    metrics[0] = 0
    var predecessors = List[Int](length=steps * state_count, fill=-1)
    var decisions = List[UInt8](length=steps * state_count, fill=UInt8(0))
    var state_mask = state_count - 1
    for step in range(steps):
        var next_metrics = List[Int](length=state_count, fill=infinity)
        for previous in range(state_count):
            if metrics[previous] == infinity:
                continue
            for input_bit in range(2):
                var register = (previous << 1) | input_bit
                var next_state = register & state_mask
                var distance = 0
                for output in range(len(generators)):
                    distance += Int(_parity(register & generators[output]) != encoded[step * len(generators) + output])
                var candidate = metrics[previous] + distance
                if candidate < next_metrics[next_state]:
                    next_metrics[next_state] = candidate
                    predecessors[step * state_count + next_state] = previous
                    decisions[step * state_count + next_state] = UInt8(input_bit)
        metrics = next_metrics^
    var state = 0 if terminate else 0
    if not terminate:
        for candidate in range(1, state_count):
            if metrics[candidate] < metrics[state]:
                state = candidate
    var decoded = List[UInt8](length=steps, fill=UInt8(0))
    for reverse_step in range(steps):
        var step = steps - reverse_step - 1
        decoded[step] = decisions[step * state_count + state]
        state = predecessors[step * state_count + state]
        if state < 0:
            raise Error("Viterbi traceback is unreachable")
    var payload_length = steps - (constraint_length - 1 if terminate else 0)
    var result = List[UInt8](capacity=payload_length)
    for i in range(payload_length):
        result.append(decoded[i])
    return result^


def puncture_bits(bits: Span[UInt8, ...], pattern: Span[UInt8, ...]) raises -> List[UInt8]:
    if len(pattern) == 0:
        raise Error("puncturing pattern cannot be empty")
    for index in range(len(pattern)):
        if pattern[index] > 1:
            raise Error("puncturing pattern must contain zero or one")
    for index in range(len(bits)):
        if bits[index] > 1:
            raise Error("puncturing input must contain zero or one")
    var result = List[UInt8]()
    for i in range(len(bits)):
        var keep = pattern[i % len(pattern)]
        if keep == 1:
            result.append(bits[i])
    return result^


def depuncture_llrs(
    llrs: Span[Float64, ...], pattern: Span[UInt8, ...], mother_length: Int
) raises -> List[Float64]:
    if len(pattern) == 0 or mother_length < 0:
        raise Error("invalid depuncturing configuration")
    for index in range(len(pattern)):
        if pattern[index] > 1:
            raise Error("depuncturing pattern must contain zero or one")
    for index in range(len(llrs)):
        if not isfinite(llrs[index]):
            raise Error("depuncturing LLRs must be finite")
    var result = List[Float64](capacity=mother_length)
    var source = 0
    for i in range(mother_length):
        if pattern[i % len(pattern)] == 1:
            if source >= len(llrs):
                raise Error("not enough punctured LLRs")
            result.append(llrs[source])
            source += 1
        else:
            result.append(0.0)
    if source != len(llrs):
        raise Error("too many punctured LLRs")
    return result^


def viterbi_decode_soft(
    llrs: Span[Float64, ...], generators: Span[Int, ...], constraint_length: Int,
    *, terminate: Bool = True,
) raises -> List[UInt8]:
    """Soft-input Viterbi; positive LLR denotes transmitted bit zero."""
    _validate_convolutional_configuration(generators, constraint_length)
    if len(generators) == 0 or len(llrs) % len(generators) != 0:
        raise Error("LLR length must contain complete trellis symbols")
    var state_count = 1 << (constraint_length - 1)
    var steps = len(llrs) // len(generators)
    if terminate and steps < constraint_length - 1:
        raise Error("terminated trellis is shorter than its tail")
    for index in range(len(llrs)):
        if not isfinite(llrs[index]):
            raise Error("Viterbi LLRs must be finite")
    var infinity = inf[DType.float64]()
    var metrics = List[Float64](length=state_count, fill=infinity)
    metrics[0] = 0.0
    var predecessors = List[Int](length=steps * state_count, fill=-1)
    var decisions = List[UInt8](length=steps * state_count, fill=UInt8(0))
    var state_mask = state_count - 1
    for step in range(steps):
        var next_metrics = List[Float64](length=state_count, fill=infinity)
        for previous in range(state_count):
            if metrics[previous] == infinity:
                continue
            for input_bit in range(2):
                var register = (previous << 1) | input_bit
                var next_state = register & state_mask
                var cost = 0.0
                for output in range(len(generators)):
                    var expected = _parity(register & generators[output])
                    var llr = llrs[step * len(generators) + output]
                    var term = (
                        max(0.0, -llr)
                        if expected == 0
                        else max(0.0, llr)
                    )
                    if cost > Float64.MAX_FINITE - term:
                        cost = infinity
                        break
                    cost += term
                var candidate = infinity
                if (
                    isfinite(cost)
                    and metrics[previous] <= Float64.MAX_FINITE - cost
                ):
                    candidate = metrics[previous] + cost
                if candidate < next_metrics[next_state]:
                    next_metrics[next_state] = candidate
                    predecessors[step * state_count + next_state] = previous
                    decisions[step * state_count + next_state] = UInt8(input_bit)
        # A common path-metric offset does not affect survivor decisions.  The
        # renormalization prevents a long but otherwise representable trellis
        # from overflowing merely because every path accumulated a large base.
        var minimum_metric = infinity
        for state in range(state_count):
            if next_metrics[state] < minimum_metric:
                minimum_metric = next_metrics[state]
        if not isfinite(minimum_metric):
            raise Error("Viterbi trellis has no representable survivor")
        if minimum_metric != 0.0:
            for state in range(state_count):
                if isfinite(next_metrics[state]):
                    next_metrics[state] -= minimum_metric
        metrics = next_metrics^
    var state = 0
    if not terminate:
        for candidate in range(1, state_count):
            if metrics[candidate] < metrics[state]:
                state = candidate
    var decoded = List[UInt8](length=steps, fill=UInt8(0))
    for reverse_step in range(steps):
        var step = steps - reverse_step - 1
        decoded[step] = decisions[step * state_count + state]
        state = predecessors[step * state_count + state]
        if state < 0:
            raise Error("Viterbi traceback is unreachable")
    var payload_length = steps - (constraint_length - 1 if terminate else 0)
    var result = List[UInt8](capacity=payload_length)
    for i in range(payload_length):
        result.append(decoded[i])
    return result^
