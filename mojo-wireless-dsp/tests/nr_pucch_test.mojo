from std.collections import Span
from std.testing import assert_equal, assert_true, assert_raises, TestSuite
from wireless_dsp.core import Complex64
from wireless_dsp.modem import qam_demap_hard
from wireless_dsp.wireless.nr import (
    PUCCH_GROUP_HOPPING_NEITHER,
    PUCCH_GROUP_HOPPING_ENABLE,
    PUCCH_SEQUENCE_HOPPING_ENABLE,
    nr_pucch_group_neither,
    nr_pucch_group_sequence_hopping,
    nr_pucch_cyclic_shift_index,
    nr_pucch_low_papr_sequence_12,
    nr_pucch_format0_sequence,
    nr_pucch_format1_sequence,
    nr_pucch_scramble,
    nr_pucch_format2_modulate,
    nr_pi_over_2_bpsk,
    nr_pucch_format3_4_modulate,
    nr_pucch_block_spread,
    nr_pucch_block_despread,
)


def _assert_complex_close(actual: Complex64, expected: Complex64, tolerance: Float64) raises:
    assert_true(abs(actual.re - expected.re) <= tolerance)
    assert_true(abs(actual.im - expected.im) <= tolerance)


def _reference_gold_bits(c_init: UInt32, length: Int) -> List[UInt8]:
    """Scalar two-register 38.211 recurrence, independent of nr_gold_bits."""
    var x1 = UInt32(1)
    var x2 = c_init & UInt32(0x7FFFFFFF)
    var result = List[UInt8](capacity=length)
    for index in range(1600 + length):
        var output = UInt8((x1 ^ x2) & UInt32(1))
        var feedback1 = ((x1 >> 3) ^ x1) & UInt32(1)
        var feedback2 = (
            (x2 >> 3) ^ (x2 >> 2) ^ (x2 >> 1) ^ x2
        ) & UInt32(1)
        x1 = (x1 >> 1) | (feedback1 << 30)
        x2 = (x2 >> 1) | (feedback2 << 30)
        if index >= 1600:
            result.append(output)
    return result^


def test_low_papr_table_vectors_and_cyclic_orthogonality() raises:
    var root = nr_pucch_low_papr_sequence_12(0, 0)
    var scale = 0.7071067811865475244
    _assert_complex_close(root[0], Complex64(-scale, -scale), 1.0e-12)
    _assert_complex_close(root[1], Complex64(scale, scale), 1.0e-12)
    _assert_complex_close(root[5], Complex64(-scale, scale), 1.0e-12)
    var shifted = nr_pucch_format0_sequence(0, 1)
    var dot = Complex64(0.0, 0.0)
    for i in range(12):
        dot = dot + root[i].conjugate() * shifted[i]
    assert_true(dot.magnitude_squared() < 1.0e-20)
    for value in shifted:
        assert_true(abs(value.magnitude_squared() - 1.0) < 1.0e-12)


def test_group_and_cyclic_shift_hopping_are_deterministic() raises:
    assert_equal(nr_pucch_group_neither(1007), 17)
    var first = nr_pucch_cyclic_shift_index(9, 4, 3, 5, 777)
    var second = nr_pucch_cyclic_shift_index(9, 4, 3, 5, 777)
    assert_equal(first, second)
    assert_true(first >= 0 and first < 12)


def test_group_and_sequence_hopping_official_equations() raises:
    var neither = nr_pucch_group_sequence_hopping(
        7, 1, 1, 321, PUCCH_GROUP_HOPPING_NEITHER
    )
    assert_equal(neither.group, 21)
    assert_equal(neither.sequence_number, 0)

    # Independently generated from the two Gold initializations and offsets
    # in TS 38.211 6.3.2.2.1 (20 slots/frame for mu=1).
    var group_first = nr_pucch_group_sequence_hopping(
        7, 1, 0, 321, PUCCH_GROUP_HOPPING_ENABLE
    )
    var group_second = nr_pucch_group_sequence_hopping(
        7, 1, 1, 321, PUCCH_GROUP_HOPPING_ENABLE
    )
    assert_equal(group_first.group, 3)
    assert_equal(group_second.group, 16)
    assert_equal(group_first.sequence_number, 0)

    var sequence_first = nr_pucch_group_sequence_hopping(
        7, 1, 0, 321, PUCCH_SEQUENCE_HOPPING_ENABLE
    )
    var sequence_second = nr_pucch_group_sequence_hopping(
        7, 1, 1, 321, PUCCH_SEQUENCE_HOPPING_ENABLE
    )
    assert_equal(sequence_first.group, 21)
    assert_equal(sequence_first.sequence_number, 0)
    assert_equal(sequence_second.sequence_number, 1)


def test_hopping_table_configs_against_integer_and_gold_oracles() raises:
    # Exhaust the finite identity domain for the non-hopping table rule.
    for n_id in range(1024):
        assert_equal(nr_pucch_group_neither(n_id), n_id % 30)

    # The expected Gold bits come from the scalar packed-register recurrence
    # above, not from the production sequence generator used by these APIs.
    for n_id in [0, 29, 30, 321, 1023]:
        for numerology in [0, 1, 3]:
            var slots_per_frame = 10 * (1 << numerology)
            for slot in [0, slots_per_frame - 1]:
                for frequency_hop in [0, 1]:
                    var f_ss = n_id % 30
                    var group_offset = 8 * (
                        2 * slots_per_frame * slot + frequency_hop
                    )
                    var group_gold = _reference_gold_bits(
                        UInt32(n_id // 30), group_offset + 8
                    )
                    var f_gh = 0
                    for bit in range(8):
                        f_gh += (1 << bit) * Int(
                            group_gold[group_offset + bit]
                        )
                    var group = nr_pucch_group_sequence_hopping(
                        slot,
                        numerology,
                        frequency_hop,
                        n_id,
                        PUCCH_GROUP_HOPPING_ENABLE,
                    )
                    assert_equal(group.group, (f_ss + f_gh) % 30)
                    assert_equal(group.sequence_number, 0)

                    var sequence_offset = (
                        2 * slots_per_frame * slot + frequency_hop
                    )
                    var sequence_gold = _reference_gold_bits(
                        UInt32(32 * (n_id // 30) + f_ss),
                        sequence_offset + 1,
                    )
                    var sequence = nr_pucch_group_sequence_hopping(
                        slot,
                        numerology,
                        frequency_hop,
                        n_id,
                        PUCCH_SEQUENCE_HOPPING_ENABLE,
                    )
                    assert_equal(sequence.group, f_ss)
                    assert_equal(
                        sequence.sequence_number,
                        Int(sequence_gold[sequence_offset]),
                    )

    for symbols_per_slot in [12, 14]:
        for slot in [0, 1, 17]:
            for symbol in [0, symbols_per_slot - 1]:
                var n_id = 777
                var offset = 8 * (
                    symbols_per_slot * slot + symbol
                )
                var gold = _reference_gold_bits(
                    UInt32(n_id), offset + 8
                )
                var hopping = 0
                for bit in range(8):
                    hopping += (1 << bit) * Int(gold[offset + bit])
                for m0 in [0, 5, 11]:
                    for m_cs in [0, 7, 11]:
                        assert_equal(
                            nr_pucch_cyclic_shift_index(
                                slot,
                                symbol,
                                m0,
                                m_cs,
                                n_id,
                                symbols_per_slot=symbols_per_slot,
                            ),
                            (m0 + m_cs + hopping) % 12,
                        )


def test_format1_bpsk_and_qpsk_sequence_modulation() raises:
    var zero: List[UInt8] = [0]
    var one: List[UInt8] = [1]
    var base = nr_pucch_format0_sequence(7, 3)
    var positive = nr_pucch_format1_sequence(Span(zero), 7, 3)
    var negative = nr_pucch_format1_sequence(Span(one), 7, 3)
    for i in range(12):
        _assert_complex_close(positive[i], base[i], 1.0e-12)
        _assert_complex_close(negative[i], -base[i], 1.0e-12)
    var qpsk_bits: List[UInt8] = [0, 0]
    var qpsk = nr_pucch_format1_sequence(Span(qpsk_bits), 7, 3)
    var scale = 0.7071067811865475244
    for i in range(12):
        _assert_complex_close(qpsk[i], base[i] * Complex64(scale, scale), 1.0e-12)


def test_format2_scrambling_and_qpsk_roundtrip() raises:
    var bits: List[UInt8] = [0,1,1,0, 1,1,0,0, 1,0,0,1]
    var scrambled = nr_pucch_scramble(Span(bits), 0x2345, 511)
    var symbols = nr_pucch_format2_modulate(Span(bits), 0x2345, 511)
    assert_equal(qam_demap_hard(Span(symbols), 2), scrambled)
    # XOR scrambling is its own inverse when regenerated with the same c_init.
    assert_equal(nr_pucch_scramble(Span(scrambled), 0x2345, 511), bits)


def test_pi_over_2_bpsk_and_block_spreading_roundtrip() raises:
    var bits: List[UInt8] = [0, 0, 1, 1]
    var symbols = nr_pi_over_2_bpsk(Span(bits))
    var scale = 0.7071067811865475244
    _assert_complex_close(symbols[0], Complex64(scale, scale), 1.0e-12)
    _assert_complex_close(symbols[1], Complex64(-scale, scale), 1.0e-12)
    _assert_complex_close(symbols[2], Complex64(-scale, -scale), 1.0e-12)
    _assert_complex_close(symbols[3], Complex64(scale, -scale), 1.0e-12)
    var format4 = nr_pucch_format3_4_modulate(
        Span(bits), 0x1111, 72, pi_over_2_bpsk=True
    )
    var spread = nr_pucch_block_spread(Span(format4), 4, 3)
    var restored = nr_pucch_block_despread(Span(spread), 4, 3)
    for i in range(len(format4)):
        _assert_complex_close(restored[i], format4[i], 1.0e-12)


def test_pucch_validation() raises:
    var three: List[UInt8] = [0, 1, 0]
    with assert_raises():
        _ = nr_pucch_format1_sequence(Span(three), 0, 0)
    with assert_raises():
        _ = nr_pucch_format2_modulate(Span(three), 1, 1)
    var values: List[Complex64] = [Complex64(1.0)]
    with assert_raises():
        _ = nr_pucch_block_spread(Span(values), 3, 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
