"""Strictly isolated latency baselines for formerly indirect public APIs.

Each ledger API is called once by its own no-inline timed workload.  Lists,
Spans, formats, and all other fixtures are constructed before timing.  The
complete result is retained after timing and reduced to an O(1) fingerprint.
"""

from std.benchmark import keep
from std.collections import Span
from std.time import global_perf_counter_ns
from wireless_dsp.benchmarking import (
    print_benchmark_metadata,
    report_timing_samples,
)
from wireless_dsp.core import Complex64
from wireless_dsp.dsp import (
    apply_window_real,
    complex_divide,
    convolve_complex,
    fft_in_place,
    sum_complex,
)
from wireless_dsp.modem import crc_reflected_bits
from wireless_dsp.synchronization import (
    estimate_repetition_cfo,
    repetition_metric,
)
from wireless_dsp.numerics import ComplexRaw, QFormat
from wireless_dsp.backend import fixed_qpsk_float64_audit


comptime _WARMUPS = 3
comptime _SAMPLES = 9


def _mix(checksum: UInt64, value: UInt64) -> UInt64:
    return (checksum ^ value) * UInt64(1099511628211)


def _require_repeat(first: UInt64, second: UInt64) raises:
    if first != second:
        raise Error("fixed kernel-gap benchmark result is nondeterministic")
    keep(first)
    keep(second)


def _fingerprint_float(value: Float64) -> UInt64:
    var fingerprint = UInt64(Int(abs(value) * 1_000_000_000.0))
    return _mix(fingerprint, UInt64(1 if value < 0.0 else 0))


def _fingerprint_complex(value: Complex64) -> UInt64:
    return _mix(_fingerprint_float(value.re), _fingerprint_float(value.im))


def _fingerprint_float_list(values: List[Float64]) -> UInt64:
    var fingerprint = UInt64(len(values))
    if len(values) > 0:
        fingerprint = _mix(fingerprint, _fingerprint_float(values[0]))
        fingerprint = _mix(
            fingerprint, _fingerprint_float(values[len(values) - 1])
        )
    return fingerprint


def _fingerprint_complex_list(values: List[Complex64]) -> UInt64:
    var fingerprint = UInt64(len(values))
    if len(values) > 0:
        fingerprint = _mix(fingerprint, _fingerprint_complex(values[0]))
        fingerprint = _mix(
            fingerprint, _fingerprint_complex(values[len(values) - 1])
        )
    return fingerprint


def _finish_sample(
    name: StringSlice, mut samples: List[UInt64], checksum: UInt64
) raises -> UInt64:
    report_timing_samples(name, samples, _WARMUPS, 1, "api_call")
    keep(samples)
    return checksum


def _real_fixture(length: Int, salt: Int) -> List[Float64]:
    var result = List[Float64](capacity=length)
    for index in range(length):
        result.append(Float64((17 * index + salt) % 101) / 50.0 - 1.0)
    return result^


def _complex_fixture(length: Int, salt: Int) -> List[Complex64]:
    var result = List[Complex64](capacity=length)
    for index in range(length):
        result.append(Complex64(
            Float64((13 * index + salt) % 97) / 48.0 - 1.0,
            Float64((19 * index + 2 * salt) % 89) / 44.0 - 1.0,
        ))
    return result^


@no_inline
def _work_apply_window_real(
    values: Span[Float64, ...], window: Span[Float64, ...]
) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = apply_window_real(values, window)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, _fingerprint_float_list(result))


def _run_apply_window_real() raises -> UInt64:
    var values = _real_fixture(256, 3)
    var window = _real_fixture(256, 11)
    var values_span = Span(values)
    var window_span = Span(window)
    var first = _work_apply_window_real(values_span, window_span)
    var second = _work_apply_window_real(values_span, window_span)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_work_apply_window_real(values_span, window_span))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _work_apply_window_real(values_span, window_span)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("apply_window_real", samples, checksum)


@no_inline
def _work_complex_divide(
    lhs: Complex64, rhs: Complex64
) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = complex_divide(lhs, rhs)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, _fingerprint_complex(result))


def _run_complex_divide() raises -> UInt64:
    var lhs = Complex64(2.75, -0.75)
    var rhs = Complex64(1.25, -0.5)
    var first = _work_complex_divide(lhs, rhs)
    var second = _work_complex_divide(lhs, rhs)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_work_complex_divide(lhs, rhs))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _work_complex_divide(lhs, rhs)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("complex_divide", samples, checksum)


@no_inline
def _work_convolve_complex(
    values: Span[Complex64, ...], taps: Span[Complex64, ...]
) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = convolve_complex(values, taps)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, _fingerprint_complex_list(result))


def _run_convolve_complex() raises -> UInt64:
    var values = _complex_fixture(128, 5)
    var taps = _complex_fixture(17, 7)
    var values_span = Span(values)
    var taps_span = Span(taps)
    var first = _work_convolve_complex(values_span, taps_span)
    var second = _work_convolve_complex(values_span, taps_span)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_work_convolve_complex(values_span, taps_span))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _work_convolve_complex(values_span, taps_span)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("convolve_complex", samples, checksum)


@no_inline
def _work_crc_reflected_bits(
    bits: Span[UInt8, ...]
) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = crc_reflected_bits(
        bits,
        width=32,
        polynomial=UInt64(0xEDB88320),
        initial=UInt64(0xFFFFFFFF),
        xor_out=UInt64(0xFFFFFFFF),
    )
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, result)


def _run_crc_reflected_bits() raises -> UInt64:
    var bits = List[UInt8](capacity=512)
    for index in range(512):
        bits.append(UInt8(((17 * index + 5) >> (index % 5)) & 1))
    var bits_span = Span(bits)
    var first = _work_crc_reflected_bits(bits_span)
    var second = _work_crc_reflected_bits(bits_span)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_work_crc_reflected_bits(bits_span))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _work_crc_reflected_bits(bits_span)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("crc_reflected_bits", samples, checksum)


@no_inline
def _work_estimate_repetition_cfo(
    repeated: Span[Complex64, ...]
) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = estimate_repetition_cfo(repeated, 0, 16, 16)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, _fingerprint_float(result))


def _repetition_fixture() -> List[Complex64]:
    var period = _complex_fixture(16, 13)
    var result = List[Complex64](capacity=32)
    for index in range(16):
        result.append(period[index])
    for index in range(16):
        result.append(period[index])
    return result^


def _run_estimate_repetition_cfo() raises -> UInt64:
    var repeated = _repetition_fixture()
    var repeated_span = Span(repeated)
    var first = _work_estimate_repetition_cfo(repeated_span)
    var second = _work_estimate_repetition_cfo(repeated_span)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_work_estimate_repetition_cfo(repeated_span))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _work_estimate_repetition_cfo(repeated_span)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("estimate_repetition_cfo", samples, checksum)


@no_inline
def _work_fft_in_place(
    mut working: List[Complex64]
) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    fft_in_place(working)
    var elapsed = global_perf_counter_ns() - start
    keep(working)
    return (elapsed, _fingerprint_complex_list(working))


def _run_fft_in_place() raises -> UInt64:
    var seed = _complex_fixture(128, 17)
    var first_values = seed.copy()
    var first = _work_fft_in_place(first_values)
    var second_values = seed.copy()
    var second = _work_fft_in_place(second_values)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        var warmup_values = seed.copy()
        keep(_work_fft_in_place(warmup_values))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample_values = seed.copy()
        var sample = _work_fft_in_place(sample_values)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("fft_in_place", samples, checksum)


@no_inline
def _work_fixed_qpsk_float64_audit(
    bits: Span[UInt8, ...],
    symbols: Span[ComplexRaw, ...],
    qformat: QFormat,
) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = fixed_qpsk_float64_audit(bits, symbols, qformat, 1.0)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _mix(
        UInt64(result.bit_errors), UInt64(result.bits_checked)
    )
    fingerprint = _mix(fingerprint, _fingerprint_float(result.evm_rms))
    return (elapsed, fingerprint)


def _run_fixed_qpsk_float64_audit() raises -> UInt64:
    var bits = List[UInt8](capacity=128)
    var symbols = List[ComplexRaw](capacity=64)
    for index in range(64):
        var first_bit = UInt8((17 * index + 3) & 1)
        var second_bit = UInt8((11 * index + 5) & 1)
        bits.append(first_bit)
        bits.append(second_bit)
        symbols.append(ComplexRaw(
            Int64(4096 if first_bit == 0 else -4096),
            Int64(4096 if second_bit == 0 else -4096),
        ))
    var qformat = QFormat(16, 12)
    var bits_span = Span(bits)
    var symbols_span = Span(symbols)
    var first = _work_fixed_qpsk_float64_audit(
        bits_span, symbols_span, qformat
    )
    var second = _work_fixed_qpsk_float64_audit(
        bits_span, symbols_span, qformat
    )
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_work_fixed_qpsk_float64_audit(
            bits_span, symbols_span, qformat
        ))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _work_fixed_qpsk_float64_audit(
            bits_span, symbols_span, qformat
        )
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("fixed_qpsk_float64_audit", samples, checksum)


@no_inline
def _work_repetition_metric(
    repeated: Span[Complex64, ...]
) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = repetition_metric(repeated, 0, 16, 16)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, _fingerprint_float(result))


def _run_repetition_metric() raises -> UInt64:
    var repeated = _repetition_fixture()
    var repeated_span = Span(repeated)
    var first = _work_repetition_metric(repeated_span)
    var second = _work_repetition_metric(repeated_span)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_work_repetition_metric(repeated_span))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _work_repetition_metric(repeated_span)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("repetition_metric", samples, checksum)


@no_inline
def _work_sum_complex(
    values: Span[Complex64, ...]
) -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = sum_complex(values)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, _fingerprint_complex(result))


def _run_sum_complex() raises -> UInt64:
    var values = _complex_fixture(256, 19)
    var values_span = Span(values)
    var first = _work_sum_complex(values_span)
    var second = _work_sum_complex(values_span)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_work_sum_complex(values_span))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _work_sum_complex(values_span)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample("sum_complex", samples, checksum)


def main() raises:
    print_benchmark_metadata()
    var checksum = _run_apply_window_real()
    checksum = _mix(checksum, _run_complex_divide())
    checksum = _mix(checksum, _run_convolve_complex())
    checksum = _mix(checksum, _run_crc_reflected_bits())
    checksum = _mix(checksum, _run_estimate_repetition_cfo())
    checksum = _mix(checksum, _run_fft_in_place())
    checksum = _mix(checksum, _run_fixed_qpsk_float64_audit())
    checksum = _mix(checksum, _run_repetition_metric())
    checksum = _mix(checksum, _run_sum_complex())
    keep(checksum)
    print("kernel_gap_strict_retained_checksum:", checksum)
