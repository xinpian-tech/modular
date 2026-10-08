"""Strict per-API benchmark for the Zigbee R23.2 NWK header slice.

Each public free API owns one unique ``@no_inline`` workload and timer pair.
The mutable configuration, fixed input List, and decode Span are constructed
before preflight, warmup, or timing.  Complete owned results are retained
after the timer, while only O(1) field/endpoint fingerprints feed checksums.
Both workloads perform two deterministic preflight checks, three untimed
warmups, and nine independent timed samples.
"""

from std.benchmark import black_box, keep
from std.collections import Span
from std.time import global_perf_counter_ns
from wireless_dsp.benchmarking import (
    print_benchmark_metadata,
    report_timing_samples,
)
from wireless_dsp.wireless.zigbee import (
    ZigbeeNWKDataHeaderConfig,
    ZigbeeNWKDataHeader,
    zigbee_nwk_data_header_encode,
    zigbee_nwk_data_header_decode,
)


comptime _WARMUPS = 3
comptime _SAMPLES = 9
comptime _ENCODE_BATCH = 2048
comptime _DECODE_BATCH = 4096
comptime _SEED = UInt64(1469598103934665603)


def _mix(checksum: UInt64, value: UInt64) -> UInt64:
    return (checksum ^ value) * UInt64(1099511628211)


def _require_repeat(first: UInt64, second: UInt64) raises -> UInt64:
    var first_checksum = _mix(_SEED, first)
    var second_checksum = _mix(_SEED, second)
    if first_checksum != second_checksum:
        raise Error("Zigbee NWK header benchmark is nondeterministic")
    keep(first_checksum)
    keep(second_checksum)
    return first_checksum


@no_inline
def _encode_workload(
    config: ZigbeeNWKDataHeaderConfig, iterations: Int
) raises -> Tuple[UInt64, UInt64]:
    var result = List[UInt8]()
    var start = global_perf_counter_ns()
    for _ in range(iterations):
        result = zigbee_nwk_data_header_encode(black_box(config))
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _mix(_SEED, UInt64(len(result)))
    fingerprint = _mix(fingerprint, UInt64(result[0]))
    fingerprint = _mix(fingerprint, UInt64(result[len(result) - 1]))
    return (elapsed, fingerprint)


@no_inline
def _decode_workload(
    header: Span[UInt8, ...], iterations: Int
) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = zigbee_nwk_data_header_decode(black_box(header))
    for _ in range(1, iterations):
        result = zigbee_nwk_data_header_decode(black_box(header))
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _mix(_SEED, UInt64(result.destination_address))
    fingerprint = _mix(fingerprint, UInt64(result.source_address))
    fingerprint = _mix(fingerprint, UInt64(result.radius))
    fingerprint = _mix(fingerprint, UInt64(result.sequence_number))
    fingerprint = _mix(fingerprint, UInt64(result.discover_route))
    fingerprint = _mix(
        fingerprint, UInt64(1 if result.end_device_initiator else 0)
    )
    return (elapsed, fingerprint)


def _run_encode(config: ZigbeeNWKDataHeaderConfig) raises -> UInt64:
    var samples = List[UInt64](capacity=_SAMPLES)
    var first = _encode_workload(config, _ENCODE_BATCH)
    var second = _encode_workload(config, _ENCODE_BATCH)
    var checksum = _require_repeat(first[1], second[1])
    keep(first)
    keep(second)
    for _ in range(_WARMUPS):
        keep(_encode_workload(config, _ENCODE_BATCH))
    for _ in range(_SAMPLES):
        var sample = _encode_workload(config, _ENCODE_BATCH)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    report_timing_samples(
        "zigbee_nwk_data_header_encode",
        samples,
        _WARMUPS,
        _ENCODE_BATCH,
        "header",
    )
    keep(samples)
    return checksum


def _run_decode(header: Span[UInt8, ...]) raises -> UInt64:
    var samples = List[UInt64](capacity=_SAMPLES)
    var first = _decode_workload(header, _DECODE_BATCH)
    var second = _decode_workload(header, _DECODE_BATCH)
    var checksum = _require_repeat(first[1], second[1])
    keep(first)
    keep(second)
    for _ in range(_WARMUPS):
        keep(_decode_workload(header, _DECODE_BATCH))
    for _ in range(_SAMPLES):
        var sample = _decode_workload(header, _DECODE_BATCH)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    report_timing_samples(
        "zigbee_nwk_data_header_decode",
        samples,
        _WARMUPS,
        _DECODE_BATCH,
        "header",
    )
    keep(samples)
    return checksum


def main() raises:
    var config = ZigbeeNWKDataHeaderConfig(
        0x1234,
        0xABCD,
        5,
        0x9A,
        1,
        source_is_end_device=True,
        parent_information_nonzero=True,
    )
    var fixed_header: List[UInt8] = [
        0x48,
        0x20,
        0x34,
        0x12,
        0xCD,
        0xAB,
        0x05,
        0x9A,
    ]
    var fixed_header_span = Span(fixed_header)

    var checksum = _mix(_SEED, _run_encode(config))
    checksum = _mix(checksum, _run_decode(fixed_header_span))

    print_benchmark_metadata()
    print("zigbee_nwk_header_backend:", "scalar-cpu-reference")
    print(
        "zigbee_nwk_header_baseline:",
        "Zigbee-Specification-R23.2-fixed-8-octet-NWK-data-base-header",
    )
    keep(config)
    keep(fixed_header)
    keep(fixed_header_span)
    keep(checksum)
    print("zigbee_nwk_header_retained_checksum:", checksum)
