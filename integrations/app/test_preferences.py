import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
import preferences as p


class Tests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup)
        self.path=Path(self.tmp.name)/'words.json'

    def test_save_reload_normalize_and_stale_generation(self):
        original=p.load(self.path)
        value=dict(original, words=[' Клавиатуры ','КЛАВИАТУРЫ'],exclusions=['Привет'])
        saved=p.save(value,'0',self.path)
        self.assertEqual(p.load(self.path),saved)
        self.assertEqual(saved['words'],['клавиатуры'])
        self.assertEqual(saved['exclusions'],['привет'])
        self.assertNotEqual(saved['generation'],'0')
        with self.assertRaises(ValueError):p.save(value,'0',self.path)
        self.assertEqual(p.load(self.path),saved)

    def test_invalid_and_write_failure_preserve_previous_file(self):
        original=p.save(p.load(self.path),'0',self.path)
        with self.assertRaises(ValueError):p.save(dict(original,words=['привеt']),original['generation'],self.path)
        with patch('preferences.os.replace',side_effect=OSError('disk failure')):
            with self.assertRaises(OSError):p.save(dict(original,words=['hello']),original['generation'],self.path)
        self.assertEqual(p.load(self.path),original)
        self.assertEqual(sorted(x.name for x in self.path.parent.iterdir()),['words.json','words.lock'])

    def test_corrupt_file_not_silently_replaced_and_limits(self):
        self.path.write_text('{invalid')
        with self.assertRaises(ValueError):p.load(self.path)
        with self.assertRaises(ValueError):p.save(dict(version=1,generation='0',words=[],exclusions=[]),'0',self.path)
        self.assertEqual(self.path.read_text(),'{invalid')
        for words in [['a'],['with space'],['hello']*501]:
            with self.assertRaises(ValueError):p.validate(dict(version=1,generation='0',words=words,exclusions=[]))

    def test_failed_runtime_reload_keeps_last_good_generation(self):
        previous=p.CURRENT
        try:
            p.CURRENT=dict(version=1,generation='old',words=['hello'],exclusions=[])
            with patch('preferences.load',return_value=dict(version=1,generation='new',words=[],exclusions=[])):
                with self.assertRaises(ValueError):p.reload('wrong')
            self.assertEqual(p.CURRENT['generation'],'old')
        finally:p.CURRENT=previous
