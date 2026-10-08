"""Bit-exact acceptance tests for the isolated fixed Wi-Fi BCC backend."""

from std.collections import Span
from std.testing import assert_equal, assert_raises, assert_true, TestSuite
from wireless_dsp.fec.convolutional import (
    convolutional_encode,
    viterbi_decode_hard,
    viterbi_decode_soft,
)
from wireless_dsp.numerics.fixed import (
    OVERFLOW_SATURATE,
    OVERFLOW_WRAP,
    ROUND_NEAREST_AWAY,
)
from wireless_dsp.numerics.quantization import QFormat
from wireless_dsp.backend.fixed_wifi_bcc_reference import (
    WIFI_BCC_CONSTRAINT_LENGTH,
    WIFI_BCC_GENERATOR_A,
    WIFI_BCC_GENERATOR_B,
    WIFI_BCC_RATE_NUMERATOR,
    WIFI_BCC_RATE_DENOMINATOR,
    WIFI_BCC_STATE_COUNT,
    WIFI_BCC_TIE_LOWER_PREDECESSOR,
    FixedWifiBCCViterbiConfig,
    fixed_wifi_bcc_canonical_rtl_vectors,
    fixed_wifi_bcc_encode,
    fixed_wifi_bcc_hard_llrs_raw,
    fixed_wifi_bcc_result_checksum,
    fixed_wifi_bcc_viterbi_decode_hard,
    fixed_wifi_bcc_viterbi_decode_soft,
)


def _oracle_fnv1a_text(text: StringSlice) -> UInt64:
    var state = UInt64(14695981039346656037)
    var bytes = text.as_bytes()
    for index in range(len(bytes)):
        state ^= UInt64(UInt8(bytes[index]))
        state *= UInt64(1099511628211)
    return state


def _static_payload() -> List[UInt8]:
    return [
        1, 0, 1, 1, 0, 0, 1, 0,
        0, 1, 1, 0, 1, 0, 0, 1,
    ]


def _static_coded_oracle() -> List[UInt8]:
    # Independently generated K=7 shift-register vector.  At each step the new
    # bit enters the LSB and parity is evaluated with octal masks 133 and 171;
    # six zero tail bits force state zero.
    return [
        1, 1, 1, 0, 1, 1, 1, 0, 0, 1, 1, 0,
        0, 0, 0, 0, 1, 0, 1, 1, 1, 0, 1, 1,
        1, 1, 1, 0, 1, 0, 1, 0, 1, 0, 0, 1,
        0, 0, 1, 1, 0, 1, 1, 1,
    ]


def _static_soft_llrs() -> List[Int64]:
    # Varying confidence, three wrong signs, and two exact erasures.  These are
    # raw Q8.2 words and were fixed independently of the decoder implementation.
    return [
        -3, -5, -7, 2, -6, -3, -5, -7, 2, -6, -3,
        0, 7, 2, 6, 3, -5, 7, 2, -6, -3, 5,
        -7, -2, -6, 0, -5, 7, -2, 6, -3, -5, -7,
        2, 6, -3, 5, 7, -2, -6, 3, -5, -7, -2,
    ]


def _as_float64(values: Span[Int64, ...]) -> List[Float64]:
    var result = List[Float64](capacity=len(values))
    for index in range(len(values)):
        result.append(Float64(values[index]))
    return result^


def _generators() -> List[Int]:
    return [0o133, 0o171]


def test_static_standard_vector_and_quantized_decode() raises:
    assert_equal(WIFI_BCC_CONSTRAINT_LENGTH, 7)
    assert_equal(WIFI_BCC_STATE_COUNT, 64)
    assert_equal(WIFI_BCC_GENERATOR_A, 0o133)
    assert_equal(WIFI_BCC_GENERATOR_B, 0o171)
    assert_equal(WIFI_BCC_RATE_NUMERATOR, 1)
    assert_equal(WIFI_BCC_RATE_DENOMINATOR, 2)
    assert_equal(WIFI_BCC_TIE_LOWER_PREDECESSOR, 0)

    var payload = _static_payload()
    var coded = fixed_wifi_bcc_encode(Span(payload))
    assert_equal(coded, _static_coded_oracle())
    var hard = fixed_wifi_bcc_viterbi_decode_hard(
        Span(coded), metric_storage_bits=12
    )
    assert_equal(hard.bits, payload)
    assert_equal(hard.final_state, 0)
    assert_equal(hard.final_normalized_metric_raw, Int64(0))
    assert_equal(hard.saturation_count, 0)

    var llr_format = QFormat(
        8, 2, ROUND_NEAREST_AWAY, OVERFLOW_SATURATE
    )
    var llrs = _static_soft_llrs()
    var config = FixedWifiBCCViterbiConfig(llr_format, 16)
    var soft = fixed_wifi_bcc_viterbi_decode_soft(Span(llrs), config)
    assert_equal(soft.bits, payload)
    assert_equal(soft.final_state, 0)
    assert_equal(soft.metric_fraction_bits, 2)
    assert_equal(len(soft.normalization_offsets_raw), 22)
    assert_equal(len(soft.survivor_predecessors), 22 * 64)
    assert_equal(len(soft.survivor_decisions), 22 * 64)

    # The pre-existing Float64 decoder is a separate implementation and must
    # select the same ML path for these integer-valued metrics.
    var float_llrs = _as_float64(Span(llrs))
    var generators = _generators()
    assert_equal(
        viterbi_decode_soft(Span(float_llrs), Span(generators), 7),
        soft.bits,
    )


def test_saturation_zero_tie_and_edge_contracts() raises:
    var saturating_q = QFormat(
        4, 0, ROUND_NEAREST_AWAY, OVERFLOW_SATURATE
    )
    var hard_bits: List[UInt8] = [0, 1, 0, 1]
    assert_equal(
        fixed_wifi_bcc_hard_llrs_raw(
            Span(hard_bits), Int64(1_000_000), saturating_q
        ),
        [Int64(7), -7, 7, -7],
    )

    # With all-zero LLRs every branch is tied.  Lower-predecessor survivor ties,
    # forced final state zero, and the zero-tail strip produce all-zero payload.
    var zero_llrs = List[Int64](length=16, fill=Int64(0))
    var tied = fixed_wifi_bcc_viterbi_decode_soft(
        Span(zero_llrs), FixedWifiBCCViterbiConfig(saturating_q, 4)
    )
    assert_equal(tied.bits, [UInt8(0), UInt8(0)])
    assert_equal(tied.final_state, 0)
    assert_equal(tied.final_normalized_metric_raw, Int64(0))

    # At seven unterminated zero-cost steps every state is reachable.  The
    # final-state tie selects state zero and the tied state-zero survivor at
    # the last step selects predecessor zero rather than predecessor 32.
    var unterminated_zero_llrs = List[Int64](length=14, fill=Int64(0))
    var final_tied = fixed_wifi_bcc_viterbi_decode_soft(
        Span(unterminated_zero_llrs),
        FixedWifiBCCViterbiConfig(saturating_q, 4),
        terminate=False,
    )
    assert_equal(final_tied.final_state, 0)
    assert_equal(
        final_tied.bits,
        [UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0)],
    )
    assert_equal(final_tied.survivor_predecessors[6 * 64], 0)

    # Q4.0 has the asymmetric raw range [-8, 7].  The -8 input is legal, its
    # negated max-log penalty saturates to the four-bit metric maximum, and the
    # surviving noiseless decision is still exactly one.
    var minimum_llrs: List[Int64] = [-8, 0]
    var minimum_result = fixed_wifi_bcc_viterbi_decode_soft(
        Span(minimum_llrs),
        FixedWifiBCCViterbiConfig(saturating_q, 4),
        terminate=False,
    )
    assert_equal(minimum_result.bits, [UInt8(1)])
    assert_equal(minimum_result.saturation_count, 1)

    # A two-bit signed metric has maximum raw value one.  Correct hard branches
    # remain zero while competing paths clamp; the saturation counter is an
    # explicit checkpoint and decoding remains deterministic.
    var payload = _static_payload()
    var coded = fixed_wifi_bcc_encode(Span(payload))
    var narrow = fixed_wifi_bcc_viterbi_decode_hard(
        Span(coded), metric_storage_bits=2
    )
    assert_equal(narrow.bits, payload)
    assert_true(narrow.saturation_count > 0)
    for index in range(len(narrow.final_metrics_raw)):
        assert_true(narrow.final_metrics_raw[index] >= 0)
        assert_true(narrow.final_metrics_raw[index] <= 1)

    var invalid_bit: List[UInt8] = [0, 2]
    with assert_raises():
        _ = fixed_wifi_bcc_encode(Span(invalid_bit))
    with assert_raises():
        _ = fixed_wifi_bcc_viterbi_decode_hard(
            Span(invalid_bit), terminate=False
        )
    with assert_raises():
        _ = fixed_wifi_bcc_hard_llrs_raw(
            Span(hard_bits), Int64(0), saturating_q
        )
    with assert_raises():
        _ = FixedWifiBCCViterbiConfig(
            QFormat(4, 0, ROUND_NEAREST_AWAY, OVERFLOW_WRAP), 8
        )
    with assert_raises():
        _ = FixedWifiBCCViterbiConfig(saturating_q, 1)
    with assert_raises():
        _ = FixedWifiBCCViterbiConfig(QFormat(8, 6), 6)
    var odd_hard: List[UInt8] = [0, 1, 0]
    with assert_raises():
        _ = fixed_wifi_bcc_viterbi_decode_hard(Span(odd_hard))
    var odd_soft: List[Int64] = [0, 0, 0]
    with assert_raises():
        _ = fixed_wifi_bcc_viterbi_decode_soft(
            Span(odd_soft),
            FixedWifiBCCViterbiConfig(saturating_q, 8),
            terminate=False,
        )
    var short_terminated: List[UInt8] = [0, 0]
    with assert_raises():
        _ = fixed_wifi_bcc_viterbi_decode_hard(Span(short_terminated))
    var out_of_range_llrs: List[Int64] = [Int64(8), 0]
    with assert_raises():
        _ = fixed_wifi_bcc_viterbi_decode_soft(
            Span(out_of_range_llrs),
            FixedWifiBCCViterbiConfig(saturating_q, 8),
            terminate=False,
        )


def test_exhaustive_small_payloads_and_reference_encoder_differential() raises:
    var generators = _generators()
    for length in range(9):
        for pattern in range(1 << length):
            var payload = List[UInt8](capacity=length)
            for index in range(length):
                payload.append(UInt8((pattern >> index) & 1))
            var actual = fixed_wifi_bcc_encode(Span(payload))
            var reference = convolutional_encode(
                Span(payload), Span(generators), 7
            )
            assert_equal(actual, reference)
            var decoded = fixed_wifi_bcc_viterbi_decode_hard(Span(actual))
            assert_equal(decoded.bits, payload)


def test_seeded_soft_property_matches_float64_oracle() raises:
    var llr_format = QFormat(
        10, 3, ROUND_NEAREST_AWAY, OVERFLOW_SATURATE
    )
    var config = FixedWifiBCCViterbiConfig(llr_format, 24)
    var generators = _generators()
    var state = UInt64(0xBCCD15EA5EED)
    for case_index in range(24):
        var length = 17 + case_index % 19
        var payload = List[UInt8](capacity=length)
        for _ in range(length):
            state = (
                state * UInt64(6364136223846793005)
                + UInt64(1442695040888963407)
            )
            payload.append(UInt8((state >> 63) & 1))
        var coded = fixed_wifi_bcc_encode(Span(payload))
        var corrupted = coded.copy()
        var flipped_index = (11 * case_index + 5) % len(corrupted)
        corrupted[flipped_index] ^= UInt8(1)
        var integer_hard = fixed_wifi_bcc_viterbi_decode_hard(
            Span(corrupted)
        )
        var floating_hard = viterbi_decode_hard(
            Span(corrupted), Span(generators), 7
        )
        assert_equal(integer_hard.bits, floating_hard)
        assert_equal(integer_hard.bits, payload)

        var llrs = List[Int64](capacity=len(coded))
        for index in range(len(coded)):
            var magnitude = Int64(9 + (index * 7 + case_index * 3) % 23)
            var value = magnitude if coded[index] == 0 else -magnitude
            # One weak wrong sign and one erasure exercise soft rather than hard
            # equivalence without overwhelming the terminated rate-1/2 code.
            if index == (5 * case_index + 3) % len(coded):
                value = -Int64(2) if coded[index] == 0 else Int64(2)
            if index == (7 * case_index + 11) % len(coded):
                value = Int64(0)
            llrs.append(value)
        var integer = fixed_wifi_bcc_viterbi_decode_soft(Span(llrs), config)
        var float_llrs = _as_float64(Span(llrs))
        var floating = viterbi_decode_soft(
            Span(float_llrs), Span(generators), 7
        )
        assert_equal(integer.bits, floating)
        assert_equal(integer.bits, payload)


def test_empty_unterminated_and_canonical_rtl_vector() raises:
    var empty = List[UInt8]()
    var empty_coded = fixed_wifi_bcc_encode(Span(empty), terminate=False)
    assert_equal(len(empty_coded), 0)
    var empty_result = fixed_wifi_bcc_viterbi_decode_hard(
        Span(empty_coded), terminate=False
    )
    assert_equal(len(empty_result.bits), 0)
    assert_equal(empty_result.final_state, 0)

    var payload = _static_payload()
    var coded = fixed_wifi_bcc_encode(Span(payload))
    var llr_format = QFormat(
        8, 2, ROUND_NEAREST_AWAY, OVERFLOW_SATURATE
    )
    var llrs = _static_soft_llrs()
    var hard = fixed_wifi_bcc_viterbi_decode_hard(
        Span(coded), metric_storage_bits=12
    )
    var soft = fixed_wifi_bcc_viterbi_decode_soft(
        Span(llrs), FixedWifiBCCViterbiConfig(llr_format, 16)
    )
    var checksum = fixed_wifi_bcc_result_checksum(
        Span(payload), Span(coded), Span(llrs), llr_format, hard, soft
    )
    assert_equal(checksum, UInt64(6028463685596740932))
    var vectors = fixed_wifi_bcc_canonical_rtl_vectors(
        Span(payload), Span(coded), Span(llrs), llr_format, hard, soft
    )
    # Independently computed FNV-1a pins every UTF-8 artifact byte.
    assert_equal(
        _oracle_fnv1a_text(StringSlice(vectors)),
        UInt64(17306098504996871604),
    )
    assert_true(vectors.startswith("MWDSP-WIFI-BCC-K7-R12-V1\n"))
    assert_true("generators_octal=133,171\n" in vectors)
    assert_true("initial_state=0\n" in vectors)
    assert_true("tail_zero_bits=6\n" in vectors)
    assert_true("metric_update=saturate-then-normalize\n" in vectors)
    assert_true("survivor_tie=lower-predecessor\n" in vectors)
    assert_true(
        "checksum_algorithm=fnv1a64-int64-little-endian\n" in vectors
    )
    assert_true("stage=quantized-llrs\n" in vectors)
    assert_true("stage=soft-survivor-predecessors\n" in vectors)
    assert_true("stage=soft-metric-normalization\n" in vectors)
    assert_true("stage=soft-decoded-bits\n" in vectors)
    assert_true(
        vectors.endswith(
            "MWDSP-WIFI-BCC-CHECKSUM-V1\n"
            "checksum=6028463685596740932\n"
        )
    )

    with assert_raises():
        _ = fixed_wifi_bcc_canonical_rtl_vectors(
            Span(payload),
            Span(coded),
            Span(llrs),
            QFormat(8, 2, ROUND_NEAREST_AWAY, OVERFLOW_WRAP),
            hard,
            soft,
        )
    var unterminated_soft = fixed_wifi_bcc_viterbi_decode_soft(
        Span(llrs),
        FixedWifiBCCViterbiConfig(llr_format, 16),
        terminate=False,
    )
    with assert_raises():
        _ = fixed_wifi_bcc_canonical_rtl_vectors(
            Span(payload),
            Span(coded),
            Span(llrs),
            llr_format,
            hard,
            unterminated_soft,
        )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
