#!/usr/bin/env python3
"""Regression tests for Kraken cohort collation numeric parsing."""

from __future__ import annotations

import subprocess
import sys
import tempfile
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
SCRIPT = REPO_ROOT / "scripts" / "collate_kraken_results.py"


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
        taxonomy = test_dir / "taxonomy.tsv"
        taxonomy.write_text(
            "tax_id\tparent_tax_id\tname\trank\tdomain_tax_id\tdomain\n"
            "2\t1\tBacteria\tD\t2\tBacteria\n"
            "46123\t2\tTest species\tS\t2\tBacteria\n",
            encoding="utf-8",
        )
        sample = test_dir / "sample.kraken.txt"
        header = (
            "name\ttax_id\trank\treads_clade\treads_taxon\t"
            "reads_clade_per_million\treads_taxon_per_million\tpct_reads\n"
        )
        sample.write_text(
            header
            + "Bacteria\t2\tD\t6.0\t1.0\t60.0\t10.0\t60.0\n"
            + "Test species\t46123\tS\t6.0\t6.0\t60.0\t60.0\t60.0\n",
            encoding="utf-8",
        )
        output_dir = test_dir / "output"
        result = run(
            "--taxonomy",
            str(taxonomy),
            "--output-dir",
            str(output_dir),
            str(sample),
        )
        assert result.returncode == 0, result.stderr
        species_counts = (output_dir / "kraken_species_counts.tsv").read_text(
            encoding="utf-8"
        )
        assert "46123\t6\n" in species_counts
        assert "46123\t6.0\n" not in species_counts

        sample.write_text(
            header + "Test species\t46123\tS\t6.5\t6\t60.0\t60.0\t60.0\n",
            encoding="utf-8",
        )
        result = run(
            "--taxonomy",
            str(taxonomy),
            "--output-dir",
            str(output_dir),
            str(sample),
        )
        assert result.returncode != 0
        assert "must be a nonnegative integer" in result.stderr

    print("collate_kraken_results tests passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
