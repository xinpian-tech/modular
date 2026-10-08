"""Strictly attributable Float32 CPU MIMO latency evidence.

Every ledger API has one no-inline workload and an independent report.  Each
workload performs two fixed-input checksum runs, three warmups, and nine timed
samples.  Its timed region is one direct target call with no setup or scan.
"""

from std.benchmark import keep
from std.collections import Span
from std.time import global_perf_counter_ns
from wireless_dsp.benchmarking import (
    print_benchmark_metadata,
    report_timing_samples,
)
from wireless_dsp.core import Complex32
from wireless_dsp.backend.cpu.mimo_f32 import (
    MIMOF32Workspace,
    complex_matvec_f32,
    complex_matvec_f32_into,
    make_mimo_workspace_f32,
    mimo_gram_matched_f32_into,
    mimo_mmse_f32_into,
    mimo_zf_f32_into,
)


comptime _WARMUPS = 3
comptime _SAMPLES = 9
comptime _FIXED_RUNS = 2


def _mix(checksum: UInt64, value: UInt64) -> UInt64:
    return (checksum ^ value) * UInt64(1099511628211)


def _fingerprint_float(value: Float32) -> UInt64:
    return _mix(
        UInt64(Int(abs(Float64(value)) * 1_000_000.0)),
        UInt64(1 if value < 0.0 else 0),
    )


def _fingerprint_complex_list(values: List[Complex32]) -> UInt64:
    var fingerprint = UInt64(len(values))
    if len(values) > 0:
        var first = values[0]
        var last = values[len(values) - 1]
        fingerprint = _mix(
            fingerprint,
            _mix(_fingerprint_float(first.re), _fingerprint_float(first.im)),
        )
        fingerprint = _mix(
            fingerprint,
            _mix(_fingerprint_float(last.re), _fingerprint_float(last.im)),
        )
    return fingerprint


def _fingerprint_workspace(workspace: MIMOF32Workspace) -> UInt64:
    var fingerprint = UInt64(workspace.size)
    fingerprint = _mix(fingerprint, UInt64(len(workspace.gram)))
    fingerprint = _mix(fingerprint, UInt64(len(workspace.matched)))
    return _mix(fingerprint, UInt64(len(workspace.factor)))


def _record(
    invocation: Int,
    elapsed: UInt64,
    fingerprint: UInt64,
    mut first: UInt64,
    mut samples: List[UInt64],
    mut checksum: UInt64,
) raises:
    if invocation == 0:
        first = fingerprint
    elif invocation == 1:
        if fingerprint != first:
            raise Error("fixed Float32 MIMO result is nondeterministic")
        keep(first)
        keep(fingerprint)
    elif invocation >= _FIXED_RUNS + _WARMUPS:
        samples.append(elapsed)
        checksum = _mix(checksum, fingerprint)


def _finish(
    name: StringSlice,
    mut samples: List[UInt64],
    checksum: UInt64,
) raises -> UInt64:
    report_timing_samples(name, samples, _WARMUPS, 1, "api_call")
    keep(samples)
    return checksum


@no_inline
def _workload_make_mimo_workspace_f32(size: Int) raises -> UInt64:
    var samples = List[UInt64](capacity=_SAMPLES)
    var first = UInt64(0)
    var checksum = UInt64(1469598103934665603)
    for invocation in range(_FIXED_RUNS + _WARMUPS + _SAMPLES):
        var start = global_perf_counter_ns()
        var result = make_mimo_workspace_f32(size)
        var elapsed = global_perf_counter_ns() - start
        keep(result)
        var fingerprint = _fingerprint_workspace(result)
        _record(
            invocation, elapsed, fingerprint, first, samples, checksum
        )
    return _finish("make_mimo_workspace_f32", samples, checksum)


@no_inline
def _workload_complex_matvec_f32(
    matrix: Span[Complex32, ...],
    vector: Span[Complex32, ...],
    size: Int,
) raises -> UInt64:
    var samples = List[UInt64](capacity=_SAMPLES)
    var first = UInt64(0)
    var checksum = UInt64(1469598103934665603)
    for invocation in range(_FIXED_RUNS + _WARMUPS + _SAMPLES):
        var start = global_perf_counter_ns()
        var result = complex_matvec_f32(matrix, vector, size)
        var elapsed = global_perf_counter_ns() - start
        keep(result)
        var fingerprint = _fingerprint_complex_list(result)
        _record(
            invocation, elapsed, fingerprint, first, samples, checksum
        )
    return _finish("complex_matvec_f32", samples, checksum)


@no_inline
def _workload_complex_matvec_f32_into(
    matrix: Span[Complex32, ...],
    vector: Span[Complex32, ...],
    size: Int,
    mut output: List[Complex32],
) raises -> UInt64:
    var samples = List[UInt64](capacity=_SAMPLES)
    var first = UInt64(0)
    var checksum = UInt64(1469598103934665603)
    for invocation in range(_FIXED_RUNS + _WARMUPS + _SAMPLES):
        var start = global_perf_counter_ns()
        complex_matvec_f32_into(matrix, vector, size, output)
        var elapsed = global_perf_counter_ns() - start
        keep(output)
        var fingerprint = _fingerprint_complex_list(output)
        _record(
            invocation, elapsed, fingerprint, first, samples, checksum
        )
    return _finish("complex_matvec_f32_into", samples, checksum)


@no_inline
def _workload_mimo_gram_matched_f32_into(
    channel: Span[Complex32, ...],
    observation: Span[Complex32, ...],
    size: Int,
    mut gram: List[Complex32],
    mut matched: List[Complex32],
) raises -> UInt64:
    var samples = List[UInt64](capacity=_SAMPLES)
    var first = UInt64(0)
    var checksum = UInt64(1469598103934665603)
    for invocation in range(_FIXED_RUNS + _WARMUPS + _SAMPLES):
        var start = global_perf_counter_ns()
        mimo_gram_matched_f32_into(
            channel, observation, size, gram, matched
        )
        var elapsed = global_perf_counter_ns() - start
        keep(gram)
        keep(matched)
        var fingerprint = _mix(
            _fingerprint_complex_list(gram),
            _fingerprint_complex_list(matched),
        )
        _record(
            invocation, elapsed, fingerprint, first, samples, checksum
        )
    return _finish("mimo_gram_matched_f32_into", samples, checksum)


@no_inline
def _workload_mimo_zf_f32_into(
    channel: Span[Complex32, ...],
    observation: Span[Complex32, ...],
    mut workspace: MIMOF32Workspace,
    mut output: List[Complex32],
) raises -> UInt64:
    var samples = List[UInt64](capacity=_SAMPLES)
    var first = UInt64(0)
    var checksum = UInt64(1469598103934665603)
    for invocation in range(_FIXED_RUNS + _WARMUPS + _SAMPLES):
        var start = global_perf_counter_ns()
        mimo_zf_f32_into(channel, observation, workspace, output)
        var elapsed = global_perf_counter_ns() - start
        keep(workspace)
        keep(output)
        var fingerprint = _mix(
            _fingerprint_complex_list(output),
            _fingerprint_float(workspace.last_minimum_pivot),
        )
        _record(
            invocation, elapsed, fingerprint, first, samples, checksum
        )
    return _finish("mimo_zf_f32_into", samples, checksum)


@no_inline
def _workload_mimo_mmse_f32_into(
    channel: Span[Complex32, ...],
    observation: Span[Complex32, ...],
    noise_variance: Float32,
    mut workspace: MIMOF32Workspace,
    mut output: List[Complex32],
) raises -> UInt64:
    var samples = List[UInt64](capacity=_SAMPLES)
    var first = UInt64(0)
    var checksum = UInt64(1469598103934665603)
    for invocation in range(_FIXED_RUNS + _WARMUPS + _SAMPLES):
        var start = global_perf_counter_ns()
        mimo_mmse_f32_into(
            channel, observation, noise_variance, workspace, output
        )
        var elapsed = global_perf_counter_ns() - start
        keep(workspace)
        keep(output)
        var fingerprint = _mix(
            _fingerprint_complex_list(output),
            _fingerprint_float(workspace.last_minimum_pivot),
        )
        _record(
            invocation, elapsed, fingerprint, first, samples, checksum
        )
    return _finish("mimo_mmse_f32_into", samples, checksum)


def _make_channel(size: Int) -> List[Complex32]:
    var result = List[Complex32](capacity=size * size)
    for row in range(size):
        for column in range(size):
            var real = Float32(
                0.035 * Float64(1 + (7 * row + 3 * column) % 9)
            )
            var imag = Float32(0.02 * Float64(row - column))
            if row == column:
                real += Float32(1.4 + 0.2 * Float64(row))
            result.append(Complex32(real, imag))
    return result^


def _benchmark_size(size: Int) raises:
    var channel = _make_channel(size)
    var transmitted = List[Complex32](capacity=size)
    for index in range(size):
        transmitted.append(Complex32(
            Float32(0.25 * Float64(2 * index + 1)),
            Float32(-0.125 * Float64(index + 1)),
        ))
    var channel_span = Span(channel)
    var transmitted_span = Span(transmitted)
    var observation = complex_matvec_f32(
        channel_span, transmitted_span, size
    )
    var observation_span = Span(observation)
    var output = List[Complex32](
        length=size, fill=Complex32(0.0, 0.0)
    )
    var gram = List[Complex32](
        length=size * size, fill=Complex32(0.0, 0.0)
    )
    var matched = List[Complex32](
        length=size, fill=Complex32(0.0, 0.0)
    )
    var workspace = make_mimo_workspace_f32(size)
    var checksum = _workload_make_mimo_workspace_f32(size)
    checksum ^= _workload_complex_matvec_f32(
        channel_span, transmitted_span, size
    )
    checksum ^= _workload_complex_matvec_f32_into(
        channel_span, transmitted_span, size, output
    )
    checksum ^= _workload_mimo_gram_matched_f32_into(
        channel_span, observation_span, size, gram, matched
    )
    checksum ^= _workload_mimo_zf_f32_into(
        channel_span, observation_span, workspace, output
    )
    checksum ^= _workload_mimo_mmse_f32_into(
        channel_span, observation_span, Float32(0.05), workspace, output
    )
    keep(observation)
    keep(gram)
    keep(matched)
    keep(workspace)
    keep(output)
    keep(checksum)
    print("mimo_f32_size:", size)
    print("mimo_f32_retained_checksum:", checksum)


def main() raises:
    print_benchmark_metadata()
    _benchmark_size(2)
    _benchmark_size(4)
