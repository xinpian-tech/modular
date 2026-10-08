"""Independent evidence for IEEE 802.11-2024 Clause 17/18 OFDM.

The manual implementation below does not call a production transmitter,
encoder, interleaver, mapper, pilot helper, FFT, or FCS helper.  It transcribes
the current RATE table, K=7 polynomials, puncturing matrices, interleaver
permutations, Gray constellations, pilot LFSR, occupied-tone tables, and IDFT.
It is used both as a stage-by-stage TX oracle and as the sole producer of the
receive-only fixture.  Production TX-to-RX roundtrips are separate seeded
property evidence and are never presented as the independent oracle.

Discrete checkpoints are exact.  Manual IDFT comparisons use absolute
complex-component tolerance 5e-12.  The CRC-32 check value for the per-octet
LSB-first ASCII string ``123456789`` is the standard 0xCBF43926 fixture.
"""

from std.collections import Span
from std.math import cos, sin, sqrt
from std.testing import assert_equal, assert_raises, assert_true, TestSuite
from std.utils.numerics import inf, nan
from wireless_dsp.core import Complex64
from wireless_dsp.wireless.wifi.ofdm_erp import (
    WIFI_OFDM_CLAUSE_17,
    WIFI_ERP_OFDM_CLAUSE_18,
    WIFI_OFDM_SYMBOL_SAMPLES,
    WIFI_ERP_SIGNAL_EXTENSION_SAMPLES,
    WifiOFDMERPConfig,
    wifi_ofdm_erp_rate_profile,
    wifi_ofdm_erp_geometry,
    wifi_ofdm_erp_lsig_bits,
    wifi_erp_protection_decision,
    wifi_ofdm_erp_tx_20mhz,
    wifi_ofdm_erp_rx_20mhz,
)


comptime _TWO_PI = 6.283185307179586476925286766559
comptime _IDFT_TOLERANCE = 5.0e-12


struct _ManualRate(ImplicitlyCopyable):
    var code: Int
    var bpsc: Int
    var numerator: Int
    var denominator: Int
    var ncbps: Int
    var ndbps: Int

    def __init__(
        out self,
        code: Int,
        bpsc: Int,
        numerator: Int,
        denominator: Int,
        ncbps: Int,
        ndbps: Int,
    ):
        self.code = code
        self.bpsc = bpsc
        self.numerator = numerator
        self.denominator = denominator
        self.ncbps = ncbps
        self.ndbps = ndbps


struct _ManualTx(Movable):
    var fcs: UInt64
    var lsig_bits: List[UInt8]
    var lsig_coded: List[UInt8]
    var lsig_interleaved: List[UInt8]
    var lsig_symbols: List[Complex64]
    var lsig_spectrum: List[Complex64]
    var lsig_waveform: List[Complex64]
    var data_bits: List[UInt8]
    var scrambled: List[UInt8]
    var mother: List[UInt8]
    var punctured: List[UInt8]
    var interleaved: List[UInt8]
    var qam: List[Complex64]
    var spectra: List[Complex64]
    var data_waveform: List[Complex64]
    var stf: List[Complex64]
    var ltf: List[Complex64]
    var ppdu: List[Complex64]

    def __init__(
        out self,
        fcs: UInt64,
        var lsig_bits: List[UInt8],
        var lsig_coded: List[UInt8],
        var lsig_interleaved: List[UInt8],
        var lsig_symbols: List[Complex64],
        var lsig_spectrum: List[Complex64],
        var lsig_waveform: List[Complex64],
        var data_bits: List[UInt8],
        var scrambled: List[UInt8],
        var mother: List[UInt8],
        var punctured: List[UInt8],
        var interleaved: List[UInt8],
        var qam: List[Complex64],
        var spectra: List[Complex64],
        var data_waveform: List[Complex64],
        var stf: List[Complex64],
        var ltf: List[Complex64],
        var ppdu: List[Complex64],
    ):
        self.fcs = fcs
        self.lsig_bits = lsig_bits^
        self.lsig_coded = lsig_coded^
        self.lsig_interleaved = lsig_interleaved^
        self.lsig_symbols = lsig_symbols^
        self.lsig_spectrum = lsig_spectrum^
        self.lsig_waveform = lsig_waveform^
        self.data_bits = data_bits^
        self.scrambled = scrambled^
        self.mother = mother^
        self.punctured = punctured^
        self.interleaved = interleaved^
        self.qam = qam^
        self.spectra = spectra^
        self.data_waveform = data_waveform^
        self.stf = stf^
        self.ltf = ltf^
        self.ppdu = ppdu^


def _manual_rate(rate: Int) raises -> _ManualRate:
    if rate == 6:
        return _ManualRate(0b1011, 1, 1, 2, 48, 24)
    if rate == 9:
        return _ManualRate(0b1111, 1, 3, 4, 48, 36)
    if rate == 12:
        return _ManualRate(0b1010, 2, 1, 2, 96, 48)
    if rate == 18:
        return _ManualRate(0b1110, 2, 3, 4, 96, 72)
    if rate == 24:
        return _ManualRate(0b1001, 4, 1, 2, 192, 96)
    if rate == 36:
        return _ManualRate(0b1101, 4, 3, 4, 192, 144)
    if rate == 48:
        return _ManualRate(0b1000, 6, 2, 3, 288, 192)
    if rate == 54:
        return _ManualRate(0b1100, 6, 3, 4, 288, 216)
    raise Error("manual oracle received an unknown rate")


def _payload(octets: Int, salt: Int) -> List[UInt8]:
    var result = List[UInt8](capacity=8 * octets)
    for index in range(8 * octets):
        result.append(UInt8((index * 13 + index // 5 + salt) & 1))
    return result^


def _ascii_123456789() -> List[UInt8]:
    var result = List[UInt8](capacity=72)
    for octet in [0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39]:
        for bit in range(8):
            result.append(UInt8((octet >> bit) & 1))
    return result^


def _manual_fcs(bits: Span[UInt8, ...]) -> UInt64:
    var register = UInt64(0xFFFFFFFF)
    for index in range(len(bits)):
        var feedback = (register & UInt64(1)) ^ UInt64(bits[index])
        register >>= UInt64(1)
        if feedback != 0:
            register ^= UInt64(0xEDB88320)
    return register ^ UInt64(0xFFFFFFFF)


def _manual_lsig(rate: _ManualRate, length_octets: Int) -> List[UInt8]:
    var result = List[UInt8](capacity=24)
    var parity = UInt8(0)
    for bit in range(4):
        var value = UInt8((rate.code >> bit) & 1)
        result.append(value)
        parity ^= value
    result.append(UInt8(0))
    for bit in range(12):
        var value = UInt8((length_octets >> bit) & 1)
        result.append(value)
        parity ^= value
    result.append(parity)
    for _ in range(6):
        result.append(UInt8(0))
    return result^


def _parity(value: Int) -> UInt8:
    var remaining = value
    var result = UInt8(0)
    while remaining != 0:
        result ^= UInt8(remaining & 1)
        remaining >>= 1
    return result


def _manual_bcc(bits: Span[UInt8, ...]) -> List[UInt8]:
    var state = 0
    var result = List[UInt8](capacity=2 * len(bits))
    for index in range(len(bits)):
        state = ((state << 1) | Int(bits[index])) & 0x7F
        result.append(_parity(state & 0o133))
        result.append(_parity(state & 0o171))
    return result^


def _manual_puncture(
    bits: Span[UInt8, ...], rate: _ManualRate
) -> List[UInt8]:
    var pattern: List[UInt8]
    if rate.numerator == 1 and rate.denominator == 2:
        pattern = [1, 1]
    elif rate.numerator == 2 and rate.denominator == 3:
        pattern = [1, 1, 1, 0]
    else:
        pattern = [1, 1, 1, 0, 0, 1]
    var result = List[UInt8]()
    for index in range(len(bits)):
        if pattern[index % len(pattern)] == 1:
            result.append(bits[index])
    return result^


def _manual_interleave(
    bits: Span[UInt8, ...], bpsc: Int
) -> List[UInt8]:
    var ncbps = 48 * bpsc
    var s = max(bpsc // 2, 1)
    var result = List[UInt8](length=ncbps, fill=UInt8(0))
    for k in range(ncbps):
        var first = (ncbps // 16) * (k % 16) + k // 16
        var second = (
            s * (first // s)
            + (first + ncbps - (16 * first) // ncbps) % s
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
    bits: Span[UInt8, ...], bpsc: Int
) -> List[Complex64]:
    var result = List[Complex64](capacity=len(bits) // bpsc)
    var axis_bits = bpsc // 2
    var axis_mask = (1 << axis_bits) - 1
    var scale = (
        sqrt((2.0 / 3.0) * Float64((1 << bpsc) - 1))
        if bpsc > 1
        else 1.0
    )
    for symbol in range(len(bits) // bpsc):
        var label = 0
        for bit in range(bpsc):
            label = (label << 1) | Int(bits[symbol * bpsc + bit])
        if bpsc == 1:
            result.append(Complex64(1.0 if label == 0 else -1.0))
        else:
            var i_binary = _gray_to_binary((label >> axis_bits) & axis_mask)
            var q_binary = _gray_to_binary(label & axis_mask)
            result.append(Complex64(
                Float64(axis_mask - 2 * i_binary) / scale,
                Float64(axis_mask - 2 * q_binary) / scale,
            ))
    return result^


def _manual_idft_cp(
    spectrum: Span[Complex64, ...], cp: Int
) -> List[Complex64]:
    var time = List[Complex64](capacity=len(spectrum))
    for n in range(len(spectrum)):
        var value = Complex64(0.0, 0.0)
        for k in range(len(spectrum)):
            var angle = _TWO_PI * Float64(n * k) / Float64(len(spectrum))
            var tone = Complex64(spectrum[k].re, spectrum[k].im)
            value = value + tone * Complex64(cos(angle), sin(angle))
        time.append(Complex64(
            value.re / Float64(len(spectrum)),
            value.im / Float64(len(spectrum)),
        ))
    var result = List[Complex64](capacity=len(time) + cp)
    for index in range(len(time) - cp, len(time)):
        result.append(time[index])
    for value in time:
        result.append(value)
    return result^


def _manual_pilot(symbol_index: Int) -> Float64:
    var state = UInt8(0x7F)
    var polarity = 1.0
    for _ in range(symbol_index + 1):
        var feedback = ((state >> 6) ^ (state >> 3)) & 1
        polarity = 1.0 if feedback == 0 else -1.0
        state = ((state << 1) & 0x7E) | feedback
    return polarity


def _manual_data_carriers() -> List[Int]:
    var result = List[Int](capacity=48)
    for subcarrier in range(-26, 27):
        if (
            subcarrier != 0
            and subcarrier != -21
            and subcarrier != -7
            and subcarrier != 7
            and subcarrier != 21
        ):
            result.append(subcarrier)
    return result^


def _bin(subcarrier: Int) -> Int:
    return subcarrier if subcarrier >= 0 else 64 + subcarrier


def _manual_spectrum(
    data: Span[Complex64, ...], symbol_index: Int
) -> List[Complex64]:
    var spectrum = List[Complex64](length=64, fill=Complex64(0.0, 0.0))
    var carriers = _manual_data_carriers()
    for index in range(48):
        spectrum[_bin(carriers[index])] = data[index]
    var p = _manual_pilot(symbol_index)
    spectrum[_bin(-21)] = Complex64(p)
    spectrum[_bin(-7)] = Complex64(p)
    spectrum[_bin(7)] = Complex64(p)
    spectrum[_bin(21)] = Complex64(-p)
    return spectrum^


def _manual_stf() -> List[Complex64]:
    var spectrum = List[Complex64](length=64, fill=Complex64(0.0, 0.0))
    var scale = sqrt(13.0 / 6.0)
    var positive = Complex64(scale, scale)
    var negative = Complex64(-scale, -scale)
    for subcarrier, value in [
        (-24, positive), (-20, negative), (-16, positive), (-12, negative),
        (-8, negative), (-4, positive), (4, negative), (8, negative),
        (12, positive), (16, positive), (20, positive), (24, positive),
    ]:
        spectrum[_bin(subcarrier)] = value
    var full = _manual_idft_cp(Span(spectrum), 0)
    var result = List[Complex64](capacity=160)
    for _ in range(10):
        for index in range(16):
            result.append(full[index])
    return result^


def _manual_ltf() -> List[Complex64]:
    # IEEE legacy L-LTF row indexed k=-26..26, including DC=0.
    var values: List[Int] = [
        1, 1, -1, -1, 1, 1, -1, 1, -1, 1, 1, 1, 1, 1, 1, -1,
        -1, 1, 1, -1, 1, -1, 1, 1, 1, 1, 0, 1, -1, -1, 1, 1,
        -1, 1, -1, 1, -1, -1, -1, -1, -1, 1, 1, -1, -1, 1, -1,
        1, -1, 1, 1, 1, 1,
    ]
    var spectrum = List[Complex64](length=64, fill=Complex64(0.0, 0.0))
    for index in range(53):
        spectrum[_bin(-26 + index)] = Complex64(Float64(values[index]))
    var long = _manual_idft_cp(Span(spectrum), 0)
    var result = List[Complex64](capacity=160)
    for index in range(32, 64):
        result.append(long[index])
    for _ in range(2):
        for value in long:
            result.append(value)
    return result^


def _manual_scramble(
    bits: Span[UInt8, ...], seed: UInt8
) -> List[UInt8]:
    var state = seed
    var result = List[UInt8](capacity=len(bits))
    for index in range(len(bits)):
        var feedback = ((state >> 6) ^ (state >> 3)) & 1
        result.append(bits[index] ^ feedback)
        state = ((state << 1) & 0x7E) | feedback
    return result^


def _manual_tx(
    payload: Span[UInt8, ...],
    rate_mbps: Int,
    seed: UInt8,
    *,
    corrupt_fcs: Bool = False,
) raises -> _ManualTx:
    var rate = _manual_rate(rate_mbps)
    var psdu_octets = len(payload) // 8 + 4
    var before_pad = 16 + 8 * psdu_octets + 6
    var symbols = (before_pad + rate.ndbps - 1) // rate.ndbps

    var lsig = _manual_lsig(rate, psdu_octets)
    var lsig_coded = _manual_bcc(Span(lsig))
    var lsig_interleaved = _manual_interleave(Span(lsig_coded), 1)
    var lsig_symbols = _manual_qam(Span(lsig_interleaved), 1)
    var lsig_spectrum = _manual_spectrum(Span(lsig_symbols), 0)
    var lsig_waveform = _manual_idft_cp(Span(lsig_spectrum), 16)

    var fcs = _manual_fcs(payload)
    var transmitted_fcs = fcs ^ (UInt64(1) if corrupt_fcs else UInt64(0))
    var data = List[UInt8](capacity=symbols * rate.ndbps)
    for _ in range(16):
        data.append(UInt8(0))
    for index in range(len(payload)):
        data.append(payload[index])
    for bit in range(32):
        data.append(UInt8((transmitted_fcs >> UInt64(bit)) & UInt64(1)))
    var tail_start = len(data)
    for _ in range(6):
        data.append(UInt8(0))
    while len(data) < symbols * rate.ndbps:
        data.append(UInt8(0))
    var scrambled = _manual_scramble(Span(data), seed)
    for index in range(tail_start, tail_start + 6):
        scrambled[index] = UInt8(0)
    var mother = _manual_bcc(Span(scrambled))
    var punctured = _manual_puncture(Span(mother), rate)
    var interleaved = List[UInt8](capacity=symbols * rate.ncbps)
    var qam = List[Complex64](capacity=48 * symbols)
    var spectra = List[Complex64](capacity=64 * symbols)
    var waveform = List[Complex64](capacity=80 * symbols)
    for symbol in range(symbols):
        var block = List[UInt8](capacity=rate.ncbps)
        for index in range(rate.ncbps):
            block.append(punctured[symbol * rate.ncbps + index])
        var interleaved_block = _manual_interleave(Span(block), rate.bpsc)
        for bit in interleaved_block:
            interleaved.append(bit)
        var mapped = _manual_qam(Span(interleaved_block), rate.bpsc)
        for value in mapped:
            qam.append(value)
        var spectrum = _manual_spectrum(Span(mapped), symbol + 1)
        for value in spectrum:
            spectra.append(value)
        var one_waveform = _manual_idft_cp(Span(spectrum), 16)
        for value in one_waveform:
            waveform.append(value)

    var stf = _manual_stf()
    var ltf = _manual_ltf()
    var ppdu = List[Complex64](
        capacity=len(stf) + len(ltf) + len(lsig_waveform) + len(waveform)
    )
    for value in stf:
        ppdu.append(value)
    for value in ltf:
        ppdu.append(value)
    for value in lsig_waveform:
        ppdu.append(value)
    for value in waveform:
        ppdu.append(value)
    return _ManualTx(
        transmitted_fcs,
        lsig^,
        lsig_coded^,
        lsig_interleaved^,
        lsig_symbols^,
        lsig_spectrum^,
        lsig_waveform^,
        data^,
        scrambled^,
        mother^,
        punctured^,
        interleaved^,
        qam^,
        spectra^,
        waveform^,
        stf^,
        ltf^,
        ppdu^,
    )


def _assert_complex_close(
    actual: List[Complex64],
    expected: List[Complex64],
    tolerance: Float64 = _IDFT_TOLERANCE,
) raises:
    assert_equal(len(actual), len(expected))
    for index in range(len(actual)):
        assert_true(abs(actual[index].re - expected[index].re) <= tolerance)
        assert_true(abs(actual[index].im - expected[index].im) <= tolerance)


def test_exhaustive_rate_table_lsig_and_geometry() raises:
    var rates: List[Int] = [6, 9, 12, 18, 24, 36, 48, 54]
    var codes: List[Int] = [11, 15, 10, 14, 9, 13, 8, 12]
    var bpsc: List[Int] = [1, 1, 2, 2, 4, 4, 6, 6]
    var numerators: List[Int] = [1, 3, 1, 3, 1, 3, 2, 3]
    var denominators: List[Int] = [2, 4, 2, 4, 2, 4, 3, 4]
    var ncbps: List[Int] = [48, 48, 96, 96, 192, 192, 288, 288]
    var ndbps: List[Int] = [24, 36, 48, 72, 96, 144, 192, 216]
    for clause in [WIFI_OFDM_CLAUSE_17, WIFI_ERP_OFDM_CLAUSE_18]:
        for index in range(8):
            var config = WifiOFDMERPConfig(clause, rates[index])
            var row = wifi_ofdm_erp_rate_profile(config)
            assert_equal(row.rate_code_lsb_first, codes[index])
            assert_equal(row.bits_per_subcarrier, bpsc[index])
            assert_equal(row.code_rate_numerator, numerators[index])
            assert_equal(row.code_rate_denominator, denominators[index])
            assert_equal(row.coded_bits_per_symbol, ncbps[index])
            assert_equal(row.data_bits_per_symbol, ndbps[index])
            assert_equal(row.coded_bits_per_symbol, 48 * row.bits_per_subcarrier)
            assert_equal(
                row.signal_extension_samples,
                WIFI_ERP_SIGNAL_EXTENSION_SAMPLES
                if clause == WIFI_ERP_OFDM_CLAUSE_18
                else 0,
            )
            assert_equal(
                row.sifs_ns,
                10_000 if clause == WIFI_ERP_OFDM_CLAUSE_18 else 16_000,
            )
            var geometry = wifi_ofdm_erp_geometry(config, 100)
            var expected_before_pad = 16 + 800 + 6
            var expected_symbols = (
                expected_before_pad + ndbps[index] - 1
            ) // ndbps[index]
            assert_equal(geometry.data_bits_before_pad, expected_before_pad)
            assert_equal(geometry.data_symbols, expected_symbols)
            assert_equal(
                geometry.pad_bits,
                expected_symbols * ndbps[index] - expected_before_pad,
            )
            assert_equal(
                geometry.ppdu_samples,
                400 + WIFI_OFDM_SYMBOL_SAMPLES * expected_symbols,
            )
            assert_equal(
                geometry.medium_occupancy_samples,
                geometry.ppdu_samples + row.signal_extension_samples,
            )
            var expected_lsig = _manual_lsig(_manual_rate(rates[index]), 100)
            assert_equal(wifi_ofdm_erp_lsig_bits(config, 100), expected_lsig)


def test_transmit_independent_manual_cross_implementation() raises:
    var payload = _payload(13, 7)
    var config = WifiOFDMERPConfig(
        WIFI_OFDM_CLAUSE_17, 36, scrambler_seed=UInt8(0x5D)
    )
    var actual = wifi_ofdm_erp_tx_20mhz(
        Span(payload), config, testcase_id="clause17-manual-tx"
    )
    var expected = _manual_tx(Span(payload), 36, UInt8(0x5D))
    assert_equal(actual.fcs, expected.fcs)
    assert_equal(actual.lsig_bits, expected.lsig_bits)
    assert_equal(actual.lsig_coded_bits, expected.lsig_coded)
    assert_equal(actual.lsig_interleaved_bits, expected.lsig_interleaved)
    _assert_complex_close(actual.lsig_symbols, expected.lsig_symbols, 0.0)
    _assert_complex_close(actual.lsig_spectrum, expected.lsig_spectrum, 0.0)
    _assert_complex_close(actual.lsig_waveform, expected.lsig_waveform)
    assert_equal(actual.data_field_bits, expected.data_bits)
    assert_equal(actual.scrambled_bits, expected.scrambled)
    assert_equal(actual.mother_bits, expected.mother)
    assert_equal(actual.punctured_bits, expected.punctured)
    assert_equal(actual.interleaved_bits, expected.interleaved)
    _assert_complex_close(actual.qam_symbols, expected.qam, 0.0)
    _assert_complex_close(actual.data_spectra, expected.spectra, 0.0)
    _assert_complex_close(actual.data_waveform, expected.data_waveform)
    _assert_complex_close(actual.stf_waveform, expected.stf)
    _assert_complex_close(actual.ltf_waveform, expected.ltf)
    _assert_complex_close(actual.ppdu_waveform, expected.ppdu)
    assert_equal(actual.geometry.psdu_length_octets, 17)
    assert_true(len(actual.checkpoint_metadata) >= 18)
    for index in range(len(actual.checkpoint_metadata)):
        assert_equal(
            actual.checkpoint_metadata[index].testcase_id,
            "clause17-manual-tx",
        )
        assert_true(
            actual.checkpoint_metadata[index].stage.byte_length() > 0
        )
        assert_true(
            actual.checkpoint_metadata[index].shape.byte_length() > 0
        )


def test_receive_only_manual_fixture_complex_gain_and_fcs() raises:
    var payload = _payload(9, 3)
    var manual = _manual_tx(Span(payload), 24, UInt8(0x35))
    var gain = Complex64(0.61, -0.37)
    var observation = List[Complex64](capacity=len(manual.ppdu))
    for sample in manual.ppdu:
        observation.append(sample * gain)
    var rx = wifi_ofdm_erp_rx_20mhz(
        Span(observation),
        WIFI_ERP_OFDM_CLAUSE_18,
        testcase_id="clause18-independent-rx",
    )
    assert_equal(rx.profile.rate_mbps, 24)
    assert_equal(rx.geometry.psdu_length_octets, 13)
    assert_equal(rx.geometry.signal_extension_samples, 120)
    assert_equal(rx.mpdu_bits_without_fcs, payload)
    assert_equal(rx.scrambler_seed, UInt8(0x35))
    assert_equal(rx.received_fcs, _manual_fcs(Span(payload)))
    assert_equal(rx.computed_fcs, _manual_fcs(Span(payload)))
    assert_true(rx.service_ok)
    assert_true(rx.tail_ok)
    assert_true(rx.fcs_ok)
    for subcarrier in _manual_data_carriers():
        var estimate = rx.channel_estimate[_bin(subcarrier)]
        assert_true(abs(estimate.re - gain.re) <= _IDFT_TOLERANCE)
        assert_true(abs(estimate.im - gain.im) <= _IDFT_TOLERANCE)
    for index in range(len(rx.checkpoint_metadata)):
        assert_equal(
            rx.checkpoint_metadata[index].testcase_id,
            "clause18-independent-rx",
        )

    var corrupt = _manual_tx(
        Span(payload), 24, UInt8(0x35), corrupt_fcs=True
    )
    var corrupt_rx = wifi_ofdm_erp_rx_20mhz(
        Span(corrupt.ppdu), WIFI_ERP_OFDM_CLAUSE_18
    )
    assert_equal(corrupt_rx.mpdu_bits_without_fcs, payload)
    assert_true(not corrupt_rx.fcs_ok)
    assert_true(corrupt_rx.received_fcs != corrupt_rx.computed_fcs)


def test_seeded_all_rate_and_clause_roundtrip_property() raises:
    var state = UInt64(0xC001D00D5EED1234)
    var rates: List[Int] = [6, 9, 12, 18, 24, 36, 48, 54]
    for clause in [WIFI_OFDM_CLAUSE_17, WIFI_ERP_OFDM_CLAUSE_18]:
        for _ in range(24):
            state = (
                state * UInt64(6364136223846793005)
                + UInt64(1442695040888963407)
            )
            var rate = rates[Int((state >> 59) & UInt64(7))]
            var octets = Int((state >> 54) & UInt64(7))
            var seed = UInt8(1 + Int((state >> 32) % UInt64(127)))
            var payload = _payload(octets, Int(state & UInt64(31)))
            var config = WifiOFDMERPConfig(
                clause, rate, scrambler_seed=seed
            )
            var tx = wifi_ofdm_erp_tx_20mhz(Span(payload), config)
            var rx = wifi_ofdm_erp_rx_20mhz(Span(tx.ppdu_waveform), clause)
            assert_equal(rx.profile.rate_mbps, rate)
            assert_equal(rx.scrambler_seed, seed)
            assert_equal(rx.mpdu_bits_without_fcs, payload)
            assert_true(rx.service_ok and rx.tail_ok and rx.fcs_ok)


def test_crc_static_erp_inheritance_and_protection_decision() raises:
    var check = _ascii_123456789()
    var tx = wifi_ofdm_erp_tx_20mhz(
        Span(check), WifiOFDMERPConfig(WIFI_OFDM_CLAUSE_17, 54)
    )
    assert_equal(tx.fcs, UInt64(0xCBF43926))
    var unprotected = wifi_erp_protection_decision(False, False)
    assert_true(not unprotected.protect_erp_ofdm_exchange)
    var protected = wifi_erp_protection_decision(True, True)
    assert_true(protected.protect_erp_ofdm_exchange)
    assert_equal(protected.signal_extension_samples, 120)
    assert_true(protected.mechanism_selection_is_policy)
    var overlap = wifi_erp_protection_decision(False, True)
    assert_true(overlap.protect_erp_ofdm_exchange)
    with assert_raises():
        _ = wifi_erp_protection_decision(True, False)


def test_configuration_payload_and_mutation_edges() raises:
    with assert_raises():
        _ = WifiOFDMERPConfig(16, 6)
    with assert_raises():
        _ = WifiOFDMERPConfig(WIFI_OFDM_CLAUSE_17, 7)
    with assert_raises():
        _ = WifiOFDMERPConfig(
            WIFI_OFDM_CLAUSE_17, 6, scrambler_seed=UInt8(0)
        )
    var mutable_config = WifiOFDMERPConfig(WIFI_OFDM_CLAUSE_17, 6)
    mutable_config.rate_mbps = 7
    with assert_raises():
        _ = wifi_ofdm_erp_rate_profile(mutable_config)
    mutable_config.rate_mbps = 6
    mutable_config.scrambler_seed = UInt8(0)
    with assert_raises():
        _ = wifi_ofdm_erp_geometry(mutable_config, 10)

    var valid = WifiOFDMERPConfig(WIFI_OFDM_CLAUSE_17, 6)
    with assert_raises():
        _ = wifi_ofdm_erp_geometry(valid, -1)
    with assert_raises():
        _ = wifi_ofdm_erp_geometry(valid, 4096)
    var zero_length = wifi_ofdm_erp_lsig_bits(valid, 0)
    assert_equal(len(zero_length), 24)
    var non_octet: List[UInt8] = [0]
    with assert_raises():
        _ = wifi_ofdm_erp_tx_20mhz(Span(non_octet), valid)
    var non_binary = List[UInt8](length=8, fill=UInt8(0))
    non_binary[5] = UInt8(2)
    with assert_raises():
        _ = wifi_ofdm_erp_tx_20mhz(Span(non_binary), valid)
    var too_large = List[UInt8](
        length=8 * (4095 - 4) + 8, fill=UInt8(0)
    )
    with assert_raises():
        _ = wifi_ofdm_erp_tx_20mhz(Span(too_large), valid)


def test_receive_shape_and_nonfinite_edges() raises:
    var payload = _payload(2, 1)
    var tx = wifi_ofdm_erp_tx_20mhz(
        Span(payload), WifiOFDMERPConfig(WIFI_OFDM_CLAUSE_17, 12)
    )
    var truncated = tx.ppdu_waveform[0:len(tx.ppdu_waveform) - 1]
    with assert_raises():
        _ = wifi_ofdm_erp_rx_20mhz(
            Span(truncated), WIFI_OFDM_CLAUSE_17
        )
    var extended = tx.ppdu_waveform.copy()
    extended.append(Complex64(0.0, 0.0))
    with assert_raises():
        _ = wifi_ofdm_erp_rx_20mhz(Span(extended), WIFI_OFDM_CLAUSE_17)
    var nonfinite = tx.ppdu_waveform.copy()
    nonfinite[0] = Complex64(nan[DType.float64](), 0.0)
    with assert_raises():
        _ = wifi_ofdm_erp_rx_20mhz(Span(nonfinite), WIFI_OFDM_CLAUSE_17)
    nonfinite[0] = Complex64(0.0, inf[DType.float64]())
    with assert_raises():
        _ = wifi_ofdm_erp_rx_20mhz(Span(nonfinite), WIFI_OFDM_CLAUSE_17)
    var zeros = List[Complex64](
        length=len(tx.ppdu_waveform), fill=Complex64(0.0, 0.0)
    )
    with assert_raises():
        _ = wifi_ofdm_erp_rx_20mhz(Span(zeros), WIFI_OFDM_CLAUSE_17)
    with assert_raises():
        _ = wifi_ofdm_erp_rx_20mhz(Span(tx.ppdu_waveform), 19)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
