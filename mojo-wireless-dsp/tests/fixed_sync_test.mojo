"""Bit-exact tests for repeated-preamble fixed synchronization."""

from std.collections import Span
from std.testing import assert_equal, assert_raises, assert_true, TestSuite
from wireless_dsp.numerics.complex_fixed import ComplexRaw
from wireless_dsp.numerics.quantization import QFormat
from wireless_dsp.backend.fixed_sync_reference import (
    fixed_repetition_canonical_rtl_vectors,
    fixed_repetition_correlation_raw,
    fixed_repetition_scan_checksum,
    fixed_repetition_scan_raw,
    fixed_window_energy_raw,
)


def _oracle_fnv1a_text(text: StringSlice) -> UInt64:
    var state = UInt64(14695981039346656037)
    var bytes = text.as_bytes()
    for index in range(len(bytes)):
        state ^= UInt64(UInt8(bytes[index]))
        state *= UInt64(1099511628211)
    return state


def _quarter_turn_pattern() -> List[ComplexRaw]:
    return [
        ComplexRaw(16, 0),
        ComplexRaw(0, 16),
        ComplexRaw(-16, 0),
        ComplexRaw(0, -16),
    ]


def _formats() raises -> Tuple[QFormat, QFormat, QFormat]:
    return (QFormat(8, 4), QFormat(24, 8), QFormat(16, 8))


def test_fixed_repetition_static_peak_energy_and_phase() raises:
    var sample_format, accumulator_format, output_format = _formats()
    var pattern = _quarter_turn_pattern()
    var samples: List[ComplexRaw] = [ComplexRaw(), ComplexRaw()]
    for value in pattern:
        samples.append(value)
    for value in pattern:
        samples.append(value)
    samples.append(ComplexRaw(3, -2))

    var result = fixed_repetition_scan_raw(
        Span(samples),
        4,
        4,
        sample_format,
        accumulator_format,
        output_format,
    )
    assert_equal(result.peak_offset, 2)
    assert_equal(result.peak_correlation, ComplexRaw(1024, 0))
    assert_equal(result.first_energies[2], Int64(1024))
    assert_equal(result.second_energies[2], Int64(1024))
    assert_equal(result.coarse_cfo_cycles_per_sample, 0.0)


def test_fixed_repetition_quarter_turn_has_exact_cfo_audit() raises:
    var sample_format, accumulator_format, output_format = _formats()
    var first = _quarter_turn_pattern()
    var samples = first.copy()
    for value in first:
        samples.append(ComplexRaw(-value.im, value.re))
    var result = fixed_repetition_scan_raw(
        Span(samples),
        4,
        4,
        sample_format,
        accumulator_format,
        output_format,
    )
    assert_equal(result.peak_offset, 0)
    assert_equal(result.peak_correlation, ComplexRaw(0, 1024))
    assert_true(abs(result.coarse_cfo_cycles_per_sample - 0.0625) < 1.0e-15)


def test_fixed_repetition_matches_independent_integer_formula() raises:
    var sample_format, accumulator_format, output_format = _formats()
    var state = UInt64(0x51AC20260821)
    var samples = List[ComplexRaw](capacity=40)
    for _ in range(40):
        state = state * UInt64(6364136223846793005) + UInt64(1)
        var real = Int64(Int((state >> 59) & UInt64(0x1f)) - 16)
        state = state * UInt64(6364136223846793005) + UInt64(1)
        var imag = Int64(Int((state >> 59) & UInt64(0x1f)) - 16)
        samples.append(ComplexRaw(real, imag))
    for offset in [0, 3, 11]:
        var expected_re = Int64(0)
        var expected_im = Int64(0)
        var expected_energy = Int64(0)
        for index in range(7):
            var lhs = samples[offset + index]
            var rhs = samples[offset + 5 + index]
            expected_re += lhs.re * rhs.re + lhs.im * rhs.im
            expected_im += lhs.re * rhs.im - lhs.im * rhs.re
            expected_energy += lhs.re * lhs.re + lhs.im * lhs.im
        assert_equal(
            fixed_repetition_correlation_raw(
                Span(samples),
                offset,
                5,
                7,
                sample_format,
                accumulator_format,
                output_format,
            ),
            ComplexRaw(expected_re, expected_im),
        )
        assert_equal(
            fixed_window_energy_raw(
                Span(samples),
                offset,
                7,
                sample_format,
                accumulator_format,
                output_format,
            ),
            expected_energy,
        )


def test_fixed_repetition_serializer_checksum_and_edges() raises:
    var sample_format, accumulator_format, output_format = _formats()
    var pattern = _quarter_turn_pattern()
    var samples = pattern.copy()
    for value in pattern:
        samples.append(value)
    var result = fixed_repetition_scan_raw(
        Span(samples),
        4,
        4,
        sample_format,
        accumulator_format,
        output_format,
    )
    var checksum = fixed_repetition_scan_checksum(result)
    var text = fixed_repetition_canonical_rtl_vectors(result, output_format)
    # Independently computed FNV-1a pins every UTF-8 artifact byte.
    assert_equal(
        _oracle_fnv1a_text(StringSlice(text)),
        UInt64(660552057278264346),
    )
    assert_true(text.startswith("MWDSP-COMPLEX-FIXED-V2\n"))
    assert_true("stage=first-window-energy\n" in text)
    assert_true("MWDSP-FIXED-SYNC-CHECKSUM-V1\n" in text)
    # This literal locks the complete raw synchronization contract.
    assert_equal(checksum, UInt64(5897863583741909833))

    with assert_raises():
        _ = fixed_repetition_scan_raw(
            Span(samples),
            0,
            4,
            sample_format,
            accumulator_format,
            output_format,
        )
    with assert_raises():
        _ = fixed_repetition_scan_raw(
            Span(samples),
            4,
            4,
            sample_format,
            accumulator_format,
            QFormat(32, 8),
        )
    with assert_raises():
        _ = fixed_repetition_correlation_raw(
            Span(samples),
            Int.MAX,
            Int.MAX,
            Int.MAX,
            sample_format,
            accumulator_format,
            output_format,
        )
    with assert_raises():
        _ = fixed_window_energy_raw(
            Span(samples),
            Int.MAX,
            Int.MAX,
            sample_format,
            accumulator_format,
            output_format,
        )
    with assert_raises():
        _ = fixed_repetition_scan_raw(
            Span(samples),
            Int.MAX,
            Int.MAX,
            sample_format,
            accumulator_format,
            output_format,
        )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
