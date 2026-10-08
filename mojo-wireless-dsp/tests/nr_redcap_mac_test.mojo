"""Independent clause, edge, and property evidence for Rel-17 RedCap MAC."""

from std.testing import assert_equal, assert_raises, TestSuite
from std.utils.numerics import inf, nan
from wireless_dsp.wireless.nr.redcap_mac import (
    NR_REDCAP_MAC_PROFILE_ORDINARY_NR,
    NR_REDCAP_MAC_PROFILE_EREDCAP_REL18,
    NR_REDCAP_RA_FEATURE_REDCAP,
    NR_REDCAP_RA_FEATURE_SLICING,
    NR_REDCAP_RA_FEATURE_SMALL_DATA,
    NR_REDCAP_RA_FEATURE_MSG3_REPETITION,
    NR_REDCAP_RA_TYPE_4_STEP,
    NR_REDCAP_RA_TYPE_2_STEP,
    NR_REDCAP_MAC_BWP_ORDINARY_INITIAL,
    NR_REDCAP_MAC_BWP_REDCAP_INITIAL,
    NR_REDCAP_MAC_BWP_DEFAULT,
    NRRedCapRAResourceSetGroup,
    nr_redcap_rel17_msg3_repetition_applicable,
    nr_redcap_rel17_ra_resource_set_available,
    nr_redcap_rel17_select_ra_resource_set_group,
    nr_redcap_rel17_select_ra_resource_set,
    nr_redcap_rel17_random_access_uplink_bwp_source,
    nr_redcap_rel17_random_access_downlink_bwp_source,
    nr_redcap_rel17_bwp_inactivity_target,
    nr_redcap_rel17_ul_ccch_lcid,
)


def _has_feature(mask: Int, feature: Int) -> Bool:
    return (mask & feature) != 0


def _literal_availability_oracle(
    configured: Int,
    applicable: Int,
    nsag_list_configured: Bool,
    nsag_matches: Bool,
) -> Bool:
    # Deliberately decomposed into the four literal 38.321 5.1.1c rules; this
    # does not reuse the implementation's subset expression.
    if _has_feature(configured, NR_REDCAP_RA_FEATURE_REDCAP) and not (
        _has_feature(applicable, NR_REDCAP_RA_FEATURE_REDCAP)
    ):
        return False
    if _has_feature(configured, NR_REDCAP_RA_FEATURE_SMALL_DATA) and not (
        _has_feature(applicable, NR_REDCAP_RA_FEATURE_SMALL_DATA)
    ):
        return False
    if nsag_list_configured and not nsag_matches:
        return False
    if nsag_list_configured and not (
        _has_feature(applicable, NR_REDCAP_RA_FEATURE_SLICING)
    ):
        return False
    if _has_feature(configured, NR_REDCAP_RA_FEATURE_MSG3_REPETITION) and not (
        _has_feature(applicable, NR_REDCAP_RA_FEATURE_MSG3_REPETITION)
    ):
        return False
    return True


def _combination_is_present(
    configured: Span[Int, ...], available: Span[UInt8, ...], mask: Int
) -> Bool:
    for index in range(len(configured)):
        if available[index] == 1 and configured[index] == mask:
            return True
    return False


def _candidate_is_higher_priority(
    candidate: Int,
    incumbent: Int,
    applicable: Int,
    priorities: Span[Int, ...],
) -> Bool:
    # Independent lexicographic reading of 5.1.1d.  The production code uses
    # recursive filtering; this oracle compares two feature combinations.
    for priority_index in range(len(priorities)):
        var feature = priorities[priority_index]
        if not _has_feature(applicable, feature):
            continue
        var candidate_has = _has_feature(candidate, feature)
        var incumbent_has = _has_feature(incumbent, feature)
        if candidate_has != incumbent_has:
            return candidate_has
    return False


def _selection_mask_oracle(
    configured: Span[Int, ...],
    available: Span[UInt8, ...],
    applicable: Int,
    priorities: Span[Int, ...],
    contention_free_resources_provided: Bool,
    si_request_resources_provided: Bool,
) -> Int:
    if (
        not contention_free_resources_provided
        and not si_request_resources_provided
        and applicable != 0
    ):
        if _combination_is_present(configured, available, applicable):
            return applicable
        var best = -1
        for mask in range(1, 16):
            if not _combination_is_present(configured, available, mask):
                continue
            if best == -1 or _candidate_is_higher_priority(
                mask, best, applicable, priorities
            ):
                best = mask
        return 0 if best == -1 else best
    if (
        contention_free_resources_provided
        and _has_feature(applicable, NR_REDCAP_RA_FEATURE_REDCAP)
        and _combination_is_present(
            configured, available, NR_REDCAP_RA_FEATURE_REDCAP
        )
    ):
        return NR_REDCAP_RA_FEATURE_REDCAP
    return 0


def test_msg3_repetition_applicability_literal_boundaries() raises:
    assert_equal(
        nr_redcap_rel17_msg3_repetition_applicable(
            True, False, nan[DType.float64](), nan[DType.float64]()
        ),
        True,
    )
    assert_equal(
        nr_redcap_rel17_msg3_repetition_applicable(
            False, True, nan[DType.float64](), nan[DType.float64]()
        ),
        False,
    )
    assert_equal(
        nr_redcap_rel17_msg3_repetition_applicable(True, True, -101.0, -100.0),
        True,
    )
    # The clause uses strict less-than: equality and a higher RSRP are false.
    assert_equal(
        nr_redcap_rel17_msg3_repetition_applicable(True, True, -100.0, -100.0),
        False,
    )
    assert_equal(
        nr_redcap_rel17_msg3_repetition_applicable(True, True, -99.0, -100.0),
        False,
    )
    with assert_raises():
        _ = nr_redcap_rel17_msg3_repetition_applicable(
            False, False, -100.0, -100.0
        )
    with assert_raises():
        _ = nr_redcap_rel17_msg3_repetition_applicable(
            True, True, nan[DType.float64](), -100.0
        )
    with assert_raises():
        _ = nr_redcap_rel17_msg3_repetition_applicable(
            True, True, -100.0, inf[DType.float64]()
        )


def test_ra_resource_availability_exhaustive_independent_oracle() raises:
    for configured in range(16):
        var has_nsag_list = _has_feature(
            configured, NR_REDCAP_RA_FEATURE_SLICING
        )
        for applicable in range(16):
            for match_value in range(2):
                if not has_nsag_list and match_value == 1:
                    continue
                var nsag_matches = has_nsag_list and match_value == 1
                if nsag_matches and not _has_feature(
                    applicable, NR_REDCAP_RA_FEATURE_SLICING
                ):
                    with assert_raises():
                        _ = nr_redcap_rel17_ra_resource_set_available(
                            configured,
                            applicable,
                            nsag_list_configured=True,
                            nsag_matches=True,
                        )
                    continue
                assert_equal(
                    nr_redcap_rel17_ra_resource_set_available(
                        configured,
                        applicable,
                        nsag_list_configured=has_nsag_list,
                        nsag_matches=nsag_matches,
                    ),
                    _literal_availability_oracle(
                        configured,
                        applicable,
                        has_nsag_list,
                        nsag_matches,
                    ),
                )

    # Slicing is represented by NSAG-list presence, not an independent flag.
    with assert_raises():
        _ = nr_redcap_rel17_ra_resource_set_available(
            NR_REDCAP_RA_FEATURE_SLICING,
            NR_REDCAP_RA_FEATURE_SLICING,
        )
    with assert_raises():
        _ = nr_redcap_rel17_ra_resource_set_available(
            0, 0, nsag_list_configured=True
        )


def test_ra_group_selection_static_clause_branches() raises:
    var redcap = NR_REDCAP_RA_FEATURE_REDCAP
    var small_data = NR_REDCAP_RA_FEATURE_SMALL_DATA
    var msg3 = NR_REDCAP_RA_FEATURE_MSG3_REPETITION
    var masks: List[Int] = [
        0,
        0,
        redcap,
        redcap,
        small_data,
        small_data,
        redcap | small_data,
        redcap | small_data,
        msg3,
    ]
    var ra_types: List[Int] = [
        NR_REDCAP_RA_TYPE_4_STEP,
        NR_REDCAP_RA_TYPE_2_STEP,
        NR_REDCAP_RA_TYPE_4_STEP,
        NR_REDCAP_RA_TYPE_2_STEP,
        NR_REDCAP_RA_TYPE_4_STEP,
        NR_REDCAP_RA_TYPE_2_STEP,
        NR_REDCAP_RA_TYPE_4_STEP,
        NR_REDCAP_RA_TYPE_2_STEP,
        NR_REDCAP_RA_TYPE_4_STEP,
    ]
    var available: List[UInt8] = [1, 1, 1, 1, 1, 1, 1, 1, 0]
    var redcap_first: List[Int] = [redcap, small_data, msg3]
    var small_data_first: List[Int] = [small_data, redcap, msg3]
    var applicable = redcap | small_data

    # The exact full-feature combination selects both RA-type members.
    var selected = nr_redcap_rel17_select_ra_resource_set_group(
        Span(masks),
        Span(ra_types),
        Span(available),
        applicable,
        Span(redcap_first),
    )
    assert_equal(selected.configured_features, applicable)
    assert_equal(selected.four_step_index, 6)
    assert_equal(selected.two_step_index, 7)
    assert_equal(selected.selected_set_count(), 2)

    available[6] = 0
    available[7] = 0
    selected = nr_redcap_rel17_select_ra_resource_set_group(
        Span(masks),
        Span(ra_types),
        Span(available),
        applicable,
        Span(small_data_first),
    )
    assert_equal(selected.configured_features, small_data)
    assert_equal(selected.four_step_index, 4)
    assert_equal(selected.two_step_index, 5)

    # A procedure may be an SI request without dedicated SI resources.  With
    # the resource-provided flag false, ordinary feature selection still runs.
    selected = nr_redcap_rel17_select_ra_resource_set_group(
        Span(masks),
        Span(ra_types),
        Span(available),
        applicable,
        Span(redcap_first),
        si_request_resources_provided=False,
    )
    assert_equal(selected.configured_features, redcap)

    selected = nr_redcap_rel17_select_ra_resource_set_group(
        Span(masks),
        Span(ra_types),
        Span(available),
        applicable,
        Span(redcap_first),
        si_request_resources_provided=True,
    )
    assert_equal(selected.configured_features, 0)
    assert_equal(selected.four_step_index, 0)
    assert_equal(selected.two_step_index, 1)

    selected = nr_redcap_rel17_select_ra_resource_set_group(
        Span(masks),
        Span(ra_types),
        Span(available),
        applicable,
        Span(redcap_first),
        contention_free_resources_provided=True,
    )
    assert_equal(selected.configured_features, redcap)
    assert_equal(selected.four_step_index, 2)
    assert_equal(selected.two_step_index, 3)

    # Clause order gives the contention-free RedCap branch precedence if the
    # decoded resource-provided flags are both true.
    selected = nr_redcap_rel17_select_ra_resource_set_group(
        Span(masks),
        Span(ra_types),
        Span(available),
        applicable,
        Span(redcap_first),
        contention_free_resources_provided=True,
        si_request_resources_provided=True,
    )
    assert_equal(selected.configured_features, redcap)

    for index in range(2, len(available)):
        available[index] = 0
    selected = nr_redcap_rel17_select_ra_resource_set_group(
        Span(masks),
        Span(ra_types),
        Span(available),
        applicable,
        Span(redcap_first),
    )
    assert_equal(selected.configured_features, 0)


def test_ra_priority_multistage_and_seeded_axis_oracle() raises:
    var redcap = NR_REDCAP_RA_FEATURE_REDCAP
    var slicing = NR_REDCAP_RA_FEATURE_SLICING
    var small_data = NR_REDCAP_RA_FEATURE_SMALL_DATA
    var base_masks: List[Int] = [
        0,
        0,
        redcap | slicing,
        redcap | slicing,
        redcap | small_data,
        redcap | small_data,
        slicing | small_data,
        slicing | small_data,
        redcap,
        redcap,
    ]
    var base_types: List[Int] = [
        NR_REDCAP_RA_TYPE_4_STEP,
        NR_REDCAP_RA_TYPE_2_STEP,
        NR_REDCAP_RA_TYPE_4_STEP,
        NR_REDCAP_RA_TYPE_2_STEP,
        NR_REDCAP_RA_TYPE_4_STEP,
        NR_REDCAP_RA_TYPE_2_STEP,
        NR_REDCAP_RA_TYPE_4_STEP,
        NR_REDCAP_RA_TYPE_2_STEP,
        NR_REDCAP_RA_TYPE_4_STEP,
        NR_REDCAP_RA_TYPE_2_STEP,
    ]
    var seed = UInt64(0x38_321_17_15_5EED)
    for _ in range(257):
        var masks = base_masks.copy()
        var ra_types = base_types.copy()
        var available = List[UInt8](length=len(masks), fill=1)
        var priorities: List[Int] = [redcap, slicing, small_data]

        var cursor = len(masks) - 1
        while cursor > 0:
            seed = (
                seed * UInt64(6364136223846793005)
                + UInt64(1442695040888963407)
            )
            var swap_index = Int(seed % UInt64(cursor + 1))
            var mask_temp = masks[cursor]
            masks[cursor] = masks[swap_index]
            masks[swap_index] = mask_temp
            var type_temp = ra_types[cursor]
            ra_types[cursor] = ra_types[swap_index]
            ra_types[swap_index] = type_temp
            cursor -= 1

        cursor = len(priorities) - 1
        while cursor > 0:
            seed = (
                seed * UInt64(2862933555777941757)
                + UInt64(3037000493)
            )
            var swap_index = Int(seed % UInt64(cursor + 1))
            var priority_temp = priorities[cursor]
            priorities[cursor] = priorities[swap_index]
            priorities[swap_index] = priority_temp
            cursor -= 1

        var applicable = redcap | slicing | small_data
        var expected_mask = _selection_mask_oracle(
            Span(masks),
            Span(available),
            applicable,
            Span(priorities),
            False,
            False,
        )
        var selected = nr_redcap_rel17_select_ra_resource_set_group(
            Span(masks),
            Span(ra_types),
            Span(available),
            applicable,
            Span(priorities),
        )
        assert_equal(selected.configured_features, expected_mask)
        assert_equal(masks[selected.four_step_index], expected_mask)
        assert_equal(masks[selected.two_step_index], expected_mask)
        assert_equal(
            ra_types[selected.four_step_index], NR_REDCAP_RA_TYPE_4_STEP
        )
        assert_equal(
            ra_types[selected.two_step_index], NR_REDCAP_RA_TYPE_2_STEP
        )


def test_single_ra_type_compatibility_and_group_edges() raises:
    var redcap = NR_REDCAP_RA_FEATURE_REDCAP
    var small_data = NR_REDCAP_RA_FEATURE_SMALL_DATA
    var masks: List[Int] = [0, redcap, small_data]
    var available: List[UInt8] = [1, 1, 1]
    var priorities: List[Int] = [redcap, small_data]
    assert_equal(
        nr_redcap_rel17_select_ra_resource_set(
            Span(masks),
            Span(available),
            redcap | small_data,
            Span(priorities),
        ),
        1,
    )

    var pair_masks: List[Int] = [redcap, redcap]
    var pair_types: List[Int] = [
        NR_REDCAP_RA_TYPE_4_STEP, NR_REDCAP_RA_TYPE_2_STEP
    ]
    var pair_available: List[UInt8] = [1, 1]
    var redcap_priority: List[Int] = [redcap]
    var paired = nr_redcap_rel17_select_ra_resource_set_group(
        Span(pair_masks),
        Span(pair_types),
        Span(pair_available),
        redcap,
        Span(redcap_priority),
    )
    assert_equal(paired.four_step_index, 0)
    assert_equal(paired.two_step_index, 1)

    var mutable_masks: List[Int] = [0, redcap]
    var mutable_types: List[Int] = [
        NR_REDCAP_RA_TYPE_4_STEP, NR_REDCAP_RA_TYPE_4_STEP
    ]
    var mutable_available: List[UInt8] = [1, 1]
    _ = nr_redcap_rel17_select_ra_resource_set_group(
        Span(mutable_masks),
        Span(mutable_types),
        Span(mutable_available),
        redcap,
        Span(redcap_priority),
    )
    mutable_masks[0] = redcap
    with assert_raises():
        _ = nr_redcap_rel17_select_ra_resource_set_group(
            Span(mutable_masks),
            Span(mutable_types),
            Span(mutable_available),
            redcap,
            Span(redcap_priority),
        )

    var duplicate_types: List[Int] = [
        NR_REDCAP_RA_TYPE_4_STEP, NR_REDCAP_RA_TYPE_4_STEP
    ]
    with assert_raises():
        _ = nr_redcap_rel17_select_ra_resource_set_group(
            Span(pair_masks),
            Span(duplicate_types),
            Span(pair_available),
            redcap,
            Span(redcap_priority),
        )

    var invalid_types: List[Int] = [NR_REDCAP_RA_TYPE_4_STEP, 2]
    with assert_raises():
        _ = nr_redcap_rel17_select_ra_resource_set_group(
            Span(pair_masks),
            Span(invalid_types),
            Span(pair_available),
            redcap,
            Span(redcap_priority),
        )

    var one_type: List[Int] = [NR_REDCAP_RA_TYPE_4_STEP]
    with assert_raises():
        _ = nr_redcap_rel17_select_ra_resource_set_group(
            Span(pair_masks),
            Span(one_type),
            Span(pair_available),
            redcap,
            Span(redcap_priority),
        )

    var msg3_masks: List[Int] = [0, NR_REDCAP_RA_FEATURE_MSG3_REPETITION]
    var two_step_types: List[Int] = [
        NR_REDCAP_RA_TYPE_2_STEP, NR_REDCAP_RA_TYPE_2_STEP
    ]
    var msg3_priority: List[Int] = [NR_REDCAP_RA_FEATURE_MSG3_REPETITION]
    with assert_raises():
        _ = nr_redcap_rel17_select_ra_resource_set_group(
            Span(msg3_masks),
            Span(two_step_types),
            Span(pair_available),
            NR_REDCAP_RA_FEATURE_MSG3_REPETITION,
            Span(msg3_priority),
        )

    var incomplete_priority: List[Int] = [redcap]
    with assert_raises():
        _ = nr_redcap_rel17_select_ra_resource_set(
            Span(masks),
            Span(available),
            redcap | small_data,
            Span(incomplete_priority),
        )

    var duplicate_priority: List[Int] = [redcap, redcap, small_data]
    with assert_raises():
        _ = nr_redcap_rel17_select_ra_resource_set(
            Span(masks),
            Span(available),
            redcap | small_data,
            Span(duplicate_priority),
        )

    var invalid_availability: List[UInt8] = [1, 2, 1]
    with assert_raises():
        _ = nr_redcap_rel17_select_ra_resource_set(
            Span(masks),
            Span(invalid_availability),
            redcap | small_data,
            Span(priorities),
        )

    var inconsistent_available: List[UInt8] = [1, 1, 0]
    with assert_raises():
        _ = nr_redcap_rel17_select_ra_resource_set(
            Span(masks),
            Span(inconsistent_available),
            small_data,
            Span(priorities),
        )

    var no_feature_available: List[UInt8] = [0, 0, 0]
    with assert_raises():
        _ = nr_redcap_rel17_select_ra_resource_set(
            Span(masks),
            Span(no_feature_available),
            redcap | small_data,
            Span(priorities),
        )

    var too_many_masks = List[Int](length=33, fill=0)
    var too_many_types = List[Int](length=33, fill=NR_REDCAP_RA_TYPE_4_STEP)
    var too_many_available = List[UInt8](length=33, fill=0)
    var no_priorities = List[Int]()
    with assert_raises():
        _ = nr_redcap_rel17_select_ra_resource_set_group(
            Span(too_many_masks),
            Span(too_many_types),
            Span(too_many_available),
            0,
            Span(no_priorities),
        )

    var mutable_group = NRRedCapRAResourceSetGroup(redcap, 0, -1)
    assert_equal(
        mutable_group.index_for_ra_type(NR_REDCAP_RA_TYPE_4_STEP), 0
    )
    with assert_raises():
        _ = mutable_group.index_for_ra_type(2)
    mutable_group.four_step_index = -2
    with assert_raises():
        mutable_group.validate()


def test_redcap_initial_bwp_and_inactivity_literal_tables() raises:
    assert_equal(
        nr_redcap_rel17_random_access_uplink_bwp_source(True),
        NR_REDCAP_MAC_BWP_REDCAP_INITIAL,
    )
    assert_equal(
        nr_redcap_rel17_random_access_uplink_bwp_source(False),
        NR_REDCAP_MAC_BWP_ORDINARY_INITIAL,
    )

    for configured_value in range(2):
        var configured = configured_value == 1
        for si_value in range(2):
            var si_request = si_value == 1
            for explicit_value in range(2):
                var explicit_resources = explicit_value == 1
                for sul_value in range(2):
                    var selected_sul = sul_value == 1
                    if explicit_resources and not si_request:
                        with assert_raises():
                            _ = nr_redcap_rel17_random_access_downlink_bwp_source(
                                configured,
                                si_request=si_request,
                                explicit_si_request_resources=explicit_resources,
                                selected_sul_carrier=selected_sul,
                            )
                        continue
                    var expected = NR_REDCAP_MAC_BWP_ORDINARY_INITIAL
                    if configured and not (
                        si_request and explicit_resources and selected_sul
                    ):
                        expected = NR_REDCAP_MAC_BWP_REDCAP_INITIAL
                    assert_equal(
                        nr_redcap_rel17_random_access_downlink_bwp_source(
                            configured,
                            si_request=si_request,
                            explicit_si_request_resources=explicit_resources,
                            selected_sul_carrier=selected_sul,
                        ),
                        expected,
                    )

    for default_value in range(2):
        for redcap_value in range(2):
            var expected = NR_REDCAP_MAC_BWP_ORDINARY_INITIAL
            if default_value == 1:
                expected = NR_REDCAP_MAC_BWP_DEFAULT
            elif redcap_value == 1:
                expected = NR_REDCAP_MAC_BWP_REDCAP_INITIAL
            assert_equal(
                nr_redcap_rel17_bwp_inactivity_target(
                    default_value == 1, redcap_value == 1
                ),
                expected,
            )


def test_redcap_ul_ccch_lcid_and_public_edges() raises:
    assert_equal(nr_redcap_rel17_ul_ccch_lcid(48), 35)
    assert_equal(nr_redcap_rel17_ul_ccch_lcid(64), 36)
    with assert_raises():
        _ = nr_redcap_rel17_ul_ccch_lcid(-1)
    with assert_raises():
        _ = nr_redcap_rel17_ul_ccch_lcid(Int.MAX)
    with assert_raises():
        _ = nr_redcap_rel17_ra_resource_set_available(16, 0)
    with assert_raises():
        _ = nr_redcap_rel17_ra_resource_set_available(
            0, NR_REDCAP_RA_FEATURE_SLICING, nsag_matches=True
        )
    with assert_raises():
        _ = nr_redcap_rel17_ra_resource_set_available(
            0,
            0,
            profile=NR_REDCAP_MAC_PROFILE_ORDINARY_NR,
        )
    with assert_raises():
        _ = nr_redcap_rel17_msg3_repetition_applicable(
            True,
            False,
            0.0,
            0.0,
            profile=NR_REDCAP_MAC_PROFILE_EREDCAP_REL18,
        )
    with assert_raises():
        _ = nr_redcap_rel17_random_access_uplink_bwp_source(
            True, profile=NR_REDCAP_MAC_PROFILE_ORDINARY_NR
        )
    with assert_raises():
        _ = nr_redcap_rel17_random_access_downlink_bwp_source(
            True, profile=NR_REDCAP_MAC_PROFILE_ORDINARY_NR
        )
    var fallback_mask: List[Int] = [0]
    var fallback_type: List[Int] = [NR_REDCAP_RA_TYPE_4_STEP]
    var fallback_available: List[UInt8] = [1]
    var no_priority = List[Int]()
    with assert_raises():
        _ = nr_redcap_rel17_select_ra_resource_set_group(
            Span(fallback_mask),
            Span(fallback_type),
            Span(fallback_available),
            0,
            Span(no_priority),
            profile=NR_REDCAP_MAC_PROFILE_EREDCAP_REL18,
        )
    with assert_raises():
        _ = nr_redcap_rel17_bwp_inactivity_target(
            False,
            True,
            profile=NR_REDCAP_MAC_PROFILE_EREDCAP_REL18,
        )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
