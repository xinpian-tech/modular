"""Per-API CPU benchmarks for bounded Rel-16 NR-U channel access.

Each public API has an independent ``@no_inline`` fixed-input workload.
Decoded priority and contention-window state fixtures are constructed before
warmup or timing, complete returned structs are retained, and only O(1) field
fingerprints enter the checksum.  Every workload is executed twice with the
same inputs before timing and must produce an identical checksum.
"""

from std.benchmark import black_box, keep
from std.time import global_perf_counter_ns
from wireless_dsp.benchmarking import (
    print_benchmark_metadata,
    report_timing_samples,
)
from wireless_dsp.wireless.nr.nr_u_rel16 import (
    NR_U_REL16_UPLINK,
    NRURel16PriorityClass,
    NRURel16ContentionWindowState,
    nr_u_rel16_priority_class,
    nr_u_rel16_defer_duration_us,
    nr_u_rel16_contention_window_allowed,
    nr_u_rel16_backoff_draw,
    nr_u_rel16_backoff_after_decrements,
    nr_u_rel16_next_higher_contention_window,
    nr_u_rel16_record_contention_window_draw,
    nr_u_rel16_channel_occupancy_allowed,
)


comptime _WARMUPS = 3
comptime _SAMPLES = 9
comptime _BATCH = 4096


def _mix(checksum: UInt64, value: Int) -> UInt64:
    return (checksum ^ UInt64(value + 4096)) * UInt64(1099511628211)


def _require_repeat(first: UInt64, second: UInt64) raises:
    if first != second:
        raise Error("NR-U fixed workload is nondeterministic")
    keep(first)
    keep(second)


@no_inline
def _priority_class_workload(iterations: Int) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for operation in range(iterations):
        var profile = nr_u_rel16_priority_class(
            black_box(NR_U_REL16_UPLINK), black_box(4), black_box(False)
        )
        checksum = _mix(checksum, profile.direction + operation)
        checksum = _mix(checksum, profile.priority_class)
        checksum = _mix(checksum, profile.defer_slot_count)
        checksum = _mix(checksum, profile.cw_min)
        checksum = _mix(checksum, profile.cw_max)
        checksum = _mix(checksum, profile.maximum_channel_occupancy_us)
        keep(profile)
    return checksum


@no_inline
def _defer_duration_workload(
    profile: NRURel16PriorityClass, iterations: Int
) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for operation in range(iterations):
        var duration = nr_u_rel16_defer_duration_us(black_box(profile))
        checksum = _mix(checksum, duration + operation)
        keep(duration)
    return checksum


@no_inline
def _contention_window_allowed_workload(
    profile: NRURel16PriorityClass,
    contention_window: Int,
    iterations: Int,
) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for operation in range(iterations):
        var allowed = nr_u_rel16_contention_window_allowed(
            black_box(profile), black_box(contention_window)
        )
        checksum = _mix(checksum, (1 if allowed else 0) + operation)
        keep(allowed)
    return checksum


@no_inline
def _backoff_draw_workload(
    profile: NRURel16PriorityClass,
    contention_window: Int,
    random_draw: Int,
    iterations: Int,
) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for operation in range(iterations):
        var draw = nr_u_rel16_backoff_draw(
            black_box(profile),
            black_box(contention_window),
            black_box(random_draw),
        )
        checksum = _mix(checksum, draw + operation)
        keep(draw)
    return checksum


@no_inline
def _backoff_after_decrements_workload(
    profile: NRURel16PriorityClass,
    contention_window: Int,
    initial_backoff: Int,
    decrement_count: Int,
    iterations: Int,
) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for operation in range(iterations):
        var remaining = nr_u_rel16_backoff_after_decrements(
            black_box(profile),
            black_box(contention_window),
            black_box(initial_backoff),
            black_box(decrement_count),
        )
        checksum = _mix(checksum, remaining + operation)
        keep(remaining)
    return checksum


@no_inline
def _next_higher_contention_window_workload(
    profile: NRURel16PriorityClass,
    current_window: Int,
    iterations: Int,
) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for operation in range(iterations):
        var next = nr_u_rel16_next_higher_contention_window(
            black_box(profile), black_box(current_window)
        )
        checksum = _mix(checksum, next + operation)
        keep(next)
    return checksum


@no_inline
def _record_contention_window_draw_workload(
    profile: NRURel16PriorityClass,
    state: NRURel16ContentionWindowState,
    maximum_draw_reset_count: Int,
    iterations: Int,
) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for operation in range(iterations):
        var updated = nr_u_rel16_record_contention_window_draw(
            black_box(profile),
            black_box(state),
            black_box(maximum_draw_reset_count),
        )
        checksum = _mix(checksum, updated.contention_window + operation)
        checksum = _mix(checksum, updated.consecutive_maximum_draws)
        keep(updated)
    return checksum


@no_inline
def _channel_occupancy_allowed_workload(
    profile: NRURel16PriorityClass,
    occupancy_duration_us: Int,
    first_inserted_gap_start_us: Int,
    minimum_inserted_gap_duration_us: Int,
    iterations: Int,
) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for operation in range(iterations):
        var allowed = nr_u_rel16_channel_occupancy_allowed(
            black_box(profile),
            black_box(occupancy_duration_us),
            black_box(first_inserted_gap_start_us),
            black_box(minimum_inserted_gap_duration_us),
        )
        checksum = _mix(checksum, (1 if allowed else 0) + operation)
        keep(allowed)
    return checksum


def main() raises:
    # All decoded configurations and state fixtures precede deterministic
    # checks, warmups, and timers.
    var profile = nr_u_rel16_priority_class(NR_U_REL16_UPLINK, 4, False)
    var state = NRURel16ContentionWindowState(profile.cw_max, 2)
    var contention_window = 63
    var random_draw = 37
    var decrement_count = 19
    var maximum_draw_reset_count = 4
    var occupancy_duration_us = 7500
    var first_inserted_gap_start_us = 5000
    var minimum_inserted_gap_duration_us = 100

    _require_repeat(
        _priority_class_workload(_BATCH),
        _priority_class_workload(_BATCH),
    )
    _require_repeat(
        _defer_duration_workload(profile, _BATCH),
        _defer_duration_workload(profile, _BATCH),
    )
    _require_repeat(
        _contention_window_allowed_workload(
            profile, contention_window, _BATCH
        ),
        _contention_window_allowed_workload(
            profile, contention_window, _BATCH
        ),
    )
    _require_repeat(
        _backoff_draw_workload(
            profile, contention_window, random_draw, _BATCH
        ),
        _backoff_draw_workload(
            profile, contention_window, random_draw, _BATCH
        ),
    )
    _require_repeat(
        _backoff_after_decrements_workload(
            profile,
            contention_window,
            random_draw,
            decrement_count,
            _BATCH,
        ),
        _backoff_after_decrements_workload(
            profile,
            contention_window,
            random_draw,
            decrement_count,
            _BATCH,
        ),
    )
    _require_repeat(
        _next_higher_contention_window_workload(
            profile, contention_window, _BATCH
        ),
        _next_higher_contention_window_workload(
            profile, contention_window, _BATCH
        ),
    )
    _require_repeat(
        _record_contention_window_draw_workload(
            profile, state, maximum_draw_reset_count, _BATCH
        ),
        _record_contention_window_draw_workload(
            profile, state, maximum_draw_reset_count, _BATCH
        ),
    )
    _require_repeat(
        _channel_occupancy_allowed_workload(
            profile,
            occupancy_duration_us,
            first_inserted_gap_start_us,
            minimum_inserted_gap_duration_us,
            _BATCH,
        ),
        _channel_occupancy_allowed_workload(
            profile,
            occupancy_duration_us,
            first_inserted_gap_start_us,
            minimum_inserted_gap_duration_us,
            _BATCH,
        ),
    )

    for _ in range(_WARMUPS):
        keep(_priority_class_workload(_BATCH))
        keep(_defer_duration_workload(profile, _BATCH))
        keep(
            _contention_window_allowed_workload(
                profile, contention_window, _BATCH
            )
        )
        keep(
            _backoff_draw_workload(
                profile, contention_window, random_draw, _BATCH
            )
        )
        keep(
            _backoff_after_decrements_workload(
                profile,
                contention_window,
                random_draw,
                decrement_count,
                _BATCH,
            )
        )
        keep(
            _next_higher_contention_window_workload(
                profile, contention_window, _BATCH
            )
        )
        keep(
            _record_contention_window_draw_workload(
                profile, state, maximum_draw_reset_count, _BATCH
            )
        )
        keep(
            _channel_occupancy_allowed_workload(
                profile,
                occupancy_duration_us,
                first_inserted_gap_start_us,
                minimum_inserted_gap_duration_us,
                _BATCH,
            )
        )

    var priority_samples = List[UInt64](capacity=_SAMPLES)
    var defer_samples = List[UInt64](capacity=_SAMPLES)
    var allowed_samples = List[UInt64](capacity=_SAMPLES)
    var draw_samples = List[UInt64](capacity=_SAMPLES)
    var decrement_samples = List[UInt64](capacity=_SAMPLES)
    var next_samples = List[UInt64](capacity=_SAMPLES)
    var reset_samples = List[UInt64](capacity=_SAMPLES)
    var occupancy_samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var start = global_perf_counter_ns()
        var priority = _priority_class_workload(_BATCH)
        priority_samples.append(global_perf_counter_ns() - start)
        checksum = (checksum ^ priority) * UInt64(1099511628211)
        keep(priority)

        start = global_perf_counter_ns()
        var defer = _defer_duration_workload(profile, _BATCH)
        defer_samples.append(global_perf_counter_ns() - start)
        checksum = (checksum ^ defer) * UInt64(1099511628211)
        keep(defer)

        start = global_perf_counter_ns()
        var allowed = _contention_window_allowed_workload(
            profile, contention_window, _BATCH
        )
        allowed_samples.append(global_perf_counter_ns() - start)
        checksum = (checksum ^ allowed) * UInt64(1099511628211)
        keep(allowed)

        start = global_perf_counter_ns()
        var draw = _backoff_draw_workload(
            profile, contention_window, random_draw, _BATCH
        )
        draw_samples.append(global_perf_counter_ns() - start)
        checksum = (checksum ^ draw) * UInt64(1099511628211)
        keep(draw)

        start = global_perf_counter_ns()
        var decrement = _backoff_after_decrements_workload(
            profile,
            contention_window,
            random_draw,
            decrement_count,
            _BATCH,
        )
        decrement_samples.append(global_perf_counter_ns() - start)
        checksum = (checksum ^ decrement) * UInt64(1099511628211)
        keep(decrement)

        start = global_perf_counter_ns()
        var next = _next_higher_contention_window_workload(
            profile, contention_window, _BATCH
        )
        next_samples.append(global_perf_counter_ns() - start)
        checksum = (checksum ^ next) * UInt64(1099511628211)
        keep(next)

        start = global_perf_counter_ns()
        var reset = _record_contention_window_draw_workload(
            profile, state, maximum_draw_reset_count, _BATCH
        )
        reset_samples.append(global_perf_counter_ns() - start)
        checksum = (checksum ^ reset) * UInt64(1099511628211)
        keep(reset)

        start = global_perf_counter_ns()
        var occupancy = _channel_occupancy_allowed_workload(
            profile,
            occupancy_duration_us,
            first_inserted_gap_start_us,
            minimum_inserted_gap_duration_us,
            _BATCH,
        )
        occupancy_samples.append(global_perf_counter_ns() - start)
        checksum = (checksum ^ occupancy) * UInt64(1099511628211)
        keep(occupancy)

    print_benchmark_metadata()
    print("nr_u_rel16_backend: scalar-cpu-reference")
    print("nr_u_rel16_baseline: NR_unlic-RP-201834-TS37.213-V16.14.0")
    report_timing_samples(
        "nr_u_rel16_priority_class",
        priority_samples,
        _WARMUPS,
        _BATCH,
        "table_lookup",
    )
    report_timing_samples(
        "nr_u_rel16_defer_duration_us",
        defer_samples,
        _WARMUPS,
        _BATCH,
        "duration",
    )
    report_timing_samples(
        "nr_u_rel16_contention_window_allowed",
        allowed_samples,
        _WARMUPS,
        _BATCH,
        "decision",
    )
    report_timing_samples(
        "nr_u_rel16_backoff_draw",
        draw_samples,
        _WARMUPS,
        _BATCH,
        "draw",
    )
    report_timing_samples(
        "nr_u_rel16_backoff_after_decrements",
        decrement_samples,
        _WARMUPS,
        _BATCH,
        "countdown",
    )
    report_timing_samples(
        "nr_u_rel16_next_higher_contention_window",
        next_samples,
        _WARMUPS,
        _BATCH,
        "window_update",
    )
    report_timing_samples(
        "nr_u_rel16_record_contention_window_draw",
        reset_samples,
        _WARMUPS,
        _BATCH,
        "state_update",
    )
    report_timing_samples(
        "nr_u_rel16_channel_occupancy_allowed",
        occupancy_samples,
        _WARMUPS,
        _BATCH,
        "decision",
    )
    keep(profile)
    keep(state)
    keep(checksum)
    print("nr_u_rel16_retained_checksum:", checksum)
