"""Retained latency distribution for fixed legacy Wi-Fi acquisition.

Three complete untimed warmups precede eleven independent timed frames.  A
sample includes standard fixed L-STF creation, whole-packet flat-channel
application, integer timing insertion, 96-sample fixed repetition scan,
detected L-LTF/DATA slicing, LS/ZF/LLR/Viterbi, and FCS.  Input construction
and the content checksum remain outside the timed region.  Median, nearest-
rank p95, and ns/frame are reported by the common benchmark harness.
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
from wireless_dsp.backend.fixed_wifi_acquired_reference import (
    FIXED_WIFI_ACQUIRED_SYNC_SEARCH_SAMPLES,
    FixedWifiAcquiredResult,
    FixedWifiAcquiredRxResult,
    fixed_wifi_acquired_canonical_rtl_vectors,
    fixed_wifi_acquired_receive,
    fixed_wifi_acquired_reference,
    fixed_wifi_acquired_result_checksum,
)


comptime _WARMUPS = 3
comptime _REPETITIONS = 11
comptime _PAYLOAD_OCTETS = 32
comptime _TIMING_OFFSET = 37


@no_inline
def _fixed_wifi_acquired_reference_workload(
    payload: Span[UInt8, ...],
    channel: ComplexRaw,
    formats: FixedPHYFormats,
    timing_offset: Int,
) raises -> FixedWifiAcquiredResult:
    return fixed_wifi_acquired_reference(
        payload, channel, formats, 8192, timing_offset
    )


@no_inline
def _fixed_wifi_acquired_receive_workload(
    observation: Span[ComplexRaw, ...],
    payload: Span[UInt8, ...],
    ltf_grid: Span[ComplexRaw, ...],
    formats: FixedPHYFormats,
    symbol_count: Int,
    scrambler_seed: UInt8,
) raises -> FixedWifiAcquiredRxResult:
    return fixed_wifi_acquired_receive(
        observation,
        payload,
        ltf_grid,
        formats,
        symbol_count,
        scrambler_seed,
    )


@no_inline
def _fixed_wifi_acquired_result_checksum_workload(
    result: FixedWifiAcquiredResult,
) -> UInt64:
    return fixed_wifi_acquired_result_checksum(result)


@no_inline
def _fixed_wifi_acquired_canonical_rtl_vectors_workload(
    result: FixedWifiAcquiredResult, formats: FixedPHYFormats,
) raises -> String:
    return fixed_wifi_acquired_canonical_rtl_vectors(result, formats)


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
    var state = UInt64(0xA55A80211AC01234)
    for _ in range(_PAYLOAD_OCTETS):
        state = (
            state * UInt64(6364136223846793005)
            + UInt64(1442695040888963407)
        )
        payload.append(UInt8(state >> 56))
    var formats = fixed_phy_default_formats()
    var channel = ComplexRaw(12288, -4096)
    var payload_span = Span(payload)

    var validation = _fixed_wifi_acquired_reference_workload(
        payload_span, channel, formats, _TIMING_OFFSET
    )
    if (
        validation.rx.packet_start != _TIMING_OFFSET
        or validation.rx.recovered_payload_bytes != payload
        or validation.rx.payload_byte_errors != 0
        or not validation.rx.service_ok
        or not validation.rx.tail_ok
        or not validation.rx.fcs_ok
        or not validation.composition_matches_known_timing
    ):
        raise Error("fixed acquired Wi-Fi benchmark workload failed round trip")
    var symbol_count = validation.known_timing_audit.data_symbol_count
    var observation_span = Span(validation.observation)
    var ltf_grid_span = Span(validation.known_timing_audit.ltf_grid)
    var scrambler_seed = validation.known_timing_audit.scrambler_seed
    var vectors_first = _fixed_wifi_acquired_canonical_rtl_vectors_workload(
        validation, formats
    )
    var vectors_second = _fixed_wifi_acquired_canonical_rtl_vectors_workload(
        validation, formats
    )
    if (
        _text_checksum(StringSlice(vectors_first))
        != _text_checksum(StringSlice(vectors_second))
    ):
        raise Error("fixed acquired Wi-Fi vectors are nondeterministic")
    keep(vectors_first)
    keep(vectors_second)

    for _ in range(_WARMUPS):
        keep(_fixed_wifi_acquired_reference_workload(
            payload_span, channel, formats, _TIMING_OFFSET
        ))
        keep(_fixed_wifi_acquired_receive_workload(
            observation_span,
            payload_span,
            ltf_grid_span,
            formats,
            symbol_count,
            scrambler_seed,
        ))
        keep(_fixed_wifi_acquired_result_checksum_workload(validation))
        keep(_fixed_wifi_acquired_canonical_rtl_vectors_workload(
            validation, formats
        ))

    var samples = List[UInt64](capacity=_REPETITIONS)
    var receive_samples = List[UInt64](capacity=_REPETITIONS)
    var result_checksum_samples = List[UInt64](capacity=_REPETITIONS)
    var vector_samples = List[UInt64](capacity=_REPETITIONS)
    var checksum = UInt64(0)
    var receive_checksum = UInt64(0)
    var result_checksum = UInt64(0)
    var vector_full_checksum = UInt64(1469598103934665603)
    var vector_fingerprint_checksum = UInt64(1469598103934665603)
    for repetition in range(_REPETITIONS):
        var start = global_perf_counter_ns()
        var result = _fixed_wifi_acquired_reference_workload(
            payload_span, channel, formats, _TIMING_OFFSET
        )
        samples.append(global_perf_counter_ns() - start)
        keep(result)
        checksum ^= (
            UInt64(
                result.rx.packet_start
                + len(result.rx.recovered_payload_bytes)
                + result.rx.payload_byte_errors
            )
            + UInt64(repetition)
        )
        if (
            result.rx.packet_start != _TIMING_OFFSET
            or not result.rx.fcs_ok
            or result.rx.payload_byte_errors != 0
            or not result.composition_matches_known_timing
        ):
            raise Error("timed fixed acquired Wi-Fi frame failed recovery")

        start = global_perf_counter_ns()
        var direct_rx = _fixed_wifi_acquired_receive_workload(
            observation_span,
            payload_span,
            ltf_grid_span,
            formats,
            symbol_count,
            scrambler_seed,
        )
        receive_samples.append(global_perf_counter_ns() - start)
        keep(direct_rx)
        receive_checksum ^= UInt64(
            direct_rx.packet_start
            + len(direct_rx.equalized_data_symbols)
            + len(direct_rx.deinterleaved_llrs_raw)
            + len(direct_rx.recovered_payload_bytes)
            + repetition
        )
        if not direct_rx.fcs_ok or direct_rx.payload_byte_errors != 0:
            raise Error("timed fixed acquired Wi-Fi receiver failed recovery")

        start = global_perf_counter_ns()
        var digest = _fixed_wifi_acquired_result_checksum_workload(validation)
        result_checksum_samples.append(global_perf_counter_ns() - start)
        keep(digest)
        result_checksum ^= digest + UInt64(repetition)

        start = global_perf_counter_ns()
        var vectors = _fixed_wifi_acquired_canonical_rtl_vectors_workload(
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
    print("fixed_wifi_acquired_payload_octets:", _PAYLOAD_OCTETS)
    print("fixed_wifi_acquired_data_symbols:", symbol_count)
    print("fixed_wifi_acquired_timing_offset:", _TIMING_OFFSET)
    print("fixed_wifi_acquired_stf_period:", 16)
    print("fixed_wifi_acquired_stf_samples:", 160)
    print("fixed_wifi_acquired_ltf_samples:", 160)
    print(
        "fixed_wifi_acquired_sync_search_samples:",
        FIXED_WIFI_ACQUIRED_SYNC_SEARCH_SAMPLES,
    )
    print("fixed_wifi_acquired_modulation_coding: QPSK-BCC-R1/2")
    print("fixed_wifi_acquired_channel: flat-complex-fixed")
    print("fixed_wifi_acquired_cfo: zero")
    print("fixed_wifi_acquired_boundary: fixed-repetition-detected")
    print("fixed_wifi_acquired_numeric_contract: nearest-away-saturate-no-wrap")
    print("fixed_wifi_acquired_known_timing_role: composition-audit-only")
    report_timing_samples(
        "fixed_wifi_acquired_frame", samples, _WARMUPS, 1
    )
    report_timing_samples(
        "fixed_wifi_acquired_receive", receive_samples, _WARMUPS, 1
    )
    report_timing_samples(
        "fixed_wifi_acquired_result_checksum",
        result_checksum_samples,
        _WARMUPS,
        1,
    )
    report_timing_samples(
        "fixed_wifi_acquired_canonical_rtl_vectors",
        vector_samples,
        _WARMUPS,
        1,
    )
    keep(checksum)
    keep(receive_checksum)
    keep(result_checksum)
    keep(vector_full_checksum)
    keep(vector_fingerprint_checksum)
    print("fixed_wifi_acquired_retained_content_checksum:", checksum)
    print("fixed_wifi_acquired_receive_checksum:", receive_checksum)
    print("fixed_wifi_acquired_result_checksum:", result_checksum)
    print(
        "fixed_wifi_acquired_vectors_full_output_checksum:",
        vector_full_checksum,
    )
    print(
        "fixed_wifi_acquired_vectors_fingerprint_checksum:",
        vector_fingerprint_checksum,
    )
