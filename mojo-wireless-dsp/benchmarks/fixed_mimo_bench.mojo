"""Attributable fixed-point 2x2 MIMO latency evidence.

Each ledger API owns one no-inline workload, one timer, and one report.  Fixed
inputs are checked twice, followed by three warmups and nine samples.  Timed
regions contain exactly one target call; result retention and endpoint
fingerprints occur only after the timer stops.
"""

from std.benchmark import keep
from std.collections import Span
from std.time import global_perf_counter_ns
from wireless_dsp.benchmarking import (
    print_benchmark_metadata,
    report_timing_samples,
)
from wireless_dsp.numerics.complex_fixed import ComplexRaw
from wireless_dsp.backend.fixed_mimo_reference import (
    FixedMIMOFormats,
    FixedMIMOZF2x2Result,
    fixed_complex_matvec_2x2_raw,
    fixed_mimo_default_formats,
    fixed_mimo_determinant_format,
    fixed_mimo_zf_canonical_rtl_vectors,
    fixed_mimo_zf_result_checksum,
    fixed_mimo_zf_scale_trace_text,
    fixed_zf_equalize_2x2_raw,
)


comptime _WARMUPS = 3
comptime _SAMPLES = 9
comptime _FIXED_RUNS = 2


def _mix(checksum: UInt64, value: UInt64) -> UInt64:
    return (checksum ^ value) * UInt64(1099511628211)


def _fingerprint_raw(values: List[ComplexRaw]) -> UInt64:
    var fingerprint = UInt64(len(values))
    if len(values) > 0:
        fingerprint = _mix(fingerprint, UInt64(values[0].re))
        fingerprint = _mix(fingerprint, UInt64(values[0].im))
        var last = values[len(values) - 1]
        fingerprint = _mix(fingerprint, UInt64(last.re))
        fingerprint = _mix(fingerprint, UInt64(last.im))
    return fingerprint


def _fingerprint_formats(formats: FixedMIMOFormats) -> UInt64:
    var fingerprint = UInt64(formats.channel.storage_bits)
    fingerprint = _mix(
        fingerprint, UInt64(formats.channel.fraction_bits)
    )
    fingerprint = _mix(
        fingerprint, UInt64(formats.output.storage_bits)
    )
    return _mix(fingerprint, UInt64(formats.output.fraction_bits))


def _fingerprint_zf(result: FixedMIMOZF2x2Result) -> UInt64:
    var fingerprint = UInt64(len(result.estimates))
    if len(result.estimates) > 0:
        fingerprint = _mix(fingerprint, UInt64(result.estimates[0].re))
        var last = result.estimates[len(result.estimates) - 1]
        fingerprint = _mix(fingerprint, UInt64(last.im))
    return _mix(
        fingerprint, UInt64(result.scale_trace.determinant_raw)
    )


def _text_checksum(text: StringSlice) -> UInt64:
    var checksum = UInt64(14695981039346656037)
    var bytes = text.as_bytes()
    for index in range(len(bytes)):
        checksum = (checksum ^ UInt64(UInt8(bytes[index]))) * UInt64(
            1099511628211
        )
    return checksum


def _text_fingerprint(text: StringSlice) -> UInt64:
    var bytes = text.as_bytes()
    var fingerprint = UInt64(len(bytes))
    if len(bytes) > 0:
        fingerprint = _mix(fingerprint, UInt64(UInt8(bytes[0])))
        fingerprint = _mix(
            fingerprint, UInt64(UInt8(bytes[len(bytes) - 1]))
        )
    return fingerprint


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
            raise Error("fixed MIMO benchmark result is nondeterministic")
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
def _workload_fixed_mimo_default_formats() raises -> UInt64:
    var samples = List[UInt64](capacity=_SAMPLES)
    var first = UInt64(0)
    var checksum = UInt64(1469598103934665603)
    for invocation in range(_FIXED_RUNS + _WARMUPS + _SAMPLES):
        var start = global_perf_counter_ns()
        var result = fixed_mimo_default_formats()
        var elapsed = global_perf_counter_ns() - start
        keep(result)
        var fingerprint = _fingerprint_formats(result)
        _record(
            invocation, elapsed, fingerprint, first, samples, checksum
        )
    return _finish("fixed_mimo_default_formats", samples, checksum)


@no_inline
def _workload_fixed_mimo_determinant_format(
    formats: FixedMIMOFormats,
) raises -> UInt64:
    var samples = List[UInt64](capacity=_SAMPLES)
    var first = UInt64(0)
    var checksum = UInt64(1469598103934665603)
    for invocation in range(_FIXED_RUNS + _WARMUPS + _SAMPLES):
        var start = global_perf_counter_ns()
        var result = fixed_mimo_determinant_format(formats)
        var elapsed = global_perf_counter_ns() - start
        keep(result)
        var fingerprint = UInt64(result.storage_bits)
        fingerprint = _mix(fingerprint, UInt64(result.fraction_bits))
        fingerprint = _mix(fingerprint, UInt64(result.rounding_mode))
        fingerprint = _mix(fingerprint, UInt64(result.overflow_mode))
        _record(
            invocation, elapsed, fingerprint, first, samples, checksum
        )
    return _finish("fixed_mimo_determinant_format", samples, checksum)


@no_inline
def _workload_fixed_complex_matvec_2x2_raw(
    matrix: Span[ComplexRaw, ...],
    vector: Span[ComplexRaw, ...],
    formats: FixedMIMOFormats,
) raises -> UInt64:
    var samples = List[UInt64](capacity=_SAMPLES)
    var first = UInt64(0)
    var checksum = UInt64(1469598103934665603)
    for invocation in range(_FIXED_RUNS + _WARMUPS + _SAMPLES):
        var start = global_perf_counter_ns()
        var result = fixed_complex_matvec_2x2_raw(
            matrix,
            vector,
            formats.channel,
            formats.symbol,
            formats.accumulator,
            formats.observation,
        )
        var elapsed = global_perf_counter_ns() - start
        keep(result)
        var fingerprint = _fingerprint_raw(result)
        _record(
            invocation, elapsed, fingerprint, first, samples, checksum
        )
    return _finish("fixed_complex_matvec_2x2_raw", samples, checksum)


@no_inline
def _workload_fixed_zf_equalize_2x2_raw(
    channel: Span[ComplexRaw, ...],
    observation: Span[ComplexRaw, ...],
    formats: FixedMIMOFormats,
    threshold: Int64,
) raises -> UInt64:
    var samples = List[UInt64](capacity=_SAMPLES)
    var first = UInt64(0)
    var checksum = UInt64(1469598103934665603)
    for invocation in range(_FIXED_RUNS + _WARMUPS + _SAMPLES):
        var start = global_perf_counter_ns()
        var result = fixed_zf_equalize_2x2_raw(
            channel, observation, formats, threshold
        )
        var elapsed = global_perf_counter_ns() - start
        keep(result)
        var fingerprint = _fingerprint_zf(result)
        _record(
            invocation, elapsed, fingerprint, first, samples, checksum
        )
    return _finish("fixed_zf_equalize_2x2_raw", samples, checksum)


@no_inline
def _workload_fixed_mimo_zf_result_checksum(
    result: FixedMIMOZF2x2Result,
) raises -> UInt64:
    var samples = List[UInt64](capacity=_SAMPLES)
    var first = UInt64(0)
    var checksum = UInt64(1469598103934665603)
    for invocation in range(_FIXED_RUNS + _WARMUPS + _SAMPLES):
        var start = global_perf_counter_ns()
        var result_checksum = fixed_mimo_zf_result_checksum(result)
        var elapsed = global_perf_counter_ns() - start
        keep(result_checksum)
        var fingerprint = result_checksum
        _record(
            invocation, elapsed, fingerprint, first, samples, checksum
        )
    return _finish("fixed_mimo_zf_result_checksum", samples, checksum)


@no_inline
def _workload_fixed_mimo_zf_scale_trace_text(
    result: FixedMIMOZF2x2Result,
) raises -> Tuple[UInt64, UInt64]:
    var samples = List[UInt64](capacity=_SAMPLES)
    var first_full = UInt64(0)
    var first_fingerprint = UInt64(0)
    var full_checksum = UInt64(1469598103934665603)
    var fingerprint_checksum = UInt64(1469598103934665603)
    for invocation in range(_FIXED_RUNS + _WARMUPS + _SAMPLES):
        var start = global_perf_counter_ns()
        var text = fixed_mimo_zf_scale_trace_text(result)
        var elapsed = global_perf_counter_ns() - start
        keep(text)
        var full = _text_checksum(StringSlice(text))
        var fingerprint = _text_fingerprint(StringSlice(text))
        if invocation == 0:
            first_full = full
            first_fingerprint = fingerprint
        elif invocation == 1:
            if full != first_full or fingerprint != first_fingerprint:
                raise Error("fixed MIMO scale trace is nondeterministic")
        elif invocation >= _FIXED_RUNS + _WARMUPS:
            samples.append(elapsed)
            full_checksum = _mix(full_checksum, full)
            fingerprint_checksum = _mix(
                fingerprint_checksum, fingerprint
            )
    report_timing_samples(
        "fixed_mimo_zf_scale_trace_text", samples, _WARMUPS, 1, "api_call"
    )
    keep(samples)
    return (full_checksum, fingerprint_checksum)


@no_inline
def _workload_fixed_mimo_zf_canonical_rtl_vectors(
    result: FixedMIMOZF2x2Result,
) raises -> Tuple[UInt64, UInt64]:
    var samples = List[UInt64](capacity=_SAMPLES)
    var first_full = UInt64(0)
    var first_fingerprint = UInt64(0)
    var full_checksum = UInt64(1469598103934665603)
    var fingerprint_checksum = UInt64(1469598103934665603)
    for invocation in range(_FIXED_RUNS + _WARMUPS + _SAMPLES):
        var start = global_perf_counter_ns()
        var text = fixed_mimo_zf_canonical_rtl_vectors(result)
        var elapsed = global_perf_counter_ns() - start
        keep(text)
        var full = _text_checksum(StringSlice(text))
        var fingerprint = _text_fingerprint(StringSlice(text))
        if invocation == 0:
            first_full = full
            first_fingerprint = fingerprint
        elif invocation == 1:
            if full != first_full or fingerprint != first_fingerprint:
                raise Error("fixed MIMO canonical vectors are nondeterministic")
        elif invocation >= _FIXED_RUNS + _WARMUPS:
            samples.append(elapsed)
            full_checksum = _mix(full_checksum, full)
            fingerprint_checksum = _mix(
                fingerprint_checksum, fingerprint
            )
    report_timing_samples(
        "fixed_mimo_zf_canonical_rtl_vectors",
        samples,
        _WARMUPS,
        1,
        "api_call",
    )
    keep(samples)
    return (full_checksum, fingerprint_checksum)


def _run_batch(
    channel: Span[ComplexRaw, ...],
    observation: Span[ComplexRaw, ...],
    formats: FixedMIMOFormats,
) raises -> UInt64:
    var checksum = _workload_fixed_zf_equalize_2x2_raw(
        channel, observation, formats, Int64(1 << 16)
    )
    var result = fixed_zf_equalize_2x2_raw(
        channel, observation, formats, Int64(1 << 16)
    )
    checksum ^= _workload_fixed_mimo_zf_result_checksum(result)
    var scale_checksums = _workload_fixed_mimo_zf_scale_trace_text(result)
    var vector_checksums = _workload_fixed_mimo_zf_canonical_rtl_vectors(
        result
    )
    print(
        "fixed_mimo_zf_scale_trace_full_output_checksum:",
        scale_checksums[0],
    )
    print(
        "fixed_mimo_zf_scale_trace_fingerprint_checksum:",
        scale_checksums[1],
    )
    print(
        "fixed_mimo_zf_vectors_full_output_checksum:",
        vector_checksums[0],
    )
    print(
        "fixed_mimo_zf_vectors_fingerprint_checksum:",
        vector_checksums[1],
    )
    checksum ^= scale_checksums[0] ^ scale_checksums[1]
    checksum ^= vector_checksums[0] ^ vector_checksums[1]
    keep(result)
    keep(checksum)
    return checksum


def main() raises:
    var formats = fixed_mimo_default_formats()
    var channel: List[ComplexRaw] = [
        ComplexRaw(4301, 173),
        ComplexRaw(-311, 419),
        ComplexRaw(257, -367),
        ComplexRaw(3987, -211),
    ]
    var symbols: List[ComplexRaw] = [
        ComplexRaw(1536, -1024), ComplexRaw(-768, 1792)
    ]
    var channel_span = Span(channel)
    var symbols_span = Span(symbols)
    var observation = fixed_complex_matvec_2x2_raw(
        channel_span,
        symbols_span,
        formats.channel,
        formats.symbol,
        formats.accumulator,
        formats.observation,
    )
    var observation_span = Span(observation)
    print_benchmark_metadata()
    var checksum = _workload_fixed_mimo_default_formats()
    checksum ^= _workload_fixed_mimo_determinant_format(formats)
    checksum ^= _workload_fixed_complex_matvec_2x2_raw(
        channel_span, symbols_span, formats
    )
    checksum ^= _run_batch(channel_span, observation_span, formats)
    keep(observation)
    keep(checksum)
    print("fixed_mimo_zf_retained_checksum:", checksum)
