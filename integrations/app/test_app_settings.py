import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
import app_settings as settings
import controller


class Checks(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup)
        self.root=Path(self.tmp.name)
        self.path=self.root/'settings.json'
        self.entry=self.root/'autostart/test.desktop'
        self.controller=self.root/'installed app/controller.py'
        self.controller.parent.mkdir();self.controller.write_text('# fixture')

    def test_defaults_and_field_updates_preserve_each_other(self):
        self.assertFalse(settings.load(self.path)['autostart'])
        settings.update({'mode':'compatibility'},self.path)
        settings.update({'automatic':False},self.path)
        self.assertEqual(settings.load(self.path),dict(version=1,mode='compatibility',automatic=False,autostart=False))

    def test_autostart_enable_disable_and_real_desktop_parser(self):
        from gi.repository import Gio
        settings.set_autostart(True,self.controller,self.path,self.entry)
        app=Gio.DesktopAppInfo.new_from_filename(str(self.entry))
        self.assertIsNotNone(app)
        self.assertIn('autostart',app.get_commandline())
        self.assertTrue(settings.load(self.path)['autostart'])
        settings.set_autostart(False,self.controller,self.path,self.entry)
        self.assertFalse(self.entry.exists())
        self.assertFalse(settings.load(self.path)['autostart'])

    def test_write_failure_does_not_leave_new_autostart_launcher(self):
        original=settings.atomic
        def fail_settings(path,text):
            if path==self.path:raise OSError('fixture failure')
            original(path,text)
        with patch.object(settings,'atomic',side_effect=fail_settings):
            with self.assertRaises(OSError):settings.set_autostart(True,self.controller,self.path,self.entry)
        self.assertFalse(self.entry.exists())
        self.assertFalse(settings.load(self.path)['autostart'])

    def test_corrupt_and_invalid_settings_not_silently_overwritten(self):
        self.path.write_text('{broken')
        with self.assertRaises(ValueError):settings.update({'automatic':False},self.path)
        self.assertEqual(self.path.read_text(),'{broken')
        with self.assertRaises(ValueError):settings.update({'automatic':1},self.path)

    def test_restore_automatic_reads_saved_value(self):
        calls=[]
        def runtime(method,enabled):calls.append((method,enabled));return enabled
        with patch.object(settings,'load',return_value=dict(settings.DEFAULT,automatic=False)):
            controller.apply_saved_automatic(runtime)
        self.assertEqual(calls,[('SetAutomatic',False)])

    def test_login_disabled_and_existing_runtime_do_not_start_or_resume(self):
        with patch.dict(controller.os.environ,{'XDG_RUNTIME_DIR':str(self.root)}),patch.object(settings,'load',return_value=dict(settings.DEFAULT)),patch.object(controller,'compat_start') as start:
            self.assertEqual(controller.login_start(),0)
            start.assert_not_called()
        snapshot=dict(locked=False,shield_active=False,overview=False,user_session=True)
        with patch.dict(controller.os.environ,{'XDG_RUNTIME_DIR':str(self.root)}),patch.object(settings,'load',return_value=dict(settings.DEFAULT,autostart=True)),patch.object(controller,'bridge',return_value={'snapshot':snapshot}),patch.object(controller,'active_runtime_control',return_value=object()),patch.object(controller,'compat_start') as start,patch.object(controller.subprocess,'Popen'):
            self.assertEqual(controller.login_start(),0)
            start.assert_not_called()

    def test_login_restores_selected_mode_and_rechecks_opt_in(self):
        snapshot=dict(locked=False,shield_active=False,overview=False,user_session=True)
        with patch.dict(controller.os.environ,{'XDG_RUNTIME_DIR':str(self.root)}),patch.object(settings,'load',return_value=dict(settings.DEFAULT,autostart=True,mode='ibus')),patch.object(controller,'bridge',return_value={'snapshot':snapshot}),patch.object(controller,'active_runtime_control',return_value=None),patch.object(controller,'compat_start') as start,patch.object(controller.subprocess,'Popen'):
            self.assertEqual(controller.login_start(),0)
            start.assert_called_once()
        with patch.dict(controller.os.environ,{'XDG_RUNTIME_DIR':str(self.root)}),patch.object(settings,'load',side_effect=[dict(settings.DEFAULT,autostart=True),dict(settings.DEFAULT)]),patch.object(controller,'bridge',return_value={'snapshot':dict(snapshot,locked=True)}),patch.object(controller.time,'sleep'),patch.object(controller,'compat_start') as start:
            self.assertEqual(controller.login_start(),0)
            start.assert_not_called()

    def test_legacy_ibus_settings_migrate_without_losing_choices(self):
        self.path.write_text('{"version":1,"mode":"ibus","automatic":false,"autostart":true}')
        self.assertEqual(settings.load(self.path),dict(version=1,mode='compatibility',automatic=False,autostart=True))
        with self.assertRaises(ValueError):settings.update({'mode':'ibus'},self.path)
