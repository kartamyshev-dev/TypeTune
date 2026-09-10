# 10 — Сборка deb-пакета

## Цель
Установка TypeTune через `sudo dpkg -i typetune.deb`.

## Шаг 10.1: Структура deb-пакета

```
typetune_0.1.0_amd64.deb
├── usr/
│   ├── bin/
│   │   ├── typetune              # CLI + daemon
│   │   └── typetune-gui          # GUI настроек
│   ├── share/
│   │   ├── applications/
│   │   │   └── typetune.desktop
│   │   ├── icons/hicolor/
│   │   │   ├── 16x16/status/typetune-*.png
│   │   │   ├── 24x24/status/typetune-*.png
│   │   │   └── scalable/typetune-*.svg
│   │   └── typetune/
│   │       └── dict/
│   │           ├── ru.txt
│   │           └── en.txt
│   └── lib/systemd/user/
│       └── typetune.service
├── etc/
│   └── typetune/
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
Package: typetune
Version: 0.1.0
Section: utils
Priority: optional
Architecture: amd64
Depends: libgtk-4-1 (>= 4.0), libadwaita-1-0 (>= 1.0), libevdev2, libudev1, libxkbcommon0
Recommends: libappindicator3-1
Maintainer: Kartamyshev <kartamyshev-dev@github.com>
Description: Keyboard daemon with layout correction, anti-chatter and snippets
 TypeTune is a lightweight keyboard daemon that provides:
  - Automatic RU/EN layout correction (ghbdtn → привет)
  - Hardware key chatter filtering for mechanical keyboards
  - Text snippet expansion
  - System tray integration with GTK4 settings GUI
Homepage: https://github.com/kartamyshev-dev/TypeTune
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
        mkdir -p /etc/typetune

        # Перезагрузить systemd
        systemctl daemon-reload 2>/dev/null || true

        echo ""
        echo "=== TypeTune установлен ==="
        echo "1. Перелогиньтесь для применения группы input"
        echo "2. Запустите: systemctl --user enable --now typetune"
        echo "3. Или: typetune daemon"
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
        systemctl --user stop typetune.service 2>/dev/null || true
        systemctl --user disable typetune.service 2>/dev/null || true
        ;;
esac
```

### DEBIAN/conffiles
```
/etc/typetune/config.toml
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
    ["target/release/typetune", "usr/bin/", "755"],
    ["target/release/typetune-gui", "usr/bin/", "755"],
    # Десктоп-файл
    ["packaging/typetune.desktop", "usr/share/applications/", "644"],
    # Иконки
    ["resources/icons/hicolor/16x16/status/*.png", "usr/share/icons/hicolor/16x16/status/", "644"],
    ["resources/icons/hicolor/24x24/status/*.png", "usr/share/icons/hicolor/24x24/status/", "644"],
    ["resources/icons/hicolor/scalable/*.svg", "usr/share/icons/hicolor/scalable/", "644"],
    # Словари
    ["dict/ru.txt", "usr/share/typetune/dict/", "644"],
    ["dict/en.txt", "usr/share/typetune/dict/", "644"],
    # Конфиг
    ["config/default.toml", "etc/typetune/config.toml", "644"],
    # Systemd service
    ["packaging/typetune.service", "usr/lib/systemd/user/", "644"],
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
ls -la target/debian/typetune_*.deb
dpkg-deb --info target/debian/typetune_*.deb
dpkg-deb --contents target/debian/typetune_*.deb
```

## Шаг 10.4: Альтернативная сборка (Makefile)

```makefile
.PHONY: build deb install clean

build:
	cargo build --release

deb: build
	cargo deb --no-build

install: deb
	sudo dpkg -i target/debian/typetune_*.deb

clean:
	cargo clean
	rm -rf target/debian/

uninstall:
	sudo dpkg -r typetune

test-deb:
	dpkg-deb --info target/debian/typetune_*.deb
	dpkg-deb --contents target/debian/typetune_*.deb
	lintian target/debian/typetune_*.deb || true
```

## Шаг 10.5: Путь установки

| Файл | Путь |
|---|---|
| Бинарник daemon | `/usr/bin/typetune` |
| Бинарник GUI | `/usr/bin/typetune-gui` |
| Конфиг | `/etc/typetune/config.toml` |
| Словари | `/usr/share/typetune/dict/{ru,en}.txt` |
| Иконки | `/usr/share/icons/hicolor/*/status/typetune-*.png` |
| Десктоп-файл | `/usr/share/applications/typetune.desktop` |
| Systemd unit | `/usr/lib/systemd/user/typetune.service` |

## Шаг 10.6: Установка и удаление

```bash
# Установка
sudo dpkg -i typetune_0.1.0_amd64.deb
sudo apt-get install -f  # если не хватает зависимостей

# Проверка
typetune version
typetune list-devices

# Включить автозапуск
systemctl --user enable --now typetune

# Удаление
sudo dpkg -r typetune
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
