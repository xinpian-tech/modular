"""Readable fixed-point golden kernels with registered-stage semantics."""

from std.collections import Span
from wireless_dsp.numerics.complex_fixed import (
    ComplexRaw,
    complex_mac_conjugate_raw,
    complex_mac_raw,
    require_complex_fits,
)
from wireless_dsp.numerics.quantization import (
    QFormat,
    narrow_raw,
    require_raw_fits,
    rescale_raw,
)


def fixed_dot_raw(
    lhs: Span[Int64, ...],
    rhs: Span[Int64, ...],
    lhs_format: QFormat,
    rhs_format: QFormat,
    accumulator_format: QFormat,
    output_format: QFormat,
) raises -> Int64:
    """Real dot product with a registered narrow after each accumulation."""
    if len(lhs) != len(rhs):
        raise Error("fixed dot inputs must have equal length")
    if lhs_format.storage_bits > 31 or rhs_format.storage_bits > 31:
        raise Error("bit-exact Int64 dot operands are limited to 31 bits")
    var product_fraction = lhs_format.fraction_bits + rhs_format.fraction_bits
    var accumulator = Int64(0)
    for i in range(len(lhs)):
        require_raw_fits(lhs[i], lhs_format)
        require_raw_fits(rhs[i], rhs_format)
        var product = rescale_raw(
            lhs[i] * rhs[i], product_fraction, accumulator_format
        )
        accumulator = narrow_raw(
            accumulator + product, accumulator_format
        )
    return rescale_raw(
        accumulator, accumulator_format.fraction_bits, output_format
    )


def fixed_fir_raw(
    samples: Span[Int64, ...],
    taps: Span[Int64, ...],
    sample_format: QFormat,
    tap_format: QFormat,
    accumulator_format: QFormat,
    output_format: QFormat,
) raises -> List[Int64]:
    """Causal same-length FIR with a narrow after every accumulator add."""
    if len(taps) == 0:
        raise Error("fixed FIR requires at least one tap")
    if sample_format.storage_bits > 31 or tap_format.storage_bits > 31:
        raise Error("bit-exact Int64 FIR operands are limited to 31 bits")
    for i in range(len(samples)):
        require_raw_fits(samples[i], sample_format)
    for i in range(len(taps)):
        require_raw_fits(taps[i], tap_format)

    var result = List[Int64](capacity=len(samples))
    var product_fraction = (
        sample_format.fraction_bits + tap_format.fraction_bits
    )
    for output_index in range(len(samples)):
        var accumulator = Int64(0)
        var used_taps = min(output_index + 1, len(taps))
        for tap_index in range(used_taps):
            var product = samples[output_index - tap_index] * taps[tap_index]
            var aligned = rescale_raw(
                product, product_fraction, accumulator_format
            )
            accumulator = narrow_raw(
                accumulator + aligned, accumulator_format
            )
        result.append(
            rescale_raw(
                accumulator,
                accumulator_format.fraction_bits,
                output_format,
            )
        )
    return result^


def complex_fir_raw(
    samples: Span[ComplexRaw, ...],
    taps: Span[ComplexRaw, ...],
    sample_format: QFormat,
    tap_format: QFormat,
    accumulator_format: QFormat,
    output_format: QFormat,
) raises -> List[ComplexRaw]:
    """Complex causal FIR using the common wide complex MAC primitive."""
    if len(taps) == 0:
        raise Error("complex fixed FIR requires at least one tap")
    for i in range(len(samples)):
        require_complex_fits(
            ComplexRaw(samples[i].re, samples[i].im), sample_format
        )
    for i in range(len(taps)):
        require_complex_fits(ComplexRaw(taps[i].re, taps[i].im), tap_format)

    var result = List[ComplexRaw](capacity=len(samples))
    for output_index in range(len(samples)):
        var accumulator = ComplexRaw()
        var used_taps = min(output_index + 1, len(taps))
        for tap_index in range(used_taps):
            var sample_index = output_index - tap_index
            accumulator = complex_mac_raw(
                accumulator,
                ComplexRaw(
                    samples[sample_index].re, samples[sample_index].im
                ),
                sample_format,
                ComplexRaw(taps[tap_index].re, taps[tap_index].im),
                tap_format,
                accumulator_format,
            )
        result.append(
            ComplexRaw(
                rescale_raw(
                    accumulator.re,
                    accumulator_format.fraction_bits,
                    output_format,
                ),
                rescale_raw(
                    accumulator.im,
                    accumulator_format.fraction_bits,
                    output_format,
                ),
            )
        )
    return result^


def complex_dot_conjugate_raw(
    lhs: Span[ComplexRaw, ...],
    rhs: Span[ComplexRaw, ...],
    lhs_format: QFormat,
    rhs_format: QFormat,
    accumulator_format: QFormat,
    output_format: QFormat,
) raises -> ComplexRaw:
    """Hermitian dot product used by correlators and MIMO equalizers."""
    if len(lhs) != len(rhs):
        raise Error("fixed complex dot inputs must have equal length")
    var accumulator = ComplexRaw()
    for i in range(len(lhs)):
        accumulator = complex_mac_conjugate_raw(
            accumulator,
            ComplexRaw(lhs[i].re, lhs[i].im),
            lhs_format,
            ComplexRaw(rhs[i].re, rhs[i].im),
            rhs_format,
            accumulator_format,
        )
    return ComplexRaw(
        rescale_raw(
            accumulator.re,
            accumulator_format.fraction_bits,
            output_format,
        ),
        rescale_raw(
            accumulator.im,
            accumulator_format.fraction_bits,
            output_format,
        ),
    )


def complex_cross_correlate_raw(
    signal: Span[ComplexRaw, ...],
    reference: Span[ComplexRaw, ...],
    signal_format: QFormat,
    reference_format: QFormat,
    accumulator_format: QFormat,
    output_format: QFormat,
) raises -> List[ComplexRaw]:
    """Valid sliding ``sum(signal * conj(reference))`` correlation."""
    if len(reference) == 0 or len(signal) < len(reference):
        return List[ComplexRaw]()
    var result = List[ComplexRaw](
        capacity=len(signal) - len(reference) + 1
    )
    for offset in range(len(signal) - len(reference) + 1):
        var accumulator = ComplexRaw()
        for k in range(len(reference)):
            # conj(reference) * signal equals signal * conj(reference).
            accumulator = complex_mac_conjugate_raw(
                accumulator,
                ComplexRaw(reference[k].re, reference[k].im),
                reference_format,
                ComplexRaw(signal[offset + k].re, signal[offset + k].im),
                signal_format,
                accumulator_format,
            )
        result.append(
            ComplexRaw(
                rescale_raw(
                    accumulator.re,
                    accumulator_format.fraction_bits,
                    output_format,
                ),
                rescale_raw(
                    accumulator.im,
                    accumulator_format.fraction_bits,
                    output_format,
                ),
            )
        )
    return result^
