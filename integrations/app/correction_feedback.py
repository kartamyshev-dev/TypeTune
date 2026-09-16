"""Session-only, bounded proposals. Never writes text or changes a dictionary."""
from collections import OrderedDict
import time
import uuid
import preferences

class Feedback:
    def __init__(self):
        self.counts=OrderedDict();self.proposals={};self.dismissed=set()
    def record(self, source, corrected, kind="exclusion"):
        source=source.strip().lower();corrected=corrected.strip().lower()
        try:preferences.validate(dict(version=1,generation='0',words=[],exclusions=[corrected]))
        except ValueError:return
        if not 2<=len(source)<=32 or source==corrected:return
        key=(kind,source,corrected)
        if key in self.dismissed:return
        if key not in self.counts and len(self.counts)>=64:
            oldest,_=self.counts.popitem(last=False)
            self.proposals.pop(oldest,None)
        previous=self.counts.get(key,0)
        self.counts[key]=min(3,previous+1)
        if self.counts[key]==3 and key not in self.proposals:
            self.proposals[key]=dict(id=uuid.uuid4().hex,source=source,word=corrected,kind=kind)
        if previous<3:return (key,self.counts[key])
    def withdraw(self, receipt):
        if receipt is None:return
        key,count=receipt
        if key in self.dismissed or self.counts.get(key)!=count:return
        self.counts[key]=count-1
        self.proposals.pop(key,None)
    def pending(self):
        return [dict(value) for value in self.proposals.values()
                if value['word'] not in preferences.CURRENT['exclusions']
                and (value['kind']=='exclusion' or (value['word'] not in preferences.CURRENT['words']
                     and value['source'] not in preferences.CURRENT['exclusions']))]
    def dismiss(self, identifier):
        for key,value in list(self.proposals.items()):
            if value['id']==identifier:
                del self.proposals[key]
                # Once full, stop collecting new proposals for this runtime session.
                self.dismissed.add(key)
                return
        raise ValueError('Предложение устарело. Обновите список')

def learnable(call, before, after):
    """Probe the real rules with a temporary vocabulary; restore it before any edit."""
    source=before.strip().lower();target=after.strip().lower()
    current=preferences.CURRENT
    if preferences.ERROR or target in current['words'] or len(current['words'])>=500:
        return False
    if source in current['exclusions'] or target in current['exclusions']:return False
    try:preferences.validate(dict(version=1,generation='0',words=[target],exclusions=[]))
    except ValueError:return False
    configure=dict(op='configure',words=current['words'],exclusions=current['exclusions'])
    if call(configure).get('status')!='configured':return False
    text=before.rstrip(' ')+' '
    if call(dict(op='infer',text=text,automatic=True)).get('status')!='ignored':return False
    try:
        if call(dict(configure,words=current['words']+[target])).get('status')!='configured':return False
        candidate=call(dict(op='infer',text=text,automatic=True))
        return candidate.get('status')=='inferred' and candidate.get('replacement')==after.rstrip(' ')+' '
    finally:
        if call(configure).get('status')!='configured':raise RuntimeError('Не удалось восстановить словарь')

class Tracker:
    def __init__(self, feedback, now=time.monotonic):
        self.feedback=feedback;self.now=now;self.reset()
    def reset(self):self.last=None;self.manual=None;self.consumed=False;self.receipt=None
    def advance(self, boundary):
        pending=self.manual
        self.reset()
        if pending and boundary and not pending[1].endswith(' '):
            self.feedback.record(*pending,kind='word')
    def completed(self, kind, before, after, learn=False):
        previous=self.last;self.last=None
        if len(self.feedback.dismissed)>=64:return
        if kind=='auto':
            self.manual=None;self.consumed=False;self.receipt=None
            if len(before)<=128 and len(after)<=128:
                self.last=(before,after,self.now()+10)
        elif kind=='manual':
            if previous:
                source,corrected,deadline=previous
                self.consumed=True
                if self.now()<=deadline and before==corrected and after==source:
                    self.feedback.record(source,corrected)
            elif self.manual:
                # Any repeat gesture on the same occurrence cancels learning.
                self.feedback.withdraw(self.receipt)
                self.receipt=None;self.manual=None;self.consumed=True
            elif learn and not self.consumed:
                self.manual=(before,after)
                if before.endswith(' ') and after.endswith(' '):
                    self.receipt=self.feedback.record(before,after,kind='word')

FEEDBACK=Feedback()
XML='''<method name="GetSuggestions"><arg type="s" direction="out"/></method>
<method name="DismissSuggestion"><arg type="s" direction="in"/><arg type="b" direction="out"/></method>'''

def method(feedback, name, parameters, invocation):
    import json
    from gi.repository import GLib
    if name=='GetSuggestions':
        invocation.return_value(GLib.Variant('(s)',(json.dumps(feedback.pending(),ensure_ascii=False),)))
    elif name=='DismissSuggestion':
        try:
            feedback.dismiss(parameters.unpack()[0])
            invocation.return_value(GLib.Variant('(b)',(True,)))
        except ValueError as error:invocation.return_dbus_error('org.typetune.Error.Suggestion',str(error))
    else:return False
    return True
