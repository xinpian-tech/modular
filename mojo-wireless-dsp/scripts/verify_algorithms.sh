#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# This is the authoritative CPU/protocol/fixed algorithm gate.  Components
# outside that algorithm scope are omitted from execution, evidence validation,
# exports, completion status, and reported counts.
exec env MWDSP_VERIFY_ALGORITHMS_ONLY=1 \
  MWDSP_VERIFY_STRICT_COMPLETION=1 \
  bash "${script_dir}/verify.sh" "$@"
