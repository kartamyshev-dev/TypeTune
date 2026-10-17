#!/bin/sh
set -eu
export GHIDRA_INSTALL_DIR="/opt/homebrew/opt/ghidra/libexec"
export JAVA_HOME="/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home"
export PATH="$JAVA_HOME/bin:$PATH"
export REA_GHIDRA_STARTUP_TIMEOUT_MS=600000
exec npx -y rea-agents@6.5.0 "$@"
