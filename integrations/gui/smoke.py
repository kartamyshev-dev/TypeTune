#!/usr/bin/python3
"""Controlled GUI actions: no real runtime mutations. Requires a GTK display."""
import sys
import time
import threading
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'app'))
from gui import Gtk, Gio, GLib, Window
from gui_model import describe

calls = []
current = dict(installed=True, bridge=True, compatibility=dict(enabled=True, automatic=True, available=True, mode='ru'))
current['settings']=dict(mode='compatibility',automatic=True,autostart_effective=False,
                         manual_switching=True,switch_only_last_word=True,dont_switch_words=False,
                         dont_correct_after_layout_change=True,play_switching_sound=False,
                         display_layout_flag=True,active_keyboards=['us','ru'])
fail_next = False
block_status = None
TOGGLE_KEYS = {
    'manual-toggle':'manual_switching',
    'switch-last-toggle':'switch_only_last_word',
    'dont-switch-toggle':'dont_switch_words',
    'anti-loop-toggle':'dont_correct_after_layout_change',
    'sound-toggle':'play_switching_sound',
    'flag-toggle':'display_layout_flag',
}

def requester(command, payload=None):
    global fail_next
    calls.append(command)
    if command == 'status' and block_status is not None:
        assert block_status.wait(3)
    r = current['compatibility']
    if command in ('autostart-on','autostart-off'): current['settings']['autostart_effective'] = command=='autostart-on'
    if command == 'stop': current['compatibility'] = 'not-running'
    if command == 'start': current['compatibility'] = dict(enabled=True, automatic=True, available=True, mode='ru')
    if command == 'auto-off': r['automatic'] = False
    if command == 'pause': r['enabled'] = False
    if command == 'resume': r['enabled'] = True
    if command in TOGGLE_KEYS:
        key = TOGGLE_KEYS[command]
        current['settings'][key] = not current['settings'].get(key, True)
        if key == 'switch_only_last_word' and current['settings'][key]:
            current['settings']['dont_switch_words'] = False
        if key == 'dont_switch_words' and current['settings'][key]:
            current['settings']['switch_only_last_word'] = False
    if command == 'threshold-set':
        raw = (payload or '').strip()
        if not raw:
            raise RuntimeError('Порог не задан')
        try: wanted = int(raw)
        except ValueError: wanted = None
        if wanted is None or not 1 <= wanted <= 10:
            raise RuntimeError('Порог вне диапазона')
        current['settings']['learn_threshold'] = wanted
    if fail_next:
        fail_next = False
        raise RuntimeError('Controlled failure')
    return describe(current), None

app = Gtk.Application(application_id='dev.kartamyshev.TypeTune.GuiStand', flags=Gio.ApplicationFlags.NON_UNIQUE)
app.register(None)
w = Window(app, requester)
w.present()
ctx = GLib.MainContext.default()

def settle():
    deadline = time.monotonic() + 3
    while w.busy and time.monotonic() < deadline:
        ctx.iteration(True)
    assert not w.busy
    while ctx.pending(): ctx.iteration(False)

settle()
assert w.title.get_label() == 'Работает'
changes = []
w.pause.connect('notify::sensitive', lambda *_: changes.append(w.pause.get_sensitive()))
block_status = threading.Event()
w.poll()
try:
    assert w.pause.get_sensitive(), 'Background polling must not disable controls'
    assert not changes, 'Background polling caused a visible sensitivity change'
    w.pause.emit('clicked')  # Must be queued rather than lost during the read.
finally:
    block_status.set()
settle()
block_status = None
assert w.title.get_label() == 'На паузе'
w.pause.emit('clicked'); settle()
assert w.title.get_label() == 'Работает'
changes.clear()
w.poll(); settle()
assert not changes, 'Unchanged status must not blink controls'
w.pause.emit('clicked'); settle()
assert w.title.get_label() == 'На паузе'
w.pause.emit('clicked'); settle()
assert w.title.get_label() == 'Работает'
w.auto.set_active(False); settle()
assert not w.auto.get_active() and calls.count('auto-off') == 1
fail_next = True
w.refresh.emit('clicked'); settle()
assert w.title.get_label() == 'Нет связи с TypeTune'
assert not w.auto.get_sensitive() and w.stop.get_sensitive()
w.refresh.emit('clicked'); settle()
assert w.title.get_label() == 'Работает'
w.stop.emit('clicked'); settle()
assert w.title.get_label() == 'Остановлен' and w.start.get_sensitive()
w.start.emit('clicked'); settle()
assert w.title.get_label() == 'Работает' and calls.count('start') == 1
w.stop.emit('clicked'); settle()
current['bridge'] = False
w.refresh.emit('clicked'); settle()
assert w.title.get_label() == 'Нет связи с GNOME' and not w.start.get_sensitive()
current['bridge'] = True
w.refresh.emit('clicked'); settle()
w.start.emit('clicked'); settle()
w.login.set_active(True); settle()
assert w.login.get_active() and calls.count('autostart-on') == 1
w.login.set_active(False); settle()
assert not w.login.get_active() and calls.count('autostart-off') == 1
assert w.threshold.get_value_as_int() == current['settings'].get('learn_threshold', 3)
w.threshold.set_value(5); settle()
assert w.threshold.get_value_as_int() == 5 and calls.count('threshold-set') == 1
assert current['settings']['learn_threshold'] == 5
w.threshold.set_value(3); settle()
assert w.threshold.get_value_as_int() == 3 and calls.count('threshold-set') == 2
assert w.manual.get_active() and w.switch_last.get_active() and not w.dont_words.get_active()
assert w.anti_loop.get_active() and not w.sound.get_active() and w.show_flag.get_active()
assert 'us, ru' in w.boards.get_label()
w.dont_words.set_active(True); settle()
assert w.dont_words.get_active() and not w.switch_last.get_active()
assert calls.count('dont-switch-toggle') == 1
w.sound.set_active(True); settle()
assert w.sound.get_active() and calls.count('sound-toggle') == 1
w.show_flag.set_active(False); settle()
assert not w.show_flag.get_active() and calls.count('flag-toggle') == 1
for bad_payload, expected in (
    (None, 'Порог не задан'),
    ('', 'Порог не задан'),
    ('   ', 'Порог не задан'),
    ('0', 'Порог вне диапазона'),
    ('11', 'Порог вне диапазона'),
    ('abc', 'Порог вне диапазона'),
):
    try:
        requester('threshold-set', bad_payload)
    except RuntimeError as exc:
        assert str(exc) == expected, (bad_payload, exc)
    else:
        raise AssertionError(f'threshold-set must reject {bad_payload!r}')
w.stop.emit('clicked'); settle()
w.start.emit('clicked'); settle()
assert w.get_width() > 0 and w.get_height() > 0
print('GUI-43 controlled GTK: status/pause/resume/auto-off/stop/start/missing-bridge/failure/recovery/threshold/policy-toggles PASS')
# Capture only this fixture's window, never the user's desktop.
if len(sys.argv) > 1:
    from gi.repository import Gsk, Graphene
    ready = []
    GLib.timeout_add(250, lambda: ready.append(True) and False)
    while not ready: ctx.iteration(True)
    paintable = Gtk.WidgetPaintable.new(w)
    snapshot = Gtk.Snapshot.new()
    paintable.snapshot(snapshot, w.get_width(), w.get_height())
    node = snapshot.to_node()
    renderer = w.get_native().get_renderer()
    texture = renderer.render_texture(node, Graphene.Rect().init(0, 0, w.get_width(), w.get_height()))
    assert texture.save_to_png(sys.argv[1])
class FakeTray:
    registered = True
    def update(self, *_): pass
app.tray = FakeTray()
w.close()
assert not w.closed and not w.get_visible(), 'Close must hide while tray is available'
w.present()
assert w.get_visible(), 'Tray open must reuse the hidden window'
app.tray = None
w.close()
