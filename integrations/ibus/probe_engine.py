#!/usr/bin/env python3
"""Experimental input method, restricted to the private disposable stand."""
import json
import os
from pathlib import Path
import gi

gi.require_version('IBus', '1.0')
from gi.repository import IBus, GLib
from manual import Manual

STATS = {'instances': 0, 'focus_in': 0, 'focus_out': 0, 'reset': 0, 'down': 0, 'up': 0,
         'surrounding': 0, 'fixture_seen': False, 'selection_seen': False,
         'capabilities': 0, 'purpose': None, 'sensitive': 0, 'content_type_events': 0, 'last_purpose': None, 'navigation': 0, 'selection_events': 0,
         'last_cursor': None, 'last_anchor': None,
         'manual_completed': 0, 'manual_rejected': 0, 'manual_indeterminate': 0, 'manual_edits': 0}
MANUAL_PROFILE = False
PROFILE = lambda: MANUAL_PROFILE
VALIDATE = None
VALIDATE_STATE = None
AUTOMATIC = lambda: False
SWITCH_MODE = None
OBSERVE_FIXTURE = True
ENGINES = []


class ProbeEngine(IBus.Engine):
    __gtype_name__ = 'TypeTuneProbeEngine'

    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        self._purpose = None
        STATS['instances'] += 1
        self.manual = Manual(self, STATS, PROFILE, VALIDATE, AUTOMATIC, SWITCH_MODE)
        if VALIDATE_STATE is not None:
            self.manual.validate = lambda done: VALIDATE_STATE(self.manual.snapshot(), done)
        ENGINES.append(self)
        self.connect('destroy', lambda *_: ENGINES.remove(self) if self in ENGINES else None)

    def do_enable(self):
        self.get_surrounding_text()

    def do_disable(self):
        self.manual.focus(False)

    def do_focus_in(self):
        STATS['focus_in'] += 1
        self.manual.focus(True)
        self._purpose = None
        STATS['purpose'] = None
        self.get_surrounding_text()

    def do_focus_out(self):
        STATS['focus_out'] += 1
        self.manual.focus(False)
        self._purpose = None
        STATS['purpose'] = None

    def do_reset(self):
        STATS['reset'] += 1
        self.manual.cancel()

    def do_set_capabilities(self, caps):
        STATS['capabilities'] = int(caps)
        if self.manual.caps != int(caps):
            self.manual.cancel()
        self.manual.caps = int(caps)

    def do_set_content_type(self, purpose, hints):
        self._purpose = int(purpose)
        self.manual.content_type(purpose)
        STATS['content_type_events'] += 1
        STATS['last_purpose'] = int(purpose)
        STATS['purpose'] = int(purpose)
        if purpose in (IBus.InputPurpose.PASSWORD, IBus.InputPurpose.PIN):
            STATS['sensitive'] += 1

    def do_set_surrounding_text(self, text, cursor, anchor):
        self.manual.surrounding(text, cursor, anchor)
        # Test-only aggregate oracle; never serialize the text or key values.
        STATS['surrounding'] += 1
        STATS['selection_seen'] |= cursor != anchor
        STATS['selection_events'] += int(cursor != anchor)
        STATS['last_cursor'] = int(cursor)
        STATS['last_anchor'] = int(anchor)
        if OBSERVE_FIXTURE and self._purpose == int(IBus.InputPurpose.FREE_FORM):
            value = text.get_text()
            if len(value) <= 4096:
                STATS['fixture_seen'] |= 'ghbdtn' in value

    def do_process_key_event(self, keyval, keycode, state):
        if not state & IBus.ModifierType.RELEASE_MASK and keyval in (IBus.KEY_Left, IBus.KEY_Right, IBus.KEY_Up, IBus.KEY_Down, IBus.KEY_Home, IBus.KEY_End):
            STATS['navigation'] += 1
        STATS['up' if state & IBus.ModifierType.RELEASE_MASK else 'down'] += 1
        return self.manual.key(keyval, state)


def publish():
    global MANUAL_PROFILE
    MANUAL_PROFILE = (BASE / 'manual-browser-profile').exists()
    path = BASE / 'ibus-stats.json'
    temp = path.with_suffix('.tmp')
    temp.write_text(json.dumps(STATS))
    temp.replace(path)
    return GLib.SOURCE_CONTINUE


if __name__ == '__main__':
    BASE = Path(os.environ['TYPETUNE_NESTED_STAND']).resolve()
    assert Path(os.environ['XDG_RUNTIME_DIR']).resolve() == BASE / 'runtime'
    assert os.environ['IBUS_ADDRESS'] == 'unix:path=' + str(BASE / 'runtime/ibus')
    IBus.init()
    bus = IBus.Bus.new()
    assert bus.is_connected()
    factory = IBus.Factory.new(bus.get_connection())
    factory.add_engine('typetune-probe', ProbeEngine)
    bus.request_name('org.freedesktop.IBus.TypeTuneProbe', 0)
    GLib.timeout_add(50, publish)
    loop = GLib.MainLoop()
    bus.connect('disconnected', lambda *_: loop.quit())
    loop.run()
