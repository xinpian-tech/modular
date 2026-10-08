"""Repeatable latency samples for the fixed Wi-Fi K=7 BCC golden model.

The benchmark keeps input construction outside the timed regions, performs
three warmups, and reports median and nearest-rank p95 across eleven samples.
Fresh result allocation and the complete survivor-memory traceback are part of
each Viterbi timing.  Output-dependent checksums keep measured work observable.
"""

from std.benchmark import keep
from std.collections import Span
from std.time import global_perf_counter_ns
from wireless_dsp.benchmarking import (
    print_benchmark_metadata,
    report_timing_samples,
)
from wireless_dsp.numerics.fixed import (
    OVERFLOW_SATURATE,
    ROUND_NEAREST_AWAY,
)
from wireless_dsp.numerics.quantization import QFormat
from wireless_dsp.backend.fixed_wifi_bcc_reference import (
    FixedWifiBCCDecodeResult,
    FixedWifiBCCViterbiConfig,
    fixed_wifi_bcc_canonical_rtl_vectors,
    fixed_wifi_bcc_encode,
    fixed_wifi_bcc_result_checksum,
    fixed_wifi_bcc_viterbi_decode_hard,
    fixed_wifi_bcc_viterbi_decode_soft,
)


comptime _PAYLOAD_BITS = 1024
comptime _WARMUPS = 3
comptime _REPETITIONS = 11


@no_inline
def _fixed_wifi_bcc_encode_workload(
    payload: Span[UInt8, ...],
) raises -> List[UInt8]:
    return fixed_wifi_bcc_encode(payload)


@no_inline
def _fixed_wifi_bcc_viterbi_decode_hard_workload(
    coded: Span[UInt8, ...], metric_storage_bits: Int,
) raises -> FixedWifiBCCDecodeResult:
    return fixed_wifi_bcc_viterbi_decode_hard(
        coded, metric_storage_bits=metric_storage_bits
    )


@no_inline
def _fixed_wifi_bcc_viterbi_decode_soft_workload(
    llrs: Span[Int64, ...], config: FixedWifiBCCViterbiConfig,
) raises -> FixedWifiBCCDecodeResult:
    return fixed_wifi_bcc_viterbi_decode_soft(llrs, config)


@no_inline
def _fixed_wifi_bcc_result_checksum_workload(
    payload: Span[UInt8, ...],
    coded: Span[UInt8, ...],
    llrs: Span[Int64, ...],
    llr_format: QFormat,
    hard: FixedWifiBCCDecodeResult,
    soft: FixedWifiBCCDecodeResult,
) raises -> UInt64:
    return fixed_wifi_bcc_result_checksum(
        payload, coded, llrs, llr_format, hard, soft
    )


@no_inline
def _fixed_wifi_bcc_canonical_rtl_vectors_workload(
    payload: Span[UInt8, ...],
    coded: Span[UInt8, ...],
    llrs: Span[Int64, ...],
    llr_format: QFormat,
    hard: FixedWifiBCCDecodeResult,
    soft: FixedWifiBCCDecodeResult,
) raises -> String:
    return fixed_wifi_bcc_canonical_rtl_vectors(
        payload, coded, llrs, llr_format, hard, soft
    )


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


def _bits_fingerprint(values: Span[UInt8, ...]) -> UInt64:
    return (
        UInt64(len(values))
        ^ (UInt64(values[0]) << 17)
        ^ (UInt64(values[len(values) - 1]) << 33)
    )


def _decode_fingerprint(result: FixedWifiBCCDecodeResult) -> UInt64:
    return (
        _bits_fingerprint(Span(result.bits))
        ^ (UInt64(result.final_state) << 7)
        ^ UInt64(result.final_normalized_metric_raw)
        ^ (UInt64(result.saturation_count) << 41)
    )


def main() raises:
    var payload = List[UInt8](capacity=_PAYLOAD_BITS)
    var state = UInt64(0xBCCD20260821)
    for _ in range(_PAYLOAD_BITS):
        state = (
            state * UInt64(6364136223846793005)
            + UInt64(1442695040888963407)
        )
        payload.append(UInt8((state >> 63) & 1))

    var payload_span = Span(payload)
    var coded = _fixed_wifi_bcc_encode_workload(payload_span)
    var llrs = List[Int64](capacity=len(coded))
    for index in range(len(coded)):
        var reliability = Int64(24 + (index * 13) % 41)
        llrs.append(reliability if coded[index] == 0 else -reliability)
    var llr_format = QFormat(
        10, 3, ROUND_NEAREST_AWAY, OVERFLOW_SATURATE
    )
    var soft_config = FixedWifiBCCViterbiConfig(llr_format, 24)
    var coded_span = Span(coded)
    var llrs_span = Span(llrs)
    comptime metric_storage_bits = 16

    # Fail before timing if the deterministic workload is not a round trip.
    var hard_check = _fixed_wifi_bcc_viterbi_decode_hard_workload(
        coded_span, metric_storage_bits
    )
    var soft_check = _fixed_wifi_bcc_viterbi_decode_soft_workload(
        llrs_span, soft_config
    )
    if hard_check.bits != payload or soft_check.bits != payload:
        raise Error("fixed Wi-Fi BCC benchmark workload failed round trip")
    var digest_first = _fixed_wifi_bcc_result_checksum_workload(
        payload_span,
        coded_span,
        llrs_span,
        llr_format,
        hard_check,
        soft_check,
    )
    var digest_second = _fixed_wifi_bcc_result_checksum_workload(
        payload_span,
        coded_span,
        llrs_span,
        llr_format,
        hard_check,
        soft_check,
    )
    var vectors_first = _fixed_wifi_bcc_canonical_rtl_vectors_workload(
        payload_span,
        coded_span,
        llrs_span,
        llr_format,
        hard_check,
        soft_check,
    )
    var vectors_second = _fixed_wifi_bcc_canonical_rtl_vectors_workload(
        payload_span,
        coded_span,
        llrs_span,
        llr_format,
        hard_check,
        soft_check,
    )
    if (
        digest_first != digest_second
        or _text_checksum(StringSlice(vectors_first))
        != _text_checksum(StringSlice(vectors_second))
    ):
        raise Error("fixed Wi-Fi BCC artifact workload is nondeterministic")
    keep(digest_first)
    keep(digest_second)
    keep(vectors_first)
    keep(vectors_second)

    for _ in range(_WARMUPS):
        keep(_fixed_wifi_bcc_encode_workload(payload_span))
        keep(_fixed_wifi_bcc_viterbi_decode_hard_workload(
            coded_span, metric_storage_bits
        ))
        keep(_fixed_wifi_bcc_viterbi_decode_soft_workload(
            llrs_span, soft_config
        ))
        keep(_fixed_wifi_bcc_result_checksum_workload(
            payload_span,
            coded_span,
            llrs_span,
            llr_format,
            hard_check,
            soft_check,
        ))
        keep(_fixed_wifi_bcc_canonical_rtl_vectors_workload(
            payload_span,
            coded_span,
            llrs_span,
            llr_format,
            hard_check,
            soft_check,
        ))

    var encode_samples = List[UInt64](capacity=_REPETITIONS)
    var hard_samples = List[UInt64](capacity=_REPETITIONS)
    var soft_samples = List[UInt64](capacity=_REPETITIONS)
    var result_checksum_samples = List[UInt64](capacity=_REPETITIONS)
    var vector_samples = List[UInt64](capacity=_REPETITIONS)
    var encode_checksum = UInt64(0)
    var hard_checksum = UInt64(0)
    var soft_checksum = UInt64(0)
    var result_checksum = UInt64(1469598103934665603)
    var vector_full_checksum = UInt64(1469598103934665603)
    var vector_fingerprint_checksum = UInt64(1469598103934665603)
    for repetition in range(_REPETITIONS):
        var start = global_perf_counter_ns()
        var encoded = _fixed_wifi_bcc_encode_workload(payload_span)
        encode_samples.append(global_perf_counter_ns() - start)
        keep(encoded)
        encode_checksum ^= _bits_fingerprint(Span(encoded)) + UInt64(repetition)

        start = global_perf_counter_ns()
        var hard = _fixed_wifi_bcc_viterbi_decode_hard_workload(
            coded_span, metric_storage_bits
        )
        hard_samples.append(global_perf_counter_ns() - start)
        keep(hard)
        hard_checksum ^= _decode_fingerprint(hard) + UInt64(repetition)

        start = global_perf_counter_ns()
        var soft = _fixed_wifi_bcc_viterbi_decode_soft_workload(
            llrs_span, soft_config
        )
        soft_samples.append(global_perf_counter_ns() - start)
        keep(soft)
        soft_checksum ^= _decode_fingerprint(soft) + UInt64(repetition)

        start = global_perf_counter_ns()
        var digest = _fixed_wifi_bcc_result_checksum_workload(
            payload_span,
            coded_span,
            llrs_span,
            llr_format,
            hard_check,
            soft_check,
        )
        result_checksum_samples.append(global_perf_counter_ns() - start)
        keep(digest)
        result_checksum = _mix(result_checksum, digest)

        start = global_perf_counter_ns()
        var vectors = _fixed_wifi_bcc_canonical_rtl_vectors_workload(
            payload_span,
            coded_span,
            llrs_span,
            llr_format,
            hard_check,
            soft_check,
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
    print("fixed_wifi_bcc_payload_bits:", _PAYLOAD_BITS)
    print("fixed_wifi_bcc_trellis_steps:", _PAYLOAD_BITS + 6)
    print("fixed_wifi_bcc_coded_bits:", 2 * (_PAYLOAD_BITS + 6))
    print("fixed_wifi_bcc_llr_q: sint10_fraction3_saturate")
    print("fixed_wifi_bcc_hard_metric_q: sint16_fraction0_saturate")
    print("fixed_wifi_bcc_soft_metric_q: sint24_fraction3_saturate")
    print("fixed_wifi_bcc_survivor_tie: lower-predecessor")
    report_timing_samples(
        "fixed_wifi_bcc_encode_payload_bit",
        encode_samples,
        _WARMUPS,
        _PAYLOAD_BITS,
    )
    report_timing_samples(
        "fixed_wifi_bcc_hard_viterbi_trellis_step",
        hard_samples,
        _WARMUPS,
        _PAYLOAD_BITS + 6,
    )
    report_timing_samples(
        "fixed_wifi_bcc_soft_viterbi_trellis_step",
        soft_samples,
        _WARMUPS,
        _PAYLOAD_BITS + 6,
    )
    report_timing_samples(
        "fixed_wifi_bcc_result_checksum",
        result_checksum_samples,
        _WARMUPS,
        1,
    )
    report_timing_samples(
        "fixed_wifi_bcc_canonical_rtl_vectors",
        vector_samples,
        _WARMUPS,
        1,
    )
    keep(encode_checksum)
    keep(hard_checksum)
    keep(soft_checksum)
    keep(result_checksum)
    keep(vector_full_checksum)
    keep(vector_fingerprint_checksum)
    print("fixed_wifi_bcc_encode_retained_checksum:", encode_checksum)
    print("fixed_wifi_bcc_hard_retained_checksum:", hard_checksum)
    print("fixed_wifi_bcc_soft_retained_checksum:", soft_checksum)
    print("fixed_wifi_bcc_result_checksum:", result_checksum)
    print(
        "fixed_wifi_bcc_vectors_full_output_checksum:",
        vector_full_checksum,
    )
    print(
        "fixed_wifi_bcc_vectors_fingerprint_checksum:",
        vector_fingerprint_checksum,
    )
