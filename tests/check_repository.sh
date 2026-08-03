#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${repo_root}"

bash -n run.sh run_lsf.sh scripts/*.sh overrides/*.sh
python3 -m py_compile scripts/*.py
bash tests/test_qcfilter_metrics.sh
bash tests/test_write_star_primary_flagstat.sh
bash tests/test_bam_integrity_contract.sh
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
  run_lsf.sh
  scripts/setup_pathseq_t2t.sh
)
for file in "${required[@]}"; do
  [[ -s "${file}" ]] || {
    echo "ERROR: Missing required file: ${file}" >&2
    exit 1
  }
done

expected_version="0.3.1"
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
run_lsf_version="$(
  awk -F'"' '
    /^readonly WORKFLOW_VERSION=/ {
      value=$2
      sub(/^v/, "", value)
      print value
      exit
    }
  ' run_lsf.sh
)"
for version_source in \
  "CITATION.cff:${citation_version}" \
  "nextflow.config:${manifest_version}" \
  "run.sh:${run_version}" \
  "run_lsf.sh:${run_lsf_version}"; do
  source_file="${version_source%%:*}"
  observed_version="${version_source#*:}"
  [[ "${observed_version}" == "${expected_version}" ]] || {
    echo "ERROR: ${source_file} version is '${observed_version}', expected '${expected_version}'." >&2
    exit 1
  }
done

expected_nextflow_version=">=26.04.6"
manifest_nextflow_version="$(
  awk -F"'" '
    /^[[:space:]]*nextflowVersion[[:space:]]*=/ {
      print $2
      exit
    }
  ' nextflow.config
)"
[[ "${manifest_nextflow_version}" == "${expected_nextflow_version}" ]] || {
  echo "ERROR: nextflow.config requires '${manifest_nextflow_version}', expected '${expected_nextflow_version}'." >&2
  exit 1
}

grep -Fq "params.lsf = [" nextflow.config || {
  echo "ERROR: nextflow.config is missing params.lsf." >&2
  exit 1
}
grep -Fq "process.executor = 'lsf'" nextflow.config || {
  echo "ERROR: nextflow.config is missing the LSF execution profile." >&2
  exit 1
}
grep -Eq '^lsf:$' parameters.example.yaml || {
  echo "ERROR: parameters.example.yaml is missing the LSF parameter section." >&2
  exit 1
}

grep -Fq 'process WRITE_WORKFLOW_VERSION' main.nf || {
  echo "ERROR: main.nf is missing the workflow provenance process." >&2
  exit 1
}
grep -Fq "path 'workflow_version.tsv'" main.nf || {
  echo "ERROR: WRITE_WORKFLOW_VERSION does not declare workflow_version.tsv." >&2
  exit 1
}
grep -Fq "printf '%s\\\\t%s\\\\n'" main.nf || {
  echo "ERROR: WRITE_WORKFLOW_VERSION does not write a deterministic TSV with printf." >&2
  exit 1
}
if grep -Fq 'cat > workflow_version.tsv <<' main.nf; then
  echo "ERROR: WRITE_WORKFLOW_VERSION uses an indentation-sensitive heredoc." >&2
  exit 1
fi
grep -Fq 'WRITE_WORKFLOW_VERSION(versionInfo)' main.nf || {
  echo "ERROR: The workflow does not invoke WRITE_WORKFLOW_VERSION." >&2
  exit 1
}
grep -Fq 'pipeline_info/workflow_version.tsv' README.md || {
  echo "ERROR: README.md does not document workflow provenance output." >&2
  exit 1
}

echo "Repository checks passed."
