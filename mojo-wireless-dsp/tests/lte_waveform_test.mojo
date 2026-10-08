"""Strict evidence for bounded LTE PUSCH, PRACH, and SISO RE mapping."""

from std.collections import Span
from std.math import cos, sin
from std.testing import assert_equal, assert_raises, assert_true, TestSuite
from wireless_dsp.core import Complex64
from wireless_dsp.wireless.lte.physical import (
    lte_pusch_scrambling_c_init,
    lte_pusch_scramble,
    lte_pusch_dmrs_base_sequence,
    lte_pusch_dmrs_sequence,
    lte_prach_root_sequence,
    lte_prach_unrestricted_cyclic_shift,
    lte_prach_format0_sequence,
    lte_prach_format0_normalized_waveform,
    lte_detect_prach_format0,
    lte_pdsch_map_siso,
    lte_pdsch_extract_siso,
    lte_pusch_map_siso,
    lte_pusch_extract_siso,
)


comptime _PI = 3.1415926535897932384626433832795


def _assert_close(actual: Float64, expected: Float64, tolerance: Float64) raises:
    assert_true(abs(actual - expected) <= tolerance)


def _assert_complex_close(
    actual: Complex64, expected: Complex64, tolerance: Float64
) raises:
    _assert_close(actual.re, expected.re, tolerance)
    _assert_close(actual.im, expected.im, tolerance)


def _nonfinite_from_finite_inputs() -> Float64:
    var maximum = Float64.MAX_FINITE
    return maximum + maximum


def _reference_gold(c_init: UInt32, length: Int) -> List[UInt8]:
    # Independent 31-bit-register transcription of clause 7.2.
    var x1 = UInt32(1)
    var x2 = c_init & UInt32(0x7FFFFFFF)
    var result = List[UInt8](capacity=length)
    for index in range(1600 + length):
        var output = UInt8((x1 ^ x2) & UInt32(1))
        var x1_feedback = ((x1 >> 3) ^ x1) & UInt32(1)
        var x2_feedback = (
            (x2 >> 3) ^ (x2 >> 2) ^ (x2 >> 1) ^ x2
        ) & UInt32(1)
        x1 = (x1 >> 1) | (x1_feedback << 30)
        x2 = (x2 >> 1) | (x2_feedback << 30)
        if index >= 1600:
            result.append(output)
    return result^


def test_pusch_scrambling_normative_initialization_and_static_gold_oracle() raises:
    # 0x1234*2^14 + 1*2^13 + floor(7/2)*2^9 + 321.
    assert_equal(
        lte_pusch_scrambling_c_init(0x1234, 1, 7, 321),
        UInt32(76359489),
    )
    assert_equal(
        lte_pusch_scrambling_c_init(0xFFFF, 1, 19, 503),
        UInt32(1073738743),
    )
    var bits = List[UInt8](capacity=257)
    for index in range(257):
        bits.append(UInt8((index * 11 + index // 7 + 1) & 1))
    var actual = lte_pusch_scramble(Span(bits), 0x1234, 1, 7, 321)
    var gold = _reference_gold(UInt32(76359489), len(bits))
    for index in range(len(bits)):
        assert_equal(actual[index], bits[index] ^ gold[index])
    assert_equal(
        lte_pusch_scramble(Span(actual), 0x1234, 1, 7, 321), bits
    )

    with assert_raises():
        _ = lte_pusch_scrambling_c_init(-1, 0, 0, 0)
    with assert_raises():
        _ = lte_pusch_scrambling_c_init(1, 2, 0, 0)
    with assert_raises():
        _ = lte_pusch_scrambling_c_init(1, 0, 20, 0)
    with assert_raises():
        _ = lte_pusch_scrambling_c_init(1, 0, 0, 504)
    var invalid_bits: List[UInt8] = [0, 1, 2]
    with assert_raises():
        _ = lte_pusch_scramble(Span(invalid_bits), 1, 0, 0, 0)


def test_pusch_dmrs_zc_base_and_cyclic_shift_hand_oracles() raises:
    # For M=36, N_ZC=31, u=0 and v=0 give q=1 exactly.
    var base = lte_pusch_dmrs_base_sequence(0, 0, 3)
    assert_equal(len(base), 36)
    for index in range(36):
        var zc_index = index % 31
        var angle = (
            -_PI * Float64(zc_index * (zc_index + 1)) / 31.0
        )
        _assert_complex_close(
            base[index], Complex64(cos(angle), sin(angle)), 2.0e-14
        )
        _assert_close(base[index].magnitude_squared(), 1.0, 2.0e-14)
    _assert_complex_close(base[31], Complex64(1.0, 0.0), 1.0e-15)

    var shifted = lte_pusch_dmrs_sequence(0, 0, 3, 3)
    for index in range(36):
        var alpha_n = _PI * Float64(index) / 2.0
        _assert_complex_close(
            shifted[index],
            base[index] * Complex64(cos(alpha_n), sin(alpha_n)),
            3.0e-14,
        )

    # For M=72, N_ZC=71, u=5: q_bar=426/31 and v=1 selects q=13.
    var hopped = lte_pusch_dmrs_base_sequence(5, 1, 6)
    for index in [0, 1, 17, 70, 71]:
        var zc_index = index % 71
        var angle = (
            -_PI * Float64(13 * zc_index * (zc_index + 1)) / 71.0
        )
        _assert_complex_close(
            hopped[index], Complex64(cos(angle), sin(angle)), 3.0e-13
        )
    var maximum_allocation = lte_pusch_dmrs_base_sequence(29, 1, 110)
    assert_equal(len(maximum_allocation), 1320)
    _assert_close(
        maximum_allocation[1319].magnitude_squared(), 1.0, 3.0e-13
    )

    with assert_raises():
        _ = lte_pusch_dmrs_base_sequence(-1, 0, 3)
    with assert_raises():
        _ = lte_pusch_dmrs_base_sequence(30, 0, 3)
    with assert_raises():
        _ = lte_pusch_dmrs_base_sequence(0, 1, 3)
    with assert_raises():
        _ = lte_pusch_dmrs_base_sequence(0, 0, 0)
    with assert_raises():
        _ = lte_pusch_dmrs_base_sequence(0, 0, 111)
    with assert_raises():
        _ = lte_pusch_dmrs_sequence(0, 0, 3, 12)


def test_prach_format0_zc_cyclic_shift_and_normalized_waveform_oracles() raises:
    var root = lte_prach_root_sequence(1)
    assert_equal(len(root), 839)
    for index in [0, 1, 2, 417, 838]:
        var angle = (
            -_PI * Float64(index * (index + 1)) / 839.0
        )
        _assert_complex_close(
            root[index], Complex64(cos(angle), sin(angle)), 3.0e-13
        )
        _assert_close(root[index].magnitude_squared(), 1.0, 3.0e-14)
    var maximum_root = lte_prach_root_sequence(838)
    assert_equal(len(maximum_root), 839)
    _assert_close(maximum_root[838].magnitude_squared(), 1.0, 3.0e-14)

    assert_equal(lte_prach_unrestricted_cyclic_shift(3, 13), 39)
    var shifted = lte_prach_format0_sequence(1, 3, 13)
    for index in range(839):
        _assert_complex_close(
            shifted[index], root[(index + 39) % 839], 0.0
        )
    var waveform = lte_prach_format0_normalized_waveform(Span(shifted))
    assert_equal(len(waveform), 947)
    _assert_complex_close(waveform[0], shifted[731], 0.0)
    _assert_complex_close(waveform[107], shifted[838], 0.0)
    _assert_complex_close(waveform[108], shifted[0], 0.0)
    _assert_complex_close(waveform[946], shifted[838], 0.0)

    with assert_raises():
        _ = lte_prach_root_sequence(0)
    with assert_raises():
        _ = lte_prach_root_sequence(839)
    with assert_raises():
        _ = lte_prach_unrestricted_cyclic_shift(1, 0)
    with assert_raises():
        _ = lte_prach_unrestricted_cyclic_shift(64, 13)
    var short = List[Complex64](length=838, fill=Complex64(0.0, 0.0))
    with assert_raises():
        _ = lte_prach_format0_normalized_waveform(Span(short))
    var nonfinite = lte_prach_root_sequence(1)
    nonfinite[0] = Complex64(_nonfinite_from_finite_inputs(), 0.0)
    with assert_raises():
        _ = lte_prach_format0_normalized_waveform(Span(nonfinite))


def test_prach_format0_detector_complex_gain_scale_and_edges() raises:
    var transmitted = lte_prach_format0_sequence(129, 4, 13)
    var gained = List[Complex64](capacity=839)
    var large = List[Complex64](capacity=839)
    var gain = Complex64(1.25, -0.75)
    for sample in transmitted:
        gained.append(sample * gain)
        large.append(Complex64(sample.re * 1.0e300, sample.im * 1.0e300))
    var gained_detection = lte_detect_prach_format0(
        Span(gained), 129, 13, 8
    )
    assert_equal(gained_detection.preamble_index, 4)
    assert_equal(gained_detection.cyclic_shift, 52)
    _assert_close(gained_detection.metric, 1.0, 3.0e-13)
    var large_detection = lte_detect_prach_format0(
        Span(large), 129, 13, 8
    )
    assert_equal(large_detection.preamble_index, 4)
    _assert_close(large_detection.metric, 1.0, 3.0e-13)

    var waveform = lte_prach_format0_normalized_waveform(Span(gained))
    var waveform_detection = lte_detect_prach_format0(
        Span(waveform), 129, 13, 8
    )
    assert_equal(waveform_detection.preamble_index, 4)
    _assert_close(waveform_detection.metric, 1.0, 3.0e-13)

    with assert_raises():
        _ = lte_detect_prach_format0(Span(gained), 129, 13, 0)
    with assert_raises():
        _ = lte_detect_prach_format0(Span(gained), 129, 0, 2)
    var wrong = List[Complex64](length=840, fill=Complex64(0.0, 0.0))
    with assert_raises():
        _ = lte_detect_prach_format0(Span(wrong), 129, 13, 8)


def test_pdsch_siso_masked_mapping_extraction_and_boundaries() raises:
    var mask = List[UInt8](length=14 * 12 * 6, fill=UInt8(0))
    var indices: List[Int] = [0, 5, 71, 72, 1007]
    for index in indices:
        mask[index] = 1
    var symbols: List[Complex64] = [
        Complex64(1.0, -1.0),
        Complex64(2.0, -2.0),
        Complex64(3.0, -3.0),
        Complex64(4.0, -4.0),
        Complex64(5.0, -5.0),
    ]
    var grid = lte_pdsch_map_siso(Span(symbols), 6, Span(mask))
    assert_equal(len(grid), 1008)
    for symbol_index in range(len(indices)):
        _assert_complex_close(
            grid[indices[symbol_index]], symbols[symbol_index], 0.0
        )
    _assert_complex_close(grid[1], Complex64(0.0, 0.0), 0.0)
    assert_equal(
        lte_pdsch_extract_siso(Span(grid), 6, Span(mask)), symbols
    )

    var short_mask = List[UInt8](length=1007, fill=UInt8(0))
    with assert_raises():
        _ = lte_pdsch_map_siso(Span(symbols), 6, Span(short_mask))
    var invalid_mask = List[UInt8](length=1008, fill=UInt8(0))
    invalid_mask[0] = 2
    with assert_raises():
        _ = lte_pdsch_map_siso(Span(symbols), 6, Span(invalid_mask))
    var too_few: List[Complex64] = [Complex64(1.0, 0.0)]
    with assert_raises():
        _ = lte_pdsch_map_siso(Span(too_few), 6, Span(mask))
    var nonfinite_symbols = symbols.copy()
    nonfinite_symbols[0] = Complex64(
        _nonfinite_from_finite_inputs(), 0.0
    )
    with assert_raises():
        _ = lte_pdsch_map_siso(Span(nonfinite_symbols), 6, Span(mask))
    with assert_raises():
        _ = lte_pdsch_extract_siso(Span(grid), 5, Span(mask))


def test_pusch_siso_mapping_dmrs_holes_roundtrip_and_indices() raises:
    var symbols = List[Complex64](capacity=288)
    for index in range(288):
        symbols.append(Complex64(Float64(index + 1), -Float64(index + 1)))
    var grid = lte_pusch_map_siso(Span(symbols), 6, 2, 2)
    assert_equal(len(grid), 1008)
    _assert_complex_close(grid[24], symbols[0], 0.0)
    _assert_complex_close(grid[47], symbols[23], 0.0)
    _assert_complex_close(grid[96], symbols[24], 0.0)
    _assert_complex_close(grid[312], symbols[72], 0.0)
    _assert_complex_close(grid[983], symbols[287], 0.0)
    _assert_complex_close(grid[23], Complex64(0.0, 0.0), 0.0)
    for index in range(3 * 72, 4 * 72):
        _assert_complex_close(grid[index], Complex64(0.0, 0.0), 0.0)
    for index in range(10 * 72, 11 * 72):
        _assert_complex_close(grid[index], Complex64(0.0, 0.0), 0.0)
    assert_equal(lte_pusch_extract_siso(Span(grid), 6, 2, 2), symbols)

    var short = List[Complex64](length=287, fill=Complex64(0.0, 0.0))
    with assert_raises():
        _ = lte_pusch_map_siso(Span(short), 6, 2, 2)
    with assert_raises():
        _ = lte_pusch_map_siso(Span(symbols), 6, 5, 2)
    with assert_raises():
        _ = lte_pusch_map_siso(Span(symbols), 10, 0, 7)
    var nonfinite_symbols = symbols.copy()
    nonfinite_symbols[0] = Complex64(
        0.0, _nonfinite_from_finite_inputs()
    )
    with assert_raises():
        _ = lte_pusch_map_siso(Span(nonfinite_symbols), 6, 2, 2)
    var wrong_grid = List[Complex64](length=1007, fill=Complex64(0.0, 0.0))
    with assert_raises():
        _ = lte_pusch_extract_siso(Span(wrong_grid), 6, 2, 2)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
