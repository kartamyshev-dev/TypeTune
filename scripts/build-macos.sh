#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
root="$PWD"
export CLANG_MODULE_CACHE_PATH="$root/target/macos-module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$CLANG_MODULE_CACHE_PATH"
cargo build --locked --release -p typetune-bridge
xcrun swift build --build-system native --disable-sandbox --cache-path "$root/target/swift-cache" -debug-info-format none --package-path integrations/macos -c release -Xlinker -L -Xlinker "$root/target/release" -Xlinker -rpath -Xlinker @executable_path/../Frameworks
app="$root/dist/TypeTune.app"
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
revision=$(git rev-parse HEAD)
dirty=false
if [[ -n "$(git status --porcelain)" ]]; then dirty=true; fi
cat > "$app/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>dev.kartamyshev.TypeTune</string>
<key>CFBundleName</key><string>TypeTune</string>
<key>CFBundleExecutable</key><string>TypeTune</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>57</string>
<key>LSMinimumSystemVersion</key><string>27.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
<key>TypeTuneSourceCommit</key><string>$revision</string>
<key>TypeTuneSourceDirty</key><$dirty/>
</dict></plist>
EOF
codesign --force --sign - "$app/Contents/Frameworks/libtypetune_bridge.dylib"
codesign --force --sign - --identifier dev.kartamyshev.TypeTune "$app"
codesign --verify --deep --strict "$app"
if [[ "${1:-}" == "--install" ]]; then
    mkdir -p "$HOME/Applications"
    ditto "$app" "$HOME/Applications/TypeTune.app"
    codesign --verify --deep --strict "$HOME/Applications/TypeTune.app"
fi
echo "$app"
