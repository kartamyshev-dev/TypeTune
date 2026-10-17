#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
swift build -c release --arch arm64 --product LayoutPilot
swift build -c release --arch arm64 --product layoutpilot-cli
BUILD_DIR=$(swift build -c release --arch arm64 --show-bin-path)
APP_DIR="$PWD/dist/LayoutPilot.app"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp assets/AppIcon.icns "$APP_DIR/Contents/Resources/AppIcon.icns"
cp "$BUILD_DIR/LayoutPilot" "$APP_DIR/Contents/MacOS/LayoutPilot"
cp "$BUILD_DIR/layoutpilot-cli" dist/layoutpilot-cli
ditto "$BUILD_DIR/LayoutPilot_LayoutPilotCore.bundle" "$APP_DIR/Contents/Resources/LayoutPilot_LayoutPilotCore.bundle"
ditto "$BUILD_DIR/LayoutPilot_LayoutPilotCore.bundle" dist/LayoutPilot_LayoutPilotCore.bundle
cat > "$APP_DIR/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>LayoutPilot</string>
<key>CFBundleIdentifier</key><string>dev.layoutpilot.mac</string>
<key>CFBundleName</key><string>TypeTune</string>
<key>CFBundleDisplayName</key><string>TypeTune</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.3</string>
<key>CFBundleVersion</key><string>9</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSHumanReadableCopyright</key><string>Independent experimental prototype</string>
</dict></plist>
PLIST
codesign --force --sign - "$APP_DIR/Contents/Resources/LayoutPilot_LayoutPilotCore.bundle"
codesign --force --sign - "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"
python3 - <<'PY'
import json, pathlib, sys
sys.path.insert(0, 'scripts')
from verify_existing_build import capture_build_identity
pathlib.Path('dist/build-identity.json').write_text(json.dumps(capture_build_identity(pathlib.Path.cwd()), ensure_ascii=False, indent=2) + '\n')
PY
file "$APP_DIR/Contents/MacOS/LayoutPilot"
echo "$APP_DIR"
