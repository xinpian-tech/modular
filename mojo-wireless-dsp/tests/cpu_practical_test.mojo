"""Deterministic and Float64-differential tests for the practical CPU path."""

from std.collections import Span
from std.math import cos, isfinite, sin
from std.sys.info import simd_width_of
from std.testing import assert_equal, assert_raises, assert_true, TestSuite
from std.utils.numerics import inf, nan
from wireless_dsp.core import Complex32, Complex64
from wireless_dsp.dsp.fft import fft
from wireless_dsp.dsp.fir import fir_real
from wireless_dsp.dsp.correlation import cross_correlate_complex
from wireless_dsp.modem.qam import (
    qam_map,
    qam_demap_hard,
    qam_demapper_llr_maxlog,
    qam_demapper_llr_piecewise,
    quantize_llr,
)
from wireless_dsp.backend.cpu.practical import (
    make_fft_plan_f32,
    fft_in_place_f32_with_plan,
    fft_f32,
    ifft_f32,
    fft_batch_f32,
    fft_batch_f32_with_plan,
    make_fir_plan_f32,
    fir_real_f32_with_plan,
    fir_real_f32,
    cross_correlate_complex_split_f32,
    qam_map_f32,
    qam_demap_hard_f32,
    qam_demapper_llr_maxlog_f32,
    qam_demapper_llr_piecewise_f32,
    quantize_llr_f32,
)


def _next_uniform_f32(mut state: UInt64) -> Float32:
    state = state * UInt64(6364136223846793005) + UInt64(1442695040888963407)
    return Float32(state >> 40) / Float32(1 << 24)


def _seeded_complex32(length: Int, mut state: UInt64) -> List[Complex32]:
    var result = List[Complex32](capacity=length)
    for _ in range(length):
        var real = Float32(2.0) * _next_uniform_f32(state) - Float32(1.0)
        var imag = Float32(2.0) * _next_uniform_f32(state) - Float32(1.0)
        result.append(Complex32(real, imag))
    return result^


def _as_complex64(values: Span[Complex32, ...]) -> List[Complex64]:
    var result = List[Complex64](capacity=len(values))
    for index in range(len(values)):
        result.append(
            Complex64(Float64(values[index].re), Float64(values[index].im))
        )
    return result^


def _assert_complex32_matches_64(
    actual: Span[Complex32, ...],
    expected: Span[Complex64, ...],
    tolerance: Float64,
) raises:
    assert_equal(len(actual), len(expected))
    for index in range(len(actual)):
        assert_true(abs(Float64(actual[index].re) - expected[index].re) <= tolerance)
        assert_true(abs(Float64(actual[index].im) - expected[index].im) <= tolerance)


def test_fft_plan_reuse_seeded_float64_differential() raises:
    var seed = UInt64(0xF32F7A11)
    # Keep every required production OFDM size on the same Float64 oracle.
    for size in [1, 2, 8, 64, 128, 256, 512, 1024, 2048, 4096]:
        var first = _seeded_complex32(size, seed)
        var second = _seeded_complex32(size, seed)
        var first_input = first.copy()
        var second_input = second.copy()
        var first64 = _as_complex64(Span(first_input))
        var second64 = _as_complex64(Span(second_input))
        var expected_first = fft(Span(first64))
        var expected_second = fft(Span(second64))
        var plan = make_fft_plan_f32(size)
        fft_in_place_f32_with_plan(first, plan)
        fft_in_place_f32_with_plan(second, plan)
        var tolerance = 1.0e-5 + 2.5e-6 * Float64(size)
        _assert_complex32_matches_64(
            Span(first), Span(expected_first), tolerance
        )
        _assert_complex32_matches_64(
            Span(second), Span(expected_second), tolerance
        )


def test_make_fft_plan_f32_analytic_builder_grid_and_int_edges() raises:
    comptime two_pi = 6.283185307179586476925286766559
    for size in [1, 2, 4, 8, 16, 64, 256]:
        for inverse in [False, True]:
            var first = make_fft_plan_f32(size, inverse=inverse)
            var second = make_fft_plan_f32(size, inverse=inverse)
            assert_equal(first.size, size)
            assert_equal(first.inverse, inverse)
            assert_equal(first.twiddles, second.twiddles)
            assert_equal(len(first.twiddles), size // 2)
            var direction = two_pi if inverse else -two_pi
            for k in range(size // 2):
                var angle = direction * Float64(k) / Float64(size)
                assert_true(abs(Float64(first.twiddles[k].re) - cos(angle)) <= 1.5e-6)
                assert_true(abs(Float64(first.twiddles[k].im) - sin(angle)) <= 1.5e-6)
    with assert_raises():
        _ = make_fft_plan_f32(Int.MIN)
    with assert_raises():
        _ = make_fft_plan_f32(Int.MAX)


def test_fft_roundtrip_batch_scale_and_non_aliasing() raises:
    var seed = UInt64(0xB47C2026)
    var first = _seeded_complex32(128, seed)
    var second = _seeded_complex32(128, seed)
    var original = first.copy()
    var flat = first.copy()
    for value in second:
        flat.append(Complex32(value.re, value.im))

    var forward_plan = make_fft_plan_f32(128)
    var transformed = fft_batch_f32_with_plan(Span(flat), forward_plan)
    var first64 = _as_complex64(Span(first))
    var second64 = _as_complex64(Span(second))
    var expected_first = fft(Span(first64))
    var expected_second = fft(Span(second64))
    _assert_complex32_matches_64(
        Span(transformed)[0:128], Span(expected_first), 4.0e-4
    )
    _assert_complex32_matches_64(
        Span(transformed)[128:256], Span(expected_second), 4.0e-4
    )
    var restored_flat = fft_batch_f32(
        Span(transformed), 128, inverse=True
    )
    for index in range(len(flat)):
        assert_true(abs(restored_flat[index].re - flat[index].re) < 4.0e-5)
        assert_true(abs(restored_flat[index].im - flat[index].im) < 4.0e-5)
    # Out-of-place batch execution must not mutate or alias the input.
    assert_equal(flat[0], original[0])
    transformed[0] = Complex32(123.0, -456.0)
    assert_equal(flat[0], original[0])

    var first_spectrum = fft_f32(Span(first))
    var restored = ifft_f32(Span(first_spectrum))
    for index in range(128):
        assert_true(abs(restored[index].re - original[index].re) < 4.0e-5)
        assert_true(abs(restored[index].im - original[index].im) < 4.0e-5)

    # An impulse exposes the forward-unscaled/inverse-1/N convention exactly.
    var impulse = List[Complex32](length=8, fill=Complex32(0.0, 0.0))
    impulse[0] = Complex32(2.0, -1.0)
    var spectrum = fft_f32(Span(impulse))
    for value in spectrum:
        assert_equal(value, Complex32(2.0, -1.0))
    var impulse_restored = ifft_f32(Span(spectrum))
    assert_equal(impulse_restored, impulse)


def test_fft_length_validation_and_empty_batch() raises:
    with assert_raises():
        _ = make_fft_plan_f32(0)
    with assert_raises():
        _ = make_fft_plan_f32(12)
    var four = List[Complex32](length=4, fill=Complex32(0.0, 0.0))
    var plan = make_fft_plan_f32(8)
    with assert_raises():
        fft_in_place_f32_with_plan(four, plan)
    var ten = List[Complex32](length=10, fill=Complex32(0.0, 0.0))
    with assert_raises():
        _ = fft_batch_f32_with_plan(Span(ten), plan)
    var empty = List[Complex32]()
    var empty_result = fft_batch_f32_with_plan(Span(empty), plan)
    assert_equal(len(empty_result), 0)


def test_real_fir_simd_seeded_float64_differential_and_plan_copy() raises:
    comptime width = simd_width_of[DType.float32]()
    var seed = UInt64(0xF1A5EED)
    var signal = List[Float32](capacity=5 * Int(width) + 19)
    var taps = List[Float32](capacity=2 * Int(width) + 3)
    for _ in range(5 * Int(width) + 19):
        signal.append(Float32(2.0) * _next_uniform_f32(seed) - Float32(1.0))
    for _ in range(2 * Int(width) + 3):
        taps.append(_next_uniform_f32(seed) - Float32(0.5))

    var signal64 = List[Float64](capacity=len(signal))
    var taps64 = List[Float64](capacity=len(taps))
    for value in signal:
        signal64.append(Float64(value))
    for value in taps:
        taps64.append(Float64(value))
    var expected = fir_real(Span(signal64), Span(taps64))

    var plan = make_fir_plan_f32(Span(taps))
    # Plans own their coefficients: changing the source list after construction
    # cannot change a later result.
    var original_first_tap = taps[0]
    taps[0] = Float32(999.0)
    var actual = fir_real_f32_with_plan(Span(signal), plan)
    taps[0] = original_first_tap
    assert_equal(len(actual), len(expected))
    for index in range(len(actual)):
        assert_true(abs(Float64(actual[index]) - expected[index]) < 8.0e-5)

    var direct = fir_real_f32(Span(signal), Span(taps))
    for index in range(len(direct)):
        assert_true(abs(direct[index] - actual[index]) < 2.0e-6)


def test_fir_edge_lengths_and_validation() raises:
    var empty_signal = List[Float32]()
    var taps: List[Float32] = [0.5, -0.25, 0.125]
    assert_equal(len(fir_real_f32(Span(empty_signal), Span(taps))), 0)
    var one: List[Float32] = [4.0]
    var single_tap: List[Float32] = [-0.5]
    assert_equal(fir_real_f32(Span(one), Span(single_tap))[0], Float32(-2.0))
    var empty_taps = List[Float32]()
    with assert_raises():
        _ = make_fir_plan_f32(Span(empty_taps))


def test_make_fir_plan_f32_owned_reverse_oracle_and_nonfinite_edges() raises:
    var state = UInt64(0xF17E2026)
    for length in [1, 2, 3, 17, 65]:
        var taps = List[Float32](capacity=length)
        for _ in range(length):
            taps.append(_next_uniform_f32(state) - Float32(0.5))
        var expected = taps.copy()
        var first = make_fir_plan_f32(Span(taps))
        var second = make_fir_plan_f32(Span(taps))
        assert_equal(first.taps, expected)
        assert_equal(first.taps, second.taps)
        assert_equal(first.reversed_taps, second.reversed_taps)
        for index in range(length):
            assert_equal(first.reversed_taps[index], expected[length - 1 - index])
        taps[0] = Float32(99.0)
        assert_equal(first.taps[0], expected[0])

    var invalid_nan: List[Float32] = [nan[DType.float32]()]
    var invalid_pos_inf: List[Float32] = [inf[DType.float32]()]
    var invalid_neg_inf: List[Float32] = [-inf[DType.float32]()]
    with assert_raises():
        _ = make_fir_plan_f32(Span(invalid_nan))
    with assert_raises():
        _ = make_fir_plan_f32(Span(invalid_pos_inf))
    with assert_raises():
        _ = make_fir_plan_f32(Span(invalid_neg_inf))

    var valid: List[Float32] = [0.25, -0.5]
    var signal: List[Float32] = [1.0, 2.0]
    var mutated_taps = make_fir_plan_f32(Span(valid))
    mutated_taps.taps[0] = nan[DType.float32]()
    with assert_raises():
        _ = fir_real_f32_with_plan(Span(signal), mutated_taps)
    var mutated_reverse = make_fir_plan_f32(Span(valid))
    mutated_reverse.reversed_taps[0] = inf[DType.float32]()
    with assert_raises():
        _ = fir_real_f32_with_plan(Span(signal), mutated_reverse)


def test_complex_split_correlation_simd_float64_differential() raises:
    comptime width = simd_width_of[DType.float32]()
    var seed = UInt64(0xC022E1A7E)
    var signal = _seeded_complex32(4 * Int(width) + 21, seed)
    var reference = _seeded_complex32(2 * Int(width) + 3, seed)
    var signal_re = List[Float32](capacity=len(signal))
    var signal_im = List[Float32](capacity=len(signal))
    var reference_re = List[Float32](capacity=len(reference))
    var reference_im = List[Float32](capacity=len(reference))
    for value in signal:
        signal_re.append(value.re)
        signal_im.append(value.im)
    for value in reference:
        reference_re.append(value.re)
        reference_im.append(value.im)

    var actual = cross_correlate_complex_split_f32(
        Span(signal_re), Span(signal_im), Span(reference_re), Span(reference_im)
    )
    var signal64 = _as_complex64(Span(signal))
    var reference64 = _as_complex64(Span(reference))
    var expected = cross_correlate_complex(Span(signal64), Span(reference64))
    _assert_complex32_matches_64(Span(actual), Span(expected), 1.2e-4)

    var short_re: List[Float32] = [1.0]
    var short_im: List[Float32] = [0.0]
    var longer_re: List[Float32] = [1.0, 2.0]
    var longer_im: List[Float32] = [0.0, 0.0]
    assert_equal(
        len(cross_correlate_complex_split_f32(
            Span(short_re), Span(short_im), Span(longer_re), Span(longer_im)
        )),
        0,
    )


def test_complex_split_correlation_validation() raises:
    var signal_re: List[Float32] = [1.0]
    var signal_im_bad: List[Float32] = [1.0, 2.0]
    var reference_re: List[Float32] = [1.0]
    var reference_im: List[Float32] = [1.0]
    with assert_raises():
        _ = cross_correlate_complex_split_f32(
            Span(signal_re),
            Span(signal_im_bad),
            Span(reference_re),
            Span(reference_im),
        )
    var signal_re_ok: List[Float32] = [1.0, 2.0]
    var signal_im_ok: List[Float32] = [0.0, 0.0]
    var reference_re_bad: List[Float32] = [1.0, 2.0]
    var reference_im_bad: List[Float32] = [1.0]
    with assert_raises():
        _ = cross_correlate_complex_split_f32(
            Span(signal_re_ok),
            Span(signal_im_ok),
            Span(reference_re_bad),
            Span(reference_im_bad),
        )
    var signal_re_one: List[Float32] = [1.0]
    var signal_im_one: List[Float32] = [0.0]
    var empty_re = List[Float32]()
    var empty_im = List[Float32]()
    with assert_raises():
        _ = cross_correlate_complex_split_f32(
            Span(signal_re_one),
            Span(signal_im_one),
            Span(empty_re),
            Span(empty_im),
        )


def test_bpsk_and_square_qam_all_orders_float64_differential() raises:
    var seed = UInt64(0x0A11C0DE)
    var noise_variance = Float32(0.173)
    for bits_per_symbol in [1, 2, 4, 6, 8, 10, 12]:
        var samples = _seeded_complex32(4, seed)
        var samples64 = _as_complex64(Span(samples))
        var expected_full = qam_demapper_llr_maxlog(
            Span(samples64), bits_per_symbol, Float64(noise_variance)
        )
        var expected_piecewise = qam_demapper_llr_piecewise(
            Span(samples64), bits_per_symbol, Float64(noise_variance)
        )
        var actual_full = qam_demapper_llr_maxlog_f32(
            Span(samples), bits_per_symbol, noise_variance
        )
        var actual_piecewise = qam_demapper_llr_piecewise_f32(
            Span(samples), bits_per_symbol, noise_variance
        )
        assert_equal(len(actual_full), 4 * bits_per_symbol)
        assert_equal(len(actual_piecewise), len(actual_full))
        for index in range(len(actual_full)):
            assert_true(
                abs(Float64(actual_full[index]) - expected_full[index]) < 8.0e-5
            )
            assert_true(
                abs(Float64(actual_piecewise[index]) - expected_piecewise[index])
                < 8.0e-5
            )
            assert_true(abs(actual_full[index] - actual_piecewise[index]) < 1.0e-4)

    # Finite Float32 inputs can overflow every raw squared-distance metric even
    # when division by the equally large N0 leaves a small, representable LLR.
    var extreme_samples: List[Complex32] = [
        Complex32(Float32(1.0e38), Float32(-1.0e38)),
        Complex32(Float32(-1.0e38), Float32(1.0e38)),
    ]
    var extreme_samples64 = _as_complex64(Span(extreme_samples))
    var extreme_noise = Float32(1.0e38)
    for bits_per_symbol in [1, 2, 4, 6, 8, 10, 12]:
        var expected_full = qam_demapper_llr_maxlog(
            Span(extreme_samples64),
            bits_per_symbol,
            Float64(extreme_noise),
        )
        var expected_piecewise = qam_demapper_llr_piecewise(
            Span(extreme_samples64),
            bits_per_symbol,
            Float64(extreme_noise),
        )
        var actual_full = qam_demapper_llr_maxlog_f32(
            Span(extreme_samples), bits_per_symbol, extreme_noise
        )
        var actual_piecewise = qam_demapper_llr_piecewise_f32(
            Span(extreme_samples), bits_per_symbol, extreme_noise
        )
        for index in range(len(actual_full)):
            assert_true(isfinite(actual_full[index]))
            assert_true(isfinite(actual_piecewise[index]))
            var tolerance = 2.0e-5 + 2.0e-6 * abs(expected_full[index])
            assert_true(
                abs(Float64(actual_full[index]) - expected_full[index])
                <= tolerance
            )
            assert_true(
                abs(
                    Float64(actual_piecewise[index])
                    - expected_piecewise[index]
                )
                <= tolerance
            )

    # The motivating BPSK ratio is exactly representable despite both raw
    # multiplication and squared-distance formulations overflowing.
    var one_extreme: List[Complex32] = [
        Complex32(Float32(1.0e38), Float32(0.0))
    ]
    var full_bpsk = qam_demapper_llr_maxlog_f32(
        Span(one_extreme), 1, Float32(1.0e38)
    )
    var piecewise_bpsk = qam_demapper_llr_piecewise_f32(
        Span(one_extreme), 1, Float32(1.0e38)
    )
    assert_true(abs(full_bpsk[0] - Float32(4.0)) < Float32(1.0e-5))
    assert_true(abs(piecewise_bpsk[0] - Float32(4.0)) < Float32(1.0e-5))


def test_bpsk_and_square_qam_exact_labels_have_correct_llr_signs() raises:
    for bits_per_symbol in [1, 2, 4, 6, 8, 10, 12]:
        var order = 1 << bits_per_symbol
        var labels: List[Int] = [0, 1, order // 3, order // 2, order - 1]
        var bits = List[UInt8](capacity=len(labels) * bits_per_symbol)
        for label in labels:
            for bit_index in range(bits_per_symbol):
                bits.append(
                    UInt8((label >> (bits_per_symbol - bit_index - 1)) & 1)
                )
        var mapped64 = qam_map(Span(bits), bits_per_symbol)
        var mapped32 = qam_map_f32(Span(bits), bits_per_symbol)
        for index in range(len(mapped64)):
            assert_true(
                abs(Float64(mapped32[index].re) - mapped64[index].re) < 1.0e-6
            )
            assert_true(
                abs(Float64(mapped32[index].im) - mapped64[index].im) < 1.0e-6
            )
        assert_equal(qam_demap_hard_f32(Span(mapped32), bits_per_symbol), bits)
        assert_equal(qam_demap_hard(Span(mapped64), bits_per_symbol), bits)
        var llrs = qam_demapper_llr_piecewise_f32(
            Span(mapped32), bits_per_symbol, Float32(0.25)
        )
        for index in range(len(bits)):
            assert_true(llrs[index] > 0.0 if bits[index] == 0 else llrs[index] < 0.0)

    # Exhaust every Gray label, including all 4096-QAM labels, so mapper and
    # hard slicer coverage is not limited to representative endpoints.
    for bits_per_symbol in [1, 2, 4, 6, 8, 10, 12]:
        var order = 1 << bits_per_symbol
        var all_bits = List[UInt8](capacity=order * bits_per_symbol)
        for label in range(order):
            for bit_index in range(bits_per_symbol):
                all_bits.append(
                    UInt8(
                        (label >> (bits_per_symbol - bit_index - 1)) & 1
                    )
                )
        var mapped32 = qam_map_f32(Span(all_bits), bits_per_symbol)
        var mapped64 = qam_map(Span(all_bits), bits_per_symbol)
        assert_equal(len(mapped32), order)
        for index in range(order):
            assert_true(isfinite(mapped32[index].re))
            assert_true(isfinite(mapped32[index].im))
            assert_true(
                abs(Float64(mapped32[index].re) - mapped64[index].re)
                < 1.0e-6
            )
            assert_true(
                abs(Float64(mapped32[index].im) - mapped64[index].im)
                < 1.0e-6
            )
        assert_equal(
            qam_demap_hard_f32(Span(mapped32), bits_per_symbol), all_bits
        )


def test_square_qam_validation_and_empty_input() raises:
    var one: List[Complex32] = [Complex32(0.0, 0.0)]
    for unsupported in [0, 3, 5, 14]:
        with assert_raises():
            _ = qam_demapper_llr_piecewise_f32(
                Span(one), unsupported, Float32(0.1)
            )
    for invalid_noise in [
        Float32(0.0),
        Float32(-1.0),
        nan[DType.float32](),
        inf[DType.float32](),
    ]:
        with assert_raises():
            _ = qam_demapper_llr_maxlog_f32(
                Span(one), 4, invalid_noise
            )
        with assert_raises():
            _ = qam_demapper_llr_piecewise_f32(
                Span(one), 4, invalid_noise
            )
    var empty = List[Complex32]()
    assert_equal(
        len(qam_demapper_llr_piecewise_f32(
            Span(empty), 12, Float32(0.1)
        )),
        0,
    )
    var llrs32: List[Float32] = [-100.0, -0.125, 0.125, 100.0]
    var llrs64: List[Float64] = [-100.0, -0.125, 0.125, 100.0]
    assert_equal(
        quantize_llr_f32(Span(llrs32), scale=Float32(4.0), clip=7),
        quantize_llr(Span(llrs64), scale=4.0, clip=7),
    )
    var overflowing_scaled_llrs: List[Float32] = [
        Float32(1.0e30), Float32(-1.0e30)
    ]
    var saturated: List[Int] = [127, -127]
    assert_equal(
        quantize_llr_f32(
            Span(overflowing_scaled_llrs),
            scale=Float32(1.0e30),
            clip=127,
        ),
        saturated,
    )

    # Extreme finite samples must reach the same endpoint decisions as the
    # Float64 slicer without overflowing the pre-clamp coordinate product.
    var extreme_hard_samples: List[Complex32] = [
        Complex32(Float32(1.0e38), Float32(-1.0e38)),
        Complex32(Float32(-1.0e38), Float32(1.0e38)),
    ]
    var extreme_hard_samples64 = _as_complex64(Span(extreme_hard_samples))
    for bits_per_symbol in [1, 2, 4, 6, 8, 10, 12]:
        assert_equal(
            qam_demap_hard_f32(
                Span(extreme_hard_samples), bits_per_symbol
            ),
            qam_demap_hard(
                Span(extreme_hard_samples64), bits_per_symbol
            ),
        )

    # A mathematically non-zero soft output beyond the Float32 exponent range
    # is rejected rather than leaking infinity or a wrapped sign.
    var overflow_sample: List[Complex32] = [
        Complex32(Float32(1.0e38), Float32(0.0))
    ]
    for bits_per_symbol in [1, 2, 4, 6, 8, 10, 12]:
        with assert_raises():
            _ = qam_demapper_llr_maxlog_f32(
                Span(overflow_sample),
                bits_per_symbol,
                Float32(1.0e-38),
            )
        with assert_raises():
            _ = qam_demapper_llr_piecewise_f32(
                Span(overflow_sample),
                bits_per_symbol,
                Float32(1.0e-38),
            )

    var underflow_sample: List[Complex32] = [
        Complex32(Float32(1.0e-38), Float32(0.0))
    ]
    with assert_raises():
        _ = qam_demapper_llr_maxlog_f32(
            Span(underflow_sample), 1, Float32(1.0e38)
        )
    with assert_raises():
        _ = qam_demapper_llr_piecewise_f32(
            Span(underflow_sample), 1, Float32(1.0e38)
        )
    with assert_raises():
        _ = quantize_llr_f32(
            Span(llrs32), scale=nan[DType.float32](), clip=7
        )
    var invalid_llrs: List[Float32] = [inf[DType.float32]()]
    with assert_raises():
        _ = quantize_llr_f32(
            Span(invalid_llrs), scale=Float32(1.0), clip=7
        )
    var invalid_sample: List[Complex32] = [
        Complex32(nan[DType.float32](), Float32(0.0))
    ]
    with assert_raises():
        _ = qam_demap_hard_f32(Span(invalid_sample), 2)
    with assert_raises():
        _ = qam_demapper_llr_maxlog_f32(
            Span(invalid_sample), 2, Float32(0.1)
        )
    with assert_raises():
        _ = qam_demapper_llr_piecewise_f32(
            Span(invalid_sample), 2, Float32(0.1)
        )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
