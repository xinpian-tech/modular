from std.collections import Span
from std.math import cos, floor, nan, sin
from std.testing import assert_equal, assert_true, assert_raises, TestSuite
from wireless_dsp.numerics.fixed import (
    ROUND_NEAREST_AWAY,
    ROUND_TOWARD_ZERO,
    OVERFLOW_SATURATE,
    OVERFLOW_WRAP,
)
from wireless_dsp.numerics.quantization import (
    FLOAT64_EXACT_INTEGER_BITS,
    QFormat,
    dequantize_raw,
    fixed_abs_raw,
    fixed_add_raw,
    fixed_sub_raw,
    fixed_mac_raw,
    fixed_max_raw,
    fixed_min_raw,
    fixed_mul_raw,
    fixed_shift_raw,
    narrow_raw,
    quantize_raw,
    raw_fits,
    rescale_raw,
    rounded_shift_right,
    validate_qformat,
)
from wireless_dsp.numerics.complex_fixed import (
    ComplexRaw,
    complex_mac_conjugate_raw,
    complex_mac_raw,
    complex_mul_raw,
)
from wireless_dsp.numerics.scale_schedule import (
    ScaleStage,
    apply_scale_schedule,
    radix2_fft_scale_schedule,
)
from wireless_dsp.backend.fixed_reference import (
    complex_cross_correlate_raw,
    complex_dot_conjugate_raw,
    complex_fir_raw,
    fixed_dot_raw,
    fixed_fir_raw,
)
from wireless_dsp.backend.fixed_fft_reference import (
    fixed_fft_radix2_raw,
    fixed_fft_radix2_trace_raw,
    quantized_fft_twiddles,
    serialize_fixed_fft_trace,
)
from wireless_dsp.testing.fixed_vectors import (
    complex_raw_checksum,
    fixed_raw_checksum,
    serialize_complex_fixed_vector,
    serialize_fixed_vector,
    serialize_scale_trace,
)


def _oracle_fnv1a_text(text: StringSlice) -> UInt64:
    var state = UInt64(14695981039346656037)
    var bytes = text.as_bytes()
    for index in range(len(bytes)):
        state ^= UInt64(UInt8(bytes[index]))
        state *= UInt64(1099511628211)
    return state


def _reference_quantize_unit(value: Float64, fraction_bits: Int) -> Int64:
    var scale = Float64(Int64(1) << Int64(fraction_bits))
    var magnitude = floor(abs(value) * scale + 0.5)
    return Int64(-magnitude if value < 0.0 else magnitude)


def test_runtime_qformat_quantization_and_overflow() raises:
    assert_equal(FLOAT64_EXACT_INTEGER_BITS, 53)
    var nearest = QFormat(8, 4)
    var truncate = QFormat(8, 4, ROUND_TOWARD_ZERO)
    var wrap = QFormat(8, 4, ROUND_NEAREST_AWAY, OVERFLOW_WRAP)
    assert_equal(quantize_raw(1.53125, nearest), Int64(25))
    assert_equal(quantize_raw(-1.53125, nearest), Int64(-25))
    assert_equal(quantize_raw(1.53125, truncate), Int64(24))
    assert_equal(quantize_raw(-1.53125, truncate), Int64(-24))
    assert_equal(quantize_raw(100.0, nearest), Int64(127))
    assert_equal(quantize_raw(-100.0, nearest), Int64(-128))
    assert_equal(quantize_raw(8.0, wrap), Int64(-128))
    assert_equal(dequantize_raw(Int64(24), nearest), 1.5)
    assert_true(raw_fits(Int64(-128), nearest))
    assert_true(not raw_fits(Int64(128), nearest))
    assert_equal(narrow_raw(Int64(130), nearest), Int64(127))
    assert_equal(narrow_raw(Int64(130), wrap), Int64(-126))
    assert_equal(narrow_raw(Int64.MAX_FINITE, wrap), Int64(-1))
    assert_equal(narrow_raw(Int64.MIN_FINITE, wrap), Int64(0))
    assert_true(validate_qformat(nearest) == nearest)

    # Float64 is a convenient real-valued ingress only while every adjacent
    # raw code is representable by its 53-bit significand.  Wider formats
    # remain valid for integer-raw arithmetic and audit dequantization.
    var q53 = QFormat(FLOAT64_EXACT_INTEGER_BITS, 0)
    var q54 = QFormat(FLOAT64_EXACT_INTEGER_BITS + 1, 0)
    assert_equal(quantize_raw(1.0, q53), Int64(1))
    assert_true(raw_fits(Int64(1), q54))
    assert_equal(dequantize_raw(Int64(1), q54), 1.0)
    with assert_raises():
        _ = quantize_raw(1.0, q54)

    # Descriptors are field-addressable for legacy callers, so every numeric
    # boundary must reject a descriptor mutated after construction.
    var malformed = QFormat(8, 4)
    malformed.fraction_bits = 8
    assert_true(not raw_fits(Int64(0), malformed))
    with assert_raises():
        _ = validate_qformat(malformed)
    with assert_raises():
        _ = narrow_raw(Int64(0), malformed)
    with assert_raises():
        _ = quantize_raw(0.0, malformed)
    malformed = QFormat(8, 4)
    malformed.rounding_mode = 99
    with assert_raises():
        _ = fixed_add_raw(
            Int64(0), malformed, Int64(0), nearest, nearest
        )
    with assert_raises():
        _ = complex_mul_raw(
            ComplexRaw(), malformed, ComplexRaw(), nearest, nearest
        )


def test_rescale_add_multiply_and_edges() raises:
    var q4 = QFormat(8, 4)
    var q2 = QFormat(8, 2)
    var q0_wrap = QFormat(8, 0, ROUND_NEAREST_AWAY, OVERFLOW_WRAP)
    assert_equal(rescale_raw(Int64(-5), 2, q2), Int64(-5))
    assert_equal(rescale_raw(Int64(-5), 2, QFormat(8, 1)), Int64(-3))
    assert_equal(
        rounded_shift_right(
            Int64.MIN_FINITE, 1, ROUND_TOWARD_ZERO
        ),
        Int64(-4611686018427387904),
    )
    assert_equal(rescale_raw(Int64(100), 0, q0_wrap), Int64(100))
    assert_equal(
        rescale_raw(
            Int64(100),
            0,
            QFormat(8, 2, ROUND_NEAREST_AWAY, OVERFLOW_WRAP),
        ),
        Int64(-112),
    )
    assert_equal(
        fixed_add_raw(Int64(24), q4, Int64(2), q2, q4), Int64(32)
    )
    assert_equal(
        fixed_sub_raw(Int64(24), q4, Int64(2), q2, q4), Int64(16)
    )
    assert_equal(
        fixed_mul_raw(Int64(24), q4, Int64(8), q4, q4), Int64(12)
    )
    assert_equal(
        fixed_mac_raw(Int64(120), Int64(24), q4, Int64(8), q4, q4),
        Int64(127),
    )
    assert_equal(fixed_shift_raw(Int64(-5), 1, q4), Int64(-3))
    assert_equal(fixed_shift_raw(Int64(100), -1, q4), Int64(127))
    assert_equal(fixed_abs_raw(Int64(-128), q4), Int64(127))
    assert_equal(
        fixed_abs_raw(Int64(-128), q0_wrap), Int64(-128)
    )
    assert_equal(fixed_min_raw(Int64(-3), Int64(7), q4), Int64(-3))
    assert_equal(fixed_max_raw(Int64(-3), Int64(7), q4), Int64(7))
    with assert_raises():
        _ = QFormat(1, 0)
    with assert_raises():
        _ = dequantize_raw(Int64(128), q4)
    with assert_raises():
        _ = quantize_raw(nan[DType.float64](), q4)
    with assert_raises():
        _ = fixed_mul_raw(
            Int64(0), QFormat(32, 0), Int64(0), q4, q4
        )


def test_complex_fixed_multiply_and_registered_mac() raises:
    var q4 = QFormat(8, 4)
    var a = ComplexRaw(Int64(24), Int64(-8))
    var b = ComplexRaw(Int64(8), Int64(16))
    assert_equal(complex_mul_raw(a, q4, b, q4, q4), ComplexRaw(20, 20))
    assert_equal(
        complex_mac_raw(ComplexRaw(120, 120), a, q4, b, q4, q4),
        ComplexRaw(127, 127),
    )
    assert_equal(
        complex_mac_conjugate_raw(
            ComplexRaw(),
            ComplexRaw(16, 16),
            q4,
            ComplexRaw(16, -16),
            q4,
            q4,
        ),
        ComplexRaw(0, -32),
    )


def test_scale_schedule_records_every_hardware_boundary() raises:
    var q4 = QFormat(8, 4)
    var stages: List[ScaleStage] = [
        ScaleStage(q4, 1), ScaleStage(q4, 1), ScaleStage(q4, 1)
    ]
    var trace = apply_scale_schedule(Int64(100), q4, Span(stages))
    assert_equal(trace.values, [Int64(50), Int64(25), Int64(13)])
    assert_equal(trace.fraction_bits, [4, 4, 4])
    assert_equal(trace.storage_bits, [8, 8, 8])
    assert_equal(trace.right_shifts, [1, 1, 1])
    assert_equal(trace.rounding_modes, [
        ROUND_NEAREST_AWAY, ROUND_NEAREST_AWAY, ROUND_NEAREST_AWAY
    ])
    assert_equal(trace.overflow_modes, [
        OVERFLOW_SATURATE, OVERFLOW_SATURATE, OVERFLOW_SATURATE
    ])
    var trace_text = serialize_scale_trace(
        "fft64-vector", "butterfly-scales", trace
    )
    assert_true(trace_text.startswith("MWDSP-SCALE-TRACE-V2\n"))
    assert_true("shape=3x6\n" in trace_text)
    assert_true(
        trace_text.endswith(
            "data=50:8:4:1:1:1,25:8:4:1:1:1,13:8:4:1:1:1\n"
        )
    )

    var mixed_stages: List[ScaleStage] = [
        ScaleStage(QFormat(8, 2, ROUND_TOWARD_ZERO, OVERFLOW_WRAP), 1),
        ScaleStage(QFormat(8, 2, ROUND_NEAREST_AWAY, OVERFLOW_SATURATE), 1),
    ]
    var mixed_trace = apply_scale_schedule(
        Int64(7), QFormat(8, 2), Span(mixed_stages)
    )
    assert_equal(mixed_trace.values, [Int64(3), Int64(2)])
    assert_equal(mixed_trace.rounding_modes, [
        ROUND_TOWARD_ZERO, ROUND_NEAREST_AWAY
    ])
    assert_equal(mixed_trace.overflow_modes, [
        OVERFLOW_WRAP, OVERFLOW_SATURATE
    ])
    var mixed_text = serialize_scale_trace(
        "mixed-modes", "registers", mixed_trace
    )
    assert_true(mixed_text.endswith(
        "data=3:8:2:1:0:0,2:8:2:1:1:1\n"
    ))
    var protective_stage: List[ScaleStage] = [ScaleStage(q4, 1)]
    assert_equal(
        apply_scale_schedule(
            Int64(200), QFormat(16, 4), Span(protective_stage)
        ).values,
        [Int64(100)],
    )

    var fft_stages = radix2_fft_scale_schedule(64, 16, 12)
    assert_equal(len(fft_stages), 6)
    var fft_trace = apply_scale_schedule(
        Int64(64), QFormat(16, 12), Span(fft_stages)
    )
    assert_equal(fft_trace.values, [
        Int64(32), Int64(16), Int64(8), Int64(4), Int64(2), Int64(1)
    ])
    with assert_raises():
        _ = radix2_fft_scale_schedule(63, 16, 12)
    with assert_raises():
        _ = ScaleStage(q4, -1)


def test_fixed_fir_and_complex_kernel_checkpoints() raises:
    var q4 = QFormat(8, 4)
    var accumulator = QFormat(20, 8)
    var samples: List[Int64] = [16, 32, 48]
    var taps: List[Int64] = [8, 8]
    var dot_samples: List[Int64] = [16, 32]
    assert_equal(
        fixed_dot_raw(
            Span(dot_samples), Span(taps), q4, q4, accumulator, q4
        ),
        Int64(24),
    )
    assert_equal(
        fixed_fir_raw(
            Span(samples), Span(taps), q4, q4, accumulator, q4
        ),
        [Int64(8), Int64(24), Int64(40)],
    )

    var complex_samples: List[ComplexRaw] = [
        ComplexRaw(16, 16), ComplexRaw(32, 0)
    ]
    var complex_taps: List[ComplexRaw] = [ComplexRaw(0, 16)]
    assert_equal(
        complex_fir_raw(
            Span(complex_samples),
            Span(complex_taps),
            q4,
            q4,
            accumulator,
            q4,
        ),
        [ComplexRaw(-16, 16), ComplexRaw(0, 32)],
    )

    var lhs: List[ComplexRaw] = [ComplexRaw(16, 16)]
    var rhs: List[ComplexRaw] = [ComplexRaw(16, -16)]
    assert_equal(
        complex_dot_conjugate_raw(
            Span(lhs), Span(rhs), q4, q4, accumulator, q4
        ),
        ComplexRaw(0, -32),
    )

    var correlation_signal: List[ComplexRaw] = [
        ComplexRaw(),
        ComplexRaw(16, 0),
        ComplexRaw(0, 16),
        ComplexRaw(),
    ]
    var correlation_reference: List[ComplexRaw] = [
        ComplexRaw(16, 0), ComplexRaw(0, 16)
    ]
    var correlation = complex_cross_correlate_raw(
        Span(correlation_signal),
        Span(correlation_reference),
        q4,
        q4,
        accumulator,
        q4,
    )
    assert_equal(correlation, [
        ComplexRaw(0, -16), ComplexRaw(32, 0), ComplexRaw(0, 16)
    ])


def test_fixed_fft_and_ifft_with_explicit_twiddles() raises:
    var q8 = QFormat(16, 8)
    var q16 = QFormat(24, 16)
    var twiddles: List[ComplexRaw] = [
        ComplexRaw(256, 0), ComplexRaw(0, -256)
    ]
    var q16_wrap = QFormat(
        24, 16, ROUND_TOWARD_ZERO, OVERFLOW_WRAP
    )
    var stages: List[ScaleStage] = [
        ScaleStage(q16), ScaleStage(q16_wrap)
    ]
    var values: List[ComplexRaw] = [
        ComplexRaw(256),
        ComplexRaw(512),
        ComplexRaw(768),
        ComplexRaw(1024),
    ]
    var spectrum = fixed_fft_radix2_raw(
        Span(values), q8, Span(twiddles), q8, Span(stages)
    )
    assert_equal(spectrum, [
        ComplexRaw(655360, 0),
        ComplexRaw(-131072, 131072),
        ComplexRaw(-131072, 0),
        ComplexRaw(-131072, -131072),
    ])

    var trace = fixed_fft_radix2_trace_raw(
        Span(values), q8, Span(twiddles), q8, Span(stages)
    )
    assert_equal(trace.size, 4)
    assert_true(trace.input_format == q8)
    assert_true(trace.twiddle_format == q8)
    assert_equal(trace.input_values, values)
    assert_equal(trace.twiddles, twiddles)
    assert_equal(trace.stage_values, [
        ComplexRaw(262144, 0),
        ComplexRaw(-131072, 0),
        ComplexRaw(393216, 0),
        ComplexRaw(-131072, 0),
        ComplexRaw(655360, 0),
        ComplexRaw(-131072, 131072),
        ComplexRaw(-131072, 0),
        ComplexRaw(-131072, -131072),
    ])
    assert_equal(trace.stage_storage_bits, [24, 24])
    assert_equal(trace.stage_fraction_bits, [16, 16])
    assert_equal(trace.stage_right_shifts, [0, 0])
    assert_equal(trace.stage_rounding_modes, [
        ROUND_NEAREST_AWAY, ROUND_TOWARD_ZERO
    ])
    assert_equal(trace.stage_overflow_modes, [
        OVERFLOW_SATURATE, OVERFLOW_WRAP
    ])
    assert_equal(trace.output, spectrum)
    var trace_text = serialize_fixed_fft_trace(
        "fft4-contract-v2", "fft", trace
    )
    # Independently computed FNV-1a pins every UTF-8 artifact byte.
    assert_equal(
        _oracle_fnv1a_text(StringSlice(trace_text)),
        UInt64(13996704339464434850),
    )
    assert_true(trace_text.startswith("MWDSP-FIXED-V2\n"))
    assert_true("stage=fft-twiddle-rom\n" in trace_text)
    assert_true("stage=fft-schedule\n" in trace_text)
    assert_true("stage=fft-stage-0\n" in trace_text)
    assert_true("stage=fft-stage-1\n" in trace_text)
    assert_true(
        "data=262144:24:16:0:1:1,655360:24:16:0:0:0\n"
        in trace_text
    )
    assert_true("stage=fft-trace-checksum-lohi32\n" in trace_text)
    assert_equal(
        trace_text,
        serialize_fixed_fft_trace("fft4-contract-v2", "fft", trace),
    )
    trace.output[0] = ComplexRaw()
    with assert_raises():
        _ = serialize_fixed_fft_trace("fft4-contract-v2", "fft", trace)

    var inverse_twiddles: List[ComplexRaw] = [
        ComplexRaw(256, 0), ComplexRaw(0, 256)
    ]
    var inverse_stages: List[ScaleStage] = [
        ScaleStage(q16, 1), ScaleStage(q16, 1)
    ]
    var restored = fixed_fft_radix2_raw(
        Span(spectrum),
        q16,
        Span(inverse_twiddles),
        q8,
        Span(inverse_stages),
    )
    assert_equal(restored, [
        ComplexRaw(65536),
        ComplexRaw(131072),
        ComplexRaw(196608),
        ComplexRaw(262144),
    ])

    var generated = quantized_fft_twiddles(4, q8)
    assert_equal(generated[0], ComplexRaw(256, 0))
    assert_equal(generated[1], ComplexRaw(0, -256))
    with assert_raises():
        _ = fixed_fft_radix2_raw(
            Span(values), q8, Span(twiddles), q8, Span(inverse_stages[:1])
        )
    with assert_raises():
        _ = fixed_fft_radix2_trace_raw(
            Span(values), q8, Span(twiddles), q8, Span(inverse_stages[:1])
        )

    var q15 = QFormat(16, 15)
    var twiddle_q = QFormat(18, 16)
    var impulse = List[ComplexRaw](
        length=64, fill=ComplexRaw()
    )
    impulse[0] = ComplexRaw(16384, 0)
    var twiddle64 = quantized_fft_twiddles(64, twiddle_q)
    var scaled_stages = radix2_fft_scale_schedule(64, 16, 15)
    var impulse_trace = fixed_fft_radix2_trace_raw(
        Span(impulse),
        q15,
        Span(twiddle64),
        twiddle_q,
        Span(scaled_stages),
    )
    assert_equal(len(impulse_trace.stage_values), 64 * 6)
    assert_equal(impulse_trace.stage_right_shifts, [1, 1, 1, 1, 1, 1])
    for i in range(64):
        assert_equal(impulse_trace.output[i], ComplexRaw(256, 0))

    var singleton: List[ComplexRaw] = [ComplexRaw(5, -3)]
    var no_twiddles = List[ComplexRaw]()
    var no_stages = List[ScaleStage]()
    var singleton_trace = fixed_fft_radix2_trace_raw(
        Span(singleton),
        q8,
        Span(no_twiddles),
        q8,
        Span(no_stages),
    )
    assert_equal(singleton_trace.input_values, singleton)
    assert_equal(len(singleton_trace.twiddles), 0)
    assert_equal(len(singleton_trace.stage_values), 0)
    assert_equal(singleton_trace.output, singleton)
    assert_true(
        "stage=fft1-output\n" in serialize_fixed_fft_trace(
            "fft1-contract-v2", "fft1", singleton_trace
        )
    )


def test_quantized_fft_twiddles_analytic_grid_and_mutation_edges() raises:
    comptime two_pi = 6.283185307179586476925286766559
    for size in [1, 2, 4, 8, 16, 64, 256, 1024]:
        for inverse in [False, True]:
            var qformat = QFormat(18, 16)
            var first = quantized_fft_twiddles(
                size, qformat, inverse=inverse
            )
            var second = quantized_fft_twiddles(
                size, qformat, inverse=inverse
            )
            assert_equal(first, second)
            assert_equal(len(first), size // 2)
            var direction = two_pi if inverse else -two_pi
            for k in range(size // 2):
                var angle = direction * Float64(k) / Float64(size)
                assert_equal(
                    first[k].re,
                    _reference_quantize_unit(cos(angle), 16),
                )
                assert_equal(
                    first[k].im,
                    _reference_quantize_unit(sin(angle), 16),
                )
    var valid = QFormat(18, 16)
    with assert_raises():
        _ = quantized_fft_twiddles(Int.MIN, valid)
    with assert_raises():
        _ = quantized_fft_twiddles(Int.MAX, valid)
    var invalid_storage = valid
    invalid_storage.storage_bits = Int.MAX
    with assert_raises():
        _ = quantized_fft_twiddles(8, invalid_storage)
    var invalid_fraction = valid
    invalid_fraction.fraction_bits = Int.MIN
    with assert_raises():
        _ = quantized_fft_twiddles(8, invalid_fraction)


def test_exhaustive_q2_2_multiplier_matches_independent_integer_oracle() raises:
    var q2 = QFormat(4, 2)
    for lhs in range(-8, 8):
        for rhs in range(-8, 8):
            var product = Int64(lhs * rhs)
            var expected: Int64
            if product < 0:
                expected = -(((-product) + 2) >> 2)
            else:
                expected = (product + 2) >> 2
            expected = min(Int64(7), max(Int64(-8), expected))
            assert_equal(
                fixed_mul_raw(
                    Int64(lhs), q2, Int64(rhs), q2, q2
                ),
                expected,
            )


def test_fixed_vector_serialization_is_canonical() raises:
    var q4 = QFormat(8, 4)
    var values: List[Int64] = [Int64(8), Int64(-24), Int64(40)]
    var first = serialize_fixed_vector(
        "wifi-vector-001", "fir-output", Span(values), q4
    )
    var second = serialize_fixed_vector(
        "wifi-vector-001", "fir-output", Span(values), q4
    )
    assert_equal(first, second)
    assert_true(first.startswith("MWDSP-FIXED-V2\ntestcase=wifi-vector-001\n"))
    assert_true(
        "dtype=sint8\nshape=3\nstride=1\nlayout=scalar-contiguous\n"
        in first
    )
    assert_true(
        "storage_bits=8\nfraction_bits=4\nscale_numerator=1\nscale_denominator=16\n"
        in first
    )
    assert_true("checksum_scope=header-utf8+data-int64-le\n" in first)
    assert_true(first.endswith("data=8,-24,40\n"))
    assert_equal(
        fixed_raw_checksum(Span(values)), UInt64(9795727541193530362)
    )

    var complex_values: List[ComplexRaw] = [
        ComplexRaw(-16, 16), ComplexRaw(0, 32)
    ]
    var encoded = serialize_complex_fixed_vector(
        "nr-vector-001", "complex-fir", Span(complex_values), q4
    )
    assert_true(encoded.startswith("MWDSP-COMPLEX-FIXED-V2\n"))
    assert_true("shape=2x2\n" in encoded)
    assert_true("layout=iq-interleaved-contiguous\n" in encoded)
    assert_true(
        "checksum_scope=header-utf8+data-iq-int64-le\n" in encoded
    )
    assert_true(encoded.endswith("data_iq=-16:16,0:32\n"))
    assert_equal(
        complex_raw_checksum(Span(complex_values)),
        UInt64(17168011761098253202),
    )
    with assert_raises():
        _ = serialize_fixed_vector(
            "bad\nid", "stage", Span(values), q4
        )
    with assert_raises():
        _ = serialize_fixed_vector(
            "id", "stage", Span(values), q4, stride=2
        )
    with assert_raises():
        _ = serialize_complex_fixed_vector(
            "id", "stage", Span(complex_values), q4, stride=2
        )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
