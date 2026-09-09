#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
RULLER_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' dist/Ruller.app/Contents/Info.plist)"
RULLER_STAGE="$(mktemp -d "$PWD/.build/share.XXXXXX")"
trap 'rm -rf "$RULLER_STAGE"' EXIT
RULLER_FOLDER="$RULLER_STAGE/Ruller $RULLER_VERSION"
mkdir -p "$RULLER_FOLDER"
ditto dist/Ruller.app "$RULLER_FOLDER/Ruller.app"
cp 'Resources/Read Me.txt' "$RULLER_FOLDER/Read Me.txt"
codesign --verify --deep --strict "$RULLER_FOLDER/Ruller.app"
RULLER_ZIP="$PWD/dist/Ruller-$RULLER_VERSION-mac-universal.zip"
ditto -c -k --sequesterRsrc --keepParent "$RULLER_FOLDER" "$RULLER_ZIP"
printf 'Ready to share: %s\n' "$RULLER_ZIP"
