"""Attributable scalar-CPU timings for the bounded LTE Annex-B channel slice."""

from std.benchmark import keep
from std.time import global_perf_counter_ns
from wireless_dsp.benchmarking import (
    print_benchmark_metadata,
    report_timing_samples,
)
from wireless_dsp.channel.standard_profiles import (
    StandardChannelProfile,
    lte_profile,
    realize_standard_channel_paths,
)
from wireless_dsp.core import Complex64


comptime _WARMUPS = 3
comptime _SAMPLES = 9


def _mix(checksum: UInt64, value: UInt64) -> UInt64:
    return (checksum ^ value) * UInt64(1099511628211)


def _require_repeat(first: UInt64, second: UInt64) raises:
    if first != second:
        raise Error("LTE channel benchmark result is nondeterministic")
    keep(first)
    keep(second)


def _fingerprint_float(value: Float64) -> UInt64:
    return _mix(
        UInt64(Int(abs(value) * 1_000_000.0)),
        UInt64(1 if value < 0.0 else 0),
    )


def _fingerprint_complex(value: Complex64) -> UInt64:
    return _mix(_fingerprint_float(value.re), _fingerprint_float(value.im))


def _fingerprint_profile(profile: StandardChannelProfile) -> UInt64:
    var checksum = UInt64(len(profile.delays))
    checksum = _mix(checksum, UInt64(profile.family))
    checksum = _mix(checksum, _fingerprint_float(profile.delay_scale_ns))
    checksum = _mix(checksum, UInt64(profile.doppler_spectrum))
    if len(profile.delays) > 0:
        var last = len(profile.delays) - 1
        checksum = _mix(checksum, _fingerprint_float(profile.delays[0]))
        checksum = _mix(checksum, _fingerprint_float(profile.delays[last]))
        checksum = _mix(checksum, _fingerprint_float(profile.powers_db[0]))
        checksum = _mix(checksum, _fingerprint_float(profile.powers_db[last]))
        checksum = _mix(checksum, UInt64(profile.fading_kinds[0]))
        checksum = _mix(checksum, UInt64(profile.fading_kinds[last]))
    return checksum


def _fingerprint_paths(paths: List[Complex64]) -> UInt64:
    var checksum = UInt64(len(paths))
    if len(paths) > 0:
        checksum = _mix(checksum, _fingerprint_complex(paths[0]))
        checksum = _mix(
            checksum, _fingerprint_complex(paths[len(paths) - 1])
        )
    return checksum


def _finish_sample(
    name: StringSlice, mut samples: List[UInt64], checksum: UInt64
) raises -> UInt64:
    report_timing_samples(name, samples, _WARMUPS, 1, "api_call")
    keep(samples)
    return checksum


@no_inline
def _bench_lte_profile(model: String) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = lte_profile(model)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _fingerprint_profile(result)
    return (elapsed, fingerprint)


def _run_lte_profile() raises -> UInt64:
    var model = String("ETU")
    var first = _bench_lte_profile(model)
    var second = _bench_lte_profile(model)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_lte_profile(model))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_lte_profile(model)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("lte_profile", samples, checksum)


@no_inline
def _bench_lte_realize_standard_channel_paths(
    profile: StandardChannelProfile,
    time_seconds: Float64,
    maximum_doppler_hz: Float64,
    seed: UInt64,
) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = realize_standard_channel_paths(
        profile, time_seconds=time_seconds,
        maximum_doppler_hz=maximum_doppler_hz, seed=seed,
    )
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _fingerprint_paths(result)
    return (elapsed, fingerprint)


def _run_lte_realize_standard_channel_paths() raises -> UInt64:
    var profile = lte_profile(String("EVA"))
    var time_seconds = 0.0125
    var maximum_doppler_hz = 70.0
    var seed = UInt64(36101)
    var first = _bench_lte_realize_standard_channel_paths(
        profile, time_seconds, maximum_doppler_hz, seed
    )
    var second = _bench_lte_realize_standard_channel_paths(
        profile, time_seconds, maximum_doppler_hz, seed
    )
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_bench_lte_realize_standard_channel_paths(
            profile, time_seconds, maximum_doppler_hz, seed
        ))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _bench_lte_realize_standard_channel_paths(
            profile, time_seconds, maximum_doppler_hz, seed
        )
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample(
        "lte_realize_standard_channel_paths", samples, checksum
    )


def main() raises:
    print_benchmark_metadata()
    print("lte_channel_standard_baseline:", "3GPP-TS-36.101-V18.13.0-Annex-B")
    print("lte_channel_profile:", "SISO-EPA5-EVA5/EVA70-ETU70/ETU300")
    print("timing_scope_includes_output_allocation:", True)
    var checksum = UInt64(1469598103934665603)
    checksum = _mix(checksum, _run_lte_profile())
    checksum = _mix(checksum, _run_lte_realize_standard_channel_paths())
    keep(checksum)
    print("lte_channel_retained_checksum:", checksum)
