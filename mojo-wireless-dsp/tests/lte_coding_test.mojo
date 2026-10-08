"""Independent CPU-only conformance tests for LTE TS 36.212 V18.1.0 coding.

Frozen authority: 3GPP TS 36.212 V18.1.0, clauses 5.1.1--5.1.4.1, official
artifact https://www.3gpp.org/ftp/Specs/archive/36_series/36.212/36212-i10.zip,
SHA-256 bf393426701e69a3b4545865c78d5a1762c6d1e7a5cd2252cc3bd22f87a5cfc6.
The table checksum and fixed encoder/rate-matching vectors are an independent
literal equation transcription checked into this module (generator/tool and
tool commit: not applicable).  CRC inputs use MSB-first octet order; turbo
streams use the clause-5.1.4.1 ``v0, v1[0], v2[0], ...`` circular packing;
named LCG seeds/configurations are fixed below; all discrete tolerances are
exact.  No external oracle package is used at run time.
"""

from std.collections import Span
from std.math import isfinite
from std.testing import assert_equal, assert_true, assert_raises, TestSuite
from std.utils.numerics import inf, nan
from wireless_dsp.wireless.lte.coding import (
    LTEQPPParameters,
    LTE_QPP_BLOCK_SIZE_COUNT,
    lte_crc8,
    lte_crc8_append,
    lte_crc8_check,
    lte_crc16,
    lte_crc16_append,
    lte_crc16_check,
    lte_crc24a,
    lte_crc24a_append,
    lte_crc24a_check,
    lte_crc24b,
    lte_crc24b_append,
    lte_crc24b_check,
    lte_code_block_segmentation_profile,
    lte_code_block_bit_range,
    lte_code_block_segment,
    lte_code_block_concatenate,
    lte_qpp_block_size,
    lte_qpp_deinterleave,
    lte_qpp_index,
    lte_qpp_interleave,
    lte_qpp_parameters,
    lte_tail_biting_convolutional_decode_hard,
    lte_tail_biting_convolutional_decode_soft,
    lte_tail_biting_convolutional_encode,
    lte_turbo_encode,
    lte_turbo_decode_max_log,
    lte_turbo_circular_buffer,
    lte_turbo_k0,
    lte_turbo_rate_match,
    lte_turbo_rate_recover,
    lte_turbo_subblock_interleave,
)


def _checksum(bits: Span[UInt8, ...]) -> UInt64:
    var result = UInt64(14695981039346656037)
    for index in range(len(bits)):
        result ^= UInt64(bits[index])
        result *= UInt64(1099511628211)
    return result


def _mix(checksum: UInt64, value: Int) -> UInt64:
    return (checksum ^ UInt64(value)) * UInt64(1099511628211)


def _pattern(length: Int, seed: UInt64 = UInt64(1)) -> List[UInt8]:
    var state = seed
    var result = List[UInt8](capacity=length)
    for _ in range(length):
        state = state * UInt64(6364136223846793005) + UInt64(1442695040888963407)
        result.append(UInt8((state >> UInt64(63)) & UInt64(1)))
    return result^


def _reference_turbo_null_mask(stream_bits: Int, filler_bits: Int) -> List[UInt8]:
    """Independent literal clause-5.1.4.1 interleaver/collection mask."""
    var permutation: List[Int] = [
        0, 16, 8, 24, 4, 20, 12, 28,
        2, 18, 10, 26, 6, 22, 14, 30,
        1, 17, 9, 25, 5, 21, 13, 29,
        3, 19, 11, 27, 7, 23, 15, 31,
    ]
    var rows = (stream_bits + 31) // 32
    var padded_bits = rows * 32
    var dummy_bits = padded_bits - stream_bits
    var padded0 = List[UInt8](length=padded_bits, fill=UInt8(0))
    var padded2 = List[UInt8](length=padded_bits, fill=UInt8(0))
    for index in range(dummy_bits):
        padded0[index] = UInt8(1)
        padded2[index] = UInt8(1)
    for index in range(filler_bits):
        padded0[dummy_bits + index] = UInt8(1)

    var stream0 = List[UInt8](capacity=padded_bits)
    for permuted_column in range(32):
        var source_column = permutation[permuted_column]
        for row in range(rows):
            stream0.append(padded0[row * 32 + source_column])
    var stream2 = List[UInt8](capacity=padded_bits)
    for output_index in range(padded_bits):
        var source = (
            permutation[output_index // rows]
            + 32 * (output_index % rows)
            + 1
        ) % padded_bits
        stream2.append(padded2[source])

    var result = List[UInt8](length=3 * padded_bits, fill=UInt8(0))
    for index in range(padded_bits):
        result[index] = stream0[index]
        result[padded_bits + 2 * index] = stream0[index]
        result[padded_bits + 2 * index + 1] = stream2[index]
    return result^


def _reference_turbo_select(
    bits: Span[UInt8, ...], null_mask: Span[UInt8, ...],
    stream_bits: Int, redundancy_version: Int, output_bits: Int,
) -> List[UInt8]:
    """Independent clause-5.1.4.1.2 circular selection equation."""
    var rows = (stream_bits + 31) // 32
    var groups = (len(bits) + 8 * rows - 1) // (8 * rows)
    var position = (
        rows * (2 * groups * redundancy_version + 2)
    ) % len(bits)
    var result = List[UInt8](capacity=output_bits)
    while len(result) < output_bits:
        if null_mask[position] == 0:
            result.append(bits[position])
        position = (position + 1) % len(bits)
    return result^


def _catalogue_bits() -> List[UInt8]:
    var result = List[UInt8](capacity=72)
    for byte in [49, 50, 51, 52, 53, 54, 55, 56, 57]:
        for bit in range(8):
            result.append(UInt8((byte >> (7 - bit)) & 1))
    return result^


def test_lte_crc_catalogue_vectors_and_attachment() raises:
    var bits = _catalogue_bits()
    assert_equal(lte_crc24a(Span(bits)), UInt64(0xCDE703))
    assert_equal(lte_crc24b(Span(bits)), UInt64(0x23EF52))
    assert_equal(lte_crc16(Span(bits)), UInt64(0x31C3))
    assert_equal(lte_crc8(Span(bits)), UInt64(0xEA))

    var a = lte_crc24a_append(Span(bits))
    var b = lte_crc24b_append(Span(bits))
    var c = lte_crc16_append(Span(bits))
    var d = lte_crc8_append(Span(bits))
    assert_equal(len(a), 96)
    assert_equal(len(b), 96)
    assert_equal(len(c), 88)
    assert_equal(len(d), 80)
    assert_true(lte_crc24a_check(Span(a)))
    assert_true(lte_crc24b_check(Span(b)))
    assert_true(lte_crc16_check(Span(c)))
    assert_true(lte_crc8_check(Span(d)))
    a[0] ^= UInt8(1)
    b[7] ^= UInt8(1)
    c[31] ^= UInt8(1)
    d[63] ^= UInt8(1)
    assert_true(not lte_crc24a_check(Span(a)))
    assert_true(not lte_crc24b_check(Span(b)))
    assert_true(not lte_crc16_check(Span(c)))
    assert_true(not lte_crc8_check(Span(d)))
    var invalid: List[UInt8] = [0, 1, 2]
    with assert_raises():
        _ = lte_crc8(Span(invalid))


def test_code_block_segmentation_profiles_cover_normative_boundaries() raises:
    var input_sizes: List[Int] = [1, 39, 40, 41, 6144, 6145, 12000, 20000]
    var expected_code_blocks: List[Int] = [1, 1, 1, 1, 1, 2, 2, 4]
    var expected_crc_bits: List[Int] = [0, 0, 0, 0, 0, 24, 24, 24]
    var expected_small_bits: List[Int] = [0, 0, 0, 0, 0, 3072, 6016, 4992]
    var expected_large_bits: List[Int] = [40, 40, 40, 48, 6144, 3136, 6080, 5056]
    var expected_small_blocks: List[Int] = [0, 0, 0, 0, 0, 1, 1, 2]
    var expected_large_blocks: List[Int] = [1, 1, 1, 1, 1, 1, 1, 2]
    var expected_filler_bits: List[Int] = [39, 1, 0, 7, 0, 15, 48, 0]
    for case_index in range(len(input_sizes)):
        var profile = lte_code_block_segmentation_profile(
            input_sizes[case_index]
        )
        assert_equal(profile.input_bits, input_sizes[case_index])
        assert_equal(profile.code_blocks, expected_code_blocks[case_index])
        assert_equal(profile.code_block_crc_bits, expected_crc_bits[case_index])
        assert_equal(profile.small_block_bits, expected_small_bits[case_index])
        assert_equal(profile.large_block_bits, expected_large_bits[case_index])
        assert_equal(profile.small_blocks, expected_small_blocks[case_index])
        assert_equal(profile.large_blocks, expected_large_blocks[case_index])
        assert_equal(profile.filler_bits, expected_filler_bits[case_index])
        assert_equal(
            profile.segmented_bits_with_crc,
            input_sizes[case_index]
            + expected_code_blocks[case_index] * expected_crc_bits[case_index],
        )
        assert_equal(
            profile.total_segmented_bits,
            expected_small_blocks[case_index] * expected_small_bits[case_index]
            + expected_large_blocks[case_index] * expected_large_bits[case_index],
        )
        for block in range(profile.code_blocks):
            var block_range = lte_code_block_bit_range(profile, block)
            assert_equal(
                block_range[1] - block_range[0],
                expected_small_bits[case_index]
                if block < expected_small_blocks[case_index]
                else expected_large_bits[case_index],
            )

    with assert_raises():
        _ = lte_code_block_segmentation_profile(0)
    with assert_raises():
        _ = lte_code_block_segmentation_profile(Int.MAX)
    var profile = lte_code_block_segmentation_profile(40)
    with assert_raises():
        _ = lte_code_block_bit_range(profile, -1)
    with assert_raises():
        _ = lte_code_block_bit_range(profile, 1)
    profile.large_block_bits = 48
    with assert_raises():
        _ = lte_code_block_bit_range(profile, 0)
    var empty_blocks = List[UInt8]()
    var empty_bypass = lte_code_block_segmentation_profile(40)
    empty_bypass.code_blocks = 0
    empty_bypass.input_bits = 0
    empty_bypass.total_segmented_bits = 0
    with assert_raises():
        _ = lte_code_block_concatenate(Span(empty_blocks), empty_bypass)


def test_code_block_segmentation_static_crc_filler_and_turbo_composition() raises:
    # B=6145 is the first input that crosses Z=6144.  The fixed expectations
    # below were independently transcribed from clause 5.1.2 and CRC24B.
    var transport_payload = _pattern(6121, UInt64(2026))
    var input = lte_crc24a_append(Span(transport_payload))
    assert_equal(len(input), 6145)
    assert_equal(lte_crc24a(Span(transport_payload)), UInt64(0xF50BC5))
    var segments = lte_code_block_segment(Span(input))
    assert_equal(segments.profile.code_blocks, 2)
    assert_equal(segments.profile.small_block_bits, 3072)
    assert_equal(segments.profile.large_block_bits, 3136)
    assert_equal(segments.profile.small_blocks, 1)
    assert_equal(segments.profile.large_blocks, 1)
    assert_equal(segments.profile.filler_bits, 15)
    assert_equal(len(segments.bits), 6208)
    assert_equal(len(segments.null_mask), 6208)
    assert_equal(_checksum(Span(segments.bits)), UInt64(8068789508021198815))
    for position in range(6208):
        assert_equal(
            segments.null_mask[position],
            UInt8(1 if position < 15 else 0),
        )
    assert_equal(lte_crc24b(Span(segments.bits)[0:3048]), UInt64(0xE8E500))
    assert_equal(
        lte_crc24b(Span(segments.bits)[3072:6184]), UInt64(0x46C4C8)
    )
    assert_true(lte_crc24b_check(Span(segments.bits)[0:3072]))
    assert_true(lte_crc24b_check(Span(segments.bits)[3072:6208]))

    # Filler value zero drives parity while the explicit count carries its
    # normative <NULL> identity through sub-block collection and selection.
    var first_encoded = lte_turbo_encode(
        Span(segments.bits)[0:3072], filler_bits=segments.profile.filler_bits
    )
    var second_encoded = lte_turbo_encode(Span(segments.bits)[3072:6208])
    assert_equal(len(first_encoded.systematic), 3076)
    assert_equal(len(second_encoded.systematic), 3140)
    assert_equal(first_encoded.filler_bits, 15)
    assert_equal(second_encoded.filler_bits, 0)

    var circular = lte_turbo_circular_buffer(
        Span(first_encoded.systematic),
        Span(first_encoded.parity1),
        Span(first_encoded.parity2),
        first_encoded.filler_bits,
    )
    var expected_null = _reference_turbo_null_mask(3076, 15)
    assert_equal(circular.null_mask, expected_null)
    var usable = 0
    for value in expected_null:
        if value == 0:
            usable += 1
    assert_equal(usable, 9198)
    var matched = lte_turbo_rate_match(
        Span(first_encoded.systematic),
        Span(first_encoded.parity1),
        Span(first_encoded.parity2),
        0,
        521,
        filler_bits=first_encoded.filler_bits,
    )
    var expected_matched = _reference_turbo_select(
        Span(circular.bits), Span(expected_null), 3076, 0, 521
    )
    assert_equal(matched, expected_matched)
    var full_matched = lte_turbo_rate_match(
        Span(first_encoded.systematic),
        Span(first_encoded.parity1),
        Span(first_encoded.parity2),
        0,
        usable,
        filler_bits=first_encoded.filler_bits,
    )
    var full_llrs = List[Float64](capacity=usable)
    for bit in full_matched:
        full_llrs.append(4.0 if bit == 0 else -4.0)
    var recovered = lte_turbo_rate_recover(
        Span(full_llrs), 3072, 0, filler_bits=first_encoded.filler_bits
    )
    for index in range(15):
        assert_equal(recovered.systematic[index], 0.0)
        assert_equal(recovered.parity1[index], 0.0)
        assert_true(abs(recovered.parity2[index]) == 4.0)
    for index in range(15, 3076):
        assert_true(abs(recovered.systematic[index]) == 4.0)
        assert_true(abs(recovered.parity1[index]) == 4.0)
        assert_true(abs(recovered.parity2[index]) == 4.0)

    var concatenated = lte_code_block_concatenate(
        Span(segments.bits), segments.profile
    )
    assert_true(concatenated.code_block_crc_ok)
    assert_equal(concatenated.bits, input)
    assert_true(lte_crc24a_check(Span(concatenated.bits)))


def test_code_block_segmentation_seeded_roundtrip_and_invalid_inputs() raises:
    var input_sizes: List[Int] = [1, 39, 40, 41, 512, 6144, 6145, 12000, 20000]
    for case_index in range(len(input_sizes)):
        var input = _pattern(
            input_sizes[case_index], UInt64(5000 + case_index)
        )
        var segments = lte_code_block_segment(Span(input))
        var result = lte_code_block_concatenate(
            Span(segments.bits), segments.profile
        )
        assert_true(result.code_block_crc_ok)
        assert_equal(result.bits, input)

    var invalid: List[UInt8] = [0, 1, 2]
    with assert_raises():
        _ = lte_code_block_segment(Span(invalid))
    var input = _pattern(6145, UInt64(77))
    var segments = lte_code_block_segment(Span(input))
    segments.bits[3100] ^= UInt8(1)
    var corrupted = lte_code_block_concatenate(
        Span(segments.bits), segments.profile
    )
    assert_true(not corrupted.code_block_crc_ok)
    segments.bits[0] = UInt8(1)
    with assert_raises():
        _ = lte_code_block_concatenate(
            Span(segments.bits), segments.profile
        )
    var short = List[UInt8](length=39, fill=UInt8(0))
    with assert_raises():
        _ = lte_code_block_concatenate(
            Span(short), lte_code_block_segmentation_profile(40)
        )


def test_complete_qpp_table_checksum_boundaries_and_formula() raises:
    assert_equal(LTE_QPP_BLOCK_SIZE_COUNT, 188)
    var checksum = UInt64(14695981039346656037)
    for table_index in range(LTE_QPP_BLOCK_SIZE_COUNT):
        var block_size = lte_qpp_block_size(table_index)
        var parameters = lte_qpp_parameters(block_size)
        checksum = _mix(checksum, table_index + 1)
        checksum = _mix(checksum, parameters.block_size)
        checksum = _mix(checksum, parameters.f1)
        checksum = _mix(checksum, parameters.f2)
        if table_index > 0:
            assert_true(block_size > lte_qpp_block_size(table_index - 1))
    assert_equal(checksum, UInt64(1451549886068724531))

    var first = lte_qpp_parameters(40)
    var middle = lte_qpp_parameters(1024)
    var last = lte_qpp_parameters(6144)
    assert_equal((first.f1, first.f2), (3, 10))
    assert_equal((middle.f1, middle.f2), (31, 64))
    assert_equal((last.f1, last.f2), (263, 480))
    var expected: List[Int] = [
        0, 13, 6, 19, 12, 25, 18, 31,
        24, 37, 30, 3, 36, 9, 2, 15,
    ]
    for index in range(len(expected)):
        # Independent hand formula: (3*i + 10*i*i) mod 40.
        assert_equal(lte_qpp_index(index, first), expected[index])

    # Binary basis vectors independently pin the full K=40 interleaver and
    # deinterleaver maps rather than treating their round trip as an oracle.
    for source_index in range(40):
        var basis = List[UInt8](length=40, fill=UInt8(0))
        basis[source_index] = 1
        var interleaved = lte_qpp_interleave(Span(basis))
        for output_index in range(40):
            var source = (3 * output_index + 10 * output_index * output_index) % 40
            assert_equal(
                interleaved[output_index],
                UInt8(1 if source == source_index else 0),
            )
        assert_equal(lte_qpp_deinterleave(Span(interleaved)), basis)

    with assert_raises():
        _ = lte_qpp_block_size(-1)
    with assert_raises():
        _ = lte_qpp_block_size(188)
    with assert_raises():
        _ = lte_qpp_parameters(39)
    with assert_raises():
        _ = lte_qpp_parameters(520)
    with assert_raises():
        _ = lte_qpp_parameters(Int.MAX)
    with assert_raises():
        _ = lte_qpp_index(40, first)
    with assert_raises():
        _ = lte_qpp_index(0, LTEQPPParameters(40, Int.MAX, 10))


def test_qpp_roundtrip_for_all_188_standardized_block_sizes() raises:
    for table_index in range(LTE_QPP_BLOCK_SIZE_COUNT):
        var block_size = lte_qpp_block_size(table_index)
        var bits = _pattern(block_size, UInt64(table_index + 11))
        var interleaved = lte_qpp_interleave(Span(bits))
        var recovered = lte_qpp_deinterleave(Span(interleaved))
        assert_equal(recovered, bits)
    var invalid = List[UInt8](length=40, fill=UInt8(0))
    invalid[17] = 2
    with assert_raises():
        _ = lte_qpp_interleave(Span(invalid))
    with assert_raises():
        _ = lte_qpp_deinterleave(Span(invalid))


def test_tail_biting_encoder_oracle_and_closed_viterbi_roundtrip() raises:
    var bits = List[UInt8](capacity=40)
    for index in range(40):
        bits.append(UInt8((index * 17 + index // 3 + 5) & 1))
    var encoded = lte_tail_biting_convolutional_encode(Span(bits))
    assert_equal(len(encoded), 120)
    assert_equal(_checksum(Span(encoded)), UInt64(15478090456998685766))
    var expected_prefix: List[UInt8] = [
        1, 1, 0, 1, 1, 1, 0, 0, 0, 0, 0, 1,
        1, 1, 0, 1, 0, 0, 1, 0, 1, 0, 0, 1,
    ]
    for index in range(len(expected_prefix)):
        assert_equal(encoded[index], expected_prefix[index])
    assert_equal(lte_tail_biting_convolutional_decode_hard(Span(encoded)), bits)

    var llrs = List[Float64](capacity=len(encoded))
    for index in range(len(encoded)):
        var magnitude = 2.0 + Float64((index * 7) % 11) * 0.125
        llrs.append(magnitude if encoded[index] == 0 else -magnitude)
    # One low-confidence wrong observation exercises the soft metric rather
    # than merely handing the decoder the encoder's hard decisions.
    llrs[17] = -0.05 * (1.0 if encoded[17] == 0 else -1.0)
    assert_equal(lte_tail_biting_convolutional_decode_soft(Span(llrs)), bits)


def test_tail_biting_seeded_properties_and_invalid_inputs() raises:
    for case_index in range(5):
        var bits = _pattern(
            24 + 8 * case_index, UInt64(101 + case_index)
        )
        var encoded = lte_tail_biting_convolutional_encode(Span(bits))
        assert_equal(
            lte_tail_biting_convolutional_decode_hard(Span(encoded)), bits
        )
    var short_bits: List[UInt8] = [0, 1, 0, 1, 0]
    var nonbinary: List[UInt8] = [0, 1, 0, 1, 0, 2]
    var incomplete: List[UInt8] = [0, 1, 1, 0]
    var nonfinite: List[Float64] = [
        1.0, -1.0, 1.0, 1.0, -1.0, inf[DType.float64](),
        1.0, -1.0, 1.0, 1.0, -1.0, 1.0,
        1.0, -1.0, 1.0, 1.0, -1.0, 1.0,
    ]
    with assert_raises():
        _ = lte_tail_biting_convolutional_encode(Span(short_bits))
    with assert_raises():
        _ = lte_tail_biting_convolutional_encode(Span(nonbinary))
    with assert_raises():
        _ = lte_tail_biting_convolutional_decode_hard(Span(incomplete))
    with assert_raises():
        _ = lte_tail_biting_convolutional_decode_soft(Span(nonfinite))


def test_turbo_encoder_constituents_and_trellis_tail_oracles() raises:
    var bits = List[UInt8](capacity=40)
    for index in range(40):
        bits.append(UInt8((index * 17 + index // 3 + 5) & 1))
    var encoded = lte_turbo_encode(Span(bits))
    assert_equal(len(encoded.systematic), 44)
    assert_equal(len(encoded.parity1), 44)
    assert_equal(len(encoded.parity2), 44)
    assert_equal(
        _checksum(Span(encoded.systematic)), UInt64(5296463416803032972)
    )
    assert_equal(
        _checksum(Span(encoded.parity1)), UInt64(17829648219632768573)
    )
    assert_equal(
        _checksum(Span(encoded.parity2)), UInt64(5181305904988146563)
    )
    var expected_systematic_tail: List[UInt8] = [0, 1, 1, 0]
    var expected_parity1_tail: List[UInt8] = [1, 0, 0, 1]
    var expected_parity2_tail: List[UInt8] = [1, 0, 1, 1]
    for index in range(4):
        assert_equal(
            encoded.systematic[40 + index], expected_systematic_tail[index]
        )
        assert_equal(encoded.parity1[40 + index], expected_parity1_tail[index])
        assert_equal(encoded.parity2[40 + index], expected_parity2_tail[index])


def test_turbo_subblock_permutations_have_explicit_null_masks() raises:
    var bits: List[UInt8] = [1, 0, 1, 1, 0, 0, 1]
    var normal = lte_turbo_subblock_interleave(Span(bits))
    var third = lte_turbo_subblock_interleave(Span(bits), third_stream=True)
    var leading_null = lte_turbo_subblock_interleave(
        Span(bits), leading_null_bits=3
    )
    assert_equal(normal.rows, 1)
    assert_equal(normal.input_bits, 7)
    assert_equal(len(normal.bits), 32)
    var normal_positions: List[Int] = [7, 11, 15, 19, 23, 27, 31]
    var third_positions: List[Int] = [3, 7, 11, 15, 19, 23, 27]
    var expected_bits: List[UInt8] = [1, 0, 0, 1, 0, 1, 1]
    for index in range(32):
        var normal_payload = False
        var third_payload = False
        for payload_index in range(7):
            if index == normal_positions[payload_index]:
                normal_payload = True
                assert_equal(normal.bits[index], expected_bits[payload_index])
            if index == third_positions[payload_index]:
                third_payload = True
                assert_equal(third.bits[index], bits[payload_index])
        assert_equal(normal.null_mask[index], UInt8(0 if normal_payload else 1))
        assert_equal(third.null_mask[index], UInt8(0 if third_payload else 1))
        var leading_filler = index == 11 or index == 19 or index == 27
        assert_equal(
            leading_null.null_mask[index],
            UInt8(1 if not normal_payload or leading_filler else 0),
        )


def test_turbo_rate_matching_matches_independent_rv_oracles() raises:
    var bits = List[UInt8](capacity=40)
    for index in range(40):
        bits.append(UInt8((index * 17 + index // 3 + 5) & 1))
    var expected_k0: List[Int] = [4, 52, 100, 148]
    var expected_hash: List[UInt64] = [
        15567448991406300722,
        9703038188680262260,
        10276970416920181681,
        4055513799806408594,
    ]
    for rv in range(4):
        var encoded = lte_turbo_encode(Span(bits))
        var circular = lte_turbo_circular_buffer(
            Span(encoded.systematic),
            Span(encoded.parity1),
            Span(encoded.parity2),
        )
        assert_equal(len(circular.bits), 192)
        assert_equal(len(circular.null_mask), 192)
        assert_equal(lte_turbo_k0(44, rv), expected_k0[rv])
        var matched = lte_turbo_rate_match(
            Span(encoded.systematic),
            Span(encoded.parity1),
            Span(encoded.parity2),
            rv,
            120,
        )
        assert_equal(_checksum(Span(matched)), expected_hash[rv])
        var full_matched = lte_turbo_rate_match(
            Span(encoded.systematic),
            Span(encoded.parity1),
            Span(encoded.parity2),
            rv,
            132,
        )
        var llrs = List[Float64](capacity=len(full_matched))
        for bit in full_matched:
            llrs.append(7.0 if bit == 0 else -7.0)
        var recovered = lte_turbo_rate_recover(Span(llrs), 40, rv)
        var hard0 = List[UInt8](capacity=44)
        var hard1 = List[UInt8](capacity=44)
        var hard2 = List[UInt8](capacity=44)
        for index in range(44):
            hard0.append(UInt8(0 if recovered.systematic[index] > 0.0 else 1))
            hard1.append(UInt8(0 if recovered.parity1[index] > 0.0 else 1))
            hard2.append(UInt8(0 if recovered.parity2[index] > 0.0 else 1))
        assert_equal(_checksum(Span(hard0)), UInt64(5296463416803032972))
        assert_equal(_checksum(Span(hard1)), UInt64(17829648219632768573))
        assert_equal(_checksum(Span(hard2)), UInt64(5181305904988146563))


def test_turbo_rate_recovery_inverts_every_rv_and_combines_repetition() raises:
    var block_sizes: List[Int] = [40, 48, 64]
    for case_index in range(3):
        var block_size = block_sizes[case_index]
        var bits = _pattern(block_size, UInt64(700 + case_index))
        for rv in range(4):
            var encoded = lte_turbo_encode(Span(bits))
            var mother_bits = 3 * (block_size + 4)
            var matched = lte_turbo_rate_match(
                Span(encoded.systematic),
                Span(encoded.parity1),
                Span(encoded.parity2),
                rv,
                mother_bits,
            )
            var llrs = List[Float64](capacity=len(matched))
            for index in range(len(matched)):
                llrs.append(9.0 if matched[index] == 0 else -9.0)
            var recovered = lte_turbo_rate_recover(
                Span(llrs), block_size, rv
            )
            for index in range(block_size + 4):
                assert_equal(
                    recovered.systematic[index],
                    9.0 if encoded.systematic[index] == 0 else -9.0,
                )
                assert_equal(
                    recovered.parity1[index],
                    9.0 if encoded.parity1[index] == 0 else -9.0,
                )
                assert_equal(
                    recovered.parity2[index],
                    9.0 if encoded.parity2[index] == 0 else -9.0,
                )

    var bits = _pattern(40, UInt64(91))
    var encoded = lte_turbo_encode(Span(bits))
    var repeated = lte_turbo_rate_match(
        Span(encoded.systematic),
        Span(encoded.parity1),
        Span(encoded.parity2),
        2,
        264,
    )
    var repeated_llrs = List[Float64](capacity=len(repeated))
    for index in range(len(repeated)):
        repeated_llrs.append(1.25 if repeated[index] == 0 else -1.25)
    var combined = lte_turbo_rate_recover(Span(repeated_llrs), 40, 2)
    for index in range(44):
        assert_equal(
            abs(combined.systematic[index]), 2.5
        )
        assert_equal(abs(combined.parity1[index]), 2.5)
        assert_equal(abs(combined.parity2[index]), 2.5)


def test_turbo_max_log_noiseless_seeded_blocks() raises:
    var block_sizes: List[Int] = [40, 48]
    for case_index in range(len(block_sizes)):
        var block_size = block_sizes[case_index]
        var bits = _pattern(block_size, UInt64(9001 + case_index))
        var encoded = lte_turbo_encode(Span(bits))
        var matched = lte_turbo_rate_match(
            Span(encoded.systematic),
            Span(encoded.parity1),
            Span(encoded.parity2),
            case_index + 1,
            3 * (block_size + 4),
        )
        var llrs = List[Float64](capacity=len(matched))
        for index in range(len(matched)):
            llrs.append(6.0 if matched[index] == 0 else -6.0)
        var recovered = lte_turbo_rate_recover(
            Span(llrs), block_size, case_index + 1
        )
        var decoded = lte_turbo_decode_max_log(
            Span(recovered.systematic),
            Span(recovered.parity1),
            Span(recovered.parity2),
            iterations=4,
        )
        assert_equal(decoded.bits, bits)
        assert_equal(decoded.iterations, 4)
        for index in range(block_size):
            assert_true(isfinite(decoded.posterior_llrs[index]))
            assert_true(
                decoded.posterior_llrs[index] >= 0.0
                if bits[index] == 0
                else decoded.posterior_llrs[index] < 0.0
            )


def test_turbo_checked_invalid_and_overflow_edges() raises:
    var empty = List[UInt8]()
    var bad: List[UInt8] = [0, 1, 2]
    with assert_raises():
        _ = lte_turbo_subblock_interleave(Span(empty))
    with assert_raises():
        _ = lte_turbo_subblock_interleave(Span(bad))
    var valid_subblock: List[UInt8] = [0, 0, 0, 1]
    with assert_raises():
        _ = lte_turbo_subblock_interleave(
            Span(valid_subblock), leading_null_bits=-1
        )
    with assert_raises():
        _ = lte_turbo_subblock_interleave(
            Span(valid_subblock), leading_null_bits=5
        )
    var invalid_size = List[UInt8](length=41, fill=UInt8(0))
    var invalid_binary = List[UInt8](length=40, fill=UInt8(0))
    invalid_binary[39] = 2
    with assert_raises():
        _ = lte_turbo_encode(Span(invalid_size))
    with assert_raises():
        _ = lte_turbo_encode(Span(invalid_binary))
    with assert_raises():
        _ = lte_turbo_encode(Span(invalid_binary), filler_bits=-1)
    var zero_block = List[UInt8](length=40, fill=UInt8(0))
    with assert_raises():
        _ = lte_turbo_encode(Span(zero_block), filler_bits=40)
    var nonzero_filler = List[UInt8](length=40, fill=UInt8(0))
    nonzero_filler[0] = UInt8(1)
    with assert_raises():
        _ = lte_turbo_encode(Span(nonzero_filler), filler_bits=1)
    with assert_raises():
        _ = lte_turbo_k0(Int.MAX, 0)
    with assert_raises():
        _ = lte_turbo_k0(44, 4)
    with assert_raises():
        _ = lte_turbo_k0(44, 0, Int.MAX)

    var stream0 = List[UInt8](length=44, fill=UInt8(0))
    var stream1 = List[UInt8](length=44, fill=UInt8(0))
    var stream2 = List[UInt8](length=44, fill=UInt8(0))
    var short_stream = List[UInt8](length=43, fill=UInt8(0))
    with assert_raises():
        _ = lte_turbo_circular_buffer(
            Span(stream0), Span(stream1), Span(short_stream)
        )
    with assert_raises():
        _ = lte_turbo_circular_buffer(
            Span(stream0), Span(stream1), Span(stream2), 40
        )
    with assert_raises():
        _ = lte_turbo_rate_match(
            Span(stream0), Span(stream1), Span(stream2), 0, -1
        )
    var empty_soft = List[Float64]()
    with assert_raises():
        _ = lte_turbo_rate_recover(Span(empty_soft), 41, 0)
    with assert_raises():
        _ = lte_turbo_rate_recover(
            Span(empty_soft), 40, 0, filler_bits=40
        )

    var huge = List[Float64](length=264, fill=Float64.MAX_FINITE)
    with assert_raises():
        _ = lte_turbo_rate_recover(Span(huge), 40, 0)
    var not_a_number: List[Float64] = [nan[DType.float64]()]
    with assert_raises():
        _ = lte_turbo_rate_recover(Span(not_a_number), 40, 0)
    var finite0 = List[Float64](length=44, fill=0.0)
    var finite1 = List[Float64](length=44, fill=0.0)
    var finite2 = List[Float64](length=44, fill=0.0)
    with assert_raises():
        _ = lte_turbo_decode_max_log(
            Span(finite0), Span(finite1), Span(finite2), iterations=0
        )
    finite2[3] = inf[DType.float64]()
    with assert_raises():
        _ = lte_turbo_decode_max_log(
            Span(finite0), Span(finite1), Span(finite2), iterations=1
        )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
