"""Independent evidence for Bluetooth Core 6.3 BR/EDR header HEC.

The normative literals come from the Adopted Core 6.3 PDF, Vol 2, Part G,
Section 4.  Bit geometry and the test-local eight-cell recurrence are
transcribed independently from Vol 2, Part B, Sections 1.2.1, 6.4.6,
6.5.1.1, and 7.1.1.  The official artifact SHA-256 is
e210fb8f697fca2b970001d35f8c9c7c8f836190550b7fd29d2915a1c8596d60.

The oracle below does not call the production wrapper or the generic CRC
primitive reused by production.
"""

from std.collections import Span
from std.testing import TestSuite, assert_equal, assert_raises, assert_true
from wireless_dsp.wireless.bluetooth import (
    bluetooth_br_edr_hec_generate,
    bluetooth_br_edr_hec_check,
)


def _bits_from_word(word: Int, width: Int) -> List[UInt8]:
    var result = List[UInt8](capacity=width)
    for index in range(width):
        result.append(UInt8((word >> index) & 1))
    return result^


def _hec_remainder_eight_cell_oracle(
    bits_in_transmission_order: Span[UInt8, ...], uap_or_dci: Int
) -> Int:
    # Cell numbering and update direction follow Figures 7.3 and 7.4
    # directly.  This representation is deliberately independent of the
    # reflected integer CRC representation used by production.
    var position0 = UInt8((uap_or_dci >> 0) & 1)
    var position1 = UInt8((uap_or_dci >> 1) & 1)
    var position2 = UInt8((uap_or_dci >> 2) & 1)
    var position3 = UInt8((uap_or_dci >> 3) & 1)
    var position4 = UInt8((uap_or_dci >> 4) & 1)
    var position5 = UInt8((uap_or_dci >> 5) & 1)
    var position6 = UInt8((uap_or_dci >> 6) & 1)
    var position7 = UInt8((uap_or_dci >> 7) & 1)
    for index in range(len(bits_in_transmission_order)):
        var feedback = position7 ^ bits_in_transmission_order[index]
        var next0 = feedback
        var next1 = position0 ^ feedback
        var next2 = position1 ^ feedback
        var next3 = position2
        var next4 = position3
        var next5 = position4 ^ feedback
        var next6 = position5
        var next7 = position6 ^ feedback
        position0 = next0
        position1 = next1
        position2 = next2
        position3 = next3
        position4 = next4
        position5 = next5
        position6 = next6
        position7 = next7

    # The Core reads positions 7 through 0.  Scalar bit i therefore contains
    # transmitted bit i, matching the hexadecimal Part G representation.
    return (
        Int(position7) << 0
        | Int(position6) << 1
        | Int(position5) << 2
        | Int(position4) << 3
        | Int(position3) << 4
        | Int(position2) << 5
        | Int(position1) << 6
        | Int(position0) << 7
    )


def _codeword_bits(
    header_information_bits: Span[UInt8, ...], hec: Int
) -> List[UInt8]:
    var result = List[UInt8](capacity=18)
    for index in range(len(header_information_bits)):
        result.append(header_information_bits[index])
    for index in range(8):
        result.append(UInt8((hec >> index) & 1))
    return result^


def _next(mut state: UInt64) -> UInt64:
    state = state * UInt64(6364136223846793005) + UInt64(1442695040888963407)
    return state


def test_part_g_all_twenty_hec_literals_and_zero_remainders() raises:
    var data_words: List[Int] = [
        0x123, 0x123, 0x124, 0x124, 0x125, 0x125, 0x126, 0x126,
        0x127, 0x127, 0x11B, 0x11B, 0x11C, 0x11C, 0x11D, 0x11D,
        0x11E, 0x11E, 0x11F, 0x11F,
    ]
    var uaps: List[Int] = [
        0x00, 0x47, 0x00, 0x47, 0x00, 0x47, 0x00, 0x47, 0x00, 0x47,
        0x00, 0x47, 0x00, 0x47, 0x00, 0x47, 0x00, 0x47, 0x00, 0x47,
    ]
    var expected_hecs: List[Int] = [
        0xE1, 0x06, 0x32, 0xD5, 0x5A, 0xBD, 0xE2, 0x05, 0x8A, 0x6D,
        0x9E, 0x79, 0x4D, 0xAA, 0x25, 0xC2, 0x9D, 0x7A, 0xF5, 0x12,
    ]
    assert_equal(len(data_words), 20)
    assert_equal(len(uaps), 20)
    assert_equal(len(expected_hecs), 20)

    for row in range(20):
        var header = _bits_from_word(data_words[row], 10)
        var actual = bluetooth_br_edr_hec_generate(
            Span(header), uaps[row]
        )
        assert_equal(Int(actual), expected_hecs[row])
        assert_equal(
            _hec_remainder_eight_cell_oracle(Span(header), uaps[row]),
            expected_hecs[row],
        )
        assert_true(bluetooth_br_edr_hec_check(
            Span(header), expected_hecs[row], uaps[row]
        ))
        var codeword = _codeword_bits(Span(header), expected_hecs[row])
        assert_equal(
            _hec_remainder_eight_cell_oracle(Span(codeword), uaps[row]), 0
        )
        for bit in range(8):
            assert_true(not bluetooth_br_edr_hec_check(
                Span(header), expected_hecs[row] ^ (1 << bit), uaps[row]
            ))


def test_complete_header_and_uap_domain_against_independent_oracle() raises:
    for header_word in range(1 << 10):
        var header = _bits_from_word(header_word, 10)
        for uap_or_dci in range(256):
            assert_equal(
                Int(bluetooth_br_edr_hec_generate(
                    Span(header), uap_or_dci
                )),
                _hec_remainder_eight_cell_oracle(
                    Span(header), uap_or_dci
                ),
            )


def test_seeded_zero_remainder_and_single_bit_properties() raises:
    var state = UInt64(0xB2ED63A7C0DEC0DE)
    for _ in range(2048):
        var header_word = Int(_next(state) & UInt64(0x3FF))
        var uap_or_dci = Int(_next(state) & UInt64(0xFF))
        var header = _bits_from_word(header_word, 10)
        var expected = _hec_remainder_eight_cell_oracle(
            Span(header), uap_or_dci
        )
        assert_equal(
            Int(bluetooth_br_edr_hec_generate(
                Span(header), uap_or_dci
            )),
            expected,
        )
        assert_true(bluetooth_br_edr_hec_check(
            Span(header), expected, uap_or_dci
        ))
        var codeword = _codeword_bits(Span(header), expected)
        assert_equal(
            _hec_remainder_eight_cell_oracle(
                Span(codeword), uap_or_dci
            ),
            0,
        )

        var hec_flip = Int(_next(state) % UInt64(8))
        assert_true(not bluetooth_br_edr_hec_check(
            Span(header), expected ^ (1 << hec_flip), uap_or_dci
        ))
        var header_flip = Int(_next(state) % UInt64(10))
        header[header_flip] ^= UInt8(1)
        assert_true(not bluetooth_br_edr_hec_check(
            Span(header), expected, uap_or_dci
        ))


def test_exact_wire_order_and_dci_anchors() raises:
    var first_header_bit = _bits_from_word(0x001, 10)
    var last_header_bit = _bits_from_word(0x200, 10)
    var all_zero = _bits_from_word(0x000, 10)
    assert_equal(
        Int(bluetooth_br_edr_hec_generate(Span(first_header_bit), 0x00)),
        0x68,
    )
    assert_equal(
        Int(bluetooth_br_edr_hec_generate(Span(last_header_bit), 0x00)),
        0xE5,
    )
    assert_equal(
        Int(bluetooth_br_edr_hec_generate(Span(all_zero), 0x01)),
        0xAE,
    )
    assert_equal(
        Int(bluetooth_br_edr_hec_generate(Span(all_zero), 0x80)),
        0x68,
    )
    assert_equal(
        Int(bluetooth_br_edr_hec_generate(Span(all_zero), 0x00)), 0x00
    )
    assert_true(bluetooth_br_edr_hec_check(Span(all_zero), 0x00, 0x00))
    assert_true(not bluetooth_br_edr_hec_check(
        Span(all_zero), 0x01, 0x00
    ))


def test_shape_and_every_binary_position_are_validated() raises:
    for length in [0, 9, 11]:
        var wrong_shape = List[UInt8](length=length, fill=UInt8(0))
        with assert_raises():
            _ = bluetooth_br_edr_hec_generate(Span(wrong_shape), 0x47)
        with assert_raises():
            _ = bluetooth_br_edr_hec_check(Span(wrong_shape), 0x06, 0x47)

    var legal_ten = List[UInt8](length=10, fill=UInt8(0))
    assert_equal(
        Int(bluetooth_br_edr_hec_generate(Span(legal_ten), 0x00)), 0
    )
    for invalid_bit in [2, 255]:
        for position in range(10):
            var bad_bits = List[UInt8](length=10, fill=UInt8(0))
            bad_bits[position] = UInt8(invalid_bit)
            with assert_raises():
                _ = bluetooth_br_edr_hec_generate(Span(bad_bits), 0x47)
            with assert_raises():
                _ = bluetooth_br_edr_hec_check(
                    Span(bad_bits), 0x06, 0x47
                )


def test_scalar_domains_and_integer_extrema_are_validated() raises:
    var header = _bits_from_word(0x123, 10)
    for invalid_initialization in [-1, 256, Int.MIN, Int.MAX]:
        with assert_raises():
            _ = bluetooth_br_edr_hec_generate(
                Span(header), invalid_initialization
            )
        with assert_raises():
            _ = bluetooth_br_edr_hec_check(
                Span(header), 0x06, invalid_initialization
            )
    for invalid_hec in [-1, 256, Int.MIN, Int.MAX]:
        with assert_raises():
            _ = bluetooth_br_edr_hec_check(
                Span(header), invalid_hec, 0x47
            )

    assert_equal(
        Int(bluetooth_br_edr_hec_generate(Span(header), 0)), 0xE1
    )
    assert_equal(
        Int(bluetooth_br_edr_hec_generate(Span(header), 255)), 0xB4
    )
    assert_true(not bluetooth_br_edr_hec_check(
        Span(header), 0x00, 0x00
    ))
    assert_true(not bluetooth_br_edr_hec_check(
        Span(header), 0xFF, 0xFF
    ))


def test_mutable_input_is_revalidated_on_every_public_call() raises:
    var header = _bits_from_word(0x123, 10)
    var original = bluetooth_br_edr_hec_generate(Span(header), 0x47)
    assert_equal(Int(original), 0x06)
    assert_true(bluetooth_br_edr_hec_check(
        Span(header), Int(original), 0x47
    ))

    header[0] ^= UInt8(1)
    var changed = bluetooth_br_edr_hec_generate(Span(header), 0x47)
    assert_true(changed != original)
    assert_true(not bluetooth_br_edr_hec_check(
        Span(header), Int(original), 0x47
    ))

    header[0] = UInt8(2)
    with assert_raises():
        _ = bluetooth_br_edr_hec_generate(Span(header), 0x47)
    with assert_raises():
        _ = bluetooth_br_edr_hec_check(Span(header), Int(changed), 0x47)

    header[0] = UInt8(1)
    assert_equal(
        bluetooth_br_edr_hec_generate(Span(header), 0x47), original
    )
    assert_true(bluetooth_br_edr_hec_check(
        Span(header), Int(original), 0x47
    ))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
