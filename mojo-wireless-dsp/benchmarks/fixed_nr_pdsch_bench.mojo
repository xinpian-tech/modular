"""Retained latency distribution for the bounded fixed NR PDSCH chain.

Three complete untimed warmups precede eleven independent timed executions.
Each sample includes TS 38.212 CRC/LDPC/rate matching, Gold scrambling and
comb-2 DM-RS, fixed QPSK/IFFT/CP, the three-tap registered fixed channel,
fixed FFT/LS/interpolation/ZF/LLRs, fixed LLR rescaling/descrambling, fixed
circular-buffer recovery, layered fixed min-sum LDPC, and CRC.  The parallel
Float64 differential audit is included but does not select decoder outputs.
Input construction and result checksumming remain outside the timed region.
P95 uses the nearest-rank definition; all latency values are nanoseconds.
"""

from std.benchmark import keep
from std.collections import Span
from std.sys.info import align_of
from std.time import global_perf_counter_ns
from wireless_dsp.benchmarking import (
    print_benchmark_metadata,
    print_runtime_buffer_alignment,
    report_timing_samples,
)
from wireless_dsp.numerics.complex_fixed import ComplexRaw
from wireless_dsp.backend.fixed_nr_pdsch_reference import (
    FixedNRPDSCHConfig,
    FixedNRPDSCHFormats,
    FixedNRPDSCHResult,
    fixed_nr_pdsch_canonical_rtl_vectors,
    fixed_nr_pdsch_default_formats,
    fixed_nr_pdsch_reference,
    fixed_nr_pdsch_result_checksum,
    fixed_nr_pdsch_scale_trace_text,
)


comptime _WARMUPS = 3
comptime _REPETITIONS = 11
comptime _PAYLOAD_BITS = 100


@no_inline
def _fixed_nr_pdsch_default_formats_workload(
) raises -> FixedNRPDSCHFormats:
    return fixed_nr_pdsch_default_formats()


@no_inline
def _fixed_nr_pdsch_reference_workload(
    payload: Span[UInt8, ...],
    taps: Span[ComplexRaw, ...],
    formats: FixedNRPDSCHFormats,
    config: FixedNRPDSCHConfig,
) raises -> FixedNRPDSCHResult:
    return fixed_nr_pdsch_reference(
        payload, taps, formats, Int64(11585), config
    )


@no_inline
def _fixed_nr_pdsch_result_checksum_workload(
    result: FixedNRPDSCHResult,
) -> UInt64:
    return fixed_nr_pdsch_result_checksum(result)


@no_inline
def _fixed_nr_pdsch_scale_trace_text_workload(
    result: FixedNRPDSCHResult, formats: FixedNRPDSCHFormats,
) raises -> String:
    return fixed_nr_pdsch_scale_trace_text(result, formats)


@no_inline
def _fixed_nr_pdsch_canonical_rtl_vectors_workload(
    result: FixedNRPDSCHResult, formats: FixedNRPDSCHFormats,
) raises -> String:
    return fixed_nr_pdsch_canonical_rtl_vectors(result, formats)


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


def _payload() -> List[UInt8]:
    var state = UInt64(0x5EED5EED20260821)
    var result = List[UInt8](capacity=_PAYLOAD_BITS)
    for _ in range(_PAYLOAD_BITS):
        state = (
            state * UInt64(6364136223846793005)
            + UInt64(1442695040888963407)
        )
        result.append(UInt8((state >> UInt64(63)) & UInt64(1)))
    return result^


def main() raises:
    var payload = _payload()
    var taps: List[ComplexRaw] = [
        ComplexRaw(12288, 1024),
        ComplexRaw(3072, -2048),
        ComplexRaw(1024, 512),
    ]
    var formats = _fixed_nr_pdsch_default_formats_workload()
    var config = FixedNRPDSCHConfig()
    var payload_span = Span(payload)
    var taps_span = Span(taps)
    var validation = _fixed_nr_pdsch_reference_workload(
        payload_span, taps_span, formats, config
    )
    if (
        validation.decoded_payload_bits != payload
        or validation.audit.scrambled_bit_errors != 0
        or validation.audit.rate_matched_bit_errors != 0
        or validation.audit.payload_bit_errors != 0
        or not validation.ldpc_converged
        or not validation.code_block_crc_ok
        or not validation.transport_crc_ok
        or not validation.float64_decoder_agrees
    ):
        raise Error("fixed NR PDSCH benchmark workload failed validation")
    var scale_first = _fixed_nr_pdsch_scale_trace_text_workload(
        validation, formats
    )
    var scale_second = _fixed_nr_pdsch_scale_trace_text_workload(
        validation, formats
    )
    var vectors_first = _fixed_nr_pdsch_canonical_rtl_vectors_workload(
        validation, formats
    )
    var vectors_second = _fixed_nr_pdsch_canonical_rtl_vectors_workload(
        validation, formats
    )
    if (
        _text_checksum(StringSlice(scale_first))
        != _text_checksum(StringSlice(scale_second))
        or _text_checksum(StringSlice(vectors_first))
        != _text_checksum(StringSlice(vectors_second))
    ):
        raise Error("fixed NR PDSCH artifact workload is nondeterministic")
    keep(scale_first)
    keep(scale_second)
    keep(vectors_first)
    keep(vectors_second)

    for _ in range(_WARMUPS):
        keep(_fixed_nr_pdsch_default_formats_workload())
        keep(_fixed_nr_pdsch_reference_workload(
            payload_span, taps_span, formats, config
        ))
        keep(_fixed_nr_pdsch_result_checksum_workload(validation))
        keep(_fixed_nr_pdsch_scale_trace_text_workload(validation, formats))
        keep(_fixed_nr_pdsch_canonical_rtl_vectors_workload(
            validation, formats
        ))

    var format_samples = List[UInt64](capacity=_REPETITIONS)
    var samples = List[UInt64](capacity=_REPETITIONS)
    var checksum_samples = List[UInt64](capacity=_REPETITIONS)
    var scale_samples = List[UInt64](capacity=_REPETITIONS)
    var vector_samples = List[UInt64](capacity=_REPETITIONS)
    var format_checksum = UInt64(0)
    var checksum = UInt64(0)
    var result_checksum = UInt64(0)
    var scale_full_checksum = UInt64(1469598103934665603)
    var scale_fingerprint_checksum = UInt64(1469598103934665603)
    var vector_full_checksum = UInt64(1469598103934665603)
    var vector_fingerprint_checksum = UInt64(1469598103934665603)
    for repetition in range(_REPETITIONS):
        var start = global_perf_counter_ns()
        var measured_formats = _fixed_nr_pdsch_default_formats_workload()
        format_samples.append(global_perf_counter_ns() - start)
        keep(measured_formats)
        format_checksum ^= UInt64(
            measured_formats.symbol.storage_bits
            + measured_formats.symbol.fraction_bits
            + repetition
        )

        start = global_perf_counter_ns()
        var result = _fixed_nr_pdsch_reference_workload(
            payload_span, taps_span, formats, config
        )
        samples.append(global_perf_counter_ns() - start)
        keep(result)
        checksum ^= UInt64(
            len(result.decoded_payload_bits)
            + result.audit.payload_bit_errors
            + repetition
        )
        if (
            result.decoded_payload_bits != payload
            or result.audit.rate_matched_bit_errors != 0
            or result.audit.payload_bit_errors != 0
            or not result.transport_crc_ok
        ):
            raise Error("timed fixed NR PDSCH chain failed recovery")

        start = global_perf_counter_ns()
        var digest = _fixed_nr_pdsch_result_checksum_workload(validation)
        checksum_samples.append(global_perf_counter_ns() - start)
        keep(digest)
        result_checksum ^= digest + UInt64(repetition)

        start = global_perf_counter_ns()
        var scale_text = _fixed_nr_pdsch_scale_trace_text_workload(
            validation, formats
        )
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
        var vectors = _fixed_nr_pdsch_canonical_rtl_vectors_workload(
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
    print_runtime_buffer_alignment(
        "fixed_nr_pdsch_payload_bits",
        Int(payload.unsafe_ptr()),
        align_of[UInt8](),
    )
    print("fixed_nr_pdsch_scope: single-layer-single-codeword-qpsk")
    print("fixed_nr_pdsch_fft_size:", 512)
    print("fixed_nr_pdsch_cyclic_prefix:", 36)
    print("fixed_nr_pdsch_allocation_re:", 480)
    print("fixed_nr_pdsch_dmrs: configuration-type-1-comb2")
    print("fixed_nr_pdsch_channel_taps:", 3)
    print("fixed_nr_pdsch_physical_numeric_contract: bit-exact-fixed")
    print("fixed_nr_pdsch_decoder_contract: end-to-end-bit-exact-fixed")
    print("fixed_nr_pdsch_float64_role: differential-audit-only")
    print("fixed_nr_pdsch_timing_unit: ns")
    report_timing_samples(
        "fixed_nr_pdsch_default_formats",
        format_samples,
        _WARMUPS,
        1,
    )
    report_timing_samples(
        "fixed_nr_pdsch_complete_chain",
        samples,
        _WARMUPS,
        1,
        "fixed_nr_pdsch_frame",
    )
    report_timing_samples(
        "fixed_nr_pdsch_result_checksum",
        checksum_samples,
        _WARMUPS,
        1,
    )
    report_timing_samples(
        "fixed_nr_pdsch_scale_trace_text",
        scale_samples,
        _WARMUPS,
        1,
    )
    report_timing_samples(
        "fixed_nr_pdsch_canonical_rtl_vectors",
        vector_samples,
        _WARMUPS,
        1,
    )
    keep(format_checksum)
    keep(checksum)
    keep(result_checksum)
    keep(scale_full_checksum)
    keep(scale_fingerprint_checksum)
    keep(vector_full_checksum)
    keep(vector_fingerprint_checksum)
    print("fixed_nr_pdsch_formats_checksum:", format_checksum)
    print("fixed_nr_pdsch_checksum:", checksum)
    print("fixed_nr_pdsch_result_checksum:", result_checksum)
    print(
        "fixed_nr_pdsch_scale_full_output_checksum:",
        scale_full_checksum,
    )
    print(
        "fixed_nr_pdsch_scale_fingerprint_checksum:",
        scale_fingerprint_checksum,
    )
    print(
        "fixed_nr_pdsch_vectors_full_output_checksum:",
        vector_full_checksum,
    )
    print(
        "fixed_nr_pdsch_vectors_fingerprint_checksum:",
        vector_fingerprint_checksum,
    )
