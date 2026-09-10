# 01 — Настройка окружения разработки

## Цель
Подготовить Ubuntu 26.04 к сборке TypeTune.

## Шаг 1.1: Установка системных зависимостей

```bash
sudo apt update
sudo apt install -y \
  build-essential \
  pkg-config \
  libevdev-dev \
  libudev-dev \
  libxkbcommon-dev \
  libxkbcommon-x11-dev \
  clang \
  git
```

Проверка:
```bash
pkg-config --libs libevdev    # -levdev
pkg-config --libs libudev     # -ludev
pkg-config --libs xkbcommon   # -lxkbcommon
```

## Шаг 1.2: Установка Rust

```bash
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
source $HOME/.cargo/env
rustc --version    # stable
cargo --version
```

## Шаг 1.3: Установка полезных cargo-инструментов

```bash
cargo install cargo-watch    # автопересборка при изменении файлов
cargo install cargo-edit     # cargo add/rm для управления зависимостями
```

## Шаг 1.4: Настройка прав доступа к /dev/input

evdev требует доступ к /dev/input/event*. Два варианта:

### Вариант A: Группа input (рекомендуется)
```bash
sudo usermod -aG input $USER
# Перелогиниться, затем проверить:
groups    # должен быть "input"
ls -la /dev/input/event9
```

### Вариант B: udev rule для конкретного устройства
```bash
# Создать правило:
sudo tee /etc/udev/rules.d/99-typetune.rules << 'EOF'
SUBSYSTEM=="input", ATTRS{name}=="YICHIP Wireless Device", MODE="0660", GROUP="input"
EOF

sudo udevadm control --reload-rules
sudo udevadm trigger
```

## Шаг 1.5: Проверка перехвата ввода

Тестовый скрипт для проверки grab (после установки Rust):

```rust
// test_grab.rs — запускать от пользователя в группе input
use evdev::Device;

fn main() {
    let mut device = Device::open("/dev/input/event9").unwrap();
    println!("Устройство: {}", device.name().unwrap_or("unknown"));
    println!("Поддерживаемые клавиши: {:?}", device.supported_keys());
    device.grab().unwrap();
    println!("Grab активен. Нажмите Ctrl+C для выхода.");
}
```

## Шаг 1.6: Определение текущей раскладки

Wayland: через xkbcommon + compositor keymap.
Проверка текущей раскладки:
```bash
# Для GNOME/Wayland:
gsettings get org.gnome.desktop.input-sources current
gsettings get org.gnome.desktop.input-sources sources
```

## Проверочный лист
- [ ] `pkg-config --libs libevdev` работает
- [ ] `rustc --version` выводит stable
- [ ] Пользователь в группе `input`
- [ ] `/dev/input/event9` доступен на чтение/запись
- [ ] `xkbcommon` компилируется (тестовый проект)
