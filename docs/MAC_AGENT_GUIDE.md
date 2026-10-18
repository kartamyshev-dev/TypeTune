# Инструкция для агента на Mac: проверка и исправление универсального режима

Документ для агента, который работает **на Mac пользователя** (решение пользователя 2026-10-18,
DECISIONS п. 31). Он заменяет [MAC_AGENT_HANDOFF](MAC_AGENT_HANDOFF.md). Прежде чем начать,
прочитай `AGENTS.md`: его правила главнее этого документа. Общение, коммиты и записи — по-русски.

Цель: пройти матрицу проверок (раздел 5) на одном коммите, найти причины сбоев по отчётам и
AX-пробнику, исправить их по одному и довести ветку `universal-input` до состояния, в котором
её можно предложить пользователю для слияния в `main`.

## 1. Что уже известно (на 2026-10-18, коммит `07d55dc` и новее)

Всё ниже — наблюдения пользователя по отчётам диагностики или выводы из кода. Историческая исходная таблица; актуальная ограниченная приёмка —
[verification P9](../research/evidence/mac-agent-p9-2026-10-18/verification.json). Полная готовность не принята.

| # | Проблема | Что показали отчёты | Что уже сделано | Статус |
| --- | --- | --- | --- | --- |
| P1 | Строка поиска Google в Chrome (google.com и новая вкладка): автоисправление первого слова не работает | `universal-observe: unreadable`; `unreadable-field: focusedField=false` (Chrome не отдаёт поле в фокусе); `web-accessibility: unsupported` — Chrome отклоняет `AXManualAccessibility` | Double Shift правит набранное слово вслепую (DECISIONS п. 30) — пользователь подтвердил, что работает | warm Google/newtab5/5 на6e07197; cold Chrome user manual PASS, «работает стабильно»; evidence chrome-cold-user-manual.json |
| P2 | «Защита» (блокировка, «Проверьте последний текст») после правки в Chrome | Сверка до правки совпала, через 150 мс поле не показало результат → `mutation-uncertain`. Одно чтение AX в Chrome — 30–54 мс | Подтверждение ждёт до 600 мс; «поле не изменилось» больше не блокирует (`81b0a28`) | ограниченно: Chrome и Telegram S7 по10 завершённых PASS; одна frontmost_changed попытка отдельно, без mutation-uncertain |
| P3 | Сотни `snapshot-failed deadlineExceeded` | Фоновые снимки прежнего механизма не укладываются в 60 мс в Chrome и занимают очередь AX | Таймер контекста в универсальном режиме выключен (`81b0a28`); снимки после событий остались | универсальная группа:0snapshot-failed/0faults в последних1000; итоговый trace включает legacy OFF deadline; не полный trace |
| P4 | Веб-приложение, установленное из Chrome: TypeTune не работает, флаг в строке меню не той раскладки | В v0.1.4 обёртка Chrome вне списка прежнего механизма | Универсальный режим работает в любом приложении; флаг сверяет раскладку раз в 0,5 с (`db82a82`) | AionUi S1–S4/S6–S9/S11 и S10 PASS на6e07197; S14 home command menu15/15 и SingleShift PASS; evidence mac-agent-s14-2026-10-18 |
| P5 | Быстрый набор во время правки в Telegram/Slack/VS Code | Чтение кода: воспроизведение проверяло прежний список приложений | `allowedFrontmost(for:)` (`5aeea11`) | Telegram S7 дополнительно10/10 PASS; Slack/VS Code SKIP_USER |
| P6 | Правила замены | `пшерги,` → «github,» сработало у пользователя | fixtures `corpus/user-rule-regressions.jsonl` | yf сохранён; TextEdit/Chrome input/textarea/Notes/AionUi ограниченный PASS на6e07197 |
| P7 | Сборка не запускалась на чужом Mac | CI без `.build`: `Trace/BPT trap` | `CoreResources` (`ec87be8`); CI проверяет запуск | закрыто в CI; опубликованная v0.1.4 затронута |
| P8 | TextEdit: пропуски в потоке 80 мс и состояние восстановления | Завершённые строки native-stream-80ms-v1 содержат ghbdtn; replay-route-rejected: только leaseFresh=false, 1 событие сохранено | Очередь восстановлена без изменения текста; 7c84860 повторяет route proof, 3244c81 — также подавленное событие, общий бюджет 2 повтора; 50 мс сохранены | **GUI ab020042/6e07197: TextEdit stream12/12=192 слова; Chrome/Telegram S7 по10 завершённых PASS, одна Chrome frontmost_changed попытка отдельно** |
| P9 | Первое слово пропускается при временно недоступном AX-фокусе | Safari ax-read cannotComplete 54 мс; следующая диагностика видит текст/каретку; Chrome newtab warm 4/5 | Повтор unreadable в прежнем бюджете 80 мс, selection/secure не повторяются; controller 93/93 | **GUI ab020042/6e07197: Google/newtab warm по5/5, Safari input5/5; остальные ограниченные группы — matrix P9** |

## 2. Жёсткие правила

1. **Текст пользователя важнее числа исправлений.** Не ослабляй проверки поля, барьер ввода,
   Secure Input и запрет на правку пароля ради результата. Лучше пропустить исправление,
   чем стереть чужой текст.
2. **Синтетический ввод.** NativeProbe — только в новых тестовых документах TextEdit (AGENTS.md).
   Вводить текст в другие приложения (Chrome, Telegram и т. д.) инструментом управления
   компьютером можно, только если пользователь **в этой сессии** явно разрешил это одной фразой.
   Запиши разрешение в журнал с датой. Без него — проси пользователя выполнить шаг и сообщить
   результат. В чужих аккаунтах ничего не отправляй: только черновики, пустые поля, поиск без Enter.
3. **Один переключатель.** Caramba, Lang Switcher и другие копии TypeTune завершены
   (`ps -axo pid=,comm= | grep -E 'Caramba|Lang ?Switcher|LayoutPilot|TypeTune'` — одна строка).
4. **Один коммит — одно исправление.** После любого изменения кода прежние PASS не действуют:
   пересобери, переустанови и повтори затронутые проверки на новом коммите.
5. **Коммиты** от `kartamyshev <vs.kartamyshev@gmail.com>`, сообщения по-русски, push только
   в `universal-input`. В `main` не сливай — это решение пользователя.
6. **Не добавляй в Git** бинарники, `research/private`, данные Caramba, тексты пользователя,
   скриншоты с личными данными.
7. **Остановись и спроси пользователя**, если: текст испорчен или потерян; TypeTune требует ⌘⌥R
   или «Проверьте последний текст» и ты не понимаешь почему; нужно действие в системных
   настройках; исправление требует менять решение из DECISIONS; две попытки исправить одну
   проблему не дали результата.
8. В конце восстанови исходное состояние (раздел 9).

## 3. Подготовка

```sh
cd <клон TypeTune>
git fetch origin && git switch universal-input && git pull --ff-only
git config user.name kartamyshev && git config user.email vs.kartamyshev@gmail.com
git rev-parse HEAD                 # проверяемый коммит
git status --porcelain             # пусто
scripts/ci_core.sh                 # exit 0
scripts/runtime_recovery_probe.sh  # "passed": true
scripts/ax_focus_probe.sh --build-only
```

Каталоги: `E=research/evidence/mac-agent-$(date +%Y-%m-%d)` (в Git),
`P=research/private/mac-agent-$(date +%Y-%m-%d)` (не в Git).

**Снимок исходного состояния** (в `$P`, без настроек в `$E`):

```sh
defaults export dev.layoutpilot.mac $P/defaults-before.plist
ditto /Applications/TypeTune.app $P/TypeTune-before.app
shasum -a 256 /Applications/TypeTune.app/Contents/MacOS/LayoutPilot > $P/installed-before.sha256
defaults read com.apple.HIToolbox AppleSelectedInputSources > $P/input-source-before.txt
```

**Сборка и установка:**

```sh
scripts/build.sh && dist/layoutpilot-cli selftest
osascript -e 'quit app "TypeTune"' || true
rm -rf /Applications/TypeTune.app && ditto dist/LayoutPilot.app /Applications/TypeTune.app
shasum -a 256 /Applications/TypeTune.app/Contents/MacOS/LayoutPilot | tee $E/installed.sha256
```

Попроси пользователя удалить и снова добавить TypeTune в «Универсальный доступ» и «Мониторинг
ввода», затем запусти приложение. Подсказка флага должна показывать «Работает». Терминалу, из
которого запускается `scripts/ax_focus_probe.sh`, тоже нужен «Универсальный доступ».

Альтернатива сборке — артефакт CI `TypeTune-test-<коммит>` (см. [MAC_MANUAL_CHECK](MAC_MANUAL_CHECK.md)).

## 4. Инструменты

### 4.1 Отчёт диагностики TypeTune

Настройки → «Сохранить отчёт…» — последние 1000 технических событий без текста. Сохраняй
сразу после проверки, копию — в `$P`, разбор — в `$E`. Разбор:

```sh
python3 - <<'PY' "$P/report.json"
import json, sys
d = json.load(open(sys.argv[1])); r = d['records']; t0 = r[0]['uptime']
for x in r:
    if x['phase'] in ('gesture-modifier', 'snapshot-failed'): continue
    print(f"{x['uptime']-t0:8.2f} rev{x['revision']:>5} {x['phase']:<24} {x.get('reason') or ''} {x.get('checks', {})}")
PY
```

Ключевые записи универсального режима:

| Запись | Смысл |
| --- | --- |
| `universal-boundary` | пробел завершил слово: `tokenBuffered`, `decision` (есть ли исправление), `anchored` (известна граница слова слева) |
| `universal-begin` | правка начата (`anchored`, `selection`) |
| `universal-observe` | что сверка увидела в поле: `text`, `selection` (выделение/автодополнение), `unreadable`, `secure` |
| `unreadable-field` | при `unreadable`: роль поля и какие атрибуты оно отдаёт (`focusedField=false` — приложение не отдало поле вообще) |
| `universal-verify` | решение: `readable`, `fieldMatches` (можно править), `current` |
| `universal-result` | итог: `confirmed`, `notShown` (поле не изменилось), `readable` |
| `web-accessibility` | ответ приложения на `AXManualAccessibility` (`accepted` / `unsupported`) |
| `fault mutation-uncertain` | «защита»: правка отправлена, поле показывает ни прежний, ни новый текст |
| `source-selection` | смена раскладки после правки (`deferred` — после воспроизведения ввода) |

### 4.2 AX-пробник поля в фокусе

```sh
scripts/ax_focus_probe.sh --delay 4 > $P/probe-<случай>.json   # за 4 с кликни в поле
scripts/ax_focus_probe.sh --delay 4 --manual                     # сначала AXManualAccessibility
scripts/ax_focus_probe.sh --delay 4 --enhanced                   # сначала AXEnhancedUserInterface
scripts/ax_focus_probe.sh --delay 0 --reset-enhanced             # вернуть AXEnhancedUserInterface=false
```

Печатает без текста: статус `AXFocusedUIElement`, роль, все атрибуты (строки — только длина),
диапазоны выделения, изменяемость и шесть предков. В `$E` клади вывод целиком: текста в нём нет,
но проверь, что длины строк не выдают личные данные (например, пароль).

### 4.3 Прочее

- **Accessibility Inspector** (Xcode → Open Developer Tool) — глазами посмотреть дерево AX.
- **chrome://accessibility** — какие режимы доступности Chrome включены глобально и для вкладки.
- **NativeProbe** — автоматические прогоны в TextEdit: `scripts/record_native_probe.py`,
  проверка `scripts/verify_native_suite.py` (как в [MAC_AGENT_HANDOFF](MAC_AGENT_HANDOFF.md), раздел 5).

## 5. Матрица проверок

Сначала поставь «Исправлять во всех приложениях» (по умолчанию включено). Для каждой клетки
запиши строку в `$E/matrix.json`: `{app, appVersion, field, scenario, result: PASS|FAIL|NOT_RUN,
observed, statusText, reportFile}`. `statusText` — подсказка флага в строке меню после шага.

### 5.1 Сценарии

| ID | Действие | Ожидание |
| --- | --- | --- |
| S1 | Клик в пустое поле, раскладка ABC, `ghbdtn ` | «привет », раскладка русская. В нечитаемом поле первое слово после клика **не** правится — это ожидаемо (DECISIONS п. 26, 30), отметь как `LIMIT`, а не FAIL |
| S2 | Сразу после S1: `vbh ` | «мир » в любом поле |
| S3 | Русская раскладка, `руддщ ` после пробела | «hello », раскладка английская |
| S4 | `ghbdtn` + Double Shift | «привет» в любом поле, включая нечитаемые |
| S5 | Выделить слово мышью + Double Shift; перед этим скопировать картинку | Слово преобразовано, ⌘V вставляет ту же картинку |
| S6 | После S2 ⌘⌥Z | Вернулось `vbh `, раскладка прежняя; слово запомнено (потом «Снова исправлять») |
| S7 | Быстро, без пауз: `ghbdtn vbh ghbdtn vbh ` | Все слова, кроме, возможно, первого после клика (S1), исправлены; порядок букв цел; нет ⌘⌥R и «Проверьте последний текст» |
| S8 | Клик в середину существующего слова, `ghbdtn ` | Чужое слово не испорчено |
| S9 | Одиночный Shift | Раскладка и флаг переключились |
| S10 | Переключиться в приложение и обратно 3 раза | Флаг совпадает с раскладкой; при расхождении — ID из подсказки флага |
| S11 | Правило `yf` → `на`, набрать `yf ` | «на » |
| S12 | Поле пароля (Safari, `sudo -v` в Terminal) | TypeTune ничего не делает |
| S13 | Включена автозамена macOS (Заметки/TextEdit), слово с опечаткой + пробел | Лишний текст не стёрт; допустимо «Исправление пропущено» |
| S14 | Поле с подсказками/автодополнением (адресная строка, поиск) | Подсказка не испорчена, нет блокировки |

### 5.2 Приложения и порядок

Порядок — по важности для пользователя. После каждой строки сохрани отчёт диагностики.

1. **Google Chrome**: строка поиска google.com; строка поиска новой вкладки; адресная строка;
   `<textarea>` на любой странице (например, поле комментария); `<input>`; contenteditable
   (Google Docs или любой онлайн-редактор); веб-приложение, установленное из Chrome. Сценарии
   S1–S10, S14. Для каждого поля — вывод AX-пробника.
2. **Safari**: страница и адресная строка (S1–S4, S12, S14).
3. **Telegram**, **Slack** (черновик, не отправлять), **VS Code** (редактор и поиск): S1–S9.
4. **TextEdit**: S1–S13, плюс NativeProbe-прогоны `corpus/native-smoke.json`,
   `native-review-fixes-v1.json`, `native-stream-80ms-v1.json` (`--interval-ms 80`).
5. **Заметки**, **Microsoft Word**, **Codex**: S1–S7, S13.
6. **Terminal** (zsh, без Return), **vim** в режиме вставки: S1–S4, S12.
7. **Выключенный режим**: снять «Исправлять во всех приложениях» → в TextEdit исправляет,
   в Заметках нет.

## 6. Как чинить известные проблемы

Каждое исправление: воспроизведи → отчёт и пробник → fixture или проверка (если логика в Core)
→ минимальная правка → `scripts/ci_core.sh` → сборка, установка → повтор сценария и S1–S4 в
TextEdit и Chrome → коммит с evidence → push → CI зелёный.

### S14 — выбранный inline suffix и меню PWA

На неизменном GUI ab020042 / код6e07197: Chrome и Safari numeric address inline suffix
по5/5; дополнение перед Space подтверждается точно по одному из максимум2 известных
значений и полному выделенному хвосту. Safari после Space может предложить новый suffix:
введённый префикс должен остаться точным, новое продолжение — целиком выделенным.
Это модель браузерной подсказки в тесте; production guards/таймауты не менялись.
AionUi home composer: /, /open, /open space по5, меню подтверждено CUA; SingleShift
при открытом меню сохранил команду/флаг, ничего не запускали. После меню auto5/5 + S7 PASS.
[Полный scope и непринятые exploratory attempts](../research/evidence/mac-agent-s14-2026-10-18/verification.json).
Это не приёмка всех сайтов, команд и окон PWA; S5 и пропущенные приложения не трогались.

### P1. Chrome не отдаёт веб-поле (строка поиска Google)

Код: `AccessibilityEditor.observeTextBeforeCaret`, `describeFocused`, `requestWebAccessibility`;
`KeyboardService.runKeystrokes` (сверка), `requestWebAccessibility(pid:trigger:)`.

1. Пробник в строке поиска без флагов. Если `focusedUIElementStatus` ≠ 0 или поле —
   не текстовое (нет `AXValue`/`AXSelectedTextRange`), запиши роль и атрибуты.
2. Тот же случай с `--manual` (ожидаемо `-25205`, unsupported) и с `--enhanced`. После
   `--enhanced` проверь, стало ли поле читаемым, затем обязательно `--reset-enhanced`.
3. Открой `chrome://accessibility`: какие режимы включены. Включи «Web accessibility» для
   вкладки и повтори пробник.
4. Сравни с `<textarea>` на обычной странице: читается ли там.

Варианты исправления, от лучшего к худшему:
- **Text markers**: если поле отдаёт `AXSelectedTextMarkerRange` и параметризованный
  `AXStringForTextMarkerRange`, читай текст перед кареткой через них в `observeTextBeforeCaret`.
- **`AXEnhancedUserInterface`** делает поле читаемым: ставить только для приложений семейства
  Chromium (`com.google.Chrome`, `com.google.Chrome.app.*`, Edge, Brave, Arc) и только если замеры
  показали, что в Chrome нет заметных побочных эффектов (анимации окон, менеджеры окон, нагрузка).
  Это меняет поведение чужого приложения — **сначала спроси пользователя**, запиши решение
  в DECISIONS.
- Если ничего не помогло: зафиксируй ограничение в STATUS и README («в строке поиска Google первое
  слово исправляется Double Shift»). Не разрешай вслепую автоисправление первого слова после клика
  без решения пользователя.

Готово, когда S1 в строке поиска google.com и новой вкладки даёт «привет » в 5 из 5 повторов,
а S8 в `<textarea>` не портит чужое слово.

### P2. Ложная «защита»

Код: `KeyboardService.performKeystrokes` (ожидание подтверждения 600 мс), `finishKeystrokes`
(`confirmed` / `notShown` / `unknown`).

Проверка: S7 в Chrome и Telegram, по 10 повторов. В отчёте не должно быть `mutation-uncertain`.
Если есть: посмотри `universal-result` и предшествующие `ax-read` (время). Если поле показывает
промежуточное состояние (часть Backspace уже применена), не увеличивай таймаут вслепую — сначала
выясни по пробнику, что видит AX. Блокировку при `unknown` не убирай без решения пользователя.

### P3. Лишние снимки поля

Исправлено в `d145971`: controller 83/83, ограниченная native-серия Chrome дала
0 snapshot-failed / 0 faults; TextEdit plain paste прошёл в smoke 13/13.
Это не закрывает остальные строки матрицы; evidence в mac-agent-p3-2026-10-18.


`snapshot-failed` в универсальном режиме — от `captureAfterEvent()` (переход в приложение,
клики, конец воспроизведения). Они нужны только ⌘⇧V прежнего механизма. Если в отчётах их по-
прежнему десятки и они идут рядом с `universal-*`, ограничь `captureAfterEvent` в универсальном
режиме случаями, где включён ⌘⇧V и приложение из прежнего списка. Проверка: ⌘⇧V в TextEdit работает.

### P4. Веб-приложение Chrome и флаг

S1–S4, S10 в веб-приложении. Если флаг не совпадает: ID из подсказки и вывод
`defaults read com.apple.HIToolbox AppleSelectedInputSources`. Код флага: `Sources/LayoutPilot/main.swift`
(`updateStatusItem`, таймер 0,5 с). Если TIS сообщает не ту раскладку, флаг тут не виноват —
запиши и спроси пользователя.

### P5. Быстрый набор в других приложениях

S7 в Telegram, Slack, VS Code по 10 повторов. В отчёте: `replay-route-rejected` или
`replay-event-rejected` с `allowed=false` — значит, проверка приложения всё ещё отсекает.
Код: `allowedFrontmost(for:)`, `drainReplay`.

### Сниппеты (ветка `snippets`)

Проверка S8 — чек-лист в [SNIPPETS_PLAN](SNIPPETS_PLAN.md#чек-лист-s8-для-mac-всё-not_run), те же правила
этого документа. Собирай ветку `snippets`; в отчёте ищи `snippet-begin`, `snippet-verify`, `snippet-result`.
Перед проверкой сохрани `~/Library/Application Support/LayoutPilot/snippets.json` в `$P` и верни его в конце.

### P10. Сниппет Telegram: LF представлен как U+2028

S8 на GUI `e862b158`/`4cf6030`: многострочная подпись вставлена без Return, но Telegram
показывает перевод строки как U+2028. Точная сверка LF не подтвердила результат:
`mutation-uncertain`, pending1. Trace сохранён до восстановления. Пользователь разрешил
исправить и повторить S8. Ожидаемое AX-представление меняется только у сниппетов Telegram,
включая preflight отмены; другие приложения, барьер и secure guards не меняются.
[Evidence](../research/evidence/snippets-s8-2026-10-18/initial-verification.json).
На `4af15f7` / GUI `04476538` targeted multiline native PASS; полная S8 не закрыта.

### P11. Chrome: многострочная вставка оставила пустое поле

На `4af15f7` / GUI `04476538`: после удаления сокращения подпись не появилась,
`snippet-result confirmed=false`, `mutation-uncertain`, pending1. Только пустой локальный
fixture. [Trace](../research/evidence/snippets-s8-2026-10-18/fixed/chrome-fault-report.json).
Пользователь разрешил исправление и повтор. Кандидат использует полный кадр Command/V,
как `pastePlainNative`; offline контроллер102/102. Native кандидата NOT_RUN, историческая
причина пустого paste не доказана. После установки сначала этот сценарий, затем S8.

### Новые проблемы

Каждая новая проблема получает номер P8, P9… в этом документе (таблица раздела 1) и строку в
журнале. Логика ядра — fixture в `corpus/*-regressions.jsonl` или проверка в selftest. Поведение
приложения — сценарий в этой матрице.

## 7. Что нельзя делать

- Отключать сверку поля, барьер или подтверждение, чтобы «заработало».
- Разрешать автоисправление вслепую без границы слова.
- Переносить результат одного коммита на другой.
- Объявлять полную готовность: условия PLAN не выполнены, четырёхчасовой прогон отложен.

## 8. Запись результатов

1. `$E/verification.json`: коммит, SHA-256 приложения, разрешение пользователя на ввод вне
   TextEdit (дата, формулировка), для каждой клетки матрицы — результат и файл отчёта; что NOT_RUN.
2. `docs/JOURNAL.md`: запись сверху — что, каким видом проверки (`agent native, user-authorized`,
   `native TextEdit, NativeProbe`), результат.
3. `docs/STATUS.md`: таблица проверок для коммита и точка продолжения.
4. Таблица раздела 1 этого документа: статусы P1–P7.
5. `docs/UNIVERSAL_INPUT_PLAN.md`: U8 закрывается только при PASS всей матрицы (кроме `LIMIT`).
6. Push в `universal-input`, дождись CI. Итог пользователю: что прошло, что упало, что
   исправлено (коммиты), что осталось, можно ли сливать в `main`.

## 9. Восстановление

1. Выученные тестовые слова — «Снова исправлять»; правило `yf` удалить, если его не было.
2. Сверить настройки: `defaults export dev.layoutpilot.mac -` против `$P/defaults-before.plist`.
3. Вернуть переключатели, которые менялись (автозамена macOS, «Исправлять во всех приложениях»,
   режимы в chrome://accessibility, `AXEnhancedUserInterface` через `--reset-enhanced`).
4. Раскладка — как в `$P/input-source-before.txt`.
5. Установленное приложение оставить новым, если пользователь не попросил вернуть прежнее.
6. `$E/state-after.json` и отличия от исходного состояния.
