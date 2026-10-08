"""Strict attributable timings for bounded Rel-17 NR-NTN arithmetic."""

from std.benchmark import keep
from std.time import global_perf_counter_ns
from wireless_dsp.benchmarking import (
    print_benchmark_metadata,
    report_timing_samples,
)
from wireless_dsp.wireless.nr.ntn_timing import (
    NRNTNECEFStateVector,
    NRNTNRel17CommonTimingAssistance,
    nr_ntn_rel17_common_one_way_delay_seconds,
    nr_ntn_rel17_common_ta_seconds,
    nr_ntn_rel17_effective_koffset_15khz_slots,
    nr_ntn_rel17_koffset_covers_propagation,
    nr_ntn_rel17_koffset_seconds,
    nr_ntn_rel17_precompensation,
    nr_ntn_rel17_radial_velocity_mps,
    nr_ntn_rel17_service_link_doppler_shift_hz,
    nr_ntn_rel17_service_link_range_m,
    nr_ntn_rel17_service_link_rtt_seconds,
    nr_ntn_rel17_ul_sync_information_valid,
    nr_ntn_rel17_uplink_frequency_precompensation_hz,
)


comptime _WARMUPS = 3
comptime _SAMPLES = 9
comptime _SEED = UInt64(1469598103934665603)


def _mix(checksum: UInt64, value: UInt64) -> UInt64:
    return (checksum ^ value) * UInt64(1099511628211)


def _float_fingerprint(value: Float64) -> UInt64:
    return _mix(
        UInt64(Int(abs(value) * 1.0e6)),
        UInt64(1 if value < 0.0 else 0),
    )


def _run[
    workload: def() thin raises -> Tuple[UInt64, UInt64]
](name: StringSlice) raises -> UInt64:
    var first = workload()
    var second = workload()
    if first[1] != second[1]:
        raise Error("NR-NTN timing benchmark is nondeterministic")
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


def _ue_state() raises -> NRNTNECEFStateVector:
    return NRNTNECEFStateVector(
        6371000.0, 1000.0, -2000.0, 0.0, 465.0, 0.0
    )


def _satellite_state() raises -> NRNTNECEFStateVector:
    return NRNTNECEFStateVector(
        21000000.0,
        14000000.0,
        9000000.0,
        -1200.0,
        2400.0,
        800.0,
    )


def _assistance() raises -> NRNTNRel17CommonTimingAssistance:
    return NRNTNRel17CommonTimingAssistance(100000, -1000, 100, 900)


@no_inline
def _range_workload() raises -> Tuple[UInt64, UInt64]:
    var ue = _ue_state()
    var satellite = _satellite_state()
    var start = global_perf_counter_ns()
    var result = nr_ntn_rel17_service_link_range_m(ue, satellite)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, _float_fingerprint(result))


@no_inline
def _rtt_workload() raises -> Tuple[UInt64, UInt64]:
    var ue = _ue_state()
    var satellite = _satellite_state()
    var start = global_perf_counter_ns()
    var result = nr_ntn_rel17_service_link_rtt_seconds(ue, satellite)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, _float_fingerprint(result))


@no_inline
def _radial_velocity_workload() raises -> Tuple[UInt64, UInt64]:
    var ue = _ue_state()
    var satellite = _satellite_state()
    var start = global_perf_counter_ns()
    var result = nr_ntn_rel17_radial_velocity_mps(ue, satellite)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, _float_fingerprint(result))


@no_inline
def _doppler_workload() raises -> Tuple[UInt64, UInt64]:
    var ue = _ue_state()
    var satellite = _satellite_state()
    var carrier_frequency_hz = 2.0e9
    var start = global_perf_counter_ns()
    var result = nr_ntn_rel17_service_link_doppler_shift_hz(
        ue, satellite, carrier_frequency_hz
    )
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, _float_fingerprint(result))


@no_inline
def _uplink_precompensation_workload() raises -> Tuple[UInt64, UInt64]:
    var ue = _ue_state()
    var satellite = _satellite_state()
    var carrier_frequency_hz = 2.0e9
    var start = global_perf_counter_ns()
    var result = nr_ntn_rel17_uplink_frequency_precompensation_hz(
        ue, satellite, carrier_frequency_hz
    )
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, _float_fingerprint(result))


@no_inline
def _validity_workload() raises -> Tuple[UInt64, UInt64]:
    var assistance = _assistance()
    var elapsed_microseconds = 123456
    var start = global_perf_counter_ns()
    var result = nr_ntn_rel17_ul_sync_information_valid(
        assistance, elapsed_microseconds
    )
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, UInt64(1 if result else 0))


@no_inline
def _common_ta_workload() raises -> Tuple[UInt64, UInt64]:
    var assistance = _assistance()
    var elapsed_seconds = 17.0
    var start = global_perf_counter_ns()
    var result = nr_ntn_rel17_common_ta_seconds(
        assistance, elapsed_seconds
    )
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, _float_fingerprint(result))


@no_inline
def _one_way_delay_workload() raises -> Tuple[UInt64, UInt64]:
    var assistance = _assistance()
    var elapsed_seconds = 17.0
    var start = global_perf_counter_ns()
    var result = nr_ntn_rel17_common_one_way_delay_seconds(
        assistance, elapsed_seconds
    )
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, _float_fingerprint(result))


@no_inline
def _effective_koffset_workload() raises -> Tuple[UInt64, UInt64]:
    var cell_specific_koffset = 256
    var differential_koffset = 17
    var start = global_perf_counter_ns()
    var result = nr_ntn_rel17_effective_koffset_15khz_slots(
        cell_specific_koffset, differential_koffset
    )
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, UInt64(result))


@no_inline
def _koffset_seconds_workload() raises -> Tuple[UInt64, UInt64]:
    var cell_specific_koffset = 256
    var differential_koffset = 17
    var start = global_perf_counter_ns()
    var result = nr_ntn_rel17_koffset_seconds(
        cell_specific_koffset, differential_koffset
    )
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, _float_fingerprint(result))


@no_inline
def _koffset_covers_workload() raises -> Tuple[UInt64, UInt64]:
    var cell_specific_koffset = 256
    var differential_koffset = 17
    var service_link_rtt_seconds = 0.020
    var common_ta_seconds = 0.001
    var start = global_perf_counter_ns()
    var result = nr_ntn_rel17_koffset_covers_propagation(
        cell_specific_koffset,
        differential_koffset,
        service_link_rtt_seconds,
        common_ta_seconds,
    )
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, UInt64(1 if result else 0))


@no_inline
def _composition_workload() raises -> Tuple[UInt64, UInt64]:
    var ue = _ue_state()
    var satellite = _satellite_state()
    var assistance = _assistance()
    var elapsed_seconds = 17.0
    var carrier_frequency_hz = 2.0e9
    var cell_specific_koffset = 300
    var differential_koffset = 11
    var start = global_perf_counter_ns()
    var result = nr_ntn_rel17_precompensation(
        ue,
        satellite,
        assistance,
        elapsed_seconds,
        carrier_frequency_hz,
        cell_specific_koffset,
        differential_koffset,
    )
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _float_fingerprint(result.service_link_range_m)
    fingerprint = _mix(
        fingerprint,
        _float_fingerprint(result.received_doppler_shift_hz),
    )
    fingerprint = _mix(
        fingerprint, UInt64(result.effective_koffset_15khz_slots)
    )
    return (elapsed, fingerprint)


def main() raises:
    print_benchmark_metadata()
    print("nr_ntn_timing_backend:", "scalar-cpu-reference")
    print(
        "nr_ntn_timing_baseline:",
        "Rel-17-38.211-38.213-38.300-38.321-38.331",
    )
    var checksum = _SEED
    checksum = _mix(
        checksum,
        _run[_range_workload]("nr_ntn_rel17_service_link_range_m"),
    )
    checksum = _mix(
        checksum,
        _run[_rtt_workload]("nr_ntn_rel17_service_link_rtt_seconds"),
    )
    checksum = _mix(
        checksum,
        _run[_radial_velocity_workload](
            "nr_ntn_rel17_radial_velocity_mps"
        ),
    )
    checksum = _mix(
        checksum,
        _run[_doppler_workload](
            "nr_ntn_rel17_service_link_doppler_shift_hz"
        ),
    )
    checksum = _mix(
        checksum,
        _run[_uplink_precompensation_workload](
            "nr_ntn_rel17_uplink_frequency_precompensation_hz"
        ),
    )
    checksum = _mix(
        checksum,
        _run[_validity_workload](
            "nr_ntn_rel17_ul_sync_information_valid"
        ),
    )
    checksum = _mix(
        checksum,
        _run[_common_ta_workload]("nr_ntn_rel17_common_ta_seconds"),
    )
    checksum = _mix(
        checksum,
        _run[_one_way_delay_workload](
            "nr_ntn_rel17_common_one_way_delay_seconds"
        ),
    )
    checksum = _mix(
        checksum,
        _run[_effective_koffset_workload](
            "nr_ntn_rel17_effective_koffset_15khz_slots"
        ),
    )
    checksum = _mix(
        checksum,
        _run[_koffset_seconds_workload]("nr_ntn_rel17_koffset_seconds"),
    )
    checksum = _mix(
        checksum,
        _run[_koffset_covers_workload](
            "nr_ntn_rel17_koffset_covers_propagation"
        ),
    )
    checksum = _mix(
        checksum,
        _run[_composition_workload]("nr_ntn_rel17_precompensation"),
    )
    keep(checksum)
    print("nr_ntn_timing_retained_checksum:", checksum)
