# v0.3.3 release preparation and review

Prepared: 2026-10-28. Candidate only. Nothing committed, pushed, tagged,
merged, or published. The citation date is provisionally 2026-10-28; update
it if publication occurs on another date.

## Remote state and complete commit review

GitHub branches/releases/check runs and `git ls-remote` were checked on
2026-10-28. Latest published release: v0.3.2 (2026-08-07).

| Ref | Commit |
| --- | --- |
| `main`, `v0.3.2` | `149fa32cdd8edc3ec7898b2b72966e6c8732b1df` |
| `feature/single-end-fastq` | `c842c4a4db1cc8ff7d46354096f7b3978bb2a8dd` |

The feature branch contains exactly two commits since v0.3.2; main contains
none. No feature-branch PR or head check runs were present.

| Commit | Review |
| --- | --- |
| [`f3250ae`](https://github.com/fabispringer/pathseq-t2t-nextflow/commit/f3250ae) | Adds validated paired/single layout selection, recursive single-end discovery with duplicate detection, three-stream staging with valid empty gzip placeholders, matching configuration and docs. Downstream processes already consume paired and unpaired streams. |
| [`c842c4a`](https://github.com/fabispringer/pathseq-t2t-nextflow/commit/c842c4a) | Replaces asynchronous prefilter writers with synchronous temporary files, checks completed BAMs, promotes each output and cleans temporary files on failure. Setup installs the new override. BWA/DRAGEN selection flags and AS threshold match the pinned upstream source. |

No blocking source defect was identified in these two commits. This is a
source review plus the bounded checks below, not proof of end-to-end success.
The single-end glob deliberately does not select R2 files; this behavior is
now explicit in the parameter comments and operating docs. The prefilter
output set is not a single atomic transaction; each final rename is separate.

## Candidate assembly and changes

The candidate was assembled in a separate detached worktree at c842c4a.
Existing uncommitted files in the original checkout were left untouched.
Earlier local release metadata/documentation preparation was incorporated
and refreshed. No merge or commit was created.

- Version 0.3.3 in manifest, citation, both launchers and consistency check.
- Documented input mode, FASTQ layout and host-aligner choices/defaults.
- Explicit INPUT_MODE, FASTQ_LAYOUT and ALIGNER selections in both launchers.
- PROFILE selection and separate source/run-directory support in run.sh.
- Updated README, execution guide, upstream modifications, third-party
  notices, release notes and this review record.
- Added targeted prefilter transaction and launcher regression checks.

The existing six provisional diagram files are included because the README
references them. Their SVG XML is checked structurally; the artwork remains
provisional and is not a fresh Nextflow-generated DAG. Unrelated historical
release notes and the recollation helper are not part of this delivery.
AGENTS.md is local-only operating metadata and is never delivered.

## Validation on 2026-10-28

`bash tests/check_repository.sh` passes, including shell syntax, Python
compilation, all eight component check scripts, and version consistency.
The new prefilter test executes the exact write-transaction block with mocked
samtools for BWA/DRAGEN success, invalid aligner, and failures in flagstat,
splitting, either output write, and BAM validation. It checks that incomplete
outputs are not promoted and temporary files are cleaned. It does not test
the upstream argument parser or biological read selection.

The launcher test executes a copied run.sh with a fake Nextflow CLI for
paired FASTQ, single FASTQ and BAM choices across local/slurm/lsf profiles.
It checks explicit parameter forwarding, the separate repository/run paths,
and arguments containing spaces. This does not submit scheduler jobs.

`git diff --check` and both SVG XML parses pass. Changed-file delivery is
verified byte-for-byte and recorded in the external handoff manifest.

Nextflow and samtools are unavailable on this shell PATH. No software was
installed, no runtime/reference/data downloads were performed, and no fresh
Nextflow parse/DAG or end-to-end pipeline run was performed. The feature
head has no passing CI evidence. Cluster validation remains outstanding.

## Server assembly and publication by Fabian

1. Preserve site-specific settings and work directories. Integrate
   feature/single-end-fastq into the intended release branch using the normal
   reviewed Git workflow. The delivery includes full implementation files
   against v0.3.2 as well as preparation edits, so copying is self-contained;
   copying files alone does not incorporate the feature branch's Git history.
2. Copy repository files from the handoff files/ tree to matching paths.
   parameters.yaml is an additional generic run-template copy and remains
   Git-ignored. Keep real site/run values out of the release commit.
3. Run bash tests/check_repository.sh on the assembled candidate. Validate
   Nextflow parsing/DAG, paired and single staging, and representative
   end-to-end completion on the server using existing dependencies.
4. Check expected versus completed samples and all failed/ignored tasks in
   the trace. Sample-specific failures may be ignored after retries, so
   overall success alone does not establish cohort completeness.
5. Rebuild the managed runtime after upgrade, preserving the old directory
   first. Switching wrapper tags does not update the generated runtime.
   Verify the pinned upstream commit is
   51d74430b6a4b34073f2d878612ac24b6a1d1e80 and all four overrides are installed.
6. Review the staged file list, including provisional diagrams. Exclude
   AGENTS.md, local configuration, run-specific parameters, data, references,
   generated runtimes and work directories. Adjust the citation date if needed.
7. Once validation is confirmed, remove candidate-only wording from the
   README/execution guide/release notes as appropriate, commit and publish
   manually, and tag the reviewed release commit v0.3.3. Use the release notes
   for the GitHub release and verify the tag points to the intended commit.

The existing run_lsf.sh checks out v0.3.3 and therefore requires the tag to
exist before use. To validate an unpublished candidate, use run.sh with
PROFILE="lsf" or invoke Nextflow directly against the candidate checkout.
