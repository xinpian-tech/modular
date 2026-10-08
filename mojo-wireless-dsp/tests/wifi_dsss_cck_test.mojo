"""Independent evidence for bounded DSSS and HR/DSSS CCK symbols.

The static rows are transcribed from the Barker, DBPSK/DQPSK, and 5.5 Mb/s
CCK tables in IEEE Std 802.11-2024 Clauses 15 and 16.  The exhaustive 11 Mb/s
oracle evaluates the published eight-chip phase equation independently of the
production helpers.  Seeded properties include differential phase continuity,
common complex gain, bounded noise, mutation revalidation, and extreme finite
Float64 scale.

PLCP framing, scrambling, preambles, pulse shaping, synchronization, CCA,
PBCC, RF behavior, and conformance are outside this evidence boundary.
"""

from std.collections import Span
from std.testing import assert_equal, assert_true, assert_raises, TestSuite
from std.utils.numerics import inf, nan
from wireless_dsp.core import Complex64
from wireless_dsp.wireless.wifi.dsss_cck import (
    WIFI_DSSS_BARKER_CHIPS,
    WIFI_CCK_CHIPS,
    WIFI_CCK_5_5_BITS_PER_SYMBOL,
    WIFI_CCK_11_BITS_PER_SYMBOL,
    wifi_dsss_barker_sequence,
    wifi_dsss_dbpsk_spread,
    wifi_dsss_dbpsk_despread_hard,
    wifi_dsss_dqpsk_spread,
    wifi_dsss_dqpsk_despread_hard,
    wifi_cck_5_5_codeword,
    wifi_cck_11_codeword,
    wifi_cck_5_5_map,
    wifi_cck_5_5_demap_hard,
    wifi_cck_11_map,
    wifi_cck_11_demap_hard,
)


def _assert_complex_equal(actual: Complex64, expected: Complex64) raises:
    assert_equal(actual.re, expected.re)
    assert_equal(actual.im, expected.im)


def _assert_complex_lists_equal(
    actual: Span[Complex64, ...], expected: Span[Complex64, ...]
) raises:
    assert_equal(len(actual), len(expected))
    for index in range(len(actual)):
        var actual_value = Complex64(actual[index].re, actual[index].im)
        var expected_value = Complex64(expected[index].re, expected[index].im)
        _assert_complex_equal(actual_value, expected_value)


struct _OracleCCKSymbol(Movable):
    var chips: List[Complex64]
    var phase: Int
    var phase_change: Int

    def __init__(
        out self,
        var chips: List[Complex64],
        phase: Int,
        phase_change: Int,
    ):
        self.chips = chips^
        self.phase = phase
        self.phase_change = phase_change


def _oracle_quadrant(quadrant: Int) -> Complex64:
    var value = quadrant & 3
    if value == 0:
        return Complex64(1.0, 0.0)
    if value == 1:
        return Complex64(0.0, 1.0)
    if value == 2:
        return Complex64(-1.0, 0.0)
    return Complex64(0.0, -1.0)


def _oracle_dqpsk(first: Int, second: Int) -> Int:
    if first == 0 and second == 0:
        return 0
    if first == 0 and second == 1:
        return 1
    if first == 1 and second == 1:
        return 2
    return 3


def _oracle_barker(index: Int) -> Float64:
    var values: List[Float64] = [
        1.0, -1.0, 1.0, 1.0, -1.0, 1.0,
        1.0, 1.0, -1.0, -1.0, -1.0,
    ]
    return values[index]


def _oracle_dsss(
    bits: Span[UInt8, ...], bits_per_symbol: Int, initial_phase: Int
) -> List[Complex64]:
    var symbols = len(bits) // bits_per_symbol
    var result = List[Complex64](capacity=symbols * WIFI_DSSS_BARKER_CHIPS)
    var phase = initial_phase
    for symbol in range(symbols):
        if bits_per_symbol == 1:
            phase = (phase + 2 * Int(bits[symbol])) & 3
        else:
            var offset = 2 * symbol
            phase = (
                phase
                + _oracle_dqpsk(Int(bits[offset]), Int(bits[offset + 1]))
            ) & 3
        var phasor = _oracle_quadrant(phase)
        for chip in range(WIFI_DSSS_BARKER_CHIPS):
            var coefficient = _oracle_barker(chip)
            result.append(
                Complex64(coefficient * phasor.re, coefficient * phasor.im)
            )
    return result^


def _pattern_bits(pattern: Int, count: Int) -> List[UInt8]:
    var result = List[UInt8](capacity=count)
    for index in range(count):
        result.append(UInt8((pattern >> (count - index - 1)) & 1))
    return result^


def _oracle_cck(
    bits: Span[UInt8, ...], previous_phase: Int, symbol_index: Int
) -> _OracleCCKSymbol:
    var phase_change = _oracle_dqpsk(Int(bits[0]), Int(bits[1]))
    if (symbol_index & 1) != 0:
        phase_change = (phase_change + 2) & 3
    var phi1 = (previous_phase + phase_change) & 3
    var phi2: Int
    var phi3: Int
    var phi4: Int
    if len(bits) == WIFI_CCK_5_5_BITS_PER_SYMBOL:
        phi2 = 1 + 2 * Int(bits[2])
        phi3 = 0
        phi4 = 2 * Int(bits[3])
    else:
        phi2 = 2 * Int(bits[2]) + Int(bits[3])
        phi3 = 2 * Int(bits[4]) + Int(bits[5])
        phi4 = 2 * Int(bits[6]) + Int(bits[7])
    var phases: List[Int] = [
        phi1 + phi2 + phi3 + phi4,
        phi1 + phi3 + phi4,
        phi1 + phi2 + phi4,
        phi1 + phi4 + 2,
        phi1 + phi2 + phi3,
        phi1 + phi3,
        phi1 + phi2 + 2,
        phi1,
    ]
    var chips = List[Complex64](capacity=WIFI_CCK_CHIPS)
    for chip in range(WIFI_CCK_CHIPS):
        chips.append(_oracle_quadrant(phases[chip]))
    return _OracleCCKSymbol(chips^, phi1, phase_change)


def _oracle_cck_stream(
    bits: Span[UInt8, ...],
    bits_per_symbol: Int,
    initial_phase: Int,
    symbol_offset: Int,
) -> List[Complex64]:
    var symbols = len(bits) // bits_per_symbol
    var result = List[Complex64](capacity=symbols * WIFI_CCK_CHIPS)
    var phase = initial_phase
    for symbol in range(symbols):
        var symbol_bits = List[UInt8](capacity=bits_per_symbol)
        for index in range(bits_per_symbol):
            symbol_bits.append(bits[symbol * bits_per_symbol + index])
        var oracle = _oracle_cck(
            Span(symbol_bits), phase, symbol_offset + symbol
        )
        for chip in range(WIFI_CCK_CHIPS):
            var value = Complex64(
                oracle.chips[chip].re, oracle.chips[chip].im
            )
            result.append(value)
        phase = oracle.phase
    return result^


def _complex_multiply(lhs: Complex64, rhs: Complex64) -> Complex64:
    return Complex64(
        lhs.re * rhs.re - lhs.im * rhs.im,
        lhs.re * rhs.im + lhs.im * rhs.re,
    )


def _gain_and_noise(
    chips: Span[Complex64, ...], gain: Complex64, seed: UInt64
) -> List[Complex64]:
    var state = seed
    var result = List[Complex64](capacity=len(chips))
    for index in range(len(chips)):
        state = (
            state * UInt64(6364136223846793005)
            + UInt64(1442695040888963407)
        )
        var real_noise = (Float64(Int((state >> 56) & UInt64(0xFF))) - 127.5) / 5000.0
        state = (
            state * UInt64(6364136223846793005)
            + UInt64(1442695040888963407)
        )
        var imag_noise = (Float64(Int((state >> 56) & UInt64(0xFF))) - 127.5) / 5000.0
        var sample = Complex64(chips[index].re, chips[index].im)
        var value = _complex_multiply(sample, gain)
        result.append(
            Complex64(value.re + real_noise, value.im + imag_noise)
        )
    return result^


def _scale_axis_chips(
    chips: Span[Complex64, ...], scale: Float64
) -> List[Complex64]:
    var result = List[Complex64](capacity=len(chips))
    for index in range(len(chips)):
        result.append(
            Complex64(chips[index].re * scale, chips[index].im * scale)
        )
    return result^


def test_barker_dbpsk_and_dqpsk_static_clause_vectors() raises:
    var barker = wifi_dsss_barker_sequence()
    assert_equal(len(barker), WIFI_DSSS_BARKER_CHIPS)
    for index in range(WIFI_DSSS_BARKER_CHIPS):
        _assert_complex_equal(
            barker[index], Complex64(_oracle_barker(index), 0.0)
        )

    var dbpsk_bits: List[UInt8] = [0, 1, 1, 0, 1]
    var expected_dbpsk = _oracle_dsss(Span(dbpsk_bits), 1, 1)
    var actual_dbpsk = wifi_dsss_dbpsk_spread(
        Span(dbpsk_bits), initial_phase_quadrant=1
    )
    _assert_complex_lists_equal(Span(actual_dbpsk), Span(expected_dbpsk))
    assert_equal(
        wifi_dsss_dbpsk_despread_hard(
            Span(actual_dbpsk), initial_reference=_oracle_quadrant(1)
        ),
        dbpsk_bits,
    )

    # All four Table-11 DQPSK dibits, in the specified first-in-time order.
    var dqpsk_bits: List[UInt8] = [0, 0, 0, 1, 1, 1, 1, 0]
    var expected_dqpsk = _oracle_dsss(Span(dqpsk_bits), 2, 3)
    var actual_dqpsk = wifi_dsss_dqpsk_spread(
        Span(dqpsk_bits), initial_phase_quadrant=3
    )
    _assert_complex_lists_equal(Span(actual_dqpsk), Span(expected_dqpsk))
    assert_equal(
        wifi_dsss_dqpsk_despread_hard(
            Span(actual_dqpsk), initial_reference=_oracle_quadrant(3)
        ),
        dqpsk_bits,
    )


def test_cck_5_5_literal_table_and_differential_cover() raises:
    var table: List[Complex64] = [
        # d2,d3 = 00
        Complex64(0.0, 1.0), Complex64(1.0, 0.0),
        Complex64(0.0, 1.0), Complex64(-1.0, 0.0),
        Complex64(0.0, 1.0), Complex64(1.0, 0.0),
        Complex64(0.0, -1.0), Complex64(1.0, 0.0),
        # d2,d3 = 01
        Complex64(0.0, -1.0), Complex64(-1.0, 0.0),
        Complex64(0.0, -1.0), Complex64(1.0, 0.0),
        Complex64(0.0, 1.0), Complex64(1.0, 0.0),
        Complex64(0.0, -1.0), Complex64(1.0, 0.0),
        # d2,d3 = 10
        Complex64(0.0, -1.0), Complex64(1.0, 0.0),
        Complex64(0.0, -1.0), Complex64(-1.0, 0.0),
        Complex64(0.0, -1.0), Complex64(1.0, 0.0),
        Complex64(0.0, 1.0), Complex64(1.0, 0.0),
        # d2,d3 = 11
        Complex64(0.0, 1.0), Complex64(-1.0, 0.0),
        Complex64(0.0, 1.0), Complex64(1.0, 0.0),
        Complex64(0.0, -1.0), Complex64(1.0, 0.0),
        Complex64(0.0, 1.0), Complex64(1.0, 0.0),
    ]
    for pattern in range(4):
        var bits: List[UInt8] = [
            0,
            0,
            UInt8((pattern >> 1) & 1),
            UInt8(pattern & 1),
        ]
        var symbol = wifi_cck_5_5_codeword(Span(bits))
        assert_equal(symbol.phase_quadrant, 0)
        assert_equal(symbol.phase_change_quadrant, 0)
        for chip in range(WIFI_CCK_CHIPS):
            _assert_complex_equal(
                symbol.chips[chip], table[pattern * WIFI_CCK_CHIPS + chip]
            )

    var bits: List[UInt8] = [0, 1, 1, 0]
    var even = wifi_cck_5_5_codeword(
        Span(bits), previous_phase_quadrant=3, symbol_index=8
    )
    var odd = wifi_cck_5_5_codeword(
        Span(bits), previous_phase_quadrant=3, symbol_index=9
    )
    assert_equal(even.phase_change_quadrant, 1)
    assert_equal(even.phase_quadrant, 0)
    assert_equal(odd.phase_change_quadrant, 3)
    assert_equal(odd.phase_quadrant, 2)
    for chip in range(WIFI_CCK_CHIPS):
        assert_equal(odd.chips[chip].re, -even.chips[chip].re)
        assert_equal(odd.chips[chip].im, -even.chips[chip].im)


def test_cck_11_exhaustive_exact_equation_oracle() raises:
    for previous_phase in range(4):
        for parity in range(2):
            for pattern in range(256):
                var bits = _pattern_bits(pattern, WIFI_CCK_11_BITS_PER_SYMBOL)
                var expected = _oracle_cck(
                    Span(bits), previous_phase, parity
                )
                var actual = wifi_cck_11_codeword(
                    Span(bits),
                    previous_phase_quadrant=previous_phase,
                    symbol_index=parity,
                )
                assert_equal(actual.phase_quadrant, expected.phase)
                assert_equal(
                    actual.phase_change_quadrant, expected.phase_change
                )
                _assert_complex_lists_equal(
                    Span(actual.chips), Span(expected.chips)
                )


def test_cck_exhaustive_stream_maps_and_hard_detectors() raises:
    var bits_5 = List[UInt8](capacity=16 * WIFI_CCK_5_5_BITS_PER_SYMBOL)
    for pattern in range(16):
        var one = _pattern_bits(pattern, WIFI_CCK_5_5_BITS_PER_SYMBOL)
        for index in range(WIFI_CCK_5_5_BITS_PER_SYMBOL):
            bits_5.append(one[index])
    var expected_5 = _oracle_cck_stream(Span(bits_5), 4, 3, 5)
    var mapped_5 = wifi_cck_5_5_map(
        Span(bits_5), initial_phase_quadrant=3, symbol_offset=5
    )
    _assert_complex_lists_equal(Span(mapped_5), Span(expected_5))
    assert_equal(
        wifi_cck_5_5_demap_hard(
            Span(mapped_5),
            initial_reference=_oracle_quadrant(3),
            symbol_offset=5,
        ),
        bits_5,
    )

    var bits_11 = List[UInt8](capacity=256 * WIFI_CCK_11_BITS_PER_SYMBOL)
    for pattern in range(256):
        var one = _pattern_bits(pattern, WIFI_CCK_11_BITS_PER_SYMBOL)
        for index in range(WIFI_CCK_11_BITS_PER_SYMBOL):
            bits_11.append(one[index])
    var expected_11 = _oracle_cck_stream(Span(bits_11), 8, 2, 7)
    var mapped_11 = wifi_cck_11_map(
        Span(bits_11), initial_phase_quadrant=2, symbol_offset=7
    )
    _assert_complex_lists_equal(Span(mapped_11), Span(expected_11))
    assert_equal(
        wifi_cck_11_demap_hard(
            Span(mapped_11),
            initial_reference=_oracle_quadrant(2),
            symbol_offset=7,
        ),
        bits_11,
    )


def test_seeded_independent_maps_gain_noise_and_roundtrips() raises:
    var state = UInt64(0xD555CCB00B13579)
    var dbpsk = List[UInt8](capacity=97)
    var dqpsk = List[UInt8](capacity=98)
    var cck5 = List[UInt8](capacity=4 * 61)
    var cck11 = List[UInt8](capacity=8 * 61)
    for _ in range(97):
        state = state * UInt64(6364136223846793005) + UInt64(1)
        dbpsk.append(UInt8((state >> 63) & UInt64(1)))
    for _ in range(98):
        state = state * UInt64(6364136223846793005) + UInt64(1)
        dqpsk.append(UInt8((state >> 62) & UInt64(1)))
    for _ in range(4 * 61):
        state = state * UInt64(6364136223846793005) + UInt64(1)
        cck5.append(UInt8((state >> 61) & UInt64(1)))
    for _ in range(8 * 61):
        state = state * UInt64(6364136223846793005) + UInt64(1)
        cck11.append(UInt8((state >> 60) & UInt64(1)))

    var dbpsk_expected = _oracle_dsss(Span(dbpsk), 1, 2)
    var dbpsk_mapped = wifi_dsss_dbpsk_spread(
        Span(dbpsk), initial_phase_quadrant=2
    )
    _assert_complex_lists_equal(Span(dbpsk_mapped), Span(dbpsk_expected))
    var dqpsk_expected = _oracle_dsss(Span(dqpsk), 2, 1)
    var dqpsk_mapped = wifi_dsss_dqpsk_spread(
        Span(dqpsk), initial_phase_quadrant=1
    )
    _assert_complex_lists_equal(Span(dqpsk_mapped), Span(dqpsk_expected))
    var cck5_expected = _oracle_cck_stream(Span(cck5), 4, 3, 4)
    var cck5_mapped = wifi_cck_5_5_map(
        Span(cck5), initial_phase_quadrant=3, symbol_offset=4
    )
    _assert_complex_lists_equal(Span(cck5_mapped), Span(cck5_expected))
    var cck11_expected = _oracle_cck_stream(Span(cck11), 8, 1, 6)
    var cck11_mapped = wifi_cck_11_map(
        Span(cck11), initial_phase_quadrant=1, symbol_offset=6
    )
    _assert_complex_lists_equal(Span(cck11_mapped), Span(cck11_expected))

    var gain = Complex64(0.75, -0.25)
    var dbpsk_rx = _gain_and_noise(Span(dbpsk_mapped), gain, state)
    var dqpsk_rx = _gain_and_noise(Span(dqpsk_mapped), gain, state + UInt64(3))
    var cck5_rx = _gain_and_noise(Span(cck5_mapped), gain, state + UInt64(7))
    var cck11_rx = _gain_and_noise(Span(cck11_mapped), gain, state + UInt64(11))
    assert_equal(
        wifi_dsss_dbpsk_despread_hard(
            Span(dbpsk_rx),
            initial_reference=_complex_multiply(_oracle_quadrant(2), gain),
        ),
        dbpsk,
    )
    assert_equal(
        wifi_dsss_dqpsk_despread_hard(
            Span(dqpsk_rx),
            initial_reference=_complex_multiply(_oracle_quadrant(1), gain),
        ),
        dqpsk,
    )
    assert_equal(
        wifi_cck_5_5_demap_hard(
            Span(cck5_rx),
            initial_reference=_complex_multiply(_oracle_quadrant(3), gain),
            symbol_offset=4,
        ),
        cck5,
    )
    assert_equal(
        wifi_cck_11_demap_hard(
            Span(cck11_rx),
            initial_reference=_complex_multiply(_oracle_quadrant(1), gain),
            symbol_offset=6,
        ),
        cck11,
    )


def test_extreme_finite_scales_are_detected_without_overflow() raises:
    var dbits: List[UInt8] = [1, 0, 1, 1]
    var qbits: List[UInt8] = [0, 1, 1, 0, 1, 1]
    var c5bits: List[UInt8] = [1, 1, 0, 1, 0, 0, 1, 0]
    var c11bits: List[UInt8] = [
        1, 0, 1, 1, 0, 1, 0, 0,
        0, 1, 1, 0, 1, 0, 1, 1,
    ]
    var db = wifi_dsss_dbpsk_spread(Span(dbits), initial_phase_quadrant=1)
    var dq = wifi_dsss_dqpsk_spread(Span(qbits), initial_phase_quadrant=2)
    var c5 = wifi_cck_5_5_map(Span(c5bits), initial_phase_quadrant=3)
    var c11 = wifi_cck_11_map(Span(c11bits), initial_phase_quadrant=1)
    for scale in [1.0e308, 1.0e-300, 5.0e-324]:
        var db_scaled = _scale_axis_chips(Span(db), scale)
        var dq_scaled = _scale_axis_chips(Span(dq), scale)
        var c5_scaled = _scale_axis_chips(Span(c5), scale)
        var c11_scaled = _scale_axis_chips(Span(c11), scale)
        assert_equal(
            wifi_dsss_dbpsk_despread_hard(
                Span(db_scaled),
                initial_reference=Complex64(0.0, scale),
            ),
            dbits,
        )
        assert_equal(
            wifi_dsss_dqpsk_despread_hard(
                Span(dq_scaled),
                initial_reference=Complex64(-scale, 0.0),
            ),
            qbits,
        )
        assert_equal(
            wifi_cck_5_5_demap_hard(
                Span(c5_scaled),
                initial_reference=Complex64(0.0, -scale),
            ),
            c5bits,
        )
        assert_equal(
            wifi_cck_11_demap_hard(
                Span(c11_scaled),
                initial_reference=Complex64(0.0, scale),
            ),
            c11bits,
        )


def test_public_mutable_boundaries_revalidate_and_reject_invalid_values() raises:
    var bits8: List[UInt8] = [0, 0, 0, 0, 0, 0, 0, 0]
    _ = wifi_cck_11_codeword(Span(bits8))
    bits8[0] = UInt8(2)
    with assert_raises():
        _ = wifi_cck_11_codeword(Span(bits8))
    with assert_raises():
        _ = wifi_cck_11_map(Span(bits8))

    var bits4: List[UInt8] = [0, 0, 0, 0]
    _ = wifi_cck_5_5_codeword(Span(bits4))
    bits4[3] = UInt8(3)
    with assert_raises():
        _ = wifi_cck_5_5_codeword(Span(bits4))
    with assert_raises():
        _ = wifi_cck_5_5_map(Span(bits4))

    var dsss: List[UInt8] = [0, 1]
    _ = wifi_dsss_dbpsk_spread(Span(dsss))
    _ = wifi_dsss_dqpsk_spread(Span(dsss))
    dsss[1] = UInt8(2)
    with assert_raises():
        _ = wifi_dsss_dbpsk_spread(Span(dsss))
    with assert_raises():
        _ = wifi_dsss_dqpsk_spread(Span(dsss))

    var short_bits: List[UInt8] = [0, 1, 0]
    with assert_raises():
        _ = wifi_dsss_dqpsk_spread(Span(short_bits))
    with assert_raises():
        _ = wifi_cck_5_5_map(Span(short_bits))
    with assert_raises():
        _ = wifi_cck_11_codeword(Span(short_bits))
    var two_symbols: List[UInt8] = [
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0,
    ]
    with assert_raises():
        _ = wifi_cck_11_map(Span(two_symbols), symbol_offset=Int.MAX)
    with assert_raises():
        _ = wifi_cck_5_5_map(Span(bits4), symbol_offset=-1)
    with assert_raises():
        _ = wifi_cck_11_codeword(
            Span(two_symbols[0:8]), previous_phase_quadrant=4
        )
    with assert_raises():
        _ = wifi_dsss_dbpsk_spread(
            Span(two_symbols[0:1]), initial_phase_quadrant=-1
        )

    var valid_cck_bits: List[UInt8] = [0, 0, 0, 0, 0, 0, 0, 0]
    var cck = wifi_cck_11_map(Span(valid_cck_bits))
    _ = wifi_cck_11_demap_hard(Span(cck))
    cck[0] = Complex64(nan[DType.float64](), 0.0)
    with assert_raises():
        _ = wifi_cck_11_demap_hard(Span(cck))
    cck[0] = Complex64(1.0, 0.0)
    cck[7] = Complex64(0.0, 0.0)
    with assert_raises():
        _ = wifi_cck_11_demap_hard(Span(cck))

    var valid_dsss_bits: List[UInt8] = [0]
    var chips = wifi_dsss_dbpsk_spread(Span(valid_dsss_bits))
    _ = wifi_dsss_dbpsk_despread_hard(Span(chips))
    chips[4] = Complex64(0.0, inf[DType.float64]())
    with assert_raises():
        _ = wifi_dsss_dbpsk_despread_hard(Span(chips))
    var zero_dsss = List[Complex64](
        length=WIFI_DSSS_BARKER_CHIPS, fill=Complex64(0.0, 0.0)
    )
    with assert_raises():
        _ = wifi_dsss_dqpsk_despread_hard(Span(zero_dsss))

    var short_chips = List[Complex64](length=7, fill=Complex64(1.0, 0.0))
    with assert_raises():
        _ = wifi_cck_5_5_demap_hard(Span(short_chips))
    with assert_raises():
        _ = wifi_dsss_dbpsk_despread_hard(Span(short_chips))
    var empty = List[Complex64]()
    for bad_reference in [
        Complex64(0.0, 0.0),
        Complex64(nan[DType.float64](), 0.0),
        Complex64(0.0, inf[DType.float64]()),
    ]:
        with assert_raises():
            _ = wifi_dsss_dbpsk_despread_hard(
                Span(empty), initial_reference=bad_reference
            )
        with assert_raises():
            _ = wifi_cck_11_demap_hard(
                Span(empty), initial_reference=bad_reference
            )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
