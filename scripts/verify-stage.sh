#!/bin/bash
set -euo pipefail
COPYSTORY_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
COPYSTORY_STAGE="${1:?Usage: verify-stage.sh /path/to/staged-release}"
python3 "$COPYSTORY_ROOT/scripts/release_policy.py" stage "$COPYSTORY_STAGE"
COPYSTORY_VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$COPYSTORY_ROOT/Config/Info.plist")"
COPYSTORY_ARCHIVE="$COPYSTORY_STAGE/CopyStory-$COPYSTORY_VERSION.zip"
COPYSTORY_VERIFY="$(mktemp -d "$COPYSTORY_ROOT/.build/verify.XXXXXX")"
trap 'rm -rf "$COPYSTORY_VERIFY"' EXIT
# Reject traversal, duplicate entries and symlink ancestors before extraction.
python3 "$COPYSTORY_ROOT/scripts/release_policy.py" archive "$COPYSTORY_ARCHIVE"
ditto -x -k "$COPYSTORY_ARCHIVE" "$COPYSTORY_VERIFY"
"$COPYSTORY_ROOT/scripts/verify-package.sh" "$COPYSTORY_VERIFY/CopyStory.app" --public
(cd "$COPYSTORY_STAGE" && shasum -a 256 -c SHA256SUMS)
echo "Public release assets verified, including extracted bundle identity/version and notarization."
