"""Static and acquired-link checks for the representative Wi-Fi chain."""

from std.collections import Span
from std.math import sqrt
from std.testing import assert_equal, assert_true, assert_raises, TestSuite
from std.utils.numerics import inf, nan
from wireless_dsp.core import Complex64
from wireless_dsp.dsp import ofdm_demodulate
from wireless_dsp.fec import convolutional_encode
from wireless_dsp.modem import qam_map
from wireless_dsp.testing import CheckpointMetadata
from wireless_dsp.wireless.wifi.profiles import (
    WIFI_PHY_HT,
    WIFI_PHY_VHT,
    WIFI_PHY_HE,
)
from wireless_dsp.wireless.wifi.legacy import (
    wifi_interleave,
    wifi_map_legacy_symbol,
)
from wireless_dsp.wireless.wifi.acquisition_chain import (
    WifiAcquisitionChannelConfig,
    wifi_stf_spectrum_20mhz,
    wifi_stf_short_symbol_20mhz,
    wifi_stf_waveform_20mhz,
    wifi_legacy_signal_tx_20mhz,
    wifi_ltf_fine_timing_20mhz,
    wifi_acquisition_tx_20mhz,
    wifi_acquisition_apply_channel_20mhz,
    wifi_acquisition_rx_20mhz,
    wifi_ltf_fine_cfo_20mhz,
)


def _assert_checkpoint_metadata(
    metadata: List[CheckpointMetadata],
    testcase_id: StringSlice,
    stages: List[String],
    dtypes: List[String],
    shapes: List[String],
    q_formats: List[String],
    layouts: List[String],
) raises:
    assert_equal(len(metadata), len(stages))
    assert_equal(len(metadata), len(dtypes))
    assert_equal(len(metadata), len(shapes))
    assert_equal(len(metadata), len(q_formats))
    assert_equal(len(metadata), len(layouts))
    for index in range(len(metadata)):
        assert_equal(metadata[index].testcase_id, testcase_id)
        assert_equal(metadata[index].stage, stages[index])
        assert_equal(metadata[index].dtype, dtypes[index])
        assert_equal(metadata[index].shape, shapes[index])
        assert_equal(metadata[index].stride, "1")
        assert_equal(metadata[index].q_format, q_formats[index])
        assert_equal(metadata[index].scale, 1.0)
        assert_equal(metadata[index].version, 1)
        assert_equal(metadata[index].layout, layouts[index])


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


def _legacy_signal_waveform_from_uncoded_bits(
    bits: Span[UInt8, ...],
) raises -> List[Complex64]:
    """Test-only SIGNAL constructor independent of the acquisition helper."""
    var generators: List[Int] = [0o133, 0o171]
    var coded = convolutional_encode(
        bits, Span(generators), 7, terminate=False
    )
    var interleaved = wifi_interleave(Span(coded), 1)
    var symbols = qam_map(Span(interleaved), 1)
    return wifi_map_legacy_symbol(Span(symbols), symbol_index=0)


def _packet_with_legacy_signal(
    packet: Span[Complex64, ...], signal_offset: Int, bits: Span[UInt8, ...]
) raises -> List[Complex64]:
    var result = List[Complex64](capacity=len(packet))
    for i in range(len(packet)):
        result.append(packet[i])
    var signal = _legacy_signal_waveform_from_uncoded_bits(bits)
    for i in range(len(signal)):
        result[signal_offset + i] = signal[i]
    return result^


def _refresh_signal_parity(mut bits: List[UInt8]) raises:
    if len(bits) != 24:
        raise Error("test SIGNAL field must contain 24 bits")
    var parity = UInt8(0)
    for i in range(17):
        parity ^= bits[i]
    bits[17] = parity


def test_legacy_l_sig_static_bits_bcc_interleaver_and_spectrum() raises:
    """Independent 9-octet vector pins every bit before the L-SIG IFFT."""
    var signal = wifi_legacy_signal_tx_20mhz(9)
    var expected_bits: List[UInt8] = [
        1, 1, 0, 1, 0, 1, 0, 0, 1, 0, 0, 0,
        0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0,
    ]
    var expected_coded: List[UInt8] = [
        1, 1, 0, 1, 1, 0, 0, 0, 1, 0, 0, 1,
        1, 1, 0, 0, 0, 1, 1, 0, 0, 1, 0, 0,
        1, 1, 0, 1, 1, 1, 0, 0, 0, 0, 1, 1,
        1, 0, 0, 0, 1, 1, 1, 1, 0, 1, 1, 1,
    ]
    var expected_interleaved: List[UInt8] = [
        1, 0, 0, 1, 1, 0, 0, 1, 1, 1, 0, 1,
        1, 0, 1, 0, 1, 0, 0, 0, 0, 0, 0, 0,
        1, 1, 1, 0, 1, 1, 0, 0, 1, 1, 1, 1,
        1, 1, 0, 1, 1, 1, 0, 0, 1, 0, 0, 1,
    ]
    var expected_rate: List[UInt8] = [1, 1, 0, 1]
    assert_equal(signal.rate_bits, expected_rate)
    assert_equal(signal.length_octets, 9)
    assert_equal(signal.bits, expected_bits)
    assert_equal(signal.coded_bits, expected_coded)
    assert_equal(signal.interleaved_bits, expected_interleaved)
    assert_equal(len(signal.symbols), 48)
    assert_equal(len(signal.waveform), 80)
    var tx_stages: List[String] = [
        "rate-bits",
        "bits",
        "coded-bits",
        "interleaved-bits",
        "symbols",
        "waveform",
    ]
    var tx_dtypes: List[String] = [
        "uint8", "uint8", "uint8", "uint8", "complex64", "complex64"
    ]
    var tx_shapes: List[String] = ["4", "24", "48", "48", "48", "80"]
    var tx_q_formats: List[String] = [
        "binary-u1",
        "binary-u1",
        "binary-u1",
        "binary-u1",
        "floating",
        "floating",
    ]
    var tx_layouts: List[String] = [
        "bit-per-byte",
        "bit-per-byte",
        "bit-per-byte",
        "bit-per-byte",
        "iq-interleaved",
        "iq-interleaved",
    ]
    _assert_checkpoint_metadata(
        signal.checkpoint_metadata,
        "wifi-legacy-signal-tx-20mhz",
        tx_stages,
        tx_dtypes,
        tx_shapes,
        tx_q_formats,
        tx_layouts,
    )
    for i in range(48):
        assert_equal(
            signal.symbols[i],
            Complex64(-1.0 if expected_interleaved[i] == 1 else 1.0),
        )

    # Static legacy carrier ordering (-26..-1,+1..+26, pilots omitted) and
    # pilot row pin the frequency-domain OFDM resource map as well.
    var data_carriers: List[Int] = [
        -26, -25, -24, -23, -22, -20, -19, -18,
        -17, -16, -15, -14, -13, -12, -11, -10,
        -9, -8, -6, -5, -4, -3, -2, -1,
        1, 2, 3, 4, 5, 6, 8, 9,
        10, 11, 12, 13, 14, 15, 16, 17,
        18, 19, 20, 22, 23, 24, 25, 26,
    ]
    var spectrum = ofdm_demodulate(Span(signal.waveform), 64, 16)
    for i in range(48):
        var fft_bin = data_carriers[i] if data_carriers[i] >= 0 else (
            64 + data_carriers[i]
        )
        assert_true(
            abs(spectrum[fft_bin].re - signal.symbols[i].re) < 1.0e-12
        )
        assert_true(abs(spectrum[fft_bin].im) < 1.0e-12)
    assert_true(abs(spectrum[64 - 21].re - 1.0) < 1.0e-12)
    assert_true(abs(spectrum[64 - 7].re - 1.0) < 1.0e-12)
    assert_true(abs(spectrum[7].re - 1.0) < 1.0e-12)
    assert_true(abs(spectrum[21].re + 1.0) < 1.0e-12)


def test_wifi_stf_static_tones_and_exact_repetition() raises:
    """Published legacy STF tone values provide a static acquisition oracle."""
    var spectrum = wifi_stf_spectrum_20mhz()
    var scale = sqrt(13.0 / 6.0)
    assert_equal(len(spectrum), 64)
    assert_true(abs(spectrum[64 - 24].re - scale) < 1.0e-15)
    assert_true(abs(spectrum[64 - 24].im - scale) < 1.0e-15)
    assert_true(abs(spectrum[4].re + scale) < 1.0e-15)
    assert_true(abs(spectrum[4].im + scale) < 1.0e-15)
    assert_true(abs(spectrum[12].re - scale) < 1.0e-15)
    assert_true(abs(spectrum[24].re - scale) < 1.0e-15)
    assert_equal(spectrum[1], Complex64(0.0, 0.0))
    assert_equal(spectrum[63], Complex64(0.0, 0.0))

    var short = wifi_stf_short_symbol_20mhz()
    var stf = wifi_stf_waveform_20mhz()
    assert_equal(len(short), 16)
    assert_equal(len(stf), 160)
    var energy = 0.0
    for i in range(16):
        energy += short[i].magnitude_squared()
        for repetition in range(10):
            assert_equal(stf[16 * repetition + i], short[i])
    assert_true(energy > 0.0)


def test_ht_mcs6_same_chain_acquisition_soft_fec_and_fcs() raises:
    """Bits traverse TX, seeded RF observation, acquisition, LLRs, and FEC."""
    var payload = _ascii_123456789_lsb_first()
    var tx = wifi_acquisition_tx_20mhz(
        Span(payload), WIFI_PHY_HT, 6, symbol_index=3
    )
    # Independent ISO/IEEE CRC-32 check value and fixed one-symbol geometry.
    assert_equal(tx.fcs, UInt64(0xCBF43926))
    assert_equal(tx.payload_bit_count, 72)
    assert_equal(tx.ltf_offset, 160)
    assert_equal(tx.signal_offset, 240)
    assert_equal(tx.data_offset, 320)
    assert_equal(len(tx.packet_waveform), 400)
    var expected_rate: List[UInt8] = [1, 1, 0, 1]
    assert_equal(tx.signal_rate_bits, expected_rate)
    # L-SIG legacy LENGTH covers the modeled PSDU: 9 payload + 4 FCS octets.
    assert_equal(tx.signal_length_octets, 13)
    assert_equal(len(tx.signal_bits), 24)
    assert_equal(len(tx.signal_coded_bits), 48)
    assert_equal(len(tx.signal_interleaved_bits), 48)
    assert_equal(len(tx.signal_symbols), 48)
    assert_equal(len(tx.signal_waveform), 80)
    assert_equal(len(tx.data_field_bits), 234)
    assert_equal(len(tx.interleaved_bits), 312)
    assert_equal(len(tx.qam_symbols), 52)
    assert_equal(len(tx.stf_short_symbol), 16)
    assert_equal(len(tx.stf_waveform), 160)
    assert_equal(len(tx.ltf_waveform), 80)
    assert_equal(len(tx.data_waveform), 80)
    var tx_stages: List[String] = [
        "signal-rate-bits",
        "signal-bits",
        "signal-coded-bits",
        "signal-interleaved-bits",
        "signal-symbols",
        "data-field-bits",
        "interleaved-bits",
        "qam-symbols",
        "stf-short-symbol",
        "stf-waveform",
        "ltf-waveform",
        "signal-waveform",
        "data-waveform",
        "packet-waveform",
    ]
    var tx_dtypes: List[String] = [
        "uint8",
        "uint8",
        "uint8",
        "uint8",
        "complex64",
        "uint8",
        "uint8",
        "complex64",
        "complex64",
        "complex64",
        "complex64",
        "complex64",
        "complex64",
        "complex64",
    ]
    var tx_shapes: List[String] = [
        "4",
        "24",
        "48",
        "48",
        "48",
        "234",
        "312",
        "52",
        "16",
        "160",
        "80",
        "80",
        "80",
        "400",
    ]
    var tx_q_formats: List[String] = [
        "binary-u1",
        "binary-u1",
        "binary-u1",
        "binary-u1",
        "floating",
        "binary-u1",
        "binary-u1",
        "floating",
        "floating",
        "floating",
        "floating",
        "floating",
        "floating",
        "floating",
    ]
    var tx_layouts: List[String] = [
        "bit-per-byte",
        "bit-per-byte",
        "bit-per-byte",
        "bit-per-byte",
        "iq-interleaved",
        "bit-per-byte",
        "bit-per-byte",
        "iq-interleaved",
        "iq-interleaved",
        "iq-interleaved",
        "iq-interleaved",
        "iq-interleaved",
        "iq-interleaved",
        "iq-interleaved",
    ]
    _assert_checkpoint_metadata(
        tx.checkpoint_metadata,
        "wifi-acquisition-tx-20mhz",
        tx_stages,
        tx_dtypes,
        tx_shapes,
        tx_q_formats,
        tx_layouts,
    )

    var channel_config = WifiAcquisitionChannelConfig(
        timing_offset=11,
        normalized_cfo=0.00225,
        noise_variance=1.0e-9,
        rician_k_factor=24.0,
        seed=UInt64(0x5A17C0DE),
    )
    var channel = wifi_acquisition_apply_channel_20mhz(
        Span(tx.packet_waveform), channel_config
    )
    var repeat = wifi_acquisition_apply_channel_20mhz(
        Span(tx.packet_waveform), channel_config
    )
    # Seed is observable and deterministic, not hidden test RNG state.
    assert_equal(len(channel.observation), 411)
    assert_equal(len(channel.observation), len(repeat.observation))
    for i in range(len(channel.observation)):
        assert_equal(channel.observation[i], repeat.observation[i])

    var rx = wifi_acquisition_rx_20mhz(
        Span(channel.observation),
        WIFI_PHY_HT,
        6,
        len(payload),
        symbol_index=3,
        detection_threshold=0.82,
        llr_noise_variance=1.0e-8,
        testcase_id="wifi-ht-mcs6-acquisition-integration",
    )
    # Acquisition checkpoints are checked independently of the final FCS.
    # A threshold crossing may lead the first nonzero sample by the STF
    # correlation-window edge; the LTF correlation below supplies fine timing.
    assert_true(abs(rx.packet_start - 11) <= 2)
    assert_true(rx.stf_metric >= 0.82)
    assert_true(abs(rx.coarse_cfo - 0.00225) < 2.0e-5)
    assert_true(abs(rx.fine_cfo) < 2.0e-5)
    assert_true(abs(rx.coarse_cfo + rx.fine_cfo - 0.00225) < 3.0e-6)
    assert_equal(rx.ltf_start, 171)
    assert_equal(rx.signal_start, 251)
    assert_equal(rx.data_start, 331)
    assert_equal(len(rx.ltf_samples), 80)
    assert_equal(len(rx.signal_samples), 80)
    assert_equal(len(rx.data_samples), 80)
    assert_equal(len(rx.channel_estimate), 64)
    assert_equal(len(rx.signal_equalized_spectrum), 64)
    assert_equal(len(rx.signal_corrected_symbols), 48)
    assert_equal(len(rx.signal_llrs), 48)
    assert_equal(len(rx.signal_deinterleaved_llrs), 48)
    assert_equal(len(rx.signal_decoded_bits), 24)
    assert_equal(rx.signal_decoded_bits, tx.signal_bits)
    assert_equal(rx.signal_rate_bits, tx.signal_rate_bits)
    assert_equal(rx.signal_length_octets, 13)
    var expected_signal_fields: List[Int] = [13, 0, 13, 1, 1, 1, 1]
    assert_equal(rx.signal_decoded_fields, expected_signal_fields)
    assert_true(rx.signal_reserved_ok)
    assert_true(rx.signal_parity_ok)
    assert_true(rx.signal_tail_ok)
    assert_true(rx.signal_rate_ok)
    assert_true(rx.signal_length_ok)
    assert_true(rx.signal_ok)
    assert_equal(len(rx.equalized_spectrum), 64)
    assert_equal(len(rx.corrected_data_symbols), 52)
    assert_equal(len(rx.qam_llrs), 312)
    assert_equal(len(rx.deinterleaved_llrs), 312)
    assert_equal(len(rx.mother_llrs), 468)
    assert_equal(len(rx.decoded_bits), 234)
    assert_equal(len(rx.checkpoint_metadata), 19)
    for index in range(len(rx.checkpoint_metadata)):
        assert_equal(
            rx.checkpoint_metadata[index].testcase_id,
            "wifi-ht-mcs6-acquisition-integration",
        )
        assert_true(rx.checkpoint_metadata[index].stage.byte_length() > 0)
        assert_true(rx.checkpoint_metadata[index].dtype.byte_length() > 0)
        assert_true(rx.checkpoint_metadata[index].shape.byte_length() > 0)
        assert_equal(rx.checkpoint_metadata[index].stride, "1")
        assert_true(rx.checkpoint_metadata[index].q_format.byte_length() > 0)
        assert_equal(rx.checkpoint_metadata[index].scale, 1.0)
        assert_equal(rx.checkpoint_metadata[index].version, 1)
        assert_true(rx.checkpoint_metadata[index].layout.byte_length() > 0)
    assert_equal(
        rx.checkpoint_metadata[0].stage, "cfo-corrected-samples"
    )
    assert_equal(rx.checkpoint_metadata[0].dtype, "complex64")
    assert_equal(rx.checkpoint_metadata[0].shape, "411")
    assert_equal(rx.checkpoint_metadata[0].q_format, "floating")
    assert_equal(rx.checkpoint_metadata[0].layout, "iq-interleaved")
    assert_equal(rx.checkpoint_metadata[1].stage, "ltf-samples")
    assert_equal(
        rx.checkpoint_metadata[2].stage, "legacy-signal-samples"
    )
    assert_equal(rx.checkpoint_metadata[2].shape, "80")
    assert_equal(rx.checkpoint_metadata[3].stage, "data-samples")
    assert_equal(rx.checkpoint_metadata[4].stage, "channel-estimate")
    assert_equal(
        rx.checkpoint_metadata[5].stage,
        "legacy-signal-equalized-spectrum",
    )
    assert_equal(
        rx.checkpoint_metadata[6].stage,
        "legacy-signal-pilot-corrected-symbols",
    )
    assert_equal(rx.checkpoint_metadata[7].stage, "legacy-signal-llrs")
    assert_equal(rx.checkpoint_metadata[7].dtype, "float64")
    assert_equal(rx.checkpoint_metadata[7].shape, "48")
    assert_equal(
        rx.checkpoint_metadata[8].stage,
        "legacy-signal-deinterleaved-llrs",
    )
    assert_equal(
        rx.checkpoint_metadata[9].stage, "legacy-signal-decoded-bits"
    )
    assert_equal(rx.checkpoint_metadata[9].shape, "24")
    assert_equal(
        rx.checkpoint_metadata[10].stage, "legacy-signal-rate-bits"
    )
    assert_equal(rx.checkpoint_metadata[10].shape, "4")
    assert_equal(
        rx.checkpoint_metadata[11].stage,
        "legacy-signal-decoded-fields",
    )
    assert_equal(rx.checkpoint_metadata[11].dtype, "int64")
    assert_equal(rx.checkpoint_metadata[11].shape, "7")
    assert_equal(rx.checkpoint_metadata[12].stage, "data-equalized-spectrum")
    assert_equal(
        rx.checkpoint_metadata[13].stage,
        "data-pilot-corrected-symbols",
    )
    assert_equal(rx.checkpoint_metadata[14].stage, "qam-llrs")
    assert_equal(rx.checkpoint_metadata[14].dtype, "float64")
    assert_equal(rx.checkpoint_metadata[14].shape, "312")
    assert_equal(rx.checkpoint_metadata[15].stage, "deinterleaved-llrs")
    assert_equal(
        rx.checkpoint_metadata[16].stage, "depunctured-mother-llrs"
    )
    assert_equal(
        rx.checkpoint_metadata[17].stage, "decoded-data-field-bits"
    )
    assert_equal(rx.checkpoint_metadata[18].stage, "payload-bits")
    assert_equal(rx.checkpoint_metadata[18].dtype, "uint8")
    assert_equal(rx.checkpoint_metadata[18].shape, "72")
    assert_equal(rx.checkpoint_metadata[18].q_format, "binary-u1")
    assert_equal(rx.checkpoint_metadata[18].layout, "bit-per-byte")

    # The soft-demapper checkpoint must agree with the independently retained
    # TX interleaver bits, and equalized constellation points must be close.
    for i in range(len(tx.signal_interleaved_bits)):
        assert_equal(
            rx.signal_llrs[i] >= 0.0,
            tx.signal_interleaved_bits[i] == 0,
        )
    for i in range(len(tx.interleaved_bits)):
        assert_equal(rx.qam_llrs[i] >= 0.0, tx.interleaved_bits[i] == 0)
    var squared_error = 0.0
    for i in range(len(tx.qam_symbols)):
        var dr = rx.corrected_data_symbols[i].re - tx.qam_symbols[i].re
        var di = rx.corrected_data_symbols[i].im - tx.qam_symbols[i].im
        squared_error += dr * dr + di * di
    assert_true(squared_error / Float64(len(tx.qam_symbols)) < 1.0e-5)

    assert_true(rx.service_ok)
    assert_true(rx.fcs_ok)
    assert_equal(rx.received_fcs, UInt64(0xCBF43926))
    assert_equal(rx.computed_fcs, UInt64(0xCBF43926))
    assert_equal(rx.payload_bits, payload)


def test_vht_mcs8_acquisition_uses_the_same_soft_receiver() raises:
    """Exercise the public VHT/256-QAM branch through acquisition and FCS."""
    var payload = _ascii_123456789_lsb_first()
    var tx = wifi_acquisition_tx_20mhz(
        Span(payload), WIFI_PHY_VHT, 8, symbol_index=5
    )
    assert_equal(len(tx.interleaved_bits), 416)
    assert_equal(len(tx.qam_symbols), 52)

    var channel = wifi_acquisition_apply_channel_20mhz(
        Span(tx.packet_waveform),
        WifiAcquisitionChannelConfig(
            timing_offset=7,
            normalized_cfo=-0.0015,
            noise_variance=1.0e-10,
            rician_k_factor=30.0,
            seed=UInt64(0xAC20260821),
        ),
    )
    var rx = wifi_acquisition_rx_20mhz(
        Span(channel.observation),
        WIFI_PHY_VHT,
        8,
        len(payload),
        symbol_index=5,
        detection_threshold=0.82,
        llr_noise_variance=1.0e-8,
    )
    assert_true(abs(rx.packet_start - 7) <= 2)
    assert_true(abs(rx.coarse_cfo + 0.0015) < 2.0e-5)
    assert_true(abs(rx.fine_cfo) < 2.0e-5)
    assert_true(abs(rx.coarse_cfo + rx.fine_cfo + 0.0015) < 3.0e-6)
    assert_equal(rx.ltf_start, 167)
    assert_equal(rx.signal_start, 247)
    assert_equal(rx.data_start, 327)
    assert_true(rx.signal_ok)
    assert_equal(rx.signal_decoded_bits, tx.signal_bits)
    assert_equal(rx.signal_length_octets, 13)
    assert_equal(len(rx.signal_llrs), 48)
    for i in range(len(tx.signal_interleaved_bits)):
        assert_equal(
            rx.signal_llrs[i] >= 0.0,
            tx.signal_interleaved_bits[i] == 0,
        )
    assert_equal(len(rx.qam_llrs), 416)
    for i in range(len(tx.interleaved_bits)):
        assert_equal(rx.qam_llrs[i] >= 0.0, tx.interleaved_bits[i] == 0)
    assert_true(rx.service_ok)
    assert_true(rx.fcs_ok)
    assert_equal(rx.payload_bits, payload)


def test_legacy_l_sig_validation_gates_data_decode() raises:
    """Parity, tail, RATE, reserved, and LENGTH each fail before DATA."""
    var payload = _ascii_123456789_lsb_first()
    var tx = wifi_acquisition_tx_20mhz(Span(payload), WIFI_PHY_HT, 6)

    var parity_bits = tx.signal_bits.copy()
    parity_bits[17] ^= UInt8(1)
    var parity_packet = _packet_with_legacy_signal(
        Span(tx.packet_waveform), tx.signal_offset, Span(parity_bits)
    )
    with assert_raises():
        _ = wifi_acquisition_rx_20mhz(
            Span(parity_packet), WIFI_PHY_HT, 6, len(payload)
        )

    var tail_bits = tx.signal_bits.copy()
    tail_bits[18] = UInt8(1)
    var tail_packet = _packet_with_legacy_signal(
        Span(tx.packet_waveform), tx.signal_offset, Span(tail_bits)
    )
    with assert_raises():
        _ = wifi_acquisition_rx_20mhz(
            Span(tail_packet), WIFI_PHY_HT, 6, len(payload)
        )

    var rate_bits = tx.signal_bits.copy()
    rate_bits[2] = UInt8(1)
    _refresh_signal_parity(rate_bits)
    var rate_packet = _packet_with_legacy_signal(
        Span(tx.packet_waveform), tx.signal_offset, Span(rate_bits)
    )
    with assert_raises():
        _ = wifi_acquisition_rx_20mhz(
            Span(rate_packet), WIFI_PHY_HT, 6, len(payload)
        )

    var reserved_bits = tx.signal_bits.copy()
    reserved_bits[4] = UInt8(1)
    _refresh_signal_parity(reserved_bits)
    var reserved_packet = _packet_with_legacy_signal(
        Span(tx.packet_waveform), tx.signal_offset, Span(reserved_bits)
    )
    with assert_raises():
        _ = wifi_acquisition_rx_20mhz(
            Span(reserved_packet), WIFI_PHY_HT, 6, len(payload)
        )

    var length_bits = tx.signal_bits.copy()
    length_bits[5] ^= UInt8(1)
    _refresh_signal_parity(length_bits)
    var length_packet = _packet_with_legacy_signal(
        Span(tx.packet_waveform), tx.signal_offset, Span(length_bits)
    )
    with assert_raises():
        _ = wifi_acquisition_rx_20mhz(
            Span(length_packet), WIFI_PHY_HT, 6, len(payload)
        )


def test_legacy_l_sig_length_boundaries_and_zero_length_chain() raises:
    var minimum = wifi_legacy_signal_tx_20mhz(0)
    var maximum = wifi_legacy_signal_tx_20mhz(4095)
    assert_equal(minimum.length_octets, 0)
    assert_equal(maximum.length_octets, 4095)
    for i in range(12):
        assert_equal(minimum.bits[5 + i], UInt8(0))
        assert_equal(maximum.bits[5 + i], UInt8(1))
    with assert_raises():
        _ = wifi_legacy_signal_tx_20mhz(-1)
    with assert_raises():
        _ = wifi_legacy_signal_tx_20mhz(4096)

    var empty_payload = List[UInt8]()
    var tx = wifi_acquisition_tx_20mhz(
        Span(empty_payload), WIFI_PHY_HT, 6
    )
    var rx = wifi_acquisition_rx_20mhz(
        Span(tx.packet_waveform), WIFI_PHY_HT, 6, 0
    )
    assert_true(rx.signal_ok)
    assert_equal(rx.signal_length_octets, 4)
    assert_equal(len(rx.payload_bits), 0)
    assert_true(rx.service_ok)
    assert_true(rx.fcs_ok)


def test_wifi_acquisition_edge_validation() raises:
    var payload = _ascii_123456789_lsb_first()
    with assert_raises():
        _ = wifi_acquisition_tx_20mhz(Span(payload), WIFI_PHY_HE, 6)
    var non_octet: List[UInt8] = [0, 1, 0]
    with assert_raises():
        _ = wifi_acquisition_tx_20mhz(Span(non_octet), WIFI_PHY_HT, 6)

    var sample: List[Complex64] = [Complex64(1.0, 0.0)]
    with assert_raises():
        _ = wifi_acquisition_apply_channel_20mhz(
            Span(sample), WifiAcquisitionChannelConfig(timing_offset=-1)
        )
    with assert_raises():
        _ = wifi_acquisition_apply_channel_20mhz(
            Span(sample), WifiAcquisitionChannelConfig(normalized_cfo=0.03125)
        )
    with assert_raises():
        _ = wifi_acquisition_apply_channel_20mhz(
            Span(sample), WifiAcquisitionChannelConfig(noise_variance=-1.0)
        )
    with assert_raises():
        _ = wifi_acquisition_apply_channel_20mhz(
            Span(sample),
            WifiAcquisitionChannelConfig(
                normalized_cfo=nan[DType.float64]()
            ),
        )
    with assert_raises():
        _ = wifi_acquisition_apply_channel_20mhz(
            Span(sample),
            WifiAcquisitionChannelConfig(
                noise_variance=inf[DType.float64]()
            ),
        )
    with assert_raises():
        _ = wifi_acquisition_apply_channel_20mhz(
            Span(sample),
            WifiAcquisitionChannelConfig(
                rician_k_factor=nan[DType.float64]()
            ),
        )
    var empty = List[Complex64]()
    with assert_raises():
        _ = wifi_acquisition_apply_channel_20mhz(
            Span(empty), WifiAcquisitionChannelConfig()
        )
    with assert_raises():
        _ = wifi_ltf_fine_timing_20mhz(
            Span(sample), WIFI_PHY_HT, 0, search_radius=-1
        )
    with assert_raises():
        _ = wifi_ltf_fine_cfo_20mhz(Span(sample), 0)
    with assert_raises():
        _ = wifi_ltf_fine_timing_20mhz(
            Span(sample), WIFI_PHY_HT, Int.MAX, search_radius=Int.MAX
        )
    with assert_raises():
        _ = wifi_acquisition_rx_20mhz(
            Span(empty), WIFI_PHY_HT, 6, len(payload)
        )
    with assert_raises():
        _ = wifi_acquisition_rx_20mhz(
            Span(empty),
            WIFI_PHY_HT,
            6,
            len(payload),
            detection_threshold=nan[DType.float64](),
        )
    with assert_raises():
        _ = wifi_acquisition_rx_20mhz(
            Span(empty),
            WIFI_PHY_HT,
            6,
            len(payload),
            llr_noise_variance=inf[DType.float64](),
        )


def test_ltf_timing_and_cfo_are_scale_safe_at_float64_extremes() raises:
    var payload = _ascii_123456789_lsb_first()
    var tx = wifi_acquisition_tx_20mhz(
        Span(payload), WIFI_PHY_HT, 6, symbol_index=0
    )
    for amplitude in [1.0e-300, 1.0e300]:
        var observation = List[Complex64](capacity=7 + len(tx.ltf_waveform))
        for _ in range(7):
            observation.append(Complex64(0.0, 0.0))
        for value in tx.ltf_waveform:
            observation.append(Complex64(
                amplitude * value.re, amplitude * value.im
            ))
        assert_equal(
            wifi_ltf_fine_timing_20mhz(
                Span(observation), WIFI_PHY_HT, 7, search_radius=3
            ),
            7,
        )
        assert_true(
            abs(wifi_ltf_fine_cfo_20mhz(Span(observation), 7))
            < 1.0e-15
        )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
