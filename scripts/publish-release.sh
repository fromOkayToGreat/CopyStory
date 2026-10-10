#!/bin/bash
# Publish only an already staged and independently reverified release.
set -euo pipefail
COPYSTORY_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$COPYSTORY_ROOT"
COPYSTORY_STAGE="${1:?Usage: publish-release.sh /absolute/stage /absolute/release-notes.md [--first-release]}"
COPYSTORY_NOTES="${2:?Provide reviewed release notes}"
shift 2
[[ "$COPYSTORY_STAGE" == /* && "$COPYSTORY_NOTES" == /* && -f "$COPYSTORY_NOTES" ]] || { echo "Use absolute stage and release-notes paths." >&2; exit 1; }
[[ -z "$(git status --porcelain)" ]] || { echo "Publishing requires a clean checkout." >&2; exit 1; }
scripts/verify-stage.sh "$COPYSTORY_STAGE"
python3 scripts/check-release-history.py "$@"
COPYSTORY_VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Config/Info.plist)"
COPYSTORY_TAG="v$COPYSTORY_VERSION"
COPYSTORY_COMMIT="$(git rev-parse HEAD)"
COPYSTORY_REPOSITORY="fromOkayToGreat/CopyStory"
# Require the exact reviewed commit already on remote main. Never publish local-only code.
[[ "$(gh api "repos/$COPYSTORY_REPOSITORY/commits/main" --jq .sha)" == "$COPYSTORY_COMMIT" ]] || { echo "HEAD must match public main." >&2; exit 1; }
if git show-ref --verify --quiet "refs/tags/$COPYSTORY_TAG"; then
    [[ "$(git rev-list -n 1 "$COPYSTORY_TAG")" == "$COPYSTORY_COMMIT" ]] || { echo "Tag points to a different commit." >&2; exit 1; }
else
    git tag -a "$COPYSTORY_TAG" "$COPYSTORY_COMMIT" -m "CopyStory $COPYSTORY_VERSION"
fi
git push origin "refs/tags/$COPYSTORY_TAG"
# A draft is intentionally left recoverable if upload fails. Never overwrite assets.
gh release create "$COPYSTORY_TAG" --repo "$COPYSTORY_REPOSITORY" --verify-tag --draft \
    --title "CopyStory $COPYSTORY_VERSION" --notes-file "$COPYSTORY_NOTES" \
    "$COPYSTORY_STAGE/CopyStory-$COPYSTORY_VERSION.zip" "$COPYSTORY_STAGE/appcast.xml" \
    "$COPYSTORY_STAGE/SHA256SUMS" "$COPYSTORY_STAGE/release-manifest.json"
COPYSTORY_REMOTE="$(mktemp -d "$COPYSTORY_ROOT/.build/remote-release.XXXXXX")"
trap 'rm -rf "$COPYSTORY_REMOTE"' EXIT
gh release download "$COPYSTORY_TAG" --repo "$COPYSTORY_REPOSITORY" --dir "$COPYSTORY_REMOTE"
scripts/verify-stage.sh "$COPYSTORY_REMOTE"
gh release edit "$COPYSTORY_TAG" --repo "$COPYSTORY_REPOSITORY" --draft=false --latest
# Verify the public endpoint now serves the exact signed feed we staged.
curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 \
    "https://github.com/$COPYSTORY_REPOSITORY/releases/latest/download/appcast.xml" -o "$COPYSTORY_REMOTE/public-appcast.xml"
cmp "$COPYSTORY_STAGE/appcast.xml" "$COPYSTORY_REMOTE/public-appcast.xml"
echo "Published and verified: https://github.com/$COPYSTORY_REPOSITORY/releases/tag/$COPYSTORY_TAG"
