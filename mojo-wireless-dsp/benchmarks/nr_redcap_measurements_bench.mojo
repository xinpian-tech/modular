"""Strict attributable timings for Rel-17 RedCap measurements."""

from std.benchmark import keep
from std.collections import Span
from std.time import global_perf_counter_ns
from wireless_dsp.benchmarking import (
    print_benchmark_metadata,
    report_timing_samples,
)
from wireless_dsp.core import Complex64
from wireless_dsp.wireless.nr.redcap import (
    NR_FREQUENCY_RANGE_FR1,
    NRRedCapRel17Capabilities,
)
from wireless_dsp.wireless.nr.redcap_measurements import (
    nr_redcap_rel17_ssb_measurement_source,
    nr_redcap_rel17_ss_linear_measurements,
    nr_redcap_rel17_csi_linear_measurements,
)


comptime _WARMUPS = 3
comptime _SAMPLES = 9
comptime _SEED = UInt64(1469598103934665603)


def _mix(checksum: UInt64, value: UInt64) -> UInt64:
    return (checksum ^ value) * UInt64(1099511628211)


def _float_fingerprint(value: Float64) -> UInt64:
    return _mix(
        UInt64(Int(abs(value) * 1.0e9)),
        UInt64(1 if value < 0.0 else 0),
    )


def _run[
    workload: def() thin raises -> Tuple[UInt64, UInt64]
](name: StringSlice) raises -> UInt64:
    var first = workload()
    var second = workload()
    if first[1] != second[1]:
        raise Error("RedCap measurement benchmark is nondeterministic")
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


def _capabilities() raises -> NRRedCapRel17Capabilities:
    return NRRedCapRel17Capabilities(
        NR_FREQUENCY_RANGE_FR1, 20.0, 1, 1
    )


def _sss() -> List[Complex64]:
    return [
        Complex64(1.0, 0.25),
        Complex64(-0.5, 0.75),
        Complex64(0.25, -1.0),
        Complex64(-0.75, -0.5),
    ]


def _measured() -> List[Complex64]:
    return [
        Complex64(1.0, 0.0),
        Complex64(0.0, 1.0),
        Complex64(-1.0, 0.0),
        Complex64(0.0, -1.0),
        Complex64(0.5, 0.5),
        Complex64(-0.5, 0.5),
        Complex64(-0.5, -0.5),
        Complex64(0.5, -0.5),
    ]


def _interference() -> List[Complex64]:
    return [
        Complex64(0.25, 0.0),
        Complex64(0.0, -0.25),
        Complex64(-0.125, 0.125),
        Complex64(0.125, -0.125),
    ]


@no_inline
def _source_workload() raises -> Tuple[UInt64, UInt64]:
    var capabilities = _capabilities()
    var start = global_perf_counter_ns()
    var result = nr_redcap_rel17_ssb_measurement_source(
        capabilities, has_cd_ssb=True, has_ncd_ssb=False
    )
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, UInt64(result + 1))


@no_inline
def _ss_measurement_workload() raises -> Tuple[UInt64, UInt64]:
    var capabilities = _capabilities()
    var sss = _sss()
    var measured = _measured()
    var interference = _interference()
    var sss_span = Span(sss)
    var measured_span = Span(measured)
    var interference_span = Span(interference)
    var start = global_perf_counter_ns()
    var result = nr_redcap_rel17_ss_linear_measurements(
        capabilities,
        sss_span,
        measured_span,
        interference_span,
        24,
        2,
        has_cd_ssb=True,
        has_ncd_ssb=False,
    )
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _float_fingerprint(result.rsrp)
    fingerprint = _mix(fingerprint, _float_fingerprint(result.rsrq))
    fingerprint = _mix(fingerprint, _float_fingerprint(result.sinr))
    fingerprint = _mix(fingerprint, _float_fingerprint(result.rssi))
    return (elapsed, fingerprint)


@no_inline
def _csi_measurement_workload() raises -> Tuple[UInt64, UInt64]:
    var capabilities = _capabilities()
    var csi = _sss()
    var measured = _measured()
    var interference = _interference()
    var csi_span = Span(csi)
    var measured_span = Span(measured)
    var interference_span = Span(interference)
    var start = global_perf_counter_ns()
    var result = nr_redcap_rel17_csi_linear_measurements(
        capabilities,
        csi_span,
        measured_span,
        interference_span,
        24,
        2,
    )
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _float_fingerprint(result.rsrp)
    fingerprint = _mix(fingerprint, _float_fingerprint(result.rsrq))
    fingerprint = _mix(fingerprint, _float_fingerprint(result.sinr))
    fingerprint = _mix(fingerprint, _float_fingerprint(result.rssi))
    return (elapsed, fingerprint)


def main() raises:
    print_benchmark_metadata()
    print("nr_redcap_measurement_backend:", "scalar-cpu-reference")
    print("nr_redcap_measurement_baseline:", "TS-38.215-V17.5.0")
    var checksum = _SEED
    checksum = _mix(
        checksum,
        _run[_source_workload]("nr_redcap_rel17_ssb_measurement_source"),
    )
    checksum = _mix(
        checksum,
        _run[_ss_measurement_workload](
            "nr_redcap_rel17_ss_linear_measurements"
        ),
    )
    checksum = _mix(
        checksum,
        _run[_csi_measurement_workload](
            "nr_redcap_rel17_csi_linear_measurements"
        ),
    )
    keep(checksum)
    print("nr_redcap_measurement_retained_checksum:", checksum)
