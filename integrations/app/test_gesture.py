import unittest
from gesture import DoubleShift

class Tests(unittest.TestCase):
    def test_two_complete_same_shift_taps(self):
        g=DoubleShift()
        for key, up, t, expected in [(1,False,0,False),(1,True,.05,False),(1,False,.15,False),(1,True,.2,True)]:
            self.assertEqual(g.edge(key,up,t),expected)
        self.assertFalse(g.edge(1,True,.21))

    def test_hold_repeat_other_shift_and_intervening_event(self):
        for trace in [ [(1,False,0),(1,True,.3),(1,False,.35),(1,True,.4)],
                       [(1,False,0),(1,False,.02),(1,True,.05),(1,False,.1),(1,True,.15)],
                       [(1,False,0),(1,True,.05),(2,False,.1),(2,True,.15)],
                       [(1,False,0),(2,False,.01),(2,True,.02),(1,True,.03)],
                       [(1,False,0),(1,True,.05),(1,False,.5),(1,True,.55)]]:
            g=DoubleShift()
            for event in trace:self.assertFalse(g.edge(*event))
        g=DoubleShift();g.edge(1,False,0);g.edge(1,True,.05);g.reset()
        self.assertFalse(g.edge(1,False,.1));self.assertFalse(g.edge(1,True,.15))

    def test_future_or_stale_clock_cannot_trigger(self):
        g=DoubleShift();g.edge(1,False,1)
        self.assertFalse(g.edge(1,True,0))

if __name__=='__main__':unittest.main()
