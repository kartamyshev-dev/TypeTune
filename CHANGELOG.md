# Changelog

All notable changes to TypeTune are documented here.

## 0.2.0

Native Linux shell (see [docs/releases/0.2.0.md](docs/releases/0.2.0.md)).

### Added (Linux)

- `typetune-gui`: GTK4/libadwaita settings window (toggles, autostart, pause, permissions/doctor)
- `typetune doctor --session` reports protocol, OS, permissions, input source, autostart (macOS `--doctor` parity keys)
- `.deb` ships `typetune-gui` and `typetune`; desktop action «Нативные настройки (GTK)»
- `TYPETUNE_NATIVE=1` prefers the native window from `typetune-preview`

### Fixed (Linux)

- Bridge policy is reconfigured when settings generation changes (not only when the word dictionary changes)
- Helper death no longer freezes the runtime: supervised respawn with backoff (3 attempts), UI shows «Нужны разрешения» / helper-lost
- `TYPETUNE_DIAG=1` writes a decision-only `diag.log` (invalidate, helper-lost, trigger) — never typed text

### Docs

- README/user-guide no longer claim snippets and key debounce as shipped features (neither is wired on either platform)

## 0.1.3

Linux input stability and Status-menu parity with macOS.

### Fixed (Linux)

- Caps Lock / Fn no longer wipe the current word or block Double Shift
- Modifier edges (Ctrl/Alt/Super) alone no longer reset keyboard history; shortcuts (e.g. Ctrl+letter) still clear
- Mouse clicks / touch no longer wipe the word (only cancel a pending gesture)
- Layout switch (Super+Space, Caps) keeps history and skips **one** auto word (anti-loop)
- Transient GNOME focus flicker (window token briefly 0) no longer resets the word
- Bridge `infer` now honours the configured policy (`switch_only_last_word`, `dont_switch_words`, `dont_correct_after_layout_change`)

### Added (Linux)

- National flags 🇺🇸/🇷🇺 in the tray status item and menu header (21×14, 10pt padding)
- Full Status menu matching macOS: auto/manual switching, switch-only-last-word, don't-switch-words, don't-correct-after-layout-change, switch sound, display flag, learned words, app exclusions, active layouts, permissions, autostart, pause, quit
- Settings schema v2 with generation ACK (tray + window cannot lose updates)
- Optional switch sound (`play_switching_sound`, best-effort via paplay/pw-play)
- `diag` decision trace is available via runtime status counters

## 0.1.2

Menu-bar flag artwork (see [docs/releases/0.1.2.md](docs/releases/0.1.2.md)).

### Changed

- Status item shows a national flag (US / RU) instead of EN/RU text, with 10pt side padding and 21×14 artwork
- Menu header shows the same flag badge

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

