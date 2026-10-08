"""Per-public-API fixed-point LDPC latency benchmarks.

Every kernel-ledger API has a direct ``@no_inline`` workload and an
independent timing distribution.  All graphs, lists, spans, configurations,
and NR rate-recovery fixtures are built before warmup or timing.  Timed
regions contain only the target call; complete owned results are retained and
fingerprinted in O(1) after the timer stops.
"""

from std.benchmark import keep
from std.collections import Span
from std.time import global_perf_counter_ns
from wireless_dsp.benchmarking import (
    print_benchmark_metadata,
    report_timing_samples,
)
from wireless_dsp.backend.fixed_ldpc_reference import (
    FIXED_LDPC_FLOODING,
    FIXED_LDPC_LAYERED,
    FixedLDPCConfig,
    FixedLDPCDecodeResult,
    FixedNRLDPCRateRecoveryResult,
    FixedNRLDPCDecodeResult,
    fixed_ldpc_default_config,
    fixed_ldpc_decode_min_sum_raw,
    fixed_nr_ldpc_rate_recover_raw,
    fixed_nr_ldpc_decode_raw,
)
from wireless_dsp.wireless.nr import nr_ldpc_encode, nr_ldpc_rate_match


comptime _WARMUPS = 3
comptime _SAMPLES = 9
comptime _BASE_GRAPH = 2
comptime _LIFTING_SIZE = 2
comptime _INFORMATION_BITS = 20
comptime _OUTPUT_BITS = 200
comptime _FNV_OFFSET = UInt64(14695981039346656037)
comptime _FNV_PRIME = UInt64(1099511628211)


def _mix(checksum: UInt64, value: Int) -> UInt64:
    return (checksum ^ UInt64(value + 8192)) * _FNV_PRIME


def _mix_u64(checksum: UInt64, value: UInt64) -> UInt64:
    return (checksum ^ value) * _FNV_PRIME


def _require_repeat(first: UInt64, second: UInt64) raises:
    if first != second:
        raise Error("fixed LDPC fixed-input workload is nondeterministic")
    keep(first)
    keep(second)


def _config_fingerprint(config: FixedLDPCConfig) -> UInt64:
    var checksum = _mix(_FNV_OFFSET, config.max_iterations)
    checksum = _mix(checksum, config.schedule)
    checksum = _mix(checksum, Int(config.normalization_raw))
    checksum = _mix(checksum, Int(config.offset_raw))
    return _mix(checksum, Int(config.clip_raw))


def _decode_fingerprint(
    bits: Span[UInt8, ...],
    iterations: Int,
    syndrome_weight: Int,
    saturation_count: Int,
    schedule: Int,
) -> UInt64:
    var checksum = _mix(_FNV_OFFSET, len(bits))
    checksum = _mix(checksum, Int(bits[0]))
    checksum = _mix(checksum, Int(bits[len(bits) - 1]))
    checksum = _mix(checksum, iterations)
    checksum = _mix(checksum, syndrome_weight)
    checksum = _mix(checksum, saturation_count)
    return _mix(checksum, schedule)


def _rate_recovery_fingerprint(
    llrs_raw: Span[Int64, ...], saturation_count: Int,
) -> UInt64:
    var checksum = _mix(_FNV_OFFSET, len(llrs_raw))
    checksum = _mix(checksum, Int(llrs_raw[0]))
    checksum = _mix(checksum, Int(llrs_raw[len(llrs_raw) - 1]))
    return _mix(checksum, saturation_count)


def _nr_decode_fingerprint(
    bits: Span[UInt8, ...],
    full_bits: Span[UInt8, ...],
    iterations: Int,
    syndrome_weight: Int,
    saturation_count: Int,
) -> UInt64:
    var checksum = _mix(_FNV_OFFSET, len(bits))
    checksum = _mix(checksum, Int(bits[0]))
    checksum = _mix(checksum, Int(bits[len(bits) - 1]))
    checksum = _mix(checksum, len(full_bits))
    checksum = _mix(checksum, Int(full_bits[0]))
    checksum = _mix(checksum, Int(full_bits[len(full_bits) - 1]))
    checksum = _mix(checksum, iterations)
    checksum = _mix(checksum, syndrome_weight)
    return _mix(checksum, saturation_count)


# These four names are retained because the kernel ledger names them as the
# evidence entry points.  Each is now the direct workload for exactly one API.
@no_inline
def _workload(max_iterations: Int, schedule: Int) raises -> FixedLDPCConfig:
    return fixed_ldpc_default_config(
        max_iterations=max_iterations, schedule=schedule
    )


@no_inline
def _benchmark(
    channel_llrs: Span[Int64, ...],
    row_offsets: Span[Int, ...],
    columns: Span[Int, ...],
    config: FixedLDPCConfig,
) raises -> FixedLDPCDecodeResult:
    return fixed_ldpc_decode_min_sum_raw(
        channel_llrs, row_offsets, columns, config
    )


@no_inline
def benchmark_nr_rate_recovery(
    received_raw: Span[Int64, ...],
    null_mask: Span[UInt8, ...],
    config: FixedLDPCConfig,
) raises -> FixedNRLDPCRateRecoveryResult:
    return fixed_nr_ldpc_rate_recover_raw(
        received_raw,
        null_mask,
        _BASE_GRAPH,
        _LIFTING_SIZE,
        1,
        2,
        config.llr_format,
        Int64(3200),
    )


@no_inline
def benchmark_nr_decode(
    recovered_raw: Span[Int64, ...],
    null_mask: Span[UInt8, ...],
    config: FixedLDPCConfig,
) raises -> FixedNRLDPCDecodeResult:
    return fixed_nr_ldpc_decode_raw(
        recovered_raw,
        null_mask,
        _BASE_GRAPH,
        _LIFTING_SIZE,
        config,
    )


def _fixed_input_checksum(
    channel_llrs: Span[Int64, ...],
    row_offsets: Span[Int, ...],
    columns: Span[Int, ...],
    received_raw: Span[Int64, ...],
    null_mask: Span[UInt8, ...],
    recovered_raw: Span[Int64, ...],
    flooding_config: FixedLDPCConfig,
    layered_config: FixedLDPCConfig,
    nr_config: FixedLDPCConfig,
) raises -> UInt64:
    var checksum = _FNV_OFFSET

    var configured = _workload(20, FIXED_LDPC_LAYERED)
    checksum = _mix_u64(checksum, _config_fingerprint(configured))
    keep(configured)

    var flooding = _benchmark(
        channel_llrs, row_offsets, columns, flooding_config
    )
    checksum = _mix_u64(checksum, _decode_fingerprint(
        Span(flooding.bits),
        flooding.iterations,
        flooding.syndrome_weight,
        flooding.saturation_count,
        flooding.schedule,
    ))
    keep(flooding)

    var layered = _benchmark(
        channel_llrs, row_offsets, columns, layered_config
    )
    checksum = _mix_u64(checksum, _decode_fingerprint(
        Span(layered.bits),
        layered.iterations,
        layered.syndrome_weight,
        layered.saturation_count,
        layered.schedule,
    ))
    keep(layered)

    var recovered = benchmark_nr_rate_recovery(
        received_raw, null_mask, nr_config
    )
    checksum = _mix_u64(checksum, _rate_recovery_fingerprint(
        Span(recovered.llrs_raw), recovered.saturation_count
    ))
    keep(recovered)

    var decoded = benchmark_nr_decode(recovered_raw, null_mask, nr_config)
    checksum = _mix_u64(checksum, _nr_decode_fingerprint(
        Span(decoded.bits),
        Span(decoded.full_bits),
        decoded.iterations,
        decoded.syndrome_weight,
        decoded.saturation_count,
    ))
    keep(decoded)
    return checksum


def main() raises:
    # Generic sparse-graph decoder fixtures.
    var row_offsets: List[Int] = [0, 3, 6, 9, 12]
    var columns: List[Int] = [
        0, 1, 3, 1, 2, 4, 2, 3, 5, 0, 4, 5,
    ]
    var channel_llrs: List[Int64] = [384, -24, 384, 384, -16, 384]
    var row_offsets_span = Span(row_offsets)
    var columns_span = Span(columns)
    var channel_llrs_span = Span(channel_llrs)
    var flooding_config = _workload(20, FIXED_LDPC_FLOODING)
    var layered_config = _workload(20, FIXED_LDPC_LAYERED)

    # NR fixtures, including all variable-length construction, are outside
    # every timed region.
    var information = List[UInt8](capacity=_INFORMATION_BITS)
    for index in range(_INFORMATION_BITS):
        information.append(UInt8((index * 5 + index // 3) & 1))
    var information_span = Span(information)
    var encoded = nr_ldpc_encode(
        information_span, _BASE_GRAPH, _LIFTING_SIZE
    )
    var encoded_span = Span(encoded)
    var null_mask = List[UInt8](length=len(encoded), fill=UInt8(0))
    var null_mask_span = Span(null_mask)
    var matched = nr_ldpc_rate_match(
        encoded_span,
        null_mask_span,
        _BASE_GRAPH,
        _LIFTING_SIZE,
        1,
        _OUTPUT_BITS,
        2,
    )
    var received = List[Int64](capacity=len(matched))
    for bit in matched:
        received.append(Int64(640 if bit == 0 else -640))
    var received_span = Span(received)
    var nr_config = _workload(30, FIXED_LDPC_LAYERED)
    var recovered_fixture = benchmark_nr_rate_recovery(
        received_span, null_mask_span, nr_config
    )
    var recovered_span = Span(recovered_fixture.llrs_raw)

    var first_checksum = _fixed_input_checksum(
        channel_llrs_span,
        row_offsets_span,
        columns_span,
        received_span,
        null_mask_span,
        recovered_span,
        flooding_config,
        layered_config,
        nr_config,
    )
    var second_checksum = _fixed_input_checksum(
        channel_llrs_span,
        row_offsets_span,
        columns_span,
        received_span,
        null_mask_span,
        recovered_span,
        flooding_config,
        layered_config,
        nr_config,
    )
    _require_repeat(first_checksum, second_checksum)

    for _ in range(_WARMUPS):
        keep(_workload(20, FIXED_LDPC_LAYERED))
        keep(_benchmark(
            channel_llrs_span,
            row_offsets_span,
            columns_span,
            flooding_config,
        ))
        keep(_benchmark(
            channel_llrs_span,
            row_offsets_span,
            columns_span,
            layered_config,
        ))
        keep(benchmark_nr_rate_recovery(
            received_span, null_mask_span, nr_config
        ))
        keep(benchmark_nr_decode(
            recovered_span, null_mask_span, nr_config
        ))

    var config_samples = List[UInt64](capacity=_SAMPLES)
    var flooding_samples = List[UInt64](capacity=_SAMPLES)
    var layered_samples = List[UInt64](capacity=_SAMPLES)
    var rate_recovery_samples = List[UInt64](capacity=_SAMPLES)
    var nr_decode_samples = List[UInt64](capacity=_SAMPLES)
    var checksum = first_checksum

    for _ in range(_SAMPLES):
        var start = global_perf_counter_ns()
        var configured = _workload(20, FIXED_LDPC_LAYERED)
        config_samples.append(global_perf_counter_ns() - start)
        checksum = _mix_u64(checksum, _config_fingerprint(configured))
        keep(configured)

        start = global_perf_counter_ns()
        var flooding = _benchmark(
            channel_llrs_span,
            row_offsets_span,
            columns_span,
            flooding_config,
        )
        flooding_samples.append(global_perf_counter_ns() - start)
        checksum = _mix_u64(checksum, _decode_fingerprint(
            Span(flooding.bits),
            flooding.iterations,
            flooding.syndrome_weight,
            flooding.saturation_count,
            flooding.schedule,
        ))
        keep(flooding)

        start = global_perf_counter_ns()
        var layered = _benchmark(
            channel_llrs_span,
            row_offsets_span,
            columns_span,
            layered_config,
        )
        layered_samples.append(global_perf_counter_ns() - start)
        checksum = _mix_u64(checksum, _decode_fingerprint(
            Span(layered.bits),
            layered.iterations,
            layered.syndrome_weight,
            layered.saturation_count,
            layered.schedule,
        ))
        keep(layered)

        start = global_perf_counter_ns()
        var recovered = benchmark_nr_rate_recovery(
            received_span, null_mask_span, nr_config
        )
        rate_recovery_samples.append(global_perf_counter_ns() - start)
        checksum = _mix_u64(checksum, _rate_recovery_fingerprint(
            Span(recovered.llrs_raw), recovered.saturation_count
        ))
        keep(recovered)

        start = global_perf_counter_ns()
        var decoded = benchmark_nr_decode(
            recovered_span, null_mask_span, nr_config
        )
        nr_decode_samples.append(global_perf_counter_ns() - start)
        checksum = _mix_u64(checksum, _nr_decode_fingerprint(
            Span(decoded.bits),
            Span(decoded.full_bits),
            decoded.iterations,
            decoded.syndrome_weight,
            decoded.saturation_count,
        ))
        keep(decoded)

    print_benchmark_metadata()
    print("fixed_ldpc_message_format:", "Q10.6-nearest-away-saturate")
    print("fixed_ldpc_timing_scope:", "target-call-only")
    report_timing_samples(
        "fixed_ldpc_default_config",
        config_samples,
        _WARMUPS,
        1,
        "config_construction",
    )
    report_timing_samples(
        "fixed_ldpc_decode_min_sum_raw_flooding",
        flooding_samples,
        _WARMUPS,
        1,
        "codeword_decode",
    )
    report_timing_samples(
        "fixed_ldpc_decode_min_sum_raw_layered",
        layered_samples,
        _WARMUPS,
        1,
        "codeword_decode",
    )
    report_timing_samples(
        "fixed_nr_ldpc_rate_recover_raw",
        rate_recovery_samples,
        _WARMUPS,
        1,
        "rate_recovery",
    )
    report_timing_samples(
        "fixed_nr_ldpc_decode_raw",
        nr_decode_samples,
        _WARMUPS,
        1,
        "codeword_decode",
    )
    keep(recovered_fixture)
    keep(checksum)
    print("fixed_ldpc_retained_checksum:", checksum)
