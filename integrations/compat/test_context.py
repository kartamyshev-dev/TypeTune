import unittest
from runtime import context, Runtime
from history import History
class Checks(unittest.TestCase):
    def state(self):
        return dict(snapshot=dict(protocol=1,instance='fixture',generation=1,locked=False,shield_active=False,
            overview=False,external_source=False,user_session=True,window_backend='wayland',window=1,
            source_type='xkb',source_id='us',xkb_id='us'),options=['grp_led:scroll'],model='pc105+inet',modifiers=0,interaction_generation=1)
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
if __name__=='__main__':unittest.main()
