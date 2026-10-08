"""Independent exact evidence for bounded Clause-28 EDMG OFDM geometry.

Four literal signal-parameter rows and 26 literal channel-center rows are
transcribed independently from the official adopted TGay table text.  Grid
packing uses a separate two-interval oracle rather than the production tone
branch.  Exact comparisons, full legal domains, a fixed-seed property space,
and adversarial mutable/shape/Int/nonfinite cases provide CPU-only evidence.
"""

from std.collections import Span
from std.testing import assert_equal, assert_raises, TestSuite
from std.utils.numerics import inf, nan
from wireless_dsp.core import Complex64
from wireless_dsp.wireless.wifi.edmg import (
    WIFI_EDMG_MIN_CONTIGUOUS_CHANNELS,
    WIFI_EDMG_MAX_CONTIGUOUS_CHANNELS,
    WIFI_EDMG_OFDM_GEOMETRY_ROW_COUNT,
    WIFI_EDMG_OFDM_CHANNEL_ROW_COUNT,
    WIFI_EDMG_OFDM_SUBCARRIER_SPACING_HZ,
    WIFI_EDMG_OFDM_DC_SUBCARRIERS,
    WIFI_EDMG_GI_SHORT,
    WIFI_EDMG_GI_NORMAL,
    WIFI_EDMG_GI_LONG,
    WifiEDMGOfdmConfig,
    wifi_edmg_ofdm_channel_numbers,
    wifi_edmg_ofdm_profile,
    wifi_edmg_ofdm_channel_center_frequency_hz,
    wifi_edmg_ofdm_symbol_samples,
    wifi_edmg_ofdm_pack_occupied_grid,
    wifi_edmg_ofdm_unpack_occupied_grid,
)


def _literal_data_subcarriers() -> List[Int]:
    return [336, 734, 1134, 1532]


def _literal_pilot_subcarriers() -> List[Int]:
    return [16, 36, 56, 76]


def _literal_total_subcarriers() -> List[Int]:
    return [355, 773, 1193, 1611]


def _literal_half_occupied() -> List[Int]:
    return [177, 386, 596, 805]


def _literal_sample_rates_hz() -> List[Int]:
    return [
        2_640_000_000,
        5_280_000_000,
        7_920_000_000,
        10_560_000_000,
    ]


def _literal_dft_sizes() -> List[Int]:
    return [512, 1024, 1536, 2048]


def _literal_channel_ncbs() -> List[Int]:
    return [
        1, 1, 1, 1, 1, 1, 1, 1,
        2, 2, 2, 2, 2, 2, 2,
        3, 3, 3, 3, 3, 3,
        4, 4, 4, 4, 4,
    ]


def _literal_channel_numbers() -> List[Int]:
    return [
        1, 2, 3, 4, 5, 6, 7, 8,
        9, 10, 11, 12, 13, 14, 15,
        17, 18, 19, 20, 21, 22,
        25, 26, 27, 28, 29,
    ]


def _literal_center_frequencies_hz() -> List[Int]:
    return [
        58_320_000_000,
        60_480_000_000,
        62_640_000_000,
        64_800_000_000,
        66_960_000_000,
        69_120_000_000,
        71_280_000_000,
        73_440_000_000,
        59_400_000_000,
        61_560_000_000,
        63_720_000_000,
        65_880_000_000,
        68_040_000_000,
        70_200_000_000,
        72_360_000_000,
        60_480_000_000,
        62_640_000_000,
        64_800_000_000,
        66_960_000_000,
        69_120_000_000,
        71_280_000_000,
        61_560_000_000,
        63_720_000_000,
        65_880_000_000,
        68_040_000_000,
        70_200_000_000,
    ]


def _literal_first_channel(ncb: Int) -> Int:
    return [1, 9, 17, 25][ncb - 1]


def _literal_channel_count(ncb: Int) -> Int:
    return [8, 7, 6, 5][ncb - 1]


def _representative_config(ncb: Int) raises -> WifiEDMGOfdmConfig:
    return WifiEDMGOfdmConfig(ncb, _literal_first_channel(ncb))


def _assert_int_lists_equal(
    actual: Span[Int, ...], expected: Span[Int, ...]
) raises:
    assert_equal(len(actual), len(expected))
    for index in range(len(actual)):
        assert_equal(actual[index], expected[index])


def _assert_complex_lists_equal(
    actual: Span[Complex64, ...], expected: Span[Complex64, ...]
) raises:
    assert_equal(len(actual), len(expected))
    for index in range(len(actual)):
        assert_equal(actual[index].re, expected[index].re)
        assert_equal(actual[index].im, expected[index].im)


def _literal_occupied_values(ncb: Int) -> List[Complex64]:
    var half = _literal_half_occupied()[ncb - 1]
    var result = List[Complex64](capacity=2 * half + 1)
    for tone in range(-half, half + 1):
        if tone >= -1 and tone <= 1:
            result.append(Complex64(0.0, 0.0))
        else:
            result.append(
                Complex64(Float64(tone), Float64((tone + 8192) % 31 - 15))
            )
    return result^


def _oracle_pack_two_intervals(
    ncb: Int, occupied: Span[Complex64, ...]
) -> List[Complex64]:
    # Independent split-copy construction: the negative interval maps to the
    # high DFT tail and the nonnegative interval maps to the low DFT head.
    var half = _literal_half_occupied()[ncb - 1]
    var dft_size = _literal_dft_sizes()[ncb - 1]
    var expected = List[Complex64](
        length=dft_size, fill=Complex64(0.0, 0.0)
    )
    for offset in range(half):
        expected[dft_size - half + offset] = Complex64(
            occupied[offset].re, occupied[offset].im
        )
    for offset in range(half + 1):
        expected[offset] = Complex64(
            occupied[half + offset].re, occupied[half + offset].im
        )
    return expected^


def test_all_four_ofdm_geometry_rows_static_and_analytic_exact() raises:
    assert_equal(WIFI_EDMG_MIN_CONTIGUOUS_CHANNELS, 1)
    assert_equal(WIFI_EDMG_MAX_CONTIGUOUS_CHANNELS, 4)
    assert_equal(WIFI_EDMG_OFDM_GEOMETRY_ROW_COUNT, 4)
    assert_equal(WIFI_EDMG_OFDM_SUBCARRIER_SPACING_HZ, 5_156_250)
    assert_equal(WIFI_EDMG_OFDM_DC_SUBCARRIERS, 3)
    var data = _literal_data_subcarriers()
    var pilots = _literal_pilot_subcarriers()
    var totals = _literal_total_subcarriers()
    var halves = _literal_half_occupied()
    var rates = _literal_sample_rates_hz()
    var dfts = _literal_dft_sizes()
    for row in range(4):
        var config = _representative_config(row + 1)
        var profile = wifi_edmg_ofdm_profile(config)
        assert_equal(profile.contiguous_channel_count, row + 1)
        assert_equal(profile.data_subcarriers, data[row])
        assert_equal(profile.pilot_subcarriers, pilots[row])
        assert_equal(profile.dc_subcarriers, 3)
        assert_equal(profile.total_subcarriers, totals[row])
        assert_equal(profile.half_occupied_subcarriers, halves[row])
        assert_equal(profile.sample_rate_hz, rates[row])
        assert_equal(profile.dft_size, dfts[row])
        assert_equal(profile.subcarrier_spacing_hz, 5_156_250)
        assert_equal(data[row] + pilots[row] + 3, totals[row])
        assert_equal(2 * halves[row] + 1, totals[row])
        assert_equal(dfts[row] * 5_156_250, rates[row])


def test_all_26_channel_center_rows_static_exact() raises:
    assert_equal(WIFI_EDMG_OFDM_CHANNEL_ROW_COUNT, 26)
    var ncbs = _literal_channel_ncbs()
    var channels = _literal_channel_numbers()
    var centers = _literal_center_frequencies_hz()
    assert_equal(len(ncbs), 26)
    assert_equal(len(channels), 26)
    assert_equal(len(centers), 26)
    for row in range(26):
        var config = WifiEDMGOfdmConfig(ncbs[row], channels[row])
        assert_equal(
            wifi_edmg_ofdm_channel_center_frequency_hz(config), centers[row]
        )

    var cursor = 0
    for ncb in range(1, 5):
        var actual = wifi_edmg_ofdm_channel_numbers(ncb)
        var count = _literal_channel_count(ncb)
        var expected = List[Int](capacity=count)
        for _ in range(count):
            expected.append(channels[cursor])
            cursor += 1
        _assert_int_lists_equal(Span(actual), Span(expected))
    assert_equal(cursor, 26)


def test_all_twelve_gi_symbol_sample_combinations_exact() raises:
    var guards: List[Int] = [
        WIFI_EDMG_GI_SHORT, WIFI_EDMG_GI_NORMAL, WIFI_EDMG_GI_LONG
    ]
    var literal_samples: List[Int] = [
        560, 608, 704,
        1120, 1216, 1408,
        1680, 1824, 2112,
        2240, 2432, 2816,
    ]
    var row = 0
    for ncb in range(1, 5):
        var config = _representative_config(ncb)
        for guard in guards:
            var actual = wifi_edmg_ofdm_symbol_samples(config, guard)
            assert_equal(actual, literal_samples[row])
            var multiplier = 1 << guard
            assert_equal(
                actual,
                _literal_dft_sizes()[ncb - 1] + 48 * ncb * multiplier,
            )
            row += 1
    assert_equal(row, 12)


def test_grid_pack_unpack_all_rows_external_oracle_exact() raises:
    for ncb in range(1, 5):
        var config = _representative_config(ncb)
        var occupied = _literal_occupied_values(ncb)
        var expected = _oracle_pack_two_intervals(ncb, Span(occupied))
        var actual = wifi_edmg_ofdm_pack_occupied_grid(
            config, Span(occupied)
        )
        _assert_complex_lists_equal(Span(actual), Span(expected))
        var decoded = wifi_edmg_ofdm_unpack_occupied_grid(
            config, Span(expected)
        )
        _assert_complex_lists_equal(Span(decoded), Span(occupied))

        var half = _literal_half_occupied()[ncb - 1]
        var dft_size = _literal_dft_sizes()[ncb - 1]
        assert_equal(len(actual), dft_size)
        assert_equal(actual[dft_size - 1].re, 0.0)
        assert_equal(actual[0].re, 0.0)
        assert_equal(actual[1].re, 0.0)
        for index in range(half + 1, dft_size - half):
            assert_equal(actual[index].re, 0.0)
            assert_equal(actual[index].im, 0.0)


def test_seeded_grid_and_channel_properties_exact() raises:
    var seed = UInt64(0x80211_2024_45444D47)
    for _ in range(64):
        seed = (
            seed * UInt64(6364136223846793005)
            + UInt64(1442695040888963407)
        )
        var ncb = 1 + Int((seed >> 11) % UInt64(4))
        var channel = (
            _literal_first_channel(ncb)
            + Int((seed >> 19) % UInt64(_literal_channel_count(ncb)))
        )
        var config = WifiEDMGOfdmConfig(ncb, channel)
        var occupied = _literal_occupied_values(ncb)
        for index in range(len(occupied)):
            var tone = index - _literal_half_occupied()[ncb - 1]
            if tone < -1 or tone > 1:
                seed = (
                    seed * UInt64(2862933555777941757)
                    + UInt64(3037000493)
                )
                occupied[index] = Complex64(
                    Float64(Int(seed & UInt64(0xFFFF)) - 32768),
                    Float64(Int((seed >> 16) & UInt64(0xFFFF)) - 32768),
                )
        var expected = _oracle_pack_two_intervals(ncb, Span(occupied))
        var actual = wifi_edmg_ofdm_pack_occupied_grid(
            config, Span(occupied)
        )
        _assert_complex_lists_equal(Span(actual), Span(expected))
        var decoded = wifi_edmg_ofdm_unpack_occupied_grid(
            config, Span(expected)
        )
        _assert_complex_lists_equal(Span(decoded), Span(occupied))

        var first_center: List[Int] = [
            58_320_000_000,
            59_400_000_000,
            60_480_000_000,
            61_560_000_000,
        ]
        assert_equal(
            wifi_edmg_ofdm_channel_center_frequency_hz(config),
            first_center[ncb - 1]
            + 2_160_000_000 * (channel - _literal_first_channel(ncb)),
        )
        var guard = Int((seed >> 37) % UInt64(3))
        assert_equal(
            wifi_edmg_ofdm_symbol_samples(config, guard),
            _literal_dft_sizes()[ncb - 1] + 48 * ncb * (1 << guard),
        )


def test_mutable_shape_int_nonfinite_and_guard_edges() raises:
    for invalid_ncb in [Int.MIN, -1, 0, 5, Int.MAX]:
        with assert_raises():
            _ = WifiEDMGOfdmConfig(invalid_ncb, 1)
        with assert_raises():
            _ = wifi_edmg_ofdm_channel_numbers(invalid_ncb)
    for ncb in range(1, 5):
        for extreme_channel in [Int.MIN, Int.MAX]:
            with assert_raises():
                _ = WifiEDMGOfdmConfig(ncb, extreme_channel)
    var invalid_channels: List[Int] = [
        Int.MIN, -1, 0, 9, Int.MAX,
        8, 16,
        16, 23,
        24, 30,
    ]
    var invalid_ncbs: List[Int] = [
        1, 1, 1, 1, 1,
        2, 2,
        3, 3,
        4, 4,
    ]
    for index in range(len(invalid_channels)):
        with assert_raises():
            _ = WifiEDMGOfdmConfig(
                invalid_ncbs[index], invalid_channels[index]
            )

    var config = WifiEDMGOfdmConfig(1, 1)
    var occupied = _literal_occupied_values(1)
    var bins = wifi_edmg_ofdm_pack_occupied_grid(config, Span(occupied))
    config.channel_number = 9
    with assert_raises():
        _ = wifi_edmg_ofdm_profile(config)
    with assert_raises():
        _ = wifi_edmg_ofdm_channel_center_frequency_hz(config)
    with assert_raises():
        _ = wifi_edmg_ofdm_symbol_samples(config, WIFI_EDMG_GI_SHORT)
    with assert_raises():
        _ = wifi_edmg_ofdm_pack_occupied_grid(config, Span(occupied))
    with assert_raises():
        _ = wifi_edmg_ofdm_unpack_occupied_grid(config, Span(bins))
    config.channel_number = 1
    config.contiguous_channel_count = Int.MAX
    with assert_raises():
        _ = wifi_edmg_ofdm_profile(config)

    config.contiguous_channel_count = 1
    for invalid_guard in [Int.MIN, -1, 3, Int.MAX]:
        with assert_raises():
            _ = wifi_edmg_ofdm_symbol_samples(config, invalid_guard)

    var empty = List[Complex64]()
    var short_occupied = List[Complex64](
        length=354, fill=Complex64(0.0, 0.0)
    )
    var long_occupied = List[Complex64](
        length=356, fill=Complex64(0.0, 0.0)
    )
    with assert_raises():
        _ = wifi_edmg_ofdm_pack_occupied_grid(config, Span(empty))
    with assert_raises():
        _ = wifi_edmg_ofdm_pack_occupied_grid(
            config, Span(short_occupied)
        )
    with assert_raises():
        _ = wifi_edmg_ofdm_pack_occupied_grid(config, Span(long_occupied))

    var short_bins = List[Complex64](
        length=511, fill=Complex64(0.0, 0.0)
    )
    var long_bins = List[Complex64](
        length=513, fill=Complex64(0.0, 0.0)
    )
    with assert_raises():
        _ = wifi_edmg_ofdm_unpack_occupied_grid(config, Span(short_bins))
    with assert_raises():
        _ = wifi_edmg_ofdm_unpack_occupied_grid(config, Span(long_bins))

    var half = _literal_half_occupied()[0]
    for dc_index in [half - 1, half, half + 1]:
        occupied[dc_index] = Complex64(1.0, 0.0)
        with assert_raises():
            _ = wifi_edmg_ofdm_pack_occupied_grid(config, Span(occupied))
        occupied[dc_index] = Complex64(0.0, 0.0)

    var finite_extreme = Float64.MAX_FINITE
    occupied[0] = Complex64(finite_extreme, -finite_extreme)
    bins = wifi_edmg_ofdm_pack_occupied_grid(config, Span(occupied))
    var decoded = wifi_edmg_ofdm_unpack_occupied_grid(config, Span(bins))
    assert_equal(decoded[0].re, finite_extreme)
    assert_equal(decoded[0].im, -finite_extreme)

    for nonfinite in [
        nan[DType.float64](),
        inf[DType.float64](),
        -inf[DType.float64](),
    ]:
        occupied[0] = Complex64(nonfinite, 0.0)
        with assert_raises():
            _ = wifi_edmg_ofdm_pack_occupied_grid(config, Span(occupied))
        occupied[0] = Complex64(2.0, -3.0)
        bins = wifi_edmg_ofdm_pack_occupied_grid(config, Span(occupied))
        bins[2] = Complex64(0.0, nonfinite)
        with assert_raises():
            _ = wifi_edmg_ofdm_unpack_occupied_grid(config, Span(bins))

    bins = wifi_edmg_ofdm_pack_occupied_grid(config, Span(occupied))
    bins[half + 1] = Complex64(1.0, 0.0)
    with assert_raises():
        _ = wifi_edmg_ofdm_unpack_occupied_grid(config, Span(bins))
    bins[half + 1] = Complex64(0.0, 0.0)
    for dc_bin in [511, 0, 1]:
        bins[dc_bin] = Complex64(0.0, -1.0)
        with assert_raises():
            _ = wifi_edmg_ofdm_unpack_occupied_grid(config, Span(bins))
        bins[dc_bin] = Complex64(0.0, 0.0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
