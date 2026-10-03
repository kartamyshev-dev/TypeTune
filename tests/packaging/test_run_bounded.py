import importlib.util
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch


spec = importlib.util.spec_from_file_location('run_bounded', Path(__file__).resolve().parents[2] / 'scripts/run-bounded.py')
bounded = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bounded)


class BoundedProcessTests(unittest.TestCase):
    def test_returns_command_result_and_retains_private_log(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            result = bounded.run([sys.executable, '-c', 'print("evidence"); raise SystemExit(7)'], 5, root)
            self.assertEqual(result, 7)
            self.assertIn('evidence', (root / 'phase.log').read_text())
            self.assertIn('END exit=7', (root / 'phase.log').read_text())
            self.assertEqual((root / 'phase.log').stat().st_mode & 0o777, 0o600)

    def test_timeout_keeps_unrelated_process_and_stops_own_group(self):
        unrelated = subprocess.Popen([sys.executable, '-c', 'import time; time.sleep(30)'])
        try:
            with tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                script = 'import os,time; print(os.getpid(), flush=True); time.sleep(30)'
                # Portable test avoids macOS sampling cost; production still captures it.
                with patch.object(bounded.sys, 'platform', 'test'):
                    result = bounded.run([sys.executable, '-c', script], 0.15, root)
                self.assertEqual(result, 124)
                self.assertIsNone(unrelated.poll())
                log = (root / 'phase.log').read_text()
                self.assertIn('TIMEOUT group=', log)
                pid = int(next(line for line in log.splitlines() if line.isdecimal()))
                with self.assertRaises(ProcessLookupError):
                    os.kill(pid, 0)
        finally:
            unrelated.terminate()
            unrelated.wait(timeout=5)

    def test_timeout_kills_child_which_ignores_term(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            child = 'import os,signal,time; signal.signal(signal.SIGTERM,signal.SIG_IGN); print(os.getpid(),flush=True); time.sleep(30)'
            script = 'import subprocess,sys,time; subprocess.Popen([sys.executable,"-c",' + repr(child) + ']); time.sleep(30)'
            with patch.object(bounded.sys, 'platform', 'test'):
                result = bounded.run([sys.executable, '-c', script], 0.2, root)
            self.assertEqual(result, 124)
            log = (root / 'phase.log').read_text()
            child_pid = next(line for line in log.splitlines() if line.isdecimal())
            # A just-killed orphan can briefly remain a zombie until init reaps
            # it. Either absence or zombie confirms it cannot keep doing work.
            for _ in range(20):
                state = subprocess.run(['ps', '-p', child_pid, '-o', 'stat='], capture_output=True, text=True)
                if state.returncode != 0 or state.stdout.strip().startswith('Z'):
                    break
                time.sleep(0.05)
            else:
                self.fail(f'Child {child_pid} survived the timeout process-group cleanup')


if __name__ == '__main__':
    unittest.main()
