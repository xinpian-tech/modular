"""Strict per-API timings for bounded Rel-17 NR FR2-2/n263."""

from std.benchmark import keep
from std.time import global_perf_counter_ns
from wireless_dsp.benchmarking import (
    print_benchmark_metadata,
    report_timing_samples,
)
from wireless_dsp.wireless.nr.fr2_2_rel17 import (
    NRFR22Rel17CarrierConfig,
    NRFR22Rel17Numerology,
    NRFR22Rel17PRACHAllocation,
    nr_fr2_2_rel17_carrier_config,
    nr_fr2_2_rel17_elapsed_slot_start_ns,
    nr_fr2_2_rel17_frequency_in_n263_mhz,
    nr_fr2_2_rel17_minimum_guardband_khz,
    nr_fr2_2_rel17_n263_2000mhz_exception_arfcn,
    nr_fr2_2_rel17_n263_arfcn_supported,
    nr_fr2_2_rel17_n263_center_frequency_hz,
    nr_fr2_2_rel17_n263_regular_arfcn,
    nr_fr2_2_rel17_n263_regular_arfcn_count,
    nr_fr2_2_rel17_nominal_channel_spacing_100khz,
    nr_fr2_2_rel17_numerology,
    nr_fr2_2_rel17_occupied_bandwidth_khz,
    nr_fr2_2_rel17_prach_allocation,
    nr_fr2_2_rel17_prach_allocation_subcarriers,
    nr_fr2_2_rel17_symbol_ordinal,
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
        raise Error("FR2-2 benchmark is nondeterministic")
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


def _numerology_fixture(scs_khz: Int) raises -> NRFR22Rel17Numerology:
    return nr_fr2_2_rel17_numerology(scs_khz)


def _carrier_fixture(
    scs_khz: Int, bandwidth_mhz: Int
) raises -> NRFR22Rel17CarrierConfig:
    return nr_fr2_2_rel17_carrier_config(scs_khz, bandwidth_mhz)


def _prach_fixture() raises -> NRFR22Rel17PRACHAllocation:
    return nr_fr2_2_rel17_prach_allocation(960, 480)


@no_inline
def _numerology_workload() raises -> Tuple[UInt64, UInt64]:
    var scs_khz = 480
    var start = global_perf_counter_ns()
    var result = nr_fr2_2_rel17_numerology(scs_khz)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = UInt64(result.mu)
    fingerprint = _mix(fingerprint, UInt64(result.slots_per_frame))
    fingerprint = _mix(fingerprint, UInt64(result.slot_duration_ns))
    return (elapsed, fingerprint)


@no_inline
def _elapsed_slot_workload() raises -> Tuple[UInt64, UInt64]:
    var numerology = _numerology_fixture(480)
    var frame = 123
    var slot = 17
    var start = global_perf_counter_ns()
    var result = nr_fr2_2_rel17_elapsed_slot_start_ns(
        numerology, frame, slot
    )
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, UInt64(result))


@no_inline
def _symbol_ordinal_workload() raises -> Tuple[UInt64, UInt64]:
    var numerology = _numerology_fixture(960)
    var frame = 123
    var slot = 17
    var symbol = 9
    var start = global_perf_counter_ns()
    var result = nr_fr2_2_rel17_symbol_ordinal(
        numerology, frame, slot, symbol
    )
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, UInt64(result))


@no_inline
def _carrier_config_workload() raises -> Tuple[UInt64, UInt64]:
    var scs_khz = 960
    var bandwidth_mhz = 800
    var start = global_perf_counter_ns()
    var result = nr_fr2_2_rel17_carrier_config(
        scs_khz, bandwidth_mhz
    )
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = UInt64(result.maximum_resource_blocks)
    fingerprint = _mix(
        fingerprint, UInt64(result.minimum_guardband_khz)
    )
    fingerprint = _mix(
        fingerprint,
        UInt64(1 if result.optional_subcarrier_spacing else 0),
    )
    return (elapsed, fingerprint)


@no_inline
def _occupied_bandwidth_workload() raises -> Tuple[UInt64, UInt64]:
    var config = _carrier_fixture(960, 800)
    var start = global_perf_counter_ns()
    var result = nr_fr2_2_rel17_occupied_bandwidth_khz(config)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, UInt64(result))


@no_inline
def _minimum_guardband_workload() raises -> Tuple[UInt64, UInt64]:
    var config = _carrier_fixture(480, 1600)
    var start = global_perf_counter_ns()
    var result = nr_fr2_2_rel17_minimum_guardband_khz(config)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, UInt64(result))


@no_inline
def _channel_spacing_workload() raises -> Tuple[UInt64, UInt64]:
    var first = _carrier_fixture(480, 400)
    var second = _carrier_fixture(960, 800)
    var start = global_perf_counter_ns()
    var result = nr_fr2_2_rel17_nominal_channel_spacing_100khz(
        first, second
    )
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, UInt64(result))


@no_inline
def _prach_allocation_workload() raises -> Tuple[UInt64, UInt64]:
    var prach_scs_khz = 960
    var pusch_scs_khz = 480
    var start = global_perf_counter_ns()
    var result = nr_fr2_2_rel17_prach_allocation(
        prach_scs_khz, pusch_scs_khz
    )
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = UInt64(result.pusch_allocation_resource_blocks)
    fingerprint = _mix(fingerprint, UInt64(result.k_bar))
    return (elapsed, fingerprint)


@no_inline
def _prach_subcarriers_workload() raises -> Tuple[UInt64, UInt64]:
    var allocation = _prach_fixture()
    var start = global_perf_counter_ns()
    var result = nr_fr2_2_rel17_prach_allocation_subcarriers(allocation)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, UInt64(result))


@no_inline
def _regular_arfcn_count_workload() raises -> Tuple[UInt64, UInt64]:
    var bandwidth_mhz = 800
    var start = global_perf_counter_ns()
    var result = nr_fr2_2_rel17_n263_regular_arfcn_count(bandwidth_mhz)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, UInt64(result))


@no_inline
def _regular_arfcn_workload() raises -> Tuple[UInt64, UInt64]:
    var bandwidth_mhz = 800
    var index = 17
    var start = global_perf_counter_ns()
    var result = nr_fr2_2_rel17_n263_regular_arfcn(
        bandwidth_mhz, index
    )
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, UInt64(result))


@no_inline
def _exception_arfcn_workload() raises -> Tuple[UInt64, UInt64]:
    var index = 2
    var start = global_perf_counter_ns()
    var result = nr_fr2_2_rel17_n263_2000mhz_exception_arfcn(index)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, UInt64(result))


@no_inline
def _arfcn_supported_workload() raises -> Tuple[UInt64, UInt64]:
    var bandwidth_mhz = 800
    var arfcn = 2569963 + 6720 * 17
    var start = global_perf_counter_ns()
    var result = nr_fr2_2_rel17_n263_arfcn_supported(
        bandwidth_mhz, arfcn
    )
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, UInt64(1 if result else 0))


@no_inline
def _center_frequency_workload() raises -> Tuple[UInt64, UInt64]:
    var bandwidth_mhz = 800
    var arfcn = 2569963 + 6720 * 17
    var start = global_perf_counter_ns()
    var result = nr_fr2_2_rel17_n263_center_frequency_hz(
        bandwidth_mhz, arfcn
    )
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, UInt64(result))


@no_inline
def _frequency_membership_workload() raises -> Tuple[UInt64, UInt64]:
    var frequency_mhz = 64000.0
    var start = global_perf_counter_ns()
    var result = nr_fr2_2_rel17_frequency_in_n263_mhz(frequency_mhz)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, UInt64(1 if result else 0))


def main() raises:
    print_benchmark_metadata()
    print("nr_fr2_2_rel17_backend:", "scalar-cpu-reference")
    print(
        "nr_fr2_2_rel17_baseline:",
        "TS-38.211-V17.10.0+38.101-2-V17.20.0+38.104-V17.22.0",
    )
    var checksum = _SEED
    checksum = _mix(
        checksum,
        _run[_numerology_workload]("nr_fr2_2_rel17_numerology"),
    )
    checksum = _mix(
        checksum,
        _run[_elapsed_slot_workload](
            "nr_fr2_2_rel17_elapsed_slot_start_ns"
        ),
    )
    checksum = _mix(
        checksum,
        _run[_symbol_ordinal_workload]("nr_fr2_2_rel17_symbol_ordinal"),
    )
    checksum = _mix(
        checksum,
        _run[_carrier_config_workload]("nr_fr2_2_rel17_carrier_config"),
    )
    checksum = _mix(
        checksum,
        _run[_occupied_bandwidth_workload](
            "nr_fr2_2_rel17_occupied_bandwidth_khz"
        ),
    )
    checksum = _mix(
        checksum,
        _run[_minimum_guardband_workload](
            "nr_fr2_2_rel17_minimum_guardband_khz"
        ),
    )
    checksum = _mix(
        checksum,
        _run[_channel_spacing_workload](
            "nr_fr2_2_rel17_nominal_channel_spacing_100khz"
        ),
    )
    checksum = _mix(
        checksum,
        _run[_prach_allocation_workload](
            "nr_fr2_2_rel17_prach_allocation"
        ),
    )
    checksum = _mix(
        checksum,
        _run[_prach_subcarriers_workload](
            "nr_fr2_2_rel17_prach_allocation_subcarriers"
        ),
    )
    checksum = _mix(
        checksum,
        _run[_regular_arfcn_count_workload](
            "nr_fr2_2_rel17_n263_regular_arfcn_count"
        ),
    )
    checksum = _mix(
        checksum,
        _run[_regular_arfcn_workload](
            "nr_fr2_2_rel17_n263_regular_arfcn"
        ),
    )
    checksum = _mix(
        checksum,
        _run[_exception_arfcn_workload](
            "nr_fr2_2_rel17_n263_2000mhz_exception_arfcn"
        ),
    )
    checksum = _mix(
        checksum,
        _run[_arfcn_supported_workload](
            "nr_fr2_2_rel17_n263_arfcn_supported"
        ),
    )
    checksum = _mix(
        checksum,
        _run[_center_frequency_workload](
            "nr_fr2_2_rel17_n263_center_frequency_hz"
        ),
    )
    checksum = _mix(
        checksum,
        _run[_frequency_membership_workload](
            "nr_fr2_2_rel17_frequency_in_n263_mhz"
        ),
    )
    keep(checksum)
    print("nr_fr2_2_rel17_retained_checksum:", checksum)
