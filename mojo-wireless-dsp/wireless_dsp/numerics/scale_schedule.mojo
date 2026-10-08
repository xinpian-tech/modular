"""Explicit per-stage fixed-point scaling schedules and raw traces."""

from std.collections import Span
from .quantization import (
    QFormat,
    narrow_raw,
    require_raw_fits,
    rescale_raw,
    rounded_shift_right,
    validate_qformat,
)
from .fixed import (
    ROUND_NEAREST_AWAY,
    OVERFLOW_SATURATE,
)


struct ScaleStage(ImplicitlyCopyable, Equatable):
    """The registered output Q-format of one hardware pipeline stage."""

    var output_format: QFormat
    var right_shift: Int

    def __init__(
        out self, output_format: QFormat, right_shift: Int = 0
    ) raises:
        if right_shift < 0 or right_shift > 61:
            raise Error("scale-stage right shift must be in [0, 61]")
        self.output_format = validate_qformat(output_format)
        self.right_shift = right_shift


struct ScaleTrace(Movable):
    """Raw output and Q-format metadata after every scheduled stage."""

    var values: List[Int64]
    var fraction_bits: List[Int]
    var storage_bits: List[Int]
    var right_shifts: List[Int]
    var rounding_modes: List[Int]
    var overflow_modes: List[Int]

    def __init__(
        out self,
        var values: List[Int64],
        var fraction_bits: List[Int],
        var storage_bits: List[Int],
        var right_shifts: List[Int],
        var rounding_modes: List[Int],
        var overflow_modes: List[Int],
    ):
        self.values = values^
        self.fraction_bits = fraction_bits^
        self.storage_bits = storage_bits^
        self.right_shifts = right_shifts^
        self.rounding_modes = rounding_modes^
        self.overflow_modes = overflow_modes^

    def __init__(
        out self,
        var values: List[Int64],
        var fraction_bits: List[Int],
        var storage_bits: List[Int],
        var right_shifts: List[Int],
    ):
        """Legacy constructor using the historical nearest/saturate modes."""
        var count = len(values)
        self.values = values^
        self.fraction_bits = fraction_bits^
        self.storage_bits = storage_bits^
        self.right_shifts = right_shifts^
        self.rounding_modes = List[Int](
            length=count, fill=ROUND_NEAREST_AWAY
        )
        self.overflow_modes = List[Int](
            length=count, fill=OVERFLOW_SATURATE
        )


def apply_scale_schedule(
    input_raw: Int64,
    input_format: QFormat,
    stages: Span[ScaleStage, ...],
) raises -> ScaleTrace:
    """Apply each rescale/narrow boundary and retain a bit-exact trace."""
    require_raw_fits(input_raw, input_format)
    var values = List[Int64](capacity=len(stages))
    var fraction_bits = List[Int](capacity=len(stages))
    var storage_bits = List[Int](capacity=len(stages))
    var right_shifts = List[Int](capacity=len(stages))
    var rounding_modes = List[Int](capacity=len(stages))
    var overflow_modes = List[Int](capacity=len(stages))
    var current = input_raw
    var current_fraction = input_format.fraction_bits
    for i in range(len(stages)):
        var stage = stages[i]
        var qformat = validate_qformat(stage.output_format)
        if stage.right_shift < 0 or stage.right_shift > 61:
            raise Error("mutated scale-stage right shift must be in [0, 61]")
        # Combining the binary-point conversion and post-stage shift makes
        # rounding/narrowing happen exactly once.  In particular, a protective
        # right shift occurs before saturation at the register boundary.
        if current_fraction > 61 - stage.right_shift:
            # The conceptual input binary point may reach 122 even though the
            # raw word remains Int64.  Evaluate its net right shift directly
            # instead of passing an artificial >61 fraction count to
            # ``rescale_raw``.
            var net_shift = (
                current_fraction
                + stage.right_shift
                - qformat.fraction_bits
            )
            var shifted: Int64
            if net_shift <= 61:
                shifted = rounded_shift_right(
                    current, net_shift, qformat.rounding_mode
                )
            else:
                var magnitude = (
                    -Int128(current) if current < 0 else Int128(current)
                )
                var divisor = Int128(1) << Int128(net_shift)
                var quotient = magnitude // divisor
                var remainder = magnitude % divisor
                if (
                    qformat.rounding_mode == ROUND_NEAREST_AWAY
                    and Int128(2) * remainder >= divisor
                ):
                    quotient += Int128(1)
                shifted = Int64(-quotient if current < 0 else quotient)
            current = narrow_raw(shifted, qformat)
        else:
            current = rescale_raw(
                current,
                current_fraction + stage.right_shift,
                qformat,
            )
        current_fraction = qformat.fraction_bits
        values.append(current)
        fraction_bits.append(current_fraction)
        storage_bits.append(qformat.storage_bits)
        right_shifts.append(stage.right_shift)
        rounding_modes.append(qformat.rounding_mode)
        overflow_modes.append(qformat.overflow_mode)
    return ScaleTrace(
        values^,
        fraction_bits^,
        storage_bits^,
        right_shifts^,
        rounding_modes^,
        overflow_modes^,
    )


def radix2_fft_scale_schedule(
    fft_size: Int,
    storage_bits: Int,
    initial_fraction_bits: Int,
    right_shift_each_stage: Bool = True,
) raises -> List[ScaleStage]:
    """Create the conventional radix-2 FFT register scaling schedule.

    With stage shifting enabled, each butterfly stage divides raw results by
    two while retaining the same binary-point position.
    """
    if fft_size < 2 or (fft_size & (fft_size - 1)) != 0:
        raise Error("FFT scale schedule requires a power-of-two size >= 2")
    _ = QFormat(storage_bits, initial_fraction_bits)
    var stage_count = 0
    var value = fft_size
    while value > 1:
        stage_count += 1
        value //= 2
    var result = List[ScaleStage](capacity=stage_count)
    for _ in range(stage_count):
        result.append(
            ScaleStage(
                QFormat(storage_bits, initial_fraction_bits),
                1 if right_shift_each_stage else 0,
            )
        )
    return result^
