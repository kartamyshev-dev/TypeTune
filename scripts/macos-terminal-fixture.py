#!/usr/bin/env python3
"""Isolated PTY fixture; no shell commands, personal text, or AX text readback.

Launch with exec in a newly created Terminal window. The JSON oracle describes
bytes received by this editor and its logical UTF-16 caret, not a screen capture.
"""
import argparse
import codecs
import json
import os
import re
import select
import signal
import stat
import sys
import tempfile
import termios
import time

WORDS = ("", "hello ", "ghbdtn", "привет", "Ghbdtn", "Привет", "ghbdtn ", "привет ",
         "ghbdtn  ", "привет  ", "Ghbdtn ", "Привет ", "ghbdtn ghbdtn ", "привет привет ",
         "ghbdtn привет ", "привет ghbdtn ", "ghbdtn ghbdtn  ", "привет привет  ")
ALLOWED = {word[:length] for word in WORDS for length in range(len(word) + 1)}


class FixtureError(Exception):
    pass


class Editor:
    def __init__(self):
        self.text = ""
        self.revision = 0
        self.received_bytes = 0
        self.decoder = codecs.getincrementaldecoder("utf-8")("strict")

    @property
    def caret(self):
        return len(self.text.encode("utf-16-le")) // 2

    @property
    def pending_utf8_bytes(self):
        return len(self.decoder.getstate()[0])

    def receive(self, data):
        for byte in data:
            self.received_bytes += 1
            if byte in (8, 127, 21):  # Backspace, Delete, fixture clear (Ctrl+U).
                if self.decoder.getstate()[0]:
                    raise FixtureError("control_inside_utf8")
                candidate = "" if byte == 21 else self.text[:-1]
            else:
                try:
                    character = self.decoder.decode(bytes((byte,)))
                except UnicodeDecodeError as exc:
                    raise FixtureError("invalid_utf8") from exc
                if not character:
                    continue
                candidate = self.text + character
            if candidate not in ALLOWED:
                raise FixtureError("input_not_allowlisted")
            self.text = candidate
            self.revision += 1


class StateWriter:
    def __init__(self, directory):
        # A fresh directory prevents adoption of another run or a stale oracle.
        os.mkdir(directory, 0o700)
        self.fd = os.open(directory, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
        info = os.fstat(self.fd)
        if info.st_uid != os.getuid() or stat.S_IMODE(info.st_mode) != 0o700:
            raise FixtureError("unsafe_run_directory")

    def publish(self, state):
        raw = json.dumps(state, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
        if len(raw) > 8192:
            raise FixtureError("state_too_large")
        fd = os.open(".state.pending", os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
                     0o600, dir_fd=self.fd)
        try:
            with os.fdopen(fd, "wb") as stream:
                stream.write(raw)
            os.replace(".state.pending", "state.json", src_dir_fd=self.fd, dst_dir_fd=self.fd)
        finally:
            try:
                os.unlink(".state.pending", dir_fd=self.fd)
            except FileNotFoundError:
                pass

    def close(self):
        os.close(self.fd)


def self_check():
    editor = Editor()
    editor.receive(b"ghbdtn  ")
    assert editor.text == "ghbdtn  " and editor.caret == 8
    editor.receive(b"\x7f" * 8)
    for byte in "привет  ".encode("utf-8"):
        editor.receive(bytes((byte,)))
    assert editor.text == "привет  " and editor.caret == 8
    editor.receive(b"\x15")
    assert editor.text == "" and editor.caret == 0
    editor.receive(b"\xd0")
    assert editor.text == "" and editor.pending_utf8_bytes == 1
    editor.receive(b"\xbf")
    assert editor.text == "п" and editor.pending_utf8_bytes == 0
    for invalid in (b"private", b"\r", b"\n", b"\x1b[A", b"\xff"):
        try:
            Editor().receive(invalid)
            raise AssertionError("unsafe input accepted")
        except FixtureError:
            pass
    with tempfile.TemporaryDirectory(prefix="typetune-terminal-selfcheck-") as root:
        path = os.path.join(root, "run")
        writer = StateWriter(path)
        writer.publish({"value": "привет", "caret_utf16": 6})
        state_path = os.path.join(path, "state.json")
        assert stat.S_IMODE(os.stat(path).st_mode) == 0o700
        assert stat.S_IMODE(os.stat(state_path).st_mode) == 0o600
        with open(state_path, encoding="utf-8") as stream:
            assert json.load(stream)["value"] == "привет"
        writer.close()
        try:
            StateWriter(path)
            raise AssertionError("existing run accepted")
        except FileExistsError:
            pass
        link = os.path.join(root, "link")
        os.symlink(path, link)
        try:
            StateWriter(link)
            raise AssertionError("symlink run accepted")
        except FileExistsError:
            pass
    print(json.dumps({"status": "PASS", "mode": "self-check", "tests": 14,
                      "events_posted": 0, "tty_modified": False}))


def run(args):
    if not re.fullmatch(r"[a-f0-9]{32}", args.run_id):
        raise FixtureError("invalid_run_id")
    if args.title != "TypeTune Native Check Terminal " + args.run_id:
        raise FixtureError("invalid_fixture_title")
    if not os.path.isabs(args.run_dir) or not 15 <= args.timeout <= 600:
        raise FixtureError("invalid_run_directory_or_timeout")
    if not os.isatty(0) or not os.isatty(1) or os.ttyname(0) != os.ttyname(1):
        raise FixtureError("isolated_tty_required")
    if os.tcgetpgrp(0) != os.getpgrp():
        raise FixtureError("fixture_not_foreground")
    writer = StateWriter(args.run_dir)
    original = termios.tcgetattr(0)
    editor = Editor()
    status, reason = "ready", ""
    stopping = False
    deadline = time.monotonic() + args.timeout

    def stop(_signal, _frame):
        nonlocal stopping
        stopping = True

    def state():
        return {"version": 1, "run_id": args.run_id, "title": args.title,
                "helper_pid": os.getpid(), "uid": os.getuid(), "tty": os.ttyname(0),
                "foreground": os.tcgetpgrp(0) == os.getpgrp(), "updated_unix_ms": time.time() * 1000,
                "revision": editor.revision, "received_bytes": editor.received_bytes,
                "pending_utf8_bytes": editor.pending_utf8_bytes,
                "value": editor.text, "caret_utf16": editor.caret, "selection_length": 0,
                "status": status, "reason": reason}

    for name in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP, signal.SIGQUIT, signal.SIGTSTP):
        signal.signal(name, stop)
    try:
        settings = termios.tcgetattr(0)
        settings[0] &= ~(termios.BRKINT | termios.ICRNL | termios.INPCK | termios.ISTRIP | termios.IXON)
        settings[2] |= termios.CS8
        # Control characters must pass the allowlist, never suspend this process
        # with raw terminal settings or bypass finally through a signal default.
        settings[3] &= ~(termios.ECHO | termios.ICANON | termios.IEXTEN | termios.ISIG)
        settings[6][termios.VMIN] = 1
        settings[6][termios.VTIME] = 0
        termios.tcsetattr(0, termios.TCSANOW, settings)
        # Only this already isolated PTY is changed. Keep a dedicated empty line.
        os.write(1, ("\x1b]2;" + args.title + "\x07\r\n").encode("ascii"))
        writer.publish(state())
        while not stopping and time.monotonic() < deadline:
            if os.tcgetpgrp(0) != os.getpgrp():
                status, reason = "failed", "fixture_lost_foreground"
                break
            readable, _, _ = select.select([0], [], [], min(0.05, max(0, deadline - time.monotonic())))
            if readable:
                data = os.read(0, 1024)
                if not data:
                    status, reason = "failed", "tty_eof"
                    break
                if status == "ready":
                    try:
                        editor.receive(data)
                        os.write(1, ("\r\x1b[2K" + editor.text).encode("utf-8"))
                    except FixtureError as exc:
                        # Preserve only the last allowed value. Never expose
                        # unexpected input or let it reach a shell after failure.
                        status, reason = "failed", str(exc)
            writer.publish(state())
        if status == "ready":
            status, reason = "stopped", "signal" if stopping else "deadline"
        writer.publish(state())
    finally:
        termios.tcsetattr(0, termios.TCSANOW, original)
        writer.close()
    return 0 if status == "stopped" else 1


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--self-check", action="store_true")
    parser.add_argument("--run-dir")
    parser.add_argument("--run-id")
    parser.add_argument("--title")
    parser.add_argument("--timeout", type=int, default=240)
    args = parser.parse_args()
    if args.self_check:
        self_check()
        return 0
    if not all((args.run_dir, args.run_id, args.title)):
        parser.error("--run-dir, --run-id and --title are required")
    try:
        return run(args)
    except (FixtureError, OSError) as exc:
        # No exception paths, terminal input, or personal text are printed.
        code = str(exc) if isinstance(exc, FixtureError) else "fixture_io_failed"
        print(json.dumps({"status": "ERROR", "reason": code}), file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
