"""Independent evidence for bounded Clause-15/16 DSSS PLCP/PPDU.

The literal CRC and LENGTH rows come from the IEEE 802.11 Working Group
primary archive P802.11b/D3.1, 18.2.3.5--18.2.3.6 (including Table 2).
Test-side scrambler, CRC-16, CRC-32, differential Barker, and CCK equations
are structurally independent of production.  They build complete RX fixtures
without invoking the production transmitter.  All discrete comparisons have
zero tolerance; a separate bounded-gain/noise test exercises the hard receiver
with explicit amplitude tolerance.

This evidence is limited to aligned complex chips with a common channel gain.
PBCC, pulse shaping, acquisition, CCA, multipath equalization, RF/OTA, and
conformance remain outside the claimed bounded profile.
"""

from std.collections import Span
from std.testing import assert_equal, assert_true, assert_raises, TestSuite
from std.utils.numerics import inf, nan
from wireless_dsp.core import Complex64
from wireless_dsp.wireless.wifi.dsss_plcp import (
    WIFI_DSSS_RATE_1_MBPS_KBPS,
    WIFI_DSSS_RATE_2_MBPS_KBPS,
    WIFI_DSSS_RATE_5_5_MBPS_KBPS,
    WIFI_DSSS_RATE_11_MBPS_KBPS,
    WIFI_DSSS_LONG_SCRAMBLER_SEED,
    WIFI_DSSS_SHORT_SCRAMBLER_SEED,
    WIFI_DSSS_LONG_SYNC_BITS,
    WIFI_DSSS_SHORT_SYNC_BITS,
    WIFI_DSSS_SFD_BITS,
    WIFI_DSSS_PLCP_HEADER_BITS,
    WIFI_DSSS_MAX_PSDU_OCTETS,
    WifiDSSSPLCPConfig,
    wifi_dsss_plcp_scramble,
    wifi_dsss_plcp_descramble,
    wifi_dsss_plcp_crc16,
    wifi_dsss_plcp_preamble_bits,
    wifi_dsss_plcp_length,
    wifi_dsss_plcp_header_pack,
    wifi_dsss_plcp_header_parse,
    wifi_dsss_ppdu_tx,
    wifi_dsss_ppdu_rx,
)


def _append_lsb(mut output: List[UInt8], value: Int, width: Int):
    for bit in range(width):
        output.append(UInt8((value >> bit) & 1))


def _read_lsb(bits: Span[UInt8, ...], offset: Int, width: Int) -> Int:
    var value = 0
    for bit in range(width):
        value |= Int(bits[offset + bit]) << bit
    return value


def _assert_bits(actual: Span[UInt8, ...], expected: Span[UInt8, ...]) raises:
    assert_equal(len(actual), len(expected))
    for index in range(len(actual)):
        assert_equal(actual[index], expected[index])


def _assert_chips(
    actual: Span[Complex64, ...], expected: Span[Complex64, ...]
) raises:
    assert_equal(len(actual), len(expected))
    for index in range(len(actual)):
        assert_equal(actual[index].re, expected[index].re)
        assert_equal(actual[index].im, expected[index].im)


def _oracle_crc16(bits: Span[UInt8, ...]) -> Int:
    # Sixteen explicit MSB-first registers implement x^16+x^12+x^5+1.
    var registers = List[Int](length=16, fill=1)
    for index in range(len(bits)):
        var feedback = registers[0] ^ Int(bits[index])
        var previous = registers.copy()
        for register in range(15):
            registers[register] = previous[register + 1]
        registers[15] = 0
        registers[3] ^= feedback
        registers[10] ^= feedback
        registers[15] ^= feedback
    var result = 0
    # The standard transmits the complemented final MSB first.  Store that
    # first-in-time bit at integer bit zero to match the public API contract.
    for bit in range(16):
        result |= (registers[bit] ^ 1) << bit
    return result


def _oracle_scramble(bits: Span[UInt8, ...], seed: Int) -> List[UInt8]:
    # Explicit Z1..Z7 registers, independently spelling Figure 5.
    var z = List[Int](capacity=7)
    for register in range(7):
        z.append((seed >> (6 - register)) & 1)
    var result = List[UInt8](capacity=len(bits))
    for index in range(len(bits)):
        var output = Int(bits[index]) ^ z[3] ^ z[6]
        result.append(UInt8(output))
        for register in range(6, 0, -1):
            z[register] = z[register - 1]
        z[0] = output
    return result^


def _oracle_fcs32(bits: Span[UInt8, ...]) -> UInt64:
    var state = UInt64(0xFFFFFFFF)
    for index in range(len(bits)):
        var feedback = (state & UInt64(1)) ^ UInt64(bits[index])
        state >>= UInt64(1)
        if feedback != UInt64(0):
            state ^= UInt64(0xEDB88320)
    return state ^ UInt64(0xFFFFFFFF)


def _octets_bits(octets: Span[UInt8, ...]) -> List[UInt8]:
    var result = List[UInt8](capacity=8 * len(octets))
    for index in range(len(octets)):
        _append_lsb(result, Int(octets[index]), 8)
    return result^


def _oracle_signal(rate: Int) -> Int:
    if rate == WIFI_DSSS_RATE_1_MBPS_KBPS:
        return 0x0A
    if rate == WIFI_DSSS_RATE_2_MBPS_KBPS:
        return 0x14
    if rate == WIFI_DSSS_RATE_5_5_MBPS_KBPS:
        return 0x37
    return 0x6E


def _oracle_header(
    psdu_octets: Int, config: WifiDSSSPLCPConfig
) -> List[UInt8]:
    var length: Int
    var extension = False
    if config.data_rate_kbps == WIFI_DSSS_RATE_1_MBPS_KBPS:
        length = 8 * psdu_octets
    elif config.data_rate_kbps == WIFI_DSSS_RATE_2_MBPS_KBPS:
        length = 4 * psdu_octets
    elif config.data_rate_kbps == WIFI_DSSS_RATE_5_5_MBPS_KBPS:
        length = (16 * psdu_octets + 10) // 11
    else:
        length = (8 * psdu_octets + 10) // 11
        extension = 11 * length - 8 * psdu_octets >= 8
    var service = (4 if config.locked_clocks else 0) | (
        0x80 if extension else 0
    )
    var result = List[UInt8](capacity=48)
    _append_lsb(result, _oracle_signal(config.data_rate_kbps), 8)
    _append_lsb(result, service, 8)
    _append_lsb(result, length, 16)
    _append_lsb(result, _oracle_crc16(Span(result)), 16)
    return result^


def _oracle_preamble(short_preamble: Bool) -> List[UInt8]:
    var sync = WIFI_DSSS_SHORT_SYNC_BITS if short_preamble else WIFI_DSSS_LONG_SYNC_BITS
    var result = List[UInt8](capacity=sync + 16)
    for _ in range(sync):
        result.append(UInt8(0 if short_preamble else 1))
    _append_lsb(result, 0x05CF if short_preamble else 0xF3A0, 16)
    return result^


def _quadrant(value: Int) -> Complex64:
    var q = value & 3
    if q == 0:
        return Complex64(1.0, 0.0)
    if q == 1:
        return Complex64(0.0, 1.0)
    if q == 2:
        return Complex64(-1.0, 0.0)
    return Complex64(0.0, -1.0)


def _dqpsk(first: Int, second: Int) -> Int:
    if first == 0:
        return second
    return 3 - second


def _barker(index: Int) -> Float64:
    if index == 1 or index == 4 or index >= 8:
        return -1.0
    return 1.0


struct _OracleBarkerMap(Movable):
    var chips: List[Complex64]
    var phase: Int

    def __init__(
        out self, var chips: List[Complex64], phase: Int
    ):
        self.chips = chips^
        self.phase = phase


def _oracle_barker_map(
    bits: Span[UInt8, ...], bits_per_symbol: Int, initial_phase: Int
) -> _OracleBarkerMap:
    var phase = initial_phase
    var symbols = len(bits) // bits_per_symbol
    var result = List[Complex64](capacity=11 * symbols)
    for symbol in range(symbols):
        if bits_per_symbol == 1:
            phase = (phase + 2 * Int(bits[symbol])) & 3
        else:
            phase = (
                phase
                + _dqpsk(
                    Int(bits[2 * symbol]), Int(bits[2 * symbol + 1])
                )
            ) & 3
        var value = _quadrant(phase)
        for chip in range(11):
            var coefficient = _barker(chip)
            result.append(Complex64(
                coefficient * value.re, coefficient * value.im
            ))
    return _OracleBarkerMap(result^, phase)


def _append_cck_word(
    mut result: List[Complex64],
    phi1: Int,
    phi2: Int,
    phi3: Int,
    phi4: Int,
):
    for phase in [
        phi1 + phi2 + phi3 + phi4,
        phi1 + phi3 + phi4,
        phi1 + phi2 + phi4,
        phi1 + phi4 + 2,
        phi1 + phi2 + phi3,
        phi1 + phi3,
        phi1 + phi2 + 2,
        phi1,
    ]:
        result.append(_quadrant(phase))


def _oracle_cck_map(
    bits: Span[UInt8, ...], bits_per_symbol: Int, initial_phase: Int
) -> List[Complex64]:
    var symbols = len(bits) // bits_per_symbol
    var result = List[Complex64](capacity=8 * symbols)
    var phase = initial_phase
    for symbol in range(symbols):
        var offset = symbol * bits_per_symbol
        var change = _dqpsk(Int(bits[offset]), Int(bits[offset + 1]))
        if (symbol & 1) != 0:
            change = (change + 2) & 3
        phase = (phase + change) & 3
        if bits_per_symbol == 4:
            _append_cck_word(
                result,
                phase,
                1 + 2 * Int(bits[offset + 2]),
                0,
                2 * Int(bits[offset + 3]),
            )
        else:
            _append_cck_word(
                result,
                phase,
                2 * Int(bits[offset + 2]) + Int(bits[offset + 3]),
                2 * Int(bits[offset + 4]) + Int(bits[offset + 5]),
                2 * Int(bits[offset + 6]) + Int(bits[offset + 7]),
            )
    return result^


struct _OraclePPDU(Movable):
    var chips: List[Complex64]
    var raw_bits: List[UInt8]
    var scrambled_bits: List[UInt8]
    var fcs: UInt64

    def __init__(
        out self,
        var chips: List[Complex64],
        var raw_bits: List[UInt8],
        var scrambled_bits: List[UInt8],
        fcs: UInt64,
    ):
        self.chips = chips^
        self.raw_bits = raw_bits^
        self.scrambled_bits = scrambled_bits^
        self.fcs = fcs


def _oracle_ppdu(
    payload: Span[UInt8, ...], config: WifiDSSSPLCPConfig
) -> _OraclePPDU:
    var payload_bits = _octets_bits(payload)
    var fcs = _oracle_fcs32(Span(payload_bits))
    var psdu = payload_bits.copy()
    for bit in range(32):
        psdu.append(UInt8((fcs >> UInt64(bit)) & UInt64(1)))
    var preamble = _oracle_preamble(config.short_preamble)
    var header = _oracle_header(len(payload) + 4, config)
    var raw = preamble.copy()
    for bit in header:
        raw.append(bit)
    for bit in psdu:
        raw.append(bit)
    var seed = (
        WIFI_DSSS_SHORT_SCRAMBLER_SEED
        if config.short_preamble
        else WIFI_DSSS_LONG_SCRAMBLER_SEED
    )
    var scrambled = _oracle_scramble(Span(raw), seed)
    var preamble_scrambled = List[UInt8](capacity=len(preamble))
    var header_scrambled = List[UInt8](capacity=len(header))
    var data_scrambled = List[UInt8](capacity=len(psdu))
    for index in range(len(scrambled)):
        if index < len(preamble):
            preamble_scrambled.append(scrambled[index])
        elif index < len(preamble) + len(header):
            header_scrambled.append(scrambled[index])
        else:
            data_scrambled.append(scrambled[index])
    var preamble_mapped = _oracle_barker_map(
        Span(preamble_scrambled), 1, 0
    )
    var preamble_phase = preamble_mapped.phase
    var preamble_chips = preamble_mapped.chips.copy()
    var header_chips: List[Complex64]
    var header_phase: Int
    if config.short_preamble:
        var mapped = _oracle_barker_map(
            Span(header_scrambled), 2, preamble_phase
        )
        header_phase = mapped.phase
        header_chips = mapped.chips.copy()
    else:
        var mapped = _oracle_barker_map(
            Span(header_scrambled), 1, preamble_phase
        )
        header_phase = mapped.phase
        header_chips = mapped.chips.copy()
    var data_chips: List[Complex64]
    if config.data_rate_kbps == WIFI_DSSS_RATE_1_MBPS_KBPS:
        var mapped = _oracle_barker_map(
            Span(data_scrambled), 1, header_phase
        )
        data_chips = mapped.chips.copy()
    elif config.data_rate_kbps == WIFI_DSSS_RATE_2_MBPS_KBPS:
        var mapped = _oracle_barker_map(
            Span(data_scrambled), 2, header_phase
        )
        data_chips = mapped.chips.copy()
    elif config.data_rate_kbps == WIFI_DSSS_RATE_5_5_MBPS_KBPS:
        data_chips = _oracle_cck_map(
            Span(data_scrambled), 4, header_phase
        )
    else:
        data_chips = _oracle_cck_map(
            Span(data_scrambled), 8, header_phase
        )
    var chips = preamble_chips.copy()
    for value in header_chips:
        chips.append(value)
    for value in data_chips:
        chips.append(value)
    return _OraclePPDU(chips^, raw^, scrambled^, fcs)


def test_official_crc_preamble_signal_and_length_table_vectors() raises:
    # Official DBPSK, 24-octet, 192 us protected fields and CRC example.
    var protected = List[UInt8]()
    _append_lsb(protected, 0x0A, 8)
    _append_lsb(protected, 0, 8)
    _append_lsb(protected, 192, 16)
    assert_equal(wifi_dsss_plcp_crc16(Span(protected)), 0xEADA)
    assert_equal(_oracle_crc16(Span(protected)), 0xEADA)
    var config_1 = WifiDSSSPLCPConfig(WIFI_DSSS_RATE_1_MBPS_KBPS)
    var header = wifi_dsss_plcp_header_pack(24, config_1)
    assert_equal(_read_lsb(Span(header), 0, 8), 0x0A)
    assert_equal(_read_lsb(Span(header), 16, 16), 192)
    assert_equal(_read_lsb(Span(header), 32, 16), 0xEADA)

    var long = wifi_dsss_plcp_preamble_bits()
    assert_equal(len(long), 144)
    for index in range(WIFI_DSSS_LONG_SYNC_BITS):
        assert_equal(long[index], UInt8(1))
    assert_equal(_read_lsb(Span(long), WIFI_DSSS_LONG_SYNC_BITS, 16), 0xF3A0)
    var short = wifi_dsss_plcp_preamble_bits(short_preamble=True)
    assert_equal(len(short), 72)
    for index in range(WIFI_DSSS_SHORT_SYNC_BITS):
        assert_equal(short[index], UInt8(0))
    assert_equal(_read_lsb(Span(short), WIFI_DSSS_SHORT_SYNC_BITS, 16), 0x05CF)

    var config_11 = WifiDSSSPLCPConfig(WIFI_DSSS_RATE_11_MBPS_KBPS)
    var octets: List[Int] = [1023, 1024, 1025, 1026]
    var lengths: List[Int] = [744, 745, 746, 747]
    var extensions: List[Bool] = [False, False, False, True]
    for index in range(4):
        var geometry = wifi_dsss_plcp_length(octets[index], config_11)
        assert_equal(geometry.length_us, lengths[index])
        assert_equal(geometry.length_extension, extensions[index])


def test_scrambler_literal_register_fixture_and_seeded_inverse() raises:
    var long_ones = List[UInt8](length=16, fill=UInt8(1))
    var short_zeros = List[UInt8](length=16, fill=UInt8(0))
    var expected_long: List[UInt8] = [
        0, 1, 1, 1, 1, 1, 1, 0, 1, 1, 1, 0, 1, 1, 0, 0,
    ]
    var expected_short: List[UInt8] = [
        0, 0, 0, 1, 1, 0, 0, 1, 1, 0, 1, 0, 1, 0, 0, 1,
    ]
    _assert_bits(
        Span(wifi_dsss_plcp_scramble(
            Span(long_ones), WIFI_DSSS_LONG_SCRAMBLER_SEED
        )),
        Span(expected_long),
    )
    _assert_bits(
        Span(wifi_dsss_plcp_scramble(
            Span(short_zeros), WIFI_DSSS_SHORT_SCRAMBLER_SEED
        )),
        Span(expected_short),
    )

    var state = UInt64(0xD1B54A32D192ED03)
    for seed in range(1, 128):
        var bits = List[UInt8](capacity=257)
        for _ in range(257):
            state = state * UInt64(6364136223846793005) + UInt64(1)
            bits.append(UInt8((state >> UInt64(63)) & UInt64(1)))
        var expected = _oracle_scramble(Span(bits), seed)
        var actual = wifi_dsss_plcp_scramble(Span(bits), seed)
        _assert_bits(Span(actual), Span(expected))
        var recovered = wifi_dsss_plcp_descramble(Span(actual), seed)
        _assert_bits(Span(recovered), Span(bits))
        assert_equal(
            wifi_dsss_plcp_crc16(Span(bits[0:32])),
            _oracle_crc16(Span(bits[0:32])),
        )


def test_header_all_rates_long_short_and_canonical_parse() raises:
    for rate in [
        WIFI_DSSS_RATE_1_MBPS_KBPS,
        WIFI_DSSS_RATE_2_MBPS_KBPS,
        WIFI_DSSS_RATE_5_5_MBPS_KBPS,
        WIFI_DSSS_RATE_11_MBPS_KBPS,
    ]:
        for short_preamble in [False, True]:
            if short_preamble and rate == WIFI_DSSS_RATE_1_MBPS_KBPS:
                continue
            for psdu_octets in [1, 4, 37, 1026, WIFI_DSSS_MAX_PSDU_OCTETS]:
                var config = WifiDSSSPLCPConfig(
                    rate,
                    short_preamble=short_preamble,
                    locked_clocks=(psdu_octets & 1) != 0,
                )
                var expected = _oracle_header(psdu_octets, config)
                var actual = wifi_dsss_plcp_header_pack(psdu_octets, config)
                _assert_bits(Span(actual), Span(expected))
                var geometry = wifi_dsss_plcp_length(psdu_octets, config)
                var parsed = wifi_dsss_plcp_header_parse(
                    Span(actual), short_preamble=short_preamble
                )
                assert_equal(parsed.config.data_rate_kbps, rate)
                assert_equal(parsed.config.short_preamble, short_preamble)
                assert_equal(parsed.config.locked_clocks, config.locked_clocks)
                assert_equal(parsed.length.psdu_octets, psdu_octets)
                assert_equal(parsed.length.length_us, geometry.length_us)
                assert_equal(
                    parsed.length.length_extension,
                    geometry.length_extension,
                )
                assert_equal(parsed.crc, _oracle_crc16(Span(actual[0:32])))


def test_complete_tx_matches_independent_chip_fixture_all_profiles() raises:
    var payload: List[UInt8] = [0x00, 0x12, 0xA5, 0xFF]
    for rate in [
        WIFI_DSSS_RATE_1_MBPS_KBPS,
        WIFI_DSSS_RATE_2_MBPS_KBPS,
        WIFI_DSSS_RATE_5_5_MBPS_KBPS,
        WIFI_DSSS_RATE_11_MBPS_KBPS,
    ]:
        for short_preamble in [False, True]:
            if short_preamble and rate == WIFI_DSSS_RATE_1_MBPS_KBPS:
                continue
            var config = WifiDSSSPLCPConfig(
                rate,
                short_preamble=short_preamble,
                locked_clocks=True,
            )
            var expected = _oracle_ppdu(Span(payload), config)
            var actual = wifi_dsss_ppdu_tx(
                Span(payload), config, testcase_id="independent-tx"
            )
            assert_equal(actual.fcs, expected.fcs)
            _assert_bits(Span(actual.ppdu_bits), Span(expected.raw_bits))
            _assert_bits(
                Span(actual.scrambled_bits), Span(expected.scrambled_bits)
            )
            _assert_chips(Span(actual.ppdu_chips), Span(expected.chips))
            assert_equal(len(actual.metadata), 10)
            assert_equal(actual.metadata[0].testcase_id, "independent-tx")


def test_rx_independent_fixtures_all_profiles_and_actual_fcs() raises:
    var payload: List[UInt8] = [0xDE, 0xAD, 0xBE, 0xEF, 0x31]
    for rate in [
        WIFI_DSSS_RATE_1_MBPS_KBPS,
        WIFI_DSSS_RATE_2_MBPS_KBPS,
        WIFI_DSSS_RATE_5_5_MBPS_KBPS,
        WIFI_DSSS_RATE_11_MBPS_KBPS,
    ]:
        for short_preamble in [False, True]:
            if short_preamble and rate == WIFI_DSSS_RATE_1_MBPS_KBPS:
                continue
            var config = WifiDSSSPLCPConfig(
                rate, short_preamble=short_preamble
            )
            # Fixture construction never calls production TX or production
            # FCS/scrambler/modulators.
            var fixture = _oracle_ppdu(Span(payload), config)
            var decoded = wifi_dsss_ppdu_rx(
                Span(fixture.chips),
                short_preamble=short_preamble,
                testcase_id="independent-rx",
            )
            assert_equal(decoded.header.config.data_rate_kbps, rate)
            assert_equal(decoded.payload_octets, payload)
            assert_equal(decoded.recovered_fcs, fixture.fcs)
            assert_equal(decoded.computed_fcs, fixture.fcs)
            assert_true(decoded.fcs_ok)
            assert_equal(len(decoded.metadata), 8)
            assert_equal(decoded.metadata[0].testcase_id, "independent-rx")

    var corrupt_config = WifiDSSSPLCPConfig(WIFI_DSSS_RATE_1_MBPS_KBPS)
    var corrupt_fixture = _oracle_ppdu(Span(payload), corrupt_config)
    var data_offset = (
        WIFI_DSSS_LONG_SYNC_BITS + WIFI_DSSS_SFD_BITS
        + WIFI_DSSS_PLCP_HEADER_BITS
    ) * 11
    for chip in range(11):
        corrupt_fixture.chips[data_offset + chip] = Complex64(
            -corrupt_fixture.chips[data_offset + chip].re,
            -corrupt_fixture.chips[data_offset + chip].im,
        )
    var corrupt = wifi_dsss_ppdu_rx(Span(corrupt_fixture.chips))
    assert_true(not corrupt.fcs_ok)


def _gain_noise(
    chips: Span[Complex64, ...], gain: Float64, noise: Float64
) -> List[Complex64]:
    var result = List[Complex64](capacity=len(chips))
    for index in range(len(chips)):
        var sign_real = 1.0 if (index % 5) < 2 else -1.0
        var sign_imag = 1.0 if (index % 7) < 3 else -1.0
        result.append(Complex64(
            gain * (chips[index].re + noise * sign_real),
            gain * (chips[index].im + noise * sign_imag),
        ))
    return result^


def test_seeded_roundtrip_gain_noise_and_extreme_finite_scale() raises:
    var state = UInt64(0x94D049BB133111EB)
    for iteration in range(31):
        var payload = List[UInt8](capacity=1 + iteration)
        for _ in range(1 + iteration):
            state = (
                state * UInt64(2862933555777941757)
                + UInt64(3037000493)
            )
            payload.append(UInt8(state >> UInt64(56)))
        var selector = iteration % 7
        var short_preamble = selector >= 4
        var rate = WIFI_DSSS_RATE_1_MBPS_KBPS
        if selector == 1 or selector == 4:
            rate = WIFI_DSSS_RATE_2_MBPS_KBPS
        elif selector == 2 or selector == 5:
            rate = WIFI_DSSS_RATE_5_5_MBPS_KBPS
        elif selector == 3 or selector == 6:
            rate = WIFI_DSSS_RATE_11_MBPS_KBPS
        var config = WifiDSSSPLCPConfig(
            rate, short_preamble=short_preamble
        )
        var tx = wifi_dsss_ppdu_tx(Span(payload), config)
        var noisy = _gain_noise(Span(tx.ppdu_chips), 7.0, 0.015)
        var rx = wifi_dsss_ppdu_rx(
            Span(noisy), short_preamble=short_preamble
        )
        assert_equal(rx.payload_octets, payload)
        assert_true(rx.fcs_ok)

    var payload: List[UInt8] = [0x55, 0xAA]
    for gain in [1.0e-300, 1.0e300]:
        var config = WifiDSSSPLCPConfig(WIFI_DSSS_RATE_11_MBPS_KBPS)
        var tx = wifi_dsss_ppdu_tx(Span(payload), config)
        var scaled = _gain_noise(Span(tx.ppdu_chips), gain, 0.0)
        var rx = wifi_dsss_ppdu_rx(Span(scaled))
        assert_equal(rx.payload_octets, payload)
        assert_true(rx.fcs_ok)


def test_mutable_validation_crc_shape_nonfinite_and_corruption_edges() raises:
    var config = WifiDSSSPLCPConfig(WIFI_DSSS_RATE_11_MBPS_KBPS)
    _ = wifi_dsss_plcp_length(4, config)
    _ = wifi_dsss_plcp_header_pack(4, config)
    var empty_payload = List[UInt8]()
    _ = wifi_dsss_ppdu_tx(Span(empty_payload), config)
    config.data_rate_kbps = 6000
    with assert_raises():
        _ = wifi_dsss_plcp_length(4, config)
    with assert_raises():
        _ = wifi_dsss_plcp_header_pack(4, config)
    with assert_raises():
        _ = wifi_dsss_ppdu_tx(Span(empty_payload), config)
    with assert_raises():
        _ = WifiDSSSPLCPConfig(
            WIFI_DSSS_RATE_1_MBPS_KBPS, short_preamble=True
        )
    with assert_raises():
        _ = wifi_dsss_plcp_length(Int.MAX, WifiDSSSPLCPConfig(1000))

    var short_crc = List[UInt8](length=31, fill=UInt8(0))
    with assert_raises():
        _ = wifi_dsss_plcp_crc16(Span(short_crc))
    short_crc.append(UInt8(2))
    with assert_raises():
        _ = wifi_dsss_plcp_crc16(Span(short_crc))
    var bits: List[UInt8] = [0, 1, 1, 0]
    with assert_raises():
        _ = wifi_dsss_plcp_scramble(Span(bits), 0)
    with assert_raises():
        _ = wifi_dsss_plcp_descramble(Span(bits), 128)
    bits[2] = UInt8(2)
    with assert_raises():
        _ = wifi_dsss_plcp_scramble(Span(bits), 1)
    with assert_raises():
        _ = wifi_dsss_plcp_descramble(Span(bits), 1)

    var valid_config = WifiDSSSPLCPConfig(WIFI_DSSS_RATE_2_MBPS_KBPS)
    var header = wifi_dsss_plcp_header_pack(17, valid_config)
    header[0] ^= UInt8(1)
    with assert_raises():
        _ = wifi_dsss_plcp_header_parse(Span(header))
    var canonical = wifi_dsss_plcp_header_pack(17, valid_config)
    canonical[11] = UInt8(1)  # SERVICE b3 requests excluded PBCC.
    # Restore CRC independently so rejection is specifically SERVICE/PBCC.
    var crc = _oracle_crc16(Span(canonical[0:32]))
    for bit in range(16):
        canonical[32 + bit] = UInt8((crc >> bit) & 1)
    with assert_raises():
        _ = wifi_dsss_plcp_header_parse(Span(canonical))

    var payload: List[UInt8] = [1, 2, 3]
    var tx = wifi_dsss_ppdu_tx(Span(payload), valid_config)
    var short_chips = List[Complex64](capacity=len(tx.ppdu_chips) - 1)
    for index in range(len(tx.ppdu_chips) - 1):
        short_chips.append(tx.ppdu_chips[index])
    with assert_raises():
        _ = wifi_dsss_ppdu_rx(Span(short_chips))
    var extra_chips = tx.ppdu_chips.copy()
    extra_chips.append(Complex64(1.0, 0.0))
    with assert_raises():
        _ = wifi_dsss_ppdu_rx(Span(extra_chips))
    var nonfinite = tx.ppdu_chips.copy()
    nonfinite[0] = Complex64(nan[DType.float64](), 0.0)
    with assert_raises():
        _ = wifi_dsss_ppdu_rx(Span(nonfinite))
    nonfinite[0] = Complex64(0.0, inf[DType.float64]())
    with assert_raises():
        _ = wifi_dsss_ppdu_rx(Span(nonfinite))
    var zero_symbol = tx.ppdu_chips.copy()
    for chip in range(11):
        zero_symbol[chip] = Complex64(0.0, 0.0)
    with assert_raises():
        _ = wifi_dsss_ppdu_rx(Span(zero_symbol))

    # Flip one complete long-header DBPSK symbol: PLCP CRC must reject it.
    var bad_header = tx.ppdu_chips.copy()
    var header_offset = (
        WIFI_DSSS_LONG_SYNC_BITS + WIFI_DSSS_SFD_BITS
    ) * 11
    for chip in range(11):
        bad_header[header_offset + chip] = Complex64(
            -bad_header[header_offset + chip].re,
            -bad_header[header_offset + chip].im,
        )
    with assert_raises():
        _ = wifi_dsss_ppdu_rx(Span(bad_header))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
