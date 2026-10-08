"""Independent conformance tests for TS 38.212 NR LDPC.

The table checksums were generated independently from py3gpp's TS-derived
``bg1.csv``/``bg2.csv`` at commit 17b432b30c965ffd350257ee4b1fc4de642c8e37.
They were also exhaustively cross-checked for all 51 Zc values against the
expanded matrices in manuts/NR-LDPC-BG commit
910ecbc9e81d43e318079aec535dc9a166a76b2a. The encoder and rate-matching
vectors use a standalone Python transcription of 38.212, not this Mojo code.
No oracle package is required at build or run time.
"""

from std.collections import Span
from std.testing import assert_equal, assert_true, assert_raises, TestSuite
from std.utils.numerics import inf, nan
from wireless_dsp.wireless.nr.ldpc_tables import (
    nr_base_graph_dimensions,
    nr_base_graph_edge_count,
    nr_base_graph_edges,
    nr_base_graph_shift,
    nr_lifting_set_index,
)
from wireless_dsp.wireless.nr.ldpc_profile import (
    nr_ldpc_filler_mask,
    nr_ldpc_profile,
    nr_select_base_graph,
    nr_standard_qc_graph,
)
from wireless_dsp.wireless.nr.ldpc_codec import (
    nr_ldpc_code_block_output_bits,
    nr_ldpc_decode,
    nr_ldpc_encode,
    nr_ldpc_encode_full,
    nr_ldpc_k0,
    nr_ldpc_rate_match,
    nr_ldpc_rate_recover,
    nr_ldpc_syndrome_ok,
)
from wireless_dsp.wireless.nr.ldpc_segmentation import (
    nr_ldpc_crc24b,
    nr_ldpc_crc24b_append,
    nr_ldpc_crc24b_check,
    nr_ldpc_decode_code_blocks,
    nr_ldpc_desegment,
    nr_ldpc_encode_code_blocks,
    nr_ldpc_rate_match_code_blocks,
    nr_ldpc_rate_recover_code_blocks,
    nr_ldpc_segment,
)


def _checksum(bits: Span[UInt8, ...]) -> UInt64:
    var result = UInt64(14695981039346656037)
    for i in range(len(bits)):
        result ^= UInt64(bits[i])
        result *= UInt64(1099511628211)
    return result


def _table_checksum(base_graph: Int, lifting_size: Int) raises -> UInt64:
    var edges = nr_base_graph_edges(base_graph, lifting_size)
    var result = UInt64(14695981039346656037)
    for i in range(len(edges.edge_rows)):
        result ^= UInt64(edges.edge_rows[i])
        result *= UInt64(1099511628211)
        result ^= UInt64(edges.edge_columns[i])
        result *= UInt64(1099511628211)
        result ^= UInt64(edges.shifts[i])
        result *= UInt64(1099511628211)
    return result


def _pattern(length: Int) -> List[UInt8]:
    var result = List[UInt8](capacity=length)
    for i in range(length):
        result.append(UInt8((i * 17 + i // 3 + 5) & 1))
    return result^


def test_complete_tables_cover_all_lifting_set_indices() raises:
    assert_equal(nr_base_graph_dimensions(1), (46, 68, 22))
    assert_equal(nr_base_graph_dimensions(2), (42, 52, 10))
    with assert_raises():
        _ = nr_base_graph_dimensions(3)
    assert_equal(nr_base_graph_edge_count(1), 316)
    assert_equal(nr_base_graph_edge_count(2), 197)
    var representatives: List[Int] = [2, 3, 5, 7, 9, 11, 13, 15]
    var bg1_oracles: List[UInt64] = [
        9422424342087039793,
        13944193197698853721,
        16111288545502745156,
        13198485151171982871,
        15062023413315424733,
        13946369163981319944,
        15146973147476958964,
        6044804278669975287,
    ]
    var bg2_oracles: List[UInt64] = [
        15144367579665561501,
        18273144216278833446,
        8934194194490434154,
        4266948967995692088,
        10395075937483027615,
        8279289531021789761,
        16184172826615631572,
        15968097006006254613,
    ]
    for i in range(8):
        assert_equal(_table_checksum(1, representatives[i]), bg1_oracles[i])
        assert_equal(_table_checksum(2, representatives[i]), bg2_oracles[i])

    # Direct values from 38.212 Tables 5.3.2-2/3, including absent edges.
    assert_equal(nr_base_graph_shift(1, 0, 0, 0), 250)
    assert_equal(nr_base_graph_shift(1, 7, 0, 0), 135)
    assert_equal(nr_base_graph_shift(1, 6, 0, 6), 0)
    assert_equal(nr_base_graph_shift(1, 3, 45, 67), 0)
    assert_equal(nr_base_graph_shift(1, 0, 0, 4), -1)
    assert_equal(nr_base_graph_shift(2, 0, 0, 0), 9)
    assert_equal(nr_base_graph_shift(2, 7, 0, 0), 145)
    assert_equal(nr_base_graph_shift(2, 3, 0, 10), 1)
    assert_equal(nr_base_graph_shift(2, 0, 41, 51), 0)


def test_all_51_standard_lifting_sizes_are_accepted() raises:
    var lifting_sizes: List[Int] = [
        2, 4, 8, 16, 32, 64, 128, 256,
        3, 6, 12, 24, 48, 96, 192, 384,
        5, 10, 20, 40, 80, 160, 320,
        7, 14, 28, 56, 112, 224,
        9, 18, 36, 72, 144, 288,
        11, 22, 44, 88, 176, 352,
        13, 26, 52, 104, 208,
        15, 30, 60, 120, 240,
    ]
    var expected_set = 0
    var next_set_offset: List[Int] = [8, 16, 23, 29, 35, 41, 46, 51]
    for i in range(len(lifting_sizes)):
        while i >= next_set_offset[expected_set]:
            expected_set += 1
        var z = lifting_sizes[i]
        assert_equal(nr_lifting_set_index(z), expected_set)
        var bg1 = nr_base_graph_edges(1, z)
        var bg2 = nr_base_graph_edges(2, z)
        for shift in bg1.shifts:
            assert_true(shift >= 0 and shift < z)
        for shift in bg2.shifts:
            assert_true(shift >= 0 and shift < z)
    assert_equal(nr_lifting_set_index(1), -1)
    assert_equal(nr_lifting_set_index(17), -1)
    assert_equal(nr_lifting_set_index(384), 1)
    assert_equal(nr_lifting_set_index(385), -1)


def test_qc_expansion_has_standard_dimensions_and_edge_counts() raises:
    for z in [2, 3, 5, 7, 9, 11, 13, 15]:
        var bg1 = nr_standard_qc_graph(1, z)
        assert_equal(len(bg1.row_offsets), 46 * z + 1)
        assert_equal(len(bg1.columns), 316 * z)
        assert_equal(bg1.variable_count, 68 * z)
        var bg2 = nr_standard_qc_graph(2, z)
        assert_equal(len(bg2.row_offsets), 42 * z + 1)
        assert_equal(len(bg2.columns), 197 * z)
        assert_equal(bg2.variable_count, 52 * z)


def test_profile_reports_segmentation_filler_and_encoded_sizes() raises:
    var short = nr_ldpc_profile(100, 0.5)
    assert_equal(short.base_graph, 2)
    assert_equal(short.transport_crc_bits, 16)
    assert_equal(short.transport_block_bits, 116)
    assert_equal(short.code_blocks, 1)
    assert_equal(short.code_block_data_bits, 116)
    assert_equal(short.lifting_size, 20)
    assert_equal(short.lifting_set_index, 2)
    assert_equal(short.code_block_bits, 120)
    assert_equal(short.encoder_input_bits, 200)
    assert_equal(short.filler_bits, 84)
    assert_equal(short.encoded_bits, 1000)
    var mask = nr_ldpc_filler_mask(short)
    assert_equal(len(mask), 1000)
    var marked = 0
    for value in mask:
        marked += Int(value)
    assert_equal(marked, 84)

    var segmented = nr_ldpc_profile(10000, 0.5)
    assert_equal(segmented.base_graph, 1)
    assert_equal(segmented.transport_crc_bits, 24)
    assert_equal(segmented.code_blocks, 2)
    assert_equal(segmented.code_block_crc_bits, 24)
    with assert_raises():
        _ = nr_ldpc_profile(100, nan[DType.float64]())
    with assert_raises():
        _ = nr_ldpc_profile(100, inf[DType.float64]())
    assert_equal(segmented.transport_block_bits, 10024)
    assert_equal(segmented.segmented_bits, 10072)
    assert_equal(segmented.code_block_payload_bits, 5012)
    assert_equal(segmented.code_block_data_bits, 5036)
    assert_equal(segmented.lifting_size, 240)
    assert_equal(segmented.encoder_input_bits, 5280)
    assert_equal(segmented.filler_bits, 244)
    assert_equal(segmented.encoded_bits, 15840)


def test_bg1_encoder_matches_independent_open_source_oracles() raises:
    var representatives: List[Int] = [2, 3, 5, 7, 9, 11, 13, 15]
    var expected: List[UInt64] = [
        429411304498307556,
        5995354127245937835,
        7242133883280872656,
        14186539637359277998,
        2075705631821138905,
        1606126366167531326,
        1561935233689808996,
        12249605732217075203,
    ]
    for i in range(8):
        var z = representatives[i]
        var information = _pattern(22 * z)
        var full = nr_ldpc_encode_full(Span(information), 1, z)
        assert_true(nr_ldpc_syndrome_ok(Span(full), 1, z))
        var encoded = nr_ldpc_encode(Span(information), 1, z)
        assert_equal(len(encoded), 66 * z)
        assert_equal(_checksum(Span(encoded)), expected[i])


def test_bg2_encoder_matches_oracles_for_all_lifting_sets() raises:
    # Representatives are chosen above 64 so BG2 uses Kb=10 in independent
    # nrLDPCEncode implementations, avoiding any ambiguity from filler bits.
    var representatives: List[Int] = [128, 96, 80, 112, 72, 88, 104, 120]
    var expected: List[UInt64] = [
        16886743801847443625,
        8731135290196813349,
        18349510671217757407,
        975901184386657937,
        9149489696999989733,
        13156438371535953977,
        4292071148298006841,
        13533809164802555109,
    ]
    for i in range(8):
        var z = representatives[i]
        var information = _pattern(10 * z)
        var full = nr_ldpc_encode_full(Span(information), 2, z)
        assert_true(nr_ldpc_syndrome_ok(Span(full), 2, z))
        var encoded = nr_ldpc_encode(Span(information), 2, z)
        assert_equal(len(encoded), 50 * z)
        assert_equal(_checksum(Span(encoded)), expected[i])


def test_rate_matching_matches_38212_oracles_for_all_rvs() raises:
    var information = _pattern(44)
    var encoded = nr_ldpc_encode(Span(information), 1, 2)
    var nulls = List[UInt8](length=132, fill=UInt8(0))
    var expected: List[List[UInt8]] = [
        [0,1,1,1,1,0,1,0,1,1,0,0,0,1,0,1,1,0,1,0,1,1,1,1,0,1,0,1,1,0,1,0,1,1,1,1,0,1,0,0,1,0,0,1,1,1,0,0,0,1,0,0,1,0,0,1,1,1,1,1,0,1,0,1,1,0,0,1,1,1,0,1,0,1,0,1,1,0,1,1],
        [1,1,1,0,1,0,1,0,0,0,1,1,1,0,1,1,1,0,1,0,0,1,1,1,1,1,1,0,1,0,1,1,0,0,0,0,0,1,1,1,1,0,1,1,1,1,0,0,0,1,0,1,1,0,0,0,1,1,0,1,0,0,1,0,0,1,1,0,0,0,1,0,0,0,0,0,0,1,1,0],
        [1,0,1,1,0,0,0,1,1,0,1,0,0,1,0,0,1,1,0,0,0,1,0,1,0,0,0,0,1,1,0,1,1,0,0,1,1,0,0,0,1,1,1,1,1,1,0,1,1,0,1,0,1,1,0,1,1,0,0,1,1,1,1,0,0,0,1,1,1,1,0,1,1,1,0,0,0,0,1,1],
        [0,0,1,1,0,1,0,1,0,1,1,0,0,0,1,0,1,1,0,1,0,1,1,1,1,0,1,0,0,1,0,1,0,1,1,1,1,0,1,0,1,1,0,0,0,1,1,0,0,0,1,0,1,1,0,0,1,1,1,1,1,0,1,0,0,1,0,0,0,1,1,0,0,0,1,0,1,1,0,1],
    ]
    for rv in range(4):
        assert_equal(nr_ldpc_k0(1, 2, rv), [0, 34, 66, 112][rv])
        var matched = nr_ldpc_rate_match(
            Span(encoded), Span(nulls), 1, 2, rv, 80, 4
        )
        assert_equal(matched, expected[rv])


def test_rate_recovery_inverts_interleaving_and_rv_selection() raises:
    var information = _pattern(44)
    var encoded = nr_ldpc_encode(Span(information), 1, 2)
    var nulls = List[UInt8](length=132, fill=UInt8(0))
    for rv in range(4):
        var matched = nr_ldpc_rate_match(
            Span(encoded), Span(nulls), 1, 2, rv, 132, 4
        )
        var llrs = List[Float64](capacity=len(matched))
        for value in matched:
            llrs.append(12.0 if value == 0 else -12.0)
        var recovered = nr_ldpc_rate_recover(
            Span(llrs), Span(nulls), 1, 2, rv, 4
        )
        for i in range(len(encoded)):
            assert_equal(recovered[i], 12.0 if encoded[i] == 0 else -12.0)


def test_nr_decoder_recovers_punctured_systematic_nodes() raises:
    var information = _pattern(44)
    var encoded = nr_ldpc_encode(Span(information), 1, 2)
    var nulls = List[UInt8](length=len(encoded), fill=UInt8(0))
    var llrs = List[Float64](capacity=len(encoded))
    for value in encoded:
        llrs.append(20.0 if value == 0 else -20.0)
    var decoded = nr_ldpc_decode(
        Span(llrs), Span(nulls), 1, 2,
        max_iterations=20, normalization=0.8,
    )
    assert_true(decoded.converged)
    assert_equal(decoded.bits, information)


def test_transport_block_bit_distribution() raises:
    assert_equal(nr_ldpc_code_block_output_bits(1008, 4, 2, 3, 0), 336)
    assert_equal(nr_ldpc_code_block_output_bits(1016, 4, 2, 3, 0), 336)
    assert_equal(nr_ldpc_code_block_output_bits(1016, 4, 2, 3, 1), 336)
    assert_equal(nr_ldpc_code_block_output_bits(1016, 4, 2, 3, 2), 344)


def test_table_config_integer_properties_and_independent_formulas() raises:
    # Direct clause predicate over both sides of every BG-selection boundary.
    for payload_bits in [0, 1, 192, 292, 293, 3824, 3825, 10000]:
        for target_code_rate in [0.2, 0.25, 0.5, 0.67, 0.6700001, 1.0]:
            var expected_base_graph = (
                2
                if payload_bits <= 292
                or (payload_bits <= 3824 and target_code_rate <= 0.67)
                or target_code_rate <= 0.25
                else 1
            )
            assert_equal(
                nr_select_base_graph(payload_bits, target_code_rate),
                expected_base_graph,
            )

    # Filler masks have one contiguous NULL interval after the punctured
    # prefix.  Check independently counted positions across both base graphs
    # and single/multiple-code-block profiles.
    for payload_bits in [0, 100, 560, 1000, 4000, 10000]:
        var profile = nr_ldpc_profile(payload_bits, 0.5)
        var mask = nr_ldpc_filler_mask(profile)
        assert_equal(len(mask), profile.encoded_bits)
        var marked = 0
        var punctured = 2 * profile.lifting_size
        for index in range(len(mask)):
            var full_index = index + punctured
            var expected = UInt8(1) if (
                full_index >= profile.code_block_data_bits
                and full_index < profile.encoder_input_bits
            ) else UInt8(0)
            assert_equal(mask[index], expected)
            marked += Int(mask[index])
        assert_equal(marked, profile.filler_bits)

    # Independent quotient/remainder distribution.  In addition to each
    # block value, the sum must recover E exactly for every tested geometry.
    for modulation_order in [1, 2, 4, 6, 8, 10]:
        for layers in [1, 2, 4]:
            var quantum = modulation_order * layers
            for code_blocks in [1, 2, 3, 7]:
                for units in [0, 1, 2, 7, 19, 127]:
                    var total_output_bits = quantum * units
                    var low = units // code_blocks
                    var high_blocks = units % code_blocks
                    var total = 0
                    for block in range(code_blocks):
                        var expected_units = low + (
                            1
                            if block >= code_blocks - high_blocks
                            else 0
                        )
                        var actual = nr_ldpc_code_block_output_bits(
                            total_output_bits,
                            modulation_order,
                            layers,
                            code_blocks,
                            block,
                        )
                        assert_equal(actual, quantum * expected_units)
                        total += actual
                    assert_equal(total, total_output_bits)


def test_crc24b_and_multi_block_segmentation_oracles() raises:
    # CRC-24/LTE-B catalogue check value, with octets serialized MSB first.
    var bytes: List[Int] = [49, 50, 51, 52, 53, 54, 55, 56, 57]
    var check_bits = List[UInt8](capacity=72)
    for byte in bytes:
        for bit in range(8):
            check_bits.append(UInt8((byte >> (7 - bit)) & 1))
    assert_equal(nr_ldpc_crc24b(Span(check_bits)), UInt64(0x23EF52))
    var attached = nr_ldpc_crc24b_append(Span(check_bits))
    assert_equal(len(attached), len(check_bits) + 24)
    assert_true(nr_ldpc_crc24b_check(Span(attached)))
    attached[0] ^= UInt8(1)
    assert_true(not nr_ldpc_crc24b_check(Span(attached)))

    var profile = nr_ldpc_profile(10000, 0.5)
    var transport_block = _pattern(profile.transport_block_bits)
    var segments = nr_ldpc_segment(Span(transport_block), profile)
    assert_equal(segments.code_blocks, 2)
    assert_equal(segments.block_bits, 5280)
    assert_equal(len(segments.bits), 10560)
    assert_equal(_checksum(Span(segments.bits)), UInt64(1714664525875926919))
    assert_equal(_checksum(Span(segments.null_mask)), UInt64(7927059806311370573))
    var null_count = 0
    for value in segments.null_mask:
        null_count += Int(value)
    assert_equal(null_count, 488)
    var reassembled = nr_ldpc_desegment(Span(segments.bits), profile)
    assert_true(reassembled.code_block_crc_ok)
    assert_equal(reassembled.bits, transport_block)

    var corrupted = segments.bits.copy()
    corrupted[profile.code_block_payload_bits] ^= UInt8(1)
    var rejected = nr_ldpc_desegment(Span(corrupted), profile)
    assert_true(not rejected.code_block_crc_ok)


def test_single_block_wrappers_run_complete_ldpc_chain() raises:
    var profile = nr_ldpc_profile(100, 0.5)
    var transport_block = _pattern(profile.transport_block_bits)
    var segments = nr_ldpc_segment(Span(transport_block), profile)
    var encoded = nr_ldpc_encode_code_blocks(segments, profile)
    assert_equal(len(encoded.bits), 1000)
    var encoded_nulls = 0
    for value in encoded.null_mask:
        encoded_nulls += Int(value)
    assert_equal(encoded_nulls, 84)

    var matched = nr_ldpc_rate_match_code_blocks(
        encoded, profile, 2, 1200, 4, 1
    )
    assert_equal(len(matched), 1200)
    var llrs = List[Float64](capacity=len(matched))
    for value in matched:
        llrs.append(20.0 if value == 0 else -20.0)
    var recovered = nr_ldpc_rate_recover_code_blocks(
        Span(llrs), Span(encoded.null_mask), profile, 2, 4, 1
    )
    var decoded = nr_ldpc_decode_code_blocks(
        Span(recovered), Span(encoded.null_mask), profile,
        max_iterations=20, normalization=0.8,
    )
    assert_true(decoded.converged)
    var reassembled = nr_ldpc_desegment(Span(decoded.bits), profile)
    assert_true(reassembled.code_block_crc_ok)
    assert_equal(reassembled.bits, transport_block)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
