import unittest
from correction_feedback import Feedback, Tracker

class Checks(unittest.TestCase):
    def setUp(self):
        self.time=0; self.feedback=Feedback();self.tracker=Tracker(self.feedback,lambda:self.time)
    def correction(self):self.tracker.completed('auto','ghbdtn ','привет ')
    def undo(self):self.tracker.completed('manual','привет ','ghbdtn ')
    def test_three_distinct_corrections_only(self):
        self.undo();self.assertEqual(self.feedback.pending(),[])
        for i in range(3):
            self.correction();self.undo()
            self.tracker.completed('manual','ghbdtn ','привет ');self.undo()
            self.assertEqual(len(self.feedback.pending()),int(i==2))
        proposal=self.feedback.pending()[0]
        self.assertEqual(proposal['word'],'привет')
        self.feedback.dismiss(proposal['id'])
        for _ in range(4):self.correction();self.undo()
        self.assertEqual(self.feedback.pending(),[])
    def test_context_change_timeout_and_wrong_inverse_never_count(self):
        for _ in range(4):
            self.correction();self.tracker.reset();self.undo()
            self.correction();self.time+=11;self.undo()
            self.correction();self.tracker.completed('manual','другое ','lheujt ')
        self.assertEqual(self.feedback.pending(),[])
    def test_bounded_memory_and_reject_stale_id(self):
        with self.assertRaises(ValueError):self.feedback.dismiss('stale')
        for n in range(300):self.feedback.record('word'+str(n),'привет')
        self.assertLessEqual(len(self.feedback.counts),64)

class LearningChecks(unittest.TestCase):
    def test_three_retained_manual_corrections(self):
        f=Feedback();t=Tracker(f,lambda:0)
        for i in range(3):
            t.completed('manual','ntcnjdcrbq','тестовский',True)
            self.assertEqual(len(f.pending()),0)
            t.advance(True)
            self.assertEqual(len(f.pending()),int(i==2))
        self.assertEqual(f.pending()[0]['kind'],'word')
    def test_reversal_context_loss_and_typing_inside_word_do_not_teach(self):
        f=Feedback();t=Tracker(f,lambda:0)
        for _ in range(4):
            t.completed('manual','ntcnjdcrbq','тестовский',True)
            t.completed('manual','тестовский','ntcnjdcrbq',True)
            t.completed('manual','ntcnjdcrbq','тестовский',True)
            t.advance(True)
            t.completed('manual','ntcnjdcrbq','тестовский',True);t.reset()
            t.completed('manual','ntcnjdcrbq','тестовский',True);t.advance(False)
        self.assertEqual(f.pending(),[])

    def test_cannot_collect_after_dismiss_limit(self):
        f=Feedback();t=Tracker(f,lambda:0)
        f.dismissed=set(range(64))
        for _ in range(3):
            t.completed('manual','nbgn.y','типтюн',True);t.advance(True)
        self.assertEqual(f.pending(),[])

    def test_space_before_manual_counts_immediately_and_repeat_withdraws(self):
        f=Feedback();t=Tracker(f,lambda:0)
        for i in range(3):
            t.reset()
            t.completed('manual','пшерги ','github ',True)
            self.assertEqual(len(f.pending()),int(i==2))
        identifier=f.pending()[0]['id']
        t.completed('manual','github ','пшерги ',False)
        self.assertEqual(f.pending(),[])
        with self.assertRaises(ValueError):f.dismiss(identifier)
        t.completed('manual','пшерги ','github ',True)
        self.assertEqual(f.pending(),[])
        t.advance(True)
        t.completed('manual','пшерги ','github ',True)
        self.assertEqual(len(f.pending()),1)

    def test_next_typing_does_not_double_count_preceding_space(self):
        f=Feedback();t=Tracker(f,lambda:0)
        for _ in range(2):
            t.completed('manual','пшерги ','github ',True)
            t.advance(False)
        self.assertEqual(f.pending(),[])
        t.completed('manual','пшерги ','github ',True)
        self.assertEqual(len(f.pending()),1)
