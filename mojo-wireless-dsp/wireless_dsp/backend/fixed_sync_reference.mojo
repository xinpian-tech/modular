"""Bit-exact repeated-preamble synchronization checkpoints.

Correlation and the two window energies are integer-only golden outputs.  A
registered narrow occurs after every complex MAC or energy accumulation.  The
peak detector compares squared raw correlation magnitudes, so the declared
correlation output is limited to 31 signed bits and the comparison remains an
exact Int64 operation.  Coarse CFO is a Float64 audit derived from the winning
integer correlation; it is not presented as an RTL phase implementation.
"""

from std.collections import Span
from std.math import atan2
from wireless_dsp.numerics.complex_fixed import (
    ComplexRaw,
    complex_mac_conjugate_raw,
    require_complex_fits,
)
from wireless_dsp.numerics.quantization import (
    QFormat,
    narrow_raw,
    rescale_raw,
)
from wireless_dsp.testing.fixed_vectors import (
    complex_raw_checksum,
    fixed_raw_checksum,
    serialize_complex_fixed_vector,
    serialize_fixed_vector,
)


comptime _TWO_PI = 6.283185307179586476925286766559


struct FixedRepetitionScanResult(Movable):
    """All per-offset fixed checkpoints plus the selected correlation peak."""

    var period: Int
    var window: Int
    var correlations: List[ComplexRaw]
    var first_energies: List[Int64]
    var second_energies: List[Int64]
    var peak_offset: Int
    var peak_correlation: ComplexRaw
    var coarse_cfo_cycles_per_sample: Float64

    def __init__(
        out self,
        period: Int,
        window: Int,
        var correlations: List[ComplexRaw],
        var first_energies: List[Int64],
        var second_energies: List[Int64],
        peak_offset: Int,
        peak_correlation: ComplexRaw,
        coarse_cfo_cycles_per_sample: Float64,
    ):
        self.period = period
        self.window = window
        self.correlations = correlations^
        self.first_energies = first_energies^
        self.second_energies = second_energies^
        self.peak_offset = peak_offset
        self.peak_correlation = peak_correlation
        self.coarse_cfo_cycles_per_sample = coarse_cfo_cycles_per_sample


def _validate_fixed_sync_window(
    samples: Span[ComplexRaw, ...], offset: Int, period: Int, window: Int
) raises:
    if (
        period < 1
        or window < 1
        or offset < 0
        or period > len(samples)
        or window > len(samples) - period
        or offset > len(samples) - period - window
    ):
        raise Error("fixed repetition window lies outside the sample vector")


def fixed_window_energy_raw(
    samples: Span[ComplexRaw, ...],
    offset: Int,
    window: Int,
    sample_format: QFormat,
    accumulator_format: QFormat,
    output_format: QFormat,
) raises -> Int64:
    """Accumulate ``re^2+im^2`` with one registered narrow per sample."""
    if (
        offset < 0
        or window < 1
        or window > len(samples)
        or offset > len(samples) - window
    ):
        raise Error("fixed energy window lies outside the sample vector")
    if sample_format.storage_bits > 31:
        raise Error("fixed energy input operands are limited to 31 bits")
    var accumulator = Int64(0)
    var product_fraction = 2 * sample_format.fraction_bits
    for index in range(window):
        var sample = ComplexRaw(
            samples[offset + index].re, samples[offset + index].im
        )
        require_complex_fits(sample, sample_format)
        var wide_energy = sample.re * sample.re + sample.im * sample.im
        var aligned = rescale_raw(
            wide_energy, product_fraction, accumulator_format
        )
        accumulator = narrow_raw(accumulator + aligned, accumulator_format)
    return rescale_raw(
        accumulator, accumulator_format.fraction_bits, output_format
    )


def fixed_repetition_correlation_raw(
    samples: Span[ComplexRaw, ...],
    offset: Int,
    period: Int,
    window: Int,
    sample_format: QFormat,
    accumulator_format: QFormat,
    output_format: QFormat,
) raises -> ComplexRaw:
    """Return ``sum(conj(x[n])*x[n+period])`` for one fixed window."""
    _validate_fixed_sync_window(samples, offset, period, window)
    if sample_format.storage_bits > 31:
        raise Error("fixed correlation input operands are limited to 31 bits")
    var accumulator = ComplexRaw()
    for index in range(window):
        accumulator = complex_mac_conjugate_raw(
            accumulator,
            ComplexRaw(
                samples[offset + index].re,
                samples[offset + index].im,
            ),
            sample_format,
            ComplexRaw(
                samples[offset + period + index].re,
                samples[offset + period + index].im,
            ),
            sample_format,
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


def fixed_repetition_scan_raw(
    samples: Span[ComplexRaw, ...],
    period: Int,
    window: Int,
    sample_format: QFormat,
    accumulator_format: QFormat,
    output_format: QFormat,
) raises -> FixedRepetitionScanResult:
    """Scan every valid repeated window and select the exact raw peak."""
    if (
        period < 1
        or window < 1
        or period > len(samples)
        or window > len(samples) - period
    ):
        raise Error("fixed repetition scan requires one complete window pair")
    if output_format.storage_bits > 31:
        raise Error("fixed synchronization peak output is limited to 31 bits")
    var offsets = len(samples) - period - window + 1
    var correlations = List[ComplexRaw](capacity=offsets)
    var first_energies = List[Int64](capacity=offsets)
    var second_energies = List[Int64](capacity=offsets)
    var peak_offset = 0
    var peak_power = Int64(-1)
    for offset in range(offsets):
        var correlation = fixed_repetition_correlation_raw(
            samples,
            offset,
            period,
            window,
            sample_format,
            accumulator_format,
            output_format,
        )
        var first_energy = fixed_window_energy_raw(
            samples,
            offset,
            window,
            sample_format,
            accumulator_format,
            output_format,
        )
        var second_energy = fixed_window_energy_raw(
            samples,
            offset + period,
            window,
            sample_format,
            accumulator_format,
            output_format,
        )
        correlations.append(correlation)
        first_energies.append(first_energy)
        second_energies.append(second_energy)
        var power = (
            correlation.re * correlation.re
            + correlation.im * correlation.im
        )
        if power > peak_power:
            peak_power = power
            peak_offset = offset
    var peak = correlations[peak_offset]
    var phase = atan2(Float64(peak.im), Float64(peak.re))
    return FixedRepetitionScanResult(
        period,
        window,
        correlations^,
        first_energies^,
        second_energies^,
        peak_offset,
        peak,
        phase / (_TWO_PI * Float64(period)),
    )


def fixed_repetition_scan_checksum(result: FixedRepetitionScanResult) -> UInt64:
    """FNV-compose correlation, energy, and peak-selection checkpoints."""
    var state = complex_raw_checksum(Span(result.correlations))
    state ^= fixed_raw_checksum(Span(result.first_energies))
    state *= UInt64(1099511628211)
    state ^= fixed_raw_checksum(Span(result.second_energies))
    state *= UInt64(1099511628211)
    state ^= UInt64(result.peak_offset)
    state *= UInt64(1099511628211)
    state ^= UInt64(result.peak_correlation.re)
    state *= UInt64(1099511628211)
    state ^= UInt64(result.peak_correlation.im)
    state *= UInt64(1099511628211)
    return state


def fixed_repetition_canonical_rtl_vectors(
    result: FixedRepetitionScanResult, output_format: QFormat
) raises -> String:
    """Serialize all integer synchronization stages and their joint checksum."""
    var peak: List[ComplexRaw] = [result.peak_correlation]
    var peak_offset: List[Int64] = [Int64(result.peak_offset)]
    var index_format = QFormat(32, 0)
    var text = String()
    text.write(
        serialize_complex_fixed_vector(
            "fixed-repetition-sync",
            "correlations",
            Span(result.correlations),
            output_format,
        )
    )
    text.write(
        serialize_fixed_vector(
            "fixed-repetition-sync",
            "first-window-energy",
            Span(result.first_energies),
            output_format,
        )
    )
    text.write(
        serialize_fixed_vector(
            "fixed-repetition-sync",
            "second-window-energy",
            Span(result.second_energies),
            output_format,
        )
    )
    text.write(
        serialize_complex_fixed_vector(
            "fixed-repetition-sync",
            "peak-correlation",
            Span(peak),
            output_format,
        )
    )
    text.write(
        serialize_fixed_vector(
            "fixed-repetition-sync",
            "peak-offset",
            Span(peak_offset),
            index_format,
        )
    )
    text.write(
        "MWDSP-FIXED-SYNC-CHECKSUM-V1\nchecksum=",
        fixed_repetition_scan_checksum(result),
        "\n",
    )
    return text^
