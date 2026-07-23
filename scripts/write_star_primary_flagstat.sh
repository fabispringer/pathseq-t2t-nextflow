#!/usr/bin/env bash
set -euo pipefail

star_log=""
single_log=""
output=""

usage() {
  cat <<'EOF'
Usage: write_star_primary_flagstat.sh --star-log <Log.final.out> [--single-log <Log.final.out>] --output <flagstat.tsv>

Writes the primary-read row expected by the upstream `pathseq-t2t summarize`
command. For paired-end STAR input, "Number of input reads" is the number of
read pairs, so the value is multiplied by two to obtain individual reads/mates.
An optional single-end STAR log is added without multiplication.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --star-log) star_log="${2:?--star-log requires a path}"; shift 2 ;;
    --single-log) single_log="${2:?--single-log requires a path}"; shift 2 ;;
    --output) output="${2:?--output requires a path}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "ERROR: Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

if [[ ! -s "$star_log" ]]; then
  echo "ERROR: Missing or empty STAR Log.final.out: ${star_log:-<unset>}" >&2
  exit 1
fi
if [[ -z "$output" ]]; then
  echo "ERROR: --output is required" >&2
  exit 1
fi

input_pairs="$(
  awk -F '|' '
    /Number of input reads/ {
      gsub(/[[:space:]]/, "", $2)
      print $2
      exit
    }
  ' "$star_log"
)"

if [[ ! "$input_pairs" =~ ^[0-9]+$ ]]; then
  echo "ERROR: Could not parse Number of input reads from: $star_log" >&2
  exit 1
fi

primary_reads=$((input_pairs * 2))
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
