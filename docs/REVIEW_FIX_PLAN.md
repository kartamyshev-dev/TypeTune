# План исправлений TypeTune по итогам ревью (для агента-исполнителя)

## Контекст

Ревью коммита `321bfdd` нашло ошибки в ядре исправления, расхождения README с
реальностью, лишнюю AX-нагрузку и архитектурный долг. Ошибки ядра:
- пунктуация, набранная в неверной раскладке, ломает исправление последнего слова;
- ложные срабатывания правила двойных заглавных;
- неполная пауза;
- словарь примерно на 350 слов.

Пользователь выбрал:
- полный объём, включая рефакторинг;
- полную паузу;
- расширение собственного словаря;
- работу **без Mac**: агент ставит Swift 6 для Linux и проверяет только ядро и CLI.

Итог: исправленное и покрытое fixtures ядро, честный README, разгруженный
KeyboardService и чек-лист, который пользователь выполнит на Mac.

## Правила для агента (обязательны, из AGENTS.md)

- Общение, UI-строки и документы — по-русски. Начать с docs/STATUS.md, PLAN.md и FEATURES.md.
- Виды проверки разделены. «Linux offline» — это не macOS PASS и не native PASS. Код GUI-таргета
  `LayoutPilot` агент **скомпилировать не может**. Каждое изменение GUI помечать в STATUS как
  «не скомпилировано, NOT_RUN на Mac».
- Каждое новое расхождение оформляется fixture. Holdout (v2 и будущий v3) не использовать для
  подстройки. Если holdout упал, правило не подгонять, а записать падение как наблюдение.
- Не добавлять бинарники, декомпиляцию и данные оригинала (Caramba). Источники словаря должны
  иметь подтверждённую лицензию.
- Ничего не устанавливать в /Applications, не запускать NativeProbe, не трогать TCC и не делать push.
  Каждый этап оформляется отдельным локальным коммитом с атрибуцией из system-reminder.
- Чекбоксы в PLAN.md отмечать только со ссылкой на evidence в `research/evidence/<этап>-2026-10-XX/`.
  Evidence: команды, exit code, хеши исходников, вывод.
- `.log` игнорируется Git. Логи сохранять как `.txt`.

## Этап 0. Окружение и базовая линия

1. Поставить официальный toolchain Swift 6.x для Linux с swift.org (swiftly или tarball) вне
   репозитория. Зафиксировать версию.
2. `Package.swift`: объявлять продукт и таргет `LayoutPilot` (AppKit) только под `#if os(macOS)`,
   чтобы на Linux работали `swift build` и `swift test` для Core, CLI и Tests. Не менять имена
   таргетов: на них опираются `scripts/verify_existing_build.py` и `scripts/test_audit_gates.py`.
   Прогнать `python3 scripts/test_audit_gates.py`.
3. Базовая линия на HEAD, до любых изменений:
   `swift build --product layoutpilot-cli`, `.build/debug/layoutpilot-cli selftest`,
   `python3 scripts/evaluate_corpus.py`, `swift test`.
   Если на Linux что-то падает из-за различий corelibs-foundation, записать это как Linux-специфику.
   Поведение под Linux в ущерб macOS не менять.
4. Добавить `scripts/engine_regressions.py` или новые разделы `SelfTest.swift`. Это регрессии из
   ревью, которые до исправления **падают**: `ghbdtn/`, `ghbdtn?`, `руддщю`, `руддщб`, `IDs`, `PCs`,
   `GHz`, `OKs`. Падение до исправления зафиксировать как evidence.

## Этап 1. Пунктуация в неверной раскладке

Файлы: `Sources/LayoutPilotCore/Layout.swift`, `Engine.swift` (`completedTokenDecision`, строка 146),
`Sources/LayoutPilot/KeyboardService.swift` (`completedTokenDecision`, около строки 838; `undo`, около
строки 958; terminal `applied`, строка 26), `Sources/LayoutPilotCLI/SelfTest.swift`.

**1a. Таблица раскладки как данные.** Заменить пару массивов, связанных через `zip`, на
`public struct Layout.Mapping`. Это список пар «физическая клавиша US ↔ RU (PC)» с двумя словарями и
проверкой уникальности в обе стороны. Добавить верхний цифровой ряд PC-раскладки:
`@↔"`, `#↔№`, `$↔;`, `^↔:`, `&↔?`, `|↔/`.
API: `Layout.convert(_:to:mapping: = .standardPC)`; у `Engine` свойство `mapping` со значением по
умолчанию `.standardPC`. Сигнатуры, которыми пользуются Replay, PartialLayoutDetector и
SystemVocabulary, не менять, только добавить параметр со значением по умолчанию.
Selftest:
- круговое преобразование для каждой пары;
- на `Ёж` по-прежнему получается `~;`;
- `ntcn&` превращается в `тест?`.

**1b. Физический суффикс.** В `Engine.completedTokenDecision` новый шаг идёт **после** целого токена
и **до** буквального отрезания `.,!?;:`:
- `converted = Layout.convert(token, mapping)`;
- `n` — число завершающих символов `converted` из набора `. , ? !`. Символы `;` и `:` исключены
  намеренно: в RU→EN они приходят из букв «ж» и «Ж», с которых часто заканчиваются русские слова;
- условия: `0 < n < token.count`, весь токен не известен (`isKnownWord(token)` равно false),
  `decide(prefix)` даёт `.layout`;
- результат: `Decision(original: token, replacement: d.replacement + suffix(converted), reason: .layout, learnAs: prefix)`.

Новый параметр `isKnownWord: (String) -> Bool`, по умолчанию `lexicon.contains`. В режиме системного
словаря KeyboardService передаёт проверку через `SystemVocabulary`: добавить internal-метод
`accepts(_:)` поверх приватного `spelling`.

**1c. Обучение после отмены.** В `Decision` добавить опциональное поле `learnAs: String?`. Синтез
Codable уже работает через decodeIfPresent. Во всех местах, где вызывается `store.learn(...)` после
отмены, использовать `decision.learnAs ?? decision.original`; это `undo` и terminal `applied`.
Обёртка `KeyboardService.completedTokenDecision` должна передавать `learnAs` дальше.

Ожидаемые результаты:

| Вход | Результат |
| --- | --- |
| `ghbdtn/` | `привет.` |
| `ghbdtn?` | `привет,` |
| `ghbdtn&` | `привет?` |
| `руддщю` | `hello.` |
| `руддщб` | `hello,` |
| `руддщ,` | `hello?` (осознанное изменение физической семантики; записать в DECISIONS.md) |
| `ghbdtn.` | `привет.` (без изменений) |
| `ghbdtn,` | `привет,` (без изменений) |

Негативные случаи: известные слова на «ю» и «б» (`делаю`, `клуб`), а также `муж` и `этаж` не меняются.
Исключение или выученное слово `ghbdtn` блокирует и `ghbdtn/`.
Fixtures: новый `corpus/punctuation-regressions.jsonl` с `events` text/boundary в формате
`context-regressions.jsonl`. Запуск: `layoutpilot-cli evaluate`.

## Этап 2. Двойные заглавные

Файл: `Engine.swift:123`. Для токенов ровно из 3 букв правило применяется, только если результат
или его конвертация есть в словаре. Для 4 и более букв поведение прежнее, исключения сохраняются.
Проверить, что категория `doublecaps` корпуса v2 проходит: она строится из словарных слов.
Дубль предиката в `KeyboardService.statisticsCategory` (около строки 829) заменить на
`public static func Engine.isDoubleCapitalTypo(_:)`.
Selftest: `IDs`, `PCs`, `TVs`, `VMs`, `OKs`, `GHz` не меняются; `THe` даёт `The`, `ПРивет` даёт `Привет`.

## Этап 3. Полная пауза

Чтобы не путать паузу с переключателем «Автоматически исправлять раскладку», ввести
`Settings.paused: Bool` со значением false и `decodeIfPresent`.
- `paused == true` или `appAutomatic[app] == false`: никаких автоматических изменений. Ни раскладки,
  ни опечаток, ни «ё», ни двойных заглавных, ни пользовательских правил. Ручные действия
  (Double Shift, ⌘⌥Space, ⌘⌥Z) продолжают работать.
- `automatic == false` остаётся «только раскладка выкл.»: действующий инвариант SelfTest
  «automatic off allows case only» сохраняется.

Центральный шлюз: `Engine.decide`, `Engine.decidePartial`, `SystemVocabulary.decision`.
GUI:
- пункт меню и жест «оба Shift» (`KeyboardService.execute .toggleAutomatic`) переключают `paused`;
- индикатор Ⅱ в `main.swift:314` зависит от `paused`;
- подписи в SettingsView и Picker для приложений: «Автоисправления: вкл/выкл».

Миграция: сохранённые `automatic=false` не трогать. Описать это в DECISIONS.md.
Selftest: полная матрица `paused` × `automatic` × `appAutomatic` × `typos` × `yo` × правило.

## Этап 4. Нагрузка на события, мёртвый код, предел буфера

Файл: `KeyboardService.swift`.
- Строка 393: для `.scrollWheel` и `*MouseDragged` **вне** mutation gate возвращать false без
  `resetTransient()` и `captureAfterEvent()`. Reset и захват делать только на mouseDown и mouseUp.
  Из маски события не убирать: барьер во время мутации должен задерживать прокрутку и
  перетаскивание (docs/NATIVE.md, раздел «Барьер входящих событий»).
- Удалить недостижимую строку 406.
- Строка 340: вместо однократного `== 512` ввести жёсткий предел. При `count >= 512`: `revision += 1`
  (как сейчас), диагностика `fault("replay-buffer-limit")`, при активном replay — `suspendReplay`.
  Нажатия не выбрасывать.

Всё это GUI-код, NOT_RUN. Логику предела вынести в Core (этап 7) и покрыть selftest.

## Этап 5. Раскладка из реальных источников ввода

Core: `Layout.Mapping.init?(pairs:)` с валидацией: 33 строчные и 33 прописные кириллические буквы,
26 латинских, уникальность. При неудаче возвращается nil.
GUI (`InputSources.swift`): `static func mapping(english:russian:) -> Layout.Mapping?`. Он строит пары
через существующий `insertionText(keyCode:flags:sourceID:layoutData:keyboardType:)` для keyCode
0..<51 без Shift и с Shift. Кэш хранить по паре ID и сбрасывать по уведомлению смены источника,
которое уже подписано в `main.swift`. При nil использовать `.standardPC`.
KeyboardService создаёт `Engine(settings:mapping:)` с этим mapping.
Selftest на Linux: валидатор принимает `.standardPC` и отклоняет испорченные таблицы.
Проверка на Apple «Русская» — пункт чек-листа для Mac.

## Этап 6. Расширение собственного словаря

1. Источник: открытые списки частотных слов EN и RU с лицензией, совместимой с распространением
   (проверить и записать в `docs/LEXICON.md`: URL, версия, лицензия, SHA-256). Сырьё хранить в
   `research/private/` (не в Git). Если однозначно подходящей лицензии нет, **остановиться и
   спросить пользователя**. Данные Caramba и словари оригинала запрещены.
2. Скрипт `scripts/build_lexicon.py`, детерминированный: топ-N (ориентир 20–30 тыс. на язык),
   только буквы, длина ≥ 3. Общий фильтр неоднозначности: удалить слово, если его конвертация в
   другую раскладку тоже есть в словаре. Ручные списки `typos` и `yo` сохранить. Индивидуальных
   правок под отдельные fixtures не делать.
3. Независимая проверка качества `scripts/evaluate_natural_text.py`:
   - тексты в общественном достоянии (EN — Project Gutenberg, RU — классика с Викитеки) хранятся в
     `research/private`;
   - метрики: ложные исправления на правильно набранном тексте (цель — 0 на 10⁵ слов, иначе
     разобрать) и полнота на тексте, переведённом в неверную раскладку, до и после расширения;
   - в Git коммитятся только скрипт и отчёт.
4. Корпус:
   - v2 остаётся регрессией. Каждое падение v2 из-за нового словаря разобрать и объяснить в
     docs/CORPUS.md;
   - создать v3: `generate_corpus.py --version 3`, новые id и manifest-v3, holdout зафиксировать до
     прогона;
   - проверить память и время построения `PartialLayoutDetector.bundled`;
   - проверить размер `lexicon.json` в bundle.

## Этап 7. Рефакторинг KeyboardService (только с сохранением поведения)

Цель: вынести машину состояний барьера, replay и восстановления в Core как чистый generic-тип и
покрыть его на Linux.
- `Sources/LayoutPilotCore/MutationSession.swift`: `MutationSession<Target, Event>` по образцу
  `InputReplayQueue<Event>` и `InputRecovery`.
  - Владеет полями: `mutationGate`, `replaying`, `inputReplay`, `recoveryTarget`,
    `recoverySourceID`, `sourceAfterReplay` (как generic payload), `replayRouteLease`, предел буфера.
  - Методы возвращают перечисление эффектов (`.postNext(token)`, `.suspend`, `.resume`,
    `.captureContext`, `.applySource` и т.д.). AX, CGEvent и TIS остаются в KeyboardService.
  - Источник истины по переходам — нынешние `finishMutation`, `replayDelayedInput`, `drainReplay`,
    `deliveryTimedOut`, `suspendReplay`, `recoverInput`, `confirmTextReviewed`, `discardPendingInput`.
- Новый `Sources/LayoutPilotCLI/MutationSessionChecks.swift`: переходы, таймауты, предел буфера,
  повторные и поздние подтверждения. Проверки из `RecoveryChecks` и `ReplayRoutingChecks` должны
  остаться зелёными.
- KeyboardService переходит на `MutationSession` маленькими коммитами, по одному переходу за коммит.
  Ничего, кроме вызовов, не менять; тестовые хуки `#if LAYOUTPILOT_TESTING` сохранить.
  Поскольку GUI не компилируется, каждый коммит перечитывать на соответствие типов и в STATUS
  пометить «требует swift build на Mac».
- `isCurrent` с `DispatchQueue.main.sync` не трогать, только задокументировать.

## Этап 8. CI

`.github/workflows/ci.yml`:
- job `linux-core` (контейнер `swift:6.x`): сборка CLI, selftest, `evaluate_corpus.py` (v2 и v3),
  `punctuation-regressions`, `swift test`;
- job `macos` (`macos-14`): `swift build` всех продуктов, selftest, `swift test` (полный Xcode
  содержит XCTest).

Linux-job проверить локально теми же командами. macOS-job до push пользователя остаётся
непроверенным. Push не делать.

## Этап 9. README и документация

- README:
  - список поддерживаемых приложений (TextEdit, Chrome, Codex; Terminal и Ghostty через zsh);
  - первый запуск неподписанного релиза: «Конфиденциальность и безопасность» → «Всё равно открыть»;
  - объём словаря и опция системного словаря;
  - семантика паузы;
  - «Одиночный Shift» включён по умолчанию.
- Три битые ссылки на `.log` в `docs/SETTINGS_NATIVE_PREPARATION.md` и `docs/STATS_RESEARCH.md`:
  файлов нет и локально, поэтому заменить пометкой «лог не сохранён».
- STATUS.md переписать в состояние на один экран: версия, что проверено каким видом проверки,
  открытые условия, точка продолжения, чек-лист для Mac. Весь журнал **дословно** перенести в
  `docs/JOURNAL.md`. Дубли разделов STATUS в PLAN.md и FEATURES.md заменить ссылками на журнал.
  Содержание не терять: проверить через `diff` объединения строк до и после.
- Обновить FEATURES и PLAN: новые пункты с evidence; старые PASS не переносить.

## Проверка

- После каждого этапа на Linux: `swift build --product layoutpilot-cli`,
  `.build/debug/layoutpilot-cli selftest`, `python3 scripts/evaluate_corpus.py`,
  `layoutpilot-cli evaluate corpus/punctuation-regressions.jsonl`, `swift test`,
  `python3 scripts/test_audit_gates.py`. Регрессии этапа 0 должны стать зелёными.
- Этап 6 дополнительно: отчёт `evaluate_natural_text.py` до и после, ложные исправления ≈ 0.
- Итоговый чек-лист для пользователя в STATUS.md (Mac, NOT_RUN):
  - `scripts/build.sh`;
  - selftest release CLI;
  - NativeProbe TextEdit: `ghbdtn/`, `руддщю`, `IDs`, пауза с опечаткой, прокрутка во время
    набора, отмена ⌘⌥Z с обучением `ghbdtn` (не `ghbdtn/`);
  - mapping для ABC + RussianWin и для Apple «Русская»;
  - push и зелёный CI.
