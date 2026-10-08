"""Bounded Rel-17 NR FR2-2/n263 configuration and timing algorithms.

This scalar CPU reference closes an auditable subset of 3GPP Work Item
``NR_ext_to_71GHz`` (UID 860041, core child UID 860141).  It transcribes:

* TS 38.211 V17.10.0 Tables 4.2-1 and 4.3.2-1 for the normal-CP
  120/480/960-kHz numerologies used by n263;
* TS 38.101-2 V17.20.0 Tables 5.3.2-1, 5.3.3-1, and 5.3.5-1 (identical
  BS values in TS 38.104 V17.22.0 Tables 5.3.2-3, 5.3.3-2a, and 5.3.5-3);
* TS 38.211 V17.10.0 Table 6.3.3.2-1 for the complete 3-by-3 n263
  ``L_RA=139`` PRACH/PUSCH SCS allocation subset; and
* TS 38.101-2 V17.20.0 Tables 5.1-1, 5.2-1, 5.4.2.1-1, and 5.4.2.3-2
  (the corresponding BS table is TS 38.104 Table 5.4.2.3-3).

The module deliberately does not claim RF requirements, waveform generation,
individual cyclic-prefix sample timing, PRACH occasion scheduling, PUSCH or
PUCCH processing, RRC ASN.1 decoding, channel access, or regulatory approval.
The 800/1600/2000-MHz channel bandwidths and both 480/960-kHz SCS values keep
their Rel-17 optionality metadata instead of being promoted to mandatory.
"""

from std.math import isfinite


comptime NR_FR2_2_REL17_BAND_N263 = 263
comptime NR_FR2_2_REL17_SYMBOLS_PER_SLOT = 14
comptime NR_FR2_2_REL17_SUBCARRIERS_PER_RB = 12
comptime NR_FR2_2_REL17_MIN_FREQUENCY_MHZ = 52600.0
comptime NR_FR2_2_REL17_MAX_FREQUENCY_MHZ = 71000.0
comptime NR_FR2_2_REL17_N263_MIN_FREQUENCY_MHZ = 57000.0
comptime NR_FR2_2_REL17_N263_MAX_FREQUENCY_MHZ = 71000.0


def _numerology_values(
    subcarrier_spacing_khz: Int,
) raises -> Tuple[Int, Int, Int, Int]:
    if subcarrier_spacing_khz == 120:
        return (3, 8, 80, 125000)
    if subcarrier_spacing_khz == 480:
        return (5, 32, 320, 31250)
    if subcarrier_spacing_khz == 960:
        return (6, 64, 640, 15625)
    raise Error("Rel-17 n263 SCS must be 120, 480, or 960 kHz")


struct NRFR22Rel17Numerology(ImplicitlyCopyable, Equatable):
    """One exact normal-CP n263 numerology and slot-geometry row."""

    var mu: Int
    var subcarrier_spacing_khz: Int
    var symbols_per_slot: Int
    var slots_per_subframe: Int
    var slots_per_frame: Int
    var slot_duration_ns: Int

    def __init__(
        out self,
        mu: Int,
        subcarrier_spacing_khz: Int,
        symbols_per_slot: Int,
        slots_per_subframe: Int,
        slots_per_frame: Int,
        slot_duration_ns: Int,
    ) raises:
        self.mu = mu
        self.subcarrier_spacing_khz = subcarrier_spacing_khz
        self.symbols_per_slot = symbols_per_slot
        self.slots_per_subframe = slots_per_subframe
        self.slots_per_frame = slots_per_frame
        self.slot_duration_ns = slot_duration_ns
        self.validate()

    def validate(self) raises:
        """Revalidate all mutable numerology fields against the exact tables."""
        var expected = _numerology_values(self.subcarrier_spacing_khz)
        if (
            self.mu != expected[0]
            or self.symbols_per_slot != NR_FR2_2_REL17_SYMBOLS_PER_SLOT
            or self.slots_per_subframe != expected[1]
            or self.slots_per_frame != expected[2]
            or self.slot_duration_ns != expected[3]
        ):
            raise Error("mutated or inconsistent Rel-17 FR2-2 numerology")


def nr_fr2_2_rel17_numerology(
    subcarrier_spacing_khz: Int,
) raises -> NRFR22Rel17Numerology:
    """Return TS 38.211 Tables 4.2-1/4.3.2-1 n263 slot geometry."""
    var values = _numerology_values(subcarrier_spacing_khz)
    return NRFR22Rel17Numerology(
        values[0],
        subcarrier_spacing_khz,
        NR_FR2_2_REL17_SYMBOLS_PER_SLOT,
        values[1],
        values[2],
        values[3],
    )


def _checked_nonnegative_int(value: Int128, field: String) raises -> Int:
    if value < Int128(0) or value > Int128(Int.MAX):
        raise Error(field + " exceeds Int")
    return Int(value)


def nr_fr2_2_rel17_elapsed_slot_start_ns(
    numerology: NRFR22Rel17Numerology,
    unwrapped_frame_index: Int,
    slot_index_in_frame: Int,
) raises -> Int:
    """Return an exact slot start on an unwrapped frame timeline in ns.

    This is slot-boundary arithmetic only.  It does not approximate the
    unequal cyclic-prefix lengths of individual OFDM symbols.
    """
    numerology.validate()
    if unwrapped_frame_index < 0:
        raise Error("unwrapped frame index cannot be negative")
    if (
        slot_index_in_frame < 0
        or slot_index_in_frame >= numerology.slots_per_frame
    ):
        raise Error("slot index is outside the selected numerology frame")
    var absolute_slot = (
        Int128(unwrapped_frame_index) * Int128(numerology.slots_per_frame)
        + Int128(slot_index_in_frame)
    )
    return _checked_nonnegative_int(
        absolute_slot * Int128(numerology.slot_duration_ns),
        "FR2-2 elapsed slot start",
    )


def nr_fr2_2_rel17_symbol_ordinal(
    numerology: NRFR22Rel17Numerology,
    unwrapped_frame_index: Int,
    slot_index_in_frame: Int,
    symbol_index_in_slot: Int,
) raises -> Int:
    """Flatten an n263 frame/slot/symbol tuple to an exact symbol ordinal."""
    numerology.validate()
    if unwrapped_frame_index < 0:
        raise Error("unwrapped frame index cannot be negative")
    if (
        slot_index_in_frame < 0
        or slot_index_in_frame >= numerology.slots_per_frame
    ):
        raise Error("slot index is outside the selected numerology frame")
    if (
        symbol_index_in_slot < 0
        or symbol_index_in_slot >= numerology.symbols_per_slot
    ):
        raise Error("OFDM symbol index must be in [0,13]")
    var absolute_slot = (
        Int128(unwrapped_frame_index) * Int128(numerology.slots_per_frame)
        + Int128(slot_index_in_frame)
    )
    return _checked_nonnegative_int(
        absolute_slot * Int128(numerology.symbols_per_slot)
        + Int128(symbol_index_in_slot),
        "FR2-2 symbol ordinal",
    )


def _carrier_values(
    subcarrier_spacing_khz: Int, channel_bandwidth_mhz: Int
) raises -> Tuple[Int, Int, Bool, Bool]:
    if subcarrier_spacing_khz == 120:
        if channel_bandwidth_mhz == 100:
            return (66, 2420, False, False)
        if channel_bandwidth_mhz == 400:
            return (264, 9860, False, False)
    elif subcarrier_spacing_khz == 480:
        if channel_bandwidth_mhz == 400:
            return (66, 9680, True, False)
        if channel_bandwidth_mhz == 800:
            return (124, 42640, True, True)
        if channel_bandwidth_mhz == 1600:
            return (248, 85520, True, True)
    elif subcarrier_spacing_khz == 960:
        if channel_bandwidth_mhz == 400:
            return (33, 9440, True, False)
        if channel_bandwidth_mhz == 800:
            return (62, 42400, True, True)
        if channel_bandwidth_mhz == 1600:
            return (124, 85280, True, True)
        if channel_bandwidth_mhz == 2000:
            return (148, 147040, True, True)
    raise Error("unsupported Rel-17 n263 SCS/channel-bandwidth pair")


struct NRFR22Rel17CarrierConfig(ImplicitlyCopyable, Equatable):
    """One exact n263 channel-bandwidth, PRB, and guardband table row."""

    var band: Int
    var subcarrier_spacing_khz: Int
    var channel_bandwidth_mhz: Int
    var maximum_resource_blocks: Int
    var minimum_guardband_khz: Int
    var optional_subcarrier_spacing: Bool
    var optional_channel_bandwidth: Bool

    def __init__(
        out self,
        band: Int,
        subcarrier_spacing_khz: Int,
        channel_bandwidth_mhz: Int,
        maximum_resource_blocks: Int,
        minimum_guardband_khz: Int,
        optional_subcarrier_spacing: Bool,
        optional_channel_bandwidth: Bool,
    ) raises:
        self.band = band
        self.subcarrier_spacing_khz = subcarrier_spacing_khz
        self.channel_bandwidth_mhz = channel_bandwidth_mhz
        self.maximum_resource_blocks = maximum_resource_blocks
        self.minimum_guardband_khz = minimum_guardband_khz
        self.optional_subcarrier_spacing = optional_subcarrier_spacing
        self.optional_channel_bandwidth = optional_channel_bandwidth
        self.validate()

    def validate(self) raises:
        """Revalidate all mutable carrier fields against the Rel-17 tables."""
        if self.band != NR_FR2_2_REL17_BAND_N263:
            raise Error("bounded Rel-17 FR2-2 profile supports band n263 only")
        var expected = _carrier_values(
            self.subcarrier_spacing_khz, self.channel_bandwidth_mhz
        )
        if (
            self.maximum_resource_blocks != expected[0]
            or self.minimum_guardband_khz != expected[1]
            or self.optional_subcarrier_spacing != expected[2]
            or self.optional_channel_bandwidth != expected[3]
        ):
            raise Error("mutated or inconsistent Rel-17 n263 carrier row")


def nr_fr2_2_rel17_carrier_config(
    subcarrier_spacing_khz: Int, channel_bandwidth_mhz: Int
) raises -> NRFR22Rel17CarrierConfig:
    """Lookup one exact n263 Tables 5.3.2/5.3.3/5.3.5 carrier row."""
    var values = _carrier_values(
        subcarrier_spacing_khz, channel_bandwidth_mhz
    )
    return NRFR22Rel17CarrierConfig(
        NR_FR2_2_REL17_BAND_N263,
        subcarrier_spacing_khz,
        channel_bandwidth_mhz,
        values[0],
        values[1],
        values[2],
        values[3],
    )


def nr_fr2_2_rel17_occupied_bandwidth_khz(
    config: NRFR22Rel17CarrierConfig,
) raises -> Int:
    """Return ``N_RB * 12 * SCS`` with checked integer arithmetic."""
    config.validate()
    return _checked_nonnegative_int(
        Int128(config.maximum_resource_blocks)
        * Int128(NR_FR2_2_REL17_SUBCARRIERS_PER_RB)
        * Int128(config.subcarrier_spacing_khz),
        "FR2-2 occupied bandwidth",
    )


def nr_fr2_2_rel17_minimum_guardband_khz(
    config: NRFR22Rel17CarrierConfig,
) raises -> Int:
    """Recompute the exact TS 38.101-2 clause 5.3.3 guardband equation."""
    config.validate()
    var channel_khz = Int128(config.channel_bandwidth_mhz) * Int128(1000)
    var occupied_khz = (
        Int128(config.maximum_resource_blocks)
        * Int128(NR_FR2_2_REL17_SUBCARRIERS_PER_RB)
        * Int128(config.subcarrier_spacing_khz)
    )
    var remainder = channel_khz - occupied_khz
    if remainder < Int128(0) or remainder % Int128(2) != Int128(0):
        raise Error("FR2-2 guardband equation is not exactly representable")
    var guardband = (
        remainder // Int128(2)
        - Int128(config.subcarrier_spacing_khz) // Int128(2)
    )
    var result = _checked_nonnegative_int(
        guardband, "FR2-2 minimum guardband"
    )
    if result != config.minimum_guardband_khz:
        raise Error("FR2-2 guardband equation disagrees with the table row")
    return result


def nr_fr2_2_rel17_nominal_channel_spacing_100khz(
    first: NRFR22Rel17CarrierConfig,
    second: NRFR22Rel17CarrierConfig,
) raises -> Int:
    """Return n263 nominal adjacent-channel spacing in exact 100-kHz units.

    TS 38.101-2 clause 5.4.1.1 defines
    ``ceil((BW1 + BW2) / 100.8) * 50.4 MHz`` for n263.
    """
    first.validate()
    second.validate()
    var sum_tenth_mhz = (
        Int128(first.channel_bandwidth_mhz)
        + Int128(second.channel_bandwidth_mhz)
    ) * Int128(10)
    var multiples = (
        sum_tenth_mhz + Int128(1007)
    ) // Int128(1008)
    return _checked_nonnegative_int(
        multiples * Int128(504), "n263 nominal channel spacing"
    )


def _prach_values(
    prach_subcarrier_spacing_khz: Int,
    pusch_subcarrier_spacing_khz: Int,
) raises -> Tuple[Int, Int]:
    if prach_subcarrier_spacing_khz == 120:
        if pusch_subcarrier_spacing_khz == 120:
            return (12, 2)
        if pusch_subcarrier_spacing_khz == 480:
            return (3, 1)
        if pusch_subcarrier_spacing_khz == 960:
            return (2, 23)
    elif prach_subcarrier_spacing_khz == 480:
        if pusch_subcarrier_spacing_khz == 120:
            return (48, 2)
        if pusch_subcarrier_spacing_khz == 480:
            return (12, 2)
        if pusch_subcarrier_spacing_khz == 960:
            return (6, 2)
    elif prach_subcarrier_spacing_khz == 960:
        if pusch_subcarrier_spacing_khz == 120:
            return (96, 2)
        if pusch_subcarrier_spacing_khz == 480:
            return (24, 2)
        if pusch_subcarrier_spacing_khz == 960:
            return (12, 2)
    raise Error("unsupported Rel-17 n263 L_RA=139 PRACH/PUSCH SCS pair")


struct NRFR22Rel17PRACHAllocation(ImplicitlyCopyable, Equatable):
    """One exact n263 ``L_RA=139`` TS 38.211 Table 6.3.3.2-1 row."""

    var sequence_length: Int
    var prach_subcarrier_spacing_khz: Int
    var pusch_subcarrier_spacing_khz: Int
    var pusch_allocation_resource_blocks: Int
    var k_bar: Int

    def __init__(
        out self,
        sequence_length: Int,
        prach_subcarrier_spacing_khz: Int,
        pusch_subcarrier_spacing_khz: Int,
        pusch_allocation_resource_blocks: Int,
        k_bar: Int,
    ) raises:
        self.sequence_length = sequence_length
        self.prach_subcarrier_spacing_khz = prach_subcarrier_spacing_khz
        self.pusch_subcarrier_spacing_khz = pusch_subcarrier_spacing_khz
        self.pusch_allocation_resource_blocks = (
            pusch_allocation_resource_blocks
        )
        self.k_bar = k_bar
        self.validate()

    def validate(self) raises:
        """Revalidate all mutable PRACH allocation fields."""
        if self.sequence_length != 139:
            raise Error("bounded Rel-17 FR2-2 PRACH profile requires L_RA=139")
        var expected = _prach_values(
            self.prach_subcarrier_spacing_khz,
            self.pusch_subcarrier_spacing_khz,
        )
        if (
            self.pusch_allocation_resource_blocks != expected[0]
            or self.k_bar != expected[1]
        ):
            raise Error("mutated or inconsistent Rel-17 FR2-2 PRACH row")


def nr_fr2_2_rel17_prach_allocation(
    prach_subcarrier_spacing_khz: Int,
    pusch_subcarrier_spacing_khz: Int,
) raises -> NRFR22Rel17PRACHAllocation:
    """Lookup the complete n263 ``L_RA=139`` 3-by-3 allocation subset."""
    var values = _prach_values(
        prach_subcarrier_spacing_khz, pusch_subcarrier_spacing_khz
    )
    return NRFR22Rel17PRACHAllocation(
        139,
        prach_subcarrier_spacing_khz,
        pusch_subcarrier_spacing_khz,
        values[0],
        values[1],
    )


def nr_fr2_2_rel17_prach_allocation_subcarriers(
    allocation: NRFR22Rel17PRACHAllocation,
) raises -> Int:
    """Return the checked PUSCH-grid subcarrier span of a PRACH row."""
    allocation.validate()
    return _checked_nonnegative_int(
        Int128(allocation.pusch_allocation_resource_blocks)
        * Int128(NR_FR2_2_REL17_SUBCARRIERS_PER_RB),
        "FR2-2 PRACH allocation subcarriers",
    )


def _regular_arfcn_parameters(
    channel_bandwidth_mhz: Int,
) raises -> Tuple[Int, Int, Int]:
    if channel_bandwidth_mhz == 100:
        return (2564083, 1680, 137)
    if channel_bandwidth_mhz == 400:
        return (2566603, 6720, 33)
    if channel_bandwidth_mhz == 800:
        return (2569963, 6720, 32)
    if channel_bandwidth_mhz == 1600:
        return (2576683, 6720, 30)
    if channel_bandwidth_mhz == 2000:
        return (2580043, 6720, 29)
    raise Error("n263 channel bandwidth must be 100/400/800/1600/2000 MHz")


def nr_fr2_2_rel17_n263_regular_arfcn_count(
    channel_bandwidth_mhz: Int,
) raises -> Int:
    """Return the number of arithmetic-sequence entries in Table 5.4.2.3-2."""
    return _regular_arfcn_parameters(channel_bandwidth_mhz)[2] + 1


def nr_fr2_2_rel17_n263_regular_arfcn(
    channel_bandwidth_mhz: Int, n: Int
) raises -> Int:
    """Evaluate one n263 Table 5.4.2.3-2 ``base + step*N`` entry."""
    var parameters = _regular_arfcn_parameters(channel_bandwidth_mhz)
    if n < 0 or n > parameters[2]:
        raise Error("n263 regular NR-ARFCN index is outside its table range")
    return _checked_nonnegative_int(
        Int128(parameters[0]) + Int128(parameters[1]) * Int128(n),
        "n263 NR-ARFCN",
    )


def nr_fr2_2_rel17_n263_2000mhz_exception_arfcn(
    exception_index: Int,
) raises -> Int:
    """Return one of the four non-sequence 2000-MHz n263 NR-ARFCNs."""
    if exception_index == 0:
        return 2585083
    if exception_index == 1:
        return 2655643
    if exception_index == 2:
        return 2692603
    if exception_index == 3:
        return 2764843
    raise Error("n263 2000-MHz exceptional NR-ARFCN index must be in [0,3]")


def nr_fr2_2_rel17_n263_arfcn_supported(
    channel_bandwidth_mhz: Int, arfcn: Int
) raises -> Bool:
    """Return exact membership in one n263 channel-bandwidth raster row."""
    var parameters = _regular_arfcn_parameters(channel_bandwidth_mhz)
    var delta = Int128(arfcn) - Int128(parameters[0])
    if (
        delta >= Int128(0)
        and delta % Int128(parameters[1]) == Int128(0)
        and delta // Int128(parameters[1]) <= Int128(parameters[2])
    ):
        return True
    if channel_bandwidth_mhz == 2000:
        return (
            arfcn == 2585083
            or arfcn == 2655643
            or arfcn == 2692603
            or arfcn == 2764843
        )
    return False


def nr_fr2_2_rel17_n263_center_frequency_hz(
    channel_bandwidth_mhz: Int, arfcn: Int
) raises -> Int:
    """Convert an applicable n263 NR-ARFCN to exact RF-reference hertz."""
    if not nr_fr2_2_rel17_n263_arfcn_supported(
        channel_bandwidth_mhz, arfcn
    ):
        raise Error("NR-ARFCN is not applicable to this n263 bandwidth")
    return _checked_nonnegative_int(
        Int128(24250080000)
        + Int128(60000) * (Int128(arfcn) - Int128(2016667)),
        "n263 RF reference frequency",
    )


def nr_fr2_2_rel17_frequency_in_n263_mhz(
    frequency_mhz: Float64,
) raises -> Bool:
    """Classify a finite frequency against the Table 5.2-1 n263 span.

    Membership in the nominal band span is not a complete carrier-fit,
    channel-raster, channel-access, or regulatory-compliance decision.
    """
    if not isfinite(frequency_mhz):
        raise Error("n263 frequency must be finite")
    return (
        frequency_mhz >= NR_FR2_2_REL17_N263_MIN_FREQUENCY_MHZ
        and frequency_mhz <= NR_FR2_2_REL17_N263_MAX_FREQUENCY_MHZ
    )
