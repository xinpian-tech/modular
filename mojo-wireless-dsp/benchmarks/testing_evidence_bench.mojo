"""Retained latency distributions for public testing/link-simulation APIs.

Every workload has untimed warmups followed by independent timed samples.
Median and nearest-rank p95 include the complete public call, while result
checksums are accumulated outside timed regions so optimizers cannot discard
the measured work.
"""

from std.benchmark import keep
from std.collections import Span
from std.memory import bitcast
from std.sys.info import align_of
from std.time import global_perf_counter_ns
from wireless_dsp.benchmarking import (
    print_benchmark_metadata,
    print_runtime_buffer_alignment,
    report_timing_samples,
)
from wireless_dsp.core import Complex64
from wireless_dsp.numerics import ComplexRaw, QFormat, ScaleTrace
from wireless_dsp.testing import (
    CheckpointMetadata,
    LinkResult,
    PacketLinkResult,
    QAMLinkSweepPoint,
    checkpoint_bits_checksum,
    checkpoint_complex_error,
    checkpoint_metadata_1d,
    checkpoint_metadata_2d,
    complex_raw_checksum,
    fixed_raw_checksum,
    serialize_complex_fixed_vector,
    serialize_fixed_vector,
    serialize_scale_trace,
    simulate_nr_pdsch_awgn,
    simulate_qam_awgn,
    simulate_qam_awgn_sweep,
    simulate_wifi_legacy_bpsk_awgn,
)


comptime _WARMUPS = 3
comptime _REPETITIONS = 9


def _mix(checksum: UInt64, value: UInt64) -> UInt64:
    return (checksum ^ value) * UInt64(1099511628211)


def _string_fingerprint(value: String) -> UInt64:
    var result = UInt64(value.byte_length())
    var bytes = StringSlice(value).as_bytes()
    if len(bytes) > 0:
        result = _mix(result, UInt64(UInt8(bytes[0])))
        result = _mix(result, UInt64(UInt8(bytes[len(bytes) - 1])))
    return result


def _metadata_fingerprint(value: CheckpointMetadata) -> UInt64:
    var result = UInt64(value.version)
    result = _mix(result, UInt64(value.shape.byte_length()))
    result = _mix(result, UInt64(value.stride.byte_length()))
    result = _mix(result, UInt64(value.layout.byte_length()))
    return result


def _link_result_fingerprint(value: LinkResult) -> UInt64:
    var result = _mix(UInt64(value.bit_count), UInt64(value.bit_errors))
    return _mix(result, bitcast[DType.uint64](value.ber))


def _packet_link_result_fingerprint(value: PacketLinkResult) -> UInt64:
    var result = _mix(UInt64(value.bit_count), UInt64(value.bit_errors))
    result = _mix(result, UInt64(value.packet_count))
    result = _mix(result, UInt64(value.packet_errors))
    result = _mix(result, bitcast[DType.uint64](value.ber))
    result = _mix(result, bitcast[DType.uint64](value.per))
    result = _mix(result, bitcast[DType.uint64](value.bler))
    result = _mix(result, value.noise_fingerprint)
    return _mix(result, value.discrete_fingerprint)


@no_inline
def _checkpoint_bits_checksum_workload(
    bits: Span[UInt8, ...]
) raises -> UInt64:
    return checkpoint_bits_checksum(bits)


@no_inline
def _checkpoint_metadata_1d_workload() raises -> CheckpointMetadata:
    return checkpoint_metadata_1d(
        "bench", "vector", "sint16", 256,
        scale=0.125,
        element_stride=2,
        q_format="Q7.8",
        version=2,
        layout="strided",
    )


@no_inline
def _checkpoint_metadata_2d_workload() raises -> CheckpointMetadata:
    return checkpoint_metadata_2d(
        "bench", "matrix", "complex-int16", 16, 16,
        row_stride=32,
        column_stride=2,
        scale=0.125,
        q_format="Q7.8",
        version=2,
        layout="row-major-padded",
    )


@no_inline
def _complex_raw_checksum_workload(
    values: Span[ComplexRaw, ...]
) -> UInt64:
    return complex_raw_checksum(values)


@no_inline
def _fixed_raw_checksum_workload(
    values: Span[Int64, ...]
) -> UInt64:
    return fixed_raw_checksum(values)


@no_inline
def _serialize_complex_fixed_vector_workload(
    values: Span[ComplexRaw, ...], qformat: QFormat
) raises -> String:
    return serialize_complex_fixed_vector(
        "bench", "complex", values, qformat
    )


@no_inline
def _serialize_fixed_vector_workload(
    values: Span[Int64, ...], qformat: QFormat
) raises -> String:
    return serialize_fixed_vector("bench", "scalar", values, qformat)


@no_inline
def _serialize_scale_trace_workload(trace: ScaleTrace) raises -> String:
    return serialize_scale_trace("bench", "scale", trace)


def benchmark_checkpoint_bits_checksum() raises -> UInt64:
    comptime elements = 256
    var bits = List[UInt8](capacity=elements)
    for index in range(elements):
        bits.append(UInt8(((17 * index + 5) >> (index % 5)) & 1))
    var bits_span = Span(bits)
    for _ in range(_WARMUPS):
        keep(_checkpoint_bits_checksum_workload(bits_span))
    var samples = List[UInt64](capacity=_REPETITIONS)
    var checksum = UInt64(14695981039346656037)
    for _ in range(_REPETITIONS):
        var start = global_perf_counter_ns()
        var result = _checkpoint_bits_checksum_workload(bits_span)
        samples.append(global_perf_counter_ns() - start)
        keep(result)
        checksum = _mix(checksum, result)
    report_timing_samples(
        "checkpoint_bits_checksum", samples, _WARMUPS, elements,
        "checkpoint_bit",
    )
    keep(bits)
    return checksum


def benchmark_checkpoint_metadata_1d() raises -> UInt64:
    for _ in range(_WARMUPS):
        keep(_checkpoint_metadata_1d_workload())
    var samples = List[UInt64](capacity=_REPETITIONS)
    var checksum = UInt64(14695981039346656037)
    for _ in range(_REPETITIONS):
        var start = global_perf_counter_ns()
        var result = _checkpoint_metadata_1d_workload()
        samples.append(global_perf_counter_ns() - start)
        keep(result)
        checksum = _mix(checksum, _metadata_fingerprint(result))
    report_timing_samples(
        "checkpoint_metadata_1d", samples, _WARMUPS, 1, "api_call"
    )
    return checksum


def benchmark_checkpoint_metadata_2d() raises -> UInt64:
    for _ in range(_WARMUPS):
        keep(_checkpoint_metadata_2d_workload())
    var samples = List[UInt64](capacity=_REPETITIONS)
    var checksum = UInt64(14695981039346656037)
    for _ in range(_REPETITIONS):
        var start = global_perf_counter_ns()
        var result = _checkpoint_metadata_2d_workload()
        samples.append(global_perf_counter_ns() - start)
        keep(result)
        checksum = _mix(checksum, _metadata_fingerprint(result))
    report_timing_samples(
        "checkpoint_metadata_2d", samples, _WARMUPS, 1, "api_call"
    )
    return checksum


def benchmark_complex_raw_checksum() raises -> UInt64:
    comptime elements = 128
    var values = List[ComplexRaw](capacity=elements)
    for index in range(elements):
        values.append(ComplexRaw(Int64(index - 64), Int64(63 - index)))
    var values_span = Span(values)
    for _ in range(_WARMUPS):
        keep(_complex_raw_checksum_workload(values_span))
    var samples = List[UInt64](capacity=_REPETITIONS)
    var checksum = UInt64(14695981039346656037)
    for _ in range(_REPETITIONS):
        var start = global_perf_counter_ns()
        var result = _complex_raw_checksum_workload(values_span)
        samples.append(global_perf_counter_ns() - start)
        keep(result)
        checksum = _mix(checksum, result)
    report_timing_samples(
        "complex_raw_checksum", samples, _WARMUPS, elements,
        "complex_raw_value",
    )
    keep(values)
    return checksum


def benchmark_fixed_raw_checksum() raises -> UInt64:
    comptime elements = 256
    var values = List[Int64](capacity=elements)
    for index in range(elements):
        values.append(Int64(index - 128))
    var values_span = Span(values)
    for _ in range(_WARMUPS):
        keep(_fixed_raw_checksum_workload(values_span))
    var samples = List[UInt64](capacity=_REPETITIONS)
    var checksum = UInt64(14695981039346656037)
    for _ in range(_REPETITIONS):
        var start = global_perf_counter_ns()
        var result = _fixed_raw_checksum_workload(values_span)
        samples.append(global_perf_counter_ns() - start)
        keep(result)
        checksum = _mix(checksum, result)
    report_timing_samples(
        "fixed_raw_checksum", samples, _WARMUPS, elements,
        "fixed_raw_value",
    )
    keep(values)
    return checksum


def benchmark_serialize_complex_fixed_vector() raises -> UInt64:
    comptime elements = 64
    var values = List[ComplexRaw](capacity=elements)
    for index in range(elements):
        values.append(ComplexRaw(Int64(index - 32), Int64(31 - index)))
    var values_span = Span(values)
    var qformat = QFormat(8, 4)
    for _ in range(_WARMUPS):
        keep(_serialize_complex_fixed_vector_workload(values_span, qformat))
    var samples = List[UInt64](capacity=_REPETITIONS)
    var checksum = UInt64(14695981039346656037)
    for _ in range(_REPETITIONS):
        var start = global_perf_counter_ns()
        var result = _serialize_complex_fixed_vector_workload(
            values_span, qformat
        )
        samples.append(global_perf_counter_ns() - start)
        keep(result)
        checksum = _mix(checksum, _string_fingerprint(result))
    report_timing_samples(
        "serialize_complex_fixed_vector", samples, _WARMUPS, elements,
        "complex_raw_value",
    )
    keep(values)
    return checksum


def benchmark_serialize_fixed_vector() raises -> UInt64:
    comptime elements = 128
    var values = List[Int64](capacity=elements)
    for index in range(elements):
        values.append(Int64(index - 64))
    var values_span = Span(values)
    var qformat = QFormat(8, 4)
    for _ in range(_WARMUPS):
        keep(_serialize_fixed_vector_workload(values_span, qformat))
    var samples = List[UInt64](capacity=_REPETITIONS)
    var checksum = UInt64(14695981039346656037)
    for _ in range(_REPETITIONS):
        var start = global_perf_counter_ns()
        var result = _serialize_fixed_vector_workload(values_span, qformat)
        samples.append(global_perf_counter_ns() - start)
        keep(result)
        checksum = _mix(checksum, _string_fingerprint(result))
    report_timing_samples(
        "serialize_fixed_vector", samples, _WARMUPS, elements,
        "fixed_raw_value",
    )
    keep(values)
    return checksum


def benchmark_serialize_scale_trace() raises -> UInt64:
    comptime elements = 64
    var values = List[Int64](capacity=elements)
    var fractions = List[Int](capacity=elements)
    var widths = List[Int](capacity=elements)
    var shifts = List[Int](capacity=elements)
    for index in range(elements):
        values.append(Int64(index - 32))
        fractions.append(4)
        widths.append(8)
        shifts.append(index % 4)
    var trace = ScaleTrace(values^, fractions^, widths^, shifts^)
    for _ in range(_WARMUPS):
        keep(_serialize_scale_trace_workload(trace))
    var samples = List[UInt64](capacity=_REPETITIONS)
    var checksum = UInt64(14695981039346656037)
    for _ in range(_REPETITIONS):
        var start = global_perf_counter_ns()
        var result = _serialize_scale_trace_workload(trace)
        samples.append(global_perf_counter_ns() - start)
        keep(result)
        checksum = _mix(checksum, _string_fingerprint(result))
    report_timing_samples(
        "serialize_scale_trace", samples, _WARMUPS, elements,
        "scale_trace_row",
    )
    keep(trace)
    return checksum


@no_inline
def _checkpoint_complex_error_workload(
    actual: Span[Complex64, ...], expected: Span[Complex64, ...]
) raises -> Tuple[Float64, Float64]:
    return checkpoint_complex_error(actual, expected)


@no_inline
def _simulate_qam_awgn_workload(
    order: Int, symbols: Int, noise: Float64, seed: UInt64
) raises -> LinkResult:
    return simulate_qam_awgn(order, symbols, noise, seed=seed)


@no_inline
def _simulate_qam_awgn_sweep_workload(
    orders: Span[Int, ...],
    noises: Span[Float64, ...],
    seeds: Span[UInt64, ...],
    symbols_per_point: Int,
) raises -> List[QAMLinkSweepPoint]:
    return simulate_qam_awgn_sweep(orders, noises, seeds, symbols_per_point)


@no_inline
def _simulate_wifi_legacy_bpsk_awgn_workload(
    packets: Int, noise: Float64, seed: UInt64
) raises -> PacketLinkResult:
    return simulate_wifi_legacy_bpsk_awgn(packets, noise, seed=seed)


@no_inline
def _simulate_nr_pdsch_awgn_workload(
    packets: Int, noise: Float64, seed: UInt64
) raises -> PacketLinkResult:
    return simulate_nr_pdsch_awgn(packets, noise, seed=seed)


def benchmark_checkpoint_complex_error() raises -> UInt64:
    comptime elements = 256
    var expected = List[Complex64](capacity=elements)
    var actual = List[Complex64](capacity=elements)
    for index in range(elements):
        var real = Float64((17 * index + 3) % 101) / 50.0 - 1.0
        var imaginary = Float64((29 * index + 5) % 97) / 48.0 - 1.0
        expected.append(Complex64(real, imaginary))
        actual.append(Complex64(
            real + 1.0e-7 * Float64(index % 7 - 3),
            imaginary - 1.0e-7 * Float64(index % 5 - 2),
        ))
    var actual_span = Span(actual)
    var expected_span = Span(expected)

    for _ in range(_WARMUPS):
        keep(_checkpoint_complex_error_workload(actual_span, expected_span))

    var samples = List[UInt64](capacity=_REPETITIONS)
    var checksum = UInt64(14695981039346656037)
    for repetition in range(_REPETITIONS):
        var start = global_perf_counter_ns()
        var evm, maximum = _checkpoint_complex_error_workload(
            actual_span, expected_span
        )
        samples.append(global_perf_counter_ns() - start)
        keep(evm); keep(maximum)
        checksum ^= UInt64(evm * 1.0e15)
        checksum *= UInt64(1099511628211)
        checksum ^= UInt64(maximum * 1.0e15) + UInt64(repetition)
        checksum *= UInt64(1099511628211)

    report_timing_samples(
        "testing_checkpoint_complex_error", samples, _WARMUPS, elements,
        "complex_comparison_element",
    )
    print("testing_checkpoint_complex_error_checksum:", checksum)
    return checksum


def benchmark_simulate_qam_awgn() raises -> UInt64:
    comptime symbols = 512
    comptime order = 8
    comptime seed = UInt64(0x5EED_0001)
    for _ in range(_WARMUPS):
        keep(_simulate_qam_awgn_workload(order, symbols, 0.1, seed))

    var samples = List[UInt64](capacity=_REPETITIONS)
    var checksum = UInt64(14695981039346656037)
    for _ in range(_REPETITIONS):
        var start = global_perf_counter_ns()
        var result = _simulate_qam_awgn_workload(order, symbols, 0.1, seed)
        samples.append(global_perf_counter_ns() - start)
        keep(result)
        checksum = _mix(checksum, _link_result_fingerprint(result))

    report_timing_samples(
        "testing_qam_awgn", samples, _WARMUPS, symbols,
        "simulated_qam_symbol",
    )
    print("testing_qam_awgn_checksum:", checksum)
    return checksum


def benchmark_simulate_qam_awgn_sweep() raises -> UInt64:
    comptime symbols_per_point = 128
    var orders: List[Int] = [1, 4]
    var noises: List[Float64] = [0.05, 0.5]
    var seeds: List[UInt64] = [UInt64(0x1001), UInt64(0x1002)]
    var orders_span = Span(orders)
    var noises_span = Span(noises)
    var seeds_span = Span(seeds)
    comptime point_count = 8
    for _ in range(_WARMUPS):
        keep(_simulate_qam_awgn_sweep_workload(
            orders_span, noises_span, seeds_span, symbols_per_point
        ))

    var samples = List[UInt64](capacity=_REPETITIONS)
    var checksum = UInt64(14695981039346656037)
    for _ in range(_REPETITIONS):
        var start = global_perf_counter_ns()
        var points = _simulate_qam_awgn_sweep_workload(
            orders_span, noises_span, seeds_span, symbols_per_point
        )
        samples.append(global_perf_counter_ns() - start)
        keep(points)
        checksum = _mix(checksum, UInt64(len(points)))
        checksum = _mix(
            checksum, _link_result_fingerprint(points[0].result)
        )
        checksum = _mix(
            checksum,
            _link_result_fingerprint(points[len(points) - 1].result),
        )

    report_timing_samples(
        "testing_qam_awgn_sweep", samples, _WARMUPS, point_count,
        "simulation_sweep_point",
    )
    print("testing_qam_awgn_sweep_checksum:", checksum)
    return checksum


def benchmark_simulate_wifi_legacy_bpsk_awgn() raises -> UInt64:
    comptime packets = 2
    comptime seed = UInt64(0x80211_0001)
    for _ in range(_WARMUPS):
        keep(_simulate_wifi_legacy_bpsk_awgn_workload(packets, 0.05, seed))

    var samples = List[UInt64](capacity=_REPETITIONS)
    var checksum = UInt64(14695981039346656037)
    for _ in range(_REPETITIONS):
        var start = global_perf_counter_ns()
        var result = _simulate_wifi_legacy_bpsk_awgn_workload(
            packets, 0.05, seed
        )
        samples.append(global_perf_counter_ns() - start)
        keep(result)
        checksum = _mix(
            checksum, _packet_link_result_fingerprint(result)
        )

    report_timing_samples(
        "testing_wifi_legacy_awgn", samples, _WARMUPS, packets,
        "simulated_wifi_packet",
    )
    print("testing_wifi_legacy_awgn_checksum:", checksum)
    return checksum


def benchmark_simulate_nr_pdsch_awgn() raises -> UInt64:
    comptime packets = 1
    comptime seed = UInt64(0x38_212_0001)
    for _ in range(_WARMUPS):
        keep(_simulate_nr_pdsch_awgn_workload(packets, 0.01, seed))

    var samples = List[UInt64](capacity=_REPETITIONS)
    var checksum = UInt64(14695981039346656037)
    for _ in range(_REPETITIONS):
        var start = global_perf_counter_ns()
        var result = _simulate_nr_pdsch_awgn_workload(packets, 0.01, seed)
        samples.append(global_perf_counter_ns() - start)
        keep(result)
        checksum = _mix(
            checksum, _packet_link_result_fingerprint(result)
        )

    report_timing_samples(
        "testing_nr_pdsch_awgn", samples, _WARMUPS, packets,
        "simulated_nr_packet",
    )
    print("testing_nr_pdsch_awgn_checksum:", checksum)
    return checksum


def main() raises:
    print_benchmark_metadata()
    var alignment_probe = List[Complex64](
        length=64, fill=Complex64(0.0, 0.0)
    )
    print_runtime_buffer_alignment(
        "testing_evidence_complex64_probe",
        Int(alignment_probe.unsafe_ptr()),
        align_of[Complex64](),
    )
    var checksum = benchmark_checkpoint_bits_checksum()
    checksum ^= benchmark_checkpoint_metadata_1d()
    checksum ^= benchmark_checkpoint_metadata_2d()
    checksum ^= benchmark_complex_raw_checksum()
    checksum ^= benchmark_fixed_raw_checksum()
    checksum ^= benchmark_serialize_complex_fixed_vector()
    checksum ^= benchmark_serialize_fixed_vector()
    checksum ^= benchmark_serialize_scale_trace()
    checksum ^= benchmark_checkpoint_complex_error()
    checksum ^= benchmark_simulate_qam_awgn()
    checksum ^= benchmark_simulate_qam_awgn_sweep()
    checksum ^= benchmark_simulate_wifi_legacy_bpsk_awgn()
    checksum ^= benchmark_simulate_nr_pdsch_awgn()
    print("testing_evidence_combined_checksum:", checksum)
