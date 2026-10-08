"""Strict independent evidence for NR downlink public primitives.

The helpers in this file deliberately restate scalar recurrences, CRC shift
registers, resource-index traversals, and QC syndrome traversal.  They do not
use an encoder/decoder round trip as the expected result.
"""

from std.collections import Span
from std.math import atan2, cos, sin, sqrt
from std.testing import assert_equal, assert_true, assert_raises, TestSuite
from std.utils.numerics import inf, nan
from wireless_dsp.core import Complex64
from wireless_dsp.wireless.nr import (
    NRResourceGrid,
    nr_gold_bits,
    nr_pss,
    nr_sss,
    nr_pbch_dmrs_c_init,
    nr_pbch_dmrs,
    nr_search_pss,
    nr_detect_sss,
    nr_normal_cp_samples,
    nr_pdsch_dmrs_c_init,
    nr_map_pdsch_comb2,
    nr_extract_pdsch_comb2,
    nr_extract_dmrs_comb2,
    nr_ls_channel_estimate_comb2,
    nr_equalize_pdsch_comb2,
    nr_map_ssb_synchronization,
    nr_pdsch_scramble,
    nr_pdsch_dmrs,
    nr_pdsch_descramble_llrs,
    nr_pdsch_encode_transport_block,
    nr_pdsch_decode_grid_comb2,
    nr_rate_recover_llrs,
    nr_transport_crc_width,
    nr_transport_crc,
    nr_transport_crc_append,
    nr_transport_crc_check,
    nr_pbch_payload_interleave,
    nr_pbch_payload_deinterleave,
    nr_pbch_crc24c,
    nr_pbch_crc24c_append,
    nr_pbch_crc24c_check,
    nr_pbch_physical_scramble,
    nr_pbch_physical_descramble_llrs,
    nr_map_pdsch_ptrs,
    nr_extract_pdsch_ptrs,
    nr_ptrs_estimate_common_phase,
    nr_ptrs_correct_common_phase,
    nr_select_base_graph,
    nr_ldpc_profile,
    nr_ldpc_filler_mask,
    nr_qc_expand_edges,
    nr_base_graph_edges,
    nr_standard_qc_graph,
    nr_ldpc_encode_full,
    nr_ldpc_encode,
    nr_ldpc_syndrome_ok,
    nr_ldpc_rate_recover,
    nr_ldpc_decode,
    nr_ldpc_crc24b,
    nr_ldpc_crc24b_append,
    nr_ldpc_crc24b_check,
    nr_ldpc_segment,
    nr_ldpc_desegment,
    nr_ldpc_encode_code_blocks,
    nr_ldpc_rate_match_code_blocks,
    nr_ldpc_rate_recover_code_blocks,
    nr_ldpc_decode_code_blocks,
)


def _assert_complex_close(
    actual: Complex64, expected: Complex64, tolerance: Float64,
) raises:
    assert_true(abs(actual.re - expected.re) <= tolerance)
    assert_true(abs(actual.im - expected.im) <= tolerance)


def _reference_gold(c_init: UInt32, length: Int) -> List[UInt8]:
    # TS 38.211 5.2.1 as two rolling 31-bit registers.  Production keeps
    # indexed arrays, so this also exercises a different state layout.
    var x1 = UInt32(1)
    var x2 = c_init & UInt32(0x7FFFFFFF)
    var result = List[UInt8](capacity=length)
    for n in range(1600 + length):
        var output = UInt8((x1 ^ x2) & UInt32(1))
        var feedback1 = ((x1 >> 3) ^ x1) & UInt32(1)
        var feedback2 = (
            (x2 >> 3) ^ (x2 >> 2) ^ (x2 >> 1) ^ x2
        ) & UInt32(1)
        x1 = (x1 >> 1) | (feedback1 << 30)
        x2 = (x2 >> 1) | (feedback2 << 30)
        if n >= 1600:
            result.append(output)
    return result^


def _reference_pss(n_id_2: Int) -> List[Float64]:
    var state = List[UInt8](length=127, fill=UInt8(0))
    var seed: List[UInt8] = [0, 1, 1, 0, 1, 1, 1]
    for index in range(7):
        state[index] = seed[index]
    for index in range(120):
        state[index + 7] = state[index + 4] ^ state[index]
    var result = List[Float64](capacity=127)
    for index in range(127):
        result.append(
            1.0 - 2.0 * Float64(state[(index + 43 * n_id_2) % 127])
        )
    return result^


def _reference_sss(n_id_1: Int, n_id_2: Int) -> List[Float64]:
    var x0 = List[UInt8](length=127, fill=UInt8(0))
    var x1 = List[UInt8](length=127, fill=UInt8(0))
    x0[0] = 1
    x1[0] = 1
    for index in range(120):
        x0[index + 7] = x0[index + 4] ^ x0[index]
        x1[index + 7] = x1[index + 1] ^ x1[index]
    var shift0 = 15 * (n_id_1 // 112) + 5 * n_id_2
    var shift1 = n_id_1 % 112
    var result = List[Float64](capacity=127)
    for index in range(127):
        result.append(
            (1.0 - 2.0 * Float64(x0[(index + shift0) % 127]))
            * (1.0 - 2.0 * Float64(x1[(index + shift1) % 127]))
        )
    return result^


def _reference_crc(
    bits: Span[UInt8, ...], width: Int, polynomial: UInt64,
) raises -> UInt64:
    # Independent MSB-first shift-register traversal.
    var mask = (UInt64(1) << UInt64(width)) - UInt64(1)
    var top = UInt64(1) << UInt64(width - 1)
    var state = UInt64(0)
    for index in range(len(bits)):
        var bit = bits[index]
        if bit > 1:
            raise Error("reference CRC accepts binary inputs only")
        var feedback = UInt64(1) if ((state & top) != 0) != (bit != 0) else UInt64(0)
        state = (state << UInt64(1)) & mask
        if feedback != 0:
            state ^= polynomial & mask
    return state


def _reference_crc_append(
    bits: Span[UInt8, ...], width: Int, polynomial: UInt64,
) raises -> List[UInt8]:
    var remainder = _reference_crc(bits, width, polynomial)
    var result = List[UInt8](capacity=len(bits) + width)
    for index in range(len(bits)):
        result.append(bits[index])
    for index in range(width):
        result.append(
            UInt8((remainder >> UInt64(width - index - 1)) & UInt64(1))
        )
    return result^


def _seeded_bits(length: Int, seed: UInt64) -> List[UInt8]:
    var state = seed
    var result = List[UInt8](capacity=length)
    for _ in range(length):
        state = (
            state * UInt64(6364136223846793005)
            + UInt64(1442695040888963407)
        )
        result.append(UInt8((state >> UInt64(63)) & UInt64(1)))
    return result^


def _reference_pdsch_rate_recover(
    received: Span[Float64, ...], codeword_length: Int, start: Int,
    filler: Span[UInt8, ...],
) -> List[Float64]:
    var result = List[Float64](length=codeword_length, fill=0.0)
    var cursor = start % codeword_length
    if cursor < 0:
        cursor += codeword_length
    for index in range(len(received)):
        var value = received[index]
        while filler[cursor] != 0:
            cursor = (cursor + 1) % codeword_length
        result[cursor] += value
        cursor = (cursor + 1) % codeword_length
    return result^


def _reference_ldpc_rate_recover_bg1_z2(
    received: Span[Float64, ...], null_mask: Span[UInt8, ...],
    redundancy_version: Int, modulation_order: Int, n_cb: Int,
    filler_llr: Float64,
) -> List[Float64]:
    comptime encoded_bits = 132
    var coefficient: List[Int] = [0, 17, 33, 56]
    var k0 = (
        coefficient[redundancy_version] * n_cb // encoded_bits
    ) * 2
    var symbol_count = len(received) // modulation_order
    var deinterleaved = List[Float64](length=len(received), fill=0.0)
    for bit_plane in range(modulation_order):
        for symbol in range(symbol_count):
            deinterleaved[bit_plane * symbol_count + symbol] = received[
                symbol * modulation_order + bit_plane
            ]
    var result = List[Float64](length=encoded_bits, fill=0.0)
    var cursor = k0
    for value in deinterleaved:
        while null_mask[cursor] != 0:
            cursor = (cursor + 1) % n_cb
        result[cursor] += value
        cursor = (cursor + 1) % n_cb
    for index in range(n_cb):
        if null_mask[index] != 0:
            result[index] = filler_llr
    return result^


def _reference_ldpc_rate_recover(
    received: Span[Float64, ...], null_mask: Span[UInt8, ...],
    base_graph: Int, lifting_size: Int, redundancy_version: Int,
    modulation_order: Int, filler_llr: Float64,
) -> List[Float64]:
    var encoded_bits = len(null_mask)
    var coefficient_bg1: List[Int] = [0, 17, 33, 56]
    var coefficient_bg2: List[Int] = [0, 13, 25, 43]
    var coefficient = (
        coefficient_bg1[redundancy_version]
        if base_graph == 1 else coefficient_bg2[redundancy_version]
    )
    var k0 = (coefficient * encoded_bits // encoded_bits) * lifting_size
    var symbol_count = len(received) // modulation_order
    var deinterleaved = List[Float64](length=len(received), fill=0.0)
    for bit_plane in range(modulation_order):
        for symbol in range(symbol_count):
            deinterleaved[bit_plane * symbol_count + symbol] = received[
                symbol * modulation_order + bit_plane
            ]
    var result = List[Float64](length=encoded_bits, fill=0.0)
    var cursor = k0
    for value in deinterleaved:
        while null_mask[cursor] != 0:
            cursor = (cursor + 1) % encoded_bits
        result[cursor] += value
        cursor = (cursor + 1) % encoded_bits
    for index in range(encoded_bits):
        if null_mask[index] != 0:
            result[index] = filler_llr
    return result^


def _reference_ldpc_rate_match(
    encoded: Span[UInt8, ...], null_mask: Span[UInt8, ...],
    base_graph: Int, lifting_size: Int, redundancy_version: Int,
    output_bits: Int, modulation_order: Int,
) -> List[UInt8]:
    var coefficient_bg1: List[Int] = [0, 17, 33, 56]
    var coefficient_bg2: List[Int] = [0, 13, 25, 43]
    var coefficient = (
        coefficient_bg1[redundancy_version]
        if base_graph == 1 else coefficient_bg2[redundancy_version]
    )
    var cursor = coefficient * lifting_size
    var selected = List[UInt8](capacity=output_bits)
    while len(selected) < output_bits:
        if null_mask[cursor] == 0:
            selected.append(encoded[cursor])
        cursor = (cursor + 1) % len(encoded)
    var symbol_count = output_bits // modulation_order
    var result = List[UInt8](capacity=output_bits)
    for symbol in range(symbol_count):
        for bit_plane in range(modulation_order):
            result.append(selected[bit_plane * symbol_count + symbol])
    return result^


def _reference_syndrome_ok(
    bits: Span[UInt8, ...], base_graph: Int, lifting_size: Int,
) raises -> Bool:
    # Table retrieval and matrix application are separate evidence: the table
    # rows have independent static-vector coverage, while traversal here is a
    # direct H*c^T calculation rather than the production syndrome routine.
    var edges = nr_base_graph_edges(base_graph, lifting_size)
    var syndrome = List[UInt8](
        length=edges.base_rows * lifting_size, fill=UInt8(0)
    )
    for edge in range(len(edges.edge_rows)):
        for lifted_row in range(lifting_size):
            syndrome[edges.edge_rows[edge] * lifting_size + lifted_row] ^= bits[
                edges.edge_columns[edge] * lifting_size
                + (lifted_row + edges.shifts[edge]) % lifting_size
            ]
    for value in syndrome:
        if value != 0:
            return False
    return True


def test_sequences_and_cell_search_against_manual_38211_recurrences() raises:
    for n_id_2 in range(3):
        assert_equal(nr_pss(n_id_2), _reference_pss(n_id_2))
    var identities: List[Int] = [0, 1, 111, 112, 217, 335]
    for n_id_1 in identities:
        for n_id_2 in range(3):
            assert_equal(
                nr_sss(n_id_1, n_id_2),
                _reference_sss(n_id_1, n_id_2),
            )

    # Exact known placement under a nontrivial complex gain.  The expected
    # metric and phase are calculated without calling either detector.
    var pss = _reference_pss(2)
    var samples = List[Complex64](length=136, fill=Complex64(0.0, 0.0))
    for index in range(127):
        samples[7 + index] = Complex64(0.6 * pss[index], -0.8 * pss[index])
    var detection = nr_search_pss(Span(samples))
    assert_equal(detection.offset, 7)
    assert_equal(detection.n_id_2, 2)
    assert_true(abs(detection.metric - 1.0) <= 1.0e-12)
    assert_true(abs(detection.phase_re - 0.6) <= 1.0e-12)
    assert_true(abs(detection.phase_im + 0.8) <= 1.0e-12)

    var sss = _reference_sss(217, 1)
    var received_sss = List[Complex64](capacity=127)
    for value in sss:
        received_sss.append(Complex64(-0.5 * value, 0.5 * value))
    var cell = nr_detect_sss(Span(received_sss), 1)
    assert_equal(cell.n_id_1, 217)
    assert_equal(cell.n_id_2, 1)
    assert_equal(cell.physical_cell_id, 652)
    # The detector reports a normalized correlation metric, independent of
    # the common complex gain magnitude.
    assert_true(abs(cell.metric - 1.0) <= 1.0e-12)

    with assert_raises():
        _ = nr_pss(-1)
    with assert_raises():
        _ = nr_pss(3)
    with assert_raises():
        _ = nr_sss(336, 0)
    with assert_raises():
        _ = nr_search_pss(Span(samples)[:126])
    with assert_raises():
        _ = nr_detect_sss(Span(received_sss)[:126], 1)
    with assert_raises():
        _ = nr_detect_sss(Span(received_sss), 3)


def test_pdsch_gold_dmrs_scrambling_crc_and_rate_recovery_oracles() raises:
    var payload = _seeded_bits(73, UInt64(0x5EED20260821))
    comptime rnti = 0x1234
    comptime codeword = 1
    comptime n_id = 777
    var c_init = UInt32((rnti << 15) + (codeword << 14) + n_id)
    var gold = _reference_gold(c_init, len(payload))
    var expected_scrambled = List[UInt8](capacity=len(payload))
    for index in range(len(payload)):
        expected_scrambled.append(payload[index] ^ gold[index])
    assert_equal(
        nr_pdsch_scramble(Span(payload), rnti, codeword, n_id),
        expected_scrambled,
    )

    var llrs = List[Float64](capacity=len(payload))
    for index in range(len(payload)):
        llrs.append(Float64(index + 1) * 0.125)
    var descrambled = nr_pdsch_descramble_llrs(
        Span(llrs), rnti, codeword, n_id
    )
    for index in range(len(llrs)):
        assert_equal(
            descrambled[index],
            llrs[index] if gold[index] == 0 else -llrs[index],
        )

    var dmrs = nr_pdsch_dmrs(c_init, 36)
    var dmrs_gold = _reference_gold(c_init, 72)
    var scale = 1.0 / sqrt(2.0)
    for index in range(36):
        _assert_complex_close(
            dmrs[index],
            Complex64(
                scale * (1.0 - 2.0 * Float64(dmrs_gold[2 * index])),
                scale * (1.0 - 2.0 * Float64(dmrs_gold[2 * index + 1])),
            ),
            1.0e-15,
        )

    var filler: List[UInt8] = [0, 1, 0, 0, 1, 0, 0]
    var received: List[Float64] = [
        0.5, -1.0, 2.5, 3.0, -4.0, 0.25, 8.0, -2.0, 1.5,
    ]
    assert_equal(
        nr_rate_recover_llrs(Span(received), 7, -3, Span(filler)),
        _reference_pdsch_rate_recover(Span(received), 7, -3, Span(filler)),
    )

    # Exercise both constant regions, not only the discontinuity.  The
    # expected value is the clause threshold itself, independent of the CRC
    # implementation that consumes it.
    for payload_bits in [0, 1, 73, 3823, 3824, 3825, 4096, 10000]:
        assert_equal(
            nr_transport_crc_width(payload_bits),
            16 if payload_bits <= 3824 else 24,
        )
    var short_crc = _reference_crc(Span(payload), 16, UInt64(0x1021))
    assert_equal(nr_transport_crc(Span(payload)), short_crc)
    var short_attached = _reference_crc_append(
        Span(payload), 16, UInt64(0x1021)
    )
    assert_equal(nr_transport_crc_append(Span(payload)), short_attached)
    assert_true(nr_transport_crc_check(Span(short_attached), len(payload)))
    short_attached[5] ^= UInt8(1)
    assert_true(not nr_transport_crc_check(Span(short_attached), len(payload)))

    var long_payload = _seeded_bits(3825, UInt64(0x24A3825))
    assert_equal(
        nr_transport_crc(Span(long_payload)),
        _reference_crc(Span(long_payload), 24, UInt64(0x864CFB)),
    )
    assert_equal(
        nr_transport_crc_append(Span(long_payload)),
        _reference_crc_append(Span(long_payload), 24, UInt64(0x864CFB)),
    )

    var bad_bits: List[UInt8] = [0, 2]
    with assert_raises():
        _ = nr_pdsch_scramble(Span(bad_bits), rnti, codeword, n_id)
    with assert_raises():
        _ = nr_pdsch_scramble(Span(payload), -1, codeword, n_id)
    with assert_raises():
        _ = nr_pdsch_dmrs(c_init, -1)
    with assert_raises():
        _ = nr_transport_crc_width(-1)
    var all_filler = List[UInt8](length=7, fill=UInt8(1))
    with assert_raises():
        _ = nr_rate_recover_llrs(
            Span(received)[:1], 7, 0, Span(all_filler)
        )


def test_grid_comb2_and_ssb_mapping_against_manual_index_formulas() raises:
    # Independent integer transcription of the normal-CP rule over every
    # symbol in representative slots, FFT sizes, and numerologies.
    for fft_size in [128, 2048, 4096]:
        for mu in [0, 1, 2, 4]:
            for slot_in_subframe in [0, (1 << mu) - 1]:
                for symbol in range(14):
                    var base = 144 * fft_size // 2048
                    var extension = 16 * (1 << mu) * fft_size // 2048
                    var absolute_symbol = 14 * slot_in_subframe + symbol
                    var expected_cp = (
                        base + extension
                        if absolute_symbol % (7 * (1 << mu)) == 0
                        else base
                    )
                    assert_equal(
                        nr_normal_cp_samples(
                            fft_size,
                            symbol,
                            mu,
                            slot_in_subframe=slot_in_subframe,
                        ),
                        expected_cp,
                    )
    assert_equal(nr_normal_cp_samples(2048, 0, 0), 160)
    assert_equal(nr_normal_cp_samples(2048, 7, 0), 160)
    assert_equal(nr_normal_cp_samples(2048, 6, 0), 144)
    assert_equal(nr_normal_cp_samples(4096, 0, 2), 416)
    var expected_c_init = UInt32(
        ((1 << 17) * (14 * 3 + 2 + 1) * (2 * 42 + 1) + 84) % (1 << 31)
    )
    assert_equal(nr_pdsch_dmrs_c_init(3, 2, 42, 0), expected_c_init)
    for slot in [0, 1, 3, 100000]:
        for symbol in [0, 6, 13]:
            for n_id in [0, 42, 65535]:
                for n_scid in [0, 1]:
                    var modulus = UInt64(1) << UInt64(31)
                    var time_term = (
                        UInt64(14) * (UInt64(slot) % modulus)
                        + UInt64(symbol + 1)
                    ) % modulus
                    var expected = (
                        (((UInt64(1) << UInt64(17)) * time_term)
                            % modulus)
                        * UInt64(2 * n_id + 1)
                        + UInt64(2 * n_id + n_scid)
                    ) % modulus
                    assert_equal(
                        nr_pdsch_dmrs_c_init(
                            slot, symbol, n_id, n_scid
                        ),
                        UInt32(expected),
                    )

    var grid = NRResourceGrid(4, 32)
    var data: List[Complex64] = [
        Complex64(1.0, -1.0), Complex64(2.0, -2.0),
        Complex64(3.0, -3.0), Complex64(4.0, -4.0),
    ]
    var pilots: List[Complex64] = [
        Complex64(10.0, 1.0), Complex64(20.0, 2.0),
        Complex64(30.0, 3.0),
    ]
    nr_map_pdsch_comb2(grid, 1, 5, 7, 1, Span(data), Span(pilots))
    var data_index = 0
    var pilot_index = 0
    for local in range(7):
        if local % 2 == 1:
            assert_equal(grid[1, 5 + local], pilots[pilot_index])
            pilot_index += 1
        else:
            assert_equal(grid[1, 5 + local], data[data_index])
            data_index += 1
    assert_equal(nr_extract_pdsch_comb2(grid, 1, 5, 7, 1), data)
    assert_equal(nr_extract_dmrs_comb2(grid, 1, 5, 7, 1), pilots)

    # Constant-channel pilots give an independent exact interpolation oracle.
    var known: List[Complex64] = [
        Complex64(1.0, 0.0), Complex64(0.0, 1.0), Complex64(-1.0, 0.0)
    ]
    var channel_value = Complex64(0.75, -0.25)
    var observed = List[Complex64](capacity=3)
    for reference in known:
        observed.append(reference * channel_value)
    var channel = nr_ls_channel_estimate_comb2(
        Span(observed), Span(known), 6, 1
    )
    for value in channel:
        _assert_complex_close(value, channel_value, 2.0e-15)
    var symbols: List[Complex64] = [
        Complex64(0.5, 0.25), Complex64(-1.0, 0.5),
        Complex64(0.25, -0.75),
    ]
    var channel_samples = List[Complex64](capacity=3)
    for symbol in symbols:
        channel_samples.append(symbol * channel_value)
    var equalized = nr_equalize_pdsch_comb2(
        Span(channel_samples), Span(channel), 1
    )
    for index in range(3):
        _assert_complex_close(equalized[index], symbols[index], 2.0e-15)

    var pss = _reference_pss(0)
    var sss = _reference_sss(335, 0)
    var ssb_grid = NRResourceGrid(4, 248)
    nr_map_ssb_synchronization(ssb_grid, 8, Span(pss), Span(sss))
    for index in range(127):
        assert_equal(ssb_grid[0, 64 + index], Complex64(pss[index], 0.0))
        assert_equal(ssb_grid[2, 64 + index], Complex64(sss[index], 0.0))
    assert_equal(ssb_grid[1, 64], Complex64(0.0, 0.0))

    with assert_raises():
        _ = nr_normal_cp_samples(127, 0, 0)
    with assert_raises():
        _ = nr_pdsch_dmrs_c_init(-1, 0, 0, 0)
    with assert_raises():
        nr_map_pdsch_comb2(grid, 1, 5, 7, 2, Span(data), Span(pilots))
    with assert_raises():
        nr_map_pdsch_comb2(grid, 1, 30, 7, 1, Span(data), Span(pilots))
    with assert_raises():
        _ = nr_ls_channel_estimate_comb2(
            Span(observed)[:2], Span(known), 6, 1
        )
    with assert_raises():
        _ = nr_equalize_pdsch_comb2(Span(channel_samples)[:2], Span(channel), 1)
    with assert_raises():
        nr_map_ssb_synchronization(
            ssb_grid, 9, Span(pss), Span(sss)
        )


def test_pbch_dmrs_physical_scrambling_and_crc_manual_oracles() raises:
    var configurations: List[Int] = [4, 8, 64]
    var indices: List[Int] = [3, 7, 63]
    for case_index in range(3):
        var l_max = configurations[case_index]
        var ssb_index = indices[case_index]
        var half_frame = case_index & 1
        var i_ssb = (
            (ssb_index & 3) + 4 * half_frame
            if l_max == 4 else ssb_index & 7
        )
        var expected = UInt32(
            (1 << 11) * (i_ssb + 1) * (1007 // 4 + 1)
            + (1 << 6) * (i_ssb + 1) + 1007 % 4
        )
        assert_equal(
            nr_pbch_dmrs_c_init(1007, ssb_index, half_frame, l_max),
            expected,
        )
        var dmrs = nr_pbch_dmrs(
            1007, ssb_index, half_frame, l_max, length=17
        )
        var gold = _reference_gold(expected, 34)
        var scale = 1.0 / sqrt(2.0)
        for index in range(17):
            _assert_complex_close(
                dmrs[index],
                Complex64(
                    scale * (1.0 - 2.0 * Float64(gold[2 * index])),
                    scale * (1.0 - 2.0 * Float64(gold[2 * index + 1])),
                ),
                1.0e-15,
            )

    var bits = _seeded_bits(97, UInt64(0xB0C12026))
    var nu = 19 & 7
    var gold = _reference_gold(UInt32(321), (nu + 1) * len(bits))
    var expected_scrambled = List[UInt8](capacity=len(bits))
    for index in range(len(bits)):
        expected_scrambled.append(bits[index] ^ gold[nu * len(bits) + index])
    assert_equal(
        nr_pbch_physical_scramble(Span(bits), 321, 19, 20),
        expected_scrambled,
    )
    var llrs = List[Float64](capacity=len(bits))
    for index in range(len(bits)):
        llrs.append(Float64(index + 1) / 16.0)
    var actual_llrs = nr_pbch_physical_descramble_llrs(
        Span(llrs), 321, 19, 20
    )
    for index in range(len(bits)):
        assert_equal(
            actual_llrs[index],
            llrs[index] if gold[nu * len(bits) + index] == 0 else -llrs[index],
        )

    var crc = _reference_crc(Span(bits), 24, UInt64(0xB2B117))
    assert_equal(nr_pbch_crc24c(Span(bits)), crc)
    var attached = _reference_crc_append(
        Span(bits), 24, UInt64(0xB2B117)
    )
    assert_equal(nr_pbch_crc24c_append(Span(bits)), attached)
    assert_true(nr_pbch_crc24c_check(Span(attached)))
    attached[11] ^= UInt8(1)
    assert_true(not nr_pbch_crc24c_check(Span(attached)))

    var wrong_payload = List[UInt8](length=31, fill=UInt8(0))
    with assert_raises():
        _ = nr_pbch_payload_interleave(Span(wrong_payload))
    with assert_raises():
        _ = nr_pbch_payload_deinterleave(Span(wrong_payload))
    with assert_raises():
        _ = nr_pbch_dmrs_c_init(1008, 0, 0, 4)
    with assert_raises():
        _ = nr_pbch_dmrs_c_init(0, 4, 0, 4)
    var invalid_llrs: List[Float64] = [nan[DType.float64](), 1.0]
    with assert_raises():
        _ = nr_pbch_physical_descramble_llrs(
            Span(invalid_llrs), 321, 0, 4
        )
    invalid_llrs[0] = inf[DType.float64]()
    with assert_raises():
        _ = nr_pbch_physical_descramble_llrs(
            Span(invalid_llrs), 321, 0, 4
        )


def test_ptrs_cartesian_mapping_phase_formula_and_edges() raises:
    var grid = NRResourceGrid(8, 32)
    var times: List[Int] = [0, 2, 5]
    var frequencies: List[Int] = [1, 7, 13]
    var references: List[Complex64] = [
        Complex64(1.0, -0.5),
        Complex64(-0.25, 0.75),
        Complex64(0.5, 0.125),
    ]
    nr_map_pdsch_ptrs(
        grid, 1, 3, Span(times), Span(frequencies), Span(references),
        beta=0.625,
    )
    for time in times:
        for index in range(len(frequencies)):
            _assert_complex_close(
                grid[1 + time, 3 + frequencies[index]],
                Complex64(
                    0.625 * references[index].re,
                    0.625 * references[index].im,
                ),
                0.0,
            )
    var extracted = nr_extract_pdsch_ptrs(
        grid, 1, 3, Span(times), Span(frequencies)
    )
    assert_equal(len(extracted), 9)
    for time_index in range(3):
        for frequency_index in range(3):
            assert_equal(
                extracted[3 * time_index + frequency_index],
                grid[1 + times[time_index], 3 + frequencies[frequency_index]],
            )

    var known: List[Complex64] = [
        Complex64(1.0, 0.0), Complex64(0.0, 2.0), Complex64(-0.5, 0.5)
    ]
    var phase_values: List[Float64] = [0.3, -0.7]
    var symbol_ids: List[Int] = [4, 9]
    var received = List[Complex64](capacity=6)
    var expected_magnitude = 0.0
    for reference in known:
        expected_magnitude += reference.magnitude_squared()
    for phase in phase_values:
        var rotation = Complex64(cos(phase), sin(phase))
        for reference in known:
            received.append(reference * rotation)
    var estimate = nr_ptrs_estimate_common_phase(
        Span(received), Span(known), Span(symbol_ids)
    )
    assert_equal(estimate.symbols, symbol_ids)
    for index in range(2):
        assert_true(
            abs(estimate.phase_radians[index] - phase_values[index]) <= 2.0e-15
        )
        assert_true(
            abs(estimate.coherent_magnitudes[index] - expected_magnitude)
            <= 2.0e-15
        )

    var arbitrary: List[Complex64] = [
        Complex64(0.25, -0.75), Complex64(-1.0, 0.125)
    ]
    var corrected = nr_ptrs_correct_common_phase(Span(arbitrary), 0.3)
    var correction = Complex64(cos(0.3), -sin(0.3))
    for index in range(2):
        _assert_complex_close(
            corrected[index], arbitrary[index] * correction, 2.0e-15
        )

    with assert_raises():
        nr_map_pdsch_ptrs(
            grid, 1, 3, Span(times), Span(frequencies), Span(references)[:2]
        )
    with assert_raises():
        nr_map_pdsch_ptrs(
            grid, 1, 3, Span(times), Span(frequencies), Span(references),
            beta=-0.1,
        )
    var bad_times: List[Int] = [7]
    with assert_raises():
        nr_map_pdsch_ptrs(
            grid, 1, 3, Span(bad_times), Span(frequencies), Span(references)
        )
    var bad_frequencies: List[Int] = [30]
    with assert_raises():
        _ = nr_extract_pdsch_ptrs(
            grid, 1, 3, Span(times), Span(bad_frequencies)
        )
    with assert_raises():
        _ = nr_ptrs_estimate_common_phase(
            Span(received)[:5], Span(known), Span(symbol_ids)
        )


def test_ldpc_profile_qc_syndrome_and_soft_recovery_independent_traversals() raises:
    assert_equal(nr_select_base_graph(292, 1.0), 2)
    assert_equal(nr_select_base_graph(293, 0.67), 2)
    assert_equal(nr_select_base_graph(293, 0.6700001), 1)
    assert_equal(nr_select_base_graph(3824, 0.25), 2)
    assert_equal(nr_select_base_graph(3825, 0.2500001), 1)
    with assert_raises():
        _ = nr_select_base_graph(-1, 0.5)
    with assert_raises():
        _ = nr_select_base_graph(100, 0.0)
    with assert_raises():
        _ = nr_select_base_graph(100, nan[DType.float64]())

    var profile = nr_ldpc_profile(100, 0.5)
    var filler = nr_ldpc_filler_mask(profile)
    assert_equal(len(filler), 1000)
    for index in range(1000):
        var expected = UInt8(1) if index >= 76 and index < 160 else UInt8(0)
        assert_equal(filler[index], expected)

    var edge_rows: List[Int] = [0, 0, 1]
    var edge_columns: List[Int] = [0, 2, 1]
    var shifts: List[Int] = [0, 1, 2]
    var graph = nr_qc_expand_edges(
        2, 3, Span(edge_rows), Span(edge_columns), Span(shifts), 3
    )
    assert_equal(graph.variable_count, 9)
    assert_equal(graph.row_offsets, [0, 2, 4, 6, 7, 8, 9])
    assert_equal(graph.columns, [0, 7, 1, 8, 2, 6, 5, 3, 4])
    with assert_raises():
        _ = nr_qc_expand_edges(
            2, 3, Span(edge_rows), Span(edge_columns)[:2], Span(shifts), 3
        )

    var standard = nr_standard_qc_graph(1, 2)
    var standard_edges = nr_base_graph_edges(1, 2)
    assert_equal(len(standard.row_offsets), 93)
    assert_equal(len(standard.columns), 632)
    assert_equal(standard.variable_count, 136)
    # Independently verify every CSR row against the table coordinates.
    for row in range(92):
        var expected_degree = 0
        for edge in range(len(standard_edges.edge_rows)):
            if standard_edges.edge_rows[edge] == row // 2:
                var expected_column = (
                    standard_edges.edge_columns[edge] * 2
                    + (row % 2 + standard_edges.shifts[edge]) % 2
                )
                assert_equal(
                    standard.columns[standard.row_offsets[row] + expected_degree],
                    expected_column,
                )
                expected_degree += 1
        assert_equal(
            standard.row_offsets[row + 1] - standard.row_offsets[row],
            expected_degree,
        )

    var information = _seeded_bits(44, UInt64(0x1D9C2026))
    var full = nr_ldpc_encode_full(Span(information), 1, 2)
    assert_true(_reference_syndrome_ok(Span(full), 1, 2))
    assert_true(nr_ldpc_syndrome_ok(Span(full), 1, 2))
    full[17] ^= UInt8(1)
    assert_true(not _reference_syndrome_ok(Span(full), 1, 2))
    assert_true(not nr_ldpc_syndrome_ok(Span(full), 1, 2))

    var null_mask = List[UInt8](length=132, fill=UInt8(0))
    null_mask[51] = 1
    null_mask[52] = 1
    null_mask[77] = 1
    var soft = List[Float64](capacity=40)
    for index in range(40):
        soft.append(Float64(index - 19) * 0.375)
    var recovered = nr_ldpc_rate_recover(
        Span(soft), Span(null_mask), 1, 2, 2, 4, 100, 37.0
    )
    var expected_recovered = _reference_ldpc_rate_recover_bg1_z2(
        Span(soft), Span(null_mask), 2, 4, 100, 37.0
    )
    assert_equal(recovered, expected_recovered)

    # The all-zero word is a specification-level codeword independent of any
    # encoder.  Decoder output and full-word syndrome are checked separately.
    var zero_llrs = List[Float64](length=132, fill=12.0)
    var zero_nulls = List[UInt8](length=132, fill=UInt8(0))
    var decoded = nr_ldpc_decode(
        Span(zero_llrs), Span(zero_nulls), 1, 2,
        max_iterations=8, normalization=0.8,
    )
    assert_true(decoded.converged)
    assert_equal(decoded.bits, List[UInt8](length=44, fill=UInt8(0)))
    assert_true(_reference_syndrome_ok(Span(decoded.full_bits), 1, 2))

    var all_nulls = List[UInt8](length=132, fill=UInt8(1))
    with assert_raises():
        _ = nr_ldpc_rate_recover(
            Span(soft)[:4], Span(all_nulls), 1, 2, 0, 4
        )
    with assert_raises():
        _ = nr_ldpc_decode(
            Span(zero_llrs)[:131], Span(zero_nulls), 1, 2
        )


def test_ldpc_crc24b_and_segmentation_manual_layout_oracles() raises:
    var bits = _seeded_bits(113, UInt64(0xC24B2026))
    assert_equal(
        nr_ldpc_crc24b(Span(bits)),
        _reference_crc(Span(bits), 24, UInt64(0x800063)),
    )
    var expected_attached = _reference_crc_append(
        Span(bits), 24, UInt64(0x800063)
    )
    assert_equal(nr_ldpc_crc24b_append(Span(bits)), expected_attached)
    assert_true(nr_ldpc_crc24b_check(Span(expected_attached)))
    expected_attached[37] ^= UInt8(1)
    assert_true(not nr_ldpc_crc24b_check(Span(expected_attached)))

    # This low-rate profile forces two BG2 code blocks while remaining small
    # enough for exhaustive bit-by-bit layout validation.
    var profile = nr_ldpc_profile(4000, 0.2)
    assert_equal(profile.code_blocks, 2)
    assert_equal(profile.code_block_crc_bits, 24)
    var transport = _seeded_bits(
        profile.transport_block_bits, UInt64(0x5E6A3E17)
    )
    var segments = nr_ldpc_segment(Span(transport), profile)
    assert_equal(
        len(segments.bits), profile.code_blocks * profile.encoder_input_bits
    )
    var source = 0
    for block in range(profile.code_blocks):
        var payload = List[UInt8](
            length=profile.code_block_payload_bits, fill=UInt8(0)
        )
        var copied = min(
            profile.code_block_payload_bits, len(transport) - source
        )
        for index in range(copied):
            payload[index] = transport[source + index]
        source += copied
        var expected_block = _reference_crc_append(
            Span(payload), 24, UInt64(0x800063)
        )
        var destination = block * profile.encoder_input_bits
        for index in range(len(expected_block)):
            assert_equal(segments.bits[destination + index], expected_block[index])
            assert_equal(segments.null_mask[destination + index], UInt8(0))
        for index in range(len(expected_block), profile.encoder_input_bits):
            assert_equal(segments.bits[destination + index], UInt8(0))
            assert_equal(segments.null_mask[destination + index], UInt8(1))
    assert_equal(source, len(transport))
    var desegmented = nr_ldpc_desegment(Span(segments.bits), profile)
    assert_true(desegmented.code_block_crc_ok)
    assert_equal(desegmented.bits, transport)

    # Validate each multi-block wrapper against an explicit outer traversal.
    # The underlying one-block encoder already has independent table/vector
    # evidence; this oracle independently owns slicing, null propagation,
    # E_r distribution, concatenation, and soft deinterleaving.
    var encoded = nr_ldpc_encode_code_blocks(segments, profile)
    var expected_encoded = List[UInt8](capacity=len(encoded.bits))
    var expected_nulls = List[UInt8](length=len(encoded.bits), fill=UInt8(0))
    var punctured = 2 * profile.lifting_size
    for block in range(profile.code_blocks):
        var block_information = List[UInt8](capacity=profile.encoder_input_bits)
        var segment_offset = block * profile.encoder_input_bits
        for index in range(profile.encoder_input_bits):
            block_information.append(segments.bits[segment_offset + index])
        var block_encoded = nr_ldpc_encode(
            Span(block_information), profile.base_graph, profile.lifting_size
        )
        for value in block_encoded:
            expected_encoded.append(value)
        var mask_offset = block * profile.encoded_bits
        for index in range(profile.encoded_bits):
            var full_index = index + punctured
            if full_index < profile.encoder_input_bits:
                expected_nulls[mask_offset + index] = segments.null_mask[
                    segment_offset + full_index
                ]
    assert_equal(encoded.bits, expected_encoded)
    assert_equal(encoded.null_mask, expected_nulls)

    comptime total_output_bits = 812
    comptime modulation_order = 4
    var matched = nr_ldpc_rate_match_code_blocks(
        encoded, profile, 2, total_output_bits, modulation_order, 1
    )
    var expected_matched = List[UInt8](capacity=total_output_bits)
    var expected_block_outputs: List[Int] = [404, 408]
    for block in range(profile.code_blocks):
        var encoded_slice = List[UInt8](capacity=profile.encoded_bits)
        var null_slice = List[UInt8](capacity=profile.encoded_bits)
        var block_offset = block * profile.encoded_bits
        for index in range(profile.encoded_bits):
            encoded_slice.append(encoded.bits[block_offset + index])
            null_slice.append(encoded.null_mask[block_offset + index])
        var expected_block = _reference_ldpc_rate_match(
            Span(encoded_slice),
            Span(null_slice),
            profile.base_graph,
            profile.lifting_size,
            2,
            expected_block_outputs[block],
            modulation_order,
        )
        for value in expected_block:
            expected_matched.append(value)
    assert_equal(matched, expected_matched)

    var soft = List[Float64](capacity=total_output_bits)
    for index in range(total_output_bits):
        soft.append(Float64((index * 37 + 11) % 101 - 50) * 0.125)
    var recovered = nr_ldpc_rate_recover_code_blocks(
        Span(soft), Span(encoded.null_mask), profile, 2,
        modulation_order, 1, filler_llr=37.0,
    )
    var expected_recovered = List[Float64](capacity=len(recovered))
    var received_offset = 0
    for block in range(profile.code_blocks):
        var block_soft = List[Float64](capacity=expected_block_outputs[block])
        var block_nulls = List[UInt8](capacity=profile.encoded_bits)
        for index in range(expected_block_outputs[block]):
            block_soft.append(soft[received_offset + index])
        received_offset += expected_block_outputs[block]
        var block_offset = block * profile.encoded_bits
        for index in range(profile.encoded_bits):
            block_nulls.append(encoded.null_mask[block_offset + index])
        var expected_block = _reference_ldpc_rate_recover(
            Span(block_soft),
            Span(block_nulls),
            profile.base_graph,
            profile.lifting_size,
            2,
            modulation_order,
            37.0,
        )
        for value in expected_block:
            expected_recovered.append(value)
    assert_equal(recovered, expected_recovered)

    # An all-zero LDPC word is known analytically, so this decoder-wrapper
    # check is not an encode/decode round trip.
    var decode_profile = nr_ldpc_profile(100, 0.5)
    var zero_llrs = List[Float64](
        length=decode_profile.encoded_bits, fill=12.0
    )
    var zero_mask = List[UInt8](
        length=decode_profile.encoded_bits, fill=UInt8(0)
    )
    var decoded = nr_ldpc_decode_code_blocks(
        Span(zero_llrs), Span(zero_mask), decode_profile,
        max_iterations=8, normalization=0.8,
    )
    assert_true(decoded.converged)
    assert_equal(decoded.code_blocks, 1)
    assert_equal(decoded.block_bits, decode_profile.encoder_input_bits)
    assert_equal(
        decoded.bits,
        List[UInt8](
            length=decode_profile.encoder_input_bits, fill=UInt8(0)
        ),
    )

    segments.bits[profile.code_block_payload_bits] ^= UInt8(1)
    var corrupted = nr_ldpc_desegment(Span(segments.bits), profile)
    assert_true(not corrupted.code_block_crc_ok)

    var wrong = transport.copy()
    _ = wrong.pop()
    with assert_raises():
        _ = nr_ldpc_segment(Span(wrong), profile)


def test_pdsch_chain_independent_intermediate_checkpoint_oracles() raises:
    comptime payload_bits = 100
    comptime output_bits = 480
    comptime allocation_size = 480
    comptime rnti = 0x3456
    comptime n_id = 71
    comptime noise_variance = 0.01
    var payload = _seeded_bits(payload_bits, UInt64(0xD15C2026))
    var transmit = nr_pdsch_encode_transport_block(
        Span(payload), 0.5, 2, 0, output_bits, rnti, 0, n_id
    )

    # The transport CRC, scrambling, and QPSK stages each have a standalone
    # oracle.  No receive-chain output is recycled as an expectation.
    var expected_transport = _reference_crc_append(
        Span(payload), 16, UInt64(0x1021)
    )
    assert_equal(transmit.transport_block, expected_transport)
    var scramble_init = UInt32((rnti << 15) + n_id)
    var scramble = _reference_gold(scramble_init, output_bits)
    for index in range(output_bits):
        assert_equal(
            transmit.scrambled_bits[index],
            transmit.rate_matched_bits[index] ^ scramble[index],
        )
    var qpsk_scale = 1.0 / sqrt(2.0)
    for index in range(output_bits // 2):
        _assert_complex_close(
            transmit.symbols[index],
            Complex64(
                qpsk_scale
                * (1.0 - 2.0 * Float64(transmit.scrambled_bits[2 * index])),
                qpsk_scale
                * (1.0 - 2.0 * Float64(transmit.scrambled_bits[2 * index + 1])),
            ),
            1.0e-15,
        )

    # Build comb-2 REs directly by the specification's even/odd index rule,
    # avoiding the production grid mapper as an oracle for the decoder.
    var dmrs_init = UInt32(
        ((1 << 17) * (2 + 1) * (2 * n_id + 1) + 2 * n_id) % (1 << 31)
    )
    var dmrs_gold = _reference_gold(dmrs_init, allocation_size)
    var dmrs = List[Complex64](capacity=allocation_size // 2)
    for index in range(allocation_size // 2):
        dmrs.append(Complex64(
            qpsk_scale * (1.0 - 2.0 * Float64(dmrs_gold[2 * index])),
            qpsk_scale * (1.0 - 2.0 * Float64(dmrs_gold[2 * index + 1])),
        ))
    var flat_channel = Complex64(0.8, 0.3)
    var grid = NRResourceGrid(1, allocation_size)
    for local in range(allocation_size):
        if local % 2 == 0:
            grid[0, local] = dmrs[local // 2] * flat_channel
        else:
            grid[0, local] = transmit.symbols[local // 2] * flat_channel

    var decoded = nr_pdsch_decode_grid_comb2(
        grid,
        0,
        0,
        allocation_size,
        0,
        Span(dmrs),
        Span(transmit.encoded_null_mask),
        transmit.profile,
        payload_bits,
        2,
        0,
        rnti,
        0,
        n_id,
        noise_variance,
        testcase_id="nr-downlink-strict-checkpoints",
    )
    assert_true(decoded.ldpc_converged)
    assert_true(decoded.code_block_crc_ok)
    assert_true(decoded.transport_crc_ok)
    assert_equal(decoded.payload, payload)
    assert_equal(decoded.transport_block, expected_transport)
    assert_equal(len(decoded.checkpoint_metadata), 9)
    for index in range(len(decoded.checkpoint_metadata)):
        assert_equal(
            decoded.checkpoint_metadata[index].testcase_id,
            "nr-downlink-strict-checkpoints",
        )
        assert_equal(decoded.checkpoint_metadata[index].stride, "1")
        assert_equal(decoded.checkpoint_metadata[index].version, 1)

    var channel_power = flat_channel.magnitude_squared()
    for index in range(allocation_size // 2):
        _assert_complex_close(
            decoded.received_data[index],
            transmit.symbols[index] * flat_channel,
            1.0e-15,
        )
        _assert_complex_close(
            decoded.channel_estimate[2 * index], flat_channel, 2.0e-14
        )
        _assert_complex_close(
            decoded.equalized_symbols[index], transmit.symbols[index], 2.0e-14
        )
        var expected_i_llr = (
            2.0 * sqrt(2.0) * transmit.symbols[index].re
            * channel_power / noise_variance
        )
        var expected_q_llr = (
            2.0 * sqrt(2.0) * transmit.symbols[index].im
            * channel_power / noise_variance
        )
        assert_true(
            abs(decoded.demapper_llrs[2 * index] - expected_i_llr) <= 1.0e-10
        )
        assert_true(
            abs(decoded.demapper_llrs[2 * index + 1] - expected_q_llr)
            <= 1.0e-10
        )
    for index in range(output_bits):
        assert_equal(
            decoded.descrambled_llrs[index],
            decoded.demapper_llrs[index]
            if scramble[index] == 0 else -decoded.demapper_llrs[index],
        )
    var expected_recovered = _reference_ldpc_rate_recover(
        Span(decoded.descrambled_llrs),
        Span(transmit.encoded_null_mask),
        transmit.profile.base_graph,
        transmit.profile.lifting_size,
        0,
        2,
        50.0,
    )
    assert_equal(decoded.rate_recovered_llrs, expected_recovered)

    var invalid_payload = payload.copy()
    invalid_payload[0] = 2
    with assert_raises():
        _ = nr_pdsch_encode_transport_block(
            Span(invalid_payload), 0.5, 2, 0, output_bits, rnti, 0, n_id
        )
    with assert_raises():
        _ = nr_pdsch_encode_transport_block(
            Span(payload), 0.5, 2, 0, output_bits - 1, rnti, 0, n_id
        )
    with assert_raises():
        _ = nr_pdsch_decode_grid_comb2(
            grid, 0, 0, allocation_size, 0, Span(dmrs),
            Span(transmit.encoded_null_mask), transmit.profile,
            payload_bits, 2, 0, rnti, 0, n_id,
            nan[DType.float64](),
        )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
