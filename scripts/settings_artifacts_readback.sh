#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
# Existing debug Core only: no SwiftPM invocation, no GUI/dist rebuild.
fixture_build_dir="$PWD/.build/debug"
if [ -f "$fixture_build_dir/LayoutPilotCore.o" ]; then
 fixture_module_dir="$fixture_build_dir"; set -- "$fixture_build_dir/LayoutPilotCore.o"
else
 fixture_module_dir="$fixture_build_dir/Modules"; set -- "$fixture_build_dir"/LayoutPilotCore.build/*.swift.o
fi
# Compilation and execution are separate in the documented workflow; this script
# only compiles. Run the resulting helper with one explicit readback mode.
swiftc -parse-as-library -swift-version 5 -I "$fixture_module_dir" Tools/SettingsArtifactsReadback.swift \
 "$@" -framework AppKit -framework ImageIO -o .build/settings-artifacts-readback
