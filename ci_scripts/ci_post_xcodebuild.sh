#!/bin/zsh
# Xcode Cloud runs this after every xcodebuild action. After an archive that is signed for
# App Store Connect, it writes the TestFlight "What to Test" notes from the recent commit
# subjects, so each internal build says what changed. Apple's reference:
# https://developer.apple.com/documentation/xcode/including-notes-for-testers-with-a-beta-release-of-your-app
set -euo pipefail

if [[ ! -d "${CI_APP_STORE_SIGNED_APP_PATH:-}" ]]; then
  exit 0
fi

testflight_dir="$(dirname "$0")/../TestFlight"
mkdir -p "$testflight_dir"

# Xcode Cloud clones shallowly; deepen so the log has something to show.
git fetch --deepen 20 >/dev/null 2>&1 || true
notes="$(git log -20 --no-merges --pretty=format:'- %s')"
{
  echo "Build ${CI_BUILD_NUMBER:-?} from ${CI_BRANCH:-${CI_TAG:-?}} (${CI_COMMIT:0:7})"
  echo
  echo "$notes"
} > "$testflight_dir/WhatToTest.en-US.txt"
