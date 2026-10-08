"""Executable Wi-Fi PHY-chain tests with independent static oracles.

The minimum-codeword positions are published by the KAIST CoCoA database at
https://cocoa.kaist.ac.kr/dmincodewords/codewords/ieee-802-11n/ .  LTF and
tone-mapper point checks transcribe IEEE 802.11ax-2021 Eq. (27-43), Table
27-36, and Eq. (27-95); CRC-32 uses the public ``123456789`` check value.
"""

from std.collections import Span
from std.testing import assert_equal, assert_true, TestSuite
from std.math import cos, sin, sqrt
from wireless_dsp.core import Complex64
from wireless_dsp.dsp import ofdm_modulate
from wireless_dsp.modem import qam_map
from wireless_dsp.testing import CheckpointMetadata
from wireless_dsp.wireless.wifi.legacy import wifi_fcs
from wireless_dsp.wireless.wifi.profiles import (
    WIFI_PHY_HT,
    WIFI_PHY_VHT,
    WIFI_PHY_HE,
    WIFI_PHY_EHT,
)
from wireless_dsp.wireless.wifi.preambles import (
    wifi_ltf_values_20mhz,
    wifi_ltf_spectrum_20mhz,
    wifi_ltf_waveform_20mhz,
    wifi_ltf_channel_estimate_20mhz,
    wifi_data_pilot_subcarriers_20mhz,
    wifi_data_pilots_20mhz,
)
from wireless_dsp.wireless.wifi.phy_chain import (
    wifi_ht_vht_data_subcarriers_20mhz,
    wifi_map_ht_vht_symbol_20mhz,
    wifi_extract_ht_vht_data_20mhz,
    wifi_extract_ht_vht_pilots_20mhz,
    wifi_ldpc_tone_mapping_distance,
    wifi_ldpc_tone_permutation,
    wifi_ldpc_tone_map_bits,
    wifi_ldpc_tone_demap_llrs,
    wifi_bcc_tx_20mhz,
    wifi_bcc_rx_20mhz,
    wifi_ldpc_tx_20mhz,
    wifi_ldpc_rx_20mhz,
)

from wireless_dsp.wireless.wifi.ldpc import (
    wifi_ldpc_profile,
    wifi_ldpc_base_shifts,
    wifi_ldpc_sparse_graph,
    wifi_ldpc_syndrome_ok,
    wifi_ldpc_encode,
    wifi_ldpc_decode,
    wifi_ldpc_rate_match_block,
    wifi_ldpc_rate_recover_block,
)


def test_wifi_ldpc_profiles_and_independent_codewords() raises:
    """KAIST CoCoA 802.11n N=648 R=1/2 minimum-codeword oracle."""
    for n in [648, 1296, 1944]:
        for numerator, denominator, rows in [
            (1, 2, 12),
            (2, 3, 8),
            (3, 4, 6),
            (5, 6, 4),
        ]:
            var profile = wifi_ldpc_profile(n, numerator, denominator)
            var base_shifts = wifi_ldpc_base_shifts(profile)
            assert_equal(len(base_shifts), rows * 24)
            assert_equal(profile.lifting_size, n // 24)
            assert_equal(profile.block_rows, rows)
            assert_equal(profile.parity_length, rows * profile.lifting_size)
            var graph = wifi_ldpc_sparse_graph(profile)
            assert_equal(len(graph.row_offsets), profile.parity_length + 1)
            assert_true(len(graph.columns) > profile.parity_length)
            var patterned = List[UInt8](capacity=profile.information_length)
            for i in range(profile.information_length):
                patterned.append(UInt8((i * 11 + i // 7 + n // 648) & 1))
            var encoded = wifi_ldpc_encode(Span(patterned), profile)
            assert_true(wifi_ldpc_syndrome_ok(Span(encoded), profile))

    var profile = wifi_ldpc_profile(648, 1, 2)
    var codeword = List[UInt8](length=648, fill=UInt8(0))
    # Public file uses one-based positions.
    var one_positions: List[Int] = [
        98,
        99,
        250,
        315,
        369,
        396,
        423,
        439,
        449,
        476,
        502,
        568,
        569,
        596,
        623,
    ]
    for position in one_positions:
        codeword[position - 1] = UInt8(1)
    assert_true(wifi_ldpc_syndrome_ok(Span(codeword), profile))
    var information = List[UInt8](capacity=profile.information_length)
    for i in range(profile.information_length):
        information.append(codeword[i])
    assert_equal(wifi_ldpc_encode(Span(information), profile), codeword)

    var llrs = List[Float64](capacity=648)
    for bit in codeword:
        llrs.append(20.0 if bit == 0 else -20.0)
    var decoded = wifi_ldpc_decode(Span(llrs), profile, max_iterations=5)
    assert_true(decoded.converged)
    assert_equal(decoded.codeword_bits, codeword)

    var shortened = 4
    var punctured = 2
    var repeated = 3
    var rate_information = List[UInt8](capacity=profile.information_length - shortened)
    for index in range(profile.information_length - shortened):
        rate_information.append(UInt8((7 * index + index // 5) & 1))
    var transmitted = wifi_ldpc_rate_match_block(
        Span(rate_information),
        profile,
        shortened_bits=shortened,
        punctured_bits=punctured,
        repeated_bits=repeated,
    )
    assert_equal(
        len(transmitted), profile.block_length - shortened - punctured + repeated
    )
    var rate_llrs = List[Float64](capacity=len(transmitted))
    for bit in transmitted:
        rate_llrs.append(20.0 if bit == 0 else -20.0)
    var recovered = wifi_ldpc_rate_recover_block(
        Span(rate_llrs),
        profile,
        shortened_bits=shortened,
        punctured_bits=punctured,
        repeated_bits=repeated,
        shortened_llr=50.0,
    )
    assert_equal(len(recovered), profile.block_length)
    for index in range(profile.information_length - shortened, profile.information_length):
        assert_equal(recovered[index], 50.0)
    for index in range(profile.block_length - punctured, profile.block_length):
        assert_equal(recovered[index], 0.0)

    # Two more first-line minimum-codeword oracles from the same independent
    # KAIST CoCoA database cover the exact HE and EHT mother-code selections.
    var he_profile = wifi_ldpc_profile(1296, 3, 4)
    var he_codeword = List[UInt8](length=1296, fill=UInt8(0))
    var he_ones: List[Int] = [
        407,
        444,
        734,
        780,
        814,
        921,
        1151,
        1177,
        1264,
        1265,
    ]
    for position in he_ones:
        he_codeword[position - 1] = UInt8(1)
    assert_true(wifi_ldpc_syndrome_ok(Span(he_codeword), he_profile))
    var he_information = List[UInt8](capacity=he_profile.information_length)
    for i in range(he_profile.information_length):
        he_information.append(he_codeword[i])
    assert_equal(
        wifi_ldpc_encode(Span(he_information), he_profile), he_codeword
    )

    var eht_profile = wifi_ldpc_profile(1944, 5, 6)
    var eht_codeword = List[UInt8](length=1944, fill=UInt8(0))
    var eht_ones: List[Int] = [
        721,
        819,
        1060,
        1221,
        1425,
        1740,
        1754,
        1779,
        1835,
    ]
    for position in eht_ones:
        eht_codeword[position - 1] = UInt8(1)
    assert_true(wifi_ldpc_syndrome_ok(Span(eht_codeword), eht_profile))
    var eht_information = List[UInt8](capacity=eht_profile.information_length)
    for i in range(eht_profile.information_length):
        eht_information.append(eht_codeword[i])
    assert_equal(
        wifi_ldpc_encode(Span(eht_information), eht_profile), eht_codeword
    )


def test_normative_ltf_and_ldpc_tone_mapper_static_points() raises:
    assert_equal(wifi_data_pilot_subcarriers_20mhz(WIFI_PHY_HT), [-21, -7, 7, 21])
    assert_equal(wifi_data_pilot_subcarriers_20mhz(WIFI_PHY_HE), [-116, -90, -48, -22, 22, 48, 90, 116])
    var ht_data_indices = wifi_ht_vht_data_subcarriers_20mhz(WIFI_PHY_HT)
    assert_equal(len(ht_data_indices), 52)
    var ht_data = List[Complex64](capacity=52)
    for index in range(52):
        ht_data.append(Complex64(Float64(index + 1), Float64(-index)))
    var ht_pilots = wifi_data_pilots_20mhz(WIFI_PHY_HT)
    var ht_spectrum = wifi_map_ht_vht_symbol_20mhz(
        Span(ht_data), Span(ht_pilots), WIFI_PHY_HT
    )
    assert_equal(
        wifi_extract_ht_vht_data_20mhz(Span(ht_spectrum), WIFI_PHY_HT),
        ht_data,
    )
    assert_equal(
        wifi_extract_ht_vht_pilots_20mhz(Span(ht_spectrum), WIFI_PHY_HT),
        ht_pilots,
    )
    assert_equal(wifi_ldpc_tone_mapping_distance(26), 1)
    assert_equal(wifi_ldpc_tone_mapping_distance(242), 9)
    assert_equal(wifi_ldpc_tone_mapping_distance(3984), 20)
    var ht = wifi_ltf_values_20mhz(WIFI_PHY_HT)
    assert_equal(len(ht), 57)
    assert_equal(ht[0], 1)
    assert_equal(ht[28], 0)
    assert_equal(ht[56], -1)
    var he = wifi_ltf_values_20mhz(WIFI_PHY_HE)
    assert_equal(len(he), 245)
    assert_equal(he[0], -1)
    assert_equal(he[121], 0)
    assert_equal(he[122], 0)
    assert_equal(he[123], 0)
    assert_equal(he[244], 1)
    assert_equal(len(wifi_ltf_spectrum_20mhz(WIFI_PHY_VHT)), 64)
    assert_equal(len(wifi_ltf_spectrum_20mhz(WIFI_PHY_EHT)), 256)

    # IEEE 802.11ax Eq. (27-95), RU-242 Nsd=234 and D_TM=9.
    var permutation = wifi_ldpc_tone_permutation(234, 9)
    assert_equal(permutation[0], 0)
    assert_equal(permutation[1], 9)
    assert_equal(permutation[25], 225)
    assert_equal(permutation[26], 1)
    assert_equal(permutation[233], 233)
    var bits = List[UInt8](capacity=234 * 10)
    var llrs = List[Float64](capacity=234 * 10)
    for i in range(234 * 10):
        bits.append(UInt8((i * 7 + i // 11) & 1))
        llrs.append(1.0 if bits[i] == 0 else -1.0)
    var mapped = wifi_ldpc_tone_map_bits(Span(bits), 10, 242)
    var mapped_llrs = List[Float64](capacity=len(mapped))
    for bit in mapped:
        mapped_llrs.append(1.0 if bit == 0 else -1.0)
    assert_equal(wifi_ldpc_tone_demap_llrs(Span(mapped_llrs), 10, 242), llrs)

    # A 2x996-tone RU maps each 980-data-tone frequency subblock separately.
    var wide_bits = List[UInt8](capacity=1960 * 2)
    for i in range(1960 * 2):
        wide_bits.append(UInt8((i * 5 + i // 17) & 1))
    var wide_mapped = wifi_ldpc_tone_map_bits(Span(wide_bits), 2, 1992)
    var wide_llrs = List[Float64](capacity=len(wide_mapped))
    for bit in wide_mapped:
        wide_llrs.append(2.0 if bit == 0 else -2.0)
    var wide_recovered = wifi_ldpc_tone_demap_llrs(Span(wide_llrs), 2, 1992)
    for i in range(len(wide_bits)):
        assert_equal(wide_recovered[i] > 0.0, wide_bits[i] == 0)


def test_public_crc32_and_high_qam_normalization_vectors() raises:
    # ISO/IEEE CRC-32 check string, serialized per octet least-significant bit first.
    var octets: List[Int] = [
        0x31,
        0x32,
        0x33,
        0x34,
        0x35,
        0x36,
        0x37,
        0x38,
        0x39,
    ]
    var check_bits = List[UInt8](capacity=72)
    for octet in octets:
        for bit in range(8):
            check_bits.append(UInt8((octet >> bit) & 1))
    assert_equal(wifi_fcs(Span(check_bits)), UInt64(0xCBF43926))

    # IEEE square-QAM all-zero labels select (+max,+max).  The normalization
    # denominators are sqrt(682) for 1024-QAM and sqrt(2730) for 4096-QAM.
    for bpsc, maximum, denominator in [(10, 31, 682), (12, 63, 2730)]:
        var bits = List[UInt8](length=bpsc, fill=UInt8(0))
        var point = qam_map(Span(bits), bpsc)[0]
        var expected = Float64(maximum) / sqrt(Float64(denominator))
        assert_true(abs(point.re - expected) < 1.0e-12)
        assert_true(abs(point.im - expected) < 1.0e-12)


def test_ltf_fft_channel_estimation_checkpoint() raises:
    var channel = Complex64(0.8, -0.35)
    for family in [WIFI_PHY_HT, WIFI_PHY_HE, WIFI_PHY_EHT]:
        var transmitted = wifi_ltf_waveform_20mhz(family)
        var received = List[Complex64](capacity=len(transmitted))
        for sample in transmitted:
            received.append(sample * channel)
        var estimate = wifi_ltf_channel_estimate_20mhz(Span(received), family)
        var known = wifi_ltf_spectrum_20mhz(family)
        for i in range(len(known)):
            if known[i].magnitude_squared() > 0.0:
                assert_true(abs(estimate[i].re - channel.re) < 1.0e-10)
                assert_true(abs(estimate[i].im - channel.im) < 1.0e-10)

    var he_pilots = wifi_data_pilots_20mhz(WIFI_PHY_HE, 0)
    assert_equal(len(he_pilots), 8)
    assert_equal(he_pilots[0], Complex64(1.0))
    assert_equal(he_pilots[3], Complex64(-1.0))


def _payload_octets(octets: Int, salt: Int) -> List[UInt8]:
    var result = List[UInt8](capacity=8 * octets)
    for i in range(8 * octets):
        result.append(UInt8((i * 13 + i // 5 + salt) & 1))
    return result^


def _length_text(length: Int) -> String:
    var result = String()
    result.write(length)
    return result^


def _matrix_shape(rows: Int, columns: Int) -> String:
    var result = String()
    result.write(rows, "x", columns)
    return result^


def _matrix_stride(columns: Int) -> String:
    var result = String()
    result.write(columns, ",1")
    return result^


def _assert_checkpoint_metadata(
    metadata: List[CheckpointMetadata],
    testcase_id: StringSlice,
    stages: List[String],
    dtypes: List[String],
    shapes: List[String],
    strides: List[String],
    q_formats: List[String],
    layouts: List[String],
) raises:
    assert_equal(len(metadata), len(stages))
    assert_equal(len(metadata), len(dtypes))
    assert_equal(len(metadata), len(shapes))
    assert_equal(len(metadata), len(strides))
    assert_equal(len(metadata), len(q_formats))
    assert_equal(len(metadata), len(layouts))
    for index in range(len(metadata)):
        assert_equal(metadata[index].testcase_id, testcase_id)
        assert_equal(metadata[index].stage, stages[index])
        assert_equal(metadata[index].dtype, dtypes[index])
        assert_equal(metadata[index].shape, shapes[index])
        assert_equal(metadata[index].stride, strides[index])
        assert_equal(metadata[index].q_format, q_formats[index])
        assert_equal(metadata[index].layout, layouts[index])
        assert_equal(metadata[index].scale, 1.0)
        assert_equal(metadata[index].version, 1)


def _flat_ltf(family: Int, channel: Complex64) raises -> List[Complex64]:
    var ltf = wifi_ltf_waveform_20mhz(family)
    var result = List[Complex64](capacity=len(ltf))
    for sample in ltf:
        result.append(sample * channel)
    return result^


def _phase_impaired_symbol(
    spectrum: Span[Complex64, ...],
    channel: Complex64,
    common: Float64,
    slope: Float64,
) raises -> List[Complex64]:
    var fft_size = len(spectrum)
    var impaired = List[Complex64](capacity=fft_size)
    for bin_index in range(fft_size):
        var subcarrier = (
            bin_index if bin_index <= fft_size // 2 else bin_index - fft_size
        )
        var angle = common + slope * Float64(subcarrier)
        var value = Complex64(spectrum[bin_index].re, spectrum[bin_index].im)
        impaired.append(value * channel * Complex64(cos(angle), sin(angle)))
    return ofdm_modulate(Span(impaired), 16)


def test_ht64_and_vht256_bcc_phy_tx_rx_checkpoints() raises:
    var channel = Complex64(0.72, -0.31)
    var common = 0.23
    var slope = 0.0025
    for family, mcs_index, octets, bpsc in [
        (WIFI_PHY_HT, 6, 18, 6),
        (WIFI_PHY_VHT, 8, 28, 8),
    ]:
        var payload = _payload_octets(octets, family)
        var tx = wifi_bcc_tx_20mhz(
            Span(payload), family, mcs_index, symbol_index=3
        )
        assert_equal(len(tx.qam_symbols), 52)
        assert_equal(len(tx.interleaved_bits), 52 * bpsc)
        assert_equal(len(tx.waveform), 80)
        var tx_stages: List[String] = [
            "payload-input", "data-field-bits", "scrambled-bits",
            "mother-bits", "punctured-bits", "interleaved-bits",
            "qam-symbols", "frequency-grid", "waveform", "fcs",
        ]
        var tx_dtypes: List[String] = [
            "uint8", "uint8", "uint8", "uint8", "uint8", "uint8",
            "complex64", "complex64", "complex64", "uint64",
        ]
        var tx_shapes: List[String] = [
            _length_text(len(payload)),
            _length_text(len(tx.data_field_bits)),
            _length_text(len(tx.scrambled_bits)),
            _length_text(len(tx.mother_bits)),
            _length_text(len(tx.punctured_bits)),
            _length_text(len(tx.interleaved_bits)),
            _length_text(len(tx.qam_symbols)),
            _matrix_shape(1, len(tx.spectrum)),
            _length_text(len(tx.waveform)),
            "1",
        ]
        var tx_strides: List[String] = [
            "1", "1", "1", "1", "1", "1", "1",
            _matrix_stride(len(tx.spectrum)), "1", "1",
        ]
        var tx_q_formats: List[String] = [
            "binary-u1", "binary-u1", "binary-u1", "binary-u1",
            "binary-u1", "binary-u1", "floating", "floating", "floating",
            "unsigned-integer",
        ]
        var tx_layouts: List[String] = [
            "bit-per-byte", "bit-per-byte", "bit-per-byte", "bit-per-byte",
            "bit-per-byte", "bit-per-byte", "iq-interleaved",
            "row-major-frequency-grid-iq-interleaved", "iq-interleaved",
            "scalar",
        ]
        _assert_checkpoint_metadata(
            tx.checkpoint_metadata,
            "wifi-bcc-tx-20mhz",
            tx_stages,
            tx_dtypes,
            tx_shapes,
            tx_strides,
            tx_q_formats,
            tx_layouts,
        )
        var received = _phase_impaired_symbol(
            Span(tx.spectrum), channel, common, slope
        )
        var ltf = _flat_ltf(family, channel)
        var rx = wifi_bcc_rx_20mhz(
            Span(received),
            Span(ltf),
            family,
            mcs_index,
            len(payload),
            symbol_index=3,
        )
        assert_equal(rx.payload_bits, payload)
        assert_equal(len(rx.equalized_spectrum), 64)
        assert_equal(len(rx.corrected_data_symbols), len(tx.qam_symbols))
        for index in range(len(tx.qam_symbols)):
            assert_true(
                abs(
                    rx.corrected_data_symbols[index].re
                    - tx.qam_symbols[index].re
                ) < 1.0e-9
            )
            assert_true(
                abs(
                    rx.corrected_data_symbols[index].im
                    - tx.qam_symbols[index].im
                ) < 1.0e-9
            )
        assert_true(rx.service_ok)
        assert_true(rx.fcs_ok)
        assert_true(abs(rx.common_phase - common) < 1.0e-10)
        assert_true(abs(rx.phase_slope - slope) < 1.0e-10)
        var rx_stages: List[String] = [
            "received-waveform", "ltf-samples", "channel-estimate",
            "equalized-spectrum", "pilot-phase-estimate",
            "pilot-corrected-data-symbols", "demapped-bits",
            "deinterleaved-bits", "decoded-data-field-bits",
            "decoded-payload-bits", "received-fcs", "computed-fcs",
            "service-ok", "fcs-ok",
        ]
        var rx_dtypes: List[String] = [
            "complex64", "complex64", "complex64", "complex64", "float64",
            "complex64", "uint8", "uint8", "uint8", "uint8", "uint64",
            "uint64", "bool", "bool",
        ]
        var rx_shapes: List[String] = [
            _length_text(len(received)),
            _length_text(len(ltf)),
            _length_text(len(rx.channel_estimate)),
            _matrix_shape(1, len(rx.equalized_spectrum)),
            "2",
            _length_text(len(rx.corrected_data_symbols)),
            _length_text(len(rx.demapped_bits)),
            _length_text(len(rx.deinterleaved_bits)),
            _length_text(len(rx.decoded_bits)),
            _length_text(len(rx.payload_bits)),
            "1", "1", "1", "1",
        ]
        var rx_strides: List[String] = [
            "1", "1", "1", _matrix_stride(len(rx.equalized_spectrum)),
            "1", "1", "1", "1", "1", "1", "1", "1", "1", "1",
        ]
        var rx_q_formats: List[String] = [
            "floating", "floating", "floating", "floating", "floating",
            "floating", "binary-u1", "binary-u1", "binary-u1", "binary-u1",
            "unsigned-integer", "unsigned-integer", "boolean", "boolean",
        ]
        var rx_layouts: List[String] = [
            "iq-interleaved", "iq-interleaved", "iq-interleaved",
            "row-major-frequency-grid-iq-interleaved",
            "common-phase-phase-slope", "iq-interleaved", "bit-per-byte",
            "bit-per-byte", "bit-per-byte", "bit-per-byte", "scalar",
            "scalar", "scalar", "scalar",
        ]
        _assert_checkpoint_metadata(
            rx.checkpoint_metadata,
            "wifi-bcc-rx-20mhz",
            rx_stages,
            rx_dtypes,
            rx_shapes,
            rx_strides,
            rx_q_formats,
            rx_layouts,
        )


def test_he1024_and_eht4096_ldpc_ru242_phy_tx_rx_checkpoints() raises:
    var channel = Complex64(0.91, 0.27)
    var common = -0.17
    var slope = -0.0012
    for family, mcs_index, octets, bpsc, block_length, shortened, repeated in [
        (WIFI_PHY_HE, 10, 205, 10, 1296, 256, 4),
        (WIFI_PHY_EHT, 13, 264, 12, 1944, 1080, 0),
    ]:
        var payload = _payload_octets(octets, 17 + family)
        var tx = wifi_ldpc_tx_20mhz(
            Span(payload), family, mcs_index, symbol_index=5
        )
        assert_equal(tx.shortened_bits, shortened)
        assert_equal(tx.ldpc_block_length, block_length)
        assert_equal(tx.punctured_bits, 0)
        assert_equal(tx.repeated_bits, repeated)
        assert_equal(len(tx.qam_symbols), 234)
        assert_equal(len(tx.tone_mapped_bits), 234 * bpsc)
        assert_equal(len(tx.waveform), 272)
        var tx_stages: List[String] = [
            "payload-input", "frame-bits", "scrambled-bits",
            "rate-matched-bits", "tone-mapped-bits", "qam-symbols",
            "frequency-grid", "waveform", "fcs",
        ]
        var tx_dtypes: List[String] = [
            "uint8", "uint8", "uint8", "uint8", "uint8", "complex64",
            "complex64", "complex64", "uint64",
        ]
        var tx_shapes: List[String] = [
            _length_text(len(payload)),
            _length_text(len(tx.frame_bits)),
            _length_text(len(tx.scrambled_bits)),
            _length_text(len(tx.rate_matched_bits)),
            _length_text(len(tx.tone_mapped_bits)),
            _length_text(len(tx.qam_symbols)),
            _matrix_shape(1, len(tx.spectrum)),
            _length_text(len(tx.waveform)),
            "1",
        ]
        var tx_strides: List[String] = [
            "1", "1", "1", "1", "1", "1",
            _matrix_stride(len(tx.spectrum)), "1", "1",
        ]
        var tx_q_formats: List[String] = [
            "binary-u1", "binary-u1", "binary-u1", "binary-u1", "binary-u1",
            "floating", "floating", "floating", "unsigned-integer",
        ]
        var tx_layouts: List[String] = [
            "bit-per-byte", "bit-per-byte", "bit-per-byte", "bit-per-byte",
            "bit-per-byte", "iq-interleaved",
            "row-major-frequency-grid-iq-interleaved", "iq-interleaved",
            "scalar",
        ]
        _assert_checkpoint_metadata(
            tx.checkpoint_metadata,
            "wifi-ldpc-tx-20mhz",
            tx_stages,
            tx_dtypes,
            tx_shapes,
            tx_strides,
            tx_q_formats,
            tx_layouts,
        )
        var received = _phase_impaired_symbol(
            Span(tx.spectrum), channel, common, slope
        )
        var ltf = _flat_ltf(family, channel)
        var rx = wifi_ldpc_rx_20mhz(
            Span(received),
            Span(ltf),
            family,
            mcs_index,
            len(payload),
            0.01,
            symbol_index=5,
            max_iterations=10,
        )
        assert_true(rx.ldpc_converged)
        assert_equal(rx.ldpc_block_length, block_length)
        assert_equal(len(rx.equalized_spectrum), 256)
        assert_equal(len(rx.corrected_data_symbols), len(tx.qam_symbols))
        assert_equal(len(rx.physical_llrs), len(tx.tone_mapped_bits))
        for index in range(len(tx.qam_symbols)):
            assert_true(
                abs(
                    rx.corrected_data_symbols[index].re
                    - tx.qam_symbols[index].re
                ) < 1.0e-9
            )
            assert_true(
                abs(
                    rx.corrected_data_symbols[index].im
                    - tx.qam_symbols[index].im
                ) < 1.0e-9
            )
        assert_equal(rx.payload_bits, payload)
        assert_true(rx.service_ok)
        assert_true(rx.fcs_ok)
        assert_true(abs(rx.common_phase - common) < 1.0e-10)
        assert_true(abs(rx.phase_slope - slope) < 1.0e-10)
        var rx_stages: List[String] = [
            "received-waveform", "ltf-samples", "channel-estimate",
            "equalized-spectrum", "pilot-phase-estimate",
            "pilot-corrected-data-symbols", "physical-llrs",
            "tone-demapped-llrs", "rate-recovered-llrs",
            "decoded-frame-bits", "decoded-payload-bits", "received-fcs",
            "computed-fcs", "ldpc-converged", "service-ok", "fcs-ok",
        ]
        var rx_dtypes: List[String] = [
            "complex64", "complex64", "complex64", "complex64", "float64",
            "complex64", "float64", "float64", "float64", "uint8", "uint8",
            "uint64", "uint64", "bool", "bool", "bool",
        ]
        var rx_shapes: List[String] = [
            _length_text(len(received)),
            _length_text(len(ltf)),
            _length_text(len(rx.channel_estimate)),
            _matrix_shape(1, len(rx.equalized_spectrum)),
            "2",
            _length_text(len(rx.corrected_data_symbols)),
            _length_text(len(rx.physical_llrs)),
            _length_text(len(rx.demapped_llrs)),
            _length_text(len(rx.rate_recovered_llrs)),
            _length_text(len(rx.decoded_frame_bits)),
            _length_text(len(rx.payload_bits)),
            "1", "1", "1", "1", "1",
        ]
        var rx_strides: List[String] = [
            "1", "1", "1", _matrix_stride(len(rx.equalized_spectrum)),
            "1", "1", "1", "1", "1", "1", "1", "1", "1", "1", "1",
            "1",
        ]
        var rx_q_formats: List[String] = [
            "floating", "floating", "floating", "floating", "floating",
            "floating", "floating", "floating", "floating", "binary-u1",
            "binary-u1", "unsigned-integer", "unsigned-integer", "boolean",
            "boolean", "boolean",
        ]
        var rx_layouts: List[String] = [
            "iq-interleaved", "iq-interleaved", "iq-interleaved",
            "row-major-frequency-grid-iq-interleaved",
            "common-phase-phase-slope", "iq-interleaved", "linear", "linear",
            "linear", "bit-per-byte", "bit-per-byte", "scalar", "scalar",
            "scalar", "scalar", "scalar",
        ]
        _assert_checkpoint_metadata(
            rx.checkpoint_metadata,
            "wifi-ldpc-rx-20mhz",
            rx_stages,
            rx_dtypes,
            rx_shapes,
            rx_strides,
            rx_q_formats,
            rx_layouts,
        )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
