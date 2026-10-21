#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
label=${1:-before}
case "$label" in *[!a-zA-Z0-9_-]*|'') echo 'Метка: только латиница, цифры, дефис и подчёркивание' >&2; exit 1;; esac
output="$PWD/research/private/ui-$(TZ=Europe/Moscow date +%F)/$label"
# CLT 27 on this Mac lacks SwiftUIMacros; use the installed complete SDK when available.
if [ -z "${SDKROOT:-}" ] && [ -d /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk ]; then
    SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk
    export SDKROOT
fi
swift build --product LayoutPilot
binary_dir=$(swift build --show-bin-path)
"$binary_dir/LayoutPilot" --render-settings "$output"
printf 'Снимки: %s\n' "$output"
