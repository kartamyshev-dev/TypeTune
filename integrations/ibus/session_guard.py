"""Asynchronous, fail-closed GNOME application/source guard; no text data."""
import json
import time
from concurrent.futures import ThreadPoolExecutor
from editor_guard import check_editor
from gi.repository import Gio, GLib

PATH = '/org/typetune/Session1'
IFACE = 'org.typetune.Session1'


def evaluate(value):
    if not isinstance(value, dict) or set(value) != {'snapshot', 'app_id', 'pid'}:
        return None, 'invalid-context'
    s = value['snapshot']
    if not isinstance(s, dict) or s.get('protocol') != 1:
        return None, 'invalid-context'
    if any(s.get(k) is not False for k in ('locked', 'shield_active', 'overview', 'external_source')) or s.get('user_session') is not True:
        return None, 'session-restricted'
    if s.get('window_backend') != 'wayland' or type(s.get('window')) is not int or s['window'] <= 0:
        return None, 'unknown-window'
    if not isinstance(value['app_id'], str) or not value['app_id'].endswith('.desktop'):
        return None, 'unsupported-application'
    if s.get('source_type') != 'ibus' or s.get('source_id') not in ('typetune-test', 'typetune-test-ru'):
        return None, 'inactive-source'
    if not isinstance(s.get('instance'), str) or not s['instance'] or type(s.get('generation')) is not int:
        return None, 'invalid-context'
    if type(value['pid']) is not int or value['pid'] <= 0:
        return None, 'unknown-process'
    return (s['instance'], s['generation'], s['window']), ('chrome-wayland-limited' if value['app_id'] == 'google-chrome.desktop' else 'atspi-limited')


class SessionGuard:
    def __init__(self, changed):
        self.connection = Gio.bus_get_sync(Gio.BusType.SESSION, None)
        self.changed = changed
        self.token = None
        self.owner = None
        self.reason = 'bridge-unavailable'
        self.received = 0.
        self.enabled = True
        self.mode_result = 'none'
        self.source_id = None
        self.serial = 0
        self.pending = False
        self.application = None
        self.pid = None
        self.worker = ThreadPoolExecutor(max_workers=1)
        self.editor_busy = False
        self.connection.signal_subscribe(None, IFACE, 'Changed', PATH, None,
                                         Gio.DBusSignalFlags.NONE, self.invalidate)
        self.watch = Gio.bus_watch_name_on_connection(self.connection, 'org.gnome.Shell',
                    Gio.BusNameWatcherFlags.NONE, self.appeared, self.vanished)
        GLib.timeout_add(200, self.poll)

    def set_enabled(self, enabled):
        self.enabled = enabled
        self.invalidate()
        self.refresh()

    def appeared(self, connection, name, owner):
        self.owner = owner
        self.invalidate()
        self.refresh()

    def vanished(self, *_):
        self.owner = None
        self.invalidate()

    def invalidate(self, *_):
        self.serial += 1
        self.token = None
        self.received = 0.
        self.reason = 'refresh-required' if self.owner else 'bridge-unavailable'
        self.changed()

    def allows(self):
        return self.enabled and self.token is not None and time.monotonic() - self.received < .6

    def refresh(self, done=None):
        owner, serial = self.owner, self.serial
        if not owner or not self.enabled:
            if done:
                done()
            return
        def complete(connection, result):
            try:
                raw = connection.call_finish(result).unpack()[0]
                token, reason = evaluate(json.loads(raw)) if len(raw) <= 8192 else (None, 'invalid-context')
            except (GLib.Error, ValueError, TypeError):
                token, reason = None, 'bridge-unavailable'
            if owner == self.owner and serial == self.serial:
                if token != self.token:
                    self.token = token
                    self.changed()
                value = json.loads(raw) if token else {}
                self.source_id = value.get('snapshot', {}).get('source_id')
                self.application = value.get('app_id')
                self.pid = value.get('pid')
                self.reason = reason
                self.received = time.monotonic()
            if done:
                done()
        self.connection.call(owner, PATH, IFACE, 'GetTextContext', None,
            GLib.VariantType.new('(s)'), Gio.DBusCallFlags.NONE, 300, None, complete)

    def poll(self):
        if not self.pending:
            self.pending = True
            self.refresh(lambda: setattr(self, 'pending', False))
        return True

    def switch_mode(self, mode):
        if not self.allows() or not self.owner:
            self.mode_result = 'rejected'
            return
        instance, generation, window = self.token
        owner = self.owner
        self.mode_result = 'pending'
        request = json.dumps(dict(instance=instance, generation=generation, window=window, target=mode))
        def finished(connection, result):
            try:
                accepted = connection.call_finish(result).unpack()[0]
            except GLib.Error:
                accepted = False
            if not accepted or self.owner != owner:
                self.mode_result = 'unconfirmed'
                return
            target = 'typetune-test-ru' if mode == 'ru' else 'typetune-test'
            # Observe asynchronously; no retry of source activation.
            deadline = time.monotonic() + .5
            def poll():
                if self.source_id == target:
                    self.mode_result = 'completed'
                    return False
                if time.monotonic() >= deadline:
                    self.mode_result = 'unconfirmed'
                    return False
                self.refresh()
                return True
            GLib.timeout_add(25, poll)
        self.connection.call(owner, PATH, IFACE, 'SetTypeTuneMode', GLib.Variant('(s)', (request,)),
            GLib.VariantType.new('(b)'), Gio.DBusCallFlags.NONE, 300, None, finished)

    def validate_state(self, state, done):
        def refreshed():
            if not self.allows() or self.application == 'google-chrome.desktop':
                done()
                return
            if self.editor_busy:
                self.invalidate()
                done()
                return
            token = self.token
            self.editor_busy = True
            future = self.worker.submit(check_editor, self.pid, state)
            def observed():
                if not future.done():
                    return True
                self.editor_busy = False
                accepted = future.result()
                def finish():
                    if not accepted or self.token != token:
                        self.invalidate()
                        self.reason = 'editor-context-unconfirmed'
                    done()
                self.refresh(finish)
                return False
            GLib.timeout_add(10, observed)
        self.refresh(refreshed)
