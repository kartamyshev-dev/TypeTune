# Changelog

All notable changes to TypeTune are documented here.

## 0.1.1

Stability release for macOS input (see [docs/releases/0.1.1.md](docs/releases/0.1.1.md)).

### Fixed

- Layout flag `EN`/`RU`/`?` always follows the current TIS source
- Caps Lock used as input-source switch no longer wipes the current word or blocks Double Shift
- Auto-correct on Space no longer rejects when AX reports the token without a trailing space
- Modifier edges and mouse clicks no longer reset keyboard history
- Transient AX focus flicker (`element` briefly nil) does not reset the word or Double Shift
- Event tap recovery no longer deadlocks; missing Input Monitoring is visible in the menu status
- Rapid Double Shift retoggle is not suppressed by an artificial cooldown
- A stuck global Secure Input latch no longer disables typing in normal fields

### Added

- `diag.log` decision trace (no typed text) for live debugging

## 0.1.0

Initial public release.

### Added

- System-wide RU ↔ EN layout correction (manual Double Shift and auto-correct on Space)
- Frequency-ranked dictionaries and learned words
- Word and application exclusions
- Snippets (Unicode triggers)
- Menu bar UI with pause, layout flag, and optional switch sound (macOS)
- Linux preview package (`.deb`, GNOME / Wayland)
- macOS preview app (`.zip`, Apple Silicon)
- CI for Linux and macOS with release publishing on version tags

### Notes

- Preview channel: not every application is guaranteed.
- Windows is not released in this version.

