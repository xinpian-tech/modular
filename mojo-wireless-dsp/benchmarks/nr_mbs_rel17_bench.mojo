"""Attributable CPU timings for bounded Rel-17 NR MBS arithmetic."""

from std.benchmark import black_box, keep
from std.time import global_perf_counter_ns
from wireless_dsp.benchmarking import (
    print_benchmark_metadata,
    report_timing_samples,
)
from wireless_dsp.wireless.nr.mbs_rel17 import (
    NR_MBS_BROADCAST_CFR_ABSENT_CORESET0,
    NR_MBS_BROADCAST_CFR_SAME_AS_INITIAL_BWP,
    NR_MBS_BROADCAST_CFR_EXPLICIT_RIV,
    nr_mbs_rel17_multicast_cfr,
    nr_mbs_rel17_broadcast_cfr,
    nr_mbs_rel17_dci_4_0_payload_bits,
    nr_mbs_rel17_dci_4_1_payload_bits,
    nr_mbs_rel17_mcch_change_notification,
    nr_mbs_rel17_nack_only_pucch_resource,
    nr_mbs_rel17_sps_occasion_slot,
    nr_mbs_rel17_sps_harq_process_id,
)


comptime _WARMUPS = 3
comptime _SAMPLES = 9
comptime _BATCH = 4096


def _mix(checksum: UInt64, value: Int) -> UInt64:
    return (checksum ^ UInt64(value + 1)) * UInt64(1099511628211)


@no_inline
def _multicast_cfr_workload(iterations: Int, salt: Int) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for operation in range(iterations):
        var explicit = ((operation + salt) & 1) == 0
        # RIV 12957 encodes start=32, length=48 in the 275-RB domain.
        var result = nr_mbs_rel17_multicast_cfr(
            black_box(explicit),
            black_box(12957 if explicit else 0),
            black_box(0),
            black_box(275),
        )
        checksum = _mix(
            checksum, result.start_prb + result.size_prbs + operation
        )
        keep(result)
    return checksum


@no_inline
def _broadcast_cfr_workload(iterations: Int, salt: Int) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for operation in range(iterations):
        var source = (operation + salt) % 3
        var riv = 21757 if (
            source == NR_MBS_BROADCAST_CFR_EXPLICIT_RIV
        ) else 0
        var result = nr_mbs_rel17_broadcast_cfr(
            black_box(source),
            black_box(riv),
            black_box(40),
            black_box(48),
            black_box(48),
            black_box(24),
        )
        checksum = _mix(
            checksum, result.start_prb + result.size_prbs + operation
        )
        keep(result)
    return checksum


@no_inline
def _dci_4_0_workload(iterations: Int, salt: Int) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for operation in range(iterations):
        var configured = ((operation + salt) & 1) == 0
        var bits = nr_mbs_rel17_dci_4_0_payload_bits(
            black_box(configured),
            black_box(1 + ((operation + salt) % 275) if configured else 0),
            black_box(106),
        )
        checksum = _mix(checksum, bits + operation)
    return checksum


@no_inline
def _dci_4_1_workload(iterations: Int, salt: Int) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for operation in range(iterations):
        var configured = ((operation + salt) & 1) != 0
        var bits = nr_mbs_rel17_dci_4_1_payload_bits(
            black_box(configured),
            black_box(1 + ((operation + salt) % 275) if configured else 0),
            black_box(106),
        )
        checksum = _mix(checksum, bits + operation)
    return checksum


@no_inline
def _mcch_notification_workload(iterations: Int, salt: Int) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for operation in range(iterations):
        var result = nr_mbs_rel17_mcch_change_notification(
            black_box((operation + salt) & 3), black_box(0xFFFD)
        )
        var encoded = (
            (2 if result.new_service_started else 0)
            + (1 if result.other_mcch_information_modified else 0)
        )
        checksum = _mix(checksum, encoded + operation)
        keep(result)
    return checksum


@no_inline
def _nack_only_pucch_workload(
    iterations: Int, salt: Int, bits: Span[Int, ...]
) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for operation in range(iterations):
        var resource = nr_mbs_rel17_nack_only_pucch_resource(
            black_box(bits), black_box(True)
        )
        checksum = _mix(checksum, resource + operation + (salt & 1))
    return checksum


@no_inline
def _sps_occasion_workload(iterations: Int, salt: Int) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for operation in range(iterations):
        var slot = nr_mbs_rel17_sps_occasion_slot(
            black_box((operation + salt) & 1023),
            black_box((operation + salt) % 80),
            black_box(operation + salt),
            black_box(80),
            black_box(8),
        )
        checksum = _mix(checksum, slot + operation)
    return checksum


@no_inline
def _sps_harq_workload(iterations: Int, salt: Int) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for operation in range(iterations):
        var process = nr_mbs_rel17_sps_harq_process_id(
            black_box((operation + salt) & 1023),
            black_box((operation + salt) % 80),
            black_box(80),
            black_box(8),
            black_box(8),
            black_box(8),
        )
        checksum = _mix(checksum, process + operation)
    return checksum


def main() raises:
    var nack_bits: List[Int] = [1, 0, 1, 0]
    for warmup in range(_WARMUPS):
        var salt = (warmup + 1) * 7919
        keep(_multicast_cfr_workload(_BATCH, salt))
        keep(_broadcast_cfr_workload(_BATCH, salt))
        keep(_dci_4_0_workload(_BATCH, salt))
        keep(_dci_4_1_workload(_BATCH, salt))
        keep(_mcch_notification_workload(_BATCH, salt))
        keep(_nack_only_pucch_workload(_BATCH, salt, nack_bits))
        keep(_sps_occasion_workload(_BATCH, salt))
        keep(_sps_harq_workload(_BATCH, salt))

    var multicast_samples = List[UInt64](capacity=_SAMPLES)
    var broadcast_samples = List[UInt64](capacity=_SAMPLES)
    var dci_4_0_samples = List[UInt64](capacity=_SAMPLES)
    var dci_4_1_samples = List[UInt64](capacity=_SAMPLES)
    var mcch_samples = List[UInt64](capacity=_SAMPLES)
    var nack_samples = List[UInt64](capacity=_SAMPLES)
    var occasion_samples = List[UInt64](capacity=_SAMPLES)
    var harq_samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for sample in range(_SAMPLES):
        var salt = (sample + 1) * 104729
        var start = global_perf_counter_ns()
        var value = _multicast_cfr_workload(_BATCH, salt)
        multicast_samples.append(global_perf_counter_ns() - start)
        checksum = _mix(checksum, Int(value & UInt64(0x7FFFFFFF)))
        keep(value)

        start = global_perf_counter_ns()
        value = _broadcast_cfr_workload(_BATCH, salt)
        broadcast_samples.append(global_perf_counter_ns() - start)
        checksum = _mix(checksum, Int(value & UInt64(0x7FFFFFFF)))
        keep(value)

        start = global_perf_counter_ns()
        value = _dci_4_0_workload(_BATCH, salt)
        dci_4_0_samples.append(global_perf_counter_ns() - start)
        checksum = _mix(checksum, Int(value & UInt64(0x7FFFFFFF)))
        keep(value)

        start = global_perf_counter_ns()
        value = _dci_4_1_workload(_BATCH, salt)
        dci_4_1_samples.append(global_perf_counter_ns() - start)
        checksum = _mix(checksum, Int(value & UInt64(0x7FFFFFFF)))
        keep(value)

        start = global_perf_counter_ns()
        value = _mcch_notification_workload(_BATCH, salt)
        mcch_samples.append(global_perf_counter_ns() - start)
        checksum = _mix(checksum, Int(value & UInt64(0x7FFFFFFF)))
        keep(value)

        start = global_perf_counter_ns()
        value = _nack_only_pucch_workload(_BATCH, salt, nack_bits)
        nack_samples.append(global_perf_counter_ns() - start)
        checksum = _mix(checksum, Int(value & UInt64(0x7FFFFFFF)))
        keep(value)

        start = global_perf_counter_ns()
        value = _sps_occasion_workload(_BATCH, salt)
        occasion_samples.append(global_perf_counter_ns() - start)
        checksum = _mix(checksum, Int(value & UInt64(0x7FFFFFFF)))
        keep(value)

        start = global_perf_counter_ns()
        value = _sps_harq_workload(_BATCH, salt)
        harq_samples.append(global_perf_counter_ns() - start)
        checksum = _mix(checksum, Int(value & UInt64(0x7FFFFFFF)))
        keep(value)

    print_benchmark_metadata()
    print("nr_mbs_rel17_backend:", "scalar-cpu-reference")
    print(
        "nr_mbs_rel17_baseline:",
        "NR_MBS-RP-220428-38.211-38.212-38.213-38.214-38.321-38.331",
    )
    report_timing_samples(
        "nr_mbs_rel17_multicast_cfr",
        multicast_samples,
        _WARMUPS,
        _BATCH,
        "configuration",
    )
    report_timing_samples(
        "nr_mbs_rel17_broadcast_cfr",
        broadcast_samples,
        _WARMUPS,
        _BATCH,
        "configuration",
    )
    report_timing_samples(
        "nr_mbs_rel17_dci_4_0_payload_bits",
        dci_4_0_samples,
        _WARMUPS,
        _BATCH,
        "payload",
    )
    report_timing_samples(
        "nr_mbs_rel17_dci_4_1_payload_bits",
        dci_4_1_samples,
        _WARMUPS,
        _BATCH,
        "payload",
    )
    report_timing_samples(
        "nr_mbs_rel17_mcch_change_notification",
        mcch_samples,
        _WARMUPS,
        _BATCH,
        "bitmap",
    )
    report_timing_samples(
        "nr_mbs_rel17_nack_only_pucch_resource",
        nack_samples,
        _WARMUPS,
        _BATCH,
        "selection",
    )
    report_timing_samples(
        "nr_mbs_rel17_sps_occasion_slot",
        occasion_samples,
        _WARMUPS,
        _BATCH,
        "occurrence",
    )
    report_timing_samples(
        "nr_mbs_rel17_sps_harq_process_id",
        harq_samples,
        _WARMUPS,
        _BATCH,
        "assignment",
    )
    keep(checksum)
    print("nr_mbs_rel17_retained_checksum:", checksum)
