"""Bounded IEEE 802.11-2024 Clause-22 TVHT PHY arithmetic.

This scalar CPU module implements TVHT-specific channelization, OFDM/tone
geometry, SIG-A bandwidth coding, MCS tables, and PPDU field-duration
arithmetic.  It does not treat an ordinary VHT profile as TVHT: the APIs use
the 6, 7, or 8 MHz basic channel unit (BCU), the five TVHT transmission
modes, 144/168-point per-BCU DFTs, 108 DATA plus six pilot tones per BCU,
TVHT interleaver/tone-mapper table arithmetic, and the TVWS field timings
explicitly.  Tables 22-26 through 22-37 contain 120 normative MCS rows; the
five TVHT mode selections expand these to 600 tested configurations, not 600
additional normative rows.

Normative baseline: IEEE Std 802.11-2024, Clause 22, especially 22.1,
22.3.2, 22.3.6-22.3.8, 22.3.10, 22.3.14, 22.4.4, and 22.5; Tables 22-8,
22-9, 22-13 through 22-15, and 22-25 through 22-37.  The active-standard
page is https://standards.ieee.org/ieee/802.11/10548/ .  The published
source amendment is IEEE Std 802.11af-2013 at
https://standards.ieee.org/ieee/802.11af/4761/ and its completed IEEE 802.11
task-group record is https://www.ieee802.org/11/Reports/tgaf_update.htm .

The bounded PPDU API accepts an already determined positive DATA-symbol
count.  It therefore closes the field timing, NTVHTLTF, long/short GI, and
20 ms duration arithmetic without claiming SERVICE/scrambler/BCC/LDPC pad
construction.  Complete TVHT-SIG-A/B packing, preamble/training sequences,
phase rotation, spatial parsing, BCC/LDPC processing, constellation mapping,
IDFT waveform generation, MU-MIMO/STBC/beamforming, channel estimation,
receive processing, spectrum-database/regulatory policy, RF masks, CCA, and
conformance remain outside this module and keep broad TVHT_PHY PARTIAL.
"""

from std.math import isfinite


comptime WIFI_TVHT_MODE_1 = 0
comptime WIFI_TVHT_MODE_2C = 1
comptime WIFI_TVHT_MODE_2N = 2
comptime WIFI_TVHT_MODE_4C = 3
comptime WIFI_TVHT_MODE_4N = 4

comptime WIFI_TVHT_LONG_GI = 0
comptime WIFI_TVHT_SHORT_GI = 1
comptime WIFI_TVHT_DATA_SUBCARRIERS_PER_BCU = 108
comptime WIFI_TVHT_PILOT_SUBCARRIERS_PER_BCU = 6
comptime WIFI_TVHT_OCCUPIED_SUBCARRIERS_PER_BCU = 114
comptime WIFI_TVHT_HIGHEST_LOCAL_SUBCARRIER = 58
comptime WIFI_TVHT_NUMBER_OF_ENCODERS = 1
comptime WIFI_TVHT_MAX_PPDU_DURATION_NS = 20_000_000
# Below 2^51, every integer and half-integer TVHT MHz offset is exactly
# representable.  The margin accommodates the largest valid index offset.
comptime WIFI_TVHT_MAX_EXACT_CHANNEL_START_MHZ = (
    2_251_799_813_683_000.0
)


def _is_tvht_mode(mode: Int) -> Bool:
    return mode >= WIFI_TVHT_MODE_1 and mode <= WIFI_TVHT_MODE_4N


def _validate_bcu_bandwidth(bcu_bandwidth_mhz: Int) raises:
    if (
        bcu_bandwidth_mhz != 6
        and bcu_bandwidth_mhz != 7
        and bcu_bandwidth_mhz != 8
    ):
        raise Error("TVHT BCU bandwidth must be 6, 7, or 8 MHz")


def _tvht_bcu_count(mode: Int) raises -> Int:
    if not _is_tvht_mode(mode):
        raise Error("unsupported TVHT transmission mode")
    if mode == WIFI_TVHT_MODE_1:
        return 1
    if mode == WIFI_TVHT_MODE_2C or mode == WIFI_TVHT_MODE_2N:
        return 2
    return 4


def _tvht_segment_count(mode: Int) raises -> Int:
    _ = _tvht_bcu_count(mode)
    if mode == WIFI_TVHT_MODE_2N or mode == WIFI_TVHT_MODE_4N:
        return 2
    return 1


def _tvht_bcus_per_segment(mode: Int) raises -> Int:
    var bcu_count = _tvht_bcu_count(mode)
    return bcu_count // _tvht_segment_count(mode)


struct WifiTVHTModeConfig(ImplicitlyCopyable):
    """Mutable TVHT BCU-width and transmission-mode selection."""

    var bcu_bandwidth_mhz: Int
    var mode: Int

    def __init__(out self, bcu_bandwidth_mhz: Int, mode: Int) raises:
        self.bcu_bandwidth_mhz = bcu_bandwidth_mhz
        self.mode = mode
        self.validate()

    def validate(self) raises:
        """Revalidate the complete mutable mode selection."""
        _validate_bcu_bandwidth(self.bcu_bandwidth_mhz)
        _ = _tvht_bcu_count(self.mode)


struct WifiTVHTChannelConfig(ImplicitlyCopyable):
    """Mutable Clause-22 TVHT channel-index configuration.

    ``center_index0`` identifies the lowest BCU in a contiguous segment.  In
    a noncontiguous mode it identifies the segment containing the primary
    BCU; ``center_index1`` identifies the other segment.  Zero is the strict
    sentinel for ``center_index1`` in single-segment modes.
    """

    var bcu_bandwidth_mhz: Int
    var mode: Int
    var center_index0: Int
    var center_index1: Int
    var primary_index: Int
    var channel_start_frequency_mhz: Float64

    def __init__(
        out self,
        bcu_bandwidth_mhz: Int,
        mode: Int,
        center_index0: Int,
        center_index1: Int,
        primary_index: Int,
        channel_start_frequency_mhz: Float64,
    ) raises:
        self.bcu_bandwidth_mhz = bcu_bandwidth_mhz
        self.mode = mode
        self.center_index0 = center_index0
        self.center_index1 = center_index1
        self.primary_index = primary_index
        self.channel_start_frequency_mhz = channel_start_frequency_mhz
        self.validate()

    def validate(self) raises:
        """Revalidate channel relations, bounds, and finite arithmetic."""
        _validate_bcu_bandwidth(self.bcu_bandwidth_mhz)
        _ = _tvht_bcu_count(self.mode)
        if self.center_index0 < 1 or self.center_index0 > 200:
            raise Error("TVHT center index 0 must be in [1,200]")
        if self.primary_index < 1 or self.primary_index > 200:
            raise Error("TVHT primary index must be in [1,200]")
        if not isfinite(self.channel_start_frequency_mhz):
            raise Error(
                "TVHT channel start must be finite"
            )
        if (
            self.channel_start_frequency_mhz <= 0.0
            or self.channel_start_frequency_mhz
            > WIFI_TVHT_MAX_EXACT_CHANNEL_START_MHZ
        ):
            raise Error("TVHT channel start is outside the exact positive range")
        # The checked upper bound makes this multiplication finite and keeps
        # the result below 2^52, so Float64-to-Int conversion cannot overflow
        # and every integer tick is exactly representable.  Exact round-trip
        # equality therefore enforces the Clause-22 0.5 MHz frequency grid,
        # including throughout the subnormal and near-upper-limit domains.
        var half_mhz_ticks_float = 2.0 * self.channel_start_frequency_mhz
        var half_mhz_ticks = Int(half_mhz_ticks_float)
        if Float64(half_mhz_ticks) != half_mhz_ticks_float:
            raise Error("TVHT channel start must be on the 0.5 MHz grid")

        if self.mode == WIFI_TVHT_MODE_1:
            if (
                self.center_index1 != 0
                or self.primary_index != self.center_index0
            ):
                raise Error("TVHT_MODE_1 requires its sole BCU as primary")
            return
        if self.mode == WIFI_TVHT_MODE_2C:
            if self.center_index0 > 199 or self.center_index1 != 0:
                raise Error("TVHT_MODE_2C requires two in-range BCUs")
            if (
                self.primary_index != self.center_index0
                and self.primary_index != self.center_index0 + 1
            ):
                raise Error("TVHT_MODE_2C primary must be in its two BCUs")
            return
        if self.mode == WIFI_TVHT_MODE_4C:
            if self.center_index0 > 197 or self.center_index1 != 0:
                raise Error("TVHT_MODE_4C requires four in-range BCUs")
            if (
                self.primary_index < self.center_index0
                or self.primary_index > self.center_index0 + 3
            ):
                raise Error("TVHT_MODE_4C primary must be in its four BCUs")
            return

        if self.center_index1 < 1 or self.center_index1 > 200:
            raise Error("noncontiguous TVHT center index 1 must be in [1,200]")
        if self.mode == WIFI_TVHT_MODE_2N:
            # Clause 22 permits any two non-identical channel indices.
            if (
                self.center_index0 == self.center_index1
                or self.primary_index != self.center_index0
            ):
                raise Error(
                    "TVHT_MODE_2N requires two distinct one-BCU segments"
                )
            return

        # TVHT_MODE_4N: each index identifies a valid two-BCU segment and
        # their starting indices differ by more than two.
        if self.center_index0 > 199 or self.center_index1 > 199:
            raise Error("TVHT_MODE_4N segment exceeds channel index 200")
        if (
            self.primary_index != self.center_index0
            and self.primary_index != self.center_index0 + 1
        ):
            raise Error("TVHT_MODE_4N primary must be in segment zero")
        if (
            (self.center_index0 < self.center_index1
             and self.center_index1 - self.center_index0 <= 2)
            or (self.center_index1 < self.center_index0
                and self.center_index0 - self.center_index1 <= 2)
            or self.center_index0 == self.center_index1
        ):
            raise Error("TVHT_MODE_4N segments must be separated by >2 BCUs")


struct WifiTVHTChannelPlan(ImplicitlyCopyable):
    """Exact channelization result for one validated TVHT configuration."""

    var bcu_bandwidth_mhz: Int
    var mode: Int
    var bcu_count: Int
    var segment_count: Int
    var bcus_per_segment: Int
    var contiguous: Bool
    var nominal_aggregate_bandwidth_mhz: Int
    var segment0_center_frequency_mhz: Float64
    var segment1_center_frequency_mhz: Float64
    var primary_center_frequency_mhz: Float64

    def __init__(
        out self,
        bcu_bandwidth_mhz: Int,
        mode: Int,
        bcu_count: Int,
        segment_count: Int,
        bcus_per_segment: Int,
        contiguous: Bool,
        nominal_aggregate_bandwidth_mhz: Int,
        segment0_center_frequency_mhz: Float64,
        segment1_center_frequency_mhz: Float64,
        primary_center_frequency_mhz: Float64,
    ):
        self.bcu_bandwidth_mhz = bcu_bandwidth_mhz
        self.mode = mode
        self.bcu_count = bcu_count
        self.segment_count = segment_count
        self.bcus_per_segment = bcus_per_segment
        self.contiguous = contiguous
        self.nominal_aggregate_bandwidth_mhz = (
            nominal_aggregate_bandwidth_mhz
        )
        self.segment0_center_frequency_mhz = (
            segment0_center_frequency_mhz
        )
        self.segment1_center_frequency_mhz = (
            segment1_center_frequency_mhz
        )
        self.primary_center_frequency_mhz = primary_center_frequency_mhz


def wifi_tvht_channel_plan(
    config: WifiTVHTChannelConfig,
) raises -> WifiTVHTChannelPlan:
    """Apply the exact Clause-22 channel-center equations.

    Regulatory-domain operating classes and database permission remain
    caller-owned.  This function validates only the standardized index and
    bonding relationships and computes the exact center-frequency arithmetic.
    """
    config.validate()
    var bcu_count = _tvht_bcu_count(config.mode)
    var segment_count = _tvht_segment_count(config.mode)
    var bcus_per_segment = _tvht_bcus_per_segment(config.mode)
    var correction_mhz = 0.0
    if config.mode == WIFI_TVHT_MODE_2C or config.mode == WIFI_TVHT_MODE_4N:
        correction_mhz = 0.5 * Float64(config.bcu_bandwidth_mhz)
    elif config.mode == WIFI_TVHT_MODE_4C:
        correction_mhz = 1.5 * Float64(config.bcu_bandwidth_mhz)
    var center0 = (
        config.channel_start_frequency_mhz
        + Float64(config.bcu_bandwidth_mhz * config.center_index0)
        + correction_mhz
    )
    var center1 = 0.0
    if segment_count == 2:
        center1 = (
            config.channel_start_frequency_mhz
            + Float64(config.bcu_bandwidth_mhz * config.center_index1)
            + correction_mhz
        )
    var primary = (
        config.channel_start_frequency_mhz
        + Float64(config.bcu_bandwidth_mhz * config.primary_index)
    )
    if (
        not isfinite(center0)
        or not isfinite(center1)
        or not isfinite(primary)
    ):
        raise Error("TVHT channel-center result is not representable")
    return WifiTVHTChannelPlan(
        config.bcu_bandwidth_mhz,
        config.mode,
        bcu_count,
        segment_count,
        bcus_per_segment,
        segment_count == 1,
        config.bcu_bandwidth_mhz * bcu_count,
        center0,
        center1,
        primary,
    )


struct WifiTVHTOFDMProfile(ImplicitlyCopyable):
    """Exact TVHT OFDM numerology and per-mode resource counts."""

    var bcu_bandwidth_mhz: Int
    var mode: Int
    var bcu_count: Int
    var segment_count: Int
    var bcus_per_segment: Int
    var dft_size_per_bcu: Int
    var dft_size_per_segment: Int
    var sample_rate_per_segment_hz: Int
    var data_subcarriers: Int
    var pilot_subcarriers: Int
    var occupied_subcarriers: Int
    var dft_period_ns: Int
    var long_guard_interval_ns: Int
    var short_guard_interval_ns: Int
    var long_symbol_duration_ns: Int
    var short_symbol_duration_ns: Int

    def __init__(
        out self,
        config: WifiTVHTModeConfig,
        bcu_count: Int,
        segment_count: Int,
        bcus_per_segment: Int,
        dft_size_per_bcu: Int,
        dft_period_ns: Int,
    ):
        self.bcu_bandwidth_mhz = config.bcu_bandwidth_mhz
        self.mode = config.mode
        self.bcu_count = bcu_count
        self.segment_count = segment_count
        self.bcus_per_segment = bcus_per_segment
        self.dft_size_per_bcu = dft_size_per_bcu
        self.dft_size_per_segment = dft_size_per_bcu * bcus_per_segment
        self.sample_rate_per_segment_hz = (
            config.bcu_bandwidth_mhz * 1_000_000 * bcus_per_segment
        )
        self.data_subcarriers = (
            WIFI_TVHT_DATA_SUBCARRIERS_PER_BCU * bcu_count
        )
        self.pilot_subcarriers = (
            WIFI_TVHT_PILOT_SUBCARRIERS_PER_BCU * bcu_count
        )
        self.occupied_subcarriers = (
            WIFI_TVHT_OCCUPIED_SUBCARRIERS_PER_BCU * bcu_count
        )
        self.dft_period_ns = dft_period_ns
        self.long_guard_interval_ns = dft_period_ns // 4
        self.short_guard_interval_ns = dft_period_ns // 8
        self.long_symbol_duration_ns = (
            dft_period_ns + self.long_guard_interval_ns
        )
        self.short_symbol_duration_ns = (
            dft_period_ns + self.short_guard_interval_ns
        )


def wifi_tvht_ofdm_profile(
    config: WifiTVHTModeConfig,
) raises -> WifiTVHTOFDMProfile:
    """Return the complete bounded Table 22-8/22-9 OFDM row."""
    config.validate()
    var bcu_count = _tvht_bcu_count(config.mode)
    var segment_count = _tvht_segment_count(config.mode)
    var bcus_per_segment = bcu_count // segment_count
    var dft_size = 168 if config.bcu_bandwidth_mhz == 7 else 144
    var dft_period_ns = 18_000 if config.bcu_bandwidth_mhz == 8 else 24_000
    return WifiTVHTOFDMProfile(
        config,
        bcu_count,
        segment_count,
        bcus_per_segment,
        dft_size,
        dft_period_ns,
    )


def _append_interval(mut values: List[Int], first: Int, last: Int):
    for value in range(first, last + 1):
        values.append(value)


def _validate_segment_index(
    config: WifiTVHTModeConfig, segment_index: Int
) raises -> Int:
    config.validate()
    var segment_count = _tvht_segment_count(config.mode)
    if segment_index < 0 or segment_index >= segment_count:
        raise Error("TVHT segment index is outside the selected mode")
    return _tvht_bcus_per_segment(config.mode)


def wifi_tvht_occupied_subcarriers(
    config: WifiTVHTModeConfig, segment_index: Int
) raises -> List[Int]:
    """Return ascending Table-22-9 occupied tones for one IDFT segment.

    Noncontiguous modes use a local index axis for each independently centered
    segment.  ``segment_index`` therefore selects the segment but does not
    translate it to an RF frequency; channel centers come from
    ``wifi_tvht_channel_plan``.
    """
    var units = _validate_segment_index(config, segment_index)
    var half_spacing = 84 if config.bcu_bandwidth_mhz == 7 else 72
    var result = List[Int](
        capacity=WIFI_TVHT_OCCUPIED_SUBCARRIERS_PER_BCU * units
    )
    for unit in range(units):
        var center = (2 * unit - (units - 1)) * half_spacing
        _append_interval(
            result,
            center - WIFI_TVHT_HIGHEST_LOCAL_SUBCARRIER,
            center - 2,
        )
        _append_interval(
            result,
            center + 2,
            center + WIFI_TVHT_HIGHEST_LOCAL_SUBCARRIER,
        )
    return result^


def wifi_tvht_pilot_subcarriers(
    config: WifiTVHTModeConfig, segment_index: Int
) raises -> List[Int]:
    """Return the exact six-per-BCU TVHT DATA pilot-tone row."""
    var units = _validate_segment_index(config, segment_index)
    var half_spacing = 84 if config.bcu_bandwidth_mhz == 7 else 72
    var local_pilots: List[Int] = [-53, -25, -11, 11, 25, 53]
    var result = List[Int](
        capacity=WIFI_TVHT_PILOT_SUBCARRIERS_PER_BCU * units
    )
    for unit in range(units):
        var center = (2 * unit - (units - 1)) * half_spacing
        for pilot in local_pilots:
            result.append(center + pilot)
    return result^


def wifi_tvht_sig_a_bandwidth_bits(
    config: WifiTVHTModeConfig,
) raises -> Int:
    """Return packed little-endian B0-B1 from TVHT-SIG-A1 Table 22-13.

    The printed bit strings are B0 first: MODE_1 is ``10`` (packed value 1),
    two-BCU modes are ``01`` (value 2), and four-BCU modes are ``11``.
    """
    config.validate()
    if config.mode == WIFI_TVHT_MODE_1:
        return 1
    if config.mode == WIFI_TVHT_MODE_2C or config.mode == WIFI_TVHT_MODE_2N:
        return 2
    return 3


def _tvht_mcs_parameters(mcs_index: Int) raises -> Tuple[Int, Int, Int]:
    if mcs_index == 0:
        return (1, 1, 2)
    if mcs_index == 1:
        return (2, 1, 2)
    if mcs_index == 2:
        return (2, 3, 4)
    if mcs_index == 3:
        return (4, 1, 2)
    if mcs_index == 4:
        return (4, 3, 4)
    if mcs_index == 5:
        return (6, 2, 3)
    if mcs_index == 6:
        return (6, 3, 4)
    if mcs_index == 7:
        return (6, 5, 6)
    if mcs_index == 8:
        return (8, 3, 4)
    if mcs_index == 9:
        return (8, 5, 6)
    raise Error("TVHT MCS index must be in [0,9]")


struct WifiTVHTMCSConfig(ImplicitlyCopyable):
    """Mutable TVHT equal-modulation MCS table selection."""

    var bcu_bandwidth_mhz: Int
    var mode: Int
    var mcs_index: Int
    var spatial_streams: Int

    def __init__(
        out self,
        bcu_bandwidth_mhz: Int,
        mode: Int,
        mcs_index: Int,
        spatial_streams: Int,
    ) raises:
        self.bcu_bandwidth_mhz = bcu_bandwidth_mhz
        self.mode = mode
        self.mcs_index = mcs_index
        self.spatial_streams = spatial_streams
        self.validate()

    def validate(self) raises:
        """Revalidate every mutable MCS table selector."""
        _validate_bcu_bandwidth(self.bcu_bandwidth_mhz)
        _ = _tvht_bcu_count(self.mode)
        _ = _tvht_mcs_parameters(self.mcs_index)
        if self.spatial_streams < 1 or self.spatial_streams > 4:
            raise Error("bounded TVHT MCS supports one through four streams")


struct WifiTVHTMCSProfile(ImplicitlyCopyable):
    """Exact Tables 22-26 through 22-37 rate-dependent row."""

    var bcu_bandwidth_mhz: Int
    var mode: Int
    var mcs_index: Int
    var spatial_streams: Int
    var bits_per_subcarrier: Int
    var code_rate_numerator: Int
    var code_rate_denominator: Int
    var data_subcarriers: Int
    var pilot_subcarriers: Int
    var coded_bits_per_symbol: Int
    var data_bits_per_symbol: Int
    var number_of_encoders: Int
    var bcc_interleaver_columns: Int
    var bcc_interleaver_rows: Int
    var bcc_interleaver_rotation: Int
    var ldpc_tone_mapping_distance: Int
    var mandatory_base_profile: Bool

    def __init__(
        out self,
        config: WifiTVHTMCSConfig,
        bits_per_subcarrier: Int,
        code_rate_numerator: Int,
        code_rate_denominator: Int,
        data_subcarriers: Int,
        pilot_subcarriers: Int,
        coded_bits_per_symbol: Int,
        data_bits_per_symbol: Int,
        interleaver_columns: Int,
        interleaver_row_multiplier: Int,
        interleaver_rotation: Int,
        tone_mapping_distance: Int,
    ):
        self.bcu_bandwidth_mhz = config.bcu_bandwidth_mhz
        self.mode = config.mode
        self.mcs_index = config.mcs_index
        self.spatial_streams = config.spatial_streams
        self.bits_per_subcarrier = bits_per_subcarrier
        self.code_rate_numerator = code_rate_numerator
        self.code_rate_denominator = code_rate_denominator
        self.data_subcarriers = data_subcarriers
        self.pilot_subcarriers = pilot_subcarriers
        self.coded_bits_per_symbol = coded_bits_per_symbol
        self.data_bits_per_symbol = data_bits_per_symbol
        self.number_of_encoders = WIFI_TVHT_NUMBER_OF_ENCODERS
        self.bcc_interleaver_columns = interleaver_columns
        self.bcc_interleaver_rows = (
            interleaver_row_multiplier * bits_per_subcarrier
        )
        self.bcc_interleaver_rotation = interleaver_rotation
        self.ldpc_tone_mapping_distance = tone_mapping_distance
        self.mandatory_base_profile = (
            config.mode == WIFI_TVHT_MODE_1
            and config.spatial_streams == 1
            and config.mcs_index <= 7
        )


def wifi_tvht_mcs_profile(
    config: WifiTVHTMCSConfig,
) raises -> WifiTVHTMCSProfile:
    """Return one exact TVHT MCS/interleaver/tone-mapping table row."""
    config.validate()
    var (bpsc, rate_numerator, rate_denominator) = _tvht_mcs_parameters(
        config.mcs_index
    )
    var bcu_count = _tvht_bcu_count(config.mode)
    var data_subcarriers = (
        WIFI_TVHT_DATA_SUBCARRIERS_PER_BCU * bcu_count
    )
    var pilot_subcarriers = (
        WIFI_TVHT_PILOT_SUBCARRIERS_PER_BCU * bcu_count
    )
    var coded_bits = data_subcarriers * config.spatial_streams * bpsc
    var data_bits = coded_bits // rate_denominator * rate_numerator
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
    return WifiTVHTMCSProfile(
        config,
        bpsc,
        rate_numerator,
        rate_denominator,
        data_subcarriers,
        pilot_subcarriers,
        coded_bits,
        data_bits,
        columns,
        row_multiplier,
        rotation,
        distance,
    )


def _tvht_ltf_count(space_time_streams: Int) raises -> Int:
    if space_time_streams == 1:
        return 1
    if space_time_streams == 2:
        return 2
    if space_time_streams == 3 or space_time_streams == 4:
        return 4
    raise Error("bounded TVHT PPDU supports one through four space-time streams")


def _tvht_ppdu_timing_parameters(
    bcu_bandwidth_mhz: Int,
) raises -> Tuple[Int, Int, Int, Int, Int]:
    _validate_bcu_bandwidth(bcu_bandwidth_mhz)
    if bcu_bandwidth_mhz == 8:
        return (45_000, 22_500, 20_250, 202_500, 22_500)
    return (60_000, 30_000, 27_000, 270_000, 30_000)


struct WifiTVHTPPDUConfig(ImplicitlyCopyable):
    """Mutable data-bearing TVHT PPDU field-duration selection.

    ``data_symbols`` is caller-supplied after coding/padding.  STBC is not in
    this bounded profile, so the space-time-stream count also determines the
    1, 2, or 4 TVHT-LTF symbols.
    """

    var bcu_bandwidth_mhz: Int
    var mode: Int
    var space_time_streams: Int
    var data_symbols: Int
    var guard_interval: Int

    def __init__(
        out self,
        bcu_bandwidth_mhz: Int,
        mode: Int,
        space_time_streams: Int,
        data_symbols: Int,
        guard_interval: Int,
    ) raises:
        self.bcu_bandwidth_mhz = bcu_bandwidth_mhz
        self.mode = mode
        self.space_time_streams = space_time_streams
        self.data_symbols = data_symbols
        self.guard_interval = guard_interval
        self.validate()

    def validate(self) raises:
        """Revalidate fields and the 20 ms PPDU bound before multiplication."""
        _validate_bcu_bandwidth(self.bcu_bandwidth_mhz)
        _ = _tvht_bcu_count(self.mode)
        var ltf_count = _tvht_ltf_count(self.space_time_streams)
        if self.data_symbols < 1:
            raise Error("bounded TVHT PPDU requires at least one DATA symbol")
        if (
            self.guard_interval != WIFI_TVHT_LONG_GI
            and self.guard_interval != WIFI_TVHT_SHORT_GI
        ):
            raise Error("TVHT guard interval must be LONG_GI or SHORT_GI")
        var (_, long_symbol, short_symbol, fixed_preamble, ltf_symbol) = (
            _tvht_ppdu_timing_parameters(self.bcu_bandwidth_mhz)
        )
        var symbol_duration = (
            long_symbol
            if self.guard_interval == WIFI_TVHT_LONG_GI
            else short_symbol
        )
        var preamble_duration = fixed_preamble + ltf_count * ltf_symbol
        var maximum_symbols = (
            WIFI_TVHT_MAX_PPDU_DURATION_NS - preamble_duration
        ) // symbol_duration
        if self.data_symbols > maximum_symbols:
            raise Error("TVHT PPDU exceeds the 20 ms duration limit")


struct WifiTVHTPPDUGeometry(ImplicitlyCopyable):
    """Exact TVHT field and total durations in integer nanoseconds."""

    var bcu_bandwidth_mhz: Int
    var mode: Int
    var space_time_streams: Int
    var tvht_ltf_symbols: Int
    var data_symbols: Int
    var guard_interval: Int
    var l_stf_duration_ns: Int
    var l_ltf_duration_ns: Int
    var l_sig_duration_ns: Int
    var tvht_sig_a_duration_ns: Int
    var tvht_stf_duration_ns: Int
    var tvht_ltf_symbol_duration_ns: Int
    var tvht_ltf_duration_ns: Int
    var tvht_sig_b_duration_ns: Int
    var data_symbol_duration_ns: Int
    var preamble_duration_ns: Int
    var data_duration_ns: Int
    var ppdu_duration_ns: Int

    def __init__(
        out self,
        config: WifiTVHTPPDUConfig,
        ltf_symbols: Int,
        long_field_duration: Int,
        short_field_duration: Int,
        data_symbol_duration: Int,
        preamble_duration: Int,
        data_duration: Int,
    ):
        self.bcu_bandwidth_mhz = config.bcu_bandwidth_mhz
        self.mode = config.mode
        self.space_time_streams = config.space_time_streams
        self.tvht_ltf_symbols = ltf_symbols
        self.data_symbols = config.data_symbols
        self.guard_interval = config.guard_interval
        self.l_stf_duration_ns = long_field_duration
        self.l_ltf_duration_ns = long_field_duration
        self.l_sig_duration_ns = short_field_duration
        self.tvht_sig_a_duration_ns = long_field_duration
        self.tvht_stf_duration_ns = short_field_duration
        self.tvht_ltf_symbol_duration_ns = short_field_duration
        self.tvht_ltf_duration_ns = ltf_symbols * short_field_duration
        self.tvht_sig_b_duration_ns = short_field_duration
        self.data_symbol_duration_ns = data_symbol_duration
        self.preamble_duration_ns = preamble_duration
        self.data_duration_ns = data_duration
        self.ppdu_duration_ns = preamble_duration + data_duration


def wifi_tvht_ppdu_geometry(
    config: WifiTVHTPPDUConfig,
) raises -> WifiTVHTPPDUGeometry:
    """Return exact Figure-22-1 field durations for a data-bearing PPDU."""
    config.validate()
    var ltf_symbols = _tvht_ltf_count(config.space_time_streams)
    var (
        long_field,
        long_symbol,
        short_symbol,
        fixed_preamble,
        ltf_symbol,
    ) = _tvht_ppdu_timing_parameters(config.bcu_bandwidth_mhz)
    var data_symbol_duration = (
        long_symbol
        if config.guard_interval == WIFI_TVHT_LONG_GI
        else short_symbol
    )
    var preamble_duration = fixed_preamble + ltf_symbols * ltf_symbol
    var data_duration = config.data_symbols * data_symbol_duration
    return WifiTVHTPPDUGeometry(
        config,
        ltf_symbols,
        long_field,
        ltf_symbol,
        data_symbol_duration,
        preamble_duration,
        data_duration,
    )
