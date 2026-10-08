from std.collections import Span
from std.testing import assert_equal, assert_true, assert_raises, TestSuite
from wireless_dsp.numerics.fixed import (
    ROUND_NEAREST_AWAY,
    ROUND_TOWARD_ZERO,
    OVERFLOW_SATURATE,
    OVERFLOW_WRAP,
)
from wireless_dsp.numerics.quantization import QFormat
from wireless_dsp.numerics.complex_fixed import (
    ComplexRaw, complex_conjugate_raw,
)
from wireless_dsp.backend.fixed_phy_reference import (
    fixed_equalize_flat_raw,
    fixed_flat_channel_raw,
    fixed_ls_flat_channel_raw,
    fixed_ofdm_demodulate_raw,
    fixed_ofdm_modulate_raw,
    fixed_phy_canonical_rtl_vectors,
    fixed_phy_default_formats,
    fixed_phy_one_symbol_reference,
    fixed_phy_result_checksum,
    fixed_phy_scale_trace_text,
    fixed_qpsk_hard_bits,
    fixed_qpsk_llrs_raw,
    fixed_qpsk_map_raw,
    fixed_reciprocal_positive_raw,
)


def _oracle_fnv1a_text(text: StringSlice) -> UInt64:
    var state = UInt64(14695981039346656037)
    var bytes = text.as_bytes()
    for index in range(len(bytes)):
        state ^= UInt64(UInt8(bytes[index]))
        state *= UInt64(1099511628211)
    return state


def test_qpsk_mapping_llrs_ties_and_exhaustive_small_q() raises:
    var q2 = QFormat(4, 2)
    var bits: List[UInt8] = [0, 0, 0, 1, 1, 0, 1, 1]
    var mapped = fixed_qpsk_map_raw(Span(bits), q2, Int64(2))
    assert_equal(
        mapped,
        [
            ComplexRaw(2, 2),
            ComplexRaw(2, -2),
            ComplexRaw(-2, 2),
            ComplexRaw(-2, -2),
        ],
    )
    assert_equal(fixed_qpsk_hard_bits(Span(mapped), q2), bits)
    assert_equal(
        fixed_qpsk_llrs_raw(Span(mapped), q2, q2),
        [Int64(2), 2, 2, -2, -2, 2, -2, -2],
    )

    # Exhaust every signed Q2.2 I/Q word.  Coordinate LLRs are identity at an
    # unchanged binary point, and the documented zero tie selects bit zero.
    for re in range(-8, 8):
        for im in range(-8, 8):
            var one: List[ComplexRaw] = [ComplexRaw(Int64(re), Int64(im))]
            var llrs = fixed_qpsk_llrs_raw(Span(one), q2, q2)
            var hard = fixed_qpsk_hard_bits(Span(one), q2)
            assert_equal(llrs, [Int64(re), Int64(im)])
            assert_equal(hard[0], UInt8(0 if re >= 0 else 1))
            assert_equal(hard[1], UInt8(0 if im >= 0 else 1))


def test_reciprocal_rounding_overflow_and_flat_ls() raises:
    var q4_nearest = QFormat(
        8, 4, ROUND_NEAREST_AWAY, OVERFLOW_SATURATE
    )
    var q4_truncate = QFormat(
        8, 4, ROUND_TOWARD_ZERO, OVERFLOW_SATURATE
    )
    var q4_wrap = QFormat(8, 4, ROUND_NEAREST_AWAY, OVERFLOW_WRAP)
    assert_equal(
        fixed_reciprocal_positive_raw(Int64(24), q4_nearest, q4_nearest),
        Int64(11),
    )
    assert_equal(
        fixed_reciprocal_positive_raw(Int64(24), q4_nearest, q4_truncate),
        Int64(10),
    )
    assert_equal(
        fixed_reciprocal_positive_raw(Int64(1), q4_nearest, q4_nearest),
        Int64(127),
    )
    assert_equal(
        fixed_reciprocal_positive_raw(Int64(1), q4_nearest, q4_wrap),
        Int64(0),
    )
    with assert_raises():
        _ = fixed_reciprocal_positive_raw(
            Int64(0), q4_nearest, q4_nearest
        )

    var accumulator = QFormat(16, 8)
    var reciprocal = QFormat(16, 8)
    var reference: List[ComplexRaw] = [ComplexRaw(8, 0)]
    var received: List[ComplexRaw] = [ComplexRaw(6, 2)]
    assert_equal(
        fixed_ls_flat_channel_raw(
            Span(received),
            Span(reference),
            q4_nearest,
            q4_nearest,
            accumulator,
            reciprocal,
            q4_nearest,
        ),
        ComplexRaw(12, 4),
    )


def test_fixed_ofdm_cp_and_bit_exact_four_point_vector() raises:
    var formats = fixed_phy_default_formats()
    var bits: List[UInt8] = [0, 0, 0, 1, 1, 0, 1, 1]
    var mapped = fixed_qpsk_map_raw(
        Span(bits), formats.symbol, Int64(8192)
    )
    var waveform = fixed_ofdm_modulate_raw(
        Span(mapped),
        formats.symbol,
        formats.time,
        formats.twiddle,
        1,
    )
    assert_equal(len(waveform), 5)
    assert_equal(waveform[0], waveform[4])
    var restored = fixed_ofdm_demodulate_raw(
        Span(waveform),
        4,
        1,
        formats.time,
        formats.frequency,
        formats.twiddle,
    )
    assert_equal(restored, mapped)


def test_flat_channel_overflow_zero_channel_and_length_edges() raises:
    var tiny = QFormat(4, 2)
    var tiny_wrap = QFormat(
        4, 2, ROUND_NEAREST_AWAY, OVERFLOW_WRAP
    )
    assert_equal(
        complex_conjugate_raw(ComplexRaw(1, tiny.min_raw()), tiny),
        ComplexRaw(1, tiny.max_raw()),
    )
    assert_equal(
        complex_conjugate_raw(
            ComplexRaw(1, tiny_wrap.min_raw()), tiny_wrap
        ),
        ComplexRaw(1, tiny_wrap.min_raw()),
    )
    var one: List[ComplexRaw] = [ComplexRaw(7, 0)]
    var saturated = fixed_flat_channel_raw(
        Span(one), tiny, ComplexRaw(7, 7), tiny, tiny
    )
    assert_equal(saturated, [ComplexRaw(7, 7)])

    var formats = fixed_phy_default_formats()
    var received: List[ComplexRaw] = [ComplexRaw(8192, -8192)]
    with assert_raises():
        _ = fixed_equalize_flat_raw(
            Span(received),
            formats.symbol,
            ComplexRaw(),
            formats.channel,
            formats.accumulator,
            formats.reciprocal,
            formats.symbol,
        )
    var odd_bits: List[UInt8] = [0, 1, 0]
    with assert_raises():
        _ = fixed_qpsk_map_raw(
            Span(odd_bits), formats.symbol, Int64(8192)
        )
    var bad_bit: List[UInt8] = [0, 2]
    with assert_raises():
        _ = fixed_qpsk_map_raw(
            Span(bad_bit), formats.symbol, Int64(8192)
        )
    var non_power: List[ComplexRaw] = [
        ComplexRaw(), ComplexRaw(), ComplexRaw()
    ]
    with assert_raises():
        _ = fixed_ofdm_modulate_raw(
            Span(non_power),
            formats.symbol,
            formats.time,
            formats.twiddle,
            0,
        )
    with assert_raises():
        _ = fixed_ofdm_demodulate_raw(
            Span(received),
            4,
            1,
            formats.time,
            formats.frequency,
            formats.twiddle,
        )


def test_representative_one_symbol_chain_float64_audit() raises:
    var formats = fixed_phy_default_formats()
    var bits = List[UInt8](capacity=16)
    for i in range(16):
        bits.append(UInt8((i * 5 + i // 3) & 1))
    var result = fixed_phy_one_symbol_reference(
        Span(bits),
        8,
        2,
        ComplexRaw(12288, 4096),
        formats,
        Int64(8192),
        2,
    )
    assert_equal(result.decoded_bits, bits)
    assert_equal(result.audit.bit_errors, 0)
    assert_equal(result.audit.bits_checked, 16)
    assert_true(result.audit.evm_rms < 0.001)
    assert_true(
        result.channel_estimate.re >= 12284
        and result.channel_estimate.re <= 12292
    )
    assert_true(
        result.channel_estimate.im >= 4092
        and result.channel_estimate.im <= 4100
    )
    assert_true(fixed_phy_result_checksum(result) != UInt64(0))


def test_canonical_rtl_vector_scale_trace_and_static_checksum() raises:
    var formats = fixed_phy_default_formats()
    var bits: List[UInt8] = [0, 0, 0, 1, 1, 0, 1, 1]
    var result = fixed_phy_one_symbol_reference(
        Span(bits),
        4,
        1,
        ComplexRaw(16384, 0),
        formats,
        Int64(8192),
    )
    assert_equal(result.mapped_symbols, [
        ComplexRaw(8192, 8192),
        ComplexRaw(8192, -8192),
        ComplexRaw(-8192, 8192),
        ComplexRaw(-8192, -8192),
    ])
    assert_equal(result.transmit_samples, [
        ComplexRaw(4096, -4096),
        ComplexRaw(0, 0),
        ComplexRaw(4096, 4096),
        ComplexRaw(0, 8192),
        ComplexRaw(4096, -4096),
    ])
    assert_equal(result.channel_samples, result.transmit_samples)
    assert_equal(result.received_bins, result.mapped_symbols)
    assert_equal(result.channel_estimate, ComplexRaw(16384, 0))
    assert_equal(result.equalized_symbols, result.mapped_symbols)
    assert_equal(result.decoded_bits, bits)
    assert_equal(result.audit.bit_errors, 0)
    assert_equal(result.audit.evm_rms, 0.0)
    var scale_text = fixed_phy_scale_trace_text(4, formats, Int64(8192))
    # Independently computed FNV-1a pins every UTF-8 artifact byte.
    assert_equal(
        _oracle_fnv1a_text(StringSlice(scale_text)),
        UInt64(4528951871083113016),
    )
    assert_true(scale_text.startswith("MWDSP-SCALE-TRACE-V2\n"))
    assert_true("stage=ifft-registers\n" in scale_text)
    assert_true(
        "data=4096:18:14:1:1:1,2048:18:14:1:1:1\n" in scale_text
    )
    assert_true("stage=fft-registers\n" in scale_text)
    assert_true(
        "data=8192:24:14:0:1:1,8192:24:14:0:1:1\n" in scale_text
    )
    var vectors = fixed_phy_canonical_rtl_vectors(result, formats)
    assert_equal(
        _oracle_fnv1a_text(StringSlice(vectors)),
        UInt64(609735544018071287),
    )
    assert_true(vectors.startswith("MWDSP-COMPLEX-FIXED-V2\n"))
    assert_true("stage=qpsk-grid\n" in vectors)
    assert_true("stage=ls-channel\n" in vectors)
    assert_true("stage=hard-bits\n" in vectors)
    assert_true("MWDSP-FIXED-PHY-CHECKSUM-V1\nchecksum=" in vectors)
    assert_true(
        vectors.endswith(
            "MWDSP-FIXED-PHY-CHECKSUM-V1\n"
            "checksum=3268373756385669765\n"
        )
    )
    assert_equal(
        fixed_phy_result_checksum(result), UInt64(3268373756385669765)
    )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
