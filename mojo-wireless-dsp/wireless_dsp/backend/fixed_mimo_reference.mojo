"""Bit-exact 2x2 complex fixed-point MIMO golden kernels.

The matrix is row-major and all vectors contain exactly two complex values.
Every complex dot product rounds each full complex product into the declared
accumulator format and narrows after each registered MAC.  Gram and matched
filter outputs then cross one explicit rescale/narrow boundary.

The ZF solver uses the Hermitian normal equations.  For
``G = H^H H = [[a, b], [conj(b), d]]`` and ``z = H^H y`` it evaluates
``det = a*d - |b|^2`` in a signed 62-bit Q format with twice the Gram
fraction width.  A caller-supplied non-negative raw determinant threshold is
inclusive: ``det <= threshold`` is singular.  The reciprocal is exact integer
division of ``2^(det_fraction + reciprocal_fraction)`` by ``det``, with the
reciprocal format's nearest-away or toward-zero rule, followed by its declared
saturate/wrap narrowing.  Closed-form numerators are accumulated wide, then
rounded/narrowed once into ``numerator`` before the reciprocal multiply and
final output boundary.  Unsupported Int64 scale products are rejected.
"""

from std.collections import Span
from wireless_dsp.numerics.fixed import (
    ROUND_NEAREST_AWAY,
    OVERFLOW_SATURATE,
)
from wireless_dsp.numerics.quantization import (
    QFormat,
    fixed_mul_raw,
    narrow_raw,
    require_raw_fits,
    rescale_raw,
)
from wireless_dsp.numerics.complex_fixed import (
    ComplexRaw,
    complex_conjugate_raw,
    complex_mac_conjugate_raw,
    complex_mac_raw,
    require_complex_fits,
)
from wireless_dsp.testing.fixed_vectors import (
    complex_raw_checksum,
    fixed_raw_checksum,
    serialize_complex_fixed_vector,
    serialize_fixed_vector,
)


struct FixedMIMOFormats(ImplicitlyCopyable):
    """Q formats at every public 2x2 MIMO register boundary."""

    var channel: QFormat
    var symbol: QFormat
    var observation: QFormat
    var accumulator: QFormat
    var gram: QFormat
    var matched: QFormat
    var numerator: QFormat
    var reciprocal: QFormat
    var output: QFormat

    def __init__(
        out self,
        channel: QFormat,
        symbol: QFormat,
        observation: QFormat,
        accumulator: QFormat,
        gram: QFormat,
        matched: QFormat,
        numerator: QFormat,
        reciprocal: QFormat,
        output: QFormat,
    ):
        self.channel = channel
        self.symbol = symbol
        self.observation = observation
        self.accumulator = accumulator
        self.gram = gram
        self.matched = matched
        self.numerator = numerator
        self.reciprocal = reciprocal
        self.output = output


struct FixedMIMOZFScaleTrace(ImplicitlyCopyable):
    """Scale contract and nonlinear scalar checkpoints of one ZF solve."""

    var determinant_format: QFormat
    var determinant_raw: Int64
    var singular_threshold_raw: Int64
    var reciprocal_raw: Int64
    var gram_source_fraction_bits: Int
    var matched_source_fraction_bits: Int
    var numerator_source_fraction_bits: Int
    var reciprocal_numerator_exponent: Int
    var output_product_fraction_bits: Int

    def __init__(
        out self,
        determinant_format: QFormat,
        determinant_raw: Int64,
        singular_threshold_raw: Int64,
        reciprocal_raw: Int64,
        gram_source_fraction_bits: Int,
        matched_source_fraction_bits: Int,
        numerator_source_fraction_bits: Int,
        reciprocal_numerator_exponent: Int,
        output_product_fraction_bits: Int,
    ):
        self.determinant_format = determinant_format
        self.determinant_raw = determinant_raw
        self.singular_threshold_raw = singular_threshold_raw
        self.reciprocal_raw = reciprocal_raw
        self.gram_source_fraction_bits = gram_source_fraction_bits
        self.matched_source_fraction_bits = matched_source_fraction_bits
        self.numerator_source_fraction_bits = numerator_source_fraction_bits
        self.reciprocal_numerator_exponent = reciprocal_numerator_exponent
        self.output_product_fraction_bits = output_product_fraction_bits


struct FixedMIMOZF2x2Result(Movable):
    """Owned bit-exact checkpoints of a 2x2 normal-equation ZF solve."""

    var formats: FixedMIMOFormats
    var channel: List[ComplexRaw]
    var observation: List[ComplexRaw]
    var gram: List[ComplexRaw]
    var matched: List[ComplexRaw]
    var numerators: List[ComplexRaw]
    var estimates: List[ComplexRaw]
    var scale_trace: FixedMIMOZFScaleTrace

    def __init__(
        out self,
        formats: FixedMIMOFormats,
        var channel: List[ComplexRaw],
        var observation: List[ComplexRaw],
        var gram: List[ComplexRaw],
        var matched: List[ComplexRaw],
        var numerators: List[ComplexRaw],
        var estimates: List[ComplexRaw],
        scale_trace: FixedMIMOZFScaleTrace,
    ):
        self.formats = formats
        self.channel = channel^
        self.observation = observation^
        self.gram = gram^
        self.matched = matched^
        self.numerators = numerators^
        self.estimates = estimates^
        self.scale_trace = scale_trace


def fixed_mimo_default_formats() raises -> FixedMIMOFormats:
    """Return a precision/growth contract audited for ordinary unit channels."""
    return FixedMIMOFormats(
        QFormat(16, 12, ROUND_NEAREST_AWAY, OVERFLOW_SATURATE),
        QFormat(16, 12, ROUND_NEAREST_AWAY, OVERFLOW_SATURATE),
        QFormat(18, 12, ROUND_NEAREST_AWAY, OVERFLOW_SATURATE),
        QFormat(40, 24, ROUND_NEAREST_AWAY, OVERFLOW_SATURATE),
        QFormat(24, 16, ROUND_NEAREST_AWAY, OVERFLOW_SATURATE),
        QFormat(24, 16, ROUND_NEAREST_AWAY, OVERFLOW_SATURATE),
        QFormat(30, 18, ROUND_NEAREST_AWAY, OVERFLOW_SATURATE),
        QFormat(30, 24, ROUND_NEAREST_AWAY, OVERFLOW_SATURATE),
        QFormat(18, 12, ROUND_NEAREST_AWAY, OVERFLOW_SATURATE),
    )


def _require_matrix_2x2(values: Span[ComplexRaw, ...]) raises:
    if len(values) != 4:
        raise Error("fixed MIMO matrix must contain four row-major values")


def _require_vector_2(values: Span[ComplexRaw, ...]) raises:
    if len(values) != 2:
        raise Error("fixed MIMO vector must contain exactly two values")


def _rescale_complex(
    value: ComplexRaw,
    input_fraction_bits: Int,
    output_format: QFormat,
) raises -> ComplexRaw:
    return ComplexRaw(
        rescale_raw(value.re, input_fraction_bits, output_format),
        rescale_raw(value.im, input_fraction_bits, output_format),
    )


def fixed_complex_matvec_2x2_raw(
    matrix: Span[ComplexRaw, ...],
    vector: Span[ComplexRaw, ...],
    matrix_format: QFormat,
    vector_format: QFormat,
    accumulator_format: QFormat,
    output_format: QFormat,
) raises -> List[ComplexRaw]:
    """Return ``matrix @ vector`` with a registered narrow after each MAC."""
    _require_matrix_2x2(matrix)
    _require_vector_2(vector)
    var result = List[ComplexRaw](capacity=2)
    for row in range(2):
        var accumulator = ComplexRaw()
        for column in range(2):
            accumulator = complex_mac_raw(
                accumulator,
                ComplexRaw(
                    matrix[2 * row + column].re,
                    matrix[2 * row + column].im,
                ),
                matrix_format,
                ComplexRaw(vector[column].re, vector[column].im),
                vector_format,
                accumulator_format,
            )
        result.append(_rescale_complex(
            accumulator, accumulator_format.fraction_bits, output_format
        ))
    return result^


def fixed_hermitian_matched_filter_2x2_raw(
    channel: Span[ComplexRaw, ...],
    observation: Span[ComplexRaw, ...],
    channel_format: QFormat,
    observation_format: QFormat,
    accumulator_format: QFormat,
    output_format: QFormat,
) raises -> List[ComplexRaw]:
    """Return ``H^H y`` with explicit MAC and output register formats."""
    _require_matrix_2x2(channel)
    _require_vector_2(observation)
    var result = List[ComplexRaw](capacity=2)
    for column in range(2):
        var accumulator = ComplexRaw()
        for row in range(2):
            accumulator = complex_mac_conjugate_raw(
                accumulator,
                ComplexRaw(
                    channel[2 * row + column].re,
                    channel[2 * row + column].im,
                ),
                channel_format,
                ComplexRaw(observation[row].re, observation[row].im),
                observation_format,
                accumulator_format,
            )
        result.append(_rescale_complex(
            accumulator, accumulator_format.fraction_bits, output_format
        ))
    return result^


def _fixed_hermitian_dot_columns_2x2_raw(
    channel: Span[ComplexRaw, ...],
    lhs_column: Int,
    rhs_column: Int,
    channel_format: QFormat,
    accumulator_format: QFormat,
    output_format: QFormat,
) raises -> ComplexRaw:
    var accumulator = ComplexRaw()
    for row in range(2):
        accumulator = complex_mac_conjugate_raw(
            accumulator,
            ComplexRaw(
                channel[2 * row + lhs_column].re,
                channel[2 * row + lhs_column].im,
            ),
            channel_format,
            ComplexRaw(
                channel[2 * row + rhs_column].re,
                channel[2 * row + rhs_column].im,
            ),
            channel_format,
            accumulator_format,
        )
    return _rescale_complex(
        accumulator, accumulator_format.fraction_bits, output_format
    )


def fixed_hermitian_gram_2x2_raw(
    channel: Span[ComplexRaw, ...],
    channel_format: QFormat,
    accumulator_format: QFormat,
    output_format: QFormat,
) raises -> List[ComplexRaw]:
    """Return row-major ``H^H H`` and enforce exact Hermitian storage."""
    _require_matrix_2x2(channel)
    var g00 = _fixed_hermitian_dot_columns_2x2_raw(
        channel, 0, 0, channel_format, accumulator_format, output_format
    )
    var g01 = _fixed_hermitian_dot_columns_2x2_raw(
        channel, 0, 1, channel_format, accumulator_format, output_format
    )
    var g11 = _fixed_hermitian_dot_columns_2x2_raw(
        channel, 1, 1, channel_format, accumulator_format, output_format
    )
    var g10 = complex_conjugate_raw(g01, output_format)
    return [g00, g01, g10, g11]


def fixed_mimo_reciprocal_positive_raw(
    value_raw: Int64,
    input_format: QFormat,
    output_format: QFormat,
) raises -> Int64:
    """Return a positive reciprocal via exact integer division and narrowing."""
    require_raw_fits(value_raw, input_format)
    if value_raw <= 0:
        raise Error("fixed MIMO reciprocal requires a positive determinant")
    var exponent = input_format.fraction_bits + output_format.fraction_bits
    if exponent > 61:
        raise Error("fixed MIMO reciprocal scale exceeds the Int64 model")
    var numerator = Int64(1) << Int64(exponent)
    var quotient = numerator // value_raw
    var remainder = numerator % value_raw
    if (
        output_format.rounding_mode == ROUND_NEAREST_AWAY
        and remainder * 2 >= value_raw
    ):
        quotient += 1
    return narrow_raw(quotient, output_format)


def _validate_zf_formats(formats: FixedMIMOFormats) raises:
    if (
        formats.channel.storage_bits > 31
        or formats.observation.storage_bits > 31
        or formats.gram.storage_bits > 31
        or formats.matched.storage_bits > 31
        or formats.numerator.storage_bits > 31
        or formats.reciprocal.storage_bits > 31
    ):
        raise Error("fixed MIMO multiplier operands are limited to 31 bits")
    if (
        formats.channel.fraction_bits + formats.channel.fraction_bits > 61
        or formats.channel.fraction_bits
        + formats.observation.fraction_bits > 61
        or 2 * formats.gram.fraction_bits > 61
        or formats.gram.fraction_bits + formats.matched.fraction_bits > 61
        or 2 * formats.gram.fraction_bits
        + formats.reciprocal.fraction_bits > 61
        or formats.numerator.fraction_bits
        + formats.reciprocal.fraction_bits > 61
    ):
        raise Error("fixed MIMO binary-point product exceeds the Int64 model")


def fixed_mimo_determinant_format(
    formats: FixedMIMOFormats,
) raises -> QFormat:
    """Return the exact raw Q format used by the determinant threshold port."""
    if formats.gram.storage_bits > 31:
        raise Error("fixed MIMO determinant operands are limited to 31 bits")
    var fraction_bits = 2 * formats.gram.fraction_bits
    if fraction_bits > 61:
        raise Error("fixed MIMO determinant fraction width exceeds Int64")
    return QFormat(
        62,
        fraction_bits,
        formats.gram.rounding_mode,
        formats.gram.overflow_mode,
    )


def fixed_zf_equalize_2x2_raw(
    channel: Span[ComplexRaw, ...],
    observation: Span[ComplexRaw, ...],
    formats: FixedMIMOFormats,
    determinant_singular_threshold_raw: Int64,
) raises -> FixedMIMOZF2x2Result:
    """Solve a full-rank 2x2 channel with bit-exact normal-equation ZF."""
    _require_matrix_2x2(channel)
    _require_vector_2(observation)
    _validate_zf_formats(formats)
    var gram = fixed_hermitian_gram_2x2_raw(
        channel, formats.channel, formats.accumulator, formats.gram
    )
    var matched = fixed_hermitian_matched_filter_2x2_raw(
        channel,
        observation,
        formats.channel,
        formats.observation,
        formats.accumulator,
        formats.matched,
    )
    if gram[0].im != 0 or gram[3].im != 0:
        raise Error("fixed MIMO Gram diagonal is not real")
    if gram[0].re <= 0 or gram[3].re <= 0:
        raise Error("fixed MIMO Gram diagonal is not positive")

    var determinant_format = fixed_mimo_determinant_format(formats)
    var determinant_fraction_bits = determinant_format.fraction_bits
    require_raw_fits(
        determinant_singular_threshold_raw, determinant_format
    )
    if determinant_singular_threshold_raw < 0:
        raise Error("fixed MIMO determinant threshold must be non-negative")
    var off_diagonal = ComplexRaw(gram[1].re, gram[1].im)
    require_complex_fits(off_diagonal, formats.gram)
    var determinant_raw = (
        gram[0].re * gram[3].re
        - off_diagonal.re * off_diagonal.re
        - off_diagonal.im * off_diagonal.im
    )
    if determinant_raw <= determinant_singular_threshold_raw:
        raise Error("fixed MIMO Gram determinant is singular at the threshold")
    require_raw_fits(determinant_raw, determinant_format)
    var reciprocal_raw = fixed_mimo_reciprocal_positive_raw(
        determinant_raw, determinant_format, formats.reciprocal
    )

    var a = gram[0].re
    var d = gram[3].re
    var b = off_diagonal
    var z0 = ComplexRaw(matched[0].re, matched[0].im)
    var z1 = ComplexRaw(matched[1].re, matched[1].im)
    var b_z1 = ComplexRaw(
        b.re * z1.re - b.im * z1.im,
        b.re * z1.im + b.im * z1.re,
    )
    var conjugate_b_z0 = ComplexRaw(
        b.re * z0.re + b.im * z0.im,
        b.re * z0.im - b.im * z0.re,
    )
    var numerator_source_fraction_bits = (
        formats.gram.fraction_bits + formats.matched.fraction_bits
    )
    var numerator0_wide = ComplexRaw(
        d * z0.re - b_z1.re,
        d * z0.im - b_z1.im,
    )
    var numerator1_wide = ComplexRaw(
        a * z1.re - conjugate_b_z0.re,
        a * z1.im - conjugate_b_z0.im,
    )
    var numerators: List[ComplexRaw] = [
        _rescale_complex(
            numerator0_wide,
            numerator_source_fraction_bits,
            formats.numerator,
        ),
        _rescale_complex(
            numerator1_wide,
            numerator_source_fraction_bits,
            formats.numerator,
        ),
    ]
    var estimates = List[ComplexRaw](capacity=2)
    for index in range(2):
        estimates.append(ComplexRaw(
            fixed_mul_raw(
                numerators[index].re,
                formats.numerator,
                reciprocal_raw,
                formats.reciprocal,
                formats.output,
            ),
            fixed_mul_raw(
                numerators[index].im,
                formats.numerator,
                reciprocal_raw,
                formats.reciprocal,
                formats.output,
            ),
        ))

    var channel_copy = List[ComplexRaw](capacity=4)
    for index in range(4):
        channel_copy.append(ComplexRaw(channel[index].re, channel[index].im))
    var observation_copy = List[ComplexRaw](capacity=2)
    for index in range(2):
        observation_copy.append(ComplexRaw(
            observation[index].re, observation[index].im
        ))
    var trace = FixedMIMOZFScaleTrace(
        determinant_format,
        determinant_raw,
        determinant_singular_threshold_raw,
        reciprocal_raw,
        formats.accumulator.fraction_bits,
        formats.accumulator.fraction_bits,
        numerator_source_fraction_bits,
        determinant_fraction_bits + formats.reciprocal.fraction_bits,
        formats.numerator.fraction_bits + formats.reciprocal.fraction_bits,
    )
    return FixedMIMOZF2x2Result(
        formats,
        channel_copy^,
        observation_copy^,
        gram^,
        matched^,
        numerators^,
        estimates^,
        trace,
    )


def fixed_mimo_zf_result_checksum(result: FixedMIMOZF2x2Result) -> UInt64:
    """Checksum all ZF numeric checkpoints in canonical stage order."""
    var values = List[ComplexRaw](capacity=18)
    for value in result.channel:
        values.append(value)
    for value in result.observation:
        values.append(value)
    for value in result.gram:
        values.append(value)
    for value in result.matched:
        values.append(value)
    for value in result.numerators:
        values.append(value)
    for value in result.estimates:
        values.append(value)
    values.append(ComplexRaw(
        result.scale_trace.determinant_raw,
        result.scale_trace.singular_threshold_raw,
    ))
    values.append(ComplexRaw(result.scale_trace.reciprocal_raw, 0))
    return complex_raw_checksum(Span(values))


def _validate_zf_result(result: FixedMIMOZF2x2Result) raises:
    if (
        len(result.channel) != 4
        or len(result.observation) != 2
        or len(result.gram) != 4
        or len(result.matched) != 2
        or len(result.numerators) != 2
        or len(result.estimates) != 2
    ):
        raise Error("fixed MIMO ZF result checkpoint dimensions are invalid")
    for value in result.channel:
        require_complex_fits(value, result.formats.channel)
    for value in result.observation:
        require_complex_fits(value, result.formats.observation)
    for value in result.gram:
        require_complex_fits(value, result.formats.gram)
    for value in result.matched:
        require_complex_fits(value, result.formats.matched)
    for value in result.numerators:
        require_complex_fits(value, result.formats.numerator)
    for value in result.estimates:
        require_complex_fits(value, result.formats.output)
    require_raw_fits(
        result.scale_trace.determinant_raw,
        result.scale_trace.determinant_format,
    )
    require_raw_fits(
        result.scale_trace.singular_threshold_raw,
        result.scale_trace.determinant_format,
    )
    require_raw_fits(
        result.scale_trace.reciprocal_raw, result.formats.reciprocal
    )
    if (
        result.scale_trace.gram_source_fraction_bits
        != result.formats.accumulator.fraction_bits
        or result.scale_trace.matched_source_fraction_bits
        != result.formats.accumulator.fraction_bits
        or result.scale_trace.numerator_source_fraction_bits
        != result.formats.gram.fraction_bits
        + result.formats.matched.fraction_bits
        or result.scale_trace.reciprocal_numerator_exponent
        != result.scale_trace.determinant_format.fraction_bits
        + result.formats.reciprocal.fraction_bits
        or result.scale_trace.output_product_fraction_bits
        != result.formats.numerator.fraction_bits
        + result.formats.reciprocal.fraction_bits
    ):
        raise Error("fixed MIMO ZF scale trace is inconsistent")


def fixed_mimo_zf_scale_trace_text(
    result: FixedMIMOZF2x2Result,
) raises -> String:
    """Serialize actual values and Q transitions at every ZF scale boundary."""
    _validate_zf_result(result)
    var raw_values = List[Int64](capacity=22)
    for value in result.gram:
        raw_values.append(value.re)
        raw_values.append(value.im)
    for value in result.matched:
        raw_values.append(value.re)
        raw_values.append(value.im)
    raw_values.append(result.scale_trace.determinant_raw)
    raw_values.append(result.scale_trace.reciprocal_raw)
    for value in result.numerators:
        raw_values.append(value.re)
        raw_values.append(value.im)
    for value in result.estimates:
        raw_values.append(value.re)
        raw_values.append(value.im)

    var text = String()
    text.write("MWDSP-FIXED-MIMO-SCALE-TRACE-V1\n")
    text.write("testcase=fixed-mimo-zf-2x2\n")
    text.write("version=1\n")
    text.write("shape=22x5\n")
    text.write("columns=stage:raw:storage_bits:fraction_bits:source_fraction_bits\n")
    text.write(
        "accumulator=sint",
        result.formats.accumulator.storage_bits,
        ":",
        result.formats.accumulator.fraction_bits,
        ":rounding=",
        result.formats.accumulator.rounding_mode,
        ":overflow=",
        result.formats.accumulator.overflow_mode,
        "\n",
    )
    text.write(
        "gram=sint",
        result.formats.gram.storage_bits,
        ":",
        result.formats.gram.fraction_bits,
        ":rounding=",
        result.formats.gram.rounding_mode,
        ":overflow=",
        result.formats.gram.overflow_mode,
        "\n",
    )
    text.write(
        "matched=sint",
        result.formats.matched.storage_bits,
        ":",
        result.formats.matched.fraction_bits,
        ":rounding=",
        result.formats.matched.rounding_mode,
        ":overflow=",
        result.formats.matched.overflow_mode,
        "\n",
    )
    text.write(
        "numerator=sint",
        result.formats.numerator.storage_bits,
        ":",
        result.formats.numerator.fraction_bits,
        ":rounding=",
        result.formats.numerator.rounding_mode,
        ":overflow=",
        result.formats.numerator.overflow_mode,
        "\n",
    )
    text.write(
        "reciprocal=sint",
        result.formats.reciprocal.storage_bits,
        ":",
        result.formats.reciprocal.fraction_bits,
        ":rounding=",
        result.formats.reciprocal.rounding_mode,
        ":overflow=",
        result.formats.reciprocal.overflow_mode,
        "\n",
    )
    text.write(
        "output=sint",
        result.formats.output.storage_bits,
        ":",
        result.formats.output.fraction_bits,
        ":rounding=",
        result.formats.output.rounding_mode,
        ":overflow=",
        result.formats.output.overflow_mode,
        "\n",
    )
    text.write(
        "determinant_threshold_raw=",
        result.scale_trace.singular_threshold_raw,
        "\n",
    )
    text.write(
        "reciprocal_numerator_exponent=",
        result.scale_trace.reciprocal_numerator_exponent,
        "\n",
    )
    text.write("checksum=", fixed_raw_checksum(Span(raw_values)), "\n")
    text.write("data=")
    var first = True
    for index in range(4):
        if not first:
            text.write(",")
        first = False
        text.write(
            "gram", index, ".re:", result.gram[index].re, ":",
            result.formats.gram.storage_bits, ":",
            result.formats.gram.fraction_bits, ":",
            result.scale_trace.gram_source_fraction_bits,
            ",gram", index, ".im:", result.gram[index].im, ":",
            result.formats.gram.storage_bits, ":",
            result.formats.gram.fraction_bits, ":",
            result.scale_trace.gram_source_fraction_bits,
        )
    for index in range(2):
        text.write(
            ",matched", index, ".re:", result.matched[index].re, ":",
            result.formats.matched.storage_bits, ":",
            result.formats.matched.fraction_bits, ":",
            result.scale_trace.matched_source_fraction_bits,
            ",matched", index, ".im:", result.matched[index].im, ":",
            result.formats.matched.storage_bits, ":",
            result.formats.matched.fraction_bits, ":",
            result.scale_trace.matched_source_fraction_bits,
        )
    text.write(
        ",determinant:", result.scale_trace.determinant_raw, ":",
        result.scale_trace.determinant_format.storage_bits, ":",
        result.scale_trace.determinant_format.fraction_bits, ":",
        result.scale_trace.determinant_format.fraction_bits,
        ",reciprocal:", result.scale_trace.reciprocal_raw, ":",
        result.formats.reciprocal.storage_bits, ":",
        result.formats.reciprocal.fraction_bits, ":",
        result.scale_trace.determinant_format.fraction_bits,
    )
    for index in range(2):
        text.write(
            ",numerator", index, ".re:", result.numerators[index].re, ":",
            result.formats.numerator.storage_bits, ":",
            result.formats.numerator.fraction_bits, ":",
            result.scale_trace.numerator_source_fraction_bits,
            ",numerator", index, ".im:", result.numerators[index].im, ":",
            result.formats.numerator.storage_bits, ":",
            result.formats.numerator.fraction_bits, ":",
            result.scale_trace.numerator_source_fraction_bits,
        )
    for index in range(2):
        text.write(
            ",estimate", index, ".re:", result.estimates[index].re, ":",
            result.formats.output.storage_bits, ":",
            result.formats.output.fraction_bits, ":",
            result.scale_trace.output_product_fraction_bits,
            ",estimate", index, ".im:", result.estimates[index].im, ":",
            result.formats.output.storage_bits, ":",
            result.formats.output.fraction_bits, ":",
            result.scale_trace.output_product_fraction_bits,
        )
    text.write("\n")
    return text^


def fixed_mimo_zf_canonical_rtl_vectors(
    result: FixedMIMOZF2x2Result,
) raises -> String:
    """Serialize inputs, all solver checkpoints, scale trace, and checksum."""
    _validate_zf_result(result)
    var determinant: List[Int64] = [result.scale_trace.determinant_raw]
    var threshold: List[Int64] = [
        result.scale_trace.singular_threshold_raw
    ]
    var reciprocal: List[Int64] = [result.scale_trace.reciprocal_raw]
    var text = String()
    text.write(serialize_complex_fixed_vector(
        "fixed-mimo-zf-2x2",
        "channel-row-major",
        Span(result.channel),
        result.formats.channel,
    ))
    text.write(serialize_complex_fixed_vector(
        "fixed-mimo-zf-2x2",
        "observation",
        Span(result.observation),
        result.formats.observation,
    ))
    text.write(serialize_complex_fixed_vector(
        "fixed-mimo-zf-2x2",
        "hermitian-gram",
        Span(result.gram),
        result.formats.gram,
    ))
    text.write(serialize_complex_fixed_vector(
        "fixed-mimo-zf-2x2",
        "matched-filter",
        Span(result.matched),
        result.formats.matched,
    ))
    text.write(serialize_fixed_vector(
        "fixed-mimo-zf-2x2",
        "determinant",
        Span(determinant),
        result.scale_trace.determinant_format,
    ))
    text.write(serialize_fixed_vector(
        "fixed-mimo-zf-2x2",
        "singular-threshold",
        Span(threshold),
        result.scale_trace.determinant_format,
    ))
    text.write(serialize_fixed_vector(
        "fixed-mimo-zf-2x2",
        "reciprocal",
        Span(reciprocal),
        result.formats.reciprocal,
    ))
    text.write(serialize_complex_fixed_vector(
        "fixed-mimo-zf-2x2",
        "adjugate-numerators",
        Span(result.numerators),
        result.formats.numerator,
    ))
    text.write(serialize_complex_fixed_vector(
        "fixed-mimo-zf-2x2",
        "zf-estimates",
        Span(result.estimates),
        result.formats.output,
    ))
    text.write(fixed_mimo_zf_scale_trace_text(result))
    text.write(
        "MWDSP-FIXED-MIMO-CHECKSUM-V1\nchecksum=",
        fixed_mimo_zf_result_checksum(result),
        "\n",
    )
    return text^
