#!/usr/bin/env python3
"""Deterministic adapter tests, synthetic text only; no IBus bus or desktop."""
import unittest
import gi
gi.require_version('IBus', '1.0')
from gi.repository import IBus, GLib
from manual import Manual


class Editor:
    def __init__(self):
        self.text = 'ghbdtn'
        self.caret = 6
        self.calls = []

    def connect(self, *_):
        pass

    def delete_surrounding_text(self, offset, count):
        start = self.caret + offset
        self.text = self.text[:start] + self.text[start + count:]
        self.caret = start
        self.calls.append('delete')

    def commit_text(self, text):
        value = text.get_text()
        self.text = self.text[:self.caret] + value + self.text[self.caret:]
        self.caret += len(value)
        self.calls.append('commit')


class Tests(unittest.TestCase):
    def setUp(self):
        self.editor = Editor()
        self.stats = dict(manual_completed=0, manual_rejected=0, manual_indeterminate=0, manual_edits=0)
        self.enabled = True
        self.manual = Manual(self.editor, self.stats, lambda: self.enabled)
        self.manual.focus(True)
        self.manual.caps = int(IBus.Capabilite.SURROUNDING_TEXT)
        self.manual.content_type(IBus.InputPurpose.FREE_FORM)
        self.editor.text = 'ghbdt'
        self.editor.caret = 5
        self.surrounding()
        self.manual.key(ord('n'), 0)
        self.editor.text = 'ghbdtn'
        self.editor.caret = 6
        self.surrounding()

    def surrounding(self, anchor=None):
        self.manual.surrounding(IBus.Text.new_from_string(self.editor.text), self.editor.caret,
                                self.editor.caret if anchor is None else anchor)

    def tearDown(self):
        self.manual.close()
        context = GLib.MainContext.default()
        while context.pending():
            context.iteration(False)

    def start(self):
        self.manual.request(False, self.manual.epoch)

    def test_exact_unicode_edit_and_readback(self):
        self.start()
        self.manual.authorize()
        self.assertEqual((self.editor.text, self.editor.caret), ('привет', 6))
        self.assertEqual(self.stats['manual_completed'], 0)
        self.surrounding()
        self.manual.observe()
        self.assertEqual(self.stats['manual_completed'], 1)
        self.assertEqual(self.editor.calls, ['delete', 'commit'])

    def test_focus_loss_between_prepare_and_edit_preserves_source(self):
        self.start()
        self.manual.focus(False)
        self.manual.authorize()
        self.assertEqual(self.editor.text, 'ghbdtn')
        self.assertEqual(self.editor.calls, [])
        self.assertEqual(self.stats['manual_rejected'], 1)

    def test_new_input_cancels_prepared_edit_and_is_forwarded(self):
        self.start()
        self.assertFalse(self.manual.key(ord('a'), 0))
        self.manual.authorize()
        self.assertEqual(self.editor.calls, [])

    def test_selection_unknown_purpose_and_profile_disable_refuse(self):
        self.surrounding(anchor=1)
        self.start()
        self.assertEqual(self.stats['manual_rejected'], 1)
        self.manual.content_type(IBus.InputPurpose.PASSWORD)
        self.surrounding()
        self.assertIsNone(self.manual.context)
        self.start()
        self.assertEqual(self.stats['manual_rejected'], 2)
        self.manual.focus(True)  # Purpose is now Unknown, not normal.
        self.surrounding()
        self.start()
        self.assertEqual(self.stats['manual_rejected'], 3)
        self.assertEqual(self.editor.calls, [])

    def test_revoked_profile_between_prepare_and_edit(self):
        self.start()
        self.enabled = False
        self.manual.authorize()
        self.assertEqual(self.editor.calls, [])
        self.assertEqual(self.stats['manual_rejected'], 1)

    def test_partial_failure_never_retries(self):
        def failed_commit(_):
            raise RuntimeError('synthetic failure')
        self.editor.commit_text = failed_commit
        self.start()
        self.manual.authorize()
        self.assertEqual(self.editor.text, '')
        self.assertEqual(self.stats['manual_indeterminate'], 1)
        self.assertIsNone(self.manual.context)
        self.assertFalse(self.manual.clear)
        self.manual.authorize()
        self.assertEqual(self.editor.calls, ['delete'])

    def test_repeat_shortcut_edits_once_on_release(self):
        for _ in range(3):
            self.assertTrue(self.manual.key(IBus.KEY_F8, 0))
        self.assertEqual(self.editor.calls, [])
        self.assertTrue(self.manual.key(IBus.KEY_F8, int(IBus.ModifierType.RELEASE_MASK)))
        context = GLib.MainContext.default()
        while context.pending():
            context.iteration(False)
        self.surrounding()
        self.manual.observe()
        self.assertEqual(self.editor.calls, ['delete', 'commit'])
        self.assertEqual(self.stats['manual_completed'], 1)

    def test_async_validation_focus_change_before_prepare(self):
        callbacks = []
        self.manual.validate = callbacks.append
        self.start()
        self.assertEqual(self.editor.calls, [])
        self.manual.focus(False)
        callbacks.pop(0)()
        self.assertEqual(self.stats['manual_rejected'], 1)
        self.assertEqual(self.editor.calls, [])

    def test_async_validation_revocation_before_authorize(self):
        callbacks = []
        self.manual.validate = callbacks.append
        self.start()
        callbacks.pop(0)()
        self.assertTrue(self.manual.pending)
        self.manual.authorize()
        self.enabled = False
        callbacks.pop(0)()
        self.assertEqual(self.editor.text, 'ghbdtn')
        self.assertEqual(self.editor.calls, [])

    def test_paused_profile_forwards_shortcut_edges(self):
        self.enabled = False
        self.assertFalse(self.manual.key(IBus.KEY_F8, 0))
        self.assertFalse(self.manual.key(IBus.KEY_F8, int(IBus.ModifierType.RELEASE_MASK)))
        self.assertEqual(self.editor.calls, [])

    def drain(self):
        context=GLib.MainContext.default()
        while context.pending():context.iteration(False)

    def test_double_shift_corrects_and_requests_mode_only_after_readback(self):
        clock=[0.]
        self.manual.now=lambda:clock[0]
        modes=[]
        self.manual.switch_mode=modes.append
        for release,t in [(False,0),(True,.04),(False,.10),(True,.14)]:
            clock[0]=t
            state=int(IBus.ModifierType.RELEASE_MASK | IBus.ModifierType.SHIFT_MASK) if release else 0
            self.assertFalse(self.manual.key(IBus.KEY_Shift_L,state))
        self.drain()
        self.assertEqual(self.editor.text,'привет')
        self.assertEqual(modes,[])
        self.surrounding();self.manual.observe()
        self.assertEqual(modes,['ru'])

    def test_auto_waits_for_exact_committed_space(self):
        self.manual.automatic=lambda:True
        self.assertFalse(self.manual.key(IBus.KEY_space,0))
        self.assertEqual(self.editor.calls,[])
        self.editor.text+=' ';self.editor.caret+=1
        self.surrounding();self.drain()
        self.assertEqual((self.editor.text,self.editor.caret),('привет ',7))
        self.surrounding();self.manual.observe()
        self.assertEqual(self.stats['auto_completed'],1)

    def test_unrelated_edit_or_next_key_cancels_automatic_candidate(self):
        self.manual.automatic=lambda:True
        self.manual.key(IBus.KEY_space,0)
        self.manual.key(ord('x'),0)
        self.editor.text+=' x';self.editor.caret+=2
        self.surrounding();self.drain()
        self.assertEqual(self.editor.calls,[])

    def test_caret_change_between_shift_taps_cancels_gesture(self):
        clock=[0.];self.manual.now=lambda:clock[0]
        self.manual.key(IBus.KEY_Shift_L,0)
        clock[0]=.04;self.manual.key(IBus.KEY_Shift_L,int(IBus.ModifierType.RELEASE_MASK))
        self.editor.caret=3;self.surrounding()
        clock[0]=.1;self.manual.key(IBus.KEY_Shift_L,0)
        clock[0]=.14;self.manual.key(IBus.KEY_Shift_L,int(IBus.ModifierType.RELEASE_MASK))
        self.drain();self.assertEqual(self.editor.calls,[])


if __name__ == '__main__':
    unittest.main()
