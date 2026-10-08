"""IEEE 802.11 HT/VHT/HE/EHT PHY configuration profiles.

The integer family tags keep the reference layer lightweight while the returned
records make every modulation, coding, and OFDM parameter explicit.  HT, VHT,
and HE values follow IEEE Std 802.11-2024 (Clauses 19, 21, and 27); EHT values
follow IEEE Std 802.11be-2024 (Clause 36), because EHT is not part of the 2024
base revision.  EHT MCS 14 (BPSK-DCM-DUP) and MCS 15 (BPSK-DCM) are modeled
explicitly instead of being mistaken for ordinary constellation-only MCSs.
"""


comptime WIFI_PHY_HT = 1
comptime WIFI_PHY_VHT = 2
comptime WIFI_PHY_HE = 3
comptime WIFI_PHY_EHT = 4


struct WifiMCSProfile(Movable):
    """Modulation and coding parameters for one spatial-stream configuration."""

    var family: Int
    var mcs_index: Int
    var bits_per_subcarrier: Int
    var code_rate_numerator: Int
    var code_rate_denominator: Int
    var spatial_streams: Int
    var dcm: Bool
    var duplicate_mode: Bool
    var ldpc_only: Bool

    def __init__(
        out self,
        family: Int,
        mcs_index: Int,
        bits_per_subcarrier: Int,
        code_rate_numerator: Int,
        code_rate_denominator: Int,
        spatial_streams: Int,
        dcm: Bool,
        duplicate_mode: Bool,
        ldpc_only: Bool,
    ):
        self.family = family
        self.mcs_index = mcs_index
        self.bits_per_subcarrier = bits_per_subcarrier
        self.code_rate_numerator = code_rate_numerator
        self.code_rate_denominator = code_rate_denominator
        self.spatial_streams = spatial_streams
        self.dcm = dcm
        self.duplicate_mode = duplicate_mode
        self.ldpc_only = ldpc_only


struct WifiOFDMProfile(Movable):
    """Full-band OFDM tone counts and nominal timing for a PHY family."""

    var family: Int
    var bandwidth_mhz: Int
    var fft_size: Int
    var data_subcarriers: Int
    var pilot_subcarriers: Int
    var occupied_subcarriers: Int
    var useful_symbol_ns: Int
    var default_guard_interval_ns: Int
    var maximum_spatial_streams: Int

    def __init__(
        out self,
        family: Int,
        bandwidth_mhz: Int,
        fft_size: Int,
        data_subcarriers: Int,
        pilot_subcarriers: Int,
        occupied_subcarriers: Int,
        useful_symbol_ns: Int,
        default_guard_interval_ns: Int,
        maximum_spatial_streams: Int,
    ):
        self.family = family
        self.bandwidth_mhz = bandwidth_mhz
        self.fft_size = fft_size
        self.data_subcarriers = data_subcarriers
        self.pilot_subcarriers = pilot_subcarriers
        self.occupied_subcarriers = occupied_subcarriers
        self.useful_symbol_ns = useful_symbol_ns
        self.default_guard_interval_ns = default_guard_interval_ns
        self.maximum_spatial_streams = maximum_spatial_streams


def _mcs_modulation_and_rate(mcs_index: Int) raises -> Tuple[Int, Int, Int]:
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
    if mcs_index == 10:
        return (10, 3, 4)
    if mcs_index == 11:
        return (10, 5, 6)
    if mcs_index == 12:
        return (12, 3, 4)
    if mcs_index == 13:
        return (12, 5, 6)
    raise Error("unsupported regular Wi-Fi MCS")


def wifi_mcs_profile(
    family: Int,
    mcs_index: Int,
    *,
    spatial_streams: Int = 0,
    dcm: Bool = False,
) raises -> WifiMCSProfile:
    """Return the normative data MCS profile.

    HT MCS 0--31 encodes the spatial-stream count in the MCS index.  For VHT,
    HE, and EHT, ``spatial_streams=0`` selects one stream.  HE DCM is accepted
    only for its defined BPSK/QPSK/16-QAM profiles and at most two streams.  EHT encodes
    DCM/DUP explicitly as MCS 14/15; RU-specific restrictions remain the
    caller's protocol responsibility.
    """
    var local_mcs = mcs_index
    var streams = spatial_streams
    if family == WIFI_PHY_HT:
        if mcs_index < 0 or mcs_index > 31:
            raise Error("HT MCS must be in the unequal-modulation-free range 0..31")
        streams = mcs_index // 8 + 1
        local_mcs = mcs_index % 8
        if spatial_streams != 0 and spatial_streams != streams:
            raise Error("HT spatial-stream count is encoded by the MCS index")
    elif family == WIFI_PHY_VHT:
        if mcs_index < 0 or mcs_index > 9:
            raise Error("VHT MCS must be in 0..9")
        streams = 1 if streams == 0 else streams
        if streams < 1 or streams > 8:
            raise Error("VHT supports one through eight spatial streams")
    elif family == WIFI_PHY_HE:
        if mcs_index < 0 or mcs_index > 11:
            raise Error("HE MCS must be in 0..11")
        streams = 1 if streams == 0 else streams
        if streams < 1 or streams > 8:
            raise Error("HE supports one through eight spatial streams")
    elif family == WIFI_PHY_EHT:
        if mcs_index < 0 or mcs_index > 15:
            raise Error("EHT MCS must be in 0..15")
        streams = 1 if streams == 0 else streams
        if streams < 1 or streams > 8:
            raise Error("EHT supports one through eight spatial streams")
    else:
        raise Error("unknown Wi-Fi PHY family")

    if family == WIFI_PHY_EHT and (local_mcs == 14 or local_mcs == 15):
        if streams != 1:
            raise Error("EHT MCS 14/15 are defined only for one spatial stream")
        return WifiMCSProfile(
            family,
            mcs_index,
            1,
            1,
            2,
            1,
            True,
            local_mcs == 14,
            local_mcs == 14,
        )

    if dcm:
        if family != WIFI_PHY_HE and family != WIFI_PHY_EHT:
            raise Error("DCM is an HE/EHT data modulation mode")
        if family == WIFI_PHY_EHT:
            raise Error("use EHT MCS 14 or 15 for DCM modes")
        if streams < 1 or streams > 2:
            raise Error("HE DCM supports one or two spatial streams")
        if local_mcs != 0 and local_mcs != 1 and local_mcs != 3 and local_mcs != 4:
            raise Error("DCM is not defined for this MCS")

    var (bits_per_subcarrier, rate_numerator, rate_denominator) = (
        _mcs_modulation_and_rate(local_mcs)
    )
    return WifiMCSProfile(
        family,
        mcs_index,
        bits_per_subcarrier,
        rate_numerator,
        rate_denominator,
        streams,
        dcm,
        False,
        (family == WIFI_PHY_HE or family == WIFI_PHY_EHT) and local_mcs >= 10,
    )


def wifi_ofdm_profile(family: Int, bandwidth_mhz: Int) raises -> WifiOFDMProfile:
    """Return full-band NFFT/Nsd/Nsp parameters for contiguous channels."""
    if family == WIFI_PHY_HT:
        if bandwidth_mhz == 20:
            return WifiOFDMProfile(family, 20, 64, 52, 4, 56, 3200, 800, 4)
        if bandwidth_mhz == 40:
            return WifiOFDMProfile(family, 40, 128, 108, 6, 114, 3200, 800, 4)
        raise Error("HT supports 20 or 40 MHz in this profile")
    if family == WIFI_PHY_VHT:
        if bandwidth_mhz == 20:
            return WifiOFDMProfile(family, 20, 64, 52, 4, 56, 3200, 800, 8)
        if bandwidth_mhz == 40:
            return WifiOFDMProfile(family, 40, 128, 108, 6, 114, 3200, 800, 8)
        if bandwidth_mhz == 80:
            return WifiOFDMProfile(family, 80, 256, 234, 8, 242, 3200, 800, 8)
        if bandwidth_mhz == 160:
            return WifiOFDMProfile(family, 160, 512, 468, 16, 484, 3200, 800, 8)
        raise Error("VHT supports 20, 40, 80, or 160 MHz")
    if family == WIFI_PHY_HE or family == WIFI_PHY_EHT:
        var maximum_streams = 8
        if bandwidth_mhz == 20:
            return WifiOFDMProfile(family, 20, 256, 234, 8, 242, 12800, 800, maximum_streams)
        if bandwidth_mhz == 40:
            return WifiOFDMProfile(family, 40, 512, 468, 16, 484, 12800, 800, maximum_streams)
        if bandwidth_mhz == 80:
            return WifiOFDMProfile(family, 80, 1024, 980, 16, 996, 12800, 800, maximum_streams)
        if bandwidth_mhz == 160:
            return WifiOFDMProfile(family, 160, 2048, 1960, 32, 1992, 12800, 800, maximum_streams)
        if family == WIFI_PHY_EHT and bandwidth_mhz == 320:
            return WifiOFDMProfile(family, 320, 4096, 3920, 64, 3984, 12800, 800, maximum_streams)
        raise Error("unsupported HE/EHT channel bandwidth")
    raise Error("unknown Wi-Fi PHY family")


def _validate_wifi_mcs_profile(profile: WifiMCSProfile) raises:
    """Reject mutable records that no longer equal one factory MCS row."""
    var expected = wifi_mcs_profile(
        profile.family,
        profile.mcs_index,
        spatial_streams=profile.spatial_streams,
        dcm=profile.dcm,
    )
    if (
        profile.family != expected.family
        or profile.mcs_index != expected.mcs_index
        or profile.bits_per_subcarrier != expected.bits_per_subcarrier
        or profile.code_rate_numerator != expected.code_rate_numerator
        or profile.code_rate_denominator != expected.code_rate_denominator
        or profile.spatial_streams != expected.spatial_streams
        or profile.dcm != expected.dcm
        or profile.duplicate_mode != expected.duplicate_mode
        or profile.ldpc_only != expected.ldpc_only
    ):
        raise Error("MCS profile does not match a canonical Wi-Fi table row")


def _validate_wifi_ofdm_profile(profile: WifiOFDMProfile) raises:
    """Reject mutable records that no longer equal one factory OFDM row."""
    var expected = wifi_ofdm_profile(profile.family, profile.bandwidth_mhz)
    if (
        profile.family != expected.family
        or profile.bandwidth_mhz != expected.bandwidth_mhz
        or profile.fft_size != expected.fft_size
        or profile.data_subcarriers != expected.data_subcarriers
        or profile.pilot_subcarriers != expected.pilot_subcarriers
        or profile.occupied_subcarriers != expected.occupied_subcarriers
        or profile.useful_symbol_ns != expected.useful_symbol_ns
        or profile.default_guard_interval_ns
        != expected.default_guard_interval_ns
        or profile.maximum_spatial_streams != expected.maximum_spatial_streams
    ):
        raise Error("OFDM profile does not match a canonical Wi-Fi table row")


def wifi_guard_interval_samples(profile: WifiOFDMProfile, guard_interval_ns: Int) raises -> Int:
    """Convert a standard guard interval to an exact sample count."""
    _validate_wifi_ofdm_profile(profile)
    if profile.family == WIFI_PHY_HT or profile.family == WIFI_PHY_VHT:
        if guard_interval_ns != 400 and guard_interval_ns != 800:
            raise Error("HT/VHT guard interval must be 400 or 800 ns")
    elif profile.family == WIFI_PHY_HE or profile.family == WIFI_PHY_EHT:
        if guard_interval_ns != 800 and guard_interval_ns != 1600 and guard_interval_ns != 3200:
            raise Error("HE/EHT guard interval must be 800, 1600, or 3200 ns")
    else:
        raise Error("unknown Wi-Fi PHY family")
    return profile.fft_size * guard_interval_ns // profile.useful_symbol_ns


def wifi_coded_bits_per_symbol(profile: WifiOFDMProfile, mcs: WifiMCSProfile) raises -> Int:
    """Return Ncbps over all spatial streams; DCM counts paired tones once."""
    _validate_wifi_ofdm_profile(profile)
    _validate_wifi_mcs_profile(mcs)
    if profile.family != mcs.family:
        raise Error("OFDM and MCS profiles belong to different PHY families")
    if mcs.duplicate_mode:
        # EHT MCS 14 sends a DCM-coded 40/80/160 MHz payload twice in a
        # non-punctured 80/160/320 MHz PPDU.  The 80 MHz case cannot be
        # inferred by simply halving full-band Nsd because its source RU-484
        # has 468 data tones rather than half of RU-996's 980.
        var source_data_subcarriers: Int
        if profile.bandwidth_mhz == 80:
            source_data_subcarriers = 468
        elif profile.bandwidth_mhz == 160:
            source_data_subcarriers = 980
        elif profile.bandwidth_mhz == 320:
            source_data_subcarriers = 1960
        else:
            raise Error("EHT MCS 14 DUP is defined for 80/160/320 MHz")
        return (
            source_data_subcarriers
            * mcs.bits_per_subcarrier
            * mcs.spatial_streams
            // 2
        )
    var divisor = 2 if mcs.dcm else 1
    return profile.data_subcarriers * mcs.bits_per_subcarrier * mcs.spatial_streams // divisor


def wifi_data_bits_per_symbol(profile: WifiOFDMProfile, mcs: WifiMCSProfile) raises -> Int:
    """Return Ndbps, rejecting fractional HT/VHT MCS/NSS combinations."""
    _validate_wifi_ofdm_profile(profile)
    _validate_wifi_mcs_profile(mcs)
    var coded = wifi_coded_bits_per_symbol(profile, mcs)
    var numerator = coded * mcs.code_rate_numerator
    if (
        profile.family == WIFI_PHY_HT or profile.family == WIFI_PHY_VHT
    ) and numerator % mcs.code_rate_denominator != 0:
        raise Error("MCS/NSS combination has no integral HT/VHT Ndbps")
    return numerator // mcs.code_rate_denominator
