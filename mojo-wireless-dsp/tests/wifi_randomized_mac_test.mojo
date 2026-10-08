"""Independent evidence for the bounded IEEE 802.11bh identity-field core.

Literal vectors pin the adopted direction-dependent Device ID, IRM, and PASN
ID base fields and both one-octet tables.  A separate direct assembler and
seeded parser comparison cover every supported kind/direction/status branch;
address-bit and status tables are also exhaustively checked.  All evidence is
integer/byte exact, so the tolerance is zero.
"""

from std.collections import Span
from std.testing import assert_equal, assert_raises, assert_true, TestSuite
from wireless_dsp.wireless.wifi.randomized_mac import (
    WIFI_RANDOMIZED_MAC_IDENTIFIER_DEVICE_ID,
    WIFI_RANDOMIZED_MAC_IDENTIFIER_IRM,
    WIFI_RANDOMIZED_MAC_IDENTIFIER_PASN_ID,
    WIFI_RANDOMIZED_MAC_SENDER_NON_AP_STA,
    WIFI_RANDOMIZED_MAC_SENDER_AP,
    WIFI_RANDOMIZED_MAC_STATUS_NOT_PRESENT,
    WIFI_RANDOMIZED_MAC_STATUS_RECOGNIZED,
    WIFI_RANDOMIZED_MAC_STATUS_NOT_RECOGNIZED,
    WIFI_RANDOMIZED_MAC_STATUS_NOT_APPLICABLE,
    WIFI_RANDOMIZED_MAC_IRM_ACTION_DUPLICATE,
    WIFI_RANDOMIZED_MAC_IRM_ACTION_NEW,
    WifiRandomizedMacIdentifierConfig,
    wifi_randomized_mac_is_local_individual,
    wifi_randomized_mac_identifier_status_decode,
    wifi_randomized_mac_identifier_payload_serialize,
    wifi_randomized_mac_identifier_payload_parse,
    wifi_randomized_mac_shared_identity_from_status,
    wifi_randomized_mac_irm_action_serialize,
    wifi_randomized_mac_irm_action_parse,
)


def _assert_octets_equal(
    actual: Span[UInt8, ...], expected: Span[UInt8, ...]
) raises:
    assert_equal(len(actual), len(expected))
    for index in range(len(actual)):
        assert_equal(actual[index], expected[index])


def _oracle_payload(
    identifier_kind: Int,
    sender_role: Int,
    status: Int,
    identifier: Span[UInt8, ...],
) -> List[UInt8]:
    # Independent direct layout assembler: it does not call either production
    # serializer, parser, status decoder, or profile validation.
    if identifier_kind == WIFI_RANDOMIZED_MAC_IDENTIFIER_IRM:
        if sender_role == WIFI_RANDOMIZED_MAC_SENDER_AP:
            return [UInt8(status)]
        var irm = List[UInt8](capacity=6)
        for index in range(len(identifier)):
            irm.append(identifier[index])
        return irm^
    var extra = 1 if sender_role == WIFI_RANDOMIZED_MAC_SENDER_AP else 0
    var result = List[UInt8](capacity=1 + extra + len(identifier))
    result.append(UInt8(len(identifier)))
    if sender_role == WIFI_RANDOMIZED_MAC_SENDER_AP:
        result.append(UInt8(status))
    for index in range(len(identifier)):
        result.append(identifier[index])
    return result^


def _next_seed(seed: UInt64) -> UInt64:
    return (
        seed * UInt64(6364136223846793005) + UInt64(1442695040888963407)
    )


def test_static_identifier_payload_vectors_exact() raises:
    var device: List[UInt8] = [0xDE, 0xAD, 0xBE, 0xEF]
    var pasn: List[UInt8] = [0x10, 0x20, 0x30, 0x40, 0x50, 0x60]
    var irm: List[UInt8] = [0x02, 0x11, 0x22, 0x33, 0x44, 0x55]
    var empty = List[UInt8]()

    var device_request = WifiRandomizedMacIdentifierConfig(
        WIFI_RANDOMIZED_MAC_IDENTIFIER_DEVICE_ID,
        WIFI_RANDOMIZED_MAC_SENDER_NON_AP_STA,
    )
    var encoded_device_request = (
        wifi_randomized_mac_identifier_payload_serialize(
            device_request,
            WIFI_RANDOMIZED_MAC_STATUS_NOT_PRESENT,
            Span(device),
        )
    )
    var expected_device_request: List[UInt8] = [
        4, 0xDE, 0xAD, 0xBE, 0xEF
    ]
    _assert_octets_equal(
        Span(encoded_device_request), Span(expected_device_request)
    )

    var device_response = WifiRandomizedMacIdentifierConfig(
        WIFI_RANDOMIZED_MAC_IDENTIFIER_DEVICE_ID,
        WIFI_RANDOMIZED_MAC_SENDER_AP,
    )
    var maintain = wifi_randomized_mac_identifier_payload_serialize(
        device_response,
        WIFI_RANDOMIZED_MAC_STATUS_RECOGNIZED,
        Span(empty),
    )
    var expected_maintain: List[UInt8] = [0, 0]
    _assert_octets_equal(Span(maintain), Span(expected_maintain))
    var initial_device = wifi_randomized_mac_identifier_payload_serialize(
        device_response,
        WIFI_RANDOMIZED_MAC_STATUS_NOT_APPLICABLE,
        Span(device),
    )
    var expected_initial_device: List[UInt8] = [
        4, 2, 0xDE, 0xAD, 0xBE, 0xEF
    ]
    _assert_octets_equal(
        Span(initial_device), Span(expected_initial_device)
    )

    var irm_request = WifiRandomizedMacIdentifierConfig(
        WIFI_RANDOMIZED_MAC_IDENTIFIER_IRM,
        WIFI_RANDOMIZED_MAC_SENDER_NON_AP_STA,
    )
    var encoded_irm = wifi_randomized_mac_identifier_payload_serialize(
        irm_request,
        WIFI_RANDOMIZED_MAC_STATUS_NOT_PRESENT,
        Span(irm),
    )
    _assert_octets_equal(Span(encoded_irm), Span(irm))
    var irm_response = WifiRandomizedMacIdentifierConfig(
        WIFI_RANDOMIZED_MAC_IDENTIFIER_IRM,
        WIFI_RANDOMIZED_MAC_SENDER_AP,
    )
    var rejected_irm = wifi_randomized_mac_identifier_payload_serialize(
        irm_response,
        WIFI_RANDOMIZED_MAC_STATUS_NOT_RECOGNIZED,
        Span(empty),
    )
    var expected_rejected_irm: List[UInt8] = [1]
    _assert_octets_equal(Span(rejected_irm), Span(expected_rejected_irm))

    var pasn_request = WifiRandomizedMacIdentifierConfig(
        WIFI_RANDOMIZED_MAC_IDENTIFIER_PASN_ID,
        WIFI_RANDOMIZED_MAC_SENDER_NON_AP_STA,
    )
    var encoded_pasn_request = (
        wifi_randomized_mac_identifier_payload_serialize(
            pasn_request,
            WIFI_RANDOMIZED_MAC_STATUS_NOT_PRESENT,
            Span(pasn),
        )
    )
    var expected_pasn_request: List[UInt8] = [
        6, 0x10, 0x20, 0x30, 0x40, 0x50, 0x60
    ]
    _assert_octets_equal(
        Span(encoded_pasn_request), Span(expected_pasn_request)
    )

    var pasn_response = WifiRandomizedMacIdentifierConfig(
        WIFI_RANDOMIZED_MAC_IDENTIFIER_PASN_ID,
        WIFI_RANDOMIZED_MAC_SENDER_AP,
    )
    var renewed_pasn = wifi_randomized_mac_identifier_payload_serialize(
        pasn_response,
        WIFI_RANDOMIZED_MAC_STATUS_RECOGNIZED,
        Span(pasn),
    )
    var expected_renewed_pasn: List[UInt8] = [
        6, 0, 0x10, 0x20, 0x30, 0x40, 0x50, 0x60
    ]
    _assert_octets_equal(Span(renewed_pasn), Span(expected_renewed_pasn))
    var no_replacement = wifi_randomized_mac_identifier_payload_serialize(
        pasn_response,
        WIFI_RANDOMIZED_MAC_STATUS_NOT_RECOGNIZED,
        Span(empty),
    )
    var expected_no_replacement: List[UInt8] = [0, 1]
    _assert_octets_equal(
        Span(no_replacement), Span(expected_no_replacement)
    )

    var parsed = wifi_randomized_mac_identifier_payload_parse(
        device_response, Span(initial_device)
    )
    assert_equal(parsed.identifier_kind, WIFI_RANDOMIZED_MAC_IDENTIFIER_DEVICE_ID)
    assert_equal(parsed.sender_role, WIFI_RANDOMIZED_MAC_SENDER_AP)
    assert_true(parsed.status_present)
    assert_equal(parsed.status, WIFI_RANDOMIZED_MAC_STATUS_NOT_APPLICABLE)
    assert_equal(parsed.identifier_length_octets, 4)
    _assert_octets_equal(Span(parsed.identifier), Span(device))


def test_complete_status_address_and_action_tables() raises:
    for first_octet in range(256):
        var address: List[UInt8] = [UInt8(first_octet), 0, 0, 0, 0, 1]
        assert_equal(
            wifi_randomized_mac_is_local_individual(Span(address)),
            (first_octet & 0x03) == 0x02,
        )

    for identifier_kind in range(3):
        var last_valid = (
            1
            if identifier_kind == WIFI_RANDOMIZED_MAC_IDENTIFIER_IRM
            else 2
        )
        for status in range(256):
            if status <= last_valid:
                var fields = wifi_randomized_mac_identifier_status_decode(
                    identifier_kind, status
                )
                assert_equal(fields.status, status)
                assert_equal(fields.recognized, status == 0)
                assert_equal(fields.not_recognized, status == 1)
                assert_equal(fields.not_applicable, status == 2)
            else:
                with assert_raises():
                    _ = wifi_randomized_mac_identifier_status_decode(
                        identifier_kind, status
                    )

    assert_equal(
        wifi_randomized_mac_irm_action_serialize(
            WIFI_RANDOMIZED_MAC_IRM_ACTION_DUPLICATE
        ),
        UInt8(0),
    )
    assert_equal(
        wifi_randomized_mac_irm_action_serialize(
            WIFI_RANDOMIZED_MAC_IRM_ACTION_NEW
        ),
        UInt8(1),
    )
    var duplicate_field: List[UInt8] = [0]
    var duplicate = wifi_randomized_mac_irm_action_parse(
        Span(duplicate_field)
    )
    assert_equal(duplicate.action, 0)
    assert_true(duplicate.duplicate_irm)
    assert_true(not duplicate.new_irm)
    var new_field: List[UInt8] = [1]
    var replacement = wifi_randomized_mac_irm_action_parse(Span(new_field))
    assert_equal(replacement.action, 1)
    assert_true(not replacement.duplicate_irm)
    assert_true(replacement.new_irm)


def test_shared_identity_static_and_seeded_state_oracle() raises:
    var address: List[UInt8] = [0xDA, 0x7A, 0x11, 0x22, 0x33, 0x44]
    var recognized = wifi_randomized_mac_shared_identity_from_status(
        WIFI_RANDOMIZED_MAC_STATUS_RECOGNIZED, Span(address)
    )
    assert_equal(recognized.response_status, 0)
    assert_true(recognized.shared_identity_present)
    _assert_octets_equal(Span(recognized.bound_address2), Span(address))
    address[5] = 0x99
    assert_equal(recognized.bound_address2[5], UInt8(0x44))

    var absent = wifi_randomized_mac_shared_identity_from_status(
        WIFI_RANDOMIZED_MAC_STATUS_NOT_RECOGNIZED, Span(address)
    )
    assert_equal(absent.response_status, 1)
    assert_true(not absent.shared_identity_present)
    assert_equal(len(absent.bound_address2), 0)

    var seed = UInt64(0x80211B2024)
    for iteration in range(2048):
        seed = _next_seed(seed)
        var generated = List[UInt8](capacity=6)
        for octet_index in range(6):
            generated.append(UInt8(
                (seed >> UInt64((octet_index * 9) % 53)) & UInt64(255)
            ))
        generated[0] = UInt8(Int(generated[0]) & 0xFE)
        var status = Int((seed >> UInt64(61)) & UInt64(1))
        var state = wifi_randomized_mac_shared_identity_from_status(
            status, Span(generated)
        )
        assert_equal(state.response_status, status)
        assert_equal(state.shared_identity_present, status == 0)
        if status == 0:
            _assert_octets_equal(Span(state.bound_address2), Span(generated))
        else:
            assert_equal(len(state.bound_address2), 0)
        assert_true(iteration >= 0)


def test_seeded_payload_differential_and_parser_properties() raises:
    var seed = UInt64(0xB17F1E1D)
    for iteration in range(2048):
        seed = _next_seed(seed)
        var kind = Int(seed % UInt64(3))
        var role = Int((seed >> UInt64(7)) & UInt64(1))
        var status = WIFI_RANDOMIZED_MAC_STATUS_NOT_PRESENT
        var identifier_octets = 1 + Int((seed >> UInt64(13)) % UInt64(24))
        if kind == WIFI_RANDOMIZED_MAC_IDENTIFIER_IRM:
            identifier_octets = 6 if role == 0 else 0
            if role == WIFI_RANDOMIZED_MAC_SENDER_AP:
                status = Int((seed >> UInt64(23)) & UInt64(1))
        elif role == WIFI_RANDOMIZED_MAC_SENDER_AP:
            status = Int((seed >> UInt64(23)) % UInt64(3))
            if kind == WIFI_RANDOMIZED_MAC_IDENTIFIER_PASN_ID:
                if status == WIFI_RANDOMIZED_MAC_STATUS_NOT_RECOGNIZED and (
                    (seed >> UInt64(29)) & UInt64(1)
                ) == UInt64(0):
                    identifier_octets = 0
                else:
                    identifier_octets = 6 + Int(
                        (seed >> UInt64(31)) % UInt64(19)
                    )
            elif status == WIFI_RANDOMIZED_MAC_STATUS_NOT_APPLICABLE:
                identifier_octets = 1 + Int(
                    (seed >> UInt64(31)) % UInt64(24)
                )
            elif (
                status == WIFI_RANDOMIZED_MAC_STATUS_RECOGNIZED
                and ((seed >> UInt64(29)) & UInt64(1)) == UInt64(0)
            ):
                identifier_octets = 0
        elif kind == WIFI_RANDOMIZED_MAC_IDENTIFIER_PASN_ID:
            identifier_octets = 6 + Int(
                (seed >> UInt64(31)) % UInt64(19)
            )

        var identifier = List[UInt8](capacity=identifier_octets)
        for index in range(identifier_octets):
            identifier.append(UInt8(
                (seed >> UInt64((index * 11) % 59)) & UInt64(255)
            ))
        if (
            kind == WIFI_RANDOMIZED_MAC_IDENTIFIER_IRM
            and role == WIFI_RANDOMIZED_MAC_SENDER_NON_AP_STA
        ):
            identifier[0] = UInt8((Int(identifier[0]) & 0xFC) | 0x02)

        var config = WifiRandomizedMacIdentifierConfig(kind, role)
        var actual = wifi_randomized_mac_identifier_payload_serialize(
            config, status, Span(identifier)
        )
        var expected = _oracle_payload(
            kind, role, status, Span(identifier)
        )
        _assert_octets_equal(Span(actual), Span(expected))

        var parsed = wifi_randomized_mac_identifier_payload_parse(
            config, Span(expected)
        )
        assert_equal(parsed.identifier_kind, kind)
        assert_equal(parsed.sender_role, role)
        assert_equal(
            parsed.status_present,
            role == WIFI_RANDOMIZED_MAC_SENDER_AP,
        )
        assert_equal(parsed.status, status)
        assert_equal(parsed.identifier_length_octets, identifier_octets)
        _assert_octets_equal(Span(parsed.identifier), Span(identifier))
        assert_true(iteration >= 0)


def test_public_mutation_lengths_reserved_and_integer_edges() raises:
    with assert_raises():
        _ = WifiRandomizedMacIdentifierConfig(-1, 0)
    with assert_raises():
        _ = WifiRandomizedMacIdentifierConfig(3, 0)
    with assert_raises():
        _ = WifiRandomizedMacIdentifierConfig(Int.MAX, 0)
    with assert_raises():
        _ = WifiRandomizedMacIdentifierConfig(0, -1)
    with assert_raises():
        _ = WifiRandomizedMacIdentifierConfig(0, 2)
    with assert_raises():
        _ = WifiRandomizedMacIdentifierConfig(0, Int.MIN)

    for invalid_status in [-1, 3, 255, 256, Int.MAX, Int.MIN]:
        with assert_raises():
            _ = wifi_randomized_mac_identifier_status_decode(
                WIFI_RANDOMIZED_MAC_IDENTIFIER_DEVICE_ID, invalid_status
            )
    with assert_raises():
        _ = wifi_randomized_mac_identifier_status_decode(
            WIFI_RANDOMIZED_MAC_IDENTIFIER_IRM,
            WIFI_RANDOMIZED_MAC_STATUS_NOT_APPLICABLE,
        )
    for invalid_action in [-1, 2, 255, 256, Int.MAX, Int.MIN]:
        with assert_raises():
            _ = wifi_randomized_mac_irm_action_serialize(invalid_action)

    var empty = List[UInt8]()
    var short_address: List[UInt8] = [0x02, 0, 0, 0, 0]
    var long_address: List[UInt8] = [0x02, 0, 0, 0, 0, 0, 0]
    with assert_raises():
        _ = wifi_randomized_mac_is_local_individual(Span(empty))
    with assert_raises():
        _ = wifi_randomized_mac_is_local_individual(Span(short_address))
    with assert_raises():
        _ = wifi_randomized_mac_is_local_individual(Span(long_address))

    var device_request = WifiRandomizedMacIdentifierConfig(
        WIFI_RANDOMIZED_MAC_IDENTIFIER_DEVICE_ID,
        WIFI_RANDOMIZED_MAC_SENDER_NON_AP_STA,
    )
    var one: List[UInt8] = [0x55]
    var valid = wifi_randomized_mac_identifier_payload_serialize(
        device_request,
        WIFI_RANDOMIZED_MAC_STATUS_NOT_PRESENT,
        Span(one),
    )
    device_request.identifier_kind = 3
    with assert_raises():
        _ = wifi_randomized_mac_identifier_payload_serialize(
            device_request,
            WIFI_RANDOMIZED_MAC_STATUS_NOT_PRESENT,
            Span(one),
        )
    with assert_raises():
        _ = wifi_randomized_mac_identifier_payload_parse(
            device_request, Span(valid)
        )
    device_request.identifier_kind = WIFI_RANDOMIZED_MAC_IDENTIFIER_DEVICE_ID
    device_request.sender_role = 2
    with assert_raises():
        _ = wifi_randomized_mac_identifier_payload_parse(
            device_request, Span(valid)
        )

    var irm_request = WifiRandomizedMacIdentifierConfig(
        WIFI_RANDOMIZED_MAC_IDENTIFIER_IRM,
        WIFI_RANDOMIZED_MAC_SENDER_NON_AP_STA,
    )
    var mutable_irm: List[UInt8] = [0x02, 1, 2, 3, 4, 5]
    _ = wifi_randomized_mac_identifier_payload_serialize(
        irm_request,
        WIFI_RANDOMIZED_MAC_STATUS_NOT_PRESENT,
        Span(mutable_irm),
    )
    mutable_irm[0] = 0x00
    with assert_raises():
        _ = wifi_randomized_mac_identifier_payload_serialize(
            irm_request,
            WIFI_RANDOMIZED_MAC_STATUS_NOT_PRESENT,
            Span(mutable_irm),
        )
    mutable_irm[0] = 0x03
    with assert_raises():
        _ = wifi_randomized_mac_identifier_payload_parse(
            irm_request, Span(mutable_irm)
        )

    var device_response = WifiRandomizedMacIdentifierConfig(
        WIFI_RANDOMIZED_MAC_IDENTIFIER_DEVICE_ID,
        WIFI_RANDOMIZED_MAC_SENDER_AP,
    )
    var malformed: List[UInt8] = [2, 0, 0xAA]
    with assert_raises():
        _ = wifi_randomized_mac_identifier_payload_parse(
            device_response, Span(malformed)
        )
    malformed[0] = 1
    malformed[1] = 3
    with assert_raises():
        _ = wifi_randomized_mac_identifier_payload_parse(
            device_response, Span(malformed)
        )
    var missing_status: List[UInt8] = [0]
    with assert_raises():
        _ = wifi_randomized_mac_identifier_payload_parse(
            device_response, Span(missing_status)
        )

    var pasn_request = WifiRandomizedMacIdentifierConfig(
        WIFI_RANDOMIZED_MAC_IDENTIFIER_PASN_ID,
        WIFI_RANDOMIZED_MAC_SENDER_NON_AP_STA,
    )
    var short_pasn = List[UInt8](length=5, fill=UInt8(0x11))
    with assert_raises():
        _ = wifi_randomized_mac_identifier_payload_serialize(
            pasn_request,
            WIFI_RANDOMIZED_MAC_STATUS_NOT_PRESENT,
            Span(short_pasn),
        )
    var pasn_response = WifiRandomizedMacIdentifierConfig(
        WIFI_RANDOMIZED_MAC_IDENTIFIER_PASN_ID,
        WIFI_RANDOMIZED_MAC_SENDER_AP,
    )
    with assert_raises():
        _ = wifi_randomized_mac_identifier_payload_serialize(
            pasn_response,
            WIFI_RANDOMIZED_MAC_STATUS_RECOGNIZED,
            Span(empty),
        )
    with assert_raises():
        _ = wifi_randomized_mac_identifier_payload_serialize(
            pasn_response,
            WIFI_RANDOMIZED_MAC_STATUS_NOT_APPLICABLE,
            Span(empty),
        )

    var max_non_ap = List[UInt8](length=253, fill=UInt8(0xA5))
    var max_non_ap_payload = wifi_randomized_mac_identifier_payload_serialize(
        pasn_request,
        WIFI_RANDOMIZED_MAC_STATUS_NOT_PRESENT,
        Span(max_non_ap),
    )
    assert_equal(len(max_non_ap_payload), 254)
    var too_long_non_ap = List[UInt8](length=254, fill=UInt8(0xA5))
    with assert_raises():
        _ = wifi_randomized_mac_identifier_payload_serialize(
            pasn_request,
            WIFI_RANDOMIZED_MAC_STATUS_NOT_PRESENT,
            Span(too_long_non_ap),
        )
    var max_ap = List[UInt8](length=252, fill=UInt8(0x5A))
    var max_ap_payload = wifi_randomized_mac_identifier_payload_serialize(
        pasn_response,
        WIFI_RANDOMIZED_MAC_STATUS_NOT_RECOGNIZED,
        Span(max_ap),
    )
    assert_equal(len(max_ap_payload), 254)
    var too_long_ap = List[UInt8](length=253, fill=UInt8(0x5A))
    with assert_raises():
        _ = wifi_randomized_mac_identifier_payload_serialize(
            pasn_response,
            WIFI_RANDOMIZED_MAC_STATUS_NOT_RECOGNIZED,
            Span(too_long_ap),
        )

    var group_address: List[UInt8] = [0xDB, 0, 0, 0, 0, 1]
    with assert_raises():
        _ = wifi_randomized_mac_shared_identity_from_status(
            WIFI_RANDOMIZED_MAC_STATUS_RECOGNIZED, Span(group_address)
        )
    with assert_raises():
        _ = wifi_randomized_mac_shared_identity_from_status(
            WIFI_RANDOMIZED_MAC_STATUS_NOT_APPLICABLE, Span(mutable_irm)
        )
    var action_empty = List[UInt8]()
    var action_long: List[UInt8] = [0, 1]
    var action_reserved: List[UInt8] = [2]
    with assert_raises():
        _ = wifi_randomized_mac_irm_action_parse(Span(action_empty))
    with assert_raises():
        _ = wifi_randomized_mac_irm_action_parse(Span(action_long))
    with assert_raises():
        _ = wifi_randomized_mac_irm_action_parse(Span(action_reserved))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
