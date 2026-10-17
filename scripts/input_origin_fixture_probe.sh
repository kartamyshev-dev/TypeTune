#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p .build
swiftc -parse-as-library -swift-version 5 Tools/InputOriginFixtureProbe.swift \
 -framework AppKit -framework ApplicationServices -framework Carbon \
 -o .build/input-origin-fixture-probe
if [ "${1:-}" = "--compile-only" ]; then
 exit 0
fi
exec .build/input-origin-fixture-probe "$@"
