#!/usr/bin/env bash
# Builds Twan Clean in Release, replaces /Applications/TwanClean.app and relaunches it.
# Usage: scripts/install.sh
set -euo pipefail

APP_NAME="TwanClean"  # bundle file and process name; the display name is Twan Clean
BUNDLE_ID="com.twan.twanclean"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALLED_APP="/Applications/$APP_NAME.app"

BUILT_APP="$("$REPO_ROOT/scripts/release-app.sh" | tail -n 1)"

if pgrep -x "$APP_NAME" >/dev/null; then
  echo "==> Quitting the running $APP_NAME"
  osascript -e "quit app id \"$BUNDLE_ID\"" || true
  for _ in {1..20}; do
    pgrep -x "$APP_NAME" >/dev/null || break
    sleep 0.5
  done
  if pgrep -x "$APP_NAME" >/dev/null; then
    echo "error: $APP_NAME is still running; quit it and run the script again" >&2
    exit 1
  fi
fi

echo "==> Installing to $INSTALLED_APP"
rm -rf "$INSTALLED_APP"
ditto "$BUILT_APP" "$INSTALLED_APP"

echo "==> Launching $APP_NAME"
open "$INSTALLED_APP"

version="$(defaults read "$INSTALLED_APP/Contents/Info.plist" CFBundleShortVersionString)"
build_number="$(defaults read "$INSTALLED_APP/Contents/Info.plist" CFBundleVersion)"
echo "Installed $APP_NAME $version ($build_number)"
codesign -dv "$INSTALLED_APP" 2>&1 | grep -q "Signature=adhoc" \
  && echo "Ad-hoc signed: macOS will ask for Full Disk Access again after each install."
exit 0
