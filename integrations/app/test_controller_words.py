import contextlib
import io
import json
import unittest
from unittest.mock import patch
from gi.repository import GLib
import controller


class Checks(unittest.TestCase):
    def run_save(self, owner):
        document=dict(version=1,generation='new',words=['hello'],exclusions=[])
        class Connection:
            def call_sync(self,*args): return GLib.Variant('(b)',(owner,))
        output=io.StringIO()
        with patch('preferences.save',return_value=document), patch.object(controller.sys,'stdin',io.StringIO(json.dumps(document))), patch.object(controller.Gio,'bus_get_sync',return_value=Connection()), patch.object(controller,'call',side_effect=RuntimeError('unavailable')),contextlib.redirect_stdout(output):
            controller.user_words('words-save')
        return json.loads(output.getvalue())

    def test_saved_but_failed_apply_is_not_success(self):
        result=self.run_save(True)
        self.assertTrue(result['error'])
        self.assertFalse(result['applied'])
        self.assertEqual(result['document']['generation'],'new')
        self.assertIn('не применено',result['message'])

    def test_stopped_runtime_defers_apply_explicitly(self):
        result=self.run_save(False)
        self.assertFalse(result['error'])
        self.assertFalse(result['applied'])
        self.assertIn('при запуске',result['message'])

    def test_applications_apply_requires_matching_generation(self):
        for mode in ('stopped','success','mismatch','old-runtime'):
            document=dict(version=1,generation='new',excluded=['code.desktop'])
            class Connection:
                def call_sync(self,*args): return GLib.Variant('(b)',(mode!='stopped',))
            calls=[]
            def call(name,path,interface,method,parameters=None):
                calls.append(method)
                if mode=='old-runtime':raise RuntimeError('unknown method')
                if method=='ReloadApplications':return ('new',)
                return (json.dumps(dict(applications_generation='new' if mode=='success' else 'old')),)
            output=io.StringIO()
            with patch('application_rules.save',return_value=document), patch.object(controller.sys,'stdin',io.StringIO(json.dumps(document))), patch.object(controller.Gio,'bus_get_sync',return_value=Connection()), patch.object(controller,'call',side_effect=call),contextlib.redirect_stdout(output):
                controller.user_words('apps-save')
            result=json.loads(output.getvalue())
            self.assertEqual(result['document'],document)
            self.assertEqual(result['applied'],mode=='success')
            self.assertEqual(result['error'],mode in ('mismatch','old-runtime'))
            if mode!='stopped':self.assertIn('ReloadApplications',calls)
