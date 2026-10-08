"""Strictly isolated latency evidence for core/numerics public APIs.

Every ledger API has one unique no-inline workload.  Fixed fixtures are built
before entry, the timer encloses exactly one target call, and the complete
result is retained before an O(1) fingerprint is computed.  Each runner first
checks two identical executions, then performs three warmups and nine samples.
"""

from std.benchmark import keep
from std.collections import Span
from std.time import global_perf_counter_ns
from wireless_dsp.benchmarking import (
    print_benchmark_metadata,
    report_timing_samples,
)
from wireless_dsp.core import Complex32, complex_mac
from wireless_dsp.numerics import (
    ROUND_NEAREST_AWAY,
    OVERFLOW_SATURATE,
    QFormat,
    validate_qformat,
    raw_fits,
    narrow_raw,
    rounded_shift_right,
    rescale_raw,
    quantize_raw,
    dequantize_raw,
    fixed_add_raw,
    fixed_sub_raw,
    fixed_mul_raw,
    fixed_mac_raw,
    fixed_shift_raw,
    fixed_abs_raw,
    fixed_min_raw,
    fixed_max_raw,
    ComplexRaw,
    complex_conjugate_raw,
    complex_mul_raw,
    complex_mac_raw,
    complex_mac_conjugate_raw,
    ScaleStage,
    apply_scale_schedule,
    radix2_fft_scale_schedule,
)


comptime _WARMUPS = 3
comptime _SAMPLES = 9


def _mix(checksum: UInt64, value: UInt64) -> UInt64:
    return (checksum ^ value) * UInt64(1099511628211)


def _require_repeat(first: UInt64, second: UInt64) raises:
    if first != second:
        raise Error("fixed core/numerics benchmark result is nondeterministic")
    keep(first)
    keep(second)


def _fingerprint_float32(value: Float32) -> UInt64:
    return UInt64(Int(abs(value) * 1_000_000.0))


def _fingerprint_float64(value: Float64) -> UInt64:
    return UInt64(Int(abs(value) * 1_000_000.0))


def _fingerprint_qformat(value: QFormat) -> UInt64:
    var fingerprint = UInt64(value.storage_bits)
    fingerprint = _mix(fingerprint, UInt64(value.fraction_bits))
    fingerprint = _mix(fingerprint, UInt64(value.rounding_mode))
    return _mix(fingerprint, UInt64(value.overflow_mode))


def _fingerprint_complex_raw(value: ComplexRaw) -> UInt64:
    return _mix(UInt64(value.re), UInt64(value.im))


def _finish_sample(
    name: StringSlice, mut samples: List[UInt64], checksum: UInt64
) raises -> UInt64:
    report_timing_samples(name, samples, _WARMUPS, 1, "api_call")
    keep(samples)
    return checksum


@no_inline
def _work_complex_mac(
    accumulator: Complex32, lhs: Complex32, rhs: Complex32
) -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = complex_mac(accumulator, lhs, rhs)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _mix(
        _fingerprint_float32(result.re), _fingerprint_float32(result.im)
    )
    return (elapsed, fingerprint)


def _run_complex_mac() raises -> UInt64:
    var accumulator = Complex32(0.25, -0.5)
    var lhs = Complex32(-0.75, 0.125)
    var rhs = Complex32(0.5, 0.25)
    var first = _work_complex_mac(accumulator, lhs, rhs)
    var second = _work_complex_mac(accumulator, lhs, rhs)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_work_complex_mac(accumulator, lhs, rhs))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _work_complex_mac(accumulator, lhs, rhs)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("complex_mac", samples, checksum)


@no_inline
def _work_validate_qformat(qformat: QFormat) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = validate_qformat(qformat)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, _fingerprint_qformat(result))


def _run_validate_qformat() raises -> UInt64:
    var qformat = QFormat(16, 8, ROUND_NEAREST_AWAY, OVERFLOW_SATURATE)
    var first = _work_validate_qformat(qformat)
    var second = _work_validate_qformat(qformat)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_work_validate_qformat(qformat))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _work_validate_qformat(qformat)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("validate_qformat", samples, checksum)


@no_inline
def _work_raw_fits(qformat: QFormat) -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = raw_fits(Int64(3200), qformat)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, UInt64(1 if result else 0))


def _run_raw_fits() raises -> UInt64:
    var qformat = QFormat(16, 8)
    var first = _work_raw_fits(qformat)
    var second = _work_raw_fits(qformat)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_work_raw_fits(qformat))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _work_raw_fits(qformat)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("raw_fits", samples, checksum)


@no_inline
def _work_narrow_raw(qformat: QFormat) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = narrow_raw(Int64(40_000), qformat)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, UInt64(result))


def _run_narrow_raw() raises -> UInt64:
    var qformat = QFormat(16, 8)
    var first = _work_narrow_raw(qformat)
    var second = _work_narrow_raw(qformat)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_work_narrow_raw(qformat))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _work_narrow_raw(qformat)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("narrow_raw", samples, checksum)


@no_inline
def _work_rounded_shift_right() raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = rounded_shift_right(
        Int64(-12_345), 3, ROUND_NEAREST_AWAY
    )
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, UInt64(result))


def _run_rounded_shift_right() raises -> UInt64:
    var first = _work_rounded_shift_right()
    var second = _work_rounded_shift_right()
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_work_rounded_shift_right())
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _work_rounded_shift_right()
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("rounded_shift_right", samples, checksum)


@no_inline
def _work_rescale_raw(qformat: QFormat) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = rescale_raw(Int64(3200), 8, qformat)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, UInt64(result))


def _run_rescale_raw() raises -> UInt64:
    var qformat = QFormat(16, 6)
    var first = _work_rescale_raw(qformat)
    var second = _work_rescale_raw(qformat)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_work_rescale_raw(qformat))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _work_rescale_raw(qformat)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("rescale_raw", samples, checksum)


@no_inline
def _work_quantize_raw(qformat: QFormat) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = quantize_raw(3.125, qformat)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, UInt64(result))


def _run_quantize_raw() raises -> UInt64:
    var qformat = QFormat(16, 8)
    var first = _work_quantize_raw(qformat)
    var second = _work_quantize_raw(qformat)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_work_quantize_raw(qformat))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _work_quantize_raw(qformat)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("quantize_raw", samples, checksum)


@no_inline
def _work_dequantize_raw(qformat: QFormat) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = dequantize_raw(Int64(3200), qformat)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, _fingerprint_float64(result))


def _run_dequantize_raw() raises -> UInt64:
    var qformat = QFormat(16, 8)
    var first = _work_dequantize_raw(qformat)
    var second = _work_dequantize_raw(qformat)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_work_dequantize_raw(qformat))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _work_dequantize_raw(qformat)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("dequantize_raw", samples, checksum)


@no_inline
def _work_fixed_add_raw(qformat: QFormat) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = fixed_add_raw(
        Int64(3200), qformat, Int64(-1408), qformat, qformat
    )
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, UInt64(result))


def _run_fixed_add_raw() raises -> UInt64:
    var qformat = QFormat(16, 8)
    var first = _work_fixed_add_raw(qformat)
    var second = _work_fixed_add_raw(qformat)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_work_fixed_add_raw(qformat))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _work_fixed_add_raw(qformat)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("fixed_add_raw", samples, checksum)


@no_inline
def _work_fixed_sub_raw(qformat: QFormat) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = fixed_sub_raw(
        Int64(3200), qformat, Int64(-1408), qformat, qformat
    )
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, UInt64(result))


def _run_fixed_sub_raw() raises -> UInt64:
    var qformat = QFormat(16, 8)
    var first = _work_fixed_sub_raw(qformat)
    var second = _work_fixed_sub_raw(qformat)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_work_fixed_sub_raw(qformat))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _work_fixed_sub_raw(qformat)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("fixed_sub_raw", samples, checksum)


@no_inline
def _work_fixed_mul_raw(qformat: QFormat) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = fixed_mul_raw(
        Int64(3200), qformat, Int64(-1408), qformat, qformat
    )
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, UInt64(result))


def _run_fixed_mul_raw() raises -> UInt64:
    var qformat = QFormat(16, 8)
    var first = _work_fixed_mul_raw(qformat)
    var second = _work_fixed_mul_raw(qformat)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_work_fixed_mul_raw(qformat))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _work_fixed_mul_raw(qformat)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("fixed_mul_raw", samples, checksum)


@no_inline
def _work_fixed_mac_raw(qformat: QFormat) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = fixed_mac_raw(
        Int64(512), Int64(3200), qformat, Int64(-1408), qformat, qformat
    )
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, UInt64(result))


def _run_fixed_mac_raw() raises -> UInt64:
    var qformat = QFormat(16, 8)
    var first = _work_fixed_mac_raw(qformat)
    var second = _work_fixed_mac_raw(qformat)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_work_fixed_mac_raw(qformat))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _work_fixed_mac_raw(qformat)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("fixed_mac_raw", samples, checksum)


@no_inline
def _work_fixed_shift_raw(qformat: QFormat) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = fixed_shift_raw(Int64(-1408), 2, qformat)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, UInt64(result))


def _run_fixed_shift_raw() raises -> UInt64:
    var qformat = QFormat(16, 8)
    var first = _work_fixed_shift_raw(qformat)
    var second = _work_fixed_shift_raw(qformat)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_work_fixed_shift_raw(qformat))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _work_fixed_shift_raw(qformat)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("fixed_shift_raw", samples, checksum)


@no_inline
def _work_fixed_abs_raw(qformat: QFormat) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = fixed_abs_raw(Int64(-1408), qformat)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, UInt64(result))


def _run_fixed_abs_raw() raises -> UInt64:
    var qformat = QFormat(16, 8)
    var first = _work_fixed_abs_raw(qformat)
    var second = _work_fixed_abs_raw(qformat)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_work_fixed_abs_raw(qformat))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _work_fixed_abs_raw(qformat)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("fixed_abs_raw", samples, checksum)


@no_inline
def _work_fixed_min_raw(qformat: QFormat) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = fixed_min_raw(Int64(3200), Int64(-1408), qformat)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, UInt64(result))


def _run_fixed_min_raw() raises -> UInt64:
    var qformat = QFormat(16, 8)
    var first = _work_fixed_min_raw(qformat)
    var second = _work_fixed_min_raw(qformat)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_work_fixed_min_raw(qformat))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _work_fixed_min_raw(qformat)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("fixed_min_raw", samples, checksum)


@no_inline
def _work_fixed_max_raw(qformat: QFormat) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = fixed_max_raw(Int64(3200), Int64(-1408), qformat)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, UInt64(result))


def _run_fixed_max_raw() raises -> UInt64:
    var qformat = QFormat(16, 8)
    var first = _work_fixed_max_raw(qformat)
    var second = _work_fixed_max_raw(qformat)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_work_fixed_max_raw(qformat))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _work_fixed_max_raw(qformat)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("fixed_max_raw", samples, checksum)


@no_inline
def _work_complex_conjugate_raw(
    value: ComplexRaw, qformat: QFormat
) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = complex_conjugate_raw(value, qformat)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, _fingerprint_complex_raw(result))


def _run_complex_conjugate_raw() raises -> UInt64:
    var qformat = QFormat(16, 8)
    var value = ComplexRaw(3200, -1408)
    var first = _work_complex_conjugate_raw(value, qformat)
    var second = _work_complex_conjugate_raw(value, qformat)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_work_complex_conjugate_raw(value, qformat))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _work_complex_conjugate_raw(value, qformat)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("complex_conjugate_raw", samples, checksum)


@no_inline
def _work_complex_mul_raw(
    lhs: ComplexRaw, rhs: ComplexRaw, qformat: QFormat
) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = complex_mul_raw(lhs, qformat, rhs, qformat, qformat)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, _fingerprint_complex_raw(result))


def _run_complex_mul_raw() raises -> UInt64:
    var qformat = QFormat(16, 8)
    var lhs = ComplexRaw(3200, -1408)
    var rhs = ComplexRaw(-768, 2048)
    var first = _work_complex_mul_raw(lhs, rhs, qformat)
    var second = _work_complex_mul_raw(lhs, rhs, qformat)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_work_complex_mul_raw(lhs, rhs, qformat))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _work_complex_mul_raw(lhs, rhs, qformat)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("complex_mul_raw", samples, checksum)


@no_inline
def _work_complex_mac_raw(
    accumulator: ComplexRaw,
    lhs: ComplexRaw,
    rhs: ComplexRaw,
    qformat: QFormat,
) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = complex_mac_raw(
        accumulator, lhs, qformat, rhs, qformat, qformat
    )
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, _fingerprint_complex_raw(result))


def _run_complex_mac_raw() raises -> UInt64:
    var qformat = QFormat(16, 8)
    var accumulator = ComplexRaw(256, -512)
    var lhs = ComplexRaw(3200, -1408)
    var rhs = ComplexRaw(-768, 2048)
    var first = _work_complex_mac_raw(accumulator, lhs, rhs, qformat)
    var second = _work_complex_mac_raw(accumulator, lhs, rhs, qformat)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_work_complex_mac_raw(accumulator, lhs, rhs, qformat))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _work_complex_mac_raw(accumulator, lhs, rhs, qformat)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("complex_mac_raw", samples, checksum)


@no_inline
def _work_complex_mac_conjugate_raw(
    accumulator: ComplexRaw,
    lhs: ComplexRaw,
    rhs: ComplexRaw,
    qformat: QFormat,
) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = complex_mac_conjugate_raw(
        accumulator, lhs, qformat, rhs, qformat, qformat
    )
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, _fingerprint_complex_raw(result))


def _run_complex_mac_conjugate_raw() raises -> UInt64:
    var qformat = QFormat(16, 8)
    var accumulator = ComplexRaw(256, -512)
    var lhs = ComplexRaw(3200, -1408)
    var rhs = ComplexRaw(-768, 2048)
    var first = _work_complex_mac_conjugate_raw(
        accumulator, lhs, rhs, qformat
    )
    var second = _work_complex_mac_conjugate_raw(
        accumulator, lhs, rhs, qformat
    )
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_work_complex_mac_conjugate_raw(
            accumulator, lhs, rhs, qformat
        ))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _work_complex_mac_conjugate_raw(
            accumulator, lhs, rhs, qformat
        )
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("complex_mac_conjugate_raw", samples, checksum)


@no_inline
def _work_radix2_fft_scale_schedule() raises -> Tuple[UInt64, UInt64]:
    var fft_size = 4096
    var storage_bits = 24
    var fraction_bits = 16
    var start = global_perf_counter_ns()
    var result = radix2_fft_scale_schedule(
        fft_size, storage_bits, fraction_bits
    )
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = UInt64(len(result))
    if len(result) > 0:
        fingerprint = _mix(
            fingerprint,
            UInt64(result[0].output_format.storage_bits),
        )
        fingerprint = _mix(
            fingerprint, UInt64(result[len(result) - 1].right_shift)
        )
    return (elapsed, fingerprint)


def _run_radix2_fft_scale_schedule() raises -> UInt64:
    var first = _work_radix2_fft_scale_schedule()
    var second = _work_radix2_fft_scale_schedule()
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_work_radix2_fft_scale_schedule())
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _work_radix2_fft_scale_schedule()
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample(
        "radix2_fft_scale_schedule", samples, checksum
    )


@no_inline
def _work_apply_scale_schedule(
    qformat: QFormat, stages: Span[ScaleStage, ...]
) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = apply_scale_schedule(Int64(3200), qformat, stages)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = UInt64(len(result.values))
    if len(result.values) > 0:
        fingerprint = _mix(fingerprint, UInt64(result.values[0]))
        fingerprint = _mix(
            fingerprint, UInt64(result.values[len(result.values) - 1])
        )
    return (elapsed, fingerprint)


def _run_apply_scale_schedule() raises -> UInt64:
    var qformat = QFormat(16, 8)
    var stages: List[ScaleStage] = [
        ScaleStage(QFormat(16, 7), 1),
        ScaleStage(QFormat(16, 8), 0),
    ]
    var stages_span = Span(stages)
    var first = _work_apply_scale_schedule(qformat, stages_span)
    var second = _work_apply_scale_schedule(qformat, stages_span)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_work_apply_scale_schedule(qformat, stages_span))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _work_apply_scale_schedule(qformat, stages_span)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("apply_scale_schedule", samples, checksum)


def main() raises:
    print_benchmark_metadata()
    var checksum = _run_complex_mac()
    checksum = _mix(checksum, _run_validate_qformat())
    checksum = _mix(checksum, _run_raw_fits())
    checksum = _mix(checksum, _run_narrow_raw())
    checksum = _mix(checksum, _run_rounded_shift_right())
    checksum = _mix(checksum, _run_rescale_raw())
    checksum = _mix(checksum, _run_quantize_raw())
    checksum = _mix(checksum, _run_dequantize_raw())
    checksum = _mix(checksum, _run_fixed_add_raw())
    checksum = _mix(checksum, _run_fixed_sub_raw())
    checksum = _mix(checksum, _run_fixed_mul_raw())
    checksum = _mix(checksum, _run_fixed_mac_raw())
    checksum = _mix(checksum, _run_fixed_shift_raw())
    checksum = _mix(checksum, _run_fixed_abs_raw())
    checksum = _mix(checksum, _run_fixed_min_raw())
    checksum = _mix(checksum, _run_fixed_max_raw())
    checksum = _mix(checksum, _run_complex_conjugate_raw())
    checksum = _mix(checksum, _run_complex_mul_raw())
    checksum = _mix(checksum, _run_complex_mac_raw())
    checksum = _mix(checksum, _run_complex_mac_conjugate_raw())
    checksum = _mix(checksum, _run_radix2_fft_scale_schedule())
    checksum = _mix(checksum, _run_apply_scale_schedule())
    keep(checksum)
    print("core_numerics_strict_retained_checksum:", checksum)
