"""Strictly attributable latency evidence for practical Float32 CPU APIs.

Each ledger API owns one no-inline workload with one direct target call in its
timed region and one report.  Fixed inputs are run twice for checksum equality,
then three warmups and nine measured samples are executed.
"""

from std.benchmark import keep
from std.collections import Span
from std.time import global_perf_counter_ns
from wireless_dsp.benchmarking import (
    print_benchmark_metadata,
    report_timing_samples,
)
from wireless_dsp.core import Complex32
from wireless_dsp.backend.cpu.practical import (
    FFTPlanF32,
    FIRPlanF32,
    cross_correlate_complex_split_f32,
    fft_batch_f32_with_plan,
    fir_real_f32_with_plan,
    make_fft_plan_f32,
    make_fir_plan_f32,
    qam_demap_hard_f32,
    qam_demapper_llr_maxlog_f32,
    qam_demapper_llr_piecewise_f32,
    qam_map_f32,
    quantize_llr_f32,
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


def _fingerprint_complex(value: Complex32) -> UInt64:
    return _mix(_fingerprint_float(value.re), _fingerprint_float(value.im))


def _fingerprint_complex_list(values: List[Complex32]) -> UInt64:
    var fingerprint = UInt64(len(values))
    if len(values) > 0:
        fingerprint = _mix(fingerprint, _fingerprint_complex(values[0]))
        fingerprint = _mix(
            fingerprint, _fingerprint_complex(values[len(values) - 1])
        )
    return fingerprint


def _fingerprint_float_list(values: List[Float32]) -> UInt64:
    var fingerprint = UInt64(len(values))
    if len(values) > 0:
        fingerprint = _mix(fingerprint, _fingerprint_float(values[0]))
        fingerprint = _mix(
            fingerprint, _fingerprint_float(values[len(values) - 1])
        )
    return fingerprint


def _fingerprint_uint8_list(values: List[UInt8]) -> UInt64:
    var fingerprint = UInt64(len(values))
    if len(values) > 0:
        fingerprint = _mix(fingerprint, UInt64(values[0]))
        fingerprint = _mix(
            fingerprint, UInt64(values[len(values) - 1])
        )
    return fingerprint


def _fingerprint_int_list(values: List[Int]) -> UInt64:
    var fingerprint = UInt64(len(values))
    if len(values) > 0:
        fingerprint = _mix(fingerprint, UInt64(values[0] + 4096))
        fingerprint = _mix(
            fingerprint, UInt64(values[len(values) - 1] + 4096)
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
            raise Error("fixed practical-CPU result is nondeterministic")
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
def _workload_make_fft_plan_f32(size: Int) raises -> UInt64:
    var samples = List[UInt64](capacity=_SAMPLES)
    var first = UInt64(0)
    var checksum = UInt64(1469598103934665603)
    for invocation in range(_FIXED_RUNS + _WARMUPS + _SAMPLES):
        var start = global_perf_counter_ns()
        var result = make_fft_plan_f32(size)
        var elapsed = global_perf_counter_ns() - start
        keep(result)
        var fingerprint = _mix(UInt64(result.size), UInt64(result.inverse))
        fingerprint = _mix(fingerprint, UInt64(len(result.twiddles)))
        if len(result.twiddles) > 0:
            fingerprint = _mix(
                fingerprint, _fingerprint_complex(result.twiddles[0])
            )
        _record(
            invocation, elapsed, fingerprint, first, samples, checksum
        )
    return _finish("make_fft_plan_f32", samples, checksum)


@no_inline
def _workload_fft_batch_f32_with_plan(
    values: Span[Complex32, ...], plan: FFTPlanF32
) raises -> UInt64:
    var samples = List[UInt64](capacity=_SAMPLES)
    var first = UInt64(0)
    var checksum = UInt64(1469598103934665603)
    for invocation in range(_FIXED_RUNS + _WARMUPS + _SAMPLES):
        var start = global_perf_counter_ns()
        var result = fft_batch_f32_with_plan(values, plan)
        var elapsed = global_perf_counter_ns() - start
        keep(result)
        var fingerprint = _fingerprint_complex_list(result)
        _record(
            invocation, elapsed, fingerprint, first, samples, checksum
        )
    return _finish("fft_batch_f32_with_plan", samples, checksum)


@no_inline
def _workload_make_fir_plan_f32(
    taps: Span[Float32, ...]
) raises -> UInt64:
    var samples = List[UInt64](capacity=_SAMPLES)
    var first = UInt64(0)
    var checksum = UInt64(1469598103934665603)
    for invocation in range(_FIXED_RUNS + _WARMUPS + _SAMPLES):
        var start = global_perf_counter_ns()
        var result = make_fir_plan_f32(taps)
        var elapsed = global_perf_counter_ns() - start
        keep(result)
        var fingerprint = _mix(
            _fingerprint_float_list(result.taps),
            _fingerprint_float_list(result.reversed_taps),
        )
        _record(
            invocation, elapsed, fingerprint, first, samples, checksum
        )
    return _finish("make_fir_plan_f32", samples, checksum)


@no_inline
def _workload_fir_real_f32_with_plan(
    signal: Span[Float32, ...], plan: FIRPlanF32
) raises -> UInt64:
    var samples = List[UInt64](capacity=_SAMPLES)
    var first = UInt64(0)
    var checksum = UInt64(1469598103934665603)
    for invocation in range(_FIXED_RUNS + _WARMUPS + _SAMPLES):
        var start = global_perf_counter_ns()
        var result = fir_real_f32_with_plan(signal, plan)
        var elapsed = global_perf_counter_ns() - start
        keep(result)
        var fingerprint = _fingerprint_float_list(result)
        _record(
            invocation, elapsed, fingerprint, first, samples, checksum
        )
    return _finish("fir_real_f32_with_plan", samples, checksum)


@no_inline
def _workload_cross_correlate_complex_split_f32(
    signal_re: Span[Float32, ...],
    signal_im: Span[Float32, ...],
    reference_re: Span[Float32, ...],
    reference_im: Span[Float32, ...],
) raises -> UInt64:
    var samples = List[UInt64](capacity=_SAMPLES)
    var first = UInt64(0)
    var checksum = UInt64(1469598103934665603)
    for invocation in range(_FIXED_RUNS + _WARMUPS + _SAMPLES):
        var start = global_perf_counter_ns()
        var result = cross_correlate_complex_split_f32(
            signal_re, signal_im, reference_re, reference_im
        )
        var elapsed = global_perf_counter_ns() - start
        keep(result)
        var fingerprint = _fingerprint_complex_list(result)
        _record(
            invocation, elapsed, fingerprint, first, samples, checksum
        )
    return _finish("cross_correlate_complex_split_f32", samples, checksum)


@no_inline
def _workload_qam_map_f32(
    bits: Span[UInt8, ...], bits_per_symbol: Int
) raises -> UInt64:
    var samples = List[UInt64](capacity=_SAMPLES)
    var first = UInt64(0)
    var checksum = UInt64(1469598103934665603)
    for invocation in range(_FIXED_RUNS + _WARMUPS + _SAMPLES):
        var start = global_perf_counter_ns()
        var result = qam_map_f32(bits, bits_per_symbol)
        var elapsed = global_perf_counter_ns() - start
        keep(result)
        var fingerprint = _fingerprint_complex_list(result)
        _record(
            invocation, elapsed, fingerprint, first, samples, checksum
        )
    return _finish("qam_map_f32", samples, checksum)


@no_inline
def _workload_qam_demap_hard_f32(
    values: Span[Complex32, ...], bits_per_symbol: Int
) raises -> UInt64:
    var samples = List[UInt64](capacity=_SAMPLES)
    var first = UInt64(0)
    var checksum = UInt64(1469598103934665603)
    for invocation in range(_FIXED_RUNS + _WARMUPS + _SAMPLES):
        var start = global_perf_counter_ns()
        var result = qam_demap_hard_f32(values, bits_per_symbol)
        var elapsed = global_perf_counter_ns() - start
        keep(result)
        var fingerprint = _fingerprint_uint8_list(result)
        _record(
            invocation, elapsed, fingerprint, first, samples, checksum
        )
    return _finish("qam_demap_hard_f32", samples, checksum)


@no_inline
def _workload_qam_demapper_llr_maxlog_f32(
    values: Span[Complex32, ...],
    bits_per_symbol: Int,
    noise_variance: Float32,
) raises -> UInt64:
    var samples = List[UInt64](capacity=_SAMPLES)
    var first = UInt64(0)
    var checksum = UInt64(1469598103934665603)
    for invocation in range(_FIXED_RUNS + _WARMUPS + _SAMPLES):
        var start = global_perf_counter_ns()
        var result = qam_demapper_llr_maxlog_f32(
            values, bits_per_symbol, noise_variance
        )
        var elapsed = global_perf_counter_ns() - start
        keep(result)
        var fingerprint = _fingerprint_float_list(result)
        _record(
            invocation, elapsed, fingerprint, first, samples, checksum
        )
    return _finish("qam_demapper_llr_maxlog_f32", samples, checksum)


@no_inline
def _workload_qam_demapper_llr_piecewise_f32(
    values: Span[Complex32, ...],
    bits_per_symbol: Int,
    noise_variance: Float32,
) raises -> UInt64:
    var samples = List[UInt64](capacity=_SAMPLES)
    var first = UInt64(0)
    var checksum = UInt64(1469598103934665603)
    for invocation in range(_FIXED_RUNS + _WARMUPS + _SAMPLES):
        var start = global_perf_counter_ns()
        var result = qam_demapper_llr_piecewise_f32(
            values, bits_per_symbol, noise_variance
        )
        var elapsed = global_perf_counter_ns() - start
        keep(result)
        var fingerprint = _fingerprint_float_list(result)
        _record(
            invocation, elapsed, fingerprint, first, samples, checksum
        )
    return _finish("qam_demapper_llr_piecewise_f32", samples, checksum)


@no_inline
def _workload_quantize_llr_f32(
    values: Span[Float32, ...], scale: Float32, clip: Int
) raises -> UInt64:
    var samples = List[UInt64](capacity=_SAMPLES)
    var first = UInt64(0)
    var checksum = UInt64(1469598103934665603)
    for invocation in range(_FIXED_RUNS + _WARMUPS + _SAMPLES):
        var start = global_perf_counter_ns()
        var result = quantize_llr_f32(values, scale=scale, clip=clip)
        var elapsed = global_perf_counter_ns() - start
        keep(result)
        var fingerprint = _fingerprint_int_list(result)
        _record(
            invocation, elapsed, fingerprint, first, samples, checksum
        )
    return _finish("quantize_llr_f32", samples, checksum)


def _next_uniform_f32(mut state: UInt64) -> Float32:
    state = state * UInt64(6364136223846793005) + UInt64(1442695040888963407)
    return Float32(state >> 40) / Float32(1 << 24)


def _benchmark_fft() raises -> UInt64:
    comptime transform_size = 256
    comptime batch_count = 4
    var state = UInt64(0xFF720260821)
    var values = List[Complex32](capacity=transform_size * batch_count)
    for _ in range(transform_size * batch_count):
        values.append(Complex32(
            Float32(2.0) * _next_uniform_f32(state) - Float32(1.0),
            Float32(2.0) * _next_uniform_f32(state) - Float32(1.0),
        ))
    var values_span = Span(values)
    var plan = make_fft_plan_f32(transform_size)
    var checksum = _workload_make_fft_plan_f32(transform_size)
    checksum ^= _workload_fft_batch_f32_with_plan(values_span, plan)
    keep(plan)
    return checksum


def _benchmark_fir() raises -> UInt64:
    comptime signal_length = 1024
    comptime tap_count = 31
    var state = UInt64(0xF1A20260821)
    var signal = List[Float32](capacity=signal_length)
    var taps = List[Float32](capacity=tap_count)
    for _ in range(signal_length):
        signal.append(
            Float32(2.0) * _next_uniform_f32(state) - Float32(1.0)
        )
    for _ in range(tap_count):
        taps.append(
            (Float32(2.0) * _next_uniform_f32(state) - Float32(1.0))
            / Float32(tap_count)
        )
    var signal_span = Span(signal)
    var taps_span = Span(taps)
    var plan = make_fir_plan_f32(taps_span)
    var checksum = _workload_make_fir_plan_f32(taps_span)
    checksum ^= _workload_fir_real_f32_with_plan(signal_span, plan)
    keep(plan)
    return checksum


def _benchmark_correlation() raises -> UInt64:
    comptime signal_length = 512
    comptime reference_length = 31
    var state = UInt64(0xC02220260821)
    var signal_re = List[Float32](capacity=signal_length)
    var signal_im = List[Float32](capacity=signal_length)
    var reference_re = List[Float32](capacity=reference_length)
    var reference_im = List[Float32](capacity=reference_length)
    for _ in range(signal_length):
        signal_re.append(
            Float32(2.0) * _next_uniform_f32(state) - Float32(1.0)
        )
        signal_im.append(
            Float32(2.0) * _next_uniform_f32(state) - Float32(1.0)
        )
    for _ in range(reference_length):
        reference_re.append(
            Float32(2.0) * _next_uniform_f32(state) - Float32(1.0)
        )
        reference_im.append(
            Float32(2.0) * _next_uniform_f32(state) - Float32(1.0)
        )
    var signal_re_span = Span(signal_re)
    var signal_im_span = Span(signal_im)
    var reference_re_span = Span(reference_re)
    var reference_im_span = Span(reference_im)
    return _workload_cross_correlate_complex_split_f32(
        signal_re_span,
        signal_im_span,
        reference_re_span,
        reference_im_span,
    )


def _benchmark_qam() raises -> UInt64:
    comptime symbol_count = 128
    comptime bits_per_symbol = 8
    var bits = List[UInt8](capacity=symbol_count * bits_per_symbol)
    for index in range(symbol_count * bits_per_symbol):
        bits.append(UInt8((index * 13 + index // 7) & 1))
    var bits_span = Span(bits)
    var mapped = qam_map_f32(bits_span, bits_per_symbol)
    var mapped_span = Span(mapped)
    var llrs = qam_demapper_llr_piecewise_f32(
        mapped_span, bits_per_symbol, Float32(0.1)
    )
    var llrs_span = Span(llrs)
    var checksum = _workload_qam_map_f32(bits_span, bits_per_symbol)
    checksum ^= _workload_qam_demap_hard_f32(
        mapped_span, bits_per_symbol
    )
    checksum ^= _workload_qam_demapper_llr_maxlog_f32(
        mapped_span, bits_per_symbol, Float32(0.1)
    )
    checksum ^= _workload_qam_demapper_llr_piecewise_f32(
        mapped_span, bits_per_symbol, Float32(0.1)
    )
    checksum ^= _workload_quantize_llr_f32(
        llrs_span, Float32(4.0), 127
    )
    keep(mapped)
    keep(llrs)
    return checksum


def main() raises:
    print_benchmark_metadata()
    var checksum = _benchmark_fft()
    checksum ^= _benchmark_fir()
    checksum ^= _benchmark_correlation()
    checksum ^= _benchmark_qam()
    keep(checksum)
    print("cpu_practical_retained_checksum:", checksum)
