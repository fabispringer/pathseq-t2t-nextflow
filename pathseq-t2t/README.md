# Managed PathSeq-T2T runtime

Run `scripts/setup_pathseq_t2t.sh` to clone the pinned upstream PathSeq-T2T
revision into `pathseq-t2t/upstream/` and install the reviewed compatibility
fixes shipped with this workflow. The upstream summarizer is retained without
modification.

The generated `upstream/` directory is intentionally ignored by Git. The
script refuses to overwrite an existing runtime so that local changes cannot
be lost accidentally.

See `docs/upstream-modifications.md` for the rationale and licensing details.
