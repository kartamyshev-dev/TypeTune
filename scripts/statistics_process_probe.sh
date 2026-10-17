#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
# Reuse the already built core. No SwiftPM invocation or GUI/dist rebuild.
fixture_build_dir="$PWD/.build/debug"
if [ -f "$fixture_build_dir/LayoutPilotCore.o" ]; then
 fixture_module_dir="$fixture_build_dir"; set -- "$fixture_build_dir/LayoutPilotCore.o"
else
 fixture_module_dir="$fixture_build_dir/Modules"; set -- "$fixture_build_dir"/LayoutPilotCore.build/*.swift.o
fi
swiftc -parse-as-library -swift-version 5 -I "$fixture_module_dir" Tools/StatisticsProcessProbe.swift \
 Sources/LayoutPilot/Store.swift "$@" -framework AppKit -framework ImageIO \
 -framework Combine -framework ServiceManagement -o .build/statistics-process-probe
exec .build/statistics-process-probe
