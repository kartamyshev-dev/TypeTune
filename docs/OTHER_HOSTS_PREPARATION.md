# Подготовка Safari, Electron-редактора и Terminal

Проверка только чтением 2026-10-16; исходники HEAD
`45188395ead944f47c186d7cffd91224b573acbb` (рабочие изменения других задач
не проверены сборкой). Приложения не запускались, AX/UI/ввод не использовались.
Версии прочитаны из установленного `Contents/Info.plist`; наличие bundle
не доказывает пригодность его редактора.

| Цель | Установленный bundle | ID | Версия / build |
|---|---|---|---|
| Safari | `/Applications/Safari.app` | `com.apple.Safari` | 27.0.1 / 22625.1.29.11.28 |
| Electron: Cursor | `/Applications/Cursor.app` | `com.todesktop.230313mzl4w4u92` | 3.24.12 / 3.24.12 |
| Terminal | `/System/Applications/Utilities/Terminal.app` | `com.apple.Terminal` | 2.15 / 488 |
| Уже разрешённый браузер: Chrome | `/Applications/Google Chrome.app` | `com.google.Chrome` | 155.0.8059.40 / 8059.40 |

У Cursor присутствует `Contents/Frameworks/Electron Framework.framework`.
`/Applications/Visual Studio Code.app` отсутствует; другие места его установки
не искались. Chrome не считается Electron-редактором для приёмки PLAN.

## Общая граница существующего кода

`EditorSupport.insertionBackend` разрешает только TextEdit, Chrome и Codex.
Следовательно, три новые цели сейчас должны пропускаться без замены; простое
добавление ID в allowlist не является адаптером или доказательством поддержки.
`AccessibilityEditor.snapshot` требует AXTextArea, AXWindow, доступный AXValue
до65536 UTF-16 units, валидный AXSelectedTextRange, отсутствие защищённого ввода.
`sameTarget` сравнивает PID, AX field/window и document включая nil-переходы.
`replace` требует наблюдаемое выделение и совпадение AXSelectedText до записи,
затем точный текст и caret. Keyboard backend запрещает control characters.

Сначала для каждого нового поля нужен отдельный разрешённый read-only AX
профиль: роль/subrole, идентичность окна/документа, полный или частичный AXValue,
координаты выделения, settable-атрибуты. Не расширять роли или снимать проверки,
если профиль не совпал. Проверить две независимые цели внутри одного PID:
смена поля/вкладки должна отменять запись/replay. CGEvent не даёт атомарной
привязки к AX-полю; остающееся TOCTOU обозначать отдельно.

## Safari: две локальные цели

Основа fixture — `Tools/fixtures/chromium/index.html`: собственные textarea и
contenteditable, без сетевой отправки. Перед будущим запуском сделать отдельные
маркер страницы и labels `LP-SAFARI-<nonce>`; pin URL/title, PID, window и field.
Не использовать адресную строку, поиск или действующие пользовательские вкладки.

1. Профиль AX обоих полей и отрицательная проверка текущего запрета адаптера.
2. После отдельной реализации выбрать backend по наблюдаемой записи: AXSelectedText
   только при точном readback; иначе keyboard backend с теми же guards. Не переносить
   Chromium-особенность structural LF и комбинацию plain-paste в Safari автоматически.
3. В каждом поле: `ghbdtn `→`привет `, `hello ` без изменения; ручная конверсия
   выделения и отмена; Unicode/пунктуация; быстрый поток и смена цели между полями.
   Сверять весь текст, caret/selection, отсутствие потери/дублей и источник ввода.
4. Plain paste проверять отдельно после определения штатной команды Safari,
   с сохранением clipboard и форматирования соседнего текста.

## Cursor: только собственный текстовый файл

Fixture — новый отдельный каталог `research/private/hosts/cursor-<nonce>/`
и файл `layoutpilot-fixture-<nonce>.txt`, только синтетический текст. Pin точный
путь документа и редактор; не открывать существующий workspace, терминал, чат,
панель команд или настройки пользователя. Не менять глобальное включение
Accessibility редактора без отдельного обоснованного разрешения.

Monaco может отдавать AX-поле/значение лишь для части документа; это проверяемая
гипотеза, а не установленное поведение данного Cursor. Если нет полного текста
и согласованных UTF-16 range, текущий адаптер должен отказать. Возможный отдельный
адаптер потребует доказать модель локального range/строк и восстановления caret;
подмена AXTextArea на любую роль без этой модели недопустима.

После профиля: тот же короткий RU/EN/manual/undo набор, затем многострочный файл
с русским текстом и emoji, выделением через строку, изменением viewport и двумя
вкладками. Позитивные замены — только после подтверждения readback. Нельзя
переносить PASS Chrome или пользовательской проверки Codex на Cursor.

## Terminal: первоначально только отказ, без shell-команд

Текущий backend запрещён. AXTextArea терминала может быть экраном/scrollback,
а AXSelectedTextRange — выделением вывода, а не редактируемого prompt: это нужно
установить профилем, не применять обычную замену редактора вслепую.

Без безопасной fixture разрешён только read-only профиль и доказательство
отказа LayoutPilot. Не печатать даже тестовое слово в действующую shell-сессию.
Будущий положительный стенд требует отдельно согласованного нового окна/PTY
с инертным приёмником вместо shell: он принимает и показывает печатные символы,
никогда не исполняет их. Способ его запуска и доказательство pin этой сессии
согласуются до ввода; этот документ не разрешает запуск или команды.

В таком стенде payload только печатные `ghbdtn `, `hello ` и Unicode;
без Return/Enter, LF/CR, TAB, Escape, управляющих сочетаний, shell-команд и paste.
Не добавлять terminal-style blind Backspace, удаление prompt или переписывание
scrollback. Если невозможно доказать редактируемый диапазон, положительная
поддержка остаётся заблокированной; безопасный пропуск не считается её PASS.

## Разрешение и следующий шаг

AGENTS ограничивает NativeProbe новыми документами TextEdit; отдельный Chrome
уже разрешён. Для Safari/Cursor/Terminal сейчас нет разрешения на расширение
helper и синтетический ввод. До его получения допустимы этот документ, чтение
bundle и подготовка самостоятельных fixture-файлов; helper не менять/не запускать
для этих целей. Реальную проверку Codex выполняет пользователь.

Следующий конкретный шаг после разрешения: Safari read-only AX профиль локальной
страницы; Cursor — профиль нового txt; Terminal — только профиль/negative case,
пока не утверждён инертный PTY. Только затем выбирать и реализовывать адаптеры.
Оригинал и прототип никогда не запускать одновременно. AppExceptions оригинала
для этих трёх ID из существующего отчёта не установлены: RESEARCH подтверждает
схему, а прежние Chrome-опыты — только Chrome. Личная БД не читалась заново.

## Реализованная подготовка Safari (без native-запуска)

Добавлены самостоятельные файлы (начальный read-only этап; далее уточнены native modes):

- `Tools/SafariFixtureDiscovery.swift`: отдельный **только читающий** помощник,
  не зависит от SwiftPM/production adapter. Режим по умолчанию требует UUID,
  явно указанный PID Safari и `plain|rich`. Автоматического выбора приложения, activation, AX write, переключения раскладки
  и запроса доступа нет. В default/read режиме нет CGEvent post.
- `Tools/fixtures/safari/index.html`: localhost-страница с двумя полями;
  title/labels получают точный UUID token, без autofocus, сетевой отправки,
  clipboard, сохранения или журнала ввода. Без валидного token полей нет.
- `scripts/build_safari_discovery.sh`: только компиляция в
  `.build/safari-fixture-discovery`, без общей SwiftPM сборки или запуска.
- `scripts/serve_safari_fixture.sh`: отдельный, **не запущенный** сервер только
  `127.0.0.1:18764` с корнем в собственной fixture-директории.

Помощник повторно доказывает frontmost PID+bundle ID, pinned focused field,
field AXWindow и app focusedWindow, неизменный optional document, title token,
точный label и точный URL в ancestry (до24 узлов с обнаружением цикла).
До AXValue проверяется вся identity. Доступны только шесть синтетических значений
(`""`, структурный LF, `ghbdtn `, `привет `, `hello `, `первая🙂вторая`), до4096
UTF-16 units. Чужое содержимое не выводится и не сохраняется. Сверяются границы
selection; report содержит capability booleans, роль, длины и ranges, без текста.
Secure Input, Accessibility и нейтральность modifier keys/flags двух состояний
проверяются при каждом identity barrier; AX timeout0.15s. PostEvent доступ
только читается preflight, для discovery не запрашивается и не требуется.

Это capability discovery: `IsAttributeSettable` не доказывает работоспособность
замены. `writeCapabilityVerified=false`, `productionAdapterEnabled=false`,
В default/read режиме `eventCap=0`. Явные native modes ниже ограничены14
кадрами down/up. Код не содержит пути отправки Return, команд или paste.

Проверка: `sh scripts/build_safari_discovery.sh` завершилась exit0 на текущем
Mac; executable не запускался. Fixture и guards проверены чтением исходников,
не Safari/AX. Production allowlist, NativeProbe, KeyboardService, Store,
STATUS/FEATURES не изменялись. Cursor helper отложен, чтобы не расширять scope
до выяснения AX-модели Monaco.

### Конкретная граница следующего разрешения

Для следующего этапа нужно явно расширить разрешённый scope на **отдельную
Safari localhost-страницу**: запустить этот localhost server, открыть URL
`http://127.0.0.1:18764/?fixture=LP-SAFARI-<uuid>`, вручную/через разрешённый UI
выбрать только одно из её полей, затем запустить только read-only discovery:

```text
.build/safari-fixture-discovery --token <uuid> --pid <Safari PID> --field plain
```

Повтор для rich требует отдельного фокуса того же собственного окна.
Эта следующая операция не включает новый TCC grant, ввод, очистку полей,
AX setter или изменение allowlist. Она сейчас не выполнялась. Синтетический
ввод, ручные жесты, undo, plain paste и production adapter — отдельный следующий
шаг после чтения capability report и разрешения bounded сценариев. Для Terminal
и Codex никакой новой операции не подготовлено и не разрешено этим helper.

## Скомпилированные bounded native modes Safari

Добавлены только явные `--type-wrong` / `--type-correct` после обязательных
аргументов identity. Без последнего аргумента или с `--read` всё ещё только
чтение. Ни один из этих режимов пока не запускался.

```text
.build/safari-fixture-discovery --token <uuid> --pid <Safari PID> --field plain --type-wrong
.build/safari-fixture-discovery --token <uuid> --pid <Safari PID> --field rich --type-correct
```

Перед первой отправкой: exact own fixture, AXTextArea, **пустой** AXValue и
caret0 (структурный LF не принимается за пустоту), ранее выданный PostEvent
доступ, источник только ABC/US. Начальное непустое поле не очищается даже
если содержит синтетический текст: для следующего опыта нужна новая fixture.

Wrong: физические keycodes `g h b d t n Space`, ровно14 down/up кадров максимум.
Correct: `h e l l o Space`, максимум12, общий жёсткий предел14. Return/Tab/Delete,
modifier chords и остальные keycodes отсутствуют в whitelist. Clipboard и AX
setters отсутствуют. Источник не меняется помощником; при необходимости его
исходное состояние и переключение до опыта обеспечивает координатор.

Перед **каждым** single event повторяются URL/token/field/window/document/PID,
Secure Input, AX, PostEvent и neutral modifier guards. Проверяются также все
128 key states HID/session, кроме единственной собственной отслеженной
неотпущенной клавиши. Down требует end-caret без выделения и всё ещё ABC/US;
Up допустим только для своего Down. Значение во время опыта — исключительно
префиксы `ghbdtn `, `hello `, `привет `; чужое значение прекращает опыт без вывода
текста. Между кадрами25ms, заключительный readback через350ms. Отчёт успеха
означает завершение bounded доставки и проверки synthetic state, а не PASS
автоисправления: `functionalAcceptance=false`; итоговый синтетический текст
и range передаются для независимой оценки. События0/AX writes0 для read mode.

При отказе identity/security последующие события, включая cleanup, **не**
посылаются в новый target. Отчёт ошибки включает число реально posted кадров
и `ownedKeyReleasePending`; это причина остановить опыт и проверить клавиши,
а не автоматически переигрывать Down. Остаточное TOCTOU между последней
проверкой и CGEvent delivery сохраняется. Эмиссия HID требует отдельного
расширения разрешённого scope на эти конкретные Safari modes после review;
подготовленная компиляция не является таким разрешением. Production allowlist
всё ещё закрыт для Safari: проверка helper без адаптера не доказывает работу
LayoutPilot. Для оригинала и будущего адаптера нужны раздельные опыты с одним
активным переключателем.

Проверка обновления: отдельная `swiftc` сборка exit0; static readback единственного
post site, конечных keycode plans и отсутствия AX write/activation/clipboard/
permission-request API. Ни executable, ни Safari, ни сервер не запускались.

Добавлен явный `--read-background`: только чтение pinned PID Safari и его
собственного AX focused field/window с теми же exact URL/token/label/document,
Secure Input/permission/neutral guards. Для этого режима единственное отличие —
не требуется macOS frontmost PID; running PID всё равно должен принадлежать
`com.apple.Safari`. Режим не активирует окно и не имеет ветви post.
Default `--read` и оба native mode сохраняют frontmost guard. Два mode-флага
одновременно CLI не принимает. Скомпилирован, не запускался этим агентом.

### Явная активация только своей Safari fixture

В native modes разрешён дополнительный последний `--activate-own-fixture`.
Без него foreground guard остаётся прежним. Read modes этот флаг отклоняют.
До единственной попытки `NSRunningApplication.activate` полностью проверяются
pinned background Safari PID, field/window/document, exact URL/token/label,
Secure Input/AX/neutral keyboard и уже выданный PostEvent доступ. Только после
этого запрашивается activation; readonly ожидание frontmost ACK ограничено1s
с интервалом20ms и повторной проверкой pinned identity. Другая вкладка/поле
не активируется повторно и не переизбирается. После ACK frontmost становится
обязательным во всех последующих barriers. При timeout/смене target событий нет.
Скомпилировано отдельно; activation и ввод не выполнялись.

Пример reviewable следующего scope (ещё не исполнен):

```text
.build/safari-fixture-discovery --token <uuid> --pid <Safari PID> --field plain --type-wrong --activate-own-fixture
```

### Следующий selectedText capability probe — протокол до реализации

Readonly `selectedTextSettable=true` не открывает production adapter. Для
отдельного будущего AX-write probe нужен известный синтетический baseline
`ghbdtn`, caret6 и точный pinned target. После проверки всех guards сохранить
baseline text/range; AX-select0..6; дождаться именно этого selection и AXSelectedText
`ghbdtn`; повторно verify target/value/range; установить только `привет` через
AXSelectedText; принять positive только при полном AXValue `привет`, caret6,
сохранённой identity. Никаких Delete, управляющих событий и clipboard.

Negative сценарий должен прекращаться **до** setter при неверном baseline,
смене field/window/URL/document или range; отдельный штатный no-op/failure setter
принимать за uncertainty, не повторять запись вслепую. Снятие временного выделения
допустимо только когда target, baseline text и принадлежащий probe selected range
всё ещё совпадают. Нельзя использовать переписывание AXValue как rollback.
Сначала отдельные positive+negative evidence; затем production selectedText
backend для Safari с теми же подтверждёнными границами, и новый runtime retest.
Первоначально этот AX-write probe не был реализован; реализация описана ниже.
Он по-прежнему не запускался и требует отдельного разрешения на AX-запись.

### Реализованы seed и AX selectedText probe (compile-only)

`--type-seed` отправляет ровно12 down/up кадров `g h b d t n` без Space; общий
лимит14 и все native guards сохранены. Он создаёт baseline `ghbdtn`, caret6
для `--probe-selected-text`, если host ничего сам не преобразовал.

`--probe-selected-text` требует exact собственную identity, AXTextArea, только
`ghbdtn` и caret6; иное начальное состояние прекращает режим до AX setters
(`axWrites=0`, ошибка). Проверяются neutral flags и все128 key states; HID/
clipboard/source-change пути в этой ветке отсутствуют. Optional явная activation
имеет тот же предварительный identity barrier и bounded1s ACK. Для activation
сохраняется требование ранее выданного PostEvent доступа; сама AX-ветка без
activation этого доступа не требует.

AX-selection setter0..6 → ACK прежнего либо точного нового range за150ms →
AXSelectedText==ghbdtn → повтор полного baseline/range/identity → единственный
setter AXSelectedText=привет → точный полный AXValue=привет и caret6 за150ms.
Неожиданный текст/range/identity прекращает попытку. Deadline проверяется после
AX read: отдельный AX request ограничен messaging timeout0.15s, поэтому150ms
означает soft ACK deadline, не жёсткий wall-clock предел всей ветки.

При отказе после selection возможен только owned-selection rollback кcaret6,
если target тот же, полный текст всё ещёghbdtn и range всё ещё0..6. AXValue
никогда не переписывается. Отчёт содержит attempted AX setter count, boolean
rollback proof, eventsPosted0 и selectedTextReplacementVerified только после
точного readback. Подтверждение AX-записи не становится полной функциональной
приёмкой (`functionalAcceptance=false`) или включением Safari в allowlist.

```text
.build/safari-fixture-discovery --token <uuid> --pid <Safari PID> --field plain --type-seed --activate-own-fixture
.build/safari-fixture-discovery --token <uuid> --pid <Safari PID> --field plain --probe-selected-text --activate-own-fixture
```

Обе операции только подготовлены для отдельного approval. Negative baseline
проверяется отдельным запуском probe на пустой собственной fixture: ожидается
ошибка и0 AX writes/0 events; пока это не runtime evidence. Сборка отдельным
swiftc завершилась exit0, выполнен static mode/API/cap review. Helper, AX writes,
HID и activation этим агентом не запускались. NativeProbe/production policy
по-прежнему не изменены.

## Решение пользователя 16 октября

На отдельный запрос ограниченного ввода/замены в Safari пользователь ответил:
«Продолжать остальные задачи без ввода в Safari». Поэтому native HID/AX-write
режимы Safari не запускать, разрешение повторно не запрашивать без нового
указания. Production adapter остаётся выключен. Выполнено только чтение
обоих пустых собственных полей: accelerated-safari-{plain,rich}-background.json.
Первые два frontmost-guard отказа сохранены отдельно, это не native PASS.
Собственная тестовая вкладка закрыта через UI, localhost18764 остановлен;
пользовательские вкладки не изменялись.
