"""Warmup, repeated timing, and retained checksums for all Wi-Fi public kernels."""

from std.benchmark import keep
from std.collections import Span
from std.math import cos, sin
from std.sys.info import align_of
from std.time import global_perf_counter_ns
from wireless_dsp.benchmarking import (
    print_benchmark_metadata,
    print_runtime_buffer_alignment,
    report_timing_samples,
)
from wireless_dsp.core import Complex64
from wireless_dsp.channel import apply_cfo
from wireless_dsp.wireless.wifi import (
    WIFI_PHY_HT, WIFI_PHY_VHT, WIFI_PHY_HE, WIFI_PHY_EHT,
    WifiMCSProfile, WifiOFDMProfile, WifiRUProfile,
    WifiBCCInterleaverProfile, WifiPilotPhaseEstimate, WifiLDPCProfile,
    wifi_scramble, wifi_interleave, wifi_deinterleave,
    wifi_data_subcarriers, wifi_map_legacy_symbol,
    wifi_extract_legacy_symbol, wifi_ls_channel_estimate, wifi_equalize,
    wifi_stf_detect, wifi_stf_coarse_cfo, wifi_pilot_polarity,
    wifi_legacy_signal_bits, wifi_parse_legacy_signal, wifi_fcs,
    wifi_mcs_profile, wifi_ofdm_profile, wifi_guard_interval_samples,
    wifi_coded_bits_per_symbol, wifi_data_bits_per_symbol,
    wifi_ru_profile, wifi_max_ru_count, wifi_ru_coded_bits_per_symbol,
    wifi_ru_data_bits_per_symbol, wifi_ru_requires_ldpc,
    wifi_ru_subcarriers_20mhz, wifi_ru_pilot_subcarriers_20mhz,
    wifi_ru_data_subcarriers_20mhz, wifi_ru_allocations_disjoint_20mhz,
    wifi_map_ru_symbol_20mhz, wifi_extract_ru_data_20mhz,
    wifi_extract_ru_pilots_20mhz, wifi_bcc_puncture_pattern,
    wifi_bcc_puncture, wifi_bcc_depuncture_llrs,
    wifi_bcc_interleaver_profile, wifi_bcc_interleave_block,
    wifi_bcc_deinterleave_block, wifi_estimate_pilot_phase,
    wifi_correct_pilot_phase, wifi_ldpc_profile, wifi_ldpc_base_shifts,
    wifi_ldpc_sparse_graph, wifi_ldpc_syndrome_ok, wifi_ldpc_encode,
    wifi_ldpc_decode, wifi_ldpc_rate_match_block,
    wifi_ldpc_rate_recover_block, wifi_ltf_values_20mhz,
    wifi_ltf_spectrum_20mhz, wifi_ltf_waveform_20mhz,
    wifi_ltf_channel_estimate_20mhz, wifi_data_pilot_subcarriers_20mhz,
    wifi_data_pilots_20mhz, wifi_ht_vht_data_subcarriers_20mhz,
    wifi_map_ht_vht_symbol_20mhz, wifi_extract_ht_vht_data_20mhz,
    wifi_extract_ht_vht_pilots_20mhz, wifi_ldpc_tone_mapping_distance,
    wifi_ldpc_tone_permutation, wifi_ldpc_tone_map_bits,
    wifi_ldpc_tone_demap_llrs, wifi_bcc_tx_20mhz, wifi_bcc_rx_20mhz,
    wifi_ldpc_tx_20mhz, wifi_ldpc_rx_20mhz, wifi_stf_spectrum_20mhz,
    wifi_stf_short_symbol_20mhz, wifi_stf_waveform_20mhz,
    wifi_legacy_signal_tx_20mhz, wifi_acquisition_tx_20mhz,
    WifiAcquisitionChannelConfig, wifi_acquisition_apply_channel_20mhz,
    wifi_ltf_fine_timing_20mhz, wifi_ltf_fine_cfo_20mhz,
    wifi_acquisition_rx_20mhz,
)


comptime _WARMUPS = 3
comptime _SAMPLES = 9


def _bits(count: Int, salt: Int) -> List[UInt8]:
    var result = List[UInt8](capacity=count)
    for i in range(count):
        result.append(UInt8((17 * i + i // 3 + salt) & 1))
    return result^


def _flat_ltf(family: Int) raises -> List[Complex64]:
    var source = wifi_ltf_waveform_20mhz(family)
    var result = List[Complex64](capacity=len(source))
    for value in source:
        result.append(value * Complex64(0.91, -0.17))
    return result^


@no_inline
def _wifi_data_subcarriers_workload() -> Float64:
    var result = wifi_data_subcarriers()
    keep(result)
    return Float64(result[7])


@no_inline
def _wifi_pilot_polarity_workload(symbol_index: Int) raises -> Float64:
    var result = wifi_pilot_polarity(symbol_index)
    keep(result)
    return result


@no_inline
def _wifi_mcs_profile_workload() raises -> Float64:
    var result = wifi_mcs_profile(WIFI_PHY_EHT, 13)
    keep(result)
    return Float64(result.bits_per_subcarrier + result.code_rate_numerator)


@no_inline
def _wifi_ofdm_profile_workload() raises -> Float64:
    var result = wifi_ofdm_profile(WIFI_PHY_EHT, 320)
    keep(result)
    return Float64(result.fft_size + result.data_subcarriers)


@no_inline
def _wifi_ru_profile_workload() raises -> Float64:
    var result = wifi_ru_profile(WIFI_PHY_HE, 106)
    keep(result)
    return Float64(result.data_subcarriers + result.pilot_subcarriers)


@no_inline
def _wifi_max_ru_count_workload() raises -> Float64:
    var result = wifi_max_ru_count(WIFI_PHY_HE, 80, 26)
    keep(result)
    return Float64(result)


@no_inline
def _wifi_ru_subcarriers_20mhz_workload() raises -> Float64:
    var result = wifi_ru_subcarriers_20mhz(106, 1)
    keep(result)
    return Float64(result[7])


@no_inline
def _wifi_ru_pilot_subcarriers_20mhz_workload() raises -> Float64:
    var result = wifi_ru_pilot_subcarriers_20mhz(106, 1)
    keep(result)
    return Float64(result[1])


@no_inline
def _wifi_ru_data_subcarriers_20mhz_workload() raises -> Float64:
    var result = wifi_ru_data_subcarriers_20mhz(106, 1)
    keep(result)
    return Float64(result[19])


@no_inline
def _wifi_bcc_puncture_pattern_workload() raises -> Float64:
    var result = wifi_bcc_puncture_pattern(3, 4)
    keep(result)
    return Float64(result[0])


@no_inline
def _wifi_bcc_interleaver_profile_workload() raises -> Float64:
    var result = wifi_bcc_interleaver_profile(WIFI_PHY_HT, 20)
    keep(result)
    return Float64(result.block_data_subcarriers + result.columns)


@no_inline
def _wifi_ltf_values_20mhz_workload() raises -> Float64:
    var result = wifi_ltf_values_20mhz(WIFI_PHY_EHT)
    keep(result)
    return Float64(result[7])


@no_inline
def _wifi_ltf_spectrum_20mhz_workload() raises -> Float64:
    var result = wifi_ltf_spectrum_20mhz(WIFI_PHY_EHT)
    keep(result)
    return result[40].re


@no_inline
def _wifi_ltf_waveform_20mhz_workload() raises -> Float64:
    var result = wifi_ltf_waveform_20mhz(WIFI_PHY_EHT)
    keep(result)
    return result[19].im


@no_inline
def _wifi_data_pilot_subcarriers_20mhz_workload() raises -> Float64:
    var result = wifi_data_pilot_subcarriers_20mhz(WIFI_PHY_EHT)
    keep(result)
    return Float64(result[0])


@no_inline
def _wifi_data_pilots_20mhz_workload(symbol_index: Int) raises -> Float64:
    var result = wifi_data_pilots_20mhz(WIFI_PHY_EHT, symbol_index)
    keep(result)
    return result[0].re


@no_inline
def _wifi_ht_vht_data_subcarriers_20mhz_workload() raises -> Float64:
    var result = wifi_ht_vht_data_subcarriers_20mhz(WIFI_PHY_VHT)
    keep(result)
    return Float64(result[17])


@no_inline
def _wifi_ldpc_tone_mapping_distance_workload() raises -> Float64:
    var result = wifi_ldpc_tone_mapping_distance(242)
    keep(result)
    return Float64(result)


@no_inline
def _wifi_ldpc_tone_permutation_workload(distance: Int) raises -> Float64:
    var result = wifi_ldpc_tone_permutation(234, distance)
    keep(result)
    return Float64(result[25])


@no_inline
def _wifi_stf_spectrum_20mhz_workload() -> Float64:
    var result = wifi_stf_spectrum_20mhz()
    keep(result)
    return result[40].re


@no_inline
def _wifi_stf_short_symbol_20mhz_workload() raises -> Float64:
    var result = wifi_stf_short_symbol_20mhz()
    keep(result)
    return result[7].im


@no_inline
def _wifi_stf_waveform_20mhz_workload() raises -> Float64:
    var result = wifi_stf_waveform_20mhz()
    keep(result)
    return result[71].re


@no_inline
def _wifi_legacy_signal_tx_20mhz_workload() raises -> Float64:
    var result = wifi_legacy_signal_tx_20mhz(13)
    keep(result)
    return Float64(result.bits[7]) + result.waveform[39].im


@no_inline
def _wifi_scramble_workload(bits: Span[UInt8, ...]) raises -> Float64:
    var result = wifi_scramble(bits, UInt8(0x5D))
    keep(result)
    return Float64(result[31])


@no_inline
def _wifi_interleave_workload(bits: Span[UInt8, ...]) raises -> Float64:
    var result = wifi_interleave(bits, 6)
    keep(result)
    return Float64(result[79])


@no_inline
def _wifi_deinterleave_workload(bits: Span[UInt8, ...]) raises -> Float64:
    var result = wifi_deinterleave(bits, 6)
    keep(result)
    return Float64(result[143])


@no_inline
def _wifi_map_legacy_symbol_workload(
    data: Span[Complex64, ...]
) raises -> Float64:
    var result = wifi_map_legacy_symbol(data, symbol_index=5)
    keep(result)
    return result[17].im


@no_inline
def _wifi_extract_legacy_symbol_workload(
    waveform: Span[Complex64, ...]
) raises -> Float64:
    var result = wifi_extract_legacy_symbol(waveform)
    keep(result)
    return result[7].re


@no_inline
def _wifi_ls_channel_estimate_workload(
    received: Span[Complex64, ...], known: Span[Complex64, ...]
) raises -> Float64:
    var result = wifi_ls_channel_estimate(received, known)
    keep(result)
    return result[0].re


@no_inline
def _wifi_equalize_workload(
    received: Span[Complex64, ...], estimate: Span[Complex64, ...]
) raises -> Float64:
    var result = wifi_equalize(received, estimate)
    keep(result)
    return result[1].im


@no_inline
def _wifi_stf_detect_workload(
    samples: Span[Complex64, ...]
) raises -> Float64:
    var result = wifi_stf_detect(samples, 0.8)
    keep(result)
    return Float64(result)


@no_inline
def _wifi_stf_coarse_cfo_workload(
    samples: Span[Complex64, ...], offset: Int
) raises -> Float64:
    var result = wifi_stf_coarse_cfo(samples, offset)
    keep(result)
    return result


@no_inline
def _wifi_legacy_signal_bits_workload(
    rate: Span[UInt8, ...]
) raises -> Float64:
    var result = wifi_legacy_signal_bits(rate, 132)
    keep(result)
    return Float64(result[7])


@no_inline
def _wifi_parse_legacy_signal_workload(
    bits: Span[UInt8, ...]
) raises -> Float64:
    var result = wifi_parse_legacy_signal(bits)
    keep(result)
    return Float64(result.length_octets)


@no_inline
def _wifi_fcs_workload(bits: Span[UInt8, ...]) raises -> Float64:
    var result = wifi_fcs(bits)
    keep(result)
    return Float64(result & UInt64(0xFFFF))


@no_inline
def _wifi_guard_interval_samples_workload(
    profile: WifiOFDMProfile
) raises -> Float64:
    var result = wifi_guard_interval_samples(profile, 800)
    keep(result)
    return Float64(result)


@no_inline
def _wifi_coded_bits_per_symbol_workload(
    profile: WifiOFDMProfile, mcs: WifiMCSProfile
) raises -> Float64:
    var result = wifi_coded_bits_per_symbol(profile, mcs)
    keep(result)
    return Float64(result)


@no_inline
def _wifi_data_bits_per_symbol_workload(
    profile: WifiOFDMProfile, mcs: WifiMCSProfile
) raises -> Float64:
    var result = wifi_data_bits_per_symbol(profile, mcs)
    keep(result)
    return Float64(result)


@no_inline
def _wifi_ru_coded_bits_per_symbol_workload(
    profile: WifiRUProfile, mcs: WifiMCSProfile
) raises -> Float64:
    var result = wifi_ru_coded_bits_per_symbol(profile, mcs)
    keep(result)
    return Float64(result)


@no_inline
def _wifi_ru_data_bits_per_symbol_workload(
    profile: WifiRUProfile, mcs: WifiMCSProfile
) raises -> Float64:
    var result = wifi_ru_data_bits_per_symbol(profile, mcs)
    keep(result)
    return Float64(result)


@no_inline
def _wifi_ru_requires_ldpc_workload(
    profile: WifiRUProfile, mcs: WifiMCSProfile
) raises -> Float64:
    var result = wifi_ru_requires_ldpc(profile, mcs)
    keep(result)
    return Float64(result)


@no_inline
def _wifi_ru_allocations_disjoint_20mhz_workload(
    sizes: Span[Int, ...], indices: Span[Int, ...]
) raises -> Float64:
    var result = wifi_ru_allocations_disjoint_20mhz(sizes, indices)
    keep(result)
    return Float64(result)


@no_inline
def _wifi_map_ru_symbol_20mhz_workload(
    data: Span[Complex64, ...], pilots: Span[Complex64, ...]
) raises -> Float64:
    var result = wifi_map_ru_symbol_20mhz(data, pilots, 106, 1)
    keep(result)
    return result[13].im


@no_inline
def _wifi_extract_ru_data_20mhz_workload(
    spectrum: Span[Complex64, ...]
) raises -> Float64:
    var result = wifi_extract_ru_data_20mhz(spectrum, 106, 1)
    keep(result)
    return result[41].re


@no_inline
def _wifi_extract_ru_pilots_20mhz_workload(
    spectrum: Span[Complex64, ...]
) raises -> Float64:
    var result = wifi_extract_ru_pilots_20mhz(spectrum, 106, 1)
    keep(result)
    return result[2].re


@no_inline
def _wifi_bcc_puncture_workload(
    bits: Span[UInt8, ...]
) raises -> Float64:
    var result = wifi_bcc_puncture(bits, 3, 4)
    keep(result)
    return Float64(result[31])


@no_inline
def _wifi_bcc_depuncture_llrs_workload(
    llrs: Span[Float64, ...], mother_length: Int
) raises -> Float64:
    var result = wifi_bcc_depuncture_llrs(llrs, mother_length, 3, 4)
    keep(result)
    return result[79]


@no_inline
def _wifi_bcc_interleave_block_workload(
    bits: Span[UInt8, ...], profile: WifiBCCInterleaverProfile
) raises -> Float64:
    var result = wifi_bcc_interleave_block(bits, 6, profile)
    keep(result)
    return Float64(result[73])


@no_inline
def _wifi_bcc_deinterleave_block_workload(
    bits: Span[UInt8, ...], profile: WifiBCCInterleaverProfile
) raises -> Float64:
    var result = wifi_bcc_deinterleave_block(bits, 6, profile)
    keep(result)
    return Float64(result[151])


@no_inline
def _wifi_estimate_pilot_phase_workload(
    received: Span[Complex64, ...],
    known: Span[Complex64, ...],
    indices: Span[Int, ...],
) raises -> Float64:
    var result = wifi_estimate_pilot_phase(received, known, indices)
    keep(result)
    return result.common_phase + result.phase_slope


@no_inline
def _wifi_correct_pilot_phase_workload(
    received: Span[Complex64, ...],
    indices: Span[Int, ...],
    estimate: WifiPilotPhaseEstimate,
) raises -> Float64:
    var result = wifi_correct_pilot_phase(received, indices, estimate)
    keep(result)
    return result[2].im


@no_inline
def _wifi_ldpc_profile_workload() raises -> Float64:
    var result = wifi_ldpc_profile(648, 1, 2)
    keep(result)
    return Float64(result.information_length)


@no_inline
def _wifi_ldpc_base_shifts_workload(
    profile: WifiLDPCProfile
) raises -> Float64:
    var result = wifi_ldpc_base_shifts(profile)
    keep(result)
    return Float64(result[7])


@no_inline
def _wifi_ldpc_sparse_graph_workload(
    profile: WifiLDPCProfile
) raises -> Float64:
    var result = wifi_ldpc_sparse_graph(profile)
    keep(result)
    return Float64(result.row_offsets[13] + result.columns[31])


@no_inline
def _wifi_ldpc_syndrome_ok_workload(
    codeword: Span[UInt8, ...], profile: WifiLDPCProfile
) raises -> Float64:
    var result = wifi_ldpc_syndrome_ok(codeword, profile)
    keep(result)
    return Float64(result)


@no_inline
def _wifi_ldpc_encode_workload(
    information: Span[UInt8, ...], profile: WifiLDPCProfile
) raises -> Float64:
    var result = wifi_ldpc_encode(information, profile)
    keep(result)
    return Float64(result[119])


@no_inline
def _wifi_ldpc_decode_workload(
    llrs: Span[Float64, ...], profile: WifiLDPCProfile
) raises -> Float64:
    var result = wifi_ldpc_decode(llrs, profile, max_iterations=3)
    keep(result)
    return Float64(result.information_bits[73]) + Float64(result.converged)


@no_inline
def _wifi_ldpc_rate_match_block_workload(
    information: Span[UInt8, ...], profile: WifiLDPCProfile
) raises -> Float64:
    var result = wifi_ldpc_rate_match_block(
        information, profile, punctured_bits=4, repeated_bits=2
    )
    keep(result)
    return Float64(result[97])


@no_inline
def _wifi_ldpc_rate_recover_block_workload(
    llrs: Span[Float64, ...], profile: WifiLDPCProfile
) raises -> Float64:
    var result = wifi_ldpc_rate_recover_block(
        llrs, profile, punctured_bits=4, repeated_bits=2
    )
    keep(result)
    return result[173]


@no_inline
def _wifi_ltf_channel_estimate_20mhz_workload(
    received: Span[Complex64, ...]
) raises -> Float64:
    var result = wifi_ltf_channel_estimate_20mhz(received, WIFI_PHY_EHT)
    keep(result)
    return result[41].im


@no_inline
def _wifi_map_ht_vht_symbol_20mhz_workload(
    data: Span[Complex64, ...], pilots: Span[Complex64, ...]
) raises -> Float64:
    var result = wifi_map_ht_vht_symbol_20mhz(data, pilots, WIFI_PHY_VHT)
    keep(result)
    return result[43].im


@no_inline
def _wifi_extract_ht_vht_data_20mhz_workload(
    spectrum: Span[Complex64, ...]
) raises -> Float64:
    var result = wifi_extract_ht_vht_data_20mhz(spectrum, WIFI_PHY_VHT)
    keep(result)
    return result[17].re


@no_inline
def _wifi_extract_ht_vht_pilots_20mhz_workload(
    spectrum: Span[Complex64, ...]
) raises -> Float64:
    var result = wifi_extract_ht_vht_pilots_20mhz(spectrum, WIFI_PHY_VHT)
    keep(result)
    return result[2].im


@no_inline
def _wifi_ldpc_tone_map_bits_workload(
    bits: Span[UInt8, ...]
) raises -> Float64:
    var result = wifi_ldpc_tone_map_bits(bits, 2, 242)
    keep(result)
    return Float64(result[113])


@no_inline
def _wifi_ldpc_tone_demap_llrs_workload(
    llrs: Span[Float64, ...]
) raises -> Float64:
    var result = wifi_ldpc_tone_demap_llrs(llrs, 2, 242)
    keep(result)
    return result[13]


@no_inline
def _wifi_bcc_tx_20mhz_workload(
    payload: Span[UInt8, ...]
) raises -> Float64:
    var result = wifi_bcc_tx_20mhz(payload, WIFI_PHY_HT, 6, symbol_index=5)
    keep(result)
    return result.waveform[17].re + Float64(result.data_field_bits[31])


@no_inline
def _wifi_bcc_rx_20mhz_workload(
    samples: Span[Complex64, ...],
    ltf: Span[Complex64, ...],
    payload_length: Int,
) raises -> Float64:
    var result = wifi_bcc_rx_20mhz(
        samples, ltf, WIFI_PHY_HT, 6, payload_length, symbol_index=5
    )
    keep(result)
    return Float64(result.payload_bits[63]) + result.channel_estimate[29].im


@no_inline
def _wifi_ldpc_tx_20mhz_workload(
    payload: Span[UInt8, ...]
) raises -> Float64:
    var result = wifi_ldpc_tx_20mhz(payload, WIFI_PHY_HE, 10, symbol_index=5)
    keep(result)
    return result.waveform[31].re + Float64(result.tone_mapped_bits[113])


@no_inline
def _wifi_ldpc_rx_20mhz_workload(
    samples: Span[Complex64, ...],
    ltf: Span[Complex64, ...],
    payload_length: Int,
) raises -> Float64:
    var result = wifi_ldpc_rx_20mhz(
        samples, ltf, WIFI_PHY_HE, 10, payload_length, 0.01,
        symbol_index=5, max_iterations=5,
    )
    keep(result)
    return Float64(result.payload_bits[127]) + result.rate_recovered_llrs[199]


@no_inline
def _wifi_acquisition_tx_20mhz_workload(
    payload: Span[UInt8, ...]
) raises -> Float64:
    var result = wifi_acquisition_tx_20mhz(
        payload, WIFI_PHY_HT, 6, symbol_index=5
    )
    keep(result)
    return result.packet_waveform[91].re


@no_inline
def _wifi_acquisition_apply_channel_20mhz_workload(
    waveform: Span[Complex64, ...], config: WifiAcquisitionChannelConfig
) raises -> Float64:
    var result = wifi_acquisition_apply_channel_20mhz(waveform, config)
    keep(result)
    return result.observation[127].im


@no_inline
def _wifi_ltf_fine_timing_20mhz_workload(
    observation: Span[Complex64, ...]
) raises -> Float64:
    var result = wifi_ltf_fine_timing_20mhz(
        observation, WIFI_PHY_HT, 167
    )
    keep(result)
    return Float64(result)


@no_inline
def _wifi_ltf_fine_cfo_20mhz_workload(
    isolated: Span[Complex64, ...]
) raises -> Float64:
    var result = wifi_ltf_fine_cfo_20mhz(isolated, 0)
    keep(result)
    return result


@no_inline
def _wifi_acquisition_rx_20mhz_workload(
    observation: Span[Complex64, ...], payload_length: Int
) raises -> Float64:
    var result = wifi_acquisition_rx_20mhz(
        observation, WIFI_PHY_HT, 6, payload_length, symbol_index=5,
        detection_threshold=0.8, llr_noise_variance=1.0e-8,
    )
    keep(result)
    return Float64(result.packet_start) + Float64(result.payload_bits[31])


def _legacy_profiles_resources_reference(iteration: Int) raises -> Float64:
    var checksum = 0.0
    var raw = _bits(288, iteration)
    var scrambled = wifi_scramble(Span(raw), UInt8(0x5D))
    var legacy_bits = List[UInt8](capacity=288)
    for i in range(288):
        legacy_bits.append(scrambled[i])
    var interleaved = wifi_interleave(Span(legacy_bits), 6)
    var deinterleaved = wifi_deinterleave(Span(interleaved), 6)
    var carriers = wifi_data_subcarriers()
    var data = List[Complex64](capacity=48)
    for i in range(48):
        data.append(Complex64(Float64(i % 9) - 4.0, Float64(i % 7) - 3.0))
    var waveform = wifi_map_legacy_symbol(Span(data), symbol_index=iteration)
    var extracted = wifi_extract_legacy_symbol(Span(waveform))
    var known: List[Complex64] = [Complex64(1.0, 0.5), Complex64(-0.5, 1.0)]
    var received: List[Complex64] = [known[0] * Complex64(0.8, -0.2), known[1] * Complex64(0.8, -0.2)]
    var estimate = wifi_ls_channel_estimate(Span(received), Span(known))
    var equalized = wifi_equalize(Span(received), Span(estimate))
    var stf = wifi_stf_waveform_20mhz()
    var padded = List[Complex64](capacity=163)
    for _ in range(3):
        padded.append(Complex64(0.0))
    for sample in stf:
        padded.append(sample)
    var shifted = apply_cfo(Span(padded), 0.001)
    var detection = wifi_stf_detect(Span(shifted), 0.8)
    var cfo = wifi_stf_coarse_cfo(Span(shifted), detection)
    var polarity = wifi_pilot_polarity(iteration)
    var rate: List[UInt8] = [1, 1, 0, 1]
    var signal = wifi_legacy_signal_bits(Span(rate), 127 + iteration)
    var parsed = wifi_parse_legacy_signal(Span(signal))
    var fcs = wifi_fcs(Span(raw))

    var ht_mcs = wifi_mcs_profile(WIFI_PHY_HT, 6)
    var vht_mcs = wifi_mcs_profile(WIFI_PHY_VHT, 8)
    var he_mcs = wifi_mcs_profile(WIFI_PHY_HE, 10)
    var eht_mcs = wifi_mcs_profile(WIFI_PHY_EHT, 13)
    var ht_ofdm = wifi_ofdm_profile(WIFI_PHY_HT, 20)
    var vht_ofdm = wifi_ofdm_profile(WIFI_PHY_VHT, 80)
    var he_ofdm = wifi_ofdm_profile(WIFI_PHY_HE, 20)
    var eht_ofdm = wifi_ofdm_profile(WIFI_PHY_EHT, 320)
    var guard = wifi_guard_interval_samples(he_ofdm, 800)
    var coded = wifi_coded_bits_per_symbol(vht_ofdm, vht_mcs)
    var uncoded = wifi_data_bits_per_symbol(ht_ofdm, ht_mcs)

    var ru = wifi_ru_profile(WIFI_PHY_HE, 106)
    var ru_mcs = wifi_mcs_profile(WIFI_PHY_HE, 6)
    var max_count = wifi_max_ru_count(WIFI_PHY_HE, 80, 26)
    var ru_coded = wifi_ru_coded_bits_per_symbol(ru, ru_mcs)
    var ru_data_bits = wifi_ru_data_bits_per_symbol(ru, ru_mcs)
    var requires = wifi_ru_requires_ldpc(ru, ru_mcs)
    var ru_tones = wifi_ru_subcarriers_20mhz(106, 1)
    var ru_pilot_indices = wifi_ru_pilot_subcarriers_20mhz(106, 1)
    var ru_data_indices = wifi_ru_data_subcarriers_20mhz(106, 1)
    var sizes: List[Int] = [52, 52]
    var indices: List[Int] = [0, 1]
    var disjoint = wifi_ru_allocations_disjoint_20mhz(Span(sizes), Span(indices))
    var ru_data_symbols = List[Complex64](capacity=102)
    for i in range(102):
        ru_data_symbols.append(Complex64(Float64(i % 13), -Float64(i % 11)))
    var ru_pilot_symbols: List[Complex64] = [Complex64(1.0), Complex64(-1.0), Complex64(1.0), Complex64(-1.0)]
    var ru_spectrum = wifi_map_ru_symbol_20mhz(Span(ru_data_symbols), Span(ru_pilot_symbols), 106, 1)
    var ru_extracted = wifi_extract_ru_data_20mhz(Span(ru_spectrum), 106, 1)
    var ru_extracted_pilots = wifi_extract_ru_pilots_20mhz(Span(ru_spectrum), 106, 1)

    var pattern = wifi_bcc_puncture_pattern(3, 4)
    var punctured = wifi_bcc_puncture(Span(raw), 3, 4)
    var punctured_llrs = List[Float64](capacity=len(punctured))
    for bit in punctured:
        punctured_llrs.append(1.0 if bit == 0 else -1.0)
    var depunctured = wifi_bcc_depuncture_llrs(Span(punctured_llrs), len(raw), 3, 4)
    var bcc_profile = wifi_bcc_interleaver_profile(WIFI_PHY_HT, 20)
    var bcc_input = _bits(312, iteration + 5)
    var bcc_interleaved = wifi_bcc_interleave_block(Span(bcc_input), 6, bcc_profile)
    var bcc_deinterleaved = wifi_bcc_deinterleave_block(Span(bcc_interleaved), 6, bcc_profile)

    var pilot_indices: List[Int] = [-21, -7, 7, 21]
    var pilot_known: List[Complex64] = [Complex64(1.0), Complex64(1.0), Complex64(1.0), Complex64(-1.0)]
    var pilot_received = List[Complex64](capacity=4)
    for i in range(4):
        var angle = 0.1 + 0.001 * Float64(pilot_indices[i])
        pilot_received.append(pilot_known[i] * Complex64(cos(angle), sin(angle)))
    var phase = wifi_estimate_pilot_phase(Span(pilot_received), Span(pilot_known), Span(pilot_indices))
    var corrected = wifi_correct_pilot_phase(Span(pilot_received), Span(pilot_indices), phase)

    keep(deinterleaved); keep(carriers); keep(extracted); keep(equalized)
    keep(signal); keep(ht_mcs); keep(he_mcs); keep(eht_mcs); keep(eht_ofdm)
    keep(ru_tones); keep(ru_pilot_indices); keep(ru_data_indices)
    keep(ru_extracted); keep(ru_extracted_pilots); keep(pattern); keep(depunctured)
    keep(bcc_deinterleaved); keep(corrected)
    checksum += extracted[7].re + estimate[0].re + equalized[1].im + cfo + polarity
    checksum += Float64(detection + parsed.length_octets + guard + coded + uncoded)
    checksum += Float64(max_count + ru_coded + ru_data_bits + len(ru_tones))
    checksum += Float64(requires) + Float64(disjoint) + Float64(fcs & UInt64(0xFFFF))
    return checksum


def _preambles_tones_ldpc_reference(iteration: Int) raises -> Float64:
    var checksum = 0.0
    for family in [WIFI_PHY_HT, WIFI_PHY_VHT, WIFI_PHY_HE, WIFI_PHY_EHT]:
        var values = wifi_ltf_values_20mhz(family)
        var spectrum = wifi_ltf_spectrum_20mhz(family)
        var waveform = wifi_ltf_waveform_20mhz(family)
        var estimate = wifi_ltf_channel_estimate_20mhz(Span(waveform), family)
        var pilot_indices = wifi_data_pilot_subcarriers_20mhz(family)
        var pilots = wifi_data_pilots_20mhz(family, iteration)
        keep(values); keep(spectrum); keep(waveform); keep(estimate)
        keep(pilot_indices); keep(pilots)
        checksum += Float64(len(values) + len(pilot_indices)) + pilots[0].re

    var ht_indices = wifi_ht_vht_data_subcarriers_20mhz(WIFI_PHY_HT)
    var ht_data = List[Complex64](capacity=52)
    for i in range(52):
        ht_data.append(Complex64(Float64(i % 7), Float64(i % 5)))
    var ht_pilots = wifi_data_pilots_20mhz(WIFI_PHY_HT, iteration)
    var ht_spectrum = wifi_map_ht_vht_symbol_20mhz(Span(ht_data), Span(ht_pilots), WIFI_PHY_HT)
    var ht_extracted = wifi_extract_ht_vht_data_20mhz(Span(ht_spectrum), WIFI_PHY_HT)
    var ht_extracted_pilots = wifi_extract_ht_vht_pilots_20mhz(Span(ht_spectrum), WIFI_PHY_HT)
    var distance = wifi_ldpc_tone_mapping_distance(242)
    var permutation = wifi_ldpc_tone_permutation(234, distance)
    var tone_bits = _bits(468, iteration + 11)
    var mapped = wifi_ldpc_tone_map_bits(Span(tone_bits), 2, 242)
    var mapped_llrs = List[Float64](capacity=468)
    for bit in mapped:
        mapped_llrs.append(1.0 if bit == 0 else -1.0)
    var demapped = wifi_ldpc_tone_demap_llrs(Span(mapped_llrs), 2, 242)
    keep(ht_indices); keep(ht_extracted); keep(ht_extracted_pilots)
    keep(permutation); keep(demapped)

    var profile = wifi_ldpc_profile(648, 1, 2)
    var shifts = wifi_ldpc_base_shifts(profile)
    var graph = wifi_ldpc_sparse_graph(profile)
    var information = _bits(profile.information_length, iteration + 19)
    var encoded = wifi_ldpc_encode(Span(information), profile)
    var syndrome = wifi_ldpc_syndrome_ok(Span(encoded), profile)
    var llrs = List[Float64](capacity=648)
    for bit in encoded:
        llrs.append(8.0 if bit == 0 else -8.0)
    var decoded = wifi_ldpc_decode(Span(llrs), profile, max_iterations=3)
    var rate_matched = wifi_ldpc_rate_match_block(Span(information), profile, punctured_bits=4, repeated_bits=2)
    var rate_llrs = List[Float64](capacity=len(rate_matched))
    for bit in rate_matched:
        rate_llrs.append(2.0 if bit == 0 else -2.0)
    var recovered = wifi_ldpc_rate_recover_block(Span(rate_llrs), profile, punctured_bits=4, repeated_bits=2)
    keep(shifts); keep(graph); keep(decoded); keep(recovered)
    checksum += ht_extracted[17].re + Float64(permutation[25]) + demapped[13]
    checksum += Float64(syndrome) + Float64(decoded.converged) + Float64(len(graph.columns))
    return checksum


def _phy_chains_reference(iteration: Int) raises -> Float64:
    var checksum = 0.0
    var ht_payload = _bits(18 * 8, iteration + 23)
    var ht_tx = wifi_bcc_tx_20mhz(Span(ht_payload), WIFI_PHY_HT, 6, symbol_index=iteration)
    var ht_ltf = _flat_ltf(WIFI_PHY_HT)
    var ht_samples = List[Complex64](capacity=80)
    for sample in ht_tx.waveform:
        ht_samples.append(sample * Complex64(0.91, -0.17))
    var ht_rx = wifi_bcc_rx_20mhz(Span(ht_samples), Span(ht_ltf), WIFI_PHY_HT, 6, len(ht_payload), symbol_index=iteration)
    var vht_payload = _bits(24 * 8, iteration + 29)
    var vht_tx = wifi_bcc_tx_20mhz(Span(vht_payload), WIFI_PHY_VHT, 8, symbol_index=iteration)
    var vht_ltf = _flat_ltf(WIFI_PHY_VHT)
    var vht_samples = List[Complex64](capacity=80)
    for sample in vht_tx.waveform:
        vht_samples.append(sample * Complex64(0.91, -0.17))
    var vht_rx = wifi_bcc_rx_20mhz(Span(vht_samples), Span(vht_ltf), WIFI_PHY_VHT, 8, len(vht_payload), symbol_index=iteration)

    var he_payload = _bits(205 * 8, iteration + 31)
    var he_tx = wifi_ldpc_tx_20mhz(Span(he_payload), WIFI_PHY_HE, 10, symbol_index=iteration)
    var he_ltf = _flat_ltf(WIFI_PHY_HE)
    var he_samples = List[Complex64](capacity=272)
    for sample in he_tx.waveform:
        he_samples.append(sample * Complex64(0.91, -0.17))
    var he_rx = wifi_ldpc_rx_20mhz(Span(he_samples), Span(he_ltf), WIFI_PHY_HE, 10, len(he_payload), 0.01, symbol_index=iteration, max_iterations=5)
    var eht_payload = _bits(264 * 8, iteration + 37)
    var eht_tx = wifi_ldpc_tx_20mhz(Span(eht_payload), WIFI_PHY_EHT, 13, symbol_index=iteration)
    var eht_ltf = _flat_ltf(WIFI_PHY_EHT)
    var eht_samples = List[Complex64](capacity=272)
    for sample in eht_tx.waveform:
        eht_samples.append(sample * Complex64(0.91, -0.17))
    var eht_rx = wifi_ldpc_rx_20mhz(Span(eht_samples), Span(eht_ltf), WIFI_PHY_EHT, 13, len(eht_payload), 0.01, symbol_index=iteration, max_iterations=5)
    keep(ht_tx); keep(ht_rx); keep(vht_tx); keep(vht_rx)
    keep(he_tx); keep(he_rx); keep(eht_tx); keep(eht_rx)
    checksum += Float64(ht_rx.fcs_ok) + Float64(vht_rx.fcs_ok)
    checksum += Float64(he_rx.fcs_ok) + Float64(eht_rx.fcs_ok)
    checksum += Float64(len(ht_rx.payload_bits) + len(vht_rx.payload_bits))
    checksum += Float64(len(he_rx.payload_bits) + len(eht_rx.payload_bits))
    return checksum


def _acquisition_reference(iteration: Int) raises -> Float64:
    var spectrum = wifi_stf_spectrum_20mhz()
    var short = wifi_stf_short_symbol_20mhz()
    var stf = wifi_stf_waveform_20mhz()
    var signal = wifi_legacy_signal_tx_20mhz(13)
    var payload = _bits(9 * 8, iteration + 41)
    var family = WIFI_PHY_HT if iteration % 2 == 0 else WIFI_PHY_VHT
    var mcs = 6 if family == WIFI_PHY_HT else 8
    var tx = wifi_acquisition_tx_20mhz(Span(payload), family, mcs, symbol_index=iteration)
    var config = WifiAcquisitionChannelConfig(timing_offset=7, normalized_cfo=0.0015, noise_variance=0.0, rician_k_factor=30.0, seed=UInt64(0xAC80211 + iteration))
    var channel = wifi_acquisition_apply_channel_20mhz(Span(tx.packet_waveform), config)
    var timing = wifi_ltf_fine_timing_20mhz(Span(channel.observation), family, 167)
    var isolated = apply_cfo(Span(tx.ltf_waveform), 0.0005)
    var fine = wifi_ltf_fine_cfo_20mhz(Span(isolated), 0)
    var rx = wifi_acquisition_rx_20mhz(Span(channel.observation), family, mcs, len(payload), symbol_index=iteration, detection_threshold=0.8, llr_noise_variance=1.0e-8)
    keep(spectrum); keep(short); keep(stf); keep(signal); keep(tx); keep(channel); keep(rx)
    return Float64(timing + rx.packet_start + len(rx.payload_bits)) + fine + spectrum[40].re


@no_inline
def _wifi_bit_permutation_once(iteration: Int) raises -> Float64:
    var raw = _bits(288, iteration)
    var scrambled = wifi_scramble(Span(raw), UInt8(0x5D))
    var source = List[UInt8](capacity=288)
    for bit in scrambled:
        source.append(bit)
    var interleaved = wifi_interleave(Span(source), 6)
    var deinterleaved = wifi_deinterleave(Span(interleaved), 6)
    keep(scrambled)
    keep(interleaved)
    keep(deinterleaved)
    return (
        Float64(scrambled[31])
        + Float64(interleaved[79])
        + Float64(deinterleaved[143])
    )


@no_inline
def _wifi_legacy_ofdm_once(iteration: Int) raises -> Float64:
    var carriers = wifi_data_subcarriers()
    var data = List[Complex64](capacity=48)
    for i in range(48):
        data.append(
            Complex64(Float64(i % 9) - 4.0, Float64(i % 7) - 3.0)
        )
    var waveform = wifi_map_legacy_symbol(Span(data), symbol_index=iteration)
    var extracted = wifi_extract_legacy_symbol(Span(waveform))
    var known: List[Complex64] = [
        Complex64(1.0, 0.5), Complex64(-0.5, 1.0)
    ]
    var received: List[Complex64] = [
        known[0] * Complex64(0.8, -0.2),
        known[1] * Complex64(0.8, -0.2),
    ]
    var estimate = wifi_ls_channel_estimate(Span(received), Span(known))
    var equalized = wifi_equalize(Span(received), Span(estimate))
    keep(carriers)
    keep(waveform)
    keep(extracted)
    keep(estimate)
    keep(equalized)
    return (
        Float64(carriers[7])
        + waveform[17].im
        + extracted[7].re
        + estimate[0].re
        + equalized[1].im
    )


@no_inline
def _wifi_stf_sync_once(iteration: Int) raises -> Float64:
    var stf = wifi_stf_waveform_20mhz()
    var padded = List[Complex64](capacity=163)
    for _ in range(3):
        padded.append(Complex64(0.0))
    for sample in stf:
        padded.append(sample)
    var shifted = apply_cfo(Span(padded), 0.001)
    var detection = wifi_stf_detect(Span(shifted), 0.8)
    var cfo = wifi_stf_coarse_cfo(Span(shifted), detection)
    keep(stf)
    keep(shifted)
    keep(detection)
    keep(cfo)
    return stf[19].re + shifted[23].im + Float64(detection) + cfo


@no_inline
def _wifi_legacy_signal_once(iteration: Int) raises -> Float64:
    var raw = _bits(288, iteration)
    var polarity = wifi_pilot_polarity(iteration)
    var rate: List[UInt8] = [1, 1, 0, 1]
    var signal = wifi_legacy_signal_bits(Span(rate), 127 + iteration)
    var parsed = wifi_parse_legacy_signal(Span(signal))
    var fcs = wifi_fcs(Span(raw))
    keep(polarity)
    keep(signal)
    keep(parsed)
    keep(fcs)
    return (
        Float64(polarity)
        + Float64(signal[7])
        + Float64(parsed.length_octets)
        + Float64(fcs & UInt64(0xFFFF))
    )


@no_inline
def _wifi_profiles_once() raises -> Float64:
    var ht_mcs = wifi_mcs_profile(WIFI_PHY_HT, 6)
    var vht_mcs = wifi_mcs_profile(WIFI_PHY_VHT, 8)
    var he_mcs = wifi_mcs_profile(WIFI_PHY_HE, 10)
    var eht_mcs = wifi_mcs_profile(WIFI_PHY_EHT, 13)
    var ht_ofdm = wifi_ofdm_profile(WIFI_PHY_HT, 20)
    var vht_ofdm = wifi_ofdm_profile(WIFI_PHY_VHT, 80)
    var he_ofdm = wifi_ofdm_profile(WIFI_PHY_HE, 20)
    var eht_ofdm = wifi_ofdm_profile(WIFI_PHY_EHT, 320)
    var guard = wifi_guard_interval_samples(he_ofdm, 800)
    var coded = wifi_coded_bits_per_symbol(vht_ofdm, vht_mcs)
    var uncoded = wifi_data_bits_per_symbol(ht_ofdm, ht_mcs)
    keep(ht_mcs)
    keep(vht_mcs)
    keep(he_mcs)
    keep(eht_mcs)
    keep(ht_ofdm)
    keep(vht_ofdm)
    keep(he_ofdm)
    keep(eht_ofdm)
    keep(guard)
    keep(coded)
    keep(uncoded)
    return Float64(guard + coded + uncoded)


@no_inline
def _wifi_ru_resources_once() raises -> Float64:
    var ru = wifi_ru_profile(WIFI_PHY_HE, 106)
    var ru_mcs = wifi_mcs_profile(WIFI_PHY_HE, 6)
    var max_count = wifi_max_ru_count(WIFI_PHY_HE, 80, 26)
    var coded = wifi_ru_coded_bits_per_symbol(ru, ru_mcs)
    var data_bits = wifi_ru_data_bits_per_symbol(ru, ru_mcs)
    var requires = wifi_ru_requires_ldpc(ru, ru_mcs)
    var tones = wifi_ru_subcarriers_20mhz(106, 1)
    var pilots = wifi_ru_pilot_subcarriers_20mhz(106, 1)
    var data = wifi_ru_data_subcarriers_20mhz(106, 1)
    var sizes: List[Int] = [52, 52]
    var indices: List[Int] = [0, 1]
    var disjoint = wifi_ru_allocations_disjoint_20mhz(
        Span(sizes), Span(indices)
    )
    keep(ru)
    keep(ru_mcs)
    keep(max_count)
    keep(coded)
    keep(data_bits)
    keep(requires)
    keep(tones)
    keep(pilots)
    keep(data)
    keep(disjoint)
    return (
        Float64(max_count + coded + data_bits)
        + Float64(requires)
        + Float64(disjoint)
        + Float64(tones[7] + pilots[1] + data[19])
    )


@no_inline
def _wifi_ru_mapping_once(iteration: Int) raises -> Float64:
    var data = List[Complex64](capacity=102)
    for i in range(102):
        data.append(Complex64(Float64(i % 13), -Float64(i % 11)))
    var pilots: List[Complex64] = [
        Complex64(1.0),
        Complex64(-1.0),
        Complex64(1.0),
        Complex64(-1.0),
    ]
    var spectrum = wifi_map_ru_symbol_20mhz(
        Span(data), Span(pilots), 106, 1
    )
    var extracted = wifi_extract_ru_data_20mhz(Span(spectrum), 106, 1)
    var extracted_pilots = wifi_extract_ru_pilots_20mhz(
        Span(spectrum), 106, 1
    )
    keep(spectrum)
    keep(extracted)
    keep(extracted_pilots)
    return spectrum[13].im + extracted[41].re + extracted_pilots[2].re


@no_inline
def _wifi_bcc_puncture_once(iteration: Int) raises -> Float64:
    var raw = _bits(288, iteration)
    var pattern = wifi_bcc_puncture_pattern(3, 4)
    var punctured = wifi_bcc_puncture(Span(raw), 3, 4)
    var punctured_llrs = List[Float64](capacity=len(punctured))
    for bit in punctured:
        punctured_llrs.append(1.0 if bit == 0 else -1.0)
    var depunctured = wifi_bcc_depuncture_llrs(
        Span(punctured_llrs), len(raw), 3, 4
    )
    keep(pattern)
    keep(punctured)
    keep(depunctured)
    return (
        Float64(pattern[0])
        + Float64(punctured[31])
        + depunctured[79]
    )


@no_inline
def _wifi_bcc_interleave_once(iteration: Int) raises -> Float64:
    var profile = wifi_bcc_interleaver_profile(WIFI_PHY_HT, 20)
    var source = _bits(312, iteration + 5)
    var interleaved = wifi_bcc_interleave_block(Span(source), 6, profile)
    var deinterleaved = wifi_bcc_deinterleave_block(
        Span(interleaved), 6, profile
    )
    keep(profile)
    keep(interleaved)
    keep(deinterleaved)
    return Float64(interleaved[73]) + Float64(deinterleaved[151])


@no_inline
def _wifi_pilot_phase_once(iteration: Int) raises -> Float64:
    var indices: List[Int] = [-21, -7, 7, 21]
    var known: List[Complex64] = [
        Complex64(1.0),
        Complex64(1.0),
        Complex64(1.0),
        Complex64(-1.0),
    ]
    var received = List[Complex64](capacity=4)
    for i in range(4):
        var angle = 0.1 + 0.001 * Float64(indices[i])
        received.append(known[i] * Complex64(cos(angle), sin(angle)))
    var phase = wifi_estimate_pilot_phase(
        Span(received), Span(known), Span(indices)
    )
    var corrected = wifi_correct_pilot_phase(
        Span(received), Span(indices), phase
    )
    keep(phase)
    keep(corrected)
    return phase.common_phase + phase.phase_slope + corrected[2].im


@no_inline
def _wifi_ltf_reference_once(iteration: Int) raises -> Float64:
    var checksum = 0.0
    for family in [WIFI_PHY_HT, WIFI_PHY_VHT, WIFI_PHY_HE, WIFI_PHY_EHT]:
        var values = wifi_ltf_values_20mhz(family)
        var spectrum = wifi_ltf_spectrum_20mhz(family)
        var waveform = wifi_ltf_waveform_20mhz(family)
        var pilot_indices = wifi_data_pilot_subcarriers_20mhz(family)
        var pilots = wifi_data_pilots_20mhz(family, iteration)
        keep(values)
        keep(spectrum)
        keep(waveform)
        keep(pilot_indices)
        keep(pilots)
        checksum += (
            Float64(values[7])
            + spectrum[40].re
            + waveform[19].im
            + Float64(pilot_indices[0])
            + pilots[0].re
        )
    return checksum


@no_inline
def _wifi_ltf_channel_once() raises -> Float64:
    var checksum = 0.0
    for family in [WIFI_PHY_HT, WIFI_PHY_VHT, WIFI_PHY_HE, WIFI_PHY_EHT]:
        var received = _flat_ltf(family)
        var estimate = wifi_ltf_channel_estimate_20mhz(
            Span(received), family
        )
        keep(received)
        keep(estimate)
        checksum += received[17].re + estimate[41].im
    return checksum


@no_inline
def _wifi_ht_vht_symbol_once(iteration: Int) raises -> Float64:
    var checksum = 0.0
    for family in [WIFI_PHY_HT, WIFI_PHY_VHT]:
        var indices = wifi_ht_vht_data_subcarriers_20mhz(family)
        var data = List[Complex64](capacity=52)
        for i in range(52):
            data.append(Complex64(Float64(i % 7), Float64(i % 5)))
        var pilots = wifi_data_pilots_20mhz(family, iteration)
        var spectrum = wifi_map_ht_vht_symbol_20mhz(
            Span(data), Span(pilots), family
        )
        var extracted = wifi_extract_ht_vht_data_20mhz(
            Span(spectrum), family
        )
        var extracted_pilots = wifi_extract_ht_vht_pilots_20mhz(
            Span(spectrum), family
        )
        keep(indices)
        keep(pilots)
        keep(spectrum)
        keep(extracted)
        keep(extracted_pilots)
        checksum += (
            Float64(indices[17])
            + pilots[1].re
            + spectrum[43].im
            + extracted[17].re
            + extracted_pilots[2].im
        )
    return checksum


@no_inline
def _wifi_ldpc_tone_once(iteration: Int) raises -> Float64:
    var distance = wifi_ldpc_tone_mapping_distance(242)
    var permutation = wifi_ldpc_tone_permutation(234, distance)
    var bits = _bits(468, iteration + 11)
    var mapped = wifi_ldpc_tone_map_bits(Span(bits), 2, 242)
    var mapped_llrs = List[Float64](capacity=468)
    for bit in mapped:
        mapped_llrs.append(1.0 if bit == 0 else -1.0)
    var demapped = wifi_ldpc_tone_demap_llrs(Span(mapped_llrs), 2, 242)
    keep(distance)
    keep(permutation)
    keep(mapped)
    keep(demapped)
    return (
        Float64(distance + permutation[25])
        + Float64(mapped[113])
        + demapped[13]
    )


@no_inline
def _wifi_ldpc_configuration_once() raises -> Float64:
    var profile = wifi_ldpc_profile(648, 1, 2)
    var shifts = wifi_ldpc_base_shifts(profile)
    var graph = wifi_ldpc_sparse_graph(profile)
    keep(profile)
    keep(shifts)
    keep(graph)
    return (
        Float64(profile.information_length)
        + Float64(shifts[7])
        + Float64(graph.row_offsets[13] + graph.columns[31])
    )


@no_inline
def _wifi_ldpc_codec_once(iteration: Int) raises -> Float64:
    var profile = wifi_ldpc_profile(648, 1, 2)
    var information = _bits(profile.information_length, iteration + 19)
    var encoded = wifi_ldpc_encode(Span(information), profile)
    var syndrome = wifi_ldpc_syndrome_ok(Span(encoded), profile)
    var llrs = List[Float64](capacity=648)
    for bit in encoded:
        llrs.append(8.0 if bit == 0 else -8.0)
    var decoded = wifi_ldpc_decode(Span(llrs), profile, max_iterations=3)
    keep(profile)
    keep(encoded)
    keep(syndrome)
    keep(decoded)
    return (
        Float64(profile.block_length)
        + Float64(encoded[119])
        + Float64(syndrome)
        + Float64(decoded.information_bits[73])
        + Float64(decoded.codeword_bits[211])
        + Float64(decoded.converged)
    )


@no_inline
def _wifi_ldpc_rate_matching_once(iteration: Int) raises -> Float64:
    var profile = wifi_ldpc_profile(648, 1, 2)
    var information = _bits(profile.information_length, iteration + 19)
    var matched = wifi_ldpc_rate_match_block(
        Span(information), profile, punctured_bits=4, repeated_bits=2
    )
    var llrs = List[Float64](capacity=len(matched))
    for bit in matched:
        llrs.append(2.0 if bit == 0 else -2.0)
    var recovered = wifi_ldpc_rate_recover_block(
        Span(llrs), profile, punctured_bits=4, repeated_bits=2
    )
    keep(profile)
    keep(matched)
    keep(recovered)
    return (
        Float64(profile.parity_length)
        + Float64(matched[97])
        + recovered[173]
    )


@no_inline
def _wifi_ht_bcc_chain_once(iteration: Int) raises -> Float64:
    var payload = _bits(18 * 8, iteration + 23)
    var tx = wifi_bcc_tx_20mhz(
        Span(payload), WIFI_PHY_HT, 6, symbol_index=iteration
    )
    var ltf = _flat_ltf(WIFI_PHY_HT)
    var samples = List[Complex64](capacity=80)
    for sample in tx.waveform:
        samples.append(sample * Complex64(0.91, -0.17))
    var rx = wifi_bcc_rx_20mhz(
        Span(samples),
        Span(ltf),
        WIFI_PHY_HT,
        6,
        len(payload),
        symbol_index=iteration,
    )
    keep(tx)
    keep(rx)
    return (
        tx.waveform[17].re
        + Float64(tx.data_field_bits[31])
        + Float64(rx.payload_bits[63])
        + rx.channel_estimate[29].im
        + Float64(rx.fcs_ok)
    )


@no_inline
def _wifi_vht_bcc_chain_once(iteration: Int) raises -> Float64:
    var payload = _bits(24 * 8, iteration + 29)
    var tx = wifi_bcc_tx_20mhz(
        Span(payload), WIFI_PHY_VHT, 8, symbol_index=iteration
    )
    var ltf = _flat_ltf(WIFI_PHY_VHT)
    var samples = List[Complex64](capacity=80)
    for sample in tx.waveform:
        samples.append(sample * Complex64(0.91, -0.17))
    var rx = wifi_bcc_rx_20mhz(
        Span(samples),
        Span(ltf),
        WIFI_PHY_VHT,
        8,
        len(payload),
        symbol_index=iteration,
    )
    keep(tx)
    keep(rx)
    return (
        tx.waveform[23].im
        + Float64(tx.interleaved_bits[71])
        + Float64(rx.payload_bits[95])
        + rx.equalized_spectrum[41].re
        + Float64(rx.fcs_ok)
    )


@no_inline
def _wifi_he_ldpc_chain_once(iteration: Int) raises -> Float64:
    var payload = _bits(205 * 8, iteration + 31)
    var tx = wifi_ldpc_tx_20mhz(
        Span(payload), WIFI_PHY_HE, 10, symbol_index=iteration
    )
    var ltf = _flat_ltf(WIFI_PHY_HE)
    var samples = List[Complex64](capacity=272)
    for sample in tx.waveform:
        samples.append(sample * Complex64(0.91, -0.17))
    var rx = wifi_ldpc_rx_20mhz(
        Span(samples),
        Span(ltf),
        WIFI_PHY_HE,
        10,
        len(payload),
        0.01,
        symbol_index=iteration,
        max_iterations=5,
    )
    keep(tx)
    keep(rx)
    return (
        tx.waveform[31].re
        + Float64(tx.tone_mapped_bits[113])
        + Float64(rx.payload_bits[127])
        + rx.rate_recovered_llrs[199]
        + Float64(rx.ldpc_converged)
        + Float64(rx.fcs_ok)
    )


@no_inline
def _wifi_eht_ldpc_chain_once(iteration: Int) raises -> Float64:
    var payload = _bits(264 * 8, iteration + 37)
    var tx = wifi_ldpc_tx_20mhz(
        Span(payload), WIFI_PHY_EHT, 13, symbol_index=iteration
    )
    var ltf = _flat_ltf(WIFI_PHY_EHT)
    var samples = List[Complex64](capacity=272)
    for sample in tx.waveform:
        samples.append(sample * Complex64(0.91, -0.17))
    var rx = wifi_ldpc_rx_20mhz(
        Span(samples),
        Span(ltf),
        WIFI_PHY_EHT,
        13,
        len(payload),
        0.01,
        symbol_index=iteration,
        max_iterations=5,
    )
    keep(tx)
    keep(rx)
    return (
        tx.waveform[37].im
        + Float64(tx.rate_matched_bits[151])
        + Float64(rx.payload_bits[191])
        + rx.demapped_llrs[223]
        + Float64(rx.ldpc_converged)
        + Float64(rx.fcs_ok)
    )


@no_inline
def _wifi_acquisition_artifacts_once() raises -> Float64:
    var spectrum = wifi_stf_spectrum_20mhz()
    var short = wifi_stf_short_symbol_20mhz()
    var stf = wifi_stf_waveform_20mhz()
    var signal = wifi_legacy_signal_tx_20mhz(13)
    keep(spectrum)
    keep(short)
    keep(stf)
    keep(signal)
    return (
        spectrum[40].re
        + short[7].im
        + stf[71].re
        + Float64(signal.bits[7])
        + signal.waveform[39].im
    )


@no_inline
def _wifi_ht_acquisition_once(iteration: Int) raises -> Float64:
    var payload = _bits(9 * 8, iteration + 41)
    var tx = wifi_acquisition_tx_20mhz(
        Span(payload), WIFI_PHY_HT, 6, symbol_index=iteration
    )
    var config = WifiAcquisitionChannelConfig(
        timing_offset=7,
        normalized_cfo=0.0015,
        noise_variance=0.0,
        rician_k_factor=30.0,
        seed=UInt64(0xAC80211 + iteration),
    )
    var channel = wifi_acquisition_apply_channel_20mhz(
        Span(tx.packet_waveform), config
    )
    var timing = wifi_ltf_fine_timing_20mhz(
        Span(channel.observation), WIFI_PHY_HT, 167
    )
    var isolated = apply_cfo(Span(tx.ltf_waveform), 0.0005)
    var fine = wifi_ltf_fine_cfo_20mhz(Span(isolated), 0)
    var rx = wifi_acquisition_rx_20mhz(
        Span(channel.observation),
        WIFI_PHY_HT,
        6,
        len(payload),
        symbol_index=iteration,
        detection_threshold=0.8,
        llr_noise_variance=1.0e-8,
    )
    keep(tx)
    keep(channel)
    keep(timing)
    keep(isolated)
    keep(fine)
    keep(rx)
    return (
        tx.packet_waveform[91].re
        + channel.observation[127].im
        + Float64(timing)
        + isolated[23].re
        + fine
        + Float64(rx.packet_start)
        + Float64(rx.payload_bits[31])
        + rx.channel_estimate[41].im
    )


@no_inline
def _wifi_vht_acquisition_once(iteration: Int) raises -> Float64:
    var payload = _bits(9 * 8, iteration + 43)
    var tx = wifi_acquisition_tx_20mhz(
        Span(payload), WIFI_PHY_VHT, 8, symbol_index=iteration
    )
    var config = WifiAcquisitionChannelConfig(
        timing_offset=7,
        normalized_cfo=0.0015,
        noise_variance=0.0,
        rician_k_factor=30.0,
        seed=UInt64(0xBC80211 + iteration),
    )
    var channel = wifi_acquisition_apply_channel_20mhz(
        Span(tx.packet_waveform), config
    )
    var timing = wifi_ltf_fine_timing_20mhz(
        Span(channel.observation), WIFI_PHY_VHT, 167
    )
    var isolated = apply_cfo(Span(tx.ltf_waveform), 0.0005)
    var fine = wifi_ltf_fine_cfo_20mhz(Span(isolated), 0)
    var rx = wifi_acquisition_rx_20mhz(
        Span(channel.observation),
        WIFI_PHY_VHT,
        8,
        len(payload),
        symbol_index=iteration,
        detection_threshold=0.8,
        llr_noise_variance=1.0e-8,
    )
    keep(tx)
    keep(channel)
    keep(timing)
    keep(isolated)
    keep(fine)
    keep(rx)
    return (
        tx.packet_waveform[103].im
        + channel.observation[139].re
        + Float64(timing)
        + isolated[29].im
        + fine
        + Float64(rx.packet_start)
        + Float64(rx.payload_bits[47])
        + rx.equalized_spectrum[43].re
    )


@no_inline
def _bench_legacy_profiles_resources(iteration: Int) raises -> Float64:
    return (
        _wifi_bit_permutation_once(iteration)
        + _wifi_legacy_ofdm_once(iteration)
        + _wifi_stf_sync_once(iteration)
        + _wifi_legacy_signal_once(iteration)
        + _wifi_profiles_once()
        + _wifi_ru_resources_once()
        + _wifi_ru_mapping_once(iteration)
        + _wifi_bcc_puncture_once(iteration)
        + _wifi_bcc_interleave_once(iteration)
        + _wifi_pilot_phase_once(iteration)
    )


@no_inline
def _bench_preambles_tones_ldpc(iteration: Int) raises -> Float64:
    return (
        _wifi_ltf_reference_once(iteration)
        + _wifi_ltf_channel_once()
        + _wifi_ht_vht_symbol_once(iteration)
        + _wifi_ldpc_tone_once(iteration)
        + _wifi_ldpc_configuration_once()
        + _wifi_ldpc_codec_once(iteration)
        + _wifi_ldpc_rate_matching_once(iteration)
    )


@no_inline
def _bench_phy_chains(iteration: Int) raises -> Float64:
    return (
        _wifi_ht_bcc_chain_once(iteration)
        + _wifi_vht_bcc_chain_once(iteration)
        + _wifi_he_ldpc_chain_once(iteration)
        + _wifi_eht_ldpc_chain_once(iteration)
    )


@no_inline
def _bench_acquisition(iteration: Int) raises -> Float64:
    return (
        _wifi_acquisition_artifacts_once()
        + _wifi_ht_acquisition_once(iteration)
        + _wifi_vht_acquisition_once(iteration)
    )



def _independent_fixed_input_checksum(distance: Int) raises -> Float64:
    comptime iteration = 5
    return (
        _wifi_data_subcarriers_workload()
        + _wifi_pilot_polarity_workload(iteration)
        + _wifi_mcs_profile_workload()
        + _wifi_ofdm_profile_workload()
        + _wifi_ru_profile_workload()
        + _wifi_max_ru_count_workload()
        + _wifi_ru_subcarriers_20mhz_workload()
        + _wifi_ru_pilot_subcarriers_20mhz_workload()
        + _wifi_ru_data_subcarriers_20mhz_workload()
        + _wifi_bcc_puncture_pattern_workload()
        + _wifi_bcc_interleaver_profile_workload()
        + _wifi_ltf_values_20mhz_workload()
        + _wifi_ltf_spectrum_20mhz_workload()
        + _wifi_ltf_waveform_20mhz_workload()
        + _wifi_data_pilot_subcarriers_20mhz_workload()
        + _wifi_data_pilots_20mhz_workload(iteration)
        + _wifi_ht_vht_data_subcarriers_20mhz_workload()
        + _wifi_ldpc_tone_mapping_distance_workload()
        + _wifi_ldpc_tone_permutation_workload(distance)
        + _wifi_stf_spectrum_20mhz_workload()
        + _wifi_stf_short_symbol_20mhz_workload()
        + _wifi_stf_waveform_20mhz_workload()
        + _wifi_legacy_signal_tx_20mhz_workload()
    )


def main() raises:
    # Scalar configuration needed by the permutation workload is built once,
    # before deterministic checks, warmups, and every timed interval.
    var tone_mapping_distance = wifi_ldpc_tone_mapping_distance(242)
    var fixture_bits = _bits(288, 5)
    var fixture_interleaved = wifi_interleave(Span(fixture_bits), 6)
    var fixture_legacy_data = List[Complex64](capacity=48)
    for i in range(48):
        fixture_legacy_data.append(
            Complex64(Float64(i % 9) - 4.0, Float64(i % 7) - 3.0)
        )
    var fixture_legacy_waveform = wifi_map_legacy_symbol(
        Span(fixture_legacy_data), symbol_index=5
    )
    var fixture_known: List[Complex64] = [
        Complex64(1.0, 0.5), Complex64(-0.5, 1.0)
    ]
    var fixture_received: List[Complex64] = [
        fixture_known[0] * Complex64(0.8, -0.2),
        fixture_known[1] * Complex64(0.8, -0.2),
    ]
    var fixture_estimate = wifi_ls_channel_estimate(
        Span(fixture_received), Span(fixture_known)
    )
    var fixture_stf = wifi_stf_waveform_20mhz()
    var fixture_padded_stf = List[Complex64](capacity=163)
    for _ in range(3):
        fixture_padded_stf.append(Complex64(0.0))
    for sample in fixture_stf:
        fixture_padded_stf.append(sample)
    var fixture_shifted_stf = apply_cfo(Span(fixture_padded_stf), 0.001)
    var fixture_detection = wifi_stf_detect(Span(fixture_shifted_stf), 0.8)
    var fixture_rate: List[UInt8] = [1, 1, 0, 1]
    var fixture_signal_bits = wifi_legacy_signal_bits(Span(fixture_rate), 132)
    var fixture_ht_ofdm = wifi_ofdm_profile(WIFI_PHY_HT, 20)
    var fixture_vht_ofdm = wifi_ofdm_profile(WIFI_PHY_VHT, 80)
    var fixture_he_ofdm = wifi_ofdm_profile(WIFI_PHY_HE, 20)
    var fixture_ht_mcs = wifi_mcs_profile(WIFI_PHY_HT, 6)
    var fixture_vht_mcs = wifi_mcs_profile(WIFI_PHY_VHT, 8)
    var fixture_he_mcs = wifi_mcs_profile(WIFI_PHY_HE, 6)
    var fixture_ru = wifi_ru_profile(WIFI_PHY_HE, 106)
    var fixture_ru_sizes: List[Int] = [52, 52]
    var fixture_ru_indices: List[Int] = [0, 1]
    var fixture_ru_data = List[Complex64](capacity=102)
    for i in range(102):
        fixture_ru_data.append(
            Complex64(Float64(i % 13), -Float64(i % 11))
        )
    var fixture_ru_pilots: List[Complex64] = [
        Complex64(1.0), Complex64(-1.0),
        Complex64(1.0), Complex64(-1.0),
    ]
    var fixture_ru_spectrum = wifi_map_ru_symbol_20mhz(
        Span(fixture_ru_data), Span(fixture_ru_pilots), 106, 1
    )
    var fixture_punctured = wifi_bcc_puncture(
        Span(fixture_bits), 3, 4
    )
    var fixture_punctured_llrs = List[Float64](capacity=len(fixture_punctured))
    for bit in fixture_punctured:
        fixture_punctured_llrs.append(1.0 if bit == 0 else -1.0)
    var fixture_bcc_profile = wifi_bcc_interleaver_profile(
        WIFI_PHY_HT, 20
    )
    var fixture_bcc_bits = _bits(312, 10)
    var fixture_bcc_interleaved = wifi_bcc_interleave_block(
        Span(fixture_bcc_bits), 6, fixture_bcc_profile
    )
    var fixture_pilot_indices: List[Int] = [-21, -7, 7, 21]
    var fixture_pilot_known: List[Complex64] = [
        Complex64(1.0), Complex64(1.0),
        Complex64(1.0), Complex64(-1.0),
    ]
    var fixture_pilot_received = List[Complex64](capacity=4)
    for i in range(4):
        var angle = 0.1 + 0.001 * Float64(fixture_pilot_indices[i])
        fixture_pilot_received.append(
            fixture_pilot_known[i] * Complex64(cos(angle), sin(angle))
        )
    var fixture_pilot_estimate = wifi_estimate_pilot_phase(
        Span(fixture_pilot_received),
        Span(fixture_pilot_known),
        Span(fixture_pilot_indices),
    )
    var fixture_ldpc_profile = wifi_ldpc_profile(648, 1, 2)
    var fixture_ldpc_information = _bits(
        fixture_ldpc_profile.information_length, 24
    )
    var fixture_ldpc_encoded = wifi_ldpc_encode(
        Span(fixture_ldpc_information), fixture_ldpc_profile
    )
    var fixture_ldpc_llrs = List[Float64](capacity=648)
    for bit in fixture_ldpc_encoded:
        fixture_ldpc_llrs.append(8.0 if bit == 0 else -8.0)
    var fixture_ldpc_matched = wifi_ldpc_rate_match_block(
        Span(fixture_ldpc_information), fixture_ldpc_profile,
        punctured_bits=4, repeated_bits=2,
    )
    var fixture_ldpc_matched_llrs = List[Float64](
        capacity=len(fixture_ldpc_matched)
    )
    for bit in fixture_ldpc_matched:
        fixture_ldpc_matched_llrs.append(2.0 if bit == 0 else -2.0)
    var fixture_ltf_received = _flat_ltf(WIFI_PHY_EHT)
    var fixture_ht_vht_data = List[Complex64](capacity=52)
    for i in range(52):
        fixture_ht_vht_data.append(
            Complex64(Float64(i % 7), Float64(i % 5))
        )
    var fixture_ht_vht_pilots = wifi_data_pilots_20mhz(WIFI_PHY_VHT, 5)
    var fixture_ht_vht_spectrum = wifi_map_ht_vht_symbol_20mhz(
        Span(fixture_ht_vht_data), Span(fixture_ht_vht_pilots), WIFI_PHY_VHT
    )
    var fixture_tone_bits = _bits(468, 16)
    var fixture_tone_mapped = wifi_ldpc_tone_map_bits(
        Span(fixture_tone_bits), 2, 242
    )
    var fixture_tone_llrs = List[Float64](capacity=468)
    for bit in fixture_tone_mapped:
        fixture_tone_llrs.append(1.0 if bit == 0 else -1.0)
    var fixture_bcc_payload = _bits(18 * 8, 28)
    var fixture_bcc_tx = wifi_bcc_tx_20mhz(
        Span(fixture_bcc_payload), WIFI_PHY_HT, 6, symbol_index=5
    )
    var fixture_bcc_ltf = _flat_ltf(WIFI_PHY_HT)
    var fixture_bcc_samples = List[Complex64](capacity=80)
    for sample in fixture_bcc_tx.waveform:
        fixture_bcc_samples.append(sample * Complex64(0.91, -0.17))
    var fixture_ldpc_payload = _bits(205 * 8, 36)
    var fixture_ldpc_tx = wifi_ldpc_tx_20mhz(
        Span(fixture_ldpc_payload), WIFI_PHY_HE, 10, symbol_index=5
    )
    var fixture_he_ltf = _flat_ltf(WIFI_PHY_HE)
    var fixture_ldpc_samples = List[Complex64](capacity=272)
    for sample in fixture_ldpc_tx.waveform:
        fixture_ldpc_samples.append(sample * Complex64(0.91, -0.17))
    var fixture_acquisition_payload = _bits(9 * 8, 46)
    var fixture_acquisition_tx = wifi_acquisition_tx_20mhz(
        Span(fixture_acquisition_payload), WIFI_PHY_HT, 6, symbol_index=5
    )
    var fixture_channel_config = WifiAcquisitionChannelConfig(
        timing_offset=7, normalized_cfo=0.0015, noise_variance=0.0,
        rician_k_factor=30.0, seed=UInt64(0xAC80216),
    )
    var fixture_channel = wifi_acquisition_apply_channel_20mhz(
        Span(fixture_acquisition_tx.packet_waveform), fixture_channel_config
    )
    var fixture_isolated_ltf = apply_cfo(
        Span(fixture_acquisition_tx.ltf_waveform), 0.0005
    )
    # Every Span passed to an attributable workload is materialized before
    # deterministic checks, warmups, and timed regions.
    var fixture_bits_span = Span(fixture_bits)
    var fixture_interleaved_span = Span(fixture_interleaved)
    var fixture_legacy_data_span = Span(fixture_legacy_data)
    var fixture_legacy_waveform_span = Span(fixture_legacy_waveform)
    var fixture_known_span = Span(fixture_known)
    var fixture_received_span = Span(fixture_received)
    var fixture_estimate_span = Span(fixture_estimate)
    var fixture_shifted_stf_span = Span(fixture_shifted_stf)
    var fixture_rate_span = Span(fixture_rate)
    var fixture_signal_bits_span = Span(fixture_signal_bits)
    var fixture_ru_sizes_span = Span(fixture_ru_sizes)
    var fixture_ru_indices_span = Span(fixture_ru_indices)
    var fixture_ru_data_span = Span(fixture_ru_data)
    var fixture_ru_pilots_span = Span(fixture_ru_pilots)
    var fixture_ru_spectrum_span = Span(fixture_ru_spectrum)
    var fixture_punctured_llrs_span = Span(fixture_punctured_llrs)
    var fixture_bcc_bits_span = Span(fixture_bcc_bits)
    var fixture_bcc_interleaved_span = Span(fixture_bcc_interleaved)
    var fixture_pilot_indices_span = Span(fixture_pilot_indices)
    var fixture_pilot_known_span = Span(fixture_pilot_known)
    var fixture_pilot_received_span = Span(fixture_pilot_received)
    var fixture_ldpc_information_span = Span(fixture_ldpc_information)
    var fixture_ldpc_encoded_span = Span(fixture_ldpc_encoded)
    var fixture_ldpc_llrs_span = Span(fixture_ldpc_llrs)
    var fixture_ldpc_matched_llrs_span = Span(fixture_ldpc_matched_llrs)
    var fixture_ltf_received_span = Span(fixture_ltf_received)
    var fixture_ht_vht_data_span = Span(fixture_ht_vht_data)
    var fixture_ht_vht_pilots_span = Span(fixture_ht_vht_pilots)
    var fixture_ht_vht_spectrum_span = Span(fixture_ht_vht_spectrum)
    var fixture_tone_bits_span = Span(fixture_tone_bits)
    var fixture_tone_llrs_span = Span(fixture_tone_llrs)
    var fixture_bcc_payload_span = Span(fixture_bcc_payload)
    var fixture_bcc_samples_span = Span(fixture_bcc_samples)
    var fixture_bcc_ltf_span = Span(fixture_bcc_ltf)
    var fixture_ldpc_payload_span = Span(fixture_ldpc_payload)
    var fixture_ldpc_samples_span = Span(fixture_ldpc_samples)
    var fixture_he_ltf_span = Span(fixture_he_ltf)
    var fixture_acquisition_payload_span = Span(fixture_acquisition_payload)
    var fixture_acquisition_waveform_span = Span(
        fixture_acquisition_tx.packet_waveform
    )
    var fixture_observation_span = Span(fixture_channel.observation)
    var fixture_isolated_ltf_span = Span(fixture_isolated_ltf)
    var fixture_bits_length = len(fixture_bits)
    var fixture_bcc_payload_length = len(fixture_bcc_payload)
    var fixture_ldpc_payload_length = len(fixture_ldpc_payload)
    var fixture_acquisition_payload_length = len(fixture_acquisition_payload)
    var independent_checksum_first = _independent_fixed_input_checksum(
        tone_mapping_distance
    )
    var independent_checksum_second = _independent_fixed_input_checksum(
        tone_mapping_distance
    )
    if independent_checksum_first != independent_checksum_second:
        raise Error("independent Wi-Fi public workload is nondeterministic")
    keep(independent_checksum_first)
    keep(independent_checksum_second)
    var remaining_checksum_first = (
        _wifi_scramble_workload(Span(fixture_bits))
        + _wifi_interleave_workload(Span(fixture_bits))
        + _wifi_deinterleave_workload(Span(fixture_interleaved))
        + _wifi_map_legacy_symbol_workload(Span(fixture_legacy_data))
        + _wifi_extract_legacy_symbol_workload(Span(fixture_legacy_waveform))
        + _wifi_ls_channel_estimate_workload(Span(fixture_received), Span(fixture_known))
        + _wifi_equalize_workload(Span(fixture_received), Span(fixture_estimate))
        + _wifi_stf_detect_workload(Span(fixture_shifted_stf))
        + _wifi_stf_coarse_cfo_workload(Span(fixture_shifted_stf), fixture_detection)
        + _wifi_legacy_signal_bits_workload(Span(fixture_rate))
        + _wifi_parse_legacy_signal_workload(Span(fixture_signal_bits))
        + _wifi_fcs_workload(Span(fixture_bits))
        + _wifi_guard_interval_samples_workload(fixture_he_ofdm)
        + _wifi_coded_bits_per_symbol_workload(fixture_vht_ofdm, fixture_vht_mcs)
        + _wifi_data_bits_per_symbol_workload(fixture_ht_ofdm, fixture_ht_mcs)
        + _wifi_ru_coded_bits_per_symbol_workload(fixture_ru, fixture_he_mcs)
        + _wifi_ru_data_bits_per_symbol_workload(fixture_ru, fixture_he_mcs)
        + _wifi_ru_requires_ldpc_workload(fixture_ru, fixture_he_mcs)
        + _wifi_ru_allocations_disjoint_20mhz_workload(Span(fixture_ru_sizes), Span(fixture_ru_indices))
        + _wifi_map_ru_symbol_20mhz_workload(Span(fixture_ru_data), Span(fixture_ru_pilots))
        + _wifi_extract_ru_data_20mhz_workload(Span(fixture_ru_spectrum))
        + _wifi_extract_ru_pilots_20mhz_workload(Span(fixture_ru_spectrum))
        + _wifi_bcc_puncture_workload(Span(fixture_bits))
        + _wifi_bcc_depuncture_llrs_workload(Span(fixture_punctured_llrs), len(fixture_bits))
        + _wifi_bcc_interleave_block_workload(Span(fixture_bcc_bits), fixture_bcc_profile)
        + _wifi_bcc_deinterleave_block_workload(Span(fixture_bcc_interleaved), fixture_bcc_profile)
        + _wifi_estimate_pilot_phase_workload(Span(fixture_pilot_received), Span(fixture_pilot_known), Span(fixture_pilot_indices))
        + _wifi_correct_pilot_phase_workload(Span(fixture_pilot_received), Span(fixture_pilot_indices), fixture_pilot_estimate)
        + _wifi_ldpc_profile_workload()
        + _wifi_ldpc_base_shifts_workload(fixture_ldpc_profile)
        + _wifi_ldpc_sparse_graph_workload(fixture_ldpc_profile)
        + _wifi_ldpc_syndrome_ok_workload(Span(fixture_ldpc_encoded), fixture_ldpc_profile)
        + _wifi_ldpc_encode_workload(Span(fixture_ldpc_information), fixture_ldpc_profile)
        + _wifi_ldpc_decode_workload(Span(fixture_ldpc_llrs), fixture_ldpc_profile)
        + _wifi_ldpc_rate_match_block_workload(Span(fixture_ldpc_information), fixture_ldpc_profile)
        + _wifi_ldpc_rate_recover_block_workload(Span(fixture_ldpc_matched_llrs), fixture_ldpc_profile)
        + _wifi_ltf_channel_estimate_20mhz_workload(Span(fixture_ltf_received))
        + _wifi_map_ht_vht_symbol_20mhz_workload(Span(fixture_ht_vht_data), Span(fixture_ht_vht_pilots))
        + _wifi_extract_ht_vht_data_20mhz_workload(Span(fixture_ht_vht_spectrum))
        + _wifi_extract_ht_vht_pilots_20mhz_workload(Span(fixture_ht_vht_spectrum))
        + _wifi_ldpc_tone_map_bits_workload(Span(fixture_tone_bits))
        + _wifi_ldpc_tone_demap_llrs_workload(Span(fixture_tone_llrs))
        + _wifi_bcc_tx_20mhz_workload(Span(fixture_bcc_payload))
        + _wifi_bcc_rx_20mhz_workload(Span(fixture_bcc_samples), Span(fixture_bcc_ltf), len(fixture_bcc_payload))
        + _wifi_ldpc_tx_20mhz_workload(Span(fixture_ldpc_payload))
        + _wifi_ldpc_rx_20mhz_workload(Span(fixture_ldpc_samples), Span(fixture_he_ltf), len(fixture_ldpc_payload))
        + _wifi_acquisition_tx_20mhz_workload(Span(fixture_acquisition_payload))
        + _wifi_acquisition_apply_channel_20mhz_workload(Span(fixture_acquisition_tx.packet_waveform), fixture_channel_config)
        + _wifi_ltf_fine_timing_20mhz_workload(Span(fixture_channel.observation))
        + _wifi_ltf_fine_cfo_20mhz_workload(Span(fixture_isolated_ltf))
        + _wifi_acquisition_rx_20mhz_workload(Span(fixture_channel.observation), len(fixture_acquisition_payload))
    )
    var remaining_checksum_second = (
        _wifi_scramble_workload(Span(fixture_bits))
        + _wifi_interleave_workload(Span(fixture_bits))
        + _wifi_deinterleave_workload(Span(fixture_interleaved))
        + _wifi_map_legacy_symbol_workload(Span(fixture_legacy_data))
        + _wifi_extract_legacy_symbol_workload(Span(fixture_legacy_waveform))
        + _wifi_ls_channel_estimate_workload(Span(fixture_received), Span(fixture_known))
        + _wifi_equalize_workload(Span(fixture_received), Span(fixture_estimate))
        + _wifi_stf_detect_workload(Span(fixture_shifted_stf))
        + _wifi_stf_coarse_cfo_workload(Span(fixture_shifted_stf), fixture_detection)
        + _wifi_legacy_signal_bits_workload(Span(fixture_rate))
        + _wifi_parse_legacy_signal_workload(Span(fixture_signal_bits))
        + _wifi_fcs_workload(Span(fixture_bits))
        + _wifi_guard_interval_samples_workload(fixture_he_ofdm)
        + _wifi_coded_bits_per_symbol_workload(fixture_vht_ofdm, fixture_vht_mcs)
        + _wifi_data_bits_per_symbol_workload(fixture_ht_ofdm, fixture_ht_mcs)
        + _wifi_ru_coded_bits_per_symbol_workload(fixture_ru, fixture_he_mcs)
        + _wifi_ru_data_bits_per_symbol_workload(fixture_ru, fixture_he_mcs)
        + _wifi_ru_requires_ldpc_workload(fixture_ru, fixture_he_mcs)
        + _wifi_ru_allocations_disjoint_20mhz_workload(Span(fixture_ru_sizes), Span(fixture_ru_indices))
        + _wifi_map_ru_symbol_20mhz_workload(Span(fixture_ru_data), Span(fixture_ru_pilots))
        + _wifi_extract_ru_data_20mhz_workload(Span(fixture_ru_spectrum))
        + _wifi_extract_ru_pilots_20mhz_workload(Span(fixture_ru_spectrum))
        + _wifi_bcc_puncture_workload(Span(fixture_bits))
        + _wifi_bcc_depuncture_llrs_workload(Span(fixture_punctured_llrs), len(fixture_bits))
        + _wifi_bcc_interleave_block_workload(Span(fixture_bcc_bits), fixture_bcc_profile)
        + _wifi_bcc_deinterleave_block_workload(Span(fixture_bcc_interleaved), fixture_bcc_profile)
        + _wifi_estimate_pilot_phase_workload(Span(fixture_pilot_received), Span(fixture_pilot_known), Span(fixture_pilot_indices))
        + _wifi_correct_pilot_phase_workload(Span(fixture_pilot_received), Span(fixture_pilot_indices), fixture_pilot_estimate)
        + _wifi_ldpc_profile_workload()
        + _wifi_ldpc_base_shifts_workload(fixture_ldpc_profile)
        + _wifi_ldpc_sparse_graph_workload(fixture_ldpc_profile)
        + _wifi_ldpc_syndrome_ok_workload(Span(fixture_ldpc_encoded), fixture_ldpc_profile)
        + _wifi_ldpc_encode_workload(Span(fixture_ldpc_information), fixture_ldpc_profile)
        + _wifi_ldpc_decode_workload(Span(fixture_ldpc_llrs), fixture_ldpc_profile)
        + _wifi_ldpc_rate_match_block_workload(Span(fixture_ldpc_information), fixture_ldpc_profile)
        + _wifi_ldpc_rate_recover_block_workload(Span(fixture_ldpc_matched_llrs), fixture_ldpc_profile)
        + _wifi_ltf_channel_estimate_20mhz_workload(Span(fixture_ltf_received))
        + _wifi_map_ht_vht_symbol_20mhz_workload(Span(fixture_ht_vht_data), Span(fixture_ht_vht_pilots))
        + _wifi_extract_ht_vht_data_20mhz_workload(Span(fixture_ht_vht_spectrum))
        + _wifi_extract_ht_vht_pilots_20mhz_workload(Span(fixture_ht_vht_spectrum))
        + _wifi_ldpc_tone_map_bits_workload(Span(fixture_tone_bits))
        + _wifi_ldpc_tone_demap_llrs_workload(Span(fixture_tone_llrs))
        + _wifi_bcc_tx_20mhz_workload(Span(fixture_bcc_payload))
        + _wifi_bcc_rx_20mhz_workload(Span(fixture_bcc_samples), Span(fixture_bcc_ltf), len(fixture_bcc_payload))
        + _wifi_ldpc_tx_20mhz_workload(Span(fixture_ldpc_payload))
        + _wifi_ldpc_rx_20mhz_workload(Span(fixture_ldpc_samples), Span(fixture_he_ltf), len(fixture_ldpc_payload))
        + _wifi_acquisition_tx_20mhz_workload(Span(fixture_acquisition_payload))
        + _wifi_acquisition_apply_channel_20mhz_workload(Span(fixture_acquisition_tx.packet_waveform), fixture_channel_config)
        + _wifi_ltf_fine_timing_20mhz_workload(Span(fixture_channel.observation))
        + _wifi_ltf_fine_cfo_20mhz_workload(Span(fixture_isolated_ltf))
        + _wifi_acquisition_rx_20mhz_workload(Span(fixture_channel.observation), len(fixture_acquisition_payload))
    )
    if remaining_checksum_first != remaining_checksum_second:
        raise Error("remaining Wi-Fi public workload is nondeterministic")
    keep(remaining_checksum_first)
    keep(remaining_checksum_second)

    for _ in range(_WARMUPS):
        keep(_wifi_scramble_workload(Span(fixture_bits)))
        keep(_wifi_interleave_workload(Span(fixture_bits)))
        keep(_wifi_deinterleave_workload(Span(fixture_interleaved)))
        keep(_wifi_map_legacy_symbol_workload(Span(fixture_legacy_data)))
        keep(_wifi_extract_legacy_symbol_workload(Span(fixture_legacy_waveform)))
        keep(_wifi_ls_channel_estimate_workload(Span(fixture_received), Span(fixture_known)))
        keep(_wifi_equalize_workload(Span(fixture_received), Span(fixture_estimate)))
        keep(_wifi_stf_detect_workload(Span(fixture_shifted_stf)))
        keep(_wifi_stf_coarse_cfo_workload(Span(fixture_shifted_stf), fixture_detection))
        keep(_wifi_legacy_signal_bits_workload(Span(fixture_rate)))
        keep(_wifi_parse_legacy_signal_workload(Span(fixture_signal_bits)))
        keep(_wifi_fcs_workload(Span(fixture_bits)))
        keep(_wifi_guard_interval_samples_workload(fixture_he_ofdm))
        keep(_wifi_coded_bits_per_symbol_workload(fixture_vht_ofdm, fixture_vht_mcs))
        keep(_wifi_data_bits_per_symbol_workload(fixture_ht_ofdm, fixture_ht_mcs))
        keep(_wifi_ru_coded_bits_per_symbol_workload(fixture_ru, fixture_he_mcs))
        keep(_wifi_ru_data_bits_per_symbol_workload(fixture_ru, fixture_he_mcs))
        keep(_wifi_ru_requires_ldpc_workload(fixture_ru, fixture_he_mcs))
        keep(_wifi_ru_allocations_disjoint_20mhz_workload(Span(fixture_ru_sizes), Span(fixture_ru_indices)))
        keep(_wifi_map_ru_symbol_20mhz_workload(Span(fixture_ru_data), Span(fixture_ru_pilots)))
        keep(_wifi_extract_ru_data_20mhz_workload(Span(fixture_ru_spectrum)))
        keep(_wifi_extract_ru_pilots_20mhz_workload(Span(fixture_ru_spectrum)))
        keep(_wifi_bcc_puncture_workload(Span(fixture_bits)))
        keep(_wifi_bcc_depuncture_llrs_workload(Span(fixture_punctured_llrs), len(fixture_bits)))
        keep(_wifi_bcc_interleave_block_workload(Span(fixture_bcc_bits), fixture_bcc_profile))
        keep(_wifi_bcc_deinterleave_block_workload(Span(fixture_bcc_interleaved), fixture_bcc_profile))
        keep(_wifi_estimate_pilot_phase_workload(Span(fixture_pilot_received), Span(fixture_pilot_known), Span(fixture_pilot_indices)))
        keep(_wifi_correct_pilot_phase_workload(Span(fixture_pilot_received), Span(fixture_pilot_indices), fixture_pilot_estimate))
        keep(_wifi_ldpc_profile_workload())
        keep(_wifi_ldpc_base_shifts_workload(fixture_ldpc_profile))
        keep(_wifi_ldpc_sparse_graph_workload(fixture_ldpc_profile))
        keep(_wifi_ldpc_syndrome_ok_workload(Span(fixture_ldpc_encoded), fixture_ldpc_profile))
        keep(_wifi_ldpc_encode_workload(Span(fixture_ldpc_information), fixture_ldpc_profile))
        keep(_wifi_ldpc_decode_workload(Span(fixture_ldpc_llrs), fixture_ldpc_profile))
        keep(_wifi_ldpc_rate_match_block_workload(Span(fixture_ldpc_information), fixture_ldpc_profile))
        keep(_wifi_ldpc_rate_recover_block_workload(Span(fixture_ldpc_matched_llrs), fixture_ldpc_profile))
        keep(_wifi_ltf_channel_estimate_20mhz_workload(Span(fixture_ltf_received)))
        keep(_wifi_map_ht_vht_symbol_20mhz_workload(Span(fixture_ht_vht_data), Span(fixture_ht_vht_pilots)))
        keep(_wifi_extract_ht_vht_data_20mhz_workload(Span(fixture_ht_vht_spectrum)))
        keep(_wifi_extract_ht_vht_pilots_20mhz_workload(Span(fixture_ht_vht_spectrum)))
        keep(_wifi_ldpc_tone_map_bits_workload(Span(fixture_tone_bits)))
        keep(_wifi_ldpc_tone_demap_llrs_workload(Span(fixture_tone_llrs)))
        keep(_wifi_bcc_tx_20mhz_workload(Span(fixture_bcc_payload)))
        keep(_wifi_bcc_rx_20mhz_workload(Span(fixture_bcc_samples), Span(fixture_bcc_ltf), len(fixture_bcc_payload)))
        keep(_wifi_ldpc_tx_20mhz_workload(Span(fixture_ldpc_payload)))
        keep(_wifi_ldpc_rx_20mhz_workload(Span(fixture_ldpc_samples), Span(fixture_he_ltf), len(fixture_ldpc_payload)))
        keep(_wifi_acquisition_tx_20mhz_workload(Span(fixture_acquisition_payload)))
        keep(_wifi_acquisition_apply_channel_20mhz_workload(Span(fixture_acquisition_tx.packet_waveform), fixture_channel_config))
        keep(_wifi_ltf_fine_timing_20mhz_workload(Span(fixture_channel.observation)))
        keep(_wifi_ltf_fine_cfo_20mhz_workload(Span(fixture_isolated_ltf)))
        keep(_wifi_acquisition_rx_20mhz_workload(Span(fixture_channel.observation), len(fixture_acquisition_payload)))
        keep(_wifi_data_subcarriers_workload())
        keep(_wifi_pilot_polarity_workload(5))
        keep(_wifi_mcs_profile_workload())
        keep(_wifi_ofdm_profile_workload())
        keep(_wifi_ru_profile_workload())
        keep(_wifi_max_ru_count_workload())
        keep(_wifi_ru_subcarriers_20mhz_workload())
        keep(_wifi_ru_pilot_subcarriers_20mhz_workload())
        keep(_wifi_ru_data_subcarriers_20mhz_workload())
        keep(_wifi_bcc_puncture_pattern_workload())
        keep(_wifi_bcc_interleaver_profile_workload())
        keep(_wifi_ltf_values_20mhz_workload())
        keep(_wifi_ltf_spectrum_20mhz_workload())
        keep(_wifi_ltf_waveform_20mhz_workload())
        keep(_wifi_data_pilot_subcarriers_20mhz_workload())
        keep(_wifi_data_pilots_20mhz_workload(5))
        keep(_wifi_ht_vht_data_subcarriers_20mhz_workload())
        keep(_wifi_ldpc_tone_mapping_distance_workload())
        keep(_wifi_ldpc_tone_permutation_workload(tone_mapping_distance))
        keep(_wifi_stf_spectrum_20mhz_workload())
        keep(_wifi_stf_short_symbol_20mhz_workload())
        keep(_wifi_stf_waveform_20mhz_workload())
        keep(_wifi_legacy_signal_tx_20mhz_workload())

    var scramble_samples = List[UInt64](capacity=_SAMPLES)
    var interleave_samples = List[UInt64](capacity=_SAMPLES)
    var deinterleave_samples = List[UInt64](capacity=_SAMPLES)
    var map_legacy_samples = List[UInt64](capacity=_SAMPLES)
    var extract_legacy_samples = List[UInt64](capacity=_SAMPLES)
    var ls_channel_samples = List[UInt64](capacity=_SAMPLES)
    var equalize_samples = List[UInt64](capacity=_SAMPLES)
    var stf_detect_samples = List[UInt64](capacity=_SAMPLES)
    var stf_cfo_samples = List[UInt64](capacity=_SAMPLES)
    var legacy_bits_samples = List[UInt64](capacity=_SAMPLES)
    var parse_signal_samples = List[UInt64](capacity=_SAMPLES)
    var fcs_samples = List[UInt64](capacity=_SAMPLES)
    var guard_samples = List[UInt64](capacity=_SAMPLES)
    var coded_bits_samples = List[UInt64](capacity=_SAMPLES)
    var data_bits_samples = List[UInt64](capacity=_SAMPLES)
    var ru_coded_samples = List[UInt64](capacity=_SAMPLES)
    var ru_data_bits_samples = List[UInt64](capacity=_SAMPLES)
    var ru_ldpc_samples = List[UInt64](capacity=_SAMPLES)
    var ru_disjoint_samples = List[UInt64](capacity=_SAMPLES)
    var map_ru_samples = List[UInt64](capacity=_SAMPLES)
    var extract_ru_data_samples = List[UInt64](capacity=_SAMPLES)
    var extract_ru_pilots_samples = List[UInt64](capacity=_SAMPLES)
    var bcc_puncture_api_samples = List[UInt64](capacity=_SAMPLES)
    var bcc_depuncture_samples = List[UInt64](capacity=_SAMPLES)
    var bcc_interleave_block_samples = List[UInt64](capacity=_SAMPLES)
    var bcc_deinterleave_block_samples = List[UInt64](capacity=_SAMPLES)
    var estimate_phase_samples = List[UInt64](capacity=_SAMPLES)
    var correct_phase_samples = List[UInt64](capacity=_SAMPLES)
    var ldpc_profile_api_samples = List[UInt64](capacity=_SAMPLES)
    var ldpc_shifts_samples = List[UInt64](capacity=_SAMPLES)
    var ldpc_graph_samples = List[UInt64](capacity=_SAMPLES)
    var ldpc_syndrome_samples = List[UInt64](capacity=_SAMPLES)
    var ldpc_encode_samples = List[UInt64](capacity=_SAMPLES)
    var ldpc_decode_samples = List[UInt64](capacity=_SAMPLES)
    var ldpc_match_samples = List[UInt64](capacity=_SAMPLES)
    var ldpc_recover_samples = List[UInt64](capacity=_SAMPLES)
    var ltf_estimate_samples = List[UInt64](capacity=_SAMPLES)
    var map_ht_vht_samples = List[UInt64](capacity=_SAMPLES)
    var extract_ht_vht_data_samples = List[UInt64](capacity=_SAMPLES)
    var extract_ht_vht_pilots_samples = List[UInt64](capacity=_SAMPLES)
    var tone_map_bits_samples = List[UInt64](capacity=_SAMPLES)
    var tone_demap_samples = List[UInt64](capacity=_SAMPLES)
    var bcc_tx_samples = List[UInt64](capacity=_SAMPLES)
    var bcc_rx_samples = List[UInt64](capacity=_SAMPLES)
    var ldpc_tx_samples = List[UInt64](capacity=_SAMPLES)
    var ldpc_rx_samples = List[UInt64](capacity=_SAMPLES)
    var acq_tx_samples = List[UInt64](capacity=_SAMPLES)
    var acq_channel_samples = List[UInt64](capacity=_SAMPLES)
    var fine_timing_samples = List[UInt64](capacity=_SAMPLES)
    var fine_cfo_samples = List[UInt64](capacity=_SAMPLES)
    var acq_rx_samples = List[UInt64](capacity=_SAMPLES)
    var data_subcarriers_samples = List[UInt64](capacity=_SAMPLES)
    var pilot_polarity_samples = List[UInt64](capacity=_SAMPLES)
    var mcs_profile_samples = List[UInt64](capacity=_SAMPLES)
    var ofdm_profile_samples = List[UInt64](capacity=_SAMPLES)
    var ru_profile_samples = List[UInt64](capacity=_SAMPLES)
    var max_ru_count_samples = List[UInt64](capacity=_SAMPLES)
    var ru_subcarriers_samples = List[UInt64](capacity=_SAMPLES)
    var ru_pilot_subcarriers_samples = List[UInt64](capacity=_SAMPLES)
    var ru_data_subcarriers_samples = List[UInt64](capacity=_SAMPLES)
    var puncture_pattern_samples = List[UInt64](capacity=_SAMPLES)
    var interleaver_profile_samples = List[UInt64](capacity=_SAMPLES)
    var ltf_values_samples = List[UInt64](capacity=_SAMPLES)
    var ltf_spectrum_samples = List[UInt64](capacity=_SAMPLES)
    var ltf_waveform_samples = List[UInt64](capacity=_SAMPLES)
    var data_pilot_subcarriers_samples = List[UInt64](capacity=_SAMPLES)
    var data_pilots_samples = List[UInt64](capacity=_SAMPLES)
    var ht_vht_data_subcarriers_samples = List[UInt64](capacity=_SAMPLES)
    var tone_distance_samples = List[UInt64](capacity=_SAMPLES)
    var tone_permutation_samples = List[UInt64](capacity=_SAMPLES)
    var stf_spectrum_samples = List[UInt64](capacity=_SAMPLES)
    var stf_short_samples = List[UInt64](capacity=_SAMPLES)
    var stf_waveform_samples = List[UInt64](capacity=_SAMPLES)
    var legacy_signal_tx_samples = List[UInt64](capacity=_SAMPLES)
    var checksum = 0.0
    for repetition in range(_SAMPLES):
        var start = global_perf_counter_ns()
        var retained = _wifi_scramble_workload(fixture_bits_span)
        scramble_samples.append(global_perf_counter_ns() - start)
        keep(retained); checksum += retained

        start = global_perf_counter_ns()
        retained = _wifi_interleave_workload(fixture_bits_span)
        interleave_samples.append(global_perf_counter_ns() - start)
        keep(retained); checksum += retained

        start = global_perf_counter_ns()
        retained = _wifi_deinterleave_workload(fixture_interleaved_span)
        deinterleave_samples.append(global_perf_counter_ns() - start)
        keep(retained); checksum += retained

        start = global_perf_counter_ns()
        retained = _wifi_map_legacy_symbol_workload(fixture_legacy_data_span)
        map_legacy_samples.append(global_perf_counter_ns() - start)
        keep(retained); checksum += retained

        start = global_perf_counter_ns()
        retained = _wifi_extract_legacy_symbol_workload(fixture_legacy_waveform_span)
        extract_legacy_samples.append(global_perf_counter_ns() - start)
        keep(retained); checksum += retained

        start = global_perf_counter_ns()
        retained = _wifi_ls_channel_estimate_workload(fixture_received_span, fixture_known_span)
        ls_channel_samples.append(global_perf_counter_ns() - start)
        keep(retained); checksum += retained

        start = global_perf_counter_ns()
        retained = _wifi_equalize_workload(fixture_received_span, fixture_estimate_span)
        equalize_samples.append(global_perf_counter_ns() - start)
        keep(retained); checksum += retained

        start = global_perf_counter_ns()
        retained = _wifi_stf_detect_workload(fixture_shifted_stf_span)
        stf_detect_samples.append(global_perf_counter_ns() - start)
        keep(retained); checksum += retained

        start = global_perf_counter_ns()
        retained = _wifi_stf_coarse_cfo_workload(fixture_shifted_stf_span, fixture_detection)
        stf_cfo_samples.append(global_perf_counter_ns() - start)
        keep(retained); checksum += retained

        start = global_perf_counter_ns()
        retained = _wifi_legacy_signal_bits_workload(fixture_rate_span)
        legacy_bits_samples.append(global_perf_counter_ns() - start)
        keep(retained); checksum += retained

        start = global_perf_counter_ns()
        retained = _wifi_parse_legacy_signal_workload(fixture_signal_bits_span)
        parse_signal_samples.append(global_perf_counter_ns() - start)
        keep(retained); checksum += retained

        start = global_perf_counter_ns()
        retained = _wifi_fcs_workload(fixture_bits_span)
        fcs_samples.append(global_perf_counter_ns() - start)
        keep(retained); checksum += retained

        start = global_perf_counter_ns()
        retained = _wifi_guard_interval_samples_workload(fixture_he_ofdm)
        guard_samples.append(global_perf_counter_ns() - start)
        keep(retained); checksum += retained

        start = global_perf_counter_ns()
        retained = _wifi_coded_bits_per_symbol_workload(fixture_vht_ofdm, fixture_vht_mcs)
        coded_bits_samples.append(global_perf_counter_ns() - start)
        keep(retained); checksum += retained

        start = global_perf_counter_ns()
        retained = _wifi_data_bits_per_symbol_workload(fixture_ht_ofdm, fixture_ht_mcs)
        data_bits_samples.append(global_perf_counter_ns() - start)
        keep(retained); checksum += retained

        start = global_perf_counter_ns()
        retained = _wifi_ru_coded_bits_per_symbol_workload(fixture_ru, fixture_he_mcs)
        ru_coded_samples.append(global_perf_counter_ns() - start)
        keep(retained); checksum += retained

        start = global_perf_counter_ns()
        retained = _wifi_ru_data_bits_per_symbol_workload(fixture_ru, fixture_he_mcs)
        ru_data_bits_samples.append(global_perf_counter_ns() - start)
        keep(retained); checksum += retained

        start = global_perf_counter_ns()
        retained = _wifi_ru_requires_ldpc_workload(fixture_ru, fixture_he_mcs)
        ru_ldpc_samples.append(global_perf_counter_ns() - start)
        keep(retained); checksum += retained

        start = global_perf_counter_ns()
        retained = _wifi_ru_allocations_disjoint_20mhz_workload(fixture_ru_sizes_span, fixture_ru_indices_span)
        ru_disjoint_samples.append(global_perf_counter_ns() - start)
        keep(retained); checksum += retained

        start = global_perf_counter_ns()
        retained = _wifi_map_ru_symbol_20mhz_workload(fixture_ru_data_span, fixture_ru_pilots_span)
        map_ru_samples.append(global_perf_counter_ns() - start)
        keep(retained); checksum += retained

        start = global_perf_counter_ns()
        retained = _wifi_extract_ru_data_20mhz_workload(fixture_ru_spectrum_span)
        extract_ru_data_samples.append(global_perf_counter_ns() - start)
        keep(retained); checksum += retained

        start = global_perf_counter_ns()
        retained = _wifi_extract_ru_pilots_20mhz_workload(fixture_ru_spectrum_span)
        extract_ru_pilots_samples.append(global_perf_counter_ns() - start)
        keep(retained); checksum += retained

        start = global_perf_counter_ns()
        retained = _wifi_bcc_puncture_workload(fixture_bits_span)
        bcc_puncture_api_samples.append(global_perf_counter_ns() - start)
        keep(retained); checksum += retained

        start = global_perf_counter_ns()
        retained = _wifi_bcc_depuncture_llrs_workload(fixture_punctured_llrs_span, fixture_bits_length)
        bcc_depuncture_samples.append(global_perf_counter_ns() - start)
        keep(retained); checksum += retained

        start = global_perf_counter_ns()
        retained = _wifi_bcc_interleave_block_workload(fixture_bcc_bits_span, fixture_bcc_profile)
        bcc_interleave_block_samples.append(global_perf_counter_ns() - start)
        keep(retained); checksum += retained

        start = global_perf_counter_ns()
        retained = _wifi_bcc_deinterleave_block_workload(fixture_bcc_interleaved_span, fixture_bcc_profile)
        bcc_deinterleave_block_samples.append(global_perf_counter_ns() - start)
        keep(retained); checksum += retained

        start = global_perf_counter_ns()
        retained = _wifi_estimate_pilot_phase_workload(fixture_pilot_received_span, fixture_pilot_known_span, fixture_pilot_indices_span)
        estimate_phase_samples.append(global_perf_counter_ns() - start)
        keep(retained); checksum += retained

        start = global_perf_counter_ns()
        retained = _wifi_correct_pilot_phase_workload(fixture_pilot_received_span, fixture_pilot_indices_span, fixture_pilot_estimate)
        correct_phase_samples.append(global_perf_counter_ns() - start)
        keep(retained); checksum += retained

        start = global_perf_counter_ns()
        retained = _wifi_ldpc_profile_workload()
        ldpc_profile_api_samples.append(global_perf_counter_ns() - start)
        keep(retained); checksum += retained

        start = global_perf_counter_ns()
        retained = _wifi_ldpc_base_shifts_workload(fixture_ldpc_profile)
        ldpc_shifts_samples.append(global_perf_counter_ns() - start)
        keep(retained); checksum += retained

        start = global_perf_counter_ns()
        retained = _wifi_ldpc_sparse_graph_workload(fixture_ldpc_profile)
        ldpc_graph_samples.append(global_perf_counter_ns() - start)
        keep(retained); checksum += retained

        start = global_perf_counter_ns()
        retained = _wifi_ldpc_syndrome_ok_workload(fixture_ldpc_encoded_span, fixture_ldpc_profile)
        ldpc_syndrome_samples.append(global_perf_counter_ns() - start)
        keep(retained); checksum += retained

        start = global_perf_counter_ns()
        retained = _wifi_ldpc_encode_workload(fixture_ldpc_information_span, fixture_ldpc_profile)
        ldpc_encode_samples.append(global_perf_counter_ns() - start)
        keep(retained); checksum += retained

        start = global_perf_counter_ns()
        retained = _wifi_ldpc_decode_workload(fixture_ldpc_llrs_span, fixture_ldpc_profile)
        ldpc_decode_samples.append(global_perf_counter_ns() - start)
        keep(retained); checksum += retained

        start = global_perf_counter_ns()
        retained = _wifi_ldpc_rate_match_block_workload(fixture_ldpc_information_span, fixture_ldpc_profile)
        ldpc_match_samples.append(global_perf_counter_ns() - start)
        keep(retained); checksum += retained

        start = global_perf_counter_ns()
        retained = _wifi_ldpc_rate_recover_block_workload(fixture_ldpc_matched_llrs_span, fixture_ldpc_profile)
        ldpc_recover_samples.append(global_perf_counter_ns() - start)
        keep(retained); checksum += retained

        start = global_perf_counter_ns()
        retained = _wifi_ltf_channel_estimate_20mhz_workload(fixture_ltf_received_span)
        ltf_estimate_samples.append(global_perf_counter_ns() - start)
        keep(retained); checksum += retained

        start = global_perf_counter_ns()
        retained = _wifi_map_ht_vht_symbol_20mhz_workload(fixture_ht_vht_data_span, fixture_ht_vht_pilots_span)
        map_ht_vht_samples.append(global_perf_counter_ns() - start)
        keep(retained); checksum += retained

        start = global_perf_counter_ns()
        retained = _wifi_extract_ht_vht_data_20mhz_workload(fixture_ht_vht_spectrum_span)
        extract_ht_vht_data_samples.append(global_perf_counter_ns() - start)
        keep(retained); checksum += retained

        start = global_perf_counter_ns()
        retained = _wifi_extract_ht_vht_pilots_20mhz_workload(fixture_ht_vht_spectrum_span)
        extract_ht_vht_pilots_samples.append(global_perf_counter_ns() - start)
        keep(retained); checksum += retained

        start = global_perf_counter_ns()
        retained = _wifi_ldpc_tone_map_bits_workload(fixture_tone_bits_span)
        tone_map_bits_samples.append(global_perf_counter_ns() - start)
        keep(retained); checksum += retained

        start = global_perf_counter_ns()
        retained = _wifi_ldpc_tone_demap_llrs_workload(fixture_tone_llrs_span)
        tone_demap_samples.append(global_perf_counter_ns() - start)
        keep(retained); checksum += retained

        start = global_perf_counter_ns()
        retained = _wifi_bcc_tx_20mhz_workload(fixture_bcc_payload_span)
        bcc_tx_samples.append(global_perf_counter_ns() - start)
        keep(retained); checksum += retained

        start = global_perf_counter_ns()
        retained = _wifi_bcc_rx_20mhz_workload(fixture_bcc_samples_span, fixture_bcc_ltf_span, fixture_bcc_payload_length)
        bcc_rx_samples.append(global_perf_counter_ns() - start)
        keep(retained); checksum += retained

        start = global_perf_counter_ns()
        retained = _wifi_ldpc_tx_20mhz_workload(fixture_ldpc_payload_span)
        ldpc_tx_samples.append(global_perf_counter_ns() - start)
        keep(retained); checksum += retained

        start = global_perf_counter_ns()
        retained = _wifi_ldpc_rx_20mhz_workload(fixture_ldpc_samples_span, fixture_he_ltf_span, fixture_ldpc_payload_length)
        ldpc_rx_samples.append(global_perf_counter_ns() - start)
        keep(retained); checksum += retained

        start = global_perf_counter_ns()
        retained = _wifi_acquisition_tx_20mhz_workload(fixture_acquisition_payload_span)
        acq_tx_samples.append(global_perf_counter_ns() - start)
        keep(retained); checksum += retained

        start = global_perf_counter_ns()
        retained = _wifi_acquisition_apply_channel_20mhz_workload(fixture_acquisition_waveform_span, fixture_channel_config)
        acq_channel_samples.append(global_perf_counter_ns() - start)
        keep(retained); checksum += retained

        start = global_perf_counter_ns()
        retained = _wifi_ltf_fine_timing_20mhz_workload(fixture_observation_span)
        fine_timing_samples.append(global_perf_counter_ns() - start)
        keep(retained); checksum += retained

        start = global_perf_counter_ns()
        retained = _wifi_ltf_fine_cfo_20mhz_workload(fixture_isolated_ltf_span)
        fine_cfo_samples.append(global_perf_counter_ns() - start)
        keep(retained); checksum += retained

        start = global_perf_counter_ns()
        retained = _wifi_acquisition_rx_20mhz_workload(fixture_observation_span, fixture_acquisition_payload_length)
        acq_rx_samples.append(global_perf_counter_ns() - start)
        keep(retained); checksum += retained

        start = global_perf_counter_ns()
        retained = _wifi_data_subcarriers_workload()
        data_subcarriers_samples.append(global_perf_counter_ns() - start)
        keep(retained); checksum += retained * Float64(repetition + 101)

        start = global_perf_counter_ns()
        retained = _wifi_pilot_polarity_workload(5)
        pilot_polarity_samples.append(global_perf_counter_ns() - start)
        keep(retained); checksum += retained * Float64(repetition + 103)

        start = global_perf_counter_ns()
        retained = _wifi_mcs_profile_workload()
        mcs_profile_samples.append(global_perf_counter_ns() - start)
        keep(retained); checksum += retained * Float64(repetition + 107)

        start = global_perf_counter_ns()
        retained = _wifi_ofdm_profile_workload()
        ofdm_profile_samples.append(global_perf_counter_ns() - start)
        keep(retained); checksum += retained * Float64(repetition + 109)

        start = global_perf_counter_ns()
        retained = _wifi_ru_profile_workload()
        ru_profile_samples.append(global_perf_counter_ns() - start)
        keep(retained); checksum += retained * Float64(repetition + 113)

        start = global_perf_counter_ns()
        retained = _wifi_max_ru_count_workload()
        max_ru_count_samples.append(global_perf_counter_ns() - start)
        keep(retained); checksum += retained * Float64(repetition + 127)

        start = global_perf_counter_ns()
        retained = _wifi_ru_subcarriers_20mhz_workload()
        ru_subcarriers_samples.append(global_perf_counter_ns() - start)
        keep(retained); checksum += retained * Float64(repetition + 131)

        start = global_perf_counter_ns()
        retained = _wifi_ru_pilot_subcarriers_20mhz_workload()
        ru_pilot_subcarriers_samples.append(global_perf_counter_ns() - start)
        keep(retained); checksum += retained * Float64(repetition + 137)

        start = global_perf_counter_ns()
        retained = _wifi_ru_data_subcarriers_20mhz_workload()
        ru_data_subcarriers_samples.append(global_perf_counter_ns() - start)
        keep(retained); checksum += retained * Float64(repetition + 139)

        start = global_perf_counter_ns()
        retained = _wifi_bcc_puncture_pattern_workload()
        puncture_pattern_samples.append(global_perf_counter_ns() - start)
        keep(retained); checksum += retained * Float64(repetition + 149)

        start = global_perf_counter_ns()
        retained = _wifi_bcc_interleaver_profile_workload()
        interleaver_profile_samples.append(global_perf_counter_ns() - start)
        keep(retained); checksum += retained * Float64(repetition + 151)

        start = global_perf_counter_ns()
        retained = _wifi_ltf_values_20mhz_workload()
        ltf_values_samples.append(global_perf_counter_ns() - start)
        keep(retained); checksum += retained * Float64(repetition + 157)

        start = global_perf_counter_ns()
        retained = _wifi_ltf_spectrum_20mhz_workload()
        ltf_spectrum_samples.append(global_perf_counter_ns() - start)
        keep(retained); checksum += retained * Float64(repetition + 163)

        start = global_perf_counter_ns()
        retained = _wifi_ltf_waveform_20mhz_workload()
        ltf_waveform_samples.append(global_perf_counter_ns() - start)
        keep(retained); checksum += retained * Float64(repetition + 167)

        start = global_perf_counter_ns()
        retained = _wifi_data_pilot_subcarriers_20mhz_workload()
        data_pilot_subcarriers_samples.append(global_perf_counter_ns() - start)
        keep(retained); checksum += retained * Float64(repetition + 173)

        start = global_perf_counter_ns()
        retained = _wifi_data_pilots_20mhz_workload(5)
        data_pilots_samples.append(global_perf_counter_ns() - start)
        keep(retained); checksum += retained * Float64(repetition + 179)

        start = global_perf_counter_ns()
        retained = _wifi_ht_vht_data_subcarriers_20mhz_workload()
        ht_vht_data_subcarriers_samples.append(global_perf_counter_ns() - start)
        keep(retained); checksum += retained * Float64(repetition + 181)

        start = global_perf_counter_ns()
        retained = _wifi_ldpc_tone_mapping_distance_workload()
        tone_distance_samples.append(global_perf_counter_ns() - start)
        keep(retained); checksum += retained * Float64(repetition + 191)

        start = global_perf_counter_ns()
        retained = _wifi_ldpc_tone_permutation_workload(tone_mapping_distance)
        tone_permutation_samples.append(global_perf_counter_ns() - start)
        keep(retained); checksum += retained * Float64(repetition + 193)

        start = global_perf_counter_ns()
        retained = _wifi_stf_spectrum_20mhz_workload()
        stf_spectrum_samples.append(global_perf_counter_ns() - start)
        keep(retained); checksum += retained * Float64(repetition + 197)

        start = global_perf_counter_ns()
        retained = _wifi_stf_short_symbol_20mhz_workload()
        stf_short_samples.append(global_perf_counter_ns() - start)
        keep(retained); checksum += retained * Float64(repetition + 199)

        start = global_perf_counter_ns()
        retained = _wifi_stf_waveform_20mhz_workload()
        stf_waveform_samples.append(global_perf_counter_ns() - start)
        keep(retained); checksum += retained * Float64(repetition + 211)

        start = global_perf_counter_ns()
        retained = _wifi_legacy_signal_tx_20mhz_workload()
        legacy_signal_tx_samples.append(global_perf_counter_ns() - start)
        keep(retained); checksum += retained * Float64(repetition + 223)


    print_benchmark_metadata()
    var alignment_probe = _bits(256, 97)
    print_runtime_buffer_alignment(
        "wifi_public_uint8_payload",
        Int(alignment_probe.unsafe_ptr()),
        align_of[UInt8](),
    )
    report_timing_samples("wifi_scramble", scramble_samples, _WARMUPS, 1, "wifi_scramble_call")
    report_timing_samples("wifi_interleave", interleave_samples, _WARMUPS, 1, "wifi_interleave_call")
    report_timing_samples("wifi_deinterleave", deinterleave_samples, _WARMUPS, 1, "wifi_deinterleave_call")
    report_timing_samples("wifi_map_legacy_symbol", map_legacy_samples, _WARMUPS, 1, "wifi_map_legacy_symbol_call")
    report_timing_samples("wifi_extract_legacy_symbol", extract_legacy_samples, _WARMUPS, 1, "wifi_extract_legacy_symbol_call")
    report_timing_samples("wifi_ls_channel_estimate", ls_channel_samples, _WARMUPS, 1, "wifi_ls_channel_estimate_call")
    report_timing_samples("wifi_equalize", equalize_samples, _WARMUPS, 1, "wifi_equalize_call")
    report_timing_samples("wifi_stf_detect", stf_detect_samples, _WARMUPS, 1, "wifi_stf_detect_call")
    report_timing_samples("wifi_stf_coarse_cfo", stf_cfo_samples, _WARMUPS, 1, "wifi_stf_coarse_cfo_call")
    report_timing_samples("wifi_legacy_signal_bits", legacy_bits_samples, _WARMUPS, 1, "wifi_legacy_signal_bits_call")
    report_timing_samples("wifi_parse_legacy_signal", parse_signal_samples, _WARMUPS, 1, "wifi_parse_legacy_signal_call")
    report_timing_samples("wifi_fcs", fcs_samples, _WARMUPS, 1, "wifi_fcs_call")
    report_timing_samples("wifi_guard_interval_samples", guard_samples, _WARMUPS, 1, "wifi_guard_interval_samples_call")
    report_timing_samples("wifi_coded_bits_per_symbol", coded_bits_samples, _WARMUPS, 1, "wifi_coded_bits_per_symbol_call")
    report_timing_samples("wifi_data_bits_per_symbol", data_bits_samples, _WARMUPS, 1, "wifi_data_bits_per_symbol_call")
    report_timing_samples("wifi_ru_coded_bits_per_symbol", ru_coded_samples, _WARMUPS, 1, "wifi_ru_coded_bits_per_symbol_call")
    report_timing_samples("wifi_ru_data_bits_per_symbol", ru_data_bits_samples, _WARMUPS, 1, "wifi_ru_data_bits_per_symbol_call")
    report_timing_samples("wifi_ru_requires_ldpc", ru_ldpc_samples, _WARMUPS, 1, "wifi_ru_requires_ldpc_call")
    report_timing_samples("wifi_ru_allocations_disjoint_20mhz", ru_disjoint_samples, _WARMUPS, 1, "wifi_ru_allocations_disjoint_call")
    report_timing_samples("wifi_map_ru_symbol_20mhz", map_ru_samples, _WARMUPS, 1, "wifi_map_ru_symbol_call")
    report_timing_samples("wifi_extract_ru_data_20mhz", extract_ru_data_samples, _WARMUPS, 1, "wifi_extract_ru_data_call")
    report_timing_samples("wifi_extract_ru_pilots_20mhz", extract_ru_pilots_samples, _WARMUPS, 1, "wifi_extract_ru_pilots_call")
    report_timing_samples("wifi_bcc_puncture", bcc_puncture_api_samples, _WARMUPS, 1, "wifi_bcc_puncture_call")
    report_timing_samples("wifi_bcc_depuncture_llrs", bcc_depuncture_samples, _WARMUPS, 1, "wifi_bcc_depuncture_llrs_call")
    report_timing_samples("wifi_bcc_interleave_block", bcc_interleave_block_samples, _WARMUPS, 1, "wifi_bcc_interleave_block_call")
    report_timing_samples("wifi_bcc_deinterleave_block", bcc_deinterleave_block_samples, _WARMUPS, 1, "wifi_bcc_deinterleave_block_call")
    report_timing_samples("wifi_estimate_pilot_phase", estimate_phase_samples, _WARMUPS, 1, "wifi_estimate_pilot_phase_call")
    report_timing_samples("wifi_correct_pilot_phase", correct_phase_samples, _WARMUPS, 1, "wifi_correct_pilot_phase_call")
    report_timing_samples("wifi_ldpc_profile", ldpc_profile_api_samples, _WARMUPS, 1, "wifi_ldpc_profile_call")
    report_timing_samples("wifi_ldpc_base_shifts", ldpc_shifts_samples, _WARMUPS, 1, "wifi_ldpc_base_shifts_call")
    report_timing_samples("wifi_ldpc_sparse_graph", ldpc_graph_samples, _WARMUPS, 1, "wifi_ldpc_sparse_graph_call")
    report_timing_samples("wifi_ldpc_syndrome_ok", ldpc_syndrome_samples, _WARMUPS, 1, "wifi_ldpc_syndrome_ok_call")
    report_timing_samples("wifi_ldpc_encode", ldpc_encode_samples, _WARMUPS, 1, "wifi_ldpc_encode_call")
    report_timing_samples("wifi_ldpc_decode", ldpc_decode_samples, _WARMUPS, 1, "wifi_ldpc_decode_call")
    report_timing_samples("wifi_ldpc_rate_match_block", ldpc_match_samples, _WARMUPS, 1, "wifi_ldpc_rate_match_block_call")
    report_timing_samples("wifi_ldpc_rate_recover_block", ldpc_recover_samples, _WARMUPS, 1, "wifi_ldpc_rate_recover_block_call")
    report_timing_samples("wifi_ltf_channel_estimate_20mhz", ltf_estimate_samples, _WARMUPS, 1, "wifi_ltf_channel_estimate_call")
    report_timing_samples("wifi_map_ht_vht_symbol_20mhz", map_ht_vht_samples, _WARMUPS, 1, "wifi_map_ht_vht_symbol_call")
    report_timing_samples("wifi_extract_ht_vht_data_20mhz", extract_ht_vht_data_samples, _WARMUPS, 1, "wifi_extract_ht_vht_data_call")
    report_timing_samples("wifi_extract_ht_vht_pilots_20mhz", extract_ht_vht_pilots_samples, _WARMUPS, 1, "wifi_extract_ht_vht_pilots_call")
    report_timing_samples("wifi_ldpc_tone_map_bits", tone_map_bits_samples, _WARMUPS, 1, "wifi_ldpc_tone_map_bits_call")
    report_timing_samples("wifi_ldpc_tone_demap_llrs", tone_demap_samples, _WARMUPS, 1, "wifi_ldpc_tone_demap_llrs_call")
    report_timing_samples("wifi_bcc_tx_20mhz", bcc_tx_samples, _WARMUPS, 1, "wifi_bcc_tx_call")
    report_timing_samples("wifi_bcc_rx_20mhz", bcc_rx_samples, _WARMUPS, 1, "wifi_bcc_rx_call")
    report_timing_samples("wifi_ldpc_tx_20mhz", ldpc_tx_samples, _WARMUPS, 1, "wifi_ldpc_tx_call")
    report_timing_samples("wifi_ldpc_rx_20mhz", ldpc_rx_samples, _WARMUPS, 1, "wifi_ldpc_rx_call")
    report_timing_samples("wifi_acquisition_tx_20mhz", acq_tx_samples, _WARMUPS, 1, "wifi_acquisition_tx_call")
    report_timing_samples("wifi_acquisition_apply_channel_20mhz", acq_channel_samples, _WARMUPS, 1, "wifi_acquisition_apply_channel_call")
    report_timing_samples("wifi_ltf_fine_timing_20mhz", fine_timing_samples, _WARMUPS, 1, "wifi_ltf_fine_timing_call")
    report_timing_samples("wifi_ltf_fine_cfo_20mhz", fine_cfo_samples, _WARMUPS, 1, "wifi_ltf_fine_cfo_call")
    report_timing_samples("wifi_acquisition_rx_20mhz", acq_rx_samples, _WARMUPS, 1, "wifi_acquisition_rx_call")
    report_timing_samples("wifi_data_subcarriers", data_subcarriers_samples, _WARMUPS, 1, "wifi_data_subcarriers_call")
    report_timing_samples("wifi_pilot_polarity", pilot_polarity_samples, _WARMUPS, 1, "wifi_pilot_polarity_call")
    report_timing_samples("wifi_mcs_profile", mcs_profile_samples, _WARMUPS, 1, "wifi_mcs_profile_call")
    report_timing_samples("wifi_ofdm_profile", ofdm_profile_samples, _WARMUPS, 1, "wifi_ofdm_profile_call")
    report_timing_samples("wifi_ru_profile", ru_profile_samples, _WARMUPS, 1, "wifi_ru_profile_call")
    report_timing_samples("wifi_max_ru_count", max_ru_count_samples, _WARMUPS, 1, "wifi_max_ru_count_call")
    report_timing_samples("wifi_ru_subcarriers_20mhz", ru_subcarriers_samples, _WARMUPS, 1, "wifi_ru_subcarriers_call")
    report_timing_samples("wifi_ru_pilot_subcarriers_20mhz", ru_pilot_subcarriers_samples, _WARMUPS, 1, "wifi_ru_pilot_subcarriers_call")
    report_timing_samples("wifi_ru_data_subcarriers_20mhz", ru_data_subcarriers_samples, _WARMUPS, 1, "wifi_ru_data_subcarriers_call")
    report_timing_samples("wifi_bcc_puncture_pattern", puncture_pattern_samples, _WARMUPS, 1, "wifi_bcc_puncture_pattern_call")
    report_timing_samples("wifi_bcc_interleaver_profile", interleaver_profile_samples, _WARMUPS, 1, "wifi_bcc_interleaver_profile_call")
    report_timing_samples("wifi_ltf_values_20mhz", ltf_values_samples, _WARMUPS, 1, "wifi_ltf_values_call")
    report_timing_samples("wifi_ltf_spectrum_20mhz", ltf_spectrum_samples, _WARMUPS, 1, "wifi_ltf_spectrum_call")
    report_timing_samples("wifi_ltf_waveform_20mhz", ltf_waveform_samples, _WARMUPS, 1, "wifi_ltf_waveform_call")
    report_timing_samples("wifi_data_pilot_subcarriers_20mhz", data_pilot_subcarriers_samples, _WARMUPS, 1, "wifi_data_pilot_subcarriers_call")
    report_timing_samples("wifi_data_pilots_20mhz", data_pilots_samples, _WARMUPS, 1, "wifi_data_pilots_call")
    report_timing_samples("wifi_ht_vht_data_subcarriers_20mhz", ht_vht_data_subcarriers_samples, _WARMUPS, 1, "wifi_ht_vht_data_subcarriers_call")
    report_timing_samples("wifi_ldpc_tone_mapping_distance", tone_distance_samples, _WARMUPS, 1, "wifi_ldpc_tone_mapping_distance_call")
    report_timing_samples("wifi_ldpc_tone_permutation", tone_permutation_samples, _WARMUPS, 1, "wifi_ldpc_tone_permutation_call")
    report_timing_samples("wifi_stf_spectrum_20mhz", stf_spectrum_samples, _WARMUPS, 1, "wifi_stf_spectrum_call")
    report_timing_samples("wifi_stf_short_symbol_20mhz", stf_short_samples, _WARMUPS, 1, "wifi_stf_short_symbol_call")
    report_timing_samples("wifi_stf_waveform_20mhz", stf_waveform_samples, _WARMUPS, 1, "wifi_stf_waveform_call")
    report_timing_samples("wifi_legacy_signal_tx_20mhz", legacy_signal_tx_samples, _WARMUPS, 1, "wifi_legacy_signal_tx_call")
    keep(checksum)
    print("wifi_public_retained_checksum:", checksum)
