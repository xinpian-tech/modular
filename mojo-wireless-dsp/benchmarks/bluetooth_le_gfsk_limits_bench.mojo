"""Strict per-API benchmark for Core 6.3 LE GFSK parameter limits.

Each public API has one unique ``@no_inline`` workload and timer pair.  The
canonical profiles, supported-PHY flags, scalar observations, and borrowed
Span are constructed before preflight, warmup, or timing.  Complete scalar
results are kept after the timer and summarized by O(1) fingerprints.  Every
workload has two determinism preflights, three warmups, and nine samples.
"""

from std.benchmark import black_box, keep
from std.collections import Span
from std.time import global_perf_counter_ns
from wireless_dsp.benchmarking import (
    print_benchmark_metadata,
    report_timing_samples,
)
from wireless_dsp.wireless.bluetooth.gfsk import (
    BLUETOOTH_LE_GFSK_PHY_1M,
    BLUETOOTH_LE_GFSK_PHY_2M,
    BluetoothLEGFSKLimits,
    bluetooth_le_gfsk_limits,
    bluetooth_le_gfsk_modulation_index_is_compliant,
    bluetooth_le_gfsk_frequency_deviation_is_compliant,
    bluetooth_le_gfsk_timing_is_compliant,
    bluetooth_le_gfsk_bit_deviation_sign_is_compliant,
    bluetooth_le_gfsk_stable_claim_is_compliant,
)


comptime _WARMUPS = 3
comptime _SAMPLES = 9
comptime _BATCH = 4096
comptime _SEED = UInt64(1469598103934665603)


def _mix(checksum: UInt64, value: UInt64) -> UInt64:
    return (checksum ^ value) * UInt64(1099511628211)


def _require_repeat(first: UInt64, second: UInt64) raises -> UInt64:
    var first_checksum = _mix(_SEED, first)
    var second_checksum = _mix(_SEED, second)
    if first_checksum != second_checksum:
        raise Error("Bluetooth LE GFSK limits benchmark is nondeterministic")
    keep(first_checksum)
    keep(second_checksum)
    return first_checksum


def _profile_fingerprint(profile: BluetoothLEGFSKLimits) -> UInt64:
    var result = _mix(_SEED, UInt64(profile.phy))
    result = _mix(
        result, UInt64(1 if profile.support_is_mandatory else 0)
    )
    result = _mix(result, UInt64(profile.symbol_rate_symbols_per_second))
    result = _mix(result, UInt64(profile.uncoded_bit_rate_bits_per_second))
    result = _mix(result, UInt64(profile.bits_per_symbol))
    result = _mix(
        result,
        UInt64(Int(profile.bandwidth_bit_period_product * 1_000_000.0)),
    )
    result = _mix(
        result, UInt64(Int(profile.modulation_index_minimum * 1_000_000.0))
    )
    result = _mix(
        result, UInt64(Int(profile.modulation_index_maximum * 1_000_000.0))
    )
    result = _mix(
        result,
        UInt64(Int(
            profile.stable_modulation_index_minimum * 1_000_000.0
        )),
    )
    result = _mix(
        result,
        UInt64(Int(
            profile.stable_modulation_index_maximum * 1_000_000.0
        )),
    )
    result = _mix(result, UInt64(profile.minimum_frequency_deviation_hz))
    result = _mix(
        result,
        UInt64(Int(profile.minimum_frequency_deviation_ratio * 1_000_000.0)),
    )
    result = _mix(
        result,
        UInt64(Int(
            profile.maximum_absolute_symbol_timing_error_ppm * 1_000_000.0
        )),
    )
    result = _mix(
        result,
        UInt64(Int(
            profile.maximum_absolute_zero_crossing_error_symbol_periods
            * 1_000_000.0
        )),
    )
    result = _mix(
        result,
        UInt64(
            1 if profile.binary_one_uses_positive_frequency_deviation else 0
        ),
    )
    result = _mix(
        result,
        UInt64(
            1 if profile.binary_zero_uses_negative_frequency_deviation else 0
        ),
    )
    return _mix(
        result,
        UInt64(
            1
            if profile.stable_claim_requires_all_supported_le_transmitter_phys
            else 0
        ),
    )


@no_inline
def _bluetooth_le_gfsk_limits_workload(
    phy: Int, iterations: Int
) raises -> Tuple[UInt64, UInt64]:
    var result = bluetooth_le_gfsk_limits(phy)
    var start = global_perf_counter_ns()
    for _ in range(iterations):
        result = bluetooth_le_gfsk_limits(black_box(phy))
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, _profile_fingerprint(result))


@no_inline
def _bluetooth_le_gfsk_modulation_index_is_compliant_workload(
    profile: BluetoothLEGFSKLimits,
    modulation_index: Float64,
    claims_stable_index: Bool,
    iterations: Int,
) raises -> Tuple[UInt64, UInt64]:
    var result = bluetooth_le_gfsk_modulation_index_is_compliant(
        profile,
        modulation_index,
        claims_stable_index=claims_stable_index,
    )
    var start = global_perf_counter_ns()
    for _ in range(iterations):
        result = bluetooth_le_gfsk_modulation_index_is_compliant(
            black_box(profile),
            black_box(modulation_index),
            claims_stable_index=black_box(claims_stable_index),
        )
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, _mix(_SEED, UInt64(1 if result else 0)))


@no_inline
def _bluetooth_le_gfsk_frequency_deviation_is_compliant_workload(
    profile: BluetoothLEGFSKLimits,
    positive_1010_deviation_hz: Float64,
    negative_1010_deviation_hz: Float64,
    deviation_00001111_hz: Float64,
    iterations: Int,
) raises -> Tuple[UInt64, UInt64]:
    var result = bluetooth_le_gfsk_frequency_deviation_is_compliant(
        profile,
        positive_1010_deviation_hz,
        negative_1010_deviation_hz,
        deviation_00001111_hz,
    )
    var start = global_perf_counter_ns()
    for _ in range(iterations):
        result = bluetooth_le_gfsk_frequency_deviation_is_compliant(
            black_box(profile),
            black_box(positive_1010_deviation_hz),
            black_box(negative_1010_deviation_hz),
            black_box(deviation_00001111_hz),
        )
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, _mix(_SEED, UInt64(1 if result else 0)))


@no_inline
def _bluetooth_le_gfsk_timing_is_compliant_workload(
    profile: BluetoothLEGFSKLimits,
    symbol_timing_error_ppm: Float64,
    zero_crossing_error_symbol_periods: Float64,
    iterations: Int,
) raises -> Tuple[UInt64, UInt64]:
    var result = bluetooth_le_gfsk_timing_is_compliant(
        profile,
        symbol_timing_error_ppm,
        zero_crossing_error_symbol_periods,
    )
    var start = global_perf_counter_ns()
    for _ in range(iterations):
        result = bluetooth_le_gfsk_timing_is_compliant(
            black_box(profile),
            black_box(symbol_timing_error_ppm),
            black_box(zero_crossing_error_symbol_periods),
        )
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, _mix(_SEED, UInt64(1 if result else 0)))


@no_inline
def _bluetooth_le_gfsk_bit_deviation_sign_is_compliant_workload(
    profile: BluetoothLEGFSKLimits,
    bit: Int,
    frequency_deviation_hz: Float64,
    iterations: Int,
) raises -> Tuple[UInt64, UInt64]:
    var result = bluetooth_le_gfsk_bit_deviation_sign_is_compliant(
        profile, bit, frequency_deviation_hz
    )
    var start = global_perf_counter_ns()
    for _ in range(iterations):
        result = bluetooth_le_gfsk_bit_deviation_sign_is_compliant(
            black_box(profile),
            black_box(bit),
            black_box(frequency_deviation_hz),
        )
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, _mix(_SEED, UInt64(1 if result else 0)))


@no_inline
def _bluetooth_le_gfsk_stable_claim_is_compliant_workload(
    profile: BluetoothLEGFSKLimits,
    stable_flags: Span[Bool, ...],
    claims_stable_index: Bool,
    iterations: Int,
) raises -> Tuple[UInt64, UInt64]:
    var result = bluetooth_le_gfsk_stable_claim_is_compliant(
        profile, stable_flags, claims_stable_index
    )
    var start = global_perf_counter_ns()
    for _ in range(iterations):
        result = bluetooth_le_gfsk_stable_claim_is_compliant(
            black_box(profile),
            black_box(stable_flags),
            black_box(claims_stable_index),
        )
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, _mix(_SEED, UInt64(1 if result else 0)))


def _run_limits(phy: Int) raises -> UInt64:
    var first = _bluetooth_le_gfsk_limits_workload(phy, _BATCH)
    var second = _bluetooth_le_gfsk_limits_workload(phy, _BATCH)
    var checksum = _require_repeat(first[1], second[1])
    keep(first)
    keep(second)
    for _ in range(_WARMUPS):
        keep(_bluetooth_le_gfsk_limits_workload(phy, _BATCH))
    var samples = List[UInt64](capacity=_SAMPLES)
    for _ in range(_SAMPLES):
        var sample = _bluetooth_le_gfsk_limits_workload(phy, _BATCH)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    report_timing_samples(
        "bluetooth_le_gfsk_limits", samples, _WARMUPS, _BATCH, "api_call"
    )
    keep(samples)
    return checksum


def _run_modulation_index(
    profile: BluetoothLEGFSKLimits,
    modulation_index: Float64,
    stable: Bool,
) raises -> UInt64:
    var first = _bluetooth_le_gfsk_modulation_index_is_compliant_workload(
        profile, modulation_index, stable, _BATCH
    )
    var second = _bluetooth_le_gfsk_modulation_index_is_compliant_workload(
        profile, modulation_index, stable, _BATCH
    )
    var checksum = _require_repeat(first[1], second[1])
    keep(first)
    keep(second)
    for _ in range(_WARMUPS):
        keep(_bluetooth_le_gfsk_modulation_index_is_compliant_workload(
            profile, modulation_index, stable, _BATCH
        ))
    var samples = List[UInt64](capacity=_SAMPLES)
    for _ in range(_SAMPLES):
        var sample = (
            _bluetooth_le_gfsk_modulation_index_is_compliant_workload(
                profile, modulation_index, stable, _BATCH
            )
        )
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    report_timing_samples(
        "bluetooth_le_gfsk_modulation_index_is_compliant",
        samples,
        _WARMUPS,
        _BATCH,
        "api_call",
    )
    keep(samples)
    return checksum


def _run_frequency_deviation(
    profile: BluetoothLEGFSKLimits,
    positive_1010_deviation_hz: Float64,
    negative_1010_deviation_hz: Float64,
    deviation_00001111_hz: Float64,
) raises -> UInt64:
    var first = _bluetooth_le_gfsk_frequency_deviation_is_compliant_workload(
        profile,
        positive_1010_deviation_hz,
        negative_1010_deviation_hz,
        deviation_00001111_hz,
        _BATCH,
    )
    var second = _bluetooth_le_gfsk_frequency_deviation_is_compliant_workload(
        profile,
        positive_1010_deviation_hz,
        negative_1010_deviation_hz,
        deviation_00001111_hz,
        _BATCH,
    )
    var checksum = _require_repeat(first[1], second[1])
    keep(first)
    keep(second)
    for _ in range(_WARMUPS):
        keep(_bluetooth_le_gfsk_frequency_deviation_is_compliant_workload(
            profile,
            positive_1010_deviation_hz,
            negative_1010_deviation_hz,
            deviation_00001111_hz,
            _BATCH,
        ))
    var samples = List[UInt64](capacity=_SAMPLES)
    for _ in range(_SAMPLES):
        var sample = (
            _bluetooth_le_gfsk_frequency_deviation_is_compliant_workload(
                profile,
                positive_1010_deviation_hz,
                negative_1010_deviation_hz,
                deviation_00001111_hz,
                _BATCH,
            )
        )
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    report_timing_samples(
        "bluetooth_le_gfsk_frequency_deviation_is_compliant",
        samples,
        _WARMUPS,
        _BATCH,
        "api_call",
    )
    keep(samples)
    return checksum


def _run_timing(
    profile: BluetoothLEGFSKLimits,
    timing_ppm: Float64,
    crossing_periods: Float64,
) raises -> UInt64:
    var first = _bluetooth_le_gfsk_timing_is_compliant_workload(
        profile, timing_ppm, crossing_periods, _BATCH
    )
    var second = _bluetooth_le_gfsk_timing_is_compliant_workload(
        profile, timing_ppm, crossing_periods, _BATCH
    )
    var checksum = _require_repeat(first[1], second[1])
    keep(first)
    keep(second)
    for _ in range(_WARMUPS):
        keep(_bluetooth_le_gfsk_timing_is_compliant_workload(
            profile, timing_ppm, crossing_periods, _BATCH
        ))
    var samples = List[UInt64](capacity=_SAMPLES)
    for _ in range(_SAMPLES):
        var sample = _bluetooth_le_gfsk_timing_is_compliant_workload(
            profile, timing_ppm, crossing_periods, _BATCH
        )
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    report_timing_samples(
        "bluetooth_le_gfsk_timing_is_compliant",
        samples,
        _WARMUPS,
        _BATCH,
        "api_call",
    )
    keep(samples)
    return checksum


def _run_bit_sign(
    profile: BluetoothLEGFSKLimits,
    bit: Int,
    deviation_hz: Float64,
) raises -> UInt64:
    var first = _bluetooth_le_gfsk_bit_deviation_sign_is_compliant_workload(
        profile, bit, deviation_hz, _BATCH
    )
    var second = _bluetooth_le_gfsk_bit_deviation_sign_is_compliant_workload(
        profile, bit, deviation_hz, _BATCH
    )
    var checksum = _require_repeat(first[1], second[1])
    keep(first)
    keep(second)
    for _ in range(_WARMUPS):
        keep(_bluetooth_le_gfsk_bit_deviation_sign_is_compliant_workload(
            profile, bit, deviation_hz, _BATCH
        ))
    var samples = List[UInt64](capacity=_SAMPLES)
    for _ in range(_SAMPLES):
        var sample = (
            _bluetooth_le_gfsk_bit_deviation_sign_is_compliant_workload(
                profile, bit, deviation_hz, _BATCH
            )
        )
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    report_timing_samples(
        "bluetooth_le_gfsk_bit_deviation_sign_is_compliant",
        samples,
        _WARMUPS,
        _BATCH,
        "api_call",
    )
    keep(samples)
    return checksum


def _run_stable_claim(
    profile: BluetoothLEGFSKLimits,
    stable_flags: Span[Bool, ...],
    stable: Bool,
) raises -> UInt64:
    var first = _bluetooth_le_gfsk_stable_claim_is_compliant_workload(
        profile, stable_flags, stable, _BATCH
    )
    var second = _bluetooth_le_gfsk_stable_claim_is_compliant_workload(
        profile, stable_flags, stable, _BATCH
    )
    var checksum = _require_repeat(first[1], second[1])
    keep(first)
    keep(second)
    for _ in range(_WARMUPS):
        keep(_bluetooth_le_gfsk_stable_claim_is_compliant_workload(
            profile, stable_flags, stable, _BATCH
        ))
    var samples = List[UInt64](capacity=_SAMPLES)
    for _ in range(_SAMPLES):
        var sample = _bluetooth_le_gfsk_stable_claim_is_compliant_workload(
            profile, stable_flags, stable, _BATCH
        )
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    report_timing_samples(
        "bluetooth_le_gfsk_stable_claim_is_compliant",
        samples,
        _WARMUPS,
        _BATCH,
        "api_call",
    )
    keep(samples)
    return checksum


def main() raises:
    print_benchmark_metadata()
    print("bluetooth_le_gfsk_limits_backend:", "scalar-cpu-reference")
    print(
        "bluetooth_le_gfsk_limits_baseline:",
        "Bluetooth-Core-6.3-Vol6-PartA-1-3.1.1",
    )

    # Every mutable profile, owned flag list, Span, and scalar is fixed before
    # the first preflight, warmup, or timed workload.
    var one = bluetooth_le_gfsk_limits(BLUETOOTH_LE_GFSK_PHY_1M)
    var two = bluetooth_le_gfsk_limits(BLUETOOTH_LE_GFSK_PHY_2M)
    var stable_flags: List[Bool] = [True, True, True]
    var stable_span = Span(stable_flags)
    var modulation_index = 0.5
    var positive_1010_deviation_hz = 400_000.0
    var negative_1010_deviation_hz = 370_000.0
    var deviation_00001111_hz = 462_500.0
    var timing_ppm = 49.0
    var crossing_periods = 0.124
    var bit = 1
    var signed_deviation_hz = 370_000.0

    var checksum = _SEED
    checksum = _mix(
        checksum, _run_limits(BLUETOOTH_LE_GFSK_PHY_2M)
    )
    checksum = _mix(
        checksum, _run_modulation_index(one, modulation_index, True)
    )
    checksum = _mix(
        checksum,
        _run_frequency_deviation(
            two,
            positive_1010_deviation_hz,
            negative_1010_deviation_hz,
            deviation_00001111_hz,
        ),
    )
    checksum = _mix(
        checksum, _run_timing(one, timing_ppm, crossing_periods)
    )
    checksum = _mix(
        checksum, _run_bit_sign(two, bit, signed_deviation_hz)
    )
    checksum = _mix(
        checksum, _run_stable_claim(one, stable_span, True)
    )
    keep(one)
    keep(two)
    keep(stable_flags)
    keep(checksum)
    print("bluetooth_le_gfsk_limits_retained_checksum:", checksum)
