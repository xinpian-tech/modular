"""Strict per-public-API TS 38.214 MCS/TBS CPU benchmark."""

from std.benchmark import keep
from std.time import global_perf_counter_ns
from wireless_dsp.benchmarking import print_benchmark_metadata, report_timing_samples
from wireless_dsp.wireless.nr.mcs_tbs import (
    NRMCSProfile,
    NRTransportBlockAllocation,
    nr_mcs_profile,
    nr_mcs_target_code_rate,
    nr_mcs_spectral_efficiency,
    nr_pdsch_resource_elements_per_prb,
    nr_transport_block_size,
    nr_transport_block_allocation,
)

comptime _WARMUPS = 3
comptime _SAMPLES = 9


def _mix(checksum: UInt64, value: Int) -> UInt64:
    return (checksum ^ UInt64(value + 1)) * UInt64(1099511628211)


@no_inline
def _workload_nr_mcs_profile() raises -> NRMCSProfile:
    return nr_mcs_profile(1, 17)


@no_inline
def _workload_nr_mcs_target_code_rate(profile: NRMCSProfile) raises -> Float64:
    return nr_mcs_target_code_rate(profile)


@no_inline
def _workload_nr_mcs_spectral_efficiency(profile: NRMCSProfile) raises -> Float64:
    return nr_mcs_spectral_efficiency(profile)


@no_inline
def _workload_nr_pdsch_resource_elements_per_prb() raises -> Int:
    return nr_pdsch_resource_elements_per_prb(12, 12, 6)


@no_inline
def _workload_nr_transport_block_size(profile: NRMCSProfile) raises -> Int:
    return nr_transport_block_size(12960, profile, 2)


@no_inline
def _workload_nr_transport_block_allocation(
    profile: NRMCSProfile,
) raises -> NRTransportBlockAllocation:
    return nr_transport_block_allocation(96, 12, 12, 6, profile, 2)


def _finish(name: StringSlice, mut samples: List[UInt64], checksum: UInt64) raises -> UInt64:
    report_timing_samples(name, samples, _WARMUPS, 1, "api_call")
    keep(samples)
    return checksum


def _benchmark_profile() raises -> UInt64:
    for _ in range(_WARMUPS):
        keep(_workload_nr_mcs_profile())
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(14695981039346656037)
    for _ in range(_SAMPLES):
        var start = global_perf_counter_ns()
        var result = _workload_nr_mcs_profile()
        samples.append(global_perf_counter_ns() - start)
        keep(result)
        checksum = _mix(checksum, result.index)
    return _finish("nr_mcs_profile", samples, checksum)


def _benchmark_rate(profile: NRMCSProfile) raises -> UInt64:
    for _ in range(_WARMUPS):
        keep(_workload_nr_mcs_target_code_rate(profile))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(14695981039346656037)
    for _ in range(_SAMPLES):
        var start = global_perf_counter_ns()
        var result = _workload_nr_mcs_target_code_rate(profile)
        samples.append(global_perf_counter_ns() - start)
        keep(result)
        checksum = _mix(checksum, Int(result * 2048.0))
    return _finish("nr_mcs_target_code_rate", samples, checksum)


def _benchmark_efficiency(profile: NRMCSProfile) raises -> UInt64:
    for _ in range(_WARMUPS):
        keep(_workload_nr_mcs_spectral_efficiency(profile))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(14695981039346656037)
    for _ in range(_SAMPLES):
        var start = global_perf_counter_ns()
        var result = _workload_nr_mcs_spectral_efficiency(profile)
        samples.append(global_perf_counter_ns() - start)
        keep(result)
        checksum = _mix(checksum, Int(result * 2048.0))
    return _finish("nr_mcs_spectral_efficiency", samples, checksum)


def _benchmark_re() raises -> UInt64:
    for _ in range(_WARMUPS):
        keep(_workload_nr_pdsch_resource_elements_per_prb())
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(14695981039346656037)
    for _ in range(_SAMPLES):
        var start = global_perf_counter_ns()
        var result = _workload_nr_pdsch_resource_elements_per_prb()
        samples.append(global_perf_counter_ns() - start)
        keep(result)
        checksum = _mix(checksum, result)
    return _finish("nr_pdsch_resource_elements_per_prb", samples, checksum)


def _benchmark_tbs(profile: NRMCSProfile) raises -> UInt64:
    for _ in range(_WARMUPS):
        keep(_workload_nr_transport_block_size(profile))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(14695981039346656037)
    for _ in range(_SAMPLES):
        var start = global_perf_counter_ns()
        var result = _workload_nr_transport_block_size(profile)
        samples.append(global_perf_counter_ns() - start)
        keep(result)
        checksum = _mix(checksum, result)
    return _finish("nr_transport_block_size", samples, checksum)


def _benchmark_allocation(profile: NRMCSProfile) raises -> UInt64:
    for _ in range(_WARMUPS):
        keep(_workload_nr_transport_block_allocation(profile))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(14695981039346656037)
    for _ in range(_SAMPLES):
        var start = global_perf_counter_ns()
        var result = _workload_nr_transport_block_allocation(profile)
        samples.append(global_perf_counter_ns() - start)
        keep(result)
        checksum = _mix(checksum, result.transport_block_size)
    return _finish("nr_transport_block_allocation", samples, checksum)


def main() raises:
    print_benchmark_metadata()
    var profile = nr_mcs_profile(1, 17)
    var checksum = _benchmark_profile()
    checksum ^= _benchmark_rate(profile)
    checksum ^= _benchmark_efficiency(profile)
    checksum ^= _benchmark_re()
    checksum ^= _benchmark_tbs(profile)
    checksum ^= _benchmark_allocation(profile)
    keep(profile)
    keep(checksum)
    print("nr_mcs_tbs_retained_checksum:", checksum)
