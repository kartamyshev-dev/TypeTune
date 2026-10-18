# F13: счётчики и оценка сэкономленного времени

Связь восьми событий с пятью категориями increment восстановлена статически.
Default-формула времени по категориям и форматирование восстановлены
статически; runtime overrides пока неизвестны. Самостоятельные2сек/исправление
LayoutPilot остаются собственной
оценкой; этот проход не закрывает F13 и не меняет GUI/Core.

Target: frozen arm64 Caramba2026.10.07,
SHA-256`19d0057a9bfc38ba590babff82b28b5bf496c0833bbbd221f502722c6e2a26e9`.
Авторский индекс [stats-research-findings.json](../research/evidence/stats-research-findings.json)
содержит digest источников/пакета и проверенные границы. Это не новый REA Evidence.
Личные preferences/DB, UI и native-ввод здесь не читались/не исполнялись.

## Что уже подтверждено cache

Метаданные `SwitchStatisticsModule` по class0x100590260, ivars0x100565138
содержат `_autoswitches`, `_cupertino`, `_yofikator`, `_sounds`, `_singleshift`,
`_doubleshift`, а также preferences/store/deviceID/cancellables. Это поддерживает
существование отдельных категорий; metadata offset0/size0 у части Swift-wrapper
полей нельзя считать адресом фактического runtime counter.

Frozen strings содержат соответствующие `tech.caramba.switcher.counters.*`,
а также `usage_stats_event_weights`; у SettingsViewModel рядом с UI-строками
находится `usage_stats_timing_limits`. Локализованные строки имеют формы
минут/часов/дней/недель. **Наличие weights/limits не устанавливает их значения,
источник конфигурации, единицы или формулу.**

Rust event bridge0x100259288 создаёт две CFString из UTF-8 ptr/len и вызывает
0x100042568 (ARM64 callsite0x100259304). Этот Swift bridge преобразует имя события
и создаёт MainActor task через descriptor0x100410650. В cached async entry
0x1000429f4 есть прямой переход на0x100042698, затем task switch на0x100042704.
Соответствие descriptor0x100410650 именно entry0x1000429f4 в этом проходе отдельно
не разрешалось; это оставшийся join между cached кусками, а не повод считать
весь call graph новым полным доказательством.

Consumer0x100042704 получает dictionary0x100590718 (once-init0x100042364),
ищет event-name через0x100031550 и извлекает value размером24байта:
два байтовых discriminator, callback по+8, captured context по+16.
При byte0!=6 выполняется отдельный0x100025740; byte1 включает ещё одну ветвь
обращения к app delegate. Callback вызывается **отдельно** после этого.
Назначение byte0 как типа статистического счётчика раньше было гипотезой;
следующий пакет этого не подтвердил.

Cached источники: `f14-engine-interface.txt`, `f14-event-bridge.txt`,
`f14-save-event-continuation.txt`, `f14-refresh-event.txt`,
`f14-final-consumers.txt`, `hotkey-main-objc-metadata.txt`, `strings.txt`.
Их полные digests в авторском индексе; raw/decompiled материалы остаются private.

## Один узкий Ghidra follow-up

После освобождения существующего persistent project выполнен ровно один пакет:
`-process caramba-arm64 -noanalysis -readOnly`, без нового import. SHA guard
внутри скрипта пройден, exit0, marker`STATS_PROBE_SAVED`.
Получены только тела и инструкции0x100025740 и0x100042364.

**0x100042364** устанавливает структуру статического event-table. Инструкции
0x1000423b4–0x100042450 обходят8 записей с шагом0x28, начиная0x100590750.
Ключ занимает16байт; byte16/17 переносятся в первые два байта dictionary value;
пара callback/context по24/32 переносится вvalue+8/+16. Итог сохраняется
в0x100590718 на0x100042488. Содержимое восьми записей в рамках этого пакета
не читалось: формула, точные имена callback и event→counter mapping неизвестны.

**0x100025740** читает Bool через dependency/preferences wrapper; основная ветвь
выполняется при enabled и parameter!=4. Затем идут вызовы других команд и
Dispatch async. В полученном теле **нет подтверждённого прямого increment**
счётчика, вычисления saved time или персистентной записи counters.*.
Называть этот callee статистическим increment на основании прежнего callsite
нельзя. Функция может иметь дальнейшие побочные эффекты; они здесь не раскрыты.

Декомпилятор использует unaff registers и местами неверно моделирует Swift ABI;
структура таблицы выше подтверждена ARM64. Имена зависимостей, скрытые sideeffects
и семантика discriminator требуют новых доказательств, а не переноса типов из
псевдокода.

## Bounded table/callback follow-up

Дополнительно разрешённый пакет прочитал ровно8×40байт статической таблицы,
пять уникальных callback, две thunk-relay и пять непосредственно вызываемых
writers. Все проходы использовали тот же существующий project с
`-noanalysis -readOnly`, SHA guard и exit0; markers сохранены в индексе.
Это несколько последовательных headless запусков внутри одного ограниченного
вопроса, а не утверждение об одном вызове инструмента. Новых imports нет.

Loaded pointer values и Ghidra DATA references в таблице согласовались и
указывали на существующие функции. Для callback не применялись эвристические
маски к raw chained-fixup словам. Large Swift String key разрешён с учётом
32-байтного смещения object representation; чтение по голому pointer без
смещения даёт соседнюю строку/заголовок и привело бы к неверной mapping.

| Event | Callback / relay | Writer(+1) | Категория |
|---|---|---|---|
| caramba_autoswitch | 0x1000458e8 → 0x1000424b4 | 0x10002f390 | autoswitch |
| caramba_autoswitch_user | тот же | 0x10002f390 | autoswitch |
| caramba_autocorrect | 0x1000424d8 | 0x10002f778 | cupertino |
| caramba_yofikator | 0x1000424fc | 0x10002fb64 | yofikator |
| caramba_doubleshift | 0x1000458ec → 0x100042520 | 0x10003040c | doubleshift |
| caramba_singleshift | 0x100042544 | 0x10002ff50 | singleshift |
| caramba_double_caps | 0x1000458e8 → 0x1000424b4 | 0x10002f390 | autoswitch |
| caramba_selection_switch | 0x1000458ec → 0x100042520 | 0x10003040c | doubleshift |

Каждый callback передаёт writer аргумент1. В каждом writer чтение
`longLongForKey:` складывается с этим аргументом как signed64 с проверкой
overflow; результат передаётся `setLongLong:forKey:`. Например, у cupertino
ARM640x10002f7f4 читает,0x10002f804 выполняет ADDS,
0x10002f808 проверяет overflow,0x10002f848 вызывает setter.
У autoswitch ADDS находится на0x10002f41c, у doubleshift на0x100030498.

Ключ строится из `tech.caramba.switcher.counters.<category>:` и suffix,
полученного из0x10002db58. Точная семантика suffix в этом лимите не раскрыта;
сходство с lazy deviceID metadata не позволяет выдавать это за доказанный ID.
Затем writer обходит `dictionaryRepresentation`, отбирает ключи с соответствующим
prefix и разделителем «:», суммирует значения, прошедшие dynamic cast вInt64,
и публикует сумму через Combine.Published. Это статическая формула **счётчика**:
`ownKey := checkedAdd(oldValue, 1); displayedCategory := checkedSum(matching Int64 values)`.
Это не формула сэкономленных секунд. Конкретный класс store, sync/restart/reset
и поведение при значениях другого типа требуют отдельных проверок.

Важная граница: dispatch посылает `caramba_selection_switch` на0x1002538bc
**до** вызова converter0x10025935c на0x1002538c8. Следовательно, нельзя переносить
на оригинал контракт LayoutPilot «только подтверждённая успешная замена+1».
Это event-based static path; runtime execution/order и ситуация неудачной
конверсии в текущем F13-проходе не проверялись. Double Caps относится к
**autoswitch**, а selection conversion к **doubleshift**; отдельного double-caps
счётчика эта таблица не вводит. Категория sounds существует в metadata, но
не имеет строки в исследованных восьми event entries: её writer здесь не найден.

## Время: default-формула и runtime JSON override

Следующий разрешённый targeted проход ограничен **шестью новыми телами**:
0x10002eebc,0x1000519f0,0x10004c4f0,0x10004c6c0,0x10004fe90,0x100014290.
Обычные xrefs к двум string addresses и их Swift header addresses отсутствовали.
Это не было принято за отрицание: точный ADRP-page+ADD-offset поиск обнаружил
материализацию weights на0x10002eee0/0x10002eee4 в0x10002eebc и timing limits
на0x100051a00/0x100051a04 в0x1000519f0. Инструкции действительно вычитают0x20
и устанавливают tagged Swift String pointer. Whole-app inventory не создавалась.

### Взвешенное время по категории

0x10002eebc получает tuple effective weights через0x10004c4f0. Compiled defaults
передаются как6 Double: `[10,10,7,2,3,1]`. Первые два10 заданы FMOV
на0x10002eeec; четыре остальных прочитаны строго по constants
0x100410040/48/50/58 и равны7/2/3/1.

| Категория | Published keypath | Default seconds/event | Результат vector |
|---|---|---:|---:|
| autoswitch | 0x100410130 | 10 | 0 |
| cupertino | 0x100410178 | 10 | 1 |
| yofikator | 0x1004101c0 | 3 | 2 |
| doubleshift | 0x100410208 | 7 | 3 |
| singleshift | 0x100410250 | 2 | 4 |
| sounds | 0x100410298 | 1 | 5 |

Порядок tuple weights отличается от порядка возвращаемого vector: это учтено
по реальным stack loads, SCVTF и FMUL0x10002ef68–0x10002f120.
Для каждой категории `seconds[i] = Double(categoryCount[i]) * effectiveWeight[i]`.
Это восстановленная **покомпонентная** формула; суммирование этих шести значений
в общий UI-total в исследованной цепочке не обнаружено и не объявляется фактом.

UI consumer0x10004fe90 вызывает weighted getter на0x10004ff34 и formatter
для vector indices0/1/2/4 на0x10004ff44/0x10004fff4/0x10005009c/0x100050144,
передавая строки вfeature tiles0..3. Здесь нет FADD-суммы и нет подтверждённого
вызова formatter для doubleShift/sounds. Доступность прочих UI поверхностей
этим локальным consumer не опровергается.

### Источник effective weights/limits и предел доказательства

Helpers0x10004c4f0 (6 weights) и0x10004c6c0 (4 limits) сначала сохраняют compiled
defaults, проверяют gate по имени параметра через0x100014290, затем запрашивают
строку параметра **`__json`** через0x1000147ac. Неотключённый и непустой override
преобразуется вUTF8 Data и декодируется JSONDecoder в соответствующую модель.
Если gate off, строка отсутствует, data conversion/JSON decode не удались,
helpers возвращают compiled defaults. ARM64 error-path сохранён отдельно:
например,0x10004c640–0x10004c6bc и0x10004c804–0x10004c848.

Gate0x100014290 разбирает small/large Swift String и вызывает engine-side
0x10025e150 для подходящего representation. Тело parameter getter0x1000147ac,
engine backend и JSON schema в лимит6тел не вошли. Поэтому **удалённость**
конфига, его cache/local storage, фактически действующие значения и имена JSON
полей не установлены. Сам runtime JSON override доказан статически; называть
compiled defaults единственно возможными рабочими весами нельзя.
Личные preferences и данные cloud/cache не читались.

### Форматирование времени

0x1000519f0 вызывает limits helper с default tuple
`(60,3600,Double.greatestFiniteMagnitude,Double.greatestFiniteMagnitude)`.
Для обычного конечного неотрицательного времени и допустимого Int64 диапазона:

- при `t <= 3600` выводит `trunc(t/60)` минут;
- при `t > 3600` ниже следующего effective limit выводит `trunc(t/3600)` часов;
- следующие настраиваемые диапазоны считают день как `trunc(t/28800)`
  (8 рабочих часов), неделю как `trunc(t/144000)` (5 рабочих дней).

Default day/week thresholds равны наибольшему конечному Double; обычный finite
ввод практически остаётся вminute/hour диапазонах. Для экстремальных значений
проверки NaN/finite/Int64 conversion могут привести к trap; это не normal input
и не основание намеренно копировать trap в LayoutPilot.
Нижний tuple element60 не используется как threshold minute→hour: сравнения
0x100051a3c–0x100051a74 используют возвращённые d1/d2/d3. Формулы используют
фиксированные делители60/60/8/5, не значения limits tuple.

Отсюда статические boundary-примеры при compiled defaults:59с→0мин,
60с→1мин,3600с→60мин,3600.1с→1час. Это вычисленные следствия инструкций,
**не выполненные native/UI тесты**. Формат plural/zero в отдельных localized
helpers и фактический override могут менять представление; они не проверялись.

## Точное продолжение

1. Если требуется воспроизвести фактический runtime config: только getter
   0x1000147ac/engine0x10025e150 и модели decode weights/limits, затем допустимый
   синтетический readback effective values. Не читать личные preferences ради
   угадывания defaults и не выдавать runtime override за shipped constant.
2. Отдельно закрыть async descriptor0x100410650→0x1000429f4 и getter suffix
   0x10002db58 при необходимости полного сквозного graph/persistence semantics.
3. Проверить synthetic positive/negative/boundary для event counters,
   restart/reset/sync и sounds; затем native/UI time boundaries. Статический
   marker до selection converter не доказывает успешную текстовую замену.

Эти последующие шаги не исполнялись. Все headless процессы завершились exit0;
GUI/Core, оригинал и пользовательский clipboard в F13-исследовании не менялись.


## Подготовленная самостоятельная реализация LayoutPilot

Добавлены UsageStatistics/UsageCategory с указанными compiled weights, Store
adapter и пять строк статистики действий. Это собственная реализация с counts-only
JSON `statistics.v1`, без engine config оригинала и без исходного текста/буфера
обмена/идентификаторов приложений. Прежний `corrected` сохраняется; его неизвестная
история не распределяется по категориям и не получает оценку времени.

Контракт отличается осознанно: наши correction counters вызываются только после
подтверждённой текстовой замены, Single Shift после проверенной смены TIS, sound
после NSSound.play()==true. К Core/API подключение KeyboardService выполняет
основной агент; наличие API само по себе не доказывает native-интеграцию.
Наша общая оценка — сумма известных категорий; оригинальный общий UI-total
не установлен. Для t<60сек собственный интерфейс показывает секунды вместо0мин.

Отрицательные/неизвестные JSON counts отклоняются, арифметика насыщается Int64.max.
Повреждённая saved JSON запись остаётся нетронутой: категории тогда доступны
только в текущем сеансе с предупреждением, а старый общий итог продолжает
сохраняться. Следующий запуск сохраняет этот общий итог как неизвестную историю.
Новые объекты никогда молча не заменяют повреждённую запись нулями.

`statisticsChecks()` подключён основным агентом; после исправления init order
и нормализации нулевых counts исполнено **451/451 CLI offline invariants**.
Actual-Store probe с уникальным named defaults suite прошёл **22/22**;
[финальный отчёт](../research/evidence/replay-stats-store-probe.json),
CLI selftest (лог `replay-stats-cli-selftest2.log` не сохранён: `*.log` исключался из Git).
Это исполнение самостоятельной реализации, не native/UI или original parity.
Первый Store probe21/22 сохранён отдельно: restart equality обнаружила sparse
counts доencode против canonical counts послеdecode. Данные не терялись;
Core теперь нормализует zero categories и содержит partial-roundtrip regression.
Повреждённые статистические данные вactualStoreprobe не были перезаписаны,
старый итог и bytes обычных настроек сохранены, уникальный suite очищен.
NSSound не воспроизводился; runtime sound acceptance остаётся открытым.


GUI debug build после этих исправлений прошёл: build2 log не сохранён (`replay-stats-gui-debug-build2.log` исключался из Git правилом `*.log`).
[Идентичности исходников/бинарников и границы проверки](../research/evidence/replay-stats-implementation-checks.json).
Приложение не запускалось, dist не пересобирался; внешний вид и native mapping
этим build не подтверждены. Линкер сообщил известные отсутствующие search paths
вCommandLineTools, сборка завершилась exit0.
