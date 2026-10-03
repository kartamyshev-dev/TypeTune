#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
root="$PWD"
install=false
destination=""
if [[ "${1:-}" == "--install" ]]; then
    install=true
    shift
    if [[ $# -gt 0 ]]; then destination="$1"; shift; fi
elif [[ "${1:-}" == "--help" ]]; then
    echo "Usage: $0 [--install [/absolute/path/TypeTune.app]]"
    exit 0
fi
if [[ $# -gt 0 ]]; then echo "Unexpected argument: $1" >&2; exit 2; fi
export CLANG_MODULE_CACHE_PATH="$root/target/macos-module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$CLANG_MODULE_CACHE_PATH"
mkdir -p "$root/target" "$root/dist"
run_dir=$(mktemp -d "$root/target/macos-build.XXXXXX")
staging=$(mktemp -d "$root/dist/.macos-build.XXXXXX")
trap 'rm -rf -- "$staging"' EXIT
python3 scripts/macos-package.py identity "$root" > "$run_dir/source.json"
python3 scripts/run-bounded.py --directory "$run_dir/rust" -- cargo build --locked --release -p typetune-bridge
python3 scripts/run-bounded.py --directory "$run_dir/swift" -- xcrun swift build --build-system native --disable-sandbox --cache-path "$root/target/swift-cache" -debug-info-format none --package-path integrations/macos -c release -Xlinker -L -Xlinker "$root/target/release" -Xlinker -rpath -Xlinker @executable_path/../Frameworks
app="$staging/TypeTune.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Frameworks" "$app/Contents/Resources"
cp integrations/macos/.build/release/TypeTune "$app/Contents/MacOS/TypeTune"
cp target/release/libtypetune_bridge.dylib "$app/Contents/Frameworks/"
dependency=$(otool -D target/release/libtypetune_bridge.dylib | tail -n 1)
install_name_tool -change "$dependency" @rpath/libtypetune_bridge.dylib "$app/Contents/MacOS/TypeTune"
install_name_tool -id @rpath/libtypetune_bridge.dylib "$app/Contents/Frameworks/libtypetune_bridge.dylib"
if otool -L "$app/Contents/MacOS/TypeTune" | tail -n +2 | rg -q --fixed-strings "$root"; then
    echo "Bundle still references the build directory" >&2
    exit 1
fi
python3 scripts/macos-package.py stamp "$root" "$app" "$run_dir/source.json"
# FrequencyWords/Leeds attribution (CC BY-SA 4.0 / CC BY 2.5) ships with the
# binary because lexicons are embedded at build time. It must be in place
# before signing: files added afterwards break the resource seal and fail
# `codesign --verify --deep --strict` after packaging.
attrs="$app/Contents/Resources/frequency-attribution"
mkdir -p "$attrs"
cp crates/typetune-engine/data/frequency/README.md "$attrs/README.md"
cp crates/typetune-engine/data/frequency/manifest.json "$attrs/manifest.json"
cp crates/typetune-engine/data/frequency/LICENSE.html "$attrs/LICENSE.html"
cp crates/typetune-engine/data/frequency/LICENSE-leeds.txt "$attrs/LICENSE-leeds.txt"
cp crates/typetune-engine/data/frequency/upstream-README.md "$attrs/upstream-README.md"
cp LICENSE "$attrs/TypeTune-LICENSE"
codesign --force --sign - "$app/Contents/Frameworks/libtypetune_bridge.dylib"
codesign --force --sign - --identifier dev.kartamyshev.TypeTune "$app"
codesign --verify --deep --strict "$app"
python3 scripts/macos-package.py publish "$app" "$root/dist/TypeTune.app"
app="$root/dist/TypeTune.app"
if $install; then
    if [[ -n "$destination" ]]; then
        python3 scripts/macos-package.py install "$app" "$destination"
    else
        python3 scripts/macos-package.py install "$app"
    fi
fi
echo "$app"
