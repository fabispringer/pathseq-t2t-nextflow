#!/usr/bin/env bash
set -euo pipefail

readonly UPSTREAM_URL="https://github.com/abdohlman/pathseq-t2t.git"
readonly UPSTREAM_COMMIT="51d74430b6a4b34073f2d878612ac24b6a1d1e80"
readonly REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly RUNTIME_DIR="${REPO_ROOT}/pathseq-t2t/upstream"

if [[ -e "${RUNTIME_DIR}" ]]; then
  echo "ERROR: ${RUNTIME_DIR} already exists." >&2
  echo "Remove it explicitly before rebuilding the managed runtime." >&2
  exit 1
fi

mkdir -p "$(dirname "${RUNTIME_DIR}")"
git clone "${UPSTREAM_URL}" "${RUNTIME_DIR}"
git -C "${RUNTIME_DIR}" checkout --detach "${UPSTREAM_COMMIT}"

install -m 0755 "${REPO_ROOT}/overrides/qcfilter.sh" \
  "${RUNTIME_DIR}/src/commands/qcfilter.sh"
install -m 0755 "${REPO_ROOT}/overrides/t2tfilter.sh" \
  "${RUNTIME_DIR}/src/commands/t2tfilter.sh"

actual_commit="$(git -C "${RUNTIME_DIR}" rev-parse HEAD)"
[[ "${actual_commit}" == "${UPSTREAM_COMMIT}" ]] || {
  echo "ERROR: Expected ${UPSTREAM_COMMIT}, got ${actual_commit}." >&2
  exit 1
}

echo "Prepared workflow-managed PathSeq-T2T runtime at: ${RUNTIME_DIR}"
echo "Upstream commit: ${actual_commit}"
echo "Local reviewed fixes: qcfilter.sh, t2tfilter.sh"
