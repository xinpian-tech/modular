"""Independent evidence for the Bluetooth Core 6.3 LE Coded TX slice.

The complete 510-symbol S=2 and 912-symbol S=8 sample streams are transcribed
from Vol 6, Part C, Sections 2.1 through 2.4 of the official Core 6.3 PDF
(SHA-256 e210fb8f697fca2b970001d35f8c9c7c8f836190550b7fd29d2915a1c8596d60).
That sample intentionally begins at the FEC input and does not specify a
whitening channel or CRCInit, so it is the independent full-vector oracle for
the public pattern mapper.  Complete packet encoding is checked separately by
test-local CRC, seven-cell whitening, explicit-delay FEC, and pattern mapping
implementations; no production encode round trip is used as an oracle.
"""

from std.collections import Span
from std.testing import TestSuite, assert_equal, assert_raises, assert_true
from wireless_dsp.testing import CheckpointMetadata
from wireless_dsp.wireless.bluetooth import (
    bluetooth_le_coded_pattern_map,
    bluetooth_le_coded_packet_encode,
)


def _parse_bits(value: StringSlice) raises -> List[UInt8]:
    var result = List[UInt8](capacity=value.byte_length())
    for index in range(value.byte_length()):
        var code = ord(value[byte=index])
        if code != ord("0") and code != ord("1"):
            raise Error("test vector is not a binary string")
        result.append(UInt8(code - ord("0")))
    return result^


def _append_text(mut result: List[UInt8], value: StringSlice) raises:
    var bits = _parse_bits(value)
    for index in range(len(bits)):
        result.append(bits[index])


def _append_bits(mut result: List[UInt8], bits: Span[UInt8, ...]):
    for index in range(len(bits)):
        result.append(bits[index])


def _official_s2_symbols() raises -> List[UInt8]:
    # Part C 2.3, all fields from the first Preamble symbol through TERM2.
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
    # Part C 2.4, all fields from the first Preamble symbol through TERM2.
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


def _oracle_crc24(pdu_bits: Span[UInt8, ...], crc_init: Int) -> UInt32:
    var state = UInt32(crc_init)
    for index in range(len(pdu_bits)):
        var feedback = ((state >> UInt32(23)) & UInt32(1)) ^ UInt32(
            pdu_bits[index]
        )
        state = (state << UInt32(1)) & UInt32(0xFFFFFF)
        if feedback != 0:
            state ^= UInt32(0x00065B)
    return state


def _oracle_whiten(
    bits: Span[UInt8, ...], channel_index: Int
) -> List[UInt8]:
    # Seven explicitly named Core cells, independent of production's packed
    # integer LFSR representation.
    var cells = List[UInt8](length=7, fill=UInt8(0))
    cells[0] = 1
    for position in range(1, 7):
        cells[position] = UInt8((channel_index >> (6 - position)) & 1)
    var result = List[UInt8](capacity=len(bits))
    for index in range(len(bits)):
        var old_six = cells[6]
        result.append(bits[index] ^ old_six)
        for position in range(6, 0, -1):
            cells[position] = cells[position - 1]
        cells[4] ^= old_six
        cells[0] = old_six
    return result^


def _oracle_fec(bits: Span[UInt8, ...]) -> List[UInt8]:
    # Direct delay-cell form of G0=1+x+x^2+x^3 and G1=1+x^2+x^3.
    var d1 = UInt8(0)
    var d2 = UInt8(0)
    var d3 = UInt8(0)
    var result = List[UInt8](capacity=2 * (len(bits) + 3))
    for step in range(len(bits) + 3):
        var bit = bits[step] if step < len(bits) else UInt8(0)
        result.append(bit ^ d1 ^ d2 ^ d3)
        result.append(bit ^ d2 ^ d3)
        d3 = d2
        d2 = d1
        d1 = bit
    return result^


def _oracle_map(
    bits: Span[UInt8, ...], coding_s: Int
) -> List[UInt8]:
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


def _oracle_packet(
    pdu_bits: Span[UInt8, ...],
    access_address: Int,
    crc_init: Int,
    channel_index: Int,
    coding_s: Int,
) raises -> List[UInt8]:
    var block_one = List[UInt8](capacity=34)
    for index in range(32):
        block_one.append(UInt8((access_address >> index) & 1))
    block_one.append(UInt8(1 if coding_s == 2 else 0))
    block_one.append(0)
    var block_one_fec = _oracle_fec(Span(block_one))
    var block_one_symbols = _oracle_map(Span(block_one_fec), 8)

    var crc = _oracle_crc24(pdu_bits, crc_init)
    var body = List[UInt8](capacity=len(pdu_bits) + 24)
    for index in range(len(pdu_bits)):
        body.append(pdu_bits[index])
    for index in range(24):
        body.append(UInt8((crc >> UInt32(23 - index)) & UInt32(1)))
    var whitened = _oracle_whiten(Span(body), channel_index)
    var block_two_fec = _oracle_fec(Span(whitened))
    var block_two_symbols = _oracle_map(Span(block_two_fec), coding_s)

    var result = List[UInt8](
        capacity=80 + len(block_one_symbols) + len(block_two_symbols)
    )
    for _ in range(10):
        _append_text(result, "00111100")
    _append_bits(result, Span(block_one_symbols))
    _append_bits(result, Span(block_two_symbols))
    return result^


def _next(mut state: UInt64) -> UInt64:
    state = state * UInt64(6364136223846793005) + UInt64(1442695040888963407)
    return state


def _seeded_bits(length: Int, mut state: UInt64) -> List[UInt8]:
    var result = List[UInt8](capacity=length)
    for _ in range(length):
        result.append(UInt8((_next(state) >> UInt64(63)) & UInt64(1)))
    return result^


def _assert_checkpoint_metadata(
    metadata: List[CheckpointMetadata],
    testcase_id: StringSlice,
    stages: List[String],
    lengths: List[Int],
    layouts: List[String],
) raises:
    assert_equal(len(metadata), len(stages))
    assert_equal(len(metadata), len(lengths))
    assert_equal(len(metadata), len(layouts))
    for index in range(len(metadata)):
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
        assert_equal(metadata[index].layout, layouts[index])


def _part_c_actual(
    block_one_fec: Span[UInt8, ...],
    block_two_fec: Span[UInt8, ...],
    coding_s: Int,
) raises -> List[UInt8]:
    var block_one = bluetooth_le_coded_pattern_map(block_one_fec, 8)
    var block_two = bluetooth_le_coded_pattern_map(block_two_fec, coding_s)
    var result = List[UInt8](capacity=80 + len(block_one) + len(block_two))
    for _ in range(10):
        _append_text(result, "00111100")
    _append_bits(result, Span(block_one))
    _append_bits(result, Span(block_two))
    return result^


def test_part_c_complete_s2_and_s8_symbol_vectors() raises:
    var access_ci_s2 = _parse_bits("0110101101111101100100010111000110")
    var access_ci_s8 = _parse_bits("0110101101111101100100010111000100")
    var pdu_crc = _parse_bits(
        "0000000011000000010000100011001010100010100101000101000001110011"
    )
    var block_one_s2 = _parse_bits(
        "00110101110100100111101001011011100100001011111110001010100011110101001100"
    )
    var block_one_s8 = _parse_bits(
        "00110101110100100111101001011011100100001011111110001010100011111011110000"
    )
    var block_two = _parse_bits(
        "00000000000000001101010011000000001110111100111011111101010000100001000111111110000111001000011111111000011111000011011010000001010011"
    )

    # The local delay-cell encoder independently checks every official FEC
    # output bit, including both three-zero terminators.
    assert_equal(_oracle_fec(Span(access_ci_s2)), block_one_s2)
    assert_equal(_oracle_fec(Span(access_ci_s8)), block_one_s8)
    assert_equal(_oracle_fec(Span(pdu_crc)), block_two)

    var actual_s2 = _part_c_actual(Span(block_one_s2), Span(block_two), 2)
    var expected_s2 = _official_s2_symbols()
    assert_equal(len(actual_s2), 510)
    assert_equal(actual_s2, expected_s2)

    var actual_s8 = _part_c_actual(Span(block_one_s8), Span(block_two), 8)
    var expected_s8 = _official_s8_symbols()
    assert_equal(len(actual_s8), 912)
    assert_equal(actual_s8, expected_s8)


def test_pattern_mapper_complete_table_and_exhaustive_sequences() raises:
    var table_input: List[UInt8] = [0, 1]
    var expected_s2: List[UInt8] = [0, 1]
    var expected_s8: List[UInt8] = [0, 0, 1, 1, 1, 1, 0, 0]
    assert_equal(
        bluetooth_le_coded_pattern_map(Span(table_input), 2), expected_s2
    )
    assert_equal(
        bluetooth_le_coded_pattern_map(Span(table_input), 8), expected_s8
    )

    # Exhaust every eight-bit mapper input for both rows of Part B Table 3.1.
    for word in range(256):
        var bits = List[UInt8](capacity=8)
        for index in range(8):
            bits.append(UInt8((word >> index) & 1))
        for coding_s in [2, 8]:
            assert_equal(
                bluetooth_le_coded_pattern_map(Span(bits), coding_s),
                _oracle_map(Span(bits), coding_s),
            )

    assert_equal(
        len(bluetooth_le_coded_pattern_map(Span(List[UInt8]()), 2)), 0
    )
    assert_equal(
        len(bluetooth_le_coded_pattern_map(Span(List[UInt8]()), 8)), 0
    )


def test_seeded_independent_complete_packet_differential() raises:
    var state = UInt64(0xC0DED63B5EED1234)
    for case_index in range(24):
        var octets = 2 + Int(_next(state) % UInt64(256))
        var pdu = _seeded_bits(8 * octets, state)
        var access_address = Int(_next(state) & UInt64(0xFFFFFFFF))
        var crc_init = Int(_next(state) & UInt64(0xFFFFFF))
        var channel_index = Int(_next(state) % UInt64(40))
        var coding_s = 2 if case_index % 2 == 0 else 8
        var actual = bluetooth_le_coded_packet_encode(
            Span(pdu),
            access_address,
            crc_init,
            channel_index,
            coding_s,
        )
        var expected = _oracle_packet(
            Span(pdu),
            access_address,
            crc_init,
            channel_index,
            coding_s,
        )
        assert_equal(actual.packet_symbols, expected)


def test_exact_packet_geometry_and_scalar_endpoints() raises:
    for pdu_length in [16, 2056]:
        var pdu = List[UInt8](capacity=pdu_length)
        for index in range(pdu_length):
            pdu.append(UInt8(((index * 7) ^ pdu_length) & 1))
        for endpoint in range(2):
            var access_address = 0 if endpoint == 0 else 0xFFFFFFFF
            var crc_init = 0 if endpoint == 0 else 0xFFFFFF
            var channel_index = 0 if endpoint == 0 else 39
            for coding_s in [2, 8]:
                var actual = bluetooth_le_coded_packet_encode(
                    Span(pdu),
                    access_address,
                    crc_init,
                    channel_index,
                    coding_s,
                )
                var expected_length = (
                    80 + 296 + 2 * (pdu_length + 27)
                    if coding_s == 2
                    else 80 + 296 + 8 * (pdu_length + 27)
                )
                assert_equal(len(actual.packet_symbols), expected_length)
                assert_equal(
                    actual.packet_symbols,
                    _oracle_packet(
                        Span(pdu),
                        access_address,
                        crc_init,
                        channel_index,
                        coding_s,
                    ),
                )
                # The complete owned output is deterministic on a repeated
                # fixed input, including both endpoint symbols.
                assert_equal(
                    actual.packet_symbols,
                    bluetooth_le_coded_packet_encode(
                        Span(pdu),
                        access_address,
                        crc_init,
                        channel_index,
                        coding_s,
                    ).packet_symbols,
                )


def test_owned_composite_intermediates_and_testcase_metadata() raises:
    var stages: List[String] = [
        "coded-preamble-symbols",
        "access-address-bits",
        "coding-indicator-bits",
        "term1-bits",
        "fec-block1-input-bits",
        "fec-block1-output-bits",
        "fec-block1-mapped-symbols",
        "pdu-bits",
        "crc-bits",
        "pdu-and-crc-bits",
        "whitened-pdu-and-crc-bits",
        "term2-bits",
        "fec-block2-input-bits",
        "fec-block2-output-bits",
        "fec-block2-mapped-symbols",
        "coded-packet-symbols",
    ]
    var layouts = List[String](length=16, fill=String("bit-per-byte"))
    for index in [0, 6, 14, 15]:
        layouts[index] = "symbol-per-byte"

    for coding_s in [2, 8]:
        var pdu = _parse_bits("0110100010100000")
        var original_pdu = pdu.copy()
        var testcase = String("bluetooth-coded-owned-s")
        testcase.write(coding_s)
        var expected_testcase = String("bluetooth-coded-owned-s")
        expected_testcase.write(coding_s)
        var transmit = bluetooth_le_coded_packet_encode(
            Span(pdu),
            0xAA08192B,
            0xC4C181,
            16,
            coding_s,
            testcase_id=testcase,
        )
        testcase.write("-caller-mutated")
        var mapped_block_two_length = 86 if coding_s == 2 else 344
        var packet_length = 80 + 296 + mapped_block_two_length
        var lengths: List[Int] = [
            80,
            32,
            2,
            3,
            37,
            74,
            296,
            16,
            24,
            40,
            40,
            3,
            43,
            86,
            mapped_block_two_length,
            packet_length,
        ]
        _assert_checkpoint_metadata(
            transmit.checkpoint_metadata,
            expected_testcase,
            stages,
            lengths,
            layouts,
        )
        assert_equal(transmit.pdu_bits, original_pdu)
        assert_equal(transmit.coding_s, coding_s)
        var expected_ci: List[UInt8] = [
            UInt8(1 if coding_s == 2 else 0), UInt8(0)
        ]
        var expected_term: List[UInt8] = [0, 0, 0]
        assert_equal(
            transmit.coding_indicator_bits, expected_ci
        )
        assert_equal(transmit.term1_bits, expected_term)
        assert_equal(transmit.term2_bits, expected_term)
        var block_one_payload = transmit.access_address_bits.copy()
        _append_bits(block_one_payload, Span(transmit.coding_indicator_bits))
        var expected_block_one = transmit.access_address_bits.copy()
        _append_bits(expected_block_one, Span(transmit.coding_indicator_bits))
        _append_bits(expected_block_one, Span(transmit.term1_bits))
        assert_equal(transmit.block_one_input_bits, expected_block_one)
        assert_equal(
            transmit.block_one_fec_bits,
            _oracle_fec(Span(block_one_payload)),
        )
        assert_equal(
            transmit.block_one_mapped_symbols,
            _oracle_map(Span(transmit.block_one_fec_bits), 8),
        )
        assert_equal(
            transmit.crc, _oracle_crc24(Span(original_pdu), 0xC4C181)
        )
        for index in range(len(original_pdu)):
            assert_equal(
                transmit.pdu_and_crc_bits[index], original_pdu[index]
            )
        for index in range(24):
            assert_equal(
                transmit.pdu_and_crc_bits[len(original_pdu) + index],
                transmit.crc_bits[index],
            )
        assert_equal(
            transmit.whitened_pdu_and_crc_bits,
            _oracle_whiten(Span(transmit.pdu_and_crc_bits), 16),
        )
        var expected_block_two = transmit.whitened_pdu_and_crc_bits.copy()
        _append_bits(expected_block_two, Span(transmit.term2_bits))
        assert_equal(transmit.block_two_input_bits, expected_block_two)
        assert_equal(
            transmit.block_two_fec_bits,
            _oracle_fec(Span(transmit.whitened_pdu_and_crc_bits)),
        )
        assert_equal(
            transmit.block_two_mapped_symbols,
            _oracle_map(Span(transmit.block_two_fec_bits), coding_s),
        )
        assert_equal(
            transmit.packet_symbols,
            _oracle_packet(
                Span(original_pdu),
                0xAA08192B,
                0xC4C181,
                16,
                coding_s,
            ),
        )
        var first_pdu_bit = transmit.pdu_bits[0]
        pdu[0] ^= 1
        assert_equal(transmit.pdu_bits[0], first_pdu_bit)

    var valid_pdu = List[UInt8](length=16, fill=UInt8(0))
    for invalid_testcase in ["", "bad\nidentifier", "bad\ridentifier"]:
        with assert_raises():
            _ = bluetooth_le_coded_packet_encode(
                Span(valid_pdu),
                0,
                0,
                0,
                2,
                testcase_id=invalid_testcase,
            )


def test_structural_reserved_and_integer_domains() raises:
    var valid_pdu = List[UInt8](length=16, fill=UInt8(0))
    var invalid_pdus = [
        List[UInt8](),
        List[UInt8](length=8, fill=UInt8(0)),
        List[UInt8](length=15, fill=UInt8(0)),
        List[UInt8](length=17, fill=UInt8(0)),
        List[UInt8](length=2057, fill=UInt8(0)),
        List[UInt8](length=2064, fill=UInt8(0)),
    ]
    for invalid in invalid_pdus:
        with assert_raises():
            _ = bluetooth_le_coded_packet_encode(
                Span(invalid), 0, 0, 0, 2
            )

    for invalid_coding in [0, 1, 3, 7, 9, Int.MIN, Int.MAX]:
        with assert_raises():
            _ = bluetooth_le_coded_pattern_map(
                Span(List[UInt8]()), invalid_coding
            )
        with assert_raises():
            _ = bluetooth_le_coded_packet_encode(
                Span(valid_pdu), 0, 0, 0, invalid_coding
            )
    for invalid_access_address in [-1, 0x100000000, Int.MIN, Int.MAX]:
        with assert_raises():
            _ = bluetooth_le_coded_packet_encode(
                Span(valid_pdu), invalid_access_address, 0, 0, 2
            )
    for invalid_crc_init in [-1, 0x1000000, Int.MIN, Int.MAX]:
        with assert_raises():
            _ = bluetooth_le_coded_packet_encode(
                Span(valid_pdu), 0, invalid_crc_init, 0, 2
            )
    for invalid_channel in [-1, 40, Int.MIN, Int.MAX]:
        with assert_raises():
            _ = bluetooth_le_coded_packet_encode(
                Span(valid_pdu), 0, 0, invalid_channel, 2
            )

    for nonbinary in [UInt8(2), UInt8(255)]:
        var bad_mapper: List[UInt8] = [0, nonbinary, 1]
        with assert_raises():
            _ = bluetooth_le_coded_pattern_map(Span(bad_mapper), 8)
        var bad_pdu = valid_pdu.copy()
        bad_pdu[len(bad_pdu) - 1] = nonbinary
        with assert_raises():
            _ = bluetooth_le_coded_packet_encode(
                Span(bad_pdu), 0, 0, 0, 8
            )


def test_mutable_inputs_are_revalidated_on_every_public_call() raises:
    var mapper_bits: List[UInt8] = [0, 1, 0, 1]
    _ = bluetooth_le_coded_pattern_map(Span(mapper_bits), 8)
    mapper_bits[0] = 2
    with assert_raises():
        _ = bluetooth_le_coded_pattern_map(Span(mapper_bits), 8)

    var pdu = List[UInt8](length=16, fill=UInt8(1))
    _ = bluetooth_le_coded_packet_encode(
        Span(pdu), 0xFFFFFFFF, 0xFFFFFF, 39, 8
    )
    pdu[0] = 2
    with assert_raises():
        _ = bluetooth_le_coded_packet_encode(
            Span(pdu), 0xFFFFFFFF, 0xFFFFFF, 39, 8
        )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
