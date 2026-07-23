#!/usr/bin/env python3
"""Convert kraken2-inspect hierarchy output into a tabular taxonomy."""

from __future__ import annotations

import argparse
import csv
from dataclasses import dataclass
from pathlib import Path


DOMAINS = {
    "2": "Bacteria",
    "2157": "Archaea",
    "2759": "Eukaryota",
    "10239": "Viruses",
}


@dataclass
class Node:
    indent: int
    tax_id: str
    domain_tax_id: str
    domain: str


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--inspect", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()

    rows: list[list[str]] = []
    stack: list[Node] = []
    observed: set[str] = set()
    with args.inspect.open(newline="") as handle:
        for line_number, row in enumerate(csv.reader(handle, delimiter="\t"), 1):
            if len(row) < 6:
                raise ValueError(f"{args.inspect}:{line_number}: expected at least 6 columns")
            rank, tax_id, indented_name = row[-3:]
            name = indented_name.lstrip(" ")
            indent = len(indented_name) - len(name)
            if not tax_id or tax_id in observed:
                if tax_id in observed:
                    raise ValueError(f"{args.inspect}:{line_number}: duplicate tax ID {tax_id}")
                raise ValueError(f"{args.inspect}:{line_number}: empty tax ID")
            while stack and stack[-1].indent >= indent:
                stack.pop()
            parent_tax_id = stack[-1].tax_id if stack else ""
            if tax_id in DOMAINS:
                domain_tax_id, domain = tax_id, DOMAINS[tax_id]
            elif stack:
                domain_tax_id, domain = stack[-1].domain_tax_id, stack[-1].domain
            else:
                domain_tax_id, domain = "", ""
            rows.append([tax_id, parent_tax_id, name, rank, domain_tax_id, domain])
            observed.add(tax_id)
            stack.append(Node(indent, tax_id, domain_tax_id, domain))

    missing = sorted(set(DOMAINS) - observed)
    if missing:
        raise ValueError(f"Kraken taxonomy is missing required domain tax IDs: {missing}")
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("w", newline="") as handle:
        writer = csv.writer(handle, delimiter="\t", lineterminator="\n")
        writer.writerow(["tax_id", "parent_tax_id", "name", "rank", "domain_tax_id", "domain"])
        writer.writerows(rows)
    print(f"Prepared {len(rows)} Kraken taxonomy nodes in {args.output}")


if __name__ == "__main__":
    main()
