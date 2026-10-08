"""HE/EHT resource-unit profiles and the normative 20 MHz tone plan.

The physical tone ranges and pilot locations implemented here follow IEEE Std
802.11-2024 Table 27-7, which the EHT PHY reuses for 20 MHz allocations.  RU
indices in this API are deliberately zero based and increase with frequency.
Wider bandwidths expose counts and capacity profiles, but not physical tone or
EHT MRU allocation-index decoding.
"""

from std.collections import Span
from wireless_dsp.core import Complex64
from .profiles import (
    WIFI_PHY_HE,
    WIFI_PHY_EHT,
    WifiMCSProfile,
    _validate_wifi_mcs_profile,
    wifi_ofdm_profile,
)


struct WifiRUProfile(Movable):
    var family: Int
    var ru_tones: Int
    var data_subcarriers: Int
    var pilot_subcarriers: Int
    var minimum_bandwidth_mhz: Int
    var requires_ldpc: Bool

    def __init__(
        out self,
        family: Int,
        ru_tones: Int,
        data_subcarriers: Int,
        pilot_subcarriers: Int,
        minimum_bandwidth_mhz: Int,
        requires_ldpc: Bool,
    ):
        self.family = family
        self.ru_tones = ru_tones
        self.data_subcarriers = data_subcarriers
        self.pilot_subcarriers = pilot_subcarriers
        self.minimum_bandwidth_mhz = minimum_bandwidth_mhz
        self.requires_ldpc = requires_ldpc


def wifi_ru_profile(family: Int, ru_tones: Int) raises -> WifiRUProfile:
    """Return Nsd/Nsp and coding constraints for one regular HE/EHT RU."""
    if family != WIFI_PHY_HE and family != WIFI_PHY_EHT:
        raise Error("resource units are defined only for HE and EHT profiles")
    if ru_tones == 26:
        return WifiRUProfile(family, 26, 24, 2, 20, False)
    if ru_tones == 52:
        return WifiRUProfile(family, 52, 48, 4, 20, False)
    if ru_tones == 106:
        return WifiRUProfile(family, 106, 102, 4, 20, False)
    if ru_tones == 242:
        return WifiRUProfile(family, 242, 234, 8, 20, False)
    if ru_tones == 484:
        return WifiRUProfile(family, 484, 468, 16, 40, True)
    if ru_tones == 996:
        return WifiRUProfile(family, 996, 980, 16, 80, True)
    if ru_tones == 1992:
        return WifiRUProfile(family, 1992, 1960, 32, 160, True)
    if family == WIFI_PHY_EHT and ru_tones == 3984:
        return WifiRUProfile(family, 3984, 3920, 64, 320, True)
    raise Error("unsupported regular HE/EHT RU size")


def _validate_wifi_ru_profile(profile: WifiRUProfile) raises:
    """Reject mutable records that no longer equal one factory RU row."""
    var expected = wifi_ru_profile(profile.family, profile.ru_tones)
    if (
        profile.family != expected.family
        or profile.ru_tones != expected.ru_tones
        or profile.data_subcarriers != expected.data_subcarriers
        or profile.pilot_subcarriers != expected.pilot_subcarriers
        or profile.minimum_bandwidth_mhz != expected.minimum_bandwidth_mhz
        or profile.requires_ldpc != expected.requires_ldpc
    ):
        raise Error("RU profile does not match a canonical Wi-Fi table row")


def wifi_max_ru_count(family: Int, bandwidth_mhz: Int, ru_tones: Int) raises -> Int:
    """Maximum count of equal-sized regular RUs in a contiguous channel."""
    _ = wifi_ofdm_profile(family, bandwidth_mhz)
    _ = wifi_ru_profile(family, ru_tones)
    if bandwidth_mhz == 20:
        if ru_tones == 26:
            return 9
        if ru_tones == 52:
            return 4
        if ru_tones == 106:
            return 2
        if ru_tones == 242:
            return 1
    elif bandwidth_mhz == 40:
        if ru_tones == 26:
            return 18
        if ru_tones == 52:
            return 8
        if ru_tones == 106:
            return 4
        if ru_tones == 242:
            return 2
        if ru_tones == 484:
            return 1
    elif bandwidth_mhz == 80:
        if ru_tones == 26:
            return 37
        if ru_tones == 52:
            return 16
        if ru_tones == 106:
            return 8
        if ru_tones == 242:
            return 4
        if ru_tones == 484:
            return 2
        if ru_tones == 996:
            return 1
    elif bandwidth_mhz == 160:
        if ru_tones == 26:
            return 74
        if ru_tones == 52:
            return 32
        if ru_tones == 106:
            return 16
        if ru_tones == 242:
            return 8
        if ru_tones == 484:
            return 4
        if ru_tones == 996:
            return 2
        if ru_tones == 1992:
            return 1
    elif family == WIFI_PHY_EHT and bandwidth_mhz == 320:
        if ru_tones == 26:
            return 148
        if ru_tones == 52:
            return 64
        if ru_tones == 106:
            return 32
        if ru_tones == 242:
            return 16
        if ru_tones == 484:
            return 8
        if ru_tones == 996:
            return 4
        if ru_tones == 1992:
            return 2
        if ru_tones == 3984:
            return 1
    raise Error("RU does not fit the selected channel bandwidth")


def wifi_ru_coded_bits_per_symbol(
    profile: WifiRUProfile, mcs: WifiMCSProfile
) raises -> Int:
    """Return per-RU Ncbps after validating modulation/RU restrictions."""
    _validate_wifi_ru_profile(profile)
    _validate_wifi_mcs_profile(mcs)
    if profile.family != mcs.family:
        raise Error("RU and MCS profiles belong to different PHY families")
    if mcs.duplicate_mode:
        raise Error("EHT MCS 14 DUP uses a full-band OFDM profile, not one RU")
    if mcs.bits_per_subcarrier >= 10 and profile.ru_tones < 242:
        raise Error("1024/4096-QAM requires an RU of at least 242 tones")
    var divisor = 2 if mcs.dcm else 1
    return (
        profile.data_subcarriers
        * mcs.bits_per_subcarrier
        * mcs.spatial_streams
        // divisor
    )


def wifi_ru_data_bits_per_symbol(
    profile: WifiRUProfile, mcs: WifiMCSProfile
) raises -> Int:
    """Return floor(per-RU Ncbps * coding rate)."""
    _validate_wifi_ru_profile(profile)
    _validate_wifi_mcs_profile(mcs)
    var coded = wifi_ru_coded_bits_per_symbol(profile, mcs)
    return coded * mcs.code_rate_numerator // mcs.code_rate_denominator


def wifi_ru_requires_ldpc(profile: WifiRUProfile, mcs: WifiMCSProfile) raises -> Bool:
    """Report whether RU size, MCS, or stream count excludes BCC coding."""
    _validate_wifi_ru_profile(profile)
    _validate_wifi_mcs_profile(mcs)
    _ = wifi_ru_coded_bits_per_symbol(profile, mcs)
    return profile.requires_ldpc or mcs.ldpc_only or mcs.spatial_streams > 4


def _append_inclusive(mut result: List[Int], first: Int, last: Int):
    for subcarrier in range(first, last + 1):
        result.append(subcarrier)


def wifi_ru_subcarriers_20mhz(ru_tones: Int, ru_index: Int) raises -> List[Int]:
    """Return occupied physical subcarrier indices for the HE/EHT 20 MHz plan."""
    var result = List[Int](capacity=ru_tones)
    if ru_tones == 26:
        if ru_index == 0:
            _append_inclusive(result, -121, -96)
        elif ru_index == 1:
            _append_inclusive(result, -95, -70)
        elif ru_index == 2:
            _append_inclusive(result, -68, -43)
        elif ru_index == 3:
            _append_inclusive(result, -42, -17)
        elif ru_index == 4:
            _append_inclusive(result, -16, -4)
            _append_inclusive(result, 4, 16)
        elif ru_index == 5:
            _append_inclusive(result, 17, 42)
        elif ru_index == 6:
            _append_inclusive(result, 43, 68)
        elif ru_index == 7:
            _append_inclusive(result, 70, 95)
        elif ru_index == 8:
            _append_inclusive(result, 96, 121)
        else:
            raise Error("20 MHz RU-26 index must be in 0..8")
    elif ru_tones == 52:
        if ru_index == 0:
            _append_inclusive(result, -121, -70)
        elif ru_index == 1:
            _append_inclusive(result, -68, -17)
        elif ru_index == 2:
            _append_inclusive(result, 17, 68)
        elif ru_index == 3:
            _append_inclusive(result, 70, 121)
        else:
            raise Error("20 MHz RU-52 index must be in 0..3")
    elif ru_tones == 106:
        if ru_index == 0:
            _append_inclusive(result, -122, -17)
        elif ru_index == 1:
            _append_inclusive(result, 17, 122)
        else:
            raise Error("20 MHz RU-106 index must be in 0..1")
    elif ru_tones == 242:
        if ru_index != 0:
            raise Error("20 MHz has one RU-242")
        _append_inclusive(result, -122, -2)
        _append_inclusive(result, 2, 122)
    else:
        raise Error("20 MHz tone-plan helper supports RU-26/52/106/242")
    return result^


def wifi_ru_pilot_subcarriers_20mhz(ru_tones: Int, ru_index: Int) raises -> List[Int]:
    """Return the normative HE/EHT pilot indices inside a 20 MHz RU."""
    var occupied = wifi_ru_subcarriers_20mhz(ru_tones, ru_index)
    var candidates: List[Int] = [-116, -90, -48, -22, 22, 48, 90, 116]
    if ru_tones == 26 or ru_tones == 52:
        candidates = [
            -116, -102, -90, -76, -62, -48, -36, -22, -10,
            10, 22, 36, 48, 62, 76, 90, 102, 116,
        ]
    var result = List[Int]()
    for candidate in candidates:
        for subcarrier in occupied:
            if subcarrier == candidate:
                result.append(candidate)
                break
    var expected = wifi_ru_profile(WIFI_PHY_HE, ru_tones).pilot_subcarriers
    if len(result) != expected:
        raise Error("internal 20 MHz pilot-tone plan mismatch")
    return result^


def wifi_ru_data_subcarriers_20mhz(ru_tones: Int, ru_index: Int) raises -> List[Int]:
    """Return occupied non-pilot subcarrier indices for a 20 MHz RU."""
    var occupied = wifi_ru_subcarriers_20mhz(ru_tones, ru_index)
    var pilots = wifi_ru_pilot_subcarriers_20mhz(ru_tones, ru_index)
    var result = List[Int]()
    for subcarrier in occupied:
        var is_pilot = False
        for pilot in pilots:
            if subcarrier == pilot:
                is_pilot = True
                break
        if not is_pilot:
            result.append(subcarrier)
    return result^


def wifi_ru_allocations_disjoint_20mhz(
    ru_tones: Span[Int, ...], ru_indices: Span[Int, ...]
) raises -> Bool:
    """Check whether a list of 20 MHz RU allocations occupies disjoint tones."""
    if len(ru_tones) != len(ru_indices):
        raise Error("RU sizes and indices must have equal length")
    var occupied_bins = List[Bool](length=256, fill=False)
    for allocation in range(len(ru_tones)):
        var subcarriers = wifi_ru_subcarriers_20mhz(
            ru_tones[allocation], ru_indices[allocation]
        )
        for subcarrier in subcarriers:
            var bin_index = subcarrier if subcarrier >= 0 else 256 + subcarrier
            if occupied_bins[bin_index]:
                return False
            occupied_bins[bin_index] = True
    return True


def wifi_map_ru_symbol_20mhz(
    data: Span[Complex64, ...],
    pilots: Span[Complex64, ...],
    ru_tones: Int,
    ru_index: Int,
) raises -> List[Complex64]:
    """Map one HE/EHT RU's data and pilots into a 256-bin FFT spectrum."""
    var data_indices = wifi_ru_data_subcarriers_20mhz(ru_tones, ru_index)
    var pilot_indices = wifi_ru_pilot_subcarriers_20mhz(ru_tones, ru_index)
    if len(data) != len(data_indices) or len(pilots) != len(pilot_indices):
        raise Error("RU data or pilot vector has the wrong length")
    var spectrum = List[Complex64](length=256, fill=Complex64(0.0, 0.0))
    for i in range(len(data_indices)):
        var subcarrier = data_indices[i]
        var bin_index = subcarrier if subcarrier >= 0 else 256 + subcarrier
        spectrum[bin_index] = data[i]
    for i in range(len(pilot_indices)):
        var subcarrier = pilot_indices[i]
        var bin_index = subcarrier if subcarrier >= 0 else 256 + subcarrier
        spectrum[bin_index] = pilots[i]
    return spectrum^


def wifi_extract_ru_data_20mhz(
    spectrum: Span[Complex64, ...], ru_tones: Int, ru_index: Int
) raises -> List[Complex64]:
    if len(spectrum) != 256:
        raise Error("20 MHz HE/EHT spectrum must contain 256 bins")
    var indices = wifi_ru_data_subcarriers_20mhz(ru_tones, ru_index)
    var result = List[Complex64](capacity=len(indices))
    for subcarrier in indices:
        var bin_index = subcarrier if subcarrier >= 0 else 256 + subcarrier
        result.append(spectrum[bin_index])
    return result^


def wifi_extract_ru_pilots_20mhz(
    spectrum: Span[Complex64, ...], ru_tones: Int, ru_index: Int
) raises -> List[Complex64]:
    if len(spectrum) != 256:
        raise Error("20 MHz HE/EHT spectrum must contain 256 bins")
    var indices = wifi_ru_pilot_subcarriers_20mhz(ru_tones, ru_index)
    var result = List[Complex64](capacity=len(indices))
    for subcarrier in indices:
        var bin_index = subcarrier if subcarrier >= 0 else 256 + subcarrier
        result.append(spectrum[bin_index])
    return result^
