# 08 — CLI и Daemon Management

## Цель
Удобный CLI для управления демоном.

## Шаг 8.1: CLI на clap

### typetune-cli/Cargo.toml
```toml
[package]
name = "typetune-cli"
version.workspace = true
edition.workspace = true

[[bin]]
name = "typetune"
path = "src/main.rs"

[dependencies]
typetune-core = { path = "../typetune-core" }
typetune-input = { path = "../typetune-input" }
typetune-inject = { path = "../typetune-inject" }
typetune-layout = { path = "../typetune-layout" }
typetune-corrector = { path = "../typetune-corrector" }
typetune-chatter = { path = "../typetune-chatter" }
typetune-snippets = { path = "../typetune-snippets" }
typetune-config = { path = "../typetune-config" }
clap = { version = "4", features = ["derive"] }
tracing = "0.1"
tracing-subscriber = "0.3"
signal-hook = "0.3"
```

### src/main.rs
```rust
use clap::{Parser, Subcommand};
use std::path::PathBuf;

#[derive(Parser)]
#[command(name = "typetune", about = "Keyboard daemon: layout correction, anti-chatter, snippets")]
struct Cli {
    #[command(subcommand)]
    command: Commands,
    #[arg(long, global = true)]
    config: Option<PathBuf>,
}

#[derive(Subcommand)]
enum Commands {
    /// Start daemon in foreground
    Daemon,
    /// Start daemon in background
    Start,
    /// Stop running daemon
    Stop,
    /// Show daemon status
    Status,
    /// Show anti-chatter statistics
    Stats,
    /// Config management
    Config {
        #[command(subcommand)]
        action: Option<ConfigAction>,
    },
    /// List detected input devices
    ListDevices,
    /// Reload config (send SIGHUP)
    Reload,
    /// Show version
    Version,
}

#[derive(Subcommand)]
enum ConfigAction {
    /// Show config file path
    Path,
    /// Open config in $EDITOR
    Edit,
}
```

## Шаг 8.2: Daemon mode

```rust
fn daemon_mode(config: Config) {
    // 1. Write PID file
    write_pid_file(&config.general.pid_file);

    // 2. Setup signal handlers (SIGTERM, SIGINT → shutdown, SIGHUP → reload)

    // 3. Discover devices
    let devices = if config.input.discovery == "auto" {
        discover_keyboards(&config.input.exclude_names)
    } else {
        config.input.device_paths.iter().map(|p| (p.clone(), String::new())).collect()
    };

    // 4. Create pipeline
    let mut pipeline = Pipeline::new();

    if config.chatter.enabled {
        pipeline.add_stage(Box::new(AntiChatter::new(
            config.chatter.debounce_ms,
            config.chatter.modifier_debounce_ms,
        )));
    }

    if config.corrector.enabled {
        let dict_dir = PathBuf::from(&config.corrector.dict_dir);
        pipeline.add_stage(Box::new(LayoutCorrector::new(
            Dictionary::load(&dict_dir.join("ru.txt")),
            Dictionary::load(&dict_dir.join("en.txt")),
            config.corrector.min_word_length,
        )));
    }

    if config.snippets.enabled {
        pipeline.add_stage(Box::new(SnippetExpander::from_config(&config.snippets)));
    }

    // 5. Create input source + virtual keyboard
    let mut source = EvdevSource::new(&devices).unwrap();
    let vkb = VirtualKeyboard::new().unwrap();

    // 6. Shared state
    let config_arc = Arc::new(Mutex::new(config));
    let enabled = Arc::new(Mutex::new(true));

    // 7. Запуск tray в отдельном tokio task
    let tray_config = config_arc.clone();
    let tray_enabled = enabled.clone();
    tokio::spawn(async move {
        if let Err(e) = run_tray(tray_config, tray_enabled).await {
            tracing::error!("Tray error: {}", e);
        }
    });

    // 8. IPC D-Bus server
    let ipc_enabled = enabled.clone();
    tokio::spawn(async move {
        if let Err(e) = run_ipc_server(ipc_enabled).await {
            tracing::error!("IPC error: {}", e);
        }
    });

    // 9. Run event loop
    tracing::info!("TypeTune daemon started (PID: {})", std::process::id());
    source.run(Box::new(move |event| {
        if *enabled.lock().unwrap() {
            let events = pipeline.process(event);
            for e in events {
                vkb.emit(&e).ok();
            }
        }
    }));
}
```

## Шаг 8.3: Systemd service

### typetune.service
```ini
[Unit]
Description=TypeTune Keyboard Daemon
After=graphical-session.target
PartOf=graphical-session.target

[Service]
Type=simple
ExecStart=/usr/local/bin/typetune daemon
Restart=on-failure
RestartSec=5
Environment=WAYLAND_DISPLAY=wayland-0
Environment=XDG_RUNTIME_DIR=/run/user/%U

[Install]
WantedBy=default.target
```

Установка:
```bash
mkdir -p ~/.config/systemd/user/
cp typetune.service ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable typetune
systemctl --user start typetune
```

## Шаг 8.4: Graceful shutdown

```rust
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;

let running = Arc::new(AtomicBool::new(true));

let r = running.clone();
signal_hook::flag::register(signal_hook::consts::SIGTERM, r.clone())?;
signal_hook::flag::register(signal_hook::consts::SIGINT, r.clone())?;

while running.load(Ordering::Relaxed) {
    // event processing
}

source.ungrab_all();
remove_pid_file();
tracing::info!("Daemon stopped");
```

## Шаг 8.5: Все CLI-команды

| Команда | Описание |
|---|---|
| `typetune daemon` | Запуск в foreground |
| `typetune start` | Запуск в background |
| `typetune stop` | Остановка демона |
| `typetune status` | Статус (PID, uptime, активные фичи) |
| `typetune stats` | Статистика anti-chatter |
| `typetune config path` | Путь к конфигу |
| `typetune config edit` | Открыть конфиг в $EDITOR |
| `typetune list-devices` | Список обнаруженных устройств |
| `typetune reload` | Перезагрузка конфига (SIGHUP) |
| `typetune version` | Версия |

## Проверочный лист
- [ ] `typetune daemon` запускает в foreground
- [ ] `typetune start` запускает в background
- [ ] `typetune stop` корректно завершает
- [ ] `typetune status` показывает статус
- [ ] `typetune list-devices` показывает клавиатуры
- [ ] PID-файл создаётся и удаляется
- [ ] Systemd service работает
