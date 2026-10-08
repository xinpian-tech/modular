"""NR PUCCH low-PAPR sequences, scrambling, modulation, and spreading."""

from std.collections import Span
from std.math import cos, isfinite, sin, sqrt
from wireless_dsp.core import Complex64
from wireless_dsp.modem import qam_map
from .sequences import nr_gold_bits

comptime _PI = 3.1415926535897932384626433832795
comptime _TWO_PI = 6.283185307179586476925286766559

comptime PUCCH_GROUP_HOPPING_NEITHER = 0
comptime PUCCH_GROUP_HOPPING_ENABLE = 1
comptime PUCCH_SEQUENCE_HOPPING_ENABLE = 2


struct NRPucchSequenceHopping(Movable):
    """PUCCH low-PAPR sequence group ``u`` and sequence number ``v``."""

    var group: Int
    var sequence_number: Int

    def __init__(out self, group: Int, sequence_number: Int):
        self.group = group
        self.sequence_number = sequence_number


def _phi_12() -> List[Int]:
    """TS 38.211 Table 5.2.2.2-2, flattened by sequence group u."""
    return [
        -3,1,-3,-3,-3,3,-3,-1,1,1,1,-3,
        -3,3,1,-3,1,3,-1,-1,1,3,3,3,
        -3,3,3,1,-3,3,-1,1,3,-3,3,-3,
        -3,-3,-1,3,3,3,-3,3,-3,1,-1,-3,
        -3,-1,-1,1,3,1,1,-1,1,-1,-3,1,
        -3,-3,3,1,-3,-3,-3,-1,3,-1,1,3,
        1,-1,3,-1,-1,-1,-3,-1,1,1,1,-3,
        -1,-3,3,-1,-3,-3,-3,-1,1,-1,1,-3,
        -3,-1,3,1,-3,-1,-3,3,1,3,3,1,
        -3,-1,-1,-3,-3,-1,-3,3,1,3,-1,-3,
        -3,3,-3,3,3,-3,-1,-1,3,3,1,-3,
        -3,-1,-3,-1,-1,-3,3,3,-1,-1,1,-3,
        -3,-1,3,-3,-3,-1,-3,1,-1,-3,3,3,
        -3,1,-1,-1,3,3,-3,-1,-1,-3,-1,-3,
        1,3,-3,1,3,3,3,1,-1,1,-1,3,
        -3,1,3,-1,-1,-3,-3,-1,-1,3,1,-3,
        -1,-1,-1,-1,1,-3,-1,3,3,-1,-3,1,
        -1,1,1,-1,1,3,3,-1,-1,-3,1,-3,
        -3,1,3,3,-1,-1,-3,3,3,-3,3,-3,
        -3,-3,3,-3,-1,3,3,3,-1,-3,1,-3,
        3,1,3,1,3,-3,-1,1,3,1,-1,-3,
        -3,3,1,3,-3,1,1,1,1,3,-3,3,
        -3,3,3,3,-1,-3,-3,-1,-3,1,3,-3,
        3,-1,-3,3,-3,-1,3,3,3,-3,-1,-3,
        -3,-1,1,-3,1,3,3,3,-1,-3,3,3,
        -3,3,1,-1,3,3,-3,1,-1,1,-1,1,
        -1,1,3,-3,1,-1,1,-1,-1,-3,1,-1,
        -3,-3,3,3,3,-3,-1,1,-3,3,1,-3,
        1,-1,3,1,1,-1,-1,-1,1,3,-3,1,
        -3,3,-3,3,-3,-3,3,-1,-1,1,3,-3,
    ]


def nr_pucch_group_neither(n_id: Int) raises -> Int:
    """Sequence group u when pucch-GroupHopping is configured as neither."""
    if n_id < 0 or n_id > 1023:
        raise Error("PUCCH hopping identity must be in [0,1023]")
    return n_id % 30


def nr_pucch_group_sequence_hopping(
    slot_in_frame: Int,
    numerology: Int,
    frequency_hop: Int,
    n_id: Int,
    mode: Int,
) raises -> NRPucchSequenceHopping:
    """TS 38.211 6.3.2.2.1 group/sequence hopping for PUCCH.

    ``mode`` is one of ``PUCCH_GROUP_HOPPING_NEITHER``,
    ``PUCCH_GROUP_HOPPING_ENABLE``, or
    ``PUCCH_SEQUENCE_HOPPING_ENABLE`` (the RRC value ``disable``).
    ``frequency_hop`` is zero without intra-slot hopping and selects the
    first/second hop when it is enabled.
    """
    if numerology < 0 or numerology > 5:
        raise Error("PUCCH numerology must be in [0,5]")
    var slots_per_frame = 10 * (1 << numerology)
    if slot_in_frame < 0 or slot_in_frame >= slots_per_frame:
        raise Error("PUCCH slot must be within the radio frame")
    if frequency_hop < 0 or frequency_hop > 1 or n_id < 0 or n_id > 1023:
        raise Error("invalid PUCCH hopping configuration")
    if (
        mode != PUCCH_GROUP_HOPPING_NEITHER
        and mode != PUCCH_GROUP_HOPPING_ENABLE
        and mode != PUCCH_SEQUENCE_HOPPING_ENABLE
    ):
        raise Error("unknown PUCCH group-hopping mode")

    var f_ss = n_id % 30
    if mode == PUCCH_GROUP_HOPPING_NEITHER:
        return NRPucchSequenceHopping(f_ss, 0)
    if mode == PUCCH_GROUP_HOPPING_ENABLE:
        var offset = 8 * (
            2 * slots_per_frame * slot_in_frame + frequency_hop
        )
        var sequence = nr_gold_bits(UInt32(n_id // 30), offset + 8)
        var f_gh = 0
        for bit in range(8):
            f_gh += (1 << bit) * Int(sequence[offset + bit])
        return NRPucchSequenceHopping((f_gh + f_ss) % 30, 0)

    var offset = 2 * slots_per_frame * slot_in_frame + frequency_hop
    var c_init = UInt32(32 * (n_id // 30) + f_ss)
    var sequence = nr_gold_bits(c_init, offset + 1)
    return NRPucchSequenceHopping(f_ss, Int(sequence[offset]))


def nr_pucch_cyclic_shift_index(
    slot: Int,
    symbol_in_slot: Int,
    m0: Int,
    m_cs: Int,
    n_id: Int,
    *,
    symbols_per_slot: Int = 14,
) raises -> Int:
    """TS 38.211 6.3.2.2.2 cyclic-shift hopping, without interlace offset."""
    if (
        slot < 0
        or (symbols_per_slot != 12 and symbols_per_slot != 14)
        or symbol_in_slot < 0
        or symbol_in_slot >= symbols_per_slot
    ):
        raise Error("invalid PUCCH slot or symbol")
    if m0 < 0 or m0 > 11 or m_cs < 0 or m_cs > 11 or n_id < 0 or n_id > 1023:
        raise Error("invalid PUCCH cyclic-shift fields")
    var symbol_offset = 8 * symbol_in_slot
    var stride = 8 * symbols_per_slot
    if slot > (Int.MAX - symbol_offset - 8) // stride:
        raise Error("PUCCH cyclic-shift sequence offset overflows Int")
    var offset = stride * slot + symbol_offset
    var sequence = nr_gold_bits(UInt32(n_id), offset + 8)
    var hopping = 0
    for bit in range(8):
        hopping += (1 << bit) * Int(sequence[offset + bit])
    return (m0 + m_cs + hopping) % 12


def nr_pucch_low_papr_sequence_12(
    group: Int, cyclic_shift_index: Int
) raises -> List[Complex64]:
    """Length-12 r_bar(u,0)^alpha sequence used by PUCCH formats 0/1."""
    if group < 0 or group >= 30 or cyclic_shift_index < 0 or cyclic_shift_index > 11:
        raise Error("invalid PUCCH low-PAPR sequence configuration")
    var phi = _phi_12()
    var result = List[Complex64](capacity=12)
    for n in range(12):
        var angle = (
            _PI * Float64(phi[12 * group + n]) / 4.0
            + _TWO_PI * Float64(cyclic_shift_index * n) / 12.0
        )
        result.append(Complex64(cos(angle), sin(angle)))
    return result^


def nr_pucch_format0_sequence(
    group: Int, cyclic_shift_index: Int
) raises -> List[Complex64]:
    return nr_pucch_low_papr_sequence_12(group, cyclic_shift_index)


def nr_pucch_format1_sequence(
    bits: Span[UInt8, ...], group: Int, cyclic_shift_index: Int
) raises -> List[Complex64]:
    """BPSK/QPSK-modulate one format-1 low-PAPR resource-block sequence."""
    if len(bits) != 1 and len(bits) != 2:
        raise Error("PUCCH format 1 carries one or two information bits")
    var data = qam_map(bits, len(bits))
    var base = nr_pucch_low_papr_sequence_12(group, cyclic_shift_index)
    var symbol = Complex64(data[0].re, data[0].im)
    var result = List[Complex64](capacity=12)
    for n in range(12):
        result.append(base[n] * symbol)
    return result^


def nr_pucch_scramble(
    bits: Span[UInt8, ...], rnti: Int, n_id: Int
) raises -> List[UInt8]:
    """PUCCH formats 2/3/4 data scrambling with c_init=RNTI*2^10+n_ID."""
    if rnti < 0 or rnti > 0xFFFF or n_id < 0 or n_id > 1023:
        raise Error("invalid PUCCH scrambling configuration")
    var sequence = nr_gold_bits(UInt32((rnti << 10) + n_id), len(bits))
    var result = List[UInt8](capacity=len(bits))
    for i in range(len(bits)):
        if bits[i] > 1:
            raise Error("PUCCH input must contain only zero and one")
        result.append(bits[i] ^ sequence[i])
    return result^


def nr_pucch_format2_modulate(
    bits: Span[UInt8, ...], rnti: Int, n_id: Int
) raises -> List[Complex64]:
    if len(bits) < 4 or len(bits) % 2 != 0:
        raise Error("PUCCH format 2 requires an even coded length greater than two")
    var scrambled = nr_pucch_scramble(bits, rnti, n_id)
    return qam_map(Span(scrambled), 2)


def nr_pi_over_2_bpsk(bits: Span[UInt8, ...]) raises -> List[Complex64]:
    """TS 38.211 pi/2-BPSK modulation with unit average symbol power."""
    var scale = 1.0 / sqrt(2.0)
    var result = List[Complex64](capacity=len(bits))
    for i in range(len(bits)):
        if bits[i] > 1:
            raise Error("pi/2-BPSK input must contain only zero and one")
        var sign = 1.0 - 2.0 * Float64(bits[i])
        if i % 2 == 0:
            result.append(Complex64(scale * sign, scale * sign))
        else:
            result.append(Complex64(-scale * sign, scale * sign))
    return result^


def nr_pucch_format3_4_modulate(
    bits: Span[UInt8, ...], rnti: Int, n_id: Int, *, pi_over_2_bpsk: Bool = False
) raises -> List[Complex64]:
    var scrambled = nr_pucch_scramble(bits, rnti, n_id)
    if pi_over_2_bpsk:
        return nr_pi_over_2_bpsk(Span(scrambled))
    if len(scrambled) % 2 != 0:
        raise Error("QPSK PUCCH requires an even coded bit count")
    return qam_map(Span(scrambled), 2)


def nr_pucch_block_spread(
    symbols: Span[Complex64, ...], spreading_factor: Int, orthogonal_index: Int
) raises -> List[Complex64]:
    """DFT-orthogonal block spreading used by PUCCH formats 2A/4."""
    if spreading_factor != 2 and spreading_factor != 4:
        raise Error("PUCCH spreading factor must be two or four")
    if orthogonal_index < 0 or orthogonal_index >= spreading_factor:
        raise Error("PUCCH orthogonal sequence index is out of range")
    if len(symbols) > Int.MAX // spreading_factor:
        raise Error("PUCCH spread dimensions overflow Int")
    var result = List[Complex64](capacity=len(symbols) * spreading_factor)
    for i in range(len(symbols)):
        if not isfinite(symbols[i].re) or not isfinite(symbols[i].im):
            raise Error("PUCCH spread symbols must be finite")
        var symbol = Complex64(symbols[i].re, symbols[i].im)
        for m in range(spreading_factor):
            var angle = -_TWO_PI * Float64(orthogonal_index * m) / Float64(spreading_factor)
            var value = symbol * Complex64(cos(angle), sin(angle))
            if not isfinite(value.re) or not isfinite(value.im):
                raise Error("PUCCH spread result must remain finite")
            result.append(value)
    return result^


def nr_pucch_block_despread(
    symbols: Span[Complex64, ...], spreading_factor: Int, orthogonal_index: Int
) raises -> List[Complex64]:
    if spreading_factor != 2 and spreading_factor != 4:
        raise Error("PUCCH spreading factor must be two or four")
    if orthogonal_index < 0 or orthogonal_index >= spreading_factor or len(symbols) % spreading_factor != 0:
        raise Error("invalid PUCCH despreading dimensions")
    var result = List[Complex64](capacity=len(symbols) // spreading_factor)
    for i in range(len(symbols) // spreading_factor):
        var acc = Complex64(0.0, 0.0)
        for m in range(spreading_factor):
            var value = Complex64(
                symbols[i * spreading_factor + m].re,
                symbols[i * spreading_factor + m].im,
            )
            if not isfinite(value.re) or not isfinite(value.im):
                raise Error("PUCCH despread symbols must be finite")
            var angle = _TWO_PI * Float64(orthogonal_index * m) / Float64(spreading_factor)
            acc = acc + value * Complex64(cos(angle), sin(angle))
            if not isfinite(acc.re) or not isfinite(acc.im):
                raise Error("PUCCH despread accumulation must remain finite")
        var output = Complex64(
            acc.re / Float64(spreading_factor),
            acc.im / Float64(spreading_factor),
        )
        if not isfinite(output.re) or not isfinite(output.im):
            raise Error("PUCCH despread result must remain finite")
        result.append(output)
    return result^
