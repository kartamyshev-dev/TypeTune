#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p .build
swiftc -parse-as-library -swift-version 5 Tools/PlainPasteFixtureProbe.swift \
 -framework AppKit -framework ApplicationServices -framework Carbon \
 -o .build/plain-paste-fixture-probe
if [ "${1:-}" = "--compile-only" ]; then
 exit 0
fi
exec .build/plain-paste-fixture-probe "$@"
