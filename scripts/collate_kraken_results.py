#!/usr/bin/env python3
"""Collate Dohlman Kraken clade counts and RPM by taxonomic rank and tax ID."""

from __future__ import annotations

import argparse
import csv
from pathlib import Path


SUFFIX = ".kraken.txt"
TARGET_DOMAINS = {"Bacteria", "Archaea"}
# Kraken's standard rank codes. Keeping the output levels here makes it explicit
# which cohort matrices are produced by default.
RANKS = {
    "phylum": "P",
    "class": "C",
    "order": "O",
    "family": "F",
    "genus": "G",
    "species": "S",
}


def sample_id(path: Path) -> str:
    if not path.name.endswith(SUFFIX):
        raise ValueError(f"Unexpected Kraken filename {path.name!r}; expected *{SUFFIX}")
    return path.name[: -len(SUFFIX)]


def read_taxonomy(path: Path) -> tuple[dict[str, dict[str, str]], list[dict[str, str]]]:
    with path.open(newline="") as handle:
        rows = list(csv.DictReader(handle, delimiter="\t"))
    expected = {"tax_id", "parent_tax_id", "name", "rank", "domain_tax_id", "domain"}
    if not rows or set(rows[0]) != expected:
        raise ValueError(f"{path}: unexpected taxonomy columns")
    indexed = {row["tax_id"]: row for row in rows}
    if len(indexed) != len(rows):
        raise ValueError(f"{path}: duplicate tax IDs")
    return indexed, rows


def read_sample(path: Path, taxonomy: dict[str, dict[str, str]]) -> dict[str, dict[str, str]]:
    with path.open(newline="") as handle:
        rows = list(csv.DictReader(handle, delimiter="\t"))
    required = {
        "name", "tax_id", "rank", "reads_clade", "reads_taxon",
        "reads_clade_per_million", "reads_taxon_per_million", "pct_reads",
    }
    if not rows or set(rows[0]) != required:
        raise ValueError(f"{path}: unexpected Kraken result columns")
    indexed: dict[str, dict[str, str]] = {}
    for row in rows:
        tax_id = row["tax_id"]
        if tax_id in indexed:
            raise ValueError(f"{path}: duplicate tax ID {tax_id}")
        if tax_id == "0" and tax_id not in taxonomy:
            if row["name"] != "unclassified" or row["rank"] != "U":
                raise ValueError(f"{path}: unexpected representation of unclassified tax ID 0")
            indexed[tax_id] = row
            continue
        if tax_id not in taxonomy:
            raise ValueError(f"{path}: tax ID {tax_id} is absent from the configured Kraken taxonomy")
        taxon = taxonomy[tax_id]
        if row["name"] != taxon["name"] or row["rank"] != taxon["rank"]:
            raise ValueError(
                f"{path}: taxonomy mismatch for tax ID {tax_id}: "
                f"result=({row['name']!r}, {row['rank']!r}), "
                f"database=({taxon['name']!r}, {taxon['rank']!r})"
            )
        try:
            int(row["reads_clade"])
            float(row["reads_clade_per_million"])
        except ValueError as error:
            raise ValueError(f"{path}: invalid clade count or RPM for tax ID {tax_id}") from error
        indexed[tax_id] = row
    return indexed


def write_matrix(
    path: Path,
    tax_ids: list[str],
    samples: list[str],
    sample_rows: dict[str, dict[str, dict[str, str]]],
    field: str,
    totals: dict[str, str],
) -> None:
    zero = "0" if field == "reads_clade" else "0.0"
    with path.open("w", newline="") as handle:
        writer = csv.writer(handle, delimiter="\t", lineterminator="\n")
        writer.writerow(["tax_id", *samples])
        writer.writerow(["Bacteria", *(totals[sample] for sample in samples)])
        for tax_id in tax_ids:
            writer.writerow([
                tax_id,
                *(sample_rows[sample].get(tax_id, {}).get(field, zero) for sample in samples),
            ])


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--taxonomy", required=True, type=Path)
    parser.add_argument("--output-dir", required=True, type=Path)
    parser.add_argument("inputs", nargs="+", type=Path)
    args = parser.parse_args()

    taxonomy, taxonomy_rows = read_taxonomy(args.taxonomy)
    sample_rows: dict[str, dict[str, dict[str, str]]] = {}
    for path in args.inputs:
        sample = sample_id(path)
        if sample in sample_rows:
            raise ValueError(f"Duplicate sample ID {sample}")
        sample_rows[sample] = read_sample(path, taxonomy)
    samples = sorted(sample_rows)

    args.output_dir.mkdir(parents=True, exist_ok=True)
    with (args.output_dir / "kraken_taxonomy.tsv").open("w", newline="") as handle:
        writer = csv.DictWriter(
            handle,
            fieldnames=["tax_id", "parent_tax_id", "name", "rank", "domain_tax_id", "domain"],
            delimiter="\t",
            lineterminator="\n",
        )
        writer.writeheader()
        writer.writerows(taxonomy_rows)

    counts_total: dict[str, str] = {}
    rpm_total: dict[str, str] = {}
    for sample, rows in sample_rows.items():
        # The historical liver-atlas tables use a row labelled "Bacteria" for
        # the combined bacterial and archaeal signal.
        domain_rows = [rows.get(tax_id) for tax_id in ("2", "2157")]
        counts_total[sample] = str(sum(int(row["reads_clade"]) for row in domain_rows if row))
        rpm_total[sample] = str(sum(float(row["reads_clade_per_million"]) for row in domain_rows if row))

    for label, rank in RANKS.items():
        # Build the cohort-wide union of observed taxa at this rank. Domain
        # membership comes from the kraken2-inspect hierarchy, so eukaryotic
        # and viral rows are excluded by lineage rather than by taxon name.
        tax_ids = sorted(
            {
                tax_id
                for rows in sample_rows.values()
                for tax_id, row in rows.items()
                if row["rank"] == rank and taxonomy[tax_id]["domain"] in TARGET_DOMAINS
            },
            key=int,
        )
        write_matrix(
            args.output_dir / f"kraken_{label}_counts.tsv",
            tax_ids, samples, sample_rows, "reads_clade", counts_total,
        )
        write_matrix(
            args.output_dir / f"kraken_{label}_rpm.tsv",
            tax_ids, samples, sample_rows, "reads_clade_per_million", rpm_total,
        )
    print(f"Collated Kraken profiles at {len(RANKS)} ranks for {len(samples)} samples")


if __name__ == "__main__":
    main()
