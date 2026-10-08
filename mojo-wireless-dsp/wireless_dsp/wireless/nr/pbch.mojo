"""NR BCH/PBCH transmit and receive reference chain.

This module follows TS 38.212 clauses 7.1.1--7.1.5 and TS 38.211 clause
7.3.3.1.  Bit indices are kept in the specification's MSB-first convention.
"""

from std.collections import Span
from std.math import isfinite
from wireless_dsp.fec.polar import polar_encode
from wireless_dsp.fec.polar_5g import (
    polar_5g_frozen_mask,
    polar_5g_input_interleave,
    polar_5g_rate_match,
    polar_5g_decode_sc,
)
from wireless_dsp.modem import crc_bits, crc_append, crc_check
from wireless_dsp.testing.checkpoint import (
    CheckpointMetadata,
    checkpoint_metadata_1d,
)
from .sequences import nr_gold_bits


comptime _PBCH_PAYLOAD_BITS = 32
comptime _PBCH_CRC_BITS = 24
comptime _PBCH_INFORMATION_BITS = 56
comptime _PBCH_MOTHER_BITS = 512
comptime _PBCH_RATE_MATCHED_BITS = 864
comptime _CRC24C_POLYNOMIAL = UInt64(0xB2B117)


struct NRPBCHTransmitBlock(Movable):
    """Specification checkpoints for one BCH/PBCH transmission."""

    var payload: List[UInt8]
    var interleaved_payload: List[UInt8]
    var payload_scrambled: List[UInt8]
    var crc_attached: List[UInt8]
    var polar_codeword: List[UInt8]
    var rate_matched: List[UInt8]
    var physical_channel_bits: List[UInt8]
    var checkpoint_metadata: List[CheckpointMetadata]

    def __init__(
        out self,
        var payload: List[UInt8],
        var interleaved_payload: List[UInt8],
        var payload_scrambled: List[UInt8],
        var crc_attached: List[UInt8],
        var polar_codeword: List[UInt8],
        var rate_matched: List[UInt8],
        var physical_channel_bits: List[UInt8],
        var checkpoint_metadata: List[CheckpointMetadata],
    ):
        self.payload = payload^
        self.interleaved_payload = interleaved_payload^
        self.payload_scrambled = payload_scrambled^
        self.crc_attached = crc_attached^
        self.polar_codeword = polar_codeword^
        self.rate_matched = rate_matched^
        self.physical_channel_bits = physical_channel_bits^
        self.checkpoint_metadata = checkpoint_metadata^


struct NRPBCHDecodeResult(Movable):
    """Decoded PBCH fields plus the CRC verdict and recovered K-bit block."""

    var mib_bits: List[UInt8]
    var payload: List[UInt8]
    var decoded_information: List[UInt8]
    var checkpoint_metadata: List[CheckpointMetadata]
    var system_frame_number: Int
    var half_frame: Int
    var ssb_index: Int
    var k_ssb_msb: Int
    var crc_ok: Bool

    def __init__(
        out self,
        var mib_bits: List[UInt8],
        var payload: List[UInt8],
        var decoded_information: List[UInt8],
        var checkpoint_metadata: List[CheckpointMetadata],
        system_frame_number: Int,
        half_frame: Int,
        ssb_index: Int,
        k_ssb_msb: Int,
        crc_ok: Bool,
    ):
        self.mib_bits = mib_bits^
        self.payload = payload^
        self.decoded_information = decoded_information^
        self.checkpoint_metadata = checkpoint_metadata^
        self.system_frame_number = system_frame_number
        self.half_frame = half_frame
        self.ssb_index = ssb_index
        self.k_ssb_msb = k_ssb_msb
        self.crc_ok = crc_ok


def _nr_pbch_tx_checkpoint_metadata(
    testcase_id: StringSlice,
    mib_input: Int,
    payload: Int,
    interleaved_payload: Int,
    payload_scrambled: Int,
    crc_attached: Int,
    polar_codeword: Int,
    rate_matched: Int,
    physical_channel_bits: Int,
) raises -> List[CheckpointMetadata]:
    var result = List[CheckpointMetadata](capacity=8)
    for stage, length in [
        ("mib-input", mib_input),
        ("payload", payload),
        ("interleaved-payload", interleaved_payload),
        ("payload-scrambled", payload_scrambled),
        ("crc-attached-information", crc_attached),
        ("polar-codeword", polar_codeword),
        ("rate-matched-bits", rate_matched),
        ("physical-channel-bits", physical_channel_bits),
    ]:
        result.append(checkpoint_metadata_1d(
            testcase_id,
            stage,
            "uint8",
            length,
            q_format="binary-u1",
            layout="bit-per-byte",
        ))
    return result^


def _nr_pbch_rx_checkpoint_metadata(
    testcase_id: StringSlice,
    physical_channel_llrs: Int,
    physical_descrambled_llrs: Int,
    decoded_information: Int,
    payload: Int,
    mib_bits: Int,
) raises -> List[CheckpointMetadata]:
    var result = List[CheckpointMetadata](capacity=7)
    result.append(checkpoint_metadata_1d(
        testcase_id,
        "physical-channel-llrs",
        "float64",
        physical_channel_llrs,
    ))
    result.append(checkpoint_metadata_1d(
        testcase_id,
        "physical-descrambled-llrs",
        "float64",
        physical_descrambled_llrs,
    ))
    result.append(checkpoint_metadata_1d(
        testcase_id,
        "decoded-information-with-crc",
        "uint8",
        decoded_information,
        q_format="binary-u1",
        layout="bit-per-byte",
    ))
    result.append(checkpoint_metadata_1d(
        testcase_id,
        "payload",
        "uint8",
        payload,
        q_format="binary-u1",
        layout="bit-per-byte",
    ))
    result.append(checkpoint_metadata_1d(
        testcase_id,
        "mib-bits",
        "uint8",
        mib_bits,
        q_format="binary-u1",
        layout="bit-per-byte",
    ))
    result.append(checkpoint_metadata_1d(
        testcase_id,
        "decoded-fields",
        "int",
        4,
        q_format="integer",
        layout="sfn-half-frame-ssb-index-k-ssb-msb",
    ))
    result.append(checkpoint_metadata_1d(
        testcase_id,
        "crc-ok",
        "bool",
        1,
        q_format="boolean",
        layout="scalar",
    ))
    return result^


def _validate_pbch_configuration(
    physical_cell_id: Int, ssb_index: Int, l_max: Int,
) raises:
    if physical_cell_id < 0 or physical_cell_id > 1007:
        raise Error("physical cell identity must be in [0,1007]")
    _validate_pbch_index(ssb_index, l_max)


def _validate_pbch_index(ssb_index: Int, l_max: Int) raises:
    if (
        l_max != 4 and l_max != 8 and l_max != 10
        and l_max != 20 and l_max != 64
    ):
        raise Error("PBCH Lmax must be 4, 8, 10, 20, or 64")
    if ssb_index < 0 or ssb_index >= l_max:
        raise Error("candidate SS/PBCH block index is out of range")


def _pbch_payload_destinations() -> List[Int]:
    # G(j), TS 38.212 Table 7.1.1-1.
    var g: List[Int] = [
        16, 23, 18, 17, 8, 30, 10, 6,
        24, 7, 0, 5, 3, 2, 1, 4,
        9, 11, 12, 13, 14, 15, 19, 20,
        21, 22, 25, 26, 27, 28, 29, 31,
    ]
    var destination = List[Int](length=32, fill=0)
    var j_sfn = 0
    var j_ssb = 11
    var j_other = 14
    for source in range(32):
        if source < 6 or (source >= 24 and source <= 27):
            destination[source] = g[j_sfn]
            j_sfn += 1
        elif source == 28:
            destination[source] = g[10]
        elif source >= 29:
            destination[source] = g[j_ssb]
            j_ssb += 1
        else:
            destination[source] = g[j_other]
            j_other += 1
    return destination^


def nr_pbch_build_payload(
    mib_bits: Span[UInt8, ...], system_frame_number: Int,
    half_frame: Int, ssb_index: Int, l_max: Int,
    *, k_ssb_msb: Int = 0,
) raises -> List[UInt8]:
    """Build the 32 bits before PBCH payload interleaving.

    ``mib_bits[0:6]`` are the six MSBs of the 10-bit SFN, matching the MIB
    ASN.1 field order.  The consistency check prevents silently transmitting
    two different SFN values.
    """
    _validate_pbch_index(ssb_index, l_max)
    if len(mib_bits) != 24 or system_frame_number < 0 or system_frame_number > 1023:
        raise Error("PBCH requires a 24-bit MIB and a 10-bit SFN")
    if half_frame < 0 or half_frame > 1 or k_ssb_msb < 0 or k_ssb_msb > 1:
        raise Error("PBCH half-frame and k_SSB MSB fields must be bits")
    var payload = List[UInt8](capacity=32)
    for index in range(24):
        if mib_bits[index] > 1:
            raise Error("MIB bits must be zero or one")
        if index < 6:
            var expected = UInt8((system_frame_number >> (9 - index)) & 1)
            if mib_bits[index] != expected:
                raise Error("MIB SFN MSBs do not match system_frame_number")
        payload.append(mib_bits[index])
    payload.append(UInt8((system_frame_number >> 3) & 1))
    payload.append(UInt8((system_frame_number >> 2) & 1))
    payload.append(UInt8((system_frame_number >> 1) & 1))
    payload.append(UInt8(system_frame_number & 1))
    payload.append(UInt8(half_frame))
    if l_max == 64:
        payload.append(UInt8((ssb_index >> 5) & 1))
        payload.append(UInt8((ssb_index >> 4) & 1))
        payload.append(UInt8((ssb_index >> 3) & 1))
    elif l_max == 20:
        payload.append(UInt8(k_ssb_msb))
        payload.append(UInt8((ssb_index >> 4) & 1))
        payload.append(UInt8((ssb_index >> 3) & 1))
    elif l_max == 10:
        payload.append(UInt8(k_ssb_msb))
        payload.append(UInt8(0))
        payload.append(UInt8((ssb_index >> 3) & 1))
    else:
        payload.append(UInt8(k_ssb_msb))
        payload.append(UInt8(0))
        payload.append(UInt8(0))
    return payload^


def nr_pbch_payload_interleave(payload: Span[UInt8, ...]) raises -> List[UInt8]:
    """TS 38.212 7.1.1 PBCH payload permutation G."""
    if len(payload) != 32:
        raise Error("PBCH payload interleaver requires 32 bits")
    var destination = _pbch_payload_destinations()
    var result = List[UInt8](length=32, fill=UInt8(0))
    for source in range(32):
        if payload[source] > 1:
            raise Error("payload bits must be zero or one")
        result[destination[source]] = payload[source]
    return result^


def nr_pbch_payload_deinterleave(payload: Span[UInt8, ...]) raises -> List[UInt8]:
    if len(payload) != 32:
        raise Error("PBCH payload deinterleaver requires 32 bits")
    var destination = _pbch_payload_destinations()
    var result = List[UInt8](length=32, fill=UInt8(0))
    for source in range(32):
        if payload[destination[source]] > 1:
            raise Error("payload bits must be zero or one")
        result[source] = payload[destination[source]]
    return result^


def _pbch_protected_positions(l_max: Int) raises -> List[UInt8]:
    _validate_pbch_index(0, l_max)
    var destination = _pbch_payload_destinations()
    var protected = List[UInt8](length=32, fill=UInt8(0))
    # Third/second SFN LSB and the half-frame bit are never scrambled.
    protected[destination[25]] = 1
    protected[destination[26]] = 1
    protected[destination[28]] = 1
    if l_max == 10:
        protected[destination[31]] = 1
    elif l_max == 20:
        protected[destination[30]] = 1
        protected[destination[31]] = 1
    elif l_max == 64:
        protected[destination[29]] = 1
        protected[destination[30]] = 1
        protected[destination[31]] = 1
    return protected^


def _pbch_payload_scramble_with_v(
    payload: Span[UInt8, ...], physical_cell_id: Int, l_max: Int, v: Int,
) raises -> List[UInt8]:
    if len(payload) != 32 or v < 0 or v > 3:
        raise Error("invalid PBCH payload scrambling dimensions")
    _validate_pbch_configuration(physical_cell_id, 0, l_max)
    var protected = _pbch_protected_positions(l_max)
    var m = 0
    for value in protected:
        if value == 0:
            m += 1
    var sequence = nr_gold_bits(UInt32(physical_cell_id), (v + 1) * m)
    var result = List[UInt8](capacity=32)
    var j = 0
    for index in range(32):
        if payload[index] > 1:
            raise Error("payload bits must be zero or one")
        if protected[index] != 0:
            result.append(payload[index])
        else:
            result.append(payload[index] ^ sequence[v * m + j])
            j += 1
    return result^


def nr_pbch_payload_scramble(
    interleaved_payload: Span[UInt8, ...], physical_cell_id: Int,
    system_frame_number: Int, l_max: Int,
) raises -> List[UInt8]:
    """TS 38.212 7.1.2 selective BCH scrambling."""
    if system_frame_number < 0 or system_frame_number > 1023:
        raise Error("system frame number must be in [0,1023]")
    var v = (system_frame_number >> 1) & 3
    return _pbch_payload_scramble_with_v(
        interleaved_payload, physical_cell_id, l_max, v
    )


def nr_pbch_payload_descramble(
    scrambled_payload: Span[UInt8, ...], physical_cell_id: Int, l_max: Int,
) raises -> List[UInt8]:
    """Infer v from protected SFN bits and reverse selective scrambling."""
    if len(scrambled_payload) != 32:
        raise Error("PBCH payload descrambler requires 32 bits")
    var destination = _pbch_payload_destinations()
    var v = (
        2 * Int(scrambled_payload[destination[25]])
        + Int(scrambled_payload[destination[26]])
    )
    return _pbch_payload_scramble_with_v(
        scrambled_payload, physical_cell_id, l_max, v
    )


def nr_pbch_crc24c(bits: Span[UInt8, ...]) raises -> UInt64:
    return crc_bits(bits, width=24, polynomial=_CRC24C_POLYNOMIAL)


def nr_pbch_crc24c_append(bits: Span[UInt8, ...]) raises -> List[UInt8]:
    return crc_append(bits, width=24, polynomial=_CRC24C_POLYNOMIAL)


def nr_pbch_crc24c_check(bits: Span[UInt8, ...]) raises -> Bool:
    return crc_check(bits, width=24, polynomial=_CRC24C_POLYNOMIAL)


def _pbch_physical_nu(ssb_index: Int, l_max: Int) -> Int:
    return ssb_index & (3 if l_max == 4 else 7)


def nr_pbch_physical_scramble(
    bits: Span[UInt8, ...], physical_cell_id: Int, ssb_index: Int, l_max: Int,
) raises -> List[UInt8]:
    """TS 38.211 7.3.3.1 physical PBCH scrambling; XOR is self-inverse."""
    _validate_pbch_configuration(physical_cell_id, ssb_index, l_max)
    var nu = _pbch_physical_nu(ssb_index, l_max)
    if len(bits) > Int.MAX // (nu + 1):
        raise Error("PBCH scrambling length exceeds the supported Int range")
    var sequence = nr_gold_bits(
        UInt32(physical_cell_id), (nu + 1) * len(bits)
    )
    var result = List[UInt8](capacity=len(bits))
    for index in range(len(bits)):
        if bits[index] > 1:
            raise Error("PBCH bits must be zero or one")
        result.append(bits[index] ^ sequence[nu * len(bits) + index])
    return result^


def nr_pbch_physical_descramble_llrs(
    llrs: Span[Float64, ...], physical_cell_id: Int,
    ssb_index: Int, l_max: Int,
) raises -> List[Float64]:
    _validate_pbch_configuration(physical_cell_id, ssb_index, l_max)
    var nu = _pbch_physical_nu(ssb_index, l_max)
    if len(llrs) > Int.MAX // (nu + 1):
        raise Error("PBCH descrambling length exceeds the supported Int range")
    var sequence = nr_gold_bits(
        UInt32(physical_cell_id), (nu + 1) * len(llrs)
    )
    var result = List[Float64](capacity=len(llrs))
    for index in range(len(llrs)):
        if not isfinite(llrs[index]):
            raise Error("PBCH physical descrambling LLRs must be finite")
        result.append(
            llrs[index]
            if sequence[nu * len(llrs) + index] == 0
            else -llrs[index]
        )
    return result^


def nr_pbch_encode(
    mib_bits: Span[UInt8, ...], physical_cell_id: Int,
    system_frame_number: Int, half_frame: Int,
    ssb_index: Int, l_max: Int, *, k_ssb_msb: Int = 0,
    testcase_id: StringSlice = "nr-pbch-tx",
) raises -> NRPBCHTransmitBlock:
    """Run payload generation through physical-channel scrambling."""
    var payload = nr_pbch_build_payload(
        mib_bits,
        system_frame_number,
        half_frame,
        ssb_index,
        l_max,
        k_ssb_msb=k_ssb_msb,
    )
    var interleaved = nr_pbch_payload_interleave(Span(payload))
    var scrambled = nr_pbch_payload_scramble(
        Span(interleaved), physical_cell_id, system_frame_number, l_max
    )
    var with_crc = nr_pbch_crc24c_append(Span(scrambled))
    var polar_input = polar_5g_input_interleave(Span(with_crc))
    var frozen = polar_5g_frozen_mask(
        _PBCH_INFORMATION_BITS, _PBCH_RATE_MATCHED_BITS, n_max=9
    )
    var mother = polar_encode(Span(polar_input), Span(frozen))
    if len(mother) != _PBCH_MOTHER_BITS:
        raise Error("PBCH Polar mother-code construction did not produce N=512")
    var rate_matched = polar_5g_rate_match(
        Span(mother), _PBCH_RATE_MATCHED_BITS, _PBCH_INFORMATION_BITS
    )
    var physical = nr_pbch_physical_scramble(
        Span(rate_matched), physical_cell_id, ssb_index, l_max
    )
    var checkpoint_metadata = _nr_pbch_tx_checkpoint_metadata(
        testcase_id,
        len(mib_bits),
        len(payload),
        len(interleaved),
        len(scrambled),
        len(with_crc),
        len(mother),
        len(rate_matched),
        len(physical),
    )
    return NRPBCHTransmitBlock(
        payload^,
        interleaved^,
        scrambled^,
        with_crc^,
        mother^,
        rate_matched^,
        physical^,
        checkpoint_metadata^,
    )


def _parse_pbch_ssb_index(
    payload: Span[UInt8, ...], supplied_ssb_index: Int, l_max: Int,
) -> Int:
    var low = supplied_ssb_index & (3 if l_max == 4 else 7)
    if l_max == 64:
        return low + (Int(payload[29]) << 5) + (Int(payload[30]) << 4) + (Int(payload[31]) << 3)
    if l_max == 20:
        return low + (Int(payload[30]) << 4) + (Int(payload[31]) << 3)
    if l_max == 10:
        return low + (Int(payload[31]) << 3)
    return low


def nr_pbch_decode(
    llrs: Span[Float64, ...], physical_cell_id: Int,
    ssb_index: Int, l_max: Int,
    *,
    testcase_id: StringSlice = "nr-pbch-rx",
) raises -> NRPBCHDecodeResult:
    """Reverse physical scrambling, rate matching, Polar coding, and BCH."""
    if len(llrs) != _PBCH_RATE_MATCHED_BITS:
        raise Error("PBCH decoder requires exactly E=864 LLRs")
    var physical_llrs = nr_pbch_physical_descramble_llrs(
        llrs, physical_cell_id, ssb_index, l_max
    )
    var information = polar_5g_decode_sc(
        Span(physical_llrs),
        _PBCH_INFORMATION_BITS,
        n_max=9,
        input_interleave=True,
    )
    var crc_ok = nr_pbch_crc24c_check(Span(information))
    var scrambled_payload = List[UInt8](capacity=32)
    for index in range(32):
        scrambled_payload.append(information[index])
    var interleaved = nr_pbch_payload_descramble(
        Span(scrambled_payload), physical_cell_id, l_max
    )
    var payload = nr_pbch_payload_deinterleave(Span(interleaved))
    var mib = List[UInt8](capacity=24)
    for index in range(24):
        mib.append(payload[index])
    var sfn = 0
    for index in range(6):
        sfn = (sfn << 1) | Int(payload[index])
    for index in range(24, 28):
        sfn = (sfn << 1) | Int(payload[index])
    var decoded_ssb_index = _parse_pbch_ssb_index(
        Span(payload), ssb_index, l_max
    )
    var k_ssb_msb = -1 if l_max == 64 else Int(payload[29])
    var checkpoint_metadata = _nr_pbch_rx_checkpoint_metadata(
        testcase_id,
        len(llrs),
        len(physical_llrs),
        len(information),
        len(payload),
        len(mib),
    )
    return NRPBCHDecodeResult(
        mib^,
        payload^,
        information^,
        checkpoint_metadata^,
        sfn,
        Int(interleaved[_pbch_payload_destinations()[28]]),
        decoded_ssb_index,
        k_ssb_msb,
        crc_ok,
    )
