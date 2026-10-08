"""Rel-17 RedCap PRACH placement in the separate initial uplink BWP.

This scalar CPU reference binds the existing normalized PRACH sequence chain
to the decoded ``initialUplinkBWP-RedCap`` frequency geometry required by
3GPP TS 38.211 V17.10.0 clauses 5.3.2 and 6.3.3.2.  PRACH frequency
resources are numbered in increasing order from ``msg1-FrequencyStart`` or,
for two-step random access, ``msgA-RO-FrequencyStart``.  Every configured
occasion is required to fit inside the initial uplink BWP and carrier grid.

The complete Rel-17 RedCap-applicable subset of Table 6.3.3.2-1 is exposed as
an exact lookup.  The low-level placement API can also accept an already
decoded allocation.  This module deliberately does not synthesize the
time-continuous radio-rate OFDM signal or decode RRC ASN.1.  The nested PRACH
waveform remains the sequence-sample normalized reference implemented by
``nr_prach_normalized_composite``.
"""

from .prach import (
    NRPRACHFormat,
    NRPRACHNormalizedCompositeResult,
    nr_prach_normalized_composite,
)
from .redcap import (
    NR_FREQUENCY_RANGE_FR1,
    NR_FREQUENCY_RANGE_FR2,
    NRRedCapInitialBWP,
    NRRedCapRel17Capabilities,
)


comptime NR_REDCAP_PRACH_SOURCE_MSG1 = 1
comptime NR_REDCAP_PRACH_SOURCE_MSGA = 2


struct NRRedCapPRACHResourceAllocation(ImplicitlyCopyable, Equatable):
    """One exact TS 38.211 Table 6.3.3.2-1 allocation row."""

    var sequence_length: Int
    var prach_subcarrier_spacing_hz: Int
    var pusch_subcarrier_spacing_khz: Int
    var resource_blocks: Int
    var k_bar: Int

    def __init__(
        out self,
        sequence_length: Int,
        prach_subcarrier_spacing_hz: Int,
        pusch_subcarrier_spacing_khz: Int,
        resource_blocks: Int,
        k_bar: Int,
    ):
        self.sequence_length = sequence_length
        self.prach_subcarrier_spacing_hz = prach_subcarrier_spacing_hz
        self.pusch_subcarrier_spacing_khz = pusch_subcarrier_spacing_khz
        self.resource_blocks = resource_blocks
        self.k_bar = k_bar


struct NRRedCapPRACHFrequencyPlacement(ImplicitlyCopyable, Equatable):
    """One checked PRACH frequency occasion in common-grid RB coordinates."""

    var source: Int
    var frequency_occasion_index: Int
    var frequency_occasion_count: Int
    var resource_blocks: Int
    var start_prb_in_initial_bwp: Int
    var start_common_resource_block: Int
    var end_common_resource_block_exclusive: Int
    var lowest_common_grid_subcarrier: Int

    def __init__(
        out self,
        source: Int,
        frequency_occasion_index: Int,
        frequency_occasion_count: Int,
        resource_blocks: Int,
        start_prb_in_initial_bwp: Int,
        start_common_resource_block: Int,
        end_common_resource_block_exclusive: Int,
        lowest_common_grid_subcarrier: Int,
    ):
        self.source = source
        self.frequency_occasion_index = frequency_occasion_index
        self.frequency_occasion_count = frequency_occasion_count
        self.resource_blocks = resource_blocks
        self.start_prb_in_initial_bwp = start_prb_in_initial_bwp
        self.start_common_resource_block = start_common_resource_block
        self.end_common_resource_block_exclusive = (
            end_common_resource_block_exclusive
        )
        self.lowest_common_grid_subcarrier = lowest_common_grid_subcarrier


struct NRRedCapPRACHPlacedCompositeResult(Movable):
    """Owned RedCap BWP placement plus the normalized PRACH checkpoints."""

    var placement: NRRedCapPRACHFrequencyPlacement
    var normalized: NRPRACHNormalizedCompositeResult

    def __init__(
        out self,
        placement: NRRedCapPRACHFrequencyPlacement,
        var normalized: NRPRACHNormalizedCompositeResult,
    ):
        self.placement = placement
        self.normalized = normalized^


def _validate_redcap_initial_uplink_bwp(
    capabilities: NRRedCapRel17Capabilities,
    bwp: NRRedCapInitialBWP,
    carrier_resource_blocks: Int,
) raises:
    capabilities.validate()
    bwp.validate()
    if carrier_resource_blocks < 1 or carrier_resource_blocks > 275:
        raise Error("RedCap uplink carrier resource blocks must be in [1,275]")
    if bwp.resource_blocks > carrier_resource_blocks or (
        bwp.start_prb > carrier_resource_blocks - bwp.resource_blocks
    ):
        raise Error("initialUplinkBWP-RedCap exceeds the uplink carrier grid")
    if capabilities.frequency_range == NR_FREQUENCY_RANGE_FR1:
        if (
            bwp.subcarrier_spacing_khz != 15
            and bwp.subcarrier_spacing_khz != 30
            and bwp.subcarrier_spacing_khz != 60
        ):
            raise Error("FR1 RedCap initial uplink BWP has invalid SCS")
    elif capabilities.frequency_range == NR_FREQUENCY_RANGE_FR2:
        if (
            bwp.subcarrier_spacing_khz != 60
            and bwp.subcarrier_spacing_khz != 120
        ):
            raise Error("FR2 RedCap initial uplink BWP has invalid SCS")
    else:
        raise Error("invalid RedCap frequency range")
    var occupied_khz = Int128(bwp.resource_blocks) * 12 * Int128(
        bwp.subcarrier_spacing_khz
    )
    var supported_khz = Float64(1000) * capabilities.channel_bandwidth_mhz
    if Float64(occupied_khz) > supported_khz:
        raise Error("initialUplinkBWP-RedCap exceeds UE channel bandwidth")


def _valid_frequency_occasion_count(count: Int) -> Bool:
    return count == 1 or count == 2 or count == 4 or count == 8


def nr_redcap_rel17_prach_resource_allocation(
    capabilities: NRRedCapRel17Capabilities,
    sequence_length: Int,
    prach_subcarrier_spacing_hz: Int,
    pusch_subcarrier_spacing_khz: Int,
) raises -> NRRedCapPRACHResourceAllocation:
    """Return the exact RedCap-applicable Table 6.3.3.2-1 row.

    FR1 supports the Rel-17 long-preamble 1.25/5-kHz rows and short-preamble
    15/30/60-kHz rows over 15/30/60-kHz PUSCH spacing.  The declared FR2
    RedCap profile supports the 139-sample 60/120-kHz rows over 60/120-kHz
    PUSCH spacing.  FR2-2 480/960-kHz and 571/1151-sample rows belong to a
    different capability profile and are rejected here.
    """
    capabilities.validate()
    var resource_blocks = 0
    var k_bar = 0
    if capabilities.frequency_range == NR_FREQUENCY_RANGE_FR1:
        if sequence_length == 839:
            if prach_subcarrier_spacing_hz == 1250:
                if pusch_subcarrier_spacing_khz == 15:
                    resource_blocks = 6
                    k_bar = 7
                elif pusch_subcarrier_spacing_khz == 30:
                    resource_blocks = 3
                    k_bar = 1
                elif pusch_subcarrier_spacing_khz == 60:
                    resource_blocks = 2
                    k_bar = 133
            elif prach_subcarrier_spacing_hz == 5000:
                if pusch_subcarrier_spacing_khz == 15:
                    resource_blocks = 24
                    k_bar = 12
                elif pusch_subcarrier_spacing_khz == 30:
                    resource_blocks = 12
                    k_bar = 10
                elif pusch_subcarrier_spacing_khz == 60:
                    resource_blocks = 6
                    k_bar = 7
        elif sequence_length == 139:
            if prach_subcarrier_spacing_hz == 15000:
                if pusch_subcarrier_spacing_khz == 15:
                    resource_blocks = 12
                    k_bar = 2
                elif pusch_subcarrier_spacing_khz == 30:
                    resource_blocks = 6
                    k_bar = 2
                elif pusch_subcarrier_spacing_khz == 60:
                    resource_blocks = 3
                    k_bar = 2
            elif prach_subcarrier_spacing_hz == 30000:
                if pusch_subcarrier_spacing_khz == 15:
                    resource_blocks = 24
                    k_bar = 2
                elif pusch_subcarrier_spacing_khz == 30:
                    resource_blocks = 12
                    k_bar = 2
                elif pusch_subcarrier_spacing_khz == 60:
                    resource_blocks = 6
                    k_bar = 2
            elif (
                prach_subcarrier_spacing_hz == 60000
                and pusch_subcarrier_spacing_khz == 60
            ):
                resource_blocks = 12
                k_bar = 2
    elif capabilities.frequency_range == NR_FREQUENCY_RANGE_FR2:
        if sequence_length == 139:
            if prach_subcarrier_spacing_hz == 60000:
                if pusch_subcarrier_spacing_khz == 60:
                    resource_blocks = 12
                    k_bar = 2
                elif pusch_subcarrier_spacing_khz == 120:
                    resource_blocks = 6
                    k_bar = 2
            elif prach_subcarrier_spacing_hz == 120000:
                if pusch_subcarrier_spacing_khz == 60:
                    resource_blocks = 24
                    k_bar = 2
                elif pusch_subcarrier_spacing_khz == 120:
                    resource_blocks = 12
                    k_bar = 2
    if resource_blocks == 0:
        raise Error("unsupported Rel-17 RedCap PRACH/PUSCH SCS table row")
    return NRRedCapPRACHResourceAllocation(
        sequence_length,
        prach_subcarrier_spacing_hz,
        pusch_subcarrier_spacing_khz,
        resource_blocks,
        k_bar,
    )


def nr_redcap_rel17_prach_frequency_placement(
    capabilities: NRRedCapRel17Capabilities,
    initial_uplink_bwp: NRRedCapInitialBWP,
    carrier_resource_blocks: Int,
    frequency_start_rb: Int,
    frequency_occasion_index: Int,
    frequency_occasion_count: Int,
    prach_resource_blocks: Int,
    *,
    two_step_random_access: Bool = False,
) raises -> NRRedCapPRACHFrequencyPlacement:
    """Resolve one Msg1 or MsgA PRACH occasion in the RedCap initial BWP.

    ``prach_resource_blocks`` is the decoded allocation from TS 38.211
    Table 6.3.3.2-1.  The function validates the complete configured FDM set,
    not only the selected occasion, so a successful result proves that all
    frequency occasions are contained by ``initialUplinkBWP-RedCap``.
    """
    _validate_redcap_initial_uplink_bwp(
        capabilities, initial_uplink_bwp, carrier_resource_blocks
    )
    if frequency_start_rb < 0:
        raise Error("RedCap PRACH frequency start must be non-negative")
    if not _valid_frequency_occasion_count(frequency_occasion_count):
        raise Error("RedCap PRACH FDM count must be 1, 2, 4, or 8")
    if (
        frequency_occasion_index < 0
        or frequency_occasion_index >= frequency_occasion_count
    ):
        raise Error("RedCap PRACH frequency occasion index is out of range")
    if prach_resource_blocks < 1:
        raise Error("decoded PRACH resource-block allocation must be positive")
    if two_step_random_access and not capabilities.supports_two_step_rach:
        raise Error("MsgA PRACH placement requires two-step RACH capability")

    var last_offset = Int128(frequency_start_rb) + Int128(
        frequency_occasion_count - 1
    ) * Int128(prach_resource_blocks)
    var configured_end = last_offset + Int128(prach_resource_blocks)
    if configured_end > Int128(initial_uplink_bwp.resource_blocks):
        raise Error("configured PRACH frequency occasions exceed initial BWP")

    var relative_start_128 = Int128(frequency_start_rb) + Int128(
        frequency_occasion_index
    ) * Int128(prach_resource_blocks)
    var start_crb_128 = Int128(initial_uplink_bwp.start_prb) + (
        relative_start_128
    )
    var end_crb_128 = start_crb_128 + Int128(prach_resource_blocks)
    var subcarrier_128 = start_crb_128 * 12
    if (
        relative_start_128 > Int128(Int.MAX)
        or start_crb_128 > Int128(Int.MAX)
        or end_crb_128 > Int128(Int.MAX)
        or subcarrier_128 > Int128(Int.MAX)
    ):
        raise Error("RedCap PRACH placement overflows Int")
    if end_crb_128 > Int128(carrier_resource_blocks):
        raise Error("selected PRACH occasion exceeds the uplink carrier grid")
    return NRRedCapPRACHFrequencyPlacement(
        (
            NR_REDCAP_PRACH_SOURCE_MSGA
            if two_step_random_access
            else NR_REDCAP_PRACH_SOURCE_MSG1
        ),
        frequency_occasion_index,
        frequency_occasion_count,
        prach_resource_blocks,
        Int(relative_start_128),
        Int(start_crb_128),
        Int(end_crb_128),
        Int(subcarrier_128),
    )


def nr_redcap_rel17_prach_placed_composite(
    capabilities: NRRedCapRel17Capabilities,
    initial_uplink_bwp: NRRedCapInitialBWP,
    carrier_resource_blocks: Int,
    frequency_start_rb: Int,
    frequency_occasion_index: Int,
    frequency_occasion_count: Int,
    parameters: NRPRACHFormat,
    starting_logical_root_index: Int,
    n_cs: Int,
    set_type: Int,
    preamble_index: Int,
    *,
    two_step_random_access: Bool = False,
    preamble_count: Int = 64,
    testcase_id: StringSlice = "nr-redcap-rel17-prach-placed-composite",
) raises -> NRRedCapPRACHPlacedCompositeResult:
    """Compose checked RedCap BWP placement with normalized PRACH loopback."""
    var allocation = nr_redcap_rel17_prach_resource_allocation(
        capabilities,
        parameters.sequence_length,
        parameters.subcarrier_spacing_hz,
        initial_uplink_bwp.subcarrier_spacing_khz,
    )
    var placement = nr_redcap_rel17_prach_frequency_placement(
        capabilities,
        initial_uplink_bwp,
        carrier_resource_blocks,
        frequency_start_rb,
        frequency_occasion_index,
        frequency_occasion_count,
        allocation.resource_blocks,
        two_step_random_access=two_step_random_access,
    )
    var normalized = nr_prach_normalized_composite(
        parameters,
        starting_logical_root_index,
        n_cs,
        set_type,
        preamble_index,
        preamble_count=preamble_count,
        testcase_id=testcase_id,
    )
    return NRRedCapPRACHPlacedCompositeResult(placement, normalized^)
