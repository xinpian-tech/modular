"""Independent evidence for public DSP, modem, synchronization, and channels.

The oracles here are deliberately outside the implementations under test:
closed-form scalar equations, a local O(N^2) DFT, literal standard vectors,
and seeded/static invariants.  Transform round trips are never used as the
sole numerical oracle.
"""

from std.collections import Span
from std.math import atan2, cos, sin, sqrt
from std.testing import assert_equal, assert_raises, assert_true, TestSuite
from std.utils.numerics import inf, nan
from wireless_dsp.core import Complex64
from wireless_dsp.dsp import (
    apply_window_complex,
    argmax_real,
    autocorrelate_complex,
    autocorrelation_sequence,
    blackman_window,
    common_phase_error,
    convolve_real,
    correlation_peak,
    correlation_phase,
    cross_correlate_complex,
    dft_reference,
    dot_complex,
    dot_real,
    energy_complex,
    energy_real,
    estimate_pilot_noise_variance,
    fft_batch,
    fft_in_place_with_plan,
    fft_radix4,
    fir_complex,
    fir_complex_chunk,
    fir_real,
    fir_real_chunk,
    generate_nco,
    hamming_window,
    hann_window,
    ifft,
    ifft_radix4,
    linear_interpolate_complex,
    linear_resample_complex,
    linear_resample_real,
    ls_channel_estimate,
    make_fft_plan,
    max_real,
    min1_min2,
    min_real,
    mix_complex,
    mmse_equalize_siso,
    normalized_correlation_at,
    normalized_cross_correlate_complex,
    ofdm_demodulate,
    ofdm_modulate,
    rational_resample_complex,
    rational_resample_real,
    rectangular_window,
    sign_product,
    sliding_window_energy,
    sum_real,
    window_energy,
    zero_forcing_equalize_siso,
)
from wireless_dsp.modem import (
    crc_append,
    crc_bits,
    crc_check,
    hard_bits_from_llr,
    qam_demap_hard,
    qam_demapper_llr_exact,
    qam_demapper_llr_piecewise,
    quantize_llr,
)
from wireless_dsp.synchronization import detect_repetition_start
from wireless_dsp.channel import (
    add_awgn,
    apply_cdl_narrowband,
    apply_cfo,
    apply_doppler,
    apply_integer_timing_offset,
    apply_iq_imbalance,
    apply_multipath,
    apply_phase_noise,
    apply_rayleigh_fading,
    apply_rician_fading,
    apply_sample_clock_offset,
    apply_standard_channel,
    awgn_and_cfo,
    cdl_array_response,
    cdl_profile,
    cdl_ray_angles,
    cdl_ray_offsets,
    cdl_ray_polarization_matrix,
    cdl_ula,
    cdl_upa,
    realize_cdl_channel,
    realize_standard_channel_paths,
    standard_channel_impulse_response,
    tdl_profile,
    wifi_tgac_profile,
    wifi_tgax_profile,
    wifi_tgn_profile,
)


comptime _PI = 3.1415926535897932384626433832795
comptime _TWO_PI = 6.283185307179586476925286766559


def _assert_close(
    actual: Float64, expected: Float64, tolerance: Float64
) raises:
    if abs(actual - expected) > tolerance:
        print(
            "differential actual/expected/tolerance:",
            actual,
            expected,
            tolerance,
        )
    assert_true(
        abs(actual - expected) <= tolerance,
        msg="numeric differential exceeded its explicit tolerance",
    )


def _assert_complex_close(
    actual: Complex64, expected: Complex64, tolerance: Float64
) raises:
    _assert_close(actual.re, expected.re, tolerance)
    _assert_close(actual.im, expected.im, tolerance)


def _assert_complex_lists_close(
    actual: List[Complex64],
    expected: List[Complex64],
    tolerance: Float64,
) raises:
    assert_equal(len(actual), len(expected))
    for i in range(len(actual)):
        _assert_complex_close(actual[i], expected[i], tolerance)


def _naive_dft(
    values: Span[Complex64, ...], *, inverse: Bool = False
) -> List[Complex64]:
    var result = List[Complex64](capacity=len(values))
    var direction = 1.0 if inverse else -1.0
    var scale = 1.0 / Float64(len(values)) if inverse else 1.0
    for k in range(len(values)):
        var re = 0.0
        var im = 0.0
        for n in range(len(values)):
            var angle = direction * _TWO_PI * Float64(k * n) / Float64(
                len(values)
            )
            var c = cos(angle)
            var s = sin(angle)
            re += values[n].re * c - values[n].im * s
            im += values[n].re * s + values[n].im * c
        result.append(Complex64(scale * re, scale * im))
    return result^


def _manual_cross_correlation(
    signal: Span[Complex64, ...], reference: Span[Complex64, ...]
) -> List[Complex64]:
    var result = List[Complex64](capacity=len(signal) - len(reference) + 1)
    for offset in range(len(signal) - len(reference) + 1):
        var re = 0.0
        var im = 0.0
        for k in range(len(reference)):
            # (a+jb) * conj(c+jd)
            re += (
                signal[offset + k].re * reference[k].re
                + signal[offset + k].im * reference[k].im
            )
            im += (
                signal[offset + k].im * reference[k].re
                - signal[offset + k].re * reference[k].im
            )
        result.append(Complex64(re, im))
    return result^


def _ascii_123456789_msb_first() -> List[UInt8]:
    var result = List[UInt8](capacity=72)
    for octet in [49, 50, 51, 52, 53, 54, 55, 56, 57]:
        for shift in range(7, -1, -1):
            result.append(UInt8((octet >> shift) & 1))
    return result^


def test_reductions_windows_and_firs_against_scalar_oracles() raises:
    var real_values: List[Float64] = [-2.0, 3.0, 1.0, -4.0]
    var real_rhs: List[Float64] = [0.5, -2.0, 4.0, 1.5]
    _assert_close(sum_real(Span(real_values)), -2.0, 0.0)
    _assert_close(dot_real(Span(real_values), Span(real_rhs)), -9.0, 0.0)
    _assert_close(energy_real(Span(real_values)), 30.0, 0.0)
    assert_equal(argmax_real(Span(real_values)), 1)
    _assert_close(min_real(Span(real_values)), -4.0, 0.0)
    _assert_close(max_real(Span(real_values)), 3.0, 0.0)
    var first, second, first_index = min1_min2(Span(real_values))
    _assert_close(first, -4.0, 0.0)
    _assert_close(second, -2.0, 0.0)
    assert_equal(first_index, 3)
    assert_equal(sign_product(Span(real_values)), 1)

    var complex_values: List[Complex64] = [
        Complex64(1.0, 2.0),
        Complex64(-3.0, 0.5),
        Complex64(0.0, -1.0),
    ]
    var complex_rhs: List[Complex64] = [
        Complex64(2.0, -1.0),
        Complex64(0.5, 4.0),
        Complex64(-2.0, 3.0),
    ]
    _assert_complex_close(
        dot_complex(Span(complex_values), Span(complex_rhs)),
        Complex64(-2.5, -19.25),
        0.0,
    )
    _assert_close(energy_complex(Span(complex_values)), 15.25, 0.0)

    var rectangular = rectangular_window(5)
    var hann = hann_window(5)
    var hamming = hamming_window(5)
    var blackman = blackman_window(5)
    var expected_rectangular: List[Float64] = [1.0, 1.0, 1.0, 1.0, 1.0]
    var expected_hann: List[Float64] = [0.0, 0.5, 1.0, 0.5, 0.0]
    var expected_hamming: List[Float64] = [0.08, 0.54, 1.0, 0.54, 0.08]
    var expected_blackman: List[Float64] = [0.0, 0.34, 1.0, 0.34, 0.0]
    for i in range(5):
        _assert_close(rectangular[i], expected_rectangular[i], 0.0)
        _assert_close(hann[i], expected_hann[i], 2.0e-15)
        _assert_close(hamming[i], expected_hamming[i], 2.0e-15)
        _assert_close(blackman[i], expected_blackman[i], 2.0e-15)
    var short_window: List[Float64] = [0.0, 0.5, 1.0]
    var windowed = apply_window_complex(
        Span(complex_values), Span(short_window)
    )
    _assert_complex_close(windowed[0], Complex64(0.0, 0.0), 0.0)
    _assert_complex_close(windowed[1], Complex64(-1.5, 0.25), 1.0e-15)
    _assert_complex_close(windowed[2], Complex64(0.0, -1.0), 1.0e-15)

    var signal_real: List[Float64] = [1.0, -2.0, 3.0]
    var taps_real: List[Float64] = [2.0, 0.5]
    var convolution = convolve_real(Span(signal_real), Span(taps_real))
    var expected_convolution: List[Float64] = [2.0, -3.5, 5.0, 1.5]
    assert_equal(convolution, expected_convolution)
    var filtered_real = fir_real(Span(signal_real), Span(taps_real))
    var expected_fir_real: List[Float64] = [2.0, -3.5, 5.0]
    assert_equal(filtered_real, expected_fir_real)
    var history_real: List[Float64] = [0.0]
    var first_real: List[Float64] = [1.0, -2.0]
    var second_real: List[Float64] = [3.0]
    var chunk_real_a = fir_real_chunk(
        Span(first_real), Span(taps_real), history_real
    )
    var chunk_real_b = fir_real_chunk(
        Span(second_real), Span(taps_real), history_real
    )
    var expected_chunk_a: List[Float64] = [2.0, -3.5]
    var expected_chunk_b: List[Float64] = [5.0]
    assert_equal(chunk_real_a, expected_chunk_a)
    assert_equal(chunk_real_b, expected_chunk_b)

    var signal_complex: List[Complex64] = [
        Complex64(1.0, 1.0),
        Complex64(2.0, -1.0),
        Complex64(-1.0, 0.5),
    ]
    var taps_complex: List[Complex64] = [
        Complex64(1.0, -1.0), Complex64(0.5, 0.0)
    ]
    var filtered_complex = fir_complex(
        Span(signal_complex), Span(taps_complex)
    )
    var expected_fir_complex: List[Complex64] = [
        Complex64(2.0, 0.0),
        Complex64(1.5, -2.5),
        Complex64(0.5, 1.0),
    ]
    _assert_complex_lists_close(
        filtered_complex, expected_fir_complex, 0.0
    )
    var history_complex: List[Complex64] = [Complex64(0.0, 0.0)]
    var first_complex: List[Complex64] = [
        Complex64(1.0, 1.0), Complex64(2.0, -1.0)
    ]
    var second_complex: List[Complex64] = [Complex64(-1.0, 0.5)]
    var chunk_complex_a = fir_complex_chunk(
        Span(first_complex), Span(taps_complex), history_complex
    )
    var chunk_complex_b = fir_complex_chunk(
        Span(second_complex), Span(taps_complex), history_complex
    )
    var expected_complex_a: List[Complex64] = [
        Complex64(2.0, 0.0), Complex64(1.5, -2.5)
    ]
    var expected_complex_b: List[Complex64] = [Complex64(0.5, 1.0)]
    _assert_complex_lists_close(chunk_complex_a, expected_complex_a, 0.0)
    _assert_complex_lists_close(chunk_complex_b, expected_complex_b, 0.0)

    var empty_real = List[Float64]()
    var empty_real_b = List[Float64]()
    var empty_complex = List[Complex64]()
    var empty_complex_b = List[Complex64]()
    _assert_close(sum_real(Span(empty_real)), 0.0, 0.0)
    _assert_close(energy_real(Span(empty_real)), 0.0, 0.0)
    _assert_close(
        dot_real(Span(empty_real), Span(empty_real_b)), 0.0, 0.0
    )
    _assert_complex_close(
        dot_complex(Span(empty_complex), Span(empty_complex_b)),
        Complex64(0.0, 0.0),
        0.0,
    )
    _assert_close(energy_complex(Span(empty_complex)), 0.0, 0.0)
    assert_equal(sign_product(Span(empty_real)), 1)
    assert_equal(
        len(convolve_real(Span(empty_real), Span(taps_real))), 0
    )
    assert_equal(len(rectangular_window(0)), 0)
    assert_equal(len(hann_window(0)), 0)
    assert_equal(len(hamming_window(0)), 0)
    assert_equal(len(blackman_window(0)), 0)
    assert_equal(len(fir_real(Span(empty_real), Span(taps_real))), 0)
    assert_equal(len(fir_complex(Span(empty_complex), Span(taps_complex))), 0)
    with assert_raises():
        _ = rectangular_window(-1)
    with assert_raises():
        _ = hann_window(-1)
    with assert_raises():
        _ = hamming_window(-1)
    with assert_raises():
        _ = blackman_window(-1)
    with assert_raises():
        _ = apply_window_complex(Span(signal_complex), Span(hann))
    with assert_raises():
        _ = argmax_real(Span(empty_real))
    with assert_raises():
        _ = min_real(Span(empty_real))
    with assert_raises():
        _ = max_real(Span(empty_real))
    with assert_raises():
        _ = min1_min2(Span(empty_real))
    var singleton: List[Float64] = [1.0]
    with assert_raises():
        _ = min1_min2(Span(singleton))
    with assert_raises():
        _ = dot_real(Span(real_values), Span(empty_real))
    with assert_raises():
        _ = dot_complex(Span(complex_values), Span(empty_complex))
    var bad_real_history = List[Float64]()
    with assert_raises():
        _ = fir_real_chunk(
            Span(first_real), Span(taps_real), bad_real_history
        )
    var bad_complex_history = List[Complex64]()
    with assert_raises():
        _ = fir_complex_chunk(
            Span(first_complex), Span(taps_complex), bad_complex_history
        )
    var huge_real_input: List[Float64] = [1.7e308]
    var overflow_real_tap: List[Float64] = [2.0]
    with assert_raises():
        _ = convolve_real(
            Span(huge_real_input), Span(overflow_real_tap)
        )
    with assert_raises():
        _ = fir_real(Span(huge_real_input), Span(overflow_real_tap))
    var empty_real_history = List[Float64]()
    with assert_raises():
        _ = fir_real_chunk(
            Span(huge_real_input),
            Span(overflow_real_tap),
            empty_real_history,
        )
    var huge_complex_input: List[Complex64] = [
        Complex64(1.7e308, 0.0)
    ]
    var overflow_complex_tap: List[Complex64] = [Complex64(2.0, 0.0)]
    with assert_raises():
        _ = fir_complex(
            Span(huge_complex_input), Span(overflow_complex_tap)
        )
    var empty_complex_history = List[Complex64]()
    with assert_raises():
        _ = fir_complex_chunk(
            Span(huge_complex_input),
            Span(overflow_complex_tap),
            empty_complex_history,
        )


def test_correlation_family_against_manual_complex_arithmetic() raises:
    var signal: List[Complex64] = [
        Complex64(1.0, 0.5),
        Complex64(-2.0, 1.0),
        Complex64(0.25, -1.5),
        Complex64(3.0, 0.0),
        Complex64(-0.5, 2.0),
    ]
    var reference: List[Complex64] = [
        Complex64(0.5, -1.0), Complex64(2.0, 0.25)
    ]
    var expected = _manual_cross_correlation(
        Span(signal), Span(reference)
    )
    var actual = cross_correlate_complex(Span(signal), Span(reference))
    _assert_complex_lists_close(actual, expected, 2.0e-15)

    var normalized = normalized_cross_correlate_complex(
        Span(signal), Span(reference)
    )
    assert_equal(len(normalized), len(expected))
    var reference_energy = 0.0
    for value in reference:
        reference_energy += value.magnitude_squared()
    for offset in range(len(normalized)):
        var signal_energy = 0.0
        for k in range(len(reference)):
            signal_energy += signal[offset + k].magnitude_squared()
        var denominator = sqrt(signal_energy * reference_energy)
        _assert_complex_close(
            normalized[offset],
            Complex64(
                expected[offset].re / denominator,
                expected[offset].im / denominator,
            ),
            2.0e-15,
        )
        var at = normalized_correlation_at(
            Span(signal), Span(reference), offset
        )
        _assert_complex_close(at, normalized[offset], 0.0)
    assert_equal(correlation_peak(Span(actual)), 2)

    var auto_zero = autocorrelate_complex(Span(signal), 0)
    var expected_energy = 0.0
    for value in signal:
        expected_energy += value.magnitude_squared()
    _assert_complex_close(auto_zero, Complex64(expected_energy, 0.0), 0.0)
    var auto_two = autocorrelate_complex(Span(signal), 2)
    var auto_two_re = 0.0
    var auto_two_im = 0.0
    for i in range(len(signal) - 2):
        auto_two_re += (
            signal[i + 2].re * signal[i].re
            + signal[i + 2].im * signal[i].im
        )
        auto_two_im += (
            signal[i + 2].im * signal[i].re
            - signal[i + 2].re * signal[i].im
        )
    _assert_complex_close(
        auto_two, Complex64(auto_two_re, auto_two_im), 2.0e-15
    )
    var auto_sequence = autocorrelation_sequence(
        Span(signal), 3, normalized=True
    )
    assert_equal(len(auto_sequence), 4)
    _assert_complex_close(auto_sequence[0], Complex64(1.0, 0.0), 0.0)
    _assert_complex_close(
        auto_sequence[2],
        Complex64(auto_two_re / expected_energy, auto_two_im / expected_energy),
        2.0e-15,
    )

    _assert_close(window_energy(Span(signal), 1, 3), 16.3125, 0.0)
    var sliding = sliding_window_energy(Span(signal), 3)
    var expected_sliding: List[Float64] = [
        8.5625, 16.3125, 15.5625
    ]
    assert_equal(sliding, expected_sliding)
    _assert_close(correlation_phase(Complex64(1.0, 1.0)), _PI / 4.0, 2.0e-15)
    _assert_close(correlation_phase(Complex64(0.0, 0.0)), 0.0, 0.0)

    # Deterministic property grid: the public sliding correlation must agree
    # with a separately indexed scalar complex formula at every offset.
    var grid = List[Complex64](capacity=31)
    var kernel = List[Complex64](capacity=7)
    for i in range(31):
        grid.append(Complex64(
            Float64((17 * i + 3) % 23) / 11.0 - 1.0,
            Float64((29 * i + 5) % 19) / 9.0 - 1.0,
        ))
    for i in range(7):
        kernel.append(Complex64(
            Float64((13 * i + 2) % 11) / 5.0 - 1.0,
            Float64((7 * i + 4) % 13) / 6.0 - 1.0,
        ))
    var grid_expected = _manual_cross_correlation(Span(grid), Span(kernel))
    var grid_actual = cross_correlate_complex(Span(grid), Span(kernel))
    _assert_complex_lists_close(grid_actual, grid_expected, 2.0e-14)

    var empty = List[Complex64]()
    assert_equal(
        len(cross_correlate_complex(Span(signal), Span(empty))), 0
    )
    assert_equal(
        len(normalized_cross_correlate_complex(Span(empty), Span(reference))),
        0,
    )
    with assert_raises():
        _ = normalized_correlation_at(Span(signal), Span(reference), -1)
    with assert_raises():
        _ = correlation_peak(Span(empty))
    with assert_raises():
        _ = autocorrelate_complex(Span(signal), len(signal))
    with assert_raises():
        _ = autocorrelation_sequence(Span(signal), len(signal))
    with assert_raises():
        _ = window_energy(Span(signal), -1, 1)
    with assert_raises():
        _ = sliding_window_energy(Span(signal), 0)


def test_make_fft_plan_analytic_builder_grid_and_int_edges() raises:
    for size in [1, 2, 4, 8, 16, 64, 256]:
        for inverse in [False, True]:
            var first = make_fft_plan(size, inverse=inverse)
            var second = make_fft_plan(size, inverse=inverse)
            assert_equal(first.size, size)
            assert_equal(first.inverse, inverse)
            assert_equal(first.twiddles, second.twiddles)
            assert_equal(len(first.twiddles), size // 2)
            var direction = _TWO_PI if inverse else -_TWO_PI
            for k in range(size // 2):
                var angle = direction * Float64(k) / Float64(size)
                _assert_close(first.twiddles[k].re, cos(angle), 0.0)
                _assert_close(first.twiddles[k].im, sin(angle), 0.0)
    with assert_raises():
        _ = make_fft_plan(Int.MIN)
    with assert_raises():
        _ = make_fft_plan(Int.MAX)


def test_fft_ofdm_nco_and_mixer_against_naive_equations() raises:
    var arbitrary: List[Complex64] = [
        Complex64(1.0, -0.5),
        Complex64(-2.0, 1.25),
        Complex64(0.75, 0.0),
        Complex64(3.0, -1.0),
        Complex64(-0.25, 2.0),
    ]
    var arbitrary_expected = _naive_dft(Span(arbitrary))
    var arbitrary_actual = dft_reference(Span(arbitrary))
    _assert_complex_lists_close(
        arbitrary_actual, arbitrary_expected, 2.0e-14
    )

    var values = List[Complex64](capacity=16)
    for i in range(16):
        values.append(Complex64(
            Float64((17 * i + 1) % 19) / 9.0 - 1.0,
            Float64((11 * i + 4) % 17) / 8.0 - 1.0,
        ))
    var forward_expected = _naive_dft(Span(values))
    var planned = values.copy()
    var plan = make_fft_plan(16)
    fft_in_place_with_plan(planned, plan)
    _assert_complex_lists_close(planned, forward_expected, 4.0e-14)
    var radix4 = fft_radix4(Span(values))
    _assert_complex_lists_close(radix4, forward_expected, 4.0e-14)

    var inverse_expected = _naive_dft(Span(values), inverse=True)
    var inverse_radix2 = ifft(Span(values))
    var inverse_radix4 = ifft_radix4(Span(values))
    _assert_complex_lists_close(inverse_radix2, inverse_expected, 4.0e-15)
    _assert_complex_lists_close(inverse_radix4, inverse_expected, 4.0e-15)

    var batched_input: List[Complex64] = [
        Complex64(1.0), Complex64(2.0), Complex64(3.0), Complex64(4.0),
        Complex64(0.0, 1.0), Complex64(1.0, 1.0),
        Complex64(2.0, -1.0), Complex64(-1.0, 0.5),
    ]
    var first_batch: List[Complex64] = [
        batched_input[0], batched_input[1], batched_input[2], batched_input[3]
    ]
    var second_batch: List[Complex64] = [
        batched_input[4], batched_input[5], batched_input[6], batched_input[7]
    ]
    var expected_first = _naive_dft(Span(first_batch))
    var expected_second = _naive_dft(Span(second_batch))
    var batched = fft_batch(Span(batched_input), 4)
    for i in range(4):
        _assert_complex_close(batched[i], expected_first[i], 3.0e-15)
        _assert_complex_close(batched[4 + i], expected_second[i], 3.0e-15)

    var spectrum: List[Complex64] = [
        Complex64(1.0, 0.0),
        Complex64(-0.5, 0.25),
        Complex64(0.0, 1.0),
        Complex64(0.75, -0.5),
        Complex64(-1.0, 0.0),
        Complex64(0.25, 0.5),
        Complex64(0.0, -0.75),
        Complex64(0.5, 0.25),
    ]
    var manual_time = _naive_dft(Span(spectrum), inverse=True)
    var expected_waveform = List[Complex64](capacity=11)
    for i in range(5, 8):
        expected_waveform.append(manual_time[i])
    for value in manual_time:
        expected_waveform.append(value)
    var waveform = ofdm_modulate(Span(spectrum), 3)
    _assert_complex_lists_close(waveform, expected_waveform, 3.0e-15)
    # Feed the independently constructed CP/time-domain vector into the RX.
    var recovered = ofdm_demodulate(Span(expected_waveform), 8, 3)
    _assert_complex_lists_close(recovered, spectrum, 4.0e-15)

    var nco = generate_nco(17, 0.125, initial_phase=0.3)
    var baseband = List[Complex64](capacity=17)
    for i in range(17):
        var expected_phase = 0.3 + _TWO_PI * 0.125 * Float64(i)
        _assert_complex_close(
            nco[i],
            Complex64(cos(expected_phase), sin(expected_phase)),
            1.0e-14,
        )
        baseband.append(Complex64(
            Float64(i - 8) / 7.0, Float64((3 * i + 1) % 9) / 4.0 - 1.0
        ))
    var mixed = mix_complex(
        Span(baseband), -0.0625, initial_phase=-0.2
    )
    for i in range(len(baseband)):
        var phase = -0.2 - _TWO_PI * 0.0625 * Float64(i)
        var expected = baseband[i] * Complex64(cos(phase), sin(phase))
        _assert_complex_close(mixed[i], expected, 1.0e-14)
        _assert_close(
            mixed[i].magnitude_squared(),
            baseband[i].magnitude_squared(),
            2.0e-15,
        )

    var empty = List[Complex64]()
    with assert_raises():
        _ = dft_reference(Span(empty))
    with assert_raises():
        _ = ifft(Span(empty))
    with assert_raises():
        _ = fft_batch(Span(values), 3)
    with assert_raises():
        _ = fft_batch(Span(arbitrary), 4)
    var wrong_plan_data: List[Complex64] = [Complex64(1.0)]
    with assert_raises():
        fft_in_place_with_plan(wrong_plan_data, plan)
    var radix4_bad: List[Complex64] = [
        Complex64(1.0), Complex64(2.0)
    ]
    with assert_raises():
        _ = fft_radix4(Span(radix4_bad))
    with assert_raises():
        _ = ifft_radix4(Span(radix4_bad))
    with assert_raises():
        _ = ofdm_modulate(Span(spectrum), 9)
    with assert_raises():
        _ = ofdm_demodulate(Span(expected_waveform), 8, 2)
    with assert_raises():
        _ = generate_nco(-1, 0.1)
    with assert_raises():
        _ = generate_nco(4, nan[DType.float64]())
    with assert_raises():
        _ = generate_nco(4, 0.1, initial_phase=inf[DType.float64]())
    # Every representable Float64 this large is an integer cycle count.  The
    # public phase contract reduces in cycles before converting to radians, so
    # this is exactly a zero-frequency oscillator rather than an overflow.
    var huge_nco = generate_nco(4, 1.0e308)
    for value in huge_nco:
        assert_equal(value, Complex64(1.0, 0.0))
    with assert_raises():
        _ = mix_complex(Span(values), inf[DType.float64]())
    var invalid_mix_sample: List[Complex64] = [
        Complex64(0.0, nan[DType.float64]())
    ]
    with assert_raises():
        _ = mix_complex(Span(invalid_mix_sample), 0.1)
    var two_finite_samples: List[Complex64] = [
        Complex64(1.0), Complex64(1.0)
    ]
    assert_equal(
        mix_complex(Span(two_finite_samples), 1.0e308),
        two_finite_samples,
    )
    assert_equal(len(mix_complex(Span(empty), 0.1)), 0)


def test_resampling_and_siso_estimation_against_closed_forms() raises:
    var real: List[Float64] = [0.0, 10.0, 20.0]
    var linear_real = linear_resample_real(Span(real), 5)
    var expected_linear_real: List[Float64] = [0.0, 5.0, 10.0, 15.0, 20.0]
    assert_equal(linear_real, expected_linear_real)
    var complex: List[Complex64] = [
        Complex64(0.0, 0.0),
        Complex64(10.0, -5.0),
        Complex64(20.0, 10.0),
    ]
    var linear_complex = linear_resample_complex(Span(complex), 5)
    var expected_linear_complex: List[Complex64] = [
        Complex64(0.0, 0.0),
        Complex64(5.0, -2.5),
        Complex64(10.0, -5.0),
        Complex64(15.0, 2.5),
        Complex64(20.0, 10.0),
    ]
    _assert_complex_lists_close(
        linear_complex, expected_linear_complex, 0.0
    )

    var rational_input: List[Float64] = [1.0, 2.0, 3.0]
    var rational_complex_input: List[Complex64] = [
        Complex64(1.0, -1.0),
        Complex64(2.0, -2.0),
        Complex64(3.0, -3.0),
    ]
    var taps: List[Float64] = [0.5, 1.0, 0.5]
    var rational_real = rational_resample_real(
        Span(rational_input), Span(taps), 2, 1
    )
    var expected_rational_real: List[Float64] = [
        0.5, 1.0, 1.5, 2.0, 2.5, 3.0, 1.5
    ]
    assert_equal(rational_real, expected_rational_real)
    var rational_complex = rational_resample_complex(
        Span(rational_complex_input), Span(taps), 2, 1
    )
    assert_equal(len(rational_complex), len(expected_rational_real))
    for i in range(len(rational_complex)):
        _assert_complex_close(
            rational_complex[i],
            Complex64(expected_rational_real[i], -expected_rational_real[i]),
            0.0,
        )

    var channel: List[Complex64] = [
        Complex64(2.0, 0.5),
        Complex64(-0.75, 1.25),
        Complex64(1.5, -0.25),
    ]
    var known: List[Complex64] = [
        Complex64(1.0, 0.0),
        Complex64(0.0, 1.0),
        Complex64(-1.0, 0.5),
    ]
    var received = List[Complex64](capacity=3)
    for i in range(3):
        received.append(channel[i] * known[i])
    var estimated = ls_channel_estimate(Span(received), Span(known))
    _assert_complex_lists_close(estimated, channel, 2.0e-15)

    var pilot_values: List[Complex64] = [
        Complex64(1.0, 1.0), Complex64(4.0, -2.0)
    ]
    var pilot_positions: List[Int] = [1, 4]
    var interpolated = linear_interpolate_complex(
        Span(pilot_values), Span(pilot_positions), 6
    )
    var expected_interpolated: List[Complex64] = [
        Complex64(1.0, 1.0),
        Complex64(1.0, 1.0),
        Complex64(2.0, 0.0),
        Complex64(3.0, -1.0),
        Complex64(4.0, -2.0),
        Complex64(4.0, -2.0),
    ]
    _assert_complex_lists_close(
        interpolated, expected_interpolated, 5.0e-16
    )

    var noise_known: List[Complex64] = [
        Complex64(1.0), Complex64(1.0)
    ]
    var noise_channel: List[Complex64] = [
        Complex64(2.0, 0.0), Complex64(1.0, -1.0)
    ]
    var noisy_received: List[Complex64] = [
        Complex64(2.1, 0.2), Complex64(0.8, -0.9)
    ]
    var noise_variance = estimate_pilot_noise_variance(
        Span(noisy_received), Span(noise_known), Span(noise_channel)
    )
    _assert_close(noise_variance, 0.05, 2.0e-16)

    var transmitted: List[Complex64] = [
        Complex64(1.0, -0.5),
        Complex64(-2.0, 1.0),
        Complex64(0.25, 0.75),
    ]
    var equalizer_received = List[Complex64](capacity=3)
    for i in range(3):
        equalizer_received.append(channel[i] * transmitted[i])
    var zf = zero_forcing_equalize_siso(
        Span(equalizer_received), Span(channel)
    )
    _assert_complex_lists_close(zf, transmitted, 2.0e-15)
    var mmse = mmse_equalize_siso(
        Span(equalizer_received), Span(channel), 0.2
    )
    for i in range(3):
        var gain = channel[i].magnitude_squared() / (
            channel[i].magnitude_squared() + 0.2
        )
        _assert_complex_close(
            mmse[i],
            Complex64(gain * transmitted[i].re, gain * transmitted[i].im),
            2.0e-15,
        )

    var expected_pilots: List[Complex64] = [
        Complex64(1.0), Complex64(-1.0), Complex64(0.0, 1.0)
    ]
    var received_pilots = List[Complex64](capacity=3)
    var phase = 0.375
    var rotation = Complex64(cos(phase), sin(phase))
    for pilot in expected_pilots:
        received_pilots.append(pilot * rotation)
    _assert_close(
        common_phase_error(Span(received_pilots), Span(expected_pilots)),
        phase,
        2.0e-15,
    )

    var empty_real = List[Float64]()
    var empty_complex = List[Complex64]()
    var empty_complex_b = List[Complex64]()
    var empty_complex_c = List[Complex64]()
    var empty_positions = List[Int]()
    assert_equal(len(linear_resample_real(Span(empty_real), 0)), 0)
    assert_equal(len(linear_resample_complex(Span(empty_complex), 0)), 0)
    assert_equal(
        len(rational_resample_real(
            Span(empty_real), Span(taps), 2, 3
        )),
        0,
    )
    assert_equal(
        len(rational_resample_complex(
            Span(empty_complex), Span(taps), 2, 3
        )),
        0,
    )
    with assert_raises():
        _ = linear_resample_real(Span(empty_real), 1)
    with assert_raises():
        _ = linear_resample_complex(Span(empty_complex), 1)
    with assert_raises():
        _ = rational_resample_real(
            Span(rational_input), Span(empty_real), 1, 1
        )
    with assert_raises():
        _ = rational_resample_complex(
            Span(rational_complex_input), Span(taps), 0, 1
        )
    with assert_raises():
        _ = ls_channel_estimate(
            Span(empty_complex), Span(empty_complex_b)
        )
    with assert_raises():
        _ = linear_interpolate_complex(
            Span(pilot_values), Span(empty_positions), 6
        )
    with assert_raises():
        _ = estimate_pilot_noise_variance(
            Span(empty_complex), Span(empty_complex_b), Span(empty_complex_c)
        )
    var zero_channel: List[Complex64] = [Complex64(0.0, 0.0)]
    var one_received: List[Complex64] = [Complex64(1.0, 0.0)]
    with assert_raises():
        _ = zero_forcing_equalize_siso(
            Span(one_received), Span(zero_channel)
        )
    with assert_raises():
        _ = mmse_equalize_siso(
            Span(one_received), Span(zero_channel), 0.0
        )
    with assert_raises():
        _ = mmse_equalize_siso(
            Span(one_received), Span(zero_channel), nan[DType.float64]()
        )
    with assert_raises():
        _ = common_phase_error(
            Span(empty_complex), Span(empty_complex_b)
        )


def test_crc_and_qam_decisions_against_static_standard_oracles() raises:
    var message = _ascii_123456789_msb_first()
    var remainder = crc_bits(
        Span(message), width=8, polynomial=UInt64(0x07)
    )
    # CRC-8/SMBUS check value for ASCII "123456789", MSB-first.
    assert_equal(remainder, UInt64(0xF4))
    var codeword = crc_append(
        Span(message), width=8, polynomial=UInt64(0x07)
    )
    assert_equal(len(codeword), 80)
    var expected_crc_bits: List[UInt8] = [1, 1, 1, 1, 0, 1, 0, 0]
    for i in range(8):
        assert_equal(codeword[72 + i], expected_crc_bits[i])
    assert_true(
        crc_check(Span(codeword), width=8, polynomial=UInt64(0x07))
    )
    # Every single-bit error in this finite codeword must be detected.
    for position in range(len(codeword)):
        var corrupted = codeword.copy()
        corrupted[position] ^= UInt8(1)
        assert_true(
            not crc_check(
                Span(corrupted), width=8, polynomial=UInt64(0x07)
            )
        )

    var bpsk_samples: List[Complex64] = [
        Complex64(2.0, 5.0), Complex64(-0.1, -7.0)
    ]
    var bpsk_hard = qam_demap_hard(Span(bpsk_samples), 1)
    var expected_bpsk: List[UInt8] = [0, 1]
    assert_equal(bpsk_hard, expected_bpsk)
    var qpsk_scale = 1.0 / sqrt(2.0)
    var qpsk_samples: List[Complex64] = [
        Complex64(qpsk_scale, qpsk_scale),
        Complex64(qpsk_scale, -qpsk_scale),
        Complex64(-qpsk_scale, -qpsk_scale),
        Complex64(-qpsk_scale, qpsk_scale),
    ]
    var qpsk_hard = qam_demap_hard(Span(qpsk_samples), 2)
    var expected_qpsk: List[UInt8] = [0, 0, 0, 1, 1, 1, 1, 0]
    assert_equal(qpsk_hard, expected_qpsk)
    var scale16 = sqrt(10.0)
    var qam16_samples: List[Complex64] = [
        Complex64(3.0 / scale16, 3.0 / scale16),
        Complex64(1.0 / scale16, -1.0 / scale16),
        Complex64(-1.0 / scale16, -3.0 / scale16),
        Complex64(-3.0 / scale16, 1.0 / scale16),
    ]
    var qam16_hard = qam_demap_hard(Span(qam16_samples), 4)
    var expected_qam16: List[UInt8] = [
        0, 0, 0, 0, 0, 1, 1, 1,
        1, 1, 1, 0, 1, 0, 0, 1,
    ]
    assert_equal(qam16_hard, expected_qam16)

    var off_grid: List[Complex64] = [
        Complex64(-0.75, 0.4),
        Complex64(0.125, -1.25),
        Complex64(1.5, 0.0),
    ]
    var noise_variance = 0.625
    var exact_bpsk = qam_demapper_llr_exact(
        Span(off_grid), 1, noise_variance
    )
    var piecewise_bpsk = qam_demapper_llr_piecewise(
        Span(off_grid), 1, noise_variance
    )
    for i in range(len(off_grid)):
        var expected = 4.0 * off_grid[i].re / noise_variance
        _assert_close(exact_bpsk[i], expected, 2.0e-15)
        _assert_close(piecewise_bpsk[i], expected, 0.0)
    var exact_qpsk = qam_demapper_llr_exact(
        Span(off_grid), 2, noise_variance
    )
    for i in range(len(off_grid)):
        _assert_close(
            exact_qpsk[2 * i],
            4.0 * qpsk_scale * off_grid[i].re / noise_variance,
            3.0e-15,
        )
        _assert_close(
            exact_qpsk[2 * i + 1],
            4.0 * qpsk_scale * off_grid[i].im / noise_variance,
            3.0e-15,
        )

    var llrs: List[Float64] = [1.24, -1.26, 100.0, -100.0, 0.0]
    var quantized = quantize_llr(Span(llrs), scale=2.0, clip=7)
    var expected_quantized: List[Int] = [2, -3, 7, -7, 0]
    assert_equal(quantized, expected_quantized)
    var hard = hard_bits_from_llr(Span(llrs))
    var expected_hard: List[UInt8] = [0, 1, 0, 1, 0]
    assert_equal(hard, expected_hard)
    var empty_llrs = List[Float64]()
    assert_equal(len(hard_bits_from_llr(Span(empty_llrs))), 0)

    var invalid_bits: List[UInt8] = [0, 2]
    with assert_raises():
        _ = crc_bits(
            Span(invalid_bits), width=8, polynomial=UInt64(0x07)
        )
    with assert_raises():
        _ = crc_append(Span(message), width=0, polynomial=UInt64(0x07))
    with assert_raises():
        _ = crc_check(Span(codeword), width=64, polynomial=UInt64(0x07))
    var invalid_sample: List[Complex64] = [
        Complex64(nan[DType.float64](), 0.0)
    ]
    with assert_raises():
        _ = qam_demap_hard(Span(invalid_sample), 2)
    with assert_raises():
        _ = qam_demapper_llr_exact(Span(off_grid), 2, 0.0)
    with assert_raises():
        _ = qam_demapper_llr_piecewise(
            Span(off_grid), 2, inf[DType.float64]()
        )
    with assert_raises():
        _ = quantize_llr(
            Span(llrs), scale=nan[DType.float64](), clip=7
        )


def test_seeded_channel_impairments_against_analytic_and_static_oracles() raises:
    var samples: List[Complex64] = [
        Complex64(1.0, 0.0),
        Complex64(0.0, 1.0),
        Complex64(-1.0, 0.5),
        Complex64(2.0, -0.25),
    ]
    var unchanged = add_awgn(Span(samples), 0.0, seed=UInt64(7))
    assert_equal(unchanged, samples)
    var noise_a = add_awgn(Span(samples), 0.2, seed=UInt64(12345))
    var noise_b = add_awgn(Span(samples), 0.2, seed=UInt64(12345))
    assert_equal(noise_a, noise_b)
    var zeros = List[Complex64](length=4096, fill=Complex64(0.0, 0.0))
    var noise_cloud = add_awgn(
        Span(zeros), 0.25, seed=UInt64(0x20260821)
    )
    var measured_noise_power = 0.0
    for sample in noise_cloud:
        measured_noise_power += sample.magnitude_squared()
    measured_noise_power /= Float64(len(noise_cloud))
    _assert_close(measured_noise_power, 0.25, 0.018)

    var cfo = apply_cfo(Span(samples), 0.125, initial_phase=0.3)
    var doppler = apply_doppler(
        Span(samples), 0.125, initial_phase=0.3
    )
    # These closed-form equations are independent of the bounded phase
    # recurrence used by the implementation.  Their final rounding can differ
    # by a few ulps, so retain a tight absolute error budget for these small,
    # fixed vectors instead of requiring bit identity.
    var periodic_phase_tolerance = 2.0e-15
    for i in range(len(samples)):
        var phase = 0.3 + _TWO_PI * 0.125 * Float64(i)
        var expected = samples[i] * Complex64(cos(phase), sin(phase))
        _assert_complex_close(cfo[i], expected, periodic_phase_tolerance)
        _assert_complex_close(
            doppler[i], expected, periodic_phase_tolerance
        )
    var combined = awgn_and_cfo(
        Span(samples),
        0.0,
        -0.25,
        seed=UInt64(999),
        initial_phase=-0.4,
    )
    for i in range(len(samples)):
        var phase = -0.4 - _TWO_PI * 0.25 * Float64(i)
        _assert_complex_close(
            combined[i],
            samples[i] * Complex64(cos(phase), sin(phase)),
            periodic_phase_tolerance,
        )
    var combined_noise_a = awgn_and_cfo(
        Span(samples), 0.1, 0.02, seed=UInt64(44)
    )
    var combined_noise_b = awgn_and_cfo(
        Span(samples), 0.1, 0.02, seed=UInt64(44)
    )
    assert_equal(combined_noise_a, combined_noise_b)

    var delayed = apply_integer_timing_offset(Span(samples), 2)
    var expected_delayed: List[Complex64] = [
        Complex64(0.0), Complex64(0.0), samples[0], samples[1]
    ]
    assert_equal(delayed, expected_delayed)
    var advanced = apply_integer_timing_offset(Span(samples), -1)
    var expected_advanced: List[Complex64] = [
        samples[1], samples[2], samples[3], Complex64(0.0)
    ]
    assert_equal(advanced, expected_advanced)
    var extreme_positive = apply_integer_timing_offset(
        Span(samples), Int.MAX
    )
    var extreme_negative = apply_integer_timing_offset(
        Span(samples), Int.MIN
    )
    for i in range(len(samples)):
        assert_equal(extreme_positive[i], Complex64(0.0, 0.0))
        assert_equal(extreme_negative[i], Complex64(0.0, 0.0))

    var multipath_input: List[Complex64] = [
        Complex64(1.0, 1.0), Complex64(2.0, -1.0)
    ]
    var multipath_taps: List[Complex64] = [
        Complex64(0.5, 0.0), Complex64(0.0, 1.0)
    ]
    var multipath = apply_multipath(
        Span(multipath_input), Span(multipath_taps)
    )
    var expected_multipath: List[Complex64] = [
        Complex64(0.5, 0.5),
        Complex64(0.0, 0.5),
        Complex64(1.0, 2.0),
    ]
    _assert_complex_lists_close(multipath, expected_multipath, 0.0)

    var unit_samples = List[Complex64](length=4, fill=Complex64(1.0, 0.0))
    var phase_noise = apply_phase_noise(
        Span(unit_samples),
        0.1,
        seed=UInt64(12345),
        initial_phase=0.2,
    )
    var phase_noise_static: List[Complex64] = [
        Complex64(0.9838968022770321, 0.17873746800553808),
        Complex64(0.9790632709145161, 0.2035561631249933),
        Complex64(0.9978311443300331, 0.06582558321060833),
        Complex64(0.9999139972002873, 0.013114808536306203),
    ]
    _assert_complex_lists_close(phase_noise, phase_noise_static, 5.0e-11)
    var phase_noise_again = apply_phase_noise(
        Span(unit_samples),
        0.1,
        seed=UInt64(12345),
        initial_phase=0.2,
    )
    assert_equal(phase_noise, phase_noise_again)
    for value in phase_noise:
        _assert_close(value.magnitude_squared(), 1.0, 2.0e-15)

    var iq = apply_iq_imbalance(Span(samples), 0.2, 0.3)
    for i in range(len(samples)):
        _assert_close(iq[i].re, 1.2 * samples[i].re, 0.0)
        _assert_close(
            iq[i].im,
            0.8
            * (cos(0.3) * samples[i].im + sin(0.3) * samples[i].re),
            0.0,
        )
    var clock_input: List[Complex64] = [
        Complex64(0.0), Complex64(1.0), Complex64(2.0), Complex64(3.0)
    ]
    var clock = apply_sample_clock_offset(Span(clock_input), 500000.0)
    var expected_clock: List[Complex64] = [
        Complex64(0.0), Complex64(1.5), Complex64(3.0), Complex64(0.0)
    ]
    assert_equal(clock, expected_clock)

    var rayleigh = apply_rayleigh_fading(
        Span(unit_samples), seed=UInt64(77), block_fading=True
    )
    var rayleigh_again = apply_rayleigh_fading(
        Span(unit_samples), seed=UInt64(77), block_fading=True
    )
    assert_equal(rayleigh, rayleigh_again)
    for i in range(1, len(rayleigh)):
        assert_equal(rayleigh[i], rayleigh[0])
    var rician_zero = apply_rician_fading(
        Span(unit_samples), 0.0, seed=UInt64(77), block_fading=True
    )
    _assert_complex_lists_close(rician_zero, rayleigh, 0.0)
    var rician = apply_rician_fading(
        Span(unit_samples),
        10.0,
        seed=UInt64(88),
        los_phase=0.4,
        block_fading=True,
    )
    var rician_again = apply_rician_fading(
        Span(unit_samples),
        10.0,
        seed=UInt64(88),
        los_phase=0.4,
        block_fading=True,
    )
    assert_equal(rician, rician_again)
    for i in range(1, len(rician)):
        assert_equal(rician[i], rician[0])

    var empty = List[Complex64]()
    assert_equal(len(add_awgn(Span(empty), 0.1, seed=UInt64(1))), 0)
    assert_equal(len(apply_cfo(Span(empty), 0.1)), 0)
    assert_equal(len(apply_doppler(Span(empty), 0.1)), 0)
    assert_equal(
        len(apply_integer_timing_offset(Span(empty), 100)), 0
    )
    assert_equal(
        len(apply_multipath(Span(empty), Span(multipath_taps))), 0
    )
    assert_equal(
        len(apply_rayleigh_fading(Span(empty), seed=UInt64(1))), 0
    )
    assert_equal(
        len(apply_rician_fading(Span(empty), 1.0, seed=UInt64(1))), 0
    )
    assert_equal(
        len(apply_phase_noise(Span(empty), 0.1, seed=UInt64(1))), 0
    )
    assert_equal(len(apply_iq_imbalance(Span(empty), 0.1, 0.1)), 0)
    assert_equal(len(apply_sample_clock_offset(Span(empty), 1.0)), 0)
    with assert_raises():
        _ = add_awgn(Span(samples), -1.0, seed=UInt64(1))
    with assert_raises():
        _ = add_awgn(
            Span(samples), inf[DType.float64](), seed=UInt64(1)
        )
    with assert_raises():
        _ = apply_cfo(Span(samples), nan[DType.float64]())
    with assert_raises():
        _ = awgn_and_cfo(
            Span(samples), 0.1, inf[DType.float64](), seed=UInt64(1)
        )
    with assert_raises():
        _ = apply_doppler(Span(samples), inf[DType.float64]())
    with assert_raises():
        _ = apply_phase_noise(
            Span(samples), nan[DType.float64](), seed=UInt64(1)
        )
    with assert_raises():
        _ = apply_rician_fading(
            Span(samples), -0.1, seed=UInt64(1)
        )
    with assert_raises():
        _ = apply_rician_fading(
            Span(samples), 1.0, seed=UInt64(1), los_phase=inf[DType.float64]()
        )
    with assert_raises():
        _ = apply_iq_imbalance(Span(samples), 1.0, 0.0)
    with assert_raises():
        _ = apply_iq_imbalance(
            Span(samples), 0.0, nan[DType.float64]()
        )
    with assert_raises():
        _ = apply_sample_clock_offset(Span(samples), 1.0e6)
    with assert_raises():
        _ = apply_sample_clock_offset(
            Span(samples), nan[DType.float64]()
        )
    var invalid_channel_sample: List[Complex64] = [
        Complex64(nan[DType.float64](), 0.0)
    ]
    var invalid_channel_tap: List[Complex64] = [
        Complex64(1.0, inf[DType.float64]())
    ]
    with assert_raises():
        _ = add_awgn(
            Span(invalid_channel_sample), 0.1, seed=UInt64(1)
        )
    with assert_raises():
        _ = apply_cfo(Span(invalid_channel_sample), 0.1)
    with assert_raises():
        _ = awgn_and_cfo(
            Span(invalid_channel_sample), 0.1, 0.1, seed=UInt64(1)
        )
    with assert_raises():
        _ = apply_integer_timing_offset(Span(invalid_channel_sample), 0)
    with assert_raises():
        _ = apply_multipath(
            Span(samples), Span(invalid_channel_tap)
        )
    with assert_raises():
        _ = apply_rayleigh_fading(
            Span(invalid_channel_sample), seed=UInt64(1)
        )
    with assert_raises():
        _ = apply_rician_fading(
            Span(invalid_channel_sample), 1.0, seed=UInt64(1)
        )
    with assert_raises():
        _ = apply_doppler(Span(invalid_channel_sample), 0.1)
    with assert_raises():
        _ = apply_phase_noise(
            Span(invalid_channel_sample), 0.1, seed=UInt64(1)
        )
    with assert_raises():
        _ = apply_iq_imbalance(Span(invalid_channel_sample), 0.1, 0.1)
    with assert_raises():
        _ = apply_sample_clock_offset(Span(invalid_channel_sample), 1.0)
    var huge_finite: List[Complex64] = [Complex64(1.7e308, 1.7e308)]
    var two_unit_samples: List[Complex64] = [
        Complex64(1.0), Complex64(1.0)
    ]
    # 1e308 is exactly an integer number of cycles/sample in Float64, so all
    # three public paths must reduce it to the identity phasor.
    assert_equal(
        apply_cfo(Span(two_unit_samples), 1.0e308), two_unit_samples
    )
    assert_equal(
        apply_doppler(Span(two_unit_samples), 1.0e308),
        two_unit_samples,
    )
    assert_equal(
        awgn_and_cfo(
            Span(two_unit_samples), 0.0, 1.0e308, seed=UInt64(1)
        ),
        two_unit_samples,
    )
    with assert_raises():
        _ = apply_phase_noise(
            Span(two_unit_samples), 1.7e308, seed=UInt64(12)
        )
    var huge_real: List[Complex64] = [Complex64(1.7e308, 0.0)]
    var overflow_multipath_tap: List[Complex64] = [
        Complex64(2.0, 0.0)
    ]
    with assert_raises():
        _ = apply_multipath(
            Span(huge_real), Span(overflow_multipath_tap)
        )
    with assert_raises():
        _ = apply_rayleigh_fading(
            Span(huge_real), seed=UInt64(6), block_fading=True
        )
    with assert_raises():
        _ = apply_rician_fading(
            Span(huge_real), 0.0, seed=UInt64(6), block_fading=True
        )
    with assert_raises():
        _ = apply_cfo(Span(huge_finite), 0.0, initial_phase=_PI / 4.0)
    with assert_raises():
        _ = apply_doppler(
            Span(huge_finite), 0.0, initial_phase=_PI / 4.0
        )
    with assert_raises():
        _ = apply_phase_noise(
            Span(huge_finite), 0.0, seed=UInt64(1),
            initial_phase=_PI / 4.0,
        )
    with assert_raises():
        _ = apply_iq_imbalance(Span(huge_finite), 0.9, 0.0)


def test_standard_channel_paths_impulse_and_application_cross_evidence() raises:
    # TGn-A is a one-path, zero-delay profile.  It makes each public channel
    # API independently reducible to y[n] = h*x[n] without reconstruction.
    var profile = wifi_tgn_profile(String("A"))
    var paths = realize_standard_channel_paths(
        profile, seed=UInt64(0x13579BDF)
    )
    var paths_again = realize_standard_channel_paths(
        profile, seed=UInt64(0x13579BDF)
    )
    assert_equal(paths, paths_again)
    assert_equal(len(paths), 1)
    var impulse = standard_channel_impulse_response(
        profile, 20.0e6, seed=UInt64(0x13579BDF)
    )
    assert_equal(len(impulse), 1)
    _assert_complex_close(impulse[0], paths[0], 0.0)
    var samples: List[Complex64] = [
        Complex64(1.0, -0.5),
        Complex64(-2.0, 1.25),
        Complex64(0.25, 0.75),
    ]
    var applied = apply_standard_channel(
        Span(samples), profile, 20.0e6, seed=UInt64(0x13579BDF)
    )
    assert_equal(len(applied), len(samples))
    for i in range(len(samples)):
        _assert_complex_close(applied[i], paths[0] * samples[i], 0.0)

    # A fractional TDL impulse must equal independently deposited path
    # coefficients with the documented linear two-bin weights.
    var tdl = tdl_profile(String("A"), desired_delay_spread_ns=100.0)
    var sample_rate = 10.0e6
    var tdl_paths = realize_standard_channel_paths(
        tdl, seed=UInt64(77)
    )
    var tdl_impulse = standard_channel_impulse_response(
        tdl, sample_rate, seed=UInt64(77)
    )
    var expected = List[Complex64](
        length=len(tdl_impulse), fill=Complex64(0.0, 0.0)
    )
    for path in range(tdl.path_count()):
        var position = tdl.delay_ns(path) * sample_rate * 1.0e-9
        var left = Int(position)
        var fraction = position - Float64(left)
        expected[left] = expected[left] + Complex64(
            (1.0 - fraction) * tdl_paths[path].re,
            (1.0 - fraction) * tdl_paths[path].im,
        )
        if fraction > 0.0:
            expected[left + 1] = expected[left + 1] + Complex64(
                fraction * tdl_paths[path].re,
                fraction * tdl_paths[path].im,
            )
    _assert_complex_lists_close(tdl_impulse, expected, 2.0e-15)

    var empty = List[Complex64]()
    assert_equal(
        len(apply_standard_channel(
            Span(empty), profile, 20.0e6, seed=UInt64(1)
        )),
        0,
    )
    with assert_raises():
        _ = realize_standard_channel_paths(
            profile, maximum_doppler_hz=-1.0, seed=UInt64(1)
        )
    with assert_raises():
        _ = standard_channel_impulse_response(
            profile, 0.0, seed=UInt64(1)
        )
    with assert_raises():
        _ = apply_standard_channel(
            Span(samples), profile, -1.0, seed=UInt64(1)
        )
    with assert_raises():
        _ = realize_standard_channel_paths(
            profile, time_seconds=nan[DType.float64](), seed=UInt64(1)
        )
    with assert_raises():
        _ = realize_standard_channel_paths(
            profile, maximum_doppler_hz=inf[DType.float64](),
            seed=UInt64(1),
        )
    with assert_raises():
        _ = standard_channel_impulse_response(
            profile, nan[DType.float64](), seed=UInt64(1)
        )
    var invalid_samples: List[Complex64] = [
        Complex64(nan[DType.float64](), 0.0)
    ]
    with assert_raises():
        _ = apply_standard_channel(
            Span(invalid_samples), profile, 20.0e6, seed=UInt64(1)
        )


def test_standard_and_cdl_profile_configuration_edges() raises:
    var offsets = cdl_ray_offsets()
    var expected_offsets: List[Float64] = [
        0.0447, -0.0447, 0.1413, -0.1413, 0.2492, -0.2492,
        0.3715, -0.3715, 0.5129, -0.5129, 0.6797, -0.6797,
        0.8844, -0.8844, 1.1481, -1.1481, 1.5195, -1.5195,
        2.1551, -2.1551,
    ]
    assert_equal(offsets, expected_offsets)
    assert_equal(cdl_ray_offsets(), expected_offsets)
    for pair in range(10):
        _assert_close(offsets[2 * pair], -offsets[2 * pair + 1], 0.0)

    var cdl = cdl_profile(String("A"), desired_delay_spread_ns=37.5)
    var cdl_again = cdl_profile(String("A"), desired_delay_spread_ns=37.5)
    assert_equal(cdl.delays, cdl_again.delays)
    assert_equal(cdl.powers_db, cdl_again.powers_db)
    assert_equal(cdl.aod_deg, cdl_again.aod_deg)
    assert_equal(cdl.aoa_deg, cdl_again.aoa_deg)
    assert_equal(cdl.zod_deg, cdl_again.zod_deg)
    assert_equal(cdl.zoa_deg, cdl_again.zoa_deg)
    assert_equal(cdl.cluster_indices, cdl_again.cluster_indices)
    assert_equal(cdl.path_kinds, cdl_again.path_kinds)
    assert_equal(cdl.component_count(), 23)
    assert_equal(cdl.delay_scale_ns, 37.5)

    var tdl = tdl_profile(String("E"), desired_delay_spread_ns=62.5)
    var tdl_again = tdl_profile(String("E"), desired_delay_spread_ns=62.5)
    assert_equal(tdl.delays, tdl_again.delays)
    assert_equal(tdl.powers_db, tdl_again.powers_db)
    assert_equal(tdl.fading_kinds, tdl_again.fading_kinds)
    assert_equal(tdl.path_count(), 15)
    assert_equal(tdl.delay_scale_ns, 62.5)

    var tgn = wifi_tgn_profile(String("F"), los=True)
    var tgn_again = wifi_tgn_profile(String("F"), los=True)
    assert_equal(tgn.delays, tgn_again.delays)
    assert_equal(tgn.powers_db, tgn_again.powers_db)
    assert_equal(tgn.fading_kinds, tgn_again.fading_kinds)
    assert_equal(tgn.tap_count(), 18)
    assert_equal(tgn.path_count(), 19)

    var tgac = wifi_tgac_profile(String("D"), bandwidth_mhz=160, los=True)
    var tgac_again = wifi_tgac_profile(
        String("D"), bandwidth_mhz=160, los=True
    )
    assert_equal(tgac.delays, tgac_again.delays)
    assert_equal(tgac.powers_db, tgac_again.powers_db)
    assert_equal(tgac.fading_kinds, tgac_again.fading_kinds)
    assert_true(tgac.tap_count() > 18)

    var tgax = wifi_tgax_profile(String("D"), bandwidth_mhz=320, los=True)
    var tgax_again = wifi_tgax_profile(
        String("D"), bandwidth_mhz=320, los=True
    )
    assert_equal(tgax.delays, tgax_again.delays)
    assert_equal(tgax.powers_db, tgax_again.powers_db)
    assert_equal(tgax.fading_kinds, tgax_again.fading_kinds)
    assert_true(tgax.tap_count() > 18)

    with assert_raises():
        _ = cdl_profile(String("Z"))
    with assert_raises():
        _ = cdl_profile(
            String("A"), desired_delay_spread_ns=nan[DType.float64]()
        )
    with assert_raises():
        _ = cdl_profile(
            String("A"), desired_delay_spread_ns=inf[DType.float64]()
        )
    with assert_raises():
        _ = tdl_profile(
            String("A"), desired_delay_spread_ns=nan[DType.float64]()
        )
    with assert_raises():
        _ = tdl_profile(
            String("A"), desired_delay_spread_ns=inf[DType.float64]()
        )
    with assert_raises():
        _ = wifi_tgn_profile(String("Z"))
    with assert_raises():
        _ = wifi_tgac_profile(String("A"), bandwidth_mhz=0)
    with assert_raises():
        _ = wifi_tgac_profile(String("A"), bandwidth_mhz=Int.MIN)
    with assert_raises():
        _ = wifi_tgac_profile(String("A"), bandwidth_mhz=Int.MAX)
    with assert_raises():
        _ = wifi_tgax_profile(String("A"), bandwidth_mhz=1281)
    with assert_raises():
        _ = wifi_tgax_profile(String("A"), bandwidth_mhz=Int.MIN)
    with assert_raises():
        _ = wifi_tgax_profile(String("A"), bandwidth_mhz=Int.MAX)

    var ula = cdl_ula(3, spacing_wavelengths=0.5, axis=0)
    assert_equal(ula.element_count(), 3)
    with assert_raises():
        _ = cdl_ula(0)
    with assert_raises():
        _ = cdl_ula(Int.MIN)
    with assert_raises():
        _ = cdl_ula(Int.MAX)
    with assert_raises():
        _ = cdl_ula(65_537)
    with assert_raises():
        _ = cdl_ula(2, spacing_wavelengths=nan[DType.float64]())
    with assert_raises():
        _ = cdl_ula(2, spacing_wavelengths=inf[DType.float64]())
    with assert_raises():
        _ = cdl_ula(2, axis=3)
    with assert_raises():
        _ = cdl_upa(0, 2)
    with assert_raises():
        _ = cdl_upa(Int.MIN, 2)
    with assert_raises():
        _ = cdl_upa(Int.MAX, 2)
    with assert_raises():
        _ = cdl_upa(257, 256)
    with assert_raises():
        _ = cdl_upa(
            2, 2, horizontal_spacing_wavelengths=nan[DType.float64]()
        )
    with assert_raises():
        _ = cdl_upa(2, 2, horizontal_axis=1, vertical_axis=1)
    with assert_raises():
        _ = cdl_array_response(ula, nan[DType.float64](), 90.0)
    with assert_raises():
        _ = cdl_array_response(ula, 0.0, inf[DType.float64]())


def test_cdl_ula_upa_seeded_analytic_coordinate_grid() raises:
    var state = UInt64(0xA22A_2026)
    for count in [1, 2, 3, 8, 17]:
        var spacing = 0.125 + Float64(state & UInt64(7)) * 0.125
        state = state * UInt64(6364136223846793005) + UInt64(1)
        for axis in range(3):
            var first = cdl_ula(count, spacing_wavelengths=spacing, axis=axis)
            var second = cdl_ula(count, spacing_wavelengths=spacing, axis=axis)
            assert_equal(first.x_wavelengths, second.x_wavelengths)
            assert_equal(first.y_wavelengths, second.y_wavelengths)
            assert_equal(first.z_wavelengths, second.z_wavelengths)
            for element in range(count):
                var expected = (
                    Float64(element) - 0.5 * Float64(count - 1)
                ) * spacing
                _assert_close(
                    first.x_wavelengths[element], expected if axis == 0 else 0.0, 0.0
                )
                _assert_close(
                    first.y_wavelengths[element], expected if axis == 1 else 0.0, 0.0
                )
                _assert_close(
                    first.z_wavelengths[element], expected if axis == 2 else 0.0, 0.0
                )

    var upa = cdl_upa(
        3, 5, horizontal_spacing_wavelengths=0.4,
        vertical_spacing_wavelengths=0.6, horizontal_axis=0, vertical_axis=2,
    )
    var upa_again = cdl_upa(
        3, 5, horizontal_spacing_wavelengths=0.4,
        vertical_spacing_wavelengths=0.6, horizontal_axis=0, vertical_axis=2,
    )
    assert_equal(upa.x_wavelengths, upa_again.x_wavelengths)
    assert_equal(upa.y_wavelengths, upa_again.y_wavelengths)
    assert_equal(upa.z_wavelengths, upa_again.z_wavelengths)
    for row in range(3):
        for column in range(5):
            var element = row * 5 + column
            _assert_close(
                upa.x_wavelengths[element],
                (Float64(column) - 2.0) * 0.4,
                0.0,
            )
            _assert_close(upa.y_wavelengths[element], 0.0, 0.0)
            _assert_close(
                upa.z_wavelengths[element],
                (Float64(row) - 1.0) * 0.6,
                0.0,
            )


def test_cdl_geometry_rays_realization_and_matvec_oracles() raises:
    var array = cdl_ula(2, spacing_wavelengths=0.5, axis=1)
    var response = cdl_array_response(array, 90.0, 90.0)
    assert_equal(len(response), 2)
    _assert_complex_close(response[0], Complex64(0.0, -1.0), 2.0e-15)
    _assert_complex_close(response[1], Complex64(0.0, 1.0), 2.0e-15)

    var profile = cdl_profile(String("D"))
    var los_angles = cdl_ray_angles(profile, 0, seed=UInt64(123))
    assert_equal(los_angles.ray_count(), 1)
    _assert_close(los_angles.aod_deg[0], profile.aod_deg[0], 0.0)
    _assert_close(los_angles.aoa_deg[0], profile.aoa_deg[0], 0.0)
    var diffuse_angles = cdl_ray_angles(
        profile, 1, seed=UInt64(0xCAFEBABE)
    )
    var diffuse_again = cdl_ray_angles(
        profile, 1, seed=UInt64(0xCAFEBABE)
    )
    assert_equal(diffuse_angles.aod_deg, diffuse_again.aod_deg)
    assert_equal(diffuse_angles.aoa_deg, diffuse_again.aoa_deg)
    assert_equal(diffuse_angles.ray_count(), 20)

    var los_polarization = cdl_ray_polarization_matrix(
        profile, 0, 0, seed=UInt64(999)
    )
    assert_equal(los_polarization.theta_theta, Complex64(1.0, 0.0))
    assert_equal(los_polarization.theta_phi, Complex64(0.0, 0.0))
    assert_equal(los_polarization.phi_theta, Complex64(0.0, 0.0))
    assert_equal(los_polarization.phi_phi, Complex64(-1.0, 0.0))
    var diffuse_polarization = cdl_ray_polarization_matrix(
        profile, 1, 7, seed=UInt64(999)
    )
    _assert_close(
        diffuse_polarization.theta_theta.magnitude_squared(), 1.0, 2.0e-15
    )
    _assert_close(
        diffuse_polarization.theta_phi.magnitude_squared(),
        1.0 / profile.xpr_linear(),
        2.0e-15,
    )

    var scalar = cdl_ula(1)
    var scalar_response = cdl_array_response(scalar, 0.0, 0.0)
    assert_equal(len(scalar_response), 1)
    _assert_complex_close(
        scalar_response[0], Complex64(1.0, 0.0), 0.0
    )
    var channel = realize_cdl_channel(
        profile,
        scalar,
        scalar,
        seed=UInt64(456),
        carrier_frequency_hz=299792458.0,
        link_distance_m=0.0,
    )
    var channel_again = realize_cdl_channel(
        profile,
        scalar,
        scalar,
        seed=UInt64(456),
        carrier_frequency_hz=299792458.0,
        link_distance_m=0.0,
    )
    assert_equal(channel.coefficients, channel_again.coefficients)
    assert_equal(channel.receive_count, 1)
    assert_equal(channel.transmit_count, 1)
    var powers = profile.normalized_linear_powers()
    _assert_close(
        channel.coefficient(0, 0, 0).magnitude_squared(),
        powers[0],
        3.0e-15,
    )
    var transmit: List[Complex64] = [Complex64(0.75, -0.25)]
    var output = apply_cdl_narrowband(channel, transmit)
    var matrix = channel.narrowband()
    _assert_complex_close(output[0], matrix[0] * transmit[0], 0.0)

    with assert_raises():
        _ = cdl_ray_angles(profile, -1, seed=UInt64(1))
    with assert_raises():
        _ = cdl_ray_polarization_matrix(
            profile, 0, 1, seed=UInt64(1)
        )
    with assert_raises():
        _ = realize_cdl_channel(
            profile, scalar, scalar, seed=UInt64(1),
            carrier_frequency_hz=0.0,
        )
    with assert_raises():
        _ = realize_cdl_channel(
            profile, scalar, scalar, seed=UInt64(1),
            time_seconds=nan[DType.float64](),
        )
    with assert_raises():
        _ = realize_cdl_channel(
            profile, scalar, scalar, seed=UInt64(1),
            carrier_frequency_hz=inf[DType.float64](),
        )
    with assert_raises():
        _ = realize_cdl_channel(
            profile, scalar, scalar, seed=UInt64(1),
            speed_mps=nan[DType.float64](),
        )
    with assert_raises():
        _ = channel.frequency_response(nan[DType.float64]())
    var wrong_transmit: List[Complex64] = [
        Complex64(1.0), Complex64(2.0)
    ]
    with assert_raises():
        _ = apply_cdl_narrowband(channel, wrong_transmit)
    var invalid_transmit: List[Complex64] = [
        Complex64(inf[DType.float64](), 0.0)
    ]
    with assert_raises():
        _ = apply_cdl_narrowband(channel, invalid_transmit)


def test_repetition_detector_against_first_crossing_formula() raises:
    var samples: List[Complex64] = [
        Complex64(0.0), Complex64(0.0), Complex64(0.0),
        Complex64(1.0, 0.5),
        Complex64(-0.5, 1.0),
        Complex64(2.0, -1.0),
        Complex64(0.25, 0.75),
        Complex64(1.0, 0.5),
        Complex64(-0.5, 1.0),
        Complex64(2.0, -1.0),
        Complex64(0.25, 0.75),
    ]
    assert_equal(detect_repetition_start(Span(samples), 4, 4, 0.999), 3)
    # Scaling and common rotation cannot change normalized first crossing.
    var transformed = List[Complex64](capacity=len(samples))
    var rotation = Complex64(cos(0.7), sin(0.7))
    for sample in samples:
        transformed.append(Complex64(3.5 * sample.re, 3.5 * sample.im) * rotation)
    assert_equal(
        detect_repetition_start(Span(transformed), 4, 4, 0.999), 3
    )
    var noise_only: List[Complex64] = [
        Complex64(1.0), Complex64(0.0, 1.0), Complex64(-1.0),
        Complex64(0.0, -1.0), Complex64(0.5), Complex64(-0.25),
        Complex64(0.75), Complex64(-0.6),
    ]
    assert_equal(
        detect_repetition_start(Span(noise_only), 4, 4, 0.99), -1
    )
    with assert_raises():
        _ = detect_repetition_start(Span(samples), 4, 4, -0.1)
    with assert_raises():
        _ = detect_repetition_start(
            Span(samples), 4, 4, nan[DType.float64]()
        )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
