#!/usr/bin/env python3
"""Single supervised TextEdit session: fixed comparison then requested duration with read-only telemetry.
Stops immediately on probe failure, preserves partial results, never retries or steals focus itself.
"""
import argparse, hashlib, json, pathlib, subprocess, threading, time, math
from native_integrity import preserved_alternating, correction_failures
from native_evidence import capture, run_probe, validate_binding, validate_workload_segments, target_binary, selected_switcher_pid, digest
root=pathlib.Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser();p.add_argument('--run-id',required=True);p.add_argument('--interval-ms',type=int,choices=range(10,1001),default=10,metavar='10..1000')
p.add_argument('--duration-minutes',type=int,choices=range(30,1441),default=30,metavar='30..1440')
p.add_argument('--app', help='Exact running .app; defaults to dist/LayoutPilot.app');args=p.parse_args()
required_seconds=args.duration_minutes*60
if not __import__('re').fullmatch('[a-z0-9-]{1,40}',args.run_id):raise ValueError('Invalid run ID')
binary=target_binary(root, args.app)
pid=str(selected_switcher_pid(binary))
stream_fixture=root/'corpus/native-fast-stream-v1.json'
stream_digest=digest(stream_fixture)
stream_cases=json.loads(stream_fixture.read_text())
if not stream_cases:raise ValueError('Empty stream regression fixture')
out=root/'research/evidence'/('native-session-'+args.run_id)
out.mkdir(exist_ok=False)
subprocess.run([str(root/'scripts/native_probe.sh'),'--build-only'],check=True,capture_output=True)
began=time.monotonic();stop=threading.Event();samples=[]
def monitor():
 while not stop.is_set():
  result=subprocess.run(['ps','-p',pid,'-o','%cpu=,rss='],capture_output=True,text=True)
  values=result.stdout.split()
  if len(values)==2:samples.append({'seconds':round(time.monotonic()-began,3),'cpuPercent':float(values[0]),'rssKiB':int(values[1])})
  stop.wait(2)
thread=threading.Thread(target=monitor,daemon=True);thread.start()
report={'pid':int(pid),'app':str(binary.parents[2]),'targetBinarySha256':digest(binary),'probeSourceSha256':digest(root/'Tools/NativeProbe.swift'),'probeBinarySha256':digest(root/'.build/native-probe'),'streamFixtureSha256':stream_digest,'intervalMilliseconds':args.interval_ms,'requiredDurationSeconds':required_seconds,'requiredIdleSecondsPerBatch':30,'inputDurationSeconds':0,'idleDurationSeconds':0,'comparisonRun':args.run_id,'stabilityBatches':[],'integrityPassed':False,'correctionQualityPassed':False,'notice':'Synthetic new TextEdit documents only: input workload includes clearing/readback/setup; every stream batch ends with measured guarded 30s idle. No app-switch or sleep/wake acceptance. CPU sampled every 2s; no correction-only latency claim.'}
try:
 report['identityBefore']=capture(root,binary,int(pid))
 comparison=subprocess.run(['python3',str(root/'scripts/run_native_corpus.py'),'--target','prototype','--app',str(binary.parents[2]),'--run-id',args.run_id,'--interval-ms',str(args.interval_ms)],cwd=root)
 if comparison.returncode:raise RuntimeError('Comparison stopped; no automatic resume')
 comparison_summary=json.loads((root/'research/evidence/native-corpus-prototype'/args.run_id/'summary.json').read_text())
 report['inputDurationSeconds']=comparison_summary['inputDurationSeconds']
 report['idleDurationSeconds']=comparison_summary['idleDurationSeconds']
 if comparison_summary.get('integrityPassed') is not True or comparison_summary.get('correctionQualityPassed') is not True:raise RuntimeError('Comparison integrity/correction quality failed; stop before stability input')
 if capture(root,binary,int(pid)) != report['identityBefore']:raise RuntimeError('Session identity changed during comparison')
 index=0
 while time.monotonic()-began<required_seconds or not report['stabilityBatches']:
  estimated_case_seconds=96*(0.024+args.interval_ms/1000)+1
  count=max(1,min(100,int(1200/estimated_case_seconds),math.ceil((required_seconds-(time.monotonic()-began))/estimated_case_seconds)))
  if digest(stream_fixture)!=stream_digest:raise RuntimeError('Stream regression fixture changed')
  cases=[dict(stream_cases[i%len(stream_cases)],id=f'stability-{index}-{i}') for i in range(count)]
  batch=root/'research/private/native-batches'/f'stability-{args.run_id}-{index}.json';batch.write_text(json.dumps(cases,ensure_ascii=False))
  if selected_switcher_pid(binary)!=int(pid):raise RuntimeError('Selected switcher process changed or conflict')
  if capture(root,binary,int(pid)) != report['identityBefore']:raise RuntimeError('Session identity changed before stability input')
  result=run_probe(root,binary,int(pid),['--batch',str(batch),'--interval-ms',str(args.interval_ms),'--settle-ms','100','--idle-after-batch'],timeout=1500)
  result['nativeBatchSha256']=hashlib.sha256(batch.read_bytes()).hexdigest()
  if report['targetBinarySha256']!=digest(binary) or report['probeSourceSha256']!=digest(root/'Tools/NativeProbe.swift') or report['probeBinarySha256']!=digest(root/'.build/native-probe'):result['error']='identity_changed_during_run'
  (out/f'stability-{index}.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
  if validate_binding(result) != report['identityBefore']:raise RuntimeError('Stability/session identity mismatch')
  batch_input,batch_idle=validate_workload_segments(result,30)
  if result.get('processExitCode',-1) or 'error' in result:raise RuntimeError('Stability stopped; no automatic resume')
  if len(result.get('results',[])) != len(cases) or result.get('completed') != len(cases):raise RuntimeError('Incomplete stability batch')
  if {r['id'] for r in result['results']} != {c['id'] for c in cases}:raise RuntimeError('Stability case IDs mismatch')
  misses=correction_failures(result['results'],cases)
  exact=len(cases)-len(misses)
  wrong=[r['id'] for r in result['results'] if not preserved_alternating(r['text'])]
  report['inputDurationSeconds']+=batch_input
  report['idleDurationSeconds']+=batch_idle
  report['stabilityBatches'].append({'index':index,'cases':len(result['results']),'inputSegmentSeconds':batch_input,'idleSegmentSeconds':batch_idle,'textIntegrityFailures':wrong,'matchesCorrectionExpectation':exact,'integrityPassed':not wrong,'correctionQualityPassed':not misses,'correctionFailureIDs':misses})
  print(json.dumps({'stabilityBatch':index,'elapsedSeconds':round(time.monotonic()-began),'textIntegrityFailures':len(wrong),'matchesCorrectionExpectation':exact}),flush=True)
  if wrong:raise RuntimeError('Unexpected text; stop to investigate')
  if misses:raise RuntimeError('Stream correction quality failed; stop to investigate')
  index+=1
 alive=subprocess.run(['ps','-ww','-p',pid,'-o','comm='],capture_output=True,text=True)
 if alive.returncode or alive.stdout.strip()!=str(binary):raise RuntimeError('Target process changed')
 report['identityAfter']=capture(root,binary,int(pid))
 report['identityUnchanged']=report['identityBefore']==report['identityAfter']
 if not report['identityUnchanged']:raise RuntimeError('Whole session identity changed')
 if digest(stream_fixture)!=stream_digest:raise RuntimeError('Stream regression fixture changed')
 if time.monotonic()-began<required_seconds:raise RuntimeError('Session shorter than requested duration')
 report['integrityPassed']=comparison_summary.get('integrityPassed') is True and all(b['integrityPassed'] for b in report['stabilityBatches'])
 report['correctionQualityPassed']=comparison_summary.get('correctionQualityPassed') is True and all(b['correctionQualityPassed'] for b in report['stabilityBatches'])
 report['status']='completed'
except Exception as error:
 report['status']='failed';report['reason']=str(error)
finally:
 stop.set();thread.join();report['durationSeconds']=time.monotonic()-began;report['atLeast30Minutes']=report['durationSeconds']>=1800
 report['atLeast4Hours']=report['durationSeconds']>=14400
 report['telemetry']={'samples':len(samples),'peakCPUPercent':max((s['cpuPercent'] for s in samples),default=None),'peakRSSKiB':max((s['rssKiB'] for s in samples),default=None)}
 (out/'telemetry.json').write_text(json.dumps(samples,indent=2)+'\n');(out/'summary.json').write_text(json.dumps(report,indent=2)+'\n')
 if report['status']!='completed':print(json.dumps(report,ensure_ascii=False,indent=2),flush=True)
if report['status']!='completed':raise SystemExit(1)
verification=subprocess.run(['python3',str(root/'scripts/verify_native_session.py'),str(out),'--app',str(binary.parents[2])],cwd=root)
if verification.returncode:
 report['status']='failed';report['reason']='Final session verification rejected evidence'
 (out/'summary.json').write_text(json.dumps(report,indent=2)+'\n')
 print(json.dumps(report,ensure_ascii=False,indent=2),flush=True)
 raise SystemExit(1)
print(json.dumps(report,ensure_ascii=False,indent=2),flush=True)
