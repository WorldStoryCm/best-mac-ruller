#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="${TMPDIR:-/tmp}/ruller-clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="${TMPDIR:-/tmp}/ruller-swift-cache"
APP="$PWD/dist/Ruller.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
RULLER_BINARIES=()
for RULLER_ARCH in arm64 x86_64; do
    RULLER_SCRATCH="$PWD/.build/build-$RULLER_ARCH"
    swift build -c release --arch "$RULLER_ARCH" --scratch-path "$RULLER_SCRATCH" --disable-sandbox
    RULLER_BIN_DIR="$(swift build -c release --arch "$RULLER_ARCH" --scratch-path "$RULLER_SCRATCH" --show-bin-path --disable-sandbox)"
    RULLER_BINARIES+=("$RULLER_BIN_DIR/Ruller")
done
lipo -create "${RULLER_BINARIES[@]}" -output "$APP/Contents/MacOS/Ruller"
cp Resources/Info.plist "$APP/Contents/Info.plist"
swift scripts/icon.swift "$PWD/.build/AppIcon.iconset"
iconutil -c icns .build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP"
codesign --verify --deep --strict "$APP"
lipo -info "$APP/Contents/MacOS/Ruller"
printf 'Built %s\n' "$APP"
