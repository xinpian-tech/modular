"""Bit-serial MSB-first CRC golden reference primitives."""

from std.collections import Span

def _width_mask(width: Int) raises -> UInt64:
    if width < 1 or width > 63:
        raise Error("CRC width must be between 1 and 63")
    return (UInt64(1) << UInt64(width)) - 1

def crc_bits(
    bits: Span[UInt8, ...], *, width: Int, polynomial: UInt64,
    initial: UInt64 = 0, xor_out: UInt64 = 0,
) raises -> UInt64:
    """Compute an unreflected MSB-first CRC; polynomial omits its top bit."""
    var mask = _width_mask(width)
    var register = initial & mask
    var top = UInt64(1) << UInt64(width - 1)
    for i in range(len(bits)):
        var bit = UInt64(bits[i])
        if bit > 1:
            raise Error("bits must be zero or one")
        var feedback = ((register & top) >> UInt64(width - 1)) ^ bit
        register = (register << 1) & mask
        if feedback != 0:
            register ^= polynomial & mask
    return (register ^ xor_out) & mask

def crc_append(bits: Span[UInt8, ...], *, width: Int, polynomial: UInt64) raises -> List[UInt8]:
    var remainder = crc_bits(bits, width=width, polynomial=polynomial)
    var result = List[UInt8](capacity=len(bits) + width)
    for i in range(len(bits)):
        result.append(bits[i])
    for i in range(width):
        result.append(UInt8((remainder >> UInt64(width - i - 1)) & 1))
    return result^

def crc_check(codeword: Span[UInt8, ...], *, width: Int, polynomial: UInt64) raises -> Bool:
    return crc_bits(codeword, width=width, polynomial=polynomial) == 0


def crc_reflected_bits(
    bits: Span[UInt8, ...], *, width: Int, polynomial: UInt64,
    initial: UInt64 = 0, xor_out: UInt64 = 0,
) raises -> UInt64:
    """Compute a reflected LSB-first CRC; polynomial is the reversed form."""
    var mask = _width_mask(width)
    var register = initial & mask
    for i in range(len(bits)):
        if bits[i] > 1:
            raise Error("bits must be zero or one")
        var feedback = (register & 1) ^ UInt64(bits[i])
        register >>= UInt64(1)
        if feedback != 0:
            register ^= polynomial & mask
    return (register ^ xor_out) & mask
