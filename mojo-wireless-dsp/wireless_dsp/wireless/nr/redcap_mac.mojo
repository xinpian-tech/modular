"""Rel-17 RedCap MAC resource, BWP, and CCCH decisions.

This CPU reference implements bounded, deterministic portions of 3GPP
TS 38.321 V17.15.0 clauses 5.1.1b--5.1.1d and 5.15.1, the initial-UL-BWP
choice nested in clause 5.27.1, and Table 6.2.1-2.  Inputs represent RRC
configuration that has already been decoded and validated for UE support.

Resource-set selection preserves the specification's ``set(s)`` result: a
chosen feature combination can select one 4-step set, one 2-step set, or both.
There is no random or scheduler-policy tie breaker.  TS 38.331 V17.15.0 permits
at most one set per feature combination per RA type and requires a priority for
every mapped feature; this module validates both cross-referenced invariants.

The module does not decode ASN.1, schedule PRACH occasions, run Random Access,
maintain MAC buffers/timers, or implement the complete SDT eligibility,
data-volume, carrier, CG-SDT, or time-alignment procedures.  Ordinary NR and
Rel-18 eRedCap tags are deliberately rejected so their rules cannot silently
satisfy Rel-17 RedCap evidence.
"""

from std.math import isfinite


comptime NR_REDCAP_MAC_PROFILE_ORDINARY_NR = 0
comptime NR_REDCAP_MAC_PROFILE_REDCAP_REL17 = 1
comptime NR_REDCAP_MAC_PROFILE_EREDCAP_REL18 = 2

comptime NR_REDCAP_RA_FEATURE_REDCAP = 1
comptime NR_REDCAP_RA_FEATURE_SLICING = 2
comptime NR_REDCAP_RA_FEATURE_SMALL_DATA = 4
comptime NR_REDCAP_RA_FEATURE_MSG3_REPETITION = 8
comptime NR_REDCAP_RA_FEATURE_MASK = 15

comptime NR_REDCAP_RA_TYPE_4_STEP = 0
comptime NR_REDCAP_RA_TYPE_2_STEP = 1

comptime NR_REDCAP_MAC_BWP_ORDINARY_INITIAL = 0
comptime NR_REDCAP_MAC_BWP_REDCAP_INITIAL = 1
comptime NR_REDCAP_MAC_BWP_DEFAULT = 2


def _validate_rel17_profile(profile: Int) raises:
    if profile != NR_REDCAP_MAC_PROFILE_REDCAP_REL17:
        raise Error("TS 38.321 RedCap MAC API requires a Rel-17 RedCap profile")


def _validate_feature_mask(mask: Int) raises:
    if mask < 0 or (mask & ~NR_REDCAP_RA_FEATURE_MASK) != 0:
        raise Error("RedCap RA feature mask contains an unsupported feature")


def _validate_ra_type(ra_type: Int) raises:
    if (
        ra_type != NR_REDCAP_RA_TYPE_4_STEP
        and ra_type != NR_REDCAP_RA_TYPE_2_STEP
    ):
        raise Error("RedCap RA type must be 4-step or 2-step")


def _is_single_feature(value: Int) -> Bool:
    return value > 0 and (value & (value - 1)) == 0


struct NRRedCapRAResourceSetGroup(ImplicitlyCopyable):
    """One clause-5.1.1b feature-combination group.

    ``four_step_index`` and ``two_step_index`` are original input indexes, or
    ``-1`` when the chosen feature combination has no available set for that
    RA type.  Public fields are mutable, so consumers should call
    :meth:`validate` after mutation and before use.
    """

    var configured_features: Int
    var four_step_index: Int
    var two_step_index: Int

    def __init__(
        out self,
        configured_features: Int,
        four_step_index: Int,
        two_step_index: Int,
    ) raises:
        self.configured_features = configured_features
        self.four_step_index = four_step_index
        self.two_step_index = two_step_index
        self.validate()

    def validate(self) raises:
        """Revalidate this possibly mutated grouped selection."""
        _validate_feature_mask(self.configured_features)
        if self.four_step_index < -1 or self.two_step_index < -1:
            raise Error("RedCap RA grouped indexes must be -1 or non-negative")
        if self.four_step_index == -1 and self.two_step_index == -1:
            raise Error("RedCap RA grouped selection must contain a set")

    def selected_set_count(self) raises -> Int:
        """Return one or two after revalidating the grouped selection."""
        self.validate()
        return (
            (1 if self.four_step_index >= 0 else 0)
            + (1 if self.two_step_index >= 0 else 0)
        )

    def index_for_ra_type(self, ra_type: Int) raises -> Int:
        """Return the selected input index for ``ra_type``, or ``-1``."""
        self.validate()
        _validate_ra_type(ra_type)
        if ra_type == NR_REDCAP_RA_TYPE_4_STEP:
            return self.four_step_index
        return self.two_step_index


def nr_redcap_rel17_msg3_repetition_applicable(
    repetition_sets_configured: Bool,
    non_repetition_sets_configured: Bool,
    downlink_pathloss_reference_rsrp: Float64,
    rsrp_threshold_msg3: Float64,
    *,
    profile: Int = NR_REDCAP_MAC_PROFILE_REDCAP_REL17,
) raises -> Bool:
    """Return Msg3-repetition applicability from clause 5.1.1b.

    When both kinds of set are configured, the comparison is the normative
    strict ``RSRP < rsrp-ThresholdMsg3`` comparison and both numbers must be
    finite.  The numeric inputs are ignored when only one kind is configured,
    because TS 38.331 requires the threshold to be absent in that case.
    """
    _validate_rel17_profile(profile)
    if not repetition_sets_configured and not non_repetition_sets_configured:
        raise Error("a RedCap RA BWP must configure at least one resource set")
    if repetition_sets_configured and non_repetition_sets_configured:
        if (
            not isfinite(downlink_pathloss_reference_rsrp)
            or not isfinite(rsrp_threshold_msg3)
        ):
            raise Error("Msg3-repetition RSRP inputs must be finite")
        return downlink_pathloss_reference_rsrp < rsrp_threshold_msg3
    return repetition_sets_configured


def nr_redcap_rel17_ra_resource_set_available(
    configured_features: Int,
    applicable_features: Int,
    *,
    nsag_list_configured: Bool = False,
    nsag_matches: Bool = False,
    profile: Int = NR_REDCAP_MAC_PROFILE_REDCAP_REL17,
) raises -> Bool:
    """Return clause-5.1.1c availability for one decoded RA resource set.

    ``configured_features`` and ``applicable_features`` are masks composed
    from the four ``NR_REDCAP_RA_FEATURE_*`` constants.  Slicing availability
    additionally consumes the caller's already decoded NSAG-list membership.
    A set without ``FeatureCombination`` is represented by mask zero.
    """
    _validate_rel17_profile(profile)
    _validate_feature_mask(configured_features)
    _validate_feature_mask(applicable_features)
    var slicing_indicated = (
        configured_features & NR_REDCAP_RA_FEATURE_SLICING
    ) != 0
    if nsag_list_configured != slicing_indicated:
        raise Error("the slicing feature indication is exactly an NSAG list")
    if nsag_matches and not nsag_list_configured:
        raise Error("an NSAG match requires a configured NSAG list")
    if nsag_matches and (
        applicable_features & NR_REDCAP_RA_FEATURE_SLICING
    ) == 0:
        raise Error("an NSAG match requires slicing to be applicable")
    if (configured_features & ~applicable_features) != 0:
        return False
    if nsag_list_configured and not nsag_matches:
        return False
    return True


def _resource_set_group_for_mask(
    configured_features: Span[Int, ...],
    ra_types: Span[Int, ...],
    available: Span[UInt8, ...],
    selected_features: Int,
) raises -> NRRedCapRAResourceSetGroup:
    var four_step_index = -1
    var two_step_index = -1
    for index in range(len(configured_features)):
        if (
            available[index] == 0
            or configured_features[index] != selected_features
        ):
            continue
        if ra_types[index] == NR_REDCAP_RA_TYPE_4_STEP:
            four_step_index = index
        else:
            two_step_index = index
    return NRRedCapRAResourceSetGroup(
        selected_features, four_step_index, two_step_index
    )


def nr_redcap_rel17_select_ra_resource_set_group(
    configured_features: Span[Int, ...],
    ra_types: Span[Int, ...],
    available: Span[UInt8, ...],
    applicable_features: Int,
    feature_priority: Span[Int, ...],
    *,
    contention_free_resources_provided: Bool = False,
    si_request_resources_provided: Bool = False,
    profile: Int = NR_REDCAP_MAC_PROFILE_REDCAP_REL17,
) raises -> NRRedCapRAResourceSetGroup:
    """Select clause-5.1.1b resource set(s) as one grouped combination.

    ``available`` must contain clause-5.1.1c decisions.  ``ra_types`` labels
    every set as 4-step or 2-step; a given ``(ra_type, feature combination)``
    may occur at most once.  Each priority entry is one feature bit, ordered
    highest to lowest, and the order must cover every feature mapped by the
    supplied configuration.  The result preserves both RA-type members of the
    selected feature combination and never applies an invented tie policy.

    The two resource flags mean resources have been provided *for this Random
    Access procedure*.  Merely being an SI-request procedure is insufficient
    to set ``si_request_resources_provided``.
    """
    _validate_rel17_profile(profile)
    _validate_feature_mask(applicable_features)
    if len(configured_features) == 0 or len(configured_features) > 32:
        raise Error("RedCap RA selection requires one to 32 resource sets")
    if (
        len(configured_features) != len(ra_types)
        or len(configured_features) != len(available)
    ):
        raise Error("RedCap RA selection vectors must align")

    var mapped_features = 0
    for index in range(len(configured_features)):
        var mask = configured_features[index]
        _validate_feature_mask(mask)
        _validate_ra_type(ra_types[index])
        if (
            ra_types[index] == NR_REDCAP_RA_TYPE_2_STEP
            and (mask & NR_REDCAP_RA_FEATURE_MSG3_REPETITION) != 0
        ):
            raise Error("Msg3 repetition cannot label a 2-step RA resource set")
        if available[index] != 0 and available[index] != 1:
            raise Error("RedCap RA availability entries must be zero or one")
        mapped_features |= mask
        if available[index] == 1 and (mask & ~applicable_features) != 0:
            raise Error("available RA set advertises a non-applicable feature")

    for right in range(len(configured_features)):
        for left in range(right):
            if (
                ra_types[left] == ra_types[right]
                and configured_features[left] == configured_features[right]
            ):
                raise Error(
                    "a feature combination may occur once per RedCap RA type"
                )

    var seen_priority = 0
    for priority_index in range(len(feature_priority)):
        var feature = feature_priority[priority_index]
        if not _is_single_feature(feature) or (
            feature & ~NR_REDCAP_RA_FEATURE_MASK
        ) != 0:
            raise Error("each RedCap RA priority must be one supported feature")
        if (seen_priority & feature) != 0:
            raise Error("RedCap RA feature priorities must be unique")
        seen_priority |= feature
    if (mapped_features & ~seen_priority) != 0:
        raise Error("RedCap RA priorities must cover every mapped feature")

    var combinations = List[UInt8](length=16, fill=0)
    for index in range(len(configured_features)):
        if available[index] == 1:
            combinations[configured_features[index]] = 1

    # This follows the exact clause-5.1.1b if/else-if order.  In particular,
    # SI-request procedure identity alone does not select unassociated sets.
    if (
        not contention_free_resources_provided
        and not si_request_resources_provided
        and applicable_features != 0
    ):
        if combinations[applicable_features] == 1:
            return _resource_set_group_for_mask(
                configured_features,
                ra_types,
                available,
                applicable_features,
            )

        var candidates = List[UInt8](length=16, fill=0)
        var candidate_count = 0
        for mask in range(1, 16):
            if combinations[mask] == 1:
                candidates[mask] = 1
                candidate_count += 1
        if candidate_count == 0:
            return _resource_set_group_for_mask(
                configured_features, ra_types, available, 0
            )

        for priority_index in range(len(feature_priority)):
            var feature = feature_priority[priority_index]
            if (applicable_features & feature) == 0:
                continue
            var matching_count = 0
            var matching_mask = 0
            for mask in range(1, 16):
                if candidates[mask] == 1 and (mask & feature) != 0:
                    matching_count += 1
                    matching_mask = mask
            if matching_count == 1:
                return _resource_set_group_for_mask(
                    configured_features, ra_types, available, matching_mask
                )
            if matching_count > 1:
                for mask in range(1, 16):
                    if candidates[mask] == 1 and (mask & feature) == 0:
                        candidates[mask] = 0

        var remaining_count = 0
        var remaining_mask = 0
        for mask in range(1, 16):
            if candidates[mask] == 1:
                remaining_count += 1
                remaining_mask = mask
        if remaining_count != 1:
            raise Error("RedCap RA priorities did not select one combination")
        return _resource_set_group_for_mask(
            configured_features, ra_types, available, remaining_mask
        )

    if (
        contention_free_resources_provided
        and (applicable_features & NR_REDCAP_RA_FEATURE_REDCAP) != 0
        and combinations[NR_REDCAP_RA_FEATURE_REDCAP] == 1
    ):
        return _resource_set_group_for_mask(
            configured_features,
            ra_types,
            available,
            NR_REDCAP_RA_FEATURE_REDCAP,
        )
    return _resource_set_group_for_mask(
        configured_features, ra_types, available, 0
    )


def nr_redcap_rel17_select_ra_resource_set(
    configured_features: Span[Int, ...],
    available: Span[UInt8, ...],
    applicable_features: Int,
    feature_priority: Span[Int, ...],
    *,
    contention_free_resources_provided: Bool = False,
    si_request_resources_provided: Bool = False,
    profile: Int = NR_REDCAP_MAC_PROFILE_REDCAP_REL17,
) raises -> Int:
    """Select one set for a BWP configured with exactly one RA type.

    This compatibility entry point is normatively bounded to a configuration
    containing only one already-decoded RA type.  Duplicate feature masks are
    rejected.  Use :func:`nr_redcap_rel17_select_ra_resource_set_group` when
    both 4-step and 2-step resource sets are present.
    """
    var ra_types = List[Int](
        length=len(configured_features), fill=NR_REDCAP_RA_TYPE_4_STEP
    )
    var group = nr_redcap_rel17_select_ra_resource_set_group(
        configured_features,
        Span(ra_types),
        available,
        applicable_features,
        feature_priority,
        contention_free_resources_provided=contention_free_resources_provided,
        si_request_resources_provided=si_request_resources_provided,
        profile=profile,
    )
    return group.four_step_index


def nr_redcap_rel17_random_access_uplink_bwp_source(
    initial_uplink_bwp_redcap_configured: Bool,
    *,
    profile: Int = NR_REDCAP_MAC_PROFILE_REDCAP_REL17,
) raises -> Int:
    """Return the RedCap initial UL-BWP source for a bounded RA context.

    This is the source choice for a RedCap UE in RRC_IDLE/RRC_INACTIVE under
    clause 5.15.1, and for the RA-SDT resource check nested in clause 5.27.1.
    It is not the general connected-mode BWP switch: that branch additionally
    depends on whether the active UL BWP has PRACH occasions.
    """
    _validate_rel17_profile(profile)
    if initial_uplink_bwp_redcap_configured:
        return NR_REDCAP_MAC_BWP_REDCAP_INITIAL
    return NR_REDCAP_MAC_BWP_ORDINARY_INITIAL


def nr_redcap_rel17_random_access_downlink_bwp_source(
    initial_downlink_bwp_redcap_configured: Bool,
    *,
    si_request: Bool = False,
    explicit_si_request_resources: Bool = False,
    selected_sul_carrier: Bool = False,
    profile: Int = NR_REDCAP_MAC_PROFILE_REDCAP_REL17,
) raises -> Int:
    """Return clause-5.15.1 initial DL-BWP monitoring for IDLE/INACTIVE RA.

    The ordinary initial DL BWP is used only when RedCap initial DL is absent,
    or when all three SI-request/SI-resource/SUL exception conditions hold.
    Selection of SUL is valid for non-SI procedures and is not itself an error.
    """
    _validate_rel17_profile(profile)
    if explicit_si_request_resources and not si_request:
        raise Error("explicit SI resources require an SI-request procedure")
    if not initial_downlink_bwp_redcap_configured:
        return NR_REDCAP_MAC_BWP_ORDINARY_INITIAL
    if si_request and explicit_si_request_resources and selected_sul_carrier:
        return NR_REDCAP_MAC_BWP_ORDINARY_INITIAL
    return NR_REDCAP_MAC_BWP_REDCAP_INITIAL


def nr_redcap_rel17_bwp_inactivity_target(
    default_downlink_bwp_configured: Bool,
    initial_downlink_bwp_redcap_configured: Bool,
    *,
    profile: Int = NR_REDCAP_MAC_PROFILE_REDCAP_REL17,
) raises -> Int:
    """Return the clause-5.15.1 target after BWP-inactivity expiry."""
    _validate_rel17_profile(profile)
    if default_downlink_bwp_configured:
        return NR_REDCAP_MAC_BWP_DEFAULT
    if initial_downlink_bwp_redcap_configured:
        return NR_REDCAP_MAC_BWP_REDCAP_INITIAL
    return NR_REDCAP_MAC_BWP_ORDINARY_INITIAL


def nr_redcap_rel17_ul_ccch_lcid(
    payload_bits: Int,
    *,
    profile: Int = NR_REDCAP_MAC_PROFILE_REDCAP_REL17,
) raises -> Int:
    """Return the RedCap UL-CCCH LCID from TS 38.321 Table 6.2.1-2."""
    _validate_rel17_profile(profile)
    if payload_bits == 48:
        return 35
    if payload_bits == 64:
        return 36
    raise Error("Rel-17 RedCap UL CCCH must contain exactly 48 or 64 bits")
