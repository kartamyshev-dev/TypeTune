#!/usr/bin/env python3
"""Rejected matrix workloads must fail before any activation or keyboard event."""
import json
import pathlib
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]


class MatrixProbeGuards(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        subprocess.run([str(ROOT / 'scripts/matrix_input_probe.sh'), '--build-only'], check=True)

    def test_reject_before_events(self):
        base = dict(bundle='com.google.Chrome', window='Google - Google Chrome',
                    description='Найти', text='ghbdtn ', expected='привет ',
                    source='com.apple.keylayout.ABC', expectedSource='com.apple.keylayout.RussianWin',
                    gesture='none')
        for changes, error in [({'bundle': 'com.apple.finder'}, 'bundle_not_in_matrix'),
                               ({'text': '\n'}, 'bounded_ascii_keys_required'),
                               ({'gesture': 'Return'}, 'unsupported_gesture')]:
            with self.subTest(error=error), tempfile.NamedTemporaryFile(mode='w', suffix='.json') as case:
                json.dump(base | changes, case)
                case.flush()
                run = subprocess.run([str(ROOT / '.build/matrix-input-probe'), case.name], capture_output=True, text=True)
                result = json.loads(run.stdout)
                self.assertEqual(run.returncode, 1)
                self.assertEqual(result['events'], 0)
                self.assertEqual(result['error'], error)


if __name__ == '__main__':
    unittest.main()
