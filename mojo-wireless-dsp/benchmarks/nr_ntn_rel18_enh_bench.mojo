"""CPU benchmarks for bounded Rel-18 NR-NTN RACH-less CG decisions."""

from std.benchmark import black_box, keep
from std.collections import Span
from std.time import global_perf_counter_ns
from wireless_dsp.benchmarking import (
    print_benchmark_metadata,
    report_timing_samples,
)
from wireless_dsp.wireless.nr.ntn_rel18_enh import (
    NRNTNRel18RACHlessCGConfig,
    nr_ntn_rel18_cg_ssb_above_threshold,
    nr_ntn_rel18_cg_resources_per_mapping_cycle,
    nr_ntn_rel18_cg_mapping,
)


comptime _WARMUPS = 3
comptime _SAMPLES = 9
comptime _BATCH = 8192
comptime _EXPECTED_RETAINED_CHECKSUM = UInt64(13695312129525448790)


def _mix(checksum: UInt64, value: UInt64) -> UInt64:
    return (checksum ^ value) * UInt64(1099511628211)


def _ssb_for_ordinal(ordinal: Int) -> Int:
    if ordinal == 0:
        return 0
    if ordinal == 1:
        return 2
    if ordinal == 2:
        return 3
    return 5


def _replica_count(code: Int) -> Int:
    if code == 0:
        return 8
    if code == 1:
        return 4
    if code == 2:
        return 2
    return 1


def _build_configs() raises -> List[NRNTNRel18RACHlessCGConfig]:
    var configs = List[NRNTNRel18RACHlessCGConfig](capacity=8)
    for code in range(8):
        configs.append(
            NRNTNRel18RACHlessCGConfig(8, 0xB4, code, 0xA0, 2)
        )
    return configs^


@no_inline
def _threshold_workload(iterations: Int, salt: Int) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for operation in range(iterations):
        var threshold = (operation * 17 + salt) & 127
        var measured = -170.0 + Float64((operation * 29 + salt) % 181)
        var above = nr_ntn_rel18_cg_ssb_above_threshold(
            black_box(measured), black_box(threshold)
        )
        checksum = _mix(
            checksum,
            UInt64(threshold) ^ (UInt64(above) << 8),
        )
        keep(above)
    return checksum


@no_inline
def _cycle_size_workload(
    iterations: Int,
    salt: Int,
    configs: Span[NRNTNRel18RACHlessCGConfig, ...],
) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for operation in range(iterations):
        var code = (operation + salt) & 7
        var config = configs[code]
        var resources = nr_ntn_rel18_cg_resources_per_mapping_cycle(
            black_box(config)
        )
        checksum = _mix(
            checksum,
            UInt64(resources) ^ (UInt64(code) << 8),
        )
        keep(resources)
    return checksum


@no_inline
def _mapping_workload(
    iterations: Int,
    salt: Int,
    configs: Span[NRNTNRel18RACHlessCGConfig, ...],
) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for operation in range(iterations):
        var selector = operation + salt
        var code = selector & 7
        var config = configs[code]
        var ssb = _ssb_for_ordinal((selector >> 3) & 3)
        var replica_count = _replica_count(code)
        var replica = (selector >> 5) % replica_count
        var mapped = nr_ntn_rel18_cg_mapping(
            black_box(config), black_box(ssb), black_box(replica)
        )
        checksum = _mix(
            checksum,
            UInt64(mapped.resource_ordinal)
            ^ (UInt64(mapped.pusch_configuration_period_index) << 8)
            ^ (UInt64(mapped.dmrs_port_index) << 16)
            ^ (UInt64(mapped.dmrs_sequence_index) << 24)
            ^ (UInt64(mapped.ssb_group_size) << 32),
        )
        keep(mapped)
    return checksum


def main() raises:
    var configs = _build_configs()
    var configs_span = Span(configs)
    for warmup in range(_WARMUPS):
        keep(_threshold_workload(_BATCH, warmup))
        keep(_cycle_size_workload(_BATCH, warmup, configs_span))
        keep(_mapping_workload(_BATCH, warmup, configs_span))

    var threshold_samples = List[UInt64](capacity=_SAMPLES)
    var cycle_size_samples = List[UInt64](capacity=_SAMPLES)
    var mapping_samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for sample in range(_SAMPLES):
        var start = global_perf_counter_ns()
        var value = _threshold_workload(_BATCH, sample)
        threshold_samples.append(global_perf_counter_ns() - start)
        checksum = _mix(checksum, value)
        keep(value)

        start = global_perf_counter_ns()
        value = _cycle_size_workload(_BATCH, sample, configs_span)
        cycle_size_samples.append(global_perf_counter_ns() - start)
        checksum = _mix(checksum, value)
        keep(value)

        start = global_perf_counter_ns()
        value = _mapping_workload(_BATCH, sample, configs_span)
        mapping_samples.append(global_perf_counter_ns() - start)
        checksum = _mix(checksum, value)
        keep(value)

    print_benchmark_metadata()
    print("nr_ntn_rel18_enh_backend:", "scalar-cpu-reference")
    print(
        "nr_ntn_rel18_enh_baseline:",
        "RP-240779-38.213-i80-38.321-ia0-38.331-ia0",
    )
    report_timing_samples(
        "nr_ntn_rel18_cg_ssb_above_threshold",
        threshold_samples,
        _WARMUPS,
        _BATCH,
        "decision",
    )
    report_timing_samples(
        "nr_ntn_rel18_cg_resources_per_mapping_cycle",
        cycle_size_samples,
        _WARMUPS,
        _BATCH,
        "configuration",
    )
    report_timing_samples(
        "nr_ntn_rel18_cg_mapping",
        mapping_samples,
        _WARMUPS,
        _BATCH,
        "association",
    )
    keep(checksum)
    print("nr_ntn_rel18_enh_retained_checksum:", checksum)
    if checksum != _EXPECTED_RETAINED_CHECKSUM:
        raise Error("Rel-18 NTN benchmark retained checksum changed")
