"""Bit-exact complex fixed-point multiply/accumulate primitives."""

from .quantization import (
    QFormat,
    narrow_raw,
    require_raw_fits,
    rescale_raw,
    validate_qformat,
)


struct ComplexRaw(ImplicitlyCopyable, Equatable, Writable):
    """Raw signed I/Q pair; interpretation is supplied by a ``QFormat``."""

    var re: Int64
    var im: Int64

    def __init__(out self, re: Int64 = 0, im: Int64 = 0):
        self.re = re
        self.im = im

    def __eq__(self, rhs: Self) -> Bool:
        return self.re == rhs.re and self.im == rhs.im

    def write_to(self, mut writer: Some[Writer]):
        writer.write("(", self.re, ", ", self.im, ")")


def require_complex_fits(value: ComplexRaw, qformat: QFormat) raises:
    require_raw_fits(value.re, qformat)
    require_raw_fits(value.im, qformat)


def complex_conjugate_raw(
    value: ComplexRaw, qformat: QFormat
) raises -> ComplexRaw:
    """Conjugate with the declared overflow policy at the imaginary port.

    A two's-complement minimum has no positive counterpart in the same
    format, so saturation maps it to ``max_raw`` while wrap maps it back to
    ``min_raw``.
    """
    var validated = validate_qformat(qformat)
    require_complex_fits(value, validated)
    return ComplexRaw(value.re, narrow_raw(-value.im, validated))


def complex_mul_raw(
    lhs: ComplexRaw,
    lhs_format: QFormat,
    rhs: ComplexRaw,
    rhs_format: QFormat,
    output_format: QFormat,
) raises -> ComplexRaw:
    """Complex multiply with one rounding/narrowing boundary per component."""
    var validated_lhs = validate_qformat(lhs_format)
    var validated_rhs = validate_qformat(rhs_format)
    var validated_output = validate_qformat(output_format)
    if validated_lhs.storage_bits > 31 or validated_rhs.storage_bits > 31:
        raise Error("bit-exact Int64 complex operands are limited to 31 bits")
    require_complex_fits(lhs, validated_lhs)
    require_complex_fits(rhs, validated_rhs)
    var product_fraction = (
        validated_lhs.fraction_bits + validated_rhs.fraction_bits
    )
    var real_wide = lhs.re * rhs.re - lhs.im * rhs.im
    var imag_wide = lhs.re * rhs.im + lhs.im * rhs.re
    return ComplexRaw(
        rescale_raw(real_wide, product_fraction, validated_output),
        rescale_raw(imag_wide, product_fraction, validated_output),
    )


def complex_mac_raw(
    accumulator: ComplexRaw,
    lhs: ComplexRaw,
    lhs_format: QFormat,
    rhs: ComplexRaw,
    rhs_format: QFormat,
    accumulator_format: QFormat,
) raises -> ComplexRaw:
    """Compute ``acc + lhs*rhs`` with a wide multiply and MAC-stage narrow.

    The real and imaginary product sums are rounded only after both partial
    products are combined.  The accumulator is then narrowed after this MAC,
    matching a registered saturating/wrapping hardware accumulator.
    """
    var validated_lhs = validate_qformat(lhs_format)
    var validated_rhs = validate_qformat(rhs_format)
    var validated_accumulator = validate_qformat(accumulator_format)
    require_complex_fits(accumulator, validated_accumulator)
    if validated_lhs.storage_bits > 31 or validated_rhs.storage_bits > 31:
        raise Error("bit-exact Int64 complex operands are limited to 31 bits")
    require_complex_fits(lhs, validated_lhs)
    require_complex_fits(rhs, validated_rhs)
    var product_fraction = (
        validated_lhs.fraction_bits + validated_rhs.fraction_bits
    )
    var product_re = rescale_raw(
        lhs.re * rhs.re - lhs.im * rhs.im,
        product_fraction,
        validated_accumulator,
    )
    var product_im = rescale_raw(
        lhs.re * rhs.im + lhs.im * rhs.re,
        product_fraction,
        validated_accumulator,
    )
    return ComplexRaw(
        narrow_raw(accumulator.re + product_re, validated_accumulator),
        narrow_raw(accumulator.im + product_im, validated_accumulator),
    )


def complex_mac_conjugate_raw(
    accumulator: ComplexRaw,
    lhs: ComplexRaw,
    lhs_format: QFormat,
    rhs: ComplexRaw,
    rhs_format: QFormat,
    accumulator_format: QFormat,
) raises -> ComplexRaw:
    """Compute ``acc + conj(lhs)*rhs`` for correlation and MIMO dot products."""
    var validated_lhs = validate_qformat(lhs_format)
    var validated_rhs = validate_qformat(rhs_format)
    var validated_accumulator = validate_qformat(accumulator_format)
    require_complex_fits(accumulator, validated_accumulator)
    if validated_lhs.storage_bits > 31 or validated_rhs.storage_bits > 31:
        raise Error("bit-exact Int64 complex operands are limited to 31 bits")
    require_complex_fits(lhs, validated_lhs)
    require_complex_fits(rhs, validated_rhs)
    var product_fraction = (
        validated_lhs.fraction_bits + validated_rhs.fraction_bits
    )
    var product_re = rescale_raw(
        lhs.re * rhs.re + lhs.im * rhs.im,
        product_fraction,
        validated_accumulator,
    )
    var product_im = rescale_raw(
        lhs.re * rhs.im - lhs.im * rhs.re,
        product_fraction,
        validated_accumulator,
    )
    return ComplexRaw(
        narrow_raw(accumulator.re + product_re, validated_accumulator),
        narrow_raw(accumulator.im + product_im, validated_accumulator),
    )
