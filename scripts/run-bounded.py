#!/usr/bin/env python3
"""Run one build phase in its own process group with bounded timeout cleanup."""
import argparse
from datetime import datetime, timezone
import os
from pathlib import Path
import signal
import subprocess
import sys
import time


def terminate_group(process):
    for sig in (signal.SIGTERM, signal.SIGKILL):
        try:
            os.killpg(process.pid, sig)
        except ProcessLookupError:
            break
        if sig == signal.SIGTERM:
            # The group may outlive its leader, so always send KILL after grace.
            time.sleep(1)
            # Reap a dead group leader: on macOS killpg against a group
            # containing only that zombie can report EPERM rather than ESRCH.
            process.poll()
    process.wait(timeout=5)


def run(command, seconds, directory):
    directory.mkdir(parents=True, exist_ok=True, mode=0o700)
    os.chmod(directory, 0o700)
    journal = directory / 'phase.log'
    with journal.open('w') as log:
        os.chmod(journal, 0o600)
        log.write(f'BEGIN {datetime.now(timezone.utc).isoformat()} timeout={seconds}\n')
        log.flush()
        print(f'Phase log: {journal}', flush=True)
        process = subprocess.Popen(command, start_new_session=True, stdout=log, stderr=subprocess.STDOUT)
        try:
            code = process.wait(timeout=seconds)
        except subprocess.TimeoutExpired:
            log.write(f'TIMEOUT group={process.pid}; collecting diagnostics before termination\n')
            log.flush()
            # PID/PPID/PGID/state only: no environment or unrelated arguments.
            try:
                listing = subprocess.check_output(['ps', '-axo', 'pid=,ppid=,pgid=,stat='], text=True, timeout=3)
                members = [line for line in listing.splitlines()
                           if len(line.split()) == 4 and line.split()[2] == str(process.pid)]
                log.write('\n'.join(members) + '\n'); log.flush()
                if sys.platform == 'darwin' and members:
                    sample = directory / 'sample.txt'
                    # Prefer the newest child over a waiting shell/group leader.
                    pid = max(int(line.split()[0]) for line in members)
                    sample.touch(mode=0o600)
                    subprocess.run(['/usr/bin/sample', str(pid), '1', '-file', str(sample)],
                                   stdout=log, stderr=log, timeout=5, check=False)
                    os.chmod(sample, 0o600)
            except (OSError, subprocess.SubprocessError) as error:
                log.write(f'diagnostic collection: {type(error).__name__}\n')
            finally:
                terminate_group(process)
            code = 124
        except BaseException:
            terminate_group(process)
            raise
        log.write(f'END exit={code} {datetime.now(timezone.utc).isoformat()}\n')
    if code:
        # Enough immediate context to act on a failure; the full private log is retained.
        with journal.open('rb') as stream:
            stream.seek(max(0, journal.stat().st_size - 65_536))
            tail = stream.read().decode(errors='replace')
        print('\n'.join(tail.splitlines()[-60:]), file=sys.stderr)
    return code if code >= 0 else 128 - code


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--seconds', type=float, default=600)
    parser.add_argument('--directory', type=Path, required=True)
    parser.add_argument('command', nargs=argparse.REMAINDER)
    args = parser.parse_args()
    if not args.command or args.seconds <= 0:
        parser.error('A positive timeout and a command are required')
    if args.command[0] == '--':
        args.command = args.command[1:]
    if not args.command:
        parser.error('A command is required after --')
    # Let the same cleanup path handle an interrupted build invocation.
    def interrupted(signum, frame):
        raise KeyboardInterrupt
    signal.signal(signal.SIGTERM, interrupted)
    sys.exit(run(args.command, args.seconds, args.directory))
