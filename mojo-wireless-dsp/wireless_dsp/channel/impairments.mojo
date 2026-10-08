"""Deterministic channel impairments with explicit random seed."""

from std.collections import Span
from std.math import cos, isfinite, log, remainder, round, sin, sqrt
from wireless_dsp.core import Complex64

comptime _TWO_PI = 6.283185307179586476925286766559
comptime _FNV1A64_OFFSET = UInt64(14695981039346656037)
comptime _FNV1A64_PRIME = UInt64(1099511628211)

def _next_uniform(mut state: UInt64) -> Float64:
    state = state * UInt64(6364136223846793005) + UInt64(1442695040888963407)
    return (Float64(state >> 11) + 0.5) / 9007199254740992.0


def _fnv1a_noise_q12_be(mut checksum: UInt64, value: Float64):
    # Q12 remains far finer than any decision tolerance used by these CPU
    # references while avoiding false mismatches from conforming libm
    # implementations of Box--Muller transcendental functions.
    var bits = UInt64(Int64(round(value * 4096.0)))
    for byte_index in range(8):
        var shift = UInt64(56 - 8 * byte_index)
        checksum ^= (bits >> shift) & UInt64(0xFF)
        checksum *= _FNV1A64_PRIME


def _add_awgn_with_fingerprint(
    samples: Span[Complex64, ...],
    noise_variance: Float64,
    mut fingerprint: UInt64,
    *,
    seed: UInt64,
) raises -> List[Complex64]:
    """Shared AWGN execution plus a quantized big-endian noise fingerprint.

    The fingerprint is a deterministic testing diagnostic over the exact
    production-path real/imaginary noise samples after signed Q12
    quantization.  It does not alter the public AWGN result and is neither a
    radio-standard checksum nor a cryptographic integrity mechanism.
    """
    if not isfinite(noise_variance) or noise_variance < 0.0:
        raise Error("noise variance must be finite and non-negative")
    for index in range(len(samples)):
        if not isfinite(samples[index].re) or not isfinite(samples[index].im):
            raise Error("AWGN input samples must be finite")
    var state = seed
    # Taking sqrt first preserves the smallest positive subnormal variances;
    # multiplying by 0.5 first can round them to zero and disable the noise.
    var sigma = sqrt(noise_variance) * sqrt(0.5)
    var result = List[Complex64](capacity=len(samples))
    for i in range(len(samples)):
        var u1 = _next_uniform(state)
        var u2 = _next_uniform(state)
        var radius = sigma * sqrt(-2.0 * log(u1))
        var noise_re = radius * cos(_TWO_PI * u2)
        var noise_im = radius * sin(_TWO_PI * u2)
        _fnv1a_noise_q12_be(fingerprint, noise_re)
        _fnv1a_noise_q12_be(fingerprint, noise_im)
        var output = Complex64(
            samples[i].re + noise_re,
            samples[i].im + noise_im,
        )
        if not isfinite(output.re) or not isfinite(output.im):
            raise Error("AWGN output samples must remain finite")
        result.append(output)
    return result^

def add_awgn(
    samples: Span[Complex64, ...], noise_variance: Float64, *, seed: UInt64
) raises -> List[Complex64]:
    """Add circular complex Gaussian noise with E[|n|^2]=noise_variance."""
    var fingerprint = _FNV1A64_OFFSET
    return _add_awgn_with_fingerprint(
        samples, noise_variance, fingerprint, seed=seed
    )

def apply_cfo(
    samples: Span[Complex64, ...], normalized_frequency: Float64, *, initial_phase: Float64 = 0.0
) raises -> List[Complex64]:
    """Apply CFO in cycles/sample and an initial phase in radians."""
    if not isfinite(normalized_frequency) or not isfinite(initial_phase):
        raise Error("CFO frequency and initial phase must be finite")
    var result = List[Complex64](capacity=len(samples))
    var phase = remainder(initial_phase, _TWO_PI)
    var increment = _TWO_PI * remainder(normalized_frequency, 1.0)
    for i in range(len(samples)):
        if not isfinite(samples[i].re) or not isfinite(samples[i].im):
            raise Error("CFO input samples must be finite")
        var oscillator = Complex64(cos(phase), sin(phase))
        var sample = Complex64(samples[i].re, samples[i].im)
        var output = sample * oscillator
        if not isfinite(output.re) or not isfinite(output.im):
            raise Error("CFO output samples must remain finite")
        result.append(output)
        phase = remainder(phase + increment, _TWO_PI)
    return result^

def awgn_and_cfo(
    samples: Span[Complex64, ...], noise_variance: Float64,
    normalized_frequency: Float64, *, seed: UInt64, initial_phase: Float64 = 0.0,
) raises -> List[Complex64]:
    var shifted = apply_cfo(samples, normalized_frequency, initial_phase=initial_phase)
    return add_awgn(Span(shifted), noise_variance, seed=seed)
