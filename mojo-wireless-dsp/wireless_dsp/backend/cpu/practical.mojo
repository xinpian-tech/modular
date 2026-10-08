"""Practical Float32 kernels for CPU-bound wireless-DSP workloads.

This module complements the readable Float64 algorithms with deliberately
explicit production semantics:

* radix-2 FFT plans own reusable Float32 twiddles; forward transforms are
  unscaled and inverse transforms apply exactly one ``1/N`` scale;
* kernels never write through input spans and every out-of-place API returns
  fresh storage; distinct span arguments follow Mojo's non-aliasing call rule;
* native-width SIMD is used for complete FIR/correlation inner-loop vectors,
  followed by a scalar tail; no alignment beyond ``Float32`` is required;
* QAM LLRs are max-log values with positive sign meaning bit zero and
  ``noise_variance`` equal to the complex-sample variance ``E[|n|^2]``.

The kernels prioritize maintainable, deterministic behavior.  The Float64 DSP
and modem modules remain the numerical oracles used by differential tests.
"""

from std.collections import Span
from std.math import cos, isfinite, sin, sqrt
from std.sys.info import simd_width_of
from std.utils.numerics import inf
from wireless_dsp.core import Complex32


comptime _TWO_PI_F32 = Float32(6.283185307179586476925286766559)


struct FFTPlanF32(Movable):
    """Reusable twiddles for one Float32 radix-2 size and direction.

    A plan is immutable while a transform is executing and may be reused
    sequentially for any number of same-size transforms.  A forward plan is
    unscaled; an inverse plan applies exactly ``1 / size`` after the butterflies.
    """

    var size: Int
    var inverse: Bool
    var twiddles: List[Complex32]

    def __init__(
        out self, size: Int, inverse: Bool, var twiddles: List[Complex32]
    ):
        self.size = size
        self.inverse = inverse
        self.twiddles = twiddles^


def _validate_fft_size_f32(size: Int) raises:
    if size < 1 or (size & (size - 1)) != 0:
        raise Error("Float32 FFT length must be a positive power of two")


def _validate_fft_plan_f32(plan: FFTPlanF32) raises:
    _validate_fft_size_f32(plan.size)
    if len(plan.twiddles) != plan.size // 2:
        raise Error("Float32 FFT plan has an invalid twiddle count")


def make_fft_plan_f32(
    size: Int, *, inverse: Bool = False
) raises -> FFTPlanF32:
    """Create a reusable plan with ``size / 2`` direction-specific twiddles."""
    _validate_fft_size_f32(size)
    var twiddles = List[Complex32](capacity=size // 2)
    var direction = _TWO_PI_F32 if inverse else -_TWO_PI_F32
    for k in range(size // 2):
        var angle = direction * Float32(k) / Float32(size)
        twiddles.append(Complex32(cos(angle), sin(angle)))
    return FFTPlanF32(size, inverse, twiddles^)


def fft_in_place_f32_with_plan(
    mut data: List[Complex32], plan: FFTPlanF32
) raises:
    """Transform ``data`` in place using a matching borrowed plan.

    ``data`` must have exactly ``plan.size`` elements.  The list is the only
    mutated object; plan twiddles are read-only.  The caller must not arrange
    concurrent mutation or aliased mutable access to the same list.
    """
    if len(data) != plan.size:
        raise Error("Float32 FFT data length does not match its plan")
    _validate_fft_plan_f32(plan)

    var size = plan.size
    var reversed_index = 0
    for index in range(1, size):
        var bit = size >> 1
        while (reversed_index & bit) != 0:
            reversed_index ^= bit
            bit >>= 1
        reversed_index ^= bit
        if index < reversed_index:
            var temporary = data[index]
            data[index] = data[reversed_index]
            data[reversed_index] = temporary

    var stage_length = 2
    while stage_length <= size:
        var base = 0
        while base < size:
            for offset in range(stage_length // 2):
                var twiddle = plan.twiddles[offset * size // stage_length]
                var even = data[base + offset]
                var odd = data[base + offset + stage_length // 2] * twiddle
                data[base + offset] = even + odd
                data[base + offset + stage_length // 2] = even - odd
            base += stage_length
        stage_length <<= 1

    if plan.inverse:
        var scale = Float32(1.0) / Float32(size)
        for index in range(size):
            data[index] = Complex32(
                data[index].re * scale, data[index].im * scale
            )


def fft_f32(values: Span[Complex32, ...]) raises -> List[Complex32]:
    """Return an unscaled Float32 FFT in fresh, non-aliasing storage."""
    var result = List[Complex32](capacity=len(values))
    for index in range(len(values)):
        result.append(Complex32(values[index].re, values[index].im))
    var plan = make_fft_plan_f32(len(result))
    fft_in_place_f32_with_plan(result, plan)
    return result^


def ifft_f32(values: Span[Complex32, ...]) raises -> List[Complex32]:
    """Return a ``1/N``-scaled Float32 inverse FFT in fresh storage."""
    var result = List[Complex32](capacity=len(values))
    for index in range(len(values)):
        result.append(Complex32(values[index].re, values[index].im))
    var plan = make_fft_plan_f32(len(result), inverse=True)
    fft_in_place_f32_with_plan(result, plan)
    return result^


def fft_batch_f32_with_plan(
    values: Span[Complex32, ...], plan: FFTPlanF32
) raises -> List[Complex32]:
    """Transform a flat contiguous batch with one reusable plan.

    The input length must be divisible by ``plan.size``.  Empty batches are
    valid.  Each transform has the plan's direction and scale semantics, and
    the returned flat list never aliases the input.
    """
    _validate_fft_plan_f32(plan)
    if len(values) % plan.size != 0:
        raise Error("Float32 FFT batch length must be divisible by plan size")
    var result = List[Complex32](capacity=len(values))
    for batch in range(len(values) // plan.size):
        var one = List[Complex32](capacity=plan.size)
        for index in range(plan.size):
            var value = values[batch * plan.size + index]
            one.append(Complex32(value.re, value.im))
        fft_in_place_f32_with_plan(one, plan)
        for value in one:
            result.append(Complex32(value.re, value.im))
    return result^


def fft_batch_f32(
    values: Span[Complex32, ...], transform_size: Int, *, inverse: Bool = False
) raises -> List[Complex32]:
    """Plan once and transform a flat batch of equal-length Float32 vectors."""
    var plan = make_fft_plan_f32(transform_size, inverse=inverse)
    return fft_batch_f32_with_plan(values, plan)


struct FIRPlanF32(Movable):
    """Reusable real-FIR coefficients in convolution and SIMD window order."""

    var taps: List[Float32]
    var reversed_taps: List[Float32]

    def __init__(
        out self, var taps: List[Float32], var reversed_taps: List[Float32]
    ):
        self.taps = taps^
        self.reversed_taps = reversed_taps^


def _validate_fir_plan_f32(plan: FIRPlanF32) raises:
    var tap_count = len(plan.taps)
    if tap_count < 1 or len(plan.reversed_taps) != tap_count:
        raise Error("Float32 FIR plan has invalid coefficient storage")
    for index in range(tap_count):
        if (
            not isfinite(plan.taps[index])
            or not isfinite(plan.reversed_taps[index])
        ):
            raise Error("Float32 FIR plan coefficients must be finite")


def make_fir_plan_f32(taps: Span[Float32, ...]) raises -> FIRPlanF32:
    """Copy finite non-empty taps into reusable, non-aliasing storage."""
    if len(taps) < 1:
        raise Error("Float32 FIR requires at least one tap")
    var owned = List[Float32](capacity=len(taps))
    var reversed_taps = List[Float32](capacity=len(taps))
    for index in range(len(taps)):
        if not isfinite(taps[index]):
            raise Error("Float32 FIR taps must be finite")
        owned.append(taps[index])
        reversed_taps.append(taps[len(taps) - index - 1])
    return FIRPlanF32(owned^, reversed_taps^)


def fir_real_f32_with_plan(
    signal: Span[Float32, ...], plan: FIRPlanF32
) raises -> List[Float32]:
    """Apply a zero-state causal FIR using native-width Float32 SIMD.

    Output length equals signal length.  The prefix, where fewer than all taps
    overlap the signal, is evaluated scalar; every complete window uses native
    vectors plus a scalar tail.  Inputs are only read and output storage is
    fresh.  As with other multi-span Mojo APIs, distinct span arguments must
    satisfy the language's exclusivity rule at the call boundary.
    """
    _validate_fir_plan_f32(plan)
    var tap_count = len(plan.taps)
    var output = List[Float32](capacity=len(signal))
    comptime width = simd_width_of[DType.float32]()
    for sample_index in range(len(signal)):
        if sample_index + 1 < tap_count:
            var prefix = Float32(0.0)
            for tap_index in range(sample_index + 1):
                prefix += plan.taps[tap_index] * signal[sample_index - tap_index]
            output.append(prefix)
            continue

        var vectors = SIMD[DType.float32, width](0.0)
        var window_start = sample_index + 1 - tap_count
        var tap_index = 0
        while tap_index + Int(width) <= tap_count:
            var samples = signal.unsafe_ptr().unsafe_load[width=width](
                window_start + tap_index
            )
            var coefficients = (
                plan.reversed_taps.unsafe_ptr().unsafe_load[width=width](tap_index)
            )
            vectors += samples * coefficients
            tap_index += Int(width)
        var value = vectors.reduce_add()
        while tap_index < tap_count:
            value += (
                signal[window_start + tap_index]
                * plan.reversed_taps[tap_index]
            )
            tap_index += 1
        output.append(value)
    return output^


def fir_real_f32(
    signal: Span[Float32, ...], taps: Span[Float32, ...]
) raises -> List[Float32]:
    """Create a plan once and return a zero-state causal real FIR result."""
    var plan = make_fir_plan_f32(taps)
    return fir_real_f32_with_plan(signal, plan)


def cross_correlate_complex_split_f32(
    signal_re: Span[Float32, ...],
    signal_im: Span[Float32, ...],
    reference_re: Span[Float32, ...],
    reference_im: Span[Float32, ...],
) raises -> List[Complex32]:
    """Return valid split-IQ ``sum(signal * conj(reference))`` correlations.

    Real/imaginary pairs must have equal lengths, the reference must be
    non-empty, and a shorter signal returns an empty list.  All inputs are
    read-only inside this function and must satisfy Mojo's non-aliasing call
    rule.  The interleaved-complex output is newly allocated.  Complete
    dot-product vectors use native-width SIMD and any remainder is scalar.
    """
    if len(signal_re) != len(signal_im):
        raise Error("split-IQ signal components must have equal length")
    if len(reference_re) != len(reference_im):
        raise Error("split-IQ reference components must have equal length")
    if len(reference_re) < 1:
        raise Error("split-IQ correlation requires a non-empty reference")
    if len(signal_re) < len(reference_re):
        return List[Complex32]()

    comptime width = simd_width_of[DType.float32]()
    var result = List[Complex32](
        capacity=len(signal_re) - len(reference_re) + 1
    )
    for offset in range(len(signal_re) - len(reference_re) + 1):
        var real_vectors = SIMD[DType.float32, width](0.0)
        var imag_vectors = SIMD[DType.float32, width](0.0)
        var index = 0
        while index + Int(width) <= len(reference_re):
            var sr = signal_re.unsafe_ptr().unsafe_load[width=width](
                offset + index
            )
            var si = signal_im.unsafe_ptr().unsafe_load[width=width](
                offset + index
            )
            var rr = reference_re.unsafe_ptr().unsafe_load[width=width](index)
            var ri = reference_im.unsafe_ptr().unsafe_load[width=width](index)
            real_vectors += sr * rr + si * ri
            imag_vectors += si * rr - sr * ri
            index += Int(width)
        var real = real_vectors.reduce_add()
        var imag = imag_vectors.reduce_add()
        while index < len(reference_re):
            real += (
                signal_re[offset + index] * reference_re[index]
                + signal_im[offset + index] * reference_im[index]
            )
            imag += (
                signal_im[offset + index] * reference_re[index]
                - signal_re[offset + index] * reference_im[index]
            )
            index += 1
        result.append(Complex32(real, imag))
    return result^


def _is_supported_modulation_f32(bits_per_symbol: Int) -> Bool:
    return (
        bits_per_symbol == 1
        or (
            bits_per_symbol >= 2
            and bits_per_symbol <= 12
            and bits_per_symbol % 2 == 0
        )
    )


def _gray_to_binary_f32(gray: Int) -> Int:
    var value = gray
    var shifted = gray >> 1
    while shifted != 0:
        value ^= shifted
        shifted >>= 1
    return value


def _binary_to_gray_f32(value: Int) -> Int:
    return value ^ (value >> 1)


def _qam_axis_level_f32(gray: Int, axis_bits: Int) -> Float32:
    return Float32(((1 << axis_bits) - 1) - 2 * _gray_to_binary_f32(gray))


def _qam_normalization_f32(bits_per_symbol: Int) -> Float32:
    if bits_per_symbol == 1:
        return Float32(1.0)
    return sqrt(
        Float32(2.0 / 3.0) * Float32((1 << bits_per_symbol) - 1)
    )


def _qam_symbol_f32(label: Int, bits_per_symbol: Int) -> Complex32:
    if bits_per_symbol == 1:
        return Complex32(Float32(1.0) if label == 0 else Float32(-1.0), 0.0)
    var axis_bits = bits_per_symbol // 2
    var mask = (1 << axis_bits) - 1
    var scale = _qam_normalization_f32(bits_per_symbol)
    return Complex32(
        _qam_axis_level_f32((label >> axis_bits) & mask, axis_bits) / scale,
        _qam_axis_level_f32(label & mask, axis_bits) / scale,
    )


def _nearest_axis_gray_f32(
    sample: Float32, axis_bits: Int, scale: Float32
) -> Int:
    var maximum = (1 << axis_bits) - 1
    var maximum_level = Float32(maximum) / scale
    # Clip in the signal domain before multiplying by ``scale``.  For a
    # finite extreme sample, ``sample * scale`` can overflow even though the
    # correct hard decision is simply the outermost constellation point.
    if sample >= maximum_level:
        return 0
    if sample <= -maximum_level:
        return _binary_to_gray_f32(maximum)
    var coordinate = (Float32(maximum) - sample * scale) * Float32(0.5)
    coordinate = max(Float32(0.0), min(Float32(maximum), coordinate))
    var binary_index = min(maximum, Int(coordinate + Float32(0.5)))
    return _binary_to_gray_f32(binary_index)


def _scaled_product_or_limit_f32(
    lhs: Float32, rhs: Float32, denominator: Float32
) -> Float32:
    """Evaluate ``lhs * rhs / denominator`` without a bad intermediate.

    Callers provide finite factors and a finite positive denominator.  The
    three equivalent operation orders cover cases where a finite final value
    would otherwise be hidden by an intermediate overflow or underflow.  A
    signed infinity/zero sentinel reports a genuinely unrepresentable result
    to soft demappers and still lets the integer quantizer saturate.
    """
    if lhs == 0.0 or rhs == 0.0:
        return lhs * rhs

    comptime minimum_normal = Float32(1.17549435e-38)
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

    # Preserve representable subnormal results after normal-first routes have
    # been exhausted.
    var direct = product / denominator
    if isfinite(direct) and direct != 0.0:
        return direct
    var divide_lhs_first = lhs_ratio * rhs
    if isfinite(divide_lhs_first) and divide_lhs_first != 0.0:
        return divide_lhs_first
    var divide_rhs_first = lhs * rhs_ratio
    if isfinite(divide_rhs_first) and divide_rhs_first != 0.0:
        return divide_rhs_first

    var negative = (lhs < 0.0) != (rhs < 0.0)
    var at_least_one = abs(lhs) >= denominator / abs(rhs)
    if at_least_one:
        return -inf[DType.float32]() if negative else inf[DType.float32]()
    return Float32(-0.0) if negative else Float32(0.0)


def _finite_scaled_product_f32(
    lhs: Float32, rhs: Float32, denominator: Float32
) raises -> Float32:
    """Return a representable scaled product or reject overflow/underflow."""
    var result = _scaled_product_or_limit_f32(lhs, rhs, denominator)
    if not isfinite(result) or (
        result == 0.0 and lhs != 0.0 and rhs != 0.0
    ):
        raise Error("Float32 QAM LLR is not representable")
    return result


def _nearest_axis_level_f32(
    sample: Float32,
    axis_bits: Int,
    shift: Int,
    bit_value: Int,
    scale: Float32,
) -> Float32:
    """Find a bit-constrained nearest PAM level without squaring distance."""
    var nearest = Float32(0.0)
    var nearest_distance = inf[DType.float32]()
    var lowest = inf[DType.float32]()
    var highest = -inf[DType.float32]()
    for gray in range(1 << axis_bits):
        if ((gray >> shift) & 1) != bit_value:
            continue
        var level = _qam_axis_level_f32(gray, axis_bits) / scale
        lowest = min(lowest, level)
        highest = max(highest, level)
        var distance = abs(sample - level)
        if distance < nearest_distance:
            nearest_distance = distance
            nearest = level
    # At extreme magnitudes all bounded level deltas can round identically;
    # selecting the constrained endpoint remains exact.
    if sample >= highest:
        return highest
    if sample <= lowest:
        return lowest
    return nearest


def _axis_maxlog_llr_f32(
    sample: Float32,
    axis_bits: Int,
    shift: Int,
    scale: Float32,
    noise_variance: Float32,
) raises -> Float32:
    """Compute one max-log bit LLR without squared-distance overflow."""
    var nearest_zero = _nearest_axis_level_f32(
        sample, axis_bits, shift, 0, scale
    )
    var nearest_one = _nearest_axis_level_f32(
        sample, axis_bits, shift, 1, scale
    )
    var level_delta = nearest_zero - nearest_one

    # (x-o)^2 - (x-z)^2 = (z-o) * ((x-o) + (x-z)).  This avoids
    # overflowing both squared metrics and then subtracting two infinities.
    var from_one = sample - nearest_one
    var from_zero = sample - nearest_zero
    var doubled_centered_sample = from_one + from_zero
    if isfinite(doubled_centered_sample):
        return _finite_scaled_product_f32(
            level_delta, doubled_centered_sample, noise_variance
        )

    # If the centered sum itself overflows, evaluate the leading and bounded
    # correction terms independently so division by a large N0 can recover a
    # representable final LLR.
    var leading = _scaled_product_or_limit_f32(
        Float32(2.0) * level_delta, sample, noise_variance
    )
    var correction = _scaled_product_or_limit_f32(
        -level_delta, nearest_zero + nearest_one, noise_variance
    )
    if not isfinite(leading) or not isfinite(correction):
        raise Error("Float32 QAM LLR is not representable")
    var result = leading + correction
    if not isfinite(result) or result == 0.0:
        raise Error("Float32 QAM LLR is not representable")
    return result


def qam_map_f32(
    bits: Span[UInt8, ...], bits_per_symbol: Int
) raises -> List[Complex32]:
    """Map binary labels directly into practical Float32 BPSK/QAM symbols."""
    if not _is_supported_modulation_f32(bits_per_symbol):
        raise Error("Float32 modulation requires 1 or an even 2..12 bits")
    if len(bits) % bits_per_symbol != 0:
        raise Error("Float32 mapper bit count must divide the symbol order")
    var result = List[Complex32](capacity=len(bits) // bits_per_symbol)
    for symbol_index in range(len(bits) // bits_per_symbol):
        var label = 0
        for bit_index in range(bits_per_symbol):
            var bit = Int(bits[symbol_index * bits_per_symbol + bit_index])
            if bit != 0 and bit != 1:
                raise Error("Float32 mapper input must be binary")
            label = (label << 1) | bit
        result.append(_qam_symbol_f32(label, bits_per_symbol))
    return result^


def qam_demap_hard_f32(
    samples: Span[Complex32, ...], bits_per_symbol: Int
) raises -> List[UInt8]:
    """Slice practical Float32 BPSK/QAM symbols back to Gray labels."""
    if not _is_supported_modulation_f32(bits_per_symbol):
        raise Error("Float32 modulation requires 1 or an even 2..12 bits")
    var result = List[UInt8](capacity=len(samples) * bits_per_symbol)
    for sample_index in range(len(samples)):
        if (
            not isfinite(samples[sample_index].re)
            or not isfinite(samples[sample_index].im)
        ):
            raise Error("Float32 hard demapper input must be finite")
        var label = 0 if samples[sample_index].re >= 0.0 else 1
        if bits_per_symbol != 1:
            var axis_bits = bits_per_symbol // 2
            var scale = _qam_normalization_f32(bits_per_symbol)
            var i_gray = _nearest_axis_gray_f32(
                samples[sample_index].re, axis_bits, scale
            )
            var q_gray = _nearest_axis_gray_f32(
                samples[sample_index].im, axis_bits, scale
            )
            label = (i_gray << axis_bits) | q_gray
        for bit_index in range(bits_per_symbol):
            result.append(
                UInt8((label >> (bits_per_symbol - bit_index - 1)) & 1)
            )
    return result^


def quantize_llr_f32(
    llrs: Span[Float32, ...], *, scale: Float32, clip: Int
) raises -> List[Int]:
    """Nearest-away Float32 LLR quantization with symmetric saturation."""
    if not isfinite(scale) or scale <= 0.0 or clip < 1:
        raise Error("Float32 LLR quantizer requires finite positive scale/clip")
    var result = List[Int](capacity=len(llrs))
    for index in range(len(llrs)):
        if not isfinite(llrs[index]):
            raise Error("Float32 LLR quantizer input must be finite")
        var scaled = _scaled_product_or_limit_f32(
            llrs[index], scale, Float32(1.0)
        )
        if not isfinite(scaled):
            result.append(clip if scaled > 0.0 else -clip)
            continue
        # Guard the conversion boundary before adding the rounding offset.
        # Float32(Int.MAX) rounds to 2^63 on a 64-bit host, while Int.MIN is
        # exact; values at either boundary must saturate instead of converting.
        if scaled >= Float32(Int.MAX):
            result.append(clip)
            continue
        if scaled <= Float32(Int.MIN):
            result.append(-clip)
            continue
        var rounded = Int(
            scaled + (Float32(0.5) if scaled >= 0.0 else Float32(-0.5))
        )
        result.append(max(-clip, min(clip, rounded)))
    return result^


def qam_demapper_llr_maxlog_f32(
    samples: Span[Complex32, ...],
    bits_per_symbol: Int,
    noise_variance: Float32,
) raises -> List[Float32]:
    """Return Float32 full-constellation max-log LLRs for BPSK/QAM.

    Supported orders are BPSK and QPSK through 4096-QAM (1, 2, 4, 6, 8, 10,
    or 12 bits/symbol).  Labels are MSB-first binary-reflected Gray labels.
    Positive LLR means bit zero.  ``noise_variance`` must be finite and
    positive and is the complex variance; outputs are therefore scaled by
    exactly ``1/N0``.  Square-QAM separability reduces the full search to the
    bit-carrying PAM axis without changing its mathematical result.  A finite
    input whose LLR is outside the Float32 range is rejected.
    """
    if not _is_supported_modulation_f32(bits_per_symbol):
        raise Error("Float32 modulation requires 1 or an even 2..12 bits")
    if not isfinite(noise_variance) or noise_variance <= 0.0:
        raise Error("Float32 QAM noise variance must be finite and positive")
    var result = List[Float32](capacity=len(samples) * bits_per_symbol)
    for sample_index in range(len(samples)):
        var sample = samples[sample_index]
        if not isfinite(sample.re) or not isfinite(sample.im):
            raise Error("Float32 QAM demapper input must be finite")
        if bits_per_symbol == 1:
            result.append(
                _finite_scaled_product_f32(
                    Float32(4.0), sample.re, noise_variance
                )
            )
            continue
        var axis_bits = bits_per_symbol // 2
        var scale = _qam_normalization_f32(bits_per_symbol)
        for bit_index in range(bits_per_symbol):
            var local_bit = (
                bit_index if bit_index < axis_bits else bit_index - axis_bits
            )
            var shift = axis_bits - local_bit - 1
            var coordinate = sample.re if bit_index < axis_bits else sample.im
            result.append(
                _axis_maxlog_llr_f32(
                    coordinate, axis_bits, shift, scale, noise_variance
                )
            )
    return result^


def qam_demapper_llr_piecewise_f32(
    samples: Span[Complex32, ...],
    bits_per_symbol: Int,
    noise_variance: Float32,
) raises -> List[Float32]:
    """Return axis-factorized Float32 max-log LLRs for BPSK/QAM.

    The orthogonal-axis minimum cancels, reducing each bit search from the full
    constellation to one PAM axis.  Sign, labeling, and ``1/N0`` scaling are
    identical to :func:`qam_demapper_llr_maxlog_f32`.
    """
    if not _is_supported_modulation_f32(bits_per_symbol):
        raise Error("Float32 modulation requires 1 or an even 2..12 bits")
    if not isfinite(noise_variance) or noise_variance <= 0.0:
        raise Error("Float32 QAM noise variance must be finite and positive")
    var result = List[Float32](capacity=len(samples) * bits_per_symbol)
    if bits_per_symbol == 1:
        for sample_index in range(len(samples)):
            if (
                not isfinite(samples[sample_index].re)
                or not isfinite(samples[sample_index].im)
            ):
                raise Error("Float32 QAM demapper input must be finite")
            result.append(
                _finite_scaled_product_f32(
                    Float32(4.0),
                    samples[sample_index].re,
                    noise_variance,
                )
            )
        return result^
    var axis_bits = bits_per_symbol // 2
    var scale = _qam_normalization_f32(bits_per_symbol)
    for sample_index in range(len(samples)):
        var sample = samples[sample_index]
        if not isfinite(sample.re) or not isfinite(sample.im):
            raise Error("Float32 QAM demapper input must be finite")
        for bit_index in range(bits_per_symbol):
            var local_bit = (
                bit_index if bit_index < axis_bits else bit_index - axis_bits
            )
            var shift = axis_bits - local_bit - 1
            var coordinate = sample.re if bit_index < axis_bits else sample.im
            result.append(
                _axis_maxlog_llr_f32(
                    coordinate, axis_bits, shift, scale, noise_variance
                )
            )
    return result^
