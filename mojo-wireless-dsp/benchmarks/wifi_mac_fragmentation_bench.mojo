"""Per-API CPU timings for Wi-Fi fragmentation and MPDU delimiters.

Each public algorithm has three untimed warmups and nine independent timed
samples.  Input mutation and delimiter construction for parser measurements
occur outside timed regions.  Every output field and list element contributes
to the retained checksum; one sample denominator is one complete API call.
"""

from std.benchmark import keep
from std.collections import Span
from std.time import global_perf_counter_ns
from wireless_dsp.benchmarking import (
    print_benchmark_metadata,
    report_timing_samples,
)
from wireless_dsp.wireless.wifi.mac_fragmentation import (
    WIFI_AMPDU_DELIMITER_PROFILE_VHT_OR_LATER,
    WifiFragmentationPlan,
    WifiReassemblyPlan,
    WifiAMPDUDelimiterFields,
    wifi_fragmentation_plan,
    wifi_reassembly_plan,
    wifi_ampdu_delimiter_crc8,
    wifi_ampdu_delimiter_serialize,
    wifi_ampdu_delimiter_parse,
)


comptime _WARMUPS = 3
comptime _SAMPLES = 9


def _mix(checksum: UInt64, value: Int) -> UInt64:
    return (checksum ^ UInt64(value + 1)) * UInt64(1099511628211)


@no_inline
def _workload_wifi_fragmentation_plan() raises -> WifiFragmentationPlan:
    return wifi_fragmentation_plan(1000, 300, 40, 291)


@no_inline
def _workload_wifi_reassembly_plan(
    controls: Span[Int, ...], more: Span[UInt8, ...], payloads: Span[Int, ...],
) raises -> WifiReassemblyPlan:
    return wifi_reassembly_plan(controls, more, payloads)


@no_inline
def _workload_wifi_ampdu_delimiter_crc8() raises -> Int:
    return wifi_ampdu_delimiter_crc8(0xB0, 0x9B)


@no_inline
def _workload_wifi_ampdu_delimiter_serialize() raises -> List[UInt8]:
    return wifi_ampdu_delimiter_serialize(
        2491, profile=WIFI_AMPDU_DELIMITER_PROFILE_VHT_OR_LATER
    )


@no_inline
def _workload_wifi_ampdu_delimiter_parse(
    delimiter: Span[UInt8, ...],
) raises -> WifiAMPDUDelimiterFields:
    return wifi_ampdu_delimiter_parse(
        delimiter, profile=WIFI_AMPDU_DELIMITER_PROFILE_VHT_OR_LATER
    )


def main() raises:
    var controls: List[Int] = [4656, 4657, 4658, 4659]
    var more: List[UInt8] = [1, 1, 1, 0]
    var payloads: List[Int] = [260, 260, 260, 220]
    var controls_span = Span(controls)
    var more_span = Span(more)
    var payloads_span = Span(payloads)
    var parser_input = _workload_wifi_ampdu_delimiter_serialize()
    var parser_span = Span(parser_input)

    for _ in range(_WARMUPS):
        keep(_workload_wifi_fragmentation_plan())
        keep(_workload_wifi_reassembly_plan(controls_span, more_span, payloads_span))
        keep(_workload_wifi_ampdu_delimiter_crc8())
        keep(_workload_wifi_ampdu_delimiter_serialize())
        keep(_workload_wifi_ampdu_delimiter_parse(parser_span))

    var fragmentation_samples = List[UInt64](capacity=_SAMPLES)
    var reassembly_samples = List[UInt64](capacity=_SAMPLES)
    var crc_samples = List[UInt64](capacity=_SAMPLES)
    var serialize_samples = List[UInt64](capacity=_SAMPLES)
    var parse_samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(14695981039346656037)

    for _ in range(_SAMPLES):
        var start = global_perf_counter_ns()
        var fragments = _workload_wifi_fragmentation_plan()
        fragmentation_samples.append(global_perf_counter_ns() - start)
        checksum = _mix(checksum, fragments.sequence_number)
        checksum = _mix(checksum, fragments.payload_capacity_octets)
        checksum = _mix(checksum, len(fragments.payload_octets))
        checksum = _mix(checksum, fragments.payload_offsets[0])
        checksum = _mix(checksum, fragments.payload_octets[len(fragments.payload_octets) - 1])
        keep(fragments)

        start = global_perf_counter_ns()
        var reassembly = _workload_wifi_reassembly_plan(controls_span, more_span, payloads_span)
        reassembly_samples.append(global_perf_counter_ns() - start)
        checksum = _mix(checksum, reassembly.sequence_number)
        checksum = _mix(checksum, reassembly.total_msdu_octets)
        checksum = _mix(checksum, len(reassembly.payload_offsets))
        checksum = _mix(checksum, reassembly.payload_offsets[len(reassembly.payload_offsets) - 1])
        keep(reassembly)

        start = global_perf_counter_ns()
        var crc = _workload_wifi_ampdu_delimiter_crc8()
        crc_samples.append(global_perf_counter_ns() - start)
        checksum = _mix(checksum, crc)
        keep(crc)

        start = global_perf_counter_ns()
        var serialized = _workload_wifi_ampdu_delimiter_serialize()
        serialize_samples.append(global_perf_counter_ns() - start)
        checksum = _mix(checksum, len(serialized))
        checksum = _mix(checksum, Int(serialized[0]))
        checksum = _mix(checksum, Int(serialized[len(serialized) - 1]))
        keep(serialized)

        start = global_perf_counter_ns()
        var parsed = _workload_wifi_ampdu_delimiter_parse(parser_span)
        parse_samples.append(global_perf_counter_ns() - start)
        checksum = _mix(checksum, parsed.profile)
        checksum = _mix(checksum, parsed.first_word)
        checksum = _mix(checksum, parsed.mpdu_length_octets)
        checksum = _mix(checksum, 1 if parsed.eof else 0)
        checksum = _mix(checksum, parsed.crc)
        checksum = _mix(checksum, parsed.padding_octets)
        checksum = _mix(checksum, parsed.next_delimiter_delta_octets)
        keep(parsed)

    print_benchmark_metadata()
    print("wifi_mac_fragmentation_backend: scalar-cpu-reference")
    report_timing_samples(
        "wifi_fragmentation_plan",
        fragmentation_samples,
        _WARMUPS,
        1,
        "fragment_plan",
    )
    report_timing_samples(
        "wifi_reassembly_plan",
        reassembly_samples,
        _WARMUPS,
        1,
        "reassembly_plan",
    )
    report_timing_samples(
        "wifi_ampdu_delimiter_crc8",
        crc_samples,
        _WARMUPS,
        1,
        "protected_word",
    )
    report_timing_samples(
        "wifi_ampdu_delimiter_serialize",
        serialize_samples,
        _WARMUPS,
        1,
        "delimiter",
    )
    report_timing_samples(
        "wifi_ampdu_delimiter_parse",
        parse_samples,
        _WARMUPS,
        1,
        "delimiter",
    )
    keep(checksum)
    print("wifi_mac_fragmentation_retained_checksum:", checksum)
