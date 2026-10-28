# v0.3.3 release preparation

Updated: 2026-10-28. This guide describes preparation and publication; it is
not a publication record.

## Release scope

- Explicit paired/single FASTQ layout selection, recursive single-end
  discovery with duplicate detection, and three-stream staging with valid
  empty gzip placeholders.
- Synchronous prefilter BAM creation, temporary-output checking and cleanup,
  and runtime override installation.
- Version 0.3.3 in the manifest, citation, launchers and consistency check.
- Explicit input mode, FASTQ layout, host-aligner and executor selections.
- Per-run launchers and parameter files with a separate source checkout.
- Prefilter and launcher regression coverage.
- Python 3.11 and ripgrep repository-check prerequisites.
- Updated operating documentation, notices and release notes.

Single-end discovery deliberately does not select R2 files. Prefilter outputs
are promoted by separate renames, not as one atomic output set.

The pipeline overview and technical process-map diagrams are deferred and
excluded from v0.3.3. The README no longer references unfinished images.
Track completion in [documentation todos](todo.md).

## Prepare the pull request

1. Work on `release/v0.3.3` and preserve unrelated local edits.
2. Review the intended changes with `git diff`. Keep local configuration,
   real parameters, data, references, generated runtimes and work directories
   out of the commit.
3. Run `bash tests/check_repository.sh` and `git diff --check` in the
   documented software environment.
4. Review and commit only the intended files, then push the release branch.
5. Open a pull request with base `main`, compare `release/v0.3.3`, and title
   `Release v0.3.3`. Summarize the changes using
   [the release notes](../RELEASE_NOTES_v0.3.3.md).

The single-end feature changes are already included in the release branch;
do not merge the feature branch separately.

## Publish

1. Confirm the intended publication date. If it differs from `2026-10-28`,
   update `date-released` in `CITATION.cff` in the release pull request.
2. Review and merge the release pull request into `main`.
3. Create the immutable tag `v0.3.3` at the intended merged release commit.
   Verify that the tag points to that commit.
4. Create a normal GitHub release titled `v0.3.3`, using
   `RELEASE_NOTES_v0.3.3.md` as the description. Do not mark it as a prerelease.
5. Confirm that the published tag, source files, release notes and launcher
   pins all identify `v0.3.3`. Keep the working branches until the published
   release has been checked; branch deletion is optional cleanup afterward.

## Upgrade notes

Switching wrapper branches or tags does not refresh the ignored managed
runtime. Preserve an existing `pathseq-t2t/upstream` directory before running
`./scripts/setup_pathseq_t2t.sh`; setup refuses an existing destination.
The pinned upstream commit is
`51d74430b6a4b34073f2d878612ac24b6a1d1e80`. Setup installs the four reviewed
overrides documented in [upstream modifications](upstream-modifications.md).

Keep site-specific configuration and run files separate from the source
checkout. Use `run.sh` with the appropriate `PROFILE` before publication;
`run_lsf.sh` selects `v0.3.3` and requires that tag to exist.
