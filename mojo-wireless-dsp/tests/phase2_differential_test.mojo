from std.testing import assert_equal, assert_true, TestSuite
from std.math import cos, sin
from wireless_dsp.core import Complex64, Span
from wireless_dsp.dsp import fft, ifft
from wireless_dsp.modem import qam_map, qam_demap_hard, crc_bits
from wireless_dsp.channel import add_awgn

comptime TWO_PI = 6.283185307179586476925286766559

def direct_dft(values: Span[Complex64, ...]) -> List[Complex64]:
    var result = List[Complex64](capacity=len(values))
    for k in range(len(values)):
        var acc = Complex64(0.0, 0.0)
        for n in range(len(values)):
            var angle = -TWO_PI * Float64(k * n) / Float64(len(values))
            var twiddle = Complex64(cos(angle), sin(angle))
            var sample = Complex64(values[n].re, values[n].im)
            acc = acc + sample * twiddle
        result.append(acc)
    return result^

def test_fft_against_independent_dft() raises:
    var values = List[Complex64](capacity=16)
    for i in range(16):
        values.append(Complex64(Float64((i * 7) % 11) - 5.0, Float64((i * 3) % 5) - 2.0))
    var actual = fft(Span(values))
    var expected = direct_dft(Span(values))
    for i in range(16):
        assert_true(abs(actual[i].re - expected[i].re) < 1.0e-9)
        assert_true(abs(actual[i].im - expected[i].im) < 1.0e-9)

def test_fft_required_sizes_roundtrip() raises:
    for size in [64, 128, 256, 512, 1024, 2048, 4096]:
        var values = List[Complex64](capacity=size)
        for i in range(size):
            values.append(Complex64(Float64((i * 17) % 29) / 29.0, Float64((i * 13) % 31) / 31.0))
        var spectrum = fft(Span(values))
        var restored = ifft(Span(spectrum))
        for i in range(size):
            assert_true(abs(restored[i].re - values[i].re) < 1.0e-9)
            assert_true(abs(restored[i].im - values[i].im) < 1.0e-9)

def test_all_constellation_labels_roundtrip_and_unit_energy() raises:
    for bits_per_symbol in [1, 2, 4, 6, 8, 10, 12]:
        var order = 1 << bits_per_symbol
        var bits = List[UInt8](capacity=order * bits_per_symbol)
        for label in range(order):
            for bit_index in range(bits_per_symbol):
                bits.append(UInt8((label >> (bits_per_symbol - bit_index - 1)) & 1))
        var symbols = qam_map(Span(bits), bits_per_symbol)
        assert_equal(qam_demap_hard(Span(symbols), bits_per_symbol), bits)
        var energy = 0.0
        for i in range(len(symbols)):
            energy += symbols[i].re * symbols[i].re + symbols[i].im * symbols[i].im
        assert_true(abs(energy / Float64(order) - 1.0) < 1.0e-12)

def test_crc8_check_vector_123456789() raises:
    var octets: List[Int] = [49, 50, 51, 52, 53, 54, 55, 56, 57]
    var bits = List[UInt8](capacity=72)
    for octet in octets:
        for shift in range(7, -1, -1):
            bits.append(UInt8((octet >> shift) & 1))
    assert_equal(crc_bits(Span(bits), width=8, polynomial=UInt64(0x07)), UInt64(0xF4))

def test_awgn_empirical_power() raises:
    var zeros = List[Complex64](capacity=20000)
    for _ in range(20000):
        zeros.append(Complex64(0.0, 0.0))
    var noisy = add_awgn(Span(zeros), 0.2, seed=UInt64(20260821))
    var power = 0.0
    var mean_re = 0.0
    var mean_im = 0.0
    for i in range(len(noisy)):
        mean_re += noisy[i].re
        mean_im += noisy[i].im
        power += noisy[i].re * noisy[i].re + noisy[i].im * noisy[i].im
    mean_re /= Float64(len(noisy))
    mean_im /= Float64(len(noisy))
    power /= Float64(len(noisy))
    assert_true(abs(mean_re) < 0.01)
    assert_true(abs(mean_im) < 0.01)
    assert_true(abs(power - 0.2) < 0.01)

def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
