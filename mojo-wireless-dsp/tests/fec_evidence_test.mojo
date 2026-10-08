"""Independent FEC kernel evidence: static, edge, and seeded properties."""

from std.collections import Span
from std.testing import assert_equal, assert_raises, assert_true, TestSuite
from std.utils.numerics import inf, nan
from wireless_dsp.fec import (
    check_node_min_sum,
    check_node_normalized_min_sum,
    check_node_offset_min_sum,
    variable_node_sum,
    syndrome_ok,
    cyclic_shift,
    ldpc_decode_min_sum,
    ldpc_decode_layered_min_sum,
    convolutional_encode,
    viterbi_decode_hard,
    viterbi_decode_soft,
    puncture_bits,
    depuncture_llrs,
    polar_transform,
    polar_encode,
    polar_decode_sc,
    nr_small_block_basis_bit,
    nr_small_block_encode,
    nr_small_block_rate_match,
    nr_small_block_rate_recover_llrs,
    nr_small_block_decode_ml,
    polar_5g_reliability_sequence,
    polar_5g_mother_code_length,
    polar_5g_parity_construction,
    polar_5g_frozen_mask,
    polar_5g_input_interleave,
    polar_5g_input_deinterleave,
    polar_5g_encode,
    polar_5g_decode_sc,
    polar_5g_encode_with_parity,
    polar_5g_decode_sc_with_parity,
)


def _assert_close(
    actual: Float64, expected: Float64, tolerance: Float64
) raises:
    assert_true(abs(actual - expected) <= tolerance)


def _next_seed(mut state: UInt64) -> UInt64:
    state = (
        state * UInt64(6364136223846793005)
        + UInt64(1442695040888963407)
    )
    return state


def _analytic_check_message(
    values: Span[Float64, ...], excluded: Int, scale: Float64, offset: Float64
) -> Float64:
    var sign = 1
    var magnitude = Float64(1.0e300)
    for index in range(len(values)):
        if index == excluded:
            continue
        if values[index] < 0.0:
            sign = -sign
        magnitude = min(magnitude, abs(values[index]))
    magnitude = max(0.0, magnitude * scale - offset)
    return magnitude if sign > 0 else -magnitude


def _bits_from_integer(value: Int, length: Int) -> List[UInt8]:
    var result = List[UInt8](capacity=length)
    for index in range(length):
        result.append(UInt8((value >> (length - index - 1)) & 1))
    return result^


def _reference_parity(value: Int) -> UInt8:
    var word = value
    var result = UInt8(0)
    while word != 0:
        result ^= UInt8(word & 1)
        word >>= 1
    return result


def _reference_convolutional_encode(
    bits: Span[UInt8, ...],
    generators: Span[Int, ...],
    constraint_length: Int,
    terminate: Bool,
) -> List[UInt8]:
    # A deliberately separate scalar trellis definition.
    var register = 0
    var mask = (1 << constraint_length) - 1
    var steps = len(bits) + (constraint_length - 1 if terminate else 0)
    var result = List[UInt8](capacity=steps * len(generators))
    for step in range(steps):
        var bit = Int(bits[step]) if step < len(bits) else 0
        register = ((register << 1) | bit) & mask
        for output in range(len(generators)):
            result.append(
                _reference_parity(register & generators[output])
            )
    return result^


def _reference_ceil_log2_positive(value: Int) -> Int:
    var exponent = 0
    var power = Int128(1)
    while power < Int128(value):
        power <<= 1
        exponent += 1
    return exponent


def _reference_polar_mother_exponent(k: Int, e: Int, n_max: Int) -> Int:
    var ceil_log_e = _reference_ceil_log2_positive(e)
    var n1 = ceil_log_e
    var lower_power = Int128(1)
    if ceil_log_e > 0:
        lower_power <<= Int128(ceil_log_e - 1)
    if (
        ceil_log_e > 0
        and Int128(8) * Int128(e) <= Int128(9) * lower_power
        and Int128(16) * Int128(k) < Int128(9) * Int128(e)
    ):
        n1 -= 1
    var n2 = _reference_ceil_log2_positive(k) + 3
    return max(5, min(n1, min(n2, n_max)))


def _exhaustive_hard_viterbi_oracle(
    received: Span[UInt8, ...],
    generators: Span[Int, ...],
    constraint_length: Int,
    payload_length: Int,
) -> List[UInt8]:
    var best_distance = 1_000_000
    var best = List[UInt8](length=payload_length, fill=UInt8(0))
    for candidate in range(1 << payload_length):
        var bits = _bits_from_integer(candidate, payload_length)
        var coded = _reference_convolutional_encode(
            Span(bits), generators, constraint_length, True
        )
        var distance = 0
        for index in range(len(received)):
            distance += Int(coded[index] != received[index])
        if distance < best_distance:
            best_distance = distance
            best = bits^
    return best^


def _exhaustive_soft_viterbi_oracle(
    llrs: Span[Float64, ...],
    generators: Span[Int, ...],
    constraint_length: Int,
    payload_length: Int,
) -> List[UInt8]:
    var best_cost = Float64(1.0e300)
    var best = List[UInt8](length=payload_length, fill=UInt8(0))
    for candidate in range(1 << payload_length):
        var bits = _bits_from_integer(candidate, payload_length)
        var coded = _reference_convolutional_encode(
            Span(bits), generators, constraint_length, True
        )
        var cost = 0.0
        for index in range(len(llrs)):
            cost += (
                max(0.0, -llrs[index])
                if coded[index] == 0
                else max(0.0, llrs[index])
            )
        if cost < best_cost:
            best_cost = cost
            best = bits^
    return best^


def _reference_polar_transform(values: Span[UInt8, ...]) -> List[UInt8]:
    # Explicit generator-matrix formula x[j] = xor_i u[i] [(i & j) == j].
    var result = List[UInt8](length=len(values), fill=UInt8(0))
    for column in range(len(values)):
        var bit = UInt8(0)
        for row in range(len(values)):
            if (row & column) == column:
                bit ^= values[row]
        result[column] = bit
    return result^


def _reference_polar_encode(
    information: Span[UInt8, ...], frozen: Span[UInt8, ...]
) -> List[UInt8]:
    var values = List[UInt8](length=len(frozen), fill=UInt8(0))
    var source = 0
    for index in range(len(frozen)):
        if frozen[index] == 0:
            values[index] = information[source]
            source += 1
    return _reference_polar_transform(Span(values))


def _small_block_masks() -> List[UInt32]:
    # TS 38.212 Table 5.3.3.3-1 columns, transcribed independently.
    return [
        UInt32(0xFFFFFFFF),
        UInt32(0xCC95A5D2),
        UInt32(0x5A7089BE),
        UInt32(0x39CC64B6),
        UInt32(0x07C3E38E),
        UInt32(0x003FF07E),
        UInt32(0x2671B8CE),
        UInt32(0x0DAF22D6),
        UInt32(0x371843BE),
        UInt32(0x62ED85B2),
        UInt32(0xFFFF0F42),
    ]


def _reference_small_block_encode(bits: Span[UInt8, ...]) -> List[UInt8]:
    var masks = _small_block_masks()
    var result = List[UInt8](length=32, fill=UInt8(0))
    for row in range(32):
        for column in range(len(bits)):
            result[row] ^= bits[column] * UInt8(
                (masks[column] >> UInt32(31 - row)) & UInt32(1)
            )
    return result^


def _reference_small_block_metric(
    bits: Span[UInt8, ...], llrs: Span[Float64, ...]
) -> Float64:
    var coded = _reference_small_block_encode(bits)
    var metric = 0.0
    for index in range(len(llrs)):
        metric += (1.0 - 2.0 * Float64(coded[index % 32])) * llrs[index]
    return metric


def _reference_5g_k3(bits: Span[UInt8, ...]) -> List[UInt8]:
    # For N=E=32, TS 38.212 reliability selects u[29],u[30],u[31].
    # Rate matching then applies the normative 32-way sub-block permutation.
    var values = List[UInt8](length=32, fill=UInt8(0))
    values[29] = bits[0]
    values[30] = bits[1]
    values[31] = bits[2]
    var transformed = _reference_polar_transform(Span(values))
    var permutation: List[Int] = [
        0, 1, 2, 4, 3, 5, 6, 7,
        8, 16, 9, 17, 10, 18, 11, 19,
        12, 20, 13, 21, 14, 22, 15, 23,
        24, 25, 26, 28, 27, 29, 30, 31,
    ]
    var result = List[UInt8](capacity=32)
    for index in permutation:
        result.append(transformed[index])
    return result^


def _llrs_from_bits(bits: Span[UInt8, ...], magnitude: Float64) -> List[Float64]:
    var result = List[Float64](capacity=len(bits))
    for index in range(len(bits)):
        result.append(magnitude if bits[index] == 0 else -magnitude)
    return result^


def test_ldpc_primitives_analytic_seeded_and_edges() raises:
    var seed = UInt64(0xC0DEC0DE)
    for _ in range(24):
        var values = List[Float64](capacity=5)
        for _ in range(5):
            var random = _next_seed(seed)
            var magnitude = 1.0 + Float64((random >> UInt64(17)) % UInt64(19)) / 4.0
            values.append(
                -magnitude if ((random >> UInt64(9)) & UInt64(1)) == 1
                else magnitude
            )
        var plain = check_node_min_sum(Span(values))
        var normalized = check_node_normalized_min_sum(Span(values), 0.75)
        var offset = check_node_offset_min_sum(Span(values), 0.5)
        for index in range(5):
            _assert_close(
                plain[index],
                _analytic_check_message(Span(values), index, 1.0, 0.0),
                0.0,
            )

        var expected_variable = 1.25
        for index in range(len(values)):
            expected_variable += values[index]
        expected_variable = max(-7.0, min(7.0, expected_variable))
        _assert_close(
            variable_node_sum(1.25, Span(values), 7.0),
            expected_variable,
            0.0,
        )
        var random_shift = Int(
            (_next_seed(seed) >> UInt64(19)) % UInt64(41)
        ) - 20
        var seeded_shift = cyclic_shift(Span(values), random_shift)
        var normalized_shift = random_shift % len(values)
        if normalized_shift < 0:
            normalized_shift += len(values)
        for index in range(len(values)):
            assert_equal(
                seeded_shift[index],
                values[
                    (index - normalized_shift + len(values)) % len(values)
                ],
            )
            _assert_close(
                normalized[index],
                _analytic_check_message(Span(values), index, 0.75, 0.0),
                1.0e-12,
            )
            _assert_close(
                offset[index],
                _analytic_check_message(Span(values), index, 1.0, 0.5),
                0.0,
            )

    var messages: List[Float64] = [4.0, -1.5, 9.0]
    assert_equal(variable_node_sum(2.0, Span(messages), 8.0), 8.0)
    assert_equal(variable_node_sum(-2.0, Span(messages), 20.0), 9.5)

    var shifted_values: List[Float64] = [1.0, -2.0, 3.5, 7.0, -9.0]
    assert_equal(
        cyclic_shift(Span(shifted_values), -7),
        [3.5, 7.0, -9.0, 1.0, -2.0],
    )
    for shift in range(-17, 18):
        var shifted = cyclic_shift(Span(shifted_values), shift)
        var normalized_shift = shift % len(shifted_values)
        if normalized_shift < 0:
            normalized_shift += len(shifted_values)
        for index in range(len(shifted_values)):
            assert_equal(
                shifted[index],
                shifted_values[
                    (index - normalized_shift + len(shifted_values))
                    % len(shifted_values)
                ],
            )

    var offsets: List[Int] = [0, 2, 4]
    var columns: List[Int] = [0, 1, 1, 2]
    for candidate in range(8):
        var bits = _bits_from_integer(candidate, 3)
        var expected = (bits[0] ^ bits[1]) == 0 and (bits[1] ^ bits[2]) == 0
        assert_equal(
            syndrome_ok(Span(bits), Span(offsets), Span(columns)), expected
        )

    var one_value: List[Float64] = [1.0]
    with assert_raises():
        _ = check_node_min_sum(Span(one_value))
    var nonfinite_values: List[Float64] = [1.0, nan[DType.float64]()]
    with assert_raises():
        _ = check_node_min_sum(Span(nonfinite_values))
    var valid_values: List[Float64] = [1.0, -2.0]
    with assert_raises():
        _ = check_node_normalized_min_sum(Span(valid_values), 0.0)
    with assert_raises():
        _ = check_node_normalized_min_sum(
            Span(valid_values), nan[DType.float64]()
        )
    with assert_raises():
        _ = check_node_offset_min_sum(Span(valid_values), -1.0)
    with assert_raises():
        _ = check_node_offset_min_sum(
            Span(valid_values), inf[DType.float64]()
        )
    with assert_raises():
        _ = variable_node_sum(inf[DType.float64](), Span(messages), 10.0)
    with assert_raises():
        _ = variable_node_sum(1.0, Span(messages), 0.0)
    var bad_message: List[Float64] = [nan[DType.float64]()]
    with assert_raises():
        _ = variable_node_sum(1.0, Span(bad_message), 10.0)
    var empty = List[Float64]()
    assert_equal(cyclic_shift(Span(empty), -99), empty)
    with assert_raises():
        _ = cyclic_shift(Span(nonfinite_values), 1)
    var invalid_bits: List[UInt8] = [0, 2, 0]
    with assert_raises():
        _ = syndrome_ok(Span(invalid_bits), Span(offsets), Span(columns))
    var duplicate_columns: List[Int] = [0, 0, 1, 2]
    with assert_raises():
        _ = syndrome_ok(
            Span(_bits_from_integer(0, 3)),
            Span(offsets),
            Span(duplicate_columns),
        )


def test_ldpc_decoders_exhaustive_codeword_oracle_and_edges() raises:
    # H = [[1,1,0], [0,1,1]] has exactly the two codewords 000 and 111.
    var offsets: List[Int] = [0, 2, 4]
    var columns: List[Int] = [0, 1, 1, 2]
    var seed = UInt64(0x1D9C5EED)
    for trial in range(24):
        var transmitted = UInt8(trial & 1)
        var llrs = List[Float64](capacity=3)
        for _ in range(3):
            var random = _next_seed(seed)
            var perturbation = Float64(Int((random >> UInt64(20)) % UInt64(9)) - 4) / 8.0
            var value = 6.0 + perturbation
            llrs.append(value if transmitted == 0 else -value)
        # Exhaustively score both valid words; this does not invoke either decoder.
        var metric_zero = llrs[0] + llrs[1] + llrs[2]
        var metric_one = -metric_zero
        var expected_bit = UInt8(0) if metric_zero >= metric_one else UInt8(1)
        var expected: List[UInt8] = [expected_bit, expected_bit, expected_bit]
        var flooding = ldpc_decode_min_sum(
            Span(llrs), Span(offsets), Span(columns),
            max_iterations=8, normalization=0.75, offset=0.125,
        )
        var layered = ldpc_decode_layered_min_sum(
            Span(llrs), Span(offsets), Span(columns),
            max_iterations=8, normalization=0.75, offset=0.125,
        )
        assert_true(flooding.converged and layered.converged)
        assert_equal(flooding.bits, expected)
        assert_equal(layered.bits, expected)

    var valid_llrs: List[Float64] = [2.0, 2.0, 2.0]
    with assert_raises():
        _ = ldpc_decode_min_sum(
            Span(valid_llrs), Span(offsets), Span(columns), max_iterations=0
        )
    with assert_raises():
        _ = ldpc_decode_layered_min_sum(
            Span(valid_llrs), Span(offsets), Span(columns),
            max_iterations=1, normalization=inf[DType.float64](),
        )
    var invalid_llrs: List[Float64] = [2.0, nan[DType.float64](), 2.0]
    with assert_raises():
        _ = ldpc_decode_min_sum(
            Span(invalid_llrs), Span(offsets), Span(columns), max_iterations=1
        )
    with assert_raises():
        _ = ldpc_decode_layered_min_sum(
            Span(invalid_llrs), Span(offsets), Span(columns), max_iterations=1
        )
    var malformed_offsets: List[Int] = [0, 1, 4]
    with assert_raises():
        _ = ldpc_decode_min_sum(
            Span(valid_llrs), Span(malformed_offsets), Span(columns),
            max_iterations=1,
        )
    with assert_raises():
        _ = ldpc_decode_layered_min_sum(
            Span(valid_llrs), Span(malformed_offsets), Span(columns),
            max_iterations=1,
        )


def test_convolutional_trellis_exhaustive_oracles_and_edges() raises:
    var generators: List[Int] = [0b111, 0b101]
    var property_pattern: List[UInt8] = [1, 0, 1, 1, 0]
    var seed = UInt64(0xBCC5EED)
    for trial in range(24):
        var random = _next_seed(seed)
        var payload = _bits_from_integer(Int(random & UInt64(31)), 5)
        var expected_coded = _reference_convolutional_encode(
            Span(payload), Span(generators), 3, True
        )
        assert_equal(
            convolutional_encode(Span(payload), Span(generators), 3),
            expected_coded,
        )

        var property_punctured = puncture_bits(
            Span(expected_coded), Span(property_pattern)
        )
        var expected_punctured = List[UInt8]()
        for index in range(len(expected_coded)):
            if property_pattern[index % len(property_pattern)] == 1:
                expected_punctured.append(expected_coded[index])
        assert_equal(property_punctured, expected_punctured)
        var property_llrs = List[Float64](capacity=len(property_punctured))
        for index in range(len(property_punctured)):
            property_llrs.append(
                Float64(index + 1)
                if property_punctured[index] == 0
                else -Float64(index + 1)
            )
        var property_depunctured = depuncture_llrs(
            Span(property_llrs), Span(property_pattern), len(expected_coded)
        )
        var source = 0
        for index in range(len(expected_coded)):
            if property_pattern[index % len(property_pattern)] == 1:
                assert_equal(property_depunctured[index], property_llrs[source])
                source += 1
            else:
                assert_equal(property_depunctured[index], 0.0)

        var hard_received = expected_coded.copy()
        hard_received[Int((random >> UInt64(8)) % UInt64(len(hard_received)))] ^= 1
        assert_equal(
            viterbi_decode_hard(
                Span(hard_received), Span(generators), 3
            ),
            _exhaustive_hard_viterbi_oracle(
                Span(hard_received), Span(generators), 3, 5
            ),
        )

        var soft = List[Float64](capacity=len(expected_coded))
        for index in range(len(expected_coded)):
            var magnitude = 1.0 + Float64((index + trial) % 7) * 0.375
            soft.append(
                magnitude if expected_coded[index] == 0 else -magnitude
            )
        soft[Int((random >> UInt64(15)) % UInt64(len(soft)))] *= -0.25
        assert_equal(
            viterbi_decode_soft(Span(soft), Span(generators), 3),
            _exhaustive_soft_viterbi_oracle(
                Span(soft), Span(generators), 3, 5
            ),
        )

    var mother: List[UInt8] = [1, 0, 1, 1, 0, 0, 1, 0, 1]
    var pattern: List[UInt8] = [1, 1, 0, 1]
    assert_equal(
        puncture_bits(Span(mother), Span(pattern)),
        [UInt8(1), UInt8(0), UInt8(1), UInt8(0), UInt8(0), UInt8(0), UInt8(1)],
    )
    var punctured_llrs: List[Float64] = [1.25, -2.0, 3.5, 4.0, -5.0]
    var depuncture_pattern: List[UInt8] = [1, 0, 1]
    assert_equal(
        depuncture_llrs(
            Span(punctured_llrs), Span(depuncture_pattern), 7
        ),
        [1.25, 0.0, -2.0, 3.5, 0.0, 4.0, -5.0],
    )

    var invalid_payload: List[UInt8] = [0, 2, 1]
    with assert_raises():
        _ = convolutional_encode(
            Span(invalid_payload), Span(generators), 3
        )
    var invalid_generators: List[Int] = [0]
    var valid_payload: List[UInt8] = [0, 1, 0]
    with assert_raises():
        _ = convolutional_encode(
            Span(valid_payload), Span(invalid_generators), 3
        )
    var odd_hard: List[UInt8] = [0, 1, 0]
    with assert_raises():
        _ = viterbi_decode_hard(Span(odd_hard), Span(generators), 3)
    var invalid_hard: List[UInt8] = [0, 2, 0, 1]
    with assert_raises():
        _ = viterbi_decode_hard(
            Span(invalid_hard), Span(generators), 3, terminate=False
        )
    var invalid_soft: List[Float64] = [1.0, nan[DType.float64](), 1.0, 1.0]
    with assert_raises():
        _ = viterbi_decode_soft(
            Span(invalid_soft), Span(generators), 3, terminate=False
        )
    var empty_pattern = List[UInt8]()
    with assert_raises():
        _ = puncture_bits(Span(mother), Span(empty_pattern))
    var invalid_pattern: List[UInt8] = [1, 2]
    with assert_raises():
        _ = puncture_bits(Span(mother), Span(invalid_pattern))
    with assert_raises():
        _ = depuncture_llrs(
            Span(punctured_llrs), Span(depuncture_pattern), 9
        )
    var nonfinite_llrs: List[Float64] = [1.0, inf[DType.float64]()]
    with assert_raises():
        _ = depuncture_llrs(
            Span(nonfinite_llrs), Span(depuncture_pattern), 2
        )


def test_polar_matrix_exhaustive_oracles_and_edges() raises:
    var seed = UInt64(0x501A5EED)
    var frozen: List[UInt8] = [1, 1, 1, 0, 1, 0, 0, 0]
    for _ in range(32):
        var random = _next_seed(seed)
        var values = _bits_from_integer(Int(random & UInt64(255)), 8)
        var expected_transform = _reference_polar_transform(Span(values))
        var actual_transform = values.copy()
        polar_transform(actual_transform)
        assert_equal(actual_transform, expected_transform)

        var information = _bits_from_integer(Int(random & UInt64(15)), 4)
        var expected_codeword = _reference_polar_encode(
            Span(information), Span(frozen)
        )
        assert_equal(
            polar_encode(Span(information), Span(frozen)), expected_codeword
        )
        var llrs = _llrs_from_bits(Span(expected_codeword), 32.0)
        assert_equal(
            polar_decode_sc(Span(llrs), Span(frozen)), information
        )

    var empty_bits = List[UInt8]()
    with assert_raises():
        polar_transform(empty_bits)
    var non_power: List[UInt8] = [0, 1, 0]
    with assert_raises():
        polar_transform(non_power)
    var invalid_transform: List[UInt8] = [0, 1, 2, 0]
    with assert_raises():
        polar_transform(invalid_transform)
    var bad_frozen: List[UInt8] = [1, 2, 0, 0]
    var two_bits: List[UInt8] = [0, 1]
    with assert_raises():
        _ = polar_encode(Span(two_bits), Span(bad_frozen))
    var mismatched_frozen: List[UInt8] = [1, 0, 0, 0]
    with assert_raises():
        _ = polar_encode(Span(two_bits), Span(mismatched_frozen))
    var bad_llrs: List[Float64] = [1.0, 1.0, nan[DType.float64](), 1.0]
    var decoder_frozen: List[UInt8] = [1, 1, 0, 0]
    with assert_raises():
        _ = polar_decode_sc(Span(bad_llrs), Span(decoder_frozen))


def test_small_block_normative_exhaustive_oracles_and_edges() raises:
    var masks = _small_block_masks()
    for row in range(32):
        for column in range(11):
            var expected = UInt8(
                (masks[column] >> UInt32(31 - row)) & UInt32(1)
            )
            assert_equal(nr_small_block_basis_bit(row, column), expected)

    var seed = UInt64(0x38_212_5EED)
    for length in range(3, 8):
        for trial in range(2):
            var random = _next_seed(seed)
            var information = _bits_from_integer(
                Int(random % UInt64(1 << length)), length
            )
            var expected_codeword = _reference_small_block_encode(
                Span(information)
            )
            assert_equal(
                nr_small_block_encode(Span(information)), expected_codeword
            )

            var output_length = 17 + Int((random >> UInt64(11)) % UInt64(49))
            var matched = nr_small_block_rate_match(
                Span(expected_codeword), output_length
            )
            for index in range(output_length):
                assert_equal(matched[index], expected_codeword[index % 32])
            var llrs = List[Float64](capacity=output_length)
            for index in range(output_length):
                var magnitude = 1.0 + Float64((index + trial) % 5) * 0.5
                llrs.append(
                    magnitude if matched[index] == 0 else -magnitude
                )
            var recovered = nr_small_block_rate_recover_llrs(Span(llrs))
            for index in range(32):
                var expected_llr = 0.0
                var source = index
                while source < len(llrs):
                    expected_llr += llrs[source]
                    source += 32
                _assert_close(recovered[index], expected_llr, 0.0)

            var decoded = nr_small_block_decode_ml(
                Span(llrs), length
            )
            var expected_candidate = 0
            var best_metric = Float64(-1.0e300)
            var second_metric = Float64(-1.0e300)
            for candidate in range(1 << length):
                var candidate_bits = _bits_from_integer(candidate, length)
                var metric = _reference_small_block_metric(
                    Span(candidate_bits), Span(llrs)
                )
                if metric > best_metric:
                    second_metric = best_metric
                    best_metric = metric
                    expected_candidate = candidate
                elif metric > second_metric:
                    second_metric = metric
            assert_equal(
                decoded.bits,
                _bits_from_integer(expected_candidate, length),
            )
            _assert_close(decoded.metric, best_metric, 1.0e-10)
            _assert_close(
                decoded.margin, best_metric - second_metric, 1.0e-10
            )

    with assert_raises():
        _ = nr_small_block_basis_bit(-1, 0)
    with assert_raises():
        _ = nr_small_block_basis_bit(31, 11)
    var too_short: List[UInt8] = [0, 1]
    with assert_raises():
        _ = nr_small_block_encode(Span(too_short))
    var invalid_information: List[UInt8] = [0, 2, 1]
    with assert_raises():
        _ = nr_small_block_encode(Span(invalid_information))
    var short_codeword = List[UInt8](length=31, fill=UInt8(0))
    with assert_raises():
        _ = nr_small_block_rate_match(Span(short_codeword), 32)
    var invalid_codeword = List[UInt8](length=32, fill=UInt8(0))
    invalid_codeword[0] = 2
    with assert_raises():
        _ = nr_small_block_rate_match(Span(invalid_codeword), 32)
    var empty_llrs = List[Float64]()
    with assert_raises():
        _ = nr_small_block_rate_recover_llrs(Span(empty_llrs))
    var nonfinite_llrs: List[Float64] = [nan[DType.float64]()]
    with assert_raises():
        _ = nr_small_block_rate_recover_llrs(Span(nonfinite_llrs))
    var overflow_llrs = List[Float64](length=33, fill=0.0)
    overflow_llrs[0] = 1.0e308
    overflow_llrs[32] = 1.0e308
    with assert_raises():
        _ = nr_small_block_rate_recover_llrs(Span(overflow_llrs))
    with assert_raises():
        _ = nr_small_block_decode_ml(Span(empty_llrs), 3)
    with assert_raises():
        _ = nr_small_block_decode_ml(Span(nonfinite_llrs), 3)
    var one_llr: List[Float64] = [1.0]
    with assert_raises():
        _ = nr_small_block_decode_ml(Span(one_llr), 12)


def test_polar5g_static_construction_codec_and_edges() raises:
    var reliability = polar_5g_reliability_sequence()
    var reliability_again = polar_5g_reliability_sequence()
    assert_equal(len(reliability), 1024)
    assert_equal(reliability, reliability_again)
    var expected_first: List[Int] = [
        0, 1, 2, 4, 8, 16, 32, 3, 5, 64, 9, 6, 17, 10, 18, 128,
    ]
    var expected_last: List[Int] = [
        959, 1011, 1013, 895, 1006, 1014, 1017, 1018,
        991, 1020, 1007, 1015, 1019, 1021, 1022, 1023,
    ]
    var seen = List[UInt8](length=1024, fill=UInt8(0))
    var reliability_checksum = UInt64(1469598103934665603)
    for index in range(1024):
        assert_true(reliability[index] >= 0 and reliability[index] < 1024)
        assert_equal(seen[reliability[index]], UInt8(0))
        seen[reliability[index]] = 1
        reliability_checksum = (
            reliability_checksum
            ^ UInt64(reliability[index] + 1024 * index)
        ) * UInt64(1099511628211)
        if index < 16:
            assert_equal(reliability[index], expected_first[index])
            assert_equal(reliability[1008 + index], expected_last[index])
    # Frozen full-table fingerprint derived from TS 38.212 V18.8.0,
    # Table 5.3.1.2-1, catches any unsampled permutation drift.
    assert_equal(reliability_checksum, UInt64(0xE77FE08E2BFCFAC1))
    reliability[0] = 1023
    assert_equal(reliability_again[0], 0)

    for n_max in range(5, 11):
        for e in [1, 2, 3, 4, 5, 8, 9, 16, 17, 31, 32, 33, 64, 65, 128, 864, 1024, Int.MAX]:
            for k in [1, 2, 3, 4, 5, 8, 16, 31, 32, 56, 128, 512, 1024]:
                if k <= e:
                    assert_equal(
                        polar_5g_mother_code_length(k, e, n_max=n_max),
                        _reference_polar_mother_exponent(k, e, n_max),
                    )
    with assert_raises():
        _ = polar_5g_mother_code_length(Int.MIN, 32)
    with assert_raises():
        _ = polar_5g_mother_code_length(3, Int.MIN)
    with assert_raises():
        _ = polar_5g_mother_code_length(3, 32, n_max=Int.MIN)
    with assert_raises():
        _ = polar_5g_mother_code_length(3, 32, n_max=Int.MAX)
    with assert_raises():
        _ = polar_5g_mother_code_length(Int.MAX, 32)
    var frozen = polar_5g_frozen_mask(3, 32)
    var expected_information_positions: List[Int] = [29, 30, 31]
    var information_positions = List[Int]()
    for index in range(32):
        if frozen[index] == 0:
            information_positions.append(index)
    assert_equal(information_positions, expected_information_positions)

    var parity = polar_5g_parity_construction(3, 32, n_pc=1)
    var selected_positions = List[Int]()
    var parity_positions = List[Int]()
    for index in range(32):
        if parity.frozen[index] == 0:
            selected_positions.append(index)
        if parity.parity_check[index] == 1:
            parity_positions.append(index)
    assert_equal(selected_positions, [Int(27), Int(29), Int(30), Int(31)])
    assert_equal(parity_positions, [Int(27)])

    var interleave_indices: List[Int] = [
        0, 2, 6, 7, 8, 1, 3, 9, 4, 10, 5, 11, 12, 13, 14, 15,
        16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31,
    ]
    var input = List[UInt8](capacity=32)
    for index in range(32):
        input.append(UInt8(((index * 13 + index // 3 + 1) >> 1) & 1))
    var expected_interleaved = List[UInt8](capacity=32)
    for index in interleave_indices:
        expected_interleaved.append(input[index])
    var interleaved = polar_5g_input_interleave(Span(input))
    assert_equal(interleaved, expected_interleaved)
    assert_equal(
        polar_5g_input_deinterleave(Span(expected_interleaved)), input
    )

    var seed = UInt64(0x5F00_38_212)
    for _ in range(12):
        var random = _next_seed(seed)
        var k = 3 + Int(random % UInt64(9))
        var property_input = List[UInt8](capacity=32)
        for index in range(32):
            property_input.append(UInt8(
                (random >> UInt64(index % 23)) & UInt64(1)
            ))
        var property_interleaved = polar_5g_input_interleave(
            Span(property_input)
        )
        assert_equal(
            polar_5g_input_deinterleave(Span(property_interleaved)),
            property_input,
        )
        var property_frozen = polar_5g_frozen_mask(k, 32)
        var frozen_count = 0
        for value in property_frozen:
            frozen_count += Int(value == 1)
        assert_equal(len(property_frozen) - frozen_count, k)
        var property_parity = polar_5g_parity_construction(
            k, 32, n_pc=1
        )
        var selected_count = 0
        var parity_count = 0
        for index in range(len(property_parity.frozen)):
            selected_count += Int(property_parity.frozen[index] == 0)
            parity_count += Int(property_parity.parity_check[index] == 1)
        assert_equal(selected_count, k + 1)
        assert_equal(parity_count, 1)

    for _ in range(24):
        var random = _next_seed(seed)
        var information = _bits_from_integer(Int(random & UInt64(7)), 3)
        var expected_coded = _reference_5g_k3(Span(information))
        assert_equal(
            polar_5g_encode(Span(information), 32), expected_coded
        )
        var llrs = _llrs_from_bits(Span(expected_coded), 40.0)
        assert_equal(polar_5g_decode_sc(Span(llrs), 3), information)

        # The independently fixed K=3 construction adds a zero PC bit at u[27].
        assert_equal(
            polar_5g_encode_with_parity(
                Span(information), 32, n_pc=1
            ),
            expected_coded,
        )
        var parity_decoded = polar_5g_decode_sc_with_parity(
            Span(llrs), 3, n_pc=1
        )
        assert_equal(parity_decoded.bits, information)
        assert_true(parity_decoded.parity_ok)

    with assert_raises():
        _ = polar_5g_mother_code_length(0, 32)
    with assert_raises():
        _ = polar_5g_mother_code_length(33, 32)
    with assert_raises():
        _ = polar_5g_mother_code_length(3, 32, n_max=4)
    with assert_raises():
        _ = polar_5g_frozen_mask(0, 32)
    with assert_raises():
        _ = polar_5g_parity_construction(3, 32, n_pc=-1)
    with assert_raises():
        _ = polar_5g_parity_construction(3, 32, n_pc=1, n_pc_wm=2)
    var too_long = List[UInt8](length=165, fill=UInt8(0))
    with assert_raises():
        _ = polar_5g_input_interleave(Span(too_long))
    with assert_raises():
        _ = polar_5g_input_deinterleave(Span(too_long))
    var invalid_input = List[UInt8](length=32, fill=UInt8(0))
    invalid_input[7] = 2
    with assert_raises():
        _ = polar_5g_input_interleave(Span(invalid_input))
    with assert_raises():
        _ = polar_5g_input_deinterleave(Span(invalid_input))
    var invalid_information: List[UInt8] = [0, 2, 1]
    with assert_raises():
        _ = polar_5g_encode(Span(invalid_information), 32)
    with assert_raises():
        _ = polar_5g_encode_with_parity(
            Span(invalid_information), 32, n_pc=1
        )
    var invalid_llrs = List[Float64](length=32, fill=1.0)
    invalid_llrs[3] = nan[DType.float64]()
    with assert_raises():
        _ = polar_5g_decode_sc(Span(invalid_llrs), 3)
    with assert_raises():
        _ = polar_5g_decode_sc_with_parity(
            Span(invalid_llrs), 3, n_pc=1
        )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
