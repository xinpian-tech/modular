"""Bluetooth Core 6.3 LE Coded PHY symbol and FEC primitives.

This bounded module implements the deterministic transmit processing in Core
6.3, Vol 6, Part B, Sections 2.2 and 3.1 through 3.3.  It covers complete
LE Coded packets with a 2 through 257-octet caller-supplied PDU and either
S=2 or S=8 coding: the fixed 80-symbol preamble, Access Address and Coding
Indicator serialization, both terminated K=4 rate-1/2 FEC blocks, whitening,
CRC-24, and pattern mapping.

The receive side is deliberately narrower: it accepts a known-boundary binary
hard-symbol packet, applies the exact inverse only to valid mapper codewords,
and reuses the generic terminated hard Viterbi decoder.  This is explicitly a
reference decoder because Core 6.3 does not specify receiver decisions for a
corrupted S=8 symbol group, Viterbi metrics, or tie breaking.  It stops at the
decoded, still-whitened PDU and CRC regions.

Access Address selection/admissibility, Link Layer PDU semantics, encryption,
RF modulation, synchronization, demodulation, dewhitening, CRC verdicts, and
packet validity are outside the reference receive slice.  There is no
interleaver in the Core LE Coded PHY bit-processing chain.
"""

from std.collections import Span
from wireless_dsp.fec import convolutional_encode, viterbi_decode_hard
from wireless_dsp.testing.checkpoint import (
    CheckpointMetadata,
    checkpoint_metadata_1d,
)

from .le_packet import bluetooth_le_crc24, bluetooth_le_whiten_bits


comptime _ACCESS_ADDRESS_BITS = 32
comptime _CRC_BITS = 24
comptime _MIN_PDU_BITS = 2 * 8
comptime _MAX_PDU_BITS = 257 * 8
comptime _PREAMBLE_SYMBOLS = 80
comptime _CODING_S2 = 2
comptime _CODING_S8 = 8
comptime _TERMINATION_BITS = 3
comptime _TERMINATION_FEC_BITS = 2 * _TERMINATION_BITS
comptime _BLOCK_ONE_DATA_BITS = _ACCESS_ADDRESS_BITS + 2
comptime _BLOCK_ONE_INPUT_BITS = _BLOCK_ONE_DATA_BITS + _TERMINATION_BITS
comptime _BLOCK_ONE_FEC_BITS = 2 * _BLOCK_ONE_INPUT_BITS
comptime _BLOCK_ONE_MAPPED_SYMBOLS = 4 * _BLOCK_ONE_FEC_BITS
comptime _CODED_FIXED_PREFIX_SYMBOLS = (
    _PREAMBLE_SYMBOLS + _BLOCK_ONE_MAPPED_SYMBOLS
)
comptime _MIN_CODED_PACKET_SYMBOLS = 462
comptime _MAX_CODED_PACKET_SYMBOLS = 17040


struct BluetoothLECodedPacketEncodeResult(Movable):
    """Owned LE Coded transmit symbols and actual intermediate bit stages."""

    var preamble_symbols: List[UInt8]
    var access_address_bits: List[UInt8]
    var coding_indicator_bits: List[UInt8]
    var term1_bits: List[UInt8]
    var block_one_input_bits: List[UInt8]
    var block_one_fec_bits: List[UInt8]
    var block_one_mapped_symbols: List[UInt8]
    var pdu_bits: List[UInt8]
    var crc_bits: List[UInt8]
    var pdu_and_crc_bits: List[UInt8]
    var whitened_pdu_and_crc_bits: List[UInt8]
    var term2_bits: List[UInt8]
    var block_two_input_bits: List[UInt8]
    var block_two_fec_bits: List[UInt8]
    var block_two_mapped_symbols: List[UInt8]
    var packet_symbols: List[UInt8]
    var checkpoint_metadata: List[CheckpointMetadata]
    var crc: UInt32
    var coding_s: Int

    def __init__(
        out self,
        var preamble_symbols: List[UInt8],
        var access_address_bits: List[UInt8],
        var coding_indicator_bits: List[UInt8],
        var term1_bits: List[UInt8],
        var block_one_input_bits: List[UInt8],
        var block_one_fec_bits: List[UInt8],
        var block_one_mapped_symbols: List[UInt8],
        var pdu_bits: List[UInt8],
        var crc_bits: List[UInt8],
        var pdu_and_crc_bits: List[UInt8],
        var whitened_pdu_and_crc_bits: List[UInt8],
        var term2_bits: List[UInt8],
        var block_two_input_bits: List[UInt8],
        var block_two_fec_bits: List[UInt8],
        var block_two_mapped_symbols: List[UInt8],
        var packet_symbols: List[UInt8],
        var checkpoint_metadata: List[CheckpointMetadata],
        crc: UInt32,
        coding_s: Int,
    ):
        self.preamble_symbols = preamble_symbols^
        self.access_address_bits = access_address_bits^
        self.coding_indicator_bits = coding_indicator_bits^
        self.term1_bits = term1_bits^
        self.block_one_input_bits = block_one_input_bits^
        self.block_one_fec_bits = block_one_fec_bits^
        self.block_one_mapped_symbols = block_one_mapped_symbols^
        self.pdu_bits = pdu_bits^
        self.crc_bits = crc_bits^
        self.pdu_and_crc_bits = pdu_and_crc_bits^
        self.whitened_pdu_and_crc_bits = whitened_pdu_and_crc_bits^
        self.term2_bits = term2_bits^
        self.block_two_input_bits = block_two_input_bits^
        self.block_two_fec_bits = block_two_fec_bits^
        self.block_two_mapped_symbols = block_two_mapped_symbols^
        self.packet_symbols = packet_symbols^
        self.checkpoint_metadata = checkpoint_metadata^
        self.crc = crc
        self.coding_s = coding_s


struct BluetoothLECodedPacketFECDecodeReferenceResult(Movable):
    """Owned known-boundary hard-symbol reference receive checkpoints.

    Every list is an actual received slice, exact demapper output, or hard
    Viterbi output.  TERM1 and TERM2 retain their observed mapped-symbol and
    demapped-FEC tails; no synthetic decoded ``000`` tail is reported.
    """

    var packet_symbols: List[UInt8]
    var preamble_symbols: List[UInt8]
    var block_one_mapped_symbols: List[UInt8]
    var block_one_fec_bits: List[UInt8]
    var term1_mapped_symbols: List[UInt8]
    var term1_fec_bits: List[UInt8]
    var block_one_decoded_bits: List[UInt8]
    var access_address_bits: List[UInt8]
    var coding_indicator_bits: List[UInt8]
    var block_two_mapped_symbols: List[UInt8]
    var block_two_fec_bits: List[UInt8]
    var term2_mapped_symbols: List[UInt8]
    var term2_fec_bits: List[UInt8]
    var decoded_whitened_pdu_and_crc_bits: List[UInt8]
    var decoded_whitened_pdu_bits: List[UInt8]
    var decoded_whitened_crc_bits: List[UInt8]
    var checkpoint_metadata: List[CheckpointMetadata]
    var received_access_address: UInt32
    var coding_s: Int
    var pdu_octets: Int
    var preamble_matches_exact: Bool

    def __init__(
        out self,
        var packet_symbols: List[UInt8],
        var preamble_symbols: List[UInt8],
        var block_one_mapped_symbols: List[UInt8],
        var block_one_fec_bits: List[UInt8],
        var term1_mapped_symbols: List[UInt8],
        var term1_fec_bits: List[UInt8],
        var block_one_decoded_bits: List[UInt8],
        var access_address_bits: List[UInt8],
        var coding_indicator_bits: List[UInt8],
        var block_two_mapped_symbols: List[UInt8],
        var block_two_fec_bits: List[UInt8],
        var term2_mapped_symbols: List[UInt8],
        var term2_fec_bits: List[UInt8],
        var decoded_whitened_pdu_and_crc_bits: List[UInt8],
        var decoded_whitened_pdu_bits: List[UInt8],
        var decoded_whitened_crc_bits: List[UInt8],
        var checkpoint_metadata: List[CheckpointMetadata],
        received_access_address: UInt32,
        coding_s: Int,
        pdu_octets: Int,
        preamble_matches_exact: Bool,
    ):
        self.packet_symbols = packet_symbols^
        self.preamble_symbols = preamble_symbols^
        self.block_one_mapped_symbols = block_one_mapped_symbols^
        self.block_one_fec_bits = block_one_fec_bits^
        self.term1_mapped_symbols = term1_mapped_symbols^
        self.term1_fec_bits = term1_fec_bits^
        self.block_one_decoded_bits = block_one_decoded_bits^
        self.access_address_bits = access_address_bits^
        self.coding_indicator_bits = coding_indicator_bits^
        self.block_two_mapped_symbols = block_two_mapped_symbols^
        self.block_two_fec_bits = block_two_fec_bits^
        self.term2_mapped_symbols = term2_mapped_symbols^
        self.term2_fec_bits = term2_fec_bits^
        self.decoded_whitened_pdu_and_crc_bits = (
            decoded_whitened_pdu_and_crc_bits^
        )
        self.decoded_whitened_pdu_bits = decoded_whitened_pdu_bits^
        self.decoded_whitened_crc_bits = decoded_whitened_crc_bits^
        self.checkpoint_metadata = checkpoint_metadata^
        self.received_access_address = received_access_address
        self.coding_s = coding_s
        self.pdu_octets = pdu_octets
        self.preamble_matches_exact = preamble_matches_exact


def _validate_coding(coding_s: Int) raises:
    if coding_s != _CODING_S2 and coding_s != _CODING_S8:
        raise Error("Bluetooth LE Coded scheme must be S=2 or S=8")


def _validate_binary(bits: Span[UInt8, ...]) raises:
    for index in range(len(bits)):
        if bits[index] > 1:
            raise Error(
                "Bluetooth LE Coded bit sequences must contain only zero and one"
            )


def _validate_pdu(pdu_bits: Span[UInt8, ...]) raises:
    if (
        len(pdu_bits) < _MIN_PDU_BITS
        or len(pdu_bits) > _MAX_PDU_BITS
        or len(pdu_bits) % 8 != 0
    ):
        raise Error(
            "Bluetooth LE Coded PDU must contain 2 through 257 complete octets"
        )
    _validate_binary(pdu_bits)


def _validate_access_address(access_address: Int) raises:
    if access_address < 0 or UInt64(access_address) > UInt64(0xFFFFFFFF):
        raise Error(
            "Bluetooth LE Access Address must be a 32-bit unsigned value"
        )


def _copy_bits(bits: Span[UInt8, ...]) -> List[UInt8]:
    var result = List[UInt8](capacity=len(bits))
    for index in range(len(bits)):
        result.append(bits[index])
    return result^


def _copy_bit_range(
    bits: Span[UInt8, ...], start: Int, end: Int
) -> List[UInt8]:
    var result = List[UInt8](capacity=end - start)
    for index in range(start, end):
        result.append(bits[index])
    return result^


def _crc_bit_list(crc: UInt32) -> List[UInt8]:
    var result = List[UInt8](capacity=_CRC_BITS)
    for index in range(_CRC_BITS):
        result.append(
            UInt8((UInt64(crc) >> UInt64(23 - index)) & UInt64(1))
        )
    return result^


def _bit_checkpoint(
    testcase_id: StringSlice,
    stage: StringSlice,
    length: Int,
    *,
    layout: StringSlice = "bit-per-byte",
) raises -> CheckpointMetadata:
    return checkpoint_metadata_1d(
        testcase_id,
        stage,
        "uint8",
        length,
        q_format="binary-u1",
        layout=layout,
    )


def _coded_tx_checkpoint_metadata(
    testcase_id: StringSlice,
    preamble_symbols: Int,
    access_address_bits: Int,
    coding_indicator_bits: Int,
    term1_bits: Int,
    block_one_input_bits: Int,
    block_one_fec_bits: Int,
    block_one_mapped_symbols: Int,
    pdu_bits: Int,
    crc_bits: Int,
    pdu_and_crc_bits: Int,
    whitened_pdu_and_crc_bits: Int,
    term2_bits: Int,
    block_two_input_bits: Int,
    block_two_fec_bits: Int,
    block_two_mapped_symbols: Int,
    packet_symbols: Int,
) raises -> List[CheckpointMetadata]:
    var result = List[CheckpointMetadata](capacity=16)
    result.append(_bit_checkpoint(
        testcase_id,
        "coded-preamble-symbols",
        preamble_symbols,
        layout="symbol-per-byte",
    ))
    result.append(_bit_checkpoint(
        testcase_id, "access-address-bits", access_address_bits
    ))
    result.append(_bit_checkpoint(
        testcase_id, "coding-indicator-bits", coding_indicator_bits
    ))
    result.append(_bit_checkpoint(testcase_id, "term1-bits", term1_bits))
    result.append(_bit_checkpoint(
        testcase_id, "fec-block1-input-bits", block_one_input_bits
    ))
    result.append(_bit_checkpoint(
        testcase_id, "fec-block1-output-bits", block_one_fec_bits
    ))
    result.append(_bit_checkpoint(
        testcase_id,
        "fec-block1-mapped-symbols",
        block_one_mapped_symbols,
        layout="symbol-per-byte",
    ))
    result.append(_bit_checkpoint(testcase_id, "pdu-bits", pdu_bits))
    result.append(_bit_checkpoint(testcase_id, "crc-bits", crc_bits))
    result.append(_bit_checkpoint(
        testcase_id, "pdu-and-crc-bits", pdu_and_crc_bits
    ))
    result.append(_bit_checkpoint(
        testcase_id,
        "whitened-pdu-and-crc-bits",
        whitened_pdu_and_crc_bits,
    ))
    result.append(_bit_checkpoint(testcase_id, "term2-bits", term2_bits))
    result.append(_bit_checkpoint(
        testcase_id, "fec-block2-input-bits", block_two_input_bits
    ))
    result.append(_bit_checkpoint(
        testcase_id, "fec-block2-output-bits", block_two_fec_bits
    ))
    result.append(_bit_checkpoint(
        testcase_id,
        "fec-block2-mapped-symbols",
        block_two_mapped_symbols,
        layout="symbol-per-byte",
    ))
    result.append(_bit_checkpoint(
        testcase_id,
        "coded-packet-symbols",
        packet_symbols,
        layout="symbol-per-byte",
    ))
    return result^


def _coded_fec_rx_checkpoint_metadata(
    testcase_id: StringSlice,
    packet_symbols: Int,
    preamble_symbols: Int,
    block_one_mapped_symbols: Int,
    block_one_fec_bits: Int,
    term1_mapped_symbols: Int,
    term1_fec_bits: Int,
    block_one_decoded_bits: Int,
    access_address_bits: Int,
    coding_indicator_bits: Int,
    block_two_mapped_symbols: Int,
    block_two_fec_bits: Int,
    term2_mapped_symbols: Int,
    term2_fec_bits: Int,
    decoded_whitened_pdu_and_crc_bits: Int,
    decoded_whitened_pdu_bits: Int,
    decoded_whitened_crc_bits: Int,
) raises -> List[CheckpointMetadata]:
    var result = List[CheckpointMetadata](capacity=16)
    result.append(_bit_checkpoint(
        testcase_id,
        "received-coded-packet-symbols",
        packet_symbols,
        layout="symbol-per-byte",
    ))
    result.append(_bit_checkpoint(
        testcase_id,
        "received-coded-preamble-symbols",
        preamble_symbols,
        layout="symbol-per-byte",
    ))
    result.append(_bit_checkpoint(
        testcase_id,
        "received-fec-block1-mapped-symbols",
        block_one_mapped_symbols,
        layout="symbol-per-byte",
    ))
    result.append(_bit_checkpoint(
        testcase_id, "demapped-fec-block1-bits", block_one_fec_bits
    ))
    result.append(_bit_checkpoint(
        testcase_id,
        "received-term1-mapped-symbols",
        term1_mapped_symbols,
        layout="symbol-per-byte",
    ))
    result.append(_bit_checkpoint(
        testcase_id, "demapped-term1-fec-bits", term1_fec_bits
    ))
    result.append(_bit_checkpoint(
        testcase_id,
        "reference-decoded-fec-block1-data-bits",
        block_one_decoded_bits,
    ))
    result.append(_bit_checkpoint(
        testcase_id, "decoded-access-address-bits", access_address_bits
    ))
    result.append(_bit_checkpoint(
        testcase_id, "decoded-coding-indicator-bits", coding_indicator_bits
    ))
    result.append(_bit_checkpoint(
        testcase_id,
        "received-fec-block2-mapped-symbols",
        block_two_mapped_symbols,
        layout="symbol-per-byte",
    ))
    result.append(_bit_checkpoint(
        testcase_id, "demapped-fec-block2-bits", block_two_fec_bits
    ))
    result.append(_bit_checkpoint(
        testcase_id,
        "received-term2-mapped-symbols",
        term2_mapped_symbols,
        layout="symbol-per-byte",
    ))
    result.append(_bit_checkpoint(
        testcase_id, "demapped-term2-fec-bits", term2_fec_bits
    ))
    result.append(_bit_checkpoint(
        testcase_id,
        "reference-decoded-whitened-pdu-and-crc-bits",
        decoded_whitened_pdu_and_crc_bits,
    ))
    result.append(_bit_checkpoint(
        testcase_id,
        "reference-decoded-whitened-pdu-bits",
        decoded_whitened_pdu_bits,
    ))
    result.append(_bit_checkpoint(
        testcase_id,
        "reference-decoded-whitened-crc-bits",
        decoded_whitened_crc_bits,
    ))
    return result^


def bluetooth_le_coded_pattern_map(
    encoded_bits: Span[UInt8, ...], coding_s: Int
) raises -> List[UInt8]:
    """Map rate-1/2 FEC output bits to Core LE Coded PHY symbols.

    With S=2 (P=1), every input bit is emitted unchanged.  With S=8 (P=4),
    zero maps to ``0011`` and one maps to ``1100``, in transmission order.
    An empty sequence is accepted for compositional callers.
    """

    _validate_coding(coding_s)
    _validate_binary(encoded_bits)
    if coding_s == _CODING_S2:
        var result = List[UInt8](capacity=len(encoded_bits))
        for index in range(len(encoded_bits)):
            result.append(encoded_bits[index])
        return result^

    var result = List[UInt8](capacity=4 * len(encoded_bits))
    for index in range(len(encoded_bits)):
        var bit = encoded_bits[index]
        result.append(bit)
        result.append(bit)
        result.append(bit ^ UInt8(1))
        result.append(bit ^ UInt8(1))
    return result^


def bluetooth_le_coded_pattern_demap_exact(
    symbols: Span[UInt8, ...], coding_s: Int
) raises -> List[UInt8]:
    """Invert Core Table 3.1 only for exact binary mapper codewords.

    S=2 is the binary identity map.  S=8 accepts only complete ``0011`` and
    ``1100`` groups.  Corrupted-group correlation, majority decisions, soft
    combining, and other receiver policies are intentionally not invented by
    this exact discrete helper.
    """

    _validate_coding(coding_s)
    _validate_binary(symbols)
    if coding_s == _CODING_S2:
        return _copy_bits(symbols)
    if len(symbols) % 4 != 0:
        raise Error(
            "Bluetooth LE Coded exact S=8 symbols must contain complete "
            "four-symbol mapper codewords"
        )

    var result = List[UInt8](capacity=len(symbols) // 4)
    for group in range(len(symbols) // 4):
        var start = 4 * group
        var bit = symbols[start]
        if (
            symbols[start + 1] != bit
            or symbols[start + 2] != (bit ^ UInt8(1))
            or symbols[start + 3] != (bit ^ UInt8(1))
        ):
            raise Error(
                "Bluetooth LE Coded exact S=8 demapper received an "
                "unsupported hard-symbol codeword"
            )
        result.append(bit)
    return result^


def bluetooth_le_coded_packet_encode(
    pdu_bits: Span[UInt8, ...],
    access_address: Int,
    crc_init: Int,
    channel_index: Int,
    coding_s: Int,
    *,
    testcase_id: StringSlice = "bluetooth-le-coded-tx",
) raises -> BluetoothLECodedPacketEncodeResult:
    """Encode one complete Core 6.3 LE Coded packet to transmit symbols.

    ``pdu_bits`` are in transmission order, including least-significant-bit
    first within each Link Layer octet.  ``coding_s`` selects S=2 or S=8 for
    FEC block 2; FEC block 1 always uses S=8.  The returned result owns every
    intermediate and the complete symbol stream from the first preamble
    symbol through the final mapped TERM2 symbol.
    """

    _validate_pdu(pdu_bits)
    _validate_access_address(access_address)
    _validate_coding(coding_s)

    # The generic encoder implements the exact non-systematic K=4 rate-1/2
    # code.  TERM1/2 are made explicit runtime inputs so the returned result
    # retains the actual bits that drove both terminated trellises.
    var generators: List[Int] = [0b1111, 0b1101]

    var access_address_bits = List[UInt8](capacity=_ACCESS_ADDRESS_BITS)
    for index in range(_ACCESS_ADDRESS_BITS):
        access_address_bits.append(
            UInt8((UInt64(access_address) >> UInt64(index)) & UInt64(1))
        )
    # CI is transmitted least-significant bit first: 0b00 selects S=8 and
    # 0b01 selects S=2.
    var coding_indicator_bits: List[UInt8] = [
        UInt8(1 if coding_s == _CODING_S2 else 0), UInt8(0)
    ]
    var term1_bits = List[UInt8](length=3, fill=UInt8(0))
    var block_one_input = List[UInt8](
        capacity=len(access_address_bits)
        + len(coding_indicator_bits)
        + len(term1_bits)
    )
    for index in range(len(access_address_bits)):
        block_one_input.append(access_address_bits[index])
    for index in range(len(coding_indicator_bits)):
        block_one_input.append(coding_indicator_bits[index])
    for index in range(len(term1_bits)):
        block_one_input.append(term1_bits[index])
    var block_one_fec = convolutional_encode(
        Span(block_one_input), Span(generators), 4, terminate=False
    )
    var block_one_symbols = bluetooth_le_coded_pattern_map(
        Span(block_one_fec), _CODING_S8
    )

    # Reuse the existing Core CRC and whitening primitives.  Only PDU and CRC
    # are whitened; the explicit TERM2 bits are appended after whitening.
    var crc = bluetooth_le_crc24(pdu_bits, crc_init)
    var owned_pdu = _copy_bits(pdu_bits)
    var crc_bits = _crc_bit_list(crc)
    var block_two_input = List[UInt8](capacity=len(pdu_bits) + _CRC_BITS)
    for index in range(len(pdu_bits)):
        block_two_input.append(pdu_bits[index])
    for index in range(len(crc_bits)):
        block_two_input.append(crc_bits[index])
    var whitened_pdu_and_crc = bluetooth_le_whiten_bits(
        Span(block_two_input), channel_index
    )
    var term2_bits = List[UInt8](length=3, fill=UInt8(0))
    var terminated_block_two_input = List[UInt8](
        capacity=len(whitened_pdu_and_crc) + len(term2_bits)
    )
    for index in range(len(whitened_pdu_and_crc)):
        terminated_block_two_input.append(whitened_pdu_and_crc[index])
    for index in range(len(term2_bits)):
        terminated_block_two_input.append(term2_bits[index])
    var block_two_fec = convolutional_encode(
        Span(terminated_block_two_input),
        Span(generators),
        4,
        terminate=False,
    )
    var block_two_symbols = bluetooth_le_coded_pattern_map(
        Span(block_two_fec), coding_s
    )

    var preamble_symbols = List[UInt8](capacity=_PREAMBLE_SYMBOLS)
    for _ in range(10):
        preamble_symbols.append(0)
        preamble_symbols.append(0)
        preamble_symbols.append(1)
        preamble_symbols.append(1)
        preamble_symbols.append(1)
        preamble_symbols.append(1)
        preamble_symbols.append(0)
        preamble_symbols.append(0)
    var packet_symbols = List[UInt8](
        capacity=_PREAMBLE_SYMBOLS
        + len(block_one_symbols)
        + len(block_two_symbols)
    )
    for index in range(len(preamble_symbols)):
        packet_symbols.append(preamble_symbols[index])
    for index in range(len(block_one_symbols)):
        packet_symbols.append(block_one_symbols[index])
    for index in range(len(block_two_symbols)):
        packet_symbols.append(block_two_symbols[index])
    var checkpoint_metadata = _coded_tx_checkpoint_metadata(
        testcase_id,
        len(preamble_symbols),
        len(access_address_bits),
        len(coding_indicator_bits),
        len(term1_bits),
        len(block_one_input),
        len(block_one_fec),
        len(block_one_symbols),
        len(owned_pdu),
        len(crc_bits),
        len(block_two_input),
        len(whitened_pdu_and_crc),
        len(term2_bits),
        len(terminated_block_two_input),
        len(block_two_fec),
        len(block_two_symbols),
        len(packet_symbols),
    )
    return BluetoothLECodedPacketEncodeResult(
        preamble_symbols^,
        access_address_bits^,
        coding_indicator_bits^,
        term1_bits^,
        block_one_input^,
        block_one_fec^,
        block_one_symbols^,
        owned_pdu^,
        crc_bits^,
        block_two_input^,
        whitened_pdu_and_crc^,
        term2_bits^,
        terminated_block_two_input^,
        block_two_fec^,
        block_two_symbols^,
        packet_symbols^,
        checkpoint_metadata^,
        crc,
        coding_s,
    )


def bluetooth_le_coded_packet_fec_decode_hard_reference(
    packet_symbols: Span[UInt8, ...],
    *,
    testcase_id: StringSlice = "bluetooth-le-coded-fec-rx-reference",
) raises -> BluetoothLECodedPacketFECDecodeReferenceResult:
    """Decode a known-boundary exact-codeword packet through both FEC blocks.

    The packet must start at the first uncoded preamble symbol and end at the
    final mapped TERM2 symbol.  FEC block 1 always uses the exact S=8 inverse;
    its decoded CI selects S=2 or S=8 for block 2.  Both blocks reuse the
    generic hard Viterbi implementation with the Core K=4 generators and the
    known zero termination constraint.

    This reference function returns the still-whitened PDU and CRC regions.
    It performs no RF demodulation, synchronization, dewhitening, CRC check,
    Access Address comparison, or packet-validity decision.
    """

    if (
        len(packet_symbols) < _MIN_CODED_PACKET_SYMBOLS
        or len(packet_symbols) > _MAX_CODED_PACKET_SYMBOLS
    ):
        raise Error(
            "Bluetooth LE Coded reference packet is outside the complete "
            "2 through 257-octet symbol-length envelope"
        )
    _validate_binary(packet_symbols)

    var owned_packet = _copy_bits(packet_symbols)
    var preamble_symbols = _copy_bit_range(
        packet_symbols, 0, _PREAMBLE_SYMBOLS
    )
    var preamble_matches_exact = True
    for index in range(_PREAMBLE_SYMBOLS):
        var position = index % 8
        var expected = UInt8(1 if position >= 2 and position <= 5 else 0)
        if preamble_symbols[index] != expected:
            preamble_matches_exact = False

    var block_one_mapped_symbols = _copy_bit_range(
        packet_symbols,
        _PREAMBLE_SYMBOLS,
        _CODED_FIXED_PREFIX_SYMBOLS,
    )
    var block_one_fec_bits = bluetooth_le_coded_pattern_demap_exact(
        Span(block_one_mapped_symbols), _CODING_S8
    )
    if len(block_one_fec_bits) != _BLOCK_ONE_FEC_BITS:
        raise Error("Bluetooth LE Coded internal block 1 geometry mismatch")
    var term1_mapped_symbols = _copy_bit_range(
        Span(block_one_mapped_symbols),
        len(block_one_mapped_symbols) - 4 * _TERMINATION_FEC_BITS,
        len(block_one_mapped_symbols),
    )
    var term1_fec_bits = _copy_bit_range(
        Span(block_one_fec_bits),
        len(block_one_fec_bits) - _TERMINATION_FEC_BITS,
        len(block_one_fec_bits),
    )

    var generators: List[Int] = [0b1111, 0b1101]
    var block_one_decoded_bits = viterbi_decode_hard(
        Span(block_one_fec_bits), Span(generators), 4, terminate=True
    )
    if len(block_one_decoded_bits) != _BLOCK_ONE_DATA_BITS:
        raise Error(
            "Bluetooth LE Coded reference Viterbi block 1 output has an "
            "invalid length"
        )
    var access_address_bits = _copy_bit_range(
        Span(block_one_decoded_bits), 0, _ACCESS_ADDRESS_BITS
    )
    var coding_indicator_bits = _copy_bit_range(
        Span(block_one_decoded_bits),
        _ACCESS_ADDRESS_BITS,
        _BLOCK_ONE_DATA_BITS,
    )
    var ci_value = Int(coding_indicator_bits[0]) | (
        Int(coding_indicator_bits[1]) << 1
    )
    if ci_value != 0 and ci_value != 1:
        raise Error(
            "Bluetooth LE Coded reference decoder does not accept a "
            "reserved Coding Indicator"
        )
    var coding_s = _CODING_S8 if ci_value == 0 else _CODING_S2

    var geometry_base = 430 if coding_s == _CODING_S2 else 592
    var geometry_step = 16 if coding_s == _CODING_S2 else 64
    var geometry_numerator = len(packet_symbols) - geometry_base
    if geometry_numerator < 0 or geometry_numerator % geometry_step != 0:
        raise Error(
            "Bluetooth LE Coded reference packet has invalid CI-selected "
            "symbol geometry"
        )
    var pdu_octets = geometry_numerator // geometry_step
    if pdu_octets < 2 or pdu_octets > 257:
        raise Error(
            "Bluetooth LE Coded reference packet must contain a 2 through "
            "257-octet PDU region"
        )

    var block_two_mapped_symbols = _copy_bit_range(
        packet_symbols, _CODED_FIXED_PREFIX_SYMBOLS, len(packet_symbols)
    )
    var block_two_fec_bits = bluetooth_le_coded_pattern_demap_exact(
        Span(block_two_mapped_symbols), coding_s
    )
    var expected_block_two_fec_bits = 16 * pdu_octets + 54
    if len(block_two_fec_bits) != expected_block_two_fec_bits:
        raise Error("Bluetooth LE Coded internal block 2 geometry mismatch")
    var term2_mapped_symbols = _copy_bit_range(
        Span(block_two_mapped_symbols),
        len(block_two_mapped_symbols) - 3 * coding_s,
        len(block_two_mapped_symbols),
    )
    var term2_fec_bits = _copy_bit_range(
        Span(block_two_fec_bits),
        len(block_two_fec_bits) - _TERMINATION_FEC_BITS,
        len(block_two_fec_bits),
    )
    var decoded_whitened_pdu_and_crc_bits = viterbi_decode_hard(
        Span(block_two_fec_bits), Span(generators), 4, terminate=True
    )
    var decoded_body_bits = 8 * pdu_octets + _CRC_BITS
    if len(decoded_whitened_pdu_and_crc_bits) != decoded_body_bits:
        raise Error(
            "Bluetooth LE Coded reference Viterbi block 2 output has an "
            "invalid length"
        )
    var decoded_whitened_pdu_bits = _copy_bit_range(
        Span(decoded_whitened_pdu_and_crc_bits), 0, 8 * pdu_octets
    )
    var decoded_whitened_crc_bits = _copy_bit_range(
        Span(decoded_whitened_pdu_and_crc_bits),
        8 * pdu_octets,
        decoded_body_bits,
    )

    var received_access_address_u64 = UInt64(0)
    for index in range(_ACCESS_ADDRESS_BITS):
        received_access_address_u64 |= (
            UInt64(access_address_bits[index]) << UInt64(index)
        )
    var checkpoint_metadata = _coded_fec_rx_checkpoint_metadata(
        testcase_id,
        len(owned_packet),
        len(preamble_symbols),
        len(block_one_mapped_symbols),
        len(block_one_fec_bits),
        len(term1_mapped_symbols),
        len(term1_fec_bits),
        len(block_one_decoded_bits),
        len(access_address_bits),
        len(coding_indicator_bits),
        len(block_two_mapped_symbols),
        len(block_two_fec_bits),
        len(term2_mapped_symbols),
        len(term2_fec_bits),
        len(decoded_whitened_pdu_and_crc_bits),
        len(decoded_whitened_pdu_bits),
        len(decoded_whitened_crc_bits),
    )
    return BluetoothLECodedPacketFECDecodeReferenceResult(
        owned_packet^,
        preamble_symbols^,
        block_one_mapped_symbols^,
        block_one_fec_bits^,
        term1_mapped_symbols^,
        term1_fec_bits^,
        block_one_decoded_bits^,
        access_address_bits^,
        coding_indicator_bits^,
        block_two_mapped_symbols^,
        block_two_fec_bits^,
        term2_mapped_symbols^,
        term2_fec_bits^,
        decoded_whitened_pdu_and_crc_bits^,
        decoded_whitened_pdu_bits^,
        decoded_whitened_crc_bits^,
        checkpoint_metadata^,
        UInt32(received_access_address_u64),
        coding_s,
        pdu_octets,
        preamble_matches_exact,
    )
