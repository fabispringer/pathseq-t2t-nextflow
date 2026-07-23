# Reference preparation

The workflow keeps reference databases outside the Git repository. They are
large, installation-specific resources and should normally live on shared
project storage or a dedicated database volume.

## Default preparation

Create all references required by the default STAR/Kraken route:

```bash
./scripts/prepare_references.sh \
  --db-root /path/to/pathseq-t2t-db \
  --threads 16
```

The database root can instead be exported:

```bash
export PST2T_DB_ROOT=/path/to/pathseq-t2t-db
./scripts/prepare_references.sh --threads 16
```

There is deliberately no implicit database location. If neither `--db-root`
nor `PST2T_DB_ROOT` is supplied, the script exits without downloading.
Repository-local storage remains possible when explicitly requested with
`--db-root ./references`; that directory is ignored by Git.

The default component set is:

```text
grch38,star,pathseq-host,t2t,kraken
```

Select a subset with, for example:

```bash
./scripts/prepare_references.sh \
  --db-root /path/to/pathseq-t2t-db \
  --components grch38,star \
  --threads 16
```

The script uses resumable downloads and skips valid completed products. It is
safe to rerun after an interrupted download or index build.

## Pinned resources

- GDC GRCh38.d1.vd1 reference genome
- GDC GENCODE v36 annotation
- STAR index built with `sjdbOverhang=100`
- Broad/GATK PathSeq host-filter bundle
- NCBI T2T-CHM13v2.0 reference genome
- Kraken2 PlusPF database dated 2024-06-05
- Picard 3.4.0 from the `pathseq-t2t-nextflow` Conda environment

The Broad server does not publish a checksum alongside its PathSeq host
archive. For that archive the script verifies the published byte size, gzip
archive integrity, and required extracted files. Downloads with published MD5
values are checked against those values. Large versioned archives without
published checksums are checked by their published byte size and archive
integrity.

The complete database set requires substantial storage. Allow well over
200 GB for compressed downloads, extracted references, and generated indexes.
The script checks available space but does not attempt to predict filesystem
quotas.

## Picard

Picard is not downloaded separately. The environment pins Picard 3.4.0, and
the script locates `picard.jar` below the active Conda environment. Activate
the environment before preparing references:

```bash
mamba activate pathseq-t2t-nextflow
```

If the environment is not active, reference preparation still works, but the
generated parameter template leaves `tools.picard_jar` empty and prints a
warning.

## Optional classifiers

The preparation script covers the default Kraken classifier. MetaPhlAn and
Sylph databases are not downloaded automatically because users may need
different database releases and taxonomic scopes. Configure their indexes
explicitly through `parameters.yaml` when enabling those classifiers.

## Generated parameter template

After successful preparation, the script writes:

```text
<db-root>/pathseq-t2t-nextflow.references.yaml
```

Copy the `tools` and `references` entries from that file into the local
`parameters.yaml`.
