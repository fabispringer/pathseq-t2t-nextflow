#!/usr/bin/env python3
"""Collate direct read-count QC metrics and selected Dohlman summary values."""

from __future__ import annotations

import argparse
import csv
from pathlib import Path


SUFFIXES = {
    "raw": ".raw_fastqc_counts.tsv",
    "post": ".post_fastqc_counts.tsv",
    "host": ".host_alignment.flagstat.tsv",
    "summary": ".summary.tsv",
    "filter": ".prefilter.unaligned.filter_metrics.txt",
    "t2t_paired": ".qcfilt_paired.t2t_unaln.flagstat.tsv",
    "t2t_unpaired": ".qcfilt_unpaired.t2t_unaln.flagstat.tsv",
}

DIRECT_FIELDS = [
    "input_r1_read_ends", "input_r2_read_ends", "input_unpaired_read_ends",
    "input_total_read_ends", "post_qc_r1_read_ends", "post_qc_r2_read_ends",
    "post_qc_unpaired_read_ends", "post_qc_total_read_ends", "read_qc_removed_read_ends",
    "read_qc_retained_pct", "host_input_read_ends", "host_mapped_primary_read_ends",
    "host_unmapped_primary_read_ends", "host_mapped_pct", "pathseq_primary_read_ends",
    "pathseq_after_prealigned_host_filter_read_ends",
    "pathseq_after_quality_complexity_filter_read_ends", "pathseq_after_host_filter_read_ends",
    "pathseq_after_deduplication_read_ends", "pathseq_final_paired_read_ends",
    "pathseq_final_unpaired_read_ends", "pathseq_final_total_read_ends",
    "t2t_output_paired_read_ends", "t2t_output_unpaired_read_ends",
    "t2t_output_total_read_ends",
]

DOHLMAN_FIELDS = {
    "PRIMARY_READS": "dohlman_primary_reads",
    "FINAL_READ_COUNT": "dohlman_final_read_count",
    "FINAL_READ_COUNT_INCLUDING_MATES": "dohlman_final_read_count_including_mates",
    "UNCLASSIFIED_READS_K2": "dohlman_unclassified_reads_k2",
    "CLASSIFIED_READS_K2": "dohlman_classified_reads_k2",
    "MICROBIAL_READS_K2": "dohlman_microbial_reads_k2",
    "BACTERIAL_READS_K2": "dohlman_bacterial_reads_k2",
    "CLASSIFICATION_RATE_K2": "dohlman_classification_rate_k2",
}

LONG_META = {
    "input": "input",
    "post_qc": "read_qc",
    "read_qc": "read_qc",
    "host": "host_alignment",
    "pathseq": "pathseq_qcfilter",
    "t2t": "t2tfilter",
}


def sample_from_suffix(path: Path, suffix: str) -> str:
    if not path.name.endswith(suffix):
        raise ValueError(f"Unexpected filename {path.name!r}; expected *{suffix}")
    return path.name[: -len(suffix)]


def read_key_values(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    with path.open(newline="") as handle:
        for row in csv.reader(handle, delimiter="\t"):
            if not row or row[0] in {"metric", "sample_id"}:
                continue
            if len(row) < 2:
                raise ValueError(f"{path}: expected at least two tab-separated columns")
            values[row[0]] = row[1]
    return values


def integer(value: str, path: Path, metric: str) -> int:
    try:
        return int(value)
    except ValueError as error:
        raise ValueError(f"{path}: {metric} is not an integer: {value!r}") from error


def read_fastqc_counts(path: Path) -> dict[str, int]:
    values = read_key_values(path)
    missing = {"r1_reads", "r2_reads"} - values.keys()
    if missing:
        raise ValueError(f"{path}: missing metrics {sorted(missing)}")
    return {
        key: integer(values.get(key, "0"), path, key)
        for key in ("r1_reads", "r2_reads", "unpaired_reads")
    }


def read_flagstat(path: Path) -> dict[str, int]:
    values: dict[str, int] = {}
    with path.open(newline="") as handle:
        for row in csv.reader(handle, delimiter="\t"):
            if len(row) >= 3:
                try:
                    values[row[2]] = int(row[0])
                except ValueError:
                    continue
    return values


def read_filter_metrics(path: Path) -> dict[str, int]:
    lines = [line.rstrip("\n") for line in path.open()]
    for index, line in enumerate(lines):
        if line.startswith("PRIMARY_READS\t"):
            headers = line.split("\t")
            if index + 1 >= len(lines):
                break
            values = lines[index + 1].split("\t")
            if len(headers) != len(values):
                raise ValueError(f"{path}: PathSeq filter header/value length mismatch")
            return {key: integer(value, path, key) for key, value in zip(headers, values)}
    raise ValueError(f"{path}: PathSeq filter metrics table not found")


def index_paths(paths: list[Path], suffix: str) -> dict[str, Path]:
    indexed: dict[str, Path] = {}
    for path in paths:
        sample = sample_from_suffix(path, suffix)
        if sample in indexed:
            raise ValueError(f"Duplicate file for sample {sample}: {path}")
        indexed[sample] = path
    return indexed


def percent(numerator: int, denominator: int) -> str:
    return "" if denominator == 0 else f"{100.0 * numerator / denominator:.6f}"


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", required=True, type=Path)
    parser.add_argument("--aligner", required=True, choices=("star", "bwa"))
    parser.add_argument("--raw-count", action="append", required=True, type=Path)
    parser.add_argument("--post-count", action="append", required=True, type=Path)
    parser.add_argument("--host-flagstat", action="append", required=True, type=Path)
    parser.add_argument("--pathseq-metric", action="append", required=True, type=Path)
    args = parser.parse_args()

    raw = index_paths(args.raw_count, SUFFIXES["raw"])
    post = index_paths(args.post_count, SUFFIXES["post"])
    host = index_paths(args.host_flagstat, SUFFIXES["host"])
    groups = {
        key: index_paths([path for path in args.pathseq_metric if path.name.endswith(suffix)], suffix)
        for key, suffix in SUFFIXES.items()
        if key in {"summary", "filter", "t2t_paired", "t2t_unpaired"}
    }
    sample_sets = {"raw": set(raw), "post": set(post), "host": set(host)}
    sample_sets.update({key: set(value) for key, value in groups.items()})
    reference = set(raw)
    mismatched = {key: sorted(value) for key, value in sample_sets.items() if value != reference}
    if mismatched:
        raise ValueError(f"QC input sample sets differ: {mismatched}")

    rows: list[dict[str, object]] = []
    for sample in sorted(reference):
        raw_counts = read_fastqc_counts(raw[sample])
        post_counts = read_fastqc_counts(post[sample])
        host_counts = read_flagstat(host[sample])
        filter_counts = read_filter_metrics(groups["filter"][sample])
        paired_t2t = read_flagstat(groups["t2t_paired"][sample]).get(
            "total (QC-passed reads + QC-failed reads)", 0
        )
        unpaired_t2t = read_flagstat(groups["t2t_unpaired"][sample]).get(
            "total (QC-passed reads + QC-failed reads)", 0
        )
        summary = read_key_values(groups["summary"][sample])
        input_total = sum(raw_counts.values())
        post_total = sum(post_counts.values())
        host_mapped = host_counts.get("primary mapped", host_counts.get("mapped", 0))

        row: dict[str, object] = {
            "sample_id": sample,
            "aligner": args.aligner,
            "input_r1_read_ends": raw_counts["r1_reads"],
            "input_r2_read_ends": raw_counts["r2_reads"],
            "input_unpaired_read_ends": raw_counts["unpaired_reads"],
            "input_total_read_ends": input_total,
            "post_qc_r1_read_ends": post_counts["r1_reads"],
            "post_qc_r2_read_ends": post_counts["r2_reads"],
            "post_qc_unpaired_read_ends": post_counts["unpaired_reads"],
            "post_qc_total_read_ends": post_total,
            "read_qc_removed_read_ends": input_total - post_total,
            "read_qc_retained_pct": percent(post_total, input_total),
            "host_input_read_ends": post_total,
            "host_mapped_primary_read_ends": host_mapped,
            "host_unmapped_primary_read_ends": post_total - host_mapped,
            "host_mapped_pct": percent(host_mapped, post_total),
            "pathseq_primary_read_ends": filter_counts["PRIMARY_READS"],
            "pathseq_after_prealigned_host_filter_read_ends": filter_counts["READS_AFTER_PREALIGNED_HOST_FILTER"],
            "pathseq_after_quality_complexity_filter_read_ends": filter_counts["READS_AFTER_QUALITY_AND_COMPLEXITY_FILTER"],
            "pathseq_after_host_filter_read_ends": filter_counts["READS_AFTER_HOST_FILTER"],
            "pathseq_after_deduplication_read_ends": filter_counts["READS_AFTER_DEDUPLICATION"],
            "pathseq_final_paired_read_ends": filter_counts["FINAL_PAIRED_READS"],
            "pathseq_final_unpaired_read_ends": filter_counts["FINAL_UNPAIRED_READS"],
            "pathseq_final_total_read_ends": filter_counts["FINAL_TOTAL_READS"],
            "t2t_output_paired_read_ends": paired_t2t,
            "t2t_output_unpaired_read_ends": unpaired_t2t,
            "t2t_output_total_read_ends": paired_t2t + unpaired_t2t,
        }
        for source, destination in DOHLMAN_FIELDS.items():
            row[destination] = summary.get(source, "")
        rows.append(row)

    args.output_dir.mkdir(parents=True, exist_ok=True)
    fields = ["sample_id", "aligner", *DIRECT_FIELDS, *DOHLMAN_FIELDS.values()]
    with (args.output_dir / "read_count_summary.tsv").open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields, delimiter="\t", lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)

    with (args.output_dir / "read_count_long.tsv").open("w", newline="") as handle:
        writer = csv.writer(handle, delimiter="\t", lineterminator="\n")
        writer.writerow(["sample_id", "aligner", "stage", "metric", "value", "unit", "source"])
        for row in rows:
            for field in DIRECT_FIELDS:
                prefix = next((key for key in LONG_META if field.startswith(key)), "pathseq")
                unit = "percent" if field.endswith("_pct") else "read_ends"
                writer.writerow([row["sample_id"], args.aligner, LONG_META[prefix], field, row[field], unit, "direct_tool_metric"])
            for field in DOHLMAN_FIELDS.values():
                unit = "percent" if field.endswith("rate_k2") else "upstream_reported_count"
                writer.writerow([row["sample_id"], args.aligner, "dohlman_summary", field, row[field], unit, "pathseq_t2t_summarize"])

    print(f"Collated read-count QC for {len(rows)} samples into {args.output_dir}")


if __name__ == "__main__":
    main()
