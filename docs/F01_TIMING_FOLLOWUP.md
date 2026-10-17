# F01: решение до разделителя и модельные флаги

2026-10-15. Индекс: [f01-timing-findings.json](../research/evidence/f01-timing-findings.json).
Target arm64 SHA-256:
`19d0057a9bfc38ba590babff82b28b5bf496c0833bbbd221f502722c6e2a26e9`.
Первый проход прочитал cached REA Evidence и selection Ghidra packet; сломанный
ABI gate сверил с узким ASM frozen файла через Apple LLVM21.0.0. Затем разрешённый
followup открыл existing persistent project один раз с `-noanalysis -readOnly`
для `0x1002e6124` pseudo+ASM, а16октября ещё один такой же узкий reopen
для `0x1002e8990`. Последующий formatter packet также использовал только
existing-project readonly reopens. Новых imports и REA sessions нет. Runtime,
UI, ввод, Core и canonical документы не менялись. Сырые результаты остались private.

## Ранний допуск: разделитель или достаточно длинный ввод без внутренних заглавных

В автоматической ветке dispatcher вызывает gate `0x1002e3ca8` из
`0x1002534d0`; false идёт в очистку/возврат `0x100253588`. Затем вызывается
другой gate `0x100255420` (settings/предыдущее исправление/модификаторы),
после исключений pipeline `0x1002d9888` вызывается в `0x100253714` с mode 0.

Точный результат `0x1002e3ca8` имеет две альтернативы:

| Условие | Допуск к дальнейшему анализу |
|---|---|
| Последний Unicode scalar — TAB, LF, CR, Space или `-` | Да, независимо от условия справа |
| Последний scalar иной | Да, если count-helper возвращает >2 и ни один scalar после первого не uppercase |

Вторая строка — именно допуск к модели, не обещание исправить каждое слово
длиной 3. Проверка всех scalar после первого объясняет, почему обычное lowercase
слово может попасть в анализ до пробела, а ПРивет/HTTP в этой автоматической ветке
ранний gate не проходят до разделителя. Первый scalar может быть uppercase.

Точные ASM anchors:

- `0x1002e3cc4–0x1002e3d48`: декодирование последнего scalar и delimiter bitset.
- `0x1002e3d4c–0x1002e3d64`: count-helper `0x1003d6e50`/`0x1003d673c`.
- `0x1002e3d68–0x1002e3e18`: UTF-8 scalar loop, первый пропускается,
  ASCII A–Z и Unicode uppercase predicate `0x1003d7fc4` после него запрещают
  вторую альтернативу.
- `0x1002e3e1c–0x1002e3e24`: count >2 и OR с delimiter-флагом.

В cached псевдокоде Ghidra count-return ошибочно выглядел сравнением указателя;
ASM показывает возвращённый x0 → x20 и сравнение x20 с 2. Точная единица
count-helper этим проходом не раскрыта: числовой порог >2 установлен, называть
его числом grapheme clusters нельзя. Scalar loop сам обрабатывает Unicode.
Cached REA gate: `ev_fd52fc9ee791fa18913d4e4cf53c0882b625b5d879ee860b8cb3ee048391634f`.
Новый LLVM ASM — отдельное supplementary evidence, без выдуманного REA ID.

## Универсального confidence threshold здесь нет

Цепочка model slot+0x18 → `0x1002e6424/FUN_1002df804` → `0x1002e083c`
→ `0x1002e0cec` уже сохранена и перечитана. Она различает категории:

| Категория evaluator | Агрегирование двух языковых кандидатов |
|---|---|
| 0 | Нет подходящей языковой пары; кандидат пропускается |
| 1 | Signed 32-bit сумма ненулевых weights; выигрывает большая, равенство сохраняет прежнего |
| 2 | Отдельный кандидат с приоритетом над обычной весовой категорией, если нет категории 3 |
| 3 | Сохраняющийся veto/особый результат `0x8000000000000002` |

Для обычной пары, где **оба** кандидата дают category1 и обе суммы равны нулю,
агрегатор сохраняет отдельный Bool. Пропуск category0 сбрасывает этот Bool,
поэтому это не универсальное правило «любая нулевая сумма запрещена». Wrapper
`0x1002df804` отклоняет обычный результат с этим Bool. Это особый нулевой случай
пары кандидатов, а не найденный фиксированный margin или порог вероятности. Данные реальной модели/веса в прототип не переносились.
Слова «известное/неизвестное» для category2/3 пока не установлены packing bridge.

Evidence evaluator ASM:
`ev_dc4ca2427cec9987472c0444b6f5ed0b41d0da44de0005bd1275c566c8e189fe`;
aggregator ASM:
`ev_93408285a7e01902352121bc95fd3fe4ba0f6db4cfc36ec13c6afdab171bdfc7`;
wrapper pseudo:
`ev_f41e7318948f8b8e620a31704c24552b17a171cac641648c45b631949e7996a9`.
Точный разбор категорий также сохранён в [RESEARCH_FOLLOWUP](RESEARCH_FOLLOWUP.md).

## Boundary и model flags — разные условия

Pipeline результат byte+`0x79` переносится из отдельного Bool результата
model wrapper; byte+`0x7a` отмечает выполненную смену кандидата. Это не одно поле.
Для особого результата категории3 wrapper сохраняет вход и ставит отдельный
Bool, вместо обычного конвертированного результата.

В dispatcher `0x100253748–0x100253760` проверяется output byte+`0x79`:
при нём выполняется отдельная ветка. Только в этой ветке проверяется
`0x1002e3c28` (последний byte TAB/LF/CR/Space/дефис); наличие границы меняет
сохранённое состояние. Затем ветка сообщает `caramba_collision`, освобождает
результат и возвращается **без retype**. Литерал находится в `0x1004283d4`.
Поэтому это нельзя описывать как «любой модельный результат ждёт пробела».

Обычный успешный результат проходит к подготовке и retype без общей обязательной
проверки разделителя. До него уже действуют ранний gate, запреты приложения,
исключения, модификаторы и модель. Полная допустимость для каждого события
этим узким исследованием не принимается.

Evidence dispatcher:
`ev_e32289eb3e357ec8d496c1023b5a756031e22c46f0f1cc2d84521461e7c6968f`;
pipeline ASM:
`ev_7fd2facc652fe69fd39fe72f3180c64868929660ab3bcddbb11f25a3a5eb0b02`;
сохранённый supplemental Ghidra `selection-followup.txt`, dispatch anchors
`0x100253708–0x100253760`. Публичный индекс содержит его digest. Это не новый
REA record и не live trace.

## Уже имеющееся наблюдение момента

В сохранённом synthetic Chrome опыте `phase3-original-hid-source.json` перед
первым Space уже записано `привет`. В emitted sequence первые три события
фиксируют ABC, а четвёртое — RussianWin: источник изменился после третьей и до
четвёртой буквы. Это подтверждает существование pre-boundary correction в том
опыте. Точное время изменения текста после каждой буквы не записано; наблюдение
не является универсальным p95, полным coverage или доказательством фильтра
источников событий. Раннее source differential позднее не воспроизвелось,
что отдельно описано в [INPUT_ORIGIN_RESEARCH](INPUT_ORIGIN_RESEARCH.md).

## Followup: fallback iterator `0x1002e6124` не рассчитывает веса

Прочитано одно тело `0x1002e6124–0x1002e6403`, 736bytes, псевдокод и полный ASM.
Декомпилятор этого persistent project — Ghidra12.1.4; это supplemental direct
Ghidra результат, не новый REA Evidence record. Program SHA проверен до чтения.
Headless завершился с exit0; 9 файлов project до/после имеют одинаковые SHA-256.
Нового import, autoanalysis, target execution и сохранения изменений нет;
процесс завершён, project свободен. Хеши вывода/script/log/manifest — в индексе.

Функция — stateful iterator с тремя источниками, а не ещё один classifier:

1. Выдаёт по одной уже подготовленной записи активного массива, двигая cursor
   на `0x28`. Обнаруженный sentinel -2 или конец завершает именно этот массив
   с освобождением остатка.
2. Если включён источник variants, берёт следующий 24-byte string-like объект
   из списка вариантов и вызывает cached `0x1002e1d98` для него. Полученный vector
   становится активным, полностью выдаётся, затем берётся следующий вариант.
   Sentinel -1 на уровне variant/lookup завершает эту фазу.
3. После variants или при их отсутствии выдаёт отдельный заранее подготовленный
   secondary массив тех же 40-byte записей. Когда всё исчерпано, возвращает -2.

ASM anchors: active record `0x1002e6178–0x1002e6188`, next variant
`0x1002e6208–0x1002e6230`, установка vector `0x1002e6254–0x1002e626c`,
неизменённая выдача record `0x1002e6294–0x1002e62ac`, secondary фаза
`0x1002e631c–0x1002e63e0`. Здесь нет weight arithmetic, выбора языка,
confidence threshold, semantic дедупликации records или изменения flags.

### Формат выдаваемой записи

| Offset | Установленный формат/потребитель |
|---|---|
| +0x00, +0x08, +0x10 | String-like/optional triple: tag/ownership-like word, pointer, length; семантическое назначение текста не установлено. -2 означает конец iterator; -1 может быть первым word обычного feature record |
| +0x18 | 64-bit metadata/flags word; существующие consumers используют low bits0/1/2 |
| +0x20 | 32-bit feature/table identifier, получаемый из model record; точное продуктовое значение ID не установлено |
| +0x24 | 32-bit signed weight, который evaluator прибавляет в ordinary score, если он ненулевой |
| Итого | 0x28 = 40bytes; iterator копирует все пять qwords без изменения |

Связка layout подтверждена новым copy ASM и cached `0x1002e1d98`, который
переносит flags, ID и weight из найденных model records. Численные original
weights/словари не выгружались и в прототип не включались. Веса берутся из модели;
этот iterator их не создаёт. Порядок sources подтверждён, но это не полный
приоритет всех model правил.

Cached `0x1002e477c` материализует список 24-byte variants вызовами
**`0x1002e8990`**. В первом followup его тело ещё отсутствовало. Последующее чтение ниже
уточнило: это iterator уникальных уже созданных строк, а не их producer. `0x1002dec80` не вызывался напрямую в новом теле и не понадобился для
выяснения порядка/формата; дополнительный запрос к нему не выполнялся.

## Новое наблюдение координатора — не эксперимент этого исследователя

Координатор отдельно записал `early-exploration-original.json`, completed9/9,
в synthetic TextEdit без разделителя. В raw подтверждены ghb→при, ghbd→прив,
ghbdtn→привет; ABc.txt, ABc;def, MBps, MHz сохранились. Это независимое runtime
наблюдение координатора, согласующееся с uppercase-suffix gate; этот агент
только прочитал существующий файл. Полная dictionary/model parity и p95
этим наблюдением не принимаются.

## Followup16октября: `0x1002e8990` только устраняет дубликаты

Прочитаны pseudo+ASM одного тела `0x1002e8990–0x1002e8bfb`, 620bytes.
Один existing-project reopen с `-noanalysis -readOnly` и SHAguard, без import.
Все 9 файлов project до/после побайтово совпали; headless exit0, JVM завершён.
Дополнительные разрешённые до3 callee не потребовались: вызовы здесь обслуживают
hash (`0x1002d90c0`), рост таблицы (`0x1003e56d8`) и clone (`0x1003d2c6c`),
а не RU/EN transformations. Ни один из них дополнительно не декомпилировался.

Iterator читает готовые 24-byte строки в исходном порядке. Для каждой вычисляет
hash, ищет в собственной таблице по fingerprint и **length+точному memcmp**.
Дубликат пропускается; новая строка добавляется в таблицу по pointer и клонируется
в результат. При исчерпании диапазона возвращается -1.

Точные ASM anchors:

- cursor/end `0x1002e89b4–0x1002e89c0`; шаг24bytes `0x1002e8a80–0x1002e8a84`;
- hash `0x1002e8a8c–0x1002e8a98`; length+memcmp `0x1002e8a10–0x1002e8a2c`;
- duplicate skip `0x1002e8a68–0x1002e8a7c`; insertion `0x1002e8aec–0x1002e8b1c`;
- clone `0x1002e8b24–0x1002e8b4c`; end -1 `0x1002e8b50–0x1002e8b58`.

В этом state+0x00/+0x08 — cursor/end, +0x10/+0x18 — table/mask;
+0x20/+0x28 участвуют в capacity/count bookkeeping; +0x30/+0x38 передаются
в hash helper. Эти поля — индексы и служебное состояние dedup, **не языковые
или model feature flags**. Здесь нет case folding, Unicode normalization,
перевода раскладки, вычисления веса или выбора языка. Точное memcmp не
объединяет разные Unicode byte representations по семантическому равенству.

### Вход — ровно две заранее форматированные строки

Cached extractor ASM `ev_29a976e554936d241a1421c1dca8f062979cc9aefc268fe72270c49413829bff`
позволил установить входной диапазон без новых функций:

1. `0x1002e0230–0x1002e023c`: форматирует punctuation-trimmed вариант в sp+0x20.
2. `0x1002e0240–0x1002e0254`: форматирует whole вариант в sp+0x38 (тот же
   выбранный format descriptor). Whole уже прошёл whitespace trim; это не
   исходный текст вместе с пробелами.
3. `0x1002e0258`: end=sp+0x20+0x30; `0x1002e0288–0x1002e02ac` передаёт
   start/end в materializer `0x1002e477c`. Разность48bytes — две строки по24.

Следовательно, эта fallback-фаза даёт **не более двух уникальных строк**:
punctuation-trimmed первой, whole второй; при точном равенстве останется одна.
Это не n-gram generator и не произвольный перебор префиксов. Результаты lookup
каждой строки затем разворачиваются в несколько feature records через
`0x1002e6124 → 0x1002e1d98`, поэтому ограничение двух строк не ограничивает
число признаков двумя.

Выбор format descriptor зависит от low byte режима и наличия последнего
TAB/LF/CR/Space/дефиса: mode!=0 либо delimiter выбирает `0x1004dac93`, иначе
`0x1004dac99`. Оба варианта строки используют один descriptor этой ветки.
Это компактные форматные данные, не обычные нуль-терминированные строки.
Предыдущий проход оставлял их output неизвестным; formatter packet ниже
восстановил его точно. RU/EN варианты в этой фазе не порождаются; языковая
пара задаётся внешним model wrapper/lookup.

## Formatter packet: точный partial/complete контракт model lookup

Теперь восстановлены callback `0x1002e6414` (16B), relay `0x1003da148` (20B),
format-to-string `0x1003d2aa0` (404B), compact format interpreter
`0x1003d61a4` (436B) и string display writer `0x1003d52d8` (784B).
Это пять ограниченных тел, а не обход библиотеки: первые три раскрыли
единственные необходимые renderer callees, которые прочитаны вторым
последовательным readonly reopen. Scope ledger явно содержит **два headless
reopen**, ноль imports/autoanalysis. Оба exit0, все9 projectfiles SHA неизменны,
JVM завершены до UI-проверок. Сырые pseudo/ASM private; это supplemental Ghidra
с target guard, без выдуманных REA Evidence IDs.

Callback распаковывает pointer/length и передаёт string slice writer. В
interpreter descriptor opcode1 означает вывод следующего literal byte,
opcode C0 — вызов default Display callback, opcode0 — конец. Для C0
устанавливаются default options `0x60000020`; writer не включает width/precision
ветви (`options & 0x18000000 == 0`) и передаёт весь исходный slice в write_str.
Таким образом, дополнительной замены регистра, Unicode нормализации,
кавычек, форматирования номера или truncation здесь нет.

| Условия lookup | Descriptor | Итоговые bytes для текста T |
|---|---|---|
| Auto mode0, последний символ не TAB/LF/CR/Space/дефис | `0x1004dac99` | `0x02 || UTF8(T)` |
| Mode!=0 либо последний символ входит в delimiter set | `0x1004dac93` | `0x02 || UTF8(T) || 0x03` |

Пример собственного synthetic `ghb`: ранний ключ — `02 67 68 62`,
завершённый — `02 67 68 62 03`. Это не JSON-escaping и не видимые управляющие
символы редактора: маркеры принадлежат внутреннему lookup representation.
Вход T к этому моменту уже прошёл описанные whitespace/punctuation trims.
Обе fallback строки получают одинаковый partial/complete descriptor, после
чего exact-byte dedup удаляет совпадение.

Точные anchors: callback `0x1002e6414–0x1002e6420`; relay
`0x1003da148–0x1003da158`; format dispatch `0x1003d2bd0`;
interpreter literal `0x1003d6218–0x1003d6238`, C0/default
`0x1003d61ec–0x1003d6204`, descriptor branch `0x1003d6248–0x1003d624c`;
writer direct-slice path `0x1003d5550–0x1003d5578`.

Независимый авторский decoder двух конкретных descriptors проверен на
18 synthetic случаях (empty, ASCII, RU, tab, emoji, NFD) и воспроизводит
указанные bytes. [Static verification](../research/evidence/f01-format-static-verification.json).
Это проверка статического вывода, **не выполнение оригинального formatter**
и не native/classifier acceptance. Содержимое словаря/модели не выгружалось.

### Практический контракт для самостоятельного classifier

Ранний анализ и завершение слова — два разных контекста одной и той же
последовательности текста. У оригинала начало помечено02 всегда, конец03
добавляется только при boundary/явном complete mode. Следовательно, нельзя
описывать его как один lookup полного слова, который просто вызывают раньше:
у partial и complete входные ключи различаются.

Для собственной реализации можно независимо представить это структурно как
`text + isComplete`, не копируя model encoding/данные. После eligibility gate
(count>2, uppercase restrictions и контекст) partial lookup должен оценивать
собственные признаки неполного слова; complete lookup — завершённого.
Последующее matching-исследование ниже установило перебор byte-подстрок
и prefix matches в trie. Из этого по-прежнему не следует немедленное исправление
любого уникального словарного префикса: решение принимает weighted model.

## Matching packet16октября: byte trie и перекрывающиеся признаки

Пакет ограничен шестью новыми телами: `0x1002dec80` (700B), `0x1002e5fb8`
(364B), `0x1002de6f0` (328B), `0x1002e4058` (432B), `0x1003d6e50` (680B),
`0x1003d1dc4` (2104B). Для них получены pseudo+ARM64. Четыре последовательных
existing-project reopen с `-noanalysis -readOnly`, SHAguard; новых imports нет.
`2e4058` оказался generic deep clone: эту ветку дальше не исследовали.
Не читались generic hash/alloc callees и никакие original dictionary/model
entries. Все9 projectfiles SHA сохранились, все4 процесса exit0/JVM завершены.

### Какие совпадения действительно собирает модель

`0x1002dec80` собирает vector 32-bit IDs из iterator `0x1002e5fb8`.
Последний проходит **каждое byte-смещение** marker-bearing строки, увеличивая
start на1, и вызывает `0x1002de6f0` на всём оставшемся suffix.

`0x1002de6f0` начинает с state0 и проходит compressed array trie по bytes.
Следующий индекс образуется XOR текущего state, offset из node и input byte.
Проверяется byte label узла; несовпадение останавливает текущий suffix.
При terminal bit8 извлекается 31-bit ID и добавляется в результат; обход
продолжается, поэтому находятся **все совпавшие префиксы данного suffix**,
включая короткий паттерн внутри более длинного. Это повторяется для всех starts.

Anchors: next byte-start `0x1002e6028–0x1002e6048`; ID return в w1
`0x1002e6088–0x1002e6090`; trie transition/label
`0x1002de758–0x1002de794`; terminal `0x1002de798–0x1002de7b8`,
31-bit ID append `0x1002de738–0x1002de748`. Псевдокод iterator скрывал payload
регистра w1, поэтому формат ID проверен по ASM.

Нового ограничения длины паттерна «только2/3/4 символа» в matcher нет.
Однобайтовое terminal совпадение возможно после первого перехода; верхняя
граница — конец suffix либо первое несовпадение. Matcher работает по UTF-8
bytes, не по graphemes и не проверяет границу Unicode scalar для каждого start.
Перекрытия и повторные IDs collector не удаляет. Это механизм поиска
перекрывающихся model patterns; называть всю модель только n-gram classifier
без её данных нельзя.

Для обычного текста markers дают конкретные виды признаков:

| Pattern shape (авторские обозначения) | Где может совпасть |
|---|---|
| P без markers | Внутренняя/начальная/конечная подстрока; partial или complete |
| 02+P | Только с помеченного начала |
| P+03 | Завершённый контекст, конец текста |
| 02+P+03 | Завершённый текст целиком |

Это следует из byte matching + формирования02/03, а не из извлечения patterns
оригинала. Никаких конкретных original patterns/weights в поставку не добавлено.

### Получение features, регистр и multiplicity

Cached `0x1002e1d98` сначала вызывает `0x1003d1dc4`, затем matcher над
полученным текстом; после этого matcher над исходным. Новое тело3d1dc4
подтвердило ASCII lowercasing (A–Z получают bit0x20), UTF-8 decode, Unicode
case mapping через `0x1003d79e4`, специальный контекст Greek Sigma и возможность
нескольких выходных scalar. Это **lowercasing**, а не доказанный Unicode
caseless-fold с теми же правилами для всех Unicode версий. Полная mapping table
не выгружалась и не переносилась.

Для lowercase matches cached feature resolver пропускает records с bit1=1;
исходный проход допускает их. Языковая пара сопоставляется в обоих направлениях.
Затем ID разрешается в model feature list, и в40B records копируются flags, ID
и signed weight. Collector не делает unique-ID dedup; resolver проходит IDs
по порядку и добавляет подходящие records. Поэтому повторные occurrences
паттерна могут повторно дать feature/вклад веса. Это отличается от бинарного
«паттерн хотя бы раз встретился»; точное число отдельных model features остаётся
зависимым от данных языка/ID. Дедупликация двух formatted строк выше — другая
операция и не удаляет повторные pattern occurrences внутри одной строки.

### Флаги и F17 veto — установленная операционная семантика

| Runtime flag | Подтверждённое действие consumer |
|---|---|
| bit0 | Для zero-weight records участвует в выборе категорий2/3 evaluator; это не общий положительный known-word gate |
| bit1 | Исключает record из lowercase lookup ветки, но не из исходного регистра |
| bit2 | `0x1002dfeb4` запрещает F17 при таком record до sentinel -2; пустой vector разрешает F17 |

Итак, F17 veto может происходить из совпавшего **model pattern**, а не только
из exact full-word исключения. Начало/конец в таком pattern определяется02/03
и фазой lookup. Названия schema `is_known_word/is_case_sensitive/
is_double_caps_preventative` согласуются с этим, но отдельный decoded-bool→
packed-bit constructor ещё не восстановлен: имена не выдаются за доказанный
layout bridge. Новое `2e4058` оказалось clone map, такого bridge оно не содержит.

### Порог ранней длины уточнён

`0x1003d6e50` считает bytes, которые не являются UTF-8 continuation, то есть
Unicode scalar count на валидном UTF-8. Для автоматического входа <32UTF8bytes
caller использует именно его: числовой gate >2 означает **минимум3 scalar**,
а не3bytes/UTF-16 units/graphemes. Emoji и combining mark считаются scalar
по отдельности. Длинный caller path вызывает другой helper3d673c; в этом
пакете он не читался. Внутренний matcher не вводит ещё одного минимума3: этот
минимум относится к раннему eligibility, а delimiter может его обходить.

## Практический контракт и границы для собственного early classifier

Реально восстановлены стадии, пригодные для самостоятельной архитектуры:

1. Отдельный early gate: boundary либо≥3scalar для короткого валидного ввода
   без uppercase после первого, плюс app/history/modifier guards.
2. Partial/complete контекст и два нормализованных кандидата строки, exact dedup.
3. Поиск перекрывающихся byte patterns всех длин с явными start/end условиями.
4. Lowercase и original-case lookup, operational case flag, языковая пара.
5. Signed additive weights с multiplicity, отдельные категории/veto и F17 bit2.

Это уже исключает модель «любой известный словарный префикс переключается».
Независимый classifier может использовать собственные patterns/weights,
структурные begin/end flags и отдельный veto; до сравнительного корпуса это
самостоятельное приближение, а не восстановленная точная таблица решений.

Не восстановлены значения original patterns/weights (они намеренно не
извлекались), packed constructor для schema labels, полный Unicode mapping
version и длинный SIMD count helper. Без собственных обучающих данных и native
сравнения нельзя обещать false-positive parity и все решения на2–3 буквах.
Новых Core/GUI/native действий этим исследователем не выполнялось.
