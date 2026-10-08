"""Bit-explicit signed fixed-point reference arithmetic."""

comptime ROUND_TOWARD_ZERO = 0
comptime ROUND_NEAREST_AWAY = 1
comptime OVERFLOW_WRAP = 0
comptime OVERFLOW_SATURATE = 1


struct Fixed[
    fraction_bits: Int,
    storage_bits: Int = 16,
    rounding_mode: Int = ROUND_NEAREST_AWAY,
    overflow_mode: Int = OVERFLOW_SATURATE,
](Copyable, Equatable, Movable):
    """Signed two's-complement fixed point stored canonically in Int64.

    ``storage_bits`` controls observable narrowing (2..32). Multiplication
    uses an Int64 product and then rescales once. Operations narrow after each
    public arithmetic operation, making this usable as a bit-exact oracle for
    matching hardware stage boundaries.
    """

    comptime scale = Int64(1) << Int64(Self.fraction_bits)
    comptime min_raw = -(Int64(1) << Int64(Self.storage_bits - 1))
    comptime max_raw = (Int64(1) << Int64(Self.storage_bits - 1)) - 1
    var raw: Int64

    def __init__(out self, *, raw: Int64):
        # 32 bits guarantees that every raw*raw product fits Int64.
        comptime assert Self.storage_bits >= 2 and Self.storage_bits <= 32
        comptime assert (
            Self.fraction_bits >= 0
            and Self.fraction_bits < Self.storage_bits
        )
        self.raw = Self._narrow(raw)

    @staticmethod
    def _narrow(value: Int64) -> Int64:
        comptime if Self.overflow_mode == OVERFLOW_SATURATE:
            if value > Self.max_raw:
                return Self.max_raw
            if value < Self.min_raw:
                return Self.min_raw
            return value
        else:
            comptime assert Self.overflow_mode == OVERFLOW_WRAP
            comptime modulus = Int64(1) << Int64(Self.storage_bits)
            var wrapped = (value - Self.min_raw) % modulus
            if wrapped < 0:
                wrapped += modulus
            return wrapped + Self.min_raw

    @staticmethod
    def from_int(value: Int64) -> Self:
        # Multiplying an arbitrary Int64 by the binary scale first can
        # overflow before the target format gets a chance to saturate or
        # wrap.  Decide saturation in integer units, or reduce the integer
        # modulo the portion that survives the target word, before scaling.
        comptime if Self.overflow_mode == OVERFLOW_SATURATE:
            comptime maximum_integer = Self.max_raw // Self.scale
            comptime minimum_integer = Self.min_raw // Self.scale
            if value > maximum_integer:
                return Self(raw=Self.max_raw)
            if value < minimum_integer:
                return Self(raw=Self.min_raw)
            return Self(raw=value * Self.scale)
        else:
            comptime assert Self.overflow_mode == OVERFLOW_WRAP
            comptime surviving_integer_modulus = (
                Int64(1)
                << Int64(Self.storage_bits - Self.fraction_bits)
            )
            var reduced = value % surviving_integer_modulus
            return Self(raw=reduced * Self.scale)

    def to_float64(self) -> Float64:
        return Float64(self.raw) / Float64(Self.scale)

    def __eq__(self, rhs: Self) -> Bool:
        return self.raw == rhs.raw

    def __add__(self, rhs: Self) -> Self:
        return Self(raw=self.raw + rhs.raw)

    def __sub__(self, rhs: Self) -> Self:
        return Self(raw=self.raw - rhs.raw)

    def __neg__(self) -> Self:
        return Self(raw=-self.raw)

    def __mul__(self, rhs: Self) -> Self:
        var product = self.raw * rhs.raw
        comptime if Self.fraction_bits == 0:
            return Self(raw=product)
        else:
            comptime if Self.rounding_mode == ROUND_NEAREST_AWAY:
                comptime half = Int64(1) << Int64(Self.fraction_bits - 1)
                if product >= 0:
                    return Self(
                        raw=(product + half) >> Int64(Self.fraction_bits)
                    )
                return Self(
                    raw=-(((-product) + half) >> Int64(Self.fraction_bits))
                )
            else:
                comptime assert Self.rounding_mode == ROUND_TOWARD_ZERO
                if product < 0:
                    return Self(raw=-((-product) >> Int64(Self.fraction_bits)))
                return Self(raw=product >> Int64(Self.fraction_bits))

    def rescale[new_fraction_bits: Int](self) -> Fixed[
        new_fraction_bits,
        Self.storage_bits,
        Self.rounding_mode,
        Self.overflow_mode,
    ]:
        comptime if new_fraction_bits >= Self.fraction_bits:
            return Fixed[
                new_fraction_bits,
                Self.storage_bits,
                Self.rounding_mode,
                Self.overflow_mode,
            ](raw=self.raw << Int64(new_fraction_bits - Self.fraction_bits))
        else:
            comptime shift = Self.fraction_bits - new_fraction_bits
            var value = self.raw
            comptime if Self.rounding_mode == ROUND_NEAREST_AWAY:
                comptime half = Int64(1) << Int64(shift - 1)
                if value < 0:
                    return Fixed[
                        new_fraction_bits,
                        Self.storage_bits,
                        Self.rounding_mode,
                        Self.overflow_mode,
                    ](raw=-(((-value) + half) >> Int64(shift)))
                value += half
            comptime if Self.rounding_mode == ROUND_TOWARD_ZERO:
                if value < 0:
                    value = -((-value) >> Int64(shift))
                    return Fixed[
                        new_fraction_bits,
                        Self.storage_bits,
                        Self.rounding_mode,
                        Self.overflow_mode,
                    ](raw=value)
            return Fixed[
                new_fraction_bits,
                Self.storage_bits,
                Self.rounding_mode,
                Self.overflow_mode,
            ](raw=value >> Int64(shift))
