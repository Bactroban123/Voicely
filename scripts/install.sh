#!/usr/bin/env bash
# Build and install Voicely.app to /Applications for personal use.
# Signs with the stable self-signed "Voicely Self-Signed" identity so the app's
# designated requirement is cert-based, not ad-hoc cdhash. That keeps macOS TCC
# grants (Accessibility, Input Monitoring) across rebuilds — no re-approval needed.
# To (re)create the identity, see scripts/make-signing-identity.sh.
SIGN_IDENTITY="${VOICELY_SIGN_IDENTITY:-Voicely Self-Signed}"
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

xcodegen generate >/dev/null
xcodebuild -project Voicely.xcodeproj -scheme Voicely -configuration Debug \
  -derivedDataPath .build-xcode build CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "BUILD (SUCCEEDED|FAILED)"

APP=.build-xcode/Build/Products/Debug/Voicely.app
rm -rf /Applications/Voicely.app
cp -R "$APP" /Applications/
xattr -cr /Applications/Voicely.app
codesign --force --deep --sign "$SIGN_IDENTITY" --entitlements App/Voicely.entitlements /Applications/Voicely.app
codesign -dvv /Applications/Voicely.app 2>&1 | grep -E "Identifier=|Signature="
echo "Installed → /Applications/Voicely.app"
