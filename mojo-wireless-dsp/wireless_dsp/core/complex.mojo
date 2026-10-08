"""Scalar complex arithmetic with explicit component dtype.

The representation is split real/imaginary (two scalars). Interleaved and
split-IQ buffers are views layered above this value type; the arithmetic does
not prescribe a buffer layout.
"""

from std.math import isfinite, sqrt


struct Complex[dtype: DType](ImplicitlyCopyable, Equatable, Writable):
    """A scalar complex value suitable for readable reference kernels."""

    comptime element_type = Scalar[Self.dtype]
    var re: Self.element_type
    var im: Self.element_type

    @always_inline
    def __init__(out self, re: Self.element_type, im: Self.element_type = 0):
        self.re = re
        self.im = im

    @always_inline
    def __eq__(self, rhs: Self) -> Bool:
        return Bool((self.re == rhs.re) and (self.im == rhs.im))

    def write_to(self, mut writer: Some[Writer]):
        writer.write("(", self.re, ", ", self.im, ")")

    @always_inline
    def __add__(self, rhs: Self) -> Self:
        return Self(self.re + rhs.re, self.im + rhs.im)

    @always_inline
    def __sub__(self, rhs: Self) -> Self:
        return Self(self.re - rhs.re, self.im - rhs.im)

    @always_inline
    def __neg__(self) -> Self:
        return Self(-self.re, -self.im)

    @always_inline
    def __mul__(self, rhs: Self) -> Self:
        return Self(
            self.re * rhs.re - self.im * rhs.im,
            self.re * rhs.im + self.im * rhs.re,
        )

    @always_inline
    def conjugate(self) -> Self:
        return Self(self.re, -self.im)

    @always_inline
    def magnitude_squared(self) -> Self.element_type:
        """Return ``re*re + im*im`` in the component dtype.

        Like any squared floating-point quantity, the exact result can exceed
        the dtype range (infinity) or fall below it (zero).  Use ``magnitude``
        or ``normalized`` when only a norm or direction is required.
        """
        return self.re * self.re + self.im * self.im

    @always_inline
    def magnitude(self) -> Self.element_type:
        """Return a scale-stable Euclidean magnitude.

        The largest component is factored out before squaring, so a finite
        representable norm is not spuriously converted to infinity or zero.
        A mathematically unrepresentable norm retains IEEE overflow behavior.
        """
        var scale = abs(self.re)
        var absolute_imaginary = abs(self.im)
        if absolute_imaginary > scale:
            scale = absolute_imaginary
        if scale == 0 or not isfinite(scale):
            return scale
        var scaled_real = self.re / scale
        var scaled_imaginary = self.im / scale
        return scale * sqrt(
            scaled_real * scaled_real + scaled_imaginary * scaled_imaginary
        )

    @always_inline
    def normalized(self) raises -> Self:
        """Return a unit-magnitude value without squaring unscaled components.

        Finite zero maps to zero.  Non-finite components are rejected because
        neither their direction nor a useful unit-vector result is defined.
        Scaling by the largest component keeps every intermediate in ``[0, 1]``
        even when a finite input's direct squared magnitude overflows or
        underflows its component dtype.
        """
        if not isfinite(self.re) or not isfinite(self.im):
            raise Error("complex normalization requires finite components")

        var scale = abs(self.re)
        var absolute_imaginary = abs(self.im)
        if absolute_imaginary > scale:
            scale = absolute_imaginary
        if scale == 0:
            return Self(0, 0)

        var scaled_real = self.re / scale
        var scaled_imaginary = self.im / scale
        var scaled_magnitude = sqrt(
            scaled_real * scaled_real + scaled_imaginary * scaled_imaginary
        )
        if not isfinite(scaled_magnitude) or scaled_magnitude == 0:
            raise Error("complex normalization magnitude is not representable")
        return Self(
            scaled_real / scaled_magnitude,
            scaled_imaginary / scaled_magnitude,
        )


@always_inline
def complex_mac[dtype: DType](
    acc: Complex[dtype], a: Complex[dtype], b: Complex[dtype]
) -> Complex[dtype]:
    """Return ``acc + a*b`` without changing the defined operation order."""
    return acc + a * b


comptime Complex32 = Complex[DType.float32]
comptime Complex64 = Complex[DType.float64]
