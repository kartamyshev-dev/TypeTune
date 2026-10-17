"""Real ZLE in a private PTY, mock decisions. No GUI, input injection or user shell config."""
import fcntl
import os
from pathlib import Path
import pty
import select
import signal
import socket
import subprocess
import tempfile
import termios
import threading
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]


class Session:
    def __init__(self, response='edit\tпривет\n'):
        self.temp = tempfile.TemporaryDirectory(prefix='lp-zle-', dir='/tmp')
        home = Path(self.temp.name)
        path = home/'Library/Application Support/LayoutPilot/terminal.sock'
        path.parent.mkdir(parents=True)
        self.server = socket.socket(socket.AF_UNIX)
        self.server.bind(str(path)); self.server.listen(1); self.server.settimeout(5)
        self.events = []
        self.response = response
        self.client = None
        self.error = None
        threading.Thread(target=self.serve, daemon=True).start()
        self.master, slave = pty.openpty()
        def tty():
            os.setsid(); fcntl.ioctl(slave, termios.TIOCSCTTY, 0)
        env = os.environ | dict(HOME=str(home), ZDOTDIR=str(home), TERM='xterm-256color', TERM_PROGRAM='ghostty', LC_ALL='en_US.UTF-8')
        # The GUI fixture's report is pinned inside project private probes.
        report = ROOT/'research/private/probes'/('TerminalFixture-'+home.name+'.json')
        report.parent.mkdir(parents=True, exist_ok=True)
        self.report = report
        self.process = subprocess.Popen(['/bin/zsh', '-d', '-f', '-i', str(ROOT/'Tools/TerminalFixture.zsh'), str(report)],
            stdin=slave, stdout=slave, stderr=slave, env=env, preexec_fn=tty)
        os.close(slave)
        self.output = b''
        try:
            self.wait(lambda: self.client is not None)
            self.read_until(b'\x1b[?2004h')
        except BaseException:
            self.close(); raise

    def serve(self):
        try:
            self.client, _ = self.server.accept()
            stream = self.client.makefile('rb')
            hello = stream.readline().decode().strip().split('\t')
            assert hello[:2] == ['hello', 'com.mitchellh.ghostty'], hello
            self.client.sendall(b'ready\n')
            for raw in stream:
                line = raw.decode().rstrip('\n'); self.events.append(line)
                if line.startswith(('auto\t', 'manual\t')):
                    if self.response is None: continue
                    answer = self.response if line.endswith('\tghbdtn') else 'skip\n'
                    self.client.sendall(answer.encode())
        except (OSError, AssertionError) as error:
            self.error = str(error)

    def wait(self, condition):
        end = time.monotonic() + 5
        while not condition():
            if self.error is not None: raise AssertionError(self.error)
            if time.monotonic() >= end: raise AssertionError('PTY timeout: ' + repr(self.events))
            time.sleep(0.01)

    def type(self, value):
        os.write(self.master, value)

    def notify(self, value):
        self.client.sendall((value+'\n').encode())

    def result(self, expected):
        self.type(b'\r')
        target = ('LP-FIXTURE-RESULT:'+expected).encode()
        self.read_until(target)

    def read_until(self, target):
        end = time.monotonic() + 5
        while target not in self.output:
            if time.monotonic() >= end: raise AssertionError(repr(self.output[-1000:]))
            ready, _, _ = select.select([self.master], [], [], 0.1)
            if ready: self.output += os.read(self.master, 8192)

    def close(self):
        os.killpg(self.process.pid, signal.SIGKILL)
        self.process.wait(timeout=3)
        if self.client: self.client.close()
        self.server.close(); os.close(self.master); self.temp.cleanup()
        self.report.unlink(missing_ok=True)


class ZleTests(unittest.TestCase):
    def run_session(self, action, response='edit\tпривет\n'):
        session = Session(response)
        try: action(session)
        finally: session.close()

    def test_auto(self):
        self.run_session(lambda s: (s.type(b'ghbdtn '), s.wait(lambda: 'applied' in s.events), s.result('привет ')))

    def test_correct_word(self):
        self.run_session(lambda s: (s.type(b'hello '), s.wait(lambda: 'auto\thello' in s.events), s.result('hello ')))

    def test_manual(self):
        def run(s):
            s.type(b'ghbdtn'); time.sleep(0.1); s.notify('manual')
            s.wait(lambda: 'applied' in s.events); s.result('привет')
        self.run_session(run)

    def test_undo(self):
        def run(s):
            s.type(b'ghbdtn '); s.wait(lambda: 'applied' in s.events)
            time.sleep(0.1); s.notify('undo'); s.wait(lambda: 'undone' in s.events); s.result('ghbdtn ')
        self.run_session(run)

    def test_timeout_preserves_input(self):
        self.run_session(lambda s: (s.type(b'ghbdtn '), s.wait(lambda: 'auto\tghbdtn' in s.events), time.sleep(0.35), s.result('ghbdtn ')), response=None)

    def test_control_payload_rejected(self):
        self.run_session(lambda s: (s.type(b'ghbdtn '), s.wait(lambda: 'auto\tghbdtn' in s.events), time.sleep(0.1), s.result('ghbdtn ')), response='edit\tbad\x1bpayload\n')


if __name__ == '__main__': unittest.main()
