#!/usr/bin/env python3
"""A successful quickcheck must not hide full-read errors during BAM reuse."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / 'overrides/prefilter.sh').read_text()
REUSE = SOURCE[SOURCE.index('  if (( dont_overwrite )); then'):SOURCE.index('\n  log "prefilter aligner=')]
MOCK = '''#!/usr/bin/env python3
import os, pathlib, sys
args=sys.argv[1:]
with open(os.environ['CALLS'],'a') as handle: handle.write(' '.join(args)+'\\n')
if args[0]=='quickcheck': sys.exit(0)
if args[:2]==['view','-c']:
    if pathlib.Path(args[-1]).read_text()=='corrupt': sys.exit(23)
    print(0)
    sys.exit(0)
sys.exit(2)
'''


class PrefilterReuseTests(unittest.TestCase):
    def check_reuse(self, corrupt=None, missing=None, empty_flagstat=False):
        with tempfile.TemporaryDirectory(prefix='prefilter-reuse-') as directory:
            root = Path(directory)
            executable = root / 'samtools'
            executable.write_text(MOCK)
            executable.chmod(0o755)
            outputs = ['unaligned.bam', 'decoys.bam', 'flagstat.tsv']
            for name in outputs:
                if name != missing:
                    (root / name).write_text('corrupt' if name == corrupt else 'valid')
            if empty_flagstat:
                (root / 'flagstat.tsv').write_text('')
            script = '''set -euo pipefail
log() { printf '%s\\n' "$*"; }
cmd_prefilter() {
  local dont_overwrite=1
  local unaligned_out=unaligned.bam decoys_out=decoys.bam flagstat_out=flagstat.tsv
''' + REUSE + '''
  printf 'regenerate\\n'
}
cmd_prefilter
'''
            env = dict(os.environ, PATH=str(root) + os.pathsep + os.environ['PATH'],
                       CALLS=str(root / 'calls'))
            result = subprocess.run(['bash', '-c', script], cwd=root, env=env,
                                    capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            valid = corrupt is None and missing is None and not empty_flagstat
            if valid:
                self.assertIn('skipping', result.stdout)
                self.assertNotIn('regenerate', result.stdout)
                self.assertTrue(all((root / name).exists() for name in outputs))
            else:
                self.assertNotIn('skipping', result.stdout)
                self.assertIn('regenerate', result.stdout)
                self.assertFalse(any((root / name).exists() for name in outputs))
            calls = (root / 'calls').read_text()
            for name in outputs[:2]:
                if name != missing:
                    self.assertIn(f'view -c {name}', calls)

    def test_valid_zero_read_bams_are_reused(self): self.check_reuse()
    def test_corrupt_unaligned_bam_is_not_reused(self): self.check_reuse(corrupt='unaligned.bam')
    def test_corrupt_decoys_bam_is_not_reused(self): self.check_reuse(corrupt='decoys.bam')
    def test_missing_outputs_trigger_regeneration(self):
        for name in ['unaligned.bam', 'decoys.bam', 'flagstat.tsv']:
            with self.subTest(name=name): self.check_reuse(missing=name)
    def test_empty_flagstat_triggers_regeneration(self): self.check_reuse(empty_flagstat=True)


if __name__ == '__main__':
    unittest.main()
