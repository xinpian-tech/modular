"""Independent exact evidence for Wi-Fi fragmentation and MPDU delimiters.

Static vectors are hand-derived from IEEE Std 802.11-2024 clauses 9.7,
10.4--10.5, and 10.12.7.  CRC differential evidence uses a separate
MSB-first implementation over bit-reversed octets, while fragmentation
properties use direct quotient/remainder arithmetic.  All outputs are
discrete, so the tolerance is exactly zero.
"""

from std.collections import Span
from std.testing import assert_equal, assert_true, assert_raises, TestSuite
from wireless_dsp.wireless.wifi.mac_fragmentation import (
    WIFI_FRAGMENTATION_MAX_FRAGMENTS,
    WIFI_AMPDU_DELIMITER_PROFILE_HT,
    WIFI_AMPDU_DELIMITER_PROFILE_VHT_OR_LATER,
    WIFI_AMPDU_DELIMITER_SIGNATURE,
    wifi_fragmentation_plan,
    wifi_reassembly_plan,
    wifi_ampdu_delimiter_crc8,
    wifi_ampdu_delimiter_serialize,
    wifi_ampdu_delimiter_parse,
)


def _reverse_octet(value: Int) -> Int:
    var result = 0
    var current = value
    for _ in range(8):
        result = (result << 1) | (current & 1)
        current >>= 1
    return result


def _independent_delimiter_crc8(octet0: Int, octet1: Int) -> Int:
    # Independent equivalent: reverse each input octet, run the ordinary
    # MSB-first polynomial-0x07 recurrence, complement, then reverse output.
    var remainder = 0xFF
    var first = _reverse_octet(octet0)
    var second = _reverse_octet(octet1)
    for value in [first, second]:
        remainder ^= value
        for _ in range(8):
            if (remainder & 0x80) != 0:
                remainder = ((remainder << 1) ^ 0x07) & 0xFF
            else:
                remainder = (remainder << 1) & 0xFF
    return _reverse_octet(remainder ^ 0xFF)


def _independent_delimiter_octets(
    mpdu_length_octets: Int,
    eof: Bool,
    profile: Int,
) -> List[UInt8]:
    # Build the transmitted bits directly instead of calling either
    # production serializer or parser.  Keeping this oracle in the test also
    # makes the seeded evidence more than a serializer/parser round trip.
    var length_low = mpdu_length_octets % 4096
    var octet0 = (length_low % 16) * 16
    var octet1 = length_low // 16
    if profile == WIFI_AMPDU_DELIMITER_PROFILE_VHT_OR_LATER:
        octet0 += (mpdu_length_octets // 4096) * 4
        if eof:
            octet0 += 1
    return [
        UInt8(octet0),
        UInt8(octet1),
        UInt8(_independent_delimiter_crc8(octet0, octet1)),
        UInt8(0x4E),
    ]


def _oracle_fragment_count(msdu_octets: Int, capacity: Int) -> Int:
    var count = msdu_octets // capacity
    if msdu_octets % capacity != 0:
        count += 1
    return count


def test_fragmentation_static_clause_vectors() raises:
    var plan = wifi_fragmentation_plan(1000, 300, 40, 291)
    assert_equal(plan.sequence_number, 291)
    assert_equal(plan.payload_capacity_octets, 260)
    assert_equal(plan.payload_offsets, [0, 260, 520, 780])
    assert_equal(plan.payload_octets, [260, 260, 260, 220])
    assert_equal(plan.mpdu_octets, [300, 300, 300, 260])
    assert_equal(plan.fragment_numbers, [0, 1, 2, 3])
    assert_equal(plan.sequence_controls, [4656, 4657, 4658, 4659])
    var expected_more: List[UInt8] = [1, 1, 1, 0]
    assert_equal(plan.more_fragments, expected_more)

    var exact = wifi_fragmentation_plan(1040, 300, 40, 4095)
    assert_equal(exact.payload_octets, [260, 260, 260, 260])
    assert_equal(exact.mpdu_octets, [300, 300, 300, 300])
    assert_equal(exact.sequence_controls, [65520, 65521, 65522, 65523])

    var single = wifi_fragmentation_plan(
        260, 300, 40, 0, is_group_addressed=True
    )
    assert_equal(single.payload_offsets, [0])
    assert_equal(single.payload_octets, [260])
    assert_equal(single.mpdu_octets, [300])
    var single_more: List[UInt8] = [0]
    assert_equal(single.more_fragments, single_more)

    # The smallest threshold can represent exactly sixteen 144-octet
    # payloads when the caller-declared overhead is 112 octets.
    var sixteen = wifi_fragmentation_plan(2304, 256, 112, 1)
    assert_equal(len(sixteen.payload_octets), WIFI_FRAGMENTATION_MAX_FRAGMENTS)
    assert_equal(sixteen.payload_offsets[15], 2160)
    assert_equal(sixteen.payload_octets[15], 144)
    assert_equal(sixteen.fragment_numbers[15], 15)
    assert_equal(sixteen.more_fragments[15], UInt8(0))


def test_reassembly_static_clause_vectors() raises:
    var controls: List[Int] = [4656, 4657, 4658, 4659]
    var more: List[UInt8] = [1, 1, 1, 0]
    var payloads: List[Int] = [260, 260, 260, 220]
    var reassembly = wifi_reassembly_plan(
        Span(controls), Span(more), Span(payloads)
    )
    assert_equal(reassembly.sequence_number, 291)
    assert_equal(reassembly.payload_offsets, [0, 260, 520, 780])
    assert_equal(reassembly.total_msdu_octets, 1000)

    var one_control: List[Int] = [0]
    var one_more: List[UInt8] = [0]
    var one_payload: List[Int] = [2304]
    var one = wifi_reassembly_plan(
        Span(one_control),
        Span(one_more),
        Span(one_payload),
        is_group_addressed=True,
    )
    assert_equal(one.sequence_number, 0)
    assert_equal(one.payload_offsets, [0])
    assert_equal(one.total_msdu_octets, 2304)


def test_delimiter_static_clause_vectors() raises:
    assert_equal(wifi_ampdu_delimiter_crc8(0x01, 0x00), 0x79)
    assert_equal(wifi_ampdu_delimiter_crc8(0xB0, 0x9B), 0x03)
    assert_equal(wifi_ampdu_delimiter_crc8(0xE8, 0xCB), 0xC4)
    assert_equal(wifi_ampdu_delimiter_crc8(0xF0, 0xFF), 0x18)

    var eof = wifi_ampdu_delimiter_serialize(
        0,
        eof=True,
        profile=WIFI_AMPDU_DELIMITER_PROFILE_VHT_OR_LATER,
    )
    var expected_eof: List[UInt8] = [0x01, 0x00, 0x79, 0x4E]
    assert_equal(eof, expected_eof)
    var eof_fields = wifi_ampdu_delimiter_parse(
        Span(eof), profile=WIFI_AMPDU_DELIMITER_PROFILE_VHT_OR_LATER
    )
    assert_equal(eof_fields.first_word, 0x0001)
    assert_equal(eof_fields.mpdu_length_octets, 0)
    assert_true(eof_fields.eof)
    assert_equal(eof_fields.crc, 0x79)
    assert_equal(eof_fields.padding_octets, 0)
    assert_equal(eof_fields.next_delimiter_delta_octets, 4)

    var ordinary = wifi_ampdu_delimiter_serialize(
        2491, profile=WIFI_AMPDU_DELIMITER_PROFILE_VHT_OR_LATER
    )
    var expected_ordinary: List[UInt8] = [0xB0, 0x9B, 0x03, 0x4E]
    assert_equal(ordinary, expected_ordinary)
    var ordinary_fields = wifi_ampdu_delimiter_parse(
        Span(ordinary), profile=WIFI_AMPDU_DELIMITER_PROFILE_VHT_OR_LATER
    )
    assert_equal(ordinary_fields.first_word, 0x9BB0)
    assert_equal(ordinary_fields.mpdu_length_octets, 2491)
    assert_true(not ordinary_fields.eof)
    assert_equal(ordinary_fields.padding_octets, 1)
    assert_equal(ordinary_fields.next_delimiter_delta_octets, 2496)

    # The two MPDU-Length-High bits distinguish the extended profile.
    var extended = wifi_ampdu_delimiter_serialize(
        11454, profile=WIFI_AMPDU_DELIMITER_PROFILE_VHT_OR_LATER
    )
    var expected_extended: List[UInt8] = [0xE8, 0xCB, 0xC4, 0x4E]
    assert_equal(extended, expected_extended)
    var extended_fields = wifi_ampdu_delimiter_parse(
        Span(extended), profile=WIFI_AMPDU_DELIMITER_PROFILE_VHT_OR_LATER
    )
    assert_equal(extended_fields.mpdu_length_octets, 11454)
    assert_equal(extended_fields.padding_octets, 2)
    assert_equal(extended_fields.next_delimiter_delta_octets, 11460)

    var ht = wifi_ampdu_delimiter_serialize(
        4095, profile=WIFI_AMPDU_DELIMITER_PROFILE_HT
    )
    var expected_ht: List[UInt8] = [0xF0, 0xFF, 0x18, 0x4E]
    assert_equal(ht, expected_ht)
    var ht_fields = wifi_ampdu_delimiter_parse(
        Span(ht), profile=WIFI_AMPDU_DELIMITER_PROFILE_HT
    )
    assert_equal(ht_fields.mpdu_length_octets, 4095)
    assert_true(not ht_fields.eof)
    assert_equal(Int(ht[3]), WIFI_AMPDU_DELIMITER_SIGNATURE)


def test_fragmentation_and_reassembly_edge_rejection() raises:
    with assert_raises():
        _ = wifi_fragmentation_plan(0, 300, 40, 0)
    with assert_raises():
        _ = wifi_fragmentation_plan(2305, 300, 40, 0)
    with assert_raises():
        _ = wifi_fragmentation_plan(Int.MAX, 300, 40, 0)
    with assert_raises():
        _ = wifi_fragmentation_plan(1, 255, 0, 0)
    with assert_raises():
        _ = wifi_fragmentation_plan(1, 2347, 0, 0)
    with assert_raises():
        _ = wifi_fragmentation_plan(1, 300, -1, 0)
    with assert_raises():
        _ = wifi_fragmentation_plan(1, 300, 27, 0)
    with assert_raises():
        _ = wifi_fragmentation_plan(1, 300, 300, 0)
    with assert_raises():
        _ = wifi_fragmentation_plan(1, 300, 40, -1)
    with assert_raises():
        _ = wifi_fragmentation_plan(1, 300, 40, 4096)
    with assert_raises():
        _ = wifi_fragmentation_plan(2304, 256, 113, 0)
    with assert_raises():
        _ = wifi_fragmentation_plan(
            1000, 300, 40, 0, is_group_addressed=True
        )

    var empty_control = List[Int]()
    var empty_more = List[UInt8]()
    var empty_payload = List[Int]()
    with assert_raises():
        _ = wifi_reassembly_plan(
            Span(empty_control), Span(empty_more), Span(empty_payload)
        )

    var controls: List[Int] = [160, 161, 162]
    var more: List[UInt8] = [1, 1, 0]
    var payloads: List[Int] = [100, 100, 50]
    var short_more: List[UInt8] = [1, 0]
    with assert_raises():
        _ = wifi_reassembly_plan(
            Span(controls), Span(short_more), Span(payloads)
        )
    with assert_raises():
        _ = wifi_reassembly_plan(
            Span(controls),
            Span(more),
            Span(payloads),
            is_group_addressed=True,
        )

    var wrong_sequence: List[Int] = [160, 177, 162]
    with assert_raises():
        _ = wifi_reassembly_plan(
            Span(wrong_sequence), Span(more), Span(payloads)
        )
    var missing_number: List[Int] = [160, 162, 163]
    with assert_raises():
        _ = wifi_reassembly_plan(
            Span(missing_number), Span(more), Span(payloads)
        )
    var invalid_control: List[Int] = [65536]
    var final_only: List[UInt8] = [0]
    var payload_only: List[Int] = [1]
    with assert_raises():
        _ = wifi_reassembly_plan(
            Span(invalid_control), Span(final_only), Span(payload_only)
        )

    var early_final: List[UInt8] = [1, 0, 0]
    with assert_raises():
        _ = wifi_reassembly_plan(
            Span(controls), Span(early_final), Span(payloads)
        )
    var invalid_flag: List[UInt8] = [1, 2, 0]
    with assert_raises():
        _ = wifi_reassembly_plan(
            Span(controls), Span(invalid_flag), Span(payloads)
        )
    var unequal_nonfinal: List[Int] = [100, 99, 50]
    with assert_raises():
        _ = wifi_reassembly_plan(
            Span(controls), Span(more), Span(unequal_nonfinal)
        )
    var final_too_long: List[Int] = [100, 100, 101]
    with assert_raises():
        _ = wifi_reassembly_plan(
            Span(controls), Span(more), Span(final_too_long)
        )
    var zero_payload: List[Int] = [100, 100, 0]
    with assert_raises():
        _ = wifi_reassembly_plan(
            Span(controls), Span(more), Span(zero_payload)
        )
    var two_controls: List[Int] = [160, 161]
    var two_more: List[UInt8] = [1, 0]
    var oversized_total: List[Int] = [2304, 1]
    with assert_raises():
        _ = wifi_reassembly_plan(
            Span(two_controls), Span(two_more), Span(oversized_total)
        )


def test_delimiter_edge_and_reserved_bit_rejection() raises:
    with assert_raises():
        _ = wifi_ampdu_delimiter_crc8(-1, 0)
    with assert_raises():
        _ = wifi_ampdu_delimiter_crc8(0, 256)
    with assert_raises():
        _ = wifi_ampdu_delimiter_serialize(-1)
    with assert_raises():
        _ = wifi_ampdu_delimiter_serialize(11455)
    with assert_raises():
        _ = wifi_ampdu_delimiter_serialize(
            4096, profile=WIFI_AMPDU_DELIMITER_PROFILE_HT
        )
    with assert_raises():
        _ = wifi_ampdu_delimiter_serialize(
            0, eof=True, profile=WIFI_AMPDU_DELIMITER_PROFILE_HT
        )
    with assert_raises():
        _ = wifi_ampdu_delimiter_serialize(1, profile=2)

    var empty = List[UInt8]()
    with assert_raises():
        _ = wifi_ampdu_delimiter_parse(Span(empty))
    var valid = wifi_ampdu_delimiter_serialize(2491)
    valid[2] = UInt8(Int(valid[2]) ^ 1)
    with assert_raises():
        _ = wifi_ampdu_delimiter_parse(Span(valid))
    var bad_signature = wifi_ampdu_delimiter_serialize(2491)
    bad_signature[3] = 0
    with assert_raises():
        _ = wifi_ampdu_delimiter_parse(Span(bad_signature))

    # B1 is reserved in both non-DMG profiles.  Recompute the CRC so the
    # parser reaches reserved-bit validation rather than failing earlier.
    var reserved_crc = _independent_delimiter_crc8(0x02, 0x00)
    var reserved: List[UInt8] = [
        0x02, 0x00, UInt8(reserved_crc), 0x4E
    ]
    with assert_raises():
        _ = wifi_ampdu_delimiter_parse(Span(reserved))

    # Extended length 4096 occupies B2; the same bytes are illegal for HT.
    var high_length = wifi_ampdu_delimiter_serialize(
        4096, profile=WIFI_AMPDU_DELIMITER_PROFILE_VHT_OR_LATER
    )
    with assert_raises():
        _ = wifi_ampdu_delimiter_parse(
            Span(high_length), profile=WIFI_AMPDU_DELIMITER_PROFILE_HT
        )


def test_seeded_fragmentation_and_reassembly_properties() raises:
    var seed = UInt64(0x11F24A6C5EED2024)
    for _ in range(257):
        seed = (
            seed * UInt64(6364136223846793005)
            + UInt64(1442695040888963407)
        )
        var msdu = 1 + Int(seed % UInt64(2304))
        var threshold = 256 + Int((seed >> 12) % UInt64(2091))
        var overhead = 28 + Int((seed >> 37) % UInt64(36))
        var sequence = Int((seed >> 20) & UInt64(0xFFF))
        var capacity = threshold - overhead
        var expected_count = _oracle_fragment_count(msdu, capacity)
        var plan = wifi_fragmentation_plan(
            msdu, threshold, overhead, sequence
        )
        assert_equal(len(plan.payload_octets), expected_count)
        assert_equal(plan.payload_capacity_octets, capacity)
        var total = 0
        for index in range(expected_count):
            var expected_payload = min(capacity, msdu - total)
            assert_equal(plan.payload_offsets[index], total)
            assert_equal(plan.payload_octets[index], expected_payload)
            assert_equal(plan.mpdu_octets[index], expected_payload + overhead)
            assert_equal(plan.fragment_numbers[index], index)
            assert_equal(
                plan.sequence_controls[index], sequence * 16 + index
            )
            assert_equal(
                plan.more_fragments[index],
                UInt8(1 if index + 1 < expected_count else 0),
            )
            total += expected_payload
        assert_equal(total, msdu)

        var reassembly = wifi_reassembly_plan(
            Span(plan.sequence_controls),
            Span(plan.more_fragments),
            Span(plan.payload_octets),
        )
        assert_equal(reassembly.sequence_number, sequence)
        assert_equal(reassembly.payload_offsets, plan.payload_offsets)
        assert_equal(reassembly.total_msdu_octets, msdu)


def test_delimiter_crc_exhaustive_independent_oracle() raises:
    # Exhaust all 65,536 protected two-octet values.  The implementation under
    # test is reflected/LSB-first; the oracle is MSB-first with bit reversals.
    for octet1 in range(256):
        for octet0 in range(256):
            assert_equal(
                wifi_ampdu_delimiter_crc8(octet0, octet1),
                _independent_delimiter_crc8(octet0, octet1),
            )


def test_delimiter_seeded_serialize_parse_differential_exact() raises:
    var seed = UInt64(0x4E07C8C2024BEE11)
    for iteration in range(257):
        seed = (
            seed * UInt64(2862933555777941757)
            + UInt64(3037000493)
        )
        var profile = (
            WIFI_AMPDU_DELIMITER_PROFILE_HT
            if iteration % 2 == 0
            else WIFI_AMPDU_DELIMITER_PROFILE_VHT_OR_LATER
        )
        var maximum = 4095 if profile == WIFI_AMPDU_DELIMITER_PROFILE_HT else 11454
        var length = Int(seed % UInt64(maximum + 1))
        var eof = (
            profile == WIFI_AMPDU_DELIMITER_PROFILE_VHT_OR_LATER
            and ((seed >> 40) & UInt64(1)) != 0
        )
        var delimiter = wifi_ampdu_delimiter_serialize(
            length, eof=eof, profile=profile
        )
        var expected = _independent_delimiter_octets(length, eof, profile)
        assert_equal(delimiter, expected)
        assert_equal(
            Int(expected[2]),
            _independent_delimiter_crc8(Int(expected[0]), Int(expected[1])),
        )
        assert_equal(Int(expected[3]), 0x4E)
        var fields = wifi_ampdu_delimiter_parse(
            Span(expected), profile=profile
        )
        assert_equal(fields.mpdu_length_octets, length)
        assert_equal(fields.eof, eof)
        assert_equal(fields.padding_octets, (4 - length % 4) % 4)
        assert_equal(
            fields.next_delimiter_delta_octets,
            4 + length + (4 - length % 4) % 4,
        )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
