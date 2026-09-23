import io,json,tempfile,unittest
from pathlib import Path
from unittest.mock import patch
from gi.repository import GLib
import controller,preferences
from correction_feedback import Feedback

class Checks(unittest.TestCase):
    def test_no_write_without_accept_preserve_dictionary_and_ack(self):
        with tempfile.TemporaryDirectory() as directory:
            path=Path(directory)/'words.json'
            initial=preferences.save(dict(version=1,generation='0',words=['hello'],exclusions=['мир']),'0',path)
            feedback=Feedback()
            for _ in range(3):feedback.record('ghbdtn','привет')
            identifier=feedback.pending()[0]['id']
            original_load=preferences.load;original_save=preferences.save
            def call(name,path_,interface,method,params=None):
                if method=='GetSuggestions':return (json.dumps(feedback.pending()),)
                if method=='DismissSuggestion':feedback.dismiss(params.unpack()[0]);return (True,)
                if method=='ReloadWords':return (params.unpack()[0],)
                return (json.dumps(dict(words_generation=original_load(path)['generation'])),)
            class Connection:
                def call_sync(self,*args):return GLib.Variant('(b)',(True,))
            def resolve(action,id_=identifier):
                value=dict(id=id_,backend='compatibility',action=action)
                with patch.object(controller.sys,'stdin',io.StringIO(json.dumps(value))):return controller.suggestions('suggestions-resolve')
            with patch.object(controller,'call',side_effect=call),patch.object(controller.Gio,'bus_get_sync',return_value=Connection()),patch.object(preferences,'load',side_effect=lambda *args:original_load(path)),patch.object(preferences,'save',side_effect=lambda value,expected:original_save(value,expected,path)):
                self.assertEqual(original_load(path),initial)
                with self.assertRaises(ValueError):resolve('accept','stale')
                self.assertEqual(original_load(path),initial)
                result=resolve('accept');self.assertFalse(result['error'])
                self.assertEqual(original_load(path)['words'],['hello'])
                self.assertEqual(original_load(path)['exclusions'],['мир','привет'])
                self.assertEqual(feedback.pending(),[])
                for _ in range(3):feedback.record('nbgn.y','типтюн','word')
                new=feedback.pending()[0]['id']
                self.assertFalse(resolve('accept',new)['error'])
                self.assertEqual(original_load(path)['words'],['hello','типтюн'])
                self.assertEqual(original_load(path)['exclusions'],['мир','привет'])
                for _ in range(3):feedback.record('rfr','как')
                other=feedback.pending()[0]['id'];before=original_load(path)
                self.assertFalse(resolve('dismiss',other)['error'])
                self.assertEqual(original_load(path),before)
                self.assertEqual(feedback.pending(),[])

    def test_threshold_set_reads_stdin_validates_and_persists(self):
        import app_settings
        with tempfile.TemporaryDirectory() as directory:
            settings_path=Path(directory)/'settings.json'
            original_update=app_settings.update
            def update(changes,path=settings_path,apply=None):
                return original_update(changes,path,apply)
            with patch.object(controller,'active_runtime_control',return_value=None), \
                 patch.object(app_settings,'update',side_effect=update):
                with patch.object(controller.sys,'stdin',io.StringIO('5\n')):
                    result=controller.threshold_set()
                self.assertFalse(result['error'])
                self.assertEqual(app_settings.load(settings_path)['learn_threshold'],5)
            with patch.object(controller.sys,'stdin',io.StringIO('0\n')):
                with self.assertRaises(ValueError):controller.threshold_set()
            with patch.object(controller.sys,'stdin',io.StringIO('abc\n')):
                with self.assertRaises(ValueError):controller.threshold_set()
