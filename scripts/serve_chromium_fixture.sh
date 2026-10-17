#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
exec python3 -m http.server 18763 --bind 127.0.0.1 --directory Tools/fixtures/chromium
