"""Direct evidence for public kernels that were previously only indirect."""

from std.collections import Span
from std.math import cos, sin, sqrt
from std.testing import assert_equal, assert_raises, assert_true, TestSuite
from std.utils.numerics import inf, nan
from wireless_dsp.core import Complex64
from wireless_dsp.dsp import (
    apply_window_real,
    complex_divide,
    convolve_complex,
    dft_reference,
    fft_in_place,
    sum_complex,
)
from wireless_dsp.modem import crc_reflected_bits
from wireless_dsp.synchronization import (
    detect_repetition_start,
    estimate_repetition_cfo,
    repetition_metric,
)
from wireless_dsp.fec import (
    polar_5g_rate_match,
    polar_5g_rate_recover_llrs,
    polar_5g_subblock_deinterleave_llrs,
    polar_5g_subblock_interleave,
)
from wireless_dsp.numerics import ComplexRaw, QFormat
from wireless_dsp.backend import fixed_qpsk_float64_audit


comptime _TWO_PI = 6.283185307179586476925286766559


def _assert_complex_close(
    actual: Complex64, expected: Complex64, tolerance: Float64
) raises:
    assert_true(abs(actual.re - expected.re) <= tolerance)
    assert_true(abs(actual.im - expected.im) <= tolerance)


def _crc_reflected_oracle(
    bits: Span[UInt8, ...], width: Int, polynomial: UInt64,
    initial: UInt64, xor_out: UInt64,
) raises -> UInt64:
    var mask = (UInt64(1) << UInt64(width)) - 1
    var register = initial & mask
    for index in range(len(bits)):
        if bits[index] > 1:
            raise Error("oracle bits must be binary")
        register ^= UInt64(bits[index])
        for _ in range(1):
            var low = register & UInt64(1)
            register >>= UInt64(1)
            if low != 0:
                register ^= polynomial & mask
    return (register ^ xor_out) & mask


def test_window_convolution_and_complex_sum_direct_oracles() raises:
    var values: List[Float64] = [1.0, -2.0, 3.0, -4.0]
    var window: List[Float64] = [0.25, 0.5, -1.0, 2.0]
    assert_equal(
        apply_window_real(Span(values), Span(window)),
        [0.25, -1.0, -3.0, -8.0],
    )

    var lhs: List[Complex64] = [
        Complex64(1.0, 2.0), Complex64(-0.5, 0.25)
    ]
    var rhs: List[Complex64] = [
        Complex64(0.75, -1.0), Complex64(2.0, 0.5)
    ]
    var convolution = convolve_complex(Span(lhs), Span(rhs))
    var expected: List[Complex64] = [
        Complex64(2.75, 0.5),
        Complex64(0.875, 5.1875),
        Complex64(-1.125, 0.25),
    ]
    assert_equal(convolution, expected)
    assert_equal(convolve_complex(Span(rhs), Span(lhs)), expected)
    assert_equal(sum_complex(Span(convolution)), Complex64(2.5, 5.9375))

    # Deterministic property grid checked against separately accumulated
    # scalar formulas, not against another library kernel.
    var property_values = List[Complex64](capacity=97)
    var expected_sum = Complex64(0.0, 0.0)
    for index in range(97):
        var value = Complex64(
            Float64((17 * index + 3) % 29) / 13.0 - 1.0,
            Float64((11 * index + 5) % 31) / 17.0 - 0.75,
        )
        property_values.append(value)
        expected_sum = Complex64(
            expected_sum.re + value.re, expected_sum.im + value.im
        )
    _assert_complex_close(
        sum_complex(Span(property_values)), expected_sum, 1.0e-13
    )

    var empty_real = List[Float64]()
    var empty_window = List[Float64]()
    var empty_complex = List[Complex64]()
    assert_equal(
        apply_window_real(Span(empty_real), Span(empty_window)), empty_real
    )
    assert_equal(
        convolve_complex(Span(empty_complex), Span(lhs)), empty_complex
    )
    assert_equal(
        sum_complex(Span(empty_complex)), Complex64(0.0, 0.0)
    )
    with assert_raises():
        _ = apply_window_real(Span(values), Span(empty_real))


def test_complex_divide_and_repetition_estimators_direct_oracles() raises:
    _assert_complex_close(
        complex_divide(Complex64(3.0, 4.0), Complex64(1.0, -2.0)),
        Complex64(-1.0, 2.0),
        1.0e-15,
    )
    for index in range(1, 65):
        var numerator = Complex64(
            Float64(index) / 9.0 - 2.0,
            Float64((7 * index) % 19) / 11.0 - 0.5,
        )
        var denominator = Complex64(
            0.5 + Float64((5 * index) % 13) / 7.0,
            Float64((3 * index) % 17) / 13.0 - 0.6,
        )
        var quotient = complex_divide(numerator, denominator)
        _assert_complex_close(quotient * denominator, numerator, 3.0e-14)

    # Scale-invariant analytic quotients at both ends of Float64's practical
    # range.  Raw |rhs|^2 arithmetic would underflow/overflow these cases.
    _assert_complex_close(
        complex_divide(Complex64(1.0e-200), Complex64(1.0e-200)),
        Complex64(1.0),
        1.0e-15,
    )
    _assert_complex_close(
        complex_divide(
            Complex64(1.0e200, -1.0e200),
            Complex64(1.0e200, 1.0e200),
        ),
        Complex64(0.0, -1.0),
        1.0e-15,
    )

    var base: List[Complex64] = [
        Complex64(1.0, 0.25),
        Complex64(-0.5, 1.0),
        Complex64(0.75, -0.125),
        Complex64(-1.25, -0.5),
    ]
    for frequency in [-0.0625, -0.03125, 0.0, 0.03125, 0.0625]:
        var samples = List[Complex64](capacity=12)
        for index in range(12):
            var phase = _TWO_PI * frequency * Float64(index)
            samples.append(
                base[index % 4] * Complex64(cos(phase), sin(phase))
            )
        assert_true(abs(repetition_metric(Span(samples), 0, 4, 8) - 1.0) < 1.0e-13)
        assert_true(
            abs(estimate_repetition_cfo(Span(samples), 0, 4, 8) - frequency)
            < 2.0e-15
        )

    # Normalized detection and CFO must remain invariant across the finite
    # Float64 dynamic range.  Raw product/energy accumulation overflows at the
    # large scale and underflows at the small scale.
    for amplitude in [1.0e-308, 1.0e308]:
        var extreme = List[Complex64](capacity=12)
        var frequency = 0.0625
        for index in range(12):
            var phase = _TWO_PI * frequency * Float64(index)
            extreme.append(
                Complex64(
                    amplitude * cos(phase), amplitude * sin(phase)
                )
            )
        assert_true(
            abs(repetition_metric(Span(extreme), 0, 4, 8) - 1.0)
            < 2.0e-14
        )
        assert_true(
            abs(
                estimate_repetition_cfo(Span(extreme), 0, 4, 8)
                - frequency
            ) < 2.0e-15
        )
        assert_equal(
            detect_repetition_start(Span(extreme), 4, 8, 0.999), 0
        )

    with assert_raises():
        _ = complex_divide(Complex64(1.0), Complex64(0.0))
    with assert_raises():
        _ = complex_divide(
            Complex64(nan[DType.float64]()), Complex64(1.0)
        )
    with assert_raises():
        _ = complex_divide(
            Complex64(1.0), Complex64(inf[DType.float64]())
        )
    with assert_raises():
        _ = complex_divide(
            Complex64(1.0e308), Complex64(1.0e-308)
        )
    var too_short: List[Complex64] = [Complex64(1.0), Complex64(1.0)]
    with assert_raises():
        _ = repetition_metric(Span(too_short), 0, 4, 1)
    with assert_raises():
        _ = estimate_repetition_cfo(Span(too_short), -1, 1, 1)
    with assert_raises():
        _ = repetition_metric(Span(too_short), Int.MAX, 1, 1)
    with assert_raises():
        _ = detect_repetition_start(Span(too_short), Int.MAX, 1, 0.5)
    var nonfinite: List[Complex64] = [
        Complex64(1.0), Complex64(inf[DType.float64]())
    ]
    with assert_raises():
        _ = repetition_metric(Span(nonfinite), 0, 1, 1)


def test_fft_in_place_direct_dft_differential_and_edges() raises:
    var impulse = List[Complex64](
        length=8, fill=Complex64(0.0, 0.0)
    )
    impulse[0] = Complex64(1.0, 0.0)
    fft_in_place(impulse)
    for value in impulse:
        _assert_complex_close(value, Complex64(1.0, 0.0), 1.0e-15)
    fft_in_place(impulse, inverse=True)
    _assert_complex_close(impulse[0], Complex64(1.0, 0.0), 1.0e-14)
    for index in range(1, 8):
        _assert_complex_close(impulse[index], Complex64(0.0, 0.0), 1.0e-14)

    for length in [2, 4, 8, 16, 32, 64]:
        var values = List[Complex64](capacity=length)
        for index in range(length):
            values.append(Complex64(
                Float64((19 * index + 1) % 37) / 19.0 - 0.8,
                Float64((13 * index + 7) % 41) / 23.0 - 0.9,
            ))
        var expected = dft_reference(Span(values))
        fft_in_place(values)
        for index in range(length):
            _assert_complex_close(values[index], expected[index], 4.0e-12)

    var empty = List[Complex64]()
    with assert_raises():
        fft_in_place(empty)
    var three: List[Complex64] = [
        Complex64(1.0), Complex64(2.0), Complex64(3.0)
    ]
    with assert_raises():
        fft_in_place(three)


def test_crc_reflected_bits_standard_and_bitwise_oracles() raises:
    var bits = List[UInt8](capacity=72)
    for octet in [0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39]:
        for bit in range(8):
            bits.append(UInt8((octet >> bit) & 1))
    var crc = crc_reflected_bits(
        Span(bits),
        width=32,
        polynomial=UInt64(0xEDB88320),
        initial=UInt64(0xFFFFFFFF),
        xor_out=UInt64(0xFFFFFFFF),
    )
    assert_equal(crc, UInt64(0xCBF43926))
    assert_equal(
        crc,
        _crc_reflected_oracle(
            Span(bits),
            32,
            UInt64(0xEDB88320),
            UInt64(0xFFFFFFFF),
            UInt64(0xFFFFFFFF),
        ),
    )
    bits[17] ^= UInt8(1)
    assert_true(
        crc_reflected_bits(
            Span(bits),
            width=32,
            polynomial=UInt64(0xEDB88320),
            initial=UInt64(0xFFFFFFFF),
            xor_out=UInt64(0xFFFFFFFF),
        ) != UInt64(0xCBF43926)
    )
    bits[0] = UInt8(2)
    with assert_raises():
        _ = crc_reflected_bits(
            Span(bits), width=32, polynomial=UInt64(0xEDB88320)
        )
    var empty = List[UInt8]()
    with assert_raises():
        _ = crc_reflected_bits(Span(empty), width=0, polynomial=UInt64(1))
    with assert_raises():
        _ = crc_reflected_bits(Span(empty), width=64, polynomial=UInt64(1))


def test_polar5g_subblock_rate_match_and_recovery_static_oracles() raises:
    var coded: List[UInt8] = [
        0, 1, 1, 0, 1, 0, 0, 1, 1, 1, 0, 0, 1, 0, 1, 0,
        0, 1, 0, 1, 1, 0, 1, 1, 0, 0, 1, 1, 0, 1, 0, 1,
    ]
    var expected_interleaved: List[UInt8] = [
        0, 1, 1, 1, 0, 0, 0, 1, 1, 0, 1, 1, 0, 0, 0, 1,
        1, 1, 0, 0, 1, 1, 0, 1, 0, 0, 1, 0, 1, 1, 0, 1,
    ]
    assert_equal(
        polar_5g_subblock_interleave(Span(coded)), expected_interleaved
    )

    var interleaved_markers: List[Float64] = [
        1.0, 2.0, 3.0, 5.0, 4.0, 6.0, 7.0, 8.0,
        9.0, 17.0, 10.0, 18.0, 11.0, 19.0, 12.0, 20.0,
        13.0, 21.0, 14.0, 22.0, 15.0, 23.0, 16.0, 24.0,
        25.0, 26.0, 27.0, 29.0, 28.0, 30.0, 31.0, 32.0,
    ]
    var recovered_markers = polar_5g_subblock_deinterleave_llrs(
        Span(interleaved_markers)
    )
    for index in range(32):
        assert_equal(recovered_markers[index], Float64(index + 1))

    var expected_repeat: List[UInt8] = [
        0, 1, 1, 1, 0, 0, 0, 1, 1, 0, 1, 1, 0, 0, 0, 1,
        1, 1, 0, 0, 1, 1, 0, 1, 0, 0, 1, 0, 1, 1, 0, 1,
        0, 1, 1, 1, 0, 0, 0, 1, 1, 0, 1, 1, 0, 0, 0, 1,
    ]
    assert_equal(
        polar_5g_rate_match(Span(coded), 48, 16), expected_repeat
    )
    var expected_puncture: List[UInt8] = [
        1, 0, 1, 1, 0, 0, 0, 1, 1, 1, 0, 0,
        1, 1, 0, 1, 0, 0, 1, 0, 1, 1, 0, 1,
    ]
    assert_equal(
        polar_5g_rate_match(Span(coded), 24, 8), expected_puncture
    )
    var expected_shorten: List[UInt8] = [
        0, 1, 1, 1, 0, 0, 0, 1, 1, 0, 1, 1,
        0, 0, 0, 1, 1, 1, 0, 0, 1, 1, 0, 1,
    ]
    assert_equal(
        polar_5g_rate_match(Span(coded), 24, 16), expected_shorten
    )

    var repeat_llrs = List[Float64](capacity=48)
    for bit in expected_repeat:
        repeat_llrs.append(2.0 if bit == 0 else -2.0)
    var recovered = polar_5g_rate_recover_llrs(
        Span(repeat_llrs), 32, 16
    )
    var repeated_source_indices: List[Int] = [
        0, 1, 2, 4, 3, 5, 6, 7, 8, 16, 9, 17, 10, 18, 11, 19,
    ]
    for index in range(32):
        var magnitude = 2.0
        for repeated in repeated_source_indices:
            if repeated == index:
                magnitude = 4.0
        assert_equal(
            recovered[index], magnitude if coded[index] == 0 else -magnitude
        )

    var invalid_length: List[UInt8] = [0, 1, 0]
    with assert_raises():
        _ = polar_5g_subblock_interleave(Span(invalid_length))
    coded[0] = UInt8(2)
    with assert_raises():
        _ = polar_5g_subblock_interleave(Span(coded))
    interleaved_markers[0] = nan[DType.float64]()
    with assert_raises():
        _ = polar_5g_subblock_deinterleave_llrs(Span(interleaved_markers))
    var one_llr: List[Float64] = [1.0]
    with assert_raises():
        _ = polar_5g_rate_recover_llrs(Span(one_llr), 31, 1)
    with assert_raises():
        _ = polar_5g_rate_recover_llrs(
            Span(one_llr), 32, 1, shortening_llr=inf[DType.float64]()
        )


def test_fixed_qpsk_float64_audit_direct_oracle_and_edges() raises:
    var q12 = QFormat(16, 12)
    var bits: List[UInt8] = [0, 0, 0, 1, 1, 0, 1, 1]
    var symbols: List[ComplexRaw] = [
        ComplexRaw(4096, 4096),
        ComplexRaw(4096, -4096),
        ComplexRaw(-4096, 4096),
        ComplexRaw(-4096, -4096),
    ]
    var exact = fixed_qpsk_float64_audit(Span(bits), Span(symbols), q12, 1.0)
    assert_equal(exact.evm_rms, 0.0)
    assert_equal(exact.bit_errors, 0)
    assert_equal(exact.bits_checked, 8)

    symbols[0] = ComplexRaw(4100, 4096)
    var perturbed = fixed_qpsk_float64_audit(
        Span(bits), Span(symbols), q12, 1.0
    )
    assert_true(
        abs(perturbed.evm_rms - (4.0 / 4096.0) / sqrt(8.0)) < 1.0e-15
    )
    assert_equal(perturbed.bit_errors, 0)

    var short_bits: List[UInt8] = [0]
    with assert_raises():
        _ = fixed_qpsk_float64_audit(
            Span(short_bits), Span(symbols), q12, 1.0
        )
    var empty_bits = List[UInt8]()
    var empty_symbols = List[ComplexRaw]()
    with assert_raises():
        _ = fixed_qpsk_float64_audit(
            Span(empty_bits), Span(empty_symbols), q12, 1.0
        )
    with assert_raises():
        _ = fixed_qpsk_float64_audit(
            Span(bits), Span(symbols), q12, nan[DType.float64]()
        )
    with assert_raises():
        _ = fixed_qpsk_float64_audit(
            Span(bits), Span(symbols), q12, 1.0e308
        )
    bits[0] = UInt8(2)
    with assert_raises():
        _ = fixed_qpsk_float64_audit(Span(bits), Span(symbols), q12, 1.0)
    bits[0] = UInt8(0)
    symbols[0] = ComplexRaw(32768, 0)
    with assert_raises():
        _ = fixed_qpsk_float64_audit(Span(bits), Span(symbols), q12, 1.0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
