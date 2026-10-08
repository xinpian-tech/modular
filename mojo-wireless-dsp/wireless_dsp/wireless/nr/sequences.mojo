"""3GPP TS 38.211 V18.9.0 synchronization and Gold sequences."""

from std.math import sqrt
from wireless_dsp.core import Complex64


def nr_gold_bits(c_init: UInt32, length: Int) raises -> List[UInt8]:
    """Clause 5.2.1 length-31 Gold sequence with Nc=1600."""
    comptime nc = 1600
    if length < 0 or length > Int.MAX - nc - 31:
        raise Error("Gold sequence length is outside the supported Int range")
    var total = nc + length + 31
    var x1 = List[UInt8](length=total, fill=UInt8(0))
    var x2 = List[UInt8](length=total, fill=UInt8(0))
    x1[0] = 1
    for i in range(31):
        x2[i] = UInt8((c_init >> UInt32(i)) & 1)
    for n in range(total - 31):
        x1[n + 31] = x1[n + 3] ^ x1[n]
        x2[n + 31] = x2[n + 3] ^ x2[n + 2] ^ x2[n + 1] ^ x2[n]
    var result = List[UInt8](capacity=length)
    for n in range(length):
        result.append(x1[n + nc] ^ x2[n + nc])
    return result^


def nr_qpsk_sequence(c_init: UInt32, length: Int) raises -> List[Complex64]:
    if length < 0 or length > (Int.MAX - 1631) // 2:
        raise Error("NR QPSK sequence length is outside the supported Int range")
    var bits = nr_gold_bits(c_init, 2 * length)
    var scale = 1.0 / sqrt(2.0)
    var result = List[Complex64](capacity=length)
    for i in range(length):
        result.append(Complex64(
            scale * (1.0 - 2.0 * Float64(bits[2 * i])),
            scale * (1.0 - 2.0 * Float64(bits[2 * i + 1])),
        ))
    return result^


def nr_pss(n_id_2: Int) raises -> List[Float64]:
    """Clause 7.4.2.2 PSS for N_ID_2 in {0,1,2}."""
    if n_id_2 < 0 or n_id_2 > 2:
        raise Error("N_ID_2 must be 0, 1, or 2")
    var x = List[UInt8](length=127, fill=UInt8(0))
    var initial: List[UInt8] = [0, 1, 1, 0, 1, 1, 1]
    for i in range(7):
        x[i] = initial[i]
    for i in range(120):
        x[i + 7] = x[i + 4] ^ x[i]
    var result = List[Float64](capacity=127)
    for n in range(127):
        var m = (n + 43 * n_id_2) % 127
        result.append(1.0 - 2.0 * Float64(x[m]))
    return result^


def nr_sss(n_id_1: Int, n_id_2: Int) raises -> List[Float64]:
    """Clause 7.4.2.3 SSS for the 1008 physical-layer cell identities."""
    if n_id_1 < 0 or n_id_1 > 335 or n_id_2 < 0 or n_id_2 > 2:
        raise Error("invalid NR synchronization identity")
    var x0 = List[UInt8](length=127, fill=UInt8(0))
    var x1 = List[UInt8](length=127, fill=UInt8(0))
    x0[0] = 1
    x1[0] = 1
    for i in range(120):
        x0[i + 7] = x0[i + 4] ^ x0[i]
        x1[i + 7] = x1[i + 1] ^ x1[i]
    var m0 = 15 * (n_id_1 // 112) + 5 * n_id_2
    var m1 = n_id_1 % 112
    var result = List[Float64](capacity=127)
    for n in range(127):
        result.append(
            (1.0 - 2.0 * Float64(x0[(n + m0) % 127]))
            * (1.0 - 2.0 * Float64(x1[(n + m1) % 127]))
        )
    return result^


def nr_pbch_dmrs_c_init(
    physical_cell_id: Int, ssb_index: Int, half_frame: Int, l_max: Int
) raises -> UInt32:
    """38.211 7.4.1.4.1 PBCH DM-RS initialization."""
    if physical_cell_id < 0 or physical_cell_id > 1007:
        raise Error("physical cell identity must be in [0,1007]")
    if half_frame < 0 or half_frame > 1 or (l_max != 4 and l_max != 8 and l_max != 64):
        raise Error("invalid SS/PBCH block configuration")
    if ssb_index < 0 or ssb_index >= l_max:
        raise Error("SS/PBCH block index is out of range")
    var i_ssb = (ssb_index & 3) + 4 * half_frame if l_max == 4 else ssb_index & 7
    var value = (
        (1 << 11) * (i_ssb + 1) * (physical_cell_id // 4 + 1)
        + (1 << 6) * (i_ssb + 1)
        + physical_cell_id % 4
    )
    return UInt32(value)


def nr_pbch_dmrs(
    physical_cell_id: Int, ssb_index: Int, half_frame: Int, l_max: Int,
    *, length: Int = 144,
) raises -> List[Complex64]:
    return nr_qpsk_sequence(
        nr_pbch_dmrs_c_init(physical_cell_id, ssb_index, half_frame, l_max),
        length,
    )
