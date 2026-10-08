"""Deterministic, edge, and Float64-differential CPU MIMO tests."""

from std.collections import Span
from std.testing import assert_equal, assert_raises, assert_true, TestSuite
from std.utils.numerics import inf, nan
from wireless_dsp.core import Complex32, Complex64
from wireless_dsp.mimo import (
    SmallComplexMatrix,
    gram_matrix,
    hermitian,
    matrix_vector_multiply,
    mmse_equalize,
    zf_equalize,
)
from wireless_dsp.backend.cpu.mimo_f32 import (
    MIMO_F32_RELATIVE_PIVOT,
    complex_matvec_f32,
    complex_matvec_f32_into,
    make_mimo_workspace_f32,
    mimo_gram_f32,
    mimo_gram_f32_into,
    mimo_gram_matched_f32_into,
    mimo_matched_filter_f32,
    mimo_matched_filter_f32_into,
    mimo_mmse_f32,
    mimo_mmse_f32_into,
    mimo_zf_f32,
    mimo_zf_f32_into,
)


def _as_matrix64(
    values: Span[Complex32, ...], size: Int
) raises -> SmallComplexMatrix:
    var result = SmallComplexMatrix(size, size)
    for row in range(size):
        for column in range(size):
            var value = values[row * size + column]
            result[row, column] = Complex64(
                Float64(value.re), Float64(value.im)
            )
    return result^


def _as_vector64(values: Span[Complex32, ...]) -> List[Complex64]:
    var result = List[Complex64](capacity=len(values))
    for index in range(len(values)):
        result.append(
            Complex64(Float64(values[index].re), Float64(values[index].im))
        )
    return result^


def _assert_complex_close(
    actual: Complex32,
    expected: Complex64,
    absolute_tolerance: Float64,
    relative_tolerance: Float64,
) raises:
    assert_true(
        abs(Float64(actual.re) - expected.re)
        <= absolute_tolerance + relative_tolerance * abs(expected.re)
    )
    assert_true(
        abs(Float64(actual.im) - expected.im)
        <= absolute_tolerance + relative_tolerance * abs(expected.im)
    )


def _assert_vector_close(
    actual: Span[Complex32, ...],
    expected: Span[Complex64, ...],
    absolute_tolerance: Float64,
    relative_tolerance: Float64,
) raises:
    assert_equal(len(actual), len(expected))
    for index in range(len(actual)):
        _assert_complex_close(
            Complex32(actual[index].re, actual[index].im),
            Complex64(expected[index].re, expected[index].im),
            absolute_tolerance,
            relative_tolerance,
        )


def _assert_matrix_close(
    actual: Span[Complex32, ...],
    expected: SmallComplexMatrix,
    absolute_tolerance: Float64,
    relative_tolerance: Float64,
) raises:
    assert_equal(len(actual), expected.rows * expected.columns)
    for row in range(expected.rows):
        for column in range(expected.columns):
            _assert_complex_close(
                Complex32(
                    actual[row * expected.columns + column].re,
                    actual[row * expected.columns + column].im,
                ),
                expected[row, column],
                absolute_tolerance,
                relative_tolerance,
            )


def _next_uniform_f32(mut state: UInt64) -> Float32:
    state = state * UInt64(6364136223846793005) + UInt64(1442695040888963407)
    return Float32(state >> 40) / Float32(1 << 24)


def _seeded_channel(size: Int, mut state: UInt64) -> List[Complex32]:
    var result = List[Complex32](capacity=size * size)
    for row in range(size):
        for column in range(size):
            var real = Float32(0.35) * (
                Float32(2.0) * _next_uniform_f32(state) - Float32(1.0)
            )
            var imag = Float32(0.25) * (
                Float32(2.0) * _next_uniform_f32(state) - Float32(1.0)
            )
            if row == column:
                real += Float32(1.5) + Float32(0.2) * Float32(row)
            result.append(Complex32(real, imag))
    return result^


def _seeded_vector(size: Int, mut state: UInt64) -> List[Complex32]:
    var result = List[Complex32](capacity=size)
    for _ in range(size):
        result.append(
            Complex32(
                Float32(2.0) * _next_uniform_f32(state) - Float32(1.0),
                Float32(2.0) * _next_uniform_f32(state) - Float32(1.0),
            )
        )
    return result^


def test_static_2x2_matvec_gram_and_matched_oracles() raises:
    # Expected values were calculated independently with scalar complex128
    # arithmetic, then copied as literals.  Binary-fraction entries are exact.
    var channel: List[Complex32] = [
        Complex32(1.0, 0.0),
        Complex32(0.5, 0.25),
        Complex32(-0.25, 0.5),
        Complex32(1.5, -0.25),
    ]
    var transmitted: List[Complex32] = [
        Complex32(1.0, -0.5), Complex32(-0.75, 0.25)
    ]
    var expected_product: List[Complex64] = [
        Complex64(0.5625, -0.5625),
        Complex64(-1.0625, 1.1875),
    ]
    var product_storage = List[Complex32](
        length=2, fill=Complex32(99.0, -99.0)
    )
    complex_matvec_f32_into(
        Span(channel), Span(transmitted), 2, product_storage
    )
    _assert_vector_close(
        Span(product_storage), Span(expected_product), 0.0, 0.0
    )
    var owning_product = complex_matvec_f32(
        Span(channel), Span(transmitted), 2
    )
    assert_equal(owning_product, product_storage)

    var expected_gram_values: List[Complex64] = [
        Complex64(1.3125, 0.0),
        Complex64(0.0, -0.4375),
        Complex64(0.0, 0.4375),
        Complex64(2.625, 0.0),
    ]
    var expected_gram = SmallComplexMatrix(2, 2)
    for index in range(4):
        expected_gram[index // 2, index % 2] = expected_gram_values[index]
    var gram_storage = List[Complex32](
        length=4, fill=Complex32(99.0, -99.0)
    )
    mimo_gram_f32_into(Span(channel), 2, gram_storage)
    _assert_matrix_close(Span(gram_storage), expected_gram, 0.0, 0.0)
    assert_equal(mimo_gram_f32(Span(channel), 2), gram_storage)
    assert_equal(gram_storage[2], gram_storage[1].conjugate())
    assert_equal(gram_storage[0].im, Float32(0.0))
    assert_equal(gram_storage[3].im, Float32(0.0))

    var observation: List[Complex32] = [
        Complex32(0.75, -0.3), Complex32(-1.2, 0.85)
    ]
    var expected_matched: List[Complex64] = [
        Complex64(1.475, 0.0875),
        Complex64(-1.7125, 0.6375),
    ]
    var matched_storage = List[Complex32](
        length=2, fill=Complex32(99.0, -99.0)
    )
    mimo_matched_filter_f32_into(
        Span(channel), Span(observation), 2, matched_storage
    )
    _assert_vector_close(
        Span(matched_storage), Span(expected_matched), 2.0e-7, 2.0e-7
    )
    var owning_matched = mimo_matched_filter_f32(
        Span(channel), Span(observation), 2
    )
    assert_equal(owning_matched, matched_storage)

    gram_storage[0] = Complex32(99.0, -99.0)
    matched_storage[0] = Complex32(99.0, -99.0)
    mimo_gram_matched_f32_into(
        Span(channel),
        Span(observation),
        2,
        gram_storage,
        matched_storage,
    )
    _assert_matrix_close(Span(gram_storage), expected_gram, 0.0, 0.0)
    _assert_vector_close(
        Span(matched_storage), Span(expected_matched), 2.0e-7, 2.0e-7
    )


def test_static_2x2_zf_mmse_and_workspace_reuse() raises:
    var channel: List[Complex32] = [
        Complex32(1.0, 0.0),
        Complex32(0.5, 0.25),
        Complex32(-0.25, 0.5),
        Complex32(1.5, -0.25),
    ]
    var observation: List[Complex32] = [
        Complex32(0.75, -0.3), Complex32(-1.2, 0.85)
    ]
    var expected_zf: List[Complex64] = [
        Complex64(1.10420168067, -0.159663865546),
        Complex64(-0.678991596639, 0.0588235294118),
    ]
    var expected_mmse: List[Complex64] = [
        Complex64(0.972556294072, -0.127690563281),
        Complex64(-0.632688594431, 0.0758521006596),
    ]
    var workspace = make_mimo_workspace_f32(2)
    var output = List[Complex32](
        length=2, fill=Complex32(0.0, 0.0)
    )
    mimo_zf_f32_into(Span(channel), Span(observation), workspace, output)
    _assert_vector_close(Span(output), Span(expected_zf), 2.0e-6, 3.0e-6)
    assert_true(workspace.last_matrix_scale > Float32(0.0))
    assert_true(workspace.last_minimum_pivot > workspace.last_pivot_threshold)
    var owning_zf = mimo_zf_f32(Span(channel), Span(observation), 2)
    assert_equal(owning_zf, output)

    mimo_mmse_f32_into(
        Span(channel), Span(observation), Float32(0.17), workspace, output
    )
    _assert_vector_close(
        Span(output), Span(expected_mmse), 2.0e-6, 3.0e-6
    )
    var owning_mmse = mimo_mmse_f32(
        Span(channel), Span(observation), 2, Float32(0.17)
    )
    assert_equal(owning_mmse, output)
    assert_equal(len(workspace.gram), 4)
    assert_equal(len(workspace.factor), 4)
    assert_equal(len(workspace.matched), 2)
    assert_equal(len(workspace.forward), 2)


def test_make_mimo_workspace_f32_exact_storage_and_int_edges() raises:
    for size in [2, 4]:
        var first = make_mimo_workspace_f32(size)
        var second = make_mimo_workspace_f32(size)
        assert_equal(first.size, size)
        assert_equal(len(first.gram), size * size)
        assert_equal(len(first.factor), size * size)
        assert_equal(len(first.matched), size)
        assert_equal(len(first.forward), size)
        assert_equal(first.gram, second.gram)
        assert_equal(first.factor, second.factor)
        assert_equal(first.matched, second.matched)
        assert_equal(first.forward, second.forward)
        for value in first.gram:
            assert_equal(value, Complex32(0.0, 0.0))
        for value in first.factor:
            assert_equal(value, Complex32(0.0, 0.0))
        for value in first.matched:
            assert_equal(value, Complex32(0.0, 0.0))
        for value in first.forward:
            assert_equal(value, Complex32(0.0, 0.0))
        assert_equal(first.last_matrix_scale, Float32(0.0))
        assert_equal(first.last_pivot_threshold, Float32(0.0))
        assert_equal(first.last_minimum_pivot, Float32(0.0))
        first.gram[0] = Complex32(1.0, 2.0)
        assert_equal(second.gram[0], Complex32(0.0, 0.0))
    with assert_raises():
        _ = make_mimo_workspace_f32(Int.MIN)
    with assert_raises():
        _ = make_mimo_workspace_f32(Int.MAX)


def test_seeded_2x2_4x4_float64_differential_properties() raises:
    var state = UInt64(0x4D494D4F20260821)
    for size in [2, 4]:
        var workspace = make_mimo_workspace_f32(size)
        var output = List[Complex32](
            length=size, fill=Complex32(0.0, 0.0)
        )
        var gram_output = List[Complex32](
            length=size * size, fill=Complex32(0.0, 0.0)
        )
        var matched_output = List[Complex32](
            length=size, fill=Complex32(0.0, 0.0)
        )
        for case_index in range(16):
            var channel = _seeded_channel(size, state)
            var observation = _seeded_vector(size, state)
            var channel64 = _as_matrix64(Span(channel), size)
            var observation64 = _as_vector64(Span(observation))

            complex_matvec_f32_into(
                Span(channel), Span(observation), size, output
            )
            var expected_product = matrix_vector_multiply(
                channel64, Span(observation64)
            )
            _assert_vector_close(
                Span(output), Span(expected_product), 3.0e-6, 4.0e-6
            )

            mimo_gram_matched_f32_into(
                Span(channel),
                Span(observation),
                size,
                gram_output,
                matched_output,
            )
            var expected_gram = gram_matrix(channel64)
            var expected_matched = matrix_vector_multiply(
                hermitian(channel64), Span(observation64)
            )
            _assert_matrix_close(
                Span(gram_output), expected_gram, 4.0e-6, 5.0e-6
            )
            _assert_vector_close(
                Span(matched_output), Span(expected_matched), 4.0e-6, 5.0e-6
            )

            mimo_zf_f32_into(
                Span(channel), Span(observation), workspace, output
            )
            var expected_zf = zf_equalize(channel64, Span(observation64))
            _assert_vector_close(
                Span(output), Span(expected_zf), 2.0e-5, 8.0e-5
            )

            var noise = Float32(0.03 + 0.01 * Float64(case_index % 7))
            mimo_mmse_f32_into(
                Span(channel), Span(observation), noise, workspace, output
            )
            var expected_mmse = mmse_equalize(
                channel64, Span(observation64), Float64(noise)
            )
            _assert_vector_close(
                Span(output), Span(expected_mmse), 2.0e-5, 8.0e-5
            )


def test_near_singular_and_scale_relative_decisions() raises:
    var symbols: List[Complex32] = [
        Complex32(0.75, -0.25), Complex32(-1.0, 0.5)
    ]
    for scale in [Float32(1.0e-14), Float32(1.0e14)]:
        var accepted: List[Complex32] = [
            Complex32(scale, 0.0),
            Complex32(0.0, 0.0),
            Complex32(0.0, 0.0),
            Complex32(Float32(0.01) * scale, 0.0),
        ]
        var observation = complex_matvec_f32(
            Span(accepted), Span(symbols), 2
        )
        var workspace = make_mimo_workspace_f32(2)
        var output = List[Complex32](
            length=2, fill=Complex32(0.0, 0.0)
        )
        mimo_zf_f32_into(
            Span(accepted), Span(observation), workspace, output
        )
        _assert_vector_close(
            Span(output),
            Span(_as_vector64(Span(symbols))),
            3.0e-4,
            3.0e-4,
        )
        assert_true(workspace.last_minimum_pivot > workspace.last_pivot_threshold)
        assert_true(
            abs(
                Float64(
                    workspace.last_pivot_threshold
                    / workspace.last_matrix_scale
                )
                - Float64(MIMO_F32_RELATIVE_PIVOT)
            )
            <= 2.0e-7
        )

        var rejected: List[Complex32] = [
            Complex32(scale, 0.0),
            Complex32(0.0, 0.0),
            Complex32(0.0, 0.0),
            Complex32(Float32(0.001) * scale, 0.0),
        ]
        var rejected_observation = complex_matvec_f32(
            Span(rejected), Span(symbols), 2
        )
        with assert_raises():
            _ = mimo_zf_f32(Span(rejected), Span(rejected_observation), 2)

        # Regularization lifts the rejected weak mode above the relative pivot.
        var noise = Float32(1.0e-4) * scale * scale
        var regularized = mimo_mmse_f32(
            Span(rejected), Span(rejected_observation), 2, noise
        )
        var rejected64 = _as_matrix64(Span(rejected), 2)
        var rejected_observation64 = _as_vector64(Span(rejected_observation))
        var expected = mmse_equalize(
            rejected64, Span(rejected_observation64), Float64(noise)
        )
        _assert_vector_close(Span(regularized), Span(expected), 2.0e-4, 3.0e-4)


def test_validation_nonfinite_overflow_and_zero_channel() raises:
    with assert_raises():
        _ = make_mimo_workspace_f32(3)
    var channel: List[Complex32] = [
        Complex32(1.0, 0.0),
        Complex32(0.0, 0.0),
        Complex32(0.0, 0.0),
        Complex32(1.0, 0.0),
    ]
    var observation: List[Complex32] = [
        Complex32(0.5, -0.25), Complex32(-1.0, 0.75)
    ]
    var short_matrix: List[Complex32] = [Complex32(1.0, 0.0)]
    var short_vector: List[Complex32] = [Complex32(1.0, 0.0)]
    var short_output: List[Complex32] = [Complex32(0.0, 0.0)]
    with assert_raises():
        _ = complex_matvec_f32(Span(short_matrix), Span(observation), 2)
    with assert_raises():
        _ = complex_matvec_f32(Span(channel), Span(short_vector), 2)
    with assert_raises():
        complex_matvec_f32_into(
            Span(channel), Span(observation), 2, short_output
        )

    var nonfinite_channel = channel.copy()
    nonfinite_channel[0] = Complex32(nan[DType.float32](), 0.0)
    with assert_raises():
        _ = mimo_zf_f32(Span(nonfinite_channel), Span(observation), 2)
    var nonfinite_observation = observation.copy()
    nonfinite_observation[0] = Complex32(inf[DType.float32](), 0.0)
    with assert_raises():
        _ = mimo_zf_f32(Span(channel), Span(nonfinite_observation), 2)

    for invalid_noise in [
        Float32(-1.0), nan[DType.float32](), inf[DType.float32]()
    ]:
        with assert_raises():
            _ = mimo_mmse_f32(
                Span(channel), Span(observation), 2, invalid_noise
            )

    var huge: List[Complex32] = [
        Complex32(Float32(3.0e38), 0.0),
        Complex32(0.0, 0.0),
        Complex32(0.0, 0.0),
        Complex32(Float32(3.0e38), 0.0),
    ]
    with assert_raises():
        _ = mimo_gram_f32(Span(huge), 2)

    var zero_channel = List[Complex32](
        length=4, fill=Complex32(0.0, 0.0)
    )
    with assert_raises():
        _ = mimo_zf_f32(Span(zero_channel), Span(observation), 2)
    var zero_mmse = mimo_mmse_f32(
        Span(zero_channel), Span(observation), 2, Float32(0.5)
    )
    assert_equal(
        zero_mmse,
        [Complex32(0.0, 0.0), Complex32(0.0, 0.0)],
    )

    var workspace = make_mimo_workspace_f32(2)
    workspace.forward.append(Complex32(0.0, 0.0))
    var output = List[Complex32](
        length=2, fill=Complex32(0.0, 0.0)
    )
    with assert_raises():
        mimo_zf_f32_into(Span(channel), Span(observation), workspace, output)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
