# PathSeq-T2T version and modifications

The managed runtime is pinned to PathSeq-T2T commit
`51d74430b6a4b34073f2d878612ac24b6a1d1e80`. Running
`scripts/setup_pathseq_t2t.sh` clones that exact revision and installs three
reviewed modified command files. It does not change any checkout outside this
project.

The reviewed, version-controlled source files are:

- `overrides/qcfilter.sh`
- `overrides/t2tfilter.sh`
- `overrides/io.sh`

During setup they overwrite the corresponding files inside the generated,
Git-ignored runtime:

- `pathseq-t2t/upstream/src/commands/qcfilter.sh`
- `pathseq-t2t/upstream/src/commands/t2tfilter.sh`
- `pathseq-t2t/upstream/lib/io.sh`

The files under `overrides/` are the sources of truth and are the files that
should be committed. The copies under `pathseq-t2t/upstream/` are generated
runtime files and should not be committed. When testing a revised override
against an already-created runtime, copy it to both locations; a fresh
`scripts/setup_pathseq_t2t.sh` installation performs that copy automatically.

## `qcfilter.sh`

- validates the host-unaligned input as an unaligned BAM;
- builds GATK commands as arrays, avoiding an empty positional argument when
  no additional `PathSeqFilterSpark` arguments are supplied;
- reads `FINAL_PAIRED_READS` and `FINAL_UNPAIRED_READS` from the GATK filter
  metrics before requiring category outputs;
- accepts a missing paired or unpaired PathSeq output only when the
  corresponding final count is zero;
- creates a valid header-only BAM for a zero-count category, preserving the
  paired/unpaired file contract required by later workflow stages;
- still fails if metrics report retained reads but the corresponding BAM/SBI
  output is missing.

## `t2tfilter.sh`

- corrects Picard option spelling and explicit stdin/stdout handling;
- writes the selected aligned reads instead of discarding them;
- retains configured decoy-overlapping reads and merges them into the output;
- writes T2T-unmapped candidates synchronously before starting decoy extraction
  or merging, eliminating an inherited process-substitution race;
- validates temporary candidates and promotes them atomically to final output
  names only after successful completion;
- tests decoy BAM record counts rather than treating header-only BAMs as
  nonempty;
- treats `samtools flagstat` failures as fatal;
- makes output and flagstat paths explicit and consistent;
- counts paired and unpaired input records independently;
- skips FASTQ conversion, BWA alignment, and extraction for a zero-record
  category, writing a header-only final BAM instead;
- validates zero-record placeholders as unaligned BAMs and nonempty T2T
  outputs as aligned BAMs;
- preserves the paired/unpaired two-BAM interface for entirely single-end,
  entirely paired, and mixed samples.

## `io.sh`

- retains upstream `samtools quickcheck` framing validation;
- additionally performs a complete `samtools view -c` read of every validated
  BAM;
- detects corrupt internal BGZF blocks even when a terminal EOF marker allows
  `quickcheck` to pass.

## Upstream summarizer retained

This repository does not carry or install a modified `pst2t_summarize.py`.
Summary and RPM generation call the pinned checkout's
`pathseq-t2t summarize` command directly. This preserves the upstream counting
behavior for reproducibility. The potential paired/unpaired unit inconsistency
and a candidate correction are documented in `read-counting-review.md` but are
not implemented.

These files are derived from PathSeq-T2T and retain its MIT license notice in
`THIRD_PARTY_NOTICES.md`. Where generally applicable, the fixes should
eventually be proposed upstream. After an upstream release includes a fix, the
managed revision can be advanced and the redundant local modification removed.
