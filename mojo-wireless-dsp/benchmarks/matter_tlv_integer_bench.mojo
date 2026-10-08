"""Strict per-API benchmark for Matter 1.6 anonymous integer TLV.

Each of the four public APIs owns a unique ``@no_inline`` workload and a
complete timer pair.  Fixed encoded fixtures and their Spans are constructed
before preflight, warmup, or timing.  Complete owned results are kept after
the timer and reduced to O(1) endpoint fingerprints.  Every workload has two
determinism preflights, three warmups, and nine independent samples.
"""

from std.benchmark import black_box, keep
from std.collections import Span
from std.time import global_perf_counter_ns
from wireless_dsp.benchmarking import (
    print_benchmark_metadata,
    report_timing_samples,
)
from wireless_dsp.wireless.matter.tlv_integer import (
    MatterTLVSignedIntegerDecodeResult,
    MatterTLVUnsignedIntegerDecodeResult,
    matter_tlv_encode_signed_integer,
    matter_tlv_decode_signed_integer,
    matter_tlv_encode_unsigned_integer,
    matter_tlv_decode_unsigned_integer,
)


comptime _WARMUPS = 3
comptime _SAMPLES = 9
comptime _BATCH = 4096
comptime _SEED = UInt64(1469598103934665603)


def _mix(checksum: UInt64, value: UInt64) -> UInt64:
    return (checksum ^ value) * UInt64(1099511628211)


def _require_repeat(first: UInt64, second: UInt64) raises -> UInt64:
    var first_checksum = _mix(_SEED, first)
    var second_checksum = _mix(_SEED, second)
    if first_checksum != second_checksum:
        raise Error("Matter TLV integer benchmark is nondeterministic")
    keep(first_checksum)
    keep(second_checksum)
    return first_checksum


def _list_fingerprint(result: List[UInt8]) -> UInt64:
    var fingerprint = _mix(_SEED, UInt64(len(result)))
    if len(result) != 0:
        fingerprint = _mix(fingerprint, UInt64(result[0]))
        fingerprint = _mix(fingerprint, UInt64(result[len(result) - 1]))
    return fingerprint


@no_inline
def _matter_tlv_encode_signed_integer_workload(
    value: Int64, width: Int, iterations: Int
) raises -> Tuple[UInt64, UInt64]:
    var result = List[UInt8]()
    var start = global_perf_counter_ns()
    for _ in range(iterations):
        result = matter_tlv_encode_signed_integer(
            black_box(value), black_box(width)
        )
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, _list_fingerprint(result))


@no_inline
def _matter_tlv_decode_signed_integer_workload(
    encoded: Span[UInt8, ...], iterations: Int
) raises -> Tuple[UInt64, UInt64]:
    var result = MatterTLVSignedIntegerDecodeResult(Int64(0), 1)
    var start = global_perf_counter_ns()
    for _ in range(iterations):
        result = matter_tlv_decode_signed_integer(black_box(encoded))
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _mix(_SEED, UInt64(result.value))
    fingerprint = _mix(fingerprint, UInt64(result.width))
    return (elapsed, fingerprint)


@no_inline
def _matter_tlv_encode_unsigned_integer_workload(
    value: UInt64, width: Int, iterations: Int
) raises -> Tuple[UInt64, UInt64]:
    var result = List[UInt8]()
    var start = global_perf_counter_ns()
    for _ in range(iterations):
        result = matter_tlv_encode_unsigned_integer(
            black_box(value), black_box(width)
        )
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, _list_fingerprint(result))


@no_inline
def _matter_tlv_decode_unsigned_integer_workload(
    encoded: Span[UInt8, ...], iterations: Int
) raises -> Tuple[UInt64, UInt64]:
    var result = MatterTLVUnsignedIntegerDecodeResult(UInt64(0), 1)
    var start = global_perf_counter_ns()
    for _ in range(iterations):
        result = matter_tlv_decode_unsigned_integer(black_box(encoded))
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _mix(_SEED, result.value)
    fingerprint = _mix(fingerprint, UInt64(result.width))
    return (elapsed, fingerprint)


def _run_encode_signed(value: Int64, width: Int) raises -> UInt64:
    var samples = List[UInt64](capacity=_SAMPLES)
    var first = _matter_tlv_encode_signed_integer_workload(value, width, _BATCH)
    var second = _matter_tlv_encode_signed_integer_workload(
        value, width, _BATCH
    )
    var checksum = _require_repeat(first[1], second[1])
    keep(first)
    keep(second)
    for _ in range(_WARMUPS):
        keep(_matter_tlv_encode_signed_integer_workload(value, width, _BATCH))
    for _ in range(_SAMPLES):
        var sample = _matter_tlv_encode_signed_integer_workload(
            value, width, _BATCH
        )
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    report_timing_samples(
        "matter_tlv_encode_signed_integer",
        samples,
        _WARMUPS,
        _BATCH,
        "api_call",
    )
    keep(samples)
    return checksum


def _run_decode_signed(encoded: Span[UInt8, ...]) raises -> UInt64:
    var samples = List[UInt64](capacity=_SAMPLES)
    var first = _matter_tlv_decode_signed_integer_workload(encoded, _BATCH)
    var second = _matter_tlv_decode_signed_integer_workload(encoded, _BATCH)
    var checksum = _require_repeat(first[1], second[1])
    keep(first)
    keep(second)
    for _ in range(_WARMUPS):
        keep(_matter_tlv_decode_signed_integer_workload(encoded, _BATCH))
    for _ in range(_SAMPLES):
        var sample = _matter_tlv_decode_signed_integer_workload(encoded, _BATCH)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    report_timing_samples(
        "matter_tlv_decode_signed_integer",
        samples,
        _WARMUPS,
        _BATCH,
        "api_call",
    )
    keep(samples)
    return checksum


def _run_encode_unsigned(value: UInt64, width: Int) raises -> UInt64:
    var samples = List[UInt64](capacity=_SAMPLES)
    var first = _matter_tlv_encode_unsigned_integer_workload(
        value, width, _BATCH
    )
    var second = _matter_tlv_encode_unsigned_integer_workload(
        value, width, _BATCH
    )
    var checksum = _require_repeat(first[1], second[1])
    keep(first)
    keep(second)
    for _ in range(_WARMUPS):
        keep(_matter_tlv_encode_unsigned_integer_workload(value, width, _BATCH))
    for _ in range(_SAMPLES):
        var sample = _matter_tlv_encode_unsigned_integer_workload(
            value, width, _BATCH
        )
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    report_timing_samples(
        "matter_tlv_encode_unsigned_integer",
        samples,
        _WARMUPS,
        _BATCH,
        "api_call",
    )
    keep(samples)
    return checksum


def _run_decode_unsigned(encoded: Span[UInt8, ...]) raises -> UInt64:
    var samples = List[UInt64](capacity=_SAMPLES)
    var first = _matter_tlv_decode_unsigned_integer_workload(encoded, _BATCH)
    var second = _matter_tlv_decode_unsigned_integer_workload(encoded, _BATCH)
    var checksum = _require_repeat(first[1], second[1])
    keep(first)
    keep(second)
    for _ in range(_WARMUPS):
        keep(_matter_tlv_decode_unsigned_integer_workload(encoded, _BATCH))
    for _ in range(_SAMPLES):
        var sample = _matter_tlv_decode_unsigned_integer_workload(
            encoded, _BATCH
        )
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    report_timing_samples(
        "matter_tlv_decode_unsigned_integer",
        samples,
        _WARMUPS,
        _BATCH,
        "api_call",
    )
    keep(samples)
    return checksum


def main() raises:
    print_benchmark_metadata()
    print("matter_tlv_integer_backend:", "scalar-cpu-reference")
    print(
        "matter_tlv_integer_baseline:",
        "Matter-R1.6-Appendix-A-anonymous-integer",
    )

    # All owned fixtures and borrowed Spans exist before any workload call.
    var signed_value = Int64(-170000)
    var unsigned_value = UInt64(0xFEDCBA9876543210)
    var width = 8
    var signed_fixture: List[UInt8] = [
        0x03,
        0xF0,
        0x67,
        0xFD,
        0xFF,
        0xFF,
        0xFF,
        0xFF,
        0xFF,
    ]
    var unsigned_fixture: List[UInt8] = [
        0x07,
        0x10,
        0x32,
        0x54,
        0x76,
        0x98,
        0xBA,
        0xDC,
        0xFE,
    ]
    var signed_span = Span(signed_fixture)
    var unsigned_span = Span(unsigned_fixture)

    var checksum = _SEED
    checksum = _mix(checksum, _run_encode_signed(signed_value, width))
    checksum = _mix(checksum, _run_decode_signed(signed_span))
    checksum = _mix(checksum, _run_encode_unsigned(unsigned_value, width))
    checksum = _mix(checksum, _run_decode_unsigned(unsigned_span))
    keep(signed_fixture)
    keep(unsigned_fixture)
    keep(checksum)
    print("matter_tlv_integer_retained_checksum:", checksum)
