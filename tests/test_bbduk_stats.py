#!/usr/bin/env python3
"""Test the BBDUK task shell with synthetic FASTQs and per-pass statistics.

The default uses a minimal BBDuk double. Set BBDUK_TEST_REAL=1 to run the same
cases with an installed bbduk.sh (including real filtering and stats files).
"""
import gzip
import os
from pathlib import Path
import random
import re
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / 'main.nf').read_text().split('process BBDUK {', 1)[1].split('\nprocess FASTQC_POST {', 1)[0]
SCRIPT = SOURCE.split('  """', 2)[1]
CONFIG = (ROOT / 'nextflow.config').read_text()
PARAMS = re.search(r"bbduk_params:\s*'([^']*)'", CONFIG).group(1)
REAL = os.environ.get('BBDUK_TEST_REAL') == '1'
MOCK = '''#!/usr/bin/env python3
import gzip, pathlib, sys
args=dict(arg.split('=',1) for arg in sys.argv[1:] if '=' in arg)
def read(name):
    opener=gzip.open if name.endswith('.gz') else open
    with opener(name,'rt') as handle: return handle.read()
def write(name, text):
    opener=gzip.open if name.endswith('.gz') else open
    with opener(name,'wt') as handle: handle.write(text)
if 'in1' in args:
    r1,r2=read(args['in1']),read(args['in2'])
    write(args['out1'],r1)
    write(args['out2'],r2)
    write(args['outs'],'')
    total=(len(r1.splitlines())+len(r2.splitlines()))//4
else:
    reads=read(args['in'])
    write(args['out'],reads)
    total=len(reads.splitlines())//4
if 'stats' in args:
    pathlib.Path(args['stats']).write_text('#Total\\t'+str(total)+'\\n')
'''


def write_fastq(path, count, label):
    rng = random.Random(20261028 + count + len(label))
    with gzip.open(path, 'wt') as handle:
        for i in range(count):
            sequence = ''.join(rng.choice('ACGT') for _ in range(100))
            handle.write(f'@synthetic_{i}/{label}\n{sequence}\n+\n' + 'I' * 100 + '\n')


class BbdukStatsTests(unittest.TestCase):
    def check_layout(self, pairs, unpaired):
        with tempfile.TemporaryDirectory(prefix='bbduk-stats-') as directory:
            root = Path(directory)
            for name, count, label in [('r1.fq.gz', pairs, '1'), ('r2.fq.gz', pairs, '2'), ('unpaired.fq.gz', unpaired, 'single')]:
                write_fastq(root / name, count, label)
            (root / 'adapters.fa').write_text('>adapter\nAGATCGGAAGAGCACACGTCTGAACTCCAGTCA\n')
            env = dict(os.environ)
            if not REAL:
                executable = root / 'bbduk.sh'
                executable.write_text(MOCK)
                executable.chmod(0o755)
                env['PATH'] = str(root) + os.pathsep + env['PATH']
            replacements = {
                '${task.memory.toGiga()}': '1', '${task.cpus}': '1',
                '${params.qc.bbduk_params}': PARAMS, '${params.qc.min_length}': '50',
                '${adapters}': 'adapters.fa', '${sample_id}': 'sample',
                '${r1}': 'r1.fq.gz', '${r2}': 'r2.fq.gz',
                '${addUnpaired}': 'gzip -cd unpaired.fq.gz >> tmp_unpaired.fq',
            }
            script = SCRIPT.replace('\\\\', '\\')
            for key, value in replacements.items():
                script = script.replace(key, value)
            self.assertNotIn('${', script)
            result = subprocess.run(['bash', '-c', script], cwd=root, env=env,
                                    capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            for label, expected in [('paired', pairs * 2), ('unpaired', unpaired)]:
                stats = root / f'sample.{label}.bbduk_stats.txt'
                self.assertTrue(stats.is_file(), f'Missing {label} statistics')
                total = re.search(r'^#Total\s+(\d+)', stats.read_text(), re.MULTILINE)
                self.assertIsNotNone(total, stats.read_text())
                self.assertEqual(int(total.group(1)), expected)
            self.assertEqual(len(list(root.glob('*.bbduk_stats.txt'))), 2)
            for label, expected in [('R1', pairs), ('R2', pairs), ('unpaired', unpaired)]:
                with gzip.open(root / f'sample.qc_{label}.fastq.gz', 'rt') as handle:
                    self.assertEqual(sum(1 for _ in handle) // 4, expected)
            self.assertFalse((root / 'tmp_unpaired.fq').exists())

    def test_single_end(self): self.check_layout(0, 10)
    def test_paired_only(self): self.check_layout(5, 0)
    def test_paired_plus_unpaired(self): self.check_layout(5, 3)
    def test_empty_passes(self): self.check_layout(0, 0)


if __name__ == '__main__':
    unittest.main()
