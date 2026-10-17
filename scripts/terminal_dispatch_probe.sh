#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
terminal_build_dir=${LAYOUTPILOT_BUILD_DIR:-.build/debug}
if [ -f "$terminal_build_dir/LayoutPilotCore.o" ]; then
 terminal_module_dir="$terminal_build_dir"; set -- "$terminal_build_dir/LayoutPilotCore.o"
else
 terminal_module_dir="$terminal_build_dir/Modules"; set -- "$terminal_build_dir"/LayoutPilotCore.build/*.swift.o
fi
swiftc -parse-as-library -swift-version 5 -module-cache-path .build/terminal-dispatch-module-cache \
 -I "$terminal_module_dir" Tools/TerminalDispatchProbe.swift Sources/LayoutPilot/TerminalBridge.swift "$@" \
 -framework AppKit -framework ApplicationServices -framework Carbon -o .build/terminal-dispatch-probe
exec .build/terminal-dispatch-probe
