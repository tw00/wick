#!/bin/bash
# Compile and run the unit tests. No XCTest, no scheme — just the pure pieces
# (duration parsing, ring geometry) built into a small binary.
set -euo pipefail
cd "$(dirname "$0")"

OUT=$(mktemp -d)/wick-tests
swiftc -O -target arm64-apple-macos14.0 \
    Sources/Duration.swift Sources/RingPath.swift Tests/main.swift \
    -o "$OUT"
"$OUT"
