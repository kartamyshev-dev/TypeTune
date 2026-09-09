# TuneType — Обзор проекта

## Описание
Универсальный фоновый демон для перехвата и обработки клавиатурного ввода.
Автокоррекция раскладки (RU/EN), антидребезг, текстовые сниппеты.

Устанавливается deb-пакетом. Имеет графический интерфейс настроек и иконку в системном трее.

## Целевая среда
- **ОС:** Ubuntu 26.04.1 LTS, ядро 7.0.0-31
- **Дисплей:** Wayland (wayland-0) + XWayland (:0)
- **Клавиатура:** YICHIP Wireless Device → /dev/input/event9
- **Язык:** Rust (stable)
- **GUI:** GTK4 + libadwaita (native для GNOME)
- **Трей:** libappindicator / StatusNotifierItem (SNI)
- **Формат конфига:** TOML
- **Дистрибуция:** deb-пакет

## Архитектура (Pipeline)

Каждое событие клавиатуры проходит через цепочку этапов:

```
[evdev grab] → InputEvent → Pipeline:
  1. AntiChatter      — фильтрация дребезга
  2. LayoutCorrector   — автокоррекция раскладки
  3. SnippetExpander   — раскрытие сниппетов
  4. TypographyEngine  — типографские замены
→ [uinput emit] → виртуальная клавиатура → приложение
```

Каждый этап — отдельный crate с трейтом `PipelineStage`:

```rust
pub trait PipelineStage {
    fn process(&mut self, event: InputEvent) -> Vec<InputEvent>;
    fn name(&self) -> &str;
}
```

## Cargo Workspace

```
tunetype/
├── Cargo.toml                    # [workspace]
├── crates/
│   ├── tunetype-core/            # типы событий, трейты, pipeline
│   ├── tunetype-input/           # evdev перехват (grab)
│   ├── tunetype-inject/          # uinput виртуальное устройство
│   ├── tunetype-layout/          # xkbcommon маппинг
│   ├── tunetype-corrector/       # автокоррекция RU↔EN
│   ├── tunetype-chatter/         # антидребезг
│   ├── tunetype-snippets/        # текстовые сниппеты
│   ├── tunetype-config/          # TOML-конфиг
│   ├── tunetype-tray/            # иконка в трее + контекстное меню
│   ├── tunetype-gui/             # GTK4 графический интерфейс настроек
│   └── tunetype-cli/             # бинарник, CLI + daemon + tray + GUI
├── config/
│   └── default.toml              # конфиг по умолчанию
├── dict/
│   ├── ru.txt                    # словарь RU (топ-10K слов)
│   └── en.txt                    # словарь EN (топ-10K слов)
├── packaging/
│   ├── deb/                      # debian-пакет (control, postinst, systemd)
│   └── Makefile                  # сборка deb через cargo-deb или dpkg-buildpackage
└── docs/                         # документация
```

## Зависимости

### Rust-крейты
| Крейт | Версия | Назначение |
|---|---|---|
| evdev | 0.13 | Чтение input-устройств + uinput |
| xkbcommon | 0.9 | Маппинг keycode → символ (Wayland/X11) |
| tokio | 1.x | Async runtime |
| clap | 4.x | CLI-парсер |
| serde | 1.x | Сериализация конфига |
| toml | 0.8 | Парсинг TOML |
| tracing | 0.1 | Логирование |
| tracing-subscriber | 0.3 | Подписчик логов |
| signal-hook | 0.3 | Обработка сигналов (SIGTERM, SIGHUP) |
| udev | 0.9 | Поиск input-устройств |
| gtk4 | 0.9 | GTK4 bindings для GUI |
| libadwaita | 0.7 | GNOME HIG виджеты |
| ksni | 0.2 | StatusNotifierItem (трей, D-Bus) |
| zbus | 4.x | D-Bus IPC (для IPC между daemon и GUI) |

### Системные пакеты (apt)
| Пакет | Назначение |
|---|---|
| build-essential | gcc, g++, make |
| pkg-config | Поиск .pc файлов |
| libevdev-dev | Заголовки evdev |
| libudev-dev | Заголовки udev |
| libxkbcommon-dev | Заголовки xkbcommon |
| libxkbcommon-x11-dev | X11 расширение xkbcommon |
| clang | Компилятор (для bindgen) |
| libgtk-4-dev | GTK4 dev-библиотеки |
| libadwaita-1-dev | libadwaita dev-библиотеки |
| cargo-deb | Сборка deb-пакетов из Cargo |

### Инструменты сборки
| Инструмент | Назначение |
|---|---|
| cargo-deb | `cargo deb` — сборка .deb из Cargo.toml метаданных |
| dpkg-deb | Проверка собранного .deb |

## Текущий статус
- [x] Git-репозиторий инициализирован
- [x] Remote: https://github.com/kartamyshev-dev/tunetype.git
- [ ] Rust toolchain
- [ ] Системные dev-пакеты
- [ ] Структура проекта
- [ ] Исходный код
