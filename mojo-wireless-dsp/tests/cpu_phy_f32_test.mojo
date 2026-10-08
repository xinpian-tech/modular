"""Strict Float32 OFDM and SISO PHY evidence.

The suite covers deterministic literals, all production FFT sizes, seeded
properties, independent Float64/analytic differentials, workspace reuse and
non-aliasing, and the finite binary32 boundary contract.
"""

from std.collections import Span
from std.math import cos, isfinite, sin
from std.testing import assert_equal, assert_raises, assert_true, TestSuite
from std.utils.numerics import inf, nan
from wireless_dsp.core import Complex32, Complex64
from wireless_dsp.dsp.estimation import (
    common_phase_error,
    estimate_pilot_noise_variance,
    ls_channel_estimate,
    mmse_equalize_siso,
    zero_forcing_equalize_siso,
)
from wireless_dsp.dsp.ofdm import ofdm_demodulate, ofdm_modulate
from wireless_dsp.backend.cpu.practical import make_fft_plan_f32
from wireless_dsp.backend.cpu.phy_practical import (
    OFDMWorkspaceF32,
    common_phase_error_f32,
    complex_divide_f32,
    correct_common_phase_error_f32,
    correct_common_phase_error_f32_into,
    estimate_pilot_noise_variance_f32,
    ls_channel_estimate_f32,
    ls_channel_estimate_f32_into,
    make_ofdm_workspace_f32,
    mmse_equalize_siso_f32,
    mmse_equalize_siso_f32_into,
    ofdm_demodulate_f32,
    ofdm_demodulate_f32_into,
    ofdm_modulate_f32,
    ofdm_modulate_f32_into,
    zero_forcing_equalize_siso_f32,
    zero_forcing_equalize_siso_f32_into,
)


def _next_uniform_f32(mut state: UInt64) -> Float32:
    state = state * UInt64(6364136223846793005) + UInt64(1442695040888963407)
    return Float32(state >> UInt64(40)) / Float32(1 << 24)


def _seeded_complex32(
    length: Int, mut state: UInt64, *, floor: Float32 = Float32(0.0)
) -> List[Complex32]:
    var result = List[Complex32](capacity=length)
    for _ in range(length):
        var real = Float32(2.0) * _next_uniform_f32(state) - Float32(1.0)
        var imaginary = Float32(2.0) * _next_uniform_f32(state) - Float32(1.0)
        if floor != 0.0:
            real += floor if real >= 0.0 else -floor
            imaginary += Float32(0.5) * floor
        result.append(Complex32(real, imaginary))
    return result^


def _as_complex64(values: Span[Complex32, ...]) -> List[Complex64]:
    var result = List[Complex64](capacity=len(values))
    for index in range(len(values)):
        result.append(Complex64(
            Float64(values[index].re), Float64(values[index].im)
        ))
    return result^


def _assert_scalar_close(
    actual: Float64,
    expected: Float64,
    absolute_tolerance: Float64,
    relative_tolerance: Float64,
) raises:
    assert_true(
        abs(actual - expected)
        <= absolute_tolerance + relative_tolerance * abs(expected)
    )


def _assert_complex_close(
    actual: Complex32,
    expected: Complex64,
    absolute_tolerance: Float64,
    relative_tolerance: Float64,
) raises:
    _assert_scalar_close(
        Float64(actual.re),
        expected.re,
        absolute_tolerance,
        relative_tolerance,
    )
    _assert_scalar_close(
        Float64(actual.im),
        expected.im,
        absolute_tolerance,
        relative_tolerance,
    )


def _assert_vector_close(
    actual: Span[Complex32, ...],
    expected: Span[Complex64, ...],
    absolute_tolerance: Float64,
    relative_tolerance: Float64,
) raises:
    assert_equal(len(actual), len(expected))
    for index in range(len(actual)):
        _assert_complex_close(
            Complex32(actual[index].re, actual[index].im),
            Complex64(expected[index].re, expected[index].im),
            absolute_tolerance,
            relative_tolerance,
        )


def _multiply_f32(lhs: Complex32, rhs: Complex32) -> Complex32:
    return Complex32(
        lhs.re * rhs.re - lhs.im * rhs.im,
        lhs.re * rhs.im + lhs.im * rhs.re,
    )


def test_make_ofdm_workspace_f32_exact_storage_and_int_edges() raises:
    for size in [64, 128, 256, 512, 1024, 2048, 4096]:
        var first = make_ofdm_workspace_f32(size)
        var second = make_ofdm_workspace_f32(size)
        assert_equal(first.size, size)
        assert_equal(len(first.scratch), size)
        assert_equal(first.scratch, second.scratch)
        for value in first.scratch:
            assert_equal(value, Complex32(0.0, 0.0))
        first.scratch[0] = Complex32(1.0, -2.0)
        assert_equal(second.scratch[0], Complex32(0.0, 0.0))
    with assert_raises():
        _ = make_ofdm_workspace_f32(Int.MIN)
    with assert_raises():
        _ = make_ofdm_workspace_f32(Int.MAX)


def test_ofdm_all_required_sizes_float64_differential_and_roundtrip() raises:
    var seed = UInt64(0x5F32_0FD0_2026)
    for size in [64, 128, 256, 512, 1024, 2048, 4096]:
        var cyclic_prefix = size // 16
        var spectrum = _seeded_complex32(size, seed)
        var original = spectrum.copy()
        var spectrum64 = _as_complex64(Span(spectrum))
        var expected_time = ofdm_modulate(Span(spectrum64), cyclic_prefix)

        var inverse_plan = make_fft_plan_f32(size, inverse=True)
        var forward_plan = make_fft_plan_f32(size)
        var workspace = make_ofdm_workspace_f32(size)
        var time = List[Complex32](
            length=size + cyclic_prefix, fill=Complex32(99.0, -99.0)
        )
        ofdm_modulate_f32_into(
            Span(spectrum), cyclic_prefix, inverse_plan, workspace, time
        )
        _assert_vector_close(Span(time), Span(expected_time), 8.0e-7, 8.0e-6)
        var owning_time = ofdm_modulate_f32(
            Span(spectrum), cyclic_prefix
        )
        _assert_vector_close(
            Span(owning_time), Span(expected_time), 8.0e-7, 8.0e-6
        )
        assert_equal(spectrum, original)
        for index in range(cyclic_prefix):
            assert_equal(time[index], time[size + index])

        var restored = List[Complex32](
            length=size, fill=Complex32(77.0, -77.0)
        )
        ofdm_demodulate_f32_into(
            Span(time), size, cyclic_prefix, forward_plan, workspace, restored
        )
        var owning_restored = ofdm_demodulate_f32(
            Span(time), size, cyclic_prefix
        )
        var roundtrip_absolute = 3.0e-5 + 8.0e-7 * Float64(size)
        _assert_vector_close(
            Span(restored), Span(spectrum64), roundtrip_absolute, 3.0e-4
        )
        _assert_vector_close(
            Span(owning_restored),
            Span(spectrum64),
            roundtrip_absolute,
            3.0e-4,
        )

        # Reuse both plans and the same scratch for an independent symbol.
        var second = _seeded_complex32(size, seed)
        var second64 = _as_complex64(Span(second))
        var expected_second = ofdm_modulate(Span(second64), cyclic_prefix)
        ofdm_modulate_f32_into(
            Span(second), cyclic_prefix, inverse_plan, workspace, time
        )
        _assert_vector_close(
            Span(time), Span(expected_second), 8.0e-7, 8.0e-6
        )


def test_ofdm_analytic_normalization_cp_owning_and_nonalias() raises:
    comptime size = 64
    comptime cyclic_prefix = 16
    var spectrum = List[Complex32](
        length=size, fill=Complex32(0.0, 0.0)
    )
    spectrum[0] = Complex32(8.0, -4.0)
    var snapshot = spectrum.copy()
    var time = ofdm_modulate_f32(Span(spectrum), cyclic_prefix)
    assert_equal(len(time), size + cyclic_prefix)
    for value in time:
        assert_equal(value, Complex32(0.125, -0.0625))
    assert_equal(spectrum, snapshot)

    # Owning output and input are independent in both directions.
    time[0] = Complex32(123.0, -456.0)
    assert_equal(spectrum, snapshot)
    time[0] = time[size]
    var restored = ofdm_demodulate_f32(Span(time), size, cyclic_prefix)
    assert_equal(restored, spectrum)
    restored[0] = Complex32(-1.0, 2.0)
    assert_equal(time[size], Complex32(0.125, -0.0625))

    var inverse_plan = make_fft_plan_f32(size, inverse=True)
    var workspace = make_ofdm_workspace_f32(size)
    var output = List[Complex32](
        length=size + cyclic_prefix, fill=Complex32(0.0, 0.0)
    )
    ofdm_modulate_f32_into(
        Span(spectrum), cyclic_prefix, inverse_plan, workspace, output
    )
    var output_snapshot = output.copy()
    workspace.scratch[0] = Complex32(999.0, -999.0)
    assert_equal(output, output_snapshot)
    var forward_plan = make_fft_plan_f32(size)
    var demodulated_output = List[Complex32](
        length=size, fill=Complex32(0.0, 0.0)
    )
    ofdm_demodulate_f32_into(
        Span(output),
        size,
        cyclic_prefix,
        forward_plan,
        workspace,
        demodulated_output,
    )
    assert_equal(demodulated_output, spectrum)


def test_ofdm_extreme_finite_common_scaling() raises:
    comptime size = 64
    var huge = Float32(3.0e38)
    var spectrum = List[Complex32](
        length=size, fill=Complex32(huge, 0.0)
    )
    var time = ofdm_modulate_f32(Span(spectrum), 0)
    assert_equal(time[0], Complex32(huge, 0.0))
    for index in range(1, size):
        assert_equal(time[index], Complex32(0.0, 0.0))

    var impulse = List[Complex32](
        length=size, fill=Complex32(0.0, 0.0)
    )
    impulse[0] = Complex32(huge, -huge)
    var extreme_spectrum = ofdm_demodulate_f32(Span(impulse), size, 0)
    for value in extreme_spectrum:
        assert_equal(value, Complex32(huge, -huge))

    var minimum_subnormal = Float32(1.0e-38)
    var tiny_spectrum = List[Complex32](
        length=size, fill=Complex32(minimum_subnormal, 0.0)
    )
    var tiny_time = ofdm_modulate_f32(Span(tiny_spectrum), 0)
    assert_equal(tiny_time[0], Complex32(minimum_subnormal, 0.0))
    for index in range(1, size):
        assert_equal(tiny_time[index], Complex32(0.0, 0.0))

    var zeros = List[Complex32](
        length=size, fill=Complex32(0.0, 0.0)
    )
    assert_equal(ofdm_modulate_f32(Span(zeros), 0), zeros)
    assert_equal(ofdm_demodulate_f32(Span(zeros), size, 0), zeros)


def test_ofdm_validation_nonfinite_malformed_and_unrepresentable() raises:
    var unsupported = List[Complex32](
        length=32, fill=Complex32(0.0, 0.0)
    )
    with assert_raises():
        _ = make_ofdm_workspace_f32(32)
    with assert_raises():
        _ = ofdm_modulate_f32(Span(unsupported), 0)

    comptime size = 64
    var values = List[Complex32](
        length=size, fill=Complex32(0.0, 0.0)
    )
    with assert_raises():
        _ = ofdm_modulate_f32(Span(values), -1)
    with assert_raises():
        _ = ofdm_modulate_f32(Span(values), size + 1)
    var short_samples = List[Complex32](
        length=size - 1, fill=Complex32(0.0, 0.0)
    )
    with assert_raises():
        _ = ofdm_demodulate_f32(Span(short_samples), size, 0)

    var workspace = make_ofdm_workspace_f32(size)
    var inverse_plan = make_fft_plan_f32(size, inverse=True)
    var forward_plan = make_fft_plan_f32(size)
    var modulated_output = List[Complex32](
        length=size, fill=Complex32(0.0, 0.0)
    )
    with assert_raises():
        ofdm_modulate_f32_into(
            Span(values), 0, forward_plan, workspace, modulated_output
        )
    var malformed_plan = make_fft_plan_f32(size, inverse=True)
    malformed_plan.twiddles.append(Complex32(1.0, 0.0))
    with assert_raises():
        ofdm_modulate_f32_into(
            Span(values), 0, malformed_plan, workspace, modulated_output
        )
    var nonfinite_plan = make_fft_plan_f32(size, inverse=True)
    nonfinite_plan.twiddles[0] = Complex32(nan[DType.float32](), 0.0)
    with assert_raises():
        ofdm_modulate_f32_into(
            Span(values), 0, nonfinite_plan, workspace, modulated_output
        )
    var wrong_output = List[Complex32](
        length=size - 1, fill=Complex32(0.0, 0.0)
    )
    with assert_raises():
        ofdm_modulate_f32_into(
            Span(values), 0, inverse_plan, workspace, wrong_output
        )
    var demodulated_output = List[Complex32](
        length=size, fill=Complex32(0.0, 0.0)
    )
    with assert_raises():
        ofdm_demodulate_f32_into(
            Span(values),
            size,
            0,
            inverse_plan,
            workspace,
            demodulated_output,
        )
    with assert_raises():
        ofdm_demodulate_f32_into(
            Span(values), size, 0, forward_plan, workspace, wrong_output
        )
    workspace.scratch.append(Complex32(0.0, 0.0))
    with assert_raises():
        ofdm_modulate_f32_into(
            Span(values), 0, inverse_plan, workspace, modulated_output
        )

    var nonfinite = values.copy()
    nonfinite[7] = Complex32(nan[DType.float32](), 0.0)
    with assert_raises():
        _ = ofdm_modulate_f32(Span(nonfinite), 0)
    nonfinite[7] = Complex32(inf[DType.float32](), 0.0)
    with assert_raises():
        _ = ofdm_demodulate_f32(Span(nonfinite), size, 0)

    # Two maximum-scale equal time samples make the unscaled DC bin exceed
    # binary32, so the final-boundary contract must reject it.
    var overflow = values.copy()
    overflow[0] = Complex32(Float32(3.0e38), 0.0)
    overflow[1] = Complex32(Float32(3.0e38), 0.0)
    with assert_raises():
        _ = ofdm_demodulate_f32(Span(overflow), size, 0)


def test_siso_deterministic_float64_differential_and_into_owning() raises:
    var known: List[Complex32] = [
        Complex32(1.0, 0.0),
        Complex32(0.0, 1.0),
        Complex32(0.5, -0.25),
        Complex32(-1.0, 0.5),
    ]
    var channel: List[Complex32] = [
        Complex32(0.75, -0.25),
        Complex32(-0.5, 1.0),
        Complex32(1.25, 0.5),
        Complex32(-0.75, -0.25),
    ]
    var received = List[Complex32](capacity=len(known))
    for index in range(len(known)):
        received.append(_multiply_f32(channel[index], known[index]))

    var received64 = _as_complex64(Span(received))
    var known64 = _as_complex64(Span(known))
    var channel64 = _as_complex64(Span(channel))
    var expected_ls = ls_channel_estimate(Span(received64), Span(known64))
    var ls_storage = List[Complex32](
        length=len(known), fill=Complex32(99.0, -99.0)
    )
    ls_channel_estimate_f32_into(Span(received), Span(known), ls_storage)
    _assert_vector_close(Span(ls_storage), Span(expected_ls), 1.0e-7, 3.0e-7)
    assert_equal(ls_channel_estimate_f32(Span(received), Span(known)), ls_storage)
    assert_equal(
        complex_divide_f32(received[0], known[0]), ls_storage[0]
    )

    var expected_zf = zero_forcing_equalize_siso(
        Span(received64), Span(channel64)
    )
    var zf_storage = List[Complex32](
        length=len(known), fill=Complex32(99.0, -99.0)
    )
    zero_forcing_equalize_siso_f32_into(
        Span(received), Span(channel), zf_storage
    )
    _assert_vector_close(Span(zf_storage), Span(expected_zf), 1.0e-7, 3.0e-7)
    assert_equal(
        zero_forcing_equalize_siso_f32(Span(received), Span(channel)),
        zf_storage,
    )

    var noise = Float32(0.125)
    var expected_mmse = mmse_equalize_siso(
        Span(received64), Span(channel64), Float64(noise)
    )
    var mmse_storage = List[Complex32](
        length=len(known), fill=Complex32(99.0, -99.0)
    )
    mmse_equalize_siso_f32_into(
        Span(received), Span(channel), noise, mmse_storage
    )
    _assert_vector_close(
        Span(mmse_storage), Span(expected_mmse), 1.0e-7, 3.0e-7
    )
    assert_equal(
        mmse_equalize_siso_f32(Span(received), Span(channel), noise),
        mmse_storage,
    )
    assert_equal(
        estimate_pilot_noise_variance_f32(
            Span(received), Span(known), Span(channel)
        ),
        Float32(0.0),
    )


def test_siso_seeded_property_float64_differential() raises:
    comptime count = 257
    var seed = UInt64(0xE571_5EED_2026)
    var known = _seeded_complex32(count, seed, floor=Float32(0.35))
    var channel = _seeded_complex32(count, seed, floor=Float32(0.5))
    var received = List[Complex32](capacity=count)
    for index in range(count):
        var prediction = _multiply_f32(channel[index], known[index])
        var noise_re = Float32(0.002) * (
            Float32(2.0) * _next_uniform_f32(seed) - Float32(1.0)
        )
        var noise_im = Float32(0.002) * (
            Float32(2.0) * _next_uniform_f32(seed) - Float32(1.0)
        )
        received.append(Complex32(
            prediction.re + noise_re, prediction.im + noise_im
        ))

    var known64 = _as_complex64(Span(known))
    var channel64 = _as_complex64(Span(channel))
    var received64 = _as_complex64(Span(received))
    var actual_ls = ls_channel_estimate_f32(Span(received), Span(known))
    var expected_ls = ls_channel_estimate(Span(received64), Span(known64))
    _assert_vector_close(Span(actual_ls), Span(expected_ls), 2.0e-7, 5.0e-7)
    var actual_ls_into = List[Complex32](
        length=count, fill=Complex32(0.0, 0.0)
    )
    ls_channel_estimate_f32_into(
        Span(received), Span(known), actual_ls_into
    )
    assert_equal(actual_ls_into, actual_ls)

    for index in range(16):
        var lhs = received[index]
        var rhs = known[index]
        var denominator = Float64(rhs.re) * Float64(rhs.re) + (
            Float64(rhs.im) * Float64(rhs.im)
        )
        var expected_ratio = Complex64(
            (
                Float64(lhs.re) * Float64(rhs.re)
                + Float64(lhs.im) * Float64(rhs.im)
            ) / denominator,
            (
                Float64(lhs.im) * Float64(rhs.re)
                - Float64(lhs.re) * Float64(rhs.im)
            ) / denominator,
        )
        _assert_complex_close(
            complex_divide_f32(lhs, rhs), expected_ratio, 2.0e-7, 5.0e-7
        )

    var actual_zf = zero_forcing_equalize_siso_f32(
        Span(received), Span(channel)
    )
    var expected_zf = zero_forcing_equalize_siso(
        Span(received64), Span(channel64)
    )
    _assert_vector_close(Span(actual_zf), Span(expected_zf), 2.0e-7, 5.0e-7)
    var actual_zf_into = List[Complex32](
        length=count, fill=Complex32(0.0, 0.0)
    )
    zero_forcing_equalize_siso_f32_into(
        Span(received), Span(channel), actual_zf_into
    )
    assert_equal(actual_zf_into, actual_zf)

    var noise_variance = Float32(0.03125)
    var actual_mmse = mmse_equalize_siso_f32(
        Span(received), Span(channel), noise_variance
    )
    var expected_mmse = mmse_equalize_siso(
        Span(received64), Span(channel64), Float64(noise_variance)
    )
    _assert_vector_close(
        Span(actual_mmse), Span(expected_mmse), 2.0e-7, 5.0e-7
    )
    var actual_mmse_into = List[Complex32](
        length=count, fill=Complex32(0.0, 0.0)
    )
    mmse_equalize_siso_f32_into(
        Span(received), Span(channel), noise_variance, actual_mmse_into
    )
    assert_equal(actual_mmse_into, actual_mmse)

    var actual_variance = estimate_pilot_noise_variance_f32(
        Span(received), Span(known), Span(channel)
    )
    var expected_variance = estimate_pilot_noise_variance(
        Span(received64), Span(known64), Span(channel64)
    )
    _assert_scalar_close(
        Float64(actual_variance), expected_variance, 2.0e-11, 5.0e-6
    )


def test_cpe_seeded_float64_and_analytic_differential() raises:
    comptime count = 193
    var seed = UInt64(0xC0FF_EE32_2026)
    var expected = _seeded_complex32(count, seed, floor=Float32(0.25))
    var phase = Float32(0.37125)
    var cosine = Float32(cos(Float64(phase)))
    var sine = Float32(sin(Float64(phase)))
    var received = List[Complex32](capacity=count)
    for value in expected:
        received.append(Complex32(
            value.re * cosine - value.im * sine,
            value.re * sine + value.im * cosine,
        ))
    var expected64 = _as_complex64(Span(expected))
    var received64 = _as_complex64(Span(received))
    var oracle = common_phase_error(Span(received64), Span(expected64))
    var estimate = common_phase_error_f32(Span(received), Span(expected))
    _assert_scalar_close(Float64(estimate), oracle, 3.0e-8, 2.0e-7)

    var corrected = correct_common_phase_error_f32(
        Span(received), estimate
    )
    _assert_vector_close(
        Span(corrected), Span(expected64), 2.0e-7, 5.0e-7
    )
    var storage = List[Complex32](
        length=count, fill=Complex32(99.0, -99.0)
    )
    correct_common_phase_error_f32_into(Span(received), estimate, storage)
    assert_equal(storage, corrected)


def test_extreme_siso_and_cpe_representability_contract() raises:
    var huge = Float32(3.0e38)
    var tiny = Float32(1.0e-38)
    assert_equal(
        complex_divide_f32(Complex32(huge, 0.0), Complex32(huge, 0.0)),
        Complex32(1.0, 0.0),
    )
    assert_equal(
        complex_divide_f32(Complex32(tiny, -tiny), Complex32(tiny, 0.0)),
        Complex32(1.0, -1.0),
    )
    var rotated = complex_divide_f32(
        Complex32(1.0, 0.0), Complex32(Float32(5.0e-39), Float32(5.0e-39))
    )
    _assert_scalar_close(Float64(rotated.re), 1.0e38, 2.0e31, 2.0e-7)
    _assert_scalar_close(Float64(rotated.im), -1.0e38, 2.0e31, 2.0e-7)
    with assert_raises():
        _ = complex_divide_f32(Complex32(huge, 0.0), Complex32(tiny, 0.0))
    with assert_raises():
        _ = complex_divide_f32(Complex32(tiny, 0.0), Complex32(huge, 0.0))

    var received_large: List[Complex32] = [Complex32(Float32(1.0e20), 0.0)]
    var channel_large: List[Complex32] = [Complex32(Float32(1.0e20), 0.0)]
    var large_mmse = mmse_equalize_siso_f32(
        Span(received_large), Span(channel_large), Float32(1.0)
    )
    _assert_scalar_close(Float64(large_mmse[0].re), 1.0, 1.0e-7, 2.0e-7)
    assert_equal(large_mmse[0].im, Float32(0.0))

    var received_small: List[Complex32] = [Complex32(Float32(1.0e-30), 0.0)]
    var channel_small: List[Complex32] = [Complex32(Float32(1.0e-30), 0.0)]
    var small_mmse = mmse_equalize_siso_f32(
        Span(received_small), Span(channel_small), Float32(1.0e-30)
    )
    _assert_scalar_close(Float64(small_mmse[0].re), 1.0e-30, 1.0e-37, 3.0e-7)

    var known_one: List[Complex32] = [Complex32(1.0, 0.0)]
    var exact_received: List[Complex32] = [Complex32(huge, 0.0)]
    var exact_channel: List[Complex32] = [Complex32(huge, 0.0)]
    assert_equal(
        estimate_pilot_noise_variance_f32(
            Span(exact_received), Span(known_one), Span(exact_channel)
        ),
        Float32(0.0),
    )
    var residual_received: List[Complex32] = [Complex32(Float32(1.0e19), 0.0)]
    var zero_channel: List[Complex32] = [Complex32(0.0, 0.0)]
    var residual_variance = estimate_pilot_noise_variance_f32(
            Span(residual_received), Span(known_one), Span(zero_channel)
        )
    _assert_scalar_close(
        Float64(residual_variance),
        1.0e38,
        2.0e31,
        3.0e-7,
    )
    var tiny_received: List[Complex32] = [Complex32(tiny, 0.0)]
    with assert_raises():
        _ = estimate_pilot_noise_variance_f32(
            Span(tiny_received), Span(known_one), Span(zero_channel)
        )
    var huge_residual: List[Complex32] = [Complex32(huge, 0.0)]
    with assert_raises():
        _ = estimate_pilot_noise_variance_f32(
            Span(huge_residual), Span(known_one), Span(zero_channel)
        )

    var expected_huge: List[Complex32] = [Complex32(huge, 0.0)]
    var received_huge: List[Complex32] = [Complex32(0.0, huge)]
    var expected_tiny: List[Complex32] = [Complex32(tiny, 0.0)]
    var received_tiny: List[Complex32] = [Complex32(0.0, tiny)]
    var huge_phase = common_phase_error_f32(
        Span(received_huge), Span(expected_huge)
    )
    _assert_scalar_close(
        Float64(huge_phase),
        1.5707963267948966,
        8.0e-8,
        8.0e-8,
    )
    var tiny_phase = common_phase_error_f32(
        Span(received_tiny), Span(expected_tiny)
    )
    _assert_scalar_close(
        Float64(tiny_phase),
        1.5707963267948966,
        8.0e-8,
        8.0e-8,
    )


def test_siso_and_cpe_validation_edges() raises:
    var empty = List[Complex32]()
    var empty_second = List[Complex32]()
    var empty_third = List[Complex32]()
    var one: List[Complex32] = [Complex32(1.0, 0.0)]
    var one_second: List[Complex32] = [Complex32(1.0, 0.0)]
    var one_third: List[Complex32] = [Complex32(1.0, 0.0)]
    var two: List[Complex32] = [Complex32(1.0, 0.0), Complex32(2.0, 0.0)]
    with assert_raises():
        _ = ls_channel_estimate_f32(Span(empty), Span(empty_second))
    with assert_raises():
        _ = ls_channel_estimate_f32(Span(one), Span(two))
    with assert_raises():
        _ = zero_forcing_equalize_siso_f32(Span(one), Span(two))
    with assert_raises():
        _ = complex_divide_f32(Complex32(1.0, 0.0), Complex32(0.0, 0.0))
    with assert_raises():
        _ = complex_divide_f32(
            Complex32(nan[DType.float32](), 0.0), Complex32(1.0, 0.0)
        )
    with assert_raises():
        _ = complex_divide_f32(
            Complex32(1.0, 0.0), Complex32(inf[DType.float32](), 0.0)
        )

    for invalid_noise in [
        Float32(-1.0), nan[DType.float32](), inf[DType.float32]()
    ]:
        with assert_raises():
            _ = mmse_equalize_siso_f32(
                Span(one), Span(one_second), invalid_noise
            )
    var zero: List[Complex32] = [Complex32(0.0, 0.0)]
    with assert_raises():
        _ = mmse_equalize_siso_f32(Span(one), Span(zero), Float32(0.0))
    var zero_mmse = mmse_equalize_siso_f32(
        Span(one), Span(zero), Float32(0.5)
    )
    assert_equal(zero_mmse[0], Complex32(0.0, 0.0))

    var wrong_output = List[Complex32]()
    with assert_raises():
        ls_channel_estimate_f32_into(
            Span(one), Span(one_second), wrong_output
        )
    with assert_raises():
        zero_forcing_equalize_siso_f32_into(
            Span(one), Span(one_second), wrong_output
        )
    with assert_raises():
        mmse_equalize_siso_f32_into(
            Span(one), Span(one_second), Float32(0.1), wrong_output
        )
    with assert_raises():
        correct_common_phase_error_f32_into(
            Span(one), Float32(0.1), wrong_output
        )

    with assert_raises():
        _ = estimate_pilot_noise_variance_f32(
            Span(empty), Span(empty_second), Span(empty_third)
        )
    with assert_raises():
        _ = estimate_pilot_noise_variance_f32(
            Span(one), Span(two), Span(one_third)
        )
    var nonfinite: List[Complex32] = [
        Complex32(nan[DType.float32](), 0.0)
    ]
    with assert_raises():
        _ = estimate_pilot_noise_variance_f32(
            Span(nonfinite), Span(one), Span(one_second)
        )

    with assert_raises():
        _ = common_phase_error_f32(Span(empty), Span(empty_second))
    with assert_raises():
        _ = common_phase_error_f32(Span(zero), Span(one))
    var cancelling_received: List[Complex32] = [
        Complex32(1.0, 0.0), Complex32(1.0, 0.0)
    ]
    var cancelling_expected: List[Complex32] = [
        Complex32(1.0, 0.0), Complex32(-1.0, 0.0)
    ]
    with assert_raises():
        _ = common_phase_error_f32(
            Span(cancelling_received), Span(cancelling_expected)
        )
    with assert_raises():
        _ = correct_common_phase_error_f32(
            Span(one), nan[DType.float32]()
        )
    with assert_raises():
        _ = correct_common_phase_error_f32(
            Span(nonfinite), Float32(0.0)
        )
    var rotation_overflow: List[Complex32] = [
        Complex32(Float32(3.0e38), Float32(3.0e38))
    ]
    with assert_raises():
        _ = correct_common_phase_error_f32(
            Span(rotation_overflow), Float32(0.7853981633974483)
        )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
