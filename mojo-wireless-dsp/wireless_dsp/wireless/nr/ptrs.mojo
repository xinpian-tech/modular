"""PDSCH phase-tracking reference signal (PT-RS) reference primitives.

Density selection follows TS 38.214 clause 5.1.6.3.  Sequence selection and
time/frequency resource locations follow TS 38.211 clauses 7.4.1.2.1 and
7.4.1.2.2.  The phase estimator is deliberately protocol-independent once
the known and received pilot vectors have been extracted.
"""

from std.collections import Span
from std.math import atan2, cos, frexp, isfinite, ldexp, sin, sqrt
from wireless_dsp.core import Complex64
from .grid import NRResourceGrid
from .sequences import nr_qpsk_sequence


def _ptrs_safe_frexp64(value: Float64) -> Tuple[Float64, Int32]:
    """Return a correct decomposition for normal and subnormal Float64."""
    if value == 0.0:
        return (value, Int32(0))
    if abs(value) < 2.2250738585072014e-308:
        var scaled = frexp(value * 18014398509481984.0)
        return (
            scaled[0], scaled[1].cast[DType.int32]() - Int32(54)
        )
    var parts = frexp(value)
    return (parts[0], parts[1].cast[DType.int32]())


struct NRPTRSDensity(ImplicitlyCopyable):
    var enabled: Bool
    var time_density: Int
    var frequency_density: Int

    def __init__(
        out self, enabled: Bool, time_density: Int = 0,
        frequency_density: Int = 0,
    ) raises:
        if enabled and (
            (time_density != 1 and time_density != 2 and time_density != 4)
            or (frequency_density != 2 and frequency_density != 4)
        ):
            raise Error("PDSCH PT-RS density must have L in {1,2,4} and K in {2,4}")
        if not enabled and (time_density != 0 or frequency_density != 0):
            raise Error("disabled PDSCH PT-RS density must use zero L and K")
        self.enabled = enabled
        self.time_density = time_density
        self.frequency_density = frequency_density


struct NRPTRSPhaseEstimate(Movable):
    var symbols: List[Int]
    var phase_radians: List[Float64]
    var coherent_magnitudes: List[Float64]

    def __init__(
        out self, var symbols: List[Int], var phase_radians: List[Float64],
        var coherent_magnitudes: List[Float64],
    ):
        self.symbols = symbols^
        self.phase_radians = phase_radians^
        self.coherent_magnitudes = coherent_magnitudes^


def _ptrs_restore_product(
    normalized: Float64, received_scale: Float64, known_scale: Float64,
) raises -> Float64:
    """Restore a three-factor PT-RS magnitude without intermediate overflow."""
    if normalized == 0.0 or received_scale == 0.0:
        return 0.0
    var normalized_parts = _ptrs_safe_frexp64(normalized)
    var received_parts = _ptrs_safe_frexp64(received_scale)
    var known_parts = _ptrs_safe_frexp64(known_scale)
    var mantissa = (
        normalized_parts[0] * received_parts[0] * known_parts[0]
    )
    var exponent = (
        normalized_parts[1] + received_parts[1] + known_parts[1]
    )
    # Canonicalize the three-mantissa product before calling ldexp.  The
    # pinned stdlib's ldexp does not define useful results for exponents far
    # beyond Float64's subnormal domain, so reject/flush those mathematical
    # ranges explicitly instead of accepting finite garbage.
    var mantissa_parts = _ptrs_safe_frexp64(mantissa)
    mantissa = mantissa_parts[0]
    exponent += mantissa_parts[1]
    if exponent < -1074:
        return 0.0
    if exponent > 1024:
        raise Error("PT-RS coherent magnitude is outside the finite range")
    var restored: Float64
    if exponent <= -1022:
        restored = (
            ldexp(mantissa, exponent + Int32(1022))
            * 2.2250738585072014e-308
        )
    elif exponent == 1024:
        restored = ldexp(mantissa, Int32(1023)) * 2.0
    else:
        restored = ldexp(mantissa, exponent)
    if not isfinite(restored) or restored < 0.0:
        raise Error("PT-RS coherent magnitude is outside the finite range")
    return restored


def nr_pdsch_ptrs_density_from_thresholds(
    scheduled_mcs: Int,
    scheduled_resource_blocks: Int,
    ptrs_mcs1: Int,
    ptrs_mcs2: Int,
    ptrs_mcs3: Int,
    ptrs_mcs4: Int,
    n_rb0: Int,
    n_rb1: Int,
) raises -> NRPTRSDensity:
    """Apply TS 38.214 Tables 5.1.6.3-1/2 threshold selection."""
    if (
        scheduled_mcs < 0 or scheduled_resource_blocks < 1
        or ptrs_mcs1 < 0 or ptrs_mcs1 > ptrs_mcs2
        or ptrs_mcs2 > ptrs_mcs3 or ptrs_mcs3 > ptrs_mcs4
        or n_rb0 < 1 or n_rb0 > n_rb1
    ):
        raise Error("invalid PDSCH PT-RS density thresholds")
    if scheduled_mcs < ptrs_mcs1 or scheduled_resource_blocks < n_rb0:
        return NRPTRSDensity(False)
    var time_density = 1
    if scheduled_mcs < ptrs_mcs2:
        time_density = 4
    elif scheduled_mcs < ptrs_mcs3:
        time_density = 2
    elif scheduled_mcs >= ptrs_mcs4:
        # ptrs-MCS4 is one past the last valid MCS for the selected table.
        return NRPTRSDensity(False)
    var frequency_density = 2 if scheduled_resource_blocks < n_rb1 else 4
    return NRPTRSDensity(True, time_density, frequency_density)


def nr_pdsch_ptrs_c_init(
    slot: Int, first_dmrs_symbol: Int, n_id: Int, n_scid: Int,
    *, symbols_per_slot: Int = 14,
) raises -> UInt32:
    """PDSCH DM-RS c_init reused by PT-RS at position l0."""
    if (
        slot < 0
        or (symbols_per_slot != 12 and symbols_per_slot != 14)
        or first_dmrs_symbol < 0 or first_dmrs_symbol >= symbols_per_slot
        or n_id < 0 or n_id > 65535 or n_scid < 0 or n_scid > 1
    ):
        raise Error("invalid PDSCH PT-RS sequence initialization fields")
    var modulus = UInt64(1) << 31
    var time_term = (
        UInt64(symbols_per_slot) * (UInt64(slot) % modulus)
        + UInt64(first_dmrs_symbol + 1)
    ) % modulus
    var value = (
        (((UInt64(1) << 17) * time_term) % modulus)
        * UInt64(2 * n_id + 1)
        + UInt64(2 * n_id + n_scid)
    ) % modulus
    return UInt32(value)


def nr_pdsch_ptrs_time_positions(
    allocation_symbols: Int, time_density: Int,
    dmrs_symbols: Span[Int, ...],
) raises -> List[Int]:
    """Return PT-RS symbol indices relative to the PDSCH allocation start.

    A DM-RS resets the PT-RS periodicity; for double-symbol DM-RS the last
    symbol in the consecutive run is therefore the effective reference.
    """
    if allocation_symbols < 1 or (time_density != 1 and time_density != 2 and time_density != 4):
        raise Error("invalid PDSCH PT-RS time allocation")
    # TS 38.214 5.1.6.3 suppresses sparse PT-RS for short allocations.
    if (
        (allocation_symbols == 2 and time_density != 1)
        or (allocation_symbols == 4 and time_density == 4)
    ):
        return List[Int]()
    var dmrs = List[UInt8](length=allocation_symbols, fill=UInt8(0))
    for dmrs_index in range(len(dmrs_symbols)):
        var symbol = dmrs_symbols[dmrs_index]
        if symbol < 0 or symbol >= allocation_symbols:
            raise Error("DM-RS symbol is outside the PDSCH allocation")
        dmrs[symbol] = 1

    var positions = List[Int]()
    var reference = 0
    var index = 0
    while reference + index * time_density < allocation_symbols:
        var candidate = reference + index * time_density
        var lower = max(reference + (index - 1) * time_density + 1, reference)
        var last_dmrs = -1
        for symbol in range(lower, candidate + 1):
            if dmrs[symbol] != 0:
                last_dmrs = symbol
        if last_dmrs >= 0:
            reference = last_dmrs
            index = 1
            continue
        positions.append(candidate)
        index += 1
    return positions^


def nr_pdsch_ptrs_k_ref_re(
    dmrs_port: Int, dmrs_configuration_type: Int,
    resource_element_offset: Int, *, enhanced_dmrs: Bool = False,
) raises -> Int:
    """TS 38.211 Table 7.4.1.2.2-1 (offset00/01/10/11 => 0/1/2/3)."""
    if resource_element_offset < 0 or resource_element_offset > 3:
        raise Error("PT-RS resourceElementOffset must identify offset00/01/10/11")
    var offset = resource_element_offset
    if dmrs_configuration_type == 1:
        if dmrs_port == 1000:
            var values: List[Int] = [0, 2, 6, 8]
            return values[offset]
        if dmrs_port == 1001:
            var values: List[Int] = [2, 4, 8, 10]
            return values[offset]
        if dmrs_port == 1002:
            var values: List[Int] = [1, 3, 7, 9]
            return values[offset]
        if dmrs_port == 1003:
            var values: List[Int] = [3, 5, 9, 11]
            return values[offset]
        if enhanced_dmrs and dmrs_port == 1008:
            var values: List[Int] = [4, 6, 10, 0]
            return values[offset]
        if enhanced_dmrs and dmrs_port == 1009:
            var values: List[Int] = [6, 8, 0, 2]
            return values[offset]
        if enhanced_dmrs and dmrs_port == 1010:
            var values: List[Int] = [5, 7, 11, 1]
            return values[offset]
        if enhanced_dmrs and dmrs_port == 1011:
            var values: List[Int] = [7, 9, 1, 3]
            return values[offset]
        raise Error("unsupported configuration-type-1 DM-RS port for PT-RS")
    if dmrs_configuration_type == 2:
        if dmrs_port == 1000:
            var values: List[Int] = [0, 1, 6, 7]
            return values[offset]
        if dmrs_port == 1001:
            var values: List[Int] = [1, 6, 7, 0]
            return values[offset]
        if dmrs_port == 1002:
            var values: List[Int] = [2, 3, 8, 9]
            return values[offset]
        if dmrs_port == 1003:
            var values: List[Int] = [3, 8, 9, 2]
            return values[offset]
        if dmrs_port == 1004:
            var values: List[Int] = [4, 5, 10, 11]
            return values[offset]
        if dmrs_port == 1005:
            var values: List[Int] = [5, 10, 11, 4]
            return values[offset]
        if enhanced_dmrs and dmrs_port == 1012:
            var values: List[Int] = [6, 7, 0, 1]
            return values[offset]
        if enhanced_dmrs and dmrs_port == 1013:
            var values: List[Int] = [7, 0, 1, 6]
            return values[offset]
        if enhanced_dmrs and dmrs_port == 1014:
            var values: List[Int] = [8, 9, 2, 3]
            return values[offset]
        if enhanced_dmrs and dmrs_port == 1015:
            var values: List[Int] = [9, 2, 3, 8]
            return values[offset]
        if enhanced_dmrs and dmrs_port == 1016:
            var values: List[Int] = [10, 11, 4, 5]
            return values[offset]
        if enhanced_dmrs and dmrs_port == 1017:
            var values: List[Int] = [11, 4, 5, 10]
            return values[offset]
        raise Error("unsupported configuration-type-2 DM-RS port for PT-RS")
    raise Error("PDSCH DM-RS configuration type must be one or two")


def nr_pdsch_ptrs_frequency_positions(
    scheduled_resource_blocks: Int, rnti: Int, frequency_density: Int,
    dmrs_port: Int, dmrs_configuration_type: Int,
    resource_element_offset: Int, *, enhanced_dmrs: Bool = False,
) raises -> List[Int]:
    """Return zero-based subcarriers within the scheduled PDSCH RB set."""
    if (
        scheduled_resource_blocks < 1 or rnti < 0 or rnti > 65535
        or (frequency_density != 2 and frequency_density != 4)
    ):
        raise Error("invalid PDSCH PT-RS frequency allocation")
    var k_ref_re = nr_pdsch_ptrs_k_ref_re(
        dmrs_port,
        dmrs_configuration_type,
        resource_element_offset,
        enhanced_dmrs=enhanced_dmrs,
    )
    var remainder = scheduled_resource_blocks % frequency_density
    var divisor = frequency_density if remainder == 0 else remainder
    var k_ref_rb = rnti % divisor
    var result = List[Int]()
    var rb = k_ref_rb
    while rb < scheduled_resource_blocks:
        result.append(rb * 12 + k_ref_re)
        rb += frequency_density
    return result^


def _ptrs_dmrs_delta(
    dmrs_port: Int, dmrs_configuration_type: Int, enhanced_dmrs: Bool,
) raises -> Int:
    if dmrs_configuration_type == 1:
        if (
            dmrs_port == 1000 or dmrs_port == 1001
            or (enhanced_dmrs and (dmrs_port == 1008 or dmrs_port == 1009))
        ):
            return 0
        if (
            dmrs_port == 1002 or dmrs_port == 1003
            or (enhanced_dmrs and (dmrs_port == 1010 or dmrs_port == 1011))
        ):
            return 1
    elif dmrs_configuration_type == 2:
        if dmrs_port >= 1000 and dmrs_port <= 1005:
            return 2 * ((dmrs_port - 1000) // 2)
        if enhanced_dmrs and dmrs_port >= 1012 and dmrs_port <= 1017:
            return 2 * ((dmrs_port - 1012) // 2)
    raise Error("unsupported DM-RS port/configuration for PT-RS sequence")


def _ptrs_dmrs_sequence_index(
    absolute_subcarrier: Int, dmrs_port: Int,
    dmrs_configuration_type: Int, enhanced_dmrs: Bool,
) raises -> Int:
    var delta = _ptrs_dmrs_delta(
        dmrs_port, dmrs_configuration_type, enhanced_dmrs
    )
    var shifted = absolute_subcarrier - delta
    if shifted < 0:
        raise Error("PT-RS subcarrier precedes the DM-RS sequence reference")
    if dmrs_configuration_type == 1:
        if shifted % 2 != 0:
            raise Error("PT-RS subcarrier is not on the associated type-1 DM-RS comb")
        # r(2m+k') for basic or r(4m+k') for enhanced both reduce to
        # the ordered even/odd-comb sequence index at the selected RE.
        return shifted // 2
    var local = shifted % 12
    var block = shifted // 12
    if not enhanced_dmrs:
        if local != 0 and local != 1 and local != 6 and local != 7:
            raise Error("PT-RS subcarrier is not on the associated type-2 DM-RS comb")
        return 4 * block + (local if local < 2 else local - 4)
    if local != 0 and local != 1 and local != 6 and local != 7:
        raise Error("PT-RS subcarrier is not on the enhanced type-2 DM-RS comb")
    return 4 * block + (local if local < 2 else local - 4)


def nr_pdsch_ptrs_sequence(
    frequency_positions: Span[Int, ...], first_common_resource_block: Int,
    slot: Int, first_dmrs_symbol: Int, n_id: Int, n_scid: Int,
    dmrs_port: Int, dmrs_configuration_type: Int,
    *, enhanced_dmrs: Bool = False, symbols_per_slot: Int = 14,
) raises -> List[Complex64]:
    """Select PT-RS symbols from the PDSCH DM-RS mother sequence at l0."""
    if first_common_resource_block < 0:
        raise Error("first common resource block must be non-negative")
    if first_common_resource_block > Int.MAX // 12:
        raise Error("PT-RS absolute subcarrier overflows Int")
    var resource_block_start = 12 * first_common_resource_block
    var indices = List[Int](capacity=len(frequency_positions))
    var largest = -1
    for frequency_index in range(len(frequency_positions)):
        var local_subcarrier = frequency_positions[frequency_index]
        if local_subcarrier < 0:
            raise Error("PT-RS frequency position must be non-negative")
        if local_subcarrier > Int.MAX - resource_block_start:
            raise Error("PT-RS absolute subcarrier overflows Int")
        var absolute_subcarrier = resource_block_start + local_subcarrier
        var index = _ptrs_dmrs_sequence_index(
            absolute_subcarrier,
            dmrs_port,
            dmrs_configuration_type,
            enhanced_dmrs,
        )
        indices.append(index)
        largest = max(largest, index)
    if largest < 0:
        return List[Complex64]()
    var mother = nr_qpsk_sequence(
        nr_pdsch_ptrs_c_init(
            slot,
            first_dmrs_symbol,
            n_id,
            n_scid,
            symbols_per_slot=symbols_per_slot,
        ),
        largest + 1,
    )
    var result = List[Complex64](capacity=len(indices))
    for index in indices:
        result.append(mother[index])
    return result^


def nr_map_pdsch_ptrs(
    mut grid: NRResourceGrid,
    allocation_start_symbol: Int,
    first_subcarrier: Int,
    time_positions: Span[Int, ...],
    frequency_positions: Span[Int, ...],
    references: Span[Complex64, ...],
    *, beta: Float64 = 1.0,
) raises:
    """Map the time/frequency Cartesian product of PT-RS resource elements."""
    if (
        len(frequency_positions) != len(references)
        or not isfinite(beta)
        or beta < 0.0
    ):
        raise Error("PT-RS references do not match frequency positions")
    if allocation_start_symbol < 0 or first_subcarrier < 0:
        raise Error("PT-RS allocation origin must be non-negative")
    for index in range(len(references)):
        if (
            not isfinite(references[index].re)
            or not isfinite(references[index].im)
        ):
            raise Error("PT-RS references must be finite")
    for time_index in range(len(time_positions)):
        var time = time_positions[time_index]
        if (
            time < 0
            or allocation_start_symbol >= grid.symbol_count
            or time > grid.symbol_count - 1 - allocation_start_symbol
        ):
            raise Error("PT-RS time position is outside the resource grid")
        var symbol = allocation_start_symbol + time
        for index in range(len(frequency_positions)):
            var frequency = frequency_positions[index]
            if (
                frequency < 0
                or first_subcarrier >= grid.subcarrier_count
                or frequency > grid.subcarrier_count - 1 - first_subcarrier
            ):
                raise Error("PT-RS frequency position is outside the resource grid")
            var subcarrier = first_subcarrier + frequency
            var value = Complex64(
                beta * references[index].re, beta * references[index].im
            )
            if not isfinite(value.re) or not isfinite(value.im):
                raise Error("PT-RS mapped values must remain finite")
            grid[symbol, subcarrier] = value


def nr_extract_pdsch_ptrs(
    grid: NRResourceGrid,
    allocation_start_symbol: Int,
    first_subcarrier: Int,
    time_positions: Span[Int, ...],
    frequency_positions: Span[Int, ...],
) raises -> List[Complex64]:
    """Extract PT-RS observations in time-major, then frequency-major order."""
    if allocation_start_symbol < 0 or first_subcarrier < 0:
        raise Error("PT-RS allocation origin must be non-negative")
    if (
        len(frequency_positions) > 0
        and len(time_positions) > Int.MAX // len(frequency_positions)
    ):
        raise Error("PT-RS extraction dimensions overflow Int")
    var result = List[Complex64](
        capacity=len(time_positions) * len(frequency_positions)
    )
    for time_index in range(len(time_positions)):
        var time = time_positions[time_index]
        if (
            time < 0
            or allocation_start_symbol >= grid.symbol_count
            or time > grid.symbol_count - 1 - allocation_start_symbol
        ):
            raise Error("PT-RS time position is outside the resource grid")
        var symbol = allocation_start_symbol + time
        for frequency_index in range(len(frequency_positions)):
            var frequency = frequency_positions[frequency_index]
            if (
                frequency < 0
                or first_subcarrier >= grid.subcarrier_count
                or frequency > grid.subcarrier_count - 1 - first_subcarrier
            ):
                raise Error("PT-RS frequency position is outside the resource grid")
            var subcarrier = first_subcarrier + frequency
            var value = grid[symbol, subcarrier]
            if not isfinite(value.re) or not isfinite(value.im):
                raise Error("PT-RS observations must be finite")
            result.append(value)
    return result^


def nr_ptrs_estimate_common_phase(
    received: Span[Complex64, ...], known: Span[Complex64, ...],
    symbols: Span[Int, ...],
) raises -> NRPTRSPhaseEstimate:
    """Coherently estimate one common phase error for each observed symbol."""
    if len(known) < 1:
        raise Error("PT-RS phase observations have inconsistent dimensions")
    if len(symbols) > Int.MAX // len(known):
        raise Error("PT-RS phase observation dimensions overflow Int")
    if len(received) != len(known) * len(symbols):
        raise Error("PT-RS phase observations have inconsistent dimensions")
    for index in range(len(known)):
        if not isfinite(known[index].re) or not isfinite(known[index].im):
            raise Error("known PT-RS values must be finite")
    for index in range(len(received)):
        if not isfinite(received[index].re) or not isfinite(received[index].im):
            raise Error("received PT-RS values must be finite")
    var known_scale = 0.0
    for index in range(len(known)):
        if known[index].re == 0.0 and known[index].im == 0.0:
            raise Error("known PT-RS values must be non-zero")
        if abs(known[index].re) > known_scale:
            known_scale = abs(known[index].re)
        if abs(known[index].im) > known_scale:
            known_scale = abs(known[index].im)
    var phases = List[Float64](capacity=len(symbols))
    var magnitudes = List[Float64](capacity=len(symbols))
    var symbol_copy = List[Int](capacity=len(symbols))
    for time_index in range(len(symbols)):
        var received_scale = 0.0
        for frequency_index in range(len(known)):
            var received_index = time_index * len(known) + frequency_index
            if abs(received[received_index].re) > received_scale:
                received_scale = abs(received[received_index].re)
            if abs(received[received_index].im) > received_scale:
                received_scale = abs(received[received_index].im)
        var coherent_re = 0.0
        var coherent_im = 0.0
        var compensation_re = 0.0
        var compensation_im = 0.0
        for frequency_index in range(len(known)):
            if received_scale > 0.0:
                var received_index = time_index * len(known) + frequency_index
                var sample_re = received[received_index].re / received_scale
                var sample_im = received[received_index].im / received_scale
                var reference_re = known[frequency_index].re / known_scale
                var reference_im = known[frequency_index].im / known_scale
                var product_re = (
                    sample_re * reference_re + sample_im * reference_im
                )
                var product_im = (
                    sample_im * reference_re - sample_re * reference_im
                )
                var next_re = coherent_re + product_re
                if abs(coherent_re) >= abs(product_re):
                    compensation_re += (coherent_re - next_re) + product_re
                else:
                    compensation_re += (product_re - next_re) + coherent_re
                coherent_re = next_re
                var next_im = coherent_im + product_im
                if abs(coherent_im) >= abs(product_im):
                    compensation_im += (coherent_im - next_im) + product_im
                else:
                    compensation_im += (product_im - next_im) + coherent_im
                coherent_im = next_im
        coherent_re += compensation_re
        coherent_im += compensation_im
        var phase = atan2(coherent_im, coherent_re)
        var normalized_magnitude = Complex64(
            coherent_re, coherent_im
        ).magnitude()
        if not isfinite(phase) or not isfinite(normalized_magnitude):
            raise Error("PT-RS phase estimate must remain finite")
        phases.append(phase)
        magnitudes.append(_ptrs_restore_product(
            normalized_magnitude, received_scale, known_scale
        ))
        symbol_copy.append(symbols[time_index])
    return NRPTRSPhaseEstimate(symbol_copy^, phases^, magnitudes^)


def nr_ptrs_correct_common_phase(
    samples: Span[Complex64, ...], phase_radians: Float64,
) raises -> List[Complex64]:
    """Apply exp(-j*phase) to arbitrary data sharing a PT-RS CPE estimate."""
    if not isfinite(phase_radians):
        raise Error("PT-RS correction phase must be finite")
    var correction = Complex64(cos(phase_radians), -sin(phase_radians))
    var result = List[Complex64](capacity=len(samples))
    for index in range(len(samples)):
        if not isfinite(samples[index].re) or not isfinite(samples[index].im):
            raise Error("PT-RS correction samples must be finite")
        var sample = Complex64(samples[index].re, samples[index].im)
        var corrected = sample * correction
        if not isfinite(corrected.re) or not isfinite(corrected.im):
            raise Error("PT-RS corrected samples must remain finite")
        result.append(corrected)
    return result^
