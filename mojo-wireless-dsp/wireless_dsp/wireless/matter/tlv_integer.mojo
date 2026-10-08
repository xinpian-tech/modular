"""Matter 1.6 anonymous signed and unsigned integer TLV elements.

This deliberately narrow module implements the deterministic integer rows in
Matter Specification R1.6 Appendix A.  The normative source is the official
June 16, 2026 PDF (SHA-256
``48b3b117569f72558ba71813360d77abdfa11fcf28747bd269148104936b52b7``),
Sections A.1, A.2.3, A.4, A.6, A.7, A.7.1, A.7.2, A.8.5, A.11.1, A.12,
and the integer rows of Table 127.

Only a single top-level anonymous integer element is accepted.  Callers choose
the exact 1, 2, 4, or 8-octet value width; legal non-minimal encodings are
preserved on decode and accepted.  Tagged elements, containers, concatenated
elements, and every other primitive type remain outside this bounded slice.
"""

from std.collections import Span


struct MatterTLVSignedIntegerDecodeResult(Movable):
    """Owned value and encoded width of one anonymous signed integer."""

    var value: Int64
    var width: Int

    def __init__(out self, value: Int64, width: Int):
        self.value = value
        self.width = width


struct MatterTLVUnsignedIntegerDecodeResult(Movable):
    """Owned value and encoded width of one anonymous unsigned integer."""

    var value: UInt64
    var width: Int

    def __init__(out self, value: UInt64, width: Int):
        self.value = value
        self.width = width


def _require_width(width: Int) raises:
    if width != 1 and width != 2 and width != 4 and width != 8:
        raise Error("Matter TLV integer width must be 1, 2, 4, or 8 octets")


def _width_code(width: Int) raises -> UInt8:
    _require_width(width)
    if width == 1:
        return UInt8(0)
    if width == 2:
        return UInt8(1)
    if width == 4:
        return UInt8(2)
    return UInt8(3)


def _width_from_code(code: UInt8) raises -> Int:
    if code == UInt8(0):
        return 1
    if code == UInt8(1):
        return 2
    if code == UInt8(2):
        return 4
    if code == UInt8(3):
        return 8
    raise Error("Matter TLV integer width code is reserved")


def _require_signed_fits(value: Int64, width: Int) raises:
    _require_width(width)
    if width == 1 and (value < Int64(-128) or value > Int64(127)):
        raise Error("Matter TLV signed value does not fit one octet")
    if width == 2 and (value < Int64(-32768) or value > Int64(32767)):
        raise Error("Matter TLV signed value does not fit two octets")
    if width == 4 and (value < Int64(-2147483648) or value > Int64(2147483647)):
        raise Error("Matter TLV signed value does not fit four octets")


def _require_unsigned_fits(value: UInt64, width: Int) raises:
    _require_width(width)
    if width == 1 and value > UInt64(0xFF):
        raise Error("Matter TLV unsigned value does not fit one octet")
    if width == 2 and value > UInt64(0xFFFF):
        raise Error("Matter TLV unsigned value does not fit two octets")
    if width == 4 and value > UInt64(0xFFFFFFFF):
        raise Error("Matter TLV unsigned value does not fit four octets")


def _append_little_endian(mut output: List[UInt8], value: UInt64, width: Int):
    for byte_index in range(width):
        output.append(UInt8((value >> UInt64(8 * byte_index)) & UInt64(0xFF)))


def _read_little_endian(encoded: Span[UInt8, ...], width: Int) -> UInt64:
    var value = UInt64(0)
    for byte_index in range(width):
        value |= UInt64(encoded[byte_index + 1]) << UInt64(8 * byte_index)
    return value


def matter_tlv_encode_signed_integer(
    value: Int64, width: Int
) raises -> List[UInt8]:
    """Encode an explicit-width top-level anonymous signed integer element."""

    _require_signed_fits(value, width)
    var result = List[UInt8](capacity=width + 1)
    result.append(_width_code(width))
    _append_little_endian(result, UInt64(value), width)
    return result^


def matter_tlv_decode_signed_integer(
    encoded: Span[UInt8, ...],
) raises -> MatterTLVSignedIntegerDecodeResult:
    """Strictly decode one exact top-level anonymous signed integer element."""

    if len(encoded) == 0:
        raise Error("Matter TLV signed integer element is empty")
    var control = encoded[0]
    if control > UInt8(3):
        raise Error(
            "Matter TLV signed decoder requires an anonymous signed control"
        )
    var width = _width_from_code(control)
    if len(encoded) != width + 1:
        raise Error("Matter TLV signed integer has a non-exact element length")

    var raw = _read_little_endian(encoded, width)
    var sign_bit = UInt64(1) << UInt64(width * 8 - 1)
    if (raw & sign_bit) == UInt64(0):
        return MatterTLVSignedIntegerDecodeResult(Int64(raw), width)
    if width == 8:
        var magnitude = (~raw) + UInt64(1)
        if magnitude == (UInt64(1) << UInt64(63)):
            return MatterTLVSignedIntegerDecodeResult(Int64.MIN_FINITE, width)
        return MatterTLVSignedIntegerDecodeResult(-Int64(magnitude), width)
    var modulus = UInt64(1) << UInt64(width * 8)
    return MatterTLVSignedIntegerDecodeResult(-Int64(modulus - raw), width)


def matter_tlv_encode_unsigned_integer(
    value: UInt64, width: Int
) raises -> List[UInt8]:
    """Encode an explicit-width top-level anonymous unsigned integer element."""

    _require_unsigned_fits(value, width)
    var result = List[UInt8](capacity=width + 1)
    result.append(UInt8(4) + _width_code(width))
    _append_little_endian(result, value, width)
    return result^


def matter_tlv_decode_unsigned_integer(
    encoded: Span[UInt8, ...],
) raises -> MatterTLVUnsignedIntegerDecodeResult:
    """Strictly decode one exact top-level anonymous unsigned integer element.
    """

    if len(encoded) == 0:
        raise Error("Matter TLV unsigned integer element is empty")
    var control = encoded[0]
    if control < UInt8(4) or control > UInt8(7):
        raise Error(
            "Matter TLV unsigned decoder requires an anonymous unsigned control"
        )
    var width = _width_from_code(control - UInt8(4))
    if len(encoded) != width + 1:
        raise Error(
            "Matter TLV unsigned integer has a non-exact element length"
        )
    return MatterTLVUnsignedIntegerDecodeResult(
        _read_little_endian(encoded, width), width
    )
