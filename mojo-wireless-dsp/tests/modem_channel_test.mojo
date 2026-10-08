from std.testing import assert_equal, assert_true, assert_raises, TestSuite
from std.math import isfinite, sqrt
from std.utils.numerics import inf, nan
from wireless_dsp.core import Complex64, Span
from wireless_dsp.modem import (
    qam_map,
    qam_demap_hard,
    qam_demapper_llr_maxlog,
    qam_demapper_llr_exact,
    qam_demapper_llr_piecewise,
    quantize_llr,
    hard_bits_from_llr,
    crc_append,
    crc_check,
)
from wireless_dsp.channel import add_awgn, apply_cfo, awgn_and_cfo


def test_qam_roundtrip_all_phase2_orders() raises:
    for bits_per_symbol in [1, 2, 4, 6, 8, 10, 12]:
        var bits = List[UInt8](capacity=bits_per_symbol * 4)
        for i in range(bits_per_symbol * 4):
            bits.append(UInt8((i * 5 + i // 3) & 1))
        var symbols = qam_map(Span(bits), bits_per_symbol)
        var recovered = qam_demap_hard(Span(symbols), bits_per_symbol)
        assert_equal(recovered, bits)


def test_standard_qpsk_and_16qam_constellation_points() raises:
    var qpsk_bits: List[UInt8] = [0, 0, 0, 1, 1, 1, 1, 0]
    var qpsk = qam_map(Span(qpsk_bits), 2)
    var qpsk_scale = 0.7071067811865475244
    assert_true(abs(qpsk[0].re - qpsk_scale) < 1.0e-12)
    assert_true(abs(qpsk[0].im - qpsk_scale) < 1.0e-12)
    assert_true(abs(qpsk[1].re - qpsk_scale) < 1.0e-12)
    assert_true(abs(qpsk[1].im + qpsk_scale) < 1.0e-12)
    assert_true(abs(qpsk[2].re + qpsk_scale) < 1.0e-12)
    assert_true(abs(qpsk[2].im + qpsk_scale) < 1.0e-12)
    assert_true(abs(qpsk[3].re + qpsk_scale) < 1.0e-12)
    assert_true(abs(qpsk[3].im - qpsk_scale) < 1.0e-12)

    var qam16_bits: List[UInt8] = [
        0, 0, 0, 0,  0, 1, 1, 1,  1, 1, 1, 0,  1, 0, 0, 1,
    ]
    var qam16 = qam_map(Span(qam16_bits), 4)
    var scale = 3.162277660168379332
    assert_true(abs(qam16[0].re - 3.0 / scale) < 1.0e-12)
    assert_true(abs(qam16[0].im - 3.0 / scale) < 1.0e-12)
    assert_true(abs(qam16[1].re - 1.0 / scale) < 1.0e-12)
    assert_true(abs(qam16[1].im + 1.0 / scale) < 1.0e-12)
    assert_true(abs(qam16[2].re + 1.0 / scale) < 1.0e-12)
    assert_true(abs(qam16[2].im + 3.0 / scale) < 1.0e-12)
    assert_true(abs(qam16[3].re + 3.0 / scale) < 1.0e-12)
    assert_true(abs(qam16[3].im - 1.0 / scale) < 1.0e-12)


def test_llr_sign_recovers_bits() raises:
    var bits: List[UInt8] = [0, 0, 0, 1, 1, 0, 1, 1]
    var symbols = qam_map(Span(bits), 2)
    var llrs = qam_demapper_llr_maxlog(Span(symbols), 2, 0.25)
    var recovered = hard_bits_from_llr(Span(llrs))
    assert_equal(recovered, bits)
    for i in range(len(llrs)):
        assert_true(llrs[i] > 0.0 if bits[i] == 0 else llrs[i] < 0.0)
    var exact = qam_demapper_llr_exact(Span(symbols), 2, 0.25)
    assert_equal(hard_bits_from_llr(Span(exact)), bits)
    var quantized = quantize_llr(Span(exact), scale=2.0, clip=7)
    for i in range(len(quantized)):
        assert_true(quantized[i] >= -7 and quantized[i] <= 7)
        assert_true(quantized[i] > 0 if bits[i] == 0 else quantized[i] < 0)


def test_piecewise_llr_matches_full_maxlog_through_4096qam() raises:
    var samples: List[Complex64] = [
        Complex64(-0.73, 0.21),
        Complex64(0.04, -1.17),
        Complex64(1.31, 0.88),
    ]
    for bits_per_symbol in [1, 2, 4, 6, 8, 10, 12]:
        var oracle = qam_demapper_llr_maxlog(Span(samples), bits_per_symbol, 0.37)
        var piecewise = qam_demapper_llr_piecewise(Span(samples), bits_per_symbol, 0.37)
        assert_equal(len(piecewise), len(oracle))
        for i in range(len(oracle)):
            assert_true(abs(piecewise[i] - oracle[i]) < 1.0e-11)


def test_llr_monotonicity_and_unclipped_quantization_error() raises:
    var samples: List[Complex64] = [
        Complex64(0.25), Complex64(0.5), Complex64(1.0)
    ]
    var llrs = qam_demapper_llr_piecewise(Span(samples), 1, 0.5)
    assert_true(0.0 < llrs[0] and llrs[0] < llrs[1] and llrs[1] < llrs[2])
    var quantized = quantize_llr(Span(llrs), scale=4.0, clip=127)
    for i in range(len(llrs)):
        assert_true(abs(Float64(quantized[i]) / 4.0 - llrs[i]) <= 0.125)


def test_extreme_finite_bpsk_llrs_are_scale_safe_and_monotonic() raises:
    var samples: List[Complex64] = [
        Complex64(-1.0e200, 1.0e308),
        Complex64(-1.0e-200, -1.0e308),
        Complex64(0.0, 0.0),
        Complex64(1.0e-200, 1.0e308),
        Complex64(1.0e200, -1.0e308),
    ]
    var expected: List[Float64] = [
        -4.0e200, -4.0e-200, 0.0, 4.0e-200, 4.0e200,
    ]
    var maxlog = qam_demapper_llr_maxlog(Span(samples), 1, 1.0)
    var exact = qam_demapper_llr_exact(Span(samples), 1, 1.0)
    var piecewise = qam_demapper_llr_piecewise(Span(samples), 1, 1.0)
    for i in range(len(expected)):
        assert_true(isfinite(maxlog[i]))
        assert_true(isfinite(exact[i]))
        assert_true(isfinite(piecewise[i]))
        assert_true(
            abs(maxlog[i] - expected[i])
            <= max(1.0e-300, abs(expected[i]) * 1.0e-15)
        )
        assert_equal(exact[i], maxlog[i])
        assert_equal(piecewise[i], maxlog[i])
    for i in range(len(maxlog) - 1):
        assert_true(maxlog[i] < maxlog[i + 1])

    # Both tiny operands and a tiny positive N0 remain representable when the
    # ratios cancel.  Multiplying or dividing in only one fixed order is not a
    # sufficient implementation for these cases.
    var tiny: List[Complex64] = [
        Complex64(-1.0e-300), Complex64(1.0e-300),
    ]
    var tiny_llrs = qam_demapper_llr_exact(Span(tiny), 1, 1.0e-300)
    assert_true(abs(tiny_llrs[0] + 4.0) < 1.0e-15)
    assert_true(abs(tiny_llrs[1] - 4.0) < 1.0e-15)


def test_extreme_finite_4096qam_soft_and_hard_decisions_agree() raises:
    var samples: List[Complex64] = [
        Complex64(1.0e308, -1.0e308),
        Complex64(-1.0e308, 1.0e308),
    ]
    var hard = qam_demap_hard(Span(samples), 12)
    var maxlog = qam_demapper_llr_maxlog(Span(samples), 12, 1.0e308)
    var piecewise = qam_demapper_llr_piecewise(
        Span(samples), 12, 1.0e308
    )
    var exact = qam_demapper_llr_exact(Span(samples), 12, 1.0e308)
    assert_equal(len(maxlog), 24)
    var expected_magnitudes: List[Float64] = [
        128.0 / sqrt(2730.0),
        64.0 / sqrt(2730.0),
        32.0 / sqrt(2730.0),
        16.0 / sqrt(2730.0),
        8.0 / sqrt(2730.0),
        4.0 / sqrt(2730.0),
    ]
    for i in range(len(maxlog)):
        assert_true(isfinite(maxlog[i]))
        assert_true(isfinite(piecewise[i]))
        assert_true(isfinite(exact[i]))
        assert_equal(piecewise[i], maxlog[i])
        var sample_index = i // 12
        var symbol_bit = i % 12
        var axis_bit = symbol_bit % 6
        # At |x|=N0=1e308, the bounded squared-level correction is negligible
        # and the nearest Gray partitions give 2*[64,32,...,2]/sqrt(2730).
        # Negative saturation maps to Gray 100000, so only the axis MSB flips.
        var negative = (
            (sample_index == 0 and symbol_bit == 6)
            or (sample_index == 1 and symbol_bit == 0)
        )
        var expected = expected_magnitudes[axis_bit]
        if negative:
            expected = -expected
        assert_true(abs(maxlog[i] - expected) < 2.0e-15)
    assert_equal(hard_bits_from_llr(Span(maxlog)), hard)
    assert_equal(hard_bits_from_llr(Span(exact)), hard)


def test_finite_inputs_with_unrepresentable_llrs_raise() raises:
    var huge: List[Complex64] = [Complex64(1.0e308, -1.0e308)]
    with assert_raises():
        _ = qam_demapper_llr_maxlog(Span(huge), 1, 1.0)
    with assert_raises():
        _ = qam_demapper_llr_exact(Span(huge), 1, 1.0)
    with assert_raises():
        _ = qam_demapper_llr_piecewise(Span(huge), 1, 1.0)

    # A finite subnormal-scale N0 can also make an otherwise ordinary high-QAM
    # distance difference unrepresentable; no API may silently emit infinity.
    var ordinary: List[Complex64] = [Complex64(0.75, -0.5)]
    with assert_raises():
        _ = qam_demapper_llr_maxlog(Span(ordinary), 12, 1.0e-320)
    with assert_raises():
        _ = qam_demapper_llr_exact(Span(ordinary), 12, 1.0e-320)
    with assert_raises():
        _ = qam_demapper_llr_piecewise(Span(ordinary), 12, 1.0e-320)


def test_quantize_extreme_finite_values_saturates_before_int_conversion() raises:
    var llrs: List[Float64] = [
        1.0e308, -1.0e308, 1.0e-308, -1.0e-308, 0.0,
    ]
    var quantized = quantize_llr(Span(llrs), scale=1.0e308, clip=127)
    var expected: List[Int] = [127, -127, 1, -1, 0]
    assert_equal(quantized, expected)

    var reverse_order: List[Float64] = [1.0e308, -1.0e308]
    var reverse_quantized = quantize_llr(
        Span(reverse_order), scale=1.0e-308, clip=127
    )
    var reverse_expected: List[Int] = [1, -1]
    assert_equal(reverse_quantized, reverse_expected)

    var positive: List[Float64] = [1.0e-308, 1.0, 1.0e308]
    var monotonic = quantize_llr(Span(positive), scale=1.0e308, clip=127)
    assert_true(0 < monotonic[0] and monotonic[0] <= monotonic[1])
    assert_true(monotonic[1] <= monotonic[2])

    # A wide clip must not be rounded through Float64 and applied too early.
    var largest_float_below_int_max = Int.MAX - 1023
    var wide: List[Float64] = [Float64(largest_float_below_int_max)]
    var wide_quantized = quantize_llr(Span(wide), scale=1.0, clip=Int.MAX)
    assert_equal(wide_quantized[0], largest_float_below_int_max)


def test_qam_validation() raises:
    var short: List[UInt8] = [0, 1, 0]
    with assert_raises():
        _ = qam_map(Span(short), 2)
    var invalid: List[UInt8] = [2, 0]
    with assert_raises():
        _ = qam_map(Span(invalid), 2)
    var invalid_sample: List[Complex64] = [
        Complex64(nan[DType.float64](), 0.0)
    ]
    with assert_raises():
        _ = qam_demap_hard(Span(invalid_sample), 2)
    with assert_raises():
        _ = qam_demapper_llr_maxlog(Span(invalid_sample), 2, 0.1)
    with assert_raises():
        _ = qam_demapper_llr_exact(Span(invalid_sample), 2, 0.1)
    with assert_raises():
        _ = qam_demapper_llr_piecewise(Span(invalid_sample), 2, 0.1)
    for nonfinite_sample in [
        Complex64(inf[DType.float64](), 0.0),
        Complex64(0.0, -inf[DType.float64]()),
    ]:
        var one_nonfinite: List[Complex64] = [nonfinite_sample]
        with assert_raises():
            _ = qam_demap_hard(Span(one_nonfinite), 12)
        with assert_raises():
            _ = qam_demapper_llr_maxlog(Span(one_nonfinite), 12, 0.1)
        with assert_raises():
            _ = qam_demapper_llr_exact(Span(one_nonfinite), 12, 0.1)
        with assert_raises():
            _ = qam_demapper_llr_piecewise(Span(one_nonfinite), 12, 0.1)
    for invalid_noise in [
        nan[DType.float64](), inf[DType.float64](), 0.0, -1.0,
    ]:
        with assert_raises():
            _ = qam_demapper_llr_maxlog(
                Span(invalid_sample), 2, invalid_noise
            )
        with assert_raises():
            _ = qam_demapper_llr_exact(
                Span(invalid_sample), 2, invalid_noise
            )
        with assert_raises():
            _ = qam_demapper_llr_piecewise(
                Span(invalid_sample), 2, invalid_noise
            )
    var invalid_llr: List[Float64] = [nan[DType.float64]()]
    with assert_raises():
        _ = quantize_llr(Span(invalid_llr), scale=1.0, clip=127)
    for nonfinite_llr in [
        inf[DType.float64](), -inf[DType.float64](),
    ]:
        var one_nonfinite_llr: List[Float64] = [nonfinite_llr]
        with assert_raises():
            _ = quantize_llr(
                Span(one_nonfinite_llr), scale=1.0, clip=127
            )
    var valid_llr: List[Float64] = [1.0]
    for invalid_scale in [
        nan[DType.float64](), inf[DType.float64](), 0.0, -1.0,
    ]:
        with assert_raises():
            _ = quantize_llr(
                Span(valid_llr), scale=invalid_scale, clip=127
            )


def test_crc_append_check_and_detection() raises:
    var payload: List[UInt8] = [1, 0, 1, 1, 0, 0, 1, 0, 1]
    # CRC-8 polynomial x^8+x^2+x+1.
    var codeword = crc_append(Span(payload), width=8, polynomial=UInt64(0x07))
    assert_true(crc_check(Span(codeword), width=8, polynomial=UInt64(0x07)))
    codeword[3] ^= 1
    assert_true(not crc_check(Span(codeword), width=8, polynomial=UInt64(0x07)))


def test_awgn_seed_and_zero_variance() raises:
    var samples: List[Complex64] = [Complex64(1.0, -2.0), Complex64(0.5, 0.25)]
    var first = add_awgn(Span(samples), 0.1, seed=UInt64(1234))
    var second = add_awgn(Span(samples), 0.1, seed=UInt64(1234))
    assert_equal(first, second)
    var unchanged = add_awgn(Span(samples), 0.0, seed=UInt64(9))
    assert_equal(unchanged, samples)
    var zero: List[Complex64] = [Complex64(0.0, 0.0)]
    var subnormal = add_awgn(
        Span(zero), 5.0e-324, seed=UInt64(1)
    )
    var repeated_subnormal = add_awgn(
        Span(zero), 5.0e-324, seed=UInt64(1)
    )
    assert_equal(subnormal, repeated_subnormal)
    assert_true(subnormal[0].re != 0.0 or subnormal[0].im != 0.0)
    assert_true(isfinite(subnormal[0].re) and isfinite(subnormal[0].im))
    with assert_raises():
        _ = add_awgn(
            Span(samples), nan[DType.float64](), seed=UInt64(1)
        )
    with assert_raises():
        _ = add_awgn(
            Span(samples), inf[DType.float64](), seed=UInt64(1)
        )


def test_cfo_known_quarter_cycle() raises:
    var samples: List[Complex64] = [Complex64(1.0), Complex64(1.0), Complex64(1.0), Complex64(1.0)]
    var shifted = apply_cfo(Span(samples), 0.25)
    assert_true(abs(shifted[0].re - 1.0) < 1.0e-12)
    assert_true(abs(shifted[1].im - 1.0) < 1.0e-12)
    assert_true(abs(shifted[2].re + 1.0) < 1.0e-12)
    assert_true(abs(shifted[3].im + 1.0) < 1.0e-12)
    var huge_frequency = apply_cfo(Span(samples), 1.0e308)
    assert_equal(huge_frequency, samples)


def test_combined_channel_smoke() raises:
    var samples: List[Complex64] = [Complex64(1.0), Complex64(-1.0)]
    var output = awgn_and_cfo(Span(samples), 0.01, 0.001, seed=UInt64(42))
    assert_equal(len(output), len(samples))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
