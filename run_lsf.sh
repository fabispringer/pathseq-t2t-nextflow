#!/usr/bin/env bash
#BSUB -L /bin/bash
#BSUB -n 1
#BSUB -J pathseq-t2t-nextflow
#BSUB -o pathseq-t2t-nextflow.%J.out
#BSUB -e pathseq-t2t-nextflow.%J.err
#BSUB -W 144:00
#BSUB -P YOUR_LSF_PROJECT
#BSUB -q YOUR_LSF_QUEUE
#BSUB -R "rusage[mem=4000]"
#BSUB -R "span[hosts=1]"

set -euo pipefail

# Run-specific paths.
INPUT_DIR="/path/to/input"
WORK_DIR="/path/to/nextflow-work"
OUTDIR="/path/to/results"

# Workflow paths and version.
readonly REPO_ROOT="/path/to/pathseq-t2t-nextflow"
readonly WORKFLOW_VERSION="v0.1.1"
readonly CONFIG_FILE="${REPO_ROOT}/nextflow.config"
readonly PARAMS_FILE="/path/to/parameters.lsf.yaml"
readonly PIPELINE_INFO_DIR="${OUTDIR}/pipeline_info"
readonly PATHSEQ_BIN="${REPO_ROOT}/pathseq-t2t/upstream/src/pathseq-t2t"

command -v nextflow >/dev/null 2>&1 || {
  echo "ERROR: nextflow is unavailable. Activate pathseq-t2t-nextflow before submitting this job." >&2
  exit 1
}

command -v bsub >/dev/null 2>&1 || {
  echo "ERROR: bsub is not available in the controller job." >&2
  exit 1
}

[[ -d "${INPUT_DIR}" ]] || {
  echo "ERROR: input directory not found: ${INPUT_DIR}" >&2
  exit 1
}

[[ -s "${PARAMS_FILE}" ]] || {
  echo "ERROR: parameter file not found: ${PARAMS_FILE}" >&2
  exit 1
}

# Select the immutable workflow release.
git -C "${REPO_ROOT}" checkout -q "${WORKFLOW_VERSION}"

[[ -x "${PATHSEQ_BIN}" ]] || {
  echo "ERROR: managed PathSeq-T2T runtime is missing." >&2
  echo "Run this once:" >&2
  echo "  cd ${REPO_ROOT}" >&2
  echo "  ./scripts/setup_pathseq_t2t.sh" >&2
  exit 1
}

mkdir -p \
  "${WORK_DIR}" \
  "${OUTDIR}" \
  "${PIPELINE_INFO_DIR}"

echo "Workflow version: ${WORKFLOW_VERSION}"
echo "Execution profile: lsf"
echo "Input directory:   ${INPUT_DIR}"
echo "Work directory:    ${WORK_DIR}"
echo "Output directory:  ${OUTDIR}"
echo "Parameter file:    ${PARAMS_FILE}"

nextflow \
  -c "${CONFIG_FILE}" \
  run "${REPO_ROOT}" \
  -params-file "${PARAMS_FILE}" \
  -profile lsf \
  -work-dir "${WORK_DIR}" \
  -resume \
  -with-report "${PIPELINE_INFO_DIR}/nextflow_report.html" \
  -with-timeline "${PIPELINE_INFO_DIR}/nextflow_timeline.html" \
  -with-trace "${PIPELINE_INFO_DIR}/nextflow_trace.tsv" \
  -with-dag "${PIPELINE_INFO_DIR}/nextflow_dag.html" \
  --input_dir "${INPUT_DIR}" \
  --input_mode fastq \
  --outdir "${OUTDIR}"
