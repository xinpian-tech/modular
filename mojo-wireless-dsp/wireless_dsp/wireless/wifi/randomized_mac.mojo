"""Bounded IEEE 802.11bh randomized/changing-MAC identity fields.

This scalar CPU reference implements a deliberately finite part of IEEE Std
802.11bh-2024 clauses 9.4.2, 9.6.36, and 12.2.13: local-individual MAC-address
classification, the direction-dependent base fields of Device ID, IRM, and
PASN ID elements, Identifier Status and IRM Action tables, and the explicit
Recognized/Not Recognized shared-identity transition.

The element payload APIs start immediately after the Element ID Extension
field.  They cover the base fields only: no optional trailing subelements,
KDE header, PASN Encrypted Data container, or complete management/action
frame is serialized.  Device ID and PASN ID payloads begin with their one-
octet identifier length.  A status octet follows only when an AP sends the
element.  The base IRM payload is exactly six octets from a non-AP STA and
exactly one status octet from an AP.

The published IEEE 802.11bh-2024 standard is the sole normative baseline.
Final-SA-recirculation record 11-24/1262r6 is a historical cross-check only,
not a production authority; its private draft target is not used.  Adopted
11-24/1301r4 defines Device ID/PASN ID status values 0, 1, and 2 and the
shared-identity transitions.  Adopted 11-24/0048r12 pins the IRM shape,
directional omission rules, and action values, while the final initial-SA
resolutions in 11-24/0883r15 retain the random-local IRM definition.  IEEE
802.11bh-2024 is published at
https://standards.ieee.org/ieee/802.11bh/10525/ .

Random-number generation or quality, AES-SIV and key handling, opaque Device
ID construction, privacy policy, identifier distribution across an ESS,
authentication/association/roaming orchestration, duplicate-detection policy,
and a complete session state machine are intentionally outside this module.
"""

from std.collections import Span


comptime WIFI_RANDOMIZED_MAC_IDENTIFIER_DEVICE_ID = 0
comptime WIFI_RANDOMIZED_MAC_IDENTIFIER_IRM = 1
comptime WIFI_RANDOMIZED_MAC_IDENTIFIER_PASN_ID = 2

comptime WIFI_RANDOMIZED_MAC_SENDER_NON_AP_STA = 0
comptime WIFI_RANDOMIZED_MAC_SENDER_AP = 1

comptime WIFI_RANDOMIZED_MAC_STATUS_NOT_PRESENT = -1
comptime WIFI_RANDOMIZED_MAC_STATUS_RECOGNIZED = 0
comptime WIFI_RANDOMIZED_MAC_STATUS_NOT_RECOGNIZED = 1
comptime WIFI_RANDOMIZED_MAC_STATUS_NOT_APPLICABLE = 2

comptime WIFI_RANDOMIZED_MAC_IRM_ACTION_DUPLICATE = 0
comptime WIFI_RANDOMIZED_MAC_IRM_ACTION_NEW = 1

comptime WIFI_RANDOMIZED_MAC_ADDRESS_OCTETS = 6
comptime WIFI_RANDOMIZED_MAC_PASN_ID_MIN_OCTETS = 6
comptime WIFI_RANDOMIZED_MAC_ELEMENT_BASE_MAX_OCTETS = 254


struct WifiRandomizedMacIdentifierConfig(ImplicitlyCopyable):
    """Mutable identifier kind and sender role for one base element payload."""

    var identifier_kind: Int
    var sender_role: Int

    def __init__(
        out self, identifier_kind: Int, sender_role: Int
    ) raises:
        self.identifier_kind = identifier_kind
        self.sender_role = sender_role
        self.validate()

    def validate(self) raises:
        """Revalidate both mutable profile selectors."""
        if (
            self.identifier_kind
            != WIFI_RANDOMIZED_MAC_IDENTIFIER_DEVICE_ID
            and self.identifier_kind
            != WIFI_RANDOMIZED_MAC_IDENTIFIER_IRM
            and self.identifier_kind
            != WIFI_RANDOMIZED_MAC_IDENTIFIER_PASN_ID
        ):
            raise Error("identifier kind must be Device ID, IRM, or PASN ID")
        if (
            self.sender_role != WIFI_RANDOMIZED_MAC_SENDER_NON_AP_STA
            and self.sender_role != WIFI_RANDOMIZED_MAC_SENDER_AP
        ):
            raise Error("sender role must be non-AP STA or AP")


struct WifiRandomizedMacIdentifierStatus(ImplicitlyCopyable):
    """Strictly decoded non-reserved Identifier Status table row."""

    var status: Int
    var recognized: Bool
    var not_recognized: Bool
    var not_applicable: Bool

    def __init__(
        out self,
        status: Int,
        recognized: Bool,
        not_recognized: Bool,
        not_applicable: Bool,
    ):
        self.status = status
        self.recognized = recognized
        self.not_recognized = not_recognized
        self.not_applicable = not_applicable


struct WifiRandomizedMacIdentifierPayload(Movable):
    """Parsed direction-dependent base fields after Element ID Extension."""

    var identifier_kind: Int
    var sender_role: Int
    var status_present: Bool
    var status: Int
    var identifier_length_octets: Int
    var identifier: List[UInt8]

    def __init__(
        out self,
        identifier_kind: Int,
        sender_role: Int,
        status_present: Bool,
        status: Int,
        identifier_length_octets: Int,
        var identifier: List[UInt8],
    ):
        self.identifier_kind = identifier_kind
        self.sender_role = sender_role
        self.status_present = status_present
        self.status = status
        self.identifier_length_octets = identifier_length_octets
        self.identifier = identifier^


struct WifiRandomizedMacSharedIdentityState(Movable):
    """Bound or absent state derived from a 0/1 response status."""

    var response_status: Int
    var shared_identity_present: Bool
    var bound_address2: List[UInt8]

    def __init__(
        out self,
        response_status: Int,
        shared_identity_present: Bool,
        var bound_address2: List[UInt8],
    ):
        self.response_status = response_status
        self.shared_identity_present = shared_identity_present
        self.bound_address2 = bound_address2^


struct WifiRandomizedMacIRMAction(ImplicitlyCopyable):
    """Strictly decoded non-reserved IRM Action field."""

    var action: Int
    var duplicate_irm: Bool
    var new_irm: Bool

    def __init__(
        out self, action: Int, duplicate_irm: Bool, new_irm: Bool
    ):
        self.action = action
        self.duplicate_irm = duplicate_irm
        self.new_irm = new_irm


def wifi_randomized_mac_is_local_individual(
    address: Span[UInt8, ...],
) raises -> Bool:
    """Return whether a six-octet address has I/G=0 and U/L=1.

    This exact bit predicate is necessary for an IRM, but it cannot prove
    that an address was selected randomly or according to a privacy policy.
    """
    if len(address) != WIFI_RANDOMIZED_MAC_ADDRESS_OCTETS:
        raise Error("a MAC address must contain exactly six octets")
    return (Int(address[0]) & 0x03) == 0x02


def wifi_randomized_mac_identifier_status_decode(
    identifier_kind: Int, status: Int
) raises -> WifiRandomizedMacIdentifierStatus:
    """Decode the adopted Device ID, IRM, or PASN ID status table.

    Device ID and PASN ID accept 0 Recognized, 1 Not Recognized, and 2 Not
    Applicable.  IRM accepts only 0 and 1.  Reserved and out-of-octet values
    are rejected instead of being normalized.
    """
    var config = WifiRandomizedMacIdentifierConfig(
        identifier_kind, WIFI_RANDOMIZED_MAC_SENDER_AP
    )
    config.validate()
    if status == WIFI_RANDOMIZED_MAC_STATUS_RECOGNIZED:
        return WifiRandomizedMacIdentifierStatus(status, True, False, False)
    if status == WIFI_RANDOMIZED_MAC_STATUS_NOT_RECOGNIZED:
        return WifiRandomizedMacIdentifierStatus(status, False, True, False)
    if (
        status == WIFI_RANDOMIZED_MAC_STATUS_NOT_APPLICABLE
        and identifier_kind != WIFI_RANDOMIZED_MAC_IDENTIFIER_IRM
    ):
        return WifiRandomizedMacIdentifierStatus(status, False, False, True)
    raise Error("identifier status is reserved or invalid for this kind")


def _validate_identifier_value(
    config: WifiRandomizedMacIdentifierConfig,
    status: Int,
    identifier: Span[UInt8, ...],
) raises:
    config.validate()
    var identifier_octets = len(identifier)
    if config.identifier_kind == WIFI_RANDOMIZED_MAC_IDENTIFIER_IRM:
        if config.sender_role == WIFI_RANDOMIZED_MAC_SENDER_NON_AP_STA:
            if status != WIFI_RANDOMIZED_MAC_STATUS_NOT_PRESENT:
                raise Error("non-AP IRM payload shall omit IRM Status")
            if not wifi_randomized_mac_is_local_individual(identifier):
                raise Error("an IRM must be a local individual MAC address")
        else:
            _ = wifi_randomized_mac_identifier_status_decode(
                WIFI_RANDOMIZED_MAC_IDENTIFIER_IRM, status
            )
            if identifier_octets != 0:
                raise Error("AP IRM payload shall omit the IRM field")
        return

    var max_identifier_octets = (
        252
        if config.sender_role == WIFI_RANDOMIZED_MAC_SENDER_AP
        else 253
    )
    if identifier_octets > max_identifier_octets:
        raise Error("identifier exceeds the one-octet element Length limit")

    if config.sender_role == WIFI_RANDOMIZED_MAC_SENDER_NON_AP_STA:
        if status != WIFI_RANDOMIZED_MAC_STATUS_NOT_PRESENT:
            raise Error("a non-AP identifier payload shall omit status")
        if identifier_octets == 0:
            raise Error("a transmitted non-AP identifier cannot be empty")
    else:
        var fields = wifi_randomized_mac_identifier_status_decode(
            config.identifier_kind, status
        )
        if fields.not_applicable and identifier_octets == 0:
            raise Error("Not Applicable response shall carry a new identifier")

    if config.identifier_kind == WIFI_RANDOMIZED_MAC_IDENTIFIER_PASN_ID:
        if (
            identifier_octets != 0
            and identifier_octets < WIFI_RANDOMIZED_MAC_PASN_ID_MIN_OCTETS
        ):
            raise Error("a present PASN ID must contain at least six octets")
        if (
            config.sender_role == WIFI_RANDOMIZED_MAC_SENDER_AP
            and status == WIFI_RANDOMIZED_MAC_STATUS_RECOGNIZED
            and identifier_octets == 0
        ):
            raise Error("a recognized PASN response shall carry a new PASN ID")


def wifi_randomized_mac_identifier_payload_serialize(
    config: WifiRandomizedMacIdentifierConfig,
    status: Int,
    identifier: Span[UInt8, ...],
) raises -> List[UInt8]:
    """Serialize one base identifier payload after Element ID Extension.

    ``status`` shall be ``WIFI_RANDOMIZED_MAC_STATUS_NOT_PRESENT`` for a
    non-AP STA.  AP IRM payloads contain status only.  No trailing extension
    data is emitted.
    """
    _validate_identifier_value(config, status, identifier)
    if config.identifier_kind == WIFI_RANDOMIZED_MAC_IDENTIFIER_IRM:
        if config.sender_role == WIFI_RANDOMIZED_MAC_SENDER_AP:
            return [UInt8(status)]
        var irm = List[UInt8](capacity=WIFI_RANDOMIZED_MAC_ADDRESS_OCTETS)
        for index in range(len(identifier)):
            irm.append(identifier[index])
        return irm^

    var status_octets = (
        1 if config.sender_role == WIFI_RANDOMIZED_MAC_SENDER_AP else 0
    )
    var result = List[UInt8](capacity=1 + status_octets + len(identifier))
    result.append(UInt8(len(identifier)))
    if config.sender_role == WIFI_RANDOMIZED_MAC_SENDER_AP:
        result.append(UInt8(status))
    for index in range(len(identifier)):
        result.append(identifier[index])
    return result^


def wifi_randomized_mac_identifier_payload_parse(
    config: WifiRandomizedMacIdentifierConfig,
    payload: Span[UInt8, ...],
) raises -> WifiRandomizedMacIdentifierPayload:
    """Parse and strictly validate one base identifier element payload."""
    config.validate()
    if len(payload) > WIFI_RANDOMIZED_MAC_ELEMENT_BASE_MAX_OCTETS:
        raise Error("base element payload exceeds the element Length limit")

    if config.identifier_kind == WIFI_RANDOMIZED_MAC_IDENTIFIER_IRM:
        if config.sender_role == WIFI_RANDOMIZED_MAC_SENDER_AP:
            if len(payload) != 1:
                raise Error("AP IRM payload must contain only IRM Status")
            var status = Int(payload[0])
            var no_identifier = List[UInt8]()
            _validate_identifier_value(
                config, status, Span(no_identifier)
            )
            return WifiRandomizedMacIdentifierPayload(
                config.identifier_kind,
                config.sender_role,
                True,
                status,
                0,
                no_identifier^,
            )
        if len(payload) != WIFI_RANDOMIZED_MAC_ADDRESS_OCTETS:
            raise Error("non-AP IRM payload must contain exactly six octets")
        var irm = List[UInt8](capacity=WIFI_RANDOMIZED_MAC_ADDRESS_OCTETS)
        for index in range(len(payload)):
            irm.append(payload[index])
        _validate_identifier_value(
            config, WIFI_RANDOMIZED_MAC_STATUS_NOT_PRESENT, Span(irm)
        )
        return WifiRandomizedMacIdentifierPayload(
            config.identifier_kind,
            config.sender_role,
            False,
            WIFI_RANDOMIZED_MAC_STATUS_NOT_PRESENT,
            WIFI_RANDOMIZED_MAC_ADDRESS_OCTETS,
            irm^,
        )

    if len(payload) < 1:
        raise Error("identifier payload is missing its length field")
    var identifier_octets = Int(payload[0])
    var status = WIFI_RANDOMIZED_MAC_STATUS_NOT_PRESENT
    var identifier_offset = 1
    if config.sender_role == WIFI_RANDOMIZED_MAC_SENDER_AP:
        if len(payload) < 2:
            raise Error("AP identifier payload is missing Identifier Status")
        status = Int(payload[1])
        identifier_offset = 2
    if identifier_octets != len(payload) - identifier_offset:
        raise Error("identifier length field does not match the payload")

    var identifier = List[UInt8](capacity=identifier_octets)
    for index in range(identifier_octets):
        identifier.append(payload[identifier_offset + index])
    _validate_identifier_value(config, status, Span(identifier))
    return WifiRandomizedMacIdentifierPayload(
        config.identifier_kind,
        config.sender_role,
        config.sender_role == WIFI_RANDOMIZED_MAC_SENDER_AP,
        status,
        identifier_octets,
        identifier^,
    )


def wifi_randomized_mac_shared_identity_from_status(
    response_status: Int, latest_request_address2: Span[UInt8, ...]
) raises -> WifiRandomizedMacSharedIdentityState:
    """Apply the explicit Recognized/Not Recognized identity-state rule.

    Status 0 binds shared identity state to Address 2 from the most recently
    transmitted Association Request or first PASN frame.  Status 1 yields no
    shared identity state.  Status 2 is excluded because the adopted text does
    not define it through either of these two transition paragraphs.
    """
    if (
        response_status != WIFI_RANDOMIZED_MAC_STATUS_RECOGNIZED
        and response_status != WIFI_RANDOMIZED_MAC_STATUS_NOT_RECOGNIZED
    ):
        raise Error("shared-identity transition requires status 0 or 1")
    if len(latest_request_address2) != WIFI_RANDOMIZED_MAC_ADDRESS_OCTETS:
        raise Error("Address 2 must contain exactly six octets")
    if (Int(latest_request_address2[0]) & 1) != 0:
        raise Error("Address 2 for this transition must be individual")

    var bound_address = List[UInt8]()
    if response_status == WIFI_RANDOMIZED_MAC_STATUS_RECOGNIZED:
        bound_address = List[UInt8](capacity=WIFI_RANDOMIZED_MAC_ADDRESS_OCTETS)
        for index in range(len(latest_request_address2)):
            bound_address.append(latest_request_address2[index])
        return WifiRandomizedMacSharedIdentityState(
            response_status, True, bound_address^
        )
    return WifiRandomizedMacSharedIdentityState(
        response_status, False, bound_address^
    )


def wifi_randomized_mac_irm_action_serialize(action: Int) raises -> UInt8:
    """Serialize Duplicate IRM (0) or New IRM (1); reject reserved values."""
    if (
        action != WIFI_RANDOMIZED_MAC_IRM_ACTION_DUPLICATE
        and action != WIFI_RANDOMIZED_MAC_IRM_ACTION_NEW
    ):
        raise Error("IRM Action must be Duplicate IRM or New IRM")
    return UInt8(action)


def wifi_randomized_mac_irm_action_parse(
    field: Span[UInt8, ...],
) raises -> WifiRandomizedMacIRMAction:
    """Parse the exact one-octet IRM Action field."""
    if len(field) != 1:
        raise Error("IRM Action field must contain exactly one octet")
    var action = Int(field[0])
    _ = wifi_randomized_mac_irm_action_serialize(action)
    return WifiRandomizedMacIRMAction(
        action,
        action == WIFI_RANDOMIZED_MAC_IRM_ACTION_DUPLICATE,
        action == WIFI_RANDOMIZED_MAC_IRM_ACTION_NEW,
    )
