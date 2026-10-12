#!/usr/bin/env bash
# Builds and signs Twan Clean in Release, then zips it into dist/ for copying to
# another Mac. The app is not notarized, so on another Mac open it the first time
# with Control-click › Open.
# Usage: scripts/package-local.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILT_APP="$("$REPO_ROOT/scripts/release-app.sh" | tail -n 1)"

codesign --verify --deep --strict "$BUILT_APP"
version="$(defaults read "$BUILT_APP/Contents/Info.plist" CFBundleShortVersionString)"
mkdir -p "$REPO_ROOT/dist"
archive="$REPO_ROOT/dist/TwanClean-$version.zip"
rm -f "$archive"
ditto -c -k --keepParent "$BUILT_APP" "$archive"

echo "Created $archive"
shasum -a 256 "$archive"
