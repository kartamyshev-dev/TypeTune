#!/bin/zsh
# Builds and runs Tools/AXFocusProbe.swift: what the focused element exposes, without text.
set -euo pipefail
probe_root="${0:A:h:h}"
probe_binary="$probe_root/.build/ax-focus-probe"
mkdir -p "$probe_root/.build"
if [[ ! -x "$probe_binary" || "$probe_root/Tools/AXFocusProbe.swift" -nt "$probe_binary" ]]; then
  swiftc -swift-version 5 "$probe_root/Tools/AXFocusProbe.swift" -o "$probe_binary" -framework AppKit -framework ApplicationServices
fi
if [[ "${1:-}" == "--build-only" ]]; then
  print '{"built":true}'
  exit 0
fi
exec "$probe_binary" "$@"
