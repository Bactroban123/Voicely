#!/usr/bin/env bash
# Build, ad-hoc sign, and install Voicely.app to /Applications for personal use.
# Ad-hoc signing is unstable across rebuilds, so TCC grants (Accessibility, Input
# Monitoring) may need re-approval after each install. A stable signing identity
# (free Apple Development cert via Xcode) avoids that.
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
codesign --force --deep --sign - --entitlements App/Voicely.entitlements /Applications/Voicely.app
codesign -dvv /Applications/Voicely.app 2>&1 | grep -E "Identifier=|Signature="
echo "Installed → /Applications/Voicely.app"
