"""Strict attributable timings for Rel-17 RedCap PRACH placement."""

from std.benchmark import keep
from std.time import global_perf_counter_ns
from wireless_dsp.benchmarking import (
    print_benchmark_metadata,
    report_timing_samples,
)
from wireless_dsp.wireless.nr.prach import (
    NRPRACHFormat,
    PRACH_FORMAT_A2,
    PRACH_SET_UNRESTRICTED,
    nr_prach_format_parameters,
)
from wireless_dsp.wireless.nr.redcap import (
    NR_FREQUENCY_RANGE_FR1,
    NRRedCapInitialBWP,
    NRRedCapRel17Capabilities,
)
from wireless_dsp.wireless.nr.redcap_prach_placement import (
    nr_redcap_rel17_prach_frequency_placement,
    nr_redcap_rel17_prach_placed_composite,
    nr_redcap_rel17_prach_resource_allocation,
)


comptime _WARMUPS = 3
comptime _SAMPLES = 9
comptime _SEED = UInt64(1469598103934665603)


def _mix(checksum: UInt64, value: UInt64) -> UInt64:
    return (checksum ^ value) * UInt64(1099511628211)


def _run[
    workload: def() thin raises -> Tuple[UInt64, UInt64]
](name: StringSlice) raises -> UInt64:
    var first = workload()
    var second = workload()
    if first[1] != second[1]:
        raise Error("RedCap PRACH placement benchmark is nondeterministic")
    keep(first)
    keep(second)
    for _ in range(_WARMUPS):
        keep(workload())
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = _SEED
    for _ in range(_SAMPLES):
        var sample = workload()
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    report_timing_samples(name, samples, _WARMUPS, 1, "api_call")
    keep(samples)
    return checksum


def _capabilities(two_step: Bool = False) raises -> NRRedCapRel17Capabilities:
    return NRRedCapRel17Capabilities(
        NR_FREQUENCY_RANGE_FR1,
        20.0,
        1,
        1,
        supports_two_step_rach=two_step,
    )


def _bwp() raises -> NRRedCapInitialBWP:
    return NRRedCapInitialBWP(8, 51, 3500000, 30)


def _prach_parameters() raises -> NRPRACHFormat:
    return nr_prach_format_parameters(
        PRACH_FORMAT_A2, numerology=1, sequence_length=139
    )


@no_inline
def _placement_workload() raises -> Tuple[UInt64, UInt64]:
    var capabilities = _capabilities(True)
    var bwp = _bwp()
    var start = global_perf_counter_ns()
    var result = nr_redcap_rel17_prach_frequency_placement(
        capabilities,
        bwp,
        106,
        3,
        1,
        4,
        6,
        two_step_random_access=True,
    )
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = UInt64(result.source + 1)
    fingerprint = _mix(
        fingerprint, UInt64(result.start_common_resource_block)
    )
    fingerprint = _mix(
        fingerprint, UInt64(result.lowest_common_grid_subcarrier)
    )
    return (elapsed, fingerprint)


@no_inline
def _allocation_workload() raises -> Tuple[UInt64, UInt64]:
    var capabilities = _capabilities()
    var start = global_perf_counter_ns()
    var result = nr_redcap_rel17_prach_resource_allocation(
        capabilities, 139, 30000, 30
    )
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = UInt64(result.resource_blocks)
    fingerprint = _mix(fingerprint, UInt64(result.k_bar))
    return (elapsed, fingerprint)


@no_inline
def _composite_workload() raises -> Tuple[UInt64, UInt64]:
    var capabilities = _capabilities()
    var bwp = _bwp()
    var parameters = _prach_parameters()
    var start = global_perf_counter_ns()
    var result = nr_redcap_rel17_prach_placed_composite(
        capabilities,
        bwp,
        106,
        3,
        1,
        2,
        parameters,
        0,
        13,
        PRACH_SET_UNRESTRICTED,
        3,
        preamble_count=8,
    )
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = UInt64(
        result.placement.start_common_resource_block
    )
    fingerprint = _mix(
        fingerprint,
        UInt64(result.normalized.detection.preamble_index + 1),
    )
    fingerprint = _mix(
        fingerprint, UInt64(len(result.normalized.normalized_waveform))
    )
    return (elapsed, fingerprint)


def main() raises:
    print_benchmark_metadata()
    print("nr_redcap_prach_placement_backend:", "scalar-cpu-reference")
    print("nr_redcap_prach_placement_baseline:", "TS-38.211-V17.10.0")
    var checksum = _SEED
    checksum = _mix(
        checksum,
        _run[_placement_workload](
            "nr_redcap_rel17_prach_frequency_placement"
        ),
    )
    checksum = _mix(
        checksum,
        _run[_allocation_workload](
            "nr_redcap_rel17_prach_resource_allocation"
        ),
    )
    checksum = _mix(
        checksum,
        _run[_composite_workload](
            "nr_redcap_rel17_prach_placed_composite"
        ),
    )
    keep(checksum)
    print("nr_redcap_prach_placement_retained_checksum:", checksum)
