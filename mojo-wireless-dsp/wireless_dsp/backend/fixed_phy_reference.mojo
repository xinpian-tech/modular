"""Bit-exact fixed-point reference for one representative OFDM PHY symbol.

This is deliberately a small hardware-facing golden model, not a complete
fixed-point NR or Wi-Fi PHY.  It provides QPSK, radix-2 OFDM with a cyclic
prefix, a memoryless complex channel, flat-channel LS estimation, one-tap
equalization, and deterministic vectors suitable for RTL co-verification.

Arithmetic boundaries are explicit.  Complex products retain both partial
products until one component rounding/narrowing boundary.  FFT/IFFT
butterflies use the supplied per-stage contract from ``fixed_fft_reference``.
The LS/equalizer reciprocal is formed by positive integer division; its
rounding mode and overflow behavior are exactly those of the reciprocal
output ``QFormat``.  A zero power estimate is rejected rather than hidden.
"""

from std.collections import Span
from std.math import isfinite, sqrt
from wireless_dsp.numerics.fixed import (
    ROUND_NEAREST_AWAY,
    OVERFLOW_SATURATE,
)
from wireless_dsp.numerics.quantization import (
    QFormat,
    dequantize_raw,
    fixed_mac_raw,
    fixed_mul_raw,
    narrow_raw,
    require_raw_fits,
    rescale_raw,
)
from wireless_dsp.numerics.complex_fixed import (
    ComplexRaw,
    complex_conjugate_raw,
    complex_mac_conjugate_raw,
    complex_mul_raw,
    require_complex_fits,
)
from wireless_dsp.numerics.scale_schedule import (
    ScaleStage,
    apply_scale_schedule,
)
from wireless_dsp.backend.fixed_fft_reference import (
    fixed_fft_radix2_raw,
    quantized_fft_twiddles,
)
from wireless_dsp.testing.fixed_vectors import (
    complex_raw_checksum,
    serialize_complex_fixed_vector,
    serialize_fixed_vector,
    serialize_scale_trace,
)


struct FixedPHYFormats(ImplicitlyCopyable):
    """Q formats at every externally visible mini-PHY boundary."""

    var symbol: QFormat
    var time: QFormat
    var channel: QFormat
    var frequency: QFormat
    var accumulator: QFormat
    var reciprocal: QFormat
    var twiddle: QFormat

    def __init__(
        out self,
        symbol: QFormat,
        time: QFormat,
        channel: QFormat,
        frequency: QFormat,
        accumulator: QFormat,
        reciprocal: QFormat,
        twiddle: QFormat,
    ):
        self.symbol = symbol
        self.time = time
        self.channel = channel
        self.frequency = frequency
        self.accumulator = accumulator
        self.reciprocal = reciprocal
        self.twiddle = twiddle


struct FixedPHYAudit(ImplicitlyCopyable):
    """Float64 EVM and hard-bit comparison for a fixed QPSK checkpoint."""

    var evm_rms: Float64
    var bit_errors: Int
    var bits_checked: Int

    def __init__(
        out self, evm_rms: Float64, bit_errors: Int, bits_checked: Int
    ):
        self.evm_rms = evm_rms
        self.bit_errors = bit_errors
        self.bits_checked = bits_checked


struct FixedPHYResult(Movable):
    """All bit-exact checkpoints of the representative one-symbol chain."""

    var transform_size: Int
    var cyclic_prefix: Int
    var pilot_symbols: Int
    var amplitude_raw: Int64
    var mapped_symbols: List[ComplexRaw]
    var transmit_samples: List[ComplexRaw]
    var channel_samples: List[ComplexRaw]
    var received_bins: List[ComplexRaw]
    var channel_estimate: ComplexRaw
    var equalized_symbols: List[ComplexRaw]
    var decoded_bits: List[UInt8]
    var audit: FixedPHYAudit

    def __init__(
        out self,
        transform_size: Int,
        cyclic_prefix: Int,
        pilot_symbols: Int,
        amplitude_raw: Int64,
        var mapped_symbols: List[ComplexRaw],
        var transmit_samples: List[ComplexRaw],
        var channel_samples: List[ComplexRaw],
        var received_bins: List[ComplexRaw],
        channel_estimate: ComplexRaw,
        var equalized_symbols: List[ComplexRaw],
        var decoded_bits: List[UInt8],
        audit: FixedPHYAudit,
    ):
        self.transform_size = transform_size
        self.cyclic_prefix = cyclic_prefix
        self.pilot_symbols = pilot_symbols
        self.amplitude_raw = amplitude_raw
        self.mapped_symbols = mapped_symbols^
        self.transmit_samples = transmit_samples^
        self.channel_samples = channel_samples^
        self.received_bins = received_bins^
        self.channel_estimate = channel_estimate
        self.equalized_symbols = equalized_symbols^
        self.decoded_bits = decoded_bits^
        self.audit = audit


def fixed_phy_default_formats() raises -> FixedPHYFormats:
    """Return the audited format contract used by the representative chain."""
    return FixedPHYFormats(
        QFormat(18, 14, ROUND_NEAREST_AWAY, OVERFLOW_SATURATE),
        QFormat(18, 14, ROUND_NEAREST_AWAY, OVERFLOW_SATURATE),
        QFormat(18, 14, ROUND_NEAREST_AWAY, OVERFLOW_SATURATE),
        QFormat(24, 14, ROUND_NEAREST_AWAY, OVERFLOW_SATURATE),
        QFormat(30, 20, ROUND_NEAREST_AWAY, OVERFLOW_SATURATE),
        QFormat(24, 18, ROUND_NEAREST_AWAY, OVERFLOW_SATURATE),
        QFormat(18, 16, ROUND_NEAREST_AWAY, OVERFLOW_SATURATE),
    )


def _radix2_stage_count(size: Int) raises -> Int:
    if size < 2 or (size & (size - 1)) != 0:
        raise Error("fixed OFDM transform size must be a power of two >= 2")
    var count = 0
    var remaining = size
    while remaining > 1:
        count += 1
        remaining //= 2
    return count


def _fft_stages(
    size: Int, output_format: QFormat, right_shift: Int
) raises -> List[ScaleStage]:
    var count = _radix2_stage_count(size)
    var result = List[ScaleStage](capacity=count)
    for _ in range(count):
        result.append(ScaleStage(output_format, right_shift))
    return result^


def fixed_qpsk_map_raw(
    bits: Span[UInt8, ...], qformat: QFormat, amplitude_raw: Int64
) raises -> List[ComplexRaw]:
    """Map ``00`` to ``(+A,+A)``; one bits select the negative axis.

    The component amplitude is supplied as a positive raw integer.  No hidden
    normalization is performed, so a caller may choose exactly the RTL QPSK
    constant it wants to audit.
    """
    if len(bits) % 2 != 0:
        raise Error("fixed QPSK mapping requires an even bit count")
    require_raw_fits(amplitude_raw, qformat)
    if amplitude_raw <= 0:
        raise Error("fixed QPSK amplitude must be positive")
    var result = List[ComplexRaw](capacity=len(bits) // 2)
    for i in range(0, len(bits), 2):
        if bits[i] > 1 or bits[i + 1] > 1:
            raise Error("fixed QPSK bits must be binary")
        result.append(
            ComplexRaw(
                -amplitude_raw if bits[i] == 1 else amplitude_raw,
                -amplitude_raw if bits[i + 1] == 1 else amplitude_raw,
            )
        )
    return result^


def fixed_qpsk_hard_bits(
    symbols: Span[ComplexRaw, ...], qformat: QFormat
) raises -> List[UInt8]:
    """Hard-demap QPSK; an exact zero-axis tie deterministically selects 0."""
    var result = List[UInt8](capacity=2 * len(symbols))
    for i in range(len(symbols)):
        var value = ComplexRaw(symbols[i].re, symbols[i].im)
        require_complex_fits(value, qformat)
        result.append(UInt8(0 if value.re >= 0 else 1))
        result.append(UInt8(0 if value.im >= 0 else 1))
    return result^


def fixed_qpsk_llrs_raw(
    symbols: Span[ComplexRaw, ...],
    input_format: QFormat,
    output_format: QFormat,
) raises -> List[Int64]:
    """Return coordinate LLRs where positive favors bit zero.

    These are deliberately unnormalized max-log metrics.  Each coordinate is
    binary-point converted, rounded, and narrowed exactly once.  A zero metric
    is the documented hard-decision tie and therefore maps to bit zero.
    """
    var result = List[Int64](capacity=2 * len(symbols))
    for i in range(len(symbols)):
        var value = ComplexRaw(symbols[i].re, symbols[i].im)
        require_complex_fits(value, input_format)
        result.append(
            rescale_raw(
                value.re,
                input_format.fraction_bits,
                output_format,
            )
        )
        result.append(
            rescale_raw(
                value.im,
                input_format.fraction_bits,
                output_format,
            )
        )
    return result^


def fixed_ofdm_modulate_raw(
    spectrum: Span[ComplexRaw, ...],
    spectrum_format: QFormat,
    time_format: QFormat,
    twiddle_format: QFormat,
    cyclic_prefix: Int,
) raises -> List[ComplexRaw]:
    """IFFT and prepend CP using one right shift at every radix-2 stage.

    The total IFFT scale is therefore exactly ``1/N``.  Positive-angle
    twiddles are quantized once into ``twiddle_format``.
    """
    var size = len(spectrum)
    _ = _radix2_stage_count(size)
    if cyclic_prefix < 0 or cyclic_prefix > size:
        raise Error("invalid fixed OFDM cyclic-prefix length")
    var twiddles = quantized_fft_twiddles(
        size, twiddle_format, inverse=True
    )
    var stages = _fft_stages(size, time_format, 1)
    var time = fixed_fft_radix2_raw(
        spectrum,
        spectrum_format,
        Span(twiddles),
        twiddle_format,
        Span(stages),
    )
    var result = List[ComplexRaw](capacity=size + cyclic_prefix)
    for i in range(size - cyclic_prefix, size):
        result.append(time[i])
    for i in range(size):
        result.append(time[i])
    return result^


def fixed_ofdm_demodulate_raw(
    samples: Span[ComplexRaw, ...],
    transform_size: Int,
    cyclic_prefix: Int,
    time_format: QFormat,
    frequency_format: QFormat,
    twiddle_format: QFormat,
) raises -> List[ComplexRaw]:
    """Remove CP and FFT with zero stage shifts into a wider frequency Q."""
    _ = _radix2_stage_count(transform_size)
    if (
        cyclic_prefix < 0
        or cyclic_prefix > transform_size
        or len(samples) != transform_size + cyclic_prefix
    ):
        raise Error("fixed OFDM symbol length does not match FFT and CP")
    var time = List[ComplexRaw](capacity=transform_size)
    for i in range(transform_size):
        var value = ComplexRaw(
            samples[cyclic_prefix + i].re, samples[cyclic_prefix + i].im
        )
        require_complex_fits(value, time_format)
        time.append(value)
    var twiddles = quantized_fft_twiddles(transform_size, twiddle_format)
    var stages = _fft_stages(transform_size, frequency_format, 0)
    return fixed_fft_radix2_raw(
        Span(time),
        time_format,
        Span(twiddles),
        twiddle_format,
        Span(stages),
    )


def fixed_flat_channel_raw(
    samples: Span[ComplexRaw, ...],
    sample_format: QFormat,
    channel: ComplexRaw,
    channel_format: QFormat,
    output_format: QFormat,
) raises -> List[ComplexRaw]:
    """Apply one memoryless complex channel with one narrow per component."""
    require_complex_fits(channel, channel_format)
    var result = List[ComplexRaw](capacity=len(samples))
    for i in range(len(samples)):
        var sample = ComplexRaw(samples[i].re, samples[i].im)
        result.append(
            complex_mul_raw(
                sample,
                sample_format,
                channel,
                channel_format,
                output_format,
            )
        )
    return result^


def fixed_reciprocal_positive_raw(
    value_raw: Int64,
    input_format: QFormat,
    output_format: QFormat,
) raises -> Int64:
    """Quantize ``1/value`` using exact positive integer division.

    ``numerator = 2^(input_fraction + output_fraction)``.  Toward-zero keeps
    the integer quotient; nearest-away increments when ``2*remainder`` is at
    least the positive denominator.  The quotient is then narrowed with the
    output format's saturation or two's-complement wrap policy.
    """
    require_raw_fits(value_raw, input_format)
    if value_raw <= 0:
        raise Error("fixed reciprocal requires strictly positive power")
    var exponent = input_format.fraction_bits + output_format.fraction_bits
    if exponent > 61:
        raise Error("fixed reciprocal scale exceeds the Int64 golden model")
    var numerator = Int64(1) << Int64(exponent)
    var quotient = numerator // value_raw
    var remainder = numerator % value_raw
    if (
        output_format.rounding_mode == ROUND_NEAREST_AWAY
        and remainder * 2 >= value_raw
    ):
        quotient += 1
    return narrow_raw(quotient, output_format)


def fixed_ls_flat_channel_raw(
    received: Span[ComplexRaw, ...],
    references: Span[ComplexRaw, ...],
    received_format: QFormat,
    reference_format: QFormat,
    accumulator_format: QFormat,
    reciprocal_format: QFormat,
    output_format: QFormat,
) raises -> ComplexRaw:
    """Estimate one flat channel as ``sum(conj(x)*y)/sum(|x|^2)``.

    Both numerator and power use a registered saturating/wrapping accumulator
    boundary after each pilot contribution.  The final scalar reciprocal and
    component multiplications each introduce one further declared boundary.
    """
    if len(received) == 0 or len(received) != len(references):
        raise Error("fixed LS requires equal non-empty pilot vectors")
    var numerator = ComplexRaw()
    var power = Int64(0)
    for i in range(len(received)):
        var reference = ComplexRaw(references[i].re, references[i].im)
        var received_value = ComplexRaw(received[i].re, received[i].im)
        numerator = complex_mac_conjugate_raw(
            numerator,
            reference,
            reference_format,
            received_value,
            received_format,
            accumulator_format,
        )
        power = fixed_mac_raw(
            power,
            reference.re,
            reference_format,
            reference.re,
            reference_format,
            accumulator_format,
        )
        power = fixed_mac_raw(
            power,
            reference.im,
            reference_format,
            reference.im,
            reference_format,
            accumulator_format,
        )
    var reciprocal = fixed_reciprocal_positive_raw(
        power, accumulator_format, reciprocal_format
    )
    return ComplexRaw(
        fixed_mul_raw(
            numerator.re,
            accumulator_format,
            reciprocal,
            reciprocal_format,
            output_format,
        ),
        fixed_mul_raw(
            numerator.im,
            accumulator_format,
            reciprocal,
            reciprocal_format,
            output_format,
        ),
    )


def fixed_equalize_flat_raw(
    received: Span[ComplexRaw, ...],
    received_format: QFormat,
    channel_estimate: ComplexRaw,
    channel_format: QFormat,
    accumulator_format: QFormat,
    reciprocal_format: QFormat,
    output_format: QFormat,
) raises -> List[ComplexRaw]:
    """One-tap ``y*conj(h)/|h|^2`` with explicit reciprocal and scales."""
    require_complex_fits(channel_estimate, channel_format)
    var power = fixed_mac_raw(
        Int64(0),
        channel_estimate.re,
        channel_format,
        channel_estimate.re,
        channel_format,
        accumulator_format,
    )
    power = fixed_mac_raw(
        power,
        channel_estimate.im,
        channel_format,
        channel_estimate.im,
        channel_format,
        accumulator_format,
    )
    var reciprocal = fixed_reciprocal_positive_raw(
        power, accumulator_format, reciprocal_format
    )
    var conjugate = complex_conjugate_raw(
        channel_estimate, channel_format
    )
    var result = List[ComplexRaw](capacity=len(received))
    for i in range(len(received)):
        var received_value = ComplexRaw(received[i].re, received[i].im)
        var mixed = complex_mul_raw(
            received_value,
            received_format,
            conjugate,
            channel_format,
            accumulator_format,
        )
        result.append(
            ComplexRaw(
                fixed_mul_raw(
                    mixed.re,
                    accumulator_format,
                    reciprocal,
                    reciprocal_format,
                    output_format,
                ),
                fixed_mul_raw(
                    mixed.im,
                    accumulator_format,
                    reciprocal,
                    reciprocal_format,
                    output_format,
                ),
            )
        )
    return result^


def fixed_qpsk_float64_audit(
    bits: Span[UInt8, ...],
    symbols: Span[ComplexRaw, ...],
    symbol_format: QFormat,
    ideal_component: Float64,
) raises -> FixedPHYAudit:
    """Audit dequantized fixed symbols against an ideal Float64 QPSK grid."""
    if (
        len(bits) == 0
        or len(bits) != 2 * len(symbols)
        or not isfinite(ideal_component)
        or ideal_component <= 0.0
        or not isfinite(ideal_component * ideal_component)
    ):
        raise Error("fixed QPSK audit dimensions/amplitude are invalid")
    var hard = fixed_qpsk_hard_bits(symbols, symbol_format)
    var error_energy = 0.0
    var reference_energy = 0.0
    var bit_errors = 0
    for i in range(len(symbols)):
        if bits[2 * i] > 1 or bits[2 * i + 1] > 1:
            raise Error("fixed QPSK audit bits must be binary")
        var ideal_re = (
            -ideal_component if bits[2 * i] == 1 else ideal_component
        )
        var ideal_im = (
            -ideal_component if bits[2 * i + 1] == 1 else ideal_component
        )
        var actual_re = dequantize_raw(symbols[i].re, symbol_format)
        var actual_im = dequantize_raw(symbols[i].im, symbol_format)
        var error_re = actual_re - ideal_re
        var error_im = actual_im - ideal_im
        error_energy += error_re * error_re + error_im * error_im
        reference_energy += ideal_re * ideal_re + ideal_im * ideal_im
        if not isfinite(error_energy) or not isfinite(reference_energy):
            raise Error("fixed QPSK audit energy must remain finite")
    for i in range(len(bits)):
        if hard[i] != bits[i]:
            bit_errors += 1
    return FixedPHYAudit(
        sqrt(error_energy / reference_energy) if reference_energy > 0.0 else 0.0,
        bit_errors,
        len(bits),
    )


def fixed_phy_one_symbol_reference(
    bits: Span[UInt8, ...],
    transform_size: Int,
    cyclic_prefix: Int,
    flat_channel: ComplexRaw,
    formats: FixedPHYFormats,
    amplitude_raw: Int64,
    pilot_symbols: Int = 1,
) raises -> FixedPHYResult:
    """Run the representative bits-to-QPSK-to-OFDM-to-bits mini-chain.

    The first ``pilot_symbols`` mapped tones are known to the receiver for one
    flat LS estimate.  Remaining tones are treated as data.  This is a single
    noiseless OFDM-symbol reference and intentionally excludes protocol
    framing, coding, synchronization, MIMO, and frequency-selective channels.
    """
    _ = _radix2_stage_count(transform_size)
    if len(bits) != 2 * transform_size:
        raise Error("fixed mini-PHY requires exactly two bits per FFT bin")
    if pilot_symbols < 1 or pilot_symbols > transform_size:
        raise Error("fixed mini-PHY pilot count is outside the FFT grid")
    var mapped = fixed_qpsk_map_raw(bits, formats.symbol, amplitude_raw)
    var transmit = fixed_ofdm_modulate_raw(
        Span(mapped),
        formats.symbol,
        formats.time,
        formats.twiddle,
        cyclic_prefix,
    )
    var through_channel = fixed_flat_channel_raw(
        Span(transmit),
        formats.time,
        flat_channel,
        formats.channel,
        formats.time,
    )
    var received = fixed_ofdm_demodulate_raw(
        Span(through_channel),
        transform_size,
        cyclic_prefix,
        formats.time,
        formats.frequency,
        formats.twiddle,
    )
    var estimate = fixed_ls_flat_channel_raw(
        Span(received[:pilot_symbols]),
        Span(mapped[:pilot_symbols]),
        formats.frequency,
        formats.symbol,
        formats.accumulator,
        formats.reciprocal,
        formats.channel,
    )
    var equalized = fixed_equalize_flat_raw(
        Span(received),
        formats.frequency,
        estimate,
        formats.channel,
        formats.accumulator,
        formats.reciprocal,
        formats.symbol,
    )
    var decoded = fixed_qpsk_hard_bits(Span(equalized), formats.symbol)
    var ideal_component = dequantize_raw(amplitude_raw, formats.symbol)
    var audit = fixed_qpsk_float64_audit(
        bits, Span(equalized), formats.symbol, ideal_component
    )
    return FixedPHYResult(
        transform_size,
        cyclic_prefix,
        pilot_symbols,
        amplitude_raw,
        mapped^,
        transmit^,
        through_channel^,
        received^,
        estimate,
        equalized^,
        decoded^,
        audit,
    )


def fixed_phy_result_checksum(result: FixedPHYResult) -> UInt64:
    """Checksum every complex checkpoint and decoded bit in stage order."""
    var values = List[ComplexRaw](
        capacity=(
            len(result.mapped_symbols)
            + len(result.transmit_samples)
            + len(result.channel_samples)
            + len(result.received_bins)
            + 1
            + len(result.equalized_symbols)
            + len(result.decoded_bits)
        )
    )
    for value in result.mapped_symbols:
        values.append(value)
    for value in result.transmit_samples:
        values.append(value)
    for value in result.channel_samples:
        values.append(value)
    for value in result.received_bins:
        values.append(value)
    values.append(result.channel_estimate)
    for value in result.equalized_symbols:
        values.append(value)
    for bit in result.decoded_bits:
        values.append(ComplexRaw(Int64(bit), 0))
    return complex_raw_checksum(Span(values))


def fixed_phy_scale_trace_text(
    transform_size: Int,
    formats: FixedPHYFormats,
    probe_raw: Int64,
) raises -> String:
    """Serialize the IFFT and FFT register-scale schedules canonically."""
    require_raw_fits(probe_raw, formats.symbol)
    var ifft_stages = _fft_stages(transform_size, formats.time, 1)
    var ifft_trace = apply_scale_schedule(
        probe_raw, formats.symbol, Span(ifft_stages)
    )
    var fft_stages = _fft_stages(transform_size, formats.frequency, 0)
    var fft_trace = apply_scale_schedule(
        probe_raw, formats.time, Span(fft_stages)
    )
    var result = String()
    result.write(
        serialize_scale_trace(
            "fixed-phy-one-symbol", "ifft-registers", ifft_trace
        )
    )
    result.write(
        serialize_scale_trace(
            "fixed-phy-one-symbol", "fft-registers", fft_trace
        )
    )
    return result^


def fixed_phy_canonical_rtl_vectors(
    result: FixedPHYResult, formats: FixedPHYFormats
) raises -> String:
    """Serialize all mini-PHY checkpoints, scale traces, and final checksum."""
    var decoded_raw = List[Int64](capacity=len(result.decoded_bits))
    for bit in result.decoded_bits:
        decoded_raw.append(Int64(bit))
    var estimate: List[ComplexRaw] = [result.channel_estimate]
    var bit_format = QFormat(2, 0)
    var text = String()
    text.write(
        serialize_complex_fixed_vector(
            "fixed-phy-one-symbol",
            "qpsk-grid",
            Span(result.mapped_symbols),
            formats.symbol,
        )
    )
    text.write(
        serialize_complex_fixed_vector(
            "fixed-phy-one-symbol",
            "ifft-cp",
            Span(result.transmit_samples),
            formats.time,
        )
    )
    text.write(
        serialize_complex_fixed_vector(
            "fixed-phy-one-symbol",
            "flat-channel",
            Span(result.channel_samples),
            formats.time,
        )
    )
    text.write(
        serialize_complex_fixed_vector(
            "fixed-phy-one-symbol",
            "fft-bins",
            Span(result.received_bins),
            formats.frequency,
        )
    )
    text.write(
        serialize_complex_fixed_vector(
            "fixed-phy-one-symbol",
            "ls-channel",
            Span(estimate),
            formats.channel,
        )
    )
    text.write(
        serialize_complex_fixed_vector(
            "fixed-phy-one-symbol",
            "equalized-qpsk",
            Span(result.equalized_symbols),
            formats.symbol,
        )
    )
    text.write(
        serialize_fixed_vector(
            "fixed-phy-one-symbol",
            "hard-bits",
            Span(decoded_raw),
            bit_format,
        )
    )
    text.write(
        fixed_phy_scale_trace_text(
            result.transform_size, formats, result.amplitude_raw
        )
    )
    text.write(
        "MWDSP-FIXED-PHY-CHECKSUM-V1\nchecksum=",
        fixed_phy_result_checksum(result),
        "\n",
    )
    return text^
