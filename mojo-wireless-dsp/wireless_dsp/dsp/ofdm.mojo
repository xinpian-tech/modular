"""Protocol-independent OFDM cyclic-prefix and transform primitives."""

from std.collections import Span
from wireless_dsp.core import Complex64
from .fft import fft, ifft


def ofdm_modulate(
    spectrum: Span[Complex64, ...], cyclic_prefix: Int
) raises -> List[Complex64]:
    if cyclic_prefix < 0 or cyclic_prefix > len(spectrum):
        raise Error("invalid cyclic-prefix length")
    var time = ifft(spectrum)
    var result = List[Complex64](capacity=len(time) + cyclic_prefix)
    for i in range(len(time) - cyclic_prefix, len(time)):
        result.append(time[i])
    for i in range(len(time)):
        result.append(time[i])
    return result^


def ofdm_demodulate(
    samples: Span[Complex64, ...], transform_size: Int, cyclic_prefix: Int
) raises -> List[Complex64]:
    if cyclic_prefix < 0 or len(samples) != transform_size + cyclic_prefix:
        raise Error("OFDM symbol length does not match FFT and CP")
    var time = List[Complex64](capacity=transform_size)
    for i in range(transform_size):
        var sample = samples[cyclic_prefix + i]
        time.append(Complex64(sample.re, sample.im))
    return fft(Span(time))
