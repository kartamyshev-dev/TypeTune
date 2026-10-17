#!/usr/bin/env python3
"""Reproducible v2 synthetic consistency fixtures; never calls the decision engine."""
import hashlib
import json
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
lex = json.loads((ROOT / 'Sources/LayoutPilotCore/Resources/lexicon.json').read_text())
latin = "`qwertyuiop[]asdfghjkl;'zxcvbnm,./~QWERTYUIOP{}ASDFGHJKL:\"ZXCVBNM<>?"
ru = 'ёйцукенгшщзхъфывапролджэячсмитьбю.ЁЙЦУКЕНГШЩЗХЪФЫВАПРОЛДЖЭЯЧСМИТЬБЮ,'
assert len(latin) == len(ru)

def digest(value):
    return hashlib.sha256(value.encode()).hexdigest()

def convert(word, language):
    return word.translate(str.maketrans(latin, ru) if language == 'english' else str.maketrans(ru, latin))

# Group ё variants together. Split at roots before deriving any casing/format variants.
groups = {}
for language in ['english', 'russian']:
    for word in lex[language]:
        wrong = convert(word, language)
        if len(word) >= 3 and wrong.isalpha():
            group = language + ':' + word.replace('ё', 'е')
            groups.setdefault(group, (language, word))
selected = sorted(groups, key=digest)
# Whole groups have eleven variants; this preserves exactly 70/30 across rows; all previous IDs/splits stay fixed.
count = min(400, len(selected) // 10 * 10)
assert count >= 100, 'Insufficient roots'
selected = selected[:count]
train = set(selected[:count * 7 // 10])
rows = []
for group in selected:
    language, word = groups[group]
    normalized = lex['yo'].get(word, word)
    wrong = convert(word, language)
    variants = [
        ('correct', word, normalized),
        ('wrong', wrong, normalized),
        ('case', word.upper(), normalized.upper()),
        ('case_wrong_upper', wrong.upper(), normalized.upper()),
        ('case_wrong_title', wrong.capitalize(), normalized.capitalize()),
        ('doublecaps', word[:2].upper() + word[2:], normalized.capitalize()),
        ('digits', wrong + '123', wrong + '123'),
        ('url', 'https://' + wrong + '.example/test', 'https://' + wrong + '.example/test'),
        ('email', wrong + '@example.test', wrong + '@example.test'),
        ('code', 'let_' + wrong + '=1', 'let_' + wrong + '=1'),
        ('mixed', 'A' + word + 'я', 'A' + word + 'я'),
    ]
    for index, (category, value, expected) in enumerate(variants):
        rows.append(dict(schemaVersion=1, id=digest(group)[:12] + f'-{category}', feature='automatic-layout',
                         split='train' if group in train else 'holdout', category=category,
                         provenance='synthetic lexicon consistency; authored standard physical mapping; root=' + group,
                         input=value, expected=expected, originalResult=None, events=None))
# Hand-authored conservative challenges are independent expectations, not outputs of Engine.
challenges = [
    ('short', 'a'), ('short', 'я'), ('short', 'to'), ('short', 'он'),
    ('ambiguous', 'все'), ('unknown', 'quizzacious'), ('unknown', 'сверхпроводимость'),
    ('unicode', '👩🏽‍💻'), ('unicode', 'e\u0301'), ('unicode', '𝒜𝓁𝓅𝒽𝒶'),
    ('mixed', 'aЁ'), ('mixed', 'testЁтест'), ('digits', 'ghbdtn42'),
    ('url', 'https://example.org'), ('email', 'nobody@example.org'),
    ('code', 'x!=nil'), ('path', '/tmp/ghbdtn'), ('path', '~/Documents/test.txt'),
    ('punctuation', 'ghbdtn!'), ('punctuation', '(руддщ)'),
]
challenge_order = sorted(range(len(challenges)), key=lambda i: digest('challenge:' + challenges[i][1]))
challenge_train = set(challenge_order[:len(challenges) * 7 // 10])
for i, (category, value) in enumerate(challenges):
    rows.append(dict(schemaVersion=1, id=f'challenge-{i:03}', feature='conservative-context',
                     split='train' if i in challenge_train else 'holdout', category=category,
                     provenance='hand-authored conservative expectation; not observed Caramba behavior; root=challenge:' + value,
                     input=value, expected=value, originalResult=None, events=None))
baseline = [json.loads(line) for line in (ROOT / 'corpus/synthetic-v1.jsonl').read_text().splitlines()]
baseline_by_key = {(r['provenance'], r['category']): r for r in baseline}
for row in rows:
    previous = baseline_by_key.get((row['provenance'], row['category']))
    if previous is not None:
        row['id'] = previous['id']
        assert row['split'] == previous['split'], 'Baseline split must not change'
rows.sort(key=lambda row: row['id'])
out = ROOT / 'corpus/synthetic-v2.jsonl'
out.parent.mkdir(exist_ok=True)
out.write_text(''.join(json.dumps(row, ensure_ascii=False, sort_keys=True) + '\n' for row in rows))
summary = dict(schemaVersion=1, rows=len(rows), split=dict(Counter(r['split'] for r in rows)),
               categories=dict(Counter(r['category'] for r in rows)),
               sha256=hashlib.sha256(out.read_bytes()).hexdigest(), lexiconSha256=hashlib.sha256((ROOT / 'Sources/LayoutPilotCore/Resources/lexicon.json').read_bytes()).hexdigest(),
               originalObservations=0, notice='Offline consistency only. No independent language quality or live equivalence claim.')
(ROOT / 'corpus/manifest-v2.json').write_text(json.dumps(summary, ensure_ascii=False, indent=2) + '\n')
print(json.dumps(summary, ensure_ascii=False, indent=2))
