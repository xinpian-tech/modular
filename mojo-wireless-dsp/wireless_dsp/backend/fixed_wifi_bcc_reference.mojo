"""Bit-exact IEEE 802.11 K=7, rate-1/2 BCC golden primitives.

The encoder implements the mother code with generators ``133`` and ``171``
(octal), serialized as ``A0, B0, A1, B1, ...``.  The two Viterbi entry points
share an integer-only 64-state trellis.  Soft inputs are signed raw LLR words:
positive favors a coded zero and negative favors a coded one.

Path metrics retain the LLR binary point, use a caller-selected signed storage
width, saturate after each branch/path addition, and are normalized by the
minimum reachable metric after every trellis step.  A survivor tie selects the
lower predecessor state; an unterminated final-state tie selects the lower
state.  An exact zero LLR therefore remains an erasure with deterministic
traceback rather than acquiring an implementation-dependent sign.
"""

from std.collections import Span
from wireless_dsp.numerics.fixed import (
    OVERFLOW_SATURATE,
    ROUND_NEAREST_AWAY,
)
from wireless_dsp.numerics.quantization import (
    QFormat,
    narrow_raw,
    require_raw_fits,
)
from wireless_dsp.testing.fixed_vectors import (
    fixed_raw_checksum,
    serialize_fixed_vector,
)


comptime WIFI_BCC_CONSTRAINT_LENGTH = 7
comptime WIFI_BCC_STATE_COUNT = 64
comptime WIFI_BCC_GENERATOR_A = 0o133
comptime WIFI_BCC_GENERATOR_B = 0o171
comptime WIFI_BCC_RATE_NUMERATOR = 1
comptime WIFI_BCC_RATE_DENOMINATOR = 2
comptime WIFI_BCC_TIE_LOWER_PREDECESSOR = 0


struct FixedWifiBCCViterbiConfig(ImplicitlyCopyable):
    """Quantized soft-input and path-metric format contract.

    ``llr_format`` must saturate.  Path metrics use the same fractional width
    and ``metric_storage_bits`` signed bits.  Although metrics are non-negative,
    the signed maximum is used so their serialized Q-format is unambiguous.
    """

    var llr_format: QFormat
    var metric_storage_bits: Int

    def __init__(
        out self, llr_format: QFormat, metric_storage_bits: Int = 24
    ) raises:
        if llr_format.overflow_mode != OVERFLOW_SATURATE:
            raise Error("fixed Wi-Fi BCC LLRs require saturating overflow")
        if metric_storage_bits < 2 or metric_storage_bits > 62:
            raise Error("fixed Wi-Fi BCC metric width must be in [2,62]")
        if llr_format.fraction_bits >= metric_storage_bits:
            raise Error("fixed Wi-Fi BCC metric width must exceed LLR fraction bits")
        self.llr_format = llr_format
        self.metric_storage_bits = metric_storage_bits

    def metric_format(self) raises -> QFormat:
        return QFormat(
            self.metric_storage_bits,
            self.llr_format.fraction_bits,
            ROUND_NEAREST_AWAY,
            OVERFLOW_SATURATE,
        )

    def metric_max_raw(self) -> Int64:
        return (Int64(1) << Int64(self.metric_storage_bits - 1)) - 1


struct FixedWifiBCCDecodeResult(Movable):
    """Decoded bits plus hardware-facing survivor/metric checkpoints.

    ``saturation_count`` counts every clamped branch or path candidate that is
    evaluated, including candidates that do not become survivors.
    """

    var bits: List[UInt8]
    var survivor_predecessors: List[Int]
    var survivor_decisions: List[UInt8]
    var final_metrics_raw: List[Int64]
    var final_reachable: List[UInt8]
    var normalization_offsets_raw: List[Int64]
    var final_state: Int
    var final_normalized_metric_raw: Int64
    var saturation_count: Int
    var steps: Int
    var terminated: Bool
    var metric_storage_bits: Int
    var metric_fraction_bits: Int

    def __init__(
        out self,
        var bits: List[UInt8],
        var survivor_predecessors: List[Int],
        var survivor_decisions: List[UInt8],
        var final_metrics_raw: List[Int64],
        var final_reachable: List[UInt8],
        var normalization_offsets_raw: List[Int64],
        final_state: Int,
        final_normalized_metric_raw: Int64,
        saturation_count: Int,
        steps: Int,
        terminated: Bool,
        metric_storage_bits: Int,
        metric_fraction_bits: Int,
    ):
        self.bits = bits^
        self.survivor_predecessors = survivor_predecessors^
        self.survivor_decisions = survivor_decisions^
        self.final_metrics_raw = final_metrics_raw^
        self.final_reachable = final_reachable^
        self.normalization_offsets_raw = normalization_offsets_raw^
        self.final_state = final_state
        self.final_normalized_metric_raw = final_normalized_metric_raw
        self.saturation_count = saturation_count
        self.steps = steps
        self.terminated = terminated
        self.metric_storage_bits = metric_storage_bits
        self.metric_fraction_bits = metric_fraction_bits


@always_inline
def _wifi_bcc_parity(value: Int) -> UInt8:
    var remaining = value
    var parity = UInt8(0)
    while remaining != 0:
        parity ^= UInt8(remaining & 1)
        remaining >>= 1
    return parity


def fixed_wifi_bcc_encode(
    bits: Span[UInt8, ...], *, terminate: Bool = True
) raises -> List[UInt8]:
    """Encode binary input using the IEEE K=7 rate-1/2 mother code."""
    for index in range(len(bits)):
        if bits[index] > 1:
            raise Error("fixed Wi-Fi BCC encoder input must be binary")
    var tail = WIFI_BCC_CONSTRAINT_LENGTH - 1 if terminate else 0
    var steps = len(bits) + tail
    var result = List[UInt8](capacity=WIFI_BCC_RATE_DENOMINATOR * steps)
    var register = 0
    comptime register_mask = (1 << WIFI_BCC_CONSTRAINT_LENGTH) - 1
    for step in range(steps):
        var bit = Int(bits[step]) if step < len(bits) else 0
        register = ((register << 1) | bit) & register_mask
        result.append(_wifi_bcc_parity(register & WIFI_BCC_GENERATOR_A))
        result.append(_wifi_bcc_parity(register & WIFI_BCC_GENERATOR_B))
    return result^


def fixed_wifi_bcc_hard_llrs_raw(
    coded_bits: Span[UInt8, ...],
    reliability_raw: Int64,
    llr_format: QFormat,
) raises -> List[Int64]:
    """Map hard bits to saturating raw LLRs with positive sign for zero.

    ``reliability_raw`` is a non-negative magnitude in ``llr_format`` units.
    Values above the positive range saturate before signs are applied.
    """
    if llr_format.overflow_mode != OVERFLOW_SATURATE:
        raise Error("fixed Wi-Fi BCC LLR generation requires saturation")
    if reliability_raw <= 0:
        raise Error("fixed Wi-Fi BCC LLR reliability must be positive")
    var magnitude = narrow_raw(reliability_raw, llr_format)
    if magnitude <= 0:
        raise Error("fixed Wi-Fi BCC LLR format has no positive reliability")
    var result = List[Int64](capacity=len(coded_bits))
    for index in range(len(coded_bits)):
        if coded_bits[index] > 1:
            raise Error("fixed Wi-Fi BCC hard decisions must be binary")
        result.append(magnitude if coded_bits[index] == 0 else -magnitude)
    return result^


@always_inline
def _saturating_metric_add(
    lhs: Int64, rhs: Int64, metric_max: Int64
) -> Tuple[Int64, Bool]:
    debug_assert(lhs >= 0 and rhs >= 0, "path metrics must be non-negative")
    if rhs > metric_max - lhs:
        return (metric_max, True)
    return (lhs + rhs, False)


def _fixed_wifi_bcc_decode_penalties(
    penalty_zero: Span[Int64, ...],
    penalty_one: Span[Int64, ...],
    metric_storage_bits: Int,
    metric_fraction_bits: Int,
    initial_saturation_count: Int,
    terminate: Bool,
) raises -> FixedWifiBCCDecodeResult:
    if len(penalty_zero) != len(penalty_one) or len(penalty_zero) % 2 != 0:
        raise Error("fixed Wi-Fi BCC penalties must contain rate-1/2 symbols")
    if metric_storage_bits < 2 or metric_storage_bits > 62:
        raise Error("fixed Wi-Fi BCC metric width must be in [2,62]")
    if metric_fraction_bits < 0 or metric_fraction_bits >= metric_storage_bits:
        raise Error("fixed Wi-Fi BCC metric fraction width is invalid")
    var steps = len(penalty_zero) // 2
    if terminate and steps < WIFI_BCC_CONSTRAINT_LENGTH - 1:
        raise Error("terminated fixed Wi-Fi BCC input is shorter than its tail")
    var metric_max = (
        (Int64(1) << Int64(metric_storage_bits - 1)) - 1
    )
    var metrics = List[Int64](length=WIFI_BCC_STATE_COUNT, fill=Int64(0))
    var reachable = List[UInt8](length=WIFI_BCC_STATE_COUNT, fill=UInt8(0))
    reachable[0] = UInt8(1)
    var predecessors = List[Int](
        length=steps * WIFI_BCC_STATE_COUNT, fill=-1
    )
    var decisions = List[UInt8](
        length=steps * WIFI_BCC_STATE_COUNT, fill=UInt8(0)
    )
    var normalization_offsets = List[Int64](capacity=steps)
    var saturation_count = initial_saturation_count

    for step in range(steps):
        var next_metrics = List[Int64](
            length=WIFI_BCC_STATE_COUNT, fill=Int64(0)
        )
        var next_reachable = List[UInt8](
            length=WIFI_BCC_STATE_COUNT, fill=UInt8(0)
        )
        var next_predecessors = List[Int](
            length=WIFI_BCC_STATE_COUNT, fill=-1
        )
        var next_decisions = List[UInt8](
            length=WIFI_BCC_STATE_COUNT, fill=UInt8(0)
        )
        for previous in range(WIFI_BCC_STATE_COUNT):
            if reachable[previous] == 0:
                continue
            for input_bit in range(2):
                var register = (previous << 1) | input_bit
                var next_state = register & (WIFI_BCC_STATE_COUNT - 1)
                var expected_a = _wifi_bcc_parity(
                    register & WIFI_BCC_GENERATOR_A
                )
                var expected_b = _wifi_bcc_parity(
                    register & WIFI_BCC_GENERATOR_B
                )
                var branch_a = (
                    penalty_zero[2 * step]
                    if expected_a == 0
                    else penalty_one[2 * step]
                )
                var branch_b = (
                    penalty_zero[2 * step + 1]
                    if expected_b == 0
                    else penalty_one[2 * step + 1]
                )
                var branch, branch_saturated = _saturating_metric_add(
                    branch_a, branch_b, metric_max
                )
                saturation_count += Int(branch_saturated)
                var candidate, path_saturated = _saturating_metric_add(
                    metrics[previous], branch, metric_max
                )
                saturation_count += Int(path_saturated)
                if (
                    next_reachable[next_state] == 0
                    or candidate < next_metrics[next_state]
                    or (
                        candidate == next_metrics[next_state]
                        and previous < next_predecessors[next_state]
                    )
                ):
                    next_reachable[next_state] = UInt8(1)
                    next_metrics[next_state] = candidate
                    next_predecessors[next_state] = previous
                    next_decisions[next_state] = UInt8(input_bit)

        var minimum = metric_max
        var any_reachable = False
        for state in range(WIFI_BCC_STATE_COUNT):
            if next_reachable[state] == 1:
                minimum = min(minimum, next_metrics[state])
                any_reachable = True
        if not any_reachable:
            raise Error("fixed Wi-Fi BCC trellis has no reachable survivor")
        normalization_offsets.append(minimum)
        for state in range(WIFI_BCC_STATE_COUNT):
            if next_reachable[state] == 1:
                next_metrics[state] -= minimum
            predecessors[step * WIFI_BCC_STATE_COUNT + state] = (
                next_predecessors[state]
            )
            decisions[step * WIFI_BCC_STATE_COUNT + state] = (
                next_decisions[state]
            )
        metrics = next_metrics^
        reachable = next_reachable^

    var final_state = 0
    if terminate:
        if reachable[0] == 0:
            raise Error("terminated fixed Wi-Fi BCC zero state is unreachable")
    else:
        var selected = False
        for state in range(WIFI_BCC_STATE_COUNT):
            if reachable[state] == 1 and (
                not selected
                or metrics[state] < metrics[final_state]
                or (
                    metrics[state] == metrics[final_state]
                    and state < final_state
                )
            ):
                final_state = state
                selected = True
        if not selected:
            raise Error("fixed Wi-Fi BCC final state is unreachable")

    var decoded = List[UInt8](length=steps, fill=UInt8(0))
    var traceback_state = final_state
    for reverse_step in range(steps):
        var step = steps - reverse_step - 1
        var checkpoint = step * WIFI_BCC_STATE_COUNT + traceback_state
        var previous = predecessors[checkpoint]
        if previous < 0:
            raise Error("fixed Wi-Fi BCC traceback is unreachable")
        decoded[step] = decisions[checkpoint]
        traceback_state = previous
    if traceback_state != 0:
        raise Error("fixed Wi-Fi BCC traceback did not reach the initial state")

    var payload_length = (
        steps - (WIFI_BCC_CONSTRAINT_LENGTH - 1 if terminate else 0)
    )
    var payload = List[UInt8](capacity=payload_length)
    for index in range(payload_length):
        payload.append(decoded[index])
    var final_reachable = reachable.copy()
    var final_metrics = metrics.copy()
    return FixedWifiBCCDecodeResult(
        payload^,
        predecessors^,
        decisions^,
        final_metrics^,
        final_reachable^,
        normalization_offsets^,
        final_state,
        metrics[final_state],
        saturation_count,
        steps,
        terminate,
        metric_storage_bits,
        metric_fraction_bits,
    )


def fixed_wifi_bcc_viterbi_decode_hard(
    coded_bits: Span[UInt8, ...],
    *,
    terminate: Bool = True,
    metric_storage_bits: Int = 16,
) raises -> FixedWifiBCCDecodeResult:
    """Decode hard rate-1/2 symbols with integer Hamming branch metrics."""
    var penalty_zero = List[Int64](capacity=len(coded_bits))
    var penalty_one = List[Int64](capacity=len(coded_bits))
    for index in range(len(coded_bits)):
        if coded_bits[index] > 1:
            raise Error("fixed Wi-Fi BCC hard input must be binary")
        penalty_zero.append(Int64(coded_bits[index]))
        penalty_one.append(Int64(1 - coded_bits[index]))
    return _fixed_wifi_bcc_decode_penalties(
        Span(penalty_zero),
        Span(penalty_one),
        metric_storage_bits,
        0,
        0,
        terminate,
    )


def fixed_wifi_bcc_viterbi_decode_soft(
    llrs_raw: Span[Int64, ...],
    config: FixedWifiBCCViterbiConfig,
    *,
    terminate: Bool = True,
) raises -> FixedWifiBCCDecodeResult:
    """Decode quantized LLRs using saturating integer max-log penalties."""
    var metric_max = config.metric_max_raw()
    var penalty_zero = List[Int64](capacity=len(llrs_raw))
    var penalty_one = List[Int64](capacity=len(llrs_raw))
    var saturation_count = 0
    for index in range(len(llrs_raw)):
        var llr = llrs_raw[index]
        require_raw_fits(llr, config.llr_format)
        var zero_cost = Int64(0)
        var one_cost = Int64(0)
        if llr < 0:
            var magnitude = -llr
            if magnitude > metric_max:
                magnitude = metric_max
                saturation_count += 1
            zero_cost = magnitude
        elif llr > 0:
            var magnitude = llr
            if magnitude > metric_max:
                magnitude = metric_max
                saturation_count += 1
            one_cost = magnitude
        penalty_zero.append(zero_cost)
        penalty_one.append(one_cost)
    return _fixed_wifi_bcc_decode_penalties(
        Span(penalty_zero),
        Span(penalty_one),
        config.metric_storage_bits,
        config.llr_format.fraction_bits,
        saturation_count,
        terminate,
    )


def _append_u8_as_raw(mut output: List[Int64], values: Span[UInt8, ...]):
    output.append(Int64(len(values)))
    for index in range(len(values)):
        output.append(Int64(values[index]))


def _append_int_as_raw(mut output: List[Int64], values: Span[Int, ...]):
    output.append(Int64(len(values)))
    for index in range(len(values)):
        output.append(Int64(values[index]))


def _append_i64_as_raw(mut output: List[Int64], values: Span[Int64, ...]):
    output.append(Int64(len(values)))
    for index in range(len(values)):
        output.append(values[index])


def fixed_wifi_bcc_result_checksum(
    payload: Span[UInt8, ...],
    coded_bits: Span[UInt8, ...],
    llrs_raw: Span[Int64, ...],
    llr_format: QFormat,
    hard: FixedWifiBCCDecodeResult,
    soft: FixedWifiBCCDecodeResult,
) raises -> UInt64:
    """Checksum the numeric contract and every exported BCC checkpoint."""
    var packed: List[Int64] = [
        Int64(1),
        Int64(WIFI_BCC_CONSTRAINT_LENGTH),
        Int64(WIFI_BCC_GENERATOR_A),
        Int64(WIFI_BCC_GENERATOR_B),
        Int64(WIFI_BCC_RATE_NUMERATOR),
        Int64(WIFI_BCC_RATE_DENOMINATOR),
        Int64(WIFI_BCC_TIE_LOWER_PREDECESSOR),
        Int64(llr_format.storage_bits),
        Int64(llr_format.fraction_bits),
        Int64(llr_format.rounding_mode),
        Int64(llr_format.overflow_mode),
        Int64(hard.metric_storage_bits),
        Int64(hard.metric_fraction_bits),
        Int64(soft.metric_storage_bits),
        Int64(soft.metric_fraction_bits),
        Int64(hard.steps),
        Int64(soft.steps),
        Int64(hard.terminated),
        Int64(soft.terminated),
    ]
    _append_u8_as_raw(packed, payload)
    _append_u8_as_raw(packed, coded_bits)
    _append_i64_as_raw(packed, llrs_raw)
    _append_u8_as_raw(packed, Span(hard.bits))
    _append_int_as_raw(packed, Span(hard.survivor_predecessors))
    _append_u8_as_raw(packed, Span(hard.survivor_decisions))
    _append_i64_as_raw(packed, Span(hard.final_metrics_raw))
    _append_u8_as_raw(packed, Span(hard.final_reachable))
    _append_i64_as_raw(packed, Span(hard.normalization_offsets_raw))
    packed.append(Int64(hard.final_state))
    packed.append(hard.final_normalized_metric_raw)
    packed.append(Int64(hard.saturation_count))
    _append_u8_as_raw(packed, Span(soft.bits))
    _append_int_as_raw(packed, Span(soft.survivor_predecessors))
    _append_u8_as_raw(packed, Span(soft.survivor_decisions))
    _append_i64_as_raw(packed, Span(soft.final_metrics_raw))
    _append_u8_as_raw(packed, Span(soft.final_reachable))
    _append_i64_as_raw(packed, Span(soft.normalization_offsets_raw))
    packed.append(Int64(soft.final_state))
    packed.append(soft.final_normalized_metric_raw)
    packed.append(Int64(soft.saturation_count))
    return fixed_raw_checksum(Span(packed))


def _u8_raw(values: Span[UInt8, ...]) -> List[Int64]:
    var result = List[Int64](capacity=len(values))
    for index in range(len(values)):
        result.append(Int64(values[index]))
    return result^


def _int_raw(values: Span[Int, ...]) -> List[Int64]:
    var result = List[Int64](capacity=len(values))
    for index in range(len(values)):
        result.append(Int64(values[index]))
    return result^


def fixed_wifi_bcc_canonical_rtl_vectors(
    payload: Span[UInt8, ...],
    coded_bits: Span[UInt8, ...],
    llrs_raw: Span[Int64, ...],
    llr_format: QFormat,
    hard: FixedWifiBCCDecodeResult,
    soft: FixedWifiBCCDecodeResult,
) raises -> String:
    """Serialize BCC inputs, survivor memories, metrics, and decoded outputs."""
    if len(coded_bits) != len(llrs_raw) or len(coded_bits) % 2 != 0:
        raise Error("fixed Wi-Fi BCC canonical inputs are inconsistent")
    if llr_format.overflow_mode != OVERFLOW_SATURATE:
        raise Error("fixed Wi-Fi BCC canonical LLR format must saturate")
    if hard.steps != len(coded_bits) // 2 or soft.steps != hard.steps:
        raise Error("fixed Wi-Fi BCC canonical trellis lengths are inconsistent")
    if hard.terminated != soft.terminated:
        raise Error("fixed Wi-Fi BCC canonical termination modes are inconsistent")
    var tail_steps = (
        WIFI_BCC_CONSTRAINT_LENGTH - 1 if hard.terminated else 0
    )
    if (
        len(payload) + tail_steps != hard.steps
        or len(hard.bits) != len(payload)
        or len(soft.bits) != len(payload)
    ):
        raise Error("fixed Wi-Fi BCC canonical payload lengths are inconsistent")
    if hard.metric_fraction_bits != 0:
        raise Error("fixed Wi-Fi BCC hard metric must have zero fraction bits")
    if soft.metric_fraction_bits != llr_format.fraction_bits:
        raise Error("fixed Wi-Fi BCC soft metric binary point is inconsistent")
    var bit_format = QFormat(2, 0)
    var state_format = QFormat(8, 0)
    var hard_metric_format = QFormat(hard.metric_storage_bits, 0)
    var soft_metric_format = QFormat(
        soft.metric_storage_bits, llr_format.fraction_bits
    )
    var payload_raw = _u8_raw(payload)
    var coded_raw = _u8_raw(coded_bits)
    var hard_decoded_raw = _u8_raw(Span(hard.bits))
    var soft_decoded_raw = _u8_raw(Span(soft.bits))
    var hard_predecessors = _int_raw(Span(hard.survivor_predecessors))
    var soft_predecessors = _int_raw(Span(soft.survivor_predecessors))
    var hard_decisions = _u8_raw(Span(hard.survivor_decisions))
    var soft_decisions = _u8_raw(Span(soft.survivor_decisions))
    var hard_reachable = _u8_raw(Span(hard.final_reachable))
    var soft_reachable = _u8_raw(Span(soft.final_reachable))

    var text = String()
    text.write(
        "MWDSP-WIFI-BCC-K7-R12-V1\n",
        "constraint_length=7\n",
        "generators_octal=133,171\n",
        "coded_order=A0,B0,A1,B1\n",
        "initial_state=0\n",
        "tail_zero_bits=", tail_steps, "\n",
        "llr_positive_bit=0\n",
        "llr_storage_bits=", llr_format.storage_bits, "\n",
        "llr_fraction_bits=", llr_format.fraction_bits, "\n",
        "llr_rounding_mode=", llr_format.rounding_mode, "\n",
        "llr_overflow=saturate\n",
        "hard_branch_metric=hamming\n",
        "soft_branch_metric=max-log\n",
        "metric_update=saturate-then-normalize\n",
        "survivor_tie=lower-predecessor\n",
        "final_tie=lower-state\n",
        "checksum_algorithm=fnv1a64-int64-little-endian\n",
        "hard_metric_storage_bits=", hard.metric_storage_bits, "\n",
        "hard_metric_fraction_bits=", hard.metric_fraction_bits, "\n",
        "soft_metric_storage_bits=", soft.metric_storage_bits, "\n",
        "soft_metric_fraction_bits=", soft.metric_fraction_bits, "\n",
        "terminated=", hard.terminated, "\n",
        "hard_final_state=", hard.final_state, "\n",
        "hard_final_normalized_metric_raw=",
        hard.final_normalized_metric_raw,
        "\n",
        "soft_final_state=", soft.final_state, "\n",
        "soft_final_normalized_metric_raw=",
        soft.final_normalized_metric_raw,
        "\n",
        "hard_saturation_count=", hard.saturation_count, "\n",
        "soft_saturation_count=", soft.saturation_count, "\n",
    )
    text.write(
        serialize_fixed_vector(
            "wifi-bcc-k7-r12", "payload-bits", Span(payload_raw), bit_format
        )
    )
    text.write(
        serialize_fixed_vector(
            "wifi-bcc-k7-r12", "coded-bits", Span(coded_raw), bit_format
        )
    )
    text.write(
        serialize_fixed_vector(
            "wifi-bcc-k7-r12", "quantized-llrs", llrs_raw, llr_format
        )
    )
    text.write(
        serialize_fixed_vector(
            "wifi-bcc-k7-r12",
            "hard-survivor-predecessors",
            Span(hard_predecessors),
            state_format,
        )
    )
    text.write(
        serialize_fixed_vector(
            "wifi-bcc-k7-r12",
            "hard-survivor-decisions",
            Span(hard_decisions),
            bit_format,
        )
    )
    text.write(
        serialize_fixed_vector(
            "wifi-bcc-k7-r12",
            "hard-final-metrics",
            Span(hard.final_metrics_raw),
            hard_metric_format,
        )
    )
    text.write(
        serialize_fixed_vector(
            "wifi-bcc-k7-r12",
            "hard-final-reachable",
            Span(hard_reachable),
            bit_format,
        )
    )
    text.write(
        serialize_fixed_vector(
            "wifi-bcc-k7-r12",
            "hard-metric-normalization",
            Span(hard.normalization_offsets_raw),
            hard_metric_format,
        )
    )
    text.write(
        serialize_fixed_vector(
            "wifi-bcc-k7-r12",
            "hard-decoded-bits",
            Span(hard_decoded_raw),
            bit_format,
        )
    )
    text.write(
        serialize_fixed_vector(
            "wifi-bcc-k7-r12",
            "soft-survivor-predecessors",
            Span(soft_predecessors),
            state_format,
        )
    )
    text.write(
        serialize_fixed_vector(
            "wifi-bcc-k7-r12",
            "soft-survivor-decisions",
            Span(soft_decisions),
            bit_format,
        )
    )
    text.write(
        serialize_fixed_vector(
            "wifi-bcc-k7-r12",
            "soft-final-metrics",
            Span(soft.final_metrics_raw),
            soft_metric_format,
        )
    )
    text.write(
        serialize_fixed_vector(
            "wifi-bcc-k7-r12",
            "soft-final-reachable",
            Span(soft_reachable),
            bit_format,
        )
    )
    text.write(
        serialize_fixed_vector(
            "wifi-bcc-k7-r12",
            "soft-metric-normalization",
            Span(soft.normalization_offsets_raw),
            soft_metric_format,
        )
    )
    text.write(
        serialize_fixed_vector(
            "wifi-bcc-k7-r12",
            "soft-decoded-bits",
            Span(soft_decoded_raw),
            bit_format,
        )
    )
    text.write(
        "MWDSP-WIFI-BCC-CHECKSUM-V1\nchecksum=",
        fixed_wifi_bcc_result_checksum(
            payload, coded_bits, llrs_raw, llr_format, hard, soft
        ),
        "\n",
    )
    return text^
