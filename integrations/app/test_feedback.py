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

class PersistenceChecks(unittest.TestCase):
    def setUp(self):
        import tempfile
        from pathlib import Path
        self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup)
        self.path=Path(self.tmp.name)/'feedback.json'

    def test_restart_preserves_counts_dismissals_and_proposals(self):
        first=Feedback(path=self.path)
        for _ in range(3):first.record('ghbdtn','привет')
        proposal=first.pending()[0]
        self.assertEqual(proposal['count'],3)
        second=Feedback(path=self.path)
        self.assertEqual(len(second.pending()),1)
        self.assertEqual(second.pending()[0]['word'],'привет')
        for _ in range(3):second.record('ghbdtn','привет')
        again=Feedback(path=self.path)
        self.assertEqual(len(again.pending()),1)
        self.assertEqual(again.pending()[0]['word'],'привет')
        again.dismiss(again.pending()[0]['id'])
        third=Feedback(path=self.path)
        self.assertEqual(third.pending(),[])
        for _ in range(5):third.record('ghbdtn','привет')
        self.assertEqual(third.pending(),[])
        self.assertIn(('exclusion','ghbdtn','привет'),third.dismissed)

    def test_corrupt_file_starts_empty_and_is_not_overwritten(self):
        self.path.write_text('{broken')
        feedback=Feedback(path=self.path)
        self.assertIsNone(feedback.path)
        self.assertTrue(feedback.error)
        feedback.record('ghbdtn','привет')
        self.assertEqual(self.path.read_text(),'{broken')
        self.assertEqual(feedback.pending(),[])

    def test_schedule_defers_flush_and_threshold_updates_proposals(self):
        scheduled=[]
        feedback=Feedback(path=self.path,schedule=scheduled.append)
        for _ in range(2):feedback.record('ghbdtn','привет')
        self.assertTrue(feedback.dirty)
        self.assertFalse(self.path.exists())
        self.assertEqual(scheduled,[feedback.flush])
        feedback.flush()
        self.assertFalse(feedback.dirty)
        self.assertTrue(self.path.exists())
        reloaded=Feedback(path=self.path)
        self.assertEqual(reloaded.threshold,3)
        self.assertEqual(reloaded.pending(),[])
        reloaded.set_threshold(2)
        self.assertEqual(len(reloaded.pending()),1)
        reloaded.set_threshold(3)
        self.assertEqual(reloaded.pending(),[])
        with self.assertRaises(ValueError):reloaded.set_threshold(0)
        with self.assertRaises(ValueError):reloaded.set_threshold(11)

    def test_words_not_written_into_logs_or_status(self):
        import io,logging
        stream=io.StringIO()
        handler=logging.StreamHandler(stream);logging.getLogger().addHandler(handler)
        try:
            feedback=Feedback(path=self.path)
            for _ in range(3):feedback.record('ghbdtn','привет')
            feedback.flush()
            _=feedback.pending();_=feedback.snapshot()
        finally:
            logging.getLogger().removeHandler(handler)
        self.assertNotIn('привет',stream.getvalue())
        self.assertNotIn('ghbdtn',stream.getvalue())
