#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
swift build --product layoutpilot-cli >&2
guard_build_dir=$(swift build --show-bin-path)
if [ -f "$guard_build_dir/LayoutPilotCore.o" ]; then
  guard_module_dir="$guard_build_dir"
  set -- "$guard_build_dir/LayoutPilotCore.o"
else
  guard_module_dir="$guard_build_dir/Modules"
  set -- "$guard_build_dir"/LayoutPilotCore.build/*.swift.o
fi
swiftc -swift-version 5 -I "$guard_module_dir" \
  Tools/EditorGuardProbe.swift Sources/LayoutPilot/AccessibilityEditor.swift \
  Sources/LayoutPilot/InputDiagnostics.swift \
  "$@" \
  -framework AppKit -framework ApplicationServices -framework Carbon \
  -o .build/editor-guard-probe
exec .build/editor-guard-probe
