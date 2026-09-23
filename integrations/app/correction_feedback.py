"""Session-or-disk proposals. Never writes free text or changes a dictionary itself."""
from collections import OrderedDict
import json
import os
from pathlib import Path
import tempfile
import time
import uuid
import fcntl
import preferences

FEEDBACK_ROOT = Path(os.environ.get('XDG_CONFIG_HOME', str(Path.home()/'.config'))) / 'typetune'
FEEDBACK_PATH = FEEDBACK_ROOT / 'feedback.json'
FEEDBACK_LIMIT = 65536
MAX_PAIRS = 64
MIN_THRESHOLD = 1
MAX_THRESHOLD = 10
DEFAULT_THRESHOLD = 3


def validate_threshold(value):
    if type(value) is not int or not MIN_THRESHOLD <= value <= MAX_THRESHOLD:
        raise ValueError(f'Порог предложений: целое число от {MIN_THRESHOLD} до {MAX_THRESHOLD}')
    return value


def load(path=FEEDBACK_PATH):
    if not path.exists():
        return dict(version=1, generation='0', pairs=[])
    with path.open('rb') as file:
        raw = file.read(FEEDBACK_LIMIT+1)
    if len(raw) > FEEDBACK_LIMIT:
        raise ValueError('Файл предложений слишком большой')
    try:
        value = json.loads(raw)
    except (UnicodeError, json.JSONDecodeError):
        raise ValueError('Файл предложений повреждён') from None
    if (not isinstance(value, dict) or set(value) != {'version', 'generation', 'pairs'}
            or type(value['version']) is not int or value['version'] != 1
            or not isinstance(value['generation'], str) or not 1 <= len(value['generation']) <= 64
            or not isinstance(value['pairs'], list) or len(value['pairs']) > MAX_PAIRS):
        raise ValueError('Неверный формат файла предложений')
    pairs = []
    seen = set()
    for entry in value['pairs']:
        if (not isinstance(entry, dict) or set(entry) - {'kind', 'source', 'word', 'count', 'dismissed', 'id'}
                or not {'kind', 'source', 'word', 'count', 'dismissed'} <= set(entry)
                or entry['kind'] not in ('exclusion', 'word')
                or type(entry['count']) is not int or not 0 <= entry['count'] <= MAX_THRESHOLD
                or type(entry['dismissed']) is not bool
                or 'id' in entry and not (isinstance(entry['id'], str) and 1 <= len(entry['id']) <= 64)):
            raise ValueError('Неверная запись в файле предложений')
        source = entry['source']; word = entry['word']
        if (not isinstance(source, str) or not isinstance(word, str)
                or not 2 <= len(source.strip()) <= 32 or not 2 <= len(word.strip()) <= 32
                or source != source.strip().lower() or word != word.strip().lower()):
            raise ValueError('Неверная запись в файле предложений')
        key = (entry['kind'], source, word)
        if key in seen:
            raise ValueError('Неверная запись в файле предложений')
        seen.add(key)
        clean = dict(kind=entry['kind'], source=source, word=word,
                     count=entry['count'], dismissed=entry['dismissed'])
        if entry.get('id'):
            clean['id'] = entry['id']
        pairs.append(clean)
    return dict(version=1, generation=value['generation'], pairs=pairs)


def save(value, expected, path=FEEDBACK_PATH):
    if (not isinstance(value, dict) or set(value) != {'version', 'generation', 'pairs'}
            or type(value['version']) is not int or value['version'] != 1
            or not isinstance(value['generation'], str) or not 1 <= len(value['generation']) <= 64
            or not isinstance(value['pairs'], list) or len(value['pairs']) > MAX_PAIRS):
        raise ValueError('Неверный формат файла предложений')
    path.parent.mkdir(parents=True, exist_ok=True)
    lock_path = path.with_suffix('.lock')
    with lock_path.open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        if load(path)['generation'] != expected:
            raise ValueError('Файл предложений изменён другим окном')
        value = dict(value, generation=uuid.uuid4().hex, pairs=_normalize_pairs(value['pairs']))
        temporary = None
        try:
            with tempfile.NamedTemporaryFile(mode='w', encoding='utf-8', dir=path.parent, delete=False) as file:
                temporary = Path(file.name)
                json.dump(value, file, ensure_ascii=False, indent=2)
                file.flush(); os.fsync(file.fileno())
            os.chmod(temporary, 0o600)
            temporary.replace(path)
        finally:
            if temporary:
                temporary.unlink(missing_ok=True)
        return value


def _normalize_pairs(pairs):
    normalized = []
    seen = set()
    for entry in pairs:
        if (not isinstance(entry, dict) or set(entry) - {'kind', 'source', 'word', 'count', 'dismissed', 'id'}
                or not {'kind', 'source', 'word', 'count', 'dismissed'} <= set(entry)
                or entry['kind'] not in ('exclusion', 'word')
                or type(entry['count']) is not int or not 0 <= entry['count'] <= MAX_THRESHOLD
                or type(entry['dismissed']) is not bool):
            raise ValueError('Неверная запись в файле предложений')
        source = str(entry.get('source', '')).strip().lower()
        word = str(entry.get('word', '')).strip().lower()
        if not 2 <= len(source) <= 32 or not 2 <= len(word) <= 32:
            raise ValueError('Неверная запись в файле предложений')
        key = (entry['kind'], source, word)
        if key in seen:
            continue
        seen.add(key)
        clean = dict(kind=entry['kind'], source=source, word=word,
                     count=entry['count'], dismissed=entry['dismissed'])
        if entry.get('id') and isinstance(entry['id'], str) and 1 <= len(entry['id']) <= 64:
            clean['id'] = entry['id']
        normalized.append(clean)
    if len(normalized) > MAX_PAIRS:
        raise ValueError('Слишком много пар предложений')
    return normalized


class Feedback:
    def __init__(self, path=None, threshold=DEFAULT_THRESHOLD, schedule=None):
        self.path = path
        self.threshold = validate_threshold(threshold)
        self.schedule = schedule
        self.counts = OrderedDict(); self.proposals = {}; self.dismissed = set()
        self.generation = '0'
        self.error = None
        self.dirty = False
        if path is not None:
            self._load()

    def _load(self):
        try:
            document = load(self.path)
        except (ValueError, OSError):
            self.error = True
            self.path = None
            return
        self.generation = document['generation']
        for entry in document['pairs']:
            key = (entry['kind'], entry['source'], entry['word'])
            self.counts[key] = entry['count']
            if entry['dismissed']:
                self.dismissed.add(key)
            if entry.get('id') and entry['count'] >= self.threshold and key not in self.dismissed:
                self.proposals[key] = dict(id=entry['id'], source=entry['source'],
                                           word=entry['word'], kind=entry['kind'],
                                           count=entry['count'])

    def _pairs_document(self):
        pairs = []
        for (kind, source, word), count in self.counts.items():
            entry = dict(kind=kind, source=source, word=word, count=count,
                         dismissed=(kind, source, word) in self.dismissed)
            proposal = self.proposals.get((kind, source, word))
            if proposal:
                entry['id'] = proposal['id']
            pairs.append(entry)
        for key in sorted(self.dismissed - set(self.counts)):
            kind, source, word = key
            pairs.append(dict(kind=kind, source=source, word=word, count=0, dismissed=True))
        if len(pairs) > MAX_PAIRS:
            pairs = pairs[:MAX_PAIRS]
        return pairs

    def flush(self):
        if self.path is None or not self.dirty:
            return
        try:
            document = save(dict(version=1, generation=self.generation,
                                 pairs=self._pairs_document()), self.generation, self.path)
        except (ValueError, OSError):
            self.error = True
            self.path = None
            self.dirty = False
            return
        self.generation = document['generation']
        self.dirty = False

    def _mark(self):
        was_dirty = self.dirty
        self.dirty = True
        if self.path is None:
            return
        if self.schedule is not None:
            if not was_dirty:
                self.schedule(self.flush)
        else:
            self.flush()

    def set_threshold(self, threshold):
        self.threshold = validate_threshold(threshold)
        for key in list(self.proposals):
            if self.counts.get(key, 0) < self.threshold:
                del self.proposals[key]
        for key, count in self.counts.items():
            if count >= self.threshold and key not in self.dismissed and key not in self.proposals:
                self.proposals[key] = dict(id=uuid.uuid4().hex, source=key[1],
                                           word=key[2], kind=key[0], count=count)

    def record(self, source, corrected, kind="exclusion"):
        source=source.strip().lower();corrected=corrected.strip().lower()
        try:preferences.validate(dict(version=1,generation='0',words=[],exclusions=[corrected]))
        except ValueError:return
        if not 2<=len(source)<=32 or source==corrected:return
        key=(kind,source,corrected)
        if key in self.dismissed:return
        if key not in self.counts and len(self.counts)>=MAX_PAIRS:
            oldest,_=self.counts.popitem(last=False)
            self.proposals.pop(oldest,None)
        previous=self.counts.get(key,0)
        self.counts[key]=min(self.threshold,previous+1)
        if self.counts[key]==self.threshold and key not in self.proposals:
            self.proposals[key]=dict(id=uuid.uuid4().hex,source=source,word=corrected,kind=kind,count=self.counts[key])
        self._mark()
        if previous<self.threshold:return (key,self.counts[key])
    def withdraw(self, receipt):
        if receipt is None:return
        key,count=receipt
        if key in self.dismissed or self.counts.get(key)!=count:return
        self.counts[key]=count-1
        self.proposals.pop(key,None)
        self._mark()
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
                self._mark()
                return
        raise ValueError('Предложение устарело. Обновите список')
    def snapshot(self):
        return dict(threshold=self.threshold, pairs=len(self.counts),
                    proposals=len(self.proposals), dismissed=len(self.dismissed),
                    error=self.error, generation=self.generation)

def learnable(call, before, after):
    """Probe the real rules with a temporary vocabulary; restore it before any edit."""
    source=before.strip().lower();target=after.strip().lower()
    current=preferences.CURRENT
    if preferences.ERROR or target in current['words'] or len(current['words'])>=preferences.LIMIT_ENTRIES:
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
        if len(self.feedback.dismissed)>=MAX_PAIRS:return
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

XML='''<method name="GetSuggestions"><arg type="s" direction="out"/></method>
<method name="DismissSuggestion"><arg type="s" direction="in"/><arg type="b" direction="out"/></method>
<method name="SetLearnThreshold"><arg type="i" direction="in"/><arg type="i" direction="out"/></method>
<method name="GetFeedback"><arg type="s" direction="out"/></method>'''

def method(feedback, name, parameters, invocation):
    import json as _json
    from gi.repository import GLib
    if name=='GetSuggestions':
        feedback.flush()
        invocation.return_value(GLib.Variant('(s)',(_json.dumps(feedback.pending(),ensure_ascii=False),)))
    elif name=='DismissSuggestion':
        try:
            feedback.dismiss(parameters.unpack()[0])
            feedback.flush()
            invocation.return_value(GLib.Variant('(b)',(True,)))
        except ValueError as error:invocation.return_dbus_error('org.typetune.Error.Suggestion',str(error))
    elif name=='SetLearnThreshold':
        try:
            feedback.set_threshold(parameters.unpack()[0])
            feedback.flush()
            invocation.return_value(GLib.Variant('(i)',(feedback.threshold,)))
        except ValueError as error:invocation.return_dbus_error('org.typetune.Error.Threshold',str(error))
    elif name=='GetFeedback':
        invocation.return_value(GLib.Variant('(s)',(_json.dumps(feedback.snapshot(),ensure_ascii=False),)))
    else:return False
    return True
