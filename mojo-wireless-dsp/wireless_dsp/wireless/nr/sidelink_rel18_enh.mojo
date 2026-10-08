"""Bounded Rel-18 NR sidelink enhancement decisions.

This scalar CPU reference implements three finite, decoded-configuration
validators from ``NR_SL_enh2`` (Feature UID 940097, Core UID 940197, and
Performance UID 940297):

* Mode-2 LTE/NR sidelink co-channel sharing for 15 kHz and 30 kHz SCS.  A
  30 kHz selection contains the earlier/first NR slot overlapping the LTE
  subframe and may additionally contain the subsequent slot.
* Candidate exclusion when a qualifying decoded E-UTRA SCI reservation
  overlaps the candidate's associated PSFCH occasion and the finite E-UTRA
  PSSCH-RSRP is strictly above the decoded Rel-18 threshold.
* A bounded two-component-carrier ``SL_n47B`` intra-band-contiguous CA
  profile with the same SCS, aligned PSFCH occasions, carrier-local
  resource/SCI/PSSCH operation, and HARQ feedback on the PSSCH carrier.

Normative TS sources:

* 3GPP TS 38.321 V18.10.0 clauses 5.22.1.1, 5.22.1.2b, and 5.22.1.11:
  https://www.3gpp.org/ftp/Specs/archive/38_series/38.321/38321-ia0.zip
* 3GPP TS 38.214 V18.10.0 clauses 8.1 and 8.1.4:
  https://www.3gpp.org/ftp/Specs/archive/38_series/38.214/38214-ia0.zip
* 3GPP TS 38.331 V18.10.0 clauses 5.8.9.1b and 6.3.5:
  https://www.3gpp.org/ftp/Specs/archive/38_series/38.331/38331-ia0.zip
* 3GPP TS 38.300 V18.10.0 clauses 16.9.3.4 and 16.9.10:
  https://www.3gpp.org/ftp/Specs/archive/38_series/38.300/38300-ia0.zip
* 3GPP TS 38.306 V18.10.0 clause 4.2.16.1.6:
  https://www.3gpp.org/ftp/Specs/archive/38_series/38.306/38306-ia0.zip
* 3GPP TS 38.213 V18.8.0 clause 16.3.0:
  https://www.3gpp.org/ftp/Specs/archive/38_series/38.213/38213-i80.zip
* 3GPP TS 38.101-1 V18.14.0 clauses 4.2, 5.2E.1A, and 5.5E.1A.1:
  https://www.3gpp.org/ftp/Specs/archive/38_series/38.101-1/38101-1-ie0.zip

Work Item inventory and scope cross-checks, not normative authorities:

* https://portal.3gpp.org/desktopmodules/WorkItem/WorkItemDetails.aspx?workitemId=940097
* https://www.3gpp.org/ftp/TSG_RAN/TSG_RAN/TSGR_102/Docs/RP-232789.zip
  (SHA-256 ``4d6109c0340c976bbb1f6d1583efd7909eb5d95ccfb423bae6974ac1edf4c7dc``)

The profile is deliberately Rel-18-only: ordinary NR, later-release, Mode-1,
inter-band, non-contiguous, non-n47, mixed-SCS, unaligned-PSFCH, cross-carrier
SCI/resource, and cross-carrier HARQ configurations are rejected.  The CA
carrier ordinals mean increasing RF frequency, never primary/secondary role.

The PSFCH decision assumes the caller already decoded a qualifying LTE SCI
format 1 reservation and selected the applicable priority-indexed threshold.
It does not decode SCI or RRC ASN.1.  Random choice, sensing, CBR/QoS carrier
selection, retransmission scheduling, conflict resolution, SL-U, FR2 beam
management, RF/RRM conformance waveforms, and the other objectives of UID
940097 remain outside this deterministic subset.
"""

from std.math import isfinite


# Explicit profile tags prevent silent use as ordinary NR or a later release.
comptime NR_SL_PROFILE_ORDINARY_NR = 0
comptime NR_SL_PROFILE_REL18_ENH2 = 1
comptime NR_SL_PROFILE_LATER_RELEASE = 2

comptime NR_SL_REL18_MODE2 = 2
comptime NR_SL_REL18_BAND_N47 = 47

# Bit values in the decoded selection mask for one LTE subframe.
comptime NR_SL_REL18_FIRST_OVERLAPPING_SLOT = 0x1
comptime NR_SL_REL18_SUBSEQUENT_OVERLAPPING_SLOT = 0x2


def _validate_rel18_mode2_profile(
    profile: Int, resource_allocation_mode: Int
) raises:
    if profile != NR_SL_PROFILE_REL18_ENH2:
        raise Error("configuration is not the bounded Rel-18 NR_SL_enh2 profile")
    if resource_allocation_mode != NR_SL_REL18_MODE2:
        raise Error("Rel-18 NR_SL_enh2 bounded profile supports Mode 2 only")


def _validate_dynamic_sharing_scs(subcarrier_spacing_khz: Int) raises:
    if subcarrier_spacing_khz != 15 and subcarrier_spacing_khz != 30:
        raise Error("dynamic LTE/NR sidelink sharing requires 15 or 30 kHz SCS")


def _validate_n47_scs(subcarrier_spacing_khz: Int) raises:
    if (
        subcarrier_spacing_khz != 15
        and subcarrier_spacing_khz != 30
        and subcarrier_spacing_khz != 60
    ):
        raise Error("bounded FR1 sidelink n47 SCS must be 15, 30, or 60 kHz")


def _validate_n47b_bandwidth_pair(
    lower_carrier_bandwidth_mhz: Int, upper_carrier_bandwidth_mhz: Int
) raises:
    # TS 38.101-1 Table 5.5E.1A.1-1, carrier columns in increasing
    # frequency: 10+(10/20/30), 20+(20/30), or 30+(30/40) MHz.
    if lower_carrier_bandwidth_mhz == 10:
        if (
            upper_carrier_bandwidth_mhz == 10
            or upper_carrier_bandwidth_mhz == 20
            or upper_carrier_bandwidth_mhz == 30
        ):
            return
    elif lower_carrier_bandwidth_mhz == 20:
        if (
            upper_carrier_bandwidth_mhz == 20
            or upper_carrier_bandwidth_mhz == 30
        ):
            return
    elif lower_carrier_bandwidth_mhz == 30:
        if (
            upper_carrier_bandwidth_mhz == 30
            or upper_carrier_bandwidth_mhz == 40
        ):
            return
    raise Error("channel bandwidth pair is not an SL_n47B table entry")


def _validate_psfch_period_and_phase(period_slots: Int, phase_slots: Int) raises:
    # Decoded non-zero sl-PSFCH-Period values in slots.  This bounded profile
    # evaluates an actual HARQ-feedback-bearing PSFCH operation, not sl0.
    if period_slots != 1 and period_slots != 2 and period_slots != 4:
        raise Error("bounded aligned PSFCH period must be 1, 2, or 4 slots")
    if phase_slots < 0 or phase_slots >= period_slots:
        raise Error("PSFCH phase must be in [0, period_slots)")


def _rsrp_strictly_above_threshold(
    eutra_pssch_rsrp_dbm: Float64, threshold_code: Int
) raises -> Bool:
    if not isfinite(eutra_pssch_rsrp_dbm):
        raise Error("E-UTRA PSSCH-RSRP must be finite")
    if threshold_code < 0 or threshold_code > 66:
        raise Error("SL-Thres-RSRP code must be in [0,66]")
    # TS 38.331 SL-Thres-RSRP: code 0 is -infinity, code 66 is +infinity,
    # and code n in 1..65 is -128 + 2*(n-1) dBm.  TS 38.214 says above,
    # hence equality is deliberately false.
    if threshold_code == 0:
        return True
    if threshold_code == 66:
        return False
    var threshold_dbm = Float64(-128 + 2 * (threshold_code - 1))
    return eutra_pssch_rsrp_dbm > threshold_dbm


struct NRSidelinkRel18CoChannelConfig(ImplicitlyCopyable, Equatable):
    """Decoded Mode-2 LTE/NR co-channel timing profile.

    Times are caller-relative non-negative half-millisecond ticks.  This exact
    unit represents both 15 kHz slots/LTE subframes (two ticks) and 30 kHz
    slots (one tick).  Public fields remain mutable, so every consuming public
    function calls ``validate()`` again.
    """

    var profile: Int
    var resource_allocation_mode: Int
    var subcarrier_spacing_khz: Int
    var lte_subframe_start_half_ms: Int
    var first_nr_slot_start_half_ms: Int

    def __init__(
        out self,
        profile: Int,
        resource_allocation_mode: Int,
        subcarrier_spacing_khz: Int,
        lte_subframe_start_half_ms: Int,
        first_nr_slot_start_half_ms: Int,
    ) raises:
        self.profile = profile
        self.resource_allocation_mode = resource_allocation_mode
        self.subcarrier_spacing_khz = subcarrier_spacing_khz
        self.lte_subframe_start_half_ms = lte_subframe_start_half_ms
        self.first_nr_slot_start_half_ms = first_nr_slot_start_half_ms
        self.validate()

    def validate(self) raises:
        """Revalidate decoded fields after possible public mutation."""
        _validate_rel18_mode2_profile(
            self.profile, self.resource_allocation_mode
        )
        _validate_dynamic_sharing_scs(self.subcarrier_spacing_khz)
        if (
            self.lte_subframe_start_half_ms < 0
            or self.first_nr_slot_start_half_ms < 0
        ):
            raise Error("co-channel timing ticks cannot be negative")
        if (
            self.subcarrier_spacing_khz == 30
            and self.first_nr_slot_start_half_ms
            != self.lte_subframe_start_half_ms
        ):
            raise Error(
                "first 30 kHz NR slot must align with the LTE subframe start"
            )


struct NRSidelinkRel18CAConfig(ImplicitlyCopyable, Equatable):
    """Decoded bounded two-CC ``SL_n47B`` CA profile.

    Carrier 0 and carrier 1 are ordered only by increasing RF frequency.  They
    carry no primary/secondary semantics.  ``intra_band_contiguous`` is the
    decoded/classified CA configuration property; channel bandwidths are then
    checked against the finite RF table.
    """

    var profile: Int
    var resource_allocation_mode: Int
    var carrier_count: Int
    var carrier0_band: Int
    var carrier1_band: Int
    var intra_band_contiguous: Bool
    var carrier0_subcarrier_spacing_khz: Int
    var carrier1_subcarrier_spacing_khz: Int
    var carrier0_channel_bandwidth_mhz: Int
    var carrier1_channel_bandwidth_mhz: Int
    var carrier0_psfch_period_slots: Int
    var carrier1_psfch_period_slots: Int
    var carrier0_psfch_phase_slots: Int
    var carrier1_psfch_phase_slots: Int

    def __init__(
        out self,
        profile: Int,
        resource_allocation_mode: Int,
        carrier_count: Int,
        carrier0_band: Int,
        carrier1_band: Int,
        intra_band_contiguous: Bool,
        carrier0_subcarrier_spacing_khz: Int,
        carrier1_subcarrier_spacing_khz: Int,
        carrier0_channel_bandwidth_mhz: Int,
        carrier1_channel_bandwidth_mhz: Int,
        carrier0_psfch_period_slots: Int,
        carrier1_psfch_period_slots: Int,
        carrier0_psfch_phase_slots: Int,
        carrier1_psfch_phase_slots: Int,
    ) raises:
        self.profile = profile
        self.resource_allocation_mode = resource_allocation_mode
        self.carrier_count = carrier_count
        self.carrier0_band = carrier0_band
        self.carrier1_band = carrier1_band
        self.intra_band_contiguous = intra_band_contiguous
        self.carrier0_subcarrier_spacing_khz = (
            carrier0_subcarrier_spacing_khz
        )
        self.carrier1_subcarrier_spacing_khz = (
            carrier1_subcarrier_spacing_khz
        )
        self.carrier0_channel_bandwidth_mhz = carrier0_channel_bandwidth_mhz
        self.carrier1_channel_bandwidth_mhz = carrier1_channel_bandwidth_mhz
        self.carrier0_psfch_period_slots = carrier0_psfch_period_slots
        self.carrier1_psfch_period_slots = carrier1_psfch_period_slots
        self.carrier0_psfch_phase_slots = carrier0_psfch_phase_slots
        self.carrier1_psfch_phase_slots = carrier1_psfch_phase_slots
        self.validate()

    def validate(self) raises:
        """Revalidate decoded fields after possible public mutation."""
        _validate_rel18_mode2_profile(
            self.profile, self.resource_allocation_mode
        )
        if self.carrier_count != 2:
            raise Error("bounded SL_n47B profile has exactly two carriers")
        if (
            self.carrier0_band != NR_SL_REL18_BAND_N47
            or self.carrier1_band != NR_SL_REL18_BAND_N47
        ):
            raise Error("Rel-18 FR1 sidelink CA bounded profile is n47 only")
        if not self.intra_band_contiguous:
            raise Error("SL_n47B profile requires intra-band contiguous CA")
        _validate_n47_scs(self.carrier0_subcarrier_spacing_khz)
        _validate_n47_scs(self.carrier1_subcarrier_spacing_khz)
        if (
            self.carrier0_subcarrier_spacing_khz
            != self.carrier1_subcarrier_spacing_khz
        ):
            raise Error("aggregated sidelink carriers must use the same SCS")
        _validate_n47b_bandwidth_pair(
            self.carrier0_channel_bandwidth_mhz,
            self.carrier1_channel_bandwidth_mhz,
        )
        _validate_psfch_period_and_phase(
            self.carrier0_psfch_period_slots,
            self.carrier0_psfch_phase_slots,
        )
        _validate_psfch_period_and_phase(
            self.carrier1_psfch_period_slots,
            self.carrier1_psfch_phase_slots,
        )
        if (
            self.carrier0_psfch_period_slots
            != self.carrier1_psfch_period_slots
            or self.carrier0_psfch_phase_slots
            != self.carrier1_psfch_phase_slots
        ):
            raise Error("aggregated sidelink PSFCH occasions must be aligned")


def nr_sl_rel18_mode2_slot_selection_allowed(
    config: NRSidelinkRel18CoChannelConfig, selected_slot_mask: Int
) raises -> Bool:
    """Return whether a decoded co-channel slot selection is admissible.

    Bit zero denotes the first/earlier NR slot overlapping the LTE subframe;
    bit one denotes the subsequent 30 kHz NR slot.  This is an admissibility
    predicate only: it never chooses a slot or implements UE scheduling.
    """
    config.validate()
    if selected_slot_mask < 0 or selected_slot_mask > 0x3:
        raise Error("selected NR slot mask must fit the two-slot domain")
    if config.subcarrier_spacing_khz == 15:
        return selected_slot_mask == NR_SL_REL18_FIRST_OVERLAPPING_SLOT
    # At 30 kHz the earlier slot is mandatory and the subsequent slot is
    # optional.  Thus masks 01 and 11 are the only admissible selections.
    return (
        selected_slot_mask & NR_SL_REL18_FIRST_OVERLAPPING_SLOT
    ) != 0


def nr_sl_rel18_psfch_candidate_excluded(
    config: NRSidelinkRel18CoChannelConfig,
    psfch_start_time_unit: Int,
    psfch_end_time_unit: Int,
    lte_reservation_start_time_unit: Int,
    lte_reservation_end_time_unit: Int,
    eutra_pssch_rsrp_dbm: Float64,
    threshold_code: Int,
) raises -> Bool:
    """Return the gated PSFCH/LTE-reservation exclusion decision.

    Both intervals are in any one caller-chosen integral time unit and are
    interpreted as half-open ``[start, end)`` ranges.  This makes touching
    endpoints non-overlapping and avoids subtraction or addition overflow at
    ``Int.MAX``.  A finite measurement must be strictly above the decoded
    threshold; equality does not exclude the candidate.
    """
    config.validate()
    if psfch_start_time_unit < 0 or psfch_end_time_unit <= psfch_start_time_unit:
        raise Error("PSFCH interval must be non-negative and non-empty")
    if (
        lte_reservation_start_time_unit < 0
        or lte_reservation_end_time_unit
        <= lte_reservation_start_time_unit
    ):
        raise Error("LTE reservation interval must be non-negative and non-empty")
    var above = _rsrp_strictly_above_threshold(
        eutra_pssch_rsrp_dbm, threshold_code
    )
    var overlaps = (
        psfch_start_time_unit < lte_reservation_end_time_unit
        and lte_reservation_start_time_unit < psfch_end_time_unit
    )
    return overlaps and above


def nr_sl_rel18_ca_transmission_allowed(
    config: NRSidelinkRel18CAConfig,
    resource_carrier_index: Int,
    sci_carrier_index: Int,
    pssch_carrier_index: Int,
    harq_feedback_carrier_index: Int,
) raises -> Bool:
    """Return whether one bounded CA transmission stays carrier-local.

    Each index must identify carrier 0 or 1.  A valid operation uses the same
    carrier for its resource, associated SCI/PSCCH, PSSCH, and corresponding
    PSFCH HARQ feedback.  Both indices are treated symmetrically; neither is a
    primary or secondary carrier.
    """
    config.validate()
    if (
        resource_carrier_index < 0
        or resource_carrier_index >= config.carrier_count
        or sci_carrier_index < 0
        or sci_carrier_index >= config.carrier_count
        or pssch_carrier_index < 0
        or pssch_carrier_index >= config.carrier_count
        or harq_feedback_carrier_index < 0
        or harq_feedback_carrier_index >= config.carrier_count
    ):
        raise Error("sidelink CA carrier index must be zero or one")
    return (
        resource_carrier_index == sci_carrier_index
        and sci_carrier_index == pssch_carrier_index
        and pssch_carrier_index == harq_feedback_carrier_index
    )
