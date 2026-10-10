#!/bin/bash
# Build, submit to Apple for notarization, and stage a public release.
# This never publishes a GitHub release or installs the app.
set -euo pipefail
COPYSTORY_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$COPYSTORY_ROOT"
[[ "${COPYSTORY_DEVELOPMENT:-0}" == 0 ]] || { echo "Public releases forbid COPYSTORY_DEVELOPMENT." >&2; exit 1; }
COPYSTORY_SIGNING_IDENTITY="${COPYSTORY_SIGNING_IDENTITY:?Set a Developer ID Application signing identity}"
COPYSTORY_NOTARY_PROFILE="${COPYSTORY_NOTARY_PROFILE:?Set a notarytool Keychain profile name}"
[[ "$COPYSTORY_SIGNING_IDENTITY" == "Developer ID Application:"* ]] || { echo "Developer ID Application identity is required." >&2; exit 1; }
[[ -z "$(git status --porcelain)" ]] || { echo "Release requires a clean committed checkout." >&2; exit 1; }
python3 scripts/release_policy.py config >/dev/null
python3 scripts/check-source-hygiene.py
mkdir -p .build
COPYSTORY_VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Config/Info.plist)"
COPYSTORY_COMMIT="$(git rev-parse HEAD)"
COPYSTORY_STAGE="$COPYSTORY_ROOT/.build/releases/v$COPYSTORY_VERSION"
[[ ! -e "$COPYSTORY_STAGE" ]] || { echo "Release stage already exists; preserve/review it before retrying." >&2; exit 1; }
# Credential preflight before building. The identity is public, never a key.
security find-identity -v -p codesigning | /usr/bin/grep -F -- "$COPYSTORY_SIGNING_IDENTITY" >/dev/null || { echo "Signing identity is not available in Keychain." >&2; exit 1; }
xcrun notarytool history --keychain-profile "$COPYSTORY_NOTARY_PROFILE" --output-format json > .build/notary-history.json
python3 scripts/check-release-history.py "$@"
COPYSTORY_TOOLS="$COPYSTORY_ROOT/.build/artifacts/sparkle/Sparkle/bin"
[[ -x "$COPYSTORY_TOOLS/generate_appcast" ]] || { echo "Run swift package resolve to fetch pinned Sparkle tools." >&2; exit 1; }
export COPYSTORY_SIGNING_IDENTITY
scripts/build.sh
COPYSTORY_APP="$COPYSTORY_ROOT/.build/CopyStory.app"
COPYSTORY_PENDING="$(mktemp -d "$COPYSTORY_ROOT/.build/release-pending.XXXXXX")"
trap 'rm -rf "$COPYSTORY_PENDING"' EXIT
COPYSTORY_ARCHIVE="$COPYSTORY_PENDING/CopyStory-$COPYSTORY_VERSION.zip"
ditto -c -k --keepParent "$COPYSTORY_APP" "$COPYSTORY_ARCHIVE"
xcrun notarytool submit "$COPYSTORY_ARCHIVE" --keychain-profile "$COPYSTORY_NOTARY_PROFILE" --wait --output-format json > .build/notary-result.json
python3 - <<'PY'
import json
result = json.load(open('.build/notary-result.json'))
if result.get('status') != 'Accepted':
    raise SystemExit('Notarization was not accepted; see .build/notary-result.json')
PY
xcrun stapler staple "$COPYSTORY_APP"
scripts/verify-package.sh "$COPYSTORY_APP" --public
rm "$COPYSTORY_ARCHIVE"
ditto -c -k --keepParent "$COPYSTORY_APP" "$COPYSTORY_ARCHIVE"
"$COPYSTORY_TOOLS/generate_appcast" --account com.copystory.app.sparkle --maximum-deltas 0 --maximum-versions 1 \
    --download-url-prefix "https://github.com/fromOkayToGreat/CopyStory/releases/download/v$COPYSTORY_VERSION/" \
    "$COPYSTORY_PENDING"
"$COPYSTORY_TOOLS/sign_update" --account com.copystory.app.sparkle --verify "$COPYSTORY_PENDING/appcast.xml"
(cd "$COPYSTORY_PENDING" && shasum -a 256 "CopyStory-$COPYSTORY_VERSION.zip" appcast.xml > SHA256SUMS)
[[ "$(git rev-parse HEAD)" == "$COPYSTORY_COMMIT" && -z "$(git status --porcelain)" ]] || { echo "Source changed during release." >&2; exit 1; }
python3 scripts/release_policy.py manifest "$COPYSTORY_PENDING"
scripts/verify-stage.sh "$COPYSTORY_PENDING"
mkdir -p "$(dirname "$COPYSTORY_STAGE")"
mv "$COPYSTORY_PENDING" "$COPYSTORY_STAGE"
echo "Validated public release staged: $COPYSTORY_STAGE"
echo "Review release acceptance evidence, then use scripts/publish-release.sh."
