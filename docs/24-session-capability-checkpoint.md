# G2B: диагностика сессии и контракт контекста — 2026-09-15

Продолжение: [GNOME compositor bridge](25-gnome-bridge-checkpoint.md).

## Результат и статус

HEAD `ca6ccaec05c511ff1e1fa210a5e703c5f5269365` + рабочие изменения, без нового
commit. Продолжение [helper checkpoint](23-helper-transport-validation.md).
Это первый реализованный срез G2B: **read-only session probe и строгий preflight
контекста**. Полный Wayland text adapter и G3 ещё не реализованы.

Добавлен `typetune-session`, независимый от evdev/uinput. Команда:

```sh
cargo run -p typetune-cli --offline -- doctor --session
```

возвращает JSON с версиями доступных API, результатом чтения GNOME screen shield,
неизвестными свойствами контекста и причинами запрета замены. Команда выполняется
до чтения/создания конфигурации; отсутствующий или повреждённый конфиг не мешает
диагностике. Exit 0 означает, что отчёт сформирован, а не что текстовые функции
готовы. Потребитель проверяет `text_capabilities` и `replacement_blockers`.

Запросы D-Bus ограничены 750 ms каждый. Подключение — отдельный ограниченный
этап, остальные запросы идут одновременно; номинальный бюджет двух этапов
1.5 s, без realtime гарантии ОС. Каждый запуск читает новые данные, не хранит
последний удачный focus/layout/unlocked. Ошибки нормализованы без печати тел
D-Bus-сообщений. Не читаются текст, clipboard, заголовки окон или имена приложений.
Ни input devices, ни helper для doctor не нужны.

В `typetune-core::session` добавлены `Knowledge`, `Capability`, `ContextSnapshot`
и список причин отказа для строгого keymap-inferred профиля. Отдельно проверяются
фокус, lock, sensitivity, selection, composition, layout, Unicode, epoch и возраст
снимка. `Limited` и `Unknown` не равны `Available`. Пустая раскладка не является
известной. Future timestamps и возраст на границе deadline отвергаются.

Этот preflight не исполнитель замены и не разрешение редактировать: ещё нужны
проверка ожидаемого суффикса, modifiers/origin, план, generation источника и защита
от interleaving. Пока guard используется диагностикой; text engine не подключён.
Документированный screen-shield `false` намеренно не превращается в `unlocked=true`:
это не доказательство владения активной сессией и безопасности поля.

## Живой GNOME: что установлено

Ubuntu 26.04.1 LTS, kernel `7.0.0-31-generic`, GNOME Shell 50.1,
`XDG_SESSION_TYPE=wayland`, `XDG_CURRENT_DESKTOP=ubuntu:GNOME`,
`WAYLAND_DISPLAY=wayland-0`, `DISPLAY=:0`. Rust/Cargo 1.98.1.
`xdg-desktop-portal` 1.21.1+ds-1ubuntu3, GNOME backend 50.0-0ubuntu1.
GTK/Qt/browser test application в этом срезе не запускалось.

Сохранён [фактический отчёт CLI](evidence/24-gnome-session-probe.json).

| Case / источник | Наблюдение | Что НЕ следует из этого |
|---|---|---|
| SES-NATIVE-01 / session bus | Подключение успешно; ShellVersion = 50.1 | Готовность text backend |
| SES-NATIVE-02 / ScreenSaver.GetActive | `false` при probe | Проверенные lock/unlock transitions, active-session ownership или безопасное поле |
| SES-NATIVE-03 / portal version | RemoteDesktop = 2, InputCapture = 1, GlobalShortcuts = 1 | Разрешение, успешный Start, события или доставка Unicode |
| SES-NATIVE-04 / environment | Wayland и DISPLAY существуют одновременно | X11 API видит native Wayland focus/layout |
| SES-NATIVE-05 / installed schema | `input-sources.current` явно deprecated/ignored | `uint32 0` определяет текущую раскладку |
| SES-NATIVE-06 / gsettings | Configured sources us/ru, per-window=false | Текущая XKB group, работа переключения или поддержка per-window |

Для SES-NATIVE-05 проверен установленный файл
`/usr/share/glib-2.0/schemas/org.gnome.desktop.input-sources.gschema.xml`.
Существующий `LayoutManager` создаёт локальную статическую карту `us,ru`, не читает
compositor state и не используется новым адаптером как источник активной раскладки.
GNOME Shell Eval не используется.

Наличие интерфейса RemoteDesktop проверяется отдельно от пользовательского
разрешения и запуска сессии: это разные этапы
[официального API](https://flatpak.github.io/xdg-desktop-portal/docs/doc-org.freedesktop.portal.RemoteDesktop.html).
Обычный wl_keyboard относится к фокусу клиента и не доказывает глобальное фоновое
наблюдение за чужим приложением:
[спецификация Wayland](https://wayland.freedesktop.org/docs/html/apa.html#protocol-spec-wl_keyboard).
Эти ограничения согласованы с архитектурой 13, а не обходятся статической картой.

## Проверки кода и отказов

Перед добавлением doctor воспроизведён отказ команды (exit 2: неизвестная команда),
в том числе с независимым config path. После реализации два integration tests
запускают настоящий CLI: missing config + missing bus и некорректный TOML.
Оба получают валидный JSON и запрет текстовой замены.

| Case | Уровень | Результат |
|---|---|---|
| SES-GUARD-01 | Unit | Каждое неизвестное поле контекста отдельно запрещает замену |
| SES-GUARD-02 | Unit | Известные lock/sensitive/selection/composition тоже запрещают замену |
| SES-GUARD-03 | Unit, fake clock | Истечение 100 ms, future timestamp, смена epoch отклоняются |
| SES-GUARD-04 | Unit | Unicode Limited/Unknown/Unavailable не разрешает удаление |
| SES-PROBE | Unit | DISPLAY и portal version не дают capability; timeout с виртуальным временем и AccessDenied остаются ошибками |
| SES-CLI | Integration, настоящий CLI | 2 tests: missing/malformed config не блокируют doctor, недоступная шина не даёт fallback |
| SES-BUS-01 | Private D-Bus fixture | Типизированные ответы и отсутствующий интерфейс; версия portal не даёт разрешение |
| SES-BUS-02 | Private D-Bus fixture | После успешного GetActive приходит AccessDenied: unlocked остаётся Unknown |
| SES-BUS-03 | Private D-Bus fixture | Зависший метод завершается timeout; весь probe укладывается в 2 s стендового допуска |
| SES-BUS-04 | Private D-Bus fixture | Имя сервиса освобождено: следующий запрос не использует старую версию/identity |
| Workspace | Unit + integration | 82 unit tests + 2 CLI integration tests, 0 failed |
| Static/build | Build | Workspace build; Clippy core/session/CLI all-targets с `-D warnings`; fmt/diff check |

Private D-Bus stand — **синтетические сервисы**, не native acceptance отказа
GNOME или отзыва portal permission. Его конфиг не содержит activation directories,
поэтому desktop services не запускаются в тестовой шине. Воспроизведение:

```sh
cargo test --workspace --offline
cargo build -p typetune-session --example probe_stand --offline
dbus-run-session --config-file crates/typetune-session/examples/private-bus.conf -- env TYPETUNE_PRIVATE_SESSION_STAND=1 target/debug/examples/probe_stand
cargo build --workspace --offline
cargo clippy -p typetune-core -p typetune-session -p typetune-cli --all-targets --offline -- -D warnings
```

## Оставшиеся работы

G2B не закрыт. Доказана возможность ограниченного чтения metadata, а не наблюдения
текста или безопасной замены в приложениях. Не проверены native lock/unlock,
logout/suspend, grant/deny/revoke portal-сессии, layout switching, IME и Unicode.
KDE, X11 и XWayland-приложения в этом срезе не принимались.

Следующий конкретный срез для GNOME: отдельная compositor integration с политикой
совместимости для GNOME 50, которая сообщает live input source/keymap generation,
focus identity и lock transitions. Даже эти сведения не дают автоматически
selection/sensitivity/composition текстового поля: потребуется отдельная интеграция
с контролируемым редактором или проверенный app adapter. Затем — Unicode range
backend и один статический сниппет G3 с проверкой содержимого и каретки.

Пока эти возможности не подтверждены, daemon по-прежнему разрешает только physical
relay; doctor не включает legacy corrector/snippets и не меняет effective config.
