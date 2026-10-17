#!/usr/bin/env python3
"""Pure argument decoding and evidence validation; never invokes native probe mode."""
import copy
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from native_integrity import validate_regression_timing
from native_evidence import digest

ROOT = Path(__file__).resolve().parents[1]


class NativeProbeFixtureTests(unittest.TestCase):
    def setUp(self):
        self.fixtures = json.loads((ROOT/'corpus/native-stability-regressions-v1.json').read_text())
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.case_file = Path(self.temp.name)/'cases.json'

    def validate(self, cases, *arguments):
        self.case_file.write_text(json.dumps(cases))
        # This mode returns immediately after parsing; no AX/TIS/apps/events are used.
        return subprocess.run([str(ROOT/'.build/native-probe'), '--validate-cases', '--batch', str(self.case_file),
                               *arguments], capture_output=True, text=True, timeout=5)

    def test_authored_regressions_are_bounded_and_decode_without_native(self):
        for arguments in [(), ('--idle-after-batch',)]:
            result = self.validate(self.fixtures, *arguments)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertEqual(json.loads(result.stdout), {'validatedCases':3,'events':0,
                             'pureFixtureValidation':True,'nativeAcceptance':False})
        control = json.loads((ROOT/'corpus/native-fast-stream-v1.json').read_text())[0]
        self.assertEqual(self.fixtures[2]['text'], control['text'])
        self.assertEqual(self.fixtures[2]['expected'], control['expected'])
        self.assertEqual(self.fixtures[2]['expectedSelection'], control['expectedSelection'])

    def test_rejects_unsafe_or_ambiguous_timing_modes(self):
        for mutation in [dict(text='hello'),dict(source='RussianWin'),dict(gesture='doubleShift'),
                         dict(boundary=False),dict(selectAllBeforeGesture=True)]:
            with self.subTest(firstWord=mutation):
                cases=copy.deepcopy(self.fixtures);cases[0].update(mutation)
                self.assertNotEqual(self.validate(cases).returncode, 0)
        cases=copy.deepcopy(self.fixtures);cases[0],cases[1]=cases[1],cases[0]
        self.assertNotEqual(self.validate(cases).returncode, 0)
        for mutation in [dict(preGestureDelayMilliseconds=-1),dict(preGestureDelayMilliseconds=1001),
                         dict(preGestureDelayMilliseconds=0.5),dict(preGestureDelayMilliseconds=True),
                         dict(gesture='none'),dict(boundary=True),dict(selectAllBeforeGesture=True)]:
            with self.subTest(immediate=mutation):
                cases=copy.deepcopy(self.fixtures);cases[1].update(mutation)
                self.assertNotEqual(self.validate(cases).returncode, 0)
        self.assertNotEqual(self.validate(self.fixtures,'--status').returncode,0)
        self.assertNotEqual(self.validate(self.fixtures,'--initial-text','x').returncode,0)

    def test_new_timing_requirements_need_measurements(self):
        rows = [{'timing':{'firstWordAfterFocus':True,'firstInputAfterFocusMilliseconds':12}},
                {'timing':{'preGestureDelayMilliseconds':0,'gestureAfterTypingMilliseconds':20}}]
        for row, fixture in zip(rows, self.fixtures):
            validate_regression_timing(row, fixture)
            for missing in [{}, {'timing':{}}, {'timing':None}]:
                with self.assertRaises(ValueError):validate_regression_timing(missing,fixture)
        for key,row_index in [('firstInputAfterFocusMilliseconds',0),('gestureAfterTypingMilliseconds',1)]:
            for bad in [None,True,-1,float('nan'),float('inf')]:
                changed=copy.deepcopy(rows[row_index]);changed['timing'][key]=bad
                with self.assertRaises(ValueError):validate_regression_timing(changed,self.fixtures[row_index])
        for bad in [False,100,None]:
            changed=copy.deepcopy(rows[1]);changed['timing']['preGestureDelayMilliseconds']=bad
            with self.assertRaises(ValueError):validate_regression_timing(changed,self.fixtures[1])

    def test_suite_rejects_correct_text_without_executed_timing_mode(self):
        rows=[{'id':row['id'],'text':row['expected'],'inputSource':row['expectedSource'],
               'selection':row['expectedSelection']} for row in self.fixtures]
        rows[0]['timing']={'firstWordAfterFocus':True,'firstInputAfterFocusMilliseconds':12}
        rows[1]['timing']={'preGestureDelayMilliseconds':0,'gestureAfterTypingMilliseconds':20}
        data={'results':rows,'completed':3,'processExitCode':0,'identityUnchanged':True,
              'targetProcessUnchanged':True,'finalModifierFlags':0,
              'caseFileSha256':digest(ROOT/'corpus/native-stability-regressions-v1.json')}
        destination=Path(self.temp.name)/'result.json'
        def verify():
            destination.write_text(json.dumps(data))
            return subprocess.run([sys.executable,str(ROOT/'scripts/verify_native_suite.py'),str(destination),
                '--fixtures',str(ROOT/'corpus/native-stability-regressions-v1.json')],capture_output=True,text=True)
        self.assertEqual(verify().returncode,0)
        del rows[0]['timing']
        rejected=verify()
        self.assertEqual(rejected.returncode,1)
        self.assertIn('first_word_timing_not_verified',rejected.stdout)


if __name__=='__main__':unittest.main()
