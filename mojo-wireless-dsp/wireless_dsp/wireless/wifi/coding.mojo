"""Wi-Fi BCC puncturing and HT/VHT/HE/EHT frequency interleaving.

The mother code and Viterbi engine remain protocol-independent in
``wireless_dsp.fec``.  This module supplies the IEEE 802.11 puncturing matrices
and per-PHY interleaver dimensions/stream rotations (IEEE Std 802.11-2024
Clauses 19, 21, and 27, plus IEEE Std 802.11be-2024 Clause 36).
"""

from std.collections import Span
from wireless_dsp.fec import puncture_bits, depuncture_llrs
from .profiles import WIFI_PHY_HT, WIFI_PHY_VHT, WIFI_PHY_HE, WIFI_PHY_EHT


struct WifiBCCInterleaverProfile(Movable):
    var family: Int
    var block_data_subcarriers: Int
    var columns: Int
    var rows_per_modulation_bit: Int
    var rotation_subcarriers: Int
    var blocks_per_symbol: Int
    var dcm: Bool

    def __init__(
        out self,
        family: Int,
        block_data_subcarriers: Int,
        columns: Int,
        rows_per_modulation_bit: Int,
        rotation_subcarriers: Int,
        blocks_per_symbol: Int,
        dcm: Bool,
    ):
        self.family = family
        self.block_data_subcarriers = block_data_subcarriers
        self.columns = columns
        self.rows_per_modulation_bit = rows_per_modulation_bit
        self.rotation_subcarriers = rotation_subcarriers
        self.blocks_per_symbol = blocks_per_symbol
        self.dcm = dcm


def wifi_bcc_puncture_pattern(
    rate_numerator: Int, rate_denominator: Int
) raises -> List[UInt8]:
    """Return the serialized [A0,B0,A1,B1,...] BCC puncturing pattern."""
    var result: List[UInt8]
    if rate_numerator == 1 and rate_denominator == 2:
        result = [1, 1]
    elif rate_numerator == 2 and rate_denominator == 3:
        result = [1, 1, 1, 0]
    elif rate_numerator == 3 and rate_denominator == 4:
        result = [1, 1, 1, 0, 0, 1]
    elif rate_numerator == 5 and rate_denominator == 6:
        result = [1, 1, 1, 0, 0, 1, 1, 0, 0, 1]
    else:
        raise Error("unsupported Wi-Fi BCC coding rate")
    return result^


def wifi_bcc_puncture(
    mother_bits: Span[UInt8, ...], rate_numerator: Int, rate_denominator: Int
) raises -> List[UInt8]:
    var pattern = wifi_bcc_puncture_pattern(rate_numerator, rate_denominator)
    return puncture_bits(mother_bits, Span(pattern))


def wifi_bcc_depuncture_llrs(
    llrs: Span[Float64, ...],
    mother_length: Int,
    rate_numerator: Int,
    rate_denominator: Int,
) raises -> List[Float64]:
    """Insert zero-erasure LLRs at punctured mother-code positions."""
    var pattern = wifi_bcc_puncture_pattern(rate_numerator, rate_denominator)
    return depuncture_llrs(llrs, Span(pattern), mother_length)


def wifi_bcc_interleaver_profile(
    family: Int, bandwidth_mhz: Int, *, ru_tones: Int = 0, dcm: Bool = False
) raises -> WifiBCCInterleaverProfile:
    """Return the BCC interleaver block geometry for a PHY or HE/EHT RU.

    A VHT 160 MHz symbol comprises two independent 80 MHz interleaver blocks.
    HE/EHT BCC is intentionally rejected above RU-242; those allocations use
    LDPC rather than pretending a larger BCC interleaver is standardized.
    """
    if family == WIFI_PHY_HT:
        if dcm:
            raise Error("HT does not define DCM")
        if ru_tones != 0:
            raise Error("HT BCC interleaving does not use resource units")
        if bandwidth_mhz == 20:
            return WifiBCCInterleaverProfile(family, 52, 13, 4, 11, 1, False)
        if bandwidth_mhz == 40:
            return WifiBCCInterleaverProfile(family, 108, 18, 6, 29, 1, False)
        raise Error("unsupported HT BCC bandwidth")
    if family == WIFI_PHY_VHT:
        if dcm:
            raise Error("VHT does not define DCM")
        if ru_tones != 0:
            raise Error("VHT BCC interleaving does not use resource units")
        if bandwidth_mhz == 20:
            return WifiBCCInterleaverProfile(family, 52, 13, 4, 11, 1, False)
        if bandwidth_mhz == 40:
            return WifiBCCInterleaverProfile(family, 108, 18, 6, 29, 1, False)
        if bandwidth_mhz == 80:
            return WifiBCCInterleaverProfile(family, 234, 26, 9, 58, 1, False)
        if bandwidth_mhz == 160:
            return WifiBCCInterleaverProfile(family, 234, 26, 9, 58, 2, False)
        raise Error("unsupported VHT BCC bandwidth")
    if family != WIFI_PHY_HE and family != WIFI_PHY_EHT:
        raise Error("unknown Wi-Fi PHY family")
    if (
        bandwidth_mhz != 20
        and bandwidth_mhz != 40
        and bandwidth_mhz != 80
        and bandwidth_mhz != 160
        and not (family == WIFI_PHY_EHT and bandwidth_mhz == 320)
    ):
        raise Error("unsupported HE/EHT BCC bandwidth")
    if dcm:
        if ru_tones == 26:
            return WifiBCCInterleaverProfile(family, 12, 4, 3, 2, 1, True)
        if ru_tones == 52:
            return WifiBCCInterleaverProfile(family, 24, 8, 3, 2, 1, True)
        if ru_tones == 106:
            return WifiBCCInterleaverProfile(family, 51, 17, 3, 11, 1, True)
        if ru_tones == 242:
            return WifiBCCInterleaverProfile(family, 117, 13, 9, 29, 1, True)
    elif ru_tones == 26:
        return WifiBCCInterleaverProfile(family, 24, 8, 3, 2, 1, False)
    elif ru_tones == 52:
        return WifiBCCInterleaverProfile(family, 48, 16, 3, 11, 1, False)
    elif ru_tones == 106:
        return WifiBCCInterleaverProfile(family, 102, 17, 6, 29, 1, False)
    elif ru_tones == 242:
        return WifiBCCInterleaverProfile(family, 234, 26, 9, 58, 1, False)
    raise Error("HE/EHT BCC interleaving is defined only through RU-242")


def _wifi_bcc_profiles_equal(
    lhs: WifiBCCInterleaverProfile, rhs: WifiBCCInterleaverProfile
) -> Bool:
    return (
        lhs.family == rhs.family
        and lhs.block_data_subcarriers == rhs.block_data_subcarriers
        and lhs.columns == rhs.columns
        and lhs.rows_per_modulation_bit == rhs.rows_per_modulation_bit
        and lhs.rotation_subcarriers == rhs.rotation_subcarriers
        and lhs.blocks_per_symbol == rhs.blocks_per_symbol
        and lhs.dcm == rhs.dcm
    )


def _is_canonical_signal_interleaver(
    profile: WifiBCCInterleaverProfile,
) -> Bool:
    """Match only the standard HE/EHT SIGNAL 56-tone geometry.

    This internal SIGNAL row is not a data-profile factory row: its third
    permutation has zero stream rotation.  Keep the exception exact across all
    seven fields so no nearby mutable data profile is admitted.
    """
    return (
        (profile.family == WIFI_PHY_HE or profile.family == WIFI_PHY_EHT)
        and profile.block_data_subcarriers == 52
        and profile.columns == 13
        and profile.rows_per_modulation_bit == 4
        and profile.rotation_subcarriers == 0
        and profile.blocks_per_symbol == 1
        and not profile.dcm
    )


def _validate_wifi_bcc_interleaver_profile(
    profile: WifiBCCInterleaverProfile,
) raises:
    """Require an exact factory data row or the one exact SIGNAL row."""
    if profile.family == WIFI_PHY_HT:
        if _wifi_bcc_profiles_equal(
            profile, wifi_bcc_interleaver_profile(WIFI_PHY_HT, 20)
        ) or _wifi_bcc_profiles_equal(
            profile, wifi_bcc_interleaver_profile(WIFI_PHY_HT, 40)
        ):
            return
    elif profile.family == WIFI_PHY_VHT:
        if (
            _wifi_bcc_profiles_equal(
                profile, wifi_bcc_interleaver_profile(WIFI_PHY_VHT, 20)
            )
            or _wifi_bcc_profiles_equal(
                profile, wifi_bcc_interleaver_profile(WIFI_PHY_VHT, 40)
            )
            or _wifi_bcc_profiles_equal(
                profile, wifi_bcc_interleaver_profile(WIFI_PHY_VHT, 80)
            )
            or _wifi_bcc_profiles_equal(
                profile, wifi_bcc_interleaver_profile(WIFI_PHY_VHT, 160)
            )
        ):
            return
    elif profile.family == WIFI_PHY_HE or profile.family == WIFI_PHY_EHT:
        if _is_canonical_signal_interleaver(profile):
            return
        if (
            _wifi_bcc_profiles_equal(
                profile,
                wifi_bcc_interleaver_profile(
                    profile.family, 20, ru_tones=26, dcm=False
                ),
            )
            or _wifi_bcc_profiles_equal(
                profile,
                wifi_bcc_interleaver_profile(
                    profile.family, 20, ru_tones=52, dcm=False
                ),
            )
            or _wifi_bcc_profiles_equal(
                profile,
                wifi_bcc_interleaver_profile(
                    profile.family, 20, ru_tones=106, dcm=False
                ),
            )
            or _wifi_bcc_profiles_equal(
                profile,
                wifi_bcc_interleaver_profile(
                    profile.family, 20, ru_tones=242, dcm=False
                ),
            )
            or _wifi_bcc_profiles_equal(
                profile,
                wifi_bcc_interleaver_profile(
                    profile.family, 20, ru_tones=26, dcm=True
                ),
            )
            or _wifi_bcc_profiles_equal(
                profile,
                wifi_bcc_interleaver_profile(
                    profile.family, 20, ru_tones=52, dcm=True
                ),
            )
            or _wifi_bcc_profiles_equal(
                profile,
                wifi_bcc_interleaver_profile(
                    profile.family, 20, ru_tones=106, dcm=True
                ),
            )
            or _wifi_bcc_profiles_equal(
                profile,
                wifi_bcc_interleaver_profile(
                    profile.family, 20, ru_tones=242, dcm=True
                ),
            )
        ):
            return
    raise Error("BCC interleaver profile is not a canonical Wi-Fi table row")


def _validate_bcc_modulation(
    profile: WifiBCCInterleaverProfile,
    bits_per_subcarrier: Int,
    spatial_stream_index: Int,
) raises:
    if profile.family == WIFI_PHY_HT and spatial_stream_index >= 4:
        raise Error("HT BCC supports at most four spatial streams")
    if profile.family == WIFI_PHY_VHT and spatial_stream_index >= 8:
        raise Error("VHT BCC supports at most eight spatial streams")
    if (
        profile.family == WIFI_PHY_HE or profile.family == WIFI_PHY_EHT
    ) and spatial_stream_index >= 4:
        raise Error("HE/EHT BCC supports at most four spatial streams")
    if profile.dcm:
        if (
            bits_per_subcarrier != 1
            and bits_per_subcarrier != 2
            and bits_per_subcarrier != 4
        ):
            raise Error("DCM supports BPSK, QPSK, or 16-QAM")
        if profile.family == WIFI_PHY_EHT and bits_per_subcarrier != 1:
            raise Error("EHT DCM MCS 14/15 use BPSK")
        if profile.family == WIFI_PHY_EHT and spatial_stream_index != 0:
            raise Error("EHT MCS 14/15 DCM is defined for one spatial stream")
        if spatial_stream_index > 1:
            raise Error("DCM supports at most two spatial streams")
    elif profile.family == WIFI_PHY_HT:
        if (
            bits_per_subcarrier != 1
            and bits_per_subcarrier != 2
            and bits_per_subcarrier != 4
            and bits_per_subcarrier != 6
        ):
            raise Error("HT BCC supports BPSK through 64-QAM")
    elif (
        bits_per_subcarrier != 1
        and bits_per_subcarrier != 2
        and bits_per_subcarrier != 4
        and bits_per_subcarrier != 6
        and bits_per_subcarrier != 8
    ):
        raise Error("VHT/HE/EHT BCC supports BPSK through 256-QAM")


def wifi_bcc_interleave_block(
    bits: Span[UInt8, ...],
    bits_per_subcarrier: Int,
    profile: WifiBCCInterleaverProfile,
    *,
    spatial_stream_index: Int = 0,
) raises -> List[UInt8]:
    """Apply all three BCC permutations to one per-stream interleaver block."""
    _validate_wifi_bcc_interleaver_profile(profile)
    if bits_per_subcarrier < 1 or spatial_stream_index < 0:
        raise Error("invalid BCC interleaver modulation or stream index")
    _validate_bcc_modulation(profile, bits_per_subcarrier, spatial_stream_index)
    var coded_bits = profile.block_data_subcarriers * bits_per_subcarrier
    var rows = profile.rows_per_modulation_bit * bits_per_subcarrier
    if len(bits) != coded_bits or rows * profile.columns != coded_bits:
        raise Error("BCC input must contain exactly one interleaver block")
    var s = max(bits_per_subcarrier // 2, 1)
    var stream_rotation = (
        ((2 * spatial_stream_index) % 3 + 3 * (spatial_stream_index // 3))
        * profile.rotation_subcarriers
        * bits_per_subcarrier
    ) % coded_bits
    var result = List[UInt8](length=coded_bits, fill=UInt8(0))
    for k in range(coded_bits):
        if bits[k] > 1:
            raise Error("BCC interleaver input must be binary")
        var first = rows * (k % profile.columns) + k // profile.columns
        var second = (
            s * (first // s)
            + (first + coded_bits - (profile.columns * first) // coded_bits) % s
        )
        var rotated = (second + coded_bits - stream_rotation) % coded_bits
        result[rotated] = bits[k]
    return result^


def wifi_bcc_deinterleave_block(
    bits: Span[UInt8, ...],
    bits_per_subcarrier: Int,
    profile: WifiBCCInterleaverProfile,
    *,
    spatial_stream_index: Int = 0,
) raises -> List[UInt8]:
    """Invert the three BCC interleaver permutations for one block."""
    _validate_wifi_bcc_interleaver_profile(profile)
    if bits_per_subcarrier < 1 or spatial_stream_index < 0:
        raise Error("invalid BCC deinterleaver modulation or stream index")
    _validate_bcc_modulation(profile, bits_per_subcarrier, spatial_stream_index)
    var coded_bits = profile.block_data_subcarriers * bits_per_subcarrier
    var rows = profile.rows_per_modulation_bit * bits_per_subcarrier
    if len(bits) != coded_bits or rows * profile.columns != coded_bits:
        raise Error("BCC input must contain exactly one interleaver block")
    var s = max(bits_per_subcarrier // 2, 1)
    var stream_rotation = (
        ((2 * spatial_stream_index) % 3 + 3 * (spatial_stream_index // 3))
        * profile.rotation_subcarriers
        * bits_per_subcarrier
    ) % coded_bits
    var result = List[UInt8](length=coded_bits, fill=UInt8(0))
    for k in range(coded_bits):
        var first = rows * (k % profile.columns) + k // profile.columns
        var second = (
            s * (first // s)
            + (first + coded_bits - (profile.columns * first) // coded_bits) % s
        )
        var rotated = (second + coded_bits - stream_rotation) % coded_bits
        if bits[rotated] > 1:
            raise Error("BCC deinterleaver input must be binary")
        result[k] = bits[rotated]
    return result^
