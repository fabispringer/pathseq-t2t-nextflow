#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${repo_root}/overrides/qcfilter.sh"

test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT

metrics="${test_dir}/filter_metrics.txt"
printf '%s\n' \
  '## METRICS CLASS	org.broadinstitute.hellbender.tools.spark.pathseq.PSFilterMetrics' \
  $'FINAL_UNPAIRED_READS\tPRIMARY_READS\tFINAL_PAIRED_READS\tSECONDARY_READS' \
  $'3\t100\t14\t8' \
  > "$metrics"

IFS=$'\t' read -r paired unpaired < <(_read_pathseq_final_counts "$metrics")
[[ "$paired" == "14" && "$unpaired" == "3" ]] || {
  echo "ERROR: Reordered metrics parsed as paired=${paired}, unpaired=${unpaired}" >&2
  exit 1
}

missing_header="${test_dir}/missing_header.txt"
printf '%s\n' \
  $'PRIMARY_READS\tFINAL_PAIRED_READS' \
  $'100\t14' \
  > "$missing_header"
if _read_pathseq_final_counts "$missing_header" >/dev/null 2>&1; then
  echo "ERROR: Expected metrics without FINAL_UNPAIRED_READS to fail" >&2
  exit 1
fi

missing_values="${test_dir}/missing_values.txt"
printf '%s\n' \
  $'PRIMARY_READS\tFINAL_PAIRED_READS\tFINAL_UNPAIRED_READS' \
  > "$missing_values"
if _read_pathseq_final_counts "$missing_values" >/dev/null 2>&1; then
  echo "ERROR: Expected metrics without a value row to fail" >&2
  exit 1
fi

echo "qcfilter metrics tests passed."
