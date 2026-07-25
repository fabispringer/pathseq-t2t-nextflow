#!/usr/bin/env python3
"""Tests for merge_star_gene_counts.py without external test dependencies."""

from __future__ import annotations

import subprocess
import sys
import tempfile
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
SCRIPT = REPO_ROOT / "scripts" / "merge_star_gene_counts.py"


def write_table(path: Path, rows: list[tuple[str, int, int, int]]) -> None:
    path.write_text(
        "".join(
            f"{identifier}\t{unstranded}\t{forward}\t{reverse}\n"
            for identifier, unstranded, forward, reverse in rows
        ),
        encoding="utf-8",
    )


def run(*arguments: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, str(SCRIPT), *arguments],
        check=False,
        capture_output=True,
        text=True,
    )


def main() -> int:
    with tempfile.TemporaryDirectory() as temporary_directory:
        test_dir = Path(temporary_directory)
        paired = test_dir / "paired.tab"
        single = test_dir / "single.tab"
        output = test_dir / "merged.tab"

        write_table(
            paired,
            [
                ("N_unmapped", 1, 2, 3),
                ("N_multimapping", 4, 5, 6),
                ("gene_a", 10, 11, 12),
            ],
        )
        write_table(
            single,
            [
                ("N_unmapped", 7, 8, 9),
                ("N_multimapping", 1, 2, 3),
                ("gene_a", 20, 21, 22),
            ],
        )
        result = run(
            "--input",
            str(paired),
            "--input",
            str(single),
            "--output",
            str(output),
        )
        assert result.returncode == 0, result.stderr
        assert output.read_text(encoding="utf-8") == (
            "N_unmapped\t8\t10\t12\n"
            "N_multimapping\t5\t7\t9\n"
            "gene_a\t30\t32\t34\n"
        )

        mismatched = test_dir / "mismatched.tab"
        write_table(mismatched, [("different_gene", 1, 1, 1)])
        result = run(
            "--input",
            str(paired),
            "--input",
            str(mismatched),
            "--output",
            str(output),
        )
        assert result.returncode != 0
        assert "do not match" in result.stderr

        malformed = test_dir / "malformed.tab"
        malformed.write_text("gene_a\t1\t2\n", encoding="utf-8")
        result = run(
            "--input",
            str(paired),
            "--input",
            str(malformed),
            "--output",
            str(output),
        )
        assert result.returncode != 0
        assert "expected 4" in result.stderr

    print("merge_star_gene_counts tests passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
