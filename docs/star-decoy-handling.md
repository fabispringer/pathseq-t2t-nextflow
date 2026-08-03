# STAR host alignment and non-human decoys

## Current behavior

The workflow supports two host-alignment routes:

- The BWA route runs the upstream PathSeq-T2T `prefilter` command. Reads that
  align to GRCh38 but overlap `references.decoys_to_mask` are rescued into the
  prefilter decoy BAM and continue through `qcfilter`.
- The STAR route uses STAR's explicit unmapped-read output as its
  prefilter-equivalent input. STAR-aligned reads are not inspected against the
  decoy BED, so there is no host-alignment-stage decoy rescue.

Both routes pass `references.decoys_to_mask` to `t2tfilter`. The difference is
therefore limited to the initial GRCh38 host-alignment stage:

```text
                         BWA route    STAR route
GRCh38-stage rescue          yes          no
T2T-stage rescue             yes          yes
```

## Decoy-list contents

The upstream `non_human_decoys.bed` contains 200 complete viral contigs
covering approximately 2.03 Mb:

- 189 human papillomavirus contigs;
- EBV, CMV, HBV, two HCV contigs, HIV-1, HIV-2, KSHV, HTLV-1, Merkel cell
  polyomavirus, and SV40.

It contains no bacterial contigs. In the evaluated GRCh38.d1.vd1 STAR index,
all 200 contig names are present. Viral reads can therefore align to these
contigs and be omitted from the STAR-unmapped reads that continue into
PathSeq.

## Expected effect

The missing STAR-stage rescue can materially reduce sensitivity for the
viruses represented by the BED. Its expected direct effect on bacterial count
and RPM matrices is small because the list contains no bacterial references.
Possible indirect effects include rare cross-mapping or classifier
misassignment and changes to classifier-relative percentages.

This difference is not expected to explain a large taxon-specific bacterial
discrepancy such as the observed legacy-versus-Nextflow `Mycobacterium`
difference.

## Decision and future work

For the current bacteria-focused analysis, retain the existing STAR behavior
and treat STAR-stage viral decoy rescue as deferred work. A future release may:

1. extract primary STAR alignments overlapping the decoy BED;
2. convert rescued records into a PathSeq-compatible unaligned BAM;
3. pass that BAM alongside STAR-unmapped reads through `qcfilter`;
4. validate the change on representative bacterial and virus-positive samples.

The behavior should remain documented until that implementation and validation
are complete.
