"""Strictly attributable backend, fixed-point, and MIMO benchmarks.

Every kernel-ledger API in this evidence file owns one unique ``@no_inline``
workload, timed call site, and report.  All configs, Lists, Spans, plans, and
derived fixtures precede the timer.  Each timed region calls exactly one target
API; the complete owned result is retained and an O(1) fingerprint is computed
after timing.  Fixed inputs run twice before three warmups and nine samples.
"""

from std.benchmark import keep
from std.collections import Span
from std.sys.info import align_of
from std.time import global_perf_counter_ns
from wireless_dsp.benchmarking import (
    print_benchmark_metadata,
    print_runtime_buffer_alignment,
    report_timing_samples,
)
from wireless_dsp.core import Complex32, Complex64
from wireless_dsp.mimo.matrix import (
    SmallComplexMatrix,
    cholesky,
    gram_matrix,
    hermitian,
    inverse,
    matrix_multiply,
    qr_decompose,
)
from wireless_dsp.backend.cpu.practical import (
    FFTPlanF32,
    fft_batch_f32,
    fft_f32,
    fft_in_place_f32_with_plan,
    fir_real_f32,
    ifft_f32,
    make_fft_plan_f32,
)
from wireless_dsp.backend.cpu.simd import (
    simd_complex_dot_split_f32,
    simd_dot_f32,
    simd_energy_f32,
    simd_sum_f32,
)
from wireless_dsp.backend.cpu.mimo_f32 import (
    mimo_gram_f32,
    mimo_gram_f32_into,
    mimo_matched_filter_f32,
    mimo_matched_filter_f32_into,
    mimo_mmse_f32,
    mimo_zf_f32,
)
from wireless_dsp.numerics.quantization import QFormat
from wireless_dsp.numerics.complex_fixed import ComplexRaw
from wireless_dsp.backend.fixed_reference import (
    complex_cross_correlate_raw,
    complex_dot_conjugate_raw,
    complex_fir_raw,
    fixed_dot_raw,
)
from wireless_dsp.backend.fixed_phy_reference import (
    fixed_equalize_flat_raw,
    fixed_flat_channel_raw,
    fixed_ls_flat_channel_raw,
    fixed_ofdm_demodulate_raw,
    fixed_ofdm_modulate_raw,
    fixed_phy_default_formats,
    fixed_qpsk_hard_bits,
    fixed_qpsk_llrs_raw,
    fixed_qpsk_map_raw,
    fixed_reciprocal_positive_raw,
)
from wireless_dsp.backend.fixed_mimo_reference import (
    fixed_complex_matvec_2x2_raw,
    fixed_hermitian_gram_2x2_raw,
    fixed_hermitian_matched_filter_2x2_raw,
    fixed_mimo_default_formats,
    fixed_mimo_determinant_format,
    fixed_mimo_reciprocal_positive_raw,
)
from wireless_dsp.backend.fixed_sync_reference import (
    fixed_repetition_correlation_raw,
    fixed_window_energy_raw,
)
from wireless_dsp.backend.fixed_wifi_bcc_reference import (
    fixed_wifi_bcc_encode,
    fixed_wifi_bcc_hard_llrs_raw,
)


comptime _WARMUPS = 3
comptime _SAMPLES = 9
comptime _FIXED_RUNS = 2


def _mix(checksum: UInt64, value: UInt64) -> UInt64:
    return (checksum ^ value) * UInt64(1099511628211)


def _fingerprint_f32(value: Float32) -> UInt64:
    return _mix(
        UInt64(Int(abs(Float64(value)) * 1_000_000.0)),
        UInt64(1 if value < 0.0 else 0),
    )


def _fingerprint_f64(value: Float64) -> UInt64:
    return _mix(
        UInt64(Int(abs(value) * 1_000_000.0)),
        UInt64(1 if value < 0.0 else 0),
    )


def _fingerprint_c32(value: Complex32) -> UInt64:
    return _mix(_fingerprint_f32(value.re), _fingerprint_f32(value.im))


def _fingerprint_c64(value: Complex64) -> UInt64:
    return _mix(_fingerprint_f64(value.re), _fingerprint_f64(value.im))


def _fingerprint_c32_list(values: List[Complex32]) -> UInt64:
    var fingerprint = UInt64(len(values))
    if len(values) > 0:
        fingerprint = _mix(fingerprint, _fingerprint_c32(values[0]))
        fingerprint = _mix(
            fingerprint, _fingerprint_c32(values[len(values) - 1])
        )
    return fingerprint


def _fingerprint_f32_list(values: List[Float32]) -> UInt64:
    var fingerprint = UInt64(len(values))
    if len(values) > 0:
        fingerprint = _mix(fingerprint, _fingerprint_f32(values[0]))
        fingerprint = _mix(
            fingerprint, _fingerprint_f32(values[len(values) - 1])
        )
    return fingerprint


def _fingerprint_raw_list(values: List[ComplexRaw]) -> UInt64:
    var fingerprint = UInt64(len(values))
    if len(values) > 0:
        fingerprint = _mix(fingerprint, UInt64(values[0].re))
        fingerprint = _mix(fingerprint, UInt64(values[0].im))
        var last = values[len(values) - 1]
        fingerprint = _mix(fingerprint, UInt64(last.re))
        fingerprint = _mix(fingerprint, UInt64(last.im))
    return fingerprint


def _fingerprint_i64_list(values: List[Int64]) -> UInt64:
    var fingerprint = UInt64(len(values))
    if len(values) > 0:
        fingerprint = _mix(fingerprint, UInt64(values[0]))
        fingerprint = _mix(
            fingerprint, UInt64(values[len(values) - 1])
        )
    return fingerprint


def _fingerprint_u8_list(values: List[UInt8]) -> UInt64:
    var fingerprint = UInt64(len(values))
    if len(values) > 0:
        fingerprint = _mix(fingerprint, UInt64(values[0]))
        fingerprint = _mix(
            fingerprint, UInt64(values[len(values) - 1])
        )
    return fingerprint


def _fingerprint_matrix(matrix: SmallComplexMatrix) -> UInt64:
    var fingerprint = _mix(UInt64(matrix.rows), UInt64(matrix.columns))
    if len(matrix.values) > 0:
        fingerprint = _mix(
            fingerprint, _fingerprint_c64(matrix.values[0])
        )
        fingerprint = _mix(
            fingerprint,
            _fingerprint_c64(matrix.values[len(matrix.values) - 1]),
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
            raise Error("fixed backend benchmark result is nondeterministic")
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
def _workload_fft_batch_f32(
    values: Span[Complex32, ...], transform_size: Int
) raises -> UInt64:
    var samples = List[UInt64](capacity=_SAMPLES)
    var first = UInt64(0)
    var checksum = UInt64(1469598103934665603)
    for invocation in range(_FIXED_RUNS + _WARMUPS + _SAMPLES):
        var start = global_perf_counter_ns()
        var result = fft_batch_f32(values, transform_size)
        var elapsed = global_perf_counter_ns() - start
        keep(result)
        var fingerprint = _fingerprint_c32_list(result)
        _record(invocation, elapsed, fingerprint, first, samples, checksum)
    return _finish("backend_fft_batch_f32", samples, checksum)


@no_inline
def _workload_fft_f32(values: Span[Complex32, ...]) raises -> UInt64:
    var samples = List[UInt64](capacity=_SAMPLES)
    var first = UInt64(0)
    var checksum = UInt64(1469598103934665603)
    for invocation in range(_FIXED_RUNS + _WARMUPS + _SAMPLES):
        var start = global_perf_counter_ns()
        var result = fft_f32(values)
        var elapsed = global_perf_counter_ns() - start
        keep(result)
        var fingerprint = _fingerprint_c32_list(result)
        _record(invocation, elapsed, fingerprint, first, samples, checksum)
    return _finish("backend_fft_f32", samples, checksum)


@no_inline
def _workload_fft_in_place_f32_with_plan(
    values: Span[Complex32, ...], plan: FFTPlanF32
) raises -> UInt64:
    var samples = List[UInt64](capacity=_SAMPLES)
    var first = UInt64(0)
    var checksum = UInt64(1469598103934665603)
    for invocation in range(_FIXED_RUNS + _WARMUPS + _SAMPLES):
        var result = List[Complex32](capacity=len(values))
        for index in range(len(values)):
            result.append(values[index])
        var start = global_perf_counter_ns()
        fft_in_place_f32_with_plan(result, plan)
        var elapsed = global_perf_counter_ns() - start
        keep(result)
        var fingerprint = _fingerprint_c32_list(result)
        _record(invocation, elapsed, fingerprint, first, samples, checksum)
    return _finish("backend_fft_in_place_f32_with_plan", samples, checksum)


@no_inline
def _workload_fir_real_f32(
    signal: Span[Float32, ...], taps: Span[Float32, ...]
) raises -> UInt64:
    var samples = List[UInt64](capacity=_SAMPLES)
    var first = UInt64(0)
    var checksum = UInt64(1469598103934665603)
    for invocation in range(_FIXED_RUNS + _WARMUPS + _SAMPLES):
        var start = global_perf_counter_ns()
        var result = fir_real_f32(signal, taps)
        var elapsed = global_perf_counter_ns() - start
        keep(result)
        var fingerprint = _fingerprint_f32_list(result)
        _record(invocation, elapsed, fingerprint, first, samples, checksum)
    return _finish("backend_fir_real_f32", samples, checksum)


@no_inline
def _workload_ifft_f32(values: Span[Complex32, ...]) raises -> UInt64:
    var samples = List[UInt64](capacity=_SAMPLES)
    var first = UInt64(0)
    var checksum = UInt64(1469598103934665603)
    for invocation in range(_FIXED_RUNS + _WARMUPS + _SAMPLES):
        var start = global_perf_counter_ns()
        var result = ifft_f32(values)
        var elapsed = global_perf_counter_ns() - start
        keep(result)
        var fingerprint = _fingerprint_c32_list(result)
        _record(invocation, elapsed, fingerprint, first, samples, checksum)
    return _finish("backend_ifft_f32", samples, checksum)


@no_inline
def _workload_simd_sum_f32(values: Span[Float32, ...]) raises -> UInt64:
    var samples = List[UInt64](capacity=_SAMPLES)
    var first = UInt64(0)
    var checksum = UInt64(1469598103934665603)
    for invocation in range(_FIXED_RUNS + _WARMUPS + _SAMPLES):
        var start = global_perf_counter_ns()
        var result = simd_sum_f32(values)
        var elapsed = global_perf_counter_ns() - start
        keep(result)
        var fingerprint = _fingerprint_f32(result)
        _record(invocation, elapsed, fingerprint, first, samples, checksum)
    return _finish("backend_simd_sum_f32", samples, checksum)


@no_inline
def _workload_simd_dot_f32(
    lhs: Span[Float32, ...], rhs: Span[Float32, ...]
) raises -> UInt64:
    var samples = List[UInt64](capacity=_SAMPLES)
    var first = UInt64(0)
    var checksum = UInt64(1469598103934665603)
    for invocation in range(_FIXED_RUNS + _WARMUPS + _SAMPLES):
        var start = global_perf_counter_ns()
        var result = simd_dot_f32(lhs, rhs)
        var elapsed = global_perf_counter_ns() - start
        keep(result)
        var fingerprint = _fingerprint_f32(result)
        _record(invocation, elapsed, fingerprint, first, samples, checksum)
    return _finish("backend_simd_dot_f32", samples, checksum)


@no_inline
def _workload_simd_energy_f32(values: Span[Float32, ...]) raises -> UInt64:
    var samples = List[UInt64](capacity=_SAMPLES)
    var first = UInt64(0)
    var checksum = UInt64(1469598103934665603)
    for invocation in range(_FIXED_RUNS + _WARMUPS + _SAMPLES):
        var start = global_perf_counter_ns()
        var result = simd_energy_f32(values)
        var elapsed = global_perf_counter_ns() - start
        keep(result)
        var fingerprint = _fingerprint_f32(result)
        _record(invocation, elapsed, fingerprint, first, samples, checksum)
    return _finish("backend_simd_energy_f32", samples, checksum)


@no_inline
def _workload_simd_complex_dot_split_f32(
    lhs_re: Span[Float32, ...],
    lhs_im: Span[Float32, ...],
    rhs_re: Span[Float32, ...],
    rhs_im: Span[Float32, ...],
) raises -> UInt64:
    var samples = List[UInt64](capacity=_SAMPLES)
    var first = UInt64(0)
    var checksum = UInt64(1469598103934665603)
    for invocation in range(_FIXED_RUNS + _WARMUPS + _SAMPLES):
        var start = global_perf_counter_ns()
        var result = simd_complex_dot_split_f32(
            lhs_re, lhs_im, rhs_re, rhs_im
        )
        var elapsed = global_perf_counter_ns() - start
        keep(result)
        var fingerprint = _fingerprint_c32(result)
        _record(invocation, elapsed, fingerprint, first, samples, checksum)
    return _finish("backend_simd_complex_dot_split_f32", samples, checksum)


@no_inline
def _workload_mimo_gram_f32(
    channel: Span[Complex32, ...], size: Int
) raises -> UInt64:
    var samples = List[UInt64](capacity=_SAMPLES)
    var first = UInt64(0)
    var checksum = UInt64(1469598103934665603)
    for invocation in range(_FIXED_RUNS + _WARMUPS + _SAMPLES):
        var start = global_perf_counter_ns()
        var result = mimo_gram_f32(channel, size)
        var elapsed = global_perf_counter_ns() - start
        keep(result)
        var fingerprint = _fingerprint_c32_list(result)
        _record(invocation, elapsed, fingerprint, first, samples, checksum)
    return _finish("backend_mimo_gram_f32", samples, checksum)


@no_inline
def _workload_mimo_gram_f32_into(
    channel: Span[Complex32, ...],
    size: Int,
    mut output: List[Complex32],
) raises -> UInt64:
    var samples = List[UInt64](capacity=_SAMPLES)
    var first = UInt64(0)
    var checksum = UInt64(1469598103934665603)
    for invocation in range(_FIXED_RUNS + _WARMUPS + _SAMPLES):
        var start = global_perf_counter_ns()
        mimo_gram_f32_into(channel, size, output)
        var elapsed = global_perf_counter_ns() - start
        keep(output)
        var fingerprint = _fingerprint_c32_list(output)
        _record(invocation, elapsed, fingerprint, first, samples, checksum)
    return _finish("backend_mimo_gram_f32_into", samples, checksum)


@no_inline
def _workload_mimo_matched_filter_f32(
    channel: Span[Complex32, ...],
    observation: Span[Complex32, ...],
    size: Int,
) raises -> UInt64:
    var samples = List[UInt64](capacity=_SAMPLES)
    var first = UInt64(0)
    var checksum = UInt64(1469598103934665603)
    for invocation in range(_FIXED_RUNS + _WARMUPS + _SAMPLES):
        var start = global_perf_counter_ns()
        var result = mimo_matched_filter_f32(channel, observation, size)
        var elapsed = global_perf_counter_ns() - start
        keep(result)
        var fingerprint = _fingerprint_c32_list(result)
        _record(invocation, elapsed, fingerprint, first, samples, checksum)
    return _finish("backend_mimo_matched_filter_f32", samples, checksum)


@no_inline
def _workload_mimo_matched_filter_f32_into(
    channel: Span[Complex32, ...],
    observation: Span[Complex32, ...],
    size: Int,
    mut output: List[Complex32],
) raises -> UInt64:
    var samples = List[UInt64](capacity=_SAMPLES)
    var first = UInt64(0)
    var checksum = UInt64(1469598103934665603)
    for invocation in range(_FIXED_RUNS + _WARMUPS + _SAMPLES):
        var start = global_perf_counter_ns()
        mimo_matched_filter_f32_into(
            channel, observation, size, output
        )
        var elapsed = global_perf_counter_ns() - start
        keep(output)
        var fingerprint = _fingerprint_c32_list(output)
        _record(invocation, elapsed, fingerprint, first, samples, checksum)
    return _finish(
        "backend_mimo_matched_filter_f32_into", samples, checksum
    )


@no_inline
def _workload_mimo_mmse_f32(
    channel: Span[Complex32, ...],
    observation: Span[Complex32, ...],
    size: Int,
    noise_variance: Float32,
) raises -> UInt64:
    var samples = List[UInt64](capacity=_SAMPLES)
    var first = UInt64(0)
    var checksum = UInt64(1469598103934665603)
    for invocation in range(_FIXED_RUNS + _WARMUPS + _SAMPLES):
        var start = global_perf_counter_ns()
        var result = mimo_mmse_f32(
            channel, observation, size, noise_variance
        )
        var elapsed = global_perf_counter_ns() - start
        keep(result)
        var fingerprint = _fingerprint_c32_list(result)
        _record(invocation, elapsed, fingerprint, first, samples, checksum)
    return _finish("backend_mimo_mmse_f32", samples, checksum)


@no_inline
def _workload_mimo_zf_f32(
    channel: Span[Complex32, ...],
    observation: Span[Complex32, ...],
    size: Int,
) raises -> UInt64:
    var samples = List[UInt64](capacity=_SAMPLES)
    var first = UInt64(0)
    var checksum = UInt64(1469598103934665603)
    for invocation in range(_FIXED_RUNS + _WARMUPS + _SAMPLES):
        var start = global_perf_counter_ns()
        var result = mimo_zf_f32(channel, observation, size)
        var elapsed = global_perf_counter_ns() - start
        keep(result)
        var fingerprint = _fingerprint_c32_list(result)
        _record(invocation, elapsed, fingerprint, first, samples, checksum)
    return _finish("backend_mimo_zf_f32", samples, checksum)


@no_inline
def _workload_hermitian(matrix: SmallComplexMatrix) raises -> UInt64:
    var samples = List[UInt64](capacity=_SAMPLES)
    var first = UInt64(0)
    var checksum = UInt64(1469598103934665603)
    for invocation in range(_FIXED_RUNS + _WARMUPS + _SAMPLES):
        var start = global_perf_counter_ns()
        var result = hermitian(matrix)
        var elapsed = global_perf_counter_ns() - start
        keep(result)
        var fingerprint = _fingerprint_matrix(result)
        _record(invocation, elapsed, fingerprint, first, samples, checksum)
    return _finish("backend_reference_hermitian", samples, checksum)


@no_inline
def _workload_matrix_multiply(
    lhs: SmallComplexMatrix, rhs: SmallComplexMatrix
) raises -> UInt64:
    var samples = List[UInt64](capacity=_SAMPLES)
    var first = UInt64(0)
    var checksum = UInt64(1469598103934665603)
    for invocation in range(_FIXED_RUNS + _WARMUPS + _SAMPLES):
        var start = global_perf_counter_ns()
        var result = matrix_multiply(lhs, rhs)
        var elapsed = global_perf_counter_ns() - start
        keep(result)
        var fingerprint = _fingerprint_matrix(result)
        _record(invocation, elapsed, fingerprint, first, samples, checksum)
    return _finish("backend_reference_matrix_multiply", samples, checksum)


@no_inline
def _workload_gram_matrix(matrix: SmallComplexMatrix) raises -> UInt64:
    var samples = List[UInt64](capacity=_SAMPLES)
    var first = UInt64(0)
    var checksum = UInt64(1469598103934665603)
    for invocation in range(_FIXED_RUNS + _WARMUPS + _SAMPLES):
        var start = global_perf_counter_ns()
        var result = gram_matrix(matrix)
        var elapsed = global_perf_counter_ns() - start
        keep(result)
        var fingerprint = _fingerprint_matrix(result)
        _record(invocation, elapsed, fingerprint, first, samples, checksum)
    return _finish("backend_reference_gram_matrix", samples, checksum)


@no_inline
def _workload_inverse(matrix: SmallComplexMatrix) raises -> UInt64:
    var samples = List[UInt64](capacity=_SAMPLES)
    var first = UInt64(0)
    var checksum = UInt64(1469598103934665603)
    for invocation in range(_FIXED_RUNS + _WARMUPS + _SAMPLES):
        var start = global_perf_counter_ns()
        var result = inverse(matrix)
        var elapsed = global_perf_counter_ns() - start
        keep(result)
        var fingerprint = _fingerprint_matrix(result)
        _record(invocation, elapsed, fingerprint, first, samples, checksum)
    return _finish("backend_reference_inverse", samples, checksum)


@no_inline
def _workload_cholesky(matrix: SmallComplexMatrix) raises -> UInt64:
    var samples = List[UInt64](capacity=_SAMPLES)
    var first = UInt64(0)
    var checksum = UInt64(1469598103934665603)
    for invocation in range(_FIXED_RUNS + _WARMUPS + _SAMPLES):
        var start = global_perf_counter_ns()
        var result = cholesky(matrix)
        var elapsed = global_perf_counter_ns() - start
        keep(result)
        var fingerprint = _fingerprint_matrix(result)
        _record(invocation, elapsed, fingerprint, first, samples, checksum)
    return _finish("backend_reference_cholesky", samples, checksum)


@no_inline
def _workload_qr_decompose(matrix: SmallComplexMatrix) raises -> UInt64:
    var samples = List[UInt64](capacity=_SAMPLES)
    var first = UInt64(0)
    var checksum = UInt64(1469598103934665603)
    for invocation in range(_FIXED_RUNS + _WARMUPS + _SAMPLES):
        var start = global_perf_counter_ns()
        var result = qr_decompose(matrix)
        var elapsed = global_perf_counter_ns() - start
        keep(result)
        var fingerprint = _mix(
            _fingerprint_matrix(result.q), _fingerprint_matrix(result.r)
        )
        _record(invocation, elapsed, fingerprint, first, samples, checksum)
    return _finish("backend_reference_qr_decompose", samples, checksum)


@no_inline
def _workload_fixed_dot_raw(
    lhs: Span[Int64, ...],
    rhs: Span[Int64, ...],
    lhs_format: QFormat,
    rhs_format: QFormat,
    accumulator_format: QFormat,
    output_format: QFormat,
) raises -> UInt64:
    var samples = List[UInt64](capacity=_SAMPLES)
    var first = UInt64(0)
    var checksum = UInt64(1469598103934665603)
    for invocation in range(_FIXED_RUNS + _WARMUPS + _SAMPLES):
        var start = global_perf_counter_ns()
        var result = fixed_dot_raw(
            lhs,
            rhs,
            lhs_format,
            rhs_format,
            accumulator_format,
            output_format,
        )
        var elapsed = global_perf_counter_ns() - start
        keep(result)
        var fingerprint = UInt64(result)
        _record(invocation, elapsed, fingerprint, first, samples, checksum)
    return _finish("backend_fixed_dot_raw", samples, checksum)


@no_inline
def _workload_complex_fir_raw(
    input_samples: Span[ComplexRaw, ...],
    taps: Span[ComplexRaw, ...],
    sample_format: QFormat,
    tap_format: QFormat,
    accumulator_format: QFormat,
    output_format: QFormat,
) raises -> UInt64:
    var samples = List[UInt64](capacity=_SAMPLES)
    var first = UInt64(0)
    var checksum = UInt64(1469598103934665603)
    for invocation in range(_FIXED_RUNS + _WARMUPS + _SAMPLES):
        var start = global_perf_counter_ns()
        var result = complex_fir_raw(
            input_samples,
            taps,
            sample_format,
            tap_format,
            accumulator_format,
            output_format,
        )
        var elapsed = global_perf_counter_ns() - start
        keep(result)
        var fingerprint = _fingerprint_raw_list(result)
        _record(invocation, elapsed, fingerprint, first, samples, checksum)
    return _finish("backend_complex_fir_raw", samples, checksum)


@no_inline
def _workload_complex_dot_conjugate_raw(
    lhs: Span[ComplexRaw, ...],
    rhs: Span[ComplexRaw, ...],
    lhs_format: QFormat,
    rhs_format: QFormat,
    accumulator_format: QFormat,
    output_format: QFormat,
) raises -> UInt64:
    var samples = List[UInt64](capacity=_SAMPLES)
    var first = UInt64(0)
    var checksum = UInt64(1469598103934665603)
    for invocation in range(_FIXED_RUNS + _WARMUPS + _SAMPLES):
        var start = global_perf_counter_ns()
        var result = complex_dot_conjugate_raw(
            lhs,
            rhs,
            lhs_format,
            rhs_format,
            accumulator_format,
            output_format,
        )
        var elapsed = global_perf_counter_ns() - start
        keep(result)
        var fingerprint = _mix(UInt64(result.re), UInt64(result.im))
        _record(invocation, elapsed, fingerprint, first, samples, checksum)
    return _finish("backend_complex_dot_conjugate_raw", samples, checksum)


@no_inline
def _workload_complex_cross_correlate_raw(
    signal: Span[ComplexRaw, ...],
    reference: Span[ComplexRaw, ...],
    signal_format: QFormat,
    reference_format: QFormat,
    accumulator_format: QFormat,
    output_format: QFormat,
) raises -> UInt64:
    var samples = List[UInt64](capacity=_SAMPLES)
    var first = UInt64(0)
    var checksum = UInt64(1469598103934665603)
    for invocation in range(_FIXED_RUNS + _WARMUPS + _SAMPLES):
        var start = global_perf_counter_ns()
        var result = complex_cross_correlate_raw(
            signal,
            reference,
            signal_format,
            reference_format,
            accumulator_format,
            output_format,
        )
        var elapsed = global_perf_counter_ns() - start
        keep(result)
        var fingerprint = _fingerprint_raw_list(result)
        _record(invocation, elapsed, fingerprint, first, samples, checksum)
    return _finish("backend_complex_cross_correlate_raw", samples, checksum)


@no_inline
def _workload_fixed_qpsk_map_raw(
    bits: Span[UInt8, ...], qformat: QFormat, amplitude_raw: Int64
) raises -> UInt64:
    var samples = List[UInt64](capacity=_SAMPLES)
    var first = UInt64(0)
    var checksum = UInt64(1469598103934665603)
    for invocation in range(_FIXED_RUNS + _WARMUPS + _SAMPLES):
        var start = global_perf_counter_ns()
        var result = fixed_qpsk_map_raw(bits, qformat, amplitude_raw)
        var elapsed = global_perf_counter_ns() - start
        keep(result)
        var fingerprint = _fingerprint_raw_list(result)
        _record(invocation, elapsed, fingerprint, first, samples, checksum)
    return _finish("backend_fixed_qpsk_map_raw", samples, checksum)


@no_inline
def _workload_fixed_qpsk_hard_bits(
    symbols: Span[ComplexRaw, ...], qformat: QFormat
) raises -> UInt64:
    var samples = List[UInt64](capacity=_SAMPLES)
    var first = UInt64(0)
    var checksum = UInt64(1469598103934665603)
    for invocation in range(_FIXED_RUNS + _WARMUPS + _SAMPLES):
        var start = global_perf_counter_ns()
        var result = fixed_qpsk_hard_bits(symbols, qformat)
        var elapsed = global_perf_counter_ns() - start
        keep(result)
        var fingerprint = _fingerprint_u8_list(result)
        _record(invocation, elapsed, fingerprint, first, samples, checksum)
    return _finish("backend_fixed_qpsk_hard_bits", samples, checksum)


@no_inline
def _workload_fixed_qpsk_llrs_raw(
    symbols: Span[ComplexRaw, ...],
    input_format: QFormat,
    output_format: QFormat,
) raises -> UInt64:
    var samples = List[UInt64](capacity=_SAMPLES)
    var first = UInt64(0)
    var checksum = UInt64(1469598103934665603)
    for invocation in range(_FIXED_RUNS + _WARMUPS + _SAMPLES):
        var start = global_perf_counter_ns()
        var result = fixed_qpsk_llrs_raw(
            symbols, input_format, output_format
        )
        var elapsed = global_perf_counter_ns() - start
        keep(result)
        var fingerprint = _fingerprint_i64_list(result)
        _record(invocation, elapsed, fingerprint, first, samples, checksum)
    return _finish("backend_fixed_qpsk_llrs_raw", samples, checksum)


@no_inline
def _workload_fixed_ofdm_modulate_raw(
    spectrum: Span[ComplexRaw, ...],
    spectrum_format: QFormat,
    time_format: QFormat,
    twiddle_format: QFormat,
    cyclic_prefix: Int,
) raises -> UInt64:
    var samples = List[UInt64](capacity=_SAMPLES)
    var first = UInt64(0)
    var checksum = UInt64(1469598103934665603)
    for invocation in range(_FIXED_RUNS + _WARMUPS + _SAMPLES):
        var start = global_perf_counter_ns()
        var result = fixed_ofdm_modulate_raw(
            spectrum,
            spectrum_format,
            time_format,
            twiddle_format,
            cyclic_prefix,
        )
        var elapsed = global_perf_counter_ns() - start
        keep(result)
        var fingerprint = _fingerprint_raw_list(result)
        _record(invocation, elapsed, fingerprint, first, samples, checksum)
    return _finish("backend_fixed_ofdm_modulate_raw", samples, checksum)


@no_inline
def _workload_fixed_ofdm_demodulate_raw(
    input_samples: Span[ComplexRaw, ...],
    transform_size: Int,
    cyclic_prefix: Int,
    time_format: QFormat,
    frequency_format: QFormat,
    twiddle_format: QFormat,
) raises -> UInt64:
    var samples = List[UInt64](capacity=_SAMPLES)
    var first = UInt64(0)
    var checksum = UInt64(1469598103934665603)
    for invocation in range(_FIXED_RUNS + _WARMUPS + _SAMPLES):
        var start = global_perf_counter_ns()
        var result = fixed_ofdm_demodulate_raw(
            input_samples,
            transform_size,
            cyclic_prefix,
            time_format,
            frequency_format,
            twiddle_format,
        )
        var elapsed = global_perf_counter_ns() - start
        keep(result)
        var fingerprint = _fingerprint_raw_list(result)
        _record(invocation, elapsed, fingerprint, first, samples, checksum)
    return _finish("backend_fixed_ofdm_demodulate_raw", samples, checksum)


@no_inline
def _workload_fixed_flat_channel_raw(
    input_samples: Span[ComplexRaw, ...],
    sample_format: QFormat,
    channel: ComplexRaw,
    channel_format: QFormat,
    output_format: QFormat,
) raises -> UInt64:
    var samples = List[UInt64](capacity=_SAMPLES)
    var first = UInt64(0)
    var checksum = UInt64(1469598103934665603)
    for invocation in range(_FIXED_RUNS + _WARMUPS + _SAMPLES):
        var start = global_perf_counter_ns()
        var result = fixed_flat_channel_raw(
            input_samples,
            sample_format,
            channel,
            channel_format,
            output_format,
        )
        var elapsed = global_perf_counter_ns() - start
        keep(result)
        var fingerprint = _fingerprint_raw_list(result)
        _record(invocation, elapsed, fingerprint, first, samples, checksum)
    return _finish("backend_fixed_flat_channel_raw", samples, checksum)


@no_inline
def _workload_fixed_ls_flat_channel_raw(
    received: Span[ComplexRaw, ...],
    references: Span[ComplexRaw, ...],
    received_format: QFormat,
    reference_format: QFormat,
    accumulator_format: QFormat,
    reciprocal_format: QFormat,
    output_format: QFormat,
) raises -> UInt64:
    var samples = List[UInt64](capacity=_SAMPLES)
    var first = UInt64(0)
    var checksum = UInt64(1469598103934665603)
    for invocation in range(_FIXED_RUNS + _WARMUPS + _SAMPLES):
        var start = global_perf_counter_ns()
        var result = fixed_ls_flat_channel_raw(
            received,
            references,
            received_format,
            reference_format,
            accumulator_format,
            reciprocal_format,
            output_format,
        )
        var elapsed = global_perf_counter_ns() - start
        keep(result)
        var fingerprint = _mix(UInt64(result.re), UInt64(result.im))
        _record(invocation, elapsed, fingerprint, first, samples, checksum)
    return _finish("backend_fixed_ls_flat_channel_raw", samples, checksum)


@no_inline
def _workload_fixed_equalize_flat_raw(
    received: Span[ComplexRaw, ...],
    received_format: QFormat,
    channel_estimate: ComplexRaw,
    channel_format: QFormat,
    accumulator_format: QFormat,
    reciprocal_format: QFormat,
    output_format: QFormat,
) raises -> UInt64:
    var samples = List[UInt64](capacity=_SAMPLES)
    var first = UInt64(0)
    var checksum = UInt64(1469598103934665603)
    for invocation in range(_FIXED_RUNS + _WARMUPS + _SAMPLES):
        var start = global_perf_counter_ns()
        var result = fixed_equalize_flat_raw(
            received,
            received_format,
            channel_estimate,
            channel_format,
            accumulator_format,
            reciprocal_format,
            output_format,
        )
        var elapsed = global_perf_counter_ns() - start
        keep(result)
        var fingerprint = _fingerprint_raw_list(result)
        _record(invocation, elapsed, fingerprint, first, samples, checksum)
    return _finish("backend_fixed_equalize_flat_raw", samples, checksum)


@no_inline
def _workload_fixed_reciprocal_positive_raw(
    value_raw: Int64,
    input_format: QFormat,
    output_format: QFormat,
) raises -> UInt64:
    var samples = List[UInt64](capacity=_SAMPLES)
    var first = UInt64(0)
    var checksum = UInt64(1469598103934665603)
    for invocation in range(_FIXED_RUNS + _WARMUPS + _SAMPLES):
        var start = global_perf_counter_ns()
        var result = fixed_reciprocal_positive_raw(
            value_raw, input_format, output_format
        )
        var elapsed = global_perf_counter_ns() - start
        keep(result)
        var fingerprint = UInt64(result)
        _record(invocation, elapsed, fingerprint, first, samples, checksum)
    return _finish("backend_fixed_reciprocal_positive_raw", samples, checksum)


@no_inline
def _workload_fixed_hermitian_gram_2x2_raw(
    channel: Span[ComplexRaw, ...],
    channel_format: QFormat,
    accumulator_format: QFormat,
    output_format: QFormat,
) raises -> UInt64:
    var samples = List[UInt64](capacity=_SAMPLES)
    var first = UInt64(0)
    var checksum = UInt64(1469598103934665603)
    for invocation in range(_FIXED_RUNS + _WARMUPS + _SAMPLES):
        var start = global_perf_counter_ns()
        var result = fixed_hermitian_gram_2x2_raw(
            channel, channel_format, accumulator_format, output_format
        )
        var elapsed = global_perf_counter_ns() - start
        keep(result)
        var fingerprint = _fingerprint_raw_list(result)
        _record(invocation, elapsed, fingerprint, first, samples, checksum)
    return _finish("backend_fixed_hermitian_gram_2x2_raw", samples, checksum)


@no_inline
def _workload_fixed_hermitian_matched_filter_2x2_raw(
    channel: Span[ComplexRaw, ...],
    observation: Span[ComplexRaw, ...],
    channel_format: QFormat,
    observation_format: QFormat,
    accumulator_format: QFormat,
    output_format: QFormat,
) raises -> UInt64:
    var samples = List[UInt64](capacity=_SAMPLES)
    var first = UInt64(0)
    var checksum = UInt64(1469598103934665603)
    for invocation in range(_FIXED_RUNS + _WARMUPS + _SAMPLES):
        var start = global_perf_counter_ns()
        var result = fixed_hermitian_matched_filter_2x2_raw(
            channel,
            observation,
            channel_format,
            observation_format,
            accumulator_format,
            output_format,
        )
        var elapsed = global_perf_counter_ns() - start
        keep(result)
        var fingerprint = _fingerprint_raw_list(result)
        _record(invocation, elapsed, fingerprint, first, samples, checksum)
    return _finish(
        "backend_fixed_hermitian_matched_filter_2x2_raw", samples, checksum
    )


@no_inline
def _workload_fixed_mimo_reciprocal_positive_raw(
    value_raw: Int64,
    input_format: QFormat,
    output_format: QFormat,
) raises -> UInt64:
    var samples = List[UInt64](capacity=_SAMPLES)
    var first = UInt64(0)
    var checksum = UInt64(1469598103934665603)
    for invocation in range(_FIXED_RUNS + _WARMUPS + _SAMPLES):
        var start = global_perf_counter_ns()
        var result = fixed_mimo_reciprocal_positive_raw(
            value_raw, input_format, output_format
        )
        var elapsed = global_perf_counter_ns() - start
        keep(result)
        var fingerprint = UInt64(result)
        _record(invocation, elapsed, fingerprint, first, samples, checksum)
    return _finish(
        "backend_fixed_mimo_reciprocal_positive_raw", samples, checksum
    )


@no_inline
def _workload_fixed_window_energy_raw(
    input_samples: Span[ComplexRaw, ...],
    offset: Int,
    window: Int,
    sample_format: QFormat,
    accumulator_format: QFormat,
    output_format: QFormat,
) raises -> UInt64:
    var samples = List[UInt64](capacity=_SAMPLES)
    var first = UInt64(0)
    var checksum = UInt64(1469598103934665603)
    for invocation in range(_FIXED_RUNS + _WARMUPS + _SAMPLES):
        var start = global_perf_counter_ns()
        var result = fixed_window_energy_raw(
            input_samples,
            offset,
            window,
            sample_format,
            accumulator_format,
            output_format,
        )
        var elapsed = global_perf_counter_ns() - start
        keep(result)
        var fingerprint = UInt64(result)
        _record(invocation, elapsed, fingerprint, first, samples, checksum)
    return _finish("backend_fixed_window_energy_raw", samples, checksum)


@no_inline
def _workload_fixed_repetition_correlation_raw(
    input_samples: Span[ComplexRaw, ...],
    offset: Int,
    period: Int,
    window: Int,
    sample_format: QFormat,
    accumulator_format: QFormat,
    output_format: QFormat,
) raises -> UInt64:
    var samples = List[UInt64](capacity=_SAMPLES)
    var first = UInt64(0)
    var checksum = UInt64(1469598103934665603)
    for invocation in range(_FIXED_RUNS + _WARMUPS + _SAMPLES):
        var start = global_perf_counter_ns()
        var result = fixed_repetition_correlation_raw(
            input_samples,
            offset,
            period,
            window,
            sample_format,
            accumulator_format,
            output_format,
        )
        var elapsed = global_perf_counter_ns() - start
        keep(result)
        var fingerprint = _mix(UInt64(result.re), UInt64(result.im))
        _record(invocation, elapsed, fingerprint, first, samples, checksum)
    return _finish(
        "backend_fixed_repetition_correlation_raw", samples, checksum
    )


@no_inline
def _workload_fixed_wifi_bcc_hard_llrs_raw(
    coded_bits: Span[UInt8, ...],
    reliability_raw: Int64,
    llr_format: QFormat,
) raises -> UInt64:
    var samples = List[UInt64](capacity=_SAMPLES)
    var first = UInt64(0)
    var checksum = UInt64(1469598103934665603)
    for invocation in range(_FIXED_RUNS + _WARMUPS + _SAMPLES):
        var start = global_perf_counter_ns()
        var result = fixed_wifi_bcc_hard_llrs_raw(
            coded_bits, reliability_raw, llr_format
        )
        var elapsed = global_perf_counter_ns() - start
        keep(result)
        var fingerprint = _fingerprint_i64_list(result)
        _record(invocation, elapsed, fingerprint, first, samples, checksum)
    return _finish("backend_fixed_wifi_bcc_hard_llrs_raw", samples, checksum)


def benchmark_cpu_practical_and_simd() raises -> UInt64:
    var values = List[Complex32](capacity=64)
    var signal = List[Float32](capacity=128)
    for index in range(128):
        signal.append(Float32((17 * index + 3) % 101) / 50.0 - 1.0)
        if index < 64:
            values.append(Complex32(
                signal[index],
                Float32((11 * index + 5) % 97) / 48.0 - 1.0,
            ))
    var taps: List[Float32] = [0.125, -0.25, 0.5, -0.25, 0.125]
    var batch = values.copy()
    for value in values:
        batch.append(value)
    var lhs_re = List[Float32](capacity=64)
    var lhs_im = List[Float32](capacity=64)
    for value in values:
        lhs_re.append(value.re)
        lhs_im.append(value.im)
    var rhs_re = lhs_re.copy()
    var rhs_im = lhs_im.copy()
    var signal_rhs = signal.copy()
    var values_span = Span(values)
    var batch_span = Span(batch)
    var signal_span = Span(signal)
    var signal_rhs_span = Span(signal_rhs)
    var taps_span = Span(taps)
    var lhs_re_span = Span(lhs_re)
    var lhs_im_span = Span(lhs_im)
    var rhs_re_span = Span(rhs_re)
    var rhs_im_span = Span(rhs_im)
    var plan = make_fft_plan_f32(64)
    var checksum = _workload_fft_batch_f32(batch_span, 64)
    checksum ^= _workload_fft_f32(values_span)
    checksum ^= _workload_fft_in_place_f32_with_plan(values_span, plan)
    checksum ^= _workload_fir_real_f32(signal_span, taps_span)
    checksum ^= _workload_ifft_f32(values_span)
    checksum ^= _workload_simd_sum_f32(signal_span)
    checksum ^= _workload_simd_dot_f32(signal_span, signal_rhs_span)
    checksum ^= _workload_simd_energy_f32(signal_span)
    checksum ^= _workload_simd_complex_dot_split_f32(
        lhs_re_span, lhs_im_span, rhs_re_span, rhs_im_span
    )
    keep(plan)
    keep(checksum)
    print("backend_cpu_practical_simd_retained_checksum:", checksum)
    return checksum


def benchmark_cpu_mimo() raises -> UInt64:
    comptime size = 2
    var channel: List[Complex32] = [
        Complex32(1.0, 0.0),
        Complex32(0.5, 0.25),
        Complex32(-0.25, 0.5),
        Complex32(1.5, -0.25),
    ]
    var observation: List[Complex32] = [
        Complex32(0.75, -0.3), Complex32(-1.2, 0.85)
    ]
    var channel_span = Span(channel)
    var observation_span = Span(observation)
    var gram = List[Complex32](
        length=4, fill=Complex32(0.0, 0.0)
    )
    var matched = List[Complex32](
        length=2, fill=Complex32(0.0, 0.0)
    )
    var checksum = _workload_mimo_gram_f32(channel_span, size)
    checksum ^= _workload_mimo_gram_f32_into(
        channel_span, size, gram
    )
    checksum ^= _workload_mimo_matched_filter_f32(
        channel_span, observation_span, size
    )
    checksum ^= _workload_mimo_matched_filter_f32_into(
        channel_span, observation_span, size, matched
    )
    checksum ^= _workload_mimo_zf_f32(
        channel_span, observation_span, size
    )
    checksum ^= _workload_mimo_mmse_f32(
        channel_span, observation_span, size, Float32(0.17)
    )
    keep(gram)
    keep(matched)
    keep(checksum)
    print("backend_cpu_mimo_retained_checksum:", checksum)
    return checksum


def _make_matrix() raises -> SmallComplexMatrix:
    var result = SmallComplexMatrix(2, 2)
    result[0, 0] = Complex64(1.0, 0.0)
    result[0, 1] = Complex64(0.5, 0.25)
    result[1, 0] = Complex64(-0.25, 0.5)
    result[1, 1] = Complex64(1.5, -0.25)
    return result^


def benchmark_reference_mimo() raises -> UInt64:
    var channel = _make_matrix()
    var channel_h = hermitian(channel)
    var gram = gram_matrix(channel)
    var checksum = _workload_hermitian(channel)
    checksum ^= _workload_matrix_multiply(channel_h, channel)
    checksum ^= _workload_gram_matrix(channel)
    checksum ^= _workload_inverse(channel)
    checksum ^= _workload_cholesky(gram)
    checksum ^= _workload_qr_decompose(channel)
    keep(channel_h)
    keep(gram)
    keep(checksum)
    print("backend_reference_mimo_retained_checksum:", checksum)
    return checksum


def benchmark_fixed_arithmetic_phy_mimo() raises -> UInt64:
    var q4 = QFormat(8, 4)
    var accumulator = QFormat(20, 8)
    var dot_lhs: List[Int64] = [16, 32]
    var dot_rhs: List[Int64] = [8, 8]
    var complex_values: List[ComplexRaw] = [
        ComplexRaw(16, 16),
        ComplexRaw(32, 0),
        ComplexRaw(-16, 8),
    ]
    var complex_taps: List[ComplexRaw] = [ComplexRaw(0, 16)]
    var complex_dot_lhs: List[ComplexRaw] = [ComplexRaw(16, 16)]
    var complex_dot_rhs: List[ComplexRaw] = [ComplexRaw(0, 16)]
    var dot_lhs_span = Span(dot_lhs)
    var dot_rhs_span = Span(dot_rhs)
    var complex_values_span = Span(complex_values)
    var complex_taps_span = Span(complex_taps)
    var complex_dot_lhs_span = Span(complex_dot_lhs)
    var complex_dot_rhs_span = Span(complex_dot_rhs)

    var formats = fixed_phy_default_formats()
    var bits: List[UInt8] = [0, 0, 0, 1, 1, 0, 1, 1]
    var bits_span = Span(bits)
    var mapped = fixed_qpsk_map_raw(bits_span, formats.symbol, 8192)
    var mapped_span = Span(mapped)
    var waveform = fixed_ofdm_modulate_raw(
        mapped_span,
        formats.symbol,
        formats.time,
        formats.twiddle,
        1,
    )
    var waveform_span = Span(waveform)
    var demodulated = fixed_ofdm_demodulate_raw(
        waveform_span,
        4,
        1,
        formats.time,
        formats.frequency,
        formats.twiddle,
    )
    var demodulated_span = Span(demodulated)
    var pilot_received: List[ComplexRaw] = [demodulated[0]]
    var pilot_reference: List[ComplexRaw] = [mapped[0]]
    var pilot_received_span = Span(pilot_received)
    var pilot_reference_span = Span(pilot_reference)
    var estimate = fixed_ls_flat_channel_raw(
        pilot_received_span,
        pilot_reference_span,
        formats.frequency,
        formats.symbol,
        formats.accumulator,
        formats.reciprocal,
        formats.channel,
    )

    var mimo_formats = fixed_mimo_default_formats()
    var mimo_channel: List[ComplexRaw] = [
        ComplexRaw(4096, 0),
        ComplexRaw(),
        ComplexRaw(),
        ComplexRaw(4096, 0),
    ]
    var mimo_symbols: List[ComplexRaw] = [
        ComplexRaw(1024, -512), ComplexRaw(-768, 256)
    ]
    var mimo_channel_span = Span(mimo_channel)
    var mimo_symbols_span = Span(mimo_symbols)
    var mimo_observation = fixed_complex_matvec_2x2_raw(
        mimo_channel_span,
        mimo_symbols_span,
        mimo_formats.channel,
        mimo_formats.symbol,
        mimo_formats.accumulator,
        mimo_formats.observation,
    )
    var mimo_observation_span = Span(mimo_observation)
    var determinant_format = fixed_mimo_determinant_format(mimo_formats)

    var checksum = _workload_fixed_dot_raw(
        dot_lhs_span, dot_rhs_span, q4, q4, accumulator, q4
    )
    checksum ^= _workload_complex_fir_raw(
        complex_values_span,
        complex_taps_span,
        q4,
        q4,
        accumulator,
        q4,
    )
    checksum ^= _workload_complex_dot_conjugate_raw(
        complex_dot_lhs_span,
        complex_dot_rhs_span,
        q4,
        q4,
        accumulator,
        q4,
    )
    checksum ^= _workload_complex_cross_correlate_raw(
        complex_values_span,
        complex_taps_span,
        q4,
        q4,
        accumulator,
        q4,
    )
    checksum ^= _workload_fixed_qpsk_map_raw(
        bits_span, formats.symbol, 8192
    )
    checksum ^= _workload_fixed_qpsk_hard_bits(
        mapped_span, formats.symbol
    )
    checksum ^= _workload_fixed_qpsk_llrs_raw(
        mapped_span, formats.symbol, formats.symbol
    )
    checksum ^= _workload_fixed_ofdm_modulate_raw(
        mapped_span,
        formats.symbol,
        formats.time,
        formats.twiddle,
        1,
    )
    checksum ^= _workload_fixed_ofdm_demodulate_raw(
        waveform_span,
        4,
        1,
        formats.time,
        formats.frequency,
        formats.twiddle,
    )
    checksum ^= _workload_fixed_flat_channel_raw(
        waveform_span,
        formats.time,
        ComplexRaw(16384, 0),
        formats.channel,
        formats.time,
    )
    checksum ^= _workload_fixed_ls_flat_channel_raw(
        pilot_received_span,
        pilot_reference_span,
        formats.frequency,
        formats.symbol,
        formats.accumulator,
        formats.reciprocal,
        formats.channel,
    )
    checksum ^= _workload_fixed_equalize_flat_raw(
        demodulated_span,
        formats.frequency,
        estimate,
        formats.channel,
        formats.accumulator,
        formats.reciprocal,
        formats.symbol,
    )
    checksum ^= _workload_fixed_reciprocal_positive_raw(
        Int64(1 << 20), formats.accumulator, formats.reciprocal
    )
    checksum ^= _workload_fixed_hermitian_gram_2x2_raw(
        mimo_channel_span,
        mimo_formats.channel,
        mimo_formats.accumulator,
        mimo_formats.gram,
    )
    checksum ^= _workload_fixed_hermitian_matched_filter_2x2_raw(
        mimo_channel_span,
        mimo_observation_span,
        mimo_formats.channel,
        mimo_formats.observation,
        mimo_formats.accumulator,
        mimo_formats.matched,
    )
    checksum ^= _workload_fixed_mimo_reciprocal_positive_raw(
        Int64(1 << 24), determinant_format, mimo_formats.reciprocal
    )
    keep(mapped)
    keep(waveform)
    keep(demodulated)
    keep(mimo_observation)
    keep(checksum)
    print("backend_fixed_arithmetic_phy_mimo_retained_checksum:", checksum)
    return checksum


def benchmark_fixed_sync_wifi_fec() raises -> UInt64:
    var sample_format = QFormat(8, 4)
    var accumulator_format = QFormat(24, 8)
    var output_format = QFormat(16, 8)
    var input_samples: List[ComplexRaw] = [
        ComplexRaw(16, 0),
        ComplexRaw(0, 16),
        ComplexRaw(-16, 0),
        ComplexRaw(0, -16),
        ComplexRaw(16, 0),
        ComplexRaw(0, 16),
        ComplexRaw(-16, 0),
        ComplexRaw(0, -16),
    ]
    var input_span = Span(input_samples)
    var payload: List[UInt8] = [1, 0, 1, 1, 0, 0, 1, 0]
    var payload_span = Span(payload)
    var coded = fixed_wifi_bcc_encode(payload_span)
    var coded_span = Span(coded)
    var llr_format = QFormat(8, 0)
    var checksum = _workload_fixed_window_energy_raw(
        input_span,
        0,
        4,
        sample_format,
        accumulator_format,
        output_format,
    )
    checksum ^= _workload_fixed_repetition_correlation_raw(
        input_span,
        0,
        4,
        4,
        sample_format,
        accumulator_format,
        output_format,
    )
    checksum ^= _workload_fixed_wifi_bcc_hard_llrs_raw(
        coded_span, 7, llr_format
    )
    keep(coded)
    keep(checksum)
    print("backend_fixed_sync_wifi_fec_retained_checksum:", checksum)
    return checksum


def main() raises:
    print_benchmark_metadata()
    var alignment_probe = List[Complex32](
        length=64, fill=Complex32(0.0, 0.0)
    )
    print_runtime_buffer_alignment(
        "backend_evidence_complex32_probe",
        Int(alignment_probe.unsafe_ptr()),
        align_of[Complex32](),
    )
    var checksum = benchmark_cpu_practical_and_simd()
    checksum ^= benchmark_cpu_mimo()
    checksum ^= benchmark_reference_mimo()
    checksum ^= benchmark_fixed_arithmetic_phy_mimo()
    checksum ^= benchmark_fixed_sync_wifi_fec()
    keep(checksum)
    print("backend_evidence_combined_retained_checksum:", checksum)
