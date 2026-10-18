#!/usr/bin/env python3
"""Synthetic consistency corpus v3 for the expanded lexicon; never calls the decision engine.

v2 stays a frozen regression set (do not regenerate it: its generator reads the current
lexicon). v3 draws roots from the expanded lexicon with an independent salt; the holdout is
fixed by the manifest digest before the first evaluation and is never used for tuning.
Expectations encode the specification, not observed engine output.
"""
import hashlib
import json
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LEXICON = ROOT / 'Sources/LayoutPilotCore/Resources/lexicon.json'
lex = json.loads(LEXICON.read_text())
LATIN = "`qwertyuiop[]asdfghjkl;'zxcvbnm,./~QWERTYUIOP{}ASDFGHJKL:\"ZXCVBNM<>?@#$^&|"
CYRILLIC = 'ёйцукенгшщзхъфывапролджэячсмитьбю.ЁЙЦУКЕНГШЩЗХЪФЫВАПРОЛДЖЭЯЧСМИТЬБЮ,"№;:?/'
SALT = 'v3:'
ROOTS = 2000


def digest(value):
    return hashlib.sha256((SALT + value).encode()).hexdigest()


def convert(word, language):
    return word.translate(str.maketrans(LATIN, CYRILLIC) if language == 'english' else str.maketrans(CYRILLIC, LATIN))


known = {'english': set(lex['english']), 'russian': set(lex['russian'])}
other = {'english': 'russian', 'russian': 'english'}
groups = {}
for language in ['english', 'russian']:
    for word in lex[language]:
        wrong = convert(word, language)
        # Unambiguous roots only: the wrong-layout form must not itself be a known word.
        if len(word) >= 3 and wrong.isalpha() and wrong not in known[other[language]]:
            groups.setdefault(language + ':' + word.replace('ё', 'е'), (language, word))
selected = sorted(groups, key=digest)[:ROOTS]
train = set(selected[:len(selected) * 7 // 10])


def doublecaps_expected(word, normalized):
    # Specification: two capitals + plural s on a three-letter word is an acronym plural.
    if len(word) == 3 and word[2] == 's':
        return word[:2].upper() + word[2:]
    return normalized.capitalize()


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
        ('doublecaps', word[:2].upper() + word[2:], doublecaps_expected(word, normalized)),
        ('digits', wrong + '123', wrong + '123'),
        ('url', 'https://' + wrong + '.example/test', 'https://' + wrong + '.example/test'),
        ('email', wrong + '@example.test', wrong + '@example.test'),
        ('code', 'let_' + wrong + '=1', 'let_' + wrong + '=1'),
        ('mixed', 'A' + word + 'я', 'A' + word + 'я'),
    ]
    for category, value, expected in variants:
        rows.append(dict(schemaVersion=1, id='v3-' + digest(group)[:12] + '-' + category, feature='automatic-layout',
                         split='train' if group in train else 'holdout', category=category,
                         provenance='synthetic lexicon consistency v3; authored standard physical mapping; root=' + group,
                         input=value, expected=expected, originalResult=None, events=None))
rows.sort(key=lambda row: row['id'])
out = ROOT / 'corpus/synthetic-v3.jsonl'
out.write_text(''.join(json.dumps(row, ensure_ascii=False, sort_keys=True) + '\n' for row in rows))
summary = dict(schemaVersion=1, rows=len(rows), roots=len(selected), split=dict(Counter(r['split'] for r in rows)),
               categories=dict(Counter(r['category'] for r in rows)),
               sha256=hashlib.sha256(out.read_bytes()).hexdigest(),
               lexiconSha256=hashlib.sha256(LEXICON.read_bytes()).hexdigest(),
               originalObservations=0,
               notice='Offline consistency only, roots from the expanded lexicon. No independent language quality or live equivalence claim.')
(ROOT / 'corpus/manifest-v3.json').write_text(json.dumps(summary, ensure_ascii=False, indent=2) + '\n')
print(json.dumps({k: summary[k] for k in ['rows', 'roots', 'split', 'sha256']}, ensure_ascii=False))
