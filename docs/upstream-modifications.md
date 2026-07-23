# PathSeq-T2T version and modifications

The managed runtime is pinned to PathSeq-T2T commit
`51d74430b6a4b34073f2d878612ac24b6a1d1e80`. Running
`scripts/setup_pathseq_t2t.sh` clones that exact revision and installs two
reviewed modified command files. It does not change any checkout outside this
project.

## `qcfilter.sh`

- validates the host-unaligned input as an unaligned BAM;
- builds GATK commands as arrays, avoiding an empty positional argument when
  no additional `PathSeqFilterSpark` arguments are supplied.

## `t2tfilter.sh`

- corrects Picard option spelling and explicit stdin/stdout handling;
- writes the selected aligned reads instead of discarding them;
- retains configured decoy-overlapping reads and merges them into the output;
- makes output and flagstat paths explicit and consistent.

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
