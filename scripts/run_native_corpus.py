#!/usr/bin/env python3
"""Runs bounded, authenticated TextEdit probes. Stop entire run on lost focus/error."""
import argparse, hashlib, json, pathlib, subprocess, time, re
from native_evidence import capture, run_probe, validate_binding, validate_workload_segments, target_binary, selected_switcher_pid
from native_integrity import load_corpus_oracle, unknown_corpus_rows, correction_failures
def require(condition, message):
    if not condition: raise ValueError(message)

root = pathlib.Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--target', choices=['original','prototype'], required=True)
parser.add_argument('--app', help='Exact running .app; defaults to dist/LayoutPilot.app for prototype')
parser.add_argument('--start', type=int, default=0)
parser.add_argument('--batches', type=int, default=5)
parser.add_argument('--run-id', default='focused')
parser.add_argument('--interval-ms', type=int, choices=range(10,1001), default=10, metavar='10..1000')
args=parser.parse_args()
binary=target_binary(root, args.app, args.target)
require(0 <= args.start < 5 and 1 <= args.batches <= 5 - args.start, 'Invalid batch range')
require(re.fullmatch('[a-z0-9-]{1,40}',args.run_id), 'Invalid run ID')
output=root/'research/evidence'/('native-corpus-'+args.target)/args.run_id
output.mkdir(parents=True,exist_ok=True)
corpus_digest=hashlib.sha256((root/'corpus/native-v1.json').read_bytes()).hexdigest()
expected={r['id']:r for r in json.loads((root/'corpus/native-v1.json').read_text())}
oracle, oracle_identity = load_corpus_oracle(root/'corpus/native-v1.json', root/'corpus/synthetic-v2.jsonl')
records=[]
integrity_passed=True
input_seconds=0
idle_seconds=0
run_identity=None
for index in range(args.start,args.start+args.batches):
    target_pid=selected_switcher_pid(binary)
    batch=root/'research/private/native-batches'/f'{index:02}.json'
    require(batch.exists(), 'Batch absent')
    destination=output/f'{index:02}.json'
    require(not destination.exists(), 'Retain previous evidence; select a new run directory for repeats')
    subprocess.run([str(root/'scripts/native_probe.sh'),'--build-only'],check=True,capture_output=True)
    binary_digest=hashlib.sha256(binary.read_bytes()).hexdigest()
    helper_digest=hashlib.sha256((root/'Tools/NativeProbe.swift').read_bytes()).hexdigest()
    helper_binary_digest=hashlib.sha256((root/'.build/native-probe').read_bytes()).hexdigest()
    current_identity=capture(root,binary,int(target_pid))
    if run_identity is None: run_identity=current_identity
    require(current_identity == run_identity, 'Identity changed between corpus batches; refuse input')
    batch_digest=hashlib.sha256(batch.read_bytes()).hexdigest()
    case_digest=hashlib.sha256((root/'corpus/native-v1.json').read_bytes()).hexdigest()
    require(case_digest == corpus_digest, 'Corpus changed before input')
    require(load_corpus_oracle(root/'corpus/native-v1.json', root/'corpus/synthetic-v2.jsonl')[1] == oracle_identity, 'Integrity corpus changed before input')
    began=time.monotonic()
    result = run_probe(root, binary, int(target_pid), ['--batch',str(batch),'--interval-ms',str(args.interval_ms),'--settle-ms','100'], timeout=1200)
    result['target']=args.target
    result['targetBinarySha256']=binary_digest
    result['probeSourceSha256']=helper_digest
    result['probeBinarySha256']=helper_binary_digest
    result['nativeBatchSha256']=hashlib.sha256(batch.read_bytes()).hexdigest()
    result['intervalMilliseconds']=args.interval_ms
    result['pid']=int(target_pid)
    alive=subprocess.run(['ps','-ww','-p',str(target_pid),'-o','comm='],capture_output=True,text=True)
    if alive.returncode or alive.stdout.strip()!=str(binary):result['error']='target_process_changed'
    if helper_binary_digest!=hashlib.sha256((root/'.build/native-probe').read_bytes()).hexdigest():result['error']='helper_binary_changed'
    if helper_digest != hashlib.sha256((root/'Tools/NativeProbe.swift').read_bytes()).hexdigest() or binary_digest != hashlib.sha256(binary.read_bytes()).hexdigest(): result['error']='identity_changed_during_run'
    result['caseFileSha256']=hashlib.sha256((root/'corpus/native-v1.json').read_bytes()).hexdigest()
    result['wallSeconds']=time.monotonic()-began
    result.setdefault('processExitCode', -1)
    if result.get('identityBefore') != run_identity or result.get('nativeBatchSha256') != batch_digest or result['caseFileSha256'] != case_digest:result['error']='run_or_fixture_identity_changed'
    try: validate_binding(result)
    except Exception as error: result['error'] = 'binding_validation_failed: ' + str(error)
    if result['processExitCode'] or 'error' in result:
        result['status']='failed'
        if result.get('checkpoint'):
            checkpoint=pathlib.Path(result['checkpoint']).resolve()
            require(checkpoint.is_relative_to(root/'research/private/probes'), 'Checkpoint outside test folder')
            if checkpoint.exists(): result['savedCheckpoint']=json.loads(checkpoint.read_text())
        destination.write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
        raise SystemExit('STOP: '+str(result))
    requested=json.loads(batch.read_text())
    try:
        batch_input, batch_idle = validate_workload_segments(result, 0)
        require(result.get('completed')==len(requested) and len(result.get('results',[]))==len(requested), 'Incomplete corpus batch')
        require({r['id'] for r in result['results']}=={r['id'] for r in requested}, 'Corpus batch IDs mismatch')
    except Exception as error:
        result['error']=str(error); result['status']='failed'
        destination.write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
        raise
    input_seconds += batch_input
    idle_seconds += batch_idle
    for row in result['results']:
        fixture=expected[row['id']]
        row['expected']=fixture['expected']; row['split']=fixture['split']; row['category']=fixture['category']
        row['matchesExpected']=row['text']==row['expected']
        records.append(row)
    _, current_oracle_identity = load_corpus_oracle(root/'corpus/native-v1.json', root/'corpus/synthetic-v2.jsonl')
    require(current_oracle_identity == oracle_identity, 'Integrity corpus changed during run')
    unknown = unknown_corpus_rows(result['results'], oracle, [r['id'] for r in requested])
    misses = correction_failures(result['results'], [expected[r['id']] for r in requested])
    result['integrityPassed'] = not unknown
    result['correctionQualityPassed'] = not misses
    result['correctionFailureIDs'] = misses
    integrity_passed = integrity_passed and not unknown
    result['corpusIntegrity'] = {'fixtureIdentity': oracle_identity, 'unknownIDs': unknown,
                                 'passed': not unknown,
                                 'notice': 'Exact raw or authored expected only; unknown is unsafe/unclassified, not proven text loss. Raw is not correction quality PASS.'}
    if unknown and args.target == 'prototype':
        result['status']='failed'; result['error']='unknown_or_unsafe_corpus_text'
    destination.write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
    if unknown and args.target == 'prototype':
        raise SystemExit('STOP: unknown/unsafe corpus results: ' + ','.join(unknown))
    print(json.dumps({'target':args.target,'batch':index,'casesCompleted':len(records),
                      'matchesExpected':sum(r['matchesExpected'] for r in records),
                      'wallSeconds':round(result['wallSeconds'],2)},ensure_ascii=False),flush=True)
summary={'target':args.target,'cases':len(records),'matchesExpected':sum(r['matchesExpected'] for r in records),
         'app':str(binary.parents[2]), 'status':'completed', 'integrityPassed':integrity_passed,
         'correctionQualityPassed':all(r['matchesExpected'] for r in records),
         'inputDurationSeconds':input_seconds, 'idleDurationSeconds':idle_seconds,
         'notice':'Native TextEdit sample of authored lexicon corpus; not independent language-quality or latency p95.'}
(output/'summary.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2)+'\n')
print(json.dumps(summary,ensure_ascii=False),flush=True)
