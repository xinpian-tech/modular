"""Bounded HE/EHT SIGNAL information-field arithmetic.

This CPU-only reference implements three discrete pre-FEC boundaries:

* HE SU HE-SIG-A and a deliberately narrow HE ER SU profile;
* the 20 MHz, nonpunctured EHT SU interpretation of U-SIG; and
* the CRC/tail envelope shared by EHT-SIG Common encoding blocks and User
  Blocks, with caller-declared CRC-covered content length.

Integer fields are serialized least significant bit first.  The four-bit CRC
is the complemented C7..C4 portion of the Clause-27 eight-register SIGNAL CRC
state and is transmitted C7 first.  HE-SIG-A and U-SIG each protect 42 bits,
then carry four CRC bits and six zero tail bits.

The HE boundary is restricted to non-Doppler SU signaling.  Its ER profile is
restricted further to the 242-tone, one-spatial-stream form with MCS 0--2.
The special HE interpretation in which the DCM and STBC bits are both one is
outside this bounded profile; the raw combination is rejected rather than
misdescribed as an ordinary simultaneous application of DCM and STBC.
The EHT U-SIG boundary is exactly a 20 MHz, nonpunctured EHT SU transmission
using the EHT MU PPDU format; the PPDU Type And Compression Mode, Validate,
Disregard, version, bandwidth, and puncturing bits are therefore fixed and
checked.  Its type/compression code is also used by an EHT sounding NDP, so
the caller must establish the non-NDP context outside these information bits.
The EHT-SIG block API does not infer Common/User field boundaries, RU
allocation, user ordering, MCS, or symbol padding: the caller supplies the
already assembled CRC-covered content and its expected length.

MU/OFDMA allocation, TB, Trigger, NDP, Doppler/midamble signaling, preamble
puncturing, 80+80 MHz HE interpretation, wider-bandwidth U-SIG placement,
EHT-SIG field interpretation, BCC encoding, interleaving, modulation, and
waveform generation are outside this bounded module.

Normative publications: IEEE Std 802.11-2024 Clause 27 and IEEE Std
802.11be-2024 Clause 36.  Bit-level traceability was independently checked
against IEEE 802.11 working-group adopted-text/comment-resolution documents
11-16/0915r2, 11-18/0038r1, 11-20/1875r2, 11-22/0472r0,
11-23/0446r1, and 11-24/0260r1.
"""

from std.collections import Span


comptime WIFI_HE_EHT_SIG_CRC_INPUT_BITS = 42
comptime WIFI_HE_EHT_SIG_CRC_BITS = 4
comptime WIFI_HE_EHT_SIG_TAIL_BITS = 6
comptime WIFI_HE_SIG_A_BITS = 52
comptime WIFI_EHT_U_SIG_BITS = 52

comptime WIFI_HE_EHT_SIG_CODING_BCC = 0
comptime WIFI_HE_EHT_SIG_CODING_LDPC = 1

comptime WIFI_EHT_SIG_BLOCK_COMMON = 0
comptime WIFI_EHT_SIG_BLOCK_USER = 1


def _append_unsigned_lsb(mut output: List[UInt8], value: Int, width: Int):
    for index in range(width):
        output.append(UInt8((value >> index) & 1))


def _append_bool(mut output: List[UInt8], value: Bool):
    output.append(UInt8(1 if value else 0))


def _read_unsigned_lsb(
    bits: Span[UInt8, ...], offset: Int, width: Int
) -> Int:
    var value = 0
    for index in range(width):
        value |= Int(bits[offset + index]) << index
    return value


def _validate_bits(
    bits: Span[UInt8, ...], expected_length: Int, label: String
) raises:
    if len(bits) != expected_length:
        raise Error(label + " has an invalid bit length")
    for index in range(len(bits)):
        if bits[index] > 1:
            raise Error(label + " must contain only zero and one")


def _append_crc4_c7_first(mut output: List[UInt8], crc: Int):
    for index in range(WIFI_HE_EHT_SIG_CRC_BITS):
        output.append(UInt8((crc >> (3 - index)) & 1))


def _read_crc4_c7_first(bits: Span[UInt8, ...], offset: Int) -> Int:
    var crc = 0
    for index in range(WIFI_HE_EHT_SIG_CRC_BITS):
        crc = (crc << 1) | Int(bits[offset + index])
    return crc


def wifi_he_eht_sig_crc4(bits: Span[UInt8, ...]) raises -> Int:
    """Return complemented CRC state C7..C4, with C7 as the high bit.

    The input is one nonempty HE/EHT SIGNAL CRC-covered sequence.  The eight
    registers C0..C7 start at one and use ``D^8 + D^2 + D + 1``.  EHT-SIG
    block lengths are variable, so this primitive intentionally does not
    require 42 bits; HE-SIG-A and U-SIG packers do.
    """
    if len(bits) < 1:
        raise Error("HE/EHT SIGNAL CRC input must be nonempty")
    for index in range(len(bits)):
        if bits[index] > 1:
            raise Error("HE/EHT SIGNAL CRC input must contain only bits")

    # Packed state bit i is Ci.  The low byte 0x07 supplies feedback to
    # C0, C1, and C2 after the C7/input XOR.
    var state = 0xFF
    for index in range(len(bits)):
        var feedback = ((state >> 7) & 1) ^ Int(bits[index])
        state = ((state << 1) & 0xFE) ^ (0x07 if feedback != 0 else 0)

    var crc = 0
    for index in range(WIFI_HE_EHT_SIG_CRC_BITS):
        var bit = ((state >> (7 - index)) & 1) ^ 1
        crc = (crc << 1) | bit
    return crc


struct WifiHeSigASUConfig(ImplicitlyCopyable):
    """Mutable bounded HE SU/ER-SU HE-SIG-A input configuration.

    ``extended_range`` selects the restricted 242-tone ER profile.  The
    non-Doppler boundary encodes ``space_time_streams - 1`` directly in the
    three-bit NSTS field.  The DCM/STBC both-one special encoding is excluded.
    Every public API revalidates all mutable members.  The checks cover this
    declared subset, not every TXVECTOR cross-field admissibility table.
    """

    var extended_range: Bool
    var beam_change: Bool
    var uplink: Bool
    var mcs_index: Int
    var dcm: Bool
    var bss_color: Int
    var spatial_reuse: Int
    var bandwidth_mhz: Int
    var gi_ltf_code: Int
    var space_time_streams: Int
    var txop_code: Int
    var coding: Int
    var ldpc_extra_symbol: Bool
    var stbc: Bool
    var beamformed: Bool
    var pre_fec_padding_factor: Int
    var pe_disambiguity: Bool

    def __init__(
        out self,
        mcs_index: Int,
        *,
        extended_range: Bool = False,
        beam_change: Bool = False,
        uplink: Bool = False,
        dcm: Bool = False,
        bss_color: Int = 0,
        spatial_reuse: Int = 0,
        bandwidth_mhz: Int = 20,
        gi_ltf_code: Int = 0,
        space_time_streams: Int = 1,
        txop_code: Int = 127,
        coding: Int = WIFI_HE_EHT_SIG_CODING_BCC,
        ldpc_extra_symbol: Bool = False,
        stbc: Bool = False,
        beamformed: Bool = False,
        pre_fec_padding_factor: Int = 0,
        pe_disambiguity: Bool = False,
    ):
        self.extended_range = extended_range
        self.beam_change = beam_change
        self.uplink = uplink
        self.mcs_index = mcs_index
        self.dcm = dcm
        self.bss_color = bss_color
        self.spatial_reuse = spatial_reuse
        self.bandwidth_mhz = bandwidth_mhz
        self.gi_ltf_code = gi_ltf_code
        self.space_time_streams = space_time_streams
        self.txop_code = txop_code
        self.coding = coding
        self.ldpc_extra_symbol = ldpc_extra_symbol
        self.stbc = stbc
        self.beamformed = beamformed
        self.pre_fec_padding_factor = pre_fec_padding_factor
        self.pe_disambiguity = pe_disambiguity


def _validate_he_sig_a_su_config(config: WifiHeSigASUConfig) raises:
    if config.mcs_index < 0 or config.mcs_index > 11:
        raise Error("HE SU HE-SIG-A MCS must be in [0,11]")
    if (
        config.bandwidth_mhz != 20
        and config.bandwidth_mhz != 40
        and config.bandwidth_mhz != 80
        and config.bandwidth_mhz != 160
    ):
        raise Error("HE SU HE-SIG-A bandwidth must be 20, 40, 80, or 160 MHz")
    if config.bss_color < 0 or config.bss_color > 63:
        raise Error("HE SU HE-SIG-A BSS Color must be in [0,63]")
    if config.spatial_reuse < 0 or config.spatial_reuse > 15:
        raise Error("HE SU HE-SIG-A Spatial Reuse must be in [0,15]")
    if config.gi_ltf_code < 0 or config.gi_ltf_code > 3:
        raise Error("HE SU HE-SIG-A GI/LTF code must be in [0,3]")
    if config.space_time_streams < 1 or config.space_time_streams > 8:
        raise Error("HE SU HE-SIG-A spatial streams must be in [1,8]")
    if config.txop_code < 0 or config.txop_code > 127:
        raise Error("HE SU HE-SIG-A TXOP code must be in [0,127]")
    if (
        config.coding != WIFI_HE_EHT_SIG_CODING_BCC
        and config.coding != WIFI_HE_EHT_SIG_CODING_LDPC
    ):
        raise Error("HE SU HE-SIG-A coding must be BCC or LDPC")
    if config.pre_fec_padding_factor < 0 or config.pre_fec_padding_factor > 3:
        raise Error("HE SU HE-SIG-A pre-FEC padding factor must be in [0,3]")
    if config.dcm:
        if (
            config.mcs_index != 0
            and config.mcs_index != 1
            and config.mcs_index != 3
            and config.mcs_index != 4
        ):
            raise Error("HE SU DCM is defined only for MCS 0, 1, 3, or 4")
        if config.space_time_streams > 2:
            raise Error("HE SU DCM is defined only for one or two streams")
        if config.stbc:
            raise Error("bounded HE SU excludes the DCM/STBC both-one code")
    if config.ldpc_extra_symbol and config.coding != WIFI_HE_EHT_SIG_CODING_LDPC:
        raise Error("HE SU LDPC extra symbol requires LDPC coding")
    if config.extended_range:
        if config.bandwidth_mhz != 20:
            raise Error("bounded HE ER SU supports only the 242-tone 20 MHz form")
        if config.mcs_index > 2:
            raise Error("bounded 242-tone HE ER SU supports MCS 0 through 2")
        if config.space_time_streams != 1:
            raise Error("bounded HE ER SU supports exactly one spatial stream")


struct WifiHeSigASUFields(ImplicitlyCopyable):
    """Validated fields parsed from one bounded 52-bit HE-SIG-A sequence."""

    var extended_range: Bool
    var beam_change: Bool
    var uplink: Bool
    var mcs_index: Int
    var dcm: Bool
    var bss_color: Int
    var spatial_reuse: Int
    var bandwidth_mhz: Int
    var gi_ltf_code: Int
    var space_time_streams: Int
    var txop_code: Int
    var coding: Int
    var ldpc_extra_symbol: Bool
    var stbc: Bool
    var beamformed: Bool
    var pre_fec_padding_factor: Int
    var pe_disambiguity: Bool
    var crc: Int

    def __init__(out self, config: WifiHeSigASUConfig, crc: Int):
        self.extended_range = config.extended_range
        self.beam_change = config.beam_change
        self.uplink = config.uplink
        self.mcs_index = config.mcs_index
        self.dcm = config.dcm
        self.bss_color = config.bss_color
        self.spatial_reuse = config.spatial_reuse
        self.bandwidth_mhz = config.bandwidth_mhz
        self.gi_ltf_code = config.gi_ltf_code
        self.space_time_streams = config.space_time_streams
        self.txop_code = config.txop_code
        self.coding = config.coding
        self.ldpc_extra_symbol = config.ldpc_extra_symbol
        self.stbc = config.stbc
        self.beamformed = config.beamformed
        self.pre_fec_padding_factor = config.pre_fec_padding_factor
        self.pe_disambiguity = config.pe_disambiguity
        self.crc = crc


struct WifiHeSigAGeometry(ImplicitlyCopyable):
    """Uncoded HE-SIG-A bit and OFDM-symbol geometry."""

    var field_bits: Int
    var crc_covered_bits: Int
    var crc_bits: Int
    var tail_bits: Int
    var information_parts: Int
    var part_bits: Int
    var repetitions_per_part: Int
    var ofdm_symbols: Int
    var duration_ns: Int

    def __init__(out self, extended_range: Bool):
        self.field_bits = WIFI_HE_SIG_A_BITS
        self.crc_covered_bits = WIFI_HE_EHT_SIG_CRC_INPUT_BITS
        self.crc_bits = WIFI_HE_EHT_SIG_CRC_BITS
        self.tail_bits = WIFI_HE_EHT_SIG_TAIL_BITS
        self.information_parts = 2
        self.part_bits = 26
        self.repetitions_per_part = 2 if extended_range else 1
        self.ofdm_symbols = 4 if extended_range else 2
        self.duration_ns = 16_000 if extended_range else 8_000


def _he_bandwidth_code(bandwidth_mhz: Int) -> Int:
    if bandwidth_mhz == 20:
        return 0
    if bandwidth_mhz == 40:
        return 1
    if bandwidth_mhz == 80:
        return 2
    return 3


def wifi_he_sig_a_su_pack(config: WifiHeSigASUConfig) raises -> List[UInt8]:
    """Pack bounded HE SU/ER-SU HE-SIG-A information, CRC, and tail bits."""
    _validate_he_sig_a_su_config(config)
    var bits = List[UInt8](capacity=WIFI_HE_SIG_A_BITS)
    bits.append(UInt8(1))  # Format: HE SU; fixed one for HE ER SU.
    _append_bool(bits, config.beam_change)
    _append_bool(bits, config.uplink)
    _append_unsigned_lsb(bits, config.mcs_index, 4)
    _append_bool(bits, config.dcm)
    _append_unsigned_lsb(bits, config.bss_color, 6)
    bits.append(UInt8(1))  # Reserved fixed bit in HE-SIG-A1.
    _append_unsigned_lsb(bits, config.spatial_reuse, 4)
    _append_unsigned_lsb(bits, _he_bandwidth_code(config.bandwidth_mhz), 2)
    _append_unsigned_lsb(bits, config.gi_ltf_code, 2)
    # Doppler is outside this module, so the field is the direct NSTS-1 code.
    _append_unsigned_lsb(bits, config.space_time_streams - 1, 3)
    _append_unsigned_lsb(bits, config.txop_code, 7)
    bits.append(UInt8(config.coding))
    # With BCC this field is reserved and fixed to one.
    _append_bool(
        bits,
        True
        if config.coding == WIFI_HE_EHT_SIG_CODING_BCC
        else config.ldpc_extra_symbol,
    )
    _append_bool(bits, config.stbc)
    _append_bool(bits, config.beamformed)
    _append_unsigned_lsb(bits, config.pre_fec_padding_factor, 2)
    _append_bool(bits, config.pe_disambiguity)
    bits.append(UInt8(1))  # Reserved fixed bit in HE-SIG-A2.
    bits.append(UInt8(0))  # Doppler excluded by the bounded profile.
    var crc = wifi_he_eht_sig_crc4(Span(bits))
    _append_crc4_c7_first(bits, crc)
    for _ in range(WIFI_HE_EHT_SIG_TAIL_BITS):
        bits.append(UInt8(0))
    return bits^


def wifi_he_sig_a_su_parse(
    bits: Span[UInt8, ...], *, extended_range: Bool = False
) raises -> WifiHeSigASUFields:
    """Parse bounded HE-SIG-A and reject fixed-bit, CRC, tail, or profile errors.

    HE SU and the restricted ER-SU profile share these information bits; the
    caller supplies ``extended_range`` from the acquired repetition geometry.
    """
    _validate_bits(bits, WIFI_HE_SIG_A_BITS, "HE-SIG-A")
    if bits[0] != 1 or bits[14] != 1 or bits[40] != 1:
        raise Error("bounded HE SU HE-SIG-A fixed bits must be one")
    if bits[41] != 0:
        raise Error("bounded HE SU HE-SIG-A excludes Doppler signaling")
    for index in range(46, 52):
        if bits[index] != 0:
            raise Error("HE-SIG-A tail must be all zero")
    var expected_crc = wifi_he_eht_sig_crc4(bits[0:42])
    var observed_crc = _read_crc4_c7_first(bits, 42)
    if observed_crc != expected_crc:
        raise Error("HE-SIG-A CRC failure")

    var bandwidth_code = _read_unsigned_lsb(bits, 19, 2)
    var bandwidth_mhz = 20 << bandwidth_code
    var coding = Int(bits[33])
    if coding == WIFI_HE_EHT_SIG_CODING_BCC and bits[34] != 1:
        raise Error("HE-SIG-A BCC LDPC-extra fixed bit must be one")
    var config = WifiHeSigASUConfig(
        _read_unsigned_lsb(bits, 3, 4),
        extended_range=extended_range,
        beam_change=bits[1] != 0,
        uplink=bits[2] != 0,
        dcm=bits[7] != 0,
        bss_color=_read_unsigned_lsb(bits, 8, 6),
        spatial_reuse=_read_unsigned_lsb(bits, 15, 4),
        bandwidth_mhz=bandwidth_mhz,
        gi_ltf_code=_read_unsigned_lsb(bits, 21, 2),
        space_time_streams=_read_unsigned_lsb(bits, 23, 3) + 1,
        txop_code=_read_unsigned_lsb(bits, 26, 7),
        coding=coding,
        ldpc_extra_symbol=(
            bits[34] != 0 if coding == WIFI_HE_EHT_SIG_CODING_LDPC else False
        ),
        stbc=bits[35] != 0,
        beamformed=bits[36] != 0,
        pre_fec_padding_factor=_read_unsigned_lsb(bits, 37, 2),
        pe_disambiguity=bits[39] != 0,
    )
    _validate_he_sig_a_su_config(config)
    return WifiHeSigASUFields(config, observed_crc)


def wifi_he_sig_a_su_geometry(
    config: WifiHeSigASUConfig,
) raises -> WifiHeSigAGeometry:
    """Return exact bounded HE SU or repeated ER-SU HE-SIG-A geometry."""
    _validate_he_sig_a_su_config(config)
    return WifiHeSigAGeometry(config.extended_range)


struct WifiEhtUSigSU20Config(ImplicitlyCopyable):
    """Mutable U-SIG configuration for a 20 MHz EHT SU transmission.

    ``eht_sig_mcs_code`` is the two-bit field value: 0 is MCS 0, 1 is MCS 1,
    2 is MCS 3, and 3 is MCS 0 with DCM.  Every public API revalidates the
    mutable configuration.  Only raw field ranges are checked here; full
    EHT-SIG-MCS/symbol-count admissibility depends on the deliberately
    out-of-scope EHT-SIG content and PHY configuration.  Non-NDP context is
    likewise a caller-supplied acquisition precondition.
    """

    var uplink: Bool
    var bss_color: Int
    var txop_code: Int
    var eht_sig_mcs_code: Int
    var eht_sig_symbols: Int

    def __init__(
        out self,
        bss_color: Int,
        *,
        uplink: Bool = False,
        txop_code: Int = 127,
        eht_sig_mcs_code: Int = 0,
        eht_sig_symbols: Int = 1,
    ):
        self.uplink = uplink
        self.bss_color = bss_color
        self.txop_code = txop_code
        self.eht_sig_mcs_code = eht_sig_mcs_code
        self.eht_sig_symbols = eht_sig_symbols


def _validate_eht_u_sig_su_20_config(config: WifiEhtUSigSU20Config) raises:
    if config.bss_color < 0 or config.bss_color > 63:
        raise Error("EHT U-SIG BSS Color must be in [0,63]")
    if config.txop_code < 0 or config.txop_code > 127:
        raise Error("EHT U-SIG TXOP code must be in [0,127]")
    if config.eht_sig_mcs_code < 0 or config.eht_sig_mcs_code > 3:
        raise Error("EHT-SIG MCS field code must be in [0,3]")
    if config.eht_sig_symbols < 1 or config.eht_sig_symbols > 32:
        raise Error("Number Of EHT-SIG Symbols must be in [1,32]")


struct WifiEhtUSigSU20Fields(ImplicitlyCopyable):
    """Validated fields parsed from one bounded 52-bit EHT U-SIG."""

    var uplink: Bool
    var bss_color: Int
    var txop_code: Int
    var eht_sig_mcs_code: Int
    var eht_sig_symbols: Int
    var crc: Int

    def __init__(out self, config: WifiEhtUSigSU20Config, crc: Int):
        self.uplink = config.uplink
        self.bss_color = config.bss_color
        self.txop_code = config.txop_code
        self.eht_sig_mcs_code = config.eht_sig_mcs_code
        self.eht_sig_symbols = config.eht_sig_symbols
        self.crc = crc


struct WifiEhtUSigGeometry(ImplicitlyCopyable):
    """Uncoded and rate-one-half BCC geometry of the bounded U-SIG."""

    var field_bits: Int
    var crc_covered_bits: Int
    var crc_bits: Int
    var tail_bits: Int
    var information_parts: Int
    var part_bits: Int
    var bcc_coded_bits: Int
    var coded_bits_per_symbol: Int
    var ofdm_symbols: Int
    var duration_ns: Int

    def __init__(out self):
        self.field_bits = WIFI_EHT_U_SIG_BITS
        self.crc_covered_bits = WIFI_HE_EHT_SIG_CRC_INPUT_BITS
        self.crc_bits = WIFI_HE_EHT_SIG_CRC_BITS
        self.tail_bits = WIFI_HE_EHT_SIG_TAIL_BITS
        self.information_parts = 2
        self.part_bits = 26
        self.bcc_coded_bits = 104
        self.coded_bits_per_symbol = 52
        self.ofdm_symbols = 2
        self.duration_ns = 8_000


def wifi_eht_u_sig_su_20_pack(
    config: WifiEhtUSigSU20Config,
) raises -> List[UInt8]:
    """Pack bounded raw fields for nonpunctured 20 MHz EHT SU signaling."""
    _validate_eht_u_sig_su_20_config(config)
    var bits = List[UInt8](capacity=WIFI_EHT_U_SIG_BITS)
    _append_unsigned_lsb(bits, 0, 3)  # PHY Version Identifier: EHT.
    _append_unsigned_lsb(bits, 0, 3)  # Bandwidth: 20 MHz.
    _append_bool(bits, config.uplink)
    _append_unsigned_lsb(bits, config.bss_color, 6)
    _append_unsigned_lsb(bits, config.txop_code, 7)
    for _ in range(5):
        bits.append(UInt8(1))  # U-SIG-1 Disregard.
    bits.append(UInt8(1))  # U-SIG-1 Validate.

    _append_unsigned_lsb(bits, 1, 2)  # EHT SU, non-OFDMA.
    bits.append(UInt8(1))  # Validate.
    _append_unsigned_lsb(bits, 0, 5)  # No puncturing in 20 MHz.
    bits.append(UInt8(1))  # Validate.
    _append_unsigned_lsb(bits, config.eht_sig_mcs_code, 2)
    _append_unsigned_lsb(bits, config.eht_sig_symbols - 1, 5)
    var crc = wifi_he_eht_sig_crc4(Span(bits))
    _append_crc4_c7_first(bits, crc)
    for _ in range(WIFI_HE_EHT_SIG_TAIL_BITS):
        bits.append(UInt8(0))
    return bits^


def wifi_eht_u_sig_su_20_parse(
    bits: Span[UInt8, ...],
) raises -> WifiEhtUSigSU20Fields:
    """Parse bounded U-SIG after the caller has excluded sounding NDP context."""
    _validate_bits(bits, WIFI_EHT_U_SIG_BITS, "EHT U-SIG")
    if _read_unsigned_lsb(bits, 0, 3) != 0:
        raise Error("bounded U-SIG PHY Version Identifier must indicate EHT")
    if _read_unsigned_lsb(bits, 3, 3) != 0:
        raise Error("bounded EHT U-SIG bandwidth must indicate 20 MHz")
    for index in range(20, 25):
        if bits[index] != 1:
            raise Error("bounded EHT U-SIG Disregard bits must be one")
    if bits[25] != 1 or bits[28] != 1 or bits[34] != 1:
        raise Error("bounded EHT U-SIG Validate bits must be one")
    if _read_unsigned_lsb(bits, 26, 2) != 1:
        raise Error("bounded EHT U-SIG requires the SU-or-sounding-NDP code")
    if _read_unsigned_lsb(bits, 29, 5) != 0:
        raise Error("bounded EHT U-SIG requires no 20 MHz puncturing")
    for index in range(46, 52):
        if bits[index] != 0:
            raise Error("EHT U-SIG tail must be all zero")
    var expected_crc = wifi_he_eht_sig_crc4(bits[0:42])
    var observed_crc = _read_crc4_c7_first(bits, 42)
    if observed_crc != expected_crc:
        raise Error("EHT U-SIG CRC failure")
    var config = WifiEhtUSigSU20Config(
        _read_unsigned_lsb(bits, 7, 6),
        uplink=bits[6] != 0,
        txop_code=_read_unsigned_lsb(bits, 13, 7),
        eht_sig_mcs_code=_read_unsigned_lsb(bits, 35, 2),
        eht_sig_symbols=_read_unsigned_lsb(bits, 37, 5) + 1,
    )
    _validate_eht_u_sig_su_20_config(config)
    return WifiEhtUSigSU20Fields(config, observed_crc)


def wifi_eht_u_sig_su_20_geometry(
    config: WifiEhtUSigSU20Config,
) raises -> WifiEhtUSigGeometry:
    """Return exact two-symbol U-SIG geometry after revalidating the profile."""
    _validate_eht_u_sig_su_20_config(config)
    return WifiEhtUSigGeometry()


struct WifiEhtSigBlockProfile(ImplicitlyCopyable):
    """Mutable declared boundary of one EHT-SIG CRC-protected block.

    ``kind`` distinguishes a Common encoding block from a User Block for
    evidence and diagnostics only.  ``content_bits`` is the exact number of
    caller-assembled bits covered by CRC; this API does not infer it.
    """

    var kind: Int
    var content_bits: Int

    def __init__(out self, kind: Int, content_bits: Int):
        self.kind = kind
        self.content_bits = content_bits


def _validate_eht_sig_block_profile(profile: WifiEhtSigBlockProfile) raises:
    if (
        profile.kind != WIFI_EHT_SIG_BLOCK_COMMON
        and profile.kind != WIFI_EHT_SIG_BLOCK_USER
    ):
        raise Error("EHT-SIG block kind must be Common or User")
    if profile.content_bits < 1:
        raise Error("EHT-SIG CRC-covered content must be nonempty")
    if profile.content_bits > Int.MAX - 10:
        raise Error("EHT-SIG block bit length overflows Int")


struct WifiEhtSigBlock(Movable):
    """Validated EHT-SIG block content and its observed four-bit CRC."""

    var kind: Int
    var content: List[UInt8]
    var crc: Int

    def __init__(
        out self, kind: Int, var content: List[UInt8], crc: Int
    ):
        self.kind = kind
        self.content = content^
        self.crc = crc


struct WifiEhtSigBlockGeometry(ImplicitlyCopyable):
    """Uncoded bit geometry of one caller-declared EHT-SIG CRC block."""

    var kind: Int
    var content_bits: Int
    var crc_bits: Int
    var tail_bits: Int
    var total_bits: Int

    def __init__(out self, profile: WifiEhtSigBlockProfile):
        self.kind = profile.kind
        self.content_bits = profile.content_bits
        self.crc_bits = WIFI_HE_EHT_SIG_CRC_BITS
        self.tail_bits = WIFI_HE_EHT_SIG_TAIL_BITS
        self.total_bits = profile.content_bits + 10


def wifi_eht_sig_block_pack(
    profile: WifiEhtSigBlockProfile, content: Span[UInt8, ...]
) raises -> List[UInt8]:
    """Append the Clause-36 four-bit CRC and six zero tail bits to content."""
    _validate_eht_sig_block_profile(profile)
    _validate_bits(content, profile.content_bits, "EHT-SIG block content")
    var bits = List[UInt8](capacity=profile.content_bits + 10)
    for index in range(len(content)):
        bits.append(content[index])
    var crc = wifi_he_eht_sig_crc4(content)
    _append_crc4_c7_first(bits, crc)
    for _ in range(WIFI_HE_EHT_SIG_TAIL_BITS):
        bits.append(UInt8(0))
    return bits^


def wifi_eht_sig_block_parse(
    profile: WifiEhtSigBlockProfile, bits: Span[UInt8, ...]
) raises -> WifiEhtSigBlock:
    """Parse one declared EHT-SIG CRC block and reject CRC/tail failures."""
    _validate_eht_sig_block_profile(profile)
    _validate_bits(bits, profile.content_bits + 10, "EHT-SIG block")
    for index in range(profile.content_bits + 4, profile.content_bits + 10):
        if bits[index] != 0:
            raise Error("EHT-SIG block tail must be all zero")
    var expected_crc = wifi_he_eht_sig_crc4(bits[0:profile.content_bits])
    var observed_crc = _read_crc4_c7_first(bits, profile.content_bits)
    if observed_crc != expected_crc:
        raise Error("EHT-SIG block CRC failure")
    var content = List[UInt8](capacity=profile.content_bits)
    for index in range(profile.content_bits):
        content.append(bits[index])
    return WifiEhtSigBlock(profile.kind, content^, observed_crc)


def wifi_eht_sig_block_geometry(
    profile: WifiEhtSigBlockProfile,
) raises -> WifiEhtSigBlockGeometry:
    """Return exact uncoded CRC-block geometry after profile revalidation."""
    _validate_eht_sig_block_profile(profile)
    return WifiEhtSigBlockGeometry(profile)
