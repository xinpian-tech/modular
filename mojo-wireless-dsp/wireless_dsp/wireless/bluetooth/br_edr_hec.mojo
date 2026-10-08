"""Bluetooth Core 6.3 BR/EDR packet-header HEC primitives.

This deliberately narrow module implements only the deterministic Header
Error Check in Vol 2, Part B, Sections 1.2.1, 6.4.6, 6.5.1.1, and 7.1.1.  The
caller supplies the ten header-information bits in transmission order and the
already selected eight-bit UAP or DCI initialization value.

Access-code validation, header-field and packet-type semantics, UAP/DCI state
selection, whitening, FEC, payload CRC, ARQ, AFH, timing, security, modulation,
and RF processing are outside this atomic boundary.  In particular, a passing
HEC check is not a complete packet-header-validity verdict because the Core
also requires the access code to be correct for the piconet.
"""

from std.collections import Span
from wireless_dsp.modem.crc import crc_reflected_bits


comptime _HEADER_INFORMATION_BITS = 10
comptime _HEC_BITS = 8
comptime _HEC_REFLECTED_POLYNOMIAL = UInt64(0xE5)


def _validate_header_information_bits(
    header_information_bits: Span[UInt8, ...]
) raises:
    if len(header_information_bits) != _HEADER_INFORMATION_BITS:
        raise Error(
            "Bluetooth BR/EDR HEC requires exactly ten header-information bits"
        )
    for index in range(len(header_information_bits)):
        if header_information_bits[index] > 1:
            raise Error(
                "Bluetooth BR/EDR header information must contain only zero and one"
            )


def _validate_uap_or_dci(uap_or_dci: Int) raises:
    if uap_or_dci < 0 or uap_or_dci > 0xFF:
        raise Error("Bluetooth BR/EDR UAP or DCI must be an eight-bit value")


def _validate_received_hec(received_hec: Int) raises:
    if received_hec < 0 or received_hec > 0xFF:
        raise Error("Bluetooth BR/EDR received HEC must be an eight-bit value")


def _reverse_uap_or_dci_bits(uap_or_dci: Int) -> UInt64:
    # The Core loads UAP0 through UAP7 into LFSR positions 0 through 7.
    # ``crc_reflected_bits`` stores the first transmitted register position in
    # its least-significant bit, so this fixed adapter reverses the octet.
    var result = UInt64(0)
    for index in range(_HEC_BITS):
        result |= (
            UInt64((uap_or_dci >> index) & 1)
            << UInt64(_HEC_BITS - index - 1)
        )
    return result


def _hec_remainder(
    bits_in_transmission_order: Span[UInt8, ...], uap_or_dci: Int
) raises -> UInt64:
    return crc_reflected_bits(
        bits_in_transmission_order,
        width=_HEC_BITS,
        polynomial=_HEC_REFLECTED_POLYNOMIAL,
        initial=_reverse_uap_or_dci_bits(uap_or_dci),
    )


def bluetooth_br_edr_hec_generate(
    header_information_bits: Span[UInt8, ...], uap_or_dci: Int
) raises -> UInt8:
    """Generate the eight-bit BR/EDR HEC for ten wire-order header bits.

    Bit ``i`` of the returned scalar is the ``i``-th HEC bit transmitted over
    the air.  This packing therefore compares directly with the hexadecimal
    HEC values in Core 6.3 Vol 2, Part G, Section 4.
    """

    _validate_header_information_bits(header_information_bits)
    _validate_uap_or_dci(uap_or_dci)
    return UInt8(_hec_remainder(header_information_bits, uap_or_dci))


def bluetooth_br_edr_hec_check(
    header_information_bits: Span[UInt8, ...],
    received_hec: Int,
    uap_or_dci: Int,
) raises -> Bool:
    """Return whether the BR/EDR HEC checking circuit has zero remainder.

    This checks only the HEC.  It does not validate the access code, interpret
    any header field, or return the Core's broader packet-header verdict.
    """

    _validate_header_information_bits(header_information_bits)
    _validate_received_hec(received_hec)
    _validate_uap_or_dci(uap_or_dci)

    var codeword = List[UInt8](capacity=_HEADER_INFORMATION_BITS + _HEC_BITS)
    for index in range(_HEADER_INFORMATION_BITS):
        codeword.append(header_information_bits[index])
    for index in range(_HEC_BITS):
        codeword.append(UInt8((received_hec >> index) & 1))
    return _hec_remainder(Span(codeword), uap_or_dci) == 0
