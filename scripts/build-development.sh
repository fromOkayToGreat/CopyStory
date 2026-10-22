#!/bin/bash
# Build only. Never installs, launches, reads clipboard contents or changes consent.
set -euo pipefail
COPYSTORY_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$COPYSTORY_ROOT"
COPYSTORY_OUTPUT="${1:?Pass a fresh absolute output directory outside the source tree}"
[[ "$COPYSTORY_OUTPUT" = /* && ! -e "$COPYSTORY_OUTPUT" ]] || { echo "Use a fresh absolute output directory" >&2; exit 1; }
mkdir -p "$COPYSTORY_OUTPUT/ModuleCache"
touch "$COPYSTORY_OUTPUT/ModuleCache/Session.modulevalidation"
COPYSTORY_REVISION="$(git rev-parse HEAD)"
COPYSTORY_DIRTY=clean
[[ -z "$(git status --porcelain --untracked-files=normal)" ]] || COPYSTORY_DIRTY=dirty
: "${DEVELOPER_DIR:?Set DEVELOPER_DIR to the full Xcode Developer directory for this command}"
xcodebuild -project CopyStoryShipping.xcodeproj -target CopyStory -configuration Debug \
  -xcconfig Config/Development.xcconfig \
  SYMROOT="$COPYSTORY_OUTPUT/Products" OBJROOT="$COPYSTORY_OUTPUT/Intermediates" \
  CLANG_MODULE_CACHE_PATH="$COPYSTORY_OUTPUT/ModuleCache" \
  CLANG_MODULES_BUILD_SESSION_FILE="$COPYSTORY_OUTPUT/ModuleCache/Session.modulevalidation" \
  COPYSTORY_SOURCE_REVISION="$COPYSTORY_REVISION" COPYSTORY_SOURCE_DIRTY="$COPYSTORY_DIRTY" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build >"$COPYSTORY_OUTPUT/build.log" 2>&1
COPYSTORY_APP="$COPYSTORY_OUTPUT/Products/Debug/CopyStory Development.app"
# Local ad-hoc signature supplies the declared sandbox entitlement; no identity,
# credentials, profile, hardened-runtime exception or user settings are changed.
codesign --force --sign - --options runtime --entitlements Config/AppStore.entitlements "$COPYSTORY_APP" >"$COPYSTORY_OUTPUT/sign.log" 2>&1
python3 scripts/verify-development.py "$COPYSTORY_APP" >"$COPYSTORY_OUTPUT/verification.json"
shasum -a 256 "$COPYSTORY_APP/Contents/MacOS/CopyStory Development" >"$COPYSTORY_OUTPUT/executable.sha256"
echo "$COPYSTORY_APP"
