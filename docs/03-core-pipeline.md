# 03 — Core Pipeline: evdev → pipeline → uinput

## Цель
Перехват клавиатуры, обработка через pipeline, инжект в виртуальное устройство.

## Шаг 3.1: tunetype-input — evdev перехватчик

### Cargo.toml
```toml
[package]
name = "tunetype-input"
version.workspace = true
edition.workspace = true

[dependencies]
tunetype-core = { path = "../tunetype-core" }
evdev = "0.13"
udev = "0.9"
tracing = "0.1"
```

### src/lib.rs — InputSource trait
```rust
pub mod evdev_source;
pub mod device_discovery;

pub trait InputSource {
    fn run(&mut self, callback: Box<dyn Fn(tunetype_core::event::InputEvent) + Send>) -> Result<(), Box<dyn std::error::Error>>;
    fn stop(&mut self);
}
```

### src/device_discovery.rs — Поиск клавиатур

Логика:
1. `udev::Enumerator::new()` → scan subsystem "input"
2. Фильтр: атрибут `capabilities/ev` содержит `EV_KEY` (бит 1)
3. Проверка: `supported_keys()` включает `KEY_A`..`KEY_Z`
4. Исключить: мыши, тачпады, кнопки питания

```rust
pub fn discover_keyboards(exclude_names: &[String]) -> Vec<(String, String)> {
    // Vec<(path, name)>
    // Перебрать /dev/input/event*, отфильтровать по EV_KEY + KEY_A
    // Исключить устройства по имени из exclude_names
    vec![]
}
```

### src/evdev_source.rs — Основной event loop

```rust
use evdev::Device;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;

pub struct EvdevSource {
    devices: Vec<Device>,
    running: Arc<AtomicBool>,
}

impl EvdevSource {
    pub fn new(device_paths: &[String]) -> Result<Self, Box<dyn std::error::Error>> {
        let devices = device_paths.iter()
            .map(|p| Device::open(p))
            .collect::<Result<Vec<_>, _>>()?;
        Ok(Self { devices, running: Arc::new(AtomicBool::new(false)) })
    }

    pub fn run(&mut self, callback: Box<dyn Fn(InputEvent) + Send>) {
        // 1. Grab все устройства
        for device in &mut self.devices {
            device.grab().expect("Failed to grab device");
        }
        self.running.store(true, Ordering::SeqCst);

        // 2. Event loop: fetch_events() → convert → callback
        // 3. Конвертация evdev::InputEvent → tunetype_core::InputEvent
        // 4. Вызов callback
    }

    pub fn ungrab_all(&mut self) {
        for device in &mut self.devices {
            let _ = device.ungrab();
        }
    }
}
```

Конвертация событий:
```rust
fn convert_event(ev: evdev::InputEvent) -> Option<InputEvent> {
    match ev.destructure() {
        evdev::EventSummary::Key(_, keycode, state) => {
            let key_state = if state == 1 { KeyState::Pressed } else { KeyState::Released };
            Some(InputEvent::new(keycode.code(), key_state))
        }
        _ => None,
    }
}
```

## Шаг 3.2: tunetype-inject — uinput виртуальное устройство

### Cargo.toml
```toml
[package]
name = "tunetype-inject"
version.workspace = true
edition.workspace = true

[dependencies]
tunetype-core = { path = "../tunetype-core" }
evdev = "0.13"
tracing = "0.1"
```

### src/lib.rs
```rust
use evdev::uinput::VirtualDeviceBuilder;
use evdev::{AttributeSet, KeyCode, InputEvent as EvdevInputEvent, EventType, SynchronizationCode};
use tunetype_core::event::{InputEvent, KeyState};

pub struct VirtualKeyboard {
    device: evdev::uinput::VirtualDevice,
}

impl VirtualKeyboard {
    pub fn new() -> Result<Self, Box<dyn std::error::Error>> {
        let mut keys = AttributeSet::<KeyCode>::new();
        for code in 0..248u16 {
            if let Ok(kc) = KeyCode::new(code) {
                keys.insert(kc);
            }
        }

        let device = VirtualDeviceBuilder::new()?
            .name("TuneType Virtual Keyboard")
            .with_keys(&keys)?
            .build()?;

        Ok(Self { device })
    }

    pub fn emit(&self, event: &InputEvent) -> Result<(), Box<dyn std::error::Error>> {
        let state_code = match event.state {
            KeyState::Pressed => 1u32,
            KeyState::Released => 0u32,
        };
        let ev = EvdevInputEvent::new(EventType::KEY, event.keycode, state_code);
        self.device.emit(&[ev])?;
        Ok(())
    }

    pub fn emit_syn(&self) -> Result<(), Box<dyn std::error::Error>> {
        let ev = EvdevInputEvent::new(EventType::SYN, SynchronizationCode::SYN_REPORT.code(), 0);
        self.device.emit(&[ev])?;
        Ok(())
    }
}
```

## Шаг 3.3: tunetype-cli — Сборка pipeline (скелет)

### src/main.rs
```rust
use tunetype_core::pipeline::Pipeline;

fn main() {
    // 1. Инициализация логирования (tracing)
    // 2. Обнаружение устройств
    // 3. Создание VirtualKeyboard
    // 4. Создание Pipeline (пока пустой — identity)
    // 5. Event loop:
    //    evdev_source.run(Box::new(|event| {
    //        let processed = pipeline.process(event);
    //        for e in processed { virtual_keyboard.emit(&e); }
    //    }));
}
```

## Шаг 3.4: tokio-based event loop (финальная версия)

```rust
use tokio::signal;

#[tokio::main]
async fn main() {
    let devices = discover_keyboards(&[]);
    let mut streams: Vec<_> = devices.into_iter()
        .map(|(path, _)| {
            let d = evdev::Device::open(&path).unwrap();
            d.into_event_stream().unwrap()
        })
        .collect();

    loop {
        tokio::select! {
            Some(event) = streams[0].next_event() => { /* process */ }
            _ = signal::ctrl_c() => { break; }
        }
    }
}
```

## Шаг 3.5: Тестирование

### Ручной тест
1. Запустить `cargo run --bin tunetype -- daemon`
2. Нажать клавиши — проверить прохождение через pipeline
3. Проверить что оригинальный ввод подавляется (grab)
4. Проверить что виртуальное устройство генерирует события

### Проверка uinput устройства
```bash
cat /proc/bus/input/devices | grep -A 5 "TuneType"
evtest  # найти виртуальное устройство
```

## Проверочный лист
- [ ] Устройства обнаруживаются автоматически (udev scan)
- [ ] evdev grab работает без ошибок
- [ ] Клавиши перехватываются (оригинальный ввод не доходит до приложений)
- [ ] Virtual keyboard создаётся в системе
- [ ] Нажатия клавиш проходят pipeline и инжектятся
- [ ] Ctrl+C корректно завершает демон (ungrab + drop device)
