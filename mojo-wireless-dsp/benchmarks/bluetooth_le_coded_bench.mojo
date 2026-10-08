"""Strict per-API benchmark for the Core 6.3 LE Coded TX slice.

Each public API has one unique ``@no_inline`` timed workload.  Fixed owned
fixtures, scalar configuration, and borrowed Spans are constructed before
preflight, warmup, or timing.  Complete owned results are retained and fully
consumed after the timer, while deterministic reported checksums use separate
O(1) length/endpoint fingerprints.  Each workload has two preflight runs,
three warmups, and nine reported samples.
"""

from std.benchmark import black_box, keep
from std.collections import Span
from std.time import global_perf_counter_ns
from wireless_dsp.benchmarking import (
    print_benchmark_metadata,
    report_timing_samples,
)
from wireless_dsp.testing import CheckpointMetadata
from wireless_dsp.wireless.bluetooth import (
    BluetoothLECodedPacketEncodeResult,
    bluetooth_le_coded_pattern_map,
    bluetooth_le_coded_packet_encode,
)


comptime _WARMUPS = 3
comptime _SAMPLES = 9
comptime _PATTERN_BATCH = 64
comptime _PACKET_BATCH = 8
comptime _SEED = UInt64(1469598103934665603)


def _mix(checksum: UInt64, value: UInt64) -> UInt64:
    return (checksum ^ value) * UInt64(1099511628211)


def _fingerprint_bits(result: List[UInt8]) -> UInt64:
    var fingerprint = _mix(_SEED, UInt64(len(result)))
    if len(result) != 0:
        fingerprint = _mix(fingerprint, UInt64(result[0]))
        fingerprint = _mix(fingerprint, UInt64(result[len(result) - 1]))
    return fingerprint


def _consume_bits(bits: Span[UInt8, ...], checksum: UInt64) -> UInt64:
    var result = _mix(checksum, UInt64(len(bits)))
    for index in range(len(bits)):
        result = _mix(result, UInt64(bits[index]) + UInt64(3 * index))
    return result


def _consume_text(value: StringSlice, checksum: UInt64) -> UInt64:
    var result = _mix(checksum, UInt64(value.byte_length()))
    for index in range(value.byte_length()):
        result = _mix(result, UInt64(ord(value[byte=index])))
    return result


def _consume_metadata(
    metadata: List[CheckpointMetadata], checksum: UInt64
) -> UInt64:
    var result = _mix(checksum, UInt64(len(metadata)))
    for index in range(len(metadata)):
        result = _consume_text(metadata[index].testcase_id, result)
        result = _consume_text(metadata[index].stage, result)
        result = _consume_text(metadata[index].dtype, result)
        result = _consume_text(metadata[index].shape, result)
        result = _consume_text(metadata[index].stride, result)
        result = _consume_text(metadata[index].q_format, result)
        result = _consume_text(metadata[index].layout, result)
        result = _mix(result, UInt64(metadata[index].version))
        result = _mix(
            result, UInt64(1 if metadata[index].scale == 1.0 else 0)
        )
    return result


def _consume_packet(result: BluetoothLECodedPacketEncodeResult) -> UInt64:
    var checksum = _SEED
    checksum = _consume_bits(Span(result.preamble_symbols), checksum)
    checksum = _consume_bits(Span(result.access_address_bits), checksum)
    checksum = _consume_bits(Span(result.coding_indicator_bits), checksum)
    checksum = _consume_bits(Span(result.term1_bits), checksum)
    checksum = _consume_bits(Span(result.block_one_input_bits), checksum)
    checksum = _consume_bits(Span(result.block_one_fec_bits), checksum)
    checksum = _consume_bits(Span(result.block_one_mapped_symbols), checksum)
    checksum = _consume_bits(Span(result.pdu_bits), checksum)
    checksum = _consume_bits(Span(result.crc_bits), checksum)
    checksum = _consume_bits(Span(result.pdu_and_crc_bits), checksum)
    checksum = _consume_bits(
        Span(result.whitened_pdu_and_crc_bits), checksum
    )
    checksum = _consume_bits(Span(result.term2_bits), checksum)
    checksum = _consume_bits(Span(result.block_two_input_bits), checksum)
    checksum = _consume_bits(Span(result.block_two_fec_bits), checksum)
    checksum = _consume_bits(Span(result.block_two_mapped_symbols), checksum)
    checksum = _consume_bits(Span(result.packet_symbols), checksum)
    checksum = _consume_metadata(result.checkpoint_metadata, checksum)
    checksum = _mix(checksum, UInt64(result.crc))
    return _mix(checksum, UInt64(result.coding_s))


def _fingerprint_packet(
    result: BluetoothLECodedPacketEncodeResult
) -> UInt64:
    var fingerprint = _mix(_SEED, UInt64(len(result.packet_symbols)))
    fingerprint = _mix(fingerprint, UInt64(len(result.checkpoint_metadata)))
    fingerprint = _mix(fingerprint, UInt64(result.crc))
    fingerprint = _mix(fingerprint, UInt64(result.coding_s))
    if len(result.packet_symbols) != 0:
        fingerprint = _mix(fingerprint, UInt64(result.packet_symbols[0]))
        fingerprint = _mix(
            fingerprint,
            UInt64(result.packet_symbols[len(result.packet_symbols) - 1]),
        )
    return fingerprint


def _require_repeat(first: UInt64, second: UInt64) raises -> UInt64:
    if first != second:
        raise Error("Bluetooth LE Coded benchmark is nondeterministic")
    keep(first)
    keep(second)
    return _mix(_SEED, first)


@no_inline
def _coded_pattern_map_workload(
    encoded_bits: Span[UInt8, ...], coding_s: Int, iterations: Int
) raises -> Tuple[UInt64, UInt64]:
    var result = List[UInt8]()
    var start = global_perf_counter_ns()
    for _ in range(iterations):
        result = bluetooth_le_coded_pattern_map(
            black_box(encoded_bits), black_box(coding_s)
        )
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var full_output_checksum = _consume_bits(Span(result), _SEED)
    keep(full_output_checksum)
    return (elapsed, _fingerprint_bits(result))


@no_inline
def _coded_packet_encode_workload(
    pdu_bits: Span[UInt8, ...],
    access_address: Int,
    crc_init: Int,
    channel_index: Int,
    coding_s: Int,
    iterations: Int,
) raises -> Tuple[UInt64, UInt64]:
    var result = bluetooth_le_coded_packet_encode(
        pdu_bits,
        access_address,
        crc_init,
        channel_index,
        coding_s,
        testcase_id="bluetooth-le-coded-benchmark-tx",
    )
    var start = global_perf_counter_ns()
    for _ in range(iterations):
        result = bluetooth_le_coded_packet_encode(
            black_box(pdu_bits),
            black_box(access_address),
            black_box(crc_init),
            black_box(channel_index),
            black_box(coding_s),
            testcase_id="bluetooth-le-coded-benchmark-tx",
        )
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var full_output_checksum = _consume_packet(result)
    keep(full_output_checksum)
    return (elapsed, _fingerprint_packet(result))


def _run_coded_pattern_map(
    encoded_bits: Span[UInt8, ...], coding_s: Int
) raises -> UInt64:
    var first = _coded_pattern_map_workload(
        encoded_bits, coding_s, _PATTERN_BATCH
    )
    var second = _coded_pattern_map_workload(
        encoded_bits, coding_s, _PATTERN_BATCH
    )
    var checksum = _require_repeat(first[1], second[1])
    keep(first)
    keep(second)
    for _ in range(_WARMUPS):
        keep(
            _coded_pattern_map_workload(
                encoded_bits, coding_s, _PATTERN_BATCH
            )
        )
    var samples = List[UInt64](capacity=_SAMPLES)
    for _ in range(_SAMPLES):
        var sample = _coded_pattern_map_workload(
            encoded_bits, coding_s, _PATTERN_BATCH
        )
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    report_timing_samples(
        "bluetooth_le_coded_pattern_map",
        samples,
        _WARMUPS,
        _PATTERN_BATCH,
        "api_call",
    )
    keep(samples)
    return checksum


def _run_coded_packet_encode(
    pdu_bits: Span[UInt8, ...],
    access_address: Int,
    crc_init: Int,
    channel_index: Int,
    coding_s: Int,
) raises -> UInt64:
    var first = _coded_packet_encode_workload(
        pdu_bits,
        access_address,
        crc_init,
        channel_index,
        coding_s,
        _PACKET_BATCH,
    )
    var second = _coded_packet_encode_workload(
        pdu_bits,
        access_address,
        crc_init,
        channel_index,
        coding_s,
        _PACKET_BATCH,
    )
    var checksum = _require_repeat(first[1], second[1])
    keep(first)
    keep(second)
    for _ in range(_WARMUPS):
        keep(
            _coded_packet_encode_workload(
                pdu_bits,
                access_address,
                crc_init,
                channel_index,
                coding_s,
                _PACKET_BATCH,
            )
        )
    var samples = List[UInt64](capacity=_SAMPLES)
    for _ in range(_SAMPLES):
        var sample = _coded_packet_encode_workload(
            pdu_bits,
            access_address,
            crc_init,
            channel_index,
            coding_s,
            _PACKET_BATCH,
        )
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    report_timing_samples(
        "bluetooth_le_coded_packet_encode",
        samples,
        _WARMUPS,
        _PACKET_BATCH,
        "api_call",
    )
    keep(samples)
    return checksum


def main() raises:
    print_benchmark_metadata()
    print("bluetooth_le_coded_backend:", "scalar-cpu-reference")
    print(
        "bluetooth_le_coded_baseline:",
        "Bluetooth-Core-6.3-Vol6-PartB-2.2-3.3",
    )

    # All owned fixtures and borrowed views are complete before workloads.
    var mapper_input = List[UInt8](capacity=4166)
    for index in range(4166):
        mapper_input.append(UInt8(((index * 11) ^ (index >> 2)) & 1))
    var pdu = List[UInt8](capacity=257 * 8)
    for index in range(257 * 8):
        pdu.append(UInt8(((index * 13) ^ (index >> 3)) & 1))
    var mapper_span = Span(mapper_input)
    var pdu_span = Span(pdu)
    var access_address = 0xAA08192B
    var crc_init = 0xC4C181
    var channel_index = 39
    var coding_s = 8

    var checksum = _SEED
    checksum = _mix(
        checksum, _run_coded_pattern_map(mapper_span, coding_s)
    )
    checksum = _mix(
        checksum,
        _run_coded_packet_encode(
            pdu_span,
            access_address,
            crc_init,
            channel_index,
            coding_s,
        ),
    )
    keep(mapper_input)
    keep(pdu)
    keep(checksum)
    print("bluetooth_le_coded_retained_checksum:", checksum)
