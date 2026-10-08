#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(cd "${script_dir}/.." && pwd)"
fixture_dir="${project_dir}/tests/fixtures"
generator="${fixture_dir}/generate_wifi_ldpc_matrix_oracle.py"
fixture="${fixture_dir}/wifi_ldpc_matrix_oracle_v1.tsv"

yaldpc_commit="7ac1cd6261e485b3cd91b2a1da5728c17d2bb50f"
tavildar_commit="05ee7f4af36ed5dacf52861315af68b8a17e71e0"
generator_sha256="c31d17ea7b39f77b61bf2b9fe26df2ecc9a591ce691ad825e6bbb1417a1c9ef8"
fixture_sha256="241ba572739b219ff0ccc08f4d8fa2b517357417b03ec44166eb27fdf8c9d9af"
canonical_records_sha256="f763bd8e0e101e10dff3d4f353ba196d1352a0f83135d156e1503e25146b12ac"

oracle_python="${MWDSP_EXTERNAL_ORACLE_PYTHON:-python3}"
if ! command -v -- "${oracle_python}" >/dev/null 2>&1; then
  printf 'Wi-Fi LDPC oracle gate requires Python: %s\n' \
    "${oracle_python}" >&2
  exit 1
fi
if ! command -v -- c++ >/dev/null 2>&1; then
  printf 'Wi-Fi LDPC oracle gate requires a C++14 compiler named c++\n' >&2
  exit 1
fi

gate_tmp="$(mktemp -d "${TMPDIR:-/tmp}/mwdsp-wifi-ldpc-oracle.XXXXXX")"
cleanup() {
  rm -r -- "${gate_tmp}"
}
trap cleanup EXIT

validate_corpus() {
  local generator_path="$1"
  local fixture_path="$2"
  local expected_generator_sha256="$3"
  local expected_fixture_sha256="$4"
  "${oracle_python}" -I - \
    "${generator_path}" \
    "${fixture_path}" \
    "${expected_generator_sha256}" \
    "${expected_fixture_sha256}" \
    "${canonical_records_sha256}" <<'PY'
from __future__ import annotations

import hashlib
from pathlib import Path
import stat
import sys


class GateError(Exception):
    pass


def reject(message: str) -> None:
    raise GateError(message)


def canonical_file(path: Path) -> bytes:
    try:
        mode = path.lstat().st_mode
    except OSError as error:
        reject(f"cannot stat {path}: {error}")
    if stat.S_ISLNK(mode) or not stat.S_ISREG(mode):
        reject(f"oracle artifact must be a regular non-symlink file: {path}")
    data = path.read_bytes()
    if not data or not data.endswith(b"\n") or data.endswith(b"\n\n"):
        reject(f"oracle artifact must have exactly one trailing LF: {path}")
    if b"\r" in data or any(
        value not in (0x09, 0x0A) and not 0x20 <= value <= 0x7E
        for value in data
    ):
        reject(f"oracle artifact must be canonical ASCII/LF text: {path}")
    return data


generator = Path(sys.argv[1])
fixture = Path(sys.argv[2])
generator_data = canonical_file(generator)
fixture_data = canonical_file(fixture)
if hashlib.sha256(generator_data).hexdigest() != sys.argv[3]:
    reject("Wi-Fi LDPC generator SHA-256 receipt mismatch")
if hashlib.sha256(fixture_data).hexdigest() != sys.argv[4]:
    reject("Wi-Fi LDPC fixture SHA-256 receipt mismatch")

lines = fixture_data.decode("ascii").splitlines()
if lines[0] != "# MWDSP-WIFI-LDPC-MATRIX-ORACLE-V1":
    reject("Wi-Fi LDPC fixture schema marker changed")
header = (
    "record\tblock_length\trate_numerator\trate_denominator\t"
    "row_index\tvalues\tauxiliary"
)
try:
    header_index = lines.index(header)
except ValueError:
    reject("Wi-Fi LDPC fixture column header is missing")
records = lines[header_index + 1 :]
canonical = ("\n".join(records) + "\n").encode("ascii")
if hashlib.sha256(canonical).hexdigest() != sys.argv[5]:
    reject("Wi-Fi LDPC canonical-record receipt mismatch")

profiles = []
base_rows = 0
base_entries = 0
codewords = 0
for line in records:
    fields = line.split("\t")
    if len(fields) != 7:
        reject("Wi-Fi LDPC fixture record width changed")
    record, n_text, rn_text, rd_text, row_text, values, auxiliary = fields
    try:
        n, rn, rd, row = map(int, (n_text, rn_text, rd_text, row_text))
    except ValueError:
        reject("Wi-Fi LDPC fixture contains a non-decimal key")
    if record == "profile":
        if row != -1 or auxiliary != "-" or len(values.split(",")) != 6:
            reject("Wi-Fi LDPC fixture profile row is malformed")
        profiles.append((n, rn, rd))
    elif record == "base":
        shifts = values.split(",")
        if row < 0 or auxiliary != "-" or len(shifts) != 24:
            reject("Wi-Fi LDPC fixture base row is malformed")
        try:
            tuple(map(int, shifts))
        except ValueError:
            reject("Wi-Fi LDPC fixture contains a non-decimal shift")
        base_rows += 1
        base_entries += len(shifts)
    elif record == "codeword":
        if row != -1 or any(bit not in "01" for bit in values + auxiliary):
            reject("Wi-Fi LDPC fixture codeword row is malformed")
        if len(auxiliary) != n:
            reject("Wi-Fi LDPC fixture codeword length changed")
        codewords += 1
    else:
        reject("Wi-Fi LDPC fixture contains an unknown record kind")

expected_profiles = [
    (n, rn, rd)
    for n in (648, 1296, 1944)
    for rn, rd in ((1, 2), (2, 3), (3, 4), (5, 6))
]
if profiles != expected_profiles:
    reject("Wi-Fi LDPC fixture profile order or membership changed")
if (base_rows, base_entries, codewords) != (90, 2160, 12):
    reject("Wi-Fi LDPC fixture corpus counts changed")
PY
}

validate_corpus \
  "${generator}" \
  "${fixture}" \
  "${generator_sha256}" \
  "${fixture_sha256}"
printf 'Wi-Fi LDPC generator and fixture trust receipts passed\n'

mutated_generator="${gate_tmp}/mutated-generator.py"
mutated_fixture="${gate_tmp}/mutated-fixture.tsv"
cp -- "${generator}" "${mutated_generator}"
cp -- "${fixture}" "${mutated_fixture}"
printf '# mutation\n' >> "${mutated_generator}"
printf '# mutation\n' >> "${mutated_fixture}"
if validate_corpus \
  "${mutated_generator}" \
  "${fixture}" \
  "${generator_sha256}" \
  "${fixture_sha256}" >/dev/null 2>&1; then
  printf 'mutated Wi-Fi LDPC generator was not rejected\n' >&2
  exit 1
fi
if validate_corpus \
  "${generator}" \
  "${mutated_fixture}" \
  "${generator_sha256}" \
  "${fixture_sha256}" >/dev/null 2>&1; then
  printf 'mutated Wi-Fi LDPC fixture was not rejected\n' >&2
  exit 1
fi
printf 'Wi-Fi LDPC generator and fixture mutation rejection passed\n'

yaldpc_checkout="${MWDSP_YALDPC_CHECKOUT:-}"
tavildar_checkout="${MWDSP_TAVILDAR_LDPC_CHECKOUT:-}"
if [[ -z "${yaldpc_checkout}" || -z "${tavildar_checkout}" ]]; then
  printf '%s\n' \
    'BLOCKED: exact Wi-Fi LDPC regeneration requires both' \
    'MWDSP_YALDPC_CHECKOUT and MWDSP_TAVILDAR_LDPC_CHECKOUT.' >&2
  exit 1
fi
for checkout in "${yaldpc_checkout}" "${tavildar_checkout}"; do
  if [[ ! -d "${checkout}/.git" ]]; then
    printf 'Wi-Fi LDPC oracle checkout is not a git worktree: %s\n' \
      "${checkout}" >&2
    exit 1
  fi
  if [[ -n "$(git -C "${checkout}" status --porcelain --untracked-files=all)" ]]; then
    printf 'Wi-Fi LDPC oracle checkout is not clean: %s\n' \
      "${checkout}" >&2
    exit 1
  fi
done
if [[ "$(git -C "${yaldpc_checkout}" rev-parse HEAD)" != "${yaldpc_commit}" ]]; then
  printf 'YALDPC checkout is not at pinned commit %s\n' \
    "${yaldpc_commit}" >&2
  exit 1
fi
if [[ "$(git -C "${tavildar_checkout}" rev-parse HEAD)" != "${tavildar_commit}" ]]; then
  printf 'tavildar checkout is not at pinned commit %s\n' \
    "${tavildar_commit}" >&2
  exit 1
fi

isolated_yaldpc="${gate_tmp}/yaldpc"
isolated_tavildar="${gate_tmp}/tavildar"
git clone --quiet --local --no-hardlinks \
  "${yaldpc_checkout}" "${isolated_yaldpc}"
git -C "${isolated_yaldpc}" checkout --quiet --detach "${yaldpc_commit}"
git clone --quiet --local --no-hardlinks \
  "${tavildar_checkout}" "${isolated_tavildar}"
git -C "${isolated_tavildar}" checkout --quiet --detach "${tavildar_commit}"

regenerated_first="${gate_tmp}/regenerated-first.tsv"
regenerated_second="${gate_tmp}/regenerated-second.tsv"
PYTHONDONTWRITEBYTECODE=1 "${oracle_python}" -I "${generator}" \
  "${isolated_yaldpc}" "${isolated_tavildar}" > "${regenerated_first}"
PYTHONDONTWRITEBYTECODE=1 "${oracle_python}" -I "${generator}" \
  "${isolated_yaldpc}" "${isolated_tavildar}" > "${regenerated_second}"
if ! cmp -s -- "${regenerated_first}" "${regenerated_second}"; then
  printf 'Wi-Fi LDPC oracle regeneration is nondeterministic\n' >&2
  exit 1
fi
if ! cmp -s -- "${fixture}" "${regenerated_first}"; then
  printf 'Wi-Fi LDPC checked-in fixture differs from exact regeneration\n' >&2
  exit 1
fi
printf 'Wi-Fi LDPC exact dual-source byte regeneration passed\n'
