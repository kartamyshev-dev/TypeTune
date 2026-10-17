# Происхождение событий: дифференциал и границы причины

2026-10-15, arm64 оригинал SHA-256
`19d0057a9bfc38ba590babff82b28b5bf496c0833bbbd221f502722c6e2a26e9`.
Индекс: [input-origin-findings.json](../research/evidence/input-origin-findings.json).
Самостоятельный статический worker не запускал приложения, не выдавал клавиши
и не менял UI/настройки. Ниже runtime наблюдения взяты из отдельных сохранённых
опытов координатора; статический анализ не подменяет их и не устанавливает
причину только по корреляции source state.

**Текущий итог:** при контролируемом повторе baseline и оригинал принимают оба
варианта источника. Без переключателей оба сохраняют `ghbdtn `; с одной Caramba
оба дают `привет ` и RussianWin. Раннее различие источников **не воспроизведено**;
гипотеза об отказе private source не считается установленной причиной.

## Исторический дифференциал до контролируемого повтора

В изолированном Chrome rich fixture исходный источник ABC и auto-on:

- `phase3-original-input-auto-on-verified.json`: private-state помощник набрал
  `ghbdtn`, до Space текст `ghbdtn`, после двух пробелов `ghbdtn  `, источник
  остался ABC. Ожидание исправления не выполнено.
- `phase3-original-hid-source.json`: источник событий HID state1. После трёх
  букв источник уже RussianWin; **до Space** в поле `привет`, после двух
  пробелов `привет  `, курсор8/выделение0. Ожидание выполнено.

Первый JSON ещё не записывает `eventSourceState` у каждого события; private-state
идентичность этого запуска установлена исходным режимом помощника и журналом
опыта координатора. Второй явно записывает1. Это ограничивает самостоятельную
атрибуцию первого опыта только по JSON. Хеши обоих результатов закреплены.

SDK `CGEventTypes.h` подтверждает enum: source PID field41, userData42,
sourceStateID45; **аргумент конструктора** private state=-1, HID state=1.
Запрошенный enum нельзя подставлять вместо фактического field45: созданный
private source получает собственный opaque ID, который в новых опытах положителен.
Эти константы сами по себе не доказывают чтение свойств оригиналом.

## Дополнение: пассивный observer на LayoutPilot

Сохранены `phase3-origin-pilot-private-flags.json` и
`phase3-origin-pilot-hid-flags.json`. Оба опыта завершились: собственные14
событий наблюдались14/14 на каждом из cghid/cgSession. Они относятся к
LayoutPilot; это не пассивное наблюдение внутреннего исполнения Caramba.

| Значение | Requested private | Requested HID |
|---|---|---|
| Enum, переданный constructor | -1 | 1 |
| Фактический field45 у созданных и полученных событий | 1516266761 | 1 |
| Flags сразу после создания | 0 | 0 |
| Flags на обоих наблюдаемых tap | 536870912 (`0x20000000`) | 536870912 (`0x20000000`) |

Следовательно, назначать bit29 причиной исходного различия нельзя: в этой паре
он одинаков. Поиск явного `0x20000000`/bit29 в сохранённых main gate, decoder
и полном dispatch не установил отдельной проверки этого бита. Это ограниченный
поиск инструкций/литералов, не символическая трассировка всех составных masks.
Пассивный контроль с оригиналом нужен отдельно; исходные два опыта Caramba
не содержали полного сопоставимого trace flags/delivery. Последующий контроль
с оригиналом описан ниже и не воспроизвёл различие результата по source.

## Контролируемый повтор baseline / одна Caramba

Независимо проверены четыре result-файла: exact последовательность type/key,
timestamp/source identity для каждого наблюдаемого события, counts по tap,
flags, текст, курсор, раскладка, target/cleanup признаки. Условия «baseline без
переключателей» и «только Caramba, global auto on, без Chrome rule» установлены
preflight координатора; сами четыре result JSON не являются инвентаризацией
процессов или настроек. Их SHA закреплены в индексе.

| Файл / вариант | cghid | cgSession | Текст после Space, курсор | Источник после Space |
|---|---:|---:|---|---|
| `phase3-origin-baseline-private.json` | 14 | 14 | `ghbdtn `,7/0 | ABC |
| `phase3-origin-baseline-hid.json` | 14 | 14 | `ghbdtn `,7/0 | ABC |
| `phase3-origin-original-private-control.json` | 14 | 13 | `привет `,7/0 | RussianWin |
| `phase3-origin-original-hid-control.json` | 14 | 13 | `привет `,7/0 | RussianWin |

Во всех четырёх created/cghid потоках точные down/up пары keycodes
`5,4,11,2,17,45,49` (`g,h,b,d,t,n,Space`). У baseline session последовательность
полностью совпадает. В обоих original session trace отсутствует **только
исходное tagged keyDown type10/keyCode11**, то есть третья буква `b`;
её keyUp присутствует. Остальные type/key идут в исходном порядке,
добавочных tagged событий нет. Это наблюдение подавления/изменения потока,
**не доказательство ошибки доставки**: оригинал может подавить запускающее
исправление событие и выдать собственный повторный набор вне helper tag.

Проверка timestamps дала дополнительную границу: baseline и original HID
сохраняют timestamp identity всех присутствующих событий между tap. У original
private timestamps изменились у четырёх session событий: `b-up`, `d-down`,
`d-up`, `t-down`; source ID/flags при этом сохранены. Дельты сохранены в индексе.
Поэтому private original не отмечен как exact timestamp-identity PASS.
Это совместимо с replay/переписыванием событий, но точный механизм по этим
метаданным не устанавливается.

В обеих baseline и обеих original trace flags одинаковы `0x20000000`.
Private actual IDs меняются между источниками/запусками, HID actual ID1.
Ни constructor enum, ни bit29 не объясняют невоспроизведённый ранний отказ.
Все четыре probes завершены без trace overflow/disable/foreign input;
target guards и восстановление исходного источника/нейтральных модификаторов
подтверждены флагами результата. Отдельные AXURL ошибки-25212 сохранены;
отсутствие всех AX ошибок не заявляется.

## Проверенные callbacks и API

| Узел | Доказанный результат | Evidence |
|---|---|---|
| Secondary tap `0x1001ce2e4 → 0x1001c8910`, mask`0x1c00` | Callback имеет8байт и возвращает полученное событие без чтения полей и без изменений. Это не origin filter | pseudo `ev_e5f618b96c8727033a52f2c12b19b2f5e81ee6009460ce2cc35ffb93d92ad862`; ASM `ev_1553a01c4cb9e062f9e4a36debe81edb564580202061f77a05cd4efd66aebda3` |
| Main tap `0x10003e89c → 0x10003e968`, mask`0x1c06` | Callback удерживает event, передаёт type/event/context в gate`0x1000411fc`, освобождает временное удержание и возвращает результат gate. Origin metadata здесь не читается | pseudo `ev_1fcc051a516cbbcfaf60fd74d8108040b6c6543ef55ed57d2243e90687311694`; ASM `ev_e7ccc8bbe2fdd7ab248b1826a33f8302db49194e164b85e5aa9b344197a85ae4` |
| Integer field API`0x1003f1e0c` | Resolved direct references ведут к SingleShift`0x1000076c0` и wrapper`0x1002d2718`. Его code callers`0x10025e82c/86c/894` каждый передают field9, keycode | xrefs `ev_2816387e75b133278d3e019d3f6d2779a0a4c6bae7557de58c9ecea083216265`, `ev_a292b40074cdffc8cfdff07a6bf115c768d56cf8580bb8b401a792e70239b42f`; wrapper ASM `ev_7cc638553aed6d8497a67d382c635bedd6edecb93d543d108a1d88765e7b9a35` |
| Procedure-name inventory | Найдены GetFlags, GetIntegerValueField, SourceCreate; SourceGetSourceStateID/CreateFromEvent в этом inventory не найдены | `ev_d56b61a99c02030fda5b5edc1cd245dd297c79dcaf3cd627b3977ffe6cdff620` |

Main gate и Rust event decoder ранее проверены инструкциями:
`ev_688c920dc5b1b7fb68351c2335b067218eadc31cfe501cb222cc66fb63aa725d`,
`ev_ea292b3bb58925ad27fbb09082cf745c615e6e6e1ecef03f975569377bf62001`.
В resolved прямом пути **нет подтверждённого чтения41/42/45**. Data/vtable refs,
неразрешённые косвенные вызовы, динамическое разрешение API и внешние компоненты
не превращаются этим поиском в доказанное отсутствие фильтра во всём приложении.

## Вывод и точный следующий контроль

Ранние два опыта дали разный результат, но контролируемый повтор **не подтвердил
устойчивого source differential**. Причина раннего различия пока неизвестна.
Найденный secondary callback — passthrough; main callback тоже не фильтрует
по origin. Гипотеза «Caramba явно отвергает private source по field45» не
подтвердилась в исследованном пути. Объявлять её восстановленным алгоритмом нельзя.

Пассивный контроль координатора выполнен: входной cghid видит все14 событий
обоих вариантов и baseline, и оригинала; текст оригинала исправлен в обоих.
Новая гипотеза о фильтре/сбое маршрута не вводится. Дополнительное расследование
раннего отказа имеет смысл после его повторного воспроизведения с точным
preflight, trace и состоянием движка. Один синтетический токен на вариант
не является полной приёмкой алгоритма или устойчивости.

## Дополнительный bounded результат eligibility

Получена `0x1002dfac8`: вызывает feature extractor`0x1002e0030`, перебирает
candidate records размером`0x28` и возвращает true при flagbit0 с учётом sentinel.
Прямого persistent writer в теле нет. Evidence pseudo
`ev_70b49bff3fb0ad93b1bcb4ff0a0680aa1628299bdc778e0d003917dea54696bd`, ASM
`ev_1c06051f78df1ee083cc8c9186c36d52b88ad8de0d3fd47376a43c8254fc8c32`.
Полный смысл категорий и обучения остаётся открытым: [UNDO_RESEARCH](UNDO_RESEARCH.md).

## Сохранение и lifecycle

Открыт matching phase3 snapshot; отсутствующий callback потребовал одного нового
readonly Ghidra import. Повторных проектов не создавалось. Экспорт содержит101
Evidence record, включая89 прежних; сохранён новый snapshot, сессия закрыта,
после закрытия `open=false`. `unknowns=0` export — отсутствие REA unknown objects,
не полнота алгоритмов. Cache snapshot разрежён:1 primitive/1 workflow; следующий
cache miss может снова потребовать import. Хеши export/snapshot — в индексе.
