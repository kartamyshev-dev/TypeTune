#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p .build
swiftc -parse-as-library -swift-version 5 -module-cache-path .build/diagnostics-module-cache \
 Sources/LayoutPilot/InputDiagnostics.swift Tools/InputDiagnosticsProbe.swift -o .build/input-diagnostics-probe
exec .build/input-diagnostics-probe
