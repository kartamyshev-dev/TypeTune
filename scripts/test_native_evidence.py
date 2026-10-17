#!/usr/bin/env python3
"""Pure temporary-file tamper fixtures; never starts a native helper or app."""
import copy
import json
import pathlib
import tempfile
from unittest.mock import patch
from native_evidence import bundle_digest, digest, validate_binding, validate_workload_segments, target_binary, selected_switcher_pid, capture
from verify_native_session import validate_session
from native_integrity import load_corpus_oracle, unknown_corpus_rows


def main():
    checks = 0
    def rejected(action):
        nonlocal checks
        try: action()
        except (ValueError, KeyError, FileNotFoundError): checks += 1
        else: raise AssertionError('Tamper accepted')
    with tempfile.TemporaryDirectory() as temp:
        root = pathlib.Path(temp).resolve()
        app = root/'Fixture.app'
        (app/'Contents/Resources').mkdir(parents=True)
        (app/'Contents/Resources/lexicon').write_text('one')
        binary = app/'Contents/MacOS/LayoutPilot'
        binary.parent.mkdir(); binary.write_text('fixture')
        assert target_binary(root, app) == binary; checks += 1
        default = root/'dist/LayoutPilot.app/Contents/MacOS/LayoutPilot'
        default.parent.mkdir(parents=True); default.write_text('default')
        assert target_binary(root) == default; checks += 1
        rejected(lambda: target_binary(root, root/'Missing.app'))
        rejected(lambda: target_binary(root, app, target='original'))
        with patch('native_evidence.subprocess.check_output', return_value=f'42 {binary}\n'):
            assert selected_switcher_pid(binary) == 42; checks += 1
        for roster in [f'42 {default}\n', f'42 {binary}\n43 /other/TypeTune\n',
                       f'42 {binary}\n43 /other/LangSwitcher\n', '']:
            with patch('native_evidence.subprocess.check_output', return_value=roster):
                rejected(lambda: selected_switcher_pid(binary))
        with patch('native_evidence.process_identity', return_value={'pid':42,'command':str(default),'started':'same'}):
            rejected(lambda: capture(root, binary, 42))
        first = bundle_digest(app)
        (app/'Contents/Resources/lexicon').write_text('two')
        assert first != bundle_digest(app); checks += 1
        (app/'Contents/Resources/link').symlink_to('lexicon')
        linked = bundle_digest(app)
        (app/'Contents/Resources/link').unlink()
        assert linked != bundle_digest(app); checks += 1
        identity = {'schemaVersion': 1, 'bundleHashAlgorithm': 'paths-files-modes-symlinks-v1',
                    **{key: 'a'*64 for key in ['targetBundleSha256','targetBinarySha256','probeSourceSha256','probeBinarySha256']},
                    'targetProcess': {'pid': 42, 'command': '/fixture/Target', 'started': 'fixture-start'}}
        record = {'identityBefore': identity, 'identityAfter': copy.deepcopy(identity), 'identityUnchanged': True,
                  'helperProcess': {'pid': 43, 'command': '/fixture/Helper', 'started': 'helper-start'},
                  'helperExecutable': '/fixture/Helper', 'helperChildWaitVerified': True, 'processExitCode': 0,
                  'finalModifierFlags':0, 'inputSegmentSeconds':1, 'idleSegmentSeconds':0,
                  'requiredIdleSeconds':0, 'idleEvents':0, 'helperWallSeconds':2}
        assert validate_binding(record) == identity; checks += 1
        for mutate in [lambda r: r['identityAfter'].__setitem__('targetBundleSha256','b'*64),
                       lambda r: r['identityAfter']['targetProcess'].__setitem__('started','reused-PID'),
                       lambda r: r.__setitem__('helperChildWaitVerified',False),
                       lambda r: r['helperProcess'].__setitem__('command','/other/helper'),
                       lambda r: r.__setitem__('processExitCode',1),
                       lambda r: r.__setitem__('processExitCode',False),
                       lambda r: r.pop('finalModifierFlags'),
                       lambda r: r.__setitem__('finalModifierFlags',True),
                       lambda r: r.__setitem__('finalModifierFlags',-1),
                       lambda r: r.__setitem__('finalModifierFlags',0x20),
                       lambda r: r.__setitem__('finalModifierFlags',1 << 20),
                       lambda r: r.__setitem__('error','probe_failed')]:
            changed=copy.deepcopy(record); mutate(changed)
            rejected(lambda: validate_binding(changed))
        rejected(lambda: validate_binding({'targetBinarySha256':'a'*64}))
        assert validate_workload_segments(record,0) == (1,0); checks+=1
        for change in [dict(inputSegmentSeconds=None),dict(inputSegmentSeconds=0),dict(inputSegmentSeconds=True),
                       dict(inputSegmentSeconds=-1),dict(inputSegmentSeconds=float('nan')),
                       dict(idleSegmentSeconds=1),dict(requiredIdleSeconds=True),dict(requiredIdleSeconds=30),
                       dict(idleEvents=1),dict(idleEvents=False),dict(helperWallSeconds=0.5)]:
            rejected(lambda: validate_workload_segments(dict(record,**change),0))
        corpus = root/'corpus'; corpus.mkdir()
        fixtures=[{'id': str(i), 'text':'hello', 'source':'ABC', 'expected':'hello '} for i in range(1000)]
        fixtures[0].update(text='ghbdtn', expected='привет ')
        (corpus/'native-v1.json').write_text(json.dumps(fixtures))
        synthetic = [{'id':str(i), 'input':'hello', 'expected':'hello'} for i in range(1000)]
        synthetic[0].update(input='ghbdtn', expected='привет')
        (corpus/'synthetic-v2.jsonl').write_text('\n'.join(json.dumps(row) for row in synthetic)+'\n')
        _, oracle_identity = load_corpus_oracle(corpus/'native-v1.json', corpus/'synthetic-v2.jsonl')
        comparison=root/'research/evidence/native-corpus-prototype/test'; comparison.mkdir(parents=True)
        for index in range(5):
            batch=copy.deepcopy(record)
            batch.update(target='prototype',cases=200,completed=200,checkpoint='fixture.results.json',caseFileSha256=digest(corpus/'native-v1.json'),totalEvents=200)
            batch['corpusIntegrity']={'fixtureIdentity':oracle_identity}
            batch['results']=[{'id':str(i),'physicalASCII':fixtures[i]['text'],'requestedSource':'com.apple.keylayout.ABC','boundary':True,'gesture':'none','selectAllBeforeGesture':False,'clipboardRestore':'not_used','pasteText':None,'text':fixtures[i]['expected'],'events':1} for i in range(index*200,(index+1)*200)]
            (comparison/f'{index:02}.json').write_text(json.dumps(batch))
        folder=root/'session'; folder.mkdir()
        stability=root/'research/private/native-batches';stability.mkdir(parents=True)
        stream = {'id':'stream','text':'ghbdtn hello '*8,'source':'ABC','boundary':True,'expected':'привет hello '*8+' ',
                  'expectedSource':'com.apple.keylayout.ABC','expectedSelection':{'location':105,'length':0}}
        stream_file=corpus/'native-fast-stream-v1.json';stream_file.write_text(json.dumps([stream]))
        case=stability/'stability-test-0.json';case.write_text(json.dumps([dict(stream,id='stability-0-0')]))
        result=copy.deepcopy(record);result.update(idleSegmentSeconds=30,requiredIdleSeconds=30,helperWallSeconds=32,completed=1,nativeBatchSha256=digest(case),results=[{'id':'stability-0-0','text':stream['expected'],
                'inputSource':stream['expectedSource'],'selection':stream['expectedSelection']}])
        (folder/'stability-0.json').write_text(json.dumps(result))
        summary={'status':'completed','atLeast30Minutes':True,'atLeast4Hours':False,'requiredDurationSeconds':1800,'durationSeconds':1800,'requiredIdleSecondsPerBatch':30,'inputDurationSeconds':6,'idleDurationSeconds':30,'identityUnchanged':True,'identityBefore':identity,'identityAfter':copy.deepcopy(identity),'comparisonRun':'test','streamFixtureSha256':digest(stream_file),'stabilityBatches':[{'index':0,'cases':1,'inputSegmentSeconds':1,'idleSegmentSeconds':30,'textIntegrityFailures':[]}]}
        (folder/'summary.json').write_text(json.dumps(summary))
        samples=[{'seconds':i*2,'cpuPercent':1,'rssKiB':100} for i in range(901)]
        (folder/'telemetry.json').write_text(json.dumps(samples))
        good = validate_session(folder,identity,root)
        assert good['passed'] and good['integrityPassed'] and good['correctionQualityPassed'];checks+=1
        assert good['requiredDurationSeconds'] == 1800 and good['atLeast4Hours'] is False;checks+=1
        for mutation in [dict(requiredDurationSeconds=value) for value in [None, True, 1800.0, 1740, 1801, 86460]] + [
                dict(durationSeconds=1799), dict(durationSeconds=float('nan')), dict(durationSeconds=float('inf')),
                dict(requiredDurationSeconds=14400), dict(atLeast4Hours=True), dict(atLeast4Hours=None),
                dict(requiredDurationSeconds=14400, durationSeconds=14400, atLeast4Hours=False),
                dict(requiredIdleSecondsPerBatch=None),dict(requiredIdleSecondsPerBatch=0),
                dict(inputDurationSeconds=5),dict(idleDurationSeconds=0),dict(idleDurationSeconds=float('nan'))]:
            (folder/'summary.json').write_text(json.dumps(dict(summary, **mutation)))
            rejected(lambda: validate_session(folder,identity,root))
        for duration in [14400, 86400]:
            (folder/'summary.json').write_text(json.dumps(dict(summary,requiredDurationSeconds=duration,durationSeconds=duration,atLeast4Hours=True)))
            long_samples=[{'seconds':i*2,'cpuPercent':1,'rssKiB':100} for i in range(duration//2+1)]
            (folder/'telemetry.json').write_text(json.dumps(long_samples))
            long_report=validate_session(folder,identity,root)
            assert long_report['passed'] and long_report['atLeast4Hours'] and long_report['requiredDurationSeconds']==duration;checks+=1
        (folder/'summary.json').write_text(json.dumps(summary))
        (folder/'telemetry.json').write_text(json.dumps(samples))
        for change in [dict(idleSegmentSeconds=29.99),dict(idleSegmentSeconds=float('inf')),
                       dict(idleEvents=1),dict(requiredIdleSeconds=0),dict(helperWallSeconds=30),
                       dict(finalModifierFlags=0x20)]:
            (folder/'stability-0.json').write_text(json.dumps(dict(result,**change)))
            rejected(lambda: validate_session(folder,identity,root))
        (folder/'stability-0.json').write_text(json.dumps(result))
        comparison_first = comparison/'00.json'
        original_first = json.loads(comparison_first.read_text())
        missed_first = copy.deepcopy(original_first)
        missed_first['results'][0]['text']='ghbdtn '
        missed_first['correctionQualityPassed']=True
        comparison_first.write_text(json.dumps(missed_first))
        missed = validate_session(folder,identity,root)
        assert missed['integrityPassed'] and not missed['correctionQualityPassed'] and not missed['passed']
        assert missed['comparisonCorrectionFailureIDs'] == ['0']; checks += 1
        corrupt_first = copy.deepcopy(original_first)
        corrupt_first['results'][0]['text']=''
        comparison_first.write_text(json.dumps(corrupt_first))
        rejected(lambda: validate_session(folder,identity,root))
        corrupt_first = copy.deepcopy(original_first)
        corrupt_first['corpusIntegrity']['fixtureIdentity']['syntheticSha256']='b'*64
        comparison_first.write_text(json.dumps(corrupt_first))
        rejected(lambda: validate_session(folder,identity,root))
        comparison_first.write_text(json.dumps(original_first))
        original_batches=summary['stabilityBatches'];summary['stabilityBatches']=[]
        (folder/'summary.json').write_text(json.dumps(summary))
        rejected(lambda: validate_session(folder,identity,root))
        summary['stabilityBatches']=original_batches
        (folder/'summary.json').write_text(json.dumps(summary))
        for mutation in [dict(text='ghbdtn hello '*8+' '), dict(inputSource='com.apple.keylayout.RussianWin'),
                         dict(selection={'location':0,'length':0})]:
            missed_result=copy.deepcopy(result)
            missed_result['results'][0].update(mutation)
            missed_result['correctionQualityPassed']=True
            (folder/'stability-0.json').write_text(json.dumps(missed_result))
            missed=validate_session(folder,identity,root)
            assert missed['integrityPassed'] and not missed['correctionQualityPassed'] and not missed['passed']
            assert missed['stabilityCorrectionFailureIDs'] == ['stability-0-0']; checks += 1
        expected_case=case.read_text()
        changed_case=json.loads(expected_case);changed_case[0]['expected']='ghbdtn hello '*8+' '
        case.write_text(json.dumps(changed_case))
        changed_result=copy.deepcopy(result);changed_result['nativeBatchSha256']=digest(case)
        (folder/'stability-0.json').write_text(json.dumps(changed_result))
        rejected(lambda: validate_session(folder,identity,root))
        case.write_text(expected_case)
        # A clean summary cannot hide corrupted actual text.
        result['results'][0]['text']='lost text'
        (folder/'stability-0.json').write_text(json.dumps(result))
        rejected(lambda: validate_session(folder,identity,root))
        result['results'][0]['text']='привет hello '*8+' '
        (folder/'stability-0.json').write_text(json.dumps(result))
        samples[400]['seconds']=samples[399]['seconds']
        (folder/'telemetry.json').write_text(json.dumps(samples))
        rejected(lambda: validate_session(folder,identity,root))
        samples[400]['seconds']=800
        (folder/'telemetry.json').write_text(json.dumps(samples))
        stale=copy.deepcopy(identity);stale['targetBundleSha256']='c'*64
        rejected(lambda: validate_session(folder,stale,root))
    print(f'{checks} offline identity/session/tamper checks PASS; no native acceptance')


if __name__=='__main__': main()
