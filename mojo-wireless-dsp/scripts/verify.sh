#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(cd "${script_dir}/.." && pwd)"
repo_root="$(cd "${project_dir}/.." && pwd)"

if [[ "${MWDSP_VERIFY_IN_NIX:-0}" != "1" ]]; then
  nix_env=(MWDSP_VERIFY_IN_NIX=1)
  if [[ -n "${MWDSP_LICENSE_RIGHTS_ATTESTATION_FILE:-}" ]]; then
    rights_attestation="${MWDSP_LICENSE_RIGHTS_ATTESTATION_FILE}"
    if [[ "${rights_attestation}" != /* ]]; then
      rights_attestation="$(cd "$(dirname "${rights_attestation}")" && pwd)/$(basename "${rights_attestation}")"
    fi
    nix_env+=(MWDSP_LICENSE_RIGHTS_ATTESTATION_FILE="${rights_attestation}")
  fi
  if [[ -n "${MWDSP_AUTHORITY_ARTIFACT_DIR:-}" ]]; then
    authority_artifact_dir="${MWDSP_AUTHORITY_ARTIFACT_DIR}"
    if [[ "${authority_artifact_dir}" != /* ]]; then
      authority_artifact_dir="$(cd "${authority_artifact_dir}" && pwd)"
    fi
    nix_env+=(MWDSP_AUTHORITY_ARTIFACT_DIR="${authority_artifact_dir}")
  fi
  cd "${repo_root}"
  exec nix shell .#mojo --command env "${nix_env[@]}" \
    bash "${script_dir}/verify.sh" "$@"
fi

cd "${repo_root}"

verify_tmp="$(mktemp -d "${TMPDIR:-/tmp}/mwdsp-verify.XXXXXX")"
cleanup() {
  rm -r -- "${verify_tmp}"
}
trap cleanup EXIT

# Run the frozen external-oracle gate before any build/test command that can
# terminate this script.  Its status is retained while the rest of the
# verification continues, so another red gate cannot hide an oracle failure.
external_oracle_status=0
printf 'verify frozen external Wi-Fi/NR oracle artifacts\n'
bash "${project_dir}/scripts/verify_external_oracles.sh" \
  || external_oracle_status=$?

wifi_ldpc_oracle_status=0
printf 'verify frozen dual-source Wi-Fi LDPC matrix oracle\n'
bash "${project_dir}/scripts/verify_wifi_ldpc_oracle.sh" \
  || wifi_ldpc_oracle_status=$?

verify_declared_sources() {
  local subdir="$1"
  local discovered="${verify_tmp}/${subdir}.discovered"
  local declared="${verify_tmp}/${subdir}.declared"
  find "${project_dir}/${subdir}" -maxdepth 1 -type f -name '*.mojo' \
    -printf "${subdir}/%f\n" | sort > "${discovered}"
  rg -o "${subdir}/[A-Za-z0-9_]+\\.mojo" \
    "${project_dir}/BUILD.bazel" | sort -u > "${declared}"
  if ! cmp -s "${discovered}" "${declared}"; then
    printf 'BUILD.bazel source mismatch for %s\n' "${subdir}" >&2
    printf '  missing declarations:\n' >&2
    comm -23 "${discovered}" "${declared}" >&2
    printf '  stale declarations:\n' >&2
    comm -13 "${discovered}" "${declared}" >&2
    exit 1
  fi
}

build_and_run() {
  local source="$1"
  local name
  name="$(basename "${source}" .mojo)"
  local binary="${verify_tmp}/${name}"
  printf 'verify %s\n' "${source}"
  mojo build --Werror -I "${project_dir}" "${source}" -o "${binary}"
  "${binary}"
}

printf 'toolchain '
mojo --version

printf 'audit BUILD.bazel source registration\n'
verify_declared_sources tests
verify_declared_sources benchmarks
verify_declared_sources examples

printf 'precompile wireless_dsp\n'
mojo precompile --Werror -I "${project_dir}" \
  "${project_dir}/wireless_dsp" -o "${verify_tmp}/wireless_dsp.mojoc"
package_bytes="$(wc -c < "${verify_tmp}/wireless_dsp.mojoc")"

while IFS= read -r source; do
  build_and_run "${source}"
done < <(
  if [[ "${MWDSP_VERIFY_ALGORITHMS_ONLY:-0}" == "1" ]]; then
    rg --files "${project_dir}/tests" -g '*.mojo' | rg -v '/gpu_' | sort
  else
    rg --files "${project_dir}/tests" -g '*.mojo' | sort
  fi
)

while IFS= read -r source; do
  build_and_run "${source}"
done < <(rg --files "${project_dir}/benchmarks" -g '*.mojo' | sort)

while IFS= read -r source; do
  build_and_run "${source}"
done < <(
  rg --files "${project_dir}/examples" -g '*.mojo' \
    | rg -v '/gpu_(qpsk_demapper|phase6_kernels|backend_validation)\.mojo$' \
    | sort
)

coverage_arguments=()
if [[ "${MWDSP_VERIFY_ALGORITHMS_ONLY:-0}" == "1" ]]; then
  coverage_arguments+=(--strict --exclude-component backend_gpu)
elif [[ "${MWDSP_VERIFY_STRICT_COVERAGE:-0}" == "1" ]]; then
  coverage_arguments+=(--strict)
fi
printf 'audit public-kernel evidence ledger\n'
kernel_status=0
bash "${project_dir}/scripts/audit_kernel_coverage.sh" \
  "${coverage_arguments[@]}" || kernel_status=$?

completion_status=0
specification_arguments=()
feature_arguments=()
if [[ "${MWDSP_VERIFY_STRICT_COMPLETION:-0}" == "1" ]]; then
  specification_arguments+=(--strict)
  feature_arguments+=(--strict)
fi
printf 'audit current communication-protocol specification matrix\n'
bash "${project_dir}/scripts/audit_specification_coverage.sh" \
  "${specification_arguments[@]}" || completion_status=$?

printf 'audit communication-protocol Work Item and Feature matrix\n'
feature_status=0
bash "${project_dir}/scripts/audit_feature_coverage.sh" \
  "${feature_arguments[@]}" || feature_status=$?
if (( feature_status > completion_status )); then
  completion_status=${feature_status}
fi

# Do not stop the remaining deterministic checks when a licensed normative
# artifact is unavailable.  Preserve the ratified-only failure and return it
# after fixed-artifact, hygiene, GPU/Bazel and summary checks have completed.
authority_status=0
printf 'audit ratified-only normative authorities and artifact hashes\n'
# A syntactically valid digest in the manifest is not independent evidence.
# The authoritative/full gate therefore re-downloads (or validates an
# explicitly supplied MWDSP_AUTHORITY_ARTIFACT_DIR cache of) every accessible
# production artifact and compares its actual bytes with the pinned SHA-256.
bash "${project_dir}/scripts/audit_ratified_authorities.sh" --verify-downloads \
  || authority_status=$?

printf 'verify checked-in fixed artifact V2 corpus\n'
MWDSP_FIXED_ARTIFACT_VERIFY_IN_NIX=1 \
  bash "${project_dir}/scripts/verify_fixed_artifacts.sh"

printf 'audit source hygiene\n'
while IFS= read -r script; do
  bash -n "${script}"
done < <(rg --files "${project_dir}/scripts" -g '*.sh' | sort)
if rg -n '[ \t]+$' "${project_dir}" \
  -g '*.mojo' -g '*.md' -g '*.sh' -g '*.tsv' -g 'BUILD.bazel'; then
  printf 'trailing whitespace found\n' >&2
  exit 1
fi
if rg -n \
  'comptime _WARMUPS? = [0-2]$|comptime _(SAMPLES|REPETITIONS) = [0-8]$' \
  "${project_dir}/benchmarks" -g '*.mojo'; then
  printf 'benchmark requires at least 3 warmups and 9 samples\n' >&2
  exit 1
fi
if rg -n -U \
  'global_perf_counter_ns\(\).*(salt|seed)|(salt|seed).*global_perf_counter_ns\(|var (salt|seed) = (Int|UInt64)\(\n([^\n]*\n){0,2}[^\n]*global_perf_counter_ns\(' \
  "${project_dir}/benchmarks" -g '*.mojo'; then
  printf 'benchmark input seed/salt must not depend on the wall clock\n' >&2
  exit 1
fi

if [[ "${MWDSP_VERIFY_ALGORITHMS_ONLY:-0}" != "1" \
  && "${MWDSP_VERIFY_SKIP_GPU:-0}" != "1" ]]; then
  for source in \
    "${project_dir}/examples/gpu_qpsk_demapper.mojo" \
    "${project_dir}/examples/gpu_phase6_kernels.mojo"; do
    name="$(basename "${source}" .mojo)"
    binary="${verify_tmp}/${name}"
    printf 'compile/run capability-gated %s\n' "${source}"
    # Imported MAX/layout sources currently emit upstream deprecation warnings,
    # so these examples cannot be built with --Werror without changing MAX.
    mojo build -I max/mojo -I max/kernels/src -I "${project_dir}" \
      "${source}" -o "${binary}"
    "${binary}"
  done

  source="${project_dir}/examples/gpu_backend_validation.mojo"
  binary="${verify_tmp}/gpu_backend_validation"
  printf 'compile/run warning-clean %s\n' "${source}"
  mojo build --Werror -I max/mojo -I max/kernels/src -I "${project_dir}" \
    "${source}" -o "${binary}"
  "${binary}"
fi

if [[ "${MWDSP_VERIFY_SKIP_BAZEL_QUERY:-0}" != "1" ]]; then
  printf 'query wireless DSP Bazel target graph\n'
  nix develop --command bazel-nix query '//mojo-wireless-dsp:*' \
    | tee "${verify_tmp}/bazel-query"
  bazel_labels="$(rg -c '^//mojo-wireless-dsp:' \
    "${verify_tmp}/bazel-query")"
else
  bazel_labels="skipped"
fi

if [[ "${MWDSP_VERIFY_ALGORITHMS_ONLY:-0}" == "1" ]]; then
  test_files="$(rg --files "${project_dir}/tests" -g '*.mojo' \
    | rg -v '/gpu_' | wc -l)"
  test_functions="$(rg -n '^def test_' "${project_dir}/tests" -g '*.mojo' \
    | rg -v '/gpu_' | wc -l)"
else
  test_files="$(rg --files "${project_dir}/tests" -g '*.mojo' | wc -l)"
  test_functions="$(rg -n '^def test_' "${project_dir}/tests" -g '*.mojo' | wc -l)"
fi
benchmarks="$(rg --files "${project_dir}/benchmarks" -g '*.mojo' | wc -l)"
printf 'verified %s test files, %s test functions, %s benchmarks\n' \
  "${test_files// /}" "${test_functions// /}" "${benchmarks// /}"
printf 'precompiled package bytes=%s; Bazel labels=%s\n' \
  "${package_bytes// /}" "${bazel_labels}"

if (( authority_status != 0 )); then
  printf 'ratified-only authority gate failed with exit %d\n' \
    "${authority_status}" >&2
fi
if (( external_oracle_status != 0 )); then
  printf 'external-oracle artifact gate failed with exit %d\n' \
    "${external_oracle_status}" >&2
fi
if (( wifi_ldpc_oracle_status != 0 )); then
  printf 'Wi-Fi LDPC matrix-oracle gate failed with exit %d\n' \
    "${wifi_ldpc_oracle_status}" >&2
fi
if (( kernel_status != 0 )); then
  printf 'strict public-kernel evidence gate failed with exit %d\n' \
    "${kernel_status}" >&2
fi
if (( completion_status != 0 )); then
  printf 'strict specification/feature completion gate failed with exit %d\n' \
    "${completion_status}" >&2
fi
final_status=${external_oracle_status}
if (( wifi_ldpc_oracle_status > final_status )); then
  final_status=${wifi_ldpc_oracle_status}
fi
if (( kernel_status > final_status )); then
  final_status=${kernel_status}
fi
if (( authority_status > final_status )); then
  final_status=${authority_status}
fi
if (( completion_status > final_status )); then
  final_status=${completion_status}
fi
if (( final_status != 0 )); then
  exit "${final_status}"
fi
