"""Bounded Rel-17 SCI-1A and PSCCH CPU reference.

The normative baselines are ETSI TS 138 212 V17.13.0 clauses 8.3 and
7.3.2--7.3.4, ETSI TS 138 211 V17.10.0 clauses 8.3.2 and 8.4.1.3.2,
ETSI TS 138 213 V17.13.0 clause 16.4, and the decoded ``SL-PSCCH-Config``
field ranges in ETSI TS 138 331 V17.17.0.  The SCI-1A serializer includes the
Rel-17 conflict-information receiver flag and its corresponding reduction of
the reserved field.

This module covers one PSCCH code block, normal-CP resource coordinates,
fixed PSCCH Gold initialization ``c_init=1010``, QPSK, and the specified
first-symbol copy.  Frequency/time resource-assignment ranking, RRC/ASN.1,
resource-pool activation, sensing or scheduler policy, PSSCH/PSFCH/HARQ,
channel estimation, RF, and GPU execution are deliberately outside this
bounded scalar CPU reference.
"""

from std.collections import Span
from std.math import isfinite
from wireless_dsp.core import Complex64
from wireless_dsp.fec.polar import polar_decode_sc, polar_encode
from wireless_dsp.fec.polar_5g import (
    polar_5g_frozen_mask,
    polar_5g_input_deinterleave,
    polar_5g_input_interleave,
    polar_5g_mother_code_length,
    polar_5g_rate_match,
    polar_5g_rate_recover_llrs,
)
from wireless_dsp.modem.crc import crc_bits, crc_check
from wireless_dsp.modem.qam import qam_map
from .sequences import nr_gold_bits, nr_qpsk_sequence


comptime _SL_CRC24C_POLYNOMIAL = UInt64(0xB2B117)
comptime _SL_CRC_BITS = 24
comptime _SL_PSCCH_C_INIT = UInt32(1010)
comptime _SL_SUBCARRIERS_PER_RB = 12
comptime _SL_PSCCH_DATA_RE_PER_RB_SYMBOL = 9


def _ceil_log2_positive(value: Int) -> Int:
    var remainder = value - 1
    var result = 0
    while remainder > 0:
        remainder >>= 1
        result += 1
    return result


def _is_pscch_resource_block_count(value: Int) -> Bool:
    return (
        value == 10
        or value == 12
        or value == 15
        or value == 20
        or value == 25
    )


def _is_psfch_period(value: Int) -> Bool:
    return value == 0 or value == 1 or value == 2 or value == 4


def _validate_binary_bits(bits: Span[UInt8, ...], label: StringSlice) raises:
    for index in range(len(bits)):
        if bits[index] > 1:
            raise Error(String(label) + " must contain only zero or one")


def _append_msb_field(
    mut output: List[UInt8], value: Int, width: Int, label: StringSlice,
) raises:
    if width < 0 or width > 30:
        raise Error("SCI-1A field width is outside the bounded profile")
    if value < 0 or (width == 0 and value != 0) or (
        width > 0 and value >= (1 << width)
    ):
        raise Error(String(label) + " does not fit its SCI-1A field")
    for offset in range(width):
        output.append(UInt8((value >> (width - 1 - offset)) & 1))


struct NRSLSCI1AConfig(ImplicitlyCopyable, Equatable):
    """Decoded field-shape configuration for one Rel-17 SCI format 1-A."""

    var number_subchannels: Int
    var max_num_per_reserve: Int
    var reserve_period_entries: Int
    var dmrs_pattern_count: Int
    var additional_mcs_tables: Int
    var psfch_period: Int
    var reserved_bits: Int
    var conflict_information_enabled: Bool

    def __init__(
        out self,
        number_subchannels: Int,
        max_num_per_reserve: Int,
        reserve_period_entries: Int,
        dmrs_pattern_count: Int,
        additional_mcs_tables: Int,
        psfch_period: Int,
        reserved_bits: Int,
        conflict_information_enabled: Bool = False,
    ) raises:
        self.number_subchannels = number_subchannels
        self.max_num_per_reserve = max_num_per_reserve
        self.reserve_period_entries = reserve_period_entries
        self.dmrs_pattern_count = dmrs_pattern_count
        self.additional_mcs_tables = additional_mcs_tables
        self.psfch_period = psfch_period
        self.reserved_bits = reserved_bits
        self.conflict_information_enabled = conflict_information_enabled
        self.validate()

    def validate(self) raises:
        """Revalidate all mutable decoded configuration fields."""
        # A 275-RB pool and the minimum 10-RB subchannel bound N_SL at 27.
        if self.number_subchannels < 1 or self.number_subchannels > 27:
            raise Error("SCI-1A number of subchannels must be in [1,27]")
        if self.max_num_per_reserve != 2 and self.max_num_per_reserve != 3:
            raise Error("sl-MaxNumPerReserve must decode to 2 or 3")
        if self.reserve_period_entries < 0 or self.reserve_period_entries > 16:
            raise Error("reservation-period list size must be in [0,16]")
        if self.dmrs_pattern_count < 1 or self.dmrs_pattern_count > 3:
            raise Error("PSSCH DM-RS pattern count must be in [1,3]")
        if self.additional_mcs_tables < 0 or self.additional_mcs_tables > 2:
            raise Error("additional sidelink MCS-table count must be in [0,2]")
        if not _is_psfch_period(self.psfch_period):
            raise Error("sl-PSFCH-Period must decode to 0, 1, 2, or 4")
        if self.reserved_bits < 2 or self.reserved_bits > 4:
            raise Error("sl-NumReservedBits must be in [2,4]")


struct NRSLSCI1AFields(ImplicitlyCopyable, Equatable):
    """Semantic and encoded values carried by one SCI format 1-A payload."""

    var priority: Int
    var frequency_resource_assignment: Int
    var time_resource_assignment: Int
    var reservation_period_index: Int
    var dmrs_pattern_index: Int
    var second_stage_sci_format: Int
    var beta_offset_indicator: Int
    var two_dmrs_ports: Bool
    var mcs_index: Int
    var additional_mcs_table_indicator: Int
    var psfch_overhead: Bool
    var conflict_information_receiver: Bool

    def __init__(
        out self,
        priority: Int,
        frequency_resource_assignment: Int,
        time_resource_assignment: Int,
        reservation_period_index: Int,
        dmrs_pattern_index: Int,
        second_stage_sci_format: Int,
        beta_offset_indicator: Int,
        two_dmrs_ports: Bool,
        mcs_index: Int,
        additional_mcs_table_indicator: Int = 0,
        psfch_overhead: Bool = False,
        conflict_information_receiver: Bool = False,
    ):
        self.priority = priority
        self.frequency_resource_assignment = frequency_resource_assignment
        self.time_resource_assignment = time_resource_assignment
        self.reservation_period_index = reservation_period_index
        self.dmrs_pattern_index = dmrs_pattern_index
        self.second_stage_sci_format = second_stage_sci_format
        self.beta_offset_indicator = beta_offset_indicator
        self.two_dmrs_ports = two_dmrs_ports
        self.mcs_index = mcs_index
        self.additional_mcs_table_indicator = additional_mcs_table_indicator
        self.psfch_overhead = psfch_overhead
        self.conflict_information_receiver = conflict_information_receiver


struct NRSLPSCCHResourceElement(ImplicitlyCopyable, Equatable):
    """One PSCCH data or DM-RS RE, including first-symbol-copy provenance."""

    var symbol: Int
    var resource_block: Int
    var subcarrier: Int
    var sequence_index: Int
    var is_duplicate: Bool

    def __init__(
        out self,
        symbol: Int,
        resource_block: Int,
        subcarrier: Int,
        sequence_index: Int,
        is_duplicate: Bool,
    ):
        self.symbol = symbol
        self.resource_block = resource_block
        self.subcarrier = subcarrier
        self.sequence_index = sequence_index
        self.is_duplicate = is_duplicate


struct NRSLPSCCHTransmitBlock(Movable):
    """Auditable SCI-1A/PSCCH transmit stages and data-RE coordinates."""

    var payload: List[UInt8]
    var crc_attached: List[UInt8]
    var input_interleaved: List[UInt8]
    var polar_codeword: List[UInt8]
    var rate_matched: List[UInt8]
    var scrambled: List[UInt8]
    var qpsk_symbols: List[Complex64]
    var data_resource_elements: List[NRSLPSCCHResourceElement]

    def __init__(
        out self,
        var payload: List[UInt8],
        var crc_attached: List[UInt8],
        var input_interleaved: List[UInt8],
        var polar_codeword: List[UInt8],
        var rate_matched: List[UInt8],
        var scrambled: List[UInt8],
        var qpsk_symbols: List[Complex64],
        var data_resource_elements: List[NRSLPSCCHResourceElement],
    ):
        self.payload = payload^
        self.crc_attached = crc_attached^
        self.input_interleaved = input_interleaved^
        self.polar_codeword = polar_codeword^
        self.rate_matched = rate_matched^
        self.scrambled = scrambled^
        self.qpsk_symbols = qpsk_symbols^
        self.data_resource_elements = data_resource_elements^


struct NRSLPSCCHDecodeResult(Movable):
    """Decoded SCI-1A payload and its unmasked CRC24C verdict."""

    var payload: List[UInt8]
    var crc_attached: List[UInt8]
    var crc_ok: Bool

    def __init__(
        out self,
        var payload: List[UInt8],
        var crc_attached: List[UInt8],
        crc_ok: Bool,
    ):
        self.payload = payload^
        self.crc_attached = crc_attached^
        self.crc_ok = crc_ok


def nr_sl_sci1a_frequency_assignment_bits(
    number_subchannels: Int, max_num_per_reserve: Int,
) raises -> Int:
    """Return the exact TS 38.212 clause-8.3.1.1 frequency-field width."""
    if number_subchannels < 1 or number_subchannels > 27:
        raise Error("SCI-1A number of subchannels must be in [1,27]")
    var combinations = Int128(number_subchannels) * Int128(
        number_subchannels + 1
    ) // Int128(2)
    if max_num_per_reserve == 3:
        combinations = (
            Int128(number_subchannels)
            * Int128(number_subchannels + 1)
            * Int128(2 * number_subchannels + 1)
            // Int128(6)
        )
    elif max_num_per_reserve != 2:
        raise Error("sl-MaxNumPerReserve must decode to 2 or 3")
    return _ceil_log2_positive(Int(combinations))


def nr_sl_sci1a_payload_bit_count(config: NRSLSCI1AConfig) raises -> Int:
    """Return A for the configured Rel-17 SCI format 1-A payload."""
    config.validate()
    var frequency_bits = nr_sl_sci1a_frequency_assignment_bits(
        config.number_subchannels, config.max_num_per_reserve
    )
    var time_bits = 5 if config.max_num_per_reserve == 2 else 9
    var reservation_bits = (
        0
        if config.reserve_period_entries == 0
        else _ceil_log2_positive(config.reserve_period_entries)
    )
    var dmrs_bits = _ceil_log2_positive(config.dmrs_pattern_count)
    var psfch_bits = (
        1 if config.psfch_period == 2 or config.psfch_period == 4 else 0
    )
    return (
        3
        + frequency_bits
        + time_bits
        + reservation_bits
        + dmrs_bits
        + 2
        + 2
        + 1
        + 5
        + config.additional_mcs_tables
        + psfch_bits
        + config.reserved_bits
    )


def nr_sl_sci1a_pack(
    config: NRSLSCI1AConfig, fields: NRSLSCI1AFields,
) raises -> List[UInt8]:
    """Serialize SCI-1A fields in clause order with each field MSB first."""
    config.validate()
    if fields.priority < 1 or fields.priority > 8:
        raise Error("SCI-1A priority must be in [1,8]")
    if fields.second_stage_sci_format < 0 or (
        fields.second_stage_sci_format > 2
    ):
        raise Error("SCI-1A second-stage format 3 is reserved")
    if fields.beta_offset_indicator < 0 or fields.beta_offset_indicator > 3:
        raise Error("SCI-1A beta-offset indicator must be in [0,3]")
    if fields.mcs_index < 0 or fields.mcs_index > 31:
        raise Error("SCI-1A MCS index must be in [0,31]")
    if not config.conflict_information_enabled and (
        fields.conflict_information_receiver
    ):
        raise Error("conflict-information flag is absent from this SCI-1A")

    var output = List[UInt8](capacity=nr_sl_sci1a_payload_bit_count(config))
    _append_msb_field(output, fields.priority - 1, 3, "priority")
    _append_msb_field(
        output,
        fields.frequency_resource_assignment,
        nr_sl_sci1a_frequency_assignment_bits(
            config.number_subchannels, config.max_num_per_reserve
        ),
        "frequency resource assignment",
    )
    _append_msb_field(
        output,
        fields.time_resource_assignment,
        5 if config.max_num_per_reserve == 2 else 9,
        "time resource assignment",
    )
    _append_msb_field(
        output,
        fields.reservation_period_index,
        0
        if config.reserve_period_entries == 0
        else _ceil_log2_positive(config.reserve_period_entries),
        "resource reservation period",
    )
    _append_msb_field(
        output,
        fields.dmrs_pattern_index,
        _ceil_log2_positive(config.dmrs_pattern_count),
        "DM-RS pattern",
    )
    _append_msb_field(
        output, fields.second_stage_sci_format, 2, "second-stage SCI format"
    )
    _append_msb_field(
        output, fields.beta_offset_indicator, 2, "beta-offset indicator"
    )
    _append_msb_field(
        output, 1 if fields.two_dmrs_ports else 0, 1, "number of DM-RS ports"
    )
    _append_msb_field(output, fields.mcs_index, 5, "MCS")
    _append_msb_field(
        output,
        fields.additional_mcs_table_indicator,
        config.additional_mcs_tables,
        "additional MCS-table indicator",
    )
    var psfch_bits = (
        1 if config.psfch_period == 2 or config.psfch_period == 4 else 0
    )
    _append_msb_field(
        output,
        1 if fields.psfch_overhead else 0,
        psfch_bits,
        "PSFCH overhead",
    )
    var ordinary_reserved_bits = config.reserved_bits
    if config.conflict_information_enabled:
        ordinary_reserved_bits -= 1
    for _ in range(ordinary_reserved_bits):
        output.append(0)
    if config.conflict_information_enabled:
        output.append(
            UInt8(1) if fields.conflict_information_receiver else UInt8(0)
        )
    if len(output) != nr_sl_sci1a_payload_bit_count(config):
        raise Error("SCI-1A serializer produced an inconsistent length")
    return output^


def nr_sl_sci_crc24c(payload: Span[UInt8, ...]) raises -> UInt64:
    """Return SCI CRC24C after the clause-7.3.2 24-one prefix."""
    if len(payload) < 1 or len(payload) > 140:
        raise Error("bounded SCI-1A payload length must be in [1,140]")
    var crc_input = List[UInt8](capacity=_SL_CRC_BITS + len(payload))
    for _ in range(_SL_CRC_BITS):
        crc_input.append(1)
    for index in range(len(payload)):
        if payload[index] > 1:
            raise Error("SCI-1A payload bits must be zero or one")
        crc_input.append(payload[index])
    return crc_bits(
        Span(crc_input), width=_SL_CRC_BITS,
        polynomial=_SL_CRC24C_POLYNOMIAL,
    )


def nr_sl_sci_crc24c_attach(payload: Span[UInt8, ...]) raises -> List[UInt8]:
    """Attach the SCI CRC24C without the DCI RNTI-scrambling step."""
    var remainder = nr_sl_sci_crc24c(payload)
    var result = List[UInt8](capacity=len(payload) + _SL_CRC_BITS)
    for index in range(len(payload)):
        result.append(payload[index])
    for index in range(_SL_CRC_BITS):
        result.append(
            UInt8((remainder >> UInt64(_SL_CRC_BITS - 1 - index)) & 1)
        )
    return result^


def nr_sl_sci_crc24c_check(crc_attached: Span[UInt8, ...]) raises -> Bool:
    """Check an SCI CRC block using the mandatory 24-one prefix."""
    if len(crc_attached) < _SL_CRC_BITS + 1 or len(crc_attached) > 164:
        raise Error("CRC-attached SCI-1A length must be in [25,164]")
    var check_input = List[UInt8](capacity=_SL_CRC_BITS + len(crc_attached))
    for _ in range(_SL_CRC_BITS):
        check_input.append(1)
    for index in range(len(crc_attached)):
        if crc_attached[index] > 1:
            raise Error("CRC-attached SCI-1A bits must be zero or one")
        check_input.append(crc_attached[index])
    return crc_check(
        Span(check_input), width=_SL_CRC_BITS,
        polynomial=_SL_CRC24C_POLYNOMIAL,
    )


def nr_sl_pscch_rate_matched_bit_count(
    resource_blocks: Int, duration_symbols: Int,
) raises -> Int:
    """Return E=2*9*N_RB*N_symb for an allowed PSCCH allocation."""
    if not _is_pscch_resource_block_count(resource_blocks):
        raise Error("PSCCH PRBs must be 10, 12, 15, 20, or 25")
    if duration_symbols != 2 and duration_symbols != 3:
        raise Error("PSCCH duration must be two or three symbols")
    return (
        2
        * _SL_PSCCH_DATA_RE_PER_RB_SYMBOL
        * resource_blocks
        * duration_symbols
    )


def nr_sl_pscch_scramble(bits: Span[UInt8, ...]) raises -> List[UInt8]:
    """Apply the TS 38.211 PSCCH Gold sequence with fixed c_init=1010."""
    _validate_binary_bits(bits, "PSCCH bits")
    var sequence = nr_gold_bits(_SL_PSCCH_C_INIT, len(bits))
    var result = List[UInt8](capacity=len(bits))
    for index in range(len(bits)):
        result.append(bits[index] ^ sequence[index])
    return result^


def nr_sl_pscch_descramble_llrs(
    llrs: Span[Float64, ...],
) raises -> List[Float64]:
    """Reverse fixed PSCCH scrambling for positive-zero/negative-one LLRs."""
    var sequence = nr_gold_bits(_SL_PSCCH_C_INIT, len(llrs))
    var result = List[Float64](capacity=len(llrs))
    for index in range(len(llrs)):
        if not isfinite(llrs[index]):
            raise Error("PSCCH LLRs must be finite")
        result.append(llrs[index] if sequence[index] == 0 else -llrs[index])
    return result^


def nr_sl_pscch_dmrs_c_init(
    slot_number: Int,
    symbol: Int,
    scrambling_id: Int,
    *,
    numerology: Int = 0,
) raises -> UInt32:
    """Return the TS 38.211 clause-8.4.1.3.1 PSCCH DM-RS c_init."""
    if numerology < 0 or numerology > 3:
        raise Error("bounded sidelink numerology must be in [0,3]")
    if slot_number < 0 or slot_number >= 10 * (1 << numerology):
        raise Error("sidelink slot number must be within its radio frame")
    if symbol < 0 or symbol >= 14:
        raise Error("PSCCH DM-RS symbol must be in [0,13]")
    if scrambling_id < 0 or scrambling_id > 65535:
        raise Error("sl-DMRS-ScrambleID must be in [0,65535]")
    var modulus = UInt64(1) << UInt64(31)
    var time_term = UInt64(14 * slot_number + symbol + 1)
    var identity_term = UInt64(2 * scrambling_id + 1)
    var value = (
        (((UInt64(1) << UInt64(17)) * time_term) % modulus)
        * identity_term
        + UInt64(2 * scrambling_id)
    ) % modulus
    return UInt32(value)


def nr_sl_pscch_dmrs(
    slot_number: Int,
    symbol: Int,
    scrambling_id: Int,
    resource_blocks: Int,
    *,
    numerology: Int = 0,
    first_resource_block: Int = 0,
) raises -> List[Complex64]:
    """Generate three PSCCH DM-RS symbols per allocated RB from CRB zero."""
    _validate_pscch_coordinates(
        resource_blocks, 2, 0, first_resource_block
    )
    var preceding = 3 * first_resource_block
    var wanted = 3 * resource_blocks
    var complete = nr_qpsk_sequence(
        nr_sl_pscch_dmrs_c_init(
            slot_number,
            symbol,
            scrambling_id,
            numerology=numerology,
        ),
        preceding + wanted,
    )
    var result = List[Complex64](capacity=wanted)
    for index in range(wanted):
        result.append(complete[preceding + index])
    return result^


def _validate_pscch_coordinates(
    resource_blocks: Int,
    duration_symbols: Int,
    first_available_symbol: Int,
    first_resource_block: Int,
) raises:
    _ = nr_sl_pscch_rate_matched_bit_count(
        resource_blocks, duration_symbols
    )
    if first_available_symbol < 0 or (
        first_available_symbol > 13 - duration_symbols
    ):
        raise Error("PSCCH allocation and copied symbol must fit a 14-symbol slot")
    if first_resource_block < 0 or (
        first_resource_block > 275 - resource_blocks
    ):
        raise Error("PSCCH allocation must fit the 275-PRB resource-grid bound")


def nr_sl_pscch_data_resource_elements(
    resource_blocks: Int,
    duration_symbols: Int,
    *,
    first_available_symbol: Int = 0,
    first_resource_block: Int = 0,
) raises -> List[NRSLPSCCHResourceElement]:
    """Map PSCCH data REs in k-then-l order plus the first-symbol copy."""
    _validate_pscch_coordinates(
        resource_blocks,
        duration_symbols,
        first_available_symbol,
        first_resource_block,
    )
    var primary_count = (
        _SL_PSCCH_DATA_RE_PER_RB_SYMBOL
        * resource_blocks
        * duration_symbols
    )
    var copied_count = _SL_PSCCH_DATA_RE_PER_RB_SYMBOL * resource_blocks
    var result = List[NRSLPSCCHResourceElement](
        capacity=primary_count + copied_count
    )
    var sequence_index = 0
    for relative_symbol in range(duration_symbols):
        var symbol = first_available_symbol + 1 + relative_symbol
        for rb_offset in range(resource_blocks):
            for subcarrier in range(_SL_SUBCARRIERS_PER_RB):
                if subcarrier == 1 or subcarrier == 5 or subcarrier == 9:
                    continue
                result.append(NRSLPSCCHResourceElement(
                    symbol,
                    first_resource_block + rb_offset,
                    subcarrier,
                    sequence_index,
                    False,
                ))
                sequence_index += 1
    for rb_offset in range(resource_blocks):
        for subcarrier in range(_SL_SUBCARRIERS_PER_RB):
            if subcarrier == 1 or subcarrier == 5 or subcarrier == 9:
                continue
            var first_symbol_index = (
                rb_offset * _SL_PSCCH_DATA_RE_PER_RB_SYMBOL
                + subcarrier
                - (1 if subcarrier > 1 else 0)
                - (1 if subcarrier > 5 else 0)
                - (1 if subcarrier > 9 else 0)
            )
            result.append(NRSLPSCCHResourceElement(
                first_available_symbol,
                first_resource_block + rb_offset,
                subcarrier,
                first_symbol_index,
                True,
            ))
    return result^


def nr_sl_pscch_dmrs_resource_elements(
    resource_blocks: Int,
    duration_symbols: Int,
    *,
    first_available_symbol: Int = 0,
    first_resource_block: Int = 0,
) raises -> List[NRSLPSCCHResourceElement]:
    """Map PSCCH DM-RS on k'=1+4m plus its first-symbol copy."""
    _validate_pscch_coordinates(
        resource_blocks,
        duration_symbols,
        first_available_symbol,
        first_resource_block,
    )
    var primary_count = 3 * resource_blocks * duration_symbols
    var copied_count = 3 * resource_blocks
    var result = List[NRSLPSCCHResourceElement](
        capacity=primary_count + copied_count
    )
    for relative_symbol in range(duration_symbols):
        var symbol = first_available_symbol + 1 + relative_symbol
        for rb_offset in range(resource_blocks):
            for dmrs_index in range(3):
                result.append(NRSLPSCCHResourceElement(
                    symbol,
                    first_resource_block + rb_offset,
                    1 + 4 * dmrs_index,
                    3 * (first_resource_block + rb_offset) + dmrs_index,
                    False,
                ))
    for rb_offset in range(resource_blocks):
        for dmrs_index in range(3):
            result.append(NRSLPSCCHResourceElement(
                first_available_symbol,
                first_resource_block + rb_offset,
                1 + 4 * dmrs_index,
                3 * (first_resource_block + rb_offset) + dmrs_index,
                True,
            ))
    return result^


def nr_sl_pscch_encode(
    payload: Span[UInt8, ...],
    resource_blocks: Int,
    duration_symbols: Int,
    *,
    first_available_symbol: Int = 0,
    first_resource_block: Int = 0,
) raises -> NRSLPSCCHTransmitBlock:
    """Encode one SCI-1A payload through the bounded PSCCH physical chain."""
    var e = nr_sl_pscch_rate_matched_bit_count(
        resource_blocks, duration_symbols
    )
    _validate_pscch_coordinates(
        resource_blocks,
        duration_symbols,
        first_available_symbol,
        first_resource_block,
    )
    if len(payload) < 1 or len(payload) > 140:
        raise Error("bounded SCI-1A payload length must be in [1,140]")
    var payload_copy = List[UInt8](capacity=len(payload))
    for index in range(len(payload)):
        if payload[index] > 1:
            raise Error("SCI-1A payload bits must be zero or one")
        payload_copy.append(payload[index])
    var attached = nr_sl_sci_crc24c_attach(payload)
    var ordered = polar_5g_input_interleave(Span(attached))
    var frozen = polar_5g_frozen_mask(len(attached), e, n_max=9)
    var mother = polar_encode(Span(ordered), Span(frozen))
    var expected_n = 1 << polar_5g_mother_code_length(
        len(attached), e, n_max=9
    )
    if len(mother) != expected_n:
        raise Error("SCI-1A Polar mother-code length is inconsistent")
    var rate_matched = polar_5g_rate_match(Span(mother), e, len(attached))
    var scrambled = nr_sl_pscch_scramble(Span(rate_matched))
    var symbols = qam_map(Span(scrambled), 2)
    var mapping = nr_sl_pscch_data_resource_elements(
        resource_blocks,
        duration_symbols,
        first_available_symbol=first_available_symbol,
        first_resource_block=first_resource_block,
    )
    if len(symbols) != e // 2:
        raise Error("PSCCH QPSK symbol count does not fill primary data REs")
    return NRSLPSCCHTransmitBlock(
        payload_copy^,
        attached^,
        ordered^,
        mother^,
        rate_matched^,
        scrambled^,
        symbols^,
        mapping^,
    )


def nr_sl_pscch_decode(
    llrs: Span[Float64, ...],
    payload_bits: Int,
    resource_blocks: Int,
    duration_symbols: Int,
) raises -> NRSLPSCCHDecodeResult:
    """Descramble, SC-decode, and CRC-check one primary PSCCH observation."""
    var e = nr_sl_pscch_rate_matched_bit_count(
        resource_blocks, duration_symbols
    )
    if payload_bits < 1 or payload_bits > 140 or len(llrs) != e:
        raise Error("PSCCH decoder dimensions do not match the bounded profile")
    var k = payload_bits + _SL_CRC_BITS
    var descrambled = nr_sl_pscch_descramble_llrs(llrs)
    var mother_length = 1 << polar_5g_mother_code_length(k, e, n_max=9)
    var recovered = polar_5g_rate_recover_llrs(
        Span(descrambled), mother_length, k
    )
    var frozen = polar_5g_frozen_mask(k, e, n_max=9)
    var ordered = polar_decode_sc(Span(recovered), Span(frozen))
    var attached = polar_5g_input_deinterleave(Span(ordered))
    var payload = List[UInt8](capacity=payload_bits)
    for index in range(payload_bits):
        payload.append(attached[index])
    var crc_ok = nr_sl_sci_crc24c_check(Span(attached))
    return NRSLPSCCHDecodeResult(payload^, attached^, crc_ok)
