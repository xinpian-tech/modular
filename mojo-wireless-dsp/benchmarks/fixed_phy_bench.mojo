"""Retained per-frame latency samples for the fixed QPSK mini-PHY."""

from std.collections import Span
from std.benchmark import keep
from std.time import global_perf_counter_ns
from wireless_dsp.benchmarking import (
    print_benchmark_metadata,
    report_timing_samples,
)
from wireless_dsp.numerics.complex_fixed import ComplexRaw
from wireless_dsp.backend.fixed_phy_reference import (
    FixedPHYFormats,
    FixedPHYResult,
    fixed_phy_canonical_rtl_vectors,
    fixed_phy_default_formats,
    fixed_phy_one_symbol_reference,
    fixed_phy_result_checksum,
    fixed_phy_scale_trace_text,
)


comptime _WARMUPS = 3
comptime _SAMPLES = 9


@no_inline
def _fixed_phy_default_formats_workload() raises -> FixedPHYFormats:
    return fixed_phy_default_formats()


@no_inline
def _fixed_phy_one_symbol_reference_workload(
    bits: Span[UInt8, ...],
    channel: ComplexRaw,
    formats: FixedPHYFormats,
) raises -> FixedPHYResult:
    return fixed_phy_one_symbol_reference(
        bits, 64, 16, channel, formats, Int64(8192), 4
    )


@no_inline
def _fixed_phy_result_checksum_workload(result: FixedPHYResult) -> UInt64:
    return fixed_phy_result_checksum(result)


@no_inline
def _fixed_phy_scale_trace_text_workload(
    formats: FixedPHYFormats,
) raises -> String:
    return fixed_phy_scale_trace_text(64, formats, Int64(8192))


@no_inline
def _fixed_phy_canonical_rtl_vectors_workload(
    result: FixedPHYResult, formats: FixedPHYFormats,
) raises -> String:
    return fixed_phy_canonical_rtl_vectors(result, formats)


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
    var formats = _fixed_phy_default_formats_workload()
    var bits = List[UInt8](capacity=128)
    for i in range(128):
        bits.append(UInt8(((i * 29) ^ (i >> 2) ^ 0x5a) & 1))
    var bits_span = Span(bits)
    var channel = ComplexRaw(12288, 4096)
    var validation = _fixed_phy_one_symbol_reference_workload(
        bits_span, channel, formats
    )
    var scale_first = _fixed_phy_scale_trace_text_workload(formats)
    var scale_second = _fixed_phy_scale_trace_text_workload(formats)
    var vectors_first = _fixed_phy_canonical_rtl_vectors_workload(
        validation, formats
    )
    var vectors_second = _fixed_phy_canonical_rtl_vectors_workload(
        validation, formats
    )
    if (
        _text_checksum(StringSlice(scale_first))
        != _text_checksum(StringSlice(scale_second))
        or _text_checksum(StringSlice(vectors_first))
        != _text_checksum(StringSlice(vectors_second))
    ):
        raise Error("fixed PHY artifact benchmark is nondeterministic")
    keep(scale_first)
    keep(scale_second)
    keep(vectors_first)
    keep(vectors_second)

    for _ in range(_WARMUPS):
        keep(_fixed_phy_default_formats_workload())
        keep(_fixed_phy_one_symbol_reference_workload(
            bits_span, channel, formats
        ))
        keep(_fixed_phy_result_checksum_workload(validation))
        keep(_fixed_phy_scale_trace_text_workload(formats))
        keep(_fixed_phy_canonical_rtl_vectors_workload(validation, formats))

    var format_samples = List[UInt64](capacity=_SAMPLES)
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum_samples = List[UInt64](capacity=_SAMPLES)
    var scale_samples = List[UInt64](capacity=_SAMPLES)
    var vector_samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(0)
    var format_checksum = UInt64(0)
    var result_checksum = UInt64(0)
    var scale_full_checksum = UInt64(1469598103934665603)
    var scale_fingerprint_checksum = UInt64(1469598103934665603)
    var vector_full_checksum = UInt64(1469598103934665603)
    var vector_fingerprint_checksum = UInt64(1469598103934665603)
    var bit_errors = 0
    var evm_sum = 0.0
    for repetition in range(_SAMPLES):
        var start = global_perf_counter_ns()
        var measured_formats = _fixed_phy_default_formats_workload()
        format_samples.append(global_perf_counter_ns() - start)
        keep(measured_formats)
        format_checksum ^= UInt64(
            measured_formats.symbol.storage_bits
            + measured_formats.symbol.fraction_bits
            + repetition
        )

        start = global_perf_counter_ns()
        var result = _fixed_phy_one_symbol_reference_workload(
            bits_span, channel, formats
        )
        samples.append(global_perf_counter_ns() - start)
        keep(result)
        checksum ^= UInt64(
            result.transform_size
            + len(result.decoded_bits)
            + result.audit.bit_errors
            + repetition
        )
        bit_errors += result.audit.bit_errors
        evm_sum += result.audit.evm_rms

        start = global_perf_counter_ns()
        var digest = _fixed_phy_result_checksum_workload(validation)
        checksum_samples.append(global_perf_counter_ns() - start)
        keep(digest)
        result_checksum ^= digest + UInt64(repetition)

        start = global_perf_counter_ns()
        var scale_text = _fixed_phy_scale_trace_text_workload(formats)
        scale_samples.append(global_perf_counter_ns() - start)
        keep(scale_text)
        scale_full_checksum = _mix(
            scale_full_checksum, _text_checksum(StringSlice(scale_text))
        )
        scale_fingerprint_checksum = _mix(
            scale_fingerprint_checksum,
            _text_fingerprint(StringSlice(scale_text)),
        )

        start = global_perf_counter_ns()
        var vectors = _fixed_phy_canonical_rtl_vectors_workload(
            validation, formats
        )
        vector_samples.append(global_perf_counter_ns() - start)
        keep(vectors)
        vector_full_checksum = _mix(
            vector_full_checksum, _text_checksum(StringSlice(vectors))
        )
        vector_fingerprint_checksum = _mix(
            vector_fingerprint_checksum,
            _text_fingerprint(StringSlice(vectors)),
        )

    print_benchmark_metadata()
    report_timing_samples(
        "fixed_phy_default_formats", format_samples, _WARMUPS, 1
    )
    report_timing_samples(
        "fixed_phy_qpsk_ofdm64_flat_ls_eq", samples, _WARMUPS, 1
    )
    report_timing_samples(
        "fixed_phy_result_checksum", checksum_samples, _WARMUPS, 1
    )
    report_timing_samples(
        "fixed_phy_scale_trace_text", scale_samples, _WARMUPS, 1
    )
    report_timing_samples(
        "fixed_phy_canonical_rtl_vectors", vector_samples, _WARMUPS, 1
    )
    keep(format_checksum)
    keep(checksum)
    keep(result_checksum)
    keep(scale_full_checksum)
    keep(scale_fingerprint_checksum)
    keep(vector_full_checksum)
    keep(vector_fingerprint_checksum)
    print("fixed_phy_formats_checksum:", format_checksum)
    print("fixed_phy_retained_checksum:", checksum)
    print("fixed_phy_result_checksum:", result_checksum)
    print("fixed_phy_scale_full_output_checksum:", scale_full_checksum)
    print(
        "fixed_phy_scale_fingerprint_checksum:",
        scale_fingerprint_checksum,
    )
    print("fixed_phy_vectors_full_output_checksum:", vector_full_checksum)
    print(
        "fixed_phy_vectors_fingerprint_checksum:",
        vector_fingerprint_checksum,
    )
    print("fixed_phy_bit_errors:", bit_errors)
    print("fixed_phy_evm_sum:", evm_sum)
