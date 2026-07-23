#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PATHSEQ_T2T_BIN="${PATHSEQ_T2T_BIN:-pathseq-t2t}"

sample_id=""
outdir=""
star_log=""

usage() {
  cat <<'EOF'
Usage: run_summarize.sh --sample-id <ID> --outdir <DIR> [OPTIONS]

Creates a STAR primary-read flagstat when --star-log is supplied, then writes
the summary and normalized classifier tables with the upstream Dohlman
PathSeq-T2T summarizer, without rerunning filtering or classification.

Options:
  --star-log <Log.final.out>   Generate the primary-read flagstat for STAR.
  --pathseq-t2t-bin <path>    PathSeq-T2T launcher (default: pathseq-t2t).
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --sample-id) sample_id="${2:?--sample-id requires a value}"; shift 2 ;;
    --outdir) outdir="${2:?--outdir requires a path}"; shift 2 ;;
    --star-log) star_log="${2:?--star-log requires a path}"; shift 2 ;;
    --pathseq-t2t-bin) PATHSEQ_T2T_BIN="${2:?--pathseq-t2t-bin requires a path}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "ERROR: Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

if [[ -z "$sample_id" || -z "$outdir" ]]; then
  echo "ERROR: --sample-id and --outdir are required" >&2
  usage >&2
  exit 2
fi

input_flagstat="${outdir}/filter_stats/${sample_id}.flagstat.tsv"
if [[ -n "$star_log" ]]; then
  "$SCRIPT_DIR/write_star_primary_flagstat.sh" \
    --star-log "$star_log" \
    --output "$input_flagstat"
fi

if [[ ! -s "$input_flagstat" ]]; then
  echo "ERROR: Missing primary-read flagstat: $input_flagstat" >&2
  echo "For STAR runs, provide --star-log <sample.star.Log.final.out>." >&2
  exit 1
fi

if [[ "$PATHSEQ_T2T_BIN" == */* ]]; then
  if [[ ! -x "$PATHSEQ_T2T_BIN" ]]; then
    echo "ERROR: PathSeq-T2T launcher is not executable: $PATHSEQ_T2T_BIN" >&2
    exit 1
  fi
elif ! command -v "$PATHSEQ_T2T_BIN" >/dev/null 2>&1; then
  echo "ERROR: PathSeq-T2T launcher not found on PATH: $PATHSEQ_T2T_BIN" >&2
  exit 1
fi

"$PATHSEQ_T2T_BIN" summarize \
  --sample-id "$sample_id" \
  --outdir "$outdir" \
  --results-dir "$outdir/results" \
  -v
