"""CPU benchmarks for exact LTE non-eDRX serving-cell RRM arithmetic."""

from std.benchmark import black_box, keep
from std.time import global_perf_counter_ns
from wireless_dsp.benchmarking import (
    print_benchmark_metadata,
    report_timing_samples,
)
from wireless_dsp.wireless.lte import (
    LTERRMServingCellConfig,
    lte_rrm_serving_cell_nserv,
    lte_rrm_minimum_filter_spacing_ms,
    lte_rrm_all_neighbour_measurements_required,
)


comptime _WARMUPS = 3
comptime _SAMPLES = 9
comptime _OPERATIONS = 8192
comptime _EXPECTED_RETAINED_CHECKSUM = UInt64(6833888695599283730)


def _mix(checksum: UInt64, value: UInt64) -> UInt64:
    return (checksum ^ value) * UInt64(1099511628211)


@no_inline
def _nserv_workload(
    config: LTERRMServingCellConfig,
) raises -> Int:
    var value = 0
    for _ in range(_OPERATIONS):
        value = lte_rrm_serving_cell_nserv(black_box(config))
    return value


@no_inline
def _filter_spacing_workload(
    config: LTERRMServingCellConfig,
) raises -> Int:
    var value = 0
    for _ in range(_OPERATIONS):
        value = lte_rrm_minimum_filter_spacing_ms(black_box(config))
    return value


@no_inline
def _neighbour_trigger_workload(
    config: LTERRMServingCellConfig,
    failed_count: Int,
) raises -> Bool:
    var value = False
    for _ in range(_OPERATIONS):
        value = lte_rrm_all_neighbour_measurements_required(
            black_box(config),
            black_box(failed_count),
        )
    return value


def main() raises:
    var nserv_config = LTERRMServingCellConfig(320)
    var spacing_config = LTERRMServingCellConfig(2560)
    var trigger_config = LTERRMServingCellConfig(640)
    var failed_count = 4

    var check_a = _nserv_workload(nserv_config)
    var check_b = _nserv_workload(nserv_config)
    if check_a != check_b:
        raise Error("LTE RRM Nserv workload is nondeterministic")
    check_a = _filter_spacing_workload(spacing_config)
    check_b = _filter_spacing_workload(spacing_config)
    if check_a != check_b:
        raise Error("LTE RRM spacing workload is nondeterministic")
    var trigger_check_a = _neighbour_trigger_workload(
        trigger_config, failed_count
    )
    var trigger_check_b = _neighbour_trigger_workload(
        trigger_config, failed_count
    )
    if trigger_check_a != trigger_check_b:
        raise Error("LTE RRM trigger workload is nondeterministic")

    for _ in range(_WARMUPS):
        keep(_nserv_workload(nserv_config))
        keep(_filter_spacing_workload(spacing_config))
        keep(_neighbour_trigger_workload(trigger_config, failed_count))

    var nserv_samples = List[UInt64](capacity=_SAMPLES)
    var spacing_samples = List[UInt64](capacity=_SAMPLES)
    var trigger_samples = List[UInt64](capacity=_SAMPLES)
    var retained_checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var start = global_perf_counter_ns()
        var value = _nserv_workload(nserv_config)
        var stop = global_perf_counter_ns()
        keep(value)
        nserv_samples.append(stop - start)
        retained_checksum = _mix(retained_checksum, UInt64(value))

        start = global_perf_counter_ns()
        value = _filter_spacing_workload(spacing_config)
        stop = global_perf_counter_ns()
        keep(value)
        spacing_samples.append(stop - start)
        retained_checksum = _mix(retained_checksum, UInt64(value))

        start = global_perf_counter_ns()
        var trigger_value = _neighbour_trigger_workload(
            trigger_config, failed_count
        )
        stop = global_perf_counter_ns()
        keep(trigger_value)
        trigger_samples.append(stop - start)
        retained_checksum = _mix(retained_checksum, UInt64(trigger_value))

    print_benchmark_metadata()
    print("lte_rrm_backend:", "scalar-cpu-reference")
    print("lte_rrm_baseline:", "3GPP-TS-36.133-V18.14.0-4.2.2.1")
    report_timing_samples(
        "lte_rrm_serving_cell_nserv",
        nserv_samples,
        _WARMUPS,
        _OPERATIONS,
        "table lookup",
    )
    report_timing_samples(
        "lte_rrm_minimum_filter_spacing_ms",
        spacing_samples,
        _WARMUPS,
        _OPERATIONS,
        "spacing calculation",
    )
    report_timing_samples(
        "lte_rrm_all_neighbour_measurements_required",
        trigger_samples,
        _WARMUPS,
        _OPERATIONS,
        "threshold decision",
    )
    keep(retained_checksum)
    print("lte_rrm_retained_checksum:", retained_checksum)
    if retained_checksum != _EXPECTED_RETAINED_CHECKSUM:
        raise Error("LTE RRM benchmark retained checksum changed")
