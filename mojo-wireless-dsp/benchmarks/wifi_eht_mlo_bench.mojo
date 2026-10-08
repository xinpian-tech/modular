"""Attributable CPU timings for bounded IEEE 802.11be-2024 EHT MLO.

Every public algorithm has an independent distribution with three untimed
warmups, nine odd timed samples, 2048 calls per sample, median/nearest-rank
p95/ns-per-call reporting, full output consumption, and one retained checksum.
"""

from std.benchmark import black_box, keep
from std.time import global_perf_counter_ns
from wireless_dsp.benchmarking import (
    print_benchmark_metadata,
    report_timing_samples,
)
from wireless_dsp.wireless.wifi.eht_mlo import (
    WIFI_EHT_MLO_DIRECTION_DOWNLINK,
    WIFI_EHT_MLO_DIRECTION_UPLINK,
    WIFI_EHT_MLO_DIRECTION_BOTH,
    WifiEhtTidToLinkElement,
    WifiEhtMloMappingState,
    wifi_eht_mlo_tid_to_link_encode,
    wifi_eht_mlo_tid_to_link_decode,
    wifi_eht_mlo_default_mapping_state,
    wifi_eht_mlo_apply_tid_to_link_element,
    wifi_eht_mlo_tid_link_state,
    wifi_eht_mlo_enabled_links,
    wifi_eht_mlo_eml_timing_decode,
    wifi_eht_mlo_mapping_switch_time_field,
    wifi_eht_mlo_expected_duration_field,
    wifi_eht_mlo_expected_duration_us,
)


comptime _WARMUPS = 3
comptime _SAMPLES = 9
comptime _BATCH = 2048
comptime _FIXED_SALT = 0x5EED_11BE


def _mix(checksum: UInt64, value: Int) -> UInt64:
    return checksum * UInt64(1099511628211) ^ UInt64(value + 1)


def _mapping_element() -> WifiEhtTidToLinkElement:
    var maps = List[Int](length=8, fill=0)
    maps[0] = 0x0001
    maps[2] = 0x0004
    maps[4] = 0x0020
    maps[6] = 0x4000
    return WifiEhtTidToLinkElement(
        WIFI_EHT_MLO_DIRECTION_BOTH,
        False,
        True,
        0x1234,
        True,
        0x010203,
        2,
        0x55,
        maps ^,
    )


def _mapping_state(setup: Int) -> WifiEhtMloMappingState:
    var down = List[Int](length=8, fill=setup)
    var up = List[Int](length=8, fill=setup)
    down[0] = 0x0001
    down[2] = 0x0004
    down[4] = 0x0020
    down[6] = 0x4000
    return WifiEhtMloMappingState(down ^, up ^)


@no_inline
def _encode_workload(
    iterations: Int, salt: Int, element: WifiEhtTidToLinkElement
) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for iteration in range(iterations):
        var encoded = wifi_eht_mlo_tid_to_link_encode(element)
        var last = len(encoded) - 1
        checksum = _mix(checksum, len(encoded) + iteration + salt % 17)
        checksum = _mix(checksum, Int(encoded[0]))
        checksum = _mix(checksum, Int(encoded[len(encoded) // 2]))
        checksum = _mix(checksum, Int(encoded[last]))
        keep(encoded)
    return checksum


@no_inline
def _decode_workload(
    iterations: Int, salt: Int, payload: Span[UInt8, ...]
) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for iteration in range(iterations):
        var decoded = wifi_eht_mlo_tid_to_link_decode(payload)
        checksum = _mix(checksum, decoded.direction + iteration)
        checksum = _mix(checksum, Int(decoded.default_link_mapping))
        checksum = _mix(checksum, Int(decoded.mapping_switch_time_present))
        checksum = _mix(checksum, decoded.mapping_switch_time + salt % 19)
        checksum = _mix(checksum, Int(decoded.expected_duration_present))
        checksum = _mix(checksum, decoded.expected_duration_tu)
        checksum = _mix(checksum, decoded.link_mapping_size_octets)
        checksum = _mix(checksum, decoded.tid_presence_bitmap)
        checksum = _mix(checksum, len(decoded.tid_link_bitmaps))
        checksum = _mix(checksum, decoded.tid_link_bitmaps[0])
        checksum = _mix(checksum, decoded.tid_link_bitmaps[4])
        checksum = _mix(checksum, decoded.tid_link_bitmaps[7])
        keep(decoded)
    return checksum


@no_inline
def _default_state_workload(
    iterations: Int, salt: Int, setup: Int
) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for iteration in range(iterations):
        var state = wifi_eht_mlo_default_mapping_state(black_box(setup))
        checksum = _mix(checksum, len(state.downlink_tid_links) + iteration)
        checksum = _mix(checksum, state.downlink_tid_links[0])
        checksum = _mix(checksum, state.downlink_tid_links[7])
        checksum = _mix(checksum, len(state.uplink_tid_links) + salt % 23)
        checksum = _mix(checksum, state.uplink_tid_links[0])
        checksum = _mix(checksum, state.uplink_tid_links[7])
        keep(state)
    return checksum


@no_inline
def _apply_workload(
    iterations: Int,
    salt: Int,
    state: WifiEhtMloMappingState,
    element: WifiEhtTidToLinkElement,
    setup: Int,
) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for iteration in range(iterations):
        var updated = wifi_eht_mlo_apply_tid_to_link_element(
            state, element, black_box(setup)
        )
        checksum = _mix(checksum, len(updated.downlink_tid_links) + iteration)
        checksum = _mix(checksum, updated.downlink_tid_links[0])
        checksum = _mix(checksum, updated.downlink_tid_links[7])
        checksum = _mix(checksum, len(updated.uplink_tid_links) + salt % 29)
        checksum = _mix(checksum, updated.uplink_tid_links[0])
        checksum = _mix(checksum, updated.uplink_tid_links[7])
        keep(updated)
    return checksum


@no_inline
def _link_state_workload(
    iterations: Int,
    salt: Int,
    state: WifiEhtMloMappingState,
    setup: Int,
) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for iteration in range(iterations):
        var active = setup & (0x5555 if (iteration & 1) == 0 else 0x2AAA)
        var direction = (
            WIFI_EHT_MLO_DIRECTION_DOWNLINK
            if (iteration & 2) == 0
            else WIFI_EHT_MLO_DIRECTION_UPLINK
        )
        var result = wifi_eht_mlo_tid_link_state(
            state,
            setup,
            black_box(active),
            black_box((iteration + salt) & 7),
            black_box(direction),
        )
        checksum = _mix(checksum, result.mapped_links_bitmap + iteration)
        checksum = _mix(checksum, result.active_mapped_links_bitmap)
        checksum = _mix(
            checksum, 1 if result.frame_allowed_on_any_active_link else 0
        )
    return checksum


@no_inline
def _enabled_workload(
    iterations: Int,
    salt: Int,
    state: WifiEhtMloMappingState,
    setup: Int,
) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for iteration in range(iterations):
        var direction = (iteration + salt) % 3
        var enabled = wifi_eht_mlo_enabled_links(
            state, setup, black_box(direction)
        )
        checksum = _mix(checksum, enabled + iteration)
    return checksum


@no_inline
def _eml_timing_workload(iterations: Int, salt: Int) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for iteration in range(iterations):
        var mode = (iteration + salt) % 3
        var emlsr_int = 1 if mode != 1 else 0
        var emlmr_int = 1 if mode != 0 else 0
        var padding_code = (iteration + salt) % 5
        var transition_modulus = 5 if emlmr_int == 1 else 6
        var transition_code = (
            (iteration + 3 * salt) % transition_modulus
        )
        var timeout_code = (iteration + 5 * salt) % 11
        var field = (
            emlsr_int
            | (padding_code << 1)
            | (transition_code << 4)
            | (emlmr_int << 7)
            | (timeout_code << 11)
        )
        var timing = wifi_eht_mlo_eml_timing_decode(black_box(field))
        checksum = _mix(checksum, timing.padding_delay_us + iteration)
        checksum = _mix(checksum, timing.emlsr_transition_delay_us)
        checksum = _mix(checksum, timing.emlmr_transition_delay_us)
        checksum = _mix(checksum, timing.transition_timeout_us)
        checksum = _mix(checksum, 1 if timing.emlsr_supported else 0)
        checksum = _mix(checksum, 1 if timing.emlmr_supported else 0)
    return checksum


@no_inline
def _switch_time_workload(iterations: Int, salt: Int) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for iteration in range(iterations):
        var tsf = (
            UInt64(iteration + 1) * UInt64(1000003) + UInt64(salt)
        )
        if ((iteration + salt) & 1) != 0:
            tsf = tsf | (UInt64(1) << 63)
        var field = wifi_eht_mlo_mapping_switch_time_field(
            black_box(tsf)
        )
        checksum = _mix(checksum, field + iteration)
    return checksum


@no_inline
def _duration_encode_workload(iterations: Int, salt: Int) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for iteration in range(iterations):
        var duration_tu = (257 * iteration + salt) & 0xFFFFFF
        var field = wifi_eht_mlo_expected_duration_field(
            black_box(duration_tu * 1024)
        )
        checksum = _mix(checksum, field + iteration)
    return checksum


@no_inline
def _duration_decode_workload(iterations: Int, salt: Int) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for iteration in range(iterations):
        var field = (509 * iteration + salt) & 0xFFFFFF
        var duration = wifi_eht_mlo_expected_duration_us(black_box(field))
        checksum = _mix(checksum, duration + iteration)
    return checksum


def main() raises:
    var setup = 0x7FFF
    var element = _mapping_element()
    var payload = wifi_eht_mlo_tid_to_link_encode(element)
    var payload_span = Span(payload)
    var state = _mapping_state(setup)

    for warmup in range(_WARMUPS):
        var salt = _FIXED_SALT + warmup * 131
        keep(_encode_workload(_BATCH, salt, element))
        keep(_decode_workload(_BATCH, salt, payload_span))
        keep(_default_state_workload(_BATCH, salt, setup))
        keep(_apply_workload(_BATCH, salt, state, element, setup))
        keep(_link_state_workload(_BATCH, salt, state, setup))
        keep(_enabled_workload(_BATCH, salt, state, setup))
        keep(_eml_timing_workload(_BATCH, salt))
        keep(_switch_time_workload(_BATCH, salt))
        keep(_duration_encode_workload(_BATCH, salt))
        keep(_duration_decode_workload(_BATCH, salt))

    var encode_samples = List[UInt64](capacity=_SAMPLES)
    var decode_samples = List[UInt64](capacity=_SAMPLES)
    var default_samples = List[UInt64](capacity=_SAMPLES)
    var apply_samples = List[UInt64](capacity=_SAMPLES)
    var link_state_samples = List[UInt64](capacity=_SAMPLES)
    var enabled_samples = List[UInt64](capacity=_SAMPLES)
    var timing_samples = List[UInt64](capacity=_SAMPLES)
    var switch_samples = List[UInt64](capacity=_SAMPLES)
    var duration_encode_samples = List[UInt64](capacity=_SAMPLES)
    var duration_decode_samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)

    for sample in range(_SAMPLES):
        var salt = _FIXED_SALT + sample * 257
        var start = global_perf_counter_ns()
        var encoded = _encode_workload(_BATCH, salt, element)
        encode_samples.append(global_perf_counter_ns() - start)
        checksum = checksum * UInt64(1099511628211) ^ encoded
        keep(encoded)

        start = global_perf_counter_ns()
        var decoded = _decode_workload(_BATCH, salt, payload_span)
        decode_samples.append(global_perf_counter_ns() - start)
        checksum = checksum * UInt64(1099511628211) ^ decoded
        keep(decoded)

        start = global_perf_counter_ns()
        var default_state = _default_state_workload(_BATCH, salt, setup)
        default_samples.append(global_perf_counter_ns() - start)
        checksum = checksum * UInt64(1099511628211) ^ default_state
        keep(default_state)

        start = global_perf_counter_ns()
        var applied = _apply_workload(_BATCH, salt, state, element, setup)
        apply_samples.append(global_perf_counter_ns() - start)
        checksum = checksum * UInt64(1099511628211) ^ applied
        keep(applied)

        start = global_perf_counter_ns()
        var link_state = _link_state_workload(_BATCH, salt, state, setup)
        link_state_samples.append(global_perf_counter_ns() - start)
        checksum = checksum * UInt64(1099511628211) ^ link_state
        keep(link_state)

        start = global_perf_counter_ns()
        var enabled = _enabled_workload(_BATCH, salt, state, setup)
        enabled_samples.append(global_perf_counter_ns() - start)
        checksum = checksum * UInt64(1099511628211) ^ enabled
        keep(enabled)

        start = global_perf_counter_ns()
        var timing = _eml_timing_workload(_BATCH, salt)
        timing_samples.append(global_perf_counter_ns() - start)
        checksum = checksum * UInt64(1099511628211) ^ timing
        keep(timing)

        start = global_perf_counter_ns()
        var switch_time = _switch_time_workload(_BATCH, salt)
        switch_samples.append(global_perf_counter_ns() - start)
        checksum = checksum * UInt64(1099511628211) ^ switch_time
        keep(switch_time)

        start = global_perf_counter_ns()
        var duration_encode = _duration_encode_workload(_BATCH, salt)
        duration_encode_samples.append(global_perf_counter_ns() - start)
        checksum = checksum * UInt64(1099511628211) ^ duration_encode
        keep(duration_encode)

        start = global_perf_counter_ns()
        var duration_decode = _duration_decode_workload(_BATCH, salt)
        duration_decode_samples.append(global_perf_counter_ns() - start)
        checksum = checksum * UInt64(1099511628211) ^ duration_decode
        keep(duration_decode)

    print_benchmark_metadata()
    print("wifi_eht_mlo_backend: scalar-cpu-reference")
    print("wifi_eht_mlo_standard: IEEE-802.11be-2024")
    print("wifi_eht_mlo_doi: 10.1109/IEEESTD.2024.11090080")
    report_timing_samples(
        "wifi_eht_mlo_tid_to_link_encode",
        encode_samples,
        _WARMUPS,
        _BATCH,
        "element_payload",
    )
    report_timing_samples(
        "wifi_eht_mlo_tid_to_link_decode",
        decode_samples,
        _WARMUPS,
        _BATCH,
        "element_payload",
    )
    report_timing_samples(
        "wifi_eht_mlo_default_mapping_state",
        default_samples,
        _WARMUPS,
        _BATCH,
        "mapping_state",
    )
    report_timing_samples(
        "wifi_eht_mlo_apply_tid_to_link_element",
        apply_samples,
        _WARMUPS,
        _BATCH,
        "mapping_update",
    )
    report_timing_samples(
        "wifi_eht_mlo_tid_link_state",
        link_state_samples,
        _WARMUPS,
        _BATCH,
        "tid_direction",
    )
    report_timing_samples(
        "wifi_eht_mlo_enabled_links",
        enabled_samples,
        _WARMUPS,
        _BATCH,
        "mapping_state",
    )
    report_timing_samples(
        "wifi_eht_mlo_eml_timing_decode",
        timing_samples,
        _WARMUPS,
        _BATCH,
        "capability_field",
    )
    report_timing_samples(
        "wifi_eht_mlo_mapping_switch_time_field",
        switch_samples,
        _WARMUPS,
        _BATCH,
        "tsf_value",
    )
    report_timing_samples(
        "wifi_eht_mlo_expected_duration_field",
        duration_encode_samples,
        _WARMUPS,
        _BATCH,
        "duration_value",
    )
    report_timing_samples(
        "wifi_eht_mlo_expected_duration_us",
        duration_decode_samples,
        _WARMUPS,
        _BATCH,
        "duration_field",
    )
    print("wifi_eht_mlo_retained_checksum:", checksum)
