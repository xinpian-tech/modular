"""Readable small dense complex matrix and linear MIMO references."""

from std.collections import Span
from std.math import isfinite, sqrt
from wireless_dsp.core import Complex64


comptime _RELATIVE_SINGULAR_POWER = 1.0e-24
comptime _RELATIVE_MATRIX_TOLERANCE = 1.0e-12


struct SmallComplexMatrix(Movable):
    """Row-major matrix restricted to the intended 1/2/4/8 antenna sizes."""

    var rows: Int
    var columns: Int
    var values: List[Complex64]

    def __init__(out self, rows: Int, columns: Int) raises:
        if not _supported_size(rows) or not _supported_size(columns):
            raise Error("small matrix dimensions must be 1, 2, 4, or 8")
        self.rows = rows
        self.columns = columns
        self.values = List[Complex64](
            length=rows * columns, fill=Complex64(0.0, 0.0)
        )

    def __getitem__(self, row: Int, column: Int) raises -> Complex64:
        if row < 0 or row >= self.rows or column < 0 or column >= self.columns:
            raise Error("matrix index is outside its row or column dimension")
        return self.values[row * self.columns + column]

    def __setitem__(
        mut self, row: Int, column: Int, value: Complex64
    ) raises:
        if row < 0 or row >= self.rows or column < 0 or column >= self.columns:
            raise Error("matrix index is outside its row or column dimension")
        self.values[row * self.columns + column] = value

    def copy(self) raises -> Self:
        var result = Self(self.rows, self.columns)
        for i in range(len(self.values)):
            result.values[i] = self.values[i]
        return result^


struct QRDecomposition(Movable):
    var q: SmallComplexMatrix
    var r: SmallComplexMatrix

    def __init__(out self, var q: SmallComplexMatrix, var r: SmallComplexMatrix):
        self.q = q^
        self.r = r^


def _supported_size(size: Int) -> Bool:
    return size == 1 or size == 2 or size == 4 or size == 8


def _matrix_component_scale(matrix: SmallComplexMatrix) raises -> Float64:
    """Return the largest finite component magnitude in ``matrix``."""
    var scale = 0.0
    for value in matrix.values:
        if not isfinite(value.re) or not isfinite(value.im):
            raise Error("matrix input must be finite")
        scale = max(scale, abs(value.re), abs(value.im))
    return scale


def _vector_component_scale(vector: Span[Complex64, ...]) raises -> Float64:
    """Return the largest finite component magnitude in ``vector``."""
    var scale = 0.0
    for i in range(len(vector)):
        var value = vector[i]
        if not isfinite(value.re) or not isfinite(value.im):
            raise Error("vector input must be finite")
        scale = max(scale, abs(value.re), abs(value.im))
    return scale


def _scaled_matrix(
    matrix: SmallComplexMatrix, divisor: Float64
) raises -> SmallComplexMatrix:
    if not isfinite(divisor) or divisor <= 0.0:
        raise Error("matrix scale must be finite and positive")
    var result = SmallComplexMatrix(matrix.rows, matrix.columns)
    for row in range(matrix.rows):
        for column in range(matrix.columns):
            var value = matrix[row, column]
            result[row, column] = Complex64(
                value.re / divisor, value.im / divisor
            )
    return result^


def _scaled_vector(
    vector: Span[Complex64, ...], divisor: Float64
) raises -> List[Complex64]:
    if not isfinite(divisor) or divisor <= 0.0:
        raise Error("vector scale must be finite and positive")
    var result = List[Complex64](capacity=len(vector))
    for i in range(len(vector)):
        var value = vector[i]
        result.append(Complex64(value.re / divisor, value.im / divisor))
    return result^


def _matrix_magnitude_scale(matrix: SmallComplexMatrix) -> Float64:
    """Return max(abs(entry)) when every component is already bounded."""
    var scale = 0.0
    for value in matrix.values:
        scale = max(
            scale, sqrt(value.re * value.re + value.im * value.im)
        )
    return scale


def _scaled_ratio_component(
    value: Float64, numerator: Float64, denominator: Float64
) raises -> Float64:
    """Evaluate ``value * numerator / denominator`` without a false ratio.

    Computing the scale ratio first may overflow or underflow even when its
    product with ``value`` is representable.  The alternate ordering covers
    exactly those two cases.  A non-finite final component is a genuinely
    unrepresentable public result and is rejected instead of being returned.
    """
    if (
        not isfinite(value)
        or not isfinite(numerator)
        or not isfinite(denominator)
        or numerator < 0.0
        or denominator <= 0.0
    ):
        raise Error("matrix result scaling requires finite values")
    if value == 0.0 or numerator == 0.0:
        return 0.0
    var ratio = numerator / denominator
    var result: Float64
    if isfinite(ratio) and ratio != 0.0:
        result = value * ratio
    else:
        result = (value * numerator) / denominator
    if not isfinite(result):
        raise Error("matrix result is not representable")
    return result


def _scaled_ratio_complex(
    value: Complex64, numerator: Float64, denominator: Float64
) raises -> Complex64:
    return Complex64(
        _scaled_ratio_component(value.re, numerator, denominator),
        _scaled_ratio_component(value.im, numerator, denominator),
    )


def _scaled_product_ratio_component(
    value: Float64,
    first_numerator: Float64,
    second_numerator: Float64,
    denominator: Float64,
) raises -> Float64:
    """Evaluate a three-factor ratio without losing its combined exponent."""
    if (
        not isfinite(value)
        or not isfinite(first_numerator)
        or not isfinite(second_numerator)
        or not isfinite(denominator)
        or first_numerator < 0.0
        or second_numerator < 0.0
        or denominator <= 0.0
    ):
        raise Error("matrix result scaling requires finite values")
    if value == 0.0 or first_numerator == 0.0 or second_numerator == 0.0:
        return 0.0

    # Combining binary exponents separately avoids both false overflow and
    # false underflow in expressions such as tiny_H * huge_y / huge_noise.
    # Explicit normalization keeps subnormal Float64 inputs in the same path
    # as normal inputs instead of dropping their exponent contribution.
    var value_mantissa = value
    var value_exponent = 0
    while abs(value_mantissa) < 0.5:
        value_mantissa *= 2.0
        value_exponent -= 1
    while abs(value_mantissa) >= 1.0:
        value_mantissa *= 0.5
        value_exponent += 1

    var first_mantissa = first_numerator
    var first_exponent = 0
    while first_mantissa < 0.5:
        first_mantissa *= 2.0
        first_exponent -= 1
    while first_mantissa >= 1.0:
        first_mantissa *= 0.5
        first_exponent += 1

    var second_mantissa = second_numerator
    var second_exponent = 0
    while second_mantissa < 0.5:
        second_mantissa *= 2.0
        second_exponent -= 1
    while second_mantissa >= 1.0:
        second_mantissa *= 0.5
        second_exponent += 1

    var denominator_mantissa = denominator
    var denominator_exponent = 0
    while denominator_mantissa < 0.5:
        denominator_mantissa *= 2.0
        denominator_exponent -= 1
    while denominator_mantissa >= 1.0:
        denominator_mantissa *= 0.5
        denominator_exponent += 1

    var result = (
        value_mantissa
        * first_mantissa
        * second_mantissa
        / denominator_mantissa
    )
    var result_exponent = (
        value_exponent
        + first_exponent
        + second_exponent
        - denominator_exponent
    )
    while abs(result) < 0.5:
        result *= 2.0
        result_exponent -= 1
    while abs(result) >= 1.0:
        result *= 0.5
        result_exponent += 1
    while result_exponent > 0:
        result *= 2.0
        result_exponent -= 1
        if not isfinite(result):
            raise Error("matrix result is not representable")
    while result_exponent < 0:
        result *= 0.5
        result_exponent += 1
        if result == 0.0:
            return 0.0
    if not isfinite(result):
        raise Error("matrix result is not representable")
    return result


def _scaled_product_ratio_complex(
    value: Complex64,
    first_numerator: Float64,
    second_numerator: Float64,
    denominator: Float64,
) raises -> Complex64:
    return Complex64(
        _scaled_product_ratio_component(
            value.re, first_numerator, second_numerator, denominator
        ),
        _scaled_product_ratio_component(
            value.im, first_numerator, second_numerator, denominator
        ),
    )


def _divide(lhs: Complex64, rhs: Complex64) raises -> Complex64:
    """Scale-stable complex division for finite Float64 components."""
    if (
        not isfinite(lhs.re)
        or not isfinite(lhs.im)
        or not isfinite(rhs.re)
        or not isfinite(rhs.im)
    ):
        raise Error("complex division requires finite components")
    if rhs.re == 0.0 and rhs.im == 0.0:
        raise Error("singular complex division")
    # A common scale preserves the quotient while bounding every Smith-division
    # numerator.  Scaling by rhs alone can falsely overflow lhs/rhs even when
    # the complex rotation leaves both final components representable.
    var scale = max(
        abs(lhs.re), abs(lhs.im), abs(rhs.re), abs(rhs.im)
    )
    var a = lhs.re / scale
    var b = lhs.im / scale
    var c = rhs.re / scale
    var d = rhs.im / scale
    var result: Complex64
    if abs(c) >= abs(d):
        var ratio = d / c
        var denominator = c + d * ratio
        result = Complex64(
            (a + b * ratio) / denominator,
            (b - a * ratio) / denominator,
        )
    else:
        var ratio = c / d
        var denominator = d + c * ratio
        result = Complex64(
            (a * ratio + b) / denominator,
            (b * ratio - a) / denominator,
        )
    if not isfinite(result.re) or not isfinite(result.im):
        raise Error("complex quotient is not representable")
    return result


def hermitian(matrix: SmallComplexMatrix) raises -> SmallComplexMatrix:
    var result = SmallComplexMatrix(matrix.columns, matrix.rows)
    for row in range(matrix.rows):
        for column in range(matrix.columns):
            var value = matrix[row, column]
            result[column, row] = Complex64(value.re, -value.im)
    return result^


def matrix_multiply(
    lhs: SmallComplexMatrix, rhs: SmallComplexMatrix
) raises -> SmallComplexMatrix:
    if lhs.columns != rhs.rows:
        raise Error("matrix inner dimensions must match")
    var result = SmallComplexMatrix(lhs.rows, rhs.columns)
    var lhs_scale = _matrix_component_scale(lhs)
    var rhs_scale = _matrix_component_scale(rhs)
    if lhs_scale == 0.0 or rhs_scale == 0.0:
        return result^
    # Preserve the original operation order when every product and complete
    # accumulation is provably finite.  Extreme operands take the scaled path
    # below, so overflow cancellation never creates an Inf/NaN intermediate.
    if (
        lhs_scale
        <= Float64.MAX_FINITE
        / rhs_scale
        / Float64(2 * lhs.columns)
    ):
        for row in range(lhs.rows):
            for column in range(rhs.columns):
                var acc = Complex64(0.0)
                for k in range(lhs.columns):
                    acc = acc + lhs[row, k] * rhs[k, column]
                result[row, column] = acc
        return result^
    for row in range(lhs.rows):
        for column in range(rhs.columns):
            var sum_re = 0.0
            var correction_re = 0.0
            var sum_im = 0.0
            var correction_im = 0.0
            for k in range(lhs.columns):
                var a = lhs[row, k]
                var b = rhs[k, column]
                var ar = a.re / lhs_scale
                var ai = a.im / lhs_scale
                var br = b.re / rhs_scale
                var bi = b.im / rhs_scale
                var term_re = ar * br - ai * bi
                var term_im = ar * bi + ai * br
                var next_re = sum_re + term_re
                if abs(sum_re) >= abs(term_re):
                    correction_re += (sum_re - next_re) + term_re
                else:
                    correction_re += (term_re - next_re) + sum_re
                sum_re = next_re
                var next_im = sum_im + term_im
                if abs(sum_im) >= abs(term_im):
                    correction_im += (sum_im - next_im) + term_im
                else:
                    correction_im += (term_im - next_im) + sum_im
                sum_im = next_im
            result[row, column] = _scaled_product_ratio_complex(
                Complex64(
                    sum_re + correction_re, sum_im + correction_im
                ),
                lhs_scale,
                rhs_scale,
                1.0,
            )
    return result^


def gram_matrix(matrix: SmallComplexMatrix) raises -> SmallComplexMatrix:
    return matrix_multiply(hermitian(matrix), matrix)


def matrix_vector_multiply(
    matrix: SmallComplexMatrix, vector: Span[Complex64, ...]
) raises -> List[Complex64]:
    if matrix.columns != len(vector):
        raise Error("matrix/vector dimensions must match")
    var result = List[Complex64](capacity=matrix.rows)
    var matrix_scale = _matrix_component_scale(matrix)
    var vector_scale = _vector_component_scale(vector)
    if matrix_scale == 0.0 or vector_scale == 0.0:
        for _ in range(matrix.rows):
            result.append(Complex64(0.0))
        return result^
    if (
        matrix_scale
        <= Float64.MAX_FINITE
        / vector_scale
        / Float64(2 * matrix.columns)
    ):
        for row in range(matrix.rows):
            var acc = Complex64(0.0)
            for column in range(matrix.columns):
                var coefficient = matrix[row, column]
                var value = Complex64(vector[column].re, vector[column].im)
                acc = acc + coefficient * value
            result.append(acc)
        return result^
    for row in range(matrix.rows):
        var sum_re = 0.0
        var correction_re = 0.0
        var sum_im = 0.0
        var correction_im = 0.0
        for column in range(matrix.columns):
            var coefficient = matrix[row, column]
            var value = Complex64(vector[column].re, vector[column].im)
            var ar = coefficient.re / matrix_scale
            var ai = coefficient.im / matrix_scale
            var br = value.re / vector_scale
            var bi = value.im / vector_scale
            var term_re = ar * br - ai * bi
            var term_im = ar * bi + ai * br
            var next_re = sum_re + term_re
            if abs(sum_re) >= abs(term_re):
                correction_re += (sum_re - next_re) + term_re
            else:
                correction_re += (term_re - next_re) + sum_re
            sum_re = next_re
            var next_im = sum_im + term_im
            if abs(sum_im) >= abs(term_im):
                correction_im += (sum_im - next_im) + term_im
            else:
                correction_im += (term_im - next_im) + sum_im
            sum_im = next_im
        result.append(_scaled_product_ratio_complex(
            Complex64(sum_re + correction_re, sum_im + correction_im),
            matrix_scale,
            vector_scale,
            1.0,
        ))
    return result^


def inverse(matrix: SmallComplexMatrix) raises -> SmallComplexMatrix:
    """Gauss-Jordan inverse with scale-relative partial-pivot rejection."""
    if matrix.rows != matrix.columns:
        raise Error("inverse requires a square matrix")
    var size = matrix.rows
    var component_scale = _matrix_component_scale(matrix)
    if component_scale == 0.0:
        raise Error("matrix is singular")
    # All elimination is performed on A / scale.  This is algebraically the
    # same system, but its pivot powers cannot overflow for a merely large
    # finite input or underflow for a merely small one.
    var work = _scaled_matrix(matrix, component_scale)
    var matrix_scale = _matrix_magnitude_scale(work)
    var singular_magnitude = sqrt(_RELATIVE_SINGULAR_POWER) * matrix_scale
    var result = SmallComplexMatrix(size, size)
    for i in range(size):
        result[i, i] = Complex64(1.0, 0.0)
    for column in range(size):
        var pivot = column
        var pivot_magnitude = work[column, column].magnitude()
        for row in range(column + 1, size):
            var candidate = work[row, column].magnitude()
            if not isfinite(candidate):
                raise Error("inverse elimination produced a non-finite pivot")
            if candidate > pivot_magnitude:
                pivot = row
                pivot_magnitude = candidate
        if pivot_magnitude <= singular_magnitude:
            raise Error("matrix is singular")
        if pivot != column:
            for j in range(size):
                var tmp = work[column, j]
                work[column, j] = work[pivot, j]
                work[pivot, j] = tmp
                tmp = result[column, j]
                result[column, j] = result[pivot, j]
                result[pivot, j] = tmp
        var diagonal = work[column, column]
        for j in range(size):
            work[column, j] = _divide(work[column, j], diagonal)
            result[column, j] = _divide(result[column, j], diagonal)
        for row in range(size):
            if row == column:
                continue
            var factor = work[row, column]
            for j in range(size):
                work[row, j] = work[row, j] - factor * work[column, j]
                result[row, j] = result[row, j] - factor * result[column, j]
    for row in range(size):
        for column in range(size):
            result[row, column] = _scaled_ratio_complex(
                result[row, column], 1.0, component_scale
            )
    return result^


def zf_equalize(
    channel: SmallComplexMatrix, received: Span[Complex64, ...]
) raises -> List[Complex64]:
    """Return (H^H H)^-1 H^H y."""
    if channel.rows != len(received):
        raise Error("received vector length must equal channel rows")
    var channel_scale = _matrix_component_scale(channel)
    if channel_scale == 0.0:
        raise Error("channel matrix is singular")
    var received_scale = _vector_component_scale(received)
    if received_scale == 0.0:
        received_scale = 1.0
    var normalized_channel = _scaled_matrix(channel, channel_scale)
    var normalized_received = _scaled_vector(received, received_scale)
    var channel_h = hermitian(normalized_channel)
    var matched = matrix_vector_multiply(channel_h, Span(normalized_received))
    var weights = inverse(matrix_multiply(channel_h, normalized_channel))
    var normalized_result = matrix_vector_multiply(weights, Span(matched))
    var result = List[Complex64](capacity=len(normalized_result))
    for value in normalized_result:
        result.append(
            _scaled_ratio_complex(value, received_scale, channel_scale)
        )
    return result^


def mmse_equalize(
    channel: SmallComplexMatrix,
    received: Span[Complex64, ...],
    noise_variance: Float64,
) raises -> List[Complex64]:
    """Return (H^H H + sigma^2 I)^-1 H^H y."""
    if channel.rows != len(received):
        raise Error("received vector length must equal channel rows")
    if not isfinite(noise_variance) or noise_variance < 0.0:
        raise Error("noise variance must be finite and non-negative")
    var channel_scale = _matrix_component_scale(channel)
    var noise_scale = sqrt(noise_variance)
    if channel_scale == 0.0 and noise_scale == 0.0:
        raise Error("regularized channel matrix is singular")
    var received_scale = _vector_component_scale(received)
    if received_scale == 0.0:
        received_scale = 1.0
    if channel_scale == 0.0:
        var zero_result = List[Complex64](
            length=channel.columns, fill=Complex64(0.0, 0.0)
        )
        return zero_result^

    # H / channel_scale retains every representable channel coefficient.  The
    # two branches normalize the normal equation by whichever of |H|**2 or
    # noise_variance is larger, without ever forming the raw channel power.
    var normalized_channel = _scaled_matrix(channel, channel_scale)
    var normalized_received = _scaled_vector(received, received_scale)
    var channel_h = hermitian(normalized_channel)
    var matched = matrix_vector_multiply(
        channel_h, Span(normalized_received)
    )
    var regularized = matrix_multiply(channel_h, normalized_channel)
    var noise_dominates = noise_scale > channel_scale
    if noise_dominates:
        var normalized_channel_scale = channel_scale / noise_scale
        var normalized_channel_power = (
            normalized_channel_scale * normalized_channel_scale
        )
        for row in range(regularized.rows):
            for column in range(regularized.columns):
                var value = regularized[row, column]
                regularized[row, column] = Complex64(
                    value.re * normalized_channel_power,
                    value.im * normalized_channel_power,
                )
            regularized[row, row] = regularized[row, row] + Complex64(
                1.0, 0.0
            )
    else:
        var normalized_noise = noise_scale / channel_scale
        var normalized_noise_variance = normalized_noise * normalized_noise
        for i in range(regularized.rows):
            regularized[i, i] = regularized[i, i] + Complex64(
                normalized_noise_variance, 0.0
            )
    var normalized_result = matrix_vector_multiply(
        inverse(regularized), Span(matched)
    )
    var result = List[Complex64](capacity=len(normalized_result))
    for value in normalized_result:
        if noise_dominates:
            result.append(_scaled_product_ratio_complex(
                value,
                channel_scale,
                received_scale,
                noise_variance,
            ))
        else:
            result.append(
                _scaled_ratio_complex(value, received_scale, channel_scale)
            )
    return result^


def cholesky(matrix: SmallComplexMatrix) raises -> SmallComplexMatrix:
    """Lower-triangular Cholesky factor of a Hermitian positive-definite matrix."""
    if matrix.rows != matrix.columns:
        raise Error("Cholesky requires a square matrix")
    var size = matrix.rows
    var component_scale = _matrix_component_scale(matrix)
    if component_scale == 0.0:
        raise Error("matrix is not Hermitian positive definite")
    # Factor B = A / scale, then return sqrt(scale) * chol(B).  Hermitian and
    # HPD decisions are made in the bounded dimensionless domain.
    var normalized = _scaled_matrix(matrix, component_scale)
    var matrix_scale = _matrix_magnitude_scale(normalized)
    for row in range(size):
        for column in range(row, size):
            var upper = normalized[row, column]
            var lower_value = normalized[column, row]
            var pair_scale = max(
                upper.magnitude(),
                lower_value.magnitude(),
            )
            var tolerance = _RELATIVE_MATRIX_TOLERANCE * pair_scale
            if (
                abs(upper.re - lower_value.re) > tolerance
                or abs(upper.im + lower_value.im) > tolerance
            ):
                raise Error("Cholesky input must be Hermitian")
    var lower = SmallComplexMatrix(size, size)
    for row in range(size):
        for column in range(row + 1):
            var acc = normalized[row, column]
            for k in range(column):
                acc = acc - lower[row, k] * lower[column, k].conjugate()
            if row == column:
                if (
                    abs(acc.im)
                    > _RELATIVE_MATRIX_TOLERANCE * matrix_scale
                    or acc.re
                    <= _RELATIVE_MATRIX_TOLERANCE * matrix_scale
                ):
                    raise Error("matrix is not Hermitian positive definite")
                lower[row, column] = Complex64(sqrt(acc.re), 0.0)
            else:
                lower[row, column] = _divide(
                    acc, lower[column, column].conjugate()
                )
    var output_scale = sqrt(component_scale)
    for row in range(size):
        for column in range(row + 1):
            lower[row, column] = _scaled_ratio_complex(
                lower[row, column], output_scale, 1.0
            )
    return lower^


def qr_decompose(
    matrix: SmallComplexMatrix
) raises -> QRDecomposition:
    """Modified Gram-Schmidt QR for tall or square small complex matrices."""
    if matrix.rows < matrix.columns:
        raise Error("QR reference requires rows >= columns")
    var component_scale = _matrix_component_scale(matrix)
    if component_scale == 0.0:
        raise Error("matrix columns are linearly dependent")
    var normalized = _scaled_matrix(matrix, component_scale)
    var matrix_scale = _matrix_magnitude_scale(normalized)
    var singular_power = (
        _RELATIVE_SINGULAR_POWER * matrix_scale * matrix_scale
    )
    var q = SmallComplexMatrix(matrix.rows, matrix.columns)
    var r = SmallComplexMatrix(matrix.columns, matrix.columns)
    for column in range(matrix.columns):
        var work = List[Complex64](capacity=matrix.rows)
        for row in range(matrix.rows):
            work.append(normalized[row, column])
        for previous in range(column):
            var projection = Complex64(0.0, 0.0)
            for row in range(matrix.rows):
                projection = projection + q[row, previous].conjugate() * work[row]
            r[previous, column] = projection
            for row in range(matrix.rows):
                work[row] = work[row] - q[row, previous] * projection
        var norm_squared = 0.0
        for row in range(matrix.rows):
            norm_squared += work[row].magnitude_squared()
        if not isfinite(norm_squared) or norm_squared <= singular_power:
            raise Error("matrix columns are linearly dependent")
        var norm = sqrt(norm_squared)
        r[column, column] = Complex64(norm, 0.0)
        for row in range(matrix.rows):
            q[row, column] = Complex64(work[row].re / norm, work[row].im / norm)
    for row in range(r.rows):
        for column in range(r.columns):
            r[row, column] = _scaled_ratio_complex(
                r[row, column], component_scale, 1.0
            )
    return QRDecomposition(q^, r^)
