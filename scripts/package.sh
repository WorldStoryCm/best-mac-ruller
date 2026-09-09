#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
RULLER_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' dist/Ruller.app/Contents/Info.plist)"
codesign --verify --deep --strict dist/Ruller.app
RULLER_ZIP="$PWD/dist/Ruller-$RULLER_VERSION-mac-universal.zip"
# A single app at the archive root works for both Sparkle and manual installation.
ditto -c -k --sequesterRsrc --keepParent dist/Ruller.app "$RULLER_ZIP"
printf 'Ready to share: %s\n' "$RULLER_ZIP"
