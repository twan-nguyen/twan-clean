#!/usr/bin/env bash
# Builds Twan Clean in Release and signs it with the self-signed identity when the
# signing keychain is set up (see scripts/create-signing-identity.sh and
# scripts/setup-signing-keychain.sh); otherwise the app stays ad-hoc signed.
# Prints the path of the signed app on the last line.
# Usage: scripts/release-app.sh
set -euo pipefail

APP_NAME="TwanClean"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA="$REPO_ROOT/.derived"
BUILT_APP="$DERIVED_DATA/Build/Products/Release/$APP_NAME.app"
SIGN_IDENTITY="Twan Clean Self-Signed"
SIGN_KEYCHAIN="$HOME/Library/Keychains/twanclean-signing.keychain-db"

echo "==> Building $APP_NAME (Release)" >&2
xcodegen generate --spec "$REPO_ROOT/project.yml" --project "$REPO_ROOT" --quiet
xcodebuild \
  -project "$REPO_ROOT/TwanClean.xcodeproj" \
  -scheme TwanClean \
  -configuration Release \
  -derivedDataPath "$DERIVED_DATA" \
  -quiet \
  build >&2

if [[ ! -d "$BUILT_APP" ]]; then
  echo "error: $BUILT_APP was not produced" >&2
  exit 1
fi

# Signing every build with the same self-signed identity keeps the same app identity,
# so macOS keeps Full Disk Access between installs.
if [[ -f "$SIGN_KEYCHAIN" ]] \
  && keychain_password="$(security find-generic-password -s twanclean-signing-keychain -a "$USER" -w 2>/dev/null)"; then
  echo "==> Signing with \"$SIGN_IDENTITY\"" >&2
  security unlock-keychain -p "$keychain_password" "$SIGN_KEYCHAIN"
  "$REPO_ROOT/scripts/sign-app.sh" "$BUILT_APP" "$SIGN_IDENTITY" "$SIGN_KEYCHAIN" >&2
  security lock-keychain "$SIGN_KEYCHAIN"
else
  echo "warning: signing keychain not set up; the app stays ad-hoc signed" >&2
fi

echo "$BUILT_APP"
