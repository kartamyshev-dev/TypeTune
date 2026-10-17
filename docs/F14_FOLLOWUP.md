# F14: запись User Rules, veto и граница автоматического обучения

Продолжение `UNDO_RESEARCH.md`. Исходный arm64 SHA-256:
`19d0057a9bfc38ba590babff82b28b5bf496c0833bbbd221f502722c6e2a26e9`.
Все новые запросы — к существующему persistent Ghidra project,
`-process caramba-arm64 -noanalysis -readOnly`, с проверкой SHA в script.
Новых imports0. Это Ghidra-complement к ранее сохранённым REA Evidence;
новые REA Evidence IDs не выдумывались. Native/UI/личные данные не читались.
Приватные инструкции/псевдокод не включены в публичный отчёт.
Индекс: `research/evidence/f14-followup-findings.json`.

## Установлен конкретный путь сохранения ручного правила

`0x10004732c` (SwiftUI handler) и `0x100054e0c`
(ExceptionsViewController, `_userDict`) обрабатывают непустую строку,
проверяют её через regexCache и engine helper `0x10025e364`, получают
связанные данные через `0x10025ed64`, затем создают background task.
Их closure `0x100049dac` передаёт context, захваченные данные и строку в
**`0x10000d20c`**, конкретный upsert managed object.

Setter callsites установлены по xrefs реальных Objective-C selector stubs,
а не по строке имени Swift-метода:

| Callsite | Stub | Действие |
|---|---|---|
| `0x10000d53c` | `0x1003ff5c0` | setPattern(input) |
| `0x10000d550` | `0x100400820` | setVisible(true) |
| `0x10000d55c` | `0x1003fd660` | setAdditions(0) |
| `0x10000d56c` | `0x1003fe280` | setDisabled(false) |

Upsert выбирает записи entity, ищет точное совпадение pattern либо создаёт
новый объект. Дополнительный список связанных строк используется для удаления
других совпадающих записей; его полное языковое назначение пока не установлено.
В этом writer **нет инкремента additions**. Наличие поля Int16 в модели не
доказывает счётчик отмен или обучение после N нажатий.

Background closure `0x10000fc30` передаёт захваченные callbacks в
`0x100010310`. Последний сначала вызывает mutation callback с context,
затем **context.save**. При save=false конвертирует NSError и вызывает
обработчик ошибки; успешная ветвь ставит completion на main queue.
Только успешное сохранение ведёт к refresh через
`0x100049dc8 → 0x10000d7ac → 0x10000dbb0`.
Следовательно, доказан persisted trigger **ручного принятого добавления правила**;
это не доказательство автоматического обучения при Backspace.

## Что значит veto/exclusion в прослеженных слоях

Fetch `0x10000dd24` действительно читает Core Data pattern, disabled, additions,
visible и собирает записи размером0x28. Смещения относительно record:
pattern0x00..0x0f, disabled0x10, additions0x18, visible0x20.

Refresh `0x10000e0c4` сначала допускает **visible==true**, выполняет validation
regex/engine и строит Published список; затем из его pattern строит
`AutoswitchExceptionsStore.patternSet`. Поля disabled/additions сохраняются
в списке, но в этом refresh не обнаружено отдельного условия disabled.
Из этого нельзя автоматически вывести, что disabled игнорируется всей
программой: другой слой может применять его при синхронизации model state.

Сохранённый REA `0x10004214c`, Evidence
`ev_ac920bff0a0e35a9a73540f5adf4dc23c90f2f28b74a258879f3dcfd2471acb2`,
проверяет **точное членство Swift String в hash set**. В этой функции нет
substring/regex поиска и нет lowercasing. Передающий вызывающий код может
нормализовать строку отдельно; полную end-to-end чувствительность к регистру
по одному matcher объявлять нельзя. `0x100042234` берёт patternSet и вызывает
этот matcher. Engine dispatch использует результат как один из gates, но
ранее описанный model gate и Undo не сведены к одной этой проверке.

## Collision event не установлен как обучение

`0x100259288` превращает event name и payload в CFString и вызывает
`0x100042568`. Новый прослеженный bridge:
`0x100042568 → async descriptor0x100410650 → 0x1000429f4 → 0x100042698 → 0x100042704`.
Bridge захватывает в async object только Swift String имени события; второй
параметр удерживает/освобождает, но в захваченную строку не передаёт.
Consumer ищет имя в event dictionary, обновляет категорию/звук/callback.
Этот путь не доказывает запись переданного слова в User Rules.
Название `caramba_collision` само по себе поэтому не является learning trigger.
Полный набор callbacks event dictionary в этом проходе не раскрыт.

## Что осталось открытым

- **Связь Backspace/отмены с сохранением правила не установлена.** Старый
  eligibility/correction-state путь из `UNDO_RESEARCH` остаётся отдельным.
- Не найден подтверждённый writer, увеличивающий additions, и не установлен
  порог/условие автоматического предложения User Rules.
- В проанализированном project у четырёх setter stubs единственный прямой
  caller — ручной writer `0x10000d20c`. Это bounded xref-результат, не исключение
  dynamic Objective-C/KVC/indirect writers.
- Readonly static path подтверждает наличие вызова save и ветки ошибки,
  но не успешную запись на конкретном live пользовательском состоянии.
- Regex/engine validation и обработка disabled вне refresh восстановлены
  частично. Набор оригинальных регулярных выражений/словарей сюда не перенесён.

Следующий точный вопрос: callbacks в initializer event dictionary `0x100042364`
и фактические caller-ветви сохранённого correction eligibility; отдельно
проверить KVC/dynamic setter путь, если direct refs не дают increment.
Для завершения F14 потребуются синтетические native действия с заранее
сохранённым исходным состоянием, а не перенос PASS ядра прототипа.


## Уточнение 2026-10-16: event callbacks и eligibility caller branches

Индекс нового ограниченного прохода:
[`f14-trigger-followup-findings.json`](../research/evidence/f14-trigger-followup-findings.json),
авторский ID `LP-F14-TRIGGER-20261016-01`. Получено одно новое semantic body
(лимит6 не исчерпан): **`0x100042364`**, 336 байт, псевдокод + полный ARM64.
Callbacks и их writers повторно не декомпилировались: использованы уже
сохранённые `stats-table-followup`, `stats-writer-followup`,
`stats-last-writer-followup`. Новых REA Evidence IDs0, imports0.
Три последовательных открытия existing project были readOnly/noanalysis;
после завершения 9 project files совпали по SHA-256, Java не осталось.

Initializer `0x100042364` строит словарь из **8 статических записей по40 байт**,
источник `0x100590750..0x10059088f`. Ключ — Swift String, значение содержит
category byte, отдельный bool и closure(code/context). Копирование видно
в `0x1000423c0–0x100042434`, шаг0x28/8 итераций —
`0x100042444–0x100042450`. Исходные ключи проверены по точным string bytes
frozen Mach-O; указатель таблицы указывает на Swift carrier перед строкой,
поэтому простой dump с начала carrier давал соседний literal.

| Событие | Category/bool | Callback → writer |
|---|---|---|
| caramba_autoswitch | 0/1 | 458e8 → 424b4 → 2f390(1) |
| caramba_autoswitch_user | 0/1 | 458e8 → 424b4 → 2f390(1) |
| caramba_autocorrect | 3/1 | 424d8 → 2f778(1) |
| caramba_yofikator | 4/1 | 424fc → 2fb64(1) |
| caramba_doubleshift | 1/1 | 458ec → 42520 → 3040c(1) |
| caramba_singleshift | 2/0 | 42544 → 2ff50(1) |
| caramba_double_caps | 6/1 | 458e8 → 424b4 → 2f390(1) |
| caramba_selection_switch | 1/1 | 458ec → 42520 → 3040c(1) |

В таблице адреса сокращены только для читаемости: к каждой записи callback
и writer следует добавить префикс `0x1000`. Это **счётчики событий**, не
`UserRules.additions`: каждый из пяти writers читает longLong по ключу
NSUserDefaults, прибавляет аргумент1 и пишет setLongLong:forKey:, затем
пересчитывает Published статистику. Нет перехода к managed-object writer,
полям pattern/additions/visible/disabled или background context.save в этих
callback chains. `caramba_collision` среди восьми ключей отсутствует.
Упомянутый ранее полный набор callbacks теперь установлен; отсутствие
регистрации collision относится только к этому словарю данной сборки.

Xrefs `0x100255a14` дали **ровно3 прямых callsites**:
`0x1002528cc` в `0x100251f20` и `0x10025e4e0`/`0x10025e53c`
в `0x10025e364`. Первый уже сохранённый dispatch читает correction snapshot
через `0x100255918` (`0x100252858`), при пустом текущем буфере проверяет
сохранённую строку, выбирает прежний input source и переставляет **только
оперативное correction state** в variant `0x8000000000000002`.
Второй caller — ранее восстановленный validator ручного добавления строки;
эти два callsites не являются отдельным автоматическим writer.
Прямых других callers по reference manager этого project нет.
Доказательства dispatch: REA
`ev_e32289eb3e357ec8d496c1023b5a756031e22c46f0f1cc2d84521461e7c6968f`,
сверка с ранее зафиксированными ARM64 anchors `0x100252844–0x100252910`.

Практический результат — **закрыт конкретный подозреваемый путь**
`event callback/collision → additions increment/save`: этот name-only bridge
вызывает статистические callbacks, а eligibility branch меняет память/раскладку.
Он не подтверждает автоматическое обучение. Это не доказательство отсутствия
автообучения вообще: dynamic KVC/ObjC paths, другие callbacks и иной механизм
хранения здесь не исключены. Порог отмен, increment additions и persist after
restart остаются UNKNOWN; придумывать их для спецификации оригинала нельзя.
Дальнейший содержательный шаг — синтетическое наблюдение отмены и readback
только собственной тестовой записи, позволяющее выбрать новый writer; повторять
generic hash/alloc или уже установленный manual upsert не требуется.

## Native-наблюдение 16 октября: Backspace не воспроизвёл обучение

На неизменённом оригинале выполнены12 ограниченных случаев в новом синтетическом
TextEdit-документе: ghbdtn без границы/послеSpace, отсутствие жеста, один и два
Backspace, повтор. Оригинал исправлял раскладку; один Backspace удалял один
предыдущий символ, два — два. Автоматическая отмена раскладки в этих случаях
не наблюдалась. Перед/после User Rules содержали0 строк, синтетической добавки
не появилось. Это ограниченный отрицательный результат; другие триггеры обучения
не исключены. Native modifier/input-source финальное состояние проверено отдельно.

Evidence: accelerated-f14-original.json, accelerated-f14-{before,after}.json,
accelerated-f14-verification.json и accelerated-f14-final-input-state.json.
После штатного выхода оригинала redb восстановлен побайтно из новой согласованной
резервной копии; постэкспериментальная копия оставлена приватно для восстановления.
Настройки функций не менялись; StoreKit изменил только timestamp проверки.
Оригинальный app bundle не изменялся. Это не принятие полного F14 parity.
