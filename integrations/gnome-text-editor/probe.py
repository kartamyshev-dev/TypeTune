#!/usr/bin/env python3
"""Synthetic capability acceptance, only inside TypeTune's disposable session."""
import os
from pathlib import Path
import subprocess
import time
import gi

gi.require_version('Atspi', '2.0')
from gi.repository import Atspi


def main():
    base = Path(os.environ['TYPETUNE_NESTED_STAND']).resolve()
    assert Path(os.environ['XDG_RUNTIME_DIR']).resolve() == base / 'runtime'
    assert os.environ['WAYLAND_DISPLAY'] == 'typetune-test'
    assert os.environ.get('AT_SPI_BUS_ADDRESS')
    source = 'до ghbdtn хвост\n🙂 e\u0301'
    fixture = base / 'editor-fixture.txt'
    fixture.write_text(source)
    app = subprocess.Popen(['gnome-text-editor', '--new-window', str(fixture)],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        Atspi.set_timeout(1000, 1000)
        deadline = time.monotonic() + 10
        field = None
        while time.monotonic() < deadline and field is None:
            desktop = Atspi.get_desktop(0)
            for i in range(desktop.get_child_count()):
                root = desktop.get_child_at_index(i)
                if root.get_process_id() != app.pid:
                    continue
                queue = [root]
                visited = 0
                while queue and visited < 512:
                    node = queue.pop()
                    visited += 1
                    if node.is_text() and node.get_state_set().contains(Atspi.StateType.EDITABLE):
                        text = node.get_text_iface()
                        if text.get_character_count() == len(source) and Atspi.Text.get_text(text, 0, len(source)) == source:
                            field = node
                            break
                    queue.extend(node.get_child_at_index(j) for j in range(min(node.get_child_count(), 128)))
            time.sleep(.1)
        assert field is not None, 'fixture editor text not exposed'
        text = field.get_text_iface()
        print('PASS EDITOR-01: real GNOME Text Editor PID, bounded text read, Unicode exact', flush=True)
        assert text.set_caret_offset(9)
        assert text.get_caret_offset() == 9
        assert text.get_n_selections() == 0
        assert text.add_selection(3, 9)
        selection = Atspi.Text.get_selection(text, 0)
        assert (selection.start_offset, selection.end_offset) == (3, 9)
        assert text.remove_selection(0)
        assert text.get_n_selections() == 0
        print('PASS EDITOR-02: scalar caret and selection round trip', flush=True)
        editable = field.is_editable_text()
        print('EDITOR capability EditableText=' + str(editable), flush=True)
        if editable:
            api = field.get_editable_text_iface()
            assert api.delete_text(3, 9)
            assert Atspi.Text.get_text(text, 0, text.get_character_count()) == source[:3] + source[9:]
            assert api.insert_text(3, 'привет', len('привет'.encode()))
            expected = source[:3] + 'привет' + source[9:]
            assert Atspi.Text.get_text(text, 0, text.get_character_count()) == expected
            assert text.set_caret_offset(9)
            assert text.get_caret_offset() == 9
            print('PASS EDITOR-03: synthetic delete/Unicode insert/readback; NOT atomic guarded replacement', flush=True)
        else:
            assert Atspi.Text.get_text(text, 0, len(source)) == source
            print('PASS EDITOR-03: absent EditableText refuses edit, source intact', flush=True)
        # Never infer composition state or compare-and-swap from Accessible/Text.
        print('EDITOR profile: replacement unavailable; composition=unknown; conditional_range=unavailable', flush=True)
        assert fixture.read_text() == source
        print('GNOME TEXT EDITOR PROBE PASS (synthetic private session; no saved edits)', flush=True)
    finally:
        app.terminate()
        try:
            app.wait(timeout=3)
        except subprocess.TimeoutExpired:
            app.kill()
            app.wait()


if __name__ == '__main__':
    main()
