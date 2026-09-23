# TypeTune macOS preview

Apple Silicon, macOS 27.0, ABC ↔ Russian — PC. Native SwiftUI/AppKit shell,
one serial controller/runtime, Rust `typetune-bridge` in the app bundle.
No Python/GTK runtime.

```sh
bash scripts/test-macos.sh
bash scripts/build-macos.sh --install
```

Open `~/Applications/TypeTune.app`. In Settings, request Input Monitoring and
Accessibility using “Разрешения macOS”; the user grants these in System Settings.
Enable “Режим совместимости”, then Apply. Automatic correction defaults on,
compatibility and login startup default off. Pause clears history immediately.
Closing Settings keeps the menu bar app alive; Quit stops it. A per-user lock
prevents multiple input observers.

Double Shift means two complete taps of the same side, each at most 200 ms,
with at most 350 ms between taps. Device identity is unknown on this backend;
same-device gestures cannot be guaranteed. Known held modifiers, navigation,
paste, mouse events, unsupported input sources, observer loss, sleep and lock
invalidate history. Input is never grabbed or delayed by the observer.

## Replacement and context

A passive session CGEvent tap only normalizes events and enqueues them. A bounded
256-event single-producer/single-consumer ring uses atomic indices; revision reads
do not contend with capture. Overflow invalidates history.
The callback never waits for the engine, Accessibility, disk, GUI or layout APIs.
The worker reads AX context with a 50 ms messaging timeout. Text Input Source APIs
run on the main queue (required on macOS 27), outside the callback.

Replacement waits for physical Space release, verifies the complete original word when
AX text is available, selects the target input source with readback, and emits
paired Backspace/Unicode events. Own events carry a dedicated user-data marker.
New input, focus changes, modifiers or timeout abort remaining output. There is
no automatic retry and no clipboard fallback. Without AX readback the result is
`submitted`, never `verified`. Unknown sensitivity/selection/composition remain
unknown in this explicitly enabled compatibility profile. Secure Input and known
secure fields suspend processing; arbitrary custom secure fields cannot be proven
safe by key history alone. API delivery is not an atomic editor transaction.

## Settings and packaging

`~/Library/Application Support/TypeTune/settings.json`: version 1, generation,
compatibility, automatic, autostart, words, exclusions, applications (bundle IDs).
Atomic save, validation and generation conflict detection; dictionary apply must
be acknowledged by Rust. Suggestions/counters live only in memory. No text or
clipboard in normal diagnostics.

```sh
~/Applications/TypeTune.app/Contents/MacOS/TypeTune --doctor
```

This reports protocol, OS, permissions, input source and effective login-item state.
The app is ad-hoc signed, not notarized. Rebuilding can require granting permissions
again. Update only after quitting the old app; build script preserves user data.
To remove, disable login startup in Settings, Quit, then move the app to Trash.
Settings remain unless the user separately removes the data directory.

The bundled CLI tools on this Mac require explicit Testing framework search paths
and the native SwiftPM build system. Tests use Swift Testing, not XCTest/full Xcode.
GitHub Actions builds on the hosted `xcode-27` Apple Silicon/macOS 27 preview
image. The main CI calls `macos.yml` on branch pushes, pull requests and version
tags; the macOS workflow also supports manual dispatch. It runs Rust/Python/Swift
tests, packages the ad-hoc signed app, verifies its signature after ZIP extraction,
and uploads `macos-preview` (14 days). Download `TypeTune-macos-arm64.zip` and
`MACOS-SHA256SUMS` from that artifact. No personal Mac runner is required.

Tags matching `vMAJOR.MINOR.PATCH-previewN-REVISION` publish a prerelease with both
Debian and macOS assets only after both jobs pass. Native keyboard/permission
acceptance remains local; CI does not grant permissions or launch input observation.
The runner image is public preview and may change; actual versions appear in logs.
See `docs/57-macos-checkpoint.md` for actual evidence.

Manual Double Shift can recover a truncated history from the current AX word.
A known snapshot must match the entire whitespace-delimited token before editing;
a suffix inside a longer token is refused. Unknown AX text remains an unverified
history-only compatibility path. Native acceptance is still required.
