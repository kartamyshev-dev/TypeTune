"""Offline regression checks; no app, keyboard events or existing evidence writes."""
import copy
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from native_evidence import digest
from verify_existing_build import validate_sources, capture_build_identity, validate_cli_artifacts

ROOT = Path(__file__).resolve().parents[1]


class AuditGateTests(unittest.TestCase):
    def test_cli_delivery_artifacts_are_bound_at_build(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root/'Sources').mkdir()
            (root/'Package.swift').write_text('fixture')
            (root/'Sources/main.swift').write_text('fixture')
            gui = root/'dist/LayoutPilot.app/Contents/MacOS/LayoutPilot'
            gui.parent.mkdir(parents=True); gui.write_text('gui')
            cli = root/'dist/layoutpilot-cli'; cli.write_text('cli')
            resource = root/'dist/LayoutPilot_LayoutPilotCore.bundle/Contents/Resources/lexicon.json'
            resource.parent.mkdir(parents=True); resource.write_text('lexicon')
            def git(*args):
                return subprocess.check_output(['git', '-C', str(root), *args], stderr=subprocess.PIPE)
            git('init', '-q'); git('add', 'Package.swift', 'Sources')
            git('-c', 'user.name=Audit', '-c', 'user.email=audit@localhost', 'commit', '-qm', 'fixture')
            identity = capture_build_identity(root)
            self.assertTrue(identity['compiledInputsMatchCommit'])
            validate_cli_artifacts(root, identity)
            for key in ['cliBinarySha256', 'cliBundleSha256']:
                missing = dict(identity); del missing[key]
                with self.assertRaises(ValueError): validate_cli_artifacts(root, missing)
            for path in [cli, resource]:
                original = path.read_bytes()
                path.write_bytes(original + b'changed')
                with self.assertRaises(ValueError): validate_cli_artifacts(root, identity)
                path.unlink()
                with self.assertRaises((ValueError, FileNotFoundError)): validate_cli_artifacts(root, identity)
                path.write_bytes(original)
            extra = resource.parent/'added.json'; extra.write_text('new')
            with self.assertRaises(ValueError): validate_cli_artifacts(root, identity)
            extra.unlink()
            extra.symlink_to(root/'Package.swift')
            with self.assertRaises(ValueError): validate_cli_artifacts(root, identity)
            extra.unlink()
            validate_cli_artifacts(root, identity)
            (root/'Sources/main.swift').write_text('uncommitted')
            self.assertFalse(capture_build_identity(root)['compiledInputsMatchCommit'])

    def test_native_suite_requires_complete_verified_run(self):
        fixtures = json.loads((ROOT/'corpus/native-smoke.json').read_text())
        rows = []
        for fixture in fixtures:
            row = {'id': fixture['id'], 'text': fixture['expected'],
                   'inputSource': fixture.get('expectedSource'), 'selection': fixture.get('expectedSelection')}
            if fixture['id'] == 'plain-paste': row['clipboardRestore'] = 'restored_all_representations'
            if fixture['id'] == 'auto-undo': row['beforeGesture'] = {'text': 'привет '}
            rows.append(row)
        good = dict(results=rows, processExitCode=0, completed=len(rows), identityUnchanged=True,
                    targetProcessUnchanged=True, finalModifierFlags=0,caseFileSha256=digest(ROOT/'corpus/native-smoke.json'))
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder)/'result.json'
            def verify(record, expected):
                path.write_text(json.dumps(record))
                result = subprocess.run([sys.executable, str(ROOT/'scripts/verify_native_suite.py'), str(path),
                                         '--fixtures', str(ROOT/'corpus/native-smoke.json')], capture_output=True, text=True)
                self.assertEqual(result.returncode, expected, result.stdout + result.stderr)
            verify(good, 0)
            mutations = [dict(processExitCode=2), dict(processExitCode=None), dict(processExitCode=False),
                         dict(identityUnchanged=False), dict(identityUnchanged=None), dict(targetProcessUnchanged=False),
                         dict(completed=len(rows)-1), dict(completed=None), dict(status='failed'), dict(status='running'),
                         dict(finalModifierFlags=None), dict(finalModifierFlags=True), dict(finalModifierFlags=1 << 20),
                         dict(finalModifierFlags=1 << 16), dict(finalModifierFlags=0x20)]
            for mutation in mutations:
                with self.subTest(mutation=mutation): verify(good | mutation, 1)
            missing = copy.deepcopy(good); del missing['finalModifierFlags']
            verify(missing, 1)
            checkpoint = copy.deepcopy(good)
            checkpoint['savedCheckpoint'] = {'results': checkpoint.pop('results')}
            verify(checkpoint, 1)
            bad_text = copy.deepcopy(good); bad_text['results'][0]['text'] = 'wrong'
            verify(bad_text, 1)
            # New identity-bound harness schema remains supported alongside the older recorder.
            identity = dict(schemaVersion=1, bundleHashAlgorithm='paths-files-modes-symlinks-v1',
                            **{key: 'a'*64 for key in ['targetBundleSha256', 'targetBinarySha256', 'probeSourceSha256', 'probeBinarySha256']},
                            targetProcess=dict(pid=42, command='/fixture/app', started='start'))
            bound = good | dict(identityBefore=identity, identityAfter=copy.deepcopy(identity),
                                helperProcess=dict(pid=43, command='/fixture/helper', started='start'),
                                helperExecutable='/fixture/helper', helperChildWaitVerified=True)
            del bound['targetProcessUnchanged']
            verify(bound, 0)
            bound['identityAfter']['targetProcess']['started'] = 'other-process'
            verify(bound, 1)

    def test_native_suite_rejects_mismatched_or_missing_fixture_digest(self):
        fixture = [{'id':'fixture','text':'hello','source':'ABC','expected':'hello '}]
        with tempfile.TemporaryDirectory() as folder:
            case_file = Path(folder)/'fixture.json'
            result_file = Path(folder)/'result.json'
            case_file.write_text(json.dumps(fixture))
            record = dict(results=[{'id':'fixture','text':'hello '}],processExitCode=0,completed=1,
                          identityUnchanged=True,targetProcessUnchanged=True,finalModifierFlags=0,
                          caseFileSha256=digest(case_file))
            def verify(expected):
                result_file.write_text(json.dumps(record))
                result = subprocess.run([sys.executable,str(ROOT/'scripts/verify_native_suite.py'),str(result_file),
                                         '--fixtures',str(case_file)],capture_output=True,text=True)
                self.assertEqual(result.returncode,expected,result.stdout+result.stderr)
                return json.loads(result.stdout)
            self.assertTrue(verify(0)['fixtureIdentityVerified'])
            # Same IDs/expected output cannot hide a changed input procedure.
            fixture[0]['text']='different input'
            case_file.write_text(json.dumps(fixture))
            changed=verify(1)
            self.assertFalse(changed['fixtureIdentityVerified'])
            self.assertIn('fixture_digest_mismatch_or_missing',changed['failures'])
            record['caseFileSha256']=digest(case_file)
            self.assertTrue(verify(0)['fixtureIdentityVerified'])
            for value in [None,False,'a'*64]:
                record['caseFileSha256']=value
                self.assertFalse(verify(1)['fixtureIdentityVerified'])
            del record['caseFileSha256']
            self.assertFalse(verify(1)['fixtureIdentityVerified'])

    def test_existing_build_requires_exact_source_and_resource_set(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder).resolve()
            (root/'Sources/Core/Resources').mkdir(parents=True)
            files = ['Package.swift', 'Sources/Core/main.swift', 'Sources/Core/Resources/lexicon.json']
            for name in files: (root/name).write_text(name)
            def git(*args):
                return subprocess.check_output(['git', '-C', str(root), *args], stderr=subprocess.PIPE)
            def commit():
                git('add', '.')
                git('-c', 'user.name=Audit', '-c', 'user.email=audit@localhost', 'commit', '-qm', 'fixture')
            git('init', '-q'); commit()
            sources = {name: digest(root/name) for name in files}
            validate_sources(root, sources)
            (root/'README.md').write_text('Documentation only'); commit()
            validate_sources(root, sources)
            for name in ['Sources/Core/Added.swift', 'Sources/Core/Resources/added.json']:
                with self.subTest(name=name):
                    (root/name).write_text('new compiled input'); commit()
                    with self.assertRaises(ValueError): validate_sources(root, sources)
                    (root/name).unlink(); commit()
            for name in files:
                with self.subTest(deleted=name):
                    (root/name).unlink()
                    with self.assertRaises(ValueError): validate_sources(root, sources)
                    (root/name).write_text(name)
            (root/files[1]).write_text('changed')
            with self.assertRaises(ValueError): validate_sources(root, sources)
            changed = sources | {files[1]: digest(root/files[1])}
            with self.assertRaises(ValueError): validate_sources(root, changed)  # Uncommitted bytes cannot become proof.
            (root/files[1]).write_text(files[1])
            (root/'Sources/Untracked.swift').write_text('untracked')
            with self.assertRaises(ValueError): validate_sources(root, sources)
            (root/'Sources/Untracked.swift').unlink()
            with self.assertRaises(ValueError): validate_sources(root, {})
            validate_sources(root, sources)


if __name__ == '__main__': unittest.main()
