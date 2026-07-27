#!/usr/bin/env python3
"""Sum compatible STAR ReadsPerGene.out.tab files."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Sum count columns from compatible STAR ReadsPerGene tables."
    )
    parser.add_argument(
        "--input",
        action="append",
        dest="inputs",
        type=Path,
        required=True,
        help="Input ReadsPerGene.out.tab; provide at least two.",
    )
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if len(args.inputs) < 2:
        parser.error("at least two --input files are required")
    return args


def read_counts(path: Path) -> list[tuple[str, tuple[int, int, int]]]:
    rows: list[tuple[str, tuple[int, int, int]]] = []
    try:
        with path.open(encoding="utf-8") as handle:
            for line_number, line in enumerate(handle, start=1):
                fields = line.rstrip("\n").split("\t")
                if len(fields) != 4:
                    raise ValueError(
                        f"{path}:{line_number}: expected 4 tab-separated columns, "
                        f"found {len(fields)}"
                    )
                try:
                    counts = tuple(int(value) for value in fields[1:])
                except ValueError as error:
                    raise ValueError(
                        f"{path}:{line_number}: count columns must be integers"
                    ) from error
                rows.append((fields[0], counts))
    except OSError as error:
        raise ValueError(f"could not read {path}: {error}") from error
    if not rows:
        raise ValueError(f"{path}: file is empty")
    return rows


def merge_tables(paths: list[Path]) -> list[tuple[str, tuple[int, int, int]]]:
    merged = read_counts(paths[0])
    identifiers = [identifier for identifier, _ in merged]
    totals = [list(counts) for _, counts in merged]

    for path in paths[1:]:
        rows = read_counts(path)
        other_identifiers = [identifier for identifier, _ in rows]
        if other_identifiers != identifiers:
            raise ValueError(
                f"{path}: row identifiers or order do not match {paths[0]}"
            )
        for total, (_, counts) in zip(totals, rows):
            for index, count in enumerate(counts):
                total[index] += count

    return [
        (identifier, (counts[0], counts[1], counts[2]))
        for identifier, counts in zip(identifiers, totals)
    ]


def main() -> int:
    args = parse_args()
    try:
        rows = merge_tables(args.inputs)
        args.output.parent.mkdir(parents=True, exist_ok=True)
        temporary = args.output.with_name(f"{args.output.name}.tmp")
        with temporary.open("w", encoding="utf-8") as handle:
            for identifier, counts in rows:
                handle.write(
                    f"{identifier}\t{counts[0]}\t{counts[1]}\t{counts[2]}\n"
                )
        temporary.replace(args.output)
    except ValueError as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
