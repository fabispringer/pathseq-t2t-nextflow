# PathSeq-T2T Nextflow v0.3.3

Release candidate prepared locally. Not yet tagged or published.

## Changes

- Add explicit direct single-end FASTQ input through `fastq_layout: single`.
  Accept one `_R1.fastq.gz` or `_1.fastq.gz` file per sample, stage it as the
  unpaired stream, and preserve valid empty R1/R2 gzip placeholders.
- Preserve paired input as the default (`fastq_layout: paired`) and reject
  ambiguous duplicate single-end inputs for the same sample.
- Make BWA/DRAGEN prefilter BAM creation synchronous. Validate complete
  temporary BAMs, promote validated outputs to their final paths, and clean
  temporary files on failure without changing intended read-selection rules.
  Each output is renamed individually, not as an atomic set.
- Document valid `input_mode` (`fastq | bam`), `fastq_layout`
  (`paired | single`), and `aligner` (`star | bwa`) values in the parameter
  template. Pass all three explicitly from both launchers.
- Support per-run copies of `run.sh` and `parameters.yaml`: the parameter
  file defaults to the launcher's directory, while `REPO_ROOT` can point to
  the separate workflow checkout. Select the executor through `PROFILE`.
- Align the manifest, citation, launcher release pins, and repository version
  check at `0.3.3`; update configuration and operating documentation.
- Add mocked regression coverage for synchronous prefilter output/failure
  handling and copied-launcher argument forwarding.

## Compatibility and upgrade

- Existing paired FASTQ and BAM configurations remain supported. Set both
  `input_mode: fastq` and `fastq_layout: single` for direct single-end input.
  Single mode does not select R2 files; do not use it for paired-end data.
- The minimum Nextflow version remains `26.04.6`.
- The managed PathSeq-T2T dependency remains pinned to
  `51d74430b6a4b34073f2d878612ac24b6a1d1e80`.
- Rebuild the ignored managed runtime after upgrading, or explicitly install
  the reviewed overrides. Switching wrapper tags alone does not refresh it.
  Preserve an existing runtime by renaming it before running
  `./scripts/setup_pathseq_t2t.sh`; setup refuses an existing destination.
- Keep site-specific configuration in a separate local file and supply it
  with `-c`. Preserve existing work directories until runs are reviewed.
- Upstream summarization/counting behavior is unchanged. This release does
  not establish equivalence with historical legacy microbial profiles.

## Validation and publication status

- Repository component and consistency checks are recorded in
  `docs/release-v0.3.3.md`.
- End-to-end cluster success has not been independently verified for this
  release candidate. Review the run summary and trace for failed or ignored
  samples, not only the overall workflow exit status.
- No Nextflow runtime or fresh DAG validation was performed locally.
- Existing pipeline artwork remains provisional and is not a release gate.

Proposed comparison after publication:
https://github.com/fabispringer/pathseq-t2t-nextflow/compare/v0.3.2...v0.3.3
