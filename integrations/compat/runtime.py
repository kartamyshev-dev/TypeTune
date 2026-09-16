#!/usr/bin/python3
"""Explicit opt-in compatibility runtime. History and output are unverified."""
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import time
import gi
from gi.repository import Gio, GLib
HERE=Path(__file__).resolve().parent
sys.path.insert(0,str(HERE.parent/'app'))
sys.path.insert(0,str(HERE.parent))
from history import History, key_plan, CODES
from rules import Rules
import preferences
import app_settings
import application_rules
import correction_feedback
PATH='/org/typetune/Session1'
IFACE='org.typetune.Session1'


def context(value):
    s=value.get('snapshot',{})
    if (s.get('protocol')!=1 or any(s.get(k) is not False for k in ('locked','shield_active','overview','external_source'))
        or s.get('user_session') is not True or s.get('window_backend') not in ('wayland','x11')
        or type(s.get('window')) is not int or s['window']<=0
        or not isinstance(s.get('instance'),str) or not s['instance'] or type(s.get('generation')) is not int
        or s.get('source_type')!='xkb' or s.get('source_id') not in ('us','ru') or s.get('xkb_id')!=s.get('source_id')
        or not isinstance(value.get('options'),list) or any(option not in ('grp_led:scroll','grp_led:num','grp_led:caps') for option in value['options'])
        or value.get('model') not in ('','pc105','pc105+inet')
        or type(value.get('modifiers')) is not int or value['modifiers'] & ~17  # Shift is tracked independently; NumLock is harmless.
        or type(value.get('interaction_generation')) is not int):
        return None
    return (s['instance'],s['window'],value['interaction_generation'])


class Runtime:
    def __init__(self,stand=False):
        preferences.initialize()
        application_rules.initialize()
        self.feedback=correction_feedback.Feedback()
        self.feedback_tracker=correction_feedback.Tracker(self.feedback)
        self.feedback_edit=None
        self.loop=GLib.MainLoop(); self.history=History();self.rules=Rules()
        self.seq=0;self.revision=0;self.action=0;self.pending=None;self.phase=None
        self.armed=None;self.replacement=None;self.now=time.monotonic
        self.stats=dict(keys_seen=0,stale_events=0,auto_triggers=0,manual_triggers=0,plans=0,invalidations=0)
        self.enabled=True;self.automatic=app_settings.initial_automatic();self.value=None;self.fresh=0;self.owner=None
        self.last='idle';self.devices=0;self.closed=False;self.refreshing=False
        self.connection=Gio.bus_get_sync(Gio.BusType.SESSION,None)
        self.proxy=Gio.DBusProxy.new_sync(self.connection,Gio.DBusProxyFlags.NONE,None,'org.gnome.Shell',PATH,IFACE,None)
        self.proxy.connect('g-signal',self.changed)
        self.proxy.connect('notify::g-name-owner',lambda *_:self.invalidate())
        self.stand=stand;self.helper=None;self.buffer=b''
        if stand:
            base=Path(os.environ['TYPETUNE_NESTED_STAND']).resolve()
            assert Path(os.environ['XDG_RUNTIME_DIR']).resolve()==base/'runtime'
            self.devices=1
        else:
            local=HERE/'compat_transport'
            executable=local if local.exists() else HERE.parents[1]/'target/debug/examples/compat_transport'
            self.helper=subprocess.Popen([str(executable)],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.DEVNULL)
            os.set_blocking(self.helper.stdout.fileno(),False)
            GLib.io_add_watch(self.helper.stdout.fileno(),GLib.IO_IN|GLib.IO_HUP|GLib.IO_ERR,self.read)
            GLib.timeout_add(250,self.ping)
        self.started=time.monotonic()
        xml='''<node><interface name="org.typetune.Compat1">
<method name="GetStatus"><arg type="s" direction="out"/></method>
<method name="SetEnabled"><arg type="b" direction="in"/><arg type="b" direction="out"/></method>
<method name="SetAutomatic"><arg type="b" direction="in"/><arg type="b" direction="out"/></method>
<method name="ReloadApplications"><arg type="s" direction="in"/><arg type="s" direction="out"/></method>
<method name="ReloadWords"><arg type="s" direction="in"/><arg type="s" direction="out"/></method>
<method name="Quit"/>'''
        if stand: xml+='<method name="Feed"><arg type="s" direction="in"/></method>'
        xml+=correction_feedback.XML+'</interface></node>'
        self.connection.register_object('/org/typetune/Compat1',Gio.DBusNodeInfo.new_for_xml(xml).interfaces[0],self.method,None,None)
        self.name=Gio.bus_own_name_on_connection(self.connection,'org.typetune.Compat',Gio.BusNameOwnerFlags.NONE,None,lambda *_:self.close())
        GLib.timeout_add(50,self.poll)
        GLib.unix_signal_add(GLib.PRIORITY_DEFAULT,signal.SIGTERM,self.close)
        GLib.unix_signal_add(GLib.PRIORITY_DEFAULT,signal.SIGINT,self.close)
    def allowed(self):
        return self.enabled and self.devices>0 and self.value is not None and time.monotonic()-self.fresh<.2 and context(self.value) is not None and not self.value['modifiers'] & ~16
    def auto_allowed(self):
        return self.automatic and not preferences.ERROR and application_rules.allows((self.value or {}).get('app_id'))
    def method(self,connection,sender,path,interface,name,parameters,invocation):
        if hasattr(self,'feedback') and correction_feedback.method(self.feedback,name,parameters,invocation):return
        if name=='GetStatus':
            s=dict(suggestion_count=len(self.feedback.pending()),**application_rules.status((self.value or {}).get('app_id')),words_generation=preferences.CURRENT['generation'],words_error=preferences.ERROR,enabled=self.enabled,automatic=self.automatic and not preferences.ERROR and not application_rules.ERROR,available=self.allowed(),devices=self.devices,
                   counters=self.stats,proof='keymap-inferred',last_result=self.last,mode=(self.value or {}).get('snapshot',{}).get('source_id'),
                   limitations=['text-unverified','selection-unknown','sensitivity-unknown','composition-unknown'])
            invocation.return_value(GLib.Variant('(s)',(json.dumps(s),)))
        elif name in ('ReloadWords','ReloadApplications'):
            try:
                config=preferences if name=='ReloadWords' else application_rules
                generation=config.reload(parameters.unpack()[0])
                self.invalidate()
                invocation.return_value(GLib.Variant('(s)',(generation,)))
            except (ValueError,OSError) as error:
                invocation.return_dbus_error('org.typetune.Error.Words',str(error))
        elif name in ('SetEnabled','SetAutomatic'):
            value=parameters.unpack()[0];self.invalidate()
            if name=='SetEnabled':self.enabled=value
            else:self.automatic=value
            invocation.return_value(GLib.Variant('(b)',(value,)))
        elif name=='Quit':invocation.return_value(None);GLib.idle_add(self.close)
        elif name=='Feed' and self.stand:
            self.event(json.loads(parameters.unpack()[0]));invocation.return_value(None)
    def changed(self,proxy,sender,name,parameters):
        if name=='Changed':
            self.fresh=0
            # Own source switch is distinguished by interaction_generation.
            if self.phase!='switching':self.invalidate()
            self.poll()
    def invalidate(self):
        if hasattr(self,'feedback_tracker'):self.feedback_tracker.reset()
        self.feedback_edit=None
        self.revision+=1;self.history.reset();self.armed=None;self.replacement=None
        if hasattr(self,'stats'):self.stats['invalidations']+=1
        if self.pending is not None:
            self.last='indeterminate' if self.phase=='injecting' else 'rejected'
            self.send({'op':'cancel'})
        self.pending=None;self.phase=None
    def poll(self):
        if not self.refreshing:self.refresh(lambda:None)
        return not self.closed
    def refresh(self,done):
        if self.refreshing:GLib.timeout_add(10,lambda:(self.refresh(done),False)[1]);return
        self.refreshing=True; owner=self.proxy.get_name_owner()
        def received(proxy,result):
            self.refreshing=False
            try:
                value=json.loads(proxy.call_finish(result).unpack()[0])
                if owner is None or owner!=proxy.get_name_owner():raise ValueError()
                old=context(self.value) if self.value else None
                current=context(value)
                if (current!=old or value.get('app_id')!=(self.value or {}).get('app_id')) and self.phase!='switching':self.invalidate()
                self.value=value;self.owner=owner;self.fresh=time.monotonic()
            except Exception:self.value=None;self.invalidate()
            done()
        self.proxy.call('GetCompatContext',None,Gio.DBusCallFlags.NONE,300,None,received)
    def send(self,value):
        if self.stand:
            if value['op']=='emit':
                identifier=value['id']
                def emitted(proxy,result):
                    try:status=proxy.call_finish(result).unpack()[0]
                    except Exception:status='indeterminate'
                    self.event(dict(kind='result',id=identifier,status=status))
                self.proxy.call('ProbeSequence',GLib.Variant('(s)',(json.dumps(value['keys']),)),Gio.DBusCallFlags.NONE,5000,None,emitted)
            elif value['op']=='cancel':self.proxy.call('ProbeCancel',None,Gio.DBusCallFlags.NONE,300,None,None)
            return
        try:
            self.helper.stdin.write((json.dumps(value)+'\n').encode());self.helper.stdin.flush()
        except (BrokenPipeError,OSError):self.close()
    def ping(self):
        if self.helper.poll() is not None:self.close();return False
        self.send(dict(op='ping'));return not self.closed
    def read(self,fd,condition):
        try:
            data=os.read(fd,65536)
            if not data:self.close();return False
            self.buffer+=data
            if len(self.buffer)>262144:self.close();return False
            while b'\n' in self.buffer:
                line,self.buffer=self.buffer.split(b'\n',1);self.event(json.loads(line))
        except BlockingIOError:pass
        except Exception:self.close();return False
        return not self.closed
    def event(self,event):
        kind=event['kind']
        if kind=='ready':self.started=time.monotonic();return
        if kind=='reset':
            self.seq=event['seq'];self.devices=event['devices'];self.invalidate();return
        if kind=='result':
            if event['id']==self.pending:
                self.last=event['status'];self.pending=None;self.phase=None;self.history.reset()
                # Output is still unverified. Preserve only our inferred suffix,
                # allowing an explicit new gesture; never retry failed output.
                if self.last=='injected-unverified' and self.replacement is not None:
                    self.history.text=self.replacement
                edit=getattr(self,'feedback_edit',None)
                if edit and self.last=='injected-unverified' and hasattr(self,'feedback_tracker'):self.feedback_tracker.completed(*edit)
                elif hasattr(self,'feedback_tracker'):self.feedback_tracker.reset()
                self.feedback_edit=None
                self.replacement=None
            return
        if kind!='key':return
        self.seq=event['seq']
        self.stats['keys_seen']+=1
        # Source timestamps are relative to the helper's monotonic startup.
        lag=self.now()-self.started-event['time']
        self.stats['last_event_lag_ms']=round(lag*1000)
        self.stats['max_event_lag_ms']=max(self.stats.get('max_event_lag_ms',-100000),round(lag*1000))
        self.stats['min_event_lag_ms']=min(self.stats.get('min_event_lag_ms',100000),round(lag*1000))
        if not self.stand and not -.1 <= lag <= .25:
            self.stats['stale_events']+=1
            self.last='stale-input'
            self.invalidate();return
        if self.pending is not None and event['value']!=0:self.invalidate()
        if event['value']!=0:
            if event['code'] not in (42,54) and hasattr(self,'feedback_tracker'):
                if (self.allowed() and event['code'] in CODES+[57]
                    and not any(c not in (42,54) for _,c in self.history.held)):
                    self.feedback_tracker.advance(event['code']==57)
                else:self.feedback_tracker.reset()
            self.armed=None
            if event['code'] not in (42,54):self.revision+=1
        allowed=self.allowed()
        # Shift-held context is expected while spelling capitals; only Shell
        # non-Shift modifiers are allowed for history, checked again before edit.
        if self.value and self.enabled and time.monotonic()-self.fresh<.2:
            copy=dict(self.value);copy['modifiers'] &= ~1
            allowed=context(copy) is not None
        mode=(self.value or {}).get('snapshot',{}).get('source_id')
        trigger=self.history.event(event,mode,allowed)
        if trigger=='auto' and not self.auto_allowed():trigger=None
        if trigger:
            self.stats[trigger+'_triggers']+=1
            self.armed=(trigger,self.revision,self.now()+.5)
        if self.armed is not None and not self.history.held:
            trigger,revision,deadline=self.armed
            self.armed=None
            if self.now()<=deadline:
                def released():
                    if self.revision==revision and not self.history.held and self.now()<=deadline:
                        self.prepare(trigger,revision)
                    return False
                GLib.timeout_add(60,released)
    def prepare(self,trigger,revision):
        if revision!=self.revision or self.pending is not None or self.history.held:return
        text=self.history.text
        def ready():
            if revision!=self.revision or not self.allowed() or self.history.held:return
            if trigger=='auto' and not self.auto_allowed():return
            suggestion=self.rules.suggest(text,trigger=='auto')
            if suggestion['status']!='inferred':self.last='no-candidate';return
            self.stats['plans']+=1
            keys=key_plan(suggestion['remove'],suggestion['replacement'],suggestion['mode'])
            if keys is None:self.last='rejected';return
            self.action+=1;identifier=self.action;self.pending=identifier;self.phase='switching'
            self.replacement=suggestion['replacement']
            self.feedback_edit=(trigger,text,self.replacement,trigger=='manual' and self.auto_allowed() and correction_feedback.learnable(self.rules.call,text,self.replacement))
            self.last='pending'
            app_id=self.value.get('app_id')
            token=context(self.value);source=self.value['snapshot'];mode=suggestion['mode']
            request={k:source[k] for k in ('instance','generation','window')};request['target']=mode
            deadline=time.monotonic()+.7
            def check():
                if self.pending!=identifier:return
                if (time.monotonic()>deadline or context(self.value)!=token or self.value.get('app_id')!=app_id or not self.allowed() or revision!=self.revision or (trigger=='auto' and not self.auto_allowed())):
                    self.last='rejected';self.invalidate();return
                if self.value['snapshot']['source_id']!=mode:
                    GLib.timeout_add(20,lambda:(self.refresh(check),False)[1]);return
                self.phase='injecting'
                self.send(dict(op='emit',id=identifier,seq=self.seq,keys=keys))
            def switched(proxy,result):
                try:
                    reply=json.loads(proxy.call_finish(result).unpack()[0])
                    if reply['status'] not in ('requested','unchanged'):raise ValueError()
                except Exception:self.last='rejected';self.invalidate();return
                self.refresh(check)
            self.proxy.call('RequestSource',GLib.Variant('(s)',(json.dumps(request),)),Gio.DBusCallFlags.NONE,300,None,switched)
        self.refresh(ready)
    def close(self):
        if self.closed:return False
        self.closed=True
        if self.helper:
            try:self.helper.stdin.close()
            except OSError:pass
            # Transport's independent lease releases keys even if runtime dies.
            self.helper.terminate()
        self.loop.quit();return False

if __name__=='__main__':
    runtime=Runtime('--stand' in sys.argv)
    try:runtime.loop.run()
    finally:runtime.close()
