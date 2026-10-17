#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
fixture_build_dir=$(swift build --show-bin-path)
if [ -f "$fixture_build_dir/LayoutPilotCore.o" ]; then
 fixture_module_dir="$fixture_build_dir"; set -- "$fixture_build_dir/LayoutPilotCore.o"
else
 fixture_module_dir="$fixture_build_dir/Modules"; set -- "$fixture_build_dir"/LayoutPilotCore.build/*.swift.o
fi
swiftc -parse-as-library -swift-version 5 -I "$fixture_module_dir" Tools/StatisticsStoreProbe.swift \
 Sources/LayoutPilot/Store.swift "$@" -framework AppKit -framework ImageIO \
 -framework Combine -framework ServiceManagement -o .build/statistics-store-probe
exec .build/statistics-store-probe
