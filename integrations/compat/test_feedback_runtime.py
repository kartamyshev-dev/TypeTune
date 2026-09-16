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
