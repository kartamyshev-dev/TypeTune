import sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'ibus'))
import unittest
from unittest.mock import patch
from rules import Rules
import preferences


class Checks(unittest.TestCase):
    def test_generation_change_configures_engine_and_manual_ignores_exclusion(self):
        rules=Rules()
        value=dict(version=1,generation='fixture1',words=['клавиатуры'],exclusions=['привет'])
        with patch.object(preferences,'CURRENT',value):
            self.assertEqual(rules.suggest('rkfdbfnehs ',True)['replacement'],'клавиатуры ')
            self.assertEqual(rules.suggest('ghbdtn ',True)['status'],'ignored')
            self.assertEqual(rules.suggest('ghbdtn ',False)['replacement'],'привет ')
            with patch.object(preferences,'CURRENT',dict(value,generation='fixture2',words=[],exclusions=[])):
                self.assertEqual(rules.suggest('rkfdbfnehs ',True)['status'],'ignored')
                self.assertEqual(rules.suggest('ghbdtn ',True)['replacement'],'привет ')
            with patch.object(preferences,'ERROR','invalid dictionary'):
                self.assertEqual(rules.suggest('ghbdtn ',True)['status'],'ignored')
                self.assertEqual(rules.suggest('ghbdtn ',False)['replacement'],'привет ')
