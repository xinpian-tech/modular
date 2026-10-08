from std.collections import Span
from std.testing import assert_equal, assert_true, assert_raises, TestSuite
from wireless_dsp.core import Complex64
from wireless_dsp.wireless.nr.grid import NRResourceGrid
from wireless_dsp.wireless.nr.pucch_resources import (
    nr_pucch_format1_data_occ_length,
    nr_pucch_format1_dmrs_occ_length,
    nr_pucch_format1_occ_phases,
    nr_pucch_format1_occ,
    nr_pucch_format1_data_occ,
    nr_pucch_format1_dmrs_occ,
    nr_pucch_format1_apply_occ,
    nr_pucch_format2_dmrs_c_init,
    nr_pucch_format2_dmrs,
    nr_pucch_format2_data_re_count,
    nr_pucch_format2_dmrs_re_count,
    nr_map_pucch_format2,
    nr_extract_pucch_format2_data,
    nr_extract_pucch_format2_dmrs,
    nr_pucch_format3_4_dmrs_positions,
    nr_pucch_format3_4_data_re_count,
    nr_pucch_format3_4_dmrs_re_count,
    nr_map_pucch_format3_4_non_interlaced,
    nr_extract_pucch_format3_4_data_non_interlaced,
    nr_extract_pucch_format3_4_dmrs_non_interlaced,
)


def _assert_complex_close(
    actual: Complex64, expected: Complex64, tolerance: Float64,
) raises:
    assert_true(abs(actual.re - expected.re) <= tolerance)
    assert_true(abs(actual.im - expected.im) <= tolerance)


def _complex_ramp(count: Int, offset: Int) -> List[Complex64]:
    var result = List[Complex64](capacity=count)
    for index in range(count):
        var value = Float64(offset + index)
        result.append(Complex64(value, -value - 0.25))
    return result^


def test_format1_normative_occ_length_tables() raises:
    # Independent transcriptions of Tables 6.3.2.4.1-1 and 6.4.1.3.1.1-1,
    # indexed by PUCCH length 4 through 14.
    var data_no_hop: List[Int] = [2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7]
    var data_hop_0: List[Int] = [1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3]
    var data_hop_1: List[Int] = [1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4]
    var dmrs_no_hop: List[Int] = [2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7]
    var dmrs_hop_0: List[Int] = [1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4]
    var dmrs_hop_1: List[Int] = [1, 2, 1, 2, 2, 3, 2, 3, 3, 4, 3]
    for offset in range(11):
        var length = offset + 4
        assert_equal(
            nr_pucch_format1_data_occ_length(length), data_no_hop[offset]
        )
        assert_equal(
            nr_pucch_format1_data_occ_length(
                length, intra_slot_hopping=True, hop=0
            ),
            data_hop_0[offset],
        )
        assert_equal(
            nr_pucch_format1_data_occ_length(
                length, intra_slot_hopping=True, hop=1
            ),
            data_hop_1[offset],
        )
        assert_equal(
            nr_pucch_format1_dmrs_occ_length(length), dmrs_no_hop[offset]
        )
        assert_equal(
            nr_pucch_format1_dmrs_occ_length(
                length, intra_slot_hopping=True, hop=0
            ),
            dmrs_hop_0[offset],
        )
        assert_equal(
            nr_pucch_format1_dmrs_occ_length(
                length, intra_slot_hopping=True, hop=1
            ),
            dmrs_hop_1[offset],
        )


def test_format1_complete_normative_occ_phase_table() raises:
    # Table 6.3.2.4.1-2, flattened by N_SF, orthogonal index, then m.
    var expected: List[Int] = [
        0,
        0, 0,  0, 1,
        0, 0, 0,  0, 1, 2,  0, 2, 1,
        0, 0, 0, 0,  0, 2, 0, 2,
        0, 0, 2, 2,  0, 2, 2, 0,
        0, 0, 0, 0, 0,  0, 1, 2, 3, 4,
        0, 2, 4, 1, 3,  0, 3, 1, 4, 2,
        0, 4, 3, 2, 1,
        0, 0, 0, 0, 0, 0,  0, 1, 2, 3, 4, 5,
        0, 2, 4, 0, 2, 4,  0, 3, 0, 3, 0, 3,
        0, 4, 2, 0, 4, 2,  0, 5, 4, 3, 2, 1,
        0, 0, 0, 0, 0, 0, 0,  0, 1, 2, 3, 4, 5, 6,
        0, 2, 4, 6, 1, 3, 5,  0, 3, 6, 2, 5, 1, 4,
        0, 4, 1, 5, 2, 6, 3,  0, 5, 3, 1, 6, 4, 2,
        0, 6, 5, 4, 3, 2, 1,
    ]
    var cursor = 0
    for spreading_factor in range(1, 8):
        for orthogonal_index in range(spreading_factor):
            var phases = nr_pucch_format1_occ_phases(
                spreading_factor, orthogonal_index
            )
            assert_equal(len(phases), spreading_factor)
            for m in range(spreading_factor):
                assert_equal(phases[m], expected[cursor])
                cursor += 1
    assert_equal(cursor, len(expected))


def test_format1_data_dmrs_occ_and_block_spreading() raises:
    var data_occ = nr_pucch_format1_data_occ(8, 2)
    assert_equal(len(data_occ), 4)
    _assert_complex_close(data_occ[0], Complex64(1.0, 0.0), 1.0e-12)
    _assert_complex_close(data_occ[1], Complex64(1.0, 0.0), 1.0e-12)
    _assert_complex_close(data_occ[2], Complex64(-1.0, 0.0), 1.0e-12)
    _assert_complex_close(data_occ[3], Complex64(-1.0, 0.0), 1.0e-12)

    var dmrs_occ = nr_pucch_format1_dmrs_occ(
        5, 1, intra_slot_hopping=True, hop=1
    )
    assert_equal(len(dmrs_occ), 2)
    _assert_complex_close(dmrs_occ[0], Complex64(1.0, 0.0), 1.0e-12)
    _assert_complex_close(dmrs_occ[1], Complex64(-1.0, 0.0), 1.0e-12)

    var base: List[Complex64] = [Complex64(2.0, -1.0), Complex64(-3.0, 0.5)]
    var spread = nr_pucch_format1_apply_occ(Span(base), Span(dmrs_occ))
    assert_equal(len(spread), 4)
    _assert_complex_close(spread[0], base[0], 1.0e-12)
    _assert_complex_close(spread[1], base[1], 1.0e-12)
    _assert_complex_close(spread[2], -base[0], 1.0e-12)
    _assert_complex_close(spread[3], -base[1], 1.0e-12)

    # A non-Walsh row exercises the complex exponential definition.
    var dft_occ = nr_pucch_format1_occ(3, 1)
    _assert_complex_close(
        dft_occ[1], Complex64(-0.5, 0.8660254037844386468), 1.0e-12
    )


def test_format2_c_init_and_independent_gold_vector() raises:
    # Direct evaluation of the clause 6.4.1.3.2.1 initialization equation.
    assert_equal(
        nr_pucch_format2_dmrs_c_init(7, 9, 321), UInt32(0x1E880282)
    )
    assert_equal(nr_pucch_format2_dmrs_c_init(0, 0, 0), UInt32(0x20000))
    assert_equal(
        nr_pucch_format2_dmrs_c_init(19, 11, 65535, symbols_per_slot=12),
        UInt32(0x7E21FFFE),
    )

    # Independently generated x1/x2 state after Nc=1600.  Each pair is the
    # unscaled QPSK sign for four PRBs (16 DM-RS resource elements).
    var expected_re: List[Int] = [
        -1, -1,  -1, -1,  -1, -1,  -1, -1,
         1, -1,  -1, -1,  -1, -1,   1,  1,
         1,  1,   1, -1,   1,  1,  -1, -1,
        -1, -1,   1,  1,  -1, -1,  -1,  1,
    ]
    var dmrs = nr_pucch_format2_dmrs(7, 9, 321, 4)
    assert_equal(len(dmrs), 16)
    var scale = 0.7071067811865475244
    for index in range(16):
        _assert_complex_close(
            dmrs[index],
            Complex64(
                scale * Float64(expected_re[2 * index]),
                scale * Float64(expected_re[2 * index + 1]),
            ),
            1.0e-12,
        )

    # Table 6.3.2.5A-1 OCC index 1 is [+1,-1], applied to each Gold symbol.
    var spread = nr_pucch_format2_dmrs(
        7, 9, 321, 1, spreading_factor=2, orthogonal_index=1
    )
    assert_equal(len(spread), 4)
    _assert_complex_close(spread[0], -spread[1], 1.0e-12)
    _assert_complex_close(spread[2], -spread[3], 1.0e-12)


def test_format2_k_3m_plus_1_map_extract_roundtrip() raises:
    var grid = NRResourceGrid(4, 48)
    var data = _complex_ramp(nr_pucch_format2_data_re_count(2, 2), 100)
    var dmrs = _complex_ramp(nr_pucch_format2_dmrs_re_count(2, 2), 1000)
    nr_map_pucch_format2(
        grid, 1, 12, 2, 2, Span(data), Span(dmrs)
    )
    assert_equal(
        nr_extract_pucch_format2_data(grid, 1, 12, 2, 2), data
    )
    assert_equal(
        nr_extract_pucch_format2_dmrs(grid, 1, 12, 2, 2), dmrs
    )

    var data_index = 0
    var dmrs_index = 0
    for local_symbol in range(2):
        for local_subcarrier in range(24):
            var actual = grid[1 + local_symbol, 12 + local_subcarrier]
            if local_subcarrier % 3 == 1:
                _assert_complex_close(actual, dmrs[dmrs_index], 0.0)
                dmrs_index += 1
            else:
                _assert_complex_close(actual, data[data_index], 0.0)
                data_index += 1
    _assert_complex_close(grid[0, 11], Complex64(0.0, 0.0), 0.0)
    _assert_complex_close(grid[3, 36], Complex64(0.0, 0.0), 0.0)


def test_format3_4_complete_dmrs_position_table() raises:
    # Every row of Table 6.4.1.3.3.2-1, including the only hopping-specific
    # row and every additional-DM-RS row.
    assert_equal(nr_pucch_format3_4_dmrs_positions(4), [1])
    assert_equal(
        nr_pucch_format3_4_dmrs_positions(4, intra_slot_hopping=True),
        [0, 2],
    )
    assert_equal(
        nr_pucch_format3_4_dmrs_positions(4, additional_dmrs=True), [1]
    )
    assert_equal(
        nr_pucch_format3_4_dmrs_positions(
            4, intra_slot_hopping=True, additional_dmrs=True
        ),
        [0, 2],
    )
    assert_equal(nr_pucch_format3_4_dmrs_positions(5), [0, 3])
    assert_equal(nr_pucch_format3_4_dmrs_positions(6), [1, 4])
    assert_equal(nr_pucch_format3_4_dmrs_positions(7), [1, 4])
    assert_equal(nr_pucch_format3_4_dmrs_positions(8), [1, 5])
    assert_equal(nr_pucch_format3_4_dmrs_positions(9), [1, 6])
    assert_equal(nr_pucch_format3_4_dmrs_positions(10), [2, 7])
    assert_equal(nr_pucch_format3_4_dmrs_positions(11), [2, 7])
    assert_equal(nr_pucch_format3_4_dmrs_positions(12), [2, 8])
    assert_equal(nr_pucch_format3_4_dmrs_positions(13), [2, 9])
    assert_equal(nr_pucch_format3_4_dmrs_positions(14), [3, 10])
    assert_equal(
        nr_pucch_format3_4_dmrs_positions(10, additional_dmrs=True),
        [1, 3, 6, 8],
    )
    assert_equal(
        nr_pucch_format3_4_dmrs_positions(11, additional_dmrs=True),
        [1, 3, 6, 9],
    )
    assert_equal(
        nr_pucch_format3_4_dmrs_positions(12, additional_dmrs=True),
        [1, 4, 7, 10],
    )
    assert_equal(
        nr_pucch_format3_4_dmrs_positions(13, additional_dmrs=True),
        [1, 4, 7, 11],
    )
    assert_equal(
        nr_pucch_format3_4_dmrs_positions(
            14, intra_slot_hopping=True, additional_dmrs=True
        ),
        [1, 5, 8, 12],
    )


def test_format3_4_non_interlaced_map_extract_roundtrip() raises:
    var grid = NRResourceGrid(14, 60)
    var data_count = nr_pucch_format3_4_data_re_count(
        10, 2, additional_dmrs=True
    )
    var dmrs_count = nr_pucch_format3_4_dmrs_re_count(
        10, 2, additional_dmrs=True
    )
    assert_equal(data_count, 144)
    assert_equal(dmrs_count, 96)
    var data = _complex_ramp(data_count, 10)
    var dmrs = _complex_ramp(dmrs_count, 1000)
    nr_map_pucch_format3_4_non_interlaced(
        grid,
        2,
        12,
        2,
        10,
        Span(data),
        Span(dmrs),
        additional_dmrs=True,
    )
    assert_equal(
        nr_extract_pucch_format3_4_data_non_interlaced(
            grid, 2, 12, 2, 10, additional_dmrs=True
        ),
        data,
    )
    assert_equal(
        nr_extract_pucch_format3_4_dmrs_non_interlaced(
            grid, 2, 12, 2, 10, additional_dmrs=True
        ),
        dmrs,
    )
    # Relative symbol 1 is DM-RS; relative symbol 2 is data.
    _assert_complex_close(grid[3, 12], dmrs[0], 0.0)
    _assert_complex_close(grid[4, 12], data[24], 0.0)


def test_format3_4_hopping_uses_floor_half_symbol_boundary() raises:
    var grid = NRResourceGrid(4, 48)
    var data = _complex_ramp(
        nr_pucch_format3_4_data_re_count(
            4, 1, intra_slot_hopping=True
        ),
        20,
    )
    var dmrs = _complex_ramp(
        nr_pucch_format3_4_dmrs_re_count(
            4, 1, intra_slot_hopping=True
        ),
        200,
    )
    nr_map_pucch_format3_4_non_interlaced(
        grid,
        0,
        0,
        1,
        4,
        Span(data),
        Span(dmrs),
        intra_slot_hopping=True,
        second_hop_first_subcarrier=24,
    )
    assert_equal(
        nr_extract_pucch_format3_4_data_non_interlaced(
            grid,
            0,
            0,
            1,
            4,
            intra_slot_hopping=True,
            second_hop_first_subcarrier=24,
        ),
        data,
    )
    assert_equal(
        nr_extract_pucch_format3_4_dmrs_non_interlaced(
            grid,
            0,
            0,
            1,
            4,
            intra_slot_hopping=True,
            second_hop_first_subcarrier=24,
        ),
        dmrs,
    )
    # Symbols 0/1 use the first hop, symbols 2/3 use the second hop.
    _assert_complex_close(grid[0, 0], dmrs[0], 0.0)
    _assert_complex_close(grid[1, 0], data[0], 0.0)
    _assert_complex_close(grid[2, 24], dmrs[12], 0.0)
    _assert_complex_close(grid[3, 24], data[12], 0.0)
    _assert_complex_close(grid[2, 0], Complex64(0.0, 0.0), 0.0)


def test_resource_count_exact_integer_oracles() raises:
    # Format 2 has exactly eight data and four DM-RS RE per PRB-symbol.
    for symbol_count in [1, 2, 7, 14]:
        for resource_blocks in [1, 2, 17, 275]:
            assert_equal(
                nr_pucch_format2_data_re_count(
                    symbol_count, resource_blocks
                ),
                8 * symbol_count * resource_blocks,
            )
            assert_equal(
                nr_pucch_format2_dmrs_re_count(
                    symbol_count, resource_blocks
                ),
                4 * symbol_count * resource_blocks,
            )

    # The complete position table is independently transcribed in
    # test_format3_4_complete_dmrs_position_table.  Here an orthogonal integer
    # accounting traversal proves the two count APIs partition all REs.
    for pucch_symbols in range(4, 15):
        for resource_blocks in [1, 2, 3, 5, 6, 10]:
            for intra_slot_hopping in [False, True]:
                for additional_dmrs in [False, True]:
                    var positions = nr_pucch_format3_4_dmrs_positions(
                        pucch_symbols,
                        intra_slot_hopping=intra_slot_hopping,
                        additional_dmrs=additional_dmrs,
                    )
                    var expected_dmrs = (
                        12 * resource_blocks * len(positions)
                    )
                    var expected_data = 12 * resource_blocks * (
                        pucch_symbols - len(positions)
                    )
                    var actual_dmrs = nr_pucch_format3_4_dmrs_re_count(
                        pucch_symbols,
                        resource_blocks,
                        intra_slot_hopping=intra_slot_hopping,
                        additional_dmrs=additional_dmrs,
                    )
                    var actual_data = nr_pucch_format3_4_data_re_count(
                        pucch_symbols,
                        resource_blocks,
                        intra_slot_hopping=intra_slot_hopping,
                        additional_dmrs=additional_dmrs,
                    )
                    assert_equal(actual_dmrs, expected_dmrs)
                    assert_equal(actual_data, expected_data)
                    assert_equal(
                        actual_dmrs + actual_data,
                        12 * resource_blocks * pucch_symbols,
                    )


def test_pucch_resource_boundaries_and_rejections() raises:
    with assert_raises():
        _ = nr_pucch_format1_data_occ_length(3)
    with assert_raises():
        _ = nr_pucch_format1_dmrs_occ_length(14, hop=1)
    with assert_raises():
        _ = nr_pucch_format1_occ_phases(4, 4)
    with assert_raises():
        _ = nr_pucch_format2_dmrs_c_init(-1, 0, 0)
    with assert_raises():
        _ = nr_pucch_format2_dmrs_c_init(0, 14, 0)
    with assert_raises():
        _ = nr_pucch_format2_dmrs_c_init(0, 0, 65536)
    with assert_raises():
        _ = nr_pucch_format2_dmrs(0, 0, 0, 1, spreading_factor=3)
    with assert_raises():
        _ = nr_pucch_format3_4_dmrs_positions(15)
    with assert_raises():
        _ = nr_pucch_format3_4_data_re_count(4, 7)

    var grid = NRResourceGrid(4, 24)
    var short_data: List[Complex64] = [Complex64(1.0, 0.0)]
    var dmrs = _complex_ramp(4, 10)
    with assert_raises():
        nr_map_pucch_format2(
            grid, 0, 0, 1, 1, Span(short_data), Span(dmrs)
        )

    var format34_data = _complex_ramp(24, 20)
    var format34_dmrs = _complex_ramp(24, 30)
    with assert_raises():
        nr_map_pucch_format3_4_non_interlaced(
            grid,
            0,
            0,
            1,
            4,
            Span(format34_data),
            Span(format34_dmrs),
            intra_slot_hopping=True,
        )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
