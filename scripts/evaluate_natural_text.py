#!/usr/bin/env python3
"""Independent offline quality check on natural text (not a fixture corpus).

For every text: (1) correctly typed text must stay unchanged — a changed token is a false
layout or case correction (intended ё restoration is counted separately); (2) the same text retyped with the other layout's physical keys
(whole token, punctuation included) should come back — recall over eligible word tokens.
Texts stay in research/private; only aggregate counts and short word examples are reported.
"""
import argparse
import collections
import hashlib
import json
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
# Same authored physical-key table as Layout.Mapping.standardPC.
LATIN = "`qwertyuiop[]asdfghjkl;'zxcvbnm,./~QWERTYUIOP{}ASDFGHJKL:\"ZXCVBNM<>?@#$^&|"
CYRILLIC = 'ёйцукенгшщзхъфывапролджэячсмитьбю.ЁЙЦУКЕНГШЩЗХЪФЫВАПРОЛДЖЭЯЧСМИТЬБЮ,"№;:?/'
TO_RUSSIAN = str.maketrans(LATIN, CYRILLIC)
TO_ENGLISH = str.maketrans(CYRILLIC, LATIN)
LETTERS = {'en': set('abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ'),
           'ru': set('абвгдеёжзийклмнопрстуфхцчшщъыьэюяАБВГДЕЁЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯ')}


def rewrite(cli, text):
    with tempfile.NamedTemporaryFile('w', suffix='.txt', delete=False, encoding='utf-8') as handle:
        handle.write(text)
    try:
        return subprocess.run([cli, 'rewrite', handle.name], check=True, capture_output=True, text=True).stdout
    finally:
        Path(handle.name).unlink()


def eligible(token, language):
    """A word of at least three letters with optional trailing sentence punctuation."""
    word = token.rstrip('.,!?;:')
    return len(word) >= 3 and all(c in LETTERS[language] for c in word)


def evaluate(cli, path, language, examples):
    text = path.read_text(encoding='utf-8-sig').replace('\r\n', '\n')
    tokens = text.split()
    rewritten = rewrite(cli, text).split()
    assert len(rewritten) == len(tokens), path
    changed = collections.Counter((a, b) for a, b in zip(tokens, rewritten) if a != b)
    def kind(a, b):
        if b.replace('ё', 'е').replace('Ё', 'Е') == a:
            return 'yo'          # intended ё restoration, reported separately
        if a.lower() == b.lower():
            return 'case'        # double-capital rule
        return 'layout'          # a correct word converted to the other layout
    by_kind = {k: collections.Counter() for k in ('yo', 'case', 'layout')}
    for (a, b), n in changed.items():
        by_kind[kind(a, b)][(a, b)] += n
    wrong_text = text.translate(TO_ENGLISH if language == 'ru' else TO_RUSSIAN)
    wrong = wrong_text.split()
    restored = rewrite(cli, wrong_text).split()
    assert len(wrong) == len(restored) == len(tokens), path
    total = recovered = 0
    misses = collections.Counter()
    for original, typed, result in zip(tokens, wrong, restored):
        if not eligible(original, language):
            continue
        total += 1
        if result == original:
            recovered += 1
        else:
            misses[original.rstrip('.,!?;:').lower()] += 1
    return {
        'file': path.name, 'language': language, 'sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
        'tokens': len(tokens),
        'falseLayout': sum(by_kind['layout'].values()), 'falseCase': sum(by_kind['case'].values()),
        'yoRestorations': sum(by_kind['yo'].values()),
        'falseCorrections': sum(by_kind['layout'].values()) + sum(by_kind['case'].values()),
        'falsePer100kTokens': round((sum(by_kind['layout'].values()) + sum(by_kind['case'].values())) * 100000 / max(1, len(tokens)), 2),
        'falseLayoutExamples': [f'{a} → {b} ×{n}' for (a, b), n in by_kind['layout'].most_common(examples)],
        'falseCaseExamples': [f'{a} → {b} ×{n}' for (a, b), n in by_kind['case'].most_common(examples)],
        'yoExamples': [f'{a} → {b} ×{n}' for (a, b), n in by_kind['yo'].most_common(10)],
        'eligibleWrongLayoutTokens': total, 'recovered': recovered,
        'recall': round(recovered / max(1, total), 4),
        'topMissedWords': [f'{w} ×{n}' for w, n in misses.most_common(examples)],
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--cli', default=str(ROOT / '.build/debug/layoutpilot-cli'))
    parser.add_argument('--text', action='append', required=True, help='LANG:PATH, LANG is en or ru')
    parser.add_argument('--examples', type=int, default=25)
    parser.add_argument('--label', required=True)
    parser.add_argument('--out', required=True)
    args = parser.parse_args()
    lexicon = ROOT / 'Sources/LayoutPilotCore/Resources/lexicon.json'
    rows = []
    for item in args.text:
        language, path = item.split(':', 1)
        assert language in LETTERS, item
        rows.append(evaluate(args.cli, Path(path), language, args.examples))
    totals = {}
    for language in sorted({r['language'] for r in rows}):
        part = [r for r in rows if r['language'] == language]
        tokens = sum(r['tokens'] for r in part)
        false = sum(r['falseCorrections'] for r in part)
        total = sum(r['eligibleWrongLayoutTokens'] for r in part)
        recovered = sum(r['recovered'] for r in part)
        totals[language] = {'tokens': tokens, 'falseCorrections': false,
                            'falseLayout': sum(r['falseLayout'] for r in part),
                            'falseCase': sum(r['falseCase'] for r in part),
                            'yoRestorations': sum(r['yoRestorations'] for r in part),
                            'falsePer100kTokens': round(false * 100000 / max(1, tokens), 2),
                            'eligibleWrongLayoutTokens': total, 'recovered': recovered,
                            'recall': round(recovered / max(1, total), 4)}
    report = {'schemaVersion': 1, 'label': args.label,
              'kind': 'offline natural-text check through layoutpilot-cli rewrite; not native, not original parity',
              'lexiconSha256': hashlib.sha256(lexicon.read_bytes()).hexdigest(),
              'totals': totals, 'files': rows}
    Path(args.out).write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps(totals, ensure_ascii=False))


if __name__ == '__main__':
    main()
