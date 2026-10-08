"""Independent evidence for bounded Rel-18 NR sidelink enhancements."""

from std.testing import (
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
    TestSuite,
)
from std.utils.numerics import inf, nan
from wireless_dsp.wireless.nr.sidelink_rel18_enh import (
    NR_SL_PROFILE_ORDINARY_NR,
    NR_SL_PROFILE_REL18_ENH2,
    NR_SL_PROFILE_LATER_RELEASE,
    NR_SL_REL18_MODE2,
    NR_SL_REL18_BAND_N47,
    NR_SL_REL18_FIRST_OVERLAPPING_SLOT,
    NR_SL_REL18_SUBSEQUENT_OVERLAPPING_SLOT,
    NRSidelinkRel18CoChannelConfig,
    NRSidelinkRel18CAConfig,
    nr_sl_rel18_mode2_slot_selection_allowed,
    nr_sl_rel18_psfch_candidate_excluded,
    nr_sl_rel18_ca_transmission_allowed,
)


def _cochannel_config(
    scs_khz: Int = 30, start_half_ms: Int = 0
) raises -> NRSidelinkRel18CoChannelConfig:
    return NRSidelinkRel18CoChannelConfig(
        NR_SL_PROFILE_REL18_ENH2,
        NR_SL_REL18_MODE2,
        scs_khz,
        start_half_ms,
        start_half_ms,
    )


def _ca_config(
    scs0_khz: Int = 30,
    scs1_khz: Int = 30,
    bandwidth0_mhz: Int = 20,
    bandwidth1_mhz: Int = 30,
    period0_slots: Int = 4,
    period1_slots: Int = 4,
    phase0_slots: Int = 3,
    phase1_slots: Int = 3,
) raises -> NRSidelinkRel18CAConfig:
    return NRSidelinkRel18CAConfig(
        NR_SL_PROFILE_REL18_ENH2,
        NR_SL_REL18_MODE2,
        2,
        NR_SL_REL18_BAND_N47,
        NR_SL_REL18_BAND_N47,
        True,
        scs0_khz,
        scs1_khz,
        bandwidth0_mhz,
        bandwidth1_mhz,
        period0_slots,
        period1_slots,
        phase0_slots,
        phase1_slots,
    )


def _oracle_slot_allowed(scs_khz: Int, mask: Int) -> Bool:
    # Independent literal truth table, with no production constant/helper.
    if scs_khz == 15:
        return mask == 1
    return mask == 1 or mask == 3


def _oracle_half_open_overlap(
    first_start: Int, first_end: Int, second_start: Int, second_end: Int
) -> Bool:
    # Set-theoretic half-open overlap oracle.
    return max(first_start, second_start) < min(first_end, second_end)


def _oracle_above_threshold_twice_dbm(
    measured_twice_dbm: Int, threshold_code: Int
) -> Bool:
    # Integer half-dBm arithmetic is independent of production Float64 math.
    if threshold_code == 0:
        return True
    if threshold_code == 66:
        return False
    var threshold_twice_dbm = -256 + 4 * (threshold_code - 1)
    return measured_twice_dbm > threshold_twice_dbm


def _oracle_ca_allowed(
    resource_carrier: Int,
    sci_carrier: Int,
    pssch_carrier: Int,
    harq_carrier: Int,
) -> Bool:
    # Independent equality partition over the finite two-carrier domain.
    var total = (
        resource_carrier + sci_carrier + pssch_carrier + harq_carrier
    )
    return total == 0 or total == 4


def test_rel18_profile_tags_and_complete_slot_mask_truth_table() raises:
    assert_equal(NR_SL_PROFILE_ORDINARY_NR, 0)
    assert_equal(NR_SL_PROFILE_REL18_ENH2, 1)
    assert_equal(NR_SL_PROFILE_LATER_RELEASE, 2)
    assert_equal(NR_SL_REL18_MODE2, 2)
    assert_equal(NR_SL_REL18_BAND_N47, 47)
    assert_equal(NR_SL_REL18_FIRST_OVERLAPPING_SLOT, 1)
    assert_equal(NR_SL_REL18_SUBSEQUENT_OVERLAPPING_SLOT, 2)

    var config15 = _cochannel_config(15, 18)
    var config30 = _cochannel_config(30, 18)
    for mask in range(4):
        var expected15 = _oracle_slot_allowed(15, mask)
        var expected30 = _oracle_slot_allowed(30, mask)
        assert_equal(
            nr_sl_rel18_mode2_slot_selection_allowed(config15, mask),
            expected15,
        )
        assert_equal(
            nr_sl_rel18_mode2_slot_selection_allowed(config30, mask),
            expected30,
        )
        # Repeat each call to make determinism explicit.
        assert_equal(
            nr_sl_rel18_mode2_slot_selection_allowed(config15, mask),
            expected15,
        )
        assert_equal(
            nr_sl_rel18_mode2_slot_selection_allowed(config30, mask),
            expected30,
        )

    # No arithmetic is needed to admit an aligned maximum tick.
    var maximum = _cochannel_config(30, Int.MAX)
    assert_true(nr_sl_rel18_mode2_slot_selection_allowed(maximum, 1))
    assert_true(nr_sl_rel18_mode2_slot_selection_allowed(maximum, 3))
    # The start-alignment expectation is specific to 30 kHz.  A decoded
    # overlapping 15 kHz slot need not satisfy that additional validator.
    var unaligned15 = NRSidelinkRel18CoChannelConfig(
        NR_SL_PROFILE_REL18_ENH2, NR_SL_REL18_MODE2, 15, 4, 3
    )
    assert_true(nr_sl_rel18_mode2_slot_selection_allowed(unaligned15, 1))


def test_psfch_static_threshold_table_and_overlap_endpoints() raises:
    var config15 = _cochannel_config(15)
    var config30 = _cochannel_config(30)

    # Exact special endpoints and representative finite table entries.
    assert_true(
        nr_sl_rel18_psfch_candidate_excluded(
            config15, 10, 20, 10, 20, -1.0e300, 0
        )
    )
    assert_false(
        nr_sl_rel18_psfch_candidate_excluded(
            config15, 10, 20, 10, 20, 1.0e300, 66
        )
    )
    # Code 1 is -128 dBm and the comparison is strict.
    assert_false(
        nr_sl_rel18_psfch_candidate_excluded(
            config30, 10, 20, 10, 20, -128.0, 1
        )
    )
    assert_false(
        nr_sl_rel18_psfch_candidate_excluded(
            config30, 10, 20, 10, 20, -128.5, 1
        )
    )
    assert_true(
        nr_sl_rel18_psfch_candidate_excluded(
            config30, 10, 20, 10, 20, -127.5, 1
        )
    )
    # Code 2 is -126 dBm; code 65 is 0 dBm.
    assert_false(
        nr_sl_rel18_psfch_candidate_excluded(
            config30, 10, 20, 10, 20, -126.0, 2
        )
    )
    assert_true(
        nr_sl_rel18_psfch_candidate_excluded(
            config30, 10, 20, 10, 20, -125.5, 2
        )
    )
    assert_false(
        nr_sl_rel18_psfch_candidate_excluded(
            config30, 10, 20, 10, 20, 0.0, 65
        )
    )
    assert_true(
        nr_sl_rel18_psfch_candidate_excluded(
            config30, 10, 20, 10, 20, 0.5, 65
        )
    )

    # Half-open endpoints touch but do not overlap, in either direction.
    assert_false(
        nr_sl_rel18_psfch_candidate_excluded(
            config30, 10, 20, 20, 30, -50.0, 1
        )
    )
    assert_false(
        nr_sl_rel18_psfch_candidate_excluded(
            config30, 20, 30, 10, 20, -50.0, 1
        )
    )
    assert_true(
        nr_sl_rel18_psfch_candidate_excluded(
            config30, 10, 20, 19, 30, -50.0, 1
        )
    )
    assert_true(
        nr_sl_rel18_psfch_candidate_excluded(
            config30, 12, 18, 10, 20, -50.0, 1
        )
    )
    assert_true(
        nr_sl_rel18_psfch_candidate_excluded(
            config30,
            Int.MAX - 1,
            Int.MAX,
            Int.MAX - 1,
            Int.MAX,
            -50.0,
            1,
        )
    )


def test_n47b_static_rf_table_and_carrier_role_symmetry() raises:
    var lower_bandwidths: List[Int] = [10, 10, 10, 20, 20, 30, 30]
    var upper_bandwidths: List[Int] = [10, 20, 30, 20, 30, 30, 40]
    for scs in [15, 30, 60]:
        for entry in range(len(lower_bandwidths)):
            var config = _ca_config(
                scs,
                scs,
                lower_bandwidths[entry],
                upper_bandwidths[entry],
            )
            for resource_carrier in range(2):
                for sci_carrier in range(2):
                    for pssch_carrier in range(2):
                        for harq_carrier in range(2):
                            var expected = _oracle_ca_allowed(
                                resource_carrier,
                                sci_carrier,
                                pssch_carrier,
                                harq_carrier,
                            )
                            assert_equal(
                                nr_sl_rel18_ca_transmission_allowed(
                                    config,
                                    resource_carrier,
                                    sci_carrier,
                                    pssch_carrier,
                                    harq_carrier,
                                ),
                                expected,
                            )

    var config = _ca_config()
    # Carrier ordinals are symmetric roles: both all-local assignments pass.
    assert_true(nr_sl_rel18_ca_transmission_allowed(config, 0, 0, 0, 0))
    assert_true(nr_sl_rel18_ca_transmission_allowed(config, 1, 1, 1, 1))
    assert_false(nr_sl_rel18_ca_transmission_allowed(config, 0, 1, 0, 0))
    assert_false(nr_sl_rel18_ca_transmission_allowed(config, 1, 1, 1, 0))


def test_seeded_independent_analytic_oracles() raises:
    var seed = UInt64(0x94009718)
    var config15 = _cochannel_config(15)
    var config30 = _cochannel_config(30)
    var ca = _ca_config()
    for _ in range(1024):
        seed = seed * UInt64(6364136223846793005) + UInt64(1)
        var scs = 15 if (seed & UInt64(1)) == 0 else 30
        var mask = Int((seed >> 1) & UInt64(3))
        var sharing = config15 if scs == 15 else config30
        assert_equal(
            nr_sl_rel18_mode2_slot_selection_allowed(sharing, mask),
            _oracle_slot_allowed(scs, mask),
        )

        seed = seed * UInt64(6364136223846793005) + UInt64(1)
        var psfch_start = Int(seed % UInt64(1000))
        var psfch_end = psfch_start + 1 + Int((seed >> 10) % UInt64(31))
        seed = seed * UInt64(6364136223846793005) + UInt64(1)
        var lte_start = Int(seed % UInt64(1000))
        var lte_end = lte_start + 1 + Int((seed >> 10) % UInt64(31))
        var threshold_code = Int((seed >> 16) % UInt64(67))
        seed = seed * UInt64(6364136223846793005) + UInt64(1)
        var measured_twice_dbm = Int(seed % UInt64(601)) - 400
        var expected_excluded = _oracle_half_open_overlap(
            psfch_start, psfch_end, lte_start, lte_end
        ) and _oracle_above_threshold_twice_dbm(
            measured_twice_dbm, threshold_code
        )
        assert_equal(
            nr_sl_rel18_psfch_candidate_excluded(
                sharing,
                psfch_start,
                psfch_end,
                lte_start,
                lte_end,
                Float64(measured_twice_dbm) / 2.0,
                threshold_code,
            ),
            expected_excluded,
        )

        var resource_carrier = Int(seed & UInt64(1))
        var sci_carrier = Int((seed >> 1) & UInt64(1))
        var pssch_carrier = Int((seed >> 2) & UInt64(1))
        var harq_carrier = Int((seed >> 3) & UInt64(1))
        assert_equal(
            nr_sl_rel18_ca_transmission_allowed(
                ca,
                resource_carrier,
                sci_carrier,
                pssch_carrier,
                harq_carrier,
            ),
            _oracle_ca_allowed(
                resource_carrier,
                sci_carrier,
                pssch_carrier,
                harq_carrier,
            ),
        )

    # Locks the independent deterministic corpus itself.
    assert_equal(seed, UInt64(4996973148674803480))


def test_cochannel_edges_nonfinite_extremes_and_mutation_revalidation() raises:
    for invalid_profile in [
        Int.MIN,
        NR_SL_PROFILE_ORDINARY_NR,
        NR_SL_PROFILE_LATER_RELEASE,
        Int.MAX,
    ]:
        with assert_raises():
            _ = NRSidelinkRel18CoChannelConfig(
                invalid_profile, NR_SL_REL18_MODE2, 30, 0, 0
            )
    for invalid_mode in [Int.MIN, -1, 0, 1, 3, Int.MAX]:
        with assert_raises():
            _ = NRSidelinkRel18CoChannelConfig(
                NR_SL_PROFILE_REL18_ENH2, invalid_mode, 30, 0, 0
            )
    for invalid_scs in [Int.MIN, -1, 0, 14, 16, 60, Int.MAX]:
        with assert_raises():
            _ = NRSidelinkRel18CoChannelConfig(
                NR_SL_PROFILE_REL18_ENH2,
                NR_SL_REL18_MODE2,
                invalid_scs,
                0,
                0,
            )
    for invalid_time in [Int.MIN, -1]:
        with assert_raises():
            _ = NRSidelinkRel18CoChannelConfig(
                NR_SL_PROFILE_REL18_ENH2,
                NR_SL_REL18_MODE2,
                30,
                invalid_time,
                invalid_time,
            )
    with assert_raises():
        _ = NRSidelinkRel18CoChannelConfig(
            NR_SL_PROFILE_REL18_ENH2, NR_SL_REL18_MODE2, 30, 4, 5
        )

    var valid = _cochannel_config()
    for invalid_mask in [Int.MIN, -1, 4, Int.MAX]:
        with assert_raises():
            _ = nr_sl_rel18_mode2_slot_selection_allowed(
                valid, invalid_mask
            )

    with assert_raises():
        _ = nr_sl_rel18_psfch_candidate_excluded(
            valid, 0, 1, 0, 1, nan[DType.float64](), 1
        )
    with assert_raises():
        _ = nr_sl_rel18_psfch_candidate_excluded(
            valid, 0, 1, 0, 1, inf[DType.float64](), 1
        )
    with assert_raises():
        _ = nr_sl_rel18_psfch_candidate_excluded(
            valid, 0, 1, 0, 1, -inf[DType.float64](), 1
        )
    for invalid_threshold in [Int.MIN, -1, 67, Int.MAX]:
        with assert_raises():
            _ = nr_sl_rel18_psfch_candidate_excluded(
                valid, 0, 1, 0, 1, -50.0, invalid_threshold
            )
    for invalid_end in [Int.MIN, -1, 0]:
        with assert_raises():
            _ = nr_sl_rel18_psfch_candidate_excluded(
                valid, 0, invalid_end, 0, 1, -50.0, 1
            )
        with assert_raises():
            _ = nr_sl_rel18_psfch_candidate_excluded(
                valid, 0, 1, 0, invalid_end, -50.0, 1
            )
    with assert_raises():
        _ = nr_sl_rel18_psfch_candidate_excluded(
            valid, Int.MAX, Int.MAX, 0, 1, -50.0, 1
        )
    with assert_raises():
        _ = nr_sl_rel18_psfch_candidate_excluded(
            valid, 0, 1, Int.MAX, Int.MAX, -50.0, 1
        )

    # Both consuming APIs revalidate their mutable configuration argument.
    var mutated = valid
    mutated.profile = NR_SL_PROFILE_ORDINARY_NR
    with assert_raises():
        _ = nr_sl_rel18_mode2_slot_selection_allowed(mutated, 1)
    with assert_raises():
        _ = nr_sl_rel18_psfch_candidate_excluded(
            mutated, 0, 1, 0, 1, -50.0, 1
        )
    mutated = valid
    mutated.resource_allocation_mode = Int.MAX
    with assert_raises():
        _ = nr_sl_rel18_mode2_slot_selection_allowed(mutated, 1)
    mutated = valid
    mutated.subcarrier_spacing_khz = 60
    with assert_raises():
        _ = nr_sl_rel18_psfch_candidate_excluded(
            mutated, 0, 1, 0, 1, -50.0, 1
        )
    mutated = valid
    mutated.lte_subframe_start_half_ms = -1
    with assert_raises():
        _ = nr_sl_rel18_mode2_slot_selection_allowed(mutated, 1)
    mutated = valid
    mutated.first_nr_slot_start_half_ms = 1
    with assert_raises():
        _ = nr_sl_rel18_psfch_candidate_excluded(
            mutated, 0, 1, 0, 1, -50.0, 1
        )


def test_ca_edges_extremes_and_mutation_revalidation() raises:
    for invalid_count in [Int.MIN, -1, 0, 1, 3, 8, Int.MAX]:
        with assert_raises():
            _ = NRSidelinkRel18CAConfig(
                NR_SL_PROFILE_REL18_ENH2,
                NR_SL_REL18_MODE2,
                invalid_count,
                47,
                47,
                True,
                30,
                30,
                20,
                30,
                4,
                4,
                3,
                3,
            )
    for invalid_band in [Int.MIN, -1, 0, 46, 48, Int.MAX]:
        with assert_raises():
            _ = NRSidelinkRel18CAConfig(
                NR_SL_PROFILE_REL18_ENH2,
                NR_SL_REL18_MODE2,
                2,
                invalid_band,
                47,
                True,
                30,
                30,
                20,
                30,
                4,
                4,
                3,
                3,
            )
        with assert_raises():
            _ = NRSidelinkRel18CAConfig(
                NR_SL_PROFILE_REL18_ENH2,
                NR_SL_REL18_MODE2,
                2,
                47,
                invalid_band,
                True,
                30,
                30,
                20,
                30,
                4,
                4,
                3,
                3,
            )
    with assert_raises():
        _ = NRSidelinkRel18CAConfig(
            NR_SL_PROFILE_REL18_ENH2,
            NR_SL_REL18_MODE2,
            2,
            47,
            47,
            False,
            30,
            30,
            20,
            30,
            4,
            4,
            3,
            3,
        )
    for invalid_scs in [Int.MIN, -1, 0, 14, 16, 120, Int.MAX]:
        with assert_raises():
            _ = _ca_config(invalid_scs, invalid_scs)
    with assert_raises():
        _ = _ca_config(15, 30)
    for invalid_bandwidth in [Int.MIN, -1, 0, 5, 40, Int.MAX]:
        with assert_raises():
            _ = _ca_config(
                bandwidth0_mhz=invalid_bandwidth,
                bandwidth1_mhz=30,
            )
    for invalid_pair_upper in [Int.MIN, -1, 0, 10, 40, Int.MAX]:
        with assert_raises():
            _ = _ca_config(
                bandwidth0_mhz=20,
                bandwidth1_mhz=invalid_pair_upper,
            )
    for invalid_period in [Int.MIN, -1, 0, 3, 5, Int.MAX]:
        with assert_raises():
            _ = _ca_config(
                period0_slots=invalid_period,
                period1_slots=invalid_period,
                phase0_slots=0,
                phase1_slots=0,
            )
    with assert_raises():
        _ = _ca_config(period0_slots=2, period1_slots=4, phase0_slots=1)
    for invalid_phase in [Int.MIN, -1, 4, Int.MAX]:
        with assert_raises():
            _ = _ca_config(
                phase0_slots=invalid_phase, phase1_slots=invalid_phase
            )
    with assert_raises():
        _ = _ca_config(phase0_slots=2, phase1_slots=3)

    var valid = _ca_config()
    for invalid_index in [Int.MIN, -1, 2, Int.MAX]:
        with assert_raises():
            _ = nr_sl_rel18_ca_transmission_allowed(
                valid, invalid_index, 0, 0, 0
            )
        with assert_raises():
            _ = nr_sl_rel18_ca_transmission_allowed(
                valid, 0, invalid_index, 0, 0
            )
        with assert_raises():
            _ = nr_sl_rel18_ca_transmission_allowed(
                valid, 0, 0, invalid_index, 0
            )
        with assert_raises():
            _ = nr_sl_rel18_ca_transmission_allowed(
                valid, 0, 0, 0, invalid_index
            )

    # Every public field class is observed again by the consuming API.
    var mutated = valid
    mutated.profile = NR_SL_PROFILE_LATER_RELEASE
    with assert_raises():
        _ = nr_sl_rel18_ca_transmission_allowed(mutated, 0, 0, 0, 0)
    mutated = valid
    mutated.resource_allocation_mode = 1
    with assert_raises():
        _ = nr_sl_rel18_ca_transmission_allowed(mutated, 0, 0, 0, 0)
    mutated = valid
    mutated.carrier_count = Int.MAX
    with assert_raises():
        _ = nr_sl_rel18_ca_transmission_allowed(mutated, 0, 0, 0, 0)
    mutated = valid
    mutated.carrier0_band = 46
    with assert_raises():
        _ = nr_sl_rel18_ca_transmission_allowed(mutated, 0, 0, 0, 0)
    mutated = valid
    mutated.carrier1_band = Int.MIN
    with assert_raises():
        _ = nr_sl_rel18_ca_transmission_allowed(mutated, 0, 0, 0, 0)
    mutated = valid
    mutated.intra_band_contiguous = False
    with assert_raises():
        _ = nr_sl_rel18_ca_transmission_allowed(mutated, 0, 0, 0, 0)
    mutated = valid
    mutated.carrier0_subcarrier_spacing_khz = 15
    with assert_raises():
        _ = nr_sl_rel18_ca_transmission_allowed(mutated, 0, 0, 0, 0)
    mutated = valid
    mutated.carrier1_subcarrier_spacing_khz = Int.MAX
    with assert_raises():
        _ = nr_sl_rel18_ca_transmission_allowed(mutated, 0, 0, 0, 0)
    mutated = valid
    mutated.carrier0_channel_bandwidth_mhz = 40
    with assert_raises():
        _ = nr_sl_rel18_ca_transmission_allowed(mutated, 0, 0, 0, 0)
    mutated = valid
    mutated.carrier1_channel_bandwidth_mhz = 10
    with assert_raises():
        _ = nr_sl_rel18_ca_transmission_allowed(mutated, 0, 0, 0, 0)
    mutated = valid
    mutated.carrier0_psfch_period_slots = 2
    with assert_raises():
        _ = nr_sl_rel18_ca_transmission_allowed(mutated, 0, 0, 0, 0)
    mutated = valid
    mutated.carrier1_psfch_period_slots = 3
    with assert_raises():
        _ = nr_sl_rel18_ca_transmission_allowed(mutated, 0, 0, 0, 0)
    mutated = valid
    mutated.carrier0_psfch_phase_slots = 2
    with assert_raises():
        _ = nr_sl_rel18_ca_transmission_allowed(mutated, 0, 0, 0, 0)
    mutated = valid
    mutated.carrier1_psfch_phase_slots = Int.MIN
    with assert_raises():
        _ = nr_sl_rel18_ca_transmission_allowed(mutated, 0, 0, 0, 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
