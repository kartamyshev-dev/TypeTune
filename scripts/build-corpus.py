#!/usr/bin/env python3
"""Validate and measure TypeTune auto-corpus against current frequency policy.

Mirrors crates/typetune-engine known_correction gates well enough to check
that generated negatives would not introduce false positives, and to report
predicted recall before running the Rust harness.

Usage:
  python3 scripts/build-corpus.py --check
  python3 scripts/build-corpus.py --generate   # rewrite data/auto-corpus.tsv from word lists
"""
from __future__ import annotations

import argparse
import math
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "crates/typetune-engine/data"
FREQ = DATA / "frequency"
FREQ_N = 50_000.0

# Keep in sync with crates/typetune-engine/src/manual.rs
US = "`qwertyuiop[]asdfghjkl;'zxcvbnm,.~QWERTYUIOP{}ASDFGHJKL:\"ZXCVBNM<>"
RU = "ёйцукенгшщзхъфывапролджэячсмитьбюЁЙЦУКЕНГШЩЗХЪФЫВАПРОЛДЖЭЯЧСМИТЬБЮ"
assert len(US) == len(RU) == 66


def load_freq(lang: str) -> dict[str, int]:
    ranks: dict[str, int] = {}
    for i, line in enumerate((FREQ / f"{lang}_50k.txt").read_text().splitlines(), 1):
        word, _cnt = line.rsplit(" ", 1)
        ranks[word] = i
    return ranks


def load_leeds() -> dict[str, int]:
    ranks: dict[str, int] = {}
    for i, line in enumerate((FREQ / "leeds_ru_50k.txt").read_text().splitlines(), 1):
        word = line.strip()
        if word:
            ranks[word] = i
    return ranks


def load_tech(lang: str) -> list[str]:
    out = []
    for line in (DATA / "tech" / f"{lang}.txt").read_text().splitlines():
        w = line.strip()
        if w and not w.startswith("#"):
            out.append(w)
    return out


def tech_rank(word: str) -> int:
    return 50 if len(word) <= 2 else 100


def apply_min(words: dict[str, int], word: str, rank: int) -> None:
    if word not in words or rank < words[word]:
        words[word] = rank


def load_pilot(lang: str) -> set[str]:
    return set((DATA / f"{lang}.txt").read_text().splitlines())


EN = load_freq("en")
RU_F = load_freq("ru")
# Mirror crates/typetune-engine/build.rs merge: Leeds secondary + tech boosts + EN plurals.
for w, r in load_leeds().items():
    apply_min(RU_F, w, r)
for lang, ranks in (("en", EN), ("ru", RU_F)):
    for w in load_tech(lang):
        apply_min(ranks, w, tech_rank(w))
_en_lemmas = [(w, r) for w, r in list(EN.items()) if r <= 15_000 and len(w) >= 3]
for lemma, rank in _en_lemmas:
    forms = [lemma + "s", lemma + "es"]
    if lemma.endswith("y") and len(lemma) > 1 and lemma[-2] not in "aeiou":
        forms.append(lemma[:-1] + "ies")
    for form in forms:
        if form.isascii() and form.isalpha() and form.islower() and 1 <= len(form) <= 32:
            apply_min(EN, form, rank + 500)
PILOT_EN = load_pilot("en")
PILOT_RU = load_pilot("ru")


def map_word(src: str, table_from: str, table_to: str) -> str | None:
    out = []
    for c in src:
        i = table_from.find(c)
        if i < 0:
            return None
        out.append(table_to[i])
    return "".join(out)


def ru_typed(expected_ru: str) -> str | None:
    """Russian word typed while US layout is active."""
    return map_word(expected_ru, RU, US)


def en_typed(expected_en: str) -> str | None:
    """English word typed while RU layout is active."""
    return map_word(expected_en, US, RU)


def is_cyrillic(s: str) -> bool:
    return any(("а" <= c <= "я") or c == "ё" for c in s.lower())


def score_from_rank(rank: int) -> float:
    """ADR-010: ln(N/rank), N = 50_000 (mirror automatic.rs)."""
    return math.log(FREQ_N / rank)


def min_score(length: int) -> float:
    if length == 2:
        min_rank = 100.0  # ln(500)
    elif length == 3:
        min_rank = 1_000.0  # ln(50)
    else:
        min_rank = 20_000.0  # ln(2.5)
    return math.log(FREQ_N / min_rank)


def threshold_ok(length: int, rank: int | None, pilot: bool) -> bool:
    if length == 1:
        return False
    if rank is not None and score_from_rank(rank) + 1e-12 >= min_score(length):
        return True
    return length >= 4 and pilot


def swap_yo_e(s: str) -> str:
    return s.translate(str.maketrans("еёЕЁ", "ёеЁЕ"))


def full_yo_e_ambiguous(words: dict[str, int], pilot: set[str], form: str) -> bool:
    """ADR-010: ≥2 е/ё orthographic variants in the target lexicon → refuse."""
    chars = list(form)
    positions = [i for i, c in enumerate(chars) if c in "её"]
    if not positions or len(positions) > 12:
        return False
    hits = 0
    for mask in range(1 << len(positions)):
        variant = chars[:]
        for bit, idx in enumerate(positions):
            variant[idx] = "ё" if mask & (1 << bit) else "е"
        if "".join(variant) in words or "".join(variant) in pilot:
            hits += 1
            if hits >= 2:
                return True
    return False


def prohibited_token(word: str) -> bool:
    """Mirror automatic.rs prohibited_token (D3 full-token URL/code guards)."""
    return (
        "://" in word
        or "@" in word
        or "/" in word
        or "\\" in word
        or "::" in word
        or "_" in word
        or "-" in word
        or any(c.isdigit() for c in word)
        or word.startswith(":")
    )


EDGE_PUNCT = set(".,;:!?()\"'«»…–—")


def split_edge_punct(word: str) -> tuple[str, str, str]:
    i = 0
    while i < len(word) and word[i] in EDGE_PUNCT:
        i += 1
    lead, rest = word[:i], word[i:]
    j = len(rest)
    while j > 0 and rest[j - 1] in EDGE_PUNCT:
        j -= 1
    return lead, rest[:j], rest[j:]


def source_protected(word: str) -> bool:
    w = word.lower()
    wa = swap_yo_e(w)
    return (
        w in EN
        or w in RU_F
        or wa in EN
        or wa in RU_F
        or w in PILOT_EN
        or w in PILOT_RU
        or wa in PILOT_EN
        or wa in PILOT_RU
    )


def threshold_ok(length: int, rank: int | None, pilot: bool) -> bool:
    if length == 1:
        return False
    if length == 2:
        return rank is not None and rank <= 100
    if length == 3:
        return rank is not None and rank <= 1000
    return (rank is not None and rank <= 20_000) or pilot


def target_ok(expected: str, length: int) -> bool:
    cand = expected.lower()
    alt = swap_yo_e(cand)
    if is_cyrillic(cand):
        words, pilot_w = RU_F, PILOT_RU
    else:
        words, pilot_w = EN, PILOT_EN
    # Full ё/е ambiguity (ADR-010): ≥2 orthographic variants → no automatic.
    if full_yo_e_ambiguous(words, pilot_w, cand):
        return False
    return threshold_ok(length, words.get(cand), cand in pilot_w) or threshold_ok(
        length, words.get(alt), alt in pilot_w
    )


def would_correct(inp: str, expected: str) -> bool:
    """Approximate known_correction for a corpus positive row (input+space)."""
    token = inp.rstrip(" ")
    if not (2 <= len(token) <= 32):
        return False
    if prohibited_token(token):
        return False
    # case gate: lower / upper / Title on alphabetic chars
    alpha = [c for c in token if c.isalpha()]
    if not alpha:
        return False
    lower = all(c.islower() for c in alpha)
    upper = all(c.isupper() for c in alpha)
    title = alpha[0].isupper() and all(c.islower() for c in alpha[1:])
    if not (lower or upper or title):
        return False
    if source_protected(token):
        return False
    # Full token first (expected without edge punct when token has none).
    if target_ok(expected, len(token)):
        return True
    # Edge-punct core fallback (D3): rank-check the alphabetic bodies.
    lead, core, trail = split_edge_punct(token)
    if not core or len(core) == len(token) or not (2 <= len(core) <= 32):
        return False
    if source_protected(core):
        return False
    _el, exp_core, _er = split_edge_punct(expected)
    return target_ok(exp_core, len(core))


# Curated positive targets (correct words in the intended language).
# Split label is assigned deterministically: every 2nd line-ish alternating
# while keeping paired negatives in the same split bucket as their positive
# when generated together.

RU_POSITIVE = [
    # greetings / politeness
    "привет", "здравствуйте", "пожалуйста", "спасибо", "извините", "свидания",
    "хорошо", "плохо", "да", "нет", "может", "надо", "нужно", "хочу", "можно",
    # time
    "сегодня", "вчера", "завтра", "утром", "вечером", "ночью", "днем", "время",
    "час", "минута", "секунда", "неделя", "месяц", "год",
    # people / family
    "человек", "люди", "ребенок", "дети", "муж", "жена", "друг", "подруга",
    "семья", "родители", "брат", "сестра", "сын", "дочь",
    # common verbs (present/frequent forms)
    "работает", "работали", "работаем", "делает", "сделал", "сделает",
    "говорит", "говорили", "пишет", "читает", "слушает", "смотрит",
    "идет", "идут", "ездит", "летит", "бежит", "стоит", "сидит",
    "знает", "знали", "помнит", "думает", "хочет", "любит", "боится",
    "открыл", "закрыл", "включил", "выключил", "нажал", "выбрал",
    "сохранил", "сохранить", "удалил", "скопировал", "вставил",
    "отправил", "получил", "открыл", "запустил", "остановил",
    # nouns everyday
    "документ", "документы", "документами", "файл", "файлы", "папка", "папки",
    "компьютер", "компьютеры", "клавиатура", "клавиатуры", "мышь", "монитор",
    "экран", "окно", "окна", "программа", "программы", "приложение", "приложения",
    "система", "системы", "проект", "проекты", "задача", "задачи",
    "встреча", "встречу", "встречи", "сообщение", "сообщения", "письмо",
    "телефон", "машина", "дом", "дома", "комната", "улица", "город",
    "страна", "мир", "жизнь", "история", "вопрос", "ответ", "причина",
    "результат", "пример", "способ", "метод", "правило", "версия",
    # tech / settings vocabulary
    "настройки", "настройками", "настройка", "настройкой", "конфигурация",
    "переключение", "переключения", "переключатель", "раскладка", "раскладки",
    "исправление", "исправления", "исправить", "ошибка", "ошибки",
    "сохранение", "сохранения", "загрузка", "установка", "удаление",
    "запуск", "остановка", "пауза", "продолжить", "начать", "закончить",
    "проверка", "проверку", "проверки", "проверить", "тест", "тесты",
    "словарь", "словаря", "словари", "слово", "слова", "текст", "текста",
    "фраза", "фразы", "ввод", "ввода", "вывод", "результат",
    "пользователь", "пользователи", "администратор", "разработчик",
    # adjectives
    "русский", "английский", "русские", "английские", "новый", "новые",
    "старый", "большой", "маленький", "быстрый", "медленный", "простой",
    "сложно", "важно", "нужно", "готов", "готовы", "активен", "выключен",
    # short / frequent (may rely on top-100/1000)
    "как", "что", "где", "кто", "это", "был", "была", "были", "они",
    "мы", "вы", "он", "она", "оно", "тут", "там", "вот", "уже", "еще",
    "тоже", "так", "вот", "чтобы", "потому", "поэтому", "однако",
    # ambiguous-looking but still positives for recall measurement
    "еще", "все", "сам", "самый", "новее", "другой", "другие",
    # forms often missing from subtitle lists
    "клавиатурами", "раскладками", "пользователями", "разработчиков",
    "настройками", "переключателями", "исправлениями", "сохранениями",
]

EN_POSITIVE = [
    "hello", "world", "meeting", "meetings", "document", "documents",
    "keyboard", "keyboards", "application", "applications", "working",
    "worked", "works", "work", "testing", "tests", "test", "settings",
    "setting", "correction", "corrections", "message", "messages",
    "tomorrow", "yesterday", "evening", "morning", "night", "today",
    "computer", "computers", "saving", "saved", "save", "switching",
    "switch", "language", "languages", "development", "developer",
    "developers", "information", "important", "available", "different",
    "because", "together", "between", "welcome", "please", "thanks",
    "sorry", "goodbye", "yes", "no", "maybe", "should", "would",
    "could", "must", "want", "need", "help", "show", "hide", "open",
    "close", "start", "stop", "pause", "resume", "create", "delete",
    "update", "upgrade", "install", "remove", "download", "upload",
    "file", "files", "folder", "folders", "screen", "window", "windows",
    "program", "programs", "system", "project", "projects", "task",
    "tasks", "result", "results", "example", "method", "methods",
    "version", "versions", "error", "errors", "check", "checking",
    "user", "users", "admin", "password", "username", "email",
    "network", "server", "client", "buffer", "cache", "memory",
    "process", "thread", "threads", "queue", "list", "item", "items",
    "value", "values", "number", "text", "string", "button", "menu",
    "options", "config", "configure", "enabled", "disabled", "active",
    "ready", "failed", "success", "warning", "status", "state",
    # short frequent
    "the", "and", "for", "you", "are", "with", "this", "that", "from",
    "have", "has", "had", "not", "but", "all", "any", "can", "will",
    "one", "two", "out", "get", "got", "new", "old", "now", "then",
    "here", "there", "when", "what", "who", "why", "how", "our", "your",
    # plurals / forms
    "files", "folders", "errors", "checks", "users", "servers",
    "clients", "buffers", "caches", "values", "strings", "buttons",
    "menus", "configs", "states", "status",  # status is mass-ish
]

# Documented gap rows from stage 40 (must remain present after regeneration).
# D4: full ё/е ambiguity flips these positives to negatives (ADR-010).
AMBIGUOUS_INPUTS = {"to`", "ht,tyjr"}


def fix_known_gaps() -> list[tuple[str, str, str]]:
    rows = []
    for split, inp, exp in [
        ("dev", "rkfdbfnehs", "клавиатуры"),
        ("holdout", "yfcnhjqrfvb", "настройками"),
        ("holdout", "bcghfdktybz", "исправления"),
        ("holdout", "cj[hfytybt", "сохранение"),
        ("dev", "gthtrk.xtybz", "переключения"),
        ("holdout", "лунищфквы", "keyboards"),
        # D3 boundary punctuation (edge strip + restore).
        ("dev", "ghbdtn,", "привет,"),
        ("holdout", "ghbdtn.", "привет."),
        ("dev", "(ghbdtn)", "(привет)"),
        ("holdout", "ghbdtn...", "привет..."),
        ("dev", "Ghbdtn,", "Привет,"),
        ("holdout", ".ghbdtn", ".привет"),
        # D3 ё target; D4: ещё/еще both in lexicon → ambiguity negative.
        ("holdout", "to`", "ещё"),
    ]:
        rows.append((split, inp, exp))
    return rows


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="validate existing corpus")
    parser.add_argument("--generate", action="store_true", help="regenerate corpus")
    args = parser.parse_args()

    if args.check or not args.generate:
        rows = []
        for line in (DATA / "auto-corpus.tsv").read_text().splitlines():
            if not line or line.startswith("#"):
                continue
            rows.append(line.split("\t"))
        pos = neg = miss = fp = 0
        for split, kind, inp, exp in rows:
            if kind == "positive":
                pos += 1
                if not would_correct(inp, exp):
                    miss += 1
            else:
                neg += 1
                # negative: input should equal expected (no correction)
                # We only approximate positives; negatives need Rust harness for FP.
        print(f"rows={len(rows)} positive={pos} negative={neg} predicted_miss>={miss}")
        print("note: false positives require the Rust corpus harness")
        if not args.generate:
            return 0

    if not args.generate:
        return 0

    # Build positives + paired negatives (correct-layout words stay unchanged).
    out: list[tuple[str, str, str, str]] = []  # split kind input expected

    def split_for(i: int) -> str:
        return "dev" if i % 5 < 2 else "holdout"  # ~40% dev / 60% holdout

    def add_pair(inp: str, exp: str, i: int) -> None:
        split = split_for(i)
        out.append((split, "positive", inp, exp))
        # negative twin: correctly typed expected word
        correct = exp if is_cyrillic(exp) else exp
        # for RU expected, correct typing with RU layout is the word itself
        # for EN expected, correct typing with EN layout is the word itself
        out.append((split, "negative", correct, correct))

    n = 0
    seen_pos: set[str] = set()
    for exp in RU_POSITIVE + EN_POSITIVE:
        key = exp.lower()
        if key in seen_pos:
            continue
        seen_pos.add(key)
        if is_cyrillic(exp):
            inp = ru_typed(exp)
            if inp is None:
                print(f"skip unmapped RU {exp}", file=sys.stderr)
                continue
        else:
            inp = en_typed(exp)
            if inp is None:
                print(f"skip unmapped EN {exp}", file=sys.stderr)
                continue
        # D4 full ё/е ambiguity: wrong-layout form must stay unchanged.
        if inp in AMBIGUOUS_INPUTS:
            out.append((split_for(n), "negative", inp, inp))
            out.append((split_for(n), "negative", exp, exp))
            n += 1
            continue
        # Preserve case only for Title/upper patterns the matcher accepts.
        add_pair(inp, exp, n)
        n += 1

    # Always include documented gap rows (same as curated, skip dups).
    for split, inp, exp in fix_known_gaps():
        if (split, "positive", inp, exp) in out:
            continue
        if inp in AMBIGUOUS_INPUTS:
            out.append((split, "negative", inp, inp))
            out.append((split, "negative", exp, exp))
            continue
        out.append((split, "positive", inp, exp))
        out.append((split, "negative", exp, exp))

    # Extra negatives: identifiers, URLs, paths, mixed script, punctuation tokens.
    extra_neg = [
        "hello@example.com",
        "https://example.com/path",
        "/usr/bin/typetune",
        "foo::bar_baz",
        "TypeTune",
        "OpenAI",
        "GitHub",
        "Python",
        "VSCode",
        "Ctrl+C",
        "myVarName",
        "snake_case_name",
        "kebab-case-name",
        "привеt",  # mixed script
        "qwerty",
        "asdfgh",
        "руддщ42",
        "ghbdtn_",
        "GhBdTn",
        "London",
        "Москва",
        "New York",
        "UTF-8",
        "x86_64",
        "JSON",
        "HTTP",
        "localhost:8080",
        "user@host",
        "C:\\Users\\test",
        "1.2.3.4",
        "null",
        "true",
        "false",
        "enum",
        "struct",
        "impl",
        "match",
        # D3 full-token URL/code (edge strip must not enable correction).
        "ghbdtn.com",
        "example.com",
        "ghbdtn.com,",
        # D3 ё/е ambiguity negatives: both target spellings in the lexicon → no auto.
        "lytv",
        "bltn",
        "dct",
        # D4 full orthographic ё/е (ADR-010): ещё/еще, все/всё, ребенок/ребёнок.
        "to`",
        "ht,tyjr",
        "есть",  # correct RU common
        "быть",
        "можно",
        "очень",
        "просто",
        "какой",
        "этот",
        "потом",
        "сейчас",
        "когда",
        "почему",
        "through",
        "though",
        "thought",
        "people",
        "another",
        "between",
        "question",
        "something",
        "anything",
        "everything",
        "shoulder",
        "mother",
        "father",
        "brother",
        "winter",
        "summer",
        "spring",
        "autumn",
    ]
    for i, w in enumerate(extra_neg):
        split = split_for(i + 1000)
        out.append((split, "negative", w, w))

    # Guard: every negative input must equal expected (unchanged contract).
    for split, kind, inp, exp in out:
        if kind == "negative" and inp != exp:
            raise SystemExit(f"negative mismatch: {inp!r} != {exp!r}")

    # Deduplicate rows while preserving order.
    unique: list[tuple[str, str, str, str]] = []
    seen: set[tuple[str, str, str]] = set()
    for row in out:
        key = (row[1], row[2], row[3])
        if key in seen:
            continue
        seen.add(key)
        unique.append(row)

    header = "# split\tkind\tinput\texpected (one trailing space added by test)"
    lines = [header]
    for split, kind, inp, exp in unique:
        lines.append(f"{split}\t{kind}\t{inp}\t{exp}")
    (DATA / "auto-corpus.tsv").write_text("\n".join(lines) + "\n")

    pos = sum(1 for r in unique if r[1] == "positive")
    neg = sum(1 for r in unique if r[1] == "negative")
    miss = sum(1 for r in unique if r[1] == "positive" and not would_correct(r[2], r[3]))
    print(f"wrote {len(unique)} rows: positive={pos} negative={neg} predicted_miss>={miss}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
