"""CPU reference timings for bounded LTE PUSCH, PRACH, and RE mapping."""

from std.benchmark import keep
from std.collections import Span
from std.time import global_perf_counter_ns
from wireless_dsp.benchmarking import (
    print_benchmark_metadata,
    report_timing_samples,
)
from wireless_dsp.core import Complex64
from wireless_dsp.wireless.lte.physical import (
    LTEPRACHDetection,
    lte_pusch_scrambling_c_init,
    lte_pusch_scramble,
    lte_pusch_dmrs_base_sequence,
    lte_pusch_dmrs_sequence,
    lte_prach_root_sequence,
    lte_prach_unrestricted_cyclic_shift,
    lte_prach_format0_sequence,
    lte_prach_format0_normalized_waveform,
    lte_detect_prach_format0,
    lte_pdsch_map_siso,
    lte_pdsch_extract_siso,
    lte_pusch_map_siso,
    lte_pusch_extract_siso,
)


comptime _WARMUP = 3
comptime _SAMPLES = 9
comptime _UPLINK_OPERATIONS = 16
comptime _PRACH_OPERATIONS = 1
comptime _MAPPING_OPERATIONS = 16


def _mix(checksum: UInt64, value: Int) -> UInt64:
    return (checksum ^ UInt64(value)) * UInt64(1099511628211)


@no_inline
def _workload_lte_pusch_scrambling_c_init() raises -> UInt32:
    return lte_pusch_scrambling_c_init(0x1234, 0, 7, 101)


@no_inline
def _workload_lte_pusch_scramble(bits: Span[UInt8, ...]) raises -> List[UInt8]:
    return lte_pusch_scramble(bits, 0x1234, 0, 7, 101)


@no_inline
def _workload_lte_pusch_dmrs_base_sequence() raises -> List[Complex64]:
    return lte_pusch_dmrs_base_sequence(7, 0, 3)


@no_inline
def _workload_lte_pusch_dmrs_sequence() raises -> List[Complex64]:
    return lte_pusch_dmrs_sequence(7, 0, 3, 4)


@no_inline
def _workload_lte_prach_root_sequence() raises -> List[Complex64]:
    return lte_prach_root_sequence(129)


@no_inline
def _workload_lte_prach_unrestricted_cyclic_shift() raises -> Int:
    return lte_prach_unrestricted_cyclic_shift(4, 13)


@no_inline
def _workload_lte_prach_format0_sequence() raises -> List[Complex64]:
    return lte_prach_format0_sequence(129, 4, 13)


@no_inline
def _workload_lte_prach_format0_normalized_waveform(
    sequence: Span[Complex64, ...],
) raises -> List[Complex64]:
    return lte_prach_format0_normalized_waveform(sequence)


@no_inline
def _workload_lte_detect_prach_format0(
    waveform: Span[Complex64, ...],
) raises -> LTEPRACHDetection:
    return lte_detect_prach_format0(waveform, 129, 13, 8)


@no_inline
def _workload_lte_pdsch_map_siso(
    symbols: Span[Complex64, ...], mask: Span[UInt8, ...],
) raises -> List[Complex64]:
    return lte_pdsch_map_siso(symbols, 6, mask)


@no_inline
def _workload_lte_pdsch_extract_siso(
    grid: Span[Complex64, ...], mask: Span[UInt8, ...],
) raises -> List[Complex64]:
    return lte_pdsch_extract_siso(grid, 6, mask)


@no_inline
def _workload_lte_pusch_map_siso(
    symbols: Span[Complex64, ...],
) raises -> List[Complex64]:
    return lte_pusch_map_siso(symbols, 6, 2, 2)


@no_inline
def _workload_lte_pusch_extract_siso(
    grid: Span[Complex64, ...],
) raises -> List[Complex64]:
    return lte_pusch_extract_siso(grid, 6, 2, 2)


def _uplink_sequence_workload() raises -> UInt64:
    var bits = List[UInt8](capacity=256)
    for index in range(256):
        bits.append(UInt8((index * 5 + index // 3) & 1))
    var checksum = UInt64(14695981039346656037)
    for operation in range(_UPLINK_OPERATIONS):
        var c_init = _workload_lte_pusch_scrambling_c_init()
        var scrambled = _workload_lte_pusch_scramble(Span(bits))
        var base = _workload_lte_pusch_dmrs_base_sequence()
        var dmrs = _workload_lte_pusch_dmrs_sequence()
        checksum = _mix(checksum, Int(c_init))
        checksum = _mix(checksum, Int(scrambled[operation % 256]))
        checksum = _mix(
            checksum, Int(abs(base[operation % 36].re) * 1000000.0)
        )
        checksum = _mix(
            checksum, Int(abs(dmrs[operation % 36].im) * 1000000.0)
        )
        keep(scrambled)
        keep(base)
        keep(dmrs)
    return checksum


def _prach_workload() raises -> UInt64:
    var checksum = UInt64(14695981039346656037)
    var root = _workload_lte_prach_root_sequence()
    var shift = _workload_lte_prach_unrestricted_cyclic_shift()
    var preamble = _workload_lte_prach_format0_sequence()
    var waveform = _workload_lte_prach_format0_normalized_waveform(Span(preamble))
    var detection = _workload_lte_detect_prach_format0(Span(waveform))
    checksum = _mix(checksum, shift)
    checksum = _mix(checksum, len(waveform))
    checksum = _mix(checksum, detection.preamble_index)
    checksum = _mix(checksum, Int(detection.metric * 1000000.0))
    checksum = _mix(checksum, Int(abs(root[17].re) * 1000000.0))
    keep(root)
    keep(preamble)
    keep(waveform)
    return checksum


def _mapping_workload() raises -> UInt64:
    var mask = List[UInt8](length=14 * 12 * 6, fill=UInt8(0))
    var pdsch_symbols = List[Complex64]()
    for index in range(len(mask)):
        if index % 17 == 0:
            mask[index] = 1
            pdsch_symbols.append(Complex64(
                Float64(index % 13) - 6.0,
                Float64(index % 11) - 5.0,
            ))
    var pusch_symbols = List[Complex64](capacity=288)
    for index in range(288):
        pusch_symbols.append(Complex64(
            Float64(index % 17) - 8.0,
            Float64(index % 19) - 9.0,
        ))
    var checksum = UInt64(14695981039346656037)
    for operation in range(_MAPPING_OPERATIONS):
        pdsch_symbols[operation % len(pdsch_symbols)] = Complex64(
            pdsch_symbols[operation % len(pdsch_symbols)].re + 0.03125,
            pdsch_symbols[operation % len(pdsch_symbols)].im - 0.015625,
        )
        pusch_symbols[operation % len(pusch_symbols)] = Complex64(
            pusch_symbols[operation % len(pusch_symbols)].re + 0.0625,
            pusch_symbols[operation % len(pusch_symbols)].im - 0.03125,
        )
        var downlink_grid = _workload_lte_pdsch_map_siso(Span(pdsch_symbols), Span(mask))
        var downlink_restored = _workload_lte_pdsch_extract_siso(Span(downlink_grid), Span(mask))
        var uplink_grid = _workload_lte_pusch_map_siso(Span(pusch_symbols))
        var uplink_restored = _workload_lte_pusch_extract_siso(Span(uplink_grid))
        checksum = _mix(
            checksum,
            Int(abs(downlink_restored[operation % len(downlink_restored)].re) * 1000.0),
        )
        checksum = _mix(
            checksum,
            Int(abs(uplink_restored[operation % len(uplink_restored)].im) * 1000.0),
        )
        keep(downlink_grid)
        keep(uplink_grid)
    return checksum


def _selected_workload(family: Int) raises -> UInt64:
    if family == 0:
        return _uplink_sequence_workload()
    if family == 1:
        return _prach_workload()
    if family == 2:
        return _mapping_workload()
    raise Error("unknown LTE waveform benchmark family")


def _benchmark_family(
    family: Int,
    name: StringSlice,
    operations: Int,
    denominator: StringSlice,
) raises -> UInt64:
    for _ in range(_WARMUP):
        keep(_selected_workload(family))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(0)
    for sample in range(_SAMPLES):
        var start = global_perf_counter_ns()
        var one_checksum = _selected_workload(family)
        samples.append(global_perf_counter_ns() - start)
        keep(one_checksum)
        checksum ^= one_checksum + UInt64(sample)
    report_timing_samples(
        name,
        samples,
        _WARMUP,
        operations,
        denominator_unit=denominator,
    )
    return checksum


def main() raises:
    print_benchmark_metadata()
    print("lte_waveform_standard_baseline:", "3GPP-TS-36.211-V18.0.2")
    print("lte_waveform_profile:", "FDD-normal-CP-SISO-CPU-reference")
    print("lte_prach_radio_rate_frequency_placement_in_scope:", False)
    print("lte_scheduler_control_and_multilayer_in_scope:", False)
    print("timing_scope_includes_output_allocation:", True)
    var bits = List[UInt8](length=256, fill=UInt8(0))
    for index in range(256):
        bits[index] = UInt8((index * 5 + index // 3) & 1)
    var preamble = _workload_lte_prach_format0_sequence()
    var waveform = _workload_lte_prach_format0_normalized_waveform(Span(preamble))
    var mask = List[UInt8](length=14 * 12 * 6, fill=UInt8(0))
    var pdsch_symbols = List[Complex64]()
    for index in range(len(mask)):
        if index % 17 == 0:
            mask[index] = 1
            pdsch_symbols.append(Complex64(Float64(index % 13), Float64(index % 11)))
    var pusch_symbols = List[Complex64](length=288, fill=Complex64(1.0, -1.0))
    var downlink_grid = _workload_lte_pdsch_map_siso(Span(pdsch_symbols), Span(mask))
    var uplink_grid = _workload_lte_pusch_map_siso(Span(pusch_symbols))
    for _ in range(_WARMUP):
        keep(_workload_lte_pusch_scrambling_c_init())
        keep(_workload_lte_pusch_scramble(Span(bits)))
        keep(_workload_lte_pusch_dmrs_base_sequence())
        keep(_workload_lte_pusch_dmrs_sequence())
        keep(_workload_lte_prach_root_sequence())
        keep(_workload_lte_prach_unrestricted_cyclic_shift())
        keep(_workload_lte_prach_format0_sequence())
        keep(_workload_lte_prach_format0_normalized_waveform(Span(preamble)))
        keep(_workload_lte_detect_prach_format0(Span(waveform)))
        keep(_workload_lte_pdsch_map_siso(Span(pdsch_symbols), Span(mask)))
        keep(_workload_lte_pdsch_extract_siso(Span(downlink_grid), Span(mask)))
        keep(_workload_lte_pusch_map_siso(Span(pusch_symbols)))
        keep(_workload_lte_pusch_extract_siso(Span(uplink_grid)))
    var s0 = List[UInt64](capacity=_SAMPLES)
    var s1 = List[UInt64](capacity=_SAMPLES)
    var s2 = List[UInt64](capacity=_SAMPLES)
    var s3 = List[UInt64](capacity=_SAMPLES)
    var s4 = List[UInt64](capacity=_SAMPLES)
    var s5 = List[UInt64](capacity=_SAMPLES)
    var s6 = List[UInt64](capacity=_SAMPLES)
    var s7 = List[UInt64](capacity=_SAMPLES)
    var s8 = List[UInt64](capacity=_SAMPLES)
    var s9 = List[UInt64](capacity=_SAMPLES)
    var s10 = List[UInt64](capacity=_SAMPLES)
    var s11 = List[UInt64](capacity=_SAMPLES)
    var s12 = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(14695981039346656037)
    for _ in range(_SAMPLES):
        var start = global_perf_counter_ns()
        var r0 = _workload_lte_pusch_scrambling_c_init()
        s0.append(global_perf_counter_ns() - start)
        keep(r0); checksum = _mix(checksum, Int(r0))
        start = global_perf_counter_ns()
        var r1 = _workload_lte_pusch_scramble(Span(bits))
        s1.append(global_perf_counter_ns() - start)
        keep(r1); checksum = _mix(checksum, len(r1) + Int(r1[0]))
        start = global_perf_counter_ns()
        var r2 = _workload_lte_pusch_dmrs_base_sequence()
        s2.append(global_perf_counter_ns() - start)
        keep(r2); checksum = _mix(checksum, len(r2) + Int(abs(r2[0].re) * 1000.0))
        start = global_perf_counter_ns()
        var r3 = _workload_lte_pusch_dmrs_sequence()
        s3.append(global_perf_counter_ns() - start)
        keep(r3); checksum = _mix(checksum, len(r3) + Int(abs(r3[0].re) * 1000.0))
        start = global_perf_counter_ns()
        var r4 = _workload_lte_prach_root_sequence()
        s4.append(global_perf_counter_ns() - start)
        keep(r4); checksum = _mix(checksum, len(r4))
        start = global_perf_counter_ns()
        var r5 = _workload_lte_prach_unrestricted_cyclic_shift()
        s5.append(global_perf_counter_ns() - start)
        keep(r5); checksum = _mix(checksum, r5)
        start = global_perf_counter_ns()
        var r6 = _workload_lte_prach_format0_sequence()
        s6.append(global_perf_counter_ns() - start)
        keep(r6); checksum = _mix(checksum, len(r6))
        start = global_perf_counter_ns()
        var r7 = _workload_lte_prach_format0_normalized_waveform(Span(preamble))
        s7.append(global_perf_counter_ns() - start)
        keep(r7); checksum = _mix(checksum, len(r7))
        start = global_perf_counter_ns()
        var r8 = _workload_lte_detect_prach_format0(Span(waveform))
        s8.append(global_perf_counter_ns() - start)
        keep(r8); checksum = _mix(checksum, r8.preamble_index)
        start = global_perf_counter_ns()
        var r9 = _workload_lte_pdsch_map_siso(Span(pdsch_symbols), Span(mask))
        s9.append(global_perf_counter_ns() - start)
        keep(r9); checksum = _mix(checksum, len(r9))
        start = global_perf_counter_ns()
        var r10 = _workload_lte_pdsch_extract_siso(Span(downlink_grid), Span(mask))
        s10.append(global_perf_counter_ns() - start)
        keep(r10); checksum = _mix(checksum, len(r10))
        start = global_perf_counter_ns()
        var r11 = _workload_lte_pusch_map_siso(Span(pusch_symbols))
        s11.append(global_perf_counter_ns() - start)
        keep(r11); checksum = _mix(checksum, len(r11))
        start = global_perf_counter_ns()
        var r12 = _workload_lte_pusch_extract_siso(Span(uplink_grid))
        s12.append(global_perf_counter_ns() - start)
        keep(r12); checksum = _mix(checksum, len(r12))
    report_timing_samples("lte_pusch_scrambling_c_init", s0, _WARMUP, 1, "api_call")
    report_timing_samples("lte_pusch_scramble", s1, _WARMUP, 1, "api_call")
    report_timing_samples("lte_pusch_dmrs_base_sequence", s2, _WARMUP, 1, "api_call")
    report_timing_samples("lte_pusch_dmrs_sequence", s3, _WARMUP, 1, "api_call")
    report_timing_samples("lte_prach_root_sequence", s4, _WARMUP, 1, "api_call")
    report_timing_samples("lte_prach_unrestricted_cyclic_shift", s5, _WARMUP, 1, "api_call")
    report_timing_samples("lte_prach_format0_sequence", s6, _WARMUP, 1, "api_call")
    report_timing_samples("lte_prach_format0_normalized_waveform", s7, _WARMUP, 1, "api_call")
    report_timing_samples("lte_detect_prach_format0", s8, _WARMUP, 1, "api_call")
    report_timing_samples("lte_pdsch_map_siso", s9, _WARMUP, 1, "api_call")
    report_timing_samples("lte_pdsch_extract_siso", s10, _WARMUP, 1, "api_call")
    report_timing_samples("lte_pusch_map_siso", s11, _WARMUP, 1, "api_call")
    report_timing_samples("lte_pusch_extract_siso", s12, _WARMUP, 1, "api_call")
    keep(checksum)
    print("lte_waveform_retained_checksum:", checksum)
