#!/usr/bin/env python3
"""Exercise the exact prefilter write transaction with a mocked samtools CLI.

This isolates synchronous writes, failure propagation and output promotion;
it does not validate BAM biology or the surrounding upstream argument parser.
"""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / 'overrides/prefilter.sh').read_text()
TRANSACTION = SOURCE[SOURCE.index('  (\n    set -euo pipefail'):SOURCE.index('\n  log "prefilter done')]

MOCK = '''#!/usr/bin/env python3
import os, pathlib, sys
args=sys.argv[1:]
with open(os.environ['CALLS'], 'a') as handle:
    handle.write(repr(args)+'\\n')
if args[0]=='flagstat':
    if os.environ.get('FAIL')=='flagstat': sys.exit(23)
    print('2\\t0\\ttotal')
elif args[0]=='view':
    output=pathlib.Path(args[args.index('-o')+1])
    step='split' if '-U' in args else ('unaligned' if output.name.startswith('unaligned') else 'decoys')
    output.write_text('incomplete')
    if os.environ.get('FAIL')==step: sys.exit(23)
    output.write_text('complete')
    if '-U' in args: pathlib.Path(args[args.index('-U')+1]).write_text('complete')
else: sys.exit(2)
'''

class PrefilterTransactionTests(unittest.TestCase):
    def run_transaction(self, aligner='bwa', fail=''):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory)
            (root/'samtools').write_text(MOCK)
            (root/'samtools').chmod(0o755)
            setup='''set -euo pipefail
log() { :; }
die() { echo "$*" >&2; exit 1; }
bam_check_or_die() {
  [[ "${FAIL:-}" != validation ]] || return 24
  [[ "$(cat "$1")" == complete ]]
}
threads=1
input_bam=input.bam
L_ARG=(-L fixture.bed)
unaligned_out=unaligned.bam
decoys_out=decoys.bam
flagstat_out=flagstat.tsv
rejected_tmp=unaligned.rejected.tmp.bam
selected_tmp=decoys.selected.tmp.bam
unaligned_tmp=unaligned.bam.tmp.bam
decoys_tmp=decoys.bam.tmp.bam
flagstat_tmp=flagstat.tsv.tmp
'''
            env=dict(os.environ, PATH=f'{root}:{os.environ["PATH"]}', aligner=aligner,
                     FAIL=fail, CALLS=str(root/'calls'))
            result=subprocess.run(['bash','-c',setup+TRANSACTION],cwd=root,env=env,
                                  capture_output=True,text=True)
            calls=(root/'calls').read_text()
            finals=['unaligned.bam','decoys.bam','flagstat.tsv']
            if fail or aligner=='invalid':
                self.assertNotEqual(result.returncode,0,result.stderr)
                self.assertFalse(any((root/f).exists() for f in finals))
            else:
                self.assertEqual(result.returncode,0,result.stderr)
                self.assertTrue(all((root/f).is_file() for f in finals))
                self.assertEqual((root/'unaligned.bam').read_text(),'complete')
                self.assertEqual((root/'decoys.bam').read_text(),'complete')
                self.assertEqual('[AS]>35' in calls,aligner=='bwa')
                self.assertIn("'-L', 'fixture.bed'",calls)
            self.assertFalse(list(root.glob('*.tmp*')))

    def test_bwa_success(self): self.run_transaction()
    def test_dragen_success(self): self.run_transaction('DRAGEN')
    def test_invalid_aligner(self): self.run_transaction('invalid')
    def test_failures_do_not_promote_incomplete_outputs(self):
        for step in ['flagstat','split','unaligned','decoys','validation']:
            with self.subTest(step=step): self.run_transaction(fail=step)

if __name__=='__main__': unittest.main()
