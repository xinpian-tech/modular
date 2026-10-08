"""Attributable CPU timings for bounded IEEE 802.11bh identity fields.

Every public algorithm has a separate ``@no_inline`` batched workload, three
untimed warmups, and nine independent samples.  Configurations, addresses,
identifiers, serialized payloads, action fields, selector tables, and their
Span views are all constructed before timing.  Complete returned objects are
retained while an O(1) field/endpoint fingerprint feeds the deterministic
checksum; no dispatcher is timed.
"""

from std.benchmark import black_box, keep
from std.collections import Span
from std.time import global_perf_counter_ns
from wireless_dsp.benchmarking import (
    print_benchmark_metadata,
    report_timing_samples,
)
from wireless_dsp.wireless.wifi.randomized_mac import (
    WIFI_RANDOMIZED_MAC_IDENTIFIER_DEVICE_ID,
    WIFI_RANDOMIZED_MAC_IDENTIFIER_IRM,
    WIFI_RANDOMIZED_MAC_IDENTIFIER_PASN_ID,
    WIFI_RANDOMIZED_MAC_SENDER_AP,
    WIFI_RANDOMIZED_MAC_STATUS_RECOGNIZED,
    WifiRandomizedMacIdentifierConfig,
    wifi_randomized_mac_is_local_individual,
    wifi_randomized_mac_identifier_status_decode,
    wifi_randomized_mac_identifier_payload_serialize,
    wifi_randomized_mac_identifier_payload_parse,
    wifi_randomized_mac_shared_identity_from_status,
    wifi_randomized_mac_irm_action_serialize,
    wifi_randomized_mac_irm_action_parse,
)


comptime _WARMUPS = 3
comptime _SAMPLES = 9
comptime _SCALAR_BATCH = 8192
comptime _PAYLOAD_BATCH = 1024
comptime _STATE_BATCH = 4096


def _mix(checksum: UInt64, value: Int) -> UInt64:
    return (checksum ^ UInt64(value + 4096)) * UInt64(1099511628211)


@no_inline
def _local_individual_workload(
    iterations: Int, address: Span[UInt8, ...]
) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for operation in range(iterations):
        var result = wifi_randomized_mac_is_local_individual(address)
        checksum = _mix(checksum, (1 if result else 0) + operation)
        keep(result)
    return checksum


@no_inline
def _status_decode_workload(
    iterations: Int,
    kinds: Span[Int, ...],
    statuses: Span[Int, ...],
) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for operation in range(iterations):
        var index = black_box(operation % len(kinds))
        var fields = wifi_randomized_mac_identifier_status_decode(
            kinds[index], statuses[index]
        )
        checksum = _mix(checksum, fields.status + operation)
        checksum = _mix(checksum, 1 if fields.recognized else 0)
        checksum = _mix(checksum, 1 if fields.not_recognized else 0)
        checksum = _mix(checksum, 1 if fields.not_applicable else 0)
        keep(fields)
    return checksum


@no_inline
def _payload_serialize_workload(
    iterations: Int,
    config: WifiRandomizedMacIdentifierConfig,
    identifier: Span[UInt8, ...],
) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for operation in range(iterations):
        var payload = wifi_randomized_mac_identifier_payload_serialize(
            config, WIFI_RANDOMIZED_MAC_STATUS_RECOGNIZED, identifier
        )
        checksum = _mix(checksum, len(payload) + operation)
        checksum = _mix(checksum, Int(payload[0]))
        checksum = _mix(checksum, Int(payload[len(payload) - 1]))
        keep(payload)
    return checksum


@no_inline
def _payload_parse_workload(
    iterations: Int,
    config: WifiRandomizedMacIdentifierConfig,
    payload: Span[UInt8, ...],
) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for operation in range(iterations):
        var fields = wifi_randomized_mac_identifier_payload_parse(
            config, payload
        )
        checksum = _mix(checksum, fields.identifier_kind)
        checksum = _mix(checksum, fields.sender_role)
        checksum = _mix(checksum, 1 if fields.status_present else 0)
        checksum = _mix(checksum, fields.status)
        checksum = _mix(
            checksum, fields.identifier_length_octets + operation
        )
        checksum = _mix(checksum, Int(fields.identifier[0]))
        checksum = _mix(
            checksum, Int(fields.identifier[len(fields.identifier) - 1])
        )
        keep(fields)
    return checksum


@no_inline
def _shared_identity_workload(
    iterations: Int,
    statuses: Span[Int, ...],
    address2: Span[UInt8, ...],
) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for operation in range(iterations):
        var status = statuses[black_box(operation % len(statuses))]
        var state = wifi_randomized_mac_shared_identity_from_status(
            status, address2
        )
        checksum = _mix(checksum, state.response_status + operation)
        checksum = _mix(
            checksum, 1 if state.shared_identity_present else 0
        )
        checksum = _mix(checksum, len(state.bound_address2))
        if len(state.bound_address2) != 0:
            checksum = _mix(checksum, Int(state.bound_address2[0]))
            checksum = _mix(
                checksum,
                Int(state.bound_address2[len(state.bound_address2) - 1]),
            )
        keep(state)
    return checksum


@no_inline
def _irm_action_serialize_workload(
    iterations: Int, actions: Span[Int, ...]
) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for operation in range(iterations):
        var action = wifi_randomized_mac_irm_action_serialize(
            actions[black_box(operation % len(actions))]
        )
        checksum = _mix(checksum, Int(action) + operation)
        keep(action)
    return checksum


@no_inline
def _irm_action_parse_workload(
    iterations: Int, field: Span[UInt8, ...]
) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for operation in range(iterations):
        var action = wifi_randomized_mac_irm_action_parse(field)
        checksum = _mix(checksum, action.action + operation)
        checksum = _mix(checksum, 1 if action.duplicate_irm else 0)
        checksum = _mix(checksum, 1 if action.new_irm else 0)
        keep(action)
    return checksum


def main() raises:
    var local_address: List[UInt8] = [0xDA, 0x7A, 0x11, 0x22, 0x33, 0x44]
    var identifier = List[UInt8](capacity=32)
    for index in range(32):
        identifier.append(UInt8((index * 37 + 19) & 0xFF))
    var pasn_ap = WifiRandomizedMacIdentifierConfig(
        WIFI_RANDOMIZED_MAC_IDENTIFIER_PASN_ID,
        WIFI_RANDOMIZED_MAC_SENDER_AP,
    )
    var parser_input = wifi_randomized_mac_identifier_payload_serialize(
        pasn_ap,
        WIFI_RANDOMIZED_MAC_STATUS_RECOGNIZED,
        Span(identifier),
    )
    var status_kinds: List[Int] = [
        WIFI_RANDOMIZED_MAC_IDENTIFIER_DEVICE_ID,
        WIFI_RANDOMIZED_MAC_IDENTIFIER_DEVICE_ID,
        WIFI_RANDOMIZED_MAC_IDENTIFIER_DEVICE_ID,
        WIFI_RANDOMIZED_MAC_IDENTIFIER_IRM,
        WIFI_RANDOMIZED_MAC_IDENTIFIER_IRM,
        WIFI_RANDOMIZED_MAC_IDENTIFIER_PASN_ID,
        WIFI_RANDOMIZED_MAC_IDENTIFIER_PASN_ID,
        WIFI_RANDOMIZED_MAC_IDENTIFIER_PASN_ID,
    ]
    var status_values: List[Int] = [0, 1, 2, 0, 1, 0, 1, 2]
    var transition_statuses: List[Int] = [0, 1]
    var actions: List[Int] = [0, 1]
    var action_field: List[UInt8] = [1]
    var local_address_span = Span(local_address)
    var identifier_span = Span(identifier)
    var parser_input_span = Span(parser_input)
    var status_kinds_span = Span(status_kinds)
    var status_values_span = Span(status_values)
    var transition_statuses_span = Span(transition_statuses)
    var actions_span = Span(actions)
    var action_field_span = Span(action_field)

    for _ in range(_WARMUPS):
        keep(_local_individual_workload(
            _SCALAR_BATCH, local_address_span
        ))
        keep(_status_decode_workload(
            _SCALAR_BATCH, status_kinds_span, status_values_span
        ))
        keep(_payload_serialize_workload(
            _PAYLOAD_BATCH, pasn_ap, identifier_span
        ))
        keep(_payload_parse_workload(
            _PAYLOAD_BATCH, pasn_ap, parser_input_span
        ))
        keep(_shared_identity_workload(
            _STATE_BATCH, transition_statuses_span, local_address_span
        ))
        keep(_irm_action_serialize_workload(
            _SCALAR_BATCH, actions_span
        ))
        keep(_irm_action_parse_workload(
            _SCALAR_BATCH, action_field_span
        ))

    var address_samples = List[UInt64](capacity=_SAMPLES)
    var status_samples = List[UInt64](capacity=_SAMPLES)
    var serialize_samples = List[UInt64](capacity=_SAMPLES)
    var parse_samples = List[UInt64](capacity=_SAMPLES)
    var state_samples = List[UInt64](capacity=_SAMPLES)
    var action_serialize_samples = List[UInt64](capacity=_SAMPLES)
    var action_parse_samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)

    for sample in range(_SAMPLES):
        var start = global_perf_counter_ns()
        var address_checksum = _local_individual_workload(
            _SCALAR_BATCH, local_address_span
        )
        address_samples.append(global_perf_counter_ns() - start)
        checksum = _mix(
            checksum, Int(address_checksum & UInt64(Int.MAX)) + sample
        )
        keep(address_checksum)

        start = global_perf_counter_ns()
        var status_checksum = _status_decode_workload(
            _SCALAR_BATCH, status_kinds_span, status_values_span
        )
        status_samples.append(global_perf_counter_ns() - start)
        checksum = _mix(
            checksum, Int(status_checksum & UInt64(Int.MAX)) + sample
        )
        keep(status_checksum)

        start = global_perf_counter_ns()
        var serialize_checksum = _payload_serialize_workload(
            _PAYLOAD_BATCH, pasn_ap, identifier_span
        )
        serialize_samples.append(global_perf_counter_ns() - start)
        checksum = _mix(
            checksum, Int(serialize_checksum & UInt64(Int.MAX)) + sample
        )
        keep(serialize_checksum)

        start = global_perf_counter_ns()
        var parse_checksum = _payload_parse_workload(
            _PAYLOAD_BATCH, pasn_ap, parser_input_span
        )
        parse_samples.append(global_perf_counter_ns() - start)
        checksum = _mix(
            checksum, Int(parse_checksum & UInt64(Int.MAX)) + sample
        )
        keep(parse_checksum)

        start = global_perf_counter_ns()
        var state_checksum = _shared_identity_workload(
            _STATE_BATCH, transition_statuses_span, local_address_span
        )
        state_samples.append(global_perf_counter_ns() - start)
        checksum = _mix(
            checksum, Int(state_checksum & UInt64(Int.MAX)) + sample
        )
        keep(state_checksum)

        start = global_perf_counter_ns()
        var action_serialize_checksum = _irm_action_serialize_workload(
            _SCALAR_BATCH, actions_span
        )
        action_serialize_samples.append(global_perf_counter_ns() - start)
        checksum = _mix(
            checksum,
            Int(action_serialize_checksum & UInt64(Int.MAX)) + sample,
        )
        keep(action_serialize_checksum)

        start = global_perf_counter_ns()
        var action_parse_checksum = _irm_action_parse_workload(
            _SCALAR_BATCH, action_field_span
        )
        action_parse_samples.append(global_perf_counter_ns() - start)
        checksum = _mix(
            checksum, Int(action_parse_checksum & UInt64(Int.MAX)) + sample
        )
        keep(action_parse_checksum)

    print_benchmark_metadata()
    print("wifi_randomized_mac_backend:", "scalar-cpu-bounded-reference")
    print(
        "wifi_randomized_mac_baseline:",
        "IEEE-802.11bh-2024-identity-field-and-state-subset",
    )
    report_timing_samples(
        "wifi_randomized_mac_is_local_individual",
        address_samples,
        _WARMUPS,
        _SCALAR_BATCH,
        "address",
    )
    report_timing_samples(
        "wifi_randomized_mac_identifier_status_decode",
        status_samples,
        _WARMUPS,
        _SCALAR_BATCH,
        "status",
    )
    report_timing_samples(
        "wifi_randomized_mac_identifier_payload_serialize",
        serialize_samples,
        _WARMUPS,
        _PAYLOAD_BATCH,
        "payload",
    )
    report_timing_samples(
        "wifi_randomized_mac_identifier_payload_parse",
        parse_samples,
        _WARMUPS,
        _PAYLOAD_BATCH,
        "payload",
    )
    report_timing_samples(
        "wifi_randomized_mac_shared_identity_from_status",
        state_samples,
        _WARMUPS,
        _STATE_BATCH,
        "state_transition",
    )
    report_timing_samples(
        "wifi_randomized_mac_irm_action_serialize",
        action_serialize_samples,
        _WARMUPS,
        _SCALAR_BATCH,
        "action",
    )
    report_timing_samples(
        "wifi_randomized_mac_irm_action_parse",
        action_parse_samples,
        _WARMUPS,
        _SCALAR_BATCH,
        "action",
    )
    keep(checksum)
    print("wifi_randomized_mac_retained_checksum:", checksum)
