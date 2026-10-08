"""One attributable CPU timing for every ledger-backed FEC public API.

Fixtures and Span views are prepared before each no-inline timed entry.  A
timed entry invokes exactly one target API, stops the timer, retains the full
owned result, and then computes an O(1) result fingerprint.  Every fixed input
is replayed twice before three warmups and nine reported samples.
"""

from std.benchmark import keep
from std.collections import Span
from std.time import global_perf_counter_ns
from wireless_dsp.benchmarking import (
    print_benchmark_metadata,
    report_timing_samples,
)
from wireless_dsp.fec import (
    check_node_min_sum,
    check_node_normalized_min_sum,
    check_node_offset_min_sum,
    variable_node_sum,
    syndrome_ok,
    cyclic_shift,
    ldpc_decode_min_sum,
    ldpc_decode_layered_min_sum,
    convolutional_encode,
    viterbi_decode_hard,
    viterbi_decode_soft,
    puncture_bits,
    depuncture_llrs,
    polar_transform,
    polar_encode,
    polar_decode_sc,
    nr_small_block_basis_bit,
    nr_small_block_encode,
    nr_small_block_rate_match,
    nr_small_block_rate_recover_llrs,
    nr_small_block_decode_ml,
    polar_5g_parity_construction,
    polar_5g_mother_code_length,
    polar_5g_reliability_sequence,
    polar_5g_frozen_mask,
    polar_5g_input_interleave,
    polar_5g_input_deinterleave,
    polar_5g_subblock_interleave,
    polar_5g_subblock_deinterleave_llrs,
    polar_5g_rate_match,
    polar_5g_rate_recover_llrs,
    polar_5g_encode,
    polar_5g_decode_sc,
    polar_5g_encode_with_parity,
    polar_5g_decode_sc_with_parity,
)


comptime _WARMUPS = 3
comptime _SAMPLES = 9


def _mix(checksum: UInt64, value: UInt64) -> UInt64:
    return (checksum ^ value) * UInt64(1099511628211)


def _require_repeat(first: UInt64, second: UInt64) raises:
    if first != second:
        raise Error("fixed FEC benchmark result is nondeterministic")
    keep(first)
    keep(second)


def _fingerprint_float(value: Float64) -> UInt64:
    var magnitude = UInt64(Int(abs(value) * 1_000_000.0))
    return _mix(magnitude, UInt64(1 if value < 0.0 else 0))


def _fingerprint_uint8(values: List[UInt8]) -> UInt64:
    var fingerprint = UInt64(len(values))
    if len(values) > 0:
        fingerprint = _mix(fingerprint, UInt64(values[0]))
        fingerprint = _mix(
            fingerprint, UInt64(values[len(values) - 1])
        )
    return fingerprint


def _fingerprint_float64(values: List[Float64]) -> UInt64:
    var fingerprint = UInt64(len(values))
    if len(values) > 0:
        fingerprint = _mix(fingerprint, _fingerprint_float(values[0]))
        fingerprint = _mix(
            fingerprint, _fingerprint_float(values[len(values) - 1])
        )
    return fingerprint


def _fingerprint_int(values: List[Int]) -> UInt64:
    var fingerprint = UInt64(len(values))
    if len(values) > 0:
        fingerprint = _mix(fingerprint, UInt64(values[0]))
        fingerprint = _mix(
            fingerprint, UInt64(values[len(values) - 1])
        )
    return fingerprint


def _finish_sample(
    name: StringSlice,
    mut samples: List[UInt64],
    checksum: UInt64,
) raises -> UInt64:
    report_timing_samples(name, samples, _WARMUPS, 1, "api_call")
    keep(samples)
    return checksum


def _bits(length: Int, salt: Int) -> List[UInt8]:
    var result = List[UInt8](capacity=length)
    for index in range(length):
        result.append(UInt8(((13 * index + index // 3 + salt) >> 1) & 1))
    return result^


def _llrs(bits: Span[UInt8, ...], magnitude: Float64) -> List[Float64]:
    var result = List[Float64](capacity=len(bits))
    for index in range(len(bits)):
        result.append(magnitude if bits[index] == 0 else -magnitude)
    return result^


@no_inline
def _bench_check_node_min_sum(
    incoming: Span[Float64, ...]
) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = check_node_min_sum(incoming)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _fingerprint_float64(result)
    return (elapsed, fingerprint)


def _run_check_node_min_sum() raises -> UInt64:
    var incoming: List[Float64] = [-2.0, 3.0, -4.0, 5.0]
    var incoming_span = Span(incoming)
    var first = _bench_check_node_min_sum(incoming_span)
    var second = _bench_check_node_min_sum(incoming_span)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_check_node_min_sum(incoming_span))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_check_node_min_sum(incoming_span)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("check_node_min_sum", samples, checksum)


@no_inline
def _bench_check_node_normalized_min_sum(
    incoming: Span[Float64, ...]
) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = check_node_normalized_min_sum(incoming, 0.75)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _fingerprint_float64(result)
    return (elapsed, fingerprint)


def _run_check_node_normalized_min_sum() raises -> UInt64:
    var incoming: List[Float64] = [-2.0, 3.0, -4.0, 5.0]
    var incoming_span = Span(incoming)
    var first = _bench_check_node_normalized_min_sum(incoming_span)
    var second = _bench_check_node_normalized_min_sum(incoming_span)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_check_node_normalized_min_sum(incoming_span))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_check_node_normalized_min_sum(incoming_span)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample(
        "check_node_normalized_min_sum", samples, checksum
    )


@no_inline
def _bench_check_node_offset_min_sum(
    incoming: Span[Float64, ...]
) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = check_node_offset_min_sum(incoming, 0.5)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _fingerprint_float64(result)
    return (elapsed, fingerprint)


def _run_check_node_offset_min_sum() raises -> UInt64:
    var incoming: List[Float64] = [-2.0, 3.0, -4.0, 5.0]
    var incoming_span = Span(incoming)
    var first = _bench_check_node_offset_min_sum(incoming_span)
    var second = _bench_check_node_offset_min_sum(incoming_span)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_check_node_offset_min_sum(incoming_span))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_check_node_offset_min_sum(incoming_span)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("check_node_offset_min_sum", samples, checksum)


@no_inline
def _bench_variable_node_sum(
    incoming: Span[Float64, ...]
) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = variable_node_sum(1.25, incoming, 20.0)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _fingerprint_float(result)
    return (elapsed, fingerprint)


def _run_variable_node_sum() raises -> UInt64:
    var incoming: List[Float64] = [-2.0, 3.0, -4.0, 5.0]
    var incoming_span = Span(incoming)
    var first = _bench_variable_node_sum(incoming_span)
    var second = _bench_variable_node_sum(incoming_span)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_variable_node_sum(incoming_span))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_variable_node_sum(incoming_span)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("variable_node_sum", samples, checksum)


@no_inline
def _bench_syndrome_ok(
    bits: Span[UInt8, ...],
    row_offsets: Span[Int, ...],
    columns: Span[Int, ...],
) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = syndrome_ok(bits, row_offsets, columns)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = UInt64(1 if result else 0)
    return (elapsed, fingerprint)


def _run_syndrome_ok() raises -> UInt64:
    var bits: List[UInt8] = [0, 0, 0]
    var row_offsets: List[Int] = [0, 2, 4]
    var columns: List[Int] = [0, 1, 1, 2]
    var bits_span = Span(bits)
    var row_offsets_span = Span(row_offsets)
    var columns_span = Span(columns)
    var first = _bench_syndrome_ok(
        bits_span, row_offsets_span, columns_span
    )
    var second = _bench_syndrome_ok(
        bits_span, row_offsets_span, columns_span
    )
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_syndrome_ok(bits_span, row_offsets_span, columns_span))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_syndrome_ok(
            bits_span, row_offsets_span, columns_span
        )
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("syndrome_ok", samples, checksum)


@no_inline
def _bench_cyclic_shift(
    incoming: Span[Float64, ...]
) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = cyclic_shift(incoming, 11)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _fingerprint_float64(result)
    return (elapsed, fingerprint)


def _run_cyclic_shift() raises -> UInt64:
    var incoming: List[Float64] = [-2.0, 3.0, -4.0, 5.0]
    var incoming_span = Span(incoming)
    var first = _bench_cyclic_shift(incoming_span)
    var second = _bench_cyclic_shift(incoming_span)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_cyclic_shift(incoming_span))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_cyclic_shift(incoming_span)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("cyclic_shift", samples, checksum)


@no_inline
def _bench_ldpc_decode_min_sum(
    channel_llrs: Span[Float64, ...],
    row_offsets: Span[Int, ...],
    columns: Span[Int, ...],
) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = ldpc_decode_min_sum(
        channel_llrs,
        row_offsets,
        columns,
        max_iterations=8,
        normalization=0.8,
    )
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _fingerprint_uint8(result.bits)
    fingerprint = _mix(fingerprint, UInt64(result.iterations))
    fingerprint = _mix(fingerprint, UInt64(1 if result.converged else 0))
    return (elapsed, fingerprint)


def _run_ldpc_decode_min_sum() raises -> UInt64:
    var channel_llrs: List[Float64] = [6.0, -0.25, 6.0]
    var row_offsets: List[Int] = [0, 2, 4]
    var columns: List[Int] = [0, 1, 1, 2]
    var channel_span = Span(channel_llrs)
    var row_offsets_span = Span(row_offsets)
    var columns_span = Span(columns)
    var first = _bench_ldpc_decode_min_sum(
        channel_span, row_offsets_span, columns_span
    )
    var second = _bench_ldpc_decode_min_sum(
        channel_span, row_offsets_span, columns_span
    )
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_ldpc_decode_min_sum(
            channel_span, row_offsets_span, columns_span
        ))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_ldpc_decode_min_sum(
            channel_span, row_offsets_span, columns_span
        )
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("ldpc_decode_min_sum", samples, checksum)


@no_inline
def _bench_ldpc_decode_layered_min_sum(
    channel_llrs: Span[Float64, ...],
    row_offsets: Span[Int, ...],
    columns: Span[Int, ...],
) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = ldpc_decode_layered_min_sum(
        channel_llrs,
        row_offsets,
        columns,
        max_iterations=8,
        normalization=0.8,
    )
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _fingerprint_uint8(result.bits)
    fingerprint = _mix(fingerprint, UInt64(result.iterations))
    fingerprint = _mix(fingerprint, UInt64(1 if result.converged else 0))
    return (elapsed, fingerprint)


def _run_ldpc_decode_layered_min_sum() raises -> UInt64:
    var channel_llrs: List[Float64] = [6.0, -0.25, 6.0]
    var row_offsets: List[Int] = [0, 2, 4]
    var columns: List[Int] = [0, 1, 1, 2]
    var channel_span = Span(channel_llrs)
    var row_offsets_span = Span(row_offsets)
    var columns_span = Span(columns)
    var first = _bench_ldpc_decode_layered_min_sum(
        channel_span, row_offsets_span, columns_span
    )
    var second = _bench_ldpc_decode_layered_min_sum(
        channel_span, row_offsets_span, columns_span
    )
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_ldpc_decode_layered_min_sum(
            channel_span, row_offsets_span, columns_span
        ))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_ldpc_decode_layered_min_sum(
            channel_span, row_offsets_span, columns_span
        )
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample(
        "ldpc_decode_layered_min_sum", samples, checksum
    )


@no_inline
def _bench_convolutional_encode(
    payload: Span[UInt8, ...], generators: Span[Int, ...]
) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = convolutional_encode(payload, generators, 7)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _fingerprint_uint8(result)
    return (elapsed, fingerprint)


def _run_convolutional_encode() raises -> UInt64:
    var payload = _bits(48, 5)
    var generators: List[Int] = [0o133, 0o171]
    var payload_span = Span(payload)
    var generators_span = Span(generators)
    var first = _bench_convolutional_encode(
        payload_span, generators_span
    )
    var second = _bench_convolutional_encode(
        payload_span, generators_span
    )
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_convolutional_encode(payload_span, generators_span))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_convolutional_encode(
            payload_span, generators_span
        )
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("convolutional_encode", samples, checksum)


@no_inline
def _bench_viterbi_decode_hard(
    encoded: Span[UInt8, ...], generators: Span[Int, ...]
) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = viterbi_decode_hard(encoded, generators, 7)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _fingerprint_uint8(result)
    return (elapsed, fingerprint)


def _run_viterbi_decode_hard() raises -> UInt64:
    var payload = _bits(48, 5)
    var generators: List[Int] = [0o133, 0o171]
    var encoded = convolutional_encode(Span(payload), Span(generators), 7)
    var encoded_span = Span(encoded)
    var generators_span = Span(generators)
    var first = _bench_viterbi_decode_hard(
        encoded_span, generators_span
    )
    var second = _bench_viterbi_decode_hard(
        encoded_span, generators_span
    )
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_viterbi_decode_hard(encoded_span, generators_span))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_viterbi_decode_hard(
            encoded_span, generators_span
        )
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("viterbi_decode_hard", samples, checksum)


@no_inline
def _bench_viterbi_decode_soft(
    llrs: Span[Float64, ...], generators: Span[Int, ...]
) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = viterbi_decode_soft(llrs, generators, 7)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _fingerprint_uint8(result)
    return (elapsed, fingerprint)


def _run_viterbi_decode_soft() raises -> UInt64:
    var payload = _bits(48, 5)
    var generators: List[Int] = [0o133, 0o171]
    var encoded = convolutional_encode(Span(payload), Span(generators), 7)
    var llrs = _llrs(Span(encoded), 8.0)
    var llrs_span = Span(llrs)
    var generators_span = Span(generators)
    var first = _bench_viterbi_decode_soft(llrs_span, generators_span)
    var second = _bench_viterbi_decode_soft(llrs_span, generators_span)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_viterbi_decode_soft(llrs_span, generators_span))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_viterbi_decode_soft(
            llrs_span, generators_span
        )
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("viterbi_decode_soft", samples, checksum)


@no_inline
def _bench_puncture_bits(
    encoded: Span[UInt8, ...], pattern: Span[UInt8, ...]
) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = puncture_bits(encoded, pattern)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _fingerprint_uint8(result)
    return (elapsed, fingerprint)


def _run_puncture_bits() raises -> UInt64:
    var encoded = _bits(108, 7)
    var pattern: List[UInt8] = [1, 1, 1, 0, 0, 1]
    var encoded_span = Span(encoded)
    var pattern_span = Span(pattern)
    var first = _bench_puncture_bits(encoded_span, pattern_span)
    var second = _bench_puncture_bits(encoded_span, pattern_span)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_puncture_bits(encoded_span, pattern_span))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_puncture_bits(encoded_span, pattern_span)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("puncture_bits", samples, checksum)


@no_inline
def _bench_depuncture_llrs(
    llrs: Span[Float64, ...], pattern: Span[UInt8, ...]
) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = depuncture_llrs(llrs, pattern, 24)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _fingerprint_float64(result)
    return (elapsed, fingerprint)


def _run_depuncture_llrs() raises -> UInt64:
    var llrs = List[Float64](capacity=16)
    for index in range(16):
        llrs.append(8.0 if (index & 1) == 0 else -8.0)
    var pattern: List[UInt8] = [1, 1, 1, 0, 0, 1]
    var llrs_span = Span(llrs)
    var pattern_span = Span(pattern)
    var first = _bench_depuncture_llrs(llrs_span, pattern_span)
    var second = _bench_depuncture_llrs(llrs_span, pattern_span)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_depuncture_llrs(llrs_span, pattern_span))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_depuncture_llrs(llrs_span, pattern_span)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("depuncture_llrs", samples, checksum)


@no_inline
def _bench_polar_transform(
    mut values: List[UInt8]
) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    polar_transform(values)
    var elapsed = global_perf_counter_ns() - start
    keep(values)
    var fingerprint = _fingerprint_uint8(values)
    return (elapsed, fingerprint)


def _run_polar_transform() raises -> UInt64:
    var seed = _bits(32, 3)
    var first_values = seed.copy()
    var first = _bench_polar_transform(first_values)
    var second_values = seed.copy()
    var second = _bench_polar_transform(second_values)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        var warmup_values = seed.copy()
        keep(_bench_polar_transform(warmup_values))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample_values = seed.copy()
        var sample = _bench_polar_transform(sample_values)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("polar_transform", samples, checksum)


@no_inline
def _bench_polar_encode(
    information: Span[UInt8, ...], frozen: Span[UInt8, ...]
) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = polar_encode(information, frozen)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _fingerprint_uint8(result)
    return (elapsed, fingerprint)


def _run_polar_encode() raises -> UInt64:
    var frozen = List[UInt8](length=32, fill=UInt8(1))
    for index in range(24, 32):
        frozen[index] = 0
    var information: List[UInt8] = [1, 0, 1, 1, 0, 0, 1, 0]
    var information_span = Span(information)
    var frozen_span = Span(frozen)
    var first = _bench_polar_encode(information_span, frozen_span)
    var second = _bench_polar_encode(information_span, frozen_span)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_polar_encode(information_span, frozen_span))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_polar_encode(information_span, frozen_span)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("polar_encode", samples, checksum)


@no_inline
def _bench_polar_decode_sc(
    llrs: Span[Float64, ...], frozen: Span[UInt8, ...]
) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = polar_decode_sc(llrs, frozen)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _fingerprint_uint8(result)
    return (elapsed, fingerprint)


def _run_polar_decode_sc() raises -> UInt64:
    var frozen = List[UInt8](length=32, fill=UInt8(1))
    for index in range(24, 32):
        frozen[index] = 0
    var information: List[UInt8] = [1, 0, 1, 1, 0, 0, 1, 0]
    var coded = polar_encode(Span(information), Span(frozen))
    var llrs = _llrs(Span(coded), 24.0)
    var llrs_span = Span(llrs)
    var frozen_span = Span(frozen)
    var first = _bench_polar_decode_sc(llrs_span, frozen_span)
    var second = _bench_polar_decode_sc(llrs_span, frozen_span)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_polar_decode_sc(llrs_span, frozen_span))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_polar_decode_sc(llrs_span, frozen_span)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("polar_decode_sc", samples, checksum)


@no_inline
def _bench_nr_small_block_basis_bit() raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_small_block_basis_bit(17, 2)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = UInt64(result)
    return (elapsed, fingerprint)


def _run_nr_small_block_basis_bit() raises -> UInt64:
    var first = _bench_nr_small_block_basis_bit()
    var second = _bench_nr_small_block_basis_bit()
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_small_block_basis_bit())
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_small_block_basis_bit()
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_small_block_basis_bit", samples, checksum)


@no_inline
def _bench_nr_small_block_encode(
    information: Span[UInt8, ...]
) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_small_block_encode(information)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _fingerprint_uint8(result)
    return (elapsed, fingerprint)


def _run_nr_small_block_encode() raises -> UInt64:
    var information: List[UInt8] = [1, 0, 1]
    var information_span = Span(information)
    var first = _bench_nr_small_block_encode(information_span)
    var second = _bench_nr_small_block_encode(information_span)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_small_block_encode(information_span))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_small_block_encode(information_span)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_small_block_encode", samples, checksum)


@no_inline
def _bench_nr_small_block_rate_match(
    codeword: Span[UInt8, ...]
) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_small_block_rate_match(codeword, 48)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _fingerprint_uint8(result)
    return (elapsed, fingerprint)


def _run_nr_small_block_rate_match() raises -> UInt64:
    var information: List[UInt8] = [1, 0, 1]
    var codeword = nr_small_block_encode(Span(information))
    var codeword_span = Span(codeword)
    var first = _bench_nr_small_block_rate_match(codeword_span)
    var second = _bench_nr_small_block_rate_match(codeword_span)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_small_block_rate_match(codeword_span))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_small_block_rate_match(codeword_span)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_small_block_rate_match", samples, checksum)


@no_inline
def _bench_nr_small_block_rate_recover_llrs(
    llrs: Span[Float64, ...]
) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_small_block_rate_recover_llrs(llrs)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _fingerprint_float64(result)
    return (elapsed, fingerprint)


def _run_nr_small_block_rate_recover_llrs() raises -> UInt64:
    var information: List[UInt8] = [1, 0, 1]
    var codeword = nr_small_block_encode(Span(information))
    var matched = nr_small_block_rate_match(Span(codeword), 48)
    var llrs = _llrs(Span(matched), 7.0)
    var llrs_span = Span(llrs)
    var first = _bench_nr_small_block_rate_recover_llrs(llrs_span)
    var second = _bench_nr_small_block_rate_recover_llrs(llrs_span)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_small_block_rate_recover_llrs(llrs_span))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_small_block_rate_recover_llrs(llrs_span)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample(
        "nr_small_block_rate_recover_llrs", samples, checksum
    )


@no_inline
def _bench_nr_small_block_decode_ml(
    llrs: Span[Float64, ...]
) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_small_block_decode_ml(llrs, 3)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _fingerprint_uint8(result.bits)
    fingerprint = _mix(fingerprint, _fingerprint_float(result.metric))
    fingerprint = _mix(fingerprint, _fingerprint_float(result.margin))
    return (elapsed, fingerprint)


def _run_nr_small_block_decode_ml() raises -> UInt64:
    var information: List[UInt8] = [1, 0, 1]
    var codeword = nr_small_block_encode(Span(information))
    var matched = nr_small_block_rate_match(Span(codeword), 48)
    var llrs = _llrs(Span(matched), 7.0)
    var llrs_span = Span(llrs)
    var first = _bench_nr_small_block_decode_ml(llrs_span)
    var second = _bench_nr_small_block_decode_ml(llrs_span)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_small_block_decode_ml(llrs_span))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_small_block_decode_ml(llrs_span)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_small_block_decode_ml", samples, checksum)


@no_inline
def _bench_polar_5g_mother_code_length() raises -> Tuple[UInt64, UInt64]:
    var k = 56
    var e = 864
    var n_max = 9
    var start = global_perf_counter_ns()
    var result = polar_5g_mother_code_length(k, e, n_max=n_max)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, UInt64(result))


def _run_polar_5g_mother_code_length() raises -> UInt64:
    var first = _bench_polar_5g_mother_code_length()
    var second = _bench_polar_5g_mother_code_length()
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_polar_5g_mother_code_length())
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_polar_5g_mother_code_length()
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample(
        "polar_5g_mother_code_length", samples, checksum
    )


@no_inline
def _bench_polar_5g_reliability_sequence() raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = polar_5g_reliability_sequence()
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, _fingerprint_int(result))


def _run_polar_5g_reliability_sequence() raises -> UInt64:
    var first = _bench_polar_5g_reliability_sequence()
    var second = _bench_polar_5g_reliability_sequence()
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_polar_5g_reliability_sequence())
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_polar_5g_reliability_sequence()
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample(
        "polar_5g_reliability_sequence", samples, checksum
    )


@no_inline
def _bench_polar_5g_parity_construction() raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = polar_5g_parity_construction(3, 32, n_pc=1)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _fingerprint_uint8(result.frozen)
    fingerprint = _mix(
        fingerprint, _fingerprint_uint8(result.parity_check)
    )
    fingerprint = _mix(fingerprint, UInt64(result.exponent))
    return (elapsed, fingerprint)


def _run_polar_5g_parity_construction() raises -> UInt64:
    var first = _bench_polar_5g_parity_construction()
    var second = _bench_polar_5g_parity_construction()
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_polar_5g_parity_construction())
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_polar_5g_parity_construction()
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample(
        "polar_5g_parity_construction", samples, checksum
    )


@no_inline
def _bench_polar_5g_frozen_mask() raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = polar_5g_frozen_mask(3, 32)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _fingerprint_uint8(result)
    return (elapsed, fingerprint)


def _run_polar_5g_frozen_mask() raises -> UInt64:
    var first = _bench_polar_5g_frozen_mask()
    var second = _bench_polar_5g_frozen_mask()
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_polar_5g_frozen_mask())
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_polar_5g_frozen_mask()
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("polar_5g_frozen_mask", samples, checksum)


@no_inline
def _bench_polar_5g_input_interleave(
    bits: Span[UInt8, ...]
) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = polar_5g_input_interleave(bits)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _fingerprint_uint8(result)
    return (elapsed, fingerprint)


def _run_polar_5g_input_interleave() raises -> UInt64:
    var bits = _bits(32, 1)
    var bits_span = Span(bits)
    var first = _bench_polar_5g_input_interleave(bits_span)
    var second = _bench_polar_5g_input_interleave(bits_span)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_polar_5g_input_interleave(bits_span))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_polar_5g_input_interleave(bits_span)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("polar_5g_input_interleave", samples, checksum)


@no_inline
def _bench_polar_5g_input_deinterleave(
    bits: Span[UInt8, ...]
) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = polar_5g_input_deinterleave(bits)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _fingerprint_uint8(result)
    return (elapsed, fingerprint)


def _run_polar_5g_input_deinterleave() raises -> UInt64:
    var original = _bits(32, 1)
    var bits = polar_5g_input_interleave(Span(original))
    var bits_span = Span(bits)
    var first = _bench_polar_5g_input_deinterleave(bits_span)
    var second = _bench_polar_5g_input_deinterleave(bits_span)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_polar_5g_input_deinterleave(bits_span))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_polar_5g_input_deinterleave(bits_span)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample(
        "polar_5g_input_deinterleave", samples, checksum
    )


@no_inline
def _bench_polar_5g_subblock_interleave(
    bits: Span[UInt8, ...]
) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = polar_5g_subblock_interleave(bits)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _fingerprint_uint8(result)
    return (elapsed, fingerprint)


def _run_polar_5g_subblock_interleave() raises -> UInt64:
    var bits = _bits(32, 5)
    var bits_span = Span(bits)
    var first = _bench_polar_5g_subblock_interleave(bits_span)
    var second = _bench_polar_5g_subblock_interleave(bits_span)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_polar_5g_subblock_interleave(bits_span))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_polar_5g_subblock_interleave(bits_span)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample(
        "polar_5g_subblock_interleave", samples, checksum
    )


@no_inline
def _bench_polar_5g_subblock_deinterleave_llrs(
    llrs: Span[Float64, ...]
) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = polar_5g_subblock_deinterleave_llrs(llrs)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _fingerprint_float64(result)
    return (elapsed, fingerprint)


def _run_polar_5g_subblock_deinterleave_llrs() raises -> UInt64:
    var bits = _bits(32, 5)
    var interleaved = polar_5g_subblock_interleave(Span(bits))
    var llrs = _llrs(Span(interleaved), 12.0)
    var llrs_span = Span(llrs)
    var first = _bench_polar_5g_subblock_deinterleave_llrs(llrs_span)
    var second = _bench_polar_5g_subblock_deinterleave_llrs(llrs_span)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_polar_5g_subblock_deinterleave_llrs(llrs_span))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_polar_5g_subblock_deinterleave_llrs(llrs_span)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample(
        "polar_5g_subblock_deinterleave_llrs", samples, checksum
    )


@no_inline
def _bench_polar_5g_rate_match(
    coded: Span[UInt8, ...]
) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = polar_5g_rate_match(coded, 48, 3)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _fingerprint_uint8(result)
    return (elapsed, fingerprint)


def _run_polar_5g_rate_match() raises -> UInt64:
    var coded = _bits(32, 5)
    var coded_span = Span(coded)
    var first = _bench_polar_5g_rate_match(coded_span)
    var second = _bench_polar_5g_rate_match(coded_span)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_polar_5g_rate_match(coded_span))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_polar_5g_rate_match(coded_span)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("polar_5g_rate_match", samples, checksum)


@no_inline
def _bench_polar_5g_rate_recover_llrs(
    llrs: Span[Float64, ...]
) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = polar_5g_rate_recover_llrs(llrs, 32, 3)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _fingerprint_float64(result)
    return (elapsed, fingerprint)


def _run_polar_5g_rate_recover_llrs() raises -> UInt64:
    var coded = _bits(32, 5)
    var matched = polar_5g_rate_match(Span(coded), 48, 3)
    var llrs = _llrs(Span(matched), 16.0)
    var llrs_span = Span(llrs)
    var first = _bench_polar_5g_rate_recover_llrs(llrs_span)
    var second = _bench_polar_5g_rate_recover_llrs(llrs_span)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_polar_5g_rate_recover_llrs(llrs_span))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_polar_5g_rate_recover_llrs(llrs_span)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample(
        "polar_5g_rate_recover_llrs", samples, checksum
    )


@no_inline
def _bench_polar_5g_encode(
    information: Span[UInt8, ...]
) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = polar_5g_encode(information, 32)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _fingerprint_uint8(result)
    return (elapsed, fingerprint)


def _run_polar_5g_encode() raises -> UInt64:
    var information: List[UInt8] = [1, 0, 1]
    var information_span = Span(information)
    var first = _bench_polar_5g_encode(information_span)
    var second = _bench_polar_5g_encode(information_span)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_polar_5g_encode(information_span))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_polar_5g_encode(information_span)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("polar_5g_encode", samples, checksum)


@no_inline
def _bench_polar_5g_decode_sc(
    llrs: Span[Float64, ...]
) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = polar_5g_decode_sc(llrs, 3)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _fingerprint_uint8(result)
    return (elapsed, fingerprint)


def _run_polar_5g_decode_sc() raises -> UInt64:
    var information: List[UInt8] = [1, 0, 1]
    var coded = polar_5g_encode(Span(information), 32)
    var llrs = _llrs(Span(coded), 24.0)
    var llrs_span = Span(llrs)
    var first = _bench_polar_5g_decode_sc(llrs_span)
    var second = _bench_polar_5g_decode_sc(llrs_span)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_polar_5g_decode_sc(llrs_span))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_polar_5g_decode_sc(llrs_span)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("polar_5g_decode_sc", samples, checksum)


@no_inline
def _bench_polar_5g_encode_with_parity(
    information: Span[UInt8, ...]
) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = polar_5g_encode_with_parity(information, 32, n_pc=1)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _fingerprint_uint8(result)
    return (elapsed, fingerprint)


def _run_polar_5g_encode_with_parity() raises -> UInt64:
    var information: List[UInt8] = [1, 0, 1]
    var information_span = Span(information)
    var first = _bench_polar_5g_encode_with_parity(information_span)
    var second = _bench_polar_5g_encode_with_parity(information_span)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_polar_5g_encode_with_parity(information_span))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_polar_5g_encode_with_parity(information_span)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample(
        "polar_5g_encode_with_parity", samples, checksum
    )


@no_inline
def _bench_polar_5g_decode_sc_with_parity(
    llrs: Span[Float64, ...]
) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = polar_5g_decode_sc_with_parity(llrs, 3, n_pc=1)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _fingerprint_uint8(result.bits)
    fingerprint = _mix(fingerprint, UInt64(1 if result.parity_ok else 0))
    return (elapsed, fingerprint)


def _run_polar_5g_decode_sc_with_parity() raises -> UInt64:
    var information: List[UInt8] = [1, 0, 1]
    var coded = polar_5g_encode_with_parity(
        Span(information), 32, n_pc=1
    )
    var llrs = _llrs(Span(coded), 24.0)
    var llrs_span = Span(llrs)
    var first = _bench_polar_5g_decode_sc_with_parity(llrs_span)
    var second = _bench_polar_5g_decode_sc_with_parity(llrs_span)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_polar_5g_decode_sc_with_parity(llrs_span))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_polar_5g_decode_sc_with_parity(llrs_span)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample(
        "polar_5g_decode_sc_with_parity", samples, checksum
    )


# Compatibility entry points retained for Feature references.  They are not
# used for attribution; each delegated runner above has its own timer/report.
def _benchmark_ldpc_once() raises -> UInt64:
    return (
        _run_check_node_min_sum()
        ^ _run_check_node_normalized_min_sum()
        ^ _run_check_node_offset_min_sum()
        ^ _run_variable_node_sum()
        ^ _run_syndrome_ok()
        ^ _run_cyclic_shift()
        ^ _run_ldpc_decode_min_sum()
        ^ _run_ldpc_decode_layered_min_sum()
    )


def _benchmark_convolutional_once() raises -> UInt64:
    return (
        _run_convolutional_encode()
        ^ _run_viterbi_decode_hard()
        ^ _run_viterbi_decode_soft()
        ^ _run_puncture_bits()
        ^ _run_depuncture_llrs()
    )


def _benchmark_polar_once() raises -> UInt64:
    return (
        _run_polar_transform()
        ^ _run_polar_encode()
        ^ _run_polar_decode_sc()
    )


def _benchmark_small_block_once() raises -> UInt64:
    return (
        _run_nr_small_block_basis_bit()
        ^ _run_nr_small_block_encode()
        ^ _run_nr_small_block_rate_match()
        ^ _run_nr_small_block_rate_recover_llrs()
        ^ _run_nr_small_block_decode_ml()
    )


def _benchmark_polar5g_once() raises -> UInt64:
    return (
        _run_polar_5g_mother_code_length()
        ^ _run_polar_5g_reliability_sequence()
        ^ _run_polar_5g_parity_construction()
        ^ _run_polar_5g_frozen_mask()
        ^ _run_polar_5g_input_interleave()
        ^ _run_polar_5g_input_deinterleave()
        ^ _run_polar_5g_subblock_interleave()
        ^ _run_polar_5g_subblock_deinterleave_llrs()
        ^ _run_polar_5g_rate_match()
        ^ _run_polar_5g_rate_recover_llrs()
        ^ _run_polar_5g_encode()
        ^ _run_polar_5g_decode_sc()
        ^ _run_polar_5g_encode_with_parity()
        ^ _run_polar_5g_decode_sc_with_parity()
    )


def main() raises:
    print_benchmark_metadata()
    var checksum = UInt64(1469598103934665603)
    checksum = _mix(checksum, _run_check_node_min_sum())
    checksum = _mix(checksum, _run_check_node_normalized_min_sum())
    checksum = _mix(checksum, _run_check_node_offset_min_sum())
    checksum = _mix(checksum, _run_convolutional_encode())
    checksum = _mix(checksum, _run_cyclic_shift())
    checksum = _mix(checksum, _run_depuncture_llrs())
    checksum = _mix(checksum, _run_ldpc_decode_layered_min_sum())
    checksum = _mix(checksum, _run_ldpc_decode_min_sum())
    checksum = _mix(checksum, _run_nr_small_block_basis_bit())
    checksum = _mix(checksum, _run_nr_small_block_decode_ml())
    checksum = _mix(checksum, _run_nr_small_block_encode())
    checksum = _mix(checksum, _run_nr_small_block_rate_match())
    checksum = _mix(checksum, _run_nr_small_block_rate_recover_llrs())
    checksum = _mix(checksum, _run_polar_5g_decode_sc())
    checksum = _mix(checksum, _run_polar_5g_decode_sc_with_parity())
    checksum = _mix(checksum, _run_polar_5g_encode())
    checksum = _mix(checksum, _run_polar_5g_encode_with_parity())
    checksum = _mix(checksum, _run_polar_5g_frozen_mask())
    checksum = _mix(checksum, _run_polar_5g_input_deinterleave())
    checksum = _mix(checksum, _run_polar_5g_input_interleave())
    checksum = _mix(checksum, _run_polar_5g_mother_code_length())
    checksum = _mix(checksum, _run_polar_5g_parity_construction())
    checksum = _mix(checksum, _run_polar_5g_rate_match())
    checksum = _mix(checksum, _run_polar_5g_rate_recover_llrs())
    checksum = _mix(checksum, _run_polar_5g_reliability_sequence())
    checksum = _mix(checksum, _run_polar_5g_subblock_deinterleave_llrs())
    checksum = _mix(checksum, _run_polar_5g_subblock_interleave())
    checksum = _mix(checksum, _run_polar_decode_sc())
    checksum = _mix(checksum, _run_polar_encode())
    checksum = _mix(checksum, _run_polar_transform())
    checksum = _mix(checksum, _run_puncture_bits())
    checksum = _mix(checksum, _run_syndrome_ok())
    checksum = _mix(checksum, _run_variable_node_sum())
    checksum = _mix(checksum, _run_viterbi_decode_hard())
    checksum = _mix(checksum, _run_viterbi_decode_soft())
    keep(checksum)
    print("fec_evidence_retained_checksum:", checksum)
