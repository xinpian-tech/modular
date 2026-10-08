"""Independent evidence for the Bluetooth Core 6.3 LE Coded FEC RX slice.

The 510-symbol S=2 and 912-symbol S=8 fixtures are complete transcriptions of
Vol 6, Part C, Sections 2.1 through 2.4 in the adopted Core 6.3 artifact with
SHA-256 e210fb8f697fca2b970001d35f8c9c7c8f836190550b7fd29d2915a1c8596d60.
Seeded and geometry fixtures use only the test-local delay-cell encoder and
Table 3.1 transcription below; production TX is never used as an RX oracle.
"""

from std.collections import Span
from std.testing import TestSuite, assert_equal, assert_raises, assert_true
from wireless_dsp.testing import CheckpointMetadata
from wireless_dsp.wireless.bluetooth import (
    bluetooth_le_coded_packet_fec_decode_hard_reference,
    bluetooth_le_coded_pattern_demap_exact,
)


def _parse_bits(value: StringSlice) raises -> List[UInt8]:
    var result = List[UInt8](capacity=value.byte_length())
    for index in range(value.byte_length()):
        var code = ord(value[byte=index])
        if code != ord("0") and code != ord("1"):
            raise Error("test vector is not binary")
        result.append(UInt8(code - ord("0")))
    return result^


def _append_text(mut result: List[UInt8], value: StringSlice) raises:
    var bits = _parse_bits(value)
    for index in range(len(bits)):
        result.append(bits[index])


def _append_bits(mut result: List[UInt8], bits: Span[UInt8, ...]):
    for index in range(len(bits)):
        result.append(bits[index])


def _slice(bits: Span[UInt8, ...], start: Int, end: Int) -> List[UInt8]:
    var result = List[UInt8](capacity=end - start)
    for index in range(start, end):
        result.append(bits[index])
    return result^


def _official_s2_symbols() raises -> List[UInt8]:
    var result = List[UInt8](capacity=510)
    _append_text(
        result,
        "0011110000111100001111000011110000111100001111000011110000111100",
    )
    _append_text(
        result,
        "0011110000111100001100111100110000111100001111001100110000111100",
    )
    _append_text(
        result,
        "0011001111000011001111001100110011000011110000110011110000111100",
    )
    _append_text(
        result,
        "1100001111001100110000110011110000110011001100111100001111001100",
    )
    _append_text(
        result,
        "1100110011001100110000110011001111000011110000111100001100110011",
    )
    _append_text(
        result,
        "1100110011001100001111000011110000110011110011000011001100000000",
    )
    _append_text(
        result,
        "0000000011010100110000000011101111001110111111010100001000010001",
    )
    _append_text(
        result,
        "11111110000111001000011111111000011111000011011010000001010011",
    )
    return result^


def _official_s8_symbols() raises -> List[UInt8]:
    var result = List[UInt8](capacity=912)
    _append_text(
        result,
        "0011110000111100001111000011110000111100001111000011110000111100",
    )
    _append_text(
        result,
        "0011110000111100001100111100110000111100001111001100110000111100",
    )
    _append_text(
        result,
        "0011001111000011001111001100110011000011110000110011110000111100",
    )
    _append_text(
        result,
        "1100001111001100110000110011110000110011001100111100001111001100",
    )
    _append_text(
        result,
        "1100110011001100110000110011001111000011110000111100001100110011",
    )
    _append_text(
        result,
        "1100110011001100110000111100110011001100001100110011001100110011",
    )
    _append_text(
        result,
        "0011001100110011001100110011001100110011001100110011001111001100",
    )
    _append_text(
        result,
        "0011110000111100001100111100110000110011001100110011001100110011",
    )
    _append_text(
        result,
        "1100110011000011110011001100110000110011110011001100001111001100",
    )
    _append_text(
        result,
        "1100110011001100001111000011110000110011001100111100001100110011",
    )
    _append_text(
        result,
        "0011110000110011001111001100110011001100110011001100001100110011",
    )
    _append_text(
        result,
        "0011110011001100001100111100001100110011001111001100110011001100",
    )
    _append_text(
        result,
        "1100110011000011001100110011110011001100110011000011001100110011",
    )
    _append_text(
        result,
        "1100110000111100110000111100001100110011001100110011110000111100",
    )
    _append_text(result, "0011001111001100")
    return result^


def _oracle_fec(data_bits: Span[UInt8, ...]) -> List[UInt8]:
    # Independent explicit delay-cell form of G0=1111 and G1=1101.
    var d1 = UInt8(0)
    var d2 = UInt8(0)
    var d3 = UInt8(0)
    var result = List[UInt8](capacity=2 * (len(data_bits) + 3))
    for step in range(len(data_bits) + 3):
        var bit = data_bits[step] if step < len(data_bits) else UInt8(0)
        result.append(bit ^ d1 ^ d2 ^ d3)
        result.append(bit ^ d2 ^ d3)
        d3 = d2
        d2 = d1
        d1 = bit
    return result^


def _oracle_map(bits: Span[UInt8, ...], coding_s: Int) -> List[UInt8]:
    var result = List[UInt8](
        capacity=len(bits) if coding_s == 2 else 4 * len(bits)
    )
    for index in range(len(bits)):
        var bit = bits[index]
        result.append(bit)
        if coding_s == 8:
            result.append(bit)
            result.append(bit ^ UInt8(1))
            result.append(bit ^ UInt8(1))
    return result^


def _oracle_packet_with_ci(
    body_bits: Span[UInt8, ...], access_address: Int, ci_value: Int,
    block_two_s: Int,
) -> List[UInt8]:
    var block_one_data = List[UInt8](capacity=34)
    for index in range(32):
        block_one_data.append(UInt8((access_address >> index) & 1))
    block_one_data.append(UInt8(ci_value & 1))
    block_one_data.append(UInt8((ci_value >> 1) & 1))
    var block_one_fec = _oracle_fec(Span(block_one_data))
    var block_one_symbols = _oracle_map(Span(block_one_fec), 8)
    var block_two_fec = _oracle_fec(body_bits)
    var block_two_symbols = _oracle_map(Span(block_two_fec), block_two_s)

    var result = List[UInt8](
        capacity=80 + len(block_one_symbols) + len(block_two_symbols)
    )
    for _ in range(10):
        result.append(0)
        result.append(0)
        result.append(1)
        result.append(1)
        result.append(1)
        result.append(1)
        result.append(0)
        result.append(0)
    _append_bits(result, Span(block_one_symbols))
    _append_bits(result, Span(block_two_symbols))
    return result^


def _oracle_packet(
    body_bits: Span[UInt8, ...], access_address: Int, coding_s: Int
) -> List[UInt8]:
    return _oracle_packet_with_ci(
        body_bits, access_address, 1 if coding_s == 2 else 0, coding_s
    )


def _next(mut state: UInt64) -> UInt64:
    state = state * UInt64(6364136223846793005) + UInt64(1442695040888963407)
    return state


def _seeded_bits(length: Int, mut state: UInt64) -> List[UInt8]:
    var result = List[UInt8](capacity=length)
    for _ in range(length):
        result.append(UInt8((_next(state) >> UInt64(63)) & UInt64(1)))
    return result^


def _assert_metadata(
    metadata: List[CheckpointMetadata],
    testcase_id: StringSlice,
    lengths: List[Int],
) raises:
    var stages: List[String] = [
        "received-coded-packet-symbols",
        "received-coded-preamble-symbols",
        "received-fec-block1-mapped-symbols",
        "demapped-fec-block1-bits",
        "received-term1-mapped-symbols",
        "demapped-term1-fec-bits",
        "reference-decoded-fec-block1-data-bits",
        "decoded-access-address-bits",
        "decoded-coding-indicator-bits",
        "received-fec-block2-mapped-symbols",
        "demapped-fec-block2-bits",
        "received-term2-mapped-symbols",
        "demapped-term2-fec-bits",
        "reference-decoded-whitened-pdu-and-crc-bits",
        "reference-decoded-whitened-pdu-bits",
        "reference-decoded-whitened-crc-bits",
    ]
    assert_equal(len(metadata), 16)
    assert_equal(len(lengths), 16)
    for index in range(16):
        var shape = String()
        shape.write(lengths[index])
        assert_equal(metadata[index].testcase_id, testcase_id)
        assert_equal(metadata[index].stage, stages[index])
        assert_equal(metadata[index].dtype, "uint8")
        assert_equal(metadata[index].shape, shape)
        assert_equal(metadata[index].stride, "1")
        assert_equal(metadata[index].q_format, "binary-u1")
        assert_equal(metadata[index].scale, 1.0)
        assert_equal(metadata[index].version, 1)
        var is_symbol_stage = (
            index == 0
            or index == 1
            or index == 2
            or index == 4
            or index == 9
            or index == 11
        )
        var expected_layout = (
            "symbol-per-byte" if is_symbol_stage else "bit-per-byte"
        )
        assert_equal(metadata[index].layout, expected_layout)


def test_part_c_complete_s2_s8_reference_receive_checkpoints() raises:
    var expected_access_ci_s2 = _parse_bits(
        "0110101101111101100100010111000110"
    )
    var expected_access_ci_s8 = _parse_bits(
        "0110101101111101100100010111000100"
    )
    var expected_body = _parse_bits(
        "0000000011000000010000100011001010100010100101000101000001110011"
    )
    var expected_block_one_s2 = _parse_bits(
        "00110101110100100111101001011011100100001011111110001010100011110101001100"
    )
    var expected_block_one_s8 = _parse_bits(
        "00110101110100100111101001011011100100001011111110001010100011111011110000"
    )
    var expected_block_two = _parse_bits(
        "00000000000000001101010011000000001110111100111011111101010000100001000111111110000111001000011111111000011111000011011010000001010011"
    )
    var expected_term1_s2 = _parse_bits("001100")
    var expected_term1_s8 = _parse_bits("110000")
    var expected_term2 = _parse_bits("010011")
    var expected_term1_mapped_s2 = _parse_bits(
        "001100111100110000110011"
    )
    var expected_term1_mapped_s8 = _parse_bits(
        "110011000011001100110011"
    )
    var expected_term2_mapped_s2 = _parse_bits("010011")
    var expected_term2_mapped_s8 = _parse_bits(
        "001111000011001111001100"
    )

    var s2_symbols = _official_s2_symbols()
    var s2 = bluetooth_le_coded_packet_fec_decode_hard_reference(
        Span(s2_symbols), testcase_id="core-6.3-part-c-2.3-s2"
    )
    assert_equal(s2.block_one_fec_bits, expected_block_one_s2)
    assert_equal(s2.block_one_decoded_bits, expected_access_ci_s2)
    assert_equal(s2.block_two_fec_bits, expected_block_two)
    assert_equal(s2.decoded_whitened_pdu_and_crc_bits, expected_body)
    assert_equal(s2.term1_fec_bits, expected_term1_s2)
    assert_equal(s2.term2_fec_bits, expected_term2)
    assert_equal(s2.term1_mapped_symbols, expected_term1_mapped_s2)
    assert_equal(s2.term2_mapped_symbols, expected_term2_mapped_s2)
    assert_equal(s2.received_access_address, UInt32(0x8E89BED6))
    assert_equal(s2.coding_s, 2)
    assert_equal(s2.pdu_octets, 5)
    assert_true(s2.preamble_matches_exact)
    assert_equal(s2.decoded_whitened_pdu_bits, _slice(Span(expected_body), 0, 40))
    assert_equal(s2.decoded_whitened_crc_bits, _slice(Span(expected_body), 40, 64))

    var s8_symbols = _official_s8_symbols()
    var s8 = bluetooth_le_coded_packet_fec_decode_hard_reference(
        Span(s8_symbols), testcase_id="core-6.3-part-c-2.4-s8"
    )
    assert_equal(s8.block_one_fec_bits, expected_block_one_s8)
    assert_equal(s8.block_one_decoded_bits, expected_access_ci_s8)
    assert_equal(s8.block_two_fec_bits, expected_block_two)
    assert_equal(s8.decoded_whitened_pdu_and_crc_bits, expected_body)
    assert_equal(s8.term1_fec_bits, expected_term1_s8)
    assert_equal(s8.term2_fec_bits, expected_term2)
    assert_equal(s8.term1_mapped_symbols, expected_term1_mapped_s8)
    assert_equal(s8.term2_mapped_symbols, expected_term2_mapped_s8)
    assert_equal(s8.received_access_address, UInt32(0x8E89BED6))
    assert_equal(s8.coding_s, 8)
    assert_equal(s8.pdu_octets, 5)
    assert_true(s8.preamble_matches_exact)
    assert_equal(
        s2.term1_mapped_symbols,
        _slice(Span(s2.block_one_mapped_symbols), 272, 296),
    )
    assert_equal(
        s8.term2_mapped_symbols,
        _slice(
            Span(s8.block_two_mapped_symbols),
            len(s8.block_two_mapped_symbols) - 24,
            len(s8.block_two_mapped_symbols),
        ),
    )


def test_pattern_demap_exact_table_exhaustive_and_bad_codewords() raises:
    var table_symbols_s2: List[UInt8] = [0, 1]
    var table_symbols_s8: List[UInt8] = [0, 0, 1, 1, 1, 1, 0, 0]
    var table_bits: List[UInt8] = [0, 1]
    assert_equal(
        bluetooth_le_coded_pattern_demap_exact(Span(table_symbols_s2), 2),
        table_bits,
    )
    assert_equal(
        bluetooth_le_coded_pattern_demap_exact(Span(table_symbols_s8), 8),
        table_bits,
    )
    assert_equal(
        len(bluetooth_le_coded_pattern_demap_exact(Span(List[UInt8]()), 2)),
        0,
    )
    assert_equal(
        len(bluetooth_le_coded_pattern_demap_exact(Span(List[UInt8]()), 8)),
        0,
    )

    for word in range(256):
        var bits = List[UInt8](capacity=8)
        for index in range(8):
            bits.append(UInt8((word >> index) & 1))
        for coding_s in [2, 8]:
            var mapped = _oracle_map(Span(bits), coding_s)
            assert_equal(
                bluetooth_le_coded_pattern_demap_exact(
                    Span(mapped), coding_s
                ),
                bits,
            )

    var accepted = 0
    for word in range(16):
        var group = List[UInt8](capacity=4)
        for index in range(4):
            group.append(UInt8((word >> (3 - index)) & 1))
        if word == 0b0011:
            var expected: List[UInt8] = [0]
            assert_equal(
                bluetooth_le_coded_pattern_demap_exact(Span(group), 8),
                expected,
            )
            accepted += 1
        elif word == 0b1100:
            var expected: List[UInt8] = [1]
            assert_equal(
                bluetooth_le_coded_pattern_demap_exact(Span(group), 8),
                expected,
            )
            accepted += 1
        else:
            with assert_raises():
                _ = bluetooth_le_coded_pattern_demap_exact(Span(group), 8)
    assert_equal(accepted, 2)


def test_seeded_independent_known_symbol_receive_differential() raises:
    var state = UInt64(0x63C0DEDFEC123456)
    for case_index in range(32):
        var pdu_octets = 2 + Int(_next(state) % UInt64(256))
        var body = _seeded_bits(8 * pdu_octets + 24, state)
        var access_address = Int(_next(state) & UInt64(0xFFFFFFFF))
        var coding_s = 2 if case_index % 2 == 0 else 8
        var expected_packet = _oracle_packet(
            Span(body), access_address, coding_s
        )
        var actual = bluetooth_le_coded_packet_fec_decode_hard_reference(
            Span(expected_packet)
        )
        assert_equal(actual.packet_symbols, expected_packet)
        assert_equal(actual.decoded_whitened_pdu_and_crc_bits, body)
        assert_equal(actual.received_access_address, UInt32(access_address))
        assert_equal(actual.coding_s, coding_s)
        assert_equal(actual.pdu_octets, pdu_octets)
        assert_true(actual.preamble_matches_exact)
        assert_equal(
            actual.term1_fec_bits,
            _slice(
                Span(actual.block_one_fec_bits),
                len(actual.block_one_fec_bits) - 6,
                len(actual.block_one_fec_bits),
            ),
        )
        assert_equal(
            actual.term2_fec_bits,
            _slice(
                Span(actual.block_two_fec_bits),
                len(actual.block_two_fec_bits) - 6,
                len(actual.block_two_fec_bits),
            ),
        )


def test_every_legal_coded_packet_geometry_and_endpoints() raises:
    for pdu_octets in range(2, 258):
        var body = List[UInt8](capacity=8 * pdu_octets + 24)
        for index in range(8 * pdu_octets + 24):
            body.append(UInt8(((index * 7) ^ pdu_octets) & 1))
        for coding_s in [2, 8]:
            var packet = _oracle_packet(
                Span(body), 0 if pdu_octets == 2 else 0xFFFFFFFF, coding_s
            )
            var actual = bluetooth_le_coded_packet_fec_decode_hard_reference(
                Span(packet)
            )
            var expected_length = (
                430 + 16 * pdu_octets
                if coding_s == 2
                else 592 + 64 * pdu_octets
            )
            assert_equal(len(packet), expected_length)
            assert_equal(actual.pdu_octets, pdu_octets)
            assert_equal(actual.coding_s, coding_s)
            assert_equal(actual.decoded_whitened_pdu_and_crc_bits, body)
            assert_equal(len(actual.block_one_fec_bits), 74)
            assert_equal(len(actual.block_one_decoded_bits), 34)
            assert_equal(
                len(actual.block_two_fec_bits), 16 * pdu_octets + 54
            )
            assert_equal(
                len(actual.decoded_whitened_pdu_and_crc_bits),
                8 * pdu_octets + 24,
            )


def test_structural_reserved_shapes_binary_and_integer_edges() raises:
    var body = List[UInt8](length=40, fill=UInt8(0))
    var valid_s2 = _oracle_packet(Span(body), 0, 2)
    var valid_s8 = _oracle_packet(Span(body), 0xFFFFFFFF, 8)

    # These are otherwise exact, independently encoded packets whose body
    # geometry represents the adjacent illegal one- and 258-octet PDU
    # endpoints.  They isolate the normative PDU bound from mapper, FEC,
    # binary-input, and outer symbol-envelope rejection.
    var one_octet_body = List[UInt8](length=8 + 24, fill=UInt8(0))
    var one_octet_s8 = _oracle_packet(
        Span(one_octet_body), 0x8E89BED6, 8
    )
    with assert_raises():
        _ = bluetooth_le_coded_packet_fec_decode_hard_reference(
            Span(one_octet_s8)
        )
    var two_hundred_fifty_eight_octet_body = List[UInt8](
        length=8 * 258 + 24, fill=UInt8(0)
    )
    var two_hundred_fifty_eight_octet_s2 = _oracle_packet(
        Span(two_hundred_fifty_eight_octet_body), 0x8E89BED6, 2
    )
    with assert_raises():
        _ = bluetooth_le_coded_packet_fec_decode_hard_reference(
            Span(two_hundred_fifty_eight_octet_s2)
        )

    for invalid_coding in [0, 1, 3, 7, 9, Int.MIN, Int.MAX]:
        with assert_raises():
            _ = bluetooth_le_coded_pattern_demap_exact(
                Span(List[UInt8]()), invalid_coding
            )
    for invalid_length in [1, 2, 3, 5, 6, 7]:
        var partial = List[UInt8](length=invalid_length, fill=UInt8(0))
        with assert_raises():
            _ = bluetooth_le_coded_pattern_demap_exact(Span(partial), 8)
    for nonbinary in [UInt8(2), UInt8(255)]:
        var bad_symbols: List[UInt8] = [0, 0, 1, nonbinary]
        with assert_raises():
            _ = bluetooth_le_coded_pattern_demap_exact(Span(bad_symbols), 8)
        var bad_packet = valid_s2.copy()
        bad_packet[0] = nonbinary
        with assert_raises():
            _ = bluetooth_le_coded_packet_fec_decode_hard_reference(
                Span(bad_packet)
            )

    for invalid_size in [0, 1, 461, 17041]:
        var invalid_packet = List[UInt8](
            length=invalid_size, fill=UInt8(0)
        )
        with assert_raises():
            _ = bluetooth_le_coded_packet_fec_decode_hard_reference(
                Span(invalid_packet)
            )
    var malformed_s2 = valid_s2.copy()
    malformed_s2.append(0)
    with assert_raises():
        _ = bluetooth_le_coded_packet_fec_decode_hard_reference(
            Span(malformed_s2)
        )
    var malformed_s8 = valid_s8.copy()
    malformed_s8.append(0)
    malformed_s8.append(0)
    malformed_s8.append(1)
    malformed_s8.append(1)
    with assert_raises():
        _ = bluetooth_le_coded_packet_fec_decode_hard_reference(
            Span(malformed_s8)
        )

    var bad_block_one = valid_s2.copy()
    bad_block_one[80] ^= 1
    with assert_raises():
        _ = bluetooth_le_coded_packet_fec_decode_hard_reference(
            Span(bad_block_one)
        )
    var bad_block_two = valid_s8.copy()
    bad_block_two[376] ^= 1
    with assert_raises():
        _ = bluetooth_le_coded_packet_fec_decode_hard_reference(
            Span(bad_block_two)
        )

    for reserved_ci in [2, 3]:
        var reserved = _oracle_packet_with_ci(Span(body), 0, reserved_ci, 2)
        with assert_raises():
            _ = bluetooth_le_coded_packet_fec_decode_hard_reference(
                Span(reserved)
            )

    var bad_preamble = valid_s2.copy()
    bad_preamble[0] ^= 1
    var diagnostic = bluetooth_le_coded_packet_fec_decode_hard_reference(
        Span(bad_preamble)
    )
    assert_equal(diagnostic.preamble_matches_exact, False)
    assert_equal(diagnostic.decoded_whitened_pdu_and_crc_bits, body)


def test_owned_reference_intermediates_metadata_and_term_observations() raises:
    for coding_s in [2, 8]:
        var body = _parse_bits(
            "0110100010100000001101010101010110110010"
        )
        var packet = _oracle_packet(Span(body), 0xAA08192B, coding_s)
        var original_packet = packet.copy()
        var testcase = String("bluetooth-coded-fec-rx-owned-s")
        testcase.write(coding_s)
        var expected_testcase = String("bluetooth-coded-fec-rx-owned-s")
        expected_testcase.write(coding_s)
        var actual = bluetooth_le_coded_packet_fec_decode_hard_reference(
            Span(packet), testcase_id=testcase
        )
        testcase.write("-caller-mutated")
        packet[0] ^= 1

        # Reconstruct every owned result list from test-local packet slices,
        # the independent delay-cell encoder, and the independent Table 3.1
        # mapper.  No production TX or demapper output is reused as an oracle.
        var expected_preamble = _slice(Span(original_packet), 0, 80)
        var expected_access = List[UInt8](capacity=32)
        for index in range(32):
            expected_access.append(UInt8((0xAA08192B >> index) & 1))
        var expected_ci = List[UInt8](capacity=2)
        expected_ci.append(UInt8(1 if coding_s == 2 else 0))
        expected_ci.append(0)
        var expected_block_one_data = List[UInt8](capacity=34)
        _append_bits(expected_block_one_data, Span(expected_access))
        _append_bits(expected_block_one_data, Span(expected_ci))
        var expected_block_one_fec = _oracle_fec(
            Span(expected_block_one_data)
        )
        var expected_block_one_mapped = _oracle_map(
            Span(expected_block_one_fec), 8
        )
        var expected_term1_fec = _slice(
            Span(expected_block_one_fec),
            len(expected_block_one_fec) - 6,
            len(expected_block_one_fec),
        )
        var expected_term1_mapped = _slice(
            Span(expected_block_one_mapped),
            len(expected_block_one_mapped) - 24,
            len(expected_block_one_mapped),
        )
        var expected_block_two_fec = _oracle_fec(Span(body))
        var expected_block_two_mapped = _oracle_map(
            Span(expected_block_two_fec), coding_s
        )
        var expected_term2_fec = _slice(
            Span(expected_block_two_fec),
            len(expected_block_two_fec) - 6,
            len(expected_block_two_fec),
        )
        var expected_term2_mapped = _slice(
            Span(expected_block_two_mapped),
            len(expected_block_two_mapped) - 3 * coding_s,
            len(expected_block_two_mapped),
        )
        var expected_pdu = _slice(Span(body), 0, 16)
        var expected_crc = _slice(Span(body), 16, 40)

        assert_equal(actual.packet_symbols, original_packet)
        assert_equal(actual.preamble_symbols, expected_preamble)
        assert_equal(
            actual.block_one_mapped_symbols, expected_block_one_mapped
        )
        assert_equal(actual.block_one_fec_bits, expected_block_one_fec)
        assert_equal(actual.term1_mapped_symbols, expected_term1_mapped)
        assert_equal(actual.term1_fec_bits, expected_term1_fec)
        assert_equal(
            actual.block_one_decoded_bits, expected_block_one_data
        )
        assert_equal(actual.access_address_bits, expected_access)
        assert_equal(actual.coding_indicator_bits, expected_ci)
        assert_equal(
            actual.block_two_mapped_symbols, expected_block_two_mapped
        )
        assert_equal(actual.block_two_fec_bits, expected_block_two_fec)
        assert_equal(actual.term2_mapped_symbols, expected_term2_mapped)
        assert_equal(actual.term2_fec_bits, expected_term2_fec)
        assert_true(actual.preamble_matches_exact)
        assert_equal(actual.decoded_whitened_pdu_and_crc_bits, body)
        assert_equal(actual.decoded_whitened_pdu_bits, expected_pdu)
        assert_equal(actual.decoded_whitened_crc_bits, expected_crc)
        var pdu_octets = 2
        var block_two_mapped = 86 if coding_s == 2 else 344
        var lengths: List[Int] = [
            len(original_packet),
            80,
            296,
            74,
            24,
            6,
            34,
            32,
            2,
            block_two_mapped,
            86,
            3 * coding_s,
            6,
            8 * pdu_octets + 24,
            8 * pdu_octets,
            24,
        ]
        _assert_metadata(
            actual.checkpoint_metadata, expected_testcase, lengths
        )

    for invalid_testcase in ["", "bad\nidentifier", "bad\ridentifier"]:
        var body = List[UInt8](length=40, fill=UInt8(0))
        var packet = _oracle_packet(Span(body), 0, 2)
        with assert_raises():
            _ = bluetooth_le_coded_packet_fec_decode_hard_reference(
                Span(packet), testcase_id=invalid_testcase
            )


def test_mutable_inputs_are_revalidated_on_every_public_call() raises:
    var mapped: List[UInt8] = [0, 0, 1, 1]
    _ = bluetooth_le_coded_pattern_demap_exact(Span(mapped), 8)
    mapped[0] = 2
    with assert_raises():
        _ = bluetooth_le_coded_pattern_demap_exact(Span(mapped), 8)

    var body = List[UInt8](length=40, fill=UInt8(1))
    var packet = _oracle_packet(Span(body), 0xFFFFFFFF, 8)
    _ = bluetooth_le_coded_packet_fec_decode_hard_reference(Span(packet))
    var original_symbol = packet[376]
    packet[376] = 2
    with assert_raises():
        _ = bluetooth_le_coded_packet_fec_decode_hard_reference(Span(packet))
    packet[376] = original_symbol
    packet[377] ^= 1
    with assert_raises():
        _ = bluetooth_le_coded_packet_fec_decode_hard_reference(Span(packet))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
