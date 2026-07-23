nextflow.enable.dsl = 2

def requireParam(value, name) {
  if (value == null || value.toString().trim() == '') {
    throw new IllegalArgumentException("Missing required parameter: ${name}")
  }
  return value
}

def optionalArgsFromMap(Map values) {
  values
    .findAll { key, value -> value != null && value.toString().trim() != '' }
    .collect { key, value -> "--${key} '${value}'" }
    .join(' ')
}

def normalizedNames(value) {
  if (value instanceof Collection) {
    return value
      .collect { it.toString().trim().toLowerCase() }
      .findAll { it }
  }
  return value
    .toString()
    .toLowerCase()
    .split(/[,\s]+/)
    .collect { it.trim() }
    .findAll { it }
}

process STAGE_FASTQ_INPUT {
  tag "$sample_id"
  label 'stage'

  input:
  tuple val(sample_id), val(source_reads)

  output:
  tuple val(sample_id), path("pipeline_input/${sample_id}_{R1,R2}.fastq.gz"), emit: reads

  script:
  def r1 = source_reads[0]
  def r2 = source_reads[1]
  def stageCommand = params.remote_input_dir ? 'cp -L' : 'ln -s'
  """
  set -euo pipefail
  mkdir -p pipeline_input
  ${stageCommand} -- '${r1}' pipeline_input/${sample_id}_R1.fastq.gz
  ${stageCommand} -- '${r2}' pipeline_input/${sample_id}_R2.fastq.gz
  """
}

process STAGE_BAM_INPUT {
  tag "$sample_id"
  label 'stage'

  input:
  tuple val(sample_id), val(source_bam)

  output:
  tuple val(sample_id), path("pipeline_input/${sample_id}.bam"), emit: bam

  script:
  def stageCommand = params.remote_input_dir ? 'cp -L' : 'ln -s'
  """
  set -euo pipefail
  mkdir -p pipeline_input
  ${stageCommand} -- '${source_bam}' pipeline_input/${sample_id}.bam
  """
}

process BAM_TO_FASTQ {
  tag "$sample_id"
  label 'bam2fastq'

  publishDir "${params.outdir}/pipeline_info/input_audit", mode: 'copy', pattern: '*.bam2fastq.stats.tsv'

  input:
  tuple val(sample_id), path(input_bam)

  output:
  tuple val(sample_id), path("${sample_id}_{R1,R2,unpaired}.fastq.gz"), emit: reads
  path "${sample_id}.bam2fastq.stats.tsv", emit: stats

  script:
  def originalQualities = params.bam2fastq.prefer_original_qualities ? '-O' : ''
  """
  set -euo pipefail

  samtools quickcheck -v ${input_bam}
  mkdir -p tmp
  collate_threads=\$(( ${task.cpus} / 2 ))
  [[ "\$collate_threads" -ge 1 ]] || collate_threads=1
  fastq_threads=\$(( ${task.cpus} - collate_threads ))
  [[ "\$fastq_threads" -ge 1 ]] || fastq_threads=1
  samtools collate -u -O -@ "\$collate_threads" -T "tmp/${sample_id}" ${input_bam} \\
    | samtools fastq -@ "\$fastq_threads" -n -F 0x900 ${originalQualities} \\
        -1 ${sample_id}_R1.fastq.gz \\
        -2 ${sample_id}_R2.fastq.gz \\
        -0 ${sample_id}_category0.fastq.gz \\
        -s ${sample_id}_singleton.fastq.gz \\
        -
  cat ${sample_id}_category0.fastq.gz ${sample_id}_singleton.fastq.gz \\
    > ${sample_id}_unpaired.fastq.gz
  rm -f ${sample_id}_category0.fastq.gz ${sample_id}_singleton.fastq.gz

  total_records="\$(samtools view -c ${input_bam})"
  primary_records="\$(samtools view -c -F 0x900 ${input_bam})"
  secondary_records="\$(samtools view -c -f 0x100 ${input_bam})"
  supplementary_records="\$(samtools view -c -f 0x800 ${input_bam})"
  r1_reads="\$(gzip -cd ${sample_id}_R1.fastq.gz | awk 'END { print NR / 4 }')"
  r2_reads="\$(gzip -cd ${sample_id}_R2.fastq.gz | awk 'END { print NR / 4 }')"
  unpaired_reads="\$(gzip -cd ${sample_id}_unpaired.fastq.gz | awk 'END { print NR / 4 }')"
  output_reads="\$((r1_reads + r2_reads + unpaired_reads))"

  [[ "\$r1_reads" -eq "\$r2_reads" ]] || {
    echo "ERROR: R1/R2 counts differ for ${sample_id}: \$r1_reads vs \$r2_reads" >&2
    exit 1
  }
  [[ "\$output_reads" -eq "\$primary_records" ]] || {
    echo "ERROR: FASTQ output count (\$output_reads) != primary BAM records (\$primary_records) for ${sample_id}" >&2
    exit 1
  }

  printf 'metric\tvalue\n' > ${sample_id}.bam2fastq.stats.tsv
  printf 'bam_total_records\t%s\n' "\$total_records" >> ${sample_id}.bam2fastq.stats.tsv
  printf 'bam_primary_records\t%s\n' "\$primary_records" >> ${sample_id}.bam2fastq.stats.tsv
  printf 'bam_secondary_records\t%s\n' "\$secondary_records" >> ${sample_id}.bam2fastq.stats.tsv
  printf 'bam_supplementary_records\t%s\n' "\$supplementary_records" >> ${sample_id}.bam2fastq.stats.tsv
  printf 'fastq_r1_reads\t%s\n' "\$r1_reads" >> ${sample_id}.bam2fastq.stats.tsv
  printf 'fastq_r2_reads\t%s\n' "\$r2_reads" >> ${sample_id}.bam2fastq.stats.tsv
  printf 'fastq_unpaired_reads\t%s\n' "\$unpaired_reads" >> ${sample_id}.bam2fastq.stats.tsv
  printf 'validation\tPASS\n' >> ${sample_id}.bam2fastq.stats.tsv
  """
}

process FASTQC_RAW {
  tag "$sample_id"
  label 'fastqc'

  publishDir params.outdir, mode: 'copy', saveAs: { name -> "samples/${sample_id}/read_qc/${name}" }

  input:
  tuple val(sample_id), path(reads)

  output:
  tuple val(sample_id), path("raw_fastqc"), emit: reports
  path "${sample_id}.raw_fastqc_counts.tsv", emit: counts

  script:
  def inputReads = reads.join(' ')
  def countRows = reads.withIndex().collect { read, index ->
    def label = index == 0 ? 'r1_reads' : index == 1 ? 'r2_reads' : 'unpaired_reads'
    def stem = read.name.replaceFirst(/(?i)\.(fastq|fq)(\.gz)?$/, '')
    "printf '${label}\\t%s\\n' \"\$(awk -F '\\t' '\$1 == \"Total Sequences\" { print \$2; exit }' raw_fastqc/${stem}_fastqc/fastqc_data.txt)\" >> ${sample_id}.raw_fastqc_counts.tsv"
  }.join('\n')
  """
  set -euo pipefail

  mkdir -p raw_fastqc
  fastqc \\
    --threads ${task.cpus} \\
    --extract \\
    --outdir raw_fastqc \\
    ${inputReads}

  printf 'metric\tvalue\n' > ${sample_id}.raw_fastqc_counts.tsv
  ${countRows}
  """
}

process BBDUK {
  tag "$sample_id"
  label 'read_qc'

  publishDir params.outdir, mode: 'copy', pattern: '*.bbduk_stats.txt', saveAs: { name -> "samples/${sample_id}/read_qc/${name}" }

  input:
  tuple val(sample_id), path(reads)
  path adapters

  output:
  tuple val(sample_id), path("${sample_id}.qc_{R1,R2,unpaired}.fastq.gz"), emit: reads
  path "${sample_id}.bbduk_stats.txt", emit: stats

  script:
  def r1 = reads[0]
  def r2 = reads[1]
  def unpaired = reads.size() > 2 ? reads[2] : null
  def addUnpaired = unpaired ? "gzip -cd ${unpaired} >> tmp_unpaired.fq" : ':'
  """
  set -euo pipefail

  bbduk.sh \\
    -Xmx${task.memory.toGiga()}g \\
    t=${task.cpus} \\
    ordered=t \\
    trd=t \\
    ${params.qc.bbduk_params} \\
    ref=${adapters} \\
    minlen=${params.qc.min_length} \\
    in1=${r1} \\
    in2=${r2} \\
    out1=${sample_id}.qc_R1.fastq.gz \\
    out2=${sample_id}.qc_R2.fastq.gz \\
    outs=tmp_unpaired.fq \\
    stats=${sample_id}.bbduk_stats.txt

  ${addUnpaired}

  if [[ -s tmp_unpaired.fq ]]; then
    bbduk.sh \\
      -Xmx${task.memory.toGiga()}g \\
      t=${task.cpus} \\
      ordered=t \\
      trd=t \\
      ${params.qc.bbduk_params} \\
      ref=${adapters} \\
      minlen=${params.qc.min_length} \\
      in=tmp_unpaired.fq \\
      out=${sample_id}.qc_unpaired.fastq.gz
  else
    gzip -c </dev/null > ${sample_id}.qc_unpaired.fastq.gz
  fi

  rm -f tmp_unpaired.fq
  """
}

process FASTQC_POST {
  tag "$sample_id"
  label 'fastqc'

  publishDir params.outdir, mode: 'copy', saveAs: { name -> "samples/${sample_id}/read_qc/${name}" }

  input:
  tuple val(sample_id), path(reads)

  output:
  tuple val(sample_id), path("post_qc_fastqc"), emit: reports
  path "${sample_id}.post_fastqc_counts.tsv", emit: counts

  script:
  def inputReads = reads.join(' ')
  def countRows = reads.withIndex().collect { read, index ->
    def label = index == 0 ? 'r1_reads' : index == 1 ? 'r2_reads' : 'unpaired_reads'
    def stem = read.name.replaceFirst(/(?i)\.(fastq|fq)(\.gz)?$/, '')
    "printf '${label}\\t%s\\n' \"\$(awk -F '\\t' '\$1 == \"Total Sequences\" { print \$2; exit }' post_qc_fastqc/${stem}_fastqc/fastqc_data.txt)\" >> ${sample_id}.post_fastqc_counts.tsv"
  }.join('\n')
  """
  set -euo pipefail

  mkdir -p post_qc_fastqc
  fastqc \\
    --threads ${task.cpus} \\
    --extract \\
    --outdir post_qc_fastqc \\
    ${inputReads}

  printf 'metric\tvalue\n' > ${sample_id}.post_fastqc_counts.tsv
  ${countRows}
  """
}

process ALIGN_BWA {
  tag "$sample_id"
  label 'align'

  publishDir params.outdir, mode: 'copy', pattern: '*.host_alignment.flagstat.tsv', saveAs: { name -> "samples/${sample_id}/host_mapping/${name}" }

  input:
  tuple val(sample_id), path(reads)

  output:
  tuple val(sample_id), path("${sample_id}.bwa.sorted.bam"), emit: bam
  path "${sample_id}.bwa.sorted.bam.bai", emit: bai
  path "${sample_id}.host_alignment.flagstat.tsv", emit: flagstat

  script:
  def r1 = reads[0]
  def r2 = reads[1]
  def unpaired = reads[2]
  """
  set -euo pipefail

  test -s '${params.references.grch38_fasta}'
  for suffix in amb ann bwt pac sa; do
    test -s '${params.references.grch38_fasta}'.\${suffix}
  done

  bwa mem \\
    -t ${task.cpus} \\
    -R '@RG\\tID:${sample_id}\\tSM:${sample_id}\\tPL:${params.read_group_platform}' \\
    '${params.references.grch38_fasta}' \\
    ${r1} \\
    ${r2} \\
    | samtools sort \\
        -@ ${task.cpus} \\
        -o ${sample_id}.paired.sorted.bam \\
        -

  unpaired_bytes="\$(gzip -l ${unpaired} | awk 'NR == 2 { print \$2 }')"
  if [[ "\${unpaired_bytes:-0}" -gt 0 ]]; then
    bwa mem \\
      -t ${task.cpus} \\
      -R '@RG\\tID:${sample_id}\\tSM:${sample_id}\\tPL:${params.read_group_platform}' \\
      '${params.references.grch38_fasta}' \\
      ${unpaired} \\
      | samtools sort -@ ${task.cpus} -o ${sample_id}.unpaired.sorted.bam -
    samtools merge -@ ${task.cpus} -f ${sample_id}.bwa.sorted.bam \\
      ${sample_id}.paired.sorted.bam ${sample_id}.unpaired.sorted.bam
  else
    mv ${sample_id}.paired.sorted.bam ${sample_id}.bwa.sorted.bam
  fi

  samtools index -@ ${task.cpus} ${sample_id}.bwa.sorted.bam
  samtools quickcheck -v ${sample_id}.bwa.sorted.bam
  samtools flagstat --output-fmt tsv ${sample_id}.bwa.sorted.bam > ${sample_id}.host_alignment.flagstat.tsv
  """
}

process ALIGN_STAR {
  tag "$sample_id"
  label 'align'

  publishDir params.outdir, mode: 'copy', pattern: '*.host_alignment.flagstat.tsv', saveAs: { name -> "samples/${sample_id}/host_mapping/${name}" }
  publishDir params.outdir, mode: 'copy', pattern: '*.star.Log.final.out', saveAs: { name -> "samples/${sample_id}/host_mapping/${name}" }
  publishDir params.outdir, mode: 'copy', pattern: '*.star.ReadsPerGene.out.tsv', saveAs: { name -> "samples/${sample_id}/host_mapping/${name}" }

  input:
  tuple val(sample_id), path(reads)

  output:
  tuple val(sample_id), path("${sample_id}.star.sorted.bam"), path("${sample_id}.prefilter.unaligned.bam"), path("${sample_id}.flagstat.tsv"), emit: star_outputs
  path "${sample_id}.star.sorted.bam.bai", emit: bai
  path "star_logs", optional: true, emit: star_logs
  path "${sample_id}.host_alignment.flagstat.tsv", emit: host_flagstat
  path "${sample_id}.star.Log.final.out", emit: final_log
  path "${sample_id}.star.ReadsPerGene.out.tsv", emit: gene_counts

  script:
  def r1 = reads[0]
  def r2 = reads[1]
  def unpaired = reads[2]
  """
  set -euo pipefail

  test -d '${params.references.star_index}'
  test -s '${params.tools.picard_jar}'

  mkdir -p star_tmp star_logs
  prefix="star_tmp/${sample_id}"

  STAR \\
    --runThreadN ${task.cpus} \\
    --genomeDir '${params.references.star_index}' \\
    --readFilesIn ${r1} ${r2} \\
    --readFilesCommand zcat \\
    --outFileNamePrefix "\${prefix}" \\
    --outReadsUnmapped Fastx \\
    --outSAMtype BAM SortedByCoordinate \\
    --quantMode TranscriptomeSAM GeneCounts \\
    --outSAMattrRGline 'ID:${sample_id}' 'SM:${sample_id}' 'PL:${params.read_group_platform}' \\
    --twopassMode Basic

  test -s "\${prefix}Aligned.sortedByCoord.out.bam"
  test -s "\${prefix}Unmapped.out.mate1"
  test -s "\${prefix}Unmapped.out.mate2"

  '${projectDir}/scripts/write_star_primary_flagstat.sh' \\
    --star-log "\${prefix}Log.final.out" \\
    --output "${sample_id}.flagstat.tsv"

  java -jar '${params.tools.picard_jar}' FastqToSam \\
    F1="\${prefix}Unmapped.out.mate1" \\
    F2="\${prefix}Unmapped.out.mate2" \\
    O="${sample_id}.paired.unaligned.bam" \\
    SM="${sample_id}" \\
    RG="${sample_id}" \\
    PL="${params.read_group_platform}" \\
    SORT_ORDER=queryname

  unpaired_bytes="\$(gzip -l ${unpaired} | awk 'NR == 2 { print \$2 }')"
  if [[ "\${unpaired_bytes:-0}" -gt 0 ]]; then
    single_prefix="star_tmp/${sample_id}.single."
    STAR \\
      --runThreadN ${task.cpus} \\
      --genomeDir '${params.references.star_index}' \\
      --readFilesIn ${unpaired} \\
      --readFilesCommand zcat \\
      --outFileNamePrefix "\${single_prefix}" \\
      --outReadsUnmapped Fastx \\
      --outSAMtype BAM SortedByCoordinate \\
      --outSAMattrRGline 'ID:${sample_id}' 'SM:${sample_id}' 'PL:${params.read_group_platform}' \\
      --twopassMode Basic

    java -jar '${params.tools.picard_jar}' FastqToSam \\
      F1="\${single_prefix}Unmapped.out.mate1" \\
      O="${sample_id}.single.unaligned.bam" \\
      SM="${sample_id}" RG="${sample_id}" PL="${params.read_group_platform}" \\
      SORT_ORDER=queryname
    java -jar '${params.tools.picard_jar}' MergeSamFiles \\
      I="${sample_id}.paired.unaligned.bam" \\
      I="${sample_id}.single.unaligned.bam" \\
      O="${sample_id}.prefilter.unaligned.bam" \\
      SORT_ORDER=queryname VALIDATION_STRINGENCY=LENIENT
    samtools merge -@ ${task.cpus} -f ${sample_id}.star.sorted.bam \\
      "\${prefix}Aligned.sortedByCoord.out.bam" \\
      "\${single_prefix}Aligned.sortedByCoord.out.bam"
    '${projectDir}/scripts/write_star_primary_flagstat.sh' \\
      --star-log "\${prefix}Log.final.out" \\
      --single-log "\${single_prefix}Log.final.out" \\
      --output "${sample_id}.flagstat.tsv"
  else
    mv ${sample_id}.paired.unaligned.bam ${sample_id}.prefilter.unaligned.bam
    mv "\${prefix}Aligned.sortedByCoord.out.bam" ${sample_id}.star.sorted.bam
  fi

  samtools view -H ${sample_id}.prefilter.unaligned.bam >/dev/null
  samtools index -@ ${task.cpus} ${sample_id}.star.sorted.bam

  for star_output in \\
    Log.final.out \\
    Log.out \\
    Log.progress.out \\
    SJ.out.tab \\
    ReadsPerGene.out.tab \\
    Aligned.toTranscriptome.out.bam \\
    Unmapped.out.mate1 \\
    Unmapped.out.mate2; do
    if [[ -f "\${prefix}\${star_output}" ]]; then
      mv "\${prefix}\${star_output}" "star_logs/${sample_id}.star.\${star_output}"
    fi
  done

  samtools quickcheck -v ${sample_id}.star.sorted.bam
  samtools flagstat --output-fmt tsv ${sample_id}.star.sorted.bam > ${sample_id}.host_alignment.flagstat.tsv
  cp star_logs/${sample_id}.star.Log.final.out ${sample_id}.star.Log.final.out
  cp star_logs/${sample_id}.star.ReadsPerGene.out.tab ${sample_id}.star.ReadsPerGene.out.tsv
  """
}

process PREPARE_PATHSEQ {
  label 'prepare'
  output:
  path 'pathseq_overrides.ready', emit: ready
  script:
  """
  set -euo pipefail
  test -x '${projectDir}/pathseq-t2t/upstream/src/pathseq-t2t'
  touch pathseq_overrides.ready
  """
}

process PREPARE_KRAKEN_TAXONOMY {
  label 'prepare'

  output:
  path 'kraken_taxonomy.tsv', emit: taxonomy

  script:
  """
  set -euo pipefail
  test -s '${params.references.kraken_index}/taxo.k2d'
  kraken2-inspect --db '${params.references.kraken_index}' > kraken2_inspect.tsv
  python3 '${projectDir}/scripts/prepare_kraken_taxonomy.py' \
    --inspect kraken2_inspect.tsv \
    --output kraken_taxonomy.tsv
  """
}

process PREFILTER_BWA {
  tag "$sample_id"
  label 'prefilter'
  input:
  tuple val(sample_id), path(input_bam)
  path overrides_ready
  output:
  tuple val(sample_id),
    path("bams/${sample_id}.prefilter.unaligned.bam"),
    path("bams/${sample_id}.prefilter.decoys.bam"),
    path("filter_stats/${sample_id}.flagstat.tsv"),
    emit: filtered
  script:
  """
  set -euo pipefail
  mkdir -p bams filter_stats
  '${projectDir}/pathseq-t2t/upstream/src/pathseq-t2t' prefilter \
    --input-bam ${input_bam} \
    --aligner bwa \
    --decoys-to-mask '${params.references.decoys_to_mask}' \
    --sample-id ${sample_id} \
    --outdir "\$PWD" \
    --threads ${task.cpus}
  """
}

process QCFILTER_BWA {
  tag "$sample_id"
  label 'qcfilter'
  input:
  tuple val(sample_id), path(prefilter_unaligned), path(prefilter_decoys), path(input_flagstat)
  output:
  tuple val(sample_id),
    path("bams/${sample_id}.qcfilt_paired.bam"),
    path("bams/${sample_id}.qcfilt_unpaired.bam"),
    path("filter_stats/${sample_id}.flagstat.tsv"),
    path("filter_stats/${sample_id}.prefilter.unaligned.filter_metrics.txt"),
    path("filter_stats/${sample_id}.prefilter.decoys.filter_metrics.txt"),
    emit: filtered
  script:
  def keepIntermediate = params.pathseq.keep_intermediate ? '--keep-intermediate' : ''
  """
  set -euo pipefail
  mkdir -p bams filter_stats tmp
  cp -f ${prefilter_unaligned} bams/${sample_id}.prefilter.unaligned.bam
  cp -f ${prefilter_decoys} bams/${sample_id}.prefilter.decoys.bam
  cp -f ${input_flagstat} filter_stats/${sample_id}.flagstat.tsv
  '${projectDir}/pathseq-t2t/upstream/src/pathseq-t2t' qcfilter \
    --sample-id ${sample_id} \
    --hostdir '${params.references.hostdir}' \
    --outdir "\$PWD" \
    --threads ${task.cpus} \
    --ram-gb ${params.resources.qcfilter_ram_gb} \
    --tmpdir "\$PWD/tmp" \
    --min-clipped-read-length ${params.pathseq.min_clipped_read_length} \
    --picard-jar '${params.tools.picard_jar}' \
    ${keepIntermediate}
  """
}

process QCFILTER_STAR {
  tag "$sample_id"
  label 'qcfilter'
  input:
  tuple val(sample_id), path(star_bam), path(prefilter_unaligned), path(input_flagstat)
  path overrides_ready
  output:
  tuple val(sample_id),
    path("bams/${sample_id}.qcfilt_paired.bam"),
    path("bams/${sample_id}.qcfilt_unpaired.bam"),
    path("filter_stats/${sample_id}.flagstat.tsv"),
    path("filter_stats/${sample_id}.prefilter.unaligned.filter_metrics.txt"),
    path("filter_stats/${sample_id}.prefilter.decoys.filter_metrics.txt"),
    emit: filtered
  script:
  def keepIntermediate = params.pathseq.keep_intermediate ? '--keep-intermediate' : ''
  """
  set -euo pipefail
  mkdir -p bams filter_stats tmp
  cp -f ${prefilter_unaligned} bams/${sample_id}.prefilter.unaligned.bam
  cp -f ${input_flagstat} filter_stats/${sample_id}.flagstat.tsv
  '${projectDir}/pathseq-t2t/upstream/src/pathseq-t2t' qcfilter \
    --sample-id ${sample_id} \
    --hostdir '${params.references.hostdir}' \
    --outdir "\$PWD" \
    --threads ${task.cpus} \
    --ram-gb ${params.resources.qcfilter_ram_gb} \
    --tmpdir "\$PWD/tmp" \
    --min-clipped-read-length ${params.pathseq.min_clipped_read_length} \
    --picard-jar '${params.tools.picard_jar}' \
    ${keepIntermediate}
  touch filter_stats/${sample_id}.prefilter.decoys.filter_metrics.txt
  """
}

process T2TFILTER {
  tag "$sample_id"
  label 't2tfilter'
  input:
  tuple val(sample_id), path(qc_paired), path(qc_unpaired), path(input_flagstat), path(metrics_unaligned), path(metrics_decoys)
  output:
  tuple val(sample_id),
    path("bams/${sample_id}.t2tfilt_paired.bam"),
    path("bams/${sample_id}.t2tfilt_unpaired.bam"),
    path("filter_stats/${sample_id}.flagstat.tsv"),
    path("filter_stats/${sample_id}.prefilter.unaligned.filter_metrics.txt"),
    path("filter_stats/${sample_id}.prefilter.decoys.filter_metrics.txt"),
    path("filter_stats/${sample_id}.qcfilt_paired.t2t_unaln.flagstat.tsv"),
    path("filter_stats/${sample_id}.qcfilt_unpaired.t2t_unaln.flagstat.tsv"),
    emit: filtered
  script:
  def keepIntermediate = params.pathseq.keep_intermediate ? '--keep-intermediate' : ''
  """
  set -euo pipefail
  mkdir -p bams filter_stats
  cp -f ${qc_paired} bams/${sample_id}.qcfilt_paired.bam
  cp -f ${qc_unpaired} bams/${sample_id}.qcfilt_unpaired.bam
  cp -f ${input_flagstat} filter_stats/${sample_id}.flagstat.tsv
  cp -f ${metrics_unaligned} filter_stats/${sample_id}.prefilter.unaligned.filter_metrics.txt
  cp -f ${metrics_decoys} filter_stats/${sample_id}.prefilter.decoys.filter_metrics.txt
  '${projectDir}/pathseq-t2t/upstream/src/pathseq-t2t' t2tfilter \
    --sample-id ${sample_id} \
    --reference '${params.references.t2tref}' \
    --decoys-to-mask '${params.references.decoys_to_mask}' \
    --outdir "\$PWD" \
    --threads ${task.cpus} \
    --picard-jar '${params.tools.picard_jar}' \
    ${keepIntermediate}
  """
}

process CLASSIFY {
  tag "$sample_id"
  label 'classify'
  input:
  tuple val(sample_id), path(t2t_paired), path(t2t_unpaired), path(input_flagstat), path(metrics_unaligned), path(metrics_decoys), path(t2t_flagstat_paired), path(t2t_flagstat_unpaired)
  output:
  tuple val(sample_id),
    path("bams/${sample_id}.t2tfilt_paired.bam"),
    path("bams/${sample_id}.t2tfilt_unpaired.bam"),
    path('filter_stats'),
    path('classification_stats'),
    emit: classified
  script:
  def keepIntermediate = params.pathseq.keep_intermediate ? '--keep-intermediate' : ''
  def classifierArgs = optionalArgsFromMap([
    'kraken-args': params.pathseq.kraken_args,
    'metaphlan-index': params.pathseq.metaphlan_index,
    'bowtie2-index': params.pathseq.bowtie2_index,
    'metaphlan-args': params.pathseq.metaphlan_args,
    'sylph-args': params.pathseq.sylph_args
  ])
  def sylphIndexArgs = (params.pathseq.sylph_indexes ?: []).collect { "--sylph-index '${it}'" }.join(' ')
  def sylphTaxArgs = (params.pathseq.sylph_taxonomies ?: []).collect { "--sylph-taxonomy '${it}'" }.join(' ')
  """
  set -euo pipefail
  mkdir -p bams filter_stats classification_stats
  cp -f ${t2t_paired} bams/${sample_id}.t2tfilt_paired.bam
  cp -f ${t2t_unpaired} bams/${sample_id}.t2tfilt_unpaired.bam
  cp -f ${input_flagstat} filter_stats/${sample_id}.flagstat.tsv
  cp -f ${metrics_unaligned} filter_stats/${sample_id}.prefilter.unaligned.filter_metrics.txt
  cp -f ${metrics_decoys} filter_stats/${sample_id}.prefilter.decoys.filter_metrics.txt
  cp -f ${t2t_flagstat_paired} filter_stats/${sample_id}.qcfilt_paired.t2t_unaln.flagstat.tsv
  cp -f ${t2t_flagstat_unpaired} filter_stats/${sample_id}.qcfilt_unpaired.t2t_unaln.flagstat.tsv
  '${projectDir}/pathseq-t2t/upstream/src/pathseq-t2t' classify \
    --sample-id ${sample_id} \
    --classifiers '${params.pathseq.classifiers}' \
    --outdir "\$PWD" \
    --kraken-index '${params.references.kraken_index}' \
    --picard-jar '${params.tools.picard_jar}' \
    --threads ${task.cpus} \
    ${classifierArgs} \
    ${sylphIndexArgs} \
    ${sylphTaxArgs} \
    ${keepIntermediate}
  """
}

process SUMMARIZE {
  tag "$sample_id"
  label 'summarize'
  publishDir params.outdir, mode: 'copy', pattern: 'samples/**'
  input:
  tuple val(sample_id), path(t2t_paired), path(t2t_unpaired), path(filter_stats), path(classification_stats)
  output:
  tuple val(sample_id), path("samples/${sample_id}/pathseq_t2t"), emit: results
  tuple val(sample_id),
    path("qc_collate/${sample_id}.summary.tsv"),
    path("qc_collate/${sample_id}.prefilter.unaligned.filter_metrics.txt"),
    path("qc_collate/${sample_id}.qcfilt_paired.t2t_unaln.flagstat.tsv"),
    path("qc_collate/${sample_id}.qcfilt_unpaired.t2t_unaln.flagstat.tsv"),
    emit: qc_metrics
  tuple val(sample_id), path("kraken_collate/${sample_id}.kraken.txt"), emit: kraken_results, optional: true
  script:
  """
  set -euo pipefail
  mkdir -p samples/${sample_id}/pathseq_t2t/{bams,filter_stats,classification_stats}
  cp -f ${t2t_paired} samples/${sample_id}/pathseq_t2t/bams/${sample_id}.t2tfilt_paired.bam
  cp -f ${t2t_unpaired} samples/${sample_id}/pathseq_t2t/bams/${sample_id}.t2tfilt_unpaired.bam
  cp -a ${filter_stats}/. samples/${sample_id}/pathseq_t2t/filter_stats/
  cp -a ${classification_stats}/. samples/${sample_id}/pathseq_t2t/classification_stats/
  '${projectDir}/scripts/run_summarize.sh' \
    --sample-id ${sample_id} \
    --outdir "\$PWD/samples/${sample_id}/pathseq_t2t" \
    --pathseq-t2t-bin '${projectDir}/pathseq-t2t/upstream/src/pathseq-t2t'
  rm -rf samples/${sample_id}/pathseq_t2t/bams
  mkdir -p qc_collate
  cp samples/${sample_id}/pathseq_t2t/results/${sample_id}.summary.tsv \
    qc_collate/${sample_id}.summary.tsv
  cp samples/${sample_id}/pathseq_t2t/filter_stats/${sample_id}.prefilter.unaligned.filter_metrics.txt \
    qc_collate/${sample_id}.prefilter.unaligned.filter_metrics.txt
  cp samples/${sample_id}/pathseq_t2t/filter_stats/${sample_id}.qcfilt_paired.t2t_unaln.flagstat.tsv \
    qc_collate/${sample_id}.qcfilt_paired.t2t_unaln.flagstat.tsv
  cp samples/${sample_id}/pathseq_t2t/filter_stats/${sample_id}.qcfilt_unpaired.t2t_unaln.flagstat.tsv \
    qc_collate/${sample_id}.qcfilt_unpaired.t2t_unaln.flagstat.tsv
  if [[ -s samples/${sample_id}/pathseq_t2t/results/${sample_id}.kraken.txt ]]; then
    mkdir -p kraken_collate
    cp samples/${sample_id}/pathseq_t2t/results/${sample_id}.kraken.txt \
      kraken_collate/${sample_id}.kraken.txt
  fi
  """
}

process COLLATE_KRAKEN_RESULTS {
  label 'summarize'
  publishDir params.outdir, mode: 'copy', pattern: 'cohort/**'

  input:
  path taxonomy
  path kraken_result_files

  output:
  path 'cohort/kraken', emit: matrices

  script:
  def resultInputs = kraken_result_files.collect { "'${it}'" }.join(' ')
  """
  set -euo pipefail
  mkdir -p cohort/kraken
  python3 '${projectDir}/scripts/collate_kraken_results.py' \
    --taxonomy ${taxonomy} \
    --output-dir cohort/kraken \
    ${resultInputs}
  """
}

process COLLATE_READ_COUNTS {
  label 'summarize'
  publishDir params.outdir, mode: 'copy', pattern: 'cohort/**'

  input:
  path raw_count_files
  path post_count_files
  path host_flagstat_files
  path pathseq_metric_files
  val aligner

  output:
  path 'cohort/qc', emit: tables

  script:
  def rawInputs = raw_count_files.collect { "--raw-count '${it}'" }.join(' ')
  def postInputs = post_count_files.collect { "--post-count '${it}'" }.join(' ')
  def hostInputs = host_flagstat_files.collect { "--host-flagstat '${it}'" }.join(' ')
  def pathseqInputs = pathseq_metric_files.collect { "--pathseq-metric '${it}'" }.join(' ')
  """
  set -euo pipefail
  mkdir -p cohort/qc
  python3 '${projectDir}/scripts/collate_read_counts.py' \
    --output-dir cohort/qc \
    --aligner '${aligner}' \
    ${rawInputs} \
    ${postInputs} \
    ${hostInputs} \
    ${pathseqInputs}
  """
}

process COLLATE_STAR_GENE_COUNTS {
  label 'summarize'
  publishDir params.outdir, mode: 'copy', pattern: 'cohort/**'

  input:
  path gene_count_files
  val completed_sample_ids

  output:
  path 'cohort/host_gene_counts', emit: matrices

  script:
  def countInputs = gene_count_files.collect { "'${it}'" }.join(' ')
  def expectedInputs = completed_sample_ids.collect { "--expected-sample '${it}'" }.join(' ')
  """
  set -euo pipefail
  mkdir -p cohort/host_gene_counts
  python3 '${projectDir}/scripts/collate_star_gene_counts.py' \
    --output-dir cohort/host_gene_counts \
    ${expectedInputs} \
    ${countInputs}
  """
}

workflow {
  requireParam(params.outdir, 'outdir')

  aligner = params.aligner.toString().toLowerCase()
  if (!(aligner in ['bwa', 'star'])) {
    throw new IllegalArgumentException("params.aligner must be 'bwa' or 'star', got: ${params.aligner}")
  }

  inputMode = params.input_mode.toString().toLowerCase()
  if (!(inputMode in ['fastq', 'bam'])) {
    throw new IllegalArgumentException("params.input_mode must be 'fastq' or 'bam', got: ${params.input_mode}")
  }
  directInputDir = params.input_dir?.toString()?.trim()
  remoteInputDir = params.remote_input_dir?.toString()?.trim()
  if (directInputDir && remoteInputDir) {
    throw new IllegalArgumentException("Use exactly one of params.input_dir or params.remote_input_dir, not both")
  }
  if (!directInputDir && !remoteInputDir) {
    throw new IllegalArgumentException("One of params.input_dir or params.remote_input_dir is required")
  }
  sourceInputDir = remoteInputDir ?: directInputDir

  if (inputMode == 'bam') {
    bamSuffix = requireParam(params.bam_suffix, 'bam_suffix').toString()
    bamGlob = "${sourceInputDir}/**/*${bamSuffix}"
    source_bam_ch = Channel.fromPath(bamGlob, checkIfExists: true).map { bam ->
      def sample_id = bam.name.endsWith(bamSuffix) ? bam.name.substring(0, bam.name.size() - bamSuffix.size()) : bam.baseName
      tuple(sample_id, bam.toString())
    }
    STAGE_BAM_INPUT(source_bam_ch)
    BAM_TO_FASTQ(STAGE_BAM_INPUT.out.bam)
    reads_ch = BAM_TO_FASTQ.out.reads
  } else {
    readsGlob = "${sourceInputDir}/**/*_{R1,R2}.fastq.gz"
    source_reads_ch = Channel.fromFilePairs(readsGlob, flat: false, checkIfExists: true)
      .map { sample_id, reads -> tuple(sample_id, reads.collect { it.toString() }) }
    STAGE_FASTQ_INPUT(source_reads_ch)
    reads_ch = STAGE_FASTQ_INPUT.out.reads
  }
  adapters_ch = Channel.value(file(requireParam(params.qc.adapters, 'qc.adapters'), checkIfExists: true))
  classifierNames = normalizedNames(params.pathseq.classifiers)
  krakenEnabled = classifierNames.contains('kraken')
  log.info "Configured PathSeq-T2T classifiers: ${classifierNames.join(', ')}"
  log.info "Kraken cohort collation: ${krakenEnabled ? 'enabled' : 'disabled'}"
  if (krakenEnabled) {
    requireParam(params.references.kraken_index, 'references.kraken_index')
    PREPARE_KRAKEN_TAXONOMY()
  }

  FASTQC_RAW(reads_ch)
  BBDUK(reads_ch, adapters_ch)
  FASTQC_POST(BBDUK.out.reads)
  PREPARE_PATHSEQ()
  overrides_ready = PREPARE_PATHSEQ.out.ready

  if (aligner == 'bwa') {
    requireParam(params.references.grch38_fasta, 'references.grch38_fasta')
    requireParam(params.references.decoys_to_mask, 'references.decoys_to_mask')
    ALIGN_BWA(BBDUK.out.reads)
    PREFILTER_BWA(ALIGN_BWA.out.bam, overrides_ready)
    QCFILTER_BWA(PREFILTER_BWA.out.filtered)
    qcfilt_ch = QCFILTER_BWA.out.filtered
    host_flagstat_ch = ALIGN_BWA.out.flagstat
  } else {
    requireParam(params.references.star_index, 'references.star_index')
    requireParam(params.tools.picard_jar, 'tools.picard_jar')
    ALIGN_STAR(BBDUK.out.reads)
    QCFILTER_STAR(ALIGN_STAR.out.star_outputs, overrides_ready)
    qcfilt_ch = QCFILTER_STAR.out.filtered
    host_flagstat_ch = ALIGN_STAR.out.host_flagstat
  }
  T2TFILTER(qcfilt_ch)
  CLASSIFY(T2TFILTER.out.filtered)
  SUMMARIZE(CLASSIFY.out.classified)
  pathseq_metric_files = SUMMARIZE.out.qc_metrics
    .map { sample_id, summary, filter_metrics, paired_flagstat, unpaired_flagstat ->
      [summary, filter_metrics, paired_flagstat, unpaired_flagstat]
    }
    .collect()
    .map { nested -> nested.flatten() }
  COLLATE_READ_COUNTS(
    FASTQC_RAW.out.counts.collect(),
    FASTQC_POST.out.counts.collect(),
    host_flagstat_ch.collect(),
    pathseq_metric_files,
    aligner
  )
  if (krakenEnabled) {
    kraken_result_files = SUMMARIZE.out.kraken_results
      .map { sample_id, result_file -> result_file }
      .collect()
    COLLATE_KRAKEN_RESULTS(PREPARE_KRAKEN_TAXONOMY.out.taxonomy, kraken_result_files)
  }
  if (aligner == 'star') {
    completed_sample_ids = SUMMARIZE.out.results
      .map { sample_id, result_dir -> sample_id }
      .collect()
    COLLATE_STAR_GENE_COUNTS(ALIGN_STAR.out.gene_counts.collect(), completed_sample_ids)
  }
}
