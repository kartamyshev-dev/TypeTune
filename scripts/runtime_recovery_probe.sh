#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
runtime_build_dir=$(swift build --show-bin-path)
if [ -f "$runtime_build_dir/LayoutPilotCore.o" ]; then
 runtime_module_dir="$runtime_build_dir"; set -- "$runtime_build_dir/LayoutPilotCore.o"
else
 runtime_module_dir="$runtime_build_dir/Modules"; set -- "$runtime_build_dir"/LayoutPilotCore.build/*.swift.o
fi
swiftc -parse-as-library -swift-version 5 -D LAYOUTPILOT_TESTING \
 -module-cache-path .build/runtime-recovery-module-cache -I "$runtime_module_dir" \
 Tools/RuntimeRecoveryProbe.swift Sources/LayoutPilot/KeyboardService.swift Sources/LayoutPilot/Store.swift \
 Sources/LayoutPilot/AccessibilityEditor.swift Sources/LayoutPilot/InputSources.swift \
 Sources/LayoutPilot/SystemVocabulary.swift Sources/LayoutPilot/TerminalBridge.swift "$@" \
 -framework AppKit -framework ApplicationServices -framework Carbon -framework ImageIO \
 -framework Combine -framework ServiceManagement -o .build/runtime-recovery-probe
exec .build/runtime-recovery-probe
