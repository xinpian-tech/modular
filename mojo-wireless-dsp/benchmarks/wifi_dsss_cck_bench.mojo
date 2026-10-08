"""Attributable timings for bounded DSSS and HR/DSSS CCK symbols.

Each public API is timed as an independent batched family with three untimed
warmups and nine odd samples.  A fixed salt selects between distinct valid
streams or varies the exact differential state.  Only target calls are timed;
complete results are kept and fully consumed afterward, and a separate O(1)
endpoint fingerprint is retained.
"""

from std.benchmark import black_box, keep
from std.collections import Span
from std.time import global_perf_counter_ns
from wireless_dsp.benchmarking import (
    print_benchmark_metadata,
    report_timing_samples,
)
from wireless_dsp.core import Complex64
from wireless_dsp.wireless.wifi.dsss_cck import (
    WIFI_DSSS_BARKER_CHIPS,
    WIFI_CCK_CHIPS,
    wifi_dsss_barker_sequence,
    wifi_dsss_dbpsk_spread,
    wifi_dsss_dbpsk_despread_hard,
    wifi_dsss_dqpsk_spread,
    wifi_dsss_dqpsk_despread_hard,
    wifi_cck_5_5_codeword,
    wifi_cck_11_codeword,
    wifi_cck_5_5_map,
    wifi_cck_5_5_demap_hard,
    wifi_cck_11_map,
    wifi_cck_11_demap_hard,
)


comptime _WARMUPS = 3
comptime _SAMPLES = 9
comptime _FAST_BATCH = 1024
comptime _MAP_BATCH = 64
comptime _CCK5_DETECT_BATCH = 32
comptime _CCK11_DETECT_BATCH = 4
comptime _STREAM_SYMBOLS = 8


@fieldwise_init
struct _WorkloadMeasurement(Copyable, Movable):
    var elapsed_ns: UInt64
    var full_output_checksum: UInt64
    var fingerprint_checksum: UInt64


def _record_measurement(
    measurement: _WorkloadMeasurement,
    mut samples: List[UInt64],
    mut full_output_checksum: UInt64,
    mut fingerprint_checksum: UInt64,
):
    samples.append(measurement.elapsed_ns)
    full_output_checksum = _mix(
        full_output_checksum,
        Int(measurement.full_output_checksum & UInt64(Int.MAX)),
    )
    fingerprint_checksum = _mix(
        fingerprint_checksum,
        Int(measurement.fingerprint_checksum & UInt64(Int.MAX)),
    )
    keep(measurement)


def _mix(checksum: UInt64, value: Int) -> UInt64:
    return (checksum ^ UInt64(value + 257)) * UInt64(1099511628211)


def _mix_bits(checksum: UInt64, bits: Span[UInt8, ...]) -> UInt64:
    var result = checksum
    for index in range(len(bits)):
        result = _mix(result, Int(bits[index]) + 3 * index)
    return result


def _mix_chips(checksum: UInt64, chips: Span[Complex64, ...]) -> UInt64:
    var result = checksum
    for index in range(len(chips)):
        var real = chips[index].re
        var imag = chips[index].im
        var real_code = 1
        var imag_code = 1
        if real < -0.5:
            real_code = 0
        elif real > 0.5:
            real_code = 2
        if imag < -0.5:
            imag_code = 0
        elif imag > 0.5:
            imag_code = 2
        result = _mix(result, real_code + 3 * imag_code + 11 * index)
    return result


def _fingerprint_bits(bits: Span[UInt8, ...]) -> UInt64:
    return _mix(
        _mix(UInt64(1469598103934665603), len(bits)),
        Int(bits[0]) * 17 + Int(bits[len(bits) - 1]) * 257,
    )


def _fingerprint_chips(chips: Span[Complex64, ...]) -> UInt64:
    var first_code = 0
    var last_code = 0
    if chips[0].re > 0.0:
        first_code += 1
    if chips[0].im > 0.0:
        first_code += 2
    if chips[len(chips) - 1].re > 0.0:
        last_code += 1
    if chips[len(chips) - 1].im > 0.0:
        last_code += 2
    return _mix(
        _mix(UInt64(1469598103934665603), len(chips)),
        first_code * 17 + last_code * 257,
    )


def _bits(count: Int, seed: UInt64) -> List[UInt8]:
    var state = seed
    var result = List[UInt8](capacity=count)
    for _ in range(count):
        state = (
            state * UInt64(6364136223846793005)
            + UInt64(1442695040888963407)
        )
        result.append(UInt8((state >> 63) & UInt64(1)))
    return result^


@no_inline
def _barker_workload(
    iterations: Int, measure: Bool
) -> _WorkloadMeasurement:
    var elapsed = UInt64(0)
    var full_checksum = UInt64(1469598103934665603)
    var fingerprint = UInt64(1469598103934665603)
    for operation in range(iterations):
        var start = UInt64(0)
        if measure:
            start = global_perf_counter_ns()
        var chips = wifi_dsss_barker_sequence()
        if measure:
            elapsed += global_perf_counter_ns() - start
        full_checksum = _mix_chips(full_checksum, Span(chips))
        full_checksum = _mix(full_checksum, operation)
        fingerprint = _mix(
            fingerprint,
            Int(_fingerprint_chips(Span(chips)) & UInt64(Int.MAX))
            + operation,
        )
        keep(chips)
    return _WorkloadMeasurement(elapsed, full_checksum, fingerprint)


@no_inline
def _dbpsk_spread_workload(
    iterations: Int,
    salt: Int,
    first: Span[UInt8, ...],
    second: Span[UInt8, ...],
    measure: Bool,
) raises -> _WorkloadMeasurement:
    var elapsed = UInt64(0)
    var full_checksum = UInt64(1469598103934665603)
    var fingerprint = UInt64(1469598103934665603)
    for operation in range(iterations):
        var chips: List[Complex64]
        var start = UInt64(0)
        if measure:
            start = global_perf_counter_ns()
        if ((operation + salt) & 1) == 0:
            chips = wifi_dsss_dbpsk_spread(black_box(first))
        else:
            chips = wifi_dsss_dbpsk_spread(black_box(second))
        if measure:
            elapsed += global_perf_counter_ns() - start
        full_checksum = _mix_chips(full_checksum, Span(chips))
        fingerprint = _mix(
            fingerprint,
            Int(_fingerprint_chips(Span(chips)) & UInt64(Int.MAX))
            + operation,
        )
        keep(chips)
    return _WorkloadMeasurement(elapsed, full_checksum, fingerprint)


@no_inline
def _dbpsk_detect_workload(
    iterations: Int,
    salt: Int,
    first: Span[Complex64, ...],
    second: Span[Complex64, ...],
    measure: Bool,
) raises -> _WorkloadMeasurement:
    var elapsed = UInt64(0)
    var full_checksum = UInt64(1469598103934665603)
    var fingerprint = UInt64(1469598103934665603)
    for operation in range(iterations):
        var bits: List[UInt8]
        var start = UInt64(0)
        if measure:
            start = global_perf_counter_ns()
        if ((operation + salt) & 1) == 0:
            bits = wifi_dsss_dbpsk_despread_hard(black_box(first))
        else:
            bits = wifi_dsss_dbpsk_despread_hard(black_box(second))
        if measure:
            elapsed += global_perf_counter_ns() - start
        full_checksum = _mix_bits(full_checksum, Span(bits))
        fingerprint = _mix(
            fingerprint,
            Int(_fingerprint_bits(Span(bits)) & UInt64(Int.MAX))
            + operation,
        )
        keep(bits)
    return _WorkloadMeasurement(elapsed, full_checksum, fingerprint)


@no_inline
def _dqpsk_spread_workload(
    iterations: Int,
    salt: Int,
    first: Span[UInt8, ...],
    second: Span[UInt8, ...],
    measure: Bool,
) raises -> _WorkloadMeasurement:
    var elapsed = UInt64(0)
    var full_checksum = UInt64(1469598103934665603)
    var fingerprint = UInt64(1469598103934665603)
    for operation in range(iterations):
        var chips: List[Complex64]
        var start = UInt64(0)
        if measure:
            start = global_perf_counter_ns()
        if ((operation + salt) & 1) == 0:
            chips = wifi_dsss_dqpsk_spread(black_box(first))
        else:
            chips = wifi_dsss_dqpsk_spread(black_box(second))
        if measure:
            elapsed += global_perf_counter_ns() - start
        full_checksum = _mix_chips(full_checksum, Span(chips))
        fingerprint = _mix(
            fingerprint,
            Int(_fingerprint_chips(Span(chips)) & UInt64(Int.MAX))
            + operation,
        )
        keep(chips)
    return _WorkloadMeasurement(elapsed, full_checksum, fingerprint)


@no_inline
def _dqpsk_detect_workload(
    iterations: Int,
    salt: Int,
    first: Span[Complex64, ...],
    second: Span[Complex64, ...],
    measure: Bool,
) raises -> _WorkloadMeasurement:
    var elapsed = UInt64(0)
    var full_checksum = UInt64(1469598103934665603)
    var fingerprint = UInt64(1469598103934665603)
    for operation in range(iterations):
        var bits: List[UInt8]
        var start = UInt64(0)
        if measure:
            start = global_perf_counter_ns()
        if ((operation + salt) & 1) == 0:
            bits = wifi_dsss_dqpsk_despread_hard(black_box(first))
        else:
            bits = wifi_dsss_dqpsk_despread_hard(black_box(second))
        if measure:
            elapsed += global_perf_counter_ns() - start
        full_checksum = _mix_bits(full_checksum, Span(bits))
        fingerprint = _mix(
            fingerprint,
            Int(_fingerprint_bits(Span(bits)) & UInt64(Int.MAX))
            + operation,
        )
        keep(bits)
    return _WorkloadMeasurement(elapsed, full_checksum, fingerprint)


@no_inline
def _cck5_codeword_workload(
    iterations: Int,
    salt: Int,
    first: Span[UInt8, ...],
    second: Span[UInt8, ...],
    measure: Bool,
) raises -> _WorkloadMeasurement:
    var elapsed = UInt64(0)
    var full_checksum = UInt64(1469598103934665603)
    var fingerprint = UInt64(1469598103934665603)
    for operation in range(iterations):
        var selector = operation + salt
        var start = UInt64(0)
        if measure:
            start = global_perf_counter_ns()
        var symbol = (
            wifi_cck_5_5_codeword(
                black_box(first),
                previous_phase_quadrant=black_box((selector >> 1) & 3),
                symbol_index=black_box(selector & 0x7FFFFFFF),
            )
            if (selector & 1) == 0
            else wifi_cck_5_5_codeword(
                black_box(second),
                previous_phase_quadrant=black_box((selector >> 1) & 3),
                symbol_index=black_box(selector & 0x7FFFFFFF),
            )
        )
        if measure:
            elapsed += global_perf_counter_ns() - start
        full_checksum = _mix_chips(full_checksum, Span(symbol.chips))
        full_checksum = _mix(full_checksum, symbol.phase_quadrant)
        full_checksum = _mix(full_checksum, symbol.phase_change_quadrant)
        fingerprint = _mix(
            fingerprint,
            Int(
                _mix(
                    _fingerprint_chips(Span(symbol.chips)),
                    symbol.phase_quadrant * 17
                    + symbol.phase_change_quadrant,
                )
                & UInt64(Int.MAX)
            )
            + operation,
        )
        keep(symbol)
    return _WorkloadMeasurement(elapsed, full_checksum, fingerprint)


@no_inline
def _cck11_codeword_workload(
    iterations: Int,
    salt: Int,
    first: Span[UInt8, ...],
    second: Span[UInt8, ...],
    measure: Bool,
) raises -> _WorkloadMeasurement:
    var elapsed = UInt64(0)
    var full_checksum = UInt64(1469598103934665603)
    var fingerprint = UInt64(1469598103934665603)
    for operation in range(iterations):
        var selector = operation + salt
        var start = UInt64(0)
        if measure:
            start = global_perf_counter_ns()
        var symbol = (
            wifi_cck_11_codeword(
                black_box(first),
                previous_phase_quadrant=black_box((selector >> 1) & 3),
                symbol_index=black_box(selector & 0x7FFFFFFF),
            )
            if (selector & 1) == 0
            else wifi_cck_11_codeword(
                black_box(second),
                previous_phase_quadrant=black_box((selector >> 1) & 3),
                symbol_index=black_box(selector & 0x7FFFFFFF),
            )
        )
        if measure:
            elapsed += global_perf_counter_ns() - start
        full_checksum = _mix_chips(full_checksum, Span(symbol.chips))
        full_checksum = _mix(full_checksum, symbol.phase_quadrant)
        full_checksum = _mix(full_checksum, symbol.phase_change_quadrant)
        fingerprint = _mix(
            fingerprint,
            Int(
                _mix(
                    _fingerprint_chips(Span(symbol.chips)),
                    symbol.phase_quadrant * 17
                    + symbol.phase_change_quadrant,
                )
                & UInt64(Int.MAX)
            )
            + operation,
        )
        keep(symbol)
    return _WorkloadMeasurement(elapsed, full_checksum, fingerprint)


@no_inline
def _cck5_map_workload(
    iterations: Int,
    salt: Int,
    first: Span[UInt8, ...],
    second: Span[UInt8, ...],
    measure: Bool,
) raises -> _WorkloadMeasurement:
    var elapsed = UInt64(0)
    var full_checksum = UInt64(1469598103934665603)
    var fingerprint = UInt64(1469598103934665603)
    for operation in range(iterations):
        var chips: List[Complex64]
        var start = UInt64(0)
        if measure:
            start = global_perf_counter_ns()
        if ((operation + salt) & 1) == 0:
            chips = wifi_cck_5_5_map(black_box(first))
        else:
            chips = wifi_cck_5_5_map(black_box(second))
        if measure:
            elapsed += global_perf_counter_ns() - start
        full_checksum = _mix_chips(full_checksum, Span(chips))
        fingerprint = _mix(
            fingerprint,
            Int(_fingerprint_chips(Span(chips)) & UInt64(Int.MAX))
            + operation,
        )
        keep(chips)
    return _WorkloadMeasurement(elapsed, full_checksum, fingerprint)


@no_inline
def _cck5_detect_workload(
    iterations: Int,
    salt: Int,
    first: Span[Complex64, ...],
    second: Span[Complex64, ...],
    measure: Bool,
) raises -> _WorkloadMeasurement:
    var elapsed = UInt64(0)
    var full_checksum = UInt64(1469598103934665603)
    var fingerprint = UInt64(1469598103934665603)
    for operation in range(iterations):
        var bits: List[UInt8]
        var start = UInt64(0)
        if measure:
            start = global_perf_counter_ns()
        if ((operation + salt) & 1) == 0:
            bits = wifi_cck_5_5_demap_hard(black_box(first))
        else:
            bits = wifi_cck_5_5_demap_hard(black_box(second))
        if measure:
            elapsed += global_perf_counter_ns() - start
        full_checksum = _mix_bits(full_checksum, Span(bits))
        fingerprint = _mix(
            fingerprint,
            Int(_fingerprint_bits(Span(bits)) & UInt64(Int.MAX))
            + operation,
        )
        keep(bits)
    return _WorkloadMeasurement(elapsed, full_checksum, fingerprint)


@no_inline
def _cck11_map_workload(
    iterations: Int,
    salt: Int,
    first: Span[UInt8, ...],
    second: Span[UInt8, ...],
    measure: Bool,
) raises -> _WorkloadMeasurement:
    var elapsed = UInt64(0)
    var full_checksum = UInt64(1469598103934665603)
    var fingerprint = UInt64(1469598103934665603)
    for operation in range(iterations):
        var chips: List[Complex64]
        var start = UInt64(0)
        if measure:
            start = global_perf_counter_ns()
        if ((operation + salt) & 1) == 0:
            chips = wifi_cck_11_map(black_box(first))
        else:
            chips = wifi_cck_11_map(black_box(second))
        if measure:
            elapsed += global_perf_counter_ns() - start
        full_checksum = _mix_chips(full_checksum, Span(chips))
        fingerprint = _mix(
            fingerprint,
            Int(_fingerprint_chips(Span(chips)) & UInt64(Int.MAX))
            + operation,
        )
        keep(chips)
    return _WorkloadMeasurement(elapsed, full_checksum, fingerprint)


@no_inline
def _cck11_detect_workload(
    iterations: Int,
    salt: Int,
    first: Span[Complex64, ...],
    second: Span[Complex64, ...],
    measure: Bool,
) raises -> _WorkloadMeasurement:
    var elapsed = UInt64(0)
    var full_checksum = UInt64(1469598103934665603)
    var fingerprint = UInt64(1469598103934665603)
    for operation in range(iterations):
        var bits: List[UInt8]
        var start = UInt64(0)
        if measure:
            start = global_perf_counter_ns()
        if ((operation + salt) & 1) == 0:
            bits = wifi_cck_11_demap_hard(black_box(first))
        else:
            bits = wifi_cck_11_demap_hard(black_box(second))
        if measure:
            elapsed += global_perf_counter_ns() - start
        full_checksum = _mix_bits(full_checksum, Span(bits))
        fingerprint = _mix(
            fingerprint,
            Int(_fingerprint_bits(Span(bits)) & UInt64(Int.MAX))
            + operation,
        )
        keep(bits)
    return _WorkloadMeasurement(elapsed, full_checksum, fingerprint)


def main() raises:
    var dbits_a = _bits(16, UInt64(0xD551))
    var dbits_b = _bits(16, UInt64(0xD552))
    var qbits_a = _bits(16, UInt64(0xD553))
    var qbits_b = _bits(16, UInt64(0xD554))
    var cck5_word_a = _bits(4, UInt64(0xCC51))
    var cck5_word_b = _bits(4, UInt64(0xCC52))
    var cck11_word_a = _bits(8, UInt64(0xCC11))
    var cck11_word_b = _bits(8, UInt64(0xCC12))
    var cck5_bits_a = _bits(4 * _STREAM_SYMBOLS, UInt64(0x5501))
    var cck5_bits_b = _bits(4 * _STREAM_SYMBOLS, UInt64(0x5502))
    var cck11_bits_a = _bits(8 * _STREAM_SYMBOLS, UInt64(0x1101))
    var cck11_bits_b = _bits(8 * _STREAM_SYMBOLS, UInt64(0x1102))
    var dbpsk_a = wifi_dsss_dbpsk_spread(Span(dbits_a))
    var dbpsk_b = wifi_dsss_dbpsk_spread(Span(dbits_b))
    var dqpsk_a = wifi_dsss_dqpsk_spread(Span(qbits_a))
    var dqpsk_b = wifi_dsss_dqpsk_spread(Span(qbits_b))
    var cck5_a = wifi_cck_5_5_map(Span(cck5_bits_a))
    var cck5_b = wifi_cck_5_5_map(Span(cck5_bits_b))
    var cck11_a = wifi_cck_11_map(Span(cck11_bits_a))
    var cck11_b = wifi_cck_11_map(Span(cck11_bits_b))

    for warmup in range(_WARMUPS):
        var salt = 324508639 + warmup
        keep(_barker_workload(_FAST_BATCH, False))
        keep(_dbpsk_spread_workload(
            _MAP_BATCH, salt, Span(dbits_a), Span(dbits_b), False
        ))
        keep(_dbpsk_detect_workload(
            _MAP_BATCH, salt, Span(dbpsk_a), Span(dbpsk_b), False
        ))
        keep(_dqpsk_spread_workload(
            _MAP_BATCH, salt, Span(qbits_a), Span(qbits_b), False
        ))
        keep(_dqpsk_detect_workload(
            _MAP_BATCH, salt, Span(dqpsk_a), Span(dqpsk_b), False
        ))
        keep(_cck5_codeword_workload(
            _FAST_BATCH,
            salt,
            Span(cck5_word_a),
            Span(cck5_word_b),
            False,
        ))
        keep(_cck11_codeword_workload(
            _FAST_BATCH,
            salt,
            Span(cck11_word_a),
            Span(cck11_word_b),
            False,
        ))
        keep(_cck5_map_workload(
            _MAP_BATCH, salt, Span(cck5_bits_a), Span(cck5_bits_b), False
        ))
        keep(_cck5_detect_workload(
            _CCK5_DETECT_BATCH,
            salt,
            Span(cck5_a),
            Span(cck5_b),
            False,
        ))
        keep(_cck11_map_workload(
            _MAP_BATCH,
            salt,
            Span(cck11_bits_a),
            Span(cck11_bits_b),
            False,
        ))
        keep(_cck11_detect_workload(
            _CCK11_DETECT_BATCH,
            salt,
            Span(cck11_a),
            Span(cck11_b),
            False,
        ))

    var barker_samples = List[UInt64](capacity=_SAMPLES)
    var dbpsk_map_samples = List[UInt64](capacity=_SAMPLES)
    var dbpsk_detect_samples = List[UInt64](capacity=_SAMPLES)
    var dqpsk_map_samples = List[UInt64](capacity=_SAMPLES)
    var dqpsk_detect_samples = List[UInt64](capacity=_SAMPLES)
    var cck5_word_samples = List[UInt64](capacity=_SAMPLES)
    var cck11_word_samples = List[UInt64](capacity=_SAMPLES)
    var cck5_map_samples = List[UInt64](capacity=_SAMPLES)
    var cck5_detect_samples = List[UInt64](capacity=_SAMPLES)
    var cck11_map_samples = List[UInt64](capacity=_SAMPLES)
    var cck11_detect_samples = List[UInt64](capacity=_SAMPLES)
    var full_output_checksum = UInt64(1469598103934665603)
    var fingerprint_checksum = UInt64(1469598103934665603)

    for sample in range(_SAMPLES):
        var salt = 324508639 + sample
        _record_measurement(
            _barker_workload(_FAST_BATCH, True),
            barker_samples,
            full_output_checksum,
            fingerprint_checksum,
        )
        _record_measurement(
            _dbpsk_spread_workload(
                _MAP_BATCH, salt, Span(dbits_a), Span(dbits_b), True
            ),
            dbpsk_map_samples,
            full_output_checksum,
            fingerprint_checksum,
        )
        _record_measurement(
            _dbpsk_detect_workload(
                _MAP_BATCH, salt, Span(dbpsk_a), Span(dbpsk_b), True
            ),
            dbpsk_detect_samples,
            full_output_checksum,
            fingerprint_checksum,
        )
        _record_measurement(
            _dqpsk_spread_workload(
                _MAP_BATCH, salt, Span(qbits_a), Span(qbits_b), True
            ),
            dqpsk_map_samples,
            full_output_checksum,
            fingerprint_checksum,
        )
        _record_measurement(
            _dqpsk_detect_workload(
                _MAP_BATCH, salt, Span(dqpsk_a), Span(dqpsk_b), True
            ),
            dqpsk_detect_samples,
            full_output_checksum,
            fingerprint_checksum,
        )
        _record_measurement(
            _cck5_codeword_workload(
                _FAST_BATCH,
                salt,
                Span(cck5_word_a),
                Span(cck5_word_b),
                True,
            ),
            cck5_word_samples,
            full_output_checksum,
            fingerprint_checksum,
        )
        _record_measurement(
            _cck11_codeword_workload(
                _FAST_BATCH,
                salt,
                Span(cck11_word_a),
                Span(cck11_word_b),
                True,
            ),
            cck11_word_samples,
            full_output_checksum,
            fingerprint_checksum,
        )
        _record_measurement(
            _cck5_map_workload(
                _MAP_BATCH,
                salt,
                Span(cck5_bits_a),
                Span(cck5_bits_b),
                True,
            ),
            cck5_map_samples,
            full_output_checksum,
            fingerprint_checksum,
        )
        _record_measurement(
            _cck5_detect_workload(
                _CCK5_DETECT_BATCH,
                salt,
                Span(cck5_a),
                Span(cck5_b),
                True,
            ),
            cck5_detect_samples,
            full_output_checksum,
            fingerprint_checksum,
        )
        _record_measurement(
            _cck11_map_workload(
                _MAP_BATCH,
                salt,
                Span(cck11_bits_a),
                Span(cck11_bits_b),
                True,
            ),
            cck11_map_samples,
            full_output_checksum,
            fingerprint_checksum,
        )
        _record_measurement(
            _cck11_detect_workload(
                _CCK11_DETECT_BATCH,
                salt,
                Span(cck11_a),
                Span(cck11_b),
                True,
            ),
            cck11_detect_samples,
            full_output_checksum,
            fingerprint_checksum,
        )

    print_benchmark_metadata()
    print("wifi_dsss_cck_backend: scalar-reference")
    print("wifi_dsss_cck_scope: clause-15-16-chip-symbols-only")
    print("wifi_dsss_cck_input_variation: fixed-salted-valid-streams")
    print("wifi_dsss_cck_timed_scope: target-api-only")
    print("wifi_dsss_cck_post_timer_scope: keep-plus-full-output-checksum-plus-o1-fingerprint")
    report_timing_samples(
        "wifi_dsss_barker_sequence",
        barker_samples,
        _WARMUPS,
        _FAST_BATCH * WIFI_DSSS_BARKER_CHIPS,
        "barker_chip",
    )
    report_timing_samples(
        "wifi_dsss_dbpsk_spread",
        dbpsk_map_samples,
        _WARMUPS,
        _MAP_BATCH * len(dbits_a) * WIFI_DSSS_BARKER_CHIPS,
        "mapped_chip",
    )
    report_timing_samples(
        "wifi_dsss_dbpsk_despread_hard",
        dbpsk_detect_samples,
        _WARMUPS,
        _MAP_BATCH * len(dbits_a),
        "detected_bit",
    )
    report_timing_samples(
        "wifi_dsss_dqpsk_spread",
        dqpsk_map_samples,
        _WARMUPS,
        _MAP_BATCH * (len(qbits_a) // 2) * WIFI_DSSS_BARKER_CHIPS,
        "mapped_chip",
    )
    report_timing_samples(
        "wifi_dsss_dqpsk_despread_hard",
        dqpsk_detect_samples,
        _WARMUPS,
        _MAP_BATCH * len(qbits_a),
        "detected_bit",
    )
    report_timing_samples(
        "wifi_cck_5_5_codeword",
        cck5_word_samples,
        _WARMUPS,
        _FAST_BATCH * WIFI_CCK_CHIPS,
        "mapped_chip",
    )
    report_timing_samples(
        "wifi_cck_11_codeword",
        cck11_word_samples,
        _WARMUPS,
        _FAST_BATCH * WIFI_CCK_CHIPS,
        "mapped_chip",
    )
    report_timing_samples(
        "wifi_cck_5_5_map",
        cck5_map_samples,
        _WARMUPS,
        _MAP_BATCH * _STREAM_SYMBOLS * WIFI_CCK_CHIPS,
        "mapped_chip",
    )
    report_timing_samples(
        "wifi_cck_5_5_demap_hard",
        cck5_detect_samples,
        _WARMUPS,
        _CCK5_DETECT_BATCH * _STREAM_SYMBOLS,
        "detected_symbol",
    )
    report_timing_samples(
        "wifi_cck_11_map",
        cck11_map_samples,
        _WARMUPS,
        _MAP_BATCH * _STREAM_SYMBOLS * WIFI_CCK_CHIPS,
        "mapped_chip",
    )
    report_timing_samples(
        "wifi_cck_11_demap_hard",
        cck11_detect_samples,
        _WARMUPS,
        _CCK11_DETECT_BATCH * _STREAM_SYMBOLS,
        "detected_symbol",
    )
    keep(full_output_checksum)
    keep(fingerprint_checksum)
    print("wifi_dsss_cck_full_output_checksum:", full_output_checksum)
    print("wifi_dsss_cck_fingerprint_checksum:", fingerprint_checksum)
