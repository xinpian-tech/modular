"""Attributable CPU timings for bounded DSSS/HR-DSSS PLCP APIs.

Every public top-level API in ``dsss_plcp`` has a separately timed family.
Three complete warmups are outside the timer, followed by nine independent
odd samples.  A fixed salt varies valid inputs.  Only the target call is
timed; complete owned results are retained and fully consumed afterward, with
a separate O(1) endpoint fingerprint checksum.
"""

from std.benchmark import black_box, keep
from std.collections import Span
from std.time import global_perf_counter_ns
from wireless_dsp.core import Complex64
from wireless_dsp.benchmarking import (
    print_benchmark_metadata,
    report_timing_samples,
)
from wireless_dsp.wireless.wifi.dsss_plcp import (
    WIFI_DSSS_RATE_1_MBPS_KBPS,
    WIFI_DSSS_RATE_2_MBPS_KBPS,
    WIFI_DSSS_RATE_5_5_MBPS_KBPS,
    WIFI_DSSS_RATE_11_MBPS_KBPS,
    WifiDSSSPLCPConfig,
    wifi_dsss_plcp_scramble,
    wifi_dsss_plcp_descramble,
    wifi_dsss_plcp_crc16,
    wifi_dsss_plcp_preamble_bits,
    wifi_dsss_plcp_length,
    wifi_dsss_plcp_header_pack,
    wifi_dsss_plcp_header_parse,
    wifi_dsss_ppdu_tx,
    wifi_dsss_ppdu_rx,
)


comptime _WARMUPS = 3
comptime _SAMPLES = 9
comptime _FAST_BATCH = 2048
comptime _BIT_BATCH = 256
comptime _TX_BATCH = 16
comptime _RX_BATCH = 4


@fieldwise_init
struct _WorkloadMeasurement(Copyable, Movable):
    var elapsed_ns: UInt64
    var full_output_checksum: UInt64
    var fingerprint_checksum: UInt64


def _mix(checksum: UInt64, value: Int) -> UInt64:
    return (checksum ^ UInt64(value + 1)) * UInt64(1099511628211)


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


def _mix_bits(checksum: UInt64, bits: Span[UInt8, ...]) -> UInt64:
    var result = checksum
    for index in range(len(bits)):
        result = _mix(result, Int(bits[index]) + index)
    return result


def _mix_chips(checksum: UInt64, chips: Span[Complex64, ...]) -> UInt64:
    var result = checksum
    for index in range(len(chips)):
        var value = Complex64(chips[index].re, chips[index].im)
        var code = 0
        if value.re > 0.0:
            code |= 1
        elif value.re < 0.0:
            code |= 2
        if value.im > 0.0:
            code |= 4
        elif value.im < 0.0:
            code |= 8
        result = _mix(result, code + index)
    return result


def _fingerprint_bits(bits: Span[UInt8, ...]) -> UInt64:
    return _mix(
        _mix(UInt64(1469598103934665603), len(bits)),
        Int(bits[0]) * 17 + Int(bits[len(bits) - 1]) * 257,
    )


def _fingerprint_chips(chips: Span[Complex64, ...]) -> UInt64:
    var code = len(chips) * 257
    if chips[0].re > 0.0:
        code += 1
    if chips[0].im > 0.0:
        code += 2
    if chips[len(chips) - 1].re > 0.0:
        code += 4
    if chips[len(chips) - 1].im > 0.0:
        code += 8
    return _mix(UInt64(1469598103934665603), code)


def _pattern_bits(length: Int, seed: UInt64) -> List[UInt8]:
    var state = seed
    var result = List[UInt8](capacity=length)
    for _ in range(length):
        state = (
            state * UInt64(6364136223846793005)
            + UInt64(1442695040888963407)
        )
        result.append(UInt8((state >> UInt64(63)) & UInt64(1)))
    return result^


def _pattern_octets(length: Int, seed: UInt64) -> List[UInt8]:
    var state = seed
    var result = List[UInt8](capacity=length)
    for _ in range(length):
        state = (
            state * UInt64(2862933555777941757)
            + UInt64(3037000493)
        )
        result.append(UInt8(state >> UInt64(56)))
    return result^


@no_inline
def _scramble_workload(
    iterations: Int,
    salt: Int,
    first: Span[UInt8, ...],
    second: Span[UInt8, ...],
    measure: Bool,
) raises -> _WorkloadMeasurement:
    var elapsed = UInt64(0)
    var full_checksum = UInt64(1469598103934665603)
    var fingerprint = UInt64(1469598103934665603)
    for iteration in range(iterations):
        var output: List[UInt8]
        var start = UInt64(0)
        if measure:
            start = global_perf_counter_ns()
        if ((iteration + salt) & 1) == 0:
            output = wifi_dsss_plcp_scramble(
                black_box(first), black_box(0x6C)
            )
        else:
            output = wifi_dsss_plcp_scramble(
                black_box(second), black_box(0x1B)
            )
        if measure:
            elapsed += global_perf_counter_ns() - start
        full_checksum = _mix_bits(full_checksum, Span(output))
        fingerprint = _mix(
            fingerprint,
            Int(_fingerprint_bits(Span(output)) & UInt64(Int.MAX))
            + iteration,
        )
        keep(output)
    return _WorkloadMeasurement(elapsed, full_checksum, fingerprint)


@no_inline
def _descramble_workload(
    iterations: Int,
    salt: Int,
    first: Span[UInt8, ...],
    second: Span[UInt8, ...],
    measure: Bool,
) raises -> _WorkloadMeasurement:
    var elapsed = UInt64(0)
    var full_checksum = UInt64(1469598103934665603)
    var fingerprint = UInt64(1469598103934665603)
    for iteration in range(iterations):
        var output: List[UInt8]
        var start = UInt64(0)
        if measure:
            start = global_perf_counter_ns()
        if ((iteration + salt) & 1) == 0:
            output = wifi_dsss_plcp_descramble(
                black_box(first), black_box(0x6C)
            )
        else:
            output = wifi_dsss_plcp_descramble(
                black_box(second), black_box(0x1B)
            )
        if measure:
            elapsed += global_perf_counter_ns() - start
        full_checksum = _mix_bits(full_checksum, Span(output))
        fingerprint = _mix(
            fingerprint,
            Int(_fingerprint_bits(Span(output)) & UInt64(Int.MAX))
            + iteration,
        )
        keep(output)
    return _WorkloadMeasurement(elapsed, full_checksum, fingerprint)


@no_inline
def _crc_workload(
    iterations: Int,
    salt: Int,
    first: Span[UInt8, ...],
    second: Span[UInt8, ...],
    measure: Bool,
) raises -> _WorkloadMeasurement:
    var elapsed = UInt64(0)
    var full_checksum = UInt64(1469598103934665603)
    var fingerprint = UInt64(1469598103934665603)
    for iteration in range(iterations):
        var start = UInt64(0)
        if measure:
            start = global_perf_counter_ns()
        var value = (
            wifi_dsss_plcp_crc16(black_box(first))
            if ((iteration + salt) & 1) == 0
            else wifi_dsss_plcp_crc16(black_box(second))
        )
        if measure:
            elapsed += global_perf_counter_ns() - start
        full_checksum = _mix(full_checksum, value + iteration)
        fingerprint = _mix(fingerprint, value + iteration)
        keep(value)
    return _WorkloadMeasurement(elapsed, full_checksum, fingerprint)


@no_inline
def _preamble_workload(
    iterations: Int, salt: Int, measure: Bool
) -> _WorkloadMeasurement:
    var elapsed = UInt64(0)
    var full_checksum = UInt64(1469598103934665603)
    var fingerprint = UInt64(1469598103934665603)
    for iteration in range(iterations):
        var short = ((iteration + salt) & 1) != 0
        var start = UInt64(0)
        if measure:
            start = global_perf_counter_ns()
        var bits = wifi_dsss_plcp_preamble_bits(
            short_preamble=black_box(short)
        )
        if measure:
            elapsed += global_perf_counter_ns() - start
        full_checksum = _mix_bits(full_checksum, Span(bits))
        fingerprint = _mix(
            fingerprint,
            Int(_fingerprint_bits(Span(bits)) & UInt64(Int.MAX))
            + iteration,
        )
        keep(bits)
    return _WorkloadMeasurement(elapsed, full_checksum, fingerprint)


@no_inline
def _length_workload(
    iterations: Int,
    salt: Int,
    config: WifiDSSSPLCPConfig,
    measure: Bool,
) raises -> _WorkloadMeasurement:
    var elapsed = UInt64(0)
    var full_checksum = UInt64(1469598103934665603)
    var fingerprint = UInt64(1469598103934665603)
    for iteration in range(iterations):
        var length = 1 + ((iteration * 37 + salt) % 4095)
        var start = UInt64(0)
        if measure:
            start = global_perf_counter_ns()
        var geometry = wifi_dsss_plcp_length(
            black_box(length),
            black_box(config),
        )
        if measure:
            elapsed += global_perf_counter_ns() - start
        full_checksum = _mix(full_checksum, geometry.psdu_octets)
        full_checksum = _mix(full_checksum, geometry.length_us)
        full_checksum = _mix(
            full_checksum, 1 if geometry.length_extension else 0
        )
        fingerprint = _mix(
            fingerprint,
            geometry.psdu_octets * 257
            + geometry.length_us
            + (1 if geometry.length_extension else 0),
        )
        keep(geometry)
    return _WorkloadMeasurement(elapsed, full_checksum, fingerprint)


@no_inline
def _header_pack_workload(
    iterations: Int,
    salt: Int,
    config: WifiDSSSPLCPConfig,
    measure: Bool,
) raises -> _WorkloadMeasurement:
    var elapsed = UInt64(0)
    var full_checksum = UInt64(1469598103934665603)
    var fingerprint = UInt64(1469598103934665603)
    for iteration in range(iterations):
        var length = 1 + ((iteration * 53 + salt) % 4095)
        var start = UInt64(0)
        if measure:
            start = global_perf_counter_ns()
        var bits = wifi_dsss_plcp_header_pack(
            black_box(length),
            black_box(config),
        )
        if measure:
            elapsed += global_perf_counter_ns() - start
        full_checksum = _mix_bits(full_checksum, Span(bits))
        fingerprint = _mix(
            fingerprint,
            Int(_fingerprint_bits(Span(bits)) & UInt64(Int.MAX))
            + iteration,
        )
        keep(bits)
    return _WorkloadMeasurement(elapsed, full_checksum, fingerprint)


@no_inline
def _header_parse_workload(
    iterations: Int,
    salt: Int,
    long_header: Span[UInt8, ...],
    short_header: Span[UInt8, ...],
    measure: Bool,
) raises -> _WorkloadMeasurement:
    var elapsed = UInt64(0)
    var full_checksum = UInt64(1469598103934665603)
    var fingerprint = UInt64(1469598103934665603)
    for iteration in range(iterations):
        var is_short = ((iteration + salt) & 1) != 0
        if is_short:
            var start = UInt64(0)
            if measure:
                start = global_perf_counter_ns()
            var header = wifi_dsss_plcp_header_parse(
                black_box(short_header), short_preamble=True
            )
            if measure:
                elapsed += global_perf_counter_ns() - start
            full_checksum = _mix(full_checksum, header.signal)
            full_checksum = _mix(full_checksum, header.service)
            full_checksum = _mix(
                full_checksum, header.length.psdu_octets
            )
            full_checksum = _mix(full_checksum, header.length.length_us)
            full_checksum = _mix(full_checksum, header.crc)
            fingerprint = _mix(
                fingerprint,
                header.signal * 257 + header.crc + iteration,
            )
            keep(header)
        else:
            var start = UInt64(0)
            if measure:
                start = global_perf_counter_ns()
            var header = wifi_dsss_plcp_header_parse(
                black_box(long_header), short_preamble=False
            )
            if measure:
                elapsed += global_perf_counter_ns() - start
            full_checksum = _mix(full_checksum, header.signal)
            full_checksum = _mix(full_checksum, header.service)
            full_checksum = _mix(
                full_checksum, header.length.psdu_octets
            )
            full_checksum = _mix(full_checksum, header.length.length_us)
            full_checksum = _mix(full_checksum, header.crc)
            fingerprint = _mix(
                fingerprint,
                header.signal * 257 + header.crc + iteration,
            )
            keep(header)
    return _WorkloadMeasurement(elapsed, full_checksum, fingerprint)


@no_inline
def _tx_workload(
    iterations: Int,
    salt: Int,
    payload: Span[UInt8, ...],
    config: WifiDSSSPLCPConfig,
    measure: Bool,
) raises -> _WorkloadMeasurement:
    var elapsed = UInt64(0)
    var full_checksum = UInt64(1469598103934665603)
    var fingerprint = UInt64(1469598103934665603)
    for iteration in range(iterations):
        var start = UInt64(0)
        if measure:
            start = global_perf_counter_ns()
        var tx = wifi_dsss_ppdu_tx(
            black_box(payload),
            black_box(config),
            testcase_id="wifi-dsss-plcp-benchmark-tx",
        )
        if measure:
            elapsed += global_perf_counter_ns() - start
        full_checksum = _mix(full_checksum, Int(tx.fcs))
        full_checksum = _mix(full_checksum, tx.header.signal)
        full_checksum = _mix(full_checksum, tx.header.service)
        full_checksum = _mix(full_checksum, tx.header.length.length_us)
        full_checksum = _mix_bits(full_checksum, Span(tx.preamble_bits))
        full_checksum = _mix_bits(full_checksum, Span(tx.header_bits))
        full_checksum = _mix_bits(full_checksum, Span(tx.psdu_bits))
        full_checksum = _mix_bits(full_checksum, Span(tx.ppdu_bits))
        full_checksum = _mix_bits(full_checksum, Span(tx.scrambled_bits))
        full_checksum = _mix_chips(full_checksum, Span(tx.preamble_chips))
        full_checksum = _mix_chips(full_checksum, Span(tx.header_chips))
        full_checksum = _mix_chips(full_checksum, Span(tx.psdu_chips))
        full_checksum = _mix_chips(full_checksum, Span(tx.ppdu_chips))
        full_checksum = _mix(
            full_checksum, len(tx.metadata) + iteration + salt
        )
        fingerprint = _mix(
            fingerprint,
            Int(_fingerprint_chips(Span(tx.ppdu_chips)) & UInt64(Int.MAX))
            + Int(tx.fcs & UInt64(Int.MAX))
            + iteration,
        )
        keep(tx)
    return _WorkloadMeasurement(elapsed, full_checksum, fingerprint)


@no_inline
def _rx_workload(
    iterations: Int,
    salt: Int,
    chips: Span[Complex64, ...],
    short_preamble: Bool,
    measure: Bool,
) raises -> _WorkloadMeasurement:
    var elapsed = UInt64(0)
    var full_checksum = UInt64(1469598103934665603)
    var fingerprint = UInt64(1469598103934665603)
    for iteration in range(iterations):
        var start = UInt64(0)
        if measure:
            start = global_perf_counter_ns()
        var rx = wifi_dsss_ppdu_rx(
            black_box(chips),
            short_preamble=black_box(short_preamble),
            testcase_id="wifi-dsss-plcp-benchmark-rx",
        )
        if measure:
            elapsed += global_perf_counter_ns() - start
        full_checksum = _mix(full_checksum, rx.header.signal)
        full_checksum = _mix(full_checksum, rx.header.service)
        full_checksum = _mix(full_checksum, rx.header.length.length_us)
        full_checksum = _mix_bits(full_checksum, Span(rx.payload_bits))
        for index in range(len(rx.payload_octets)):
            full_checksum = _mix(
                full_checksum, Int(rx.payload_octets[index]) + index
            )
        full_checksum = _mix(full_checksum, Int(rx.recovered_fcs))
        full_checksum = _mix(full_checksum, Int(rx.computed_fcs))
        full_checksum = _mix(full_checksum, 1 if rx.fcs_ok else 0)
        full_checksum = _mix_bits(full_checksum, Span(rx.scrambled_bits))
        full_checksum = _mix_bits(full_checksum, Span(rx.descrambled_bits))
        full_checksum = _mix(
            full_checksum, len(rx.metadata) + iteration + salt
        )
        fingerprint = _mix(
            fingerprint,
            Int(_fingerprint_bits(Span(rx.payload_bits)) & UInt64(Int.MAX))
            + Int(rx.computed_fcs & UInt64(Int.MAX))
            + iteration,
        )
        keep(rx)
    return _WorkloadMeasurement(elapsed, full_checksum, fingerprint)


def main() raises:
    var bits_a = _pattern_bits(256, UInt64(0x123456789ABCDEF0))
    var bits_b = _pattern_bits(256, UInt64(0x0FEDCBA987654321))
    var scrambled_a = wifi_dsss_plcp_scramble(Span(bits_a), 0x6C)
    var scrambled_b = wifi_dsss_plcp_scramble(Span(bits_b), 0x1B)
    var crc_a = _pattern_bits(32, UInt64(0x1020304050607080))
    var crc_b = _pattern_bits(32, UInt64(0x8070605040302010))
    var long_config = WifiDSSSPLCPConfig(
        WIFI_DSSS_RATE_1_MBPS_KBPS, locked_clocks=True
    )
    var short_config = WifiDSSSPLCPConfig(
        WIFI_DSSS_RATE_11_MBPS_KBPS,
        short_preamble=True,
        locked_clocks=True,
    )
    var long_header = wifi_dsss_plcp_header_pack(103, long_config)
    var short_header = wifi_dsss_plcp_header_pack(107, short_config)
    var payload = _pattern_octets(32, UInt64(0xD1B54A32D192ED03))
    var long_tx = wifi_dsss_ppdu_tx(Span(payload), long_config)
    var short_tx = wifi_dsss_ppdu_tx(Span(payload), short_config)

    var full_output_checksum = UInt64(1469598103934665603)
    var fingerprint_checksum = UInt64(1469598103934665603)
    for _ in range(_WARMUPS):
        var salt = 324508639
        keep(_scramble_workload(
            _BIT_BATCH, salt, Span(bits_a), Span(bits_b), False
        ))
        keep(_descramble_workload(
            _BIT_BATCH,
            salt,
            Span(scrambled_a),
            Span(scrambled_b),
            False,
        ))
        keep(_crc_workload(
            _FAST_BATCH, salt, Span(crc_a), Span(crc_b), False
        ))
        keep(_preamble_workload(_FAST_BATCH, salt, False))
        keep(_length_workload(
            _FAST_BATCH, salt, short_config, False
        ))
        keep(_header_pack_workload(
            _FAST_BATCH, salt, short_config, False
        ))
        keep(_header_parse_workload(
            _FAST_BATCH,
            salt,
            Span(long_header),
            Span(short_header),
            False,
        ))
        keep(_tx_workload(
            _TX_BATCH, salt, Span(payload), short_config, False
        ))
        keep(_rx_workload(
            _RX_BATCH, salt, Span(short_tx.ppdu_chips), True, False
        ))

    var scramble_samples = List[UInt64](capacity=_SAMPLES)
    var descramble_samples = List[UInt64](capacity=_SAMPLES)
    var crc_samples = List[UInt64](capacity=_SAMPLES)
    var preamble_samples = List[UInt64](capacity=_SAMPLES)
    var length_samples = List[UInt64](capacity=_SAMPLES)
    var pack_samples = List[UInt64](capacity=_SAMPLES)
    var parse_samples = List[UInt64](capacity=_SAMPLES)
    var tx_samples = List[UInt64](capacity=_SAMPLES)
    var rx_samples = List[UInt64](capacity=_SAMPLES)
    for sample in range(_SAMPLES):
        var salt = 324508639 + sample
        _record_measurement(
            _scramble_workload(
                _BIT_BATCH, salt, Span(bits_a), Span(bits_b), True
            ),
            scramble_samples,
            full_output_checksum,
            fingerprint_checksum,
        )
        _record_measurement(
            _descramble_workload(
                _BIT_BATCH,
                salt,
                Span(scrambled_a),
                Span(scrambled_b),
                True,
            ),
            descramble_samples,
            full_output_checksum,
            fingerprint_checksum,
        )
        _record_measurement(
            _crc_workload(
                _FAST_BATCH, salt, Span(crc_a), Span(crc_b), True
            ),
            crc_samples,
            full_output_checksum,
            fingerprint_checksum,
        )
        _record_measurement(
            _preamble_workload(_FAST_BATCH, salt, True),
            preamble_samples,
            full_output_checksum,
            fingerprint_checksum,
        )
        _record_measurement(
            _length_workload(_FAST_BATCH, salt, short_config, True),
            length_samples,
            full_output_checksum,
            fingerprint_checksum,
        )
        _record_measurement(
            _header_pack_workload(_FAST_BATCH, salt, short_config, True),
            pack_samples,
            full_output_checksum,
            fingerprint_checksum,
        )
        _record_measurement(
            _header_parse_workload(
                _FAST_BATCH,
                salt,
                Span(long_header),
                Span(short_header),
                True,
            ),
            parse_samples,
            full_output_checksum,
            fingerprint_checksum,
        )
        _record_measurement(
            _tx_workload(
                _TX_BATCH, salt, Span(payload), short_config, True
            ),
            tx_samples,
            full_output_checksum,
            fingerprint_checksum,
        )
        _record_measurement(
            _rx_workload(
                _RX_BATCH,
                salt,
                Span(short_tx.ppdu_chips),
                True,
                True,
            ),
            rx_samples,
            full_output_checksum,
            fingerprint_checksum,
        )

    # Consume the alternate complete PPDU too; it is intentionally outside
    # the timed samples and prevents benchmark setup from becoming dead data.
    full_output_checksum = _mix_chips(
        full_output_checksum, Span(long_tx.ppdu_chips)
    )
    print_benchmark_metadata()
    print("wifi_dsss_plcp_backend: scalar-cpu-reference")
    print("wifi_dsss_plcp_scope: aligned-clause-15-16-long-short-cck-ppdu")
    print("wifi_dsss_plcp_input_variation: fixed-salted-valid-inputs")
    print("wifi_dsss_plcp_timed_scope: target-api-only")
    print("wifi_dsss_plcp_post_timer_scope: keep-plus-full-output-checksum-plus-o1-fingerprint")
    report_timing_samples(
        "wifi_dsss_plcp_scramble",
        scramble_samples,
        _WARMUPS,
        _BIT_BATCH * len(bits_a),
        "scrambled_bit",
    )
    report_timing_samples(
        "wifi_dsss_plcp_descramble",
        descramble_samples,
        _WARMUPS,
        _BIT_BATCH * len(bits_a),
        "descrambled_bit",
    )
    report_timing_samples(
        "wifi_dsss_plcp_crc16",
        crc_samples,
        _WARMUPS,
        _FAST_BATCH,
        "header_crc",
    )
    report_timing_samples(
        "wifi_dsss_plcp_preamble_bits",
        preamble_samples,
        _WARMUPS,
        _FAST_BATCH,
        "preamble",
    )
    report_timing_samples(
        "wifi_dsss_plcp_length",
        length_samples,
        _WARMUPS,
        _FAST_BATCH,
        "geometry",
    )
    report_timing_samples(
        "wifi_dsss_plcp_header_pack",
        pack_samples,
        _WARMUPS,
        _FAST_BATCH,
        "header",
    )
    report_timing_samples(
        "wifi_dsss_plcp_header_parse",
        parse_samples,
        _WARMUPS,
        _FAST_BATCH,
        "header",
    )
    report_timing_samples(
        "wifi_dsss_ppdu_tx",
        tx_samples,
        _WARMUPS,
        _TX_BATCH,
        "ppdu",
    )
    report_timing_samples(
        "wifi_dsss_ppdu_rx",
        rx_samples,
        _WARMUPS,
        _RX_BATCH,
        "ppdu",
    )
    keep(full_output_checksum)
    keep(fingerprint_checksum)
    print("wifi_dsss_plcp_full_output_checksum:", full_output_checksum)
    print("wifi_dsss_plcp_fingerprint_checksum:", fingerprint_checksum)
