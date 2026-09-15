"""Explicitly inferred last-word history; no assertion about editor contents."""
from gesture import DoubleShift
CODES = [41,16,17,18,19,20,21,22,23,24,25,26,27,30,31,32,33,34,35,36,37,38,39,40,44,45,46,47,48,49,50,51,52]
US = "`qwertyuiop[]asdfghjkl;'zxcvbnm,."
RU = "ёйцукенгшщзхъфывапролджэячсмитьбю"
UPPER_US = '~QWERTYUIOP{}ASDFGHJKL:"ZXCVBNM<>'


def key_plan(remove, replacement, mode):
    """Validate the entire bounded sequence before any deletion. No clipboard."""
    if mode not in ('us','ru') or not 1 <= remove <= 128 or len(replacement)>128:
        return None
    table = {}
    lower, upper = (US, UPPER_US) if mode=='us' else (RU, RU.upper())
    for code, small, capital in zip(CODES, lower, upper):
        table[small] = (code, False); table[capital] = (code, True)
    table[' '] = (57, False)
    if any(c not in table for c in replacement): return None
    keys = [[14, state] for _ in range(remove) for state in (True,False)]
    for c in replacement:
        code, shift = table[c]
        if shift: keys.append([42,True])
        keys.extend([[code,True],[code,False]])
        if shift: keys.append([42,False])
    return keys


class History:
    def __init__(self):
        self.held=set(); self.last_time=None; self.clear()
    def clear(self):
        self.text=''; self.gesture=DoubleShift()
    def reset(self):
        self.held.clear(); self.last_time=None; self.clear()
    def event(self, event, mode, allowed=True):
        code, value, device, stamp = (event[k] for k in ('code','value','device','time'))
        identity=(device,code)
        if value==0: self.held.discard(identity)
        elif value==1: self.held.add(identity)
        if self.last_time is not None and stamp < self.last_time:
            self.clear(); return None
        self.last_time=stamp
        if not allowed or mode not in ('us','ru'):
            self.clear(); return None
        if code in (42,54):
            if value==2 or any(c not in (42,54) for _,c in self.held):
                self.gesture.reset(); return None
            # Device identity matters: two keyboards cannot form one gesture.
            if self.gesture.edge(identity, value==0, stamp) and not self.held and self.text:
                return 'manual'
            return None
        if value==0: return None
        self.gesture.reset()
        if any(c in (29,97,56,100,125,126,58,69) for _,c in self.held):
            self.clear(); return None
        if code==14:
            self.text=self.text[:-1]; return None
        if code==57:
            if self.text and not self.text.endswith(' '):
                self.text+=' '; return 'auto'
            self.clear(); return None
        if code not in CODES:
            self.clear(); return None
        shift=any(c in (42,54) for _,c in self.held)
        text=(US if mode=='us' else RU)
        if shift: text=UPPER_US if mode=='us' else RU.upper()
        if self.text.endswith(' '): self.text=''
        self.text+=text[CODES.index(code)]
        if len(self.text)>128: self.clear()
        return None
