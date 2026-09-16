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
