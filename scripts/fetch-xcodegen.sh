#!/usr/bin/env bash
# Downloads the pinned XcodeGen release into a folder, checks its checksum and
# prints the folder holding the executable. CI uses it instead of an unpinned
# `brew install`, so the tool that generates the project is the one reviewed.
# Usage: scripts/fetch-xcodegen.sh <folder>
set -euo pipefail

VERSION="2.45.3"
SHA256="0c90f4d28ca57335f9fa78cf5bf6dabfe20a232036dabe36de2eef79cb7c0878"

DEST="${1:?usage: scripts/fetch-xcodegen.sh <folder>}"
mkdir -p "$DEST"
ZIP="$DEST/xcodegen-$VERSION.zip"
curl -fsSL --retry 3 -o "$ZIP" "https://github.com/yonaskolb/XcodeGen/releases/download/$VERSION/xcodegen.zip"
echo "$SHA256  $ZIP" | shasum -a 256 -c - >&2
unzip -q -o "$ZIP" -d "$DEST"
rm -f "$ZIP"
echo "$DEST/xcodegen/bin"
