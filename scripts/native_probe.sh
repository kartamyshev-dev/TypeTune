#!/bin/zsh
set -euo pipefail
probe_root="${0:A:h:h}"
probe_binary="$probe_root/.build/native-probe"
mkdir -p "$probe_root/.build"
if [[ ! -x "$probe_binary" || "$probe_root/Tools/NativeProbe.swift" -nt "$probe_binary" || "$probe_root/Tools/ClipboardLease.swift" -nt "$probe_binary" ]]; then
  swiftc -parse-as-library -swift-version 5 "$probe_root/Tools/NativeProbe.swift" "$probe_root/Tools/ClipboardLease.swift" -o "$probe_binary" -framework AppKit -framework ApplicationServices -framework Carbon
fi
if [[ "${1:-}" == "--build-only" ]]; then
  print '{"built":true,"events":0}'
  exit 0
fi
exec "$probe_binary" "$@"
