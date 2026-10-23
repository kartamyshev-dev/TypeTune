#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
git diff --quiet
git diff --cached --quiet
test -z "$(git ls-files --others --exclude-standard)" || { echo 'Commit all source before packaging' >&2; exit 1; }
REVISION=$(git rev-parse HEAD)
SHORT_REVISION=$(git rev-parse --short=12 HEAD)
DELIVERY="dist/delivery-$SHORT_REVISION"
ARCHIVE="dist/TypeTune-0.1.8-$SHORT_REVISION-arm64.zip"
test ! -e "$DELIVERY" && test ! -e "$ARCHIVE" || { echo "Delivery already exists" >&2; exit 1; }
if [ "$#" -eq 0 ]; then
  scripts/build.sh
elif [ "$#" -eq 3 ] && [ "$1" = "--verified-existing-build" ]; then
  python3 scripts/verify_existing_build.py "$2" "$3"
elif [ "$#" -eq 5 ] && [ "$1" = "--verified-existing-build" ] && [ "$4" = "--app" ]; then
  python3 scripts/verify_existing_build.py "$2" "$3" --app "$5"
elif [ "$#" -eq 2 ] && [ "$1" = "--candidate-build" ]; then
  python3 scripts/verify_existing_build.py "$2" --artifact-only
else
  echo 'Usage: scripts/package.sh [--candidate-build BUILD_IDENTITY | --verified-existing-build BUILD_IDENTITY NATIVE_SESSION [--app PATH]]' >&2
  exit 1
fi
mkdir -p "$DELIVERY"
ditto dist/LayoutPilot.app "$DELIVERY/TypeTune.app"
cp dist/layoutpilot-cli "$DELIVERY/layoutpilot-cli"
ditto dist/LayoutPilot_LayoutPilotCore.bundle "$DELIVERY/LayoutPilot_LayoutPilotCore.bundle"
cp README.md "$DELIVERY/"
mkdir -p "$DELIVERY/assets"
ditto assets/readme "$DELIVERY/assets/readme"
mkdir -p "$DELIVERY/docs"
cp docs/*.md "$DELIVERY/docs/"
git archive --format=tar HEAD | gzip > "$DELIVERY/sources.tar.gz"
printf '%s\n' "$REVISION" > "$DELIVERY/SOURCE_COMMIT.txt"
codesign -dvvv dist/LayoutPilot.app 2>"$DELIVERY/signature.txt"
python3 - "$DELIVERY" <<'MANIFEST'
import hashlib, json, pathlib, subprocess, sys
root = pathlib.Path(sys.argv[1])
entries = {str(p.relative_to(root)): hashlib.sha256(p.read_bytes()).hexdigest()
           for p in sorted(root.rglob('*')) if p.is_file() and p.name != 'MANIFEST.json'}
manifest = {'sourceCommit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip(),
            'notice': 'File hashes for this local experimental delivery; no notarization or full acceptance claim.',
            'files': entries}
(root / 'MANIFEST.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n')
MANIFEST
ditto -c -k --keepParent "$DELIVERY" "$ARCHIVE"
shasum -a 256 "$ARCHIVE" > "$ARCHIVE.sha256"
cat "$ARCHIVE.sha256"
