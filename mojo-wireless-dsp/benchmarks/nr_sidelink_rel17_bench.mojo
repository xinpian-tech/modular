"""Attributable scalar-CPU timings for Rel-17 SCI-1A and PSCCH.

Each ledger-backed public API owns a separate no-inline timed entry and report.
All configs, Lists, Spans, and derived fixtures precede the timer.  The timed
region invokes one target API, then the full owned result is retained and an
O(1) endpoint fingerprint is computed after the timer has stopped.
"""

from std.benchmark import keep
from std.collections import Span
from std.time import global_perf_counter_ns
from wireless_dsp.benchmarking import (
    print_benchmark_metadata,
    report_timing_samples,
)
from wireless_dsp.core import Complex64
from wireless_dsp.wireless.nr.sidelink_rel17 import (
    NRSLSCI1AConfig,
    NRSLSCI1AFields,
    nr_sl_sci1a_frequency_assignment_bits,
    nr_sl_sci1a_payload_bit_count,
    nr_sl_sci1a_pack,
    nr_sl_sci_crc24c,
    nr_sl_sci_crc24c_attach,
    nr_sl_sci_crc24c_check,
    nr_sl_pscch_rate_matched_bit_count,
    nr_sl_pscch_scramble,
    nr_sl_pscch_descramble_llrs,
    nr_sl_pscch_data_resource_elements,
    nr_sl_pscch_dmrs_resource_elements,
    nr_sl_pscch_dmrs_c_init,
    nr_sl_pscch_dmrs,
    nr_sl_pscch_encode,
    nr_sl_pscch_decode,
)


comptime _WARMUPS = 3
comptime _SAMPLES = 9


def _mix(checksum: UInt64, value: UInt64) -> UInt64:
    return (checksum ^ value) * UInt64(1099511628211)


def _require_repeat(first: UInt64, second: UInt64) raises:
    if first != second:
        raise Error("fixed sidelink benchmark result is nondeterministic")
    keep(first)
    keep(second)


def _fingerprint_float(value: Float64) -> UInt64:
    var magnitude = UInt64(Int(abs(value) * 1_000_000.0))
    return _mix(magnitude, UInt64(1 if value < 0.0 else 0))


def _fingerprint_complex(value: Complex64) -> UInt64:
    return _mix(
        _fingerprint_float(value.re), _fingerprint_float(value.im)
    )


def _fingerprint_uint8(values: List[UInt8]) -> UInt64:
    var fingerprint = UInt64(len(values))
    if len(values) > 0:
        fingerprint = _mix(fingerprint, UInt64(values[0]))
        fingerprint = _mix(
            fingerprint, UInt64(values[len(values) - 1])
        )
    return fingerprint


def _fingerprint_float64(values: List[Float64]) -> UInt64:
    var fingerprint = UInt64(len(values))
    if len(values) > 0:
        fingerprint = _mix(fingerprint, _fingerprint_float(values[0]))
        fingerprint = _mix(
            fingerprint, _fingerprint_float(values[len(values) - 1])
        )
    return fingerprint


def _fingerprint_complex64(values: List[Complex64]) -> UInt64:
    var fingerprint = UInt64(len(values))
    if len(values) > 0:
        fingerprint = _mix(fingerprint, _fingerprint_complex(values[0]))
        fingerprint = _mix(
            fingerprint,
            _fingerprint_complex(values[len(values) - 1]),
        )
    return fingerprint


def _finish_sample(
    name: StringSlice,
    mut samples: List[UInt64],
    checksum: UInt64,
) raises -> UInt64:
    report_timing_samples(name, samples, _WARMUPS, 1, "api_call")
    keep(samples)
    return checksum


def _config() raises -> NRSLSCI1AConfig:
    return NRSLSCI1AConfig(10, 3, 16, 3, 2, 2, 4, True)


def _fields() -> NRSLSCI1AFields:
    return NRSLSCI1AFields(
        3,
        123,
        77,
        5,
        2,
        1,
        2,
        True,
        19,
        2,
        True,
        True,
    )


def _repeated_bits(source: Span[UInt8, ...], length: Int) -> List[UInt8]:
    var result = List[UInt8](capacity=length)
    for index in range(length):
        result.append(source[index % len(source)])
    return result^


def _llrs(bits: Span[UInt8, ...], magnitude: Float64) -> List[Float64]:
    var result = List[Float64](capacity=len(bits))
    for index in range(len(bits)):
        result.append(magnitude if bits[index] == 0 else -magnitude)
    return result^


@no_inline
def _bench_nr_sl_sci1a_frequency_assignment_bits(
    number_subchannels: Int, max_num_per_reserve: Int
) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_sl_sci1a_frequency_assignment_bits(
        number_subchannels, max_num_per_reserve
    )
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = UInt64(result)
    return (elapsed, fingerprint)


def _run_nr_sl_sci1a_frequency_assignment_bits() raises -> UInt64:
    var number_subchannels = 10
    var max_num_per_reserve = 3
    var first = _bench_nr_sl_sci1a_frequency_assignment_bits(
        number_subchannels, max_num_per_reserve
    )
    var second = _bench_nr_sl_sci1a_frequency_assignment_bits(
        number_subchannels, max_num_per_reserve
    )
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_sl_sci1a_frequency_assignment_bits(
            number_subchannels, max_num_per_reserve
        ))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_sl_sci1a_frequency_assignment_bits(
            number_subchannels, max_num_per_reserve
        )
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample(
        "nr_sl_sci1a_frequency_assignment_bits", samples, checksum
    )


@no_inline
def _bench_nr_sl_sci1a_payload_bit_count(
    config: NRSLSCI1AConfig
) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_sl_sci1a_payload_bit_count(config)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = UInt64(result)
    return (elapsed, fingerprint)


def _run_nr_sl_sci1a_payload_bit_count() raises -> UInt64:
    var config = _config()
    var first = _bench_nr_sl_sci1a_payload_bit_count(config)
    var second = _bench_nr_sl_sci1a_payload_bit_count(config)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_sl_sci1a_payload_bit_count(config))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_sl_sci1a_payload_bit_count(config)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample(
        "nr_sl_sci1a_payload_bit_count", samples, checksum
    )


@no_inline
def _bench_nr_sl_sci1a_pack(
    config: NRSLSCI1AConfig, fields: NRSLSCI1AFields
) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_sl_sci1a_pack(config, fields)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _fingerprint_uint8(result)
    return (elapsed, fingerprint)


def _run_nr_sl_sci1a_pack() raises -> UInt64:
    var config = _config()
    var fields = _fields()
    var first = _bench_nr_sl_sci1a_pack(config, fields)
    var second = _bench_nr_sl_sci1a_pack(config, fields)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_sl_sci1a_pack(config, fields))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_sl_sci1a_pack(config, fields)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_sl_sci1a_pack", samples, checksum)


@no_inline
def _bench_nr_sl_sci_crc24c(
    payload: Span[UInt8, ...]
) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_sl_sci_crc24c(payload)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = result
    return (elapsed, fingerprint)


def _run_nr_sl_sci_crc24c() raises -> UInt64:
    var config = _config()
    var fields = _fields()
    var payload = nr_sl_sci1a_pack(config, fields)
    var payload_span = Span(payload)
    var first = _bench_nr_sl_sci_crc24c(payload_span)
    var second = _bench_nr_sl_sci_crc24c(payload_span)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_sl_sci_crc24c(payload_span))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_sl_sci_crc24c(payload_span)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_sl_sci_crc24c", samples, checksum)


@no_inline
def _bench_nr_sl_sci_crc24c_attach(
    payload: Span[UInt8, ...]
) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_sl_sci_crc24c_attach(payload)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _fingerprint_uint8(result)
    return (elapsed, fingerprint)


def _run_nr_sl_sci_crc24c_attach() raises -> UInt64:
    var config = _config()
    var fields = _fields()
    var payload = nr_sl_sci1a_pack(config, fields)
    var payload_span = Span(payload)
    var first = _bench_nr_sl_sci_crc24c_attach(payload_span)
    var second = _bench_nr_sl_sci_crc24c_attach(payload_span)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_sl_sci_crc24c_attach(payload_span))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_sl_sci_crc24c_attach(payload_span)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_sl_sci_crc24c_attach", samples, checksum)


@no_inline
def _bench_nr_sl_sci_crc24c_check(
    attached: Span[UInt8, ...]
) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_sl_sci_crc24c_check(attached)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = UInt64(1 if result else 0)
    return (elapsed, fingerprint)


def _run_nr_sl_sci_crc24c_check() raises -> UInt64:
    var config = _config()
    var fields = _fields()
    var payload = nr_sl_sci1a_pack(config, fields)
    var attached = nr_sl_sci_crc24c_attach(Span(payload))
    var attached_span = Span(attached)
    var first = _bench_nr_sl_sci_crc24c_check(attached_span)
    var second = _bench_nr_sl_sci_crc24c_check(attached_span)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_sl_sci_crc24c_check(attached_span))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_sl_sci_crc24c_check(attached_span)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_sl_sci_crc24c_check", samples, checksum)


@no_inline
def _bench_nr_sl_pscch_rate_matched_bit_count(
    resource_blocks: Int, duration: Int
) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_sl_pscch_rate_matched_bit_count(
        resource_blocks, duration
    )
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = UInt64(result)
    return (elapsed, fingerprint)


def _run_nr_sl_pscch_rate_matched_bit_count() raises -> UInt64:
    var resource_blocks = 10
    var duration = 3
    var first = _bench_nr_sl_pscch_rate_matched_bit_count(
        resource_blocks, duration
    )
    var second = _bench_nr_sl_pscch_rate_matched_bit_count(
        resource_blocks, duration
    )
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_sl_pscch_rate_matched_bit_count(
            resource_blocks, duration
        ))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_sl_pscch_rate_matched_bit_count(
            resource_blocks, duration
        )
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample(
        "nr_sl_pscch_rate_matched_bit_count", samples, checksum
    )


@no_inline
def _bench_nr_sl_pscch_scramble(
    bits: Span[UInt8, ...]
) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_sl_pscch_scramble(bits)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _fingerprint_uint8(result)
    return (elapsed, fingerprint)


def _run_nr_sl_pscch_scramble() raises -> UInt64:
    var config = _config()
    var fields = _fields()
    var payload = nr_sl_sci1a_pack(config, fields)
    var bits = _repeated_bits(Span(payload), 540)
    var bits_span = Span(bits)
    var first = _bench_nr_sl_pscch_scramble(bits_span)
    var second = _bench_nr_sl_pscch_scramble(bits_span)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_sl_pscch_scramble(bits_span))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_sl_pscch_scramble(bits_span)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_sl_pscch_scramble", samples, checksum)


@no_inline
def _bench_nr_sl_pscch_descramble_llrs(
    llrs: Span[Float64, ...]
) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_sl_pscch_descramble_llrs(llrs)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _fingerprint_float64(result)
    return (elapsed, fingerprint)


def _run_nr_sl_pscch_descramble_llrs() raises -> UInt64:
    var config = _config()
    var fields = _fields()
    var payload = nr_sl_sci1a_pack(config, fields)
    var bits = _repeated_bits(Span(payload), 540)
    var llrs = _llrs(Span(bits), 8.0)
    var llrs_span = Span(llrs)
    var first = _bench_nr_sl_pscch_descramble_llrs(llrs_span)
    var second = _bench_nr_sl_pscch_descramble_llrs(llrs_span)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_sl_pscch_descramble_llrs(llrs_span))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_sl_pscch_descramble_llrs(llrs_span)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample(
        "nr_sl_pscch_descramble_llrs", samples, checksum
    )


@no_inline
def _bench_nr_sl_pscch_dmrs_c_init(
    slot: Int, symbol: Int, scrambling_id: Int
) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_sl_pscch_dmrs_c_init(slot, symbol, scrambling_id)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = UInt64(result)
    return (elapsed, fingerprint)


def _run_nr_sl_pscch_dmrs_c_init() raises -> UInt64:
    var slot = 7
    var symbol = 2
    var scrambling_id = 0x1234
    var first = _bench_nr_sl_pscch_dmrs_c_init(
        slot, symbol, scrambling_id
    )
    var second = _bench_nr_sl_pscch_dmrs_c_init(
        slot, symbol, scrambling_id
    )
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_sl_pscch_dmrs_c_init(
            slot, symbol, scrambling_id
        ))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_sl_pscch_dmrs_c_init(
            slot, symbol, scrambling_id
        )
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_sl_pscch_dmrs_c_init", samples, checksum)


@no_inline
def _bench_nr_sl_pscch_dmrs(
    slot: Int,
    symbol: Int,
    scrambling_id: Int,
    resource_blocks: Int,
    first_resource_block: Int,
) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_sl_pscch_dmrs(
        slot,
        symbol,
        scrambling_id,
        resource_blocks,
        first_resource_block=first_resource_block,
    )
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _fingerprint_complex64(result)
    return (elapsed, fingerprint)


def _run_nr_sl_pscch_dmrs() raises -> UInt64:
    var slot = 7
    var symbol = 2
    var scrambling_id = 0x1234
    var resource_blocks = 10
    var first_resource_block = 20
    var first = _bench_nr_sl_pscch_dmrs(
        slot, symbol, scrambling_id, resource_blocks, first_resource_block
    )
    var second = _bench_nr_sl_pscch_dmrs(
        slot, symbol, scrambling_id, resource_blocks, first_resource_block
    )
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_sl_pscch_dmrs(
            slot,
            symbol,
            scrambling_id,
            resource_blocks,
            first_resource_block,
        ))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_sl_pscch_dmrs(
            slot,
            symbol,
            scrambling_id,
            resource_blocks,
            first_resource_block,
        )
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_sl_pscch_dmrs", samples, checksum)


@no_inline
def _bench_nr_sl_pscch_data_resource_elements(
    resource_blocks: Int,
    duration: Int,
    first_symbol: Int,
    first_resource_block: Int,
) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_sl_pscch_data_resource_elements(
        resource_blocks,
        duration,
        first_available_symbol=first_symbol,
        first_resource_block=first_resource_block,
    )
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = UInt64(len(result))
    fingerprint = _mix(fingerprint, UInt64(result[0].sequence_index))
    fingerprint = _mix(
        fingerprint, UInt64(result[len(result) - 1].subcarrier)
    )
    fingerprint = _mix(
        fingerprint,
        UInt64(1 if result[len(result) - 1].is_duplicate else 0),
    )
    return (elapsed, fingerprint)


def _run_nr_sl_pscch_data_resource_elements() raises -> UInt64:
    var resource_blocks = 10
    var duration = 3
    var first_symbol = 1
    var first_resource_block = 20
    var first = _bench_nr_sl_pscch_data_resource_elements(
        resource_blocks, duration, first_symbol, first_resource_block
    )
    var second = _bench_nr_sl_pscch_data_resource_elements(
        resource_blocks, duration, first_symbol, first_resource_block
    )
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_sl_pscch_data_resource_elements(
            resource_blocks, duration, first_symbol, first_resource_block
        ))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_sl_pscch_data_resource_elements(
            resource_blocks, duration, first_symbol, first_resource_block
        )
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample(
        "nr_sl_pscch_data_resource_elements", samples, checksum
    )


@no_inline
def _bench_nr_sl_pscch_dmrs_resource_elements(
    resource_blocks: Int,
    duration: Int,
    first_symbol: Int,
    first_resource_block: Int,
) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_sl_pscch_dmrs_resource_elements(
        resource_blocks,
        duration,
        first_available_symbol=first_symbol,
        first_resource_block=first_resource_block,
    )
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = UInt64(len(result))
    fingerprint = _mix(fingerprint, UInt64(result[0].sequence_index))
    fingerprint = _mix(
        fingerprint, UInt64(result[len(result) - 1].subcarrier)
    )
    fingerprint = _mix(
        fingerprint,
        UInt64(1 if result[len(result) - 1].is_duplicate else 0),
    )
    return (elapsed, fingerprint)


def _run_nr_sl_pscch_dmrs_resource_elements() raises -> UInt64:
    var resource_blocks = 10
    var duration = 3
    var first_symbol = 1
    var first_resource_block = 20
    var first = _bench_nr_sl_pscch_dmrs_resource_elements(
        resource_blocks, duration, first_symbol, first_resource_block
    )
    var second = _bench_nr_sl_pscch_dmrs_resource_elements(
        resource_blocks, duration, first_symbol, first_resource_block
    )
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_sl_pscch_dmrs_resource_elements(
            resource_blocks, duration, first_symbol, first_resource_block
        ))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_sl_pscch_dmrs_resource_elements(
            resource_blocks, duration, first_symbol, first_resource_block
        )
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample(
        "nr_sl_pscch_dmrs_resource_elements", samples, checksum
    )


@no_inline
def _bench_nr_sl_pscch_encode(
    payload: Span[UInt8, ...],
    resource_blocks: Int,
    duration: Int,
    first_symbol: Int,
    first_resource_block: Int,
) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_sl_pscch_encode(
        payload,
        resource_blocks,
        duration,
        first_available_symbol=first_symbol,
        first_resource_block=first_resource_block,
    )
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = UInt64(len(result.payload))
    fingerprint = _mix(fingerprint, UInt64(len(result.scrambled)))
    fingerprint = _mix(fingerprint, UInt64(len(result.qpsk_symbols)))
    fingerprint = _mix(
        fingerprint, UInt64(len(result.data_resource_elements))
    )
    fingerprint = _mix(fingerprint, UInt64(result.scrambled[0]))
    fingerprint = _mix(
        fingerprint,
        UInt64(result.scrambled[len(result.scrambled) - 1]),
    )
    return (elapsed, fingerprint)


def _run_nr_sl_pscch_encode() raises -> UInt64:
    var config = _config()
    var fields = _fields()
    var payload = nr_sl_sci1a_pack(config, fields)
    var payload_span = Span(payload)
    var resource_blocks = 10
    var duration = 3
    var first_symbol = 1
    var first_resource_block = 20
    var first = _bench_nr_sl_pscch_encode(
        payload_span,
        resource_blocks,
        duration,
        first_symbol,
        first_resource_block,
    )
    var second = _bench_nr_sl_pscch_encode(
        payload_span,
        resource_blocks,
        duration,
        first_symbol,
        first_resource_block,
    )
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_sl_pscch_encode(
            payload_span,
            resource_blocks,
            duration,
            first_symbol,
            first_resource_block,
        ))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_sl_pscch_encode(
            payload_span,
            resource_blocks,
            duration,
            first_symbol,
            first_resource_block,
        )
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_sl_pscch_encode", samples, checksum)


@no_inline
def _bench_nr_sl_pscch_decode(
    llrs: Span[Float64, ...],
    payload_bits: Int,
    resource_blocks: Int,
    duration: Int,
) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_sl_pscch_decode(
        llrs, payload_bits, resource_blocks, duration
    )
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _fingerprint_uint8(result.payload)
    fingerprint = _mix(
        fingerprint, UInt64(len(result.crc_attached))
    )
    fingerprint = _mix(fingerprint, UInt64(1 if result.crc_ok else 0))
    return (elapsed, fingerprint)


def _run_nr_sl_pscch_decode() raises -> UInt64:
    var config = _config()
    var fields = _fields()
    var payload = nr_sl_sci1a_pack(config, fields)
    var resource_blocks = 10
    var duration = 3
    var encoded = nr_sl_pscch_encode(
        Span(payload),
        resource_blocks,
        duration,
        first_available_symbol=1,
        first_resource_block=20,
    )
    var llrs = _llrs(Span(encoded.scrambled), 16.0)
    var llrs_span = Span(llrs)
    var payload_bits = len(payload)
    var first = _bench_nr_sl_pscch_decode(
        llrs_span, payload_bits, resource_blocks, duration
    )
    var second = _bench_nr_sl_pscch_decode(
        llrs_span, payload_bits, resource_blocks, duration
    )
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_sl_pscch_decode(
            llrs_span, payload_bits, resource_blocks, duration
        ))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_sl_pscch_decode(
            llrs_span, payload_bits, resource_blocks, duration
        )
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_sl_pscch_decode", samples, checksum)


# Compatibility entry points retained for existing ledger/Feature references.
# They delegate to independent runners and are never grouped timed regions.
def _pack_workload(iterations: Int, salt: Int) raises -> UInt64:
    keep(iterations)
    keep(salt)
    return (
        _run_nr_sl_sci1a_frequency_assignment_bits()
        ^ _run_nr_sl_sci1a_payload_bit_count()
        ^ _run_nr_sl_sci1a_pack()
    )


def _crc_scramble_workload(iterations: Int, salt: Int) raises -> UInt64:
    keep(iterations)
    keep(salt)
    return (
        _run_nr_sl_sci_crc24c()
        ^ _run_nr_sl_sci_crc24c_attach()
        ^ _run_nr_sl_sci_crc24c_check()
        ^ _run_nr_sl_pscch_scramble()
        ^ _run_nr_sl_pscch_descramble_llrs()
    )


def _mapping_workload(iterations: Int, salt: Int) raises -> UInt64:
    keep(iterations)
    keep(salt)
    return (
        _run_nr_sl_pscch_rate_matched_bit_count()
        ^ _run_nr_sl_pscch_dmrs_c_init()
        ^ _run_nr_sl_pscch_dmrs()
        ^ _run_nr_sl_pscch_data_resource_elements()
        ^ _run_nr_sl_pscch_dmrs_resource_elements()
    )


def _encode_workload(iterations: Int, salt: Int) raises -> UInt64:
    keep(iterations)
    keep(salt)
    return _run_nr_sl_pscch_encode() ^ _run_nr_sl_pscch_decode()


def main() raises:
    print_benchmark_metadata()
    print("nr_sidelink_rel17_backend:", "scalar-cpu-reference")
    print(
        "nr_sidelink_rel17_baselines:",
        "TS-38.211-V17.10.0/TS-38.212-V17.13.0/TS-38.213-V17.13.0/TS-38.331-V17.17.0",
    )
    var checksum = UInt64(1469598103934665603)
    checksum = _mix(
        checksum, _run_nr_sl_sci1a_frequency_assignment_bits()
    )
    checksum = _mix(checksum, _run_nr_sl_sci1a_payload_bit_count())
    checksum = _mix(checksum, _run_nr_sl_sci1a_pack())
    checksum = _mix(checksum, _run_nr_sl_sci_crc24c())
    checksum = _mix(checksum, _run_nr_sl_sci_crc24c_attach())
    checksum = _mix(checksum, _run_nr_sl_sci_crc24c_check())
    checksum = _mix(
        checksum, _run_nr_sl_pscch_rate_matched_bit_count()
    )
    checksum = _mix(checksum, _run_nr_sl_pscch_scramble())
    checksum = _mix(checksum, _run_nr_sl_pscch_descramble_llrs())
    checksum = _mix(checksum, _run_nr_sl_pscch_dmrs_c_init())
    checksum = _mix(checksum, _run_nr_sl_pscch_dmrs())
    checksum = _mix(
        checksum, _run_nr_sl_pscch_data_resource_elements()
    )
    checksum = _mix(
        checksum, _run_nr_sl_pscch_dmrs_resource_elements()
    )
    checksum = _mix(checksum, _run_nr_sl_pscch_encode())
    checksum = _mix(checksum, _run_nr_sl_pscch_decode())
    keep(checksum)
    print("nr_sidelink_rel17_retained_checksum:", checksum)
