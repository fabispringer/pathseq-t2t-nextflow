#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${repo_root}"

bash -n scripts/*.sh overrides/*.sh
python3 -m py_compile scripts/*.py
bash tests/test_qcfilter_metrics.sh
bash tests/test_write_star_primary_flagstat.sh
python3 tests/test_merge_star_gene_counts.py
python3 tests/test_collate_kraken_results.py
python3 tests/test_check_fastq_content.py

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

expected_version="0.3.0"
citation_version="$(awk '$1 == "version:" { print $2; exit }' CITATION.cff)"
manifest_version="$(
  awk -F"'" '
    /^[[:space:]]*version[[:space:]]*=/ {
      print $2
      exit
    }
  ' nextflow.config
)"
run_version="$(
  awk -F'"' '
    /^readonly WORKFLOW_VERSION=/ {
      value=$2
      sub(/^v/, "", value)
      print value
      exit
    }
  ' run.sh
)"
for version_source in \
  "CITATION.cff:${citation_version}" \
  "nextflow.config:${manifest_version}" \
  "run.sh:${run_version}"; do
  source_file="${version_source%%:*}"
  observed_version="${version_source#*:}"
  [[ "${observed_version}" == "${expected_version}" ]] || {
    echo "ERROR: ${source_file} version is '${observed_version}', expected '${expected_version}'." >&2
    exit 1
  }
done

echo "Repository checks passed."
