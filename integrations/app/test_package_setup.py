import contextlib,json,tempfile,unittest
from pathlib import Path
from unittest.mock import patch
import controller
from gi.repository import GLib

class Settings:
    def __init__(self):self.values={'enabled-extensions':['unrelated'],'disabled-extensions':[], 'sources':[('xkb','us'),('ibus','typetune-test'),('ibus','other-engine'),('xkb','ru')]}
    def get_value(self,key):return GLib.Variant('a(ss)',self.values[key])
    def set_value(self,key,value):self.values[key]=value.unpack()
    def get_strv(self,key):return self.values[key]
    def set_strv(self,key,value):self.values[key]=value

class Checks(unittest.TestCase):
    def test_migration_upgrade_and_unregister_preserve_user_preferences(self):
        with tempfile.TemporaryDirectory() as directory, contextlib.ExitStack() as stack:
            base=Path(directory);payload=base/'payload';state=base/'state';state.mkdir();payload.mkdir()
            (payload/'package.json').write_text(json.dumps(dict(version='1')))
            extension=payload/'gnome'/controller.UUID;extension.mkdir(parents=True);(extension/'metadata.json').write_text('{}')
            previous=dict(extension_was_enabled=False,extension_was_disabled=False,previous_component_path=None)
            (state/'installed.json').write_text(json.dumps(previous))
            config=base/'config';config.mkdir();settings=config/'settings.json';settings.write_text('{"user":"keep"}')
            for key,value in dict(PACKAGED=True,PACKAGE=payload,STATE=state,EXTENSION=base/'extension',COMPONENT=base/'ibus/component.xml',ENVIRONMENT=base/'env/typetune.conf',DESKTOP=base/'applications/typetune.desktop').items():stack.enter_context(patch.object(controller,key,value))
            controller.COMPONENT.parent.mkdir(parents=True);controller.COMPONENT.write_text('legacy component')
            controller.ENVIRONMENT.parent.mkdir(parents=True);controller.ENVIRONMENT.write_text('legacy environment')
            shell=Settings()
            stack.enter_context(patch.object(controller,'call',side_effect=GLib.Error('absent')))
            stack.enter_context(patch.object(controller.Gio.Settings,'new',return_value=shell))
            stack.enter_context(patch.object(controller.Gio.Settings,'sync'))
            commands=stack.enter_context(patch.object(controller.subprocess,'run'))
            stack.enter_context(patch.object(controller,'stop'));stack.enter_context(patch.object(controller,'stop_gui'))
            stack.enter_context(patch.object(controller.os,'getuid',return_value=1000))
            stack.enter_context(patch('app_settings.load',return_value=dict(autostart=False)))
            stack.enter_context(patch('app_settings.AUTOSTART',base/'autostart.desktop'))
            controller.configure_package()
            self.assertEqual(json.loads((state/'installed.json').read_text()),dict(previous,package_version='1'))
            self.assertFalse(controller.COMPONENT.exists());self.assertFalse(controller.ENVIRONMENT.exists())
            self.assertEqual(shell.values['sources'],[('xkb','us'),('ibus','other-engine'),('xkb','ru')])
            self.assertIn('package_launcher.py',controller.DESKTOP.read_text())
            (payload/'package.json').write_text(json.dumps(dict(version='2')))
            controller.configure_package()
            self.assertEqual(json.loads((state/'installed.json').read_text())['package_version'],'2')
            self.assertEqual(settings.read_text(),'{"user":"keep"}')
            controller.package_lifecycle(remove=True)
            self.assertFalse(state.exists());self.assertFalse(controller.EXTENSION.exists())
            self.assertTrue(payload.exists());self.assertEqual(settings.read_text(),'{"user":"keep"}')
            self.assertEqual(shell.get_strv('enabled-extensions'),['unrelated'])
            self.assertFalse(any(call.args[0][0] in ('cargo','ibus') for call in commands.call_args_list))
    def test_removal_does_not_touch_unrelated_checkout_install(self):
        with tempfile.TemporaryDirectory() as directory:
            state=Path(directory);(state/'installed.json').write_text('{}')
            with patch.object(controller,'STATE',state),patch.object(controller,'uninstall') as remove,patch.object(controller,'stop_gui') as stop:
                controller.package_lifecycle(remove=True)
                remove.assert_not_called();stop.assert_not_called()
