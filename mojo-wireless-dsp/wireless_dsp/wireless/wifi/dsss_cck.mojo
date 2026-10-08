"""Bounded IEEE 802.11 DSSS and HR/DSSS chip-symbol algorithms.

This scalar reference implements the exact symbol rules that are auditable
from IEEE Std 802.11-2024 Clauses 15 and 16: the 11-chip Barker sequence,
1 Mb/s differential BPSK, 2 Mb/s differential QPSK, and the 8-complex-chip
5.5 Mb/s and 11 Mb/s CCK codewords.  CCK bit ``d0`` is first in time, the
fourth and seventh chips carry the specified 180-degree cover rotations, and
odd PSDU symbols receive the additional 180-degree differential rotation.

The hard receive routines are deterministic correlation references for these
finite chip alphabets; IEEE does not prescribe a unique soft-output detector.
They accept an explicit received reference phasor so a caller can preserve the
header-to-PSDU differential phase across a separately implemented boundary.

This is intentionally not a complete DSSS or HR/DSSS PHY.  PLCP framing,
scrambling, long and short preambles, SFDs, modulation-rate switching, pulse
shaping, carrier recovery, multipath equalization, CCA, RF behavior, PBCC,
channel agility, and conformance procedures are outside this module.

Normative publication: IEEE Std 802.11-2024, Clauses 15 and 16, especially
16.3.6.5 and 16.3.6.6.  DOI 10.1109/IEEESTD.2025.10979691.  The equations and
tables are also preserved in the IEEE 802.11 Working Group primary archive,
P802.11b/D3.1, 18.4.6.4--18.4.6.5.3, which is a historical cross-check only
and never an authority for production qualification.
"""

from std.collections import Span
from std.math import isfinite
from wireless_dsp.core import Complex64


comptime WIFI_DSSS_BARKER_CHIPS = 11
comptime WIFI_CCK_CHIPS = 8
comptime WIFI_CCK_5_5_BITS_PER_SYMBOL = 4
comptime WIFI_CCK_11_BITS_PER_SYMBOL = 8


struct WifiCCKSymbol(Movable):
    """One exact CCK codeword and its differential phase state.

    ``phase_quadrant`` is phi1 after applying the data dibit and the odd-symbol
    differential rotation.  Quadrants 0, 1, 2, and 3 denote 0, pi/2, pi, and
    -pi/2.
    """

    var chips: List[Complex64]
    var phase_quadrant: Int
    var phase_change_quadrant: Int

    def __init__(
        out self,
        var chips: List[Complex64],
        phase_quadrant: Int,
        phase_change_quadrant: Int,
    ):
        self.chips = chips^
        self.phase_quadrant = phase_quadrant
        self.phase_change_quadrant = phase_change_quadrant


struct _NormalizedCCKSymbol(Movable):
    var chips: List[Complex64]
    var last_real: Float64
    var last_imag: Float64

    def __init__(
        out self,
        var chips: List[Complex64],
        last_real: Float64,
        last_imag: Float64,
    ):
        self.chips = chips^
        self.last_real = last_real
        self.last_imag = last_imag


def _validate_phase_quadrant(phase_quadrant: Int) raises:
    if phase_quadrant < 0 or phase_quadrant > 3:
        raise Error("differential phase quadrant must be in [0,3]")


def _validate_symbol_range(symbol_offset: Int, symbol_count: Int) raises:
    if symbol_offset < 0:
        raise Error("CCK symbol offset must be non-negative")
    if symbol_count > 0 and symbol_offset > Int.MAX - (symbol_count - 1):
        raise Error("CCK symbol index range overflows Int")


def _checked_capacity(length: Int, factor: Int, label: String) raises -> Int:
    if length < 0 or factor <= 0 or length > Int.MAX // factor:
        raise Error(label + " output length overflows Int")
    return length * factor


def _validate_bits(bits: Span[UInt8, ...], multiple: Int, label: String) raises:
    if len(bits) % multiple != 0:
        raise Error(label + " must contain complete symbols")
    for index in range(len(bits)):
        if bits[index] > 1:
            raise Error(label + " must contain only zero and one")


def _validate_exact_bits(bits: Span[UInt8, ...], count: Int, label: String) raises:
    if len(bits) != count:
        raise Error(label + " has an invalid bit length")
    for index in range(count):
        if bits[index] > 1:
            raise Error(label + " must contain only zero and one")


def _validate_reference(reference: Complex64) raises:
    if not isfinite(reference.re) or not isfinite(reference.im):
        raise Error("differential reference must be finite")
    if reference.re == 0.0 and reference.im == 0.0:
        raise Error("differential reference must be nonzero")


def _unit_max_pair(real: Float64, imag: Float64) raises -> Tuple[Float64, Float64]:
    var scale = max(abs(real), abs(imag))
    if not isfinite(scale) or scale == 0.0:
        raise Error("differential phasor must be finite and nonzero")
    return (real / scale, imag / scale)


def _quadrant_complex(quadrant: Int) -> Complex64:
    var value = quadrant & 3
    if value == 0:
        return Complex64(1.0, 0.0)
    if value == 1:
        return Complex64(0.0, 1.0)
    if value == 2:
        return Complex64(-1.0, 0.0)
    return Complex64(0.0, -1.0)


def _dqpsk_quadrant(first: Int, second: Int) -> Int:
    if first == 0:
        return second
    return 3 - second


def _append_dqpsk_bits(mut output: List[UInt8], quadrant: Int):
    var value = quadrant & 3
    if value == 0:
        output.append(UInt8(0))
        output.append(UInt8(0))
    elif value == 1:
        output.append(UInt8(0))
        output.append(UInt8(1))
    elif value == 2:
        output.append(UInt8(1))
        output.append(UInt8(1))
    else:
        output.append(UInt8(1))
        output.append(UInt8(0))


def _nearest_quadrant(real: Float64, imag: Float64) -> Int:
    # Correlation with [1, j, -1, -j].  Strict comparisons retain the lower
    # quadrant on an exact tie, making the bounded hard detector deterministic.
    var best_quadrant = 0
    var best_score = real
    if imag > best_score:
        best_quadrant = 1
        best_score = imag
    if -real > best_score:
        best_quadrant = 2
        best_score = -real
    if -imag > best_score:
        best_quadrant = 3
    return best_quadrant


def _barker_coefficient(index: Int) -> Float64:
    # Leftmost chip first: + - + + - + + + - - -.
    if index == 1 or index == 4 or index >= 8:
        return -1.0
    return 1.0


def wifi_dsss_barker_sequence() -> List[Complex64]:
    """Return the Clause-15 11-chip Barker sequence, leftmost chip first."""
    var result = List[Complex64](capacity=WIFI_DSSS_BARKER_CHIPS)
    for index in range(WIFI_DSSS_BARKER_CHIPS):
        result.append(Complex64(_barker_coefficient(index), 0.0))
    return result^


def _append_barker_symbol(mut output: List[Complex64], quadrant: Int):
    var phase = _quadrant_complex(quadrant)
    for chip in range(WIFI_DSSS_BARKER_CHIPS):
        var coefficient = _barker_coefficient(chip)
        output.append(
            Complex64(coefficient * phase.re, coefficient * phase.im)
        )


def wifi_dsss_dbpsk_spread(
    bits: Span[UInt8, ...], *, initial_phase_quadrant: Int = 0
) raises -> List[Complex64]:
    """Differentially DBPSK-map bits and spread each bit by 11 Barker chips.

    A zero bit preserves the preceding phase and a one bit rotates it by pi.
    ``initial_phase_quadrant`` is the phase of the preceding reference symbol.
    """
    _validate_phase_quadrant(initial_phase_quadrant)
    _validate_bits(bits, 1, "DSSS DBPSK input")
    var capacity = _checked_capacity(
        len(bits), WIFI_DSSS_BARKER_CHIPS, "DSSS DBPSK"
    )
    var result = List[Complex64](capacity=capacity)
    var phase = initial_phase_quadrant
    for index in range(len(bits)):
        phase = (phase + 2 * Int(bits[index])) & 3
        _append_barker_symbol(result, phase)
    return result^


def wifi_dsss_dqpsk_spread(
    bits: Span[UInt8, ...], *, initial_phase_quadrant: Int = 0
) raises -> List[Complex64]:
    """Differentially DQPSK-map dibits and Barker-spread each symbol.

    Dibits ``00, 01, 11, 10`` give counterclockwise phase changes
    ``0, pi/2, pi, -pi/2`` respectively; the first bit is first in time.
    """
    _validate_phase_quadrant(initial_phase_quadrant)
    _validate_bits(bits, 2, "DSSS DQPSK input")
    var symbol_count = len(bits) // 2
    var capacity = _checked_capacity(
        symbol_count, WIFI_DSSS_BARKER_CHIPS, "DSSS DQPSK"
    )
    var result = List[Complex64](capacity=capacity)
    var phase = initial_phase_quadrant
    for symbol in range(symbol_count):
        var bit_offset = 2 * symbol
        phase = (
            phase
            + _dqpsk_quadrant(
                Int(bits[bit_offset]), Int(bits[bit_offset + 1])
            )
        ) & 3
        _append_barker_symbol(result, phase)
    return result^


def _dsss_symbol_correlation(
    chips: Span[Complex64, ...], offset: Int
) raises -> Tuple[Float64, Float64]:
    var scale = 0.0
    for chip in range(WIFI_DSSS_BARKER_CHIPS):
        var sample = Complex64(chips[offset + chip].re, chips[offset + chip].im)
        if not isfinite(sample.re) or not isfinite(sample.im):
            raise Error("DSSS chips must be finite")
        scale = max(scale, abs(sample.re), abs(sample.im))
    if scale == 0.0:
        raise Error("DSSS symbol energy must be nonzero")

    var real = 0.0
    var imag = 0.0
    for chip in range(WIFI_DSSS_BARKER_CHIPS):
        var coefficient = _barker_coefficient(chip)
        real += coefficient * (chips[offset + chip].re / scale)
        imag += coefficient * (chips[offset + chip].im / scale)
    return _unit_max_pair(real, imag)


def _differential_delta(
    current_real: Float64,
    current_imag: Float64,
    previous_real: Float64,
    previous_imag: Float64,
) -> Tuple[Float64, Float64]:
    return (
        current_real * previous_real + current_imag * previous_imag,
        current_imag * previous_real - current_real * previous_imag,
    )


def wifi_dsss_dbpsk_despread_hard(
    chips: Span[Complex64, ...],
    *,
    initial_reference: Complex64 = Complex64(1.0, 0.0),
) raises -> List[UInt8]:
    """Barker-correlate and hard-detect a DBPSK chip sequence.

    ``initial_reference`` is the received nonzero phasor immediately preceding
    this sequence.  Per-symbol scaling makes every finite input accumulation
    overflow-safe without changing the correlation decision.
    """
    _validate_reference(initial_reference)
    if len(chips) % WIFI_DSSS_BARKER_CHIPS != 0:
        raise Error("DSSS DBPSK input must contain complete 11-chip symbols")
    var symbol_count = len(chips) // WIFI_DSSS_BARKER_CHIPS
    var result = List[UInt8](capacity=symbol_count)
    var previous_real, previous_imag = _unit_max_pair(
        initial_reference.re, initial_reference.im
    )
    for symbol in range(symbol_count):
        var current_real, current_imag = _dsss_symbol_correlation(
            chips, symbol * WIFI_DSSS_BARKER_CHIPS
        )
        var delta_real, _ = _differential_delta(
            current_real, current_imag, previous_real, previous_imag
        )
        result.append(UInt8(0 if delta_real >= 0.0 else 1))
        previous_real = current_real
        previous_imag = current_imag
    return result^


def wifi_dsss_dqpsk_despread_hard(
    chips: Span[Complex64, ...],
    *,
    initial_reference: Complex64 = Complex64(1.0, 0.0),
) raises -> List[UInt8]:
    """Barker-correlate and nearest-phase hard-detect DQPSK chips."""
    _validate_reference(initial_reference)
    if len(chips) % WIFI_DSSS_BARKER_CHIPS != 0:
        raise Error("DSSS DQPSK input must contain complete 11-chip symbols")
    var symbol_count = len(chips) // WIFI_DSSS_BARKER_CHIPS
    var capacity = _checked_capacity(symbol_count, 2, "DSSS DQPSK bits")
    var result = List[UInt8](capacity=capacity)
    var previous_real, previous_imag = _unit_max_pair(
        initial_reference.re, initial_reference.im
    )
    for symbol in range(symbol_count):
        var current_real, current_imag = _dsss_symbol_correlation(
            chips, symbol * WIFI_DSSS_BARKER_CHIPS
        )
        var delta_real, delta_imag = _differential_delta(
            current_real, current_imag, previous_real, previous_imag
        )
        _append_dqpsk_bits(
            result, _nearest_quadrant(delta_real, delta_imag)
        )
        previous_real = current_real
        previous_imag = current_imag
    return result^


def _append_cck_codeword(
    mut output: List[Complex64],
    phi1: Int,
    phi2: Int,
    phi3: Int,
    phi4: Int,
):
    var phases: List[Int] = [
        phi1 + phi2 + phi3 + phi4,
        phi1 + phi3 + phi4,
        phi1 + phi2 + phi4,
        phi1 + phi4 + 2,
        phi1 + phi2 + phi3,
        phi1 + phi3,
        phi1 + phi2 + 2,
        phi1,
    ]
    for chip in range(WIFI_CCK_CHIPS):
        output.append(_quadrant_complex(phases[chip]))


def _cck_phase1(
    d0: Int,
    d1: Int,
    previous_phase_quadrant: Int,
    symbol_index: Int,
) -> Tuple[Int, Int]:
    var phase_change = _dqpsk_quadrant(d0, d1)
    if (symbol_index & 1) != 0:
        phase_change = (phase_change + 2) & 3
    return ((previous_phase_quadrant + phase_change) & 3, phase_change)


def _cck_5_5_unchecked(
    d0: Int,
    d1: Int,
    d2: Int,
    d3: Int,
    previous_phase_quadrant: Int,
    symbol_index: Int,
) -> WifiCCKSymbol:
    var phi1, phase_change = _cck_phase1(
        d0, d1, previous_phase_quadrant, symbol_index
    )
    var chips = List[Complex64](capacity=WIFI_CCK_CHIPS)
    _append_cck_codeword(chips, phi1, 1 + 2 * d2, 0, 2 * d3)
    return WifiCCKSymbol(chips^, phi1, phase_change)


def _cck_11_unchecked(
    d0: Int,
    d1: Int,
    d2: Int,
    d3: Int,
    d4: Int,
    d5: Int,
    d6: Int,
    d7: Int,
    previous_phase_quadrant: Int,
    symbol_index: Int,
) -> WifiCCKSymbol:
    var phi1, phase_change = _cck_phase1(
        d0, d1, previous_phase_quadrant, symbol_index
    )
    var chips = List[Complex64](capacity=WIFI_CCK_CHIPS)
    _append_cck_codeword(
        chips,
        phi1,
        2 * d2 + d3,
        2 * d4 + d5,
        2 * d6 + d7,
    )
    return WifiCCKSymbol(chips^, phi1, phase_change)


def wifi_cck_5_5_codeword(
    bits: Span[UInt8, ...],
    *,
    previous_phase_quadrant: Int = 0,
    symbol_index: Int = 0,
) raises -> WifiCCKSymbol:
    """Map one 4-bit 5.5 Mb/s CCK symbol to eight exact complex chips."""
    _validate_exact_bits(bits, WIFI_CCK_5_5_BITS_PER_SYMBOL, "5.5 Mb/s CCK")
    _validate_phase_quadrant(previous_phase_quadrant)
    _validate_symbol_range(symbol_index, 1)
    return _cck_5_5_unchecked(
        Int(bits[0]),
        Int(bits[1]),
        Int(bits[2]),
        Int(bits[3]),
        previous_phase_quadrant,
        symbol_index,
    )


def wifi_cck_11_codeword(
    bits: Span[UInt8, ...],
    *,
    previous_phase_quadrant: Int = 0,
    symbol_index: Int = 0,
) raises -> WifiCCKSymbol:
    """Map one 8-bit 11 Mb/s CCK symbol to eight exact complex chips."""
    _validate_exact_bits(bits, WIFI_CCK_11_BITS_PER_SYMBOL, "11 Mb/s CCK")
    _validate_phase_quadrant(previous_phase_quadrant)
    _validate_symbol_range(symbol_index, 1)
    return _cck_11_unchecked(
        Int(bits[0]),
        Int(bits[1]),
        Int(bits[2]),
        Int(bits[3]),
        Int(bits[4]),
        Int(bits[5]),
        Int(bits[6]),
        Int(bits[7]),
        previous_phase_quadrant,
        symbol_index,
    )


def wifi_cck_5_5_map(
    bits: Span[UInt8, ...],
    *,
    initial_phase_quadrant: Int = 0,
    symbol_offset: Int = 0,
) raises -> List[Complex64]:
    """Map a 4-bit-grouped PSDU segment to 5.5 Mb/s CCK chip symbols."""
    _validate_phase_quadrant(initial_phase_quadrant)
    _validate_bits(bits, WIFI_CCK_5_5_BITS_PER_SYMBOL, "5.5 Mb/s CCK input")
    var symbol_count = len(bits) // WIFI_CCK_5_5_BITS_PER_SYMBOL
    _validate_symbol_range(symbol_offset, symbol_count)
    var capacity = _checked_capacity(symbol_count, WIFI_CCK_CHIPS, "5.5 Mb/s CCK")
    var result = List[Complex64](capacity=capacity)
    var phase = initial_phase_quadrant
    for symbol in range(symbol_count):
        var offset = symbol * WIFI_CCK_5_5_BITS_PER_SYMBOL
        var codeword = _cck_5_5_unchecked(
            Int(bits[offset]),
            Int(bits[offset + 1]),
            Int(bits[offset + 2]),
            Int(bits[offset + 3]),
            phase,
            symbol_offset + symbol,
        )
        for chip in range(WIFI_CCK_CHIPS):
            result.append(codeword.chips[chip])
        phase = codeword.phase_quadrant
    return result^


def wifi_cck_11_map(
    bits: Span[UInt8, ...],
    *,
    initial_phase_quadrant: Int = 0,
    symbol_offset: Int = 0,
) raises -> List[Complex64]:
    """Map an 8-bit-grouped PSDU segment to 11 Mb/s CCK chip symbols."""
    _validate_phase_quadrant(initial_phase_quadrant)
    _validate_bits(bits, WIFI_CCK_11_BITS_PER_SYMBOL, "11 Mb/s CCK input")
    var symbol_count = len(bits) // WIFI_CCK_11_BITS_PER_SYMBOL
    _validate_symbol_range(symbol_offset, symbol_count)
    var capacity = _checked_capacity(symbol_count, WIFI_CCK_CHIPS, "11 Mb/s CCK")
    var result = List[Complex64](capacity=capacity)
    var phase = initial_phase_quadrant
    for symbol in range(symbol_count):
        var offset = symbol * WIFI_CCK_11_BITS_PER_SYMBOL
        var codeword = _cck_11_unchecked(
            Int(bits[offset]),
            Int(bits[offset + 1]),
            Int(bits[offset + 2]),
            Int(bits[offset + 3]),
            Int(bits[offset + 4]),
            Int(bits[offset + 5]),
            Int(bits[offset + 6]),
            Int(bits[offset + 7]),
            phase,
            symbol_offset + symbol,
        )
        for chip in range(WIFI_CCK_CHIPS):
            result.append(codeword.chips[chip])
        phase = codeword.phase_quadrant
    return result^


def _normalized_cck_symbol(
    chips: Span[Complex64, ...], offset: Int
) raises -> _NormalizedCCKSymbol:
    var scale = 0.0
    for chip in range(WIFI_CCK_CHIPS):
        var sample = Complex64(chips[offset + chip].re, chips[offset + chip].im)
        if not isfinite(sample.re) or not isfinite(sample.im):
            raise Error("CCK chips must be finite")
        scale = max(scale, abs(sample.re), abs(sample.im))
    if scale == 0.0:
        raise Error("CCK symbol energy must be nonzero")

    var result = List[Complex64](capacity=WIFI_CCK_CHIPS)
    for chip in range(WIFI_CCK_CHIPS):
        result.append(
            Complex64(
                chips[offset + chip].re / scale,
                chips[offset + chip].im / scale,
            )
        )
    var last_real, last_imag = _unit_max_pair(
        result[WIFI_CCK_CHIPS - 1].re,
        result[WIFI_CCK_CHIPS - 1].im,
    )
    return _NormalizedCCKSymbol(result^, last_real, last_imag)


def _cck_relative_score(
    received: Span[Complex64, ...],
    last_real: Float64,
    last_imag: Float64,
    phi2: Int,
    phi3: Int,
    phi4: Int,
) -> Float64:
    var candidate = List[Complex64](capacity=WIFI_CCK_CHIPS)
    _append_cck_codeword(candidate, 0, phi2, phi3, phi4)
    var score = 0.0
    for chip in range(WIFI_CCK_CHIPS):
        # received * conjugate(received c7), followed by correlation with the
        # q1-free candidate.  All factors are bounded by one here.
        var relative_real = (
            received[chip].re * last_real
            + received[chip].im * last_imag
        )
        var relative_imag = (
            received[chip].im * last_real
            - received[chip].re * last_imag
        )
        score += (
            relative_real * candidate[chip].re
            + relative_imag * candidate[chip].im
        )
    return score


def _cck_differential_bits(
    mut output: List[UInt8],
    current_real: Float64,
    current_imag: Float64,
    previous_real: Float64,
    previous_imag: Float64,
    symbol_index: Int,
):
    var delta_real, delta_imag = _differential_delta(
        current_real, current_imag, previous_real, previous_imag
    )
    var phase_change = _nearest_quadrant(delta_real, delta_imag)
    if (symbol_index & 1) != 0:
        phase_change = (phase_change + 2) & 3
    _append_dqpsk_bits(output, phase_change)


def wifi_cck_5_5_demap_hard(
    chips: Span[Complex64, ...],
    *,
    initial_reference: Complex64 = Complex64(1.0, 0.0),
    symbol_offset: Int = 0,
) raises -> List[UInt8]:
    """Hard-detect 5.5 Mb/s CCK by differential and codeword correlation."""
    _validate_reference(initial_reference)
    if len(chips) % WIFI_CCK_CHIPS != 0:
        raise Error("5.5 Mb/s CCK input must contain complete 8-chip symbols")
    var symbol_count = len(chips) // WIFI_CCK_CHIPS
    _validate_symbol_range(symbol_offset, symbol_count)
    var capacity = _checked_capacity(
        symbol_count, WIFI_CCK_5_5_BITS_PER_SYMBOL, "5.5 Mb/s CCK bits"
    )
    var result = List[UInt8](capacity=capacity)
    var previous_real, previous_imag = _unit_max_pair(
        initial_reference.re, initial_reference.im
    )
    for symbol in range(symbol_count):
        var normalized = _normalized_cck_symbol(
            chips, symbol * WIFI_CCK_CHIPS
        )
        _cck_differential_bits(
            result,
            normalized.last_real,
            normalized.last_imag,
            previous_real,
            previous_imag,
            symbol_offset + symbol,
        )

        var best_pattern = 0
        var best_score = -1.0e300
        for pattern in range(4):
            var d2 = (pattern >> 1) & 1
            var d3 = pattern & 1
            var score = _cck_relative_score(
                Span(normalized.chips),
                normalized.last_real,
                normalized.last_imag,
                1 + 2 * d2,
                0,
                2 * d3,
            )
            if score > best_score:
                best_pattern = pattern
                best_score = score
        result.append(UInt8((best_pattern >> 1) & 1))
        result.append(UInt8(best_pattern & 1))
        previous_real = normalized.last_real
        previous_imag = normalized.last_imag
    return result^


def wifi_cck_11_demap_hard(
    chips: Span[Complex64, ...],
    *,
    initial_reference: Complex64 = Complex64(1.0, 0.0),
    symbol_offset: Int = 0,
) raises -> List[UInt8]:
    """Hard-detect 11 Mb/s CCK by differential and 64-code correlation."""
    _validate_reference(initial_reference)
    if len(chips) % WIFI_CCK_CHIPS != 0:
        raise Error("11 Mb/s CCK input must contain complete 8-chip symbols")
    var symbol_count = len(chips) // WIFI_CCK_CHIPS
    _validate_symbol_range(symbol_offset, symbol_count)
    var capacity = _checked_capacity(
        symbol_count, WIFI_CCK_11_BITS_PER_SYMBOL, "11 Mb/s CCK bits"
    )
    var result = List[UInt8](capacity=capacity)
    var previous_real, previous_imag = _unit_max_pair(
        initial_reference.re, initial_reference.im
    )
    for symbol in range(symbol_count):
        var normalized = _normalized_cck_symbol(
            chips, symbol * WIFI_CCK_CHIPS
        )
        _cck_differential_bits(
            result,
            normalized.last_real,
            normalized.last_imag,
            previous_real,
            previous_imag,
            symbol_offset + symbol,
        )

        var best_pattern = 0
        var best_score = -1.0e300
        for pattern in range(64):
            var d2 = (pattern >> 5) & 1
            var d3 = (pattern >> 4) & 1
            var d4 = (pattern >> 3) & 1
            var d5 = (pattern >> 2) & 1
            var d6 = (pattern >> 1) & 1
            var d7 = pattern & 1
            var score = _cck_relative_score(
                Span(normalized.chips),
                normalized.last_real,
                normalized.last_imag,
                2 * d2 + d3,
                2 * d4 + d5,
                2 * d6 + d7,
            )
            if score > best_score:
                best_pattern = pattern
                best_score = score
        for shift in range(5, -1, -1):
            result.append(UInt8((best_pattern >> shift) & 1))
        previous_real = normalized.last_real
        previous_imag = normalized.last_imag
    return result^
