# Review of paired and unpaired read counting

## Status

This document records a candidate correction to PathSeq-T2T read counting for
future validation and a possible upstream contribution. It is **not
implemented by this workflow**. Summary generation calls the pinned upstream
`pathseq-t2t summarize` command directly, preserving its counting behavior.
Any future change should be validated with regression data, discussed
upstream, and versioned explicitly.

## Final-read summary

Current upstream computation:

```python
merged['FINAL_READ_COUNT'] = paired_reads + unpaired_reads
merged['FINAL_READ_COUNT_INCLUDING_MATES'] = paired_reads + 2 * unpaired_reads
```

Candidate correction:

```python
merged['FINAL_READ_COUNT'] = paired_reads // 2 + unpaired_reads
merged['FINAL_READ_COUNT_INCLUDING_MATES'] = paired_reads + unpaired_reads
```

Rationale: `paired_reads` and `unpaired_reads` are obtained from primary BAM
record counts. The paired BAM contains two records per complete pair, whereas
the unpaired BAM contains one record per singleton.

## Kraken2

Current upstream paired computation, which is retained by the candidate
correction:

```python
dfp['reads_clade'] = 2 * dfp['reads_clade']
dfp['reads_taxon'] = 2 * dfp['reads_taxon']
```

Current upstream unpaired computation:

```python
dfu['reads_clade'] = 2 * dfu['reads_clade']
dfu['reads_taxon'] = 2 * dfu['reads_taxon']
```

Candidate correction: remove the two unpaired multiplications. Kraken paired
reports represent fragments/read pairs, while unpaired reports already
represent individual reads.

## Sylph

Current upstream domain-level computation:

```python
df_syl['sequence_abundance'] = 1.0 * df_syl['seq_p'] + 2.0 * df_syl['seq_u']
```

Candidate correction:

```python
df_syl['sequence_abundance'] = 2.0 * df_syl['seq_p'] + 1.0 * df_syl['seq_u']
```

Current upstream normalized-table computation:

```python
merged['sequence_abundance'] = 1.0 * merged['seq_p'] + 2.0 * merged['seq_u']
```

Candidate correction:

```python
merged['sequence_abundance'] = 2.0 * merged['seq_p'] + 1.0 * merged['seq_u']
```

Rationale: `seq_p` represents paired fragments and therefore corresponds to
two reads per fragment; `seq_u` represents individual unpaired reads.

## Proposed validation and upstream path

Before changing the public workflow behavior:

1. construct a minimal fixture with known paired and unpaired counts;
2. verify the units emitted by Kraken2 and Sylph directly;
3. capture upstream and candidate outputs as regression-test expectations;
4. propose the correction to the PathSeq-T2T maintainers;
5. adopt it only through an explicit workflow version or compatibility option.
