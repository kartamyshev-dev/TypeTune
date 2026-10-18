"""Identity-bound native harness primitives. Importing never launches a probe."""
import hashlib
import json
import math
import pathlib
import subprocess
import time


def require(ok, reason):
    if not ok:
        raise ValueError(reason)


def digest(path):
    return hashlib.sha256(pathlib.Path(path).read_bytes()).hexdigest()


def validate_fixture_digest(record, fixture_bytes):
    expected = hashlib.sha256(fixture_bytes).hexdigest()
    require(record.get('caseFileSha256') == expected, 'fixture_digest_mismatch_or_missing')
    return expected


def target_binary(root, app=None, target='prototype'):
    require(target in ('prototype', 'original'), 'unknown_target')
    name = 'LayoutPilot' if target == 'prototype' else 'Caramba Switcher Pro'
    default = pathlib.Path(root)/'dist/LayoutPilot.app' if target == 'prototype' else pathlib.Path('/Applications/Caramba Switcher Pro.app')
    selected = pathlib.Path(app).expanduser().resolve() if app else default.resolve()
    require(target != 'original' or selected == default.resolve(), 'original_reference_path_mismatch')
    require(selected.suffix == '.app' and selected.is_dir(), 'target_bundle_absent')
    binary = selected/'Contents/MacOS'/name
    require(binary.is_file() and binary.resolve().is_relative_to(selected), 'target_executable_absent_or_external')
    return binary


def selected_switcher_pid(binary):
    roster = subprocess.check_output(['ps', '-ww', '-axo', 'pid=,comm='], text=True).splitlines()
    switchers = [row.strip().split(None, 1) for row in roster if row.strip() and
                 pathlib.Path(row.strip().split(None, 1)[-1]).name in
                 {'Caramba Switcher Pro', 'LayoutPilot', 'Lang Switcher', 'LangSwitcher', 'TypeTune'}]
    require(len(switchers) == 1 and switchers[0][1] == str(binary), 'Exactly the selected switcher must be running')
    return int(switchers[0][0])


def bundle_digest(app):
    app = pathlib.Path(app).resolve()
    require(app.is_dir(), 'target_bundle_absent')
    manifest = []
    for path in sorted(app.rglob('*')):
        relative = str(path.relative_to(app))
        if path.is_symlink():
            require(path.resolve().is_relative_to(app), 'external_bundle_symlink')
            manifest.append([relative, 'symlink', str(path.readlink())])
        elif path.is_file():
            manifest.append([relative, 'file', path.stat().st_mode & 0o777, digest(path)])
    require(manifest, 'empty_bundle')
    return hashlib.sha256(json.dumps(manifest, ensure_ascii=False, separators=(',', ':')).encode()).hexdigest()


def process_identity(pid):
    pid = int(pid)
    command = subprocess.check_output(['ps', '-ww', '-p', str(pid), '-o', 'comm='], text=True).strip()
    started = subprocess.check_output(['ps', '-p', str(pid), '-o', 'lstart='], text=True).strip()
    require(command and started, 'process_identity_unavailable')
    return {'pid': pid, 'command': command, 'started': started}


def capture(root, binary, pid):
    root, binary = pathlib.Path(root), pathlib.Path(binary)
    process = process_identity(pid)
    require(process['command'] == str(binary), 'target_process_path_mismatch')
    return {'schemaVersion': 1, 'bundleHashAlgorithm': 'paths-files-modes-symlinks-v1',
            'targetBundleSha256': bundle_digest(binary.parents[2]),
            'targetBinarySha256': digest(binary), 'probeSourceSha256': digest(root/'Tools/NativeProbe.swift'),
            'clipboardLeaseSourceSha256': digest(root/'Tools/ClipboardLease.swift'),
            'probeBinarySha256': digest(root/'.build/native-probe'), 'targetProcess': process}


def validate_binding(record):
    require(record.get('identityUnchanged') is True, 'identity_not_verified')
    before, after = record.get('identityBefore'), record.get('identityAfter')
    require(isinstance(before, dict) and before == after, 'identity_before_after_mismatch')
    require(before.get('schemaVersion') == 1 and before.get('bundleHashAlgorithm') == 'paths-files-modes-symlinks-v1', 'identity_schema_missing')
    for key in ['targetBundleSha256', 'targetBinarySha256', 'probeSourceSha256', 'probeBinarySha256']:
        value = before.get(key)
        require(isinstance(value, str) and len(value) == 64 and all(c in '0123456789abcdef' for c in value), 'invalid_' + key)
    for key in ['targetBinarySha256', 'probeSourceSha256', 'probeBinarySha256']:
        if key in record: require(record[key] == before[key], 'legacy_alias_identity_mismatch_' + key)
    target = before.get('targetProcess', {})
    require(type(target.get('pid')) is int and target['pid'] > 0 and target.get('command') and target.get('started'), 'target_process_identity_missing')
    helper = record.get('helperProcess', {})
    require(type(helper.get('pid')) is int and helper['pid'] > 0 and helper.get('started') and helper.get('command') == record.get('helperExecutable'), 'helper_process_identity_missing')
    require(record.get('helperChildWaitVerified') is True and type(record.get('processExitCode')) is int and record['processExitCode'] == 0 and not record.get('error'), 'helper_exit_not_verified')
    flags = record.get('finalModifierFlags')
    require(type(flags) is int and flags >= 0 and flags & 0x9f207f == 0, 'final_modifiers_not_neutral_or_missing')
    return before


def validate_workload_segments(record, required_idle_seconds):
    """Measured guarded TextEdit workload/idle; input includes readback/setup pauses."""
    require(required_idle_seconds in (0, 30), 'unsupported_idle_requirement')
    durations = [record.get(key) for key in ('inputSegmentSeconds', 'idleSegmentSeconds', 'helperWallSeconds')]
    require(all(type(value) in (int, float) and math.isfinite(value) and value >= 0 for value in durations), 'invalid_workload_durations')
    input_seconds, idle_seconds, wall_seconds = durations
    require(input_seconds > 0 and input_seconds + idle_seconds <= wall_seconds + 0.01, 'workload_duration_exceeds_helper')
    require(type(record.get('requiredIdleSeconds')) is int and record['requiredIdleSeconds'] == required_idle_seconds, 'idle_requirement_mismatch')
    require(idle_seconds >= required_idle_seconds if required_idle_seconds else idle_seconds == 0, 'idle_shorter_than_required')
    require(type(record.get('idleEvents')) is int and record['idleEvents'] == 0, 'idle_events_not_zero')
    return input_seconds, idle_seconds


def run_probe(root, binary, pid, arguments, timeout):
    """Run the already-built executable directly; wait on that exact child once."""
    root = pathlib.Path(root)
    before = capture(root, binary, pid)
    helper = str(root/'.build/native-probe')
    record = {'identityBefore': before, 'helperExecutable': helper, 'identityUnchanged': False,
              'helperChildWaitVerified': False}
    child = None
    began = time.monotonic()
    try:
        child = subprocess.Popen([helper, *arguments], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, cwd=root)
        record['helperProcess'] = process_identity(child.pid)
        require(record['helperProcess']['command'] == helper, 'wrong_helper_process_path')
        stdout, stderr = child.communicate(timeout=timeout)
        parsed = json.loads(stdout)
        require(isinstance(parsed, dict), 'probe_output_not_object')
        # Probe output cannot replace the harness-owned identity fields.
        parsed.update(record)
        record = parsed
        record['processExitCode'] = child.returncode
        record['helperChildWaitVerified'] = True
        if child.returncode:
            record['error'] = record.get('error', 'helper_nonzero_exit')
    except Exception as error:
        record['error'] = type(error).__name__ + ': ' + str(error)
        if child is not None:
            if child.poll() is None:
                child.kill()
            child.communicate()
            record['processExitCode'] = child.returncode
    record['helperWallSeconds'] = time.monotonic() - began
    try:
        record['identityAfter'] = capture(root, binary, pid)
        record['identityUnchanged'] = before == record['identityAfter']
        if not record['identityUnchanged']:
            record['error'] = 'identity_changed_during_run'
    except Exception as error:
        record['error'] = 'after_identity_failed: ' + str(error)
    return record
