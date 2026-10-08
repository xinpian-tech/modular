"""Strict per-public-API benchmark for Monte-Carlo foundation APIs."""

from std.benchmark import keep
from std.collections import Span
from std.time import global_perf_counter_ns
from wireless_dsp.benchmarking import print_benchmark_metadata, report_timing_samples
from wireless_dsp.testing import (
    SNR_EBN0_INFORMATION,
    MONTE_CARLO_METRIC_BER,
    LINK_SEED_STREAM_NOISE,
    LinkSNRPoint,
    LinkEnergyReference,
    LinkCounters,
    MonteCarloStop,
    BinomialInterval,
    LinkCase,
    LinkSweepPoint,
    link_noise_variance,
    wilson_interval,
    monte_carlo_stop_reason,
    should_stop,
    derive_link_seed,
    cartesian_link_cases,
    make_link_sweep_point,
)

comptime _WARMUPS = 3
comptime _SAMPLES = 9


def _mix(checksum: UInt64, value: UInt64) -> UInt64:
    return (checksum ^ value) * UInt64(1099511628211)


@no_inline
def _workload_link_noise_variance(
    point: LinkSNRPoint, energy: LinkEnergyReference,
) raises -> Float64:
    return link_noise_variance(point, energy)


@no_inline
def _workload_wilson_interval() raises -> BinomialInterval:
    return wilson_interval(37, 1000)


@no_inline
def _workload_monte_carlo_stop_reason(
    counters: LinkCounters, policy: MonteCarloStop,
) raises -> Int:
    return monte_carlo_stop_reason(counters, policy, MONTE_CARLO_METRIC_BER)


@no_inline
def _workload_should_stop(
    counters: LinkCounters, policy: MonteCarloStop,
) raises -> Bool:
    return should_stop(counters, policy, MONTE_CARLO_METRIC_BER)


@no_inline
def _workload_derive_link_seed() -> UInt64:
    return derive_link_seed(
        UInt64(0x5EED), UInt64(1), UInt64(6), UInt64(10250),
        UInt64(2), UInt64(17), UInt64(31), LINK_SEED_STREAM_NOISE,
    )


@no_inline
def _workload_cartesian_link_cases(
    protocols: Span[UInt64, ...], mcs: Span[UInt64, ...],
    snrs: Span[LinkSNRPoint, ...], snr_ids: Span[UInt64, ...],
    channels: Span[UInt64, ...], channel_seeds: Span[UInt64, ...],
) raises -> List[LinkCase]:
    return cartesian_link_cases(
        protocols, mcs, snrs, snr_ids, channels, channel_seeds
    )


@no_inline
def _workload_make_link_sweep_point(
    link_case: LinkCase,
    counters: LinkCounters,
    policy: MonteCarloStop,
) raises -> LinkSweepPoint:
    return make_link_sweep_point(
        link_case, counters, policy, MONTE_CARLO_METRIC_BER
    )


def _finish(
    name: StringSlice, mut samples: List[UInt64], checksum: UInt64
) raises -> UInt64:
    report_timing_samples(name, samples, _WARMUPS, 1, "api_call")
    keep(samples)
    return checksum


def _benchmark_noise(point: LinkSNRPoint, energy: LinkEnergyReference) raises -> UInt64:
    for _ in range(_WARMUPS):
        keep(_workload_link_noise_variance(point, energy))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(14695981039346656037)
    for _ in range(_SAMPLES):
        var start = global_perf_counter_ns()
        var result = _workload_link_noise_variance(point, energy)
        samples.append(global_perf_counter_ns() - start)
        keep(result)
        checksum = _mix(checksum, UInt64(result * 1.0e12))
    return _finish("link_noise_variance", samples, checksum)


def _benchmark_wilson() raises -> UInt64:
    for _ in range(_WARMUPS):
        keep(_workload_wilson_interval())
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(14695981039346656037)
    for _ in range(_SAMPLES):
        var start = global_perf_counter_ns()
        var result = _workload_wilson_interval()
        samples.append(global_perf_counter_ns() - start)
        keep(result)
        checksum = _mix(checksum, UInt64(result.half_width * 1.0e15))
    return _finish("wilson_interval", samples, checksum)


def _benchmark_stop(counters: LinkCounters, policy: MonteCarloStop) raises -> UInt64:
    for _ in range(_WARMUPS):
        keep(_workload_monte_carlo_stop_reason(counters, policy))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(14695981039346656037)
    for _ in range(_SAMPLES):
        var start = global_perf_counter_ns()
        var result = _workload_monte_carlo_stop_reason(counters, policy)
        samples.append(global_perf_counter_ns() - start)
        keep(result)
        checksum = _mix(checksum, UInt64(result))
    return _finish("monte_carlo_stop_reason", samples, checksum)


def _benchmark_should_stop(
    counters: LinkCounters, policy: MonteCarloStop
) raises -> UInt64:
    for _ in range(_WARMUPS):
        keep(_workload_should_stop(counters, policy))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(14695981039346656037)
    for _ in range(_SAMPLES):
        var start = global_perf_counter_ns()
        var result = _workload_should_stop(counters, policy)
        samples.append(global_perf_counter_ns() - start)
        keep(result)
        checksum = _mix(checksum, UInt64(result))
    return _finish("should_stop", samples, checksum)


def _benchmark_seed() raises -> UInt64:
    for _ in range(_WARMUPS):
        keep(_workload_derive_link_seed())
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(14695981039346656037)
    for _ in range(_SAMPLES):
        var start = global_perf_counter_ns()
        var result = _workload_derive_link_seed()
        samples.append(global_perf_counter_ns() - start)
        keep(result)
        checksum = _mix(checksum, result)
    return _finish("derive_link_seed", samples, checksum)


def _benchmark_cartesian(
    protocols: Span[UInt64, ...], mcs: Span[UInt64, ...],
    snrs: Span[LinkSNRPoint, ...], snr_ids: Span[UInt64, ...],
    channels: Span[UInt64, ...], channel_seeds: Span[UInt64, ...],
) raises -> UInt64:
    for _ in range(_WARMUPS):
        keep(_workload_cartesian_link_cases(
            protocols, mcs, snrs, snr_ids, channels, channel_seeds
        ))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(14695981039346656037)
    for _ in range(_SAMPLES):
        var start = global_perf_counter_ns()
        var result = _workload_cartesian_link_cases(
            protocols, mcs, snrs, snr_ids, channels, channel_seeds
        )
        samples.append(global_perf_counter_ns() - start)
        keep(result)
        checksum = _mix(checksum, UInt64(len(result)))
        checksum = _mix(checksum, result[len(result) - 1].channel_seed_identity)
    return _finish("cartesian_link_cases", samples, checksum)


def _benchmark_sweep_point(
    link_case: LinkCase,
    counters: LinkCounters,
    policy: MonteCarloStop,
) raises -> UInt64:
    for _ in range(_WARMUPS):
        keep(_workload_make_link_sweep_point(link_case, counters, policy))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(14695981039346656037)
    for _ in range(_SAMPLES):
        var start = global_perf_counter_ns()
        var result = _workload_make_link_sweep_point(
            link_case, counters, policy
        )
        samples.append(global_perf_counter_ns() - start)
        keep(result)
        checksum = _mix(checksum, UInt64(result.stop_reason))
        checksum = _mix(checksum, UInt64(result.counters.bit_count))
        checksum = _mix(
            checksum, UInt64(result.interval.estimate * 1.0e15)
        )
    return _finish("make_link_sweep_point", samples, checksum)


def main() raises:
    print_benchmark_metadata()
    var point = LinkSNRPoint(SNR_EBN0_INFORMATION, 2.5)
    var energy = LinkEnergyReference(
        waveform_energy=937.5, information_bits=317, sample_count=1024
    )
    var counters = LinkCounters(bit_count=4096, bit_errors=37)
    var policy = MonteCarloStop(min_trials=256, max_trials=8192, target_errors=64)
    var protocols: List[UInt64] = [UInt64(1), UInt64(2)]
    var mcs: List[UInt64] = [UInt64(0), UInt64(6)]
    var snrs: List[LinkSNRPoint] = [point]
    var snr_ids: List[UInt64] = [UInt64(10250)]
    var channels: List[UInt64] = [UInt64(1), UInt64(2)]
    var channel_seeds: List[UInt64] = [UInt64(11), UInt64(17)]
    var checksum = _benchmark_noise(point, energy)
    checksum ^= _benchmark_wilson()
    checksum ^= _benchmark_stop(counters, policy)
    checksum ^= _benchmark_should_stop(counters, policy)
    checksum ^= _benchmark_seed()
    checksum ^= _benchmark_cartesian(
        Span(protocols), Span(mcs), Span(snrs), Span(snr_ids),
        Span(channels), Span(channel_seeds),
    )
    var link_case = LinkCase(
        UInt64(1), UInt64(6), point, UInt64(10250), UInt64(2), UInt64(17)
    )
    checksum ^= _benchmark_sweep_point(link_case, counters, policy)
    keep(checksum)
    print("monte_carlo_combined_checksum:", checksum)
