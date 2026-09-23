import unittest
import test_applications
from correction_feedback import Feedback,Tracker

class Checks(unittest.TestCase):
    def test_three_independent_auto_undo_edits_and_no_double_count(self):
        r,editor,callbacks=test_applications.Checks().fixture('browser.desktop')
        r.feedback=Feedback();r.feedback_tracker=Tracker(r.feedback,lambda:0)
        def edit(kind):
            r.prepare(kind,r.revision)
            self.assertEqual(len(callbacks),1)
            callbacks.pop()()
            r.event(dict(kind='result',id=r.pending,status='injected-unverified'))
            self.assertFalse(editor.held)
            self.assertEqual(editor.caret,14)
        for i in range(3):
            r.invalidate();r.history.text='ghbdtn '
            editor.text='prefix ghbdtn ';editor.caret=14
            r.value['snapshot'].update(source_id='us',xkb_id='us')
            edit('auto');self.assertEqual(editor.text,'prefix привет ')
            edit('manual');self.assertEqual(editor.text,'prefix ghbdtn ')
            edit('manual');edit('manual')
            self.assertEqual(len(r.feedback.pending()),int(i==2))
        self.assertEqual(r.feedback.pending()[0]['word'],'привет')
    def test_failed_output_and_invalidated_context_never_count(self):
        r,editor,callbacks=test_applications.Checks().fixture('browser.desktop')
        r.feedback=Feedback();r.feedback_tracker=Tracker(r.feedback,lambda:0)
        for _ in range(4):
            r.history.text='ghbdtn '
            r.prepare('auto',r.revision);callbacks.pop()()
            r.event(dict(kind='result',id=r.pending,status='indeterminate'))
            self.assertIsNone(r.feedback_tracker.last)
            r.feedback_tracker.completed('auto','ghbdtn ','привет ')
            r.invalidate();r.feedback_tracker.completed('manual','привет ','ghbdtn ')
        self.assertEqual(r.feedback.pending(),[])

    def test_retained_manual_word_then_dictionary_enables_real_edit(self):
        import time,preferences
        from unittest.mock import patch
        config=dict(version=1,generation='learn-test',words=[],exclusions=[])
        with patch.object(preferences,'CURRENT',config):
            r,editor,callbacks=test_applications.Checks().fixture('browser.desktop')
            r.feedback=Feedback();r.feedback_tracker=Tracker(r.feedback,lambda:0)
            r.now=lambda:0;r.started=0;r.stand=True;r.enabled=True;r.fresh=time.monotonic()
            r.stats.update(keys_seen=0,manual_triggers=0,auto_triggers=0)
            for i in range(3):
                r.invalidate();r.history.text='nbgn.y '
                editor.text='prefix nbgn.y ';editor.caret=14
                r.value['snapshot'].update(source_id='us',xkb_id='us')
                r.prepare('auto',r.revision)
                self.assertEqual(r.last,'no-candidate');self.assertEqual(editor.text,'prefix nbgn.y ')
                r.prepare('manual',r.revision);callbacks.pop()()
                r.event(dict(kind='result',id=r.pending,status='injected-unverified'))
                self.assertEqual((editor.text,editor.caret,editor.held),('prefix типтюн ',14,set()))
                self.assertEqual(len(r.feedback.pending()),int(i==2))
                # A normal next letter must not count this occurrence twice.
                r.event(dict(kind='key',code=30,value=1,device=1,time=i,seq=i+1))
                self.assertEqual(len(r.feedback.pending()),int(i==2))
            proposal=r.feedback.pending()[0]
            self.assertEqual((proposal['word'],proposal['kind']),('типтюн','word'))
            config['words']=['типтюн'];config['generation']='accepted'
            r.invalidate();r.history.text='nbgn.y ';editor.text='prefix nbgn.y ';editor.caret=14
            r.prepare('auto',r.revision);callbacks.pop()()
            r.event(dict(kind='result',id=r.pending,status='injected-unverified'))
            self.assertEqual((editor.text,editor.caret,editor.held),('prefix типтюн ',14,set()))

    def test_learning_probe_preserves_rules_and_respects_existing_protections(self):
        from correction_feedback import learnable
        from rules import Rules
        from unittest.mock import patch
        import preferences
        config=dict(version=1,generation='probe-test',words=[],exclusions=[])
        with patch.object(preferences,'CURRENT',config):
            r=Rules()
            self.assertTrue(learnable(r.call,'nbgn.y ','типтюн '))
            self.assertEqual(r.suggest('nbgn.y ',True)['status'],'ignored')
            self.assertFalse(learnable(r.call,'ghbdtn ','привет '))
            self.assertFalse(learnable(r.call,'hello ','руддщ '))
            config['exclusions']=['типтюн']
            self.assertFalse(learnable(r.call,'nbgn.y ','типтюн '))
            config['exclusions']=[];config['words']=['nbgn']
            self.assertFalse(learnable(r.call,'nbgn ','типт '))
