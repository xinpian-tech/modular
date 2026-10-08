"""Attributable CPU timings for bounded HE/EHT SIGNAL-field APIs.

Each public algorithm is measured as an independent batched family with three
untimed warmups and nine odd samples.  A fixed salt varies valid inputs or
selects prebuilt parser inputs.  Only the target API call is timed.  Complete
results are kept and fully consumed after the timer, with a separate O(1)
endpoint fingerprint checksum.
"""

from std.benchmark import black_box, keep
from std.collections import Span
from std.time import global_perf_counter_ns
from wireless_dsp.benchmarking import (
    print_benchmark_metadata,
    report_timing_samples,
)
from wireless_dsp.wireless.wifi.he_eht_sig_fields import (
    WIFI_HE_EHT_SIG_CODING_BCC,
    WIFI_HE_EHT_SIG_CODING_LDPC,
    WIFI_EHT_SIG_BLOCK_COMMON,
    WIFI_EHT_SIG_BLOCK_USER,
    WifiHeSigASUConfig,
    WifiHeSigASUFields,
    WifiEhtUSigSU20Config,
    WifiEhtUSigSU20Fields,
    WifiEhtSigBlockProfile,
    wifi_he_eht_sig_crc4,
    wifi_he_sig_a_su_pack,
    wifi_he_sig_a_su_parse,
    wifi_he_sig_a_su_geometry,
    wifi_eht_u_sig_su_20_pack,
    wifi_eht_u_sig_su_20_parse,
    wifi_eht_u_sig_su_20_geometry,
    wifi_eht_sig_block_pack,
    wifi_eht_sig_block_parse,
    wifi_eht_sig_block_geometry,
)


comptime _WARMUPS = 3
comptime _SAMPLES = 9
comptime _BATCH = 1024


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


def _pattern42(seed: UInt64) -> List[UInt8]:
    var state = seed
    var result = List[UInt8](capacity=42)
    for _ in range(42):
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
            crc = wifi_he_eht_sig_crc4(black_box(first))
        else:
            crc = wifi_he_eht_sig_crc4(black_box(second))
        if measure:
            elapsed += global_perf_counter_ns() - start
        full_checksum = _mix(full_checksum, crc + iteration)
        fingerprint = _mix(fingerprint, crc + iteration)
        keep(crc)
    return _WorkloadMeasurement(elapsed, full_checksum, fingerprint)


def _bandwidth(selector: Int) -> Int:
    return 20 << (selector & 3)


@no_inline
def _he_pack_workload(
    iterations: Int, salt: Int, measure: Bool
) raises -> _WorkloadMeasurement:
    var elapsed = UInt64(0)
    var full_checksum = UInt64(1469598103934665603)
    var fingerprint = UInt64(1469598103934665603)
    for iteration in range(iterations):
        var selector = iteration + salt
        var extended = (selector & 15) == 0
        var coding = (selector >> 4) & 1
        var config = WifiHeSigASUConfig(
            selector % (3 if extended else 12),
            extended_range=black_box(extended),
            beam_change=black_box(((selector >> 1) & 1) != 0),
            uplink=black_box(((selector >> 2) & 1) != 0),
            bss_color=black_box((selector * 13) & 63),
            spatial_reuse=black_box((selector >> 3) & 15),
            bandwidth_mhz=black_box(20 if extended else _bandwidth(selector)),
            gi_ltf_code=black_box((selector >> 5) & 3),
            space_time_streams=black_box(
                1 if extended else 1 + ((selector >> 7) & 7)
            ),
            txop_code=black_box((selector * 17) & 127),
            coding=black_box(coding),
            ldpc_extra_symbol=black_box(
                coding == WIFI_HE_EHT_SIG_CODING_LDPC
                and ((selector >> 10) & 1) != 0
            ),
            stbc=black_box(((selector >> 11) & 1) != 0),
            beamformed=black_box(((selector >> 12) & 1) != 0),
            pre_fec_padding_factor=black_box((selector >> 13) & 3),
            pe_disambiguity=black_box(((selector >> 15) & 1) != 0),
        )
        var start = UInt64(0)
        if measure:
            start = global_perf_counter_ns()
        var bits = wifi_he_sig_a_su_pack(config)
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


def _mix_he_fields(checksum: UInt64, fields: WifiHeSigASUFields) -> UInt64:
    var result = checksum
    result = _mix(result, 1 if fields.extended_range else 0)
    result = _mix(result, 1 if fields.beam_change else 0)
    result = _mix(result, 1 if fields.uplink else 0)
    result = _mix(result, fields.mcs_index)
    result = _mix(result, 1 if fields.dcm else 0)
    result = _mix(result, fields.bss_color)
    result = _mix(result, fields.spatial_reuse)
    result = _mix(result, fields.bandwidth_mhz)
    result = _mix(result, fields.gi_ltf_code)
    result = _mix(result, fields.space_time_streams)
    result = _mix(result, fields.txop_code)
    result = _mix(result, fields.coding)
    result = _mix(result, 1 if fields.ldpc_extra_symbol else 0)
    result = _mix(result, 1 if fields.stbc else 0)
    result = _mix(result, 1 if fields.beamformed else 0)
    result = _mix(result, fields.pre_fec_padding_factor)
    result = _mix(result, 1 if fields.pe_disambiguity else 0)
    return _mix(result, fields.crc)


@no_inline
def _he_parse_workload(
    iterations: Int,
    salt: Int,
    su_bits: Span[UInt8, ...],
    er_bits: Span[UInt8, ...],
    measure: Bool,
) raises -> _WorkloadMeasurement:
    var elapsed = UInt64(0)
    var full_checksum = UInt64(1469598103934665603)
    var fingerprint = UInt64(1469598103934665603)
    for iteration in range(iterations):
        var fields: WifiHeSigASUFields
        var start = UInt64(0)
        if measure:
            start = global_perf_counter_ns()
        if ((iteration + salt) & 1) == 0:
            fields = wifi_he_sig_a_su_parse(black_box(su_bits))
        else:
            fields = wifi_he_sig_a_su_parse(
                black_box(er_bits), extended_range=True
            )
        if measure:
            elapsed += global_perf_counter_ns() - start
        full_checksum = _mix_he_fields(full_checksum, fields)
        fingerprint = _mix(
            fingerprint,
            fields.mcs_index * 257 + fields.crc + iteration,
        )
        keep(fields)
    return _WorkloadMeasurement(elapsed, full_checksum, fingerprint)


@no_inline
def _he_geometry_workload(
    iterations: Int, salt: Int, measure: Bool
) raises -> _WorkloadMeasurement:
    var elapsed = UInt64(0)
    var full_checksum = UInt64(1469598103934665603)
    var fingerprint = UInt64(1469598103934665603)
    for iteration in range(iterations):
        var selector = iteration + salt
        var extended = (selector & 1) != 0
        var config = WifiHeSigASUConfig(
            selector % (3 if extended else 12),
            extended_range=black_box(extended),
            bandwidth_mhz=black_box(20 if extended else _bandwidth(selector)),
            space_time_streams=black_box(
                1 if extended else 1 + ((selector >> 3) & 7)
            ),
        )
        var start = UInt64(0)
        if measure:
            start = global_perf_counter_ns()
        var geometry = wifi_he_sig_a_su_geometry(config)
        if measure:
            elapsed += global_perf_counter_ns() - start
        full_checksum = _mix(full_checksum, geometry.field_bits)
        full_checksum = _mix(full_checksum, geometry.crc_covered_bits)
        full_checksum = _mix(full_checksum, geometry.crc_bits)
        full_checksum = _mix(full_checksum, geometry.tail_bits)
        full_checksum = _mix(full_checksum, geometry.information_parts)
        full_checksum = _mix(full_checksum, geometry.part_bits)
        full_checksum = _mix(
            full_checksum, geometry.repetitions_per_part
        )
        full_checksum = _mix(full_checksum, geometry.ofdm_symbols)
        full_checksum = _mix(
            full_checksum, geometry.duration_ns + iteration
        )
        fingerprint = _mix(
            fingerprint,
            geometry.field_bits * 257
            + geometry.duration_ns
            + iteration,
        )
        keep(geometry)
    return _WorkloadMeasurement(elapsed, full_checksum, fingerprint)


@no_inline
def _u_sig_pack_workload(
    iterations: Int, salt: Int, measure: Bool
) raises -> _WorkloadMeasurement:
    var elapsed = UInt64(0)
    var full_checksum = UInt64(1469598103934665603)
    var fingerprint = UInt64(1469598103934665603)
    for iteration in range(iterations):
        var selector = iteration + salt
        var config = WifiEhtUSigSU20Config(
            black_box((selector * 11) & 63),
            uplink=black_box((selector & 1) != 0),
            txop_code=black_box((selector * 19) & 127),
            eht_sig_mcs_code=black_box((selector >> 3) & 3),
            eht_sig_symbols=black_box(1 + ((selector >> 5) & 31)),
        )
        var start = UInt64(0)
        if measure:
            start = global_perf_counter_ns()
        var bits = wifi_eht_u_sig_su_20_pack(config)
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


def _mix_u_fields(checksum: UInt64, fields: WifiEhtUSigSU20Fields) -> UInt64:
    var result = _mix(checksum, 1 if fields.uplink else 0)
    result = _mix(result, fields.bss_color)
    result = _mix(result, fields.txop_code)
    result = _mix(result, fields.eht_sig_mcs_code)
    result = _mix(result, fields.eht_sig_symbols)
    return _mix(result, fields.crc)


@no_inline
def _u_sig_parse_workload(
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
        var fields: WifiEhtUSigSU20Fields
        var start = UInt64(0)
        if measure:
            start = global_perf_counter_ns()
        if ((iteration + salt) & 1) == 0:
            fields = wifi_eht_u_sig_su_20_parse(black_box(first))
        else:
            fields = wifi_eht_u_sig_su_20_parse(black_box(second))
        if measure:
            elapsed += global_perf_counter_ns() - start
        full_checksum = _mix_u_fields(full_checksum, fields)
        fingerprint = _mix(
            fingerprint,
            fields.bss_color * 257 + fields.crc + iteration,
        )
        keep(fields)
    return _WorkloadMeasurement(elapsed, full_checksum, fingerprint)


@no_inline
def _u_sig_geometry_workload(
    iterations: Int, salt: Int, measure: Bool
) raises -> _WorkloadMeasurement:
    var elapsed = UInt64(0)
    var full_checksum = UInt64(1469598103934665603)
    var fingerprint = UInt64(1469598103934665603)
    for iteration in range(iterations):
        var selector = iteration + salt
        var config = WifiEhtUSigSU20Config(
            black_box(selector & 63),
            eht_sig_mcs_code=black_box((selector >> 4) & 3),
            eht_sig_symbols=black_box(1 + ((selector >> 6) & 31)),
        )
        var start = UInt64(0)
        if measure:
            start = global_perf_counter_ns()
        var geometry = wifi_eht_u_sig_su_20_geometry(config)
        if measure:
            elapsed += global_perf_counter_ns() - start
        full_checksum = _mix(full_checksum, geometry.field_bits)
        full_checksum = _mix(full_checksum, geometry.crc_covered_bits)
        full_checksum = _mix(full_checksum, geometry.crc_bits)
        full_checksum = _mix(full_checksum, geometry.tail_bits)
        full_checksum = _mix(full_checksum, geometry.information_parts)
        full_checksum = _mix(full_checksum, geometry.part_bits)
        full_checksum = _mix(full_checksum, geometry.bcc_coded_bits)
        full_checksum = _mix(
            full_checksum, geometry.coded_bits_per_symbol
        )
        full_checksum = _mix(full_checksum, geometry.ofdm_symbols)
        full_checksum = _mix(
            full_checksum, geometry.duration_ns + iteration
        )
        fingerprint = _mix(
            fingerprint,
            geometry.field_bits * 257
            + geometry.duration_ns
            + iteration,
        )
        keep(geometry)
    return _WorkloadMeasurement(elapsed, full_checksum, fingerprint)


@no_inline
def _block_pack_workload(
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
        var common = ((iteration + salt) & 1) == 0
        var profile = WifiEhtSigBlockProfile(
            (
                WIFI_EHT_SIG_BLOCK_COMMON
                if common
                else WIFI_EHT_SIG_BLOCK_USER
            ),
            42,
        )
        var bits: List[UInt8]
        var start = UInt64(0)
        if measure:
            start = global_perf_counter_ns()
        if common:
            bits = wifi_eht_sig_block_pack(profile, black_box(first))
        else:
            bits = wifi_eht_sig_block_pack(profile, black_box(second))
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
def _block_parse_workload(
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
        var common = ((iteration + salt) & 1) == 0
        var profile = WifiEhtSigBlockProfile(
            (
                WIFI_EHT_SIG_BLOCK_COMMON
                if common
                else WIFI_EHT_SIG_BLOCK_USER
            ),
            42,
        )
        if common:
            var start = UInt64(0)
            if measure:
                start = global_perf_counter_ns()
            var block = wifi_eht_sig_block_parse(profile, black_box(first))
            if measure:
                elapsed += global_perf_counter_ns() - start
            full_checksum = _mix(full_checksum, block.kind)
            full_checksum = _mix_bits(
                full_checksum, Span(block.content)
            )
            full_checksum = _mix(full_checksum, block.crc)
            fingerprint = _mix(
                fingerprint,
                Int(
                    _fingerprint_bits(Span(block.content))
                    & UInt64(Int.MAX)
                )
                + block.crc
                + iteration,
            )
            keep(block)
        else:
            var start = UInt64(0)
            if measure:
                start = global_perf_counter_ns()
            var block = wifi_eht_sig_block_parse(profile, black_box(second))
            if measure:
                elapsed += global_perf_counter_ns() - start
            full_checksum = _mix(full_checksum, block.kind)
            full_checksum = _mix_bits(
                full_checksum, Span(block.content)
            )
            full_checksum = _mix(full_checksum, block.crc)
            fingerprint = _mix(
                fingerprint,
                Int(
                    _fingerprint_bits(Span(block.content))
                    & UInt64(Int.MAX)
                )
                + block.crc
                + iteration,
            )
            keep(block)
    return _WorkloadMeasurement(elapsed, full_checksum, fingerprint)


@no_inline
def _block_geometry_workload(
    iterations: Int, salt: Int, measure: Bool
) raises -> _WorkloadMeasurement:
    var elapsed = UInt64(0)
    var full_checksum = UInt64(1469598103934665603)
    var fingerprint = UInt64(1469598103934665603)
    for iteration in range(iterations):
        var selector = iteration + salt
        var profile = WifiEhtSigBlockProfile(
            (
                WIFI_EHT_SIG_BLOCK_COMMON
                if (selector & 1) == 0
                else WIFI_EHT_SIG_BLOCK_USER
            ),
            black_box(1 + ((selector >> 2) & 127)),
        )
        var start = UInt64(0)
        if measure:
            start = global_perf_counter_ns()
        var geometry = wifi_eht_sig_block_geometry(profile)
        if measure:
            elapsed += global_perf_counter_ns() - start
        full_checksum = _mix(full_checksum, geometry.kind)
        full_checksum = _mix(full_checksum, geometry.content_bits)
        full_checksum = _mix(full_checksum, geometry.crc_bits)
        full_checksum = _mix(full_checksum, geometry.tail_bits)
        full_checksum = _mix(
            full_checksum, geometry.total_bits + iteration
        )
        fingerprint = _mix(
            fingerprint,
            geometry.kind * 257 + geometry.total_bits + iteration,
        )
        keep(geometry)
    return _WorkloadMeasurement(elapsed, full_checksum, fingerprint)


def main() raises:
    var first = _pattern42(UInt64(0x243F6A8885A308D3))
    var second = _pattern42(UInt64(0x13198A2E03707344))
    var he_su = wifi_he_sig_a_su_pack(
        WifiHeSigASUConfig(
            7,
            bss_color=37,
            spatial_reuse=9,
            bandwidth_mhz=80,
            gi_ltf_code=3,
            space_time_streams=4,
            txop_code=41,
            coding=WIFI_HE_EHT_SIG_CODING_LDPC,
            ldpc_extra_symbol=True,
            beamformed=True,
        )
    )
    var he_er = wifi_he_sig_a_su_pack(
        WifiHeSigASUConfig(
            2,
            extended_range=True,
            bss_color=17,
            gi_ltf_code=1,
        )
    )
    var u_first = wifi_eht_u_sig_su_20_pack(
        WifiEhtUSigSU20Config(
            21, txop_code=17, eht_sig_mcs_code=1, eht_sig_symbols=4
        )
    )
    var u_second = wifi_eht_u_sig_su_20_pack(
        WifiEhtUSigSU20Config(
            45,
            uplink=True,
            txop_code=127,
            eht_sig_mcs_code=3,
            eht_sig_symbols=11,
        )
    )
    var common_profile = WifiEhtSigBlockProfile(
        WIFI_EHT_SIG_BLOCK_COMMON, 42
    )
    var user_profile = WifiEhtSigBlockProfile(WIFI_EHT_SIG_BLOCK_USER, 42)
    var common_block = wifi_eht_sig_block_pack(
        common_profile, Span(first)
    )
    var user_block = wifi_eht_sig_block_pack(user_profile, Span(second))

    for _ in range(_WARMUPS):
        var salt = 324508639
        keep(_crc_workload(
            _BATCH, salt, Span(first), Span(second), False
        ))
        keep(_he_pack_workload(_BATCH, salt, False))
        keep(_he_parse_workload(
            _BATCH, salt, Span(he_su), Span(he_er), False
        ))
        keep(_he_geometry_workload(_BATCH, salt, False))
        keep(_u_sig_pack_workload(_BATCH, salt, False))
        keep(_u_sig_parse_workload(
            _BATCH, salt, Span(u_first), Span(u_second), False
        ))
        keep(_u_sig_geometry_workload(_BATCH, salt, False))
        keep(_block_pack_workload(
            _BATCH, salt, Span(first), Span(second), False
        ))
        keep(_block_parse_workload(
            _BATCH,
            salt,
            Span(common_block),
            Span(user_block),
            False,
        ))
        keep(_block_geometry_workload(_BATCH, salt, False))

    var crc_samples = List[UInt64](capacity=_SAMPLES)
    var he_pack_samples = List[UInt64](capacity=_SAMPLES)
    var he_parse_samples = List[UInt64](capacity=_SAMPLES)
    var he_geometry_samples = List[UInt64](capacity=_SAMPLES)
    var u_pack_samples = List[UInt64](capacity=_SAMPLES)
    var u_parse_samples = List[UInt64](capacity=_SAMPLES)
    var u_geometry_samples = List[UInt64](capacity=_SAMPLES)
    var block_pack_samples = List[UInt64](capacity=_SAMPLES)
    var block_parse_samples = List[UInt64](capacity=_SAMPLES)
    var block_geometry_samples = List[UInt64](capacity=_SAMPLES)
    var full_output_checksum = UInt64(1469598103934665603)
    var fingerprint_checksum = UInt64(1469598103934665603)

    for _ in range(_SAMPLES):
        var salt = 324508639
        _record_measurement(
            _crc_workload(
                _BATCH, salt, Span(first), Span(second), True
            ),
            crc_samples,
            full_output_checksum,
            fingerprint_checksum,
        )
        _record_measurement(
            _he_pack_workload(_BATCH, salt, True),
            he_pack_samples,
            full_output_checksum,
            fingerprint_checksum,
        )
        _record_measurement(
            _he_parse_workload(
                _BATCH, salt, Span(he_su), Span(he_er), True
            ),
            he_parse_samples,
            full_output_checksum,
            fingerprint_checksum,
        )
        _record_measurement(
            _he_geometry_workload(_BATCH, salt, True),
            he_geometry_samples,
            full_output_checksum,
            fingerprint_checksum,
        )
        _record_measurement(
            _u_sig_pack_workload(_BATCH, salt, True),
            u_pack_samples,
            full_output_checksum,
            fingerprint_checksum,
        )
        _record_measurement(
            _u_sig_parse_workload(
                _BATCH, salt, Span(u_first), Span(u_second), True
            ),
            u_parse_samples,
            full_output_checksum,
            fingerprint_checksum,
        )
        _record_measurement(
            _u_sig_geometry_workload(_BATCH, salt, True),
            u_geometry_samples,
            full_output_checksum,
            fingerprint_checksum,
        )
        _record_measurement(
            _block_pack_workload(
                _BATCH, salt, Span(first), Span(second), True
            ),
            block_pack_samples,
            full_output_checksum,
            fingerprint_checksum,
        )
        _record_measurement(
            _block_parse_workload(
                _BATCH,
                salt,
                Span(common_block),
                Span(user_block),
                True,
            ),
            block_parse_samples,
            full_output_checksum,
            fingerprint_checksum,
        )
        _record_measurement(
            _block_geometry_workload(_BATCH, salt, True),
            block_geometry_samples,
            full_output_checksum,
            fingerprint_checksum,
        )

    print_benchmark_metadata()
    print("wifi_he_eht_sig_fields_implementation: scalar-cpu-reference")
    print("wifi_he_eht_sig_fields_scope: bounded-pre-fec-fields")
    print("wifi_he_eht_sig_fields_input_variation: fixed-salted")
    print("wifi_he_eht_sig_fields_timed_scope: target-api-only")
    print("wifi_he_eht_sig_fields_post_timer_scope: keep-plus-full-output-checksum-plus-o1-fingerprint")
    report_timing_samples(
        "wifi_he_eht_sig_crc4", crc_samples, _WARMUPS, _BATCH, "crc_query"
    )
    report_timing_samples(
        "wifi_he_sig_a_su_pack",
        he_pack_samples,
        _WARMUPS,
        _BATCH,
        "signal_field",
    )
    report_timing_samples(
        "wifi_he_sig_a_su_parse",
        he_parse_samples,
        _WARMUPS,
        _BATCH,
        "signal_field",
    )
    report_timing_samples(
        "wifi_he_sig_a_su_geometry",
        he_geometry_samples,
        _WARMUPS,
        _BATCH,
        "geometry_query",
    )
    report_timing_samples(
        "wifi_eht_u_sig_su_20_pack",
        u_pack_samples,
        _WARMUPS,
        _BATCH,
        "signal_field",
    )
    report_timing_samples(
        "wifi_eht_u_sig_su_20_parse",
        u_parse_samples,
        _WARMUPS,
        _BATCH,
        "signal_field",
    )
    report_timing_samples(
        "wifi_eht_u_sig_su_20_geometry",
        u_geometry_samples,
        _WARMUPS,
        _BATCH,
        "geometry_query",
    )
    report_timing_samples(
        "wifi_eht_sig_block_pack",
        block_pack_samples,
        _WARMUPS,
        _BATCH,
        "crc_block",
    )
    report_timing_samples(
        "wifi_eht_sig_block_parse",
        block_parse_samples,
        _WARMUPS,
        _BATCH,
        "crc_block",
    )
    report_timing_samples(
        "wifi_eht_sig_block_geometry",
        block_geometry_samples,
        _WARMUPS,
        _BATCH,
        "geometry_query",
    )
    keep(full_output_checksum)
    keep(fingerprint_checksum)
    print(
        "wifi_he_eht_sig_fields_full_output_checksum:",
        full_output_checksum,
    )
    print(
        "wifi_he_eht_sig_fields_fingerprint_checksum:",
        fingerprint_checksum,
    )
