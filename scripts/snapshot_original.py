#!/usr/bin/env python3
"""Local-only reproducible snapshot. Never publishes original app/user data."""
import hashlib, json, os, pathlib, plistlib, shutil, sqlite3, subprocess

ROOT = pathlib.Path(__file__).resolve().parents[1]
PRIVATE = ROOT / 'research/private'
EVIDENCE = ROOT / 'research/evidence'
APP = pathlib.Path('/Applications/Caramba Switcher Pro.app')
PRIVATE.mkdir(parents=True, exist_ok=True)
os.chmod(PRIVATE, 0o700)
EVIDENCE.mkdir(parents=True, exist_ok=True)

def command(*args):
    p = subprocess.run(args, capture_output=True, text=True)
    return {'exit': p.returncode, 'stdout': p.stdout, 'stderr': p.stderr}

def manifest(path):
    result = []
    for p in sorted(path.rglob('*')):
        rel = str(p.relative_to(path))
        if p.is_symlink():
            result.append({'path': rel, 'symlink': os.readlink(p)})
        elif p.is_file():
            result.append({'path': rel, 'size': p.stat().st_size,
                           'sha256': hashlib.sha256(p.read_bytes()).hexdigest()})
    return result

copy = PRIVATE / APP.name
before = manifest(APP)
if not copy.exists():
    subprocess.run(['ditto', str(APP), str(copy)], check=True)
assert manifest(copy) == before, 'Research copy differs from installed original'
(EVIDENCE / 'original-manifest.json').write_text(json.dumps(before, indent=2))
info = plistlib.loads((APP / 'Contents/Info.plist').read_bytes())
record = {'version': info['CFBundleShortVersionString'], 'build': info['CFBundleVersion'],
          'bundleIdentifier': info['CFBundleIdentifier'], 'architecture': command('uname', '-m'),
          'os': command('sw_vers'), 'swift': command('swift', '--version'),
          'binary': command('file', str(APP / 'Contents/MacOS' / info['CFBundleExecutable'])),
          'signature': command('codesign', '-dvvv', str(APP)),
          'signatureVerification': command('codesign', '--verify', '--deep', '--strict', str(APP)),
          'entitlements': command('codesign', '-d', '--entitlements', ':-', str(APP))}
(EVIDENCE / 'environment.json').write_text(json.dumps(record, indent=2))
home = pathlib.Path.home()
candidates = [home/'Library/Containers/tech.caramba.switcher',
              home/'Library/Group Containers/AKZHD7272L.com.caramba-switcher.shared',
              home/'Library/Preferences/tech.caramba.switcher.plist']
backup = PRIVATE / 'initial-state'
backup.mkdir(exist_ok=True)
inventory = []
for source in candidates:
    item = {'path': str(source.relative_to(home)), 'exists': source.exists()}
    if source.exists():
        target = backup / str(source.relative_to(home))
        try:
            if not target.exists():
                target.parent.mkdir(parents=True, exist_ok=True)
                subprocess.run(['ditto', str(source), str(target)], check=True, capture_output=True)
            # SQLite backup reads a coherent snapshot, including a live WAL.
            for db in source.rglob('*.sqlite') if source.is_dir() else []:
                destination = backup / 'sqlite' / (hashlib.sha256(str(db).encode()).hexdigest()[:12]+'.sqlite')
                destination.parent.mkdir(exist_ok=True)
                if not destination.exists():
                    with sqlite3.connect(f'file:{db}?mode=ro', uri=True) as src:
                        with sqlite3.connect(destination) as dst:
                            src.backup(dst)
                            assert dst.execute('PRAGMA integrity_check').fetchone()[0] == 'ok'
            item['backup'] = 'local private backup created'
        except (OSError, subprocess.CalledProcessError, sqlite3.Error) as error:
            item['error'] = str(error)
    inventory.append(item)
(PRIVATE/'state-inventory.json').write_text(json.dumps(inventory, indent=2))
(PRIVATE/'input-sources.plist').write_text(command('defaults', 'read', 'com.apple.HIToolbox')['stdout'])
processes = command('pgrep', '-fl', 'Caramba|TypeTune|Lang Switcher')
(PRIVATE/'initial-processes.json').write_text(json.dumps(processes, indent=2))
assert manifest(APP) == before, 'Installed original changed during snapshot'
print(json.dumps({'copied_files': len(before), 'version': record['version'],
                  'signature_verified': record['signatureVerification']['exit'] == 0,
                  'data_backups': inventory}, indent=2))
