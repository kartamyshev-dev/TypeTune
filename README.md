# TuneType

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
tunetype/
├── Cargo.toml                    # workspace root
├── crates/
│   ├── tunetype-core/            # InputEvent, PipelineStage trait, Pipeline
│   ├── tunetype-input/           # evdev grab, epoll event loop, device discovery
│   ├── tunetype-inject/          # uinput virtual keyboard (raw ioctl)
│   ├── tunetype-layout/          # xkbcommon keycode→char mapping
│   ├── tunetype-corrector/       # RU↔EN layout correction with dictionaries
│   ├── tunetype-chatter/         # anti-chatter (per-key debounce)
│   ├── tunetype-snippets/        # text snippet expansion
│   ├── tunetype-config/          # TOML config with XDG paths
│   ├── tunetype-tray/            # system tray icon (ksni/StatusNotifierItem)
│   ├── tunetype-gui/             # GTK4 settings window
│   └── tunetype-cli/             # binary, CLI + daemon + IPC
├── config/default.toml           # default configuration
├── dict/{ru,en}.txt              # dictionaries (10K words each)
├── packaging/                    # systemd service, desktop file
└── resources/icons/              # SVG icons for tray
```

### Key Implementation Details

- **Input**: Raw evdev via `libc::read()` with `O_NONBLOCK`, epoll for efficient multi-device polling
- **Grab**: `EVIOCGRAB` ioctl to exclusively capture keyboard input
- **Output**: Raw uinput via `libc::write()` to `/dev/uinput` (no evdev crate dependency for injection)
- **IPC**: D-Bus interface `org.tunetype.Daemon` via zbus (get_status, set_enabled, get_stats, reload_config)
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
git clone https://github.com/kartamyshev-dev/tunetype.git
cd tunetype
make build
sudo make install DESTDIR=/
```

### Enable as User Service

```bash
systemctl --user daemon-reload
systemctl --user enable --now tunetype
```

## Usage

### CLI Commands

| Command | Description |
|---|---|
| `tunetype daemon` | Start daemon in foreground |
| `tunetype start` | Start daemon in background |
| `tunetype stop` | Stop running daemon |
| `tunetype status` | Show daemon status (PID) |
| `tunetype stats` | Show anti-chatter statistics |
| `tunetype list-devices` | List detected keyboard devices |
| `tunetype reload` | Reload config (send SIGHUP) |
| `tunetype config path` | Show config file path |
| `tunetype config edit` | Open config in $EDITOR |
| `tunetype version` | Show version |

### Quick Start

```bash
# Start daemon (foreground, for testing)
tunetype daemon

# Or start as background service
tunetype start
tunetype status

# Open GUI settings
tunetype-gui
```

## Configuration

Config location: `~/.config/tunetype/config.toml`

```toml
[general]
log_level = "info"
pid_file = "/tmp/tunetype.pid"

[input]
discovery = "auto"           # auto-detect keyboards
device_paths = []            # or specify paths manually
exclude_names = ["Power Button", "Sleep Button"]

[corrector]
enabled = true
min_word_length = 3          # don't correct words shorter than this
layouts = ["us", "ru"]
dict_dir = "~/.config/tunetype/dict/"
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
