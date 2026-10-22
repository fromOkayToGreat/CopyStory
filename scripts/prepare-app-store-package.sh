#!/bin/bash
# SwiftPM removes Package.resolved for a dependency-free manifest. Resolve the
# temporary store configuration in an ignored source copy, preserving the baseline lockfile.
set -euo pipefail
COPYSTORY_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
COPYSTORY_PACKAGE="$COPYSTORY_ROOT/.build/app-store-package"
mkdir -p "$COPYSTORY_PACKAGE"
rm -rf "$COPYSTORY_PACKAGE/Sources" "$COPYSTORY_PACKAGE/Tests"
cp "$COPYSTORY_ROOT/Package.swift" "$COPYSTORY_PACKAGE/Package.swift"
ditto "$COPYSTORY_ROOT/Sources" "$COPYSTORY_PACKAGE/Sources"
ditto "$COPYSTORY_ROOT/Tests" "$COPYSTORY_PACKAGE/Tests"
echo "$COPYSTORY_PACKAGE"
