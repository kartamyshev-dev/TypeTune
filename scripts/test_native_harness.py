#!/usr/bin/env python3
"""Offline orchestration checks with fake processes; never starts apps or probes."""
import contextlib
import copy
import hashlib
import io
import json
from pathlib import Path
import subprocess
import shutil
import sys
import tempfile
import unittest
from unittest.mock import patch, Mock
from native_evidence import bundle_digest, digest, run_probe, validate_binding, validate_workload_segments
import verify_native_session
import verify_existing_build

ROOT = Path(__file__).resolve().parents[1]


class NativeHarnessTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        self.app = self.root/'Applications/Layout Pilot.app'
        self.binary = self.app/'Contents/MacOS/LayoutPilot'
        for path in [self.binary, self.root/'.build/native-probe', self.root/'Tools/NativeProbe.swift']:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text('synthetic fixture')
        for folder in ['corpus', 'research/evidence', 'research/private/native-batches']:
            (self.root/folder).mkdir(parents=True, exist_ok=True)
        self.stream = json.loads((ROOT/'corpus/native-fast-stream-v1.json').read_text())[0]
        self.write('corpus/native-fast-stream-v1.json', [self.stream])
        self.identity = {'schemaVersion':1, 'bundleHashAlgorithm':'paths-files-modes-symlinks-v1',
                         'targetBundleSha256':bundle_digest(self.app), 'targetBinarySha256':digest(self.binary),
                         'probeSourceSha256':digest(self.root/'Tools/NativeProbe.swift'),
                         'probeBinarySha256':digest(self.root/'.build/native-probe'),
                         'targetProcess':{'pid':42, 'command':str(self.binary), 'started':'target-start'}}
        self.record = {'identityBefore':self.identity, 'identityAfter':copy.deepcopy(self.identity), 'identityUnchanged':True,
                       'helperExecutable':str(self.root/'.build/native-probe'), 'helperChildWaitVerified':True,
                       'helperProcess':{'pid':43, 'command':str(self.root/'.build/native-probe'), 'started':'helper-start'},
                       'processExitCode':0,'finalModifierFlags':0,'inputSegmentSeconds':1,'idleSegmentSeconds':0,
                       'requiredIdleSeconds':0,'idleEvents':0,'helperWallSeconds':32}

    def write(self, path, value):
        destination = self.root/path
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_text(json.dumps(value))

    def execute(self, name, args):
        source = ROOT/'scripts'/name
        with patch.object(sys, 'argv', [str(source), *args]), contextlib.redirect_stdout(io.StringIO()):
            exec(compile(source.read_text(), str(source), 'exec'),
                 {'__name__':'__main__', '__file__':str(self.root/'scripts'/name)})

    def test_session_forwards_exact_app_and_stream_expectations(self):
        for name, duration_args, required, expected_batches in [('default',[],1800,1), ('four-hours',['--duration-minutes','240'],14400,5)]:
            with self.subTest(duration=required):
                calls, elapsed, batches = [], [0], []
                def command(argv, **kwargs):
                    calls.append(argv)
                    if 'run_native_corpus.py' in argv[1]:
                        self.assertEqual(argv[argv.index('--app')+1], str(self.app))
                        self.write(f'research/evidence/native-corpus-prototype/{name}/summary.json',
                                   {'integrityPassed':True, 'correctionQualityPassed':True,'inputDurationSeconds':5,'idleDurationSeconds':0})
                        elapsed[0] = 1801 if not duration_args else 0
                    return subprocess.CompletedProcess(argv, 0, stdout=str(self.binary)+'\n')
                def probe(root, binary, pid, arguments, timeout):
                    self.assertEqual((root, binary, pid), (self.root, self.binary, 42))
                    self.assertIn('--idle-after-batch', arguments)
                    cases = json.loads(Path(arguments[1]).read_text())
                    self.assertEqual(cases[0], dict(self.stream, id=f'stability-{len(batches)}-0'))
                    batches.append(cases)
                    elapsed[0] += 3000 if duration_args else 0
                    result = copy.deepcopy(self.record)
                    result.update(idleSegmentSeconds=30,requiredIdleSeconds=30,completed=len(cases), results=[{'id':row['id'], 'text':row['expected'],
                                  'inputSource':row['expectedSource'], 'selection':row['expectedSelection']} for row in cases])
                    return result
                with patch('native_evidence.subprocess.check_output', return_value=f'42 {self.binary}\n'), \
                     patch('subprocess.run', side_effect=command), \
                     patch('native_evidence.capture', return_value=self.identity) as capture, \
                     patch('native_evidence.run_probe', side_effect=probe), \
                     patch('threading.Thread'), patch('time.monotonic', side_effect=lambda:elapsed[0]):
                    self.execute('run_native_session.py', ['--run-id',name,'--app',str(self.app),*duration_args])
                self.assertTrue(all(call.args[1] == self.binary for call in capture.call_args_list))
                verifier = next(argv for argv in calls if 'verify_native_session.py' in argv[1])
                self.assertEqual(verifier[-2:], ['--app', str(self.app)])
                summary = json.loads((self.root/f'research/evidence/native-session-{name}/summary.json').read_text())
                self.assertTrue(summary['integrityPassed'] and summary['correctionQualityPassed'])
                self.assertEqual(summary['streamFixtureSha256'], digest(self.root/'corpus/native-fast-stream-v1.json'))
                self.assertEqual(summary['requiredDurationSeconds'], required)
                self.assertEqual(len(summary['stabilityBatches']), expected_batches)
                self.assertEqual(summary['atLeast4Hours'], bool(duration_args))
                self.assertEqual(summary['inputDurationSeconds'], 5+expected_batches)
                self.assertEqual(summary['idleDurationSeconds'], 30*expected_batches)

    def test_session_rejects_invalid_duration_before_process_or_file_access(self):
        for duration in ['29','1441','0','-1','30.5','invalid']:
            with self.subTest(duration=duration), patch('native_evidence.target_binary') as target, \
                 patch('subprocess.run') as command, contextlib.redirect_stderr(io.StringIO()):
                with self.assertRaises(SystemExit) as stopped:
                    self.execute('run_native_session.py', ['--run-id','invalid','--duration-minutes',duration])
                self.assertEqual(stopped.exception.code, 2)
                target.assert_not_called()
                command.assert_not_called()
        self.assertFalse((self.root/'research/evidence/native-session-invalid').exists())

    def test_long_session_stops_after_first_failed_helper(self):
        calls = []
        def command(argv, **kwargs):
            calls.append(argv)
            if 'run_native_corpus.py' in argv[1]:
                self.write('research/evidence/native-corpus-prototype/failed/summary.json',
                           {'integrityPassed':True,'correctionQualityPassed':True,'inputDurationSeconds':5,'idleDurationSeconds':0})
            return subprocess.CompletedProcess(argv, 0)
        failed = dict(self.record,processExitCode=1)
        with patch('native_evidence.subprocess.check_output', return_value=f'42 {self.binary}\n'), \
             patch('subprocess.run', side_effect=command), patch('native_evidence.capture', return_value=self.identity), \
             patch('native_evidence.run_probe', return_value=failed) as probe, \
             patch('threading.Thread'), patch('time.monotonic', return_value=0):
            with self.assertRaises(SystemExit) as stopped:
                self.execute('run_native_session.py', ['--run-id','failed','--app',str(self.app),'--duration-minutes','240'])
        self.assertEqual(stopped.exception.code, 1)
        self.assertEqual(probe.call_count, 1)
        self.assertFalse(any('verify_native_session.py' in argv[1] for argv in calls))
        summary = json.loads((self.root/'research/evidence/native-session-failed/summary.json').read_text())
        self.assertEqual(summary['status'], 'failed')
        self.assertEqual(summary['requiredDurationSeconds'], 14400)
        self.assertFalse(summary['atLeast4Hours'])

    def test_corpus_selected_app_reports_raw_as_quality_failure(self):
        fixture = {'id':'word','text':'ghbdtn','source':'ABC','expected':'привет ','split':'train','category':'fixture'}
        self.write('corpus/native-v1.json', [fixture])
        (self.root/'corpus/synthetic-v2.jsonl').write_text(json.dumps({'id':'word','input':'ghbdtn','expected':'привет'})+'\n')
        self.write('research/private/native-batches/00.json', [fixture])
        record = copy.deepcopy(self.record)
        record.update(completed=1, results=[{'id':'word','text':'ghbdtn '}])
        with patch('native_evidence.subprocess.check_output', return_value=f'42 {self.binary}\n'), \
             patch('subprocess.run', return_value=subprocess.CompletedProcess([],0,stdout=str(self.binary)+'\n')), \
             patch('native_evidence.capture', return_value=self.identity), \
             patch('native_evidence.run_probe', return_value=record) as probe:
            self.execute('run_native_corpus.py', ['--target','prototype','--batches','1','--run-id','fixture','--app',str(self.app)])
        self.assertEqual(probe.call_args.args[1:3], (self.binary,42))
        summary = json.loads((self.root/'research/evidence/native-corpus-prototype/fixture/summary.json').read_text())
        self.assertTrue(summary['integrityPassed'])
        self.assertFalse(summary['correctionQualityPassed'])
        batch = json.loads((self.root/'research/evidence/native-corpus-prototype/fixture/00.json').read_text())
        self.assertEqual(batch['correctionFailureIDs'], ['word'])

    def test_session_stops_on_first_stream_quality_miss(self):
        def command(argv, **kwargs):
            if 'run_native_corpus.py' in argv[1]:
                self.write('research/evidence/native-corpus-prototype/missed/summary.json',
                           {'integrityPassed':True,'correctionQualityPassed':True,'inputDurationSeconds':5,'idleDurationSeconds':0})
            return subprocess.CompletedProcess(argv, 0)
        def missed_probe(root, binary, pid, arguments, timeout):
            cases=json.loads(Path(arguments[1]).read_text())
            return dict(self.record, idleSegmentSeconds=30,requiredIdleSeconds=30,completed=len(cases),
                        results=[{'id':r['id'],'text':r['text']+' ','inputSource':r['expectedSource'],
                                  'selection':r['expectedSelection']} for r in cases])
        with patch('native_evidence.subprocess.check_output', return_value=f'42 {self.binary}\n'), \
             patch('subprocess.run', side_effect=command), patch('native_evidence.capture', return_value=self.identity), \
             patch('native_evidence.run_probe', side_effect=missed_probe) as probe, \
             patch('threading.Thread'), patch('time.monotonic', return_value=0):
            with self.assertRaises(SystemExit):
                self.execute('run_native_session.py',['--run-id','missed','--app',str(self.app),'--duration-minutes','240'])
        self.assertEqual(probe.call_count,1)
        summary=json.loads((self.root/'research/evidence/native-session-missed/summary.json').read_text())
        self.assertEqual(summary['status'],'failed')
        self.assertIn('correction quality',summary['reason'])
        self.assertTrue(summary['stabilityBatches'][0]['integrityPassed'])
        self.assertFalse(summary['stabilityBatches'][0]['correctionQualityPassed'])

    def test_probe_waits_exact_child_and_owns_wall_duration(self):
        child=Mock(pid=43,returncode=0)
        child.communicate.return_value=(json.dumps(dict(self.record,helperWallSeconds=999)), '')
        with patch('native_evidence.capture', return_value=self.identity), \
             patch('native_evidence.process_identity',return_value=self.record['helperProcess']), \
             patch('native_evidence.subprocess.Popen',return_value=child) as process, \
             patch('native_evidence.time.monotonic',side_effect=[10,12]):
            result=run_probe(self.root,self.binary,42,['--batch','fixed.json'],180)
        self.assertEqual(process.call_args.args[0],[str(self.root/'.build/native-probe'),'--batch','fixed.json'])
        child.communicate.assert_called_once_with(timeout=180)
        self.assertEqual(result['helperWallSeconds'],2)
        self.assertEqual(validate_binding(result),self.identity)
        self.assertEqual(validate_workload_segments(result,0),(1,0))

    def test_recorder_forwards_installed_app_to_bound_helper(self):
        self.write('corpus/regressions.json',[self.stream])
        output=self.root/'research/evidence/smoke.json'
        def lookup(argv, **kwargs):
            return 'fixture-commit' if argv[0]=='git' else f'42 {self.binary}\n'
        with patch('subprocess.check_output',side_effect=lookup), \
             patch('subprocess.run',return_value=subprocess.CompletedProcess([],0)), \
             patch('native_evidence.run_probe',return_value=copy.deepcopy(self.record)) as probe:
            with self.assertRaises(SystemExit) as stopped:
                self.execute('record_native_probe.py',['--app',str(self.app),'--output',str(output),
                            '--batch',str(self.root/'corpus/regressions.json')])
        self.assertEqual(stopped.exception.code,0)
        self.assertEqual(probe.call_args.args[1:3],(self.binary,42))
        record=json.loads(output.read_text())
        self.assertEqual(record['app'],str(self.app))
        self.assertEqual(record['caseFileSha256'],digest(self.root/'corpus/regressions.json'))
        self.assertEqual(validate_binding(record),self.identity)

    def test_load_accepts_selected_app_with_quality_separate_from_integrity(self):
        fixtures=[dict(self.stream,id=f'load-{i}') for i in range(12)]
        self.write('corpus/native-load-v1.json',fixtures)
        record=copy.deepcopy(self.record)
        record.update(completed=12,results=[{'id':r['id'],'text':r['text']+' ','inputSource':r['expectedSource'],
                                           'selection':r['expectedSelection']} for r in fixtures])
        def lookup(argv, **kwargs):return '00:01.00' if 'time=' in argv else f'42 {self.binary}\n'
        with patch('subprocess.check_output',side_effect=lookup), \
             patch('subprocess.run',return_value=subprocess.CompletedProcess([],0)), \
             patch('threading.Thread'),patch('native_evidence.run_probe',return_value=record) as probe:
            self.execute('measure_native_load.py',['--app',str(self.app),'--run-id','quality'])
        self.assertEqual(probe.call_args.args[1:3],(self.binary,42))
        summary=json.loads((self.root/'research/evidence/native-load-quality/summary.json').read_text())
        self.assertEqual(summary['status'],'completed')
        self.assertTrue(summary['integrityPassed'])
        self.assertFalse(summary['correctionQualityPassed'])

    def test_initial_cases_forward_app_and_reject_held_modifiers(self):
        fixture={'id':'seed','initialText':'привет','text':'','source':'ABC','gesture':'doubleShift',
                 'boundary':False,'selectAllBeforeGesture':True,'expected':'ghbdtn',
                 'expectedSource':'com.apple.keylayout.ABC','expectedSelection':{'location':0,'length':6}}
        self.write('corpus/seed.json',{'schemaVersion':1,'cases':[fixture]})
        record=dict(self.record,text=fixture['expected'],inputSource=fixture['expectedSource'],
                    selection=fixture['expectedSelection'],beforeGesture={'text':'привет','selection':{'location':0,'length':6}})
        def command(argv, **kwargs):
            self.assertEqual(argv[argv.index('--app')+1],str(self.app))
            Path(argv[argv.index('--output')+1]).write_text(json.dumps(record))
            return subprocess.CompletedProcess(argv,0)
        for name,flags,expected in [('clean',0,0),('held',0x20,1)]:
            record['finalModifierFlags']=flags
            with patch('subprocess.run',side_effect=command):
                with self.assertRaises(SystemExit) as stopped:
                    self.execute('record_native_initial_cases.py',['--app',str(self.app),
                        '--fixture',str(self.root/'corpus/seed.json'),'--output-dir',str(self.root/f'research/evidence/{name}')])
            self.assertEqual(stopped.exception.code,expected)

    def test_verifier_uses_app_and_exits_nonzero_for_quality_failure(self):
        self.write('session/summary.json', {'pid':42})
        report = {'passed':False, 'integrityPassed':True, 'correctionQualityPassed':False}
        with patch.object(verify_native_session, '__file__', str(self.root/'scripts/verify_native_session.py')), \
             patch.object(verify_native_session, 'capture', return_value=self.identity) as capture, \
             patch.object(verify_native_session, 'validate_session', return_value=report), \
             patch.object(sys, 'argv', ['verify_native_session.py',str(self.root/'session'),'--app',str(self.app)]), \
             contextlib.redirect_stdout(io.StringIO()):
            with self.assertRaises(SystemExit) as stopped:
                verify_native_session.main()
        self.assertEqual(stopped.exception.code, 1)
        capture.assert_called_once_with(self.root, self.binary, 42)
        self.assertEqual(json.loads((self.root/'session/verification.json').read_text()), report)

    def test_package_verifier_requires_matching_bundle_and_quality(self):
        packaged = self.root/'dist/LayoutPilot.app'
        shutil.copytree(self.app, packaged)
        manifest = [(str(path.relative_to(packaged)), digest(path)) for path in sorted(packaged.rglob('*')) if path.is_file()]
        self.write('identity.json', {'compiledInputsMatchCommit':True, 'sources':{}, 'binarySha256':digest(self.binary),
                                    'bundleSha256':hashlib.sha256(json.dumps(manifest, ensure_ascii=False, separators=(',', ':')).encode()).hexdigest()})
        self.write('session/summary.json', {'pid':42})
        report = {'passed':False, 'integrityPassed':True, 'correctionQualityPassed':False, 'durationSeconds':1800}
        with patch.object(verify_existing_build, '__file__', str(self.root/'scripts/verify_existing_build.py')), \
             patch.object(verify_existing_build, 'validate_sources'), patch.object(verify_existing_build, 'validate_cli_artifacts'), \
             patch.object(verify_existing_build, 'capture', return_value=self.identity) as capture, \
             patch.object(verify_existing_build, 'validate_session', return_value=report), \
             patch('subprocess.run') as command, contextlib.redirect_stdout(io.StringIO()), \
             patch.object(sys, 'argv', ['verify_existing_build.py',str(self.root/'identity.json'),str(self.root/'session'),'--app',str(self.app)]):
            with self.assertRaisesRegex(ValueError, 'correction quality failed'):
                verify_existing_build.main()
            capture.assert_called_once_with(self.root, self.binary, 42)
            command.assert_not_called()
            self.binary.write_text('different installed build')
            with self.assertRaisesRegex(ValueError, 'differs from packaged'):
                verify_existing_build.main()
            self.assertEqual(capture.call_count, 1)
            command.assert_not_called()


if __name__ == '__main__':
    unittest.main()
