"""NR PUCCH OCC, DM-RS, and non-interlaced resource mapping.

The normative source is 3GPP TS 38.211 V18.9.0 (3GPP TS 38.211
Release 18), clauses 6.3.2.4.1 and 6.4.1.3.

Format-3/4 DM-RS sequence generation from clause 6.4.1.3.3.1 is
configuration-dependent and is intentionally outside this module.  The
format-3/4 mapper therefore requires caller-generated, standard-conformant
DM-RS symbols; it only implements the positions and physical-resource order.
"""

from std.collections import Span
from std.math import cos, isfinite, sin, sqrt
from wireless_dsp.core import Complex64
from .grid import NRResourceGrid
from .sequences import nr_gold_bits

comptime _TWO_PI = 6.283185307179586476925286766559
comptime _SUBCARRIERS_PER_RB = 12


def _checked_pucch_product(lhs: Int, rhs: Int) raises -> Int:
    if lhs < 0 or rhs < 0 or (rhs != 0 and lhs > Int.MAX // rhs):
        raise Error("PUCCH dimensions overflow Int")
    return lhs * rhs


def _validate_finite_pucch_values(
    values: Span[Complex64, ...]
) raises:
    for index in range(len(values)):
        if not isfinite(values[index].re) or not isfinite(values[index].im):
            raise Error("PUCCH resource values must be finite")


def _validate_format1_table_key(
    pucch_symbols: Int, intra_slot_hopping: Bool, hop: Int,
) raises:
    if pucch_symbols < 4 or pucch_symbols > 14:
        raise Error("PUCCH format-1 length must be in [4,14]")
    if intra_slot_hopping:
        if hop < 0 or hop > 1:
            raise Error("PUCCH format-1 hop must be zero or one")
    elif hop != 0:
        raise Error("PUCCH format-1 hop must be zero when hopping is disabled")


def nr_pucch_format1_data_occ_length(
    pucch_symbols: Int, *, intra_slot_hopping: Bool = False, hop: Int = 0,
) raises -> Int:
    """Return ``N_SF,m'`` from TS 38.211 Table 6.3.2.4.1-1."""
    _validate_format1_table_key(pucch_symbols, intra_slot_hopping, hop)
    var offset = pucch_symbols - 4
    var no_hopping: List[Int] = [2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7]
    var first_hop: List[Int] = [1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3]
    var second_hop: List[Int] = [1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4]
    if not intra_slot_hopping:
        return no_hopping[offset]
    return first_hop[offset] if hop == 0 else second_hop[offset]


def nr_pucch_format1_dmrs_occ_length(
    pucch_symbols: Int, *, intra_slot_hopping: Bool = False, hop: Int = 0,
) raises -> Int:
    """Return ``N_SF,m'`` from TS 38.211 Table 6.4.1.3.1.1-1."""
    _validate_format1_table_key(pucch_symbols, intra_slot_hopping, hop)
    var offset = pucch_symbols - 4
    var no_hopping: List[Int] = [2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7]
    var first_hop: List[Int] = [1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4]
    var second_hop: List[Int] = [1, 2, 1, 2, 2, 3, 2, 3, 3, 4, 3]
    if not intra_slot_hopping:
        return no_hopping[offset]
    return first_hop[offset] if hop == 0 else second_hop[offset]


def nr_pucch_format1_occ_phases(
    spreading_factor: Int, orthogonal_index: Int,
) raises -> List[Int]:
    """Return integer phases ``phi_i(m)`` from Table 6.3.2.4.1-2."""
    if spreading_factor < 1 or spreading_factor > 7:
        raise Error("PUCCH format-1 OCC length must be in [1,7]")
    if orthogonal_index < 0 or orthogonal_index >= spreading_factor:
        raise Error("PUCCH format-1 orthogonal index is out of range")

    var result = List[Int](capacity=spreading_factor)
    if spreading_factor == 4:
        # The length-four row is the Walsh phase table, rather than the DFT
        # rows used by all the other supported lengths.
        var phases: List[Int] = [
            0, 0, 0, 0,
            0, 2, 0, 2,
            0, 0, 2, 2,
            0, 2, 2, 0,
        ]
        for m in range(4):
            result.append(phases[4 * orthogonal_index + m])
    else:
        for m in range(spreading_factor):
            result.append((orthogonal_index * m) % spreading_factor)
    return result^


def nr_pucch_format1_occ(
    spreading_factor: Int, orthogonal_index: Int,
) raises -> List[Complex64]:
    """Return ``w_i(m)=exp(j*2*pi*phi_i(m)/N_SF)`` for format 1."""
    var phases = nr_pucch_format1_occ_phases(
        spreading_factor, orthogonal_index
    )
    var result = List[Complex64](capacity=spreading_factor)
    for m in range(spreading_factor):
        var angle = (
            _TWO_PI * Float64(phases[m]) / Float64(spreading_factor)
        )
        result.append(Complex64(cos(angle), sin(angle)))
    return result^


def nr_pucch_format1_data_occ(
    pucch_symbols: Int,
    orthogonal_index: Int,
    *,
    intra_slot_hopping: Bool = False,
    hop: Int = 0,
) raises -> List[Complex64]:
    """Return the format-1 data OCC selected by Tables 6.3.2.4.1-1/2."""
    var length = nr_pucch_format1_data_occ_length(
        pucch_symbols, intra_slot_hopping=intra_slot_hopping, hop=hop
    )
    return nr_pucch_format1_occ(length, orthogonal_index)


def nr_pucch_format1_dmrs_occ(
    pucch_symbols: Int,
    orthogonal_index: Int,
    *,
    intra_slot_hopping: Bool = False,
    hop: Int = 0,
) raises -> List[Complex64]:
    """Return the format-1 DM-RS OCC selected by Tables 6.4.1.3.1.1-1 and 6.3.2.4.1-2."""
    var length = nr_pucch_format1_dmrs_occ_length(
        pucch_symbols, intra_slot_hopping=intra_slot_hopping, hop=hop
    )
    return nr_pucch_format1_occ(length, orthogonal_index)


def nr_pucch_format1_apply_occ(
    sequence: Span[Complex64, ...],
    occ: Span[Complex64, ...],
) raises -> List[Complex64]:
    """Block-wise spread one low-PAPR block with a format-1 OCC.

    The returned order is ``m'`` first and then the input sequence index, as
    in clause 6.3.2.4.1 and clause 6.4.1.3.1.1.
    """
    if len(sequence) == 0 or len(occ) < 1 or len(occ) > 7:
        raise Error("invalid PUCCH format-1 sequence or OCC")
    _validate_finite_pucch_values(sequence)
    _validate_finite_pucch_values(occ)
    var output_length = _checked_pucch_product(len(sequence), len(occ))
    var result = List[Complex64](capacity=output_length)
    for m_prime in range(len(occ)):
        var coefficient = Complex64(occ[m_prime].re, occ[m_prime].im)
        for m in range(len(sequence)):
            var value = coefficient * Complex64(
                sequence[m].re, sequence[m].im
            )
            if not isfinite(value.re) or not isfinite(value.im):
                raise Error("PUCCH OCC result must remain finite")
            result.append(value)
    return result^


def _validate_format2_dmrs_fields(
    slot_in_frame: Int,
    symbol_in_slot: Int,
    n_id_0: Int,
    symbols_per_slot: Int,
) raises:
    if slot_in_frame < 0:
        raise Error("PUCCH format-2 slot must be non-negative")
    if symbols_per_slot != 12 and symbols_per_slot != 14:
        raise Error("PUCCH format-2 slot must have 12 or 14 symbols")
    if symbol_in_slot < 0 or symbol_in_slot >= symbols_per_slot:
        raise Error("PUCCH format-2 symbol is outside the slot")
    if n_id_0 < 0 or n_id_0 > 65535:
        raise Error("PUCCH format-2 DM-RS identity must be in [0,65535]")


def nr_pucch_format2_dmrs_c_init(
    slot_in_frame: Int,
    symbol_in_slot: Int,
    n_id_0: Int,
    *,
    symbols_per_slot: Int = 14,
) raises -> UInt32:
    """Return format-2 DM-RS ``c_init`` from clause 6.4.1.3.2.1."""
    _validate_format2_dmrs_fields(
        slot_in_frame, symbol_in_slot, n_id_0, symbols_per_slot
    )
    var modulus = UInt64(1) << 31
    var time_term = (
        UInt64(symbols_per_slot) * (UInt64(slot_in_frame) % modulus)
        + UInt64(symbol_in_slot + 1)
    ) % modulus
    var value = (
        (((UInt64(1) << 17) * time_term) % modulus)
        * UInt64(2 * n_id_0 + 1)
        + UInt64(2 * n_id_0)
    ) % modulus
    return UInt32(value)


def _format2_occ_sign(
    spreading_factor: Int, orthogonal_index: Int, index: Int,
) raises -> Float64:
    if spreading_factor != 1 and spreading_factor != 2 and spreading_factor != 4:
        raise Error("PUCCH format-2 spreading factor must be one, two, or four")
    if orthogonal_index < 0 or orthogonal_index >= spreading_factor:
        raise Error("PUCCH format-2 orthogonal index is out of range")
    if spreading_factor == 1 or orthogonal_index == 0:
        return 1.0
    if spreading_factor == 2:
        return 1.0 if index == 0 else -1.0
    if orthogonal_index == 1:
        return 1.0 if index % 2 == 0 else -1.0
    if orthogonal_index == 2:
        return 1.0 if index < 2 else -1.0
    return 1.0 if index == 0 or index == 3 else -1.0


def nr_pucch_format2_dmrs(
    slot_in_frame: Int,
    symbol_in_slot: Int,
    n_id_0: Int,
    resource_blocks: Int,
    *,
    symbols_per_slot: Int = 14,
    spreading_factor: Int = 1,
    orthogonal_index: Int = 0,
) raises -> List[Complex64]:
    """Generate one OFDM symbol of format-2 Gold-sequence DM-RS.

    The result has four values per allocated resource block.  Optional
    spreading follows clause 6.4.1.3.2.1 and Tables 6.3.2.5A-1/2.
    """
    var c_init = nr_pucch_format2_dmrs_c_init(
        slot_in_frame,
        symbol_in_slot,
        n_id_0,
        symbols_per_slot=symbols_per_slot,
    )
    if resource_blocks < 1:
        raise Error("PUCCH format-2 allocation must contain a resource block")
    # Validate the OCC before generating the Gold sequence.
    _ = _format2_occ_sign(spreading_factor, orthogonal_index, 0)
    var output_length = _checked_pucch_product(4, resource_blocks)
    if output_length % spreading_factor != 0:
        raise Error("PUCCH format-2 DM-RS length is not divisible by its OCC")
    var base_length = output_length // spreading_factor
    if base_length > (Int.MAX - 1631) // 2:
        raise Error("PUCCH format-2 DM-RS sequence length overflows Int")
    var bits = nr_gold_bits(c_init, 2 * base_length)
    var scale = 1.0 / sqrt(2.0)
    var result = List[Complex64](capacity=output_length)
    for m in range(base_length):
        var base = Complex64(
            scale * (1.0 - 2.0 * Float64(bits[2 * m])),
            scale * (1.0 - 2.0 * Float64(bits[2 * m + 1])),
        )
        for index in range(spreading_factor):
            var sign = _format2_occ_sign(
                spreading_factor, orthogonal_index, index
            )
            result.append(base * Complex64(sign, 0.0))
    return result^


def nr_pucch_format2_data_re_count(
    symbol_count: Int, resource_blocks: Int,
) raises -> Int:
    if symbol_count < 1 or resource_blocks < 1:
        raise Error("PUCCH format-2 dimensions must be positive")
    return _checked_pucch_product(
        _checked_pucch_product(8, symbol_count), resource_blocks
    )


def nr_pucch_format2_dmrs_re_count(
    symbol_count: Int, resource_blocks: Int,
) raises -> Int:
    if symbol_count < 1 or resource_blocks < 1:
        raise Error("PUCCH format-2 dimensions must be positive")
    return _checked_pucch_product(
        _checked_pucch_product(4, symbol_count), resource_blocks
    )


def _validate_grid_allocation(
    grid: NRResourceGrid,
    start_symbol: Int,
    symbol_count: Int,
    first_subcarrier: Int,
    resource_blocks: Int,
) raises:
    if start_symbol < 0 or symbol_count < 1:
        raise Error("PUCCH symbol allocation is invalid")
    if (
        symbol_count > grid.symbol_count
        or start_symbol > grid.symbol_count - symbol_count
    ):
        raise Error("PUCCH symbol allocation exceeds the resource grid")
    if first_subcarrier < 0 or resource_blocks < 1:
        raise Error("PUCCH frequency allocation is invalid")
    var allocation_subcarriers = _checked_pucch_product(
        _SUBCARRIERS_PER_RB, resource_blocks
    )
    if (
        allocation_subcarriers > grid.subcarrier_count
        or first_subcarrier > grid.subcarrier_count - allocation_subcarriers
    ):
        raise Error("PUCCH frequency allocation exceeds the resource grid")


def nr_map_pucch_format2(
    mut grid: NRResourceGrid,
    start_symbol: Int,
    first_subcarrier: Int,
    resource_blocks: Int,
    symbol_count: Int,
    data: Span[Complex64, ...],
    dmrs: Span[Complex64, ...],
) raises:
    """Map format-2 data and DM-RS in increasing ``k``, then ``l`` order.

    Each symbol uses DM-RS at local allocation indices ``k=3*m+1``.  Since a
    PRB has twelve subcarriers, a resource-block-aligned allocation has the
    same residue as ``k`` relative to common resource block zero.
    """
    _validate_grid_allocation(
        grid, start_symbol, symbol_count, first_subcarrier, resource_blocks
    )
    if len(data) != nr_pucch_format2_data_re_count(
        symbol_count, resource_blocks
    ):
        raise Error("PUCCH format-2 data count does not match the allocation")
    if len(dmrs) != nr_pucch_format2_dmrs_re_count(
        symbol_count, resource_blocks
    ):
        raise Error("PUCCH format-2 DM-RS count does not match the allocation")
    # Validate the entire operation before mutating the caller's grid.
    _validate_finite_pucch_values(data)
    _validate_finite_pucch_values(dmrs)

    var data_index = 0
    var dmrs_index = 0
    var allocation_subcarriers = _SUBCARRIERS_PER_RB * resource_blocks
    for local_symbol in range(symbol_count):
        for local_subcarrier in range(allocation_subcarriers):
            if local_subcarrier % 3 == 1:
                grid[
                    start_symbol + local_symbol,
                    first_subcarrier + local_subcarrier,
                ] = Complex64(dmrs[dmrs_index].re, dmrs[dmrs_index].im)
                dmrs_index += 1
            else:
                grid[
                    start_symbol + local_symbol,
                    first_subcarrier + local_subcarrier,
                ] = Complex64(data[data_index].re, data[data_index].im)
                data_index += 1


def nr_extract_pucch_format2_data(
    grid: NRResourceGrid,
    start_symbol: Int,
    first_subcarrier: Int,
    resource_blocks: Int,
    symbol_count: Int,
) raises -> List[Complex64]:
    _validate_grid_allocation(
        grid, start_symbol, symbol_count, first_subcarrier, resource_blocks
    )
    var result = List[Complex64](
        capacity=nr_pucch_format2_data_re_count(symbol_count, resource_blocks)
    )
    var allocation_subcarriers = _SUBCARRIERS_PER_RB * resource_blocks
    for local_symbol in range(symbol_count):
        for local_subcarrier in range(allocation_subcarriers):
            if local_subcarrier % 3 != 1:
                result.append(grid[
                    start_symbol + local_symbol,
                    first_subcarrier + local_subcarrier,
                ])
    return result^


def nr_extract_pucch_format2_dmrs(
    grid: NRResourceGrid,
    start_symbol: Int,
    first_subcarrier: Int,
    resource_blocks: Int,
    symbol_count: Int,
) raises -> List[Complex64]:
    _validate_grid_allocation(
        grid, start_symbol, symbol_count, first_subcarrier, resource_blocks
    )
    var result = List[Complex64](
        capacity=nr_pucch_format2_dmrs_re_count(symbol_count, resource_blocks)
    )
    var allocation_subcarriers = _SUBCARRIERS_PER_RB * resource_blocks
    for local_symbol in range(symbol_count):
        for local_subcarrier in range(allocation_subcarriers):
            if local_subcarrier % 3 == 1:
                result.append(grid[
                    start_symbol + local_symbol,
                    first_subcarrier + local_subcarrier,
                ])
    return result^


def nr_pucch_format3_4_dmrs_positions(
    pucch_symbols: Int,
    *,
    intra_slot_hopping: Bool = False,
    additional_dmrs: Bool = False,
) raises -> List[Int]:
    """Return Table 6.4.1.3.3.2-1 positions relative to the PUCCH span."""
    if pucch_symbols < 4 or pucch_symbols > 14:
        raise Error("PUCCH format-3/4 length must be in [4,14]")

    var result = List[Int]()
    if pucch_symbols == 4:
        if intra_slot_hopping:
            result.append(0)
            result.append(2)
        else:
            result.append(1)
        return result^

    # For lengths 5 through 14 the hopping and no-hopping columns are merged
    # in the normative table.  Additional DM-RS differs only from length 10.
    if additional_dmrs and pucch_symbols >= 10:
        result.append(1)
        if pucch_symbols <= 11:
            result.append(3)
            result.append(6)
        elif pucch_symbols <= 13:
            result.append(4)
            result.append(7)
        else:
            result.append(5)
            result.append(8)
        result.append(pucch_symbols - 2)
        return result^

    if pucch_symbols == 5:
        result.append(0)
        result.append(3)
    elif pucch_symbols <= 7:
        result.append(1)
        result.append(4)
    elif pucch_symbols == 8:
        result.append(1)
        result.append(5)
    elif pucch_symbols == 9:
        result.append(1)
        result.append(6)
    elif pucch_symbols <= 11:
        result.append(2)
        result.append(7)
    elif pucch_symbols == 12:
        result.append(2)
        result.append(8)
    elif pucch_symbols == 13:
        result.append(2)
        result.append(9)
    else:
        result.append(3)
        result.append(10)
    return result^


def _validate_format3_4_resource_blocks(resource_blocks: Int) raises:
    if resource_blocks < 1:
        raise Error("PUCCH format-3/4 allocation must contain a resource block")
    var remainder = resource_blocks
    while remainder % 2 == 0:
        remainder //= 2
    while remainder % 3 == 0:
        remainder //= 3
    while remainder % 5 == 0:
        remainder //= 5
    if remainder != 1:
        raise Error("non-interlaced PUCCH format-3/4 PRBs must factor over 2,3,5")


def nr_pucch_format3_4_dmrs_re_count(
    pucch_symbols: Int,
    resource_blocks: Int,
    *,
    intra_slot_hopping: Bool = False,
    additional_dmrs: Bool = False,
) raises -> Int:
    _validate_format3_4_resource_blocks(resource_blocks)
    var positions = nr_pucch_format3_4_dmrs_positions(
        pucch_symbols,
        intra_slot_hopping=intra_slot_hopping,
        additional_dmrs=additional_dmrs,
    )
    return _checked_pucch_product(
        _checked_pucch_product(len(positions), _SUBCARRIERS_PER_RB),
        resource_blocks,
    )


def nr_pucch_format3_4_data_re_count(
    pucch_symbols: Int,
    resource_blocks: Int,
    *,
    intra_slot_hopping: Bool = False,
    additional_dmrs: Bool = False,
) raises -> Int:
    _validate_format3_4_resource_blocks(resource_blocks)
    var positions = nr_pucch_format3_4_dmrs_positions(
        pucch_symbols,
        intra_slot_hopping=intra_slot_hopping,
        additional_dmrs=additional_dmrs,
    )
    return _checked_pucch_product(
        _checked_pucch_product(
            pucch_symbols - len(positions), _SUBCARRIERS_PER_RB
        ),
        resource_blocks,
    )


def _contains_symbol(positions: Span[Int, ...], symbol: Int) -> Bool:
    for index in range(len(positions)):
        if positions[index] == symbol:
            return True
    return False


def _validate_format3_4_grid(
    grid: NRResourceGrid,
    start_symbol: Int,
    first_subcarrier: Int,
    resource_blocks: Int,
    pucch_symbols: Int,
    intra_slot_hopping: Bool,
    second_hop_first_subcarrier: Int,
) raises:
    _validate_format3_4_resource_blocks(resource_blocks)
    _validate_grid_allocation(
        grid,
        start_symbol,
        pucch_symbols,
        first_subcarrier,
        resource_blocks,
    )
    if intra_slot_hopping:
        if second_hop_first_subcarrier < 0:
            raise Error("PUCCH second-hop frequency allocation is required")
        _validate_grid_allocation(
            grid,
            start_symbol,
            pucch_symbols,
            second_hop_first_subcarrier,
            resource_blocks,
        )


def _format3_4_first_subcarrier(
    local_symbol: Int,
    pucch_symbols: Int,
    first_subcarrier: Int,
    intra_slot_hopping: Bool,
    second_hop_first_subcarrier: Int,
) -> Int:
    if intra_slot_hopping and local_symbol >= pucch_symbols // 2:
        return second_hop_first_subcarrier
    return first_subcarrier


def nr_map_pucch_format3_4_non_interlaced(
    mut grid: NRResourceGrid,
    start_symbol: Int,
    first_subcarrier: Int,
    resource_blocks: Int,
    pucch_symbols: Int,
    data: Span[Complex64, ...],
    dmrs: Span[Complex64, ...],
    *,
    intra_slot_hopping: Bool = False,
    additional_dmrs: Bool = False,
    second_hop_first_subcarrier: Int = -1,
) raises:
    """Map format-3/4 data and caller-generated DM-RS without interlacing.

    ``dmrs`` must already conform to clause 6.4.1.3.3.1.  Values are grouped
    by DM-RS symbol and then by increasing subcarrier.  This function does not
    generate or approximate the configuration-dependent DM-RS sequence.
    """
    _validate_format3_4_grid(
        grid,
        start_symbol,
        first_subcarrier,
        resource_blocks,
        pucch_symbols,
        intra_slot_hopping,
        second_hop_first_subcarrier,
    )
    var positions = nr_pucch_format3_4_dmrs_positions(
        pucch_symbols,
        intra_slot_hopping=intra_slot_hopping,
        additional_dmrs=additional_dmrs,
    )
    var expected_dmrs = nr_pucch_format3_4_dmrs_re_count(
        pucch_symbols,
        resource_blocks,
        intra_slot_hopping=intra_slot_hopping,
        additional_dmrs=additional_dmrs,
    )
    var expected_data = nr_pucch_format3_4_data_re_count(
        pucch_symbols,
        resource_blocks,
        intra_slot_hopping=intra_slot_hopping,
        additional_dmrs=additional_dmrs,
    )
    if len(data) != expected_data:
        raise Error("PUCCH format-3/4 data count does not match the allocation")
    if len(dmrs) != expected_dmrs:
        raise Error("PUCCH format-3/4 DM-RS count does not match the allocation")
    # Reject all non-finite values before the first resource-grid write.
    _validate_finite_pucch_values(data)
    _validate_finite_pucch_values(dmrs)

    var data_index = 0
    var dmrs_index = 0
    var allocation_subcarriers = _SUBCARRIERS_PER_RB * resource_blocks
    for local_symbol in range(pucch_symbols):
        var symbol_first_subcarrier = _format3_4_first_subcarrier(
            local_symbol,
            pucch_symbols,
            first_subcarrier,
            intra_slot_hopping,
            second_hop_first_subcarrier,
        )
        var is_dmrs = _contains_symbol(Span(positions), local_symbol)
        for local_subcarrier in range(allocation_subcarriers):
            if is_dmrs:
                grid[
                    start_symbol + local_symbol,
                    symbol_first_subcarrier + local_subcarrier,
                ] = Complex64(dmrs[dmrs_index].re, dmrs[dmrs_index].im)
                dmrs_index += 1
            else:
                grid[
                    start_symbol + local_symbol,
                    symbol_first_subcarrier + local_subcarrier,
                ] = Complex64(data[data_index].re, data[data_index].im)
                data_index += 1


def nr_extract_pucch_format3_4_data_non_interlaced(
    grid: NRResourceGrid,
    start_symbol: Int,
    first_subcarrier: Int,
    resource_blocks: Int,
    pucch_symbols: Int,
    *,
    intra_slot_hopping: Bool = False,
    additional_dmrs: Bool = False,
    second_hop_first_subcarrier: Int = -1,
) raises -> List[Complex64]:
    _validate_format3_4_grid(
        grid,
        start_symbol,
        first_subcarrier,
        resource_blocks,
        pucch_symbols,
        intra_slot_hopping,
        second_hop_first_subcarrier,
    )
    var positions = nr_pucch_format3_4_dmrs_positions(
        pucch_symbols,
        intra_slot_hopping=intra_slot_hopping,
        additional_dmrs=additional_dmrs,
    )
    var result = List[Complex64](
        capacity=nr_pucch_format3_4_data_re_count(
            pucch_symbols,
            resource_blocks,
            intra_slot_hopping=intra_slot_hopping,
            additional_dmrs=additional_dmrs,
        )
    )
    var allocation_subcarriers = _SUBCARRIERS_PER_RB * resource_blocks
    for local_symbol in range(pucch_symbols):
        if not _contains_symbol(Span(positions), local_symbol):
            var symbol_first_subcarrier = _format3_4_first_subcarrier(
                local_symbol,
                pucch_symbols,
                first_subcarrier,
                intra_slot_hopping,
                second_hop_first_subcarrier,
            )
            for local_subcarrier in range(allocation_subcarriers):
                result.append(grid[
                    start_symbol + local_symbol,
                    symbol_first_subcarrier + local_subcarrier,
                ])
    return result^


def nr_extract_pucch_format3_4_dmrs_non_interlaced(
    grid: NRResourceGrid,
    start_symbol: Int,
    first_subcarrier: Int,
    resource_blocks: Int,
    pucch_symbols: Int,
    *,
    intra_slot_hopping: Bool = False,
    additional_dmrs: Bool = False,
    second_hop_first_subcarrier: Int = -1,
) raises -> List[Complex64]:
    """Extract caller-generated format-3/4 DM-RS in standard mapping order."""
    _validate_format3_4_grid(
        grid,
        start_symbol,
        first_subcarrier,
        resource_blocks,
        pucch_symbols,
        intra_slot_hopping,
        second_hop_first_subcarrier,
    )
    var positions = nr_pucch_format3_4_dmrs_positions(
        pucch_symbols,
        intra_slot_hopping=intra_slot_hopping,
        additional_dmrs=additional_dmrs,
    )
    var result = List[Complex64](
        capacity=nr_pucch_format3_4_dmrs_re_count(
            pucch_symbols,
            resource_blocks,
            intra_slot_hopping=intra_slot_hopping,
            additional_dmrs=additional_dmrs,
        )
    )
    var allocation_subcarriers = _SUBCARRIERS_PER_RB * resource_blocks
    for local_symbol in range(pucch_symbols):
        if _contains_symbol(Span(positions), local_symbol):
            var symbol_first_subcarrier = _format3_4_first_subcarrier(
                local_symbol,
                pucch_symbols,
                first_subcarrier,
                intra_slot_hopping,
                second_hop_first_subcarrier,
            )
            for local_subcarrier in range(allocation_subcarriers):
                result.append(grid[
                    start_symbol + local_symbol,
                    symbol_first_subcarrier + local_subcarrier,
                ])
    return result^
