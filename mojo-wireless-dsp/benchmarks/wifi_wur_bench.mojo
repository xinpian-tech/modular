"""Attributable CPU timings for the bounded adopted WUR reference slice.

Each public algorithm has a separate no-inline workload, three untimed
warmups, and nine independent samples.  Fixed per-sample salt changes valid
lookup and randomizer rows reproducibly.  Complete owned results are retained
and O(1) endpoint fingerprints drive the checksum, so no second output-length
scan contaminates the attributed timings.  No dispatcher or bundle is timed.
Waveform timings describe the adopted Clause-30 reference/example, not a
uniquely mandatory transmitter implementation.
"""

from std.benchmark import black_box, keep
from std.collections import Span
from std.time import global_perf_counter_ns
from wireless_dsp.benchmarking import (
    print_benchmark_metadata,
    report_timing_samples,
)
from wireless_dsp.core import Complex64
from wireless_dsp.wireless.wifi.wur import (
    WIFI_WUR_DATA_RATE_LDR_BPS,
    WIFI_WUR_DATA_RATE_HDR_BPS,
    WIFI_WUR_SAMPLE_RATE_HZ,
    WIFI_WUR_IDFT_SIZE,
    WifiWURDataOOKConfig,
    wifi_wur_data_profile,
    wifi_wur_mc_ook_active_subcarriers,
    wifi_wur_symbol_randomizer_state,
    wifi_wur_symbol_randomizer_cyclic_shift_ns,
    wifi_wur_data_mc_ook_on_symbol,
    wifi_wur_data_mc_ook_off_symbol,
    wifi_wur_data_mc_ook_modulate,
)


comptime _WARMUPS = 3
comptime _SAMPLES = 9
comptime _TABLE_BATCH = 4096
comptime _TONE_BATCH = 256
comptime _WAVEFORM_BATCH = 64
comptime _MODULATE_BATCH = 16
comptime _MODULATE_SYMBOLS = 15
comptime _FIXED_SALT = 0x080211BA


def _mix(checksum: UInt64, value: Int) -> UInt64:
    return (checksum ^ UInt64(value + 4096)) * UInt64(1099511628211)


def _config(data_rate_bps: Int) raises -> WifiWURDataOOKConfig:
    return WifiWURDataOOKConfig(
        data_rate_bps,
        WIFI_WUR_SAMPLE_RATE_HZ,
        WIFI_WUR_IDFT_SIZE,
        1,
    )


def _mix_complex(
    checksum: UInt64, value: Complex64, sample_index: Int
) -> UInt64:
    var result = _mix(
        checksum, Int((value.re + 8.0) * 1_000_000_000.0) + sample_index
    )
    return _mix(
        result, Int((value.im + 8.0) * 1_000_000_000.0) + sample_index
    )


@no_inline
def _profile_workload(
    iterations: Int,
    salt: Int,
    ldr_config: WifiWURDataOOKConfig,
    hdr_config: WifiWURDataOOKConfig,
) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for operation in range(iterations):
        var config = (
            ldr_config
            if ((operation + salt) & 1) == 0
            else hdr_config
        )
        var profile = wifi_wur_data_profile(config)
        checksum = _mix(checksum, profile.data_rate_bps)
        checksum = _mix(checksum, profile.data_symbol_duration_ns)
        checksum = _mix(checksum, profile.useful_samples)
        checksum = _mix(checksum, profile.guard_interval_samples)
        checksum = _mix(checksum, profile.total_symbol_samples)
        checksum = _mix(checksum, profile.active_subcarriers)
        checksum = _mix(checksum, profile.sync_duration_ns)
        checksum = _mix(
            checksum, profile.sync_randomizer_symbols + operation
        )
    return checksum


@no_inline
def _active_tones_workload(
    iterations: Int, config: WifiWURDataOOKConfig
) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for operation in range(iterations):
        var tones = wifi_wur_mc_ook_active_subcarriers(config)
        var last = len(tones) - 1
        checksum = _mix(checksum, len(tones) + operation)
        checksum = _mix(checksum, tones[0])
        checksum = _mix(checksum, tones[len(tones) // 2])
        checksum = _mix(checksum, tones[last])
        keep(tones)
    return checksum


@no_inline
def _randomizer_state_workload(
    iterations: Int, salt: Int
) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for operation in range(iterations):
        var index = black_box((operation * 37 + salt) & Int.MAX)
        var state = wifi_wur_symbol_randomizer_state(index)
        checksum = _mix(checksum, state.lfsr_x7_to_x1)
        checksum = _mix(checksum, state.phase_sign)
        checksum = _mix(
            checksum, state.cyclic_shift_index + operation
        )
    return checksum


@no_inline
def _cyclic_shift_workload(
    iterations: Int,
    salt: Int,
    ldr_config: WifiWURDataOOKConfig,
    hdr_config: WifiWURDataOOKConfig,
) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for operation in range(iterations):
        var config = (
            ldr_config
            if ((operation + salt) & 1) == 0
            else hdr_config
        )
        var shift = wifi_wur_symbol_randomizer_cyclic_shift_ns(
            config,
            black_box((operation * 53 + salt) & Int.MAX),
        )
        checksum = _mix(checksum, shift + 4_000 + operation)
    return checksum


@no_inline
def _on_symbol_workload(
    iterations: Int,
    salt: Int,
    config: WifiWURDataOOKConfig,
    coefficients: Span[Complex64, ...],
) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for operation in range(iterations):
        var waveform = wifi_wur_data_mc_ook_on_symbol(
            config,
            coefficients,
            black_box((operation * 29 + salt) & Int.MAX),
        )
        var last = len(waveform) - 1
        checksum = _mix(checksum, len(waveform) + operation)
        checksum = _mix_complex(checksum, waveform[0], operation)
        checksum = _mix_complex(
            checksum, waveform[len(waveform) // 2], operation
        )
        checksum = _mix_complex(checksum, waveform[last], operation)
        keep(waveform)
    return checksum


@no_inline
def _off_symbol_workload(
    iterations: Int, config: WifiWURDataOOKConfig
) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for operation in range(iterations):
        var waveform = wifi_wur_data_mc_ook_off_symbol(config)
        var last = len(waveform) - 1
        checksum = _mix(checksum, len(waveform) + operation)
        checksum = _mix_complex(checksum, waveform[0], operation)
        checksum = _mix_complex(
            checksum, waveform[len(waveform) // 2], operation
        )
        checksum = _mix_complex(checksum, waveform[last], operation)
        keep(waveform)
    return checksum


@no_inline
def _modulate_workload(
    iterations: Int,
    config: WifiWURDataOOKConfig,
    decisions: Span[UInt8, ...],
    coefficients: Span[Complex64, ...],
) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for operation in range(iterations):
        var waveform = wifi_wur_data_mc_ook_modulate(
            config, decisions, coefficients
        )
        var last = len(waveform) - 1
        checksum = _mix(checksum, len(waveform) + operation)
        checksum = _mix_complex(checksum, waveform[0], operation)
        checksum = _mix_complex(
            checksum, waveform[len(waveform) // 2], operation
        )
        checksum = _mix_complex(checksum, waveform[last], operation)
        keep(waveform)
    return checksum


def main() raises:
    var ldr_config = _config(WIFI_WUR_DATA_RATE_LDR_BPS)
    var hdr_config = _config(WIFI_WUR_DATA_RATE_HDR_BPS)
    var coefficients = List[Complex64](capacity=12)
    for index in range(12):
        coefficients.append(
            Complex64(1.0 if index % 3 != 1 else -1.0, 0.0)
        )
    var decisions = List[UInt8](capacity=_MODULATE_SYMBOLS)
    for index in range(_MODULATE_SYMBOLS):
        decisions.append(UInt8(0 if index % 3 == 0 else 1))
    var coefficients_span = Span(coefficients)
    var decisions_span = Span(decisions)

    for warmup in range(_WARMUPS):
        var salt = _FIXED_SALT + warmup * 131
        keep(
            _profile_workload(
                _TABLE_BATCH, salt, ldr_config, hdr_config
            )
        )
        keep(_active_tones_workload(_TONE_BATCH, ldr_config))
        keep(_randomizer_state_workload(_TABLE_BATCH, salt))
        keep(
            _cyclic_shift_workload(
                _TABLE_BATCH, salt, ldr_config, hdr_config
            )
        )
        keep(
            _on_symbol_workload(
                _WAVEFORM_BATCH,
                salt,
                ldr_config,
                coefficients_span,
            )
        )
        keep(_off_symbol_workload(_WAVEFORM_BATCH, ldr_config))
        keep(
            _modulate_workload(
                _MODULATE_BATCH,
                ldr_config,
                decisions_span,
                coefficients_span,
            )
        )

    var profile_samples = List[UInt64](capacity=_SAMPLES)
    var tones_samples = List[UInt64](capacity=_SAMPLES)
    var state_samples = List[UInt64](capacity=_SAMPLES)
    var shift_samples = List[UInt64](capacity=_SAMPLES)
    var on_samples = List[UInt64](capacity=_SAMPLES)
    var off_samples = List[UInt64](capacity=_SAMPLES)
    var modulate_samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for sample in range(_SAMPLES):
        var salt = _FIXED_SALT + sample * 257

        var start = global_perf_counter_ns()
        var profile_checksum = _profile_workload(
            _TABLE_BATCH, salt, ldr_config, hdr_config
        )
        profile_samples.append(global_perf_counter_ns() - start)
        checksum = _mix(
            checksum, Int(profile_checksum & UInt64(Int.MAX))
        )
        keep(profile_checksum)

        start = global_perf_counter_ns()
        var tones_checksum = _active_tones_workload(
            _TONE_BATCH, ldr_config
        )
        tones_samples.append(global_perf_counter_ns() - start)
        checksum = _mix(checksum, Int(tones_checksum & UInt64(Int.MAX)))
        keep(tones_checksum)

        start = global_perf_counter_ns()
        var state_checksum = _randomizer_state_workload(
            _TABLE_BATCH, salt
        )
        state_samples.append(global_perf_counter_ns() - start)
        checksum = _mix(checksum, Int(state_checksum & UInt64(Int.MAX)))
        keep(state_checksum)

        start = global_perf_counter_ns()
        var shift_checksum = _cyclic_shift_workload(
            _TABLE_BATCH, salt, ldr_config, hdr_config
        )
        shift_samples.append(global_perf_counter_ns() - start)
        checksum = _mix(checksum, Int(shift_checksum & UInt64(Int.MAX)))
        keep(shift_checksum)

        start = global_perf_counter_ns()
        var on_checksum = _on_symbol_workload(
            _WAVEFORM_BATCH,
            salt,
            ldr_config,
            coefficients_span,
        )
        on_samples.append(global_perf_counter_ns() - start)
        checksum = _mix(checksum, Int(on_checksum & UInt64(Int.MAX)))
        keep(on_checksum)

        start = global_perf_counter_ns()
        var off_checksum = _off_symbol_workload(
            _WAVEFORM_BATCH, ldr_config
        )
        off_samples.append(global_perf_counter_ns() - start)
        checksum = _mix(checksum, Int(off_checksum & UInt64(Int.MAX)))
        keep(off_checksum)

        start = global_perf_counter_ns()
        var modulate_checksum = _modulate_workload(
            _MODULATE_BATCH,
            ldr_config,
            decisions_span,
            coefficients_span,
        )
        modulate_samples.append(global_perf_counter_ns() - start)
        checksum = _mix(
            checksum, Int(modulate_checksum & UInt64(Int.MAX))
        )
        keep(modulate_checksum)

    print_benchmark_metadata()
    print("wifi_wur_backend:", "scalar-cpu-adopted-reference")
    print(
        "wifi_wur_baseline:",
        "IEEE-802.11-2024-Clause-30-bounded-reference-example",
    )
    report_timing_samples(
        "wifi_wur_data_profile",
        profile_samples,
        _WARMUPS,
        _TABLE_BATCH,
        "profile",
    )
    report_timing_samples(
        "wifi_wur_mc_ook_active_subcarriers",
        tones_samples,
        _WARMUPS,
        _TONE_BATCH * 12,
        "active_tone",
    )
    report_timing_samples(
        "wifi_wur_symbol_randomizer_state",
        state_samples,
        _WARMUPS,
        _TABLE_BATCH,
        "state",
    )
    report_timing_samples(
        "wifi_wur_symbol_randomizer_cyclic_shift_ns",
        shift_samples,
        _WARMUPS,
        _TABLE_BATCH,
        "shift_lookup",
    )
    report_timing_samples(
        "wifi_wur_data_mc_ook_on_symbol",
        on_samples,
        _WARMUPS,
        _WAVEFORM_BATCH * 80,
        "generated_sample",
    )
    report_timing_samples(
        "wifi_wur_data_mc_ook_off_symbol",
        off_samples,
        _WARMUPS,
        _WAVEFORM_BATCH * 80,
        "generated_sample",
    )
    report_timing_samples(
        "wifi_wur_data_mc_ook_modulate",
        modulate_samples,
        _WARMUPS,
        _MODULATE_BATCH * _MODULATE_SYMBOLS * 80,
        "generated_sample",
    )
    keep(checksum)
    print("wifi_wur_retained_checksum:", checksum)
