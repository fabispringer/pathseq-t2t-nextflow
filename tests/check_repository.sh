#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${repo_root}"

bash -n scripts/*.sh overrides/*.sh
python3 -m py_compile scripts/*.py

if rg -n -i '(/Users/[^/]+/|/home/[^/]+/|pathseq-t2t_setup|openclaw|gmail)' \
  --glob '!pathseq-t2t/upstream/**' \
  --glob '!tests/check_repository.sh' \
  --glob '!.nextflow*' .; then
  echo "ERROR: Found a setup-specific or private identifier." >&2
  exit 1
fi

required=(
  .gitignore
  main.nf
  nextflow.config
  parameters.example.yaml
  README.md
  LICENSE
  THIRD_PARTY_NOTICES.md
  CITATION.cff
  run_lsf.sh
  scripts/setup_pathseq_t2t.sh
)
for file in "${required[@]}"; do
  [[ -s "${file}" ]] || {
    echo "ERROR: Missing required file: ${file}" >&2
    exit 1
  }
done

manifest_version="$(
  awk -F"'" '/^[[:space:]]*version = / { print $2; exit }' nextflow.config
)"
citation_version="$(
  awk '/^version:/ { value=$2; gsub(/"/, "", value); print value; exit }' CITATION.cff
)"
[[ -n "${manifest_version}" ]] || {
  echo "ERROR: Missing manifest version in nextflow.config." >&2
  exit 1
}
[[ "${manifest_version}" == "${citation_version}" ]] || {
  echo "ERROR: Version mismatch: manifest=${manifest_version}, CITATION.cff=${citation_version}" >&2
  exit 1
}
rg -q "process WRITE_WORKFLOW_VERSION" main.nf || {
  echo "ERROR: Missing workflow-version output process." >&2
  exit 1
}

echo "Repository checks passed."
