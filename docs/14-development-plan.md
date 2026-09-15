# План разработки и проверки

Статус: план после аудита `8cc19d0`, 2026-09-10. Реализация в рамках аудита не изменялась. Фактические результаты текущих проверок находятся в [протоколе](17-validation-record.md).

Текущий следующий срез (2026-09-16): [качество автокоррекции RU/EN](18-linux-completion-plan.md#следующий-этап-качество-автокоррекции-ruen) — словари, корпус, оценка уверенности и пользовательские исключения. Статус: запланирован.

## 1. Что изменить в процессе

Разрабатывать вертикальными срезами с наблюдаемым результатом. Наличие crate, кнопки GUI, `.deb` или успешной компиляции не закрывает функцию. Каждый срез проходит цепочку:

```text
сценарий пользователя → контракт → воспроизводящий тест/trace
→ минимальная реализация → негативные сценарии → live-проверка
→ обновление матрицы поддержки и документации
```

Исходные пошаговые планы содержали ошибки в самих алгоритмах. Они сохранены в `docs/archive/initial-plan/` как история; брать оттуда готовый код для реализации нельзя без сверки с новой архитектурой. Канонические документы: [архитектура](13-target-architecture.md), [поведение функций](16-product-spec.md), этот план и протокол проверок.

### Единица готовности

В каждой задаче указывать: symptom/input trace, ожидаемое поведение, backend/OS scope, инварианты, изменения кода, способ проверки и оставшиеся ограничения. Для исправления дефекта нужен минимальный тест, падающий на старом коде, либо воспроизводимый native-сценарий, если unit test не способен доказать результат.

Не менять дважды `+8` на `-8` по визуальному результату. Сначала записать пространство кодов на каждой границе и получить ожидаемые/фактические значения. Не включать следующий этап pipeline, пока текущий не сохраняет свой контракт.

## 2. Фазы и зависимости

### G0. Зафиксировать исходную точку — документационный этап

Результат: audits 11/12, reference 15, решения ADR-001…009, план и honest status. Исправления Linux ещё не сделаны. Проверки на macOS не доказывают работу evdev/uinput на Linux.

Для начала G1 не требуется заново проектировать весь продукт. Открытые платформенные вопросы оформляются короткими исследовательскими задачами с выходом `supported / limited / unsupported` и доказательствами.

### G1. Проверяемое ядро и воспроизведение багов

**Зависимость:** G0. **Выход:** детерминированные тесты и скелет платформенных границ.

1. Зафиксировать toolchain/MSRV по реально используемым зависимостям и зафиксированному `Cargo.lock`; не объявлять текущий local Rust минимально поддерживаемым без проверки.
2. Отделить Linux/system/GUI зависимости от platform-independent ядра через target-specific dependencies/features. Сборка common crates на Linux, Windows и macOS обязательна с начала работ.
3. Ввести typed native keycodes, `Repeat`, device identity, origin, context epoch и clock abstraction. Транспорт physical и text observations — разные типы.
4. Добавить fake capture, fake output, fake clock и простой тестовый редактор. Редактор должен моделировать текст, каретку, focus change, modifiers и частичную ошибку вставки; точное содержимое документа — основной oracle.
5. Перенести подтверждённые traces из аудита в regression fixtures. Старые дефекты должны воспроизводиться без `/dev/input`.
6. Удалить/изолировать альтернативную неиспользуемую реализацию `evdev_source.rs` в рамках отдельного runtime-изменения, чтобы существовал один canonical backend.

**Gate:** unit/property tests реально выполняются; не «0 tests». Отдельно проверены кодовые пространства, key-up balance, repeat, временные окна и отказы/limited profiles по матрице guards в архитектуре, раздел 3.4. На этом этапе не включать grab для автоматического старта.

### G2A. Linux transport и lifecycle без текстовых функций

**Зависимость:** G1. **Выход:** проверенный identity relay на отдельном стенде.

1. Сначала nongrabbing diagnostics: устройства, native коды/действия в тестовом режиме, timestamps, capabilities, доступ к output. Никаких слов пользователя в логах.
2. Исправить grab/ungrab, offset, repeat, error handling, shutdown; использовать RAII для fd и один cancellation путь. Не считать Drop единственной аварийной стратегией.
3. Сделать relay с полными frames, проверкой capabilities, resync, горячим подключением и neutral-state startup.
4. Проверить identity mode и отключение фильтра до введения debounce. Сформулировать условия seamless-перехода: удержанные клавиши требуют reconciliation, а не простого сброса коллекций.
5. Выделить минимальный helper с независимым watchdog и bounded queues; privileges/session ownership проверить в стендовой установке.
6. Лишь после transport gate добавить автомат anti-chatter из [спецификации](16-product-spec.md).

**Gate:** выбранная клавиатура сохраняет ввод в identity mode; repeat, shortcuts, media keys, disconnect, two keyboards, SIGTERM, output failure и зависший consumer проходят матрицу. Есть независимый путь остановки. При любой невосстановимой ошибке grab отпускается; потери уже случившегося ввода отдельно фиксируются.

### G2B. Wayland feasibility — параллельно G2A

**Зависимость:** контракты G1; полный relay не требуется. **Выход:** capability report по конкретным сессиям.

Это ранняя задача, поскольку текущий целевой Linux desktop в прежнем плане указан как Wayland. Нельзя сначала построить весь UI, а затем выяснять, возможно ли надёжное определение раскладки.

Для GNOME Wayland и KDE Wayland отдельно проверить:

- Способ наблюдения и единый источник событий, включая работу с hardware filter.
- Получение актуальной keymap/group после переключения через UI, hotkey и per-window layout.
- Доступность focus/lock/context; поведение при неизвестном контексте.
- Доставку RU/EN/Unicode в native GTK, Qt и браузерное поле; XWayland проверяется отдельно.
- Portal permissions: разрешить, отказать, отозвать, reconnect после logout/suspend.
- Совместимость с IME/composition и возможность надёжно выключить правила при неизвестном состоянии.

**Gate:** таблица возможностей со способом проверки, версиями и evidence. Если автоматическая коррекция не получается надёжно, результатом является ограниченный профиль с ручной вставкой/копированием, а не очередной implicit fallback в `us,ru`. При необходимости compositor extension — отдельный deliverable с политикой совместимости по версиям.

### G3. Текстовая вертикаль на одном проверяемом backend-е

**Зависимость:** G1 и работоспособный платформенный observation/injection прототип. Начальный baseline — X11, Wayland продолжается по G2B.

1. Observation → text history → один статический сниппет → replacement executor → контролируемое текстовое поле. Обычный ввод сразу виден.
2. Ввести context invalidation, origin ledger, deadlines, bounded queue и modifier policy. Не добавлять shell до прохождения негативных сценариев.
3. Реализовать Unicode insertion strategy и unsupported-result без предварительного удаления. Первая acceptance: RU/EN, регистр, пунктуация и многострочность. Если выбрана clipboard strategy, сохранение поддерживаемых форматов, проверка ownership/sequence и restore-or-refuse входят в этот же gate, а не откладываются до следующей фазы.
4. Добавить ручную RU↔EN коррекцию текущего/последнего слова. Проверить двойной Shift как gesture, включая обычный набор заглавных букв.
5. Автоматическая коррекция — после ручной, с новыми проверенными словарями и conservative policy. Две валидные альтернативы, неизвестные слова, code-like tokens не исправлять автоматически.
6. Проверить конфликт сниппета и корректора: один план, одна замена, отсутствие повторного matching своего output.

**Gate:** результат читается из поля тестового приложения; отдельно перечислены native проверки в реальных редакторах. Все сценарии потери фокуса и частичной вставки возвращают корректный статус и не инициируют повторное удаление.

### G4. Wayland-профиль и общие продуктовые функции

**Зависимость:** G2B + G3.

Подключить только подтверждённые возможности Wayland к общему engine. Завершить config generations, applied-status, pause, CLI doctor, настройки профилей и startup lifecycle. Встроенные date/time — без внешней команды. Shell worker и undo включать отдельными задачами после собственных tests; расширение clipboard-профилей также требует тестов, базовые guards обязательны с первого использования paste.

**Gate:** одна заявленная Wayland-конфигурация проходит end-to-end; неподдерживаемые варианты корректно отображаются как limited/unsupported. В README указаны точные версии проверенных профилей. Нет заявления о проверке «Linux вообще».

### G5. Windows и macOS адаптеры

**Зависимость:** стабилизированный semantic contract G3; разработки можно вести независимо друг от друга и от Wayland UI.

Каждый адаптер проходит одинаковую вертикаль: permissions → observation → context/layout → static snippet → Unicode insertion → cancellation → lifecycle. Общий engine не получает платформенных `if windows` внутри corrector.

Windows gate: normal/elevated application boundary, hook responsiveness, foreground HKL, IME, UTF-16, shutdown, synthetic tagging. macOS gate: permissions/revoke, tap lifecycle, input source change, Secure Input, Unicode, lock/sleep/wake. Отдельно подтвердить подписанную packaged-сборку: dev-binary и установленный продукт могут иметь разное поведение разрешений.

**Gate:** текстовые функции приняты на обеих ОС. Per-device hardware anti-chatter за пределами Linux не включён в MVP. Для него нужна отдельная оценка hook/driver/HID решений; один Raw Input listener не доказывает возможность подавления события для других приложений.

### G6. Оболочка, установка и выпуск

**Зависимость:** хотя бы один принятый native backend и стабильный control API; выпуск с пометкой ограниченной платформы допустим раньше полного G5.

- Выбрать GUI по короткому prototype на целевых ОС: tray, автозапуск, permissions, accessibility, размер поставки и поддержка зависимостей. Linux GTK оставить рабочей оболочкой до решения.
- Linux: headless runtime/helper отделить от GUI-зависимостей; собрать `.deb`, проверить содержимое, maintainer scripts, conffiles, права и user-session lifecycle.
- Windows: user-session startup и installer; macOS: app bundle, signing/notarization и login-item путь. До реализации не обещать конкретный installer API/поддерживаемую минимальную ОС.
- Install/upgrade/restart/uninstall не должны включать незапрошенный эксклюзивный grab, менять права шире выбранного режима или удалять пользовательские сниппеты/конфиг.
- Release notes перечисляют проверенную матрицу, известные ограничения и способ отключения.

**Gate:** установка на чистую систему без developer packages; upgrade сохраняет конфиг; удаление завершает процессы и освобождает устройства; runtime готовность подтверждена control API и реальным сценарием.

## 3. Матрица приёмки

Каждая строка становится самостоятельным case с ID, окружением и сохранённым результатом. «Неприменимо» допустимо только с причиной capability. `Not run` нельзя превращать в `Pass`.

| ID | Ввод / ситуация | Ожидаемый результат | Уровень |
|---|---|---|---|
| IN-01 | evdev A=30, Shift=42, Esc=1 | Identity output: те же коды; XKB-преобразование отдельно | Unit + Linux |
| IN-02 | Down → несколько Repeat → Up | Repeat не становится Up; нет двойного autorepeat | Unit + Linux |
| IN-03 | Burst из нескольких frames | Порядок/время/границы не теряются | Replay + Linux |
| IN-04 | SYN_DROPPED, удержан Ctrl | Resync состояния, text history invalidated | Linux integration |
| IN-05 | Shift на двух клавиатурах, release одной | Удержание второй сохранено | Replay + Linux |
| IN-06 | Hotplug/reconnect, меняется eventN | Новая идентичность сопоставлена, self-device исключён | Linux live |
| IN-07 | Media key с кодом >255 | Поддержан либо устройство заранее rejected; не silent drop | Linux live |
| IN-08 | Grab отказал / uinput недоступен | Понятная причина, исходный ввод продолжает работать | Fault injection |
| IN-09 | Output умер / очередь заполнена / worker завис | Сработала заявленная аварийная политика, grab освобождён при отказе output | Fault injection + live |
| IN-10 | SIGTERM, Ctrl+C, tray exit, IPC Shutdown | Один shutdown, без SIGKILL и оставленного grab | Lifecycle |
| IN-11 | Start/stop при удержанных Shift/Ctrl | Известный resync/neutral-state переход, нет stuck keys | Linux live |
| AC-01 | Down0, Up3, Down6, Up9 ms | Один согласованный press/release по выбранному алгоритму | Fake clock |
| AC-02 | Down0, Up500, Down505, Up510 | Подавление release-bounce; long hold не ломает debounce | Fake clock |
| AC-03 | Два намеренных быстрых нажатия | Результат соответствует настройке; false suppression измеряется | Replay + live |
| AC-04 | Repeat при удержании | Не считается chatter | Unit + live |
| AC-05 | Одинаковый key на двух устройствах | Состояния фильтров независимы | Unit |
| AC-06 | Physical Up перед desktop repeat deadline; затем Ctrl/Shift Down | Измерены дополнительные повторы/overlap; работает flush policy либо профиль отклонён | Native |
| AC-07 | Up@100, deadline120, Down@110; helper проснулся@130 | Queued Down отменяет pending Up до исполнения таймера | Fake clock + replay |
| AC-08 | Reload/disable в Down и PendingRelease | Удержание и deadline обработаны по отдельным lifecycle правилам | Fake clock + Linux |
| TX-01 | Набор без delimiter | Текст появляется немедленно | Controlled app |
| TX-02 | `ghbdtn ` / `руддщ ` | `привет ` / `hello `, предыдущий текст сохранён | Engine + native |
| TX-03 | `Ghbdtn ` / `GHBDTN ` | Регистр по спецификации; переключение OS layout отдельно | Engine + native |
| TX-04 | `:date ` | Полный trigger заменён ровно один раз; boundary сохранён | Engine + native |
| TX-05 | `A:Привет!\n🙂` в replacement | Полная вставка либо отказ до удаления; без усечения | Native |
| TX-06 | Backspace, Delete, arrows, mouse click | История скорректирована/сброшена; чужой текст не удаляется | Engine + native |
| TX-07 | Focus change во время render/до edit | План отменён, вставки в другое окно нет | Fault injection |
| TX-08 | Focus change/ошибка после первого edit | `IndeterminateAfterEdit`, без автоматического retry | Fault injection |
| TX-09 | Shift/Ctrl/AltGr/Meta удержан | Не возникают shortcut/ошибочный регистр; policy выполнена | Native |
| TX-10 | Input source меняется извне | Generation обновлена, старый план отменён | Native |
| TX-11 | IME, dead key, combining marks | Поддержанный committed flow либо safe refusal | Native |
| TX-12 | Sensitive/Unknown context, lock screen | Автозамена/история выключены согласно capability policy | Native |
| TX-13 | Собственная вставка похожа на trigger | Нет рекурсии; физический ввод не потерян | Engine + native |
| TX-14 | Сниппет и корректор совпали | Один заранее определённый победитель | Unit |
| TX-15 | Double Shift / Shift+A+Shift / Shift удержан | Gesture срабатывает только по спецификации | Fake clock + native |
| TX-16 | Shell timeout/exit error/слишком большой stdout | Trigger остаётся, ввод работает, ошибка видима | Worker integration |
| TX-17 | Пользователь скопировал текст во время paste | Новый clipboard не перезаписан restoration-ом | Native |
| TX-18 | Undo сразу / после движения каретки | Условный rollback работает только в допустимом контексте | Engine + native |
| TX-19 | Enter отправляет форму; Tab переводит фокус | После action-key нет запоздалой замены/Backspace; история сброшена | Native |
| TX-20 | Anti-chatter включён, пользователь набрал trigger | Relay считается пользовательским вводом ровно один раз, insertion не запускает matcher | Linux integration + native |
| TX-21 | Пользователь печатает одновременно с replacement в observer-only режиме | До edit отмена; после edit неопределённый результат без новых слепых команд | Fault injection + native |
| CF-01 | Reload valid config | Новый matcher/threshold и applied generation реально действуют | Integration |
| CF-02 | Reload invalid config | Старая рабочая generation сохранена, UI показывает ошибку | Integration |
| CF-03 | `--config` + start/reload/UI save | Один согласованный config path, нет отката к default | Integration |
| CF-04 | Pause/resume с накопленной историей | Старое слово не исправляется в новом месте | Integration |
| LC-01 | Два запуска одновременно / stale PID | Один экземпляр, чужой процесс не сигнализируется | Process integration |
| LC-02 | Permissions revoke / suspend / logout | Degraded/Stopped, pending plans отменены | Native |
| PK-01 | Clean install/upgrade/uninstall | Соответствие assets, defaults, permissions и cleanup | Package VM |

## 4. Уровни тестирования и CI

### Common suite

Unit и property tests работают без GUI и устройств на Linux/macOS/Windows. Основные инварианты: сохранение keyspace, согласованность press/release, независимость устройств, отсутствие дублирования text observations, один executor, invalidation устаревших планов и нет удаления при невозможной вставке.

Текущее безопасное подмножество для проверки сборки:

```bash
cargo test --locked -p typetune-core -p typetune-chatter -p typetune-config -p typetune-corrector -p typetune-snippets
```

В baseline оно выполняет **ноль тестов**. В G1 команда должна выполнять настоящий regression suite. Новые package/feature имена фиксируются только после появления в Cargo metadata; документация не должна выдавать проектные названия за уже существующие команды.

### Linux integration

VM с тестовыми input-устройствами и доступом к uinput, без grab основной клавиатуры хоста. Fake input generator пишет детерминированные frames в тестовое устройство, независимый observer читает output и сравнивает последовательности. Контейнер годится для сборки/части ABI-проверок; он не заменяет desktop compositor и реальный seat.

Перед live grab: отдельная тестовая клавиатура, ограниченный allowlist, готовый output, проверенная остановка из независимой сессии, watchdog и способ восстановить ввод. Это критерии тестового стенда, а не просьба пользователю подтверждать каждый запуск. Fail-open измерять в условиях ошибки, а не выводить из наличия `Drop`.

### Desktop end-to-end

Контролируемое native-приложение с извлекаемым текстом/кареткой плюс реальные GTK/Qt/browser/editor поля. Проверять backend-вставку настоящими OS events: browser automation, напрямую меняющая DOM, не проверяет keyboard daemon.

Запись результата содержит ОС/архитектуру, desktop/compositor и версии, session type, layout/IME, target app/version, клавиатуру/transport, способ установки, commit, capabilities, IDs выполненных cases и evidence. Synthetic fixtures допустимы в репозитории; введённый пользователем текст и clipboard — нет.

### Изменение CI в будущем

Текущий CI проверяет check/clippy/fmt на Ubuntu и не запускает tests. В G1 добавить common matrix на трёх ОС; Linux backend build отдельно с полным набором нужных system deps; GUI job отдельно. Затем privileged Linux integration на изолированном runner и native acceptance для desktop cases. Сначала диагностировать текущие CI failures, затем добавлять новые gates — не ослаблять check для зелёного статуса.

На стадии этого аудита workflow **не менялся**. Минимальные зависимости и supported versions получать из manifest, bindings feature gates и clean-build результатов. Не копировать версии библиотек из старых примеров.

### Измеряемые бюджеты

Начальные инженерные цели, ещё не измеренные: быстрый callback без blocking I/O; relay processing p99 ≤2 ms без intentional debounce, остановка ≤1 s в нормальном состоянии, bounded replacement и worker deadlines. Достижимость подтвердить на стенде с указанной нагрузкой. Anti-chatter release delay измеряется отдельно. При превышении бюджета изменить реализацию/заявленный профиль и записать решение.

## 5. Работа параллельными задачами

Безопасно параллелить Linux transport, Wayland capability probe, словари/чистые правила и Windows/macOS adapters после согласования типов. Владелец common contracts — один интегратор; изменения event types сначала согласуются в коротком ADR и fixture примере. UI и packaging зависят от принятого control/lifecycle API.

Не объединять в одну правку offset, buffer semantics, shell renderer, GUI и deb packaging: отдельные проверяемые изменения позволяют установить причину регрессии. При этом изменения самого контракта должны включать всех затронутых потребителей в одной согласованной миграции.

## 6. Checkpoint для продолжения

Начать следующую реализационную задачу с G1: baseline fixtures и разделение событий. Параллельно подготовить G2B capability report целевого Linux desktop. Точный доступный Linux-стенд, desktop version и клавиатуры ещё предстоит установить по живой системе; историческая запись Ubuntu/YICHIP в старом плане не является подтверждением текущего окружения.

Первый milestone: **воспроизводимые дефекты + надёжный identity relay + измеренные Wayland-возможности**. Второй: **статический Unicode-сниппет и ручная коррекция с context guards**. После этих результатов расширять автоматическую коррекцию и GUI.
