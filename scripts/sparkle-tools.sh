#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
RULLER_SPARKLE_VERSION=2.9.6
RULLER_TOOLS="$PWD/.build/sparkle-tools-$RULLER_SPARKLE_VERSION"
if [ ! -x "$RULLER_TOOLS/bin/generate_appcast" ]; then
    mkdir -p "$RULLER_TOOLS"
    RULLER_ARCHIVE="$RULLER_TOOLS/distribution.tar.xz"
    curl --fail --location --silent --show-error \
        "https://github.com/sparkle-project/Sparkle/releases/download/$RULLER_SPARKLE_VERSION/Sparkle-$RULLER_SPARKLE_VERSION.tar.xz" \
        --output "$RULLER_ARCHIVE"
    python3 - "$RULLER_ARCHIVE" <<'PY'
import hashlib, pathlib, sys
expected = '52bf9e88cdd972fc0c81501377a880e90d47031bd8ca5462488f843e2609e192'
if hashlib.sha256(pathlib.Path(sys.argv[1]).read_bytes()).hexdigest() != expected:
    sys.exit('Sparkle download checksum mismatch; refusing to run it.')
PY
    tar -xf "$RULLER_ARCHIVE" -C "$RULLER_TOOLS"
fi
printf '%s\n' "$RULLER_TOOLS"
