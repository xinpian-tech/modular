"""Retained benchmark for the connected fixed BCC/QPSK/OFDM mini-PHY."""

from std.collections import Span
from std.benchmark import keep
from std.time import global_perf_counter_ns
from wireless_dsp.benchmarking import (
    print_benchmark_metadata,
    report_timing_samples,
)
from wireless_dsp.numerics.complex_fixed import ComplexRaw
from wireless_dsp.numerics.quantization import QFormat
from wireless_dsp.backend.fixed_phy_reference import (
    FixedPHYFormats,
    fixed_phy_default_formats,
)
from wireless_dsp.backend.fixed_wifi_phy_reference import (
    FixedWifiPHYResult,
    fixed_wifi_bcc_ofdm_reference,
    fixed_wifi_phy_canonical_rtl_vectors,
    fixed_wifi_phy_result_checksum,
)


comptime _WARMUPS = 3
comptime _SAMPLES = 9


@no_inline
def _fixed_wifi_bcc_ofdm_reference_workload(
    payload: Span[UInt8, ...], channel: ComplexRaw, formats: FixedPHYFormats
) raises -> FixedWifiPHYResult:
    return fixed_wifi_bcc_ofdm_reference(
        payload,
        64,
        16,
        channel,
        formats,
        8192,
        pilot_symbols=4,
    )


@no_inline
def _fixed_wifi_phy_result_checksum_workload(
    result: FixedWifiPHYResult, llr_format: QFormat
) raises -> UInt64:
    return fixed_wifi_phy_result_checksum(result, llr_format)


@no_inline
def _fixed_wifi_phy_canonical_rtl_vectors_workload(
    result: FixedWifiPHYResult, formats: FixedPHYFormats,
) raises -> String:
    return fixed_wifi_phy_canonical_rtl_vectors(result, formats)


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
    var payload = List[UInt8](capacity=58)
    for index in range(58):
        payload.append(UInt8((index * 17 + index // 3 + 1) & 1))
    var formats = fixed_phy_default_formats()
    var payload_span = Span(payload)
    var channel = ComplexRaw(12288, -4096)
    var validation = _fixed_wifi_bcc_ofdm_reference_workload(
        payload_span, channel, formats
    )
    var vectors_first = _fixed_wifi_phy_canonical_rtl_vectors_workload(
        validation, formats
    )
    var vectors_second = _fixed_wifi_phy_canonical_rtl_vectors_workload(
        validation, formats
    )
    if (
        _text_checksum(StringSlice(vectors_first))
        != _text_checksum(StringSlice(vectors_second))
    ):
        raise Error("fixed Wi-Fi PHY vectors are nondeterministic")
    keep(vectors_first)
    keep(vectors_second)
    for _ in range(_WARMUPS):
        keep(_fixed_wifi_bcc_ofdm_reference_workload(
            payload_span, channel, formats
        ))
        keep(_fixed_wifi_phy_result_checksum_workload(
            validation, formats.symbol
        ))
        keep(_fixed_wifi_phy_canonical_rtl_vectors_workload(
            validation, formats
        ))

    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum_samples = List[UInt64](capacity=_SAMPLES)
    var vector_samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(0)
    var result_checksum = UInt64(0)
    var vector_full_checksum = UInt64(1469598103934665603)
    var vector_fingerprint_checksum = UInt64(1469598103934665603)
    var bit_errors = 0
    for repetition in range(_SAMPLES):
        var start = global_perf_counter_ns()
        var result = _fixed_wifi_bcc_ofdm_reference_workload(
            payload_span, channel, formats
        )
        samples.append(global_perf_counter_ns() - start)
        keep(result)
        checksum ^= UInt64(
            len(result.payload_bits)
            + len(result.coded_bits)
            + result.payload_bit_errors
            + repetition
        )
        bit_errors += result.payload_bit_errors

        start = global_perf_counter_ns()
        var digest = _fixed_wifi_phy_result_checksum_workload(
            validation, formats.symbol
        )
        checksum_samples.append(global_perf_counter_ns() - start)
        keep(digest)
        result_checksum ^= digest + UInt64(repetition)

        start = global_perf_counter_ns()
        var vectors = _fixed_wifi_phy_canonical_rtl_vectors_workload(
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
    print("fixed_wifi_phy_payload_bits_per_symbol:", 58)
    report_timing_samples(
        "fixed_wifi_bcc_qpsk_ofdm_symbol", samples, _WARMUPS, 1
    )
    report_timing_samples(
        "fixed_wifi_phy_result_checksum",
        checksum_samples,
        _WARMUPS,
        1,
    )
    report_timing_samples(
        "fixed_wifi_phy_canonical_rtl_vectors",
        vector_samples,
        _WARMUPS,
        1,
    )
    print("fixed_wifi_phy_payload_bit_errors:", bit_errors)
    keep(checksum)
    keep(result_checksum)
    keep(vector_full_checksum)
    keep(vector_fingerprint_checksum)
    print("fixed_wifi_phy_retained_checksum:", checksum)
    print("fixed_wifi_phy_result_checksum:", result_checksum)
    print(
        "fixed_wifi_phy_vectors_full_output_checksum:",
        vector_full_checksum,
    )
    print(
        "fixed_wifi_phy_vectors_fingerprint_checksum:",
        vector_fingerprint_checksum,
    )
