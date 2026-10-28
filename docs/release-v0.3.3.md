# v0.3.3 release preparation and validation

Updated: 2026-10-28. Release candidate, not a publication record.
The candidate was committed and pushed on `release/v0.3.3`; cluster validation
remains outstanding. The citation date is provisionally 2026-10-28; update it
if publication occurs on another date.

## Reviewed candidate

The pushed candidate reviewed on 2026-10-28 is
`3b7b01ae799be5b27bf8890d5c5750f921e42116`. This documentation cleanup is
prepared against that commit and must be committed separately. After applying
it, record the new commit and validate that exact revision on the cluster.

| Commit | Changes |
| --- | --- |
| `f3250ae` | Explicit paired/single FASTQ layout selection, recursive single-end discovery with duplicate detection, and three-stream staging with valid empty gzip placeholders. |
| `c842c4a` | Synchronous prefilter BAM creation, temporary-output validation and cleanup, and runtime override installation. |
| `7a4f2b3` | v0.3.3 candidate metadata, launcher configuration, documentation, and repository-check prerequisites. |
| `3b7b01a` | Release guide, release notes, prefilter/launcher regression tests, and restored executable script permissions. |

No blocking source defect was identified in the reviewed implementation.
Source review and mocked checks do not establish end-to-end pipeline success.
Single-end discovery deliberately does not select R2 files. Prefilter outputs
are promoted by separate renames, not as one atomic output set.

## Candidate scope

- Version 0.3.3 in the manifest, citation, launchers and consistency check.
- Explicit input mode, FASTQ layout, host-aligner and executor selections.
- Per-run launchers and parameter files with a separate source checkout.
- Synchronous prefilter BAM writing and failure-handling regression coverage.
- Python 3.11 and ripgrep repository-check prerequisites.
- Updated operating documentation, notices and release notes.

The pipeline overview and technical process-map diagrams are unfinished and
excluded from v0.3.3. Their broken README image references are removed by this
cleanup. Track completion in [documentation todos](todo.md). No diagram
artwork or generated DAG is included in this cleanup.

## Validation evidence and limitations

The exact pushed candidate at `3b7b01a` passed
`bash tests/check_repository.sh`, including shell syntax, Python compilation,
all eight component checks, and version consistency. `git diff --check` also
passed during that review. These results apply to the reviewed candidate, not
to an untested future revision.

The documentation-cleanup working tree also passed the repository suite on
2026-10-28. Local Markdown link checks and `git diff --check` passed. No
pipeline code or configuration was changed, and no cluster run was performed.

The prefilter regression test executes the write-transaction block with mocked
samtools for BWA/DRAGEN success, invalid aligner, and failures in flagstat,
splitting, output writing and BAM validation. It checks cleanup and rejection
of incomplete outputs. It does not establish biological read-selection
correctness or test the upstream argument parser.

The launcher regression test uses a fake Nextflow CLI for paired FASTQ, single
FASTQ and BAM modes across local/slurm/lsf profiles. It verifies parameter
forwarding, separate repository/run paths, and arguments containing spaces.
It does not submit scheduler jobs.

No GitHub CI runs were present for the reviewed candidate. No fresh Nextflow
parse/DAG or end-to-end run was performed locally. Cluster validation, expected
sample counts, and failed/ignored-task review remain release requirements.
The deferred documentation diagrams do not replace runtime/DAG validation.

## Apply the documentation cleanup

1. Stay on `release/v0.3.3`. Preserve any local edits before copying files.
2. Copy the four repository files listed in the handoff to their matching
   paths individually. Do not replace whole folders or copy handoff metadata
   into the repository.
3. Review `git diff`, run `bash tests/check_repository.sh` and
   `git diff --check`, then stage only the intended documentation files.
4. Commit and push the documentation cleanup. Record the resulting commit
   with `git rev-parse HEAD` for the cluster test. Keep local configuration,
   real parameters, data, references, generated runtimes and work directories
   out of the commit.

## Cluster validation before publication

1. Preserve site-specific settings, existing run files and work directories.
   Check out the exact candidate commit being validated.
2. Refresh the managed runtime before launching the test, preserving the old
   `pathseq-t2t/upstream` directory first. Run
   `./scripts/setup_pathseq_t2t.sh`; it refuses an existing destination.
   Switching wrapper branches or tags does not refresh this runtime. Verify
   the pinned upstream commit is
   `51d74430b6a4b34073f2d878612ac24b6a1d1e80` and that all four overrides
   documented in [upstream modifications](upstream-modifications.md) are
   installed. Use existing approved references and dependencies.
3. Validate Nextflow parsing/stub execution as appropriate and run small,
   representative single-end and paired-end tests using the relevant cluster
   profile. Keep run-specific parameters separate from the source checkout.
4. Review expected versus completed samples, output counts and all
   failed/ignored tasks in the trace. Sample failures may be ignored after
   retries, so overall workflow success alone is insufficient. Retain the
   workflow version record, trace and reports with the test results.
5. If fixes are needed, commit them and repeat affected validation against
   the new exact commit.

Use `run.sh` with `PROFILE="lsf"` (or the appropriate profile), or invoke
Nextflow directly against the candidate checkout. `run_lsf.sh` selects
`v0.3.3` and therefore requires that tag to exist; do not use it to validate
the unpublished candidate.

## Publication after validation

Once validation is confirmed, update this record with the tested commit and
actual results, adjust the citation date if necessary, and remove candidate
status wording from the README, execution guide and release notes as
appropriate. Review and commit those changes. Merge through the normal
reviewed workflow, then tag the intended final release commit `v0.3.3` and
create the GitHub release manually. Verify the tag points to the intended
commit and use `RELEASE_NOTES_v0.3.3.md` for the release description.

Do not tag or publish while cluster validation remains outstanding.
