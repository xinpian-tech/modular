"""Independent evidence for bounded HE/EHT SIGNAL waveform chains.

The test oracle has its own scalar CRC registers, BCC tap parity, 13 by 4
interleaver, pilot LFSR, tone mapper, and direct O(N^2) inverse DFT.  Receiver
fixtures are built only by those test helpers, never by the production TX.
Discrete checkpoints use exact comparison; direct-DFT waveform comparison is
1e-11 absolute/relative, and the noisy complex-gain receive fixtures must
still recover every protected bit and decoded DATA profile exactly.
"""

from std.collections import Span
from std.math import cos, isfinite, sin, sqrt
from std.testing import assert_equal, assert_raises, assert_true, TestSuite
from std.utils.numerics import inf, nan
from wireless_dsp.core import Complex64
from wireless_dsp.wireless.wifi.he_eht_sig_fields import (
    WIFI_HE_EHT_SIG_CODING_BCC,
    WIFI_HE_EHT_SIG_CODING_LDPC,
    WifiEhtUSigSU20Config,
    WifiHeSigASUConfig,
)
from wireless_dsp.wireless.wifi.he_eht_sig_waveform import (
    WIFI_EHT_ACQUISITION_SOUNDING_NDP,
    WIFI_EHT_ACQUISITION_SU_DATA,
    WIFI_EHT_SU_SIGNAL_WAVEFORM_SAMPLES,
    WIFI_EHT_U_SIG_WAVEFORM_SAMPLES,
    WIFI_HE_EHT_SIG_WAVEFORM_CP_SAMPLES,
    WIFI_HE_EHT_SIG_WAVEFORM_DATA_TONES,
    WIFI_HE_EHT_SIG_WAVEFORM_FFT_SIZE,
    WIFI_HE_EHT_SIG_WAVEFORM_PILOT_TONES,
    WIFI_HE_EHT_SIG_WAVEFORM_SYMBOL_SAMPLES,
    WIFI_HE_SIG_A_ER_SU_WAVEFORM_SAMPLES,
    WIFI_HE_SIG_A_SU_WAVEFORM_SAMPLES,
    WifiEhtSigSU20Config,
    wifi_eht_sig_su_20_pack,
    wifi_eht_sig_su_20_parse,
    wifi_eht_u_sig_waveform_tx_20mhz,
    wifi_eht_u_sig_waveform_rx_20mhz,
    wifi_eht_su_signal_tx_20mhz,
    wifi_eht_su_signal_rx_20mhz,
    wifi_he_sig_a_waveform_tx_20mhz,
    wifi_he_sig_a_waveform_rx_20mhz,
    wifi_he_signal_driven_ldpc_rx_20mhz,
    wifi_eht_signal_driven_ldpc_rx_20mhz,
)
from wireless_dsp.wireless.wifi.phy_chain import wifi_ldpc_tx_20mhz
from wireless_dsp.wireless.wifi.preambles import wifi_ltf_waveform_20mhz
from wireless_dsp.wireless.wifi.profiles import WIFI_PHY_EHT, WIFI_PHY_HE


comptime _TWO_PI = 6.283185307179586476925286766559
comptime _ORACLE_ORDINARY = 0
comptime _ORACLE_HE_ER = 1
comptime _ORACLE_EHT_SIG = 2


def _append_lsb(mut output: List[UInt8], value: Int, width: Int):
    for index in range(width):
        output.append(UInt8((value >> index) & 1))


def _oracle_crc4(bits: Span[UInt8, ...]) -> Int:
    var c0 = 1
    var c1 = 1
    var c2 = 1
    var c3 = 1
    var c4 = 1
    var c5 = 1
    var c6 = 1
    var c7 = 1
    for bit_index in range(len(bits)):
        var feedback = c7 ^ Int(bits[bit_index])
        var old0 = c0
        var old1 = c1
        var old2 = c2
        var old3 = c3
        var old4 = c4
        var old5 = c5
        var old6 = c6
        c0 = feedback
        c1 = old0 ^ feedback
        c2 = old1 ^ feedback
        c3 = old2
        c4 = old3
        c5 = old4
        c6 = old5
        c7 = old6
    return (
        ((c7 ^ 1) << 3)
        | ((c6 ^ 1) << 2)
        | ((c5 ^ 1) << 1)
        | (c4 ^ 1)
    )


def _append_crc_and_tail(mut bits: List[UInt8]):
    var crc = _oracle_crc4(Span(bits))
    for index in range(4):
        bits.append(UInt8((crc >> (3 - index)) & 1))
    for _ in range(6):
        bits.append(UInt8(0))


def _refresh_crc(mut bits: List[UInt8], content_bits: Int):
    var crc = _oracle_crc4(bits[0:content_bits])
    for index in range(4):
        bits[content_bits + index] = UInt8((crc >> (3 - index)) & 1)


def _oracle_he_bits(config: WifiHeSigASUConfig) -> List[UInt8]:
    var bits = List[UInt8](capacity=52)
    bits.append(UInt8(1))
    bits.append(UInt8(1 if config.beam_change else 0))
    bits.append(UInt8(1 if config.uplink else 0))
    _append_lsb(bits, config.mcs_index, 4)
    bits.append(UInt8(1 if config.dcm else 0))
    _append_lsb(bits, config.bss_color, 6)
    bits.append(UInt8(1))
    _append_lsb(bits, config.spatial_reuse, 4)
    _append_lsb(bits, 0, 2)  # The waveform boundary is exactly 20 MHz.
    _append_lsb(bits, config.gi_ltf_code, 2)
    _append_lsb(bits, config.space_time_streams - 1, 3)
    _append_lsb(bits, config.txop_code, 7)
    bits.append(UInt8(config.coding))
    bits.append(
        UInt8(
            1
            if config.coding == WIFI_HE_EHT_SIG_CODING_BCC
            or config.ldpc_extra_symbol
            else 0
        )
    )
    bits.append(UInt8(1 if config.stbc else 0))
    bits.append(UInt8(1 if config.beamformed else 0))
    _append_lsb(bits, config.pre_fec_padding_factor, 2)
    bits.append(UInt8(1 if config.pe_disambiguity else 0))
    bits.append(UInt8(1))
    bits.append(UInt8(0))
    _append_crc_and_tail(bits)
    return bits^


def _oracle_u_sig_bits(config: WifiEhtUSigSU20Config) -> List[UInt8]:
    var bits = List[UInt8](capacity=52)
    _append_lsb(bits, 0, 6)
    bits.append(UInt8(1 if config.uplink else 0))
    _append_lsb(bits, config.bss_color, 6)
    _append_lsb(bits, config.txop_code, 7)
    for _ in range(6):
        bits.append(UInt8(1))
    _append_lsb(bits, 1, 2)
    bits.append(UInt8(1))
    _append_lsb(bits, 0, 5)
    bits.append(UInt8(1))
    _append_lsb(bits, config.eht_sig_mcs_code, 2)
    _append_lsb(bits, config.eht_sig_symbols - 1, 5)
    _append_crc_and_tail(bits)
    return bits^


def _oracle_eht_sig_bits(config: WifiEhtSigSU20Config) -> List[UInt8]:
    var bits = List[UInt8](capacity=52)
    _append_lsb(bits, config.spatial_reuse, 4)
    _append_lsb(bits, config.gi_ltf_code, 2)
    _append_lsb(bits, 0, 3)  # One EHT-LTF.
    bits.append(UInt8(1 if config.ldpc_extra_symbol else 0))
    _append_lsb(bits, config.pre_fec_padding_factor, 2)
    bits.append(UInt8(1 if config.pe_disambiguity else 0))
    for _ in range(4):
        bits.append(UInt8(1))
    _append_lsb(bits, 0, 3)  # One non-OFDMA user minus one.
    _append_lsb(bits, config.sta_id, 11)
    _append_lsb(bits, config.mcs_index, 4)
    bits.append(UInt8(1))
    _append_lsb(bits, config.spatial_streams - 1, 4)
    bits.append(UInt8(1 if config.beamformed else 0))
    bits.append(UInt8(config.coding))
    _append_crc_and_tail(bits)
    return bits^


def _parity(value: Int) -> UInt8:
    var work = value
    var result = UInt8(0)
    while work != 0:
        result ^= UInt8(work & 1)
        work >>= 1
    return result


def _oracle_bcc(bits: Span[UInt8, ...]) -> List[UInt8]:
    var state = 0
    var result = List[UInt8](capacity=2 * len(bits))
    for bit_index in range(len(bits)):
        state = ((state << 1) | Int(bits[bit_index])) & 0x7F
        result.append(_parity(state & 0o133))
        result.append(_parity(state & 0o171))
    return result^


def _oracle_interleave(bits: Span[UInt8, ...]) -> List[UInt8]:
    var result = List[UInt8](length=52, fill=UInt8(0))
    for source in range(52):
        var destination = 4 * (source % 13) + source // 13
        result[destination] = bits[source]
    return result^


def _oracle_pilot_polarity(symbol_index: Int) -> Float64:
    var state = UInt8(0x7F)
    var polarity = 1.0
    for _ in range(symbol_index + 1):
        var feedback = ((state >> 6) ^ (state >> 3)) & 1
        polarity = 1.0 if feedback == 0 else -1.0
        state = ((state << 1) & 0x7E) | feedback
    return polarity


def _oracle_data_subcarriers() -> List[Int]:
    var result = List[Int](capacity=52)
    for subcarrier in range(-28, 29):
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


def _oracle_ofdm_symbol(
    bits: Span[UInt8, ...], symbol_index: Int, mode: Int
) -> List[Complex64]:
    var spectrum = List[Complex64](length=64, fill=Complex64(0.0, 0.0))
    var data_indices = _oracle_data_subcarriers()
    var tone_scale = sqrt(64.0 / 56.0)
    for index in range(52):
        var value = 1.0 if bits[index] == 0 else -1.0
        var mapped = Complex64(value)
        if mode == _ORACLE_HE_ER:
            mapped = Complex64(0.0, value)
        elif mode == _ORACLE_EHT_SIG and index >= 26 and index % 2 != 0:
            mapped = -mapped
        spectrum[_bin(data_indices[index])] = mapped * Complex64(tone_scale)
    var polarity = _oracle_pilot_polarity(symbol_index)
    var pilot_indices: List[Int] = [-21, -7, 7, 21]
    var pilot_signs: List[Float64] = [1.0, 1.0, 1.0, -1.0]
    for index in range(4):
        spectrum[_bin(pilot_indices[index])] = Complex64(
            polarity * pilot_signs[index] * tone_scale
        )

    var useful = List[Complex64](capacity=64)
    for time_index in range(64):
        var accumulator = Complex64(0.0, 0.0)
        for frequency_index in range(64):
            var angle = (
                _TWO_PI
                * Float64(frequency_index * time_index)
                / 64.0
            )
            accumulator = accumulator + spectrum[frequency_index] * Complex64(
                cos(angle), sin(angle)
            )
        useful.append(accumulator * Complex64(1.0 / 64.0))
    var waveform = List[Complex64](capacity=80)
    for index in range(48, 64):
        waveform.append(useful[index])
    for value in useful:
        waveform.append(value)
    return waveform^


def _oracle_waveform(
    bits: Span[UInt8, ...], mode: Int, pilot_start: Int
) -> List[Complex64]:
    var coded = _oracle_bcc(bits)
    var symbol_count = 4 if mode == _ORACLE_HE_ER else 2
    var waveform = List[Complex64](capacity=symbol_count * 80)
    for emitted in range(symbol_count):
        var source = emitted
        var interleave = True
        var symbol_mode = _ORACLE_ORDINARY
        if mode == _ORACLE_HE_ER:
            source = emitted // 2
            interleave = emitted == 0 or emitted == 2
            if emitted == 1:
                symbol_mode = _ORACLE_HE_ER
        elif mode == _ORACLE_EHT_SIG:
            symbol_mode = _ORACLE_EHT_SIG
        var block = List[UInt8](capacity=52)
        for index in range(52):
            block.append(coded[source * 52 + index])
        if interleave:
            block = _oracle_interleave(Span(block))
        var symbol = _oracle_ofdm_symbol(
            Span(block), pilot_start + emitted, symbol_mode
        )
        for value in symbol:
            waveform.append(value)
    return waveform^


def _assert_close(
    actual: Float64, expected: Float64, tolerance: Float64
) raises:
    assert_true(isfinite(actual))
    assert_true(isfinite(expected))
    assert_true(
        abs(actual - expected)
        <= tolerance * max(1.0, max(abs(actual), abs(expected)))
    )


def _assert_complex_lists_close(
    actual: List[Complex64], expected: List[Complex64], tolerance: Float64
) raises:
    assert_equal(len(actual), len(expected))
    for index in range(len(actual)):
        _assert_close(actual[index].re, expected[index].re, tolerance)
        _assert_close(actual[index].im, expected[index].im, tolerance)


def _apply_gain_and_noise(
    samples: Span[Complex64, ...], gain: Complex64, noise: Float64
) -> List[Complex64]:
    var result = List[Complex64](capacity=len(samples))
    for index in range(len(samples)):
        var sample = samples[index]
        var deterministic_noise = Complex64(
            noise * cos(0.371 * Float64(index)),
            noise * sin(0.619 * Float64(index)),
        )
        result.append(sample * gain + deterministic_noise)
    return result^


def _payload_bits() -> List[UInt8]:
    var result = List[UInt8](capacity=64)
    for index in range(64):
        result.append(UInt8(((index * 13 + index // 3 + 1) >> 1) & 1))
    return result^


def test_he_su_tx_static_manual_oracle_and_checkpoints() raises:
    assert_equal(WIFI_HE_EHT_SIG_WAVEFORM_FFT_SIZE, 64)
    assert_equal(WIFI_HE_EHT_SIG_WAVEFORM_CP_SAMPLES, 16)
    assert_equal(WIFI_HE_EHT_SIG_WAVEFORM_SYMBOL_SAMPLES, 80)
    assert_equal(WIFI_HE_EHT_SIG_WAVEFORM_DATA_TONES, 52)
    assert_equal(WIFI_HE_EHT_SIG_WAVEFORM_PILOT_TONES, 4)
    assert_equal(WIFI_HE_SIG_A_SU_WAVEFORM_SAMPLES, 160)
    assert_equal(WIFI_HE_SIG_A_ER_SU_WAVEFORM_SAMPLES, 320)

    var config = WifiHeSigASUConfig(
        10,
        beam_change=True,
        bss_color=37,
        spatial_reuse=9,
        gi_ltf_code=3,
        txop_code=42,
        coding=WIFI_HE_EHT_SIG_CODING_LDPC,
        ldpc_extra_symbol=True,
        beamformed=True,
        pre_fec_padding_factor=2,
        pe_disambiguity=True,
    )
    var expected_bits = _oracle_he_bits(config)
    var expected_coded = _oracle_bcc(Span(expected_bits))
    var expected_waveform = _oracle_waveform(
        Span(expected_bits), _ORACLE_ORDINARY, 2
    )
    var tx = wifi_he_sig_a_waveform_tx_20mhz(
        config, testcase_id="he-su-static"
    )
    assert_equal(tx.bits, expected_bits)
    assert_equal(tx.coded_bits, expected_coded)
    assert_equal(len(tx.transmitted_bits), 104)
    assert_equal(tx.data_profile.family, WIFI_PHY_HE)
    assert_equal(tx.data_profile.mcs_index, 10)
    assert_equal(tx.data_profile.coding, WIFI_HE_EHT_SIG_CODING_LDPC)
    assert_equal(tx.data_profile.bits_per_subcarrier, 10)
    assert_equal(len(tx.waveform), 160)
    assert_equal(len(tx.checkpoint_metadata), 6)
    assert_equal(tx.checkpoint_metadata[0].testcase_id, "he-su-static")
    assert_equal(tx.checkpoint_metadata[0].stage, "bits")
    assert_equal(tx.checkpoint_metadata[5].stage, "waveform")
    _assert_complex_lists_close(tx.waveform, expected_waveform, 1.0e-11)

    var rx = wifi_he_sig_a_waveform_rx_20mhz(
        Span(expected_waveform), testcase_id="he-su-static-rx"
    )
    assert_equal(rx.decoded_bits, expected_bits)
    assert_equal(rx.fields.mcs_index, 10)
    assert_equal(rx.fields.bss_color, 37)
    assert_equal(rx.data_profile.code_rate_numerator, 3)
    assert_equal(rx.data_profile.code_rate_denominator, 4)
    assert_equal(rx.repetition_disagreements, 0)
    assert_equal(rx.checkpoint_metadata[0].testcase_id, "he-su-static-rx")


def test_he_er_su_independent_waveform_fixture_and_noisy_gain() raises:
    var config = WifiHeSigASUConfig(
        2,
        extended_range=True,
        uplink=True,
        bss_color=63,
        spatial_reuse=15,
        gi_ltf_code=1,
        txop_code=0,
        coding=WIFI_HE_EHT_SIG_CODING_BCC,
    )
    var bits = _oracle_he_bits(config)
    var coded = _oracle_bcc(Span(bits))
    var expected = _oracle_waveform(Span(bits), _ORACLE_HE_ER, 2)
    var tx = wifi_he_sig_a_waveform_tx_20mhz(config)
    _assert_complex_lists_close(tx.waveform, expected, 1.0e-11)
    assert_equal(len(tx.transmitted_bits), 208)
    for index in range(52):
        assert_equal(tx.transmitted_bits[52 + index], coded[index])
        assert_equal(tx.transmitted_bits[156 + index], coded[52 + index])

    var impaired = _apply_gain_and_noise(
        Span(expected), Complex64(0.71, -0.39), 0.004
    )
    var rx = wifi_he_sig_a_waveform_rx_20mhz(
        Span(impaired), extended_range=True
    )
    assert_equal(rx.decoded_bits, bits)
    assert_equal(rx.fields.extended_range, True)
    assert_equal(rx.fields.mcs_index, 2)
    assert_equal(rx.data_profile.coding, WIFI_HE_EHT_SIG_CODING_BCC)
    assert_equal(rx.repetition_disagreements, 0)
    assert_equal(len(rx.channel_estimates), 4)


def test_eht_su_content_static_manual_oracle_and_profile() raises:
    var config = WifiEhtSigSU20Config(
        13,
        sta_id=888,
        spatial_reuse=11,
        gi_ltf_code=3,
        ldpc_extra_symbol=True,
        pre_fec_padding_factor=2,
        pe_disambiguity=True,
        beamformed=True,
        coding=WIFI_HE_EHT_SIG_CODING_LDPC,
    )
    var expected = _oracle_eht_sig_bits(config)
    var actual = wifi_eht_sig_su_20_pack(config)
    assert_equal(actual, expected)
    assert_equal(len(actual), 52)
    assert_equal(
        Int(actual[42]) * 8
        + Int(actual[43]) * 4
        + Int(actual[44]) * 2
        + Int(actual[45]),
        _oracle_crc4(expected[0:42]),
    )
    var parsed = wifi_eht_sig_su_20_parse(Span(expected))
    assert_equal(parsed.spatial_reuse, 11)
    assert_equal(parsed.gi_ltf_code, 3)
    assert_equal(parsed.eht_ltf_symbols, 1)
    assert_equal(parsed.ldpc_extra_symbol, True)
    assert_equal(parsed.sta_id, 888)
    assert_equal(parsed.mcs_index, 13)
    assert_equal(parsed.spatial_streams, 1)
    assert_equal(parsed.beamformed, True)
    assert_equal(parsed.coding, WIFI_HE_EHT_SIG_CODING_LDPC)


def test_eht_u_sig_waveform_context_and_manual_oracle() raises:
    assert_equal(WIFI_EHT_U_SIG_WAVEFORM_SAMPLES, 160)
    var config = WifiEhtUSigSU20Config(
        45,
        uplink=True,
        txop_code=17,
        eht_sig_mcs_code=0,
        eht_sig_symbols=2,
    )
    var bits = _oracle_u_sig_bits(config)
    var expected = _oracle_waveform(Span(bits), _ORACLE_ORDINARY, 2)
    var tx = wifi_eht_u_sig_waveform_tx_20mhz(config)
    assert_equal(tx.bits, bits)
    assert_equal(tx.coded_bits, _oracle_bcc(Span(bits)))
    _assert_complex_lists_close(tx.waveform, expected, 1.0e-11)

    var su = wifi_eht_u_sig_waveform_rx_20mhz(
        Span(expected), WIFI_EHT_ACQUISITION_SU_DATA
    )
    var ndp = wifi_eht_u_sig_waveform_rx_20mhz(
        Span(expected), WIFI_EHT_ACQUISITION_SOUNDING_NDP
    )
    assert_equal(su.decoded_bits, bits)
    assert_equal(su.acquisition_context, WIFI_EHT_ACQUISITION_SU_DATA)
    assert_equal(ndp.decoded_bits, bits)
    assert_equal(
        ndp.acquisition_context, WIFI_EHT_ACQUISITION_SOUNDING_NDP
    )
    assert_equal(su.fields.eht_sig_mcs_code, 0)
    assert_equal(su.fields.eht_sig_symbols, 2)


def test_eht_combined_independent_fixture_drives_signal_geometry() raises:
    assert_equal(WIFI_EHT_SU_SIGNAL_WAVEFORM_SAMPLES, 320)
    var u_config = WifiEhtUSigSU20Config(
        9, txop_code=31, eht_sig_mcs_code=0, eht_sig_symbols=2
    )
    var e_config = WifiEhtSigSU20Config(
        13,
        sta_id=321,
        spatial_reuse=7,
        gi_ltf_code=2,
        coding=WIFI_HE_EHT_SIG_CODING_LDPC,
    )
    var u_bits = _oracle_u_sig_bits(u_config)
    var e_bits = _oracle_eht_sig_bits(e_config)
    var u_waveform = _oracle_waveform(
        Span(u_bits), _ORACLE_ORDINARY, 2
    )
    var e_waveform = _oracle_waveform(
        Span(e_bits), _ORACLE_EHT_SIG, 4
    )
    var expected = List[Complex64](capacity=320)
    for value in u_waveform:
        expected.append(value)
    for value in e_waveform:
        expected.append(value)
    var tx = wifi_eht_su_signal_tx_20mhz(u_config, e_config)
    _assert_complex_lists_close(tx.waveform, expected, 1.0e-11)
    assert_equal(tx.eht_sig_bits, e_bits)

    var impaired = _apply_gain_and_noise(
        Span(expected), Complex64(-0.43, 0.82), 0.003
    )
    var rx = wifi_eht_su_signal_rx_20mhz(
        Span(impaired), WIFI_EHT_ACQUISITION_SU_DATA
    )
    assert_equal(rx.u_sig.decoded_bits, u_bits)
    assert_equal(rx.eht_sig_decoded_bits, e_bits)
    assert_equal(rx.eht_sig_fields.sta_id, 321)
    assert_equal(rx.data_profile.family, WIFI_PHY_EHT)
    assert_equal(rx.data_profile.mcs_index, 13)
    assert_equal(rx.data_profile.bits_per_subcarrier, 12)
    assert_equal(rx.data_profile.code_rate_numerator, 5)
    assert_equal(rx.data_profile.code_rate_denominator, 6)

    with assert_raises():
        _ = wifi_eht_su_signal_rx_20mhz(
            Span(expected), WIFI_EHT_ACQUISITION_SOUNDING_NDP
        )
    var wrong_geometry_u = WifiEhtUSigSU20Config(
        9, eht_sig_mcs_code=0, eht_sig_symbols=1
    )
    with assert_raises():
        _ = wifi_eht_su_signal_tx_20mhz(wrong_geometry_u, e_config)


def test_signal_driven_ldpc_data_receive() raises:
    var payload = _payload_bits()
    var he_config = WifiHeSigASUConfig(
        10, coding=WIFI_HE_EHT_SIG_CODING_LDPC
    )
    var he_bits = _oracle_he_bits(he_config)
    var he_signal = _oracle_waveform(
        Span(he_bits), _ORACLE_ORDINARY, 2
    )
    var he_data = wifi_ldpc_tx_20mhz(
        Span(payload), WIFI_PHY_HE, 10, scrambler_seed=UInt8(0x5D)
    )
    var he_ltf = wifi_ltf_waveform_20mhz(
        WIFI_PHY_HE, cyclic_prefix_samples=16
    )
    var he_rx = wifi_he_signal_driven_ldpc_rx_20mhz(
        Span(he_signal),
        Span(he_data.waveform),
        Span(he_ltf),
        len(payload),
        0.01,
        scrambler_seed=UInt8(0x5D),
    )
    assert_equal(he_rx.signal.data_profile.mcs_index, 10)
    assert_equal(he_rx.data.payload_bits, payload)
    assert_true(he_rx.data.ldpc_converged)
    assert_true(he_rx.data.service_ok)
    assert_true(he_rx.data.fcs_ok)

    var u_config = WifiEhtUSigSU20Config(
        4, eht_sig_mcs_code=0, eht_sig_symbols=2
    )
    var e_config = WifiEhtSigSU20Config(
        13, sta_id=77, coding=WIFI_HE_EHT_SIG_CODING_LDPC
    )
    var u_bits = _oracle_u_sig_bits(u_config)
    var e_bits = _oracle_eht_sig_bits(e_config)
    var eht_signal = _oracle_waveform(
        Span(u_bits), _ORACLE_ORDINARY, 2
    )
    var eht_tail = _oracle_waveform(
        Span(e_bits), _ORACLE_EHT_SIG, 4
    )
    for value in eht_tail:
        eht_signal.append(value)
    var eht_data = wifi_ldpc_tx_20mhz(
        Span(payload), WIFI_PHY_EHT, 13, scrambler_seed=UInt8(0x4B)
    )
    var eht_ltf = wifi_ltf_waveform_20mhz(
        WIFI_PHY_EHT, cyclic_prefix_samples=16
    )
    var eht_rx = wifi_eht_signal_driven_ldpc_rx_20mhz(
        Span(eht_signal),
        Span(eht_data.waveform),
        Span(eht_ltf),
        len(payload),
        0.01,
        WIFI_EHT_ACQUISITION_SU_DATA,
        scrambler_seed=UInt8(0x4B),
    )
    assert_equal(eht_rx.signal.data_profile.mcs_index, 13)
    assert_equal(eht_rx.data.payload_bits, payload)
    assert_true(eht_rx.data.ldpc_converged)
    assert_true(eht_rx.data.service_ok)
    assert_true(eht_rx.data.fcs_ok)


def test_waveform_edges_mutation_corruption_nonfinite_and_scale() raises:
    var he = WifiHeSigASUConfig(0)
    var he_bits = _oracle_he_bits(he)
    var he_waveform = _oracle_waveform(
        Span(he_bits), _ORACLE_ORDINARY, 2
    )
    var short = he_waveform[0:159]
    with assert_raises():
        _ = wifi_he_sig_a_waveform_rx_20mhz(short)
    var zeros = List[Complex64](length=160, fill=Complex64(0.0, 0.0))
    with assert_raises():
        _ = wifi_he_sig_a_waveform_rx_20mhz(Span(zeros))
    var nonfinite = he_waveform.copy()
    nonfinite[17] = Complex64(nan[DType.float64]())
    with assert_raises():
        _ = wifi_he_sig_a_waveform_rx_20mhz(Span(nonfinite))
    nonfinite = he_waveform.copy()
    nonfinite[81] = Complex64(inf[DType.float64]())
    with assert_raises():
        _ = wifi_he_sig_a_waveform_rx_20mhz(Span(nonfinite))

    var bad_crc = he_bits.copy()
    bad_crc[3] ^= UInt8(1)
    var bad_crc_waveform = _oracle_waveform(
        Span(bad_crc), _ORACLE_ORDINARY, 2
    )
    with assert_raises():
        _ = wifi_he_sig_a_waveform_rx_20mhz(Span(bad_crc_waveform))
    var bad_tail = he_bits.copy()
    bad_tail[51] = UInt8(1)
    var bad_tail_waveform = _oracle_waveform(
        Span(bad_tail), _ORACLE_ORDINARY, 2
    )
    with assert_raises():
        _ = wifi_he_sig_a_waveform_rx_20mhz(Span(bad_tail_waveform))

    var huge = List[Complex64](capacity=160)
    var tiny = List[Complex64](capacity=160)
    for value in he_waveform:
        huge.append(value * Complex64(1.0e300))
        tiny.append(value * Complex64(1.0e-300))
    assert_equal(
        wifi_he_sig_a_waveform_rx_20mhz(Span(huge)).decoded_bits,
        he_bits,
    )
    assert_equal(
        wifi_he_sig_a_waveform_rx_20mhz(Span(tiny)).decoded_bits,
        he_bits,
    )

    he.bandwidth_mhz = 40
    with assert_raises():
        _ = wifi_he_sig_a_waveform_tx_20mhz(he)
    he.bandwidth_mhz = 20
    he.space_time_streams = 2
    with assert_raises():
        _ = wifi_he_sig_a_waveform_tx_20mhz(he)
    var he_dcm = wifi_he_sig_a_waveform_tx_20mhz(
        WifiHeSigASUConfig(0, dcm=True)
    )
    assert_equal(he_dcm.data_profile.dcm, True)

    var valid_u = WifiEhtUSigSU20Config(
        12, eht_sig_mcs_code=0, eht_sig_symbols=2
    )
    var valid_u_bits = _oracle_u_sig_bits(valid_u)
    var valid_u_waveform = _oracle_waveform(
        Span(valid_u_bits), _ORACLE_ORDINARY, 2
    )
    var bad_u = valid_u
    bad_u.bss_color = 64
    with assert_raises():
        _ = wifi_eht_u_sig_waveform_tx_20mhz(bad_u)
    var short_u = valid_u_waveform[0:159]
    with assert_raises():
        _ = wifi_eht_u_sig_waveform_rx_20mhz(
            short_u, WIFI_EHT_ACQUISITION_SU_DATA
        )
    var nonfinite_u = valid_u_waveform.copy()
    nonfinite_u[79] = Complex64(nan[DType.float64]())
    with assert_raises():
        _ = wifi_eht_u_sig_waveform_rx_20mhz(
            Span(nonfinite_u), WIFI_EHT_ACQUISITION_SU_DATA
        )

    var e = WifiEhtSigSU20Config(13)
    e.spatial_streams = 2
    with assert_raises():
        _ = wifi_eht_sig_su_20_pack(e)
    e.spatial_streams = 1
    e.sta_id = 2046
    with assert_raises():
        _ = wifi_eht_sig_su_20_pack(e)
    e.sta_id = 1
    e.coding = WIFI_HE_EHT_SIG_CODING_BCC
    with assert_raises():
        _ = wifi_eht_sig_su_20_pack(e)

    var valid_e = WifiEhtSigSU20Config(13, sta_id=1)
    var fixed_bad = _oracle_eht_sig_bits(valid_e)
    fixed_bad[35] = UInt8(0)
    _refresh_crc(fixed_bad, 42)
    with assert_raises():
        _ = wifi_eht_sig_su_20_parse(Span(fixed_bad))
    with assert_raises():
        _ = wifi_eht_u_sig_waveform_rx_20mhz(
            Span(he_waveform), 99
        )

    var valid_e_bits = _oracle_eht_sig_bits(valid_e)
    var valid_e_waveform = _oracle_waveform(
        Span(valid_e_bits), _ORACLE_EHT_SIG, 4
    )
    var combined = valid_u_waveform.copy()
    for value in valid_e_waveform:
        combined.append(value)
    var short_combined = combined[0:319]
    with assert_raises():
        _ = wifi_eht_su_signal_rx_20mhz(
            short_combined, WIFI_EHT_ACQUISITION_SU_DATA
        )

    var wrong_geometry_u = WifiEhtUSigSU20Config(
        12, eht_sig_mcs_code=0, eht_sig_symbols=1
    )
    var wrong_geometry_bits = _oracle_u_sig_bits(wrong_geometry_u)
    var wrong_geometry_signal = _oracle_waveform(
        Span(wrong_geometry_bits), _ORACLE_ORDINARY, 2
    )
    for value in valid_e_waveform:
        wrong_geometry_signal.append(value)
    with assert_raises():
        _ = wifi_eht_su_signal_rx_20mhz(
            Span(wrong_geometry_signal), WIFI_EHT_ACQUISITION_SU_DATA
        )

    var corrupted_u_bits = valid_u_bits.copy()
    corrupted_u_bits[7] ^= UInt8(1)
    var corrupted_signal = _oracle_waveform(
        Span(corrupted_u_bits), _ORACLE_ORDINARY, 2
    )
    for value in valid_e_waveform:
        corrupted_signal.append(value)
    with assert_raises():
        _ = wifi_eht_su_signal_rx_20mhz(
            Span(corrupted_signal), WIFI_EHT_ACQUISITION_SU_DATA
        )

    var empty_data_samples = List[Complex64]()
    var empty_ltf_samples = List[Complex64]()
    var wrong_he = WifiHeSigASUConfig(
        9, coding=WIFI_HE_EHT_SIG_CODING_LDPC
    )
    var wrong_he_bits = _oracle_he_bits(wrong_he)
    var wrong_he_waveform = _oracle_waveform(
        Span(wrong_he_bits), _ORACLE_ORDINARY, 2
    )
    with assert_raises():
        _ = wifi_he_signal_driven_ldpc_rx_20mhz(
            Span(wrong_he_waveform),
            Span(empty_data_samples),
            Span(empty_ltf_samples),
            0,
            0.01,
        )

    var wrong_e = WifiEhtSigSU20Config(
        12, sta_id=1, coding=WIFI_HE_EHT_SIG_CODING_LDPC
    )
    var wrong_e_bits = _oracle_eht_sig_bits(wrong_e)
    var wrong_e_waveform = _oracle_waveform(
        Span(wrong_e_bits), _ORACLE_EHT_SIG, 4
    )
    var wrong_e_signal = valid_u_waveform.copy()
    for value in wrong_e_waveform:
        wrong_e_signal.append(value)
    with assert_raises():
        _ = wifi_eht_signal_driven_ldpc_rx_20mhz(
            Span(wrong_e_signal),
            Span(empty_data_samples),
            Span(empty_ltf_samples),
            0,
            0.01,
            WIFI_EHT_ACQUISITION_SU_DATA,
        )


def test_seeded_differential_properties_and_tolerance() raises:
    var state = UInt64(0xD1B54A32D192ED03)
    for iteration in range(17):
        state = state * UInt64(6364136223846793005) + UInt64(1442695040888963407)
        var mcs = Int((state >> 8) % UInt64(12))
        var coding = (
            WIFI_HE_EHT_SIG_CODING_LDPC
            if mcs >= 10 or ((state >> 20) & UInt64(1)) != 0
            else WIFI_HE_EHT_SIG_CODING_BCC
        )
        var he = WifiHeSigASUConfig(
            mcs,
            beam_change=((state >> 21) & UInt64(1)) != 0,
            uplink=((state >> 22) & UInt64(1)) != 0,
            bss_color=Int((state >> 23) & UInt64(63)),
            spatial_reuse=Int((state >> 29) & UInt64(15)),
            gi_ltf_code=Int((state >> 33) & UInt64(3)),
            txop_code=Int((state >> 35) & UInt64(127)),
            coding=coding,
            ldpc_extra_symbol=(
                coding == WIFI_HE_EHT_SIG_CODING_LDPC
                and ((state >> 42) & UInt64(1)) != 0
            ),
            beamformed=((state >> 43) & UInt64(1)) != 0,
            pre_fec_padding_factor=Int((state >> 44) & UInt64(3)),
            pe_disambiguity=((state >> 46) & UInt64(1)) != 0,
        )
        var he_bits = _oracle_he_bits(he)
        var he_tx = wifi_he_sig_a_waveform_tx_20mhz(he)
        assert_equal(he_tx.bits, he_bits)
        assert_equal(he_tx.coded_bits, _oracle_bcc(Span(he_bits)))
        if iteration < 5:
            var expected_he = _oracle_waveform(
                Span(he_bits), _ORACLE_ORDINARY, 2
            )
            _assert_complex_lists_close(
                he_tx.waveform, expected_he, 1.0e-11
            )
        assert_equal(
            wifi_he_sig_a_waveform_rx_20mhz(
                Span(he_tx.waveform)
            ).decoded_bits,
            he_bits,
        )

        state = state * UInt64(2862933555777941757) + UInt64(3037000493)
        var eht_mcs = Int((state >> 5) % UInt64(14))
        var eht_coding = (
            WIFI_HE_EHT_SIG_CODING_LDPC
            if eht_mcs >= 10 or ((state >> 19) & UInt64(1)) != 0
            else WIFI_HE_EHT_SIG_CODING_BCC
        )
        var u = WifiEhtUSigSU20Config(
            Int((state >> 20) & UInt64(63)),
            uplink=((state >> 26) & UInt64(1)) != 0,
            txop_code=Int((state >> 27) & UInt64(127)),
            eht_sig_mcs_code=0,
            eht_sig_symbols=2,
        )
        var e = WifiEhtSigSU20Config(
            eht_mcs,
            sta_id=Int((state >> 34) % UInt64(2046)),
            spatial_reuse=Int((state >> 45) & UInt64(15)),
            gi_ltf_code=Int((state >> 49) & UInt64(3)),
            ldpc_extra_symbol=(
                eht_coding == WIFI_HE_EHT_SIG_CODING_LDPC
                and ((state >> 51) & UInt64(1)) != 0
            ),
            pre_fec_padding_factor=Int((state >> 52) & UInt64(3)),
            pe_disambiguity=((state >> 54) & UInt64(1)) != 0,
            beamformed=((state >> 55) & UInt64(1)) != 0,
            coding=eht_coding,
        )
        var u_bits = _oracle_u_sig_bits(u)
        var e_bits = _oracle_eht_sig_bits(e)
        var combined = wifi_eht_su_signal_tx_20mhz(u, e)
        assert_equal(combined.u_sig.bits, u_bits)
        assert_equal(combined.eht_sig_bits, e_bits)
        assert_equal(
            combined.eht_sig_coded_bits, _oracle_bcc(Span(e_bits))
        )
        var decoded = wifi_eht_su_signal_rx_20mhz(
            Span(combined.waveform), WIFI_EHT_ACQUISITION_SU_DATA
        )
        assert_equal(decoded.u_sig.decoded_bits, u_bits)
        assert_equal(decoded.eht_sig_decoded_bits, e_bits)
        assert_equal(decoded.data_profile.mcs_index, eht_mcs)
        assert_equal(decoded.data_profile.coding, eht_coding)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
