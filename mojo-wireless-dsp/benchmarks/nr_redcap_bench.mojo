"""Attributable CPU timings for RedCap capability and access algorithms."""

from std.benchmark import keep
from std.time import global_perf_counter_ns
from wireless_dsp.benchmarking import (
    print_benchmark_metadata,
    report_timing_samples,
)
from wireless_dsp.wireless.nr.redcap import (
    NRRedCapRel17Capabilities,
    NRERedCapRel18Capabilities,
    NRRedCapInitialBWP,
    NRRedCapRel17InitialAccessConfig,
    NRInitialBWPSelection,
    NR_FREQUENCY_RANGE_FR1,
    NR_DUPLEX_TDD,
    NR_REDCAP_DL_BWP_RACH_ONLY,
    NR_REDCAP_RA_MESSAGE_MSG1,
    NR_REDCAP_RA_MESSAGE_MSGA,
    NR_INITIAL_BWP_DIRECTION_DOWNLINK,
    nr_redcap_rel17_validate_capabilities,
    nr_redcap_rel17_cell_access_allowed,
    nr_eredcap_rel18_validate_capabilities,
    nr_eredcap_rel18_unicast_prb_limit,
    nr_eredcap_rel18_validate_scheduled_prbs,
    nr_redcap_rel17_select_initial_bwp,
    nr_redcap_rel17_validate_initial_access,
    nr_redcap_rel17_ra_search_space_first_cces,
    nr_redcap_rel17_early_indication_available,
    nr_eredcap_rel18_early_indication_available,
)


comptime _WARMUPS = 3
comptime _REPETITIONS = 9


def _candidate_checksum(values: List[Int]) -> UInt64:
    return UInt64(len(values)) ^ UInt64(values[0] + 1) ^ (UInt64(values[len(values) - 1] + 1) << 32)


@no_inline
def _workload_nr_redcap_rel17_validate_capabilities(
    value: NRRedCapRel17Capabilities,
) raises -> Bool:
    return nr_redcap_rel17_validate_capabilities(value)


@no_inline
def _workload_nr_redcap_rel17_cell_access_allowed(
    value: NRRedCapRel17Capabilities,
) raises -> Bool:
    return nr_redcap_rel17_cell_access_allowed(value)


@no_inline
def _workload_nr_eredcap_rel18_validate_capabilities(
    value: NRERedCapRel18Capabilities,
) raises -> Bool:
    return nr_eredcap_rel18_validate_capabilities(value)


@no_inline
def _workload_nr_eredcap_rel18_unicast_prb_limit(
    value: NRERedCapRel18Capabilities,
) raises -> Int:
    return nr_eredcap_rel18_unicast_prb_limit(value)


@no_inline
def _workload_nr_eredcap_rel18_validate_scheduled_prbs(
    value: NRERedCapRel18Capabilities,
) raises -> Bool:
    return nr_eredcap_rel18_validate_scheduled_prbs(value, 12)


@no_inline
def _workload_nr_redcap_rel17_select_initial_bwp(
    value: NRRedCapRel17Capabilities,
) raises -> NRInitialBWPSelection:
    return nr_redcap_rel17_select_initial_bwp(
        value, NR_INITIAL_BWP_DIRECTION_DOWNLINK, 20.0
    )


@no_inline
def _workload_nr_redcap_rel17_validate_initial_access(
    value: NRRedCapRel17Capabilities,
    config: NRRedCapRel17InitialAccessConfig,
) raises -> Bool:
    return nr_redcap_rel17_validate_initial_access(value, config)


@no_inline
def _workload_nr_redcap_rel17_ra_search_space_first_cces(
    value: NRRedCapRel17Capabilities,
    config: NRRedCapRel17InitialAccessConfig,
) raises -> List[Int]:
    return nr_redcap_rel17_ra_search_space_first_cces(value, config, 2, 4)


@no_inline
def _workload_nr_redcap_rel17_early_indication_available(
    value: NRRedCapRel17Capabilities,
) raises -> Bool:
    return nr_redcap_rel17_early_indication_available(
        value, NR_REDCAP_RA_MESSAGE_MSGA
    )


@no_inline
def _workload_nr_eredcap_rel18_early_indication_available(
    value: NRERedCapRel18Capabilities,
) raises -> Bool:
    return nr_eredcap_rel18_early_indication_available(
        value, NR_REDCAP_RA_MESSAGE_MSG1
    )


def main() raises:
    var rel17 = NRRedCapRel17Capabilities(
        NR_FREQUENCY_RANGE_FR1,
        20.0,
        2,
        2,
        duplex_mode=NR_DUPLEX_TDD,
        supports_two_step_rach=True,
        supports_rrm_relaxation_connected=True,
    )
    var eredcap = NRERedCapRel18Capabilities(20.0, 30, 1, 1)
    var dl = NRRedCapInitialBWP(0, 48, 3500000, 30)
    var ul = NRRedCapInitialBWP(0, 48, 3500000, 30)
    var access = NRRedCapRel17InitialAccessConfig(
        dl,
        ul,
        51,
        51,
        NR_REDCAP_DL_BWP_RACH_ONLY,
        coreset_resource_blocks=24,
        coreset_duration_symbols=2,
    )

    for _ in range(_WARMUPS):
        keep(_workload_nr_redcap_rel17_validate_capabilities(rel17))
        keep(_workload_nr_redcap_rel17_cell_access_allowed(rel17))
        keep(_workload_nr_eredcap_rel18_validate_capabilities(eredcap))
        keep(_workload_nr_eredcap_rel18_unicast_prb_limit(eredcap))
        keep(_workload_nr_redcap_rel17_select_initial_bwp(rel17))
        keep(_workload_nr_redcap_rel17_validate_initial_access(rel17, access))
        keep(_workload_nr_redcap_rel17_ra_search_space_first_cces(rel17, access))
        keep(_workload_nr_redcap_rel17_early_indication_available(rel17))
        keep(_workload_nr_eredcap_rel18_early_indication_available(eredcap))
        keep(_workload_nr_eredcap_rel18_validate_scheduled_prbs(eredcap))

    var capability_samples = List[UInt64](capacity=_REPETITIONS)
    var cell_access_samples = List[UInt64](capacity=_REPETITIONS)
    var eredcap_capability_samples = List[UInt64](capacity=_REPETITIONS)
    var eredcap_limit_samples = List[UInt64](capacity=_REPETITIONS)
    var bwp_selection_samples = List[UInt64](capacity=_REPETITIONS)
    var access_samples = List[UInt64](capacity=_REPETITIONS)
    var search_space_samples = List[UInt64](capacity=_REPETITIONS)
    var redcap_indication_samples = List[UInt64](capacity=_REPETITIONS)
    var eredcap_indication_samples = List[UInt64](capacity=_REPETITIONS)
    var eredcap_prb_samples = List[UInt64](capacity=_REPETITIONS)
    var checksum = UInt64(0)
    for repetition in range(_REPETITIONS):
        var start = global_perf_counter_ns()
        var capability_ok = _workload_nr_redcap_rel17_validate_capabilities(rel17)
        capability_samples.append(global_perf_counter_ns() - start)
        if capability_ok:
            checksum ^= UInt64(0x17 + repetition)
        keep(capability_ok)

        start = global_perf_counter_ns()
        var cell_allowed = _workload_nr_redcap_rel17_cell_access_allowed(rel17)
        cell_access_samples.append(global_perf_counter_ns() - start)
        if cell_allowed:
            checksum ^= UInt64(0xCE11 + repetition)
        keep(cell_allowed)

        start = global_perf_counter_ns()
        var eredcap_capability_ok = _workload_nr_eredcap_rel18_validate_capabilities(
            eredcap
        )
        eredcap_capability_samples.append(global_perf_counter_ns() - start)
        if eredcap_capability_ok:
            checksum ^= UInt64(0xECA0 + repetition)
        keep(eredcap_capability_ok)

        start = global_perf_counter_ns()
        var eredcap_limit = _workload_nr_eredcap_rel18_unicast_prb_limit(eredcap)
        eredcap_limit_samples.append(global_perf_counter_ns() - start)
        checksum ^= UInt64(eredcap_limit + repetition)
        keep(eredcap_limit)

        start = global_perf_counter_ns()
        var bwp_selection = _workload_nr_redcap_rel17_select_initial_bwp(rel17)
        bwp_selection_samples.append(global_perf_counter_ns() - start)
        checksum ^= UInt64(
            bwp_selection.source + repetition
            + Int(bwp_selection.bandwidth_mhz)
        )
        keep(bwp_selection)

        start = global_perf_counter_ns()
        var access_ok = _workload_nr_redcap_rel17_validate_initial_access(rel17, access)
        access_samples.append(global_perf_counter_ns() - start)
        if access_ok:
            checksum ^= UInt64(0xB0 + repetition)
        keep(access_ok)

        start = global_perf_counter_ns()
        var candidates = _workload_nr_redcap_rel17_ra_search_space_first_cces(rel17, access)
        search_space_samples.append(global_perf_counter_ns() - start)
        checksum ^= _candidate_checksum(candidates) + UInt64(repetition)
        keep(candidates)

        start = global_perf_counter_ns()
        var redcap_indication = _workload_nr_redcap_rel17_early_indication_available(rel17)
        redcap_indication_samples.append(global_perf_counter_ns() - start)
        if redcap_indication:
            checksum ^= UInt64(0xA17 + repetition)
        keep(redcap_indication)

        start = global_perf_counter_ns()
        var eredcap_indication = _workload_nr_eredcap_rel18_early_indication_available(eredcap)
        eredcap_indication_samples.append(global_perf_counter_ns() - start)
        if eredcap_indication:
            checksum ^= UInt64(0xA18 + repetition)
        keep(eredcap_indication)

        start = global_perf_counter_ns()
        var prb_ok = _workload_nr_eredcap_rel18_validate_scheduled_prbs(eredcap)
        eredcap_prb_samples.append(global_perf_counter_ns() - start)
        if prb_ok:
            checksum ^= UInt64(0xE18 + repetition)
        keep(prb_ok)

    print_benchmark_metadata()
    print("nr_redcap_scope: rel17-capability-bwp-pdcch-rel18-prb")
    print("nr_redcap_backend: scalar-cpu-reference")
    print("nr_redcap_timing_unit: ns")
    report_timing_samples(
        "nr_redcap_rel17_validate_capabilities",
        capability_samples,
        _WARMUPS,
        1,
        "capability_record",
    )
    report_timing_samples(
        "nr_redcap_rel17_cell_access_allowed",
        cell_access_samples,
        _WARMUPS,
        1,
        "cell_access_decision",
    )
    report_timing_samples(
        "nr_eredcap_rel18_validate_capabilities",
        eredcap_capability_samples,
        _WARMUPS,
        1,
        "capability_record",
    )
    report_timing_samples(
        "nr_eredcap_rel18_unicast_prb_limit",
        eredcap_limit_samples,
        _WARMUPS,
        1,
        "limit_decision",
    )
    report_timing_samples(
        "nr_redcap_rel17_select_initial_bwp",
        bwp_selection_samples,
        _WARMUPS,
        1,
        "bwp_selection",
    )
    report_timing_samples(
        "nr_redcap_rel17_validate_initial_access",
        access_samples,
        _WARMUPS,
        1,
        "initial_access_config",
    )
    report_timing_samples(
        "nr_redcap_rel17_ra_search_space_first_cces",
        search_space_samples,
        _WARMUPS,
        1,
        "candidate_set",
    )
    report_timing_samples(
        "nr_redcap_rel17_early_indication_available",
        redcap_indication_samples,
        _WARMUPS,
        1,
        "message_decision",
    )
    report_timing_samples(
        "nr_eredcap_rel18_early_indication_available",
        eredcap_indication_samples,
        _WARMUPS,
        1,
        "message_decision",
    )
    report_timing_samples(
        "nr_eredcap_rel18_validate_scheduled_prbs",
        eredcap_prb_samples,
        _WARMUPS,
        1,
        "scheduled_allocation",
    )
    print("nr_redcap_retained_checksum:", checksum)
