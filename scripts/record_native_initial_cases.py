#!/usr/bin/env python3
"""Observe seeded Unicode selections in new, authenticated TextEdit documents.

Uses the existing guarded helper unchanged. Stops on the first failed case;
never retries, changes focus itself, or broadens the target application.
"""
import argparse
import hashlib
import json
import pathlib
import subprocess
import sys
from native_evidence import validate_binding

root = pathlib.Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--target', choices=['prototype', 'original'], default='prototype')
parser.add_argument('--app', help='Exact running .app; defaults to dist/LayoutPilot.app')
parser.add_argument('--fixture', default='corpus/native-initial-selection-v1.json')
parser.add_argument('--output-dir', required=True)
args = parser.parse_args()
fixture = pathlib.Path(args.fixture).resolve()
out = pathlib.Path(args.output_dir).resolve()
if not fixture.is_relative_to(root / 'corpus') or not out.is_relative_to(root / 'research/evidence'):
    raise ValueError('Use project synthetic fixtures and a new evidence directory')
data = json.loads(fixture.read_text())
if data.get('schemaVersion') != 1 or not 1 <= len(data.get('cases', [])) <= 20:
    raise ValueError('Unsupported fixture schema or count')
cases = [case for case in data['cases'] if args.target in case.get('targets', ['prototype', 'original'])]
if not cases or len({case['id'] for case in cases}) != len(cases):
    raise ValueError('Missing or duplicate cases')
out.mkdir(exist_ok=False)
rows = []
for index, case in enumerate(cases):
    destination = out / f'{index:02d}.json'
    command = [sys.executable, str(root / 'scripts/record_native_probe.py'),
               '--output', str(destination), '--target', args.target,
               '--initial-text', case['initialText'], '--text', case['text'],
               '--source', case['source'], '--gesture', case['gesture'],
               '--interval-ms', '80', '--settle-ms', '600']
    if not case['boundary']:
        command.append('--no-boundary')
    if args.app:
        command.extend(['--app', args.app])
    if case['selectAllBeforeGesture']:
        command.append('--select-all-before-gesture')
    if args.target == 'original' and case['selectAllBeforeGesture'] and case['gesture'] == 'doubleShift':
        command.append('--reference-selection-clipboard')
    process = subprocess.run(command, capture_output=True, text=True, timeout=210, cwd=root)
    observed = json.loads(destination.read_text()) if destination.is_file() else {'error': 'no_result'}
    failures = []
    if process.returncode or observed.get('error') or not observed.get('identityUnchanged'):
        failures.append('probe_or_identity')
    try:validate_binding(observed)
    except (ValueError, KeyError, TypeError):failures.append('binding_or_modifier_cleanup')
    for actual, expected in [('text', case['expected']), ('inputSource', case['expectedSource']),
                             ('selection', case['expectedSelection'])]:
        if observed.get(actual) != expected:
            failures.append(actual)
    if args.target == 'original' and observed.get('clipboardRestore') != 'restored_all_representations':
        failures.append('reference_clipboard_not_restored')
    before = observed.get('beforeGesture', {})
    length = len(case['initialText'].encode('utf-16-le')) // 2
    if before.get('text') != case['initialText'] or before.get('selection') != {'location': 0, 'length': length}:
        failures.append('selected_initial_text_precondition')
    if 'expectedIntermediate' in case and observed.get('gestureIntermediate', {}).get('text') != case['expectedIntermediate']:
        failures.append('undo_lacks_actual_conversion')
    row = {'id': case['id'], 'failures': failures, 'evidence': str(destination.relative_to(root))}
    rows.append(row)
    print(json.dumps(row, ensure_ascii=False), flush=True)
    if failures:
        break
report = {'schemaVersion': 1, 'target': args.target, 'fixtureSha256': hashlib.sha256(fixture.read_bytes()).hexdigest(),
          'requested': len(cases), 'completed': len(rows), 'results': rows,
          'passed': len(rows) == len(cases) and all(not row['failures'] for row in rows),
          'notice': 'Only these seeded TextEdit selections; no other-host or full F05 acceptance.'}
(out / 'verification.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
raise SystemExit(0 if report['passed'] else 1)
