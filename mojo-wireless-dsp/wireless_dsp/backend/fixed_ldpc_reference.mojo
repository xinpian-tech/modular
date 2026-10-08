"""Bit-exact fixed-point min-sum LDPC golden reference.

The decoder is intentionally graph-generic.  Every message is a signed raw
two's-complement word in one explicit saturating ``QFormat``.  Check updates,
variable updates, clipping, normalization and offset subtraction are all
registered narrowing boundaries, so an RTL implementation can replay the
same operation order.  Both flooding and layered schedules are available.
"""

from std.collections import Span
from wireless_dsp.numerics import (
    QFormat,
    OVERFLOW_SATURATE,
    ROUND_NEAREST_AWAY,
    validate_qformat,
    raw_fits,
    narrow_raw,
    fixed_mul_raw,
    quantize_raw,
)
from wireless_dsp.wireless.nr.ldpc_tables import nr_base_graph_dimensions
from wireless_dsp.wireless.nr.ldpc_profile import nr_standard_qc_graph
from wireless_dsp.wireless.nr.ldpc_codec import nr_ldpc_k0


comptime FIXED_LDPC_FLOODING = 0
comptime FIXED_LDPC_LAYERED = 1


struct FixedLDPCConfig(ImplicitlyCopyable):
    """Complete numeric and scheduling contract for a fixed LDPC decoder."""

    var llr_format: QFormat
    var normalization_format: QFormat
    var normalization_raw: Int64
    var offset_raw: Int64
    var clip_raw: Int64
    var max_iterations: Int
    var schedule: Int

    def __init__(
        out self,
        llr_format: QFormat,
        normalization_format: QFormat,
        normalization_raw: Int64,
        offset_raw: Int64,
        clip_raw: Int64,
        max_iterations: Int,
        schedule: Int = FIXED_LDPC_LAYERED,
    ) raises:
        self.llr_format = validate_qformat(llr_format)
        self.normalization_format = validate_qformat(normalization_format)
        self.normalization_raw = normalization_raw
        self.offset_raw = offset_raw
        self.clip_raw = clip_raw
        self.max_iterations = max_iterations
        self.schedule = schedule
        self.validate()

    def validate(self) raises:
        """Reject a mutated numeric or scheduling contract at API boundaries."""
        var llr_format = validate_qformat(self.llr_format)
        var normalization_format = validate_qformat(
            self.normalization_format
        )
        if llr_format.overflow_mode != OVERFLOW_SATURATE:
            raise Error("fixed LDPC messages require saturating overflow")
        if llr_format.storage_bits > 31:
            raise Error("fixed LDPC message storage is limited to 31 bits")
        if normalization_format.storage_bits > 31:
            raise Error("fixed LDPC normalization storage is limited to 31 bits")
        if not raw_fits(self.normalization_raw, normalization_format):
            raise Error("fixed LDPC normalization exceeds its Q-format")
        if (
            self.normalization_raw <= 0
            or self.normalization_raw > normalization_format.scale()
        ):
            raise Error("fixed LDPC normalization must be in (0, 1]")
        if not raw_fits(self.offset_raw, llr_format) or self.offset_raw < 0:
            raise Error("fixed LDPC offset must be non-negative and representable")
        if not raw_fits(self.clip_raw, llr_format) or self.clip_raw <= 0:
            raise Error("fixed LDPC clip must be positive and representable")
        if self.max_iterations < 1:
            raise Error("fixed LDPC iteration count must be positive")
        if (
            self.schedule != FIXED_LDPC_FLOODING
            and self.schedule != FIXED_LDPC_LAYERED
        ):
            raise Error("fixed LDPC schedule is unsupported")


def fixed_ldpc_default_config(
    *,
    max_iterations: Int = 20,
    schedule: Int = FIXED_LDPC_LAYERED,
    rounding_mode: Int = ROUND_NEAREST_AWAY,
) raises -> FixedLDPCConfig:
    """Return the canonical Q10.6 message/Q1.15 normalization contract."""
    var llr_format = QFormat(16, 6, rounding_mode, OVERFLOW_SATURATE)
    var normalization_format = QFormat(
        16, 15, rounding_mode, OVERFLOW_SATURATE
    )
    return FixedLDPCConfig(
        llr_format,
        normalization_format,
        quantize_raw(0.75, normalization_format),
        Int64(0),
        quantize_raw(50.0, llr_format),
        max_iterations,
        schedule,
    )


struct FixedLDPCDecodeResult(Movable):
    """Decoder output plus raw final state and saturation audit."""

    var bits: List[UInt8]
    var posterior_raw: List[Int64]
    var variable_to_check_raw: List[Int64]
    var check_to_variable_raw: List[Int64]
    var iterations: Int
    var converged: Bool
    var syndrome_weight: Int
    var saturation_count: Int
    var schedule: Int

    def __init__(
        out self,
        var bits: List[UInt8],
        var posterior_raw: List[Int64],
        var variable_to_check_raw: List[Int64],
        var check_to_variable_raw: List[Int64],
        iterations: Int,
        converged: Bool,
        syndrome_weight: Int,
        saturation_count: Int,
        schedule: Int,
    ):
        self.bits = bits^
        self.posterior_raw = posterior_raw^
        self.variable_to_check_raw = variable_to_check_raw^
        self.check_to_variable_raw = check_to_variable_raw^
        self.iterations = iterations
        self.converged = converged
        self.syndrome_weight = syndrome_weight
        self.saturation_count = saturation_count
        self.schedule = schedule


struct FixedNRLDPCRateRecoveryResult(Movable):
    """Raw NR circular-buffer rate recovery and its saturation count."""

    var llrs_raw: List[Int64]
    var saturation_count: Int

    def __init__(
        out self, var llrs_raw: List[Int64], saturation_count: Int
    ):
        self.llrs_raw = llrs_raw^
        self.saturation_count = saturation_count


struct FixedNRLDPCDecodeResult(Movable):
    """NR systematic result with the complete fixed decoder state."""

    var bits: List[UInt8]
    var full_bits: List[UInt8]
    var posterior_raw: List[Int64]
    var variable_to_check_raw: List[Int64]
    var check_to_variable_raw: List[Int64]
    var iterations: Int
    var converged: Bool
    var syndrome_weight: Int
    var saturation_count: Int

    def __init__(
        out self,
        var bits: List[UInt8],
        var full_bits: List[UInt8],
        var posterior_raw: List[Int64],
        var variable_to_check_raw: List[Int64],
        var check_to_variable_raw: List[Int64],
        iterations: Int,
        converged: Bool,
        syndrome_weight: Int,
        saturation_count: Int,
    ):
        self.bits = bits^
        self.full_bits = full_bits^
        self.posterior_raw = posterior_raw^
        self.variable_to_check_raw = variable_to_check_raw^
        self.check_to_variable_raw = check_to_variable_raw^
        self.iterations = iterations
        self.converged = converged
        self.syndrome_weight = syndrome_weight
        self.saturation_count = saturation_count


def _validate_graph(
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
        raise Error("invalid fixed LDPC sparse parity graph")
    for row in range(len(row_offsets) - 1):
        var start = row_offsets[row]
        var end = row_offsets[row + 1]
        if start < 0 or end < start or end > len(columns) or end - start < 2:
            raise Error("fixed LDPC row offsets or degree are invalid")
        for edge in range(start, end):
            var column = columns[edge]
            if column < 0 or column >= variable_count:
                raise Error("fixed LDPC column is out of range")
            for other in range(edge + 1, end):
                if columns[other] == column:
                    raise Error("fixed LDPC row contains a duplicate column")


def _clip_registered(
    value: Int64,
    config: FixedLDPCConfig,
    mut saturation_count: Int,
) raises -> Int64:
    var bounded = min(max(value, -config.clip_raw), config.clip_raw)
    var narrowed = narrow_raw(bounded, config.llr_format)
    if narrowed != value:
        saturation_count += 1
    return narrowed


def _registered_add(
    lhs: Int64,
    rhs: Int64,
    config: FixedLDPCConfig,
    mut saturation_count: Int,
) raises -> Int64:
    return _clip_registered(lhs + rhs, config, saturation_count)


def _registered_sub(
    lhs: Int64,
    rhs: Int64,
    config: FixedLDPCConfig,
    mut saturation_count: Int,
) raises -> Int64:
    return _clip_registered(lhs - rhs, config, saturation_count)


def _magnitude(value: Int64, config: FixedLDPCConfig) -> Int64:
    if value >= 0:
        return value
    if value == config.llr_format.min_raw():
        return config.llr_format.max_raw()
    return -value


def _normalized_offset_magnitude(
    magnitude: Int64,
    config: FixedLDPCConfig,
    mut saturation_count: Int,
) raises -> Int64:
    var normalized = fixed_mul_raw(
        magnitude,
        config.llr_format,
        config.normalization_raw,
        config.normalization_format,
        config.llr_format,
    )
    var offset_value = max(Int64(0), normalized - config.offset_raw)
    return _clip_registered(offset_value, config, saturation_count)


def _syndrome_weight(
    bits: Span[UInt8, ...],
    row_offsets: Span[Int, ...],
    columns: Span[Int, ...],
) -> Int:
    var weight = 0
    for row in range(len(row_offsets) - 1):
        var parity = UInt8(0)
        for edge in range(row_offsets[row], row_offsets[row + 1]):
            parity ^= bits[columns[edge]]
        if parity != 0:
            weight += 1
    return weight


def _hard_decisions(values: Span[Int64, ...]) -> List[UInt8]:
    var bits = List[UInt8](capacity=len(values))
    for index in range(len(values)):
        bits.append(UInt8(0) if values[index] >= 0 else UInt8(1))
    return bits^


def _row_messages(
    inputs: Span[Int64, ...],
    config: FixedLDPCConfig,
    mut saturation_count: Int,
) raises -> List[Int64]:
    var minimum = _magnitude(inputs[0], config)
    var second = _magnitude(inputs[1], config)
    var minimum_index = 0
    if second < minimum:
        var swap = minimum
        minimum = second
        second = swap
        minimum_index = 1
    var all_sign = 1
    for index in range(len(inputs)):
        if inputs[index] < 0:
            all_sign = -all_sign
    for index in range(2, len(inputs)):
        var magnitude = _magnitude(inputs[index], config)
        if magnitude < minimum:
            second = minimum
            minimum = magnitude
            minimum_index = index
        elif magnitude < second:
            second = magnitude
    var result = List[Int64](capacity=len(inputs))
    for index in range(len(inputs)):
        var magnitude = second if index == minimum_index else minimum
        magnitude = _normalized_offset_magnitude(
            magnitude, config, saturation_count
        )
        var sign = -all_sign if inputs[index] < 0 else all_sign
        result.append(magnitude if sign > 0 else -magnitude)
    return result^


def _decode_flooding(
    channel_llrs: Span[Int64, ...],
    row_offsets: Span[Int, ...],
    columns: Span[Int, ...],
    config: FixedLDPCConfig,
) raises -> FixedLDPCDecodeResult:
    var saturation_count = 0
    var variable_to_check = List[Int64](length=len(columns), fill=Int64(0))
    var check_to_variable = List[Int64](length=len(columns), fill=Int64(0))
    for edge in range(len(columns)):
        variable_to_check[edge] = _clip_registered(
            channel_llrs[columns[edge]], config, saturation_count
        )
    var posterior = List[Int64](length=len(channel_llrs), fill=Int64(0))
    var hard = List[UInt8](length=len(channel_llrs), fill=UInt8(0))
    var final_weight = len(row_offsets) - 1
    for iteration in range(config.max_iterations):
        for row in range(len(row_offsets) - 1):
            var start = row_offsets[row]
            var end = row_offsets[row + 1]
            var inputs = List[Int64](capacity=end - start)
            for edge in range(start, end):
                inputs.append(variable_to_check[edge])
            var messages = _row_messages(
                Span(inputs), config, saturation_count
            )
            for local in range(len(messages)):
                check_to_variable[start + local] = messages[local]
        for variable in range(len(channel_llrs)):
            posterior[variable] = _clip_registered(
                channel_llrs[variable], config, saturation_count
            )
        for edge in range(len(columns)):
            var variable = columns[edge]
            posterior[variable] = _registered_add(
                posterior[variable],
                check_to_variable[edge],
                config,
                saturation_count,
            )
        hard = _hard_decisions(Span(posterior))
        final_weight = _syndrome_weight(Span(hard), row_offsets, columns)
        if final_weight == 0:
            return FixedLDPCDecodeResult(
                hard^,
                posterior^,
                variable_to_check^,
                check_to_variable^,
                iteration + 1,
                True,
                0,
                saturation_count,
                config.schedule,
            )
        for edge in range(len(columns)):
            variable_to_check[edge] = _registered_sub(
                posterior[columns[edge]],
                check_to_variable[edge],
                config,
                saturation_count,
            )
    return FixedLDPCDecodeResult(
        hard^,
        posterior^,
        variable_to_check^,
        check_to_variable^,
        config.max_iterations,
        False,
        final_weight,
        saturation_count,
        config.schedule,
    )


def _decode_layered(
    channel_llrs: Span[Int64, ...],
    row_offsets: Span[Int, ...],
    columns: Span[Int, ...],
    config: FixedLDPCConfig,
) raises -> FixedLDPCDecodeResult:
    var saturation_count = 0
    var posterior = List[Int64](capacity=len(channel_llrs))
    for index in range(len(channel_llrs)):
        posterior.append(
            _clip_registered(channel_llrs[index], config, saturation_count)
        )
    var variable_to_check = List[Int64](length=len(columns), fill=Int64(0))
    var check_to_variable = List[Int64](length=len(columns), fill=Int64(0))
    var hard = List[UInt8](length=len(channel_llrs), fill=UInt8(0))
    var final_weight = len(row_offsets) - 1
    for iteration in range(config.max_iterations):
        for row in range(len(row_offsets) - 1):
            var start = row_offsets[row]
            var end = row_offsets[row + 1]
            var extrinsic = List[Int64](capacity=end - start)
            for edge in range(start, end):
                var value = _registered_sub(
                    posterior[columns[edge]],
                    check_to_variable[edge],
                    config,
                    saturation_count,
                )
                extrinsic.append(value)
                variable_to_check[edge] = value
            var messages = _row_messages(
                Span(extrinsic), config, saturation_count
            )
            for local in range(len(messages)):
                var edge = start + local
                check_to_variable[edge] = messages[local]
                posterior[columns[edge]] = _registered_add(
                    extrinsic[local],
                    messages[local],
                    config,
                    saturation_count,
                )
        hard = _hard_decisions(Span(posterior))
        final_weight = _syndrome_weight(Span(hard), row_offsets, columns)
        if final_weight == 0:
            return FixedLDPCDecodeResult(
                hard^,
                posterior^,
                variable_to_check^,
                check_to_variable^,
                iteration + 1,
                True,
                0,
                saturation_count,
                config.schedule,
            )
    return FixedLDPCDecodeResult(
        hard^,
        posterior^,
        variable_to_check^,
        check_to_variable^,
        config.max_iterations,
        False,
        final_weight,
        saturation_count,
        config.schedule,
    )


def fixed_ldpc_decode_min_sum_raw(
    channel_llrs: Span[Int64, ...],
    row_offsets: Span[Int, ...],
    columns: Span[Int, ...],
    config: FixedLDPCConfig,
) raises -> FixedLDPCDecodeResult:
    """Decode a sparse parity graph with registered bit-exact updates."""
    config.validate()
    _validate_graph(len(channel_llrs), row_offsets, columns)
    for index in range(len(channel_llrs)):
        if not raw_fits(channel_llrs[index], config.llr_format):
            raise Error("fixed LDPC channel LLR exceeds its Q-format")
    if config.schedule == FIXED_LDPC_FLOODING:
        return _decode_flooding(channel_llrs, row_offsets, columns, config)
    return _decode_layered(channel_llrs, row_offsets, columns, config)


def fixed_nr_ldpc_rate_recover_raw(
    received_raw: Span[Int64, ...],
    null_mask: Span[UInt8, ...],
    base_graph: Int,
    lifting_size: Int,
    redundancy_version: Int,
    modulation_order: Int,
    llr_format: QFormat,
    filler_raw: Int64,
    circular_buffer_bits: Int = 0,
) raises -> FixedNRLDPCRateRecoveryResult:
    """Bit-exact NR deinterleaving, circular combining, and filler insertion."""
    if llr_format.overflow_mode != OVERFLOW_SATURATE:
        raise Error("fixed NR rate recovery requires saturating overflow")
    if llr_format.storage_bits > 31:
        raise Error("fixed NR rate-recovery LLRs are limited to 31 bits")
    var dimensions = nr_base_graph_dimensions(base_graph)
    var expected = (dimensions[1] - 2) * lifting_size
    if len(null_mask) != expected or modulation_order < 1:
        raise Error("invalid fixed NR rate-recovery configuration")
    if len(received_raw) % modulation_order != 0:
        raise Error("fixed NR rate-recovery input is not symbol aligned")
    if not raw_fits(filler_raw, llr_format) or filler_raw <= 0:
        raise Error("fixed NR filler LLR must be positive and representable")
    for index in range(len(received_raw)):
        if not raw_fits(received_raw[index], llr_format):
            raise Error("fixed NR received LLR exceeds its Q-format")
    for index in range(len(null_mask)):
        if null_mask[index] > 1:
            raise Error("fixed NR null mask must be binary")
    var n_cb = expected if circular_buffer_bits == 0 else circular_buffer_bits
    if n_cb < 1 or n_cb > expected:
        raise Error("invalid fixed NR circular-buffer length")
    var usable = 0
    for index in range(n_cb):
        if null_mask[index] == 0:
            usable += 1
    if len(received_raw) > 0 and usable == 0:
        raise Error("fixed NR circular buffer contains only filler")
    var symbols = len(received_raw) // modulation_order
    var selected = List[Int64](length=len(received_raw), fill=Int64(0))
    for bit_plane in range(modulation_order):
        for symbol in range(symbols):
            selected[bit_plane * symbols + symbol] = received_raw[
                symbol * modulation_order + bit_plane
            ]
    var result = List[Int64](length=expected, fill=Int64(0))
    var position = nr_ldpc_k0(
        base_graph, lifting_size, redundancy_version, n_cb
    )
    var saturation_count = 0
    for selected_index in range(len(selected)):
        var value = selected[selected_index]
        var searched = 0
        while null_mask[position] != 0:
            position = (position + 1) % n_cb
            searched += 1
            if searched >= n_cb:
                raise Error("fixed NR circular buffer contains only filler")
        var sum = result[position] + value
        var narrowed = narrow_raw(sum, llr_format)
        if narrowed != sum:
            saturation_count += 1
        result[position] = narrowed
        position = (position + 1) % n_cb
    for index in range(expected):
        if null_mask[index] != 0:
            result[index] = filler_raw
    return FixedNRLDPCRateRecoveryResult(result^, saturation_count)


def fixed_nr_ldpc_decode_raw(
    recovered_raw: Span[Int64, ...],
    null_mask: Span[UInt8, ...],
    base_graph: Int,
    lifting_size: Int,
    config: FixedLDPCConfig,
) raises -> FixedNRLDPCDecodeResult:
    """Decode one NR BG1/BG2 code block without a floating-point boundary."""
    config.validate()
    var dimensions = nr_base_graph_dimensions(base_graph)
    var expected = (dimensions[1] - 2) * lifting_size
    if len(recovered_raw) != expected or len(null_mask) != expected:
        raise Error("fixed NR LDPC decoder input has invalid length")
    var full_llrs = List[Int64](
        length=dimensions[1] * lifting_size, fill=Int64(0)
    )
    var punctured = 2 * lifting_size
    for index in range(expected):
        if null_mask[index] > 1:
            raise Error("fixed NR LDPC null mask must be binary")
        if not raw_fits(recovered_raw[index], config.llr_format):
            raise Error("fixed NR recovered LLR exceeds its Q-format")
        full_llrs[punctured + index] = (
            config.clip_raw if null_mask[index] != 0 else recovered_raw[index]
        )
    var graph = nr_standard_qc_graph(base_graph, lifting_size)
    var decoded = fixed_ldpc_decode_min_sum_raw(
        Span(full_llrs), Span(graph.row_offsets), Span(graph.columns), config
    )
    var information_length = dimensions[2] * lifting_size
    var information = List[UInt8](capacity=information_length)
    for index in range(information_length):
        information.append(decoded.bits[index])
    var full_bits = decoded.bits.copy()
    var posterior = decoded.posterior_raw.copy()
    var variable_to_check = decoded.variable_to_check_raw.copy()
    var check_to_variable = decoded.check_to_variable_raw.copy()
    return FixedNRLDPCDecodeResult(
        information^,
        full_bits^,
        posterior^,
        variable_to_check^,
        check_to_variable^,
        decoded.iterations,
        decoded.converged,
        decoded.syndrome_weight,
        decoded.saturation_count,
    )
