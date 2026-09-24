import unittest
from runtime import context, Runtime
from history import History
class Checks(unittest.TestCase):
    def state(self):
        return dict(snapshot=dict(protocol=1,instance='fixture',generation=1,locked=False,shield_active=False,
            overview=False,external_source=False,user_session=True,window_backend='wayland',window=1,
            source_type='xkb',source_id='us',xkb_id='us',source_generation=1),options=['grp_led:scroll'],model='pc105+inet',modifiers=0,interaction_generation=1)
    def test_native_and_xwayland_are_explicit_but_context_unknown_is_not_success(self):
        for backend in ['wayland','x11']:
            s=self.state();s['snapshot']['window_backend']=backend
            self.assertEqual(context(s),('fixture',1,1))
        for key,value in [('locked',True),('window',0),('window_backend','unknown'),('source_type','ibus'),('xkb_id','us(dvorak)'),('user_session',None)]:
            s=self.state();s['snapshot'][key]=value;self.assertIsNone(context(s))
        self.assertIsNone(context({}))
    def test_remapping_caps_and_shortcut_modifiers_refuse(self):
        for key,value in [('options',['caps:swapescape']),('model','unknown'),('modifiers',2),('modifiers',4),('modifiers',128)]:
            s=self.state();s[key]=value;self.assertIsNone(context(s))
        s=self.state();s['modifiers']=1;self.assertIsNotNone(context(s)) # gesture tracks Shift
    def test_cancel_preserves_uncertainty_and_never_retries(self):
        from types import SimpleNamespace
        calls=[]
        runtime=SimpleNamespace(revision=1,history=History(),pending=1,phase='injecting',last='idle',send=calls.append)
        Runtime.invalidate(runtime)
        self.assertEqual(runtime.last,'indeterminate')
        self.assertIsNone(runtime.pending)
        self.assertEqual(calls,[{'op':'cancel'}])
        Runtime.invalidate(runtime)
        self.assertEqual(len(calls),1)
    def _runtime(self):
        from types import SimpleNamespace
        calls=[]
        runtime=SimpleNamespace(revision=1,history=History(),pending=None,phase=None,last='idle',
            send=calls.append,armed=None,replacement=None,feedback_edit=None,_skip_auto_once=False,
            _window_zero_since=None,value=None)
        runtime.invalidate=lambda: Runtime.invalidate(runtime)
        runtime.soft_invalidate=lambda: Runtime.soft_invalidate(runtime)
        runtime.layout_changed=lambda source: Runtime.layout_changed(runtime,source)
        runtime.history.text='ghb'
        return runtime,calls
    def test_interaction_only_keeps_history(self):
        r,_=self._runtime()
        old=self.state();new=self.state();new['interaction_generation']=2
        Runtime.reconcile(r,old,new)
        self.assertEqual(r.history.text,'ghb')
    def test_interaction_only_cancels_pending(self):
        r,calls=self._runtime();r.pending=3;r.phase='injecting'
        old=self.state();new=self.state();new['interaction_generation']=2
        Runtime.reconcile(r,old,new)
        self.assertIsNone(r.pending)
        self.assertEqual(r.history.text,'ghb')
        self.assertEqual(calls,[{'op':'cancel'}])
    def test_source_only_keeps_history_and_arms_skip(self):
        r,calls=self._runtime()
        class Rules:
            def call(self,value):calls.append(value)
        r.rules=Rules()
        old=self.state();new=self.state()
        new['snapshot']=dict(old['snapshot'],source_id='ru',xkb_id='ru',source_generation=2)
        Runtime.reconcile(r,old,new)
        self.assertEqual(r.history.text,'ghb')
        self.assertTrue(r._skip_auto_once)
        self.assertEqual(calls,[{'op':'layout_notice','source':'user','layout':'ru'}])
    def test_window_flicker_keeps_history(self):
        r,_=self._runtime()
        old=self.state();new=self.state();new['snapshot']=dict(old['snapshot'],window=0)
        Runtime.reconcile(r,old,new)
        self.assertEqual(r.history.text,'ghb')
        self.assertIsNotNone(r._window_zero_since)
    def test_window_change_is_hard(self):
        r,_=self._runtime()
        old=self.state();new=self.state();new['snapshot']=dict(old['snapshot'],window=2)
        Runtime.reconcile(r,old,new)
        self.assertEqual(r.history.text,'')
    def test_app_change_is_hard(self):
        r,_=self._runtime()
        old=self.state();old['app_id']='a.desktop';new=self.state();new['app_id']='b.desktop'
        Runtime.reconcile(r,old,new)
        self.assertEqual(r.history.text,'')
if __name__=='__main__':unittest.main()
