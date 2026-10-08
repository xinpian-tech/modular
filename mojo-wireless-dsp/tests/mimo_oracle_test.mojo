"""Independent complex MIMO numerical oracles.

The expected values in this file were generated offline with NumPy 2.3.2
complex128/OpenBLAS, then copied as Float64 literals.  Test execution has no
Python dependency.  The 4x4 fixtures use ``default_rng(20260821)`` (PCG64):

* H = 0.32 * (normal + 0.7j * normal) + diag(1.4, 1.6, 1.8, 2.0)
* y = 0.75 * (normal + 1j * normal)
* B = 0.38 * (normal + 1j * normal)
* A_hpd = B @ B.H + diag(0.8, 0.9, 1.0, 1.1)

NumPy QR columns were phase-normalized so every diagonal element of R is a
positive real number.  That makes the full-rank QR oracle unique and matches
the convention used by the readable modified Gram-Schmidt implementation.

The 8x8 fixture is a separate analytic oracle: ``H = Q D``, where ``Q`` is the
unitary eight-point DFT matrix and ``D`` is a positive nonuniform diagonal.
Its inverse, QR, ZF, and MMSE answers follow in closed form.  A second dense
positive-definite fixture is formed from an explicitly known lower-triangular
factor, so its Cholesky answer is also independent of the implementation.
"""

from std.math import cos, isfinite, sin, sqrt
from std.testing import assert_equal, assert_raises, assert_true, TestSuite
from std.utils.numerics import inf, nan
from wireless_dsp.core import Complex64, Span
from wireless_dsp.mimo import (
    SmallComplexMatrix,
    cholesky,
    hermitian,
    inverse,
    matrix_multiply,
    matrix_vector_multiply,
    mmse_equalize,
    qr_decompose,
    zf_equalize,
)


comptime _TWO_PI = 6.283185307179586476925286766559


def _square_matrix(
    size: Int, values: Span[Complex64, ...]
) raises -> SmallComplexMatrix:
    assert_true(len(values) == size * size)
    var result = SmallComplexMatrix(size, size)
    for row in range(size):
        for column in range(size):
            var value = values[row * size + column]
            result[row, column] = Complex64(value.re, value.im)
    return result^


def _scaled_copy(
    matrix: SmallComplexMatrix, scale: Float64
) raises -> SmallComplexMatrix:
    var result = SmallComplexMatrix(matrix.rows, matrix.columns)
    for row in range(matrix.rows):
        for column in range(matrix.columns):
            var value = matrix[row, column]
            result[row, column] = Complex64(
                value.re * scale, value.im * scale
            )
    return result^


def _scaled_vector_copy(
    vector: Span[Complex64, ...], scale: Float64
) -> List[Complex64]:
    var result = List[Complex64](capacity=len(vector))
    for i in range(len(vector)):
        result.append(Complex64(
            vector[i].re * scale, vector[i].im * scale
        ))
    return result^


def _assert_complex_close(
    actual: Complex64,
    expected: Complex64,
    relative_tolerance: Float64,
) raises:
    # Component-wise relative comparison with a unit absolute floor.  This is
    # also suitable for the large entries of the near-singular inverse oracle.
    assert_true(
        abs(actual.re - expected.re)
        <= relative_tolerance * (1.0 + abs(expected.re))
    )
    assert_true(
        abs(actual.im - expected.im)
        <= relative_tolerance * (1.0 + abs(expected.im))
    )


def _assert_matrix_close(
    actual: SmallComplexMatrix,
    expected: SmallComplexMatrix,
    relative_tolerance: Float64,
) raises:
    assert_true(actual.rows == expected.rows)
    assert_true(actual.columns == expected.columns)
    for row in range(actual.rows):
        for column in range(actual.columns):
            _assert_complex_close(
                actual[row, column],
                expected[row, column],
                relative_tolerance,
            )


def _assert_vector_close(
    actual: Span[Complex64, ...],
    expected: Span[Complex64, ...],
    relative_tolerance: Float64,
) raises:
    assert_true(len(actual) == len(expected))
    for i in range(len(actual)):
        _assert_complex_close(
            Complex64(actual[i].re, actual[i].im),
            Complex64(expected[i].re, expected[i].im),
            relative_tolerance,
        )


def _assert_identity_residual(
    matrix: SmallComplexMatrix, tolerance: Float64
) raises:
    assert_true(matrix.rows == matrix.columns)
    for row in range(matrix.rows):
        for column in range(matrix.columns):
            _assert_complex_close(
                matrix[row, column],
                Complex64(1.0 if row == column else 0.0, 0.0),
                tolerance,
            )


def _assert_linear_residual(
    matrix: SmallComplexMatrix,
    solution: Span[Complex64, ...],
    rhs: Span[Complex64, ...],
    tolerance: Float64,
) raises:
    var product = matrix_vector_multiply(matrix, solution)
    _assert_vector_close(Span(product), rhs, tolerance)


def _assert_mmse_normal_equation(
    channel: SmallComplexMatrix,
    solution: Span[Complex64, ...],
    received: Span[Complex64, ...],
    noise_variance: Float64,
    tolerance: Float64,
) raises:
    # Check H.H * (H*x - y) + sigma^2*x = 0 independently of the expected
    # vector comparison below.  This is a backward-error property, not an
    # oracle generator.
    var predicted = matrix_vector_multiply(channel, solution)
    for row in range(len(predicted)):
        predicted[row] = predicted[row] - Complex64(
            received[row].re, received[row].im
        )
    var normal = matrix_vector_multiply(hermitian(channel), Span(predicted))
    for column in range(len(normal)):
        normal[column] = normal[column] + Complex64(
            noise_variance * solution[column].re,
            noise_variance * solution[column].im,
        )
        _assert_complex_close(normal[column], Complex64(0.0, 0.0), tolerance)


def _h2() raises -> SmallComplexMatrix:
    var values: List[Complex64] = [
        Complex64(1.25, 0.2),
        Complex64(-0.35, 0.4),
        Complex64(0.15, -0.55),
        Complex64(0.95, 0.1),
    ]
    return _square_matrix(2, Span(values))


def _inverse2_oracle() raises -> SmallComplexMatrix:
    var values: List[Complex64] = [
        Complex64(0.95252918287937749, 0.040466926070038878),
        Complex64(0.32373540856031124, -0.42023346303501946),
        Complex64(-0.1151750972762646, 0.55719844357976656),
        Complex64(1.2575875486381323, 0.12140077821011674),
    ]
    return _square_matrix(2, Span(values))


def _q2_oracle() raises -> SmallComplexMatrix:
    var values: List[Complex64] = [
        Complex64(0.90035300758202474, 0.14405648121312398),
        Complex64(-0.083120466770490883, -0.4021233392410235),
        Complex64(0.10804236090984295, -0.39615532333609088),
        Complex64(0.90758563716968421, -0.087613464974301225),
    ]
    return _square_matrix(2, Span(values))


def _r2_oracle() raises -> SmallComplexMatrix:
    var values: List[Complex64] = [
        Complex64(1.3883443376914819, 0.0),
        Complex64(-0.19447624963771737, 0.79771276471767394),
        Complex64(0.0, 0.0),
        Complex64(0.72168783648703205, 0.0),
    ]
    return _square_matrix(2, Span(values))


def _hpd2() raises -> SmallComplexMatrix:
    var values: List[Complex64] = [
        Complex64(3.2, 0.0),
        Complex64(0.45, 0.65),
        Complex64(0.45, -0.65),
        Complex64(2.1, 0.0),
    ]
    return _square_matrix(2, Span(values))


def _cholesky2_oracle() raises -> SmallComplexMatrix:
    var values: List[Complex64] = [
        Complex64(1.7888543819998317, 0.0),
        Complex64(0.0, 0.0),
        Complex64(0.25155764746872639, -0.36336104634371585),
        Complex64(1.3801041627355524, 0.0),
    ]
    return _square_matrix(2, Span(values))


def _h4_seeded() raises -> SmallComplexMatrix:
    var values: List[Complex64] = [
        Complex64(2.2060940533747191, -0.068066689752044551),
        Complex64(-0.18984348520999322, 0.19782228710410998),
        Complex64(0.71235668046418255, 0.12980613506483926),
        Complex64(-0.053331153429008106, -0.25832198944760559),
        Complex64(0.25834631340915748, 0.25262695205683439),
        Complex64(1.0798824370269244, 0.11159553022391377),
        Complex64(-0.66804417934848725, -0.10203705896328727),
        Complex64(-0.0060793077083505795, -0.21648392039512002),
        Complex64(0.42025483378069517, -0.21110703926549046),
        Complex64(0.36744528906023399, -0.25761298482685591),
        Complex64(2.3132631853172061, 0.11198490451613785),
        Complex64(-0.39197565231925596, -0.46927177969514694),
        Complex64(-0.18482638024858222, -0.21160932557438653),
        Complex64(-0.1888036118789285, 0.0080853947517727284),
        Complex64(-0.010506160807639426, 0.17949605263419746),
        Complex64(2.4355586034920904, -0.14194241867668003),
    ]
    return _square_matrix(4, Span(values))


def _inverse4_oracle() raises -> SmallComplexMatrix:
    var values: List[Complex64] = [
        Complex64(0.44918994397235817, 0.014312279834118032),
        Complex64(0.1184915621899849, -0.093993391686134548),
        Complex64(-0.098917884727166727, -0.047239065501367486),
        Complex64(0.0082810235450016846, 0.032074172470829283),
        Complex64(-0.15621454091192505, -0.064990518240363712),
        Complex64(0.78612164583212263, 0.0066297868355153083),
        Complex64(0.28277077797296829, 0.04956885448518672),
        Complex64(0.034023111729592763, 0.11634242045456344),
        Complex64(-0.053386528075313841, 0.045150863968499745),
        Complex64(-0.12017034528271622, 0.14050120100507082),
        Complex64(0.41588310267193496, 0.0011264893621497896),
        Complex64(0.044012906735047347, 0.067872435678784634),
        Complex64(0.021228690863891442, 0.040960198820735372),
        Complex64(0.087047293533630901, 0.015601767595331519),
        Complex64(0.022808627522981798, -0.038590956207908388),
        Complex64(0.41470139501503711, 0.033276936359809862),
    ]
    return _square_matrix(4, Span(values))


def _q4_oracle() raises -> SmallComplexMatrix:
    var values: List[Complex64] = [
        Complex64(0.95807019355783596, -0.029560238615314243),
        Complex64(-0.19675417350633628, 0.12685693034886203),
        Complex64(-0.096290657779760952, -0.075158255152472084),
        Complex64(0.049349950318549274, -0.095219426850264591),
        Complex64(0.112195534961094, 0.10971171083334876),
        Complex64(0.88535451201836124, 0.082681902133148771),
        Complex64(-0.28352007005232166, -0.24907640177352264),
        Complex64(0.20235725503712956, -0.036269144463391745),
        Complex64(0.18250972995823442, -0.091680298789217463),
        Complex64(0.29030937202391854, -0.21448417518689694),
        Complex64(0.90395205329877004, 0.0036067636270962749),
        Complex64(0.053022800242855536, 0.089711691776761901),
        Complex64(-0.080267042843651493, -0.091898433433318133),
        Complex64(-0.15504891074480157, 0.013529520501517751),
        Complex64(0.01038411366758886, 0.15939419261777543),
        Complex64(0.96404876646612103, -0.077358286794002903),
    ]
    return _square_matrix(4, Span(values))


def _r4_oracle() raises -> SmallComplexMatrix:
    var values: List[Complex64] = [
        Complex64(2.3026434474308104, 0.0),
        Complex64(0.050762314022550131, 0.046631459431221517),
        Complex64(0.9887784902051433, 0.42441086743658119),
        Complex64(-0.27885901563552101, -0.15905443037583744),
        Complex64(0.0, 0.0),
        Complex64(1.2190632504731311, 0.0),
        Complex64(-0.071984431518265168, 0.34996900176668433),
        Complex64(-0.43825240869408427, -0.36482150383519851),
        Complex64(0.0, 0.0),
        Complex64(0.0, 0.0),
        Complex64(2.2564541005537984, 0.0),
        Complex64(-0.27315846446437791, -0.73174422663954419),
        Complex64(0.0, 0.0),
        Complex64(0.0, 0.0),
        Complex64(0.0, 0.0),
        Complex64(2.3246817542804856, 0.0),
    ]
    return _square_matrix(4, Span(values))


def _hpd4_seeded() raises -> SmallComplexMatrix:
    var values: List[Complex64] = [
        Complex64(1.9407252073208576, 0.0),
        Complex64(0.21286057918539053, 0.49815665979697249),
        Complex64(0.26916356305445355, -0.18652690703036512),
        Complex64(-0.20118568533376582, 0.52116684630860977),
        Complex64(0.21286057918539053, -0.49815665979697249),
        Complex64(2.103477929112004, 0.0),
        Complex64(0.047318726522987645, -0.0551549231277179),
        Complex64(0.73453048502372309, 0.2355241470662254),
        Complex64(0.26916356305445355, 0.18652690703036512),
        Complex64(0.047318726522987645, 0.0551549231277179),
        Complex64(1.7611688015333173, 0.0),
        Complex64(0.033903355088095694, 0.24951401188627526),
        Complex64(-0.20118568533376582, -0.52116684630860977),
        Complex64(0.73453048502372309, -0.2355241470662254),
        Complex64(0.033903355088095694, -0.24951401188627526),
        Complex64(2.6518777214279132, 0.0),
    ]
    return _square_matrix(4, Span(values))


def _cholesky4_oracle() raises -> SmallComplexMatrix:
    var values: List[Complex64] = [
        Complex64(1.3930991376498865, 0.0),
        Complex64(0.0, 0.0),
        Complex64(0.0, 0.0),
        Complex64(0.0, 0.0),
        Complex64(0.1527964330984222, -0.35758880781259172),
        Complex64(1.3972334893179352, 0.0),
        Complex64(0.0, 0.0),
        Complex64(0.0, 0.0),
        Complex64(0.1932120663777912, 0.13389349113016469),
        Complex64(0.047003901866141708, -0.024615783593834237),
        Complex64(1.3050268688344073, 0.0),
        Complex64(0.0, 0.0),
        Complex64(-0.14441591405559237, -0.37410607201135848),
        Complex64(0.4457526834631661, -0.090693903413367583),
        Complex64(0.067977147079481895, -0.15576548244887789),
        Complex64(1.5017529074721545, 0.0),
    ]
    return _square_matrix(4, Span(values))


def _dft8_entry(row: Int, column: Int) -> Complex64:
    var angle = -_TWO_PI * Float64(row * column) / 8.0
    var scale = 1.0 / sqrt(8.0)
    return Complex64(scale * cos(angle), scale * sin(angle))


def _dft8_column_scale(column: Int) -> Float64:
    return 1.0 + 0.125 * Float64(column)


def _h8_analytic() raises -> SmallComplexMatrix:
    var result = SmallComplexMatrix(8, 8)
    for row in range(8):
        for column in range(8):
            var value = _dft8_entry(row, column)
            var scale = _dft8_column_scale(column)
            result[row, column] = Complex64(
                scale * value.re, scale * value.im
            )
    return result^


def _inverse8_analytic() raises -> SmallComplexMatrix:
    # (Q D)^-1 = D^-1 Q.H.
    var result = SmallComplexMatrix(8, 8)
    for row in range(8):
        for column in range(8):
            var q_value = _dft8_entry(column, row)
            var scale = _dft8_column_scale(row)
            result[row, column] = Complex64(
                q_value.re / scale, -q_value.im / scale
            )
    return result^


def _q8_analytic() raises -> SmallComplexMatrix:
    var result = SmallComplexMatrix(8, 8)
    for row in range(8):
        for column in range(8):
            result[row, column] = _dft8_entry(row, column)
    return result^


def _r8_analytic() raises -> SmallComplexMatrix:
    var result = SmallComplexMatrix(8, 8)
    for diagonal in range(8):
        result[diagonal, diagonal] = Complex64(
            _dft8_column_scale(diagonal), 0.0
        )
    return result^


def _dense_lower8_oracle() raises -> SmallComplexMatrix:
    var result = SmallComplexMatrix(8, 8)
    for row in range(8):
        for column in range(row + 1):
            if row == column:
                result[row, column] = Complex64(
                    1.0 + 0.125 * Float64(row), 0.0
                )
            else:
                result[row, column] = Complex64(
                    0.025 * Float64(row + column + 1),
                    0.0125 * Float64(row - column),
                )
    return result^


def _hpd8_analytic() raises -> SmallComplexMatrix:
    # Construct A = L L.H directly from the known closed-form factor rather
    # than using matrix_multiply, keeping the input oracle independent.
    var lower = _dense_lower8_oracle()
    var result = SmallComplexMatrix(8, 8)
    for row in range(8):
        for column in range(8):
            var accumulator = Complex64(0.0, 0.0)
            for k in range(min(row, column) + 1):
                accumulator = accumulator + (
                    lower[row, k] * lower[column, k].conjugate()
                )
            result[row, column] = accumulator
    return result^


def test_2x2_inverse_zf_mmse_against_numpy_oracles() raises:
    var channel = _h2()
    var calculated_inverse = inverse(channel)
    _assert_matrix_close(calculated_inverse, _inverse2_oracle(), 2.0e-12)
    _assert_identity_residual(
        matrix_multiply(channel, calculated_inverse), 2.0e-12
    )

    var received: List[Complex64] = [
        Complex64(0.75, -0.3), Complex64(-1.2, 0.85)
    ]
    var expected_zf: List[Complex64] = [
        Complex64(0.69525291828793789, 0.52404669260700398),
        Complex64(-1.5315175097276268, 1.3757198443579768),
    ]
    var zf = zf_equalize(channel, Span(received))
    _assert_vector_close(Span(zf), Span(expected_zf), 3.0e-12)
    _assert_linear_residual(channel, Span(zf), Span(received), 3.0e-12)

    var expected_mmse: List[Complex64] = [
        Complex64(0.47138271891150796, 0.22148364584041158),
        Complex64(-1.1395749477378381, 0.96289886122447355),
    ]
    var mmse = mmse_equalize(channel, Span(received), 0.17)
    _assert_vector_close(Span(mmse), Span(expected_mmse), 3.0e-12)
    _assert_mmse_normal_equation(
        channel, Span(mmse), Span(received), 0.17, 4.0e-12
    )


def test_2x2_qr_and_cholesky_against_numpy_oracles() raises:
    var channel = _h2()
    var decomposition = qr_decompose(channel)
    _assert_matrix_close(decomposition.q, _q2_oracle(), 2.0e-12)
    _assert_matrix_close(decomposition.r, _r2_oracle(), 2.0e-12)
    _assert_matrix_close(
        matrix_multiply(decomposition.q, decomposition.r), channel, 3.0e-12
    )
    _assert_identity_residual(
        matrix_multiply(hermitian(decomposition.q), decomposition.q),
        3.0e-12,
    )

    var positive = _hpd2()
    var lower = cholesky(positive)
    _assert_matrix_close(lower, _cholesky2_oracle(), 2.0e-12)
    _assert_matrix_close(
        matrix_multiply(lower, hermitian(lower)), positive, 3.0e-12
    )


def test_seeded_4x4_inverse_zf_mmse_against_numpy_oracles() raises:
    # Fixed-seed random inputs make this a repeatable numerical property test,
    # while the expected answers remain independent hard-coded oracles.
    var channel = _h4_seeded()
    var calculated_inverse = inverse(channel)
    _assert_matrix_close(calculated_inverse, _inverse4_oracle(), 5.0e-12)
    _assert_identity_residual(
        matrix_multiply(channel, calculated_inverse), 8.0e-12
    )

    var received: List[Complex64] = [
        Complex64(-0.0031207971805499589, 1.2095946868803458),
        Complex64(0.30554240103777169, -0.12963389498984576),
        Complex64(-1.2800948393083156, 1.1193284002998203),
        Complex64(0.90868614418347271, 0.280135156908212),
    ]
    var expected_zf: List[Complex64] = [
        Complex64(0.18334562798251877, 0.48042766282878596),
        Complex64(-0.098979872458691234, 0.07967455656242653),
        Complex64(-0.5856013164570445, 0.53186231603917677),
        Complex64(0.36051778639600079, 0.24037416482549243),
    ]
    var zf = zf_equalize(channel, Span(received))
    _assert_vector_close(Span(zf), Span(expected_zf), 8.0e-12)
    _assert_linear_residual(channel, Span(zf), Span(received), 1.0e-11)

    var expected_mmse: List[Complex64] = [
        Complex64(0.15480972623158909, 0.45945979988265628),
        Complex64(-0.08642020022774892, 0.047380751622185628),
        Complex64(-0.54731202912771182, 0.50935867091278875),
        Complex64(0.34407538305594237, 0.21589080938364993),
    ]
    var mmse = mmse_equalize(channel, Span(received), 0.23)
    _assert_vector_close(Span(mmse), Span(expected_mmse), 8.0e-12)
    _assert_mmse_normal_equation(
        channel, Span(mmse), Span(received), 0.23, 1.0e-11
    )


def test_seeded_4x4_qr_and_cholesky_against_numpy_oracles() raises:
    var channel = _h4_seeded()
    var decomposition = qr_decompose(channel)
    _assert_matrix_close(decomposition.q, _q4_oracle(), 8.0e-12)
    _assert_matrix_close(decomposition.r, _r4_oracle(), 8.0e-12)
    _assert_matrix_close(
        matrix_multiply(decomposition.q, decomposition.r), channel, 1.0e-11
    )
    _assert_identity_residual(
        matrix_multiply(hermitian(decomposition.q), decomposition.q),
        1.0e-11,
    )

    var positive = _hpd4_seeded()
    var lower = cholesky(positive)
    _assert_matrix_close(lower, _cholesky4_oracle(), 8.0e-12)
    _assert_matrix_close(
        matrix_multiply(lower, hermitian(lower)), positive, 1.0e-11
    )


def test_analytic_dense_8x8_all_algorithms() raises:
    var channel = _h8_analytic()
    var calculated_inverse = inverse(channel)
    _assert_matrix_close(calculated_inverse, _inverse8_analytic(), 4.0e-11)
    _assert_identity_residual(
        matrix_multiply(channel, calculated_inverse), 5.0e-11
    )

    var transmitted: List[Complex64] = [
        Complex64(0.75, -0.25),
        Complex64(-0.5, 0.125),
        Complex64(0.25, 0.625),
        Complex64(-0.875, -0.375),
        Complex64(0.0625, -0.75),
        Complex64(0.5, 0.5),
        Complex64(-0.3125, 0.8125),
        Complex64(1.0, -0.0625),
    ]
    # Closed-form y = Q D x; this does not call the matrix-vector kernel under
    # test and therefore remains an analytic forward oracle.
    var received = List[Complex64](capacity=8)
    for row in range(8):
        var accumulator = Complex64(0.0, 0.0)
        for column in range(8):
            var q_value = _dft8_entry(row, column)
            var scaled = Complex64(
                transmitted[column].re * _dft8_column_scale(column),
                transmitted[column].im * _dft8_column_scale(column),
            )
            accumulator = accumulator + q_value * scaled
        received.append(accumulator)

    var zf = zf_equalize(channel, Span(received))
    _assert_vector_close(Span(zf), Span(transmitted), 5.0e-11)

    var noise_variance = 0.1875
    var expected_mmse = List[Complex64](capacity=8)
    for column in range(8):
        var diagonal = _dft8_column_scale(column)
        var shrinkage = (
            diagonal * diagonal
            / (diagonal * diagonal + noise_variance)
        )
        expected_mmse.append(Complex64(
            shrinkage * transmitted[column].re,
            shrinkage * transmitted[column].im,
        ))
    var mmse = mmse_equalize(channel, Span(received), noise_variance)
    _assert_vector_close(Span(mmse), Span(expected_mmse), 5.0e-11)
    _assert_mmse_normal_equation(
        channel, Span(mmse), Span(received), noise_variance, 7.0e-11
    )

    var decomposition = qr_decompose(channel)
    _assert_matrix_close(decomposition.q, _q8_analytic(), 5.0e-11)
    _assert_matrix_close(decomposition.r, _r8_analytic(), 5.0e-11)
    _assert_matrix_close(
        matrix_multiply(decomposition.q, decomposition.r),
        channel,
        7.0e-11,
    )

    var positive = _hpd8_analytic()
    var expected_lower = _dense_lower8_oracle()
    var lower = cholesky(positive)
    _assert_matrix_close(lower, expected_lower, 5.0e-11)
    _assert_matrix_close(
        matrix_multiply(lower, hermitian(lower)), positive, 7.0e-11
    )


def test_near_singular_inverse_and_qr_boundaries() raises:
    # kappa_2 = 5.3625e11.  The second pivot magnitude is 2e-12, just above
    # the implementation's relative 1e-12 pivot-magnitude boundary for this
    # unit-scaled fixture.
    var values: List[Complex64] = [
        Complex64(1.0, 0.0),
        Complex64(0.25, -0.1),
        Complex64(0.0, 0.0),
        Complex64(2.0e-12, 0.0),
    ]
    var near_singular = _square_matrix(2, Span(values))
    var expected_values: List[Complex64] = [
        Complex64(1.0, 0.0),
        Complex64(-1.25e11, 5.0e10),
        Complex64(0.0, 0.0),
        Complex64(5.0e11, 0.0),
    ]
    var calculated_inverse = inverse(near_singular)
    _assert_matrix_close(
        calculated_inverse,
        _square_matrix(2, Span(expected_values)),
        2.0e-12,
    )
    # A backward residual is the meaningful accuracy measure for this very
    # ill-conditioned system; a forward absolute tolerance would be misleading.
    _assert_identity_residual(
        matrix_multiply(near_singular, calculated_inverse), 2.0e-5
    )
    var decomposition = qr_decompose(near_singular)
    _assert_matrix_close(
        matrix_multiply(decomposition.q, decomposition.r),
        near_singular,
        2.0e-12,
    )

    # A 5e-13 final pivot has squared magnitude 2.5e-25, below the 1e-24
    # relative algorithm boundary.  Both inverse and QR reject it.
    values[3] = Complex64(5.0e-13, 0.0)
    var rejected = _square_matrix(2, Span(values))
    with assert_raises():
        _ = inverse(rejected)
    with assert_raises():
        _ = qr_decompose(rejected)


def test_inverse_and_qr_singularity_decisions_are_scale_invariant() raises:
    var base_values: List[Complex64] = [
        Complex64(2.0, 0.25),
        Complex64(-0.5, 0.75),
        Complex64(0.25, -0.5),
        Complex64(1.5, 0.0),
    ]
    var base = _square_matrix(2, Span(base_values))
    var base_inverse = inverse(base)
    for scale in [1.0e-14, 1.0e14]:
        var scaled_values = List[Complex64](capacity=4)
        for value in base_values:
            scaled_values.append(
                Complex64(value.re * scale, value.im * scale)
            )
        var scaled = _square_matrix(2, Span(scaled_values))
        var scaled_inverse = inverse(scaled)
        for row in range(2):
            for column in range(2):
                _assert_complex_close(
                    scaled_inverse[row, column],
                    Complex64(
                        base_inverse[row, column].re / scale,
                        base_inverse[row, column].im / scale,
                    ),
                    2.0e-12,
                )
        var decomposition = qr_decompose(scaled)
        _assert_matrix_close(
            matrix_multiply(decomposition.q, decomposition.r),
            scaled,
            2.0e-12,
        )

        var dependent_values: List[Complex64] = [
            Complex64(scale, 0.0),
            Complex64(2.0 * scale, 0.0),
            Complex64(-0.5 * scale, 0.0),
            Complex64(-scale, 0.0),
        ]
        var dependent = _square_matrix(2, Span(dependent_values))
        with assert_raises():
            _ = inverse(dependent)
        with assert_raises():
            _ = qr_decompose(dependent)


def test_cholesky_rejects_nonhermitian_and_is_scale_invariant() raises:
    var polluted_values: List[Complex64] = [
        Complex64(1.0), Complex64(999.0),
        Complex64(0.0), Complex64(1.0),
    ]
    with assert_raises():
        _ = cholesky(_square_matrix(2, Span(polluted_values)))

    var nonfinite_values: List[Complex64] = [
        Complex64(inf[DType.float64]()), Complex64(0.0),
        Complex64(0.0), Complex64(1.0),
    ]
    var nonfinite = _square_matrix(2, Span(nonfinite_values))
    with assert_raises():
        _ = inverse(nonfinite)
    with assert_raises():
        _ = qr_decompose(nonfinite)
    with assert_raises():
        _ = cholesky(nonfinite)

    var identity_values: List[Complex64] = [
        Complex64(1.0), Complex64(0.0),
        Complex64(0.0), Complex64(1.0),
    ]
    var identity = _square_matrix(2, Span(identity_values))
    var received: List[Complex64] = [Complex64(1.0), Complex64(-1.0)]
    with assert_raises():
        _ = mmse_equalize(
            identity, Span(received), nan[DType.float64]()
        )
    with assert_raises():
        _ = mmse_equalize(
            identity, Span(received), inf[DType.float64]()
        )

    var base_values: List[Complex64] = [
        Complex64(4.0), Complex64(1.0, 1.0),
        Complex64(1.0, -1.0), Complex64(3.0),
    ]
    for scale in [1.0e-14, 1.0e14]:
        var scaled_values = List[Complex64](capacity=4)
        for value in base_values:
            scaled_values.append(
                Complex64(value.re * scale, value.im * scale)
            )
        var scaled = _square_matrix(2, Span(scaled_values))
        var lower = cholesky(scaled)
        var reconstructed = matrix_multiply(lower, hermitian(lower))
        for row in range(2):
            for column in range(2):
                _assert_complex_close(
                    Complex64(
                        reconstructed[row, column].re / scale,
                        reconstructed[row, column].im / scale,
                    ),
                    base_values[row * 2 + column],
                    2.0e-12,
                )


def test_decompositions_are_stable_near_float64_scale_extremes() raises:
    # These scales are far enough into the Float64 range that every old raw
    # square either overflowed or underflowed.  The reference results remain
    # representable, so rejecting them would be a numerical implementation
    # error rather than a limitation of the public result type.
    for scalar_scale in [1.0e-308, 1.0e308]:
        var edge_scalar = SmallComplexMatrix(1, 1)
        edge_scalar[0, 0] = Complex64(scalar_scale)
        var edge_inverse = inverse(edge_scalar)[0, 0]
        assert_true(isfinite(edge_inverse.re))
        assert_true(
            abs(edge_inverse.re * scalar_scale - 1.0) <= 3.0e-15
        )
        var edge_qr = qr_decompose(edge_scalar)
        assert_true(abs(edge_qr.q[0, 0].re - 1.0) <= 2.0e-15)
        assert_true(
            abs(edge_qr.r[0, 0].re / scalar_scale - 1.0) <= 2.0e-15
        )
        var edge_lower = cholesky(edge_scalar)[0, 0]
        assert_true(isfinite(edge_lower.re))
        assert_true(
            abs(edge_lower.re / sqrt(scalar_scale) - 1.0) <= 2.0e-15
        )

    # The exact reciprocal has two representable 1e308 components even though
    # dividing lhs by the rhs component before applying its phase would
    # overflow.  This guards the common-scale Smith division path.
    var rotated_subnormal = SmallComplexMatrix(1, 1)
    rotated_subnormal[0, 0] = Complex64(5.0e-309, 5.0e-309)
    var rotated_inverse = inverse(rotated_subnormal)[0, 0]
    assert_true(isfinite(rotated_inverse.re))
    assert_true(isfinite(rotated_inverse.im))
    assert_true(abs(rotated_inverse.re / 1.0e308 - 1.0) <= 4.0e-15)
    assert_true(abs(rotated_inverse.im / -1.0e308 - 1.0) <= 4.0e-15)

    for scale in [1.0e-300, 1.0e-200, 1.0e200, 1.0e300]:
        var scalar = SmallComplexMatrix(1, 1)
        scalar[0, 0] = Complex64(scale, 0.0)
        var scalar_inverse = inverse(scalar)[0, 0]
        assert_true(isfinite(scalar_inverse.re))
        assert_true(abs(scalar_inverse.re * scale - 1.0) <= 3.0e-15)
        assert_equal(scalar_inverse.im, 0.0)

        # A complex 1x1 fixture exercises the stable complex division path.
        scalar[0, 0] = Complex64(scale, -0.5 * scale)
        scalar_inverse = inverse(scalar)[0, 0]
        assert_true(isfinite(scalar_inverse.re))
        assert_true(isfinite(scalar_inverse.im))
        assert_true(abs(scalar_inverse.re * scale - 0.8) <= 3.0e-15)
        assert_true(abs(scalar_inverse.im * scale - 0.4) <= 3.0e-15)

        var scaled_channel = _scaled_copy(_h2(), scale)
        var calculated_inverse = inverse(scaled_channel)
        var expected_inverse = _inverse2_oracle()
        for row in range(2):
            for column in range(2):
                _assert_complex_close(
                    Complex64(
                        calculated_inverse[row, column].re * scale,
                        calculated_inverse[row, column].im * scale,
                    ),
                    expected_inverse[row, column],
                    4.0e-12,
                )
        _assert_identity_residual(
            matrix_multiply(scaled_channel, calculated_inverse), 5.0e-12
        )

        var decomposition = qr_decompose(scaled_channel)
        _assert_matrix_close(decomposition.q, _q2_oracle(), 4.0e-12)
        var expected_r = _r2_oracle()
        for row in range(2):
            for column in range(2):
                _assert_complex_close(
                    Complex64(
                        decomposition.r[row, column].re / scale,
                        decomposition.r[row, column].im / scale,
                    ),
                    expected_r[row, column],
                    4.0e-12,
                )

        var scaled_positive = _scaled_copy(_hpd2(), scale)
        var lower = cholesky(scaled_positive)
        var expected_lower = _cholesky2_oracle()
        var root_scale = sqrt(scale)
        for row in range(2):
            for column in range(2):
                _assert_complex_close(
                    Complex64(
                        lower[row, column].re / root_scale,
                        lower[row, column].im / root_scale,
                    ),
                    expected_lower[row, column],
                    5.0e-12,
                )
        var reconstructed = matrix_multiply(lower, hermitian(lower))
        for row in range(2):
            for column in range(2):
                var expected = _hpd2()[row, column]
                _assert_complex_close(
                    Complex64(
                        reconstructed[row, column].re / scale,
                        reconstructed[row, column].im / scale,
                    ),
                    expected,
                    6.0e-12,
                )

        var singular_values: List[Complex64] = [
            Complex64(scale), Complex64(0.0),
            Complex64(0.0), Complex64(0.0),
        ]
        var singular = _square_matrix(2, Span(singular_values))
        with assert_raises():
            _ = inverse(singular)
        with assert_raises():
            _ = qr_decompose(singular)

        var indefinite_values: List[Complex64] = [
            Complex64(scale), Complex64(0.0),
            Complex64(0.0), Complex64(-scale),
        ]
        with assert_raises():
            _ = cholesky(_square_matrix(2, Span(indefinite_values)))


def test_zf_and_mmse_are_stable_at_extreme_equation_scales() raises:
    var received: List[Complex64] = [
        Complex64(0.75, -0.3), Complex64(-1.2, 0.85)
    ]
    var expected_zf: List[Complex64] = [
        Complex64(0.69525291828793789, 0.52404669260700398),
        Complex64(-1.5315175097276268, 1.3757198443579768),
    ]
    for scale in [1.0e-200, 1.0e200]:
        var channel = _scaled_copy(_h2(), scale)
        var observation = _scaled_vector_copy(Span(received), scale)
        var zf = zf_equalize(channel, Span(observation))
        _assert_vector_close(Span(zf), Span(expected_zf), 5.0e-12)
        var zero_noise_mmse = mmse_equalize(
            channel, Span(observation), 0.0
        )
        _assert_vector_close(
            Span(zero_noise_mmse), Span(expected_zf), 5.0e-12
        )

    var expected_mmse: List[Complex64] = [
        Complex64(0.47138271891150796, 0.22148364584041158),
        Complex64(-1.1395749477378381, 0.96289886122447355),
    ]
    # Scaling H and y by s and the variance by s**2 leaves the MMSE answer
    # unchanged.  s=1e+/-150 puts the power term near both Float64 extremes.
    for scale in [1.0e-150, 1.0e150]:
        var channel = _scaled_copy(_h2(), scale)
        var observation = _scaled_vector_copy(Span(received), scale)
        var scaled_noise_variance = 0.17 * scale * scale
        var mmse = mmse_equalize(
            channel, Span(observation), scaled_noise_variance
        )
        _assert_vector_close(Span(mmse), Span(expected_mmse), 6.0e-12)

    # The channel and observation need not share a scale.  This expected
    # value is checked after rescaling so a tiny but valid result cannot pass
    # through the unit absolute floor in the general oracle helper.
    var scalar_channel = SmallComplexMatrix(1, 1)
    scalar_channel[0, 0] = Complex64(1.0e200)
    var ordinary_observation: List[Complex64] = [Complex64(2.0, -3.0)]
    var tiny_solution = zf_equalize(
        scalar_channel, Span(ordinary_observation)
    )[0]
    assert_true(isfinite(tiny_solution.re))
    assert_true(isfinite(tiny_solution.im))
    assert_true(abs(tiny_solution.re * 1.0e200 - 2.0) <= 2.0e-15)
    assert_true(abs(tiny_solution.im * 1.0e200 + 3.0) <= 2.0e-15)

    # Here H / sqrt(noise) underflows, but H*y/noise is still a representable
    # 1e-308.  This specifically guards the combined-exponent MMSE rescaling.
    scalar_channel[0, 0] = Complex64(1.0e-308)
    var huge_observation: List[Complex64] = [Complex64(1.0e308)]
    var noise_dominated = mmse_equalize(
        scalar_channel, Span(huge_observation), 1.0e308
    )[0]
    assert_true(noise_dominated.re > 0.0)
    assert_true(isfinite(noise_dominated.re))
    assert_true(
        abs(noise_dominated.re / 1.0e-308 - 1.0) <= 5.0e-15
    )
    assert_equal(noise_dominated.im, 0.0)

    scalar_channel[0, 0] = Complex64(0.0)
    var regularized_zero_channel = mmse_equalize(
        scalar_channel, Span(ordinary_observation), 1.0e-300
    )[0]
    assert_equal(regularized_zero_channel, Complex64(0.0))
    with assert_raises():
        _ = mmse_equalize(
            scalar_channel, Span(ordinary_observation), 0.0
        )


def test_extreme_mimo_paths_reject_nonfinite_or_unrepresentable_results() raises:
    # Individual 2e308 products overflow, but the exact dot product cancels.
    # Scaling and compensated accumulation must preserve the finite zero.
    var cancelling_lhs = SmallComplexMatrix(1, 2)
    cancelling_lhs[0, 0] = Complex64(1.0e308)
    cancelling_lhs[0, 1] = Complex64(1.0e308)
    var cancelling_rhs = SmallComplexMatrix(2, 1)
    cancelling_rhs[0, 0] = Complex64(2.0)
    cancelling_rhs[1, 0] = Complex64(-2.0)
    assert_equal(
        matrix_multiply(cancelling_lhs, cancelling_rhs)[0, 0],
        Complex64(0.0),
    )
    var cancelling_vector: List[Complex64] = [
        Complex64(2.0), Complex64(-2.0)
    ]
    assert_equal(
        matrix_vector_multiply(cancelling_lhs, Span(cancelling_vector))[0],
        Complex64(0.0),
    )

    var tiny_scalar = SmallComplexMatrix(1, 1)
    tiny_scalar[0, 0] = Complex64(1.0e-320)
    with assert_raises():
        _ = inverse(tiny_scalar)

    var finite_scalar = SmallComplexMatrix(1, 1)
    finite_scalar[0, 0] = Complex64(1.0e-308)
    var huge_observation: List[Complex64] = [Complex64(1.0e308)]
    with assert_raises():
        _ = zf_equalize(finite_scalar, Span(huge_observation))
    with assert_raises():
        _ = mmse_equalize(finite_scalar, Span(huge_observation), 0.0)

    var identity_values: List[Complex64] = [
        Complex64(1.0), Complex64(0.0),
        Complex64(0.0), Complex64(1.0),
    ]
    var identity = _square_matrix(2, Span(identity_values))
    var nonfinite_observation: List[Complex64] = [
        Complex64(nan[DType.float64]()), Complex64(0.0)
    ]
    with assert_raises():
        _ = zf_equalize(identity, Span(nonfinite_observation))
    with assert_raises():
        _ = mmse_equalize(identity, Span(nonfinite_observation), 1.0)


def test_matrix_indices_reject_each_out_of_range_dimension() raises:
    var matrix = SmallComplexMatrix(2, 2)
    matrix[0, 0] = Complex64(1.0)
    matrix[1, 0] = Complex64(2.0)

    # Column 2 previously flattened to index 2 and silently aliased [1, 0].
    with assert_raises():
        _ = matrix[0, 2]
    with assert_raises():
        matrix[0, 2] = Complex64(9.0)
    with assert_raises():
        _ = matrix[2, 0]
    with assert_raises():
        _ = matrix[-1, 0]
    with assert_raises():
        matrix[0, -1] = Complex64(9.0)

    assert_equal(matrix[0, 0], Complex64(1.0))
    assert_equal(matrix[1, 0], Complex64(2.0))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
