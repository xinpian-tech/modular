"""Runtime Q-format primitives with explicit hardware boundary semantics.

The generic ``Fixed`` type is convenient inside a statically configured
kernel.  This module complements it with runtime descriptors used by test
vectors, scale schedules, and bit-exact reference backends.  Every public
operation states exactly where rounding and narrowing occur.
"""

from std.math import ceil, floor, isfinite
from .fixed import (
    ROUND_NEAREST_AWAY,
    ROUND_TOWARD_ZERO,
    OVERFLOW_SATURATE,
    OVERFLOW_WRAP,
)


comptime FLOAT64_EXACT_INTEGER_BITS = 53


struct QFormat(ImplicitlyCopyable, Equatable):
    """A signed two's-complement Q-format descriptor.

    Storage widths are capped at 62 bits so bounds, modular narrowing, and
    intermediate shifts remain representable in the Int64 golden model.
    Multipliers further require operands of at most 31 bits.
    """

    var storage_bits: Int
    var fraction_bits: Int
    var rounding_mode: Int
    var overflow_mode: Int

    def __init__(
        out self,
        storage_bits: Int,
        fraction_bits: Int,
        rounding_mode: Int = ROUND_NEAREST_AWAY,
        overflow_mode: Int = OVERFLOW_SATURATE,
    ) raises:
        if storage_bits < 2 or storage_bits > 62:
            raise Error("Q-format storage width must be in [2, 62]")
        if fraction_bits < 0 or fraction_bits >= storage_bits:
            raise Error("Q-format fraction width must be in [0, storage_bits)")
        if (
            rounding_mode != ROUND_NEAREST_AWAY
            and rounding_mode != ROUND_TOWARD_ZERO
        ):
            raise Error("unsupported Q-format rounding mode")
        if (
            overflow_mode != OVERFLOW_SATURATE
            and overflow_mode != OVERFLOW_WRAP
        ):
            raise Error("unsupported Q-format overflow mode")
        self.storage_bits = storage_bits
        self.fraction_bits = fraction_bits
        self.rounding_mode = rounding_mode
        self.overflow_mode = overflow_mode

    def min_raw(self) -> Int64:
        return -(Int64(1) << Int64(self.storage_bits - 1))

    def max_raw(self) -> Int64:
        return (Int64(1) << Int64(self.storage_bits - 1)) - 1

    def scale(self) -> Int64:
        return Int64(1) << Int64(self.fraction_bits)


def _qformat_fields_are_valid(qformat: QFormat) -> Bool:
    return (
        qformat.storage_bits >= 2
        and qformat.storage_bits <= 62
        and qformat.fraction_bits >= 0
        and qformat.fraction_bits < qformat.storage_bits
        and (
            qformat.rounding_mode == ROUND_NEAREST_AWAY
            or qformat.rounding_mode == ROUND_TOWARD_ZERO
        )
        and (
            qformat.overflow_mode == OVERFLOW_SATURATE
            or qformat.overflow_mode == OVERFLOW_WRAP
        )
    )


def validate_qformat(qformat: QFormat) raises -> QFormat:
    """Return a validated descriptor copy for a numeric operation boundary.

    ``QFormat`` remains field-addressable for source compatibility.  Callers
    can therefore mutate a previously constructed value, so every public
    arithmetic boundary must validate and copy it before evaluating shifts or
    bounds.  This function is the single validation path used by the runtime
    fixed-point layer and the canonical artifact serializers.
    """
    if not _qformat_fields_are_valid(qformat):
        raise Error("invalid or mutated Q-format descriptor")
    return QFormat(
        qformat.storage_bits,
        qformat.fraction_bits,
        qformat.rounding_mode,
        qformat.overflow_mode,
    )


def raw_fits(value: Int64, qformat: QFormat) -> Bool:
    """Return whether the descriptor and raw value are both canonical."""
    if not _qformat_fields_are_valid(qformat):
        return False
    return value >= qformat.min_raw() and value <= qformat.max_raw()


def require_raw_fits(value: Int64, qformat: QFormat) raises:
    """Reject a raw operand that violates its declared interface format."""
    var validated = validate_qformat(qformat)
    if not raw_fits(value, validated):
        raise Error("raw fixed-point operand exceeds its declared Q-format")


def narrow_raw(value: Int64, qformat: QFormat) raises -> Int64:
    """Narrow using the descriptor's saturation or two's-complement wrap."""
    var validated = validate_qformat(qformat)
    if validated.overflow_mode == OVERFLOW_SATURATE:
        return min(max(value, validated.min_raw()), validated.max_raw())

    var modulus = Int64(1) << Int64(validated.storage_bits)
    var wrapped = value % modulus
    if wrapped > validated.max_raw():
        wrapped -= modulus
    elif wrapped < validated.min_raw():
        wrapped += modulus
    return wrapped


def rounded_shift_right(
    value: Int64, shift: Int, rounding_mode: Int
) raises -> Int64:
    """Arithmetic scale-down with symmetric, explicitly selected rounding."""
    if shift < 0 or shift > 61:
        raise Error("fixed-point right shift must be in [0, 61]")
    if shift == 0:
        return value
    var shifted = value >> Int64(shift)
    var mask = (Int64(1) << Int64(shift)) - 1
    var remainder = value & mask
    if rounding_mode == ROUND_TOWARD_ZERO:
        if value < 0 and remainder != 0:
            return shifted + 1
        return shifted
    if rounding_mode != ROUND_NEAREST_AWAY:
        raise Error("unsupported fixed-point rounding mode")
    var half = Int64(1) << Int64(shift - 1)
    if value < 0:
        # Arithmetic shift gives floor(value / 2^shift).  A negative tie stays
        # at floor (away from zero); only a remainder larger than half moves
        # one step toward zero.
        return shifted + Int64(1 if remainder > half else 0)
    return shifted + Int64(1 if remainder >= half else 0)


def rescale_raw(
    value: Int64,
    input_fraction_bits: Int,
    output_format: QFormat,
) raises -> Int64:
    """Convert a raw value to ``output_format`` and narrow exactly once.

    A left shift is evaluated as repeated width-limited doubling.  Besides
    avoiding Int64 overflow, this gives exact modular behavior for wrap mode.
    """
    if input_fraction_bits < 0 or input_fraction_bits > 61:
        raise Error("input fraction width must be in [0, 61]")
    var validated_output = validate_qformat(output_format)
    if validated_output.fraction_bits <= input_fraction_bits:
        var shift = input_fraction_bits - validated_output.fraction_bits
        return narrow_raw(
            rounded_shift_right(
                value, shift, validated_output.rounding_mode
            ),
            validated_output,
        )

    var result = narrow_raw(value, validated_output)
    for _ in range(validated_output.fraction_bits - input_fraction_bits):
        result = narrow_raw(result * 2, validated_output)
    return result


def quantize_raw(value: Float64, qformat: QFormat) raises -> Int64:
    """Quantize a real value with an explicit Float64 exactness contract.

    A binary64 value has 53 significant integer bits.  Formats wider than
    that cannot, in general, distinguish adjacent raw codes after scaling, so
    this Float64 entry point rejects them instead of making a false bit-exact
    promise.  Wider RTL constants must enter through integer raw words (or a
    future rational/integer quantizer), not through Float64.
    """
    var validated = validate_qformat(qformat)
    if validated.storage_bits > FLOAT64_EXACT_INTEGER_BITS:
        raise Error(
            "Float64 quantization supports at most 53-bit Q-formats; use raw integer input for wider formats"
        )
    if not isfinite(value):
        raise Error("fixed-point quantization requires a finite input")
    var scaled = value * Float64(validated.scale())

    # Saturating before the Float64-to-Int64 conversion also makes extremely
    # large finite values deterministic and safe.
    if validated.overflow_mode == OVERFLOW_SATURATE:
        if scaled >= Float64(validated.max_raw()) + 0.5:
            return validated.max_raw()
        if scaled <= Float64(validated.min_raw()) - 0.5:
            return validated.min_raw()
    elif scaled > 9.0e18 or scaled < -9.0e18:
        raise Error("wrapped quantization input exceeds Int64 reference range")

    var rounded: Int64
    if validated.rounding_mode == ROUND_NEAREST_AWAY:
        if scaled < 0.0:
            rounded = Int64(ceil(scaled - 0.5))
        else:
            rounded = Int64(floor(scaled + 0.5))
    else:
        if scaled < 0.0:
            rounded = Int64(ceil(scaled))
        else:
            rounded = Int64(floor(scaled))
    return narrow_raw(rounded, validated)


def dequantize_raw(value: Int64, qformat: QFormat) raises -> Float64:
    """Convert a canonical raw value to the nearest representable Float64.

    Unlike ``quantize_raw``, this is an audit conversion rather than a
    reversible bit-exact encoding for raw magnitudes above 2**53.
    """
    var validated = validate_qformat(qformat)
    require_raw_fits(value, validated)
    return Float64(value) / Float64(validated.scale())


def fixed_add_raw(
    lhs: Int64,
    lhs_format: QFormat,
    rhs: Int64,
    rhs_format: QFormat,
    output_format: QFormat,
) raises -> Int64:
    """Convert both adder ports to output Q, add, then narrow the sum.

    The two port conversions are explicit narrowing boundaries.  Kernels that
    require a wider fused butterfly use their own guarded wide datapath.
    """
    var validated_lhs = validate_qformat(lhs_format)
    var validated_rhs = validate_qformat(rhs_format)
    var validated_output = validate_qformat(output_format)
    require_raw_fits(lhs, validated_lhs)
    require_raw_fits(rhs, validated_rhs)
    var lhs_out = rescale_raw(
        lhs, validated_lhs.fraction_bits, validated_output
    )
    var rhs_out = rescale_raw(
        rhs, validated_rhs.fraction_bits, validated_output
    )
    return narrow_raw(lhs_out + rhs_out, validated_output)


def fixed_sub_raw(
    lhs: Int64,
    lhs_format: QFormat,
    rhs: Int64,
    rhs_format: QFormat,
    output_format: QFormat,
) raises -> Int64:
    """Convert both subtractor ports to output Q, then narrow the difference."""
    var validated_lhs = validate_qformat(lhs_format)
    var validated_rhs = validate_qformat(rhs_format)
    var validated_output = validate_qformat(output_format)
    require_raw_fits(lhs, validated_lhs)
    require_raw_fits(rhs, validated_rhs)
    var lhs_out = rescale_raw(
        lhs, validated_lhs.fraction_bits, validated_output
    )
    var rhs_out = rescale_raw(
        rhs, validated_rhs.fraction_bits, validated_output
    )
    return narrow_raw(lhs_out - rhs_out, validated_output)


def fixed_mul_raw(
    lhs: Int64,
    lhs_format: QFormat,
    rhs: Int64,
    rhs_format: QFormat,
    output_format: QFormat,
) raises -> Int64:
    """Multiply wide, rescale once, then narrow at the output boundary."""
    var validated_lhs = validate_qformat(lhs_format)
    var validated_rhs = validate_qformat(rhs_format)
    var validated_output = validate_qformat(output_format)
    if validated_lhs.storage_bits > 31 or validated_rhs.storage_bits > 31:
        raise Error("bit-exact Int64 multiplier operands are limited to 31 bits")
    require_raw_fits(lhs, validated_lhs)
    require_raw_fits(rhs, validated_rhs)
    return rescale_raw(
        lhs * rhs,
        validated_lhs.fraction_bits + validated_rhs.fraction_bits,
        validated_output,
    )


def fixed_mac_raw(
    accumulator: Int64,
    lhs: Int64,
    lhs_format: QFormat,
    rhs: Int64,
    rhs_format: QFormat,
    accumulator_format: QFormat,
) raises -> Int64:
    """Registered ``acc + lhs*rhs`` with explicit multiplier/MAC boundaries."""
    var validated_accumulator = validate_qformat(accumulator_format)
    require_raw_fits(accumulator, validated_accumulator)
    var product = fixed_mul_raw(
        lhs, lhs_format, rhs, rhs_format, validated_accumulator
    )
    return narrow_raw(accumulator + product, validated_accumulator)


def fixed_shift_raw(
    value: Int64, right_shift: Int, qformat: QFormat
) raises -> Int64:
    """Shift a raw word in place; negative counts are narrowing left shifts."""
    var validated = validate_qformat(qformat)
    require_raw_fits(value, validated)
    if right_shift >= 0:
        return narrow_raw(
            rounded_shift_right(value, right_shift, validated.rounding_mode),
            validated,
        )
    if right_shift < -61:
        raise Error("fixed-point left shift must be at most 61 bits")
    var result = value
    for _ in range(-right_shift):
        result = narrow_raw(result * 2, validated)
    return result


def fixed_abs_raw(value: Int64, qformat: QFormat) raises -> Int64:
    """Bit-exact absolute value, including the two's-complement minimum."""
    var validated = validate_qformat(qformat)
    require_raw_fits(value, validated)
    return narrow_raw(-value, validated) if value < 0 else value


def fixed_min_raw(
    lhs: Int64, rhs: Int64, qformat: QFormat
) raises -> Int64:
    """Minimum of two canonical words in the same Q-format."""
    var validated = validate_qformat(qformat)
    require_raw_fits(lhs, validated)
    require_raw_fits(rhs, validated)
    return min(lhs, rhs)


def fixed_max_raw(
    lhs: Int64, rhs: Int64, qformat: QFormat
) raises -> Int64:
    """Maximum of two canonical words in the same Q-format."""
    var validated = validate_qformat(qformat)
    require_raw_fits(lhs, validated)
    require_raw_fits(rhs, validated)
    return max(lhs, rhs)
