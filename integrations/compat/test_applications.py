"""Real compatibility planner/executor with controlled editor and fake source switch."""
import json
import unittest
from unittest.mock import patch
from types import SimpleNamespace
from gi.repository import GLib
from runtime import Runtime
from history import History, CODES, RU, US, UPPER_US
from rules import Rules
import application_rules
import test_context


class Checks(unittest.TestCase):
    def fixture(self, app='code.desktop'):
        r=Runtime.__new__(Runtime)
        r.history=History();r.history.text='ghbdtn '
        r.pending=None;r.revision=1;r.phase=None;r.automatic=True;r.action=0;r.seq=0
        r.armed=None;r.stats=dict(plans=0,invalidations=0);r.last='idle';r.rules=Rules()
        r.value=test_context.Checks().state();r.value['app_id']=app
        r.allowed=lambda:True;r.refresh=lambda done:done()
        editor=SimpleNamespace(text='prefix ghbdtn ',caret=14,held=set(),emits=0)
        callbacks=[]
        class Proxy:
            def call(self, method, params, flags, timeout, cancel, callback):
                callbacks.append(lambda:callback(self,None))
                target=json.loads(params.unpack()[0])['target']
                r.value['snapshot']['source_id']=target;r.value['snapshot']['xkb_id']=target
            def call_finish(self,result):return GLib.Variant('(s)',(json.dumps({'status':'requested'}),))
        r.proxy=Proxy()
        def send(value):
            if value['op']!='emit':return
            editor.emits+=1
            for code,down in value['keys']:
                if not down:editor.held.remove(code);continue
                self.assertNotIn(code,editor.held);editor.held.add(code)
                if code==42:continue
                if code==14:
                    editor.text=editor.text[:editor.caret-1]+editor.text[editor.caret:];editor.caret-=1
                else:
                    table=(RU.upper() if 42 in editor.held else RU) if r.value['snapshot']['source_id']=='ru' else (UPPER_US if 42 in editor.held else US)
                    char=' ' if code==57 else table[CODES.index(code)]
                    editor.text=editor.text[:editor.caret]+char+editor.text[editor.caret:];editor.caret+=1
        r.send=send
        return r,editor,callbacks

    def test_excluded_unknown_and_allowed_apps_manual_stays_available(self):
        config=dict(version=1,generation='fixture',excluded=['code.desktop'])
        with patch.object(application_rules,'CURRENT',config):
            for app in ['code.desktop',None,'browser.desktop']:
                r,editor,callbacks=self.fixture(app)
                r.prepare('auto',1)
                for callback in callbacks:callback()
                expected='prefix привет ' if app=='browser.desktop' else 'prefix ghbdtn '
                self.assertEqual((editor.text,editor.caret,editor.held),(expected,14,set()))
                if app!='browser.desktop':
                    self.assertEqual(callbacks,[]) # No source switching either.
                    r.prepare('manual',1)
                    for callback in callbacks:callback()
                    self.assertEqual((editor.text,editor.caret,editor.held),('prefix привет ',14,set()))

    def test_policy_or_identity_change_before_injection_preserves_source(self):
        for change in ['policy','identity','reload']:
            with patch.object(application_rules,'CURRENT',dict(version=1,generation='fixture',excluded=[])):
                r,editor,callbacks=self.fixture('browser.desktop')
                r.prepare('auto',1);self.assertEqual(len(callbacks),1)
                if change=='policy':application_rules.CURRENT['excluded']=['browser.desktop']
                elif change=='identity':r.value['app_id']='other.desktop'
                else:
                    class Invocation:
                        def return_value(self,_):pass
                    with patch.object(application_rules,'load',return_value=dict(version=1,generation='new',excluded=['browser.desktop'])):
                        r.method(None,None,None,None,'ReloadApplications',GLib.Variant('(s)',('new',)),Invocation())
                callbacks.pop()()
                self.assertEqual((editor.text,editor.caret,editor.held,editor.emits),('prefix ghbdtn ',14,set(),0))
                self.assertIsNone(r.pending)
