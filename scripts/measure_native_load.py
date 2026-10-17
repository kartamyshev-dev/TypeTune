#!/usr/bin/env python3
"""Bounded TextEdit fixture plus process CPU time/samples; never retries focus failures."""
import argparse,hashlib,json,pathlib,statistics,subprocess,threading,time,sys
from native_integrity import preserved_alternating, correction_failures
from native_evidence import target_binary, selected_switcher_pid, run_probe, validate_binding, validate_workload_segments
root=pathlib.Path(__file__).resolve().parents[1]
def require(ok,message):
 if not ok:raise ValueError(message)
p=argparse.ArgumentParser();p.add_argument('--app',required=True);p.add_argument('--run-id',required=True);a=p.parse_args()
binary=target_binary(root,a.app);app=binary.parents[2]
require(a.run_id.replace('-','').isalnum() and len(a.run_id)<=40,'Invalid run ID')
out=root/'research/evidence'/('native-load-'+a.run_id);out.mkdir(exist_ok=False)
digest=hashlib.sha256(binary.read_bytes()).hexdigest()
pid=str(selected_switcher_pid(binary))
fixture=root/'corpus/native-load-v1.json'
fixture_digest=hashlib.sha256(fixture.read_bytes()).hexdigest()
fixtures=json.loads(fixture.read_text())
subprocess.run([str(root/'scripts/native_probe.sh'),'--build-only'],check=True,capture_output=True)
stop=threading.Event();samples=[]
def cpu_time():
 parts=subprocess.check_output(['ps','-p',pid,'-o','time='],text=True).strip().split(':');result=0.
 for part in parts:result=result*60+float(part)
 return result
def monitor():
 while not stop.is_set():
  values=subprocess.run(['ps','-p',pid,'-o','%cpu=,rss='],capture_output=True,text=True).stdout.split()
  if len(values)==2:samples.append({'seconds':time.monotonic()-start,'cpuPercent':float(values[0]),'rssKiB':int(values[1])})
  stop.wait(1)
start=time.monotonic();before=cpu_time();thread=threading.Thread(target=monitor);thread.start()
data=None
try:
 data=run_probe(root,binary,int(pid),['--batch',str(fixture),'--interval-ms','10','--settle-ms','100'],timeout=180)
 (out/'probe.json').write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n')
 validate_binding(data)
 input_seconds,idle_seconds=validate_workload_segments(data,0)
 require(data.get('completed')==len(fixtures) and len(data.get('results',[]))==len(fixtures),'Incomplete probe')
 require(hashlib.sha256(fixture.read_bytes()).hexdigest()==fixture_digest,'Fixture changed')
 require(selected_switcher_pid(binary)==int(pid),'Selected switcher changed')
 require(hashlib.sha256(binary.read_bytes()).hexdigest()==digest,'Binary changed')
 require(all(preserved_alternating(r['text']) for r in data['results']),'Text integrity failure')
 misses=correction_failures(data['results'],fixtures)
 after=cpu_time();elapsed=time.monotonic()-start
 report={'status':'completed','pid':int(pid),'binarySha256':digest,'fixtureSha256':hashlib.sha256(fixture.read_bytes()).hexdigest(),'probeSourceSha256':hashlib.sha256((root/'Tools/NativeProbe.swift').read_bytes()).hexdigest(),'wallSeconds':elapsed,'processCPUSeconds':round(after-before,3),'processCPUPercentOfWall':round(100*(after-before)/elapsed,2),'cases':12,'textIntegrityFailures':0,'fullyCorrectedPhrases':sum(r['text']=='привет hello '*8+' ' for r in data['results']),'notice':'Short observational synthetic TextEdit load run, includes setup/clear pauses; not 30-minute or other-app acceptance.'}
 report.update({'app':str(app),'integrityPassed':True,'correctionQualityPassed':not misses,'correctionFailureIDs':misses,'inputDurationSeconds':input_seconds,'idleDurationSeconds':idle_seconds})
except Exception as error:
 report={'status':'stopped','error':str(error),'pid':int(pid),'binarySha256':digest,'completed':data.get('completed') if data else None,'probeError':data.get('error') if data else None}
 if data and data.get('checkpoint'):
  saved=pathlib.Path(data['checkpoint']).resolve()
  if saved.is_relative_to(root/'research/private/probes') and saved.is_file():
   (out/'stopped-checkpoint.json').write_bytes(saved.read_bytes())
finally:
 stop.set();thread.join();(out/'samples.json').write_text(json.dumps(samples,indent=2)+'\n')
report.update({'fixtureSha256':hashlib.sha256(fixture.read_bytes()).hexdigest(),'probeSourceSha256':hashlib.sha256((root/'Tools/NativeProbe.swift').read_bytes()).hexdigest(),'medianSampleCPUPercent':statistics.median(s['cpuPercent'] for s in samples) if samples else None,'peakSampleCPUPercent':max((s['cpuPercent'] for s in samples),default=None),'peakRSSKiB':max((s['rssKiB'] for s in samples),default=None)})
(out/'summary.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n');print(json.dumps(report,ensure_ascii=False,indent=2))
if report['status']!='completed':sys.exit(1)
