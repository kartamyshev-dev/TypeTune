#!/usr/bin/env python3
"""Record exact app/bundle/process/helper identity around one bounded TextEdit probe."""
import argparse
import json
import pathlib
import subprocess
import sys
import time
from native_evidence import (digest, run_probe, validate_binding, validate_workload_segments,
                             target_binary, selected_switcher_pid, require)

root = pathlib.Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--output', required=True)
parser.add_argument('--target', choices=['prototype', 'original'], default='prototype')
parser.add_argument('--app', help='Exact running .app; defaults to dist/LayoutPilot.app')
args, probe_args = parser.parse_known_args()
output = pathlib.Path(args.output).resolve()
require(output.is_relative_to(root/'research/evidence') and not output.exists(),
        'Choose a new evidence file inside research/evidence')
binary = target_binary(root, args.app, args.target)
if args.target == 'original':
    subprocess.run([sys.executable, str(root/'scripts/verify_original.py')], check=True, capture_output=True)
pid = selected_switcher_pid(binary)
case_file = None
if '--batch' in probe_args:
    case_file = pathlib.Path(probe_args[probe_args.index('--batch') + 1]).resolve()
    require(any(case_file.is_relative_to(folder) for folder in [root/'corpus', root/'research/private/native-batches']),
            'Batch must belong to this project synthetic corpus')
case_digest = digest(case_file) if case_file else None
subprocess.run([str(root/'scripts/native_probe.sh'), '--build-only'], check=True, capture_output=True)
metadata = {'target': args.target, 'app': str(binary.parents[2]), 'pid': pid,
            'sourceCommit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip(),
            'sourceDirty': bool(subprocess.check_output(['git', 'status', '--porcelain'], text=True).strip()),
            'probeStartUptime': time.monotonic()}
require(selected_switcher_pid(binary) == pid, 'Selected switcher changed before probe')
result = run_probe(root, binary, pid, probe_args, timeout=180)
result.update(metadata)
result['probeEndUptime'] = time.monotonic()
if case_file:
    result['caseFileSha256'] = case_digest
try:
    validate_binding(result)
    require(selected_switcher_pid(binary) == pid, 'Selected switcher changed after probe')
    if case_file:
        require(digest(case_file) == case_digest, 'case_file_changed_during_run')
        validate_workload_segments(result, 30 if '--idle-after-batch' in probe_args else 0)
except Exception as error:
    result['validationError'] = str(error)
    result.setdefault('error', str(error))
if result.get('error') and result.get('checkpoint'):
    checkpoint = pathlib.Path(result['checkpoint']).resolve()
    if checkpoint.is_relative_to(root/'research/private/probes') and checkpoint.is_file():
        result['savedCheckpoint'] = json.loads(checkpoint.read_text())
output.parent.mkdir(parents=True, exist_ok=True)
with output.open('x') as stream:
    stream.write(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
print(json.dumps({'output': str(output), 'completed': result.get('completed'), 'error': result.get('error'),
                  'identityUnchanged': result['identityUnchanged']}, ensure_ascii=False))
sys.exit(1 if result.get('error') or result.get('processExitCode', 1) else 0)
