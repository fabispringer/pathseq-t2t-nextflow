#!/usr/bin/env bash
#BSUB -L /bin/bash
#BSUB -n 1
#BSUB -J pathseq-t2t-nextflow
#BSUB -o pathseq-t2t-nextflow.%J.out
#BSUB -e pathseq-t2t-nextflow.%J.err
#BSUB -W 144:00
#BSUB -P acc_SeqLiver
#BSUB -q premium
#BSUB -R "rusage[mem=4000]"
#BSUB -R "span[hosts=1]"

set -euo pipefail

REPO_ROOT="${REPO_ROOT:-${LS_SUBCWD:-$PWD}}"
CONDA_ENV_PREFIX="${CONDA_ENV_PREFIX:-/path/to/conda/envs/pathseq-t2t-nextflow}"
WORK_DIR="${WORK_DIR:-/path/to/shared/nextflow-work}"

readonly REPO_ROOT="$(cd "${REPO_ROOT}" && pwd -P)"
readonly PARAMS_FILE="${PARAMS_FILE:-${REPO_ROOT}/parameters.yaml}"

for path_value in "${CONDA_ENV_PREFIX}" "${WORK_DIR}"; do
  if [[ "${path_value}" == /path/to/* ]]; then
    echo "ERROR: edit CONDA_ENV_PREFIX and WORK_DIR in run_lsf.sh or export them before submission." >&2
    exit 2
  fi
done
[[ -s "${REPO_ROOT}/main.nf" ]] || {
  echo "ERROR: repository root not found: ${REPO_ROOT}" >&2
  echo "Submit from the repository root or export REPO_ROOT." >&2
  exit 1
}
[[ -d "${CONDA_ENV_PREFIX}/bin" ]] || {
  echo "ERROR: Conda environment not found: ${CONDA_ENV_PREFIX}" >&2
  exit 1
}

export PATH="${CONDA_ENV_PREFIX}/bin:${PATH}"
export JAVA_HOME="${CONDA_ENV_PREFIX}/lib/jvm"

command -v nextflow >/dev/null 2>&1 || {
  echo "ERROR: nextflow is not available in the controller job." >&2
  exit 1
}
command -v bsub >/dev/null 2>&1 || {
  echo "ERROR: bsub is not available in the controller job." >&2
  exit 1
}
[[ -s "${PARAMS_FILE}" ]] || {
  echo "ERROR: parameter file not found: ${PARAMS_FILE}" >&2
  exit 1
}

mkdir -p "${WORK_DIR}"

nextflow run "${REPO_ROOT}" \
  -params-file "${PARAMS_FILE}" \
  -profile lsf \
  -work-dir "${WORK_DIR}" \
  -resume
