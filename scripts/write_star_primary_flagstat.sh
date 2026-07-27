#!/usr/bin/env bash
set -euo pipefail

paired_log=""
single_log=""
output=""

usage() {
  cat <<'EOF'
Usage: write_star_primary_flagstat.sh [--paired-log <Log.final.out>] [--single-log <Log.final.out>] --output <flagstat.tsv>

Writes the primary-read row expected by the upstream `pathseq-t2t summarize`
command. At least one STAR log is required. For paired-end STAR input, "Number
of input reads" is the number of read pairs, so the value is multiplied by two
to obtain individual reads/mates. Single-end STAR input is added without
multiplication.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --paired-log) paired_log="${2:?--paired-log requires a path}"; shift 2 ;;
    --single-log) single_log="${2:?--single-log requires a path}"; shift 2 ;;
    --output) output="${2:?--output requires a path}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "ERROR: Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

if [[ -z "$paired_log" && -z "$single_log" ]]; then
  echo "ERROR: At least one of --paired-log or --single-log is required" >&2
  exit 1
fi
if [[ -z "$output" ]]; then
  echo "ERROR: --output is required" >&2
  exit 1
fi

primary_reads=0
if [[ -n "$paired_log" ]]; then
  if [[ ! -s "$paired_log" ]]; then
    echo "ERROR: Missing or empty paired-end STAR log: $paired_log" >&2
    exit 1
  fi
  input_pairs="$(
    awk -F '|' '
      /Number of input reads/ {
        gsub(/[[:space:]]/, "", $2)
        print $2
        exit
      }
    ' "$paired_log"
  )"
  if [[ ! "$input_pairs" =~ ^[0-9]+$ ]]; then
    echo "ERROR: Could not parse Number of input reads from: $paired_log" >&2
    exit 1
  fi
  primary_reads=$((input_pairs * 2))
fi

if [[ -n "$single_log" ]]; then
  if [[ ! -s "$single_log" ]]; then
    echo "ERROR: Missing or empty single-end STAR log: $single_log" >&2
    exit 1
  fi
  single_reads="$(
    awk -F '|' '
      /Number of input reads/ {
        gsub(/[[:space:]]/, "", $2)
        print $2
        exit
      }
    ' "$single_log"
  )"
  if [[ ! "$single_reads" =~ ^[0-9]+$ ]]; then
    echo "ERROR: Could not parse Number of input reads from: $single_log" >&2
    exit 1
  fi
  primary_reads=$((primary_reads + single_reads))
fi
mkdir -p "$(dirname -- "$output")"
tmp_output="${output}.tmp.$$"
trap 'rm -f "$tmp_output"' EXIT
printf '%s\t0\tprimary\n' "$primary_reads" > "$tmp_output"
mv -f "$tmp_output" "$output"
trap - EXIT

echo "Wrote STAR primary reads: $primary_reads -> $output"
