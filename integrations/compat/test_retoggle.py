import unittest
from runtime import Runtime
from history import History
class RetoggleChecks(unittest.TestCase):
    def fixture(self):
        r=Runtime.__new__(Runtime)
        r.history=History();r.pending=7;r.phase='injecting';r.replacement='привет '
        r.revision=1;r.armed=None;r.send=lambda _:None
        return r
    def test_sent_replacement_becomes_inferred_word_for_next_double_shift(self):
        r=self.fixture()
        r.event(dict(kind='result',id=7,status='injected-unverified'))
        self.assertEqual(r.history.text,'привет ')
        result=None
        for value,t in [(1,0),(0,.05),(1,.12),(0,.17)]:
            result=r.history.event(dict(device=1,code=42,value=value,time=t),'ru')
        self.assertEqual(result,'manual')
        self.assertFalse(r.history.held)
    def test_failed_or_cancelled_output_never_restores_word(self):
        for status in ['rejected','indeterminate']:
            r=self.fixture();r.event(dict(kind='result',id=7,status=status))
            self.assertEqual(r.history.text,'')
        r=self.fixture();r.invalidate()
        r.event(dict(kind='result',id=7,status='injected-unverified'))
        self.assertEqual(r.history.text,'')
    def test_navigation_and_new_word_do_not_toggle_previous_word(self):
        r=self.fixture();r.event(dict(kind='result',id=7,status='injected-unverified'))
        r.history.event(dict(device=1,code=30,value=1,time=0),'ru')
        self.assertEqual(r.history.text,'ф')
        r.history.event(dict(device=1,code=105,value=1,time=.1),'ru')
        self.assertEqual(r.history.text,'')
if __name__=='__main__':unittest.main()
