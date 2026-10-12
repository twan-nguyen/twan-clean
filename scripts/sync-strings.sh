#!/usr/bin/env bash
# Compiles the app and merges every user-facing string found in source into the
# String Catalog. Strings that disappeared from source are marked stale.
# Add the Vietnamese translations afterwards; LocalizationTests fails while any
# key is missing one.
set -euo pipefail
cd "$(dirname "$0")/.."

derived=".derived"
catalog="TwanClean/Resources/Localizable.xcstrings"

xcodegen generate --quiet
xcodebuild -project TwanClean.xcodeproj -scheme TwanClean -configuration Debug \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath "$derived" -quiet build

objects="$derived/Build/Intermediates.noindex/TwanClean.build/Debug/TwanClean.build/Objects-normal"
stringsdata=()
while IFS= read -r -d '' file; do
  stringsdata+=(--stringsdata "$file")
done < <(find "$objects" -name '*.stringsdata' -print0)

xcrun xcstringstool sync "$catalog" "${stringsdata[@]}"
