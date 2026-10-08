#!/usr/bin/env python3
"""Generate an independent static oracle for the legacy BPSK/AWGN link API.

This generator deliberately has no dependency on ``wireless_dsp`` and does
not execute Mojo.  It is a direct, scalar Python transcription of the public
mathematical chain exercised by ``simulate_wifi_legacy_bpsk_awgn``:

* a specified 64-bit LCG supplies payload bits and fixed-seed uniforms;
* the additive x^7+x^4+1 scrambler and terminated K=7, rate-1/2 code are
  evaluated with integer recurrences;
* the 48-position BPSK interleaver and 64-point OFDM transform are evaluated
  from their index equations and O(N^2) DFT sums;
* circular AWGN is generated with the Box--Muller transform and
  E[|n|^2] equal to the requested variance;
* a scalar, forced-zero-state hard Viterbi recurrence recovers the payload.

Only Python's standard library is used.  The output records SHA-256 digests
of the generator, the binary64 big-endian noise stream, every discrete chain
checkpoint, and the canonical fixture rows.  No IEEE document or production
implementation is used as an oracle source.
"""

from __future__ import annotations

from dataclasses import dataclass
import hashlib
import math
from pathlib import Path
import struct
import sys


MASK64 = (1 << 64) - 1
FNV1A64_OFFSET = 14_695_981_039_346_656_037
FNV1A64_PRIME = 1_099_511_628_211
LCG_MULTIPLIER = 6_364_136_223_846_793_005
LCG_INCREMENT = 1_442_695_040_888_963_407
PAYLOAD_SALT = 0x94D049BB133111EB
PACKET_SEED_STRIDE = 0x9E3779B97F4A7C15
SCRAMBLER_SEED = 0x5D
GENERATORS = (0o133, 0o171)
CONSTRAINT_LENGTH = 7
DATA_SUBCARRIERS = tuple(
    subcarrier
    for subcarrier in range(-26, 27)
    if subcarrier not in (0, -21, -7, 7, 21)
)


@dataclass(frozen=True)
class FixtureResult:
    packets: int
    noise_variance: float
    seed: int
    bit_count: int
    bit_errors: int
    packet_errors: int
    minimum_bpsk_margin: float
    noise_sha256: str
    checkpoints_sha256: str
    noise_fnv1a64: int
    checkpoints_fnv1a64: int


def fnv1a64_update(state: int, values: bytes) -> int:
    for value in values:
        state = ((state ^ value) * FNV1A64_PRIME) & MASK64
    return state


def quantized_noise_bytes(packed_noise: bytes) -> bytes:
    values = struct.iter_unpack(">d", packed_noise)
    return b"".join(
        struct.pack(">q", round(value[0] * (1 << 12))) for value in values
    )


def lcg_step(state: int) -> int:
    return (state * LCG_MULTIPLIER + LCG_INCREMENT) & MASK64


def payload_bit(state: int) -> tuple[int, int]:
    state = lcg_step(state)
    return state, (state >> 63) & 1


def uniform(state: int) -> tuple[int, float]:
    state = lcg_step(state)
    return state, (float(state >> 11) + 0.5) / 9_007_199_254_740_992.0


def scramble(bits: list[int]) -> list[int]:
    state = SCRAMBLER_SEED
    output: list[int] = []
    for bit in bits:
        feedback = ((state >> 6) ^ (state >> 3)) & 1
        output.append(bit ^ feedback)
        state = ((state << 1) & 0x7E) | feedback
    return output


def parity(value: int) -> int:
    return value.bit_count() & 1


def convolutional_encode(bits: list[int]) -> list[int]:
    register = 0
    output: list[int] = []
    for bit in bits + [0] * (CONSTRAINT_LENGTH - 1):
        register = ((register << 1) | bit) & 0x7F
        output.extend(parity(register & generator) for generator in GENERATORS)
    return output


def interleave(bits: list[int]) -> list[int]:
    assert len(bits) == 48
    output = [0] * 48
    for source in range(48):
        destination = 3 * (source % 16) + source // 16
        output[destination] = bits[source]
    return output


def deinterleave(bits: list[int]) -> list[int]:
    assert len(bits) == 48
    return [bits[3 * (source % 16) + source // 16] for source in range(48)]


def transform(values: list[complex], *, inverse: bool) -> list[complex]:
    """Direct DFT definition, intentionally unrelated to an FFT library."""
    length = len(values)
    sign = 1.0 if inverse else -1.0
    output: list[complex] = []
    for frequency in range(length):
        total = 0.0j
        for time, value in enumerate(values):
            angle = sign * 2.0 * math.pi * frequency * time / length
            total += value * complex(math.cos(angle), math.sin(angle))
        output.append(total / length if inverse else total)
    return output


def map_ofdm(interleaved: list[int]) -> list[complex]:
    spectrum = [0.0j] * 64
    for subcarrier, bit in zip(DATA_SUBCARRIERS, interleaved, strict=True):
        spectrum[subcarrier % 64] = complex(1.0 if bit == 0 else -1.0, 0.0)
    for subcarrier, value in ((-21, 1.0), (-7, 1.0), (7, 1.0), (21, -1.0)):
        spectrum[subcarrier % 64] = complex(value, 0.0)
    useful = transform(spectrum, inverse=True)
    return useful[-16:] + useful


def add_awgn(
    samples: list[complex], noise_variance: float, seed: int
) -> tuple[list[complex], bytes]:
    state = seed & MASK64
    sigma = math.sqrt(noise_variance) * math.sqrt(0.5)
    output: list[complex] = []
    packed_noise = bytearray()
    for sample in samples:
        state, u1 = uniform(state)
        state, u2 = uniform(state)
        radius = sigma * math.sqrt(-2.0 * math.log(u1))
        noise = complex(
            radius * math.cos(2.0 * math.pi * u2),
            radius * math.sin(2.0 * math.pi * u2),
        )
        packed_noise.extend(struct.pack(">dd", noise.real, noise.imag))
        output.append(sample + noise)
    return output, bytes(packed_noise)


def extract_bpsk(samples: list[complex]) -> tuple[list[int], float]:
    spectrum = transform(samples[16:], inverse=False)
    values = [spectrum[subcarrier % 64].real for subcarrier in DATA_SUBCARRIERS]
    return [0 if value >= 0.0 else 1 for value in values], min(map(abs, values))


def viterbi_decode(encoded: list[int]) -> list[int]:
    state_count = 1 << (CONSTRAINT_LENGTH - 1)
    steps = len(encoded) // len(GENERATORS)
    infinity = 1_000_000_000
    metrics = [infinity] * state_count
    metrics[0] = 0
    predecessors = [[-1] * state_count for _ in range(steps)]
    decisions = [[0] * state_count for _ in range(steps)]
    for step in range(steps):
        next_metrics = [infinity] * state_count
        observed = encoded[2 * step : 2 * step + 2]
        for previous in range(state_count):
            if metrics[previous] == infinity:
                continue
            for input_bit in (0, 1):
                register = (previous << 1) | input_bit
                next_state = register & (state_count - 1)
                expected = [
                    parity(register & generator) for generator in GENERATORS
                ]
                distance = sum(a != b for a, b in zip(expected, observed, strict=True))
                candidate = metrics[previous] + distance
                if candidate < next_metrics[next_state]:
                    next_metrics[next_state] = candidate
                    predecessors[step][next_state] = previous
                    decisions[step][next_state] = input_bit
        metrics = next_metrics
    state = 0
    decoded = [0] * steps
    for step in range(steps - 1, -1, -1):
        decoded[step] = decisions[step][state]
        state = predecessors[step][state]
        if state < 0:
            raise RuntimeError("unreachable forced-zero traceback")
    return decoded[: -(CONSTRAINT_LENGTH - 1)]


def simulate(packets: int, noise_variance: float, seed: int) -> FixtureResult:
    payload_state = seed ^ PAYLOAD_SALT
    bit_errors = 0
    packet_errors = 0
    minimum_margin = math.inf
    noise_hasher = hashlib.sha256()
    checkpoint_hasher = hashlib.sha256()
    noise_fnv1a64 = FNV1A64_OFFSET
    checkpoints_fnv1a64 = FNV1A64_OFFSET
    for packet in range(packets):
        payload: list[int] = []
        for _ in range(18):
            payload_state, bit = payload_bit(payload_state)
            payload.append(bit)
        scrambled = scramble(payload)
        coded = convolutional_encode(scrambled)
        interleaved = interleave(coded)
        waveform = map_ofdm(interleaved)
        noisy, packed_noise = add_awgn(
            waveform,
            noise_variance,
            seed + packet * PACKET_SEED_STRIDE,
        )
        hard, margin = extract_bpsk(noisy)
        deinterleaved = deinterleave(hard)
        decoded = viterbi_decode(deinterleaved)
        recovered = scramble(decoded)

        noise_hasher.update(packed_noise)
        noise_fnv1a64 = fnv1a64_update(
            noise_fnv1a64, quantized_noise_bytes(packed_noise)
        )
        for checkpoint in (
            payload,
            scrambled,
            coded,
            interleaved,
            hard,
            deinterleaved,
            decoded,
            recovered,
        ):
            checkpoint_bytes = bytes(checkpoint)
            checkpoint_hasher.update(checkpoint_bytes)
            checkpoints_fnv1a64 = fnv1a64_update(
                checkpoints_fnv1a64, checkpoint_bytes
            )
        minimum_margin = min(minimum_margin, margin)
        errors = sum(a != b for a, b in zip(payload, recovered, strict=True))
        bit_errors += errors
        packet_errors += errors != 0

    return FixtureResult(
        packets=packets,
        noise_variance=noise_variance,
        seed=seed,
        bit_count=18 * packets,
        bit_errors=bit_errors,
        packet_errors=packet_errors,
        minimum_bpsk_margin=minimum_margin,
        noise_sha256=noise_hasher.hexdigest(),
        checkpoints_sha256=checkpoint_hasher.hexdigest(),
        noise_fnv1a64=noise_fnv1a64,
        checkpoints_fnv1a64=checkpoints_fnv1a64,
    )


def canonical_rows(results: list[FixtureResult]) -> str:
    header = (
        "packets\tnoise_variance_hex\tseed_hex\tbit_count\tbit_errors\t"
        "packet_errors\tminimum_bpsk_margin\tnoise_f64be_sha256\t"
        "checkpoints_sha256\tnoise_q12be_fnv1a64\tcheckpoints_fnv1a64\n"
    )
    rows = []
    for result in results:
        rows.append(
            "\t".join(
                (
                    str(result.packets),
                    result.noise_variance.hex(),
                    f"0x{result.seed:016x}",
                    str(result.bit_count),
                    str(result.bit_errors),
                    str(result.packet_errors),
                    result.minimum_bpsk_margin.hex(),
                    result.noise_sha256,
                    result.checkpoints_sha256,
                    f"0x{result.noise_fnv1a64:016x}",
                    f"0x{result.checkpoints_fnv1a64:016x}",
                )
            )
        )
    return header + "\n".join(rows) + "\n"


def main() -> None:
    configurations = [
        (1, 0.0, 0x0000000000000000),
        (3, 0.01, 0x0000000000080211),
        (7, 0.05, 0x0000000005EED123),
        (11, 0.2, 0x00000000BADC0DE5),
        (5, 1.0, 0xFEDCBA9876543210),
    ]
    results = [simulate(*configuration) for configuration in configurations]
    rows = canonical_rows(results)
    generator_sha256 = hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
    rows_sha256 = hashlib.sha256(rows.encode("ascii")).hexdigest()
    print("# MWDSP-WIFI-LEGACY-BPSK-AWGN-ORACLE-V1")
    print(f"# generator_sha256={generator_sha256}")
    print(
        "# generator_runtime="
        f"CPython_{sys.version_info.major}.{sys.version_info.minor}.{sys.version_info.micro}"
    )
    print("# dependencies=python_standard_library_only")
    print("# float_format=IEEE-754_binary64;noise_packing=big-endian_real_then_imag")
    print("# result_tolerance=exact;minimum_bpsk_margin_is_diagnostic_only")
    print(f"# canonical_rows_sha256={rows_sha256}")
    print(rows, end="")


if __name__ == "__main__":
    main()
