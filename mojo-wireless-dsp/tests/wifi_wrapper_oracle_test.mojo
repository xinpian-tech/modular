"""Independent differential oracles for the three composite Wi-Fi wrappers.

The LDPC vectors below are packed, bit-exact vectors generated outside Mojo by
an independent GF(2) Gaussian solver from the IEEE 802.11 1944-bit QC-LDPC
shift tables.  Runtime expectations never call a production helper below the
wrapper under test.  The acquisition oracle rebuilds every exposed field from
the standard CRC, scrambler, BCC, interleaver, carrier, pilot, and inverse-DFT
formulas.  The channel oracle separately implements the documented LCG,
Box-Muller, block-Rician, timing, CFO, and AWGN equations.
"""

from std.collections import Span
from std.math import cos, log, sin, sqrt
from std.testing import assert_equal, assert_true, TestSuite
from wireless_dsp.core import Complex64
from wireless_dsp.wireless.wifi import (
    WIFI_PHY_HT,
    WIFI_PHY_HE,
    WIFI_PHY_EHT,
    WifiAcquisitionChannelConfig,
    wifi_ldpc_tx_20mhz,
    wifi_acquisition_tx_20mhz,
    wifi_acquisition_apply_channel_20mhz,
)


comptime TWO_PI = 6.283185307179586476925286766559
comptime BIT_EXACT_TOLERANCE = 0.0
comptime CONSTELLATION_TOLERANCE = 2.0e-15
comptime IDFT_TOLERANCE = 3.0e-12
comptime CHANNEL_TOLERANCE = 3.0e-14


struct _ManualFrame(Movable):
    var bits: List[UInt8]
    var fcs: UInt64

    def __init__(out self, var bits: List[UInt8], fcs: UInt64):
        self.bits = bits^
        self.fcs = fcs


struct _ManualSignal(Movable):
    var bits: List[UInt8]
    var coded: List[UInt8]
    var interleaved: List[UInt8]
    var symbols: List[Complex64]
    var waveform: List[Complex64]

    def __init__(
        out self,
        var bits: List[UInt8],
        var coded: List[UInt8],
        var interleaved: List[UInt8],
        var symbols: List[Complex64],
        var waveform: List[Complex64],
    ):
        self.bits = bits^
        self.coded = coded^
        self.interleaved = interleaved^
        self.symbols = symbols^
        self.waveform = waveform^


def _pattern_payload(octets: Int, salt: Int) -> List[UInt8]:
    var result = List[UInt8](capacity=8 * octets)
    for i in range(8 * octets):
        result.append(UInt8((13 * i + i // 5 + salt) & 1))
    return result^


def _ascii_123456789_lsb_first() -> List[UInt8]:
    var result = List[UInt8](capacity=72)
    for octet in [
        0x31,
        0x32,
        0x33,
        0x34,
        0x35,
        0x36,
        0x37,
        0x38,
        0x39,
    ]:
        for bit in range(8):
            result.append(UInt8((octet >> bit) & 1))
    return result^


def _manual_fcs(bits: Span[UInt8, ...]) -> UInt64:
    var register = UInt64(0xFFFFFFFF)
    for i in range(len(bits)):
        var feedback = (register & UInt64(1)) ^ UInt64(bits[i])
        register >>= UInt64(1)
        if feedback != 0:
            register ^= UInt64(0xEDB88320)
    return register ^ UInt64(0xFFFFFFFF)


def _manual_frame(payload: Span[UInt8, ...]) -> _ManualFrame:
    var fcs = _manual_fcs(payload)
    var frame = List[UInt8](capacity=16 + len(payload) + 32)
    for _ in range(16):
        frame.append(UInt8(0))
    for i in range(len(payload)):
        frame.append(payload[i])
    for shift in range(32):
        frame.append(UInt8((fcs >> UInt64(shift)) & UInt64(1)))
    return _ManualFrame(frame^, fcs)


def _manual_scramble(bits: Span[UInt8, ...], seed: UInt8) -> List[UInt8]:
    var state = seed
    var result = List[UInt8](capacity=len(bits))
    for i in range(len(bits)):
        var feedback = ((state >> 6) ^ (state >> 3)) & 1
        result.append(bits[i] ^ feedback)
        state = ((state << 1) & 0x7E) | feedback
    return result^


def _parity(value: Int) -> UInt8:
    var remaining = value
    var result = UInt8(0)
    while remaining != 0:
        result ^= UInt8(remaining & 1)
        remaining >>= 1
    return result


def _manual_bcc(bits: Span[UInt8, ...]) -> List[UInt8]:
    var result = List[UInt8](capacity=2 * len(bits))
    var register = 0
    for i in range(len(bits)):
        register = ((register << 1) | Int(bits[i])) & 0x7F
        result.append(_parity(register & 0o133))
        result.append(_parity(register & 0o171))
    return result^


def _manual_puncture_three_quarters(
    bits: Span[UInt8, ...],
) -> List[UInt8]:
    var pattern: List[UInt8] = [1, 1, 1, 0, 0, 1]
    var result = List[UInt8]()
    for i in range(len(bits)):
        if pattern[i % 6] == 1:
            result.append(bits[i])
    return result^


def _manual_interleave(
    bits: Span[UInt8, ...],
    bits_per_subcarrier: Int,
    columns: Int,
    rows_per_modulation_bit: Int,
) -> List[UInt8]:
    var coded_bits = len(bits)
    var rows = rows_per_modulation_bit * bits_per_subcarrier
    var s = max(bits_per_subcarrier // 2, 1)
    var result = List[UInt8](length=coded_bits, fill=UInt8(0))
    for k in range(coded_bits):
        var first = rows * (k % columns) + k // columns
        var second = (
            s * (first // s)
            + (first + coded_bits - (columns * first) // coded_bits) % s
        )
        result[second] = bits[k]
    return result^


def _gray_to_binary(gray: Int) -> Int:
    var result = gray
    var shifted = gray >> 1
    while shifted != 0:
        result ^= shifted
        shifted >>= 1
    return result


def _manual_qam(
    bits: Span[UInt8, ...], bits_per_symbol: Int
) -> List[Complex64]:
    var result = List[Complex64](capacity=len(bits) // bits_per_symbol)
    var axis_bits = bits_per_symbol // 2
    var axis_mask = (1 << axis_bits) - 1
    var scale = sqrt(
        (2.0 / 3.0) * Float64((1 << bits_per_symbol) - 1)
    ) if bits_per_symbol > 1 else 1.0
    for symbol in range(len(bits) // bits_per_symbol):
        var label = 0
        for local_bit in range(bits_per_symbol):
            label = (
                (label << 1)
                | Int(bits[symbol * bits_per_symbol + local_bit])
            )
        if bits_per_symbol == 1:
            result.append(Complex64(1.0 if label == 0 else -1.0))
        else:
            var i_binary = _gray_to_binary(
                (label >> axis_bits) & axis_mask
            )
            var q_binary = _gray_to_binary(label & axis_mask)
            result.append(Complex64(
                Float64(axis_mask - 2 * i_binary) / scale,
                Float64(axis_mask - 2 * q_binary) / scale,
            ))
    return result^


def _manual_idft_with_cp(
    spectrum: Span[Complex64, ...], cyclic_prefix: Int
) -> List[Complex64]:
    var time = List[Complex64](capacity=len(spectrum))
    for n in range(len(spectrum)):
        var value = Complex64(0.0, 0.0)
        for k in range(len(spectrum)):
            var angle = TWO_PI * Float64(n * k) / Float64(len(spectrum))
            value = value + Complex64(
                spectrum[k].re, spectrum[k].im
            ) * Complex64(cos(angle), sin(angle))
        time.append(Complex64(
            value.re / Float64(len(spectrum)),
            value.im / Float64(len(spectrum)),
        ))
    var result = List[Complex64](capacity=len(time) + cyclic_prefix)
    for i in range(len(time) - cyclic_prefix, len(time)):
        result.append(time[i])
    for sample in time:
        result.append(sample)
    return result^


def _manual_pilot_polarity(symbol_index: Int) -> Float64:
    var state = UInt8(0x7F)
    var polarity = 1.0
    for _ in range(symbol_index + 1):
        var feedback = ((state >> 6) ^ (state >> 3)) & 1
        polarity = 1.0 if feedback == 0 else -1.0
        state = ((state << 1) & 0x7E) | feedback
    return polarity


def _manual_ht_pilots(symbol_index: Int) -> List[Complex64]:
    var p = _manual_pilot_polarity(symbol_index)
    return [Complex64(p), Complex64(p), Complex64(p), Complex64(-p)]


def _manual_he_eht_pilots(
    family: Int, symbol_index: Int
) -> List[Complex64]:
    var base: List[Int] = [1, 1, 1, -1, -1, 1, 1, 1]
    var polarity = (
        _manual_pilot_polarity(symbol_index)
        if family == WIFI_PHY_EHT
        else 1.0
    )
    var result = List[Complex64](capacity=8)
    for i in range(8):
        result.append(Complex64(
            polarity * Float64(base[(i + symbol_index % 8) % 8])
        ))
    return result^


def _manual_ht_spectrum(
    data: Span[Complex64, ...], pilots: Span[Complex64, ...]
) -> List[Complex64]:
    var result = List[Complex64](length=64, fill=Complex64(0.0, 0.0))
    var source = 0
    for subcarrier in range(-28, 29):
        if (
            subcarrier == 0
            or subcarrier == -21
            or subcarrier == -7
            or subcarrier == 7
            or subcarrier == 21
        ):
            continue
        var bin_index = subcarrier if subcarrier >= 0 else 64 + subcarrier
        result[bin_index] = data[source]
        source += 1
    var pilot_indices: List[Int] = [-21, -7, 7, 21]
    for i in range(4):
        var bin_index = (
            pilot_indices[i]
            if pilot_indices[i] >= 0
            else 64 + pilot_indices[i]
        )
        result[bin_index] = pilots[i]
    return result^


def _manual_legacy_spectrum(
    data: Span[Complex64, ...]
) -> List[Complex64]:
    var carriers: List[Int] = [
        -26, -25, -24, -23, -22, -20, -19, -18,
        -17, -16, -15, -14, -13, -12, -11, -10,
        -9, -8, -6, -5, -4, -3, -2, -1,
        1, 2, 3, 4, 5, 6, 8, 9,
        10, 11, 12, 13, 14, 15, 16, 17,
        18, 19, 20, 22, 23, 24, 25, 26,
    ]
    var result = List[Complex64](length=64, fill=Complex64(0.0, 0.0))
    for i in range(48):
        var k = carriers[i]
        result[k if k >= 0 else 64 + k] = data[i]
    result[64 - 21] = Complex64(1.0)
    result[64 - 7] = Complex64(1.0)
    result[7] = Complex64(1.0)
    result[21] = Complex64(-1.0)
    return result^


def _manual_ru242_spectrum(
    data: Span[Complex64, ...], pilots: Span[Complex64, ...]
) raises -> List[Complex64]:
    var pilot_indices: List[Int] = [-116, -90, -48, -22, 22, 48, 90, 116]
    var result = List[Complex64](length=256, fill=Complex64(0.0, 0.0))
    var data_source = 0
    for subcarrier in range(-122, 123):
        if subcarrier == -1 or subcarrier == 0 or subcarrier == 1:
            continue
        var is_pilot = False
        for pilot in pilot_indices:
            if subcarrier == pilot:
                is_pilot = True
                break
        if not is_pilot:
            result[
                subcarrier if subcarrier >= 0 else 256 + subcarrier
            ] = data[data_source]
            data_source += 1
    for i in range(8):
        var k = pilot_indices[i]
        result[k if k >= 0 else 256 + k] = pilots[i]
    assert_equal(data_source, 234)
    return result^


def _manual_stf_short() -> List[Complex64]:
    var spectrum = List[Complex64](length=64, fill=Complex64(0.0, 0.0))
    var scale = sqrt(13.0 / 6.0)
    var carriers: List[Int] = [
        -24, -20, -16, -12, -8, -4, 4, 8, 12, 16, 20, 24,
    ]
    var signs: List[Int] = [1, -1, 1, -1, -1, 1, -1, -1, 1, 1, 1, 1]
    for i in range(12):
        var k = carriers[i]
        var value = Float64(signs[i]) * scale
        spectrum[k if k >= 0 else 64 + k] = Complex64(value, value)
    var full = _manual_idft_with_cp(Span(spectrum), 0)
    var result = List[Complex64](capacity=16)
    for i in range(16):
        result.append(full[i])
    return result^


def _manual_stf_waveform(short: Span[Complex64, ...]) -> List[Complex64]:
    var result = List[Complex64](capacity=160)
    for _ in range(10):
        for i in range(len(short)):
            result.append(short[i])
    return result^


def _manual_ht_ltf_waveform() -> List[Complex64]:
    # IEEE HT-LTF one-stream row for k=-28..28.
    var values: List[Int] = [
        1, 1, 1, 1, -1, -1, 1, 1, -1, 1, -1, 1, 1, 1, 1, 1,
        1, -1, -1, 1, 1, -1, 1, -1, 1, 1, 1, 1, 0,
        1, -1, -1, 1, 1, -1, 1, -1, 1, -1, -1, -1, -1, -1,
        1, 1, -1, -1, 1, -1, 1, -1, 1, 1, 1, 1, -1, -1,
    ]
    var spectrum = List[Complex64](length=64, fill=Complex64(0.0, 0.0))
    for i in range(57):
        var k = -28 + i
        spectrum[k if k >= 0 else 64 + k] = Complex64(Float64(values[i]))
    return _manual_idft_with_cp(Span(spectrum), 16)


def _manual_legacy_signal(length_octets: Int) -> _ManualSignal:
    var bits: List[UInt8] = [1, 1, 0, 1, 0]
    var parity = UInt8(1 ^ 1 ^ 0 ^ 1)
    for shift in range(12):
        var bit = UInt8((length_octets >> shift) & 1)
        bits.append(bit)
        parity ^= bit
    bits.append(parity)
    for _ in range(6):
        bits.append(UInt8(0))
    var coded = _manual_bcc(Span(bits))
    var interleaved = _manual_interleave(Span(coded), 1, 16, 3)
    var symbols = _manual_qam(Span(interleaved), 1)
    var spectrum = _manual_legacy_spectrum(Span(symbols))
    var waveform = _manual_idft_with_cp(Span(spectrum), 16)
    return _ManualSignal(
        bits^, coded^, interleaved^, symbols^, waveform^
    )


def _unpack_static_bits(
    words: Span[UInt64, ...], bit_count: Int
) -> List[UInt8]:
    var result = List[UInt8](capacity=bit_count)
    for i in range(bit_count):
        result.append(UInt8(
            (words[i // 64] >> UInt64(i % 64)) & UInt64(1)
        ))
    return result^


def _manual_tone_map(
    rate_matched: Span[UInt8, ...], bits_per_subcarrier: Int
) -> List[UInt8]:
    var result = List[UInt8](length=len(rate_matched), fill=UInt8(0))
    for source_tone in range(234):
        var destination_tone = (
            9 * (source_tone % 26) + (source_tone * 9) // 234
        )
        for bit in range(bits_per_subcarrier):
            result[destination_tone * bits_per_subcarrier + bit] = (
                rate_matched[source_tone * bits_per_subcarrier + bit]
            )
    return result^


def _assert_complex_close(
    actual: List[Complex64],
    expected: List[Complex64],
    tolerance: Float64,
) raises:
    assert_equal(len(actual), len(expected))
    for i in range(len(actual)):
        assert_true(abs(actual[i].re - expected[i].re) <= tolerance)
        assert_true(abs(actual[i].im - expected[i].im) <= tolerance)


def _he_rate_matched_words() -> List[UInt64]:
    return [
        UInt64(0x8F7D3EB3DADF9836), UInt64(0xC9BC396E81489AA7),
        UInt64(0x4BDD879FDCE38649), UInt64(0xFC182D3B23BC8B62),
        UInt64(0x1462A0D728404F47), UInt64(0x9D14D0AC1DBD5D77),
        UInt64(0x4C00DC088CE6162F), UInt64(0x42E970903F52CDA3),
        UInt64(0xBEC65F88256BCD26), UInt64(0x10F8DB50D998EAB2),
        UInt64(0x3C7BE9F59ED6FE55), UInt64(0x4E4DE1CB740A44D5),
        UInt64(0x125EEC3CFEE71C32), UInt64(0xD1ADD35EE7B0145B),
        UInt64(0xA5A59E12CECA93F4), UInt64(0xF981676C54312C54),
        UInt64(0x36EBD6202C53F3D4), UInt64(0xB3D07177CF64A92A),
        UInt64(0xF8305A76477A7EFC), UInt64(0x28C541AE50809E8F),
        UInt64(0x3A29A1583B7ABAEE), UInt64(0x9801B81119CC2C5F),
        UInt64(0x85D2E1207EA59B46), UInt64(0x7D8CBF104AD79A4C),
        UInt64(0x21F1B6A1B331D565), UInt64(0x78F7D3EB3DADFCAA),
        UInt64(0x9C9BC396E81489AA), UInt64(0x24BDD879FDCE3864),
        UInt64(0x7FC182D3B23BC8B6), UInt64(0x71462A0D728404F4),
        UInt64(0xF9D14D0AC1DBD5D7), UInt64(0x25A78524722C072F),
        UInt64(0x97EF4AEAA195FC5F), UInt64(0x9CC30799DEC64DA4),
        UInt64(0xA6DA65D2296DC9AF), UInt64(0x02EB41F76EC2BD78),
        UInt64(0x0000000826293C4F),
    ]


def _eht_rate_matched_words() -> List[UInt64]:
    return [
        UInt64(0x8F7D3EB3DADF9836), UInt64(0xC9BC396E81489AA7),
        UInt64(0x4BDD879FDCE38649), UInt64(0xFC182D3B23BC8B62),
        UInt64(0x1462A0D728404F47), UInt64(0x9D14D0AC1DBD5D77),
        UInt64(0x4C00DC088CE6162F), UInt64(0x42E970903F52CDA3),
        UInt64(0xBEC65F88256BCD26), UInt64(0x10F8DB50D998EAB2),
        UInt64(0x3C7BE9F59ED6FE55), UInt64(0x4E4DE1CB740A44D5),
        UInt64(0x125EEC3CFEE71C32), UInt64(0x3FE0C169D91DE45B),
        UInt64(0xB8A31506B942027A), UInt64(0x7CE8A68560EDEAEB),
        UInt64(0xF46006E0446730B1), UInt64(0xE42B2F87DC7E2E36),
        UInt64(0xD67C852A364E0E12), UInt64(0x80B524F59EECF18F),
        UInt64(0x79CBF29031726A91), UInt64(0xAC48EFF86F95523F),
        UInt64(0x2174B8481FA966D1), UInt64(0x5F632FC412B5E693),
        UInt64(0x887C6DA86CCC7559), UInt64(0x9E3DF4FACF6B7F2A),
        UInt64(0x2726F0E5BA05226A), UInt64(0x892F761E7F738E19),
        UInt64(0x1FF060B4EC8EF22D), UInt64(0xDC518A835CA1013D),
        UInt64(0xBE745342B076F575), UInt64(0x8D30037022339858),
        UInt64(0x990BA5C240FD4B36), UInt64(0xCAFB197E2095AF34),
        UInt64(0x5443E36D436663AA), UInt64(0x54F1EFA7D67B5BF9),
        UInt64(0xC93937872DD02913), UInt64(0x6C497BB0F3FB9C70),
        UInt64(0xFA63C45F12C47791), UInt64(0x8BC0E47477F09003),
        UInt64(0x064A29AB84E9D48D), UInt64(0x3CD94116BBE8DF1D),
        UInt64(0xF772B918ED4384DF), UInt64(0x005839218900F5C7),
    ]


def _assert_ldpc_external_vector(
    family: Int,
    mcs_index: Int,
    octets: Int,
    salt: Int,
    symbol_index: Int,
    expected_fcs: UInt64,
    expected_block_length: Int,
    expected_shortened: Int,
    expected_punctured: Int,
    expected_repeated: Int,
    static_words: List[UInt64],
) raises:
    var payload = _pattern_payload(octets, salt)
    var tx = wifi_ldpc_tx_20mhz(
        Span(payload), family, mcs_index, symbol_index=symbol_index
    )
    var manual_frame = _manual_frame(Span(payload))
    var expected_frame = manual_frame.bits.copy()
    assert_equal(manual_frame.fcs, expected_fcs)
    var expected_scrambled = _manual_scramble(
        Span(expected_frame), UInt8(0x5D)
    )
    var bits_per_subcarrier = 10 if family == WIFI_PHY_HE else 12
    var coded_bits = 234 * bits_per_subcarrier
    var expected_rate_matched = _unpack_static_bits(
        Span(static_words), coded_bits
    )
    var expected_tone_mapped = _manual_tone_map(
        Span(expected_rate_matched), bits_per_subcarrier
    )
    var expected_symbols = _manual_qam(
        Span(expected_tone_mapped), bits_per_subcarrier
    )
    var expected_pilots = _manual_he_eht_pilots(family, symbol_index)
    var expected_spectrum = _manual_ru242_spectrum(
        Span(expected_symbols), Span(expected_pilots)
    )
    var expected_waveform = _manual_idft_with_cp(
        Span(expected_spectrum), 16
    )

    assert_equal(tx.family, family)
    assert_equal(tx.mcs_index, mcs_index)
    assert_equal(tx.payload_bit_count, 8 * octets)
    assert_equal(tx.fcs, expected_fcs)
    assert_equal(tx.ldpc_block_length, expected_block_length)
    assert_equal(tx.shortened_bits, expected_shortened)
    assert_equal(tx.punctured_bits, expected_punctured)
    assert_equal(tx.repeated_bits, expected_repeated)
    assert_equal(tx.frame_bits, expected_frame)
    assert_equal(tx.scrambled_bits, expected_scrambled)
    assert_equal(tx.rate_matched_bits, expected_rate_matched)
    assert_equal(tx.tone_mapped_bits, expected_tone_mapped)
    _assert_complex_close(
        tx.qam_symbols, expected_symbols, CONSTELLATION_TOLERANCE
    )
    _assert_complex_close(
        tx.spectrum, expected_spectrum, CONSTELLATION_TOLERANCE
    )
    _assert_complex_close(tx.waveform, expected_waveform, IDFT_TOLERANCE)


def test_wifi_ldpc_tx_20mhz_against_external_qc_ldpc_vectors() raises:
    """Pin both wrapper branches through every returned LDPC/OFDM checkpoint."""
    var he_words = _he_rate_matched_words()
    _assert_ldpc_external_vector(
        WIFI_PHY_HE,
        10,
        205,
        0x62,
        4,
        UInt64(0x7F2CB07E),
        1296,
        256,
        0,
        4,
        he_words^,
    )
    var eht_words = _eht_rate_matched_words()
    _assert_ldpc_external_vector(
        WIFI_PHY_EHT,
        13,
        264,
        4,
        5,
        UInt64(0x615CE108),
        1944,
        1080,
        0,
        0,
        eht_words^,
    )


def test_wifi_acquisition_tx_20mhz_against_manual_packet_oracle() raises:
    """Rebuild STF, LTF, L-SIG, and HT DATA without production helpers."""
    var payload = _ascii_123456789_lsb_first()
    var tx = wifi_acquisition_tx_20mhz(
        Span(payload), WIFI_PHY_HT, 6, symbol_index=3
    )

    var manual_frame = _manual_frame(Span(payload))
    var base_frame = manual_frame.bits.copy()
    assert_equal(manual_frame.fcs, UInt64(0xCBF43926))
    var tail_start = len(base_frame)
    var data_field = base_frame.copy()
    for _ in range(6):
        data_field.append(UInt8(0))
    while len(data_field) < 234:
        data_field.append(UInt8(0))
    var scrambled = _manual_scramble(Span(data_field), UInt8(0x5D))
    for i in range(tail_start, tail_start + 6):
        scrambled[i] = UInt8(0)
    var mother = _manual_bcc(Span(scrambled))
    var punctured = _manual_puncture_three_quarters(Span(mother))
    var data_interleaved = _manual_interleave(
        Span(punctured), 6, 13, 4
    )
    var data_symbols = _manual_qam(Span(data_interleaved), 6)
    var data_pilots = _manual_ht_pilots(3)
    var data_spectrum = _manual_ht_spectrum(
        Span(data_symbols), Span(data_pilots)
    )
    var data_waveform = _manual_idft_with_cp(Span(data_spectrum), 16)

    var short = _manual_stf_short()
    var stf = _manual_stf_waveform(Span(short))
    var ltf = _manual_ht_ltf_waveform()
    var signal = _manual_legacy_signal(13)
    var packet = List[Complex64](capacity=400)
    for sample in stf:
        packet.append(sample)
    for sample in ltf:
        packet.append(sample)
    for sample in signal.waveform:
        packet.append(sample)
    for sample in data_waveform:
        packet.append(sample)

    assert_equal(tx.family, WIFI_PHY_HT)
    assert_equal(tx.mcs_index, 6)
    assert_equal(tx.payload_bit_count, 72)
    assert_equal(tx.scrambler_seed, UInt8(0x5D))
    assert_equal(tx.symbol_index, 3)
    assert_equal(tx.fcs, UInt64(0xCBF43926))
    assert_equal((tx.ltf_offset, tx.signal_offset, tx.data_offset), (160, 240, 320))
    assert_equal(tx.signal_rate_bits, [UInt8(1), 1, 0, 1])
    assert_equal(tx.signal_length_octets, 13)
    assert_equal(tx.signal_bits, signal.bits)
    assert_equal(tx.signal_coded_bits, signal.coded)
    assert_equal(tx.signal_interleaved_bits, signal.interleaved)
    _assert_complex_close(
        tx.signal_symbols, signal.symbols, BIT_EXACT_TOLERANCE
    )
    assert_equal(tx.data_field_bits, data_field)
    assert_equal(tx.interleaved_bits, data_interleaved)
    _assert_complex_close(
        tx.qam_symbols, data_symbols, CONSTELLATION_TOLERANCE
    )
    _assert_complex_close(tx.stf_short_symbol, short, IDFT_TOLERANCE)
    _assert_complex_close(tx.stf_waveform, stf, IDFT_TOLERANCE)
    _assert_complex_close(tx.ltf_waveform, ltf, IDFT_TOLERANCE)
    _assert_complex_close(
        tx.signal_waveform, signal.waveform, IDFT_TOLERANCE
    )
    _assert_complex_close(tx.data_waveform, data_waveform, IDFT_TOLERANCE)
    _assert_complex_close(tx.packet_waveform, packet, IDFT_TOLERANCE)


def _uniform(mut state: UInt64) -> Float64:
    state = (
        state * UInt64(6364136223846793005)
        + UInt64(1442695040888963407)
    )
    return (Float64(state >> 11) + 0.5) / 9007199254740992.0


def _unit_complex_gaussian(mut state: UInt64) -> Complex64:
    var radius = sqrt(-log(_uniform(state)))
    var angle = TWO_PI * _uniform(state)
    return Complex64(radius * cos(angle), radius * sin(angle))


def test_wifi_acquisition_apply_channel_20mhz_against_manual_rng_oracle(
) raises:
    """Independently evaluate every random draw and channel operation."""
    var samples: List[Complex64] = [
        Complex64(1.0, -0.5),
        Complex64(-0.25, 0.75),
        Complex64(0.125, 0.25),
        Complex64(-1.5, -0.125),
    ]
    var timing_offset = 3
    var normalized_cfo = -0.003125
    var noise_variance = 0.125
    var k_factor = 3.5
    var seed = UInt64(0x123456789ABCDEF0)
    var config = WifiAcquisitionChannelConfig(
        timing_offset=timing_offset,
        normalized_cfo=normalized_cfo,
        noise_variance=noise_variance,
        rician_k_factor=k_factor,
        seed=seed,
    )
    var actual = wifi_acquisition_apply_channel_20mhz(
        Span(samples), config
    )

    var fading_state = seed
    var scatter = _unit_complex_gaussian(fading_state)
    var los_scale = sqrt(k_factor / (k_factor + 1.0))
    var scatter_scale = sqrt(1.0 / (k_factor + 1.0))
    var coefficient = Complex64(
        los_scale + scatter_scale * scatter.re,
        scatter_scale * scatter.im,
    )
    var expected_faded = List[Complex64](capacity=len(samples))
    for sample in samples:
        expected_faded.append(sample * coefficient)

    var noise_state = seed ^ UInt64(0xD1B54A32D192ED03)
    var sigma = sqrt(noise_variance * 0.5)
    var expected_observation = List[Complex64](capacity=7)
    for n in range(len(samples) + timing_offset):
        var shifted = Complex64(0.0, 0.0)
        if n >= timing_offset:
            var faded = expected_faded[n - timing_offset]
            var phase = TWO_PI * normalized_cfo * Float64(n)
            shifted = faded * Complex64(cos(phase), sin(phase))
        var u1 = _uniform(noise_state)
        var u2 = _uniform(noise_state)
        var radius = sigma * sqrt(-2.0 * log(u1))
        expected_observation.append(Complex64(
            shifted.re + radius * cos(TWO_PI * u2),
            shifted.im + radius * sin(TWO_PI * u2),
        ))

    assert_equal(actual.timing_offset, timing_offset)
    assert_true(actual.normalized_cfo == normalized_cfo)
    assert_true(actual.noise_variance == noise_variance)
    assert_true(actual.rician_k_factor == k_factor)
    assert_equal(actual.seed, seed)
    _assert_complex_close(
        actual.faded_waveform, expected_faded, CHANNEL_TOLERANCE
    )
    _assert_complex_close(
        actual.observation, expected_observation, CHANNEL_TOLERANCE
    )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
