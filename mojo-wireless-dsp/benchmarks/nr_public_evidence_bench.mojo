"""Reachability benchmark for every public ``nr_*`` export.

Each group receives two untimed warmups and seven independent timed samples.
Every family reports median, nearest-rank p95, normalized latency, and a
checksum printed after timing so computed results remain observable.
"""

from std.benchmark import keep
from std.collections import Span
from std.sys.info import align_of
from std.time import global_perf_counter_ns
from wireless_dsp.benchmarking import (
    print_benchmark_metadata,
    print_runtime_buffer_alignment,
    report_timing_samples,
)
from wireless_dsp.core import Complex64
from wireless_dsp.wireless.nr import (
    NRResourceGrid, NRPUSCHConfig, NRPUCCHFormat2Config, NRLDPCProfile,
    NRLDPCSegments, NRLDPCEncodedBlocks,
    NRPRACHFormat, NRPRACHPreamble, NRPRACHOccasion,
    PRACH_FORMAT_A1, PRACH_REGION_FR1, PRACH_SPECTRUM_PAIRED,
    PRACH_SET_UNRESTRICTED, PRACH_SET_RESTRICTED_A,
    PUCCH_GROUP_HOPPING_ENABLE,
    nr_gold_bits, nr_qpsk_sequence, nr_pss, nr_sss,
    nr_pbch_dmrs_c_init, nr_pbch_dmrs, nr_pdsch_scramble, nr_pdsch_dmrs,
    nr_pdsch_descramble_llrs, nr_rate_recover_llrs, nr_transport_crc_width,
    nr_transport_crc, nr_transport_crc_append, nr_transport_crc_check,
    nr_select_base_graph, nr_ldpc_profile, nr_ldpc_filler_mask,
    nr_qc_expand_edges, nr_standard_qc_graph, nr_base_graph_dimensions,
    nr_base_graph_edge_count, nr_base_graph_edges, nr_base_graph_shift,
    nr_lifting_set_index, nr_ldpc_encode_full, nr_ldpc_encode,
    nr_ldpc_syndrome_ok, nr_ldpc_k0, nr_ldpc_rate_match,
    nr_ldpc_rate_recover, nr_ldpc_code_block_output_bits, nr_ldpc_decode,
    nr_ldpc_crc24b, nr_ldpc_crc24b_append, nr_ldpc_crc24b_check,
    nr_ldpc_segment, nr_ldpc_desegment, nr_ldpc_encode_code_blocks,
    nr_ldpc_rate_match_code_blocks, nr_ldpc_rate_recover_code_blocks,
    nr_ldpc_decode_code_blocks, nr_normal_cp_samples, nr_pdsch_dmrs_c_init,
    nr_map_pdsch_comb2, nr_extract_pdsch_comb2, nr_extract_dmrs_comb2,
    nr_ls_channel_estimate_comb2, nr_equalize_pdsch_comb2,
    nr_map_ssb_synchronization, nr_search_pss, nr_detect_sss,
    nr_pdsch_encode_transport_block, nr_pdsch_decode_grid_comb2,
    nr_pusch_scramble, nr_pusch_descramble_llrs,
    nr_pusch_transform_precoding, nr_pusch_transform_deprecoding,
    nr_pusch_dmrs_c_init, nr_pusch_dmrs, nr_prach_root_sequence,
    nr_prach_sequence, nr_prach_unrestricted_cyclic_shift,
    nr_detect_prach_unrestricted, nr_pucch_group_neither,
    nr_pucch_group_sequence_hopping, nr_pucch_cyclic_shift_index,
    nr_pucch_low_papr_sequence_12, nr_pucch_format0_sequence,
    nr_pucch_format1_sequence, nr_pucch_scramble, nr_pucch_format2_modulate,
    nr_pi_over_2_bpsk, nr_pucch_format3_4_modulate,
    nr_pucch_block_spread, nr_pucch_block_despread,
    nr_pucch_format1_data_occ_length, nr_pucch_format1_dmrs_occ_length,
    nr_pucch_format1_occ_phases, nr_pucch_format1_occ,
    nr_pucch_format1_data_occ, nr_pucch_format1_dmrs_occ,
    nr_pucch_format1_apply_occ, nr_pucch_format2_dmrs_c_init,
    nr_pucch_format2_dmrs, nr_pucch_format2_data_re_count,
    nr_pucch_format2_dmrs_re_count, nr_map_pucch_format2,
    nr_extract_pucch_format2_data, nr_extract_pucch_format2_dmrs,
    nr_pucch_format3_4_dmrs_positions, nr_pucch_format3_4_dmrs_re_count,
    nr_pucch_format3_4_data_re_count, nr_map_pucch_format3_4_non_interlaced,
    nr_extract_pucch_format3_4_data_non_interlaced,
    nr_extract_pucch_format3_4_dmrs_non_interlaced,
    nr_prach_format_parameters, nr_prach_logical_root_count,
    nr_prach_logical_root_u, nr_prach_root_sequence_standard,
    nr_prach_sequence_standard, nr_prach_n_cs, nr_prach_d_u,
    nr_prach_restricted_parameters, nr_prach_cyclic_shifts,
    nr_prach_allocate_preambles, nr_prach_preamble_sequence,
    nr_prach_frequency_sequence, nr_prach_normalized_cp_samples,
    nr_prach_normalized_waveform, nr_prach_normalized_composite,
    nr_detect_prach_multi_root,
    nr_prach_representative_occasion, nr_prach_occasion_is_active,
    nr_pbch_build_payload, nr_pbch_payload_interleave,
    nr_pbch_payload_deinterleave, nr_pbch_payload_scramble,
    nr_pbch_payload_descramble, nr_pbch_crc24c, nr_pbch_crc24c_append,
    nr_pbch_crc24c_check, nr_pbch_physical_scramble,
    nr_pbch_physical_descramble_llrs, nr_pbch_encode, nr_pbch_decode,
    nr_pdsch_ptrs_density_from_thresholds, nr_pdsch_ptrs_c_init,
    nr_pdsch_ptrs_time_positions, nr_pdsch_ptrs_k_ref_re,
    nr_pdsch_ptrs_frequency_positions, nr_pdsch_ptrs_sequence,
    nr_map_pdsch_ptrs, nr_extract_pdsch_ptrs,
    nr_ptrs_estimate_common_phase, nr_ptrs_correct_common_phase,
    nr_pusch_allocation_subcarriers, nr_pusch_data_re_count,
    nr_pusch_coded_bit_capacity, nr_pusch_reference_dmrs,
    nr_map_pusch_single_layer, nr_pusch_grid_to_waveform,
    nr_pusch_waveform_to_grid, nr_pusch_encode_transport_block,
    nr_pusch_decode_waveform, nr_uci_crc_length, nr_uci_code_block_count,
    nr_pucch_uci_capacity, nr_uci_encode, nr_uci_decode,
    nr_pucch_format2_coded_bit_capacity, nr_pucch_format2_bits_checksum,
    nr_pucch_format2_reference_dmrs, nr_pucch_format2_waveform_sample_count,
    nr_pucch_format2_grid_to_waveform, nr_pucch_format2_waveform_to_grid,
    nr_pucch_format2_encode, nr_pucch_format2_flat_channel,
    nr_pucch_format2_descramble_llrs, nr_pucch_format2_decode,
)


comptime _WARMUPS = 3
comptime _SAMPLES = 9


def _mix(checksum: UInt64, value: UInt64) -> UInt64:
    return (checksum ^ value) * UInt64(1099511628211)


def _require_repeat(first: UInt64, second: UInt64) raises:
    if first != second:
        raise Error("NR public fixed workload is nondeterministic")
    keep(first)
    keep(second)


def _fingerprint_uint8(values: List[UInt8]) -> UInt64:
    var fingerprint = UInt64(len(values))
    if len(values) > 0:
        fingerprint = _mix(fingerprint, UInt64(values[0]))
        fingerprint = _mix(fingerprint, UInt64(values[len(values) - 1]))
    return fingerprint


def _fingerprint_float64(values: List[Float64]) -> UInt64:
    var fingerprint = UInt64(len(values))
    if len(values) > 0:
        fingerprint = _mix(fingerprint, UInt64(1 if values[0] >= 0.0 else 0))
        fingerprint = _mix(
            fingerprint,
            UInt64(1 if values[len(values) - 1] >= 0.0 else 0),
        )
    return fingerprint


def _fingerprint_int(values: List[Int]) -> UInt64:
    var fingerprint = UInt64(len(values))
    if len(values) > 0:
        fingerprint = _mix(fingerprint, UInt64(values[0] + 4096))
        fingerprint = _mix(
            fingerprint, UInt64(values[len(values) - 1] + 4096)
        )
    return fingerprint


def _fingerprint_complex64(values: List[Complex64]) -> UInt64:
    var fingerprint = UInt64(len(values))
    if len(values) > 0:
        fingerprint = _mix(fingerprint, UInt64(1 if values[0].re >= 0.0 else 0))
        fingerprint = _mix(fingerprint, UInt64(1 if values[0].im >= 0.0 else 0))
        fingerprint = _mix(
            fingerprint,
            UInt64(1 if values[len(values) - 1].re >= 0.0 else 0),
        )
        fingerprint = _mix(
            fingerprint,
            UInt64(1 if values[len(values) - 1].im >= 0.0 else 0),
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
    for i in range(length):
        result.append(UInt8((13 * i + i // 3 + salt) & 1))
    return result^


def _llrs(bits: Span[UInt8, ...]) -> List[Float64]:
    var result = List[Float64](capacity=len(bits))
    for i in range(len(bits)):
        result.append(20.0 if bits[i] == 0 else -20.0)
    return result^


@no_inline
def _bench_nr_gold_bits() raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_gold_bits(UInt32(0x1234567), 64)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _fingerprint_uint8(result)
    return (elapsed, fingerprint)


def _run_nr_gold_bits() raises -> UInt64:
    var first = _bench_nr_gold_bits()
    var second = _bench_nr_gold_bits()
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_gold_bits())
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_gold_bits()
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_gold_bits", samples, checksum)


@no_inline
def _bench_nr_qpsk_sequence() raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_qpsk_sequence(UInt32(0x1234567), 32)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _fingerprint_complex64(result)
    return (elapsed, fingerprint)


def _run_nr_qpsk_sequence() raises -> UInt64:
    var first = _bench_nr_qpsk_sequence()
    var second = _bench_nr_qpsk_sequence()
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_qpsk_sequence())
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_qpsk_sequence()
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_qpsk_sequence", samples, checksum)


@no_inline
def _bench_nr_pss() raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_pss(2)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _fingerprint_float64(result)
    return (elapsed, fingerprint)


def _run_nr_pss() raises -> UInt64:
    var first = _bench_nr_pss()
    var second = _bench_nr_pss()
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_pss())
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_pss()
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_pss", samples, checksum)


@no_inline
def _bench_nr_sss() raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_sss(17, 2)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _fingerprint_float64(result)
    return (elapsed, fingerprint)


def _run_nr_sss() raises -> UInt64:
    var first = _bench_nr_sss()
    var second = _bench_nr_sss()
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_sss())
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_sss()
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_sss", samples, checksum)


@no_inline
def _bench_nr_pbch_dmrs_c_init() raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_pbch_dmrs_c_init(42, 1, 0, 4)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = UInt64(result)
    return (elapsed, fingerprint)


def _run_nr_pbch_dmrs_c_init() raises -> UInt64:
    var first = _bench_nr_pbch_dmrs_c_init()
    var second = _bench_nr_pbch_dmrs_c_init()
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_pbch_dmrs_c_init())
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_pbch_dmrs_c_init()
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_pbch_dmrs_c_init", samples, checksum)


@no_inline
def _bench_nr_pbch_dmrs() raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_pbch_dmrs(42, 1, 0, 4)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _fingerprint_complex64(result)
    return (elapsed, fingerprint)


def _run_nr_pbch_dmrs() raises -> UInt64:
    var first = _bench_nr_pbch_dmrs()
    var second = _bench_nr_pbch_dmrs()
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_pbch_dmrs())
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_pbch_dmrs()
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_pbch_dmrs", samples, checksum)


@no_inline
def _bench_nr_pdsch_scramble(bits: Span[UInt8, ...]) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_pdsch_scramble(bits, 0x1234, 0, 42)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _fingerprint_uint8(result)
    return (elapsed, fingerprint)


def _run_nr_pdsch_scramble() raises -> UInt64:
    var bits = _bits(32, 1)
    var bits_span = Span(bits)
    var first = _bench_nr_pdsch_scramble(bits_span)
    var second = _bench_nr_pdsch_scramble(bits_span)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_pdsch_scramble(bits_span))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_pdsch_scramble(bits_span)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_pdsch_scramble", samples, checksum)


@no_inline
def _bench_nr_pdsch_dmrs() raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_pdsch_dmrs(UInt32(77), 16)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _fingerprint_complex64(result)
    return (elapsed, fingerprint)


def _run_nr_pdsch_dmrs() raises -> UInt64:
    var first = _bench_nr_pdsch_dmrs()
    var second = _bench_nr_pdsch_dmrs()
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_pdsch_dmrs())
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_pdsch_dmrs()
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_pdsch_dmrs", samples, checksum)


@no_inline
def _bench_nr_pdsch_descramble_llrs(llrs: Span[Float64, ...]) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_pdsch_descramble_llrs(llrs, 0x1234, 0, 42)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _fingerprint_float64(result)
    return (elapsed, fingerprint)


def _run_nr_pdsch_descramble_llrs() raises -> UInt64:
    var bits = _bits(32, 1)
    var scrambled = nr_pdsch_scramble(Span(bits), 0x1234, 0, 42)
    var llrs = _llrs(Span(scrambled))
    var llrs_span = Span(llrs)
    var first = _bench_nr_pdsch_descramble_llrs(llrs_span)
    var second = _bench_nr_pdsch_descramble_llrs(llrs_span)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_pdsch_descramble_llrs(llrs_span))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_pdsch_descramble_llrs(llrs_span)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_pdsch_descramble_llrs", samples, checksum)


@no_inline
def _bench_nr_rate_recover_llrs(received: Span[Float64, ...], filler: Span[UInt8, ...]) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_rate_recover_llrs(received, 4, 1, filler)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _fingerprint_float64(result)
    return (elapsed, fingerprint)


def _run_nr_rate_recover_llrs() raises -> UInt64:
    var received: List[Float64] = [20.0, -20.0, 20.0, 20.0, -20.0, 20.0, -20.0, 20.0]
    var filler: List[UInt8] = [0, 1, 0, 0]
    var received_span = Span(received)
    var filler_span = Span(filler)
    var first = _bench_nr_rate_recover_llrs(received_span, filler_span)
    var second = _bench_nr_rate_recover_llrs(received_span, filler_span)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_rate_recover_llrs(received_span, filler_span))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_rate_recover_llrs(received_span, filler_span)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_rate_recover_llrs", samples, checksum)


@no_inline
def _bench_nr_transport_crc_width() raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_transport_crc_width(32)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = UInt64(result)
    return (elapsed, fingerprint)


def _run_nr_transport_crc_width() raises -> UInt64:
    var first = _bench_nr_transport_crc_width()
    var second = _bench_nr_transport_crc_width()
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_transport_crc_width())
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_transport_crc_width()
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_transport_crc_width", samples, checksum)


@no_inline
def _bench_nr_transport_crc(bits: Span[UInt8, ...]) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_transport_crc(bits)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = result
    return (elapsed, fingerprint)


def _run_nr_transport_crc() raises -> UInt64:
    var bits = _bits(32, 1)
    var bits_span = Span(bits)
    var first = _bench_nr_transport_crc(bits_span)
    var second = _bench_nr_transport_crc(bits_span)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_transport_crc(bits_span))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_transport_crc(bits_span)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_transport_crc", samples, checksum)


@no_inline
def _bench_nr_transport_crc_append(bits: Span[UInt8, ...]) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_transport_crc_append(bits)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _fingerprint_uint8(result)
    return (elapsed, fingerprint)


def _run_nr_transport_crc_append() raises -> UInt64:
    var bits = _bits(32, 1)
    var bits_span = Span(bits)
    var first = _bench_nr_transport_crc_append(bits_span)
    var second = _bench_nr_transport_crc_append(bits_span)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_transport_crc_append(bits_span))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_transport_crc_append(bits_span)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_transport_crc_append", samples, checksum)


@no_inline
def _bench_nr_transport_crc_check(codeword: Span[UInt8, ...]) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_transport_crc_check(codeword, 32)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = UInt64(1 if result else 0)
    return (elapsed, fingerprint)


def _run_nr_transport_crc_check() raises -> UInt64:
    var bits = _bits(32, 1)
    var codeword = nr_transport_crc_append(Span(bits))
    var codeword_span = Span(codeword)
    var first = _bench_nr_transport_crc_check(codeword_span)
    var second = _bench_nr_transport_crc_check(codeword_span)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_transport_crc_check(codeword_span))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_transport_crc_check(codeword_span)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_transport_crc_check", samples, checksum)



@no_inline
def _bench_nr_pusch_scramble(bits: Span[UInt8, ...]) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_pusch_scramble(bits, 0x1234, 0, 42)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _fingerprint_uint8(result)
    return (elapsed, fingerprint)


def _run_nr_pusch_scramble() raises -> UInt64:
    var bits = _bits(32, 5)
    var bits_span = Span(bits)
    var first = _bench_nr_pusch_scramble(bits_span)
    var second = _bench_nr_pusch_scramble(bits_span)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_pusch_scramble(bits_span))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_pusch_scramble(bits_span)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_pusch_scramble", samples, checksum)


@no_inline
def _bench_nr_pusch_descramble_llrs(llrs: Span[Float64, ...]) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_pusch_descramble_llrs(llrs, 0x1234, 0, 42)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _fingerprint_float64(result)
    return (elapsed, fingerprint)


def _run_nr_pusch_descramble_llrs() raises -> UInt64:
    var bits = _bits(32, 5)
    var scrambled = nr_pusch_scramble(Span(bits), 0x1234, 0, 42)
    var llrs = _llrs(Span(scrambled))
    var llrs_span = Span(llrs)
    var first = _bench_nr_pusch_descramble_llrs(llrs_span)
    var second = _bench_nr_pusch_descramble_llrs(llrs_span)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_pusch_descramble_llrs(llrs_span))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_pusch_descramble_llrs(llrs_span)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_pusch_descramble_llrs", samples, checksum)


@no_inline
def _bench_nr_pusch_transform_precoding(symbols: Span[Complex64, ...]) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_pusch_transform_precoding(symbols)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _fingerprint_complex64(result)
    return (elapsed, fingerprint)


def _run_nr_pusch_transform_precoding() raises -> UInt64:
    var symbols = List[Complex64](length=12, fill=Complex64(1.0, -0.5))
    var symbols_span = Span(symbols)
    var first = _bench_nr_pusch_transform_precoding(symbols_span)
    var second = _bench_nr_pusch_transform_precoding(symbols_span)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_pusch_transform_precoding(symbols_span))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_pusch_transform_precoding(symbols_span)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_pusch_transform_precoding", samples, checksum)


@no_inline
def _bench_nr_pusch_transform_deprecoding(symbols: Span[Complex64, ...]) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_pusch_transform_deprecoding(symbols)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _fingerprint_complex64(result)
    return (elapsed, fingerprint)


def _run_nr_pusch_transform_deprecoding() raises -> UInt64:
    var source = List[Complex64](length=12, fill=Complex64(1.0, -0.5))
    var symbols = nr_pusch_transform_precoding(Span(source))
    var symbols_span = Span(symbols)
    var first = _bench_nr_pusch_transform_deprecoding(symbols_span)
    var second = _bench_nr_pusch_transform_deprecoding(symbols_span)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_pusch_transform_deprecoding(symbols_span))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_pusch_transform_deprecoding(symbols_span)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_pusch_transform_deprecoding", samples, checksum)


@no_inline
def _bench_nr_pusch_dmrs_c_init() raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_pusch_dmrs_c_init(3, 2, 42, 0)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = UInt64(result)
    return (elapsed, fingerprint)


def _run_nr_pusch_dmrs_c_init() raises -> UInt64:
    var first = _bench_nr_pusch_dmrs_c_init()
    var second = _bench_nr_pusch_dmrs_c_init()
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_pusch_dmrs_c_init())
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_pusch_dmrs_c_init()
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_pusch_dmrs_c_init", samples, checksum)


@no_inline
def _bench_nr_pusch_dmrs() raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_pusch_dmrs(3, 2, 42, 0, 6)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _fingerprint_complex64(result)
    return (elapsed, fingerprint)


def _run_nr_pusch_dmrs() raises -> UInt64:
    var first = _bench_nr_pusch_dmrs()
    var second = _bench_nr_pusch_dmrs()
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_pusch_dmrs())
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_pusch_dmrs()
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_pusch_dmrs", samples, checksum)


@no_inline
def _bench_nr_prach_root_sequence() raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_prach_root_sequence(1, 139)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _fingerprint_complex64(result)
    return (elapsed, fingerprint)


def _run_nr_prach_root_sequence() raises -> UInt64:
    var first = _bench_nr_prach_root_sequence()
    var second = _bench_nr_prach_root_sequence()
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_prach_root_sequence())
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_prach_root_sequence()
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_prach_root_sequence", samples, checksum)


@no_inline
def _bench_nr_prach_sequence() raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_prach_sequence(1, 139, 13)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _fingerprint_complex64(result)
    return (elapsed, fingerprint)


def _run_nr_prach_sequence() raises -> UInt64:
    var first = _bench_nr_prach_sequence()
    var second = _bench_nr_prach_sequence()
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_prach_sequence())
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_prach_sequence()
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_prach_sequence", samples, checksum)


@no_inline
def _bench_nr_prach_unrestricted_cyclic_shift() raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_prach_unrestricted_cyclic_shift(1, 13, 139)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = UInt64(result)
    return (elapsed, fingerprint)


def _run_nr_prach_unrestricted_cyclic_shift() raises -> UInt64:
    var first = _bench_nr_prach_unrestricted_cyclic_shift()
    var second = _bench_nr_prach_unrestricted_cyclic_shift()
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_prach_unrestricted_cyclic_shift())
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_prach_unrestricted_cyclic_shift()
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_prach_unrestricted_cyclic_shift", samples, checksum)


@no_inline
def _bench_nr_detect_prach_unrestricted(prach: Span[Complex64, ...]) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_detect_prach_unrestricted(prach, 1, 13, 4)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = UInt64(result.preamble_index)
    return (elapsed, fingerprint)


def _run_nr_detect_prach_unrestricted() raises -> UInt64:
    var prach = nr_prach_sequence(1, 139, 13)
    var prach_span = Span(prach)
    var first = _bench_nr_detect_prach_unrestricted(prach_span)
    var second = _bench_nr_detect_prach_unrestricted(prach_span)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_detect_prach_unrestricted(prach_span))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_detect_prach_unrestricted(prach_span)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_detect_prach_unrestricted", samples, checksum)


@no_inline
def _bench_nr_uci_crc_length() raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_uci_crc_length(12)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = UInt64(result)
    return (elapsed, fingerprint)


def _run_nr_uci_crc_length() raises -> UInt64:
    var first = _bench_nr_uci_crc_length()
    var second = _bench_nr_uci_crc_length()
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_uci_crc_length())
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_uci_crc_length()
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_uci_crc_length", samples, checksum)


@no_inline
def _bench_nr_uci_code_block_count() raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_uci_code_block_count(12, 32)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = UInt64(result)
    return (elapsed, fingerprint)


def _run_nr_uci_code_block_count() raises -> UInt64:
    var first = _bench_nr_uci_code_block_count()
    var second = _bench_nr_uci_code_block_count()
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_uci_code_block_count())
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_uci_code_block_count()
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_uci_code_block_count", samples, checksum)


@no_inline
def _bench_nr_pucch_uci_capacity() raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_pucch_uci_capacity(2, 1, 1)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = UInt64(result)
    return (elapsed, fingerprint)


def _run_nr_pucch_uci_capacity() raises -> UInt64:
    var first = _bench_nr_pucch_uci_capacity()
    var second = _bench_nr_pucch_uci_capacity()
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_pucch_uci_capacity())
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_pucch_uci_capacity()
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_pucch_uci_capacity", samples, checksum)


@no_inline
def _bench_nr_uci_encode(payload: Span[UInt8, ...]) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_uci_encode(payload, 16)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _mix(UInt64(len(result.bits)), UInt64(result.code_blocks))
    return (elapsed, fingerprint)


def _run_nr_uci_encode() raises -> UInt64:
    var payload = _bits(7, 1)
    var payload_span = Span(payload)
    var first = _bench_nr_uci_encode(payload_span)
    var second = _bench_nr_uci_encode(payload_span)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_uci_encode(payload_span))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_uci_encode(payload_span)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_uci_encode", samples, checksum)


@no_inline
def _bench_nr_uci_decode(llrs: Span[Float64, ...]) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_uci_decode(llrs, 7)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _mix(UInt64(len(result.bits)), UInt64(result.code_blocks))
    return (elapsed, fingerprint)


def _run_nr_uci_decode() raises -> UInt64:
    var payload = _bits(7, 1)
    var encoded = nr_uci_encode(Span(payload), 16)
    var llrs = _llrs(Span(encoded.bits))
    var llrs_span = Span(llrs)
    var first = _bench_nr_uci_decode(llrs_span)
    var second = _bench_nr_uci_decode(llrs_span)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_uci_decode(llrs_span))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_uci_decode(llrs_span)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_uci_decode", samples, checksum)



@no_inline
def _bench_nr_pucch_group_neither() raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_pucch_group_neither(77)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = UInt64(result)
    return (elapsed, fingerprint)


def _run_nr_pucch_group_neither() raises -> UInt64:
    var first = _bench_nr_pucch_group_neither()
    var second = _bench_nr_pucch_group_neither()
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_pucch_group_neither())
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_pucch_group_neither()
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_pucch_group_neither", samples, checksum)


@no_inline
def _bench_nr_pucch_group_sequence_hopping() raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_pucch_group_sequence_hopping(3, 0, 0, 77, PUCCH_GROUP_HOPPING_ENABLE)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _mix(UInt64(result.group), UInt64(result.sequence_number))
    return (elapsed, fingerprint)


def _run_nr_pucch_group_sequence_hopping() raises -> UInt64:
    var first = _bench_nr_pucch_group_sequence_hopping()
    var second = _bench_nr_pucch_group_sequence_hopping()
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_pucch_group_sequence_hopping())
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_pucch_group_sequence_hopping()
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_pucch_group_sequence_hopping", samples, checksum)


@no_inline
def _bench_nr_pucch_cyclic_shift_index() raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_pucch_cyclic_shift_index(3, 2, 1, 2, 77)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = UInt64(result)
    return (elapsed, fingerprint)


def _run_nr_pucch_cyclic_shift_index() raises -> UInt64:
    var first = _bench_nr_pucch_cyclic_shift_index()
    var second = _bench_nr_pucch_cyclic_shift_index()
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_pucch_cyclic_shift_index())
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_pucch_cyclic_shift_index()
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_pucch_cyclic_shift_index", samples, checksum)


@no_inline
def _bench_nr_pucch_low_papr_sequence_12() raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_pucch_low_papr_sequence_12(17, 3)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _fingerprint_complex64(result)
    return (elapsed, fingerprint)


def _run_nr_pucch_low_papr_sequence_12() raises -> UInt64:
    var first = _bench_nr_pucch_low_papr_sequence_12()
    var second = _bench_nr_pucch_low_papr_sequence_12()
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_pucch_low_papr_sequence_12())
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_pucch_low_papr_sequence_12()
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_pucch_low_papr_sequence_12", samples, checksum)


@no_inline
def _bench_nr_pucch_format0_sequence() raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_pucch_format0_sequence(17, 3)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _fingerprint_complex64(result)
    return (elapsed, fingerprint)


def _run_nr_pucch_format0_sequence() raises -> UInt64:
    var first = _bench_nr_pucch_format0_sequence()
    var second = _bench_nr_pucch_format0_sequence()
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_pucch_format0_sequence())
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_pucch_format0_sequence()
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_pucch_format0_sequence", samples, checksum)


@no_inline
def _bench_nr_pucch_format1_sequence(bits: Span[UInt8, ...]) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_pucch_format1_sequence(bits, 17, 3)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _fingerprint_complex64(result)
    return (elapsed, fingerprint)


def _run_nr_pucch_format1_sequence() raises -> UInt64:
    var bits: List[UInt8] = [1, 0]
    var bits_span = Span(bits)
    var first = _bench_nr_pucch_format1_sequence(bits_span)
    var second = _bench_nr_pucch_format1_sequence(bits_span)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_pucch_format1_sequence(bits_span))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_pucch_format1_sequence(bits_span)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_pucch_format1_sequence", samples, checksum)


@no_inline
def _bench_nr_pucch_scramble(bits: Span[UInt8, ...]) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_pucch_scramble(bits, 0x1234, 77)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _fingerprint_uint8(result)
    return (elapsed, fingerprint)


def _run_nr_pucch_scramble() raises -> UInt64:
    var bits = _bits(16, 2)
    var bits_span = Span(bits)
    var first = _bench_nr_pucch_scramble(bits_span)
    var second = _bench_nr_pucch_scramble(bits_span)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_pucch_scramble(bits_span))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_pucch_scramble(bits_span)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_pucch_scramble", samples, checksum)


@no_inline
def _bench_nr_pucch_format2_modulate(bits: Span[UInt8, ...]) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_pucch_format2_modulate(bits, 0x1234, 77)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _fingerprint_complex64(result)
    return (elapsed, fingerprint)


def _run_nr_pucch_format2_modulate() raises -> UInt64:
    var bits = _bits(16, 2)
    var bits_span = Span(bits)
    var first = _bench_nr_pucch_format2_modulate(bits_span)
    var second = _bench_nr_pucch_format2_modulate(bits_span)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_pucch_format2_modulate(bits_span))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_pucch_format2_modulate(bits_span)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_pucch_format2_modulate", samples, checksum)


@no_inline
def _bench_nr_pi_over_2_bpsk(bits: Span[UInt8, ...]) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_pi_over_2_bpsk(bits)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _fingerprint_complex64(result)
    return (elapsed, fingerprint)


def _run_nr_pi_over_2_bpsk() raises -> UInt64:
    var bits = _bits(16, 2)
    var bits_span = Span(bits)
    var first = _bench_nr_pi_over_2_bpsk(bits_span)
    var second = _bench_nr_pi_over_2_bpsk(bits_span)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_pi_over_2_bpsk(bits_span))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_pi_over_2_bpsk(bits_span)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_pi_over_2_bpsk", samples, checksum)


@no_inline
def _bench_nr_pucch_format3_4_modulate(bits: Span[UInt8, ...]) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_pucch_format3_4_modulate(bits, 0x1234, 77)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _fingerprint_complex64(result)
    return (elapsed, fingerprint)


def _run_nr_pucch_format3_4_modulate() raises -> UInt64:
    var bits = _bits(16, 2)
    var bits_span = Span(bits)
    var first = _bench_nr_pucch_format3_4_modulate(bits_span)
    var second = _bench_nr_pucch_format3_4_modulate(bits_span)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_pucch_format3_4_modulate(bits_span))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_pucch_format3_4_modulate(bits_span)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_pucch_format3_4_modulate", samples, checksum)


@no_inline
def _bench_nr_pucch_block_spread(symbols: Span[Complex64, ...]) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_pucch_block_spread(symbols, 2, 1)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _fingerprint_complex64(result)
    return (elapsed, fingerprint)


def _run_nr_pucch_block_spread() raises -> UInt64:
    var bits = _bits(16, 2)
    var symbols = nr_pucch_format3_4_modulate(Span(bits), 0x1234, 77)
    var symbols_span = Span(symbols)
    var first = _bench_nr_pucch_block_spread(symbols_span)
    var second = _bench_nr_pucch_block_spread(symbols_span)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_pucch_block_spread(symbols_span))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_pucch_block_spread(symbols_span)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_pucch_block_spread", samples, checksum)


@no_inline
def _bench_nr_pucch_block_despread(symbols: Span[Complex64, ...]) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_pucch_block_despread(symbols, 2, 1)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _fingerprint_complex64(result)
    return (elapsed, fingerprint)


def _run_nr_pucch_block_despread() raises -> UInt64:
    var bits = _bits(16, 2)
    var modulated = nr_pucch_format3_4_modulate(Span(bits), 0x1234, 77)
    var symbols = nr_pucch_block_spread(Span(modulated), 2, 1)
    var symbols_span = Span(symbols)
    var first = _bench_nr_pucch_block_despread(symbols_span)
    var second = _bench_nr_pucch_block_despread(symbols_span)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_pucch_block_despread(symbols_span))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_pucch_block_despread(symbols_span)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_pucch_block_despread", samples, checksum)


@no_inline
def _bench_nr_pucch_format1_data_occ_length() raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_pucch_format1_data_occ_length(7)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = UInt64(result)
    return (elapsed, fingerprint)


def _run_nr_pucch_format1_data_occ_length() raises -> UInt64:
    var first = _bench_nr_pucch_format1_data_occ_length()
    var second = _bench_nr_pucch_format1_data_occ_length()
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_pucch_format1_data_occ_length())
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_pucch_format1_data_occ_length()
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_pucch_format1_data_occ_length", samples, checksum)


@no_inline
def _bench_nr_pucch_format1_dmrs_occ_length() raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_pucch_format1_dmrs_occ_length(7)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = UInt64(result)
    return (elapsed, fingerprint)


def _run_nr_pucch_format1_dmrs_occ_length() raises -> UInt64:
    var first = _bench_nr_pucch_format1_dmrs_occ_length()
    var second = _bench_nr_pucch_format1_dmrs_occ_length()
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_pucch_format1_dmrs_occ_length())
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_pucch_format1_dmrs_occ_length()
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_pucch_format1_dmrs_occ_length", samples, checksum)


@no_inline
def _bench_nr_pucch_format1_occ_phases() raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_pucch_format1_occ_phases(3, 1)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _fingerprint_int(result)
    return (elapsed, fingerprint)


def _run_nr_pucch_format1_occ_phases() raises -> UInt64:
    var first = _bench_nr_pucch_format1_occ_phases()
    var second = _bench_nr_pucch_format1_occ_phases()
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_pucch_format1_occ_phases())
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_pucch_format1_occ_phases()
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_pucch_format1_occ_phases", samples, checksum)


@no_inline
def _bench_nr_pucch_format1_occ() raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_pucch_format1_occ(3, 1)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _fingerprint_complex64(result)
    return (elapsed, fingerprint)


def _run_nr_pucch_format1_occ() raises -> UInt64:
    var first = _bench_nr_pucch_format1_occ()
    var second = _bench_nr_pucch_format1_occ()
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_pucch_format1_occ())
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_pucch_format1_occ()
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_pucch_format1_occ", samples, checksum)


@no_inline
def _bench_nr_pucch_format1_data_occ() raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_pucch_format1_data_occ(7, 1)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _fingerprint_complex64(result)
    return (elapsed, fingerprint)


def _run_nr_pucch_format1_data_occ() raises -> UInt64:
    var first = _bench_nr_pucch_format1_data_occ()
    var second = _bench_nr_pucch_format1_data_occ()
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_pucch_format1_data_occ())
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_pucch_format1_data_occ()
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_pucch_format1_data_occ", samples, checksum)


@no_inline
def _bench_nr_pucch_format1_dmrs_occ() raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_pucch_format1_dmrs_occ(7, 1)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _fingerprint_complex64(result)
    return (elapsed, fingerprint)


def _run_nr_pucch_format1_dmrs_occ() raises -> UInt64:
    var first = _bench_nr_pucch_format1_dmrs_occ()
    var second = _bench_nr_pucch_format1_dmrs_occ()
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_pucch_format1_dmrs_occ())
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_pucch_format1_dmrs_occ()
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_pucch_format1_dmrs_occ", samples, checksum)


@no_inline
def _bench_nr_pucch_format1_apply_occ(sequence: Span[Complex64, ...], occ: Span[Complex64, ...]) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_pucch_format1_apply_occ(sequence, occ)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _fingerprint_complex64(result)
    return (elapsed, fingerprint)


def _run_nr_pucch_format1_apply_occ() raises -> UInt64:
    var bits: List[UInt8] = [1, 0]
    var sequence = nr_pucch_format1_sequence(Span(bits), 17, 3)
    var occ = nr_pucch_format1_occ(3, 1)
    var sequence_span = Span(sequence)
    var occ_span = Span(occ)
    var first = _bench_nr_pucch_format1_apply_occ(sequence_span, occ_span)
    var second = _bench_nr_pucch_format1_apply_occ(sequence_span, occ_span)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_pucch_format1_apply_occ(sequence_span, occ_span))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_pucch_format1_apply_occ(sequence_span, occ_span)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_pucch_format1_apply_occ", samples, checksum)


@no_inline
def _bench_nr_pucch_format2_dmrs_c_init() raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_pucch_format2_dmrs_c_init(3, 2, 77)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = UInt64(result)
    return (elapsed, fingerprint)


def _run_nr_pucch_format2_dmrs_c_init() raises -> UInt64:
    var first = _bench_nr_pucch_format2_dmrs_c_init()
    var second = _bench_nr_pucch_format2_dmrs_c_init()
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_pucch_format2_dmrs_c_init())
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_pucch_format2_dmrs_c_init()
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_pucch_format2_dmrs_c_init", samples, checksum)


@no_inline
def _bench_nr_pucch_format2_dmrs() raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_pucch_format2_dmrs(3, 2, 77, 1)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _fingerprint_complex64(result)
    return (elapsed, fingerprint)


def _run_nr_pucch_format2_dmrs() raises -> UInt64:
    var first = _bench_nr_pucch_format2_dmrs()
    var second = _bench_nr_pucch_format2_dmrs()
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_pucch_format2_dmrs())
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_pucch_format2_dmrs()
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_pucch_format2_dmrs", samples, checksum)


@no_inline
def _bench_nr_pucch_format2_data_re_count() raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_pucch_format2_data_re_count(1, 1)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = UInt64(result)
    return (elapsed, fingerprint)


def _run_nr_pucch_format2_data_re_count() raises -> UInt64:
    var first = _bench_nr_pucch_format2_data_re_count()
    var second = _bench_nr_pucch_format2_data_re_count()
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_pucch_format2_data_re_count())
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_pucch_format2_data_re_count()
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_pucch_format2_data_re_count", samples, checksum)


@no_inline
def _bench_nr_pucch_format2_dmrs_re_count() raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_pucch_format2_dmrs_re_count(1, 1)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = UInt64(result)
    return (elapsed, fingerprint)


def _run_nr_pucch_format2_dmrs_re_count() raises -> UInt64:
    var first = _bench_nr_pucch_format2_dmrs_re_count()
    var second = _bench_nr_pucch_format2_dmrs_re_count()
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_pucch_format2_dmrs_re_count())
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_pucch_format2_dmrs_re_count()
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_pucch_format2_dmrs_re_count", samples, checksum)


@no_inline
def _bench_nr_extract_pucch_format2_data(grid: NRResourceGrid) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_extract_pucch_format2_data(grid, 2, 12, 1, 1)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _fingerprint_complex64(result)
    return (elapsed, fingerprint)


def _run_nr_extract_pucch_format2_data() raises -> UInt64:
    var bits = _bits(16, 2)
    var data = nr_pucch_format2_modulate(Span(bits), 0x1234, 77)
    var dmrs = nr_pucch_format2_dmrs(3, 2, 77, 1)
    var grid = NRResourceGrid(14, 64)
    nr_map_pucch_format2(grid, 2, 12, 1, 1, Span(data), Span(dmrs))
    var first = _bench_nr_extract_pucch_format2_data(grid)
    var second = _bench_nr_extract_pucch_format2_data(grid)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_extract_pucch_format2_data(grid))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_extract_pucch_format2_data(grid)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_extract_pucch_format2_data", samples, checksum)


@no_inline
def _bench_nr_extract_pucch_format2_dmrs(grid: NRResourceGrid) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_extract_pucch_format2_dmrs(grid, 2, 12, 1, 1)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _fingerprint_complex64(result)
    return (elapsed, fingerprint)


def _run_nr_extract_pucch_format2_dmrs() raises -> UInt64:
    var bits = _bits(16, 2)
    var data = nr_pucch_format2_modulate(Span(bits), 0x1234, 77)
    var dmrs = nr_pucch_format2_dmrs(3, 2, 77, 1)
    var grid = NRResourceGrid(14, 64)
    nr_map_pucch_format2(grid, 2, 12, 1, 1, Span(data), Span(dmrs))
    var first = _bench_nr_extract_pucch_format2_dmrs(grid)
    var second = _bench_nr_extract_pucch_format2_dmrs(grid)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_extract_pucch_format2_dmrs(grid))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_extract_pucch_format2_dmrs(grid)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_extract_pucch_format2_dmrs", samples, checksum)


@no_inline
def _bench_nr_pucch_format3_4_dmrs_positions() raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_pucch_format3_4_dmrs_positions(4)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _fingerprint_int(result)
    return (elapsed, fingerprint)


def _run_nr_pucch_format3_4_dmrs_positions() raises -> UInt64:
    var first = _bench_nr_pucch_format3_4_dmrs_positions()
    var second = _bench_nr_pucch_format3_4_dmrs_positions()
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_pucch_format3_4_dmrs_positions())
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_pucch_format3_4_dmrs_positions()
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_pucch_format3_4_dmrs_positions", samples, checksum)


@no_inline
def _bench_nr_pucch_format3_4_dmrs_re_count() raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_pucch_format3_4_dmrs_re_count(4, 1)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = UInt64(result)
    return (elapsed, fingerprint)


def _run_nr_pucch_format3_4_dmrs_re_count() raises -> UInt64:
    var first = _bench_nr_pucch_format3_4_dmrs_re_count()
    var second = _bench_nr_pucch_format3_4_dmrs_re_count()
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_pucch_format3_4_dmrs_re_count())
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_pucch_format3_4_dmrs_re_count()
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_pucch_format3_4_dmrs_re_count", samples, checksum)


@no_inline
def _bench_nr_pucch_format3_4_data_re_count() raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_pucch_format3_4_data_re_count(4, 1)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = UInt64(result)
    return (elapsed, fingerprint)


def _run_nr_pucch_format3_4_data_re_count() raises -> UInt64:
    var first = _bench_nr_pucch_format3_4_data_re_count()
    var second = _bench_nr_pucch_format3_4_data_re_count()
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_pucch_format3_4_data_re_count())
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_pucch_format3_4_data_re_count()
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_pucch_format3_4_data_re_count", samples, checksum)


@no_inline
def _bench_nr_extract_pucch_format3_4_data_non_interlaced(grid: NRResourceGrid) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_extract_pucch_format3_4_data_non_interlaced(grid, 1, 12, 1, 4)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _fingerprint_complex64(result)
    return (elapsed, fingerprint)


def _run_nr_extract_pucch_format3_4_data_non_interlaced() raises -> UInt64:
    var data_count = nr_pucch_format3_4_data_re_count(4, 1)
    var dmrs_count = nr_pucch_format3_4_dmrs_re_count(4, 1)
    var data = List[Complex64](length=data_count, fill=Complex64(1.0))
    var dmrs = List[Complex64](length=dmrs_count, fill=Complex64(0.0, 1.0))
    var grid = NRResourceGrid(14, 64)
    nr_map_pucch_format3_4_non_interlaced(grid, 1, 12, 1, 4, Span(data), Span(dmrs))
    var first = _bench_nr_extract_pucch_format3_4_data_non_interlaced(grid)
    var second = _bench_nr_extract_pucch_format3_4_data_non_interlaced(grid)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_extract_pucch_format3_4_data_non_interlaced(grid))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_extract_pucch_format3_4_data_non_interlaced(grid)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_extract_pucch_format3_4_data_non_interlaced", samples, checksum)


@no_inline
def _bench_nr_extract_pucch_format3_4_dmrs_non_interlaced(grid: NRResourceGrid) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_extract_pucch_format3_4_dmrs_non_interlaced(grid, 1, 12, 1, 4)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _fingerprint_complex64(result)
    return (elapsed, fingerprint)


def _run_nr_extract_pucch_format3_4_dmrs_non_interlaced() raises -> UInt64:
    var data_count = nr_pucch_format3_4_data_re_count(4, 1)
    var dmrs_count = nr_pucch_format3_4_dmrs_re_count(4, 1)
    var data = List[Complex64](length=data_count, fill=Complex64(1.0))
    var dmrs = List[Complex64](length=dmrs_count, fill=Complex64(0.0, 1.0))
    var grid = NRResourceGrid(14, 64)
    nr_map_pucch_format3_4_non_interlaced(grid, 1, 12, 1, 4, Span(data), Span(dmrs))
    var first = _bench_nr_extract_pucch_format3_4_dmrs_non_interlaced(grid)
    var second = _bench_nr_extract_pucch_format3_4_dmrs_non_interlaced(grid)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_extract_pucch_format3_4_dmrs_non_interlaced(grid))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_extract_pucch_format3_4_dmrs_non_interlaced(grid)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_extract_pucch_format3_4_dmrs_non_interlaced", samples, checksum)



@no_inline
def _bench_nr_map_pucch_format2(
    mut grid: NRResourceGrid,
    data: Span[Complex64, ...],
    dmrs: Span[Complex64, ...],
) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    nr_map_pucch_format2(grid, 2, 12, 1, 1, data, dmrs)
    var elapsed = global_perf_counter_ns() - start
    var mapped = grid[2, 12]
    var fingerprint = _mix(
        UInt64(len(grid.values)),
        UInt64(1 if mapped.re >= 0.0 else 0),
    )
    keep(mapped)
    return (elapsed, fingerprint)


def _run_nr_map_pucch_format2() raises -> UInt64:
    var bits = _bits(16, 2)
    var data = nr_pucch_format2_modulate(Span(bits), 0x1234, 77)
    var dmrs = nr_pucch_format2_dmrs(3, 2, 77, 1)
    var data_span = Span(data)
    var dmrs_span = Span(dmrs)
    var grid = NRResourceGrid(14, 64)
    var first = _bench_nr_map_pucch_format2(grid, data_span, dmrs_span)
    var second = _bench_nr_map_pucch_format2(grid, data_span, dmrs_span)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_map_pucch_format2(grid, data_span, dmrs_span))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_map_pucch_format2(
            grid, data_span, dmrs_span
        )
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    keep(grid)
    return _finish_sample("nr_map_pucch_format2", samples, checksum)


@no_inline
def _bench_nr_map_pucch_format3_4_non_interlaced(
    mut grid: NRResourceGrid,
    data: Span[Complex64, ...],
    dmrs: Span[Complex64, ...],
) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    nr_map_pucch_format3_4_non_interlaced(
        grid, 1, 12, 1, 4, data, dmrs
    )
    var elapsed = global_perf_counter_ns() - start
    var mapped = grid[1, 12]
    var fingerprint = _mix(
        UInt64(len(grid.values)),
        UInt64(1 if mapped.re >= 0.0 else 0),
    )
    keep(mapped)
    return (elapsed, fingerprint)


def _run_nr_map_pucch_format3_4_non_interlaced() raises -> UInt64:
    var data_count = nr_pucch_format3_4_data_re_count(4, 1)
    var dmrs_count = nr_pucch_format3_4_dmrs_re_count(4, 1)
    var data = List[Complex64](
        length=data_count, fill=Complex64(1.0)
    )
    var dmrs = List[Complex64](
        length=dmrs_count, fill=Complex64(0.0, 1.0)
    )
    var data_span = Span(data)
    var dmrs_span = Span(dmrs)
    var grid = NRResourceGrid(14, 64)
    var first = _bench_nr_map_pucch_format3_4_non_interlaced(
        grid, data_span, dmrs_span
    )
    var second = _bench_nr_map_pucch_format3_4_non_interlaced(
        grid, data_span, dmrs_span
    )
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(
            _bench_nr_map_pucch_format3_4_non_interlaced(
                grid, data_span, dmrs_span
            )
        )
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_map_pucch_format3_4_non_interlaced(
            grid, data_span, dmrs_span
        )
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    keep(grid)
    return _finish_sample(
        "nr_map_pucch_format3_4_non_interlaced", samples, checksum
    )



@no_inline
def _bench_nr_prach_format_parameters() raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_prach_format_parameters(PRACH_FORMAT_A1, numerology=0, sequence_length=139)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _mix(UInt64(result.sequence_length), UInt64(result.repetitions))
    return (elapsed, fingerprint)


def _run_nr_prach_format_parameters() raises -> UInt64:
    var first = _bench_nr_prach_format_parameters()
    var second = _bench_nr_prach_format_parameters()
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_prach_format_parameters())
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_prach_format_parameters()
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_prach_format_parameters", samples, checksum)


@no_inline
def _bench_nr_prach_logical_root_count() raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_prach_logical_root_count(139)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = UInt64(result)
    return (elapsed, fingerprint)


def _run_nr_prach_logical_root_count() raises -> UInt64:
    var first = _bench_nr_prach_logical_root_count()
    var second = _bench_nr_prach_logical_root_count()
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_prach_logical_root_count())
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_prach_logical_root_count()
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_prach_logical_root_count", samples, checksum)


@no_inline
def _bench_nr_prach_logical_root_u() raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_prach_logical_root_u(0, 139)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = UInt64(result)
    return (elapsed, fingerprint)


def _run_nr_prach_logical_root_u() raises -> UInt64:
    var first = _bench_nr_prach_logical_root_u()
    var second = _bench_nr_prach_logical_root_u()
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_prach_logical_root_u())
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_prach_logical_root_u()
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_prach_logical_root_u", samples, checksum)


@no_inline
def _bench_nr_prach_root_sequence_standard() raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_prach_root_sequence_standard(1, 139)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _fingerprint_complex64(result)
    return (elapsed, fingerprint)


def _run_nr_prach_root_sequence_standard() raises -> UInt64:
    var first = _bench_nr_prach_root_sequence_standard()
    var second = _bench_nr_prach_root_sequence_standard()
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_prach_root_sequence_standard())
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_prach_root_sequence_standard()
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_prach_root_sequence_standard", samples, checksum)


@no_inline
def _bench_nr_prach_sequence_standard() raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_prach_sequence_standard(1, 139, 2)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _fingerprint_complex64(result)
    return (elapsed, fingerprint)


def _run_nr_prach_sequence_standard() raises -> UInt64:
    var first = _bench_nr_prach_sequence_standard()
    var second = _bench_nr_prach_sequence_standard()
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_prach_sequence_standard())
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_prach_sequence_standard()
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_prach_sequence_standard", samples, checksum)


@no_inline
def _bench_nr_prach_n_cs() raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_prach_n_cs(1, 139, 15000)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = UInt64(result)
    return (elapsed, fingerprint)


def _run_nr_prach_n_cs() raises -> UInt64:
    var first = _bench_nr_prach_n_cs()
    var second = _bench_nr_prach_n_cs()
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_prach_n_cs())
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_prach_n_cs()
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_prach_n_cs", samples, checksum)


@no_inline
def _bench_nr_prach_d_u() raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_prach_d_u(1, 139)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = UInt64(result)
    return (elapsed, fingerprint)


def _run_nr_prach_d_u() raises -> UInt64:
    var first = _bench_nr_prach_d_u()
    var second = _bench_nr_prach_d_u()
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_prach_d_u())
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_prach_d_u()
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_prach_d_u", samples, checksum)


@no_inline
def _bench_nr_prach_restricted_parameters() raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_prach_restricted_parameters(129, 839, 13, PRACH_SET_RESTRICTED_A)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _mix(UInt64(result.d_u), UInt64(result.count()))
    return (elapsed, fingerprint)


def _run_nr_prach_restricted_parameters() raises -> UInt64:
    var first = _bench_nr_prach_restricted_parameters()
    var second = _bench_nr_prach_restricted_parameters()
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_prach_restricted_parameters())
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_prach_restricted_parameters()
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_prach_restricted_parameters", samples, checksum)


@no_inline
def _bench_nr_prach_cyclic_shifts() raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_prach_cyclic_shifts(1, 139, 13, PRACH_SET_UNRESTRICTED)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _fingerprint_int(result)
    return (elapsed, fingerprint)


def _run_nr_prach_cyclic_shifts() raises -> UInt64:
    var first = _bench_nr_prach_cyclic_shifts()
    var second = _bench_nr_prach_cyclic_shifts()
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_prach_cyclic_shifts())
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_prach_cyclic_shifts()
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_prach_cyclic_shifts", samples, checksum)


@no_inline
def _bench_nr_prach_allocate_preambles() raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_prach_allocate_preambles(0, 139, 13, PRACH_SET_UNRESTRICTED, 4)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _mix(UInt64(len(result)), UInt64(result[0].root_u))
    return (elapsed, fingerprint)


def _run_nr_prach_allocate_preambles() raises -> UInt64:
    var first = _bench_nr_prach_allocate_preambles()
    var second = _bench_nr_prach_allocate_preambles()
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_prach_allocate_preambles())
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_prach_allocate_preambles()
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_prach_allocate_preambles", samples, checksum)


@no_inline
def _bench_nr_prach_preamble_sequence(allocation: NRPRACHPreamble) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_prach_preamble_sequence(allocation, 139)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _fingerprint_complex64(result)
    return (elapsed, fingerprint)


def _run_nr_prach_preamble_sequence() raises -> UInt64:
    var allocations = nr_prach_allocate_preambles(0, 139, 13, PRACH_SET_UNRESTRICTED, 4)
    var allocation = allocations[0]
    var first = _bench_nr_prach_preamble_sequence(allocation)
    var second = _bench_nr_prach_preamble_sequence(allocation)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_prach_preamble_sequence(allocation))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_prach_preamble_sequence(allocation)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_prach_preamble_sequence", samples, checksum)


@no_inline
def _bench_nr_prach_frequency_sequence(sequence: Span[Complex64, ...]) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_prach_frequency_sequence(sequence)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _fingerprint_complex64(result)
    return (elapsed, fingerprint)


def _run_nr_prach_frequency_sequence() raises -> UInt64:
    var sequence = nr_prach_sequence_standard(1, 139, 2)
    var sequence_span = Span(sequence)
    var first = _bench_nr_prach_frequency_sequence(sequence_span)
    var second = _bench_nr_prach_frequency_sequence(sequence_span)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_prach_frequency_sequence(sequence_span))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_prach_frequency_sequence(sequence_span)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_prach_frequency_sequence", samples, checksum)


@no_inline
def _bench_nr_prach_normalized_cp_samples(parameters: NRPRACHFormat) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_prach_normalized_cp_samples(parameters)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = UInt64(result)
    return (elapsed, fingerprint)


def _run_nr_prach_normalized_cp_samples() raises -> UInt64:
    var parameters = nr_prach_format_parameters(PRACH_FORMAT_A1, numerology=0, sequence_length=139)
    var first = _bench_nr_prach_normalized_cp_samples(parameters)
    var second = _bench_nr_prach_normalized_cp_samples(parameters)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_prach_normalized_cp_samples(parameters))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_prach_normalized_cp_samples(parameters)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_prach_normalized_cp_samples", samples, checksum)


@no_inline
def _bench_nr_prach_normalized_waveform(sequence: Span[Complex64, ...], parameters: NRPRACHFormat) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_prach_normalized_waveform(sequence, parameters)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _fingerprint_complex64(result)
    return (elapsed, fingerprint)


def _run_nr_prach_normalized_waveform() raises -> UInt64:
    var parameters = nr_prach_format_parameters(PRACH_FORMAT_A1, numerology=0, sequence_length=139)
    var sequence = nr_prach_sequence_standard(1, 139, 2)
    var sequence_span = Span(sequence)
    var first = _bench_nr_prach_normalized_waveform(sequence_span, parameters)
    var second = _bench_nr_prach_normalized_waveform(sequence_span, parameters)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_prach_normalized_waveform(sequence_span, parameters))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_prach_normalized_waveform(sequence_span, parameters)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_prach_normalized_waveform", samples, checksum)


@no_inline
def _bench_nr_prach_normalized_composite(parameters: NRPRACHFormat) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_prach_normalized_composite(parameters, 0, 13, PRACH_SET_UNRESTRICTED, 0, preamble_count=4)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _mix(UInt64(len(result.normalized_waveform)), UInt64(result.detection.preamble_index))
    return (elapsed, fingerprint)


def _run_nr_prach_normalized_composite() raises -> UInt64:
    var parameters = nr_prach_format_parameters(PRACH_FORMAT_A1, numerology=0, sequence_length=139)
    var first = _bench_nr_prach_normalized_composite(parameters)
    var second = _bench_nr_prach_normalized_composite(parameters)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_prach_normalized_composite(parameters))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_prach_normalized_composite(parameters)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_prach_normalized_composite", samples, checksum)


@no_inline
def _bench_nr_detect_prach_multi_root(received: Span[Complex64, ...]) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_detect_prach_multi_root(received, 0, 13, PRACH_SET_UNRESTRICTED, 4)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _mix(UInt64(result.preamble_index), UInt64(result.root_u))
    return (elapsed, fingerprint)


def _run_nr_detect_prach_multi_root() raises -> UInt64:
    var allocations = nr_prach_allocate_preambles(0, 139, 13, PRACH_SET_UNRESTRICTED, 4)
    var received = nr_prach_preamble_sequence(allocations[0], 139)
    var received_span = Span(received)
    var first = _bench_nr_detect_prach_multi_root(received_span)
    var second = _bench_nr_detect_prach_multi_root(received_span)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_detect_prach_multi_root(received_span))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_detect_prach_multi_root(received_span)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_detect_prach_multi_root", samples, checksum)


@no_inline
def _bench_nr_prach_representative_occasion() raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_prach_representative_occasion(PRACH_REGION_FR1, PRACH_SPECTRUM_PAIRED, 0)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _mix(UInt64(result.configuration_index), UInt64(result.frame_period))
    return (elapsed, fingerprint)


def _run_nr_prach_representative_occasion() raises -> UInt64:
    var first = _bench_nr_prach_representative_occasion()
    var second = _bench_nr_prach_representative_occasion()
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_prach_representative_occasion())
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_prach_representative_occasion()
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_prach_representative_occasion", samples, checksum)


@no_inline
def _bench_nr_prach_occasion_is_active(occasion: NRPRACHOccasion) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_prach_occasion_is_active(occasion, 1, 1)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = UInt64(1 if result else 0)
    return (elapsed, fingerprint)


def _run_nr_prach_occasion_is_active() raises -> UInt64:
    var occasion = nr_prach_representative_occasion(PRACH_REGION_FR1, PRACH_SPECTRUM_PAIRED, 0)
    var first = _bench_nr_prach_occasion_is_active(occasion)
    var second = _bench_nr_prach_occasion_is_active(occasion)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_prach_occasion_is_active(occasion))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_prach_occasion_is_active(occasion)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_prach_occasion_is_active", samples, checksum)



@no_inline
def _bench_nr_pusch_allocation_subcarriers(config: NRPUSCHConfig) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_pusch_allocation_subcarriers(config)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = UInt64(result)
    return (elapsed, fingerprint)


def _run_nr_pusch_allocation_subcarriers() raises -> UInt64:
    var config = NRPUSCHConfig(64, 8, 5, 2, 8, 2, 3, 42, 0, 0x1234)
    var first = _bench_nr_pusch_allocation_subcarriers(config)
    var second = _bench_nr_pusch_allocation_subcarriers(config)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_pusch_allocation_subcarriers(config))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_pusch_allocation_subcarriers(config)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_pusch_allocation_subcarriers", samples, checksum)


@no_inline
def _bench_nr_pusch_data_re_count(config: NRPUSCHConfig) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_pusch_data_re_count(config)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = UInt64(result)
    return (elapsed, fingerprint)


def _run_nr_pusch_data_re_count() raises -> UInt64:
    var config = NRPUSCHConfig(64, 8, 5, 2, 8, 2, 3, 42, 0, 0x1234)
    var first = _bench_nr_pusch_data_re_count(config)
    var second = _bench_nr_pusch_data_re_count(config)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_pusch_data_re_count(config))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_pusch_data_re_count(config)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_pusch_data_re_count", samples, checksum)


@no_inline
def _bench_nr_pusch_coded_bit_capacity(config: NRPUSCHConfig) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_pusch_coded_bit_capacity(config, 2)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = UInt64(result)
    return (elapsed, fingerprint)


def _run_nr_pusch_coded_bit_capacity() raises -> UInt64:
    var config = NRPUSCHConfig(64, 8, 5, 2, 8, 2, 3, 42, 0, 0x1234)
    var first = _bench_nr_pusch_coded_bit_capacity(config)
    var second = _bench_nr_pusch_coded_bit_capacity(config)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_pusch_coded_bit_capacity(config))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_pusch_coded_bit_capacity(config)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_pusch_coded_bit_capacity", samples, checksum)


@no_inline
def _bench_nr_pusch_reference_dmrs(config: NRPUSCHConfig) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_pusch_reference_dmrs(config)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _fingerprint_complex64(result)
    return (elapsed, fingerprint)


def _run_nr_pusch_reference_dmrs() raises -> UInt64:
    var config = NRPUSCHConfig(64, 8, 5, 2, 8, 2, 3, 42, 0, 0x1234)
    var first = _bench_nr_pusch_reference_dmrs(config)
    var second = _bench_nr_pusch_reference_dmrs(config)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_pusch_reference_dmrs(config))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_pusch_reference_dmrs(config)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_pusch_reference_dmrs", samples, checksum)


@no_inline
def _bench_nr_map_pusch_single_layer(config: NRPUSCHConfig, data: Span[Complex64, ...], dmrs: Span[Complex64, ...]) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_map_pusch_single_layer(config, data, dmrs)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _mix(UInt64(result.symbol_count), UInt64(len(result.values)))
    return (elapsed, fingerprint)


def _run_nr_map_pusch_single_layer() raises -> UInt64:
    var config = NRPUSCHConfig(64, 8, 5, 2, 8, 2, 3, 42, 0, 0x1234)
    var data = List[Complex64](length=nr_pusch_data_re_count(config), fill=Complex64(1.0))
    var dmrs = nr_pusch_reference_dmrs(config)
    var data_span = Span(data)
    var dmrs_span = Span(dmrs)
    var first = _bench_nr_map_pusch_single_layer(config, data_span, dmrs_span)
    var second = _bench_nr_map_pusch_single_layer(config, data_span, dmrs_span)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_map_pusch_single_layer(config, data_span, dmrs_span))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_map_pusch_single_layer(config, data_span, dmrs_span)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_map_pusch_single_layer", samples, checksum)


@no_inline
def _bench_nr_pusch_grid_to_waveform(config: NRPUSCHConfig, grid: NRResourceGrid) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_pusch_grid_to_waveform(config, grid)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _fingerprint_complex64(result)
    return (elapsed, fingerprint)


def _run_nr_pusch_grid_to_waveform() raises -> UInt64:
    var config = NRPUSCHConfig(64, 8, 5, 2, 8, 2, 3, 42, 0, 0x1234)
    var data = List[Complex64](length=nr_pusch_data_re_count(config), fill=Complex64(1.0))
    var dmrs = nr_pusch_reference_dmrs(config)
    var grid = nr_map_pusch_single_layer(config, Span(data), Span(dmrs))
    var first = _bench_nr_pusch_grid_to_waveform(config, grid)
    var second = _bench_nr_pusch_grid_to_waveform(config, grid)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_pusch_grid_to_waveform(config, grid))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_pusch_grid_to_waveform(config, grid)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_pusch_grid_to_waveform", samples, checksum)


@no_inline
def _bench_nr_pusch_waveform_to_grid(config: NRPUSCHConfig, waveform: Span[Complex64, ...]) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_pusch_waveform_to_grid(config, waveform)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _mix(UInt64(result.symbol_count), UInt64(len(result.values)))
    return (elapsed, fingerprint)


def _run_nr_pusch_waveform_to_grid() raises -> UInt64:
    var config = NRPUSCHConfig(64, 8, 5, 2, 8, 2, 3, 42, 0, 0x1234)
    var data = List[Complex64](length=nr_pusch_data_re_count(config), fill=Complex64(1.0))
    var dmrs = nr_pusch_reference_dmrs(config)
    var grid = nr_map_pusch_single_layer(config, Span(data), Span(dmrs))
    var waveform = nr_pusch_grid_to_waveform(config, grid)
    var waveform_span = Span(waveform)
    var first = _bench_nr_pusch_waveform_to_grid(config, waveform_span)
    var second = _bench_nr_pusch_waveform_to_grid(config, waveform_span)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_pusch_waveform_to_grid(config, waveform_span))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_pusch_waveform_to_grid(config, waveform_span)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_pusch_waveform_to_grid", samples, checksum)


@no_inline
def _bench_nr_pusch_encode_transport_block(payload: Span[UInt8, ...], config: NRPUSCHConfig) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_pusch_encode_transport_block(payload, 0.5, 2, 0, config)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _mix(UInt64(len(result.waveform)), UInt64(len(result.encoded_null_mask)))
    return (elapsed, fingerprint)


def _run_nr_pusch_encode_transport_block() raises -> UInt64:
    var config = NRPUSCHConfig(64, 8, 5, 2, 8, 2, 3, 42, 0, 0x1234)
    var payload = _bits(32, 3)
    var payload_span = Span(payload)
    var first = _bench_nr_pusch_encode_transport_block(payload_span, config)
    var second = _bench_nr_pusch_encode_transport_block(payload_span, config)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_pusch_encode_transport_block(payload_span, config))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_pusch_encode_transport_block(payload_span, config)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_pusch_encode_transport_block", samples, checksum)


@no_inline
def _bench_nr_pusch_decode_waveform(waveform: Span[Complex64, ...], config: NRPUSCHConfig, null_mask: Span[UInt8, ...], profile: NRLDPCProfile) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_pusch_decode_waveform(waveform, config, null_mask, profile, 32, 2, 0, 0.01)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _mix(
        UInt64(len(result.payload)),
        UInt64(1 if result.transport_crc_ok else 0),
    )
    return (elapsed, fingerprint)


def _run_nr_pusch_decode_waveform() raises -> UInt64:
    var config = NRPUSCHConfig(64, 8, 5, 2, 8, 2, 3, 42, 0, 0x1234)
    var payload = _bits(32, 3)
    var tx = nr_pusch_encode_transport_block(Span(payload), 0.5, 2, 0, config)
    var waveform_span = Span(tx.waveform)
    var null_mask_span = Span(tx.encoded_null_mask)
    var profile = nr_ldpc_profile(32, 0.5)
    var first = _bench_nr_pusch_decode_waveform(waveform_span, config, null_mask_span, profile)
    var second = _bench_nr_pusch_decode_waveform(waveform_span, config, null_mask_span, profile)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_pusch_decode_waveform(waveform_span, config, null_mask_span, profile))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_pusch_decode_waveform(waveform_span, config, null_mask_span, profile)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_pusch_decode_waveform", samples, checksum)


@no_inline
def _bench_nr_pucch_format2_coded_bit_capacity(config: NRPUCCHFormat2Config) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_pucch_format2_coded_bit_capacity(config)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = UInt64(result)
    return (elapsed, fingerprint)


def _run_nr_pucch_format2_coded_bit_capacity() raises -> UInt64:
    var config = NRPUCCHFormat2Config(128, 0, 7, 9, 1, 24, 73, 321, 0x1234)
    var first = _bench_nr_pucch_format2_coded_bit_capacity(config)
    var second = _bench_nr_pucch_format2_coded_bit_capacity(config)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_pucch_format2_coded_bit_capacity(config))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_pucch_format2_coded_bit_capacity(config)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_pucch_format2_coded_bit_capacity", samples, checksum)


@no_inline
def _bench_nr_pucch_format2_bits_checksum(bits: Span[UInt8, ...]) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_pucch_format2_bits_checksum(bits)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = result
    return (elapsed, fingerprint)


def _run_nr_pucch_format2_bits_checksum() raises -> UInt64:
    var bits = _bits(7, 1)
    var bits_span = Span(bits)
    var first = _bench_nr_pucch_format2_bits_checksum(bits_span)
    var second = _bench_nr_pucch_format2_bits_checksum(bits_span)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_pucch_format2_bits_checksum(bits_span))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_pucch_format2_bits_checksum(bits_span)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_pucch_format2_bits_checksum", samples, checksum)


@no_inline
def _bench_nr_pucch_format2_reference_dmrs(config: NRPUCCHFormat2Config) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_pucch_format2_reference_dmrs(config)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _fingerprint_complex64(result)
    return (elapsed, fingerprint)


def _run_nr_pucch_format2_reference_dmrs() raises -> UInt64:
    var config = NRPUCCHFormat2Config(128, 0, 7, 9, 1, 24, 73, 321, 0x1234)
    var first = _bench_nr_pucch_format2_reference_dmrs(config)
    var second = _bench_nr_pucch_format2_reference_dmrs(config)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_pucch_format2_reference_dmrs(config))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_pucch_format2_reference_dmrs(config)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_pucch_format2_reference_dmrs", samples, checksum)


@no_inline
def _bench_nr_pucch_format2_waveform_sample_count(config: NRPUCCHFormat2Config) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_pucch_format2_waveform_sample_count(config)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = UInt64(result)
    return (elapsed, fingerprint)


def _run_nr_pucch_format2_waveform_sample_count() raises -> UInt64:
    var config = NRPUCCHFormat2Config(128, 0, 7, 9, 1, 24, 73, 321, 0x1234)
    var first = _bench_nr_pucch_format2_waveform_sample_count(config)
    var second = _bench_nr_pucch_format2_waveform_sample_count(config)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_pucch_format2_waveform_sample_count(config))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_pucch_format2_waveform_sample_count(config)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_pucch_format2_waveform_sample_count", samples, checksum)


@no_inline
def _bench_nr_pucch_format2_grid_to_waveform(config: NRPUCCHFormat2Config, grid: NRResourceGrid) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_pucch_format2_grid_to_waveform(config, grid)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _fingerprint_complex64(result)
    return (elapsed, fingerprint)


def _run_nr_pucch_format2_grid_to_waveform() raises -> UInt64:
    var config = NRPUCCHFormat2Config(128, 0, 7, 9, 1, 24, 73, 321, 0x1234)
    var payload = _bits(7, 1)
    var tx = nr_pucch_format2_encode(Span(payload), config)
    var grid = nr_pucch_format2_waveform_to_grid(
        config, Span(tx.waveform)
    )
    var first = _bench_nr_pucch_format2_grid_to_waveform(config, grid)
    var second = _bench_nr_pucch_format2_grid_to_waveform(config, grid)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_pucch_format2_grid_to_waveform(config, grid))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_pucch_format2_grid_to_waveform(config, grid)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_pucch_format2_grid_to_waveform", samples, checksum)


@no_inline
def _bench_nr_pucch_format2_waveform_to_grid(config: NRPUCCHFormat2Config, waveform: Span[Complex64, ...]) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_pucch_format2_waveform_to_grid(config, waveform)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _mix(UInt64(result.symbol_count), UInt64(len(result.values)))
    return (elapsed, fingerprint)


def _run_nr_pucch_format2_waveform_to_grid() raises -> UInt64:
    var config = NRPUCCHFormat2Config(128, 0, 7, 9, 1, 24, 73, 321, 0x1234)
    var payload = _bits(7, 1)
    var tx = nr_pucch_format2_encode(Span(payload), config)
    var waveform_span = Span(tx.waveform)
    var first = _bench_nr_pucch_format2_waveform_to_grid(config, waveform_span)
    var second = _bench_nr_pucch_format2_waveform_to_grid(config, waveform_span)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_pucch_format2_waveform_to_grid(config, waveform_span))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_pucch_format2_waveform_to_grid(config, waveform_span)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_pucch_format2_waveform_to_grid", samples, checksum)


@no_inline
def _bench_nr_pucch_format2_encode(payload: Span[UInt8, ...], config: NRPUCCHFormat2Config) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_pucch_format2_encode(payload, config)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _mix(UInt64(len(result.waveform)), UInt64(len(result.scrambled_bits)))
    return (elapsed, fingerprint)


def _run_nr_pucch_format2_encode() raises -> UInt64:
    var config = NRPUCCHFormat2Config(128, 0, 7, 9, 1, 24, 73, 321, 0x1234)
    var payload = _bits(7, 1)
    var payload_span = Span(payload)
    var first = _bench_nr_pucch_format2_encode(payload_span, config)
    var second = _bench_nr_pucch_format2_encode(payload_span, config)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_pucch_format2_encode(payload_span, config))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_pucch_format2_encode(payload_span, config)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_pucch_format2_encode", samples, checksum)


@no_inline
def _bench_nr_pucch_format2_flat_channel(waveform: Span[Complex64, ...]) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_pucch_format2_flat_channel(waveform, Complex64(0.8, 0.2), seed=UInt64(7))
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _fingerprint_complex64(result)
    return (elapsed, fingerprint)


def _run_nr_pucch_format2_flat_channel() raises -> UInt64:
    var config = NRPUCCHFormat2Config(128, 0, 7, 9, 1, 24, 73, 321, 0x1234)
    var payload = _bits(7, 1)
    var tx = nr_pucch_format2_encode(Span(payload), config)
    var waveform_span = Span(tx.waveform)
    var first = _bench_nr_pucch_format2_flat_channel(waveform_span)
    var second = _bench_nr_pucch_format2_flat_channel(waveform_span)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_pucch_format2_flat_channel(waveform_span))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_pucch_format2_flat_channel(waveform_span)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_pucch_format2_flat_channel", samples, checksum)


@no_inline
def _bench_nr_pucch_format2_descramble_llrs(llrs: Span[Float64, ...]) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_pucch_format2_descramble_llrs(llrs, 0x1234, 321)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _fingerprint_float64(result)
    return (elapsed, fingerprint)


def _run_nr_pucch_format2_descramble_llrs() raises -> UInt64:
    var config = NRPUCCHFormat2Config(128, 0, 7, 9, 1, 24, 73, 321, 0x1234)
    var payload = _bits(7, 1)
    var tx = nr_pucch_format2_encode(Span(payload), config)
    var llrs = _llrs(Span(tx.scrambled_bits))
    var llrs_span = Span(llrs)
    var first = _bench_nr_pucch_format2_descramble_llrs(llrs_span)
    var second = _bench_nr_pucch_format2_descramble_llrs(llrs_span)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_pucch_format2_descramble_llrs(llrs_span))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_pucch_format2_descramble_llrs(llrs_span)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_pucch_format2_descramble_llrs", samples, checksum)


@no_inline
def _bench_nr_pucch_format2_decode(waveform: Span[Complex64, ...], config: NRPUCCHFormat2Config) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_pucch_format2_decode(waveform, config, 7, 0.0)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _mix(UInt64(len(result.payload)), UInt64(1 if result.crc_ok else 0))
    return (elapsed, fingerprint)


def _run_nr_pucch_format2_decode() raises -> UInt64:
    var config = NRPUCCHFormat2Config(128, 0, 7, 9, 1, 24, 73, 321, 0x1234)
    var payload = _bits(7, 1)
    var tx = nr_pucch_format2_encode(Span(payload), config)
    var received = nr_pucch_format2_flat_channel(Span(tx.waveform), Complex64(0.8, 0.2), seed=UInt64(7))
    var waveform_span = Span(received)
    var first = _bench_nr_pucch_format2_decode(waveform_span, config)
    var second = _bench_nr_pucch_format2_decode(waveform_span, config)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_pucch_format2_decode(waveform_span, config))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_pucch_format2_decode(waveform_span, config)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_pucch_format2_decode", samples, checksum)



@no_inline
def _bench_nr_pdsch_ptrs_density_from_thresholds() raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_pdsch_ptrs_density_from_thresholds(12, 12, 5, 10, 15, 29, 4, 12)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _mix(UInt64(result.time_density), UInt64(result.frequency_density))
    return (elapsed, fingerprint)


def _run_nr_pdsch_ptrs_density_from_thresholds() raises -> UInt64:
    var first = _bench_nr_pdsch_ptrs_density_from_thresholds()
    var second = _bench_nr_pdsch_ptrs_density_from_thresholds()
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_pdsch_ptrs_density_from_thresholds())
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_pdsch_ptrs_density_from_thresholds()
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_pdsch_ptrs_density_from_thresholds", samples, checksum)


@no_inline
def _bench_nr_pdsch_ptrs_c_init() raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_pdsch_ptrs_c_init(3, 2, 42, 0)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = UInt64(result)
    return (elapsed, fingerprint)


def _run_nr_pdsch_ptrs_c_init() raises -> UInt64:
    var first = _bench_nr_pdsch_ptrs_c_init()
    var second = _bench_nr_pdsch_ptrs_c_init()
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_pdsch_ptrs_c_init())
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_pdsch_ptrs_c_init()
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_pdsch_ptrs_c_init", samples, checksum)


@no_inline
def _bench_nr_pdsch_ptrs_time_positions(dmrs_symbols: Span[Int, ...]) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_pdsch_ptrs_time_positions(14, 2, dmrs_symbols)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _fingerprint_int(result)
    return (elapsed, fingerprint)


def _run_nr_pdsch_ptrs_time_positions() raises -> UInt64:
    var dmrs_symbols: List[Int] = [2, 11]
    var dmrs_span = Span(dmrs_symbols)
    var first = _bench_nr_pdsch_ptrs_time_positions(dmrs_span)
    var second = _bench_nr_pdsch_ptrs_time_positions(dmrs_span)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_pdsch_ptrs_time_positions(dmrs_span))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_pdsch_ptrs_time_positions(dmrs_span)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_pdsch_ptrs_time_positions", samples, checksum)


@no_inline
def _bench_nr_pdsch_ptrs_k_ref_re() raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_pdsch_ptrs_k_ref_re(1000, 1, 2)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = UInt64(result)
    return (elapsed, fingerprint)


def _run_nr_pdsch_ptrs_k_ref_re() raises -> UInt64:
    var first = _bench_nr_pdsch_ptrs_k_ref_re()
    var second = _bench_nr_pdsch_ptrs_k_ref_re()
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_pdsch_ptrs_k_ref_re())
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_pdsch_ptrs_k_ref_re()
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_pdsch_ptrs_k_ref_re", samples, checksum)


@no_inline
def _bench_nr_pdsch_ptrs_frequency_positions() raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_pdsch_ptrs_frequency_positions(10, 0x1234, 4, 1000, 1, 2)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _fingerprint_int(result)
    return (elapsed, fingerprint)


def _run_nr_pdsch_ptrs_frequency_positions() raises -> UInt64:
    var first = _bench_nr_pdsch_ptrs_frequency_positions()
    var second = _bench_nr_pdsch_ptrs_frequency_positions()
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_pdsch_ptrs_frequency_positions())
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_pdsch_ptrs_frequency_positions()
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_pdsch_ptrs_frequency_positions", samples, checksum)


@no_inline
def _bench_nr_pdsch_ptrs_sequence(positions: Span[Int, ...]) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_pdsch_ptrs_sequence(positions, 0, 3, 2, 42, 0, 1000, 1)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _fingerprint_complex64(result)
    return (elapsed, fingerprint)


def _run_nr_pdsch_ptrs_sequence() raises -> UInt64:
    var positions = nr_pdsch_ptrs_frequency_positions(10, 0x1234, 4, 1000, 1, 2)
    var positions_span = Span(positions)
    var first = _bench_nr_pdsch_ptrs_sequence(positions_span)
    var second = _bench_nr_pdsch_ptrs_sequence(positions_span)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_pdsch_ptrs_sequence(positions_span))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_pdsch_ptrs_sequence(positions_span)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_pdsch_ptrs_sequence", samples, checksum)


@no_inline
def _bench_nr_extract_pdsch_ptrs(grid: NRResourceGrid, times: Span[Int, ...], frequencies: Span[Int, ...]) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_extract_pdsch_ptrs(grid, 0, 0, times, frequencies)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _fingerprint_complex64(result)
    return (elapsed, fingerprint)


def _run_nr_extract_pdsch_ptrs() raises -> UInt64:
    var dmrs_symbols: List[Int] = [2, 11]
    var times = nr_pdsch_ptrs_time_positions(14, 2, Span(dmrs_symbols))
    var frequencies = nr_pdsch_ptrs_frequency_positions(10, 0x1234, 4, 1000, 1, 2)
    var references = nr_pdsch_ptrs_sequence(Span(frequencies), 0, 3, 2, 42, 0, 1000, 1)
    var grid = NRResourceGrid(14, 128)
    nr_map_pdsch_ptrs(grid, 0, 0, Span(times), Span(frequencies), Span(references))
    var times_span = Span(times)
    var frequencies_span = Span(frequencies)
    var first = _bench_nr_extract_pdsch_ptrs(grid, times_span, frequencies_span)
    var second = _bench_nr_extract_pdsch_ptrs(grid, times_span, frequencies_span)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_extract_pdsch_ptrs(grid, times_span, frequencies_span))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_extract_pdsch_ptrs(grid, times_span, frequencies_span)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_extract_pdsch_ptrs", samples, checksum)


@no_inline
def _bench_nr_ptrs_estimate_common_phase(received: Span[Complex64, ...], known: Span[Complex64, ...], symbols: Span[Int, ...]) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_ptrs_estimate_common_phase(received, known, symbols)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _mix(UInt64(len(result.symbols)), UInt64(len(result.phase_radians)))
    return (elapsed, fingerprint)


def _run_nr_ptrs_estimate_common_phase() raises -> UInt64:
    var dmrs_symbols: List[Int] = [2, 11]
    var symbols = nr_pdsch_ptrs_time_positions(14, 2, Span(dmrs_symbols))
    var frequencies = nr_pdsch_ptrs_frequency_positions(10, 0x1234, 4, 1000, 1, 2)
    var known = nr_pdsch_ptrs_sequence(Span(frequencies), 0, 3, 2, 42, 0, 1000, 1)
    var received = List[Complex64](capacity=len(symbols) * len(known))
    for _ in symbols:
        for value in known:
            received.append(value)
    var received_span = Span(received)
    var known_span = Span(known)
    var symbols_span = Span(symbols)
    var first = _bench_nr_ptrs_estimate_common_phase(received_span, known_span, symbols_span)
    var second = _bench_nr_ptrs_estimate_common_phase(received_span, known_span, symbols_span)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_ptrs_estimate_common_phase(received_span, known_span, symbols_span))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_ptrs_estimate_common_phase(received_span, known_span, symbols_span)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_ptrs_estimate_common_phase", samples, checksum)


@no_inline
def _bench_nr_ptrs_correct_common_phase(samples: Span[Complex64, ...]) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_ptrs_correct_common_phase(samples, 0.1)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _fingerprint_complex64(result)
    return (elapsed, fingerprint)


def _run_nr_ptrs_correct_common_phase() raises -> UInt64:
    var input_samples = List[Complex64](
        length=8, fill=Complex64(1.0, 0.5)
    )
    var samples_span = Span(input_samples)
    var first = _bench_nr_ptrs_correct_common_phase(samples_span)
    var second = _bench_nr_ptrs_correct_common_phase(samples_span)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_ptrs_correct_common_phase(samples_span))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_ptrs_correct_common_phase(samples_span)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_ptrs_correct_common_phase", samples, checksum)



@no_inline
def _bench_nr_map_pdsch_ptrs(
    mut grid: NRResourceGrid,
    times: Span[Int, ...],
    frequencies: Span[Int, ...],
    references: Span[Complex64, ...],
) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    nr_map_pdsch_ptrs(
        grid, 0, 0, times, frequencies, references
    )
    var elapsed = global_perf_counter_ns() - start
    var mapped = grid[times[0], frequencies[0]]
    var fingerprint = _mix(
        UInt64(len(grid.values)),
        UInt64(1 if mapped.re >= 0.0 else 0),
    )
    keep(mapped)
    return (elapsed, fingerprint)


def _run_nr_map_pdsch_ptrs() raises -> UInt64:
    var dmrs_symbols: List[Int] = [2, 11]
    var times = nr_pdsch_ptrs_time_positions(
        14, 2, Span(dmrs_symbols)
    )
    var frequencies = nr_pdsch_ptrs_frequency_positions(
        10, 0x1234, 4, 1000, 1, 2
    )
    var references = nr_pdsch_ptrs_sequence(
        Span(frequencies), 0, 3, 2, 42, 0, 1000, 1
    )
    var times_span = Span(times)
    var frequencies_span = Span(frequencies)
    var references_span = Span(references)
    var grid = NRResourceGrid(14, 128)
    var first = _bench_nr_map_pdsch_ptrs(
        grid, times_span, frequencies_span, references_span
    )
    var second = _bench_nr_map_pdsch_ptrs(
        grid, times_span, frequencies_span, references_span
    )
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(
            _bench_nr_map_pdsch_ptrs(
                grid, times_span, frequencies_span, references_span
            )
        )
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_map_pdsch_ptrs(
            grid, times_span, frequencies_span, references_span
        )
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    keep(grid)
    return _finish_sample("nr_map_pdsch_ptrs", samples, checksum)



@no_inline
def _bench_nr_pbch_build_payload(mib: Span[UInt8, ...]) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_pbch_build_payload(mib, 0, 0, 1, 4)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _fingerprint_uint8(result)
    return (elapsed, fingerprint)


def _run_nr_pbch_build_payload() raises -> UInt64:
    var mib = _bits(24, 0)
    for index in range(6):
        mib[index] = 0
    var mib_span = Span(mib)
    var first = _bench_nr_pbch_build_payload(mib_span)
    var second = _bench_nr_pbch_build_payload(mib_span)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_pbch_build_payload(mib_span))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_pbch_build_payload(mib_span)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_pbch_build_payload", samples, checksum)


@no_inline
def _bench_nr_pbch_payload_interleave(payload: Span[UInt8, ...]) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_pbch_payload_interleave(payload)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _fingerprint_uint8(result)
    return (elapsed, fingerprint)


def _run_nr_pbch_payload_interleave() raises -> UInt64:
    var mib = _bits(24, 0)
    for index in range(6):
        mib[index] = 0
    var payload = nr_pbch_build_payload(Span(mib), 0, 0, 1, 4)
    var payload_span = Span(payload)
    var first = _bench_nr_pbch_payload_interleave(payload_span)
    var second = _bench_nr_pbch_payload_interleave(payload_span)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_pbch_payload_interleave(payload_span))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_pbch_payload_interleave(payload_span)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_pbch_payload_interleave", samples, checksum)


@no_inline
def _bench_nr_pbch_payload_deinterleave(payload: Span[UInt8, ...]) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_pbch_payload_deinterleave(payload)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _fingerprint_uint8(result)
    return (elapsed, fingerprint)


def _run_nr_pbch_payload_deinterleave() raises -> UInt64:
    var mib = _bits(24, 0)
    for index in range(6):
        mib[index] = 0
    var payload = nr_pbch_build_payload(Span(mib), 0, 0, 1, 4)
    var interleaved = nr_pbch_payload_interleave(Span(payload))
    var payload_span = Span(interleaved)
    var first = _bench_nr_pbch_payload_deinterleave(payload_span)
    var second = _bench_nr_pbch_payload_deinterleave(payload_span)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_pbch_payload_deinterleave(payload_span))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_pbch_payload_deinterleave(payload_span)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_pbch_payload_deinterleave", samples, checksum)


@no_inline
def _bench_nr_pbch_payload_scramble(payload: Span[UInt8, ...]) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_pbch_payload_scramble(payload, 42, 0, 4)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _fingerprint_uint8(result)
    return (elapsed, fingerprint)


def _run_nr_pbch_payload_scramble() raises -> UInt64:
    var mib = _bits(24, 0)
    for index in range(6):
        mib[index] = 0
    var payload = nr_pbch_build_payload(Span(mib), 0, 0, 1, 4)
    var interleaved = nr_pbch_payload_interleave(Span(payload))
    var payload_span = Span(interleaved)
    var first = _bench_nr_pbch_payload_scramble(payload_span)
    var second = _bench_nr_pbch_payload_scramble(payload_span)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_pbch_payload_scramble(payload_span))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_pbch_payload_scramble(payload_span)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_pbch_payload_scramble", samples, checksum)


@no_inline
def _bench_nr_pbch_payload_descramble(payload: Span[UInt8, ...]) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_pbch_payload_descramble(payload, 42, 4)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _fingerprint_uint8(result)
    return (elapsed, fingerprint)


def _run_nr_pbch_payload_descramble() raises -> UInt64:
    var mib = _bits(24, 0)
    for index in range(6):
        mib[index] = 0
    var payload = nr_pbch_build_payload(Span(mib), 0, 0, 1, 4)
    var interleaved = nr_pbch_payload_interleave(Span(payload))
    var scrambled = nr_pbch_payload_scramble(Span(interleaved), 42, 0, 4)
    var payload_span = Span(scrambled)
    var first = _bench_nr_pbch_payload_descramble(payload_span)
    var second = _bench_nr_pbch_payload_descramble(payload_span)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_pbch_payload_descramble(payload_span))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_pbch_payload_descramble(payload_span)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_pbch_payload_descramble", samples, checksum)


@no_inline
def _bench_nr_pbch_crc24c(payload: Span[UInt8, ...]) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_pbch_crc24c(payload)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = result
    return (elapsed, fingerprint)


def _run_nr_pbch_crc24c() raises -> UInt64:
    var mib = _bits(24, 0)
    for index in range(6):
        mib[index] = 0
    var payload = nr_pbch_build_payload(Span(mib), 0, 0, 1, 4)
    var payload_span = Span(payload)
    var first = _bench_nr_pbch_crc24c(payload_span)
    var second = _bench_nr_pbch_crc24c(payload_span)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_pbch_crc24c(payload_span))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_pbch_crc24c(payload_span)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_pbch_crc24c", samples, checksum)


@no_inline
def _bench_nr_pbch_crc24c_append(payload: Span[UInt8, ...]) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_pbch_crc24c_append(payload)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _fingerprint_uint8(result)
    return (elapsed, fingerprint)


def _run_nr_pbch_crc24c_append() raises -> UInt64:
    var mib = _bits(24, 0)
    for index in range(6):
        mib[index] = 0
    var payload = nr_pbch_build_payload(Span(mib), 0, 0, 1, 4)
    var payload_span = Span(payload)
    var first = _bench_nr_pbch_crc24c_append(payload_span)
    var second = _bench_nr_pbch_crc24c_append(payload_span)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_pbch_crc24c_append(payload_span))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_pbch_crc24c_append(payload_span)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_pbch_crc24c_append", samples, checksum)


@no_inline
def _bench_nr_pbch_crc24c_check(payload: Span[UInt8, ...]) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_pbch_crc24c_check(payload)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = UInt64(1 if result else 0)
    return (elapsed, fingerprint)


def _run_nr_pbch_crc24c_check() raises -> UInt64:
    var mib = _bits(24, 0)
    for index in range(6):
        mib[index] = 0
    var payload = nr_pbch_build_payload(Span(mib), 0, 0, 1, 4)
    var crc = nr_pbch_crc24c_append(Span(payload))
    var payload_span = Span(crc)
    var first = _bench_nr_pbch_crc24c_check(payload_span)
    var second = _bench_nr_pbch_crc24c_check(payload_span)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_pbch_crc24c_check(payload_span))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_pbch_crc24c_check(payload_span)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_pbch_crc24c_check", samples, checksum)


@no_inline
def _bench_nr_pbch_physical_scramble(bits: Span[UInt8, ...]) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_pbch_physical_scramble(bits, 42, 1, 4)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _fingerprint_uint8(result)
    return (elapsed, fingerprint)


def _run_nr_pbch_physical_scramble() raises -> UInt64:
    var mib = _bits(24, 0)
    for index in range(6):
        mib[index] = 0
    var payload = nr_pbch_build_payload(Span(mib), 0, 0, 1, 4)
    var crc = nr_pbch_crc24c_append(Span(payload))
    var bits_span = Span(crc)
    var first = _bench_nr_pbch_physical_scramble(bits_span)
    var second = _bench_nr_pbch_physical_scramble(bits_span)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_pbch_physical_scramble(bits_span))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_pbch_physical_scramble(bits_span)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_pbch_physical_scramble", samples, checksum)


@no_inline
def _bench_nr_pbch_physical_descramble_llrs(llrs: Span[Float64, ...]) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_pbch_physical_descramble_llrs(llrs, 42, 1, 4)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _fingerprint_float64(result)
    return (elapsed, fingerprint)


def _run_nr_pbch_physical_descramble_llrs() raises -> UInt64:
    var mib = _bits(24, 0)
    for index in range(6):
        mib[index] = 0
    var payload = nr_pbch_build_payload(Span(mib), 0, 0, 1, 4)
    var crc = nr_pbch_crc24c_append(Span(payload))
    var physical = nr_pbch_physical_scramble(Span(crc), 42, 1, 4)
    var llrs = _llrs(Span(physical))
    var llrs_span = Span(llrs)
    var first = _bench_nr_pbch_physical_descramble_llrs(llrs_span)
    var second = _bench_nr_pbch_physical_descramble_llrs(llrs_span)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_pbch_physical_descramble_llrs(llrs_span))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_pbch_physical_descramble_llrs(llrs_span)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_pbch_physical_descramble_llrs", samples, checksum)


@no_inline
def _bench_nr_pbch_encode(mib: Span[UInt8, ...]) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_pbch_encode(mib, 42, 0, 0, 1, 4)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _mix(UInt64(len(result.physical_channel_bits)), UInt64(len(result.checkpoint_metadata)))
    return (elapsed, fingerprint)


def _run_nr_pbch_encode() raises -> UInt64:
    var mib = _bits(24, 0)
    for index in range(6):
        mib[index] = 0
    var mib_span = Span(mib)
    var first = _bench_nr_pbch_encode(mib_span)
    var second = _bench_nr_pbch_encode(mib_span)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_pbch_encode(mib_span))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_pbch_encode(mib_span)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_pbch_encode", samples, checksum)


@no_inline
def _bench_nr_pbch_decode(llrs: Span[Float64, ...]) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_pbch_decode(llrs, 42, 1, 4)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _mix(UInt64(len(result.payload)), UInt64(1 if result.crc_ok else 0))
    return (elapsed, fingerprint)


def _run_nr_pbch_decode() raises -> UInt64:
    var mib = _bits(24, 0)
    for index in range(6):
        mib[index] = 0
    var tx = nr_pbch_encode(Span(mib), 42, 0, 0, 1, 4)
    var llrs = _llrs(Span(tx.physical_channel_bits))
    var llrs_span = Span(llrs)
    var first = _bench_nr_pbch_decode(llrs_span)
    var second = _bench_nr_pbch_decode(llrs_span)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_pbch_decode(llrs_span))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_pbch_decode(llrs_span)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_pbch_decode", samples, checksum)



@no_inline
def _bench_nr_normal_cp_samples() raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_normal_cp_samples(2048, 0, 0)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = UInt64(result)
    return (elapsed, fingerprint)


def _run_nr_normal_cp_samples() raises -> UInt64:
    var first = _bench_nr_normal_cp_samples()
    var second = _bench_nr_normal_cp_samples()
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_normal_cp_samples())
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_normal_cp_samples()
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_normal_cp_samples", samples, checksum)


@no_inline
def _bench_nr_pdsch_dmrs_c_init() raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_pdsch_dmrs_c_init(3, 2, 42, 0)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = UInt64(result)
    return (elapsed, fingerprint)


def _run_nr_pdsch_dmrs_c_init() raises -> UInt64:
    var first = _bench_nr_pdsch_dmrs_c_init()
    var second = _bench_nr_pdsch_dmrs_c_init()
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_pdsch_dmrs_c_init())
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_pdsch_dmrs_c_init()
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_pdsch_dmrs_c_init", samples, checksum)


@no_inline
def _bench_nr_extract_pdsch_comb2(grid: NRResourceGrid) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_extract_pdsch_comb2(grid, 1, 4, 11, 0)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _fingerprint_complex64(result)
    return (elapsed, fingerprint)


def _run_nr_extract_pdsch_comb2() raises -> UInt64:
    var grid = NRResourceGrid(4, 256)
    var data = List[Complex64](length=5, fill=Complex64(1.0, -1.0))
    var dmrs = nr_pdsch_dmrs(nr_pdsch_dmrs_c_init(3, 2, 42, 0), 6)
    nr_map_pdsch_comb2(grid, 1, 4, 11, 0, Span(data), Span(dmrs))
    var first = _bench_nr_extract_pdsch_comb2(grid)
    var second = _bench_nr_extract_pdsch_comb2(grid)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_extract_pdsch_comb2(grid))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_extract_pdsch_comb2(grid)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_extract_pdsch_comb2", samples, checksum)


@no_inline
def _bench_nr_extract_dmrs_comb2(grid: NRResourceGrid) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_extract_dmrs_comb2(grid, 1, 4, 11, 0)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _fingerprint_complex64(result)
    return (elapsed, fingerprint)


def _run_nr_extract_dmrs_comb2() raises -> UInt64:
    var grid = NRResourceGrid(4, 256)
    var data = List[Complex64](length=5, fill=Complex64(1.0, -1.0))
    var dmrs = nr_pdsch_dmrs(nr_pdsch_dmrs_c_init(3, 2, 42, 0), 6)
    nr_map_pdsch_comb2(grid, 1, 4, 11, 0, Span(data), Span(dmrs))
    var first = _bench_nr_extract_dmrs_comb2(grid)
    var second = _bench_nr_extract_dmrs_comb2(grid)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_extract_dmrs_comb2(grid))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_extract_dmrs_comb2(grid)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_extract_dmrs_comb2", samples, checksum)


@no_inline
def _bench_nr_ls_channel_estimate_comb2(received: Span[Complex64, ...], known: Span[Complex64, ...]) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_ls_channel_estimate_comb2(received, known, 11, 0)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _fingerprint_complex64(result)
    return (elapsed, fingerprint)


def _run_nr_ls_channel_estimate_comb2() raises -> UInt64:
    var known = nr_pdsch_dmrs(nr_pdsch_dmrs_c_init(3, 2, 42, 0), 6)
    var received = List[Complex64](capacity=len(known))
    for value in known:
        received.append(value * Complex64(0.8, 0.2))
    var received_span = Span(received)
    var known_span = Span(known)
    var first = _bench_nr_ls_channel_estimate_comb2(received_span, known_span)
    var second = _bench_nr_ls_channel_estimate_comb2(received_span, known_span)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_ls_channel_estimate_comb2(received_span, known_span))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_ls_channel_estimate_comb2(received_span, known_span)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_ls_channel_estimate_comb2", samples, checksum)


@no_inline
def _bench_nr_equalize_pdsch_comb2(received: Span[Complex64, ...], channel: Span[Complex64, ...]) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_equalize_pdsch_comb2(received, channel, 0)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _fingerprint_complex64(result)
    return (elapsed, fingerprint)


def _run_nr_equalize_pdsch_comb2() raises -> UInt64:
    var received = List[Complex64](length=5, fill=Complex64(0.8, 0.2))
    var channel = List[Complex64](length=11, fill=Complex64(0.8, 0.2))
    var received_span = Span(received)
    var channel_span = Span(channel)
    var first = _bench_nr_equalize_pdsch_comb2(received_span, channel_span)
    var second = _bench_nr_equalize_pdsch_comb2(received_span, channel_span)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_equalize_pdsch_comb2(received_span, channel_span))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_equalize_pdsch_comb2(received_span, channel_span)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_equalize_pdsch_comb2", samples, checksum)


@no_inline
def _bench_nr_search_pss(samples: Span[Complex64, ...]) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_search_pss(samples)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = UInt64(result.n_id_2)
    return (elapsed, fingerprint)


def _run_nr_search_pss() raises -> UInt64:
    var pss = nr_pss(2)
    var pss_samples = List[Complex64](capacity=len(pss))
    for value in pss:
        pss_samples.append(Complex64(value, 0.0))
    var samples_span = Span(pss_samples)
    var first = _bench_nr_search_pss(samples_span)
    var second = _bench_nr_search_pss(samples_span)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_search_pss(samples_span))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_search_pss(samples_span)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_search_pss", samples, checksum)


@no_inline
def _bench_nr_detect_sss(samples: Span[Complex64, ...]) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_detect_sss(samples, 2)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = UInt64(result.physical_cell_id)
    return (elapsed, fingerprint)


def _run_nr_detect_sss() raises -> UInt64:
    var sss = nr_sss(17, 2)
    var sss_samples = List[Complex64](capacity=len(sss))
    for value in sss:
        sss_samples.append(Complex64(value, 0.0))
    var samples_span = Span(sss_samples)
    var first = _bench_nr_detect_sss(samples_span)
    var second = _bench_nr_detect_sss(samples_span)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_detect_sss(samples_span))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_detect_sss(samples_span)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_detect_sss", samples, checksum)


@no_inline
def _bench_nr_pdsch_encode_transport_block(payload: Span[UInt8, ...]) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_pdsch_encode_transport_block(payload, 0.5, 2, 0, 240, 0x1234, 0, 42)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _mix(UInt64(len(result.symbols)), UInt64(len(result.encoded_null_mask)))
    return (elapsed, fingerprint)


def _run_nr_pdsch_encode_transport_block() raises -> UInt64:
    var payload = _bits(32, 1)
    var payload_span = Span(payload)
    var first = _bench_nr_pdsch_encode_transport_block(payload_span)
    var second = _bench_nr_pdsch_encode_transport_block(payload_span)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_pdsch_encode_transport_block(payload_span))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_pdsch_encode_transport_block(payload_span)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_pdsch_encode_transport_block", samples, checksum)


@no_inline
def _bench_nr_pdsch_decode_grid_comb2(grid: NRResourceGrid, dmrs: Span[Complex64, ...], null_mask: Span[UInt8, ...], profile: NRLDPCProfile) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_pdsch_decode_grid_comb2(grid, 0, 0, 240, 0, dmrs, null_mask, profile, 32, 2, 0, 0x1234, 0, 42, 0.01)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _mix(UInt64(len(result.payload)), UInt64(1 if result.transport_crc_ok else 0))
    return (elapsed, fingerprint)


def _run_nr_pdsch_decode_grid_comb2() raises -> UInt64:
    var payload = _bits(32, 1)
    var tx = nr_pdsch_encode_transport_block(Span(payload), 0.5, 2, 0, 240, 0x1234, 0, 42)
    var c_init = nr_pdsch_dmrs_c_init(3, 2, 42, 0)
    var dmrs = nr_pdsch_dmrs(c_init, 120)
    var grid = NRResourceGrid(1, 256)
    nr_map_pdsch_comb2(grid, 0, 0, 240, 0, Span(tx.symbols), Span(dmrs))
    var dmrs_span = Span(dmrs)
    var null_mask_span = Span(tx.encoded_null_mask)
    var profile = nr_ldpc_profile(32, 0.5)
    var first = _bench_nr_pdsch_decode_grid_comb2(grid, dmrs_span, null_mask_span, profile)
    var second = _bench_nr_pdsch_decode_grid_comb2(grid, dmrs_span, null_mask_span, profile)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_pdsch_decode_grid_comb2(grid, dmrs_span, null_mask_span, profile))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_pdsch_decode_grid_comb2(grid, dmrs_span, null_mask_span, profile)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_pdsch_decode_grid_comb2", samples, checksum)



@no_inline
def _bench_nr_map_pdsch_comb2(
    mut grid: NRResourceGrid,
    data: Span[Complex64, ...],
    dmrs: Span[Complex64, ...],
) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    nr_map_pdsch_comb2(grid, 1, 4, 11, 0, data, dmrs)
    var elapsed = global_perf_counter_ns() - start
    var mapped = grid[1, 4]
    var fingerprint = _mix(
        UInt64(len(grid.values)),
        UInt64(1 if mapped.re >= 0.0 else 0),
    )
    keep(mapped)
    return (elapsed, fingerprint)


def _run_nr_map_pdsch_comb2() raises -> UInt64:
    var data = List[Complex64](
        length=5, fill=Complex64(1.0, -1.0)
    )
    var dmrs = nr_pdsch_dmrs(
        nr_pdsch_dmrs_c_init(3, 2, 42, 0), 6
    )
    var data_span = Span(data)
    var dmrs_span = Span(dmrs)
    var grid = NRResourceGrid(4, 256)
    var first = _bench_nr_map_pdsch_comb2(
        grid, data_span, dmrs_span
    )
    var second = _bench_nr_map_pdsch_comb2(
        grid, data_span, dmrs_span
    )
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_map_pdsch_comb2(grid, data_span, dmrs_span))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_map_pdsch_comb2(
            grid, data_span, dmrs_span
        )
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    keep(grid)
    return _finish_sample("nr_map_pdsch_comb2", samples, checksum)


@no_inline
def _bench_nr_map_ssb_synchronization(
    mut grid: NRResourceGrid,
    pss: Span[Float64, ...],
    sss: Span[Float64, ...],
) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    nr_map_ssb_synchronization(grid, 8, pss, sss)
    var elapsed = global_perf_counter_ns() - start
    var mapped = grid[0, 8]
    var fingerprint = _mix(
        UInt64(len(grid.values)),
        UInt64(1 if mapped.re >= 0.0 else 0),
    )
    keep(mapped)
    return (elapsed, fingerprint)


def _run_nr_map_ssb_synchronization() raises -> UInt64:
    var pss = nr_pss(2)
    var sss = nr_sss(17, 2)
    var pss_span = Span(pss)
    var sss_span = Span(sss)
    var grid = NRResourceGrid(4, 256)
    var first = _bench_nr_map_ssb_synchronization(
        grid, pss_span, sss_span
    )
    var second = _bench_nr_map_ssb_synchronization(
        grid, pss_span, sss_span
    )
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(
            _bench_nr_map_ssb_synchronization(
                grid, pss_span, sss_span
            )
        )
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_map_ssb_synchronization(
            grid, pss_span, sss_span
        )
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    keep(grid)
    return _finish_sample(
        "nr_map_ssb_synchronization", samples, checksum
    )



@no_inline
def _bench_nr_select_base_graph() raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_select_base_graph(32, 0.5)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = UInt64(result)
    return (elapsed, fingerprint)


def _run_nr_select_base_graph() raises -> UInt64:
    var first = _bench_nr_select_base_graph()
    var second = _bench_nr_select_base_graph()
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_select_base_graph())
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_select_base_graph()
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_select_base_graph", samples, checksum)


@no_inline
def _bench_nr_ldpc_profile() raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_ldpc_profile(32, 0.5)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _mix(UInt64(result.base_graph), UInt64(result.lifting_size))
    return (elapsed, fingerprint)


def _run_nr_ldpc_profile() raises -> UInt64:
    var first = _bench_nr_ldpc_profile()
    var second = _bench_nr_ldpc_profile()
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_ldpc_profile())
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_ldpc_profile()
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_ldpc_profile", samples, checksum)


@no_inline
def _bench_nr_ldpc_filler_mask(profile: NRLDPCProfile) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_ldpc_filler_mask(profile)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _fingerprint_uint8(result)
    return (elapsed, fingerprint)


def _run_nr_ldpc_filler_mask() raises -> UInt64:
    var profile = nr_ldpc_profile(32, 0.5)
    var first = _bench_nr_ldpc_filler_mask(profile)
    var second = _bench_nr_ldpc_filler_mask(profile)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_ldpc_filler_mask(profile))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_ldpc_filler_mask(profile)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_ldpc_filler_mask", samples, checksum)


@no_inline
def _bench_nr_qc_expand_edges(rows: Span[Int, ...], columns: Span[Int, ...], shifts: Span[Int, ...]) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_qc_expand_edges(1, 2, rows, columns, shifts, 2)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _mix(UInt64(result.variable_count), UInt64(len(result.columns)))
    return (elapsed, fingerprint)


def _run_nr_qc_expand_edges() raises -> UInt64:
    var rows: List[Int] = [0, 0]
    var columns: List[Int] = [0, 1]
    var shifts: List[Int] = [0, 1]
    var rows_span = Span(rows)
    var columns_span = Span(columns)
    var shifts_span = Span(shifts)
    var first = _bench_nr_qc_expand_edges(rows_span, columns_span, shifts_span)
    var second = _bench_nr_qc_expand_edges(rows_span, columns_span, shifts_span)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_qc_expand_edges(rows_span, columns_span, shifts_span))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_qc_expand_edges(rows_span, columns_span, shifts_span)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_qc_expand_edges", samples, checksum)


@no_inline
def _bench_nr_standard_qc_graph() raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_standard_qc_graph(2, 2)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _mix(UInt64(result.variable_count), UInt64(len(result.columns)))
    return (elapsed, fingerprint)


def _run_nr_standard_qc_graph() raises -> UInt64:
    var first = _bench_nr_standard_qc_graph()
    var second = _bench_nr_standard_qc_graph()
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_standard_qc_graph())
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_standard_qc_graph()
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_standard_qc_graph", samples, checksum)


@no_inline
def _bench_nr_base_graph_dimensions() raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_base_graph_dimensions(2)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _mix(UInt64(result[0]), UInt64(result[1]))
    return (elapsed, fingerprint)


def _run_nr_base_graph_dimensions() raises -> UInt64:
    var first = _bench_nr_base_graph_dimensions()
    var second = _bench_nr_base_graph_dimensions()
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_base_graph_dimensions())
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_base_graph_dimensions()
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_base_graph_dimensions", samples, checksum)


@no_inline
def _bench_nr_base_graph_edge_count() raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_base_graph_edge_count(2)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = UInt64(result)
    return (elapsed, fingerprint)


def _run_nr_base_graph_edge_count() raises -> UInt64:
    var first = _bench_nr_base_graph_edge_count()
    var second = _bench_nr_base_graph_edge_count()
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_base_graph_edge_count())
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_base_graph_edge_count()
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_base_graph_edge_count", samples, checksum)


@no_inline
def _bench_nr_base_graph_edges() raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_base_graph_edges(2, 2)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _mix(UInt64(len(result.shifts)), UInt64(result.base_rows))
    return (elapsed, fingerprint)


def _run_nr_base_graph_edges() raises -> UInt64:
    var first = _bench_nr_base_graph_edges()
    var second = _bench_nr_base_graph_edges()
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_base_graph_edges())
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_base_graph_edges()
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_base_graph_edges", samples, checksum)


@no_inline
def _bench_nr_base_graph_shift() raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_base_graph_shift(2, 0, 0, 0)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = UInt64(result + 4096)
    return (elapsed, fingerprint)


def _run_nr_base_graph_shift() raises -> UInt64:
    var first = _bench_nr_base_graph_shift()
    var second = _bench_nr_base_graph_shift()
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_base_graph_shift())
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_base_graph_shift()
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_base_graph_shift", samples, checksum)


@no_inline
def _bench_nr_lifting_set_index() raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_lifting_set_index(2)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = UInt64(result + 4096)
    return (elapsed, fingerprint)


def _run_nr_lifting_set_index() raises -> UInt64:
    var first = _bench_nr_lifting_set_index()
    var second = _bench_nr_lifting_set_index()
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_lifting_set_index())
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_lifting_set_index()
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_lifting_set_index", samples, checksum)


@no_inline
def _bench_nr_ldpc_encode_full(information: Span[UInt8, ...]) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_ldpc_encode_full(information, 2, 2)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _fingerprint_uint8(result)
    return (elapsed, fingerprint)


def _run_nr_ldpc_encode_full() raises -> UInt64:
    var information = _bits(20, 3)
    var information_span = Span(information)
    var first = _bench_nr_ldpc_encode_full(information_span)
    var second = _bench_nr_ldpc_encode_full(information_span)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_ldpc_encode_full(information_span))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_ldpc_encode_full(information_span)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_ldpc_encode_full", samples, checksum)


@no_inline
def _bench_nr_ldpc_encode(information: Span[UInt8, ...]) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_ldpc_encode(information, 2, 2)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _fingerprint_uint8(result)
    return (elapsed, fingerprint)


def _run_nr_ldpc_encode() raises -> UInt64:
    var information = _bits(20, 3)
    var information_span = Span(information)
    var first = _bench_nr_ldpc_encode(information_span)
    var second = _bench_nr_ldpc_encode(information_span)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_ldpc_encode(information_span))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_ldpc_encode(information_span)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_ldpc_encode", samples, checksum)


@no_inline
def _bench_nr_ldpc_syndrome_ok(full: Span[UInt8, ...]) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_ldpc_syndrome_ok(full, 2, 2)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = UInt64(1 if result else 0)
    return (elapsed, fingerprint)


def _run_nr_ldpc_syndrome_ok() raises -> UInt64:
    var information = _bits(20, 3)
    var full = nr_ldpc_encode_full(Span(information), 2, 2)
    var full_span = Span(full)
    var first = _bench_nr_ldpc_syndrome_ok(full_span)
    var second = _bench_nr_ldpc_syndrome_ok(full_span)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_ldpc_syndrome_ok(full_span))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_ldpc_syndrome_ok(full_span)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_ldpc_syndrome_ok", samples, checksum)


@no_inline
def _bench_nr_ldpc_k0() raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_ldpc_k0(2, 2, 0)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = UInt64(result)
    return (elapsed, fingerprint)


def _run_nr_ldpc_k0() raises -> UInt64:
    var first = _bench_nr_ldpc_k0()
    var second = _bench_nr_ldpc_k0()
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_ldpc_k0())
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_ldpc_k0()
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_ldpc_k0", samples, checksum)


@no_inline
def _bench_nr_ldpc_rate_match(encoded: Span[UInt8, ...], nulls: Span[UInt8, ...]) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_ldpc_rate_match(encoded, nulls, 2, 2, 0, 100, 2)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _fingerprint_uint8(result)
    return (elapsed, fingerprint)


def _run_nr_ldpc_rate_match() raises -> UInt64:
    var information = _bits(20, 3)
    var encoded = nr_ldpc_encode(Span(information), 2, 2)
    var nulls = List[UInt8](length=len(encoded), fill=UInt8(0))
    var encoded_span = Span(encoded)
    var nulls_span = Span(nulls)
    var first = _bench_nr_ldpc_rate_match(encoded_span, nulls_span)
    var second = _bench_nr_ldpc_rate_match(encoded_span, nulls_span)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_ldpc_rate_match(encoded_span, nulls_span))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_ldpc_rate_match(encoded_span, nulls_span)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_ldpc_rate_match", samples, checksum)


@no_inline
def _bench_nr_ldpc_rate_recover(received: Span[Float64, ...], nulls: Span[UInt8, ...]) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_ldpc_rate_recover(received, nulls, 2, 2, 0, 2)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _fingerprint_float64(result)
    return (elapsed, fingerprint)


def _run_nr_ldpc_rate_recover() raises -> UInt64:
    var information = _bits(20, 3)
    var encoded = nr_ldpc_encode(Span(information), 2, 2)
    var nulls = List[UInt8](length=len(encoded), fill=UInt8(0))
    var matched = nr_ldpc_rate_match(Span(encoded), Span(nulls), 2, 2, 0, 100, 2)
    var received = _llrs(Span(matched))
    var received_span = Span(received)
    var nulls_span = Span(nulls)
    var first = _bench_nr_ldpc_rate_recover(received_span, nulls_span)
    var second = _bench_nr_ldpc_rate_recover(received_span, nulls_span)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_ldpc_rate_recover(received_span, nulls_span))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_ldpc_rate_recover(received_span, nulls_span)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_ldpc_rate_recover", samples, checksum)


@no_inline
def _bench_nr_ldpc_code_block_output_bits() raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_ldpc_code_block_output_bits(100, 2, 1, 1, 0)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = UInt64(result)
    return (elapsed, fingerprint)


def _run_nr_ldpc_code_block_output_bits() raises -> UInt64:
    var first = _bench_nr_ldpc_code_block_output_bits()
    var second = _bench_nr_ldpc_code_block_output_bits()
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_ldpc_code_block_output_bits())
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_ldpc_code_block_output_bits()
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_ldpc_code_block_output_bits", samples, checksum)


@no_inline
def _bench_nr_ldpc_decode(recovered: Span[Float64, ...], nulls: Span[UInt8, ...]) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_ldpc_decode(recovered, nulls, 2, 2, max_iterations=4)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _mix(UInt64(len(result.bits)), UInt64(1 if result.converged else 0))
    return (elapsed, fingerprint)


def _run_nr_ldpc_decode() raises -> UInt64:
    var information = _bits(20, 3)
    var encoded = nr_ldpc_encode(Span(information), 2, 2)
    var nulls = List[UInt8](length=len(encoded), fill=UInt8(0))
    var matched = nr_ldpc_rate_match(Span(encoded), Span(nulls), 2, 2, 0, 100, 2)
    var received = _llrs(Span(matched))
    var recovered = nr_ldpc_rate_recover(Span(received), Span(nulls), 2, 2, 0, 2)
    var recovered_span = Span(recovered)
    var nulls_span = Span(nulls)
    var first = _bench_nr_ldpc_decode(recovered_span, nulls_span)
    var second = _bench_nr_ldpc_decode(recovered_span, nulls_span)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_ldpc_decode(recovered_span, nulls_span))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_ldpc_decode(recovered_span, nulls_span)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_ldpc_decode", samples, checksum)


@no_inline
def _bench_nr_ldpc_crc24b(bits: Span[UInt8, ...]) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_ldpc_crc24b(bits)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = result
    return (elapsed, fingerprint)


def _run_nr_ldpc_crc24b() raises -> UInt64:
    var bits = _bits(32, 1)
    var bits_span = Span(bits)
    var first = _bench_nr_ldpc_crc24b(bits_span)
    var second = _bench_nr_ldpc_crc24b(bits_span)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_ldpc_crc24b(bits_span))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_ldpc_crc24b(bits_span)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_ldpc_crc24b", samples, checksum)


@no_inline
def _bench_nr_ldpc_crc24b_append(bits: Span[UInt8, ...]) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_ldpc_crc24b_append(bits)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _fingerprint_uint8(result)
    return (elapsed, fingerprint)


def _run_nr_ldpc_crc24b_append() raises -> UInt64:
    var bits = _bits(32, 1)
    var bits_span = Span(bits)
    var first = _bench_nr_ldpc_crc24b_append(bits_span)
    var second = _bench_nr_ldpc_crc24b_append(bits_span)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_ldpc_crc24b_append(bits_span))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_ldpc_crc24b_append(bits_span)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_ldpc_crc24b_append", samples, checksum)


@no_inline
def _bench_nr_ldpc_crc24b_check(bits: Span[UInt8, ...]) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_ldpc_crc24b_check(bits)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = UInt64(1 if result else 0)
    return (elapsed, fingerprint)


def _run_nr_ldpc_crc24b_check() raises -> UInt64:
    var payload = _bits(32, 1)
    var bits = nr_ldpc_crc24b_append(Span(payload))
    var bits_span = Span(bits)
    var first = _bench_nr_ldpc_crc24b_check(bits_span)
    var second = _bench_nr_ldpc_crc24b_check(bits_span)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_ldpc_crc24b_check(bits_span))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_ldpc_crc24b_check(bits_span)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_ldpc_crc24b_check", samples, checksum)


@no_inline
def _bench_nr_ldpc_segment(transport: Span[UInt8, ...], profile: NRLDPCProfile) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_ldpc_segment(transport, profile)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _mix(UInt64(len(result.bits)), UInt64(result.code_blocks))
    return (elapsed, fingerprint)


def _run_nr_ldpc_segment() raises -> UInt64:
    var payload = _bits(32, 1)
    var transport = nr_transport_crc_append(Span(payload))
    var transport_span = Span(transport)
    var profile = nr_ldpc_profile(32, 0.5)
    var first = _bench_nr_ldpc_segment(transport_span, profile)
    var second = _bench_nr_ldpc_segment(transport_span, profile)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_ldpc_segment(transport_span, profile))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_ldpc_segment(transport_span, profile)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_ldpc_segment", samples, checksum)


@no_inline
def _bench_nr_ldpc_desegment(decoded: Span[UInt8, ...], profile: NRLDPCProfile) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_ldpc_desegment(decoded, profile)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _mix(UInt64(len(result.bits)), UInt64(1 if result.code_block_crc_ok else 0))
    return (elapsed, fingerprint)


def _run_nr_ldpc_desegment() raises -> UInt64:
    var payload = _bits(32, 1)
    var transport = nr_transport_crc_append(Span(payload))
    var profile = nr_ldpc_profile(32, 0.5)
    var segments = nr_ldpc_segment(Span(transport), profile)
    var decoded_span = Span(segments.bits)
    var first = _bench_nr_ldpc_desegment(decoded_span, profile)
    var second = _bench_nr_ldpc_desegment(decoded_span, profile)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_ldpc_desegment(decoded_span, profile))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_ldpc_desegment(decoded_span, profile)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_ldpc_desegment", samples, checksum)


@no_inline
def _bench_nr_ldpc_encode_code_blocks(segments: NRLDPCSegments, profile: NRLDPCProfile) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_ldpc_encode_code_blocks(segments, profile)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _mix(UInt64(len(result.bits)), UInt64(result.code_blocks))
    return (elapsed, fingerprint)


def _run_nr_ldpc_encode_code_blocks() raises -> UInt64:
    var payload = _bits(32, 1)
    var transport = nr_transport_crc_append(Span(payload))
    var profile = nr_ldpc_profile(32, 0.5)
    var segments = nr_ldpc_segment(Span(transport), profile)
    var first = _bench_nr_ldpc_encode_code_blocks(segments, profile)
    var second = _bench_nr_ldpc_encode_code_blocks(segments, profile)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_ldpc_encode_code_blocks(segments, profile))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_ldpc_encode_code_blocks(segments, profile)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_ldpc_encode_code_blocks", samples, checksum)


@no_inline
def _bench_nr_ldpc_rate_match_code_blocks(blocks: NRLDPCEncodedBlocks, profile: NRLDPCProfile) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_ldpc_rate_match_code_blocks(blocks, profile, 0, 200, 2, 1)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _fingerprint_uint8(result)
    return (elapsed, fingerprint)


def _run_nr_ldpc_rate_match_code_blocks() raises -> UInt64:
    var payload = _bits(32, 1)
    var transport = nr_transport_crc_append(Span(payload))
    var profile = nr_ldpc_profile(32, 0.5)
    var segments = nr_ldpc_segment(Span(transport), profile)
    var blocks = nr_ldpc_encode_code_blocks(segments, profile)
    var first = _bench_nr_ldpc_rate_match_code_blocks(blocks, profile)
    var second = _bench_nr_ldpc_rate_match_code_blocks(blocks, profile)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_ldpc_rate_match_code_blocks(blocks, profile))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_ldpc_rate_match_code_blocks(blocks, profile)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_ldpc_rate_match_code_blocks", samples, checksum)


@no_inline
def _bench_nr_ldpc_rate_recover_code_blocks(received: Span[Float64, ...], nulls: Span[UInt8, ...], profile: NRLDPCProfile) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_ldpc_rate_recover_code_blocks(received, nulls, profile, 0, 2, 1)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _fingerprint_float64(result)
    return (elapsed, fingerprint)


def _run_nr_ldpc_rate_recover_code_blocks() raises -> UInt64:
    var payload = _bits(32, 1)
    var transport = nr_transport_crc_append(Span(payload))
    var profile = nr_ldpc_profile(32, 0.5)
    var segments = nr_ldpc_segment(Span(transport), profile)
    var blocks = nr_ldpc_encode_code_blocks(segments, profile)
    var matched = nr_ldpc_rate_match_code_blocks(blocks, profile, 0, 200, 2, 1)
    var received = _llrs(Span(matched))
    var received_span = Span(received)
    var nulls_span = Span(blocks.null_mask)
    var first = _bench_nr_ldpc_rate_recover_code_blocks(received_span, nulls_span, profile)
    var second = _bench_nr_ldpc_rate_recover_code_blocks(received_span, nulls_span, profile)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_ldpc_rate_recover_code_blocks(received_span, nulls_span, profile))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_ldpc_rate_recover_code_blocks(received_span, nulls_span, profile)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_ldpc_rate_recover_code_blocks", samples, checksum)


@no_inline
def _bench_nr_ldpc_decode_code_blocks(recovered: Span[Float64, ...], nulls: Span[UInt8, ...], profile: NRLDPCProfile) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = nr_ldpc_decode_code_blocks(recovered, nulls, profile, max_iterations=4)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _mix(UInt64(len(result.bits)), UInt64(1 if result.converged else 0))
    return (elapsed, fingerprint)


def _run_nr_ldpc_decode_code_blocks() raises -> UInt64:
    var payload = _bits(32, 1)
    var transport = nr_transport_crc_append(Span(payload))
    var profile = nr_ldpc_profile(32, 0.5)
    var segments = nr_ldpc_segment(Span(transport), profile)
    var blocks = nr_ldpc_encode_code_blocks(segments, profile)
    var matched = nr_ldpc_rate_match_code_blocks(blocks, profile, 0, 200, 2, 1)
    var received = _llrs(Span(matched))
    var recovered = nr_ldpc_rate_recover_code_blocks(Span(received), Span(blocks.null_mask), profile, 0, 2, 1)
    var recovered_span = Span(recovered)
    var nulls_span = Span(blocks.null_mask)
    var first = _bench_nr_ldpc_decode_code_blocks(recovered_span, nulls_span, profile)
    var second = _bench_nr_ldpc_decode_code_blocks(recovered_span, nulls_span, profile)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_nr_ldpc_decode_code_blocks(recovered_span, nulls_span, profile))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_nr_ldpc_decode_code_blocks(recovered_span, nulls_span, profile)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("nr_ldpc_decode_code_blocks", samples, checksum)



def _nr_sequence_transport_once() raises -> UInt64:
    var checksum = UInt64(0)
    var gold = nr_gold_bits(UInt32(0x1234567), 64)
    var qpsk = nr_qpsk_sequence(UInt32(0x1234567), 32)
    var pss = nr_pss(2)
    var sss = nr_sss(17, 2)
    checksum += UInt64(len(gold) + len(qpsk) + len(pss) + len(sss))
    checksum += UInt64(nr_pbch_dmrs_c_init(42, 1, 0, 4))
    checksum += UInt64(len(nr_pbch_dmrs(42, 1, 0, 4)))

    var payload = _bits(32, 1)
    var scrambled = nr_pdsch_scramble(Span(payload), 0x1234, 0, 42)
    var pdsch_refs = nr_pdsch_dmrs(UInt32(77), 16)
    var soft = _llrs(Span(scrambled))
    var descrambled = nr_pdsch_descramble_llrs(Span(soft), 0x1234, 0, 42)
    var filler4: List[UInt8] = [0, 1, 0, 0]
    var recovered4 = nr_rate_recover_llrs(Span(descrambled), 4, 1, Span(filler4))
    checksum += UInt64(len(pdsch_refs) + len(recovered4))
    checksum += UInt64(nr_transport_crc_width(len(payload)))
    checksum += nr_transport_crc(Span(payload))
    var transport = nr_transport_crc_append(Span(payload))
    checksum += UInt64(nr_transport_crc_check(Span(transport), len(payload)))
    keep(gold); keep(qpsk); keep(pss); keep(sss)
    keep(scrambled); keep(pdsch_refs); keep(descrambled); keep(recovered4)
    keep(transport)
    return checksum


@no_inline
def _nr_ldpc_once() raises -> UInt64:
    var checksum = UInt64(0)
    var payload = _bits(32, 1)
    var transport = nr_transport_crc_append(Span(payload))

    checksum += UInt64(nr_select_base_graph(32, 0.5))
    var profile = nr_ldpc_profile(32, 0.5)
    var profile_filler = nr_ldpc_filler_mask(profile)
    var rows: List[Int] = [0, 0]
    var columns: List[Int] = [0, 1]
    var shifts: List[Int] = [0, 1]
    var tiny = nr_qc_expand_edges(1, 2, Span(rows), Span(columns), Span(shifts), 2)
    var standard = nr_standard_qc_graph(2, 2)
    var dimensions = nr_base_graph_dimensions(2)
    checksum += UInt64(dimensions[0] + nr_base_graph_edge_count(2))
    var edges = nr_base_graph_edges(2, 2)
    checksum += UInt64(len(edges.shifts) + nr_base_graph_shift(2, 0, 0, 0))
    checksum += UInt64(nr_lifting_set_index(2) + tiny.variable_count + standard.variable_count)

    var information = _bits(20, 3)
    var full = nr_ldpc_encode_full(Span(information), 2, 2)
    var encoded = nr_ldpc_encode(Span(information), 2, 2)
    checksum += UInt64(nr_ldpc_syndrome_ok(Span(full), 2, 2))
    checksum += UInt64(nr_ldpc_k0(2, 2, 0))
    var nulls = List[UInt8](length=len(encoded), fill=UInt8(0))
    var matched = nr_ldpc_rate_match(Span(encoded), Span(nulls), 2, 2, 0, 100, 2)
    var matched_llrs = _llrs(Span(matched))
    var recovered = nr_ldpc_rate_recover(Span(matched_llrs), Span(nulls), 2, 2, 0, 2)
    checksum += UInt64(nr_ldpc_code_block_output_bits(100, 2, 1, 1, 0))
    var decoded = nr_ldpc_decode(Span(recovered), Span(nulls), 2, 2, max_iterations=4)
    checksum += UInt64(len(decoded.bits))
    checksum += nr_ldpc_crc24b(Span(payload))
    var crc24b = nr_ldpc_crc24b_append(Span(payload))
    checksum += UInt64(nr_ldpc_crc24b_check(Span(crc24b)))

    var segments = nr_ldpc_segment(Span(transport), profile)
    var desegmented = nr_ldpc_desegment(Span(segments.bits), profile)
    var blocks = nr_ldpc_encode_code_blocks(segments, profile)
    var block_matched = nr_ldpc_rate_match_code_blocks(blocks, profile, 0, 200, 2, 1)
    var block_llrs = _llrs(Span(block_matched))
    var block_recovered = nr_ldpc_rate_recover_code_blocks(
        Span(block_llrs), Span(blocks.null_mask), profile, 0, 2, 1
    )
    var block_decoded = nr_ldpc_decode_code_blocks(
        Span(block_recovered), Span(blocks.null_mask), profile, max_iterations=4
    )
    checksum += UInt64(len(profile_filler) + len(desegmented.bits) + len(block_decoded.bits))
    keep(profile_filler); keep(tiny); keep(standard); keep(edges)
    keep(full); keep(encoded); keep(matched); keep(recovered); keep(decoded)
    keep(crc24b); keep(segments); keep(desegmented); keep(blocks)
    keep(block_matched); keep(block_recovered); keep(block_decoded)
    return checksum


@no_inline
def _nr_pdsch_grid_chain_once() raises -> UInt64:
    var checksum = UInt64(0)
    var payload = _bits(32, 1)
    var pss = nr_pss(2)
    var sss = nr_sss(17, 2)

    checksum += UInt64(nr_normal_cp_samples(2048, 0, 0))
    var c_init = nr_pdsch_dmrs_c_init(3, 2, 42, 0)
    var grid = NRResourceGrid(4, 256)
    var data = List[Complex64](length=5, fill=Complex64(1.0, -1.0))
    var dmrs = nr_pdsch_dmrs(c_init, 6)
    nr_map_pdsch_comb2(grid, 1, 4, 11, 0, Span(data), Span(dmrs))
    var extracted_data = nr_extract_pdsch_comb2(grid, 1, 4, 11, 0)
    var extracted_dmrs = nr_extract_dmrs_comb2(grid, 1, 4, 11, 0)
    var channel = nr_ls_channel_estimate_comb2(Span(extracted_dmrs), Span(dmrs), 11, 0)
    var equalized = nr_equalize_pdsch_comb2(Span(extracted_data), Span(channel), 0)
    nr_map_ssb_synchronization(grid, 8, Span(pss), Span(sss))
    var samples = List[Complex64](capacity=127)
    for value in pss:
        samples.append(Complex64(value, 0.0))
    var pss_detection = nr_search_pss(Span(samples))
    samples = List[Complex64](capacity=127)
    for value in sss:
        samples.append(Complex64(value, 0.0))
    var sss_detection = nr_detect_sss(Span(samples), 2)
    checksum += UInt64(len(equalized) + pss_detection.n_id_2 + sss_detection.physical_cell_id)

    var tx = nr_pdsch_encode_transport_block(Span(payload), 0.5, 2, 0, 240, 0x1234, 0, 42)
    var chain_dmrs = nr_pdsch_dmrs(c_init, 120)
    var chain_grid = NRResourceGrid(1, 256)
    nr_map_pdsch_comb2(chain_grid, 0, 0, 240, 0, Span(tx.symbols), Span(chain_dmrs))
    var rx = nr_pdsch_decode_grid_comb2(
        chain_grid, 0, 0, 240, 0, Span(chain_dmrs), Span(tx.encoded_null_mask),
        tx.profile, len(payload), 2, 0, 0x1234, 0, 42, 0.01,
    )
    checksum += UInt64(len(rx.payload))
    keep(dmrs); keep(grid); keep(extracted_data); keep(extracted_dmrs)
    keep(channel); keep(equalized); keep(pss); keep(sss)
    keep(pss_detection); keep(sss_detection); keep(tx); keep(chain_dmrs)
    keep(chain_grid); keep(rx)
    return checksum


def _sequences_pdsch_ldpc_once() raises -> UInt64:
    return (
        _nr_sequence_transport_once()
        ^ _nr_ldpc_once()
        ^ _nr_pdsch_grid_chain_once()
    )


def _nr_pucch_base_sequences_once() raises -> UInt64:
    var checksum = UInt64(nr_pucch_group_neither(77))
    var hopping = nr_pucch_group_sequence_hopping(3, 0, 0, 77, PUCCH_GROUP_HOPPING_ENABLE)
    checksum += UInt64(hopping.group + hopping.sequence_number)
    var alpha = nr_pucch_cyclic_shift_index(3, 2, 1, 2, 77)
    var low = nr_pucch_low_papr_sequence_12(17, alpha)
    var f0 = nr_pucch_format0_sequence(17, alpha)
    var bits2: List[UInt8] = [1, 0]
    var f1 = nr_pucch_format1_sequence(Span(bits2), 17, alpha)
    var bits = _bits(16, 2)
    var scrambled = nr_pucch_scramble(Span(bits), 0x1234, 77)
    var f2 = nr_pucch_format2_modulate(Span(bits), 0x1234, 77)
    var pi2 = nr_pi_over_2_bpsk(Span(bits))
    var f34 = nr_pucch_format3_4_modulate(Span(bits), 0x1234, 77)
    var spread = nr_pucch_block_spread(Span(f34), 2, 1)
    var despread = nr_pucch_block_despread(Span(spread), 2, 1)
    checksum += UInt64(len(low)+len(f0)+len(f1)+len(scrambled)+len(f2)+len(pi2)+len(despread))
    keep(hopping); keep(low); keep(f0); keep(f1); keep(scrambled)
    keep(f2); keep(pi2); keep(f34); keep(spread); keep(despread)
    return checksum


def _nr_pucch_format1_resources_once() raises -> UInt64:
    var checksum = UInt64(0)
    var alpha = nr_pucch_cyclic_shift_index(3, 2, 1, 2, 77)
    var bits2: List[UInt8] = [1, 0]
    var f1 = nr_pucch_format1_sequence(Span(bits2), 17, alpha)

    checksum += UInt64(nr_pucch_format1_data_occ_length(7))
    checksum += UInt64(nr_pucch_format1_dmrs_occ_length(7))
    var phases = nr_pucch_format1_occ_phases(3, 1)
    var occ = nr_pucch_format1_occ(3, 1)
    var data_occ = nr_pucch_format1_data_occ(7, 1)
    var dmrs_occ = nr_pucch_format1_dmrs_occ(7, 1)
    var applied = nr_pucch_format1_apply_occ(Span(f1), Span(occ))
    checksum += UInt64(len(phases)+len(data_occ)+len(dmrs_occ)+len(applied))
    keep(f1); keep(phases); keep(occ); keep(data_occ); keep(dmrs_occ)
    keep(applied)
    return checksum


def _nr_pucch_format2_resources_once() raises -> UInt64:
    var checksum = UInt64(0)
    var bits = _bits(16, 2)
    var f2 = nr_pucch_format2_modulate(Span(bits), 0x1234, 77)

    checksum += UInt64(nr_pucch_format2_dmrs_c_init(3, 2, 77))
    var f2_dmrs = nr_pucch_format2_dmrs(3, 2, 77, 1)
    var f2_data_count = nr_pucch_format2_data_re_count(1, 1)
    var f2_dmrs_count = nr_pucch_format2_dmrs_re_count(1, 1)
    var f2_grid = NRResourceGrid(14, 64)
    nr_map_pucch_format2(f2_grid, 2, 12, 1, 1, Span(f2), Span(f2_dmrs))
    var f2_data = nr_extract_pucch_format2_data(f2_grid, 2, 12, 1, 1)
    var f2_refs = nr_extract_pucch_format2_dmrs(f2_grid, 2, 12, 1, 1)
    checksum += UInt64(f2_data_count+f2_dmrs_count+len(f2_data)+len(f2_refs))
    keep(f2); keep(f2_dmrs); keep(f2_grid); keep(f2_data); keep(f2_refs)
    return checksum


def _nr_pucch_format34_resources_once() raises -> UInt64:
    var checksum = UInt64(0)

    var positions = nr_pucch_format3_4_dmrs_positions(4)
    var dmrs_count = nr_pucch_format3_4_dmrs_re_count(4, 1)
    var data_count = nr_pucch_format3_4_data_re_count(4, 1)
    var grid34 = NRResourceGrid(14, 64)
    var data34 = List[Complex64](length=data_count, fill=Complex64(1.0))
    var refs34 = List[Complex64](length=dmrs_count, fill=Complex64(0.0, 1.0))
    nr_map_pucch_format3_4_non_interlaced(grid34, 1, 12, 1, 4, Span(data34), Span(refs34))
    var extracted34 = nr_extract_pucch_format3_4_data_non_interlaced(grid34, 1, 12, 1, 4)
    var extracted_refs34 = nr_extract_pucch_format3_4_dmrs_non_interlaced(grid34, 1, 12, 1, 4)
    checksum += UInt64(len(positions)+len(extracted34)+len(extracted_refs34))
    keep(positions); keep(grid34); keep(extracted34); keep(extracted_refs34)
    return checksum


def _pucch_resources_once() raises -> UInt64:
    return (
        _nr_pucch_base_sequences_once()
        ^ _nr_pucch_format1_resources_once()
        ^ _nr_pucch_format2_resources_once()
        ^ _nr_pucch_format34_resources_once()
    )


@no_inline
def _nr_prach_standard_once() raises -> UInt64:
    var checksum = UInt64(0)
    var format = nr_prach_format_parameters(PRACH_FORMAT_A1, numerology=0, sequence_length=139)
    checksum += UInt64(nr_prach_logical_root_count(139))
    var root_u = nr_prach_logical_root_u(0, 139)
    var root = nr_prach_root_sequence_standard(root_u, 139)
    var shifted = nr_prach_sequence_standard(root_u, 139, 2)
    var n_cs = nr_prach_n_cs(1, 139, 15000)
    checksum += UInt64(nr_prach_d_u(root_u, 139))
    var restricted = nr_prach_restricted_parameters(129, 839, 13, PRACH_SET_RESTRICTED_A)
    var shifts = nr_prach_cyclic_shifts(root_u, 139, n_cs, PRACH_SET_UNRESTRICTED)
    var allocations = nr_prach_allocate_preambles(0, 139, n_cs, PRACH_SET_UNRESTRICTED, 4)
    var preamble = nr_prach_preamble_sequence(allocations[0], 139)
    var frequency = nr_prach_frequency_sequence(Span(preamble))
    checksum += UInt64(nr_prach_normalized_cp_samples(format))
    var waveform = nr_prach_normalized_waveform(Span(preamble), format)
    var composite = nr_prach_normalized_composite(
        format,
        0,
        n_cs,
        PRACH_SET_UNRESTRICTED,
        0,
        preamble_count=4,
    )
    var detection = nr_detect_prach_multi_root(Span(preamble), 0, n_cs, PRACH_SET_UNRESTRICTED, 4)
    var occasion = nr_prach_representative_occasion(PRACH_REGION_FR1, PRACH_SPECTRUM_PAIRED, 0)
    checksum += UInt64(nr_prach_occasion_is_active(occasion, 1, 1))
    checksum += UInt64(len(root)+len(shifted)+restricted.count()+len(shifts)+len(frequency)+len(waveform)+len(composite.normalized_waveform)+detection.preamble_index+composite.detection.preamble_index)
    keep(format); keep(root); keep(shifted); keep(restricted); keep(shifts)
    keep(allocations); keep(preamble); keep(frequency); keep(waveform)
    keep(composite)
    keep(detection); keep(occasion)
    return checksum


def _nr_pbch_chain_once() raises -> UInt64:
    var checksum = UInt64(0)

    var mib = _bits(24, 0)
    # Match the six MIB SFN MSBs to SFN 0.
    for i in range(6):
        mib[i] = 0
    var pbch_payload = nr_pbch_build_payload(Span(mib), 0, 0, 1, 4)
    var interleaved = nr_pbch_payload_interleave(Span(pbch_payload))
    var deinterleaved = nr_pbch_payload_deinterleave(Span(interleaved))
    var payload_scrambled = nr_pbch_payload_scramble(Span(interleaved), 42, 0, 4)
    var payload_descrambled = nr_pbch_payload_descramble(Span(payload_scrambled), 42, 4)
    checksum += nr_pbch_crc24c(Span(pbch_payload))
    var crc = nr_pbch_crc24c_append(Span(pbch_payload))
    checksum += UInt64(nr_pbch_crc24c_check(Span(crc)))
    var physical = nr_pbch_physical_scramble(Span(crc), 42, 1, 4)
    var physical_llrs = _llrs(Span(physical))
    var physical_soft = nr_pbch_physical_descramble_llrs(Span(physical_llrs), 42, 1, 4)
    var pbch_tx = nr_pbch_encode(Span(mib), 42, 0, 0, 1, 4)
    var pbch_llrs = _llrs(Span(pbch_tx.physical_channel_bits))
    var pbch_rx = nr_pbch_decode(Span(pbch_llrs), 42, 1, 4)
    checksum += UInt64(len(deinterleaved)+len(payload_descrambled)+len(physical_soft)+len(pbch_rx.payload))
    keep(pbch_payload); keep(interleaved); keep(deinterleaved)
    keep(payload_scrambled); keep(payload_descrambled); keep(crc)
    keep(physical); keep(physical_soft); keep(pbch_tx); keep(pbch_rx)
    return checksum


def _nr_ptrs_once() raises -> UInt64:
    var checksum = UInt64(0)

    var density = nr_pdsch_ptrs_density_from_thresholds(12, 12, 5, 10, 15, 29, 4, 12)
    checksum += UInt64(nr_pdsch_ptrs_c_init(3, 2, 42, 0))
    var dmrs_symbols: List[Int] = [2, 11]
    var times = nr_pdsch_ptrs_time_positions(14, 2, Span(dmrs_symbols))
    checksum += UInt64(nr_pdsch_ptrs_k_ref_re(1000, 1, 2))
    var frequencies = nr_pdsch_ptrs_frequency_positions(10, 0x1234, 4, 1000, 1, 2)
    var references = nr_pdsch_ptrs_sequence(Span(frequencies), 0, 3, 2, 42, 0, 1000, 1)
    var ptrs_grid = NRResourceGrid(14, 128)
    nr_map_pdsch_ptrs(ptrs_grid, 0, 0, Span(times), Span(frequencies), Span(references))
    var extracted = nr_extract_pdsch_ptrs(ptrs_grid, 0, 0, Span(times), Span(frequencies))
    var estimate = nr_ptrs_estimate_common_phase(Span(extracted), Span(references), Span(times))
    var corrected = nr_ptrs_correct_common_phase(Span(extracted), 0.1)
    checksum += UInt64(density.time_density+len(estimate.phase_radians)+len(corrected))
    keep(density); keep(times); keep(frequencies); keep(references)
    keep(ptrs_grid); keep(extracted); keep(estimate); keep(corrected)
    return checksum


def _prach_pbch_ptrs_once() raises -> UInt64:
    return _nr_prach_standard_once() ^ _nr_pbch_chain_once() ^ _nr_ptrs_once()


def _nr_pusch_primitives_once() raises -> UInt64:
    var checksum = UInt64(0)
    var bits = _bits(32, 5)
    var pusch_scrambled = nr_pusch_scramble(Span(bits), 0x1234, 0, 42)
    var soft = _llrs(Span(pusch_scrambled))
    var pusch_soft = nr_pusch_descramble_llrs(Span(soft), 0x1234, 0, 42)
    var symbols = List[Complex64](length=12, fill=Complex64(1.0, -0.5))
    var precoded = nr_pusch_transform_precoding(Span(symbols))
    var deprecoded = nr_pusch_transform_deprecoding(Span(precoded))
    checksum += UInt64(nr_pusch_dmrs_c_init(3, 2, 42, 0))
    var pusch_dmrs = nr_pusch_dmrs(3, 2, 42, 0, 6)
    checksum += UInt64(len(pusch_soft)+len(deprecoded)+len(pusch_dmrs))
    keep(pusch_scrambled); keep(pusch_soft); keep(precoded); keep(deprecoded)
    keep(pusch_dmrs)
    return checksum


def _nr_prach_legacy_once() raises -> UInt64:
    var checksum = UInt64(0)
    var prach_root = nr_prach_root_sequence(1, 139)
    var prach = nr_prach_sequence(1, 139, 13)
    checksum += UInt64(nr_prach_unrestricted_cyclic_shift(1, 13, 139))
    var prach_detection = nr_detect_prach_unrestricted(Span(prach), 1, 13, 4)
    checksum += UInt64(len(prach_root)+prach_detection.preamble_index)
    keep(prach_root); keep(prach); keep(prach_detection)
    return checksum


@no_inline
def _nr_pusch_chain_once() raises -> UInt64:
    var checksum = UInt64(0)

    var config = NRPUSCHConfig(64, 8, 5, 2, 8, 2, 3, 42, 0, 0x1234)
    checksum += UInt64(nr_pusch_allocation_subcarriers(config))
    checksum += UInt64(nr_pusch_data_re_count(config))
    checksum += UInt64(nr_pusch_coded_bit_capacity(config, 2))
    var dmrs = nr_pusch_reference_dmrs(config)
    var mapped_data = List[Complex64](length=nr_pusch_data_re_count(config), fill=Complex64(1.0))
    var grid = nr_map_pusch_single_layer(config, Span(mapped_data), Span(dmrs))
    var waveform = nr_pusch_grid_to_waveform(config, grid)
    var recovered_grid = nr_pusch_waveform_to_grid(config, Span(waveform))
    var tx_payload = _bits(32, 3)
    var tx = nr_pusch_encode_transport_block(Span(tx_payload), 0.5, 2, 0, config)
    var rx = nr_pusch_decode_waveform(
        Span(tx.waveform), config, Span(tx.encoded_null_mask), tx.profile,
        len(tx_payload), 2, 0, 0.01,
    )
    checksum += UInt64(recovered_grid.symbol_count+len(rx.payload))
    keep(dmrs); keep(mapped_data); keep(grid); keep(waveform)
    keep(recovered_grid); keep(tx); keep(rx)
    return checksum


def _nr_uci_once() raises -> UInt64:
    var checksum = UInt64(0)

    checksum += UInt64(nr_uci_crc_length(12)+nr_uci_code_block_count(12, 32))
    checksum += UInt64(nr_pucch_uci_capacity(2, 1, 1))
    var uci_payload = _bits(7, 1)
    var uci = nr_uci_encode(Span(uci_payload), 16)
    var uci_llrs = _llrs(Span(uci.bits))
    var uci_rx = nr_uci_decode(Span(uci_llrs), len(uci_payload))
    checksum += UInt64(len(uci_rx.bits))
    keep(uci); keep(uci_rx)
    return checksum


def _nr_pucch_format2_chain_once() raises -> UInt64:
    var checksum = UInt64(0)
    var uci_payload = _bits(7, 1)

    var pucch_config = NRPUCCHFormat2Config(128, 0, 7, 9, 1, 24, 73, 321, 0x1234)
    checksum += UInt64(nr_pucch_format2_coded_bit_capacity(pucch_config))
    checksum += nr_pucch_format2_bits_checksum(Span(uci_payload))
    var pucch_dmrs = nr_pucch_format2_reference_dmrs(pucch_config)
    checksum += UInt64(nr_pucch_format2_waveform_sample_count(pucch_config))
    var pucch_tx = nr_pucch_format2_encode(Span(uci_payload), pucch_config)
    var direct_waveform = nr_pucch_format2_grid_to_waveform(pucch_config, pucch_tx.grid)
    var direct_grid = nr_pucch_format2_waveform_to_grid(pucch_config, Span(direct_waveform))
    var received = nr_pucch_format2_flat_channel(Span(pucch_tx.waveform), Complex64(0.8, 0.2), seed=UInt64(7))
    var raw_llrs = _llrs(Span(pucch_tx.scrambled_bits))
    var descrambled_llrs = nr_pucch_format2_descramble_llrs(Span(raw_llrs), pucch_config.rnti, pucch_config.n_id)
    var pucch_rx = nr_pucch_format2_decode(Span(received), pucch_config, len(uci_payload), 0.0)
    checksum += UInt64(len(pucch_dmrs)+direct_grid.symbol_count+len(descrambled_llrs)+len(pucch_rx.payload))
    keep(pucch_dmrs); keep(pucch_tx); keep(direct_waveform); keep(direct_grid)
    keep(received); keep(descrambled_llrs); keep(pucch_rx)
    return checksum


def _uplink_uci_chains_once() raises -> UInt64:
    return (
        _nr_pusch_primitives_once()
        ^ _nr_prach_legacy_once()
        ^ _nr_pusch_chain_once()
        ^ _nr_uci_once()
        ^ _nr_pucch_format2_chain_once()
    )


def _run_legacy_benchmarks() raises:
    for _ in range(_WARMUPS):
        keep(_nr_sequence_transport_once())
        keep(_nr_ldpc_once())
        keep(_nr_pdsch_grid_chain_once())
        keep(_nr_pucch_base_sequences_once())
        keep(_nr_pucch_format1_resources_once())
        keep(_nr_pucch_format2_resources_once())
        keep(_nr_pucch_format34_resources_once())
        keep(_nr_prach_standard_once())
        keep(_nr_pbch_chain_once())
        keep(_nr_ptrs_once())
        keep(_nr_pusch_primitives_once())
        keep(_nr_prach_legacy_once())
        keep(_nr_pusch_chain_once())
        keep(_nr_uci_once())
        keep(_nr_pucch_format2_chain_once())

    var sequence_samples = List[UInt64](capacity=_SAMPLES)
    var ldpc_samples = List[UInt64](capacity=_SAMPLES)
    var pdsch_samples = List[UInt64](capacity=_SAMPLES)
    var pucch_base_samples = List[UInt64](capacity=_SAMPLES)
    var pucch_f1_samples = List[UInt64](capacity=_SAMPLES)
    var pucch_f2_samples = List[UInt64](capacity=_SAMPLES)
    var pucch_f34_samples = List[UInt64](capacity=_SAMPLES)
    var prach_samples = List[UInt64](capacity=_SAMPLES)
    var pbch_samples = List[UInt64](capacity=_SAMPLES)
    var ptrs_samples = List[UInt64](capacity=_SAMPLES)
    var pusch_primitive_samples = List[UInt64](capacity=_SAMPLES)
    var prach_legacy_samples = List[UInt64](capacity=_SAMPLES)
    var pusch_chain_samples = List[UInt64](capacity=_SAMPLES)
    var uci_samples = List[UInt64](capacity=_SAMPLES)
    var pucch_chain_samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(0)
    for repetition in range(_SAMPLES):
        var start = global_perf_counter_ns()
        var retained = _nr_sequence_transport_once()
        sequence_samples.append(global_perf_counter_ns() - start)
        keep(retained)
        checksum ^= retained + UInt64(repetition)

        start = global_perf_counter_ns()
        retained = _nr_ldpc_once()
        ldpc_samples.append(global_perf_counter_ns() - start)
        keep(retained)
        checksum ^= retained + UInt64(3 * repetition)

        start = global_perf_counter_ns()
        retained = _nr_pdsch_grid_chain_once()
        pdsch_samples.append(global_perf_counter_ns() - start)
        keep(retained)
        checksum ^= retained + UInt64(5 * repetition)

        start = global_perf_counter_ns()
        retained = _nr_pucch_base_sequences_once()
        pucch_base_samples.append(global_perf_counter_ns() - start)
        keep(retained)
        checksum ^= retained + UInt64(7 * repetition)

        start = global_perf_counter_ns()
        retained = _nr_pucch_format1_resources_once()
        pucch_f1_samples.append(global_perf_counter_ns() - start)
        keep(retained); checksum ^= retained + UInt64(11 * repetition)

        start = global_perf_counter_ns()
        retained = _nr_pucch_format2_resources_once()
        pucch_f2_samples.append(global_perf_counter_ns() - start)
        keep(retained); checksum ^= retained + UInt64(13 * repetition)

        start = global_perf_counter_ns()
        retained = _nr_pucch_format34_resources_once()
        pucch_f34_samples.append(global_perf_counter_ns() - start)
        keep(retained); checksum ^= retained + UInt64(17 * repetition)

        start = global_perf_counter_ns()
        retained = _nr_prach_standard_once()
        prach_samples.append(global_perf_counter_ns() - start)
        keep(retained); checksum ^= retained + UInt64(19 * repetition)

        start = global_perf_counter_ns()
        retained = _nr_pbch_chain_once()
        pbch_samples.append(global_perf_counter_ns() - start)
        keep(retained); checksum ^= retained + UInt64(23 * repetition)

        start = global_perf_counter_ns()
        retained = _nr_ptrs_once()
        ptrs_samples.append(global_perf_counter_ns() - start)
        keep(retained); checksum ^= retained + UInt64(29 * repetition)

        start = global_perf_counter_ns()
        retained = _nr_pusch_primitives_once()
        pusch_primitive_samples.append(global_perf_counter_ns() - start)
        keep(retained); checksum ^= retained + UInt64(31 * repetition)

        start = global_perf_counter_ns()
        retained = _nr_prach_legacy_once()
        prach_legacy_samples.append(global_perf_counter_ns() - start)
        keep(retained); checksum ^= retained + UInt64(37 * repetition)

        start = global_perf_counter_ns()
        retained = _nr_pusch_chain_once()
        pusch_chain_samples.append(global_perf_counter_ns() - start)
        keep(retained); checksum ^= retained + UInt64(41 * repetition)

        start = global_perf_counter_ns()
        retained = _nr_uci_once()
        uci_samples.append(global_perf_counter_ns() - start)
        keep(retained); checksum ^= retained + UInt64(43 * repetition)

        start = global_perf_counter_ns()
        retained = _nr_pucch_format2_chain_once()
        pucch_chain_samples.append(global_perf_counter_ns() - start)
        keep(retained); checksum ^= retained + UInt64(47 * repetition)

    print_benchmark_metadata()
    var alignment_probe = _bits(256, 91)
    print_runtime_buffer_alignment(
        "nr_public_uint8_payload",
        Int(alignment_probe.unsafe_ptr()),
        align_of[UInt8](),
    )
    print("nr_public_api_count:", 158)
    report_timing_samples("nr_sequence_transport", sequence_samples, _WARMUPS, 14, "nr_sequence_or_transport_api_call")
    report_timing_samples("nr_ldpc_family", ldpc_samples, _WARMUPS, 26, "nr_ldpc_api_call")
    report_timing_samples("nr_pdsch_grid_chain", pdsch_samples, _WARMUPS, 15, "nr_pdsch_api_call")
    report_timing_samples("nr_pucch_base_sequences", pucch_base_samples, _WARMUPS, 12, "nr_pucch_sequence_api_call")
    report_timing_samples("nr_pucch_format1_resources", pucch_f1_samples, _WARMUPS, 8, "nr_pucch_format1_api_call")
    report_timing_samples("nr_pucch_format2_resources", pucch_f2_samples, _WARMUPS, 8, "nr_pucch_format2_resource_api_call")
    report_timing_samples("nr_pucch_format34_resources", pucch_f34_samples, _WARMUPS, 6, "nr_pucch_format34_api_call")
    report_timing_samples("nr_prach_standard", prach_samples, _WARMUPS, 19, "nr_prach_api_call")
    report_timing_samples("nr_pbch_chain", pbch_samples, _WARMUPS, 13, "nr_pbch_api_call")
    report_timing_samples("nr_ptrs_family", ptrs_samples, _WARMUPS, 11, "nr_ptrs_api_call")
    report_timing_samples("nr_pusch_primitives", pusch_primitive_samples, _WARMUPS, 6, "nr_pusch_primitive_api_call")
    report_timing_samples("nr_prach_legacy", prach_legacy_samples, _WARMUPS, 4, "nr_prach_legacy_api_call")
    report_timing_samples("nr_pusch_chain", pusch_chain_samples, _WARMUPS, 10, "nr_pusch_chain_api_call")
    report_timing_samples("nr_uci_family", uci_samples, _WARMUPS, 5, "nr_uci_api_call")
    report_timing_samples("nr_pucch_format2_chain", pucch_chain_samples, _WARMUPS, 11, "nr_pucch_chain_api_call")
    keep(checksum)
    print("nr_public_retained_checksum:", checksum)


def main() raises:
    _run_legacy_benchmarks()
    var strict_checksum = UInt64(1469598103934665603)
    strict_checksum = _mix(strict_checksum, _run_nr_gold_bits())
    strict_checksum = _mix(strict_checksum, _run_nr_qpsk_sequence())
    strict_checksum = _mix(strict_checksum, _run_nr_pss())
    strict_checksum = _mix(strict_checksum, _run_nr_sss())
    strict_checksum = _mix(strict_checksum, _run_nr_pbch_dmrs_c_init())
    strict_checksum = _mix(strict_checksum, _run_nr_pbch_dmrs())
    strict_checksum = _mix(strict_checksum, _run_nr_pdsch_scramble())
    strict_checksum = _mix(strict_checksum, _run_nr_pdsch_dmrs())
    strict_checksum = _mix(
        strict_checksum, _run_nr_pdsch_descramble_llrs()
    )
    strict_checksum = _mix(strict_checksum, _run_nr_rate_recover_llrs())
    strict_checksum = _mix(strict_checksum, _run_nr_transport_crc_width())
    strict_checksum = _mix(strict_checksum, _run_nr_transport_crc())
    strict_checksum = _mix(strict_checksum, _run_nr_transport_crc_append())
    strict_checksum = _mix(strict_checksum, _run_nr_transport_crc_check())
    strict_checksum = _mix(strict_checksum, _run_nr_pusch_scramble())
    strict_checksum = _mix(strict_checksum, _run_nr_pusch_descramble_llrs())
    strict_checksum = _mix(strict_checksum, _run_nr_pusch_transform_precoding())
    strict_checksum = _mix(strict_checksum, _run_nr_pusch_transform_deprecoding())
    strict_checksum = _mix(strict_checksum, _run_nr_pusch_dmrs_c_init())
    strict_checksum = _mix(strict_checksum, _run_nr_pusch_dmrs())
    strict_checksum = _mix(strict_checksum, _run_nr_prach_root_sequence())
    strict_checksum = _mix(strict_checksum, _run_nr_prach_sequence())
    strict_checksum = _mix(strict_checksum, _run_nr_prach_unrestricted_cyclic_shift())
    strict_checksum = _mix(strict_checksum, _run_nr_detect_prach_unrestricted())
    strict_checksum = _mix(strict_checksum, _run_nr_uci_crc_length())
    strict_checksum = _mix(strict_checksum, _run_nr_uci_code_block_count())
    strict_checksum = _mix(strict_checksum, _run_nr_pucch_uci_capacity())
    strict_checksum = _mix(strict_checksum, _run_nr_uci_encode())
    strict_checksum = _mix(strict_checksum, _run_nr_uci_decode())
    strict_checksum = _mix(strict_checksum, _run_nr_pucch_group_neither())
    strict_checksum = _mix(strict_checksum, _run_nr_pucch_group_sequence_hopping())
    strict_checksum = _mix(strict_checksum, _run_nr_pucch_cyclic_shift_index())
    strict_checksum = _mix(strict_checksum, _run_nr_pucch_low_papr_sequence_12())
    strict_checksum = _mix(strict_checksum, _run_nr_pucch_format0_sequence())
    strict_checksum = _mix(strict_checksum, _run_nr_pucch_format1_sequence())
    strict_checksum = _mix(strict_checksum, _run_nr_pucch_scramble())
    strict_checksum = _mix(strict_checksum, _run_nr_pucch_format2_modulate())
    strict_checksum = _mix(strict_checksum, _run_nr_pi_over_2_bpsk())
    strict_checksum = _mix(strict_checksum, _run_nr_pucch_format3_4_modulate())
    strict_checksum = _mix(strict_checksum, _run_nr_pucch_block_spread())
    strict_checksum = _mix(strict_checksum, _run_nr_pucch_block_despread())
    strict_checksum = _mix(strict_checksum, _run_nr_pucch_format1_data_occ_length())
    strict_checksum = _mix(strict_checksum, _run_nr_pucch_format1_dmrs_occ_length())
    strict_checksum = _mix(strict_checksum, _run_nr_pucch_format1_occ_phases())
    strict_checksum = _mix(strict_checksum, _run_nr_pucch_format1_occ())
    strict_checksum = _mix(strict_checksum, _run_nr_pucch_format1_data_occ())
    strict_checksum = _mix(strict_checksum, _run_nr_pucch_format1_dmrs_occ())
    strict_checksum = _mix(strict_checksum, _run_nr_pucch_format1_apply_occ())
    strict_checksum = _mix(strict_checksum, _run_nr_pucch_format2_dmrs_c_init())
    strict_checksum = _mix(strict_checksum, _run_nr_pucch_format2_dmrs())
    strict_checksum = _mix(strict_checksum, _run_nr_pucch_format2_data_re_count())
    strict_checksum = _mix(strict_checksum, _run_nr_pucch_format2_dmrs_re_count())
    strict_checksum = _mix(strict_checksum, _run_nr_map_pucch_format2())
    strict_checksum = _mix(strict_checksum, _run_nr_extract_pucch_format2_data())
    strict_checksum = _mix(strict_checksum, _run_nr_extract_pucch_format2_dmrs())
    strict_checksum = _mix(strict_checksum, _run_nr_pucch_format3_4_dmrs_positions())
    strict_checksum = _mix(strict_checksum, _run_nr_pucch_format3_4_dmrs_re_count())
    strict_checksum = _mix(strict_checksum, _run_nr_pucch_format3_4_data_re_count())
    strict_checksum = _mix(strict_checksum, _run_nr_map_pucch_format3_4_non_interlaced())
    strict_checksum = _mix(strict_checksum, _run_nr_extract_pucch_format3_4_data_non_interlaced())
    strict_checksum = _mix(strict_checksum, _run_nr_extract_pucch_format3_4_dmrs_non_interlaced())
    strict_checksum = _mix(strict_checksum, _run_nr_prach_format_parameters())
    strict_checksum = _mix(strict_checksum, _run_nr_prach_logical_root_count())
    strict_checksum = _mix(strict_checksum, _run_nr_prach_logical_root_u())
    strict_checksum = _mix(strict_checksum, _run_nr_prach_root_sequence_standard())
    strict_checksum = _mix(strict_checksum, _run_nr_prach_sequence_standard())
    strict_checksum = _mix(strict_checksum, _run_nr_prach_n_cs())
    strict_checksum = _mix(strict_checksum, _run_nr_prach_d_u())
    strict_checksum = _mix(strict_checksum, _run_nr_prach_restricted_parameters())
    strict_checksum = _mix(strict_checksum, _run_nr_prach_cyclic_shifts())
    strict_checksum = _mix(strict_checksum, _run_nr_prach_allocate_preambles())
    strict_checksum = _mix(strict_checksum, _run_nr_prach_preamble_sequence())
    strict_checksum = _mix(strict_checksum, _run_nr_prach_frequency_sequence())
    strict_checksum = _mix(strict_checksum, _run_nr_prach_normalized_cp_samples())
    strict_checksum = _mix(strict_checksum, _run_nr_prach_normalized_waveform())
    strict_checksum = _mix(strict_checksum, _run_nr_prach_normalized_composite())
    strict_checksum = _mix(strict_checksum, _run_nr_detect_prach_multi_root())
    strict_checksum = _mix(strict_checksum, _run_nr_prach_representative_occasion())
    strict_checksum = _mix(strict_checksum, _run_nr_prach_occasion_is_active())
    strict_checksum = _mix(strict_checksum, _run_nr_pusch_allocation_subcarriers())
    strict_checksum = _mix(strict_checksum, _run_nr_pusch_data_re_count())
    strict_checksum = _mix(strict_checksum, _run_nr_pusch_coded_bit_capacity())
    strict_checksum = _mix(strict_checksum, _run_nr_pusch_reference_dmrs())
    strict_checksum = _mix(strict_checksum, _run_nr_map_pusch_single_layer())
    strict_checksum = _mix(strict_checksum, _run_nr_pusch_grid_to_waveform())
    strict_checksum = _mix(strict_checksum, _run_nr_pusch_waveform_to_grid())
    strict_checksum = _mix(strict_checksum, _run_nr_pusch_encode_transport_block())
    strict_checksum = _mix(strict_checksum, _run_nr_pusch_decode_waveform())
    strict_checksum = _mix(strict_checksum, _run_nr_pucch_format2_coded_bit_capacity())
    strict_checksum = _mix(strict_checksum, _run_nr_pucch_format2_bits_checksum())
    strict_checksum = _mix(strict_checksum, _run_nr_pucch_format2_reference_dmrs())
    strict_checksum = _mix(strict_checksum, _run_nr_pucch_format2_waveform_sample_count())
    strict_checksum = _mix(strict_checksum, _run_nr_pucch_format2_grid_to_waveform())
    strict_checksum = _mix(strict_checksum, _run_nr_pucch_format2_waveform_to_grid())
    strict_checksum = _mix(strict_checksum, _run_nr_pucch_format2_encode())
    strict_checksum = _mix(strict_checksum, _run_nr_pucch_format2_flat_channel())
    strict_checksum = _mix(strict_checksum, _run_nr_pucch_format2_descramble_llrs())
    strict_checksum = _mix(strict_checksum, _run_nr_pucch_format2_decode())
    strict_checksum = _mix(strict_checksum, _run_nr_pdsch_ptrs_density_from_thresholds())
    strict_checksum = _mix(strict_checksum, _run_nr_pdsch_ptrs_c_init())
    strict_checksum = _mix(strict_checksum, _run_nr_pdsch_ptrs_time_positions())
    strict_checksum = _mix(strict_checksum, _run_nr_pdsch_ptrs_k_ref_re())
    strict_checksum = _mix(strict_checksum, _run_nr_pdsch_ptrs_frequency_positions())
    strict_checksum = _mix(strict_checksum, _run_nr_pdsch_ptrs_sequence())
    strict_checksum = _mix(strict_checksum, _run_nr_map_pdsch_ptrs())
    strict_checksum = _mix(strict_checksum, _run_nr_extract_pdsch_ptrs())
    strict_checksum = _mix(strict_checksum, _run_nr_ptrs_estimate_common_phase())
    strict_checksum = _mix(strict_checksum, _run_nr_ptrs_correct_common_phase())
    strict_checksum = _mix(strict_checksum, _run_nr_pbch_build_payload())
    strict_checksum = _mix(strict_checksum, _run_nr_pbch_payload_interleave())
    strict_checksum = _mix(strict_checksum, _run_nr_pbch_payload_deinterleave())
    strict_checksum = _mix(strict_checksum, _run_nr_pbch_payload_scramble())
    strict_checksum = _mix(strict_checksum, _run_nr_pbch_payload_descramble())
    strict_checksum = _mix(strict_checksum, _run_nr_pbch_crc24c())
    strict_checksum = _mix(strict_checksum, _run_nr_pbch_crc24c_append())
    strict_checksum = _mix(strict_checksum, _run_nr_pbch_crc24c_check())
    strict_checksum = _mix(strict_checksum, _run_nr_pbch_physical_scramble())
    strict_checksum = _mix(strict_checksum, _run_nr_pbch_physical_descramble_llrs())
    strict_checksum = _mix(strict_checksum, _run_nr_pbch_encode())
    strict_checksum = _mix(strict_checksum, _run_nr_pbch_decode())
    strict_checksum = _mix(strict_checksum, _run_nr_normal_cp_samples())
    strict_checksum = _mix(strict_checksum, _run_nr_pdsch_dmrs_c_init())
    strict_checksum = _mix(strict_checksum, _run_nr_map_pdsch_comb2())
    strict_checksum = _mix(strict_checksum, _run_nr_extract_pdsch_comb2())
    strict_checksum = _mix(strict_checksum, _run_nr_extract_dmrs_comb2())
    strict_checksum = _mix(strict_checksum, _run_nr_ls_channel_estimate_comb2())
    strict_checksum = _mix(strict_checksum, _run_nr_equalize_pdsch_comb2())
    strict_checksum = _mix(strict_checksum, _run_nr_map_ssb_synchronization())
    strict_checksum = _mix(strict_checksum, _run_nr_search_pss())
    strict_checksum = _mix(strict_checksum, _run_nr_detect_sss())
    strict_checksum = _mix(strict_checksum, _run_nr_pdsch_encode_transport_block())
    strict_checksum = _mix(strict_checksum, _run_nr_pdsch_decode_grid_comb2())
    strict_checksum = _mix(strict_checksum, _run_nr_select_base_graph())
    strict_checksum = _mix(strict_checksum, _run_nr_ldpc_profile())
    strict_checksum = _mix(strict_checksum, _run_nr_ldpc_filler_mask())
    strict_checksum = _mix(strict_checksum, _run_nr_qc_expand_edges())
    strict_checksum = _mix(strict_checksum, _run_nr_standard_qc_graph())
    strict_checksum = _mix(strict_checksum, _run_nr_base_graph_dimensions())
    strict_checksum = _mix(strict_checksum, _run_nr_base_graph_edge_count())
    strict_checksum = _mix(strict_checksum, _run_nr_base_graph_edges())
    strict_checksum = _mix(strict_checksum, _run_nr_base_graph_shift())
    strict_checksum = _mix(strict_checksum, _run_nr_lifting_set_index())
    strict_checksum = _mix(strict_checksum, _run_nr_ldpc_encode_full())
    strict_checksum = _mix(strict_checksum, _run_nr_ldpc_encode())
    strict_checksum = _mix(strict_checksum, _run_nr_ldpc_syndrome_ok())
    strict_checksum = _mix(strict_checksum, _run_nr_ldpc_k0())
    strict_checksum = _mix(strict_checksum, _run_nr_ldpc_rate_match())
    strict_checksum = _mix(strict_checksum, _run_nr_ldpc_rate_recover())
    strict_checksum = _mix(strict_checksum, _run_nr_ldpc_code_block_output_bits())
    strict_checksum = _mix(strict_checksum, _run_nr_ldpc_decode())
    strict_checksum = _mix(strict_checksum, _run_nr_ldpc_crc24b())
    strict_checksum = _mix(strict_checksum, _run_nr_ldpc_crc24b_append())
    strict_checksum = _mix(strict_checksum, _run_nr_ldpc_crc24b_check())
    strict_checksum = _mix(strict_checksum, _run_nr_ldpc_segment())
    strict_checksum = _mix(strict_checksum, _run_nr_ldpc_desegment())
    strict_checksum = _mix(strict_checksum, _run_nr_ldpc_encode_code_blocks())
    strict_checksum = _mix(strict_checksum, _run_nr_ldpc_rate_match_code_blocks())
    strict_checksum = _mix(strict_checksum, _run_nr_ldpc_rate_recover_code_blocks())
    strict_checksum = _mix(strict_checksum, _run_nr_ldpc_decode_code_blocks())
    keep(strict_checksum)
    print("nr_public_strict_retained_checksum:", strict_checksum)
