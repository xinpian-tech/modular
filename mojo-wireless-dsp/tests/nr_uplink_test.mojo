from std.collections import Span
from std.testing import assert_equal, assert_true, assert_raises, TestSuite
from wireless_dsp.core import Complex64
from wireless_dsp.wireless.nr import (
    nr_pdsch_scramble,
    nr_pusch_scramble,
    nr_pusch_descramble_llrs,
    nr_pusch_transform_precoding,
    nr_pusch_transform_deprecoding,
    nr_pusch_dmrs_c_init,
    nr_pusch_dmrs,
    nr_prach_root_sequence,
    nr_prach_sequence,
    nr_prach_unrestricted_cyclic_shift,
    nr_detect_prach_unrestricted,
)


def _assert_complex_close(actual: Complex64, expected: Complex64, tolerance: Float64) raises:
    assert_true(abs(actual.re - expected.re) <= tolerance)
    assert_true(abs(actual.im - expected.im) <= tolerance)


def test_pusch_scrambling_and_soft_inverse() raises:
    var bits = List[UInt8](capacity=127)
    for i in range(127):
        bits.append(UInt8((i * 9 + i // 4) & 1))
    var scrambled = nr_pusch_scramble(Span(bits), 0x4567, 1, 721)
    # Ordinary PUSCH and PDSCH use the same c_init for binary data positions.
    assert_equal(scrambled, nr_pdsch_scramble(Span(bits), 0x4567, 1, 721))
    var channel_llrs = List[Float64](capacity=len(scrambled))
    for bit in scrambled:
        channel_llrs.append(7.0 if bit == 0 else -7.0)
    var restored = nr_pusch_descramble_llrs(
        Span(channel_llrs), 0x4567, 1, 721
    )
    for i in range(len(bits)):
        assert_true(restored[i] > 0.0 if bits[i] == 0 else restored[i] < 0.0)


def test_pusch_unitary_dft_spreading_roundtrip_non_power_of_two() raises:
    for length in [12, 24, 36]:
        var symbols = List[Complex64](capacity=length)
        var input_energy = 0.0
        for i in range(length):
            var value = Complex64(
                Float64((7 * i) % 11) - 5.0,
                Float64((3 * i) % 7) - 3.0,
            )
            symbols.append(value)
            input_energy += value.magnitude_squared()
        var spread = nr_pusch_transform_precoding(Span(symbols))
        var spread_energy = 0.0
        for value in spread:
            spread_energy += value.magnitude_squared()
        assert_true(abs(spread_energy - input_energy) < 1.0e-9)
        var restored = nr_pusch_transform_deprecoding(Span(spread))
        for i in range(length):
            _assert_complex_close(restored[i], symbols[i], 1.0e-10)


def test_pusch_dmrs_initialization_and_unit_power() raises:
    assert_equal(nr_pusch_dmrs_c_init(7, 4, 321, 1), UInt32(90833539))
    var sequence = nr_pusch_dmrs(7, 4, 321, 1, 72)
    for value in sequence:
        assert_true(abs(value.magnitude_squared() - 1.0) < 1.0e-12)


def test_prach_root_and_cyclic_shift_known_properties() raises:
    var root = nr_prach_root_sequence(129, 839)
    _assert_complex_close(root[0], Complex64(1.0), 1.0e-12)
    for value in root:
        assert_true(abs(value.magnitude_squared() - 1.0) < 1.0e-10)
    var shifted = nr_prach_sequence(129, 839, 52)
    for i in range(839):
        _assert_complex_close(shifted[i], root[(i + 52) % 839], 1.0e-12)
    assert_equal(nr_prach_unrestricted_cyclic_shift(3, 13, 839), 39)
    for sequence_length in [139, 839]:
        for n_cs in [1, 13, sequence_length - 1]:
            for preamble_index in range(sequence_length // n_cs):
                assert_equal(
                    nr_prach_unrestricted_cyclic_shift(
                        preamble_index, n_cs, sequence_length
                    ),
                    preamble_index * n_cs,
                )
        assert_equal(
            nr_prach_unrestricted_cyclic_shift(0, 0, sequence_length),
            0,
        )


def test_prach_detector_finds_preamble_under_complex_gain() raises:
    var transmitted = nr_prach_sequence(17, 139, 4 * 13)
    var gain = Complex64(0.7, -0.4)
    for i in range(len(transmitted)):
        transmitted[i] = transmitted[i] * gain
    var detection = nr_detect_prach_unrestricted(
        Span(transmitted), 17, 13, 8
    )
    assert_equal(detection.preamble_index, 4)
    assert_equal(detection.cyclic_shift, 52)
    assert_true(detection.metric > 0.999999999)


def test_uplink_validation_edges() raises:
    var eleven = List[Complex64](length=11, fill=Complex64(0.0))
    with assert_raises():
        _ = nr_pusch_transform_precoding(Span(eleven))
    with assert_raises():
        _ = nr_prach_root_sequence(0, 839)
    with assert_raises():
        _ = nr_prach_unrestricted_cyclic_shift(1, 0, 139)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
