"""Per-public-API CPU timings for the bounded EHT wideband tables.

Each public algorithm has its own ``@no_inline`` batched workload, three
untimed warmups, nine odd samples, and complete output consumption.  There is
no bundled public-API dispatcher and no accelerator or RF path.
"""

from std.benchmark import black_box, keep
from std.collections import Span
from std.time import global_perf_counter_ns
from wireless_dsp.benchmarking import (
    print_benchmark_metadata,
    report_timing_samples,
)
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


comptime _WARMUPS = 3
comptime _SAMPLES = 9
comptime _SCALAR_BATCH = 16_384
comptime _ALLOCATION_BATCH = 4096
comptime _FIXED_SALT = 0x11BE0320


def _mix(checksum: UInt64, value: Int) -> UInt64:
    return (checksum ^ UInt64(value + 4096)) * UInt64(1099511628211)


def _puncturing_bitmap(bandwidth_mhz: Int, indication: Int) -> Int:
    if bandwidth_mhz == 20 or bandwidth_mhz == 40:
        return 0
    if bandwidth_mhz == 80:
        if indication == 0:
            return 0
        return 1 << (indication - 1)
    if bandwidth_mhz == 160:
        var rows: List[Int] = [
            0x00, 0x01, 0x02, 0x04, 0x08, 0x10, 0x20,
            0x40, 0x80, 0x03, 0x0C, 0x30, 0xC0,
        ]
        return rows[indication]
    var rows: List[Int] = [
        0x0000, 0x0003, 0x000C, 0x0030, 0x00C0,
        0x0300, 0x0C00, 0x3000, 0xC000, 0x000F,
        0x00F0, 0x0F00, 0xF000, 0x003F, 0x00CF,
        0x030F, 0x0C0F, 0x300F, 0xC00F, 0xF003,
        0xF00C, 0xF030, 0xF0C0, 0xF300, 0xFC00,
    ]
    return rows[indication]


def _first_active_20mhz(disabled: Int, bandwidth_mhz: Int) -> Int:
    for index in range(bandwidth_mhz // 20):
        if (disabled & (1 << index)) == 0:
            return index
    return 0


@no_inline
def _geometry_workload(
    iterations: Int,
    salt: Int,
    bandwidths: Span[Int, ...],
) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for operation in range(iterations):
        var bandwidth_mhz = bandwidths[
            (operation + salt) % len(bandwidths)
        ]
        var geometry = wifi_eht_wideband_geometry(
            black_box(bandwidth_mhz)
        )
        checksum = _mix(checksum, geometry.bandwidth_mhz)
        checksum = _mix(checksum, geometry.fft_size)
        checksum = _mix(checksum, geometry.subcarrier_spacing_hz)
        checksum = _mix(checksum, geometry.twenty_mhz_subchannels)
        checksum = _mix(checksum, geometry.eighty_mhz_subblocks)
        checksum = _mix(checksum, geometry.one_sixty_mhz_segments)
        checksum = _mix(checksum, geometry.puncturing_granularity_mhz)
        keep(geometry)
    return checksum


@no_inline
def _puncturing_decode_workload(
    iterations: Int,
    salt: Int,
    bandwidths: Span[Int, ...],
    indications: Span[Int, ...],
    primaries: Span[Int, ...],
) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for operation in range(iterations):
        var case_index = (operation + salt) % len(bandwidths)
        var bandwidth_mhz = bandwidths[case_index]
        var indication = indications[case_index]
        var primary = primaries[case_index]
        var pattern = wifi_eht_non_ofdma_puncturing_decode(
            black_box(bandwidth_mhz),
            black_box(indication),
            black_box(primary),
        )
        checksum = _mix(checksum, pattern.bandwidth_mhz)
        checksum = _mix(checksum, pattern.indication)
        checksum = _mix(checksum, pattern.primary_20mhz_index)
        checksum = _mix(checksum, pattern.granularity_mhz)
        checksum = _mix(checksum, pattern.disabled_20mhz_bitmap)
        checksum = _mix(checksum, pattern.active_20mhz_bitmap)
        checksum = _mix(checksum, pattern.active_20mhz_subchannels)
        keep(pattern)
    return checksum


@no_inline
def _puncturing_index_workload(
    iterations: Int,
    salt: Int,
    bandwidths: Span[Int, ...],
    bitmaps: Span[Int, ...],
    primaries: Span[Int, ...],
) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for operation in range(iterations):
        var case_index = (operation + salt) % len(bandwidths)
        var bandwidth_mhz = bandwidths[case_index]
        var disabled_bitmap = bitmaps[case_index]
        var primary = primaries[case_index]
        var decoded_index = wifi_eht_non_ofdma_puncturing_index(
            black_box(bandwidth_mhz),
            black_box(disabled_bitmap),
            black_box(primary),
        )
        checksum = _mix(checksum, decoded_index + operation)
        keep(decoded_index)
    return checksum


@no_inline
def _large_mru_allocation_workload(
    iterations: Int,
    salt: Int,
    bandwidths: Span[Int, ...],
    mru_types: Span[Int, ...],
    row_counts: Span[Int, ...],
    ofdma_modes: Span[Bool, ...],
) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for operation in range(iterations):
        var selector = operation + salt
        var case_index = selector % len(bandwidths)
        var bandwidth_mhz = bandwidths[case_index]
        var mru_type = mru_types[case_index]
        # Advance the row ordinal once per visit to this profile.  Using the
        # raw selector here aliases even row counts with the 14-profile case
        # cycle and leaves half of every table permanently unbenchmarked.
        var row_ordinal = selector // len(bandwidths)
        var mru_index = row_ordinal % row_counts[case_index] + 1
        var is_ofdma = ofdma_modes[case_index]
        var allocation = wifi_eht_large_mru_allocation(
            black_box(bandwidth_mhz),
            black_box(mru_type),
            black_box(mru_index),
            black_box(is_ofdma),
        )
        checksum = _mix(checksum, allocation.bandwidth_mhz)
        checksum = _mix(checksum, allocation.mru_type)
        checksum = _mix(checksum, allocation.mru_index)
        checksum = _mix(checksum, Int(allocation.is_ofdma))
        checksum = _mix(checksum, allocation.total_tones)
        checksum = _mix(checksum, len(allocation.component_tones))
        checksum = _mix(checksum, len(allocation.component_ru_indices))
        # Retain the complete owned result while fingerprinting it in O(1), so
        # the attributable timing has no second output-length scan.
        var last = len(allocation.component_tones) - 1
        checksum = _mix(checksum, allocation.component_tones[0])
        checksum = _mix(checksum, allocation.component_tones[last])
        checksum = _mix(checksum, allocation.component_ru_indices[0])
        checksum = _mix(checksum, allocation.component_ru_indices[last])
        keep(allocation)
    return checksum


def main() raises:
    var geometry_bandwidths: List[Int] = [20, 40, 80, 160, 320]
    var puncturing_bandwidths = List[Int](capacity=45)
    var puncturing_indications = List[Int](capacity=45)
    var puncturing_bitmaps = List[Int](capacity=45)
    var puncturing_primaries = List[Int](capacity=45)
    for bandwidth_index in range(len(geometry_bandwidths)):
        var bandwidth_mhz = geometry_bandwidths[bandwidth_index]
        var row_count = 1
        if bandwidth_mhz == 80:
            row_count = 5
        elif bandwidth_mhz == 160:
            row_count = 13
        elif bandwidth_mhz == 320:
            row_count = 25
        for indication in range(row_count):
            var bitmap = _puncturing_bitmap(bandwidth_mhz, indication)
            puncturing_bandwidths.append(bandwidth_mhz)
            puncturing_indications.append(indication)
            puncturing_bitmaps.append(bitmap)
            puncturing_primaries.append(
                _first_active_20mhz(bitmap, bandwidth_mhz)
            )

    var mru_bandwidths: List[Int] = [
        80, 80, 160, 320, 160, 160, 320,
        160, 320, 320, 320, 320, 320, 320,
    ]
    var mru_types: List[Int] = [
        WIFI_EHT_MRU_484_242,
        WIFI_EHT_MRU_484_242,
        WIFI_EHT_MRU_484_242,
        WIFI_EHT_MRU_484_242,
        WIFI_EHT_MRU_996_484,
        WIFI_EHT_MRU_996_484,
        WIFI_EHT_MRU_996_484,
        WIFI_EHT_MRU_996_484_242,
        WIFI_EHT_MRU_2X996_484,
        WIFI_EHT_MRU_2X996_484,
        WIFI_EHT_MRU_3X996,
        WIFI_EHT_MRU_3X996,
        WIFI_EHT_MRU_3X996_484,
        WIFI_EHT_MRU_3X996_484,
    ]
    var mru_row_counts: List[Int] = [
        4, 4, 8, 16, 4, 4, 8, 8, 12, 12, 4, 4, 8, 8,
    ]
    var mru_ofdma_modes: List[Bool] = [
        False, True, True, True, False, True, True,
        False, False, True, False, True, False, True,
    ]

    var geometry_bandwidth_span = Span(geometry_bandwidths)
    var puncturing_bandwidth_span = Span(puncturing_bandwidths)
    var puncturing_indication_span = Span(puncturing_indications)
    var puncturing_bitmap_span = Span(puncturing_bitmaps)
    var puncturing_primary_span = Span(puncturing_primaries)
    var mru_bandwidth_span = Span(mru_bandwidths)
    var mru_type_span = Span(mru_types)
    var mru_row_count_span = Span(mru_row_counts)
    var mru_ofdma_mode_span = Span(mru_ofdma_modes)

    for _ in range(_WARMUPS):
        keep(
            _geometry_workload(
                _SCALAR_BATCH, _FIXED_SALT, geometry_bandwidth_span
            )
        )
        keep(
            _puncturing_decode_workload(
                _SCALAR_BATCH,
                _FIXED_SALT,
                puncturing_bandwidth_span,
                puncturing_indication_span,
                puncturing_primary_span,
            )
        )
        keep(
            _puncturing_index_workload(
                _SCALAR_BATCH,
                _FIXED_SALT,
                puncturing_bandwidth_span,
                puncturing_bitmap_span,
                puncturing_primary_span,
            )
        )
        keep(
            _large_mru_allocation_workload(
                _ALLOCATION_BATCH,
                _FIXED_SALT,
                mru_bandwidth_span,
                mru_type_span,
                mru_row_count_span,
                mru_ofdma_mode_span,
            )
        )

    var geometry_samples = List[UInt64](capacity=_SAMPLES)
    var decode_samples = List[UInt64](capacity=_SAMPLES)
    var index_samples = List[UInt64](capacity=_SAMPLES)
    var allocation_samples = List[UInt64](capacity=_SAMPLES)
    var retained = UInt64(1469598103934665603)

    for sample in range(_SAMPLES):
        var salt = _FIXED_SALT + sample * 17
        var start = global_perf_counter_ns()
        var geometry_value = _geometry_workload(
            _SCALAR_BATCH, salt, geometry_bandwidth_span
        )
        geometry_samples.append(global_perf_counter_ns() - start)
        retained = retained * UInt64(1099511628211) ^ geometry_value
        keep(geometry_value)

        start = global_perf_counter_ns()
        var decode_value = _puncturing_decode_workload(
            _SCALAR_BATCH,
            salt,
            puncturing_bandwidth_span,
            puncturing_indication_span,
            puncturing_primary_span,
        )
        decode_samples.append(global_perf_counter_ns() - start)
        retained = retained * UInt64(1099511628211) ^ decode_value
        keep(decode_value)

        start = global_perf_counter_ns()
        var index_value = _puncturing_index_workload(
            _SCALAR_BATCH,
            salt,
            puncturing_bandwidth_span,
            puncturing_bitmap_span,
            puncturing_primary_span,
        )
        index_samples.append(global_perf_counter_ns() - start)
        retained = retained * UInt64(1099511628211) ^ index_value
        keep(index_value)

        start = global_perf_counter_ns()
        var allocation_value = _large_mru_allocation_workload(
            _ALLOCATION_BATCH,
            salt,
            mru_bandwidth_span,
            mru_type_span,
            mru_row_count_span,
            mru_ofdma_mode_span,
        )
        allocation_samples.append(global_perf_counter_ns() - start)
        retained = retained * UInt64(1099511628211) ^ allocation_value
        keep(allocation_value)

    print_benchmark_metadata()
    print("wifi_eht_wideband_backend: scalar-cpu-exact-tables")
    report_timing_samples(
        "wifi_eht_wideband_geometry",
        geometry_samples,
        _WARMUPS,
        _SCALAR_BATCH,
        "one_complete_geometry_lookup",
    )
    report_timing_samples(
        "wifi_eht_non_ofdma_puncturing_decode",
        decode_samples,
        _WARMUPS,
        _SCALAR_BATCH,
        "one_complete_assigned_row_decode",
    )
    report_timing_samples(
        "wifi_eht_non_ofdma_puncturing_index",
        index_samples,
        _WARMUPS,
        _SCALAR_BATCH,
        "one_complete_legal_bitmap_inverse_lookup",
    )
    report_timing_samples(
        "wifi_eht_large_mru_allocation",
        allocation_samples,
        _WARMUPS,
        _ALLOCATION_BATCH,
        "one_complete_large_mru_row_with_list_allocation",
    )
    print("wifi_eht_wideband_retained_checksum:", retained)
