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
                               ({'bundle': 'com.apple.finder', 'description': None}, 'bundle_not_in_matrix'),
                               ({'bundle': 'com.apple.finder', 'window': None}, 'bundle_not_in_matrix'),
                               ({'text': '\n'}, 'bounded_ascii_keys_required'),
                               ({'text': '', 'gesture': 'none'}, 'bounded_ascii_keys_required'),
                               ({'gesture': 'undo'}, 'undo_precondition_required'),
                               ({'gesture': 'focus'}, 'focus_must_not_type'),
                               ({'gesture': 'Return'}, 'unsupported_gesture'),
                               ({'text': '/', 'gesture': 'Return'}, 'unsupported_gesture'),
                               ({'text': '.', 'gesture': 'Return'}, 'unsupported_gesture'),
                               ({'text': '\t'}, 'bounded_ascii_keys_required'),
                               ({'gesture': 'inlineSpace'}, 'inline_completion_precondition_required'),
                               ({'gesture': 'inlineSpace', 'text': '127', 'expected': '127 ',
                                 'expectedSource': base['source'], 'completionTexts': ['127.0.0.1']},
                                'inline_completion_precondition_required'),
                               ({'gesture': 'inlineSpace', 'text': '127', 'expected': '127 ',
                                 'window': 'LayoutPilot isolated input LP-CODEX-001 - Google Chrome',
                                 'description': 'Адресная строка и строка поиска',
                                 'expectedSource': base['source'], 'completionTexts': ['128.0.0.1']},
                                'inline_completion_precondition_required')]:
            with self.subTest(error=error), tempfile.NamedTemporaryFile(mode='w', suffix='.json') as case:
                json.dump(base | changes, case)
                case.flush()
                run = subprocess.run([str(ROOT / '.build/matrix-input-probe'), case.name], capture_output=True, text=True)
                result = json.loads(run.stdout)
                self.assertEqual(run.returncode, 1)
                self.assertEqual(result['events'], 0)
                self.assertEqual(result['error'], error)

    def test_selected_suffix_preserves_every_typed_character(self):
        run = subprocess.run([str(ROOT / '.build/matrix-input-probe'), '--validate-completion-policy'],
                             capture_output=True, text=True, check=True)
        result = json.loads(run.stdout)
        self.assertTrue(result['passed'])
        self.assertEqual(result['completionPolicyCases'], 8)
        self.assertEqual(result['events'], 0)

    def test_focus_retry_requires_pinned_identity(self):
        run = subprocess.run([str(ROOT / '.build/matrix-input-probe'), '--validate-focus-policy'],
                             capture_output=True, text=True, check=True)
        result = json.loads(run.stdout)
        self.assertTrue(result['passed'])
        self.assertEqual(result['focusPolicyCases'], 9)
        self.assertEqual(result['events'], 0)


if __name__ == '__main__':
    unittest.main()
