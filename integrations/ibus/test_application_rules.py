import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
import application_rules as rules


class Checks(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup)
        self.path=Path(self.tmp.name)/'applications.json'

    def test_save_reopen_normalize_conflict_and_invalid(self):
        default=rules.load(self.path)
        saved=rules.save(dict(default,excluded=['code.desktop','code.desktop']), '0',self.path)
        self.assertEqual(rules.load(self.path),saved)
        self.assertEqual(saved['excluded'],['code.desktop'])
        with self.assertRaises(ValueError):rules.save(default,'0',self.path)
        for entry in ['window title','/tmp/code.desktop','code.desktop\n',None]:
            with self.assertRaises(ValueError):rules.save(dict(saved,excluded=[entry]),saved['generation'],self.path)
        self.assertEqual(rules.load(self.path),saved)

    def test_failed_write_and_corrupt_file_are_not_overwritten(self):
        saved=rules.save(rules.load(self.path),'0',self.path)
        with patch('app_settings.atomic',side_effect=OSError('fixture disk full')):
            with self.assertRaises(OSError):rules.save(dict(saved,excluded=['code.desktop']),saved['generation'],self.path)
        self.assertEqual(rules.load(self.path),saved)
        self.path.write_text('{broken')
        with self.assertRaises(ValueError):rules.save(saved,saved['generation'],self.path)
        self.assertEqual(self.path.read_text(),'{broken')

    def test_exact_identity_and_unknown_with_nonempty_list(self):
        with patch.object(rules,'CURRENT',dict(version=1,generation='test',excluded=['code.desktop'])):
            self.assertEqual(rules.reason('code.desktop'),'excluded-application')
            self.assertTrue(rules.allows('other-code.desktop'))
            for identity in [None,'','code','/code.desktop']:
                self.assertEqual(rules.reason(identity),'unknown-application')
        with patch.object(rules,'CURRENT',dict(version=1,generation='0',excluded=[])):
            self.assertTrue(rules.allows(None)) # Existing explicitly opted-in compatibility policy.
        with patch.object(rules,'ERROR','broken config'):
            self.assertFalse(rules.allows('browser.desktop'))

    def test_reload_failure_keeps_previous_generation_startup_failure_disables(self):
        with patch.object(rules,'CURRENT',dict(version=1,generation='old',excluded=['code.desktop'])), patch.object(rules,'ERROR',None):
            with patch.object(rules,'load',return_value=dict(version=1,generation='new',excluded=[])):
                with self.assertRaises(ValueError):rules.reload('wrong')
                self.assertEqual(rules.CURRENT['generation'],'old')
                self.assertEqual(rules.reload('new'),'new')
                self.assertTrue(rules.allows('code.desktop'))
            with patch.object(rules,'load',side_effect=ValueError('broken')):rules.initialize()
            self.assertEqual(rules.reason('browser.desktop'),'config-error')
