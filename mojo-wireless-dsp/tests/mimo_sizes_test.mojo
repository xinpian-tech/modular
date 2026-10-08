from std.testing import assert_true, TestSuite
from wireless_dsp.core import Complex64, Span
from wireless_dsp.mimo import (
    SmallComplexMatrix,
    matrix_multiply,
    matrix_vector_multiply,
    inverse,
    zf_equalize,
    mmse_equalize,
    hermitian,
    gram_matrix,
    cholesky,
    qr_decompose,
)


def _assert_complex_close(actual: Complex64, expected: Complex64, tolerance: Float64) raises:
    assert_true(abs(actual.re - expected.re) <= tolerance)
    assert_true(abs(actual.im - expected.im) <= tolerance)


def _well_conditioned_channel(size: Int) raises -> SmallComplexMatrix:
    var result = SmallComplexMatrix(size, size)
    for row in range(size):
        for column in range(size):
            if row == column:
                result[row, column] = Complex64(2.0 + 0.1 * Float64(row), 0.02 * Float64(row))
            else:
                result[row, column] = Complex64(
                    0.02 * Float64(1 + ((3 * row + column) % 5)),
                    0.01 * Float64(row - column),
                )
    return result^


def _assert_identity(matrix: SmallComplexMatrix, tolerance: Float64) raises:
    for row in range(matrix.rows):
        for column in range(matrix.columns):
            _assert_complex_close(
                matrix[row, column],
                Complex64(1.0 if row == column else 0.0),
                tolerance,
            )


def _exercise_square_size(size: Int) raises:
    var channel = _well_conditioned_channel(size)
    var product = matrix_multiply(channel, inverse(channel))
    _assert_identity(product, 2.0e-10)

    var transmitted = List[Complex64](capacity=size)
    for i in range(size):
        transmitted.append(Complex64(
            1.0 if i % 2 == 0 else -1.0,
            0.5 if (i // 2) % 2 == 0 else -0.5,
        ))
    var received = matrix_vector_multiply(channel, Span(transmitted))
    var zf = zf_equalize(channel, Span(received))
    var mmse = mmse_equalize(channel, Span(received), 0.0)
    for i in range(size):
        _assert_complex_close(zf[i], transmitted[i], 2.0e-10)
        _assert_complex_close(mmse[i], transmitted[i], 2.0e-10)

    var decomposition = qr_decompose(channel)
    var reconstructed = matrix_multiply(decomposition.q, decomposition.r)
    for row in range(size):
        for column in range(size):
            _assert_complex_close(reconstructed[row, column], channel[row, column], 2.0e-10)
    var qhq = matrix_multiply(hermitian(decomposition.q), decomposition.q)
    _assert_identity(qhq, 2.0e-10)

    var gram = gram_matrix(channel)
    var lower = cholesky(gram)
    reconstructed = matrix_multiply(lower, hermitian(lower))
    for row in range(size):
        for column in range(size):
            _assert_complex_close(reconstructed[row, column], gram[row, column], 5.0e-10)


def test_mimo_1x1_all_algorithms() raises:
    _exercise_square_size(1)


def test_mimo_4x4_all_algorithms() raises:
    _exercise_square_size(4)


def test_mimo_8x8_all_algorithms() raises:
    _exercise_square_size(8)


def test_tall_8x4_qr_reconstruction() raises:
    var matrix = SmallComplexMatrix(8, 4)
    for row in range(8):
        for column in range(4):
            var real = 1.0 if row == column else 0.03 * Float64(1 + row + 2 * column)
            matrix[row, column] = Complex64(real, 0.01 * Float64(row - column))
    var decomposition = qr_decompose(matrix)
    var reconstructed = matrix_multiply(decomposition.q, decomposition.r)
    for row in range(8):
        for column in range(4):
            _assert_complex_close(reconstructed[row, column], matrix[row, column], 2.0e-10)
    var qhq = matrix_multiply(hermitian(decomposition.q), decomposition.q)
    _assert_identity(qhq, 2.0e-10)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
