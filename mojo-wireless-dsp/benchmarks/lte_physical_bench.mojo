"""Attributable scalar-CPU timings for the bounded LTE physical profile.

Every ledger-backed public API has a separate no-inline timed entry and a
separate report.  Configurations, Lists, Spans, and derived fixtures are built
before timing.  Timed regions contain one target call; complete owned results
are retained and fingerprinted in O(1) only after timing stops.
"""

from std.benchmark import keep
from std.collections import Span
from std.time import global_perf_counter_ns
from wireless_dsp.benchmarking import (
    print_benchmark_metadata,
    report_timing_samples,
)
from wireless_dsp.core import Complex64
from wireless_dsp.wireless.lte.physical import (
    LTEFDDConfiguration,
    lte_gold_bits,
    lte_pss_root,
    lte_pss,
    lte_sss_indices,
    lte_sss,
    lte_fdd_configuration,
    lte_normal_cp_samples,
    lte_crs_c_init,
    lte_crs_sequence,
    lte_crs_port_mapping,
    lte_pdsch_scrambling_c_init,
    lte_pdsch_scramble,
    lte_sc_fdma_transform_precoding,
    lte_sc_fdma_transform_deprecoding,
    lte_pusch_dmrs_ifdma_short_base_sequence,
    lte_pusch_dmrs_base_sequence,
    lte_pusch_dmrs_sequence,
)
from wireless_dsp.wireless.lte.procedures import (
    lte_downlink_mcs_profile,
    lte_downlink_mcs_entry,
    lte_downlink_redundancy_version,
    lte_uplink_mcs_entry,
    lte_base_tbs_table_bounds,
    lte_base_transport_block_size,
    lte_downlink_transport_block_size,
    lte_downlink_resource_block_group_size,
    lte_downlink_type0_resource_blocks,
    lte_uplink_encode_riv,
    lte_uplink_decode_riv,
)
from wireless_dsp.wireless.lte.measurements import (
    lte_rsrp,
    lte_rssi,
    lte_rsrq,
    lte_rs_sinr_from_powers,
    lte_rs_sinr,
)


comptime _WARMUPS = 3
comptime _SAMPLES = 9


def _mix(checksum: UInt64, value: UInt64) -> UInt64:
    return (checksum ^ value) * UInt64(1099511628211)


def _require_repeat(first: UInt64, second: UInt64) raises:
    if first != second:
        raise Error("fixed LTE benchmark result is nondeterministic")
    keep(first)
    keep(second)


def _fingerprint_float(value: Float64) -> UInt64:
    var magnitude = UInt64(Int(abs(value) * 1_000_000.0))
    return _mix(magnitude, UInt64(1 if value < 0.0 else 0))


def _fingerprint_complex(value: Complex64) -> UInt64:
    return _mix(_fingerprint_float(value.re), _fingerprint_float(value.im))


def _fingerprint_uint8(values: List[UInt8]) -> UInt64:
    var fingerprint = UInt64(len(values))
    if len(values) > 0:
        fingerprint = _mix(fingerprint, UInt64(values[0]))
        fingerprint = _mix(fingerprint, UInt64(values[len(values) - 1]))
    return fingerprint


def _fingerprint_int(values: List[Int]) -> UInt64:
    var fingerprint = UInt64(len(values))
    if len(values) > 0:
        fingerprint = _mix(fingerprint, UInt64(values[0] + 4096))
        fingerprint = _mix(fingerprint, UInt64(values[len(values) - 1] + 4096))
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


def _bits(length: Int, salt: Int) -> List[UInt8]:
    var result = List[UInt8](capacity=length)
    for index in range(length):
        result.append(UInt8(((17 * index + index // 3 + salt) >> 1) & 1))
    return result^


def _complex_fixture() -> List[Complex64]:
    var values = List[Complex64](capacity=24)
    for index in range(24):
        values.append(
            Complex64(
                Float64(index % 7) - 3.0,
                Float64(index % 5) - 2.0,
            )
        )
    return values^


def _noise_fixture() -> List[Complex64]:
    var values = List[Complex64](capacity=24)
    for index in range(24):
        values.append(
            Complex64(
                0.25 + Float64(index % 3) * 0.125,
                -0.25 + Float64(index % 2) * 0.125,
            )
        )
    return values^


@no_inline
def _bench_lte_pss_root(n_id_2: Int) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = lte_pss_root(n_id_2)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, UInt64(result))


def _run_lte_pss_root() raises -> UInt64:
    var n_id_2 = 2
    var first = _bench_lte_pss_root(n_id_2)
    var second = _bench_lte_pss_root(n_id_2)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_lte_pss_root(n_id_2))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_lte_pss_root(n_id_2)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("lte_pss_root", samples, checksum)


@no_inline
def _bench_lte_sss_indices(n_id_1: Int) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = lte_sss_indices(n_id_1)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _mix(UInt64(result[0]), UInt64(result[1]))
    return (elapsed, fingerprint)


def _run_lte_sss_indices() raises -> UInt64:
    var n_id_1 = 137
    var first = _bench_lte_sss_indices(n_id_1)
    var second = _bench_lte_sss_indices(n_id_1)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_lte_sss_indices(n_id_1))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_lte_sss_indices(n_id_1)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("lte_sss_indices", samples, checksum)


@no_inline
def _bench_lte_fdd_configuration(
    channel_bandwidth_khz: Int,
) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = lte_fdd_configuration(channel_bandwidth_khz)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _mix(
        UInt64(result.channel_bandwidth_khz),
        UInt64(result.downlink_resource_blocks),
    )
    fingerprint = _mix(fingerprint, UInt64(result.fft_size))
    fingerprint = _mix(fingerprint, UInt64(result.sample_rate_hz))
    return (elapsed, fingerprint)


def _run_lte_fdd_configuration() raises -> UInt64:
    var channel_bandwidth_khz = 20000
    var first = _bench_lte_fdd_configuration(channel_bandwidth_khz)
    var second = _bench_lte_fdd_configuration(channel_bandwidth_khz)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_lte_fdd_configuration(channel_bandwidth_khz))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_lte_fdd_configuration(channel_bandwidth_khz)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("lte_fdd_configuration", samples, checksum)


@no_inline
def _bench_lte_normal_cp_samples(
    configuration: LTEFDDConfiguration, symbol_in_slot: Int
) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = lte_normal_cp_samples(configuration, symbol_in_slot)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, UInt64(result))


def _run_lte_normal_cp_samples() raises -> UInt64:
    var configuration = lte_fdd_configuration(20000)
    var symbol_in_slot = 0
    var first = _bench_lte_normal_cp_samples(configuration, symbol_in_slot)
    var second = _bench_lte_normal_cp_samples(configuration, symbol_in_slot)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_lte_normal_cp_samples(configuration, symbol_in_slot))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_lte_normal_cp_samples(configuration, symbol_in_slot)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("lte_normal_cp_samples", samples, checksum)


@no_inline
def _bench_lte_crs_c_init(
    physical_cell_id: Int, slot: Int, symbol_in_slot: Int
) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = lte_crs_c_init(physical_cell_id, slot, symbol_in_slot)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, UInt64(result))


def _run_lte_crs_c_init() raises -> UInt64:
    var physical_cell_id = 137
    var slot = 7
    var symbol_in_slot = 4
    var first = _bench_lte_crs_c_init(physical_cell_id, slot, symbol_in_slot)
    var second = _bench_lte_crs_c_init(physical_cell_id, slot, symbol_in_slot)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_lte_crs_c_init(physical_cell_id, slot, symbol_in_slot))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_lte_crs_c_init(
            physical_cell_id, slot, symbol_in_slot
        )
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("lte_crs_c_init", samples, checksum)


@no_inline
def _bench_lte_gold_bits(
    c_init: UInt32, length: Int
) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = lte_gold_bits(c_init, length)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _fingerprint_uint8(result)
    return (elapsed, fingerprint)


def _run_lte_gold_bits() raises -> UInt64:
    var c_init = UInt32(0x1234567)
    var length = 128
    var first = _bench_lte_gold_bits(c_init, length)
    var second = _bench_lte_gold_bits(c_init, length)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_lte_gold_bits(c_init, length))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_lte_gold_bits(c_init, length)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("lte_gold_bits", samples, checksum)


@no_inline
def _bench_lte_pss(n_id_2: Int) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = lte_pss(n_id_2)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _fingerprint_complex64(result)
    return (elapsed, fingerprint)


def _run_lte_pss() raises -> UInt64:
    var n_id_2 = 2
    var first = _bench_lte_pss(n_id_2)
    var second = _bench_lte_pss(n_id_2)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_lte_pss(n_id_2))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_lte_pss(n_id_2)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("lte_pss", samples, checksum)


@no_inline
def _bench_lte_sss(
    physical_cell_id: Int, subframe: Int
) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = lte_sss(physical_cell_id, subframe)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = UInt64(len(result))
    fingerprint = _mix(fingerprint, _fingerprint_float(result[0]))
    fingerprint = _mix(fingerprint, _fingerprint_float(result[len(result) - 1]))
    return (elapsed, fingerprint)


def _run_lte_sss() raises -> UInt64:
    var physical_cell_id = 137
    var subframe = 5
    var first = _bench_lte_sss(physical_cell_id, subframe)
    var second = _bench_lte_sss(physical_cell_id, subframe)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_lte_sss(physical_cell_id, subframe))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_lte_sss(physical_cell_id, subframe)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("lte_sss", samples, checksum)


@no_inline
def _bench_lte_crs_sequence(
    physical_cell_id: Int, slot: Int, symbol: Int
) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = lte_crs_sequence(physical_cell_id, slot, symbol)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _fingerprint_complex64(result)
    return (elapsed, fingerprint)


def _run_lte_crs_sequence() raises -> UInt64:
    var physical_cell_id = 137
    var slot = 7
    var symbol = 4
    var first = _bench_lte_crs_sequence(physical_cell_id, slot, symbol)
    var second = _bench_lte_crs_sequence(physical_cell_id, slot, symbol)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_lte_crs_sequence(physical_cell_id, slot, symbol))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_lte_crs_sequence(physical_cell_id, slot, symbol)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("lte_crs_sequence", samples, checksum)


@no_inline
def _bench_lte_pusch_dmrs_base_sequence(
    group_number: Int,
    sequence_number: Int,
    allocated_resource_blocks: Int,
) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = lte_pusch_dmrs_base_sequence(
        group_number, sequence_number, allocated_resource_blocks
    )
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _fingerprint_complex64(result)
    return (elapsed, fingerprint)


def _run_lte_pusch_dmrs_base_sequence() raises -> UInt64:
    var group_number = 29
    var sequence_number = 0
    var allocated_resource_blocks = 1
    var first = _bench_lte_pusch_dmrs_base_sequence(
        group_number, sequence_number, allocated_resource_blocks
    )
    var second = _bench_lte_pusch_dmrs_base_sequence(
        group_number, sequence_number, allocated_resource_blocks
    )
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(
            _bench_lte_pusch_dmrs_base_sequence(
                group_number, sequence_number, allocated_resource_blocks
            )
        )
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_lte_pusch_dmrs_base_sequence(
            group_number, sequence_number, allocated_resource_blocks
        )
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("lte_pusch_dmrs_base_sequence", samples, checksum)


@no_inline
def _bench_lte_pusch_dmrs_ifdma_short_base_sequence(
    group_number: Int,
    reference_signal_subcarriers: Int,
) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = lte_pusch_dmrs_ifdma_short_base_sequence(
        group_number, reference_signal_subcarriers
    )
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _fingerprint_complex64(result)
    return (elapsed, fingerprint)


def _run_lte_pusch_dmrs_ifdma_short_base_sequence() raises -> UInt64:
    var group_number = 29
    var reference_signal_subcarriers = 18
    var first = _bench_lte_pusch_dmrs_ifdma_short_base_sequence(
        group_number, reference_signal_subcarriers
    )
    var second = _bench_lte_pusch_dmrs_ifdma_short_base_sequence(
        group_number, reference_signal_subcarriers
    )
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(
            _bench_lte_pusch_dmrs_ifdma_short_base_sequence(
                group_number, reference_signal_subcarriers
            )
        )
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_lte_pusch_dmrs_ifdma_short_base_sequence(
            group_number, reference_signal_subcarriers
        )
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample(
        "lte_pusch_dmrs_ifdma_short_base_sequence", samples, checksum
    )


@no_inline
def _bench_lte_pusch_dmrs_sequence(
    group_number: Int,
    sequence_number: Int,
    allocated_resource_blocks: Int,
    cyclic_shift_index: Int,
) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = lte_pusch_dmrs_sequence(
        group_number,
        sequence_number,
        allocated_resource_blocks,
        cyclic_shift_index,
    )
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _fingerprint_complex64(result)
    return (elapsed, fingerprint)


def _run_lte_pusch_dmrs_sequence() raises -> UInt64:
    var group_number = 17
    var sequence_number = 0
    var allocated_resource_blocks = 2
    var cyclic_shift_index = 11
    var first = _bench_lte_pusch_dmrs_sequence(
        group_number,
        sequence_number,
        allocated_resource_blocks,
        cyclic_shift_index,
    )
    var second = _bench_lte_pusch_dmrs_sequence(
        group_number,
        sequence_number,
        allocated_resource_blocks,
        cyclic_shift_index,
    )
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(
            _bench_lte_pusch_dmrs_sequence(
                group_number,
                sequence_number,
                allocated_resource_blocks,
                cyclic_shift_index,
            )
        )
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_lte_pusch_dmrs_sequence(
            group_number,
            sequence_number,
            allocated_resource_blocks,
            cyclic_shift_index,
        )
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("lte_pusch_dmrs_sequence", samples, checksum)


@no_inline
def _bench_lte_crs_port_mapping(
    physical_cell_id: Int,
    slot: Int,
    antenna_port: Int,
    resource_blocks: Int,
) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = lte_crs_port_mapping(
        physical_cell_id, slot, antenna_port, resource_blocks
    )
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = UInt64(len(result))
    fingerprint = _mix(fingerprint, UInt64(result[0].subcarrier))
    fingerprint = _mix(
        fingerprint, UInt64(result[len(result) - 1].sequence_index)
    )
    return (elapsed, fingerprint)


def _run_lte_crs_port_mapping() raises -> UInt64:
    var physical_cell_id = 137
    var slot = 7
    var antenna_port = 3
    var resource_blocks = 25
    var first = _bench_lte_crs_port_mapping(
        physical_cell_id, slot, antenna_port, resource_blocks
    )
    var second = _bench_lte_crs_port_mapping(
        physical_cell_id, slot, antenna_port, resource_blocks
    )
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(
            _bench_lte_crs_port_mapping(
                physical_cell_id, slot, antenna_port, resource_blocks
            )
        )
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_lte_crs_port_mapping(
            physical_cell_id, slot, antenna_port, resource_blocks
        )
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("lte_crs_port_mapping", samples, checksum)


@no_inline
def _bench_lte_pdsch_scrambling_c_init(
    rnti: Int, codeword: Int, slot: Int, physical_cell_id: Int
) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = lte_pdsch_scrambling_c_init(
        rnti, codeword, slot, physical_cell_id
    )
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = UInt64(result)
    return (elapsed, fingerprint)


def _run_lte_pdsch_scrambling_c_init() raises -> UInt64:
    var rnti = 0x1234
    var codeword = 1
    var slot = 7
    var physical_cell_id = 137
    var first = _bench_lte_pdsch_scrambling_c_init(
        rnti, codeword, slot, physical_cell_id
    )
    var second = _bench_lte_pdsch_scrambling_c_init(
        rnti, codeword, slot, physical_cell_id
    )
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(
            _bench_lte_pdsch_scrambling_c_init(
                rnti, codeword, slot, physical_cell_id
            )
        )
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_lte_pdsch_scrambling_c_init(
            rnti, codeword, slot, physical_cell_id
        )
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("lte_pdsch_scrambling_c_init", samples, checksum)


@no_inline
def _bench_lte_pdsch_scramble(
    bits: Span[UInt8, ...],
    rnti: Int,
    codeword: Int,
    slot: Int,
    physical_cell_id: Int,
) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = lte_pdsch_scramble(
        bits, rnti, codeword, slot, physical_cell_id
    )
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _fingerprint_uint8(result)
    return (elapsed, fingerprint)


def _run_lte_pdsch_scramble() raises -> UInt64:
    var bits = _bits(128, 5)
    var bits_span = Span(bits)
    var rnti = 0x1234
    var codeword = 1
    var slot = 7
    var physical_cell_id = 137
    var first = _bench_lte_pdsch_scramble(
        bits_span, rnti, codeword, slot, physical_cell_id
    )
    var second = _bench_lte_pdsch_scramble(
        bits_span, rnti, codeword, slot, physical_cell_id
    )
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(
            _bench_lte_pdsch_scramble(
                bits_span, rnti, codeword, slot, physical_cell_id
            )
        )
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_lte_pdsch_scramble(
            bits_span, rnti, codeword, slot, physical_cell_id
        )
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("lte_pdsch_scramble", samples, checksum)


@no_inline
def _bench_lte_sc_fdma_transform_precoding(
    symbols: Span[Complex64, ...]
) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = lte_sc_fdma_transform_precoding(symbols)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _fingerprint_complex64(result)
    return (elapsed, fingerprint)


def _run_lte_sc_fdma_transform_precoding() raises -> UInt64:
    var symbols = _complex_fixture()
    var symbols_span = Span(symbols)
    var first = _bench_lte_sc_fdma_transform_precoding(symbols_span)
    var second = _bench_lte_sc_fdma_transform_precoding(symbols_span)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_lte_sc_fdma_transform_precoding(symbols_span))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_lte_sc_fdma_transform_precoding(symbols_span)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("lte_sc_fdma_transform_precoding", samples, checksum)


@no_inline
def _bench_lte_sc_fdma_transform_deprecoding(
    symbols: Span[Complex64, ...]
) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = lte_sc_fdma_transform_deprecoding(symbols)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _fingerprint_complex64(result)
    return (elapsed, fingerprint)


def _run_lte_sc_fdma_transform_deprecoding() raises -> UInt64:
    var source = _complex_fixture()
    var symbols = lte_sc_fdma_transform_precoding(Span(source))
    var symbols_span = Span(symbols)
    var first = _bench_lte_sc_fdma_transform_deprecoding(symbols_span)
    var second = _bench_lte_sc_fdma_transform_deprecoding(symbols_span)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_lte_sc_fdma_transform_deprecoding(symbols_span))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_lte_sc_fdma_transform_deprecoding(symbols_span)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample(
        "lte_sc_fdma_transform_deprecoding", samples, checksum
    )


@no_inline
def _bench_lte_downlink_mcs_profile(index: Int) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = lte_downlink_mcs_profile(index)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = UInt64(result.index)
    fingerprint = _mix(fingerprint, UInt64(result.modulation_order))
    fingerprint = _mix(fingerprint, UInt64(result.second_slot_modulation_order))
    fingerprint = _mix(fingerprint, UInt64(result.tbs_index))
    fingerprint = _mix(
        fingerprint, UInt64(1 if result.tbs_index_26a_possible else 0)
    )
    return (elapsed, fingerprint)


def _run_lte_downlink_mcs_profile() raises -> UInt64:
    var index = 28
    var first = _bench_lte_downlink_mcs_profile(index)
    var second = _bench_lte_downlink_mcs_profile(index)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_lte_downlink_mcs_profile(index))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_lte_downlink_mcs_profile(index)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("lte_downlink_mcs_profile", samples, checksum)


@no_inline
def _bench_lte_base_tbs_table_bounds() -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = lte_base_tbs_table_bounds()
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = UInt64(result.minimum_base_tbs_index)
    fingerprint = _mix(
        fingerprint, UInt64(result.maximum_base_numeric_tbs_index)
    )
    fingerprint = _mix(
        fingerprint, UInt64(result.maximum_complete_numeric_tbs_index)
    )
    fingerprint = _mix(fingerprint, UInt64(result.maximum_resource_blocks))
    fingerprint = _mix(
        fingerprint, UInt64(1 if result.full_lookup_implemented else 0)
    )
    return (elapsed, fingerprint)


def _run_lte_base_tbs_table_bounds() raises -> UInt64:
    var first = _bench_lte_base_tbs_table_bounds()
    var second = _bench_lte_base_tbs_table_bounds()
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_lte_base_tbs_table_bounds())
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_lte_base_tbs_table_bounds()
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("lte_base_tbs_table_bounds", samples, checksum)


@no_inline
def _bench_lte_downlink_resource_block_group_size(
    downlink_resource_blocks: Int,
) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = lte_downlink_resource_block_group_size(
        downlink_resource_blocks
    )
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, UInt64(result))


def _run_lte_downlink_resource_block_group_size() raises -> UInt64:
    var downlink_resource_blocks = 100
    var first = _bench_lte_downlink_resource_block_group_size(
        downlink_resource_blocks
    )
    var second = _bench_lte_downlink_resource_block_group_size(
        downlink_resource_blocks
    )
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(
            _bench_lte_downlink_resource_block_group_size(
                downlink_resource_blocks
            )
        )
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_lte_downlink_resource_block_group_size(
            downlink_resource_blocks
        )
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample(
        "lte_downlink_resource_block_group_size", samples, checksum
    )


@no_inline
def _bench_lte_downlink_mcs_entry(index: Int) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = lte_downlink_mcs_entry(index)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = UInt64(result.index)
    fingerprint = _mix(fingerprint, UInt64(result.modulation_order))
    fingerprint = _mix(fingerprint, UInt64(result.tbs_index + 1))
    return (elapsed, fingerprint)


def _run_lte_downlink_mcs_entry() raises -> UInt64:
    var index = 17
    var first = _bench_lte_downlink_mcs_entry(index)
    var second = _bench_lte_downlink_mcs_entry(index)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_lte_downlink_mcs_entry(index))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_lte_downlink_mcs_entry(index)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("lte_downlink_mcs_entry", samples, checksum)


@no_inline
def _bench_lte_downlink_redundancy_version(
    rv_value: Int,
) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = lte_downlink_redundancy_version(rv_value)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = UInt64(result)
    return (elapsed, fingerprint)


def _run_lte_downlink_redundancy_version() raises -> UInt64:
    var rv_value = 2
    var first = _bench_lte_downlink_redundancy_version(rv_value)
    var second = _bench_lte_downlink_redundancy_version(rv_value)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_lte_downlink_redundancy_version(rv_value))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_lte_downlink_redundancy_version(rv_value)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("lte_downlink_redundancy_version", samples, checksum)


@no_inline
def _bench_lte_uplink_mcs_entry(index: Int) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = lte_uplink_mcs_entry(index)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = UInt64(result.index)
    fingerprint = _mix(fingerprint, UInt64(result.modulation_order))
    fingerprint = _mix(fingerprint, UInt64(result.tbs_index + 1))
    fingerprint = _mix(fingerprint, UInt64(result.redundancy_version))
    return (elapsed, fingerprint)


def _run_lte_uplink_mcs_entry() raises -> UInt64:
    var index = 17
    var first = _bench_lte_uplink_mcs_entry(index)
    var second = _bench_lte_uplink_mcs_entry(index)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_lte_uplink_mcs_entry(index))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_lte_uplink_mcs_entry(index)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("lte_uplink_mcs_entry", samples, checksum)


@no_inline
def _bench_lte_base_transport_block_size(
    tbs_index: Int, resource_blocks: Int
) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = lte_base_transport_block_size(tbs_index, resource_blocks)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = UInt64(result)
    return (elapsed, fingerprint)


def _run_lte_base_transport_block_size() raises -> UInt64:
    var tbs_index = 10
    var resource_blocks = 25
    var first = _bench_lte_base_transport_block_size(tbs_index, resource_blocks)
    var second = _bench_lte_base_transport_block_size(
        tbs_index, resource_blocks
    )
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_lte_base_transport_block_size(tbs_index, resource_blocks))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_lte_base_transport_block_size(
            tbs_index, resource_blocks
        )
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("lte_base_transport_block_size", samples, checksum)


@no_inline
def _bench_lte_downlink_transport_block_size(
    mcs_index: Int, resource_blocks: Int
) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = lte_downlink_transport_block_size(mcs_index, resource_blocks)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = UInt64(result)
    return (elapsed, fingerprint)


def _run_lte_downlink_transport_block_size() raises -> UInt64:
    var mcs_index = 17
    var resource_blocks = 25
    var first = _bench_lte_downlink_transport_block_size(
        mcs_index, resource_blocks
    )
    var second = _bench_lte_downlink_transport_block_size(
        mcs_index, resource_blocks
    )
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(
            _bench_lte_downlink_transport_block_size(mcs_index, resource_blocks)
        )
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_lte_downlink_transport_block_size(
            mcs_index, resource_blocks
        )
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample(
        "lte_downlink_transport_block_size", samples, checksum
    )


@no_inline
def _bench_lte_downlink_type0_resource_blocks(
    resource_blocks: Int, bitmap: UInt32
) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = lte_downlink_type0_resource_blocks(resource_blocks, bitmap)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _fingerprint_int(result)
    return (elapsed, fingerprint)


def _run_lte_downlink_type0_resource_blocks() raises -> UInt64:
    var resource_blocks = 50
    var bitmap = UInt32(0b101011)
    var first = _bench_lte_downlink_type0_resource_blocks(
        resource_blocks, bitmap
    )
    var second = _bench_lte_downlink_type0_resource_blocks(
        resource_blocks, bitmap
    )
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_lte_downlink_type0_resource_blocks(resource_blocks, bitmap))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_lte_downlink_type0_resource_blocks(
            resource_blocks, bitmap
        )
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample(
        "lte_downlink_type0_resource_blocks", samples, checksum
    )


@no_inline
def _bench_lte_uplink_encode_riv(
    resource_blocks: Int, first_resource_block: Int, allocation_length: Int
) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = lte_uplink_encode_riv(
        resource_blocks, first_resource_block, allocation_length
    )
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = UInt64(result)
    return (elapsed, fingerprint)


def _run_lte_uplink_encode_riv() raises -> UInt64:
    var resource_blocks = 50
    var first_resource_block = 7
    var allocation_length = 12
    var first = _bench_lte_uplink_encode_riv(
        resource_blocks, first_resource_block, allocation_length
    )
    var second = _bench_lte_uplink_encode_riv(
        resource_blocks, first_resource_block, allocation_length
    )
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(
            _bench_lte_uplink_encode_riv(
                resource_blocks, first_resource_block, allocation_length
            )
        )
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_lte_uplink_encode_riv(
            resource_blocks, first_resource_block, allocation_length
        )
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("lte_uplink_encode_riv", samples, checksum)


@no_inline
def _bench_lte_uplink_decode_riv(
    resource_blocks: Int, riv: Int
) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = lte_uplink_decode_riv(resource_blocks, riv)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = UInt64(result.first_resource_block)
    fingerprint = _mix(fingerprint, UInt64(result.allocated_resource_blocks))
    fingerprint = _mix(fingerprint, UInt64(result.resource_indication_value))
    return (elapsed, fingerprint)


def _run_lte_uplink_decode_riv() raises -> UInt64:
    var resource_blocks = 50
    var riv = lte_uplink_encode_riv(resource_blocks, 7, 12)
    var first = _bench_lte_uplink_decode_riv(resource_blocks, riv)
    var second = _bench_lte_uplink_decode_riv(resource_blocks, riv)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_lte_uplink_decode_riv(resource_blocks, riv))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_lte_uplink_decode_riv(resource_blocks, riv)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("lte_uplink_decode_riv", samples, checksum)


@no_inline
def _bench_lte_rsrp(
    signal: Span[Complex64, ...]
) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = lte_rsrp(signal)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _fingerprint_float(result)
    return (elapsed, fingerprint)


def _run_lte_rsrp() raises -> UInt64:
    var signal = _complex_fixture()
    var signal_span = Span(signal)
    var first = _bench_lte_rsrp(signal_span)
    var second = _bench_lte_rsrp(signal_span)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_lte_rsrp(signal_span))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_lte_rsrp(signal_span)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("lte_rsrp", samples, checksum)


@no_inline
def _bench_lte_rssi(
    signal: Span[Complex64, ...], resource_elements_per_symbol: Int
) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = lte_rssi(signal, resource_elements_per_symbol)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _fingerprint_float(result)
    return (elapsed, fingerprint)


def _run_lte_rssi() raises -> UInt64:
    var signal = _complex_fixture()
    var signal_span = Span(signal)
    var resource_elements_per_symbol = 12
    var first = _bench_lte_rssi(signal_span, resource_elements_per_symbol)
    var second = _bench_lte_rssi(signal_span, resource_elements_per_symbol)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_lte_rssi(signal_span, resource_elements_per_symbol))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_lte_rssi(signal_span, resource_elements_per_symbol)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("lte_rssi", samples, checksum)


@no_inline
def _bench_lte_rsrq(
    rsrp: Float64, rssi: Float64, resource_blocks: Int
) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = lte_rsrq(rsrp, rssi, resource_blocks)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _fingerprint_float(result)
    return (elapsed, fingerprint)


def _run_lte_rsrq() raises -> UInt64:
    var rsrp = 2.0
    var rssi = 24.0
    var resource_blocks = 25
    var first = _bench_lte_rsrq(rsrp, rssi, resource_blocks)
    var second = _bench_lte_rsrq(rsrp, rssi, resource_blocks)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_lte_rsrq(rsrp, rssi, resource_blocks))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_lte_rsrq(rsrp, rssi, resource_blocks)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("lte_rsrq", samples, checksum)


@no_inline
def _bench_lte_rs_sinr_from_powers(
    signal_power: Float64, noise_power: Float64
) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = lte_rs_sinr_from_powers(signal_power, noise_power)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _fingerprint_float(result)
    return (elapsed, fingerprint)


def _run_lte_rs_sinr_from_powers() raises -> UInt64:
    var signal_power = 2.0
    var noise_power = 0.5
    var first = _bench_lte_rs_sinr_from_powers(signal_power, noise_power)
    var second = _bench_lte_rs_sinr_from_powers(signal_power, noise_power)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_lte_rs_sinr_from_powers(signal_power, noise_power))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_lte_rs_sinr_from_powers(signal_power, noise_power)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("lte_rs_sinr_from_powers", samples, checksum)


@no_inline
def _bench_lte_rs_sinr(
    signal: Span[Complex64, ...], noise: Span[Complex64, ...]
) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = lte_rs_sinr(signal, noise)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _fingerprint_float(result)
    return (elapsed, fingerprint)


def _run_lte_rs_sinr() raises -> UInt64:
    var signal = _complex_fixture()
    var noise = _noise_fixture()
    var signal_span = Span(signal)
    var noise_span = Span(noise)
    var first = _bench_lte_rs_sinr(signal_span, noise_span)
    var second = _bench_lte_rs_sinr(signal_span, noise_span)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_lte_rs_sinr(signal_span, noise_span))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_lte_rs_sinr(signal_span, noise_span)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("lte_rs_sinr", samples, checksum)


# Compatibility entry points retained for Feature references.  They delegate
# to the independent runners and are not used as grouped timing regions.
def _sequence_workload() raises -> UInt64:
    return (
        _run_lte_gold_bits()
        ^ _run_lte_pss_root()
        ^ _run_lte_pss()
        ^ _run_lte_sss_indices()
        ^ _run_lte_sss()
        ^ _run_lte_fdd_configuration()
        ^ _run_lte_normal_cp_samples()
        ^ _run_lte_crs_c_init()
        ^ _run_lte_crs_sequence()
        ^ _run_lte_pusch_dmrs_base_sequence()
        ^ _run_lte_pusch_dmrs_ifdma_short_base_sequence()
        ^ _run_lte_pusch_dmrs_sequence()
        ^ _run_lte_crs_port_mapping()
        ^ _run_lte_pdsch_scrambling_c_init()
        ^ _run_lte_pdsch_scramble()
    )


def _procedure_workload() raises -> UInt64:
    return (
        _run_lte_downlink_mcs_profile()
        ^ _run_lte_downlink_mcs_entry()
        ^ _run_lte_downlink_redundancy_version()
        ^ _run_lte_uplink_mcs_entry()
        ^ _run_lte_base_tbs_table_bounds()
        ^ _run_lte_base_transport_block_size()
        ^ _run_lte_downlink_transport_block_size()
        ^ _run_lte_downlink_resource_block_group_size()
        ^ _run_lte_downlink_type0_resource_blocks()
        ^ _run_lte_uplink_encode_riv()
        ^ _run_lte_uplink_decode_riv()
    )


def _measurement_workload() raises -> UInt64:
    return (
        _run_lte_rsrp()
        ^ _run_lte_rssi()
        ^ _run_lte_rsrq()
        ^ _run_lte_rs_sinr_from_powers()
        ^ _run_lte_rs_sinr()
    )


def _transform_workload() raises -> UInt64:
    return (
        _run_lte_sc_fdma_transform_precoding()
        ^ _run_lte_sc_fdma_transform_deprecoding()
    )


def main() raises:
    print_benchmark_metadata()
    print("lte_physical_standard_baseline:", "3GPP-TS-36.211-V18.0.2")
    print("lte_procedures_standard_baseline:", "3GPP-TS-36.213-V18.3.0")
    print("lte_measurements_standard_baseline:", "3GPP-TS-36.214-V18.1.0")
    print("lte_profile:", "FDD-normal-CP-15kHz-SISO-CPU-reference")
    print("timing_scope_includes_output_allocation:", True)
    var checksum = UInt64(1469598103934665603)
    checksum = _mix(checksum, _run_lte_gold_bits())
    checksum = _mix(checksum, _run_lte_pss_root())
    checksum = _mix(checksum, _run_lte_pss())
    checksum = _mix(checksum, _run_lte_sss_indices())
    checksum = _mix(checksum, _run_lte_sss())
    checksum = _mix(checksum, _run_lte_fdd_configuration())
    checksum = _mix(checksum, _run_lte_normal_cp_samples())
    checksum = _mix(checksum, _run_lte_crs_c_init())
    checksum = _mix(checksum, _run_lte_crs_sequence())
    checksum = _mix(checksum, _run_lte_pusch_dmrs_base_sequence())
    checksum = _mix(
        checksum, _run_lte_pusch_dmrs_ifdma_short_base_sequence()
    )
    checksum = _mix(checksum, _run_lte_pusch_dmrs_sequence())
    checksum = _mix(checksum, _run_lte_crs_port_mapping())
    checksum = _mix(checksum, _run_lte_pdsch_scrambling_c_init())
    checksum = _mix(checksum, _run_lte_pdsch_scramble())
    checksum = _mix(checksum, _run_lte_sc_fdma_transform_precoding())
    checksum = _mix(checksum, _run_lte_sc_fdma_transform_deprecoding())
    checksum = _mix(checksum, _run_lte_downlink_mcs_profile())
    checksum = _mix(checksum, _run_lte_downlink_mcs_entry())
    checksum = _mix(checksum, _run_lte_downlink_redundancy_version())
    checksum = _mix(checksum, _run_lte_uplink_mcs_entry())
    checksum = _mix(checksum, _run_lte_base_tbs_table_bounds())
    checksum = _mix(checksum, _run_lte_base_transport_block_size())
    checksum = _mix(checksum, _run_lte_downlink_transport_block_size())
    checksum = _mix(checksum, _run_lte_downlink_resource_block_group_size())
    checksum = _mix(checksum, _run_lte_downlink_type0_resource_blocks())
    checksum = _mix(checksum, _run_lte_uplink_encode_riv())
    checksum = _mix(checksum, _run_lte_uplink_decode_riv())
    checksum = _mix(checksum, _run_lte_rsrp())
    checksum = _mix(checksum, _run_lte_rssi())
    checksum = _mix(checksum, _run_lte_rsrq())
    checksum = _mix(checksum, _run_lte_rs_sinr_from_powers())
    checksum = _mix(checksum, _run_lte_rs_sinr())
    keep(checksum)
    print("lte_physical_retained_checksum:", checksum)
