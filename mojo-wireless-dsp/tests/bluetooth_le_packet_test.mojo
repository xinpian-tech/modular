"""Independent evidence for the Bluetooth Core 6.3 LE packet-bit slice.

Static complete-packet and all-channel whitening vectors are transcribed from
Vol 6, Part C, Sections 4.1, 4.2.1, 4.2.2, and 4.3.1 of the official Core 6.3
PDF (SHA-256 e210fb8f697fca2b970001d35f8c9c7c8f836190550b7fd29d2915a1c8596d60).
The published Section 4.2.2 ChSel/CRC inconsistency is retained as an explicit
negative decode regression; Sections 4.2.1 and 4.3.1 are positive vectors.
Seeded differential checks use test-local CRC and whitening LFSRs; no
production encode/decode round trip serves as the oracle.
"""

from std.collections import Span
from std.testing import TestSuite, assert_equal, assert_raises, assert_true
from wireless_dsp.testing import CheckpointMetadata
from wireless_dsp.wireless.bluetooth import (
    BLUETOOTH_LE_PHY_1M,
    BLUETOOTH_LE_PHY_2M,
    bluetooth_le_crc24,
    bluetooth_le_whiten_bits,
    bluetooth_le_uncoded_packet_encode,
    bluetooth_le_uncoded_packet_decode,
)


def _parse_bits(value: StringSlice) raises -> List[UInt8]:
    var result = List[UInt8](capacity=value.byte_length())
    for index in range(value.byte_length()):
        var code = ord(value[byte=index])
        if code != ord("0") and code != ord("1"):
            raise Error("test vector is not a binary string")
        result.append(UInt8(code - ord("0")))
    return result^


def _oracle_crc24(pdu_bits: Span[UInt8, ...], crc_init: Int) -> UInt32:
    # Standalone direct polynomial recurrence.  This test oracle does not call
    # the package CRC primitive used by production.
    var state = UInt32(crc_init)
    for index in range(len(pdu_bits)):
        var feedback = ((state >> UInt32(23)) & UInt32(1)) ^ UInt32(
            pdu_bits[index]
        )
        state = (state << UInt32(1)) & UInt32(0xFFFFFF)
        if feedback != 0:
            state ^= UInt32(0x00065B)
    return state


def _oracle_whiten(bits: Span[UInt8, ...], channel_index: Int) -> List[UInt8]:
    # Independent scalar seven-cell recurrence for x^7+x^4+1.
    var cells = List[UInt8](length=7, fill=UInt8(0))
    cells[0] = 1
    for position in range(1, 7):
        cells[position] = UInt8((channel_index >> (6 - position)) & 1)
    var result = List[UInt8](capacity=len(bits))
    for index in range(len(bits)):
        # Position 6 is the transmitted whitening bit.  Advance the seven
        # explicitly named Core positions without sharing production's packed
        # integer representation.
        var old_six = cells[6]
        result.append(bits[index] ^ old_six)
        for position in range(6, 0, -1):
            cells[position] = cells[position - 1]
        cells[4] ^= old_six
        cells[0] = old_six
    return result^


def _oracle_packet(
    pdu_bits: Span[UInt8, ...],
    access_address: Int,
    crc_init: Int,
    channel_index: Int,
    phy: Int,
) -> List[UInt8]:
    var preamble_length = 8 if phy == BLUETOOTH_LE_PHY_1M else 16
    var crc = _oracle_crc24(pdu_bits, crc_init)
    var body = List[UInt8](capacity=len(pdu_bits) + 24)
    for index in range(len(pdu_bits)):
        body.append(pdu_bits[index])
    for index in range(24):
        body.append(UInt8((UInt32(crc) >> UInt32(23 - index)) & UInt32(1)))
    var whitened = _oracle_whiten(Span(body), channel_index)
    var result = List[UInt8](capacity=preamble_length + 32 + len(whitened))
    var first = UInt8(access_address & 1)
    for index in range(preamble_length):
        result.append(first ^ UInt8(index & 1))
    for index in range(32):
        result.append(UInt8((access_address >> index) & 1))
    for index in range(len(whitened)):
        result.append(whitened[index])
    return result^


def _next(mut state: UInt64) -> UInt64:
    state = state * UInt64(6364136223846793005) + UInt64(1442695040888963407)
    return state


def _seeded_bits(length: Int, mut state: UInt64) -> List[UInt8]:
    var result = List[UInt8](capacity=length)
    for _ in range(length):
        result.append(UInt8((_next(state) >> UInt64(63)) & UInt64(1)))
    return result^


def _prefix(bits: Span[UInt8, ...], length: Int) -> List[UInt8]:
    var result = List[UInt8](capacity=length)
    for index in range(length):
        result.append(bits[index])
    return result^


def _assert_checkpoint_metadata(
    metadata: List[CheckpointMetadata],
    testcase_id: StringSlice,
    stages: List[String],
    lengths: List[Int],
) raises:
    assert_equal(len(metadata), len(stages))
    assert_equal(len(metadata), len(lengths))
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
        assert_equal(metadata[index].layout, "bit-per-byte")


def _assert_static_packet(
    pdu_text: StringSlice,
    crc_text: StringSlice,
    complete_text: StringSlice,
    access_address: Int,
    crc_init: Int,
    channel_index: Int,
) raises:
    var pdu = _parse_bits(pdu_text)
    var expected_crc_bits = _parse_bits(crc_text)
    var expected_crc = UInt32(0)
    for index in range(24):
        expected_crc = (expected_crc << UInt32(1)) | UInt32(
            expected_crc_bits[index]
        )
    assert_equal(bluetooth_le_crc24(Span(pdu), crc_init), expected_crc)

    var expected_packet = _parse_bits(complete_text)
    var encoded = bluetooth_le_uncoded_packet_encode(
        Span(pdu),
        access_address,
        crc_init,
        channel_index,
        BLUETOOTH_LE_PHY_1M,
    )
    assert_equal(encoded.packet_bits, expected_packet)
    var decoded = bluetooth_le_uncoded_packet_decode(
        Span(expected_packet),
        access_address,
        crc_init,
        channel_index,
        BLUETOOTH_LE_PHY_1M,
    )
    assert_equal(decoded.pdu_bits, pdu)
    assert_equal(decoded.received_access_address, UInt32(access_address))
    assert_equal(decoded.received_crc, expected_crc)
    assert_equal(decoded.expected_crc, expected_crc)
    assert_true(decoded.preamble_ok)
    assert_true(decoded.access_address_ok)
    assert_true(decoded.crc_ok)
    assert_true(decoded.valid)


def test_part_c_static_complete_packet_vectors() raises:
    # Part C 4.2.1, ADV_NONCONN_IND.
    _assert_static_packet(
        "0100001010010000011001011010010100100101110001010100010110000011100000000100000011000000",
        "101101010010110111010111",
        "01010101011010110111110110010001011100010010100100110011010001111010000110111111101111101100001001110010010110001110010100110101111101111111001110100101",
        0x8E89BED6,
        0x555555,
        38,
    )

    # Part C 4.3.1, unencrypted LL data PDU.
    _assert_static_packet(
        "01101000101000001000000001000000110000000010000010100000",
        "101000100000101101001011",
        "101010101101010010011000000100000101010101100011110110010100101010001100110110110111110110111001101100100010111110011000",
        0xAA08192B,
        0xC4C181,
        16,
    )


def test_part_c_4_2_2_published_extended_crc_internal_conflict() raises:
    # Part C 4.2.2, connectable undirected AUX_ADV_IND.  Core 6.3 has a
    # localized internal conflict in this published vector: the stated PDU
    # and de-whitened complete packet carry ChSel=0, while CRC 0x1BC475 is the
    # result for ChSel=1.  Part B 3.1.1 applied to the printed ChSel=0 PDU is
    # 0x65D123, independently confirmed below.  Preserve both official
    # literals and require the decoder to report (not raise) that CRC defect.
    var extended_pdu = _parse_bits(
        "111000000000100001010010100100100111010110110101001101011101010101010101100101010011110101010111011010111010000011100000100100001101000010110000"
    )
    assert_equal(_oracle_crc24(Span(extended_pdu), 0x555555), 0x65D123)
    assert_equal(bluetooth_le_crc24(Span(extended_pdu), 0x555555), 0x65D123)
    var chsel_one = extended_pdu.copy()
    chsel_one[5] = 1
    assert_equal(_oracle_crc24(Span(chsel_one), 0x555555), 0x1BC475)
    var published_extended_packet = _parse_bits(
        "0101010101101011011111011001000101110001000111000111111001111011111011110010010100000010101010010111100110010100001000001110110011000110011010011110110111011101010100110010100001011100010010010011111011010100"
    )
    var published_extended = bluetooth_le_uncoded_packet_decode(
        Span(published_extended_packet),
        0x8E89BED6,
        0x555555,
        7,
        BLUETOOTH_LE_PHY_1M,
    )
    assert_equal(published_extended.pdu_bits, extended_pdu)
    assert_equal(published_extended.received_crc, 0x1BC475)
    assert_equal(published_extended.expected_crc, 0x65D123)
    assert_true(published_extended.preamble_ok)
    assert_true(published_extended.access_address_ok)
    assert_true(not published_extended.crc_ok)
    assert_true(not published_extended.valid)
    var normative_extended = bluetooth_le_uncoded_packet_encode(
        Span(extended_pdu),
        0x8E89BED6,
        0x555555,
        7,
        BLUETOOTH_LE_PHY_1M,
    )
    assert_equal(
        normative_extended.packet_bits,
        _oracle_packet(
            Span(extended_pdu),
            0x8E89BED6,
            0x555555,
            7,
            BLUETOOTH_LE_PHY_1M,
        ),
    )
    assert_true(normative_extended.packet_bits != published_extended_packet)


def test_part_c_all_40_whitening_sequences_first_64_bits() raises:
    var expected: List[String] = [
        "0000001001001101001111011100001111111000111011000101001011111010",
        "1001000100000010010011010011110111000011111110001110110001010010",
        "0100101111101010100001011011110011100101011001100000110110101110",
        "1101100010100101111101010100001011011110011100101011001100000110",
        "0010011010011110111000011111110001110110001010010111110101010000",
        "1011010111010001100100010000001001001101001111011100001111111000",
        "0110111100111001010110011000001101101011101000110010001000000100",
        "1111110001110110001010010111110101010000101101111001110010101100",
        "0001000000100100110100111101110000111111100011101100010100101111",
        "1000001101101011101000110010001000000100100110100111101110000111",
        "0101100110000011011010111010001100100010000001001001101001111011",
        "1100101011001100000110110101110100011001000100000010010011010011",
        "0011010011110111000011111110001110110001010010111110101010000101",
        "1010011110111000011111110001110110001010010111110101010000101101",
        "0111110101010000101101111001110010101100110000011011010111010001",
        "1110111000011111110001110110001010010111110101010000101101111001",
        "0000101101111001110010101100110000011011010111010001100100010000",
        "1001100000110110101110100011001000100000010010011010011110111000",
        "0100001011011110011100101011001100000110110101110100011001000100",
        "1101000110010001000000100100110100111101110000111111100011101100",
        "0010111110101010000101101111001110010101100110000011011010111010",
        "1011110011100101011001100000110110101110100011001000100000010010",
        "0110011000001101101011101000110010001000000100100110100111101110",
        "1111010101000010110111100111001010110011000001101101011101000110",
        "0001100100010000001001001101001111011100001111111000111011000101",
        "1000101001011111010101000010110111100111001010110011000001101101",
        "0101000010110111100111001010110011000001101101011101000110010001",
        "1100001111111000111011000101001011111010101000010110111100111001",
        "0011110111000011111110001110110001010010111110101010000101101111",
        "1010111010001100100010000001001001101001111011100001111111000111",
        "0111010001100100010000001001001101001111011100001111111000111011",
        "1110011100101011001100000110110101110100011001000100000010010011",
        "0000011011010111010001100100010000001001001101001111011100001111",
        "1001010110011000001101101011101000110010001000000100100110100111",
        "0100111101110000111111100011101100010100101111101010100001011011",
        "1101110000111111100011101100010100101111101010100001011011110011",
        "0010001000000100100110100111101110000111111100011101100010100101",
        "1011000101001011111010101000010110111100111001010110011000001101",
        "0110101110100011001000100000010010011010011110111000011111110001",
        "1111100011101100010100101111101010100001011011110011100101011001",
    ]
    assert_equal(len(expected), 40)
    var zeros = List[UInt8](length=64, fill=UInt8(0))
    for channel_index in range(40):
        var literal = _parse_bits(expected[channel_index])
        var actual = bluetooth_le_whiten_bits(Span(zeros), channel_index)
        assert_equal(actual, literal)
        assert_equal(
            bluetooth_le_whiten_bits(Span(literal), channel_index), zeros
        )


def test_seeded_independent_crc_whitening_and_packet_differential() raises:
    var state = UInt64(0x63B10E5EEDC0FFEE)
    for case_index in range(32):
        var octets = 2 + Int(_next(state) % UInt64(257))
        var pdu = _seeded_bits(8 * octets, state)
        var access_address = Int(_next(state) & UInt64(0xFFFFFFFF))
        var crc_init = Int(_next(state) & UInt64(0xFFFFFF))
        var channel_index = Int(_next(state) % UInt64(40))
        var phy = (
            BLUETOOTH_LE_PHY_1M if case_index % 2 == 0 else BLUETOOTH_LE_PHY_2M
        )
        assert_equal(
            bluetooth_le_crc24(Span(pdu), crc_init),
            _oracle_crc24(Span(pdu), crc_init),
        )

        var crc = _oracle_crc24(Span(pdu), crc_init)
        var body = pdu.copy()
        for index in range(24):
            body.append(UInt8((crc >> UInt32(23 - index)) & UInt32(1)))
        assert_equal(
            bluetooth_le_whiten_bits(Span(body), channel_index),
            _oracle_whiten(Span(body), channel_index),
        )

        var expected_packet = _oracle_packet(
            Span(pdu), access_address, crc_init, channel_index, phy
        )
        var actual_packet = bluetooth_le_uncoded_packet_encode(
            Span(pdu), access_address, crc_init, channel_index, phy
        )
        assert_equal(actual_packet.packet_bits, expected_packet)
        var decoded = bluetooth_le_uncoded_packet_decode(
            Span(expected_packet),
            access_address,
            crc_init,
            channel_index,
            phy,
        )
        assert_equal(decoded.pdu_bits, pdu)
        assert_true(decoded.valid)


def test_exact_pdu_phy_and_scalar_endpoints() raises:
    var lengths: List[Int] = [16, 2064]
    var access_addresses: List[Int] = [0, 0xFFFFFFFF]
    var crc_inits: List[Int] = [0, 0xFFFFFF]
    var channels: List[Int] = [0, 39]
    var phys: List[Int] = [BLUETOOTH_LE_PHY_1M, BLUETOOTH_LE_PHY_2M]
    for length in lengths:
        var pdu = List[UInt8](capacity=length)
        for index in range(length):
            pdu.append(UInt8((index + length // 8) & 1))
        for endpoint in range(2):
            for phy in phys:
                var encoded = bluetooth_le_uncoded_packet_encode(
                    Span(pdu),
                    access_addresses[endpoint],
                    crc_inits[endpoint],
                    channels[endpoint],
                    phy,
                )
                var preamble_length = 8 if phy == BLUETOOTH_LE_PHY_1M else 16
                assert_equal(
                    len(encoded.packet_bits),
                    preamble_length + 32 + length + 24,
                )
                assert_equal(
                    encoded.packet_bits[0],
                    UInt8(access_addresses[endpoint] & 1),
                )
                var decoded = bluetooth_le_uncoded_packet_decode(
                    Span(encoded.packet_bits),
                    access_addresses[endpoint],
                    crc_inits[endpoint],
                    channels[endpoint],
                    phy,
                )
                assert_equal(decoded.pdu_bits, pdu)
                assert_true(decoded.valid)

    var empty = bluetooth_le_whiten_bits(Span(List[UInt8]()), 0)
    assert_equal(len(empty), 0)
    var maximum = List[UInt8](length=2088, fill=UInt8(1))
    assert_equal(len(bluetooth_le_whiten_bits(Span(maximum), 39)), 2088)


def test_decode_bit_flip_verdicts_without_structural_exceptions() raises:
    var pdu = _parse_bits(
        "01101000101000001000000001000000110000000010000010100000"
    )
    var encoded = bluetooth_le_uncoded_packet_encode(
        Span(pdu), 0xAA08192B, 0xC4C181, 16, BLUETOOTH_LE_PHY_1M
    )
    var packet = encoded.packet_bits.copy()

    var bad_preamble = packet.copy()
    bad_preamble[0] ^= 1
    var preamble_result = bluetooth_le_uncoded_packet_decode(
        Span(bad_preamble),
        0xAA08192B,
        0xC4C181,
        16,
        BLUETOOTH_LE_PHY_1M,
    )
    assert_true(not preamble_result.preamble_ok)
    assert_true(preamble_result.access_address_ok)
    assert_true(preamble_result.crc_ok)
    assert_true(not preamble_result.valid)

    var bad_access_address = packet.copy()
    bad_access_address[8] ^= 1
    var access_result = bluetooth_le_uncoded_packet_decode(
        Span(bad_access_address),
        0xAA08192B,
        0xC4C181,
        16,
        BLUETOOTH_LE_PHY_1M,
    )
    assert_true(access_result.preamble_ok)
    assert_true(not access_result.access_address_ok)
    assert_true(access_result.crc_ok)
    assert_true(not access_result.valid)

    var bad_pdu = packet.copy()
    bad_pdu[8 + 32] ^= 1
    var pdu_result = bluetooth_le_uncoded_packet_decode(
        Span(bad_pdu),
        0xAA08192B,
        0xC4C181,
        16,
        BLUETOOTH_LE_PHY_1M,
    )
    assert_true(pdu_result.preamble_ok)
    assert_true(pdu_result.access_address_ok)
    assert_true(not pdu_result.crc_ok)
    assert_true(not pdu_result.valid)

    var bad_crc = packet.copy()
    bad_crc[len(bad_crc) - 1] ^= 1
    var crc_result = bluetooth_le_uncoded_packet_decode(
        Span(bad_crc),
        0xAA08192B,
        0xC4C181,
        16,
        BLUETOOTH_LE_PHY_1M,
    )
    assert_true(crc_result.preamble_ok)
    assert_true(crc_result.access_address_ok)
    assert_true(not crc_result.crc_ok)
    assert_true(not crc_result.valid)

    var wrong_expected = bluetooth_le_uncoded_packet_decode(
        Span(packet),
        0xAA081929,
        0xC4C181,
        16,
        BLUETOOTH_LE_PHY_1M,
    )
    assert_true(wrong_expected.preamble_ok)
    assert_true(not wrong_expected.access_address_ok)
    assert_true(wrong_expected.crc_ok)


def test_owned_composite_checkpoints_and_testcase_metadata() raises:
    var pdu = _parse_bits("0110100010100000")
    var tx_testcase = String("bluetooth-uncoded-owned-tx")
    var transmit = bluetooth_le_uncoded_packet_encode(
        Span(pdu),
        0xAA08192B,
        0xC4C181,
        16,
        BLUETOOTH_LE_PHY_1M,
        testcase_id=tx_testcase,
    )
    tx_testcase.write("-caller-mutated")
    var tx_stages: List[String] = [
        "uncoded-preamble-bits",
        "access-address-bits",
        "pdu-bits",
        "crc-bits",
        "pdu-and-crc-bits",
        "whitened-body-bits",
        "packet-bits",
    ]
    var tx_lengths: List[Int] = [8, 32, 16, 24, 40, 40, 80]
    _assert_checkpoint_metadata(
        transmit.checkpoint_metadata,
        "bluetooth-uncoded-owned-tx",
        tx_stages,
        tx_lengths,
    )
    assert_equal(transmit.pdu_bits, pdu)
    assert_equal(len(transmit.preamble_bits), 8)
    assert_equal(len(transmit.access_address_bits), 32)
    assert_equal(len(transmit.crc_bits), 24)
    assert_equal(transmit.crc, _oracle_crc24(Span(pdu), 0xC4C181))
    for index in range(len(pdu)):
        assert_equal(transmit.pdu_and_crc_bits[index], pdu[index])
    for index in range(24):
        assert_equal(
            transmit.pdu_and_crc_bits[len(pdu) + index],
            transmit.crc_bits[index],
        )
    assert_equal(
        transmit.whitened_body_bits,
        _oracle_whiten(Span(transmit.pdu_and_crc_bits), 16),
    )

    # The transmit result owns the caller PDU, and the receive result owns the
    # complete packet even when both caller buffers are mutated afterwards.
    var first_pdu_bit = transmit.pdu_bits[0]
    pdu[0] ^= 1
    assert_equal(transmit.pdu_bits[0], first_pdu_bit)
    var packet_input = transmit.packet_bits.copy()
    var rx_testcase = String("bluetooth-uncoded-owned-rx")
    var receive = bluetooth_le_uncoded_packet_decode(
        Span(packet_input),
        0xAA08192B,
        0xC4C181,
        16,
        BLUETOOTH_LE_PHY_1M,
        testcase_id=rx_testcase,
    )
    rx_testcase.write("-caller-mutated")
    var first_packet_bit = receive.packet_bits[0]
    packet_input[0] ^= 1
    assert_equal(receive.packet_bits[0], first_packet_bit)
    assert_equal(receive.preamble_bits, transmit.preamble_bits)
    assert_equal(receive.access_address_bits, transmit.access_address_bits)
    assert_equal(
        receive.whitened_body_bits, transmit.whitened_body_bits
    )
    assert_equal(receive.pdu_and_crc_bits, transmit.pdu_and_crc_bits)
    assert_equal(receive.received_crc_bits, transmit.crc_bits)
    assert_equal(receive.expected_crc_bits, transmit.crc_bits)
    assert_true(receive.valid)
    var rx_stages: List[String] = [
        "received-packet-bits",
        "received-preamble-bits",
        "received-access-address-bits",
        "received-whitened-body-bits",
        "dewhitened-pdu-and-crc-bits",
        "decoded-pdu-bits",
        "received-crc-bits",
        "expected-crc-bits",
    ]
    var rx_lengths: List[Int] = [80, 8, 32, 40, 40, 16, 24, 24]
    _assert_checkpoint_metadata(
        receive.checkpoint_metadata,
        "bluetooth-uncoded-owned-rx",
        rx_stages,
        rx_lengths,
    )

    var valid_pdu = List[UInt8](length=16, fill=UInt8(0))
    for invalid_testcase in ["", "bad\nidentifier", "bad\ridentifier"]:
        with assert_raises():
            _ = bluetooth_le_uncoded_packet_encode(
                Span(valid_pdu),
                0,
                0,
                0,
                BLUETOOTH_LE_PHY_1M,
                testcase_id=invalid_testcase,
            )
        with assert_raises():
            _ = bluetooth_le_uncoded_packet_decode(
                Span(transmit.packet_bits),
                0xAA08192B,
                0xC4C181,
                16,
                BLUETOOTH_LE_PHY_1M,
                testcase_id=invalid_testcase,
            )


def test_structural_domains_reserved_values_and_integer_extrema() raises:
    var valid_pdu = List[UInt8](length=16, fill=UInt8(0))
    var one_octet_pdu = List[UInt8](length=8, fill=UInt8(0))
    var short_pdu = List[UInt8](length=15, fill=UInt8(0))
    var fractional_pdu = List[UInt8](length=17, fill=UInt8(0))
    var long_pdu = List[UInt8](length=2065, fill=UInt8(0))
    var two_hundred_fifty_nine_octet_pdu = List[UInt8](
        length=2072, fill=UInt8(0)
    )
    var invalid_pdus = [
        one_octet_pdu.copy(),
        short_pdu.copy(),
        fractional_pdu.copy(),
        long_pdu.copy(),
        two_hundred_fifty_nine_octet_pdu.copy(),
    ]
    for invalid in invalid_pdus:
        with assert_raises():
            _ = bluetooth_le_crc24(Span(invalid), 0)
        with assert_raises():
            _ = bluetooth_le_uncoded_packet_encode(
                Span(invalid), 0, 0, 0, BLUETOOTH_LE_PHY_1M
            )

    var nonbinary_pdu = valid_pdu.copy()
    nonbinary_pdu[15] = 2
    with assert_raises():
        _ = bluetooth_le_crc24(Span(nonbinary_pdu), 0)
    with assert_raises():
        _ = bluetooth_le_whiten_bits(Span(nonbinary_pdu), 0)
    with assert_raises():
        _ = bluetooth_le_uncoded_packet_encode(
            Span(nonbinary_pdu), 0, 0, 0, BLUETOOTH_LE_PHY_1M
        )

    for invalid_channel in [-1, 40, Int.MIN, Int.MAX]:
        with assert_raises():
            _ = bluetooth_le_whiten_bits(Span(List[UInt8]()), invalid_channel)
        with assert_raises():
            _ = bluetooth_le_uncoded_packet_encode(
                Span(valid_pdu), 0, 0, invalid_channel, BLUETOOTH_LE_PHY_1M
            )
    for invalid_crc_init in [-1, 0x1000000, Int.MIN, Int.MAX]:
        with assert_raises():
            _ = bluetooth_le_crc24(Span(valid_pdu), invalid_crc_init)
        with assert_raises():
            _ = bluetooth_le_uncoded_packet_encode(
                Span(valid_pdu), 0, invalid_crc_init, 0, BLUETOOTH_LE_PHY_1M
            )
    for invalid_access_address in [-1, 0x100000000, Int.MIN, Int.MAX]:
        with assert_raises():
            _ = bluetooth_le_uncoded_packet_encode(
                Span(valid_pdu),
                invalid_access_address,
                0,
                0,
                BLUETOOTH_LE_PHY_1M,
            )
    for invalid_phy in [0, 3, Int.MIN, Int.MAX]:
        with assert_raises():
            _ = bluetooth_le_uncoded_packet_encode(
                Span(valid_pdu), 0, 0, 0, invalid_phy
            )

    var maximum_whitening = List[UInt8](length=2089, fill=UInt8(0))
    with assert_raises():
        _ = bluetooth_le_whiten_bits(Span(maximum_whitening), 0)

    var encoded = bluetooth_le_uncoded_packet_encode(
        Span(valid_pdu), 0, 0, 0, BLUETOOTH_LE_PHY_1M
    )
    var packet = encoded.packet_bits.copy()
    var missing = _prefix(Span(packet), len(packet) - 1)
    var extra = packet.copy()
    extra.append(0)
    var invalid_packets = [missing.copy(), extra.copy()]
    for invalid_packet in invalid_packets:
        with assert_raises():
            _ = bluetooth_le_uncoded_packet_decode(
                Span(invalid_packet), 0, 0, 0, BLUETOOTH_LE_PHY_1M
            )
    # These are exact octet-shaped packets just outside the 2..258-octet PDU
    # domain.  They isolate the lower/upper bounds from the byte-alignment
    # checks above, so widening either endpoint cannot pass for another reason.
    var one_octet_packet = List[UInt8](length=8 + 32 + 8 + 24, fill=UInt8(0))
    var two_hundred_fifty_nine_octet_packet = List[UInt8](
        length=8 + 32 + 2072 + 24, fill=UInt8(0)
    )
    with assert_raises():
        _ = bluetooth_le_uncoded_packet_decode(
            Span(one_octet_packet), 0, 0, 0, BLUETOOTH_LE_PHY_1M
        )
    with assert_raises():
        _ = bluetooth_le_uncoded_packet_decode(
            Span(two_hundred_fifty_nine_octet_packet),
            0,
            0,
            0,
            BLUETOOTH_LE_PHY_1M,
        )
    var nonbinary_packet = packet.copy()
    nonbinary_packet[len(nonbinary_packet) - 1] = 2
    with assert_raises():
        _ = bluetooth_le_uncoded_packet_decode(
            Span(nonbinary_packet), 0, 0, 0, BLUETOOTH_LE_PHY_1M
        )
    with assert_raises():
        _ = bluetooth_le_uncoded_packet_decode(
            Span(packet), -1, 0, 0, BLUETOOTH_LE_PHY_1M
        )
    with assert_raises():
        _ = bluetooth_le_uncoded_packet_decode(
            Span(packet), 0, Int.MAX, 0, BLUETOOTH_LE_PHY_1M
        )
    with assert_raises():
        _ = bluetooth_le_uncoded_packet_decode(
            Span(packet), 0, 0, Int.MIN, BLUETOOTH_LE_PHY_1M
        )
    with assert_raises():
        _ = bluetooth_le_uncoded_packet_decode(Span(packet), 0, 0, 0, Int.MAX)


def test_mutable_input_is_revalidated_on_every_public_call() raises:
    var pdu = List[UInt8](length=16, fill=UInt8(1))
    var encoded = bluetooth_le_uncoded_packet_encode(
        Span(pdu), 0xFFFFFFFF, 0xFFFFFF, 39, BLUETOOTH_LE_PHY_2M
    )
    var packet = encoded.packet_bits.copy()
    pdu[0] = 2
    with assert_raises():
        _ = bluetooth_le_crc24(Span(pdu), 0xFFFFFF)
    with assert_raises():
        _ = bluetooth_le_whiten_bits(Span(pdu), 39)
    with assert_raises():
        _ = bluetooth_le_uncoded_packet_encode(
            Span(pdu), 0xFFFFFFFF, 0xFFFFFF, 39, BLUETOOTH_LE_PHY_2M
        )

    packet[0] = 2
    with assert_raises():
        _ = bluetooth_le_uncoded_packet_decode(
            Span(packet),
            0xFFFFFFFF,
            0xFFFFFF,
            39,
            BLUETOOTH_LE_PHY_2M,
        )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
