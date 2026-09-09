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
RULLER_FRAMEWORK="$(python3 - "$PWD/.build/build-arm64/artifacts" <<'PY'
from pathlib import Path
import sys
paths = list(Path(sys.argv[1]).rglob('Sparkle.framework'))
if len(paths) != 1:
    sys.exit(f'Expected exactly one Sparkle framework, found {len(paths)}')
print(paths[0])
PY
)"
mkdir -p "$APP/Contents/Frameworks"
ditto "$RULLER_FRAMEWORK" "$APP/Contents/Frameworks/Sparkle.framework"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp 'Resources/Read Me.txt' "$APP/Contents/Resources/Read Me.txt"
RULLER_TOOLS="$(bash scripts/sparkle-tools.sh)"
cp "$RULLER_TOOLS/LICENSE" "$APP/Contents/Resources/Sparkle-LICENSE.txt"
swift scripts/icon.swift "$PWD/.build/AppIcon.iconset"
iconutil -c icns .build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"
bash scripts/sign-app.sh "$APP"
lipo -info "$APP/Contents/MacOS/Ruller"
printf 'Built %s\n' "$APP"
