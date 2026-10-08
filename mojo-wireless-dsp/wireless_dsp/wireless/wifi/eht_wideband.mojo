"""Bounded CPU-only IEEE 802.11be EHT wideband table algorithms.

This module implements four exact, discrete parts of the published
IEEE Std 802.11be-2024 PHY: contiguous 20/40/80/160/320 MHz geometry, the
5-bit non-OFDMA U-SIG punctured-channel indication, its inverse legality
lookup, and the large-MRU component/index rows in Tables 36-13--36-15.

Sole normative publication: https://standards.ieee.org/ieee/802.11be/7516/ .
The following WG artifacts are historical table cross-checks only and never
authorize production or substitute for the final published amendment:
https://mentor.ieee.org/802.11/dcn/19/11-19-1262-21-00be-specification-framework-for-tgbe.docx
https://mentor.ieee.org/802.11/dcn/21/11-21-1368-01-00be-cc36-cr-on-36-3-12-7-2-u-sig-content-part-4.docx
https://mentor.ieee.org/802.11/dcn/22/11-22-0383-03-00be-cr-for-clause-36-3-2-2-subcarriers-and-resource-allocation-for-multiple-rus-part-2.doc

The puncturing bitmap uses one bit per 20 MHz subchannel, with bit zero at
the lowest frequency and one meaning disabled.  Decode and inverse lookup
both take the primary 20 MHz index and reject a row that disables it.  MRU
``component_ru_indices`` use
the per-size RU numbering printed in the cited tables; table gaps are never
returned as components.  Small MRUs, RU Allocation signaling, center-tone
details, noncontiguous channels, PPDU construction, and waveform processing
are outside this bounded reference.
"""


comptime WIFI_EHT_MRU_484_242 = 0
comptime WIFI_EHT_MRU_996_484 = 1
comptime WIFI_EHT_MRU_996_484_242 = 2
comptime WIFI_EHT_MRU_2X996_484 = 3
comptime WIFI_EHT_MRU_3X996 = 4
comptime WIFI_EHT_MRU_3X996_484 = 5


struct WifiEhtWidebandGeometry(ImplicitlyCopyable):
    """Exact contiguous EHT channel and OFDM geometry."""

    var bandwidth_mhz: Int
    var fft_size: Int
    var subcarrier_spacing_hz: Int
    var twenty_mhz_subchannels: Int
    var eighty_mhz_subblocks: Int
    var one_sixty_mhz_segments: Int
    var puncturing_granularity_mhz: Int

    def __init__(
        out self,
        bandwidth_mhz: Int,
        fft_size: Int,
        twenty_mhz_subchannels: Int,
        eighty_mhz_subblocks: Int,
        one_sixty_mhz_segments: Int,
        puncturing_granularity_mhz: Int,
    ):
        self.bandwidth_mhz = bandwidth_mhz
        self.fft_size = fft_size
        self.subcarrier_spacing_hz = 78_125
        self.twenty_mhz_subchannels = twenty_mhz_subchannels
        self.eighty_mhz_subblocks = eighty_mhz_subblocks
        self.one_sixty_mhz_segments = one_sixty_mhz_segments
        self.puncturing_granularity_mhz = puncturing_granularity_mhz


struct WifiEhtPuncturingPattern(ImplicitlyCopyable):
    """One decoded non-OFDMA U-SIG punctured-channel table row."""

    var bandwidth_mhz: Int
    var indication: Int
    var primary_20mhz_index: Int
    var granularity_mhz: Int
    var disabled_20mhz_bitmap: Int
    var active_20mhz_bitmap: Int
    var active_20mhz_subchannels: Int

    def __init__(
        out self,
        bandwidth_mhz: Int,
        indication: Int,
        primary_20mhz_index: Int,
        granularity_mhz: Int,
        disabled_20mhz_bitmap: Int,
        active_20mhz_bitmap: Int,
        active_20mhz_subchannels: Int,
    ):
        self.bandwidth_mhz = bandwidth_mhz
        self.indication = indication
        self.primary_20mhz_index = primary_20mhz_index
        self.granularity_mhz = granularity_mhz
        self.disabled_20mhz_bitmap = disabled_20mhz_bitmap
        self.active_20mhz_bitmap = active_20mhz_bitmap
        self.active_20mhz_subchannels = active_20mhz_subchannels


struct WifiEhtMruAllocation(Movable):
    """One exact large-MRU component composition and index-table row."""

    var bandwidth_mhz: Int
    var mru_type: Int
    var mru_index: Int
    var is_ofdma: Bool
    var component_tones: List[Int]
    var component_ru_indices: List[Int]
    var total_tones: Int

    def __init__(
        out self,
        bandwidth_mhz: Int,
        mru_type: Int,
        mru_index: Int,
        is_ofdma: Bool,
        var component_tones: List[Int],
        var component_ru_indices: List[Int],
        total_tones: Int,
    ):
        self.bandwidth_mhz = bandwidth_mhz
        self.mru_type = mru_type
        self.mru_index = mru_index
        self.is_ofdma = is_ofdma
        self.component_tones = component_tones^
        self.component_ru_indices = component_ru_indices^
        self.total_tones = total_tones


def wifi_eht_wideband_geometry(
    bandwidth_mhz: Int,
) raises -> WifiEhtWidebandGeometry:
    """Return exact EHT FFT/subchannel geometry for a contiguous bandwidth."""

    if bandwidth_mhz == 20:
        return WifiEhtWidebandGeometry(20, 256, 1, 0, 0, 20)
    if bandwidth_mhz == 40:
        return WifiEhtWidebandGeometry(40, 512, 2, 0, 0, 20)
    if bandwidth_mhz == 80:
        return WifiEhtWidebandGeometry(80, 1024, 4, 1, 0, 20)
    if bandwidth_mhz == 160:
        return WifiEhtWidebandGeometry(160, 2048, 8, 2, 1, 20)
    if bandwidth_mhz == 320:
        return WifiEhtWidebandGeometry(320, 4096, 16, 4, 2, 40)
    raise Error("EHT bandwidth must be 20, 40, 80, 160, or 320 MHz")


def _puncturing_max_indication(bandwidth_mhz: Int) raises -> Int:
    if bandwidth_mhz == 20 or bandwidth_mhz == 40:
        return 0
    if bandwidth_mhz == 80:
        return 4
    if bandwidth_mhz == 160:
        return 12
    if bandwidth_mhz == 320:
        return 24
    raise Error("EHT bandwidth must be 20, 40, 80, 160, or 320 MHz")


def _puncturing_disabled_bitmap(
    bandwidth_mhz: Int, indication: Int
) raises -> Int:
    var maximum = _puncturing_max_indication(bandwidth_mhz)
    if indication < 0 or indication > maximum:
        raise Error("non-OFDMA puncturing indication is reserved")

    if bandwidth_mhz == 20 or bandwidth_mhz == 40:
        return 0
    if bandwidth_mhz == 80:
        if indication == 0:
            return 0
        return 1 << (indication - 1)
    if bandwidth_mhz == 160:
        if indication == 0:
            return 0
        if indication <= 8:
            return 1 << (indication - 1)
        var forty_mhz_rows: List[Int] = [0x03, 0x0C, 0x30, 0xC0]
        return forty_mhz_rows[indication - 9]

    # Table order is increasing frequency.  Every printed 320 MHz table unit
    # is 40 MHz, so every disabled unit expands to two adjacent 20 MHz bits.
    var rows_320: List[Int] = [
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
    return rows_320[indication]


def _population_count(value: Int, width: Int) -> Int:
    var count = 0
    for bit in range(width):
        if (value & (1 << bit)) != 0:
            count += 1
    return count


def _validate_primary_20mhz_index(
    primary_20mhz_index: Int, subchannels: Int
) raises:
    if primary_20mhz_index < 0 or primary_20mhz_index >= subchannels:
        raise Error("primary 20 MHz index is outside the channel")


def wifi_eht_non_ofdma_puncturing_decode(
    bandwidth_mhz: Int, indication: Int, primary_20mhz_index: Int
) raises -> WifiEhtPuncturingPattern:
    """Decode one legal 5-bit non-OFDMA U-SIG puncturing table value."""

    var geometry = wifi_eht_wideband_geometry(bandwidth_mhz)
    _validate_primary_20mhz_index(
        primary_20mhz_index, geometry.twenty_mhz_subchannels
    )
    var disabled = _puncturing_disabled_bitmap(bandwidth_mhz, indication)
    if (disabled & (1 << primary_20mhz_index)) != 0:
        raise Error("puncturing pattern disables the primary 20 MHz channel")
    var channel_mask = (1 << geometry.twenty_mhz_subchannels) - 1
    var active = channel_mask ^ disabled
    return WifiEhtPuncturingPattern(
        bandwidth_mhz,
        indication,
        primary_20mhz_index,
        geometry.puncturing_granularity_mhz,
        disabled,
        active,
        _population_count(active, geometry.twenty_mhz_subchannels),
    )


def wifi_eht_non_ofdma_puncturing_index(
    bandwidth_mhz: Int,
    disabled_20mhz_bitmap: Int,
    primary_20mhz_index: Int,
) raises -> Int:
    """Return the 5-bit value, rejecting non-table or primary-disabled rows."""

    var geometry = wifi_eht_wideband_geometry(bandwidth_mhz)
    _validate_primary_20mhz_index(
        primary_20mhz_index, geometry.twenty_mhz_subchannels
    )
    var channel_mask = (1 << geometry.twenty_mhz_subchannels) - 1
    if (
        disabled_20mhz_bitmap < 0
        or disabled_20mhz_bitmap > channel_mask
    ):
        raise Error("puncturing bitmap has bits outside the channel")
    if (disabled_20mhz_bitmap & (1 << primary_20mhz_index)) != 0:
        raise Error("puncturing bitmap disables the primary 20 MHz channel")
    var maximum = _puncturing_max_indication(bandwidth_mhz)
    for indication in range(maximum + 1):
        if (
            _puncturing_disabled_bitmap(bandwidth_mhz, indication)
            == disabled_20mhz_bitmap
        ):
            return indication
    raise Error("puncturing bitmap is not an assigned non-OFDMA table row")


def _large_mru_table(
    bandwidth_mhz: Int, mru_type: Int, is_ofdma: Bool
) raises -> Tuple[List[Int], List[Int], Int]:
    """Return component tones, flattened RU indices, and row count."""

    if mru_type == WIFI_EHT_MRU_484_242:
        if bandwidth_mhz == 80:
            return [484, 242], [2, 2, 2, 1, 1, 4, 1, 3], 4
        if bandwidth_mhz == 160:
            if not is_ofdma:
                raise Error("484+242-tone MRU is OFDMA-only above 80 MHz")
            return [484, 242], [
                2, 2, 2, 1, 1, 4, 1, 3,
                4, 6, 4, 5, 3, 8, 3, 7,
            ], 8
        if bandwidth_mhz == 320:
            if not is_ofdma:
                raise Error("484+242-tone MRU is OFDMA-only above 80 MHz")
            return [484, 242], [
                2, 2, 2, 1, 1, 4, 1, 3,
                4, 6, 4, 5, 3, 8, 3, 7,
                6, 10, 6, 9, 5, 12, 5, 11,
                8, 14, 8, 13, 7, 16, 7, 15,
            ], 16
        raise Error("484+242-tone MRU requires 80, 160, or 320 MHz")

    if mru_type == WIFI_EHT_MRU_996_484:
        if bandwidth_mhz == 160:
            return [996, 484], [2, 2, 2, 1, 1, 4, 1, 3], 4
        if bandwidth_mhz == 320:
            if not is_ofdma:
                raise Error("996+484-tone MRU is OFDMA-only at 320 MHz")
            return [996, 484], [
                2, 2, 2, 1, 1, 4, 1, 3,
                4, 6, 4, 5, 3, 8, 3, 7,
            ], 8
        raise Error("996+484-tone MRU requires 160 or 320 MHz")

    if mru_type == WIFI_EHT_MRU_996_484_242:
        if bandwidth_mhz != 160:
            raise Error("996+484+242-tone MRU is defined only for 160 MHz")
        if is_ofdma:
            raise Error("996+484+242-tone MRU is non-OFDMA only")
        return [996, 484, 242], [
            2, 2, 2, 2, 2, 1, 2, 1, 4, 2, 1, 3,
            1, 4, 6, 1, 4, 5, 1, 3, 8, 1, 3, 7,
        ], 8

    if mru_type == WIFI_EHT_MRU_2X996_484:
        if bandwidth_mhz != 320:
            raise Error("2x996+484-tone MRU requires 320 MHz")
        return [996, 996, 484], [
            2, 3, 2, 2, 3, 1, 1, 3, 4, 1, 3, 3,
            1, 2, 6, 1, 2, 5, 3, 4, 4, 3, 4, 3,
            2, 4, 6, 2, 4, 5, 2, 3, 8, 2, 3, 7,
        ], 12

    if mru_type == WIFI_EHT_MRU_3X996:
        if bandwidth_mhz != 320:
            raise Error("3x996-tone MRU requires 320 MHz")
        return [996, 996, 996], [
            2, 3, 4, 1, 3, 4, 1, 2, 4, 1, 2, 3,
        ], 4

    if mru_type == WIFI_EHT_MRU_3X996_484:
        if bandwidth_mhz != 320:
            raise Error("3x996+484-tone MRU requires 320 MHz")
        return [996, 996, 996, 484], [
            2, 3, 4, 2, 2, 3, 4, 1,
            1, 3, 4, 4, 1, 3, 4, 3,
            1, 2, 4, 6, 1, 2, 4, 5,
            1, 2, 3, 8, 1, 2, 3, 7,
        ], 8

    raise Error("unsupported large-MRU type")


def wifi_eht_large_mru_allocation(
    bandwidth_mhz: Int,
    mru_type: Int,
    mru_index: Int,
    is_ofdma: Bool,
) raises -> WifiEhtMruAllocation:
    """Return one exact Tables 36-13--36-15 large-MRU composition row."""

    var table = _large_mru_table(bandwidth_mhz, mru_type, is_ofdma)
    var component_tones = table[0].copy()
    var flat_indices = table[1].copy()
    var row_count = table[2]
    if mru_index < 1 or mru_index > row_count:
        raise Error("large-MRU index is outside the selected table")
    var component_count = len(component_tones)
    var component_indices = List[Int](capacity=component_count)
    var total_tones = 0
    for component in range(component_count):
        total_tones += component_tones[component]
        component_indices.append(
            flat_indices[(mru_index - 1) * component_count + component]
        )
    return WifiEhtMruAllocation(
        bandwidth_mhz,
        mru_type,
        mru_index,
        is_ofdma,
        component_tones^,
        component_indices^,
        total_tones,
    )
