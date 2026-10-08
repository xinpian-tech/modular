"""Bounded, stateless NR physical-layer control procedures.

The functions here implement arithmetic kernels from 3GPP TS 38.213 rather
than the surrounding UE/MAC state machines.  In particular, search-space
hashing and candidate placement follow clause 10.1, timing-advance arithmetic
follows clause 4.2, the PUSCH power expression follows clause 7.1, and the
bounded PUCCH selectors follow clauses 9.2.1/9.2.3. RA-RNTI construction
follows 3GPP TS 38.321 clause 5.1.3; TS 38.213 random-access procedures refer
to that identifier rather than defining its arithmetic.
"""

from std.math import isfinite, log


comptime _SEARCH_SPACE_MODULUS = UInt64(65537)


def _is_aggregation_level(value: Int) -> Bool:
    return value == 1 or value == 2 or value == 4 or value == 8 or value == 16


def nr_coreset_cce_count(resource_blocks: Int, duration_symbols: Int) raises -> Int:
    """Return the number of six-REG CCEs in a contiguous CORESET profile.

    A standards-conformant CORESET frequency-domain bitmap selects groups of
    six resource blocks.  This bounded API therefore accepts 6--270 RBs in
    multiples of six and a duration of one, two, or three OFDM symbols.
    """
    if (
        resource_blocks < 6
        or resource_blocks > 270
        or resource_blocks % 6 != 0
        or duration_symbols < 1
        or duration_symbols > 3
    ):
        raise Error("invalid contiguous NR CORESET dimensions")
    return resource_blocks * duration_symbols // 6


def _modular_power(base: UInt64, exponent: Int) raises -> UInt64:
    if exponent < 0:
        raise Error("modular exponent must be non-negative")
    var result = UInt64(1)
    var factor = base % _SEARCH_SPACE_MODULUS
    var remaining = exponent
    while remaining != 0:
        if remaining & 1:
            result = (result * factor) % _SEARCH_SPACE_MODULUS
        factor = (factor * factor) % _SEARCH_SPACE_MODULUS
        remaining >>= 1
    return result


def nr_uss_search_space_y(
    rnti: Int, slot_index: Int, *, coreset_index: Int = 0,
) raises -> Int:
    """Return ``Y_p`` for a UE-specific search space (38.213 clause 10.1).

    ``slot_index`` is the zero-based slot recurrence index.  The multiplier is
    39827, 39829, or 39839 according to ``coreset_index mod 3`` and remains
    fixed throughout the slot recurrence for that CORESET.  Modular
    exponentiation keeps runtime logarithmic for a very large valid index.
    """
    if (
        rnti < 1
        or rnti > 65535
        or slot_index < 0
        or coreset_index < 0
        or coreset_index > 11
    ):
        raise Error("invalid UE-specific search-space fields")
    var multipliers: List[UInt64] = [39827, 39829, 39839]
    var multiplier = multipliers[coreset_index % 3]
    # Compute A_p^(slot+1) without forming slot_index+1 at Int.MAX.
    var y = (
        UInt64(rnti)
        * _modular_power(multiplier, slot_index)
    ) % _SEARCH_SPACE_MODULUS
    y = (y * multiplier) % _SEARCH_SPACE_MODULUS
    return Int(y)


def nr_search_space_candidate_first_cces(
    cce_count: Int,
    aggregation_level: Int,
    candidate_count: Int,
    y: Int,
    *,
    carrier_indicator: Int = 0,
    maximum_candidate_count: Int = -1,
) raises -> List[Int]:
    """Return first-CCE indexes from the clause 10.1 candidate equation.

    Use ``y=0`` for a common search space and
    :func:`nr_uss_search_space_y` for a UE-specific search space.  This profile
    supports the standardized aggregation levels and the at-most-eight
    candidates representable by the search-space configuration tables.  Set
    ``maximum_candidate_count`` when cross-carrier configurations have
    different candidate counts; its default is ``candidate_count``.
    """
    var maximum_candidates = (
        candidate_count
        if maximum_candidate_count == -1
        else maximum_candidate_count
    )
    if (
        cce_count < aggregation_level
        or cce_count > 135
        or not _is_aggregation_level(aggregation_level)
        or candidate_count < 1
        or candidate_count > 8
        or candidate_count > cce_count // aggregation_level
        or maximum_candidates < candidate_count
        or maximum_candidates > 8
        or y < 0
        or y >= Int(_SEARCH_SPACE_MODULUS)
        or carrier_indicator < 0
        or carrier_indicator > 7
    ):
        raise Error("invalid NR search-space candidate configuration")
    var groups = cce_count // aggregation_level
    var result = List[Int](capacity=candidate_count)
    for candidate in range(candidate_count):
        # The operands are bounded above, but the division is written this
        # way to preserve the exact floor in the specification equation.
        var offset = (
            candidate * cce_count
        ) // (aggregation_level * maximum_candidates)
        var group = (y + offset + carrier_indicator) % groups
        result.append(aggregation_level * group)
    return result^


def nr_search_space_candidate_cces(
    cce_count: Int,
    aggregation_level: Int,
    candidate_count: Int,
    y: Int,
    *,
    carrier_indicator: Int = 0,
    maximum_candidate_count: Int = -1,
) raises -> List[Int]:
    """Return every CCE index, grouped candidate-major then CCE-major."""
    var first = nr_search_space_candidate_first_cces(
        cce_count,
        aggregation_level,
        candidate_count,
        y,
        carrier_indicator=carrier_indicator,
        maximum_candidate_count=maximum_candidate_count,
    )
    var result = List[Int](capacity=candidate_count * aggregation_level)
    for base in first:
        for local_cce in range(aggregation_level):
            result.append(base + local_cce)
    return result^


def nr_ra_rnti(
    first_symbol: Int,
    slot_in_frame: Int,
    frequency_index: Int,
    ul_carrier_id: Int,
) raises -> Int:
    """Construct the TS 38.321 clause-5.1.3 RA-RNTI."""
    if (
        first_symbol < 0
        or first_symbol > 13
        or slot_in_frame < 0
        or slot_in_frame > 79
        or frequency_index < 0
        or frequency_index > 7
        or ul_carrier_id < 0
        or ul_carrier_id > 1
    ):
        raise Error("invalid PRACH coordinates for RA-RNTI")
    return (
        1
        + first_symbol
        + 14 * slot_in_frame
        + 14 * 80 * frequency_index
        + 14 * 80 * 8 * ul_carrier_id
    )


def _timing_advance_scale(mu: Int) raises -> Int:
    if mu < 0 or mu > 6:
        raise Error("timing-advance numerology must be in [0,6]")
    return 1024 // (1 << mu)


def nr_timing_advance_absolute_tc(command: Int, mu: Int) raises -> Int:
    """Return absolute ``N_TA`` in T_c units for a 12-bit TA command."""
    if command < 0 or command > 3846:
        raise Error("absolute timing-advance command must be in [0,3846]")
    return command * _timing_advance_scale(mu)


def nr_timing_advance_delta_tc(command: Int, mu: Int) raises -> Int:
    """Return the signed relative TA change in T_c units for a 6-bit command."""
    if command < 0 or command > 63:
        raise Error("relative timing-advance command must be in [0,63]")
    return (command - 31) * _timing_advance_scale(mu)


def nr_timing_advance_update_tc(current_tc: Int, command: Int, mu: Int) raises -> Int:
    """Apply one relative TA command with explicit signed-Int overflow checks."""
    var delta = nr_timing_advance_delta_tc(command, mu)
    if delta > 0 and current_tc > Int.MAX - delta:
        raise Error("timing-advance update overflows Int")
    if delta < 0 and current_tc < Int.MIN - delta:
        raise Error("timing-advance update underflows Int")
    return current_tc + delta


def nr_pusch_power_dbm(
    resource_blocks: Int,
    mu: Int,
    p0_dbm: Float64,
    alpha: Float64,
    pathloss_db: Float64,
    delta_tf_db: Float64,
    closed_loop_db: Float64,
    p_cmax_dbm: Float64,
) raises -> Float64:
    """Evaluate and clamp the bounded single-serving-cell PUSCH power core.

    The return value is ``min(P_CMAX, 10*log10(2^mu*M_RB) + P0 +
    alpha*PL + Delta_TF + f)``.  Multi-cell accumulation, power sharing,
    ramping, and closed-loop state evolution are intentionally outside this
    stateless arithmetic kernel.
    """
    if resource_blocks < 1 or resource_blocks > 275 or mu < 0 or mu > 6:
        raise Error("invalid PUSCH bandwidth or numerology")
    if (
        not isfinite(p0_dbm)
        or not isfinite(alpha)
        or not isfinite(pathloss_db)
        or not isfinite(delta_tf_db)
        or not isfinite(closed_loop_db)
        or not isfinite(p_cmax_dbm)
        or alpha < 0.0
        or alpha > 1.0
        or pathloss_db < 0.0
    ):
        raise Error("PUSCH power-control inputs must be finite and physical")
    var bandwidth = Float64((1 << mu) * resource_blocks)
    var requested = 10.0 * log(bandwidth) / log(10.0) + p0_dbm
    requested += alpha * pathloss_db
    requested += delta_tf_db
    requested += closed_loop_db
    if not isfinite(requested):
        raise Error("PUSCH power-control sum is not representable")
    return min(p_cmax_dbm, requested)


def nr_pucch_resource_set_index(
    uci_bits: Int,
    *,
    set1_max_payload: Int = 1706,
    set2_max_payload: Int = 1706,
) raises -> Int:
    """Select PUCCH resource-set id 0--3 from clause 9.2.1 thresholds."""
    if (
        uci_bits < 1
        or uci_bits > 1706
        or set1_max_payload < 3
        or set1_max_payload > 1706
        or set2_max_payload < set1_max_payload
        or set2_max_payload > 1706
    ):
        raise Error("invalid PUCCH payload or resource-set thresholds")
    if uci_bits <= 2:
        return 0
    if uci_bits <= set1_max_payload:
        return 1
    if uci_bits <= set2_max_payload:
        return 2
    return 3


def nr_pucch_resource_index(indicator: Int, resource_count: Int) raises -> Int:
    """Map a 1--3 bit PRI value to a bounded resource list of at most 8."""
    if resource_count < 1 or resource_count > 8:
        raise Error("bounded PUCCH resource list must contain 1--8 entries")
    if indicator < 0 or indicator > 7 or indicator >= resource_count:
        raise Error("PUCCH resource indicator does not select a configured entry")
    return indicator


def nr_pucch_resource_is_within_bwp(
    carrier_resource_blocks: Int,
    bwp_start_prb: Int,
    bwp_resource_blocks: Int,
    first_prb: Int,
    resource_blocks: Int,
    *,
    second_hop_prb: Int = -1,
) raises -> Bool:
    """Validate absolute PUCCH PRB allocation(s) against the active UL BWP.

    ``second_hop_prb=-1`` disables the second-hop check.  Invalid carrier/BWP
    dimensions raise; a well-formed resource outside the active BWP returns
    ``False`` so callers can use the function as a pure configuration filter.
    """
    if (
        carrier_resource_blocks < 1
        or carrier_resource_blocks > 275
        or bwp_start_prb < 0
        or bwp_resource_blocks < 1
        or bwp_resource_blocks > carrier_resource_blocks
        or bwp_start_prb > carrier_resource_blocks - bwp_resource_blocks
        or first_prb < 0
        or resource_blocks < 1
        or resource_blocks > carrier_resource_blocks
        or second_hop_prb < -1
    ):
        raise Error("invalid carrier, BWP, or PUCCH resource dimensions")
    var bwp_end = bwp_start_prb + bwp_resource_blocks
    var first_inside = (
        first_prb >= bwp_start_prb
        and first_prb <= bwp_end - resource_blocks
    )
    if not first_inside or second_hop_prb == -1:
        return first_inside
    return (
        second_hop_prb >= bwp_start_prb
        and second_hop_prb <= bwp_end - resource_blocks
    )
