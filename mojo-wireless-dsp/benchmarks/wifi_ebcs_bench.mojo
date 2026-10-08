"""Attributable CPU timings for bounded IEEE 802.11 EBCS TIM Mode 1.

Every public algorithm has a separate ``@no_inline`` batched workload, three
untimed warmups, and nine independent samples.  Content-ID sets, timing
configs, Mode-1 content, serialized elements, parsed elements, query IDs, and
their Span views are all constructed outside timed regions.  Owned results
are retained with O(1) length/endpoint fingerprints plus ``keep`` so a second
linear output scan does not contaminate the API denominator.  No dispatcher
is timed.  Mode 0 is outside the benchmark because its adopted Length clauses
conflict and the bounded API explicitly rejects it.
"""

from std.benchmark import black_box, keep
from std.collections import Span
from std.time import global_perf_counter_ns
from wireless_dsp.benchmarking import (
    print_benchmark_metadata,
    report_timing_samples,
)
from wireless_dsp.wireless.wifi.ebcs import (
    WifiEBCSTIMConfig,
    WifiEBCSTIMContent,
    WifiEBCSTIMElement,
    wifi_ebcs_tim_content_id_list_from_ids,
    wifi_ebcs_dtim_next_count,
    wifi_ebcs_tim_element_serialize_mode_one,
    wifi_ebcs_tim_element_parse_mode_one,
    wifi_ebcs_tim_mode_one_content_id_buffered,
)


comptime _WARMUPS = 3
comptime _SAMPLES = 9
comptime _CONTENT_BATCH = 512
comptime _COUNTDOWN_BATCH = 8192
comptime _ELEMENT_BATCH = 1024
comptime _MEMBERSHIP_BATCH = 8192


def _mix(checksum: UInt64, value: Int) -> UInt64:
    return (checksum ^ UInt64(value + 4096)) * UInt64(1099511628211)


@no_inline
def _content_id_list_from_ids_workload(
    iterations: Int, content_ids: Span[Int, ...]
) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for operation in range(iterations):
        var retained_operation = black_box(operation)
        var content = wifi_ebcs_tim_content_id_list_from_ids(content_ids)
        checksum = _mix(
            checksum, content.bitmap_mode + retained_operation
        )
        checksum = _mix(checksum, content.bitmap_offset)
        checksum = _mix(checksum, len(content.content_id_bitmap))
        checksum = _mix(checksum, Int(content.content_id_bitmap[0]))
        checksum = _mix(
            checksum,
            Int(content.content_id_bitmap[len(content.content_id_bitmap) - 1]),
        )
        keep(content)
    return checksum


@no_inline
def _dtim_next_count_workload(
    iterations: Int, config: WifiEBCSTIMConfig
) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for operation in range(iterations):
        var retained_operation = black_box(operation)
        var next_count = wifi_ebcs_dtim_next_count(config)
        checksum = _mix(checksum, next_count + retained_operation)
        keep(next_count)
    return checksum


@no_inline
def _element_serialize_workload(
    iterations: Int,
    config: WifiEBCSTIMConfig,
    content: WifiEBCSTIMContent,
) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for operation in range(iterations):
        var element = wifi_ebcs_tim_element_serialize_mode_one(
            config, content
        )
        checksum = _mix(checksum, len(element) + operation)
        checksum = _mix(checksum, Int(element[0]))
        checksum = _mix(checksum, Int(element[len(element) - 1]))
        keep(element)
    return checksum


@no_inline
def _element_parse_workload(
    iterations: Int, element: Span[UInt8, ...]
) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for operation in range(iterations):
        var parsed = wifi_ebcs_tim_element_parse_mode_one(element)
        checksum = _mix(checksum, parsed.dtim_count + operation)
        checksum = _mix(checksum, parsed.dtim_period)
        checksum = _mix(checksum, parsed.bitmap_mode)
        checksum = _mix(checksum, parsed.bitmap_offset)
        checksum = _mix(checksum, len(parsed.content_id_bitmap))
        checksum = _mix(checksum, Int(parsed.content_id_bitmap[0]))
        checksum = _mix(
            checksum,
            Int(parsed.content_id_bitmap[len(parsed.content_id_bitmap) - 1]),
        )
        keep(parsed)
    return checksum


@no_inline
def _content_id_buffered_workload(
    iterations: Int,
    element: WifiEBCSTIMElement,
    content_ids: Span[Int, ...],
) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for operation in range(iterations):
        var content_id = content_ids[black_box(operation % len(content_ids))]
        var buffered = wifi_ebcs_tim_mode_one_content_id_buffered(
            element, content_id
        )
        checksum = _mix(
            checksum, (1 if buffered else 0) + content_id + operation
        )
        keep(buffered)
    return checksum


def main() raises:
    var sparse_ids: List[Int] = [1, 17, 63, 129, 200, 255]
    var config = WifiEBCSTIMConfig(2, 7)
    var content = wifi_ebcs_tim_content_id_list_from_ids(
        Span(sparse_ids)
    )
    var wire = wifi_ebcs_tim_element_serialize_mode_one(config, content)
    var parsed = wifi_ebcs_tim_element_parse_mode_one(Span(wire))
    var query_ids = List[Int](capacity=255)
    for content_id in range(1, 256):
        query_ids.append(content_id)
    var sparse_ids_span = Span(sparse_ids)
    var wire_span = Span(wire)
    var query_ids_span = Span(query_ids)

    for _ in range(_WARMUPS):
        keep(_content_id_list_from_ids_workload(
            _CONTENT_BATCH, sparse_ids_span
        ))
        keep(_dtim_next_count_workload(_COUNTDOWN_BATCH, config))
        keep(_element_serialize_workload(
            _ELEMENT_BATCH, config, content
        ))
        keep(_element_parse_workload(_ELEMENT_BATCH, wire_span))
        keep(_content_id_buffered_workload(
            _MEMBERSHIP_BATCH, parsed, query_ids_span
        ))

    var content_samples = List[UInt64](capacity=_SAMPLES)
    var countdown_samples = List[UInt64](capacity=_SAMPLES)
    var serialize_samples = List[UInt64](capacity=_SAMPLES)
    var parse_samples = List[UInt64](capacity=_SAMPLES)
    var membership_samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)

    for sample in range(_SAMPLES):
        var start = global_perf_counter_ns()
        var content_checksum = _content_id_list_from_ids_workload(
            _CONTENT_BATCH, sparse_ids_span
        )
        content_samples.append(global_perf_counter_ns() - start)
        checksum = _mix(
            checksum, Int(content_checksum & UInt64(Int.MAX)) + sample
        )
        keep(content_checksum)

        start = global_perf_counter_ns()
        var countdown_checksum = _dtim_next_count_workload(
            _COUNTDOWN_BATCH, config
        )
        countdown_samples.append(global_perf_counter_ns() - start)
        checksum = _mix(
            checksum, Int(countdown_checksum & UInt64(Int.MAX)) + sample
        )
        keep(countdown_checksum)

        start = global_perf_counter_ns()
        var serialize_checksum = _element_serialize_workload(
            _ELEMENT_BATCH, config, content
        )
        serialize_samples.append(global_perf_counter_ns() - start)
        checksum = _mix(
            checksum, Int(serialize_checksum & UInt64(Int.MAX)) + sample
        )
        keep(serialize_checksum)

        start = global_perf_counter_ns()
        var parse_checksum = _element_parse_workload(
            _ELEMENT_BATCH, wire_span
        )
        parse_samples.append(global_perf_counter_ns() - start)
        checksum = _mix(
            checksum, Int(parse_checksum & UInt64(Int.MAX)) + sample
        )
        keep(parse_checksum)

        start = global_perf_counter_ns()
        var membership_checksum = _content_id_buffered_workload(
            _MEMBERSHIP_BATCH, parsed, query_ids_span
        )
        membership_samples.append(global_perf_counter_ns() - start)
        checksum = _mix(
            checksum, Int(membership_checksum & UInt64(Int.MAX)) + sample
        )
        keep(membership_checksum)

    print_benchmark_metadata()
    print("wifi_ebcs_backend:", "scalar-cpu-mode1-bounded-reference")
    print(
        "wifi_ebcs_baseline:",
        "IEEE-802.11-2024-Clause-34-EBCS-TIM-Mode1-finite-slice",
    )
    report_timing_samples(
        "wifi_ebcs_tim_content_id_list_from_ids",
        content_samples,
        _WARMUPS,
        _CONTENT_BATCH,
        "strict_mode1_content_set",
    )
    report_timing_samples(
        "wifi_ebcs_dtim_next_count",
        countdown_samples,
        _WARMUPS,
        _COUNTDOWN_BATCH,
        "count_transition",
    )
    report_timing_samples(
        "wifi_ebcs_tim_element_serialize_mode_one",
        serialize_samples,
        _WARMUPS,
        _ELEMENT_BATCH,
        "element",
    )
    report_timing_samples(
        "wifi_ebcs_tim_element_parse_mode_one",
        parse_samples,
        _WARMUPS,
        _ELEMENT_BATCH,
        "element",
    )
    report_timing_samples(
        "wifi_ebcs_tim_mode_one_content_id_buffered",
        membership_samples,
        _WARMUPS,
        _MEMBERSHIP_BATCH,
        "content_id_query",
    )
    keep(checksum)
    print("wifi_ebcs_retained_checksum:", checksum)
