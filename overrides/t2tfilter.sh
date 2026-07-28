cmd_t2tfilter() {
  local input_paired="" input_unpaired="" reference=""
  local decoys_to_mask=""
  local output_paired="" output_unpaired=""
  local flagstat_unaligned_paired=""
  local flagstat_unaligned_unpaired=""
  local threads=""
  local sample_id=""
  local dont_overwrite=0
  local keep_intermediate=0
  local PICARD_JAR="${PICARD_JAR:-}"

  : "${OUTDIR:=./pst2t_out}"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --outdir) OUTDIR="${2:?--outdir requires a directory path}"; shift 2; _set_outdirs ;;
      --dont-overwrite) dont_overwrite=1; shift ;;
      --input-paired) input_paired="${2:-}"; shift 2 ;;
      --input-unpaired) input_unpaired="${2:-}"; shift 2 ;;
      --reference) reference="${2:-}"; shift 2 ;;
      --decoys-to-mask) decoys_to_mask="${2:-}"; shift 2 ;;
      --output-paired) output_paired="${2:-}"; shift 2 ;;
      --output-unpaired) output_unpaired="${2:-}"; shift 2 ;;
      --flagstat-unaln-paired) flagstat_unaligned_paired="${2:-}"; shift 2 ;;
      --flagstat-unaln-unpaired) flagstat_unaligned_unpaired="${2:-}"; shift 2 ;;
      --threads) threads="${2:-}"; shift 2 ;;
      --sample-id) sample_id="${2:-}"; shift 2 ;;
      --keep-intermediate) keep_intermediate=1; shift ;;
      --picard-jar) PICARD_JAR="${2:-}"; shift 2 ;;
      -h|--help)
        cat <<'HLP'
Usage: pathseq-t2t t2tfilter [ARGS]

Core options:
  [--outdir <dir>] Root output directory (default: ./pst2t_out)
  [--sample-id <string>] Sample ID to use for naming inputs/outputs if needed
  [--input-paired <bam>] QC-filtered paired BAM from qcfilter
  [--input-unpaired <bam>] QC-filtered unpaired BAM from qcfilter
  [--reference <t2t.fa>] T2T reference FASTA, or set $T2TREF
  [--decoys-to-mask <bed|None>] BED of decoy/blacklist regions to retain
  [--output-paired <bam>] Output paired BAM for reads not removed by T2T filtering
  [--output-unpaired <bam>] Output unpaired BAM for reads not removed by T2T filtering
  [--flagstat-unaln-paired <tsv>] Flagstat TSV for paired output
  [--flagstat-unaln-unpaired <tsv>] Flagstat TSV for unpaired output

Performance / environment:
  [--threads <int>] CPU threads (default: auto-detect)
  [--picard-jar </path/picard.jar>] Use a Picard jar instead of picard on PATH
  [--dont-overwrite] Skip step if final outputs already exist
  [--keep-intermediate] Keep intermediate FASTQs and aligned BAMs

Notes:
- Inputs default to <outdir>/bams/<ID>.qcfilt_paired.bam and
  <outdir>/bams/<ID>.qcfilt_unpaired.bam when --sample-id is provided.
- If --decoys-to-mask is provided and not "None", decoy-overlapping reads are
  merged into the final outputs.
- Requires samtools >=1.16, Java 17, bwa, Picard, and a T2T reference.
HLP
        return 0
        ;;
      --) shift; break ;;
      -*) die "Unknown option for t2tfilter: $1" ;;
      *) die "Unexpected argument to t2tfilter: $1" ;;
    esac
  done

  _require_samtools_116
  _require_java17
  _require_picard
  _require_bwa
  _require_t2tref "${reference:-}"

  if [[ -z "${reference}" ]]; then
    if [[ -n "${T2TREF:-}" ]]; then
      reference="${T2TREF}"
      log "Using reference from T2TREF: ${reference}"
    else
      die "No reference provided. Use --reference <t2t.fa> or set T2TREF."
    fi
  fi
  require_file "${reference}"

  local -a L_ARG=()
  if [[ -n "${decoys_to_mask}" ]]; then
    if [[ "${decoys_to_mask,,}" == "none" ]]; then
      decoys_to_mask=""
      L_ARG=()
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
          <(awk '/^>/{h=$0; sub(/^>/,"",h); sub(/[[:space:]].*$/,"",h); print h}' "${reference}" | sort -u)
      )
      [[ -z "${miss}" ]] || echo "[t2tfilter] WARNING: BED chrom(s) not in reference FASTA headers: ${miss}" >&2
    fi
  fi

  if declare -F _set_outdirs >/dev/null; then
    _set_outdirs
  else
    OUTDIR_BAMS="${OUTDIR}/bams"
    OUTDIR_FILTER="${OUTDIR}/filter_stats"
  fi
  mkdir -p "${OUTDIR_BAMS}" "${OUTDIR_FILTER}"

  local sample_base=""
  if [[ -n "${sample_id}" ]]; then
    sample_base="${sample_id}"
    [[ -n "${input_paired}" ]] || input_paired="${OUTDIR_BAMS}/${sample_base}.qcfilt_paired.bam"
    [[ -n "${input_unpaired}" ]] || input_unpaired="${OUTDIR_BAMS}/${sample_base}.qcfilt_unpaired.bam"
    [[ -n "${output_paired}" ]] || output_paired="${OUTDIR_BAMS}/${sample_base}.t2tfilt_paired.bam"
    [[ -n "${output_unpaired}" ]] || output_unpaired="${OUTDIR_BAMS}/${sample_base}.t2tfilt_unpaired.bam"
    [[ -n "${flagstat_unaligned_paired}" ]] || flagstat_unaligned_paired="${OUTDIR_FILTER}/${sample_base}.qcfilt_paired.t2t_unaln.flagstat.tsv"
    [[ -n "${flagstat_unaligned_unpaired}" ]] || flagstat_unaligned_unpaired="${OUTDIR_FILTER}/${sample_base}.qcfilt_unpaired.t2t_unaln.flagstat.tsv"
  else
    require_nonempty "${input_paired}" "--input-paired (required when --sample-id is not provided)"
    require_nonempty "${input_unpaired}" "--input-unpaired (required when --sample-id is not provided)"
    require_nonempty "${output_paired}" "--output-paired (required when --sample-id is not provided)"
    require_nonempty "${output_unpaired}" "--output-unpaired (required when --sample-id is not provided)"
    require_nonempty "${flagstat_unaligned_paired}" "--flagstat-unaln-paired (required when --sample-id is not provided)"
    require_nonempty "${flagstat_unaligned_unpaired}" "--flagstat-unaln-unpaired (required when --sample-id is not provided)"
    sample_base="$(basename "${output_paired%.bam}")"
  fi

  require_file "${input_paired}"
  require_file "${input_unpaired}"
  ubam_check_or_die "${input_paired}" "t2tfilter: input_paired"
  ubam_check_or_die "${input_unpaired}" "t2tfilter: input_unpaired"
  local paired_input_records unpaired_input_records
  paired_input_records="$(samtools view -c "${input_paired}")"
  unpaired_input_records="$(samtools view -c "${input_unpaired}")"
  log "Input records: paired=${paired_input_records}; unpaired=${unpaired_input_records}"

  if [[ -z "${threads}" ]]; then
    if command -v nproc >/dev/null 2>&1; then
      threads="$(nproc)"
    elif [[ "${OSTYPE}" == "darwin"* ]] && command -v sysctl >/dev/null 2>&1; then
      threads="$(sysctl -n hw.ncpu)"
    else
      threads="8"
    fi
  fi

  ensure_parent_dir "${output_paired}"
  ensure_parent_dir "${output_unpaired}"
  ensure_parent_dir "${flagstat_unaligned_paired}"
  ensure_parent_dir "${flagstat_unaligned_unpaired}"

  local base_paired base_unpaired
  if [[ -n "${sample_id}" ]]; then
    base_paired="${sample_id}.qcfilt_paired"
    base_unpaired="${sample_id}.qcfilt_unpaired"
  else
    base_paired="${sample_base}.qcfilt_paired"
    base_unpaired="${sample_base}.qcfilt_unpaired"
  fi

  local fastq_r1="${OUTDIR_BAMS}/${base_paired}.R1.fq.gz"
  local fastq_r2="${OUTDIR_BAMS}/${base_paired}.R2.fq.gz"
  local fastq_u="${OUTDIR_BAMS}/${base_unpaired}.U.fq.gz"

  local bam_aligned_paired="${OUTDIR_BAMS}/${base_paired}.t2t_aln.bam"
  local bam_aligned_unpaired="${OUTDIR_BAMS}/${base_unpaired}.t2t_aln.bam"
  local bam_decoys_paired="${OUTDIR_BAMS}/${base_paired}.t2t_decoys.bam"
  local bam_decoys_unpaired="${OUTDIR_BAMS}/${base_unpaired}.t2t_decoys.bam"
  local bam_unaligned_raw_paired="${OUTDIR_BAMS}/${base_paired}.t2t_unaligned.raw.bam"
  local bam_unaligned_raw_unpaired="${OUTDIR_BAMS}/${base_unpaired}.t2t_unaligned.raw.bam"
  local tmp_output_paired="${output_paired}.tmp.candidate.bam"
  local tmp_output_unpaired="${output_unpaired}.tmp.candidate.bam"
  local tmp_merge_paired="${output_paired}.tmp.merge.bam"
  local tmp_merge_unpaired="${output_unpaired}.tmp.merge.bam"

  if [[ ${dont_overwrite} -eq 1 && -f "${output_paired}" && -f "${output_unpaired}" ]]; then
    log "t2tfilter (--dont-overwrite): final outputs exist; skipping."
    return 0
  fi

  log "t2tfilter threads=${threads} sample=${sample_base}"
  log " decoys_to_mask: ${decoys_to_mask:-<None>}"

  if [[ "${paired_input_records}" -gt 0 && ( ! -f "${fastq_r1}" || ! -f "${fastq_r2}" ) ]]; then
    log "Converting paired QC-filtered BAM to FASTQ"
    if [[ -n "${PICARD_JAR}" ]]; then
      java -jar "${PICARD_JAR}" SamToFastq \
        --INPUT "${input_paired}" \
        --FASTQ "${fastq_r1}" \
        --SECOND_END_FASTQ "${fastq_r2}" \
        --VALIDATION_STRINGENCY LENIENT
    else
      picard SamToFastq \
        --INPUT "${input_paired}" \
        --FASTQ "${fastq_r1}" \
        --SECOND_END_FASTQ "${fastq_r2}" \
        --VALIDATION_STRINGENCY LENIENT
    fi
  fi

  if [[ "${unpaired_input_records}" -gt 0 && ! -f "${fastq_u}" ]]; then
    log "Converting unpaired QC-filtered BAM to FASTQ"
    if [[ -n "${PICARD_JAR}" ]]; then
      java -jar "${PICARD_JAR}" SamToFastq \
        --INPUT "${input_unpaired}" \
        --FASTQ "${fastq_u}" \
        --VALIDATION_STRINGENCY SILENT
    else
      picard SamToFastq \
        --INPUT "${input_unpaired}" \
        --FASTQ "${fastq_u}" \
        --VALIDATION_STRINGENCY SILENT
    fi
  fi

  if [[ "${paired_input_records}" -eq 0 ]]; then
    log "No paired reads entered t2tfilter; creating a header-only paired output BAM"
    samtools view -H "${input_paired}" |
      samtools view -b -o "${tmp_output_paired}" -
    ubam_check_or_die "${tmp_output_paired}" "t2tfilter: empty paired candidate"
    mv -f "${tmp_output_paired}" "${output_paired}"
  else
    if [[ ! -f "${bam_aligned_paired}" || ${dont_overwrite} -eq 0 ]]; then
      log "Aligning paired reads to T2T"
      bwa mem -t "${threads}" -T 0 "${reference}" "${fastq_r1}" "${fastq_r2}" \
        | samtools view -@ "${threads}" -S -h -b -o "${bam_aligned_paired}" -
      [[ -f "${bam_aligned_paired}" ]] || die "Failed to create aligned paired BAM."
    fi

    # Reads that do not align well to T2T continue to microbial classification.
    # If a decoy BED is configured, decoy-overlapping reads are rescued and merged
    # back into the final BAM after the primary T2T-unmapped extraction.
    if [[ ! -f "${output_paired}" || ${dont_overwrite} -eq 0 ]]; then
      log "[ Extracting paired unaligned reads ]"
      time samtools view -@ "${threads}" -b -h -f 3 -e '[AS]>35' \
        -U "${bam_unaligned_raw_paired}" \
        -o /dev/null \
        "${bam_aligned_paired}"
      time samtools view -@ "${threads}" -b -h -F 2048 -x SA -x OQ -x MD \
        -o "${tmp_output_paired}" \
        "${bam_unaligned_raw_paired}"
      bam_check_or_die "${tmp_output_paired}" "t2tfilter: paired candidate"

      if [[ -n "${decoys_to_mask}" ]]; then
        log "[ Extracting paired decoy-overlap reads for merge ]"
        time samtools view -@ "${threads}" -b -h -f 3 -e '[AS]>35' "${L_ARG[@]}" \
          "${bam_aligned_paired}" \
          | samtools view -@ "${threads}" -b -h -F 2048 -x SA -x OQ -x MD -o "${bam_decoys_paired}" -

        local paired_decoy_records
        paired_decoy_records="$(samtools view -c "${bam_decoys_paired}")"
        if [[ "${paired_decoy_records}" -gt 0 ]]; then
          log "[ Merging paired decoy-overlap reads into output ]"
          time samtools cat -o "${tmp_merge_paired}" "${tmp_output_paired}" "${bam_decoys_paired}"
          bam_check_or_die "${tmp_merge_paired}" "t2tfilter: merged paired candidate"
          mv -f "${tmp_merge_paired}" "${output_paired}"
        else
          mv -f "${tmp_output_paired}" "${output_paired}"
        fi
      else
        mv -f "${tmp_output_paired}" "${output_paired}"
      fi
    fi
  fi

  if [[ "${unpaired_input_records}" -eq 0 ]]; then
    log "No unpaired reads entered t2tfilter; creating a header-only unpaired output BAM"
    samtools view -H "${input_unpaired}" |
      samtools view -b -o "${tmp_output_unpaired}" -
    ubam_check_or_die "${tmp_output_unpaired}" "t2tfilter: empty unpaired candidate"
    mv -f "${tmp_output_unpaired}" "${output_unpaired}"
  else
    if [[ ! -f "${bam_aligned_unpaired}" || ${dont_overwrite} -eq 0 ]]; then
      log "[ Aligning unpaired reads to T2T ]"
      bwa mem -t "${threads}" -T 0 "${reference}" "${fastq_u}" \
        | samtools view -@ "${threads}" -S -h -b -o "${bam_aligned_unpaired}" -
      [[ -f "${bam_aligned_unpaired}" ]] || die "Failed to create aligned unpaired BAM."
    fi

    if [[ ! -f "${output_unpaired}" || ${dont_overwrite} -eq 0 ]]; then
      log "[ Extracting unpaired unaligned reads ]"
      time samtools view -@ "${threads}" -b -h -e '[AS]>35' \
        -U "${bam_unaligned_raw_unpaired}" \
        -o /dev/null \
        "${bam_aligned_unpaired}"
      time samtools view -@ "${threads}" -b -h -F 2048 -x SA -x OQ -x MD \
        -o "${tmp_output_unpaired}" \
        "${bam_unaligned_raw_unpaired}"
      bam_check_or_die "${tmp_output_unpaired}" "t2tfilter: unpaired candidate"

      if [[ -n "${decoys_to_mask}" ]]; then
        log "[ Extracting unpaired decoy-overlap reads for merge ]"
        time samtools view -@ "${threads}" -b -h -e '[AS]>35' "${L_ARG[@]}" \
          "${bam_aligned_unpaired}" \
          | samtools view -@ "${threads}" -b -h -F 2048 -x SA -x OQ -x MD -o "${bam_decoys_unpaired}" -

        local unpaired_decoy_records
        unpaired_decoy_records="$(samtools view -c "${bam_decoys_unpaired}")"
        if [[ "${unpaired_decoy_records}" -gt 0 ]]; then
          log "[ Merging unpaired decoy-overlap reads into output ]"
          time samtools cat -o "${tmp_merge_unpaired}" "${tmp_output_unpaired}" "${bam_decoys_unpaired}"
          bam_check_or_die "${tmp_merge_unpaired}" "t2tfilter: merged unpaired candidate"
          mv -f "${tmp_merge_unpaired}" "${output_unpaired}"
        else
          mv -f "${tmp_output_unpaired}" "${output_unpaired}"
        fi
      else
        mv -f "${tmp_output_unpaired}" "${output_unpaired}"
      fi
    fi
  fi

  samtools flagstat --output-fmt tsv "${output_paired}" > "${flagstat_unaligned_paired}"
  samtools flagstat --output-fmt tsv "${output_unpaired}" > "${flagstat_unaligned_unpaired}"

  if [[ "${paired_input_records}" -eq 0 ]]; then
    ubam_check_or_die "${output_paired}" "t2tfilter: empty final paired"
  else
    bam_check_or_die "${output_paired}" "t2tfilter: final paired"
  fi
  if [[ "${unpaired_input_records}" -eq 0 ]]; then
    ubam_check_or_die "${output_unpaired}" "t2tfilter: empty final unpaired"
  else
    bam_check_or_die "${output_unpaired}" "t2tfilter: final unpaired"
  fi

  if [[ ${keep_intermediate} -eq 0 ]]; then
    log "Removing intermediate FASTQs and aligned BAMs (use --keep-intermediate to retain):"
    for f in \
      "${fastq_r1}" "${fastq_r2}" "${fastq_u}" \
      "${bam_aligned_paired}" "${bam_aligned_unpaired}" \
      "${bam_decoys_paired}" "${bam_decoys_unpaired}" \
      "${bam_unaligned_raw_paired}" "${bam_unaligned_raw_unpaired}" \
      "${tmp_output_paired}" "${tmp_output_unpaired}" \
      "${tmp_merge_paired}" "${tmp_merge_unpaired}"
    do
      [[ -e "$f" ]] && rm -f "$f"
    done
  fi

  log "t2tfilter done: paired output=${output_paired}; unpaired output=${output_unpaired}"
}
