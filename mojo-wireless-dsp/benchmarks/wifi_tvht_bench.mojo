"""Attributable CPU timings for bounded Clause-22 TVHT PHY APIs.

Each public algorithm has a separate no-inline workload, three untimed
warmups, and nine odd timing samples.  All mutable configurations are fully
prebuilt before timing.  Fixed salts select valid configurations
deterministically.  Owned list results are retained and O(1) endpoint
fingerprints feed a fixed checksum, so no second length-dependent scan
contaminates table timings.
"""

from std.benchmark import black_box, keep
from std.collections import Span
from std.time import global_perf_counter_ns
from wireless_dsp.benchmarking import (
    print_benchmark_metadata,
    report_timing_samples,
)
from wireless_dsp.wireless.wifi.tvht import (
    WIFI_TVHT_MODE_1,
    WIFI_TVHT_MODE_2C,
    WIFI_TVHT_MODE_2N,
    WIFI_TVHT_MODE_4C,
    WIFI_TVHT_MODE_4N,
    WIFI_TVHT_LONG_GI,
    WIFI_TVHT_SHORT_GI,
    WifiTVHTModeConfig,
    WifiTVHTChannelConfig,
    WifiTVHTMCSConfig,
    WifiTVHTPPDUConfig,
    wifi_tvht_channel_plan,
    wifi_tvht_ofdm_profile,
    wifi_tvht_occupied_subcarriers,
    wifi_tvht_pilot_subcarriers,
    wifi_tvht_sig_a_bandwidth_bits,
    wifi_tvht_mcs_profile,
    wifi_tvht_ppdu_geometry,
)


comptime _WARMUPS = 3
comptime _SAMPLES = 9
comptime _TABLE_BATCH = 4096
comptime _TONE_BATCH = 256
comptime _PILOT_BATCH = 512
comptime _SIG_BATCH = 8192
comptime _FIXED_SALT = 0x080211AF


def _mix(checksum: UInt64, value: Int) -> UInt64:
    return (checksum ^ UInt64(value + 4096)) * UInt64(1099511628211)


def _modes() -> List[Int]:
    return [
        WIFI_TVHT_MODE_1,
        WIFI_TVHT_MODE_2C,
        WIFI_TVHT_MODE_2N,
        WIFI_TVHT_MODE_4C,
        WIFI_TVHT_MODE_4N,
    ]


def _build_mode_configs() raises -> List[WifiTVHTModeConfig]:
    var configs = List[WifiTVHTModeConfig](capacity=15)
    for bcu in [6, 7, 8]:
        for mode in _modes():
            configs.append(WifiTVHTModeConfig(bcu, mode))
    return configs^


def _build_channel_configs() raises -> List[WifiTVHTChannelConfig]:
    var configs = List[WifiTVHTChannelConfig](capacity=15)
    for bcu in [6, 7, 8]:
        configs.append(
            WifiTVHTChannelConfig(
                bcu, WIFI_TVHT_MODE_1, 10, 0, 10, 389.0
            )
        )
        configs.append(
            WifiTVHTChannelConfig(
                bcu, WIFI_TVHT_MODE_2C, 10, 0, 11, 389.0
            )
        )
        configs.append(
            WifiTVHTChannelConfig(
                bcu, WIFI_TVHT_MODE_2N, 10, 30, 10, 389.0
            )
        )
        configs.append(
            WifiTVHTChannelConfig(
                bcu, WIFI_TVHT_MODE_4C, 10, 0, 12, 389.0
            )
        )
        configs.append(
            WifiTVHTChannelConfig(
                bcu, WIFI_TVHT_MODE_4N, 10, 30, 11, 389.0
            )
        )
    return configs^


def _build_mcs_configs() raises -> List[WifiTVHTMCSConfig]:
    # 600 mode-expanded configurations exercise 120 normative MCS table rows.
    var configs = List[WifiTVHTMCSConfig](capacity=600)
    for bcu in [6, 7, 8]:
        for mode in _modes():
            for spatial_streams in range(1, 5):
                for mcs_index in range(10):
                    configs.append(
                        WifiTVHTMCSConfig(
                            bcu, mode, mcs_index, spatial_streams
                        )
                    )
    return configs^


def _build_ppdu_configs() raises -> List[WifiTVHTPPDUConfig]:
    var configs = List[WifiTVHTPPDUConfig](capacity=120)
    for bcu in [6, 7, 8]:
        for mode in _modes():
            for space_time_streams in range(1, 5):
                configs.append(
                    WifiTVHTPPDUConfig(
                        bcu,
                        mode,
                        space_time_streams,
                        17 + space_time_streams,
                        WIFI_TVHT_LONG_GI,
                    )
                )
                configs.append(
                    WifiTVHTPPDUConfig(
                        bcu,
                        mode,
                        space_time_streams,
                        17 + space_time_streams,
                        WIFI_TVHT_SHORT_GI,
                    )
                )
    return configs^


@no_inline
def _channel_plan_workload(
    iterations: Int,
    salt: Int,
    configs: Span[WifiTVHTChannelConfig, ...],
) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for operation in range(iterations):
        var index = black_box((operation * 17 + salt) % len(configs))
        var config = configs[index]
        var plan = wifi_tvht_channel_plan(config)
        checksum = _mix(checksum, plan.bcu_bandwidth_mhz)
        checksum = _mix(checksum, plan.mode)
        checksum = _mix(checksum, plan.bcu_count)
        checksum = _mix(checksum, plan.segment_count)
        checksum = _mix(checksum, plan.bcus_per_segment)
        checksum = _mix(checksum, 1 if plan.contiguous else 0)
        checksum = _mix(
            checksum, plan.nominal_aggregate_bandwidth_mhz
        )
        checksum = _mix(
            checksum, Int(2.0 * plan.segment0_center_frequency_mhz)
        )
        checksum = _mix(
            checksum, Int(2.0 * plan.segment1_center_frequency_mhz)
        )
        checksum = _mix(
            checksum,
            Int(2.0 * plan.primary_center_frequency_mhz) + operation,
        )
    return checksum


@no_inline
def _ofdm_profile_workload(
    iterations: Int,
    salt: Int,
    configs: Span[WifiTVHTModeConfig, ...],
) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for operation in range(iterations):
        var index = black_box((operation * 19 + salt) % len(configs))
        var config = configs[index]
        var profile = wifi_tvht_ofdm_profile(config)
        checksum = _mix(checksum, profile.bcu_bandwidth_mhz)
        checksum = _mix(checksum, profile.mode)
        checksum = _mix(checksum, profile.bcu_count)
        checksum = _mix(checksum, profile.segment_count)
        checksum = _mix(checksum, profile.bcus_per_segment)
        checksum = _mix(checksum, profile.dft_size_per_bcu)
        checksum = _mix(checksum, profile.dft_size_per_segment)
        checksum = _mix(checksum, profile.sample_rate_per_segment_hz)
        checksum = _mix(checksum, profile.data_subcarriers)
        checksum = _mix(checksum, profile.pilot_subcarriers)
        checksum = _mix(checksum, profile.occupied_subcarriers)
        checksum = _mix(checksum, profile.dft_period_ns)
        checksum = _mix(checksum, profile.long_guard_interval_ns)
        checksum = _mix(checksum, profile.short_guard_interval_ns)
        checksum = _mix(checksum, profile.long_symbol_duration_ns)
        checksum = _mix(
            checksum, profile.short_symbol_duration_ns + operation
        )
    return checksum


@no_inline
def _occupied_tones_workload(
    iterations: Int,
    salt: Int,
    configs: Span[WifiTVHTModeConfig, ...],
) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for operation in range(iterations):
        var index = black_box((operation * 23 + salt) % len(configs))
        var config = configs[index]
        var segment = (
            (operation + salt) & 1
            if config.mode == WIFI_TVHT_MODE_2N
            or config.mode == WIFI_TVHT_MODE_4N
            else 0
        )
        var tones = wifi_tvht_occupied_subcarriers(config, segment)
        var last = len(tones) - 1
        checksum = _mix(checksum, len(tones) + operation)
        checksum = _mix(checksum, tones[0])
        checksum = _mix(checksum, tones[len(tones) // 2])
        checksum = _mix(checksum, tones[last])
        keep(tones)
    return checksum


@no_inline
def _pilot_tones_workload(
    iterations: Int,
    salt: Int,
    configs: Span[WifiTVHTModeConfig, ...],
) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for operation in range(iterations):
        var index = black_box((operation * 29 + salt) % len(configs))
        var config = configs[index]
        var segment = (
            (operation + salt) & 1
            if config.mode == WIFI_TVHT_MODE_2N
            or config.mode == WIFI_TVHT_MODE_4N
            else 0
        )
        var pilots = wifi_tvht_pilot_subcarriers(config, segment)
        var last = len(pilots) - 1
        checksum = _mix(checksum, len(pilots) + operation)
        checksum = _mix(checksum, pilots[0])
        checksum = _mix(checksum, pilots[len(pilots) // 2])
        checksum = _mix(checksum, pilots[last])
        keep(pilots)
    return checksum


@no_inline
def _sig_a_bandwidth_workload(
    iterations: Int,
    salt: Int,
    configs: Span[WifiTVHTModeConfig, ...],
) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for operation in range(iterations):
        var index = black_box((operation * 31 + salt) % len(configs))
        var config = configs[index]
        var bits = wifi_tvht_sig_a_bandwidth_bits(config)
        checksum = _mix(checksum, bits + operation)
    return checksum


@no_inline
def _mcs_profile_workload(
    iterations: Int,
    salt: Int,
    configs: Span[WifiTVHTMCSConfig, ...],
) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for operation in range(iterations):
        var index = black_box((operation * 37 + salt) % len(configs))
        var config = configs[index]
        var profile = wifi_tvht_mcs_profile(config)
        checksum = _mix(checksum, profile.bcu_bandwidth_mhz)
        checksum = _mix(checksum, profile.mode)
        checksum = _mix(checksum, profile.mcs_index)
        checksum = _mix(checksum, profile.spatial_streams)
        checksum = _mix(checksum, profile.bits_per_subcarrier)
        checksum = _mix(checksum, profile.code_rate_numerator)
        checksum = _mix(checksum, profile.code_rate_denominator)
        checksum = _mix(checksum, profile.data_subcarriers)
        checksum = _mix(checksum, profile.pilot_subcarriers)
        checksum = _mix(checksum, profile.coded_bits_per_symbol)
        checksum = _mix(checksum, profile.data_bits_per_symbol)
        checksum = _mix(checksum, profile.number_of_encoders)
        checksum = _mix(checksum, profile.bcc_interleaver_columns)
        checksum = _mix(checksum, profile.bcc_interleaver_rows)
        checksum = _mix(checksum, profile.bcc_interleaver_rotation)
        checksum = _mix(checksum, profile.ldpc_tone_mapping_distance)
        checksum = _mix(
            checksum,
            (1 if profile.mandatory_base_profile else 0) + operation,
        )
    return checksum


@no_inline
def _ppdu_geometry_workload(
    iterations: Int,
    salt: Int,
    configs: Span[WifiTVHTPPDUConfig, ...],
) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for operation in range(iterations):
        var index = black_box((operation * 41 + salt) % len(configs))
        var config = configs[index]
        var geometry = wifi_tvht_ppdu_geometry(config)
        checksum = _mix(checksum, geometry.bcu_bandwidth_mhz)
        checksum = _mix(checksum, geometry.mode)
        checksum = _mix(checksum, geometry.space_time_streams)
        checksum = _mix(checksum, geometry.tvht_ltf_symbols)
        checksum = _mix(checksum, geometry.data_symbols)
        checksum = _mix(checksum, geometry.guard_interval)
        checksum = _mix(checksum, geometry.l_stf_duration_ns)
        checksum = _mix(checksum, geometry.l_ltf_duration_ns)
        checksum = _mix(checksum, geometry.l_sig_duration_ns)
        checksum = _mix(checksum, geometry.tvht_sig_a_duration_ns)
        checksum = _mix(checksum, geometry.tvht_stf_duration_ns)
        checksum = _mix(checksum, geometry.tvht_ltf_symbol_duration_ns)
        checksum = _mix(checksum, geometry.tvht_ltf_duration_ns)
        checksum = _mix(checksum, geometry.tvht_sig_b_duration_ns)
        checksum = _mix(checksum, geometry.data_symbol_duration_ns)
        checksum = _mix(checksum, geometry.preamble_duration_ns)
        checksum = _mix(checksum, geometry.data_duration_ns)
        checksum = _mix(checksum, geometry.ppdu_duration_ns + operation)
    return checksum


def main() raises:
    # Every mutable input is constructed and validated before any timer.
    var mode_configs = _build_mode_configs()
    var channel_configs = _build_channel_configs()
    var mcs_configs = _build_mcs_configs()
    var ppdu_configs = _build_ppdu_configs()
    var mode_configs_span = Span(mode_configs)
    var channel_configs_span = Span(channel_configs)
    var mcs_configs_span = Span(mcs_configs)
    var ppdu_configs_span = Span(ppdu_configs)

    for warmup in range(_WARMUPS):
        var salt = _FIXED_SALT + warmup * 131
        keep(
            _channel_plan_workload(
                _TABLE_BATCH, salt, channel_configs_span
            )
        )
        keep(
            _ofdm_profile_workload(
                _TABLE_BATCH, salt, mode_configs_span
            )
        )
        keep(
            _occupied_tones_workload(
                _TONE_BATCH, salt, mode_configs_span
            )
        )
        keep(
            _pilot_tones_workload(
                _PILOT_BATCH, salt, mode_configs_span
            )
        )
        keep(
            _sig_a_bandwidth_workload(
                _SIG_BATCH, salt, mode_configs_span
            )
        )
        keep(
            _mcs_profile_workload(
                _TABLE_BATCH, salt, mcs_configs_span
            )
        )
        keep(
            _ppdu_geometry_workload(
                _TABLE_BATCH, salt, ppdu_configs_span
            )
        )

    var channel_samples = List[UInt64](capacity=_SAMPLES)
    var ofdm_samples = List[UInt64](capacity=_SAMPLES)
    var occupied_samples = List[UInt64](capacity=_SAMPLES)
    var pilot_samples = List[UInt64](capacity=_SAMPLES)
    var sig_samples = List[UInt64](capacity=_SAMPLES)
    var mcs_samples = List[UInt64](capacity=_SAMPLES)
    var ppdu_samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for sample in range(_SAMPLES):
        var salt = _FIXED_SALT + sample * 257

        var start = global_perf_counter_ns()
        var channel_checksum = _channel_plan_workload(
            _TABLE_BATCH, salt, channel_configs_span
        )
        channel_samples.append(global_perf_counter_ns() - start)
        checksum = _mix(
            checksum, Int(channel_checksum & UInt64(Int.MAX))
        )
        keep(channel_checksum)

        start = global_perf_counter_ns()
        var ofdm_checksum = _ofdm_profile_workload(
            _TABLE_BATCH, salt, mode_configs_span
        )
        ofdm_samples.append(global_perf_counter_ns() - start)
        checksum = _mix(checksum, Int(ofdm_checksum & UInt64(Int.MAX)))
        keep(ofdm_checksum)

        start = global_perf_counter_ns()
        var occupied_checksum = _occupied_tones_workload(
            _TONE_BATCH, salt, mode_configs_span
        )
        occupied_samples.append(global_perf_counter_ns() - start)
        checksum = _mix(
            checksum, Int(occupied_checksum & UInt64(Int.MAX))
        )
        keep(occupied_checksum)

        start = global_perf_counter_ns()
        var pilot_checksum = _pilot_tones_workload(
            _PILOT_BATCH, salt, mode_configs_span
        )
        pilot_samples.append(global_perf_counter_ns() - start)
        checksum = _mix(checksum, Int(pilot_checksum & UInt64(Int.MAX)))
        keep(pilot_checksum)

        start = global_perf_counter_ns()
        var sig_checksum = _sig_a_bandwidth_workload(
            _SIG_BATCH, salt, mode_configs_span
        )
        sig_samples.append(global_perf_counter_ns() - start)
        checksum = _mix(checksum, Int(sig_checksum & UInt64(Int.MAX)))
        keep(sig_checksum)

        start = global_perf_counter_ns()
        var mcs_checksum = _mcs_profile_workload(
            _TABLE_BATCH, salt, mcs_configs_span
        )
        mcs_samples.append(global_perf_counter_ns() - start)
        checksum = _mix(checksum, Int(mcs_checksum & UInt64(Int.MAX)))
        keep(mcs_checksum)

        start = global_perf_counter_ns()
        var ppdu_checksum = _ppdu_geometry_workload(
            _TABLE_BATCH, salt, ppdu_configs_span
        )
        ppdu_samples.append(global_perf_counter_ns() - start)
        checksum = _mix(checksum, Int(ppdu_checksum & UInt64(Int.MAX)))
        keep(ppdu_checksum)

    print_benchmark_metadata()
    print("wifi_tvht_backend:", "scalar-cpu-reference")
    print(
        "wifi_tvht_baseline:",
        "IEEE-802.11-2024-Clause-22-bounded",
    )
    report_timing_samples(
        "wifi_tvht_channel_plan",
        channel_samples,
        _WARMUPS,
        _TABLE_BATCH,
        "channel_plan",
    )
    report_timing_samples(
        "wifi_tvht_ofdm_profile",
        ofdm_samples,
        _WARMUPS,
        _TABLE_BATCH,
        "profile",
    )
    report_timing_samples(
        "wifi_tvht_occupied_subcarriers",
        occupied_samples,
        _WARMUPS,
        _TONE_BATCH,
        "tone_row",
    )
    report_timing_samples(
        "wifi_tvht_pilot_subcarriers",
        pilot_samples,
        _WARMUPS,
        _PILOT_BATCH,
        "pilot_row",
    )
    report_timing_samples(
        "wifi_tvht_sig_a_bandwidth_bits",
        sig_samples,
        _WARMUPS,
        _SIG_BATCH,
        "lookup",
    )
    report_timing_samples(
        "wifi_tvht_mcs_profile",
        mcs_samples,
        _WARMUPS,
        _TABLE_BATCH,
        "profile",
    )
    report_timing_samples(
        "wifi_tvht_ppdu_geometry",
        ppdu_samples,
        _WARMUPS,
        _TABLE_BATCH,
        "geometry",
    )
    keep(checksum)
    print("wifi_tvht_retained_checksum:", checksum)
