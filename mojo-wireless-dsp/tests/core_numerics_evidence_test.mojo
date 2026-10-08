"""Strict independent evidence for the public core and numerics kernels."""

from std.collections import Span
from std.math import ceil, floor
from std.testing import assert_equal, assert_raises, assert_true, TestSuite
from wireless_dsp.core import Complex32, Complex64, complex_mac
from wireless_dsp.numerics import (
    Fixed,
    ROUND_NEAREST_AWAY,
    ROUND_TOWARD_ZERO,
    OVERFLOW_SATURATE,
    OVERFLOW_WRAP,
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


def _assert_close(
    actual: Float64, expected: Float64, tolerance: Float64
) raises:
    assert_true(abs(actual - expected) <= tolerance)


def _next_seed(state: UInt64) -> UInt64:
    return (
        state * UInt64(6364136223846793005)
        + UInt64(1442695040888963407)
    )


def _ref_min(bits: Int) -> Int64:
    return -(Int64(1) << Int64(bits - 1))


def _ref_max(bits: Int) -> Int64:
    return (Int64(1) << Int64(bits - 1)) - 1


def _ref_narrow(value: Int64, bits: Int, saturate: Bool) -> Int64:
    var minimum = _ref_min(bits)
    var maximum = _ref_max(bits)
    if saturate:
        return min(max(value, minimum), maximum)
    var modulus = Int64(1) << Int64(bits)
    var residue = value % modulus
    if residue < 0:
        residue += modulus
    if residue > maximum:
        residue -= modulus
    return residue


def _ref_round_right(value: Int64, shift: Int, nearest: Bool) -> Int64:
    if shift == 0:
        return value
    var divisor = Int64(1) << Int64(shift)
    var magnitude = value if value >= 0 else -value
    var quotient = magnitude // divisor
    var remainder = magnitude % divisor
    if nearest and remainder * 2 >= divisor:
        quotient += 1
    return quotient if value >= 0 else -quotient


def _ref_rescale(
    value: Int64,
    input_fraction: Int,
    output_fraction: Int,
    output_bits: Int,
    nearest: Bool,
    saturate: Bool,
) -> Int64:
    if output_fraction <= input_fraction:
        return _ref_narrow(
            _ref_round_right(
                value, input_fraction - output_fraction, nearest
            ),
            output_bits,
            saturate,
        )
    var result = _ref_narrow(value, output_bits, saturate)
    for _ in range(output_fraction - input_fraction):
        result = _ref_narrow(result * 2, output_bits, saturate)
    return result


def _ref_quantize(
    value: Float64,
    bits: Int,
    fraction: Int,
    nearest: Bool,
    saturate: Bool,
) -> Int64:
    var scaled = value * Float64(Int64(1) << Int64(fraction))
    var rounded: Int64
    if nearest:
        rounded = (
            Int64(ceil(scaled - 0.5))
            if scaled < 0.0
            else Int64(floor(scaled + 0.5))
        )
    else:
        rounded = (
            Int64(ceil(scaled)) if scaled < 0.0 else Int64(floor(scaled))
        )
    return _ref_narrow(rounded, bits, saturate)


def test_complex_mac_float64_oracle_seeded_and_edges() raises:
    # The oracle expands (ar+i ai)(br+i bi) directly in Float64.
    var exact = complex_mac(
        Complex64(2.0, -3.0), Complex64(4.0, 5.0), Complex64(-2.0, 7.0)
    )
    assert_equal(exact, Complex64(-41.0, 15.0))
    assert_equal(
        complex_mac(
            Complex64(0.0, 0.0),
            Complex64(0.0, 0.0),
            Complex64(-1.0e200, 1.0e200),
        ),
        Complex64(0.0, 0.0),
    )

    var seed = UInt64(0xC0DEC0DE)
    for _ in range(256):
        seed = _next_seed(seed)
        var ar = Float64(Int64((seed >> UInt64(8)) % UInt64(2001)) - 1000) / 64.0
        seed = _next_seed(seed)
        var ai = Float64(Int64((seed >> UInt64(8)) % UInt64(2001)) - 1000) / 64.0
        seed = _next_seed(seed)
        var br = Float64(Int64((seed >> UInt64(8)) % UInt64(2001)) - 1000) / 64.0
        seed = _next_seed(seed)
        var bi = Float64(Int64((seed >> UInt64(8)) % UInt64(2001)) - 1000) / 64.0
        seed = _next_seed(seed)
        var cr = Float64(Int64((seed >> UInt64(8)) % UInt64(2001)) - 1000) / 64.0
        seed = _next_seed(seed)
        var ci = Float64(Int64((seed >> UInt64(8)) % UInt64(2001)) - 1000) / 64.0
        var actual = complex_mac(
            Complex32(Float32(cr), Float32(ci)),
            Complex32(Float32(ar), Float32(ai)),
            Complex32(Float32(br), Float32(bi)),
        )
        var expected_re = cr + ar * br - ai * bi
        var expected_im = ci + ar * bi + ai * br
        _assert_close(Float64(actual.re), expected_re, 1.0e-4)
        _assert_close(Float64(actual.im), expected_im, 1.0e-4)


def test_runtime_quantization_exhaustive_seeded_and_edges() raises:
    var sat = QFormat(
        4, 1, ROUND_NEAREST_AWAY, OVERFLOW_SATURATE
    )
    var wrap = QFormat(4, 1, ROUND_TOWARD_ZERO, OVERFLOW_WRAP)

    # Exhaust every 4-bit word and a wide halo around both narrowing edges.
    for value in range(-40, 41):
        var word = Int64(value)
        assert_equal(raw_fits(word, sat), value >= -8 and value <= 7)
        assert_equal(narrow_raw(word, sat), _ref_narrow(word, 4, True))
        assert_equal(narrow_raw(word, wrap), _ref_narrow(word, 4, False))
    for value in range(-32, 33):
        for shift in range(5):
            assert_equal(
                rounded_shift_right(
                    Int64(value), shift, ROUND_NEAREST_AWAY
                ),
                _ref_round_right(Int64(value), shift, True),
            )
            assert_equal(
                rounded_shift_right(
                    Int64(value), shift, ROUND_TOWARD_ZERO
                ),
                _ref_round_right(Int64(value), shift, False),
            )

    var input_q = QFormat(4, 1)
    var output_q = QFormat(5, 2)
    for value in range(-8, 8):
        assert_equal(
            rescale_raw(Int64(value), 1, output_q),
            _ref_rescale(Int64(value), 1, 2, 5, True, True),
        )
        assert_equal(
            fixed_shift_raw(Int64(value), 1, input_q),
            _ref_rescale(Int64(value), 2, 1, 4, True, True),
        )
        assert_equal(
            fixed_shift_raw(Int64(value), -1, input_q),
            _ref_narrow(Int64(value) * 2, 4, True),
        )
        assert_equal(
            fixed_abs_raw(Int64(value), input_q),
            _ref_narrow(
                -Int64(value) if value < 0 else Int64(value), 4, True
            ),
        )
        assert_equal(
            dequantize_raw(Int64(value), input_q), Float64(value) / 2.0
        )
        for rhs in range(-8, 8):
            assert_equal(
                fixed_add_raw(
                    Int64(value), input_q, Int64(rhs), input_q, input_q
                ),
                _ref_narrow(Int64(value + rhs), 4, True),
            )
            assert_equal(
                fixed_sub_raw(
                    Int64(value), input_q, Int64(rhs), input_q, input_q
                ),
                _ref_narrow(Int64(value - rhs), 4, True),
            )
            assert_equal(
                fixed_mul_raw(
                    Int64(value), input_q, Int64(rhs), input_q, input_q
                ),
                _ref_narrow(
                    _ref_round_right(Int64(value * rhs), 1, True),
                    4,
                    True,
                ),
            )
            assert_equal(
                fixed_min_raw(Int64(value), Int64(rhs), input_q),
                Int64(min(value, rhs)),
            )
            assert_equal(
                fixed_max_raw(Int64(value), Int64(rhs), input_q),
                Int64(max(value, rhs)),
            )
            for accumulator in range(-8, 8):
                var product = _ref_narrow(
                    _ref_round_right(Int64(value * rhs), 1, True),
                    4,
                    True,
                )
                assert_equal(
                    fixed_mac_raw(
                        Int64(accumulator),
                        Int64(value),
                        input_q,
                        Int64(rhs),
                        input_q,
                        input_q,
                    ),
                    _ref_narrow(Int64(accumulator) + product, 4, True),
                )

    # Float64 is an independent numeric oracle; half ties are explicit.
    var seed = UInt64(0x51A1E123)
    for _ in range(256):
        seed = _next_seed(seed)
        var numerator = Int64((seed >> UInt64(11)) % UInt64(257)) - 128
        var value = Float64(numerator) / 16.0
        assert_equal(
            quantize_raw(value, sat),
            _ref_quantize(value, 4, 1, True, True),
        )
        assert_equal(
            quantize_raw(value, wrap),
            _ref_quantize(value, 4, 1, False, False),
        )
    assert_equal(quantize_raw(3.25, sat), Int64(7))
    assert_equal(quantize_raw(-4.25, sat), Int64(-8))
    assert_equal(quantize_raw(0.25, sat), Int64(1))
    assert_equal(quantize_raw(-0.25, sat), Int64(-1))

    with assert_raises():
        _ = rounded_shift_right(1, 62, ROUND_NEAREST_AWAY)
    with assert_raises():
        _ = dequantize_raw(8, input_q)
    with assert_raises():
        _ = fixed_add_raw(8, input_q, 0, input_q, input_q)
    with assert_raises():
        _ = fixed_sub_raw(0, input_q, -9, input_q, input_q)
    with assert_raises():
        _ = fixed_mul_raw(8, input_q, 0, input_q, input_q)
    with assert_raises():
        _ = fixed_mac_raw(8, 0, input_q, 0, input_q, input_q)
    with assert_raises():
        _ = fixed_shift_raw(0, -62, input_q)
    with assert_raises():
        _ = fixed_abs_raw(8, input_q)
    with assert_raises():
        _ = fixed_min_raw(-9, 0, input_q)
    with assert_raises():
        _ = fixed_max_raw(0, 8, input_q)


def _ref_complex_product(
    lhs: ComplexRaw, rhs: ComplexRaw, qformat: QFormat
) -> ComplexRaw:
    return ComplexRaw(
        _ref_narrow(
            _ref_round_right(
                lhs.re * rhs.re - lhs.im * rhs.im, 1, True
            ),
            qformat.storage_bits,
            True,
        ),
        _ref_narrow(
            _ref_round_right(
                lhs.re * rhs.im + lhs.im * rhs.re, 1, True
            ),
            qformat.storage_bits,
            True,
        ),
    )


def test_complex_fixed_exhaustive_integer_oracle_and_edges() raises:
    var qformat = QFormat(4, 1)
    for re in range(-8, 8):
        for im in range(-8, 8):
            var value = ComplexRaw(Int64(re), Int64(im))
            assert_equal(
                complex_conjugate_raw(value, qformat),
                ComplexRaw(Int64(re), _ref_narrow(-Int64(im), 4, True)),
            )

    # Exhaust all 65,536 pairs of complex Q2.1 input words.
    var seed = UInt64(0xF17EDC0D)
    for ar in range(-8, 8):
        for ai in range(-8, 8):
            for br in range(-8, 8):
                for bi in range(-8, 8):
                    var lhs = ComplexRaw(Int64(ar), Int64(ai))
                    var rhs = ComplexRaw(Int64(br), Int64(bi))
                    var expected = _ref_complex_product(
                        lhs, rhs, qformat
                    )
                    assert_equal(
                        complex_mul_raw(
                            lhs, qformat, rhs, qformat, qformat
                        ),
                        expected,
                    )
                    seed = _next_seed(seed)
                    var accumulator = ComplexRaw(
                        Int64(seed % UInt64(16)) - 8,
                        Int64((seed >> UInt64(9)) % UInt64(16)) - 8,
                    )
                    assert_equal(
                        complex_mac_raw(
                            accumulator,
                            lhs,
                            qformat,
                            rhs,
                            qformat,
                            qformat,
                        ),
                        ComplexRaw(
                            _ref_narrow(
                                accumulator.re + expected.re, 4, True
                            ),
                            _ref_narrow(
                                accumulator.im + expected.im, 4, True
                            ),
                        ),
                    )
                    var conjugated_product = _ref_complex_product(
                        ComplexRaw(lhs.re, -lhs.im), rhs, qformat
                    )
                    assert_equal(
                        complex_mac_conjugate_raw(
                            accumulator,
                            lhs,
                            qformat,
                            rhs,
                            qformat,
                            qformat,
                        ),
                        ComplexRaw(
                            _ref_narrow(
                                accumulator.re + conjugated_product.re,
                                4,
                                True,
                            ),
                            _ref_narrow(
                                accumulator.im + conjugated_product.im,
                                4,
                                True,
                            ),
                        ),
                    )

    with assert_raises():
        _ = complex_conjugate_raw(ComplexRaw(8, 0), qformat)
    with assert_raises():
        _ = complex_mul_raw(
            ComplexRaw(8, 0), qformat, ComplexRaw(), qformat, qformat
        )
    with assert_raises():
        _ = complex_mac_raw(
            ComplexRaw(8, 0),
            ComplexRaw(),
            qformat,
            ComplexRaw(),
            qformat,
            qformat,
        )
    with assert_raises():
        _ = complex_mac_conjugate_raw(
            ComplexRaw(),
            ComplexRaw(),
            qformat,
            ComplexRaw(0, -9),
            qformat,
            qformat,
        )


def test_scale_schedule_analytic_seeded_and_edges() raises:
    var input_q = QFormat(8, 3)
    var stages: List[ScaleStage] = [
        ScaleStage(QFormat(7, 2), 1),
        ScaleStage(QFormat(6, 3), 0),
        ScaleStage(QFormat(5, 1), 2),
    ]
    var seed = UInt64(0x5CA1E123)
    for _ in range(128):
        seed = _next_seed(seed)
        var input = Int64(seed % UInt64(256)) - 128
        var trace = apply_scale_schedule(input, input_q, Span(stages))
        var expected0 = _ref_rescale(input, 4, 2, 7, True, True)
        var expected1 = _ref_rescale(expected0, 2, 3, 6, True, True)
        var expected2 = _ref_rescale(expected1, 5, 1, 5, True, True)
        assert_equal(trace.values, [expected0, expected1, expected2])
        assert_equal(trace.fraction_bits, [2, 3, 1])
        assert_equal(trace.storage_bits, [7, 6, 5])
        assert_equal(trace.right_shifts, [1, 0, 2])

    var empty = List[ScaleStage]()
    var empty_trace = apply_scale_schedule(7, input_q, Span(empty))
    assert_equal(len(empty_trace.values), 0)
    with assert_raises():
        _ = apply_scale_schedule(128, input_q, Span(empty))


def test_radix2_fft_scale_schedule_deterministic_and_edges() raises:
    var size = 2
    var expected_stages = 1
    while size <= 65_536:
        for storage_bits in [2, 8, 31, 62]:
            for fraction_bits in [0, storage_bits - 1]:
                for shifted in [False, True]:
                    var first = radix2_fft_scale_schedule(
                        size,
                        storage_bits,
                        fraction_bits,
                        right_shift_each_stage=shifted,
                    )
                    var second = radix2_fft_scale_schedule(
                        size,
                        storage_bits,
                        fraction_bits,
                        right_shift_each_stage=shifted,
                    )
                    assert_equal(len(first), expected_stages)
                    assert_equal(len(second), expected_stages)
                    for stage_index in range(expected_stages):
                        var stage = first[stage_index]
                        var repeated = second[stage_index]
                        assert_true(stage.output_format == repeated.output_format)
                        assert_equal(stage.right_shift, repeated.right_shift)
                        assert_equal(stage.output_format.storage_bits, storage_bits)
                        assert_equal(stage.output_format.fraction_bits, fraction_bits)
                        assert_equal(stage.output_format.rounding_mode, ROUND_NEAREST_AWAY)
                        assert_equal(stage.output_format.overflow_mode, OVERFLOW_SATURATE)
                        assert_equal(stage.right_shift, 1 if shifted else 0)
        size <<= 1
        expected_stages += 1
    var widest = radix2_fft_scale_schedule(2, 62, 61)
    var widest_trace = apply_scale_schedule(
        Int64(2), QFormat(62, 61), Span(widest)
    )
    assert_equal(widest_trace.values, [Int64(1)])
    assert_equal(widest_trace.fraction_bits, [61])
    with assert_raises():
        _ = radix2_fft_scale_schedule(1, 8, 3)
    with assert_raises():
        _ = radix2_fft_scale_schedule(12, 8, 3)
    with assert_raises():
        _ = radix2_fft_scale_schedule(8, 1, 0)
    with assert_raises():
        _ = radix2_fft_scale_schedule(Int.MIN, 8, 3)
    with assert_raises():
        _ = radix2_fft_scale_schedule(Int.MAX, 8, 3)
    with assert_raises():
        _ = radix2_fft_scale_schedule(8, Int.MIN, 3)
    with assert_raises():
        _ = radix2_fft_scale_schedule(8, Int.MAX, 3)
    with assert_raises():
        _ = radix2_fft_scale_schedule(8, 8, Int.MIN)
    with assert_raises():
        _ = radix2_fft_scale_schedule(8, 8, Int.MAX)


def test_validate_qformat_exhaustive_descriptor_domain_and_mutation_edges() raises:
    for storage_bits in range(2, 63):
        for fraction_bits in range(storage_bits):
            for rounding_mode in [ROUND_NEAREST_AWAY, ROUND_TOWARD_ZERO]:
                for overflow_mode in [OVERFLOW_SATURATE, OVERFLOW_WRAP]:
                    var descriptor = QFormat(
                        storage_bits,
                        fraction_bits,
                        rounding_mode,
                        overflow_mode,
                    )
                    var validated = validate_qformat(descriptor)
                    assert_true(validated == descriptor)

    var valid = QFormat(16, 8, ROUND_NEAREST_AWAY, OVERFLOW_SATURATE)
    for invalid_storage in [Int.MIN, 1, 63, Int.MAX]:
        var mutated = valid
        mutated.storage_bits = invalid_storage
        with assert_raises():
            _ = validate_qformat(mutated)
    for invalid_fraction in [Int.MIN, -1, 16, Int.MAX]:
        var mutated = valid
        mutated.fraction_bits = invalid_fraction
        with assert_raises():
            _ = validate_qformat(mutated)
    for invalid_rounding in [Int.MIN, -1, 2, Int.MAX]:
        var mutated = valid
        mutated.rounding_mode = invalid_rounding
        with assert_raises():
            _ = validate_qformat(mutated)
    for invalid_overflow in [Int.MIN, -1, 2, Int.MAX]:
        var mutated = valid
        mutated.overflow_mode = invalid_overflow
        with assert_raises():
            _ = validate_qformat(mutated)


def test_fixed_struct_contract_extremes_arithmetic_and_rescale() raises:
    comptime SatQ4 = Fixed[4, 8, ROUND_NEAREST_AWAY, OVERFLOW_SATURATE]
    comptime WrapQ4 = Fixed[4, 8, ROUND_TOWARD_ZERO, OVERFLOW_WRAP]
    assert_equal(SatQ4.from_int(Int64.MAX_FINITE).raw, Int64(127))
    assert_equal(SatQ4.from_int(Int64.MIN_FINITE).raw, Int64(-128))
    assert_equal(WrapQ4.from_int(Int64.MAX_FINITE).raw, Int64(-16))
    assert_equal(WrapQ4.from_int(Int64.MIN_FINITE).raw, Int64(0))

    for lhs in range(-8, 8):
        for rhs in range(-8, 8):
            var a = SatQ4(raw=Int64(lhs * 8))
            var b = SatQ4(raw=Int64(rhs * 8))
            assert_equal(
                (a + b).raw,
                _ref_narrow(Int64((lhs + rhs) * 8), 8, True),
            )
            assert_equal(
                (a - b).raw,
                _ref_narrow(Int64((lhs - rhs) * 8), 8, True),
            )
            assert_equal(
                (a * b).raw,
                _ref_narrow(Int64(lhs * rhs * 4), 8, True),
            )
            assert_equal(
                a.rescale[2]().raw,
                _ref_round_right(a.raw, 2, True),
            )
            assert_equal(a.to_float64(), Float64(lhs) / 2.0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
