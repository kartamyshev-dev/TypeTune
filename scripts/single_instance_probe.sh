#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p .build
swiftc -parse-as-library Sources/LayoutPilot/SingleInstance.swift Tools/SingleInstanceProbe.swift -o .build/single-instance-probe
exec .build/single-instance-probe
