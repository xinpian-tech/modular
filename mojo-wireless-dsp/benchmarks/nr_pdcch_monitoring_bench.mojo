"""Strict per-API benchmark for non-grouped NR PDCCH monitoring occasions.

Each public free API owns one unique ``@no_inline`` workload.  Mutable pattern
fixtures and sample storage are constructed before warmup or timing.  Timed
loops use fixed inputs and contain only the attributable API call; result
fingerprints and checksums are formed after the timer.  Each workload has two
independent preflight checksums, three warmups, and nine timed samples.
"""

from std.benchmark import black_box, keep
from std.collections import Span
from std.time import global_perf_counter_ns
from wireless_dsp.benchmarking import (
    print_benchmark_metadata,
    report_timing_samples,
)
from wireless_dsp.wireless.nr.pdcch_monitoring import (
    NR_PDCCH_MONITORING_SL2560,
    NRPDCCHMonitoringPattern,
    nr_pdcch_monitoring_periodicity,
    nr_pdcch_monitoring_pattern,
    nr_pdcch_is_monitoring_slot,
    nr_pdcch_monitoring_first_symbols,
    nr_pdcch_is_monitoring_occasion,
)


comptime _WARMUPS = 3
comptime _SAMPLES = 9
comptime _BATCH = 4096
comptime _SEED = UInt64(1469598103934665603)


def _mix(checksum: UInt64, value: UInt64) -> UInt64:
    return (checksum ^ value) * UInt64(1099511628211)


def _require_repeat(first: UInt64, second: UInt64) raises -> UInt64:
    var first_checksum = _mix(_SEED, first)
    var second_checksum = _mix(_SEED, second)
    if first_checksum != second_checksum:
        raise Error("NR PDCCH monitoring benchmark is nondeterministic")
    keep(first_checksum)
    keep(second_checksum)
    return first_checksum


@no_inline
def _periodicity_workload(
    choice_index: Int, iterations: Int
) raises -> Tuple[UInt64, UInt64]:
    var result = 0
    var start = global_perf_counter_ns()
    for _ in range(iterations):
        result = nr_pdcch_monitoring_periodicity(black_box(choice_index))
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, UInt64(result))


@no_inline
def _pattern_workload(
    initial: NRPDCCHMonitoringPattern,
    choice_index: Int,
    offset_slots: Int,
    duration_slots: Int,
    iterations: Int,
) raises -> Tuple[UInt64, UInt64]:
    var result = initial.copy()
    var start = global_perf_counter_ns()
    for _ in range(iterations):
        result = nr_pdcch_monitoring_pattern(
            black_box(choice_index),
            black_box(offset_slots),
            black_box(True),
            black_box(duration_slots),
        )
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = UInt64(result.periodicity_slots)
    fingerprint = _mix(fingerprint, UInt64(result.offset_slots))
    fingerprint = _mix(
        fingerprint, UInt64(1 if result.duration_present else 0)
    )
    fingerprint = _mix(fingerprint, UInt64(result.duration_slots))
    return (elapsed, fingerprint)


@no_inline
def _monitoring_slot_workload(
    pattern: NRPDCCHMonitoringPattern,
    absolute_slot: Int,
    iterations: Int,
) raises -> Tuple[UInt64, UInt64]:
    var result = False
    var start = global_perf_counter_ns()
    for _ in range(iterations):
        result = nr_pdcch_is_monitoring_slot(
            black_box(pattern), black_box(absolute_slot)
        )
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, UInt64(1 if result else 0))


@no_inline
def _first_symbols_workload(
    mask: Int, extended_cp: Bool, iterations: Int
) raises -> Tuple[UInt64, UInt64]:
    var result = List[Int]()
    var start = global_perf_counter_ns()
    for _ in range(iterations):
        result = nr_pdcch_monitoring_first_symbols(
            black_box(mask), black_box(extended_cp)
        )
    var elapsed = global_perf_counter_ns() - start
    # Retain the complete owned result after timing; the fingerprint samples
    # only length and endpoints, so no O(N) output scan pollutes attribution.
    keep(result)
    var fingerprint = _mix(_SEED, UInt64(len(result)))
    if len(result) != 0:
        fingerprint = _mix(fingerprint, UInt64(result[0]))
        fingerprint = _mix(fingerprint, UInt64(result[len(result) - 1]))
    return (elapsed, fingerprint)


@no_inline
def _monitoring_occasion_workload(
    pattern: NRPDCCHMonitoringPattern,
    first_symbols: Span[Int, ...],
    coreset_duration_symbols: Int,
    extended_cp: Bool,
    absolute_slot: Int,
    first_symbol: Int,
    iterations: Int,
) raises -> Tuple[UInt64, UInt64]:
    var result = False
    var start = global_perf_counter_ns()
    for _ in range(iterations):
        result = nr_pdcch_is_monitoring_occasion(
            black_box(pattern),
            black_box(first_symbols),
            black_box(coreset_duration_symbols),
            black_box(extended_cp),
            black_box(absolute_slot),
            black_box(first_symbol),
        )
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, UInt64(1 if result else 0))


def _run_periodicity(choice_index: Int) raises -> UInt64:
    var samples = List[UInt64](capacity=_SAMPLES)
    var first = _periodicity_workload(choice_index, _BATCH)
    var second = _periodicity_workload(choice_index, _BATCH)
    var checksum = _require_repeat(first[1], second[1])
    keep(first)
    keep(second)
    for _ in range(_WARMUPS):
        keep(_periodicity_workload(choice_index, _BATCH))
    for _ in range(_SAMPLES):
        var sample = _periodicity_workload(choice_index, _BATCH)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    report_timing_samples(
        "nr_pdcch_monitoring_periodicity",
        samples,
        _WARMUPS,
        _BATCH,
        "api_call",
    )
    keep(samples)
    return checksum


def _run_pattern(
    initial: NRPDCCHMonitoringPattern,
    choice_index: Int,
    offset_slots: Int,
    duration_slots: Int,
) raises -> UInt64:
    var samples = List[UInt64](capacity=_SAMPLES)
    var first = _pattern_workload(
        initial,
        choice_index,
        offset_slots,
        duration_slots,
        _BATCH,
    )
    var second = _pattern_workload(
        initial,
        choice_index,
        offset_slots,
        duration_slots,
        _BATCH,
    )
    var checksum = _require_repeat(first[1], second[1])
    keep(first)
    keep(second)
    for _ in range(_WARMUPS):
        keep(
            _pattern_workload(
                initial,
                choice_index,
                offset_slots,
                duration_slots,
                _BATCH,
            )
        )
    for _ in range(_SAMPLES):
        var sample = _pattern_workload(
            initial,
            choice_index,
            offset_slots,
            duration_slots,
            _BATCH,
        )
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    report_timing_samples(
        "nr_pdcch_monitoring_pattern",
        samples,
        _WARMUPS,
        _BATCH,
        "api_call",
    )
    keep(samples)
    return checksum


def _run_monitoring_slot(
    pattern: NRPDCCHMonitoringPattern, absolute_slot: Int
) raises -> UInt64:
    var samples = List[UInt64](capacity=_SAMPLES)
    var first = _monitoring_slot_workload(pattern, absolute_slot, _BATCH)
    var second = _monitoring_slot_workload(pattern, absolute_slot, _BATCH)
    var checksum = _require_repeat(first[1], second[1])
    keep(first)
    keep(second)
    for _ in range(_WARMUPS):
        keep(_monitoring_slot_workload(pattern, absolute_slot, _BATCH))
    for _ in range(_SAMPLES):
        var sample = _monitoring_slot_workload(
            pattern, absolute_slot, _BATCH
        )
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    report_timing_samples(
        "nr_pdcch_is_monitoring_slot",
        samples,
        _WARMUPS,
        _BATCH,
        "api_call",
    )
    keep(samples)
    return checksum


def _run_first_symbols(mask: Int, extended_cp: Bool) raises -> UInt64:
    var samples = List[UInt64](capacity=_SAMPLES)
    var first = _first_symbols_workload(mask, extended_cp, _BATCH)
    var second = _first_symbols_workload(mask, extended_cp, _BATCH)
    var checksum = _require_repeat(first[1], second[1])
    keep(first)
    keep(second)
    for _ in range(_WARMUPS):
        keep(_first_symbols_workload(mask, extended_cp, _BATCH))
    for _ in range(_SAMPLES):
        var sample = _first_symbols_workload(mask, extended_cp, _BATCH)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    report_timing_samples(
        "nr_pdcch_monitoring_first_symbols",
        samples,
        _WARMUPS,
        _BATCH,
        "api_call",
    )
    keep(samples)
    return checksum


def _run_monitoring_occasion(
    pattern: NRPDCCHMonitoringPattern,
    first_symbols: Span[Int, ...],
    coreset_duration_symbols: Int,
    extended_cp: Bool,
    absolute_slot: Int,
    first_symbol: Int,
) raises -> UInt64:
    var samples = List[UInt64](capacity=_SAMPLES)
    var first = _monitoring_occasion_workload(
        pattern,
        first_symbols,
        coreset_duration_symbols,
        extended_cp,
        absolute_slot,
        first_symbol,
        _BATCH,
    )
    var second = _monitoring_occasion_workload(
        pattern,
        first_symbols,
        coreset_duration_symbols,
        extended_cp,
        absolute_slot,
        first_symbol,
        _BATCH,
    )
    var checksum = _require_repeat(first[1], second[1])
    keep(first)
    keep(second)
    for _ in range(_WARMUPS):
        keep(
            _monitoring_occasion_workload(
                pattern,
                first_symbols,
                coreset_duration_symbols,
                extended_cp,
                absolute_slot,
                first_symbol,
                _BATCH,
            )
        )
    for _ in range(_SAMPLES):
        var sample = _monitoring_occasion_workload(
            pattern,
            first_symbols,
            coreset_duration_symbols,
            extended_cp,
            absolute_slot,
            first_symbol,
            _BATCH,
        )
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    report_timing_samples(
        "nr_pdcch_is_monitoring_occasion",
        samples,
        _WARMUPS,
        _BATCH,
        "api_call",
    )
    keep(samples)
    return checksum


def main() raises:
    print_benchmark_metadata()
    print("nr_pdcch_monitoring_backend:", "scalar-cpu-reference")
    print(
        "nr_pdcch_monitoring_baseline:",
        "TS-38.213-V18.8.0-clause-10.1+TS-38.331-V18.10.0-clause-6.3.2",
    )

    # The complete mutable fixture and every fixed scalar input precede all
    # preflights, warmups, and timed samples.
    var choice_index = NR_PDCCH_MONITORING_SL2560
    var offset_slots = 2559
    var duration_slots = 2559
    var absolute_slot = Int.MAX
    var pattern = nr_pdcch_monitoring_pattern(
        choice_index, offset_slots, True, duration_slots
    )
    var monitoring_symbol_mask = 0x2490
    var extended_cp = False
    var coreset_duration_symbols = 3
    var queried_first_symbol = 6
    var first_symbols = nr_pdcch_monitoring_first_symbols(
        monitoring_symbol_mask, extended_cp
    )
    var first_symbols_span = Span(first_symbols)
    var occasion_pattern = nr_pdcch_monitoring_pattern(
        0, 0
    )

    var checksum = _SEED
    checksum = _mix(checksum, _run_periodicity(choice_index))
    checksum = _mix(
        checksum,
        _run_pattern(
            pattern, choice_index, offset_slots, duration_slots
        ),
    )
    checksum = _mix(
        checksum, _run_monitoring_slot(pattern, absolute_slot)
    )
    checksum = _mix(
        checksum,
        _run_first_symbols(monitoring_symbol_mask, extended_cp),
    )
    checksum = _mix(
        checksum,
        _run_monitoring_occasion(
            occasion_pattern,
            first_symbols_span,
            coreset_duration_symbols,
            extended_cp,
            absolute_slot,
            queried_first_symbol,
        ),
    )
    keep(pattern)
    keep(first_symbols)
    keep(occasion_pattern)
    keep(checksum)
    print("nr_pdcch_monitoring_retained_checksum:", checksum)
