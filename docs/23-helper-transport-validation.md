# Минимальный helper и проверки транспорта — 2026-09-15

## Результат

HEAD `ca6ccaec05c511ff1e1fa210a5e703c5f5269365` + рабочие изменения; новый commit
не создавался. Продолжение [checkpoint 22](22-frames-watchdog-validation.md).

- Новый `typetune-helper` владеет evdev/uinput и выполняет physical relay.
  Daemon передаёт выбранные устройства, ждёт readiness и поддерживает lease
  через private pipe. Helper не зависит от GUI, D-Bus, конфигуратора, словарей
  или текстовых правил. Бинарники должны находиться рядом; helper добавлен
  в assets будущего deb-пакета.
- Watchdog выделен в `typetune-input`: отдельные мониторы защищают supervisor
  daemon и input loop helper. При утрате родителя helper завершает работу;
  при зависании helper его монитор освобождает устройства завершением процесса.
  Сохранены pidfd, отдельные process groups и ограниченный heartbeat.
- До grab проверяются input capabilities и соответствие диапазону output
  (keycodes 1..=0x2ff). REL/ABS и неизвестные классы отклоняются. Обычный файл
  больше не принимается за evdev: regression test сначала воспроизвёл дефект.
- Reader включает `EVIOCSCLOCKID(CLOCK_MONOTONIC)`. Source timestamps переводятся
  через фиксированную пару kernel clock / Rust Instant без realtime samples.
- Watcher раз в 250 ms повторяет attach только явно выбранных разрешимых symlinks
  (обычно `/dev/input/by-id`). Активный путь повторно не открывается. Неуспешный
  neutral-state attach повторяется позже. Raw `eventN` остаётся startup-only:
  после disconnect его номер может принадлежать другому устройству.
- Не более 32 выбранных устройств; drain control pipe ограничен четырьмя чтениями
  по 4096 bytes за проход. Прежние пределы input read/frame сохраняются.

## Проверки

Ubuntu 26.04.1 LTS, kernel `7.0.0-31-generic`, GNOME Shell 50.1, Wayland
(`ubuntu:GNOME`), Rust/Cargo 1.98.1, UID 1000. Backend — evdev/uinput.
GTK/Qt/browser не участвуют. Все устройства и события синтетические;
observer захватывает тестовый output. Основная клавиатура не открывалась.

| Case | Результат |
|---|---|
| IN-08 open failures | Отсутствующий output: ENOENT; временный path без прав: EACCES output и отказ input. Права настоящих устройств не менялись |
| IN-08 busy | B занят тестовым grab: startup A+B отклонён, output writes = 0, grab A откатан и доступен probe |
| IN-08 capabilities | Синтетический KEY+REL отклонён до grab; независимый probe может его захватить |
| IN-03-clock | Kernel source time попал в monotonic интервал между отправкой и чтением с допуском 2 ms; unit test проверяет дельты и некорректные timestamps |
| IN-06 daemon | Удаление синтетического устройства, создание нового и обновление выбранного symlink автоматически приводят к reattach |
| IN-10 TERM / INT + IN-11 stop | Настоящий daemon с удержанным Ctrl: exit 0, около 275–279 ms; output удалён, input доступен повторному grab |
| WD-01 daemon freeze | SIGSTOP daemon: его watchdog завершает процесс, output удалён, input доступен; около 2.53 s |
| WD-02 monitor death | Гибель монитора daemon: exit 1, освобождение устройств; около 183 ms |
| WD-03 helper freeze | SIGSTOP helper: его watchdog завершает процесс, daemon exit 1, освобождение устройств; около 2.66 s |
| WD-04 helper death | SIGKILL helper: daemon exit 1, освобождение устройств; около 165 ms |
| Staged install | Оба debug-бинарника скопированы во временный каталог; весь lifecycle suite повторно прошёл, включая ownership и WD-01…04. Установка в систему не выполнялась |
| Ownership | `/proc` подтверждает отсутствие evdev/uinput fd в daemon и совпадение всех UID helper с текущим пользователем |
| IN-01/02/03/04/05/06/07/09/11 | Прежние identity/media/repeat/frame/resync/ownership/disconnect/output-error/neutral-start cases повторно прошли |
| Unit suite | `cargo test --workspace --offline`: 74 passed (input 33, core 23, chatter 6, corrector 4, snippets 5, CLI 3) |
| Build / static checks | Workspace build, Clippy input/inject/helper/CLI all-targets с `-D warnings`, fmt и diff check |

Воспроизведение:

```sh
cargo build --workspace --offline
cargo test --workspace --offline
cargo run -p typetune-input --example stand --offline
cargo run -p typetune-input --example lifecycle_stand --offline -- "$PWD/target/debug/typetune"
cargo clippy -p typetune-input -p typetune-inject -p typetune-helper -p typetune-cli --all-targets --offline -- -D warnings
```

## Ограничения и следующий этап

- Это профиль **EV_KEY frames**, не универсальный raw relay: MSC metadata,
  LED feedback и REP settings не пересылаются. REL/ABS устройства отвергаются.
- Helper работает с тем же UID и уже имеющимся доступом к устройствам; setuid
  режим запрещён. Разделение процессов изолирует владение fd и lifecycle,
  но не создаёт security boundary между процессами одного UID. Policy активной
  сессии, lock/logout и выдача/отзыв разрешений требуют отдельной приёмки.
- EACCES проверяет отказ открытия. Смена прав path не отзывает уже открытый fd;
  runtime revocation этим тестом не подтверждён.
- Monotonic mapping проверен без изменения системного времени.
- Исходно отсутствующий выбранный input вызывает startup error. Автоматическая
  повторная попытка применяется к disconnect после успешного старта.
- Времена остановки — измерения стенда, не realtime гарантия. После уничтожения
  output проверяется доступность input, а не доставка последнего Up приложению.
- G2A целиком не объявляется принятым: остаются session/permissions acceptance,
  договорённость о достаточности key-only профиля и установка. Полный deb lifecycle
  относится к G6. Tray/IPC Shutdown пока не входят в signal acceptance.
- Legacy chatter/corrector/snippets остаются отключёнными. Часть их старых тестов
  фиксирует известные дефекты; зелёный suite не означает готовности функций.
- Следующий функциональный этап — G2B: проверяемый session adapter для конкретной
  сессии (layout, focus/lock, composition, Unicode). Затем G3: один статический
  сниппет через единый replacement executor в контролируемом поле. X11, XWayland
  и native Wayland должны иметь отдельные результаты.
