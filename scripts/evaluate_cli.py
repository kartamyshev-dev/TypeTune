#!/usr/bin/env python3
"""Reproducible CLI input-validation and offline invariant smoke."""
import argparse
import json
import subprocess
import tempfile
from pathlib import Path

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--cli', default=str(root / '.build/debug/layoutpilot-cli'))
args = parser.parse_args()
checks = []

def run(arguments, code):
    result = subprocess.run([args.cli] + arguments, capture_output=True, text=True)
    assert result.returncode == code, (arguments, result.returncode, result.stderr)
    return result

selftest = run(['selftest'], 0).stdout.strip()
run([], 2)
checks.append('missing command rejected')
run(['nonsense'], 2)
checks.append('unknown command rejected')
assert run(['convert', 'Ghbdtn'], 0).stdout.strip() == 'Привет'
checks.append('convert result checked')
run(['evaluate', str(root / 'corpus/synthetic-v1.jsonl'), '--split', 'test'], 2)
checks.append('invalid split rejected')
with tempfile.TemporaryDirectory() as directory:
    path = Path(directory) / 'input.json'
    path.write_text('[{"kind":"unknown"}]')
    run(['replay', str(path)], 2)
    checks.append('unknown replay event rejected')
    path.write_text('')
    run(['evaluate', str(path)], 2)
    checks.append('empty evaluation rejected')
    row = dict(schemaVersion=1, id='testing-evaluator-only', feature='test', split='train', category='test',
               provenance='temporary evaluator test; no original observation', input='ghbdtn', expected='wrong', originalResult=None)
    path.write_text(json.dumps(row) + '\n')
    report = json.loads(run(['evaluate', str(path)], 1).stdout)
    assert report['total']['misses'] == 1 and report['total']['originalCompared'] == 0
    checks.append('evaluation failure reported and null original excluded')
    path.write_text((json.dumps(row) + '\n') * 2)
    run(['evaluate', str(path)], 2)
    checks.append('duplicate fixture id rejected')
output = dict(passed=len(checks), checks=checks, offlineSelftest=selftest)
(root / 'corpus/cli-smoke-v2.json').write_text(json.dumps(output, ensure_ascii=False, indent=2) + '\n')
print(selftest)
print(f'CLI validation: {len(checks)} passed')
