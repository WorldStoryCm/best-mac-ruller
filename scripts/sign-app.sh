#!/bin/bash
set -euo pipefail
RULLER_APP="${1:?Usage: sign-app.sh /path/to/Ruller.app}"
RULLER_IDENTITY="${RULLER_SIGNING_IDENTITY:--}"
RULLER_FLAGS=(--force --sign "$RULLER_IDENTITY" --preserve-metadata=entitlements)
if [ "$RULLER_IDENTITY" != - ]; then
    RULLER_FLAGS+=(--timestamp --options runtime)
fi
RULLER_FRAMEWORK="$RULLER_APP/Contents/Frameworks/Sparkle.framework"
for RULLER_NESTED in \
    "$RULLER_FRAMEWORK/Versions/B/XPCServices/Downloader.xpc" \
    "$RULLER_FRAMEWORK/Versions/B/XPCServices/Installer.xpc" \
    "$RULLER_FRAMEWORK/Versions/B/Autoupdate" \
    "$RULLER_FRAMEWORK/Versions/B/Updater.app"; do
    if [ -e "$RULLER_NESTED" ]; then codesign "${RULLER_FLAGS[@]}" "$RULLER_NESTED"; fi
done
codesign "${RULLER_FLAGS[@]}" "$RULLER_FRAMEWORK"
codesign "${RULLER_FLAGS[@]}" "$RULLER_APP"
codesign --verify --deep --strict "$RULLER_APP"
