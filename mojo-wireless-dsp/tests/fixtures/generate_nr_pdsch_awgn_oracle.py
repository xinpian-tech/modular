#!/usr/bin/env python3
"""Generate an external static oracle for ``simulate_nr_pdsch_awgn``.

This script never imports ``wireless_dsp`` and never executes Mojo.  The
external transmit stages use the public ``catkira/py3gpp`` implementation at
the exact commit recorded below for the frozen normative profile.  The flat
channel, unsigned 64-bit LCG,
Box--Muller AWGN, comb-2 LS/interpolation/ZF receiver, QPSK LLRs, and flooding
normalized-min-sum decoder are separate scalar Python implementations.

The frozen normative scope is 3GPP TS 38.211 V18.9.0 clauses 5.2.1 and
7.3--7.4 plus TS 38.212 V18.8.0 clauses 5.1, 5.2.2, 5.3.2, 5.4.2, and 7.2.
Channel estimation, equalization, AWGN generation, and the chosen flooding
decoder are non-normative reference-receiver operations.

Regeneration example (the dependency checkout must be exactly the pinned
commit, and the generated stdout is the fixture file):

    git clone https://github.com/catkira/py3gpp /tmp/py3gpp
    git -C /tmp/py3gpp checkout 17b432b30c965ffd350257ee4b1fc4de642c8e37
    python generate_nr_pdsch_awgn_oracle.py --py3gpp /tmp/py3gpp

The script requires NumPy, SciPy, and importlib-resources because those are
runtime dependencies of the pinned py3gpp implementation.  Every fixture row
records hashes of the discrete and binary64 intermediate checkpoints.
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass
import hashlib
import math
from pathlib import Path
import struct
import subprocess
import sys


PY3GPP_COMMIT = "17b432b30c965ffd350257ee4b1fc4de642c8e37"
PY3GPP_REPOSITORY = "https://github.com/catkira/py3gpp"
MASK64 = (1 << 64) - 1
FNV1A64_OFFSET = 14_695_981_039_346_656_037
FNV1A64_PRIME = 1_099_511_628_211
LCG_MULTIPLIER = 6_364_136_223_846_793_005
LCG_INCREMENT = 1_442_695_040_888_963_407
PAYLOAD_SALT = 0xA24BAED4963EE407
PACKET_SEED_STRIDE = 0x9E3779B97F4A7C15
GAIN = complex(0.9, 0.2)
FILLER_LLR = 50.0
LLR_CLIP = 50.0
NORMALIZATION = 0.8
MAX_ITERATIONS = 30


@dataclass(frozen=True)
class FixtureResult:
    packet_count: int
    noise_variance: float
    seed: int
    payload_bits: int
    output_bits: int
    modulation_order: int
    bit_count: int
    bit_errors: int
    packet_errors: int
    per_packet_bit_errors: tuple[int, ...]
    per_packet_failures: tuple[int, ...]
    minimum_payload_posterior_margin: float
    noise_f64be_sha256: str
    discrete_checkpoints_sha256: str
    receiver_f64be_sha256: str
    noise_q12be_fnv1a64: int
    observable_discrete_fnv1a64: int


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


def next_payload_bit(state: int) -> tuple[int, int]:
    state = lcg_step(state)
    return state, (state >> 63) & 1


def next_uniform(state: int) -> tuple[int, float]:
    state = lcg_step(state)
    return state, (float(state >> 11) + 0.5) / 9_007_199_254_740_992.0


def pack_float64(hasher: object, values: list[float]) -> None:
    for value in values:
        hasher.update(struct.pack(">d", value))


def pack_complex64(hasher: object, values: list[complex]) -> None:
    for value in values:
        hasher.update(struct.pack(">dd", value.real, value.imag))


def add_awgn(
    samples: list[complex], noise_variance: float, seed: int
) -> tuple[list[complex], bytes]:
    state = seed & MASK64
    sigma = math.sqrt(noise_variance) * math.sqrt(0.5)
    output: list[complex] = []
    packed_noise = bytearray()
    for sample in samples:
        state, u1 = next_uniform(state)
        state, u2 = next_uniform(state)
        radius = sigma * math.sqrt(-2.0 * math.log(u1))
        noise = complex(
            radius * math.cos(2.0 * math.pi * u2),
            radius * math.sin(2.0 * math.pi * u2),
        )
        packed_noise.extend(struct.pack(">dd", noise.real, noise.imag))
        output.append(sample + noise)
    return output, bytes(packed_noise)


def complex_divide(numerator: complex, denominator: complex) -> complex:
    energy = denominator.real * denominator.real + denominator.imag * denominator.imag
    if energy == 0.0:
        raise ZeroDivisionError("singular independent channel estimate")
    return complex(
        (
            numerator.real * denominator.real
            + numerator.imag * denominator.imag
        )
        / energy,
        (
            numerator.imag * denominator.real
            - numerator.real * denominator.imag
        )
        / energy,
    )


def comb2_receive(
    noisy_grid: list[complex], known_dmrs: list[complex], noise_variance: float
) -> tuple[list[complex], list[complex], list[complex], list[float]]:
    received_dmrs = noisy_grid[0::2]
    received_data = noisy_grid[1::2]
    pilots = [
        complex_divide(received, known)
        for received, known in zip(received_dmrs, known_dmrs, strict=True)
    ]
    channel: list[complex] = []
    for local in range(len(noisy_grid)):
        if local % 2 == 0:
            channel.append(pilots[local // 2])
        elif local + 1 < len(noisy_grid):
            left = pilots[local // 2]
            right = pilots[local // 2 + 1]
            channel.append(0.5 * left + 0.5 * right)
        else:
            channel.append(pilots[-1])
    equalized = [
        complex_divide(sample, channel[2 * index + 1])
        for index, sample in enumerate(received_data)
    ]
    llrs: list[float] = []
    qpsk_factor = 2.0 * math.sqrt(2.0)
    for index, symbol in enumerate(equalized):
        estimate = channel[2 * index + 1]
        power = estimate.real * estimate.real + estimate.imag * estimate.imag
        llrs.append(qpsk_factor * symbol.real * power / noise_variance)
        llrs.append(qpsk_factor * symbol.imag * power / noise_variance)
    return received_data, channel, equalized, llrs


def base_graph_rows(py3gpp_root: Path, base_graph: int, lifting: int) -> list[list[int]]:
    del py3gpp_root
    from py3gpp.nrDLSCHInfo import getZarray
    from py3gpp.nrLDPCEncode import _load_basegraph

    lifting_set = next(
        index for index, values in enumerate(getZarray()) if lifting in values
    )
    matrix = _load_basegraph(lifting_set, base_graph)
    rows: list[list[int]] = []
    for base_row in range(matrix.shape[0]):
        active_columns = [
            column
            for column in range(matrix.shape[1])
            if int(matrix[base_row, column]) >= 0
        ]
        for lifted_row in range(lifting):
            rows.append(
                [
                    column * lifting
                    + (lifted_row + int(matrix[base_row, column])) % lifting
                    for column in active_columns
                ]
            )
    return rows


def syndrome_ok(bits: list[int], rows: list[list[int]]) -> bool:
    for row in rows:
        parity = 0
        for column in row:
            parity ^= bits[column]
        if parity != 0:
            return False
    return True


def flooding_normalized_min_sum(
    channel_llrs: list[float], rows: list[list[int]]
) -> tuple[list[int], int, bool, list[float]]:
    edge_columns = [column for row in rows for column in row]
    row_offsets = [0]
    for row in rows:
        row_offsets.append(row_offsets[-1] + len(row))
    variable_to_check = [
        max(-LLR_CLIP, min(LLR_CLIP, channel_llrs[column]))
        for column in edge_columns
    ]
    check_to_variable = [0.0] * len(edge_columns)
    posterior = [0.0] * len(channel_llrs)
    hard = [0] * len(channel_llrs)

    for iteration in range(MAX_ITERATIONS):
        for row_index in range(len(rows)):
            start = row_offsets[row_index]
            end = row_offsets[row_index + 1]
            minimum = abs(variable_to_check[start])
            second = abs(variable_to_check[start + 1])
            minimum_edge = start
            if second < minimum:
                minimum, second = second, minimum
                minimum_edge = start + 1
            all_sign = 1
            for edge in range(start, end):
                if variable_to_check[edge] < 0.0:
                    all_sign = -all_sign
            for edge in range(start + 2, end):
                magnitude = abs(variable_to_check[edge])
                if magnitude < minimum:
                    second = minimum
                    minimum = magnitude
                    minimum_edge = edge
                elif magnitude < second:
                    second = magnitude
            for edge in range(start, end):
                magnitude = second if edge == minimum_edge else minimum
                magnitude = max(0.0, NORMALIZATION * magnitude)
                sign = (
                    -all_sign
                    if variable_to_check[edge] < 0.0
                    else all_sign
                )
                check_to_variable[edge] = magnitude if sign > 0 else -magnitude

        posterior = channel_llrs.copy()
        for edge, column in enumerate(edge_columns):
            posterior[column] += check_to_variable[edge]
        for variable in range(len(channel_llrs)):
            posterior[variable] = max(
                -LLR_CLIP, min(LLR_CLIP, posterior[variable])
            )
            hard[variable] = 0 if posterior[variable] >= 0.0 else 1
        if syndrome_ok(hard, rows):
            return hard, iteration + 1, True, posterior
        for edge, column in enumerate(edge_columns):
            variable_to_check[edge] = max(
                -LLR_CLIP,
                min(
                    LLR_CLIP,
                    posterior[column] - check_to_variable[edge],
                ),
            )
    return hard, MAX_ITERATIONS, False, posterior


def crc16_remainder(bits: list[int]) -> int:
    state = 0
    for bit in bits:
        feedback = ((state >> 15) & 1) ^ bit
        state = (state << 1) & 0xFFFF
        if feedback:
            state ^= 0x1021
    return state


def simulate(
    py3gpp_root: Path,
    packet_count: int,
    noise_variance: float,
    seed: int,
    payload_bits: int,
    output_bits: int,
    modulation_order: int,
) -> FixtureResult:
    from py3gpp import (
        nrCodeBlockSegmentLDPC,
        nrCRCEncode,
        nrDLSCHInfo,
        nrPDSCH,
        nrPRBS,
        nrRateMatchLDPC,
        nrRateRecoverLDPC,
        nrSymbolModulate,
    )
    from py3gpp.nrLDPCEncode import _encode_thangaraj, _load_basegraph

    if modulation_order != 2:
        raise ValueError("the V1 external fixture is deliberately QPSK-only")
    info = nrDLSCHInfo(payload_bits, 0.5)
    if not (
        info["BGN"] == 2
        and info["C"] == 1
        and info["Zc"] == 20
        and info["K"] == 200
        and info["N"] == 1000
    ):
        raise RuntimeError("unexpected py3gpp LDPC profile for the V1 fixture")
    rows = base_graph_rows(py3gpp_root, 2, 20)
    payload_state = seed ^ PAYLOAD_SALT
    total_errors = 0
    failed_packets = 0
    packet_errors: list[int] = []
    packet_failures: list[int] = []
    minimum_margin = math.inf
    noise_hasher = hashlib.sha256()
    discrete_hasher = hashlib.sha256()
    receiver_hasher = hashlib.sha256()
    noise_q12be_fnv1a64 = FNV1A64_OFFSET
    observable_discrete_fnv1a64 = FNV1A64_OFFSET

    for packet in range(packet_count):
        payload: list[int] = []
        for _ in range(payload_bits):
            payload_state, bit = next_payload_bit(payload_state)
            payload.append(bit)
        n_id = 42 + packet % 17
        rnti = 0x1200 + packet
        redundancy_version = packet % 4

        transport = nrCRCEncode(
            __import__("numpy").array(payload, dtype=int), "16"
        )[:, 0]
        segments = nrCodeBlockSegmentLDPC(transport, 2)
        # Resolve iLS directly from Zc=20 (set index 2), then use py3gpp's
        # scalar QC recurrence.  Its public wrapper infers iLS from the padded
        # 10*Zc array length, which is ambiguous for this short-Kb profile.
        information = segments[:, 0].copy()
        information[information == -1] = 0
        encoded_full = _encode_thangaraj(
            _load_basegraph(2, 2), 20, information
        )
        encoded = encoded_full[40:].astype("int8")[:, None]
        encoded[76:160, 0] = -1
        rate_matched = nrRateMatchLDPC(
            encoded, output_bits, redundancy_version, "QPSK", 1
        ).astype(int)
        symbols = nrPDSCH(
            [rate_matched], ["QPSK"], 1, n_id, rnti
        )[0].astype(complex)
        scramble = nrPRBS((rnti << 15) + n_id, output_bits).astype(int)
        scrambled = rate_matched ^ scramble

        dmrs_c_init = (
            (1 << 17)
            * (14 * packet + 2 + 1)
            * (2 * n_id + 1)
            + 2 * n_id
        ) % (1 << 31)
        dmrs_bits = nrPRBS(dmrs_c_init, output_bits).astype(int)
        dmrs = nrSymbolModulate(dmrs_bits, "QPSK").astype(complex)
        allocation_size = 2 * (output_bits // modulation_order)
        transmit_grid = [0.0j] * allocation_size
        for local in range(allocation_size):
            transmit_grid[local] = (
                dmrs[local // 2]
                if local % 2 == 0
                else symbols[local // 2]
            )
        channel_samples = [sample * GAIN for sample in transmit_grid]
        noisy_grid, packed_noise = add_awgn(
            channel_samples,
            noise_variance,
            (seed + packet * PACKET_SEED_STRIDE) & MASK64,
        )
        received, channel, equalized, llrs = comb2_receive(
            noisy_grid, list(dmrs), noise_variance
        )
        descrambled = [
            value if scramble[index] == 0 else -value
            for index, value in enumerate(llrs)
        ]
        recovered_array = nrRateRecoverLDPC(
            __import__("numpy").array(descrambled),
            payload_bits,
            0.5,
            redundancy_version,
            "QPSK",
            1,
        )[:, 0]
        recovered = [
            FILLER_LLR if math.isinf(float(value)) else float(value)
            for value in recovered_array
        ]
        full_llrs = [0.0] * 1040
        full_llrs[40:] = recovered
        decoded, iterations, converged, posterior = flooding_normalized_min_sum(
            full_llrs, rows
        )
        information = decoded[:200]
        decoded_transport = information[: payload_bits + 16]
        recovered_payload = decoded_transport[:payload_bits]
        crc_ok = crc16_remainder(decoded_transport) == 0
        errors = sum(
            expected != actual
            for expected, actual in zip(
                payload, recovered_payload, strict=True
            )
        )
        packet_failed = (not crc_ok) or (not converged) or errors != 0
        total_errors += errors
        failed_packets += packet_failed
        packet_errors.append(errors)
        packet_failures.append(int(packet_failed))
        minimum_margin = min(
            minimum_margin,
            min(abs(value) for value in posterior[:payload_bits]),
        )

        noise_hasher.update(packed_noise)
        noise_q12be_fnv1a64 = fnv1a64_update(
            noise_q12be_fnv1a64, quantized_noise_bytes(packed_noise)
        )
        for checkpoint in (
            payload,
            list(map(int, transport)),
            list(map(int, segments[:, 0])),
            list(map(int, encoded[:, 0])),
            list(map(int, rate_matched)),
            list(map(int, scrambled)),
            list(map(int, dmrs_bits)),
            recovered_payload,
            [iterations, int(converged), int(crc_ok), errors],
        ):
            for value in checkpoint:
                discrete_hasher.update(struct.pack(">q", int(value)))
        for checkpoint in (
            list(symbols),
            list(dmrs),
            channel_samples,
            noisy_grid,
            received,
            channel,
            equalized,
        ):
            pack_complex64(receiver_hasher, checkpoint)
        for checkpoint in (llrs, descrambled, recovered, posterior):
            pack_float64(receiver_hasher, checkpoint)

        # Exact public-wrapper-observable transcript.  This deliberately uses
        # only stages retained by the Mojo wrapper so the test can compare the
        # independent implementation without a production round trip.
        for checkpoint in (
            payload,
            list(map(int, transport)),
            list(map(int, rate_matched)),
            list(map(int, scrambled)),
            recovered_payload,
        ):
            observable_discrete_fnv1a64 = fnv1a64_update(
                observable_discrete_fnv1a64, bytes(checkpoint)
            )
        observable_discrete_fnv1a64 = fnv1a64_update(
            observable_discrete_fnv1a64,
            struct.pack(">q", errors) + bytes([int(packet_failed)]),
        )

    return FixtureResult(
        packet_count=packet_count,
        noise_variance=noise_variance,
        seed=seed,
        payload_bits=payload_bits,
        output_bits=output_bits,
        modulation_order=modulation_order,
        bit_count=packet_count * payload_bits,
        bit_errors=total_errors,
        packet_errors=failed_packets,
        per_packet_bit_errors=tuple(packet_errors),
        per_packet_failures=tuple(packet_failures),
        minimum_payload_posterior_margin=minimum_margin,
        noise_f64be_sha256=noise_hasher.hexdigest(),
        discrete_checkpoints_sha256=discrete_hasher.hexdigest(),
        receiver_f64be_sha256=receiver_hasher.hexdigest(),
        noise_q12be_fnv1a64=noise_q12be_fnv1a64,
        observable_discrete_fnv1a64=observable_discrete_fnv1a64,
    )


def canonical_rows(results: list[FixtureResult]) -> str:
    header = (
        "packets\tnoise_variance_hex\tseed_hex\tpayload_bits\toutput_bits\t"
        "modulation_order\tbit_count\tbit_errors\tpacket_errors\t"
        "per_packet_bit_errors\tper_packet_failures\t"
        "minimum_payload_posterior_margin\tnoise_f64be_sha256\t"
        "discrete_checkpoints_sha256\treceiver_f64be_sha256\t"
        "noise_q12be_fnv1a64\tobservable_discrete_fnv1a64\n"
    )
    rows = []
    for result in results:
        rows.append(
            "\t".join(
                (
                    str(result.packet_count),
                    result.noise_variance.hex(),
                    f"0x{result.seed:016x}",
                    str(result.payload_bits),
                    str(result.output_bits),
                    str(result.modulation_order),
                    str(result.bit_count),
                    str(result.bit_errors),
                    str(result.packet_errors),
                    ",".join(map(str, result.per_packet_bit_errors)),
                    ",".join(map(str, result.per_packet_failures)),
                    result.minimum_payload_posterior_margin.hex(),
                    result.noise_f64be_sha256,
                    result.discrete_checkpoints_sha256,
                    result.receiver_f64be_sha256,
                    f"0x{result.noise_q12be_fnv1a64:016x}",
                    f"0x{result.observable_discrete_fnv1a64:016x}",
                )
            )
        )
    return header + "\n".join(rows) + "\n"


def checked_py3gpp_root(path: Path) -> Path:
    root = path.resolve()
    commit = subprocess.run(
        ["git", "-C", str(root), "rev-parse", "HEAD"],
        check=True,
        capture_output=True,
        text=True,
    ).stdout.strip()
    if commit != PY3GPP_COMMIT:
        raise SystemExit(
            f"py3gpp commit {commit} does not match pinned {PY3GPP_COMMIT}"
        )
    dirty = subprocess.run(
        [
            "git",
            "-C",
            str(root),
            "status",
            "--porcelain",
            "--untracked-files=no",
        ],
        check=True,
        capture_output=True,
        text=True,
    ).stdout
    if dirty:
        raise SystemExit("py3gpp checkout has modified tracked files")
    if not (root / "py3gpp" / "nrLDPCEncode.py").is_file():
        raise SystemExit("--py3gpp must name the py3gpp repository root")
    sys.path.insert(0, str(root))
    return root


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--py3gpp", required=True, type=Path)
    arguments = parser.parse_args()
    py3gpp_root = checked_py3gpp_root(arguments.py3gpp)
    import numpy
    import scipy

    configurations = [
        (2, 1.0, 0x000000005A173821, 100, 480, 2),
    ]
    results = [
        simulate(py3gpp_root, *configuration)
        for configuration in configurations
    ]
    rows = canonical_rows(results)
    generator_sha256 = hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
    rows_sha256 = hashlib.sha256(rows.encode("ascii")).hexdigest()
    print("# MWDSP-NR-PDSCH-AWGN-EXTERNAL-ORACLE-V1")
    print(f"# generator_sha256={generator_sha256}")
    print(
        "# generator_runtime="
        f"CPython_{sys.version_info.major}.{sys.version_info.minor}.{sys.version_info.micro}"
    )
    print(f"# numpy_version={numpy.__version__};scipy_version={scipy.__version__}")
    print(f"# py3gpp_repository={PY3GPP_REPOSITORY}")
    print(f"# py3gpp_commit={PY3GPP_COMMIT}")
    print(
        "# normative_sources=3GPP_TS_38.211_V18.9.0_sha256_"
        "6b44878ccf4b651441608ec810b6639a6e4939160ca64b4980738a58692ee140;"
        "3GPP_TS_38.212_V18.8.0_sha256_"
        "1762858b2f09a5a48f5a4730ccbc72c43ff90bebb96c14833841e36a235c8e4c"
    )
    print(
        "# profile=single_codeword_single_layer_QPSK_BG2_Zc20_C1_RV0_then_RV1_"
        "comb2_flat_gain_0.9_plus_0.2j"
    )
    print(
        "# receiver=comb2_LS_linear_interpolation_ZF_piecewise_QPSK_LLR_"
        "flooding_normalized_min_sum_alpha_0.8_clip_50_iterations_30"
    )
    print("# bit_order=one_bit_per_int_MSB_first_CRC;packing=big_endian")
    print("# result_tolerance=exact;posterior_margin_is_diagnostic_only")
    print(f"# canonical_rows_sha256={rows_sha256}")
    print(rows, end="")


if __name__ == "__main__":
    main()
