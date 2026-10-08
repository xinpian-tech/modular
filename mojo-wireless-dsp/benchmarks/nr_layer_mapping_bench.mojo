"""Attributable CPU benchmarks for exact NR PDSCH layer mapping."""

from std.benchmark import black_box, keep
from std.collections import Span
from std.time import global_perf_counter_ns
from wireless_dsp.benchmarking import (
    print_benchmark_metadata,
    report_timing_samples,
)
from wireless_dsp.core import Complex64
from wireless_dsp.wireless.nr.layer_mapping import (
    NRPDSCHLayerMapping,
    nr_pdsch_codeword_layer_allocation,
    nr_pdsch_layer_map,
    nr_pdsch_layer_demap,
)


comptime _WARMUPS = 3
comptime _SAMPLES = 9
comptime _TABLE_BATCH = 4096
comptime _MAP_BATCH = 256
comptime _SYMBOLS_PER_LAYER = 16
comptime _LAYER_COUNT = 8
comptime _MAPPED_SYMBOLS = _LAYER_COUNT * _SYMBOLS_PER_LAYER


def _mix(checksum: UInt64, value: UInt64) -> UInt64:
    return (checksum ^ value) * UInt64(1099511628211)


def _input(count: Int, offset: Int) -> List[Complex64]:
    var values = List[Complex64](capacity=count)
    for index in range(count):
        values.append(
            Complex64(
                Float64(offset + index + 1),
                -Float64(offset + 2 * index + 1),
            )
        )
    return values^


@no_inline
def _allocation_workload(iterations: Int, salt: Int) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for operation in range(iterations):
        var allocation = nr_pdsch_codeword_layer_allocation(
            black_box(1 + (operation + salt) % 8)
        )
        checksum = _mix(
            checksum,
            UInt64(
                allocation.codeword_count
                + 3 * allocation.codeword0_layers
                + 7 * allocation.codeword1_layers
                + operation
            ),
        )
    return checksum


@no_inline
def _map_workload(
    codeword0: Span[Complex64, ...],
    codeword1: Span[Complex64, ...],
    iterations: Int,
) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for operation in range(iterations):
        var mapping = nr_pdsch_layer_map(
            codeword0, codeword1, black_box(_LAYER_COUNT)
        )
        for index in range(len(mapping.values)):
            checksum = _mix(
                checksum,
                UInt64(abs(mapping.values[index].re))
                + UInt64(abs(mapping.values[index].im))
                + UInt64(index + operation + 1),
            )
        keep(mapping)
    return checksum


@no_inline
def _demap_workload(
    mapping: NRPDSCHLayerMapping, iterations: Int
) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for operation in range(iterations):
        var codewords = nr_pdsch_layer_demap(black_box(mapping))
        for index in range(len(codewords.codeword0)):
            checksum = _mix(
                checksum,
                UInt64(abs(codewords.codeword0[index].re))
                + UInt64(abs(codewords.codeword0[index].im))
                + UInt64(index + operation + 1),
            )
        for index in range(len(codewords.codeword1)):
            checksum = _mix(
                checksum,
                UInt64(abs(codewords.codeword1[index].re))
                + UInt64(abs(codewords.codeword1[index].im))
                + UInt64(index + operation + 1),
            )
        keep(codewords)
    return checksum


def main() raises:
    var codeword0 = _input(4 * _SYMBOLS_PER_LAYER, 0)
    var codeword1 = _input(4 * _SYMBOLS_PER_LAYER, 1000)
    var mapping = nr_pdsch_layer_map(
        Span(codeword0), Span(codeword1), _LAYER_COUNT
    )
    for warmup in range(_WARMUPS):
        var salt = 324508639 + warmup
        keep(_allocation_workload(_TABLE_BATCH, salt))
        keep(_map_workload(Span(codeword0), Span(codeword1), _MAP_BATCH))
        keep(_demap_workload(mapping, _MAP_BATCH))

    var allocation_samples = List[UInt64](capacity=_SAMPLES)
    var map_samples = List[UInt64](capacity=_SAMPLES)
    var demap_samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for sample in range(_SAMPLES):
        var salt = 324508639 + sample
        var start = global_perf_counter_ns()
        var allocation_checksum = _allocation_workload(_TABLE_BATCH, salt)
        allocation_samples.append(global_perf_counter_ns() - start)
        checksum = _mix(checksum, allocation_checksum)
        keep(allocation_checksum)

        start = global_perf_counter_ns()
        var map_checksum = _map_workload(
            Span(codeword0), Span(codeword1), _MAP_BATCH
        )
        map_samples.append(global_perf_counter_ns() - start)
        checksum = _mix(checksum, map_checksum)
        keep(map_checksum)

        start = global_perf_counter_ns()
        var demap_checksum = _demap_workload(mapping, _MAP_BATCH)
        demap_samples.append(global_perf_counter_ns() - start)
        checksum = _mix(checksum, demap_checksum)
        keep(demap_checksum)

    print_benchmark_metadata()
    print("nr_layer_mapping_backend:", "scalar-cpu-reference")
    print("nr_layer_mapping_baseline:", "TS-38.211-V18.9.0-7.3.1.3")
    report_timing_samples(
        "nr_pdsch_codeword_layer_allocation",
        allocation_samples,
        _WARMUPS,
        _TABLE_BATCH,
        "table_lookup",
    )
    report_timing_samples(
        "nr_pdsch_layer_map",
        map_samples,
        _WARMUPS,
        _MAP_BATCH * _MAPPED_SYMBOLS,
        "mapped_complex_symbol",
    )
    report_timing_samples(
        "nr_pdsch_layer_demap",
        demap_samples,
        _WARMUPS,
        _MAP_BATCH * _MAPPED_SYMBOLS,
        "demapped_complex_symbol",
    )
    keep(checksum)
    print("nr_layer_mapping_retained_checksum:", checksum)
