"""Attributable CPU benchmarks for Rel-18 NR sidelink decisions.

Each public algorithm has its own no-inline workload and timing series.  All
decoded configurations and scalar inputs are constructed before warmup and
timing.  Each scalar result contributes only an O(1) fingerprint and is kept
alive; the final deterministic checksum pins the complete retained workload.
"""

from std.benchmark import black_box, keep
from std.collections import Span
from std.time import global_perf_counter_ns
from wireless_dsp.benchmarking import (
    print_benchmark_metadata,
    report_timing_samples,
)
from wireless_dsp.wireless.nr.sidelink_rel18_enh import (
    NR_SL_PROFILE_REL18_ENH2,
    NR_SL_REL18_MODE2,
    NR_SL_REL18_BAND_N47,
    NRSidelinkRel18CoChannelConfig,
    NRSidelinkRel18CAConfig,
    nr_sl_rel18_mode2_slot_selection_allowed,
    nr_sl_rel18_psfch_candidate_excluded,
    nr_sl_rel18_ca_transmission_allowed,
)


comptime _WARMUPS = 3
comptime _SAMPLES = 9
comptime _BATCH = 8192
comptime _CASE_COUNT = 256
comptime _FIXED_SALT = 0x940097
comptime _EXPECTED_RETAINED_CHECKSUM = UInt64(15981093977707720278)


def _mix(checksum: UInt64, value: UInt64) -> UInt64:
    return (checksum ^ value) * UInt64(1099511628211)


def _build_cochannel_configs() raises -> List[NRSidelinkRel18CoChannelConfig]:
    var configs = List[NRSidelinkRel18CoChannelConfig](capacity=_CASE_COUNT)
    for index in range(_CASE_COUNT):
        var scs = 15 if (index & 1) == 0 else 30
        var start = index * 7
        configs.append(
            NRSidelinkRel18CoChannelConfig(
                NR_SL_PROFILE_REL18_ENH2,
                NR_SL_REL18_MODE2,
                scs,
                start,
                start,
            )
        )
    return configs^


def _build_slot_masks() -> List[Int]:
    var masks = List[Int](capacity=_CASE_COUNT)
    for index in range(_CASE_COUNT):
        masks.append((index * 5 + 1) & 3)
    return masks^


def _build_psfch_starts() -> List[Int]:
    var values = List[Int](capacity=_CASE_COUNT)
    for index in range(_CASE_COUNT):
        values.append(index * 13)
    return values^


def _build_psfch_ends(starts: Span[Int, ...]) -> List[Int]:
    var values = List[Int](capacity=len(starts))
    for index in range(len(starts)):
        values.append(starts[index] + 1 + (index % 11))
    return values^


def _build_lte_starts(
    psfch_starts: Span[Int, ...], psfch_ends: Span[Int, ...]
) -> List[Int]:
    var values = List[Int](capacity=len(psfch_starts))
    for index in range(len(psfch_starts)):
        var selector = index % 4
        if selector == 0:
            values.append(psfch_starts[index])
        elif selector == 1:
            values.append(psfch_ends[index])
        elif selector == 2 and psfch_starts[index] > 0:
            values.append(psfch_starts[index] - 1)
        else:
            values.append(psfch_starts[index] + 1)
    return values^


def _build_lte_ends(starts: Span[Int, ...]) -> List[Int]:
    var values = List[Int](capacity=len(starts))
    for index in range(len(starts)):
        values.append(starts[index] + 1 + ((index * 3) % 13))
    return values^


def _build_measurements() -> List[Float64]:
    var values = List[Float64](capacity=_CASE_COUNT)
    for index in range(_CASE_COUNT):
        values.append(-150.0 + Float64((index * 17) % 181) * 0.5)
    return values^


def _build_threshold_codes() -> List[Int]:
    var values = List[Int](capacity=_CASE_COUNT)
    for index in range(_CASE_COUNT):
        values.append((index * 29) % 67)
    return values^


def _lower_bandwidth(selector: Int) -> Int:
    if selector <= 2:
        return 10
    if selector <= 4:
        return 20
    return 30


def _upper_bandwidth(selector: Int) -> Int:
    if selector == 0:
        return 10
    if selector == 1:
        return 20
    if selector == 2:
        return 30
    if selector == 3:
        return 20
    if selector == 4:
        return 30
    if selector == 5:
        return 30
    return 40


def _build_ca_configs() raises -> List[NRSidelinkRel18CAConfig]:
    var configs = List[NRSidelinkRel18CAConfig](capacity=_CASE_COUNT)
    for index in range(_CASE_COUNT):
        var selector = index % 7
        var scs_selector = (index // 7) % 3
        var scs = 15
        if scs_selector == 1:
            scs = 30
        elif scs_selector == 2:
            scs = 60
        var period_selector = (index // 21) % 3
        var period = 1
        if period_selector == 1:
            period = 2
        elif period_selector == 2:
            period = 4
        var phase = index % period
        configs.append(
            NRSidelinkRel18CAConfig(
                NR_SL_PROFILE_REL18_ENH2,
                NR_SL_REL18_MODE2,
                2,
                NR_SL_REL18_BAND_N47,
                NR_SL_REL18_BAND_N47,
                True,
                scs,
                scs,
                _lower_bandwidth(selector),
                _upper_bandwidth(selector),
                period,
                period,
                phase,
                phase,
            )
        )
    return configs^


def _build_carrier_indices(shift: Int) -> List[Int]:
    var values = List[Int](capacity=_CASE_COUNT)
    for index in range(_CASE_COUNT):
        values.append((index >> shift) & 1)
    return values^


@no_inline
def _slot_selection_workload(
    iterations: Int,
    salt: Int,
    configs: Span[NRSidelinkRel18CoChannelConfig, ...],
    masks: Span[Int, ...],
) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for operation in range(iterations):
        var index = black_box((operation * 17 + salt) % len(configs))
        var config = configs[index]
        var mask = masks[index]
        var allowed = nr_sl_rel18_mode2_slot_selection_allowed(
            black_box(config), black_box(mask)
        )
        var fingerprint = (
            UInt64(mask)
            ^ (UInt64(config.subcarrier_spacing_khz) << 8)
            ^ (UInt64(allowed) << 24)
        )
        checksum = _mix(checksum, fingerprint)
        keep(allowed)
    return checksum


@no_inline
def _psfch_exclusion_workload(
    iterations: Int,
    salt: Int,
    configs: Span[NRSidelinkRel18CoChannelConfig, ...],
    psfch_starts: Span[Int, ...],
    psfch_ends: Span[Int, ...],
    lte_starts: Span[Int, ...],
    lte_ends: Span[Int, ...],
    measurements: Span[Float64, ...],
    threshold_codes: Span[Int, ...],
) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for operation in range(iterations):
        var index = black_box((operation * 19 + salt) % len(configs))
        var config = configs[index]
        var psfch_start = psfch_starts[index]
        var psfch_end = psfch_ends[index]
        var lte_start = lte_starts[index]
        var lte_end = lte_ends[index]
        var measurement = measurements[index]
        var threshold_code = threshold_codes[index]
        var excluded = nr_sl_rel18_psfch_candidate_excluded(
            black_box(config),
            black_box(psfch_start),
            black_box(psfch_end),
            black_box(lte_start),
            black_box(lte_end),
            black_box(measurement),
            black_box(threshold_code),
        )
        var fingerprint = (
            UInt64(psfch_start)
            ^ (UInt64(lte_start) << 16)
            ^ (UInt64(threshold_code) << 32)
            ^ (UInt64(excluded) << 48)
        )
        checksum = _mix(checksum, fingerprint)
        keep(excluded)
    return checksum


@no_inline
def _ca_transmission_workload(
    iterations: Int,
    salt: Int,
    configs: Span[NRSidelinkRel18CAConfig, ...],
    resource_indices: Span[Int, ...],
    sci_indices: Span[Int, ...],
    pssch_indices: Span[Int, ...],
    harq_indices: Span[Int, ...],
) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for operation in range(iterations):
        var index = black_box((operation * 23 + salt) % len(configs))
        var config = configs[index]
        var resource_index = resource_indices[index]
        var sci_index = sci_indices[index]
        var pssch_index = pssch_indices[index]
        var harq_index = harq_indices[index]
        var allowed = nr_sl_rel18_ca_transmission_allowed(
            black_box(config),
            black_box(resource_index),
            black_box(sci_index),
            black_box(pssch_index),
            black_box(harq_index),
        )
        var fingerprint = (
            UInt64(resource_index)
            ^ (UInt64(sci_index) << 4)
            ^ (UInt64(pssch_index) << 8)
            ^ (UInt64(harq_index) << 12)
            ^ (UInt64(config.carrier0_subcarrier_spacing_khz) << 16)
            ^ (UInt64(allowed) << 32)
        )
        checksum = _mix(checksum, fingerprint)
        keep(allowed)
    return checksum


def main() raises:
    # Every benchmark input is owned and fully decoded before any warmup or
    # timer starts.
    var cochannel_configs = _build_cochannel_configs()
    var slot_masks = _build_slot_masks()
    var psfch_starts = _build_psfch_starts()
    var psfch_starts_span = Span(psfch_starts)
    var psfch_ends = _build_psfch_ends(psfch_starts_span)
    var psfch_ends_span = Span(psfch_ends)
    var lte_starts = _build_lte_starts(
        psfch_starts_span, psfch_ends_span
    )
    var lte_ends = _build_lte_ends(Span(lte_starts))
    var measurements = _build_measurements()
    var threshold_codes = _build_threshold_codes()
    var ca_configs = _build_ca_configs()
    var resource_indices = _build_carrier_indices(0)
    var sci_indices = _build_carrier_indices(1)
    var pssch_indices = _build_carrier_indices(2)
    var harq_indices = _build_carrier_indices(3)

    var cochannel_configs_span = Span(cochannel_configs)
    var slot_masks_span = Span(slot_masks)
    var lte_starts_span = Span(lte_starts)
    var lte_ends_span = Span(lte_ends)
    var measurements_span = Span(measurements)
    var threshold_codes_span = Span(threshold_codes)
    var ca_configs_span = Span(ca_configs)
    var resource_indices_span = Span(resource_indices)
    var sci_indices_span = Span(sci_indices)
    var pssch_indices_span = Span(pssch_indices)
    var harq_indices_span = Span(harq_indices)

    for warmup in range(_WARMUPS):
        var salt = _FIXED_SALT + warmup * 257
        keep(
            _slot_selection_workload(
                _BATCH, salt, cochannel_configs_span, slot_masks_span
            )
        )
        keep(
            _psfch_exclusion_workload(
                _BATCH,
                salt,
                cochannel_configs_span,
                psfch_starts_span,
                psfch_ends_span,
                lte_starts_span,
                lte_ends_span,
                measurements_span,
                threshold_codes_span,
            )
        )
        keep(
            _ca_transmission_workload(
                _BATCH,
                salt,
                ca_configs_span,
                resource_indices_span,
                sci_indices_span,
                pssch_indices_span,
                harq_indices_span,
            )
        )

    var slot_samples = List[UInt64](capacity=_SAMPLES)
    var psfch_samples = List[UInt64](capacity=_SAMPLES)
    var ca_samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for sample in range(_SAMPLES):
        var salt = _FIXED_SALT + sample * 257

        var start = global_perf_counter_ns()
        var slot_checksum = _slot_selection_workload(
            _BATCH, salt, cochannel_configs_span, slot_masks_span
        )
        slot_samples.append(global_perf_counter_ns() - start)
        checksum = _mix(checksum, slot_checksum)
        keep(slot_checksum)

        start = global_perf_counter_ns()
        var psfch_checksum = _psfch_exclusion_workload(
            _BATCH,
            salt,
            cochannel_configs_span,
            psfch_starts_span,
            psfch_ends_span,
            lte_starts_span,
            lte_ends_span,
            measurements_span,
            threshold_codes_span,
        )
        psfch_samples.append(global_perf_counter_ns() - start)
        checksum = _mix(checksum, psfch_checksum)
        keep(psfch_checksum)

        start = global_perf_counter_ns()
        var ca_checksum = _ca_transmission_workload(
            _BATCH,
            salt,
            ca_configs_span,
            resource_indices_span,
            sci_indices_span,
            pssch_indices_span,
            harq_indices_span,
        )
        ca_samples.append(global_perf_counter_ns() - start)
        checksum = _mix(checksum, ca_checksum)
        keep(ca_checksum)

    print_benchmark_metadata()
    print("nr_sidelink_rel18_enh_backend:", "scalar-cpu-reference")
    print(
        "nr_sidelink_rel18_enh_baseline:",
        "RP-232789-38.321-ia0-38.214-ia0-38.331-ia0-38.101-1-ie0",
    )
    report_timing_samples(
        "nr_sl_rel18_mode2_slot_selection_allowed",
        slot_samples,
        _WARMUPS,
        _BATCH,
        "selection",
    )
    report_timing_samples(
        "nr_sl_rel18_psfch_candidate_excluded",
        psfch_samples,
        _WARMUPS,
        _BATCH,
        "candidate",
    )
    report_timing_samples(
        "nr_sl_rel18_ca_transmission_allowed",
        ca_samples,
        _WARMUPS,
        _BATCH,
        "transmission",
    )
    keep(checksum)
    print("nr_sidelink_rel18_enh_retained_checksum:", checksum)
    if checksum != _EXPECTED_RETAINED_CHECKSUM:
        raise Error("Rel-18 sidelink benchmark retained checksum changed")
