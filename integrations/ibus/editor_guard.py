"""Read-only AT-SPI selection/focus proof, off the IBus loop."""
import time
import gi
gi.require_version('Atspi', '2.0')
from gi.repository import Atspi


def check_editor(pid, snapshot):
    # Only this worker thread touches AT-SPI. Never write text or log its value.
    Atspi.set_timeout(100, 100)
    deadline = time.monotonic() + .300
    try:
        desktop = Atspi.get_desktop(0)
        roots = [desktop.get_child_at_index(i) for i in range(min(desktop.get_child_count(), 64))]
        roots = [node for node in roots if node.get_process_id() == pid]
        queue = list(roots)
        for _ in range(128):
            if not queue or time.monotonic() >= deadline:
                break
            node = queue.pop()
            node.clear_cache()
            states = node.get_state_set()
            if node.is_text() and states.contains(Atspi.StateType.FOCUSED) and states.contains(Atspi.StateType.EDITABLE):
                if node.get_role() in (Atspi.Role.PASSWORD_TEXT, Atspi.Role.TERMINAL) or node.get_n_selections() != 0:
                    return False
                caret = node.get_caret_offset()
                value = snapshot['text']
                start = caret - snapshot['caret']
                if start < 0 or start + len(value) > node.get_character_count():
                    return False
                return (Atspi.Text.get_text(node, start, start + len(value)) == value and
                        node.get_n_selections() == 0 and node.get_caret_offset() == caret and
                        time.monotonic() < deadline)
            queue.extend(node.get_child_at_index(i) for i in range(min(node.get_child_count(), 64)))
    except Exception:
        return False
    return False
