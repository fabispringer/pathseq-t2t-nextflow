#!/usr/bin/env python3
"""Report whether a gzip-compressed FASTQ stream contains any data."""

from __future__ import annotations

import argparse
import gzip
import sys
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("fastq", type=Path)
    args = parser.parse_args()

    try:
        with gzip.open(args.fastq, "rb") as handle:
            first_byte = handle.read(1)
    except (OSError, EOFError) as error:
        print(f"ERROR: Could not read gzip FASTQ {args.fastq}: {error}", file=sys.stderr)
        return 1

    print("nonempty" if first_byte else "empty")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
