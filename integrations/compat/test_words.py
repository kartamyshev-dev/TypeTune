import sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'app'))
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
                # Built-in tech vocab still auto-corrects without user words (D2).
                self.assertEqual(rules.suggest('rkfdbfnehs ',True)['replacement'],'клавиатуры ')
                self.assertEqual(rules.suggest('ghbdtn ',True)['replacement'],'привет ')
            with patch.object(preferences,'ERROR','invalid dictionary'):
                self.assertEqual(rules.suggest('ghbdtn ',True)['status'],'ignored')
                self.assertEqual(rules.suggest('ghbdtn ',False)['replacement'],'привет ')

    def test_settings_policy_change_reconfigures_without_dictionary_generation(self):
        rules=Rules()
        words=dict(version=1,generation='fixture-words',words=['клавиатуры'],exclusions=[])
        settings=dict(generation='s1',switch_only_last_word=True,dont_switch_words=False,
                      dont_correct_after_layout_change=True)
        with patch.object(preferences,'CURRENT',words), \
             patch('app_settings.load',return_value=dict(settings)):
            self.assertEqual(rules.suggest('rkfdbfnehs ',True)['replacement'],'клавиатуры ')
            # dont_switch_words switches layout only on automatic; manual still rewrites.
            settings=dict(settings,generation='s2',switch_only_last_word=False,dont_switch_words=True)
            with patch('app_settings.load',return_value=dict(settings)):
                auto=rules.suggest('rkfdbfnehs ',True)
                self.assertEqual(auto['status'],'inferred')
                self.assertTrue(auto.get('layout_only'))
                self.assertEqual(rules.suggest('rkfdbfnehs ',False)['replacement'],'клавиатуры ')
