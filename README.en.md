# TypeTune

> System-wide Russian ↔ English layout correction, snippets, and optional key debounce.

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![CI](https://img.shields.io/badge/CI-Linux%20%2B%20macOS-success)](https://github.com/kartamyshev-dev/TypeTune/actions)
[![Release](https://img.shields.io/badge/release-pre--release-orange)](https://github.com/kartamyshev-dev/TypeTune/releases)

**[Русский](README.md)**

TypeTune fixes text typed in the wrong keyboard layout (for example `ghbdtn` → `привет`), switches the input source, expands snippets, and can optionally debounce noisy keyboards on Linux.

## Status

| Platform | Channel | Artifact |
|---|---|---|
| Linux (Ubuntu 26.04 / GNOME 50 / Wayland, amd64) | Preview | `.deb` |
| macOS (Apple Silicon, macOS 27) | Preview | `.zip` (ad-hoc signed, not notarized) |
| Windows | — | Not released |

Preview builds are usable day-to-day but are **not** a production guarantee. Not every application is treated the same way. What CI tests versus what is checked by hand is described in [docs/testing.md](docs/testing.md) (Russian).

## Features

- **Double Shift** — convert the last word `RU ↔ EN` and switch the input source; repeat toggles back
- **Auto-correct on Space** — frequency-ranked RU/EN dictionaries; short words and code-like tokens are conservative
- **Snippets** — trigger + delimiter, Unicode replacements
- **Learned words** and **exclusions** — improve or block corrections without editing files by hand
- **Application exclusions** — disable auto-correct in selected apps (manual gesture stays)
- **Menu bar** — pause, layout flag (`EN` / `RU` / `?`), optional switch sound (macOS)
- **Key debounce** (Linux, opt-in, per device)

## Screenshots

| Settings | Menu bar |
|---|---|
| ![Settings](docs/assets/screenshots/settings.png) | ![Menu](docs/assets/screenshots/menu.png) |

> Screenshots are placeholders until release assets are added.

## Install

### Linux (`.deb`)

1. Download the `.deb` from [Releases](https://github.com/kartamyshev-dev/TypeTune/releases).
2. Install with APT or `dpkg` (not GNOME Software for a local file).
3. Run **TypeTune Setup** from the application menu and confirm the device-access prompt.
4. Log out and back in so the session helper is loaded.

Details: [docs/install.md](docs/install.md)

### macOS (`.zip`)

1. Download `TypeTune-macos-arm64.zip` from Releases.
2. Unpack and move `TypeTune.app` to `~/Applications`.
3. Open the app and grant **Input Monitoring** and **Accessibility** when prompted.

Details: [docs/install.md](docs/install.md)

## Privacy

Keystroke history used for corrections stays **in memory only**. TypeTune does not log typed words or clipboard contents. Pause the app before passwords or other sensitive fields. Secure input fields are skipped when the system reports them.

More: [docs/security-privacy.md](docs/security-privacy.md)

## Limitations

- Behaviour can differ across editors, terminals, and toolkits.
- IME / dead keys / secure fields have reduced support.
- Layout pairs are standard US ↔ Russian (PC) unless configured otherwise.

See [docs/user-guide.md](docs/user-guide.md).

## Documentation

Documentation is written in Russian.

| Document | Topic |
|---|---|
| [docs/overview.md](docs/overview.md) | Product overview and scope |
| [docs/install.md](docs/install.md) | Install and permissions |
| [docs/user-guide.md](docs/user-guide.md) | Everyday use |
| [docs/architecture.md](docs/architecture.md) | How the pieces fit |
| [docs/development.md](docs/development.md) | Build from source |
| [docs/testing.md](docs/testing.md) | CI vs native checks |
| [docs/security-privacy.md](docs/security-privacy.md) | Privacy and safety |
| [docs/troubleshooting.md](docs/troubleshooting.md) | Common problems |

## Development

```sh
# Linux toolchain (CI)
rustup toolchain install 1.98.1
cargo test --workspace --all-targets --locked

# macOS toolchain (CI)
rustup toolchain install 1.89.0
bash scripts/test-macos.sh
bash scripts/build-macos.sh
```

See [docs/development.md](docs/development.md) and [CONTRIBUTING.md](CONTRIBUTING.md).

## License

[MIT](LICENSE)

Frequency word lists used for ranking ship under their own terms (CC BY-SA 4.0 / CC BY 2.5) and are attributed inside the application bundle (`frequency-attribution`).
