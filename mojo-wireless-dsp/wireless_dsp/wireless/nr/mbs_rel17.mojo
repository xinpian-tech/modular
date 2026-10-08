"""Bounded CPU reference arithmetic for Rel-17 NR MBS.

This module implements decoded-configuration portions of the PCG-approved
3GPP Work Item ``NR_MBS`` (UID 860048, WID RP-220428):

* TS 38.211 V17.10.0 clause 4.4.6 common MBS frequency resources;
* TS 38.212 V17.13.0 clauses 7.3.1.5.1--7.3.1.5.2 DCI 4_0/4_1 sizes;
* TS 38.213 V17.13.0 clause 18 NACK-only PUCCH resource selection;
* TS 38.214 V17.16.0 clause 5.1.2.2.2 resource-indication values;
* TS 38.321 V17.15.0 clauses 5.3.1 and 5.8.1a MBS SPS arithmetic;
* TS 38.331 V17.17.0 clauses 5.9.1.3 and 6.3.2/6.3.6 CFR fields.

All PRB coordinates are relative to the first PRB selected by the associated
``offsetToCarrier``.  The caller has already decoded ASN.1 presence choices
and SPS periodicity into an integer number of slots.  The latter is exact for
the Work Item's declared Rel-15 data numerologies (15/30/60/120 kHz).

RRC/MAC message decoding, PDCCH/PDSCH coding and waveforms, DRX, full HARQ
state, bearer/service delivery, core-network control, scheduler policy, SFN
coordination, RF, and conformance operation are outside this bounded module.
Ordinary NR and later-release MBS profiles are rejected rather than silently
being treated as Rel-17 evidence.
"""


comptime NR_MBS_PROFILE_ORDINARY_NR = 0
comptime NR_MBS_PROFILE_REL17 = 1
comptime NR_MBS_PROFILE_LATER_RELEASE = 2

comptime NR_MBS_REL17_MAX_RESOURCE_BLOCKS = 275
comptime NR_MBS_REL17_LOCATION_AND_BANDWIDTH_MAX = 37949
comptime NR_MBS_REL17_MCCH_RNTI = 0xFFFD

comptime NR_MBS_BROADCAST_CFR_ABSENT_CORESET0 = 0
comptime NR_MBS_BROADCAST_CFR_SAME_AS_INITIAL_BWP = 1
comptime NR_MBS_BROADCAST_CFR_EXPLICIT_RIV = 2


def _validate_rel17_profile(profile: Int) raises:
    if profile != NR_MBS_PROFILE_REL17:
        raise Error("NR MBS arithmetic requires the Rel-17 MBS profile")


def _validate_cfr(start_prb: Int, size_prbs: Int) raises:
    if start_prb < 0 or start_prb >= NR_MBS_REL17_MAX_RESOURCE_BLOCKS:
        raise Error("MBS CFR start PRB must be in the 275-RB RIV domain")
    if size_prbs < 1 or size_prbs > NR_MBS_REL17_MAX_RESOURCE_BLOCKS:
        raise Error("MBS CFR size must be in [1, 275] PRBs")
    if start_prb > NR_MBS_REL17_MAX_RESOURCE_BLOCKS - size_prbs:
        raise Error("MBS CFR extends beyond the 275-RB RIV domain")


struct NRMBSRel17CFR(ImplicitlyCopyable, Equatable):
    """One decoded contiguous common MBS frequency resource.

    Fields remain public for readable golden-reference checkpoints.  Every
    public consumer revalidates them so mutation cannot bypass the contract.
    """

    var start_prb: Int
    var size_prbs: Int

    def __init__(out self, start_prb: Int, size_prbs: Int) raises:
        self.start_prb = start_prb
        self.size_prbs = size_prbs
        self.validate()

    def validate(self) raises:
        """Revalidate the public mutable CFR fields."""
        _validate_cfr(self.start_prb, self.size_prbs)

    def end_prb_exclusive(self) raises -> Int:
        """Return the checked exclusive PRB end."""
        self.validate()
        return self.start_prb + self.size_prbs


struct NRMBSRel17MCCHChange(ImplicitlyCopyable, Equatable):
    """Decoded TS 38.331 clause-5.9.1.3 notification bits."""

    var new_service_started: Bool
    var other_mcch_information_modified: Bool

    def __init__(
        out self,
        new_service_started: Bool,
        other_mcch_information_modified: Bool,
    ):
        self.new_service_started = new_service_started
        self.other_mcch_information_modified = (
            other_mcch_information_modified
        )


def _decode_location_and_bandwidth_riv(
    location_and_bandwidth: Int,
) raises -> NRMBSRel17CFR:
    if location_and_bandwidth < 0 or (
        location_and_bandwidth
        > NR_MBS_REL17_LOCATION_AND_BANDWIDTH_MAX
    ):
        raise Error("MBS locationAndBandwidth is outside INTEGER(0..37949)")

    # TS 38.214 RIV inversion with N_RB^size_BWP fixed to 275.  The shorter
    # interpretation is selected when it fits; otherwise the complementary
    # long allocation is the only valid interpretation.
    var quotient = (
        location_and_bandwidth // NR_MBS_REL17_MAX_RESOURCE_BLOCKS
    )
    var remainder = (
        location_and_bandwidth % NR_MBS_REL17_MAX_RESOURCE_BLOCKS
    )
    var short_size = quotient + 1
    if remainder <= NR_MBS_REL17_MAX_RESOURCE_BLOCKS - short_size:
        return NRMBSRel17CFR(remainder, short_size)
    return NRMBSRel17CFR(
        NR_MBS_REL17_MAX_RESOURCE_BLOCKS - 1 - remainder,
        NR_MBS_REL17_MAX_RESOURCE_BLOCKS - quotient + 1,
    )


def _contains(outer: NRMBSRel17CFR, inner: NRMBSRel17CFR) raises -> Bool:
    outer.validate()
    inner.validate()
    return (
        outer.start_prb <= inner.start_prb
        and outer.end_prb_exclusive() >= inner.end_prb_exclusive()
    )


def nr_mbs_rel17_multicast_cfr(
    location_and_bandwidth_present: Bool,
    location_and_bandwidth: Int,
    dl_bwp_start_prb: Int,
    dl_bwp_size_prbs: Int,
    *,
    profile: Int = NR_MBS_PROFILE_REL17,
) raises -> NRMBSRel17CFR:
    """Resolve ``CFR-ConfigMulticast-r17`` frequency geometry.

    TS 38.331 fixes the explicit RIV domain to 275 RBs.  If the optional
    field is absent, clause 18 of TS 38.213 makes the CFR equal to its DL
    BWP.  An explicit multicast CFR must be contained in that BWP.  A zero
    value is required for the unused argument when the field is absent.
    """
    _validate_rel17_profile(profile)
    var bwp = NRMBSRel17CFR(dl_bwp_start_prb, dl_bwp_size_prbs)
    if not location_and_bandwidth_present:
        if location_and_bandwidth != 0:
            raise Error("an absent multicast CFR RIV must use value zero")
        return bwp
    var cfr = _decode_location_and_bandwidth_riv(location_and_bandwidth)
    if not _contains(bwp, cfr):
        raise Error("a multicast CFR must be within its associated DL BWP")
    return cfr


def nr_mbs_rel17_broadcast_cfr(
    source: Int,
    location_and_bandwidth: Int,
    initial_bwp_start_prb: Int,
    initial_bwp_size_prbs: Int,
    coreset0_start_prb: Int,
    coreset0_size_prbs: Int,
    *,
    profile: Int = NR_MBS_PROFILE_REL17,
) raises -> NRMBSRel17CFR:
    """Resolve the three ``CFR-ConfigMCCH-MTCH-r17`` choices.

    An absent field selects CORESET#0, ``sameAsSib1ConfiguredLocationAndBW``
    selects the initial DL BWP, and an explicit RIV must have a bandwidth
    larger than and fully contain both the initial DL BWP and CORESET#0.
    Non-explicit choices require the unused RIV argument to be zero.
    """
    _validate_rel17_profile(profile)
    var initial_bwp = NRMBSRel17CFR(
        initial_bwp_start_prb, initial_bwp_size_prbs
    )
    var coreset0 = NRMBSRel17CFR(coreset0_start_prb, coreset0_size_prbs)
    if source == NR_MBS_BROADCAST_CFR_ABSENT_CORESET0:
        if location_and_bandwidth != 0:
            raise Error("an absent broadcast CFR RIV must use value zero")
        return coreset0
    if source == NR_MBS_BROADCAST_CFR_SAME_AS_INITIAL_BWP:
        if location_and_bandwidth != 0:
            raise Error("same-as-initial broadcast CFR must use RIV zero")
        return initial_bwp
    if source != NR_MBS_BROADCAST_CFR_EXPLICIT_RIV:
        raise Error("invalid Rel-17 broadcast CFR source")

    var cfr = _decode_location_and_bandwidth_riv(location_and_bandwidth)
    if cfr.size_prbs <= initial_bwp.size_prbs:
        raise Error("an explicit broadcast CFR must be wider than initial BWP")
    if not _contains(cfr, initial_bwp) or not _contains(cfr, coreset0):
        raise Error("an explicit broadcast CFR must contain BWP and CORESET#0")
    return cfr


def _type1_frequency_assignment_bits(resource_blocks: Int) raises -> Int:
    if resource_blocks < 1 or (
        resource_blocks > NR_MBS_REL17_MAX_RESOURCE_BLOCKS
    ):
        raise Error("DCI 4_0/4_1 resource size must be in [1, 275]")
    var allocation_count = resource_blocks * (resource_blocks + 1) // 2
    var bits = 0
    var capacity = 1
    while capacity < allocation_count:
        capacity *= 2
        bits += 1
    return bits


def _dci_4_0_4_1_payload_bits(
    coreset0_configured: Bool,
    coreset0_size_prbs: Int,
    initial_dl_bwp_size_prbs: Int,
) raises -> Int:
    if initial_dl_bwp_size_prbs < 1 or (
        initial_dl_bwp_size_prbs > NR_MBS_REL17_MAX_RESOURCE_BLOCKS
    ):
        raise Error("initial DL BWP size must be in [1, 275]")
    var resource_blocks = initial_dl_bwp_size_prbs
    if coreset0_configured:
        if coreset0_size_prbs < 1 or (
            coreset0_size_prbs > NR_MBS_REL17_MAX_RESOURCE_BLOCKS
        ):
            raise Error("configured CORESET#0 size must be in [1, 275]")
        resource_blocks = coreset0_size_prbs
    elif coreset0_size_prbs != 0:
        raise Error("an absent CORESET#0 must use size zero")
    # Both formats have 28 fixed information bits in their Rel-17 clauses.
    return _type1_frequency_assignment_bits(resource_blocks) + 28


def nr_mbs_rel17_dci_4_0_payload_bits(
    coreset0_configured: Bool,
    coreset0_size_prbs: Int,
    initial_dl_bwp_size_prbs: Int,
    *,
    profile: Int = NR_MBS_PROFILE_REL17,
) raises -> Int:
    """Return exact TS 38.212 clause-7.3.1.5.1 DCI 4_0 payload size."""
    _validate_rel17_profile(profile)
    return _dci_4_0_4_1_payload_bits(
        coreset0_configured, coreset0_size_prbs, initial_dl_bwp_size_prbs
    )


def nr_mbs_rel17_dci_4_1_payload_bits(
    coreset0_configured: Bool,
    coreset0_size_prbs: Int,
    initial_dl_bwp_size_prbs: Int,
    *,
    profile: Int = NR_MBS_PROFILE_REL17,
) raises -> Int:
    """Return exact TS 38.212 clause-7.3.1.5.2 DCI 4_1 payload size."""
    _validate_rel17_profile(profile)
    return _dci_4_0_4_1_payload_bits(
        coreset0_configured, coreset0_size_prbs, initial_dl_bwp_size_prbs
    )


def nr_mbs_rel17_mcch_change_notification(
    bitmap: Int,
    rnti: Int = NR_MBS_REL17_MCCH_RNTI,
    *,
    profile: Int = NR_MBS_PROFILE_REL17,
) raises -> NRMBSRel17MCCHChange:
    """Decode the exact two-bit MCCH change notification bitmap.

    The MSB announces the start of new MBS service(s); the LSB announces
    another MCCH-information modification.
    """
    _validate_rel17_profile(profile)
    if rnti != NR_MBS_REL17_MCCH_RNTI:
        raise Error("MCCH change bits are valid only with MCCH-RNTI 0xFFFD")
    if bitmap < 0 or bitmap > 3:
        raise Error("MCCH change notification must be a two-bit bitmap")
    return NRMBSRel17MCCHChange((bitmap & 2) != 0, (bitmap & 1) != 0)


def nr_mbs_rel17_nack_only_pucch_resource(
    harq_ack_bits: Span[Int, ...],
    more_than_one_nack_only_mode: Bool,
    *,
    profile: Int = NR_MBS_PROFILE_REL17,
) raises -> Int:
    """Select the TS 38.213 Table-18-1 PUCCH resource ordinal.

    One to four bits are supplied in the table's displayed left-to-right
    order, with 0=NACK and 1=ACK.  The first bit is the least-significant
    resource-selection bit.  The result is 1--15, or zero when all bits are
    ACK and the second reporting mode suppresses the PUCCH transmission.
    ``more_than_one_nack_only_mode`` must be true because otherwise the
    multi-bit Table-18-1 resource-selection procedure is not applicable.
    """
    _validate_rel17_profile(profile)
    if not more_than_one_nack_only_mode:
        raise Error("Table 18-1 requires moreThanOneNackOnlyMode")
    if len(harq_ack_bits) < 1 or len(harq_ack_bits) > 4:
        raise Error("NACK-only MBS feedback requires one to four bits")
    var all_ack = True
    var encoded = 0
    for bit_index in range(len(harq_ack_bits)):
        var bit = harq_ack_bits[bit_index]
        if bit != 0 and bit != 1:
            raise Error("MBS HARQ-ACK values must be zero or one")
        if bit == 0:
            all_ack = False
        else:
            encoded |= 1 << bit_index
    if all_ack:
        return 0
    return encoded + 1


def _validate_sps_slot_domain(
    slots_per_frame: Int, periodicity_slots: Int
) raises:
    if (
        slots_per_frame != 10
        and slots_per_frame != 20
        and slots_per_frame != 40
        and slots_per_frame != 80
    ):
        raise Error("unsupported Rel-17 SPS data SCS slot domain")
    # TS 38.331 periodicityExt supports at most 640 ms.  Expressed in slots,
    # that is 64 frames for every admitted SCS.
    if periodicity_slots < 1 or periodicity_slots > 64 * slots_per_frame:
        raise Error("MBS SPS periodicity is outside its Rel-17 SCS range")


def _validate_sfn_slot(
    sfn: Int, slot_in_frame: Int, slots_per_frame: Int
) raises:
    if sfn < 0 or sfn > 1023:
        raise Error("NR SFN must be in [0, 1023]")
    if slot_in_frame < 0 or slot_in_frame >= slots_per_frame:
        raise Error("slot number is outside the selected NR frame")


def nr_mbs_rel17_sps_occasion_slot(
    start_sfn: Int,
    start_slot_in_frame: Int,
    occurrence_index: Int,
    slots_per_frame: Int,
    periodicity_slots: Int,
    *,
    profile: Int = NR_MBS_PROFILE_REL17,
) raises -> Int:
    """Return the cyclic absolute slot of MBS SPS occurrence ``N``.

    This is TS 38.321 clause 5.8.1a after exactly decoding
    ``periodicity * numberOfSlotsPerFrame / 10`` into ``periodicity_slots``.
    The result is in ``[0, 1024*slots_per_frame)``.  Int128 intermediates
    make even ``occurrence_index == Int.MAX`` deterministic and checked.
    """
    _validate_rel17_profile(profile)
    _validate_sps_slot_domain(slots_per_frame, periodicity_slots)
    _validate_sfn_slot(start_sfn, start_slot_in_frame, slots_per_frame)
    if occurrence_index < 0:
        raise Error("MBS SPS occurrence index N must be non-negative")
    var cycle = 1024 * slots_per_frame
    var start_slot = start_sfn * slots_per_frame + start_slot_in_frame
    var result = (
        Int128(start_slot)
        + Int128(occurrence_index) * Int128(periodicity_slots)
    ) % Int128(cycle)
    return Int(result)


def nr_mbs_rel17_sps_harq_process_id(
    sfn: Int,
    slot_in_frame: Int,
    slots_per_frame: Int,
    periodicity_slots: Int,
    nrof_harq_processes: Int,
    harq_process_offset: Int = 0,
    *,
    profile: Int = NR_MBS_PROFILE_REL17,
) raises -> Int:
    """Return the clause-5.3.1 HARQ process for an MBS SPS slot.

    ``harq_process_offset`` is zero when the optional RRC field is absent.
    The bounded Rel-17 profile admits the extended 1--32 process domain and
    ensures the configured offset range remains within HARQ IDs 0--31.
    """
    _validate_rel17_profile(profile)
    _validate_sps_slot_domain(slots_per_frame, periodicity_slots)
    _validate_sfn_slot(sfn, slot_in_frame, slots_per_frame)
    if nrof_harq_processes < 1 or nrof_harq_processes > 32:
        raise Error("MBS SPS requires one to 32 HARQ processes")
    if harq_process_offset < 0 or (
        harq_process_offset > 32 - nrof_harq_processes
    ):
        raise Error("MBS SPS HARQ process range exceeds IDs 0--31")
    var current_slot = sfn * slots_per_frame + slot_in_frame
    return (
        (current_slot // periodicity_slots) % nrof_harq_processes
        + harq_process_offset
    )
