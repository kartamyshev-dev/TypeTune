# TypeTune

Keyboard daemon for Linux (Wayland/X11). Auto-correction of RU/EN layout, key debounce for mechanical keyboards, text snippets.

## Features

- **Layout Correction** — automatically fixes words typed in wrong layout (`ghbdtn` → `привет`, `руддщ` → `hello`)
- **Anti-Chatter** — filters duplicate key presses from mechanical keyboards (configurable debounce window)
- **Text Snippets** — expands triggers into text/commands (`:date` → current date, `:myip` → your IP)
- **System Tray** — icon with context menu (enable/disable, settings, exit)
- **GTK4 Settings GUI** — graphical interface for configuration
- **D-Bus IPC** — daemon communicates with tray and GUI via D-Bus
- **Hot-Reload** — reload config with `SIGHUP` or from GUI without restarting daemon

## Architecture

```
evdev grab → Pipeline → uinput emit

Pipeline stages:
  1. AntiChatter     — key debounce filtering
  2. LayoutCorrector — RU↔EN auto-correction
  3. SnippetExpander — text snippet expansion
```

Each stage is a separate Rust crate implementing the `PipelineStage` trait:

```rust
pub trait PipelineStage: Send {
    fn name(&self) -> &str;
    fn process(&mut self, event: InputEvent) -> Vec<InputEvent>;
    fn reset(&mut self) {}
}
```

### Crate Structure

```
typetune/
├── Cargo.toml                    # workspace root
├── crates/
│   ├── typetune-core/            # InputEvent, PipelineStage trait, Pipeline
│   ├── typetune-input/           # evdev grab, epoll event loop, device discovery
│   ├── typetune-inject/          # uinput virtual keyboard (raw ioctl)
│   ├── typetune-layout/          # xkbcommon keycode→char mapping
│   ├── typetune-corrector/       # RU↔EN layout correction with dictionaries
│   ├── typetune-chatter/         # anti-chatter (per-key debounce)
│   ├── typetune-snippets/        # text snippet expansion
│   ├── typetune-config/          # TOML config with XDG paths
│   ├── typetune-tray/            # system tray icon (ksni/StatusNotifierItem)
│   ├── typetune-gui/             # GTK4 settings window
│   └── typetune-cli/             # binary, CLI + daemon + IPC
├── config/default.toml           # default configuration
├── dict/{ru,en}.txt              # dictionaries (10K words each)
├── packaging/                    # systemd service, desktop file
└── resources/icons/              # SVG icons for tray
```

### Key Implementation Details

- **Input**: Raw evdev via `libc::read()` with `O_NONBLOCK`, epoll for efficient multi-device polling
- **Grab**: `EVIOCGRAB` ioctl to exclusively capture keyboard input
- **Output**: Raw uinput via `libc::write()` to `/dev/uinput` (no evdev crate dependency for injection)
- **IPC**: D-Bus interface `org.typetune.Daemon` via zbus (get_status, set_enabled, get_stats, reload_config)
- **Config**: TOML with hot-reload via SIGHUP signal
- **Cleanup**: `Drop` impl on devices for automatic ungrab, PID file management

## Requirements

### System Packages (Ubuntu/Debian)

```bash
sudo apt install build-essential pkg-config libevdev-dev libudev-dev \
    libxkbcommon-dev libxkbcommon-x11-dev clang libdbus-1-dev \
    libgtk-4-dev libadwaita-1-dev
```

### Permissions

Your user must have access to `/dev/input/event*` devices:

```bash
sudo usermod -aG input $USER
# Log out and back in for the group to take effect
```

### Rust Toolchain

```bash
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
source $HOME/.cargo/env
```

## Installation

### From Source

```bash
git clone https://github.com/kartamyshev-dev/TypeTune.git
cd TypeTune
make build
sudo make install DESTDIR=/
```

### Enable as User Service

```bash
systemctl --user daemon-reload
systemctl --user enable --now typetune
```

## Usage

### CLI Commands

| Command | Description |
|---|---|
| `typetune daemon` | Start daemon in foreground |
| `typetune start` | Start daemon in background |
| `typetune stop` | Stop running daemon |
| `typetune status` | Show daemon status (PID) |
| `typetune stats` | Show anti-chatter statistics |
| `typetune list-devices` | List detected keyboard devices |
| `typetune reload` | Reload config (send SIGHUP) |
| `typetune config path` | Show config file path |
| `typetune config edit` | Open config in $EDITOR |
| `typetune version` | Show version |

### Quick Start

```bash
# Start daemon (foreground, for testing)
typetune daemon

# Or start as background service
typetune start
typetune status

# Open GUI settings
typetune-gui
```

## Configuration

Config location: `~/.config/typetune/config.toml`

```toml
[general]
log_level = "info"
pid_file = "/tmp/typetune.pid"

[input]
discovery = "auto"           # auto-detect keyboards
device_paths = []            # or specify paths manually
exclude_names = ["Power Button", "Sleep Button"]

[corrector]
enabled = true
min_word_length = 3          # don't correct words shorter than this
layouts = ["us", "ru"]
dict_dir = "~/.config/typetune/dict/"
exclude_classes = ["Alacritty", "kitty", "Code"]
exclude_titles = []

[chatter]
enabled = true
debounce_ms = 50             # debounce window for regular keys
modifier_debounce_ms = 30    # shorter window for Shift/Ctrl/Alt

[snippets]
enabled = true
trigger_prefix = ":"
word_separators = [" ", "\t", "\n", "\r"]

[snippets.entries]
date = "{{date}}"
time = "{{time}}"
myip = "{{shell:curl -s ifconfig.me}}"
docker = "docker run -it --rm -v $(pwd):/app -w /app"

[typography]
enabled = false
smart_quotes = true
em_dash = true
```

### Dynamic Variables in Snippets

| Variable | Description |
|---|---|
| `{{date}}` | Current date (YYYY-MM-DD) |
| `{{time}}` | Current time (HH:MM:SS) |
| `{{shell:cmd}}` | Output of shell command |

## License

MIT
