#!/usr/bin/env python3
"""Generate the independent all-profile WLAN QC-LDPC matrix oracle.

This generator never imports ``wireless_dsp`` and never reads a Mojo source.
It requires two clean, pinned, permissively licensed source checkouts:

* talenik/YALDPC commit 7ac1cd6261e485b3cd91b2a1da5728c17d2bb50f
  supplies all twelve IEEE 802.11-2020 Annex F base-shift matrices under the
  BSD-3-Clause license;
* tavildar/LDPC commit 05ee7f4af36ed5dacf52861315af68b8a17e71e0
  supplies a second copy of all matrices and its native C++ systematic
  encoder under the MIT license.

The two independently maintained matrix corpora must agree at all 2160 base
entries.  A temporary driver then calls the pinned tavildar C++ encoder for a
fixed xorshift64* information word in every profile.  The generator expands
the YALDPC matrices itself, checks every native codeword against the resulting
CSR graph, and emits the complete base rows plus all twelve exact information
and codeword bit strings.  The checked-in fixture is a differential oracle,
not a substitute for the repository's separate IEEE normative authority gate.
"""

from __future__ import annotations

import hashlib
from pathlib import Path
import re
import stat
import subprocess
import sys
import tempfile


YALDPC_REPOSITORY = "https://github.com/talenik/YALDPC"
YALDPC_COMMIT = "7ac1cd6261e485b3cd91b2a1da5728c17d2bb50f"
YALDPC_MATRIX_PATH = Path("lib/IEEE80211_2020_LDPC.m")
YALDPC_MATRIX_SHA256 = (
    "35b8dd95ad08f1aaa8a5dd7f659711a391562c0537adb8e5b99f6fd25c57d7b4"
)
YALDPC_LICENSE_SHA256 = (
    "832953db1090569f874669ff8ca9889dd9206b4575a4997075c84d78b1111334"
)

TAVILDAR_REPOSITORY = "https://github.com/tavildar/LDPC"
TAVILDAR_COMMIT = "05ee7f4af36ed5dacf52861315af68b8a17e71e0"
TAVILDAR_MATRIX_PATH = Path("LdpcC/WiFiLDPC.h")
TAVILDAR_MATRIX_SHA256 = (
    "b2a6e22dce37ab57c883503f7078feb16fcc8e5dc029efc7bc596c10de196934"
)
TAVILDAR_HEADER_PATH = Path("LdpcC/LdpcCode.h")
TAVILDAR_HEADER_SHA256 = (
    "e1075eab5a6c91f822a7184dde2ba38e0e78ad6a030b8cc89530386500028fbf"
)
TAVILDAR_SOURCE_PATH = Path("LdpcC/LdpcCode.cpp")
TAVILDAR_SOURCE_SHA256 = (
    "236decce7a06c179579b07bf58d189be927bc27cad7772a77768932bff5203f0"
)
TAVILDAR_LICENSE_SHA256 = (
    "d4fbfb1aeca7504abd6d64bce60d18e02d116a3a46addb13b14441bb4ad5cfe5"
)

PROFILE_ORDER = tuple(
    (block_length, numerator, denominator)
    for block_length in (648, 1296, 1944)
    for numerator, denominator in ((1, 2), (2, 3), (3, 4), (5, 6))
)
BLOCK_ROWS = {(1, 2): 12, (2, 3): 8, (3, 4): 6, (5, 6): 4}
RATE_TAG = {(1, 2): "12", (2, 3): "23", (3, 4): "34", (5, 6): "56"}


class OracleError(RuntimeError):
    pass


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def checked_file(root: Path, relative: Path, expected_sha256: str) -> bytes:
    path = root / relative
    try:
        mode = path.lstat().st_mode
    except OSError as error:
        raise OracleError(f"cannot stat oracle source {path}: {error}") from error
    if stat.S_ISLNK(mode) or not stat.S_ISREG(mode):
        raise OracleError(f"oracle source must be a regular non-symlink: {path}")
    data = path.read_bytes()
    actual = sha256(data)
    if actual != expected_sha256:
        raise OracleError(
            f"oracle source SHA-256 mismatch for {relative}: "
            f"expected {expected_sha256}, got {actual}"
        )
    return data


def checked_commit(root: Path, expected: str) -> None:
    try:
        actual = subprocess.run(
            ["git", "-C", str(root), "rev-parse", "HEAD"],
            check=True,
            capture_output=True,
            text=True,
        ).stdout.strip()
    except (OSError, subprocess.CalledProcessError) as error:
        raise OracleError(f"cannot inspect git checkout {root}: {error}") from error
    if actual != expected:
        raise OracleError(
            f"oracle checkout commit mismatch for {root}: expected {expected}, got {actual}"
        )
    status_output = subprocess.run(
        [
            "git",
            "-C",
            str(root),
            "status",
            "--porcelain",
            "--untracked-files=all",
        ],
        check=True,
        capture_output=True,
        text=True,
    ).stdout
    if status_output:
        raise OracleError(f"oracle checkout is not clean: {root}")


def parse_yaldpc(data: bytes) -> dict[tuple[int, int, int], list[list[int]]]:
    text = data.decode("utf-8")
    pattern = re.compile(
        r"H_R(12|23|34|56)_N(648|1296|1944)\s*=\s*"
        r"\[\s*\.\.\.(.*?)\]\s*;",
        re.DOTALL,
    )
    matrices: dict[tuple[int, int, int], list[list[int]]] = {}
    for match in pattern.finditer(text):
        rate_tag, block_length_text, body = match.groups()
        rate = next(rate for rate, tag in RATE_TAG.items() if tag == rate_tag)
        block_length = int(block_length_text)
        rows: list[list[int]] = []
        for source_row in body.split(";"):
            source_row = re.sub(r"%[^\n]*", "", source_row)
            values = [int(value) for value in re.findall(r"-?\d+", source_row)]
            if values:
                rows.append(values)
        matrices[(block_length, *rate)] = rows
    validate_matrices(matrices, "YALDPC")
    return matrices


def parse_tavildar(data: bytes) -> dict[tuple[int, int, int], list[list[int]]]:
    text = data.decode("ascii")
    pattern = re.compile(
        r"int\s+H_(648|1296|1944)_(1_2|2_3|3_4|5_6)"
        r"\[(\d+)\]\[24\]\s*=\s*\{(.*?)\};",
        re.DOTALL,
    )
    matrices: dict[tuple[int, int, int], list[list[int]]] = {}
    for match in pattern.finditer(text):
        block_length_text, rate_text, declared_rows_text, body = match.groups()
        numerator, denominator = (int(value) for value in rate_text.split("_"))
        rows = [
            [int(value) for value in re.findall(r"-?\d+", row.group(1))]
            for row in re.finditer(r"\{([^{}]+)\}", body)
        ]
        if len(rows) != int(declared_rows_text):
            raise OracleError("tavildar matrix row declaration does not match its body")
        matrices[(int(block_length_text), numerator, denominator)] = rows
    validate_matrices(matrices, "tavildar")
    return matrices


def validate_matrices(
    matrices: dict[tuple[int, int, int], list[list[int]]], source: str
) -> None:
    if tuple(matrices) != PROFILE_ORDER:
        raise OracleError(f"{source} matrix profile order or membership changed")
    for block_length, numerator, denominator in PROFILE_ORDER:
        rows = matrices[(block_length, numerator, denominator)]
        expected_rows = BLOCK_ROWS[(numerator, denominator)]
        lifting_size = block_length // 24
        if len(rows) != expected_rows or any(len(row) != 24 for row in rows):
            raise OracleError(f"{source} matrix dimensions are invalid")
        if any(
            shift < -1 or shift >= lifting_size
            for row in rows
            for shift in row
        ):
            raise OracleError(f"{source} matrix contains an invalid shift")


def expand_graph(matrix: list[list[int]], lifting_size: int) -> list[list[int]]:
    graph: list[list[int]] = []
    for base_row in matrix:
        for local_row in range(lifting_size):
            graph.append(
                [
                    block_column * lifting_size
                    + (local_row + shift) % lifting_size
                    for block_column, shift in enumerate(base_row)
                    if shift >= 0
                ]
            )
    return graph


DRIVER_SOURCE = r'''#include <algorithm>
#include <cstdint>
#include <iostream>
#include <stdexcept>
#include <vector>
#include "LdpcCode.h"

static std::uint64_t next_xorshift64star(std::uint64_t& state) {
    state ^= state >> 12;
    state ^= state << 25;
    state ^= state >> 27;
    return state * UINT64_C(2685821657736338717);
}

int main() {
    const unsigned lengths[] = {648, 1296, 1944};
    const unsigned rate_num[] = {1, 2, 3, 5};
    const unsigned rate_den[] = {2, 3, 4, 6};
    for (unsigned length : lengths) {
        for (unsigned rate_index = 0; rate_index < 4; ++rate_index) {
            LdpcCode code(length, 1);
            code.load_wifi_ldpc(length, rate_index);
            const unsigned information_length = code.get_info_length();
            std::uint64_t state = UINT64_C(0x6a09e667f3bcc909)
                ^ (std::uint64_t(length) << 17)
                ^ (std::uint64_t(rate_num[rate_index]) << 9)
                ^ std::uint64_t(rate_den[rate_index]);
            std::vector<std::uint8_t> information(information_length);
            for (auto& bit : information)
                bit = std::uint8_t(next_xorshift64star(state) >> 63);
            const auto codeword = code.encode(information);
            if (codeword.size() != length || !code.check_codeword(codeword))
                throw std::runtime_error("native tavildar encoder validation failed");
            std::cout << length << '\t' << rate_num[rate_index] << '\t'
                      << rate_den[rate_index] << '\t';
            for (auto bit : information) std::cout << unsigned(bit);
            std::cout << '\t';
            for (auto bit : codeword) std::cout << unsigned(bit);
            std::cout << '\n';
        }
    }
}
'''


def native_codewords(
    tavildar_root: Path,
) -> dict[tuple[int, int, int], tuple[str, str]]:
    with tempfile.TemporaryDirectory(prefix="mwdsp-wifi-ldpc-oracle-") as raw:
        temporary = Path(raw)
        driver = temporary / "driver.cpp"
        executable = temporary / "driver"
        driver.write_text(DRIVER_SOURCE, encoding="ascii", newline="\n")
        command = [
            "c++",
            "-std=c++14",
            "-O2",
            "-include",
            "algorithm",
            "-include",
            "cstdint",
            "-I",
            str(tavildar_root / "LdpcC"),
            str(driver),
            str(tavildar_root / TAVILDAR_SOURCE_PATH),
            "-o",
            str(executable),
        ]
        try:
            subprocess.run(command, check=True, capture_output=True)
            output = subprocess.run(
                [str(executable)], check=True, capture_output=True, text=True
            ).stdout
        except (OSError, subprocess.CalledProcessError) as error:
            raise OracleError(f"cannot run pinned tavildar encoder: {error}") from error
    result: dict[tuple[int, int, int], tuple[str, str]] = {}
    for line in output.splitlines():
        fields = line.split("\t")
        if len(fields) != 5:
            raise OracleError("native tavildar driver emitted a malformed row")
        key = (int(fields[0]), int(fields[1]), int(fields[2]))
        information, codeword = fields[3], fields[4]
        if any(bit not in "01" for bit in information + codeword):
            raise OracleError("native tavildar driver emitted a non-binary word")
        result[key] = (information, codeword)
    if tuple(result) != PROFILE_ORDER:
        raise OracleError("native tavildar profile order or membership changed")
    return result


def license_comment(prefix: str, license_bytes: bytes) -> list[str]:
    text = license_bytes.decode("ascii")
    lines = [f"# {prefix}_license_text_begin"]
    lines.extend("# " + line if line else "#" for line in text.splitlines())
    lines.append(f"# {prefix}_license_text_end")
    return lines


def render(yaldpc_root: Path, tavildar_root: Path) -> str:
    checked_commit(yaldpc_root, YALDPC_COMMIT)
    checked_commit(tavildar_root, TAVILDAR_COMMIT)
    yaldpc_matrix_bytes = checked_file(
        yaldpc_root, YALDPC_MATRIX_PATH, YALDPC_MATRIX_SHA256
    )
    yaldpc_license_bytes = checked_file(
        yaldpc_root, Path("LICENSE"), YALDPC_LICENSE_SHA256
    )
    tavildar_matrix_bytes = checked_file(
        tavildar_root, TAVILDAR_MATRIX_PATH, TAVILDAR_MATRIX_SHA256
    )
    checked_file(tavildar_root, TAVILDAR_HEADER_PATH, TAVILDAR_HEADER_SHA256)
    checked_file(tavildar_root, TAVILDAR_SOURCE_PATH, TAVILDAR_SOURCE_SHA256)
    tavildar_license_bytes = checked_file(
        tavildar_root, Path("LICENSE"), TAVILDAR_LICENSE_SHA256
    )

    yaldpc = parse_yaldpc(yaldpc_matrix_bytes)
    tavildar = parse_tavildar(tavildar_matrix_bytes)
    if yaldpc != tavildar:
        raise OracleError("the independent YALDPC and tavildar matrices disagree")
    codewords = native_codewords(tavildar_root)

    records: list[str] = []
    total_edges = 0
    for block_length, numerator, denominator in PROFILE_ORDER:
        key = (block_length, numerator, denominator)
        matrix = yaldpc[key]
        lifting_size = block_length // 24
        block_rows = len(matrix)
        parity_length = block_rows * lifting_size
        information_length = block_length - parity_length
        graph = expand_graph(matrix, lifting_size)
        edge_count = sum(len(row) for row in graph)
        total_edges += edge_count
        information, codeword = codewords[key]
        if len(information) != information_length or len(codeword) != block_length:
            raise OracleError("native tavildar word dimensions are invalid")
        bits = [int(bit) for bit in codeword]
        if any(sum(bits[column] for column in row) & 1 for row in graph):
            raise OracleError("native tavildar word fails the independent YALDPC graph")
        records.append(
            "profile\t{}\t{}\t{}\t-1\t{},{},{},{},{},{}\t-".format(
                block_length,
                numerator,
                denominator,
                lifting_size,
                block_rows,
                information_length,
                parity_length,
                sum(shift >= 0 for row in matrix for shift in row),
                edge_count,
            )
        )
        for row_index, row in enumerate(matrix):
            records.append(
                "base\t{}\t{}\t{}\t{}\t{}\t-".format(
                    block_length,
                    numerator,
                    denominator,
                    row_index,
                    ",".join(str(value) for value in row),
                )
            )
        records.append(
            "codeword\t{}\t{}\t{}\t-1\t{}\t{}".format(
                block_length,
                numerator,
                denominator,
                information,
                codeword,
            )
        )

    records_bytes = ("\n".join(records) + "\n").encode("ascii")
    generator_sha256 = sha256(Path(__file__).read_bytes())
    header = [
        "# MWDSP-WIFI-LDPC-MATRIX-ORACLE-V1",
        f"# generator_sha256={generator_sha256}",
        "# dependencies=python_standard_library_and_cxx14_only",
        f"# yaldpc_repository={YALDPC_REPOSITORY}",
        f"# yaldpc_commit={YALDPC_COMMIT}",
        f"# yaldpc_matrix_path={YALDPC_MATRIX_PATH.as_posix()}",
        f"# yaldpc_matrix_sha256={YALDPC_MATRIX_SHA256}",
        f"# yaldpc_license=BSD-3-Clause;license_sha256={YALDPC_LICENSE_SHA256}",
        f"# tavildar_repository={TAVILDAR_REPOSITORY}",
        f"# tavildar_commit={TAVILDAR_COMMIT}",
        f"# tavildar_matrix_path={TAVILDAR_MATRIX_PATH.as_posix()}",
        f"# tavildar_matrix_sha256={TAVILDAR_MATRIX_SHA256}",
        f"# tavildar_header_sha256={TAVILDAR_HEADER_SHA256}",
        f"# tavildar_source_sha256={TAVILDAR_SOURCE_SHA256}",
        f"# tavildar_license=MIT;license_sha256={TAVILDAR_LICENSE_SHA256}",
        "# oracle_role=independent_differential_only_not_normative_authority",
        "# expansion=right_circulant_column=(local_row+shift)%lifting_size",
        "# information=xorshift64star_seed_0x6a09e667f3bcc909_xor_N_shift17_xor_Rn_shift9_xor_Rd;output_msb",
        f"# corpus=12_profiles;2160_base_entries;90_base_rows;12_codewords;{total_edges}_expanded_edges",
        f"# canonical_records_sha256={sha256(records_bytes)}",
    ]
    header.extend(license_comment("yaldpc_bsd3", yaldpc_license_bytes))
    header.extend(license_comment("tavildar_mit", tavildar_license_bytes))
    header.append(
        "record\tblock_length\trate_numerator\trate_denominator\trow_index\tvalues\tauxiliary"
    )
    return "\n".join(header) + "\n" + records_bytes.decode("ascii")


def main() -> int:
    if len(sys.argv) != 3:
        print(
            "usage: generate_wifi_ldpc_matrix_oracle.py "
            "YALDPC_CHECKOUT TAVILDAR_LDPC_CHECKOUT",
            file=sys.stderr,
        )
        return 2
    try:
        output = render(Path(sys.argv[1]).resolve(), Path(sys.argv[2]).resolve())
    except OracleError as error:
        print(f"Wi-Fi LDPC oracle generation failed: {error}", file=sys.stderr)
        return 1
    sys.stdout.write(output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
