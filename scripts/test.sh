#!/usr/bin/env bash
# Regenerates the project and runs the unit tests, printing only the summary
# and any failures. Extra arguments go to xcodebuild, e.g.
#   scripts/test.sh -only-testing:TwanCleanTests/PathPolicyTests
set -euo pipefail
cd "$(dirname "$0")/.."
xcodegen generate --quiet
set +e
xcodebuild test -project TwanClean.xcodeproj -scheme TwanClean \
  -destination "${TEST_DESTINATION:-platform=macOS,arch=arm64}" "$@" 2>&1 \
  | grep -E "error:|warning: .*\.swift|failed|Executed [0-9]+ tests|TEST (SUCCEEDED|FAILED)" \
  | grep -v "linkd.autoShortcut"
exit "${PIPESTATUS[0]}"
