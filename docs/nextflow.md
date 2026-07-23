# Nextflow pipeline

This workflow moves sample handling and job submission into Nextflow:

1. symlink direct inputs or copy remote inputs into the Nextflow work directory
2. optional BAM-to-FASTQ reconstruction for BAM-only cohorts
3. raw FastQC on each paired FASTQ sample
4. stringent BBDuk cleanup using the `vortex_knight` adapter sequences
5. post-QC FastQC on the cleaned paired reads
6. GRCh38 alignment with either BWA or STAR
7. PathSeq-T2T filtering and classification

The PathSeq-T2T section is split into independent Nextflow processes:

1. `PREFILTER_BWA` for BWA input only
2. `QCFILTER_BWA` or `QCFILTER_STAR`
3. `T2TFILTER`
4. `CLASSIFY`
5. `SUMMARIZE`
6. cohort collation for read counts and Kraken profiles, plus STAR gene counts

Each process has separate CPU, memory, and time settings under `resources` in
`parameters.yaml`. This allows SLURM to allocate 16 CPUs and larger memory to
filtering and classification while keeping summarization at 2 CPUs and 8 GB.
It also allows failed stages to resume independently with `-resume`.

## Configure

Edit `parameters.yaml` before running. The important fields are:

- `input_mode` - `fastq` (default) or `bam`
- `input_dir` - source directory whose selected input files are symlinked by
  the first pipeline process
- `remote_input_dir` - source directory whose selected input files are copied
  by the first pipeline process; mutually exclusive with `input_dir`
- `bam_suffix` - exact suffix removed to obtain the sample identifier
- `outdir` - the single durable, curated result directory; large FASTQs and
  BAMs remain only in Nextflow's work directory
- `conda_prefix` - absolute path to the `pathseq-t2t-nextflow` Conda environment; the
  SLURM profile adds its executables and Java runtime to every batch job
- `aligner` - `star` or `bwa`
- `qc.adapters` - adapter FASTA; use this repo's `assets/adapters.fa`
- `qc.min_length` - minimum retained read length; configured as `45`
- `qc.bbduk_params` - stringent shotgun parameters matching `vortex_knight`
- `tools.picard_jar` - path to the Picard JAR
- `references.*` - GRCh38, STAR, PathSeq host, T2T, Kraken, and decoy inputs
- `resources.*` - per-stage CPU, memory, wall-time, and GATK heap settings
- `slurm.max_jobs` - global maximum number of submitted/active SLURM jobs;
  configured as `20`, equivalent to an array concurrency limit such as `%20`
- `lsf.queue` - LSF queue supplied to `bsub -q`
- `lsf.project` - LSF billing project supplied to `bsub -P`
- `lsf.max_jobs` - global maximum number of submitted/active LSF jobs

Both BWA and STAR alignment consume the cleaned paired FASTQs emitted by
BBDuk. Surviving singleton reads, including reads made singleton by BBDuk, are
cleaned separately and carried through BWA or STAR as single-end reads.

## BAM input mode

For TCGA-style BAM-only input:

```yaml
input_mode: bam
remote_input_dir: "/g/path/to/bams"
bam_suffix: .rna_seq.genomic.gdc_realn.bam
bam2fastq:
  prefer_original_qualities: false
```

`BAM_TO_FASTQ` uses the same core approach as `vortex_knight`:
`samtools collate | samtools fastq`. It explicitly uses `-F 0x900`, retaining
mapped, unmapped, duplicate, and QC-failed primary records while excluding
secondary and supplementary alignment representations. Paired reads go to R1
and R2; category-zero and singleton reads are retained in an unpaired FASTQ.
The process fails unless R1 and R2 contain equal numbers of reads and the total
FASTQ read count exactly equals the number of primary BAM records. The audit is
published as `outdir/pipeline_info/input_audit/<sample>.bam2fastq.stats.tsv`.

Set `prefer_original_qualities: true` only if representative BAMs contain
meaningful `OQ` tags and those original qualities are desired. BAMs cannot
restore reads that were removed before archival or bases removed by hard
clipping.

## Durable results

FASTQs, BAMs, and other large intermediates remain only in Nextflow's work
directory (normally on scratch). `outdir` receives the curated audit trail and
final PathSeq-T2T results:

- `samples/<sample>/read_qc/raw_fastqc/`
- `samples/<sample>/read_qc/post_qc_fastqc/` (including cleaned singleton reads)
- `samples/<sample>/read_qc/<sample>.bbduk_stats.txt`
- `samples/<sample>/host_mapping/<sample>.host_alignment.flagstat.tsv`
- `samples/<sample>/host_mapping/<sample>.star.Log.final.out` for STAR runs
- `samples/<sample>/host_mapping/<sample>.star.ReadsPerGene.out.tsv` for STAR runs
- `samples/<sample>/pathseq_t2t/filter_stats/`
- `samples/<sample>/pathseq_t2t/classification_stats/`
- `samples/<sample>/pathseq_t2t/results/`
- `pipeline_info/input_audit/` for BAM-input reconstruction validation

The resulting directory tree is:

```text
<outdir>/
├── cohort/
│   ├── host_gene_counts/                    # STAR only
│   │   ├── host_gene_counts.unstranded.tsv
│   │   ├── host_gene_counts.forward.tsv
│   │   ├── host_gene_counts.reverse.tsv
│   │   ├── host_gene_counting_qc.unstranded.tsv
│   │   ├── host_gene_counting_qc.forward.tsv
│   │   └── host_gene_counting_qc.reverse.tsv
│   ├── qc/
│   │   ├── read_count_summary.tsv
│   │   └── read_count_long.tsv
│   └── kraken/                              # Kraken classifier only
│       ├── kraken_taxonomy.tsv
│       ├── kraken_genus_counts.tsv
│       ├── kraken_genus_rpm.tsv
│       ├── kraken_species_counts.tsv
│       └── kraken_species_rpm.tsv
├── pipeline_info/
│   ├── nextflow_report.html
│   ├── nextflow_timeline.html
│   ├── nextflow_trace.tsv
│   ├── nextflow_dag.html
│   └── input_audit/
│       └── <sample>.bam2fastq.stats.tsv       # BAM input mode only
└── samples/
    └── <sample>/
        ├── read_qc/
        │   ├── raw_fastqc/
        │   ├── post_qc_fastqc/
        │   ├── <sample>.raw_fastqc_counts.tsv
        │   ├── <sample>.post_fastqc_counts.tsv
        │   └── <sample>.bbduk_stats.txt
        ├── host_mapping/
        │   ├── <sample>.host_alignment.flagstat.tsv
        │   ├── <sample>.star.Log.final.out             # STAR only
        │   └── <sample>.star.ReadsPerGene.out.tsv      # STAR only
        └── pathseq_t2t/
            ├── filter_stats/
            ├── classification_stats/
            └── results/
```

Keep the scratch work directory until the cohort run and compact result export
have been checked; it is required for `-resume`.

For STAR, the pipeline converts STAR's unmapped FASTQs into:

```text
<sample>.prefilter.unaligned.bam
```

and starts PathSeq-T2T at `qcfilter`.

The STAR process also converts `Number of input reads` from `Log.final.out`
into the primary-read flagstat consumed by the pinned upstream
`pathseq-t2t summarize` command. The repository does not carry a modified copy
of `pst2t_summarize.py`; paired/unpaired counting and RPM generation therefore
follow the pinned PathSeq-T2T checkout. The known counting concern is recorded
in `docs/read-counting-review.md` for later validation and upstream discussion.

After every sample has completed `SUMMARIZE`, `COLLATE_STAR_GENE_COUNTS`
validates that the completed sample set matches the STAR count files and that
all samples use the same ordered Ensembl gene set. It writes cohort-level
matrices to `outdir/cohort/host_gene_counts/`: gene-count and four-row STAR
counting-QC matrices for the unstranded, forward, and reverse columns. This
process is skipped for BWA runs.

For both aligners, `COLLATE_READ_COUNTS` writes a one-row-per-sample wide table
and a plotting-friendly long table to `outdir/cohort/qc/`. Counts derived
directly from FastQC, `samtools flagstat`, PathSeq filter metrics, and T2T
output flagstats use the explicit unit `read_ends`. Values copied from the
upstream Dohlman summary are prefixed with `dohlman_` and retain its original
paired/unpaired counting convention.

When Kraken is enabled, `PREPARE_KRAKEN_TAXONOMY` runs `kraken2-inspect` once
against the configured database. `COLLATE_KRAKEN_RESULTS` joins final Kraken
tables to that taxonomy and writes genus- and species-level count and RPM
matrices to `outdir/cohort/kraken/`. Only Bacteria and Archaea descendants are
retained. For liver-atlas compatibility, the matrix row named `Bacteria` is
defined as the Bacteria plus Archaea domain-level clade counts; Archaea taxa
are otherwise retained normally. RPM values are inherited unchanged from the
upstream summarizer output.

For BWA, the pipeline starts PathSeq-T2T at `prefilter` using the aligned
GRCh38 BAM.

## Run

Launch Nextflow from the repository root and specify exactly one input
location. For files already on scratch, use `--input_dir`; the first pipeline
stage creates symlinks in its task input area:

```bash
nextflow run . \
  -params-file ./parameters.yaml \
  -profile slurm \
  -work-dir "$WORK_DIR" \
  -resume \
  --input_dir /path/to/scratch/cohort \
  --input_mode fastq \
  --outdir "$OUTDIR"
```

When input is on another high-I/O shared filesystem, use
`--remote_input_dir`; the first pipeline stage copies each selected FASTQ pair
or BAM into its Nextflow work directory:

```bash
nextflow run . \
  -params-file ./parameters.yaml \
  -profile slurm \
  -work-dir "$WORK_DIR" \
  -resume \
  --remote_input_dir /path/to/shared/cohort \
  --input_mode fastq \
  --outdir "$OUTDIR"
```

For BAM input, use `--input_mode bam`. The staging operation appears as
`STAGE_FASTQ_INPUT` or `STAGE_BAM_INPUT` in the Nextflow DAG, trace, timeline,
and report. Every downstream process consumes only these staged outputs.
Discovery is recursive: FASTQ mode selects `_R1.fastq.gz`/`_R2.fastq.gz`
pairs, while BAM mode selects files ending in `bam_suffix`.

The trace includes both observed utilization (`%cpu`, `peak_rss`, I/O, and
runtime) and the requested `cpus`, `memory`, and `time` for each task.

Keep `WORK_DIR` until the run and exports have been checked because it is
required by `-resume`. Nextflow engine options use one dash (for example
`-resume` and `-work-dir`), while pipeline parameters use two dashes (for
example `--input_mode` and `--outdir`).

The SLURM profile requires `conda_prefix` and uses the environment directly by
absolute path. This avoids relying on interactive shell initialization or a
named `conda activate` call inside compute jobs.

Nextflow applies `slurm.max_jobs` through `executor.queueSize`. When the limit
is reached, completed jobs free slots for subsequent processes. Change the
value in `parameters.yaml` for cohort runs; it applies across the whole
workflow rather than separately to each process.

## LSF execution

The `lsf` profile submits every workflow process through `bsub`:

```bash
nextflow run . \
  -params-file ./parameters.yaml \
  -profile lsf \
  -work-dir "$WORK_DIR" \
  -resume
```

Configure the site-specific queue and billing project in `parameters.yaml`:

```yaml
lsf:
  queue: premium
  project: acc_SeqLiver
  max_jobs: 20
```

The profile keeps the CPU, total-memory, and wall-time values defined under
`resources`. This LSF configuration treats `rusage[mem=...]` as memory per CPU
slot, so Nextflow divides each process's total requested memory by its CPU
count. For example, an 8-CPU process requesting 64 GB total asks LSF for
approximately 8 GB per slot. All multi-core tasks also request
`span[hosts=1]`.

If the cluster permits scheduler submission from compute jobs, the optional
`run_lsf.sh` wrapper can submit the long-lived Nextflow controller itself:

```bash
bsub < run_lsf.sh
```

Submit it from the repository root after editing `CONDA_ENV_PREFIX` and
`WORK_DIR`, or export those values before submission. The controller requests
only one CPU and 4 GB. It then submits the actual pipeline tasks with the
process-specific resources. If nested `bsub` submission is not allowed at the
site, start the same `nextflow run` command from a persistent login-node
session instead.

For a local graph and syntax preview on a machine with Nextflow installed:

```bash
nextflow run . \
  -params-file parameters.yaml \
  -profile local \
  -preview
```

`parameters.yaml` is deliberately plain YAML so the cluster-specific paths stay
in one place instead of being hardcoded in the workflow.
