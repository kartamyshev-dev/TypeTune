#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
root="$PWD"
export CLANG_MODULE_CACHE_PATH="$root/target/macos-module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$CLANG_MODULE_CACHE_PATH"
developer="${DEVELOPER_DIR:-$(xcode-select -p)}"
frameworks=""
for candidate in "$developer/Platforms/MacOSX.platform/Developer/Library/Frameworks"                  "$developer/Library/Developer/Frameworks" "$developer/Library/Frameworks"; do
    if [[ -d "$candidate/Testing.framework" ]]; then frameworks="$candidate"; break; fi
done
if [[ -z "$frameworks" ]]; then
    echo "Swift Testing.framework not found in selected Xcode/Command Line Tools" >&2
    exit 1
fi
cargo test --locked -p typetune-engine -p typetune-bridge
cargo build --locked --release -p typetune-bridge
PYTHONPATH=integrations/app python3 -m unittest integrations/app/test_portable_parity.py integrations/app/test_gesture.py integrations/app/test_feedback.py
xcrun swift test --build-system native --disable-sandbox --disable-xctest --cache-path "$root/target/swift-cache" \
    --package-path integrations/macos \
    -Xswiftc -F -Xswiftc "$frameworks" \
    -Xlinker -F -Xlinker "$frameworks" -Xlinker -rpath -Xlinker "$frameworks" \
    -Xlinker -L -Xlinker "$root/target/release" -Xlinker -rpath -Xlinker "$root/target/release"
