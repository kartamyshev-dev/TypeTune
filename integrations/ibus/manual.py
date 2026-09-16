"""Experimental adapter for the stand's explicitly scoped plain-text profile.

Rust owns planning/authorization/readback. GI emits native edit requests only.
No file, subprocess, network or synchronous D-Bus calls in key callbacks.
"""
import ctypes
import json
import preferences
import correction_feedback
import time
from gesture import DoubleShift
from pathlib import Path
from gi.repository import IBus, GLib

LOCAL_LIB = Path(__file__).resolve().parent / 'libtypetune_ibus.so'
LIB = ctypes.CDLL(str(LOCAL_LIB if LOCAL_LIB.exists() else Path(__file__).resolve().parents[2] / 'target/debug/libtypetune_ibus.so'))
LIB.typetune_ibus_new.restype = ctypes.c_void_p
LIB.typetune_ibus_free.argtypes = [ctypes.c_void_p]
LIB.typetune_ibus_call.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_size_t, ctypes.c_void_p]
LIB.typetune_ibus_call.restype = ctypes.c_size_t


class Manual:
    def __init__(self, engine, stats, profile, validate=None, automatic=lambda: False, switch_mode=None, now=time.monotonic):
        self.engine, self.stats, self.profile = engine, stats, profile
        self.validate = validate
        self.automatic = automatic
        self.switch_mode = switch_mode
        self.now = now
        self.feedback_tracker = correction_feedback.Tracker(correction_feedback.FEEDBACK, lambda:self.now())
        self.feedback_edit = None
        self.gesture = DoubleShift()
        self.auto_expected = None
        self.plain_expected = None
        self.next_mode = None
        self.action_kind = "manual"
        self.smart_blocked = False
        self.handle = LIB.typetune_ibus_new()
        self.dictionary_generation = None
        self.epoch = self.revision = 1
        self.focused = False
        self.purpose = None
        self.caps = 0
        self.context = None
        self.pending = False
        self.timer = None
        self.shortcut = None
        self.clear = False
        self.modifiers = 0
        self.closed = False
        engine.connect('destroy', lambda *_: self.close())

    def call(self, op, **kwargs):
        if op == 'smart' and self.dictionary_generation != preferences.CURRENT['generation']:
            result = self.call('configure', words=preferences.CURRENT['words'], exclusions=preferences.CURRENT['exclusions'])
            if result['status'] != 'configured': return {'status':'rejected'}
            self.dictionary_generation = preferences.CURRENT['generation']
        raw = json.dumps(dict(op=op, **kwargs), ensure_ascii=False).encode()
        output = ctypes.create_string_buffer(32768)
        size = LIB.typetune_ibus_call(self.handle, raw, len(raw), output)
        return json.loads(output.raw[:size]) if size else {'status': 'indeterminate'}

    def result(self, response):
        status = response['status']
        if status in ('completed', 'rejected', 'indeterminate'):
            self.stats['manual_' + status] += 1
            if self.action_kind == 'auto':
                key = 'auto_' + status
                self.stats[key] = self.stats.get(key, 0) + 1
            self.pending = False
            if status == 'indeterminate':
                self.context = None
                self.clear = False
                self.epoch += 1
            if status == 'completed' and self.feedback_edit:
                self.feedback_tracker.completed(*self.feedback_edit)
            elif status != 'completed':self.feedback_tracker.reset()
            self.feedback_edit = None
            if status == 'completed' and self.next_mode and self.switch_mode:
                mode = self.next_mode
                self.next_mode = None
                self.switch_mode(mode)
            elif status != 'completed':
                self.next_mode = None
            if self.timer is not None:
                GLib.source_remove(self.timer)
                self.timer = None
        return status

    def cancel(self):
        self.feedback_tracker.reset()
        self.feedback_edit = None
        self.plain_expected = None
        self.gesture.reset()
        self.auto_expected = None
        if self.pending:
            self.result(self.call('cancel'))
        self.context = None
        self.clear = False
        self.epoch += 1

    def close(self):
        if not self.closed:
            self.cancel()
            LIB.typetune_ibus_free(self.handle)
            self.closed = True

    def focus(self, focused):
        self.cancel()
        self.focused = focused
        self.purpose = None

    def content_type(self, purpose):
        if self.purpose != int(purpose):
            self.cancel()
        self.purpose = int(purpose)

    def surrounding(self, text, cursor, anchor):
        # Context is bounded and normal-purpose only. Non-Chrome applications
        # additionally require fresh AT-SPI proof before both prepare and edit.
        if not self.profile() or self.purpose != int(IBus.InputPurpose.FREE_FORM):
            self.cancel()
            return
        value = text.get_text()
        if len(value.encode('utf-8')) > 16384:
            self.cancel()
            return
        if self.context is not None and self.context != (value, int(cursor), int(anchor)):
            self.gesture.reset()
            if not self.pending:
                self.feedback_tracker.reset()
                self.clear = False
        if self.plain_expected is not None:
            expected, expected_caret, epoch, deadline = self.plain_expected
            self.plain_expected = None
            if value == expected and cursor == anchor == expected_caret and epoch == self.epoch and self.now() <= deadline:
                self.clear = True
        if self.context != (value, int(cursor), int(anchor)):
            self.revision += 1
        self.context = (value, int(cursor), int(anchor))
        if self.pending:
            GLib.idle_add(self.observe)
        elif self.auto_expected is not None:
            expected, expected_caret, epoch, deadline = self.auto_expected
            self.auto_expected = None
            if (self.automatic() and self.now() <= deadline and epoch == self.epoch and
                    value == expected and cursor == anchor == expected_caret):
                GLib.idle_add(self.request_smart, True, epoch, self.revision)

    def snapshot(self):
        value, caret, anchor = self.context or ('', 0, 0)
        return dict(target=1, epoch=self.epoch, revision=self.revision, text=value,
                    caret=caret, anchor=anchor, focused=self.focused,
                    normal_field=True if self.purpose == int(IBus.InputPurpose.FREE_FORM) else None,
                    composing=False if self.clear else None,
                    modifiers_clear=self.modifiers == 0,
                    unicode_range=True if self.profile() and self.context is not None and self.caps & int(IBus.Capabilite.SURROUNDING_TEXT) else None)

    def key(self, keyval, state):
        release = bool(state & IBus.ModifierType.RELEASE_MASK)
        self.modifiers = int(state) & int(IBus.ModifierType.SHIFT_MASK | IBus.ModifierType.CONTROL_MASK | IBus.ModifierType.MOD1_MASK | IBus.ModifierType.MOD4_MASK | IBus.ModifierType.MOD5_MASK)
        if keyval in (IBus.KEY_Shift_L, IBus.KEY_Shift_R):
            # IBus release state still includes the modifier being released.
            if release:
                self.modifiers &= ~int(IBus.ModifierType.SHIFT_MASK)
            if self.modifiers & ~int(IBus.ModifierType.SHIFT_MASK):
                self.gesture.reset()
            elif self.gesture.edge(keyval, release, self.now()) and self.profile():
                GLib.idle_add(self.request_smart, False, self.epoch, self.revision)
            return False  # Both Down/Up continue normally; Shift typing stays intact.
        if not release:
            self.feedback_tracker.reset()
            self.gesture.reset()
            self.auto_expected = None
        if keyval in (IBus.KEY_F8, IBus.KEY_F9):
            if release and self.shortcut == keyval:
                self.shortcut = None
                if self.profile():
                    GLib.idle_add(self.request, keyval == IBus.KEY_F9, self.epoch)
                return True
            if not release and self.profile():
                if self.shortcut is None:
                    self.shortcut = keyval
                return True
            return False
        if not release:
            if self.pending:
                self.cancel()  # Ordinary input is still forwarded immediately.
            # Plain US fixture profile: no dead keys, compose or alternate IME.
            # This is not a general proof of composition state in other clients.
            previous_clear = self.clear
            character = IBus.keyval_to_unicode(keyval)
            printable = bool(character) and (32 <= keyval <= 126 or 'а' <= character.lower() <= 'я' or character.lower() == 'ё') and not self.modifiers & ~int(IBus.ModifierType.SHIFT_MASK)
            self.clear = False
            self.plain_expected = None
            if printable and self.context:
                value, caret, anchor = self.context
                if caret == anchor:
                    self.plain_expected = (value[:caret] + character + value[caret:], caret + 1, self.epoch, self.now() + .250)
            # Ctrl+Z/undo, paste and navigation cannot immediately re-trigger auto.
            if self.modifiers & int(IBus.ModifierType.CONTROL_MASK):
                self.smart_blocked = True
            if character and character != ' ' and printable:
                self.smart_blocked = False
            if (keyval == IBus.KEY_space and self.modifiers == 0 and previous_clear and
                    self.automatic() and not self.smart_blocked and self.profile() and self.context):
                value, caret, anchor = self.context
                if caret == anchor:
                    self.auto_expected = (value[:caret] + ' ' + value[caret:], caret + 1, self.epoch, self.now() + .250)
        return False

    def request(self, reverse, epoch):
        if self.validate is not None:
            self.validate(lambda: self._request(reverse, epoch))
            return False
        return self._request(reverse, epoch)

    def _request(self, reverse, epoch):
        if self.closed:
            return False
        if self.pending or epoch != self.epoch or not self.profile():
            self.stats['manual_rejected'] += 1
            return False
        self.action_kind = 'manual'
        self.next_mode = None
        response = self.call('prepare', state=self.snapshot(), reverse=reverse)
        if self.result(response) != 'ready':
            return False
        self.pending = True
        self.timer = GLib.timeout_add(500, self.timeout)
        GLib.idle_add(self.authorize)
        return False

    def request_smart(self, automatic, epoch, revision):
        def prepared():
            if self.closed or self.pending or self.epoch != epoch or self.revision != revision or not self.profile():
                self.stats["manual_rejected"] += 1
                return False
            if automatic and not self.automatic():
                return False
            self.action_kind = 'auto' if automatic else 'manual'
            response = self.call('smart', state=self.snapshot(), automatic=automatic)
            if self.result(response) != 'ready':
                return False
            self.next_mode = response['mode']
            self.pending = True
            self.timer = GLib.timeout_add(500, self.timeout)
            GLib.idle_add(self.authorize)
            return False
        if self.validate is not None:
            self.validate(prepared)
        else:
            prepared()
        return False

    def authorize(self):
        if self.validate is not None:
            self.validate(self._authorize)
            return False
        return self._authorize()

    def _authorize(self):
        if self.closed or not self.pending:
            return False
        if not self.profile() or (self.action_kind == 'auto' and not self.automatic()):
            self.cancel()
            return False
        response = self.call('authorize', state=self.snapshot())
        if self.result(response) == 'edit':
            value,caret,_ = self.context
            start = caret + response['offset']
            self.feedback_edit = (self.action_kind, value[start:start+response['length']], response['replacement'])
            try:
                # Both requests are asynchronous. There is no atomicity promise.
                self.engine.delete_surrounding_text(response['offset'], response['length'])
                self.engine.commit_text(IBus.Text.new_from_string(response['replacement']))
                self.stats['manual_edits'] += 1
            except Exception:
                self.cancel()  # No retry even if only deletion was delivered.
        return False

    def observe(self):
        if not self.closed and self.pending:
            self.result(self.call('observe', state=self.snapshot()))
        return False

    def timeout(self):
        self.timer = None
        if self.pending:
            self.result(self.call('cancel'))
        return False
