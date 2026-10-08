"""IEEE 802.11a/g reusable PHY primitives for 64-point OFDM symbols."""

from std.collections import Span
from wireless_dsp.core import Complex64
from wireless_dsp.dsp import (
    ofdm_modulate,
    ofdm_demodulate,
    ls_channel_estimate,
    zero_forcing_equalize_siso,
)
from wireless_dsp.synchronization import detect_repetition_start, estimate_repetition_cfo
from wireless_dsp.modem import crc_reflected_bits


def wifi_scramble(bits: Span[UInt8, ...], seed: UInt8) raises -> List[UInt8]:
    """IEEE 802.11 x^7+x^4+1 additive scrambler; seed must be nonzero."""
    if seed == 0 or seed > 0x7F:
        raise Error("Wi-Fi scrambler seed must be a nonzero 7-bit value")
    var state = seed
    var result = List[UInt8](capacity=len(bits))
    for i in range(len(bits)):
        if bits[i] > 1:
            raise Error("bits must be zero or one")
        var feedback = ((state >> 6) ^ (state >> 3)) & 1
        result.append(bits[i] ^ feedback)
        state = ((state << 1) & 0x7E) | feedback
    return result^


def wifi_interleave(bits: Span[UInt8, ...], bits_per_subcarrier: Int) raises -> List[UInt8]:
    """Two-step legacy OFDM interleaver from IEEE 802.11-2020 17.3.5.7."""
    var coded_bits = 48 * bits_per_subcarrier
    if len(bits) != coded_bits or bits_per_subcarrier < 1:
        raise Error("interleaver requires one complete legacy OFDM symbol")
    var s = max(bits_per_subcarrier // 2, 1)
    var result = List[UInt8](length=coded_bits, fill=UInt8(0))
    for k in range(coded_bits):
        var first = (coded_bits // 16) * (k % 16) + k // 16
        var second = s * (first // s) + (first + coded_bits - (16 * first) // coded_bits) % s
        result[second] = bits[k]
    return result^


def wifi_deinterleave(bits: Span[UInt8, ...], bits_per_subcarrier: Int) raises -> List[UInt8]:
    var coded_bits = 48 * bits_per_subcarrier
    if len(bits) != coded_bits:
        raise Error("deinterleaver requires one complete legacy OFDM symbol")
    var result = List[UInt8](length=coded_bits, fill=UInt8(0))
    var s = max(bits_per_subcarrier // 2, 1)
    for k in range(coded_bits):
        var first = (coded_bits // 16) * (k % 16) + k // 16
        var second = s * (first // s) + (first + coded_bits - (16 * first) // coded_bits) % s
        result[k] = bits[second]
    return result^


def wifi_data_subcarriers() -> List[Int]:
    var result = List[Int](capacity=48)
    for subcarrier in range(-26, 27):
        if subcarrier == 0 or subcarrier == -21 or subcarrier == -7 or subcarrier == 7 or subcarrier == 21:
            continue
        result.append(subcarrier)
    return result^


def _bin(subcarrier: Int) -> Int:
    return subcarrier if subcarrier >= 0 else 64 + subcarrier


def wifi_pilot_polarity(symbol_index: Int) raises -> Float64:
    """Generate the 127-symbol pilot polarity sequence with x^7+x^4+1."""
    if symbol_index < 0:
        raise Error("symbol index must be non-negative")
    var state = UInt8(0x7F)
    var polarity = 1.0
    for _ in range(symbol_index + 1):
        var feedback = ((state >> 6) ^ (state >> 3)) & 1
        polarity = 1.0 if feedback == 0 else -1.0
        state = ((state << 1) & 0x7E) | feedback
    return polarity


def wifi_map_legacy_symbol(
    data: Span[Complex64, ...], *, symbol_index: Int = 0
) raises -> List[Complex64]:
    """Map 48 data and four fixed pilots, then create a 16-sample CP symbol."""
    if len(data) != 48:
        raise Error("legacy OFDM symbol requires 48 data subcarriers")
    var spectrum = List[Complex64](length=64, fill=Complex64(0.0, 0.0))
    var carriers = wifi_data_subcarriers()
    for i in range(48):
        spectrum[_bin(carriers[i])] = data[i]
    var polarity = wifi_pilot_polarity(symbol_index)
    spectrum[_bin(-21)] = Complex64(polarity)
    spectrum[_bin(-7)] = Complex64(polarity)
    spectrum[_bin(7)] = Complex64(polarity)
    spectrum[_bin(21)] = Complex64(-polarity)
    return ofdm_modulate(Span(spectrum), 16)


def wifi_extract_legacy_symbol(samples: Span[Complex64, ...]) raises -> List[Complex64]:
    var spectrum = ofdm_demodulate(samples, 64, 16)
    var carriers = wifi_data_subcarriers()
    var result = List[Complex64](capacity=48)
    for i in range(48):
        result.append(spectrum[_bin(carriers[i])])
    return result^


def wifi_ls_channel_estimate(
    received: Span[Complex64, ...], known: Span[Complex64, ...]
) raises -> List[Complex64]:
    """Per-subcarrier LS equalization from a known legacy training symbol."""
    return ls_channel_estimate(received, known)


def wifi_equalize(
    received: Span[Complex64, ...], channel: Span[Complex64, ...]
) raises -> List[Complex64]:
    return zero_forcing_equalize_siso(received, channel)


def wifi_stf_detect(samples: Span[Complex64, ...], threshold: Float64 = 0.8) raises -> Int:
    """Legacy STF detection using its 16-sample repetition."""
    return detect_repetition_start(samples, 16, 16, threshold)


def wifi_stf_coarse_cfo(samples: Span[Complex64, ...], offset: Int) raises -> Float64:
    return estimate_repetition_cfo(samples, offset, 16, 16)


struct LegacySignal(Movable):
    var rate_bits: List[UInt8]
    var length_octets: Int

    def __init__(out self, var rate_bits: List[UInt8], length_octets: Int):
        self.rate_bits = rate_bits^
        self.length_octets = length_octets


def wifi_legacy_signal_bits(
    rate_bits: Span[UInt8, ...], length_octets: Int
) raises -> List[UInt8]:
    """Build the 24 uncoded L-SIG bits: RATE/R/LENGTH/parity/tail."""
    if len(rate_bits) != 4 or length_octets < 0 or length_octets > 4095:
        raise Error("invalid legacy SIGNAL fields")
    var result = List[UInt8](capacity=24)
    var parity = UInt8(0)
    for i in range(4):
        if rate_bits[i] > 1:
            raise Error("RATE must contain bits")
        result.append(rate_bits[i])
        parity ^= rate_bits[i]
    result.append(UInt8(0))
    for i in range(12):
        var bit = UInt8((length_octets >> i) & 1)
        result.append(bit)
        parity ^= bit
    result.append(parity)
    for _ in range(6):
        result.append(UInt8(0))
    return result^


def wifi_parse_legacy_signal(bits: Span[UInt8, ...]) raises -> LegacySignal:
    if len(bits) != 24:
        raise Error("legacy SIGNAL must contain 24 bits")
    var parity = UInt8(0)
    for i in range(17):
        parity ^= bits[i]
    if parity != bits[17]:
        raise Error("legacy SIGNAL parity failure")
    var rate = List[UInt8](capacity=4)
    for i in range(4):
        rate.append(bits[i])
    var length_octets = 0
    for i in range(12):
        length_octets |= Int(bits[5 + i]) << i
    return LegacySignal(rate^, length_octets)


def wifi_fcs(bits_lsb_first: Span[UInt8, ...]) raises -> UInt64:
    """IEEE 802.11 FCS/CRC-32 over per-octet LSB-first input bits."""
    return crc_reflected_bits(
        bits_lsb_first,
        width=32,
        polynomial=UInt64(0xEDB88320),
        initial=UInt64(0xFFFFFFFF),
        xor_out=UInt64(0xFFFFFFFF),
    )
