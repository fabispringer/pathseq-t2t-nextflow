#!/usr/bin/env python3
"""Run a copied launcher against a fake Nextflow, checking real argv boundaries."""
import json
import os
import re
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[1]

class LauncherTests(unittest.TestCase):
    def test_explicit_choices_and_copied_run_directory(self):
        for mode,layout,aligner,profile in [
            ('fastq','paired','star','local'),
            ('fastq','single','bwa','slurm'),
            ('bam','paired','star','lsf'),
        ]:
            with self.subTest(mode=mode,layout=layout,aligner=aligner,profile=profile):
                with tempfile.TemporaryDirectory(prefix='launcher test ') as directory:
                    root=Path(directory)
                    run=root/'run directory'; repo=root/'source repository'; bin_dir=root/'bin'
                    for path in [run,repo,bin_dir,root/'input reads']: path.mkdir()
                    script=(ROOT/'run.sh').read_text()
                    for key,value in [('INPUT_MODE',mode),('FASTQ_LAYOUT',layout),('ALIGNER',aligner),('PROFILE',profile)]:
                        script=re.sub(rf'^{key}="[^"]*"',f'{key}="{value}"',script,flags=re.M)
                    (run/'run.sh').write_text(script)
                    (run/'parameters.yaml').write_text('input_mode: fastq\n')
                    (repo/'nextflow.config').write_text('// fixture\n')
                    capture=root/'args.json'
                    fake=bin_dir/'nextflow'
                    fake.write_text('#!/usr/bin/env python3\nimport json,os,sys\nwith open(os.environ["CAPTURE"],"w") as handle: json.dump(sys.argv[1:],handle)\n')
                    fake.chmod(0o755)
                    env=dict(os.environ,PATH=f'{bin_dir}:{os.environ["PATH"]}',
                             INPUT_DIR=str(root/'input reads'),WORK_DIR=str(root/'work directory'),
                             OUTDIR=str(root/'output directory'),REPO_ROOT=str(repo),CAPTURE=str(capture))
                    env.pop('CONFIG_FILE',None);env.pop('PARAMS_FILE',None)
                    result=subprocess.run(['bash',str(run/'run.sh')],cwd=root,env=env,capture_output=True,text=True)
                    self.assertEqual(result.returncode,0,result.stderr)
                    args=json.loads(capture.read_text())
                    for key,value in [('--input_mode',mode),('--fastq_layout',layout),('--aligner',aligner),('-profile',profile),('run',str(repo)),('-params-file',str(run/'parameters.yaml')),('-c',str(repo/'nextflow.config')),('--input_dir',env['INPUT_DIR']),('--outdir',env['OUTDIR'])]:
                        self.assertEqual(args[args.index(key)+1],value)

if __name__=='__main__': unittest.main()
