from std.testing import assert_equal, assert_true, assert_raises, TestSuite
from std.utils.numerics import inf, nan
from wireless_dsp.core import Complex64, Span
from wireless_dsp.mimo import (
    SmallComplexMatrix,
    matrix_multiply,
    inverse,
    matrix_vector_multiply,
    zf_equalize,
    mmse_equalize,
    hermitian,
    cholesky,
    qr_decompose,
)
from wireless_dsp.fec import (
    check_node_min_sum,
    check_node_normalized_min_sum,
    check_node_offset_min_sum,
    variable_node_sum,
    syndrome_ok,
    cyclic_shift,
    ldpc_decode_min_sum,
    convolutional_encode,
    viterbi_decode_hard,
    viterbi_decode_soft,
    puncture_bits,
    depuncture_llrs,
    polar_transform,
    polar_encode,
    polar_decode_sc,
)


def assert_complex_close(actual: Complex64, expected: Complex64, tolerance: Float64) raises:
    assert_true(abs(actual.re - expected.re) <= tolerance)
    assert_true(abs(actual.im - expected.im) <= tolerance)


def test_matrix_inverse_and_identity() raises:
    var matrix = SmallComplexMatrix(2, 2)
    matrix[0, 0] = Complex64(2.0, 1.0)
    matrix[0, 1] = Complex64(1.0, -1.0)
    matrix[1, 0] = Complex64(0.5, 0.25)
    matrix[1, 1] = Complex64(3.0, 0.0)
    var identity = matrix_multiply(matrix, inverse(matrix))
    for row in range(2):
        for column in range(2):
            assert_complex_close(
                identity[row, column],
                Complex64(1.0 if row == column else 0.0),
                1.0e-10,
            )


def test_zf_and_mmse_equalization() raises:
    var channel = SmallComplexMatrix(2, 2)
    channel[0, 0] = Complex64(1.0, 0.0)
    channel[0, 1] = Complex64(0.25, 0.1)
    channel[1, 0] = Complex64(-0.1, 0.2)
    channel[1, 1] = Complex64(0.8, -0.1)
    var transmitted: List[Complex64] = [Complex64(1.0, 1.0), Complex64(-1.0, 1.0)]
    var received = matrix_vector_multiply(channel, Span(transmitted))
    var recovered = zf_equalize(channel, Span(received))
    for i in range(2):
        assert_complex_close(recovered[i], transmitted[i], 1.0e-10)
    var mmse = mmse_equalize(channel, Span(received), 0.0)
    for i in range(2):
        assert_complex_close(mmse[i], transmitted[i], 1.0e-10)


def test_singular_inverse_rejected() raises:
    var singular = SmallComplexMatrix(2, 2)
    singular[0, 0] = Complex64(1.0)
    singular[0, 1] = Complex64(2.0)
    singular[1, 0] = Complex64(2.0)
    singular[1, 1] = Complex64(4.0)
    with assert_raises():
        _ = inverse(singular)


def test_cholesky_and_qr_reconstruction() raises:
    var positive = SmallComplexMatrix(2, 2)
    positive[0, 0] = Complex64(4.0)
    positive[0, 1] = Complex64(1.0, 1.0)
    positive[1, 0] = Complex64(1.0, -1.0)
    positive[1, 1] = Complex64(3.0)
    var lower = cholesky(positive)
    var reconstructed = matrix_multiply(lower, hermitian(lower))
    for row in range(2):
        for column in range(2):
            assert_complex_close(reconstructed[row, column], positive[row, column], 1.0e-10)

    var decomposition = qr_decompose(positive)
    reconstructed = matrix_multiply(decomposition.q, decomposition.r)
    for row in range(2):
        for column in range(2):
            assert_complex_close(reconstructed[row, column], positive[row, column], 1.0e-10)
    var qhq = matrix_multiply(hermitian(decomposition.q), decomposition.q)
    for row in range(2):
        for column in range(2):
            assert_complex_close(qhq[row, column], Complex64(1.0 if row == column else 0.0), 1.0e-10)


def test_ldpc_check_and_variable_nodes() raises:
    var incoming: List[Float64] = [-2.0, 3.0, -4.0]
    var plain = check_node_min_sum(Span(incoming))
    assert_equal(plain, [-3.0, 2.0, -2.0])
    var normalized = check_node_normalized_min_sum(Span(incoming), 0.5)
    assert_equal(normalized, [-1.5, 1.0, -1.0])
    var offset = check_node_offset_min_sum(Span(incoming), 1.0)
    assert_equal(offset, [-2.0, 1.0, -1.0])
    var messages: List[Float64] = [4.0, 5.0]
    assert_equal(variable_node_sum(3.0, Span(messages), 10.0), 10.0)
    var cancelling_messages: List[Float64] = [1.0e308, -1.0e308]
    assert_true(
        abs(
            variable_node_sum(
                1.0, Span(cancelling_messages), 50.0
            ) - 1.0
        ) <= 1.0e-12
    )
    with assert_raises():
        _ = check_node_normalized_min_sum(
            Span(incoming), nan[DType.float64]()
        )
    with assert_raises():
        _ = check_node_offset_min_sum(
            Span(incoming), inf[DType.float64]()
        )
    var invalid_messages: List[Float64] = [nan[DType.float64]()]
    with assert_raises():
        _ = variable_node_sum(1.0, Span(invalid_messages), 10.0)

    var huge: List[Float64] = [1.5e308, -1.25e308, 1.0e308]
    assert_equal(
        check_node_min_sum(Span(huge)),
        [-1.0e308, 1.0e308, -1.25e308],
    )


def test_ldpc_syndrome_and_cyclic_shift() raises:
    # H = [[1,1,0], [0,1,1]]
    var offsets: List[Int] = [0, 2, 4]
    var columns: List[Int] = [0, 1, 1, 2]
    var valid: List[UInt8] = [1, 1, 1]
    var invalid: List[UInt8] = [1, 0, 1]
    assert_true(syndrome_ok(Span(valid), Span(offsets), Span(columns)))
    assert_true(not syndrome_ok(Span(invalid), Span(offsets), Span(columns)))
    var values: List[Float64] = [1.0, 2.0, 3.0, 4.0]
    assert_equal(cyclic_shift(Span(values), 1), [4.0, 1.0, 2.0, 3.0])
    var llrs: List[Float64] = [5.0, -1.0, 5.0]
    var decoded = ldpc_decode_min_sum(
        Span(llrs), Span(offsets), Span(columns), max_iterations=10
    )
    assert_true(decoded.converged)
    assert_equal(decoded.bits, [UInt8(0), UInt8(0), UInt8(0)])


def test_convolutional_viterbi_roundtrip_and_error_correction() raises:
    # IEEE 802.11 mother code: K=7, generators 133 and 171 (octal).
    var generators: List[Int] = [0o133, 0o171]
    var bits: List[UInt8] = [1, 0, 1, 1, 0, 0, 1, 1, 1, 0]
    var encoded = convolutional_encode(Span(bits), Span(generators), 7)
    assert_equal(viterbi_decode_hard(Span(encoded), Span(generators), 7), bits)
    encoded[7] ^= 1
    assert_equal(viterbi_decode_hard(Span(encoded), Span(generators), 7), bits)
    var pattern: List[UInt8] = [1, 1, 1, 0, 0, 1]  # rate 3/4
    var punctured = puncture_bits(Span(encoded), Span(pattern))
    var punctured_llrs = List[Float64](capacity=len(punctured))
    for bit in punctured:
        punctured_llrs.append(8.0 if bit == 0 else -8.0)
    var mother_llrs = depuncture_llrs(Span(punctured_llrs), Span(pattern), len(encoded))
    assert_equal(viterbi_decode_soft(Span(mother_llrs), Span(generators), 7), bits)

    var huge_encoded = convolutional_encode(Span(bits), Span(generators), 7)
    var huge_llrs = List[Float64](capacity=len(huge_encoded))
    for bit in huge_encoded:
        huge_llrs.append(1.0e308 if bit == 0 else -1.0e308)
    assert_equal(
        viterbi_decode_soft(Span(huge_llrs), Span(generators), 7), bits
    )


def test_polar_transform_and_encoder() raises:
    var basis: List[UInt8] = [1, 0, 0, 0]
    polar_transform(basis)
    assert_equal(basis, [1, 0, 0, 0])
    var information: List[UInt8] = [1, 0]
    var frozen: List[UInt8] = [1, 1, 0, 0]
    var encoded = polar_encode(Span(information), Span(frozen))
    assert_equal(encoded, [1, 0, 1, 0])
    var llrs = List[Float64](capacity=4)
    for i in range(4):
        llrs.append(20.0 if encoded[i] == 0 else -20.0)
    assert_equal(polar_decode_sc(Span(llrs), Span(frozen)), information)

    var huge_llrs = List[Float64](capacity=4)
    for i in range(4):
        huge_llrs.append(1.0e308 if encoded[i] == 0 else -1.0e308)
    assert_equal(
        polar_decode_sc(Span(huge_llrs), Span(frozen)), information
    )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
