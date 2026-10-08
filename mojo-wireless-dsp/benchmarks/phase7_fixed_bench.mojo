"""Per-public-API fixed-point FIR and FFT benchmarks."""

from std.benchmark import keep
from std.collections import Span
from std.time import global_perf_counter_ns
from wireless_dsp.benchmarking import (
    print_benchmark_metadata,
    report_timing_samples,
)
from wireless_dsp.numerics.fixed import (
    ROUND_NEAREST_AWAY, OVERFLOW_SATURATE,
)


comptime _WARMUPS = 3
comptime _SAMPLES = 9
from wireless_dsp.numerics.quantization import QFormat
from wireless_dsp.numerics.complex_fixed import ComplexRaw
from wireless_dsp.numerics.scale_schedule import ScaleStage
from wireless_dsp.backend.fixed_reference import fixed_fir_raw
from wireless_dsp.backend.fixed_fft_reference import (
    FixedFFTTrace,
    fixed_fft_radix2_raw,
    fixed_fft_radix2_trace_raw,
    quantized_fft_twiddles,
    serialize_fixed_fft_trace,
)


@no_inline
def _fixed_fir_raw_workload(
    samples: Span[Int64, ...],
    taps: Span[Int64, ...],
    q15: QFormat,
    accumulator_format: QFormat,
) raises -> List[Int64]:
    return fixed_fir_raw(
        samples, taps, q15, q15, accumulator_format, q15
    )


def _quantized_fft_twiddles_fixture(
    size: Int, twiddle_format: QFormat,
) raises -> List[ComplexRaw]:
    return quantized_fft_twiddles(size, twiddle_format)


@no_inline
def _fixed_fft_radix2_raw_workload(
    values: Span[ComplexRaw, ...],
    q15: QFormat,
    twiddles: Span[ComplexRaw, ...],
    twiddle_format: QFormat,
    stages: Span[ScaleStage, ...],
) raises -> List[ComplexRaw]:
    return fixed_fft_radix2_raw(
        values, q15, twiddles, twiddle_format, stages
    )


@no_inline
def _fixed_fft_radix2_trace_raw_workload(
    values: Span[ComplexRaw, ...],
    q15: QFormat,
    twiddles: Span[ComplexRaw, ...],
    twiddle_format: QFormat,
    stages: Span[ScaleStage, ...],
) raises -> FixedFFTTrace:
    return fixed_fft_radix2_trace_raw(
        values, q15, twiddles, twiddle_format, stages
    )


@no_inline
def _serialize_fixed_fft_trace_workload(
    trace: FixedFFTTrace,
) raises -> String:
    return serialize_fixed_fft_trace("fft1024-benchmark-v2", "fft", trace)


def _int_list_fingerprint(values: Span[Int64, ...]) -> UInt64:
    return (
        UInt64(len(values))
        ^ UInt64(values[0])
        ^ (UInt64(values[len(values) - 1]) << 19)
    )


def _complex_list_fingerprint(values: Span[ComplexRaw, ...]) -> UInt64:
    return (
        UInt64(len(values))
        ^ UInt64(values[0].re)
        ^ (UInt64(values[0].im) << 11)
        ^ (UInt64(values[len(values) - 1].re) << 23)
        ^ (UInt64(values[len(values) - 1].im) << 37)
    )


def _mix(checksum: UInt64, value: UInt64) -> UInt64:
    return (checksum ^ value) * UInt64(1099511628211)


def _text_checksum(text: StringSlice) -> UInt64:
    var checksum = UInt64(14695981039346656037)
    var bytes = text.as_bytes()
    for index in range(len(bytes)):
        checksum = _mix(checksum, UInt64(UInt8(bytes[index])))
    return checksum


def _text_fingerprint(text: StringSlice) -> UInt64:
    var bytes = text.as_bytes()
    var result = UInt64(len(bytes))
    if len(bytes) > 0:
        result = _mix(result, UInt64(UInt8(bytes[0])))
        result = _mix(result, UInt64(UInt8(bytes[len(bytes) - 1])))
    return result


@no_inline
def _quantized_fft_twiddles_workload(
    size: Int, twiddle_format: QFormat,
) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = quantized_fft_twiddles(size, twiddle_format)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, _complex_list_fingerprint(Span(result)))


def main() raises:
    var q15 = QFormat(16, 15, ROUND_NEAREST_AWAY, OVERFLOW_SATURATE)
    var accumulator_format = QFormat(
        32, 30, ROUND_NEAREST_AWAY, OVERFLOW_SATURATE
    )
    var samples = List[Int64](capacity=4096)
    for i in range(4096):
        samples.append(Int64((i * 7919) % 32768 - 16384))
    var taps: List[Int64] = [
        128, -384, 1024, 4096, 8192, 4096, 1024, -384, 128
    ]
    var sample_span = Span(samples)
    var tap_span = Span(taps)
    var fft_input = List[ComplexRaw](capacity=1024)
    for i in range(1024):
        fft_input.append(
            ComplexRaw(
                Int64((i * 127) % 16384 - 8192),
                Int64((i * 251) % 16384 - 8192),
            )
        )
    var twiddle_format = QFormat(18, 16)
    var fft_format = QFormat(30, 20)
    var twiddles = _quantized_fft_twiddles_fixture(1024, twiddle_format)
    var fft_stages = List[ScaleStage](capacity=10)
    for _ in range(10):
        fft_stages.append(ScaleStage(fft_format, 1))
    var fft_input_span = Span(fft_input)
    var twiddle_span = Span(twiddles)
    var fft_stage_span = Span(fft_stages)
    var trace_fixture = _fixed_fft_radix2_trace_raw_workload(
        fft_input_span,
        q15,
        twiddle_span,
        twiddle_format,
        fft_stage_span,
    )
    var trace_text_first = _serialize_fixed_fft_trace_workload(trace_fixture)
    var trace_text_second = _serialize_fixed_fft_trace_workload(trace_fixture)
    if (
        _text_checksum(StringSlice(trace_text_first))
        != _text_checksum(StringSlice(trace_text_second))
    ):
        raise Error("fixed FFT serialization benchmark is nondeterministic")
    keep(trace_text_first)
    keep(trace_text_second)

    var first_twiddles = _quantized_fft_twiddles_workload(
        1024, twiddle_format
    )
    var second_twiddles = _quantized_fft_twiddles_workload(
        1024, twiddle_format
    )
    if first_twiddles[1] != second_twiddles[1]:
        raise Error("fixed twiddle benchmark result is nondeterministic")
    keep(first_twiddles)
    keep(second_twiddles)

    for _ in range(_WARMUPS):
        keep(_fixed_fir_raw_workload(
            sample_span, tap_span, q15, accumulator_format
        ))
        keep(_quantized_fft_twiddles_workload(1024, twiddle_format))
        keep(_fixed_fft_radix2_raw_workload(
            fft_input_span,
            q15,
            twiddle_span,
            twiddle_format,
            fft_stage_span,
        ))
        keep(_fixed_fft_radix2_trace_raw_workload(
            fft_input_span,
            q15,
            twiddle_span,
            twiddle_format,
            fft_stage_span,
        ))
        keep(_serialize_fixed_fft_trace_workload(trace_fixture))

    var fir_timings = List[UInt64](capacity=_SAMPLES)
    var twiddle_timings = List[UInt64](capacity=_SAMPLES)
    var fft_timings = List[UInt64](capacity=_SAMPLES)
    var fft_trace_timings = List[UInt64](capacity=_SAMPLES)
    var serialize_timings = List[UInt64](capacity=_SAMPLES)
    var fir_checksum = UInt64(0)
    var twiddle_checksum = UInt64(0)
    var fft_checksum = UInt64(0)
    var fft_trace_checksum = UInt64(0)
    var serialize_full_checksum = UInt64(1469598103934665603)
    var serialize_fingerprint_checksum = UInt64(1469598103934665603)
    for repetition in range(_SAMPLES):
        var start = global_perf_counter_ns()
        var filtered = _fixed_fir_raw_workload(
            sample_span, tap_span, q15, accumulator_format
        )
        fir_timings.append(global_perf_counter_ns() - start)
        keep(filtered)
        fir_checksum ^= (
            _int_list_fingerprint(Span(filtered)) + UInt64(repetition)
        )

        var measured_twiddles = _quantized_fft_twiddles_workload(
            1024, twiddle_format
        )
        twiddle_timings.append(measured_twiddles[0])
        keep(measured_twiddles)
        twiddle_checksum ^= measured_twiddles[1] + UInt64(repetition)

        start = global_perf_counter_ns()
        var spectrum = _fixed_fft_radix2_raw_workload(
            fft_input_span,
            q15,
            twiddle_span,
            twiddle_format,
            fft_stage_span,
        )
        fft_timings.append(global_perf_counter_ns() - start)
        keep(spectrum)
        fft_checksum ^= (
            _complex_list_fingerprint(Span(spectrum)) + UInt64(repetition)
        )

        start = global_perf_counter_ns()
        var trace = _fixed_fft_radix2_trace_raw_workload(
            fft_input_span,
            q15,
            twiddle_span,
            twiddle_format,
            fft_stage_span,
        )
        fft_trace_timings.append(global_perf_counter_ns() - start)
        keep(trace.stage_values)
        keep(trace.output)
        fft_trace_checksum ^= (
            _complex_list_fingerprint(Span(trace.stage_values))
            ^ _complex_list_fingerprint(Span(trace.output))
            ^ UInt64(repetition)
        )

        start = global_perf_counter_ns()
        var trace_text = _serialize_fixed_fft_trace_workload(trace_fixture)
        serialize_timings.append(global_perf_counter_ns() - start)
        keep(trace_text)
        serialize_full_checksum = _mix(
            serialize_full_checksum,
            _text_checksum(StringSlice(trace_text)),
        )
        serialize_fingerprint_checksum = _mix(
            serialize_fingerprint_checksum,
            _text_fingerprint(StringSlice(trace_text)),
        )

    print_benchmark_metadata()
    report_timing_samples(
        "fixed_fir_q15_output_element", fir_timings, _WARMUPS, 4096
    )
    report_timing_samples(
        "quantized_fft_twiddle", twiddle_timings, _WARMUPS, 512
    )
    report_timing_samples(
        "fixed_fft_q15_element", fft_timings, _WARMUPS, 1024
    )
    report_timing_samples(
        "fixed_fft_trace_q15_stage_element",
        fft_trace_timings,
        _WARMUPS,
        1024 * 10,
        "stage_complex_element",
    )
    report_timing_samples(
        "serialize_fixed_fft_trace",
        serialize_timings,
        _WARMUPS,
        1,
        "api_call",
    )
    keep(fir_checksum)
    keep(twiddle_checksum)
    keep(fft_checksum)
    keep(fft_trace_checksum)
    keep(serialize_full_checksum)
    keep(serialize_fingerprint_checksum)
    print(
        "phase7_fixed_retained_checksums:",
        fir_checksum,
        twiddle_checksum,
        fft_checksum,
        fft_trace_checksum,
    )
    print(
        "fixed_fft_trace_full_output_checksum:", serialize_full_checksum
    )
    print(
        "fixed_fft_trace_fingerprint_checksum:",
        serialize_fingerprint_checksum,
    )
