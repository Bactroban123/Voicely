#!/usr/bin/env bash
# Verify VoicelyCore's pure logic without Xcode/SwiftPM (Command Line Tools only).
# SwiftPM needs Xcode's macOS platform bundle, which isn't present on CLT-only
# machines; the Swift compiler itself works fine, so we compile the library
# sources + the spec runner directly and run them.
#
# When Xcode is installed, prefer: `swift test` (runs the XCTest suite).
set -euo pipefail
cd "$(dirname "$0")/.."
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
grep -v '^import VoicelyCore' Sources/voicely-spec/main.swift > "$tmp/main.swift"
swiftc Sources/VoicelyCore/*.swift "$tmp/main.swift" -o "$tmp/voicely-spec"
"$tmp/voicely-spec"
