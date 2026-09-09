#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
RULLER_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' dist/Ruller.app/Contents/Info.plist)"
RULLER_ARCHIVE="$PWD/dist/Ruller-$RULLER_VERSION-mac-universal.zip"
RULLER_NOTES="${NOTES:-releases/$RULLER_VERSION.md}"
test -f "$RULLER_ARCHIVE" || { echo 'Run make share first.' >&2; exit 1; }
test -f "$RULLER_NOTES" || { echo "Write release notes in $RULLER_NOTES or set NOTES=/path/to/notes.md." >&2; exit 1; }
RULLER_TOOLS="$(bash scripts/sparkle-tools.sh)"
RULLER_PUBLIC_KEY="$("$RULLER_TOOLS/bin/generate_keys" --account WorldStoryCm.Ruller -p)"
RULLER_APP_KEY="$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' dist/Ruller.app/Contents/Info.plist)"
test "$RULLER_PUBLIC_KEY" = "$RULLER_APP_KEY" || { echo 'The Keychain signing key does not match this app. Do not replace it with a new key.' >&2; exit 1; }
RULLER_STAGE="$(mktemp -d "$PWD/.build/update.XXXXXX")"
trap 'rm -rf "$RULLER_STAGE"' EXIT
cp "$RULLER_ARCHIVE" "$RULLER_STAGE/"
cp "$RULLER_NOTES" "$RULLER_STAGE/Ruller-$RULLER_VERSION-mac-universal.md"
if [ -f docs/appcast.xml ]; then cp docs/appcast.xml "$RULLER_STAGE/appcast.xml"; fi
"$RULLER_TOOLS/bin/generate_appcast" --account WorldStoryCm.Ruller \
    --download-url-prefix "https://github.com/WorldStoryCm/best-mac-ruller/releases/download/v$RULLER_VERSION/" \
    --link https://github.com/WorldStoryCm/best-mac-ruller \
    --maximum-deltas 0 --maximum-versions 5 --embed-release-notes "$RULLER_STAGE"
mkdir -p docs
cp "$RULLER_STAGE/appcast.xml" docs/appcast.xml
python3 scripts/verify-feed.py docs/appcast.xml "$RULLER_ARCHIVE"
printf 'Signed update ready: %s\n' "$RULLER_ARCHIVE"
