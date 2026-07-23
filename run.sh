#!/usr/bin/env bash
set -euo pipefail

# Edit these paths, or export INPUT_DIR, WORK_DIR, and OUTDIR before running.
INPUT_DIR="${INPUT_DIR:-/path/to/paired-fastq}"
WORK_DIR="${WORK_DIR:-/path/to/nextflow-work}"
OUTDIR="${OUTDIR:-/path/to/results}"

readonly REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly CONFIG_FILE="${CONFIG_FILE:-${REPO_ROOT}/nextflow.config}"
readonly PARAMS_FILE="${PARAMS_FILE:-${REPO_ROOT}/parameters.yaml}"
readonly PIPELINE_INFO_DIR="${OUTDIR}/pipeline_info"

for path_value in "${INPUT_DIR}" "${WORK_DIR}" "${OUTDIR}"; do
  if [[ "${path_value}" == /path/to/* ]]; then
    echo "ERROR: edit the example paths in run.sh or export INPUT_DIR, WORK_DIR, and OUTDIR." >&2
    exit 2
  fi
done

command -v nextflow >/dev/null 2>&1 || {
  echo "ERROR: nextflow is not available. Activate pathseq-t2t-nextflow first." >&2
  exit 1
}
[[ -d "${INPUT_DIR}" ]] || {
  echo "ERROR: input directory not found: ${INPUT_DIR}" >&2
  exit 1
}
[[ -s "${CONFIG_FILE}" ]] || {
  echo "ERROR: Nextflow configuration not found: ${CONFIG_FILE}" >&2
  exit 1
}
[[ -s "${PARAMS_FILE}" ]] || {
  echo "ERROR: parameter file not found: ${PARAMS_FILE}" >&2
  echo "Create it with: cp parameters.example.yaml parameters.yaml" >&2
  exit 1
}

mkdir -p "${WORK_DIR}" "${OUTDIR}" "${PIPELINE_INFO_DIR}"

nextflow \
  -c "${CONFIG_FILE}" \
  run "${REPO_ROOT}" \
  -params-file "${PARAMS_FILE}" \
  -profile local \
  -work-dir "${WORK_DIR}" \
  -resume \
  -with-report "${PIPELINE_INFO_DIR}/nextflow_report.html" \
  -with-timeline "${PIPELINE_INFO_DIR}/nextflow_timeline.html" \
  -with-trace "${PIPELINE_INFO_DIR}/nextflow_trace.tsv" \
  -with-dag "${PIPELINE_INFO_DIR}/nextflow_dag.html" \
  --input_dir "${INPUT_DIR}" \
  --input_mode fastq \
  --outdir "${OUTDIR}"
