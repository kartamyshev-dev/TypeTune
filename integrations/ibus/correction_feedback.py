"""Session-only, bounded proposals. Never writes text or changes a dictionary."""
from collections import OrderedDict
import time
import uuid
import preferences

class Feedback:
    def __init__(self):
        self.counts=OrderedDict();self.proposals={};self.dismissed=set()
    def record(self, source, corrected):
        source=source.strip().lower();corrected=corrected.strip().lower()
        try:preferences.validate(dict(version=1,generation='0',words=[],exclusions=[corrected]))
        except ValueError:return
        if not 2<=len(source)<=32 or source==corrected:return
        key=(source,corrected)
        if key in self.dismissed:return
        if key not in self.counts and len(self.counts)>=64:
            oldest,_=self.counts.popitem(last=False)
            self.proposals.pop(oldest,None)
        self.counts[key]=min(3,self.counts.get(key,0)+1)
        if self.counts[key]==3 and key not in self.proposals:
            self.proposals[key]=dict(id=uuid.uuid4().hex,source=source,word=corrected)
    def pending(self):
        return [dict(value) for value in self.proposals.values() if value['word'] not in preferences.CURRENT['exclusions']]
    def dismiss(self, identifier):
        for key,value in list(self.proposals.items()):
            if value['id']==identifier:
                del self.proposals[key]
                # Once full, stop collecting new proposals for this runtime session.
                self.dismissed.add(key)
                return
        raise ValueError('Предложение устарело. Обновите список')

class Tracker:
    def __init__(self, feedback, now=time.monotonic):
        self.feedback=feedback;self.now=now;self.last=None
    def reset(self):self.last=None
    def completed(self, kind, before, after):
        previous=self.last;self.last=None
        if len(self.feedback.dismissed)>=64:return
        if kind=='auto':
            if len(before)<=128 and len(after)<=128:
                self.last=(before,after,self.now()+10)
        elif kind=='manual' and previous:
            source,corrected,deadline=previous
            if self.now()<=deadline and before==corrected and after==source:
                self.feedback.record(source,corrected)

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
