# Frames, recovery и watchdog — 2026-09-15

Актуальное продолжение: [helper и проверки транспорта](23-helper-transport-validation.md).
Описанная ниже структура daemon/watchdog относится к предыдущему срезу.

## Срез

HEAD `ca6ccaec05c511ff1e1fa210a5e703c5f5269365` + рабочие изменения.
Коммит не создавался; сохранены незавершённые правки предыдущих этапов.
Продолжение [checkpoint 21](21-physical-relay-checkpoint.md): реализован следующий
срез транспорта, без подключения legacy text/chatter stages.

## Изменения

### Пакеты клавиш

Reader сохраняет неполный пакет между read calls и публикует его только по
SYN_REPORT. Лимиты: 256 raw records за read call, 1024 EV_KEY в неполном frame;
превышение лимита frame возвращает ошибку. При SYN_DROPPED неполный пакет
отбрасывается; завершённые пакеты и snapshot reconciliation остаются согласованы.

`ReadResult.frames`, `Relay::forward_frame` и `VirtualKeyboard::emit_frame`
передают пакет до output с одним SYN_REPORT. Daemon и stand используют
`EvdevSource::run_frames`. Старые per-key методы оставлены как совместимые
адаптеры; они сами не обещают сохранение исходных границ.

Это контракт **пакетов EV_KEY**: MSC/LED/прочие классы raw input не реализованы.
Source time/sequence остаются в metadata событий; время kernel output отражает
новую инъекцию и не выдаётся за исходное время физического устройства.

### Независимый watchdog daemon

Перед grab daemon запускает отдельный процесс того же executable, ждёт handshake
и открывает неблокирующий heartbeat pipe. Сообщение о прогрессе отправляет сам
input loop, в том числе в idle, с интервалом не менее 100 ms. Отдельного потока,
который продолжал бы слать heartbeat при зависшем loop, нет.

Watchdog контролирует только своего родителя через pidfd, а не повторно найденный
числовой PID. Это исключает отправку сигнала новому владельцу переиспользованного
PID: [pidfd_open](https://www.man7.org/linux/man-pages/man2/pidfd_open.2.html),
[pidfd_send_signal](https://www.man7.org/linux/man-pages/man2/pidfd_send_signal.2.html).
Невозможность запуска watchdog/pidfd отклоняет startup до grab.

При отсутствии heartbeat 2 s или EOF монитор отправляет SIGTERM; если за 500 ms
процесс не завершился — SIGKILL. Это аварийный путь; штатные SIGTERM/SIGINT не
используют SIGKILL. Watchdog работает в отдельной process group. Его смерть
разрывает pipe: daemon останавливает relay, освобождает grab и уничтожает output.
Дисармирование выполняется после cleanup и уничтожения output. При аварийном
SIGKILL может остаться stale PID-файл; владение devices от него не зависит.

## Выполненные проверки

Ubuntu 26.04.1 LTS, kernel `7.0.0-31-generic`, GNOME Shell 50.1, Wayland
(`ubuntu:GNOME`), Rust/Cargo 1.98.1. Native backend — evdev/uinput;
observer захватывает только созданный тестом output. GTK/Qt/browser не участвуют.
Физические клавиатуры не открывались и не захватывались.

До исправления `in03_incomplete_frame_is_not_forwarded` падал: Down выдавался
до SYN_REPORT. После исправления этот и ещё три новых regression cases проходят:
неполный frame при потере событий; границы после ownership filtering/finish;
отказ записи frame без последующих cleanup writes.

| ID / команда | Проверенный результат |
|---|---|
| IN-03, native stand | Три быстро поданных пакета дошли с точным порядком клавиш и границами 2/2/2 |
| IN-04, native stand | Реальный overflow kernel evdev: потерянный Ctrl Up восстановлен; новый удержанный Shift восстановлен; обычный Up после resync дошёл |
| IN-05, native stand | Shift одновременно на A/B; отпускание A не снимает Shift B; snapshot output подтверждает удержание; последний Up B доходит |
| IN-11 startup | Attach с удержанным Ctrl отклонён; сторонний тестовый raw grab подтверждает освобождение; после Up neutral retry успешен |
| IN-10 SIGTERM + IN-11 stop | Отдельный daemon с удержанным Ctrl завершается с exit 0 примерно за 130 ms; output удалён, input доступен повторному grab |
| IN-10 SIGINT + IN-11 stop | SIGINT всей process group тестового daemon, аналог терминального Ctrl+C: exit 0, примерно 140 ms; output удалён, input доступен |
| WD-01 | SIGSTOP всего daemon: watchdog завершает его SIGKILL примерно за 2.5–2.7 s; output удалён, input доступен |
| WD-02 | SIGKILL только watchdog: daemon обнаруживает потерю pipe и выходит с ошибкой, примерно за 200 ms; output удалён, input доступен |
| Idle lease | Daemon живёт без событий дольше 2 s: heartbeat зависит от прогресса loop, а не наличия ввода |
| IN-01/02/06/07/09 | Повторно пройдены исходные native cases identity/repeat/hotplug/media/output-callback-error |
| `cargo test --workspace --offline` | 70 passed: core 23, chatter 6, corrector 4, snippets 5, input 29, CLI 3 |
| Build workspace, Clippy input/inject/CLI `--all-targets -- -D warnings`, fmt, diff | Успешно |

Для overlapping Shift порядок между устройствами подтверждается barrier-клавишами
того же устройства, а не произвольным sleep. Lifecycle stand запускает настоящий
daemon с отдельным config/PID-файлом и явным synthetic device. При ошибке стенд
сам завершает созданный child. `RUST_LOG=info` задаётся стендом для readiness marker.
Вывод содержит только заранее заданные тестовые события и статусы.

Повторение:

```sh
cargo build -p typetune-cli --offline
cargo run -p typetune-input --example stand --offline
cargo run -p typetune-input --example lifecycle_stand --offline -- "$PWD/target/debug/typetune"
```

## Границы результата

- Измеренные времена — наблюдения этого стенда, не real-time гарантия ОС.
- При остановке native тест подтверждает удаление output и доступность input.
  Он не утверждает, что прочитал последний Up после уничтожения uinput;
  явные cleanup edges отдельно проверены unit tests. Бесшовное продолжение
  физического удержания после detach не обещается.
- IN-10 покрывает SIGTERM/SIGINT, но не будущие tray exit / IPC Shutdown.
- IN-04 проверяет `resynced` и физическое состояние; text engine для проверки
  сброса его истории пока не подключён.
- G2A целиком ещё не принят: остаются полная проверка capabilities, IN-08 fault
  cases, monotonic timestamps/clock jumps, автоматический hotplug watcher daemon,
  отдельный минимальный helper и проверка privileges/установки. Watchdog не заменяет их.
- Старые characterization tests text/chatter дефектов остаются зелёными и не
  являются доказательством готовности этих функций. Текстовый Wayland профиль
  ещё требует session adapter с layout/focus/composition/Unicode и одного
  принятого сниппета в контролируемом поле.
