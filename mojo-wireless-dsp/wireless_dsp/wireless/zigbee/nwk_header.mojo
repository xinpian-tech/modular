"""Bounded Zigbee R23.2 unsecured unicast NWK data base header.

This CPU-only module implements the exact eight-octet NWK header profile in
Zigbee Specification R23.2, clauses 1.2.3, 1.4.2, 3.3, 3.3.1,
3.3.1.1--3.3.1.1.8, 3.3.1.2--3.3.1.5, 3.3.2.1, and 3.3.2.1.1, with Tables
1-5, 3-51--3-53, 3-66, and 3-80.  The profile is a protocol-version-2 data
frame with a 16-bit unicast destination, a 16-bit unicast source, no NWK
security, no source route subframe, and no optional IEEE addresses.  Discover
Route is limited to its two non-reserved values.  The End Device Initiator bit
is derived from the caller-owned device/NIB state required by clause
3.3.1.1.8.

Broadcast/multicast addressing, NWK command frames, security processing,
source routing, optional IEEE addresses, payload construction, sequence
state, radius updates, forwarding, and MAC framing are outside this narrow
serializer/parser.  Receive accepts but does not expose reserved frame-control
bits 14--15 because the specification requires receivers to ignore them.

Normative artifact: Zigbee Specification R23.2, Zigbee Document
05-3474-23, issue 1.0, released by the Connectivity Standards Alliance on
2025-11-10 at
https://csa-iot.org/wp-content/uploads/2025/11/docs-06-3474-23-csg-zigbee-specificationR23.2_clean.pdf,
SHA-256 c2638ad11136c94f69ac6ea445d6a6ebf164791c64bea5806de2c2ad4c1fe2ea.
"""

from std.collections import Span


comptime ZIGBEE_NWK_DATA_BASE_HEADER_OCTETS = 8
comptime ZIGBEE_NWK_PROTOCOL_VERSION = 2
comptime ZIGBEE_NWK_MAX_UNICAST_ADDRESS = 0xFFF7
comptime ZIGBEE_NWK_DISCOVER_ROUTE_SUPPRESS = 0
comptime ZIGBEE_NWK_DISCOVER_ROUTE_ENABLE = 1

comptime _FRAME_TYPE_DATA = 0
comptime _FRAME_TYPE_MASK = 0x0003
comptime _PROTOCOL_VERSION_MASK = 0x003C
comptime _DISCOVER_ROUTE_MASK = 0x00C0
comptime _DISALLOWED_BASE_HEADER_FLAGS_MASK = 0x1F00
comptime _END_DEVICE_INITIATOR_MASK = 0x2000
comptime _BASE_FRAME_CONTROL = 0x0008


def _validate_unicast_address(address: Int, label: String) raises:
    if address < 0 or address > ZIGBEE_NWK_MAX_UNICAST_ADDRESS:
        raise Error(label + " must be a 16-bit Zigbee unicast address")


def _validate_octet(value: Int, label: String) raises:
    if value < 0 or value > 0xFF:
        raise Error(label + " must be an unsigned octet")


def _validate_discover_route(discover_route: Int) raises:
    if (
        discover_route != ZIGBEE_NWK_DISCOVER_ROUTE_SUPPRESS
        and discover_route != ZIGBEE_NWK_DISCOVER_ROUTE_ENABLE
    ):
        raise Error("Zigbee Discover Route must be Suppress or Enable")


struct ZigbeeNWKDataHeaderConfig(Equatable, ImplicitlyCopyable):
    """Mutable caller state for one bounded NWK data base header.

    All fields remain public for composition.  The encoder revalidates the
    entire record on every call, so mutation cannot bypass the exact domains.
    ``parent_information_nonzero`` is the clause-3.3.1.1.8 predicate
    ``nwkParentInformation != 0``; the raw NIB bitmask is intentionally not
    copied into this wire-format boundary.
    """

    var destination_address: Int
    var source_address: Int
    var radius: Int
    var sequence_number: Int
    var discover_route: Int
    var source_is_end_device: Bool
    var parent_information_nonzero: Bool

    def __init__(
        out self,
        destination_address: Int,
        source_address: Int,
        radius: Int,
        sequence_number: Int,
        discover_route: Int,
        *,
        source_is_end_device: Bool = False,
        parent_information_nonzero: Bool = False,
    ) raises:
        self.destination_address = destination_address
        self.source_address = source_address
        self.radius = radius
        self.sequence_number = sequence_number
        self.discover_route = discover_route
        self.source_is_end_device = source_is_end_device
        self.parent_information_nonzero = parent_information_nonzero
        self.validate()

    def validate(self) raises:
        """Revalidate every mutable scalar field against the bounded profile."""
        _validate_unicast_address(
            self.destination_address, "Zigbee NWK destination address"
        )
        _validate_unicast_address(
            self.source_address, "Zigbee NWK source address"
        )
        _validate_octet(self.radius, "Zigbee NWK radius")
        _validate_octet(self.sequence_number, "Zigbee NWK sequence number")
        _validate_discover_route(self.discover_route)


struct ZigbeeNWKDataHeader(Equatable, ImplicitlyCopyable):
    """Canonical fields decoded from the fixed eight-octet base header.

    Reserved receive bits 14--15 are deliberately absent.  The decoded End
    Device Initiator bit is exposed directly because the two caller-state
    predicates from which a transmitter derives it cannot be reconstructed
    from the wire representation.
    """

    var destination_address: Int
    var source_address: Int
    var radius: Int
    var sequence_number: Int
    var discover_route: Int
    var end_device_initiator: Bool

    def __init__(
        out self,
        destination_address: Int,
        source_address: Int,
        radius: Int,
        sequence_number: Int,
        discover_route: Int,
        end_device_initiator: Bool,
    ):
        self.destination_address = destination_address
        self.source_address = source_address
        self.radius = radius
        self.sequence_number = sequence_number
        self.discover_route = discover_route
        self.end_device_initiator = end_device_initiator


def zigbee_nwk_data_header_encode(
    config: ZigbeeNWKDataHeaderConfig,
) raises -> List[UInt8]:
    """Serialize one canonical unsecured unicast NWK data base header.

    Frame type and protocol version are fixed to Data and version 2.  The
    End Device Initiator flag is always derived afresh as
    ``source_is_end_device and parent_information_nonzero``.
    """
    config.validate()
    var end_device_initiator = (
        config.source_is_end_device and config.parent_information_nonzero
    )
    var frame_control = _BASE_FRAME_CONTROL | (config.discover_route << 6)
    if end_device_initiator:
        frame_control |= _END_DEVICE_INITIATOR_MASK
    return [
        UInt8(frame_control & 0xFF),
        UInt8((frame_control >> 8) & 0xFF),
        UInt8(config.destination_address & 0xFF),
        UInt8((config.destination_address >> 8) & 0xFF),
        UInt8(config.source_address & 0xFF),
        UInt8((config.source_address >> 8) & 0xFF),
        UInt8(config.radius),
        UInt8(config.sequence_number),
    ]


def zigbee_nwk_data_header_decode(
    header: Span[UInt8, ...],
) raises -> ZigbeeNWKDataHeader:
    """Strictly parse one bounded eight-octet NWK data base header.

    Reserved frame type, protocol version, Discover Route, multicast,
    security, source-route, and optional-address encodings are rejected.
    Reserved frame-control bits 14--15 are ignored as required by R23.2.
    """
    if len(header) != ZIGBEE_NWK_DATA_BASE_HEADER_OCTETS:
        raise Error("Zigbee NWK data base header must contain exactly 8 octets")

    var frame_control = Int(header[0]) | (Int(header[1]) << 8)
    if (frame_control & _FRAME_TYPE_MASK) != _FRAME_TYPE_DATA:
        raise Error("Zigbee NWK base header must carry a data frame")
    if (
        frame_control & _PROTOCOL_VERSION_MASK
    ) >> 2 != ZIGBEE_NWK_PROTOCOL_VERSION:
        raise Error("Zigbee NWK base header must use protocol version 2")
    var discover_route = (frame_control & _DISCOVER_ROUTE_MASK) >> 6
    _validate_discover_route(discover_route)
    if (frame_control & _DISALLOWED_BASE_HEADER_FLAGS_MASK) != 0:
        raise Error(
            "Zigbee bounded base header forbids multicast, security, source "
            "route, and optional IEEE addresses"
        )

    var destination_address = Int(header[2]) | (Int(header[3]) << 8)
    var source_address = Int(header[4]) | (Int(header[5]) << 8)
    _validate_unicast_address(
        destination_address, "Zigbee NWK destination address"
    )
    _validate_unicast_address(source_address, "Zigbee NWK source address")
    return ZigbeeNWKDataHeader(
        destination_address,
        source_address,
        Int(header[6]),
        Int(header[7]),
        discover_route,
        (frame_control & _END_DEVICE_INITIATOR_MASK) != 0,
    )
