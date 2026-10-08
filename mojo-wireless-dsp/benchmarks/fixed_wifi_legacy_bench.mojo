"""Retained latency distribution for the standard fixed legacy mini-PHY.

Three complete untimed warmups precede eleven independent timed executions.
Each sample includes framing, FCS, scrambling, BCC/interleaving, standard
52-tone OFDM, L-LTF flat LS, ZF, fixed LLRs, and soft Viterbi recovery.  Input
construction and result checksumming remain outside the timed region.  The
reported p95 uses the nearest-rank definition.
"""

from std.benchmark import keep
from std.collections import Span
from std.time import global_perf_counter_ns
from wireless_dsp.benchmarking import (
    print_benchmark_metadata,
    report_timing_samples,
)
from wireless_dsp.numerics.complex_fixed import ComplexRaw
from wireless_dsp.backend.fixed_phy_reference import (
    FixedPHYFormats,
    fixed_phy_default_formats,
)
from wireless_dsp.backend.fixed_wifi_legacy_reference import (
    FixedWifiLegacyResult,
    fixed_wifi_legacy_canonical_rtl_vectors,
    fixed_wifi_legacy_reference,
    fixed_wifi_legacy_result_checksum,
)


comptime _WARMUPS = 3
comptime _REPETITIONS = 11
comptime _PAYLOAD_OCTETS = 32


@no_inline
def _fixed_wifi_legacy_reference_workload(
    payload: Span[UInt8, ...],
    channel: ComplexRaw,
    formats: FixedPHYFormats,
) raises -> FixedWifiLegacyResult:
    return fixed_wifi_legacy_reference(payload, channel, formats, 8192)


@no_inline
def _fixed_wifi_legacy_result_checksum_workload(
    result: FixedWifiLegacyResult,
) -> UInt64:
    return fixed_wifi_legacy_result_checksum(result)


@no_inline
def _fixed_wifi_legacy_canonical_rtl_vectors_workload(
    result: FixedWifiLegacyResult, formats: FixedPHYFormats,
) raises -> String:
    return fixed_wifi_legacy_canonical_rtl_vectors(result, formats)


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
    var payload = List[UInt8](capacity=_PAYLOAD_OCTETS)
    var state = UInt64(0x80211A5EED202608)
    for _ in range(_PAYLOAD_OCTETS):
        state = (
            state * UInt64(6364136223846793005)
            + UInt64(1442695040888963407)
        )
        payload.append(UInt8(state >> 56))
    var formats = fixed_phy_default_formats()
    var channel = ComplexRaw(12288, -4096)
    var payload_span = Span(payload)

    var validation = _fixed_wifi_legacy_reference_workload(
        payload_span, channel, formats
    )
    if (
        validation.recovered_payload_bytes != payload
        or validation.payload_byte_errors != 0
        or not validation.service_ok
        or not validation.tail_ok
        or not validation.fcs_ok
        or validation.audit.bit_errors != 0
    ):
        raise Error("fixed legacy Wi-Fi benchmark workload failed round trip")
    var symbol_count = validation.data_symbol_count
    var vectors_first = _fixed_wifi_legacy_canonical_rtl_vectors_workload(
        validation, formats
    )
    var vectors_second = _fixed_wifi_legacy_canonical_rtl_vectors_workload(
        validation, formats
    )
    if (
        _text_checksum(StringSlice(vectors_first))
        != _text_checksum(StringSlice(vectors_second))
    ):
        raise Error("fixed legacy Wi-Fi vectors are nondeterministic")
    keep(vectors_first)
    keep(vectors_second)

    for _ in range(_WARMUPS):
        keep(
            _fixed_wifi_legacy_reference_workload(
                payload_span, channel, formats
            )
        )
        keep(_fixed_wifi_legacy_result_checksum_workload(validation))
        keep(_fixed_wifi_legacy_canonical_rtl_vectors_workload(
            validation, formats
        ))

    var samples = List[UInt64](capacity=_REPETITIONS)
    var checksum_samples = List[UInt64](capacity=_REPETITIONS)
    var vector_samples = List[UInt64](capacity=_REPETITIONS)
    var checksum = UInt64(0)
    var result_checksum = UInt64(0)
    var vector_full_checksum = UInt64(1469598103934665603)
    var vector_fingerprint_checksum = UInt64(1469598103934665603)
    for repetition in range(_REPETITIONS):
        var start = global_perf_counter_ns()
        var result = _fixed_wifi_legacy_reference_workload(
            payload_span, channel, formats
        )
        samples.append(global_perf_counter_ns() - start)
        keep(result)
        checksum ^= UInt64(
            len(result.recovered_payload_bytes)
            + result.payload_byte_errors
            + repetition
        )
        if not result.fcs_ok or result.payload_byte_errors != 0:
            raise Error("timed fixed legacy Wi-Fi frame failed recovery")

        start = global_perf_counter_ns()
        var digest = _fixed_wifi_legacy_result_checksum_workload(validation)
        checksum_samples.append(global_perf_counter_ns() - start)
        keep(digest)
        result_checksum ^= digest + UInt64(repetition)

        start = global_perf_counter_ns()
        var vectors = _fixed_wifi_legacy_canonical_rtl_vectors_workload(
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
    print("fixed_wifi_legacy_payload_octets:", _PAYLOAD_OCTETS)
    print("fixed_wifi_legacy_data_symbols:", symbol_count)
    print("fixed_wifi_legacy_fft_size:", 64)
    print("fixed_wifi_legacy_data_cp:", 16)
    print("fixed_wifi_legacy_active_tones:", 52)
    print("fixed_wifi_legacy_data_tones:", 48)
    print("fixed_wifi_legacy_pilot_tones:", 4)
    print("fixed_wifi_legacy_modulation_coding: QPSK-BCC-R1/2")
    print("fixed_wifi_legacy_numeric_contract: nearest-away-saturate-no-wrap")
    report_timing_samples(
        "fixed_wifi_legacy_frame", samples, _WARMUPS, 1
    )
    report_timing_samples(
        "fixed_wifi_legacy_result_checksum",
        checksum_samples,
        _WARMUPS,
        1,
    )
    report_timing_samples(
        "fixed_wifi_legacy_canonical_rtl_vectors",
        vector_samples,
        _WARMUPS,
        1,
    )
    keep(checksum)
    keep(result_checksum)
    keep(vector_full_checksum)
    keep(vector_fingerprint_checksum)
    print("fixed_wifi_legacy_retained_checksum:", checksum)
    print("fixed_wifi_legacy_result_checksum:", result_checksum)
    print(
        "fixed_wifi_legacy_vectors_full_output_checksum:",
        vector_full_checksum,
    )
    print(
        "fixed_wifi_legacy_vectors_fingerprint_checksum:",
        vector_fingerprint_checksum,
    )
