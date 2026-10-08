"""Per-API CPU latency evidence for deterministic IEEE 802.11 MAC math.

Every public algorithm has an attributable timing distribution with three
untimed warmups and nine independent samples.  Input construction and
mutation occur outside timed regions, and output-dependent checksums retain
all work.  Each denominator is one exact API call.
"""

from std.benchmark import keep
from std.collections import Span
from std.time import global_perf_counter_ns
from wireless_dsp.benchmarking import (
    print_benchmark_metadata,
    report_timing_samples,
)
from wireless_dsp.wireless.wifi.mac_algorithms import (
    WifiContentionConfig,
    WifiContentionState,
    WifiSequenceControlFields,
    WifiBlockAckReorderPlan,
    WifiAMSDUPlan,
    WifiAMPDUPlan,
    wifi_aifs_duration,
    wifi_backoff_select_slots,
    wifi_backoff_after_idle_slots,
    wifi_retry_contention_after_failure,
    wifi_retry_contention_after_success,
    wifi_nav_update_end,
    wifi_nav_remaining,
    wifi_sequence_control_pack,
    wifi_sequence_control_unpack,
    wifi_sequence_number_add,
    wifi_sequence_number_distance,
    wifi_block_ack_reorder_plan,
    wifi_amsdu_plan,
    wifi_ampdu_maximum_octets,
    wifi_ampdu_plan,
)


comptime _WARMUPS = 3
comptime _SAMPLES = 9


def _mix(checksum: UInt64, value: Int) -> UInt64:
    return (checksum ^ UInt64(value)) * UInt64(1099511628211)


@no_inline
def _workload_wifi_aifs_duration() raises -> Int:
    return wifi_aifs_duration(16, 9, 3)


@no_inline
def _workload_wifi_backoff_select_slots(
    config: WifiContentionConfig, state: WifiContentionState,
) raises -> Int:
    return wifi_backoff_select_slots(config, state, 5)


@no_inline
def _workload_wifi_backoff_after_idle_slots() raises -> Int:
    return wifi_backoff_after_idle_slots(15, 7)


@no_inline
def _workload_wifi_retry_contention_after_failure(
    config: WifiContentionConfig, state: WifiContentionState,
) raises -> WifiContentionState:
    return wifi_retry_contention_after_failure(config, state)


@no_inline
def _workload_wifi_retry_contention_after_success(
    config: WifiContentionConfig, state: WifiContentionState,
) raises -> WifiContentionState:
    return wifi_retry_contention_after_success(config, state)


@no_inline
def _workload_wifi_nav_update_end() raises -> Int:
    return wifi_nav_update_end(1000, 900, 200)


@no_inline
def _workload_wifi_nav_remaining() raises -> Int:
    return wifi_nav_remaining(900, 1100)


@no_inline
def _workload_wifi_sequence_control_pack() raises -> Int:
    return wifi_sequence_control_pack(100, 3)


@no_inline
def _workload_wifi_sequence_control_unpack() raises -> WifiSequenceControlFields:
    return wifi_sequence_control_unpack(0x1234)


@no_inline
def _workload_wifi_sequence_number_add() raises -> Int:
    return wifi_sequence_number_add(4090, 10)


@no_inline
def _workload_wifi_sequence_number_distance() raises -> Int:
    return wifi_sequence_number_distance(4090, 7)


@no_inline
def _workload_wifi_block_ack_reorder_plan() raises -> WifiBlockAckReorderPlan:
    return wifi_block_ack_reorder_plan(4090, 64, 100)


@no_inline
def _workload_wifi_amsdu_plan(
    lengths: Span[Int, ...],
) raises -> WifiAMSDUPlan:
    return wifi_amsdu_plan(lengths, 3839)


@no_inline
def _workload_wifi_ampdu_maximum_octets() raises -> Int:
    return wifi_ampdu_maximum_octets(3)


@no_inline
def _workload_wifi_ampdu_plan(
    lengths: Span[Int, ...],
) raises -> WifiAMPDUPlan:
    return wifi_ampdu_plan(lengths, 0)


def main() raises:
    var config = WifiContentionConfig(15, 1023, 7)
    var initial = WifiContentionState(15, 0)
    var failed = WifiContentionState(63, 2)
    var msdu_lengths: List[Int] = [256, 511, 1024]
    var mpdu_lengths: List[Int] = [512, 1023, 2048]

    var msdu_span = Span(msdu_lengths)
    var mpdu_span = Span(mpdu_lengths)
    for _ in range(_WARMUPS):
        keep(_workload_wifi_aifs_duration())
        keep(_workload_wifi_backoff_select_slots(config, initial))
        keep(_workload_wifi_backoff_after_idle_slots())
        keep(_workload_wifi_retry_contention_after_failure(config, failed))
        keep(_workload_wifi_retry_contention_after_success(config, failed))
        keep(_workload_wifi_nav_update_end())
        keep(_workload_wifi_nav_remaining())
        keep(_workload_wifi_sequence_control_pack())
        keep(_workload_wifi_sequence_control_unpack())
        keep(_workload_wifi_sequence_number_add())
        keep(_workload_wifi_sequence_number_distance())
        keep(_workload_wifi_block_ack_reorder_plan())
        keep(_workload_wifi_amsdu_plan(msdu_span))
        keep(_workload_wifi_ampdu_maximum_octets())
        keep(_workload_wifi_ampdu_plan(mpdu_span))

    var aifs_samples = List[UInt64](capacity=_SAMPLES)
    var backoff_select_samples = List[UInt64](capacity=_SAMPLES)
    var backoff_countdown_samples = List[UInt64](capacity=_SAMPLES)
    var retry_failure_samples = List[UInt64](capacity=_SAMPLES)
    var retry_success_samples = List[UInt64](capacity=_SAMPLES)
    var nav_update_samples = List[UInt64](capacity=_SAMPLES)
    var nav_remaining_samples = List[UInt64](capacity=_SAMPLES)
    var sequence_pack_samples = List[UInt64](capacity=_SAMPLES)
    var sequence_unpack_samples = List[UInt64](capacity=_SAMPLES)
    var sequence_add_samples = List[UInt64](capacity=_SAMPLES)
    var sequence_distance_samples = List[UInt64](capacity=_SAMPLES)
    var block_ack_samples = List[UInt64](capacity=_SAMPLES)
    var amsdu_samples = List[UInt64](capacity=_SAMPLES)
    var ampdu_max_samples = List[UInt64](capacity=_SAMPLES)
    var ampdu_plan_samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(14695981039346656037)

    for _ in range(_SAMPLES):
        var start = global_perf_counter_ns()
        var aifs = _workload_wifi_aifs_duration()
        aifs_samples.append(global_perf_counter_ns() - start)
        keep(aifs)
        checksum = _mix(checksum, aifs)

        start = global_perf_counter_ns()
        var selected = _workload_wifi_backoff_select_slots(config, initial)
        backoff_select_samples.append(global_perf_counter_ns() - start)
        keep(selected)
        checksum = _mix(checksum, selected)

        start = global_perf_counter_ns()
        var remaining_backoff = _workload_wifi_backoff_after_idle_slots()
        backoff_countdown_samples.append(global_perf_counter_ns() - start)
        keep(remaining_backoff)
        checksum = _mix(checksum, remaining_backoff)

        start = global_perf_counter_ns()
        var failure_state = _workload_wifi_retry_contention_after_failure(config, failed)
        retry_failure_samples.append(global_perf_counter_ns() - start)
        keep(failure_state)
        checksum = _mix(checksum, failure_state.contention_window)
        checksum = _mix(checksum, failure_state.retry_count)

        start = global_perf_counter_ns()
        var success_state = _workload_wifi_retry_contention_after_success(config, failed)
        retry_success_samples.append(global_perf_counter_ns() - start)
        keep(success_state)
        checksum = _mix(checksum, success_state.contention_window)
        checksum = _mix(checksum, success_state.retry_count)

        start = global_perf_counter_ns()
        var nav_end = _workload_wifi_nav_update_end()
        nav_update_samples.append(global_perf_counter_ns() - start)
        keep(nav_end)
        checksum = _mix(checksum, nav_end)

        start = global_perf_counter_ns()
        var nav_left = _workload_wifi_nav_remaining()
        nav_remaining_samples.append(global_perf_counter_ns() - start)
        keep(nav_left)
        checksum = _mix(checksum, nav_left)

        start = global_perf_counter_ns()
        var packed = _workload_wifi_sequence_control_pack()
        sequence_pack_samples.append(global_perf_counter_ns() - start)
        keep(packed)
        checksum = _mix(checksum, packed)

        start = global_perf_counter_ns()
        var unpacked = _workload_wifi_sequence_control_unpack()
        sequence_unpack_samples.append(global_perf_counter_ns() - start)
        keep(unpacked)
        checksum = _mix(checksum, unpacked.sequence_number)
        checksum = _mix(checksum, unpacked.fragment_number)

        start = global_perf_counter_ns()
        var sequence_added = _workload_wifi_sequence_number_add()
        sequence_add_samples.append(global_perf_counter_ns() - start)
        keep(sequence_added)
        checksum = _mix(checksum, sequence_added)

        start = global_perf_counter_ns()
        var sequence_distance = _workload_wifi_sequence_number_distance()
        sequence_distance_samples.append(global_perf_counter_ns() - start)
        keep(sequence_distance)
        checksum = _mix(checksum, sequence_distance)

        start = global_perf_counter_ns()
        var reorder = _workload_wifi_block_ack_reorder_plan()
        block_ack_samples.append(global_perf_counter_ns() - start)
        keep(reorder)
        checksum = _mix(checksum, reorder.action)
        checksum = _mix(checksum, reorder.next_window_start)
        checksum = _mix(checksum, reorder.buffer_index)

        start = global_perf_counter_ns()
        var amsdu = _workload_wifi_amsdu_plan(msdu_span)
        amsdu_samples.append(global_perf_counter_ns() - start)
        keep(amsdu)
        checksum = _mix(checksum, amsdu.total_octets)
        checksum = _mix(checksum, amsdu.msdu_offsets[2])
        checksum = _mix(checksum, amsdu.padding_octets[0])

        start = global_perf_counter_ns()
        var maximum = _workload_wifi_ampdu_maximum_octets()
        ampdu_max_samples.append(global_perf_counter_ns() - start)
        keep(maximum)
        checksum = _mix(checksum, maximum)

        start = global_perf_counter_ns()
        var ampdu = _workload_wifi_ampdu_plan(mpdu_span)
        ampdu_plan_samples.append(global_perf_counter_ns() - start)
        keep(ampdu)
        checksum = _mix(checksum, ampdu.total_octets)
        checksum = _mix(checksum, ampdu.mpdu_offsets[2])
        checksum = _mix(checksum, ampdu.delimiter_length_low_12[0])

    print_benchmark_metadata()
    report_timing_samples(
        "wifi_mac_aifs_duration",
        aifs_samples,
        _WARMUPS,
        1,
        "api_call",
    )
    report_timing_samples(
        "wifi_mac_backoff_select_slots",
        backoff_select_samples,
        _WARMUPS,
        1,
        "api_call",
    )
    report_timing_samples(
        "wifi_mac_backoff_after_idle_slots",
        backoff_countdown_samples,
        _WARMUPS,
        1,
        "api_call",
    )
    report_timing_samples(
        "wifi_mac_retry_after_failure",
        retry_failure_samples,
        _WARMUPS,
        1,
        "api_call",
    )
    report_timing_samples(
        "wifi_mac_retry_after_success",
        retry_success_samples,
        _WARMUPS,
        1,
        "api_call",
    )
    report_timing_samples(
        "wifi_mac_nav_update_end",
        nav_update_samples,
        _WARMUPS,
        1,
        "api_call",
    )
    report_timing_samples(
        "wifi_mac_nav_remaining",
        nav_remaining_samples,
        _WARMUPS,
        1,
        "api_call",
    )
    report_timing_samples(
        "wifi_mac_sequence_control_pack",
        sequence_pack_samples,
        _WARMUPS,
        1,
        "api_call",
    )
    report_timing_samples(
        "wifi_mac_sequence_control_unpack",
        sequence_unpack_samples,
        _WARMUPS,
        1,
        "api_call",
    )
    report_timing_samples(
        "wifi_mac_sequence_number_add",
        sequence_add_samples,
        _WARMUPS,
        1,
        "api_call",
    )
    report_timing_samples(
        "wifi_mac_sequence_number_distance",
        sequence_distance_samples,
        _WARMUPS,
        1,
        "api_call",
    )
    report_timing_samples(
        "wifi_mac_block_ack_reorder_plan",
        block_ack_samples,
        _WARMUPS,
        1,
        "api_call",
    )
    report_timing_samples(
        "wifi_mac_amsdu_plan",
        amsdu_samples,
        _WARMUPS,
        1,
        "api_call",
    )
    report_timing_samples(
        "wifi_mac_ampdu_maximum_octets",
        ampdu_max_samples,
        _WARMUPS,
        1,
        "api_call",
    )
    report_timing_samples(
        "wifi_mac_ampdu_plan",
        ampdu_plan_samples,
        _WARMUPS,
        1,
        "api_call",
    )
    keep(checksum)
    print("wifi_mac_retained_checksum:", checksum)
