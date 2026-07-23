# pathseq-t2t-nextflow

An independent Nextflow workflow built around
[PathSeq-T2T](https://github.com/abdohlman/pathseq-t2t) for host-read
subtraction and microbial classification. It extends the upstream WGS-oriented
workflow with configurable read preprocessing, BAM input reconstruction, and
BWA or STAR host alignment, including an RNA-seq-compatible route.

This repository is not an official PathSeq-T2T distribution and is not
affiliated with its upstream maintainers.

## Workflow overview

1. stage paired FASTQ files or reconstruct FASTQs from primary BAM records;
2. run raw FastQC;
3. apply configurable BBDuk read cleanup and run post-QC FastQC;
4. align host reads with BWA or STAR;
5. run the PathSeq-T2T filtering stages independently;
6. classify retained reads and generate upstream-compatible summary tables;
7. collate cohort-level read-count QC and optional STAR/Kraken matrices;
8. publish curated QC, mapping, classification, and execution reports.

Large FASTQ and BAM intermediates remain in the Nextflow work directory. Keep
that directory until the run has been reviewed because it is needed by
`-resume`.

## Status

This is an early research workflow. Validate parameters, resource requests,
reference versions, and output counts on representative test data before using
it for production analysis.

## Requirements

- Linux or an HPC cluster with SLURM
- Conda/Mamba
- Git
- reference files and classifier databases supplied by the user

Reference databases and input data are not distributed by this repository.

## Installation

Create the pinned software environment:

```bash
mamba env create -f envs/pathseq-t2t.yml
mamba activate pathseq-t2t-nextflow
```

Prepare the workflow-managed, pinned PathSeq-T2T runtime and apply the reviewed
fixes:

```bash
./scripts/setup_pathseq_t2t.sh
```

The generated checkout lives at `pathseq-t2t/upstream/` and is ignored by Git.
The setup script never modifies another PathSeq-T2T installation.

Prepare the required reference databases in an external data location:

```bash
./scripts/prepare_references.sh \
  --db-root /path/to/pathseq-t2t-db \
  --threads 16
```

The database root may instead be supplied through `PST2T_DB_ROOT`. The script
downloads the versioned default references, verifies available upstream
checksums or published sizes, builds the BWA and STAR indexes, and writes a
ready-to-copy parameter template. See
[docs/references.md](docs/references.md) for storage requirements, individual
components, and restart behavior.

## Configuration

Copy and edit the example parameter file:

```bash
cp parameters.example.yaml parameters.yaml
```

Set exactly one of `input_dir` and `remote_input_dir`. Configure the host and
T2T references, classifier database, Picard JAR, and cluster queue as required.
Paths in `parameters.yaml` may be absolute; the file is ignored by Git to help
avoid publishing local paths accidentally.

Input discovery is recursive. FASTQ mode expects paired files ending in
`_R1.fastq.gz` and `_R2.fastq.gz`. BAM mode uses the configured `bam_suffix`.

## Running

SLURM:

```bash
nextflow run . \
  -params-file parameters.yaml \
  -profile slurm \
  -work-dir /path/to/scratch/work \
  -resume
```

For a direct Bash-run local execution, edit the three paths at the top of
`run.sh` and run:

```bash
./run.sh
```

The same values can be supplied without editing:

```bash
INPUT_DIR=/path/to/paired-fastq \
WORK_DIR=/path/to/nextflow-work \
OUTDIR=/path/to/results \
./run.sh
```

`run.sh` uses Nextflow's `local` executor and contains no SLURM or `sbatch`
settings. FASTQ discovery is handled by the workflow itself.

Local syntax/stub check:

```bash
nextflow run . \
  -params-file parameters.yaml \
  -profile local \
  -stub-run
```

See [docs/nextflow.md](docs/nextflow.md) for parameters, output structure, BAM
input behavior, and operational guidance.

## Cohort collation

After all samples finish, the workflow generates cohort-level read-count QC
tables. STAR runs additionally produce unstranded, forward, and reverse gene
count matrices. When Kraken is enabled, the workflow generates bacterial and
archaeal genus/species count and RPM matrices using taxonomy from the exact
configured Kraken database.

For compatibility with the liver-atlas bulk analysis, Kraken matrices use the
row label `Bacteria` for the sum of the Bacteria and Archaea domain-level clade
counts. Archaeal genera and species are still retained separately. This is an
intentional project naming convention, not a taxonomic reclassification.

## Upstream modifications

The workflow pins PathSeq-T2T and installs reviewed fixes for uBAM validation,
command construction, and T2T filtering. Summary and RPM generation are
delegated directly to that pinned checkout's `pathseq-t2t summarize` command.
See [docs/upstream-modifications.md](docs/upstream-modifications.md) and
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

The inherited paired/unpaired counting behavior and a candidate upstream
correction, which is not implemented here, are recorded separately in
[docs/read-counting-review.md](docs/read-counting-review.md).

## License and citation

The workflow-specific code is available under the MIT license. Modified
upstream files retain the PathSeq-T2T MIT notice. See [LICENSE](LICENSE),
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md), and [CITATION.cff](CITATION.cff).
