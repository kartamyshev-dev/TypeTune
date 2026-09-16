# TypeTune — обзор проекта и документации

## Текущий статус — 2026-09-16

Linux preview для GNOME 50 / Wayland: Double Shift с повторным переключением
слова и раскладки, консервативная автокоррекция на пробеле, controller и установка.
Два режима: opt-in evdev/uinput compatibility и ограниченный IBus/AT-SPI профиль.
Compatibility не ограничен списком приложений, но не подтверждает текст/selection/
sensitivity/composition. Работа во всех существующих приложениях не гарантируется.

Пользователь подтвердил работу в браузере после исправления evdev latency.
Повторный жест проверен в изолированных Wayland/XWayland fixtures.

- [Руководство](35-user-test.md)
- [Последний checkpoint 52 — GitHub Releases](52-github-releases.md)
- [Сводный протокол и границы доказательств](17-validation-record.md)
- [Оставшаяся работа](18-linux-completion-plan.md)

## Исторический baseline

Обновлено 2026-09-10 по исходникам `8cc19d0`. Цель: помощник ввода для Linux, Windows и macOS с коррекцией раскладки, сниппетами и доступным на конкретной платформе физическим фильтром клавиш.

## Результат исследования

Подход к реализации нужно изменить. Текущий единственный pipeline смешивает физический транспорт и текстовое редактирование, хотя у них разные источники состояния, требования к задержке и способы отказа. Недостаток тестов позволил попасть в код ошибкам keycode, repeat, shutdown и взаимоисключающим правилам буферизации/удаления.

Сохранить Rust и модульность. Переработать контракты событий, выделить text engine с планами замены и независимый Linux anti-chatter helper. Заимствовать у Espanso принципы разделения detector, matcher и executor, затем проверить собственные гарантии в TypeTune.

Актуальная цель и следующий этап: [общесистемный переключатель](30-systemwide-product-direction.md).

Текущий checkpoint реализации: [36 — Double Shift, автокоррекция и межприложенческий профиль](36-auto-shift-checkpoint.md).
Таблица ниже описывает baseline, а не статус последующих исправлений.

## Фактическая готовность

| Область | Состояние на baseline | Что нужно для готовности |
|---|---|---|
| Portable crates | Сборка выбранных библиотек на macOS прошла, существующих тестов нет | Contract tests + CI Linux/macOS/Windows |
| Linux input/output | Реализован raw evdev/uinput путь с P0/P1 дефектами | Identity, lifecycle, resync, hotplug и fault tests |
| Layout/text bridge | `LayoutManager` не подключён; `character=None` | Живой platform state и достоверность text observations |
| Corrector/snippets | Есть алгоритмы; daemon не передаёт им текст; latent defects воспроизведены | Новая модель истории, Unicode executor, guards |
| Словари | 10K строк на язык, качество/происхождение не подтверждены | Provenance, curated corpus, negative cases |
| Config/UI/tray | Заготовки; reload расходится с effective state | Один controller, atomic apply, visible errors |
| Linux X11 | Native acceptance не выполнялась | Отдельный профиль и live результаты |
| GNOME/KDE Wayland | Реальные возможности ещё не измерены | Ранний capability prototype по desktop-ам |
| Windows/macOS приложение | Backend-ов нет | Native adapters, permissions, lifecycle и установка |
| Packaging/CI | Файлы есть; готовность установленного продукта не установлена | Clean package/install/upgrade/remove tests |

Ни одна ОС пока не имеет статуса принятой runtime-платформы. Кроссплатформенная сборка части логики и кроссплатформенная работа приложения — разные milestones.

## Как читать документы

| Документ | Назначение |
|---|---|
| [11 — Linux audit](11-linux-audit.md) | 11 findings о транспорте, событиях, остановке и anti-chatter |
| [12 — Feature audit](12-feature-audit.md) | 16 findings о функциях, ресурсах, GUI, IPC и поставке |
| [13 — Target architecture](13-target-architecture.md) | Контракты компонентов, событий и замены; платформенные стратегии; ADR |
| [14 — Development plan](14-development-plan.md) | Фазы G0–G6, зависимости, тестовая матрица и критерии готовности |
| [15 — Espanso reference](15-espanso-reference.md) | Проверенные ссылки на конкретную upstream revision и переносимые принципы |
| [16 — Product spec](16-product-spec.md) | Поведение ручной/автоматической коррекции, сниппетов, debounce и настроек |
| [17 — Validation record](17-validation-record.md) | Что реально запускалось, результаты, ограничения и точка продолжения |
| [Архив первоначального плана](archive/initial-plan/README.md) | История без статуса действующей инструкции |

Номера 01–10 сохранены как страницы-переадресации для старых ссылок. Источник истины для реализации — 13/14/16; audits 11/12 описывают baseline и сохраняются как свидетельство, а не автоматически обновляемая оценка будущего кода.

## Среда исследования и неизвестные

Аудит выполнялся в `/Users/kartamyshev/Git/TypeTune` на macOS arm64, Rust/Cargo 1.89.0. Живой Linux desktop и периферия не исследовались. Прежний документ называл Ubuntu 26.04.1, ядро 7.0.0-31, Wayland и YICHIP `/dev/input/event9`; это исторические записи, не проверенные текущей задачей.

До реализации нужно установить конкретный Linux-стенд и доступные session APIs, источник качественных словарей, минимальные поддерживаемые версии ОС и подход к GUI после headless прототипов. Эти неизвестные не мешают начать G1 и не оправдывают обещание универсального Wayland API.

## Следующий шаг

Первый срез — regression fixtures и контракты физического/text события, затем identity relay с управляемым выходом. Параллельно — исследование возможностей целевого Wayland desktop. Автоматическую коррекцию и shell-сниппеты не подключать к текущему grab callback после одного исправления offset: этим активируются подтверждённые ошибки следующего слоя.
