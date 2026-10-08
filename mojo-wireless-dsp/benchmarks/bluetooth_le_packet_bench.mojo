"""Strict per-API benchmark for the Bluetooth Core 6.3 LE packet-bit slice.

Each public free API has one unique ``@no_inline`` workload with a complete
timer pair.  Fixed Lists, Spans, and scalar fixtures are constructed before
preflight, warmup, or timing.  Complete owned results are retained after the
timer and every field is consumed outside it; only separate O(1) endpoint
fingerprints contribute to deterministic reported checksums.  Every workload
uses two preflight checks, three warmups, and nine independent samples.
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
    BLUETOOTH_LE_PHY_2M,
    BluetoothLEUncodedPacketEncodeResult,
    BluetoothLEUncodedPacketDecodeResult,
    bluetooth_le_crc24,
    bluetooth_le_whiten_bits,
    bluetooth_le_uncoded_packet_encode,
    bluetooth_le_uncoded_packet_decode,
)


comptime _WARMUPS = 3
comptime _SAMPLES = 9
comptime _CRC_BATCH = 128
comptime _WHITEN_BATCH = 128
comptime _PACKET_BATCH = 16
comptime _SEED = UInt64(1469598103934665603)


def _mix(checksum: UInt64, value: UInt64) -> UInt64:
    return (checksum ^ value) * UInt64(1099511628211)


def _require_repeat(first: UInt64, second: UInt64) raises -> UInt64:
    var first_checksum = _mix(_SEED, first)
    var second_checksum = _mix(_SEED, second)
    if first_checksum != second_checksum:
        raise Error("Bluetooth LE packet benchmark is nondeterministic")
    keep(first_checksum)
    keep(second_checksum)
    return first_checksum


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


def _consume_encode(result: BluetoothLEUncodedPacketEncodeResult) -> UInt64:
    var checksum = _SEED
    checksum = _consume_bits(Span(result.preamble_bits), checksum)
    checksum = _consume_bits(Span(result.access_address_bits), checksum)
    checksum = _consume_bits(Span(result.pdu_bits), checksum)
    checksum = _consume_bits(Span(result.crc_bits), checksum)
    checksum = _consume_bits(Span(result.pdu_and_crc_bits), checksum)
    checksum = _consume_bits(Span(result.whitened_body_bits), checksum)
    checksum = _consume_bits(Span(result.packet_bits), checksum)
    checksum = _consume_metadata(result.checkpoint_metadata, checksum)
    return _mix(checksum, UInt64(result.crc))


def _consume_decode(result: BluetoothLEUncodedPacketDecodeResult) -> UInt64:
    var checksum = _SEED
    checksum = _consume_bits(Span(result.packet_bits), checksum)
    checksum = _consume_bits(Span(result.preamble_bits), checksum)
    checksum = _consume_bits(Span(result.access_address_bits), checksum)
    checksum = _consume_bits(Span(result.whitened_body_bits), checksum)
    checksum = _consume_bits(Span(result.pdu_and_crc_bits), checksum)
    checksum = _consume_bits(Span(result.pdu_bits), checksum)
    checksum = _consume_bits(Span(result.received_crc_bits), checksum)
    checksum = _consume_bits(Span(result.expected_crc_bits), checksum)
    checksum = _consume_metadata(result.checkpoint_metadata, checksum)
    checksum = _mix(checksum, UInt64(result.received_access_address))
    checksum = _mix(checksum, UInt64(result.received_crc))
    checksum = _mix(checksum, UInt64(result.expected_crc))
    checksum = _mix(checksum, UInt64(1 if result.preamble_ok else 0))
    checksum = _mix(checksum, UInt64(1 if result.access_address_ok else 0))
    checksum = _mix(checksum, UInt64(1 if result.crc_ok else 0))
    return _mix(checksum, UInt64(1 if result.valid else 0))


def _fingerprint_encode(
    result: BluetoothLEUncodedPacketEncodeResult
) -> UInt64:
    var fingerprint = _mix(_SEED, UInt64(len(result.packet_bits)))
    fingerprint = _mix(fingerprint, UInt64(len(result.checkpoint_metadata)))
    fingerprint = _mix(fingerprint, UInt64(result.crc))
    if len(result.packet_bits) != 0:
        fingerprint = _mix(fingerprint, UInt64(result.packet_bits[0]))
        fingerprint = _mix(
            fingerprint,
            UInt64(result.packet_bits[len(result.packet_bits) - 1]),
        )
    return fingerprint


@no_inline
def _crc24_workload(
    pdu_bits: Span[UInt8, ...], crc_init: Int, iterations: Int
) raises -> Tuple[UInt64, UInt64]:
    var result = UInt32(0)
    var start = global_perf_counter_ns()
    for _ in range(iterations):
        result = bluetooth_le_crc24(black_box(pdu_bits), black_box(crc_init))
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, UInt64(result))


@no_inline
def _whiten_bits_workload(
    bits: Span[UInt8, ...], channel_index: Int, iterations: Int
) raises -> Tuple[UInt64, UInt64]:
    var result = List[UInt8]()
    var start = global_perf_counter_ns()
    for _ in range(iterations):
        result = bluetooth_le_whiten_bits(
            black_box(bits), black_box(channel_index)
        )
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var full_output_checksum = _consume_bits(Span(result), _SEED)
    keep(full_output_checksum)
    var fingerprint = _mix(_SEED, UInt64(len(result)))
    if len(result) != 0:
        fingerprint = _mix(fingerprint, UInt64(result[0]))
        fingerprint = _mix(fingerprint, UInt64(result[len(result) - 1]))
    return (elapsed, fingerprint)


@no_inline
def _uncoded_packet_encode_workload(
    pdu_bits: Span[UInt8, ...],
    access_address: Int,
    crc_init: Int,
    channel_index: Int,
    phy: Int,
    iterations: Int,
) raises -> Tuple[UInt64, UInt64]:
    var result = bluetooth_le_uncoded_packet_encode(
        pdu_bits,
        access_address,
        crc_init,
        channel_index,
        phy,
        testcase_id="bluetooth-le-uncoded-benchmark-tx",
    )
    var start = global_perf_counter_ns()
    for _ in range(iterations):
        result = bluetooth_le_uncoded_packet_encode(
            black_box(pdu_bits),
            black_box(access_address),
            black_box(crc_init),
            black_box(channel_index),
            black_box(phy),
            testcase_id="bluetooth-le-uncoded-benchmark-tx",
        )
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var full_output_checksum = _consume_encode(result)
    keep(full_output_checksum)
    return (elapsed, _fingerprint_encode(result))


@no_inline
def _uncoded_packet_decode_workload(
    packet_bits: Span[UInt8, ...],
    expected_access_address: Int,
    crc_init: Int,
    channel_index: Int,
    phy: Int,
    iterations: Int,
) raises -> Tuple[UInt64, UInt64]:
    var result = bluetooth_le_uncoded_packet_decode(
        packet_bits,
        expected_access_address,
        crc_init,
        channel_index,
        phy,
        testcase_id="bluetooth-le-uncoded-benchmark-rx",
    )
    var start = global_perf_counter_ns()
    for _ in range(iterations):
        result = bluetooth_le_uncoded_packet_decode(
            black_box(packet_bits),
            black_box(expected_access_address),
            black_box(crc_init),
            black_box(channel_index),
            black_box(phy),
            testcase_id="bluetooth-le-uncoded-benchmark-rx",
        )
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var full_output_checksum = _consume_decode(result)
    keep(full_output_checksum)
    var fingerprint = _mix(_SEED, UInt64(len(result.pdu_bits)))
    if len(result.pdu_bits) != 0:
        fingerprint = _mix(fingerprint, UInt64(result.pdu_bits[0]))
        fingerprint = _mix(
            fingerprint,
            UInt64(result.pdu_bits[len(result.pdu_bits) - 1]),
        )
    fingerprint = _mix(fingerprint, UInt64(result.received_access_address))
    fingerprint = _mix(fingerprint, UInt64(result.received_crc))
    fingerprint = _mix(fingerprint, UInt64(result.expected_crc))
    fingerprint = _mix(fingerprint, UInt64(1 if result.preamble_ok else 0))
    fingerprint = _mix(
        fingerprint, UInt64(1 if result.access_address_ok else 0)
    )
    fingerprint = _mix(fingerprint, UInt64(1 if result.crc_ok else 0))
    fingerprint = _mix(fingerprint, UInt64(1 if result.valid else 0))
    return (elapsed, fingerprint)


def _run_crc24(pdu_bits: Span[UInt8, ...], crc_init: Int) raises -> UInt64:
    var samples = List[UInt64](capacity=_SAMPLES)
    var first = _crc24_workload(pdu_bits, crc_init, _CRC_BATCH)
    var second = _crc24_workload(pdu_bits, crc_init, _CRC_BATCH)
    var checksum = _require_repeat(first[1], second[1])
    keep(first)
    keep(second)
    for _ in range(_WARMUPS):
        keep(_crc24_workload(pdu_bits, crc_init, _CRC_BATCH))
    for _ in range(_SAMPLES):
        var sample = _crc24_workload(pdu_bits, crc_init, _CRC_BATCH)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    report_timing_samples(
        "bluetooth_le_crc24", samples, _WARMUPS, _CRC_BATCH, "api_call"
    )
    keep(samples)
    return checksum


def _run_whiten_bits(
    bits: Span[UInt8, ...], channel_index: Int
) raises -> UInt64:
    var samples = List[UInt64](capacity=_SAMPLES)
    var first = _whiten_bits_workload(bits, channel_index, _WHITEN_BATCH)
    var second = _whiten_bits_workload(bits, channel_index, _WHITEN_BATCH)
    var checksum = _require_repeat(first[1], second[1])
    keep(first)
    keep(second)
    for _ in range(_WARMUPS):
        keep(_whiten_bits_workload(bits, channel_index, _WHITEN_BATCH))
    for _ in range(_SAMPLES):
        var sample = _whiten_bits_workload(bits, channel_index, _WHITEN_BATCH)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    report_timing_samples(
        "bluetooth_le_whiten_bits",
        samples,
        _WARMUPS,
        _WHITEN_BATCH,
        "api_call",
    )
    keep(samples)
    return checksum


def _run_uncoded_packet_encode(
    pdu_bits: Span[UInt8, ...],
    access_address: Int,
    crc_init: Int,
    channel_index: Int,
    phy: Int,
) raises -> UInt64:
    var samples = List[UInt64](capacity=_SAMPLES)
    var first = _uncoded_packet_encode_workload(
        pdu_bits,
        access_address,
        crc_init,
        channel_index,
        phy,
        _PACKET_BATCH,
    )
    var second = _uncoded_packet_encode_workload(
        pdu_bits,
        access_address,
        crc_init,
        channel_index,
        phy,
        _PACKET_BATCH,
    )
    var checksum = _require_repeat(first[1], second[1])
    keep(first)
    keep(second)
    for _ in range(_WARMUPS):
        keep(
            _uncoded_packet_encode_workload(
                pdu_bits,
                access_address,
                crc_init,
                channel_index,
                phy,
                _PACKET_BATCH,
            )
        )
    for _ in range(_SAMPLES):
        var sample = _uncoded_packet_encode_workload(
            pdu_bits,
            access_address,
            crc_init,
            channel_index,
            phy,
            _PACKET_BATCH,
        )
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    report_timing_samples(
        "bluetooth_le_uncoded_packet_encode",
        samples,
        _WARMUPS,
        _PACKET_BATCH,
        "api_call",
    )
    keep(samples)
    return checksum


def _run_uncoded_packet_decode(
    packet_bits: Span[UInt8, ...],
    expected_access_address: Int,
    crc_init: Int,
    channel_index: Int,
    phy: Int,
) raises -> UInt64:
    var samples = List[UInt64](capacity=_SAMPLES)
    var first = _uncoded_packet_decode_workload(
        packet_bits,
        expected_access_address,
        crc_init,
        channel_index,
        phy,
        _PACKET_BATCH,
    )
    var second = _uncoded_packet_decode_workload(
        packet_bits,
        expected_access_address,
        crc_init,
        channel_index,
        phy,
        _PACKET_BATCH,
    )
    var checksum = _require_repeat(first[1], second[1])
    keep(first)
    keep(second)
    for _ in range(_WARMUPS):
        keep(
            _uncoded_packet_decode_workload(
                packet_bits,
                expected_access_address,
                crc_init,
                channel_index,
                phy,
                _PACKET_BATCH,
            )
        )
    for _ in range(_SAMPLES):
        var sample = _uncoded_packet_decode_workload(
            packet_bits,
            expected_access_address,
            crc_init,
            channel_index,
            phy,
            _PACKET_BATCH,
        )
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    report_timing_samples(
        "bluetooth_le_uncoded_packet_decode",
        samples,
        _WARMUPS,
        _PACKET_BATCH,
        "api_call",
    )
    keep(samples)
    return checksum


def main() raises:
    print_benchmark_metadata()
    print("bluetooth_le_packet_backend:", "scalar-cpu-reference")
    print(
        "bluetooth_le_packet_baseline:",
        "Bluetooth-Core-6.3-Vol6-PartB-2.1-3.2",
    )

    # Every owned fixture and borrowed Span is fixed before any workload.
    var pdu = List[UInt8](capacity=258 * 8)
    for index in range(258 * 8):
        pdu.append(UInt8(((index * 13) ^ (index >> 3)) & 1))
    var body = pdu.copy()
    for index in range(24):
        body.append(UInt8((index * 5 + 1) & 1))
    var access_address = 0xAA08192B
    var crc_init = 0xC4C181
    var channel_index = 39
    var phy = BLUETOOTH_LE_PHY_2M
    var packet = bluetooth_le_uncoded_packet_encode(
        Span(pdu), access_address, crc_init, channel_index, phy
    )
    var pdu_span = Span(pdu)
    var body_span = Span(body)
    var packet_span = Span(packet.packet_bits)

    var checksum = _SEED
    checksum = _mix(checksum, _run_crc24(pdu_span, crc_init))
    checksum = _mix(checksum, _run_whiten_bits(body_span, channel_index))
    checksum = _mix(
        checksum,
        _run_uncoded_packet_encode(
            pdu_span, access_address, crc_init, channel_index, phy
        ),
    )
    checksum = _mix(
        checksum,
        _run_uncoded_packet_decode(
            packet_span, access_address, crc_init, channel_index, phy
        ),
    )
    keep(pdu)
    keep(body)
    keep(packet)
    keep(checksum)
    print("bluetooth_le_packet_retained_checksum:", checksum)
