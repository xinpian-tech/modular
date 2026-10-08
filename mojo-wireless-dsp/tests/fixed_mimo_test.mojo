"""Bit-exact and seeded differential tests for the fixed 2x2 MIMO model."""

from std.collections import Span
from std.testing import assert_equal, assert_raises, assert_true, TestSuite
from wireless_dsp.numerics.fixed import (
    ROUND_NEAREST_AWAY,
    ROUND_TOWARD_ZERO,
    OVERFLOW_SATURATE,
    OVERFLOW_WRAP,
)
from wireless_dsp.numerics.quantization import QFormat
from wireless_dsp.numerics.complex_fixed import ComplexRaw
from wireless_dsp.core import Complex64
from wireless_dsp.backend.fixed_mimo_reference import (
    FixedMIMOFormats,
    fixed_complex_matvec_2x2_raw,
    fixed_hermitian_gram_2x2_raw,
    fixed_hermitian_matched_filter_2x2_raw,
    fixed_mimo_default_formats,
    fixed_mimo_determinant_format,
    fixed_mimo_reciprocal_positive_raw,
    fixed_mimo_zf_canonical_rtl_vectors,
    fixed_mimo_zf_result_checksum,
    fixed_mimo_zf_scale_trace_text,
    fixed_zf_equalize_2x2_raw,
)


def _oracle_fnv1a_text(text: StringSlice) -> UInt64:
    var state = UInt64(14695981039346656037)
    var bytes = text.as_bytes()
    for index in range(len(bytes)):
        state ^= UInt64(UInt8(bytes[index]))
        state *= UInt64(1099511628211)
    return state


def _static_formats() raises -> FixedMIMOFormats:
    var q4 = QFormat(16, 4, ROUND_NEAREST_AWAY, OVERFLOW_SATURATE)
    return FixedMIMOFormats(
        q4,
        q4,
        q4,
        QFormat(32, 8, ROUND_NEAREST_AWAY, OVERFLOW_SATURATE),
        QFormat(24, 8, ROUND_NEAREST_AWAY, OVERFLOW_SATURATE),
        QFormat(24, 8, ROUND_NEAREST_AWAY, OVERFLOW_SATURATE),
        QFormat(24, 16, ROUND_NEAREST_AWAY, OVERFLOW_SATURATE),
        QFormat(24, 20, ROUND_NEAREST_AWAY, OVERFLOW_SATURATE),
        QFormat(16, 12, ROUND_NEAREST_AWAY, OVERFLOW_SATURATE),
    )


def _static_channel() -> List[ComplexRaw]:
    return [
        ComplexRaw(16, 8),
        ComplexRaw(8, -4),
        ComplexRaw(-4, 12),
        ComplexRaw(20, 8),
    ]


def _static_symbols() -> List[ComplexRaw]:
    return [ComplexRaw(12, -8), ComplexRaw(-4, 16)]


def test_hand_checked_matvec_gram_matched_and_zf_vector() raises:
    """Static values were cross-checked with Python Fraction integer math."""
    var formats = _static_formats()
    var channel = _static_channel()
    var symbols = _static_symbols()
    var observation = fixed_complex_matvec_2x2_raw(
        Span(channel),
        Span(symbols),
        formats.channel,
        formats.symbol,
        formats.accumulator,
        formats.observation,
    )
    assert_equal(observation, [ComplexRaw(18, 7), ComplexRaw(-10, 29)])
    var gram = fixed_hermitian_gram_2x2_raw(
        Span(channel),
        formats.channel,
        formats.accumulator,
        formats.gram,
    )
    assert_equal(gram, [
        ComplexRaw(480, 0),
        ComplexRaw(112, -400),
        ComplexRaw(112, 400),
        ComplexRaw(544, 0),
    ])
    var matched = fixed_hermitian_matched_filter_2x2_raw(
        Span(channel),
        Span(observation),
        formats.channel,
        formats.observation,
        formats.accumulator,
        formats.matched,
    )
    assert_equal(matched, [ComplexRaw(732, -28), ComplexRaw(148, 788)])

    var result = fixed_zf_equalize_2x2_raw(
        Span(channel), Span(observation), formats, Int64(64)
    )
    assert_equal(result.gram, gram)
    assert_equal(result.matched, matched)
    assert_equal(result.scale_trace.determinant_raw, Int64(88576))
    assert_equal(result.scale_trace.determinant_format.storage_bits, 62)
    assert_equal(result.scale_trace.determinant_format.fraction_bits, 16)
    var determinant_format = fixed_mimo_determinant_format(formats)
    assert_equal(
        determinant_format.storage_bits,
        result.scale_trace.determinant_format.storage_bits,
    )
    assert_equal(
        determinant_format.fraction_bits,
        result.scale_trace.determinant_format.fraction_bits,
    )
    assert_equal(result.scale_trace.singular_threshold_raw, Int64(64))
    assert_equal(result.scale_trace.reciprocal_raw, Int64(775825))
    assert_equal(result.scale_trace.reciprocal_numerator_exponent, 36)
    assert_equal(result.scale_trace.numerator_source_fraction_bits, 16)
    assert_equal(result.scale_trace.output_product_fraction_bits, 36)
    assert_equal(result.numerators, [
        ComplexRaw(66432, -44288), ComplexRaw(-22144, 88576)
    ])
    assert_equal(result.estimates, [
        ComplexRaw(3072, -2048), ComplexRaw(-1024, 4096)
    ])
    # The q12 output is the exact representation of the original q4 symbols.
    for index in range(2):
        assert_equal(result.estimates[index].re, symbols[index].re * 256)
        assert_equal(result.estimates[index].im, symbols[index].im * 256)


def _next_seeded_signed(mut state: UInt64, magnitude: Int64) -> Int64:
    state = state * UInt64(6364136223846793005) + UInt64(1442695040888963407)
    return Int64(state >> 32) % (2 * magnitude + 1) - magnitude


def _independent_float64_zf_2x2(
    channel: Span[ComplexRaw, ...],
    observation: Span[ComplexRaw, ...],
    formats: FixedMIMOFormats,
) raises -> List[Complex64]:
    var h = List[Complex64](capacity=4)
    for index in range(4):
        h.append(Complex64(
            Float64(channel[index].re) / Float64(formats.channel.scale()),
            Float64(channel[index].im) / Float64(formats.channel.scale()),
        ))
    var y = List[Complex64](capacity=2)
    for index in range(2):
        y.append(Complex64(
            Float64(observation[index].re)
            / Float64(formats.observation.scale()),
            Float64(observation[index].im)
            / Float64(formats.observation.scale()),
        ))
    var determinant = h[0] * h[3] - h[1] * h[2]
    var determinant_power = determinant.magnitude_squared()
    if determinant_power <= 0.0:
        raise Error("independent Float64 2x2 oracle is singular")
    var inverse_determinant = determinant.conjugate() * Complex64(
        1.0 / determinant_power, 0.0
    )
    return [
        (h[3] * y[0] - h[1] * y[1]) * inverse_determinant,
        (h[0] * y[1] - h[2] * y[0]) * inverse_determinant,
    ]


def test_seeded_diagonally_dominant_zf_roundtrip_property() raises:
    var formats = fixed_mimo_default_formats()
    var state = UInt64(0xF17ED2A2)
    for _ in range(64):
        var channel: List[ComplexRaw] = [
            ComplexRaw(
                4096 + _next_seeded_signed(state, 256),
                _next_seeded_signed(state, 192),
            ),
            ComplexRaw(
                _next_seeded_signed(state, 384),
                _next_seeded_signed(state, 384),
            ),
            ComplexRaw(
                _next_seeded_signed(state, 384),
                _next_seeded_signed(state, 384),
            ),
            ComplexRaw(
                4096 + _next_seeded_signed(state, 256),
                _next_seeded_signed(state, 192),
            ),
        ]
        var symbols: List[ComplexRaw] = [
            ComplexRaw(
                _next_seeded_signed(state, 2048),
                _next_seeded_signed(state, 2048),
            ),
            ComplexRaw(
                _next_seeded_signed(state, 2048),
                _next_seeded_signed(state, 2048),
            ),
        ]
        var observation = fixed_complex_matvec_2x2_raw(
            Span(channel),
            Span(symbols),
            formats.channel,
            formats.symbol,
            formats.accumulator,
            formats.observation,
        )
        var result = fixed_zf_equalize_2x2_raw(
            Span(channel), Span(observation), formats, Int64(1 << 16)
        )
        var expected = _independent_float64_zf_2x2(
            Span(channel), Span(observation), formats
        )
        for index in range(2):
            assert_true(abs(result.estimates[index].re - symbols[index].re) <= 4)
            assert_true(abs(result.estimates[index].im - symbols[index].im) <= 4)
            var actual_re = (
                Float64(result.estimates[index].re)
                / Float64(formats.output.scale())
            )
            var actual_im = (
                Float64(result.estimates[index].im)
                / Float64(formats.output.scale())
            )
            assert_true(abs(actual_re - expected[index].re) <= 0.002)
            assert_true(abs(actual_im - expected[index].im) <= 0.002)


def test_registered_overflow_input_and_singular_edges() raises:
    var saturate = QFormat(
        4, 2, ROUND_NEAREST_AWAY, OVERFLOW_SATURATE
    )
    var wrap = QFormat(4, 2, ROUND_NEAREST_AWAY, OVERFLOW_WRAP)
    var matrix = List[ComplexRaw](length=4, fill=ComplexRaw(7, 7))
    var vector = List[ComplexRaw](length=2, fill=ComplexRaw(7, 7))
    assert_equal(
        fixed_complex_matvec_2x2_raw(
            Span(matrix), Span(vector), saturate, saturate, saturate, saturate
        ),
        [ComplexRaw(0, 7), ComplexRaw(0, 7)],
    )
    assert_equal(
        fixed_complex_matvec_2x2_raw(
            Span(matrix), Span(vector), wrap, wrap, wrap, wrap
        ),
        [ComplexRaw(0, 2), ComplexRaw(0, 2)],
    )
    var invalid = matrix.copy()
    invalid[0] = ComplexRaw(8, 0)
    with assert_raises():
        _ = fixed_complex_matvec_2x2_raw(
            Span(invalid),
            Span(vector),
            saturate,
            saturate,
            saturate,
            saturate,
        )

    var formats = _static_formats()
    var singular: List[ComplexRaw] = [
        ComplexRaw(16, 0),
        ComplexRaw(32, 0),
        ComplexRaw(8, 0),
        ComplexRaw(16, 0),
    ]
    var observation: List[ComplexRaw] = [ComplexRaw(4, 0), ComplexRaw(2, 0)]
    with assert_raises():
        _ = fixed_zf_equalize_2x2_raw(
            Span(singular), Span(observation), formats, Int64(0)
        )
    var near_singular: List[ComplexRaw] = [
        ComplexRaw(16, 0),
        ComplexRaw(0, 0),
        ComplexRaw(0, 0),
        ComplexRaw(1, 0),
    ]
    with assert_raises():
        _ = fixed_zf_equalize_2x2_raw(
            Span(near_singular), Span(observation), formats, Int64(256)
        )
    with assert_raises():
        _ = fixed_zf_equalize_2x2_raw(
            Span(near_singular), Span(observation), formats, Int64(-1)
        )
    var short_matrix: List[ComplexRaw] = [ComplexRaw()]
    with assert_raises():
        _ = fixed_hermitian_gram_2x2_raw(
            Span(short_matrix), formats.channel, formats.accumulator, formats.gram
        )


def test_reciprocal_scale_trace_and_canonical_rtl_checksum() raises:
    var formats = _static_formats()
    var channel = _static_channel()
    var symbols = _static_symbols()
    var observation = fixed_complex_matvec_2x2_raw(
        Span(channel),
        Span(symbols),
        formats.channel,
        formats.symbol,
        formats.accumulator,
        formats.observation,
    )
    var result = fixed_zf_equalize_2x2_raw(
        Span(channel), Span(observation), formats, Int64(64)
    )
    assert_equal(
        fixed_mimo_reciprocal_positive_raw(
            Int64(88576),
            result.scale_trace.determinant_format,
            formats.reciprocal,
        ),
        Int64(775825),
    )
    with assert_raises():
        _ = fixed_mimo_reciprocal_positive_raw(
            Int64(0),
            result.scale_trace.determinant_format,
            formats.reciprocal,
        )
    var q4_nearest = QFormat(
        8, 4, ROUND_NEAREST_AWAY, OVERFLOW_SATURATE
    )
    var q4_truncate = QFormat(
        8, 4, ROUND_TOWARD_ZERO, OVERFLOW_SATURATE
    )
    var q4_wrap = QFormat(8, 4, ROUND_NEAREST_AWAY, OVERFLOW_WRAP)
    assert_equal(
        fixed_mimo_reciprocal_positive_raw(
            Int64(24), q4_nearest, q4_nearest
        ),
        Int64(11),
    )
    assert_equal(
        fixed_mimo_reciprocal_positive_raw(
            Int64(24), q4_nearest, q4_truncate
        ),
        Int64(10),
    )
    assert_equal(
        fixed_mimo_reciprocal_positive_raw(
            Int64(1), q4_nearest, q4_wrap
        ),
        Int64(0),
    )
    var trace = fixed_mimo_zf_scale_trace_text(result)
    # Independently computed FNV-1a pins every UTF-8 artifact byte.
    assert_equal(
        _oracle_fnv1a_text(StringSlice(trace)),
        UInt64(14381424636616730075),
    )
    assert_true(trace.startswith("MWDSP-FIXED-MIMO-SCALE-TRACE-V1\n"))
    assert_true("shape=22x5\n" in trace)
    assert_true("accumulator=sint32:8:rounding=" in trace)
    assert_true("reciprocal=sint24:20:rounding=" in trace)
    assert_true("determinant_threshold_raw=64\n" in trace)
    assert_true("reciprocal_numerator_exponent=36\n" in trace)
    assert_true("checksum=13414757721653704169\n" in trace)
    assert_true("determinant:88576:62:16:16" in trace)
    assert_true("estimate1.im:4096:16:12:36" in trace)

    var vectors = fixed_mimo_zf_canonical_rtl_vectors(result)
    assert_equal(
        _oracle_fnv1a_text(StringSlice(vectors)),
        UInt64(11855920542874926252),
    )
    assert_true(vectors.startswith("MWDSP-COMPLEX-FIXED-V2\n"))
    assert_true("stage=channel-row-major\n" in vectors)
    assert_true("stage=hermitian-gram\n" in vectors)
    assert_true("stage=singular-threshold\n" in vectors)
    assert_true("stage=adjugate-numerators\n" in vectors)
    assert_true("stage=zf-estimates\n" in vectors)
    assert_true("MWDSP-FIXED-MIMO-SCALE-TRACE-V1\n" in vectors)
    assert_equal(
        fixed_mimo_zf_result_checksum(result),
        UInt64(2961700366866594992),
    )
    assert_true(vectors.endswith(
        "MWDSP-FIXED-MIMO-CHECKSUM-V1\n"
        "checksum=2961700366866594992\n"
    ))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
