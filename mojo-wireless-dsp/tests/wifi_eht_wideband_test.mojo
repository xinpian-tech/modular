"""Independent exact-table evidence for bounded EHT wideband algorithms.

The expected puncturing bitmaps and MRU component indices below are direct
test-only transcriptions of the official IEEE 802.11 TGbe adopted table
sources cited by ``eht_wideband.mojo``.  They are deliberately not generated
through production helpers.
"""

from std.collections import Span
from std.testing import assert_equal, assert_raises, assert_true, TestSuite
from wireless_dsp.wireless.wifi.eht_wideband import (
    WIFI_EHT_MRU_484_242,
    WIFI_EHT_MRU_996_484,
    WIFI_EHT_MRU_996_484_242,
    WIFI_EHT_MRU_2X996_484,
    WIFI_EHT_MRU_3X996,
    WIFI_EHT_MRU_3X996_484,
    wifi_eht_wideband_geometry,
    wifi_eht_non_ofdma_puncturing_decode,
    wifi_eht_non_ofdma_puncturing_index,
    wifi_eht_large_mru_allocation,
)


def _oracle_population_count(value: Int, width: Int) -> Int:
    var count = 0
    for bit in range(width):
        if ((value >> bit) & 1) == 1:
            count += 1
    return count


def _oracle_first_active_20mhz(disabled: Int, width: Int) raises -> Int:
    for index in range(width):
        if (disabled & (1 << index)) == 0:
            return index
    raise Error("test oracle requires at least one active subchannel")


def _oracle_puncturing_rows(bandwidth_mhz: Int) raises -> List[Int]:
    if bandwidth_mhz == 20 or bandwidth_mhz == 40:
        return [0]
    if bandwidth_mhz == 80:
        return [0x0, 0x1, 0x2, 0x4, 0x8]
    if bandwidth_mhz == 160:
        return [
            0x00,
            0x01,
            0x02,
            0x04,
            0x08,
            0x10,
            0x20,
            0x40,
            0x80,
            0x03,
            0x0C,
            0x30,
            0xC0,
        ]
    if bandwidth_mhz == 320:
        return [
            0x0000,
            0x0003,
            0x000C,
            0x0030,
            0x00C0,
            0x0300,
            0x0C00,
            0x3000,
            0xC000,
            0x000F,
            0x00F0,
            0x0F00,
            0xF000,
            0x003F,
            0x00CF,
            0x030F,
            0x0C0F,
            0x300F,
            0xC00F,
            0xF003,
            0xF00C,
            0xF030,
            0xF0C0,
            0xF300,
            0xFC00,
        ]
    raise Error("test oracle bandwidth")


def _assert_mru_table(
    bandwidth_mhz: Int,
    mru_type: Int,
    non_ofdma_allowed: Bool,
    ofdma_allowed: Bool,
    expected_tones: Span[Int, ...],
    expected_flat_indices: Span[Int, ...],
) raises:
    var components = len(expected_tones)
    assert_true(components > 0)
    assert_equal(len(expected_flat_indices) % components, 0)
    var rows = len(expected_flat_indices) // components
    var expected_total = 0
    for component in range(components):
        expected_total += expected_tones[component]

    for profile in range(2):
        var is_ofdma = profile == 1
        if is_ofdma and not ofdma_allowed:
            continue
        if not is_ofdma and not non_ofdma_allowed:
            continue
        for row in range(rows):
            var allocation = wifi_eht_large_mru_allocation(
                bandwidth_mhz, mru_type, row + 1, is_ofdma
            )
            assert_equal(allocation.bandwidth_mhz, bandwidth_mhz)
            assert_equal(allocation.mru_type, mru_type)
            assert_equal(allocation.mru_index, row + 1)
            assert_equal(allocation.is_ofdma, is_ofdma)
            assert_equal(len(allocation.component_tones), components)
            assert_equal(len(allocation.component_ru_indices), components)
            assert_equal(allocation.total_tones, expected_total)
            for component in range(components):
                assert_equal(
                    allocation.component_tones[component],
                    expected_tones[component],
                )
                assert_equal(
                    allocation.component_ru_indices[component],
                    expected_flat_indices[row * components + component],
                )


def test_exact_contiguous_channel_geometry() raises:
    var bandwidths: List[Int] = [20, 40, 80, 160, 320]
    var fft_sizes: List[Int] = [256, 512, 1024, 2048, 4096]
    var subchannels: List[Int] = [1, 2, 4, 8, 16]
    var eighty_subblocks: List[Int] = [0, 0, 1, 2, 4]
    var one_sixty_segments: List[Int] = [0, 0, 0, 1, 2]
    var granularities: List[Int] = [20, 20, 20, 20, 40]
    for index in range(len(bandwidths)):
        var geometry = wifi_eht_wideband_geometry(bandwidths[index])
        assert_equal(geometry.bandwidth_mhz, bandwidths[index])
        assert_equal(geometry.fft_size, fft_sizes[index])
        assert_equal(geometry.subcarrier_spacing_hz, 78_125)
        assert_equal(geometry.twenty_mhz_subchannels, subchannels[index])
        assert_equal(geometry.eighty_mhz_subblocks, eighty_subblocks[index])
        assert_equal(
            geometry.one_sixty_mhz_segments, one_sixty_segments[index]
        )
        assert_equal(
            geometry.puncturing_granularity_mhz, granularities[index]
        )


def test_all_45_assigned_non_ofdma_puncturing_rows() raises:
    var bandwidths: List[Int] = [20, 40, 80, 160, 320]
    for bandwidth_mhz in bandwidths:
        var expected = _oracle_puncturing_rows(bandwidth_mhz)
        var width = bandwidth_mhz // 20
        var channel_mask = (1 << width) - 1
        var granularity = 40 if bandwidth_mhz == 320 else 20
        for indication in range(len(expected)):
            for primary in range(width):
                if (expected[indication] & (1 << primary)) != 0:
                    with assert_raises():
                        _ = wifi_eht_non_ofdma_puncturing_decode(
                            bandwidth_mhz, indication, primary
                        )
                    with assert_raises():
                        _ = wifi_eht_non_ofdma_puncturing_index(
                            bandwidth_mhz,
                            expected[indication],
                            primary,
                        )
                    continue
                var pattern = wifi_eht_non_ofdma_puncturing_decode(
                    bandwidth_mhz, indication, primary
                )
                assert_equal(pattern.bandwidth_mhz, bandwidth_mhz)
                assert_equal(pattern.indication, indication)
                assert_equal(pattern.primary_20mhz_index, primary)
                assert_equal(pattern.granularity_mhz, granularity)
                assert_equal(
                    pattern.disabled_20mhz_bitmap, expected[indication]
                )
                assert_equal(
                    pattern.active_20mhz_bitmap,
                    channel_mask ^ expected[indication],
                )
                assert_equal(
                    pattern.active_20mhz_subchannels,
                    _oracle_population_count(
                        channel_mask ^ expected[indication], width
                    ),
                )
                assert_equal(
                    wifi_eht_non_ofdma_puncturing_index(
                        bandwidth_mhz, expected[indication], primary
                    ),
                    indication,
                )


def test_all_72_large_mru_rows_against_independent_tables() raises:
    var tones_484_242: List[Int] = [484, 242]
    var indices_80_484_242: List[Int] = [2, 2, 2, 1, 1, 4, 1, 3]
    _assert_mru_table(
        80,
        WIFI_EHT_MRU_484_242,
        True,
        True,
        Span(tones_484_242),
        Span(indices_80_484_242),
    )

    var indices_160_484_242: List[Int] = [
        2, 2, 2, 1, 1, 4, 1, 3,
        4, 6, 4, 5, 3, 8, 3, 7,
    ]
    _assert_mru_table(
        160,
        WIFI_EHT_MRU_484_242,
        False,
        True,
        Span(tones_484_242),
        Span(indices_160_484_242),
    )

    var indices_320_484_242: List[Int] = [
        2, 2, 2, 1, 1, 4, 1, 3,
        4, 6, 4, 5, 3, 8, 3, 7,
        6, 10, 6, 9, 5, 12, 5, 11,
        8, 14, 8, 13, 7, 16, 7, 15,
    ]
    _assert_mru_table(
        320,
        WIFI_EHT_MRU_484_242,
        False,
        True,
        Span(tones_484_242),
        Span(indices_320_484_242),
    )

    var tones_996_484: List[Int] = [996, 484]
    var indices_160_996_484: List[Int] = [2, 2, 2, 1, 1, 4, 1, 3]
    _assert_mru_table(
        160,
        WIFI_EHT_MRU_996_484,
        True,
        True,
        Span(tones_996_484),
        Span(indices_160_996_484),
    )
    var indices_320_996_484: List[Int] = [
        2, 2, 2, 1, 1, 4, 1, 3,
        4, 6, 4, 5, 3, 8, 3, 7,
    ]
    _assert_mru_table(
        320,
        WIFI_EHT_MRU_996_484,
        False,
        True,
        Span(tones_996_484),
        Span(indices_320_996_484),
    )

    var tones_996_484_242: List[Int] = [996, 484, 242]
    var indices_160_996_484_242: List[Int] = [
        2, 2, 2, 2, 2, 1, 2, 1, 4, 2, 1, 3,
        1, 4, 6, 1, 4, 5, 1, 3, 8, 1, 3, 7,
    ]
    _assert_mru_table(
        160,
        WIFI_EHT_MRU_996_484_242,
        True,
        False,
        Span(tones_996_484_242),
        Span(indices_160_996_484_242),
    )

    var tones_2x996_484: List[Int] = [996, 996, 484]
    var indices_320_2x996_484: List[Int] = [
        2, 3, 2, 2, 3, 1, 1, 3, 4, 1, 3, 3,
        1, 2, 6, 1, 2, 5, 3, 4, 4, 3, 4, 3,
        2, 4, 6, 2, 4, 5, 2, 3, 8, 2, 3, 7,
    ]
    _assert_mru_table(
        320,
        WIFI_EHT_MRU_2X996_484,
        True,
        True,
        Span(tones_2x996_484),
        Span(indices_320_2x996_484),
    )

    var tones_3x996: List[Int] = [996, 996, 996]
    var indices_320_3x996: List[Int] = [
        2, 3, 4, 1, 3, 4, 1, 2, 4, 1, 2, 3,
    ]
    _assert_mru_table(
        320,
        WIFI_EHT_MRU_3X996,
        True,
        True,
        Span(tones_3x996),
        Span(indices_320_3x996),
    )

    var tones_3x996_484: List[Int] = [996, 996, 996, 484]
    var indices_320_3x996_484: List[Int] = [
        2, 3, 4, 2, 2, 3, 4, 1,
        1, 3, 4, 4, 1, 3, 4, 3,
        1, 2, 4, 6, 1, 2, 4, 5,
        1, 2, 3, 8, 1, 2, 3, 7,
    ]
    _assert_mru_table(
        320,
        WIFI_EHT_MRU_3X996_484,
        True,
        True,
        Span(tones_3x996_484),
        Span(indices_320_3x996_484),
    )


def test_reserved_shape_profile_and_integer_extremes() raises:
    for bandwidth_mhz in [Int.MIN, -320, 0, 10, 60, 240, 640, Int.MAX]:
        with assert_raises():
            _ = wifi_eht_wideband_geometry(bandwidth_mhz)
        with assert_raises():
            _ = wifi_eht_non_ofdma_puncturing_decode(bandwidth_mhz, 0, 0)
        with assert_raises():
            _ = wifi_eht_non_ofdma_puncturing_index(bandwidth_mhz, 0, 0)
        with assert_raises():
            _ = wifi_eht_large_mru_allocation(
                bandwidth_mhz, WIFI_EHT_MRU_484_242, 1, True
            )

    var bandwidths: List[Int] = [20, 40, 80, 160, 320]
    var first_reserved: List[Int] = [1, 1, 5, 13, 25]
    for index in range(len(bandwidths)):
        for indication in [Int.MIN, -1, first_reserved[index], 31, Int.MAX]:
            if indication == 31 and first_reserved[index] == 31:
                continue
            with assert_raises():
                _ = wifi_eht_non_ofdma_puncturing_decode(
                    bandwidths[index], indication, 0
                )

    with assert_raises():
        _ = wifi_eht_non_ofdma_puncturing_index(20, 1, 0)
    with assert_raises():
        _ = wifi_eht_non_ofdma_puncturing_index(40, 4, 0)
    with assert_raises():
        _ = wifi_eht_non_ofdma_puncturing_index(80, 0x3, 2)
    with assert_raises():
        _ = wifi_eht_non_ofdma_puncturing_index(160, 0x5, 1)
    with assert_raises():
        _ = wifi_eht_non_ofdma_puncturing_index(320, 0x1, 1)
    with assert_raises():
        _ = wifi_eht_non_ofdma_puncturing_index(320, 0xFFFF, 0)
    for bitmap in [Int.MIN, -1, Int.MAX]:
        with assert_raises():
            _ = wifi_eht_non_ofdma_puncturing_index(320, bitmap, 0)

    for primary in [Int.MIN, -1, 16, Int.MAX]:
        with assert_raises():
            _ = wifi_eht_non_ofdma_puncturing_decode(320, 0, primary)
        with assert_raises():
            _ = wifi_eht_non_ofdma_puncturing_index(320, 0, primary)
    with assert_raises():
        _ = wifi_eht_non_ofdma_puncturing_decode(80, 1, 0)
    with assert_raises():
        _ = wifi_eht_non_ofdma_puncturing_index(80, 0x1, 0)

    for mru_type in [Int.MIN, -1, 6, Int.MAX]:
        with assert_raises():
            _ = wifi_eht_large_mru_allocation(320, mru_type, 1, False)
    for mru_index in [Int.MIN, -1, 0, 17, Int.MAX]:
        with assert_raises():
            _ = wifi_eht_large_mru_allocation(
                320, WIFI_EHT_MRU_484_242, mru_index, True
            )
    for bandwidth_mhz in [20, 40, 80, 320]:
        with assert_raises():
            _ = wifi_eht_large_mru_allocation(
                bandwidth_mhz, WIFI_EHT_MRU_996_484_242, 1, False
            )
    with assert_raises():
        _ = wifi_eht_large_mru_allocation(
            160, WIFI_EHT_MRU_996_484_242, 1, True
        )
    with assert_raises():
        _ = wifi_eht_large_mru_allocation(
            160, WIFI_EHT_MRU_484_242, 1, False
        )
    with assert_raises():
        _ = wifi_eht_large_mru_allocation(
            320, WIFI_EHT_MRU_484_242, 1, False
        )
    with assert_raises():
        _ = wifi_eht_large_mru_allocation(
            320, WIFI_EHT_MRU_996_484, 1, False
        )

    # Every public numeric input is integral; NaN and infinity are therefore
    # unrepresentable at the API boundary rather than silently accepted.


def test_mutation_isolation_and_seeded_differential_roundtrips() raises:
    var mutated = wifi_eht_large_mru_allocation(
        320, WIFI_EHT_MRU_3X996_484, 8, False
    )
    mutated.component_tones[0] = Int.MAX
    mutated.component_ru_indices[0] = Int.MIN
    var fresh = wifi_eht_large_mru_allocation(
        320, WIFI_EHT_MRU_3X996_484, 8, False
    )
    assert_equal(fresh.component_tones[0], 996)
    assert_equal(fresh.component_ru_indices[0], 1)
    assert_equal(fresh.total_tones, 3472)

    var seed = UInt64(0x80211BE320)
    var bandwidths: List[Int] = [20, 40, 80, 160, 320]
    for _ in range(1021):
        seed = (
            seed * UInt64(6364136223846793005)
            + UInt64(1442695040888963407)
        )
        var bandwidth_mhz = bandwidths[Int(seed % UInt64(5))]
        var geometry = wifi_eht_wideband_geometry(bandwidth_mhz)
        assert_equal(geometry.twenty_mhz_subchannels * 20, bandwidth_mhz)
        assert_equal(geometry.fft_size * 20, bandwidth_mhz * 256)
        var oracle = _oracle_puncturing_rows(bandwidth_mhz)
        var indication = Int((seed >> 17) % UInt64(len(oracle)))
        var primary = _oracle_first_active_20mhz(
            oracle[indication], bandwidth_mhz // 20
        )
        var decoded = wifi_eht_non_ofdma_puncturing_decode(
            bandwidth_mhz, indication, primary
        )
        assert_equal(
            decoded.disabled_20mhz_bitmap, oracle[indication]
        )
        assert_equal(
            wifi_eht_non_ofdma_puncturing_index(
                bandwidth_mhz,
                decoded.disabled_20mhz_bitmap,
                primary,
            ),
            indication,
        )

        var mru_selector = Int((seed >> 29) % UInt64(6))
        var mru_type = WIFI_EHT_MRU_484_242
        var row_count = 16
        if mru_selector == 1:
            mru_type = WIFI_EHT_MRU_996_484
            row_count = 8
        elif mru_selector == 2:
            mru_type = WIFI_EHT_MRU_2X996_484
            row_count = 12
        elif mru_selector == 3:
            mru_type = WIFI_EHT_MRU_3X996
            row_count = 4
        elif mru_selector == 4 or mru_selector == 5:
            mru_type = WIFI_EHT_MRU_3X996_484
            row_count = 8
        var row = Int((seed >> 41) % UInt64(row_count)) + 1
        var is_ofdma = (seed & UInt64(1)) == UInt64(1)
        if (
            mru_type == WIFI_EHT_MRU_484_242
            or mru_type == WIFI_EHT_MRU_996_484
        ):
            is_ofdma = True
        var allocation = wifi_eht_large_mru_allocation(
            320, mru_type, row, is_ofdma
        )
        assert_equal(
            len(allocation.component_tones),
            len(allocation.component_ru_indices),
        )
        var independent_total = 0
        for component in range(len(allocation.component_tones)):
            independent_total += allocation.component_tones[component]
            assert_true(allocation.component_ru_indices[component] >= 1)
        assert_equal(allocation.total_tones, independent_total)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
