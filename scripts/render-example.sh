#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="${TMPDIR:-/tmp}/ruller-clang-cache"
swift build --target RullerCore --disable-sandbox
RULLER_BIN_DIR="$(swift build --show-bin-path --disable-sandbox)"
swiftc -parse-as-library -target "$(uname -m)-apple-macosx13.0" -I "$RULLER_BIN_DIR/Modules" \
  "$RULLER_BIN_DIR"/RullerCore.build/*.o \
  Sources/Ruller/{Model,Overlay,Palette,WindowTracker,Shortcuts}.swift \
  scripts/render-example.swift -o .build/render-example
.build/render-example docs/images/ruller-example.png
