#!/usr/bin/env python3
"""Verify text, input source, cursor, paste restoration and actual undo precondition."""
import argparse,json,pathlib
from native_evidence import validate_binding, validate_fixture_digest
p=argparse.ArgumentParser();p.add_argument('result');p.add_argument('--fixtures',default='corpus/native-smoke.json');a=p.parse_args()
d=json.loads(pathlib.Path(a.result).read_text());fixture_bytes=pathlib.Path(a.fixtures).read_bytes();fixtures=json.loads(fixture_bytes)
# Stopped wrapper runs retain completed cases in their authenticated checkpoint.
# Reporting those rows never changes a stopped or incomplete run into acceptance.
from_checkpoint='results' not in d and bool(d.get('savedCheckpoint'))
rows=d.get('results',d.get('savedCheckpoint',{}).get('results',[]))
failures=[]
fixture_identity=False
try:
 validate_fixture_digest(d,fixture_bytes)
 fixture_identity=True
except (ValueError, OSError) as error:failures.append(str(error))
if 'error' in d:failures.append(d['error'])
if type(d.get('processExitCode')) is not int or d['processExitCode'] != 0:failures.append('Process completion not verified')
if d.get('identityUnchanged') is not True:failures.append('Identity not verified')
if 'identityBefore' in d:
 try:validate_binding(d)
 except (ValueError, KeyError, TypeError) as error:failures.append(str(error))
elif d.get('targetProcessUnchanged') is not True:failures.append('Target process not verified')
if from_checkpoint or ('status' in d and d['status'] != 'completed'):failures.append('Stopped/incomplete run')
if type(d.get('completed')) is not int or d['completed'] != len(fixtures):failures.append('Completion count not verified')
flags=d.get('finalModifierFlags')
modifier_cleanup=type(flags) is int and flags >= 0 and flags & 0x9f207f == 0
if not modifier_cleanup:failures.append('Modifier cleanup not verified')
by_id={r['id']:r for r in rows}
if len(rows)!=len(fixtures) or len(by_id)!=len(rows):failures.append('Missing or duplicate cases')
for f in fixtures:
 r=by_id.get(f['id'],{})
 from native_integrity import validate_regression_timing
 try:validate_regression_timing(r,f)
 except (ValueError, TypeError) as error:failures.append(f['id']+': '+str(error))
 for field,expected in [('text',f['expected']),('inputSource',f.get('expectedSource')),('selection',f.get('expectedSelection'))]:
  if expected is not None and r.get(field)!=expected:failures.append(f['id']+': '+field)
 if f['id']=='plain-paste' and r.get('clipboardRestore')!='restored_all_representations':failures.append('Clipboard not restored')
 if f['id']=='auto-undo' and r.get('beforeGesture',{}).get('text')!='привет ':failures.append('Auto undo lacks actual correction before gesture')
print(json.dumps({'cases':len(rows),'requestedCases':len(fixtures),'rowsFromStoppedCheckpoint':from_checkpoint,'failures':failures,'fixtureIdentityVerified':fixture_identity,'modifierCleanupVerified':modifier_cleanup,'notice':'Only supplied native scenarios; stopped/incomplete runs cannot pass.'},ensure_ascii=False))
if failures:raise SystemExit(1)
