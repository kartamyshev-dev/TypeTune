#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
fixture_mode=${1:-read}
if [ "$#" -gt 0 ]; then shift; fi
fixture_hid_flag=${1:-}
swift build --product layoutpilot-cli >&2
fixture_build_dir=$(swift build --show-bin-path)
if [ -f "$fixture_build_dir/LayoutPilotCore.o" ]; then
 fixture_module_dir="$fixture_build_dir"; set -- "$fixture_build_dir/LayoutPilotCore.o"
else
 fixture_module_dir="$fixture_build_dir/Modules"; set -- "$fixture_build_dir"/LayoutPilotCore.build/*.swift.o
fi
swiftc -parse-as-library -swift-version 5 -I "$fixture_module_dir" "$PWD/Tools/CodexFixtureProbe.swift" "$PWD/Tools/OmniboxProbe.swift" \
 Sources/LayoutPilot/AccessibilityEditor.swift Sources/LayoutPilot/InputSources.swift Sources/LayoutPilot/InputDiagnostics.swift "$@" \
 -framework AppKit -framework ApplicationServices -framework Carbon -o .build/chromium-fixture-probe
if [ "$fixture_mode" = "--compile-only" ]; then exit 0; fi
exec .build/chromium-fixture-probe "$fixture_mode" "$fixture_hid_flag"
