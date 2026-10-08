"""Bounded Rel-18 NR-NTN RACH-less handover CG decisions.

This scalar CPU reference implements a closed, decoded-configuration subset
of the Rel-18 ``NR_NTN_enh`` feature (UID 941006, Core UID 941106):

* 3GPP TS 38.213 V18.8.0 clause 22.1 ordering of SS/PBCH block indexes onto
  Type-1 configured-grant PUSCH occasions and their DM-RS resources;
* TS 38.321 V18.10.0 clauses 5.8.2 and 5.33 selection of an SSB whose latest
  unfiltered L1 SS-RSRP is strictly above ``cg-RRC-RSRP-ThresholdSSB``; and
* TS 38.331 V18.10.0 clause 6.3.2 decoded ``CG-RRC-Configuration-r18``,
  ``RSRP-Range``, bitmap, and ``rrc-SSB-PerCG-PUSCH`` field semantics.

Normative TS sources:

* https://www.3gpp.org/ftp/Specs/archive/38_series/38.213/38213-i80.zip
* https://www.3gpp.org/ftp/Specs/archive/38_series/38.321/38321-ia0.zip
* https://www.3gpp.org/ftp/Specs/archive/38_series/38.331/38331-ia0.zip

Work Item inventory and scope cross-checks, not normative authorities:

* https://portal.3gpp.org/desktopmodules/WorkItem/WorkItemDetails.aspx?workitemId=941006
* https://www.3gpp.org/ftp/tsg_ran/TSG_RAN/TSGR_103/Docs/RP-240779.zip

The exact profile is FDD, one valid Type-1 CG PUSCH occasion per configured
grant period, ``repK=1``, DM-RS type 1, a nonempty decoded short (4-bit) or
medium (8-bit) SSB subset, and a nonempty eight-bit DM-RS port subset.  The
returned resource ordinal is within one complete SSB-to-PUSCH mapping cycle.
The caller owns the actual periodicity, PRACH overlap and occasion-validity
schedule.

Long 64-bit SSB subsets, DM-RS type 2, repetitions, TDD gap checks, association
period construction, retransmission/HARQ state, dynamic-grant handover,
RRC/ASN.1 decoding, orbit and RF measurements, network deployment policy, and
the remaining coverage, positioning, mobility, FR2-NTN and protocol objectives
of UID 941006 are deliberately outside this bounded subset.
"""

from std.math import isfinite


# ASN.1 ENUMERATED order from CG-RRC-Configuration-r18.
comptime NR_NTN_REL18_SSB_PER_CG_ONE_EIGHTH = 0
comptime NR_NTN_REL18_SSB_PER_CG_ONE_FOURTH = 1
comptime NR_NTN_REL18_SSB_PER_CG_HALF = 2
comptime NR_NTN_REL18_SSB_PER_CG_ONE = 3
comptime NR_NTN_REL18_SSB_PER_CG_TWO = 4
comptime NR_NTN_REL18_SSB_PER_CG_FOUR = 5
comptime NR_NTN_REL18_SSB_PER_CG_EIGHT = 6
comptime NR_NTN_REL18_SSB_PER_CG_SIXTEEN = 7


def _ssb_per_cg_ratio(code: Int) raises -> Tuple[Int, Int]:
    # Exact (numerator, denominator) table in ASN.1 enumeration order.
    if code == NR_NTN_REL18_SSB_PER_CG_ONE_EIGHTH:
        return (1, 8)
    if code == NR_NTN_REL18_SSB_PER_CG_ONE_FOURTH:
        return (1, 4)
    if code == NR_NTN_REL18_SSB_PER_CG_HALF:
        return (1, 2)
    if code == NR_NTN_REL18_SSB_PER_CG_ONE:
        return (1, 1)
    if code == NR_NTN_REL18_SSB_PER_CG_TWO:
        return (2, 1)
    if code == NR_NTN_REL18_SSB_PER_CG_FOUR:
        return (4, 1)
    if code == NR_NTN_REL18_SSB_PER_CG_EIGHT:
        return (8, 1)
    if code == NR_NTN_REL18_SSB_PER_CG_SIXTEEN:
        return (16, 1)
    raise Error("rrc-SSB-PerCG-PUSCH-r18 enum must be in [0,7]")


def _bitmap_limit(width: Int) raises -> Int:
    if width == 4:
        return 0xF
    if width == 8:
        return 0xFF
    raise Error("bounded Rel-18 NTN SSB bitmap width must be 4 or 8")


def _bitmap_contains(bitmap: Int, width: Int, index: Int) -> Bool:
    # ASN.1 BIT STRING order: its leftmost/MSB bit denotes index zero.
    return (bitmap & (1 << (width - 1 - index))) != 0


def _bitmap_count(bitmap: Int, width: Int) -> Int:
    var count = 0
    for index in range(width):
        if _bitmap_contains(bitmap, width, index):
            count += 1
    return count


def _selected_ordinal(bitmap: Int, width: Int, selected_index: Int) raises -> Int:
    if selected_index < 0 or selected_index >= width:
        raise Error("selected bitmap index is outside its decoded width")
    var ordinal = 0
    for index in range(width):
        if _bitmap_contains(bitmap, width, index):
            if index == selected_index:
                return ordinal
            ordinal += 1
    raise Error("selected index is absent from the decoded bitmap")


def _selected_index(bitmap: Int, width: Int, ordinal: Int) raises -> Int:
    if ordinal < 0:
        raise Error("selected bitmap ordinal cannot be negative")
    var current = 0
    for index in range(width):
        if _bitmap_contains(bitmap, width, index):
            if current == ordinal:
                return index
            current += 1
    raise Error("selected bitmap ordinal is outside the decoded set")


struct NRNTNRel18RACHlessCGConfig(ImplicitlyCopyable, Equatable):
    """Decoded bounded ``CG-RRC-Configuration-r18`` mapping fields.

    ``ssb_subset_bitmap`` and ``dmrs_port_bitmap`` retain ASN.1 BIT STRING
    orientation: the most-significant in-width bit represents index zero.
    Public fields intentionally remain mutable; every public algorithm calls
    ``validate()`` again before observing them.
    """

    var ssb_bitmap_width: Int
    var ssb_subset_bitmap: Int
    var ssb_per_cg_pusch: Int
    var dmrs_port_bitmap: Int
    var dmrs_sequence_count: Int

    def __init__(
        out self,
        ssb_bitmap_width: Int,
        ssb_subset_bitmap: Int,
        ssb_per_cg_pusch: Int,
        dmrs_port_bitmap: Int,
        dmrs_sequence_count: Int,
    ) raises:
        self.ssb_bitmap_width = ssb_bitmap_width
        self.ssb_subset_bitmap = ssb_subset_bitmap
        self.ssb_per_cg_pusch = ssb_per_cg_pusch
        self.dmrs_port_bitmap = dmrs_port_bitmap
        self.dmrs_sequence_count = dmrs_sequence_count
        self.validate()

    def validate(self) raises:
        """Revalidate decoded fields after possible public mutation."""
        var ssb_limit = _bitmap_limit(self.ssb_bitmap_width)
        if (
            self.ssb_subset_bitmap <= 0
            or self.ssb_subset_bitmap > ssb_limit
        ):
            raise Error("Rel-18 NTN SSB subset bitmap is empty or out of width")
        _ = _ssb_per_cg_ratio(self.ssb_per_cg_pusch)
        if self.dmrs_port_bitmap <= 0 or self.dmrs_port_bitmap > 0xFF:
            raise Error("bounded Rel-18 NTN DM-RS type-1 bitmap is 8 bits")
        if self.dmrs_sequence_count < 1 or self.dmrs_sequence_count > 2:
            raise Error("rrc-NrofDMRS-Sequences-r18 must be one or two")


struct NRNTNRel18RACHlessCGMapping(ImplicitlyCopyable, Equatable):
    """One exact SSB-to-CG-PUSCH/DM-RS association in a mapping cycle."""

    var ssb_index: Int
    var ssb_ordinal: Int
    var ssb_group_first_index: Int
    var ssb_group_first_ordinal: Int
    var ssb_group_size: Int
    var mapping_replica_index: Int
    var resource_ordinal: Int
    var pusch_configuration_period_index: Int
    var dmrs_resource_index: Int
    var dmrs_port_index: Int
    var dmrs_sequence_index: Int

    def __init__(
        out self,
        ssb_index: Int,
        ssb_ordinal: Int,
        ssb_group_first_index: Int,
        ssb_group_first_ordinal: Int,
        ssb_group_size: Int,
        mapping_replica_index: Int,
        resource_ordinal: Int,
        pusch_configuration_period_index: Int,
        dmrs_resource_index: Int,
        dmrs_port_index: Int,
        dmrs_sequence_index: Int,
    ):
        self.ssb_index = ssb_index
        self.ssb_ordinal = ssb_ordinal
        self.ssb_group_first_index = ssb_group_first_index
        self.ssb_group_first_ordinal = ssb_group_first_ordinal
        self.ssb_group_size = ssb_group_size
        self.mapping_replica_index = mapping_replica_index
        self.resource_ordinal = resource_ordinal
        self.pusch_configuration_period_index = (
            pusch_configuration_period_index
        )
        self.dmrs_resource_index = dmrs_resource_index
        self.dmrs_port_index = dmrs_port_index
        self.dmrs_sequence_index = dmrs_sequence_index


def nr_ntn_rel18_cg_ssb_above_threshold(
    latest_unfiltered_l1_ss_rsrp_dbm: Float64, threshold_rsrp_range: Int
) raises -> Bool:
    """Return the strict Rel-18 CG SSB threshold decision.

    TS 38.331 defines a threshold ``RSRP-Range`` value ``n`` below 127 as
    ``n - 156`` dBm and value 127 as positive infinity.  TS 38.321 requires
    SS-RSRP to be *above* that threshold and uses the latest unfiltered L1
    measurement.  Non-finite measured values are never accepted as RF data.
    """
    if not isfinite(latest_unfiltered_l1_ss_rsrp_dbm):
        raise Error("latest unfiltered L1 SS-RSRP must be finite")
    if threshold_rsrp_range < 0 or threshold_rsrp_range > 127:
        raise Error("cg-RRC-RSRP-ThresholdSSB must be RSRP-Range 0..127")
    if threshold_rsrp_range == 127:
        return False
    var threshold_dbm = Float64(threshold_rsrp_range - 156)
    return latest_unfiltered_l1_ss_rsrp_dbm > threshold_dbm


def nr_ntn_rel18_cg_resources_per_mapping_cycle(
    config: NRNTNRel18RACHlessCGConfig,
) raises -> Int:
    """Return CG-PUSCH/DM-RS resource pairs needed for one mapping cycle."""
    config.validate()
    var ratio = _ssb_per_cg_ratio(config.ssb_per_cg_pusch)
    var ssb_count = _bitmap_count(
        config.ssb_subset_bitmap, config.ssb_bitmap_width
    )
    # Exact ceil(ssb_count / N), with N represented as numerator/denominator.
    var scaled = Int128(ssb_count) * Int128(ratio[1])
    var resources = (
        scaled + Int128(ratio[0]) - Int128(1)
    ) // Int128(ratio[0])
    if resources <= 0 or resources > Int128(Int.MAX):
        raise Error("Rel-18 NTN mapping-cycle size is not representable")
    return Int(resources)


def nr_ntn_rel18_cg_mapping(
    config: NRNTNRel18RACHlessCGConfig,
    ssb_index: Int,
    mapping_replica_index: Int = 0,
) raises -> NRNTNRel18RACHlessCGMapping:
    """Map one configured SSB to its ordered CG-PUSCH/DM-RS resource.

    Fractional ``rrc-SSB-PerCG-PUSCH`` values map one SSB to respectively
    eight, four, or two resource pairs; ``mapping_replica_index`` selects one
    of those associations.  For values one through sixteen it must be zero.
    The profile has one valid PUSCH occasion per configuration period, so the
    resource ordinal is decomposed DM-RS-resource-first and period-second.
    Within ``DMRSid``, port index advances first and sequence index second.
    """
    config.validate()
    var ssb_ordinal = _selected_ordinal(
        config.ssb_subset_bitmap, config.ssb_bitmap_width, ssb_index
    )
    var ratio = _ssb_per_cg_ratio(config.ssb_per_cg_pusch)
    var numerator = ratio[0]
    var denominator = ratio[1]
    var ssb_count = _bitmap_count(
        config.ssb_subset_bitmap, config.ssb_bitmap_width
    )

    var resource_ordinal: Int
    var group_first_ordinal: Int
    var group_size = 1
    if denominator > 1:
        if (
            mapping_replica_index < 0
            or mapping_replica_index >= denominator
        ):
            raise Error("fractional SSB-per-CG replica index is out of range")
        resource_ordinal = ssb_ordinal * denominator + mapping_replica_index
        group_first_ordinal = ssb_ordinal
    else:
        if mapping_replica_index != 0:
            raise Error("integer SSB-per-CG mapping has only replica zero")
        resource_ordinal = ssb_ordinal // numerator
        group_first_ordinal = resource_ordinal * numerator
        group_size = min(numerator, ssb_count - group_first_ordinal)

    var port_count = _bitmap_count(config.dmrs_port_bitmap, 8)
    var dmrs_resource_count = port_count * config.dmrs_sequence_count
    var dmrs_resource_index = resource_ordinal % dmrs_resource_count
    # "First" port ordering is the inner/fastest-varying index; after all
    # selected ports, the DM-RS sequence index advances.
    var port_ordinal = dmrs_resource_index % port_count
    var sequence_index = dmrs_resource_index // port_count
    var port_index = _selected_index(
        config.dmrs_port_bitmap, 8, port_ordinal
    )
    var period_index = resource_ordinal // dmrs_resource_count
    var group_first_index = _selected_index(
        config.ssb_subset_bitmap,
        config.ssb_bitmap_width,
        group_first_ordinal,
    )

    return NRNTNRel18RACHlessCGMapping(
        ssb_index,
        ssb_ordinal,
        group_first_index,
        group_first_ordinal,
        group_size,
        mapping_replica_index,
        resource_ordinal,
        period_index,
        dmrs_resource_index,
        port_index,
        sequence_index,
    )
