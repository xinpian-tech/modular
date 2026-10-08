"""Bounded IEEE 802.11-2024 Clause-28 EDMG OFDM geometry.

This scalar CPU reference closes the exact integer portion of the EDMG OFDM
signal-parameter table for one through four contiguous 2.16 GHz channels.  It
implements all four NCB rows (NSD, NSP, NDC, NST, NSR, sample rate, DFT size,
and subcarrier spacing), all 26 channel-number/center-frequency rows, exact
short/normal/long guard-interval sample geometry, and strict natural-order DFT
packing of the complete occupied interval.  The three DC tones are required
to be zero and strict unpacking also requires every guard bin to be zero.

The sole normative sources are the published IEEE Std 802.11ay-2021, available from
https://standards.ieee.org/ieee/802.11ay/6142/ and incorporated into the
published IEEE Std 802.11-2024 at
https://standards.ieee.org/ieee/802.11/10548/ .  Historical cross-checks use
official TGay contribution 11-17/0597r1, subclause 30.6.1, its motion #208
(18/0/0), and final motion compendium 11-17/0186r37.  These WG records never
authorize production or substitute for the published standards.  They are
linked by the completed TGay record at
https://www.ieee802.org/11/Reports/tgay_update.htm .  Adopted comment
resolution 11-18/0275r1 retained channels 7, 8, and the related wider-channel
rows.

The occupied-grid functions are an exact EDMG-specific geometry primitive;
they do not claim pilot/data classification or an OFDM waveform.  Pilot and
data tone tables, DC relative shift, channel aggregation, EDMG-STF/CEF,
headers, MCS/FEC/LDPC, SC PHY, PPDU construction, TRN, beamforming/MIMO,
receive processing, RF, and conformance remain outside this bounded module.
Consequently broad EDMG_PHY coverage remains PARTIAL.
"""

from std.collections import Span
from std.math import isfinite
from wireless_dsp.core import Complex64


comptime WIFI_EDMG_MIN_CONTIGUOUS_CHANNELS = 1
comptime WIFI_EDMG_MAX_CONTIGUOUS_CHANNELS = 4
comptime WIFI_EDMG_OFDM_GEOMETRY_ROW_COUNT = 4
comptime WIFI_EDMG_OFDM_CHANNEL_ROW_COUNT = 26
comptime WIFI_EDMG_OFDM_SUBCARRIER_SPACING_HZ = 5_156_250
comptime WIFI_EDMG_OFDM_DC_SUBCARRIERS = 3

comptime WIFI_EDMG_GI_SHORT = 0
comptime WIFI_EDMG_GI_NORMAL = 1
comptime WIFI_EDMG_GI_LONG = 2


def _validate_contiguous_channel_count(count: Int) raises:
    if (
        count < WIFI_EDMG_MIN_CONTIGUOUS_CHANNELS
        or count > WIFI_EDMG_MAX_CONTIGUOUS_CHANNELS
    ):
        raise Error("EDMG contiguous channel count must be in [1,4]")


def _channel_number_bounds(count: Int) raises -> Tuple[Int, Int]:
    _validate_contiguous_channel_count(count)
    if count == 1:
        return (1, 8)
    if count == 2:
        return (9, 15)
    if count == 3:
        return (17, 22)
    return (25, 29)


def _validate_guard_interval(guard_interval: Int) raises:
    if (
        guard_interval != WIFI_EDMG_GI_SHORT
        and guard_interval != WIFI_EDMG_GI_NORMAL
        and guard_interval != WIFI_EDMG_GI_LONG
    ):
        raise Error("EDMG guard interval must be short, normal, or long")


def _validate_finite_symbols(values: Span[Complex64, ...]) raises:
    for index in range(len(values)):
        if not isfinite(values[index].re) or not isfinite(values[index].im):
            raise Error("EDMG OFDM grid values must be finite")


def _is_exact_zero(value: Complex64) -> Bool:
    return value.re == 0.0 and value.im == 0.0


struct WifiEDMGOfdmConfig(ImplicitlyCopyable):
    """Mutable contiguous-channel and EDMG OFDM channel-number selection.

    ``contiguous_channel_count`` is NCB in the normative table.  This bounded
    configuration intentionally excludes noncontiguous channel aggregation.
    """

    var contiguous_channel_count: Int
    var channel_number: Int

    def __init__(
        out self, contiguous_channel_count: Int, channel_number: Int
    ) raises:
        self.contiguous_channel_count = contiguous_channel_count
        self.channel_number = channel_number
        self.validate()

    def validate(self) raises:
        """Revalidate the complete mutable channel selection."""
        var first, last = _channel_number_bounds(
            self.contiguous_channel_count
        )
        if self.channel_number < first or self.channel_number > last:
            raise Error("channel number is illegal for the EDMG NCB row")


struct WifiEDMGOfdmProfile(ImplicitlyCopyable):
    """Exact integer EDMG OFDM signal parameters for one NCB row."""

    var contiguous_channel_count: Int
    var data_subcarriers: Int
    var pilot_subcarriers: Int
    var dc_subcarriers: Int
    var total_subcarriers: Int
    var half_occupied_subcarriers: Int
    var sample_rate_hz: Int
    var dft_size: Int
    var subcarrier_spacing_hz: Int

    def __init__(
        out self,
        contiguous_channel_count: Int,
        data_subcarriers: Int,
        pilot_subcarriers: Int,
        total_subcarriers: Int,
        half_occupied_subcarriers: Int,
        sample_rate_hz: Int,
        dft_size: Int,
    ):
        self.contiguous_channel_count = contiguous_channel_count
        self.data_subcarriers = data_subcarriers
        self.pilot_subcarriers = pilot_subcarriers
        self.dc_subcarriers = WIFI_EDMG_OFDM_DC_SUBCARRIERS
        self.total_subcarriers = total_subcarriers
        self.half_occupied_subcarriers = half_occupied_subcarriers
        self.sample_rate_hz = sample_rate_hz
        self.dft_size = dft_size
        self.subcarrier_spacing_hz = (
            WIFI_EDMG_OFDM_SUBCARRIER_SPACING_HZ
        )


def wifi_edmg_ofdm_channel_numbers(
    contiguous_channel_count: Int,
) raises -> List[Int]:
    """Return every legal channel-number row for one contiguous bandwidth.

    The complete table domains are 1..8, 9..15, 17..22, and 25..29 for NCB
    one through four, respectively.  Returned rows are in normative order.
    """
    var first, last = _channel_number_bounds(contiguous_channel_count)
    var result = List[Int](capacity=last - first + 1)
    for channel_number in range(first, last + 1):
        result.append(channel_number)
    return result^


def wifi_edmg_ofdm_profile(
    config: WifiEDMGOfdmConfig,
) raises -> WifiEDMGOfdmProfile:
    """Return the complete exact integer signal-parameter row for ``config``.

    Rounded display values for sample time, DFT duration, and GI duration are
    represented without rounding by ``sample_rate_hz``, ``dft_size``, and
    ``wifi_edmg_ofdm_symbol_samples``.
    """
    config.validate()
    if config.contiguous_channel_count == 1:
        return WifiEDMGOfdmProfile(
            1, 336, 16, 355, 177, 2_640_000_000, 512
        )
    if config.contiguous_channel_count == 2:
        return WifiEDMGOfdmProfile(
            2, 734, 36, 773, 386, 5_280_000_000, 1024
        )
    if config.contiguous_channel_count == 3:
        return WifiEDMGOfdmProfile(
            3, 1134, 56, 1193, 596, 7_920_000_000, 1536
        )
    return WifiEDMGOfdmProfile(
        4, 1532, 76, 1611, 805, 10_560_000_000, 2048
    )


def wifi_edmg_ofdm_channel_center_frequency_hz(
    config: WifiEDMGOfdmConfig,
) raises -> Int:
    """Return the exact carrier center frequency for all 26 legal rows.

    Validation precedes subtraction and multiplication, bounding the result
    to 58.32--73.44 GHz and making every ``Int`` operation overflow-safe.
    """
    config.validate()
    var first_channel: Int
    var first_center_mhz: Int
    if config.contiguous_channel_count == 1:
        first_channel = 1
        first_center_mhz = 58_320
    elif config.contiguous_channel_count == 2:
        first_channel = 9
        first_center_mhz = 59_400
    elif config.contiguous_channel_count == 3:
        first_channel = 17
        first_center_mhz = 60_480
    else:
        first_channel = 25
        first_center_mhz = 61_560
    return (
        first_center_mhz + 2160 * (config.channel_number - first_channel)
    ) * 1_000_000


def wifi_edmg_ofdm_symbol_samples(
    config: WifiEDMGOfdmConfig, guard_interval: Int
) raises -> Int:
    """Return exact DFT-plus-GI samples for short, normal, or long GI.

    The displayed 18.18/36.36/72.72 ns table entries correspond exactly to
    48/96/192 samples per 2.16 GHz constituent channel.  Together with the
    normative sample rate this preserves the duration as a rational value.
    """
    config.validate()
    _validate_guard_interval(guard_interval)
    var profile = wifi_edmg_ofdm_profile(config)
    var guard_samples_per_channel = 48
    if guard_interval == WIFI_EDMG_GI_NORMAL:
        guard_samples_per_channel = 96
    elif guard_interval == WIFI_EDMG_GI_LONG:
        guard_samples_per_channel = 192
    return (
        profile.dft_size
        + config.contiguous_channel_count * guard_samples_per_channel
    )


def wifi_edmg_ofdm_pack_occupied_grid(
    config: WifiEDMGOfdmConfig,
    occupied_tones: Span[Complex64, ...],
) raises -> List[Complex64]:
    """Pack ascending tones ``[-NSR,NSR]`` into natural-order DFT bins.

    Input length is exactly NST.  The entries for tones -1, 0, and +1 must
    be exact complex zero.  Every other finite entry is copied without
    numerical transformation; unused DFT bins are exact zero.
    """
    config.validate()
    var profile = wifi_edmg_ofdm_profile(config)
    if len(occupied_tones) != profile.total_subcarriers:
        raise Error("EDMG occupied grid length must equal NST")
    _validate_finite_symbols(occupied_tones)
    var midpoint = profile.half_occupied_subcarriers
    var dc_minus = Complex64(
        occupied_tones[midpoint - 1].re,
        occupied_tones[midpoint - 1].im,
    )
    var dc_zero = Complex64(
        occupied_tones[midpoint].re, occupied_tones[midpoint].im
    )
    var dc_plus = Complex64(
        occupied_tones[midpoint + 1].re,
        occupied_tones[midpoint + 1].im,
    )
    if (
        not _is_exact_zero(dc_minus)
        or not _is_exact_zero(dc_zero)
        or not _is_exact_zero(dc_plus)
    ):
        raise Error("EDMG DC tones -1, 0, and +1 must be zero")

    var result = List[Complex64](
        length=profile.dft_size, fill=Complex64(0.0, 0.0)
    )
    for index in range(profile.total_subcarriers):
        var tone = index - midpoint
        var bin_index = tone if tone >= 0 else profile.dft_size + tone
        result[bin_index] = Complex64(
            occupied_tones[index].re, occupied_tones[index].im
        )
    return result^


def wifi_edmg_ofdm_unpack_occupied_grid(
    config: WifiEDMGOfdmConfig, dft_bins: Span[Complex64, ...]
) raises -> List[Complex64]:
    """Strictly invert a finite, zero-guard EDMG natural-order DFT grid.

    The vector length is exactly NDFT.  Every guard bin and all three DC bins
    must be exact complex zero, preventing a malformed wider grid from being
    silently truncated.
    """
    config.validate()
    var profile = wifi_edmg_ofdm_profile(config)
    if len(dft_bins) != profile.dft_size:
        raise Error("EDMG DFT grid length must equal NDFT")
    _validate_finite_symbols(dft_bins)
    var half = profile.half_occupied_subcarriers
    for bin_index in range(profile.dft_size):
        var occupied = (
            bin_index <= half or bin_index >= profile.dft_size - half
        )
        var value = Complex64(
            dft_bins[bin_index].re, dft_bins[bin_index].im
        )
        if not occupied and not _is_exact_zero(value):
            raise Error("EDMG DFT guard bins must be zero")
    var dc_minus = Complex64(
        dft_bins[profile.dft_size - 1].re,
        dft_bins[profile.dft_size - 1].im,
    )
    var dc_zero = Complex64(dft_bins[0].re, dft_bins[0].im)
    var dc_plus = Complex64(dft_bins[1].re, dft_bins[1].im)
    if (
        not _is_exact_zero(dc_minus)
        or not _is_exact_zero(dc_zero)
        or not _is_exact_zero(dc_plus)
    ):
        raise Error("EDMG DC tones -1, 0, and +1 must be zero")

    var result = List[Complex64](capacity=profile.total_subcarriers)
    for tone in range(-half, half + 1):
        var bin_index = tone if tone >= 0 else profile.dft_size + tone
        result.append(
            Complex64(dft_bins[bin_index].re, dft_bins[bin_index].im)
        )
    return result^
