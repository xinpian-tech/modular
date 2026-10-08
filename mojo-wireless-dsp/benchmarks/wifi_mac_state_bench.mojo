"""Attributable batched CPU timings for bounded Wi-Fi MAC state.

Every public algorithm has a separate distribution with three untimed
warmups, nine timed samples, 2048 operations per sample, shared host/compiler
metadata, median/nearest-rank p95 reporting, and an output-dependent retained
checksum.  No RF, accelerator, or randomized scheduler work is included.
"""

from std.benchmark import black_box, keep
from std.collections import Span
from std.time import global_perf_counter_ns
from wireless_dsp.benchmarking import (
    print_benchmark_metadata,
    report_timing_samples,
)
from wireless_dsp.wireless.wifi.mac_state import (
    WifiLegacyPowerSaveProfile,
    wifi_dtim_count_advance,
    wifi_tim_method_a_encode,
    wifi_tim_aid_buffered,
    wifi_tim_indication,
    wifi_legacy_ps_listen_required,
    wifi_legacy_ps_next_listen_tbtt,
    wifi_ps_poll_duration_id_encode,
    wifi_ps_poll_duration_id_decode,
    wifi_legacy_ps_tim_decision,
)


comptime _WARMUPS = 3
comptime _SAMPLES = 9
comptime _BATCH = 2048


def _mix(checksum: UInt64, value: Int) -> UInt64:
    return checksum * UInt64(1099511628211) ^ UInt64(value + 1)


@no_inline
def _dtim_workload(iterations: Int, salt: Int) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for iteration in range(iterations):
        var period = 1 + ((iteration + salt) % 255)
        var count = (iteration * 7 + salt) % period
        var advanced = wifi_dtim_count_advance(
            black_box(count),
            black_box(period),
            black_box(iteration + salt),
        )
        checksum = _mix(checksum, advanced + iteration)
    return checksum


@no_inline
def _tim_encode_workload(
    iterations: Int, salt: Int, buffered_aids: List[Int]
) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for iteration in range(iterations):
        var count = (iteration + salt) % 3
        var element = wifi_tim_method_a_encode(
            Span(buffered_aids),
            black_box(count),
            black_box(3),
            group_addressed_buffered=black_box(
                count == 0 and (iteration & 1) == 0
            ),
        )
        checksum = _mix(checksum, element.bitmap_control + iteration)
        checksum = _mix(checksum, len(element.partial_virtual_bitmap))
        checksum = _mix(
            checksum,
            Int(
                element.partial_virtual_bitmap[
                    len(element.partial_virtual_bitmap) - 1
                ]
            ),
        )
    return checksum


@no_inline
def _aid_lookup_workload(
    iterations: Int, salt: Int, pvb: List[UInt8]
) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for iteration in range(iterations):
        var aid = 40 + ((iteration + salt) & 3)
        var buffered = wifi_tim_aid_buffered(
            black_box(4), Span(pvb), black_box(aid)
        )
        checksum = _mix(checksum, iteration + (1 if buffered else 0))
    return checksum


@no_inline
def _tim_indication_workload(
    iterations: Int, salt: Int, pvb: List[UInt8]
) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for iteration in range(iterations):
        var count = (iteration + salt) % 3
        var control = 4 | (1 if count == 0 and (iteration & 1) == 0 else 0)
        var indication = wifi_tim_indication(
            black_box(count),
            black_box(3),
            black_box(control),
            Span(pvb),
            black_box(42),
        )
        checksum = _mix(checksum, indication.next_dtim_count + iteration)
        checksum = _mix(
            checksum,
            1 if indication.individually_addressed_buffered else 0,
        )
        checksum = _mix(
            checksum, 1 if indication.group_addressed_buffered else 0
        )
    return checksum


@no_inline
def _listen_workload(
    iterations: Int, salt: Int, profile: WifiLegacyPowerSaveProfile
) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for iteration in range(iterations):
        var count = (iteration + salt) % 3
        var required = wifi_legacy_ps_listen_required(
            profile,
            black_box(1000 + iteration),
            black_box(count),
            black_box(3),
        )
        checksum = _mix(checksum, iteration + (1 if required else 0))
    return checksum


@no_inline
def _next_listen_workload(
    iterations: Int, salt: Int, profile: WifiLegacyPowerSaveProfile
) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for iteration in range(iterations):
        var count = (iteration + salt) % 3
        var selected = wifi_legacy_ps_next_listen_tbtt(
            profile,
            black_box(1000 + iteration),
            black_box(count),
            black_box(3),
        )
        checksum = _mix(checksum, selected + iteration)
    return checksum


@no_inline
def _ps_poll_encode_workload(iterations: Int, salt: Int) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for iteration in range(iterations):
        var aid = 1 + ((iteration + salt) % 2007)
        var encoded = wifi_ps_poll_duration_id_encode(black_box(aid))
        checksum = _mix(checksum, encoded + iteration)
    return checksum


@no_inline
def _ps_poll_decode_workload(iterations: Int, salt: Int) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for iteration in range(iterations):
        var duration_id = 0xC000 | (1 + ((iteration + salt) % 2007))
        var aid = wifi_ps_poll_duration_id_decode(black_box(duration_id))
        checksum = _mix(checksum, aid + iteration)
    return checksum


@no_inline
def _ps_decision_workload(
    iterations: Int,
    salt: Int,
    profile: WifiLegacyPowerSaveProfile,
    pvb: List[UInt8],
) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for iteration in range(iterations):
        var count = (iteration + salt) % 3
        var control = 4 | (1 if count == 0 and (iteration & 1) == 0 else 0)
        var decision = wifi_legacy_ps_tim_decision(
            profile,
            black_box(1000 + iteration),
            black_box(count),
            black_box(3),
            black_box(control),
            Span(pvb),
        )
        checksum = _mix(checksum, iteration + (1 if decision.listen_required else 0))
        checksum = _mix(
            checksum, 1 if decision.ps_poll_trigger_eligible else 0
        )
        checksum = _mix(
            checksum, 1 if decision.delivery_awake_required else 0
        )
    return checksum


def main() raises:
    var profile = WifiLegacyPowerSaveProfile(42, 7, 2, True)
    var buffered_aids: List[Int] = [1, 42, 90, 2007]
    var pvb: List[UInt8] = [UInt8(0), UInt8(4)]

    for _ in range(_WARMUPS):
        var salt = 324508639
        keep(_dtim_workload(_BATCH, salt))
        keep(_tim_encode_workload(_BATCH, salt, buffered_aids))
        keep(_aid_lookup_workload(_BATCH, salt, pvb))
        keep(_tim_indication_workload(_BATCH, salt, pvb))
        keep(_listen_workload(_BATCH, salt, profile))
        keep(_next_listen_workload(_BATCH, salt, profile))
        keep(_ps_poll_encode_workload(_BATCH, salt))
        keep(_ps_poll_decode_workload(_BATCH, salt))
        keep(_ps_decision_workload(_BATCH, salt, profile, pvb))

    var dtim_samples = List[UInt64](capacity=_SAMPLES)
    var tim_encode_samples = List[UInt64](capacity=_SAMPLES)
    var aid_lookup_samples = List[UInt64](capacity=_SAMPLES)
    var indication_samples = List[UInt64](capacity=_SAMPLES)
    var listen_samples = List[UInt64](capacity=_SAMPLES)
    var next_listen_samples = List[UInt64](capacity=_SAMPLES)
    var ps_poll_encode_samples = List[UInt64](capacity=_SAMPLES)
    var ps_poll_decode_samples = List[UInt64](capacity=_SAMPLES)
    var decision_samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)

    for _ in range(_SAMPLES):
        var salt = 324508639
        var start = global_perf_counter_ns()
        var dtim = _dtim_workload(_BATCH, salt)
        dtim_samples.append(global_perf_counter_ns() - start)
        checksum = checksum * UInt64(1099511628211) ^ dtim
        keep(dtim)

        start = global_perf_counter_ns()
        var tim_encode = _tim_encode_workload(_BATCH, salt, buffered_aids)
        tim_encode_samples.append(global_perf_counter_ns() - start)
        checksum = checksum * UInt64(1099511628211) ^ tim_encode
        keep(tim_encode)

        start = global_perf_counter_ns()
        var aid_lookup = _aid_lookup_workload(_BATCH, salt, pvb)
        aid_lookup_samples.append(global_perf_counter_ns() - start)
        checksum = checksum * UInt64(1099511628211) ^ aid_lookup
        keep(aid_lookup)

        start = global_perf_counter_ns()
        var indication = _tim_indication_workload(_BATCH, salt, pvb)
        indication_samples.append(global_perf_counter_ns() - start)
        checksum = checksum * UInt64(1099511628211) ^ indication
        keep(indication)

        start = global_perf_counter_ns()
        var listen = _listen_workload(_BATCH, salt, profile)
        listen_samples.append(global_perf_counter_ns() - start)
        checksum = checksum * UInt64(1099511628211) ^ listen
        keep(listen)

        start = global_perf_counter_ns()
        var next_listen = _next_listen_workload(_BATCH, salt, profile)
        next_listen_samples.append(global_perf_counter_ns() - start)
        checksum = checksum * UInt64(1099511628211) ^ next_listen
        keep(next_listen)

        start = global_perf_counter_ns()
        var ps_poll_encode = _ps_poll_encode_workload(_BATCH, salt)
        ps_poll_encode_samples.append(global_perf_counter_ns() - start)
        checksum = checksum * UInt64(1099511628211) ^ ps_poll_encode
        keep(ps_poll_encode)

        start = global_perf_counter_ns()
        var ps_poll_decode = _ps_poll_decode_workload(_BATCH, salt)
        ps_poll_decode_samples.append(global_perf_counter_ns() - start)
        checksum = checksum * UInt64(1099511628211) ^ ps_poll_decode
        keep(ps_poll_decode)

        start = global_perf_counter_ns()
        var decision = _ps_decision_workload(
            _BATCH, salt, profile, pvb
        )
        decision_samples.append(global_perf_counter_ns() - start)
        checksum = checksum * UInt64(1099511628211) ^ decision
        keep(decision)

    print_benchmark_metadata()
    print("wifi_mac_state_backend: scalar-cpu-reference")
    report_timing_samples(
        "wifi_dtim_count_advance", dtim_samples, _WARMUPS, _BATCH, "dtim_transition"
    )
    report_timing_samples(
        "wifi_tim_method_a_encode",
        tim_encode_samples,
        _WARMUPS,
        _BATCH,
        "tim_element",
    )
    report_timing_samples(
        "wifi_tim_aid_buffered",
        aid_lookup_samples,
        _WARMUPS,
        _BATCH,
        "aid_lookup",
    )
    report_timing_samples(
        "wifi_tim_indication",
        indication_samples,
        _WARMUPS,
        _BATCH,
        "tim_decision",
    )
    report_timing_samples(
        "wifi_legacy_ps_listen_required",
        listen_samples,
        _WARMUPS,
        _BATCH,
        "tbtt_decision",
    )
    report_timing_samples(
        "wifi_legacy_ps_next_listen_tbtt",
        next_listen_samples,
        _WARMUPS,
        _BATCH,
        "tbtt_schedule",
    )
    report_timing_samples(
        "wifi_ps_poll_duration_id_encode",
        ps_poll_encode_samples,
        _WARMUPS,
        _BATCH,
        "duration_id",
    )
    report_timing_samples(
        "wifi_ps_poll_duration_id_decode",
        ps_poll_decode_samples,
        _WARMUPS,
        _BATCH,
        "duration_id",
    )
    report_timing_samples(
        "wifi_legacy_ps_tim_decision",
        decision_samples,
        _WARMUPS,
        _BATCH,
        "ps_state_decision",
    )
    print("wifi_mac_state_retained_checksum:", checksum)
