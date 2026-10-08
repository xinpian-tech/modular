from std.testing import assert_equal, assert_true, assert_raises, TestSuite
from std.math import cos, sin
from std.utils.numerics import inf, nan
from wireless_dsp.core import Complex64, Span
from wireless_dsp.modem import qam_map, qam_demap_hard
from wireless_dsp.wireless.wifi import (
    WIFI_PHY_HT,
    WIFI_PHY_VHT,
    WIFI_PHY_HE,
    WIFI_PHY_EHT,
    WifiMCSProfile,
    WifiOFDMProfile,
    WifiRUProfile,
    WifiPilotPhaseEstimate,
    WifiBCCInterleaverProfile,
    wifi_mcs_profile,
    wifi_ofdm_profile,
    wifi_guard_interval_samples,
    wifi_coded_bits_per_symbol,
    wifi_data_bits_per_symbol,
    wifi_ru_profile,
    wifi_max_ru_count,
    wifi_ru_coded_bits_per_symbol,
    wifi_ru_data_bits_per_symbol,
    wifi_ru_requires_ldpc,
    wifi_ru_subcarriers_20mhz,
    wifi_ru_pilot_subcarriers_20mhz,
    wifi_ru_data_subcarriers_20mhz,
    wifi_ru_allocations_disjoint_20mhz,
    wifi_map_ru_symbol_20mhz,
    wifi_extract_ru_data_20mhz,
    wifi_extract_ru_pilots_20mhz,
    wifi_bcc_puncture_pattern,
    wifi_bcc_puncture,
    wifi_bcc_depuncture_llrs,
    wifi_bcc_interleaver_profile,
    wifi_bcc_interleave_block,
    wifi_bcc_deinterleave_block,
    wifi_estimate_pilot_phase,
    wifi_correct_pilot_phase,
)


def assert_complex_close(actual: Complex64, expected: Complex64, tolerance: Float64) raises:
    assert_true(abs(actual.re - expected.re) <= tolerance)
    assert_true(abs(actual.im - expected.im) <= tolerance)


def test_ht_vht_he_eht_mcs_tables() raises:
    var ht0 = wifi_mcs_profile(WIFI_PHY_HT, 0)
    assert_equal(ht0.bits_per_subcarrier, 1)
    assert_equal(ht0.code_rate_numerator, 1)
    assert_equal(ht0.code_rate_denominator, 2)
    assert_equal(ht0.spatial_streams, 1)

    var ht31 = wifi_mcs_profile(WIFI_PHY_HT, 31)
    assert_equal(ht31.bits_per_subcarrier, 6)
    assert_equal(ht31.code_rate_numerator, 5)
    assert_equal(ht31.code_rate_denominator, 6)
    assert_equal(ht31.spatial_streams, 4)

    var vht9 = wifi_mcs_profile(WIFI_PHY_VHT, 9, spatial_streams=8)
    assert_equal(vht9.bits_per_subcarrier, 8)
    assert_equal(vht9.code_rate_numerator, 5)
    assert_equal(vht9.code_rate_denominator, 6)
    assert_equal(vht9.spatial_streams, 8)

    var he10 = wifi_mcs_profile(WIFI_PHY_HE, 10)
    var he11 = wifi_mcs_profile(WIFI_PHY_HE, 11)
    assert_equal(he10.bits_per_subcarrier, 10)
    assert_equal(he10.code_rate_numerator, 3)
    assert_equal(he11.bits_per_subcarrier, 10)
    assert_equal(he11.code_rate_numerator, 5)
    var he_dcm = wifi_mcs_profile(
        WIFI_PHY_HE, 4, spatial_streams=2, dcm=True
    )
    assert_true(he_dcm.dcm)
    assert_equal(he_dcm.spatial_streams, 2)

    var eht12 = wifi_mcs_profile(WIFI_PHY_EHT, 12)
    var eht13 = wifi_mcs_profile(WIFI_PHY_EHT, 13, spatial_streams=8)
    assert_equal(eht12.bits_per_subcarrier, 12)
    assert_equal(eht12.code_rate_numerator, 3)
    assert_equal(eht13.bits_per_subcarrier, 12)
    assert_equal(eht13.code_rate_numerator, 5)
    assert_equal(eht13.spatial_streams, 8)
    assert_true(eht13.ldpc_only)
    var eht14 = wifi_mcs_profile(WIFI_PHY_EHT, 14)
    var eht15 = wifi_mcs_profile(WIFI_PHY_EHT, 15)
    assert_true(eht14.dcm and eht14.duplicate_mode and eht14.ldpc_only)
    assert_true(eht15.dcm and not eht15.duplicate_mode and not eht15.ldpc_only)

    with assert_raises():
        _ = wifi_mcs_profile(WIFI_PHY_EHT, 13, spatial_streams=9)
    with assert_raises():
        _ = wifi_mcs_profile(WIFI_PHY_VHT, 10)
    with assert_raises():
        _ = wifi_mcs_profile(WIFI_PHY_HE, 5, dcm=True)


def test_he_1024qam_and_eht_4096qam_profile_mapping() raises:
    for family, mcs_index in [(WIFI_PHY_HE, 11), (WIFI_PHY_EHT, 13)]:
        var profile = wifi_mcs_profile(family, mcs_index)
        var bits = List[UInt8](capacity=4 * profile.bits_per_subcarrier)
        for i in range(4 * profile.bits_per_subcarrier):
            bits.append(UInt8((i * 13 + i // 5 + 1) & 1))
        var symbols = qam_map(Span(bits), profile.bits_per_subcarrier)
        assert_equal(
            qam_demap_hard(Span(symbols), profile.bits_per_subcarrier), bits
        )


def test_ofdm_profiles_timing_and_symbol_capacity() raises:
    var ht40 = wifi_ofdm_profile(WIFI_PHY_HT, 40)
    assert_equal(ht40.fft_size, 128)
    assert_equal(ht40.data_subcarriers, 108)
    assert_equal(ht40.pilot_subcarriers, 6)
    assert_equal(wifi_guard_interval_samples(ht40, 400), 16)

    var vht160 = wifi_ofdm_profile(WIFI_PHY_VHT, 160)
    assert_equal(vht160.fft_size, 512)
    assert_equal(vht160.data_subcarriers, 468)
    assert_equal(vht160.pilot_subcarriers, 16)
    var vht20 = wifi_ofdm_profile(WIFI_PHY_VHT, 20)
    var vht9_one_stream = wifi_mcs_profile(WIFI_PHY_VHT, 9)
    with assert_raises():
        _ = wifi_data_bits_per_symbol(vht20, vht9_one_stream)
    var vht9_three_streams = wifi_mcs_profile(
        WIFI_PHY_VHT, 9, spatial_streams=3
    )
    assert_equal(wifi_data_bits_per_symbol(vht20, vht9_three_streams), 1040)

    var he20 = wifi_ofdm_profile(WIFI_PHY_HE, 20)
    assert_equal(he20.fft_size, 256)
    assert_equal(he20.data_subcarriers, 234)
    assert_equal(he20.pilot_subcarriers, 8)
    var he11 = wifi_mcs_profile(WIFI_PHY_HE, 11)
    assert_equal(wifi_coded_bits_per_symbol(he20, he11), 2340)
    assert_equal(wifi_data_bits_per_symbol(he20, he11), 1950)

    var eht320 = wifi_ofdm_profile(WIFI_PHY_EHT, 320)
    assert_equal(eht320.fft_size, 4096)
    assert_equal(eht320.data_subcarriers, 3920)
    assert_equal(eht320.pilot_subcarriers, 64)
    assert_equal(wifi_guard_interval_samples(eht320, 800), 256)
    var eht13 = wifi_mcs_profile(WIFI_PHY_EHT, 13)
    assert_equal(wifi_data_bits_per_symbol(eht320, eht13), 39200)
    var eht14 = wifi_mcs_profile(WIFI_PHY_EHT, 14)
    var eht15 = wifi_mcs_profile(WIFI_PHY_EHT, 15)
    assert_equal(wifi_data_bits_per_symbol(eht320, eht14), 490)
    assert_equal(wifi_data_bits_per_symbol(eht320, eht15), 980)
    var eht80 = wifi_ofdm_profile(WIFI_PHY_EHT, 80)
    assert_equal(wifi_coded_bits_per_symbol(eht80, eht14), 234)
    assert_equal(wifi_data_bits_per_symbol(eht80, eht14), 117)
    var eht20 = wifi_ofdm_profile(WIFI_PHY_EHT, 20)
    with assert_raises():
        _ = wifi_coded_bits_per_symbol(eht20, eht14)

    with assert_raises():
        _ = wifi_ofdm_profile(WIFI_PHY_HE, 320)
    with assert_raises():
        _ = wifi_guard_interval_samples(he20, 400)


def test_he_eht_ru_profiles_and_capacity() raises:
    var ru26 = wifi_ru_profile(WIFI_PHY_HE, 26)
    assert_equal(ru26.data_subcarriers, 24)
    assert_equal(ru26.pilot_subcarriers, 2)
    assert_true(not ru26.requires_ldpc)
    var ru996 = wifi_ru_profile(WIFI_PHY_HE, 996)
    assert_equal(ru996.data_subcarriers, 980)
    assert_equal(ru996.pilot_subcarriers, 16)
    assert_true(ru996.requires_ldpc)
    var ru4x996 = wifi_ru_profile(WIFI_PHY_EHT, 3984)
    assert_equal(ru4x996.data_subcarriers, 3920)
    assert_equal(ru4x996.pilot_subcarriers, 64)
    assert_equal(ru4x996.minimum_bandwidth_mhz, 320)

    assert_equal(wifi_max_ru_count(WIFI_PHY_HE, 20, 26), 9)
    assert_equal(wifi_max_ru_count(WIFI_PHY_HE, 80, 26), 37)
    assert_equal(wifi_max_ru_count(WIFI_PHY_HE, 160, 996), 2)
    assert_equal(wifi_max_ru_count(WIFI_PHY_EHT, 320, 3984), 1)
    var he_mcs0_dcm = wifi_mcs_profile(WIFI_PHY_HE, 0, dcm=True)
    var he_ru106 = wifi_ru_profile(WIFI_PHY_HE, 106)
    assert_equal(wifi_ru_coded_bits_per_symbol(he_ru106, he_mcs0_dcm), 51)
    assert_equal(wifi_ru_data_bits_per_symbol(he_ru106, he_mcs0_dcm), 25)
    assert_true(not wifi_ru_requires_ldpc(he_ru106, he_mcs0_dcm))
    var he_mcs11 = wifi_mcs_profile(WIFI_PHY_HE, 11)
    with assert_raises():
        _ = wifi_ru_coded_bits_per_symbol(he_ru106, he_mcs11)
    var he_ru242 = wifi_ru_profile(WIFI_PHY_HE, 242)
    assert_true(wifi_ru_requires_ldpc(he_ru242, he_mcs11))
    assert_equal(wifi_ru_data_bits_per_symbol(he_ru242, he_mcs11), 1950)
    with assert_raises():
        _ = wifi_max_ru_count(WIFI_PHY_HE, 20, 484)


def test_20mhz_ru_tone_and_pilot_tables() raises:
    var center26 = wifi_ru_subcarriers_20mhz(26, 4)
    assert_equal(len(center26), 26)
    assert_equal(center26[0], -16)
    assert_equal(center26[12], -4)
    assert_equal(center26[13], 4)
    assert_equal(center26[25], 16)
    assert_equal(wifi_ru_pilot_subcarriers_20mhz(26, 4), [-10, 10])
    assert_equal(len(wifi_ru_data_subcarriers_20mhz(26, 4)), 24)

    assert_equal(
        wifi_ru_pilot_subcarriers_20mhz(52, 0),
        [-116, -102, -90, -76],
    )
    assert_equal(
        wifi_ru_pilot_subcarriers_20mhz(106, 0),
        [-116, -90, -48, -22],
    )
    assert_equal(
        wifi_ru_pilot_subcarriers_20mhz(242, 0),
        [-116, -90, -48, -22, 22, 48, 90, 116],
    )
    assert_equal(len(wifi_ru_data_subcarriers_20mhz(52, 2)), 48)
    assert_equal(len(wifi_ru_data_subcarriers_20mhz(106, 1)), 102)
    assert_equal(len(wifi_ru_data_subcarriers_20mhz(242, 0)), 234)


def test_20mhz_ru_allocation_overlap_and_mapping() raises:
    var four52_sizes: List[Int] = [52, 52, 52, 52]
    var four52_indices: List[Int] = [0, 1, 2, 3]
    assert_true(
        wifi_ru_allocations_disjoint_20mhz(
            Span(four52_sizes), Span(four52_indices)
        )
    )
    var overlap_sizes: List[Int] = [52, 26]
    var overlap_indices: List[Int] = [0, 0]
    assert_true(
        not wifi_ru_allocations_disjoint_20mhz(
            Span(overlap_sizes), Span(overlap_indices)
        )
    )

    var data = List[Complex64](capacity=102)
    for i in range(102):
        data.append(Complex64(Float64(i) - 50.0, Float64((i * 7) % 13)))
    var pilots: List[Complex64] = [
        Complex64(1.0), Complex64(-1.0), Complex64(1.0), Complex64(1.0)
    ]
    var spectrum = wifi_map_ru_symbol_20mhz(Span(data), Span(pilots), 106, 1)
    assert_equal(len(spectrum), 256)
    assert_equal(wifi_extract_ru_data_20mhz(Span(spectrum), 106, 1), data)
    assert_equal(wifi_extract_ru_pilots_20mhz(Span(spectrum), 106, 1), pilots)


def test_bcc_puncturing_vectors() raises:
    assert_equal(wifi_bcc_puncture_pattern(1, 2), [1, 1])
    assert_equal(wifi_bcc_puncture_pattern(2, 3), [1, 1, 1, 0])
    assert_equal(wifi_bcc_puncture_pattern(3, 4), [1, 1, 1, 0, 0, 1])
    assert_equal(
        wifi_bcc_puncture_pattern(5, 6),
        [1, 1, 1, 0, 0, 1, 1, 0, 0, 1],
    )
    var mother: List[UInt8] = [0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1]
    assert_equal(wifi_bcc_puncture(Span(mother), 3, 4), [0, 1, 0, 1, 0, 1, 0, 1])
    var llrs: List[Float64] = [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0]
    assert_equal(
        wifi_bcc_depuncture_llrs(Span(llrs), 12, 3, 4),
        [1.0, 2.0, 3.0, 0.0, 0.0, 4.0, 5.0, 6.0, 7.0, 0.0, 0.0, 8.0],
    )


def check_bcc_interleaver_roundtrip(
    profile: WifiBCCInterleaverProfile,
    bits_per_subcarrier: Int,
    spatial_stream_index: Int,
) raises:
    var count = profile.block_data_subcarriers * bits_per_subcarrier
    var bits = List[UInt8](capacity=count)
    for i in range(count):
        bits.append(UInt8((i * 11 + i // 7 + 1) & 1))
    var interleaved = wifi_bcc_interleave_block(
        Span(bits),
        bits_per_subcarrier,
        profile,
        spatial_stream_index=spatial_stream_index,
    )
    var recovered = wifi_bcc_deinterleave_block(
        Span(interleaved),
        bits_per_subcarrier,
        profile,
        spatial_stream_index=spatial_stream_index,
    )
    assert_equal(recovered, bits)


def test_bcc_interleaver_profiles_and_roundtrip() raises:
    var ht20 = wifi_bcc_interleaver_profile(WIFI_PHY_HT, 20)
    assert_equal(ht20.columns, 13)
    assert_equal(ht20.rows_per_modulation_bit, 4)
    check_bcc_interleaver_roundtrip(ht20, 1, 0)
    check_bcc_interleaver_roundtrip(ht20, 6, 3)

    var vht80 = wifi_bcc_interleaver_profile(WIFI_PHY_VHT, 80)
    assert_equal(vht80.columns, 26)
    assert_equal(vht80.rows_per_modulation_bit, 9)
    check_bcc_interleaver_roundtrip(vht80, 8, 7)
    var vht160 = wifi_bcc_interleaver_profile(WIFI_PHY_VHT, 160)
    assert_equal(vht160.blocks_per_symbol, 2)
    assert_equal(vht160.block_data_subcarriers, 234)

    var he106 = wifi_bcc_interleaver_profile(WIFI_PHY_HE, 80, ru_tones=106)
    assert_equal(he106.columns, 17)
    assert_equal(he106.rows_per_modulation_bit, 6)
    check_bcc_interleaver_roundtrip(he106, 4, 2)
    var he106_dcm = wifi_bcc_interleaver_profile(
        WIFI_PHY_HE, 80, ru_tones=106, dcm=True
    )
    assert_true(he106_dcm.dcm)
    assert_equal(he106_dcm.block_data_subcarriers, 51)
    assert_equal(he106_dcm.columns, 17)
    assert_equal(he106_dcm.rows_per_modulation_bit, 3)
    assert_equal(he106_dcm.rotation_subcarriers, 11)
    check_bcc_interleaver_roundtrip(he106_dcm, 4, 1)
    var eht242 = wifi_bcc_interleaver_profile(WIFI_PHY_EHT, 320, ru_tones=242)
    check_bcc_interleaver_roundtrip(eht242, 8, 1)
    var invalid_bits = List[UInt8](length=2340, fill=UInt8(0))
    with assert_raises():
        _ = wifi_bcc_interleave_block(Span(invalid_bits), 10, eht242)
    with assert_raises():
        _ = wifi_bcc_interleaver_profile(WIFI_PHY_HE, 80, ru_tones=484)


def test_bcc_interleaver_known_index_mapping() raises:
    var profile = wifi_bcc_interleaver_profile(WIFI_PHY_HT, 20)
    var bits = List[UInt8](length=52, fill=UInt8(0))
    bits[13] = 1
    var mapped = wifi_bcc_interleave_block(Span(bits), 1, profile)
    assert_equal(mapped[1], UInt8(1))

    var qpsk_bits = List[UInt8](length=104, fill=UInt8(0))
    qpsk_bits[0] = 1
    var rotated = wifi_bcc_interleave_block(
        Span(qpsk_bits), 2, profile, spatial_stream_index=1
    )
    assert_equal(rotated[60], UInt8(1))


def test_pilot_common_and_linear_phase_tracking() raises:
    var indices: List[Int] = [-116, -48, 22, 90]
    var known: List[Complex64] = [
        Complex64(1.0), Complex64(-1.0), Complex64(1.0), Complex64(-1.0)
    ]
    var common = 3.0
    var slope = 0.01
    var received = List[Complex64](capacity=4)
    for i in range(4):
        var phase = common + slope * Float64(indices[i])
        received.append(known[i] * Complex64(cos(phase), sin(phase)))
    var estimate = wifi_estimate_pilot_phase(
        Span(received), Span(known), Span(indices)
    )
    assert_true(abs(estimate.common_phase - common) < 1.0e-12)
    assert_true(abs(estimate.phase_slope - slope) < 1.0e-12)
    assert_true(estimate.residual_mean_square < 1.0e-24)

    var data_indices: List[Int] = [-100, -17, 4, 70]
    var original: List[Complex64] = [
        Complex64(0.5, -0.25),
        Complex64(-1.0, 0.5),
        Complex64(0.25, 1.25),
        Complex64(-0.75, -0.5),
    ]
    var impaired = List[Complex64](capacity=4)
    for i in range(4):
        var phase = common + slope * Float64(data_indices[i])
        impaired.append(original[i] * Complex64(cos(phase), sin(phase)))
    var corrected = wifi_correct_pilot_phase(
        Span(impaired), Span(data_indices), estimate
    )
    for i in range(4):
        assert_complex_close(corrected[i], original[i], 1.0e-12)

    # The estimator is invariant to pilot magnitude, including scales whose
    # direct squared magnitude would overflow or underflow Float64.
    var extreme_indices: List[Int] = [-1, 1]
    var extreme_known: List[Complex64] = [
        Complex64(1.0e308, 0.0),
        Complex64(1.0e-308, 0.0),
    ]
    var extreme_received: List[Complex64] = [
        Complex64(1.0e308 * cos(0.1), 1.0e308 * sin(0.1)),
        Complex64(1.0e-308 * cos(0.3), 1.0e-308 * sin(0.3)),
    ]
    var extreme_estimate = wifi_estimate_pilot_phase(
        Span(extreme_received), Span(extreme_known), Span(extreme_indices)
    )
    assert_true(abs(extreme_estimate.common_phase - 0.2) <= 2.0e-15)
    assert_true(abs(extreme_estimate.phase_slope - 0.1) <= 2.0e-15)


def _assert_mcs_consumers_reject(profile: WifiMCSProfile) raises:
    var ofdm = wifi_ofdm_profile(WIFI_PHY_HE, 20)
    with assert_raises():
        _ = wifi_coded_bits_per_symbol(ofdm, profile)
    with assert_raises():
        _ = wifi_data_bits_per_symbol(ofdm, profile)


def _assert_ofdm_consumers_reject(profile: WifiOFDMProfile) raises:
    var mcs = wifi_mcs_profile(WIFI_PHY_HE, 2)
    with assert_raises():
        _ = wifi_guard_interval_samples(profile, 800)
    with assert_raises():
        _ = wifi_coded_bits_per_symbol(profile, mcs)
    with assert_raises():
        _ = wifi_data_bits_per_symbol(profile, mcs)


def _assert_ru_consumers_reject(profile: WifiRUProfile) raises:
    var mcs = wifi_mcs_profile(WIFI_PHY_HE, 2)
    with assert_raises():
        _ = wifi_ru_coded_bits_per_symbol(profile, mcs)
    with assert_raises():
        _ = wifi_ru_data_bits_per_symbol(profile, mcs)
    with assert_raises():
        _ = wifi_ru_requires_ldpc(profile, mcs)


def _assert_bcc_consumers_reject(
    profile: WifiBCCInterleaverProfile, input_length: Int
) raises:
    var bits = List[UInt8](length=input_length, fill=UInt8(0))
    with assert_raises():
        _ = wifi_bcc_interleave_block(Span(bits), 1, profile)
    with assert_raises():
        _ = wifi_bcc_deinterleave_block(Span(bits), 1, profile)


def test_canonical_profile_validators_accept_all_factory_rows() raises:
    var ht_ofdm = wifi_ofdm_profile(WIFI_PHY_HT, 20)
    for mcs_index in range(32):
        var mcs = wifi_mcs_profile(WIFI_PHY_HT, mcs_index)
        assert_true(wifi_coded_bits_per_symbol(ht_ofdm, mcs) > 0)

    var vht_ofdm = wifi_ofdm_profile(WIFI_PHY_VHT, 20)
    for mcs_index in range(10):
        for streams in range(1, 9):
            var mcs = wifi_mcs_profile(
                WIFI_PHY_VHT, mcs_index, spatial_streams=streams
            )
            assert_true(wifi_coded_bits_per_symbol(vht_ofdm, mcs) > 0)

    var he_ofdm = wifi_ofdm_profile(WIFI_PHY_HE, 20)
    for mcs_index in range(12):
        for streams in range(1, 9):
            var mcs = wifi_mcs_profile(
                WIFI_PHY_HE, mcs_index, spatial_streams=streams
            )
            assert_true(wifi_coded_bits_per_symbol(he_ofdm, mcs) > 0)
    for mcs_index in [0, 1, 3, 4]:
        for streams in range(1, 3):
            var mcs = wifi_mcs_profile(
                WIFI_PHY_HE,
                mcs_index,
                spatial_streams=streams,
                dcm=True,
            )
            assert_true(wifi_coded_bits_per_symbol(he_ofdm, mcs) > 0)

    var eht_ofdm = wifi_ofdm_profile(WIFI_PHY_EHT, 80)
    for mcs_index in range(14):
        for streams in range(1, 9):
            var mcs = wifi_mcs_profile(
                WIFI_PHY_EHT, mcs_index, spatial_streams=streams
            )
            assert_true(wifi_coded_bits_per_symbol(eht_ofdm, mcs) > 0)
    assert_true(
        wifi_coded_bits_per_symbol(
            eht_ofdm, wifi_mcs_profile(WIFI_PHY_EHT, 14)
        )
        > 0
    )
    assert_true(
        wifi_coded_bits_per_symbol(
            eht_ofdm, wifi_mcs_profile(WIFI_PHY_EHT, 15)
        )
        > 0
    )

    for family, bandwidth in [
        (WIFI_PHY_HT, 20),
        (WIFI_PHY_HT, 40),
        (WIFI_PHY_VHT, 20),
        (WIFI_PHY_VHT, 40),
        (WIFI_PHY_VHT, 80),
        (WIFI_PHY_VHT, 160),
        (WIFI_PHY_HE, 20),
        (WIFI_PHY_HE, 40),
        (WIFI_PHY_HE, 80),
        (WIFI_PHY_HE, 160),
        (WIFI_PHY_EHT, 20),
        (WIFI_PHY_EHT, 40),
        (WIFI_PHY_EHT, 80),
        (WIFI_PHY_EHT, 160),
        (WIFI_PHY_EHT, 320),
    ]:
        var profile = wifi_ofdm_profile(family, bandwidth)
        var guard_interval_ns = 400 if family <= WIFI_PHY_VHT else 800
        assert_true(
            wifi_guard_interval_samples(profile, guard_interval_ns) > 0
        )

    for family in [WIFI_PHY_HE, WIFI_PHY_EHT]:
        var mcs = wifi_mcs_profile(family, 0)
        for ru_tones in [26, 52, 106, 242, 484, 996, 1992, 3984]:
            if family == WIFI_PHY_HE and ru_tones == 3984:
                continue
            var profile = wifi_ru_profile(family, ru_tones)
            assert_true(wifi_ru_coded_bits_per_symbol(profile, mcs) > 0)
            assert_true(wifi_ru_data_bits_per_symbol(profile, mcs) > 0)
            _ = wifi_ru_requires_ldpc(profile, mcs)

    for family, bandwidth in [
        (WIFI_PHY_HT, 20),
        (WIFI_PHY_HT, 40),
        (WIFI_PHY_VHT, 20),
        (WIFI_PHY_VHT, 40),
        (WIFI_PHY_VHT, 80),
        (WIFI_PHY_VHT, 160),
    ]:
        check_bcc_interleaver_roundtrip(
            wifi_bcc_interleaver_profile(family, bandwidth), 1, 0
        )
    for family in [WIFI_PHY_HE, WIFI_PHY_EHT]:
        for ru_tones in [26, 52, 106, 242]:
            check_bcc_interleaver_roundtrip(
                wifi_bcc_interleaver_profile(
                    family, 20, ru_tones=ru_tones
                ),
                1,
                0,
            )
            check_bcc_interleaver_roundtrip(
                wifi_bcc_interleaver_profile(
                    family, 20, ru_tones=ru_tones, dcm=True
                ),
                1,
                0,
            )

    # HE/EHT SIGNAL uses this exact 56-tone, zero-rotation internal row rather
    # than one of the data-profile factory rows.
    for family in [WIFI_PHY_HE, WIFI_PHY_EHT]:
        check_bcc_interleaver_roundtrip(
            WifiBCCInterleaverProfile(family, 52, 13, 4, 0, 1, False),
            1,
            0,
        )


def test_mutable_profile_fields_are_revalidated_before_arithmetic() raises:
    var invalid_mcs = wifi_mcs_profile(WIFI_PHY_HE, 2)
    invalid_mcs.family = Int.MIN
    _assert_mcs_consumers_reject(invalid_mcs)
    invalid_mcs = wifi_mcs_profile(WIFI_PHY_HE, 2)
    invalid_mcs.mcs_index = Int.MAX
    _assert_mcs_consumers_reject(invalid_mcs)
    invalid_mcs = wifi_mcs_profile(WIFI_PHY_HE, 2)
    invalid_mcs.bits_per_subcarrier = Int.MAX
    _assert_mcs_consumers_reject(invalid_mcs)
    invalid_mcs = wifi_mcs_profile(WIFI_PHY_HE, 2)
    invalid_mcs.code_rate_numerator = Int.MIN
    _assert_mcs_consumers_reject(invalid_mcs)
    invalid_mcs = wifi_mcs_profile(WIFI_PHY_HE, 2)
    invalid_mcs.code_rate_denominator = 0
    _assert_mcs_consumers_reject(invalid_mcs)
    invalid_mcs = wifi_mcs_profile(WIFI_PHY_HE, 2)
    invalid_mcs.spatial_streams = 0
    _assert_mcs_consumers_reject(invalid_mcs)
    invalid_mcs = wifi_mcs_profile(WIFI_PHY_HE, 2)
    invalid_mcs.dcm = True
    _assert_mcs_consumers_reject(invalid_mcs)
    invalid_mcs = wifi_mcs_profile(WIFI_PHY_HE, 2)
    invalid_mcs.duplicate_mode = True
    _assert_mcs_consumers_reject(invalid_mcs)
    invalid_mcs = wifi_mcs_profile(WIFI_PHY_HE, 2)
    invalid_mcs.ldpc_only = True
    _assert_mcs_consumers_reject(invalid_mcs)

    var invalid_ofdm = wifi_ofdm_profile(WIFI_PHY_HE, 20)
    invalid_ofdm.family = Int.MAX
    _assert_ofdm_consumers_reject(invalid_ofdm)
    invalid_ofdm = wifi_ofdm_profile(WIFI_PHY_HE, 20)
    invalid_ofdm.bandwidth_mhz = 0
    _assert_ofdm_consumers_reject(invalid_ofdm)
    invalid_ofdm = wifi_ofdm_profile(WIFI_PHY_HE, 20)
    invalid_ofdm.fft_size = Int.MAX
    _assert_ofdm_consumers_reject(invalid_ofdm)
    invalid_ofdm = wifi_ofdm_profile(WIFI_PHY_HE, 20)
    invalid_ofdm.data_subcarriers = Int.MAX
    _assert_ofdm_consumers_reject(invalid_ofdm)
    invalid_ofdm = wifi_ofdm_profile(WIFI_PHY_HE, 20)
    invalid_ofdm.pilot_subcarriers = Int.MIN
    _assert_ofdm_consumers_reject(invalid_ofdm)
    invalid_ofdm = wifi_ofdm_profile(WIFI_PHY_HE, 20)
    invalid_ofdm.occupied_subcarriers = 0
    _assert_ofdm_consumers_reject(invalid_ofdm)
    invalid_ofdm = wifi_ofdm_profile(WIFI_PHY_HE, 20)
    invalid_ofdm.useful_symbol_ns = 0
    _assert_ofdm_consumers_reject(invalid_ofdm)
    invalid_ofdm = wifi_ofdm_profile(WIFI_PHY_HE, 20)
    invalid_ofdm.default_guard_interval_ns = Int.MIN
    _assert_ofdm_consumers_reject(invalid_ofdm)
    invalid_ofdm = wifi_ofdm_profile(WIFI_PHY_HE, 20)
    invalid_ofdm.maximum_spatial_streams = 0
    _assert_ofdm_consumers_reject(invalid_ofdm)

    var invalid_ru = wifi_ru_profile(WIFI_PHY_HE, 26)
    invalid_ru.family = Int.MIN
    _assert_ru_consumers_reject(invalid_ru)
    invalid_ru = wifi_ru_profile(WIFI_PHY_HE, 26)
    invalid_ru.ru_tones = Int.MAX
    _assert_ru_consumers_reject(invalid_ru)
    invalid_ru = wifi_ru_profile(WIFI_PHY_HE, 26)
    invalid_ru.data_subcarriers = Int.MAX
    _assert_ru_consumers_reject(invalid_ru)
    invalid_ru = wifi_ru_profile(WIFI_PHY_HE, 26)
    invalid_ru.pilot_subcarriers = Int.MIN
    _assert_ru_consumers_reject(invalid_ru)
    invalid_ru = wifi_ru_profile(WIFI_PHY_HE, 26)
    invalid_ru.minimum_bandwidth_mhz = 0
    _assert_ru_consumers_reject(invalid_ru)
    invalid_ru = wifi_ru_profile(WIFI_PHY_HE, 26)
    invalid_ru.requires_ldpc = True
    _assert_ru_consumers_reject(invalid_ru)

    var invalid_bcc = wifi_bcc_interleaver_profile(
        WIFI_PHY_HE, 20, ru_tones=26
    )
    invalid_bcc.family = Int.MAX
    _assert_bcc_consumers_reject(invalid_bcc, 24)
    invalid_bcc = wifi_bcc_interleaver_profile(
        WIFI_PHY_HE, 20, ru_tones=26
    )
    invalid_bcc.block_data_subcarriers = Int.MAX
    _assert_bcc_consumers_reject(invalid_bcc, 24)
    invalid_bcc = wifi_bcc_interleaver_profile(
        WIFI_PHY_HE, 20, ru_tones=26
    )
    invalid_bcc.columns = 0
    _assert_bcc_consumers_reject(invalid_bcc, 24)
    invalid_bcc = wifi_bcc_interleaver_profile(
        WIFI_PHY_HE, 20, ru_tones=26
    )
    invalid_bcc.rows_per_modulation_bit = Int.MIN
    _assert_bcc_consumers_reject(invalid_bcc, 24)
    invalid_bcc = wifi_bcc_interleaver_profile(
        WIFI_PHY_HE, 20, ru_tones=26
    )
    invalid_bcc.rotation_subcarriers = Int.MAX
    _assert_bcc_consumers_reject(invalid_bcc, 24)
    invalid_bcc = wifi_bcc_interleaver_profile(
        WIFI_PHY_HE, 20, ru_tones=26
    )
    invalid_bcc.blocks_per_symbol = 0
    _assert_bcc_consumers_reject(invalid_bcc, 24)
    # Use RU-52 here because toggling DCM on the RU-26 non-DCM geometry would
    # intentionally form the distinct, canonical RU-52 DCM row.
    invalid_bcc = wifi_bcc_interleaver_profile(
        WIFI_PHY_HE, 20, ru_tones=52
    )
    invalid_bcc.dcm = True
    _assert_bcc_consumers_reject(invalid_bcc, 48)

    # This forged geometry is internally self-consistent, so rejection cannot
    # be attributed to the public APIs' ordinary length/shape checks.
    _assert_bcc_consumers_reject(
        WifiBCCInterleaverProfile(WIFI_PHY_HE, 1, 1, 1, 0, 1, False),
        1,
    )


def test_signal_profile_exact_row_and_extreme_factory_domains() raises:
    var invalid_signal = WifiBCCInterleaverProfile(
        WIFI_PHY_HE, 52, 13, 4, 0, 1, False
    )
    invalid_signal.family = Int.MAX
    _assert_bcc_consumers_reject(invalid_signal, 52)
    invalid_signal = WifiBCCInterleaverProfile(
        WIFI_PHY_HE, 52, 13, 4, 0, 1, False
    )
    invalid_signal.block_data_subcarriers = 51
    _assert_bcc_consumers_reject(invalid_signal, 52)
    invalid_signal = WifiBCCInterleaverProfile(
        WIFI_PHY_HE, 52, 13, 4, 0, 1, False
    )
    invalid_signal.columns = 12
    _assert_bcc_consumers_reject(invalid_signal, 52)
    invalid_signal = WifiBCCInterleaverProfile(
        WIFI_PHY_HE, 52, 13, 4, 0, 1, False
    )
    invalid_signal.rows_per_modulation_bit = 3
    _assert_bcc_consumers_reject(invalid_signal, 52)
    invalid_signal = WifiBCCInterleaverProfile(
        WIFI_PHY_HE, 52, 13, 4, 0, 1, False
    )
    invalid_signal.rotation_subcarriers = 1
    _assert_bcc_consumers_reject(invalid_signal, 52)
    invalid_signal = WifiBCCInterleaverProfile(
        WIFI_PHY_HE, 52, 13, 4, 0, 1, False
    )
    invalid_signal.blocks_per_symbol = 0
    _assert_bcc_consumers_reject(invalid_signal, 52)
    invalid_signal = WifiBCCInterleaverProfile(
        WIFI_PHY_HE, 52, 13, 4, 0, 1, False
    )
    invalid_signal.dcm = True
    _assert_bcc_consumers_reject(invalid_signal, 52)

    for invalid_family in [Int.MIN, 0, Int.MAX]:
        with assert_raises():
            _ = wifi_mcs_profile(invalid_family, 0)
        with assert_raises():
            _ = wifi_ofdm_profile(invalid_family, 20)
        with assert_raises():
            _ = wifi_ru_profile(invalid_family, 26)
        with assert_raises():
            _ = wifi_bcc_interleaver_profile(invalid_family, 20)
    for invalid_index in [Int.MIN, -1, 12, Int.MAX]:
        with assert_raises():
            _ = wifi_mcs_profile(WIFI_PHY_HE, invalid_index)
    for invalid_streams in [Int.MIN, -1, 9, Int.MAX]:
        with assert_raises():
            _ = wifi_mcs_profile(
                WIFI_PHY_HE, 0, spatial_streams=invalid_streams
            )
    for invalid_bandwidth in [Int.MIN, 0, Int.MAX]:
        with assert_raises():
            _ = wifi_ofdm_profile(WIFI_PHY_HE, invalid_bandwidth)
        with assert_raises():
            _ = wifi_bcc_interleaver_profile(
                WIFI_PHY_HE, invalid_bandwidth, ru_tones=26
            )
    for invalid_ru_tones in [Int.MIN, 0, Int.MAX]:
        with assert_raises():
            _ = wifi_ru_profile(WIFI_PHY_HE, invalid_ru_tones)
        with assert_raises():
            _ = wifi_bcc_interleaver_profile(
                WIFI_PHY_HE, 20, ru_tones=invalid_ru_tones
            )

    var he20 = wifi_ofdm_profile(WIFI_PHY_HE, 20)
    for invalid_guard in [Int.MIN, 0, Int.MAX]:
        with assert_raises():
            _ = wifi_guard_interval_samples(he20, invalid_guard)
    var he_bcc = wifi_bcc_interleaver_profile(
        WIFI_PHY_HE, 20, ru_tones=26
    )
    var bits = List[UInt8](length=24, fill=UInt8(0))
    for invalid_bpsc in [Int.MIN, 0, Int.MAX]:
        with assert_raises():
            _ = wifi_bcc_interleave_block(
                Span(bits), invalid_bpsc, he_bcc
            )
        with assert_raises():
            _ = wifi_bcc_deinterleave_block(
                Span(bits), invalid_bpsc, he_bcc
            )
    for invalid_stream in [Int.MIN, Int.MAX]:
        with assert_raises():
            _ = wifi_bcc_interleave_block(
                Span(bits), 1, he_bcc, spatial_stream_index=invalid_stream
            )
        with assert_raises():
            _ = wifi_bcc_deinterleave_block(
                Span(bits), 1, he_bcc, spatial_stream_index=invalid_stream
            )


def test_profile_validation_edges() raises:
    with assert_raises():
        _ = wifi_ru_subcarriers_20mhz(26, 9)
    with assert_raises():
        _ = wifi_ru_profile(WIFI_PHY_VHT, 242)
    var ht20 = wifi_bcc_interleaver_profile(WIFI_PHY_HT, 20)
    var ht_bits = List[UInt8](length=52, fill=UInt8(0))
    with assert_raises():
        _ = wifi_bcc_interleave_block(
            Span(ht_bits), 1, ht20, spatial_stream_index=4
        )
    var he26_dcm = wifi_bcc_interleaver_profile(
        WIFI_PHY_HE, 20, ru_tones=26, dcm=True
    )
    var he_dcm_bits = List[UInt8](length=12, fill=UInt8(0))
    with assert_raises():
        _ = wifi_bcc_interleave_block(
            Span(he_dcm_bits), 1, he26_dcm, spatial_stream_index=2
        )
    var eht26_dcm = wifi_bcc_interleaver_profile(
        WIFI_PHY_EHT, 20, ru_tones=26, dcm=True
    )
    with assert_raises():
        _ = wifi_bcc_interleave_block(
            Span(he_dcm_bits), 1, eht26_dcm, spatial_stream_index=1
        )
    var empty_received = List[Complex64]()
    var empty_known = List[Complex64]()
    var empty_int = List[Int]()
    with assert_raises():
        _ = wifi_estimate_pilot_phase(
            Span(empty_received), Span(empty_known), Span(empty_int)
        )
    var one_known: List[Complex64] = [Complex64(1.0, 0.0)]
    var one_index: List[Int] = [0]
    var zero_pilot: List[Complex64] = [Complex64(0.0, 0.0)]
    with assert_raises():
        _ = wifi_estimate_pilot_phase(
            Span(zero_pilot), Span(one_known), Span(one_index)
        )
    var invalid_pilot: List[Complex64] = [
        Complex64(nan[DType.float64](), 0.0)
    ]
    with assert_raises():
        _ = wifi_estimate_pilot_phase(
            Span(invalid_pilot), Span(one_known), Span(one_index)
        )
    var one_sample: List[Complex64] = [Complex64(1.0, 0.0)]
    var invalid_estimate = WifiPilotPhaseEstimate(
        inf[DType.float64](), 0.0, 0.0
    )
    with assert_raises():
        _ = wifi_correct_pilot_phase(
            Span(one_sample), Span(one_index), invalid_estimate
        )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
