# Разработка

## Структура

| Путь | Роль |
|---|---|
| `crates/typetune-engine` | Коррекция, словари, сниппеты, guards |
| `crates/typetune-bridge` | JSON ABI, gesture/history для compatibility |
| `crates/typetune-*` | Транспорт, helper, CLI (Linux) |
| `integrations/macos` | Swift-оболочка и runtime |
| `integrations/app`, `compat`, `gnome`, `gui` | Linux UI, compatibility, session, smoke |
| `scripts/` | Сборка, тесты, версия релиза |
| `packaging/preview/` | Состав `.deb` |

## Toolchain (как в CI)

| Платформа | Rust | Прочее |
|---|---|---|
| Linux | **1.98.1** | Python 3, GTK 4 / libadwaita, Xvfb для smoke |
| macOS | **1.89.0** | Xcode / CLT Swift 6.x, `xcodebuild` |

Расхождение версий Rust между платформами намеренное (версии runner-ов).

## Команды

```sh
# Тесты ядра (любая ОС)
cargo test --locked -p typetune-engine -p typetune-bridge

# Полный Linux workspace (нужны GTK/dev-pkgs)
cargo test --workspace --all-targets --locked
/usr/bin/python3 -m unittest discover -s integrations/app -p 'test_*.py'
/usr/bin/python3 -m unittest discover -s integrations/compat -p 'test_*.py'
/usr/bin/python3 -m unittest discover -s tests/packaging -p 'test_*.py'

# macOS
bash scripts/test-macos.sh
bash scripts/build-macos.sh          # dist/TypeTune.app
bash scripts/build-macos.sh --install  # ~/Applications

# Проверка частотных данных
python3 scripts/verify-frequency-data.py

# Debian preview (нужен Linux + deps из CI)
python3 scripts/build-preview-deb.py --version 0.1.0
```

Точка входа Linux из checkout: `./scripts/typetune-test` (install / gui / pause / …).

## Настройки

- macOS: `~/Library/Application Support/TypeTune/settings.json` (version/generation).
- Linux: см. controller в `integrations/app` (пользовательский словарь, exclusions, apps).

Изменение настройки проходит один controller с подтверждением apply; не обходите его «прямой записью» в UI-коде.

## Стиль

- Rust: `cargo fmt`, `cargo clippy -- -D warnings` — обязательно перед PR.
- Swift: тесты через `scripts/test-macos.sh` (в CLT нужен `-F` к Testing framework).
- Не логировать пользовательский текст и clipboard.

См. также [CONTRIBUTING.md](../CONTRIBUTING.md).
