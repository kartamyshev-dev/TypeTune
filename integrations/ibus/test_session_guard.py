#!/usr/bin/python3
import copy
import unittest
from session_guard import evaluate


class Tests(unittest.TestCase):
    def context(self):
        return dict(app_id='google-chrome.desktop', pid=123, snapshot=dict(protocol=1, instance='instance', generation=7,
            source_type='ibus', source_id='typetune-test', window=3, window_backend='wayland',
            locked=False, shield_active=False, overview=False, external_source=False, user_session=True))

    def test_exact_supported_profile(self):
        self.assertEqual(evaluate(self.context()), (('instance', 7, 3), 'chrome-wayland-limited'))

    def test_restricted_and_unknown_contexts_fail_closed(self):
        for key in ('locked', 'shield_active', 'overview', 'external_source', 'user_session'):
            for bad in (None, 1, 'false', True if key != 'user_session' else False):
                value = self.context()
                value['snapshot'][key] = bad
                self.assertIsNone(evaluate(value)[0], (key, bad))

    def test_unknown_other_app_xwayland_and_other_source(self):
        for key, bad in [('window', 0), ('window', True), ('window_backend', 'x11'),
                         ('source_type', 'xkb'), ('source_id', 'typetune-probe'), ('instance', ''), ('generation', True)]:
            value = self.context()
            value['snapshot'][key] = bad
            self.assertIsNone(evaluate(value)[0], key)
        for app in ('window:5', '', 'unknown-client'):
            value = self.context()
            value['app_id'] = app
            self.assertIsNone(evaluate(value)[0], app)

    def test_new_window_generation_and_shell_instance_invalidate_token(self):
        original = self.context()
        for key in ('window', 'generation', 'instance'):
            value = copy.deepcopy(original)
            value['snapshot'][key] = 'other' if key == 'instance' else 22
            self.assertNotEqual(evaluate(value)[0], evaluate(original)[0])

    def test_editor_requires_separate_selection_proof_at_execution(self):
        value = self.context()
        value['app_id'] = 'org.gnome.TextEditor.desktop'
        self.assertEqual(evaluate(value)[1], 'atspi-limited')

    def test_malformed_messages_never_authorize(self):
        for value in (None, [], {}, {'snapshot': None, 'app_id': 'google-chrome.desktop'},
                      {'snapshot': {}, 'app_id': 'google-chrome.desktop'}):
            self.assertIsNone(evaluate(value)[0])


if __name__ == '__main__':
    unittest.main()
