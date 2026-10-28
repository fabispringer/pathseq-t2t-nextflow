#!/usr/bin/env python3
"""Exercise prefilter argument parsing and thread defaults with mocked helpers.

Run the exact function prefix up to the BAM-filtering setup, then report the
parsed values. This keeps the tests independent of samtools, BAM contents,
and Bash 4's lowercase expansion in the downstream filtering code.
"""

from __future__ import annotations

import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / "overrides/prefilter.sh").read_text()
PARSER = SOURCE[:SOURCE.index("  local -a L_ARG=()")] + """
  printf '%s\t%s\t%s\t%s\\n' "$input_bam" "$aligner" "$decoys_to_mask" "$threads"
}
"""

HELPERS = """
set -euo pipefail
die() { printf '%s\\n' "$*" >&2; exit 1; }
require_nonempty() { [[ -n "$1" ]] || die "Missing required option: $2"; }
require_file() { [[ -f "$1" ]] || die "Missing fixture file: $1"; }
_require_samtools_116() { :; }
bam_check_or_die() { :; }
source "$PARSER_FILE"
OSTYPE="$TEST_OSTYPE"
"""


class PrefilterArgumentTests(unittest.TestCase):
    def run_parser(self, *, omit=(), threads=None, globals_=False,
                   after="", nproc="16", sysctl=None, ostype="linux-gnu"):
        with tempfile.TemporaryDirectory(prefix="prefilter arguments ") as directory:
            root = Path(directory)
            input_bam = root / "input.bam"
            input_bam.touch()
            parser_file = root / "parser.sh"
            parser_file.write_text(PARSER)
            for name, value in (("nproc", nproc), ("sysctl", sysctl)):
                if value is not None:
                    executable = root / name
                    executable.write_text(f"#!/bin/sh\nprintf '%s\\n' '{value}'\n")
                    executable.chmod(0o755)

            arguments = []
            for option, value in (
                ("--input-bam", str(input_bam)),
                ("--aligner", "bwa"),
                ("--decoys-to-mask", "None"),
            ):
                if option not in omit:
                    arguments.extend((option, value))
            if threads is not None:
                arguments.extend(("--threads", threads))

            env = dict(os.environ, PATH=str(root), PARSER_FILE=str(parser_file),
                       TEST_OSTYPE=ostype)
            for name in ("input_bam", "aligner", "decoys_to_mask"):
                env.pop(name, None)
            if globals_:
                env.update(input_bam=str(input_bam), aligner="stale-aligner",
                           decoys_to_mask="stale-decoys")
            bash = shutil.which("bash")
            self.assertIsNotNone(bash, "bash is required for the parser tests")
            return subprocess.run(
                [bash, "-c", HELPERS + '\ncmd_prefilter "$@"\n' + after,
                 "prefilter-test", *arguments],
                env=env, capture_output=True, text=True, check=False,
            )

    def assert_missing(self, result, option):
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(f"Missing required option: {option}", result.stderr)
        self.assertNotIn("unbound variable", result.stderr)

    def assert_threads(self, result, expected):
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip().split("\t")[-1], expected)

    def test_each_missing_required_option_has_a_clear_error(self):
        for option in ("--input-bam", "--aligner", "--decoys-to-mask"):
            with self.subTest(option=option):
                self.assert_missing(self.run_parser(omit=(option,)), option)

    def test_global_values_cannot_replace_required_options(self):
        for option in ("--input-bam", "--aligner", "--decoys-to-mask"):
            with self.subTest(option=option):
                self.assert_missing(
                    self.run_parser(omit=(option,), globals_=True), option,
                )

    def test_successful_invocation_preserves_globals(self):
        result = self.run_parser(
            globals_=True,
            after='printf "GLOBALS:%s:%s\\n" "$aligner" "$decoys_to_mask"\n',
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.splitlines()[-1],
                         "GLOBALS:stale-aligner:stale-decoys")

    def test_required_options_do_not_leak_between_invocations(self):
        result = self.run_parser(
            after="cmd_prefilter --aligner bwa --decoys-to-mask None\n",
        )
        self.assert_missing(result, "--input-bam")
        self.assertEqual(len(result.stdout.splitlines()), 1)

    def test_omitted_threads_uses_nproc(self):
        self.assert_threads(self.run_parser(), "16")

    def test_explicit_threads_override_detection(self):
        for threads in ("1", "8"):
            with self.subTest(threads=threads):
                self.assert_threads(self.run_parser(threads=threads), threads)

    def test_omitted_threads_uses_sysctl_on_macos_without_nproc(self):
        self.assert_threads(
            self.run_parser(nproc=None, sysctl="6", ostype="darwin25"), "6",
        )

    def test_omitted_threads_uses_fallback_without_detection_tools(self):
        self.assert_threads(self.run_parser(nproc=None), "8")


if __name__ == "__main__":
    unittest.main()
