# TypeTune

> Общесистемная коррекция раскладки русский ↔ английский, сниппеты и необязательный антидребезг клавиш.

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![CI](https://img.shields.io/badge/CI-Linux%20%2B%20macOS-success)](https://github.com/kartamyshev-dev/TypeTune/actions)
[![Release](https://img.shields.io/badge/release-pre--release-orange)](https://github.com/kartamyshev-dev/TypeTune/releases)

**[English](README.md)**

TypeTune исправляет текст, набранный не в той раскладке (например, `ghbdtn` → `привет`), переключает источник ввода, раскрывает сниппеты и может гасить дребезг клавиатуры на Linux.

## Статус

| Платформа | Канал | Артефакт |
|---|---|---|
| Linux (Ubuntu 26.04 / GNOME 50 / Wayland, amd64) | Preview | `.deb` |
| macOS (Apple Silicon, macOS 27) | Preview | `.zip` (ad-hoc подпись, без notarization) |
| Windows | — | Не выпускается |

Preview пригоден для ежедневной работы, но **не** гарантирует поведение в каждом приложении. Что проверяет CI, а что проверяется вручную — в [docs/testing.md](docs/testing.md).

## Возможности

- **Double Shift** — перевод последнего слова `RU ↔ EN` и смена источника ввода; повтор переключает обратно
- **Автокоррекция на пробеле** — частотные словари RU/EN; короткие слова и «кодовые» токены — консервативно
- **Сниппеты** — триггер и разделитель, Unicode-замены
- **Выученные слова** и **исключения** — уточнение или запрет правок без ручного редактирования файлов
- **Исключения приложений** — отключить авто-правку в выбранных программах (жест остаётся)
- **Строка меню** — пауза, флаг раскладки (`EN` / `RU` / `?`), необязательный звук переключения (macOS)
- **Антидребезг** (Linux, opt-in, для выбранного устройства)

## Скриншоты

| Настройки | Строка меню |
|---|---|
| ![Settings](docs/assets/screenshots/settings.png) | ![Menu](docs/assets/screenshots/menu.png) |

> Пока это заглушки — перед релизом можно заменить реальными снимками.

## Установка

### Linux (`.deb`)

1. Скачайте `.deb` из [Releases](https://github.com/kartamyshev-dev/TypeTune/releases).
2. Установите через APT или `dpkg` (не через GNOME Software для локального файла).
3. Запустите **TypeTune Setup** из меню приложений и подтвердите доступ к устройствам.
4. Выйдите из сеанса и войдите снова, чтобы загрузился session helper.

Подробнее: [docs/install.md](docs/install.md)

### macOS (`.zip`)

1. Скачайте `TypeTune-macos-arm64.zip` из Releases.
2. Распакуйте и перенесите `TypeTune.app` в `~/Applications`.
3. Откройте приложение и выдайте **Input Monitoring** и **Accessibility**.

Подробнее: [docs/install.md](docs/install.md)

## Конфиденциальность

История нажатий для коррекции хранится **только в оперативной памяти**. TypeTune не пишет в логи набранные слова и содержимое буфера обмена. Перед паролями и другим чувствительным вводом включайте паузу. Защищённые системные поля пропускаются, когда ОС о них сообщает.

Подробнее: [docs/security-privacy.md](docs/security-privacy.md)

## Ограничения

- Поведение в редакторах, терминалах и разных toolkit может отличаться.
- IME / dead keys / защищённые поля поддерживаются ограниченно.
- По умолчанию пара раскладок — стандартные US ↔ Русская (ПК).

См. [docs/user-guide.md](docs/user-guide.md).

## Документация

| Документ | Тема |
|---|---|
| [docs/overview.md](docs/overview.md) | Обзор продукта и границы |
| [docs/install.md](docs/install.md) | Установка и разрешения |
| [docs/user-guide.md](docs/user-guide.md) | Повседневное использование |
| [docs/architecture.md](docs/architecture.md) | Как устроено |
| [docs/development.md](docs/development.md) | Сборка из исходников |
| [docs/testing.md](docs/testing.md) | CI и ручные проверки |
| [docs/security-privacy.md](docs/security-privacy.md) | Безопасность и приватность |
| [docs/troubleshooting.md](docs/troubleshooting.md) | Типовые проблемы |

## Разработка

```sh
# Linux (как в CI)
rustup toolchain install 1.98.1
cargo test --workspace --all-targets --locked

# macOS (как в CI)
rustup toolchain install 1.89.0
bash scripts/test-macos.sh
bash scripts/build-macos.sh
```

См. [docs/development.md](docs/development.md) и [CONTRIBUTING.md](CONTRIBUTING.md).

## Лицензия

[MIT](LICENSE)

Частотные списки слов для ранжирования распространяются на собственных условиях (CC BY-SA 4.0 / CC BY 2.5); атрибуция вкладывается в состав приложения (`frequency-attribution`).
