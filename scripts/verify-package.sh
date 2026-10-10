#!/bin/bash
set -euo pipefail
COPYSTORY_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
COPYSTORY_APP="${1:-$COPYSTORY_ROOT/.build/CopyStory.app}"
COPYSTORY_MODE="${2:---development}"
[[ "$COPYSTORY_MODE" == "--development" || "$COPYSTORY_MODE" == "--public" ]] || exit 2
python3 "$COPYSTORY_ROOT/scripts/release_policy.py" bundle "$COPYSTORY_APP" "$COPYSTORY_MODE"
codesign --verify --deep --strict --all-architectures "$COPYSTORY_APP"
if [[ "$COPYSTORY_MODE" == "--public" ]]; then
    xcrun stapler validate "$COPYSTORY_APP"
    spctl --assess --type execute --verbose=2 "$COPYSTORY_APP"
fi
echo "Package verified ($COPYSTORY_MODE)."
