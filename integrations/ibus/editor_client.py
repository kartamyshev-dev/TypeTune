#!/usr/bin/env python3
"""Real editor readback oracle for the private IBus stand; synthetic text only."""
import os
from pathlib import Path
import subprocess
import time
import gi

gi.require_version('Atspi', '2.0')
from gi.repository import Atspi

base = Path(os.environ['TYPETUNE_NESTED_STAND']).resolve()
assert Path(os.environ['XDG_RUNTIME_DIR']).resolve() == base / 'runtime'
assert os.environ['WAYLAND_DISPLAY'] == 'typetune-test'
Atspi.set_timeout(1000, 1000)
source = 'prefix '
fixture = base / 'ibus-editor.txt'
fixture.write_text(source)
app = subprocess.Popen(['gnome-text-editor', '--new-window', str(fixture)],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
try:
    deadline = time.monotonic() + 10
    field = None
    while time.monotonic() < deadline and field is None:
        desktop = Atspi.get_desktop(0)
        for i in range(desktop.get_child_count()):
            root = desktop.get_child_at_index(i)
            if root.get_process_id() != app.pid:
                continue
            queue = [root]
            for _ in range(512):
                if not queue:
                    break
                node = queue.pop()
                if node.is_text() and node.get_state_set().contains(Atspi.StateType.EDITABLE):
                    if (node.get_character_count() == len(source) and
                            Atspi.Text.get_text(node, 0, len(source)) == source):
                        field = node
                        break
                queue.extend(node.get_child_at_index(j) for j in range(min(node.get_child_count(), 128)))
        time.sleep(.05)
    assert field is not None
    assert field.set_caret_offset(len(source))
    (base / 'ibus-editor-ready').write_text('ready')
    expected = source + 'ghbdtn'
    deadline = time.monotonic() + 10
    while time.monotonic() < deadline:
        field.clear_cache()
        if field.get_character_count() == len(expected) and Atspi.Text.get_text(field, 0, len(expected)) == expected:
            break
        time.sleep(.05)
    assert Atspi.Text.get_text(field, 0, len(expected)) == expected
    assert field.get_caret_offset() == len(expected)
    assert field.get_n_selections() == 0
    print('PASS IBUS-02: unmodified GNOME Text Editor receives all keys; exact text/caret via independent AT-SPI readback', flush=True)
    if 'TYPETUNE_RUNTIME_STAND' in os.environ:
        (base / 'ibus-editor-correct').write_text('ready')
        expected = source + 'привет'
        deadline = time.monotonic() + 10
        while time.monotonic() < deadline:
            field.clear_cache()
            if Atspi.Text.get_text(field, 0, field.get_character_count()) == expected:
                break
            time.sleep(.05)
        assert Atspi.Text.get_text(field, 0, field.get_character_count()) == expected
        assert field.get_caret_offset() == len(expected) and field.get_n_selections() == 0
        print('PASS EDITOR-MANUAL: real GNOME Text Editor corrected through IBus, independent AT-SPI text/caret readback', flush=True)
    assert field.add_selection(7, 13)
    selection = Atspi.Text.get_selection(field, 0)
    assert (selection.start_offset, selection.end_offset) == (7, 13)
    (base / 'ibus-editor-selected').write_text('ready')
    deadline = time.monotonic() + 5
    while not (base / 'ibus-editor-finish').exists() and time.monotonic() < deadline:
        time.sleep(.05)
    assert (base / 'ibus-editor-finish').exists()
    assert Atspi.Text.get_text(field, 0, field.get_character_count()) == expected
    assert fixture.read_text() == source
finally:
    app.terminate()
    try:
        app.wait(timeout=3)
    except subprocess.TimeoutExpired:
        app.kill()
        app.wait()
