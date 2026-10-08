"""Direct backend/fixed/MIMO evidence with independent scalar oracles."""

from std.collections import Span
from std.math import cos, sin, sqrt
from std.testing import assert_equal, assert_raises, assert_true, TestSuite
from wireless_dsp.core import Complex32, Complex64
from wireless_dsp.mimo.matrix import (
    SmallComplexMatrix,
    cholesky,
    gram_matrix,
    hermitian,
    inverse,
    matrix_multiply,
    matrix_vector_multiply,
    mmse_equalize,
    qr_decompose,
    zf_equalize,
)
from wireless_dsp.backend.cpu.practical import (
    cross_correlate_complex_split_f32,
    fft_batch_f32,
    fft_batch_f32_with_plan,
    fft_f32,
    fft_in_place_f32_with_plan,
    fir_real_f32,
    fir_real_f32_with_plan,
    ifft_f32,
    make_fft_plan_f32,
    make_fir_plan_f32,
    qam_demap_hard_f32,
    qam_demapper_llr_maxlog_f32,
    qam_demapper_llr_piecewise_f32,
    qam_map_f32,
    quantize_llr_f32,
)
from wireless_dsp.backend.cpu.simd import (
    simd_complex_dot_split_f32,
    simd_dot_f32,
    simd_energy_f32,
    simd_sum_f32,
)
from wireless_dsp.backend.cpu.mimo_f32 import (
    complex_matvec_f32,
    complex_matvec_f32_into,
    make_mimo_workspace_f32,
    mimo_gram_f32,
    mimo_gram_f32_into,
    mimo_gram_matched_f32_into,
    mimo_matched_filter_f32,
    mimo_matched_filter_f32_into,
    mimo_mmse_f32,
    mimo_mmse_f32_into,
    mimo_zf_f32,
    mimo_zf_f32_into,
)
from wireless_dsp.numerics.quantization import QFormat
from wireless_dsp.numerics.complex_fixed import ComplexRaw
from wireless_dsp.numerics.scale_schedule import ScaleStage
from wireless_dsp.backend.fixed_fft_reference import (
    fixed_fft_radix2_raw,
    quantized_fft_twiddles,
)
from wireless_dsp.backend.fixed_reference import (
    complex_cross_correlate_raw,
    complex_dot_conjugate_raw,
    complex_fir_raw,
    fixed_dot_raw,
    fixed_fir_raw,
)
from wireless_dsp.backend.fixed_phy_reference import (
    FixedPHYFormats,
    fixed_equalize_flat_raw,
    fixed_flat_channel_raw,
    fixed_ls_flat_channel_raw,
    fixed_ofdm_demodulate_raw,
    fixed_ofdm_modulate_raw,
    fixed_phy_canonical_rtl_vectors,
    fixed_phy_default_formats,
    fixed_phy_one_symbol_reference,
    fixed_phy_result_checksum,
    fixed_phy_scale_trace_text,
    fixed_qpsk_float64_audit,
    fixed_qpsk_hard_bits,
    fixed_qpsk_llrs_raw,
    fixed_qpsk_map_raw,
    fixed_reciprocal_positive_raw,
)
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
from wireless_dsp.backend.fixed_sync_reference import (
    fixed_repetition_canonical_rtl_vectors,
    fixed_repetition_correlation_raw,
    fixed_repetition_scan_checksum,
    fixed_repetition_scan_raw,
    fixed_window_energy_raw,
)
from wireless_dsp.backend.fixed_wifi_bcc_reference import (
    FixedWifiBCCViterbiConfig,
    fixed_wifi_bcc_canonical_rtl_vectors,
    fixed_wifi_bcc_encode,
    fixed_wifi_bcc_hard_llrs_raw,
    fixed_wifi_bcc_result_checksum,
    fixed_wifi_bcc_viterbi_decode_hard,
    fixed_wifi_bcc_viterbi_decode_soft,
)
from wireless_dsp.backend.fixed_wifi_phy_reference import (
    fixed_wifi_bcc_ofdm_reference,
    fixed_wifi_phy_canonical_rtl_vectors,
    fixed_wifi_phy_result_checksum,
)


comptime _TWO_PI = 6.283185307179586476925286766559


def _assert_close(actual: Float64, expected: Float64, tolerance: Float64) raises:
    assert_true(abs(actual - expected) <= tolerance)


def _parity(value: Int) -> UInt8:
    var remaining = value
    var result = UInt8(0)
    while remaining != 0:
        result ^= UInt8(remaining & 1)
        remaining >>= 1
    return result


def _independent_bcc(bits: Span[UInt8, ...]) -> List[UInt8]:
    var result = List[UInt8](capacity=2 * (len(bits) + 6))
    var register = 0
    for step in range(len(bits) + 6):
        var bit = Int(bits[step]) if step < len(bits) else 0
        register = ((register << 1) | bit) & 0x7f
        result.append(_parity(register & 0o133))
        result.append(_parity(register & 0o171))
    return result^


def _naive_dft(values: Span[Complex32, ...], inverse_transform: Bool) -> List[Complex64]:
    var result = List[Complex64](capacity=len(values))
    for output_index in range(len(values)):
        var acc = Complex64(0.0, 0.0)
        for input_index in range(len(values)):
            var angle = _TWO_PI * Float64(output_index * input_index) / Float64(len(values))
            if not inverse_transform:
                angle = -angle
            var twiddle = Complex64(cos(angle), sin(angle))
            acc = acc + Complex64(Float64(values[input_index].re), Float64(values[input_index].im)) * twiddle
        if inverse_transform:
            acc = Complex64(acc.re / Float64(len(values)), acc.im / Float64(len(values)))
        result.append(acc)
    return result^


def test_cpu_fft_direct_float64_oracle_and_edges() raises:
    var state = UInt64(0xD17F64)
    for size in [1, 2, 4, 8, 16]:
        var values = List[Complex32](capacity=size)
        for _ in range(size):
            state = state * UInt64(6364136223846793005) + UInt64(1442695040888963407)
            var re = Float32(Int((state >> 56) & 255) - 128) / 64.0
            state = state * UInt64(6364136223846793005) + UInt64(1442695040888963407)
            var im = Float32(Int((state >> 56) & 255) - 128) / 64.0
            values.append(Complex32(re, im))
        var expected = _naive_dft(Span(values), False)
        var direct = fft_f32(Span(values))
        var plan = make_fft_plan_f32(size)
        var in_place = values.copy()
        fft_in_place_f32_with_plan(in_place, plan)
        var batch_values = values.copy()
        for value in values:
            batch_values.append(value)
        var planned_batch = fft_batch_f32_with_plan(Span(batch_values), plan)
        var direct_batch = fft_batch_f32(Span(batch_values), size)
        for index in range(size):
            # Explicit absolute tolerance: Float32 FFT versus O(N^2) Float64 DFT.
            _assert_close(Float64(direct[index].re), expected[index].re, 3.0e-5)
            _assert_close(Float64(direct[index].im), expected[index].im, 3.0e-5)
            _assert_close(Float64(in_place[index].re), expected[index].re, 3.0e-5)
            _assert_close(Float64(planned_batch[index].re), expected[index].re, 3.0e-5)
            _assert_close(Float64(direct_batch[index + size].im), expected[index].im, 3.0e-5)
        var expected_inverse = _naive_dft(Span(direct), True)
        var restored = ifft_f32(Span(direct))
        for index in range(size):
            _assert_close(Float64(restored[index].re), expected_inverse[index].re, 3.0e-5)
            _assert_close(Float64(restored[index].im), expected_inverse[index].im, 3.0e-5)
    with assert_raises():
        _ = make_fft_plan_f32(0)
    with assert_raises():
        _ = make_fft_plan_f32(3)


def test_cpu_practical_and_simd_scalar_differentials() raises:
    var signal: List[Float32] = [0.5, -1.0, 2.0, 0.25, -0.75]
    var taps: List[Float32] = [0.25, -0.5, 0.125]
    var expected: List[Float64] = [0.125, -0.5, 1.0625, -1.0625, -0.0625]
    var plan = make_fir_plan_f32(Span(taps))
    var planned = fir_real_f32_with_plan(Span(signal), plan)
    var direct = fir_real_f32(Span(signal), Span(taps))
    for index in range(len(expected)):
        _assert_close(Float64(planned[index]), expected[index], 1.0e-7)
        _assert_close(Float64(direct[index]), expected[index], 1.0e-7)

    var re: List[Float32] = [1.0, -2.0, 0.5, 3.0]
    var im: List[Float32] = [0.5, 1.0, -1.0, 2.0]
    var rr: List[Float32] = [0.25, -0.5]
    var ri: List[Float32] = [1.0, 0.25]
    var correlation = cross_correlate_complex_split_f32(Span(re), Span(im), Span(rr), Span(ri))
    for lag in range(3):
        var expected_re = 0.0
        var expected_im = 0.0
        for k in range(2):
            expected_re += Float64(re[lag + k]) * Float64(rr[k]) + Float64(im[lag + k]) * Float64(ri[k])
            expected_im += Float64(im[lag + k]) * Float64(rr[k]) - Float64(re[lag + k]) * Float64(ri[k])
        _assert_close(Float64(correlation[lag].re), expected_re, 2.0e-6)
        _assert_close(Float64(correlation[lag].im), expected_im, 2.0e-6)

    var rhs: List[Float32] = [-0.25, 0.75, 1.5, -2.0]
    var expected_sum = 0.0
    var expected_dot = 0.0
    var expected_energy = 0.0
    for index in range(len(re)):
        expected_sum += Float64(re[index])
        expected_dot += Float64(re[index]) * Float64(rhs[index])
        expected_energy += Float64(re[index]) * Float64(re[index])
    _assert_close(Float64(simd_sum_f32(Span(re))), expected_sum, 1.0e-6)
    _assert_close(Float64(simd_dot_f32(Span(re), Span(rhs))), expected_dot, 1.0e-6)
    _assert_close(Float64(simd_energy_f32(Span(re))), expected_energy, 1.0e-6)
    var dot_re = re.copy()
    var dot_im = im.copy()
    var complex_dot = simd_complex_dot_split_f32(Span(re), Span(im), Span(dot_re), Span(dot_im))
    _assert_close(Float64(complex_dot.re), 20.5, 1.0e-6)
    _assert_close(Float64(complex_dot.im), 0.0, 1.0e-6)

    var bits: List[UInt8] = [0, 0, 0, 1, 1, 0, 1, 1]
    var mapped = qam_map_f32(Span(bits), 2)
    assert_equal(qam_demap_hard_f32(Span(mapped), 2), bits)
    var full = qam_demapper_llr_maxlog_f32(Span(mapped), 2, 0.25)
    var piecewise = qam_demapper_llr_piecewise_f32(Span(mapped), 2, 0.25)
    for index in range(len(full)):
        _assert_close(Float64(full[index]), Float64(piecewise[index]), 1.0e-6)
    var quantized = quantize_llr_f32(Span(full), scale=1.0, clip=31)
    assert_equal(len(quantized), len(bits))
    var empty = List[Float32]()
    assert_equal(len(fir_real_f32(Span(empty), Span(taps))), 0)


def test_cpu_practical_seeded_properties_and_direct_edges() raises:
    var state = UInt64(0x43505550524F50)
    for _ in range(12):
        var signal_re = List[Float32](capacity=11)
        var signal_im = List[Float32](capacity=11)
        var reference_re = List[Float32](capacity=4)
        var reference_im = List[Float32](capacity=4)
        for index in range(11):
            state = state * UInt64(6364136223846793005) + UInt64(1)
            signal_re.append(Float32(Int((state >> 59) & 31) - 16) / 8.0)
            state = state * UInt64(6364136223846793005) + UInt64(1)
            signal_im.append(Float32(Int((state >> 59) & 31) - 16) / 8.0)
            if index < 4:
                reference_re.append(Float32(index - 2) / 4.0)
                reference_im.append(Float32(3 - index) / 8.0)
        var actual = cross_correlate_complex_split_f32(
            Span(signal_re), Span(signal_im), Span(reference_re), Span(reference_im)
        )
        for lag in range(len(actual)):
            var expected_re = 0.0
            var expected_im = 0.0
            for k in range(4):
                expected_re += Float64(signal_re[lag + k]) * Float64(reference_re[k]) + Float64(signal_im[lag + k]) * Float64(reference_im[k])
                expected_im += Float64(signal_im[lag + k]) * Float64(reference_re[k]) - Float64(signal_re[lag + k]) * Float64(reference_im[k])
            _assert_close(Float64(actual[lag].re), expected_re, 3.0e-6)
            _assert_close(Float64(actual[lag].im), expected_im, 3.0e-6)

        var bpsk = List[Complex32](capacity=17)
        var expected_bits = List[UInt8](capacity=17)
        var llrs = List[Float32](capacity=17)
        for index in range(17):
            state = state * UInt64(6364136223846793005) + UInt64(1)
            var bit = UInt8((state >> 63) & 1)
            expected_bits.append(bit)
            bpsk.append(Complex32(Float32(1.0) if bit == 0 else Float32(-1.0), Float32(index - 8) / Float32(16.0)))
            llrs.append(Float32(Int((state >> 56) & 127) - 63) / 4.0)
        assert_equal(qam_demap_hard_f32(Span(bpsk), 1), expected_bits)
        var quantized = quantize_llr_f32(Span(llrs), scale=2.0, clip=23)
        for index in range(len(llrs)):
            var scaled = llrs[index] * 2.0
            var expected = Int(scaled + (Float32(0.5) if scaled >= 0.0 else Float32(-0.5)))
            assert_equal(quantized[index], max(-23, min(23, expected)))

        var lhs = signal_re.copy()
        var rhs = signal_im.copy()
        var scalar_sum = 0.0
        var scalar_dot = 0.0
        var scalar_energy = 0.0
        var scalar_complex_re = 0.0
        var scalar_complex_im = 0.0
        for index in range(len(lhs)):
            scalar_sum += Float64(lhs[index])
            scalar_dot += Float64(lhs[index]) * Float64(rhs[index])
            scalar_energy += Float64(lhs[index]) * Float64(lhs[index])
            scalar_complex_re += Float64(lhs[index]) * Float64(lhs[index]) + Float64(rhs[index]) * Float64(rhs[index])
        var lhs_copy = lhs.copy()
        var rhs_copy = rhs.copy()
        _assert_close(Float64(simd_sum_f32(Span(lhs))), scalar_sum, 4.0e-6)
        _assert_close(Float64(simd_dot_f32(Span(lhs), Span(rhs))), scalar_dot, 4.0e-6)
        _assert_close(Float64(simd_energy_f32(Span(lhs))), scalar_energy, 4.0e-6)
        var complex_dot = simd_complex_dot_split_f32(Span(lhs), Span(rhs), Span(lhs_copy), Span(rhs_copy))
        _assert_close(Float64(complex_dot.re), scalar_complex_re, 8.0e-6)
        _assert_close(Float64(complex_dot.im), scalar_complex_im, 8.0e-6)

    var empty_complex = List[Complex32]()
    with assert_raises():
        _ = fft_f32(Span(empty_complex))
    with assert_raises():
        _ = ifft_f32(Span(empty_complex))
    var bad_batch = List[Complex32](length=5, fill=Complex32(0.0, 0.0))
    with assert_raises():
        _ = fft_batch_f32(Span(bad_batch), 4)
    var taps: List[Float32] = [1.0]
    var plan = make_fir_plan_f32(Span(taps))
    var empty_real = List[Float32]()
    assert_equal(len(fir_real_f32_with_plan(Span(empty_real), plan)), 0)
    var odd_bits: List[UInt8] = [0, 1, 0]
    with assert_raises():
        _ = qam_map_f32(Span(odd_bits), 2)
    with assert_raises():
        _ = qam_map_f32(Span(odd_bits), 3)
    var short: List[Float32] = [1.0]
    var long: List[Float32] = [1.0, 2.0]
    with assert_raises():
        _ = cross_correlate_complex_split_f32(Span(short), Span(long), Span(short.copy()), Span(short.copy()))
    var one_complex: List[Complex32] = [Complex32(1.0, 0.0)]
    with assert_raises():
        _ = qam_demap_hard_f32(Span(one_complex), 3)
    with assert_raises():
        _ = quantize_llr_f32(Span(short), scale=0.0, clip=7)
    assert_equal(simd_sum_f32(Span(empty_real)), Float32(0.0))
    assert_equal(simd_energy_f32(Span(empty_real)), Float32(0.0))
    with assert_raises():
        _ = simd_dot_f32(Span(short), Span(long))
    with assert_raises():
        _ = simd_complex_dot_split_f32(Span(short), Span(short.copy()), Span(long), Span(long.copy()))


def _mimo_static_channel() raises -> SmallComplexMatrix:
    var channel = SmallComplexMatrix(2, 2)
    channel[0, 0] = Complex64(1.0, 0.0)
    channel[0, 1] = Complex64(0.5, 0.25)
    channel[1, 0] = Complex64(-0.25, 0.5)
    channel[1, 1] = Complex64(1.5, -0.25)
    return channel^


def test_reference_mimo_independent_static_and_seeded_properties() raises:
    var channel = _mimo_static_channel()
    var channel_h = hermitian(channel)
    assert_equal(channel_h[1, 0], Complex64(0.5, -0.25))
    var gram = gram_matrix(channel)
    var multiplied = matrix_multiply(channel_h, channel)
    var expected_gram: List[Complex64] = [
        Complex64(1.3125, 0.0), Complex64(0.0, -0.4375),
        Complex64(0.0, 0.4375), Complex64(2.625, 0.0),
    ]
    for index in range(4):
        assert_equal(gram[index // 2, index % 2], expected_gram[index])
        assert_equal(multiplied[index // 2, index % 2], expected_gram[index])
    var vector: List[Complex64] = [Complex64(1.0, -0.5), Complex64(-0.75, 0.25)]
    var product = matrix_vector_multiply(channel, Span(vector))
    assert_equal(product, [Complex64(0.5625, -0.5625), Complex64(-1.0625, 1.1875)])
    var inv = inverse(channel)
    var identity = matrix_multiply(channel, inv)
    for row in range(2):
        for column in range(2):
            _assert_close(identity[row, column].re, 1.0 if row == column else 0.0, 2.0e-12)
            _assert_close(identity[row, column].im, 0.0, 2.0e-12)
    var received: List[Complex64] = [Complex64(0.75, -0.3), Complex64(-1.2, 0.85)]
    var zf = zf_equalize(channel, Span(received))
    var mmse = mmse_equalize(channel, Span(received), 0.17)
    _assert_close(zf[0].re, 1.104201680672269, 2.0e-12)
    _assert_close(mmse[1].im, 0.075852100659645, 2.0e-12)
    var lower = cholesky(gram)
    var reconstructed = matrix_multiply(lower, hermitian(lower))
    for index in range(4):
        _assert_close(reconstructed[index // 2, index % 2].re, expected_gram[index].re, 2.0e-12)
        _assert_close(reconstructed[index // 2, index % 2].im, expected_gram[index].im, 2.0e-12)
    var qr = qr_decompose(channel)
    var qr_reconstructed = matrix_multiply(qr.q, qr.r)
    for row in range(2):
        for column in range(2):
            _assert_close(qr_reconstructed[row, column].re, channel[row, column].re, 2.0e-12)
            _assert_close(qr_reconstructed[row, column].im, channel[row, column].im, 2.0e-12)
    var state = UInt64(0x4D494D4F20260821)
    for _ in range(8):
        var seeded = SmallComplexMatrix(2, 2)
        var seeded_vector = List[Complex64](capacity=2)
        for row in range(2):
            for column in range(2):
                state = state * UInt64(6364136223846793005) + UInt64(1)
                var re = Float64(Int((state >> 57) & 127) - 64) / 128.0
                state = state * UInt64(6364136223846793005) + UInt64(1)
                var im = Float64(Int((state >> 57) & 127) - 64) / 192.0
                if row == column:
                    re += 2.0 + Float64(row)
                seeded[row, column] = Complex64(re, im)
            state = state * UInt64(6364136223846793005) + UInt64(1)
            seeded_vector.append(
                Complex64(Float64(Int((state >> 58) & 63) - 32) / 16.0, 0.25)
            )
        var seeded_product = matrix_vector_multiply(seeded, Span(seeded_vector))
        var seeded_gram = gram_matrix(seeded)
        for row in range(2):
            var scalar = Complex64(0.0, 0.0)
            for column in range(2):
                scalar = scalar + seeded[row, column] * seeded_vector[column]
            _assert_close(seeded_product[row].re, scalar.re, 1.0e-13)
            _assert_close(seeded_product[row].im, scalar.im, 1.0e-13)
        for row in range(2):
            for column in range(2):
                var scalar = Complex64(0.0, 0.0)
                for k in range(2):
                    scalar = scalar + seeded[k, row].conjugate() * seeded[k, column]
                _assert_close(seeded_gram[row, column].re, scalar.re, 1.0e-13)
                _assert_close(seeded_gram[row, column].im, scalar.im, 1.0e-13)
    var singular = SmallComplexMatrix(2, 2)
    with assert_raises():
        _ = inverse(singular)
    with assert_raises():
        _ = qr_decompose(singular)


def test_cpu_mimo_all_entrypoints_against_float64_literals() raises:
    var channel64 = _mimo_static_channel()
    var channel = List[Complex32](capacity=4)
    for value in channel64.values:
        channel.append(Complex32(Float32(value.re), Float32(value.im)))
    var vector: List[Complex32] = [Complex32(1.0, -0.5), Complex32(-0.75, 0.25)]
    var observation: List[Complex32] = [Complex32(0.75, -0.3), Complex32(-1.2, 0.85)]
    var storage = List[Complex32](length=2, fill=Complex32(0.0, 0.0))
    complex_matvec_f32_into(Span(channel), Span(vector), 2, storage)
    assert_equal(complex_matvec_f32(Span(channel), Span(vector), 2), storage)
    _assert_close(Float64(storage[0].re), 0.5625, 0.0)
    var gram_storage = List[Complex32](length=4, fill=Complex32(0.0, 0.0))
    mimo_gram_f32_into(Span(channel), 2, gram_storage)
    assert_equal(mimo_gram_f32(Span(channel), 2), gram_storage)
    _assert_close(Float64(gram_storage[1].im), -0.4375, 0.0)
    var matched = List[Complex32](length=2, fill=Complex32(0.0, 0.0))
    mimo_matched_filter_f32_into(Span(channel), Span(observation), 2, matched)
    assert_equal(mimo_matched_filter_f32(Span(channel), Span(observation), 2), matched)
    _assert_close(Float64(matched[0].re), 1.475, 3.0e-7)
    mimo_gram_matched_f32_into(Span(channel), Span(observation), 2, gram_storage, matched)
    var workspace = make_mimo_workspace_f32(2)
    mimo_zf_f32_into(Span(channel), Span(observation), workspace, storage)
    _assert_close(Float64(storage[0].re), 1.104201680672269, 4.0e-6)
    var zf = mimo_zf_f32(Span(channel), Span(observation), 2)
    _assert_close(Float64(zf[1].im), 0.058823529411765, 4.0e-6)
    mimo_mmse_f32_into(Span(channel), Span(observation), 0.17, workspace, storage)
    _assert_close(Float64(storage[1].im), 0.075852100659645, 4.0e-6)
    var mmse = mimo_mmse_f32(Span(channel), Span(observation), 2, 0.17)
    _assert_close(Float64(mmse[0].re), 0.972556294072, 4.0e-6)
    with assert_raises():
        _ = make_mimo_workspace_f32(3)


def test_cpu_mimo_seeded_scalar_properties_and_all_edges() raises:
    var state = UInt64(0x4350554D494D4F)
    for _ in range(12):
        var channel = List[Complex32](capacity=4)
        var vector = List[Complex32](capacity=2)
        for row in range(2):
            for column in range(2):
                state = state * UInt64(6364136223846793005) + UInt64(1)
                var re = Float32(Int((state >> 59) & 31) - 16) / 32.0
                state = state * UInt64(6364136223846793005) + UInt64(1)
                var im = Float32(Int((state >> 59) & 31) - 16) / 40.0
                if row == column:
                    re += 1.5 + Float32(row)
                channel.append(Complex32(re, im))
            vector.append(Complex32(Float32(row) - 0.25, 0.375 - Float32(row)))
        var expected_product = List[Complex64](capacity=2)
        for row in range(2):
            var acc = Complex64(0.0, 0.0)
            for column in range(2):
                acc = acc + Complex64(Float64(channel[2 * row + column].re), Float64(channel[2 * row + column].im)) * Complex64(Float64(vector[column].re), Float64(vector[column].im))
            expected_product.append(acc)
        var storage = List[Complex32](length=2, fill=Complex32(0.0, 0.0))
        complex_matvec_f32_into(Span(channel), Span(vector), 2, storage)
        var owning = complex_matvec_f32(Span(channel), Span(vector), 2)
        for index in range(2):
            _assert_close(Float64(storage[index].re), expected_product[index].re, 2.0e-6)
            _assert_close(Float64(owning[index].im), expected_product[index].im, 2.0e-6)

        var gram = List[Complex32](length=4, fill=Complex32(0.0, 0.0))
        var matched = List[Complex32](length=2, fill=Complex32(0.0, 0.0))
        mimo_gram_f32_into(Span(channel), 2, gram)
        var owning_gram = mimo_gram_f32(Span(channel), 2)
        mimo_matched_filter_f32_into(Span(channel), Span(vector), 2, matched)
        var owning_matched = mimo_matched_filter_f32(Span(channel), Span(vector), 2)
        mimo_gram_matched_f32_into(Span(channel), Span(vector), 2, gram, matched)
        for row in range(2):
            var expected_matched = Complex64(0.0, 0.0)
            for column in range(2):
                expected_matched = expected_matched + Complex64(Float64(channel[2 * column + row].re), -Float64(channel[2 * column + row].im)) * Complex64(Float64(vector[column].re), Float64(vector[column].im))
            _assert_close(Float64(matched[row].re), expected_matched.re, 3.0e-6)
            _assert_close(Float64(owning_matched[row].im), expected_matched.im, 3.0e-6)
            for column in range(2):
                var expected_gram = Complex64(0.0, 0.0)
                for k in range(2):
                    expected_gram = expected_gram + Complex64(Float64(channel[2 * k + row].re), -Float64(channel[2 * k + row].im)) * Complex64(Float64(channel[2 * k + column].re), Float64(channel[2 * k + column].im))
                var index = 2 * row + column
                _assert_close(Float64(gram[index].re), expected_gram.re, 4.0e-6)
                _assert_close(Float64(owning_gram[index].im), expected_gram.im, 4.0e-6)

    var bad_channel = List[Complex32](length=3, fill=Complex32(0.0, 0.0))
    var vector = List[Complex32](length=2, fill=Complex32(0.0, 0.0))
    var output = List[Complex32](length=2, fill=Complex32(0.0, 0.0))
    var gram_output = List[Complex32](length=4, fill=Complex32(0.0, 0.0))
    var workspace = make_mimo_workspace_f32(2)
    with assert_raises():
        _ = complex_matvec_f32(Span(bad_channel), Span(vector), 2)
    with assert_raises():
        complex_matvec_f32_into(Span(bad_channel), Span(vector), 2, output)
    with assert_raises():
        _ = mimo_gram_f32(Span(bad_channel), 2)
    with assert_raises():
        mimo_gram_f32_into(Span(bad_channel), 2, gram_output)
    with assert_raises():
        _ = mimo_matched_filter_f32(Span(bad_channel), Span(vector), 2)
    with assert_raises():
        mimo_matched_filter_f32_into(Span(bad_channel), Span(vector), 2, output)
    with assert_raises():
        mimo_gram_matched_f32_into(Span(bad_channel), Span(vector), 2, gram_output, output)
    with assert_raises():
        _ = mimo_zf_f32(Span(bad_channel), Span(vector), 2)
    with assert_raises():
        mimo_zf_f32_into(Span(bad_channel), Span(vector), workspace, output)
    with assert_raises():
        _ = mimo_mmse_f32(Span(bad_channel), Span(vector), 2, -0.1)
    with assert_raises():
        mimo_mmse_f32_into(Span(bad_channel), Span(vector), -0.1, workspace, output)


def test_fixed_arithmetic_phy_and_mimo_integer_oracles() raises:
    var q4 = QFormat(8, 4)
    var accumulator = QFormat(20, 8)
    var samples: List[Int64] = [16, 32, 48]
    var taps: List[Int64] = [8, 8]
    assert_equal(fixed_dot_raw(Span(samples)[:2], Span(taps), q4, q4, accumulator, q4), Int64(24))
    assert_equal(fixed_fir_raw(Span(samples), Span(taps), q4, q4, accumulator, q4), [Int64(8), 24, 40])
    var cs: List[ComplexRaw] = [ComplexRaw(16, 16), ComplexRaw(32, 0)]
    var ct: List[ComplexRaw] = [ComplexRaw(0, 16)]
    assert_equal(complex_fir_raw(Span(cs), Span(ct), q4, q4, accumulator, q4), [ComplexRaw(-16, 16), ComplexRaw(0, 32)])
    assert_equal(complex_dot_conjugate_raw(Span(cs)[:1], Span(ct), q4, q4, accumulator, q4), ComplexRaw(16, 16))
    var corr = complex_cross_correlate_raw(Span(cs), Span(ct), q4, q4, accumulator, q4)
    assert_equal(corr, [ComplexRaw(16, -16), ComplexRaw(0, -32)])

    var q8 = QFormat(16, 8)
    var q16 = QFormat(24, 16)
    var fft_values: List[ComplexRaw] = [ComplexRaw(256), ComplexRaw(512), ComplexRaw(768), ComplexRaw(1024)]
    var twiddles = quantized_fft_twiddles(4, q8)
    var stages: List[ScaleStage] = [ScaleStage(q16), ScaleStage(q16)]
    assert_equal(fixed_fft_radix2_raw(Span(fft_values), q8, Span(twiddles), q8, Span(stages)), [ComplexRaw(655360, 0), ComplexRaw(-131072, 131072), ComplexRaw(-131072, 0), ComplexRaw(-131072, -131072)])

    var formats = fixed_phy_default_formats()
    var bits: List[UInt8] = [0, 0, 0, 1, 1, 0, 1, 1]
    var mapped = fixed_qpsk_map_raw(Span(bits), formats.symbol, 8192)
    assert_equal(fixed_qpsk_hard_bits(Span(mapped), formats.symbol), bits)
    assert_equal(fixed_qpsk_llrs_raw(Span(mapped), formats.symbol, formats.symbol), [Int64(8192), 8192, 8192, -8192, -8192, 8192, -8192, -8192])
    var waveform = fixed_ofdm_modulate_raw(Span(mapped), formats.symbol, formats.time, formats.twiddle, 1)
    var bins = fixed_ofdm_demodulate_raw(Span(waveform), 4, 1, formats.time, formats.frequency, formats.twiddle)
    assert_equal(bins, mapped)
    var channel_samples = fixed_flat_channel_raw(Span(waveform), formats.time, ComplexRaw(16384, 0), formats.channel, formats.time)
    var estimate = fixed_ls_flat_channel_raw(Span(bins)[:1], Span(mapped)[:1], formats.frequency, formats.symbol, formats.accumulator, formats.reciprocal, formats.channel)
    var equalized = fixed_equalize_flat_raw(Span(bins), formats.frequency, estimate, formats.channel, formats.accumulator, formats.reciprocal, formats.symbol)
    assert_equal(fixed_qpsk_hard_bits(Span(equalized), formats.symbol), bits)
    assert_true(fixed_reciprocal_positive_raw(Int64(1 << 20), formats.accumulator, formats.reciprocal) > 0)
    var audit = fixed_qpsk_float64_audit(Span(bits), Span(mapped), formats.symbol, 0.5)
    assert_equal(audit.bit_errors, 0)
    assert_equal(audit.evm_rms, 0.0)
    var phy = fixed_phy_one_symbol_reference(Span(bits), 4, 1, ComplexRaw(16384, 0), formats, 8192)
    assert_equal(fixed_phy_result_checksum(phy), UInt64(3268373756385669765))
    assert_true("stage=ifft-registers\n" in fixed_phy_scale_trace_text(4, formats, 8192))
    assert_true("MWDSP-FIXED-PHY-CHECKSUM-V1\n" in fixed_phy_canonical_rtl_vectors(phy, formats))
    assert_equal(len(channel_samples), 5)

    var mf = fixed_mimo_default_formats()
    var h: List[ComplexRaw] = [ComplexRaw(4096, 0), ComplexRaw(), ComplexRaw(), ComplexRaw(4096, 0)]
    var x: List[ComplexRaw] = [ComplexRaw(1024, -512), ComplexRaw(-768, 256)]
    var y = fixed_complex_matvec_2x2_raw(Span(h), Span(x), mf.channel, mf.symbol, mf.accumulator, mf.observation)
    assert_equal(y, x)
    var g = fixed_hermitian_gram_2x2_raw(Span(h), mf.channel, mf.accumulator, mf.gram)
    var matched_mimo = fixed_hermitian_matched_filter_2x2_raw(Span(h), Span(y), mf.channel, mf.observation, mf.accumulator, mf.matched)
    assert_equal(len(g), 4)
    assert_equal(len(matched_mimo), 2)
    var determinant_format = fixed_mimo_determinant_format(mf)
    assert_equal(determinant_format.fraction_bits, 2 * mf.gram.fraction_bits)
    assert_true(fixed_mimo_reciprocal_positive_raw(Int64(1 << 24), determinant_format, mf.reciprocal) > 0)
    var zf = fixed_zf_equalize_2x2_raw(Span(h), Span(y), mf, Int64(1))
    assert_equal(zf.estimates, x)
    assert_true(fixed_mimo_zf_result_checksum(zf) != UInt64(0))
    assert_true(fixed_mimo_zf_scale_trace_text(zf).startswith("MWDSP-FIXED-MIMO-SCALE-TRACE-V1\n"))
    assert_true("MWDSP-FIXED-MIMO-CHECKSUM-V1\n" in fixed_mimo_zf_canonical_rtl_vectors(zf))


def test_fixed_dsp_seeded_integer_formulas_and_edges() raises:
    var q0 = QFormat(8, 0)
    var accumulator = QFormat(24, 0)
    var output = QFormat(16, 0)
    var state = UInt64(0x4649584544445350)
    for _ in range(16):
        var lhs = List[Int64](capacity=7)
        var rhs = List[Int64](capacity=7)
        var complex_lhs = List[ComplexRaw](capacity=7)
        var complex_rhs = List[ComplexRaw](capacity=7)
        var expected_dot = Int64(0)
        var expected_complex_re = Int64(0)
        var expected_complex_im = Int64(0)
        for _ in range(7):
            state = state * UInt64(6364136223846793005) + UInt64(1)
            var a = Int64(Int((state >> 60) & 15) - 8)
            state = state * UInt64(6364136223846793005) + UInt64(1)
            var b = Int64(Int((state >> 60) & 15) - 8)
            state = state * UInt64(6364136223846793005) + UInt64(1)
            var ai = Int64(Int((state >> 60) & 15) - 8)
            state = state * UInt64(6364136223846793005) + UInt64(1)
            var bi = Int64(Int((state >> 60) & 15) - 8)
            lhs.append(a); rhs.append(b)
            complex_lhs.append(ComplexRaw(a, ai)); complex_rhs.append(ComplexRaw(b, bi))
            expected_dot += a * b
            expected_complex_re += a * b + ai * bi
            expected_complex_im += a * bi - ai * b
        assert_equal(fixed_dot_raw(Span(lhs), Span(rhs), q0, q0, accumulator, output), expected_dot)
        assert_equal(complex_dot_conjugate_raw(Span(complex_lhs), Span(complex_rhs), q0, q0, accumulator, output), ComplexRaw(expected_complex_re, expected_complex_im))
        var real_fir = fixed_fir_raw(Span(lhs), Span(rhs)[:3], q0, q0, accumulator, output)
        var complex_fir = complex_fir_raw(Span(complex_lhs), Span(complex_rhs)[:3], q0, q0, accumulator, output)
        for index in range(7):
            var expected_real = Int64(0)
            var expected_re = Int64(0)
            var expected_im = Int64(0)
            for tap in range(min(3, index + 1)):
                var sample = complex_lhs[index - tap]
                var coefficient = complex_rhs[tap]
                expected_real += lhs[index - tap] * rhs[tap]
                expected_re += sample.re * coefficient.re - sample.im * coefficient.im
                expected_im += sample.re * coefficient.im + sample.im * coefficient.re
            assert_equal(real_fir[index], expected_real)
            assert_equal(complex_fir[index], ComplexRaw(expected_re, expected_im))
        var correlation = complex_cross_correlate_raw(Span(complex_lhs), Span(complex_rhs)[:3], q0, q0, accumulator, output)
        for lag in range(len(correlation)):
            var expected_re = Int64(0)
            var expected_im = Int64(0)
            for k in range(3):
                var a = complex_lhs[lag + k]
                var b = complex_rhs[k]
                expected_re += a.re * b.re + a.im * b.im
                expected_im += a.im * b.re - a.re * b.im
            assert_equal(correlation[lag], ComplexRaw(expected_re, expected_im))

        var fft_input = complex_lhs[:4]
        var twiddles = quantized_fft_twiddles(4, q0)
        var stages: List[ScaleStage] = [ScaleStage(output), ScaleStage(output)]
        var spectrum = fixed_fft_radix2_raw(Span(fft_input), q0, Span(twiddles), q0, Span(stages))
        var a = fft_input[0]; var b = fft_input[1]; var c = fft_input[2]; var d = fft_input[3]
        var expected: List[ComplexRaw] = [
            ComplexRaw(a.re + b.re + c.re + d.re, a.im + b.im + c.im + d.im),
            ComplexRaw(a.re - c.re + b.im - d.im, a.im - c.im - b.re + d.re),
            ComplexRaw(a.re - b.re + c.re - d.re, a.im - b.im + c.im - d.im),
            ComplexRaw(a.re - c.re - b.im + d.im, a.im - c.im + b.re - d.re),
        ]
        assert_equal(spectrum, expected)

    var empty_i64 = List[Int64]()
    var one_i64: List[Int64] = [1]
    with assert_raises():
        _ = fixed_dot_raw(Span(empty_i64), Span(one_i64), q0, q0, accumulator, output)
    with assert_raises():
        _ = fixed_fir_raw(Span(one_i64), Span(empty_i64), q0, q0, accumulator, output)
    var empty_complex = List[ComplexRaw]()
    var one_complex: List[ComplexRaw] = [ComplexRaw(1, 0)]
    with assert_raises():
        _ = complex_dot_conjugate_raw(Span(empty_complex), Span(one_complex), q0, q0, accumulator, output)
    with assert_raises():
        _ = complex_fir_raw(Span(one_complex), Span(empty_complex), q0, q0, accumulator, output)
    assert_equal(len(complex_cross_correlate_raw(Span(empty_complex), Span(one_complex), q0, q0, accumulator, output)), 0)
    with assert_raises():
        _ = quantized_fft_twiddles(3, q0)
    var twiddles: List[ComplexRaw] = [ComplexRaw(1, 0), ComplexRaw(0, -1)]
    var bad_stages: List[ScaleStage] = [ScaleStage(output)]
    var four = List[ComplexRaw](length=4, fill=ComplexRaw())
    with assert_raises():
        _ = fixed_fft_radix2_raw(Span(four), q0, Span(twiddles), q0, Span(bad_stages))


def test_fixed_phy_mimo_sync_wifi_seeded_formulas_and_edges() raises:
    var formats = fixed_phy_default_formats()
    var state = UInt64(0x5048594D494D4F)
    for _ in range(12):
        var bits = List[UInt8](capacity=8)
        for _ in range(8):
            state = state * UInt64(6364136223846793005) + UInt64(1)
            bits.append(UInt8((state >> 63) & 1))
        var mapped = fixed_qpsk_map_raw(Span(bits), formats.symbol, 8192)
        var hard = fixed_qpsk_hard_bits(Span(mapped), formats.symbol)
        var llrs = fixed_qpsk_llrs_raw(Span(mapped), formats.symbol, formats.symbol)
        assert_equal(hard, bits)
        for index in range(4):
            var expected_re = Int64(-8192 if bits[2 * index] == 1 else 8192)
            var expected_im = Int64(-8192 if bits[2 * index + 1] == 1 else 8192)
            assert_equal(mapped[index], ComplexRaw(expected_re, expected_im))
            assert_equal(llrs[2 * index], expected_re)
            assert_equal(llrs[2 * index + 1], expected_im)

        # Independent closed-form four-point IFFT, including exact 1/4 scale.
        var x0 = mapped[0]; var x1 = mapped[1]; var x2 = mapped[2]; var x3 = mapped[3]
        var expected_time: List[ComplexRaw] = [
            ComplexRaw((x0.re + x1.re + x2.re + x3.re) // 4, (x0.im + x1.im + x2.im + x3.im) // 4),
            ComplexRaw((x0.re - x1.im - x2.re + x3.im) // 4, (x0.im + x1.re - x2.im - x3.re) // 4),
            ComplexRaw((x0.re - x1.re + x2.re - x3.re) // 4, (x0.im - x1.im + x2.im - x3.im) // 4),
            ComplexRaw((x0.re + x1.im - x2.re - x3.im) // 4, (x0.im - x1.re - x2.im + x3.re) // 4),
        ]
        var waveform = fixed_ofdm_modulate_raw(Span(mapped), formats.symbol, formats.time, formats.twiddle, 1)
        assert_equal(waveform[0], expected_time[3])
        for index in range(4):
            assert_equal(waveform[index + 1], expected_time[index])
        var bins = fixed_ofdm_demodulate_raw(Span(waveform), 4, 1, formats.time, formats.frequency, formats.twiddle)
        # Direct independent four-point DFT oracle over the actual time words.
        var t0 = expected_time[0]; var t1 = expected_time[1]; var t2 = expected_time[2]; var t3 = expected_time[3]
        var expected_bins: List[ComplexRaw] = [
            ComplexRaw(t0.re + t1.re + t2.re + t3.re, t0.im + t1.im + t2.im + t3.im),
            ComplexRaw(t0.re + t1.im - t2.re - t3.im, t0.im - t1.re - t2.im + t3.re),
            ComplexRaw(t0.re - t1.re + t2.re - t3.re, t0.im - t1.im + t2.im - t3.im),
            ComplexRaw(t0.re - t1.im - t2.re + t3.im, t0.im + t1.re - t2.im - t3.re),
        ]
        assert_equal(bins, expected_bins)

        var identity_channel = ComplexRaw(16384, 0)
        var through = fixed_flat_channel_raw(Span(waveform), formats.time, identity_channel, formats.channel, formats.time)
        assert_equal(through, waveform)
        var estimate = fixed_ls_flat_channel_raw(Span(bins)[:2], Span(mapped)[:2], formats.frequency, formats.symbol, formats.accumulator, formats.reciprocal, formats.channel)
        assert_equal(estimate, identity_channel)
        var equalized = fixed_equalize_flat_raw(Span(bins), formats.frequency, estimate, formats.channel, formats.accumulator, formats.reciprocal, formats.symbol)
        assert_equal(equalized, mapped)
        var audit = fixed_qpsk_float64_audit(Span(bits), Span(mapped), formats.symbol, 0.5)
        assert_equal(audit.bit_errors, 0)
        assert_equal(audit.evm_rms, 0.0)

        var mf = fixed_mimo_default_formats()
        var channel: List[ComplexRaw] = [ComplexRaw(4096, 0), ComplexRaw(), ComplexRaw(), ComplexRaw(4096, 0)]
        var symbols: List[ComplexRaw] = [mapped[0], mapped[1]]
        var observation = fixed_complex_matvec_2x2_raw(Span(channel), Span(symbols), mf.channel, mf.symbol, mf.accumulator, mf.observation)
        assert_equal(observation, symbols)
        var gram = fixed_hermitian_gram_2x2_raw(Span(channel), mf.channel, mf.accumulator, mf.gram)
        assert_equal(gram, [ComplexRaw(65536, 0), ComplexRaw(), ComplexRaw(), ComplexRaw(65536, 0)])
        var matched = fixed_hermitian_matched_filter_2x2_raw(Span(channel), Span(observation), mf.channel, mf.observation, mf.accumulator, mf.matched)
        assert_equal(matched[0].re, symbols[0].re << 4)
        var solved = fixed_zf_equalize_2x2_raw(Span(channel), Span(observation), mf, 1)
        assert_equal(solved.estimates, symbols)

    var q4 = QFormat(8, 4)
    var acc = QFormat(24, 8)
    var sync_out = QFormat(16, 8)
    var sync_samples = List[ComplexRaw](capacity=24)
    for index in range(12):
        state = state * UInt64(6364136223846793005) + UInt64(1)
        var value = ComplexRaw(Int64(Int((state >> 60) & 15) - 8), Int64(index % 7 - 3))
        sync_samples.append(value)
    for index in range(12):
        sync_samples.append(sync_samples[index])
    var scan = fixed_repetition_scan_raw(Span(sync_samples), 12, 12, q4, acc, sync_out)
    var expected_energy = Int64(0)
    for index in range(12):
        expected_energy += sync_samples[index].re * sync_samples[index].re + sync_samples[index].im * sync_samples[index].im
    assert_equal(fixed_window_energy_raw(Span(sync_samples), 0, 12, q4, acc, sync_out), expected_energy)
    assert_equal(fixed_repetition_correlation_raw(Span(sync_samples), 0, 12, 12, q4, acc, sync_out), ComplexRaw(expected_energy, 0))
    assert_equal(scan.peak_offset, 0)

    for length in range(1, 10):
        var payload = List[UInt8](capacity=length)
        for _ in range(length):
            state = state * UInt64(6364136223846793005) + UInt64(1)
            payload.append(UInt8((state >> 63) & 1))
        var expected_coded = _independent_bcc(Span(payload))
        var coded = fixed_wifi_bcc_encode(Span(payload))
        assert_equal(coded, expected_coded)
        var llrs = fixed_wifi_bcc_hard_llrs_raw(Span(coded), 7, QFormat(8, 0))
        for index in range(len(coded)):
            assert_equal(llrs[index], Int64(7 if coded[index] == 0 else -7))
        assert_equal(fixed_wifi_bcc_viterbi_decode_hard(Span(coded)).bits, payload)
        assert_equal(fixed_wifi_bcc_viterbi_decode_soft(Span(llrs), FixedWifiBCCViterbiConfig(QFormat(8, 0), 16)).bits, payload)

    var empty_bits = List[UInt8]()
    var odd_bits: List[UInt8] = [0, 1, 0]
    with assert_raises():
        _ = fixed_qpsk_map_raw(Span(odd_bits), formats.symbol, 8192)
    var zero_channel = ComplexRaw()
    var one_symbol: List[ComplexRaw] = [ComplexRaw(8192, 0)]
    var one_symbol_copy = one_symbol.copy()
    with assert_raises():
        _ = fixed_equalize_flat_raw(Span(one_symbol), formats.symbol, zero_channel, formats.channel, formats.accumulator, formats.reciprocal, formats.symbol)
    with assert_raises():
        _ = fixed_reciprocal_positive_raw(0, formats.accumulator, formats.reciprocal)
    with assert_raises():
        _ = fixed_ls_flat_channel_raw(Span(one_symbol), Span(List[ComplexRaw]()), formats.symbol, formats.symbol, formats.accumulator, formats.reciprocal, formats.channel)
    with assert_raises():
        _ = fixed_ofdm_modulate_raw(Span(one_symbol), formats.symbol, formats.time, formats.twiddle, 0)
    with assert_raises():
        _ = fixed_ofdm_demodulate_raw(Span(one_symbol), 4, 1, formats.time, formats.frequency, formats.twiddle)
    assert_equal(len(fixed_flat_channel_raw(Span(List[ComplexRaw]()), formats.time, ComplexRaw(16384, 0), formats.channel, formats.time)), 0)
    with assert_raises():
        _ = fixed_qpsk_float64_audit(Span(empty_bits), Span(List[ComplexRaw]()), formats.symbol, 0.5)
    with assert_raises():
        _ = fixed_phy_one_symbol_reference(Span(empty_bits), 4, 1, ComplexRaw(16384, 0), formats, 8192)
    var mf = fixed_mimo_default_formats()
    with assert_raises():
        _ = fixed_mimo_reciprocal_positive_raw(0, fixed_mimo_determinant_format(mf), mf.reciprocal)
    with assert_raises():
        _ = fixed_complex_matvec_2x2_raw(Span(one_symbol), Span(one_symbol_copy), mf.channel, mf.symbol, mf.accumulator, mf.observation)
    with assert_raises():
        _ = fixed_hermitian_gram_2x2_raw(Span(one_symbol), mf.channel, mf.accumulator, mf.gram)
    with assert_raises():
        _ = fixed_hermitian_matched_filter_2x2_raw(Span(one_symbol), Span(one_symbol_copy), mf.channel, mf.observation, mf.accumulator, mf.matched)
    with assert_raises():
        _ = fixed_zf_equalize_2x2_raw(Span(one_symbol), Span(one_symbol_copy), mf, 1)
    with assert_raises():
        _ = fixed_window_energy_raw(Span(one_symbol), 1, 1, q4, acc, sync_out)
    with assert_raises():
        _ = fixed_repetition_correlation_raw(Span(one_symbol), 0, 1, 1, q4, acc, sync_out)
    with assert_raises():
        _ = fixed_repetition_scan_raw(Span(one_symbol), 1, 1, q4, acc, sync_out)
    var invalid_bit: List[UInt8] = [2]
    with assert_raises():
        _ = fixed_wifi_bcc_encode(Span(invalid_bit))
    with assert_raises():
        _ = fixed_wifi_bcc_hard_llrs_raw(Span(invalid_bit), 7, QFormat(8, 0))
    var odd_coded: List[UInt8] = [0]
    with assert_raises():
        _ = fixed_wifi_bcc_viterbi_decode_hard(Span(odd_coded), terminate=False)
    var odd_llrs: List[Int64] = [1]
    with assert_raises():
        _ = fixed_wifi_bcc_viterbi_decode_soft(Span(odd_llrs), FixedWifiBCCViterbiConfig(QFormat(8, 0), 16), terminate=False)
    with assert_raises():
        _ = fixed_wifi_bcc_ofdm_reference(Span(empty_bits), 64, 16, ComplexRaw(16384, 0), formats, 8192)
    with assert_raises():
        _ = fixed_phy_scale_trace_text(3, formats, 8192)


def test_fixed_config_and_artifact_determinism_and_edges() raises:
    var first_phy_formats = fixed_phy_default_formats()
    var second_phy_formats = fixed_phy_default_formats()
    assert_equal(first_phy_formats.symbol.storage_bits, second_phy_formats.symbol.storage_bits)
    assert_equal(first_phy_formats.twiddle.fraction_bits, second_phy_formats.twiddle.fraction_bits)
    var first_mimo_formats = fixed_mimo_default_formats()
    var second_mimo_formats = fixed_mimo_default_formats()
    assert_equal(first_mimo_formats.gram.storage_bits, second_mimo_formats.gram.storage_bits)
    assert_equal(first_mimo_formats.output.fraction_bits, second_mimo_formats.output.fraction_bits)
    assert_equal(fixed_mimo_determinant_format(first_mimo_formats).fraction_bits, 2 * first_mimo_formats.gram.fraction_bits)
    var bad_gram = QFormat(32, 16)
    var bad_formats = FixedMIMOFormats(
        first_mimo_formats.channel,
        first_mimo_formats.symbol,
        first_mimo_formats.observation,
        first_mimo_formats.accumulator,
        bad_gram,
        first_mimo_formats.matched,
        first_mimo_formats.numerator,
        first_mimo_formats.reciprocal,
        first_mimo_formats.output,
    )
    with assert_raises():
        _ = fixed_mimo_determinant_format(bad_formats)
    assert_equal(quantized_fft_twiddles(2, QFormat(8, 6)), [ComplexRaw(64, 0)])
    assert_equal(len(quantized_fft_twiddles(1, QFormat(8, 6))), 0)

    var bits: List[UInt8] = [0, 0, 0, 1, 1, 0, 1, 1]
    var first_phy = fixed_phy_one_symbol_reference(Span(bits), 4, 1, ComplexRaw(16384, 0), first_phy_formats, 8192)
    var first_phy_checksum = fixed_phy_result_checksum(first_phy)
    assert_equal(fixed_phy_result_checksum(first_phy), first_phy_checksum)
    var first_phy_trace = fixed_phy_scale_trace_text(4, first_phy_formats, 8192)
    assert_equal(fixed_phy_scale_trace_text(4, first_phy_formats, 8192), first_phy_trace)
    var first_phy_vectors = fixed_phy_canonical_rtl_vectors(first_phy, first_phy_formats)
    assert_equal(fixed_phy_canonical_rtl_vectors(first_phy, first_phy_formats), first_phy_vectors)
    var invalid_phy = fixed_phy_one_symbol_reference(Span(bits), 4, 1, ComplexRaw(16384, 0), first_phy_formats, 8192)
    invalid_phy.mapped_symbols[0] = ComplexRaw(Int64(1 << 30), 0)
    assert_true(fixed_phy_result_checksum(invalid_phy) != UInt64(0))
    with assert_raises():
        _ = fixed_phy_canonical_rtl_vectors(invalid_phy, first_phy_formats)
    with assert_raises():
        _ = fixed_phy_scale_trace_text(1, first_phy_formats, 8192)

    var channel: List[ComplexRaw] = [ComplexRaw(4096, 0), ComplexRaw(), ComplexRaw(), ComplexRaw(4096, 0)]
    var symbols: List[ComplexRaw] = [ComplexRaw(1024, -512), ComplexRaw(-768, 256)]
    var observation = fixed_complex_matvec_2x2_raw(Span(channel), Span(symbols), first_mimo_formats.channel, first_mimo_formats.symbol, first_mimo_formats.accumulator, first_mimo_formats.observation)
    var first_zf = fixed_zf_equalize_2x2_raw(Span(channel), Span(observation), first_mimo_formats, 1)
    var first_zf_checksum = fixed_mimo_zf_result_checksum(first_zf)
    assert_equal(fixed_mimo_zf_result_checksum(first_zf), first_zf_checksum)
    var first_zf_trace = fixed_mimo_zf_scale_trace_text(first_zf)
    assert_equal(fixed_mimo_zf_scale_trace_text(first_zf), first_zf_trace)
    var first_zf_vectors = fixed_mimo_zf_canonical_rtl_vectors(first_zf)
    assert_equal(fixed_mimo_zf_canonical_rtl_vectors(first_zf), first_zf_vectors)
    var invalid_zf = fixed_zf_equalize_2x2_raw(Span(channel), Span(observation), first_mimo_formats, 1)
    invalid_zf.estimates = List[ComplexRaw]()
    # Checksums are total over checkpoint lists; empty is their meaningful edge.
    assert_true(fixed_mimo_zf_result_checksum(invalid_zf) != UInt64(0))
    with assert_raises():
        _ = fixed_mimo_zf_scale_trace_text(invalid_zf)
    with assert_raises():
        _ = fixed_mimo_zf_canonical_rtl_vectors(invalid_zf)

    var sync_samples: List[ComplexRaw] = [ComplexRaw(1, 0), ComplexRaw(1, 0)]
    var sync = fixed_repetition_scan_raw(Span(sync_samples), 1, 1, QFormat(8, 0), QFormat(16, 0), QFormat(16, 0))
    var sync_checksum = fixed_repetition_scan_checksum(sync)
    assert_equal(fixed_repetition_scan_checksum(sync), sync_checksum)
    var sync_vectors = fixed_repetition_canonical_rtl_vectors(sync, QFormat(16, 0))
    assert_equal(fixed_repetition_canonical_rtl_vectors(sync, QFormat(16, 0)), sync_vectors)

    var empty_payload = List[UInt8]()
    var coded = fixed_wifi_bcc_encode(Span(empty_payload))
    var llr_format = QFormat(8, 0)
    var llrs = fixed_wifi_bcc_hard_llrs_raw(Span(coded), 7, llr_format)
    var hard = fixed_wifi_bcc_viterbi_decode_hard(Span(coded))
    var soft = fixed_wifi_bcc_viterbi_decode_soft(Span(llrs), FixedWifiBCCViterbiConfig(llr_format, 16))
    var bcc_checksum = fixed_wifi_bcc_result_checksum(Span(empty_payload), Span(coded), Span(llrs), llr_format, hard, soft)
    assert_equal(fixed_wifi_bcc_result_checksum(Span(empty_payload), Span(coded), Span(llrs), llr_format, hard, soft), bcc_checksum)
    var bcc_vectors = fixed_wifi_bcc_canonical_rtl_vectors(Span(empty_payload), Span(coded), Span(llrs), llr_format, hard, soft)
    assert_equal(fixed_wifi_bcc_canonical_rtl_vectors(Span(empty_payload), Span(coded), Span(llrs), llr_format, hard, soft), bcc_vectors)
    var short_llrs = llrs[:len(llrs) - 1]
    with assert_raises():
        _ = fixed_wifi_bcc_canonical_rtl_vectors(Span(empty_payload), Span(coded), Span(short_llrs), llr_format, hard, soft)

    var payload58 = List[UInt8](capacity=58)
    for index in range(58):
        payload58.append(UInt8((index * 13 + index // 5 + 1) & 1))
    var wifi = fixed_wifi_bcc_ofdm_reference(Span(payload58), 64, 16, ComplexRaw(16384, 0), first_phy_formats, 8192)
    var wifi_checksum = fixed_wifi_phy_result_checksum(wifi, first_phy_formats.symbol)
    assert_equal(fixed_wifi_phy_result_checksum(wifi, first_phy_formats.symbol), wifi_checksum)
    var wifi_vectors = fixed_wifi_phy_canonical_rtl_vectors(wifi, first_phy_formats)
    assert_equal(fixed_wifi_phy_canonical_rtl_vectors(wifi, first_phy_formats), wifi_vectors)
    with assert_raises():
        _ = fixed_wifi_phy_canonical_rtl_vectors(wifi, FixedPHYFormats(
            QFormat(2, 0), QFormat(2, 0), QFormat(2, 0), QFormat(2, 0),
            QFormat(4, 0), QFormat(4, 0), QFormat(4, 0),
        ))


def test_fixed_sync_and_wifi_fec_direct_static_evidence() raises:
    var sample_format = QFormat(8, 4)
    var accumulator_format = QFormat(24, 8)
    var output_format = QFormat(16, 8)
    var samples: List[ComplexRaw] = [ComplexRaw(16, 0), ComplexRaw(0, 16), ComplexRaw(-16, 0), ComplexRaw(0, -16), ComplexRaw(16, 0), ComplexRaw(0, 16), ComplexRaw(-16, 0), ComplexRaw(0, -16)]
    assert_equal(fixed_window_energy_raw(Span(samples), 0, 4, sample_format, accumulator_format, output_format), Int64(1024))
    assert_equal(fixed_repetition_correlation_raw(Span(samples), 0, 4, 4, sample_format, accumulator_format, output_format), ComplexRaw(1024, 0))
    var scan = fixed_repetition_scan_raw(Span(samples), 4, 4, sample_format, accumulator_format, output_format)
    assert_equal(fixed_repetition_scan_checksum(scan), UInt64(5897863583741909833))
    assert_true("MWDSP-FIXED-SYNC-CHECKSUM-V1\n" in fixed_repetition_canonical_rtl_vectors(scan, output_format))

    var payload: List[UInt8] = [1, 0, 1, 1, 0, 0, 1, 0]
    var coded = fixed_wifi_bcc_encode(Span(payload))
    var llr_format = QFormat(8, 0)
    var hard_llrs = fixed_wifi_bcc_hard_llrs_raw(Span(coded), 7, llr_format)
    var hard = fixed_wifi_bcc_viterbi_decode_hard(Span(coded))
    var soft = fixed_wifi_bcc_viterbi_decode_soft(Span(hard_llrs), FixedWifiBCCViterbiConfig(llr_format, 16))
    assert_equal(hard.bits, payload)
    assert_equal(soft.bits, payload)
    var bcc_checksum = fixed_wifi_bcc_result_checksum(Span(payload), Span(coded), Span(hard_llrs), llr_format, hard, soft)
    assert_true(bcc_checksum != UInt64(0))
    assert_true("MWDSP-WIFI-BCC-CHECKSUM-V1\n" in fixed_wifi_bcc_canonical_rtl_vectors(Span(payload), Span(coded), Span(hard_llrs), llr_format, hard, soft))

    var payload58 = List[UInt8](capacity=58)
    for index in range(58):
        payload58.append(UInt8((index * 13 + index // 5 + 1) & 1))
    var phy_formats = fixed_phy_default_formats()
    var wifi = fixed_wifi_bcc_ofdm_reference(Span(payload58), 64, 16, ComplexRaw(16384, 0), phy_formats, 8192)
    assert_equal(wifi.payload_bit_errors, 0)
    assert_true(fixed_wifi_phy_result_checksum(wifi, phy_formats.symbol) != UInt64(0))
    assert_true("MWDSP-FIXED-WIFI-PHY-CHECKSUM-V1\n" in fixed_wifi_phy_canonical_rtl_vectors(wifi, phy_formats))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
