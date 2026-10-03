cmd_prefilter() {
  local decoys_bed=""
  local unaligned_out="" decoys_out="" flagstat_out=""
  local sample_id=""
  local threads=1
  local dont_overwrite=0

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --input-bam)      input_bam="${2:-}"; shift 2 ;;
      --aligner)        aligner="${2:-}"; shift 2 ;;
      --decoys-to-mask) decoys_to_mask="${2:-}"; shift 2 ;;
      --sample-id)      sample_id="${2:-}"; shift 2 ;;
      --outdir)         OUTDIR="${2:?--outdir requires a directory path}"; shift 2; _set_outdirs ;;
      --unaligned-out)  unaligned_out="${2:-}"; shift 2 ;;
      --decoys-out)     decoys_out="${2:-}"; shift 2 ;;
      --flagstat-out)   flagstat_out="${2:-}"; shift 2 ;;
      --threads)        threads="${2:-}"; shift 2 ;;
      --dont-overwrite) dont_overwrite=1; shift ;;
      -h|--help)
        cat <<'HLP'
Usage: pathseq-t2t prefilter \
  --input-bam <bam> \
  --aligner [dragen|bwa] \
  --decoys-to-mask [<bed>|"None"] \
  [--sample-id <string>] \
  [--outdir <dir>] \
  [--unaligned-out <bam>] \
  [--decoys-out <bam>] \
  [--flagstat-out <tsv>] \
  [--threads <int>] \
  [--dont-overwrite]
HLP
        return 0 ;;
      --) shift; break ;;
      -*) die "Unknown option for prefilter: $1" ;;
      *)  die "Unexpected argument to prefilter: $1" ;;
    esac
  done

  require_nonempty "${input_bam}" "--input-bam"
  require_nonempty "${aligner}" "--aligner"
  require_nonempty "${decoys_to_mask}" "--decoys-to-mask"
  require_file "${input_bam}"
  _require_samtools_116
  bam_check_or_die "${input_bam}" || die "prefilter: input BAM failed checks: ${input_bam}"

  if [[ -z "${threads}" ]]; then
    if command -v nproc >/dev/null 2>&1; then
      threads="$(nproc)"
    elif [[ "${OSTYPE}" == darwin* ]] && command -v sysctl >/dev/null 2>&1; then
      threads="$(sysctl -n hw.ncpu)"
    else
      threads=8
    fi
  fi

  local -a L_ARG=()
  if [[ "${decoys_to_mask,,}" == "none" ]]; then
    decoys_to_mask=""
  else
    require_file "${decoys_to_mask}"
    if command -v readlink >/dev/null 2>&1; then
      local abs_rl
      abs_rl="$(readlink -f "${decoys_to_mask}" 2>/dev/null || true)"
      [[ -n "${abs_rl}" ]] && decoys_to_mask="${abs_rl}"
    fi
    L_ARG=(-L "${decoys_to_mask}")
    local miss
    miss=$(
      comm -23 \
        <(awk 'NF&&$1!~/^#/{print $1}' "${decoys_to_mask}" | sort -u) \
        <(samtools view -H "${input_bam}" | awk -F'\t' '$1=="@SQ"{for(i=1;i<=NF;i++) if($i~/^SN:/){print substr($i,4)}}' | sort -u)
    )
    [[ -z "${miss}" ]] || echo "[prefilter] WARNING: BED chrom(s) not in BAM header: ${miss}" >&2
  fi

  if declare -F _set_outdirs >/dev/null; then
    _set_outdirs
  else
    OUTDIR_BAMS="${OUTDIR}/bams"
    OUTDIR_FILTER="${OUTDIR}/filter_stats"
  fi
  mkdir -p "${OUTDIR_FILTER}" "${OUTDIR_BAMS}"

  if [[ -n "${sample_id}" ]]; then
    [[ -n "${unaligned_out}" ]] || unaligned_out="${OUTDIR_BAMS}/${sample_id}.prefilter.unaligned.bam"
    [[ -n "${decoys_out}" ]] || decoys_out="${OUTDIR_BAMS}/${sample_id}.prefilter.decoys.bam"
    [[ -n "${flagstat_out}" ]] || flagstat_out="${OUTDIR_FILTER}/${sample_id}.flagstat.tsv"
  else
    require_nonempty "${unaligned_out}" "--unaligned-out (required when --sample-id is not provided)"
    require_nonempty "${decoys_out}" "--decoys-out (required when --sample-id is not provided)"
    require_nonempty "${flagstat_out}" "--flagstat-out (required when --sample-id is not provided)"
  fi

  ensure_parent_dir "${unaligned_out}"
  ensure_parent_dir "${decoys_out}"
  ensure_parent_dir "${flagstat_out}"

  if (( dont_overwrite )); then
    local ok_u=0 ok_d=0 ok_f=0
    [[ -s "${unaligned_out}" ]] && samtools quickcheck "${unaligned_out}" >/dev/null 2>&1 && ok_u=1
    [[ -s "${decoys_out}" ]] && samtools quickcheck "${decoys_out}" >/dev/null 2>&1 && ok_d=1
    [[ -s "${flagstat_out}" ]] && ok_f=1
    if (( ok_u && ok_d && ok_f )); then
      log "prefilter --dont-overwrite: outputs already present and valid -> skipping"
      return 0
    fi
    rm -f "${unaligned_out}" "${decoys_out}" "${flagstat_out}"
  fi

  log "prefilter aligner=${aligner} threads=${threads}"
  log "  input_bam: ${input_bam}"
  log "  outputs: unaligned_seqs=${unaligned_out} decoy_seqs=${decoys_out}"
  log "  flagstat: ${flagstat_out}"
  log "  decoys_to_mask: ${decoys_to_mask:-<None>}"

  local rejected_tmp="${unaligned_out}.rejected.tmp.bam"
  local selected_tmp="${decoys_out}.selected.tmp.bam"
  local unaligned_tmp="${unaligned_out}.tmp.bam"
  local decoys_tmp="${decoys_out}.tmp.bam"
  local flagstat_tmp="${flagstat_out}.tmp"

  (
    set -euo pipefail
    trap 'rm -f "${rejected_tmp}" "${selected_tmp}" "${unaligned_tmp}" "${decoys_tmp}" "${flagstat_tmp}"' EXIT

    samtools flagstat --output-fmt tsv -@ "${threads}" \
      "${input_bam}" > "${flagstat_tmp}"

    case "${aligner}" in
      dragen|DRAGEN)
        samtools view -@ "${threads}" -bh -f 3 \
          -U "${rejected_tmp}" -o "${selected_tmp}" "${input_bam}"
        ;;
      bwa|BWA)
        samtools view -@ "${threads}" -bh -f 3 -e '[AS]>35' \
          -U "${rejected_tmp}" -o "${selected_tmp}" "${input_bam}"
        ;;
      *) die "Invalid --aligner '${aligner}'. Use 'dragen' or 'bwa'." ;;
    esac

    samtools view -@ "${threads}" -bh -F 2048 -x SA -x OQ -x MD \
      -o "${unaligned_tmp}" "${rejected_tmp}"
    samtools view -@ "${threads}" -bh -F 2048 -x SA -x OQ -x MD \
      "${L_ARG[@]}" -o "${decoys_tmp}" "${selected_tmp}"

    bam_check_or_die "${unaligned_tmp}" "prefilter: unaligned_out"
    bam_check_or_die "${decoys_tmp}" "prefilter: decoys_out"
    [[ -s "${flagstat_tmp}" ]] || die "Flagstat TSV is empty: ${flagstat_tmp}"

    mv -f "${unaligned_tmp}" "${unaligned_out}"
    mv -f "${decoys_tmp}" "${decoys_out}"
    mv -f "${flagstat_tmp}" "${flagstat_out}"
    rm -f "${rejected_tmp}" "${selected_tmp}"
    trap - EXIT
  )

  log "prefilter done -> unaligned: ${unaligned_out}, decoys: ${decoys_out}, flagstat: ${flagstat_out}"
}
