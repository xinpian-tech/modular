"""Protocol configuration primitives for an NR PDSCH reference chain."""

from std.collections import Span
from std.math import isfinite
from wireless_dsp.core import Complex64
from wireless_dsp.modem import crc_bits, crc_append, crc_check
from .sequences import nr_gold_bits, nr_qpsk_sequence


def nr_pdsch_scramble(
    bits: Span[UInt8, ...], rnti: Int, codeword: Int, n_id: Int
) raises -> List[UInt8]:
    """TS 38.211 7.3.1.1 PDSCH scrambling; applying twice descrambles."""
    if rnti < 0 or rnti > 0xFFFF or codeword < 0 or codeword > 1 or n_id < 0 or n_id > 1023:
        raise Error("invalid PDSCH scrambling configuration")
    var c_init = UInt32((rnti << 15) + (codeword << 14) + n_id)
    var sequence = nr_gold_bits(c_init, len(bits))
    var result = List[UInt8](capacity=len(bits))
    for i in range(len(bits)):
        if bits[i] > 1:
            raise Error("bits must be zero or one")
        result.append(bits[i] ^ sequence[i])
    return result^


def nr_pdsch_dmrs(c_init: UInt32, length: Int) raises -> List[Complex64]:
    """TS 38.211 7.4.1.1.1 QPSK base sequence for PDSCH DM-RS."""
    return nr_qpsk_sequence(c_init, length)


def nr_pdsch_descramble_llrs(
    llrs: Span[Float64, ...], rnti: Int, codeword: Int, n_id: Int
) raises -> List[Float64]:
    if rnti < 0 or rnti > 0xFFFF or codeword < 0 or codeword > 1 or n_id < 0 or n_id > 1023:
        raise Error("invalid PDSCH scrambling configuration")
    var c_init = UInt32((rnti << 15) + (codeword << 14) + n_id)
    var sequence = nr_gold_bits(c_init, len(llrs))
    var result = List[Float64](capacity=len(llrs))
    for i in range(len(llrs)):
        if not isfinite(llrs[i]):
            raise Error("PDSCH LLRs must be finite")
        result.append(llrs[i] if sequence[i] == 0 else -llrs[i])
    return result^


def nr_rate_recover_llrs(
    received: Span[Float64, ...], codeword_length: Int, start: Int,
    filler: Span[UInt8, ...],
) raises -> List[Float64]:
    """Undo circular-buffer bit selection and combine repetitions."""
    if codeword_length < 1 or len(filler) != codeword_length:
        raise Error("invalid rate-recovery dimensions")
    for i in range(codeword_length):
        if filler[i] > 1:
            raise Error("rate-recovery filler mask must be binary")
    for i in range(len(received)):
        if not isfinite(received[i]):
            raise Error("rate-recovery LLRs must be finite")
    var result = List[Float64](length=codeword_length, fill=0.0)
    var position = start % codeword_length
    if position < 0:
        position += codeword_length
    for i in range(len(received)):
        var searched = 0
        while filler[position] != 0:
            position = (position + 1) % codeword_length
            searched += 1
            if searched >= codeword_length:
                raise Error("rate-recovery buffer contains only filler")
        result[position] += received[i]
        if not isfinite(result[position]):
            raise Error("rate-recovery LLR accumulation must remain finite")
        position = (position + 1) % codeword_length
    return result^


def nr_transport_crc_width(payload_bits: Int) raises -> Int:
    if payload_bits < 0:
        raise Error("payload length must be non-negative")
    return 24 if payload_bits > 3824 else 16


def nr_transport_crc(bits: Span[UInt8, ...]) raises -> UInt64:
    """TS 38.212 7.2.1: CRC24A above 3824 bits, otherwise CRC16."""
    if len(bits) > 3824:
        return crc_bits(bits, width=24, polynomial=UInt64(0x864CFB))
    return crc_bits(bits, width=16, polynomial=UInt64(0x1021))


def nr_transport_crc_append(bits: Span[UInt8, ...]) raises -> List[UInt8]:
    if len(bits) > 3824:
        return crc_append(bits, width=24, polynomial=UInt64(0x864CFB))
    return crc_append(bits, width=16, polynomial=UInt64(0x1021))


def nr_transport_crc_check(codeword: Span[UInt8, ...], payload_bits: Int) raises -> Bool:
    var width = 24 if payload_bits > 3824 else 16
    if (
        payload_bits < 0
        or payload_bits > Int.MAX - width
        or len(codeword) != payload_bits + width
    ):
        raise Error("NR transport CRC dimensions do not match payload")
    if payload_bits > 3824:
        return crc_check(codeword, width=24, polynomial=UInt64(0x864CFB))
    return crc_check(codeword, width=16, polynomial=UInt64(0x1021))
