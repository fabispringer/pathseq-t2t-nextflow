#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${repo_root}"

bash -n scripts/*.sh overrides/*.sh
python3 -m py_compile scripts/*.py

if rg -n -i '(fspringe|/g/scb|pathseq-t2t_setup|openclaw|gmail)' \
  --glob '!pathseq-t2t/upstream/**' \
  --glob '!tests/check_repository.sh' \
  --glob '!.nextflow*' .; then
  echo "ERROR: Found a setup-specific or private identifier." >&2
  exit 1
fi

required=(
  main.nf
  nextflow.config
  parameters.example.yaml
  README.md
  LICENSE
  THIRD_PARTY_NOTICES.md
  CITATION.cff
  scripts/setup_pathseq_t2t.sh
)
for file in "${required[@]}"; do
  [[ -s "${file}" ]] || {
    echo "ERROR: Missing required file: ${file}" >&2
    exit 1
  }
done

echo "Repository checks passed."
