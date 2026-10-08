"""Readable Gray-coded BPSK and square-QAM mapping and demapping."""

from std.collections import Span
from std.math import exp, isfinite, log, sqrt
from std.utils.numerics import inf
from wireless_dsp.core import Complex64

def _is_supported(bits_per_symbol: Int) -> Bool:
    return bits_per_symbol >= 1 and bits_per_symbol <= 12 and (bits_per_symbol == 1 or bits_per_symbol % 2 == 0)

def _gray_to_binary(gray: Int) -> Int:
    var value = gray
    var shifted = gray >> 1
    while shifted != 0:
        value ^= shifted
        shifted >>= 1
    return value

def _binary_to_gray(value: Int) -> Int:
    return value ^ (value >> 1)

def _axis_level(gray: Int, axis_bits: Int) -> Float64:
    # 3GPP/IEEE Gray labeling: an all-zero axis label is the largest
    # positive amplitude; increasing binary-reflected Gray index walks down.
    return Float64(((1 << axis_bits) - 1) - 2 * _gray_to_binary(gray))

def _normalization(bits_per_symbol: Int) -> Float64:
    if bits_per_symbol == 1:
        return 1.0
    return sqrt((2.0 / 3.0) * Float64((1 << bits_per_symbol) - 1))

def _symbol_from_label(label: Int, bits_per_symbol: Int) -> Complex64:
    if bits_per_symbol == 1:
        return Complex64(1.0 if label == 0 else -1.0, 0.0)
    var axis_bits = bits_per_symbol // 2
    var mask = (1 << axis_bits) - 1
    var scale = _normalization(bits_per_symbol)
    return Complex64(
        _axis_level((label >> axis_bits) & mask, axis_bits) / scale,
        _axis_level(label & mask, axis_bits) / scale,
    )

def _scaled_product_or_limit(
    lhs: Float64, rhs: Float64, denominator: Float64
) -> Float64:
    """Evaluate ``lhs * rhs / denominator`` without a bad intermediate.

    All callers provide finite factors and a finite positive denominator.  A
    non-zero finite result is tried in each algebraically equivalent order.
    If the real result lies beyond the Float64 range, signed infinity is
    returned as a sentinel; if it lies below that range, signed zero is
    returned.  This lets soft demappers reject an unrepresentable output while
    the saturating integer quantizer can still map an overflowing product to
    its declared clip value.
    """
    if lhs == 0.0 or rhs == 0.0:
        return lhs * rhs

    comptime minimum_normal = 2.2250738585072014e-308
    var product = lhs * rhs
    if isfinite(product) and abs(product) >= minimum_normal:
        var direct = product / denominator
        if isfinite(direct) and direct != 0.0:
            return direct

    var lhs_ratio = lhs / denominator
    if isfinite(lhs_ratio) and abs(lhs_ratio) >= minimum_normal:
        var divide_lhs_first = lhs_ratio * rhs
        if isfinite(divide_lhs_first) and divide_lhs_first != 0.0:
            return divide_lhs_first

    var rhs_ratio = rhs / denominator
    if isfinite(rhs_ratio) and abs(rhs_ratio) >= minimum_normal:
        var divide_rhs_first = lhs * rhs_ratio
        if isfinite(divide_rhs_first) and divide_rhs_first != 0.0:
            return divide_rhs_first

    # If every safe first intermediate is subnormal, retain any representable
    # final result as a last resort.  Normal-first routes above avoid magnifying
    # premature subnormal rounding whenever an equivalent ordering permits it.
    var direct = product / denominator
    if isfinite(direct) and direct != 0.0:
        return direct
    var divide_lhs_first = lhs_ratio * rhs
    if isfinite(divide_lhs_first) and divide_lhs_first != 0.0:
        return divide_lhs_first
    var divide_rhs_first = lhs * rhs_ratio
    if isfinite(divide_rhs_first) and divide_rhs_first != 0.0:
        return divide_rhs_first

    # The three possible operation orders failed only because an intermediate
    # overflowed or underflowed.  Compare magnitudes without multiplication to
    # distinguish those cases.  ``denominator / abs(rhs)`` may itself become
    # zero or infinity; both outcomes make the comparison unambiguous.
    var negative = (lhs < 0.0) != (rhs < 0.0)
    var at_least_one = abs(lhs) >= denominator / abs(rhs)
    if at_least_one:
        return -inf[DType.float64]() if negative else inf[DType.float64]()
    return -0.0 if negative else 0.0

def _finite_scaled_product(
    lhs: Float64, rhs: Float64, denominator: Float64
) raises -> Float64:
    """Return a representable scaled product or reject overflow/underflow."""
    var result = _scaled_product_or_limit(lhs, rhs, denominator)
    if not isfinite(result) or (
        result == 0.0 and lhs != 0.0 and rhs != 0.0
    ):
        raise Error("QAM LLR is not representable as Float64")
    return result

def _nearest_axis_level(
    sample: Float64,
    axis_bits: Int,
    shift: Int,
    bit_value: Int,
    scale: Float64,
) -> Float64:
    """Find a bit-constrained nearest PAM level without squaring distance."""
    var nearest = 0.0
    var nearest_distance = inf[DType.float64]()
    var lowest = inf[DType.float64]()
    var highest = -inf[DType.float64]()
    for gray in range(1 << axis_bits):
        if ((gray >> shift) & 1) != bit_value:
            continue
        var level = _axis_level(gray, axis_bits) / scale
        lowest = min(lowest, level)
        highest = max(highest, level)
        var distance = abs(sample - level)
        if distance < nearest_distance:
            nearest_distance = distance
            nearest = level
    # At very large magnitudes, ``sample - level`` rounds to the same Float64
    # for every bounded constellation point.  Endpoint selection remains
    # exact and avoids relying on those indistinguishable rounded distances.
    if sample >= highest:
        return highest
    if sample <= lowest:
        return lowest
    return nearest

def _axis_maxlog_llr(
    sample: Float64,
    axis_bits: Int,
    shift: Int,
    scale: Float64,
    noise_variance: Float64,
) raises -> Float64:
    """Compute a bit LLR from its two nearest levels without squared terms."""
    var nearest_zero = _nearest_axis_level(
        sample, axis_bits, shift, 0, scale
    )
    var nearest_one = _nearest_axis_level(
        sample, axis_bits, shift, 1, scale
    )
    var level_delta = nearest_zero - nearest_one

    # (x-o)^2 - (x-z)^2 = (z-o) * ((x-o) + (x-z)).  The
    # factored form avoids both squared-distance overflow and catastrophic
    # cancellation.  Only the sum can overflow for a finite x.
    var from_one = sample - nearest_one
    var from_zero = sample - nearest_zero
    var doubled_centered_sample = from_one + from_zero
    if isfinite(doubled_centered_sample):
        return _finite_scaled_product(
            level_delta, doubled_centered_sample, noise_variance
        )

    # Evaluate the same identity as two scale-safe terms when 2*x is outside
    # Float64 even though the final division by N0 may make the LLR finite.
    var leading = _scaled_product_or_limit(
        2.0 * level_delta, sample, noise_variance
    )
    var correction = _scaled_product_or_limit(
        -level_delta, nearest_zero + nearest_one, noise_variance
    )
    if not isfinite(leading) or not isfinite(correction):
        raise Error("QAM LLR is not representable as Float64")
    var result = leading + correction
    if not isfinite(result) or result == 0.0:
        raise Error("QAM LLR is not representable as Float64")
    return result

def _relative_axis_metric(
    sample: Float64,
    level: Float64,
    nearest: Float64,
    noise_variance: Float64,
) -> Float64:
    """Return ``((x-level)^2 - (x-nearest)^2) / N0`` stably."""
    if level == nearest:
        return 0.0
    var level_delta = nearest - level
    var from_level = sample - level
    var from_nearest = sample - nearest
    var doubled_centered_sample = from_level + from_nearest
    var metric: Float64
    if isfinite(doubled_centered_sample):
        metric = _scaled_product_or_limit(
            level_delta, doubled_centered_sample, noise_variance
        )
    else:
        var leading = _scaled_product_or_limit(
            2.0 * level_delta, sample, noise_variance
        )
        var correction = _scaled_product_or_limit(
            -level_delta, level + nearest, noise_variance
        )
        if not isfinite(leading) or not isfinite(correction):
            return inf[DType.float64]()
        metric = leading + correction
    if not isfinite(metric):
        return inf[DType.float64]()
    # ``nearest`` is selected by absolute distance, hence the mathematical
    # metric is non-negative.  Clamp only negative roundoff at a tie.
    return max(0.0, metric)

def _axis_relative_log_sum(
    sample: Float64,
    axis_bits: Int,
    shift: Int,
    bit_value: Int,
    scale: Float64,
    noise_variance: Float64,
    nearest: Float64,
) -> Float64:
    """Log-sum-exp after subtracting a bit group's nearest-axis metric."""
    var relative_sum = 0.0
    for gray in range(1 << axis_bits):
        if ((gray >> shift) & 1) != bit_value:
            continue
        var level = _axis_level(gray, axis_bits) / scale
        var metric = _relative_axis_metric(
            sample, level, nearest, noise_variance
        )
        if isfinite(metric):
            relative_sum += exp(-metric)
    # The nearest level contributes exactly exp(0) == 1.
    return log(relative_sum)

def _nearest_axis_gray(sample: Float64, axis_bits: Int, scale: Float64) -> Int:
    """Slice one normalized PAM axis, then convert its binary index to Gray."""
    var maximum = (1 << axis_bits) - 1
    var maximum_level = Float64(maximum) / scale
    if sample >= maximum_level:
        return 0
    if sample <= -maximum_level:
        return _binary_to_gray(maximum)
    var coordinate = (Float64(maximum) - sample * scale) * 0.5
    coordinate = max(0.0, min(Float64(maximum), coordinate))
    var binary_index = min(maximum, Int(coordinate + 0.5))
    return _binary_to_gray(binary_index)

def qam_map(bits: Span[UInt8, ...], bits_per_symbol: Int) raises -> List[Complex64]:
    """Map MSB-first labels using binary-reflected Gray coding per axis."""
    if not _is_supported(bits_per_symbol):
        raise Error("QAM bits per symbol must be 1 or an even value from 2 to 12")
    if len(bits) % bits_per_symbol != 0:
        raise Error("bit count must be divisible by bits per symbol")
    var result = List[Complex64](capacity=len(bits) // bits_per_symbol)
    for symbol_index in range(len(bits) // bits_per_symbol):
        var label = 0
        for bit_index in range(bits_per_symbol):
            var bit = Int(bits[symbol_index * bits_per_symbol + bit_index])
            if bit != 0 and bit != 1:
                raise Error("bits must be zero or one")
            label = (label << 1) | bit
        result.append(_symbol_from_label(label, bits_per_symbol))
    return result^

def qam_demap_hard(samples: Span[Complex64, ...], bits_per_symbol: Int) raises -> List[UInt8]:
    if not _is_supported(bits_per_symbol):
        raise Error("unsupported QAM order")
    var result = List[UInt8](capacity=len(samples) * bits_per_symbol)
    for sample_index in range(len(samples)):
        if (
            not isfinite(samples[sample_index].re)
            or not isfinite(samples[sample_index].im)
        ):
            raise Error("QAM hard-demapper input must be finite")
        var best_label = 0 if samples[sample_index].re >= 0.0 else 1
        if bits_per_symbol != 1:
            var axis_bits = bits_per_symbol // 2
            var scale = _normalization(bits_per_symbol)
            var i_gray = _nearest_axis_gray(samples[sample_index].re, axis_bits, scale)
            var q_gray = _nearest_axis_gray(samples[sample_index].im, axis_bits, scale)
            best_label = (i_gray << axis_bits) | q_gray
        for bit_index in range(bits_per_symbol):
            result.append(UInt8((best_label >> (bits_per_symbol - bit_index - 1)) & 1))
    return result^

def qam_demapper_llr_maxlog(
    samples: Span[Complex64, ...], bits_per_symbol: Int, noise_variance: Float64
) raises -> List[Float64]:
    """Return finite max-log LLRs with positive sign indicating bit zero.

    A finite input whose mathematical LLR is outside the Float64 range is
    rejected instead of returning infinity or a wrapped-sign artifact.
    """
    if not _is_supported(bits_per_symbol):
        raise Error("unsupported QAM order")
    if not isfinite(noise_variance) or noise_variance <= 0.0:
        raise Error("noise variance must be finite and positive")
    var result = List[Float64](capacity=len(samples) * bits_per_symbol)
    for sample_index in range(len(samples)):
        if (
            not isfinite(samples[sample_index].re)
            or not isfinite(samples[sample_index].im)
        ):
            raise Error("QAM soft-demapper input must be finite")
        if bits_per_symbol == 1:
            result.append(
                _finite_scaled_product(
                    4.0, samples[sample_index].re, noise_variance
                )
            )
            continue
        var axis_bits = bits_per_symbol // 2
        var scale = _normalization(bits_per_symbol)
        for bit_index in range(bits_per_symbol):
            var local_bit = (
                bit_index if bit_index < axis_bits else bit_index - axis_bits
            )
            var shift = axis_bits - local_bit - 1
            var sample = (
                samples[sample_index].re
                if bit_index < axis_bits
                else samples[sample_index].im
            )
            result.append(
                _axis_maxlog_llr(
                    sample, axis_bits, shift, scale, noise_variance
                )
            )
    return result^

def qam_demapper_llr_exact(
    samples: Span[Complex64, ...], bits_per_symbol: Int, noise_variance: Float64
) raises -> List[Float64]:
    """Log-MAP LLR evaluated by stable per-axis log-sum-exp enumeration.

    A finite input whose mathematical LLR is outside the Float64 range is
    rejected instead of returning a non-finite value.
    """
    if not _is_supported(bits_per_symbol):
        raise Error("unsupported QAM order")
    if not isfinite(noise_variance) or noise_variance <= 0.0:
        raise Error("noise variance must be finite and positive")
    var result = List[Float64](capacity=len(samples) * bits_per_symbol)
    for sample_index in range(len(samples)):
        if (
            not isfinite(samples[sample_index].re)
            or not isfinite(samples[sample_index].im)
        ):
            raise Error("QAM soft-demapper input must be finite")
        if bits_per_symbol == 1:
            result.append(
                _finite_scaled_product(
                    4.0, samples[sample_index].re, noise_variance
                )
            )
            continue
        var axis_bits = bits_per_symbol // 2
        var scale = _normalization(bits_per_symbol)
        for bit_index in range(bits_per_symbol):
            var local_bit = (
                bit_index if bit_index < axis_bits else bit_index - axis_bits
            )
            var shift = axis_bits - local_bit - 1
            var sample = (
                samples[sample_index].re
                if bit_index < axis_bits
                else samples[sample_index].im
            )
            var nearest_zero = _nearest_axis_level(
                sample, axis_bits, shift, 0, scale
            )
            var nearest_one = _nearest_axis_level(
                sample, axis_bits, shift, 1, scale
            )
            var maxlog = _axis_maxlog_llr(
                sample, axis_bits, shift, scale, noise_variance
            )
            var log_sum_zero = _axis_relative_log_sum(
                sample,
                axis_bits,
                shift,
                0,
                scale,
                noise_variance,
                nearest_zero,
            )
            var log_sum_one = _axis_relative_log_sum(
                sample,
                axis_bits,
                shift,
                1,
                scale,
                noise_variance,
                nearest_one,
            )
            var llr = maxlog + log_sum_zero - log_sum_one
            if not isfinite(llr):
                raise Error("QAM LLR is not representable as Float64")
            result.append(llr)
    return result^

def qam_demapper_llr_piecewise(
    samples: Span[Complex64, ...], bits_per_symbol: Int, noise_variance: Float64
) raises -> List[Float64]:
    """Axis-factorized piecewise max-log LLR for BPSK and square QAM.

    Unlike the full-constellation oracle, this searches only the PAM levels on
    the axis carrying the requested bit.  The unconstrained orthogonal-axis
    minimum cancels from the LLR, so the result is mathematically identical.
    Unrepresentable finite-input LLRs are rejected.
    """
    if not _is_supported(bits_per_symbol):
        raise Error("unsupported QAM order")
    if not isfinite(noise_variance) or noise_variance <= 0.0:
        raise Error("noise variance must be finite and positive")
    var result = List[Float64](capacity=len(samples) * bits_per_symbol)
    if bits_per_symbol == 1:
        for i in range(len(samples)):
            if not isfinite(samples[i].re) or not isfinite(samples[i].im):
                raise Error("QAM soft-demapper input must be finite")
            result.append(
                _finite_scaled_product(4.0, samples[i].re, noise_variance)
            )
        return result^

    var axis_bits = bits_per_symbol // 2
    var scale = _normalization(bits_per_symbol)
    for sample_index in range(len(samples)):
        if (
            not isfinite(samples[sample_index].re)
            or not isfinite(samples[sample_index].im)
        ):
            raise Error("QAM soft-demapper input must be finite")
        for bit_index in range(bits_per_symbol):
            var local_bit = bit_index if bit_index < axis_bits else bit_index - axis_bits
            var shift = axis_bits - local_bit - 1
            var sample = samples[sample_index].re if bit_index < axis_bits else samples[sample_index].im
            result.append(
                _axis_maxlog_llr(
                    sample, axis_bits, shift, scale, noise_variance
                )
            )
    return result^

def quantize_llr(
    llrs: Span[Float64, ...], *, scale: Float64, clip: Int
) raises -> List[Int]:
    """Round scaled LLRs to nearest integer and symmetrically saturate."""
    if not isfinite(scale) or scale <= 0.0 or clip < 1:
        raise Error("LLR quantizer requires finite positive scale and clip")
    var result = List[Int](capacity=len(llrs))
    for i in range(len(llrs)):
        if not isfinite(llrs[i]):
            raise Error("LLR quantizer input must be finite")
        var scaled = _scaled_product_or_limit(llrs[i], scale, 1.0)
        if not isfinite(scaled):
            result.append(clip if scaled > 0.0 else -clip)
            continue
        # Float64(Int.MAX) rounds upward to 2^63, while Int.MIN is exactly
        # representable.  Guard both conversion boundaries before adding the
        # rounding offset; the final integer clamp then remains exact even for
        # clip values above Float64's consecutive-integer range.
        if scaled >= Float64(Int.MAX):
            result.append(clip)
            continue
        if scaled <= Float64(Int.MIN):
            result.append(-clip)
            continue
        var rounded = Int(scaled + (0.5 if scaled >= 0.0 else -0.5))
        result.append(max(-clip, min(clip, rounded)))
    return result^

def hard_bits_from_llr(llrs: Span[Float64, ...]) -> List[UInt8]:
    var result = List[UInt8](capacity=len(llrs))
    for i in range(len(llrs)):
        result.append(UInt8(0) if llrs[i] >= 0.0 else UInt8(1))
    return result^
