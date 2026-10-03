#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
root="$PWD"
export CLANG_MODULE_CACHE_PATH="$root/target/macos-module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$CLANG_MODULE_CACHE_PATH"
mkdir -p "$root/target"
run_dir=$(mktemp -d "$root/target/macos-test.XXXXXX")
developer="${DEVELOPER_DIR:-$(xcode-select -p)}"
frameworks=""
for candidate in "$developer/Platforms/MacOSX.platform/Developer/Library/Frameworks"                  "$developer/Library/Developer/Frameworks" "$developer/Library/Frameworks"; do
    if [[ -d "$candidate/Testing.framework" ]]; then frameworks="$candidate"; break; fi
done
if [[ -z "$frameworks" ]]; then
    echo "Swift Testing.framework not found in selected Xcode/Command Line Tools" >&2
    exit 1
fi
python3 scripts/run-bounded.py --directory "$run_dir/rust-test" -- cargo test --locked -p typetune-engine -p typetune-bridge
python3 scripts/run-bounded.py --directory "$run_dir/rust-build" -- cargo build --locked --release -p typetune-bridge
PYTHONPATH=integrations/app python3 scripts/run-bounded.py --directory "$run_dir/parity" -- python3 -m unittest integrations/app/test_portable_parity.py integrations/app/test_gesture.py integrations/app/test_feedback.py
python3 scripts/run-bounded.py --directory "$run_dir/packaging" -- python3 -m unittest discover -s tests/packaging -p 'test_*.py'
python3 scripts/run-bounded.py --directory "$run_dir/swift-test" -- xcrun swift test --build-system native --disable-sandbox --disable-xctest --cache-path "$root/target/swift-cache" \
    --package-path integrations/macos --no-parallel \
    -Xswiftc -F -Xswiftc "$frameworks" \
    -Xlinker -F -Xlinker "$frameworks" -Xlinker -rpath -Xlinker "$frameworks" \
    -Xlinker -L -Xlinker "$root/target/release" -Xlinker -rpath -Xlinker "$root/target/release"
