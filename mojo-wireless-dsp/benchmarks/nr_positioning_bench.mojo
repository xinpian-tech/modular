"""Strict attributable timings for bounded Rel-17 NR positioning."""

from std.benchmark import keep
from std.time import global_perf_counter_ns
from wireless_dsp.benchmarking import (
    print_benchmark_metadata,
    report_timing_samples,
)
from wireless_dsp.core import Complex64
from wireless_dsp.wireless.nr.positioning import (
    NRDLPRSConfig,
    nr_dl_prs_c_init,
    nr_dl_prs_sequence,
    nr_dl_prs_frequency_offset,
    nr_dl_prs_resource,
    nr_ul_rtoa_reference_time_seconds,
    nr_ul_rtoa_seconds,
    nr_dl_rstd_seconds,
    nr_ue_rx_tx_time_difference_seconds,
    nr_gnb_rx_tx_time_difference_seconds,
)


comptime _WARMUPS = 3
comptime _SAMPLES = 9
comptime _SEED = UInt64(1469598103934665603)


def _mix(checksum: UInt64, value: UInt64) -> UInt64:
    return (checksum ^ value) * UInt64(1099511628211)


def _float_fingerprint(value: Float64) -> UInt64:
    return _mix(
        UInt64(Int(abs(value) * 1.0e12)),
        UInt64(1 if value < 0.0 else 0),
    )


def _complex_fingerprint(value: Complex64) -> UInt64:
    return _mix(
        _float_fingerprint(value.re), _float_fingerprint(value.im)
    )


def _run[
    workload: def() thin raises -> Tuple[UInt64, UInt64]
](name: StringSlice) raises -> UInt64:
    var first = workload()
    var second = workload()
    if first[1] != second[1]:
        raise Error("NR positioning benchmark is nondeterministic")
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


@no_inline
def _c_init_workload() raises -> Tuple[UInt64, UInt64]:
    var resource_id = 1729
    var numerology = 2
    var slot = 17
    var symbol = 9
    var start = global_perf_counter_ns()
    var result = nr_dl_prs_c_init(
        resource_id, numerology, slot, symbol
    )
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, UInt64(result))


@no_inline
def _sequence_workload() raises -> Tuple[UInt64, UInt64]:
    var resource_id = 1729
    var numerology = 2
    var slot = 17
    var symbol = 9
    var sequence_length = 96
    var start = global_perf_counter_ns()
    var result = nr_dl_prs_sequence(
        resource_id, numerology, slot, symbol, sequence_length
    )
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = UInt64(len(result))
    fingerprint = _mix(fingerprint, _complex_fingerprint(result[0]))
    fingerprint = _mix(
        fingerprint, _complex_fingerprint(result[len(result) - 1])
    )
    return (elapsed, fingerprint)


@no_inline
def _frequency_offset_workload() raises -> Tuple[UInt64, UInt64]:
    var comb_size = 4
    var resource_element_offset = 7
    var start = global_perf_counter_ns()
    var result = nr_dl_prs_frequency_offset(
        comb_size, resource_element_offset
    )
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, UInt64(result + 1))


@no_inline
def _mapping_workload() raises -> Tuple[UInt64, UInt64]:
    var config = NRDLPRSConfig(
        1729, 2, 17, 13, 24, 4, 1, 2, 4
    )
    var amplitude = 1.25
    var start = global_perf_counter_ns()
    var result = nr_dl_prs_resource(config, amplitude)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = UInt64(len(result.values))
    fingerprint = _mix(fingerprint, UInt64(result.symbols[0]))
    fingerprint = _mix(fingerprint, UInt64(result.subcarriers[0]))
    fingerprint = _mix(
        fingerprint, _complex_fingerprint(result.values[0])
    )
    return (elapsed, fingerprint)


@no_inline
def _ul_rtoa_reference_time_workload() raises -> Tuple[UInt64, UInt64]:
    var frame_start_seconds = 1000.0
    var frame = 37
    var subframe = 6
    var start = global_perf_counter_ns()
    var result = nr_ul_rtoa_reference_time_seconds(
        frame_start_seconds, frame, subframe
    )
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, _float_fingerprint(result))


@no_inline
def _ul_rtoa_workload() raises -> Tuple[UInt64, UInt64]:
    var measured_time_seconds = 1000.376000123
    var frame_start_seconds = 1000.0
    var frame = 37
    var subframe = 6
    var start = global_perf_counter_ns()
    var result = nr_ul_rtoa_seconds(
        measured_time_seconds, frame_start_seconds, frame, subframe
    )
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, _float_fingerprint(result))


@no_inline
def _dl_rstd_workload() raises -> Tuple[UInt64, UInt64]:
    var neighbour_time_seconds = 2.000000123
    var reference_time_seconds = 1.999999877
    var start = global_perf_counter_ns()
    var result = nr_dl_rstd_seconds(
        neighbour_time_seconds, reference_time_seconds
    )
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, _float_fingerprint(result))


@no_inline
def _ue_rx_tx_workload() raises -> Tuple[UInt64, UInt64]:
    var receive_time_seconds = 3.000000123
    var transmit_time_seconds = 2.999999877
    var start = global_perf_counter_ns()
    var result = nr_ue_rx_tx_time_difference_seconds(
        receive_time_seconds, transmit_time_seconds
    )
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, _float_fingerprint(result))


@no_inline
def _gnb_rx_tx_workload() raises -> Tuple[UInt64, UInt64]:
    var receive_time_seconds = 4.000000123
    var transmit_time_seconds = 3.999999877
    var start = global_perf_counter_ns()
    var result = nr_gnb_rx_tx_time_difference_seconds(
        receive_time_seconds, transmit_time_seconds
    )
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, _float_fingerprint(result))


def _timing_workload() raises -> UInt64:
    var checksum = _SEED
    checksum = _mix(
        checksum,
        _run[_ul_rtoa_reference_time_workload](
            "nr_ul_rtoa_reference_time_seconds"
        ),
    )
    checksum = _mix(
        checksum, _run[_ul_rtoa_workload]("nr_ul_rtoa_seconds")
    )
    checksum = _mix(
        checksum, _run[_dl_rstd_workload]("nr_dl_rstd_seconds")
    )
    checksum = _mix(
        checksum,
        _run[_ue_rx_tx_workload](
            "nr_ue_rx_tx_time_difference_seconds"
        ),
    )
    checksum = _mix(
        checksum,
        _run[_gnb_rx_tx_workload](
            "nr_gnb_rx_tx_time_difference_seconds"
        ),
    )
    return checksum


def main() raises:
    print_benchmark_metadata()
    print("nr_positioning_backend:", "scalar-cpu-reference")
    print(
        "nr_positioning_rel17_baselines:",
        "TS-38.211-V17.10.0/TS-38.214-V17.16.0/TS-38.215-V17.5.0",
    )
    var checksum = _SEED
    checksum = _mix(
        checksum, _run[_c_init_workload]("nr_dl_prs_c_init")
    )
    checksum = _mix(
        checksum, _run[_sequence_workload]("nr_dl_prs_sequence")
    )
    checksum = _mix(
        checksum,
        _run[_frequency_offset_workload]("nr_dl_prs_frequency_offset"),
    )
    checksum = _mix(
        checksum, _run[_mapping_workload]("nr_dl_prs_resource")
    )
    checksum = _mix(checksum, _timing_workload())
    keep(checksum)
    print("nr_positioning_retained_checksum:", checksum)
