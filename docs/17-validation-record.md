# Протокол исследования и точка продолжения

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
