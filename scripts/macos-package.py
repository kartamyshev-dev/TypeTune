#!/usr/bin/env python3
"""Build identity and verified macOS bundle installation; never launches the app."""
import argparse
from contextlib import contextmanager, nullcontext
import ctypes
import fcntl
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import stat
import subprocess
import sys
import tempfile
import uuid

BUNDLE_ID = 'dev.kartamyshev.TypeTune'


def command(arguments, **kwargs):
    return subprocess.run(arguments, check=True, timeout=60, **kwargs)


def source_identity(root):
    def git(*args):
        return subprocess.check_output(['git', *args], cwd=root, timeout=30).decode().strip()
    revision = git('rev-parse', 'HEAD')
    dirty = bool(git('status', '--porcelain'))
    # Match the repository's vMAJOR.MINOR.PATCH release convention, including
    # development commits following a release (Cargo's workspace version lags).
    tags = git('tag', '--merged', 'HEAD', '--sort=-version:refname').splitlines()
    version = next((tag[1:] for tag in tags if re.fullmatch(r'v\d+\.\d+\.\d+', tag)), None)
    if version is None:
        # Shallow branch checkouts used by CI may contain no tags. Release notes
        # are versioned alongside the source and remain available there.
        releases = [file.stem for file in (root / 'docs/releases').glob('*.md')
                    if re.fullmatch(r'\d+\.\d+\.\d+', file.stem)]
        version = max(releases, key=lambda item: tuple(map(int, item.split('.'))), default='0.0.0')
    digest = hashlib.sha256()
    names = subprocess.check_output(['git', 'ls-files', '-z', '--cached', '--others', '--exclude-standard'],
                                    cwd=root, timeout=30).split(b'\0')
    for raw in sorted(set(name for name in names if name)):
        path = root / os.fsdecode(raw)
        digest.update(raw + b'\0')
        if path.is_symlink():
            digest.update(b'link\0' + os.fsencode(os.readlink(path)))
        elif path.is_file():
            digest.update(str(path.stat().st_mode & 0o777).encode() + b'\0')
            with path.open('rb') as stream:
                for block in iter(lambda: stream.read(1024 * 1024), b''):
                    digest.update(block)
        else:
            digest.update(b'deleted')
        digest.update(b'\0')
    source_digest = digest.hexdigest()
    return dict(version=version, build=git('rev-list', '--count', 'HEAD'), source_commit=revision,
                source_dirty=dirty, source_digest=source_digest,
                description=f'{version}+g{revision[:12]}{".dirty" if dirty else ""}.{source_digest[:12]}')


def stamp(root, bundle, expected):
    identity = source_identity(root)
    if identity != expected:
        raise RuntimeError('Sources changed during the build; rebuild the candidate before installing')
    metadata = dict(CFBundleIdentifier=BUNDLE_ID, CFBundleName='TypeTune', CFBundleExecutable='TypeTune',
                    CFBundlePackageType='APPL', CFBundleShortVersionString=identity['version'],
                    CFBundleVersion=identity['build'], LSMinimumSystemVersion='27.0', LSUIElement=True,
                    NSHighResolutionCapable=True, TypeTuneSourceCommit=identity['source_commit'],
                    TypeTuneSourceDirty=identity['source_dirty'], TypeTuneSourceDigest=identity['source_digest'],
                    TypeTuneBuildDescription=identity['description'])
    with (bundle / 'Contents/Info.plist').open('wb') as stream:
        plistlib.dump(metadata, stream)


def verify(bundle):
    if bundle.is_symlink() or not bundle.is_dir():
        raise RuntimeError(f'Expected a real app bundle: {bundle}')
    with (bundle / 'Contents/Info.plist').open('rb') as stream:
        metadata = plistlib.load(stream)
    if metadata.get('CFBundleIdentifier') != BUNDLE_ID or metadata.get('CFBundleExecutable') != 'TypeTune':
        raise RuntimeError(f'Not a TypeTune bundle: {bundle}')
    if not (bundle / 'Contents/MacOS/TypeTune').is_file():
        raise RuntimeError(f'Executable is missing: {bundle}')
    command(['codesign', '--verify', '--deep', '--strict', str(bundle)])


def ensure_stopped():
    result = subprocess.run(['pgrep', '-x', 'TypeTune'], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                            text=True, timeout=10)
    if result.returncode == 0:
        raise RuntimeError('TypeTune is running. Quit TypeTune before replacing its bundle.')
    if result.returncode != 1:
        raise RuntimeError('Cannot establish whether TypeTune is running; installation was not attempted')


@contextmanager
def application_lock(path=None):
    """Share the app's launch lock, closing the process-check/swap race."""
    path = path or Path.home() / 'Library/Application Support/TypeTune/instance.lock'
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    descriptor = os.open(path, os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
    try:
        if not stat.S_ISREG(os.fstat(descriptor).st_mode):
            raise RuntimeError('TypeTune instance lock is not a regular file')
        os.fchmod(descriptor, 0o600)
        try:
            fcntl.flock(descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as error:
            raise RuntimeError('TypeTune or another installer holds the instance lock; quit it first') from error
        yield
    finally:
        os.close(descriptor)


def default_destination(home=None, applications=Path('/Applications')):
    home = Path.home() if home is None else home
    candidates = [applications / 'TypeTune.app', home / 'Applications/TypeTune.app']
    return next((path for path in candidates if path.exists()), candidates[1])


def exchange(left, right):
    # renamex_np exchanges complete directory trees atomically on macOS. An
    # unavailable/unsupported filesystem must fail before replacing either app.
    libc = ctypes.CDLL(None, use_errno=True)
    function = libc.renamex_np
    function.argtypes = [ctypes.c_char_p, ctypes.c_char_p, ctypes.c_uint]
    function.restype = ctypes.c_int
    if function(os.fsencode(left), os.fsencode(right), 2) != 0:  # RENAME_SWAP
        error = ctypes.get_errno()
        raise OSError(error, os.strerror(error))


def rollback_directory():
    return Path.home() / 'Library/Application Support/TypeTune/backups'


def bundle_digest(bundle):
    digest = hashlib.sha256()
    for path in sorted(bundle.rglob('*')):
        relative = os.fsencode(path.relative_to(bundle))
        if path.is_symlink():
            digest.update(b'link\0' + relative + b'\0' + os.fsencode(os.readlink(path)) + b'\0')
        elif path.is_file():
            digest.update(b'file\0' + relative + b'\0')
            with path.open('rb') as stream:
                for block in iter(lambda: stream.read(1024 * 1024), b''):
                    digest.update(block)
            digest.update(b'\0')
    return digest.hexdigest()


def archive_bundle(bundle):
    """Keep rollback outside LaunchServices app discovery, before replacement."""
    directory = rollback_directory()
    directory.mkdir(parents=True, exist_ok=True, mode=0o700)
    os.chmod(directory, 0o700)
    archive = directory / f'TypeTune.rollback-{uuid.uuid4().hex[:12]}.zip'
    pending = archive.with_suffix('.zip.pending')
    expected = bundle_digest(bundle)
    try:
        command(['ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', str(bundle), str(pending)])
        with tempfile.TemporaryDirectory(prefix='.verify-', dir=directory) as temporary:
            command(['ditto', '-x', '-k', str(pending), temporary])
            extracted = Path(temporary) / bundle.name
            verify(extracted)
            if bundle_digest(extracted) != expected or bundle_digest(bundle) != expected:
                raise RuntimeError('Rollback archive does not match the original bundle')
        with pending.open('rb') as stream:
            os.fsync(stream.fileno())
        pending.chmod(0o400)
        os.replace(pending, archive)
    finally:
        pending.unlink(missing_ok=True)
    return archive


def install(source, destination, check_running=True):
    # Publishing an artifact in dist does not alter an installed app. Installation
    # holds the same per-user lock acquired before AppDelegate starts its runtime.
    with application_lock() if check_running else nullcontext():
        return replace_bundle(source, destination, check_running)


def replace_bundle(source, destination, check_running):
    source, destination = source.absolute(), destination.absolute()
    if destination.name != 'TypeTune.app' or source == destination or destination.is_symlink():
        raise RuntimeError('Destination must be a separate, non-symlink TypeTune.app')
    verify(source)
    if check_running:
        ensure_stopped()
    if destination.exists():
        # Old metadata may predate source identity, but the identity and signature
        # must still be TypeTune's before we replace it.
        verify(destination)
    destination.parent.mkdir(parents=True, exist_ok=True)
    # Neither the staging directory nor the old bundle's temporary name has an
    # .app suffix: a second discoverable bundle ID confuses macOS TCC grants.
    staging = Path(tempfile.mkdtemp(prefix='.TypeTune-install-', dir=destination.parent))
    candidate = staging / 'candidate'
    archive = None
    swapped = False
    preserve_stage = False
    installed_new = False
    try:
        command(['ditto', str(source), str(candidate)])
        verify(candidate)
        if check_running:
            ensure_stopped()
        if destination.exists():
            if check_running:
                archive = archive_bundle(destination)
                ensure_stopped()
            exchange(candidate, destination)
            swapped = True
        else:
            os.rename(candidate, destination)
            installed_new = True
        verify(destination)
    except BaseException:
        if swapped:
            # If rollback itself fails, both bundles are deliberately retained
            # in addition to the verified ZIP, and the error is propagated.
            preserve_stage = True
            exchange(candidate, destination)
            preserve_stage = False
        elif installed_new:
            os.rename(destination, candidate)
        raise
    finally:
        if not preserve_stage:
            shutil.rmtree(staging)
    return archive


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='operation', required=True)
    identity_parser = commands.add_parser('identity')
    identity_parser.add_argument('root', type=Path)
    stamp_parser = commands.add_parser('stamp')
    stamp_parser.add_argument('root', type=Path)
    stamp_parser.add_argument('bundle', type=Path)
    stamp_parser.add_argument('identity', type=Path)
    for operation in ('install', 'publish'):
        install_parser = commands.add_parser(operation)
        install_parser.add_argument('source', type=Path)
        install_parser.add_argument('destination', type=Path, nargs=None if operation == 'publish' else '?')
    args = parser.parse_args()
    if args.operation == 'identity':
        print(json.dumps(source_identity(args.root), sort_keys=True))
    elif args.operation == 'stamp':
        stamp(args.root, args.bundle, json.loads(args.identity.read_text()))
    else:
        destination = args.destination or default_destination()
        if args.operation == 'publish' and destination.absolute() != Path(__file__).resolve().parents[1] / 'dist/TypeTune.app':
            raise RuntimeError('publish is restricted to the repository dist/TypeTune.app artifact')
        backup = install(args.source, destination, check_running=args.operation == 'install')
        print(f'Installed: {destination}')
        if backup:
            print(f'Rollback archive: {backup}')


if __name__ == '__main__':
    try:
        main()
    except (OSError, RuntimeError, subprocess.SubprocessError) as error:
        print(f'macOS packaging failed: {error}', file=sys.stderr)
        sys.exit(1)
