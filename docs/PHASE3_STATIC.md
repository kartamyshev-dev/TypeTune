# Третий статический проход: подтверждённые границы

Источник — сохранённый REA export `research/private/phase3-evidence-final.json`,
89 records, target arm64 SHA-256
`19d0057a9bfc38ba590babff82b28b5bf496c0833bbbd221f502722c6e2a26e9`.
Индекс хешей, Evidence ID и ограничений:
[phase3-static-findings.json](../research/evidence/phase3-static-findings.json).
Это анализ оригинала, не runtime-приёмка прототипа. Декомпиляция и данные модели
остаются private; публично сохранены только авторские выводы и anchors.

| Вопрос | Наблюдение | Остаток |
|---|---|---|
| Как проверяются пользовательские исключения? | `0x10004214c` использует `Swift.String.hash`, probing слотов Set и равенство сохранённой строки. Evidence pseudo `ev_ac920bff0a0e35a9a73540f5adf4dc23c90f2f28b74a258879f3dcfd2471acb2`; ASM `ev_6cd8adc13d6c2e8be473765a34e3b278e1c78a8c649dfcd9318bb00c143c7d5a` | Это exact String equality, не substring. Swift equality не следует переименовывать в чистое побайтовое сравнение. Нормализация регистра/Unicode до вызова здесь не установлена |
| Откуда берётся Set? | Bridge `0x100042234` берёт `AutoswitchExceptionsStore.patternSet`, преобразует входную строку и вызывает `0x10004214c`. Evidence `ev_f455eef7cfe53fef5768ea4209f5a8b60c60d8e9903e7607328eceae66c6ba6f` | Построение/фильтрация Set, роль visible/disabled/additions и learning ещё требуют writer/callers |
| Как работает plain paste? | `0x100022cb4` получает general pasteboard, сохраняет представление type→data, временно объявляет только строковый тип, записывает его и вызывает выдачу клавиш; запрашивает Task sleep `1_000_000_000` нс | Это запрошенный1с sleep, не измеренная длительность. Полная поддержка нескольких pasteboard items, отказов и нового clipboard не доказана |
| Как восстанавливается clipboard? | Нормальная continuation: `0x100022f90 → 0x100022fe8 → 0x10002341c`. Последняя объявляет сохранённые типы и записывает сохранённые data для каждого типа | В четырёх полученных телах нет установленной проверки `changeCount` перед восстановлением. Нельзя заявлять, что более новое копирование пользователя будет сохранено. Error continuation `0x100023060` отдельно не восстановлена |
| Как извлекаются кандидаты модели? | `0x1002e1d98` содержит hashed integer-key lookup, проверки flags, равенство пар byte sequences и накопление candidate records. Evidence `ev_c7fc339d3853043a4c8a90beb71b259c34dbf8273e18340ce29e7c3ce460c0af` | Это структура поиска, не полный смысл feature categories, приоритетов и правил. Численные веса и словари не переносились |

Clipboard Evidence:

- `0x100022cb4`: `ev_6a01a7b57c19fe099f11b87374ca21b2260cd82f3f0ce1760574d5589b8d6189`.
- `0x100022f90`: `ev_35b1c1ccb109f5fe0f73039a29e7cba0ceabcab4f88a73e0c999750355c18c37`.
- `0x100022fe8`: `ev_385e02f94d62c14a47e7da3740a562d20e7843ab565ac13493da3b231ebc9221`.
- `0x10002341c`: `ev_6ea1d734338d0899c0700676ea3488ba37a37eea2a4f29be75868fade41bbb7a`.

У clipboard и model helper пока псевдокод без отдельного corroboration всех
системных ABI инструкциями. Ghidra иногда неверно называет return registers,
поэтому конкретные flags/keycodes выдаваемой paste-комбинации здесь не заявлены.
Получение данных clipboard и восстановление описывают найденный путь оригинала;
LayoutPilot не обязан повторять риск перезаписи более нового clipboard.

Продолжение Undo/learning с полученными пятью новыми телами:
[UNDO_RESEARCH](UNDO_RESEARCH.md). Реестр и checkbox полноты этим проходом
не закрываются; поведенческие проверки учитываются отдельно.
