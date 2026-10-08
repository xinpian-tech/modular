"""Bit-exact, differential, and NR composition tests for fixed LDPC."""

from std.collections import Span
from std.testing import assert_equal, assert_raises, assert_true, TestSuite
from wireless_dsp.numerics import (
    QFormat,
    ROUND_NEAREST_AWAY,
    OVERFLOW_SATURATE,
    OVERFLOW_WRAP,
    quantize_raw,
    dequantize_raw,
)
from wireless_dsp.fec import ldpc_decode_min_sum, syndrome_ok
from wireless_dsp.wireless.nr import (
    nr_ldpc_encode,
    nr_ldpc_rate_match,
    nr_ldpc_rate_recover,
    nr_ldpc_syndrome_ok,
)
from wireless_dsp.backend.fixed_ldpc_reference import (
    FIXED_LDPC_FLOODING,
    FIXED_LDPC_LAYERED,
    FixedLDPCConfig,
    fixed_ldpc_default_config,
    fixed_ldpc_decode_min_sum_raw,
    fixed_nr_ldpc_rate_recover_raw,
    fixed_nr_ldpc_decode_raw,
)


def _toy_offsets() -> List[Int]:
    return [0, 3, 6, 9, 12]


def _toy_columns() -> List[Int]:
    return [0, 1, 3, 1, 2, 4, 2, 3, 5, 0, 4, 5]


def _config(schedule: Int, max_iterations: Int = 20) raises -> FixedLDPCConfig:
    var llr = QFormat(12, 4, ROUND_NEAREST_AWAY, OVERFLOW_SATURATE)
    var norm = QFormat(16, 15, ROUND_NEAREST_AWAY, OVERFLOW_SATURATE)
    return FixedLDPCConfig(
        llr,
        norm,
        quantize_raw(0.75, norm),
        Int64(0),
        quantize_raw(50.0, llr),
        max_iterations,
        schedule,
    )


def test_fixed_ldpc_default_config_static_table_and_mutation_edges() raises:
    """Pin the public builder against the independently reviewed Q table."""
    var config = fixed_ldpc_default_config()
    assert_equal(config.llr_format.storage_bits, 16)
    assert_equal(config.llr_format.fraction_bits, 6)
    assert_equal(config.llr_format.rounding_mode, ROUND_NEAREST_AWAY)
    assert_equal(config.llr_format.overflow_mode, OVERFLOW_SATURATE)
    assert_equal(config.normalization_format.storage_bits, 16)
    assert_equal(config.normalization_format.fraction_bits, 15)
    assert_equal(config.normalization_raw, Int64(24576))
    assert_equal(config.offset_raw, Int64(0))
    assert_equal(config.clip_raw, Int64(3200))
    assert_equal(config.max_iterations, 20)
    assert_equal(config.schedule, FIXED_LDPC_LAYERED)

    var flooding = fixed_ldpc_default_config(
        max_iterations=1, schedule=FIXED_LDPC_FLOODING
    )
    assert_equal(flooding.max_iterations, 1)
    assert_equal(flooding.schedule, FIXED_LDPC_FLOODING)
    with assert_raises():
        _ = fixed_ldpc_default_config(max_iterations=0)
    with assert_raises():
        _ = fixed_ldpc_default_config(schedule=Int.MIN)
    with assert_raises():
        _ = fixed_ldpc_default_config(schedule=Int.MAX)
    config.max_iterations = Int.MIN
    with assert_raises():
        config.validate()


def test_fixed_flooding_and_layered_correct_toy_code() raises:
    var offsets = _toy_offsets()
    var columns = _toy_columns()
    var raw: List[Int64] = [96, -8, 96, 96, -4, 96]
    var flooding = fixed_ldpc_decode_min_sum_raw(
        Span(raw), Span(offsets), Span(columns),
        _config(FIXED_LDPC_FLOODING),
    )
    var layered = fixed_ldpc_decode_min_sum_raw(
        Span(raw), Span(offsets), Span(columns),
        _config(FIXED_LDPC_LAYERED),
    )
    assert_true(flooding.converged and layered.converged)
    assert_equal(flooding.syndrome_weight, 0)
    assert_equal(layered.syndrome_weight, 0)
    assert_equal(
        flooding.bits,
        [UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0)],
    )
    assert_equal(layered.bits, flooding.bits)
    assert_true(flooding.iterations <= 20 and layered.iterations <= 20)
    assert_equal(len(flooding.posterior_raw), 6)
    assert_equal(len(flooding.variable_to_check_raw), 12)
    assert_equal(len(flooding.check_to_variable_raw), 12)


def test_fixed_seeded_decisions_match_float64_reference() raises:
    var offsets = _toy_offsets()
    var columns = _toy_columns()
    var config = _config(FIXED_LDPC_LAYERED)
    var state = UInt64(20260822)
    for case_index in range(64):
        var raw = List[Int64](capacity=6)
        var floating = List[Float64](capacity=6)
        for index in range(6):
            state = state * UInt64(6364136223846793005) + UInt64(1)
            var magnitude = Int64(48 + Int((state >> 60) & UInt64(7)) * 8)
            # At most one deliberately unreliable position keeps the oracle
            # away from algorithm-dependent marginal trapping sets.
            var value = (
                -Int64(4 + case_index % 4)
                if index == case_index % 6
                else magnitude
            )
            raw.append(value)
            floating.append(Float64(value) / 16.0)
        var fixed = fixed_ldpc_decode_min_sum_raw(
            Span(raw), Span(offsets), Span(columns), config
        )
        var reference = ldpc_decode_min_sum(
            Span(floating), Span(offsets), Span(columns),
            max_iterations=20, normalization=0.75, clip=50.0,
        )
        assert_true(fixed.converged and reference.converged)
        assert_equal(fixed.bits, reference.bits)
        assert_true(syndrome_ok(Span(fixed.bits), Span(offsets), Span(columns)))


def test_registered_saturation_and_numeric_contract() raises:
    var offsets: List[Int] = [0, 2, 4]
    var columns: List[Int] = [0, 1, 0, 1]
    var llr = QFormat(6, 0, ROUND_NEAREST_AWAY, OVERFLOW_SATURATE)
    var norm = QFormat(8, 7, ROUND_NEAREST_AWAY, OVERFLOW_SATURATE)
    var config = FixedLDPCConfig(
        llr, norm, Int64(127), Int64(0), Int64(31), 2,
        FIXED_LDPC_FLOODING,
    )
    var raw: List[Int64] = [31, 31]
    var result = fixed_ldpc_decode_min_sum_raw(
        Span(raw), Span(offsets), Span(columns), config
    )
    assert_true(result.converged)
    assert_true(result.saturation_count > 0)
    assert_equal(result.posterior_raw, [Int64(31), Int64(31)])

    with assert_raises():
        _ = FixedLDPCConfig(
            QFormat(6, 0, ROUND_NEAREST_AWAY, OVERFLOW_WRAP),
            norm, Int64(127), Int64(0), Int64(31), 2,
        )
    with assert_raises():
        _ = FixedLDPCConfig(llr, norm, Int64(0), Int64(0), Int64(31), 2)
    with assert_raises():
        _ = FixedLDPCConfig(llr, norm, Int64(127), Int64(-1), Int64(31), 2)
    var bad_raw: List[Int64] = [32, 0]
    with assert_raises():
        _ = fixed_ldpc_decode_min_sum_raw(
            Span(bad_raw), Span(offsets), Span(columns), config
        )
    var duplicate_columns: List[Int] = [0, 0]
    var one_row: List[Int] = [0, 2]
    with assert_raises():
        _ = fixed_ldpc_decode_min_sum_raw(
            Span(raw), Span(one_row), Span(duplicate_columns), config
        )

    var mutated_schedule = config
    mutated_schedule.schedule = 99
    with assert_raises():
        _ = fixed_ldpc_decode_min_sum_raw(
            Span(raw), Span(offsets), Span(columns), mutated_schedule
        )
    var mutated_iterations = config
    mutated_iterations.max_iterations = 0
    with assert_raises():
        _ = fixed_ldpc_decode_min_sum_raw(
            Span(raw), Span(offsets), Span(columns), mutated_iterations
        )
    var mutated_normalization = config
    mutated_normalization.normalization_raw = 0
    with assert_raises():
        _ = fixed_ldpc_decode_min_sum_raw(
            Span(raw), Span(offsets), Span(columns), mutated_normalization
        )
    var mutated_format = config
    mutated_format.llr_format.overflow_mode = OVERFLOW_WRAP
    with assert_raises():
        _ = fixed_ldpc_decode_min_sum_raw(
            Span(raw), Span(offsets), Span(columns), mutated_format
        )


def test_fixed_nr_rate_recovery_matches_float64_and_decodes() raises:
    comptime base_graph = 2
    comptime lifting_size = 2
    comptime information_bits = 20
    comptime encoded_bits = 100
    comptime output_bits = 200
    var information = List[UInt8](capacity=information_bits)
    for index in range(information_bits):
        information.append(UInt8((index * 5 + index // 3) & 1))
    var encoded = nr_ldpc_encode(Span(information), base_graph, lifting_size)
    assert_equal(len(encoded), encoded_bits)
    var null_mask = List[UInt8](length=encoded_bits, fill=UInt8(0))
    var matched = nr_ldpc_rate_match(
        Span(encoded), Span(null_mask), base_graph, lifting_size, 1,
        output_bits, 2,
    )
    var llr_format = QFormat(
        16, 6, ROUND_NEAREST_AWAY, OVERFLOW_SATURATE
    )
    var received_raw = List[Int64](capacity=output_bits)
    var received_float = List[Float64](capacity=output_bits)
    for bit in matched:
        var value = Int64(640 if bit == 0 else -640)
        received_raw.append(value)
        received_float.append(Float64(value) / 64.0)
    var fixed_recovered = fixed_nr_ldpc_rate_recover_raw(
        Span(received_raw), Span(null_mask), base_graph, lifting_size, 1, 2,
        llr_format, Int64(3200),
    )
    var float_recovered = nr_ldpc_rate_recover(
        Span(received_float), Span(null_mask), base_graph, lifting_size, 1, 2,
        filler_llr=50.0,
    )
    assert_equal(len(fixed_recovered.llrs_raw), len(float_recovered))
    for index in range(len(float_recovered)):
        assert_equal(
            dequantize_raw(fixed_recovered.llrs_raw[index], llr_format),
            float_recovered[index],
        )
    var config = fixed_ldpc_default_config(max_iterations=30)
    var decoded = fixed_nr_ldpc_decode_raw(
        Span(fixed_recovered.llrs_raw), Span(null_mask), base_graph,
        lifting_size, config,
    )
    assert_true(decoded.converged)
    assert_equal(decoded.bits, information)
    assert_true(
        nr_ldpc_syndrome_ok(Span(decoded.full_bits), base_graph, lifting_size)
    )
    assert_equal(decoded.syndrome_weight, 0)


def test_fixed_nr_rate_recovery_rejects_invalid_domains() raises:
    var llr_format = QFormat(
        8, 2, ROUND_NEAREST_AWAY, OVERFLOW_SATURATE
    )
    var received: List[Int64] = [4, -4]
    var null_mask = List[UInt8](length=100, fill=UInt8(0))
    with assert_raises():
        _ = fixed_nr_ldpc_rate_recover_raw(
            Span(received), Span(null_mask), 2, 2, 0, 3,
            llr_format, Int64(20),
        )
    null_mask[0] = UInt8(2)
    with assert_raises():
        _ = fixed_nr_ldpc_rate_recover_raw(
            Span(received), Span(null_mask), 2, 2, 0, 2,
            llr_format, Int64(20),
        )
    null_mask[0] = UInt8(0)
    var bad_received: List[Int64] = [Int64(128), Int64(0)]
    with assert_raises():
        _ = fixed_nr_ldpc_rate_recover_raw(
            Span(bad_received), Span(null_mask), 2, 2, 0, 2,
            llr_format, Int64(20),
        )
    var decoder_config = fixed_ldpc_default_config()
    with assert_raises():
        _ = fixed_nr_ldpc_decode_raw(
            Span(received), Span(null_mask), 2, 2, decoder_config
        )
    var recovered = List[Int64](length=100, fill=Int64(0))
    decoder_config.schedule = 99
    with assert_raises():
        _ = fixed_nr_ldpc_decode_raw(
            Span(recovered), Span(null_mask), 2, 2, decoder_config
        )
    var invalid_mask = null_mask.copy()
    invalid_mask[0] = UInt8(2)
    var full_llrs = List[Int64](length=100, fill=Int64(4))
    with assert_raises():
        _ = fixed_nr_ldpc_decode_raw(
            Span(full_llrs), Span(invalid_mask), 2, 2, decoder_config
        )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
