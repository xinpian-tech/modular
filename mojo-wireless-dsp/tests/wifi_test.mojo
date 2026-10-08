from std.testing import assert_equal, assert_true, TestSuite
from wireless_dsp.core import Complex64, Span
from wireless_dsp.modem import qam_map, qam_demap_hard
from wireless_dsp.fec import convolutional_encode, viterbi_decode_hard
from wireless_dsp.wireless.wifi import (
    wifi_scramble,
    wifi_interleave,
    wifi_deinterleave,
    wifi_data_subcarriers,
    wifi_map_legacy_symbol,
    wifi_extract_legacy_symbol,
    wifi_ls_channel_estimate,
    wifi_equalize,
    wifi_stf_detect,
    wifi_stf_coarse_cfo,
    wifi_pilot_polarity,
    wifi_legacy_signal_bits,
    wifi_parse_legacy_signal,
    wifi_fcs,
)
from wireless_dsp.channel import apply_cfo


def test_wifi_interleaver_roundtrip_all_legacy_modulations() raises:
    for bits_per_subcarrier in [1, 2, 4, 6]:
        var bits = List[UInt8](capacity=48 * bits_per_subcarrier)
        for i in range(48 * bits_per_subcarrier):
            bits.append(UInt8((i * 7 + i // 5) & 1))
        var interleaved = wifi_interleave(Span(bits), bits_per_subcarrier)
        assert_equal(wifi_deinterleave(Span(interleaved), bits_per_subcarrier), bits)


def test_wifi_ofdm_resource_mapping_roundtrip() raises:
    assert_equal(len(wifi_data_subcarriers()), 48)
    var bits = List[UInt8](capacity=48 * 6)
    for i in range(48 * 6):
        bits.append(UInt8((i * 11 + 3) & 1))
    var mapped = qam_map(Span(bits), 6)
    var time = wifi_map_legacy_symbol(Span(mapped))
    assert_equal(len(time), 80)
    var extracted = wifi_extract_legacy_symbol(Span(time))
    for i in range(48):
        assert_true(abs(extracted[i].re - mapped[i].re) < 1.0e-10)
        assert_true(abs(extracted[i].im - mapped[i].im) < 1.0e-10)


def test_wifi_ls_channel_and_equalizer() raises:
    var known: List[Complex64] = [Complex64(1.0), Complex64(-1.0), Complex64(0.0, 1.0)]
    var channel: List[Complex64] = [Complex64(0.8, 0.2), Complex64(0.8, 0.2), Complex64(0.8, 0.2)]
    var received = List[Complex64](capacity=3)
    for i in range(3):
        received.append(known[i] * channel[i])
    var estimate = wifi_ls_channel_estimate(Span(received), Span(known))
    var equalized = wifi_equalize(Span(received), Span(estimate))
    for i in range(3):
        assert_true(abs(estimate[i].re - channel[i].re) < 1.0e-12)
        assert_true(abs(estimate[i].im - channel[i].im) < 1.0e-12)
        assert_true(abs(equalized[i].re - known[i].re) < 1.0e-12)
        assert_true(abs(equalized[i].im - known[i].im) < 1.0e-12)


def test_wifi_legacy_bpsk_phy_roundtrip() raises:
    var payload: List[UInt8] = [1, 0, 1, 1, 0, 0, 1, 0, 0, 1, 1, 1, 0, 1, 0, 1, 1, 0]
    var scrambled = wifi_scramble(Span(payload), UInt8(0x5D))
    var generators: List[Int] = [0o133, 0o171]
    var coded = convolutional_encode(Span(scrambled), Span(generators), 7)
    assert_equal(len(coded), 48)
    var interleaved = wifi_interleave(Span(coded), 1)
    var symbols = qam_map(Span(interleaved), 1)
    var waveform = wifi_map_legacy_symbol(Span(symbols))
    var received_symbols = wifi_extract_legacy_symbol(Span(waveform))
    var hard = qam_demap_hard(Span(received_symbols), 1)
    var deinterleaved = wifi_deinterleave(Span(hard), 1)
    var decoded = viterbi_decode_hard(Span(deinterleaved), Span(generators), 7)
    var recovered = wifi_scramble(Span(decoded), UInt8(0x5D))
    assert_equal(recovered, payload)


def test_wifi_stf_detection_and_coarse_cfo() raises:
    var samples = List[Complex64](capacity=3 + 16 * 4)
    for _ in range(3):
        samples.append(Complex64(0.0, 0.0))
    for _ in range(4):
        for i in range(16):
            samples.append(Complex64(
                Float64((i * 5 + 1) % 7) - 3.0,
                Float64((i * 3 + 2) % 5) - 2.0,
            ))
    var impaired = apply_cfo(Span(samples), 0.003)
    var offset = wifi_stf_detect(Span(impaired), 0.99)
    assert_equal(offset, 3)
    assert_true(abs(wifi_stf_coarse_cfo(Span(impaired), offset) - 0.003) < 1.0e-12)


def test_wifi_signal_pilots_and_fcs_vectors() raises:
    var rate: List[UInt8] = [1, 1, 0, 1]  # legacy 6 Mb/s RATE field ordering
    var signal = wifi_legacy_signal_bits(Span(rate), 1500)
    var parsed = wifi_parse_legacy_signal(Span(signal))
    assert_equal(parsed.rate_bits, rate)
    assert_equal(parsed.length_octets, 1500)
    assert_true(abs(wifi_pilot_polarity(0)) == 1.0)

    var octets: List[Int] = [49, 50, 51, 52, 53, 54, 55, 56, 57]
    var bits = List[UInt8](capacity=72)
    for octet in octets:
        for shift in range(8):
            bits.append(UInt8((octet >> shift) & 1))
    assert_equal(wifi_fcs(Span(bits)), UInt64(0xCBF43926))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
