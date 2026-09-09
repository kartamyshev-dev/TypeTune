# 10 — Сборка deb-пакета

## Цель
Установка TuneType через `sudo dpkg -i tunetype.deb`.

## Шаг 10.1: Структура deb-пакета

```
tunetype_0.1.0_amd64.deb
├── usr/
│   ├── bin/
│   │   ├── tunetype              # CLI + daemon
│   │   └── tunetype-gui          # GUI настроек
│   ├── share/
│   │   ├── applications/
│   │   │   └── tunetype.desktop
│   │   ├── icons/hicolor/
│   │   │   ├── 16x16/status/tunetype-*.png
│   │   │   ├── 24x24/status/tunetype-*.png
│   │   │   └── scalable/tunetype-*.svg
│   │   └── tunetype/
│   │       └── dict/
│   │           ├── ru.txt
│   │           └── en.txt
│   └── lib/systemd/user/
│       └── tunetype.service
├── etc/
│   └── tunetype/
│       └── config.toml           # конфиг по умолчанию
└── DEBIAN/
    ├── control
    ├── postinst
    ├── prerm
    └── conffiles
```

## Шаг 10.2: Метаданные пакета

### DEBIAN/control
```
Package: tunetype
Version: 0.1.0
Section: utils
Priority: optional
Architecture: amd64
Depends: libgtk-4-1 (>= 4.0), libadwaita-1-0 (>= 1.0), libevdev2, libudev1, libxkbcommon0
Recommends: libappindicator3-1
Maintainer: Kartamyshev <kartamyshev-dev@github.com>
Description: Keyboard daemon with layout correction, anti-chatter and snippets
 TuneType is a lightweight keyboard daemon that provides:
  - Automatic RU/EN layout correction (ghbdtn → привет)
  - Hardware key chatter filtering for mechanical keyboards
  - Text snippet expansion
  - System tray integration with GTK4 settings GUI
Homepage: https://github.com/kartamyshev-dev/tunetype
```

### DEBIAN/postinst
```bash
#!/bin/bash
set -e

case "$1" in
    configure)
        # Создать группу input если нет
        getent group input >/dev/null || groupadd input

        # Добавить текущего пользователя в группу input
        if [ -n "$SUDO_USER" ]; then
            usermod -aG input "$SUDO_USER"
        fi

        # Создать директорию конфига
        mkdir -p /etc/tunetype

        # Перезагрузить systemd
        systemctl daemon-reload 2>/dev/null || true

        echo ""
        echo "=== TuneType установлен ==="
        echo "1. Перелогиньтесь для применения группы input"
        echo "2. Запустите: systemctl --user enable --now tunetype"
        echo "3. Или: tunetype daemon"
        echo ""
        ;;
esac
```

### DEBIAN/prerm
```bash
#!/bin/bash
set -e

case "$1" in
    remove|upgrade)
        # Остановить сервис
        systemctl --user stop tunetype.service 2>/dev/null || true
        systemctl --user disable tunetype.service 2>/dev/null || true
        ;;
esac
```

### DEBIAN/conffiles
```
/etc/tunetype/config.toml
```

## Шаг 10.3: Сборка через cargo-deb

### Cargo.toml (workspace root) — метаданные для cargo-deb

```toml
[workspace.metadata.deb]
maintainer = "Kartamyshev <kartamyshev-dev@github.com>"
copyright = "2026 Kartamyshev"
license-file = ["LICENSE", "0"]
extended-description = """\
Keyboard daemon with layout correction, anti-chatter and snippets. \
Provides automatic RU/EN layout switching, hardware key debounce \
for mechanical keyboards, and text snippet expansion."""
section = "utils"
priority = "optional"
depends = "libgtk-4-1 (>= 4.0), libadwaita-1-0 (>= 1.0), libevdev2, libudev1, libxkbcommon0"
assets = [
    # Бинарники
    ["target/release/tunetype", "usr/bin/", "755"],
    ["target/release/tunetype-gui", "usr/bin/", "755"],
    # Десктоп-файл
    ["packaging/tunetype.desktop", "usr/share/applications/", "644"],
    # Иконки
    ["resources/icons/hicolor/16x16/status/*.png", "usr/share/icons/hicolor/16x16/status/", "644"],
    ["resources/icons/hicolor/24x24/status/*.png", "usr/share/icons/hicolor/24x24/status/", "644"],
    ["resources/icons/hicolor/scalable/*.svg", "usr/share/icons/hicolor/scalable/", "644"],
    # Словари
    ["dict/ru.txt", "usr/share/tunetype/dict/", "644"],
    ["dict/en.txt", "usr/share/tunetype/dict/", "644"],
    # Конфиг
    ["config/default.toml", "etc/tunetype/config.toml", "644"],
    # Systemd service
    ["packaging/tunetype.service", "usr/lib/systemd/user/", "644"],
]

[workspace.metadata.deb.systemd]
unit-scripts = "packaging/systemd-units"
enable = false
start = false
```

### Сборка
```bash
# Релизная сборка
cargo build --release

# Сборка deb
cargo deb --no-build

# Проверка
ls -la target/debian/tunetype_*.deb
dpkg-deb --info target/debian/tunetype_*.deb
dpkg-deb --contents target/debian/tunetype_*.deb
```

## Шаг 10.4: Альтернативная сборка (Makefile)

```makefile
.PHONY: build deb install clean

build:
	cargo build --release

deb: build
	cargo deb --no-build

install: deb
	sudo dpkg -i target/debian/tunetype_*.deb

clean:
	cargo clean
	rm -rf target/debian/

uninstall:
	sudo dpkg -r tunetype

test-deb:
	dpkg-deb --info target/debian/tunetype_*.deb
	dpkg-deb --contents target/debian/tunetype_*.deb
	lintian target/debian/tunetype_*.deb || true
```

## Шаг 10.5: Путь установки

| Файл | Путь |
|---|---|
| Бинарник daemon | `/usr/bin/tunetype` |
| Бинарник GUI | `/usr/bin/tunetype-gui` |
| Конфиг | `/etc/tunetype/config.toml` |
| Словари | `/usr/share/tunetype/dict/{ru,en}.txt` |
| Иконки | `/usr/share/icons/hicolor/*/status/tunetype-*.png` |
| Десктоп-файл | `/usr/share/applications/tunetype.desktop` |
| Systemd unit | `/usr/lib/systemd/user/tunetype.service` |

## Шаг 10.6: Установка и удаление

```bash
# Установка
sudo dpkg -i tunetype_0.1.0_amd64.deb
sudo apt-get install -f  # если не хватает зависимостей

# Проверка
tunetype version
tunetype list-devices

# Включить автозапуск
systemctl --user enable --now tunetype

# Удаление
sudo dpkg -r tunetype
```

## Проверочный лист
- [ ] `cargo deb` собирает .deb без ошибок
- [ ] `dpkg-deb --info` показывает корректные метаданные
- [ ] `dpkg-deb --contents` показывает все файлы
- [ ] `sudo dpkg -i` устанавливает без ошибок
- [ ] Зависимости автоматически подтягиваются (`apt-get install -f`)
- [ ] Бинарники в PATH после установки
- [ ] Systemd service корректно регистрируется
- [ ] Десктоп-файл появляется в app grid
- [ ] `dpkg -r` корректно удаляет пакет
