#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p .build
exec swiftc -parse-as-library -swift-version 5 Tools/TextEditFocusSwapProbe.swift \
 -framework AppKit -framework ApplicationServices -framework Carbon -o .build/focus-swap-probe
