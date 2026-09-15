# Почему Linux-реализация пока не работает как продукт

Дата: 2026-09-15. Исследован HEAD `ca6ccaec05c511ff1e1fa210a5e703c5f5269365`
**с существующими незакоммиченными изменениями**. Это оценка рабочего дерева,
а не повтор аудита baseline `8cc19d0`. Реализация в этой диагностике не менялась.

## Результат

Главная причина: новый транспорт проверяется отдельно, но приложение продолжает
исполнять старую цепочку физической фильтрации и текстовых правил. Целевая архитектура
из [13](13-target-architecture.md) ещё не стала рабочим текстовым runtime.
Наличие crates и успешные unit tests не замыкают путь от клавиши до правильного текста в поле.

### 1. Daemon не передаёт текст текстовым правилам

В callback `crates/typetune-cli/src/main.rs` создаётся `InputEvent::new(...)` без
`with_character`; конструктор оставляет `character=None`. Corrector и snippets
при `None` возвращают исходное событие. `LayoutManager` встречается только в своём
модуле и не подключён к daemon. Поэтому обычный набор не запускает замену слова
или сниппета, даже когда статус показывает включённую функцию.

### 2. Стенд и приложение исполняют разные пути

- `crates/typetune-input/examples/stand.rs:118`: `emit_physical`, сохранение Repeat,
  остановка через stop token при ошибке output.
- `crates/typetune-cli/src/main.rs`: мост в legacy `InputEvent`, `Repeat => return`,
  потеря device/origin, `vkb.emit`; ошибка output только логируется.
- `add_device()` вызывается стендом, но в daemon нет вызывающего его hotplug watcher.

Следовательно, IN-02/IN-09/IN-06 со стенда нельзя переносить на готовность daemon.
Потеря kernel Repeat установлена по коду; видимый autorepeat compositor/app отдельно не проверялся.

### 3. Простое подключение character активирует ошибки следующего слоя

- Corrector удерживает буквы (`return vec![]`), затем генерирует Backspace, как будто
  эти буквы уже были введены. Удаляется предшествующий текст. Случай
  `f09_corrector_deletes_before_word` воспроизводит именно ошибочное поведение.
- Snippets заменяет на последней букве триггера, не передав эту букву приложению,
  но удаляет полную длину триггера. История не учитывает Backspace и reset.
- Вывод текста через таблицы keycodes теряет неподдержанные символы/регистр;
  общего Unicode replacement executor с focus/context guards нет.
- Shell-шаблон выполняет синхронный `Command::output()` внутри того же callback,
  который обслуживает grabbed клавиатуры. При активированном matching зависание
  команды остановит forwarding. Сейчас этот путь обычно скрыт за `character=None`.

### 4. Anti-chatter остался старым алгоритмом

`last_press` индексируется только keycode. Быстрый второй Down подавляется,
а его Up проходит; два устройства не различаются. Автомата физических/output
удержаний и release-debounce scheduler из спецификации нет. Тесты
`l09_rapid_press_suppresses_down_but_not_up` и `l09_two_devices_same_key_no_identity`
проходят, поскольку ожидают дефектный результат.

### 5. Даже транспорт ещё имеет пробелы состояния

Статический анализ `crates/typetune-input/src/lib.rs`:

- `key_state` записывается при snapshot/resync, но не обновляется обычными EV_KEY.
  Если после нейтрального snapshot доставлен Down, затем потерян Up, следующий
  пустой snapshot сравнивается со старым пустым состоянием: нужный Up не выдаётся.
- Disconnect удаляет устройство через `swap_remove`, без передачи освобождения
  его output удержаний. Output ownership по устройствам не реализован.
- Чтение SYN_DROPPED сразу прерывает цикл: нет явного состояния discard до следующего
  SYN_REPORT. Контракт ядра требует пропустить события до SYN_REPORT включительно,
  затем запросить состояние: [Linux input event codes](https://cdn.kernel.org/doc/html/latest/input/event-codes.html).

Эти выводы основаны на коде; новые live fault cases в этой диагностике не запускались.
Существующие tests `resync_deltas_*` проверяют сравнение двух готовых bitmap,
а не сопровождение состояния полным read/relay циклом.

### 6. Wayland gate отмечен завершённым преждевременно

[Отчёт 19](19-wayland-capability-report.md) смешивает доставку физических keycodes
и знание реально введённого текста. В `typetune-layout` создаётся собственная keymap
`us,ru`; источника обновлений состояния GNOME нет. `xkb_state_serialize_layout`
читает локальное состояние, а не опрашивает Mutter. Клиентское состояние требует
явной синхронизации: [libxkbcommon state API](https://xkbcommon.org/doc/current/group__state.html).

Объяснение «grab сам блокирует layout switching» не установлено имеющимися
проверками: надо проследить всю комбинацию до output и проверить реакцию compositor.
Положительный тест keycode relay этого не доказывает и не опровергает.
`per-window=false` не доказывает поддержку per-window режима. Для утверждений о
GTK/Qt/browser/XWayland в отчёте нет отдельных версий приложений и результатов чтения поля.
Рекомендация работать без привязки к полю противоречит отказу при Unknown context
в канонической спецификации. Текстовый GNOME Wayland профиль пока не принят.

### 7. Настройки могут сообщать успех без изменения поведения

SIGHUP/D-Bus заменяют `config_arc`, но pipeline построен один раз из копии config.
IPC status перечисляет функции по новому config, а не по реально работающим stages.
Reload также использует default path вместо исходного `--config`.
Это объясняет эффект «настройку изменил, ничего не изменилось».

## Проверки

- Среда: Ubuntu 26.04.1 LTS, kernel `7.0.0-31-generic`,
  `XDG_SESSION_TYPE=wayland`, `ubuntu:GNOME`, GNOME Shell 50.1.
- Rust 1.98.1, Cargo 1.98.1.
- `cargo test --workspace --offline`: exit 0, **54 unit tests passed**:
  core 23, chatter 6, corrector 4, snippets 5, input 16.
- CLI, config, layout, inject, GUI, tray: **0 tests**; это не проверка их поведения.
- Выполнены имеющиеся IN-01/IN-02 conversion tests, `in06_parse_control_*`,
  `resync_deltas_*`, L09/F09/F10/R4/R5/R6 и остальные unit cases.
  L09/F09/F10/R4/R5/R6 включают фиксацию дефектного поведения, не acceptance.
- Warning: неиспользуемый `ReadResult::nothing`.
- Сопоставлены production callback, stand callback и checkpoints 17/18/19.

## Порядок продолжения

1. Вернуть gate-статус к evidence: отдельно библиотека, стенд, daemon, native editor.
2. Сделать один общий физический relay для daemon и стенда; проверить Repeat,
   output failure, device ownership, disconnect, resync, bounded shutdown.
3. Выбрать конкретный текстовый профиль и доказать в нём layout/context/Unicode
   в одном контролируемом поле. Для GNOME Wayland начать с проверки доступного
   session adapter; Unknown должен явно отключать замену.
4. Реализовать один статический сниппет через observation → history → plan → executor.
   Проверять окончательный текст, каретку и удержания. Затем ручная коррекция.
5. Отдельно довести anti-chatter автомат. Автокоррекция, shell и GUI — после
   работоспособной вертикали и controller с честным applied-status.

## Ограничения

Daemon и live stand не запускались; физические устройства не открывались и не
захватывались. Native acceptance, права устройства, latency, установка и поведение
конкретных редакторов не проверены. Документы 17/18/19 сохраняют исторические записи;
их прежние заявления о готовности нужно читать с поправками этого среза.
