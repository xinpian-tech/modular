"""Bounded Rel-17 NR positioning reference and timing arithmetic.

The normative baselines are ETSI TS 138 211 V17.10.0 clauses 5.2.1 and
7.4.1.7.2--7.4.1.7.3, ETSI TS 138 214 V17.16.0 clause 5.1.6.5, and ETSI
TS 138 215 V17.5.0 clauses 5.1.29--5.1.30 and 5.2.2--5.2.3.  The DL-PRS
mapper covers the published Rel-17 parameter envelope: 15/30/60/120 kHz,
normal CP plus extended CP at 60 kHz, 24--272 PRBs in steps of four, start
PRB 0--2176, and every allowed ``(L_PRS, K_comb)`` pair.

Inputs are already decoded higher-layer fields and already detected timing
reference points.  Slot activation, repetition/muting, SS/PBCH collision
avoidance, RF first-path detection, timestamp acquisition, antenna processing,
and location solvers are deliberately outside this pure CPU reference.  In
particular, TS 38.305 leaves the technique used to derive a position from the
measurements outside its scope; this module does not invent such a technique.
"""

from std.math import isfinite
from wireless_dsp.core import Complex64
from .sequences import nr_qpsk_sequence


comptime _PRS_SUBCARRIERS_PER_RB = 12
comptime _PRS_GOLD_MODULUS = UInt64(1) << 31


def _prs_symbols_per_slot(
    numerology: Int, extended_cyclic_prefix: Bool
) raises -> Int:
    # TS 38.214 5.1.6.5 excludes 240/480/960 kHz for the Rel-17 DL-PRS
    # positioning frequency layer, leaving mu=0..3.  TS 38.211 Table 4.2-1
    # permits extended CP only for mu=2.
    if numerology < 0 or numerology > 3:
        raise Error("Rel-17 DL-PRS numerology must be in [0,3]")
    if extended_cyclic_prefix:
        if numerology != 2:
            raise Error("extended CP DL-PRS requires numerology 2")
        return 12
    return 14


def _valid_prs_symbol_comb_pair(symbol_count: Int, comb_size: Int) -> Bool:
    return (
        (symbol_count == 2 and comb_size == 2)
        or (symbol_count == 4 and comb_size == 2)
        or (symbol_count == 6 and comb_size == 2)
        or (symbol_count == 12 and comb_size == 2)
        or (symbol_count == 4 and comb_size == 4)
        or (symbol_count == 12 and comb_size == 4)
        or (symbol_count == 6 and comb_size == 6)
        or (symbol_count == 12 and comb_size == 6)
        or (symbol_count == 12 and comb_size == 12)
    )


def _validate_prs_config_fields(
    sequence_id: Int,
    numerology: Int,
    slot_number: Int,
    first_resource_block: Int,
    resource_block_count: Int,
    comb_size: Int,
    resource_element_offset: Int,
    first_symbol: Int,
    symbol_count: Int,
    extended_cyclic_prefix: Bool,
) raises:
    var symbols_per_slot = _prs_symbols_per_slot(
        numerology, extended_cyclic_prefix
    )
    if sequence_id < 0 or sequence_id > 4095:
        raise Error("DL-PRS sequence identity must be in [0,4095]")
    var slots_per_frame = 10 * (1 << numerology)
    if slot_number < 0 or slot_number >= slots_per_frame:
        raise Error("DL-PRS slot number is outside its radio frame")
    if first_resource_block < 0 or first_resource_block > 2176:
        raise Error("DL-PRS start PRB must be in [0,2176]")
    if (
        resource_block_count < 24
        or resource_block_count > 272
        or resource_block_count % 4 != 0
    ):
        raise Error("DL-PRS bandwidth must be 24--272 PRBs in steps of four")
    if (
        comb_size != 2
        and comb_size != 4
        and comb_size != 6
        and comb_size != 12
    ):
        raise Error("DL-PRS comb size must be 2, 4, 6, or 12")
    if resource_element_offset < 0 or resource_element_offset >= comb_size:
        raise Error("DL-PRS resource-element offset is outside the comb")
    if not _valid_prs_symbol_comb_pair(symbol_count, comb_size):
        raise Error("DL-PRS symbol-count and comb-size pair is not specified")
    if (
        first_symbol < 0
        or first_symbol > symbols_per_slot - symbol_count
    ):
        raise Error("DL-PRS symbols do not fit in the selected slot")


struct NRDLPRSConfig(ImplicitlyCopyable):
    """Mutable decoded configuration for one bounded Rel-17 DL-PRS resource."""

    var sequence_id: Int
    var numerology: Int
    var slot_number: Int
    var first_resource_block: Int
    var resource_block_count: Int
    var comb_size: Int
    var resource_element_offset: Int
    var first_symbol: Int
    var symbol_count: Int
    var extended_cyclic_prefix: Bool

    def __init__(
        out self,
        sequence_id: Int,
        numerology: Int,
        slot_number: Int,
        first_resource_block: Int,
        resource_block_count: Int,
        comb_size: Int,
        resource_element_offset: Int,
        first_symbol: Int,
        symbol_count: Int,
        *,
        extended_cyclic_prefix: Bool = False,
    ) raises:
        self.sequence_id = sequence_id
        self.numerology = numerology
        self.slot_number = slot_number
        self.first_resource_block = first_resource_block
        self.resource_block_count = resource_block_count
        self.comb_size = comb_size
        self.resource_element_offset = resource_element_offset
        self.first_symbol = first_symbol
        self.symbol_count = symbol_count
        self.extended_cyclic_prefix = extended_cyclic_prefix
        self.validate()

    def validate(self) raises:
        """Revalidate every field, including mutations made after construction."""
        _validate_prs_config_fields(
            self.sequence_id,
            self.numerology,
            self.slot_number,
            self.first_resource_block,
            self.resource_block_count,
            self.comb_size,
            self.resource_element_offset,
            self.first_symbol,
            self.symbol_count,
            self.extended_cyclic_prefix,
        )


struct NRDLPRSResource(Movable):
    """Symbol-major DL-PRS RE coordinates, sequence indices, and values."""

    var symbols: List[Int]
    var subcarriers: List[Int]
    var sequence_indices: List[Int]
    var values: List[Complex64]

    def __init__(
        out self,
        var symbols: List[Int],
        var subcarriers: List[Int],
        var sequence_indices: List[Int],
        var values: List[Complex64],
    ):
        self.symbols = symbols^
        self.subcarriers = subcarriers^
        self.sequence_indices = sequence_indices^
        self.values = values^


def nr_dl_prs_c_init(
    sequence_id: Int,
    numerology: Int,
    slot_number: Int,
    symbol: Int,
    *,
    extended_cyclic_prefix: Bool = False,
) raises -> UInt32:
    """Return TS 38.211 clause 7.4.1.7.2 DL-PRS ``c_init``.

    ``slot_number`` is the slot index within the radio frame.  This Rel-17
    profile accepts the four PRS subcarrier spacings specified by TS 38.214
    clause 5.1.6.5 and applies the mandated modulo-``2^31`` arithmetic in
    ``UInt64`` so the largest legal intermediate cannot wrap.
    """
    var symbols_per_slot = _prs_symbols_per_slot(
        numerology, extended_cyclic_prefix
    )
    if sequence_id < 0 or sequence_id > 4095:
        raise Error("DL-PRS sequence identity must be in [0,4095]")
    var slots_per_frame = 10 * (1 << numerology)
    if slot_number < 0 or slot_number >= slots_per_frame:
        raise Error("DL-PRS slot number is outside its radio frame")
    if symbol < 0 or symbol >= symbols_per_slot:
        raise Error("DL-PRS symbol is outside its slot")

    var low_identity = sequence_id % 1024
    var value = (
        (UInt64(1) << 22) * UInt64(sequence_id // 1024)
        + (UInt64(1) << 10)
        * UInt64(symbols_per_slot * slot_number + symbol + 1)
        * UInt64(2 * low_identity + 1)
        + UInt64(low_identity)
    ) % _PRS_GOLD_MODULUS
    return UInt32(value)


def nr_dl_prs_sequence(
    sequence_id: Int,
    numerology: Int,
    slot_number: Int,
    symbol: Int,
    length: Int,
    *,
    extended_cyclic_prefix: Bool = False,
) raises -> List[Complex64]:
    """Generate the clause-7.4.1.7.2 unit-energy DL-PRS QPSK sequence."""
    return nr_qpsk_sequence(
        nr_dl_prs_c_init(
            sequence_id,
            numerology,
            slot_number,
            symbol,
            extended_cyclic_prefix=extended_cyclic_prefix,
        ),
        length,
    )


def nr_dl_prs_frequency_offset(
    comb_size: Int, relative_symbol: Int
) raises -> Int:
    """Return ``k'`` from TS 38.211 Table 7.4.1.7.3-1."""
    if relative_symbol < 0 or relative_symbol > 11:
        raise Error("DL-PRS relative symbol must be in [0,11]")
    if comb_size == 2:
        return relative_symbol % 2
    if comb_size == 4:
        var offsets: List[Int] = [0, 2, 1, 3, 0, 2, 1, 3, 0, 2, 1, 3]
        return offsets[relative_symbol]
    if comb_size == 6:
        var offsets: List[Int] = [0, 3, 1, 4, 2, 5, 0, 3, 1, 4, 2, 5]
        return offsets[relative_symbol]
    if comb_size == 12:
        var offsets: List[Int] = [0, 6, 3, 9, 1, 7, 4, 10, 2, 8, 5, 11]
        return offsets[relative_symbol]
    raise Error("DL-PRS comb size must be 2, 4, 6, or 12")


def nr_dl_prs_resource(
    config: NRDLPRSConfig, beta_prs: Float64 = 1.0
) raises -> NRDLPRSResource:
    """Map one DL-PRS resource per TS 38.211 clause 7.4.1.7.3.

    Coordinates are relative to Point A and returned symbol-major, with
    increasing subcarrier inside each symbol.  The sequence index is the
    normative ``m`` in ``k=m*K_comb+(k_offset+k') mod K_comb``.  The public
    boundary always calls ``config.validate()``, so a caller cannot bypass
    the specification envelope by mutating a previously valid configuration.
    Slot activity, muting, and SS/PBCH collisions remain caller-supplied
    preconditions as stated in the module boundary.
    """
    config.validate()
    if not isfinite(beta_prs) or beta_prs <= 0.0:
        raise Error("DL-PRS beta must be finite and positive")

    var references_per_symbol = (
        config.resource_block_count * _PRS_SUBCARRIERS_PER_RB
        // config.comb_size
    )
    var total_re = references_per_symbol * config.symbol_count
    var first_sequence_index = (
        config.first_resource_block * _PRS_SUBCARRIERS_PER_RB
        // config.comb_size
    )
    var sequence_length = (
        (config.first_resource_block + config.resource_block_count)
        * _PRS_SUBCARRIERS_PER_RB
        // config.comb_size
    )

    var symbols = List[Int](capacity=total_re)
    var subcarriers = List[Int](capacity=total_re)
    var sequence_indices = List[Int](capacity=total_re)
    var values = List[Complex64](capacity=total_re)

    for relative_symbol in range(config.symbol_count):
        var symbol = config.first_symbol + relative_symbol
        var k_prime = nr_dl_prs_frequency_offset(
            config.comb_size, relative_symbol
        )
        var residue = (
            config.resource_element_offset + k_prime
        ) % config.comb_size
        var sequence = nr_dl_prs_sequence(
            config.sequence_id,
            config.numerology,
            config.slot_number,
            symbol,
            sequence_length,
            extended_cyclic_prefix=config.extended_cyclic_prefix,
        )
        for local_index in range(references_per_symbol):
            var sequence_index = first_sequence_index + local_index
            var subcarrier = sequence_index * config.comb_size + residue
            var scaled = Complex64(
                beta_prs * sequence[sequence_index].re,
                beta_prs * sequence[sequence_index].im,
            )
            if (
                not isfinite(scaled.re)
                or not isfinite(scaled.im)
                or scaled.re == 0.0
                or scaled.im == 0.0
            ):
                raise Error("scaled DL-PRS value is not representable")
            symbols.append(symbol)
            subcarriers.append(subcarrier)
            sequence_indices.append(sequence_index)
            values.append(scaled)
    return NRDLPRSResource(
        symbols^, subcarriers^, sequence_indices^, values^
    )


def _finite_time_difference(lhs: Float64, rhs: Float64) raises -> Float64:
    if not isfinite(lhs) or not isfinite(rhs):
        raise Error("NR positioning timestamps must be finite")
    var result = lhs - rhs
    if not isfinite(result):
        raise Error("NR positioning time difference is not representable")
    return result


def nr_ul_rtoa_reference_time_seconds(
    sfn0_nominal_time_seconds: Float64,
    system_frame_number: Int,
    subframe_number: Int,
) raises -> Float64:
    """Return ``T0 + (10*n_f+n_sf)*10^-3`` from TS 38.215 clause 5.2.2."""
    if not isfinite(sfn0_nominal_time_seconds):
        raise Error("UL-RTOA SFN-0 nominal time must be finite")
    if system_frame_number < 0 or system_frame_number > 1023:
        raise Error("UL-RTOA system frame number must be in [0,1023]")
    if subframe_number < 0 or subframe_number > 9:
        raise Error("UL-RTOA subframe number must be in [0,9]")
    var result = sfn0_nominal_time_seconds + Float64(
        10 * system_frame_number + subframe_number
    ) * 1.0e-3
    if not isfinite(result):
        raise Error("UL-RTOA reference time is not representable")
    return result


def nr_ul_rtoa_seconds(
    received_subframe_start_seconds: Float64,
    sfn0_nominal_time_seconds: Float64,
    system_frame_number: Int,
    subframe_number: Int,
) raises -> Float64:
    """Return UL-RTOA relative to the clause-5.2.2 reference time.

    The caller supplies the already detected beginning of the subframe that
    contains SRS; RF first-path detection is outside this arithmetic API.
    """
    return _finite_time_difference(
        received_subframe_start_seconds,
        nr_ul_rtoa_reference_time_seconds(
            sfn0_nominal_time_seconds,
            system_frame_number,
            subframe_number,
        ),
    )


def nr_dl_rstd_seconds(
    tp_j_subframe_rx_seconds: Float64,
    tp_i_closest_subframe_rx_seconds: Float64,
) raises -> Float64:
    """Return DL RSTD ``TSubframeRxj-TSubframeRxi`` (clause 5.1.29).

    The second timestamp must already identify the corresponding reference-TP
    subframe closest in time, exactly as required by the measurement
    definition.  Selecting that timestamp is an acquisition responsibility.
    """
    return _finite_time_difference(
        tp_j_subframe_rx_seconds, tp_i_closest_subframe_rx_seconds
    )


def nr_ue_rx_tx_time_difference_seconds(
    ue_rx_seconds: Float64, ue_tx_seconds: Float64
) raises -> Float64:
    """Return ``T_UE-RX-T_UE-TX`` from TS 38.215 clause 5.1.30."""
    return _finite_time_difference(ue_rx_seconds, ue_tx_seconds)


def nr_gnb_rx_tx_time_difference_seconds(
    gnb_rx_seconds: Float64, gnb_tx_closest_seconds: Float64
) raises -> Float64:
    """Return ``T_gNB-RX-T_gNB-TX`` from TS 38.215 clause 5.2.3."""
    return _finite_time_difference(gnb_rx_seconds, gnb_tx_closest_seconds)
