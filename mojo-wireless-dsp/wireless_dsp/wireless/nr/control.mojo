"""Bounded NR DCI/PDCCH coding, modulation, DM-RS, and mapping reference.

The single-codeword profile implements TS 38.212 clause 7.3 CRC24C/RNTI
masking, Polar construction (Nmax=512), and rate matching/recovery together
with TS 38.211 clause 7.3.2 scrambling/QPSK.  It also exposes PDCCH DM-RS and
the non-interleaved CORESET REG/CCE mapping from clause 7.3.2.2.  Interleaved
CCE-to-REG mapping, multiple co-scheduled DCI messages, blind-decoding policy,
and scheduler state are deliberately outside this module.
"""

from std.collections import Span
from std.math import isfinite
from wireless_dsp.core import Complex64
from wireless_dsp.fec.polar import polar_encode, polar_decode_sc
from wireless_dsp.fec.polar_5g import (
    polar_5g_frozen_mask,
    polar_5g_input_interleave,
    polar_5g_input_deinterleave,
    polar_5g_mother_code_length,
    polar_5g_rate_match,
    polar_5g_rate_recover_llrs,
)
from wireless_dsp.modem.crc import crc_bits, crc_check
from wireless_dsp.modem.qam import qam_map
from wireless_dsp.testing.checkpoint import (
    CheckpointMetadata,
    checkpoint_metadata_1d,
)
from .sequences import nr_gold_bits, nr_qpsk_sequence


comptime _CRC24C_POLYNOMIAL = UInt64(0xB2B117)
comptime _DCI_CRC_BITS = 24
comptime _DCI_MAX_INFORMATION_BITS = 164
comptime _PDCCH_BITS_PER_CCE = 108


struct NRPDCCHREGLocation(ImplicitlyCopyable, Equatable):
    """One REG in a non-interleaved CCE-to-REG mapping."""

    var cce_index: Int
    var reg_within_cce: Int
    var reg_index: Int
    var symbol: Int
    var resource_block: Int

    def __init__(
        out self,
        cce_index: Int,
        reg_within_cce: Int,
        reg_index: Int,
        symbol: Int,
        resource_block: Int,
    ):
        self.cce_index = cce_index
        self.reg_within_cce = reg_within_cce
        self.reg_index = reg_index
        self.symbol = symbol
        self.resource_block = resource_block


struct NRPDCCHResourceElement(ImplicitlyCopyable, Equatable):
    """Absolute resource-grid coordinate for one PDCCH data or DM-RS RE."""

    var reg_index: Int
    var symbol: Int
    var resource_block: Int
    var subcarrier: Int

    def __init__(
        out self,
        reg_index: Int,
        symbol: Int,
        resource_block: Int,
        subcarrier: Int,
    ):
        self.reg_index = reg_index
        self.symbol = symbol
        self.resource_block = resource_block
        self.subcarrier = subcarrier


struct NRPDCCHTransmitBlock(Movable):
    """Auditable DCI/PDCCH transmit checkpoints for one aggregation candidate."""

    var payload: List[UInt8]
    var crc_attached_masked: List[UInt8]
    var input_interleaved: List[UInt8]
    var polar_codeword: List[UInt8]
    var rate_matched: List[UInt8]
    var scrambled: List[UInt8]
    var qpsk_symbols: List[Complex64]
    var checkpoint_metadata: List[CheckpointMetadata]

    def __init__(
        out self,
        var payload: List[UInt8],
        var crc_attached_masked: List[UInt8],
        var input_interleaved: List[UInt8],
        var polar_codeword: List[UInt8],
        var rate_matched: List[UInt8],
        var scrambled: List[UInt8],
        var qpsk_symbols: List[Complex64],
        var checkpoint_metadata: List[CheckpointMetadata],
    ):
        self.payload = payload^
        self.crc_attached_masked = crc_attached_masked^
        self.input_interleaved = input_interleaved^
        self.polar_codeword = polar_codeword^
        self.rate_matched = rate_matched^
        self.scrambled = scrambled^
        self.qpsk_symbols = qpsk_symbols^
        self.checkpoint_metadata = checkpoint_metadata^


struct NRPDCCHDecodeResult(Movable):
    """DCI payload, CRC verdict, and soft/hard decoder checkpoints."""

    var physical_descrambled_llrs: List[Float64]
    var rate_recovered_llrs: List[Float64]
    var decoded_masked_information: List[UInt8]
    var crc_unmasked_information: List[UInt8]
    var payload: List[UInt8]
    var crc_ok: Bool
    var checkpoint_metadata: List[CheckpointMetadata]

    def __init__(
        out self,
        var physical_descrambled_llrs: List[Float64],
        var rate_recovered_llrs: List[Float64],
        var decoded_masked_information: List[UInt8],
        var crc_unmasked_information: List[UInt8],
        var payload: List[UInt8],
        crc_ok: Bool,
        var checkpoint_metadata: List[CheckpointMetadata],
    ):
        self.physical_descrambled_llrs = physical_descrambled_llrs^
        self.rate_recovered_llrs = rate_recovered_llrs^
        self.decoded_masked_information = decoded_masked_information^
        self.crc_unmasked_information = crc_unmasked_information^
        self.payload = payload^
        self.crc_ok = crc_ok
        self.checkpoint_metadata = checkpoint_metadata^


def _is_aggregation_level(value: Int) -> Bool:
    return value == 1 or value == 2 or value == 4 or value == 8 or value == 16


def nr_pdcch_rate_matched_bit_count(aggregation_level: Int) raises -> Int:
    """Return E=108*L coded bits for aggregation level L."""
    if not _is_aggregation_level(aggregation_level):
        raise Error("PDCCH aggregation level must be 1, 2, 4, 8, or 16")
    return _PDCCH_BITS_PER_CCE * aggregation_level


def _validate_dci_dimensions(payload_bits: Int, aggregation_level: Int) raises -> Int:
    var e = nr_pdcch_rate_matched_bit_count(aggregation_level)
    if (
        payload_bits < 1
        or payload_bits > _DCI_MAX_INFORMATION_BITS - _DCI_CRC_BITS
        or payload_bits > e - _DCI_CRC_BITS
    ):
        raise Error("DCI payload does not fit the bounded Polar/PDCCH profile")
    return e


def _validate_scrambling_fields(rnti: Int, scrambling_id: Int) raises:
    if rnti < 0 or rnti > 65535 or scrambling_id < 0 or scrambling_id > 65535:
        raise Error("PDCCH RNTI and scrambling identity must be in [0,65535]")


def nr_dci_crc24c(bits: Span[UInt8, ...]) raises -> UInt64:
    """Return TS 38.212 7.3.2 CRC24C, including its 24-one prefix."""
    if len(bits) < 1 or len(bits) > 140:
        raise Error("bounded DCI payload length must be in [1,140]")
    var crc_input = List[UInt8](capacity=24 + len(bits))
    for _ in range(24):
        crc_input.append(1)
    for index in range(len(bits)):
        if bits[index] > 1:
            raise Error("DCI bits must be zero or one")
        crc_input.append(bits[index])
    return crc_bits(
        Span(crc_input), width=24, polynomial=_CRC24C_POLYNOMIAL
    )


def nr_dci_rnti_mask_crc(
    crc_attached: Span[UInt8, ...], rnti: Int,
) raises -> List[UInt8]:
    """XOR the final 16 CRC bits with RNTI; the operation is self-inverse."""
    if (
        len(crc_attached) < _DCI_CRC_BITS + 1
        or len(crc_attached) > _DCI_MAX_INFORMATION_BITS
        or rnti < 0
        or rnti > 65535
    ):
        raise Error("invalid CRC-attached DCI block or RNTI")
    var result = List[UInt8](capacity=len(crc_attached))
    var mask_start = len(crc_attached) - 16
    for index in range(len(crc_attached)):
        var bit = crc_attached[index]
        if bit > 1:
            raise Error("DCI bits must be zero or one")
        if index >= mask_start:
            bit ^= UInt8((rnti >> (15 - (index - mask_start))) & 1)
        result.append(bit)
    return result^


def nr_dci_crc24c_attach_mask(
    payload: Span[UInt8, ...], rnti: Int,
) raises -> List[UInt8]:
    """Attach CRC24C then apply the TS 38.212 7.3.2 RNTI mask."""
    if len(payload) < 1 or len(payload) > 140:
        raise Error("bounded DCI payload length must be in [1,140]")
    var remainder = nr_dci_crc24c(payload)
    var attached = List[UInt8](capacity=len(payload) + 24)
    for index in range(len(payload)):
        attached.append(payload[index])
    for index in range(24):
        attached.append(UInt8((remainder >> UInt64(23 - index)) & 1))
    return nr_dci_rnti_mask_crc(Span(attached), rnti)


def _dci_crc24c_check_unmasked(crc_attached: Span[UInt8, ...]) raises -> Bool:
    if len(crc_attached) < 25 or len(crc_attached) > 164:
        raise Error("invalid CRC-attached DCI length")
    var check_input = List[UInt8](capacity=24 + len(crc_attached))
    for _ in range(24):
        check_input.append(1)
    for index in range(len(crc_attached)):
        if crc_attached[index] > 1:
            raise Error("DCI bits must be zero or one")
        check_input.append(crc_attached[index])
    return crc_check(
        Span(check_input), width=24, polynomial=_CRC24C_POLYNOMIAL
    )


def nr_dci_crc24c_check_masked(
    crc_attached_masked: Span[UInt8, ...], rnti: Int,
) raises -> Bool:
    var unmasked = nr_dci_rnti_mask_crc(crc_attached_masked, rnti)
    return _dci_crc24c_check_unmasked(Span(unmasked))


def nr_pdcch_scrambling_c_init(rnti: Int, scrambling_id: Int) raises -> UInt32:
    """Return ``(RNTI*2^16+n_ID) mod 2^31`` from TS 38.211 7.3.2.3."""
    _validate_scrambling_fields(rnti, scrambling_id)
    var value = (
        (UInt64(rnti) << UInt64(16)) + UInt64(scrambling_id)
    ) % (UInt64(1) << UInt64(31))
    return UInt32(value)


def nr_pdcch_scramble(
    bits: Span[UInt8, ...], rnti: Int, scrambling_id: Int,
) raises -> List[UInt8]:
    """Scramble PDCCH coded bits; applying it twice recovers the input."""
    var sequence = nr_gold_bits(
        nr_pdcch_scrambling_c_init(rnti, scrambling_id), len(bits)
    )
    var result = List[UInt8](capacity=len(bits))
    for index in range(len(bits)):
        if bits[index] > 1:
            raise Error("PDCCH bits must be zero or one")
        result.append(bits[index] ^ sequence[index])
    return result^


def nr_pdcch_descramble_llrs(
    llrs: Span[Float64, ...], rnti: Int, scrambling_id: Int,
) raises -> List[Float64]:
    """Reverse PDCCH scrambling for positive-zero/negative-one LLRs."""
    var sequence = nr_gold_bits(
        nr_pdcch_scrambling_c_init(rnti, scrambling_id), len(llrs)
    )
    var result = List[Float64](capacity=len(llrs))
    for index in range(len(llrs)):
        if not isfinite(llrs[index]):
            raise Error("PDCCH LLRs must be finite")
        result.append(llrs[index] if sequence[index] == 0 else -llrs[index])
    return result^


def nr_pdcch_dmrs_c_init(
    slot: Int,
    symbol: Int,
    scrambling_id: Int,
    *,
    symbols_per_slot: Int = 14,
) raises -> UInt32:
    """Return the PDCCH DM-RS Gold initialization (38.211 7.4.1.3.1)."""
    if (
        slot < 0
        or (symbols_per_slot != 12 and symbols_per_slot != 14)
        or symbol < 0
        or symbol >= symbols_per_slot
        or scrambling_id < 0
        or scrambling_id > 65535
    ):
        raise Error("invalid PDCCH DM-RS initialization fields")
    var modulus = UInt64(1) << UInt64(31)
    var time_term = (
        ((UInt64(slot) % modulus) * UInt64(symbols_per_slot)) % modulus
        + UInt64(symbol + 1)
    ) % modulus
    var identity_term = UInt64(2 * scrambling_id + 1)
    var value = (
        (((UInt64(1) << UInt64(17)) * time_term) % modulus)
        * identity_term
        + UInt64(2 * scrambling_id)
    ) % modulus
    return UInt32(value)


def nr_pdcch_dmrs(
    slot: Int,
    symbol: Int,
    scrambling_id: Int,
    resource_blocks: Int,
    *,
    reference_resource_block: Int = 0,
    symbols_per_slot: Int = 14,
) raises -> List[Complex64]:
    """Generate three DM-RS symbols per RB from an explicit reference point."""
    if (
        resource_blocks < 1
        or resource_blocks > 275
        or reference_resource_block < 0
        or reference_resource_block > 275 - resource_blocks
    ):
        raise Error("invalid PDCCH DM-RS resource-block allocation")
    var preceding = 3 * reference_resource_block
    var wanted = 3 * resource_blocks
    var complete = nr_qpsk_sequence(
        nr_pdcch_dmrs_c_init(
            slot,
            symbol,
            scrambling_id,
            symbols_per_slot=symbols_per_slot,
        ),
        preceding + wanted,
    )
    var result = List[Complex64](capacity=wanted)
    for index in range(wanted):
        result.append(complete[preceding + index])
    return result^


def _validate_coreset_coordinates(
    resource_blocks: Int,
    duration_symbols: Int,
    first_symbol: Int,
    first_resource_block: Int,
) raises -> Int:
    if (
        resource_blocks < 6
        or resource_blocks > 270
        or resource_blocks % 6 != 0
        or duration_symbols < 1
        or duration_symbols > 3
        or first_symbol < 0
        or first_symbol > 14 - duration_symbols
        or first_resource_block < 0
        or first_resource_block > 275 - resource_blocks
    ):
        raise Error("invalid contiguous CORESET coordinates")
    return resource_blocks * duration_symbols // 6


def nr_pdcch_noninterleaved_regs(
    resource_blocks: Int,
    duration_symbols: Int,
    first_cce: Int,
    aggregation_level: Int,
    *,
    first_symbol: Int = 0,
    first_resource_block: Int = 0,
) raises -> List[NRPDCCHREGLocation]:
    """Map a candidate to REGs using non-interleaved, time-first indexing."""
    var cce_count = _validate_coreset_coordinates(
        resource_blocks,
        duration_symbols,
        first_symbol,
        first_resource_block,
    )
    if (
        not _is_aggregation_level(aggregation_level)
        or first_cce < 0
        or first_cce > cce_count - aggregation_level
        or first_cce % aggregation_level != 0
    ):
        raise Error("PDCCH candidate is outside the CORESET")
    var result = List[NRPDCCHREGLocation](capacity=6 * aggregation_level)
    for local_cce in range(aggregation_level):
        var cce = first_cce + local_cce
        for local_reg in range(6):
            var reg = 6 * cce + local_reg
            result.append(NRPDCCHREGLocation(
                cce,
                local_reg,
                reg,
                first_symbol + reg % duration_symbols,
                first_resource_block + reg // duration_symbols,
            ))
    return result^


def nr_pdcch_noninterleaved_data_resource_elements(
    resource_blocks: Int,
    duration_symbols: Int,
    first_cce: Int,
    aggregation_level: Int,
    *,
    first_symbol: Int = 0,
    first_resource_block: Int = 0,
) raises -> List[NRPDCCHResourceElement]:
    """Return candidate data REs in increasing k, then l, mapping order."""
    var regs = nr_pdcch_noninterleaved_regs(
        resource_blocks,
        duration_symbols,
        first_cce,
        aggregation_level,
        first_symbol=first_symbol,
        first_resource_block=first_resource_block,
    )
    var selected_regs = List[Int](
        length=resource_blocks * duration_symbols, fill=-1
    )
    for reg in regs:
        var local_rb = reg.resource_block - first_resource_block
        var local_symbol = reg.symbol - first_symbol
        selected_regs[local_rb * duration_symbols + local_symbol] = reg.reg_index
    var result = List[NRPDCCHResourceElement](capacity=54 * aggregation_level)
    for local_rb in range(resource_blocks):
        for local_subcarrier in range(12):
            if local_subcarrier % 4 != 1:
                for local_symbol in range(duration_symbols):
                    var reg_index = selected_regs[
                        local_rb * duration_symbols + local_symbol
                    ]
                    if reg_index >= 0:
                        var resource_block = first_resource_block + local_rb
                        result.append(NRPDCCHResourceElement(
                            reg_index,
                            first_symbol + local_symbol,
                            resource_block,
                            12 * resource_block + local_subcarrier,
                        ))
    return result^


def nr_pdcch_dmrs_resource_elements(
    resource_blocks: Int,
    duration_symbols: Int,
    *,
    first_symbol: Int = 0,
    first_resource_block: Int = 0,
) raises -> List[NRPDCCHResourceElement]:
    """Return CORESET DM-RS RE coordinates k=4m+1 for every REG."""
    _ = _validate_coreset_coordinates(
        resource_blocks,
        duration_symbols,
        first_symbol,
        first_resource_block,
    )
    var result = List[NRPDCCHResourceElement](
        capacity=3 * resource_blocks * duration_symbols
    )
    for local_symbol in range(duration_symbols):
        for local_rb in range(resource_blocks):
            var reg = local_rb * duration_symbols + local_symbol
            var resource_block = first_resource_block + local_rb
            for local_subcarrier in [1, 5, 9]:
                result.append(NRPDCCHResourceElement(
                    reg,
                    first_symbol + local_symbol,
                    resource_block,
                    12 * resource_block + local_subcarrier,
                ))
    return result^


def _tx_checkpoint_metadata(
    testcase_id: StringSlice,
    payload: Int,
    information: Int,
    mother: Int,
    rate_matched: Int,
    symbols: Int,
) raises -> List[CheckpointMetadata]:
    var result = List[CheckpointMetadata](capacity=7)
    for stage, dtype, length, q_format, layout in [
        ("dci-payload", "uint8", payload, "binary-u1", "bit-per-byte"),
        ("crc-attached-rnti-masked", "uint8", information, "binary-u1", "bit-per-byte"),
        ("polar-input-interleaved", "uint8", information, "binary-u1", "bit-per-byte"),
        ("polar-codeword", "uint8", mother, "binary-u1", "bit-per-byte"),
        ("rate-matched-bits", "uint8", rate_matched, "binary-u1", "bit-per-byte"),
        ("physical-scrambled-bits", "uint8", rate_matched, "binary-u1", "bit-per-byte"),
        ("qpsk-symbols", "complex64", symbols, "floating", "complex-values"),
    ]:
        result.append(checkpoint_metadata_1d(
            testcase_id,
            stage,
            dtype,
            length,
            q_format=q_format,
            layout=layout,
        ))
    return result^


def _rx_checkpoint_metadata(
    testcase_id: StringSlice,
    physical: Int,
    mother: Int,
    information: Int,
    payload: Int,
) raises -> List[CheckpointMetadata]:
    var result = List[CheckpointMetadata](capacity=7)
    for stage, dtype, length, q_format, layout in [
        ("physical-channel-llrs", "float64", physical, "floating", "linear"),
        ("physical-descrambled-llrs", "float64", physical, "floating", "linear"),
        ("polar-rate-recovered-llrs", "float64", mother, "floating", "linear"),
        ("decoded-rnti-masked-information", "uint8", information, "binary-u1", "bit-per-byte"),
        ("crc-unmasked-information", "uint8", information, "binary-u1", "bit-per-byte"),
        ("decoded-dci-payload", "uint8", payload, "binary-u1", "bit-per-byte"),
        ("crc-ok", "bool", 1, "boolean", "scalar"),
    ]:
        result.append(checkpoint_metadata_1d(
            testcase_id,
            stage,
            dtype,
            length,
            q_format=q_format,
            layout=layout,
        ))
    return result^


def nr_pdcch_encode(
    payload: Span[UInt8, ...],
    rnti: Int,
    scrambling_id: Int,
    aggregation_level: Int,
    *,
    physical_scrambling_rnti: Int = -1,
    testcase_id: StringSlice = "nr-pdcch-tx",
) raises -> NRPDCCHTransmitBlock:
    """Encode one DCI payload through QPSK PDCCH symbols.

    ``rnti`` masks the DCI CRC.  By default it also initializes physical
    scrambling, matching a configured UE-specific DM-RS-scrambling-ID
    profile.  Set ``physical_scrambling_rnti=0`` for the common/cell-identity
    case required by 38.211 clause 7.3.2.3.
    """
    var e = _validate_dci_dimensions(len(payload), aggregation_level)
    _validate_scrambling_fields(rnti, scrambling_id)
    if physical_scrambling_rnti < -1 or physical_scrambling_rnti > 65535:
        raise Error("invalid physical PDCCH scrambling RNTI")
    var physical_rnti = (
        rnti if physical_scrambling_rnti == -1 else physical_scrambling_rnti
    )
    var payload_copy = List[UInt8](capacity=len(payload))
    for index in range(len(payload)):
        if payload[index] > 1:
            raise Error("DCI payload bits must be zero or one")
        payload_copy.append(payload[index])
    var masked = nr_dci_crc24c_attach_mask(payload, rnti)
    var ordered = polar_5g_input_interleave(Span(masked))
    var frozen = polar_5g_frozen_mask(len(masked), e, n_max=9)
    var mother = polar_encode(Span(ordered), Span(frozen))
    var expected_n = 1 << polar_5g_mother_code_length(
        len(masked), e, n_max=9
    )
    if len(mother) != expected_n:
        raise Error("DCI Polar mother-code length does not match construction")
    var rate_matched = polar_5g_rate_match(Span(mother), e, len(masked))
    var scrambled = nr_pdcch_scramble(
        Span(rate_matched), physical_rnti, scrambling_id
    )
    var symbols = qam_map(Span(scrambled), 2)
    var metadata = _tx_checkpoint_metadata(
        testcase_id,
        len(payload_copy),
        len(masked),
        len(mother),
        len(rate_matched),
        len(symbols),
    )
    return NRPDCCHTransmitBlock(
        payload_copy^,
        masked^,
        ordered^,
        mother^,
        rate_matched^,
        scrambled^,
        symbols^,
        metadata^,
    )


def nr_pdcch_decode(
    llrs: Span[Float64, ...],
    payload_bits: Int,
    rnti: Int,
    scrambling_id: Int,
    aggregation_level: Int,
    *,
    physical_scrambling_rnti: Int = -1,
    testcase_id: StringSlice = "nr-pdcch-rx",
) raises -> NRPDCCHDecodeResult:
    """Descramble, rate-recover, SC-decode, and CRC-check one DCI candidate."""
    var e = _validate_dci_dimensions(payload_bits, aggregation_level)
    _validate_scrambling_fields(rnti, scrambling_id)
    if physical_scrambling_rnti < -1 or physical_scrambling_rnti > 65535:
        raise Error("invalid physical PDCCH scrambling RNTI")
    var physical_rnti = (
        rnti if physical_scrambling_rnti == -1 else physical_scrambling_rnti
    )
    if len(llrs) != e:
        raise Error("PDCCH decoder LLR count does not match aggregation level")
    var k = payload_bits + _DCI_CRC_BITS
    var descrambled = nr_pdcch_descramble_llrs(
        llrs, physical_rnti, scrambling_id
    )
    var exponent = polar_5g_mother_code_length(k, e, n_max=9)
    var mother_length = 1 << exponent
    var recovered = polar_5g_rate_recover_llrs(
        Span(descrambled), mother_length, k
    )
    var frozen = polar_5g_frozen_mask(k, e, n_max=9)
    var ordered = polar_decode_sc(Span(recovered), Span(frozen))
    var masked = polar_5g_input_deinterleave(Span(ordered))
    var unmasked = nr_dci_rnti_mask_crc(Span(masked), rnti)
    var crc_ok = _dci_crc24c_check_unmasked(Span(unmasked))
    var payload = List[UInt8](capacity=payload_bits)
    for index in range(payload_bits):
        payload.append(unmasked[index])
    var metadata = _rx_checkpoint_metadata(
        testcase_id, len(llrs), len(recovered), len(masked), len(payload)
    )
    return NRPDCCHDecodeResult(
        descrambled^,
        recovered^,
        masked^,
        unmasked^,
        payload^,
        crc_ok,
        metadata^,
    )
