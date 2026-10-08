"""Repeatable Phase-2 FFT, QAM, and correlation latency samples.

The three kernel-ledger APIs each have one attributable ``@no_inline``
workload.  Every invocation times exactly one public API call; fixed inputs are
run twice before three warmups and nine retained samples.
"""

from std.benchmark import keep
from std.sys.info import align_of
from std.time import global_perf_counter_ns
from wireless_dsp.benchmarking import (
    print_benchmark_metadata,
    print_runtime_buffer_alignment,
    report_timing_samples,
)
from wireless_dsp.core import Complex64, Span
from wireless_dsp.dsp import fft, cross_correlate_complex
from wireless_dsp.modem import qam_map, qam_demapper_llr_maxlog


comptime _WARMUP = 3
comptime _REPETITIONS = 9
comptime _FIXED_RUNS = 2


def _mix(checksum: UInt64, value: UInt64) -> UInt64:
    return (checksum ^ value) * UInt64(1099511628211)


def _fingerprint_float(value: Float64) -> UInt64:
    return _mix(
        UInt64(Int(abs(value) * 1_000_000.0)),
        UInt64(1 if value < 0.0 else 0),
    )


def _fingerprint_complex(values: List[Complex64]) -> UInt64:
    var fingerprint = UInt64(len(values))
    if len(values) > 0:
        fingerprint = _mix(
            fingerprint,
            _mix(
                _fingerprint_float(values[0].re),
                _fingerprint_float(values[0].im),
            ),
        )
        var last = values[len(values) - 1]
        fingerprint = _mix(
            fingerprint,
            _mix(
                _fingerprint_float(last.re),
                _fingerprint_float(last.im),
            ),
        )
    return fingerprint


def _fingerprint_float_list(values: List[Float64]) -> UInt64:
    var fingerprint = UInt64(len(values))
    if len(values) > 0:
        fingerprint = _mix(fingerprint, _fingerprint_float(values[0]))
        fingerprint = _mix(
            fingerprint, _fingerprint_float(values[len(values) - 1])
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
            raise Error("fixed Phase-2 benchmark result is nondeterministic")
        keep(first)
        keep(fingerprint)
    elif invocation >= _FIXED_RUNS + _WARMUP:
        samples.append(elapsed)
        checksum = _mix(checksum, fingerprint)


def _finish(
    name: StringSlice,
    mut samples: List[UInt64],
    checksum: UInt64,
) raises -> UInt64:
    report_timing_samples(name, samples, _WARMUP, 1, "api_call")
    keep(samples)
    return checksum


@no_inline
def _workload_fft(values: Span[Complex64, ...]) raises -> UInt64:
    var samples = List[UInt64](capacity=_REPETITIONS)
    var first = UInt64(0)
    var checksum = UInt64(1469598103934665603)
    for invocation in range(_FIXED_RUNS + _WARMUP + _REPETITIONS):
        var start = global_perf_counter_ns()
        var output = fft(values)
        var elapsed = global_perf_counter_ns() - start
        keep(output)
        var fingerprint = _fingerprint_complex(output)
        _record(
            invocation, elapsed, fingerprint, first, samples, checksum
        )
    return _finish("phase2_fft", samples, checksum)


@no_inline
def _workload_qam_map(
    bits: Span[UInt8, ...], bits_per_symbol: Int
) raises -> UInt64:
    var samples = List[UInt64](capacity=_REPETITIONS)
    var first = UInt64(0)
    var checksum = UInt64(1469598103934665603)
    for invocation in range(_FIXED_RUNS + _WARMUP + _REPETITIONS):
        var start = global_perf_counter_ns()
        var output = qam_map(bits, bits_per_symbol)
        var elapsed = global_perf_counter_ns() - start
        keep(output)
        var fingerprint = _fingerprint_complex(output)
        _record(
            invocation, elapsed, fingerprint, first, samples, checksum
        )
    return _finish("phase2_qam_map", samples, checksum)


@no_inline
def _workload_qam_demapper_llr_maxlog(
    symbols: Span[Complex64, ...],
    bits_per_symbol: Int,
    noise_variance: Float64,
) raises -> UInt64:
    var samples = List[UInt64](capacity=_REPETITIONS)
    var first = UInt64(0)
    var checksum = UInt64(1469598103934665603)
    for invocation in range(_FIXED_RUNS + _WARMUP + _REPETITIONS):
        var start = global_perf_counter_ns()
        var output = qam_demapper_llr_maxlog(
            symbols, bits_per_symbol, noise_variance
        )
        var elapsed = global_perf_counter_ns() - start
        keep(output)
        var fingerprint = _fingerprint_float_list(output)
        _record(
            invocation, elapsed, fingerprint, first, samples, checksum
        )
    return _finish("phase2_qam_demapper_llr_maxlog", samples, checksum)


def _benchmark_fft() raises -> UInt64:
    comptime size = 4096
    var values = List[Complex64](capacity=size)
    for index in range(size):
        values.append(Complex64(
            Float64(index % 17) / 17.0,
            Float64(index % 13) / 13.0,
        ))
    var values_span = Span(values)
    return _workload_fft(values_span)


def _benchmark_qam() raises -> UInt64:
    comptime symbol_count = 4096
    comptime bits_per_symbol = 8
    var bits = List[UInt8](capacity=bits_per_symbol * symbol_count)
    for index in range(bits_per_symbol * symbol_count):
        bits.append(UInt8((13 * index + index // 7) & 1))
    var bits_span = Span(bits)
    var checksum = _workload_qam_map(bits_span, bits_per_symbol)
    # The demapper fixture is intentionally constructed outside its workload.
    var symbols = qam_map(bits_span, bits_per_symbol)
    var symbols_span = Span(symbols)
    checksum ^= _workload_qam_demapper_llr_maxlog(
        symbols_span, bits_per_symbol, 0.1
    )
    keep(checksum)
    return checksum


def _benchmark_correlation() raises:
    comptime signal_count = 4096
    comptime reference_count = 64
    var signal = List[Complex64](capacity=signal_count)
    var reference = List[Complex64](capacity=reference_count)
    for index in range(signal_count):
        signal.append(Complex64(
            Float64((17 * index + 3) % 101) / 101.0,
            Float64((11 * index + 7) % 97) / 97.0,
        ))
    for index in range(reference_count):
        reference.append(Complex64(
            Float64((5 * index + 1) % 31) / 31.0,
            -Float64((7 * index + 2) % 29) / 29.0,
        ))
    for _ in range(_WARMUP):
        keep(cross_correlate_complex(Span(signal), Span(reference)))
    var samples = List[UInt64](capacity=_REPETITIONS)
    var checksum = 0.0
    var output_count = signal_count - reference_count + 1
    for repetition in range(_REPETITIONS):
        var start = global_perf_counter_ns()
        var output = cross_correlate_complex(
            Span(signal), Span(reference)
        )
        samples.append(global_perf_counter_ns() - start)
        keep(output)
        var selected = output[(211 * repetition + 13) % len(output)]
        checksum += selected.re - 2.0 * selected.im
    report_timing_samples(
        "complex_correlation", samples, _WARMUP, output_count,
        "complex_correlation_output",
    )
    print("complex_correlation_checksum:", checksum)


def main() raises:
    print_benchmark_metadata()
    var alignment_probe = List[Complex64](
        length=64, fill=Complex64(0.0, 0.0)
    )
    print_runtime_buffer_alignment(
        "phase2_complex64_probe",
        Int(alignment_probe.unsafe_ptr()),
        align_of[Complex64](),
    )
    print("warmup_repetitions:", _WARMUP)
    print("measured_repetitions:", _REPETITIONS)
    var checksum = _benchmark_fft()
    checksum ^= _benchmark_qam()
    _benchmark_correlation()
    keep(checksum)
    print("phase2_attributable_retained_checksum:", checksum)
