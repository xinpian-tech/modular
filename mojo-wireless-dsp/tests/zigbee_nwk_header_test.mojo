"""Independent evidence for the Zigbee R23.2 NWK base-header slice.

The literal fields and test-local bit-weight packer follow the locked Zigbee
R23.2 scope: clauses 1.2.3, 1.4.2, 3.3, 3.3.1,
3.3.1.1--3.3.1.1.8, 3.3.1.2--3.3.1.5, 3.3.2.1, and 3.3.2.1.1, with Tables
1-5, 3-51--3-53, 3-66, and 3-80.  Exhaustive evidence covers all 65,536
frame-control words, every valid unicast address, both complete octet fields,
all caller-state Boolean combinations, strict shape, mutation revalidation,
and signed-Int endpoints.  Encode/decode round trips are used only as
additional properties; the static and differential oracles never call the
opposite production direction.

Official artifact SHA-256:
c2638ad11136c94f69ac6ea445d6a6ebf164791c64bea5806de2c2ad4c1fe2ea.
"""

from std.collections import Span
from std.testing import TestSuite, assert_equal, assert_raises, assert_true
from wireless_dsp.wireless.zigbee import (
    ZIGBEE_NWK_DATA_BASE_HEADER_OCTETS,
    ZIGBEE_NWK_PROTOCOL_VERSION,
    ZIGBEE_NWK_MAX_UNICAST_ADDRESS,
    ZIGBEE_NWK_DISCOVER_ROUTE_SUPPRESS,
    ZIGBEE_NWK_DISCOVER_ROUTE_ENABLE,
    ZigbeeNWKDataHeaderConfig,
    zigbee_nwk_data_header_encode,
    zigbee_nwk_data_header_decode,
)


def _oracle_header(
    destination_address: Int,
    source_address: Int,
    radius: Int,
    sequence_number: Int,
    discover_route: Int,
    source_is_end_device: Bool,
    parent_information_nonzero: Bool,
) -> List[UInt8]:
    # Independent field construction: name each transmitted frame-control
    # bit and then accumulate little-endian octets by arithmetic weights.
    var bits = List[Int](length=16, fill=0)
    bits[3] = 1  # protocol version 2 is 0010 in bits 2--5
    bits[6] = discover_route
    bits[13] = 1 if source_is_end_device and parent_information_nonzero else 0
    var low = 0
    var high = 0
    var weight = 1
    for bit in range(8):
        low += bits[bit] * weight
        high += bits[bit + 8] * weight
        weight *= 2
    return [
        UInt8(low),
        UInt8(high),
        UInt8(destination_address % 256),
        UInt8(destination_address // 256),
        UInt8(source_address % 256),
        UInt8(source_address // 256),
        UInt8(radius),
        UInt8(sequence_number),
    ]


def _frame_control_header(frame_control: Int) -> List[UInt8]:
    return [
        UInt8(frame_control & 0xFF),
        UInt8((frame_control >> 8) & 0xFF),
        UInt8(0x34),
        UInt8(0x12),
        UInt8(0xCD),
        UInt8(0xAB),
        UInt8(5),
        UInt8(0x9A),
    ]


def _decode_outcome(frame_control: Int) -> Int:
    var header = _frame_control_header(frame_control)
    try:
        _ = zigbee_nwk_data_header_decode(Span(header))
        return 1
    except:
        return 0


def test_exported_constants_and_literal_vectors() raises:
    assert_equal(ZIGBEE_NWK_DATA_BASE_HEADER_OCTETS, 8)
    assert_equal(ZIGBEE_NWK_PROTOCOL_VERSION, 2)
    assert_equal(ZIGBEE_NWK_MAX_UNICAST_ADDRESS, 0xFFF7)
    assert_equal(ZIGBEE_NWK_DISCOVER_ROUTE_SUPPRESS, 0)
    assert_equal(ZIGBEE_NWK_DISCOVER_ROUTE_ENABLE, 1)

    var initiator = ZigbeeNWKDataHeaderConfig(
        0x1234,
        0xABCD,
        5,
        0x9A,
        1,
        source_is_end_device=True,
        parent_information_nonzero=True,
    )
    var encoded = zigbee_nwk_data_header_encode(initiator)
    var expected: List[UInt8] = [0x48, 0x20, 0x34, 0x12, 0xCD, 0xAB, 0x05, 0x9A]
    assert_equal(encoded, expected)
    var decoded = zigbee_nwk_data_header_decode(Span(expected))
    assert_equal(decoded.destination_address, 0x1234)
    assert_equal(decoded.source_address, 0xABCD)
    assert_equal(decoded.radius, 5)
    assert_equal(decoded.sequence_number, 0x9A)
    assert_equal(decoded.discover_route, 1)
    assert_true(decoded.end_device_initiator)

    var ordinary = ZigbeeNWKDataHeaderConfig(0, 0xFFF7, 0, 0, 0)
    var ordinary_encoded = zigbee_nwk_data_header_encode(ordinary)
    var ordinary_expected: List[UInt8] = [
        0x08,
        0x00,
        0x00,
        0x00,
        0xF7,
        0xFF,
        0x00,
        0x00,
    ]
    assert_equal(ordinary_encoded, ordinary_expected)


def test_independent_bit_packing_oracle_and_boolean_derivation() raises:
    for discover_route in range(2):
        for source_is_end_device_value in range(2):
            for parent_information_value in range(2):
                var source_is_end_device = source_is_end_device_value == 1
                var parent_information_nonzero = parent_information_value == 1
                var config = ZigbeeNWKDataHeaderConfig(
                    0x0102,
                    0xBEEF,
                    0x80,
                    0x7F,
                    discover_route,
                    source_is_end_device=source_is_end_device,
                    parent_information_nonzero=parent_information_nonzero,
                )
                var encoded = zigbee_nwk_data_header_encode(config)
                assert_equal(
                    encoded,
                    _oracle_header(
                        0x0102,
                        0xBEEF,
                        0x80,
                        0x7F,
                        discover_route,
                        source_is_end_device,
                        parent_information_nonzero,
                    ),
                )
                var expected_initiator = (
                    source_is_end_device and parent_information_nonzero
                )
                assert_equal((Int(encoded[1]) & 0x20) != 0, expected_initiator)


def test_every_frame_control_word_matches_strict_predicate() raises:
    var accepted = 0
    for frame_control in range(0x10000):
        var expected = (
            (frame_control & 0x0003) == 0
            and ((frame_control >> 2) & 0x000F) == 2
            and ((frame_control >> 6) & 0x0003) <= 1
            and (frame_control & 0x1F00) == 0
        )
        var outcome = _decode_outcome(frame_control)
        assert_equal(outcome, 1 if expected else 0)
        accepted += outcome
    # Discover Route, End Device Initiator, and two ignored reserved bits.
    assert_equal(accepted, 16)


def test_every_unicast_address_and_address_exclusions() raises:
    var config = ZigbeeNWKDataHeaderConfig(0, 0, 1, 2, 0)
    for address in range(ZIGBEE_NWK_MAX_UNICAST_ADDRESS + 1):
        config.destination_address = address
        config.source_address = address
        var encoded = zigbee_nwk_data_header_encode(config)
        assert_equal(Int(encoded[2]), address % 256)
        assert_equal(Int(encoded[3]), address // 256)
        assert_equal(Int(encoded[4]), address % 256)
        assert_equal(Int(encoded[5]), address // 256)
        var decoded = zigbee_nwk_data_header_decode(Span(encoded))
        assert_equal(decoded.destination_address, address)
        assert_equal(decoded.source_address, address)

    for address in range(0xFFF8, 0x10000):
        with assert_raises():
            _ = ZigbeeNWKDataHeaderConfig(address, 0, 0, 0, 0)
        with assert_raises():
            _ = ZigbeeNWKDataHeaderConfig(0, address, 0, 0, 0)
        var destination_header = _frame_control_header(0x0008)
        destination_header[2] = UInt8(address & 0xFF)
        destination_header[3] = UInt8(address >> 8)
        with assert_raises():
            _ = zigbee_nwk_data_header_decode(Span(destination_header))
        var source_header = _frame_control_header(0x0008)
        source_header[4] = UInt8(address & 0xFF)
        source_header[5] = UInt8(address >> 8)
        with assert_raises():
            _ = zigbee_nwk_data_header_decode(Span(source_header))


def test_complete_radius_and_sequence_octet_domains() raises:
    var config = ZigbeeNWKDataHeaderConfig(1, 2, 0, 0, 1)
    for radius in range(256):
        for sequence_number in range(256):
            config.radius = radius
            config.sequence_number = sequence_number
            var encoded = zigbee_nwk_data_header_encode(config)
            assert_equal(Int(encoded[6]), radius)
            assert_equal(Int(encoded[7]), sequence_number)
            var decoded = zigbee_nwk_data_header_decode(Span(encoded))
            assert_equal(decoded.radius, radius)
            assert_equal(decoded.sequence_number, sequence_number)


def test_explicit_illegal_flags_and_ignored_reserved_bits() raises:
    for frame_type in range(1, 4):
        with assert_raises():
            var header = _frame_control_header(0x0008 | frame_type)
            _ = zigbee_nwk_data_header_decode(Span(header))
    for version in range(16):
        if version != 2:
            with assert_raises():
                var header = _frame_control_header(version << 2)
                _ = zigbee_nwk_data_header_decode(Span(header))
    for discover_route in range(2, 4):
        with assert_raises():
            var header = _frame_control_header(0x0008 | (discover_route << 6))
            _ = zigbee_nwk_data_header_decode(Span(header))
    # Deprecated Multicast, Security, Source Route, Destination IEEE Address,
    # and Source IEEE Address all leave this exact eight-octet profile.
    for disallowed_mask in [0x0100, 0x0200, 0x0400, 0x0800, 0x1000]:
        with assert_raises():
            var header = _frame_control_header(0x0008 | disallowed_mask)
            _ = zigbee_nwk_data_header_decode(Span(header))

    # Bits 14--15 are RX-ignored, while bit 13 is a decoded field.
    for reserved in [0x0000, 0x4000, 0x8000, 0xC000]:
        for initiator_value in range(2):
            var frame_control = 0x0048 | reserved | (initiator_value << 13)
            var header = _frame_control_header(frame_control)
            var decoded = zigbee_nwk_data_header_decode(Span(header))
            assert_equal(decoded.destination_address, 0x1234)
            assert_equal(decoded.source_address, 0xABCD)
            assert_equal(decoded.radius, 5)
            assert_equal(decoded.sequence_number, 0x9A)
            assert_equal(decoded.discover_route, 1)
            assert_equal(decoded.end_device_initiator, initiator_value == 1)


def test_strict_shape_and_mutable_revalidation() raises:
    for length in range(8):
        var short_header = List[UInt8](length=length, fill=UInt8(0))
        with assert_raises():
            _ = zigbee_nwk_data_header_decode(Span(short_header))
    for length in range(9, 17):
        var long_header = List[UInt8](length=length, fill=UInt8(0))
        with assert_raises():
            _ = zigbee_nwk_data_header_decode(Span(long_header))

    var config = ZigbeeNWKDataHeaderConfig(1, 2, 3, 4, 0)
    config.destination_address = -1
    with assert_raises():
        _ = zigbee_nwk_data_header_encode(config)
    config.destination_address = 1
    config.source_address = 0xFFF8
    with assert_raises():
        _ = zigbee_nwk_data_header_encode(config)
    config.source_address = 2
    config.radius = -1
    with assert_raises():
        _ = zigbee_nwk_data_header_encode(config)
    config.radius = 3
    config.sequence_number = 256
    with assert_raises():
        _ = zigbee_nwk_data_header_encode(config)
    config.sequence_number = 4
    config.discover_route = 2
    with assert_raises():
        _ = zigbee_nwk_data_header_encode(config)
    config.discover_route = 0
    config.source_is_end_device = True
    var no_parent = zigbee_nwk_data_header_encode(config)
    assert_equal(Int(no_parent[1]) & 0x20, 0)
    config.parent_information_nonzero = True
    var with_parent = zigbee_nwk_data_header_encode(config)
    assert_equal(Int(with_parent[1]) & 0x20, 0x20)


def test_signed_int_endpoints_and_exact_field_edges() raises:
    for invalid in [Int.MIN, -1, Int.MAX]:
        with assert_raises():
            _ = ZigbeeNWKDataHeaderConfig(invalid, 0, 0, 0, 0)
        with assert_raises():
            _ = ZigbeeNWKDataHeaderConfig(0, invalid, 0, 0, 0)
        with assert_raises():
            _ = ZigbeeNWKDataHeaderConfig(0, 0, invalid, 0, 0)
        with assert_raises():
            _ = ZigbeeNWKDataHeaderConfig(0, 0, 0, invalid, 0)
        with assert_raises():
            _ = ZigbeeNWKDataHeaderConfig(0, 0, 0, 0, invalid)

    var minimum = ZigbeeNWKDataHeaderConfig(0, 0, 0, 0, 0)
    assert_equal(
        zigbee_nwk_data_header_encode(minimum),
        _oracle_header(0, 0, 0, 0, 0, False, False),
    )
    var maximum = ZigbeeNWKDataHeaderConfig(
        0xFFF7,
        0xFFF7,
        0xFF,
        0xFF,
        1,
        source_is_end_device=True,
        parent_information_nonzero=True,
    )
    assert_equal(
        zigbee_nwk_data_header_encode(maximum),
        _oracle_header(0xFFF7, 0xFFF7, 0xFF, 0xFF, 1, True, True),
    )


def test_seeded_roundtrip_property_is_not_the_oracle() raises:
    var state = UInt64(0xD1B54A32D192ED03)
    var checksum = UInt64(1469598103934665603)
    for _ in range(4096):
        state = state * UInt64(6364136223846793005) + UInt64(1)
        var destination_address = Int(state % UInt64(0xFFF8))
        state = state * UInt64(1442695040888963407) + UInt64(1)
        var source_address = Int(state % UInt64(0xFFF8))
        var radius = Int((state >> UInt64(16)) & UInt64(0xFF))
        var sequence_number = Int((state >> UInt64(32)) & UInt64(0xFF))
        var discover_route = Int((state >> UInt64(48)) & UInt64(1))
        var source_is_end_device = (state & UInt64(2)) != 0
        var parent_information_nonzero = (state & UInt64(4)) != 0
        var config = ZigbeeNWKDataHeaderConfig(
            destination_address,
            source_address,
            radius,
            sequence_number,
            discover_route,
            source_is_end_device=source_is_end_device,
            parent_information_nonzero=parent_information_nonzero,
        )
        var encoded = zigbee_nwk_data_header_encode(config)
        assert_equal(
            encoded,
            _oracle_header(
                destination_address,
                source_address,
                radius,
                sequence_number,
                discover_route,
                source_is_end_device,
                parent_information_nonzero,
            ),
        )
        var decoded = zigbee_nwk_data_header_decode(Span(encoded))
        assert_equal(decoded.destination_address, destination_address)
        assert_equal(decoded.source_address, source_address)
        assert_equal(decoded.radius, radius)
        assert_equal(decoded.sequence_number, sequence_number)
        assert_equal(decoded.discover_route, discover_route)
        assert_equal(
            decoded.end_device_initiator,
            source_is_end_device and parent_information_nonzero,
        )
        checksum = (
            checksum
            ^ UInt64(destination_address + 1)
            ^ (UInt64(source_address + 1) << UInt64(16))
            ^ (UInt64(radius + 1) << UInt64(32))
            ^ (UInt64(sequence_number + 1) << UInt64(40))
            ^ UInt64(1 if decoded.end_device_initiator else 0)
        ) * UInt64(1099511628211)
    assert_true(checksum != 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
