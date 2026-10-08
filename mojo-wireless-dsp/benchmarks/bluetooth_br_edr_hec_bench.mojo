"""Strict per-API benchmark for Bluetooth Core 6.3 BR/EDR header HEC.

The fixed ten-bit header List and Span, UAP, and received HEC are all created
before any preflight, warmup, or timed workload.  Each public API has one
unique ``@no_inline`` workload, three warmups, nine independent samples, and
two deterministic preflights.  Complete scalar results are kept after timing
and consumed with O(1) fingerprints.
"""

from std.benchmark import black_box, keep
from std.collections import Span
from std.time import global_perf_counter_ns
from wireless_dsp.benchmarking import (
    print_benchmark_metadata,
    report_timing_samples,
)
from wireless_dsp.wireless.bluetooth import (
    bluetooth_br_edr_hec_generate,
    bluetooth_br_edr_hec_check,
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
        raise Error("Bluetooth BR/EDR HEC benchmark is nondeterministic")
    keep(first_checksum)
    keep(second_checksum)
    return first_checksum


@no_inline
def _bluetooth_br_edr_hec_generate_workload(
    header_information_bits: Span[UInt8, ...],
    uap_or_dci: Int,
    iterations: Int,
) raises -> Tuple[UInt64, UInt64]:
    var result = bluetooth_br_edr_hec_generate(
        header_information_bits, uap_or_dci
    )
    var start = global_perf_counter_ns()
    for _ in range(iterations):
        result = bluetooth_br_edr_hec_generate(
            black_box(header_information_bits), black_box(uap_or_dci)
        )
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, _mix(_SEED, UInt64(result)))


@no_inline
def _bluetooth_br_edr_hec_check_workload(
    header_information_bits: Span[UInt8, ...],
    received_hec: Int,
    uap_or_dci: Int,
    iterations: Int,
) raises -> Tuple[UInt64, UInt64]:
    var result = bluetooth_br_edr_hec_check(
        header_information_bits, received_hec, uap_or_dci
    )
    var start = global_perf_counter_ns()
    for _ in range(iterations):
        result = bluetooth_br_edr_hec_check(
            black_box(header_information_bits),
            black_box(received_hec),
            black_box(uap_or_dci),
        )
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, _mix(_SEED, UInt64(1 if result else 0)))


def _run_generate(
    header_information_bits: Span[UInt8, ...], uap_or_dci: Int
) raises -> UInt64:
    var first = _bluetooth_br_edr_hec_generate_workload(
        header_information_bits, uap_or_dci, _BATCH
    )
    var second = _bluetooth_br_edr_hec_generate_workload(
        header_information_bits, uap_or_dci, _BATCH
    )
    var checksum = _require_repeat(first[1], second[1])
    keep(first)
    keep(second)
    for _ in range(_WARMUPS):
        keep(_bluetooth_br_edr_hec_generate_workload(
            header_information_bits, uap_or_dci, _BATCH
        ))
    var samples = List[UInt64](capacity=_SAMPLES)
    for _ in range(_SAMPLES):
        var sample = _bluetooth_br_edr_hec_generate_workload(
            header_information_bits, uap_or_dci, _BATCH
        )
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    report_timing_samples(
        "bluetooth_br_edr_hec_generate",
        samples,
        _WARMUPS,
        _BATCH,
        "header",
    )
    keep(samples)
    return checksum


def _run_check(
    header_information_bits: Span[UInt8, ...],
    received_hec: Int,
    uap_or_dci: Int,
) raises -> UInt64:
    var first = _bluetooth_br_edr_hec_check_workload(
        header_information_bits, received_hec, uap_or_dci, _BATCH
    )
    var second = _bluetooth_br_edr_hec_check_workload(
        header_information_bits, received_hec, uap_or_dci, _BATCH
    )
    var checksum = _require_repeat(first[1], second[1])
    keep(first)
    keep(second)
    for _ in range(_WARMUPS):
        keep(_bluetooth_br_edr_hec_check_workload(
            header_information_bits, received_hec, uap_or_dci, _BATCH
        ))
    var samples = List[UInt64](capacity=_SAMPLES)
    for _ in range(_SAMPLES):
        var sample = _bluetooth_br_edr_hec_check_workload(
            header_information_bits, received_hec, uap_or_dci, _BATCH
        )
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    report_timing_samples(
        "bluetooth_br_edr_hec_check",
        samples,
        _WARMUPS,
        _BATCH,
        "header",
    )
    keep(samples)
    return checksum


def main() raises:
    print_benchmark_metadata()
    print("bluetooth_br_edr_hec_backend:", "generic-reflected-crc-cpu")
    print(
        "bluetooth_br_edr_hec_baseline:",
        "Bluetooth-Core-6.3-Vol2-PartB-6.4.6-7.1.1",
    )

    # Part G Section 4 row: Data=0x123, UAP=0x47, HEC=0x06.
    var header_information_bits: List[UInt8] = [
        1, 1, 0, 0, 0, 1, 0, 0, 1, 0,
    ]
    var header_span = Span(header_information_bits)
    var uap_or_dci = 0x47
    var received_hec = 0x06

    var checksum = _SEED
    checksum = _mix(checksum, _run_generate(header_span, uap_or_dci))
    checksum = _mix(
        checksum, _run_check(header_span, received_hec, uap_or_dci)
    )
    keep(header_information_bits)
    keep(checksum)
    print("bluetooth_br_edr_hec_retained_checksum:", checksum)
