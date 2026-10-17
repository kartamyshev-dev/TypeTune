#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
translation_build_only=false
if [ "${1:-}" = "--build-only" ]; then translation_build_only=true; shift; fi
[ "$#" -eq 0 ] || { echo "usage: $0 [--build-only]" >&2; exit 2; }
translation_build_dir=${LAYOUTPILOT_BUILD_DIR:-.build/debug}
if [ -f "$translation_build_dir/LayoutPilotCore.o" ]; then
 translation_module_dir="$translation_build_dir"; set -- "$translation_build_dir/LayoutPilotCore.o"
else
 translation_module_dir="$translation_build_dir/Modules"; set -- "$translation_build_dir"/LayoutPilotCore.build/*.swift.o
fi
swiftc -parse-as-library -swift-version 5 -module-cache-path .build/input-source-translation-module-cache \
 -I "$translation_module_dir" Tools/InputSourceTranslationProbe.swift Sources/LayoutPilot/InputSources.swift "$@" \
 -framework AppKit -framework Carbon -o .build/input-source-translation-probe
if [ "$translation_build_only" = true ]; then exit 0; fi
exec .build/input-source-translation-probe
