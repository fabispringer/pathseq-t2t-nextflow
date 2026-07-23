#!/usr/bin/env python3
"""Collate STAR ReadsPerGene.out tables into cohort-level matrices."""

from __future__ import annotations

import argparse
import csv
from pathlib import Path


SUFFIX = ".star.ReadsPerGene.out.tsv"
QC_ROWS = ("N_unmapped", "N_multimapping", "N_noFeature", "N_ambiguous")
COLUMNS = {
    "unstranded": 1,
    "forward": 2,
    "reverse": 3,
}


def sample_id(path: Path) -> str:
    if not path.name.endswith(SUFFIX):
        raise ValueError(f"Unexpected STAR count filename: {path.name!r}; expected *{SUFFIX}")
    value = path.name[: -len(SUFFIX)]
    if not value:
        raise ValueError(f"Could not derive sample ID from {path}")
    return value


def read_table(path: Path) -> tuple[list[str], list[list[int]], list[str], list[list[int]]]:
    rows: list[list[str]] = []
    with path.open(newline="") as handle:
        for line_number, row in enumerate(csv.reader(handle, delimiter="\t"), 1):
            if len(row) != 4:
                raise ValueError(f"{path}:{line_number}: expected 4 tab-separated columns, found {len(row)}")
            rows.append(row)
    if len(rows) < 5:
        raise ValueError(f"{path}: expected four QC rows and at least one gene row")
    observed_qc = tuple(row[0] for row in rows[:4])
    if observed_qc != QC_ROWS:
        raise ValueError(f"{path}: unexpected QC rows {observed_qc}; expected {QC_ROWS}")

    identifiers = [row[0] for row in rows]
    if len(identifiers) != len(set(identifiers)):
        raise ValueError(f"{path}: duplicate gene or QC identifiers")
    values: list[list[int]] = []
    for line_number, row in enumerate(rows, 1):
        try:
            values.append([int(value) for value in row[1:]])
        except ValueError as error:
            raise ValueError(f"{path}:{line_number}: counts must be integers") from error
    return identifiers[:4], values[:4], identifiers[4:], values[4:]


def write_matrix(
    path: Path,
    row_label: str,
    row_ids: list[str],
    samples: list[str],
    sample_values: dict[str, list[list[int]]],
    value_index: int,
) -> None:
    with path.open("w", newline="") as handle:
        writer = csv.writer(handle, delimiter="\t", lineterminator="\n")
        writer.writerow([row_label, *samples])
        for row_index, identifier in enumerate(row_ids):
            writer.writerow([identifier, *(sample_values[sample][row_index][value_index] for sample in samples)])


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", required=True, type=Path)
    parser.add_argument("--expected-sample", action="append", default=[])
    parser.add_argument("inputs", nargs="+", type=Path)
    args = parser.parse_args()

    tables: dict[str, tuple[list[str], list[list[int]], list[str], list[list[int]]]] = {}
    for path in args.inputs:
        sample = sample_id(path)
        if sample in tables:
            raise ValueError(f"Duplicate sample ID: {sample}")
        tables[sample] = read_table(path)
    samples = sorted(tables)
    expected_samples = sorted(args.expected_sample)
    if expected_samples and samples != expected_samples:
        raise ValueError(
            "STAR count samples do not match completed pipeline samples; "
            f"count files={samples}, completed={expected_samples}"
        )

    reference_qc, _, reference_genes, _ = tables[samples[0]]
    for sample in samples[1:]:
        qc_ids, _, genes, _ = tables[sample]
        if qc_ids != reference_qc:
            raise ValueError(f"{sample}: QC identifiers or order differ from {samples[0]}")
        if genes != reference_genes:
            raise ValueError(
                f"{sample}: gene identifiers or order differ from {samples[0]}; "
                "verify that all STAR runs used the same annotation"
            )

    args.output_dir.mkdir(parents=True, exist_ok=True)
    qc_values = {sample: tables[sample][1] for sample in samples}
    gene_values = {sample: tables[sample][3] for sample in samples}
    for label, column_index in COLUMNS.items():
        value_index = column_index - 1
        write_matrix(
            args.output_dir / f"host_gene_counts.{label}.tsv",
            "ENSEMBL",
            reference_genes,
            samples,
            gene_values,
            value_index,
        )
        write_matrix(
            args.output_dir / f"host_gene_counting_qc.{label}.tsv",
            "metric",
            reference_qc,
            samples,
            qc_values,
            value_index,
        )

    print(f"Collated {len(samples)} samples and {len(reference_genes)} genes into {args.output_dir}")


if __name__ == "__main__":
    main()
