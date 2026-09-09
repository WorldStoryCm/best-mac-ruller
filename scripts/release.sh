#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
RULLER_REPO=WorldStoryCm/best-mac-ruller
test "$(git branch --show-current)" = main || { echo 'Release from main.' >&2; exit 1; }
test -z "$(git status --porcelain)" || { echo 'Commit your source changes and release notes before releasing.' >&2; exit 1; }
gh api "repos/$RULLER_REPO" --jq '.permissions.push' | /usr/bin/grep -qx true || { echo 'GitHub write access is required. Run gh auth login.' >&2; exit 1; }
git fetch origin main
test "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" || { echo 'Push or pull main so it matches origin/main before releasing.' >&2; exit 1; }
RULLER_CURRENT="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
RULLER_VERSION="${VERSION:-$RULLER_CURRENT}"
RULLER_TAG="v$RULLER_VERSION"
RULLER_NOTES="${NOTES:-releases/$RULLER_VERSION.md}"
test -f "$RULLER_NOTES" || { echo "Write and commit $RULLER_NOTES before releasing." >&2; exit 1; }
if git ls-remote --exit-code --tags origin "refs/tags/$RULLER_TAG" >/dev/null 2>&1; then
    echo "$RULLER_TAG already exists; releases are immutable. Choose a newer VERSION." >&2; exit 1
fi
if gh release view "$RULLER_TAG" --repo "$RULLER_REPO" >/dev/null 2>&1; then
    echo "$RULLER_TAG already has a GitHub release." >&2; exit 1
fi
if git show-ref --verify --quiet "refs/tags/$RULLER_TAG"; then
    echo "$RULLER_TAG already exists locally; inspect the previous release attempt before continuing." >&2; exit 1
fi
RULLER_TOOLS="$(bash scripts/sparkle-tools.sh)"
test "$("$RULLER_TOOLS/bin/generate_keys" --account WorldStoryCm.Ruller -p)" = "$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' Resources/Info.plist)" || {
    echo 'The signing key in this Mac’s Keychain does not match Ruller.' >&2; exit 1;
}
if [ "$RULLER_VERSION" != "$RULLER_CURRENT" ]; then python3 scripts/set-version.py "$RULLER_VERSION"; fi
make test
make share
RULLER_ZIP="dist/Ruller-$RULLER_VERSION-mac-universal.zip"
if [ -n "${RULLER_NOTARY_PROFILE:-}" ]; then
    test "${RULLER_SIGNING_IDENTITY:--}" != - || { echo 'Notarization requires RULLER_SIGNING_IDENTITY.' >&2; exit 1; }
    xcrun notarytool submit "$RULLER_ZIP" --keychain-profile "$RULLER_NOTARY_PROFILE" --wait
    xcrun stapler staple dist/Ruller.app
    bash scripts/package.sh
fi
NOTES="$RULLER_NOTES" bash scripts/prepare-update.sh
git add Resources/Info.plist 'Resources/Read Me.txt' docs/appcast.xml
git diff --cached --check
git commit -m "Release Ruller $RULLER_VERSION"
git tag -a "$RULLER_TAG" -m "Ruller $RULLER_VERSION"
# Keep the feed offline until its archive is fully uploaded and the release is public.
git push origin "$RULLER_TAG"
gh release create "$RULLER_TAG" "$RULLER_ZIP" --repo "$RULLER_REPO" --verify-tag \
    --title "Ruller $RULLER_VERSION" --notes-file "$RULLER_NOTES" --draft
gh release edit "$RULLER_TAG" --repo "$RULLER_REPO" --draft=false --latest
git push origin main
printf 'Published: https://github.com/%s/releases/tag/%s\n' "$RULLER_REPO" "$RULLER_TAG"
printf 'GitHub Pages will deploy the signed feed from main/docs.\n'
