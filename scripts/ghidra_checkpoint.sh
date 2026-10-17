#!/bin/sh
# Separate persistent Ghidra workflow; never an REA session save.
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
private="$root/research/private/ghidra-persistent"
target="$root/research/private/caramba-arm64"
expected=19d0057a9bfc38ba590babff82b28b5bf496c0833bbbd221f502722c6e2a26e9
actual=$(shasum -a 256 "$target" | cut -d ' ' -f 1)
[ "$actual" = "$expected" ] || { echo 'Target digest mismatch' >&2; exit 1; }
export JAVA_HOME=/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home
export PATH="$JAVA_HOME/bin:$PATH"
export GHIDRA_HEADLESS_MAXMEM=2G
export GHIDRA_HEADLESS_JAVA_OPTIONS='-XX:ActiveProcessorCount=2'
headless=/opt/homebrew/opt/ghidra/libexec/support/analyzeHeadless
mkdir -p "$private"
case "${1:-}" in
  create)
    [ ! -e "$private/caramba.gpr" ] && [ ! -e "$private/caramba.rep" ] || {
      echo 'Persistent project already exists; use reopen' >&2; exit 1;
    }
    exec nice -n 10 "$headless" "$private" caramba -import "$target" \
      -max-cpu 2 -analysisTimeoutPerFile 600 \
      -scriptPath "$root/scripts" -postScript ghidra_checkpoint.java create "$private/create.json" \
      -log "$private/create.log" -scriptlog "$private/create-script.log"
    ;;
  reopen)
    [ -f "$private/caramba.gpr" ] || { echo 'No persistent project' >&2; exit 1; }
    exec nice -n 10 "$headless" "$private" caramba -process caramba-arm64 \
      -noanalysis -readOnly -max-cpu 2 \
      -scriptPath "$root/scripts" -postScript ghidra_checkpoint.java reopen "$private/reopen.json" \
      -log "$private/reopen.log" -scriptlog "$private/reopen-script.log"
    ;;
  *) echo 'Usage: scripts/ghidra_checkpoint.sh create|reopen' >&2; exit 2 ;;
esac
