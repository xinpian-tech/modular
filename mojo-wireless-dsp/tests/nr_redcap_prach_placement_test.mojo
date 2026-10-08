"""Independent Rel-17 RedCap PRACH initial-BWP placement evidence."""

from std.testing import assert_equal, assert_true, assert_raises, TestSuite
from wireless_dsp.wireless.nr.prach import (
    PRACH_FORMAT_A2,
    PRACH_SET_UNRESTRICTED,
    nr_prach_format_parameters,
)
from wireless_dsp.wireless.nr.redcap import (
    NR_FREQUENCY_RANGE_FR1,
    NR_FREQUENCY_RANGE_FR2,
    NRRedCapInitialBWP,
    NRRedCapRel17Capabilities,
)
from wireless_dsp.wireless.nr.redcap_prach_placement import (
    NR_REDCAP_PRACH_SOURCE_MSG1,
    NR_REDCAP_PRACH_SOURCE_MSGA,
    nr_redcap_rel17_prach_frequency_placement,
    nr_redcap_rel17_prach_placed_composite,
    nr_redcap_rel17_prach_resource_allocation,
)


def _capabilities(
    *,
    frequency_range: Int = NR_FREQUENCY_RANGE_FR1,
    two_step: Bool = False,
) raises -> NRRedCapRel17Capabilities:
    return NRRedCapRel17Capabilities(
        frequency_range,
        20.0 if frequency_range == NR_FREQUENCY_RANGE_FR1 else 100.0,
        1 if frequency_range == NR_FREQUENCY_RANGE_FR1 else 2,
        1,
        supports_two_step_rach=two_step,
    )


def test_msg1_frequency_occasions_static_clause_geometry() raises:
    var capabilities = _capabilities()
    var bwp = NRRedCapInitialBWP(12, 51, 3500000, 30)
    for index in range(4):
        var placement = nr_redcap_rel17_prach_frequency_placement(
            capabilities, bwp, 106, 3, index, 4, 6
        )
        var expected_relative = 3 + index * 6
        var expected_crb = 12 + expected_relative
        assert_equal(placement.source, NR_REDCAP_PRACH_SOURCE_MSG1)
        assert_equal(placement.frequency_occasion_index, index)
        assert_equal(placement.frequency_occasion_count, 4)
        assert_equal(placement.resource_blocks, 6)
        assert_equal(placement.start_prb_in_initial_bwp, expected_relative)
        assert_equal(placement.start_common_resource_block, expected_crb)
        assert_equal(placement.end_common_resource_block_exclusive, expected_crb + 6)
        assert_equal(placement.lowest_common_grid_subcarrier, 12 * expected_crb)


def test_complete_redcap_applicable_table_6_3_3_2_1_rows() raises:
    var fr1 = _capabilities()
    var sequence_lengths: List[Int] = [
        839, 839, 839, 839, 839, 839,
        139, 139, 139, 139, 139, 139, 139,
    ]
    var prach_spacings_hz: List[Int] = [
        1250, 1250, 1250, 5000, 5000, 5000,
        15000, 15000, 15000, 30000, 30000, 30000, 60000,
    ]
    var pusch_spacings_khz: List[Int] = [
        15, 30, 60, 15, 30, 60, 15, 30, 60, 15, 30, 60, 60,
    ]
    var resource_blocks: List[Int] = [
        6, 3, 2, 24, 12, 6, 12, 6, 3, 24, 12, 6, 12,
    ]
    var k_bars: List[Int] = [
        7, 1, 133, 12, 10, 7, 2, 2, 2, 2, 2, 2, 2,
    ]
    for index in range(len(sequence_lengths)):
        var row = nr_redcap_rel17_prach_resource_allocation(
            fr1,
            sequence_lengths[index],
            prach_spacings_hz[index],
            pusch_spacings_khz[index],
        )
        assert_equal(row.sequence_length, sequence_lengths[index])
        assert_equal(
            row.prach_subcarrier_spacing_hz, prach_spacings_hz[index]
        )
        assert_equal(
            row.pusch_subcarrier_spacing_khz, pusch_spacings_khz[index]
        )
        assert_equal(row.resource_blocks, resource_blocks[index])
        assert_equal(row.k_bar, k_bars[index])

    var fr2 = _capabilities(frequency_range=NR_FREQUENCY_RANGE_FR2)
    var fr2_prach_spacings_hz: List[Int] = [60000, 60000, 120000, 120000]
    var fr2_pusch_spacings_khz: List[Int] = [60, 120, 60, 120]
    var fr2_resource_blocks: List[Int] = [12, 6, 24, 12]
    for index in range(len(fr2_prach_spacings_hz)):
        var row = nr_redcap_rel17_prach_resource_allocation(
            fr2,
            139,
            fr2_prach_spacings_hz[index],
            fr2_pusch_spacings_khz[index],
        )
        assert_equal(row.resource_blocks, fr2_resource_blocks[index])
        assert_equal(row.k_bar, 2)

    with assert_raises():
        _ = nr_redcap_rel17_prach_resource_allocation(fr1, 139, 120000, 60)
    with assert_raises():
        _ = nr_redcap_rel17_prach_resource_allocation(fr2, 839, 1250, 60)
    with assert_raises():
        _ = nr_redcap_rel17_prach_resource_allocation(fr2, 571, 480000, 120)


def test_msga_placed_composite_owns_real_normalized_checkpoints() raises:
    var capabilities = _capabilities(two_step=True)
    var bwp = NRRedCapInitialBWP(7, 51, 3500000, 30)
    var parameters = nr_prach_format_parameters(
        PRACH_FORMAT_A2, numerology=1, sequence_length=139
    )
    var testcase = String("redcap-msga-bwp-composite")
    var result = nr_redcap_rel17_prach_placed_composite(
        capabilities,
        bwp,
        106,
        5,
        1,
        2,
        parameters,
        0,
        13,
        PRACH_SET_UNRESTRICTED,
        7,
        two_step_random_access=True,
        preamble_count=12,
        testcase_id=testcase,
    )
    testcase.write("-mutated")
    assert_equal(result.placement.source, NR_REDCAP_PRACH_SOURCE_MSGA)
    assert_equal(result.placement.start_prb_in_initial_bwp, 17)
    assert_equal(result.placement.start_common_resource_block, 24)
    assert_equal(result.normalized.allocation.preamble_index, 7)
    assert_equal(result.normalized.detection.preamble_index, 7)
    assert_equal(len(result.normalized.checkpoint_metadata), 9)
    for index in range(len(result.normalized.checkpoint_metadata)):
        assert_equal(
            result.normalized.checkpoint_metadata[index].testcase_id,
            "redcap-msga-bwp-composite",
        )


def test_seeded_frequency_geometry_matches_independent_int128_oracle() raises:
    var capabilities = _capabilities()
    var seed = UInt64(0x243F6A8885A308D3)
    var counts: List[Int] = [1, 2, 4, 8]
    for _ in range(257):
        seed = seed * UInt64(6364136223846793005) + UInt64(1)
        var count = counts[Int(seed & UInt64(3))]
        var allocation = 1 + Int((seed >> 5) % UInt64(5))
        var frequency_start = Int((seed >> 11) % UInt64(4))
        var needed = frequency_start + count * allocation
        var bwp_size = needed + Int((seed >> 19) % UInt64(9))
        var bwp_start = Int((seed >> 27) % UInt64(20))
        var carrier = bwp_start + bwp_size + 5
        var index = Int((seed >> 33) % UInt64(count))
        var bwp = NRRedCapInitialBWP(bwp_start, bwp_size, 3500000, 15)
        var actual = nr_redcap_rel17_prach_frequency_placement(
            capabilities,
            bwp,
            carrier,
            frequency_start,
            index,
            count,
            allocation,
        )
        var expected_relative = Int128(frequency_start) + Int128(index) * (
            Int128(allocation)
        )
        var expected_crb = Int128(bwp_start) + expected_relative
        assert_equal(actual.start_prb_in_initial_bwp, Int(expected_relative))
        assert_equal(actual.start_common_resource_block, Int(expected_crb))
        assert_equal(
            actual.end_common_resource_block_exclusive,
            Int(expected_crb + Int128(allocation)),
        )
        assert_equal(
            actual.lowest_common_grid_subcarrier, Int(expected_crb * 12)
        )


def test_mutable_profile_containment_and_overflow_edges() raises:
    var capabilities = _capabilities()
    var bwp = NRRedCapInitialBWP(10, 24, 3500000, 30)
    _ = nr_redcap_rel17_prach_frequency_placement(
        capabilities, bwp, 52, 0, 0, 4, 6
    )
    with assert_raises():
        _ = nr_redcap_rel17_prach_frequency_placement(
            capabilities, bwp, 52, -1, 0, 4, 6
        )
    with assert_raises():
        _ = nr_redcap_rel17_prach_frequency_placement(
            capabilities, bwp, 52, 0, 0, 3, 6
        )
    with assert_raises():
        _ = nr_redcap_rel17_prach_frequency_placement(
            capabilities, bwp, 52, 0, 4, 4, 6
        )
    with assert_raises():
        _ = nr_redcap_rel17_prach_frequency_placement(
            capabilities, bwp, 52, 1, 0, 4, 6
        )
    with assert_raises():
        _ = nr_redcap_rel17_prach_frequency_placement(
            capabilities, bwp, 52, Int.MAX, 0, 8, Int.MAX
        )
    with assert_raises():
        _ = nr_redcap_rel17_prach_frequency_placement(
            capabilities, bwp, 52, 0, 0, 1, 0
        )
    with assert_raises():
        _ = nr_redcap_rel17_prach_frequency_placement(
            capabilities, bwp, 52, 0, 0, 1, 6,
            two_step_random_access=True,
        )

    capabilities.support_of_redcap = False
    with assert_raises():
        _ = nr_redcap_rel17_prach_frequency_placement(
            capabilities, bwp, 52, 0, 0, 1, 6
        )
    capabilities = _capabilities()
    bwp.subcarrier_spacing_khz = 120
    with assert_raises():
        _ = nr_redcap_rel17_prach_frequency_placement(
            capabilities, bwp, 52, 0, 0, 1, 6
        )
    bwp = NRRedCapInitialBWP(40, 20, 3500000, 30)
    with assert_raises():
        _ = nr_redcap_rel17_prach_frequency_placement(
            capabilities, bwp, 52, 0, 0, 1, 6
        )

    var fr2 = _capabilities(frequency_range=NR_FREQUENCY_RANGE_FR2)
    var fr2_bwp = NRRedCapInitialBWP(0, 66, 28000000, 120)
    assert_equal(
        nr_redcap_rel17_prach_frequency_placement(
            fr2, fr2_bwp, 132, 2, 0, 1, 8
        ).start_prb_in_initial_bwp,
        2,
    )

    var parameters = nr_prach_format_parameters(
        PRACH_FORMAT_A2, numerology=1, sequence_length=139
    )
    with assert_raises():
        _ = nr_redcap_rel17_prach_placed_composite(
            capabilities,
            NRRedCapInitialBWP(0, 24, 3500000, 30),
            52,
            0,
            2,
            2,
            parameters,
            0,
            13,
            PRACH_SET_UNRESTRICTED,
            3,
            preamble_count=8,
        )


def test_bwp_shift_changes_only_absolute_placement_not_prach_samples() raises:
    var capabilities = _capabilities()
    var first_bwp = NRRedCapInitialBWP(4, 40, 3500000, 30)
    var second_bwp = NRRedCapInitialBWP(17, 40, 3500000, 30)
    var parameters = nr_prach_format_parameters(
        PRACH_FORMAT_A2, numerology=1, sequence_length=139
    )
    var first = nr_redcap_rel17_prach_placed_composite(
        capabilities, first_bwp, 80, 2, 1, 2,
        parameters, 0, 13, PRACH_SET_UNRESTRICTED, 3,
        preamble_count=8,
    )
    var second = nr_redcap_rel17_prach_placed_composite(
        capabilities, second_bwp, 80, 2, 1, 2,
        parameters, 0, 13, PRACH_SET_UNRESTRICTED, 3,
        preamble_count=8,
    )
    assert_equal(
        second.placement.start_common_resource_block
        - first.placement.start_common_resource_block,
        13,
    )
    assert_equal(
        first.placement.start_prb_in_initial_bwp,
        second.placement.start_prb_in_initial_bwp,
    )
    assert_equal(
        len(first.normalized.normalized_waveform),
        len(second.normalized.normalized_waveform),
    )
    for index in range(len(first.normalized.normalized_waveform)):
        assert_equal(
            first.normalized.normalized_waveform[index].re,
            second.normalized.normalized_waveform[index].re,
        )
        assert_equal(
            first.normalized.normalized_waveform[index].im,
            second.normalized.normalized_waveform[index].im,
        )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
