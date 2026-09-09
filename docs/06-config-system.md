# 06 — Config System

## Цель
Единый TOML-конфиг с hot-reload.

## Шаг 6.1: Структура конфига

### config/default.toml
```toml
[general]
log_level = "info"
pid_file = "/tmp/tunetype.pid"

[input]
discovery = "auto"
device_paths = []
exclude_names = ["Power Button", "Sleep Button"]

[corrector]
enabled = true
min_word_length = 3
layouts = ["us", "ru"]
dict_dir = "~/.config/tunetype/dict/"
exclude_classes = ["Alacritty", "kitty", "Code"]
exclude_titles = []

[chatter]
enabled = true
debounce_ms = 50
modifier_debounce_ms = 30

[snippets]
enabled = true
trigger_prefix = ":"
word_separators = [" ", "\t", "\n", "\r"]

[snippets.entries]
# date = "{{date}}"
# time = "{{time}}"
# docker = "docker run -it --rm -v $(pwd):/app -w /app"

[typography]
enabled = false
smart_quotes = true
em_dash = true
```

## Шаг 6.2: tunetype-config crate

### Cargo.toml
```toml
[package]
name = "tunetype-config"
version.workspace = true
edition.workspace = true

[dependencies]
tunetype-core = { path = "../tunetype-core" }
serde = { version = "1", features = ["derive"] }
toml = "0.8"
tracing = "0.1"
dirs = "5"
```

### src/lib.rs
```rust
use serde::Deserialize;
use std::path::PathBuf;

#[derive(Debug, Deserialize)]
pub struct Config {
    pub general: GeneralConfig,
    pub input: InputConfig,
    pub corrector: CorrectorConfig,
    pub chatter: ChatterConfig,
    pub snippets: SnippetsConfig,
    pub typography: TypographyConfig,
}

#[derive(Debug, Deserialize)]
pub struct GeneralConfig {
    pub log_level: String,
    pub pid_file: PathBuf,
}

#[derive(Debug, Deserialize)]
pub struct InputConfig {
    pub discovery: String,
    pub device_paths: Vec<String>,
    pub exclude_names: Vec<String>,
}

#[derive(Debug, Deserialize)]
pub struct CorrectorConfig {
    pub enabled: bool,
    pub min_word_length: usize,
    pub layouts: Vec<String>,
    pub dict_dir: String,
    pub exclude_classes: Vec<String>,
    pub exclude_titles: Vec<String>,
}

#[derive(Debug, Deserialize)]
pub struct ChatterConfig {
    pub enabled: bool,
    pub debounce_ms: u64,
    pub modifier_debounce_ms: u64,
}

#[derive(Debug, Deserialize)]
pub struct SnippetsConfig {
    pub enabled: bool,
    pub trigger_prefix: String,
    pub word_separators: Vec<String>,
    pub entries: std::collections::HashMap<String, String>,
}

#[derive(Debug, Deserialize)]
pub struct TypographyConfig {
    pub enabled: bool,
    pub smart_quotes: bool,
    pub em_dash: bool,
}
```

### src/loader.rs
```rust
use std::path::PathBuf;

pub fn config_path() -> PathBuf {
    dirs::config_dir()
        .unwrap_or_else(|| PathBuf::from("/etc"))
        .join("tunetype")
        .join("config.toml")
}

pub fn load(path: &PathBuf) -> Result<Config, Box<dyn std::error::Error>> {
    let content = std::fs::read_to_string(path)?;
    let config: Config = toml::from_str(&content)?;
    Ok(config)
}

pub fn ensure_config_exists() -> PathBuf {
    let path = config_path();
    if !path.exists() {
        std::fs::create_dir_all(path.parent().unwrap()).unwrap();
        std::fs::write(&path, include_str!("../../config/default.toml")).unwrap();
        tracing::info!("Created default config at {}", path.display());
    }
    path
}
```

## Шаг 6.3: Hot-reload (SIGHUP)

```rust
use signal_hook::iterator::Signals;
use std::sync::{Arc, Mutex};

let config = Arc::new(Mutex::new(load_config()));

let config_clone = config.clone();
std::thread::spawn(move || {
    let mut signals = Signals::new([libc::SIGHUP]).unwrap();
    for _ in signals.forever() {
        match load(&config_path()) {
            Ok(new_config) => {
                *config_clone.lock().unwrap() = new_config;
                tracing::info!("Config reloaded");
            }
            Err(e) => {
                tracing::error!("Failed to reload config: {}", e);
            }
        }
    }
});
```

## Шаг 6.4: XDG-пути

| Приоритет | Путь |
|---|---|
| 1. CLI flag | `--config /path/to/config.toml` |
| 2. XDG | `$XDG_CONFIG_HOME/tunetype/config.toml` |
| 3. Default | `~/.config/tunetype/config.toml` |
| 4. System | `/etc/tunetype/config.toml` |

## Проверочный лист
- [ ] Конфиг загружается из XDG-пути
- [ ] TOML парсится без ошибок
- [ ] SIGHUP перезагружает конфиг
- [ ] Дефолтный конфиг создаётся при первом запуске
