"""Attributable CPU timings for Rel-17 RedCap Annex table lookups."""

from std.benchmark import black_box, keep
from std.time import global_perf_counter_ns
from wireless_dsp.benchmarking import (
    print_benchmark_metadata,
    report_timing_samples,
)
from wireless_dsp.wireless.nr.redcap_rrm_annex import (
    NR_REDCAP_ANNEX_FR1,
    NR_REDCAP_ANNEX_FR2,
    NR_REDCAP_ANNEX_SOURCE_NR,
    NR_REDCAP_ANNEX_SOURCE_EUTRA,
    NR_REDCAP_ANNEX_CONDITION_CELL_RESELECTION,
    NR_REDCAP_ANNEX_RELATION_INTRA_FREQUENCY,
    NR_REDCAP_ANNEX_RELATION_INTER_FREQUENCY,
    NR_REDCAP_ANNEX_TABLE_B1_4_3,
    NR_REDCAP_ANNEX_TABLE_B2_15_3,
    NR_REDCAP_ANNEX_TABLE_B2_16_2_AS_PUBLISHED,
    NR_REDCAP_ANNEX_TABLE_B2_16_3,
    NR_REDCAP_ANNEX_AOA_RX_BEAM_PEAK,
    NRRedCapAnnexFR2Condition,
    nr_redcap_rel17_annex_bwp_configuration,
    nr_redcap_rel17_annex_ssb_configuration,
    nr_redcap_rel17_annex_smtc_configuration,
    nr_redcap_rel17_annex_test_scope,
    nr_redcap_rel17_annex_fr1_condition,
    nr_redcap_rel17_annex_fr2_condition,
    nr_redcap_rel17_annex_resolve_fr2_minimum_ssb_rp_tenth_dbm,
)


comptime _WARMUPS = 3
comptime _SAMPLES = 9
comptime _BATCH = 4096


def _mix(checksum: UInt64, value: Int) -> UInt64:
    return checksum * UInt64(1099511628211) ^ UInt64(value + 4096)


def _ssb_scs(selector: Int) -> Int:
    if selector == 0:
        return 15
    if selector == 1:
        return 30
    if selector == 2:
        return 120
    return 240


def _fr2_table(selector: Int) -> Int:
    if selector == 0:
        return NR_REDCAP_ANNEX_TABLE_B1_4_3
    if selector == 1:
        return NR_REDCAP_ANNEX_TABLE_B2_15_3
    if selector == 2:
        return NR_REDCAP_ANNEX_TABLE_B2_16_2_AS_PUBLISHED
    return NR_REDCAP_ANNEX_TABLE_B2_16_3


@no_inline
def _bwp_workload(iterations: Int, salt: Int) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for iteration in range(iterations):
        var selector = iteration + salt
        var config = nr_redcap_rel17_annex_bwp_configuration(
            black_box(selector & 1),
            black_box(selector % 3 + 1),
            black_box(_ssb_scs((selector >> 2) & 3)),
        )
        checksum = _mix(
            checksum,
            config.bandwidth_prbs
                + config.starting_prb_rule
                + iteration,
        )
    return checksum


@no_inline
def _ssb_workload(iterations: Int, salt: Int) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for iteration in range(iterations):
        var selector = iteration + salt
        var frequency_range = (
            NR_REDCAP_ANNEX_FR1
            if (selector & 1) == 0
            else NR_REDCAP_ANNEX_FR2
        )
        var pattern = (
            selector % 7 + 1
            if frequency_range == NR_REDCAP_ANNEX_FR1
            else selector % 5 + 1
        )
        var config = nr_redcap_rel17_annex_ssb_configuration(
            black_box(frequency_range), black_box(pattern)
        )
        checksum = _mix(
            checksum,
            config.ssb_scs_khz
                + config.periodicity_ms
                + config.first_symbol_start
                + iteration,
        )
    return checksum


@no_inline
def _smtc_workload(iterations: Int, salt: Int) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for iteration in range(iterations):
        var config = nr_redcap_rel17_annex_smtc_configuration(
            black_box((iteration + salt) & 3) + 1
        )
        checksum = _mix(
            checksum,
            config.periodicity_ms
                + config.offset_ms
                + config.duration_ms
                + iteration,
        )
    return checksum


@no_inline
def _scope_workload(iterations: Int, salt: Int) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for iteration in range(iterations):
        var selector = iteration + salt
        var source_rat = (
            NR_REDCAP_ANNEX_SOURCE_NR
            if (selector & 1) == 0
            else NR_REDCAP_ANNEX_SOURCE_EUTRA
        )
        var frequency_range = (
            NR_REDCAP_ANNEX_FR1
            if (selector & 2) == 0
            else NR_REDCAP_ANNEX_FR2
        )
        var rx = 1 + ((selector >> 2) & 1)
        if frequency_range == NR_REDCAP_ANNEX_FR2:
            rx = 2
        var scope = nr_redcap_rel17_annex_test_scope(
            black_box(source_rat), black_box(frequency_range), black_box(rx)
        )
        checksum = _mix(checksum, scope.annex_clause + iteration)
    return checksum


@no_inline
def _fr1_workload(iterations: Int, salt: Int) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for iteration in range(iterations):
        var selector = iteration + salt
        var condition = nr_redcap_rel17_annex_fr1_condition(
            black_box(NR_REDCAP_ANNEX_CONDITION_CELL_RESELECTION),
            black_box(
                NR_REDCAP_ANNEX_RELATION_INTRA_FREQUENCY
                if (selector & 1) == 0
                else NR_REDCAP_ANNEX_RELATION_INTER_FREQUENCY
            ),
            black_box(1 + ((selector >> 1) & 1)),
            black_box((selector >> 2) & 7),
            black_box(15 if (selector & 32) == 0 else 30),
        )
        checksum = _mix(
            checksum,
            condition.minimum_ssb_rp_tenth_dbm
                + condition.minimum_ssb_es_iot_tenth_db
                + iteration,
        )
    return checksum


@no_inline
def _fr2_workload(iterations: Int, salt: Int) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for iteration in range(iterations):
        var selector = iteration + salt
        var condition = nr_redcap_rel17_annex_fr2_condition(
            black_box(_fr2_table(selector & 3)),
            black_box(selector >> 2 & 1),
            black_box(257 if (selector & 8) == 0 else 258),
            black_box(2),
            black_box(120 if (selector & 16) == 0 else 240),
        )
        checksum = _mix(
            checksum,
            condition.minimum_ssb_rp_base_tenth_dbm
                + condition.minimum_ssb_es_iot_tenth_db
                + iteration,
        )
    return checksum


@no_inline
def _resolve_workload(
    iterations: Int,
    salt: Int,
    condition: NRRedCapAnnexFR2Condition,
) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for iteration in range(iterations):
        var selector = iteration + salt
        var resolved = (
            nr_redcap_rel17_annex_resolve_fr2_minimum_ssb_rp_tenth_dbm(
                condition,
                black_box(selector & 31),
                black_box((selector >> 5) & 15),
            )
        )
        checksum = _mix(checksum, resolved + iteration)
    return checksum


def main() raises:
    var symbolic = nr_redcap_rel17_annex_fr2_condition(
        NR_REDCAP_ANNEX_TABLE_B1_4_3,
        NR_REDCAP_ANNEX_AOA_RX_BEAM_PEAK,
        257,
        4,
        120,
    )

    for _ in range(_WARMUPS):
        var salt = 324508639
        keep(_bwp_workload(_BATCH, salt))
        keep(_ssb_workload(_BATCH, salt))
        keep(_smtc_workload(_BATCH, salt))
        keep(_scope_workload(_BATCH, salt))
        keep(_fr1_workload(_BATCH, salt))
        keep(_fr2_workload(_BATCH, salt))
        keep(_resolve_workload(_BATCH, salt, symbolic))

    var bwp_samples = List[UInt64](capacity=_SAMPLES)
    var ssb_samples = List[UInt64](capacity=_SAMPLES)
    var smtc_samples = List[UInt64](capacity=_SAMPLES)
    var scope_samples = List[UInt64](capacity=_SAMPLES)
    var fr1_samples = List[UInt64](capacity=_SAMPLES)
    var fr2_samples = List[UInt64](capacity=_SAMPLES)
    var resolve_samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)

    for _ in range(_SAMPLES):
        var salt = 324508639
        var start = global_perf_counter_ns()
        var bwp = _bwp_workload(_BATCH, salt)
        bwp_samples.append(global_perf_counter_ns() - start)
        checksum = checksum * UInt64(1099511628211) ^ bwp
        keep(bwp)

        start = global_perf_counter_ns()
        var ssb = _ssb_workload(_BATCH, salt)
        ssb_samples.append(global_perf_counter_ns() - start)
        checksum = checksum * UInt64(1099511628211) ^ ssb
        keep(ssb)

        start = global_perf_counter_ns()
        var smtc = _smtc_workload(_BATCH, salt)
        smtc_samples.append(global_perf_counter_ns() - start)
        checksum = checksum * UInt64(1099511628211) ^ smtc
        keep(smtc)

        start = global_perf_counter_ns()
        var scope = _scope_workload(_BATCH, salt)
        scope_samples.append(global_perf_counter_ns() - start)
        checksum = checksum * UInt64(1099511628211) ^ scope
        keep(scope)

        start = global_perf_counter_ns()
        var fr1 = _fr1_workload(_BATCH, salt)
        fr1_samples.append(global_perf_counter_ns() - start)
        checksum = checksum * UInt64(1099511628211) ^ fr1
        keep(fr1)

        start = global_perf_counter_ns()
        var fr2 = _fr2_workload(_BATCH, salt)
        fr2_samples.append(global_perf_counter_ns() - start)
        checksum = checksum * UInt64(1099511628211) ^ fr2
        keep(fr2)

        start = global_perf_counter_ns()
        var resolved = _resolve_workload(_BATCH, salt, symbolic)
        resolve_samples.append(global_perf_counter_ns() - start)
        checksum = checksum * UInt64(1099511628211) ^ resolved
        keep(resolved)

    print_benchmark_metadata()
    print("nr_redcap_rrm_annex_backend: scalar-cpu-reference")
    report_timing_samples(
        "nr_redcap_rel17_annex_bwp_configuration",
        bwp_samples,
        _WARMUPS,
        _BATCH,
        "published_bwp_row_lookup",
    )
    report_timing_samples(
        "nr_redcap_rel17_annex_ssb_configuration",
        ssb_samples,
        _WARMUPS,
        _BATCH,
        "published_ssb_pattern_lookup",
    )
    report_timing_samples(
        "nr_redcap_rel17_annex_smtc_configuration",
        smtc_samples,
        _WARMUPS,
        _BATCH,
        "published_smtc_pattern_lookup",
    )
    report_timing_samples(
        "nr_redcap_rel17_annex_test_scope",
        scope_samples,
        _WARMUPS,
        _BATCH,
        "annex_test_family_selection",
    )
    report_timing_samples(
        "nr_redcap_rel17_annex_fr1_condition",
        fr1_samples,
        _WARMUPS,
        _BATCH,
        "published_fr1_condition_lookup",
    )
    report_timing_samples(
        "nr_redcap_rel17_annex_fr2_condition",
        fr2_samples,
        _WARMUPS,
        _BATCH,
        "published_fr2_expression_lookup",
    )
    report_timing_samples(
        "nr_redcap_rel17_annex_resolve_fr2_minimum_ssb_rp_tenth_dbm",
        resolve_samples,
        _WARMUPS,
        _BATCH,
        "checked_symbolic_condition_resolution",
    )
    print("nr_redcap_rrm_annex_retained_checksum:", checksum)
