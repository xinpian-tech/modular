"""Independent evidence for bounded Clause-30 WUR Data MC-OOK.

Literal geometry, active-tone, and randomizer-state rows are paired with a
separate seven-bit shift-register model and an O(N*K) analytic tone-sum
oracle.  The oracle does not call the production FFT, profile, tone, shift, or
waveform helpers.  Complex waveform comparisons use absolute tolerance
5e-12; discrete tables, state transitions, shapes, and Off symbols are exact.
"""

from std.collections import Span
from std.math import cos, sin, sqrt
from std.testing import (
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
    TestSuite,
)
from std.utils.numerics import inf, nan
from wireless_dsp.core import Complex64
from wireless_dsp.wireless.wifi.wur import (
    WIFI_WUR_DATA_RATE_LDR_BPS,
    WIFI_WUR_DATA_RATE_HDR_BPS,
    WIFI_WUR_SAMPLE_RATE_HZ,
    WIFI_WUR_IDFT_SIZE,
    WIFI_WUR_RANDOMIZER_PERIOD,
    WifiWURDataOOKConfig,
    wifi_wur_data_profile,
    wifi_wur_mc_ook_active_subcarriers,
    wifi_wur_symbol_randomizer_state,
    wifi_wur_symbol_randomizer_cyclic_shift_ns,
    wifi_wur_data_mc_ook_on_symbol,
    wifi_wur_data_mc_ook_off_symbol,
    wifi_wur_data_mc_ook_modulate,
)


comptime _TWO_PI = 6.283185307179586476925286766559


def _config(data_rate_bps: Int) raises -> WifiWURDataOOKConfig:
    return WifiWURDataOOKConfig(
        data_rate_bps,
        WIFI_WUR_SAMPLE_RATE_HZ,
        WIFI_WUR_IDFT_SIZE,
        1,
    )


def _literal_tones(data_rate_bps: Int) -> List[Int]:
    if data_rate_bps == WIFI_WUR_DATA_RATE_LDR_BPS:
        return [-6, -5, -4, -3, -2, -1, 1, 2, 3, 4, 5, 6]
    return [-6, -4, -2, 2, 4, 6]


def _literal_useful_samples(data_rate_bps: Int) -> Int:
    return 64 if data_rate_bps == WIFI_WUR_DATA_RATE_LDR_BPS else 32


def _literal_guard_samples(data_rate_bps: Int) -> Int:
    return 16 if data_rate_bps == WIFI_WUR_DATA_RATE_LDR_BPS else 8


def _literal_sync_symbols(data_rate_bps: Int) -> Int:
    return 64 if data_rate_bps == WIFI_WUR_DATA_RATE_LDR_BPS else 32


def _oracle_randomizer_bits(symbol_index: Int) -> List[UInt8]:
    # Independent register representation: [X7, X6, ..., X1].
    var bits = List[UInt8](length=7, fill=1)
    for _ in range(symbol_index % 127):
        var feedback = bits[0] ^ bits[3]
        for position in range(6):
            bits[position] = bits[position + 1]
        bits[6] = feedback
    return bits^


def _oracle_randomizer_word(symbol_index: Int) -> Int:
    var bits = _oracle_randomizer_bits(symbol_index)
    var word = 0
    for position in range(7):
        word = (word << 1) | Int(bits[position])
    return word


def _oracle_phase_sign(symbol_index: Int) -> Int:
    var bits = _oracle_randomizer_bits(symbol_index)
    return 1 if bits[0] == 0 else -1


def _oracle_shift_index(symbol_index: Int) -> Int:
    var bits = _oracle_randomizer_bits(symbol_index)
    return 4 * Int(bits[4]) + 2 * Int(bits[5]) + Int(bits[6])


def _oracle_on_symbol(
    data_rate_bps: Int,
    coefficients: Span[Complex64, ...],
    data_symbol_index: Int,
) -> List[Complex64]:
    var tones = _literal_tones(data_rate_bps)
    var useful_samples = _literal_useful_samples(data_rate_bps)
    var guard_samples = _literal_guard_samples(data_rate_bps)
    var ppdu_index = (
        _literal_sync_symbols(data_rate_bps) + data_symbol_index % 127
    ) % 127
    var phase_sign = _oracle_phase_sign(ppdu_index)
    var shift_quantum_samples = (
        8 if data_rate_bps == WIFI_WUR_DATA_RATE_LDR_BPS else 4
    )
    var shift_samples = (
        shift_quantum_samples * _oracle_shift_index(ppdu_index)
    )
    var amplitude = sqrt(2.0 / Float64(len(tones)))
    var useful = List[Complex64](capacity=useful_samples)
    for sample in range(useful_samples):
        var source = (sample + shift_samples) % useful_samples
        var real = 0.0
        var imaginary = 0.0
        for tone_index in range(len(tones)):
            var angle = (
                _TWO_PI
                * Float64(tones[tone_index] * source)
                / Float64(WIFI_WUR_IDFT_SIZE)
            )
            var coefficient = coefficients[tone_index]
            real += (
                coefficient.re * cos(angle)
                - coefficient.im * sin(angle)
            )
            imaginary += (
                coefficient.re * sin(angle)
                + coefficient.im * cos(angle)
            )
        useful.append(
            Complex64(
                Float64(phase_sign) * amplitude * real,
                Float64(phase_sign) * amplitude * imaginary,
            )
        )

    var result = List[Complex64](capacity=useful_samples + guard_samples)
    for sample in range(useful_samples - guard_samples, useful_samples):
        result.append(useful[sample])
    for sample in range(useful_samples):
        result.append(useful[sample])
    return result^


def _assert_ints_equal(
    actual: Span[Int, ...], expected: Span[Int, ...]
) raises:
    assert_equal(len(actual), len(expected))
    for index in range(len(actual)):
        assert_equal(actual[index], expected[index])


def _assert_complex_close(
    actual: Span[Complex64, ...],
    expected: Span[Complex64, ...],
    tolerance: Float64 = 5.0e-12,
) raises:
    assert_equal(len(actual), len(expected))
    for index in range(len(actual)):
        assert_almost_equal(
            actual[index].re, expected[index].re, atol=tolerance
        )
        assert_almost_equal(
            actual[index].im, expected[index].im, atol=tolerance
        )


def test_published_profiles_and_active_tone_rows_exact() raises:
    assert_equal(WIFI_WUR_DATA_RATE_LDR_BPS, 62_500)
    assert_equal(WIFI_WUR_DATA_RATE_HDR_BPS, 250_000)
    assert_equal(WIFI_WUR_SAMPLE_RATE_HZ, 20_000_000)
    assert_equal(WIFI_WUR_IDFT_SIZE, 64)
    assert_equal(WIFI_WUR_RANDOMIZER_PERIOD, 127)

    var ldr = _config(WIFI_WUR_DATA_RATE_LDR_BPS)
    var ldr_profile = wifi_wur_data_profile(ldr)
    assert_equal(ldr_profile.data_rate_bps, 62_500)
    assert_equal(ldr_profile.data_symbol_duration_ns, 4_000)
    assert_equal(ldr_profile.useful_samples, 64)
    assert_equal(ldr_profile.guard_interval_samples, 16)
    assert_equal(ldr_profile.total_symbol_samples, 80)
    assert_equal(ldr_profile.active_subcarriers, 12)
    assert_equal(ldr_profile.sync_duration_ns, 128_000)
    assert_equal(ldr_profile.sync_randomizer_symbols, 64)
    var ldr_tones = wifi_wur_mc_ook_active_subcarriers(ldr)
    var expected_ldr = _literal_tones(WIFI_WUR_DATA_RATE_LDR_BPS)
    _assert_ints_equal(Span(ldr_tones), Span(expected_ldr))

    var hdr = _config(WIFI_WUR_DATA_RATE_HDR_BPS)
    var hdr_profile = wifi_wur_data_profile(hdr)
    assert_equal(hdr_profile.data_rate_bps, 250_000)
    assert_equal(hdr_profile.data_symbol_duration_ns, 2_000)
    assert_equal(hdr_profile.useful_samples, 32)
    assert_equal(hdr_profile.guard_interval_samples, 8)
    assert_equal(hdr_profile.total_symbol_samples, 40)
    assert_equal(hdr_profile.active_subcarriers, 6)
    assert_equal(hdr_profile.sync_duration_ns, 64_000)
    assert_equal(hdr_profile.sync_randomizer_symbols, 32)
    var hdr_tones = wifi_wur_mc_ook_active_subcarriers(hdr)
    var expected_hdr = _literal_tones(WIFI_WUR_DATA_RATE_HDR_BPS)
    _assert_ints_equal(Span(hdr_tones), Span(expected_hdr))


def test_randomizer_literal_prefix_full_period_and_shift_tables() raises:
    var expected_words: List[Int] = [127, 126, 124, 120, 112, 97, 67]
    var expected_indices: List[Int] = [7, 6, 4, 0, 0, 1, 3]
    var ldr = _config(WIFI_WUR_DATA_RATE_LDR_BPS)
    var hdr = _config(WIFI_WUR_DATA_RATE_HDR_BPS)
    for index in range(len(expected_words)):
        var state = wifi_wur_symbol_randomizer_state(index)
        assert_equal(state.lfsr_x7_to_x1, expected_words[index])
        assert_equal(state.phase_sign, -1)
        assert_equal(state.cyclic_shift_index, expected_indices[index])
        assert_equal(
            wifi_wur_symbol_randomizer_cyclic_shift_ns(ldr, index),
            -400 * expected_indices[index],
        )
        assert_equal(
            wifi_wur_symbol_randomizer_cyclic_shift_ns(hdr, index),
            -200 * expected_indices[index],
        )

    var seen = List[Bool](length=128, fill=False)
    var seen_shift = List[Bool](length=8, fill=False)
    for index in range(127):
        var state = wifi_wur_symbol_randomizer_state(index)
        assert_equal(state.lfsr_x7_to_x1, _oracle_randomizer_word(index))
        assert_equal(state.phase_sign, _oracle_phase_sign(index))
        assert_equal(state.cyclic_shift_index, _oracle_shift_index(index))
        assert_true(state.lfsr_x7_to_x1 != 0)
        assert_true(not seen[state.lfsr_x7_to_x1])
        seen[state.lfsr_x7_to_x1] = True
        seen_shift[state.cyclic_shift_index] = True
        assert_equal(
            wifi_wur_symbol_randomizer_cyclic_shift_ns(ldr, index),
            -400 * state.cyclic_shift_index,
        )
        assert_equal(
            wifi_wur_symbol_randomizer_cyclic_shift_ns(hdr, index),
            -200 * state.cyclic_shift_index,
        )
        var periodic = wifi_wur_symbol_randomizer_state(index + 127)
        assert_equal(periodic.lfsr_x7_to_x1, state.lfsr_x7_to_x1)
        assert_equal(periodic.phase_sign, state.phase_sign)
        assert_equal(periodic.cyclic_shift_index, state.cyclic_shift_index)
    for shift_index in range(8):
        assert_true(seen_shift[shift_index])

    var maximum = wifi_wur_symbol_randomizer_state(Int.MAX)
    assert_equal(maximum.lfsr_x7_to_x1, _oracle_randomizer_word(Int.MAX))
    assert_equal(maximum.phase_sign, _oracle_phase_sign(Int.MAX))
    assert_equal(maximum.cyclic_shift_index, _oracle_shift_index(Int.MAX))


def test_static_on_off_waveforms_against_analytic_oracle() raises:
    var ldr = _config(WIFI_WUR_DATA_RATE_LDR_BPS)
    var ldr_coefficients = List[Complex64](capacity=12)
    for index in range(12):
        ldr_coefficients.append(
            Complex64(1.0 if index % 3 != 1 else -1.0, 0.0)
        )
    var actual_ldr = wifi_wur_data_mc_ook_on_symbol(
        ldr, Span(ldr_coefficients), 47
    )
    var expected_ldr = _oracle_on_symbol(
        WIFI_WUR_DATA_RATE_LDR_BPS, Span(ldr_coefficients), 47
    )
    _assert_complex_close(Span(actual_ldr), Span(expected_ldr))
    assert_equal(len(actual_ldr), 80)
    for sample in range(16):
        assert_equal(actual_ldr[sample], actual_ldr[64 + sample])

    var hdr = _config(WIFI_WUR_DATA_RATE_HDR_BPS)
    var hdr_coefficients = List[Complex64](
        length=6, fill=Complex64(1.0, 0.0)
    )
    var actual_hdr = wifi_wur_data_mc_ook_on_symbol(
        hdr, Span(hdr_coefficients), 2
    )
    var expected_hdr = _oracle_on_symbol(
        WIFI_WUR_DATA_RATE_HDR_BPS, Span(hdr_coefficients), 2
    )
    _assert_complex_close(Span(actual_hdr), Span(expected_hdr))
    assert_equal(len(actual_hdr), 40)
    assert_almost_equal(actual_hdr[8].re, sqrt(12.0), atol=5.0e-12)
    assert_almost_equal(actual_hdr[8].im, 0.0, atol=5.0e-12)
    for sample in range(8):
        assert_equal(actual_hdr[sample], actual_hdr[32 + sample])

    var ldr_off = wifi_wur_data_mc_ook_off_symbol(ldr)
    var hdr_off = wifi_wur_data_mc_ook_off_symbol(hdr)
    assert_equal(len(ldr_off), 80)
    assert_equal(len(hdr_off), 40)
    for sample in range(len(ldr_off)):
        assert_equal(ldr_off[sample], Complex64(0.0, 0.0))
    for sample in range(len(hdr_off)):
        assert_equal(hdr_off[sample], Complex64(0.0, 0.0))


def test_static_already_encoded_modulation_full_output() raises:
    var decisions: List[UInt8] = [0, 1, 1, 0, 1]
    for data_rate_bps in [
        WIFI_WUR_DATA_RATE_LDR_BPS, WIFI_WUR_DATA_RATE_HDR_BPS
    ]:
        var config = _config(data_rate_bps)
        var tones = _literal_tones(data_rate_bps)
        var coefficients = List[Complex64](capacity=len(tones))
        for tone in range(len(tones)):
            coefficients.append(
                Complex64(1.0 if tone % 2 == 0 else -1.0, 0.0)
            )
        var actual = wifi_wur_data_mc_ook_modulate(
            config, Span(decisions), Span(coefficients)
        )
        var one_length = (
            _literal_useful_samples(data_rate_bps)
            + _literal_guard_samples(data_rate_bps)
        )
        assert_equal(len(actual), len(decisions) * one_length)
        for symbol in range(len(decisions)):
            if decisions[symbol] == 0:
                for sample in range(one_length):
                    assert_equal(
                        actual[symbol * one_length + sample],
                        Complex64(0.0, 0.0),
                    )
            else:
                var expected = _oracle_on_symbol(
                    data_rate_bps, Span(coefficients), symbol
                )
                for sample in range(one_length):
                    assert_almost_equal(
                        actual[symbol * one_length + sample].re,
                        expected[sample].re,
                        atol=5.0e-12,
                    )
                    assert_almost_equal(
                        actual[symbol * one_length + sample].im,
                        expected[sample].im,
                        atol=5.0e-12,
                    )


def test_seeded_differential_and_periodicity_properties() raises:
    var seed = UInt64(0x80211_2024_57555230)
    for iteration in range(1021):
        seed = (
            seed * UInt64(6364136223846793005)
            + UInt64(1442695040888963407)
        )
        var data_rate_bps = (
            WIFI_WUR_DATA_RATE_LDR_BPS
            if (seed & UInt64(1)) == 0
            else WIFI_WUR_DATA_RATE_HDR_BPS
        )
        var config = _config(data_rate_bps)
        var tones = _literal_tones(data_rate_bps)
        var coefficients = List[Complex64](capacity=len(tones))
        for _ in range(len(tones)):
            seed = (
                seed * UInt64(6364136223846793005)
                + UInt64(1442695040888963407)
            )
            coefficients.append(
                Complex64(1.0 if (seed & UInt64(1)) == 0 else -1.0, 0.0)
            )
        var data_symbol_index = Int((seed >> 17) % UInt64(100_000))
        if iteration == 1020:
            data_symbol_index = Int.MAX
        var actual = wifi_wur_data_mc_ook_on_symbol(
            config, Span(coefficients), data_symbol_index
        )
        var expected = _oracle_on_symbol(
            data_rate_bps, Span(coefficients), data_symbol_index
        )
        _assert_complex_close(Span(actual), Span(expected))
        if data_symbol_index <= Int.MAX - 127:
            var periodic = wifi_wur_data_mc_ook_on_symbol(
                config, Span(coefficients), data_symbol_index + 127
            )
            _assert_complex_close(Span(periodic), Span(actual), 0.0)

        var decisions = List[UInt8](capacity=1 + iteration % 4)
        for _ in range(1 + iteration % 4):
            seed = (
                seed * UInt64(6364136223846793005)
                + UInt64(1442695040888963407)
            )
            decisions.append(UInt8(seed & UInt64(1)))
        var modulated = wifi_wur_data_mc_ook_modulate(
            config, Span(decisions), Span(coefficients)
        )
        var symbol_samples = (
            _literal_useful_samples(data_rate_bps)
            + _literal_guard_samples(data_rate_bps)
        )
        assert_equal(len(modulated), len(decisions) * symbol_samples)
        for symbol in range(len(decisions)):
            if decisions[symbol] == 0:
                for sample in range(symbol_samples):
                    assert_equal(
                        modulated[symbol * symbol_samples + sample],
                        Complex64(0.0, 0.0),
                    )
            else:
                var oracle = _oracle_on_symbol(
                    data_rate_bps, Span(coefficients), symbol
                )
                for sample in range(symbol_samples):
                    assert_almost_equal(
                        modulated[symbol * symbol_samples + sample].re,
                        oracle[sample].re,
                        atol=5.0e-12,
                    )
                    assert_almost_equal(
                        modulated[symbol * symbol_samples + sample].im,
                        oracle[sample].im,
                        atol=5.0e-12,
                    )


def test_public_mutation_nonfinite_shape_and_integer_edges() raises:
    for invalid_rate in [Int.MIN, -1, 0, 62_501, 249_999, Int.MAX]:
        with assert_raises():
            _ = WifiWURDataOOKConfig(invalid_rate, 20_000_000, 64, 1)
    for invalid_sample_rate in [Int.MIN, -1, 0, 19_999_999, Int.MAX]:
        with assert_raises():
            _ = WifiWURDataOOKConfig(62_500, invalid_sample_rate, 64, 1)
    for invalid_idft in [Int.MIN, -1, 0, 32, 63, 65, Int.MAX]:
        with assert_raises():
            _ = WifiWURDataOOKConfig(62_500, 20_000_000, invalid_idft, 1)
    for invalid_chains in [Int.MIN, -1, 0, 2, Int.MAX]:
        with assert_raises():
            _ = WifiWURDataOOKConfig(62_500, 20_000_000, 64, invalid_chains)

    var coefficients = List[Complex64](
        length=12, fill=Complex64(1.0, 0.0)
    )
    var decisions: List[UInt8] = [1]
    var mutable = _config(WIFI_WUR_DATA_RATE_LDR_BPS)
    mutable.data_rate_bps = 0
    with assert_raises():
        _ = wifi_wur_data_profile(mutable)
    mutable.data_rate_bps = WIFI_WUR_DATA_RATE_LDR_BPS
    mutable.sample_rate_hz = Int.MAX
    with assert_raises():
        _ = wifi_wur_mc_ook_active_subcarriers(mutable)
    mutable.sample_rate_hz = WIFI_WUR_SAMPLE_RATE_HZ
    mutable.idft_size = 32
    with assert_raises():
        _ = wifi_wur_symbol_randomizer_cyclic_shift_ns(mutable, 0)
    mutable.idft_size = WIFI_WUR_IDFT_SIZE
    mutable.transmit_chains = 2
    with assert_raises():
        _ = wifi_wur_data_mc_ook_on_symbol(
            mutable, Span(coefficients), 0
        )
    with assert_raises():
        _ = wifi_wur_data_mc_ook_off_symbol(mutable)
    with assert_raises():
        _ = wifi_wur_data_mc_ook_modulate(
            mutable, Span(decisions), Span(coefficients)
        )

    var valid = _config(WIFI_WUR_DATA_RATE_LDR_BPS)
    with assert_raises():
        _ = wifi_wur_symbol_randomizer_state(Int.MIN)
    with assert_raises():
        _ = wifi_wur_symbol_randomizer_state(-1)
    with assert_raises():
        _ = wifi_wur_symbol_randomizer_cyclic_shift_ns(valid, -1)
    with assert_raises():
        _ = wifi_wur_data_mc_ook_on_symbol(valid, Span(coefficients), -1)

    var empty_coefficients = List[Complex64]()
    var short_coefficients = List[Complex64](
        length=11, fill=Complex64(1.0, 0.0)
    )
    var long_coefficients = List[Complex64](
        length=13, fill=Complex64(1.0, 0.0)
    )
    with assert_raises():
        _ = wifi_wur_data_mc_ook_on_symbol(
            valid, Span(empty_coefficients), 0
        )
    with assert_raises():
        _ = wifi_wur_data_mc_ook_on_symbol(
            valid, Span(short_coefficients), 0
        )
    with assert_raises():
        _ = wifi_wur_data_mc_ook_on_symbol(
            valid, Span(long_coefficients), 0
        )

    coefficients[0] = Complex64(nan[DType.float64](), 0.0)
    with assert_raises():
        _ = wifi_wur_data_mc_ook_on_symbol(valid, Span(coefficients), 0)
    coefficients[0] = Complex64(0.0, inf[DType.float64]())
    with assert_raises():
        _ = wifi_wur_data_mc_ook_modulate(
            valid, Span(decisions), Span(coefficients)
        )
    coefficients[0] = Complex64(-inf[DType.float64](), 0.0)
    with assert_raises():
        _ = wifi_wur_data_mc_ook_on_symbol(valid, Span(coefficients), 0)
    coefficients[0] = Complex64(Float64.MAX_FINITE, 0.0)
    with assert_raises():
        _ = wifi_wur_data_mc_ook_on_symbol(valid, Span(coefficients), 0)
    coefficients[0] = Complex64(0.0, 1.0)
    with assert_raises():
        _ = wifi_wur_data_mc_ook_on_symbol(valid, Span(coefficients), 0)
    coefficients[0] = Complex64(1.0, 0.0)

    var empty_decisions = List[UInt8]()
    with assert_raises():
        _ = wifi_wur_data_mc_ook_modulate(
            valid, Span(empty_decisions), Span(coefficients)
        )
    var nonbinary: List[UInt8] = [0, 1, 2]
    with assert_raises():
        _ = wifi_wur_data_mc_ook_modulate(
            valid, Span(nonbinary), Span(coefficients)
        )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
