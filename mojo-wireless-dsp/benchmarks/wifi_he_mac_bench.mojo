"""Attributable batched CPU timings for bounded HE MAC algorithms.

Each public algorithm has its own distribution: three untimed warmups, nine
independent timed samples, 4096 operations per sample, median/nearest-rank
p95/ns-per-operation, shared host/compiler/ISA metadata, and a retained
output-dependent checksum.
"""

from std.benchmark import black_box, keep
from std.time import global_perf_counter_ns
from wireless_dsp.benchmarking import (
    print_benchmark_metadata,
    report_timing_samples,
)
from wireless_dsp.wireless.wifi.he_mac import (
    WIFI_HE_BSS_INTRA,
    WIFI_HE_BSS_INTER,
    WIFI_HE_BSS_UNCLASSIFIED,
    WIFI_HE_RU_SEGMENT_PRIMARY_80,
    WifiHeMacProfile,
    WifiHeDualNavState,
    wifi_he_txop_duration_decode,
    wifi_he_txop_duration_encode,
    wifi_he_dual_nav_update_from_frame,
    wifi_he_dual_nav_update_from_txop_subfield,
    wifi_he_dual_nav_remaining,
    wifi_he_cf_end_reset_decision,
    wifi_he_dual_nav_apply_reset,
    wifi_he_nav_reset_timeout_us,
    wifi_he_trigger_ru_decode,
    wifi_he_trigger_ru_encode,
    wifi_he_trigger_user_allocation_plan,
)


comptime _WARMUPS = 3
comptime _SAMPLES = 9
comptime _BATCH = 4096


def _mix(checksum: UInt64, value: Int) -> UInt64:
    return checksum * UInt64(1099511628211) ^ UInt64(value + 1)


@no_inline
def _txop_decode_workload(iterations: Int, salt: Int) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for iteration in range(iterations):
        var decoded = wifi_he_txop_duration_decode(
            black_box((iteration + salt) & 127)
        )
        checksum = _mix(checksum, decoded.duration_us + iteration)
        checksum = _mix(checksum, 1 if decoded.specified else 0)
    return checksum


@no_inline
def _txop_encode_workload(iterations: Int, salt: Int) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for iteration in range(iterations):
        var duration = (37 * iteration + salt) % 8449
        var field = wifi_he_txop_duration_encode(black_box(duration))
        checksum = _mix(checksum, field + iteration)
    return checksum


@no_inline
def _frame_nav_workload(
    iterations: Int,
    salt: Int,
    profile: WifiHeMacProfile,
    state: WifiHeDualNavState,
) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for iteration in range(iterations):
        var classification = (iteration + salt) % 3
        var update = wifi_he_dual_nav_update_from_frame(
            profile,
            state,
            black_box(1000 + (iteration & 31)),
            black_box(1400 + ((iteration + salt) & 127)),
            black_box(classification),
            receiver_address_is_self=black_box((iteration & 1) == 0),
            sta_is_txop_holder=black_box((iteration & 2) == 0),
            solicits_immediate_response=black_box((iteration & 4) == 0),
            frame_is_trigger=black_box((iteration & 8) == 0),
        )
        checksum = _mix(checksum, update.updated_nav + iteration)
        checksum = _mix(checksum, update.state.intra_bss_nav_end_us)
        checksum = _mix(checksum, update.state.basic_nav_end_us)
    return checksum


@no_inline
def _txop_nav_workload(
    iterations: Int,
    salt: Int,
    profile: WifiHeMacProfile,
    state: WifiHeDualNavState,
) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for iteration in range(iterations):
        var field = (iteration + salt) & 126
        var classification = (iteration + salt) % 3
        var update = wifi_he_dual_nav_update_from_txop_subfield(
            profile,
            state,
            black_box(1000 + (iteration & 31)),
            black_box(field),
            black_box(classification),
            sta_is_txop_holder=black_box((iteration & 1) == 0),
            ppdu_has_duration_field=black_box((iteration & 15) == 0),
        )
        checksum = _mix(checksum, update.updated_nav + iteration)
        checksum = _mix(checksum, update.state.intra_bss_nav_end_us)
        checksum = _mix(checksum, update.state.basic_nav_end_us)
    return checksum


@no_inline
def _remaining_workload(
    iterations: Int,
    salt: Int,
    profile: WifiHeMacProfile,
    state: WifiHeDualNavState,
) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for iteration in range(iterations):
        var remaining = wifi_he_dual_nav_remaining(
            profile, state, black_box(1500 + ((iteration + salt) & 1023))
        )
        checksum = _mix(checksum, remaining.intra_bss_us + iteration)
        checksum = _mix(checksum, remaining.basic_us)
        checksum = _mix(checksum, 1 if remaining.medium_busy else 0)
    return checksum


@no_inline
def _cf_end_workload(
    iterations: Int,
    salt: Int,
    profile: WifiHeMacProfile,
    state: WifiHeDualNavState,
) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for iteration in range(iterations):
        var classification = (iteration + salt) % 3
        var decision = wifi_he_cf_end_reset_decision(
            profile,
            state,
            black_box(1500 + (iteration & 63)),
            black_box(classification),
        )
        checksum = _mix(
            checksum, 1 if decision.reset_intra_bss_nav else 0
        )
        checksum = _mix(checksum, 1 if decision.reset_basic_nav else 0)
        checksum = _mix(
            checksum,
            (1 if decision.reset_both_permitted else 0) + iteration,
        )
    return checksum


@no_inline
def _apply_reset_workload(
    iterations: Int,
    salt: Int,
    profile: WifiHeMacProfile,
    state: WifiHeDualNavState,
) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for iteration in range(iterations):
        var reset_intra = ((iteration + salt) & 1) == 0
        var reset = wifi_he_dual_nav_apply_reset(
            profile,
            state,
            black_box(1500 + (iteration & 63)),
            reset_intra_bss_nav=black_box(reset_intra),
            reset_basic_nav=black_box(not reset_intra),
        )
        checksum = _mix(checksum, reset.state.intra_bss_nav_end_us)
        checksum = _mix(checksum, reset.state.basic_nav_end_us + iteration)
        checksum = _mix(
            checksum, 1 if reset.phy_cca_reset_required else 0
        )
    return checksum


@no_inline
def _reset_timeout_workload(iterations: Int, salt: Int) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for iteration in range(iterations):
        var timeout = wifi_he_nav_reset_timeout_us(
            black_box(16 + ((iteration + salt) & 1)),
            black_box(44 + (iteration & 3)),
            black_box(4 + (iteration & 1)),
            black_box(9),
        )
        checksum = _mix(checksum, timeout + iteration)
    return checksum


@no_inline
def _ru_decode_workload(
    iterations: Int, salt: Int, profile: WifiHeMacProfile,
) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for iteration in range(iterations):
        var allocation = 2 * ((iteration + salt) % 68)
        var ru = wifi_he_trigger_ru_decode(
            profile, black_box(allocation)
        )
        checksum = _mix(checksum, ru.ru_tones + iteration)
        checksum = _mix(checksum, ru.ru_index)
        checksum = _mix(checksum, ru.allocation)
    return checksum


@no_inline
def _ru_encode_workload(
    iterations: Int, salt: Int, profile: WifiHeMacProfile,
) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for iteration in range(iterations):
        var selector = (iteration + salt) % 6
        var tones: Int
        var maximum: Int
        if selector == 0:
            tones, maximum = 26, 37
        elif selector == 1:
            tones, maximum = 52, 16
        elif selector == 2:
            tones, maximum = 106, 8
        elif selector == 3:
            tones, maximum = 242, 4
        elif selector == 4:
            tones, maximum = 484, 2
        else:
            tones, maximum = 996, 1
        var index = 1 + ((iteration + salt) % maximum)
        var allocation = wifi_he_trigger_ru_encode(
            profile,
            black_box(tones),
            black_box(index),
            black_box(WIFI_HE_RU_SEGMENT_PRIMARY_80),
        )
        checksum = _mix(checksum, allocation + iteration)
    return checksum


@no_inline
def _user_allocation_workload(
    iterations: Int, salt: Int, profile: WifiHeMacProfile,
) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for iteration in range(iterations):
        var count_field = (iteration + salt) & 31
        var plan = wifi_he_trigger_user_allocation_plan(
            profile,
            black_box(0),
            black_box(0),
            number_of_ra_ru_field=black_box(count_field),
        )
        checksum = _mix(checksum, plan.number_of_rus + iteration)
        checksum = _mix(checksum, plan.last_ru_index)
        checksum = _mix(checksum, plan.last_ru_allocation)
    return checksum


def main() raises:
    var nav_profile = WifiHeMacProfile(False, True, 80)
    var ru_profile = WifiHeMacProfile(True, False, 80)
    var state = WifiHeDualNavState(2000, 2400, WIFI_HE_BSS_UNCLASSIFIED)

    for _ in range(_WARMUPS):
        var salt = 324508639
        keep(_txop_decode_workload(_BATCH, salt))
        keep(_txop_encode_workload(_BATCH, salt))
        keep(_frame_nav_workload(_BATCH, salt, nav_profile, state))
        keep(_txop_nav_workload(_BATCH, salt, nav_profile, state))
        keep(_remaining_workload(_BATCH, salt, nav_profile, state))
        keep(_cf_end_workload(_BATCH, salt, nav_profile, state))
        keep(_apply_reset_workload(_BATCH, salt, nav_profile, state))
        keep(_reset_timeout_workload(_BATCH, salt))
        keep(_ru_decode_workload(_BATCH, salt, ru_profile))
        keep(_ru_encode_workload(_BATCH, salt, ru_profile))
        keep(_user_allocation_workload(_BATCH, salt, ru_profile))

    var txop_decode_samples = List[UInt64](capacity=_SAMPLES)
    var txop_encode_samples = List[UInt64](capacity=_SAMPLES)
    var frame_nav_samples = List[UInt64](capacity=_SAMPLES)
    var txop_nav_samples = List[UInt64](capacity=_SAMPLES)
    var remaining_samples = List[UInt64](capacity=_SAMPLES)
    var cf_end_samples = List[UInt64](capacity=_SAMPLES)
    var apply_reset_samples = List[UInt64](capacity=_SAMPLES)
    var reset_timeout_samples = List[UInt64](capacity=_SAMPLES)
    var ru_decode_samples = List[UInt64](capacity=_SAMPLES)
    var ru_encode_samples = List[UInt64](capacity=_SAMPLES)
    var user_allocation_samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)

    for _ in range(_SAMPLES):
        var salt = 324508639
        var start = global_perf_counter_ns()
        var txop_decode = _txop_decode_workload(_BATCH, salt)
        txop_decode_samples.append(global_perf_counter_ns() - start)
        checksum = checksum * UInt64(1099511628211) ^ txop_decode
        keep(txop_decode)

        start = global_perf_counter_ns()
        var txop_encode = _txop_encode_workload(_BATCH, salt)
        txop_encode_samples.append(global_perf_counter_ns() - start)
        checksum = checksum * UInt64(1099511628211) ^ txop_encode
        keep(txop_encode)

        start = global_perf_counter_ns()
        var frame_nav = _frame_nav_workload(
            _BATCH, salt, nav_profile, state
        )
        frame_nav_samples.append(global_perf_counter_ns() - start)
        checksum = checksum * UInt64(1099511628211) ^ frame_nav
        keep(frame_nav)

        start = global_perf_counter_ns()
        var txop_nav = _txop_nav_workload(
            _BATCH, salt, nav_profile, state
        )
        txop_nav_samples.append(global_perf_counter_ns() - start)
        checksum = checksum * UInt64(1099511628211) ^ txop_nav
        keep(txop_nav)

        start = global_perf_counter_ns()
        var remaining = _remaining_workload(
            _BATCH, salt, nav_profile, state
        )
        remaining_samples.append(global_perf_counter_ns() - start)
        checksum = checksum * UInt64(1099511628211) ^ remaining
        keep(remaining)

        start = global_perf_counter_ns()
        var cf_end = _cf_end_workload(_BATCH, salt, nav_profile, state)
        cf_end_samples.append(global_perf_counter_ns() - start)
        checksum = checksum * UInt64(1099511628211) ^ cf_end
        keep(cf_end)

        start = global_perf_counter_ns()
        var apply_reset = _apply_reset_workload(
            _BATCH, salt, nav_profile, state
        )
        apply_reset_samples.append(global_perf_counter_ns() - start)
        checksum = checksum * UInt64(1099511628211) ^ apply_reset
        keep(apply_reset)

        start = global_perf_counter_ns()
        var reset_timeout = _reset_timeout_workload(_BATCH, salt)
        reset_timeout_samples.append(global_perf_counter_ns() - start)
        checksum = checksum * UInt64(1099511628211) ^ reset_timeout
        keep(reset_timeout)

        start = global_perf_counter_ns()
        var ru_decode = _ru_decode_workload(_BATCH, salt, ru_profile)
        ru_decode_samples.append(global_perf_counter_ns() - start)
        checksum = checksum * UInt64(1099511628211) ^ ru_decode
        keep(ru_decode)

        start = global_perf_counter_ns()
        var ru_encode = _ru_encode_workload(_BATCH, salt, ru_profile)
        ru_encode_samples.append(global_perf_counter_ns() - start)
        checksum = checksum * UInt64(1099511628211) ^ ru_encode
        keep(ru_encode)

        start = global_perf_counter_ns()
        var user_allocation = _user_allocation_workload(
            _BATCH, salt, ru_profile
        )
        user_allocation_samples.append(global_perf_counter_ns() - start)
        checksum = checksum * UInt64(1099511628211) ^ user_allocation
        keep(user_allocation)

    print_benchmark_metadata()
    print("wifi_he_mac_backend: scalar-cpu-reference")
    report_timing_samples(
        "wifi_he_txop_duration_decode",
        txop_decode_samples,
        _WARMUPS,
        _BATCH,
        "txop_field",
    )
    report_timing_samples(
        "wifi_he_txop_duration_encode",
        txop_encode_samples,
        _WARMUPS,
        _BATCH,
        "txop_duration",
    )
    report_timing_samples(
        "wifi_he_dual_nav_update_from_frame",
        frame_nav_samples,
        _WARMUPS,
        _BATCH,
        "frame_nav_decision",
    )
    report_timing_samples(
        "wifi_he_dual_nav_update_from_txop_subfield",
        txop_nav_samples,
        _WARMUPS,
        _BATCH,
        "txop_nav_decision",
    )
    report_timing_samples(
        "wifi_he_dual_nav_remaining",
        remaining_samples,
        _WARMUPS,
        _BATCH,
        "dual_nav_observation",
    )
    report_timing_samples(
        "wifi_he_cf_end_reset_decision",
        cf_end_samples,
        _WARMUPS,
        _BATCH,
        "cf_end_decision",
    )
    report_timing_samples(
        "wifi_he_dual_nav_apply_reset",
        apply_reset_samples,
        _WARMUPS,
        _BATCH,
        "dual_nav_reset",
    )
    report_timing_samples(
        "wifi_he_nav_reset_timeout_us",
        reset_timeout_samples,
        _WARMUPS,
        _BATCH,
        "reset_timeout",
    )
    report_timing_samples(
        "wifi_he_trigger_ru_decode",
        ru_decode_samples,
        _WARMUPS,
        _BATCH,
        "ru_field",
    )
    report_timing_samples(
        "wifi_he_trigger_ru_encode",
        ru_encode_samples,
        _WARMUPS,
        _BATCH,
        "ru_tuple",
    )
    report_timing_samples(
        "wifi_he_trigger_user_allocation_plan",
        user_allocation_samples,
        _WARMUPS,
        _BATCH,
        "trigger_user_info",
    )
    print("wifi_he_mac_retained_checksum:", checksum)
