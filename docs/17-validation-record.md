# Протокол проверок и точка продолжения

## Текущий срез — 2026-09-16

- Рабочая платформа preview: Ubuntu 26.04.1, kernel 7.0.0-31-generic,
  GNOME/Mutter 50.1 / Wayland; GTK 4.22.4, IBus 1.5.34-rc2, Rust 1.98.1.
- [39 — повторный Double Shift](39-repeat-double-shift.md): слово и источник
  переключаются обратно без нового набора, в том числе после auto с пробелом.
- [38 — задержка evdev](38-compat-input-latency.md): scanner вынесен из reader;
  пользователь подтвердил работу в браузере. Наблюдаемая задержка снизилась
  с 480 до 2 мс, stale events отсутствовали в повторной проверке.
- [37 — compatibility backend](37-universal-input-investigation.md): явный opt-in,
  evdev/uinput без grab; Unknown text/selection/sensitivity/composition сохраняются.
- [36 — IBus auto/Shift](36-auto-shift-checkpoint.md): отдельные Chrome/editor cases.

Перед публикацией накопленного checkout повторно выполнены:
`cargo test --workspace --all-targets --locked --offline` — **115 PASS**;
Python unittest discover — **12 compatibility + 23 IBus/gesture/profile PASS**.
Нулевые test targets не включены в число поведенческих проверок.

Последние native acceptance: [Wayland](evidence/39-repeat-wayland.txt),
[XWayland](evidence/39-repeat-xwayland.txt),
[IBus regression](evidence/37-ibus-regression.txt).
Compatibility stand использует контролируемый Feed и Clutter virtual keyboard;
реальный evdev/uinput lifecycle проверен отдельно, а работу с физической клавиатурой
в браузере подтвердил пользователь. Это не приемка всех приложений/полей.

[Как запустить и остановить](35-user-test.md). Общие G2–G4 gates остаются открытыми;
следующие задачи перечислены в [плане доведения Linux](18-linux-completion-plan.md).

## История исследования и предыдущих этапов

Ниже сохранён протокол baseline-а; его даты и утверждения относятся к тому этапу.


Актуальный срез от 2026-09-15: [проверка API GNOME Text Editor](29-real-editor-checkpoint.md).
Ниже сохранены исторические результаты; прежний полный G2A/G2B не считается принятым.

Дата: 2026-09-10. Исходный commit TypeTune: `8cc19d0` (`fix: evdev raw keycodes have +8 offset, must subtract before uinput`). Рабочее дерево перед исследованием было чистым.

## Объём работы

Изучены все 11 crates, конфигурация, словари, CLI/IPC, GUI/tray, packaging, Makefile, CI, первоначальные документы 00–10 и история последних исправлений keycode. Независимо разобраны Linux transport, прикладные функции и Espanso. Затем целевой дизайн прошёл перекрёстную проверку двумя аудиторами.

Результат — документация и правила следующей разработки. Файлы приложения, Cargo manifests/lock, словари, конфигурация, CI, packaging и runtime tests в репозитории не менялись. Никакие сервисы не устанавливались, разрешения устройств не менялись, daemon не запускался.

## Фактически выполненные проверки

| Проверка | Результат | Что этот результат доказывает |
|---|---|---|
| Исходники и call sites | Найден active reader в `typetune-input/src/lib.rs`; `evdev_source.rs` не подключён | Ошибки относятся к реально используемому коду |
| Границы evdev/XKB/uinput, grab/ungrab | Сверены kernel API и локальные исходники зафиксированных зависимостей | Статически подтверждены ошибочный offset и integer/pointer contract ioctl |
| SIGTERM/SIGINT | Сверены daemon wiring и реализация `signal-hook::flag::register` | Shutdown flag не связан с event loop и имеет неверную для него полярность |
| Portable cargo test, пять crates | Успех; 0 unit tests и 0 doctests | Подмножество собирается на текущем macOS; поведение существующим suite не проверяется |
| Дополнительная сборка core/chatter offline | Успех; 0 tests | Повторно подтверждена сборка исследованной библиотеки для отдельного harness |
| Три AntiChatter traces через реальную библиотеку | Подтверждены пропущенный release-bounce, orphan release и смешивание устройств | Реальное поведение pure Rust processor на детерминированных событиях |
| Восемь Rust API assertions corrector/snippets | Все подтвердили описанные в audit выходы | Латентные ошибки при `character=Some`, без Linux-устройств |
| Словари | По 10 000 уникальных строк; `hello`/`привет` отсутствуют; есть некорректные формы | README examples не обеспечены штатными ресурсами |
| Календарная формула | Сопоставлены фиксированные календарные даты и расчёт текущего алгоритма | Ошибочность date renderer независимо от ОС |
| `cargo check --locked --workspace` | Ошибка, exit 101: отсутствует `pkg-config` для native dependencies (`glib/gio/gtk` и др.) | Полная сборка на этом хосте не подтверждена; это не Linux build failure |
| Espanso reference | Изучен pinned commit, 164 файла сверены с Git blob SHA; проверены 42 source line links | Источники отчёта 15 относятся к указанному commit |
| Проверка документации | 31 Markdown-файл: парность code fences, 87 локальных ссылок, отсутствие trailing whitespace; ошибок нет | Локальная навигация и базовая структура документов корректны |
| Сохранность архива | Все 10 исходных документов побайтово совпали с `git show 8cc19d0:docs/...` | Историческое содержание не потеряно |
| Границы изменений | `git diff --check` прошёл; исходники, manifests/lock, config, dictionaries, CI, packaging и resources без diff; новые файлы только `.md` | Изменения ограничены документацией |

Среда: `Darwin arm64`, target `aarch64-apple-darwin`; `rustc 1.89.0 (29483883e 2025-08-04)`, `cargo 1.89.0 (c24e10642 2025-06-23)`. Новые системные зависимости для обхода ограничения сборки не устанавливались.

Команда portable-проверки:

```bash
cargo test --locked -p typetune-core -p typetune-chatter -p typetune-config -p typetune-corrector -p typetune-snippets
```

Изолированные harness-ы запускались во временных каталогах вне workspace; они не добавлены как новый suite. Трассы, входные данные и фактические результаты приведены в [Linux audit, L09](11-linux-audit.md) и [feature audit, раздел 4](12-feature-audit.md). Их следует перенести в постоянные regression fixtures на этапе G1 с ожиданием **исправленного** поведения. Нынешние успешные assertions подтверждают наличие дефектов, а не их исправление.

## Что изменено в документации

- README и overview теперь описывают реальное состояние и маршрут чтения.
- Audits 11/12 содержат 11 и 16 findings соответственно; некоторые системные причины упомянуты в обоих документах, это не 27 независимых багов.
- Architecture 13 фиксирует separation physical/text, типы событий, capabilities, guards, replacement executor, lifecycle/config и 9 ADR.
- Plan 14 задаёт G0–G6, ранний Wayland prototype, матрицу приёмки и требования к native evidence.
- Reference 15 документирует Espanso `a6bfad5985ea2e16d43d906aed0282b63bdb2bd2` и границы применимости его решений.
- Product spec 16 определяет ручную/автоматическую коррекцию, сниппеты, словари, release-debounce hypothesis и настройки.
- Старые планы 01–10 сохранены побайтово в `docs/archive/initial-plan/`; исходные пути заменены ссылками на действующие документы.
- Корневой `AGENTS.md` закрепляет требования к реализации, evidence и сохранению контрактов для последующих задач.

После перекрёстного review уточнены action-delimiters Enter/Tab, физический interleaving в observer mode, роли HardwareRelay/TextInjection, guards для разных Unknown, clipboard gate, debounce timers/repeat и различия reload/disable/disconnect. Это уточнения проектного решения, а не дополнительные выполненные Linux tests.

## Ограничения и открытые решения

Не проводились: native Linux build, запуск TypeTune или Espanso, реальные evdev/uinput/grab, X11/Wayland, macOS/Windows hooks, GUI/D-Bus, installation/upgrade/removal, измерение latency и аппаратного bounce. Такие пункты остаются `Not run`.

Не установлены по живой системе: текущий Linux desktop/версия/клавиатура, доступные Wayland APIs, поддерживаемые минимальные версии ОС, источник будущих словарей и окончательный GUI toolkit. GNOME/KDE и XWayland нельзя считать взаимозаменяемыми стендами. Предложенный release-debounce должен пройти native repeat/shortcut checks и может потребовать пересмотра.

Память OpenViking: поиск в actor scope и scoped Experience root отработал; относящихся к задаче результатов не найдено. Настройки памяти не менялись. Канонический результат находится в репозитории; дополнительных project memories/resources вручную не публиковалось.

## Checkpoint

Документационный этап G0 завершён после проверки документации. **Следующая работа — G1, не исправление production ввода вслепую:** добавить regression fixtures, развести physical/text события и платформенные зависимости; параллельно установить возможности целевого Wayland desktop. Затем G2A identity relay и lifecycle на изолированном Linux-стенде.

Перед продолжением прочитать [overview](00-overview.md), [архитектуру](13-target-architecture.md), [план](14-development-plan.md) и [спецификацию](16-product-spec.md). Не использовать архивный псевдокод как готовую реализацию. Для каждого нового завершённого среза создать отдельный протокол с commit и native scope, не переписывая результаты этого baseline-а задним числом.

## Checkpoint G1/G2A code-fixes — 2026-09-12

Протокол текущей сессии по [плану](14-development-plan.md) G1 + кодовая часть G2A. Коммит сессии и результат native-проверок дополняются по живой системе; эта запись фиксирует только то, что проверено здесь.

### Собрано и проверено (Linux, `cargo`)

- `default-members` = platform-independent набор (core, chatter, config, corrector, snippets); `cargo build`/`cargo test` на любой ОС трогает только portable crates. Полный `cargo build --workspace` на Linux — OK.
- `cargo test --workspace` (Linux): **43 unit tests**, 0 failed: core 23, chatter 6, corrector 4, snippets 5, input 5. `cargo clippy` на изменённых crates — без warning.
- Удалён неиспользуемый `crates/typetune-input/src/evdev_source.rs` (L11-adjacent изоляция мёртвого кода; в сборку не входил).

### Изменения кода

- `crates/typetune-input/src/lib.rs`:
  - **L01**: убран `EVDEV_OFFSET`; `evdev_keycode_identity` — маппинг identity; evdev/uinput в одном keycode-пространстве, +8 остаётся только на XKB-границе decode.
  - **L02**: `evdev_value_to_action`: `0→Up, 1→Down, 2→Repeat`, прочие значения отфильтрованы; repeat больше не превращается в Up.
  - **L03**: `EVIOCGRAB` — ветка ядра выбирается по `if (p)` (сверено с Linux v6.12 `evdev.c` evdev_do_ioctl). `grab()` передаёт не-NULL, `ungrab()` — NULL. Введён `grabbed: bool`, ungrab только при фактическом захвате, ошибки возвращаются, а не игнорируются. RAII: `Drop` отпускает только захваченное устройство; закрытие fd освобождает grab в ядре.
  - **L04 (кодовый контур)**: единый stop-токен `Arc<AtomicBool>` через `stop_token()`/`stop(&self)`; поток CLI регистрирует SIGTERM/SIGINT на том же токене, полярность сходится с проверкой цикла; доработка epoll cleanup и ungrab на путях ошибок.
  - **L06 (частично)**: `read_events` возвращает typed `PhysicalKeyEvent` с `DeviceId`, `NativeCode::Evdev`, `KeyAction`, `source_time` из `input_event.time`, sequence и `EventOrigin::Physical`. Поле времени у `input_event` ядро заполняет из **CLOCK_REALTIME** (`INPUT_CLK_REAL`); конвертация в домен `Instant` вычитает delta из свежего `clock_gettime(CLOCK_REALTIME)` (см. live-подтверждение ниже).
- `crates/typetune-inject/src/lib.rs`:
  - **L11**: fd `/dev/uinput` открывается с `O_CLOEXEC`; `write_all_fd` — повтор при EINTR, цикл по partial write, ошибки с errno.
- `crates/typetune-cli/src/main.rs`:
  - Убран нечитаемый `Arc<AtomicBool>=true` флаг; shutdown через `source.stop_token()`. Мост `PhysicalKeyEvent → InputEvent`: Down/Up переносятся (identity keycode, source timestamp); **Repeat не форвардится** в legacy pipeline (legacy `KeyState` и uinput-вывод не выражают repeat без повторного press или снятия hold — политика зафиксирована в коде моста).

### Unit-покрытие транспорта

- `in01_identity_keycode_preserved_across_physical_surface`: codes 1 (Esc), 2/3/6/7 (цифры), 28 (Enter), 30 (A), 42/54 (Shift), медиа-коды >255 — identity, без underflow.
- `in02_repeat_stream_preserved_as_distinct_actions`: `Down,Repeat,Repeat,Up` не схлопываются.
- `evdev_value_maps_to_action`, `source_time_and_sequence_carried_on_event`, `monotonic_delta_arithmetic`.

### Границы (Not run / требует live-стенда)

- Реальный evdev read, EVIOCGRAB/ungrab на живом устройстве, восстановление после `SYN_DROPPED`, hotplug/reconnect, две клавиатуры, media key с кодом >255, SIGTERM/SIGINT на живом daemon, отказ uinput.
- Gnome/KDE Wayland, X11, XWayland — вне этого среза.
- Поэтому статусы матрицы приёмки: IN-01/IN-02 — Unit подтверждён, Linux-части строк остаются `Not run` до стенда. L04/L05 выходы, строка IN-10 — только код-контур собран; runtime не проверен.

Следующая работа: G2A live identity relay на стенде с синтетическим input и независимым observer, затем G2B capability report.

## Checkpoint G2A live-стенд — 2026-09-12

Протокол живого прогона на рабочей машине. Среда: Ubuntu 26.04, GNOME Wayland (`ubuntu:GNOME`), ядро 7.0.0-31-generic, `cargo test --workspace` = **54 unit tests, 0 failed** (core 23, chatter 6, corrector 4, snippets 5, input 16), clippy (изменённые crates) и `cargo fmt` чисто. Real клавиатуры машины (Keychron V1, YICHIP Wireless и др.) не трогаются: все проверки — на синтетических uinput-устройствах.

### Изменения кода по итогам стенда

- **Timestamps**: `input_event.time` заполняется ядром из CLOCK_REALTIME (константа `INPUT_CLK_REAL`, `include/linux/input.h`). Исходная версия сравнивала его с CLOCK_MONOTONIC и падала с `overflow when subtracting durations` (realtime ~1.7e9s против monotonic). `evdev_time_to_instant` теперь семплирует CLOCK_REALTIME, вычисляет delta и конвертирует в домен `Instant`; `monotonic_delta` использует `saturating_sub` (граница: событие из будущего не паникует). Добавлен regression-случай в `monotonic_delta_arithmetic`.
- **Семантика ядра для value=2** подтверждена по `drivers/input/input.c`: EV_KEY `value == 2` проходит безусловно; `value 0/1` проходит только если меняет состояние `dev->key` (`!!test_bit != !!value`). Для релея это означает: общее выходное устройство — единый keycode-домен, одновременное удержание одного keycode с двух источников невыразимо и легитимно фильтруется. Это свойство ядра, не дефект ретрансляции (тот же лимит у одиночного uinput-устройства в Espanso-архитектуре).
- Probe-примеры `repeat_probe` и `interleave_probe` (свободные примеры в `typetune-input`): первый — direct readback поворота `Down,Repeat×3,Up` в порядке (с grab и без), второй — воспроизводит фильтрацию дублирующих переходов состояния.

### Live стенд `crates/typetune-input/examples/stand.rs` — STAND PASS, 6/6

К проверкам IN-01/02/05/07/04/11 добавлен IN-06 (hotplug). `EvdevSource` переведён на interior mutability
(`Mutex<Vec<EvdevDevice>>`, `run(&self)`, `Arc<EvdevSource>`) для поддержки `add_device()` из другого потока
через control pipe + epoll. `parse_control_messages()` — byte-verbatim framing для `path\nname\n` пар
(7 юнит-тестов: single/two/split_across_drains/split_after_path_newline/split_inside_path/empty/exact_boundary).

Сценарий: два синтетических uinput-входа (`TypeTune Test Input`/`B`), оба в одном `EvdevSource` (grab через EVIOCGRAB),
relay через `VirtualKeyboard::emit_physical` (Down=1, Repeat=2, Up=0) в общий выход `TypeTune Virtual Keyboard`,
независимый observer без grab от сессии, но **с grab от процесса** (EVIOCGRAB на выходе изолирует сессию).

Прогон: `cargo run -p typetune-input --example stand`.

| Проверка | Результат |
|---|---|
| Exclusive grab на удержанном устройстве (второй EVIOCGRAB) | второй grab отклонён |
| IN-01 identity: A=30, LShift=42, LCtrl=29, Enter=28, 1/6, Backspace=14, Esc=1 | 16 событий, коды тождественны |
| IN-02 repeat: `Down,Repeat×3,Up` кода 30 | 5 событий, порядок и действия сохранены |
| IN-05: keycode 30 попеременно на A и B (последовательно, чтобы ядро успело развести состояние keycode) | обе пары дошли с сохранением DeviceId |
| IN-07: media 256/274 (коды >255) со входа A | keybits выхода расширены до 0x2ff; обе пары relayed, трасса 29/29 |
| Stop-токен (единый shutdown), join без зависаний | relays остановлены чисто |
| Ungrab освобождает устройство (повторный grab свежим владельцем A и B) | оба устройства свободны |
| Трасса observer против expected | **31/31 событий `(KeyAction, PhysicalKeyCode)` совпали по порядку** (16 identity + 5 repeat + 4 IN-05 + 4 media + 2 IN-06) |
| IN-04 resync: feed 300 чередований Down/Up кода 30 (валидные переходы, >64-событийный буфер evdev) + удержанный 46, fd не читается | `SYN_DROPPED`-маркер получен; `read_events` сбрасывает поток и реконструирует состояние через `EVIOCGKEY`: удержанная клавиша 46 восстановлена (`EventOrigin::Resync`), пост-resync поток продолжает обычным `Up(46)`, `resynced=false` |
| IN-11 neutral-state: grab при удержанных клавишах | grab фиксирует `EVIOCGKEY`-снимок как старт (не повторяет нажатия), будущий `Up` удержанной клавиши релеится штатно; `resynced` в обычном потоке `false` |
| IN-06 hotplug: `add_device()` через control pipe, grab D, feed D (46 down/up), drop D (detach) | relay обрабатывает D-события, observer видит трассу; post-drop relay продолжает работать (A/B события до drop корректны); ядерная особенность: feed A/B после hotplug-D очищает evdev-буфер observer-а (workaround: drop D сразу после D-событий) |
| IN-09 output failure: закрытие uinput fd → `emit_physical` → EBADF | callback сигнализирует `stop_token` → relay выходит из loop, `ungrab_all_locked` отпускает grab; relay остановлен чисто, grab A/B освобождены |
| IN-10 SIGTERM/SIGINT: `typetune daemon` → grab 4 устройств → `kill -TERM`/`kill -INT` | stop_token → relay выходит из loop, ungrab всех4 устройств, "Event loop stopped", "Virtual keyboard destroyed"; exit code143 (SIGTERM) |
| Nightly unit регрессии | 54 тестов green, включая `resync_deltas`, `monotonic_delta_arithmetic`, `parse_control_messages` (7 тестов framing) |

**Находки по kernel evdev (проверено на 7.0.0-31-generic):**

- `input_event.time` — домен `CLOCK_REALTIME` (`INPUT_CLK_REAL`), не MONOTONIC; смещение пересчитывается
  через свежий реалтайм-снимок, будущее событие → `Duration::ZERO`.
- EV_KEY disposition (`input_get_disposition`): `value==2` проходит всегда; `0/1` только при смене
  `!!test_bit(code, dev->key) != !!value`. Событие «Up неудержанной» или «Down удержанной» клавиши
  фильтруется и НЕ создаёт переполнение — форсировать overflow в тестах нужно валидными переходами.
- `EVIOCGKEY` возвращает **число скопированных байт (96), не 0**; проверять `ret < 0`, иначе успех
  трактуется как ошибка (в коде был bug: positive-ret читал застарелый errno). Побочно ioctl
  вымывает pending EV_KEY из очереди клиента — snapshot согласован с потоком.
- При переполнении evdev отдаёт клиенту `SYN_DROPPED`-маркер и «новейшее событие», история
  восстановима только через state snapshot; маркер читается штатно (в старом стенде его «не было»,
  т.к. feed давал лишь ~10 валидных событий < буфера 64).

Правильные `Not run` на этом стенде: media keys >255 через реальный вывод uinput (неизвестно; событие закрыто косвенно капабилити), одновременное удержание одного keycode с двух физических клавиатур (невыразимо в едином домене — см. выше), X11/XWayland/native Wayland profiles, GUI/tray (на машине отсутствуют glib/gtk dev-заголовки; для стенда не нужны).

Следующая работа: G2A gate-прогон IN-01..11, затем G2B capability report. Ведущий план — `docs/18-linux-completion-plan.md`.
