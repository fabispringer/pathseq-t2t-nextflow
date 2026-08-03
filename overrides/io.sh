#!/usr/bin/env bash

# Shared command execution and BAM validation helpers.
# quickcheck validates the BAM framing; a full read catches corrupt internal
# BGZF blocks that can remain hidden behind a valid terminal EOF marker.
bam_check_or_die() {
  local bam="$1"
  local label="${2:-}"
  [[ -f "${bam}" ]] || die "Expected BAM missing: ${bam}${label:+ (${label})}"

  if ! samtools quickcheck -v "${bam}"; then
    die "samtools quickcheck failed: ${bam}${label:+ (${label})}"
  fi
  if ! samtools view -c "${bam}" >/dev/null; then
    die "Failed to fully read BAM (samtools view -c): ${bam}${label:+ (${label})}"
  fi
  log "BAM OK: ${bam}${label:+ (${label})}"
}

ubam_check_or_die() {
  local bam="$1"
  local label="${2:-}"
  [[ -f "${bam}" ]] || die "Expected BAM missing: ${bam}${label:+ (${label})}"

  if ! samtools quickcheck -u -v "${bam}"; then
    die "samtools quickcheck -u failed: ${bam}${label:+ (${label})}"
  fi
  if ! samtools view -c "${bam}" >/dev/null; then
    die "Failed to fully read BAM (samtools view -c): ${bam}${label:+ (${label})}"
  fi
  log "BAM OK: ${bam}${label:+ (${label})}"
}

# Log the exact command (with variables expanded) before executing it.
log_cmd() {
  local rc
  { printf '[CMD] '; printf '%q ' "$@"; printf '\n'; } >&2
  "$@"; rc=$?
  return "${rc}"
}
