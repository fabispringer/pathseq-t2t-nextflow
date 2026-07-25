#!/usr/bin/env python3
"""Tests for gzip FASTQ content-state detection."""

from __future__ import annotations

import gzip
import subprocess
import sys
import tempfile
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
SCRIPT = REPO_ROOT / "scripts" / "check_fastq_content.py"


def run(path: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, str(SCRIPT), str(path)],
        check=False,
        capture_output=True,
        text=True,
    )


def main() -> int:
    with tempfile.TemporaryDirectory() as temporary_directory:
        test_dir = Path(temporary_directory)

        empty = test_dir / "empty.fastq.gz"
        with gzip.open(empty, "wb"):
            pass
        result = run(empty)
        assert result.returncode == 0, result.stderr
        assert result.stdout.strip() == "empty"

        nonempty = test_dir / "nonempty.fastq.gz"
        with gzip.open(nonempty, "wb") as handle:
            handle.write(b"@read\nACGT\n+\nIIII\n")
        result = run(nonempty)
        assert result.returncode == 0, result.stderr
        assert result.stdout.strip() == "nonempty"

        corrupt = test_dir / "corrupt.fastq.gz"
        corrupt.write_bytes(b"not a gzip stream")
        result = run(corrupt)
        assert result.returncode != 0
        assert "Could not read gzip FASTQ" in result.stderr
        assert str(corrupt) in result.stderr

        missing = test_dir / "missing.fastq.gz"
        result = run(missing)
        assert result.returncode != 0
        assert "Could not read gzip FASTQ" in result.stderr
        assert str(missing) in result.stderr

    print("check_fastq_content tests passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
