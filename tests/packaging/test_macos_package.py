import importlib.util
from contextlib import nullcontext
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile
import unittest
import zipfile
from unittest.mock import patch


spec = importlib.util.spec_from_file_location('macos_package', Path(__file__).resolve().parents[2] / 'scripts/macos-package.py')
package = importlib.util.module_from_spec(spec)
spec.loader.exec_module(package)


class BundleInstallTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.source = self.bundle(self.root / 'dist/TypeTune.app', 'new')
        self.destination = self.bundle(self.root / 'Applications/TypeTune.app', 'old')
        self.commands = []
        lock_patch = patch.object(package, 'application_lock', return_value=nullcontext())
        lock_patch.start()
        self.addCleanup(lock_patch.stop)
        directory_patch = patch.object(package, 'rollback_directory', return_value=self.root / 'private-backups')
        directory_patch.start()
        self.addCleanup(directory_patch.stop)

    def bundle(self, path, text):
        (path / 'Contents/MacOS').mkdir(parents=True)
        (path / 'Contents/MacOS/TypeTune').write_text(text)
        with (path / 'Contents/Info.plist').open('wb') as stream:
            plistlib.dump(dict(CFBundleIdentifier=package.BUNDLE_ID, CFBundleExecutable='TypeTune'), stream)
        return path

    def command(self, arguments, **kwargs):
        self.commands.append(arguments)
        if arguments[0] == 'ditto':
            if arguments[1] == '-c':
                bundle = Path(arguments[-2])
                with zipfile.ZipFile(arguments[-1], 'w') as archive:
                    for file in bundle.rglob('*'):
                        if file.is_file(): archive.write(file, file.relative_to(bundle.parent))
            elif arguments[1] == '-x':
                with zipfile.ZipFile(arguments[-2]) as archive: archive.extractall(arguments[-1])
            else:
                shutil.copytree(arguments[1], arguments[2])

    @staticmethod
    def exchange(left, right):
        # Portable stand-in for the single macOS RENAME_SWAP operation.
        temporary = left.with_name('exchange-temporary')
        left.rename(temporary)
        right.rename(left)
        temporary.rename(right)

    def installed_text(self):
        return (self.destination / 'Contents/MacOS/TypeTune').read_text()

    def test_replaces_complete_bundle_and_retains_original_backup(self):
        (self.destination / 'obsolete-resource').write_text('must not survive')
        with patch.object(package, 'command', self.command), \
                patch.object(package, 'ensure_stopped') as stopped, \
                patch.object(package, 'exchange', self.exchange):
            backup = package.install(self.source, self.destination)
        self.assertEqual(stopped.call_count, 3)
        self.assertEqual(self.installed_text(), 'new')
        self.assertFalse((self.destination / 'obsolete-resource').exists())
        with zipfile.ZipFile(backup) as archive:
            self.assertEqual(archive.read('TypeTune.app/Contents/MacOS/TypeTune'), b'old')
            self.assertEqual(archive.read('TypeTune.app/obsolete-resource'), b'must not survive')
        self.assertEqual(backup.suffix, '.zip')
        self.assertEqual(backup.stat().st_mode & 0o777, 0o400)
        self.assertEqual(backup.parent.stat().st_mode & 0o777, 0o700)
        self.assertEqual(list(self.destination.parent.iterdir()), [self.destination])
        copies = [args for args in self.commands if args[0] == 'ditto' and len(args) == 3]
        self.assertTrue(all(not args[-1].endswith('.app') for args in copies))
        self.assertFalse(any(args[0] == 'ditto' and args[2] == str(self.destination) for args in self.commands))

    def test_rejects_running_process_before_copy(self):
        with patch.object(package, 'command', self.command), \
                patch.object(package, 'ensure_stopped', side_effect=RuntimeError('running')):
            with self.assertRaisesRegex(RuntimeError, 'running'):
                package.install(self.source, self.destination)
        self.assertEqual(self.installed_text(), 'old')
        self.assertFalse(any(args[0] == 'ditto' for args in self.commands))

    def test_process_start_during_staging_aborts_before_swap(self):
        with patch.object(package, 'command', self.command), \
                patch.object(package, 'ensure_stopped', side_effect=[None, RuntimeError('running')]), \
                patch.object(package, 'exchange') as exchange:
            with self.assertRaisesRegex(RuntimeError, 'running'):
                package.install(self.source, self.destination)
        exchange.assert_not_called()
        self.assertEqual(self.installed_text(), 'old')
        self.assertEqual(list(self.destination.parent.iterdir()), [self.destination])

    def test_post_install_verification_failure_rolls_back(self):
        destination_verifications = 0
        def command(arguments, **kwargs):
            nonlocal destination_verifications
            if arguments[0] == 'codesign' and arguments[-1] == str(self.destination):
                destination_verifications += 1
                if destination_verifications == 2:
                    raise RuntimeError('post-install verification failed')
            self.command(arguments, **kwargs)
        with patch.object(package, 'command', command), patch.object(package, 'ensure_stopped'), \
                patch.object(package, 'exchange', self.exchange):
            with self.assertRaisesRegex(RuntimeError, 'post-install'):
                package.install(self.source, self.destination)
        self.assertEqual(self.installed_text(), 'old')
        self.assertEqual(list(self.destination.parent.iterdir()), [self.destination])

    def test_bad_staged_signature_keeps_original(self):
        def command(arguments, **kwargs):
            if arguments[0] == 'codesign' and Path(arguments[-1]).name == 'candidate':
                raise RuntimeError('signature failed')
            self.command(arguments, **kwargs)
        with patch.object(package, 'command', command), patch.object(package, 'ensure_stopped'), \
                patch.object(package, 'exchange') as exchange:
            with self.assertRaisesRegex(RuntimeError, 'signature'):
                package.install(self.source, self.destination)
        exchange.assert_not_called()
        self.assertEqual(self.installed_text(), 'old')

    def test_new_install_and_default_existing_system_location(self):
        shutil.rmtree(self.destination)
        with patch.object(package, 'command', self.command), patch.object(package, 'ensure_stopped'):
            self.assertIsNone(package.install(self.source, self.destination))
        self.assertEqual(self.installed_text(), 'new')
        home = self.root / 'home'
        self.bundle(home / 'Applications/TypeTune.app', 'home')
        self.assertEqual(package.default_destination(home, self.destination.parent), self.destination)
        shutil.rmtree(self.destination)
        self.assertEqual(package.default_destination(home, self.destination.parent), home / 'Applications/TypeTune.app')

    def test_refuses_wrong_app_and_symlink(self):
        wrong = self.root / 'Applications/Unrelated.app'
        self.destination.rename(wrong)
        self.destination.symlink_to(wrong, target_is_directory=True)
        with self.assertRaisesRegex(RuntimeError, 'non-symlink'):
            package.install(self.source, self.destination)
        self.assertEqual((wrong / 'Contents/MacOS/TypeTune').read_text(), 'old')

    @unittest.skipUnless(sys.platform == 'darwin', 'native directory exchange requires macOS')
    def test_native_atomic_directory_exchange_in_temporary_bundles(self):
        package.exchange(self.source, self.destination)
        self.assertEqual(self.installed_text(), 'new')
        self.assertEqual((self.source / 'Contents/MacOS/TypeTune').read_text(), 'old')

    def test_rollback_failure_retains_both_bundles(self):
        verifications = 0
        exchanges = 0
        def command(arguments, **kwargs):
            nonlocal verifications
            if arguments[0] == 'codesign' and arguments[-1] == str(self.destination):
                verifications += 1
                if verifications == 2:
                    raise RuntimeError('post-install signature failed')
            self.command(arguments, **kwargs)
        def exchange(left, right):
            nonlocal exchanges
            exchanges += 1
            if exchanges == 2:
                raise OSError('rollback exchange failed')
            self.exchange(left, right)
        with patch.object(package, 'command', command), patch.object(package, 'ensure_stopped'), \
                patch.object(package, 'exchange', exchange):
            with self.assertRaisesRegex(OSError, 'rollback exchange failed'):
                package.install(self.source, self.destination)
        self.assertEqual(self.installed_text(), 'new')
        stages = list(self.destination.parent.glob('.TypeTune-install-*'))
        self.assertEqual(len(stages), 1)
        self.assertEqual((stages[0] / 'candidate/Contents/MacOS/TypeTune').read_text(), 'old')
        self.assertEqual(len(list((self.root / 'private-backups').glob('*.zip'))), 1)
        self.assertEqual(list(self.destination.parent.glob('*.app')), [self.destination])

    def test_archive_failure_keeps_original_and_never_swaps(self):
        def command(arguments, **kwargs):
            if arguments[:2] == ['ditto','-c']:
                raise RuntimeError('archive failed')
            self.command(arguments, **kwargs)
        with patch.object(package, 'command', command), patch.object(package, 'ensure_stopped'), \
                patch.object(package, 'exchange') as exchange:
            with self.assertRaisesRegex(RuntimeError, 'archive failed'):
                package.install(self.source, self.destination)
        exchange.assert_not_called()
        self.assertEqual(self.installed_text(), 'old')
        self.assertEqual(list(self.destination.parent.iterdir()), [self.destination])
        self.assertEqual(list((self.root / 'private-backups').iterdir()), [])

    def test_archive_content_mismatch_blocks_swap(self):
        def command(arguments, **kwargs):
            self.command(arguments, **kwargs)
            if arguments[:2] == ['ditto','-x']:
                (Path(arguments[-1]) / 'TypeTune.app/Contents/MacOS/TypeTune').write_text('wrong backup')
        with patch.object(package, 'command', command), patch.object(package, 'ensure_stopped'), \
                patch.object(package, 'exchange') as exchange:
            with self.assertRaisesRegex(RuntimeError, 'does not match'):
                package.install(self.source, self.destination)
        exchange.assert_not_called()
        self.assertEqual(self.installed_text(), 'old')
        self.assertEqual(list((self.root / 'private-backups').iterdir()), [])

    def test_publish_does_not_create_personal_rollback_archive(self):
        with patch.object(package, 'command', self.command), patch.object(package, 'exchange', self.exchange), \
                patch.object(package, 'archive_bundle') as archive:
            self.assertIsNone(package.install(self.source, self.destination, check_running=False))
        archive.assert_not_called()
        self.assertEqual(self.installed_text(), 'new')


class IdentityTests(unittest.TestCase):
    def test_source_digest_tracks_dirty_content_and_stamp_rejects_mid_build_edit(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            def git(*arguments):
                subprocess.run(['git', *arguments], cwd=root, check=True, stdout=subprocess.DEVNULL,
                               stderr=subprocess.DEVNULL)
            git('init')
            (root / 'source.swift').write_text('original')
            (root / '.gitignore').write_text('/dist/\n')
            git('add', '.')
            git('-c', 'user.name=Test', '-c', 'user.email=test@example.test', 'commit', '-m', 'initial')
            git('tag', 'v0.2.4')
            initial = package.source_identity(root)
            self.assertEqual(initial['version'], '0.2.4')
            self.assertFalse(initial['source_dirty'])
            (root / 'source.swift').write_text('changed')
            changed = package.source_identity(root)
            self.assertTrue(changed['source_dirty'])
            self.assertNotEqual(changed['source_digest'], initial['source_digest'])
            (root / 'new.swift').write_text('new source')
            self.assertNotEqual(package.source_identity(root)['source_digest'], changed['source_digest'])
            bundle = root / 'dist/TypeTune.app'
            (bundle / 'Contents').mkdir(parents=True)
            with self.assertRaisesRegex(RuntimeError, 'Sources changed'):
                package.stamp(root, bundle, initial)
            package.stamp(root, bundle, package.source_identity(root))
            with (bundle / 'Contents/Info.plist').open('rb') as stream:
                metadata = plistlib.load(stream)
            self.assertEqual(metadata['CFBundleShortVersionString'], '0.2.4')
            self.assertTrue(metadata['TypeTuneSourceDirty'])
            self.assertEqual(len(metadata['TypeTuneSourceDigest']), 64)

    def test_no_tags_uses_release_notes_in_shallow_checkout(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            subprocess.run(['git', 'init', '-q', str(root)], check=True)
            releases = root / 'docs/releases'
            releases.mkdir(parents=True)
            (releases / '0.2.4.md').write_text('release notes')
            (releases / '0.2.3.md').write_text('previous release')
            subprocess.run(['git', '-C', str(root), 'add', '.'], check=True)
            subprocess.run(['git', '-C', str(root), '-c', 'user.name=Test', '-c', 'user.email=test@example.test',
                            'commit', '-qm', 'source snapshot'], check=True)
            self.assertEqual(package.source_identity(root)['version'], '0.2.4')


class InstallationLockTests(unittest.TestCase):
    def test_excludes_new_app_start_and_releases_lock_after_error(self):
        with tempfile.TemporaryDirectory() as temporary:
            lock = Path(temporary) / 'instance.lock'
            with self.assertRaisesRegex(RuntimeError, 'simulated installation error'):
                with package.application_lock(lock):
                    with self.assertRaisesRegex(RuntimeError, 'instance lock'):
                        with package.application_lock(lock):
                            self.fail('a second observer/installer acquired the lock')
                    raise RuntimeError('simulated installation error')
            with package.application_lock(lock):
                self.assertEqual(lock.stat().st_mode & 0o777, 0o600)


if __name__ == '__main__':
    unittest.main()
