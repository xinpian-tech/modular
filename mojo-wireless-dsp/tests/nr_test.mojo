from std.testing import assert_equal, assert_true, assert_raises, TestSuite
from wireless_dsp.core import Span
from wireless_dsp.wireless.nr import (
    nr_gold_bits,
    nr_qpsk_sequence,
    nr_pss,
    nr_sss,
    nr_pdsch_scramble,
    nr_pdsch_dmrs,
    nr_rate_recover_llrs,
    nr_transport_crc_width,
    nr_transport_crc,
    nr_select_base_graph,
    nr_lifting_set_index,
    nr_base_graph_dimensions,
    nr_ldpc_profile,
    nr_qc_expand_edges,
)


def test_nr_pss_sequences_and_separation() raises:
    var pss0 = nr_pss(0)
    var pss1 = nr_pss(1)
    var pss2 = nr_pss(2)
    assert_equal(len(pss0), 127)
    assert_equal(len(pss1), 127)
    assert_equal(len(pss2), 127)
    var energy0 = 0.0
    var energy1 = 0.0
    var energy2 = 0.0
    for i in range(127):
        assert_true(pss0[i] == -1.0 or pss0[i] == 1.0)
        energy0 += pss0[i] * pss0[i]
        energy1 += pss1[i] * pss1[i]
        energy2 += pss2[i] * pss2[i]
    assert_equal(energy0, 127.0)
    assert_equal(energy1, 127.0)
    assert_equal(energy2, 127.0)
    var cross01 = 0.0
    var cross02 = 0.0
    for i in range(127):
        cross01 += pss0[i] * pss1[i]
        cross02 += pss0[i] * pss2[i]
    assert_true(abs(cross01) < 20.0)
    assert_true(abs(cross02) < 20.0)


def test_nr_sss_all_cell_identity_boundaries() raises:
    for n_id_1 in [0, 111, 112, 335]:
        for n_id_2 in [0, 1, 2]:
            var sequence = nr_sss(n_id_1, n_id_2)
            assert_equal(len(sequence), 127)
            for value in sequence:
                assert_true(value == -1.0 or value == 1.0)


def test_nr_gold_qpsk_and_pdsch_scrambling() raises:
    var seed = UInt32(0x1234567)
    var bits = nr_gold_bits(seed, 257)
    assert_equal(len(bits), 257)
    var qpsk_bits = nr_gold_bits(seed, 8)
    var qpsk = nr_qpsk_sequence(seed, 4)
    var scale = 0.70710678118654752440084436210485
    for index in range(4):
        assert_true(
            abs(
                qpsk[index].re
                - scale * (1.0 - 2.0 * Float64(qpsk_bits[2 * index]))
            ) < 1.0e-15
        )
        assert_true(
            abs(
                qpsk[index].im
                - scale * (1.0 - 2.0 * Float64(qpsk_bits[2 * index + 1]))
            ) < 1.0e-15
        )
    with assert_raises():
        _ = nr_qpsk_sequence(seed, -1)
    with assert_raises():
        _ = nr_qpsk_sequence(seed, Int.MAX)
    var payload = List[UInt8](capacity=257)
    for i in range(257):
        payload.append(UInt8((i * 13 + 5) & 1))
    var scrambled = nr_pdsch_scramble(Span(payload), 0x1234, 1, 42)
    assert_equal(nr_pdsch_scramble(Span(scrambled), 0x1234, 1, 42), payload)
    var dmrs = nr_pdsch_dmrs(UInt32(99), 100)
    var energy = 0.0
    for value in dmrs:
        energy += value.re * value.re + value.im * value.im
    assert_true(abs(energy - 100.0) < 1.0e-12)


def test_nr_rate_recovery_combines_repetition_and_skips_filler() raises:
    var received: List[Float64] = [1.0, 2.0, 3.0, 4.0, 5.0, 6.0]
    var filler: List[UInt8] = [0, 1, 0, 0]
    var recovered = nr_rate_recover_llrs(Span(received), 4, 0, Span(filler))
    assert_equal(recovered, [5.0, 0.0, 7.0, 9.0])


def test_nr_transport_crc_selection() raises:
    assert_equal(nr_transport_crc_width(3824), 16)
    assert_equal(nr_transport_crc_width(3825), 24)
    var bits: List[UInt8] = [1, 0, 1, 1]
    assert_equal(nr_transport_crc(Span(bits)), UInt64(0xB16B))


def test_nr_ldpc_selection_lifting_and_qc_expansion() raises:
    assert_equal(nr_base_graph_dimensions(1), (46, 68, 22))
    assert_equal(nr_base_graph_dimensions(2), (42, 52, 10))
    with assert_raises():
        _ = nr_base_graph_dimensions(0)
    assert_equal(nr_select_base_graph(292, 0.9), 2)
    assert_equal(nr_select_base_graph(4000, 0.5), 1)
    assert_equal(nr_select_base_graph(10000, 0.25), 2)
    assert_equal(nr_lifting_set_index(256), 0)
    assert_equal(nr_lifting_set_index(384), 1)
    assert_equal(nr_lifting_set_index(320), 2)
    assert_equal(nr_lifting_set_index(17), -1)
    var small = nr_ldpc_profile(100, 0.5)
    assert_equal(small.base_graph, 2)
    assert_equal(small.lifting_size, 20)
    assert_equal(small.code_block_bits, 120)
    var large = nr_ldpc_profile(4000, 0.5)
    assert_equal(large.base_graph, 1)
    assert_equal(large.lifting_size, 192)

    var rows: List[Int] = [0, 0]
    var columns: List[Int] = [0, 1]
    var shifts: List[Int] = [0, 1]
    var graph = nr_qc_expand_edges(
        1, 2, Span(rows), Span(columns), Span(shifts), 2
    )
    assert_equal(graph.row_offsets, [0, 2, 4])
    assert_equal(graph.columns, [0, 3, 1, 2])
    assert_equal(graph.variable_count, 4)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
