"""NR UCI channel coding for PUCCH formats 2, 3, and 4.

This readable reference implements TS 38.212 clauses 5.2.1, 5.3.1, 5.3.3,
5.4.1, 5.4.3, and 6.3.1.2--6.3.1.5.  Payloads of 3--11 bits use the
normative (32, K) small-block code.  Payloads of 12--1706 bits use CRC6/CRC11,
optional two-block segmentation, Polar coding (including the three dynamic
parity-check bits for K=18--25), coded-bit interleaving, and rate matching.

HARQ/SR/CSI semantic field generation and two-part CSI rate allocation remain
configuration-layer concerns; this module operates on the resulting UCI bit
sequence and an explicitly supplied physical-channel capacity E.
"""

from std.collections import Span
from wireless_dsp.fec import (
    nr_small_block_encode,
    nr_small_block_rate_match,
    nr_small_block_decode_ml,
    polar_5g_encode,
    polar_5g_decode_sc,
    polar_5g_encode_with_parity,
    polar_5g_decode_sc_with_parity,
)
from wireless_dsp.modem import crc_append, crc_check


comptime NR_UCI_SCHEME_SMALL_BLOCK = 1
comptime NR_UCI_SCHEME_POLAR = 2
comptime _MAX_UCI_CODE_BLOCK_BITS = 8192


struct NRUCIEncodeResult(Movable):
    var bits: List[UInt8]
    var scheme: Int
    var code_blocks: Int
    var crc_bits: Int
    var parity_check_bits: Int
    var padded_payload_bits: Int

    def __init__(
        out self,
        var bits: List[UInt8],
        scheme: Int,
        code_blocks: Int,
        crc_bits: Int,
        parity_check_bits: Int,
        padded_payload_bits: Int,
    ):
        self.bits = bits^
        self.scheme = scheme
        self.code_blocks = code_blocks
        self.crc_bits = crc_bits
        self.parity_check_bits = parity_check_bits
        self.padded_payload_bits = padded_payload_bits


struct NRUCIDecodeResult(Movable):
    var bits: List[UInt8]
    var crc_ok: Bool
    var parity_ok: Bool
    var scheme: Int
    var code_blocks: Int

    def __init__(
        out self,
        var bits: List[UInt8],
        crc_ok: Bool,
        parity_ok: Bool,
        scheme: Int,
        code_blocks: Int,
    ):
        self.bits = bits^
        self.crc_ok = crc_ok
        self.parity_ok = parity_ok
        self.scheme = scheme
        self.code_blocks = code_blocks


def nr_uci_crc_length(payload_length: Int) raises -> Int:
    if payload_length < 3 or payload_length > 1706:
        raise Error("PUCCH UCI payload length must be in [3,1706]")
    if payload_length <= 11:
        return 0
    if payload_length <= 19:
        return 6
    return 11


def nr_uci_code_block_count(payload_length: Int, output_length: Int) raises -> Int:
    _ = nr_uci_crc_length(payload_length)
    if output_length < 1:
        raise Error("PUCCH UCI output length must be positive")
    if payload_length <= 11:
        if output_length > _MAX_UCI_CODE_BLOCK_BITS:
            raise Error("PUCCH UCI output exceeds one code-block capacity")
        return 1
    var code_blocks = (
        2
        if (payload_length >= 360 and output_length >= 1088)
        or payload_length >= 1013
        else 1
    )
    if output_length > _MAX_UCI_CODE_BLOCK_BITS * code_blocks:
        raise Error("PUCCH UCI output exceeds code-block capacity")
    return code_blocks


def _checked_uci_capacity_product(
    bits_per_prb_symbol: Int,
    resource_blocks: Int,
    uci_symbols: Int,
) raises -> Int:
    if resource_blocks > Int.MAX // bits_per_prb_symbol:
        raise Error("PUCCH UCI capacity overflows Int")
    var bits_per_symbol = bits_per_prb_symbol * resource_blocks
    if uci_symbols > Int.MAX // bits_per_symbol:
        raise Error("PUCCH UCI capacity overflows Int")
    return bits_per_symbol * uci_symbols


def nr_pucch_uci_capacity(
    pucch_format: Int,
    resource_blocks: Int,
    uci_symbols: Int,
    *,
    spreading_factor: Int = 1,
    pi_over_2_bpsk: Bool = False,
) raises -> Int:
    """Return E_tot from TS 38.212 Table 6.3.1.4-1.

    ``uci_symbols`` excludes whole DM-RS symbols.  Format 2 has four DM-RS
    resource elements per PRB and therefore eight data REs; formats 3/4 use
    twelve data REs in each UCI-bearing symbol.
    """
    if resource_blocks < 1 or uci_symbols < 1:
        raise Error("PUCCH UCI allocation must be non-empty")
    if spreading_factor != 1 and spreading_factor != 2 and spreading_factor != 4:
        raise Error("PUCCH spreading factor must be 1, 2, or 4")
    if pucch_format == 2:
        if pi_over_2_bpsk:
            raise Error("PUCCH format 2 supports QPSK only")
        return _checked_uci_capacity_product(
            16 // spreading_factor, resource_blocks, uci_symbols
        )
    if pucch_format == 3:
        var bits_per_prb_symbol = 12 if pi_over_2_bpsk else 24
        return _checked_uci_capacity_product(
            bits_per_prb_symbol // spreading_factor,
            resource_blocks,
            uci_symbols,
        )
    if pucch_format == 4:
        if resource_blocks != 1 or (
            spreading_factor != 2 and spreading_factor != 4
        ):
            raise Error("PUCCH format 4 uses one PRB and spreading factor 2/4")
        var bits_per_prb_symbol = 12 if pi_over_2_bpsk else 24
        return _checked_uci_capacity_product(
            bits_per_prb_symbol // spreading_factor, 1, uci_symbols
        )
    raise Error("UCI channel coding applies to PUCCH formats 2, 3, and 4")


def _uci_crc_polynomial(crc_length: Int) raises -> UInt64:
    if crc_length == 6:
        return UInt64(0x21)  # D^6 + D^5 + 1
    if crc_length == 11:
        return UInt64(0x621)  # D^11 + D^10 + D^9 + D^5 + 1
    raise Error("unsupported UCI CRC length")


def _validate_uci_bits(bits: Span[UInt8, ...]) raises:
    for index in range(len(bits)):
        if bits[index] > 1:
            raise Error("UCI input must contain only zero and one")


def _uci_parity_count(information_length: Int) -> Int:
    return 3 if information_length >= 18 and information_length <= 25 else 0


def _uci_row_weight_parity(
    information_length: Int, output_length: Int
) -> Int:
    return (
        1
        if _uci_parity_count(information_length) == 3
        and output_length - information_length + 3 > 192
        else 0
    )


def nr_uci_encode(
    payload: Span[UInt8, ...], output_length: Int
) raises -> NRUCIEncodeResult:
    """Encode and rate-match one PUCCH UCI bit sequence to exactly E bits."""
    var crc_length = nr_uci_crc_length(len(payload))
    _validate_uci_bits(payload)
    var code_blocks = nr_uci_code_block_count(len(payload), output_length)
    if crc_length == 0:
        var mother = nr_small_block_encode(payload)
        var matched = nr_small_block_rate_match(Span(mother), output_length)
        return NRUCIEncodeResult(
            matched^, NR_UCI_SCHEME_SMALL_BLOCK, 1, 0, 0, 0
        )

    if output_length % code_blocks != 0:
        raise Error("Polar UCI E must be divisible by its code-block count")
    var block_output_length = output_length // code_blocks
    var padded_length = (
        (len(payload) + code_blocks - 1) // code_blocks * code_blocks
    )
    var padding = padded_length - len(payload)
    var padded = List[UInt8](length=padded_length, fill=UInt8(0))
    for index in range(len(payload)):
        padded[padding + index] = payload[index]
    var block_payload_length = padded_length // code_blocks
    var result = List[UInt8](capacity=output_length)
    var parity_count = 0
    for block_index in range(code_blocks):
        var block_payload = List[UInt8](capacity=block_payload_length)
        var start = block_index * block_payload_length
        for index in range(block_payload_length):
            block_payload.append(padded[start + index])
        var information = crc_append(
            Span(block_payload), width=crc_length,
            polynomial=_uci_crc_polynomial(crc_length),
        )
        var n_pc = _uci_parity_count(len(information))
        var n_pc_wm = _uci_row_weight_parity(
            len(information), block_output_length
        )
        parity_count = n_pc
        var coded: List[UInt8]
        if n_pc == 0:
            coded = polar_5g_encode(
                Span(information), block_output_length, n_max=10,
                bit_interleave=True,
            )
        else:
            coded = polar_5g_encode_with_parity(
                Span(information), block_output_length, n_pc=n_pc,
                n_pc_wm=n_pc_wm, n_max=10, bit_interleave=True,
            )
        for bit in coded:
            result.append(bit)
    if len(result) != output_length:
        raise Error("UCI encoder produced wrong output length")
    return NRUCIEncodeResult(
        result^, NR_UCI_SCHEME_POLAR, code_blocks, crc_length,
        parity_count, padding,
    )


def nr_uci_decode(
    llrs: Span[Float64, ...], payload_length: Int
) raises -> NRUCIDecodeResult:
    """Soft-decode a PUCCH UCI sequence with CRC and PC status."""
    var crc_length = nr_uci_crc_length(payload_length)
    var code_blocks = nr_uci_code_block_count(payload_length, len(llrs))
    if crc_length == 0:
        var decoded = nr_small_block_decode_ml(llrs, payload_length)
        var payload = List[UInt8](capacity=len(decoded.bits))
        for bit in decoded.bits:
            payload.append(bit)
        return NRUCIDecodeResult(
            payload^, True, True, NR_UCI_SCHEME_SMALL_BLOCK, 1
        )
    if len(llrs) % code_blocks != 0:
        raise Error("Polar UCI E must be divisible by its code-block count")
    var block_output_length = len(llrs) // code_blocks
    var padded_length = (
        (payload_length + code_blocks - 1) // code_blocks * code_blocks
    )
    var padding = padded_length - payload_length
    var block_payload_length = padded_length // code_blocks
    var padded = List[UInt8](capacity=padded_length)
    var all_crc_ok = True
    var all_parity_ok = True
    for block_index in range(code_blocks):
        var block_llrs = List[Float64](capacity=block_output_length)
        var start = block_index * block_output_length
        for index in range(block_output_length):
            block_llrs.append(llrs[start + index])
        var information_length = block_payload_length + crc_length
        var n_pc = _uci_parity_count(information_length)
        var n_pc_wm = _uci_row_weight_parity(
            information_length, block_output_length
        )
        var information = List[UInt8]()
        if n_pc == 0:
            information = polar_5g_decode_sc(
                Span(block_llrs), information_length, n_max=10,
                bit_interleave=True,
            )
        else:
            var decoded = polar_5g_decode_sc_with_parity(
                Span(block_llrs), information_length, n_pc=n_pc,
                n_pc_wm=n_pc_wm, n_max=10, bit_interleave=True,
            )
            all_parity_ok = all_parity_ok and decoded.parity_ok
            for bit in decoded.bits:
                information.append(bit)
        all_crc_ok = all_crc_ok and crc_check(
            Span(information), width=crc_length,
            polynomial=_uci_crc_polynomial(crc_length),
        )
        for index in range(block_payload_length):
            padded.append(information[index])
    var payload = List[UInt8](capacity=payload_length)
    for index in range(payload_length):
        payload.append(padded[padding + index])
    return NRUCIDecodeResult(
        payload^, all_crc_ok, all_parity_ok, NR_UCI_SCHEME_POLAR,
        code_blocks,
    )
