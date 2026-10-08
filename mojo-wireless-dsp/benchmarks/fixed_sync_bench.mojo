"""Retained benchmark for fixed repeated-preamble correlation scans."""

from std.collections import Span
from std.benchmark import keep
from std.time import global_perf_counter_ns
from wireless_dsp.benchmarking import (
    print_benchmark_metadata,
    report_timing_samples,
)
from wireless_dsp.numerics.complex_fixed import ComplexRaw
from wireless_dsp.numerics.quantization import QFormat
from wireless_dsp.backend.fixed_sync_reference import (
    FixedRepetitionScanResult,
    fixed_repetition_canonical_rtl_vectors,
    fixed_repetition_scan_checksum,
    fixed_repetition_scan_raw,
)


comptime _WARMUPS = 3
comptime _SAMPLES = 9


@no_inline
def _fixed_repetition_scan_raw_workload(
    samples: Span[ComplexRaw, ...],
    sample_format: QFormat,
    accumulator_format: QFormat,
    output_format: QFormat,
) raises -> FixedRepetitionScanResult:
    return fixed_repetition_scan_raw(
        samples,
        16,
        16,
        sample_format,
        accumulator_format,
        output_format,
    )


@no_inline
def _fixed_repetition_scan_checksum_workload(
    result: FixedRepetitionScanResult,
) -> UInt64:
    return fixed_repetition_scan_checksum(result)


@no_inline
def _fixed_repetition_canonical_rtl_vectors_workload(
    result: FixedRepetitionScanResult, output_format: QFormat,
) raises -> String:
    return fixed_repetition_canonical_rtl_vectors(result, output_format)


def _mix(checksum: UInt64, value: UInt64) -> UInt64:
    return (checksum ^ value) * UInt64(1099511628211)


def _text_checksum(text: StringSlice) -> UInt64:
    var checksum = UInt64(14695981039346656037)
    var bytes = text.as_bytes()
    for index in range(len(bytes)):
        checksum = _mix(checksum, UInt64(UInt8(bytes[index])))
    return checksum


def _text_fingerprint(text: StringSlice) -> UInt64:
    var bytes = text.as_bytes()
    var result = UInt64(len(bytes))
    if len(bytes) > 0:
        result = _mix(result, UInt64(UInt8(bytes[0])))
        result = _mix(result, UInt64(UInt8(bytes[len(bytes) - 1])))
    return result


def main() raises:
    var samples = List[ComplexRaw](capacity=2048)
    var state = UInt64(0x51ACBEEF20260821)
    for _ in range(2048):
        state = state * UInt64(6364136223846793005) + UInt64(1)
        var real = Int64(Int((state >> 52) & UInt64(0xfff)) - 2048)
        state = state * UInt64(6364136223846793005) + UInt64(1)
        var imag = Int64(Int((state >> 52) & UInt64(0xfff)) - 2048)
        samples.append(ComplexRaw(real, imag))
    # Plant an exact 16-sample repetition after the random prefix.
    for index in range(16):
        samples[1024 + 16 + index] = samples[1024 + index]

    var sample_format = QFormat(16, 12)
    var accumulator_format = QFormat(48, 24)
    var output_format = QFormat(30, 18)
    var sample_span = Span(samples)
    var validation = _fixed_repetition_scan_raw_workload(
        sample_span, sample_format, accumulator_format, output_format
    )
    var vectors_first = _fixed_repetition_canonical_rtl_vectors_workload(
        validation, output_format
    )
    var vectors_second = _fixed_repetition_canonical_rtl_vectors_workload(
        validation, output_format
    )
    if (
        _text_checksum(StringSlice(vectors_first))
        != _text_checksum(StringSlice(vectors_second))
    ):
        raise Error("fixed repetition artifact benchmark is nondeterministic")
    keep(vectors_first)
    keep(vectors_second)
    for _ in range(_WARMUPS):
        keep(_fixed_repetition_scan_raw_workload(
            sample_span, sample_format, accumulator_format, output_format
        ))
        keep(_fixed_repetition_scan_checksum_workload(validation))
        keep(_fixed_repetition_canonical_rtl_vectors_workload(
            validation, output_format
        ))

    var timings = List[UInt64](capacity=_SAMPLES)
    var checksum_timings = List[UInt64](capacity=_SAMPLES)
    var vector_timings = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(0)
    var result_checksum = UInt64(0)
    var vector_full_checksum = UInt64(1469598103934665603)
    var vector_fingerprint_checksum = UInt64(1469598103934665603)
    var peak_sum = 0
    for repetition in range(_SAMPLES):
        var start = global_perf_counter_ns()
        var result = _fixed_repetition_scan_raw_workload(
            sample_span, sample_format, accumulator_format, output_format
        )
        timings.append(global_perf_counter_ns() - start)
        keep(result)
        checksum ^= UInt64(
            result.peak_offset + len(result.correlations) + repetition
        )
        peak_sum += result.peak_offset

        start = global_perf_counter_ns()
        var digest = _fixed_repetition_scan_checksum_workload(validation)
        checksum_timings.append(global_perf_counter_ns() - start)
        keep(digest)
        result_checksum ^= digest + UInt64(repetition)

        start = global_perf_counter_ns()
        var vectors = _fixed_repetition_canonical_rtl_vectors_workload(
            validation, output_format
        )
        vector_timings.append(global_perf_counter_ns() - start)
        keep(vectors)
        vector_full_checksum = _mix(
            vector_full_checksum, _text_checksum(StringSlice(vectors))
        )
        vector_fingerprint_checksum = _mix(
            vector_fingerprint_checksum,
            _text_fingerprint(StringSlice(vectors)),
        )
    print_benchmark_metadata()
    print("fixed_sync_samples:", len(samples))
    print("fixed_sync_period_window:", 16, 16)
    report_timing_samples(
        "fixed_repetition_scan_input_sample",
        timings,
        _WARMUPS,
        len(samples),
    )
    report_timing_samples(
        "fixed_repetition_scan_checksum",
        checksum_timings,
        _WARMUPS,
        1,
    )
    report_timing_samples(
        "fixed_repetition_canonical_rtl_vectors",
        vector_timings,
        _WARMUPS,
        1,
    )
    print("fixed_sync_peak_offset_sum:", peak_sum)
    keep(checksum)
    keep(result_checksum)
    keep(vector_full_checksum)
    keep(vector_fingerprint_checksum)
    print("fixed_sync_retained_checksum:", checksum)
    print("fixed_sync_result_checksum:", result_checksum)
    print(
        "fixed_sync_vectors_full_output_checksum:", vector_full_checksum
    )
    print(
        "fixed_sync_vectors_fingerprint_checksum:",
        vector_fingerprint_checksum,
    )
