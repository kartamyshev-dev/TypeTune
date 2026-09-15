# План доведения Linux-версии TypeTune

## Точка продолжения — 2026-09-16

Реализованы два preview режима: IBus и opt-in compatibility evdev/uinput.
Последний checkpoint — [повторный Double Shift](39-repeat-double-shift.md).
Физический ввод в браузере подтверждён пользователем после [исправления latency](38-compat-input-latency.md).
Сводные результаты: [115 Rust + 35 Python tests и native cases](17-validation-record.md).

Следующие задачи:

1. Расширить матрицу реальных приложений: браузеры, Qt/Electron, редакторы,
   терминалы; отдельно selection, IME, hotplug и вмешательство во время замены.
2. Закрыть end-to-end fault/lifecycle acceptance нового compatibility transport;
   Feed/Clutter fixture не заменяет physical evdev → uinput приемку.
3. Расширить и оценить словарь на размеченном корпусе; добавить пользовательские
   исключения и сохранение настроек между запусками.
4. Настройки/диагностика в UI, выбор режима и исключения чувствительных приложений.
5. Другие Linux desktops и standalone X11 — отдельные backend/acceptance этапы.

Полная поддержка всех приложений и завершение G2–G4 не заявляются.

## Исторические отметки этапов

## Поправка 2026-09-15

Актуальная точка продолжения: [пользовательский preview IBus](35-user-test.md).
Добавлены portable range executor, cooperating GTK text-field adapter и статический
snippet :hi + Space. Native Wayland typing в собственном поле проверен.
IBus manual adapter принят в ограниченном профиле Chrome Wayland; добавлена пользовательская установка.
Текущие проверки: 105 unit + 2 CLI integration tests, 15 Python adapter/profile tests.
G2A/G2B целиком не закрыты. Проверены IN-08, capabilities, monotonic timestamps,
автоматический reattach выбранного symlink и отдельный helper с watchdog.
Unit tests и native transport cases не означают готовность текстовых функций.
Остаются session/permissions acceptance и ограничения key-only профиля.
Отметки ниже — исторический срез 12–13 сентября, пересмотренный по
[диагностике](20-linux-diagnosis.md) и последующим checkpoints.

Статус: активный рабочий план. Ведётся от 2026-09-12. Канонические фазы — в
[docs/14-development-plan.md](14-development-plan.md); этот файл — рабочая трассировка
выполнения и результат на живой машине (Ubuntu 26.04, GNOME Wayland, ядро 7.0.0-31-generic).

## Легенда статусов

- `[x]` — выполнено и проверено (есть evidence в `docs/17-validation-record.md` или ниже).
- `[~]` — код готов, поведение на живом стенде не подтверждено.
- `[ ]` — не начато.
- После пункта допустима подпись причины/границы.

## Текущее состояние на 2026-09-12

- `cargo build --workspace` на Linux — OK; `cargo test --workspace` = **54 unit tests, 0 failed**.
- `default-members` = portable set (core, chatter, config, corrector, snippets).
- G1 (fixtures/регрессии) и кодовая часть G2A закрыты; live-стенд `examples/stand.rs` — `STAND PASS` 6/6:
  exclusive grab, IN-01 identity (16 событий), IN-02 `Down,Repeat×3,Up`, IN-05 с двух устройств,
  IN-04 resync (SYN_DROPPED → EVIOCGKEY reconstruction), IN-07 media 256/274,
  IN-06 hotplug attach + D events + detach, stop-токен, ungrab A/B, трасса observer 31/31.
- Найдены и зафиксированы в протоколе: realtime-домен `input_event.time` (не monotonic) и
  ядерная фильтрация EV_KEY по состоянию `dev->key` (value==2 проходит всегда).
- Доступ к `/dev/uinput` — через udev-правило `99-typetune-uinput.rules` (group `input`).
- Стенд изолирован от сессии: observer делает grab выхода, compositor значений не получает.

## Фазы и задачи

### G2A. Linux transport и lifecycle — ОСТАТОК

**Выход по плану:** identity relay на отдельном стенде проходит gate.

- [x] nongrabbing diagnostics устройств (`device_discovery`, ls /dev/input).
- [x] grab/ungrab (EVIOCGRAB, ветка по NULL) + `grabbed: bool`, RAII Drop.
- [x] identity keycodes (без +8), Down/Repeat/Up, отсев невалидных значений.
- [x] единый stop-токен, epoll loop, ungrab на путях ошибок.
- [x] `write_all_fd` (EINTR/partial), O_CLOEXEC для `/dev/uinput`.
- [x] live-стенд identity relay (IN-01/IN-02/IN-05, grab, ungrab, shutdown).
- [x] timestamps: realtime-домен `input_event.time` → домен `Instant` (CLOCK_REALTIME + saturating delta).
- [x] **Media keys >255 (IN-07)**: `VirtualKeyboard::new()` задаёт `UI_SET_KEYBIT` на полный
      evdev-диапазон `0..=0x2ff` (было `0..256`). Live-стенд: media 256/274 relayed, трасса 29/29.
- [ ] **Capabilities output в relay (план п.3)**: проверка поддержки кода/евента устройством,
      отказ устройства с понятной причиной вместо silent drop (IN-08 path частично).
- [x] **Resync после SYN_DROPPED (IN-04/IN-11)**: `EvdevDevice` ведёт вычисленное состояние
      удержаний (`key_state`, 96 байт EVIOCGKEY); на grab — neutral-state sync без повтора удержанных
      клавиш; на SYN_DROPPED — отказ от поточных данных, реконструкция текущего состояния и
      `EVIOCGKEY`-deltas с `EventOrigin::Resync`, флаг `ReadResult::resynced`. Live: маркер синтетического
      overflow (300 чередований Down/Up > 64-событийный буфер) → удержанный 46 реконструирован,
      пост-resync поток продолжается обычным Up. Nightly unit: `resync_deltas` cold/delta/empty.
- [x] **Hotplug/reconnect (IN-06)**: `EvdevSource` переведён на interior mutability (`Mutex<Vec<EvdevDevice>>`,
      `run(&self)`, `Arc<EvdevSource>`); `add_device()` через control pipe + epoll;
      `drain_control()` / `try_add_device()` с byte-verbatim framing (`parse_control_messages()`,
      7 юнит-тестов); hotplug grab + neutral-state sync. Live-стенд: attach D, feed D events (46 down/up),
      drop D (detach), трасса 31/31. **Известная ядерная особенность**: feed событий с A/B после
      hotplug-D-событий очищает evdev-буфер observer-а (EVIOCGRAB + uinput interaction); workaround —
      D дропается сразу после D-событий.
- [x] **Output failure / зависший consumer (IN-09)**: callback при `emit_physical` ошибке
      сигнализирует `stop_token` → relay выходит из loop, `ungrab_all_locked` отпускает grab.
      Live-стенд: закрытие uinput fd → `write failed: errno 9 (EBADF)` → relay остановлен чисто,
      grab A/B освобождены. Политика: grab отпускается при невосстановимой ошибке вывода.
- [x] SIGTERM/SIGINT на живом daemon (IN-10): `signal_hook::flag::register` для SIGTERM/SIGINT
      → `stop_token` → relay выходит из loop, `ungrab_all_locked` отпускает grab. Live: `typetune daemon`
      → grab 4 устройств → `kill -TERM`/`kill -INT` → ungrab всех → "Event loop stopped" →
      "Virtual keyboard destroyed". Exit code143 (SIGTERM).
- [x] Gate G2A: прогон матрицы IN-01..11 на стенде, фиксация в протоколе.
  `STAND PASS` 6/6, 54 unit тестов. Покрыто: IN-01 identity, IN-02 repeat, IN-04 SYN_DROPPED resync,
  IN-05 multi-device, IN-06 hotplug, IN-07 media >255, IN-09 output failure, IN-10 SIGTERM/SIGINT,
  IN-11 neutral-state. Не покрыто на этом стенде: IN-03 burst/frames (частично IN-01/02),
  IN-08 fault injection (grab fail / uinput недоступен — кодовая часть есть, live не прогнан).

### G2B. Wayland feasibility — capability report

**Выход по плану:** таблица возможностей по конкретной сессии (GNOME Wayland этой машины).

- [x] Источник событий и единый pipeline; совместимость с hardware filter. → uinput → evdev → Mutter работает; EVIOCGRAB эксклюзивен; identity relay подтверждён.
- [x] Актуальная keymap/group после переключения через UI, hotkey, per-window layout. → layouts us/ru; xkb group наследуется VirtualKeyboard; per-window=false; **grab блокирует переключение layouts** — требуется forward layout-switch keys.
- [x] Доступность focus/lock/context; поведение при Unknown context. → GNOME Shell D-Bus ограниченно; AT-SPI как опция для текстовых полей; нет прямого focus API.
- [x] RU/EN/Unicode delivery в native GTK, Qt, браузер; XWayland отдельно. → RU/EN работают через xkb group; XWayland работает; Unicode/keycodes beyond scope.
- [x] Portal permissions (VirtualKeyboard/RemoteDesktop): разрешить, отказать, отозвать, reconnect. → Portal доступен (RemoteDesktop, InputCapture), но не требуется для uinput.
- [x] IME/composition совместимость и способ гарантированно отключить правила. → IBus активен, RU/EN совместимы; CJK — отдельное исследование.
- [x] Gate: capability report с версиями и evidence; вывод профиля limited/unsupported если авто-коррекция ненадёжна. → **Profile: limited**. Документ: `docs/19-wayland-capability-report.md`.

### G3. Текстовая вертикаль (X11 baseline / Wayland по G2B)

**Выход по плану:** observation → text history → сниппет → replacement в контролируемом поле.

- [ ] Observation → text history → один статический сниппет → replacement executor → тестовое поле.
- [ ] Context invalidation, origin ledger, deadlines, bounded queue, modifier policy.
- [ ] Unicode insertion strategy; unsupported-result без предварительного удаления (RU/EN, регистр, punct, многострочность).
- [ ] Ручная RU↔EN коррекция слова; double Shift как gesture (с отдельной проверкой заглавных).
- [ ] Авто-коррекция после ручной: conservative policy, две валидные альтернативы, code-like не трогать.
- [ ] Конфликт сниппет/корректор: один план, одна замена, без self-matching.
- [ ] Gate: результат читается из поля; отдельно native-проверки в реальных редакторах.

### G4. Wayland-профиль и общие функции

**Выход по плану:** одна заявленная Wayland-конфигурация end-to-end; limited/unsupported отображаются явно.

- [ ] Подключить подтверждённые G2B возможности к engine.
- [ ] Config generations, applied-status, pause, CLI doctor, профили, startup lifecycle.
- [ ] Встроенные date/time без внешней команды.
- [ ] Clipboard-профили (по G3-решению) + базовые guards с первого paste.
- [ ] Shell worker и undo отдельными задачами после собственных tests.
- [ ] Gate: README с точными версиями проверенных профилей; без заявлений про «Linux вообще».

### G6. Оболочка и выпуск Linux

**Выход по плану:** самостоятельная установка без developer packages; config сохраняется; удаление освобождает устройства.

- [ ] GUI-решение по короткому prototype (tray на целевых ОС; GTK остаётся рабочей оболочкой до решения).
- [ ] Headless runtime/helper отделить от GUI-зависимостей.
- [ ] .deb: собрать, проверить содержимое, maintainer scripts, conffiles, права, user-session lifecycle.
- [ ] Install/upgrade/restart/uninstall: без незапрошенного grab, без расширения прав, без удаления пользовательских данных.
- [ ] Стендовая установка: privileges/session ownership, independent watchdog и bounded queues helper (план G2A п.5).
- [ ] Release notes: проверенная матрица, ограничения, способ отключения.

### Вне границ Linux-трассы (в план 14, но не обязательны для «Linux до конца»)

- G5 Windows/macOS адаптеры — отдельный трек после стабилизации G3-контракта.
- KDE Wayland профиль — отдельный capability report после GNOME.

## Матрица приёмки — актуальный статус (Linux-строки)

| ID | Статус сегодня | Комментарий |
|---|---|---|
| IN-01 | [x] Unit + live | 16 identity-событий на стенде |
| IN-02 | [x] Unit + live | Repeat×3 сохраняется как отдельные действия |
| IN-03 | [ ] | Burst/frames порядок — частично покрыт IN-01/IN-02; нужен replay |
| IN-04 | [x] Unit + live | SYN_DROPPED → resync; EVIOCGKEY-reconstruction сохраняет удержанную клавишу; пост-resync поток корректен |
| IN-05 | [x] Unit + live | Два устройства, последовательные кадры; одновременное удержание невыразимо в одном домене (kernel filter) |
| IN-06 | [x] Unit + live | Hotplug attach + D events + detach; interior mutability; 31/31 трасса |
| IN-07 | [x] live | keybits output расширен до 0x2ff; media 256/274 relayed (трасса 29/29) |
| IN-08 | [ ] | Fault injection: grab fail / uinput недоступен |
| IN-09 | [x] live | Output failure → stop_token signal → ungrab; EBADF тест на стенде |
| IN-10 | [x] live | SIGTERM/SIGINT → stop_token → ungrab; `typetune daemon` + kill -TERM/-INT |
| IN-11 | [x] Unit + live | neutral-state: граб стартует из EVIOCGKEY-снимка (без re-press удержанных); EVIOCGKEY возвращает 96 байт, не 0 |
| AC-* | [ ] | fake-clock anti-chatter — фаза после G2A gate |
| TX-01..21 | [ ] | есть кодовая база core/corrector/snippets и fixtures; текстовая вертикаль — G3 |
| CF-*, LC-* | [ ] | config/lifecycle — G3/G4 |
| PK-01 | [ ] | package — G6 |

## Порядок ближайших шагов

1. ~~G2A: media >255 — расширить keybits `VirtualKeyboard` и прогнать IN-07 на стенде.~~ (done)
2. ~~G2A: SYN_DROPPED/resync + neutral-state (IN-04, IN-11).~~ (done)
3. ~~G2A: hotplug (IN-06).~~ (done)
4. ~~G2A: output failure (IN-09), SIGTERM/SIGINT (IN-10), gate-прогон IN-01..11.~~ (done)
5. ~~G2B capability report GNOME Wayland.~~ (done — `docs/19-wayland-capability-report.md`, profile: limited)
6. G3 текстовая вертикаль → G4 → G6.

## Протокол обновлений

- 2026-09-12: создан план; зафиксирован срез G2A live-стенда `STAND PASS` 4/4; выявлены
  пробелы IN-04/IN-06/IN-07/IN-09 и keybits-ограничение инжектора.
- 2026-09-12: IN-07 (media >255) и IN-04/IN-11 (SYN_DROPPED → resync, neutral-state startup)
  реализованы и прогнаны на живом стенде — `STAND PASS` 6/6. Найдено и задокументировано:
  `EVIOCGKEY` возвращает число скопированных байт (96), а не 0; при overflow evdev отдаёт
  [`marker + newest event`], история не восстановима; события типа «value для неудержанной
  клавиши» фильтруются disposition и не создают overflow (тест фидит валидные переходы).
- 2026-09-13: IN-06 (hotplug) реализован: `EvdevSource` → interior mutability (`Mutex<Vec<EvdevDevice>>`,
  `run(&self)`, `Arc`); `add_device()` через control pipe + epoll; `parse_control_messages()` byte-verbatim
  framing (7 тестов). Live-стенд `STAND PASS` 6/6, 31/31 трасса, 54 unit тестов. Найдена ядерная
  особенность: feed событий с A/B после hotplug-D очищает evdev-буфер observer-а (EVIOCGRAB + uinput
  interaction);   workaround — drop D сразу после D-событий. Документация обновлена.
- 2026-09-13: IN-09 (output failure): callback при ошибке `emit_physical` сигнализирует `stop_token`;
  relay выходит из loop, `ungrab_all_locked` отпускает grab. Live-стенд: закрытие uinput fd →
  `EBADF` → relay остановлен чисто, grab A/B освобождены. `VirtualKeyboard::fd()` добавлен.
  54 unit тестов, `STAND PASS` 6/6.
- 2026-09-13: IN-10 (SIGTERM/SIGINT): `signal_hook::flag::register` для SIGTERM/SIGINT → `stop_token`;
  live: `typetune daemon` → grab 4 устройств → `kill -TERM` → ungrab всех, "Event loop stopped",
  "Virtual keyboard destroyed", exit code143.   SIGINT аналогично. Документация обновлена.
- 2026-09-13: G2B capability report: `docs/19-wayland-capability-report.md`. GNOME Shell 50.1,
  Wayland, ядро 7.0.0-31-generic. Profile: **limited**. Ключевые находки: uinput injection работает;
  xkb group наследуется VirtualKeyboard; **grab блокирует layout switching** (требуется forward);
  focus tracking — AT-SPI как опция; Portal доступен но не требуется; RU/EN работают; XWayland работает.
