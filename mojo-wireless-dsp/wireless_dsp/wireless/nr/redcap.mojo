"""Release-scoped NR RedCap/eRedCap capability and initial-access rules.

This module is a CPU reference for finite capability/configuration decisions;
it deliberately reuses the existing NR PHY implementations instead of
duplicating PSS/SSS, PBCH, PDCCH, PDSCH, PUSCH, PUCCH, or PRACH algorithms.

Normative baselines (latest published maintenance versions on 2026-08-22):

* 3GPP TS 38.306 V17.16.0, clauses 4.2.21.1--4.2.21.6.1;
* 3GPP TS 38.331 V17.17.0, ``initialDownlinkBWP-RedCap`` and
  ``initialUplinkBWP-RedCap`` field descriptions;
* 3GPP TS 38.213 V17.13.0, clause 17.1;
* 3GPP TS 38.306 V18.10.0, clauses 4.2.22.1--4.2.22.2.

The Rel-17 and Rel-18 capability records are intentionally different types.
An eRedCap record can therefore never silently satisfy a Rel-17 RedCap API.
The ordinary-NR tag is likewise independent and does not inherit any reduced-
capability restriction.  RRC ASN.1 encoding, complete RRM state machines,
RF/OTA requirements, and conformance certification are outside this module.
"""

from std.math import isfinite
from .procedures import (
    nr_coreset_cce_count,
    nr_search_space_candidate_first_cces,
)


comptime NR_FREQUENCY_RANGE_FR1 = 1
comptime NR_FREQUENCY_RANGE_FR2 = 2

comptime NR_DUPLEX_FDD = 0
comptime NR_DUPLEX_TDD = 1

comptime NR_REDCAP_DL_BWP_RACH_ONLY = 0
comptime NR_REDCAP_DL_BWP_PAGING = 1
comptime NR_REDCAP_DL_BWP_CONNECTED_OPTION_1 = 2

comptime NR_REDCAP_RA_MESSAGE_MSG1 = 1
comptime NR_REDCAP_RA_MESSAGE_MSGA = 2
comptime NR_REDCAP_RA_MESSAGE_MSG3 = 3

comptime NR_INITIAL_BWP_DIRECTION_DOWNLINK = 0
comptime NR_INITIAL_BWP_DIRECTION_UPLINK = 1
comptime NR_INITIAL_BWP_SOURCE_ORDINARY = 0
comptime NR_INITIAL_BWP_SOURCE_REDCAP_SPECIFIC = 1


def _validate_frequency_range(value: Int) raises:
    if value != NR_FREQUENCY_RANGE_FR1 and value != NR_FREQUENCY_RANGE_FR2:
        raise Error("NR frequency range must be FR1 or FR2")


def _validate_duplex_mode(value: Int) raises:
    if value != NR_DUPLEX_FDD and value != NR_DUPLEX_TDD:
        raise Error("NR duplex mode must be FDD or TDD")


struct NROrdinaryNRProfile(ImplicitlyCopyable, Equatable):
    """An explicit non-RedCap NR profile tag.

    This tag prevents a generic NR path from being counted as RedCap evidence.
    It does not attempt to replace the ordinary-NR capability schema in TS
    38.306.  Releases 15--19 are the published NR releases represented by the
    repository baseline on the audit date.
    """

    var release: Int

    def __init__(out self, release: Int = 19) raises:
        self.release = release
        self.validate()

    def validate(self) raises:
        if self.release < 15 or self.release > 19:
            raise Error("ordinary NR profile release must be in [15,19]")


struct NRRedCapRel17Capabilities(ImplicitlyCopyable):
    """TS 38.306 clause-4.2.21 capability record for Rel-17 RedCap.

    ``channel_bandwidth_mhz`` is the mandatory maximum UE channel-bandwidth
    capability (exactly 20 MHz in FR1 or 100 MHz in FR2), not the bandwidth of
    one serving-cell configuration or BWP.  ``rx_branches`` and ``dl_layers``
    are supported capability maxima, not the
    number scheduled in one transmission.  Consequently the FR1 pairs are
    exactly (1,1) and (2,2); FR2 always has two Rx branches and can advertise
    one or two DL layers.  Both ranges are single-Tx/single-UL-layer.
    """

    var frequency_range: Int
    var channel_bandwidth_mhz: Float64
    var rx_branches: Int
    var dl_layers: Int
    var tx_branches: Int
    var ul_layers: Int
    var duplex_mode: Int
    var support_of_redcap: Bool
    var supports_two_step_rach: Bool
    var carrier_aggregation: Bool
    var mr_dc: Bool
    var daps: Bool
    var cpac: Bool
    var iab: Bool
    var supports_16_drbs: Bool
    var supports_long_pdcp_sn: Bool
    var supports_long_rlc_am_sn: Bool
    var supports_rrm_relaxation_connected: Bool
    var supports_bwp_without_cd_or_ncd_ssb: Bool
    var supports_ncd_ssb_initial_bwp_sdt: Bool
    var supports_ra_sdt: Bool
    var supports_cg_sdt: Bool
    var supports_half_duplex_fdd_type_a: Bool
    var supports_full_duplex_fdd: Bool
    var ue_specific_dl_bwps_per_carrier: Int
    var ue_specific_ul_bwps_per_carrier: Int
    var supports_dl_bwp_with_cd_or_ncd_ssb: Bool
    var supports_ncd_ssb_measurements: Bool
    var supports_cef_report_redcap: Bool
    var supports_rlf_report_redcap: Bool

    def __init__(
        out self,
        frequency_range: Int,
        channel_bandwidth_mhz: Float64,
        rx_branches: Int,
        dl_layers: Int,
        *,
        tx_branches: Int = 1,
        ul_layers: Int = 1,
        duplex_mode: Int = NR_DUPLEX_TDD,
        support_of_redcap: Bool = True,
        supports_two_step_rach: Bool = False,
        carrier_aggregation: Bool = False,
        mr_dc: Bool = False,
        daps: Bool = False,
        cpac: Bool = False,
        iab: Bool = False,
        supports_16_drbs: Bool = False,
        supports_long_pdcp_sn: Bool = False,
        supports_long_rlc_am_sn: Bool = False,
        supports_rrm_relaxation_connected: Bool = False,
        supports_bwp_without_cd_or_ncd_ssb: Bool = False,
        supports_ncd_ssb_initial_bwp_sdt: Bool = False,
        supports_ra_sdt: Bool = False,
        supports_cg_sdt: Bool = False,
        supports_half_duplex_fdd_type_a: Bool = False,
        supports_full_duplex_fdd: Bool = True,
        ue_specific_dl_bwps_per_carrier: Int = 1,
        ue_specific_ul_bwps_per_carrier: Int = 1,
        supports_dl_bwp_with_cd_or_ncd_ssb: Bool = True,
        supports_ncd_ssb_measurements: Bool = True,
        supports_cef_report_redcap: Bool = True,
        supports_rlf_report_redcap: Bool = True,
    ) raises:
        self.frequency_range = frequency_range
        self.channel_bandwidth_mhz = channel_bandwidth_mhz
        self.rx_branches = rx_branches
        self.dl_layers = dl_layers
        self.tx_branches = tx_branches
        self.ul_layers = ul_layers
        self.duplex_mode = duplex_mode
        self.support_of_redcap = support_of_redcap
        self.supports_two_step_rach = supports_two_step_rach
        self.carrier_aggregation = carrier_aggregation
        self.mr_dc = mr_dc
        self.daps = daps
        self.cpac = cpac
        self.iab = iab
        self.supports_16_drbs = supports_16_drbs
        self.supports_long_pdcp_sn = supports_long_pdcp_sn
        self.supports_long_rlc_am_sn = supports_long_rlc_am_sn
        self.supports_rrm_relaxation_connected = (
            supports_rrm_relaxation_connected
        )
        self.supports_bwp_without_cd_or_ncd_ssb = (
            supports_bwp_without_cd_or_ncd_ssb
        )
        self.supports_ncd_ssb_initial_bwp_sdt = (
            supports_ncd_ssb_initial_bwp_sdt
        )
        self.supports_ra_sdt = supports_ra_sdt
        self.supports_cg_sdt = supports_cg_sdt
        self.supports_half_duplex_fdd_type_a = (
            supports_half_duplex_fdd_type_a
        )
        self.supports_full_duplex_fdd = supports_full_duplex_fdd
        self.ue_specific_dl_bwps_per_carrier = (
            ue_specific_dl_bwps_per_carrier
        )
        self.ue_specific_ul_bwps_per_carrier = (
            ue_specific_ul_bwps_per_carrier
        )
        self.supports_dl_bwp_with_cd_or_ncd_ssb = (
            supports_dl_bwp_with_cd_or_ncd_ssb
        )
        self.supports_ncd_ssb_measurements = supports_ncd_ssb_measurements
        self.supports_cef_report_redcap = supports_cef_report_redcap
        self.supports_rlf_report_redcap = supports_rlf_report_redcap
        self.validate()

    def validate(self) raises:
        _validate_frequency_range(self.frequency_range)
        _validate_duplex_mode(self.duplex_mode)
        if not isfinite(self.channel_bandwidth_mhz):
            raise Error("RedCap maximum channel bandwidth must be finite")
        if self.frequency_range == NR_FREQUENCY_RANGE_FR1:
            if self.channel_bandwidth_mhz != 20.0:
                raise Error("Rel-17 RedCap FR1 maximum bandwidth must be 20 MHz")
            if (
                (self.rx_branches != 1 or self.dl_layers != 1)
                and (self.rx_branches != 2 or self.dl_layers != 2)
            ):
                raise Error("Rel-17 RedCap FR1 requires Rx/DL pair (1,1) or (2,2)")
        else:
            if self.channel_bandwidth_mhz != 100.0:
                raise Error("Rel-17 RedCap FR2 maximum bandwidth must be 100 MHz")
            if self.rx_branches != 2 or self.dl_layers < 1 or self.dl_layers > 2:
                raise Error("Rel-17 RedCap FR2 requires two Rx branches and one or two DL layers")
        if self.tx_branches != 1 or self.ul_layers != 1:
            raise Error("Rel-17 RedCap supports one Tx branch and one UL layer")
        if not self.support_of_redcap:
            raise Error("Rel-17 RedCap shall signal supportOfRedCap-r17")
        if self.carrier_aggregation:
            raise Error("carrier aggregation is not supported by Rel-17 RedCap")
        if self.mr_dc:
            raise Error("MR-DC is not supported by Rel-17 RedCap")
        if self.daps:
            raise Error("DAPS is not supported by Rel-17 RedCap")
        if self.cpac:
            raise Error("CPAC is not supported by Rel-17 RedCap")
        if self.iab:
            raise Error("IAB-node operation is not supported by Rel-17 RedCap")
        if self.supports_half_duplex_fdd_type_a and (
            self.frequency_range != NR_FREQUENCY_RANGE_FR1
            or self.duplex_mode != NR_DUPLEX_FDD
        ):
            raise Error("RedCap half-duplex FDD type A is restricted to FR1 FDD")
        if (
            self.supports_half_duplex_fdd_type_a
            and self.supports_full_duplex_fdd
        ):
            raise Error("RedCap FDD full- and half-duplex capabilities are exclusive")
        if (
            self.duplex_mode == NR_DUPLEX_FDD
            and not self.supports_full_duplex_fdd
            and not self.supports_half_duplex_fdd_type_a
        ):
            raise Error("RedCap FDD capability requires full- or half-duplex support")
        if self.supports_ncd_ssb_initial_bwp_sdt and not (
            self.supports_ra_sdt or self.supports_cg_sdt
        ):
            raise Error("NCD-SSB initial-BWP SDT requires RA-SDT or CG-SDT")
        if (
            self.ue_specific_dl_bwps_per_carrier != 1
            or self.ue_specific_ul_bwps_per_carrier != 1
        ):
            raise Error(
                "Rel-17 RedCap supports one UE-specific DL and UL BWP per carrier"
            )
        if not self.supports_dl_bwp_with_cd_or_ncd_ssb:
            raise Error(
                "supportOfRedCap requires a UE-specific DL BWP with CD- or NCD-SSB"
            )
        if not self.supports_ncd_ssb_measurements:
            raise Error(
                "supportOfRedCap requires NCD-SSB measurements in configured DL BWP"
            )
        if (
            not self.supports_cef_report_redcap
            or not self.supports_rlf_report_redcap
        ):
            raise Error(
                "RedCap CEF and RLF report capabilities require mandatory signaling"
            )

    def maximum_supported_drbs(self) -> Int:
        """Return the declared mandatory/optional DRB capability."""
        return 16 if self.supports_16_drbs else 8

    def pdcp_sequence_number_bits(self) -> Int:
        """Return mandatory 12-bit or optional 18-bit PDCP SN support."""
        return 18 if self.supports_long_pdcp_sn else 12

    def rlc_am_sequence_number_bits(self) -> Int:
        """Return mandatory 12-bit or optional 18-bit RLC-AM SN support."""
        return 18 if self.supports_long_rlc_am_sn else 12


def nr_redcap_rel17_validate_capabilities(
    capabilities: NRRedCapRel17Capabilities,
) raises -> Bool:
    """Revalidate a possibly-mutated public Rel-17 capability record."""
    capabilities.validate()
    return True


def nr_redcap_rel17_cell_access_allowed(
    capabilities: NRRedCapRel17Capabilities,
    *,
    cell_barred_for_1rx: Bool = False,
    cell_barred_for_2rx: Bool = False,
    half_duplex_redcap_allowed: Bool = False,
) raises -> Bool:
    """Evaluate the deterministic Rel-17 RedCap cell-access gates.

    TS 38.331 clause 5.2.2.4.2 applies the matching one-/two-Rx barring bit.
    An FR1 FDD UE that supports only half-duplex operation additionally needs
    ``halfDuplexRedCapAllowed`` in SIB1.  Other ordinary cell-selection inputs
    remain with the caller and are not silently approximated here.
    """
    capabilities.validate()
    if capabilities.rx_branches == 1 and cell_barred_for_1rx:
        return False
    if capabilities.rx_branches == 2 and cell_barred_for_2rx:
        return False
    if (
        capabilities.duplex_mode == NR_DUPLEX_FDD
        and not capabilities.supports_full_duplex_fdd
        and not half_duplex_redcap_allowed
    ):
        return False
    return True


struct NRERedCapRel18Capabilities(ImplicitlyCopyable):
    """TS 38.306 clause-4.2.22 capability record for Rel-18 eRedCap.

    ``channel_bandwidth_mhz`` is the mandatory 20-MHz maximum FR1 capability,
    not a serving-cell or BWP width.  eRedCap is FR1-only, does not support
    FR1 60 kHz SCS, and is mutually
    exclusive with ``supportOfRedCap-r17``.  The optional non-reduced-baseband
    flag controls whether the 25/12-PRB unicast restriction generally applies.
    """

    var channel_bandwidth_mhz: Float64
    var subcarrier_spacing_khz: Int
    var rx_branches: Int
    var dl_layers: Int
    var tx_branches: Int
    var ul_layers: Int
    var duplex_mode: Int
    var support_of_eredcap: Bool
    var support_of_redcap: Bool
    var supports_two_step_rach: Bool
    var not_reduced_baseband_bandwidth: Bool
    var carrier_aggregation: Bool
    var mr_dc: Bool
    var daps: Bool
    var cpac: Bool
    var iab: Bool
    var ncr_mt: Bool
    var supports_half_duplex_fdd_type_a: Bool

    def __init__(
        out self,
        channel_bandwidth_mhz: Float64,
        subcarrier_spacing_khz: Int,
        rx_branches: Int,
        dl_layers: Int,
        *,
        tx_branches: Int = 1,
        ul_layers: Int = 1,
        duplex_mode: Int = NR_DUPLEX_TDD,
        support_of_eredcap: Bool = True,
        support_of_redcap: Bool = False,
        supports_two_step_rach: Bool = False,
        not_reduced_baseband_bandwidth: Bool = False,
        carrier_aggregation: Bool = False,
        mr_dc: Bool = False,
        daps: Bool = False,
        cpac: Bool = False,
        iab: Bool = False,
        ncr_mt: Bool = False,
        supports_half_duplex_fdd_type_a: Bool = False,
    ) raises:
        self.channel_bandwidth_mhz = channel_bandwidth_mhz
        self.subcarrier_spacing_khz = subcarrier_spacing_khz
        self.rx_branches = rx_branches
        self.dl_layers = dl_layers
        self.tx_branches = tx_branches
        self.ul_layers = ul_layers
        self.duplex_mode = duplex_mode
        self.support_of_eredcap = support_of_eredcap
        self.support_of_redcap = support_of_redcap
        self.supports_two_step_rach = supports_two_step_rach
        self.not_reduced_baseband_bandwidth = not_reduced_baseband_bandwidth
        self.carrier_aggregation = carrier_aggregation
        self.mr_dc = mr_dc
        self.daps = daps
        self.cpac = cpac
        self.iab = iab
        self.ncr_mt = ncr_mt
        self.supports_half_duplex_fdd_type_a = (
            supports_half_duplex_fdd_type_a
        )
        self.validate()

    def validate(self) raises:
        _validate_duplex_mode(self.duplex_mode)
        if (
            not isfinite(self.channel_bandwidth_mhz)
            or self.channel_bandwidth_mhz != 20.0
        ):
            raise Error("Rel-18 eRedCap maximum FR1 bandwidth must be 20 MHz")
        if self.subcarrier_spacing_khz != 15 and self.subcarrier_spacing_khz != 30:
            raise Error("Rel-18 eRedCap supports FR1 15 or 30 kHz SCS, not 60 kHz")
        if (
            (self.rx_branches != 1 or self.dl_layers != 1)
            and (self.rx_branches != 2 or self.dl_layers != 2)
        ):
            raise Error("Rel-18 eRedCap requires Rx/DL pair (1,1) or (2,2)")
        if self.tx_branches != 1 or self.ul_layers != 1:
            raise Error("Rel-18 eRedCap supports one Tx branch and one UL layer")
        if not self.support_of_eredcap or self.support_of_redcap:
            raise Error("eRedCap shall signal only supportOfERedCap-r18")
        if self.carrier_aggregation:
            raise Error("carrier aggregation is not supported by Rel-18 eRedCap")
        if self.mr_dc:
            raise Error("MR-DC is not supported by Rel-18 eRedCap")
        if self.daps:
            raise Error("DAPS is not supported by Rel-18 eRedCap")
        if self.cpac:
            raise Error("CPAC is not supported by Rel-18 eRedCap")
        if self.iab:
            raise Error("IAB-node operation is not supported by Rel-18 eRedCap")
        if self.ncr_mt:
            raise Error("NCR-MT operation is not supported by Rel-18 eRedCap")
        if self.supports_half_duplex_fdd_type_a and self.duplex_mode != NR_DUPLEX_FDD:
            raise Error("eRedCap half-duplex FDD type A requires FDD")


def nr_eredcap_rel18_validate_capabilities(
    capabilities: NRERedCapRel18Capabilities,
) raises -> Bool:
    """Revalidate a possibly-mutated public Rel-18 capability record."""
    capabilities.validate()
    return True


def nr_eredcap_rel18_unicast_prb_limit(
    capabilities: NRERedCapRel18Capabilities,
) raises -> Int:
    """Return the applicable unicast PRB limit.

    TS 38.306 clause 4.2.22.2 specifies 25 PRBs at 15 kHz and 12 PRBs at
    30 kHz.  ``eRedCapNotReducedBB-BW-r18`` removes that reduced-baseband
    component, leaving the 20-MHz FR1 transmission-bandwidth limit of 106 PRBs
    at 15 kHz or 51 PRBs at 30 kHz.
    """
    capabilities.validate()
    if capabilities.not_reduced_baseband_bandwidth:
        return 106 if capabilities.subcarrier_spacing_khz == 15 else 51
    return 25 if capabilities.subcarrier_spacing_khz == 15 else 12


def nr_eredcap_rel18_validate_scheduled_prbs(
    capabilities: NRERedCapRel18Capabilities,
    resource_blocks: Int,
    *,
    is_msg3_msga_or_msg4: Bool = False,
    contention_based_random_access: Bool = False,
) raises -> Bool:
    """Validate the eRedCap reduced-baseband and random-access PRB limits.

    For reduced-baseband eRedCap the 25/12 limit applies to unicast.  For an
    eRedCap UE advertising ``eRedCapNotReducedBB-BW-r18``, the general limit is
    the 20-MHz FR1 transmission-bandwidth configuration (106 or 51 PRBs), while
    the Msg3/MsgA/Msg4 25/12 component still applies during contention-based
    random access.
    """
    capabilities.validate()
    if resource_blocks < 1:
        raise Error("scheduled eRedCap resource blocks must be positive")
    var reduced_limit = 25 if capabilities.subcarrier_spacing_khz == 15 else 12
    var carrier_limit = 106 if capabilities.subcarrier_spacing_khz == 15 else 51
    var use_reduced_limit = not capabilities.not_reduced_baseband_bandwidth or (
        is_msg3_msga_or_msg4 and contention_based_random_access
    )
    var limit = reduced_limit if use_reduced_limit else carrier_limit
    if resource_blocks > limit:
        raise Error("scheduled eRedCap PRBs exceed the applicable bandwidth limit")
    return True


struct NRRedCapInitialBWP(ImplicitlyCopyable, Equatable):
    """One checked initial-BWP geometry used by the RedCap access profile."""

    var start_prb: Int
    var resource_blocks: Int
    var center_frequency_khz: Int
    var subcarrier_spacing_khz: Int

    def __init__(
        out self,
        start_prb: Int,
        resource_blocks: Int,
        center_frequency_khz: Int,
        subcarrier_spacing_khz: Int,
    ) raises:
        self.start_prb = start_prb
        self.resource_blocks = resource_blocks
        self.center_frequency_khz = center_frequency_khz
        self.subcarrier_spacing_khz = subcarrier_spacing_khz
        self.validate()

    def validate(self) raises:
        if self.start_prb < 0 or self.resource_blocks < 1 or self.resource_blocks > 275:
            raise Error("RedCap initial BWP has invalid PRB geometry")
        if self.start_prb > Int.MAX - self.resource_blocks:
            raise Error("RedCap initial BWP PRB end overflows Int")
        if self.center_frequency_khz <= 0:
            raise Error("RedCap initial BWP center frequency must be positive")
        if (
            self.subcarrier_spacing_khz != 15
            and self.subcarrier_spacing_khz != 30
            and self.subcarrier_spacing_khz != 60
            and self.subcarrier_spacing_khz != 120
        ):
            raise Error("RedCap initial BWP SCS must be 15, 30, 60, or 120 kHz")


struct NRInitialBWPSelection(ImplicitlyCopyable, Equatable):
    """Selected ordinary or RedCap-specific BWP width and source."""

    var direction: Int
    var source: Int
    var bandwidth_mhz: Float64

    def __init__(
        out self, direction: Int, source: Int, bandwidth_mhz: Float64
    ):
        self.direction = direction
        self.source = source
        self.bandwidth_mhz = bandwidth_mhz


def nr_redcap_rel17_select_initial_bwp(
    capabilities: NRRedCapRel17Capabilities,
    direction: Int,
    ordinary_bwp_bandwidth_mhz: Float64,
    *,
    redcap_specific_present: Bool = False,
    redcap_specific_bandwidth_mhz: Float64 = 0.0,
) raises -> NRInitialBWPSelection:
    """Apply the TS 38.331 RedCap-specific/fallback initial-BWP rule."""
    capabilities.validate()
    if (
        direction != NR_INITIAL_BWP_DIRECTION_DOWNLINK
        and direction != NR_INITIAL_BWP_DIRECTION_UPLINK
    ):
        raise Error("initial BWP direction must be downlink or uplink")
    var maximum = capabilities.channel_bandwidth_mhz
    if redcap_specific_present:
        if (
            not isfinite(redcap_specific_bandwidth_mhz)
            or redcap_specific_bandwidth_mhz <= 0.0
            or redcap_specific_bandwidth_mhz > maximum
        ):
            raise Error("RedCap-specific initial BWP exceeds UE bandwidth")
        return NRInitialBWPSelection(
            direction,
            NR_INITIAL_BWP_SOURCE_REDCAP_SPECIFIC,
            redcap_specific_bandwidth_mhz,
        )
    if (
        not isfinite(ordinary_bwp_bandwidth_mhz)
        or ordinary_bwp_bandwidth_mhz <= 0.0
        or ordinary_bwp_bandwidth_mhz > maximum
    ):
        raise Error("ordinary initial BWP is not a valid RedCap fallback")
    return NRInitialBWPSelection(
        direction,
        NR_INITIAL_BWP_SOURCE_ORDINARY,
        ordinary_bwp_bandwidth_mhz,
    )


struct NRRedCapRel17InitialAccessConfig(ImplicitlyCopyable):
    """Declared separate-DL/UL-BWP Rel-17 RedCap initial-access profile.

    This configuration intentionally represents the RedCap-specific BWP path.
    Use :func:`nr_redcap_rel17_select_initial_bwp` to model the normative
    ordinary-BWP fallback when either RedCap-specific IE is absent.
    """

    var dl_bwp: NRRedCapInitialBWP
    var ul_bwp: NRRedCapInitialBWP
    var dl_carrier_resource_blocks: Int
    var ul_carrier_resource_blocks: Int
    var dl_purpose: Int
    var separate_dl_bwp_configured: Bool
    var separate_ul_bwp_configured: Bool
    var has_cd_ssb: Bool
    var has_ncd_ssb: Bool
    var contains_coreset0: Bool
    var ra_search_space_configured: Bool
    var ra_coreset_id: Int
    var coreset_start_prb: Int
    var coreset_resource_blocks: Int
    var coreset_duration_symbols: Int
    var monitors_type1_css: Bool
    var monitors_type2_css: Bool
    var ul_rach_configured: Bool
    var ul_msga_configured: Bool
    var common_pucch_configured: Bool
    var common_pucch_frequency_hopping_enabled: Bool

    def __init__(
        out self,
        dl_bwp: NRRedCapInitialBWP,
        ul_bwp: NRRedCapInitialBWP,
        dl_carrier_resource_blocks: Int,
        ul_carrier_resource_blocks: Int,
        dl_purpose: Int,
        *,
        separate_dl_bwp_configured: Bool = True,
        separate_ul_bwp_configured: Bool = True,
        has_cd_ssb: Bool = False,
        has_ncd_ssb: Bool = False,
        contains_coreset0: Bool = False,
        ra_search_space_configured: Bool = True,
        ra_coreset_id: Int = 1,
        coreset_start_prb: Int = 0,
        coreset_resource_blocks: Int = 24,
        coreset_duration_symbols: Int = 2,
        monitors_type1_css: Bool = True,
        monitors_type2_css: Bool = False,
        ul_rach_configured: Bool = True,
        ul_msga_configured: Bool = False,
        common_pucch_configured: Bool = True,
        common_pucch_frequency_hopping_enabled: Bool = False,
    ):
        self.dl_bwp = dl_bwp
        self.ul_bwp = ul_bwp
        self.dl_carrier_resource_blocks = dl_carrier_resource_blocks
        self.ul_carrier_resource_blocks = ul_carrier_resource_blocks
        self.dl_purpose = dl_purpose
        self.separate_dl_bwp_configured = separate_dl_bwp_configured
        self.separate_ul_bwp_configured = separate_ul_bwp_configured
        self.has_cd_ssb = has_cd_ssb
        self.has_ncd_ssb = has_ncd_ssb
        self.contains_coreset0 = contains_coreset0
        self.ra_search_space_configured = ra_search_space_configured
        self.ra_coreset_id = ra_coreset_id
        self.coreset_start_prb = coreset_start_prb
        self.coreset_resource_blocks = coreset_resource_blocks
        self.coreset_duration_symbols = coreset_duration_symbols
        self.monitors_type1_css = monitors_type1_css
        self.monitors_type2_css = monitors_type2_css
        self.ul_rach_configured = ul_rach_configured
        self.ul_msga_configured = ul_msga_configured
        self.common_pucch_configured = common_pucch_configured
        self.common_pucch_frequency_hopping_enabled = (
            common_pucch_frequency_hopping_enabled
        )

    def validate(self, capabilities: NRRedCapRel17Capabilities) raises:
        capabilities.validate()
        self.dl_bwp.validate()
        self.ul_bwp.validate()
        if not self.separate_dl_bwp_configured or not self.separate_ul_bwp_configured:
            raise Error("declared RedCap separate-initial-BWP profile requires both IEs")
        if (
            self.dl_carrier_resource_blocks < 1
            or self.dl_carrier_resource_blocks > 275
            or self.ul_carrier_resource_blocks < 1
            or self.ul_carrier_resource_blocks > 275
        ):
            raise Error("RedCap carrier PRB counts must be in [1,275]")
        if (
            self.dl_bwp.resource_blocks > self.dl_carrier_resource_blocks
            or self.dl_bwp.start_prb
            > self.dl_carrier_resource_blocks - self.dl_bwp.resource_blocks
            or self.ul_bwp.resource_blocks > self.ul_carrier_resource_blocks
            or self.ul_bwp.start_prb
            > self.ul_carrier_resource_blocks - self.ul_bwp.resource_blocks
        ):
            raise Error("RedCap initial BWP exceeds its carrier")
        if capabilities.frequency_range == NR_FREQUENCY_RANGE_FR1:
            if (
                self.dl_bwp.subcarrier_spacing_khz != 15
                and self.dl_bwp.subcarrier_spacing_khz != 30
                and self.dl_bwp.subcarrier_spacing_khz != 60
            ) or (
                self.ul_bwp.subcarrier_spacing_khz != 15
                and self.ul_bwp.subcarrier_spacing_khz != 30
                and self.ul_bwp.subcarrier_spacing_khz != 60
            ):
                raise Error("Rel-17 RedCap FR1 initial BWP has invalid SCS")
        else:
            if (
                self.dl_bwp.subcarrier_spacing_khz != 60
                and self.dl_bwp.subcarrier_spacing_khz != 120
            ) or (
                self.ul_bwp.subcarrier_spacing_khz != 60
                and self.ul_bwp.subcarrier_spacing_khz != 120
            ):
                raise Error("Rel-17 RedCap FR2 initial BWP has invalid SCS")
        var dl_occupied_bandwidth_mhz = Float64(
            self.dl_bwp.resource_blocks
            * 12
            * self.dl_bwp.subcarrier_spacing_khz
        ) / 1000.0
        var ul_occupied_bandwidth_mhz = Float64(
            self.ul_bwp.resource_blocks
            * 12
            * self.ul_bwp.subcarrier_spacing_khz
        ) / 1000.0
        if (
            dl_occupied_bandwidth_mhz > capabilities.channel_bandwidth_mhz
            or ul_occupied_bandwidth_mhz > capabilities.channel_bandwidth_mhz
        ):
            raise Error("RedCap initial BWP occupied bandwidth exceeds UE support")
        if (
            capabilities.duplex_mode == NR_DUPLEX_TDD
            and self.dl_bwp.center_frequency_khz != self.ul_bwp.center_frequency_khz
        ):
            raise Error("unpaired-spectrum RedCap initial DL/UL BWP centers must match")
        if (
            self.dl_purpose != NR_REDCAP_DL_BWP_RACH_ONLY
            and self.dl_purpose != NR_REDCAP_DL_BWP_PAGING
            and self.dl_purpose != NR_REDCAP_DL_BWP_CONNECTED_OPTION_1
        ):
            raise Error("unknown RedCap initial DL BWP purpose")
        if self.dl_purpose == NR_REDCAP_DL_BWP_PAGING and (
            not self.has_cd_ssb or not self.contains_coreset0
        ):
            raise Error("paging RedCap initial DL BWP requires CD-SSB and CORESET#0")
        if self.has_cd_ssb and self.has_ncd_ssb:
            raise Error("a RedCap BWP contains at most one CD-SSB or NCD-SSB")
        if (
            self.dl_purpose == NR_REDCAP_DL_BWP_CONNECTED_OPTION_1
            and not self.has_cd_ssb
        ):
            raise Error("connected option-1 RedCap BWP requires CD-SSB")
        if not self.ra_search_space_configured or not self.monitors_type1_css:
            raise Error("RedCap initial DL BWP requires a Type1 random-access CSS")
        if self.ra_coreset_id < 0 or self.ra_coreset_id > 11:
            raise Error("RedCap random-access CORESET id must be in [0,11]")
        _ = nr_coreset_cce_count(
            self.coreset_resource_blocks, self.coreset_duration_symbols
        )
        if (
            self.coreset_start_prb < 0
            or self.coreset_resource_blocks > self.dl_bwp.resource_blocks
            or self.coreset_start_prb
            > self.dl_bwp.resource_blocks - self.coreset_resource_blocks
        ):
            raise Error("RedCap random-access CORESET exceeds the initial DL BWP")
        if self.monitors_type1_css and not self.monitors_type2_css and (
            self.has_cd_ssb
            or self.has_ncd_ssb
            or self.contains_coreset0
            or self.ra_coreset_id == 0
        ):
            raise Error("Type1-only RedCap initial BWP excludes SS/PBCH and CORESET#0")
        if not self.ul_rach_configured:
            raise Error("RedCap initial UL BWP requires random-access configuration")
        if self.ul_msga_configured and not capabilities.supports_two_step_rach:
            raise Error("MsgA configuration requires two-step RACH capability")
        if not self.common_pucch_configured:
            raise Error("RedCap initial UL BWP requires common PUCCH configuration")


def nr_redcap_rel17_validate_initial_access(
    capabilities: NRRedCapRel17Capabilities,
    config: NRRedCapRel17InitialAccessConfig,
) raises -> Bool:
    """Revalidate the complete separate-BWP initial-access configuration."""
    config.validate(capabilities)
    return True


def nr_redcap_rel17_ra_search_space_first_cces(
    capabilities: NRRedCapRel17Capabilities,
    config: NRRedCapRel17InitialAccessConfig,
    aggregation_level: Int,
    candidate_count: Int,
) raises -> List[Int]:
    """Return common-search-space CCE starts for the RedCap RA CORESET.

    Validation applies the RedCap BWP/CORESET restrictions first; candidate
    arithmetic then delegates to the existing TS 38.213 clause-10.1 kernel.
    """
    config.validate(capabilities)
    var cce_count = nr_coreset_cce_count(
        config.coreset_resource_blocks, config.coreset_duration_symbols
    )
    return nr_search_space_candidate_first_cces(
        cce_count, aggregation_level, candidate_count, 0
    )


def nr_redcap_rel17_early_indication_available(
    capabilities: NRRedCapRel17Capabilities, message_kind: Int
) raises -> Bool:
    """Return mandatory RedCap RA early-indication availability.

    Msg1 and Msg3 are mandatory parts of ``supportOfRedCap-r17``.  MsgA is
    available exactly when the UE also advertises ``twoStepRACH-r16``.
    """
    capabilities.validate()
    if (
        message_kind != NR_REDCAP_RA_MESSAGE_MSG1
        and message_kind != NR_REDCAP_RA_MESSAGE_MSGA
        and message_kind != NR_REDCAP_RA_MESSAGE_MSG3
    ):
        raise Error("unknown RedCap random-access message kind")
    if message_kind == NR_REDCAP_RA_MESSAGE_MSGA:
        return capabilities.supports_two_step_rach
    return True


def nr_eredcap_rel18_early_indication_available(
    capabilities: NRERedCapRel18Capabilities, message_kind: Int
) raises -> Bool:
    """Return eRedCap Msg1/MsgA/Msg3 early-indication availability.

    This reports device capability.  Selection of the separate eRedCap Msg1
    indication remains a network configuration decision and is not invented
    here.
    """
    capabilities.validate()
    if (
        message_kind != NR_REDCAP_RA_MESSAGE_MSG1
        and message_kind != NR_REDCAP_RA_MESSAGE_MSGA
        and message_kind != NR_REDCAP_RA_MESSAGE_MSG3
    ):
        raise Error("unknown eRedCap random-access message kind")
    if message_kind == NR_REDCAP_RA_MESSAGE_MSGA:
        return capabilities.supports_two_step_rach
    return True
