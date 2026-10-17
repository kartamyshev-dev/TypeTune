# Две начальные заглавные: стадия, допуск модели и короткое слово

2026-10-15. Индекс: [double-caps-findings.json](../research/evidence/double-caps-findings.json).
Target main arm64 SHA-256:
`19d0057a9bfc38ba590babff82b28b5bf496c0833bbbd221f502722c6e2a26e9`.
Первый проход использовал сохранённые REA exports/snapshots и file-format
inspection frozen Mach-O. Затем выполнен отдельно разрешённый один main import
только для `0x1002dfeb4` pseudo+ASM. UI/native ввода и изменений кода нет.
Частные псевдотела, бинарники и извлечённые словари в отчёт не включены.

## Точный верхний путь F17

Pipeline `0x1002e10b4` вызывается wrapper `0x1002d9888` с объектом pipeline
`0x10060b838`. Сохранённые псевдокод и ARM64 позволяют разделить условия:

| Шаг | Адрес ARM64 | Условие/действие |
|---|---|---|
| Enable | `0x1002e120c–0x1002e1210` | Проверка младшего бита отдельного byte pipeline+`0x2b`; 0 пропускает F17 |
| Допуск модели | `0x1002e1214–0x1002e1224` | Model data/vtable из pipeline+`0x10/+0x18`; вызов slot+`0x28`; false пропускает F17 |
| Предварительный размер | `0x1002e1234–0x1002e1244`, `0x1002e149c–0x1002e14a4` | Helpers `0x1003d6e50`/`0x1003d673c`, сравнение возвращённого значения с 3 |
| UTF-8 scalars | `0x1002e14b0–0x1002e1910` | Декодируются первые три Unicode scalar; при нехватке стадия отклоняется |
| Регистр | `0x1002e191c–0x1002e1940`, `0x1002e19f4–0x1002e1a3c` | Первый и второй uppercase, третий lowercase; ASCII fast paths и отдельные Unicode predicates |
| Создание результата | `0x1002e1944–0x1002e19e4` | Helpers `0x1002d8e40`, `0x1003d1dc4`, formatter `0x1002e8d00`, затем `0x1002def3c` применяет полученный текст к представлению ввода |
| Отчётный флаг | `0x1002e19ec`, `0x1002e1610` | Отмечается выполненная F17 стадия; результат содержит byte+`0x78` |

После F17 выполняется autoswitch (byte+`0x28`, model slot+`0x18`), затем
опечатки/ё через `0x1002dbdfc` с bytes+`0x29/+0x2a`. Это отдельные поля и стадии.
Их фактическая привязка к пользовательским выключателям и независимость
от настройки «Опечатки» не принимаются только по этим полям.

Evidence pipeline pseudo:
`ev_9d8880bb72af09b01dc75a8dab09744a86eb7dd26d84edc54012bb05720078be`;
полный ASM: `ev_7fd2facc652fe69fd39fe72f3180c64868929660ab3bcddbb11f25a3a5eb0b02`;
wrapper: `ev_75d491a274ba578743fd0754eee43abeafd4888e73ab23e44e275f37a5f4d96c`.

## Допуск модели восстановлен до точного missing callee

Cached initializer `0x1002db210` устанавливает model data в `0x10060b848`,
model vtable `0x10052e038` в `0x10060b850`, bytes enable в `0x10060b860`.
Это соответствует аргументам F17 gate выше.

По frozen `LC_DYLD_CHAINED_FIXUPS` slot `0x10052e038+0x28 = 0x10052e060`
является rebase pointer format 6 (DYLD_CHAINED_PTR_64_OFFSET) на
**`0x1002e6428`**. Проверено принадлежность slot реальной starts-page chain,
а не просто совпадение low bytes. Соседние slots+`0x18/+0x20` указывают на
`0x1002e6424/0x1002e64f4`. Формат сопоставлен с локальным SDK
`mach-o/fixup-chains.h`, enum и struct dyld_chained_ptr_64_rebase.

Тело `0x1002e6428` уже сохранено: создаёт языковые строки `ru`, `en` и вызывает
**`0x1002dfeb4`**, передавая model fields+`0x20/+0x28`, RU/EN и последний аргумент 1.
В первом cached проходе тела `0x1002dfeb4` не было; оно получено последующим
узким пакетом ниже.

Значение gate после отдельного чтения известно: это veto по bit2 в полученном
feature vector, а не требование positive known-word lookup. Точное именование
packed bit2 как `is_double_caps_preventative` ещё требует моста от schema
к packed runtime record; подробности и границы ниже. Ранее исследованный
`0x1002dfac8`, проверяющий feature bit0, — другой helper.

Evidence initializer:
`ev_e67d9a3a22a170903c622c2c41c79e7e9a41bd858ba9b7ebc11592ef5a4e9c0b`;
wrapper gate: `ev_ef75960aec2254ae04d247aa063a83bc3a39549a68a9368ef5caa9bb18a719e8`.
File-format derivation с target hash и точными slot/target записан в индексе.
Это авторская статическая связка, не новый REA Evidence ID и не runtime trace.

## Что известно о длине и регистре

Outer stage требует как минимум три декодируемых scalar, не четыре буквы.
Дополнительно есть сравнение результата count helper с 3; точная единица
count helper без его тела не доказана. Три scalar явно требуются самим разбором.

В проверенном outer stage нет условия «каждый символ после второго lowercase»:
проверяется именно третий. Однако gate модели и transformation helpers могут
иметь дополнительные ограничения. Поведение `ПРиВет`/`HElLo` и неизвестных имён
пока не предсказывается как подтверждённое. Не установлено, меняет helper только
второй символ или весь хвост, и как ведут себя многоскалярные case mappings.

Словарь прототипа — самостоятельная стратегия. Добавление собственного слова
«при» исправляет воспроизведённый native gap прототипа, но не доказывает,
что оригинал использует такое же условие известного lowercased слова.

## Имеющееся native наблюдение — отдельное доказательство

Новый ввод в этом исследовании не выполнялся. Повторно сверены сохранённые
`header-phase-original-double-caps.json`, его verification и четыре fixtures
`corpus/native-double-caps.json`: completed=4, failures=[], тексты, источники
и selection совпадают с ожиданиями.

| Синтетический ввод оригинала | Раскладка | Результат после Space |
|---|---|---|
| GHbdtn (ПРивет) | RussianWin | `Привет `, cursor7 |
| HTTP | ABC | `HTTP `, cursor5 |
| iPhone | ABC | `iPhone `, cursor7 |
| GHb (ПРи) | RussianWin | `При `, cursor4 |

Таким образом, трёхбуквенное слово оригинал действительно исправил в этом
опыте. HTTP и iPhone согласуются с pattern, но не раскрывают model gate.
Корпус не проверяет неизвестные словарю слова, смешанный хвост, выключенную
typo-настройку или все Unicode cases. Наблюдение после Space не доказывает,
что исправление было впервые решено именно на Space; trace stage здесь отсутствует.

## Один новый gate body: F17 разрешается при отсутствии запретительного bit2

Последующий разрешённый пакет получил ровно одно тело `0x1002dfeb4` и его
полный ASM: 380 bytes, диапазон `0x1002dfeb4–0x1002e002f`. Других новых тел,
xrefs или callgraph запросов не было. Один fresh main import; export140 records
и snapshot сохранены private, session закрыта, JVM завершён. В snapshot остаются
1 primitive / 1 workflow binding; это не обещание replay нового тела без import.

Функция сначала вызывает **уже исследованный** `0x1002e0030`, затем сканирует
его vector с шагом `0x28` (40-byte records). Решение восстановлено и по ASM:

| Наблюдаемое условие | Результат model gate | Точный anchor |
|---|---|---|
| Пустой vector | true, F17 может продолжить pattern check | `0x1002dfee8 → 0x1002dff84` |
| При сканировании record первый qword равен sentinel -2 | Прекратить просмотр, освободить остаток, вернуть true | `0x1002dff04–0x1002dff0c`, `0x1002dff34–0x1002dff84` |
| До sentinel найден record с byte+0x18 bit2=1 | false, F17 пропускается | `0x1002dff18–0x1002dff1c → 0x1002dffbc → 0x1002e0024` |
| Все просмотренные records имеют bit2=0 | true | `0x1002dfef4–0x1002dfefc → 0x1002dff84` |

Gate не проверяет непосредственно bit0/bit1 и не требует хотя бы одного
положительного словарного результата. Следовательно, стратегия прототипа
«обязательно известное lowercased слово» не восстановлена из оригинального
gate и не должна называться точной копией его алгоритма. Это не означает,
что словарь совсем не участвует: vector формируется моделью.

Cached `0x1002e0030` сначала пробует преобразованный текст через
`0x1002e28c4 → 0x1002e1d98`; если feature vector найден, возвращает его.
Иначе формирует нормализованные варианты и получает records через
`0x1002e6124`. Cached `0x1002e1d98` выполняет hashed lookup, сравнение языковой
пары в обоих направлениях и переносит packed feature word в record+0x18;
в одной case-fold ветке он дополнительно фильтрует bit1. Поэтому языковой
контекст RU/EN действительно проходит через wrapper/lookup, но все его
критерии не восстановлены одним gate.

Schema parser `0x1002d68a0` подтверждает раздельные fields: tag3 —
`is_known_word`, tag4 — `is_case_sensitive`, tag5 — `is_double_caps_preventative`.
Он сохраняет их как отдельные bool bytes в decoded 12-byte feature record
(+8/+9/+10), а gate читает packed bit2 другого 40-byte runtime record.
Без кода упаковки нельзя переносить имя tag5 на bit2 как установленный факт.
Это сильная согласованная гипотеза, но не завершённая привязка.

Новые Evidence:
`ev_fcef5d900d114ad47253f9624a020346adc0fcdac4e78b56541b93d9e034bd94` (pseudo),
`ev_7622d953747d6e96d420f27718cfa175fa0e7512ef794bf48dff116ec597ce1e` (ASM).
Дополнительно перечитаны cached extractor
`ev_389ea798cd7848c4d5ca94ff2a8aaafdff9cae88620302c4bceb9e390aaf8219`,
lookup `ev_c7fc339d3853043a4c8a90beb71b259c34dbf8273e18340ce29e7c3ce460c0af`,
schema `ev_734199f05f45a9750c2e948596578f59d613d77a439bce9c7a4560cd3ec7da20`.

## Оставшаяся точная граница

Поведение верхнего gate теперь восстановлено. Неизвестны mapping bool→packed
bit2, все варианты lookup/fallback и transformation semantics. Если продолжать
эту ветку отдельно, точный следующий helper для происхождения fallback records —
`0x1002e6124`; для значения первичных lookup IDs — `0x1002dec80`. Они не были
запрошены этим пакетом. Обход classifier и дополнительные bodies не запускались.

## Самостоятельная реализация и новые native границы

Core теперь допускает F17 без положительного словаря, смотрит первые три буквы,
понижает оставшийся хвост и передаёт результат дальше в layout/spelling stage.
Собственные veto: facebook, iphone, MHz. Они не являются извлечённой моделью
оригинала. Собственные неизвестные слова и разные стадии проверены отдельно.

Выявлены две разные границы: CLI all-letter guard сохраняет `ABc.txt`, но GUI
раньше исправлял `ABc` уже при точке/semicolon. Native4 показал2FAIL/2PASS,
`punctuation-regression-native*.json`. Исправление GUI откладывает auto до пробельной
границы, чтобы видеть весь token и снимать только trailing sentence punctuation.
Это самостоятельное консервативное отличие по моменту срабатывания; не выдаётся
за точное повторение early classifier Caramba.

Новые synthetic original observations:
`early-exploration-original.json` — ghb→при, ghbd→прив, ghbdtn→привет до Space;
ABc.txt/ABc;def/MBps/MHz до Space не меняются. Следующий unit-run впервые дал
`Компьютерьизы` вместо ожидаемого локального результата MBps. Перед ним предыдущий
опыт завершился без разделителя на RJvgm.nth; поэтому состояние не считалось
достаточно изолированным. После полного restart original и нового документа:
MBps→Mbps, MHz unchanged, GHZ unchanged, GBps→Пизы, RJvgm.nth→Компьютер.
`unit-exploration-original-restarted.json`. Первый run сохранён и не используется
как чистая спецификация MBps. Прямая причина внутреннего накопления не доказана.
Перед новой независимой original-серией после nonboundary опыта нужен restart.
Модель оригинала не является безошибочным oracle для единиц/кода.
