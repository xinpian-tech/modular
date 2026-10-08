"""Bounded IEEE 802.11-2024 Clause-20 DMG Golay algorithms.

This scalar CPU reference implements the six normative bipolar sequences in
Tables 20-23 through 20-28, strict noiseless pi/2-BPSK axis mapping, and the
DMG control-PHY Short Training field composition in 20.4.3.1.2.  Table order
is transmission order.  The control STF contains 48 copies of Gb128 followed
by -Gb128 and -Ga128.

The exact tables and composition are inherited from the published
IEEE Std 802.11ad-2012 DMG PHY and retained in IEEE Std 802.11-2024.  The
current publication is DOI 10.1109/IEEESTD.2025.10979691; its official IEEE
SA page is https://standards.ieee.org/ieee/802.11/10548/.

This is deliberately not a complete DMG PHY.  Gu/Gv channel-estimation
fields, SC/OFDM/control headers, scrambling, HCS, LDPC, payload modulation,
beam-training state, noisy detection, synchronization, RF, and conformance
procedures remain outside this module.
"""

from std.collections import Span
from std.math import isfinite
from wireless_dsp.core import Complex64


comptime WIFI_DMG_GOLAY_MIN_LENGTH = 32
comptime WIFI_DMG_GOLAY_MAX_LENGTH = 128
comptime WIFI_DMG_CONTROL_STF_GB_REPETITIONS = 48
comptime WIFI_DMG_CONTROL_STF_SEQUENCE_COUNT = 50
comptime WIFI_DMG_CONTROL_STF_CHIPS = 6400


def _validate_golay_length(length: Int) raises:
    if length != 32 and length != 64 and length != 128:
        raise Error("DMG Golay length must be 32, 64, or 128")


def _validate_bipolar_chips(
    chips: Span[Int, ...], *, allow_control_stf: Bool = False
) raises:
    var length = len(chips)
    if (
        length != 32
        and length != 64
        and length != 128
        and (not allow_control_stf or length != WIFI_DMG_CONTROL_STF_CHIPS)
    ):
        raise Error("DMG chip vector has an unsupported length")
    for index in range(length):
        if chips[index] != -1 and chips[index] != 1:
            raise Error("DMG Golay chips must be exactly -1 or +1")


def _validate_start_chip_index(start_chip_index: Int) raises:
    if start_chip_index < 0:
        raise Error("DMG pi/2-BPSK start chip index must be non-negative")


def wifi_dmg_golay_sequence(length: Int, is_ga: Bool) raises -> List[Int]:
    """Return one normative DMG Ga/Gb sequence in transmission order.

    ``length`` is exactly 32, 64, or 128.  ``is_ga=True`` selects Ga and
    ``False`` selects Gb.  Every returned chip is the integer -1 or +1.
    """
    _validate_golay_length(length)
    if length == 32:
        if is_ga:
            return [
                1, 1, 1, 1, 1, -1, 1, -1,
                -1, -1, 1, 1, 1, -1, -1, 1,
                1, 1, -1, -1, 1, -1, -1, 1,
                -1, -1, -1, -1, 1, -1, 1, -1,
            ]
        return [
            -1, -1, -1, -1, -1, 1, -1, 1,
            1, 1, -1, -1, -1, 1, 1, -1,
            1, 1, -1, -1, 1, -1, -1, 1,
            -1, -1, -1, -1, 1, -1, 1, -1,
        ]

    if length == 64:
        if is_ga:
            return [
                -1, -1, 1, -1, 1, -1, -1, -1,
                1, 1, -1, 1, 1, -1, -1, -1,
                -1, -1, 1, -1, 1, -1, -1, -1,
                -1, -1, 1, -1, -1, 1, 1, 1,
                -1, -1, 1, -1, 1, -1, -1, -1,
                1, 1, -1, 1, 1, -1, -1, -1,
                1, 1, -1, 1, -1, 1, 1, 1,
                1, 1, -1, 1, 1, -1, -1, -1,
            ]
        return [
            1, 1, -1, 1, -1, 1, 1, 1,
            -1, -1, 1, -1, -1, 1, 1, 1,
            1, 1, -1, 1, -1, 1, 1, 1,
            1, 1, -1, 1, 1, -1, -1, -1,
            -1, -1, 1, -1, 1, -1, -1, -1,
            1, 1, -1, 1, 1, -1, -1, -1,
            1, 1, -1, 1, -1, 1, 1, 1,
            1, 1, -1, 1, 1, -1, -1, -1,
        ]

    if is_ga:
        return [
            1, 1, -1, -1, -1, -1, -1, -1,
            -1, 1, -1, 1, 1, -1, -1, 1,
            1, 1, -1, -1, 1, 1, 1, 1,
            -1, 1, -1, 1, -1, 1, 1, -1,
            -1, -1, 1, 1, 1, 1, 1, 1,
            1, -1, 1, -1, -1, 1, 1, -1,
            1, 1, -1, -1, 1, 1, 1, 1,
            -1, 1, -1, 1, -1, 1, 1, -1,
            1, 1, -1, -1, -1, -1, -1, -1,
            -1, 1, -1, 1, 1, -1, -1, 1,
            1, 1, -1, -1, 1, 1, 1, 1,
            -1, 1, -1, 1, -1, 1, 1, -1,
            1, 1, -1, -1, -1, -1, -1, -1,
            -1, 1, -1, 1, 1, -1, -1, 1,
            -1, -1, 1, 1, -1, -1, -1, -1,
            1, -1, 1, -1, 1, -1, -1, 1,
        ]
    return [
        -1, -1, 1, 1, 1, 1, 1, 1,
        1, -1, 1, -1, -1, 1, 1, -1,
        -1, -1, 1, 1, -1, -1, -1, -1,
        1, -1, 1, -1, 1, -1, -1, 1,
        1, 1, -1, -1, -1, -1, -1, -1,
        -1, 1, -1, 1, 1, -1, -1, 1,
        -1, -1, 1, 1, -1, -1, -1, -1,
        1, -1, 1, -1, 1, -1, -1, 1,
        1, 1, -1, -1, -1, -1, -1, -1,
        -1, 1, -1, 1, 1, -1, -1, 1,
        1, 1, -1, -1, 1, 1, 1, 1,
        -1, 1, -1, 1, -1, 1, 1, -1,
        1, 1, -1, -1, -1, -1, -1, -1,
        -1, 1, -1, 1, 1, -1, -1, 1,
        -1, -1, 1, 1, -1, -1, -1, -1,
        1, -1, 1, -1, 1, -1, -1, 1,
    ]


def wifi_dmg_pi_over_2_bpsk_modulate(
    chips: Span[Int, ...], *, start_chip_index: Int = 0
) raises -> List[Complex64]:
    """Map bipolar chips to the exact rotated pi/2-BPSK axes.

    The returned symbol for local chip ``k`` is ``chips[k]`` multiplied by
    ``exp(j*pi*(start_chip_index+k)/2)``.  Accepted vectors are one supported
    Golay length or the complete 6400-chip control STF.  Only the index modulo
    four is evaluated, so every non-negative ``Int`` start is overflow-safe.
    """
    _validate_bipolar_chips(chips, allow_control_stf=True)
    _validate_start_chip_index(start_chip_index)
    var result = List[Complex64](capacity=len(chips))
    var start_phase = start_chip_index & 3
    for index in range(len(chips)):
        var chip = Float64(chips[index])
        var phase = (start_phase + (index & 3)) & 3
        if phase == 0:
            result.append(Complex64(chip, 0.0))
        elif phase == 1:
            result.append(Complex64(0.0, chip))
        elif phase == 2:
            result.append(Complex64(-chip, 0.0))
        else:
            result.append(Complex64(0.0, -chip))
    return result^


def _exact_pi_over_2_chip(symbol: Complex64, phase: Int) raises -> Int:
    if not isfinite(symbol.re) or not isfinite(symbol.im):
        raise Error("DMG pi/2-BPSK symbols must be finite")
    if phase == 0:
        if symbol.im != 0.0:
            raise Error("DMG symbol is outside the exact pi/2-BPSK alphabet")
        if symbol.re == 1.0:
            return 1
        if symbol.re == -1.0:
            return -1
    elif phase == 1:
        if symbol.re != 0.0:
            raise Error("DMG symbol is outside the exact pi/2-BPSK alphabet")
        if symbol.im == 1.0:
            return 1
        if symbol.im == -1.0:
            return -1
    elif phase == 2:
        if symbol.im != 0.0:
            raise Error("DMG symbol is outside the exact pi/2-BPSK alphabet")
        if symbol.re == -1.0:
            return 1
        if symbol.re == 1.0:
            return -1
    else:
        if symbol.re != 0.0:
            raise Error("DMG symbol is outside the exact pi/2-BPSK alphabet")
        if symbol.im == -1.0:
            return 1
        if symbol.im == 1.0:
            return -1
    raise Error("DMG symbol is outside the exact pi/2-BPSK alphabet")


def wifi_dmg_pi_over_2_bpsk_demodulate_exact(
    symbols: Span[Complex64, ...], *, start_chip_index: Int = 0
) raises -> List[Int]:
    """Strictly invert a noiseless unit-axis DMG pi/2-BPSK vector.

    This parser is intentionally not a noisy hard or soft detector.  It
    rejects non-finite, off-axis, non-unit, empty, and unsupported-length
    inputs instead of silently quantizing them.
    """
    var length = len(symbols)
    if (
        length != 32
        and length != 64
        and length != 128
        and length != WIFI_DMG_CONTROL_STF_CHIPS
    ):
        raise Error("DMG pi/2-BPSK vector has an unsupported length")
    _validate_start_chip_index(start_chip_index)
    var result = List[Int](capacity=length)
    var start_phase = start_chip_index & 3
    for index in range(length):
        var symbol = Complex64(symbols[index].re, symbols[index].im)
        result.append(
            _exact_pi_over_2_chip(
                symbol, (start_phase + (index & 3)) & 3
            )
        )
    return result^


def wifi_dmg_control_stf_chips() raises -> List[Int]:
    """Return the exact 6400-chip DMG control-PHY Short Training field.

    Clause 20.4.3.1.2 orders 48 Gb128 sequences, then -Gb128, then -Ga128.
    The returned bipolar chips precede the global pi/2 rotation; pass them to
    ``wifi_dmg_pi_over_2_bpsk_modulate`` with start index zero for the
    transmitted baseband axes.
    """
    var ga = wifi_dmg_golay_sequence(128, True)
    var gb = wifi_dmg_golay_sequence(128, False)
    var result = List[Int](capacity=WIFI_DMG_CONTROL_STF_CHIPS)
    for _ in range(WIFI_DMG_CONTROL_STF_GB_REPETITIONS):
        for index in range(128):
            result.append(gb[index])
    for index in range(128):
        result.append(-gb[index])
    for index in range(128):
        result.append(-ga[index])
    return result^


def wifi_dmg_golay_complementary_autocorrelation(
    ga: Span[Int, ...], gb: Span[Int, ...], lag: Int
) raises -> Int:
    """Return the exact summed aperiodic autocorrelation at nonnegative lag.

    Both input vectors must have the same supported DMG Golay length and must
    remain bipolar after any caller mutation.  For a normative pair the
    result is ``2*length`` at lag zero and zero at every other legal lag.
    Accumulation is bounded by 256 and cannot overflow ``Int``.
    """
    _validate_bipolar_chips(ga)
    _validate_bipolar_chips(gb)
    if len(ga) != len(gb):
        raise Error("DMG complementary sequences must have equal lengths")
    if lag < 0 or lag >= len(ga):
        raise Error("DMG autocorrelation lag is outside the sequence")
    var result = 0
    for index in range(len(ga) - lag):
        result += ga[index] * ga[index + lag]
        result += gb[index] * gb[index + lag]
    return result
