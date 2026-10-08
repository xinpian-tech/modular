"""Bluetooth Core 6.3 LE Uncoded PHY packet-bit reference primitives.

This bounded slice implements the deterministic bit processing in Bluetooth
Core Specification 6.3, Vol 6, Part B, Sections 2.1, 2.1.1, 3.1, 3.1.1,
and 3.2.  It covers LE 1M and LE 2M packets without a Constant Tone
Extension: preamble construction, caller-supplied Access Address
serialization, CRC-24, and PDU/CRC whitening.

The PDU is supplied as bits in transmission order and must contain 2 through
258 complete octets.  Access Address generation and admissibility, Link Layer
PDU semantics, encryption, timing, RF modulation, synchronization, and CTE
processing are intentionally outside this narrow packet-bit module.  Decode
therefore receives the expected caller-owned Access Address.  A structurally
invalid call raises; preamble, Access Address, and CRC mismatches are returned
as packet verdict flags.
"""

from std.collections import Span
from wireless_dsp.modem.crc import crc_bits
from wireless_dsp.testing.checkpoint import (
    CheckpointMetadata,
    checkpoint_metadata_1d,
)


comptime BLUETOOTH_LE_PHY_1M = 1
comptime BLUETOOTH_LE_PHY_2M = 2

comptime _CRC_WIDTH = 24
comptime _CRC_POLYNOMIAL = UInt64(0x00065B)
comptime _ACCESS_ADDRESS_BITS = 32
comptime _MIN_PDU_BITS = 2 * 8
comptime _MAX_PDU_BITS = 258 * 8
comptime _MAX_WHITENED_BITS = _MAX_PDU_BITS + _CRC_WIDTH


struct BluetoothLEUncodedPacketEncodeResult(Movable):
    """Owned LE Uncoded transmit bits and every observable bit stage."""

    var preamble_bits: List[UInt8]
    var access_address_bits: List[UInt8]
    var pdu_bits: List[UInt8]
    var crc_bits: List[UInt8]
    var pdu_and_crc_bits: List[UInt8]
    var whitened_body_bits: List[UInt8]
    var packet_bits: List[UInt8]
    var checkpoint_metadata: List[CheckpointMetadata]
    var crc: UInt32

    def __init__(
        out self,
        var preamble_bits: List[UInt8],
        var access_address_bits: List[UInt8],
        var pdu_bits: List[UInt8],
        var crc_bits: List[UInt8],
        var pdu_and_crc_bits: List[UInt8],
        var whitened_body_bits: List[UInt8],
        var packet_bits: List[UInt8],
        var checkpoint_metadata: List[CheckpointMetadata],
        crc: UInt32,
    ):
        self.preamble_bits = preamble_bits^
        self.access_address_bits = access_address_bits^
        self.pdu_bits = pdu_bits^
        self.crc_bits = crc_bits^
        self.pdu_and_crc_bits = pdu_and_crc_bits^
        self.whitened_body_bits = whitened_body_bits^
        self.packet_bits = packet_bits^
        self.checkpoint_metadata = checkpoint_metadata^
        self.crc = crc


struct BluetoothLEUncodedPacketDecodeResult(Movable):
    """Owned receive checkpoints and independent packet validity verdicts."""

    var packet_bits: List[UInt8]
    var preamble_bits: List[UInt8]
    var access_address_bits: List[UInt8]
    var whitened_body_bits: List[UInt8]
    var pdu_and_crc_bits: List[UInt8]
    var pdu_bits: List[UInt8]
    var received_crc_bits: List[UInt8]
    var expected_crc_bits: List[UInt8]
    var checkpoint_metadata: List[CheckpointMetadata]
    var received_access_address: UInt32
    var received_crc: UInt32
    var expected_crc: UInt32
    var preamble_ok: Bool
    var access_address_ok: Bool
    var crc_ok: Bool
    var valid: Bool

    def __init__(
        out self,
        var packet_bits: List[UInt8],
        var preamble_bits: List[UInt8],
        var access_address_bits: List[UInt8],
        var whitened_body_bits: List[UInt8],
        var pdu_and_crc_bits: List[UInt8],
        var pdu_bits: List[UInt8],
        var received_crc_bits: List[UInt8],
        var expected_crc_bits: List[UInt8],
        var checkpoint_metadata: List[CheckpointMetadata],
        received_access_address: UInt32,
        received_crc: UInt32,
        expected_crc: UInt32,
        preamble_ok: Bool,
        access_address_ok: Bool,
        crc_ok: Bool,
    ):
        self.packet_bits = packet_bits^
        self.preamble_bits = preamble_bits^
        self.access_address_bits = access_address_bits^
        self.whitened_body_bits = whitened_body_bits^
        self.pdu_and_crc_bits = pdu_and_crc_bits^
        self.pdu_bits = pdu_bits^
        self.received_crc_bits = received_crc_bits^
        self.expected_crc_bits = expected_crc_bits^
        self.checkpoint_metadata = checkpoint_metadata^
        self.received_access_address = received_access_address
        self.received_crc = received_crc
        self.expected_crc = expected_crc
        self.preamble_ok = preamble_ok
        self.access_address_ok = access_address_ok
        self.crc_ok = crc_ok
        self.valid = preamble_ok and access_address_ok and crc_ok


def _preamble_length(phy: Int) raises -> Int:
    if phy == BLUETOOTH_LE_PHY_1M:
        return 8
    if phy == BLUETOOTH_LE_PHY_2M:
        return 16
    raise Error("Bluetooth LE Uncoded PHY must be LE 1M or LE 2M")


def _validate_channel(channel_index: Int) raises:
    if channel_index < 0 or channel_index > 39:
        raise Error("Bluetooth LE physical channel index must be in [0,39]")


def _validate_crc_init(crc_init: Int) raises:
    if crc_init < 0 or crc_init > 0xFFFFFF:
        raise Error("Bluetooth LE CRCInit must be a 24-bit unsigned value")


def _validate_access_address(access_address: Int) raises:
    if access_address < 0 or UInt64(access_address) > UInt64(0xFFFFFFFF):
        raise Error(
            "Bluetooth LE Access Address must be a 32-bit unsigned value"
        )


def _validate_binary(bits: Span[UInt8, ...]) raises:
    for index in range(len(bits)):
        if bits[index] > 1:
            raise Error(
                "Bluetooth LE bit sequences must contain only zero and one"
            )


def _validate_pdu(pdu_bits: Span[UInt8, ...]) raises:
    if (
        len(pdu_bits) < _MIN_PDU_BITS
        or len(pdu_bits) > _MAX_PDU_BITS
        or len(pdu_bits) % 8 != 0
    ):
        raise Error(
            "Bluetooth LE PDU must contain 2 through 258 complete octets"
        )
    _validate_binary(pdu_bits)


def _copy_bits(bits: Span[UInt8, ...]) -> List[UInt8]:
    var result = List[UInt8](capacity=len(bits))
    for index in range(len(bits)):
        result.append(bits[index])
    return result^


def _crc_bit_list(crc: UInt32) -> List[UInt8]:
    var result = List[UInt8](capacity=_CRC_WIDTH)
    for index in range(_CRC_WIDTH):
        result.append(
            UInt8((UInt64(crc) >> UInt64(23 - index)) & UInt64(1))
        )
    return result^


def _bit_checkpoint(
    testcase_id: StringSlice, stage: StringSlice, length: Int
) raises -> CheckpointMetadata:
    return checkpoint_metadata_1d(
        testcase_id,
        stage,
        "uint8",
        length,
        q_format="binary-u1",
        layout="bit-per-byte",
    )


def _uncoded_tx_checkpoint_metadata(
    testcase_id: StringSlice,
    preamble_bits: Int,
    access_address_bits: Int,
    pdu_bits: Int,
    crc_bits: Int,
    pdu_and_crc_bits: Int,
    whitened_body_bits: Int,
    packet_bits: Int,
) raises -> List[CheckpointMetadata]:
    var result = List[CheckpointMetadata](capacity=7)
    result.append(_bit_checkpoint(
        testcase_id, "uncoded-preamble-bits", preamble_bits
    ))
    result.append(_bit_checkpoint(
        testcase_id, "access-address-bits", access_address_bits
    ))
    result.append(_bit_checkpoint(testcase_id, "pdu-bits", pdu_bits))
    result.append(_bit_checkpoint(testcase_id, "crc-bits", crc_bits))
    result.append(_bit_checkpoint(
        testcase_id, "pdu-and-crc-bits", pdu_and_crc_bits
    ))
    result.append(_bit_checkpoint(
        testcase_id, "whitened-body-bits", whitened_body_bits
    ))
    result.append(_bit_checkpoint(testcase_id, "packet-bits", packet_bits))
    return result^


def _uncoded_rx_checkpoint_metadata(
    testcase_id: StringSlice,
    packet_bits: Int,
    preamble_bits: Int,
    access_address_bits: Int,
    whitened_body_bits: Int,
    pdu_and_crc_bits: Int,
    pdu_bits: Int,
    received_crc_bits: Int,
    expected_crc_bits: Int,
) raises -> List[CheckpointMetadata]:
    var result = List[CheckpointMetadata](capacity=8)
    result.append(_bit_checkpoint(
        testcase_id, "received-packet-bits", packet_bits
    ))
    result.append(_bit_checkpoint(
        testcase_id, "received-preamble-bits", preamble_bits
    ))
    result.append(_bit_checkpoint(
        testcase_id, "received-access-address-bits", access_address_bits
    ))
    result.append(_bit_checkpoint(
        testcase_id, "received-whitened-body-bits", whitened_body_bits
    ))
    result.append(_bit_checkpoint(
        testcase_id, "dewhitened-pdu-and-crc-bits", pdu_and_crc_bits
    ))
    result.append(_bit_checkpoint(testcase_id, "decoded-pdu-bits", pdu_bits))
    result.append(_bit_checkpoint(
        testcase_id, "received-crc-bits", received_crc_bits
    ))
    result.append(_bit_checkpoint(
        testcase_id, "expected-crc-bits", expected_crc_bits
    ))
    return result^


def bluetooth_le_crc24(
    pdu_bits: Span[UInt8, ...], crc_init: Int
) raises -> UInt32:
    """Return the Core 6.3 LE CRC-24 state transmitted from bit 23 to bit 0.

    ``pdu_bits`` are processed in transmission order.  Within each Link Layer
    octet that means least-significant bit first.  The caller supplies the
    already-selected 24-bit ``CRCInit`` value.
    """

    _validate_pdu(pdu_bits)
    _validate_crc_init(crc_init)
    return UInt32(
        crc_bits(
            pdu_bits,
            width=_CRC_WIDTH,
            polynomial=_CRC_POLYNOMIAL,
            initial=UInt64(crc_init),
        )
    )


def bluetooth_le_whiten_bits(
    bits: Span[UInt8, ...], channel_index: Int
) raises -> List[UInt8]:
    """Whiten or de-whiten at most one bounded LE PDU-plus-CRC bit stream.

    The operation is its own inverse.  ``bits`` may be empty for compositional
    callers and may contain at most 2088 bits, the 258-octet PDU plus CRC
    maximum.  Preamble and Access Address bits must not be passed here.
    """

    if len(bits) > _MAX_WHITENED_BITS:
        raise Error("Bluetooth LE whitening input exceeds PDU-plus-CRC maximum")
    _validate_channel(channel_index)
    _validate_binary(bits)

    # Integer bits 6..0 represent Core positions 0..6 respectively; the low
    # bit (position 6) is emitted first.  This gives the required
    # channel_index | 0x40 initialization.  The 0x44 feedback realizes
    # x^7 + x^4 + 1 for that reversed storage orientation.
    var state = UInt8(channel_index | 0x40)
    var result = List[UInt8](capacity=len(bits))
    for index in range(len(bits)):
        var whitening_bit = state & UInt8(1)
        result.append(bits[index] ^ whitening_bit)
        state >>= 1
        if whitening_bit != 0:
            state ^= UInt8(0x44)
    return result^


def bluetooth_le_uncoded_packet_encode(
    pdu_bits: Span[UInt8, ...],
    access_address: Int,
    crc_init: Int,
    channel_index: Int,
    phy: Int,
    *,
    testcase_id: StringSlice = "bluetooth-le-uncoded-tx",
) raises -> BluetoothLEUncodedPacketEncodeResult:
    """Encode one LE 1M/2M packet and retain every real bit checkpoint."""

    _validate_pdu(pdu_bits)
    _validate_access_address(access_address)
    _validate_crc_init(crc_init)
    _validate_channel(channel_index)
    var preamble_length = _preamble_length(phy)

    var crc = bluetooth_le_crc24(pdu_bits, crc_init)
    var owned_pdu = _copy_bits(pdu_bits)
    var crc_output_bits = _crc_bit_list(crc)
    var pdu_and_crc = List[UInt8](capacity=len(pdu_bits) + _CRC_WIDTH)
    for index in range(len(pdu_bits)):
        pdu_and_crc.append(pdu_bits[index])
    for index in range(len(crc_output_bits)):
        pdu_and_crc.append(crc_output_bits[index])
    var whitened = bluetooth_le_whiten_bits(Span(pdu_and_crc), channel_index)

    var preamble = List[UInt8](capacity=preamble_length)
    var first_preamble_bit = UInt8(UInt64(access_address) & UInt64(1))
    for index in range(preamble_length):
        preamble.append(first_preamble_bit ^ UInt8(index & 1))
    var access_address_output_bits = List[UInt8](capacity=_ACCESS_ADDRESS_BITS)
    for index in range(_ACCESS_ADDRESS_BITS):
        access_address_output_bits.append(
            UInt8((UInt64(access_address) >> UInt64(index)) & UInt64(1))
        )
    var packet = List[UInt8](
        capacity=len(preamble) + len(access_address_output_bits) + len(whitened)
    )
    for index in range(len(preamble)):
        packet.append(preamble[index])
    for index in range(len(access_address_output_bits)):
        packet.append(access_address_output_bits[index])
    for index in range(len(whitened)):
        packet.append(whitened[index])
    var checkpoint_metadata = _uncoded_tx_checkpoint_metadata(
        testcase_id,
        len(preamble),
        len(access_address_output_bits),
        len(owned_pdu),
        len(crc_output_bits),
        len(pdu_and_crc),
        len(whitened),
        len(packet),
    )
    return BluetoothLEUncodedPacketEncodeResult(
        preamble^,
        access_address_output_bits^,
        owned_pdu^,
        crc_output_bits^,
        pdu_and_crc^,
        whitened^,
        packet^,
        checkpoint_metadata^,
        crc,
    )


def bluetooth_le_uncoded_packet_decode(
    packet_bits: Span[UInt8, ...],
    expected_access_address: Int,
    crc_init: Int,
    channel_index: Int,
    phy: Int,
    *,
    testcase_id: StringSlice = "bluetooth-le-uncoded-rx",
) raises -> BluetoothLEUncodedPacketDecodeResult:
    """Decode one exact LE 1M/2M packet and return AA/preamble/CRC flags.

    Packet shape, scalar domains, and non-binary inputs raise.  A well-shaped
    packet with a corrupted preamble, Access Address, PDU, or CRC returns a
    result; callers use ``valid`` or the individual flags to reject it.
    """

    _validate_access_address(expected_access_address)
    _validate_crc_init(crc_init)
    _validate_channel(channel_index)
    var preamble_bits = _preamble_length(phy)
    var fixed_bits = preamble_bits + _ACCESS_ADDRESS_BITS + _CRC_WIDTH
    if (
        len(packet_bits) < fixed_bits + _MIN_PDU_BITS
        or len(packet_bits) > fixed_bits + _MAX_PDU_BITS
        or (len(packet_bits) - fixed_bits) % 8 != 0
    ):
        raise Error(
            "Bluetooth LE packet has an invalid exact Uncoded PHY length"
        )
    _validate_binary(packet_bits)

    var owned_packet = _copy_bits(packet_bits)
    var preamble = List[UInt8](capacity=preamble_bits)
    for index in range(preamble_bits):
        preamble.append(packet_bits[index])

    var first_preamble_bit = UInt8(UInt64(expected_access_address) & UInt64(1))
    var preamble_ok = True
    for index in range(preamble_bits):
        if packet_bits[index] != first_preamble_bit ^ UInt8(index & 1):
            preamble_ok = False

    var access_address_output_bits = List[UInt8](capacity=_ACCESS_ADDRESS_BITS)
    var received_access_address_u64 = UInt64(0)
    for index in range(_ACCESS_ADDRESS_BITS):
        var bit = packet_bits[preamble_bits + index]
        access_address_output_bits.append(bit)
        received_access_address_u64 |= UInt64(bit) << UInt64(index)
    var received_access_address = UInt32(received_access_address_u64)
    var access_address_ok = received_access_address_u64 == UInt64(
        expected_access_address
    )

    var body_start = preamble_bits + _ACCESS_ADDRESS_BITS
    var whitened_body = List[UInt8](capacity=len(packet_bits) - body_start)
    for index in range(body_start, len(packet_bits)):
        whitened_body.append(packet_bits[index])
    var body = bluetooth_le_whiten_bits(Span(whitened_body), channel_index)
    var pdu_length = len(body) - _CRC_WIDTH
    var pdu = List[UInt8](capacity=pdu_length)
    for index in range(pdu_length):
        pdu.append(body[index])

    var received_crc_bits = List[UInt8](capacity=_CRC_WIDTH)
    var received_crc_u64 = UInt64(0)
    for index in range(_CRC_WIDTH):
        var bit = body[pdu_length + index]
        received_crc_bits.append(bit)
        received_crc_u64 = (received_crc_u64 << UInt64(1)) | UInt64(bit)
    var received_crc = UInt32(received_crc_u64)
    var expected_crc = bluetooth_le_crc24(Span(pdu), crc_init)
    var expected_crc_bits = _crc_bit_list(expected_crc)
    var crc_ok = received_crc == expected_crc
    var checkpoint_metadata = _uncoded_rx_checkpoint_metadata(
        testcase_id,
        len(owned_packet),
        len(preamble),
        len(access_address_output_bits),
        len(whitened_body),
        len(body),
        len(pdu),
        len(received_crc_bits),
        len(expected_crc_bits),
    )
    return BluetoothLEUncodedPacketDecodeResult(
        owned_packet^,
        preamble^,
        access_address_output_bits^,
        whitened_body^,
        body^,
        pdu^,
        received_crc_bits^,
        expected_crc_bits^,
        checkpoint_metadata^,
        received_access_address,
        received_crc,
        expected_crc,
        preamble_ok,
        access_address_ok,
        crc_ok,
    )
