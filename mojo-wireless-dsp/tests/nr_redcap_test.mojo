"""Independent clause tables, edges, and properties for NR RedCap profiles.

The four-entry Rel-17 branch/layer oracle is a literal transcription of 3GPP
TS 38.306 V17.16.0 clause 4.2.21.1.  It is intentionally encoded as packed
static rows rather than calculated by the production validator.  BWP and
eRedCap expectations similarly come from TS 38.331 V17.17.0, TS 38.213
V17.13.0 clause 17.1, and TS 38.306 V18.10.0 clause 4.2.22.
"""

from std.testing import assert_equal, assert_true, assert_raises, TestSuite
from std.utils.numerics import inf, nan
from wireless_dsp.wireless.nr.redcap import (
    NROrdinaryNRProfile,
    NRRedCapRel17Capabilities,
    NRERedCapRel18Capabilities,
    NRRedCapInitialBWP,
    NRRedCapRel17InitialAccessConfig,
    NR_FREQUENCY_RANGE_FR1,
    NR_FREQUENCY_RANGE_FR2,
    NR_DUPLEX_FDD,
    NR_DUPLEX_TDD,
    NR_REDCAP_DL_BWP_RACH_ONLY,
    NR_REDCAP_DL_BWP_PAGING,
    NR_REDCAP_DL_BWP_CONNECTED_OPTION_1,
    NR_REDCAP_RA_MESSAGE_MSG1,
    NR_REDCAP_RA_MESSAGE_MSGA,
    NR_REDCAP_RA_MESSAGE_MSG3,
    NR_INITIAL_BWP_DIRECTION_DOWNLINK,
    NR_INITIAL_BWP_DIRECTION_UPLINK,
    NR_INITIAL_BWP_SOURCE_ORDINARY,
    NR_INITIAL_BWP_SOURCE_REDCAP_SPECIFIC,
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


def _rel17_capabilities(
    *,
    frequency_range: Int = NR_FREQUENCY_RANGE_FR1,
    bandwidth_mhz: Float64 = 20.0,
    rx_branches: Int = 1,
    dl_layers: Int = 1,
    duplex_mode: Int = NR_DUPLEX_TDD,
    two_step: Bool = False,
) raises -> NRRedCapRel17Capabilities:
    return NRRedCapRel17Capabilities(
        frequency_range,
        bandwidth_mhz,
        rx_branches,
        dl_layers,
        duplex_mode=duplex_mode,
        supports_two_step_rach=two_step,
    )


def _rel17_shape_is_accepted(
    frequency_range: Int,
    rx_branches: Int,
    dl_layers: Int,
    tx_branches: Int,
    ul_layers: Int,
) -> Bool:
    try:
        var capabilities = NRRedCapRel17Capabilities(
            frequency_range,
            20.0 if frequency_range == NR_FREQUENCY_RANGE_FR1 else 100.0,
            rx_branches,
            dl_layers,
            tx_branches=tx_branches,
            ul_layers=ul_layers,
        )
        return nr_redcap_rel17_validate_capabilities(capabilities)
    except:
        return False


def _rel17_static_shape_oracle(
    frequency_range: Int,
    rx_branches: Int,
    dl_layers: Int,
    tx_branches: Int,
    ul_layers: Int,
) -> Bool:
    # Packed fields are FR, Rx, DL, Tx, UL.  These are the complete legal rows.
    var legal_rows: List[Int] = [11111, 12211, 22111, 22211]
    var packed = (
        10000 * frequency_range
        + 1000 * rx_branches
        + 100 * dl_layers
        + 10 * tx_branches
        + ul_layers
    )
    for row in legal_rows:
        if packed == row:
            return True
    return False


def _rach_only_initial_access(
    *,
    center_frequency_khz: Int = 3500000,
    ul_center_frequency_khz: Int = 3500000,
    ul_msga_configured: Bool = False,
) raises -> NRRedCapRel17InitialAccessConfig:
    var dl = NRRedCapInitialBWP(0, 48, center_frequency_khz, 30)
    var ul = NRRedCapInitialBWP(0, 48, ul_center_frequency_khz, 30)
    return NRRedCapRel17InitialAccessConfig(
        dl,
        ul,
        51,
        51,
        NR_REDCAP_DL_BWP_RACH_ONLY,
        ul_msga_configured=ul_msga_configured,
    )


def _paging_initial_access() raises -> NRRedCapRel17InitialAccessConfig:
    var dl = NRRedCapInitialBWP(0, 48, 3500000, 30)
    var ul = NRRedCapInitialBWP(0, 48, 3500000, 30)
    return NRRedCapRel17InitialAccessConfig(
        dl,
        ul,
        51,
        51,
        NR_REDCAP_DL_BWP_PAGING,
        has_cd_ssb=True,
        contains_coreset0=True,
        ra_coreset_id=0,
        monitors_type2_css=True,
    )


def test_profile_types_and_release_tags_are_independent() raises:
    var ordinary = NROrdinaryNRProfile()
    assert_equal(ordinary.release, 19)
    with assert_raises():
        _ = NROrdinaryNRProfile(20)

    var rel17 = _rel17_capabilities()
    var rel18 = NRERedCapRel18Capabilities(20.0, 30, 1, 1)
    assert_true(nr_redcap_rel17_validate_capabilities(rel17))
    assert_true(nr_eredcap_rel18_validate_capabilities(rel18))
    assert_true(rel17.support_of_redcap)
    assert_equal(rel17.ue_specific_dl_bwps_per_carrier, 1)
    assert_equal(rel17.ue_specific_ul_bwps_per_carrier, 1)
    assert_true(rel17.supports_dl_bwp_with_cd_or_ncd_ssb)
    assert_true(rel17.supports_ncd_ssb_measurements)
    assert_true(rel17.supports_cef_report_redcap)
    assert_true(rel17.supports_rlf_report_redcap)
    assert_true(rel18.support_of_eredcap)
    assert_true(not rel18.support_of_redcap)


def test_rel17_branch_layer_complete_static_table_oracle() raises:
    for frequency_range in range(1, 3):
        for rx_branches in range(0, 4):
            for dl_layers in range(0, 4):
                for tx_branches in range(0, 3):
                    for ul_layers in range(0, 3):
                        assert_equal(
                            _rel17_shape_is_accepted(
                                frequency_range,
                                rx_branches,
                                dl_layers,
                                tx_branches,
                                ul_layers,
                            ),
                            _rel17_static_shape_oracle(
                                frequency_range,
                                rx_branches,
                                dl_layers,
                                tx_branches,
                                ul_layers,
                            ),
                        )


def test_rel17_bandwidth_and_mutable_boundary_edges() raises:
    _ = _rel17_capabilities(bandwidth_mhz=20.0)
    _ = _rel17_capabilities(
        frequency_range=NR_FREQUENCY_RANGE_FR2,
        bandwidth_mhz=100.0,
        rx_branches=2,
        dl_layers=1,
    )
    with assert_raises():
        _ = _rel17_capabilities(bandwidth_mhz=20.0001)
    with assert_raises():
        _ = _rel17_capabilities(bandwidth_mhz=19.9999)
    with assert_raises():
        _ = _rel17_capabilities(
            frequency_range=NR_FREQUENCY_RANGE_FR2,
            bandwidth_mhz=100.0001,
            rx_branches=2,
            dl_layers=2,
        )
    with assert_raises():
        _ = _rel17_capabilities(bandwidth_mhz=nan[DType.float64]())
    with assert_raises():
        _ = _rel17_capabilities(bandwidth_mhz=inf[DType.float64]())
    with assert_raises():
        _ = _rel17_capabilities(bandwidth_mhz=0.0)

    var mutated = _rel17_capabilities()
    mutated.tx_branches = 2
    with assert_raises():
        _ = nr_redcap_rel17_validate_capabilities(mutated)


def test_rel17_forbidden_features_and_optional_dependencies() raises:
    with assert_raises():
        _ = NRRedCapRel17Capabilities(1, 20.0, 1, 1, carrier_aggregation=True)
    with assert_raises():
        _ = NRRedCapRel17Capabilities(1, 20.0, 1, 1, mr_dc=True)
    with assert_raises():
        _ = NRRedCapRel17Capabilities(1, 20.0, 1, 1, daps=True)
    with assert_raises():
        _ = NRRedCapRel17Capabilities(1, 20.0, 1, 1, cpac=True)
    with assert_raises():
        _ = NRRedCapRel17Capabilities(1, 20.0, 1, 1, iab=True)
    with assert_raises():
        _ = NRRedCapRel17Capabilities(1, 20.0, 1, 1, support_of_redcap=False)
    with assert_raises():
        _ = NRRedCapRel17Capabilities(
            1, 20.0, 1, 1, supports_ncd_ssb_initial_bwp_sdt=True
        )
    with assert_raises():
        _ = NRRedCapRel17Capabilities(
            1,
            20.0,
            1,
            1,
            duplex_mode=NR_DUPLEX_TDD,
            supports_half_duplex_fdd_type_a=True,
        )
    with assert_raises():
        _ = NRRedCapRel17Capabilities(
            2,
            100.0,
            2,
            2,
            duplex_mode=NR_DUPLEX_FDD,
            supports_half_duplex_fdd_type_a=True,
        )
    with assert_raises():
        _ = NRRedCapRel17Capabilities(
            1, 20.0, 1, 1, ue_specific_dl_bwps_per_carrier=2
        )
    with assert_raises():
        _ = NRRedCapRel17Capabilities(
            1, 20.0, 1, 1, ue_specific_ul_bwps_per_carrier=0
        )
    with assert_raises():
        _ = NRRedCapRel17Capabilities(
            1, 20.0, 1, 1, supports_dl_bwp_with_cd_or_ncd_ssb=False
        )
    with assert_raises():
        _ = NRRedCapRel17Capabilities(
            1, 20.0, 1, 1, supports_ncd_ssb_measurements=False
        )
    with assert_raises():
        _ = NRRedCapRel17Capabilities(
            1, 20.0, 1, 1, supports_cef_report_redcap=False
        )
    with assert_raises():
        _ = NRRedCapRel17Capabilities(
            1, 20.0, 1, 1, supports_rlf_report_redcap=False
        )

    var optional = NRRedCapRel17Capabilities(
        1,
        20.0,
        2,
        2,
        duplex_mode=NR_DUPLEX_FDD,
        supports_16_drbs=True,
        supports_long_pdcp_sn=True,
        supports_long_rlc_am_sn=True,
        supports_rrm_relaxation_connected=True,
        supports_ncd_ssb_initial_bwp_sdt=True,
        supports_ra_sdt=True,
        supports_half_duplex_fdd_type_a=True,
        supports_full_duplex_fdd=False,
    )
    assert_equal(optional.maximum_supported_drbs(), 16)
    assert_equal(optional.pdcp_sequence_number_bits(), 18)
    assert_equal(optional.rlc_am_sequence_number_bits(), 18)
    assert_true(optional.supports_rrm_relaxation_connected)
    with assert_raises():
        _ = NRRedCapRel17Capabilities(
            1,
            20.0,
            1,
            1,
            duplex_mode=NR_DUPLEX_FDD,
            supports_half_duplex_fdd_type_a=True,
            supports_full_duplex_fdd=True,
        )

    # Public fields are mutable, so each capability boundary must revalidate
    # the complete mandatory feature bundle after construction.
    optional.supports_ncd_ssb_measurements = False
    with assert_raises():
        _ = nr_redcap_rel17_validate_capabilities(optional)


def test_rel17_cell_barring_and_half_duplex_fdd_static_cases() raises:
    var one_rx = _rel17_capabilities(
        duplex_mode=NR_DUPLEX_FDD
    )
    assert_true(nr_redcap_rel17_cell_access_allowed(one_rx))
    assert_true(not nr_redcap_rel17_cell_access_allowed(
        one_rx, cell_barred_for_1rx=True
    ))
    assert_true(nr_redcap_rel17_cell_access_allowed(
        one_rx, cell_barred_for_2rx=True
    ))

    var two_rx = NRRedCapRel17Capabilities(
        1, 20.0, 2, 2, duplex_mode=NR_DUPLEX_FDD
    )
    assert_true(not nr_redcap_rel17_cell_access_allowed(
        two_rx, cell_barred_for_2rx=True
    ))

    var half_only = NRRedCapRel17Capabilities(
        1,
        20.0,
        1,
        1,
        duplex_mode=NR_DUPLEX_FDD,
        supports_half_duplex_fdd_type_a=True,
        supports_full_duplex_fdd=False,
    )
    assert_true(not nr_redcap_rel17_cell_access_allowed(half_only))
    assert_true(nr_redcap_rel17_cell_access_allowed(
        half_only, half_duplex_redcap_allowed=True
    ))
    with assert_raises():
        _ = NRRedCapRel17Capabilities(
            1,
            20.0,
            1,
            1,
            duplex_mode=NR_DUPLEX_FDD,
            supports_full_duplex_fdd=False,
        )


def test_initial_bwp_selection_static_cases_and_edges() raises:
    var capabilities = _rel17_capabilities()
    var fallback = nr_redcap_rel17_select_initial_bwp(
        capabilities, NR_INITIAL_BWP_DIRECTION_DOWNLINK, 20.0
    )
    assert_equal(fallback.source, NR_INITIAL_BWP_SOURCE_ORDINARY)
    assert_equal(fallback.bandwidth_mhz, 20.0)
    var narrower_fallback = nr_redcap_rel17_select_initial_bwp(
        capabilities, NR_INITIAL_BWP_DIRECTION_DOWNLINK, 10.0
    )
    assert_equal(narrower_fallback.bandwidth_mhz, 10.0)
    var selected = nr_redcap_rel17_select_initial_bwp(
        capabilities,
        NR_INITIAL_BWP_DIRECTION_UPLINK,
        80.0,
        redcap_specific_present=True,
        redcap_specific_bandwidth_mhz=10.0,
    )
    assert_equal(selected.source, NR_INITIAL_BWP_SOURCE_REDCAP_SPECIFIC)
    assert_equal(selected.bandwidth_mhz, 10.0)
    with assert_raises():
        _ = nr_redcap_rel17_select_initial_bwp(
            capabilities, NR_INITIAL_BWP_DIRECTION_DOWNLINK, 20.0001
        )
    with assert_raises():
        _ = nr_redcap_rel17_select_initial_bwp(
            capabilities,
            NR_INITIAL_BWP_DIRECTION_DOWNLINK,
            10.0,
            redcap_specific_present=True,
            redcap_specific_bandwidth_mhz=nan[DType.float64](),
        )
    with assert_raises():
        _ = nr_redcap_rel17_select_initial_bwp(capabilities, 7, 10.0)
    with assert_raises():
        _ = nr_redcap_rel17_select_initial_bwp(
            capabilities,
            NR_INITIAL_BWP_DIRECTION_UPLINK,
            5.0,
            redcap_specific_present=True,
            redcap_specific_bandwidth_mhz=20.0001,
        )


def test_initial_access_coreset_search_space_static_oracle() raises:
    var capabilities = _rel17_capabilities()
    var rach = _rach_only_initial_access()
    assert_true(nr_redcap_rel17_validate_initial_access(capabilities, rach))
    # 24 RB * 2 symbols / 6 REG-per-CCE = 8 CCEs; four L=2 CSS
    # candidates at Y=0 start at 0,2,4,6 by the clause-10.1 equation.
    assert_equal(
        nr_redcap_rel17_ra_search_space_first_cces(
            capabilities, rach, 2, 4
        ),
        [0, 2, 4, 6],
    )
    var paging = _paging_initial_access()
    assert_true(nr_redcap_rel17_validate_initial_access(capabilities, paging))

    var connected = _paging_initial_access()
    connected.dl_purpose = NR_REDCAP_DL_BWP_CONNECTED_OPTION_1
    assert_true(
        nr_redcap_rel17_validate_initial_access(capabilities, connected)
    )


def test_initial_access_negative_geometry_presence_and_pdcch_cases() raises:
    var capabilities = _rel17_capabilities()
    with assert_raises():
        _ = nr_redcap_rel17_ra_search_space_first_cces(
            capabilities, _rach_only_initial_access(), 3, 1
        )

    var config = _rach_only_initial_access()
    config.separate_dl_bwp_configured = False
    with assert_raises():
        _ = nr_redcap_rel17_validate_initial_access(capabilities, config)

    config = _rach_only_initial_access()
    config.separate_ul_bwp_configured = False
    with assert_raises():
        _ = nr_redcap_rel17_validate_initial_access(capabilities, config)

    config = _paging_initial_access()
    config.has_cd_ssb = False
    with assert_raises():
        _ = nr_redcap_rel17_validate_initial_access(capabilities, config)

    config = _paging_initial_access()
    config.contains_coreset0 = False
    with assert_raises():
        _ = nr_redcap_rel17_validate_initial_access(capabilities, config)

    config = _rach_only_initial_access()
    config.coreset_start_prb = 30
    with assert_raises():
        _ = nr_redcap_rel17_validate_initial_access(capabilities, config)

    config = _rach_only_initial_access()
    config.has_ncd_ssb = True
    with assert_raises():
        _ = nr_redcap_rel17_validate_initial_access(capabilities, config)

    config = _paging_initial_access()
    config.has_ncd_ssb = True
    with assert_raises():
        _ = nr_redcap_rel17_validate_initial_access(capabilities, config)

    config = _rach_only_initial_access()
    config.ra_search_space_configured = False
    with assert_raises():
        _ = nr_redcap_rel17_validate_initial_access(capabilities, config)

    config = _rach_only_initial_access()
    config.ul_rach_configured = False
    with assert_raises():
        _ = nr_redcap_rel17_validate_initial_access(capabilities, config)

    config = _rach_only_initial_access()
    config.common_pucch_configured = False
    with assert_raises():
        _ = nr_redcap_rel17_validate_initial_access(capabilities, config)

    config = _rach_only_initial_access(ul_center_frequency_khz=3510000)
    with assert_raises():
        _ = nr_redcap_rel17_validate_initial_access(capabilities, config)

    var fdd = _rel17_capabilities(duplex_mode=NR_DUPLEX_FDD)
    assert_true(nr_redcap_rel17_validate_initial_access(fdd, config))

    config = _rach_only_initial_access()
    config.dl_bwp.resource_blocks = 56
    config.dl_carrier_resource_blocks = 60
    with assert_raises():
        _ = nr_redcap_rel17_validate_initial_access(capabilities, config)


def test_two_step_rach_and_early_indication_decisions() raises:
    var four_step = _rel17_capabilities()
    assert_true(nr_redcap_rel17_early_indication_available(
        four_step, NR_REDCAP_RA_MESSAGE_MSG1
    ))
    assert_true(not nr_redcap_rel17_early_indication_available(
        four_step, NR_REDCAP_RA_MESSAGE_MSGA
    ))
    assert_true(nr_redcap_rel17_early_indication_available(
        four_step, NR_REDCAP_RA_MESSAGE_MSG3
    ))
    with assert_raises():
        _ = nr_redcap_rel17_early_indication_available(four_step, 99)
    var invalid_msga = _rach_only_initial_access(ul_msga_configured=True)
    with assert_raises():
        _ = nr_redcap_rel17_validate_initial_access(four_step, invalid_msga)

    var two_step = _rel17_capabilities(two_step=True)
    assert_true(nr_redcap_rel17_early_indication_available(
        two_step, NR_REDCAP_RA_MESSAGE_MSGA
    ))
    assert_true(nr_redcap_rel17_validate_initial_access(two_step, invalid_msga))


def test_eredcap_rel18_exact_profile_and_prb_limits() raises:
    var reduced_15 = NRERedCapRel18Capabilities(20.0, 15, 1, 1)
    var reduced_30 = NRERedCapRel18Capabilities(
        20.0, 30, 2, 2, supports_two_step_rach=True
    )
    assert_true(nr_eredcap_rel18_validate_capabilities(reduced_15))
    assert_true(nr_eredcap_rel18_validate_capabilities(reduced_30))
    assert_equal(nr_eredcap_rel18_unicast_prb_limit(reduced_15), 25)
    assert_equal(nr_eredcap_rel18_unicast_prb_limit(reduced_30), 12)
    assert_true(nr_eredcap_rel18_validate_scheduled_prbs(reduced_15, 25))
    assert_true(nr_eredcap_rel18_validate_scheduled_prbs(reduced_30, 12))
    with assert_raises():
        _ = nr_eredcap_rel18_validate_scheduled_prbs(reduced_15, 26)
    with assert_raises():
        _ = nr_eredcap_rel18_validate_scheduled_prbs(reduced_30, 13)

    var full_bb = NRERedCapRel18Capabilities(
        20.0, 30, 1, 1, not_reduced_baseband_bandwidth=True
    )
    assert_equal(nr_eredcap_rel18_unicast_prb_limit(full_bb), 51)
    assert_true(nr_eredcap_rel18_validate_scheduled_prbs(full_bb, 25))
    assert_true(nr_eredcap_rel18_validate_scheduled_prbs(full_bb, 51))
    with assert_raises():
        _ = nr_eredcap_rel18_validate_scheduled_prbs(full_bb, 52)
    assert_true(nr_eredcap_rel18_validate_scheduled_prbs(
        full_bb,
        12,
        is_msg3_msga_or_msg4=True,
        contention_based_random_access=True,
    ))
    with assert_raises():
        _ = nr_eredcap_rel18_validate_scheduled_prbs(
            full_bb,
            13,
            is_msg3_msga_or_msg4=True,
            contention_based_random_access=True,
        )
    assert_true(nr_eredcap_rel18_early_indication_available(
        reduced_30, NR_REDCAP_RA_MESSAGE_MSGA
    ))


def test_eredcap_rel18_negative_profile_edges() raises:
    with assert_raises():
        _ = NRERedCapRel18Capabilities(20.0001, 30, 1, 1)
    with assert_raises():
        _ = NRERedCapRel18Capabilities(19.9999, 30, 1, 1)
    with assert_raises():
        _ = NRERedCapRel18Capabilities(nan[DType.float64](), 30, 1, 1)
    with assert_raises():
        _ = NRERedCapRel18Capabilities(inf[DType.float64](), 30, 1, 1)
    with assert_raises():
        _ = NRERedCapRel18Capabilities(20.0, 60, 1, 1)
    with assert_raises():
        _ = NRERedCapRel18Capabilities(20.0, 30, 2, 1)
    with assert_raises():
        _ = NRERedCapRel18Capabilities(20.0, 30, 1, 1, tx_branches=2)
    with assert_raises():
        _ = NRERedCapRel18Capabilities(20.0, 30, 1, 1, support_of_redcap=True)
    with assert_raises():
        _ = NRERedCapRel18Capabilities(20.0, 30, 1, 1, support_of_eredcap=False)
    with assert_raises():
        _ = NRERedCapRel18Capabilities(20.0, 30, 1, 1, carrier_aggregation=True)
    with assert_raises():
        _ = NRERedCapRel18Capabilities(20.0, 30, 1, 1, mr_dc=True)
    with assert_raises():
        _ = NRERedCapRel18Capabilities(20.0, 30, 1, 1, daps=True)
    with assert_raises():
        _ = NRERedCapRel18Capabilities(20.0, 30, 1, 1, cpac=True)
    with assert_raises():
        _ = NRERedCapRel18Capabilities(20.0, 30, 1, 1, iab=True)
    with assert_raises():
        _ = NRERedCapRel18Capabilities(20.0, 30, 1, 1, ncr_mt=True)
    with assert_raises():
        _ = nr_eredcap_rel18_validate_scheduled_prbs(
            NRERedCapRel18Capabilities(20.0, 30, 1, 1), 0
        )

    var mutated = NRERedCapRel18Capabilities(20.0, 30, 1, 1)
    mutated.channel_bandwidth_mhz = 21.0
    with assert_raises():
        _ = nr_eredcap_rel18_validate_capabilities(mutated)
    with assert_raises():
        _ = nr_eredcap_rel18_unicast_prb_limit(mutated)
    with assert_raises():
        _ = nr_eredcap_rel18_early_indication_available(
            NRERedCapRel18Capabilities(20.0, 30, 1, 1), 99
        )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
