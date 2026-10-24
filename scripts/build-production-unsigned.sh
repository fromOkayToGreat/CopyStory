#!/bin/bash
# Source preparation only: no signing, installation, launch or native effects.
set -euo pipefail
COPYSTORY_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$COPYSTORY_ROOT"
COPYSTORY_OUTPUT="${1:?Pass a fresh absolute output directory outside the source tree}"
[[ "$COPYSTORY_OUTPUT" = /* && ! -e "$COPYSTORY_OUTPUT" && "$COPYSTORY_OUTPUT" != "$COPYSTORY_ROOT"/* ]] || { echo "Use a fresh absolute output directory outside the source tree" >&2; exit 1; }
: "${DEVELOPER_DIR:?Set DEVELOPER_DIR to the full Xcode Developer directory for this command}"
mkdir -p "$COPYSTORY_OUTPUT/ModuleCache"
touch "$COPYSTORY_OUTPUT/ModuleCache/Session.modulevalidation"
COPYSTORY_REVISION="$(git rev-parse HEAD)"
COPYSTORY_DIRTY=clean
[[ -z "$(git status --porcelain --untracked-files=normal)" ]] || COPYSTORY_DIRTY=dirty
xcodebuild -project CopyStoryShipping.xcodeproj -target CopyStory -configuration Production \
  SYMROOT="$COPYSTORY_OUTPUT/Products" OBJROOT="$COPYSTORY_OUTPUT/Intermediates" \
  CLANG_MODULE_CACHE_PATH="$COPYSTORY_OUTPUT/ModuleCache" \
  CLANG_MODULES_BUILD_SESSION_FILE="$COPYSTORY_OUTPUT/ModuleCache/Session.modulevalidation" \
  COPYSTORY_SOURCE_REVISION="$COPYSTORY_REVISION" COPYSTORY_SOURCE_DIRTY="$COPYSTORY_DIRTY" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build >"$COPYSTORY_OUTPUT/build.log" 2>&1
python3 scripts/verify-production.py "$COPYSTORY_OUTPUT/Products/Production/CopyStory.app" >"$COPYSTORY_OUTPUT/verification.json"
echo "$COPYSTORY_OUTPUT/Products/Production/CopyStory.app"
