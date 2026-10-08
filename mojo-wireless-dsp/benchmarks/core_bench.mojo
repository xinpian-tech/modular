"""Attributable latency baselines for core complex methods and buffer views.

Every label has two untimed warmups and nine independent samples.  Inputs are
constructed before timing; output-dependent retained checksums make every
method and every representative view load/store observable.
"""

from std.benchmark import keep
from std.collections import Span
from std.time import global_perf_counter_ns
from wireless_dsp.benchmarking import (
    print_benchmark_metadata,
    report_timing_samples,
)
from wireless_dsp.core import (
    BitSpan,
    Complex64,
    ComplexSpan,
    LLRBuffer,
    MatrixView,
    SplitComplexSpan,
    complex_mac,
)


comptime _WARMUPS = 3
comptime _SAMPLES = 9
comptime _COMPLEX_OPERATIONS = 8_192
comptime _VIEW_OPERATIONS = 4_096


def _complex_add_batch(
    lhs: Span[Complex64, ...], rhs: Span[Complex64, ...]
) -> Float64:
    var checksum = 0.0
    for index in range(len(lhs)):
        var left = Complex64(lhs[index].re, lhs[index].im)
        var right = Complex64(rhs[index].re, rhs[index].im)
        var value = left + right
        checksum += value.re + 3.0 * value.im
    return checksum


def _complex_sub_batch(
    lhs: Span[Complex64, ...], rhs: Span[Complex64, ...]
) -> Float64:
    var checksum = 0.0
    for index in range(len(lhs)):
        var left = Complex64(lhs[index].re, lhs[index].im)
        var right = Complex64(rhs[index].re, rhs[index].im)
        var value = left - right
        checksum += value.re + 3.0 * value.im
    return checksum


def _complex_mul_batch(
    lhs: Span[Complex64, ...], rhs: Span[Complex64, ...]
) -> Float64:
    var checksum = 0.0
    for index in range(len(lhs)):
        var left = Complex64(lhs[index].re, lhs[index].im)
        var right = Complex64(rhs[index].re, rhs[index].im)
        var value = left * right
        checksum += value.re + 3.0 * value.im
    return checksum


def _complex_conjugate_batch(values: Span[Complex64, ...]) -> Float64:
    var checksum = 0.0
    for index in range(len(values)):
        var source = Complex64(values[index].re, values[index].im)
        var value = source.conjugate()
        checksum += value.re + 3.0 * value.im
    return checksum


def _complex_mac_batch(
    lhs: Span[Complex64, ...], rhs: Span[Complex64, ...]
) -> Float64:
    var checksum = 0.0
    var accumulator = Complex64(0.125, -0.25)
    for index in range(len(lhs)):
        var left = Complex64(lhs[index].re, lhs[index].im)
        var right = Complex64(rhs[index].re, rhs[index].im)
        var value = complex_mac(accumulator, left, right)
        checksum += value.re + 3.0 * value.im
        accumulator = Complex64(
            0.125 + Float64(index % 7) * 1.0e-5,
            -0.25 + Float64(index % 11) * 1.0e-5,
        )
    return checksum


def _complex_magnitude_batch(values: Span[Complex64, ...]) -> Float64:
    var checksum = 0.0
    for index in range(len(values)):
        var source = Complex64(values[index].re, values[index].im)
        checksum += source.magnitude()
    return checksum


def _complex_magnitude_squared_batch(
    values: Span[Complex64, ...],
) -> Float64:
    var checksum = 0.0
    for index in range(len(values)):
        var source = Complex64(values[index].re, values[index].im)
        checksum += source.magnitude_squared()
    return checksum


def _complex_normalized_batch(
    values: Span[Complex64, ...],
) raises -> Float64:
    var checksum = 0.0
    for index in range(len(values)):
        var source = Complex64(values[index].re, values[index].im)
        var value = source.normalized()
        checksum += value.re + 3.0 * value.im
    return checksum


def _benchmark_complex_methods() raises -> Float64:
    var lhs = List[Complex64](capacity=_COMPLEX_OPERATIONS)
    var rhs = List[Complex64](capacity=_COMPLEX_OPERATIONS)
    for index in range(_COMPLEX_OPERATIONS):
        lhs.append(
            Complex64(
                Float64((17 * index + 3) % 101) / 51.0 - 0.98,
                Float64((29 * index + 7) % 103) / 52.0 - 0.98,
            )
        )
        rhs.append(
            Complex64(
                Float64((31 * index + 5) % 107) / 54.0 - 0.98,
                Float64((23 * index + 11) % 109) / 55.0 - 0.98,
            )
        )

    for _ in range(_WARMUPS):
        keep(_complex_add_batch(Span(lhs), Span(rhs)))
        keep(_complex_sub_batch(Span(lhs), Span(rhs)))
        keep(_complex_mul_batch(Span(lhs), Span(rhs)))
        keep(_complex_conjugate_batch(Span(lhs)))
        keep(_complex_mac_batch(Span(lhs), Span(rhs)))
        keep(_complex_magnitude_batch(Span(lhs)))
        keep(_complex_magnitude_squared_batch(Span(lhs)))
        keep(_complex_normalized_batch(Span(lhs)))

    var add_samples = List[UInt64](capacity=_SAMPLES)
    var sub_samples = List[UInt64](capacity=_SAMPLES)
    var mul_samples = List[UInt64](capacity=_SAMPLES)
    var conjugate_samples = List[UInt64](capacity=_SAMPLES)
    var mac_samples = List[UInt64](capacity=_SAMPLES)
    var magnitude_samples = List[UInt64](capacity=_SAMPLES)
    var magnitude_squared_samples = List[UInt64](capacity=_SAMPLES)
    var normalized_samples = List[UInt64](capacity=_SAMPLES)
    var checksum = 0.0
    for repetition in range(_SAMPLES):
        var start = global_perf_counter_ns()
        var retained = _complex_add_batch(Span(lhs), Span(rhs))
        add_samples.append(global_perf_counter_ns() - start)
        keep(retained)
        checksum += retained * Float64(repetition + 1)

        start = global_perf_counter_ns()
        retained = _complex_sub_batch(Span(lhs), Span(rhs))
        sub_samples.append(global_perf_counter_ns() - start)
        keep(retained)
        checksum += retained * Float64(repetition + 3)

        start = global_perf_counter_ns()
        retained = _complex_mul_batch(Span(lhs), Span(rhs))
        mul_samples.append(global_perf_counter_ns() - start)
        keep(retained)
        checksum += retained * Float64(repetition + 5)

        start = global_perf_counter_ns()
        retained = _complex_conjugate_batch(Span(lhs))
        conjugate_samples.append(global_perf_counter_ns() - start)
        keep(retained)
        checksum += retained * Float64(repetition + 7)

        start = global_perf_counter_ns()
        retained = _complex_mac_batch(Span(lhs), Span(rhs))
        mac_samples.append(global_perf_counter_ns() - start)
        keep(retained)
        checksum += retained * Float64(repetition + 9)

        start = global_perf_counter_ns()
        retained = _complex_magnitude_batch(Span(lhs))
        magnitude_samples.append(global_perf_counter_ns() - start)
        keep(retained)
        checksum += retained * Float64(repetition + 11)

        start = global_perf_counter_ns()
        retained = _complex_magnitude_squared_batch(Span(lhs))
        magnitude_squared_samples.append(global_perf_counter_ns() - start)
        keep(retained)
        checksum += retained * Float64(repetition + 13)

        start = global_perf_counter_ns()
        retained = _complex_normalized_batch(Span(lhs))
        normalized_samples.append(global_perf_counter_ns() - start)
        keep(retained)
        checksum += retained * Float64(repetition + 15)

    report_timing_samples(
        "core_complex_add", add_samples, _WARMUPS, _COMPLEX_OPERATIONS
    )
    report_timing_samples(
        "core_complex_sub", sub_samples, _WARMUPS, _COMPLEX_OPERATIONS
    )
    report_timing_samples(
        "core_complex_mul", mul_samples, _WARMUPS, _COMPLEX_OPERATIONS
    )
    report_timing_samples(
        "core_complex_conjugate",
        conjugate_samples,
        _WARMUPS,
        _COMPLEX_OPERATIONS,
    )
    report_timing_samples(
        "core_complex_mac", mac_samples, _WARMUPS, _COMPLEX_OPERATIONS
    )
    report_timing_samples(
        "core_complex_magnitude",
        magnitude_samples,
        _WARMUPS,
        _COMPLEX_OPERATIONS,
    )
    report_timing_samples(
        "core_complex_magnitude_squared",
        magnitude_squared_samples,
        _WARMUPS,
        _COMPLEX_OPERATIONS,
    )
    report_timing_samples(
        "core_complex_normalized",
        normalized_samples,
        _WARMUPS,
        _COMPLEX_OPERATIONS,
    )
    keep(checksum)
    print("core_complex_methods_retained_checksum:", checksum)
    return checksum


def _benchmark_views_and_buffers() raises -> Float64:
    var matrix_storage = List[Int64](capacity=_VIEW_OPERATIONS)
    var interleaved_storage = List[Complex64](capacity=_VIEW_OPERATIONS)
    var split_real = List[Float64](capacity=_VIEW_OPERATIONS)
    var split_imag = List[Float64](capacity=_VIEW_OPERATIONS)
    var packed_bits = List[UInt8](length=_VIEW_OPERATIONS // 8, fill=UInt8(0x5A))
    var quantized_llrs = List[Int](capacity=_VIEW_OPERATIONS)
    for index in range(_VIEW_OPERATIONS):
        matrix_storage.append(Int64(index % 257))
        interleaved_storage.append(
            Complex64(Float64(index % 101), -Float64(index % 103))
        )
        split_real.append(Float64(index % 107))
        split_imag.append(-Float64(index % 109))
        quantized_llrs.append(index % 63 - 31)

    var matrix = MatrixView(
        unsafe_ptr=matrix_storage.unsafe_ptr(),
        rows=64,
        columns=64,
        row_stride=64,
    )
    var interleaved = ComplexSpan(
        unsafe_ptr=interleaved_storage.unsafe_ptr(),
        length=_VIEW_OPERATIONS,
    )
    var split = SplitComplexSpan(
        real_ptr=split_real.unsafe_ptr(),
        imag_ptr=split_imag.unsafe_ptr(),
        length=_VIEW_OPERATIONS,
    )
    var bits = BitSpan(
        unsafe_ptr=packed_bits.unsafe_ptr(), bit_length=_VIEW_OPERATIONS
    )
    var llrs = LLRBuffer(quantized_llrs^, 4.0, 31)

    for _ in range(_WARMUPS):
        for index in range(_VIEW_OPERATIONS):
            var row = index // 64
            var column = index % 64
            matrix[row, column] = matrix[row, column] + 1
            var interleaved_value = interleaved.load(index)
            interleaved.store(
                index,
                Complex64(interleaved_value.re + 1.0e-9, interleaved_value.im),
            )
            var split_value = split.load(index)
            split.store(
                index, Complex64(split_value.re, split_value.im - 1.0e-9)
            )
            bits.set(index, bits[index] ^ UInt8(1))
        keep(llrs.dequantize())

    var matrix_samples = List[UInt64](capacity=_SAMPLES)
    var interleaved_samples = List[UInt64](capacity=_SAMPLES)
    var split_samples = List[UInt64](capacity=_SAMPLES)
    var bit_samples = List[UInt64](capacity=_SAMPLES)
    var llr_samples = List[UInt64](capacity=_SAMPLES)
    var checksum = 0.0
    for repetition in range(_SAMPLES):
        var start = global_perf_counter_ns()
        var matrix_checksum = Int64(0)
        for index in range(_VIEW_OPERATIONS):
            var row = index // 64
            var column = index % 64
            var value = matrix[row, column]
            matrix[row, column] = value + 1
            matrix_checksum += value
        matrix_samples.append(global_perf_counter_ns() - start)
        keep(matrix_checksum)
        checksum += Float64(matrix_checksum) * Float64(repetition + 1)

        start = global_perf_counter_ns()
        var interleaved_checksum = 0.0
        for index in range(_VIEW_OPERATIONS):
            var value = interleaved.load(index)
            interleaved.store(
                index, Complex64(value.re + 1.0e-9, value.im - 1.0e-9)
            )
            interleaved_checksum += value.re + value.im
        interleaved_samples.append(global_perf_counter_ns() - start)
        keep(interleaved_checksum)
        checksum += interleaved_checksum * Float64(repetition + 3)

        start = global_perf_counter_ns()
        var split_checksum = 0.0
        for index in range(_VIEW_OPERATIONS):
            var value = split.load(index)
            split.store(
                index, Complex64(value.re - 1.0e-9, value.im + 1.0e-9)
            )
            split_checksum += value.re - value.im
        split_samples.append(global_perf_counter_ns() - start)
        keep(split_checksum)
        checksum += split_checksum * Float64(repetition + 5)

        start = global_perf_counter_ns()
        var bit_checksum = UInt64(0)
        for index in range(_VIEW_OPERATIONS):
            var value = bits[index]
            bits.set(index, value ^ UInt8(1))
            bit_checksum += UInt64(value)
        bit_samples.append(global_perf_counter_ns() - start)
        keep(bit_checksum)
        checksum += Float64(bit_checksum) * Float64(repetition + 7)

        start = global_perf_counter_ns()
        var dequantized = llrs.dequantize()
        llr_samples.append(global_perf_counter_ns() - start)
        keep(dequantized)
        checksum += (
            dequantized[(613 * repetition + 29) % len(dequantized)]
            * Float64(repetition + 9)
        )

    report_timing_samples(
        "core_matrix_view_load_store",
        matrix_samples,
        _WARMUPS,
        _VIEW_OPERATIONS,
    )
    report_timing_samples(
        "core_complex_span_load_store",
        interleaved_samples,
        _WARMUPS,
        _VIEW_OPERATIONS,
    )
    report_timing_samples(
        "core_split_complex_span_load_store",
        split_samples,
        _WARMUPS,
        _VIEW_OPERATIONS,
    )
    report_timing_samples(
        "core_bit_span_load_store",
        bit_samples,
        _WARMUPS,
        _VIEW_OPERATIONS,
    )
    report_timing_samples(
        "core_llr_buffer_dequantize",
        llr_samples,
        _WARMUPS,
        _VIEW_OPERATIONS,
    )
    keep(checksum)
    print("core_views_buffers_retained_checksum:", checksum)
    return checksum


def main() raises:
    print_benchmark_metadata()
    var checksum = _benchmark_complex_methods()
    checksum += _benchmark_views_and_buffers()
    keep(checksum)
    print("core_benchmark_combined_retained_checksum:", checksum)
