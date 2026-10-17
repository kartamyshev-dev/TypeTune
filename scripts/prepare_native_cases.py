#!/usr/bin/env python3
"""Select fixed native sample before measuring either program; no engine calls."""
import collections, hashlib, json
from pathlib import Path
root = Path(__file__).resolve().parents[1]
latin = "`qwertyuiop[]asdfghjkl;'zxcvbnm,./~QWERTYUIOP{}ASDFGHJKL:\"ZXCVBNM<>?"
russian = 'ёйцукенгшщзхъфывапролджэячсмитьбю.ЁЙЦУКЕНГШЩЗХЪФЫВАПРОЛДЖЭЯЧСМИТЬБЮ,'
to_en, to_ru = str.maketrans(russian, latin), str.maketrans(latin, russian)
rows = []
for line in (root/'corpus/synthetic-v2.jsonl').read_text().splitlines():
    fixture = json.loads(line); value = fixture['input']
    if value.isascii():
        physical, source = value, 'ABC'
    else:
        physical, source = value.translate(to_en), 'RussianWin'
        if physical.translate(to_ru) != value: continue
    if not physical.isascii() or not physical or len(physical) > 100: continue
    if any(ord(c) < 32 or ord(c) > 126 for c in physical): continue
    rows.append(dict(id=fixture['id'], text=physical, source=source,
                     expected=fixture['expected']+' ', split=fixture['split'], category=fixture['category'],
                     provenance=fixture['provenance']))
rows.sort(key=lambda r: hashlib.sha256(('native-v1:'+r['id']).encode()).hexdigest())
selected = []
for split, count in [('train',700),('holdout',300)]:
    sample = [r for r in rows if r['split']==split][:count]
    assert len(sample)==count
    selected += sample
output = root/'corpus/native-v1.json'
output.write_text(json.dumps(selected,ensure_ascii=False,indent=2)+'\n')
folder = root/'research/private/native-batches'; folder.mkdir(parents=True, exist_ok=True)
for index in range(0,len(selected),200):
    (folder/f'{index//200:02}.json').write_text(json.dumps(selected[index:index+200],ensure_ascii=False))
print(json.dumps({'count':len(selected),'split':dict(collections.Counter(r['split'] for r in selected)),
                  'categories':dict(collections.Counter(r['category'] for r in selected)),
                  'sha256':hashlib.sha256(output.read_bytes()).hexdigest(),
                  'notice':'Native sample from synthetic lexicon consistency corpus. Not independent language quality.'},indent=2))
