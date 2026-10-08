"""Independent exact evidence for bounded Clause-20 DMG Golay algorithms.

The six static oracles encode Tables 20-23 through 20-28 as independent
MSB-first octets with +1 represented by one.  The control-STF oracle composes
those bytes independently, and the pi/2-BPSK oracle uses an explicit four-axis
lookup.  Correlation evidence covers every legal lag plus seeded arbitrary
bipolar pairs using a separate Int128 accumulator.  Discrete comparisons use
exact zero tolerance.
"""

from std.collections import Span
from std.testing import assert_equal, assert_raises, assert_true, TestSuite
from std.utils.numerics import inf, nan
from wireless_dsp.core import Complex64
from wireless_dsp.wireless.wifi.dmg import (
    WIFI_DMG_GOLAY_MIN_LENGTH,
    WIFI_DMG_GOLAY_MAX_LENGTH,
    WIFI_DMG_CONTROL_STF_GB_REPETITIONS,
    WIFI_DMG_CONTROL_STF_SEQUENCE_COUNT,
    WIFI_DMG_CONTROL_STF_CHIPS,
    wifi_dmg_golay_sequence,
    wifi_dmg_pi_over_2_bpsk_modulate,
    wifi_dmg_pi_over_2_bpsk_demodulate_exact,
    wifi_dmg_control_stf_chips,
    wifi_dmg_golay_complementary_autocorrelation,
)


def _oracle_octets(length: Int, is_ga: Bool) -> List[UInt8]:
    if length == 32:
        if is_ga:
            return [0xFA, 0x39, 0xC9, 0x0A]
        return [0x05, 0xC6, 0xC9, 0x0A]
    if length == 64:
        if is_ga:
            return [
                0x28, 0xD8, 0x28, 0x27,
                0x28, 0xD8, 0xD7, 0xD8,
            ]
        return [
            0xD7, 0x27, 0xD7, 0xD8,
            0x28, 0xD8, 0xD7, 0xD8,
        ]
    if is_ga:
        return [
            0xC0, 0x59, 0xCF, 0x56,
            0x3F, 0xA6, 0xCF, 0x56,
            0xC0, 0x59, 0xCF, 0x56,
            0xC0, 0x59, 0x30, 0xA9,
        ]
    return [
        0x3F, 0xA6, 0x30, 0xA9,
        0xC0, 0x59, 0x30, 0xA9,
        0xC0, 0x59, 0xCF, 0x56,
        0xC0, 0x59, 0x30, 0xA9,
    ]


def _oracle_sequence(length: Int, is_ga: Bool) -> List[Int]:
    var octets = _oracle_octets(length, is_ga)
    var result = List[Int](capacity=length)
    for index in range(length):
        var octet = Int(octets[index // 8])
        var bit = (octet >> (7 - (index & 7))) & 1
        result.append(1 if bit == 1 else -1)
    return result^


struct _OraclePair(Movable):
    var ga: List[Int]
    var gb: List[Int]

    def __init__(out self, var ga: List[Int], var gb: List[Int]):
        self.ga = ga^
        self.gb = gb^


def _oracle_recursive_pair(length: Int) -> _OraclePair:
    var delays: List[Int]
    var signs: List[Int]
    if length == 32:
        delays = [1, 4, 8, 2, 16]
        signs = [-1, 1, -1, 1, -1]
    elif length == 64:
        delays = [2, 1, 4, 8, 16, 32]
        signs = [1, 1, -1, -1, 1, -1]
    else:
        delays = [1, 8, 2, 4, 16, 32, 64]
        signs = [-1, -1, -1, -1, 1, -1, -1]

    var a = List[Int](capacity=length)
    var b = List[Int](capacity=length)
    for index in range(length):
        a.append(1 if index == 0 else 0)
        b.append(1 if index == 0 else 0)
    for stage in range(len(delays)):
        var next_a = List[Int](capacity=length)
        var next_b = List[Int](capacity=length)
        for index in range(length):
            var undelayed = signs[stage] * a[index]
            var delayed = (
                b[index - delays[stage]]
                if index >= delays[stage]
                else 0
            )
            next_a.append(undelayed + delayed)
            next_b.append(undelayed - delayed)
        a = next_a^
        b = next_b^

    var ga = List[Int](capacity=length)
    var gb = List[Int](capacity=length)
    for index in range(length):
        ga.append(a[length - index - 1])
        gb.append(b[length - index - 1])
    return _OraclePair(ga^, gb^)


def _assert_int_lists_equal(
    actual: Span[Int, ...], expected: Span[Int, ...]
) raises:
    assert_equal(len(actual), len(expected))
    for index in range(len(actual)):
        assert_equal(actual[index], expected[index])


def _oracle_pi_over_2(
    chips: Span[Int, ...], start_chip_index: Int
) -> List[Complex64]:
    var phase_real: List[Float64] = [1.0, 0.0, -1.0, 0.0]
    var phase_imag: List[Float64] = [0.0, 1.0, 0.0, -1.0]
    var result = List[Complex64](capacity=len(chips))
    var start_phase = start_chip_index & 3
    for index in range(len(chips)):
        var phase = (start_phase + (index & 3)) & 3
        result.append(
            Complex64(
                Float64(chips[index]) * phase_real[phase],
                Float64(chips[index]) * phase_imag[phase],
            )
        )
    return result^


def _assert_complex_lists_equal(
    actual: Span[Complex64, ...], expected: Span[Complex64, ...]
) raises:
    assert_equal(len(actual), len(expected))
    for index in range(len(actual)):
        assert_equal(actual[index].re, expected[index].re)
        assert_equal(actual[index].im, expected[index].im)


def _oracle_complementary_correlation(
    ga: Span[Int, ...], gb: Span[Int, ...], lag: Int
) -> Int:
    # For bipolar values, sum(x*y) = pair_count - 2*mismatch_count.  Counting
    # equality is structurally independent from the production multiply-add.
    var pair_count = len(ga) - lag
    var mismatches = 0
    for index in range(pair_count):
        if ga[index] != ga[index + lag]:
            mismatches += 1
        if gb[index] != gb[index + lag]:
            mismatches += 1
    return 2 * pair_count - 2 * mismatches


def test_clause_20_11_all_six_normative_tables_exact() raises:
    assert_equal(WIFI_DMG_GOLAY_MIN_LENGTH, 32)
    assert_equal(WIFI_DMG_GOLAY_MAX_LENGTH, 128)
    var lengths: List[Int] = [32, 64, 128]
    for length in lengths:
        for selector in range(2):
            var is_ga = selector == 0
            var actual = wifi_dmg_golay_sequence(length, is_ga)
            var expected = _oracle_sequence(length, is_ga)
            _assert_int_lists_equal(Span(actual), Span(expected))
        var recursive = _oracle_recursive_pair(length)
        var actual_ga = wifi_dmg_golay_sequence(length, True)
        var actual_gb = wifi_dmg_golay_sequence(length, False)
        _assert_int_lists_equal(Span(actual_ga), Span(recursive.ga))
        _assert_int_lists_equal(Span(actual_gb), Span(recursive.gb))


def test_pi_over_2_bpsk_static_axes_and_exact_inverse() raises:
    var lengths: List[Int] = [32, 64, 128]
    for length in lengths:
        for selector in range(2):
            var chips = wifi_dmg_golay_sequence(length, selector == 0)
            for start in range(4):
                var actual = wifi_dmg_pi_over_2_bpsk_modulate(
                    Span(chips), start_chip_index=start
                )
                var expected = _oracle_pi_over_2(Span(chips), start)
                _assert_complex_lists_equal(Span(actual), Span(expected))
                var decoded = wifi_dmg_pi_over_2_bpsk_demodulate_exact(
                    Span(actual), start_chip_index=start
                )
                _assert_int_lists_equal(Span(decoded), Span(chips))


def test_control_stf_full_static_composition_and_waveform() raises:
    assert_equal(WIFI_DMG_CONTROL_STF_GB_REPETITIONS, 48)
    assert_equal(WIFI_DMG_CONTROL_STF_SEQUENCE_COUNT, 50)
    assert_equal(WIFI_DMG_CONTROL_STF_CHIPS, 6400)
    var ga = _oracle_sequence(128, True)
    var gb = _oracle_sequence(128, False)
    var expected = List[Int](capacity=WIFI_DMG_CONTROL_STF_CHIPS)
    for _ in range(48):
        for index in range(128):
            expected.append(gb[index])
    for index in range(128):
        expected.append(-gb[index])
    for index in range(128):
        expected.append(-ga[index])

    var actual = wifi_dmg_control_stf_chips()
    _assert_int_lists_equal(Span(actual), Span(expected))
    assert_equal(actual[48 * 128 - 1], gb[127])
    assert_equal(actual[48 * 128], -gb[0])
    assert_equal(actual[49 * 128], -ga[0])
    assert_equal(actual[WIFI_DMG_CONTROL_STF_CHIPS - 1], -ga[127])

    var waveform = wifi_dmg_pi_over_2_bpsk_modulate(Span(actual))
    var expected_waveform = _oracle_pi_over_2(Span(expected), 0)
    _assert_complex_lists_equal(Span(waveform), Span(expected_waveform))
    var decoded = wifi_dmg_pi_over_2_bpsk_demodulate_exact(Span(waveform))
    _assert_int_lists_equal(Span(decoded), Span(expected))


def test_every_complementary_lag_exact_analytic_oracle() raises:
    var lengths: List[Int] = [32, 64, 128]
    for length in lengths:
        var ga = wifi_dmg_golay_sequence(length, True)
        var gb = wifi_dmg_golay_sequence(length, False)
        for lag in range(length):
            var actual = wifi_dmg_golay_complementary_autocorrelation(
                Span(ga), Span(gb), lag
            )
            assert_equal(
                actual,
                _oracle_complementary_correlation(Span(ga), Span(gb), lag),
            )
            assert_equal(actual, 2 * length if lag == 0 else 0)


def test_seeded_mutable_bipolar_differential_properties() raises:
    var seed = UInt64(0x80211AD2024)
    var lengths: List[Int] = [32, 64, 128]
    for _ in range(1021):
        seed = (
            seed * UInt64(6364136223846793005)
            + UInt64(1442695040888963407)
        )
        var length = lengths[Int((seed >> 17) % UInt64(3))]
        var first = wifi_dmg_golay_sequence(length, True)
        var second = wifi_dmg_golay_sequence(length, False)
        for index in range(length):
            seed = (
                seed * UInt64(6364136223846793005)
                + UInt64(1442695040888963407)
            )
            first[index] = 1 if (seed & UInt64(1)) == 0 else -1
            second[index] = 1 if (seed & UInt64(2)) == 0 else -1
        var lag = Int((seed >> 32) % UInt64(length))
        assert_equal(
            wifi_dmg_golay_complementary_autocorrelation(
                Span(first), Span(second), lag
            ),
            _oracle_complementary_correlation(
                Span(first), Span(second), lag
            ),
        )
        var start = Int((seed >> 7) & UInt64(0x7FFFFFFF))
        var waveform = wifi_dmg_pi_over_2_bpsk_modulate(
            Span(first), start_chip_index=start
        )
        var expected = _oracle_pi_over_2(Span(first), start)
        _assert_complex_lists_equal(Span(waveform), Span(expected))
        var decoded = wifi_dmg_pi_over_2_bpsk_demodulate_exact(
            Span(waveform), start_chip_index=start
        )
        _assert_int_lists_equal(Span(decoded), Span(first))


def test_public_edges_mutation_nonfinite_and_int_extremes() raises:
    for length in [Int.MIN, -1, 0, 31, 33, 63, 65, 127, 129, Int.MAX]:
        with assert_raises():
            _ = wifi_dmg_golay_sequence(length, True)

    var empty = List[Int]()
    with assert_raises():
        _ = wifi_dmg_pi_over_2_bpsk_modulate(Span(empty))
    var empty_symbols = List[Complex64]()
    with assert_raises():
        _ = wifi_dmg_pi_over_2_bpsk_demodulate_exact(Span(empty_symbols))
    var short = List[Int](capacity=31)
    var short_symbols = List[Complex64](capacity=31)
    for _ in range(31):
        short.append(1)
        short_symbols.append(Complex64(1.0, 0.0))
    with assert_raises():
        _ = wifi_dmg_pi_over_2_bpsk_modulate(Span(short))
    with assert_raises():
        _ = wifi_dmg_pi_over_2_bpsk_demodulate_exact(Span(short_symbols))

    var ga32 = wifi_dmg_golay_sequence(32, True)
    var gb32 = wifi_dmg_golay_sequence(32, False)
    var gb64 = wifi_dmg_golay_sequence(64, False)
    ga32[7] = 0
    with assert_raises():
        _ = wifi_dmg_pi_over_2_bpsk_modulate(Span(ga32))
    with assert_raises():
        _ = wifi_dmg_golay_complementary_autocorrelation(
            Span(ga32), Span(gb32), 0
        )
    ga32[7] = 1
    with assert_raises():
        _ = wifi_dmg_golay_complementary_autocorrelation(
            Span(ga32), Span(gb64), 0
        )
    for lag in [Int.MIN, -1, 32, Int.MAX]:
        with assert_raises():
            _ = wifi_dmg_golay_complementary_autocorrelation(
                Span(ga32), Span(gb32), lag
            )

    with assert_raises():
        _ = wifi_dmg_pi_over_2_bpsk_modulate(
            Span(gb32), start_chip_index=Int.MIN
        )
    var at_max = wifi_dmg_pi_over_2_bpsk_modulate(
        Span(gb32), start_chip_index=Int.MAX
    )
    var max_decoded = wifi_dmg_pi_over_2_bpsk_demodulate_exact(
        Span(at_max), start_chip_index=Int.MAX
    )
    _assert_int_lists_equal(Span(max_decoded), Span(gb32))

    var symbols = wifi_dmg_pi_over_2_bpsk_modulate(Span(gb32))
    symbols[0] = Complex64(nan[DType.float64](), 0.0)
    with assert_raises():
        _ = wifi_dmg_pi_over_2_bpsk_demodulate_exact(Span(symbols))
    symbols[0] = Complex64(1.0, inf[DType.float64]())
    with assert_raises():
        _ = wifi_dmg_pi_over_2_bpsk_demodulate_exact(Span(symbols))
    symbols[0] = Complex64(-inf[DType.float64](), 0.0)
    with assert_raises():
        _ = wifi_dmg_pi_over_2_bpsk_demodulate_exact(Span(symbols))
    symbols[0] = Complex64(0.5, 0.0)
    with assert_raises():
        _ = wifi_dmg_pi_over_2_bpsk_demodulate_exact(Span(symbols))
    symbols[0] = Complex64(1.0, 1.0)
    with assert_raises():
        _ = wifi_dmg_pi_over_2_bpsk_demodulate_exact(Span(symbols))
    with assert_raises():
        _ = wifi_dmg_pi_over_2_bpsk_demodulate_exact(
            Span(symbols), start_chip_index=-1
        )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
