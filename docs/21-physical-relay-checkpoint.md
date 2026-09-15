# Исправление физического relay — 2026-09-15

Следующий срез выполнен: [frames, recovery и watchdog](22-frames-watchdog-validation.md).
Ниже сохранён протокол первого этапа.

## Срез и результат

HEAD `ca6ccaec05c511ff1e1fa210a5e703c5f5269365` + рабочие изменения; отдельный
коммит не создавался. Существующие незавершённые изменения сохранены.
Основание: [диагностика](20-linux-diagnosis.md). Завершён первый срез исправления
транспорта; Linux-продукт и текстовая вертикаль ещё не приняты.

- Daemon и stand используют один `EvdevSource::run_with_ready` / `run` и
  `relay::Relay` с fallible output callback. Legacy pipeline отключён от forwarding.
  Shell, text stages и GUI mutex не вызываются при обработке ввода.
- Down/Up/Repeat, native code, source time, device identity и origin не теряются
  в daemon. Ownership по `(device,key)` не даёт отпусканию/отключению одного
  устройства снять удержание другого на общем uinput output.
- Output error возвращается из loop, прекращает записи и освобождает grabs.
  Частично выполненный write не повторяется. Владелец уничтожает output.
- Disconnect освобождает удержания исчезнувшего устройства; stop освобождает
  виртуальные удержания перед ungrab.
- Обычные события обновляют key-state bitmap. После SYN_DROPPED reader пропускает
  данные до SYN_REPORT, в том числе через несколько read calls. Ошибка snapshot
  возвращается вызывающему коду. Valid prefix и reconciliation согласованы.
  Чтение ограничено 256 raw events за вызов.
- Attach при ненейтральном состоянии отклоняется с ungrab. Ошибка открытия/grab
  любого явно выбранного начального устройства не замалчивается.
- Stand сравнивает фактические трассы; ошибка/таймаут возвращает ненулевой код.
  Forced stop не засчитывается как output-failure PASS. Устранено ручное закрытие
  заимствованного raw fd с риском повторного close. Имена устройств включают PID;
  output захвачен до первого ввода; отдельный watchdog выставляет stop через 15 s.

## Изменение поведения CLI

`daemon`/`start` **отказывают до открытия устройств**, если включён неподдержанный
backend: `chatter`, `corrector`, `snippets`, `typography`. Для физического relay
нужны `input.discovery = "manual"`, непустой `device_paths` и выключенные эти функции.
Старый default config не переписывается: запуск с ним сообщит причину отказа.
Автоматического захвата всех клавиатур больше нет.

IPC показывает только `physical-relay`; готовность устанавливается после grab и
настройки epoll. Pause возвращает ошибку; CLI/D-Bus reload — `restart-required`.
SIGHUP пишет причину и не меняет effective config. Tray с неработающими toggles
не запускается. `start` передаёт исходный `--config`, запускает текущий executable
и замечает ранний выход child вместо безусловного «daemon started».

Изолированная проверка сама выбирает свои синтетические устройства:

```sh
cargo run -p typetune-input --example stand --offline
```

## Проверки

Ubuntu 26.04.1 LTS, kernel `7.0.0-31-generic`, GNOME Shell 50.1, Wayland
(`ubuntu:GNOME`), Rust/Cargo 1.98.1. Backend проверки: evdev/uinput и собственный
grabbed observer; GTK/Qt/browser не участвовали.

| Проверка | Результат |
|---|---|
| Red test до исправления `in04_normal_down_is_remembered_for_lost_release` | FAILED: `[]` вместо `[(30, Up)]` |
| `cargo test --workspace --offline` | 66 passed: core 23, chatter 6, corrector 4, snippets 5, input 25, CLI 3 |
| `cargo build --workspace --offline` | exit 0 |
| Clippy input/inject/CLI, `--all-targets --offline -- -D warnings` | exit 0 |
| `cargo fmt --all -- --check`, `git diff --check` | exit 0 |
| Native IN-01/IN-07 | Совпадение Down/Up для 30,42,29,28,2,7,14,1,256,274 |
| Native IN-02 | Совпадение Down,Repeat×3,Up |
| Native IN-06 | Attach synthetic B, Down(46), disconnect → Up(46) |
| Native IN-09 | Output callback error → возврат ошибки и завершение без forced stop; повторный grab synthetic A успешен |

Новые cases: пять reader tests `in04_*` / `in03_read_batch_is_bounded_and_keeps_remaining_records`,
четыре `relay::tests::*` (Repeat/metadata, shared ownership, disconnect/stop,
terminal output error), три CLI/IPC теста отказов и честного статуса.
Reader fixtures передают синтетические input_event через локальный Unix socket.
Socket tests и native stand запускались вне sandbox с разрешением.
Физические клавиатуры не открывались. Старые characterization tests дефектов
входят в общий счётчик: их успех не подтверждает исправление text/chatter crates.

## Ограничения и следующий шаг

G2A целиком не закрыт. Нового native IN-04/IN-05/IN-10/IN-11 нет. IN-03 проверяет
bounded reads, а не сохранение исходных SYN frames. Нет измерения latency,
аппаратного debounce, отдельного watchdog процесса daemon, автоматического
hotplug watcher daemon, полной проверки output capabilities и переноса удержаний
между физическим и виртуальным устройствами при detach. Stop освобождает
виртуальные клавиши; продолжение удержания после detach не обещается.
Realtime → Instant требует отдельной проверки clock jumps. Реальный отказ
ioctl/write и отказ output callback — разные тестовые уровни.

Старые `STAND PASS 6/6` и отметки полного G2A/G2B в документах 17–19 не доказывают
принятие продукта. Текстовый Wayland профиль, focus/layout/composition/Unicode
остаются непроверенными для замены в редакторе.

Дальше: остальные transport acceptance cases; затем GNOME session adapter и один
статический сниппет observation → history → plan → executor с проверкой текста,
каретки и удержаний. Возвращать `with_character` в старый pipeline нельзя:
ошибки удаления и Unicode в отключённых legacy правилах ещё существуют.
