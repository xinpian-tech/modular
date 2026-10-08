"""Bit-exact radix-2 FFT golden backend with explicit stage scaling."""

from std.collections import Span
from std.math import cos, sin
from wireless_dsp.numerics.complex_fixed import ComplexRaw, require_complex_fits
from wireless_dsp.numerics.quantization import (
    QFormat,
    narrow_raw,
    quantize_raw,
    rounded_shift_right,
    validate_qformat,
)
from wireless_dsp.numerics.scale_schedule import ScaleStage, ScaleTrace
from wireless_dsp.testing.fixed_vectors import (
    fixed_raw_checksum,
    serialize_complex_fixed_vector,
    serialize_fixed_vector,
    serialize_scale_trace,
)

comptime _TWO_PI = 6.283185307179586476925286766559


struct FixedFFTTrace(Movable):
    """Owned bit-exact inputs, ROM, full stage outputs, and stage semantics.

    ``stage_values`` is flattened stage-major with exactly ``size`` complex
    values per radix-2 stage.  The companion metadata lists have exactly one
    entry per stage and retain the actual rounding and overflow modes used by
    the transform.  ``output`` equals the final stage (or the input for N=1).
    """

    var size: Int
    var input_format: QFormat
    var twiddle_format: QFormat
    var input_values: List[ComplexRaw]
    var twiddles: List[ComplexRaw]
    var stage_values: List[ComplexRaw]
    var stage_storage_bits: List[Int]
    var stage_fraction_bits: List[Int]
    var stage_right_shifts: List[Int]
    var stage_rounding_modes: List[Int]
    var stage_overflow_modes: List[Int]
    var output: List[ComplexRaw]

    def __init__(
        out self,
        size: Int,
        input_format: QFormat,
        twiddle_format: QFormat,
        var input_values: List[ComplexRaw],
        var twiddles: List[ComplexRaw],
        var stage_values: List[ComplexRaw],
        var stage_storage_bits: List[Int],
        var stage_fraction_bits: List[Int],
        var stage_right_shifts: List[Int],
        var stage_rounding_modes: List[Int],
        var stage_overflow_modes: List[Int],
        var output: List[ComplexRaw],
    ):
        self.size = size
        self.input_format = input_format
        self.twiddle_format = twiddle_format
        self.input_values = input_values^
        self.twiddles = twiddles^
        self.stage_values = stage_values^
        self.stage_storage_bits = stage_storage_bits^
        self.stage_fraction_bits = stage_fraction_bits^
        self.stage_right_shifts = stage_right_shifts^
        self.stage_rounding_modes = stage_rounding_modes^
        self.stage_overflow_modes = stage_overflow_modes^
        self.output = output^

    def take_output(deinit self) -> List[ComplexRaw]:
        """Consume a trace shell and return its owned output without a copy."""
        return self.output^


def _fft_stage_count(size: Int) raises -> Int:
    if size < 1 or (size & (size - 1)) != 0:
        raise Error("fixed FFT length must be a positive power of two")
    var count = 0
    var value = size
    while value > 1:
        count += 1
        value //= 2
    return count


def _align_wide(
    value: Int64,
    input_fraction_bits: Int,
    output_fraction_bits: Int,
    rounding_mode: Int,
) raises -> Int64:
    """Align a binary point without narrowing the butterfly datapath."""
    if output_fraction_bits <= input_fraction_bits:
        return rounded_shift_right(
            value, input_fraction_bits - output_fraction_bits, rounding_mode
        )
    var shift = output_fraction_bits - input_fraction_bits
    if shift > 30:
        raise Error("fixed FFT binary-point left shift exceeds guard model")
    if (
        value > (Int64.MAX_FINITE >> Int64(shift))
        or value < (Int64.MIN_FINITE >> Int64(shift))
    ):
        raise Error("fixed FFT wide binary-point alignment overflowed Int64")
    return value << Int64(shift)


def _checked_add(lhs: Int64, rhs: Int64) raises -> Int64:
    if rhs > 0 and lhs > Int64.MAX_FINITE - rhs:
        raise Error("fixed FFT wide butterfly addition overflowed Int64")
    if rhs < 0 and lhs < Int64.MIN_FINITE - rhs:
        raise Error("fixed FFT wide butterfly addition overflowed Int64")
    return lhs + rhs


def _checked_sub(lhs: Int64, rhs: Int64) raises -> Int64:
    if rhs < 0 and lhs > Int64.MAX_FINITE + rhs:
        raise Error("fixed FFT wide butterfly subtraction overflowed Int64")
    if rhs > 0 and lhs < Int64.MIN_FINITE + rhs:
        raise Error("fixed FFT wide butterfly subtraction overflowed Int64")
    return lhs - rhs


def quantized_fft_twiddles(
    size: Int, twiddle_format: QFormat, *, inverse: Bool = False
) raises -> List[ComplexRaw]:
    """Generate a canonical half-table in the declared twiddle Q-format."""
    _ = _fft_stage_count(size)
    var result = List[ComplexRaw](capacity=size // 2)
    for k in range(size // 2):
        var angle = (
            (_TWO_PI if inverse else -_TWO_PI)
            * Float64(k)
            / Float64(size)
        )
        result.append(
            ComplexRaw(
                quantize_raw(cos(angle), twiddle_format),
                quantize_raw(sin(angle), twiddle_format),
            )
        )
    return result^


def _fixed_fft_radix2_raw_impl(
    values: Span[ComplexRaw, ...],
    input_format: QFormat,
    twiddles: Span[ComplexRaw, ...],
    twiddle_format: QFormat,
    stages: Span[ScaleStage, ...],
    capture_trace: Bool,
) raises -> FixedFFTTrace:
    """Transform using supplied bit-exact twiddles and per-stage contracts.

    Each butterfly combines wide products, applies the stage's right shift,
    then rounds/narrows once into its output Q-format.  Supplying twiddles
    rather than hiding libm calls makes RTL comparisons completely explicit.
    For an IFFT, supply positive-angle twiddles and a schedule whose total
    right shift equals log2(N).
    """
    var size = len(values)
    var stage_count = _fft_stage_count(size)
    if len(stages) != stage_count:
        raise Error("fixed FFT scale schedule length must equal log2(size)")
    if len(twiddles) < size // 2:
        raise Error("fixed FFT requires a half-length twiddle table")
    var validated_input = validate_qformat(input_format)
    var validated_twiddle = validate_qformat(twiddle_format)
    if (
        validated_input.storage_bits > 30
        or validated_twiddle.storage_bits > 24
    ):
        raise Error("fixed FFT formats exceed the Int64 wide-butterfly model")
    if validated_input.storage_bits + validated_twiddle.storage_bits > 54:
        raise Error("fixed FFT product has insufficient Int64 guard bits")

    var stage_formats = List[QFormat](capacity=stage_count)
    var stage_right_shifts = List[Int](capacity=stage_count)
    for stage_index in range(stage_count):
        var stage = stages[stage_index]
        var stage_format = validate_qformat(stage.output_format)
        var right_shift = stage.right_shift
        if right_shift < 0 or right_shift > 61:
            raise Error("mutated fixed FFT stage shift must be in [0, 61]")
        if stage_format.storage_bits > 30:
            raise Error("fixed FFT stage width exceeds 30-bit guard contract")
        if stage_format.storage_bits + validated_twiddle.storage_bits > 54:
            raise Error("fixed FFT stage product has insufficient Int64 guard bits")
        stage_formats.append(stage_format)
        stage_right_shifts.append(right_shift)

    var result = List[ComplexRaw](capacity=size)
    var traced_input = List[ComplexRaw](capacity=size if capture_trace else 0)
    for i in range(size):
        require_complex_fits(
            ComplexRaw(values[i].re, values[i].im), validated_input
        )
        result.append(ComplexRaw(values[i].re, values[i].im))
        if capture_trace:
            traced_input.append(ComplexRaw(values[i].re, values[i].im))
    var traced_twiddles = List[ComplexRaw](
        capacity=size // 2 if capture_trace else 0
    )
    for i in range(size // 2):
        require_complex_fits(
            ComplexRaw(twiddles[i].re, twiddles[i].im), validated_twiddle
        )
        if capture_trace:
            traced_twiddles.append(
                ComplexRaw(twiddles[i].re, twiddles[i].im)
            )

    # Iterative bit-reversal permutation.
    var reversed_index = 0
    for i in range(1, size):
        var bit = size >> 1
        while (reversed_index & bit) != 0:
            reversed_index ^= bit
            bit >>= 1
        reversed_index ^= bit
        if i < reversed_index:
            var temporary = result[i]
            result[i] = result[reversed_index]
            result[reversed_index] = temporary

    var traced_stage_values = List[ComplexRaw](
        capacity=size * stage_count if capture_trace else 0
    )
    var traced_storage_bits = List[Int](
        capacity=stage_count if capture_trace else 0
    )
    var traced_fraction_bits = List[Int](
        capacity=stage_count if capture_trace else 0
    )
    var traced_right_shifts = List[Int](
        capacity=stage_count if capture_trace else 0
    )
    var traced_rounding_modes = List[Int](
        capacity=stage_count if capture_trace else 0
    )
    var traced_overflow_modes = List[Int](
        capacity=stage_count if capture_trace else 0
    )
    var current_format = validated_input
    var length = 2
    var stage_index = 0
    while length <= size:
        var output_format = stage_formats[stage_index]
        var right_shift = stage_right_shifts[stage_index]
        var twiddle_stride = size // length
        var base = 0
        while base < size:
            for offset in range(length // 2):
                var even_index = base + offset
                var odd_index = even_index + length // 2
                var even = result[even_index]
                var odd = result[odd_index]
                var twiddle = twiddles[offset * twiddle_stride]

                # Retain the complete complex product until the butterfly
                # output's binary point is selected.
                var product_fraction = (
                    current_format.fraction_bits
                    + twiddle_format.fraction_bits
                )
                var product_re = odd.re * twiddle.re - odd.im * twiddle.im
                var product_im = odd.re * twiddle.im + odd.im * twiddle.re
                var aligned_product_re = _align_wide(
                    product_re,
                    product_fraction,
                    output_format.fraction_bits,
                    output_format.rounding_mode,
                )
                var aligned_product_im = _align_wide(
                    product_im,
                    product_fraction,
                    output_format.fraction_bits,
                    output_format.rounding_mode,
                )
                var aligned_even_re = _align_wide(
                    even.re,
                    current_format.fraction_bits,
                    output_format.fraction_bits,
                    output_format.rounding_mode,
                )
                var aligned_even_im = _align_wide(
                    even.im,
                    current_format.fraction_bits,
                    output_format.fraction_bits,
                    output_format.rounding_mode,
                )

                var top_re = rounded_shift_right(
                    _checked_add(aligned_even_re, aligned_product_re),
                    right_shift,
                    output_format.rounding_mode,
                )
                var top_im = rounded_shift_right(
                    _checked_add(aligned_even_im, aligned_product_im),
                    right_shift,
                    output_format.rounding_mode,
                )
                var bottom_re = rounded_shift_right(
                    _checked_sub(aligned_even_re, aligned_product_re),
                    right_shift,
                    output_format.rounding_mode,
                )
                var bottom_im = rounded_shift_right(
                    _checked_sub(aligned_even_im, aligned_product_im),
                    right_shift,
                    output_format.rounding_mode,
                )
                result[even_index] = ComplexRaw(
                    narrow_raw(top_re, output_format),
                    narrow_raw(top_im, output_format),
                )
                result[odd_index] = ComplexRaw(
                    narrow_raw(bottom_re, output_format),
                    narrow_raw(bottom_im, output_format),
                )
            base += length
        current_format = output_format
        if capture_trace:
            for value in result:
                traced_stage_values.append(ComplexRaw(value.re, value.im))
            traced_storage_bits.append(output_format.storage_bits)
            traced_fraction_bits.append(output_format.fraction_bits)
            traced_right_shifts.append(right_shift)
            traced_rounding_modes.append(output_format.rounding_mode)
            traced_overflow_modes.append(output_format.overflow_mode)
        stage_index += 1
        length <<= 1
    return FixedFFTTrace(
        size,
        validated_input,
        validated_twiddle,
        traced_input^,
        traced_twiddles^,
        traced_stage_values^,
        traced_storage_bits^,
        traced_fraction_bits^,
        traced_right_shifts^,
        traced_rounding_modes^,
        traced_overflow_modes^,
        result^,
    )


def fixed_fft_radix2_raw(
    values: Span[ComplexRaw, ...],
    input_format: QFormat,
    twiddles: Span[ComplexRaw, ...],
    twiddle_format: QFormat,
    stages: Span[ScaleStage, ...],
) raises -> List[ComplexRaw]:
    """Compatibility entry point returning only the final FFT output."""
    var trace = _fixed_fft_radix2_raw_impl(
        values,
        input_format,
        twiddles,
        twiddle_format,
        stages,
        False,
    )
    return trace^.take_output()


def fixed_fft_radix2_trace_raw(
    values: Span[ComplexRaw, ...],
    input_format: QFormat,
    twiddles: Span[ComplexRaw, ...],
    twiddle_format: QFormat,
    stages: Span[ScaleStage, ...],
) raises -> FixedFFTTrace:
    """Run the FFT and retain its exact ROM and every full stage output."""
    return _fixed_fft_radix2_raw_impl(
        values,
        input_format,
        twiddles,
        twiddle_format,
        stages,
        True,
    )


def _validate_fixed_fft_trace(trace: FixedFFTTrace) raises -> Int:
    var stage_count = _fft_stage_count(trace.size)
    var input_format = validate_qformat(trace.input_format)
    var twiddle_format = validate_qformat(trace.twiddle_format)
    if (
        len(trace.input_values) != trace.size
        or len(trace.twiddles) != trace.size // 2
        or len(trace.output) != trace.size
        or len(trace.stage_values) != trace.size * stage_count
        or len(trace.stage_storage_bits) != stage_count
        or len(trace.stage_fraction_bits) != stage_count
        or len(trace.stage_right_shifts) != stage_count
        or len(trace.stage_rounding_modes) != stage_count
        or len(trace.stage_overflow_modes) != stage_count
    ):
        raise Error("fixed FFT trace dimensions are inconsistent")
    for value in trace.input_values:
        require_complex_fits(value, input_format)
    for value in trace.twiddles:
        require_complex_fits(value, twiddle_format)
    for stage_index in range(stage_count):
        var stage_format = validate_qformat(QFormat(
            trace.stage_storage_bits[stage_index],
            trace.stage_fraction_bits[stage_index],
            trace.stage_rounding_modes[stage_index],
            trace.stage_overflow_modes[stage_index],
        ))
        var shift = trace.stage_right_shifts[stage_index]
        if shift < 0 or shift > 61:
            raise Error("fixed FFT trace stage shift must be in [0, 61]")
        for element in range(trace.size):
            require_complex_fits(
                trace.stage_values[stage_index * trace.size + element],
                stage_format,
            )
    var output_format = input_format
    if stage_count > 0:
        output_format = QFormat(
            trace.stage_storage_bits[stage_count - 1],
            trace.stage_fraction_bits[stage_count - 1],
            trace.stage_rounding_modes[stage_count - 1],
            trace.stage_overflow_modes[stage_count - 1],
        )
    for element in range(trace.size):
        require_complex_fits(trace.output[element], output_format)
        var expected = (
            trace.input_values[element]
            if stage_count == 0
            else trace.stage_values[(stage_count - 1) * trace.size + element]
        )
        if trace.output[element] != expected:
            raise Error("fixed FFT trace output differs from its final stage")
    return stage_count


def _fixed_fft_trace_checksum(trace: FixedFFTTrace) raises -> UInt64:
    var stage_count = _validate_fixed_fft_trace(trace)
    var words: List[Int64] = [
        Int64(2),
        Int64(trace.size),
        Int64(stage_count),
        Int64(trace.input_format.storage_bits),
        Int64(trace.input_format.fraction_bits),
        Int64(trace.input_format.rounding_mode),
        Int64(trace.input_format.overflow_mode),
        Int64(trace.twiddle_format.storage_bits),
        Int64(trace.twiddle_format.fraction_bits),
        Int64(trace.twiddle_format.rounding_mode),
        Int64(trace.twiddle_format.overflow_mode),
    ]
    for stage_index in range(stage_count):
        words.append(Int64(trace.stage_storage_bits[stage_index]))
        words.append(Int64(trace.stage_fraction_bits[stage_index]))
        words.append(Int64(trace.stage_right_shifts[stage_index]))
        words.append(Int64(trace.stage_rounding_modes[stage_index]))
        words.append(Int64(trace.stage_overflow_modes[stage_index]))
    for value in trace.input_values:
        words.append(value.re)
        words.append(value.im)
    for value in trace.twiddles:
        words.append(value.re)
        words.append(value.im)
    for value in trace.stage_values:
        words.append(value.re)
        words.append(value.im)
    for value in trace.output:
        words.append(value.re)
        words.append(value.im)
    return fixed_raw_checksum(Span(words))


def serialize_fixed_fft_trace(
    testcase_id: StringSlice,
    stage_prefix: StringSlice,
    trace: FixedFFTTrace,
    version: Int = 2,
) raises -> String:
    """Serialize a complete FFT trace as independently protected V2 records."""
    if testcase_id.byte_length() == 0 or stage_prefix.byte_length() == 0:
        raise Error("fixed FFT trace testcase and stage prefix must be non-empty")
    if (
        "\n" in testcase_id or "\r" in testcase_id
        or "\n" in stage_prefix or "\r" in stage_prefix
    ):
        raise Error("fixed FFT trace identifiers cannot contain line breaks")
    if version < 1:
        raise Error("fixed FFT trace version must be positive")
    var stage_count = _validate_fixed_fft_trace(trace)
    var config: List[Int64] = [Int64(trace.size), Int64(stage_count)]
    var config_stage = String()
    config_stage.write(stage_prefix, "-config")
    var input_stage = String()
    input_stage.write(stage_prefix, "-input")
    var twiddle_stage = String()
    twiddle_stage.write(stage_prefix, "-twiddle-rom")
    var schedule_stage = String()
    schedule_stage.write(stage_prefix, "-schedule")
    var output_stage = String()
    output_stage.write(stage_prefix, "-output")

    var result = String()
    result.write(serialize_fixed_vector(
        testcase_id,
        StringSlice(config_stage),
        Span(config),
        QFormat(32, 0),
        version=version,
    ))
    result.write(serialize_complex_fixed_vector(
        testcase_id,
        StringSlice(input_stage),
        Span(trace.input_values),
        trace.input_format,
        version=version,
    ))
    result.write(serialize_complex_fixed_vector(
        testcase_id,
        StringSlice(twiddle_stage),
        Span(trace.twiddles),
        trace.twiddle_format,
        version=version,
    ))

    var schedule_values = List[Int64](capacity=stage_count)
    for stage_index in range(stage_count):
        schedule_values.append(
            trace.stage_values[stage_index * trace.size].re
        )
    var schedule = ScaleTrace(
        schedule_values^,
        trace.stage_fraction_bits.copy(),
        trace.stage_storage_bits.copy(),
        trace.stage_right_shifts.copy(),
        trace.stage_rounding_modes.copy(),
        trace.stage_overflow_modes.copy(),
    )
    result.write(serialize_scale_trace(
        testcase_id,
        StringSlice(schedule_stage),
        schedule,
        version=version,
    ))

    for stage_index in range(stage_count):
        var stage_values = List[ComplexRaw](capacity=trace.size)
        for element in range(trace.size):
            var value = trace.stage_values[
                stage_index * trace.size + element
            ]
            stage_values.append(ComplexRaw(value.re, value.im))
        var stage_name = String()
        stage_name.write(stage_prefix, "-stage-", stage_index)
        var stage_format = QFormat(
            trace.stage_storage_bits[stage_index],
            trace.stage_fraction_bits[stage_index],
            trace.stage_rounding_modes[stage_index],
            trace.stage_overflow_modes[stage_index],
        )
        result.write(serialize_complex_fixed_vector(
            testcase_id,
            StringSlice(stage_name),
            Span(stage_values),
            stage_format,
            version=version,
        ))
    result.write(serialize_complex_fixed_vector(
        testcase_id,
        StringSlice(output_stage),
        Span(trace.output),
        (
            trace.input_format
            if stage_count == 0
            else QFormat(
                trace.stage_storage_bits[stage_count - 1],
                trace.stage_fraction_bits[stage_count - 1],
                trace.stage_rounding_modes[stage_count - 1],
                trace.stage_overflow_modes[stage_count - 1],
            )
        ),
        version=version,
    ))
    var checksum = _fixed_fft_trace_checksum(trace)
    var checksum_words: List[Int64] = [
        Int64(checksum & UInt64(0xffffffff)),
        Int64(checksum >> UInt64(32)),
    ]
    var checksum_stage = String()
    checksum_stage.write(stage_prefix, "-trace-checksum-lohi32")
    result.write(serialize_fixed_vector(
        testcase_id,
        StringSlice(checksum_stage),
        Span(checksum_words),
        QFormat(33, 0),
        version=version,
    ))
    return result^
