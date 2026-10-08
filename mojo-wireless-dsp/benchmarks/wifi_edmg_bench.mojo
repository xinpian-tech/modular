"""Attributable CPU timings for bounded Clause-28 EDMG OFDM APIs.

Every public algorithm has a distinct no-inline workload, three untimed
warmups, and nine odd timing samples.  All legal configurations and all grid
inputs are constructed before timing.  Fixed selection salts and O(1)
endpoint fingerprints retain owned results in a deterministic checksum.
"""

from std.benchmark import black_box, keep
from std.collections import Span
from std.time import global_perf_counter_ns
from wireless_dsp.benchmarking import (
    print_benchmark_metadata,
    report_timing_samples,
)
from wireless_dsp.core import Complex64
from wireless_dsp.wireless.wifi.edmg import (
    WifiEDMGOfdmConfig,
    wifi_edmg_ofdm_channel_numbers,
    wifi_edmg_ofdm_profile,
    wifi_edmg_ofdm_channel_center_frequency_hz,
    wifi_edmg_ofdm_symbol_samples,
    wifi_edmg_ofdm_pack_occupied_grid,
    wifi_edmg_ofdm_unpack_occupied_grid,
)


comptime _WARMUPS = 3
comptime _SAMPLES = 9
comptime _TABLE_BATCH = 4096
comptime _CHANNEL_LIST_BATCH = 2048
comptime _SYMBOL_BATCH = 8192
comptime _GRID_BATCH = 128
comptime _FIXED_SALT = 0x11A72024


def _mix(checksum: UInt64, value: Int) -> UInt64:
    return (checksum ^ UInt64(value + 32768)) * UInt64(1099511628211)


def _mix_complex(checksum: UInt64, value: Complex64) -> UInt64:
    var result = _mix(checksum, Int(value.re))
    return _mix(result, Int(value.im))


def _first_channel(ncb: Int) -> Int:
    return [1, 9, 17, 25][ncb - 1]


def _last_channel(ncb: Int) -> Int:
    return [8, 15, 22, 29][ncb - 1]


def _half_occupied(ncb: Int) -> Int:
    return [177, 386, 596, 805][ncb - 1]


def _build_all_configs() raises -> List[WifiEDMGOfdmConfig]:
    var configs = List[WifiEDMGOfdmConfig](capacity=26)
    for ncb in range(1, 5):
        for channel in range(_first_channel(ncb), _last_channel(ncb) + 1):
            configs.append(WifiEDMGOfdmConfig(ncb, channel))
    return configs^


def _build_grid_configs() raises -> List[WifiEDMGOfdmConfig]:
    return [
        WifiEDMGOfdmConfig(1, 1),
        WifiEDMGOfdmConfig(2, 9),
        WifiEDMGOfdmConfig(3, 17),
        WifiEDMGOfdmConfig(4, 25),
    ]


def _build_occupied(ncb: Int) -> List[Complex64]:
    var half = _half_occupied(ncb)
    var result = List[Complex64](capacity=2 * half + 1)
    for tone in range(-half, half + 1):
        if tone >= -1 and tone <= 1:
            result.append(Complex64(0.0, 0.0))
        else:
            result.append(
                Complex64(Float64(tone), Float64((tone + 4096) % 23 - 11))
            )
    return result^


@no_inline
def _channel_numbers_workload(iterations: Int, salt: Int) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for operation in range(iterations):
        var ncb = 1 + black_box((operation * 17 + salt) % 4)
        var channels = wifi_edmg_ofdm_channel_numbers(ncb)
        checksum = _mix(checksum, ncb)
        checksum = _mix(checksum, len(channels))
        checksum = _mix(checksum, channels[0])
        checksum = _mix(
            checksum, channels[len(channels) - 1] + operation
        )
        keep(channels)
    return checksum


@no_inline
def _profile_workload(
    iterations: Int,
    salt: Int,
    configs: Span[WifiEDMGOfdmConfig, ...],
) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for operation in range(iterations):
        var index = black_box((operation * 19 + salt) % len(configs))
        var config = configs[index]
        var profile = wifi_edmg_ofdm_profile(config)
        checksum = _mix(checksum, profile.contiguous_channel_count)
        checksum = _mix(checksum, profile.data_subcarriers)
        checksum = _mix(checksum, profile.pilot_subcarriers)
        checksum = _mix(checksum, profile.dc_subcarriers)
        checksum = _mix(checksum, profile.total_subcarriers)
        checksum = _mix(checksum, profile.half_occupied_subcarriers)
        checksum = _mix(checksum, profile.sample_rate_hz)
        checksum = _mix(checksum, profile.dft_size)
        checksum = _mix(
            checksum, profile.subcarrier_spacing_hz + operation
        )
    return checksum


@no_inline
def _center_frequency_workload(
    iterations: Int,
    salt: Int,
    configs: Span[WifiEDMGOfdmConfig, ...],
) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for operation in range(iterations):
        var index = black_box((operation * 23 + salt) % len(configs))
        var config = configs[index]
        var frequency = wifi_edmg_ofdm_channel_center_frequency_hz(
            config
        )
        checksum = _mix(checksum, frequency + operation)
    return checksum


@no_inline
def _symbol_samples_workload(
    iterations: Int,
    salt: Int,
    configs: Span[WifiEDMGOfdmConfig, ...],
) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for operation in range(iterations):
        var selector = operation * 29 + salt
        var index = black_box(selector % len(configs))
        var guard = black_box((selector // len(configs)) % 3)
        var config = configs[index]
        var samples = wifi_edmg_ofdm_symbol_samples(config, guard)
        checksum = _mix(checksum, samples + guard + operation)
    return checksum


@no_inline
def _pack_workload(
    iterations: Int,
    salt: Int,
    configs: Span[WifiEDMGOfdmConfig, ...],
    occupied1: Span[Complex64, ...],
    occupied2: Span[Complex64, ...],
    occupied3: Span[Complex64, ...],
    occupied4: Span[Complex64, ...],
) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for operation in range(iterations):
        var index = black_box((operation * 31 + salt) % 4)
        var config = configs[index]
        var bins: List[Complex64]
        if index == 0:
            bins = wifi_edmg_ofdm_pack_occupied_grid(
                config, black_box(occupied1)
            )
        elif index == 1:
            bins = wifi_edmg_ofdm_pack_occupied_grid(
                config, black_box(occupied2)
            )
        elif index == 2:
            bins = wifi_edmg_ofdm_pack_occupied_grid(
                config, black_box(occupied3)
            )
        else:
            bins = wifi_edmg_ofdm_pack_occupied_grid(
                config, black_box(occupied4)
            )
        checksum = _mix(checksum, len(bins) + operation)
        checksum = _mix_complex(checksum, bins[2])
        checksum = _mix_complex(checksum, bins[len(bins) - 2])
        keep(bins)
    return checksum


@no_inline
def _unpack_workload(
    iterations: Int,
    salt: Int,
    configs: Span[WifiEDMGOfdmConfig, ...],
    bins1: Span[Complex64, ...],
    bins2: Span[Complex64, ...],
    bins3: Span[Complex64, ...],
    bins4: Span[Complex64, ...],
) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for operation in range(iterations):
        var index = black_box((operation * 37 + salt) % 4)
        var config = configs[index]
        var occupied: List[Complex64]
        if index == 0:
            occupied = wifi_edmg_ofdm_unpack_occupied_grid(
                config, black_box(bins1)
            )
        elif index == 1:
            occupied = wifi_edmg_ofdm_unpack_occupied_grid(
                config, black_box(bins2)
            )
        elif index == 2:
            occupied = wifi_edmg_ofdm_unpack_occupied_grid(
                config, black_box(bins3)
            )
        else:
            occupied = wifi_edmg_ofdm_unpack_occupied_grid(
                config, black_box(bins4)
            )
        checksum = _mix(checksum, len(occupied) + operation)
        checksum = _mix_complex(checksum, occupied[0])
        checksum = _mix_complex(checksum, occupied[len(occupied) - 1])
        keep(occupied)
    return checksum


def main() raises:
    var all_configs = _build_all_configs()
    var grid_configs = _build_grid_configs()
    var occupied1 = _build_occupied(1)
    var occupied2 = _build_occupied(2)
    var occupied3 = _build_occupied(3)
    var occupied4 = _build_occupied(4)
    var bins1 = wifi_edmg_ofdm_pack_occupied_grid(
        grid_configs[0], Span(occupied1)
    )
    var bins2 = wifi_edmg_ofdm_pack_occupied_grid(
        grid_configs[1], Span(occupied2)
    )
    var bins3 = wifi_edmg_ofdm_pack_occupied_grid(
        grid_configs[2], Span(occupied3)
    )
    var bins4 = wifi_edmg_ofdm_pack_occupied_grid(
        grid_configs[3], Span(occupied4)
    )
    var all_configs_span = Span(all_configs)
    var grid_configs_span = Span(grid_configs)
    var occupied1_span = Span(occupied1)
    var occupied2_span = Span(occupied2)
    var occupied3_span = Span(occupied3)
    var occupied4_span = Span(occupied4)
    var bins1_span = Span(bins1)
    var bins2_span = Span(bins2)
    var bins3_span = Span(bins3)
    var bins4_span = Span(bins4)

    for _ in range(_WARMUPS):
        var salt = _FIXED_SALT
        keep(_channel_numbers_workload(_CHANNEL_LIST_BATCH, salt))
        keep(_profile_workload(_TABLE_BATCH, salt, all_configs_span))
        keep(
            _center_frequency_workload(
                _TABLE_BATCH, salt, all_configs_span
            )
        )
        keep(
            _symbol_samples_workload(
                _SYMBOL_BATCH, salt, all_configs_span
            )
        )
        keep(
            _pack_workload(
                _GRID_BATCH,
                salt,
                grid_configs_span,
                occupied1_span,
                occupied2_span,
                occupied3_span,
                occupied4_span,
            )
        )
        keep(
            _unpack_workload(
                _GRID_BATCH,
                salt,
                grid_configs_span,
                bins1_span,
                bins2_span,
                bins3_span,
                bins4_span,
            )
        )

    var channel_samples = List[UInt64](capacity=_SAMPLES)
    var profile_samples = List[UInt64](capacity=_SAMPLES)
    var center_samples = List[UInt64](capacity=_SAMPLES)
    var symbol_samples = List[UInt64](capacity=_SAMPLES)
    var pack_samples = List[UInt64](capacity=_SAMPLES)
    var unpack_samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for sample in range(_SAMPLES):
        var salt = _FIXED_SALT + sample * 257

        var start = global_perf_counter_ns()
        var channel_checksum = _channel_numbers_workload(
            _CHANNEL_LIST_BATCH, salt
        )
        channel_samples.append(global_perf_counter_ns() - start)
        checksum = _mix(
            checksum, Int(channel_checksum & UInt64(Int.MAX))
        )
        keep(channel_checksum)

        start = global_perf_counter_ns()
        var profile_checksum = _profile_workload(
            _TABLE_BATCH, salt, all_configs_span
        )
        profile_samples.append(global_perf_counter_ns() - start)
        checksum = _mix(
            checksum, Int(profile_checksum & UInt64(Int.MAX))
        )
        keep(profile_checksum)

        start = global_perf_counter_ns()
        var center_checksum = _center_frequency_workload(
            _TABLE_BATCH, salt, all_configs_span
        )
        center_samples.append(global_perf_counter_ns() - start)
        checksum = _mix(checksum, Int(center_checksum & UInt64(Int.MAX)))
        keep(center_checksum)

        start = global_perf_counter_ns()
        var symbol_checksum = _symbol_samples_workload(
            _SYMBOL_BATCH, salt, all_configs_span
        )
        symbol_samples.append(global_perf_counter_ns() - start)
        checksum = _mix(checksum, Int(symbol_checksum & UInt64(Int.MAX)))
        keep(symbol_checksum)

        start = global_perf_counter_ns()
        var pack_checksum = _pack_workload(
            _GRID_BATCH,
            salt,
            grid_configs_span,
            occupied1_span,
            occupied2_span,
            occupied3_span,
            occupied4_span,
        )
        pack_samples.append(global_perf_counter_ns() - start)
        checksum = _mix(checksum, Int(pack_checksum & UInt64(Int.MAX)))
        keep(pack_checksum)

        start = global_perf_counter_ns()
        var unpack_checksum = _unpack_workload(
            _GRID_BATCH,
            salt,
            grid_configs_span,
            bins1_span,
            bins2_span,
            bins3_span,
            bins4_span,
        )
        unpack_samples.append(global_perf_counter_ns() - start)
        checksum = _mix(
            checksum, Int(unpack_checksum & UInt64(Int.MAX))
        )
        keep(unpack_checksum)

    print_benchmark_metadata()
    print("wifi_edmg_backend:", "scalar-cpu-reference")
    print(
        "wifi_edmg_baseline:",
        "IEEE-802.11-2024-Clause-28-OFDM-bounded",
    )
    report_timing_samples(
        "wifi_edmg_ofdm_channel_numbers",
        channel_samples,
        _WARMUPS,
        _CHANNEL_LIST_BATCH,
        "channel_row",
    )
    report_timing_samples(
        "wifi_edmg_ofdm_profile",
        profile_samples,
        _WARMUPS,
        _TABLE_BATCH,
        "profile",
    )
    report_timing_samples(
        "wifi_edmg_ofdm_channel_center_frequency_hz",
        center_samples,
        _WARMUPS,
        _TABLE_BATCH,
        "lookup",
    )
    report_timing_samples(
        "wifi_edmg_ofdm_symbol_samples",
        symbol_samples,
        _WARMUPS,
        _SYMBOL_BATCH,
        "geometry",
    )
    report_timing_samples(
        "wifi_edmg_ofdm_pack_occupied_grid",
        pack_samples,
        _WARMUPS,
        _GRID_BATCH,
        "grid",
    )
    report_timing_samples(
        "wifi_edmg_ofdm_unpack_occupied_grid",
        unpack_samples,
        _WARMUPS,
        _GRID_BATCH,
        "grid",
    )
    keep(checksum)
    print("wifi_edmg_retained_checksum:", checksum)
