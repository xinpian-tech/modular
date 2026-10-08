#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(cd "${script_dir}/.." && pwd)"
repo_root="$(cd "${project_dir}/.." && pwd)"

if [[ "${MWDSP_FIXED_ARTIFACT_VERIFY_IN_NIX:-0}" != "1" ]]; then
  cd "${repo_root}"
  exec nix shell .#mojo --command env \
    MWDSP_FIXED_ARTIFACT_VERIFY_IN_NIX=1 \
    bash "${script_dir}/verify_fixed_artifacts.sh" "$@"
fi

cd "${repo_root}"
verify_tmp="$(mktemp -d "${TMPDIR:-/tmp}/mwdsp-fixed-v2.XXXXXX")"
cleanup() {
  rm -r -- "${verify_tmp}"
}
trap cleanup EXIT

binary="${verify_tmp}/fixed_artifact_corpus"
first="${verify_tmp}/first"
second="${verify_tmp}/second"
mkdir -p -- "${first}" "${second}"

printf 'compile fixed artifact V2 corpus generator\n'
mojo build --Werror -I "${project_dir}" \
  "${project_dir}/tools/fixed_artifact_corpus.mojo" -o "${binary}"

printf 'regenerate fixed artifact V2 corpus twice\n'
"${binary}" "${first}"
"${binary}" "${second}"

files=(
  complex.mwdsp
  fft-trace.mwdsp
  manifest.tsv
  scalar.mwdsp
  scale-trace.mwdsp
)

first_count="$(find "${first}" -maxdepth 1 -type f | wc -l)"
second_count="$(find "${second}" -maxdepth 1 -type f | wc -l)"
checked_count="$(find "${project_dir}/artifacts/fixed-v2" -maxdepth 1 -type f | wc -l)"
if [[ "${first_count}" != "${#files[@]}" \
    || "${second_count}" != "${#files[@]}" \
    || "${checked_count}" != "${#files[@]}" ]]; then
  printf 'fixed artifact corpus file set differs from the canonical five files\n' >&2
  exit 1
fi

printf 'compare deterministic regeneration and checked-in bytes\n'
for file in "${files[@]}"; do
  cmp -- "${first}/${file}" "${second}/${file}"
  cmp -- "${first}/${file}" \
    "${project_dir}/artifacts/fixed-v2/${file}"
done

printf 'fixed artifact V2 corpus byte comparison passed\n'
