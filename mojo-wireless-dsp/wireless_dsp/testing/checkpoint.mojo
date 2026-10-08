"""Versioned PHY checkpoint metadata and deterministic checksums."""

from std.collections import Span
from std.math import isfinite, sqrt
from wireless_dsp.core import Complex64


struct CheckpointMetadata(Movable):
    var testcase_id: String
    var stage: String
    var dtype: String
    var shape: String
    var scale: Float64
    var version: Int
    var stride: String
    var q_format: String
    var layout: String

    def __init__(
        out self, var testcase_id: String, var stage: String, var dtype: String,
        var shape: String, scale: Float64, version: Int,
        var stride: String = "contiguous", var q_format: String = "floating",
        var layout: String = "unspecified",
    ):
        self.testcase_id = testcase_id^
        self.stage = stage^
        self.dtype = dtype^
        self.shape = shape^
        self.scale = scale
        self.version = version
        self.stride = stride^
        self.q_format = q_format^
        self.layout = layout^


def _checkpoint_text(value: StringSlice, field: StringSlice) raises -> String:
    if value.byte_length() == 0:
        raise Error("checkpoint metadata " + String(field) + " must not be empty")
    if "\n" in value or "\r" in value:
        raise Error(
            "checkpoint metadata " + String(field)
            + " must not contain line breaks"
        )
    var result = String()
    result.write(value)
    return result^


def _scaled_sumsq_add(
    scale: Float64,
    sum_squares: Float64,
    component_scale: Float64,
    component_factor: Float64,
) -> Tuple[Float64, Float64]:
    """Accumulate ``(component_scale * component_factor)^2`` safely.

    ``component_factor`` is supplied separately so even a finite difference
    between opposite-sign near-limit values never has to be materialized.
    """
    var factor = abs(component_factor)
    if component_scale == 0.0 or factor == 0.0:
        return (scale, sum_squares)
    if scale == 0.0:
        return (component_scale, factor * factor)
    if component_scale > scale:
        var ratio = scale / component_scale
        return (
            component_scale,
            factor * factor + sum_squares * ratio * ratio,
        )
    var ratio = component_scale / scale
    return (scale, sum_squares + factor * factor * ratio * ratio)


def _scaled_norm(scale: Float64, sum_squares: Float64) raises -> Float64:
    if scale == 0.0 or sum_squares == 0.0:
        return 0.0
    var factor = sqrt(sum_squares)
    if scale > Float64.MAX_FINITE / factor:
        raise Error("checkpoint complex norm is outside Float64 range")
    return scale * factor


def _scaled_norm_ratio(
    numerator_scale: Float64,
    numerator_sum_squares: Float64,
    denominator_scale: Float64,
    denominator_sum_squares: Float64,
) raises -> Float64:
    """Divide two scaled Euclidean norms without bad intermediates."""
    var norm_factor = sqrt(
        numerator_sum_squares / denominator_sum_squares
    )
    var scale_ratio = numerator_scale / denominator_scale
    if isfinite(scale_ratio) and scale_ratio != 0.0:
        var direct = scale_ratio * norm_factor
        if isfinite(direct) or direct == 0.0:
            return direct

    # A scale quotient can overflow even when a factor below one makes the
    # final ratio representable, or underflow before a factor above one
    # restores it.  Reduce the corresponding side before dividing.
    if norm_factor <= 1.0:
        var reduced_numerator = numerator_scale * norm_factor
        var result = reduced_numerator / denominator_scale
        if not isfinite(result):
            raise Error("checkpoint EVM is outside Float64 range")
        return result
    var reduced_denominator = denominator_scale / norm_factor
    if reduced_denominator != 0.0:
        var result = numerator_scale / reduced_denominator
        if isfinite(result):
            return result
    raise Error("checkpoint EVM is outside Float64 range")


def _complex_difference_magnitude(
    actual_re: Float64,
    actual_im: Float64,
    expected_re: Float64,
    expected_im: Float64,
) raises -> Float64:
    """Return ``abs(actual - expected)`` without overflowing subtraction."""
    var difference_scale = 0.0
    var difference_sum_squares = 0.0
    var real_scale = max(abs(actual_re), abs(expected_re))
    if real_scale != 0.0:
        difference_scale, difference_sum_squares = _scaled_sumsq_add(
            difference_scale,
            difference_sum_squares,
            real_scale,
            actual_re / real_scale - expected_re / real_scale,
        )
    var imaginary_scale = max(abs(actual_im), abs(expected_im))
    if imaginary_scale != 0.0:
        difference_scale, difference_sum_squares = _scaled_sumsq_add(
            difference_scale,
            difference_sum_squares,
            imaginary_scale,
            actual_im / imaginary_scale - expected_im / imaginary_scale,
        )
    return _scaled_norm(difference_scale, difference_sum_squares)


def checkpoint_metadata_1d(
    testcase_id: StringSlice,
    stage: StringSlice,
    dtype: StringSlice,
    length: Int,
    *,
    scale: Float64 = 1.0,
    element_stride: Int = 1,
    q_format: StringSlice = "floating",
    version: Int = 1,
    layout: StringSlice = "linear",
) raises -> CheckpointMetadata:
    """Build owned metadata for a one-dimensional production checkpoint.

    Shape and stride are expressed in logical elements.  Text arguments are
    copied so the returned envelope never borrows call-site storage.
    """
    if length < 0 or element_stride < 1:
        raise Error("checkpoint length and element stride are invalid")
    if not isfinite(scale) or scale <= 0.0 or version < 1:
        raise Error("checkpoint scale/version metadata are invalid")
    var testcase_text = _checkpoint_text(testcase_id, "testcase_id")
    var stage_text = _checkpoint_text(stage, "stage")
    var dtype_text = _checkpoint_text(dtype, "dtype")
    var q_format_text = _checkpoint_text(q_format, "q_format")
    var layout_text = _checkpoint_text(layout, "layout")
    var shape_text = String()
    shape_text.write(length)
    var stride_text = String()
    stride_text.write(element_stride)
    return CheckpointMetadata(
        testcase_id=testcase_text^,
        stage=stage_text^,
        dtype=dtype_text^,
        shape=shape_text^,
        scale=scale,
        version=version,
        stride=stride_text^,
        q_format=q_format_text^,
        layout=layout_text^,
    )


def checkpoint_metadata_2d(
    testcase_id: StringSlice,
    stage: StringSlice,
    dtype: StringSlice,
    rows: Int,
    columns: Int,
    *,
    row_stride: Int,
    column_stride: Int = 1,
    scale: Float64 = 1.0,
    q_format: StringSlice = "floating",
    version: Int = 1,
    layout: StringSlice = "row-major",
) raises -> CheckpointMetadata:
    """Build owned metadata for a two-dimensional production checkpoint."""
    if rows < 0 or columns < 0 or row_stride < 1 or column_stride < 1:
        raise Error("checkpoint matrix dimensions or strides are invalid")
    if not isfinite(scale) or scale <= 0.0 or version < 1:
        raise Error("checkpoint scale/version metadata are invalid")
    var testcase_text = _checkpoint_text(testcase_id, "testcase_id")
    var stage_text = _checkpoint_text(stage, "stage")
    var dtype_text = _checkpoint_text(dtype, "dtype")
    var q_format_text = _checkpoint_text(q_format, "q_format")
    var layout_text = _checkpoint_text(layout, "layout")
    var shape_text = String()
    shape_text.write(rows, "x", columns)
    var stride_text = String()
    stride_text.write(row_stride, ",", column_stride)
    return CheckpointMetadata(
        testcase_id=testcase_text^,
        stage=stage_text^,
        dtype=dtype_text^,
        shape=shape_text^,
        scale=scale,
        version=version,
        stride=stride_text^,
        q_format=q_format_text^,
        layout=layout_text^,
    )


def checkpoint_bits_checksum(bits: Span[UInt8, ...]) raises -> UInt64:
    """FNV-1a checksum for compact bit-exact checkpoint comparisons."""
    var result = UInt64(14695981039346656037)
    for i in range(len(bits)):
        var bit = bits[i]
        if bit > 1:
            raise Error("checkpoint input is not binary")
        result ^= UInt64(bit)
        result *= UInt64(1099511628211)
    return result


def checkpoint_complex_error(
    actual: Span[Complex64, ...], expected: Span[Complex64, ...]
) raises -> Tuple[Float64, Float64]:
    """Return RMS EVM and maximum absolute complex error.

    EVM is zero when both vectors have zero energy.  A non-zero error against
    an all-zero reference, or any otherwise unrepresentable finite-input
    result, raises instead of returning a non-finite sentinel.
    """
    if len(actual) != len(expected) or len(actual) == 0:
        raise Error("checkpoint vectors must be equal and non-empty")
    var error_scale = 0.0
    var error_sum_squares = 0.0
    var reference_scale = 0.0
    var reference_sum_squares = 0.0
    var maximum = 0.0
    for i in range(len(actual)):
        if (
            not isfinite(actual[i].re)
            or not isfinite(actual[i].im)
            or not isfinite(expected[i].re)
            or not isfinite(expected[i].im)
        ):
            raise Error("checkpoint complex vectors must contain finite values")

        var real_scale = max(abs(actual[i].re), abs(expected[i].re))
        if real_scale != 0.0:
            var real_factor = (
                actual[i].re / real_scale - expected[i].re / real_scale
            )
            error_scale, error_sum_squares = _scaled_sumsq_add(
                error_scale,
                error_sum_squares,
                real_scale,
                real_factor,
            )
        var imaginary_scale = max(abs(actual[i].im), abs(expected[i].im))
        if imaginary_scale != 0.0:
            var imaginary_factor = (
                actual[i].im / imaginary_scale
                - expected[i].im / imaginary_scale
            )
            error_scale, error_sum_squares = _scaled_sumsq_add(
                error_scale,
                error_sum_squares,
                imaginary_scale,
                imaginary_factor,
            )

        reference_scale, reference_sum_squares = _scaled_sumsq_add(
            reference_scale,
            reference_sum_squares,
            abs(expected[i].re),
            1.0,
        )
        reference_scale, reference_sum_squares = _scaled_sumsq_add(
            reference_scale,
            reference_sum_squares,
            abs(expected[i].im),
            1.0,
        )
        maximum = max(
            maximum,
            _complex_difference_magnitude(
                actual[i].re,
                actual[i].im,
                expected[i].re,
                expected[i].im,
            ),
        )
    var evm = 0.0
    if reference_scale > 0.0 and error_scale > 0.0:
        evm = _scaled_norm_ratio(
            error_scale,
            error_sum_squares,
            reference_scale,
            reference_sum_squares,
        )
    elif reference_scale == 0.0 and error_scale > 0.0:
        raise Error("checkpoint EVM is undefined for an all-zero reference")
    if not isfinite(evm) or not isfinite(maximum):
        raise Error("checkpoint complex error is outside Float64 range")
    return (evm, maximum)
