"""Independent exact evidence for bounded Clause-23 S1G PHY arithmetic.

The static oracles below transcribe the five one-stream OFDM/MCS tables and
occupied-tone intervals independently of production control flow.  Seeded
geometry evidence uses a separate integer ceiling formula.  All discrete
comparisons and frequency-grid comparisons are exact (zero tolerance).

The current IEEE 802.11-2024 landing page and published table-of-contents
preview are public, but IEEE GET requires an interactive personal account for
the full standard in this environment.  Tests therefore make no claim beyond
the stable integer rows/formulas named in the production module.
"""

from std.collections import Span
from std.testing import assert_equal, assert_raises, assert_true, TestSuite
from std.utils.numerics import inf, nan
from wireless_dsp.wireless.wifi.s1g_phy import (
    WIFI_S1G_SUBCARRIER_SPACING_HZ,
    WIFI_S1G_FFT_PERIOD_NS,
    WIFI_S1G_LONG_GI_NS,
    WIFI_S1G_SHORT_GI_NS,
    WIFI_S1G_LONG_SYMBOL_NS,
    WIFI_S1G_SHORT_SYMBOL_NS,
    WIFI_S1G_SERVICE_BITS,
    WIFI_S1G_BCC_TAIL_BITS,
    WIFI_S1G_NON_MCS10_MAX_DATA_SYMBOLS,
    WIFI_S1G_MCS10_MAX_PSDU_OCTETS,
    WIFI_S1G_MAX_PSDU_OCTETS,
    WIFI_S1G_MAX_PPDU_DURATION_NS,
    WIFI_S1G_1M_PREAMBLE_NS,
    WIFI_S1G_SHORT_PREAMBLE_NS,
    WifiS1GOFDMProfile,
    WifiS1GMCSProfile,
    WifiS1GBCCSUConfig,
    wifi_s1g_ofdm_profile,
    wifi_s1g_occupied_subcarriers,
    wifi_s1g_subcarrier_frequency_hz,
    wifi_s1g_mcs_profile,
    wifi_s1g_bcc_su_long_gi_geometry,
)


def _expected_bpsc(mcs_index: Int) -> Int:
    return [1, 2, 2, 4, 4, 6, 6, 6, 8, 8, 1][mcs_index]


def _expected_rate_numerator(mcs_index: Int) -> Int:
    return [1, 1, 3, 1, 3, 2, 3, 5, 3, 5, 1][mcs_index]


def _expected_rate_denominator(mcs_index: Int) -> Int:
    return [2, 2, 4, 2, 4, 3, 4, 6, 4, 6, 4][mcs_index]


def _expected_ndbps(bandwidth_mhz: Int, mcs_index: Int) -> Int:
    if bandwidth_mhz == 1:
        return [12, 24, 36, 48, 72, 96, 108, 120, 144, 160, 6][
            mcs_index
        ]
    if bandwidth_mhz == 2:
        return [26, 52, 78, 104, 156, 208, 234, 260, 312][mcs_index]
    if bandwidth_mhz == 4:
        return [54, 108, 162, 216, 324, 432, 486, 540, 648, 720][
            mcs_index
        ]
    if bandwidth_mhz == 8:
        return [
            117, 234, 351, 468, 702, 936, 1053, 1170, 1404, 1560,
        ][mcs_index]
    return [
        234, 468, 702, 936, 1404, 1872, 2106, 2340, 2808, 3120,
    ][mcs_index]


def _append_interval(mut output: List[Int], first: Int, last: Int):
    for tone in range(first, last + 1):
        output.append(tone)


def _manual_occupied_tones(bandwidth_mhz: Int) -> List[Int]:
    var result = List[Int]()
    if bandwidth_mhz == 1:
        _append_interval(result, -13, -1)
        _append_interval(result, 1, 13)
    elif bandwidth_mhz == 2:
        _append_interval(result, -28, -1)
        _append_interval(result, 1, 28)
    elif bandwidth_mhz == 4:
        _append_interval(result, -58, -2)
        _append_interval(result, 2, 58)
    elif bandwidth_mhz == 8:
        _append_interval(result, -122, -2)
        _append_interval(result, 2, 122)
    else:
        _append_interval(result, -250, -130)
        _append_interval(result, -126, -6)
        _append_interval(result, 6, 126)
        _append_interval(result, 130, 250)
    return result^


def _assert_int_lists_equal(
    actual: Span[Int, ...], expected: Span[Int, ...]
) raises:
    assert_equal(len(actual), len(expected))
    for index in range(len(actual)):
        assert_equal(actual[index], expected[index])


def test_clause_23_timing_and_all_five_ofdm_rows_exact() raises:
    assert_equal(WIFI_S1G_SUBCARRIER_SPACING_HZ, 31_250)
    assert_equal(WIFI_S1G_FFT_PERIOD_NS, 32_000)
    assert_equal(WIFI_S1G_LONG_GI_NS, 8_000)
    assert_equal(WIFI_S1G_SHORT_GI_NS, 4_000)
    assert_equal(WIFI_S1G_LONG_SYMBOL_NS, 40_000)
    assert_equal(WIFI_S1G_SHORT_SYMBOL_NS, 36_000)
    assert_equal(WIFI_S1G_SERVICE_BITS, 8)
    assert_equal(WIFI_S1G_BCC_TAIL_BITS, 6)

    var bandwidths: List[Int] = [1, 2, 4, 8, 16]
    var fft_sizes: List[Int] = [32, 64, 128, 256, 512]
    var data_tones: List[Int] = [24, 52, 108, 234, 468]
    var pilot_tones: List[Int] = [2, 4, 6, 8, 16]
    var occupied_tones: List[Int] = [26, 56, 114, 242, 484]
    var highest_indices: List[Int] = [13, 28, 58, 122, 250]
    for row in range(len(bandwidths)):
        var profile = wifi_s1g_ofdm_profile(bandwidths[row])
        assert_equal(profile.bandwidth_mhz, bandwidths[row])
        assert_equal(profile.fft_size, fft_sizes[row])
        assert_equal(profile.data_subcarriers, data_tones[row])
        assert_equal(profile.pilot_subcarriers, pilot_tones[row])
        assert_equal(profile.occupied_subcarriers, occupied_tones[row])
        assert_equal(profile.highest_occupied_index, highest_indices[row])
        assert_equal(profile.subcarrier_spacing_hz, 31_250)
        assert_equal(profile.fft_period_ns, 32_000)
        assert_equal(profile.long_gi_ns, 8_000)
        assert_equal(profile.short_gi_ns, 4_000)
        assert_equal(profile.long_symbol_ns, 40_000)
        assert_equal(profile.short_symbol_ns, 36_000)


def test_all_occupied_tone_intervals_and_frequency_grid_exact() raises:
    var bandwidths: List[Int] = [1, 2, 4, 8, 16]
    for bandwidth in bandwidths:
        var actual = wifi_s1g_occupied_subcarriers(bandwidth)
        var expected = _manual_occupied_tones(bandwidth)
        _assert_int_lists_equal(Span(actual), Span(expected))
        for index in range(len(actual)):
            var expected_frequency = (
                915_000_000.0 + Float64(actual[index] * 31_250)
            )
            assert_equal(
                wifi_s1g_subcarrier_frequency_hz(
                    915_000_000.0, bandwidth, actual[index]
                ),
                expected_frequency,
            )


def test_complete_one_stream_mcs_rows_and_invalid_cells_exact() raises:
    var bandwidths: List[Int] = [1, 2, 4, 8, 16]
    var data_tones: List[Int] = [24, 52, 108, 234, 468]
    var pilot_tones: List[Int] = [2, 4, 6, 8, 16]
    for row in range(len(bandwidths)):
        for mcs_index in range(10):
            if bandwidths[row] == 2 and mcs_index == 9:
                continue
            var profile = wifi_s1g_mcs_profile(
                bandwidths[row], mcs_index
            )
            var bpsc = _expected_bpsc(mcs_index)
            var ndbps = _expected_ndbps(bandwidths[row], mcs_index)
            assert_equal(profile.bits_per_subcarrier, bpsc)
            assert_equal(
                profile.effective_code_rate_numerator,
                _expected_rate_numerator(mcs_index),
            )
            assert_equal(
                profile.effective_code_rate_denominator,
                _expected_rate_denominator(mcs_index),
            )
            assert_equal(profile.bcc_repetition_factor, 1)
            assert_equal(profile.data_subcarriers, data_tones[row])
            assert_equal(profile.pilot_subcarriers, pilot_tones[row])
            assert_equal(
                profile.coded_bits_per_symbol, data_tones[row] * bpsc
            )
            assert_equal(profile.data_bits_per_symbol, ndbps)
            assert_equal(profile.long_gi_data_rate_bps, ndbps * 25_000)

    var mcs10 = wifi_s1g_mcs_profile(1, 10)
    assert_equal(mcs10.bits_per_subcarrier, 1)
    assert_equal(mcs10.effective_code_rate_numerator, 1)
    assert_equal(mcs10.effective_code_rate_denominator, 4)
    assert_equal(mcs10.bcc_repetition_factor, 2)
    assert_equal(mcs10.coded_bits_per_symbol, 24)
    assert_equal(mcs10.data_bits_per_symbol, 6)
    assert_equal(mcs10.long_gi_data_rate_bps, 150_000)

    with assert_raises():
        _ = wifi_s1g_mcs_profile(2, 9)
    for bandwidth in [2, 4, 8, 16]:
        with assert_raises():
            _ = wifi_s1g_mcs_profile(bandwidth, 10)


def test_static_bcc_geometry_and_mcs10_max_duration_oracle() raises:
    assert_equal(WIFI_S1G_NON_MCS10_MAX_DATA_SYMBOLS, 511)
    assert_equal(WIFI_S1G_MCS10_MAX_PSDU_OCTETS, 511)
    assert_equal(WIFI_S1G_MAX_PSDU_OCTETS, 797_159)
    assert_equal(WIFI_S1G_MAX_PPDU_DURATION_NS, 27_920_000)
    assert_equal(WIFI_S1G_1M_PREAMBLE_NS, 560_000)
    assert_equal(WIFI_S1G_SHORT_PREAMBLE_NS, 240_000)

    var long_range = wifi_s1g_bcc_su_long_gi_geometry(
        WifiS1GBCCSUConfig(1, 10, 511)
    )
    assert_equal(long_range.data_bits_per_symbol, 6)
    assert_equal(long_range.data_bits_before_pad, 4102)
    assert_equal(long_range.data_symbols, 684)
    assert_equal(long_range.pad_bits, 2)
    assert_equal(long_range.preamble_duration_ns, 560_000)
    assert_equal(long_range.data_duration_ns, 27_360_000)
    assert_equal(long_range.ppdu_duration_ns, 27_920_000)
    assert_true(long_range.s1g_1m_format)

    var two_mhz = wifi_s1g_bcc_su_long_gi_geometry(
        WifiS1GBCCSUConfig(2, 0, 100)
    )
    assert_equal(two_mhz.data_bits_per_symbol, 26)
    assert_equal(two_mhz.data_bits_before_pad, 814)
    assert_equal(two_mhz.data_symbols, 32)
    assert_equal(two_mhz.pad_bits, 18)
    assert_equal(two_mhz.preamble_duration_ns, 240_000)
    assert_equal(two_mhz.data_duration_ns, 1_280_000)
    assert_equal(two_mhz.ppdu_duration_ns, 1_520_000)
    assert_true(not two_mhz.s1g_1m_format)

    var sixteen_mhz = wifi_s1g_bcc_su_long_gi_geometry(
        WifiS1GBCCSUConfig(16, 9, 1)
    )
    assert_equal(sixteen_mhz.data_bits_per_symbol, 3120)
    assert_equal(sixteen_mhz.data_bits_before_pad, 22)
    assert_equal(sixteen_mhz.data_symbols, 1)
    assert_equal(sixteen_mhz.pad_bits, 3098)
    assert_equal(sixteen_mhz.ppdu_duration_ns, 280_000)


def test_seeded_geometry_matches_independent_integer_oracle() raises:
    var bandwidths: List[Int] = [1, 2, 4, 8, 16]
    var seed = UInt64(0x80211A42024)
    for iteration in range(1021):
        seed = (
            seed * UInt64(6364136223846793005)
            + UInt64(1442695040888963407)
        )
        var bandwidth = bandwidths[Int(seed % UInt64(5))]
        var mcs_index = Int((seed >> 7) % UInt64(10))
        if bandwidth == 2 and mcs_index == 9:
            mcs_index = 8
        if bandwidth == 1 and (iteration % 17) == 0:
            mcs_index = 10
        var ndbps = _expected_ndbps(bandwidth, mcs_index)
        var mcs = wifi_s1g_mcs_profile(bandwidth, mcs_index)
        assert_equal(mcs.data_bits_per_symbol, ndbps)
        var max_octets = (
            511
            if mcs_index == 10
            else (
                WIFI_S1G_NON_MCS10_MAX_DATA_SYMBOLS * ndbps - 14
            ) // 8
        )
        var length = 1 + Int((seed >> 19) % UInt64(max_octets))
        var geometry = wifi_s1g_bcc_su_long_gi_geometry(
            WifiS1GBCCSUConfig(bandwidth, mcs_index, length)
        )

        var expected_bits = 8 * length + 8 + 6
        var expected_symbols = (expected_bits + ndbps - 1) // ndbps
        var expected_pad = expected_symbols * ndbps - expected_bits
        var expected_preamble = 560_000 if bandwidth == 1 else 240_000
        assert_equal(geometry.data_bits_per_symbol, ndbps)
        assert_equal(geometry.data_bits_before_pad, expected_bits)
        assert_equal(geometry.data_symbols, expected_symbols)
        assert_equal(geometry.pad_bits, expected_pad)
        assert_true(expected_pad >= 0 and expected_pad < ndbps)
        assert_equal(geometry.preamble_duration_ns, expected_preamble)
        assert_equal(
            geometry.data_duration_ns, expected_symbols * 40_000
        )
        assert_equal(
            geometry.ppdu_duration_ns,
            expected_preamble + expected_symbols * 40_000,
        )
        assert_true(geometry.ppdu_duration_ns <= 27_920_000)


def test_invalid_overflow_and_mutable_boundary_rejection() raises:
    for bandwidth in [0, -1, 3, 32]:
        with assert_raises():
            _ = wifi_s1g_ofdm_profile(bandwidth)
        with assert_raises():
            _ = wifi_s1g_occupied_subcarriers(bandwidth)
    with assert_raises():
        _ = wifi_s1g_mcs_profile(1, -1)
    with assert_raises():
        _ = wifi_s1g_mcs_profile(1, 11)
    with assert_raises():
        _ = WifiS1GBCCSUConfig(1, 0, 0)
    with assert_raises():
        _ = WifiS1GBCCSUConfig(1, 10, 512)
    with assert_raises():
        _ = WifiS1GBCCSUConfig(16, 9, Int.MAX)

    with assert_raises():
        _ = wifi_s1g_subcarrier_frequency_hz(915_000_000.0, 1, 0)
    with assert_raises():
        _ = wifi_s1g_subcarrier_frequency_hz(915_000_000.0, 4, 1)
    with assert_raises():
        _ = wifi_s1g_subcarrier_frequency_hz(915_000_000.0, 16, 127)

    var ofdm = WifiS1GOFDMProfile(8)
    ofdm.fft_size = 255
    with assert_raises():
        ofdm.validate()
    var mcs = WifiS1GMCSProfile(4, 7)
    mcs.data_bits_per_symbol = 541
    with assert_raises():
        mcs.validate()
    var config = WifiS1GBCCSUConfig(1, 10, 64)
    config.bandwidth_mhz = 2
    with assert_raises():
        _ = wifi_s1g_bcc_su_long_gi_geometry(config)
    config.bandwidth_mhz = 1
    config.psdu_length_octets = 512
    with assert_raises():
        _ = wifi_s1g_bcc_su_long_gi_geometry(config)


def test_nonfinite_and_extreme_finite_frequency_boundaries() raises:
    with assert_raises():
        _ = wifi_s1g_subcarrier_frequency_hz(
            nan[DType.float64](), 1, 1
        )
    with assert_raises():
        _ = wifi_s1g_subcarrier_frequency_hz(
            inf[DType.float64](), 1, 1
        )
    with assert_raises():
        _ = wifi_s1g_subcarrier_frequency_hz(
            -inf[DType.float64](), 1, 1
        )
    with assert_raises():
        _ = wifi_s1g_subcarrier_frequency_hz(-0.0, 1, 1)
    with assert_raises():
        _ = wifi_s1g_subcarrier_frequency_hz(
            2.2250738585072014e-308, 1, -1
        )

    assert_equal(
        wifi_s1g_subcarrier_frequency_hz(Float64.MAX_FINITE, 16, 250),
        Float64.MAX_FINITE,
    )
    assert_equal(
        wifi_s1g_subcarrier_frequency_hz(
            2.2250738585072014e-308, 1, 1
        ),
        31_250.0,
    )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
