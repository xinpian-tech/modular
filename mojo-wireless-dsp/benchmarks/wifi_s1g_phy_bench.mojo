"""Attributable CPU timings for bounded Clause-23 S1G PHY APIs.

Every public algorithm is a separate family with three untimed warmups and
nine odd samples.  A fixed salt changes valid table/configuration rows.
Every returned scalar, struct field, and allocated occupied tone contributes
to the retained checksum.
"""

from std.benchmark import black_box, keep
from std.time import global_perf_counter_ns
from wireless_dsp.benchmarking import (
    print_benchmark_metadata,
    report_timing_samples,
)
from wireless_dsp.wireless.wifi.s1g_phy import (
    WifiS1GBCCSUConfig,
    wifi_s1g_ofdm_profile,
    wifi_s1g_occupied_subcarriers,
    wifi_s1g_subcarrier_frequency_hz,
    wifi_s1g_mcs_profile,
    wifi_s1g_bcc_su_long_gi_geometry,
)


comptime _WARMUPS = 3
comptime _SAMPLES = 9
comptime _TABLE_BATCH = 4096
comptime _TONE_BATCH = 64
comptime _FIXED_SALT = 324508639


def _mix(checksum: UInt64, value: Int) -> UInt64:
    return (checksum ^ UInt64(value + 257)) * UInt64(1099511628211)


def _bandwidth(selector: Int) -> Int:
    var row = selector % 5
    if row == 0:
        return 1
    if row == 1:
        return 2
    if row == 2:
        return 4
    if row == 3:
        return 8
    return 16


@no_inline
def _ofdm_profile_workload(iterations: Int, salt: Int) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for operation in range(iterations):
        var profile = wifi_s1g_ofdm_profile(
            black_box(_bandwidth(operation + salt))
        )
        checksum = _mix(checksum, profile.bandwidth_mhz)
        checksum = _mix(checksum, profile.fft_size)
        checksum = _mix(checksum, profile.data_subcarriers)
        checksum = _mix(checksum, profile.pilot_subcarriers)
        checksum = _mix(checksum, profile.occupied_subcarriers)
        checksum = _mix(checksum, profile.highest_occupied_index)
        checksum = _mix(checksum, profile.subcarrier_spacing_hz)
        checksum = _mix(checksum, profile.fft_period_ns)
        checksum = _mix(checksum, profile.long_gi_ns)
        checksum = _mix(checksum, profile.short_gi_ns)
        checksum = _mix(checksum, profile.long_symbol_ns)
        checksum = _mix(checksum, profile.short_symbol_ns + operation)
    return checksum


@no_inline
def _occupied_tones_workload(iterations: Int) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for operation in range(iterations):
        var tones = wifi_s1g_occupied_subcarriers(black_box(16))
        for index in range(len(tones)):
            checksum = _mix(checksum, tones[index] + index + operation)
        keep(tones)
    return checksum


def _valid_positive_tone(bandwidth_mhz: Int, selector: Int) -> Int:
    if bandwidth_mhz == 1:
        return 1 + selector % 13
    if bandwidth_mhz == 2:
        return 1 + selector % 28
    if bandwidth_mhz == 4:
        return 2 + selector % 57
    if bandwidth_mhz == 8:
        return 2 + selector % 121
    return 6 + selector % 121


@no_inline
def _frequency_workload(iterations: Int, salt: Int) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for operation in range(iterations):
        var selector = operation + salt
        var bandwidth = _bandwidth(selector)
        var frequency = wifi_s1g_subcarrier_frequency_hz(
            black_box(902_000_000.0 + Float64(selector & 1023)),
            black_box(bandwidth),
            black_box(_valid_positive_tone(bandwidth, selector)),
        )
        checksum = _mix(checksum, Int(frequency) + operation)
    return checksum


@no_inline
def _mcs_profile_workload(iterations: Int, salt: Int) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for operation in range(iterations):
        var selector = operation + salt
        var bandwidth = _bandwidth(selector)
        var mcs_index = selector % 10
        if bandwidth == 2 and mcs_index == 9:
            mcs_index = 8
        if bandwidth == 1 and (selector & 31) == 0:
            mcs_index = 10
        var profile = wifi_s1g_mcs_profile(
            black_box(bandwidth), black_box(mcs_index)
        )
        checksum = _mix(checksum, profile.bandwidth_mhz)
        checksum = _mix(checksum, profile.mcs_index)
        checksum = _mix(checksum, profile.bits_per_subcarrier)
        checksum = _mix(
            checksum, profile.effective_code_rate_numerator
        )
        checksum = _mix(
            checksum, profile.effective_code_rate_denominator
        )
        checksum = _mix(checksum, profile.bcc_repetition_factor)
        checksum = _mix(checksum, profile.data_subcarriers)
        checksum = _mix(checksum, profile.pilot_subcarriers)
        checksum = _mix(checksum, profile.coded_bits_per_symbol)
        checksum = _mix(checksum, profile.data_bits_per_symbol)
        checksum = _mix(checksum, profile.long_gi_data_rate_bps + operation)
    return checksum


@no_inline
def _geometry_workload(iterations: Int, salt: Int) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for operation in range(iterations):
        var selector = operation + salt
        var bandwidth = _bandwidth(selector)
        var mcs_index = selector % 10
        if bandwidth == 2 and mcs_index == 9:
            mcs_index = 8
        if bandwidth == 1 and (selector & 31) == 0:
            mcs_index = 10
        var config = WifiS1GBCCSUConfig(
            black_box(bandwidth),
            black_box(mcs_index),
            black_box(1 + selector % 400),
        )
        var geometry = wifi_s1g_bcc_su_long_gi_geometry(config)
        checksum = _mix(checksum, geometry.bandwidth_mhz)
        checksum = _mix(checksum, geometry.mcs_index)
        checksum = _mix(checksum, geometry.psdu_length_octets)
        checksum = _mix(checksum, geometry.data_bits_per_symbol)
        checksum = _mix(checksum, geometry.data_bits_before_pad)
        checksum = _mix(checksum, geometry.pad_bits)
        checksum = _mix(checksum, geometry.data_symbols)
        checksum = _mix(checksum, geometry.preamble_duration_ns)
        checksum = _mix(checksum, geometry.data_duration_ns)
        checksum = _mix(checksum, geometry.ppdu_duration_ns)
        checksum = _mix(
            checksum, 1 if geometry.s1g_1m_format else 0
        )
    return checksum


def main() raises:
    for warmup in range(_WARMUPS):
        var salt = _FIXED_SALT + warmup
        keep(_ofdm_profile_workload(_TABLE_BATCH, salt))
        keep(_occupied_tones_workload(_TONE_BATCH))
        keep(_frequency_workload(_TABLE_BATCH, salt))
        keep(_mcs_profile_workload(_TABLE_BATCH, salt))
        keep(_geometry_workload(_TABLE_BATCH, salt))

    var ofdm_samples = List[UInt64](capacity=_SAMPLES)
    var tones_samples = List[UInt64](capacity=_SAMPLES)
    var frequency_samples = List[UInt64](capacity=_SAMPLES)
    var mcs_samples = List[UInt64](capacity=_SAMPLES)
    var geometry_samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for sample in range(_SAMPLES):
        var salt = _FIXED_SALT + sample
        var start = global_perf_counter_ns()
        var ofdm_checksum = _ofdm_profile_workload(_TABLE_BATCH, salt)
        ofdm_samples.append(global_perf_counter_ns() - start)
        checksum = _mix(checksum, Int(ofdm_checksum & UInt64(Int.MAX)))
        keep(ofdm_checksum)

        start = global_perf_counter_ns()
        var tones_checksum = _occupied_tones_workload(_TONE_BATCH)
        tones_samples.append(global_perf_counter_ns() - start)
        checksum = _mix(checksum, Int(tones_checksum & UInt64(Int.MAX)))
        keep(tones_checksum)

        start = global_perf_counter_ns()
        var frequency_checksum = _frequency_workload(_TABLE_BATCH, salt)
        frequency_samples.append(global_perf_counter_ns() - start)
        checksum = _mix(
            checksum, Int(frequency_checksum & UInt64(Int.MAX))
        )
        keep(frequency_checksum)

        start = global_perf_counter_ns()
        var mcs_checksum = _mcs_profile_workload(_TABLE_BATCH, salt)
        mcs_samples.append(global_perf_counter_ns() - start)
        checksum = _mix(checksum, Int(mcs_checksum & UInt64(Int.MAX)))
        keep(mcs_checksum)

        start = global_perf_counter_ns()
        var geometry_checksum = _geometry_workload(_TABLE_BATCH, salt)
        geometry_samples.append(global_perf_counter_ns() - start)
        checksum = _mix(
            checksum, Int(geometry_checksum & UInt64(Int.MAX))
        )
        keep(geometry_checksum)

    print_benchmark_metadata()
    print("wifi_s1g_phy_backend:", "scalar-cpu-reference")
    print(
        "wifi_s1g_phy_baseline:",
        "IEEE-802.11-2024-Clause-23.3.4-23.5-bounded",
    )
    report_timing_samples(
        "wifi_s1g_ofdm_profile",
        ofdm_samples,
        _WARMUPS,
        _TABLE_BATCH,
        "profile",
    )
    report_timing_samples(
        "wifi_s1g_occupied_subcarriers",
        tones_samples,
        _WARMUPS,
        _TONE_BATCH * 484,
        "occupied_tone",
    )
    report_timing_samples(
        "wifi_s1g_subcarrier_frequency_hz",
        frequency_samples,
        _WARMUPS,
        _TABLE_BATCH,
        "mapped_tone",
    )
    report_timing_samples(
        "wifi_s1g_mcs_profile",
        mcs_samples,
        _WARMUPS,
        _TABLE_BATCH,
        "profile",
    )
    report_timing_samples(
        "wifi_s1g_bcc_su_long_gi_geometry",
        geometry_samples,
        _WARMUPS,
        _TABLE_BATCH,
        "geometry",
    )
    keep(checksum)
    print("wifi_s1g_phy_retained_checksum:", checksum)
