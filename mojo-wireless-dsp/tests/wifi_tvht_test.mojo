"""Independent exact evidence for bounded Clause-22 TVHT PHY arithmetic.

Literal Table-22 tone intervals, pilot offsets, MCS columns, interleaver rows,
and PPDU field durations are transcribed independently of production control
flow.  A fixed-seed state space additionally compares channel, MCS, and PPDU
results against separate integer/half-integer formulas.  All evidence is
discrete or exactly representable binary arithmetic, so tolerance is exact.
"""

from std.collections import Span
from std.testing import assert_equal, assert_raises, assert_true, TestSuite
from std.utils.numerics import inf, nan
from wireless_dsp.wireless.wifi.tvht import (
    WIFI_TVHT_MODE_1,
    WIFI_TVHT_MODE_2C,
    WIFI_TVHT_MODE_2N,
    WIFI_TVHT_MODE_4C,
    WIFI_TVHT_MODE_4N,
    WIFI_TVHT_LONG_GI,
    WIFI_TVHT_SHORT_GI,
    WIFI_TVHT_DATA_SUBCARRIERS_PER_BCU,
    WIFI_TVHT_PILOT_SUBCARRIERS_PER_BCU,
    WIFI_TVHT_OCCUPIED_SUBCARRIERS_PER_BCU,
    WIFI_TVHT_HIGHEST_LOCAL_SUBCARRIER,
    WIFI_TVHT_NUMBER_OF_ENCODERS,
    WIFI_TVHT_MAX_PPDU_DURATION_NS,
    WIFI_TVHT_MAX_EXACT_CHANNEL_START_MHZ,
    WifiTVHTModeConfig,
    WifiTVHTChannelConfig,
    WifiTVHTMCSConfig,
    WifiTVHTPPDUConfig,
    wifi_tvht_channel_plan,
    wifi_tvht_ofdm_profile,
    wifi_tvht_occupied_subcarriers,
    wifi_tvht_pilot_subcarriers,
    wifi_tvht_sig_a_bandwidth_bits,
    wifi_tvht_mcs_profile,
    wifi_tvht_ppdu_geometry,
)


def _modes() -> List[Int]:
    return [
        WIFI_TVHT_MODE_1,
        WIFI_TVHT_MODE_2C,
        WIFI_TVHT_MODE_2N,
        WIFI_TVHT_MODE_4C,
        WIFI_TVHT_MODE_4N,
    ]


def _literal_bcu_count(mode: Int) -> Int:
    if mode == WIFI_TVHT_MODE_1:
        return 1
    if mode == WIFI_TVHT_MODE_2C or mode == WIFI_TVHT_MODE_2N:
        return 2
    return 4


def _literal_segment_count(mode: Int) -> Int:
    if mode == WIFI_TVHT_MODE_2N or mode == WIFI_TVHT_MODE_4N:
        return 2
    return 1


def _literal_units_per_segment(mode: Int) -> Int:
    if mode == WIFI_TVHT_MODE_4C:
        return 4
    if mode == WIFI_TVHT_MODE_2C or mode == WIFI_TVHT_MODE_4N:
        return 2
    return 1


def _append_interval(mut output: List[Int], first: Int, last: Int):
    for value in range(first, last + 1):
        output.append(value)


def _literal_occupied_tones(
    bcu_bandwidth_mhz: Int, mode: Int
) -> List[Int]:
    var result = List[Int]()
    var units = _literal_units_per_segment(mode)
    if units == 1:
        _append_interval(result, -58, -2)
        _append_interval(result, 2, 58)
        return result^
    if units == 2 and bcu_bandwidth_mhz != 7:
        _append_interval(result, -130, -74)
        _append_interval(result, -70, -14)
        _append_interval(result, 14, 70)
        _append_interval(result, 74, 130)
        return result^
    if units == 2:
        _append_interval(result, -142, -86)
        _append_interval(result, -82, -26)
        _append_interval(result, 26, 82)
        _append_interval(result, 86, 142)
        return result^
    if bcu_bandwidth_mhz != 7:
        _append_interval(result, -274, -218)
        _append_interval(result, -214, -158)
        _append_interval(result, -130, -74)
        _append_interval(result, -70, -14)
        _append_interval(result, 14, 70)
        _append_interval(result, 74, 130)
        _append_interval(result, 158, 214)
        _append_interval(result, 218, 274)
        return result^
    _append_interval(result, -310, -254)
    _append_interval(result, -250, -194)
    _append_interval(result, -142, -86)
    _append_interval(result, -82, -26)
    _append_interval(result, 26, 82)
    _append_interval(result, 86, 142)
    _append_interval(result, 194, 250)
    _append_interval(result, 254, 310)
    return result^


def _literal_pilot_tones(
    bcu_bandwidth_mhz: Int, mode: Int
) -> List[Int]:
    var local: List[Int] = [-53, -25, -11, 11, 25, 53]
    var centers = List[Int]()
    var units = _literal_units_per_segment(mode)
    if units == 1:
        centers.append(0)
    elif units == 2 and bcu_bandwidth_mhz == 7:
        centers.extend([-84, 84])
    elif units == 2:
        centers.extend([-72, 72])
    elif bcu_bandwidth_mhz == 7:
        centers.extend([-252, -84, 84, 252])
    else:
        centers.extend([-216, -72, 72, 216])
    var result = List[Int](capacity=6 * units)
    for center in centers:
        for pilot in local:
            result.append(center + pilot)
    return result^


def _assert_int_lists_equal(
    actual: Span[Int, ...], expected: Span[Int, ...]
) raises:
    assert_equal(len(actual), len(expected))
    for index in range(len(actual)):
        assert_equal(actual[index], expected[index])


def _contains(values: Span[Int, ...], target: Int) -> Bool:
    for index in range(len(values)):
        if values[index] == target:
            return True
    return False


def _literal_mcs_bpsc(mcs_index: Int) -> Int:
    return [1, 2, 2, 4, 4, 6, 6, 6, 8, 8][mcs_index]


def _literal_mcs_rate_numerator(mcs_index: Int) -> Int:
    return [1, 1, 3, 1, 3, 2, 3, 5, 3, 5][mcs_index]


def _literal_mcs_rate_denominator(mcs_index: Int) -> Int:
    return [2, 2, 4, 2, 4, 3, 4, 6, 4, 6][mcs_index]


def _literal_one_bcu_one_stream_ncbps(mcs_index: Int) -> Int:
    return [108, 216, 216, 432, 432, 648, 648, 648, 864, 864][
        mcs_index
    ]


def _literal_one_bcu_one_stream_ndbps(mcs_index: Int) -> Int:
    return [54, 108, 162, 216, 324, 432, 486, 540, 648, 720][
        mcs_index
    ]


def _literal_ltf_count(space_time_streams: Int) -> Int:
    if space_time_streams == 1:
        return 1
    if space_time_streams == 2:
        return 2
    return 4


def _literal_ppdu_durations(
    bcu_bandwidth_mhz: Int,
    space_time_streams: Int,
    data_symbols: Int,
    guard_interval: Int,
) -> Tuple[Int, Int, Int, Int, Int, Int]:
    var long_field = 45_000 if bcu_bandwidth_mhz == 8 else 60_000
    var short_field = 22_500 if bcu_bandwidth_mhz == 8 else 30_000
    var fixed = 202_500 if bcu_bandwidth_mhz == 8 else 270_000
    var data_symbol: Int
    if bcu_bandwidth_mhz == 8:
        data_symbol = (
            22_500 if guard_interval == WIFI_TVHT_LONG_GI else 20_250
        )
    else:
        data_symbol = (
            30_000 if guard_interval == WIFI_TVHT_LONG_GI else 27_000
        )
    var preamble = fixed + _literal_ltf_count(space_time_streams) * short_field
    var data = data_symbols * data_symbol
    return (
        long_field,
        short_field,
        data_symbol,
        preamble,
        data,
        preamble + data,
    )


def _channel_config(
    bcu_bandwidth_mhz: Int, mode: Int, start_mhz: Float64 = 100.0
) raises -> WifiTVHTChannelConfig:
    if mode == WIFI_TVHT_MODE_1:
        return WifiTVHTChannelConfig(
            bcu_bandwidth_mhz, mode, 10, 0, 10, start_mhz
        )
    if mode == WIFI_TVHT_MODE_2C:
        return WifiTVHTChannelConfig(
            bcu_bandwidth_mhz, mode, 10, 0, 11, start_mhz
        )
    if mode == WIFI_TVHT_MODE_2N:
        return WifiTVHTChannelConfig(
            bcu_bandwidth_mhz, mode, 10, 20, 10, start_mhz
        )
    if mode == WIFI_TVHT_MODE_4C:
        return WifiTVHTChannelConfig(
            bcu_bandwidth_mhz, mode, 10, 0, 13, start_mhz
        )
    return WifiTVHTChannelConfig(
        bcu_bandwidth_mhz, mode, 10, 20, 11, start_mhz
    )


def test_channelization_and_all_bonding_modes_static_exact() raises:
    var modes = _modes()
    for bcu_bandwidth_mhz in [6, 7, 8]:
        for mode in modes:
            var config = _channel_config(bcu_bandwidth_mhz, mode)
            var plan = wifi_tvht_channel_plan(config)
            var bcu_count = _literal_bcu_count(mode)
            var segment_count = _literal_segment_count(mode)
            var correction = 0.0
            if mode == WIFI_TVHT_MODE_2C or mode == WIFI_TVHT_MODE_4N:
                correction = 0.5 * Float64(bcu_bandwidth_mhz)
            elif mode == WIFI_TVHT_MODE_4C:
                correction = 1.5 * Float64(bcu_bandwidth_mhz)
            assert_equal(plan.bcu_bandwidth_mhz, bcu_bandwidth_mhz)
            assert_equal(plan.mode, mode)
            assert_equal(plan.bcu_count, bcu_count)
            assert_equal(plan.segment_count, segment_count)
            assert_equal(plan.bcus_per_segment, bcu_count // segment_count)
            assert_equal(plan.contiguous, segment_count == 1)
            assert_equal(
                plan.nominal_aggregate_bandwidth_mhz,
                bcu_bandwidth_mhz * bcu_count,
            )
            assert_equal(
                plan.segment0_center_frequency_mhz,
                100.0 + Float64(10 * bcu_bandwidth_mhz) + correction,
            )
            if segment_count == 2:
                assert_equal(
                    plan.segment1_center_frequency_mhz,
                    100.0
                    + Float64(20 * bcu_bandwidth_mhz)
                    + correction,
                )
            else:
                assert_equal(plan.segment1_center_frequency_mhz, 0.0)
            assert_equal(
                plan.primary_center_frequency_mhz,
                100.0
                + Float64(config.primary_index * bcu_bandwidth_mhz),
            )

    # Published U.S. 12 MHz example: start 389, lowest index 15,
    # primary index 16 gives segment center 482 and primary center 485 MHz.
    var published = wifi_tvht_channel_plan(
        WifiTVHTChannelConfig(6, WIFI_TVHT_MODE_2C, 15, 0, 16, 389.0)
    )
    assert_equal(published.segment0_center_frequency_mhz, 482.0)
    assert_equal(published.primary_center_frequency_mhz, 485.0)

    # Exact legal channel-index endpoints and maximum contiguous starts.
    var index_one = wifi_tvht_channel_plan(
        WifiTVHTChannelConfig(6, WIFI_TVHT_MODE_1, 1, 0, 1, 45.0)
    )
    assert_equal(index_one.segment0_center_frequency_mhz, 51.0)
    assert_equal(index_one.primary_center_frequency_mhz, 51.0)
    var index_two_hundred = wifi_tvht_channel_plan(
        WifiTVHTChannelConfig(8, WIFI_TVHT_MODE_1, 200, 0, 200, 45.5)
    )
    assert_equal(index_two_hundred.segment0_center_frequency_mhz, 1645.5)
    assert_equal(index_two_hundred.primary_center_frequency_mhz, 1645.5)
    var two_contiguous_end = wifi_tvht_channel_plan(
        WifiTVHTChannelConfig(6, WIFI_TVHT_MODE_2C, 199, 0, 200, 45.0)
    )
    assert_equal(two_contiguous_end.segment0_center_frequency_mhz, 1242.0)
    assert_equal(two_contiguous_end.primary_center_frequency_mhz, 1245.0)
    var four_contiguous_end = wifi_tvht_channel_plan(
        WifiTVHTChannelConfig(7, WIFI_TVHT_MODE_4C, 197, 0, 200, 45.0)
    )
    assert_equal(four_contiguous_end.segment0_center_frequency_mhz, 1434.5)
    assert_equal(four_contiguous_end.primary_center_frequency_mhz, 1445.0)

    # Noncontiguous segment numbering follows the primary-containing segment,
    # not ascending frequency order.  This exercises the reverse-order branch.
    var reversed_four_noncontiguous = wifi_tvht_channel_plan(
        WifiTVHTChannelConfig(8, WIFI_TVHT_MODE_4N, 199, 1, 200, 45.5)
    )
    assert_equal(
        reversed_four_noncontiguous.segment0_center_frequency_mhz, 1641.5
    )
    assert_equal(
        reversed_four_noncontiguous.segment1_center_frequency_mhz, 57.5
    )
    assert_true(
        reversed_four_noncontiguous.segment1_center_frequency_mhz
        < reversed_four_noncontiguous.segment0_center_frequency_mhz
    )


def test_ofdm_tone_pilot_and_sig_a_tables_exhaustive_exact() raises:
    assert_equal(WIFI_TVHT_DATA_SUBCARRIERS_PER_BCU, 108)
    assert_equal(WIFI_TVHT_PILOT_SUBCARRIERS_PER_BCU, 6)
    assert_equal(WIFI_TVHT_OCCUPIED_SUBCARRIERS_PER_BCU, 114)
    assert_equal(WIFI_TVHT_HIGHEST_LOCAL_SUBCARRIER, 58)

    var modes = _modes()
    for bcu_bandwidth_mhz in [6, 7, 8]:
        for mode in modes:
            var config = WifiTVHTModeConfig(bcu_bandwidth_mhz, mode)
            var profile = wifi_tvht_ofdm_profile(config)
            var bcu_count = _literal_bcu_count(mode)
            var segment_count = _literal_segment_count(mode)
            var units = _literal_units_per_segment(mode)
            assert_equal(profile.bcu_count, bcu_count)
            assert_equal(profile.segment_count, segment_count)
            assert_equal(profile.bcus_per_segment, units)
            assert_equal(
                profile.dft_size_per_bcu,
                168 if bcu_bandwidth_mhz == 7 else 144,
            )
            assert_equal(
                profile.dft_size_per_segment,
                (168 if bcu_bandwidth_mhz == 7 else 144) * units,
            )
            assert_equal(
                profile.sample_rate_per_segment_hz,
                bcu_bandwidth_mhz * 1_000_000 * units,
            )
            assert_equal(profile.data_subcarriers, 108 * bcu_count)
            assert_equal(profile.pilot_subcarriers, 6 * bcu_count)
            assert_equal(profile.occupied_subcarriers, 114 * bcu_count)
            var expected_dft_ns = 18_000 if bcu_bandwidth_mhz == 8 else 24_000
            assert_equal(profile.dft_period_ns, expected_dft_ns)
            assert_equal(profile.long_guard_interval_ns, expected_dft_ns // 4)
            assert_equal(profile.short_guard_interval_ns, expected_dft_ns // 8)
            assert_equal(
                profile.long_symbol_duration_ns,
                expected_dft_ns + expected_dft_ns // 4,
            )
            assert_equal(
                profile.short_symbol_duration_ns,
                expected_dft_ns + expected_dft_ns // 8,
            )

            var expected_tones = _literal_occupied_tones(
                bcu_bandwidth_mhz, mode
            )
            var expected_pilots = _literal_pilot_tones(
                bcu_bandwidth_mhz, mode
            )
            for segment in range(segment_count):
                var tones = wifi_tvht_occupied_subcarriers(
                    config, segment
                )
                var pilots = wifi_tvht_pilot_subcarriers(config, segment)
                _assert_int_lists_equal(Span(tones), Span(expected_tones))
                _assert_int_lists_equal(Span(pilots), Span(expected_pilots))
                assert_equal(len(tones), 114 * units)
                assert_equal(len(pilots), 6 * units)
                for pilot in pilots:
                    assert_true(_contains(Span(tones), pilot))
                assert_equal(len(tones) - len(pilots), 108 * units)

            var bits = wifi_tvht_sig_a_bandwidth_bits(config)
            if mode == WIFI_TVHT_MODE_1:
                assert_equal(bits, 1)
            elif mode == WIFI_TVHT_MODE_2C or mode == WIFI_TVHT_MODE_2N:
                assert_equal(bits, 2)
            else:
                assert_equal(bits, 3)


def test_all_600_mcs_configurations_over_120_normative_rows_exact() raises:
    """Check 600 mode-expanded configurations over 120 normative rows."""
    assert_equal(WIFI_TVHT_NUMBER_OF_ENCODERS, 1)
    var configuration_count = 0
    var normative_table_row_count = 3 * 4 * 10
    assert_equal(normative_table_row_count, 120)
    for bcu_bandwidth_mhz in [6, 7, 8]:
        for mode in _modes():
            var bcu_count = _literal_bcu_count(mode)
            var columns = 18
            var row_multiplier = 6
            var rotation = 29
            var distance = 6
            if bcu_count == 2:
                columns = 27
                row_multiplier = 8
                rotation = 46
                distance = 8
            elif bcu_count == 4:
                columns = 48
                row_multiplier = 9
                rotation = 78
                distance = 9
            for spatial_streams in range(1, 5):
                for mcs_index in range(10):
                    var config = WifiTVHTMCSConfig(
                        bcu_bandwidth_mhz,
                        mode,
                        mcs_index,
                        spatial_streams,
                    )
                    var profile = wifi_tvht_mcs_profile(config)
                    var scale = bcu_count * spatial_streams
                    var bpsc = _literal_mcs_bpsc(mcs_index)
                    assert_equal(profile.bits_per_subcarrier, bpsc)
                    assert_equal(
                        profile.code_rate_numerator,
                        _literal_mcs_rate_numerator(mcs_index),
                    )
                    assert_equal(
                        profile.code_rate_denominator,
                        _literal_mcs_rate_denominator(mcs_index),
                    )
                    assert_equal(profile.data_subcarriers, 108 * bcu_count)
                    assert_equal(profile.pilot_subcarriers, 6 * bcu_count)
                    assert_equal(
                        profile.coded_bits_per_symbol,
                        _literal_one_bcu_one_stream_ncbps(mcs_index) * scale,
                    )
                    assert_equal(
                        profile.data_bits_per_symbol,
                        _literal_one_bcu_one_stream_ndbps(mcs_index) * scale,
                    )
                    assert_equal(profile.number_of_encoders, 1)
                    assert_equal(profile.bcc_interleaver_columns, columns)
                    assert_equal(
                        profile.bcc_interleaver_rows,
                        row_multiplier * bpsc,
                    )
                    assert_equal(profile.bcc_interleaver_rotation, rotation)
                    assert_equal(profile.ldpc_tone_mapping_distance, distance)
                    assert_equal(
                        profile.mandatory_base_profile,
                        mode == WIFI_TVHT_MODE_1
                        and spatial_streams == 1
                        and mcs_index <= 7,
                    )
                    configuration_count += 1
    assert_equal(configuration_count, 600)


def _assert_ppdu_matches_literal(config: WifiTVHTPPDUConfig) raises:
    var geometry = wifi_tvht_ppdu_geometry(config)
    var (
        long_field,
        short_field,
        data_symbol,
        preamble,
        data,
        total,
    ) = _literal_ppdu_durations(
        config.bcu_bandwidth_mhz,
        config.space_time_streams,
        config.data_symbols,
        config.guard_interval,
    )
    assert_equal(
        geometry.tvht_ltf_symbols,
        _literal_ltf_count(config.space_time_streams),
    )
    assert_equal(geometry.l_stf_duration_ns, long_field)
    assert_equal(geometry.l_ltf_duration_ns, long_field)
    assert_equal(geometry.l_sig_duration_ns, short_field)
    assert_equal(geometry.tvht_sig_a_duration_ns, long_field)
    assert_equal(geometry.tvht_stf_duration_ns, short_field)
    assert_equal(geometry.tvht_ltf_symbol_duration_ns, short_field)
    assert_equal(
        geometry.tvht_ltf_duration_ns,
        _literal_ltf_count(config.space_time_streams) * short_field,
    )
    assert_equal(geometry.tvht_sig_b_duration_ns, short_field)
    assert_equal(geometry.data_symbol_duration_ns, data_symbol)
    assert_equal(geometry.preamble_duration_ns, preamble)
    assert_equal(geometry.data_duration_ns, data)
    assert_equal(geometry.ppdu_duration_ns, total)


def test_ppdu_field_durations_and_twenty_ms_boundary_exact() raises:
    for bcu_bandwidth_mhz in [6, 7, 8]:
        for mode in _modes():
            for space_time_streams in range(1, 5):
                for guard_interval in [
                    WIFI_TVHT_LONG_GI, WIFI_TVHT_SHORT_GI
                ]:
                    _assert_ppdu_matches_literal(
                        WifiTVHTPPDUConfig(
                            bcu_bandwidth_mhz,
                            mode,
                            space_time_streams,
                            1 + 17 * space_time_streams + mode,
                            guard_interval,
                        )
                    )

    var one = wifi_tvht_ppdu_geometry(
        WifiTVHTPPDUConfig(6, WIFI_TVHT_MODE_1, 1, 1, WIFI_TVHT_LONG_GI)
    )
    assert_equal(one.preamble_duration_ns, 300_000)
    assert_equal(one.ppdu_duration_ns, 330_000)

    # Maximal legal integer symbol counts immediately below the 20 ms cap.
    for bcu_bandwidth_mhz in [6, 8]:
        for space_time_streams in [1, 2, 4]:
            for guard_interval in [
                WIFI_TVHT_LONG_GI, WIFI_TVHT_SHORT_GI
            ]:
                var (_, _, symbol_ns, preamble_ns, _, _) = (
                    _literal_ppdu_durations(
                        bcu_bandwidth_mhz,
                        space_time_streams,
                        1,
                        guard_interval,
                    )
                )
                var maximum_symbols = (
                    WIFI_TVHT_MAX_PPDU_DURATION_NS - preamble_ns
                ) // symbol_ns
                var maximum = WifiTVHTPPDUConfig(
                    bcu_bandwidth_mhz,
                    WIFI_TVHT_MODE_4C,
                    space_time_streams,
                    maximum_symbols,
                    guard_interval,
                )
                var geometry = wifi_tvht_ppdu_geometry(maximum)
                assert_true(
                    geometry.ppdu_duration_ns
                    <= WIFI_TVHT_MAX_PPDU_DURATION_NS
                )
                with assert_raises():
                    _ = WifiTVHTPPDUConfig(
                        bcu_bandwidth_mhz,
                        WIFI_TVHT_MODE_4C,
                        space_time_streams,
                        maximum_symbols + 1,
                        guard_interval,
                    )


def test_seeded_differential_properties_exact() raises:
    var seed = UInt64(0x80211_2024_54564854)
    var modes = _modes()
    var bandwidths: List[Int] = [6, 7, 8]
    for iteration in range(1021):
        seed = (
            seed * UInt64(6364136223846793005)
            + UInt64(1442695040888963407)
        )
        var bcu = bandwidths[Int(seed % UInt64(3))]
        var mode = modes[Int((seed >> 7) % UInt64(5))]
        var nss = 1 + Int((seed >> 13) % UInt64(4))
        var mcs_index = Int((seed >> 19) % UInt64(10))
        var mode_config = WifiTVHTModeConfig(bcu, mode)
        var ofdm = wifi_tvht_ofdm_profile(mode_config)
        assert_equal(ofdm.bcu_count, _literal_bcu_count(mode))
        assert_equal(
            ofdm.dft_size_per_bcu, 168 if bcu == 7 else 144
        )
        var segment = (
            Int((seed >> 25) & UInt64(1))
            if _literal_segment_count(mode) == 2
            else 0
        )
        var tones = wifi_tvht_occupied_subcarriers(
            mode_config, segment
        )
        var pilots = wifi_tvht_pilot_subcarriers(mode_config, segment)
        var expected_tones = _literal_occupied_tones(bcu, mode)
        var expected_pilots = _literal_pilot_tones(bcu, mode)
        _assert_int_lists_equal(Span(tones), Span(expected_tones))
        _assert_int_lists_equal(Span(pilots), Span(expected_pilots))
        var sig_bits = wifi_tvht_sig_a_bandwidth_bits(mode_config)
        assert_equal(
            sig_bits,
            1
            if mode == WIFI_TVHT_MODE_1
            else (
                2
                if mode == WIFI_TVHT_MODE_2C
                or mode == WIFI_TVHT_MODE_2N
                else 3
            ),
        )
        var mcs = wifi_tvht_mcs_profile(
            WifiTVHTMCSConfig(bcu, mode, mcs_index, nss)
        )
        var scale = _literal_bcu_count(mode) * nss
        assert_equal(
            mcs.coded_bits_per_symbol,
            _literal_one_bcu_one_stream_ncbps(mcs_index) * scale,
        )
        assert_equal(
            mcs.data_bits_per_symbol,
            _literal_one_bcu_one_stream_ndbps(mcs_index) * scale,
        )

        var guard_interval = (
            WIFI_TVHT_LONG_GI
            if ((seed >> 29) & UInt64(1)) == 0
            else WIFI_TVHT_SHORT_GI
        )
        var data_symbols = 1 + Int((seed >> 31) % UInt64(400))
        var ppdu_config = WifiTVHTPPDUConfig(
            bcu, mode, nss, data_symbols, guard_interval
        )
        _assert_ppdu_matches_literal(ppdu_config)

        var start = 45.0 + 0.5 * Float64(Int(seed % UInt64(2000)))
        var channel = _channel_config(bcu, mode, start)
        var plan = wifi_tvht_channel_plan(channel)
        var correction = 0.0
        if mode == WIFI_TVHT_MODE_2C or mode == WIFI_TVHT_MODE_4N:
            correction = 0.5 * Float64(bcu)
        elif mode == WIFI_TVHT_MODE_4C:
            correction = 1.5 * Float64(bcu)
        assert_equal(
            plan.segment0_center_frequency_mhz,
            start + Float64(10 * bcu) + correction,
        )
        assert_equal(
            plan.primary_center_frequency_mhz,
            start + Float64(channel.primary_index * bcu),
        )
        assert_equal(iteration >= 0, True)


def test_public_mutation_nonfinite_overflow_and_index_edges() raises:
    for invalid_bcu in [Int.MIN, -1, 0, 5, 9, Int.MAX]:
        with assert_raises():
            _ = WifiTVHTModeConfig(invalid_bcu, WIFI_TVHT_MODE_1)
    for invalid_mode in [Int.MIN, -1, 5, Int.MAX]:
        with assert_raises():
            _ = WifiTVHTModeConfig(6, invalid_mode)

    var mode_config = WifiTVHTModeConfig(6, WIFI_TVHT_MODE_1)
    mode_config.bcu_bandwidth_mhz = 20
    with assert_raises():
        _ = wifi_tvht_ofdm_profile(mode_config)
    mode_config.bcu_bandwidth_mhz = 6
    mode_config.mode = Int.MAX
    with assert_raises():
        _ = wifi_tvht_occupied_subcarriers(mode_config, 0)
    with assert_raises():
        _ = wifi_tvht_pilot_subcarriers(mode_config, 0)
    with assert_raises():
        _ = wifi_tvht_sig_a_bandwidth_bits(mode_config)

    var valid_mode = WifiTVHTModeConfig(7, WIFI_TVHT_MODE_2N)
    for invalid_segment in [Int.MIN, -1, 2, Int.MAX]:
        with assert_raises():
            _ = wifi_tvht_occupied_subcarriers(
                valid_mode, invalid_segment
            )
        with assert_raises():
            _ = wifi_tvht_pilot_subcarriers(valid_mode, invalid_segment)

    for invalid_index in [Int.MIN, -1, 0, 201, Int.MAX]:
        with assert_raises():
            _ = WifiTVHTChannelConfig(
                6, WIFI_TVHT_MODE_1, invalid_index, 0, 1, 45.0
            )
    with assert_raises():
        _ = WifiTVHTChannelConfig(
            6, WIFI_TVHT_MODE_1, 1, 2, 1, 45.0
        )
    with assert_raises():
        _ = WifiTVHTChannelConfig(
            6, WIFI_TVHT_MODE_2C, 200, 0, 200, 45.0
        )
    with assert_raises():
        _ = WifiTVHTChannelConfig(
            6, WIFI_TVHT_MODE_4C, 198, 0, 198, 45.0
        )
    with assert_raises():
        _ = WifiTVHTChannelConfig(
            6, WIFI_TVHT_MODE_2N, 10, 10, 10, 45.0
        )
    with assert_raises():
        _ = WifiTVHTChannelConfig(
            6, WIFI_TVHT_MODE_4N, 10, 12, 10, 45.0
        )
    with assert_raises():
        _ = WifiTVHTChannelConfig(
            6, WIFI_TVHT_MODE_4N, 10, 20, 12, 45.0
        )

    for nonfinite in [
        nan[DType.float64](),
        inf[DType.float64](),
        -inf[DType.float64](),
        Float64.MAX_FINITE,
    ]:
        with assert_raises():
            _ = WifiTVHTChannelConfig(
                8, WIFI_TVHT_MODE_1, 1, 0, 1, nonfinite
            )
    with assert_raises():
        _ = WifiTVHTChannelConfig(
            8, WIFI_TVHT_MODE_1, 1, 0, 1, -0.0
        )
    for off_grid in [
        0.1,
        5.0e-324,
        WIFI_TVHT_MAX_EXACT_CHANNEL_START_MHZ - 0.25,
    ]:
        with assert_raises():
            _ = WifiTVHTChannelConfig(
                8, WIFI_TVHT_MODE_1, 1, 0, 1, off_grid
            )

    var extreme = wifi_tvht_channel_plan(
        WifiTVHTChannelConfig(
            8,
            WIFI_TVHT_MODE_1,
            1,
            0,
            1,
            WIFI_TVHT_MAX_EXACT_CHANNEL_START_MHZ,
        )
    )
    assert_equal(
        extreme.primary_center_frequency_mhz,
        WIFI_TVHT_MAX_EXACT_CHANNEL_START_MHZ + 8.0,
    )

    var mutable_channel = _channel_config(6, WIFI_TVHT_MODE_4N)
    mutable_channel.center_index1 = 12
    with assert_raises():
        _ = wifi_tvht_channel_plan(mutable_channel)
    mutable_channel.center_index1 = 20
    mutable_channel.channel_start_frequency_mhz = 0.1
    with assert_raises():
        _ = wifi_tvht_channel_plan(mutable_channel)
    mutable_channel.channel_start_frequency_mhz = Float64.MAX_FINITE
    with assert_raises():
        _ = wifi_tvht_channel_plan(mutable_channel)

    for invalid_mcs in [Int.MIN, -1, 10, Int.MAX]:
        with assert_raises():
            _ = WifiTVHTMCSConfig(6, WIFI_TVHT_MODE_1, invalid_mcs, 1)
    for invalid_nss in [Int.MIN, -1, 0, 5, Int.MAX]:
        with assert_raises():
            _ = WifiTVHTMCSConfig(6, WIFI_TVHT_MODE_1, 0, invalid_nss)
    var mutable_mcs = WifiTVHTMCSConfig(6, WIFI_TVHT_MODE_1, 7, 1)
    mutable_mcs.mcs_index = 10
    with assert_raises():
        _ = wifi_tvht_mcs_profile(mutable_mcs)
    mutable_mcs.mcs_index = 7
    mutable_mcs.spatial_streams = Int.MAX
    with assert_raises():
        _ = wifi_tvht_mcs_profile(mutable_mcs)

    for invalid_gi in [Int.MIN, -1, 2, Int.MAX]:
        with assert_raises():
            _ = WifiTVHTPPDUConfig(
                6, WIFI_TVHT_MODE_1, 1, 1, invalid_gi
            )
    for invalid_symbols in [Int.MIN, -1, 0, Int.MAX]:
        with assert_raises():
            _ = WifiTVHTPPDUConfig(
                6,
                WIFI_TVHT_MODE_1,
                1,
                invalid_symbols,
                WIFI_TVHT_LONG_GI,
            )
    var mutable_ppdu = WifiTVHTPPDUConfig(
        8, WIFI_TVHT_MODE_1, 1, 1, WIFI_TVHT_SHORT_GI
    )
    mutable_ppdu.data_symbols = Int.MAX
    with assert_raises():
        _ = wifi_tvht_ppdu_geometry(mutable_ppdu)
    mutable_ppdu.data_symbols = 1
    mutable_ppdu.space_time_streams = 5
    with assert_raises():
        _ = wifi_tvht_ppdu_geometry(mutable_ppdu)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
