#!/usr/bin/env python3
"""Deterministic lexicon build: frequency ranking × spelling validity.

Sources (see docs/LEXICON.md for licenses, versions and SHA-256):
  * ranking  — FrequencyWords 2018 (OpenSubtitles), en_50k.txt / ru_50k.txt, CC BY-SA 4.0;
  * validity — SCOWL 2020.12.07 english-words/american-words lists (EN) and
               Hunspell ru_RU by A. Lebedev (RU), checked with the hunspell binary.
Rules are general and never tuned to single fixtures:
  1. letters of one script only, 2…24 characters (two-letter words such as it/он only
     mark known words; decisions still need three characters), lowercase as in the ranking lists;
  2. the word must be valid in its spelling source (names and lowercase proper nouns fail);
  3. the first --top-en / --top-ru valid words of each language by frequency;
  4. pair protection: when the other-layout conversion of a selected word is itself a valid
     word of the other language, that conversion is added too, so neither is ever converted;
  5. frequency dominance: when both words of a cross-layout pair are present and one is at
     least --dominance times more frequent (relative frequency in its own ranking list; a word
     absent from a list gets that list's cut-off frequency as an upper bound), the rarer
     non-authored word is dropped, so typing it converts to the common
     word (tot → ещё). Pairs of comparable frequency keep both words protected;
  6. the independently authored words, typos and ё entries of the current lexicon are kept.
"""
import argparse
import hashlib
import json
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LATIN = "`qwertyuiop[]asdfghjkl;'zxcvbnm,./~QWERTYUIOP{}ASDFGHJKL:\"ZXCVBNM<>?@#$^&|"
CYRILLIC = 'ёйцукенгшщзхъфывапролджэячсмитьбю.ЁЙЦУКЕНГШЩЗХЪФЫВАПРОЛДЖЭЯЧСМИТЬБЮ,"№;:?/'
TO_RUSSIAN = str.maketrans(LATIN, CYRILLIC)
TO_ENGLISH = str.maketrans(CYRILLIC, LATIN)
EN = set('abcdefghijklmnopqrstuvwxyz')
RU = set('абвгдеёжзийклмнопрстуфхцчшщъыьэюя')
SCOWL_LEVELS = [10, 20, 35, 40, 50, 55, 60, 70]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def relative_frequency(path):
    counts = {}
    for line in path.read_text(encoding='utf-8').splitlines():
        word, count = line.rsplit(' ', 1)
        counts[word] = int(count)
    total = sum(counts.values())
    return {word: count / total for word, count in counts.items()}, min(counts.values()) / total


def ranked(path, letters):
    words = []
    for line in path.read_text(encoding='utf-8').splitlines():
        word = line.split(' ', 1)[0]
        if 2 <= len(word) <= 24 and all(c in letters for c in word):
            words.append(word)
    return words


def scowl_words(directory):
    words = set()
    for prefix in ['english-words', 'american-words']:
        for level in SCOWL_LEVELS:
            path = directory / f'{prefix}.{level}'
            if path.exists():
                for word in path.read_text(encoding='latin-1').split():
                    if all(c in EN for c in word):
                        words.add(word)
    return words


def hunspell_valid(words, dictionary):
    """Return the subset of words that hunspell -l does not report as misspelled."""
    words = sorted(set(words))
    result = subprocess.run(['hunspell', '-d', str(dictionary), '-l', '-i', 'utf-8'], input='\n'.join(words) + '\n',
                            capture_output=True, text=True, check=True)
    misspelled = set(result.stdout.split())
    return {w for w in words if w not in misspelled}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--sources', default=str(ROOT / 'research/private/lexicon-sources'))
    parser.add_argument('--top-en', type=int, default=30000)
    parser.add_argument('--top-ru', type=int, default=30000)
    parser.add_argument('--dominance', type=float, default=100.0)
    parser.add_argument('--out', default=str(ROOT / 'Sources/LayoutPilotCore/Resources/lexicon.json'))
    parser.add_argument('--authored', default=str(ROOT / 'research/lexicon/authored-lexicon.json'))
    parser.add_argument('--report', required=True)
    args = parser.parse_args()
    src = Path(args.sources)
    authored = json.loads(Path(args.authored).read_text(encoding='utf-8'))
    scowl = scowl_words(src / 'scowl/final')
    en_ranked = ranked(src / 'en_50k.txt', EN)
    ru_ranked = ranked(src / 'ru_50k.txt', RU)
    ru_valid = hunspell_valid(ru_ranked, src / 'ru_RU')
    english = [w for w in en_ranked if w in scowl][:args.top_en]
    russian = [w for w in ru_ranked if w in ru_valid][:args.top_ru]
    english_set, russian_set = set(english), set(russian)
    # Pair protection in both directions, validated by the full spelling sources.
    en_from_ru = {w.translate(TO_ENGLISH) for w in russian_set | set(authored['russian'])}
    en_pairs = {w for w in en_from_ru if all(c in EN for c in w) and w in scowl} - english_set
    ru_from_en = {w.translate(TO_RUSSIAN) for w in english_set | set(authored['english'])}
    ru_candidates = {w for w in ru_from_en if all(c in RU for c in w)}
    ru_pairs = hunspell_valid(ru_candidates, src / 'ru_RU') - russian_set
    english_all = english_set | en_pairs | set(authored['english'])
    russian_all = russian_set | ru_pairs | set(authored['russian'])
    (en_freq, en_floor), (ru_freq, ru_floor) = relative_frequency(src / 'en_50k.txt'), relative_frequency(src / 'ru_50k.txt')
    dropped = []
    for ru_word in sorted(russian_all):
        en_word = ru_word.translate(TO_ENGLISH)
        if en_word not in english_all:
            continue
        fr, fe = ru_freq.get(ru_word, ru_floor), en_freq.get(en_word, en_floor)
        if fr >= args.dominance * fe and en_word not in authored['english']:
            english_all.discard(en_word); dropped.append(f'{en_word} (en {fe:.2e}) → {ru_word} (ru {fr:.2e})')
        elif fe >= args.dominance * fr and ru_word not in authored['russian']:
            russian_all.discard(ru_word); dropped.append(f'{ru_word} (ru {fr:.2e}) → {en_word} (en {fe:.2e})')
    english_final = sorted(english_all)
    russian_final = sorted(russian_all)
    lexicon = {'english': english_final, 'russian': russian_final,
               'typos': authored['typos'], 'yo': authored['yo']}
    out = Path(args.out)
    out.write_text(json.dumps(lexicon, ensure_ascii=False, indent=0, sort_keys=True) + '\n', encoding='utf-8')
    report = {
        'schemaVersion': 1, 'topEnglish': args.top_en, 'topRussian': args.top_ru, 'dominance': args.dominance, 'scowlLevels': SCOWL_LEVELS,
        'sources': {name: sha(src / name) for name in ['en_50k.txt', 'ru_50k.txt', 'ru_RU.dic', 'ru_RU.aff', 'scowl.tar.gz']},
        'authoredSha256': sha(Path(args.authored)),
        'counts': {'englishRankedLetters': len(en_ranked), 'englishValid': len([w for w in en_ranked if w in scowl]),
                   'russianRankedLetters': len(ru_ranked), 'russianValid': len(ru_valid),
                   'englishSelected': len(english), 'russianSelected': len(russian),
                   'englishPairProtection': len(en_pairs), 'russianPairProtection': len(ru_pairs),
                   'englishFinal': len(english_final), 'russianFinal': len(russian_final)},
        'dominanceDropped': dropped,
        'pairProtectionExamples': {'english': sorted(en_pairs)[:40], 'russian': sorted(ru_pairs)[:40]},
        'lexiconSha256': sha(out), 'lexiconBytes': out.stat().st_size,
    }
    Path(args.report).write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps(report['counts'], ensure_ascii=False))


if __name__ == '__main__':
    main()
