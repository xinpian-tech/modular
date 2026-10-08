"""Allocation-controlled Float32 CPU kernels for square 2x2/4x4 MIMO.

Matrices are flat row-major ``Span[Complex32]`` values.  The ``*_into`` APIs
write into caller-owned, exactly sized lists and the ZF/MMSE solvers reuse a
``MIMOF32Workspace``; no storage is allocated inside a successful ``*_into``
call.  Convenience wrappers return fresh owning lists.

ZF and MMSE form ``G = H^H H`` and ``z = H^H y``, then solve the Hermitian
normal equations with Float32 Cholesky factorization.  Every input and computed
boundary is finite-checked.  A diagonal Cholesky pivot is accepted only when
it is strictly greater than ``MIMO_F32_RELATIVE_PIVOT * max(diag(G))``.  The
criterion is therefore invariant to a common finite channel/observation scale
until Float32 underflow or overflow is reached.
"""

from std.collections import Span
from std.math import isfinite, sqrt
from wireless_dsp.core import Complex32


# 2^-16 = 128 binary32 epsilons.  This applies to the normal-equation matrix,
# whose condition number is the square of the channel condition number.
comptime MIMO_F32_RELATIVE_PIVOT = Float32(1.52587890625e-5)


struct MIMOF32Workspace(Movable):
    """Reusable scratch storage and diagnostics for one 2x2 or 4x4 size.

    A workspace is mutable and supports sequential reuse.  It must not be
    shared by concurrent solves.  ``last_*`` diagnostics describe the most
    recent factorization attempt and use Gram-matrix power units.
    """

    var size: Int
    var gram: List[Complex32]
    var matched: List[Complex32]
    var factor: List[Complex32]
    var forward: List[Complex32]
    var last_matrix_scale: Float32
    var last_pivot_threshold: Float32
    var last_minimum_pivot: Float32

    def __init__(out self, size: Int) raises:
        _validate_mimo_size_f32(size)
        self.size = size
        self.gram = List[Complex32](
            length=size * size, fill=Complex32(0.0, 0.0)
        )
        self.matched = List[Complex32](
            length=size, fill=Complex32(0.0, 0.0)
        )
        self.factor = List[Complex32](
            length=size * size, fill=Complex32(0.0, 0.0)
        )
        self.forward = List[Complex32](
            length=size, fill=Complex32(0.0, 0.0)
        )
        self.last_matrix_scale = Float32(0.0)
        self.last_pivot_threshold = Float32(0.0)
        self.last_minimum_pivot = Float32(0.0)


def make_mimo_workspace_f32(size: Int) raises -> MIMOF32Workspace:
    """Allocate reusable normal-equation scratch for size two or four."""
    return MIMOF32Workspace(size)


def _validate_mimo_size_f32(size: Int) raises:
    if size != 2 and size != 4:
        raise Error("Float32 MIMO size must be 2 or 4")


def _is_finite_complex_f32(value: Complex32) -> Bool:
    return isfinite(value.re) and isfinite(value.im)


def _require_finite_f32(values: Span[Complex32, ...]) raises:
    for index in range(len(values)):
        var value = Complex32(values[index].re, values[index].im)
        if not _is_finite_complex_f32(value):
            raise Error("Float32 MIMO inputs must be finite")


def _validate_square_matrix_f32(
    matrix: Span[Complex32, ...], size: Int
) raises:
    _validate_mimo_size_f32(size)
    if len(matrix) != size * size:
        raise Error("Float32 MIMO matrix must be a square row-major size")
    _require_finite_f32(matrix)


def _validate_vector_f32(
    vector: Span[Complex32, ...], size: Int
) raises:
    if len(vector) != size:
        raise Error("Float32 MIMO vector length must match matrix size")
    _require_finite_f32(vector)


def _validate_output_f32(output: List[Complex32], length: Int) raises:
    if len(output) != length:
        raise Error("Float32 MIMO output storage has the wrong length")


def _validate_workspace_f32(workspace: MIMOF32Workspace) raises:
    _validate_mimo_size_f32(workspace.size)
    if (
        len(workspace.gram) != workspace.size * workspace.size
        or len(workspace.matched) != workspace.size
        or len(workspace.factor) != workspace.size * workspace.size
        or len(workspace.forward) != workspace.size
    ):
        raise Error("Float32 MIMO workspace storage is inconsistent")


def _require_finite_boundary_f32(value: Complex32) raises:
    if not _is_finite_complex_f32(value):
        raise Error("Float32 MIMO arithmetic exceeded its finite range")


def complex_matvec_f32_into(
    matrix: Span[Complex32, ...],
    vector: Span[Complex32, ...],
    size: Int,
    mut output: List[Complex32],
) raises:
    """Write ``matrix @ vector`` using row-major 2x2/4x4 Float32 inputs."""
    _validate_square_matrix_f32(matrix, size)
    _validate_vector_f32(vector, size)
    _validate_output_f32(output, size)
    for row in range(size):
        var accumulator = Complex32(0.0, 0.0)
        for column in range(size):
            var coefficient = Complex32(
                matrix[row * size + column].re,
                matrix[row * size + column].im,
            )
            var value = Complex32(vector[column].re, vector[column].im)
            accumulator = (
                accumulator + coefficient * value
            )
        _require_finite_boundary_f32(accumulator)
        output[row] = accumulator


def complex_matvec_f32(
    matrix: Span[Complex32, ...],
    vector: Span[Complex32, ...],
    size: Int,
) raises -> List[Complex32]:
    """Return an owning row-major 2x2/4x4 complex matrix-vector product."""
    _validate_mimo_size_f32(size)
    var output = List[Complex32](
        length=size, fill=Complex32(0.0, 0.0)
    )
    complex_matvec_f32_into(matrix, vector, size, output)
    return output^


def _gram_f32_unchecked(
    channel: Span[Complex32, ...],
    size: Int,
    mut output: List[Complex32],
) raises:
    for left in range(size):
        var diagonal = Float32(0.0)
        for row in range(size):
            var value = Complex32(
                channel[row * size + left].re,
                channel[row * size + left].im,
            )
            diagonal += value.magnitude_squared()
        var diagonal_value = Complex32(diagonal, 0.0)
        _require_finite_boundary_f32(diagonal_value)
        output[left * size + left] = diagonal_value

        for right in range(left + 1, size):
            var accumulator = Complex32(0.0, 0.0)
            for row in range(size):
                var lhs = Complex32(
                    channel[row * size + left].re,
                    channel[row * size + left].im,
                )
                var rhs = Complex32(
                    channel[row * size + right].re,
                    channel[row * size + right].im,
                )
                accumulator = (
                    accumulator
                    + lhs.conjugate() * rhs
                )
            _require_finite_boundary_f32(accumulator)
            output[left * size + right] = accumulator
            output[right * size + left] = accumulator.conjugate()


def mimo_gram_f32_into(
    channel: Span[Complex32, ...],
    size: Int,
    mut output: List[Complex32],
) raises:
    """Write exact-Hermitian row-major ``H^H H`` into reusable storage."""
    _validate_square_matrix_f32(channel, size)
    _validate_output_f32(output, size * size)
    _gram_f32_unchecked(channel, size, output)


def mimo_gram_f32(
    channel: Span[Complex32, ...], size: Int
) raises -> List[Complex32]:
    """Return owning row-major ``H^H H`` for a 2x2/4x4 channel."""
    _validate_mimo_size_f32(size)
    var output = List[Complex32](
        length=size * size, fill=Complex32(0.0, 0.0)
    )
    mimo_gram_f32_into(channel, size, output)
    return output^


def _matched_f32_unchecked(
    channel: Span[Complex32, ...],
    observation: Span[Complex32, ...],
    size: Int,
    mut output: List[Complex32],
) raises:
    for column in range(size):
        var accumulator = Complex32(0.0, 0.0)
        for row in range(size):
            var coefficient = Complex32(
                channel[row * size + column].re,
                channel[row * size + column].im,
            )
            var value = Complex32(
                observation[row].re, observation[row].im
            )
            accumulator = (
                accumulator
                + coefficient.conjugate() * value
            )
        _require_finite_boundary_f32(accumulator)
        output[column] = accumulator


def mimo_matched_filter_f32_into(
    channel: Span[Complex32, ...],
    observation: Span[Complex32, ...],
    size: Int,
    mut output: List[Complex32],
) raises:
    """Write ``H^H y`` into caller-owned reusable storage."""
    _validate_square_matrix_f32(channel, size)
    _validate_vector_f32(observation, size)
    _validate_output_f32(output, size)
    _matched_f32_unchecked(channel, observation, size, output)


def mimo_matched_filter_f32(
    channel: Span[Complex32, ...],
    observation: Span[Complex32, ...],
    size: Int,
) raises -> List[Complex32]:
    """Return an owning ``H^H y`` for a 2x2/4x4 channel."""
    _validate_mimo_size_f32(size)
    var output = List[Complex32](
        length=size, fill=Complex32(0.0, 0.0)
    )
    mimo_matched_filter_f32_into(channel, observation, size, output)
    return output^


def mimo_gram_matched_f32_into(
    channel: Span[Complex32, ...],
    observation: Span[Complex32, ...],
    size: Int,
    mut gram_output: List[Complex32],
    mut matched_output: List[Complex32],
) raises:
    """Write ``H^H H`` and ``H^H y`` after one shared validation pass."""
    _validate_square_matrix_f32(channel, size)
    _validate_vector_f32(observation, size)
    _validate_output_f32(gram_output, size * size)
    _validate_output_f32(matched_output, size)
    _gram_f32_unchecked(channel, size, gram_output)
    _matched_f32_unchecked(channel, observation, size, matched_output)


def _factor_and_solve_f32(
    mut workspace: MIMOF32Workspace,
    mut output: List[Complex32],
) raises:
    var size = workspace.size
    for index in range(size * size):
        workspace.factor[index] = Complex32(0.0, 0.0)

    var matrix_scale = Float32(0.0)
    for diagonal in range(size):
        var value = workspace.gram[diagonal * size + diagonal]
        _require_finite_boundary_f32(value)
        matrix_scale = max(matrix_scale, abs(value.re))
    if not isfinite(matrix_scale) or matrix_scale <= Float32(0.0):
        raise Error("Float32 MIMO normal matrix has zero finite scale")
    var pivot_threshold = MIMO_F32_RELATIVE_PIVOT * matrix_scale
    if not isfinite(pivot_threshold) or pivot_threshold <= Float32(0.0):
        raise Error("Float32 MIMO pivot threshold left its finite range")
    workspace.last_matrix_scale = matrix_scale
    workspace.last_pivot_threshold = pivot_threshold
    workspace.last_minimum_pivot = matrix_scale

    for row in range(size):
        for column in range(row + 1):
            var accumulator = workspace.gram[row * size + column]
            for previous in range(column):
                accumulator = (
                    accumulator
                    - workspace.factor[row * size + previous]
                    * workspace.factor[column * size + previous].conjugate()
                )
            _require_finite_boundary_f32(accumulator)
            if row == column:
                if (
                    abs(accumulator.im) > pivot_threshold
                    or accumulator.re <= pivot_threshold
                ):
                    raise Error(
                        "Float32 MIMO normal matrix is singular at relative pivot"
                    )
                workspace.last_minimum_pivot = min(
                    workspace.last_minimum_pivot, accumulator.re
                )
                var root = sqrt(accumulator.re)
                if not isfinite(root) or root <= Float32(0.0):
                    raise Error("Float32 MIMO Cholesky pivot is not finite")
                workspace.factor[row * size + column] = Complex32(root, 0.0)
            else:
                var divisor = workspace.factor[column * size + column].re
                var value = Complex32(
                    accumulator.re / divisor, accumulator.im / divisor
                )
                _require_finite_boundary_f32(value)
                workspace.factor[row * size + column] = value

    for row in range(size):
        var accumulator = workspace.matched[row]
        for column in range(row):
            accumulator = (
                accumulator
                - workspace.factor[row * size + column]
                * workspace.forward[column]
            )
        var divisor = workspace.factor[row * size + row].re
        var value = Complex32(
            accumulator.re / divisor, accumulator.im / divisor
        )
        _require_finite_boundary_f32(value)
        workspace.forward[row] = value

    for reverse_row in range(size):
        var row = size - reverse_row - 1
        var accumulator = workspace.forward[row]
        for column in range(row + 1, size):
            accumulator = (
                accumulator
                - workspace.factor[column * size + row].conjugate()
                * output[column]
            )
        var divisor = workspace.factor[row * size + row].re
        var value = Complex32(
            accumulator.re / divisor, accumulator.im / divisor
        )
        _require_finite_boundary_f32(value)
        output[row] = value


def mimo_zf_f32_into(
    channel: Span[Complex32, ...],
    observation: Span[Complex32, ...],
    mut workspace: MIMOF32Workspace,
    mut output: List[Complex32],
) raises:
    """Solve ``(H^H H)x = H^H y`` without allocating scratch storage."""
    _validate_workspace_f32(workspace)
    _validate_output_f32(output, workspace.size)
    mimo_gram_matched_f32_into(
        channel,
        observation,
        workspace.size,
        workspace.gram,
        workspace.matched,
    )
    _factor_and_solve_f32(workspace, output)


def mimo_zf_f32(
    channel: Span[Complex32, ...],
    observation: Span[Complex32, ...],
    size: Int,
) raises -> List[Complex32]:
    """Allocate one workspace and return an owning Float32 ZF estimate."""
    var workspace = make_mimo_workspace_f32(size)
    var output = List[Complex32](
        length=size, fill=Complex32(0.0, 0.0)
    )
    mimo_zf_f32_into(channel, observation, workspace, output)
    return output^


def mimo_mmse_f32_into(
    channel: Span[Complex32, ...],
    observation: Span[Complex32, ...],
    noise_variance: Float32,
    mut workspace: MIMOF32Workspace,
    mut output: List[Complex32],
) raises:
    """Solve ``(H^H H + noise_variance*I)x = H^H y`` without allocation."""
    if not isfinite(noise_variance) or noise_variance < Float32(0.0):
        raise Error("Float32 MIMO noise variance must be finite and non-negative")
    _validate_workspace_f32(workspace)
    _validate_output_f32(output, workspace.size)
    mimo_gram_matched_f32_into(
        channel,
        observation,
        workspace.size,
        workspace.gram,
        workspace.matched,
    )
    for diagonal in range(workspace.size):
        var index = diagonal * workspace.size + diagonal
        var regularized = Complex32(
            workspace.gram[index].re + noise_variance, 0.0
        )
        _require_finite_boundary_f32(regularized)
        workspace.gram[index] = regularized
    _factor_and_solve_f32(workspace, output)


def mimo_mmse_f32(
    channel: Span[Complex32, ...],
    observation: Span[Complex32, ...],
    size: Int,
    noise_variance: Float32,
) raises -> List[Complex32]:
    """Allocate one workspace and return an owning Float32 MMSE estimate."""
    var workspace = make_mimo_workspace_f32(size)
    var output = List[Complex32](
        length=size, fill=Complex32(0.0, 0.0)
    )
    mimo_mmse_f32_into(
        channel, observation, noise_variance, workspace, output
    )
    return output^
