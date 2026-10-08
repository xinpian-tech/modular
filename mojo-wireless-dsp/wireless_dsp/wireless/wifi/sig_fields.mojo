"""Bounded IEEE 802.11 HT and VHT SIGNAL-field arithmetic.

This CPU-only reference implements the discrete, pre-FEC information fields
that can be audited directly against IEEE Std 802.11-2024 Clause 19 (HT) and
Clause 21 (VHT): HT-SIG, single-user VHT-SIG-A, and the ordinary non-NDP
single-user VHT-SIG-B field.  Integer subfields are serialized least
significant bit first.  The common HT-SIG/VHT-SIG-A CRC is returned in the
conventional C7..C0 numeric order and serialized with C7 first.

The boundary is deliberately narrower than a complete PPDU implementation.
It excludes VHT MU field interpretations, the VHT NDP special SIG-B patterns,
80+80 MHz placement, BCC/interleaving/modulation, L-SIG duration spoofing,
RL-SIG, HE-SIG, U-SIG, EHT-SIG, and waveform generation.  The 160 MHz VHT
profile below is contiguous; its second 80 MHz SIG-B content copy is exposed
as geometry rather than silently synthesized.  These field serializers are
not a substitute for every TXVECTOR cross-field admissibility table; the
bounded geometry APIs reject only combinations whose stream count is fully
determined by their arguments.

Normative publication: IEEE Std 802.11-2024, Tables 19-11, 21-12, and 21-14;
Figures 19-6, 21-18, and 21-19; and subclauses 19.3.9.4.4, 21.3.4.5, and
21.3.4.8.  DOI 10.1109/IEEESTD.2025.10979691.
"""

from std.collections import Span


comptime WIFI_SIG_CODING_BCC = 0
comptime WIFI_SIG_CODING_LDPC = 1

comptime WIFI_SIG_CRC_INPUT_BITS = 34
comptime WIFI_SIG_CRC_BITS = 8
comptime WIFI_SIG_TAIL_BITS = 6
comptime WIFI_HT_SIG_BITS = 48
comptime WIFI_VHT_SIG_A_BITS = 48
comptime WIFI_VHT_MAX_APEP_OCTETS = 1_048_575


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


def _validate_bits(bits: Span[UInt8, ...], expected_length: Int, label: String) raises:
    if len(bits) != expected_length:
        raise Error(label + " has an invalid bit length")
    for index in range(len(bits)):
        if bits[index] > 1:
            raise Error(label + " must contain only zero and one")


def _validate_ht_mcs_and_bandwidth(mcs_index: Int, bandwidth_mhz: Int) raises:
    if mcs_index < 0 or mcs_index > 76:
        raise Error("HT-SIG MCS must be a defined index in [0,76]")
    if bandwidth_mhz != 20 and bandwidth_mhz != 40:
        raise Error("HT-SIG bandwidth must be 20 or 40 MHz")
    if mcs_index == 32 and bandwidth_mhz != 40:
        raise Error("HT MCS 32 duplicate mode is defined only for 40 MHz")


def _validate_sig_coding(coding: Int) raises:
    if coding != WIFI_SIG_CODING_BCC and coding != WIFI_SIG_CODING_LDPC:
        raise Error("SIGNAL coding must be BCC or LDPC")


def wifi_sig_crc8(bits: Span[UInt8, ...]) raises -> Int:
    """Return the Clause-19 CRC-8 over exactly 34 SIGNAL information bits.

    The shift registers C0..C7 start at one and use generator polynomial
    ``D^8 + D^2 + D + 1``.  The result is the complemented final state in
    conventional C7..C0 numeric order; C7 is transmitted first.
    """
    _validate_bits(bits, WIFI_SIG_CRC_INPUT_BITS, "SIGNAL CRC input")
    # Packed state bit i is Ci.  A left shift supplies C1'=C0 through
    # C7'=C6; feedback toggles C0, C1, and C2 (polynomial low byte 0x07).
    var state = 0xFF
    for index in range(WIFI_SIG_CRC_INPUT_BITS):
        var feedback = ((state >> 7) & 1) ^ Int(bits[index])
        state = ((state << 1) & 0xFE) ^ (0x07 if feedback != 0 else 0)

    var crc = 0
    for index in range(WIFI_SIG_CRC_BITS):
        var bit = ((state >> (7 - index)) & 1) ^ 1
        crc = (crc << 1) | bit
    return crc


def _append_crc_msb_first(mut output: List[UInt8], crc: Int):
    for index in range(WIFI_SIG_CRC_BITS):
        output.append(UInt8((crc >> (7 - index)) & 1))


def _read_crc_msb_first(bits: Span[UInt8, ...], offset: Int) -> Int:
    var crc = 0
    for index in range(WIFI_SIG_CRC_BITS):
        crc = (crc << 1) | Int(bits[offset + index])
    return crc


struct WifiHTSigFields(Movable):
    """Validated fields from one 48-bit HT-SIG information sequence."""

    var mcs_index: Int
    var bandwidth_mhz: Int
    var ht_length_octets: Int
    var smoothing: Bool
    var not_sounding: Bool
    var aggregation: Bool
    var stbc_streams: Int
    var fec_coding: Int
    var short_gi: Bool
    var extension_spatial_streams: Int
    var crc: Int

    def __init__(
        out self,
        mcs_index: Int,
        bandwidth_mhz: Int,
        ht_length_octets: Int,
        smoothing: Bool,
        not_sounding: Bool,
        aggregation: Bool,
        stbc_streams: Int,
        fec_coding: Int,
        short_gi: Bool,
        extension_spatial_streams: Int,
        crc: Int,
    ):
        self.mcs_index = mcs_index
        self.bandwidth_mhz = bandwidth_mhz
        self.ht_length_octets = ht_length_octets
        self.smoothing = smoothing
        self.not_sounding = not_sounding
        self.aggregation = aggregation
        self.stbc_streams = stbc_streams
        self.fec_coding = fec_coding
        self.short_gi = short_gi
        self.extension_spatial_streams = extension_spatial_streams
        self.crc = crc


def wifi_ht_sig_pack(
    mcs_index: Int,
    bandwidth_mhz: Int,
    ht_length_octets: Int,
    *,
    smoothing: Bool = True,
    not_sounding: Bool = True,
    aggregation: Bool = False,
    stbc_streams: Int = 0,
    fec_coding: Int = WIFI_SIG_CODING_BCC,
    short_gi: Bool = False,
    extension_spatial_streams: Int = 0,
) raises -> List[UInt8]:
    """Pack HT-SIG1/HT-SIG2 information bits, CRC, and zero tail.

    All defined raw MCS indices 0--76 are serializable.  Geometry for unequal
    modulation MCS 33--76 remains outside ``wifi_ht_sig_geometry``.
    """
    _validate_ht_mcs_and_bandwidth(mcs_index, bandwidth_mhz)
    if ht_length_octets < 0 or ht_length_octets > 65535:
        raise Error("HT Length must be an unsigned 16-bit value")
    if stbc_streams < 0 or stbc_streams > 2:
        raise Error("HT-SIG STBC field value three is reserved")
    _validate_sig_coding(fec_coding)
    if extension_spatial_streams < 0 or extension_spatial_streams > 3:
        raise Error("HT-SIG extension-spatial-stream field must be in [0,3]")

    var bits = List[UInt8](capacity=WIFI_HT_SIG_BITS)
    _append_unsigned_lsb(bits, mcs_index, 7)
    _append_bool(bits, bandwidth_mhz == 40)
    _append_unsigned_lsb(bits, ht_length_octets, 16)
    _append_bool(bits, smoothing)
    _append_bool(bits, not_sounding)
    bits.append(UInt8(1))  # Fixed bit B2 of HT-SIG2.
    _append_bool(bits, aggregation)
    _append_unsigned_lsb(bits, stbc_streams, 2)
    bits.append(UInt8(fec_coding))
    _append_bool(bits, short_gi)
    _append_unsigned_lsb(bits, extension_spatial_streams, 2)
    var crc = wifi_sig_crc8(Span(bits))
    _append_crc_msb_first(bits, crc)
    for _ in range(WIFI_SIG_TAIL_BITS):
        bits.append(UInt8(0))
    return bits^


def wifi_ht_sig_parse(bits: Span[UInt8, ...]) raises -> WifiHTSigFields:
    """Parse HT-SIG and reject invalid fixed, CRC, tail, or MCS fields."""
    _validate_bits(bits, WIFI_HT_SIG_BITS, "HT-SIG")
    if bits[26] != 1:
        raise Error("HT-SIG fixed bit must be one")
    for index in range(42, 48):
        if bits[index] != 0:
            raise Error("HT-SIG tail must be all zero")
    var expected_crc = wifi_sig_crc8(bits[0:34])
    var observed_crc = _read_crc_msb_first(bits, 34)
    if observed_crc != expected_crc:
        raise Error("HT-SIG CRC failure")

    var mcs_index = _read_unsigned_lsb(bits, 0, 7)
    var bandwidth_mhz = 40 if bits[7] != 0 else 20
    _validate_ht_mcs_and_bandwidth(mcs_index, bandwidth_mhz)
    var stbc_streams = _read_unsigned_lsb(bits, 28, 2)
    if stbc_streams > 2:
        raise Error("HT-SIG STBC field value three is reserved")
    var fec_coding = Int(bits[30])
    _validate_sig_coding(fec_coding)
    return WifiHTSigFields(
        mcs_index,
        bandwidth_mhz,
        _read_unsigned_lsb(bits, 8, 16),
        bits[24] != 0,
        bits[25] != 0,
        bits[27] != 0,
        stbc_streams,
        fec_coding,
        bits[31] != 0,
        _read_unsigned_lsb(bits, 32, 2),
        observed_crc,
    )


struct WifiHTSigGeometry(Movable):
    """Bounded HT-SIG and training-field geometry."""

    var signal_bits: Int
    var crc_covered_bits: Int
    var tail_bits: Int
    var signal_ofdm_symbols: Int
    var signal_duration_ns: Int
    var data_spatial_streams: Int
    var space_time_streams: Int
    var data_ltf_symbols: Int
    var extension_ltf_symbols: Int
    var total_ltf_symbols: Int

    def __init__(
        out self,
        data_spatial_streams: Int,
        space_time_streams: Int,
        data_ltf_symbols: Int,
        extension_ltf_symbols: Int,
    ):
        self.signal_bits = WIFI_HT_SIG_BITS
        self.crc_covered_bits = WIFI_SIG_CRC_INPUT_BITS
        self.tail_bits = WIFI_SIG_TAIL_BITS
        self.signal_ofdm_symbols = 2
        self.signal_duration_ns = 8000
        self.data_spatial_streams = data_spatial_streams
        self.space_time_streams = space_time_streams
        self.data_ltf_symbols = data_ltf_symbols
        self.extension_ltf_symbols = extension_ltf_symbols
        self.total_ltf_symbols = data_ltf_symbols + extension_ltf_symbols


def _ltf_symbol_count(streams: Int) raises -> Int:
    if streams == 0:
        return 0
    if streams == 1:
        return 1
    if streams == 2:
        return 2
    if streams == 3 or streams == 4:
        return 4
    raise Error("HT training geometry supports at most four streams")


def wifi_ht_sig_geometry(
    mcs_index: Int,
    bandwidth_mhz: Int,
    *,
    stbc_streams: Int = 0,
    extension_spatial_streams: Int = 0,
) raises -> WifiHTSigGeometry:
    """Return exact HT-SIG timing and equal-modulation/MCS-32 LTF geometry.

    MCS 33--76 field serialization is supported, but their unequal-modulation
    stream tuples are intentionally rejected here rather than guessed.
    """
    _validate_ht_mcs_and_bandwidth(mcs_index, bandwidth_mhz)
    if stbc_streams < 0 or stbc_streams > 2:
        raise Error("HT-SIG STBC field value three is reserved")
    if extension_spatial_streams < 0 or extension_spatial_streams > 3:
        raise Error("HT-SIG extension-spatial-stream field must be in [0,3]")
    if mcs_index > 32:
        raise Error("unequal-modulation HT MCS geometry is outside this bounded API")
    var data_spatial_streams = 1 if mcs_index == 32 else mcs_index // 8 + 1
    var space_time_streams = data_spatial_streams + stbc_streams
    if space_time_streams > 4:
        raise Error("HT data plus STBC streams exceed four space-time streams")
    if space_time_streams + extension_spatial_streams > 4:
        raise Error("HT data, STBC, and extension streams exceed four streams")
    return WifiHTSigGeometry(
        data_spatial_streams,
        space_time_streams,
        _ltf_symbol_count(space_time_streams),
        _ltf_symbol_count(extension_spatial_streams),
    )


struct WifiVHTSigASUFields(Movable):
    """Validated single-user interpretation of one VHT-SIG-A field."""

    var bandwidth_mhz: Int
    var stbc: Bool
    var group_id: Int
    var space_time_streams: Int
    var partial_aid: Int
    var txop_ps_not_allowed: Bool
    var short_gi: Bool
    var short_gi_nsym_disambiguation: Bool
    var coding: Int
    var ldpc_extra_ofdm_symbol: Bool
    var mcs_index: Int
    var beamformed: Bool
    var crc: Int

    def __init__(
        out self,
        bandwidth_mhz: Int,
        stbc: Bool,
        group_id: Int,
        space_time_streams: Int,
        partial_aid: Int,
        txop_ps_not_allowed: Bool,
        short_gi: Bool,
        short_gi_nsym_disambiguation: Bool,
        coding: Int,
        ldpc_extra_ofdm_symbol: Bool,
        mcs_index: Int,
        beamformed: Bool,
        crc: Int,
    ):
        self.bandwidth_mhz = bandwidth_mhz
        self.stbc = stbc
        self.group_id = group_id
        self.space_time_streams = space_time_streams
        self.partial_aid = partial_aid
        self.txop_ps_not_allowed = txop_ps_not_allowed
        self.short_gi = short_gi
        self.short_gi_nsym_disambiguation = short_gi_nsym_disambiguation
        self.coding = coding
        self.ldpc_extra_ofdm_symbol = ldpc_extra_ofdm_symbol
        self.mcs_index = mcs_index
        self.beamformed = beamformed
        self.crc = crc


def _vht_bandwidth_code(bandwidth_mhz: Int) raises -> Int:
    if bandwidth_mhz == 20:
        return 0
    if bandwidth_mhz == 40:
        return 1
    if bandwidth_mhz == 80:
        return 2
    if bandwidth_mhz == 160:
        return 3
    raise Error("bounded contiguous VHT bandwidth must be 20/40/80/160 MHz")


def _vht_bandwidth_from_code(code: Int) -> Int:
    if code == 0:
        return 20
    if code == 1:
        return 40
    if code == 2:
        return 80
    return 160


def _validate_vht_su_fields(
    group_id: Int,
    space_time_streams: Int,
    partial_aid: Int,
    stbc: Bool,
    short_gi: Bool,
    short_gi_nsym_disambiguation: Bool,
    coding: Int,
    ldpc_extra_ofdm_symbol: Bool,
    mcs_index: Int,
) raises:
    if group_id != 0 and group_id != 63:
        raise Error("single-user VHT-SIG-A group ID must be 0 or 63")
    if space_time_streams < 1 or space_time_streams > 8:
        raise Error("single-user VHT NSTS must represent one through eight streams")
    if stbc and space_time_streams % 2 != 0:
        raise Error("VHT STBC requires an even number of space-time streams")
    if partial_aid < 0 or partial_aid > 511:
        raise Error("VHT partial AID must be an unsigned 9-bit value")
    if short_gi_nsym_disambiguation and not short_gi:
        raise Error("VHT short-GI disambiguation requires short GI")
    _validate_sig_coding(coding)
    if ldpc_extra_ofdm_symbol and coding != WIFI_SIG_CODING_LDPC:
        raise Error("VHT LDPC extra-symbol flag requires LDPC coding")
    if mcs_index < 0 or mcs_index > 9:
        raise Error("single-user VHT MCS must be in [0,9]")


def wifi_vht_sig_a_su_pack(
    bandwidth_mhz: Int,
    space_time_streams: Int,
    partial_aid: Int,
    mcs_index: Int,
    *,
    group_id: Int = 63,
    stbc: Bool = False,
    txop_ps_not_allowed: Bool = True,
    short_gi: Bool = False,
    short_gi_nsym_disambiguation: Bool = False,
    coding: Int = WIFI_SIG_CODING_BCC,
    ldpc_extra_ofdm_symbol: Bool = False,
    beamformed: Bool = False,
) raises -> List[UInt8]:
    """Pack the SU interpretation of VHT-SIG-A1/A2 with CRC and tail."""
    var bandwidth_code = _vht_bandwidth_code(bandwidth_mhz)
    _validate_vht_su_fields(
        group_id,
        space_time_streams,
        partial_aid,
        stbc,
        short_gi,
        short_gi_nsym_disambiguation,
        coding,
        ldpc_extra_ofdm_symbol,
        mcs_index,
    )
    var bits = List[UInt8](capacity=WIFI_VHT_SIG_A_BITS)
    _append_unsigned_lsb(bits, bandwidth_code, 2)
    bits.append(UInt8(1))  # VHT-SIG-A1 B2 fixed to one.
    _append_bool(bits, stbc)
    _append_unsigned_lsb(bits, group_id, 6)
    _append_unsigned_lsb(bits, space_time_streams - 1, 3)
    _append_unsigned_lsb(bits, partial_aid, 9)
    _append_bool(bits, txop_ps_not_allowed)
    bits.append(UInt8(1))  # VHT-SIG-A1 B23 fixed to one.

    _append_bool(bits, short_gi)
    _append_bool(bits, short_gi_nsym_disambiguation)
    bits.append(UInt8(coding))
    _append_bool(bits, ldpc_extra_ofdm_symbol)
    _append_unsigned_lsb(bits, mcs_index, 4)
    _append_bool(bits, beamformed)
    bits.append(UInt8(1))  # VHT-SIG-A2 B9 fixed to one.
    var crc = wifi_sig_crc8(Span(bits))
    _append_crc_msb_first(bits, crc)
    for _ in range(WIFI_SIG_TAIL_BITS):
        bits.append(UInt8(0))
    return bits^


def wifi_vht_sig_a_su_parse(
    bits: Span[UInt8, ...]
) raises -> WifiVHTSigASUFields:
    """Parse SU VHT-SIG-A and reject MU, fixed, CRC, tail, and profile errors."""
    _validate_bits(bits, WIFI_VHT_SIG_A_BITS, "VHT-SIG-A")
    if bits[2] != 1 or bits[23] != 1 or bits[33] != 1:
        raise Error("VHT-SIG-A fixed bits must be one")
    for index in range(42, 48):
        if bits[index] != 0:
            raise Error("VHT-SIG-A tail must be all zero")
    var expected_crc = wifi_sig_crc8(bits[0:34])
    var observed_crc = _read_crc_msb_first(bits, 34)
    if observed_crc != expected_crc:
        raise Error("VHT-SIG-A CRC failure")

    var bandwidth_mhz = _vht_bandwidth_from_code(
        _read_unsigned_lsb(bits, 0, 2)
    )
    var stbc = bits[3] != 0
    var group_id = _read_unsigned_lsb(bits, 4, 6)
    var space_time_streams = _read_unsigned_lsb(bits, 10, 3) + 1
    var partial_aid = _read_unsigned_lsb(bits, 13, 9)
    var short_gi = bits[24] != 0
    var disambiguation = bits[25] != 0
    var coding = Int(bits[26])
    var extra_symbol = bits[27] != 0
    var mcs_index = _read_unsigned_lsb(bits, 28, 4)
    _validate_vht_su_fields(
        group_id,
        space_time_streams,
        partial_aid,
        stbc,
        short_gi,
        disambiguation,
        coding,
        extra_symbol,
        mcs_index,
    )
    return WifiVHTSigASUFields(
        bandwidth_mhz,
        stbc,
        group_id,
        space_time_streams,
        partial_aid,
        bits[22] != 0,
        short_gi,
        disambiguation,
        coding,
        extra_symbol,
        mcs_index,
        bits[32] != 0,
        observed_crc,
    )


struct WifiVHTSigASUGeometry(Movable):
    """Fixed SIG-A timing plus the SU VHT-LTF count implied by NSTS/STBC."""

    var signal_bits: Int
    var crc_covered_bits: Int
    var tail_bits: Int
    var signal_ofdm_symbols: Int
    var signal_duration_ns: Int
    var data_spatial_streams: Int
    var space_time_streams: Int
    var vht_ltf_symbols: Int

    def __init__(
        out self,
        data_spatial_streams: Int,
        space_time_streams: Int,
        vht_ltf_symbols: Int,
    ):
        self.signal_bits = WIFI_VHT_SIG_A_BITS
        self.crc_covered_bits = WIFI_SIG_CRC_INPUT_BITS
        self.tail_bits = WIFI_SIG_TAIL_BITS
        self.signal_ofdm_symbols = 2
        self.signal_duration_ns = 8000
        self.data_spatial_streams = data_spatial_streams
        self.space_time_streams = space_time_streams
        self.vht_ltf_symbols = vht_ltf_symbols


def wifi_vht_sig_a_su_geometry(
    space_time_streams: Int, *, stbc: Bool = False
) raises -> WifiVHTSigASUGeometry:
    """Return the exact SU VHT-SIG-A and VHT-LTF symbol geometry."""
    if space_time_streams < 1 or space_time_streams > 8:
        raise Error("single-user VHT NSTS must represent one through eight streams")
    if stbc and space_time_streams % 2 != 0:
        raise Error("VHT STBC requires an even number of space-time streams")
    var data_spatial_streams = (
        space_time_streams // 2 if stbc else space_time_streams
    )
    var ltf_symbols: Int
    if space_time_streams == 1:
        ltf_symbols = 1
    elif space_time_streams == 2:
        ltf_symbols = 2
    elif space_time_streams <= 4:
        ltf_symbols = 4
    elif space_time_streams <= 6:
        ltf_symbols = 6
    else:
        ltf_symbols = 8
    return WifiVHTSigASUGeometry(
        data_spatial_streams, space_time_streams, ltf_symbols
    )


struct WifiVHTSigBSUGeometry(Movable):
    """Per-content-channel SU VHT-SIG-B information/BCC-input geometry."""

    var bandwidth_mhz: Int
    var length_bits: Int
    var fixed_bits: Int
    var tail_bits: Int
    var base_field_bits: Int
    var base_field_repetitions: Int
    var zero_pad_bits: Int
    var bcc_input_bits: Int
    var coded_bpsk_bits: Int
    var content_copies: Int
    var signal_ofdm_symbols: Int
    var signal_duration_ns: Int

    def __init__(
        out self,
        bandwidth_mhz: Int,
        length_bits: Int,
        fixed_bits: Int,
        base_field_bits: Int,
        base_field_repetitions: Int,
        zero_pad_bits: Int,
        bcc_input_bits: Int,
        coded_bpsk_bits: Int,
        content_copies: Int,
    ):
        self.bandwidth_mhz = bandwidth_mhz
        self.length_bits = length_bits
        self.fixed_bits = fixed_bits
        self.tail_bits = WIFI_SIG_TAIL_BITS
        self.base_field_bits = base_field_bits
        self.base_field_repetitions = base_field_repetitions
        self.zero_pad_bits = zero_pad_bits
        self.bcc_input_bits = bcc_input_bits
        self.coded_bpsk_bits = coded_bpsk_bits
        self.content_copies = content_copies
        self.signal_ofdm_symbols = 1
        self.signal_duration_ns = 4000


def wifi_vht_sig_b_su_geometry(
    bandwidth_mhz: Int
) raises -> WifiVHTSigBSUGeometry:
    """Return ordinary SU VHT-SIG-B base-field and repetition geometry."""
    _ = _vht_bandwidth_code(bandwidth_mhz)
    if bandwidth_mhz == 20:
        return WifiVHTSigBSUGeometry(20, 17, 3, 26, 1, 0, 26, 52, 1)
    if bandwidth_mhz == 40:
        return WifiVHTSigBSUGeometry(40, 19, 2, 27, 2, 0, 54, 108, 1)
    if bandwidth_mhz == 80:
        return WifiVHTSigBSUGeometry(80, 21, 2, 29, 4, 1, 117, 234, 1)
    return WifiVHTSigBSUGeometry(160, 21, 2, 29, 4, 1, 117, 234, 2)


struct WifiVHTSigBSUFields(Movable):
    """Validated ordinary SU VHT-SIG-B base information field."""

    var bandwidth_mhz: Int
    var length_units_4_octets: Int
    var rounded_apep_length_octets: Int
    var base_field_bits: Int

    def __init__(
        out self,
        bandwidth_mhz: Int,
        length_units_4_octets: Int,
        rounded_apep_length_octets: Int,
        base_field_bits: Int,
    ):
        self.bandwidth_mhz = bandwidth_mhz
        self.length_units_4_octets = length_units_4_octets
        self.rounded_apep_length_octets = rounded_apep_length_octets
        self.base_field_bits = base_field_bits


def wifi_vht_sig_b_su_pack(
    apep_length_octets: Int, bandwidth_mhz: Int
) raises -> List[UInt8]:
    """Pack ordinary non-NDP SU VHT-SIG-B before repetition and BCC.

    APEP length is rounded up to a four-octet boundary, and only the resulting
    quotient is recoverable at the receiver.  Zero-length/NDP uses special
    Table-21-15 patterns and is rejected by this bounded API.
    """
    var geometry = wifi_vht_sig_b_su_geometry(bandwidth_mhz)
    if apep_length_octets < 1 or (
        apep_length_octets > WIFI_VHT_MAX_APEP_OCTETS
    ):
        raise Error("ordinary VHT APEP length must be in [1,1048575] octets")
    var length_units = (apep_length_octets + 3) // 4
    if length_units >= (1 << geometry.length_bits):
        raise Error("VHT-SIG-B Length does not fit the selected bandwidth")
    var bits = List[UInt8](capacity=geometry.base_field_bits)
    _append_unsigned_lsb(bits, length_units, geometry.length_bits)
    for _ in range(geometry.fixed_bits):
        bits.append(UInt8(1))
    for _ in range(WIFI_SIG_TAIL_BITS):
        bits.append(UInt8(0))
    return bits^


def wifi_vht_sig_b_su_parse(
    bits: Span[UInt8, ...], bandwidth_mhz: Int
) raises -> WifiVHTSigBSUFields:
    """Parse ordinary SU VHT-SIG-B and validate fixed and tail bits."""
    var geometry = wifi_vht_sig_b_su_geometry(bandwidth_mhz)
    _validate_bits(bits, geometry.base_field_bits, "SU VHT-SIG-B")
    var fixed_start = geometry.length_bits
    for index in range(fixed_start, fixed_start + geometry.fixed_bits):
        if bits[index] != 1:
            raise Error("SU VHT-SIG-B fixed bits must be all one")
    var tail_start = fixed_start + geometry.fixed_bits
    for index in range(tail_start, tail_start + WIFI_SIG_TAIL_BITS):
        if bits[index] != 0:
            raise Error("SU VHT-SIG-B tail must be all zero")
    var length_units = _read_unsigned_lsb(bits, 0, geometry.length_bits)
    if length_units == 0:
        raise Error("VHT NDP SIG-B pattern is outside this ordinary SU API")
    if length_units > (WIFI_VHT_MAX_APEP_OCTETS + 3) // 4:
        raise Error("SU VHT-SIG-B Length exceeds the bounded VHT APEP maximum")
    return WifiVHTSigBSUFields(
        bandwidth_mhz,
        length_units,
        length_units * 4,
        geometry.base_field_bits,
    )


def wifi_vht_sig_b_su_bcc_input(
    base_bits: Span[UInt8, ...], bandwidth_mhz: Int
) raises -> List[UInt8]:
    """Expand one ordinary SU SIG-B base field to the per-content BCC input.

    The 80 MHz form repeats its 29-bit field four times and appends one zero.
    Contiguous 160 MHz uses the same 117-bit input in each of two 80 MHz
    content copies; callers use ``content_copies`` from the geometry record.
    """
    var geometry = wifi_vht_sig_b_su_geometry(bandwidth_mhz)
    # Parsing supplies all fixed/tail validation and excludes the NDP form.
    _ = wifi_vht_sig_b_su_parse(base_bits, bandwidth_mhz)
    var expanded = List[UInt8](capacity=geometry.bcc_input_bits)
    for _ in range(geometry.base_field_repetitions):
        for index in range(len(base_bits)):
            expanded.append(base_bits[index])
    for _ in range(geometry.zero_pad_bits):
        expanded.append(UInt8(0))
    return expanded^
