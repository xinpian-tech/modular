"""Independent, receive-only evidence for the four composite Wi-Fi RX APIs.

No fixture in this file calls a production transmitter, channel model, FFT,
mapper, encoder, or helper below the wrapper under test.  HT/VHT DATA and the
preambles are rebuilt from the IEEE bit/carrier formulas.  The HE and separate
EHT DATA fixtures use packed codewords generated independently with a GF(2)
solver from the IEEE 802.11 QC-LDPC matrices.  The observation model is the
explicit y[n] = h*x[n-delay]*exp(j*2*pi*f*n) equation.

Exact comparisons are used for bits and metadata.  Floating checkpoints use
the explicit absolute-plus-relative predicate documented below; the larger
LLR tolerance accounts only for the 1/noise-variance scaling.
"""

from std.collections import Span
from std.math import cos, sin, sqrt
from std.testing import assert_equal, assert_raises, assert_true, TestSuite
from std.utils.numerics import inf, nan
from wireless_dsp.core import Complex64
from wireless_dsp.testing import CheckpointMetadata
from wireless_dsp.wireless.wifi import (
    WIFI_PHY_HT,
    WIFI_PHY_VHT,
    WIFI_PHY_HE,
    WIFI_PHY_EHT,
    wifi_bcc_rx_20mhz,
    wifi_ldpc_rx_20mhz,
    wifi_acquisition_rx_20mhz,
    wifi_he_eht_acquisition_rx_20mhz,
)


comptime TWO_PI = 6.283185307179586476925286766559
comptime SAMPLE_ABS_TOL = 4.0e-10
comptime SAMPLE_REL_TOL = 4.0e-10
comptime LLR_ABS_TOL = 2.0e-6
comptime LLR_REL_TOL = 2.0e-9
comptime PHASE_TOL = 2.0e-10


struct _Frame(Movable):
    var bits: List[UInt8]
    var fcs: UInt64

    def __init__(out self, var bits: List[UInt8], fcs: UInt64):
        self.bits = bits^
        self.fcs = fcs


struct _Signal(Movable):
    var bits: List[UInt8]
    var coded: List[UInt8]
    var interleaved: List[UInt8]
    var symbols: List[Complex64]
    var spectrum: List[Complex64]
    var waveform: List[Complex64]

    def __init__(
        out self,
        var bits: List[UInt8],
        var coded: List[UInt8],
        var interleaved: List[UInt8],
        var symbols: List[Complex64],
        var spectrum: List[Complex64],
        var waveform: List[Complex64],
    ):
        self.bits = bits^
        self.coded = coded^
        self.interleaved = interleaved^
        self.symbols = symbols^
        self.spectrum = spectrum^
        self.waveform = waveform^


struct _BCCData(Movable):
    var payload: List[UInt8]
    var frame: List[UInt8]
    var scrambled: List[UInt8]
    var expected_decoded: List[UInt8]
    var punctured: List[UInt8]
    var interleaved: List[UInt8]
    var symbols: List[Complex64]
    var spectrum: List[Complex64]
    var waveform: List[Complex64]
    var fcs: UInt64

    def __init__(
        out self,
        var payload: List[UInt8],
        var frame: List[UInt8],
        var scrambled: List[UInt8],
        var expected_decoded: List[UInt8],
        var punctured: List[UInt8],
        var interleaved: List[UInt8],
        var symbols: List[Complex64],
        var spectrum: List[Complex64],
        var waveform: List[Complex64],
        fcs: UInt64,
    ):
        self.payload = payload^
        self.frame = frame^
        self.scrambled = scrambled^
        self.expected_decoded = expected_decoded^
        self.punctured = punctured^
        self.interleaved = interleaved^
        self.symbols = symbols^
        self.spectrum = spectrum^
        self.waveform = waveform^
        self.fcs = fcs


struct _LDPCData(Movable):
    var payload: List[UInt8]
    var frame: List[UInt8]
    var rate_matched: List[UInt8]
    var tone_mapped: List[UInt8]
    var symbols: List[Complex64]
    var spectrum: List[Complex64]
    var waveform: List[Complex64]
    var fcs: UInt64

    def __init__(
        out self,
        var payload: List[UInt8],
        var frame: List[UInt8],
        var rate_matched: List[UInt8],
        var tone_mapped: List[UInt8],
        var symbols: List[Complex64],
        var spectrum: List[Complex64],
        var waveform: List[Complex64],
        fcs: UInt64,
    ):
        self.payload = payload^
        self.frame = frame^
        self.rate_matched = rate_matched^
        self.tone_mapped = tone_mapped^
        self.symbols = symbols^
        self.spectrum = spectrum^
        self.waveform = waveform^
        self.fcs = fcs


def _payload(octets: Int, salt: Int) -> List[UInt8]:
    var result = List[UInt8](capacity=8 * octets)
    for i in range(8 * octets):
        result.append(UInt8((13 * i + i // 5 + salt) & 1))
    return result^


def _ascii_123456789() -> List[UInt8]:
    var result = List[UInt8](capacity=72)
    for octet in [
        0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39,
    ]:
        for bit in range(8):
            result.append(UInt8((octet >> bit) & 1))
    return result^


def _fcs(bits: Span[UInt8, ...]) -> UInt64:
    var register = UInt64(0xFFFFFFFF)
    for i in range(len(bits)):
        var feedback = (register & UInt64(1)) ^ UInt64(bits[i])
        register >>= UInt64(1)
        if feedback != 0:
            register ^= UInt64(0xEDB88320)
    return register ^ UInt64(0xFFFFFFFF)


def _frame(payload: Span[UInt8, ...]) -> _Frame:
    var checksum = _fcs(payload)
    var bits = List[UInt8](capacity=16 + len(payload) + 32)
    for _ in range(16):
        bits.append(UInt8(0))
    for i in range(len(payload)):
        bits.append(payload[i])
    for shift in range(32):
        bits.append(UInt8((checksum >> UInt64(shift)) & UInt64(1)))
    return _Frame(bits^, checksum)


def _scramble(bits: Span[UInt8, ...], seed: UInt8) -> List[UInt8]:
    var state = seed
    var result = List[UInt8](capacity=len(bits))
    for i in range(len(bits)):
        var feedback = ((state >> 6) ^ (state >> 3)) & 1
        result.append(bits[i] ^ feedback)
        state = ((state << 1) & 0x7E) | feedback
    return result^


def _parity(value: Int) -> UInt8:
    var remaining = value
    var parity = UInt8(0)
    while remaining != 0:
        parity ^= UInt8(remaining & 1)
        remaining >>= 1
    return parity


def _bcc(bits: Span[UInt8, ...]) -> List[UInt8]:
    var result = List[UInt8](capacity=2 * len(bits))
    var register = 0
    for i in range(len(bits)):
        register = ((register << 1) | Int(bits[i])) & 0x7F
        result.append(_parity(register & 0o133))
        result.append(_parity(register & 0o171))
    return result^


def _puncture_three_quarters(bits: Span[UInt8, ...]) -> List[UInt8]:
    var keep: List[UInt8] = [1, 1, 1, 0, 0, 1]
    var result = List[UInt8]()
    for i in range(len(bits)):
        if keep[i % 6] == 1:
            result.append(bits[i])
    return result^


def _depuncture_three_quarters(
    llrs: Span[Float64, ...], mother_length: Int
) -> List[Float64]:
    var keep: List[UInt8] = [1, 1, 1, 0, 0, 1]
    var result = List[Float64](capacity=mother_length)
    var source = 0
    for i in range(mother_length):
        if keep[i % 6] == 1:
            result.append(llrs[source])
            source += 1
        else:
            result.append(0.0)
    return result^


def _interleave(
    bits: Span[UInt8, ...], bits_per_subcarrier: Int, columns: Int,
    rows_per_modulation_bit: Int,
) -> List[UInt8]:
    var coded_bits = len(bits)
    var rows = rows_per_modulation_bit * bits_per_subcarrier
    var s = max(bits_per_subcarrier // 2, 1)
    var result = List[UInt8](length=coded_bits, fill=UInt8(0))
    for k in range(coded_bits):
        var first = rows * (k % columns) + k // columns
        var second = (
            s * (first // s)
            + (first + coded_bits - (columns * first) // coded_bits) % s
        )
        result[second] = bits[k]
    return result^


def _deinterleave_llrs(
    llrs: Span[Float64, ...], bits_per_subcarrier: Int, columns: Int,
    rows_per_modulation_bit: Int,
) -> List[Float64]:
    var coded_bits = len(llrs)
    var rows = rows_per_modulation_bit * bits_per_subcarrier
    var s = max(bits_per_subcarrier // 2, 1)
    var result = List[Float64](length=coded_bits, fill=0.0)
    for k in range(coded_bits):
        var first = rows * (k % columns) + k // columns
        var second = (
            s * (first // s)
            + (first + coded_bits - (columns * first) // coded_bits) % s
        )
        result[k] = llrs[second]
    return result^


def _gray_to_binary(gray: Int) -> Int:
    var result = gray
    var shifted = gray >> 1
    while shifted != 0:
        result ^= shifted
        shifted >>= 1
    return result


def _qam(bits: Span[UInt8, ...], bits_per_symbol: Int) -> List[Complex64]:
    var result = List[Complex64](capacity=len(bits) // bits_per_symbol)
    var axis_bits = bits_per_symbol // 2
    var mask = (1 << axis_bits) - 1
    var scale = (
        sqrt((2.0 / 3.0) * Float64((1 << bits_per_symbol) - 1))
        if bits_per_symbol > 1 else 1.0
    )
    for symbol in range(len(bits) // bits_per_symbol):
        var label = 0
        for local in range(bits_per_symbol):
            label = (
                (label << 1)
                | Int(bits[symbol * bits_per_symbol + local])
            )
        if bits_per_symbol == 1:
            result.append(Complex64(1.0 if label == 0 else -1.0))
        else:
            var i_index = _gray_to_binary((label >> axis_bits) & mask)
            var q_index = _gray_to_binary(label & mask)
            result.append(Complex64(
                Float64(mask - 2 * i_index) / scale,
                Float64(mask - 2 * q_index) / scale,
            ))
    return result^


def _maxlog_llrs(
    samples: Span[Complex64, ...], bits_per_symbol: Int,
    noise_variance: Float64,
) -> List[Float64]:
    # Independent exhaustive-PAM oracle.  It does not call the production
    # piecewise demapper and enumerates both bit partitions explicitly.
    var result = List[Float64](capacity=len(samples) * bits_per_symbol)
    if bits_per_symbol == 1:
        for i in range(len(samples)):
            result.append(4.0 * samples[i].re / noise_variance)
        return result^
    var axis_bits = bits_per_symbol // 2
    var order = 1 << axis_bits
    var mask = order - 1
    var scale = sqrt(
        (2.0 / 3.0) * Float64((1 << bits_per_symbol) - 1)
    )
    for sample_index in range(len(samples)):
        for bit_index in range(bits_per_symbol):
            var local = (
                bit_index if bit_index < axis_bits
                else bit_index - axis_bits
            )
            var shift = axis_bits - local - 1
            var coordinate = (
                samples[sample_index].re
                if bit_index < axis_bits else samples[sample_index].im
            )
            var best_zero = 1.0e300
            var best_one = 1.0e300
            for gray in range(order):
                var level = Float64(
                    mask - 2 * _gray_to_binary(gray)
                ) / scale
                var distance = (coordinate - level) * (coordinate - level)
                if ((gray >> shift) & 1) == 0:
                    best_zero = min(best_zero, distance)
                else:
                    best_one = min(best_one, distance)
            result.append((best_one - best_zero) / noise_variance)
    return result^


def _idft_cp(
    spectrum: Span[Complex64, ...], cyclic_prefix: Int
) -> List[Complex64]:
    var time = List[Complex64](capacity=len(spectrum))
    for n in range(len(spectrum)):
        var value = Complex64(0.0, 0.0)
        for k in range(len(spectrum)):
            var angle = TWO_PI * Float64(n * k) / Float64(len(spectrum))
            var spectral_value = Complex64(spectrum[k].re, spectrum[k].im)
            value = value + spectral_value * Complex64(cos(angle), sin(angle))
        time.append(Complex64(
            value.re / Float64(len(spectrum)),
            value.im / Float64(len(spectrum)),
        ))
    var result = List[Complex64](capacity=len(time) + cyclic_prefix)
    for i in range(len(time) - cyclic_prefix, len(time)):
        result.append(time[i])
    for sample in time:
        result.append(sample)
    return result^


def _pilot_polarity(symbol_index: Int) -> Float64:
    var state = UInt8(0x7F)
    var polarity = 1.0
    for _ in range(symbol_index + 1):
        var feedback = ((state >> 6) ^ (state >> 3)) & 1
        polarity = 1.0 if feedback == 0 else -1.0
        state = ((state << 1) & 0x7E) | feedback
    return polarity


def _ht_pilots(symbol_index: Int) -> List[Complex64]:
    var p = _pilot_polarity(symbol_index)
    return [Complex64(p), Complex64(p), Complex64(p), Complex64(-p)]


def _vht_pilots(symbol_index: Int) -> List[Complex64]:
    # VHT uses the same four base signs, evaluated here as a distinct fixture.
    var p = _pilot_polarity(symbol_index)
    var base: List[Int] = [1, 1, 1, -1]
    var result = List[Complex64](capacity=4)
    for index in range(4):
        result.append(Complex64(p * Float64(base[index])))
    return result^


def _he_pilots(symbol_index: Int) -> List[Complex64]:
    var base: List[Int] = [1, 1, 1, -1, -1, 1, 1, 1]
    var result = List[Complex64](capacity=8)
    for i in range(8):
        result.append(Complex64(
            Float64(base[(i + symbol_index % 8) % 8])
        ))
    return result^


def _eht_pilots(symbol_index: Int) -> List[Complex64]:
    var base: List[Int] = [1, 1, 1, -1, -1, 1, 1, 1]
    var polarity = _pilot_polarity(symbol_index)
    var result = List[Complex64](capacity=8)
    for index in range(8):
        result.append(Complex64(
            polarity * Float64(base[(index + symbol_index % 8) % 8])
        ))
    return result^


def _ht_spectrum(
    data: Span[Complex64, ...], pilots: Span[Complex64, ...]
) -> List[Complex64]:
    var result = List[Complex64](length=64, fill=Complex64(0.0))
    var source = 0
    for subcarrier in range(-28, 29):
        if (
            subcarrier == 0
            or subcarrier == -21
            or subcarrier == -7
            or subcarrier == 7
            or subcarrier == 21
        ):
            continue
        result[subcarrier if subcarrier >= 0 else 64 + subcarrier] = (
            data[source]
        )
        source += 1
    var pilot_indices: List[Int] = [-21, -7, 7, 21]
    for i in range(4):
        var k = pilot_indices[i]
        result[k if k >= 0 else 64 + k] = pilots[i]
    return result^


def _vht_spectrum(
    data: Span[Complex64, ...], pilots: Span[Complex64, ...]
) -> List[Complex64]:
    var result = List[Complex64](length=64, fill=Complex64(0.0))
    var source = 0
    for subcarrier in range(-28, 29):
        if (
            subcarrier == 0
            or subcarrier == -21
            or subcarrier == -7
            or subcarrier == 7
            or subcarrier == 21
        ):
            continue
        result[subcarrier if subcarrier >= 0 else 64 + subcarrier] = data[source]
        source += 1
    var pilot_indices: List[Int] = [-21, -7, 7, 21]
    for index in range(4):
        var subcarrier = pilot_indices[index]
        result[
            subcarrier if subcarrier >= 0 else 64 + subcarrier
        ] = pilots[index]
    return result^


def _legacy_spectrum(data: Span[Complex64, ...]) -> List[Complex64]:
    var carriers: List[Int] = [
        -26, -25, -24, -23, -22, -20, -19, -18,
        -17, -16, -15, -14, -13, -12, -11, -10,
        -9, -8, -6, -5, -4, -3, -2, -1,
        1, 2, 3, 4, 5, 6, 8, 9,
        10, 11, 12, 13, 14, 15, 16, 17,
        18, 19, 20, 22, 23, 24, 25, 26,
    ]
    var result = List[Complex64](length=64, fill=Complex64(0.0))
    for i in range(48):
        var k = carriers[i]
        result[k if k >= 0 else 64 + k] = data[i]
    result[64 - 21] = Complex64(1.0)
    result[64 - 7] = Complex64(1.0)
    result[7] = Complex64(1.0)
    result[21] = Complex64(-1.0)
    return result^


def _ru242_spectrum(
    data: Span[Complex64, ...], pilots: Span[Complex64, ...]
) raises -> List[Complex64]:
    var pilot_indices: List[Int] = [-116, -90, -48, -22, 22, 48, 90, 116]
    var result = List[Complex64](length=256, fill=Complex64(0.0))
    var source = 0
    for subcarrier in range(-122, 123):
        if subcarrier == -1 or subcarrier == 0 or subcarrier == 1:
            continue
        var is_pilot = False
        for pilot in pilot_indices:
            if subcarrier == pilot:
                is_pilot = True
                break
        if not is_pilot:
            result[
                subcarrier if subcarrier >= 0 else 256 + subcarrier
            ] = data[source]
            source += 1
    for i in range(8):
        var k = pilot_indices[i]
        result[k if k >= 0 else 256 + k] = pilots[i]
    assert_equal(source, 234)
    return result^


def _static_ltf_values(
    count: Int, active_words: Span[UInt64, ...],
    negative_words: Span[UInt64, ...]
) -> List[Int]:
    var result = List[Int](capacity=count)
    for i in range(count):
        var mask = UInt64(1) << UInt64(i % 64)
        var active = (active_words[i // 64] & mask) != 0
        var negative = (negative_words[i // 64] & mask) != 0
        result.append(-1 if negative else (1 if active else 0))
    return result^


def _ht_ltf_spectrum() -> List[Complex64]:
    # Packed IEEE HT-LTF row, k=-28..28.  Bit i of ACTIVE/NEGATIVE states
    # whether the tone is nonzero/negative; this is an immutable fixture.
    var active: List[UInt64] = [UInt64(0x01FFFFFFEFFFFFFF)]
    var negative: List[UInt64] = [UInt64(0x018567D4C0A60530)]
    var values = _static_ltf_values(57, Span(active), Span(negative))
    var result = List[Complex64](length=64, fill=Complex64(0.0))
    for i in range(57):
        var k = -28 + i
        result[k if k >= 0 else 64 + k] = Complex64(Float64(values[i]))
    return result^


def _vht_ltf_spectrum() -> List[Complex64]:
    # Independent copy of the one-stream VHT-LTF row, k=-28..28.
    var active: List[UInt64] = [UInt64(0x01FFFFFFEFFFFFFF)]
    var negative: List[UInt64] = [UInt64(0x018567D4C0A60530)]
    var values = _static_ltf_values(57, Span(active), Span(negative))
    var result = List[Complex64](length=64, fill=Complex64(0.0))
    for index in range(57):
        var subcarrier = -28 + index
        result[
            subcarrier if subcarrier >= 0 else 64 + subcarrier
        ] = Complex64(Float64(values[index]))
    return result^


def _he_ltf_spectrum() -> List[Complex64]:
    # IEEE 802.11ax Eq. (27-43), k=-122..122, compact static fixture.
    var active: List[UInt64] = [
        UInt64(0xFFFFFFFFFFFFFFFF),
        UInt64(0xF1FFFFFFFFFFFFFF),
        UInt64(0xFFFFFFFFFFFFFFFF),
        UInt64(0x001FFFFFFFFFFFFF),
    ]
    var negative: List[UInt64] = [
        UInt64(0xF21D84D0A79F622B),
        UInt64(0x502E3EA237CFD7A6),
        UInt64(0x09ECBD7E7D88AD89),
        UInt64(0x00057720C35E9BC8),
    ]
    var values = _static_ltf_values(245, Span(active), Span(negative))
    var result = List[Complex64](length=256, fill=Complex64(0.0))
    for i in range(245):
        var k = -122 + i
        result[k if k >= 0 else 256 + k] = Complex64(Float64(values[i]))
    return result^


def _eht_ltf_spectrum() -> List[Complex64]:
    # IEEE 802.11be reuses the 20 MHz 4x training row; keep a distinct fixture.
    var active: List[UInt64] = [
        UInt64(0xFFFFFFFFFFFFFFFF),
        UInt64(0xF1FFFFFFFFFFFFFF),
        UInt64(0xFFFFFFFFFFFFFFFF),
        UInt64(0x001FFFFFFFFFFFFF),
    ]
    var negative: List[UInt64] = [
        UInt64(0xF21D84D0A79F622B),
        UInt64(0x502E3EA237CFD7A6),
        UInt64(0x09ECBD7E7D88AD89),
        UInt64(0x00057720C35E9BC8),
    ]
    var values = _static_ltf_values(245, Span(active), Span(negative))
    var result = List[Complex64](length=256, fill=Complex64(0.0))
    for index in range(245):
        var subcarrier = -122 + index
        result[
            subcarrier if subcarrier >= 0 else 256 + subcarrier
        ] = Complex64(Float64(values[index]))
    return result^


def _ht_ltf_waveform() -> List[Complex64]:
    var spectrum = _ht_ltf_spectrum()
    return _idft_cp(Span(spectrum), 16)


def _vht_ltf_waveform() -> List[Complex64]:
    var spectrum = _vht_ltf_spectrum()
    return _idft_cp(Span(spectrum), 16)


def _legacy_ltf_spectrum() -> List[Complex64]:
    var spectrum = _ht_ltf_spectrum()
    for k in [-28, -27, 27, 28]:
        spectrum[k if k >= 0 else 64 + k] = Complex64(0.0)
    return spectrum^


def _legacy_ltf_waveform() -> List[Complex64]:
    var spectrum = _legacy_ltf_spectrum()
    var symbol = _idft_cp(Span(spectrum), 0)
    var result = List[Complex64](capacity=160)
    for i in range(32, 64):
        result.append(symbol[i])
    for _ in range(2):
        for sample in symbol:
            result.append(sample)
    return result^


def _he_ltf_waveform() -> List[Complex64]:
    var spectrum = _he_ltf_spectrum()
    return _idft_cp(Span(spectrum), 16)


def _eht_ltf_waveform() -> List[Complex64]:
    var spectrum = _eht_ltf_spectrum()
    return _idft_cp(Span(spectrum), 16)


def _stf_waveform() -> List[Complex64]:
    var spectrum = List[Complex64](length=64, fill=Complex64(0.0))
    var scale = sqrt(13.0 / 6.0)
    var carriers: List[Int] = [
        -24, -20, -16, -12, -8, -4, 4, 8, 12, 16, 20, 24,
    ]
    var signs: List[Int] = [1, -1, 1, -1, -1, 1, -1, -1, 1, 1, 1, 1]
    for i in range(12):
        var k = carriers[i]
        var value = Float64(signs[i]) * scale
        spectrum[k if k >= 0 else 64 + k] = Complex64(value, value)
    var full = _idft_cp(Span(spectrum), 0)
    var result = List[Complex64](capacity=160)
    for _ in range(10):
        for i in range(16):
            result.append(full[i])
    return result^


def _legacy_signal(length_octets: Int) -> _Signal:
    var bits: List[UInt8] = [1, 1, 0, 1, 0]
    var parity = UInt8(1 ^ 1 ^ 0 ^ 1)
    for shift in range(12):
        var bit = UInt8((length_octets >> shift) & 1)
        bits.append(bit)
        parity ^= bit
    bits.append(parity)
    for _ in range(6):
        bits.append(UInt8(0))
    var coded = _bcc(Span(bits))
    var interleaved = _interleave(Span(coded), 1, 16, 3)
    var symbols = _qam(Span(interleaved), 1)
    var spectrum = _legacy_spectrum(Span(symbols))
    var waveform = _idft_cp(Span(spectrum), 16)
    return _Signal(
        bits^, coded^, interleaved^, symbols^, spectrum^, waveform^
    )


def _he_rate_matched_words() -> List[UInt64]:
    # Packed little-endian bit vector produced outside Mojo by an independent
    # GF(2) Gaussian encoder for N=1296, R=3/4, S=256, P=0, RPT=4.
    return [
        UInt64(0x8F7D3EB3DADF9836), UInt64(0xC9BC396E81489AA7),
        UInt64(0x4BDD879FDCE38649), UInt64(0xFC182D3B23BC8B62),
        UInt64(0x1462A0D728404F47), UInt64(0x9D14D0AC1DBD5D77),
        UInt64(0x4C00DC088CE6162F), UInt64(0x42E970903F52CDA3),
        UInt64(0xBEC65F88256BCD26), UInt64(0x10F8DB50D998EAB2),
        UInt64(0x3C7BE9F59ED6FE55), UInt64(0x4E4DE1CB740A44D5),
        UInt64(0x125EEC3CFEE71C32), UInt64(0xD1ADD35EE7B0145B),
        UInt64(0xA5A59E12CECA93F4), UInt64(0xF981676C54312C54),
        UInt64(0x36EBD6202C53F3D4), UInt64(0xB3D07177CF64A92A),
        UInt64(0xF8305A76477A7EFC), UInt64(0x28C541AE50809E8F),
        UInt64(0x3A29A1583B7ABAEE), UInt64(0x9801B81119CC2C5F),
        UInt64(0x85D2E1207EA59B46), UInt64(0x7D8CBF104AD79A4C),
        UInt64(0x21F1B6A1B331D565), UInt64(0x78F7D3EB3DADFCAA),
        UInt64(0x9C9BC396E81489AA), UInt64(0x24BDD879FDCE3864),
        UInt64(0x7FC182D3B23BC8B6), UInt64(0x71462A0D728404F4),
        UInt64(0xF9D14D0AC1DBD5D7), UInt64(0x25A78524722C072F),
        UInt64(0x97EF4AEAA195FC5F), UInt64(0x9CC30799DEC64DA4),
        UInt64(0xA6DA65D2296DC9AF), UInt64(0x02EB41F76EC2BD78),
        UInt64(0x0000000826293C4F),
    ]


def _eht_rate_matched_words() -> List[UInt64]:
    # Separate external GF(2) vector: N=1944, R=5/6, S=1080 over two blocks.
    return [
        UInt64(0x8F7D3EB3DADF9836), UInt64(0xC9BC396E81489AA7),
        UInt64(0x4BDD879FDCE38649), UInt64(0xFC182D3B23BC8B62),
        UInt64(0x1462A0D728404F47), UInt64(0x9D14D0AC1DBD5D77),
        UInt64(0x4C00DC088CE6162F), UInt64(0x42E970903F52CDA3),
        UInt64(0xBEC65F88256BCD26), UInt64(0x10F8DB50D998EAB2),
        UInt64(0x3C7BE9F59ED6FE55), UInt64(0x4E4DE1CB740A44D5),
        UInt64(0x125EEC3CFEE71C32), UInt64(0x3FE0C169D91DE45B),
        UInt64(0xB8A31506B942027A), UInt64(0x7CE8A68560EDEAEB),
        UInt64(0xF46006E0446730B1), UInt64(0xE42B2F87DC7E2E36),
        UInt64(0xD67C852A364E0E12), UInt64(0x80B524F59EECF18F),
        UInt64(0x79CBF29031726A91), UInt64(0xAC48EFF86F95523F),
        UInt64(0x2174B8481FA966D1), UInt64(0x5F632FC412B5E693),
        UInt64(0x887C6DA86CCC7559), UInt64(0x9E3DF4FACF6B7F2A),
        UInt64(0x2726F0E5BA05226A), UInt64(0x892F761E7F738E19),
        UInt64(0x1FF060B4EC8EF22D), UInt64(0xDC518A835CA1013D),
        UInt64(0xBE745342B076F575), UInt64(0x8D30037022339858),
        UInt64(0x990BA5C240FD4B36), UInt64(0xCAFB197E2095AF34),
        UInt64(0x5443E36D436663AA), UInt64(0x54F1EFA7D67B5BF9),
        UInt64(0xC93937872DD02913), UInt64(0x6C497BB0F3FB9C70),
        UInt64(0xFA63C45F12C47791), UInt64(0x8BC0E47477F09003),
        UInt64(0x064A29AB84E9D48D), UInt64(0x3CD94116BBE8DF1D),
        UInt64(0xF772B918ED4384DF), UInt64(0x005839218900F5C7),
    ]


def _unpack(words: Span[UInt64, ...], bit_count: Int) -> List[UInt8]:
    var result = List[UInt8](capacity=bit_count)
    for i in range(bit_count):
        result.append(UInt8(
            (words[i // 64] >> UInt64(i % 64)) & UInt64(1)
        ))
    return result^


def _tone_map(
    bits: Span[UInt8, ...], bits_per_subcarrier: Int
) -> List[UInt8]:
    var result = List[UInt8](length=len(bits), fill=UInt8(0))
    for source_tone in range(234):
        var destination_tone = (
            9 * (source_tone % 26) + (source_tone * 9) // 234
        )
        for bit in range(bits_per_subcarrier):
            result[destination_tone * bits_per_subcarrier + bit] = bits[
                source_tone * bits_per_subcarrier + bit
            ]
    return result^


def _tone_demap_llrs(
    llrs: Span[Float64, ...], bits_per_subcarrier: Int
) -> List[Float64]:
    var result = List[Float64](length=len(llrs), fill=0.0)
    for source_tone in range(234):
        var destination_tone = (
            9 * (source_tone % 26) + (source_tone * 9) // 234
        )
        for bit in range(bits_per_subcarrier):
            result[source_tone * bits_per_subcarrier + bit] = llrs[
                destination_tone * bits_per_subcarrier + bit
            ]
    return result^


def _he_rate_recover(llrs: Span[Float64, ...]) raises -> List[Float64]:
    # Two N=1296, K=972 blocks.  Each has 128 shortened information bits,
    # no puncturing, and two repetitions from the start of its base block.
    var result = List[Float64](capacity=2592)
    var source = 0
    for _ in range(2):
        var recovered = List[Float64](length=1296, fill=0.0)
        for i in range(844):
            recovered[i] = llrs[source]
            source += 1
        for i in range(844, 972):
            recovered[i] = 50.0
        for i in range(324):
            recovered[972 + i] = llrs[source]
            source += 1
        recovered[0] += llrs[source]
        source += 1
        recovered[1] += llrs[source]
        source += 1
        for value in recovered:
            result.append(value)
    assert_equal(source, len(llrs))
    return result^


def _eht_rate_recover(llrs: Span[Float64, ...]) raises -> List[Float64]:
    # Two N=1944, K=1620 blocks with 540 shortened information bits each.
    var result = List[Float64](capacity=3888)
    var source = 0
    for _ in range(2):
        var recovered = List[Float64](length=1944, fill=0.0)
        for index in range(1080):
            recovered[index] = llrs[source]
            source += 1
        for index in range(1080, 1620):
            recovered[index] = 50.0
        for index in range(324):
            recovered[1620 + index] = llrs[source]
            source += 1
        for value in recovered:
            result.append(value)
    assert_equal(source, len(llrs))
    return result^


def _bcc_fixture(symbol_index: Int) -> _BCCData:
    var payload = _ascii_123456789()
    var framed = _frame(Span(payload))
    var frame = framed.bits.copy()
    var checksum = framed.fcs
    var field = frame.copy()
    var tail_start = len(field)
    for _ in range(6):
        field.append(UInt8(0))
    while len(field) < 234:
        field.append(UInt8(0))
    var scrambled = _scramble(Span(field), UInt8(0x5D))
    for i in range(tail_start, tail_start + 6):
        scrambled[i] = UInt8(0)
    var expected_decoded = _scramble(Span(scrambled), UInt8(0x5D))
    var mother = _bcc(Span(scrambled))
    var punctured = _puncture_three_quarters(Span(mother))
    var interleaved = _interleave(Span(punctured), 6, 13, 4)
    var symbols = _qam(Span(interleaved), 6)
    var pilots = _ht_pilots(symbol_index)
    var spectrum = _ht_spectrum(Span(symbols), Span(pilots))
    var waveform = _idft_cp(Span(spectrum), 16)
    return _BCCData(
        payload^,
        frame^,
        scrambled^,
        expected_decoded^,
        punctured^,
        interleaved^,
        symbols^,
        spectrum^,
        waveform^,
        checksum,
    )


def _vht_mcs8_fixture(symbol_index: Int) -> _BCCData:
    # Fresh VHT MCS-8 construction: Ndbps=312 and Ncbps=416.
    var payload = _payload(31, 0x35)
    var framed = _frame(Span(payload))
    var frame = framed.bits.copy()
    var checksum = framed.fcs
    var field = frame.copy()
    var tail_start = len(field)
    for _ in range(6):
        field.append(UInt8(0))
    while len(field) < 312:
        field.append(UInt8(0))
    var scrambled = _scramble(Span(field), UInt8(0x5D))
    for index in range(tail_start, tail_start + 6):
        scrambled[index] = UInt8(0)
    var expected_decoded = _scramble(Span(scrambled), UInt8(0x5D))
    var mother = _bcc(Span(scrambled))
    var punctured = _puncture_three_quarters(Span(mother))
    var interleaved = _interleave(Span(punctured), 8, 13, 4)
    var symbols = _qam(Span(interleaved), 8)
    var pilots = _vht_pilots(symbol_index)
    var spectrum = _vht_spectrum(Span(symbols), Span(pilots))
    var waveform = _idft_cp(Span(spectrum), 16)
    return _BCCData(
        payload^,
        frame^,
        scrambled^,
        expected_decoded^,
        punctured^,
        interleaved^,
        symbols^,
        spectrum^,
        waveform^,
        checksum,
    )


def _ldpc_fixture(symbol_index: Int) raises -> _LDPCData:
    var payload = _payload(205, 0x62)
    var framed = _frame(Span(payload))
    var frame = framed.bits.copy()
    var checksum = framed.fcs
    var words = _he_rate_matched_words()
    var rate_matched = _unpack(Span(words), 2340)
    var tone_mapped = _tone_map(Span(rate_matched), 10)
    var symbols = _qam(Span(tone_mapped), 10)
    var pilots = _he_pilots(symbol_index)
    var spectrum = _ru242_spectrum(Span(symbols), Span(pilots))
    var waveform = _idft_cp(Span(spectrum), 16)
    return _LDPCData(
        payload^,
        frame^,
        rate_matched^,
        tone_mapped^,
        symbols^,
        spectrum^,
        waveform^,
        checksum,
    )


def _eht_mcs13_fixture(symbol_index: Int) raises -> _LDPCData:
    var payload = _payload(264, 4)
    var framed = _frame(Span(payload))
    var frame = framed.bits.copy()
    var checksum = framed.fcs
    var words = _eht_rate_matched_words()
    var rate_matched = _unpack(Span(words), 2808)
    var tone_mapped = _tone_map(Span(rate_matched), 12)
    var symbols = _qam(Span(tone_mapped), 12)
    var pilots = _eht_pilots(symbol_index)
    var spectrum = _ru242_spectrum(Span(symbols), Span(pilots))
    var waveform = _idft_cp(Span(spectrum), 16)
    return _LDPCData(
        payload^,
        frame^,
        rate_matched^,
        tone_mapped^,
        symbols^,
        spectrum^,
        waveform^,
        checksum,
    )


def _flat(samples: Span[Complex64, ...], h: Complex64) -> List[Complex64]:
    var result = List[Complex64](capacity=len(samples))
    for i in range(len(samples)):
        var sample = Complex64(samples[i].re, samples[i].im)
        result.append(sample * h)
    return result^


def _inject(
    packet: Span[Complex64, ...], delay: Int, cfo: Float64, h: Complex64
) -> List[Complex64]:
    var result = List[Complex64](capacity=delay + len(packet))
    for _ in range(delay):
        result.append(Complex64(0.0))
    for i in range(len(packet)):
        var n = delay + i
        var phase = TWO_PI * cfo * Float64(n)
        var sample = Complex64(packet[i].re, packet[i].im)
        result.append(sample * h * Complex64(cos(phase), sin(phase)))
    return result^


def _flat_delayed(
    packet: Span[Complex64, ...], delay: Int, h: Complex64
) -> List[Complex64]:
    var result = List[Complex64](capacity=delay + len(packet))
    for _ in range(delay):
        result.append(Complex64(0.0))
    for i in range(len(packet)):
        var sample = Complex64(packet[i].re, packet[i].im)
        result.append(sample * h)
    return result^


def _append(mut target: List[Complex64], source: Span[Complex64, ...]):
    for i in range(len(source)):
        target.append(Complex64(source[i].re, source[i].im))


def _channel_from_training(
    training_spectrum: Span[Complex64, ...], h: Complex64
) -> List[Complex64]:
    var result = List[Complex64](capacity=len(training_spectrum))
    for i in range(len(training_spectrum)):
        var value = Complex64(
            training_spectrum[i].re, training_spectrum[i].im
        )
        result.append(
            h if value.magnitude_squared() > 0.0
            else Complex64(0.0)
        )
    return result^


def _assert_close(
    actual: Float64, expected: Float64, abs_tol: Float64, rel_tol: Float64
) raises:
    assert_true(
        abs(actual - expected)
        <= abs_tol + rel_tol * max(abs(actual), abs(expected))
    )


def _assert_complex_list_close(
    actual: List[Complex64], expected: List[Complex64],
    abs_tol: Float64 = SAMPLE_ABS_TOL,
    rel_tol: Float64 = SAMPLE_REL_TOL,
) raises:
    assert_equal(len(actual), len(expected))
    for i in range(len(actual)):
        _assert_close(actual[i].re, expected[i].re, abs_tol, rel_tol)
        _assert_close(actual[i].im, expected[i].im, abs_tol, rel_tol)


def _assert_float_list_close(
    actual: List[Float64], expected: List[Float64],
    abs_tol: Float64 = LLR_ABS_TOL,
    rel_tol: Float64 = LLR_REL_TOL,
) raises:
    assert_equal(len(actual), len(expected))
    for i in range(len(actual)):
        _assert_close(actual[i], expected[i], abs_tol, rel_tol)


def _assert_metadata_common(
    testcase: StringSlice,
    stages: List[String],
    shapes: List[String],
    metadata: List[CheckpointMetadata],
) raises:
    assert_equal(len(metadata), len(stages))
    assert_equal(len(metadata), len(shapes))
    for i in range(len(metadata)):
        assert_equal(metadata[i].testcase_id, testcase)
        assert_equal(metadata[i].stage, stages[i])
        assert_equal(metadata[i].shape, shapes[i])
        assert_equal(metadata[i].stride, "1")
        assert_equal(metadata[i].scale, 1.0)
        assert_equal(metadata[i].version, 1)
        assert_true(metadata[i].dtype.byte_length() > 0)
        assert_true(metadata[i].q_format.byte_length() > 0)
        assert_true(metadata[i].layout.byte_length() > 0)


def test_wifi_bcc_rx_20mhz_manual_ht_bcc_oracle() raises:
    """Decode an HT MCS-6 waveform built only from scalar IEEE formulas."""
    var symbol_index = 3
    var fixture = _bcc_fixture(symbol_index)
    assert_equal(fixture.fcs, UInt64(0xCBF43926))
    var h = Complex64(0.73, -0.29)
    var samples = _flat(Span(fixture.waveform), h)
    var ltf = _ht_ltf_waveform()
    var received_ltf = _flat(Span(ltf), h)
    var rx = wifi_bcc_rx_20mhz(
        Span(samples),
        Span(received_ltf),
        WIFI_PHY_HT,
        6,
        len(fixture.payload),
        symbol_index=symbol_index,
    )

    assert_equal(rx.demapped_bits, fixture.interleaved)
    assert_equal(rx.deinterleaved_bits, fixture.punctured)
    assert_equal(rx.decoded_bits, fixture.expected_decoded)
    assert_equal(rx.payload_bits, fixture.payload)
    _assert_complex_list_close(rx.corrected_data_symbols, fixture.symbols)
    var ltf_spectrum = _ht_ltf_spectrum()
    var expected_channel = _channel_from_training(Span(ltf_spectrum), h)
    _assert_complex_list_close(rx.channel_estimate, expected_channel)
    _assert_complex_list_close(rx.equalized_spectrum, fixture.spectrum)
    _assert_close(rx.common_phase, 0.0, PHASE_TOL, 0.0)
    _assert_close(rx.phase_slope, 0.0, PHASE_TOL, 0.0)
    assert_equal(rx.received_fcs, UInt64(0xCBF43926))
    assert_equal(rx.computed_fcs, UInt64(0xCBF43926))
    assert_true(rx.service_ok)
    assert_true(rx.fcs_ok)


def test_wifi_ldpc_rx_20mhz_external_he_qc_ldpc_oracle() raises:
    """Decode an external HE MCS-10 QC-LDPC vector without a Mojo TX."""
    var symbol_index = 4
    var noise_variance = 0.01
    var fixture = _ldpc_fixture(symbol_index)
    assert_equal(fixture.fcs, UInt64(0x7F2CB07E))
    var h = Complex64(0.82, 0.21)
    var samples = _flat(Span(fixture.waveform), h)
    var ltf = _he_ltf_waveform()
    var received_ltf = _flat(Span(ltf), h)
    var rx = wifi_ldpc_rx_20mhz(
        Span(samples),
        Span(received_ltf),
        WIFI_PHY_HE,
        10,
        len(fixture.payload),
        noise_variance,
        symbol_index=symbol_index,
        max_iterations=8,
    )

    var physical_llrs = _maxlog_llrs(
        Span(fixture.symbols), 10, noise_variance
    )
    var expected_demapped = _tone_demap_llrs(Span(physical_llrs), 10)
    var expected_recovered = _he_rate_recover(Span(expected_demapped))
    _assert_complex_list_close(rx.corrected_data_symbols, fixture.symbols)
    _assert_float_list_close(rx.physical_llrs, physical_llrs)
    _assert_float_list_close(rx.demapped_llrs, expected_demapped)
    _assert_float_list_close(rx.rate_recovered_llrs, expected_recovered)
    assert_equal(rx.decoded_frame_bits, fixture.frame)
    assert_equal(rx.payload_bits, fixture.payload)
    var ltf_spectrum = _he_ltf_spectrum()
    var expected_channel = _channel_from_training(Span(ltf_spectrum), h)
    _assert_complex_list_close(rx.channel_estimate, expected_channel)
    _assert_complex_list_close(rx.equalized_spectrum, fixture.spectrum)
    _assert_close(rx.common_phase, 0.0, PHASE_TOL, 0.0)
    _assert_close(rx.phase_slope, 0.0, PHASE_TOL, 0.0)
    assert_equal(rx.ldpc_block_length, 1296)
    assert_true(rx.ldpc_converged)
    assert_equal(rx.received_fcs, UInt64(0x7F2CB07E))
    assert_equal(rx.computed_fcs, UInt64(0x7F2CB07E))
    assert_true(rx.service_ok)
    assert_true(rx.fcs_ok)


def test_wifi_acquisition_rx_20mhz_manual_ht_packet_oracle() raises:
    """Acquire a hand-built L-STF/HT-LTF/L-SIG/DATA packet under h/CFO."""
    var symbol_index = 3
    var noise_variance = 0.01
    var data = _bcc_fixture(symbol_index)
    var stf = _stf_waveform()
    var ltf = _ht_ltf_waveform()
    var signal = _legacy_signal(13)
    var packet = List[Complex64](capacity=400)
    _append(packet, Span(stf))
    _append(packet, Span(ltf))
    _append(packet, Span(signal.waveform))
    _append(packet, Span(data.waveform))
    assert_equal(len(packet), 400)

    var delay = 7
    var cfo = 0.00125
    var h = Complex64(0.88, -0.34)
    var observation = _inject(Span(packet), delay, cfo, h)
    var expected_corrected = _flat_delayed(Span(packet), delay, h)
    var rx = wifi_acquisition_rx_20mhz(
        Span(observation),
        WIFI_PHY_HT,
        6,
        len(data.payload),
        symbol_index=symbol_index,
        detection_threshold=0.82,
        llr_noise_variance=noise_variance,
        testcase_id="wifi-rx-independent-ht",
    )

    assert_true(abs(rx.packet_start - delay) <= 2)
    assert_true(rx.stf_metric >= 0.82)
    _assert_close(rx.coarse_cfo + rx.fine_cfo, cfo, 2.0e-12, 0.0)
    _assert_close(rx.fine_cfo, 0.0, 2.0e-12, 0.0)
    assert_equal(rx.ltf_start, delay + 160)
    assert_equal(rx.signal_start, delay + 240)
    assert_equal(rx.data_start, delay + 320)
    _assert_complex_list_close(
        rx.cfo_corrected_samples, expected_corrected, 2.0e-9, 2.0e-9
    )
    var expected_ltf = _flat(Span(ltf), h)
    var expected_signal_samples = _flat(Span(signal.waveform), h)
    var expected_data_samples = _flat(Span(data.waveform), h)
    _assert_complex_list_close(rx.ltf_samples, expected_ltf)
    _assert_complex_list_close(rx.signal_samples, expected_signal_samples)
    _assert_complex_list_close(rx.data_samples, expected_data_samples)

    var ltf_spectrum = _ht_ltf_spectrum()
    var expected_channel = _channel_from_training(Span(ltf_spectrum), h)
    _assert_complex_list_close(rx.channel_estimate, expected_channel)
    _assert_complex_list_close(rx.signal_equalized_spectrum, signal.spectrum)
    _assert_complex_list_close(rx.signal_corrected_symbols, signal.symbols)
    var signal_llrs = _maxlog_llrs(
        Span(signal.symbols), 1, noise_variance
    )
    var signal_deinterleaved = _deinterleave_llrs(
        Span(signal_llrs), 1, 16, 3
    )
    _assert_float_list_close(rx.signal_llrs, signal_llrs)
    _assert_float_list_close(
        rx.signal_deinterleaved_llrs, signal_deinterleaved
    )
    assert_equal(rx.signal_decoded_bits, signal.bits)
    assert_equal(rx.signal_rate_bits, [UInt8(1), 1, 0, 1])
    assert_equal(rx.signal_decoded_fields, [13, 0, 13, 1, 1, 1, 1])
    assert_equal(rx.signal_length_octets, 13)
    assert_true(
        rx.signal_reserved_ok and rx.signal_parity_ok
        and rx.signal_tail_ok and rx.signal_rate_ok
        and rx.signal_length_ok and rx.signal_ok
    )

    _assert_complex_list_close(rx.equalized_spectrum, data.spectrum)
    _assert_complex_list_close(rx.corrected_data_symbols, data.symbols)
    var data_llrs = _maxlog_llrs(
        Span(data.symbols), 6, noise_variance
    )
    var deinterleaved = _deinterleave_llrs(
        Span(data_llrs), 6, 13, 4
    )
    var mother = _depuncture_three_quarters(Span(deinterleaved), 468)
    _assert_float_list_close(rx.qam_llrs, data_llrs)
    _assert_float_list_close(rx.deinterleaved_llrs, deinterleaved)
    _assert_float_list_close(rx.mother_llrs, mother)
    assert_equal(rx.decoded_bits, data.expected_decoded)
    assert_equal(rx.payload_bits, data.payload)
    assert_equal(rx.received_fcs, UInt64(0xCBF43926))
    assert_equal(rx.computed_fcs, UInt64(0xCBF43926))
    assert_true(rx.service_ok and rx.fcs_ok)
    _assert_close(rx.signal_common_phase, 0.0, PHASE_TOL, 0.0)
    _assert_close(rx.signal_phase_slope, 0.0, PHASE_TOL, 0.0)
    _assert_close(rx.common_phase, 0.0, PHASE_TOL, 0.0)
    _assert_close(rx.phase_slope, 0.0, PHASE_TOL, 0.0)

    var stages: List[String] = [
        "cfo-corrected-samples",
        "ltf-samples",
        "legacy-signal-samples",
        "data-samples",
        "channel-estimate",
        "legacy-signal-equalized-spectrum",
        "legacy-signal-pilot-corrected-symbols",
        "legacy-signal-llrs",
        "legacy-signal-deinterleaved-llrs",
        "legacy-signal-decoded-bits",
        "legacy-signal-rate-bits",
        "legacy-signal-decoded-fields",
        "data-equalized-spectrum",
        "data-pilot-corrected-symbols",
        "qam-llrs",
        "deinterleaved-llrs",
        "depunctured-mother-llrs",
        "decoded-data-field-bits",
        "payload-bits",
    ]
    var shapes: List[String] = [
        "407", "80", "80", "80", "64", "64", "48", "48", "48",
        "24", "4", "7", "64", "52", "312", "312", "468", "234", "72",
    ]
    _assert_metadata_common(
        "wifi-rx-independent-ht", stages, shapes, rx.checkpoint_metadata
    )


def test_wifi_acquisition_rx_20mhz_manual_vht_mcs8_packet_oracle() raises:
    """Acquire a fresh scalar-formula VHT MCS-8 packet under explicit h/CFO."""
    var symbol_index = 6
    var noise_variance = 0.01
    var data = _vht_mcs8_fixture(symbol_index)
    assert_equal(data.fcs, UInt64(0xC46BE2BE))
    var stf = _stf_waveform()
    var ltf = _vht_ltf_waveform()
    var signal = _legacy_signal(35)
    var packet = List[Complex64](capacity=400)
    _append(packet, Span(stf))
    _append(packet, Span(ltf))
    _append(packet, Span(signal.waveform))
    _append(packet, Span(data.waveform))
    assert_equal(len(packet), 400)

    var delay = 6
    var cfo = 0.001125
    var h = Complex64(0.76, 0.31)
    var observation = _inject(Span(packet), delay, cfo, h)
    var expected_corrected = _flat_delayed(Span(packet), delay, h)
    var rx = wifi_acquisition_rx_20mhz(
        Span(observation),
        WIFI_PHY_VHT,
        8,
        len(data.payload),
        symbol_index=symbol_index,
        detection_threshold=0.82,
        llr_noise_variance=noise_variance,
        testcase_id="wifi-rx-independent-vht-mcs8",
    )

    assert_true(abs(rx.packet_start - delay) <= 2)
    assert_true(rx.stf_metric >= 0.82)
    _assert_close(rx.coarse_cfo + rx.fine_cfo, cfo, 2.0e-12, 0.0)
    _assert_close(rx.fine_cfo, 0.0, 2.0e-12, 0.0)
    assert_equal(rx.ltf_start, delay + 160)
    assert_equal(rx.signal_start, delay + 240)
    assert_equal(rx.data_start, delay + 320)
    _assert_complex_list_close(
        rx.cfo_corrected_samples, expected_corrected, 2.0e-9, 2.0e-9
    )
    var expected_ltf = _flat(Span(ltf), h)
    var expected_signal_samples = _flat(Span(signal.waveform), h)
    var expected_data_samples = _flat(Span(data.waveform), h)
    _assert_complex_list_close(rx.ltf_samples, expected_ltf)
    _assert_complex_list_close(rx.signal_samples, expected_signal_samples)
    _assert_complex_list_close(rx.data_samples, expected_data_samples)

    var ltf_spectrum = _vht_ltf_spectrum()
    var expected_channel = _channel_from_training(Span(ltf_spectrum), h)
    _assert_complex_list_close(rx.channel_estimate, expected_channel)
    _assert_complex_list_close(rx.signal_equalized_spectrum, signal.spectrum)
    _assert_complex_list_close(rx.signal_corrected_symbols, signal.symbols)
    var signal_llrs = _maxlog_llrs(
        Span(signal.symbols), 1, noise_variance
    )
    var signal_deinterleaved = _deinterleave_llrs(
        Span(signal_llrs), 1, 16, 3
    )
    _assert_float_list_close(rx.signal_llrs, signal_llrs)
    _assert_float_list_close(
        rx.signal_deinterleaved_llrs, signal_deinterleaved
    )
    assert_equal(rx.signal_decoded_bits, signal.bits)
    assert_equal(rx.signal_rate_bits, [UInt8(1), 1, 0, 1])
    assert_equal(rx.signal_decoded_fields, [13, 0, 35, 1, 1, 1, 1])
    assert_equal(rx.signal_length_octets, 35)
    assert_true(
        rx.signal_reserved_ok and rx.signal_parity_ok
        and rx.signal_tail_ok and rx.signal_rate_ok
        and rx.signal_length_ok and rx.signal_ok
    )

    _assert_complex_list_close(rx.equalized_spectrum, data.spectrum)
    _assert_complex_list_close(rx.corrected_data_symbols, data.symbols)
    var data_llrs = _maxlog_llrs(
        Span(data.symbols), 8, noise_variance
    )
    var deinterleaved = _deinterleave_llrs(
        Span(data_llrs), 8, 13, 4
    )
    var mother = _depuncture_three_quarters(Span(deinterleaved), 624)
    _assert_float_list_close(rx.qam_llrs, data_llrs)
    _assert_float_list_close(rx.deinterleaved_llrs, deinterleaved)
    _assert_float_list_close(rx.mother_llrs, mother)
    assert_equal(rx.decoded_bits, data.expected_decoded)
    assert_equal(rx.payload_bits, data.payload)
    assert_equal(rx.received_fcs, data.fcs)
    assert_equal(rx.computed_fcs, data.fcs)
    assert_true(rx.service_ok and rx.fcs_ok)
    _assert_close(rx.signal_common_phase, 0.0, PHASE_TOL, 0.0)
    _assert_close(rx.signal_phase_slope, 0.0, PHASE_TOL, 0.0)
    _assert_close(rx.common_phase, 0.0, PHASE_TOL, 0.0)
    _assert_close(rx.phase_slope, 0.0, PHASE_TOL, 0.0)

    var stages: List[String] = [
        "cfo-corrected-samples",
        "ltf-samples",
        "legacy-signal-samples",
        "data-samples",
        "channel-estimate",
        "legacy-signal-equalized-spectrum",
        "legacy-signal-pilot-corrected-symbols",
        "legacy-signal-llrs",
        "legacy-signal-deinterleaved-llrs",
        "legacy-signal-decoded-bits",
        "legacy-signal-rate-bits",
        "legacy-signal-decoded-fields",
        "data-equalized-spectrum",
        "data-pilot-corrected-symbols",
        "qam-llrs",
        "deinterleaved-llrs",
        "depunctured-mother-llrs",
        "decoded-data-field-bits",
        "payload-bits",
    ]
    var shapes: List[String] = [
        "406", "80", "80", "80", "64", "64", "48", "48", "48",
        "24", "4", "7", "64", "52", "416", "416", "624", "312",
        "248",
    ]
    _assert_metadata_common(
        "wifi-rx-independent-vht-mcs8",
        stages,
        shapes,
        rx.checkpoint_metadata,
    )


def test_wifi_he_eht_acquisition_rx_20mhz_manual_he_packet_oracle() raises:
    """Acquire hand-built legacy fields plus HE-LTF and external LDPC DATA."""
    var symbol_index = 4
    var noise_variance = 0.01
    var data = _ldpc_fixture(symbol_index)
    var stf = _stf_waveform()
    var legacy_ltf = _legacy_ltf_waveform()
    var signal = _legacy_signal(209)
    var he_ltf = _he_ltf_waveform()
    var packet = List[Complex64](capacity=944)
    _append(packet, Span(stf))
    _append(packet, Span(legacy_ltf))
    _append(packet, Span(signal.waveform))
    _append(packet, Span(he_ltf))
    _append(packet, Span(data.waveform))
    assert_equal(len(packet), 944)

    var delay = 9
    var cfo = -0.001
    var h = Complex64(0.79, 0.26)
    var observation = _inject(Span(packet), delay, cfo, h)
    var expected_corrected = _flat_delayed(Span(packet), delay, h)
    var rx = wifi_he_eht_acquisition_rx_20mhz(
        Span(observation),
        WIFI_PHY_HE,
        10,
        len(data.payload),
        symbol_index=symbol_index,
        detection_threshold=0.82,
        llr_noise_variance=noise_variance,
        max_iterations=8,
        testcase_id="wifi-rx-independent-he",
    )

    assert_true(abs(rx.packet_start - delay) <= 2)
    assert_true(rx.stf_metric >= 0.82)
    _assert_close(rx.coarse_cfo + rx.fine_cfo, cfo, 2.0e-12, 0.0)
    _assert_close(rx.fine_cfo, 0.0, 2.0e-12, 0.0)
    assert_equal(rx.legacy_ltf_start, delay + 160)
    assert_equal(rx.signal_start, delay + 320)
    assert_equal(rx.he_eht_ltf_start, delay + 400)
    assert_equal(rx.data_start, delay + 672)
    assert_true(rx.he_eht_ltf_metric >= 1.0 - 2.0e-12)
    _assert_complex_list_close(
        rx.coarse_corrected_samples, expected_corrected, 2.0e-9, 2.0e-9
    )
    _assert_complex_list_close(
        rx.corrected_samples, expected_corrected, 2.0e-9, 2.0e-9
    )
    var expected_legacy_ltf = _flat(Span(legacy_ltf), h)
    var expected_signal_samples = _flat(Span(signal.waveform), h)
    var expected_he_ltf = _flat(Span(he_ltf), h)
    var expected_data_samples = _flat(Span(data.waveform), h)
    _assert_complex_list_close(rx.legacy_ltf_samples, expected_legacy_ltf)
    _assert_complex_list_close(rx.signal_samples, expected_signal_samples)
    _assert_complex_list_close(rx.he_eht_ltf_samples, expected_he_ltf)
    _assert_complex_list_close(rx.data_samples, expected_data_samples)

    var legacy_ltf_spectrum = _legacy_ltf_spectrum()
    var expected_legacy_channel = _channel_from_training(
        Span(legacy_ltf_spectrum), h
    )
    _assert_complex_list_close(
        rx.legacy_channel_estimate, expected_legacy_channel
    )
    _assert_complex_list_close(rx.signal_equalized_spectrum, signal.spectrum)
    _assert_complex_list_close(rx.signal_corrected_symbols, signal.symbols)
    assert_equal(rx.signal_deinterleaved_bits, signal.coded)
    assert_equal(rx.signal_decoded_bits, signal.bits)
    assert_equal(rx.signal_length_octets, 209)
    assert_true(
        rx.signal_reserved_ok and rx.signal_parity_ok
        and rx.signal_tail_ok and rx.signal_rate_ok
        and rx.signal_length_ok and rx.signal_ok
    )
    var he_ltf_spectrum = _he_ltf_spectrum()
    var expected_he_channel = _channel_from_training(Span(he_ltf_spectrum), h)
    _assert_complex_list_close(
        rx.he_eht_channel_estimate, expected_he_channel
    )

    var physical_llrs = _maxlog_llrs(
        Span(data.symbols), 10, noise_variance
    )
    var expected_demapped = _tone_demap_llrs(Span(physical_llrs), 10)
    var expected_recovered = _he_rate_recover(Span(expected_demapped))
    _assert_complex_list_close(rx.data.equalized_spectrum, data.spectrum)
    _assert_complex_list_close(rx.data.corrected_data_symbols, data.symbols)
    _assert_float_list_close(rx.data.physical_llrs, physical_llrs)
    _assert_float_list_close(rx.data.demapped_llrs, expected_demapped)
    _assert_float_list_close(
        rx.data.rate_recovered_llrs, expected_recovered
    )
    assert_equal(rx.data.decoded_frame_bits, data.frame)
    assert_equal(rx.data.payload_bits, data.payload)
    assert_equal(rx.data.ldpc_block_length, 1296)
    assert_true(rx.data.ldpc_converged)
    assert_equal(rx.data.received_fcs, UInt64(0x7F2CB07E))
    assert_equal(rx.data.computed_fcs, UInt64(0x7F2CB07E))
    assert_true(rx.data.service_ok and rx.data.fcs_ok)

    var stages: List[String] = [
        "coarse-cfo-corrected-samples",
        "fine-cfo-corrected-samples",
        "legacy-ltf-samples",
        "legacy-channel-estimate",
        "legacy-signal-samples",
        "legacy-signal-equalized-spectrum",
        "legacy-signal-pilot-corrected-symbols",
        "he-eht-ltf-samples",
        "he-eht-channel-estimate",
        "data-samples",
        "data-equalized-spectrum",
        "legacy-signal-deinterleaved-bits",
        "legacy-signal-decoded-bits",
        "decoded-data-field-bits",
        "payload-bits",
        "ldpc-rate-recovered-llrs",
    ]
    var shapes: List[String] = [
        "953", "953", "160", "64", "80", "64", "48", "272", "256",
        "272", "256", "48", "24", "1688", "1640", "2592",
    ]
    _assert_metadata_common(
        "wifi-rx-independent-he", stages, shapes, rx.checkpoint_metadata
    )
    for index in range(len(rx.data.checkpoint_metadata)):
        assert_equal(
            rx.data.checkpoint_metadata[index].testcase_id,
            "wifi-rx-independent-he",
        )


def test_wifi_he_eht_acquisition_rx_20mhz_manual_eht_mcs13_packet_oracle(
) raises:
    """Acquire a distinct EHT MCS-13 packet backed by an external LDPC vector."""
    var symbol_index = 4
    var noise_variance = 0.01
    var data = _eht_mcs13_fixture(symbol_index)
    assert_equal(data.fcs, UInt64(0x615CE108))
    var stf = _stf_waveform()
    var legacy_ltf = _legacy_ltf_waveform()
    var signal = _legacy_signal(268)
    var eht_ltf = _eht_ltf_waveform()
    var packet = List[Complex64](capacity=944)
    _append(packet, Span(stf))
    _append(packet, Span(legacy_ltf))
    _append(packet, Span(signal.waveform))
    _append(packet, Span(eht_ltf))
    _append(packet, Span(data.waveform))
    assert_equal(len(packet), 944)

    var delay = 11
    var cfo = 0.000875
    var h = Complex64(0.84, -0.23)
    var observation = _inject(Span(packet), delay, cfo, h)
    var expected_corrected = _flat_delayed(Span(packet), delay, h)
    var rx = wifi_he_eht_acquisition_rx_20mhz(
        Span(observation),
        WIFI_PHY_EHT,
        13,
        len(data.payload),
        symbol_index=symbol_index,
        detection_threshold=0.82,
        llr_noise_variance=noise_variance,
        max_iterations=10,
        testcase_id="wifi-rx-independent-eht-mcs13",
    )

    assert_true(abs(rx.packet_start - delay) <= 2)
    assert_true(rx.stf_metric >= 0.82)
    _assert_close(rx.coarse_cfo + rx.fine_cfo, cfo, 2.0e-12, 0.0)
    _assert_close(rx.fine_cfo, 0.0, 2.0e-12, 0.0)
    assert_equal(rx.legacy_ltf_start, delay + 160)
    assert_equal(rx.signal_start, delay + 320)
    assert_equal(rx.he_eht_ltf_start, delay + 400)
    assert_equal(rx.data_start, delay + 672)
    assert_true(rx.he_eht_ltf_metric >= 1.0 - 2.0e-12)
    _assert_complex_list_close(
        rx.coarse_corrected_samples, expected_corrected, 2.0e-9, 2.0e-9
    )
    _assert_complex_list_close(
        rx.corrected_samples, expected_corrected, 2.0e-9, 2.0e-9
    )
    var expected_legacy_ltf = _flat(Span(legacy_ltf), h)
    var expected_signal_samples = _flat(Span(signal.waveform), h)
    var expected_eht_ltf = _flat(Span(eht_ltf), h)
    var expected_data_samples = _flat(Span(data.waveform), h)
    _assert_complex_list_close(rx.legacy_ltf_samples, expected_legacy_ltf)
    _assert_complex_list_close(rx.signal_samples, expected_signal_samples)
    _assert_complex_list_close(rx.he_eht_ltf_samples, expected_eht_ltf)
    _assert_complex_list_close(rx.data_samples, expected_data_samples)

    var legacy_ltf_spectrum = _legacy_ltf_spectrum()
    var expected_legacy_channel = _channel_from_training(
        Span(legacy_ltf_spectrum), h
    )
    _assert_complex_list_close(
        rx.legacy_channel_estimate, expected_legacy_channel
    )
    _assert_complex_list_close(rx.signal_equalized_spectrum, signal.spectrum)
    _assert_complex_list_close(rx.signal_corrected_symbols, signal.symbols)
    assert_equal(rx.signal_deinterleaved_bits, signal.coded)
    assert_equal(rx.signal_decoded_bits, signal.bits)
    assert_equal(rx.signal_length_octets, 268)
    assert_true(
        rx.signal_reserved_ok and rx.signal_parity_ok
        and rx.signal_tail_ok and rx.signal_rate_ok
        and rx.signal_length_ok and rx.signal_ok
    )
    var eht_ltf_spectrum = _eht_ltf_spectrum()
    var expected_eht_channel = _channel_from_training(
        Span(eht_ltf_spectrum), h
    )
    _assert_complex_list_close(
        rx.he_eht_channel_estimate, expected_eht_channel
    )

    var physical_llrs = _maxlog_llrs(
        Span(data.symbols), 12, noise_variance
    )
    var expected_demapped = _tone_demap_llrs(Span(physical_llrs), 12)
    var expected_recovered = _eht_rate_recover(Span(expected_demapped))
    _assert_complex_list_close(rx.data.equalized_spectrum, data.spectrum)
    _assert_complex_list_close(rx.data.corrected_data_symbols, data.symbols)
    _assert_float_list_close(rx.data.physical_llrs, physical_llrs)
    _assert_float_list_close(rx.data.demapped_llrs, expected_demapped)
    _assert_float_list_close(
        rx.data.rate_recovered_llrs, expected_recovered
    )
    assert_equal(rx.data.decoded_frame_bits, data.frame)
    assert_equal(rx.data.payload_bits, data.payload)
    assert_equal(rx.data.ldpc_block_length, 1944)
    assert_true(rx.data.ldpc_converged)
    assert_equal(rx.data.received_fcs, UInt64(0x615CE108))
    assert_equal(rx.data.computed_fcs, UInt64(0x615CE108))
    assert_true(rx.data.service_ok and rx.data.fcs_ok)

    var stages: List[String] = [
        "coarse-cfo-corrected-samples",
        "fine-cfo-corrected-samples",
        "legacy-ltf-samples",
        "legacy-channel-estimate",
        "legacy-signal-samples",
        "legacy-signal-equalized-spectrum",
        "legacy-signal-pilot-corrected-symbols",
        "he-eht-ltf-samples",
        "he-eht-channel-estimate",
        "data-samples",
        "data-equalized-spectrum",
        "legacy-signal-deinterleaved-bits",
        "legacy-signal-decoded-bits",
        "decoded-data-field-bits",
        "payload-bits",
        "ldpc-rate-recovered-llrs",
    ]
    var shapes: List[String] = [
        "955", "955", "160", "64", "80", "64", "48", "272", "256",
        "272", "256", "48", "24", "2160", "2112", "3888",
    ]
    _assert_metadata_common(
        "wifi-rx-independent-eht-mcs13",
        stages,
        shapes,
        rx.checkpoint_metadata,
    )
    assert_equal(len(rx.data.checkpoint_metadata), 16)
    for index in range(len(rx.data.checkpoint_metadata)):
        assert_equal(
            rx.data.checkpoint_metadata[index].testcase_id,
            "wifi-rx-independent-eht-mcs13",
        )


def test_wifi_rx_wrappers_direct_illegal_and_nonfinite_edges() raises:
    """Exercise direct shape/range/finite rejection at all four RX APIs."""
    var empty_samples = List[Complex64]()
    var empty_ltf = List[Complex64]()
    with assert_raises():
        _ = wifi_bcc_rx_20mhz(
            Span(empty_samples), Span(empty_ltf), WIFI_PHY_HT, 6, 1
        )
    var empty_ldpc_samples = List[Complex64]()
    var empty_ldpc_ltf = List[Complex64]()
    with assert_raises():
        _ = wifi_ldpc_rx_20mhz(
            Span(empty_ldpc_samples), Span(empty_ldpc_ltf), WIFI_PHY_HE, 10, 8,
            nan[DType.float64](),
        )
    var empty_acquisition = List[Complex64]()
    with assert_raises():
        _ = wifi_acquisition_rx_20mhz(
            Span(empty_acquisition), WIFI_PHY_HT, 6, 72,
            detection_threshold=inf[DType.float64](),
        )
    var empty_he_acquisition = List[Complex64]()
    with assert_raises():
        _ = wifi_he_eht_acquisition_rx_20mhz(
            Span(empty_he_acquisition), WIFI_PHY_HE, 10, 1640,
            llr_noise_variance=nan[DType.float64](),
        )

    var bad_observation: List[Complex64] = [
        Complex64(nan[DType.float64](), 0.0)
    ]
    with assert_raises():
        _ = wifi_acquisition_rx_20mhz(
            Span(bad_observation), WIFI_PHY_HT, 6, 72
        )
    with assert_raises():
        _ = wifi_he_eht_acquisition_rx_20mhz(
            Span(bad_observation), WIFI_PHY_HE, 10, 1640
        )

    var bcc = _bcc_fixture(3)
    var bcc_ltf = _ht_ltf_waveform()
    bcc.waveform[16] = Complex64(inf[DType.float64](), 0.0)
    with assert_raises():
        _ = wifi_bcc_rx_20mhz(
            Span(bcc.waveform), Span(bcc_ltf), WIFI_PHY_HT, 6, 72
        )
    var ldpc = _ldpc_fixture(4)
    var he_ltf = _he_ltf_waveform()
    ldpc.waveform[16] = Complex64(0.0, nan[DType.float64]())
    with assert_raises():
        _ = wifi_ldpc_rx_20mhz(
            Span(ldpc.waveform), Span(he_ltf), WIFI_PHY_HE, 10, 1640, 0.01
        )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
