#!/usr/bin/env bash
# Build a drag-to-install Voicely.dmg from the built app.
#
# NOTE on distribution: this DMG is signed with the self-signed dev identity, so
# recipients must right-click → Open on first launch (Gatekeeper). For a clean,
# double-click-to-open experience you need an Apple Developer ID + notarization —
# that path is wired in .github/workflows/release.yml and turns on automatically
# once the signing secrets exist. See docs/STATUS.md.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="${1:-/Applications/Voicely.app}"
OUT="dist/Voicely.dmg"
mkdir -p dist
rm -f "$OUT"

if command -v create-dmg >/dev/null 2>&1; then
  create-dmg \
    --volname "Voicely" \
    --window-size 540 380 \
    --icon-size 110 \
    --icon "Voicely.app" 150 185 \
    --app-drop-link 390 185 \
    --hide-extension "Voicely.app" \
    "$OUT" "$APP"
else
  echo "create-dmg not found; using hdiutil (no drag-install styling)"
  hdiutil create -volname "Voicely" -srcfolder "$APP" -ov -format UDZO "$OUT"
fi

echo "Built → $OUT ($(du -h "$OUT" | awk '{print $1}'))"
