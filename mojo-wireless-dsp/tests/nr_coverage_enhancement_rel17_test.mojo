"""Clause and property evidence for Rel-17 NR coverage enhancement."""

from std.testing import assert_equal, assert_true, assert_raises, TestSuite
from wireless_dsp.wireless.nr.coverage_enhancement_rel17 import (
    NR_COV_ENH_MAPPING_TYPE_A,
    NR_COV_ENH_MAPPING_TYPE_B,
    NR_COV_ENH_CP_NORMAL,
    NR_COV_ENH_CP_EXTENDED,
    NR_COV_ENH_REPETITION_TYPE_A,
    NR_COV_ENH_REPETITION_TYPE_B,
    NR_COV_ENH_SPECTRUM_PAIRED_OR_SUL,
    NR_COV_ENH_SPECTRUM_UNPAIRED,
    NRCoverageEnhancementTBMSProfile,
    nr_cov_enh_rel17_valid_pusch_allocation,
    nr_cov_enh_rel17_msg3_repetition_count,
    nr_cov_enh_rel17_tbms_profile,
    nr_cov_enh_rel17_select_tbms_slots,
    nr_cov_enh_rel17_pusch_nominal_tdw_length_slots,
    nr_cov_enh_rel17_pusch_nominal_tdw_ids,
    nr_cov_enh_rel17_dmrs_bundling_gap_event,
)


def _literal_sl_oracle(
    mapping_type: Int,
    cyclic_prefix: Int,
    repetition_type: Int,
    start: Int,
    length: Int,
) -> Bool:
    if start < 0 or length < 1:
        return False
    var symbols = 14 if cyclic_prefix == 0 else 12
    if mapping_type == 0:
        return (
            repetition_type == 0
            and start == 0
            and length >= 4
            and length <= symbols
        )
    if start < 0 or start >= symbols or length < 1 or length > symbols:
        return False
    var limit = symbols if repetition_type == 0 else 2 * symbols - 1
    return start + length <= limit


def test_complete_valid_sl_table_against_literal_oracle() raises:
    for mapping_type in range(2):
        for cyclic_prefix in range(2):
            for repetition_type in range(2):
                for start in range(-1, 16):
                    for length in range(0, 16):
                        assert_equal(
                            nr_cov_enh_rel17_valid_pusch_allocation(
                                mapping_type,
                                cyclic_prefix,
                                repetition_type,
                                start,
                                length,
                            ),
                            _literal_sl_oracle(
                                mapping_type,
                                cyclic_prefix,
                                repetition_type,
                                start,
                                length,
                            ),
                        )


def test_msg3_and_tbms_static_clause_tables() raises:
    var absent: List[Int] = []
    for codepoint in range(4):
        assert_equal(
            nr_cov_enh_rel17_msg3_repetition_count(
                codepoint, Span(absent)
            ),
            codepoint + 1,
        )
    var configured: List[Int] = [2, 4, 8, 16]
    for codepoint in range(4):
        assert_equal(
            nr_cov_enh_rel17_msg3_repetition_count(
                codepoint, Span(configured)
            ),
            configured[codepoint],
        )
    var legal_n: List[Int] = [2, 4, 8]
    var legal_k: List[Int] = [1, 2, 3, 4, 7, 8, 12, 16, 20, 24, 28, 32]
    for n_index in range(len(legal_n)):
        for k_index in range(len(legal_k)):
            var n = legal_n[n_index]
            var k = legal_k[k_index]
            if Int128(n) * Int128(k) <= 32:
                var profile = nr_cov_enh_rel17_tbms_profile(n, k)
                assert_equal(profile.number_of_slots, n)
                assert_equal(profile.number_of_repetitions, k)
                assert_equal(profile.required_slot_count, n * k)


def test_slot_selection_and_nominal_tdw_static_oracles() raises:
    var eligibility: List[UInt8] = [1, 0, 1, 1, 0, 1, 1, 1]
    var profile = nr_cov_enh_rel17_tbms_profile(2, 2)
    var paired = nr_cov_enh_rel17_select_tbms_slots(
        10,
        Span(eligibility),
        profile,
        NR_COV_ENH_SPECTRUM_PAIRED_OR_SUL,
    )
    var expected_paired: List[Int] = [10, 11, 12, 13]
    assert_equal(paired, expected_paired)
    var unpaired = nr_cov_enh_rel17_select_tbms_slots(
        10,
        Span(eligibility),
        profile,
        NR_COV_ENH_SPECTRUM_UNPAIRED,
    )
    var expected_unpaired: List[Int] = [10, 12, 13, 15]
    assert_equal(unpaired, expected_unpaired)

    assert_equal(
        nr_cov_enh_rel17_pusch_nominal_tdw_length_slots(0, 4, 10, 15),
        4,
    )
    assert_equal(
        nr_cov_enh_rel17_pusch_nominal_tdw_length_slots(4, 8, 10, 15),
        4,
    )
    var ids = nr_cov_enh_rel17_pusch_nominal_tdw_ids(
        Span(unpaired), 3
    )
    var expected_ids: List[Int] = [0, 0, 1, 1]
    assert_equal(ids, expected_ids)
    _check_seeded_slot_selection_and_tdw_independent_oracles()


def _check_seeded_slot_selection_and_tdw_independent_oracles() raises:
    var legal_n: List[Int] = [2, 4, 8]
    var legal_k: List[Int] = [1, 2, 4]
    var maximums: List[Int] = [2, 4, 8, 16, 32]
    var seed = UInt64(0x243F6A8885A308D3)
    for case_index in range(257):
        seed = seed * UInt64(6364136223846793005) + UInt64(1)
        var n = legal_n[Int(seed % UInt64(len(legal_n)))]
        var k = legal_k[Int((seed >> 8) % UInt64(len(legal_k)))]
        var profile = nr_cov_enh_rel17_tbms_profile(n, k)
        var start_slot = Int((seed >> 24) % UInt64(100000))
        var eligibility = List[UInt8](capacity=96)
        for _ in range(96):
            seed = seed * UInt64(6364136223846793005) + UInt64(1)
            eligibility.append(UInt8(0 if seed % UInt64(5) == 0 else 1))

        var paired = nr_cov_enh_rel17_select_tbms_slots(
            start_slot,
            Span(eligibility),
            profile,
            NR_COV_ENH_SPECTRUM_PAIRED_OR_SUL,
        )
        assert_equal(len(paired), profile.required_slot_count)
        for index in range(len(paired)):
            assert_equal(paired[index], start_slot + index)

        var expected_unpaired = List[Int](
            capacity=profile.required_slot_count
        )
        for offset in range(len(eligibility)):
            if eligibility[offset] == 1:
                expected_unpaired.append(start_slot + offset)
                if len(expected_unpaired) == profile.required_slot_count:
                    break
        var unpaired = nr_cov_enh_rel17_select_tbms_slots(
            start_slot,
            Span(eligibility),
            profile,
            NR_COV_ENH_SPECTRUM_UNPAIRED,
        )
        assert_equal(unpaired, expected_unpaired)

        var maximum = maximums[
            Int((seed >> 40) % UInt64(len(maximums)))
        ]
        var configured = maximum if (case_index & 1) == 1 else 0
        var span = unpaired[len(unpaired) - 1] - unpaired[0] + 1
        var expected_length = (
            configured
            if configured != 0
            else maximum if maximum < span else span
        )
        var actual_length = nr_cov_enh_rel17_pusch_nominal_tdw_length_slots(
            configured,
            maximum,
            unpaired[0],
            unpaired[len(unpaired) - 1],
        )
        assert_equal(actual_length, expected_length)

        var expected_ids = List[Int](capacity=len(unpaired))
        var expected_window_id = 0
        var expected_window_end = unpaired[0] + actual_length
        for index in range(len(unpaired)):
            if unpaired[index] >= expected_window_end:
                expected_window_id += 1
                expected_window_end = unpaired[index] + actual_length
            expected_ids.append(expected_window_id)
        assert_equal(
            nr_cov_enh_rel17_pusch_nominal_tdw_ids(
                Span(unpaired), actual_length
            ),
            expected_ids,
        )


def test_dmrs_bundling_gap_event_exhaustive() raises:
    for cp in range(2):
        var limit = 13 if cp == NR_COV_ENH_CP_NORMAL else 11
        for gap in range(1, 20):
            for capability_int in range(2):
                for other_int in range(2):
                    var capability = capability_int == 1
                    var other = other_int == 1
                    var expected = (
                        gap > limit if capability else gap != 0
                    )
                    if other and gap <= 13:
                        expected = True
                    assert_equal(
                        nr_cov_enh_rel17_dmrs_bundling_gap_event(
                            cp, gap, capability, other
                        ),
                        expected,
                    )
        for capability_int in range(2):
            var capability = capability_int == 1
            assert_equal(
                nr_cov_enh_rel17_dmrs_bundling_gap_event(
                    cp, 0, capability, False
                ),
                False,
            )
            with assert_raises():
                _ = nr_cov_enh_rel17_dmrs_bundling_gap_event(
                    cp, 0, capability, True
                )


def test_public_mutation_invalid_and_overflow_edges() raises:
    with assert_raises():
        _ = nr_cov_enh_rel17_valid_pusch_allocation(9, 0, 0, 0, 4)
    with assert_raises():
        _ = nr_cov_enh_rel17_valid_pusch_allocation(0, 9, 0, 0, 4)
    with assert_raises():
        _ = nr_cov_enh_rel17_valid_pusch_allocation(0, 0, 9, 0, 4)
    var absent: List[Int] = []
    with assert_raises():
        _ = nr_cov_enh_rel17_msg3_repetition_count(4, Span(absent))
    var short_list: List[Int] = [1, 2, 3]
    with assert_raises():
        _ = nr_cov_enh_rel17_msg3_repetition_count(0, Span(short_list))
    var zero_list: List[Int] = [1, 2, 0, 4]
    with assert_raises():
        _ = nr_cov_enh_rel17_msg3_repetition_count(0, Span(zero_list))
    var nonstandard_list: List[Int] = [1, 2, 5, 8]
    with assert_raises():
        _ = nr_cov_enh_rel17_msg3_repetition_count(
            0, Span(nonstandard_list)
        )
    with assert_raises():
        _ = nr_cov_enh_rel17_tbms_profile(3, 1)
    with assert_raises():
        _ = nr_cov_enh_rel17_tbms_profile(2, 5)
    with assert_raises():
        _ = nr_cov_enh_rel17_tbms_profile(Int.MAX, Int.MAX)

    var profile = nr_cov_enh_rel17_tbms_profile(2, 2)
    profile.required_slot_count = 3
    var eligibility: List[UInt8] = [1, 1, 1, 1]
    with assert_raises():
        _ = nr_cov_enh_rel17_select_tbms_slots(
            0, Span(eligibility), profile, 0
        )
    profile.required_slot_count = 4
    var corrupt: List[UInt8] = [1, 2, 1, 1]
    with assert_raises():
        _ = nr_cov_enh_rel17_select_tbms_slots(
            0, Span(corrupt), profile, 0
        )
    with assert_raises():
        _ = nr_cov_enh_rel17_select_tbms_slots(
            Int.MAX - 1, Span(eligibility), profile, 0
        )
    var unordered: List[Int] = [1, 1]
    with assert_raises():
        _ = nr_cov_enh_rel17_pusch_nominal_tdw_ids(Span(unordered), 1)
    var one_slot: List[Int] = [0]
    with assert_raises():
        _ = nr_cov_enh_rel17_pusch_nominal_tdw_ids(Span(one_slot), 0)
    with assert_raises():
        _ = nr_cov_enh_rel17_pusch_nominal_tdw_ids(Span(one_slot), 33)
    with assert_raises():
        _ = nr_cov_enh_rel17_pusch_nominal_tdw_length_slots(0, 1, 2, 1)
    with assert_raises():
        _ = nr_cov_enh_rel17_pusch_nominal_tdw_length_slots(0, 3, 1, 2)
    with assert_raises():
        _ = nr_cov_enh_rel17_pusch_nominal_tdw_length_slots(1, 4, 1, 2)
    with assert_raises():
        _ = nr_cov_enh_rel17_pusch_nominal_tdw_length_slots(5, 4, 1, 8)
    with assert_raises():
        _ = nr_cov_enh_rel17_pusch_nominal_tdw_length_slots(33, 32, 1, 8)
    with assert_raises():
        _ = nr_cov_enh_rel17_dmrs_bundling_gap_event(0, -1, True, False)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
