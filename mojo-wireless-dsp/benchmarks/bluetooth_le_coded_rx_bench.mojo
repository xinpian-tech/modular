"""Per-API CPU benchmark for the Core 6.3 LE Coded FEC RX slice.

Each public API has one unique ``@no_inline`` timed workload.  Fixed owned
fixtures, testcase identity, scalar configuration, and borrowed Spans are
constructed before timing.  The complete owned result is retained after each
timer and only an O(1) length/endpoint fingerprint feeds the reported checksum.
"""

from std.benchmark import black_box, keep
from std.collections import Span
from std.time import global_perf_counter_ns
from wireless_dsp.benchmarking import (
    print_benchmark_metadata,
    report_timing_samples,
)
from wireless_dsp.wireless.bluetooth import (
    BluetoothLECodedPacketFECDecodeReferenceResult,
    bluetooth_le_coded_packet_fec_decode_hard_reference,
    bluetooth_le_coded_pattern_demap_exact,
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


def _fingerprint_packet(
    result: BluetoothLECodedPacketFECDecodeReferenceResult,
) -> UInt64:
    var fingerprint = _mix(_SEED, UInt64(len(result.packet_symbols)))
    fingerprint = _mix(
        fingerprint, UInt64(len(result.block_one_fec_bits))
    )
    fingerprint = _mix(
        fingerprint, UInt64(len(result.block_two_fec_bits))
    )
    fingerprint = _mix(
        fingerprint,
        UInt64(len(result.decoded_whitened_pdu_and_crc_bits)),
    )
    fingerprint = _mix(
        fingerprint, UInt64(len(result.checkpoint_metadata))
    )
    fingerprint = _mix(fingerprint, UInt64(result.received_access_address))
    fingerprint = _mix(fingerprint, UInt64(result.coding_s))
    fingerprint = _mix(fingerprint, UInt64(result.pdu_octets))
    fingerprint = _mix(
        fingerprint, UInt64(1 if result.preamble_matches_exact else 0)
    )
    if len(result.packet_symbols) != 0:
        fingerprint = _mix(fingerprint, UInt64(result.packet_symbols[0]))
        fingerprint = _mix(
            fingerprint,
            UInt64(result.packet_symbols[len(result.packet_symbols) - 1]),
        )
    if len(result.decoded_whitened_pdu_and_crc_bits) != 0:
        fingerprint = _mix(
            fingerprint,
            UInt64(result.decoded_whitened_pdu_and_crc_bits[0]),
        )
        fingerprint = _mix(
            fingerprint,
            UInt64(
                result.decoded_whitened_pdu_and_crc_bits[
                    len(result.decoded_whitened_pdu_and_crc_bits) - 1
                ]
            ),
        )
    return fingerprint


def _fixture_fec(data_bits: Span[UInt8, ...]) -> List[UInt8]:
    var d1 = UInt8(0)
    var d2 = UInt8(0)
    var d3 = UInt8(0)
    var result = List[UInt8](capacity=2 * (len(data_bits) + 3))
    for step in range(len(data_bits) + 3):
        var bit = data_bits[step] if step < len(data_bits) else UInt8(0)
        result.append(bit ^ d1 ^ d2 ^ d3)
        result.append(bit ^ d2 ^ d3)
        d3 = d2
        d2 = d1
        d1 = bit
    return result^


def _fixture_map(bits: Span[UInt8, ...], coding_s: Int) -> List[UInt8]:
    var result = List[UInt8](
        capacity=len(bits) if coding_s == 2 else 4 * len(bits)
    )
    for index in range(len(bits)):
        var bit = bits[index]
        result.append(bit)
        if coding_s == 8:
            result.append(bit)
            result.append(bit ^ UInt8(1))
            result.append(bit ^ UInt8(1))
    return result^


def _append(mut output: List[UInt8], values: Span[UInt8, ...]):
    for index in range(len(values)):
        output.append(values[index])


def _make_packet_fixture(
    body_bits: Span[UInt8, ...], access_address: Int, coding_s: Int
) -> List[UInt8]:
    var block_one_data = List[UInt8](capacity=34)
    for index in range(32):
        block_one_data.append(UInt8((access_address >> index) & 1))
    block_one_data.append(UInt8(1 if coding_s == 2 else 0))
    block_one_data.append(0)
    var block_one_fec = _fixture_fec(Span(block_one_data))
    var block_one_symbols = _fixture_map(Span(block_one_fec), 8)
    var block_two_fec = _fixture_fec(body_bits)
    var block_two_symbols = _fixture_map(Span(block_two_fec), coding_s)

    var result = List[UInt8](
        capacity=80 + len(block_one_symbols) + len(block_two_symbols)
    )
    for _ in range(10):
        result.append(0)
        result.append(0)
        result.append(1)
        result.append(1)
        result.append(1)
        result.append(1)
        result.append(0)
        result.append(0)
    _append(result, Span(block_one_symbols))
    _append(result, Span(block_two_symbols))
    return result^


def _require_repeat(first: UInt64, second: UInt64) raises -> UInt64:
    if first != second:
        raise Error("Bluetooth LE Coded RX benchmark is nondeterministic")
    keep(first)
    keep(second)
    return _mix(_SEED, first)


@no_inline
def _coded_pattern_demap_exact_workload(
    mapped_symbols: Span[UInt8, ...], coding_s: Int, iterations: Int
) raises -> Tuple[UInt64, UInt64]:
    var result = List[UInt8]()
    var start = global_perf_counter_ns()
    for _ in range(iterations):
        result = bluetooth_le_coded_pattern_demap_exact(
            black_box(mapped_symbols), black_box(coding_s)
        )
    var elapsed = global_perf_counter_ns() - start
    var fingerprint = _fingerprint_bits(result)
    keep(result)
    keep(fingerprint)
    return (elapsed, fingerprint)


@no_inline
def _coded_packet_fec_decode_hard_reference_workload(
    packet_symbols: Span[UInt8, ...],
    testcase_id: StringSlice,
    iterations: Int,
) raises -> Tuple[UInt64, UInt64]:
    var result = bluetooth_le_coded_packet_fec_decode_hard_reference(
        packet_symbols, testcase_id=testcase_id
    )
    var start = global_perf_counter_ns()
    for _ in range(iterations):
        result = bluetooth_le_coded_packet_fec_decode_hard_reference(
            black_box(packet_symbols), testcase_id=testcase_id
        )
    var elapsed = global_perf_counter_ns() - start
    var fingerprint = _fingerprint_packet(result)
    keep(result)
    keep(fingerprint)
    return (elapsed, fingerprint)


def _run_pattern_demap_exact(
    mapped_symbols: Span[UInt8, ...], coding_s: Int
) raises -> UInt64:
    var first = _coded_pattern_demap_exact_workload(
        mapped_symbols, coding_s, _PATTERN_BATCH
    )
    var second = _coded_pattern_demap_exact_workload(
        mapped_symbols, coding_s, _PATTERN_BATCH
    )
    var checksum = _require_repeat(first[1], second[1])
    keep(first)
    keep(second)
    for _ in range(_WARMUPS):
        keep(
            _coded_pattern_demap_exact_workload(
                mapped_symbols, coding_s, _PATTERN_BATCH
            )
        )
    var samples = List[UInt64](capacity=_SAMPLES)
    for _ in range(_SAMPLES):
        var sample = _coded_pattern_demap_exact_workload(
            mapped_symbols, coding_s, _PATTERN_BATCH
        )
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    report_timing_samples(
        "bluetooth_le_coded_pattern_demap_exact",
        samples,
        _WARMUPS,
        _PATTERN_BATCH,
        "api_call",
    )
    keep(samples)
    return checksum


def _run_packet_fec_decode_hard_reference(
    packet_symbols: Span[UInt8, ...], testcase_id: StringSlice
) raises -> UInt64:
    var first = _coded_packet_fec_decode_hard_reference_workload(
        packet_symbols, testcase_id, _PACKET_BATCH
    )
    var second = _coded_packet_fec_decode_hard_reference_workload(
        packet_symbols, testcase_id, _PACKET_BATCH
    )
    var checksum = _require_repeat(first[1], second[1])
    keep(first)
    keep(second)
    for _ in range(_WARMUPS):
        keep(
            _coded_packet_fec_decode_hard_reference_workload(
                packet_symbols, testcase_id, _PACKET_BATCH
            )
        )
    var samples = List[UInt64](capacity=_SAMPLES)
    for _ in range(_SAMPLES):
        var sample = _coded_packet_fec_decode_hard_reference_workload(
            packet_symbols, testcase_id, _PACKET_BATCH
        )
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    report_timing_samples(
        "bluetooth_le_coded_packet_fec_decode_hard_reference",
        samples,
        _WARMUPS,
        _PACKET_BATCH,
        "api_call",
    )
    keep(samples)
    return checksum


def main() raises:
    print_benchmark_metadata()
    print("bluetooth_le_coded_rx_backend:", "scalar-cpu-hard-reference")
    print(
        "bluetooth_le_coded_rx_baseline:",
        "Bluetooth-Core-6.3-Vol6-PartB-2.2-3.3-PartC-2",
    )

    # Every owned fixture, scalar, String, and Span is complete before timing.
    var mapper_bits = List[UInt8](capacity=2048)
    for index in range(2048):
        mapper_bits.append(UInt8(((index * 11) ^ (index >> 3)) & 1))
    var mapped_symbols = _fixture_map(Span(mapper_bits), 8)
    var body = List[UInt8](capacity=64 * 8 + 24)
    for index in range(64 * 8 + 24):
        body.append(UInt8(((index * 13) ^ (index >> 2)) & 1))
    var packet = _make_packet_fixture(Span(body), 0xAA08192B, 8)
    var testcase = String("bluetooth-le-coded-rx-benchmark")
    var mapped_span = Span(mapped_symbols)
    var packet_span = Span(packet)
    var coding_s = 8

    var checksum = _SEED
    checksum = _mix(
        checksum, _run_pattern_demap_exact(mapped_span, coding_s)
    )
    checksum = _mix(
        checksum,
        _run_packet_fec_decode_hard_reference(packet_span, testcase),
    )
    keep(mapper_bits)
    keep(mapped_symbols)
    keep(body)
    keep(packet)
    keep(testcase)
    keep(checksum)
    print("bluetooth_le_coded_rx_retained_checksum:", checksum)
