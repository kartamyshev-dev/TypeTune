"""Actual evdev timing is independent of how long a key stays down."""
import unittest
from unittest.mock import patch
from runtime import Runtime
from history import History
class TriggerChecks(unittest.TestCase):
    def fixture(self):
        r=Runtime.__new__(Runtime)
        r.seq=0;r.revision=0;r.pending=None;r.stand=True;r.enabled=True
        r.automatic=True;r.history=History();r.fresh=0;r.value={'snapshot':{'source_id':'us'}}
        r.allowed=lambda:True;r.armed=None;r.now=lambda:0;r.started=0
        r.stats=dict(keys_seen=0,stale_events=0,auto_triggers=0,manual_triggers=0,plans=0,invalidations=0)
        calls=[]
        r.prepare=lambda trigger,revision:calls.append((trigger,revision,len(r.history.held)))
        return r,calls
    def test_space_waits_for_release_instead_of_dropping_at_60ms(self):
        r,calls=self.fixture();timers=[]
        def edge(code,value,t):r.event(dict(kind='key',seq=1,device=1,code=code,value=value,time=t))
        with patch('runtime.GLib.timeout_add',side_effect=lambda ms,fn:timers.append(fn)):
            edge(34,1,0);edge(34,0,.05)
            edge(57,1,.1)
            for callback in list(timers):callback()
            self.assertEqual(calls,[], 'must not prepare while Space is held')
            timers.clear()
            edge(57,0,.22) # ordinary 120 ms hold
            for callback in list(timers):callback()
        self.assertEqual(calls,[('auto',2,0)])
    def test_new_key_cancels_armed_space(self):
        r,calls=self.fixture();timers=[]
        with patch('runtime.GLib.timeout_add',side_effect=lambda ms,fn:timers.append(fn)):
            for code,value,t in [(34,1,0),(34,0,.02),(57,1,.04),(30,1,.06),(57,0,.08),(30,0,.1)]:
                r.event(dict(kind='key',seq=1,device=1,code=code,value=value,time=t))
            for callback in timers:callback()
        self.assertEqual(calls,[])
if __name__=='__main__':unittest.main()
