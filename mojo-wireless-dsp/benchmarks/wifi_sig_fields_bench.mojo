"""Attributable CPU timings for bounded HT/VHT SIGNAL-field algorithms.

Every public API is measured as a separate batched family.  Each family has
three untimed warmups and nine independent odd samples; a fixed salt varies
valid scalar inputs or selects among prebuilt valid parser inputs.  Only the
target API call is timed.  Complete results are kept and fully consumed after
the timer, with a separate O(1) endpoint fingerprint checksum.
"""

from std.benchmark import black_box, keep
from std.collections import Span
from std.time import global_perf_counter_ns
from wireless_dsp.benchmarking import (
    print_benchmark_metadata,
    report_timing_samples,
)
from wireless_dsp.wireless.wifi.sig_fields import (
    WIFI_SIG_CODING_BCC,
    WIFI_SIG_CODING_LDPC,
    WifiHTSigFields,
    WifiVHTSigASUFields,
    WifiVHTSigBSUFields,
    wifi_sig_crc8,
    wifi_ht_sig_pack,
    wifi_ht_sig_parse,
    wifi_ht_sig_geometry,
    wifi_vht_sig_a_su_pack,
    wifi_vht_sig_a_su_parse,
    wifi_vht_sig_a_su_geometry,
    wifi_vht_sig_b_su_geometry,
    wifi_vht_sig_b_su_pack,
    wifi_vht_sig_b_su_parse,
    wifi_vht_sig_b_su_bcc_input,
)


comptime _WARMUPS = 3
comptime _SAMPLES = 9
comptime _BATCH = 2048


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


def _fingerprint_bits(bits: Span[UInt8, ...]) -> UInt64:
    return _mix(
        _mix(UInt64(1469598103934665603), len(bits)),
        Int(bits[0]) * 17 + Int(bits[len(bits) - 1]) * 257,
    )


def _pattern34(seed: UInt64) -> List[UInt8]:
    var state = seed
    var result = List[UInt8](capacity=34)
    for _ in range(34):
        state = (
            state * UInt64(6364136223846793005)
            + UInt64(1442695040888963407)
        )
        result.append(UInt8((state >> 63) & UInt64(1)))
    return result^


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
        var crc: Int
        var start = UInt64(0)
        if measure:
            start = global_perf_counter_ns()
        if ((iteration + salt) & 1) == 0:
            crc = wifi_sig_crc8(black_box(first))
        else:
            crc = wifi_sig_crc8(black_box(second))
        if measure:
            elapsed += global_perf_counter_ns() - start
        full_checksum = _mix(full_checksum, crc + iteration)
        fingerprint = _mix(fingerprint, crc + iteration)
        keep(crc)
    return _WorkloadMeasurement(elapsed, full_checksum, fingerprint)


@no_inline
def _ht_pack_workload(
    iterations: Int, salt: Int, measure: Bool
) raises -> _WorkloadMeasurement:
    var elapsed = UInt64(0)
    var full_checksum = UInt64(1469598103934665603)
    var fingerprint = UInt64(1469598103934665603)
    for iteration in range(iterations):
        var selector = iteration + salt
        var mcs = selector & 31
        var bandwidth = 40 if ((selector >> 5) & 1) != 0 else 20
        var stbc = 1 if mcs < 24 and ((selector >> 6) & 1) != 0 else 0
        var start = UInt64(0)
        if measure:
            start = global_perf_counter_ns()
        var bits = wifi_ht_sig_pack(
            black_box(mcs),
            black_box(bandwidth),
            black_box(1 + ((selector * 37) % 65535)),
            smoothing=black_box((selector & 1) == 0),
            not_sounding=black_box(((selector >> 1) & 1) == 0),
            aggregation=black_box(((selector >> 2) & 1) != 0),
            stbc_streams=black_box(stbc),
            fec_coding=black_box((selector >> 3) & 1),
            short_gi=black_box(((selector >> 4) & 1) != 0),
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
def _ht_parse_workload(
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
        var fields: WifiHTSigFields
        var start = UInt64(0)
        if measure:
            start = global_perf_counter_ns()
        if ((iteration + salt) & 1) == 0:
            fields = wifi_ht_sig_parse(black_box(first))
        else:
            fields = wifi_ht_sig_parse(black_box(second))
        if measure:
            elapsed += global_perf_counter_ns() - start
        full_checksum = _mix(full_checksum, fields.mcs_index)
        full_checksum = _mix(full_checksum, fields.bandwidth_mhz)
        full_checksum = _mix(full_checksum, fields.ht_length_octets)
        full_checksum = _mix(
            full_checksum, 1 if fields.smoothing else 0
        )
        full_checksum = _mix(
            full_checksum, 1 if fields.not_sounding else 0
        )
        full_checksum = _mix(
            full_checksum, 1 if fields.aggregation else 0
        )
        full_checksum = _mix(full_checksum, fields.stbc_streams)
        full_checksum = _mix(full_checksum, fields.fec_coding)
        full_checksum = _mix(
            full_checksum, 1 if fields.short_gi else 0
        )
        full_checksum = _mix(
            full_checksum, fields.extension_spatial_streams
        )
        full_checksum = _mix(full_checksum, fields.crc + iteration)
        fingerprint = _mix(
            fingerprint,
            fields.mcs_index * 257 + fields.crc + iteration,
        )
        keep(fields)
    return _WorkloadMeasurement(elapsed, full_checksum, fingerprint)


@no_inline
def _ht_geometry_workload(
    iterations: Int, salt: Int, measure: Bool
) raises -> _WorkloadMeasurement:
    var elapsed = UInt64(0)
    var full_checksum = UInt64(1469598103934665603)
    var fingerprint = UInt64(1469598103934665603)
    for iteration in range(iterations):
        var selector = iteration + salt
        var mcs = selector & 31
        var stbc = 1 if mcs < 24 and ((selector >> 7) & 1) != 0 else 0
        var bandwidth = 40 if ((selector >> 5) & 1) != 0 else 20
        var start = UInt64(0)
        if measure:
            start = global_perf_counter_ns()
        var geometry = wifi_ht_sig_geometry(
            black_box(mcs),
            black_box(bandwidth),
            stbc_streams=black_box(stbc),
        )
        if measure:
            elapsed += global_perf_counter_ns() - start
        full_checksum = _mix(full_checksum, geometry.signal_bits)
        full_checksum = _mix(full_checksum, geometry.crc_covered_bits)
        full_checksum = _mix(full_checksum, geometry.tail_bits)
        full_checksum = _mix(full_checksum, geometry.signal_ofdm_symbols)
        full_checksum = _mix(full_checksum, geometry.signal_duration_ns)
        full_checksum = _mix(full_checksum, geometry.data_spatial_streams)
        full_checksum = _mix(full_checksum, geometry.space_time_streams)
        full_checksum = _mix(full_checksum, geometry.data_ltf_symbols)
        full_checksum = _mix(
            full_checksum, geometry.extension_ltf_symbols
        )
        full_checksum = _mix(
            full_checksum, geometry.total_ltf_symbols + iteration
        )
        fingerprint = _mix(
            fingerprint,
            geometry.signal_bits * 257
            + geometry.total_ltf_symbols
            + iteration,
        )
        keep(geometry)
    return _WorkloadMeasurement(elapsed, full_checksum, fingerprint)


@no_inline
def _vht_a_pack_workload(
    iterations: Int, salt: Int, measure: Bool
) raises -> _WorkloadMeasurement:
    var elapsed = UInt64(0)
    var full_checksum = UInt64(1469598103934665603)
    var fingerprint = UInt64(1469598103934665603)
    for iteration in range(iterations):
        var selector = iteration + salt
        var nsts = 1 + (selector & 7)
        var coding = (selector >> 3) & 1
        var short_gi = ((selector >> 4) & 1) != 0
        var bandwidth = 20 << ((selector >> 5) & 3)
        var mcs = (selector >> 2) % 10
        if mcs == 9 and bandwidth == 20:
            bandwidth = 40
        var start = UInt64(0)
        if measure:
            start = global_perf_counter_ns()
        var bits = wifi_vht_sig_a_su_pack(
            black_box(bandwidth),
            black_box(nsts),
            black_box((selector * 13) & 0x1FF),
            black_box(mcs),
            group_id=black_box(63 if ((selector >> 7) & 1) == 0 else 0),
            txop_ps_not_allowed=black_box(((selector >> 8) & 1) != 0),
            short_gi=black_box(short_gi),
            short_gi_nsym_disambiguation=black_box(
                short_gi and ((selector >> 9) & 1) != 0
            ),
            coding=black_box(coding),
            ldpc_extra_ofdm_symbol=black_box(
                coding == WIFI_SIG_CODING_LDPC
                and ((selector >> 10) & 1) != 0
            ),
            beamformed=black_box(((selector >> 11) & 1) != 0),
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
def _vht_a_parse_workload(
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
        var fields: WifiVHTSigASUFields
        var start = UInt64(0)
        if measure:
            start = global_perf_counter_ns()
        if ((iteration + salt) & 1) == 0:
            fields = wifi_vht_sig_a_su_parse(black_box(first))
        else:
            fields = wifi_vht_sig_a_su_parse(black_box(second))
        if measure:
            elapsed += global_perf_counter_ns() - start
        full_checksum = _mix(full_checksum, fields.bandwidth_mhz)
        full_checksum = _mix(full_checksum, 1 if fields.stbc else 0)
        full_checksum = _mix(full_checksum, fields.group_id)
        full_checksum = _mix(full_checksum, fields.space_time_streams)
        full_checksum = _mix(full_checksum, fields.partial_aid)
        full_checksum = _mix(
            full_checksum, 1 if fields.txop_ps_not_allowed else 0
        )
        full_checksum = _mix(
            full_checksum, 1 if fields.short_gi else 0
        )
        full_checksum = _mix(
            full_checksum,
            1 if fields.short_gi_nsym_disambiguation else 0,
        )
        full_checksum = _mix(full_checksum, fields.coding)
        full_checksum = _mix(
            full_checksum, 1 if fields.ldpc_extra_ofdm_symbol else 0
        )
        full_checksum = _mix(full_checksum, fields.mcs_index)
        full_checksum = _mix(
            full_checksum, 1 if fields.beamformed else 0
        )
        full_checksum = _mix(full_checksum, fields.crc + iteration)
        fingerprint = _mix(
            fingerprint,
            fields.bandwidth_mhz * 257 + fields.crc + iteration,
        )
        keep(fields)
    return _WorkloadMeasurement(elapsed, full_checksum, fingerprint)


@no_inline
def _vht_a_geometry_workload(
    iterations: Int, salt: Int, measure: Bool
) raises -> _WorkloadMeasurement:
    var elapsed = UInt64(0)
    var full_checksum = UInt64(1469598103934665603)
    var fingerprint = UInt64(1469598103934665603)
    for iteration in range(iterations):
        var nsts = 1 + ((iteration + salt) & 7)
        var start = UInt64(0)
        if measure:
            start = global_perf_counter_ns()
        var geometry = wifi_vht_sig_a_su_geometry(black_box(nsts))
        if measure:
            elapsed += global_perf_counter_ns() - start
        full_checksum = _mix(full_checksum, geometry.signal_bits)
        full_checksum = _mix(full_checksum, geometry.crc_covered_bits)
        full_checksum = _mix(full_checksum, geometry.tail_bits)
        full_checksum = _mix(full_checksum, geometry.signal_ofdm_symbols)
        full_checksum = _mix(full_checksum, geometry.signal_duration_ns)
        full_checksum = _mix(full_checksum, geometry.data_spatial_streams)
        full_checksum = _mix(full_checksum, geometry.space_time_streams)
        full_checksum = _mix(
            full_checksum, geometry.vht_ltf_symbols + iteration
        )
        fingerprint = _mix(
            fingerprint,
            geometry.signal_bits * 257
            + geometry.vht_ltf_symbols
            + iteration,
        )
        keep(geometry)
    return _WorkloadMeasurement(elapsed, full_checksum, fingerprint)


def _bandwidth(selector: Int) -> Int:
    return 20 << (selector & 3)


@no_inline
def _vht_b_geometry_workload(
    iterations: Int, salt: Int, measure: Bool
) raises -> _WorkloadMeasurement:
    var elapsed = UInt64(0)
    var full_checksum = UInt64(1469598103934665603)
    var fingerprint = UInt64(1469598103934665603)
    for iteration in range(iterations):
        var bandwidth = _bandwidth(iteration + salt)
        var start = UInt64(0)
        if measure:
            start = global_perf_counter_ns()
        var geometry = wifi_vht_sig_b_su_geometry(
            black_box(bandwidth)
        )
        if measure:
            elapsed += global_perf_counter_ns() - start
        full_checksum = _mix(full_checksum, geometry.bandwidth_mhz)
        full_checksum = _mix(full_checksum, geometry.length_bits)
        full_checksum = _mix(full_checksum, geometry.fixed_bits)
        full_checksum = _mix(full_checksum, geometry.tail_bits)
        full_checksum = _mix(full_checksum, geometry.base_field_bits)
        full_checksum = _mix(
            full_checksum, geometry.base_field_repetitions
        )
        full_checksum = _mix(full_checksum, geometry.zero_pad_bits)
        full_checksum = _mix(full_checksum, geometry.bcc_input_bits)
        full_checksum = _mix(full_checksum, geometry.coded_bpsk_bits)
        full_checksum = _mix(full_checksum, geometry.content_copies)
        full_checksum = _mix(full_checksum, geometry.signal_ofdm_symbols)
        full_checksum = _mix(
            full_checksum, geometry.signal_duration_ns + iteration
        )
        fingerprint = _mix(
            fingerprint,
            geometry.bandwidth_mhz * 257
            + geometry.bcc_input_bits
            + iteration,
        )
        keep(geometry)
    return _WorkloadMeasurement(elapsed, full_checksum, fingerprint)


@no_inline
def _vht_b_pack_workload(
    iterations: Int, salt: Int, measure: Bool
) raises -> _WorkloadMeasurement:
    var elapsed = UInt64(0)
    var full_checksum = UInt64(1469598103934665603)
    var fingerprint = UInt64(1469598103934665603)
    for iteration in range(iterations):
        var selector = iteration + salt
        var length = 1 + ((selector * 29) & 0x3FFFF)
        var bandwidth = _bandwidth(selector)
        var start = UInt64(0)
        if measure:
            start = global_perf_counter_ns()
        var bits = wifi_vht_sig_b_su_pack(
            black_box(length),
            black_box(bandwidth),
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
def _vht_b_parse_workload(
    iterations: Int,
    salt: Int,
    bits20: Span[UInt8, ...],
    bits40: Span[UInt8, ...],
    bits80: Span[UInt8, ...],
    bits160: Span[UInt8, ...],
    measure: Bool,
) raises -> _WorkloadMeasurement:
    var elapsed = UInt64(0)
    var full_checksum = UInt64(1469598103934665603)
    var fingerprint = UInt64(1469598103934665603)
    for iteration in range(iterations):
        var selector = (iteration + salt) & 3
        var fields: WifiVHTSigBSUFields
        var start = UInt64(0)
        if measure:
            start = global_perf_counter_ns()
        if selector == 0:
            fields = wifi_vht_sig_b_su_parse(black_box(bits20), 20)
        elif selector == 1:
            fields = wifi_vht_sig_b_su_parse(black_box(bits40), 40)
        elif selector == 2:
            fields = wifi_vht_sig_b_su_parse(black_box(bits80), 80)
        else:
            fields = wifi_vht_sig_b_su_parse(black_box(bits160), 160)
        if measure:
            elapsed += global_perf_counter_ns() - start
        full_checksum = _mix(full_checksum, fields.bandwidth_mhz)
        full_checksum = _mix(
            full_checksum, fields.length_units_4_octets
        )
        full_checksum = _mix(
            full_checksum, fields.rounded_apep_length_octets
        )
        full_checksum = _mix(
            full_checksum, fields.base_field_bits + iteration
        )
        fingerprint = _mix(
            fingerprint,
            fields.bandwidth_mhz * 257
            + fields.base_field_bits
            + iteration,
        )
        keep(fields)
    return _WorkloadMeasurement(elapsed, full_checksum, fingerprint)


@no_inline
def _vht_b_bcc_input_workload(
    iterations: Int,
    salt: Int,
    bits20: Span[UInt8, ...],
    bits40: Span[UInt8, ...],
    bits80: Span[UInt8, ...],
    bits160: Span[UInt8, ...],
    measure: Bool,
) raises -> _WorkloadMeasurement:
    var elapsed = UInt64(0)
    var full_checksum = UInt64(1469598103934665603)
    var fingerprint = UInt64(1469598103934665603)
    for iteration in range(iterations):
        var selector = (iteration + salt) & 3
        var expanded: List[UInt8]
        var start = UInt64(0)
        if measure:
            start = global_perf_counter_ns()
        if selector == 0:
            expanded = wifi_vht_sig_b_su_bcc_input(
                black_box(bits20), 20
            )
        elif selector == 1:
            expanded = wifi_vht_sig_b_su_bcc_input(
                black_box(bits40), 40
            )
        elif selector == 2:
            expanded = wifi_vht_sig_b_su_bcc_input(
                black_box(bits80), 80
            )
        else:
            expanded = wifi_vht_sig_b_su_bcc_input(
                black_box(bits160), 160
            )
        if measure:
            elapsed += global_perf_counter_ns() - start
        full_checksum = _mix_bits(full_checksum, Span(expanded))
        full_checksum = _mix(full_checksum, iteration)
        fingerprint = _mix(
            fingerprint,
            Int(_fingerprint_bits(Span(expanded)) & UInt64(Int.MAX))
            + iteration,
        )
        keep(expanded)
    return _WorkloadMeasurement(elapsed, full_checksum, fingerprint)


def main() raises:
    var crc_first = _pattern34(UInt64(0x19A21))
    var crc_second = _pattern34(UInt64(0x21AC))
    var ht_first = wifi_ht_sig_pack(6, 20, 1000)
    var ht_second = wifi_ht_sig_pack(
        18,
        40,
        4095,
        smoothing=False,
        not_sounding=False,
        aggregation=True,
        stbc_streams=0,
        fec_coding=WIFI_SIG_CODING_LDPC,
        short_gi=True,
        extension_spatial_streams=1,
    )
    var vht_a_first = wifi_vht_sig_a_su_pack(80, 1, 0x155, 8)
    var vht_a_second = wifi_vht_sig_a_su_pack(
        160,
        4,
        0x12A,
        9,
        stbc=True,
        txop_ps_not_allowed=False,
        short_gi=True,
        short_gi_nsym_disambiguation=True,
        coding=WIFI_SIG_CODING_LDPC,
        ldpc_extra_ofdm_symbol=True,
        beamformed=True,
    )
    var vht_b_20 = wifi_vht_sig_b_su_pack(1500, 20)
    var vht_b_40 = wifi_vht_sig_b_su_pack(4095, 40)
    var vht_b_80 = wifi_vht_sig_b_su_pack(65535, 80)
    var vht_b_160 = wifi_vht_sig_b_su_pack(1_000_000, 160)

    for _ in range(_WARMUPS):
        var salt = 324508639
        keep(_crc_workload(
            _BATCH, salt, Span(crc_first), Span(crc_second), False
        ))
        keep(_ht_pack_workload(_BATCH, salt, False))
        keep(_ht_parse_workload(
            _BATCH, salt, Span(ht_first), Span(ht_second), False
        ))
        keep(_ht_geometry_workload(_BATCH, salt, False))
        keep(_vht_a_pack_workload(_BATCH, salt, False))
        keep(_vht_a_parse_workload(
            _BATCH,
            salt,
            Span(vht_a_first),
            Span(vht_a_second),
            False,
        ))
        keep(_vht_a_geometry_workload(_BATCH, salt, False))
        keep(_vht_b_geometry_workload(_BATCH, salt, False))
        keep(_vht_b_pack_workload(_BATCH, salt, False))
        keep(_vht_b_parse_workload(
            _BATCH,
            salt,
            Span(vht_b_20),
            Span(vht_b_40),
            Span(vht_b_80),
            Span(vht_b_160),
            False,
        ))
        keep(_vht_b_bcc_input_workload(
            _BATCH,
            salt,
            Span(vht_b_20),
            Span(vht_b_40),
            Span(vht_b_80),
            Span(vht_b_160),
            False,
        ))

    var crc_samples = List[UInt64](capacity=_SAMPLES)
    var ht_pack_samples = List[UInt64](capacity=_SAMPLES)
    var ht_parse_samples = List[UInt64](capacity=_SAMPLES)
    var ht_geometry_samples = List[UInt64](capacity=_SAMPLES)
    var vht_a_pack_samples = List[UInt64](capacity=_SAMPLES)
    var vht_a_parse_samples = List[UInt64](capacity=_SAMPLES)
    var vht_a_geometry_samples = List[UInt64](capacity=_SAMPLES)
    var vht_b_geometry_samples = List[UInt64](capacity=_SAMPLES)
    var vht_b_pack_samples = List[UInt64](capacity=_SAMPLES)
    var vht_b_parse_samples = List[UInt64](capacity=_SAMPLES)
    var vht_b_bcc_input_samples = List[UInt64](capacity=_SAMPLES)
    var full_output_checksum = UInt64(1469598103934665603)
    var fingerprint_checksum = UInt64(1469598103934665603)

    for _ in range(_SAMPLES):
        var salt = 324508639
        _record_measurement(
            _crc_workload(
                _BATCH, salt, Span(crc_first), Span(crc_second), True
            ),
            crc_samples,
            full_output_checksum,
            fingerprint_checksum,
        )
        _record_measurement(
            _ht_pack_workload(_BATCH, salt, True),
            ht_pack_samples,
            full_output_checksum,
            fingerprint_checksum,
        )
        _record_measurement(
            _ht_parse_workload(
                _BATCH, salt, Span(ht_first), Span(ht_second), True
            ),
            ht_parse_samples,
            full_output_checksum,
            fingerprint_checksum,
        )
        _record_measurement(
            _ht_geometry_workload(_BATCH, salt, True),
            ht_geometry_samples,
            full_output_checksum,
            fingerprint_checksum,
        )
        _record_measurement(
            _vht_a_pack_workload(_BATCH, salt, True),
            vht_a_pack_samples,
            full_output_checksum,
            fingerprint_checksum,
        )
        _record_measurement(
            _vht_a_parse_workload(
                _BATCH,
                salt,
                Span(vht_a_first),
                Span(vht_a_second),
                True,
            ),
            vht_a_parse_samples,
            full_output_checksum,
            fingerprint_checksum,
        )
        _record_measurement(
            _vht_a_geometry_workload(_BATCH, salt, True),
            vht_a_geometry_samples,
            full_output_checksum,
            fingerprint_checksum,
        )
        _record_measurement(
            _vht_b_geometry_workload(_BATCH, salt, True),
            vht_b_geometry_samples,
            full_output_checksum,
            fingerprint_checksum,
        )
        _record_measurement(
            _vht_b_pack_workload(_BATCH, salt, True),
            vht_b_pack_samples,
            full_output_checksum,
            fingerprint_checksum,
        )
        _record_measurement(
            _vht_b_parse_workload(
                _BATCH,
                salt,
                Span(vht_b_20),
                Span(vht_b_40),
                Span(vht_b_80),
                Span(vht_b_160),
                True,
            ),
            vht_b_parse_samples,
            full_output_checksum,
            fingerprint_checksum,
        )
        _record_measurement(
            _vht_b_bcc_input_workload(
                _BATCH,
                salt,
                Span(vht_b_20),
                Span(vht_b_40),
                Span(vht_b_80),
                Span(vht_b_160),
                True,
            ),
            vht_b_bcc_input_samples,
            full_output_checksum,
            fingerprint_checksum,
        )

    print_benchmark_metadata()
    print("wifi_sig_fields_backend: scalar-cpu-reference")
    print("wifi_sig_fields_scope: pre-fec-information-fields-only")
    print("wifi_sig_fields_input_variation: fixed-salted")
    print("wifi_sig_fields_timed_scope: target-api-only")
    print("wifi_sig_fields_post_timer_scope: keep-plus-full-output-checksum-plus-o1-fingerprint")
    report_timing_samples(
        "wifi_sig_crc8", crc_samples, _WARMUPS, _BATCH, "34_bit_field"
    )
    report_timing_samples(
        "wifi_ht_sig_pack", ht_pack_samples, _WARMUPS, _BATCH, "signal_field"
    )
    report_timing_samples(
        "wifi_ht_sig_parse", ht_parse_samples, _WARMUPS, _BATCH, "signal_field"
    )
    report_timing_samples(
        "wifi_ht_sig_geometry",
        ht_geometry_samples,
        _WARMUPS,
        _BATCH,
        "geometry_query",
    )
    report_timing_samples(
        "wifi_vht_sig_a_su_pack",
        vht_a_pack_samples,
        _WARMUPS,
        _BATCH,
        "signal_field",
    )
    report_timing_samples(
        "wifi_vht_sig_a_su_parse",
        vht_a_parse_samples,
        _WARMUPS,
        _BATCH,
        "signal_field",
    )
    report_timing_samples(
        "wifi_vht_sig_a_su_geometry",
        vht_a_geometry_samples,
        _WARMUPS,
        _BATCH,
        "geometry_query",
    )
    report_timing_samples(
        "wifi_vht_sig_b_su_geometry",
        vht_b_geometry_samples,
        _WARMUPS,
        _BATCH,
        "geometry_query",
    )
    report_timing_samples(
        "wifi_vht_sig_b_su_pack",
        vht_b_pack_samples,
        _WARMUPS,
        _BATCH,
        "signal_field",
    )
    report_timing_samples(
        "wifi_vht_sig_b_su_parse",
        vht_b_parse_samples,
        _WARMUPS,
        _BATCH,
        "signal_field",
    )
    report_timing_samples(
        "wifi_vht_sig_b_su_bcc_input",
        vht_b_bcc_input_samples,
        _WARMUPS,
        _BATCH,
        "bcc_input_field",
    )
    keep(full_output_checksum)
    keep(fingerprint_checksum)
    print("wifi_sig_fields_full_output_checksum:", full_output_checksum)
    print("wifi_sig_fields_fingerprint_checksum:", fingerprint_checksum)
