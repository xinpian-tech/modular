#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(cd "${script_dir}/.." && pwd)"
fixture_dir="${project_dir}/tests/fixtures"

# This is the reviewed trust receipt for the complete frozen oracle corpus.
# Updating a generator or fixture is a four-party review operation: regenerate
# the fixture, review its provenance and canonical rows, then update the
# corresponding digest here.  A digest printed inside a fixture is not its own
# independent trust receipt.
nr_generator_sha256="0be701507a6f879528b0bcb822fc0369e6c934ac6b9be3940d5053ffa5508f17"
wifi_generator_sha256="90edb514f011b9b722b25c283d1cec184c224dca9145899272f3ed420a977d94"
nr_fixture_sha256="d733ae4855913293213f5d6427f51ee8f956c19d05e1d8902873e41a9c08738c"
wifi_fixture_sha256="626d843b0d016d1338894c640e6568206527651960b071c86ec9b0ef6ec39705"
nr_canonical_rows_sha256="91f8e74415eb5ee187036fdb6a46a6855d56c37c6a998b19089360ec1b3ff143"
wifi_canonical_rows_sha256="05c42137c99b7e606f624140f9dde8323c0aad3b122aa2832d06277579a5de05"
py3gpp_commit="17b432b30c965ffd350257ee4b1fc4de642c8e37"

oracle_python="${MWDSP_EXTERNAL_ORACLE_PYTHON:-python3}"
if ! command -v -- "${oracle_python}" >/dev/null 2>&1; then
  printf 'external-oracle gate requires Python: %s\n' \
    "${oracle_python}" >&2
  exit 1
fi

gate_tmp="$(mktemp -d "${TMPDIR:-/tmp}/mwdsp-external-oracles.XXXXXX")"
cleanup() {
  rm -r -- "${gate_tmp}"
}
trap cleanup EXIT

validate_frozen_corpus() {
  local run_mutation_tests="$1"
  "${oracle_python}" -I - \
    "${fixture_dir}" \
    "${nr_generator_sha256}" \
    "${wifi_generator_sha256}" \
    "${nr_fixture_sha256}" \
    "${wifi_fixture_sha256}" \
    "${nr_canonical_rows_sha256}" \
    "${wifi_canonical_rows_sha256}" \
    "${run_mutation_tests}" <<'PY'
from __future__ import annotations

import hashlib
import math
from pathlib import Path
import re
import shutil
import stat
import sys
import tempfile


class GateError(Exception):
    pass


fixture_dir = Path(sys.argv[1])
expected_sha256 = {
    "generate_nr_pdsch_awgn_oracle.py": sys.argv[2],
    "generate_wifi_legacy_bpsk_awgn_oracle.py": sys.argv[3],
    "nr_pdsch_awgn_external_oracle_v1.tsv": sys.argv[4],
    "wifi_legacy_bpsk_awgn_oracle_v1.tsv": sys.argv[5],
}
nr_canonical_rows_sha256 = sys.argv[6]
wifi_canonical_rows_sha256 = sys.argv[7]


def reject(message: str) -> None:
    raise GateError(message)


def read_canonical_ascii(path: Path, *, fixture: bool) -> bytes:
    try:
        mode = path.lstat().st_mode
    except OSError as error:
        reject(f"cannot stat {path}: {error}")
    if stat.S_ISLNK(mode) or not stat.S_ISREG(mode):
        reject(f"oracle artifact must be a regular non-symlink file: {path}")
    try:
        data = path.read_bytes()
    except OSError as error:
        reject(f"cannot read {path}: {error}")
    if not data:
        reject(f"oracle artifact is empty: {path}")
    invalid = [
        value
        for value in data
        if value not in (0x09, 0x0A) and not 0x20 <= value <= 0x7E
    ]
    if invalid:
        reject(f"oracle artifact is not canonical ASCII/LF text: {path}")
    if b"\r" in data:
        reject(f"oracle artifact contains CR instead of LF: {path}")
    if not data.endswith(b"\n") or data.endswith(b"\n\n"):
        reject(f"oracle artifact needs exactly one trailing LF: {path}")
    lines = data[:-1].split(b"\n")
    if any(line.endswith((b" ", b"\t")) for line in lines):
        reject(f"oracle artifact contains trailing horizontal space: {path}")
    if fixture and any(not line for line in lines):
        reject(f"fixture contains a blank line: {path}")
    return data


def validate_receipts(root: Path) -> None:
    for name, expected in expected_sha256.items():
        path = root / name
        data = read_canonical_ascii(path, fixture=name.endswith(".tsv"))
        actual = hashlib.sha256(data).hexdigest()
        if actual != expected:
            reject(
                f"SHA-256 trust receipt mismatch for {path}: "
                f"expected {expected}, got {actual}"
            )


def canonical_uint(value: str, field: str) -> int:
    if re.fullmatch(r"0|[1-9][0-9]*", value) is None:
        reject(f"{field} is not canonical unsigned decimal: {value!r}")
    return int(value)


def canonical_float_hex(value: str, field: str) -> float:
    try:
        parsed = float.fromhex(value)
    except ValueError:
        reject(f"{field} is not binary64 hexadecimal: {value!r}")
    if not math.isfinite(parsed) or parsed.hex() != value:
        reject(f"{field} is not canonical finite binary64: {value!r}")
    return parsed


def require_sha256(value: str, field: str) -> None:
    if re.fullmatch(r"[0-9a-f]{64}", value) is None:
        reject(f"{field} is not canonical lower-case SHA-256: {value!r}")


def require_hex64(value: str, field: str) -> None:
    if re.fullmatch(r"0x[0-9a-f]{16}", value) is None:
        reject(f"{field} is not canonical lower-case UInt64: {value!r}")


def canonical_uint_list(value: str, field: str) -> list[int]:
    if not value:
        reject(f"{field} must not be empty")
    return [
        canonical_uint(item, f"{field}[{index}]")
        for index, item in enumerate(value.split(","))
    ]


def fixture_lines(
    path: Path,
    metadata: list[str],
    header: list[str],
    row_count: int,
    expected_rows_hash: str,
) -> list[list[str]]:
    data = read_canonical_ascii(path, fixture=True)
    lines = data.decode("ascii").splitlines()
    metadata_count = len(metadata)
    expected_line_count = metadata_count + 2 + row_count
    if len(lines) != expected_line_count:
        reject(
            f"{path} has {len(lines)} lines; expected {expected_line_count}"
        )
    if lines[:metadata_count] != metadata:
        reject(f"{path} metadata is not the exact frozen ordered schema")
    canonical_hash_line = lines[metadata_count]
    match = re.fullmatch(
        r"# canonical_rows_sha256=([0-9a-f]{64})", canonical_hash_line
    )
    if match is None:
        reject(f"{path} has a malformed canonical_rows_sha256 metadata row")
    if match.group(1) != expected_rows_hash:
        reject(
            f"{path} canonical_rows_sha256 metadata is not the frozen value"
        )
    header_index = metadata_count + 1
    if lines[header_index].split("\t") != header:
        reject(f"{path} has a non-canonical TSV header")
    canonical_rows = (
        "\n".join(lines[header_index:]) + "\n"
    ).encode("ascii")
    actual_rows_hash = hashlib.sha256(canonical_rows).hexdigest()
    if actual_rows_hash != match.group(1):
        reject(
            f"{path} canonical row hash mismatch: metadata "
            f"{match.group(1)}, computed {actual_rows_hash}"
        )
    rows = [line.split("\t") for line in lines[header_index + 1 :]]
    if any(len(row) != len(header) for row in rows):
        reject(f"{path} contains a row with the wrong column width")
    if len({tuple(row) for row in rows}) != row_count:
        reject(f"{path} contains duplicate rows")
    return rows


def validate_wifi(root: Path) -> None:
    name = "generate_wifi_legacy_bpsk_awgn_oracle.py"
    metadata = [
        "# MWDSP-WIFI-LEGACY-BPSK-AWGN-ORACLE-V1",
        f"# generator_sha256={expected_sha256[name]}",
        "# generator_runtime=CPython_3.13.7",
        "# dependencies=python_standard_library_only",
        (
            "# float_format=IEEE-754_binary64;"
            "noise_packing=big-endian_real_then_imag"
        ),
        (
            "# result_tolerance=exact;"
            "minimum_bpsk_margin_is_diagnostic_only"
        ),
    ]
    header = [
        "packets",
        "noise_variance_hex",
        "seed_hex",
        "bit_count",
        "bit_errors",
        "packet_errors",
        "minimum_bpsk_margin",
        "noise_f64be_sha256",
        "checkpoints_sha256",
        "noise_q12be_fnv1a64",
        "checkpoints_fnv1a64",
    ]
    rows = fixture_lines(
        root / "wifi_legacy_bpsk_awgn_oracle_v1.tsv",
        metadata,
        header,
        5,
        wifi_canonical_rows_sha256,
    )
    configurations = [
        (1, "0x0.0p+0", "0x0000000000000000"),
        (3, "0x1.47ae147ae147bp-7", "0x0000000000080211"),
        (7, "0x1.999999999999ap-5", "0x0000000005eed123"),
        (11, "0x1.999999999999ap-3", "0x00000000badc0de5"),
        (5, "0x1.0000000000000p+0", "0xfedcba9876543210"),
    ]
    for row_index, (row, expected) in enumerate(
        zip(rows, configurations, strict=True)
    ):
        packets = canonical_uint(row[0], f"wifi row {row_index} packets")
        noise = canonical_float_hex(
            row[1], f"wifi row {row_index} noise_variance_hex"
        )
        require_hex64(row[2], f"wifi row {row_index} seed_hex")
        if (packets, row[1], row[2]) != expected or noise < 0.0:
            reject(f"wifi row {row_index} is not the frozen configuration")
        bit_count = canonical_uint(row[3], f"wifi row {row_index} bit_count")
        bit_errors = canonical_uint(
            row[4], f"wifi row {row_index} bit_errors"
        )
        packet_errors = canonical_uint(
            row[5], f"wifi row {row_index} packet_errors"
        )
        margin = canonical_float_hex(
            row[6], f"wifi row {row_index} minimum_bpsk_margin"
        )
        if bit_count != 18 * packets:
            reject(f"wifi row {row_index} bit_count is inconsistent")
        if bit_errors > bit_count or packet_errors > packets or margin <= 0.0:
            reject(f"wifi row {row_index} has impossible result counters")
        require_sha256(row[7], f"wifi row {row_index} noise_f64be_sha256")
        require_sha256(row[8], f"wifi row {row_index} checkpoints_sha256")
        require_hex64(row[9], f"wifi row {row_index} noise_q12be_fnv1a64")
        require_hex64(row[10], f"wifi row {row_index} checkpoints_fnv1a64")


def validate_nr(root: Path) -> None:
    name = "generate_nr_pdsch_awgn_oracle.py"
    metadata = [
        "# MWDSP-NR-PDSCH-AWGN-EXTERNAL-ORACLE-V1",
        f"# generator_sha256={expected_sha256[name]}",
        "# generator_runtime=CPython_3.13.7",
        "# numpy_version=2.3.2;scipy_version=1.16.1",
        "# py3gpp_repository=https://github.com/catkira/py3gpp",
        (
            "# py3gpp_commit="
            "17b432b30c965ffd350257ee4b1fc4de642c8e37"
        ),
        (
            "# normative_sources="
            "3GPP_TS_38.211_V18.9.0_sha256_"
            "6b44878ccf4b651441608ec810b6639a6e4939160ca64b4980738a58692ee140;"
            "3GPP_TS_38.212_V18.8.0_sha256_"
            "1762858b2f09a5a48f5a4730ccbc72c43ff90bebb96c14833841e36a235c8e4c"
        ),
        (
            "# profile=single_codeword_single_layer_QPSK_BG2_Zc20_C1_"
            "RV0_then_RV1_comb2_flat_gain_0.9_plus_0.2j"
        ),
        (
            "# receiver=comb2_LS_linear_interpolation_ZF_piecewise_QPSK_"
            "LLR_flooding_normalized_min_sum_alpha_0.8_clip_50_iterations_30"
        ),
        "# bit_order=one_bit_per_int_MSB_first_CRC;packing=big_endian",
        (
            "# result_tolerance=exact;"
            "posterior_margin_is_diagnostic_only"
        ),
    ]
    header = [
        "packets",
        "noise_variance_hex",
        "seed_hex",
        "payload_bits",
        "output_bits",
        "modulation_order",
        "bit_count",
        "bit_errors",
        "packet_errors",
        "per_packet_bit_errors",
        "per_packet_failures",
        "minimum_payload_posterior_margin",
        "noise_f64be_sha256",
        "discrete_checkpoints_sha256",
        "receiver_f64be_sha256",
        "noise_q12be_fnv1a64",
        "observable_discrete_fnv1a64",
    ]
    rows = fixture_lines(
        root / "nr_pdsch_awgn_external_oracle_v1.tsv",
        metadata,
        header,
        1,
        nr_canonical_rows_sha256,
    )
    row = rows[0]
    packets = canonical_uint(row[0], "NR packets")
    noise = canonical_float_hex(row[1], "NR noise_variance_hex")
    require_hex64(row[2], "NR seed_hex")
    payload_bits = canonical_uint(row[3], "NR payload_bits")
    output_bits = canonical_uint(row[4], "NR output_bits")
    modulation_order = canonical_uint(row[5], "NR modulation_order")
    if (
        packets,
        row[1],
        row[2],
        payload_bits,
        output_bits,
        modulation_order,
    ) != (2, "0x1.0000000000000p+0", "0x000000005a173821", 100, 480, 2):
        reject("NR row is not the frozen QPSK BG2 configuration")
    if noise <= 0.0:
        reject("NR noise variance must be positive")
    bit_count = canonical_uint(row[6], "NR bit_count")
    bit_errors = canonical_uint(row[7], "NR bit_errors")
    packet_errors = canonical_uint(row[8], "NR packet_errors")
    per_packet_errors = canonical_uint_list(
        row[9], "NR per_packet_bit_errors"
    )
    per_packet_failures = canonical_uint_list(
        row[10], "NR per_packet_failures"
    )
    margin = canonical_float_hex(
        row[11], "NR minimum_payload_posterior_margin"
    )
    if bit_count != packets * payload_bits or bit_errors != sum(per_packet_errors):
        reject("NR bit counters are inconsistent")
    if len(per_packet_errors) != packets or any(
        value > payload_bits for value in per_packet_errors
    ):
        reject("NR per-packet bit-error counters are inconsistent")
    if len(per_packet_failures) != packets or any(
        value not in (0, 1) for value in per_packet_failures
    ):
        reject("NR per-packet failure counters are inconsistent")
    if packet_errors != sum(per_packet_failures) or margin <= 0.0:
        reject("NR packet counters or posterior margin are inconsistent")
    require_sha256(row[12], "NR noise_f64be_sha256")
    require_sha256(row[13], "NR discrete_checkpoints_sha256")
    require_sha256(row[14], "NR receiver_f64be_sha256")
    require_hex64(row[15], "NR noise_q12be_fnv1a64")
    require_hex64(row[16], "NR observable_discrete_fnv1a64")


def validate_all(root: Path) -> None:
    validate_receipts(root)
    validate_wifi(root)
    validate_nr(root)


def mutation_tests(root: Path) -> None:
    names = list(expected_sha256)
    with tempfile.TemporaryDirectory(prefix="mwdsp-oracle-mutation-") as tmp:
        temporary_root = Path(tmp)
        for mutated_name in names:
            case_root = temporary_root / mutated_name
            case_root.mkdir()
            for name in names:
                shutil.copyfile(root / name, case_root / name)
            path = case_root / mutated_name
            data = bytearray(path.read_bytes())
            mutation_index = len(data) // 2
            data[mutation_index] ^= 0x01
            path.write_bytes(data)
            try:
                validate_all(case_root)
            except GateError as error:
                if "SHA-256 trust receipt mismatch" not in str(error):
                    reject(
                        f"single-byte mutation of {mutated_name} failed for "
                        f"an unexpected reason: {error}"
                    )
            else:
                reject(f"single-byte mutation was accepted: {mutated_name}")
            print(f"reject single-byte mutation {mutated_name}")


try:
    validate_all(fixture_dir)
    if sys.argv[8] == "1":
        mutation_tests(fixture_dir)
except GateError as error:
    print(f"external-oracle corpus validation failed: {error}", file=sys.stderr)
    raise SystemExit(1)
PY
}

printf 'verify external-oracle trust receipts, schema, and mutations\n'
validate_frozen_corpus 1

overall_status=0
wifi_generated="${gate_tmp}/wifi.tsv"
printf 'regenerate Wi-Fi external oracle and compare exact bytes\n'
if env -u PYTHONHOME -u PYTHONPATH \
  LC_ALL=C TZ=UTC PYTHONHASHSEED=0 PYTHONNOUSERSITE=1 \
  "${oracle_python}" -I \
  "${fixture_dir}/generate_wifi_legacy_bpsk_awgn_oracle.py" \
  > "${wifi_generated}"; then
  if ! cmp -- \
    "${wifi_generated}" \
    "${fixture_dir}/wifi_legacy_bpsk_awgn_oracle_v1.tsv"; then
    printf 'Wi-Fi external oracle regeneration differs byte-for-byte\n' >&2
    overall_status=1
  fi
else
  printf 'Wi-Fi external oracle generator failed\n' >&2
  overall_status=1
fi

verify_py3gpp_checkout() {
  local checkout="$1"
  local resolved
  local top_level
  local head
  if [[ ! -d "${checkout}" ]]; then
    printf 'MWDSP_PY3GPP_CHECKOUT is not a directory: %s\n' \
      "${checkout}" >&2
    return 1
  fi
  if ! resolved="$(cd "${checkout}" && pwd -P)"; then
    printf 'cannot resolve py3gpp checkout: %s\n' "${checkout}" >&2
    return 1
  fi
  if ! top_level="$(git -C "${resolved}" rev-parse --show-toplevel 2>/dev/null)"; then
    printf 'py3gpp checkout is not a Git worktree: %s\n' "${resolved}" >&2
    return 1
  fi
  if [[ "$(cd "${top_level}" && pwd -P)" != "${resolved}" ]]; then
    printf 'MWDSP_PY3GPP_CHECKOUT must name the repository root: %s\n' \
      "${resolved}" >&2
    return 1
  fi
  if ! head="$(git -C "${resolved}" rev-parse HEAD 2>/dev/null)"; then
    printf 'cannot resolve py3gpp HEAD: %s\n' "${resolved}" >&2
    return 1
  fi
  if [[ "${head}" != "${py3gpp_commit}" ]]; then
    printf 'py3gpp HEAD %s does not match pinned %s\n' \
      "${head}" "${py3gpp_commit}" >&2
    return 1
  fi
  if [[ -n "$(git -C "${resolved}" status \
    --porcelain --untracked-files=all)" ]]; then
    printf 'py3gpp checkout is not completely clean: %s\n' \
      "${resolved}" >&2
    return 1
  fi
  if [[ ! -f "${resolved}/py3gpp/nrLDPCEncode.py" ]]; then
    printf 'py3gpp checkout is missing py3gpp/nrLDPCEncode.py: %s\n' \
      "${resolved}" >&2
    return 1
  fi
  # Never import from the caller's worktree: ignored bytecode or another
  # ignored executable could otherwise affect Python imports without
  # appearing in ordinary Git status.  A local no-hardlink clone materializes
  # exactly the pinned commit in the gate-owned temporary directory.
  local isolated="${gate_tmp}/py3gpp-pinned"
  if ! git -c protocol.file.allow=always clone \
    --no-hardlinks --no-checkout --quiet -- "${resolved}" "${isolated}"; then
    printf 'cannot create isolated py3gpp clone from: %s\n' \
      "${resolved}" >&2
    return 1
  fi
  if ! git -C "${isolated}" checkout --detach --quiet \
    "${py3gpp_commit}"; then
    printf 'cannot check out pinned py3gpp commit in isolation\n' >&2
    return 1
  fi
  if [[ -n "$(git -C "${isolated}" status \
    --porcelain --untracked-files=all)" ]]; then
    printf 'isolated py3gpp checkout is unexpectedly dirty\n' >&2
    return 1
  fi
  printf '%s\n' "${isolated}"
}

py3gpp_checkout="${MWDSP_PY3GPP_CHECKOUT:-}"
if [[ -z "${py3gpp_checkout}" ]]; then
  printf '%s\n' \
    'BLOCKED: NR oracle regeneration requires MWDSP_PY3GPP_CHECKOUT at' \
    "pinned clean commit ${py3gpp_commit}; static receipt checks are not" \
    'accepted as a successful full external-oracle gate.' >&2
  overall_status=1
else
  verified_checkout=""
  if verified_checkout="$(verify_py3gpp_checkout "${py3gpp_checkout}")"; then
    nr_python="${MWDSP_PY3GPP_PYTHON:-${oracle_python}}"
    if ! command -v -- "${nr_python}" >/dev/null 2>&1; then
      printf 'NR oracle Python is unavailable: %s\n' "${nr_python}" >&2
      overall_status=1
    else
      nr_generated="${gate_tmp}/nr.tsv"
      printf 'regenerate pinned py3gpp NR external oracle and compare exact bytes\n'
      if env -u PYTHONHOME -u PYTHONPATH \
        LC_ALL=C TZ=UTC PYTHONHASHSEED=0 PYTHONNOUSERSITE=1 \
        PYTHONDONTWRITEBYTECODE=1 \
        "${nr_python}" -I \
        "${fixture_dir}/generate_nr_pdsch_awgn_oracle.py" \
        --py3gpp "${verified_checkout}" > "${nr_generated}"; then
        if ! cmp -- \
          "${nr_generated}" \
          "${fixture_dir}/nr_pdsch_awgn_external_oracle_v1.tsv"; then
          printf 'NR external oracle regeneration differs byte-for-byte\n' >&2
          overall_status=1
        fi
      else
        printf '%s\n' \
          'NR external oracle generator failed; its pinned NumPy/SciPy' \
          'runtime is a required part of regeneration.' >&2
        overall_status=1
      fi
    fi
  else
    overall_status=1
  fi
fi

# Detect a concurrent or accidental artifact change after generator execution.
if ! validate_frozen_corpus 0; then
  overall_status=1
fi

printf '%s\n' \
  "external-oracle receipt nr_generator=${nr_generator_sha256}" \
  "external-oracle receipt wifi_generator=${wifi_generator_sha256}" \
  "external-oracle receipt nr_fixture=${nr_fixture_sha256}" \
  "external-oracle receipt wifi_fixture=${wifi_fixture_sha256}" \
  "external-oracle canonical rows nr=${nr_canonical_rows_sha256}" \
  "external-oracle canonical rows wifi=${wifi_canonical_rows_sha256}"

if (( overall_status != 0 )); then
  exit "${overall_status}"
fi
printf 'external-oracle frozen artifact gate passed\n'
