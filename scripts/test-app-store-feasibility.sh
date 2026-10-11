#!/bin/bash
# Run model/core tests compiled without Sparkle; this is not a sandbox runtime test.
set -euo pipefail
COPYSTORY_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$COPYSTORY_ROOT"
export COPYSTORY_APP_STORE=1
COPYSTORY_PACKAGE="$(scripts/prepare-app-store-package.sh)"
COPYSTORY_TEST_PLUGIN="$(xcode-select -p)/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib"
COPYSTORY_ARGS=(--package-path "$COPYSTORY_PACKAGE" --scratch-path "$COPYSTORY_ROOT/.build/app-store-tests" --disable-xctest)
if [[ -f "$COPYSTORY_TEST_PLUGIN" ]]; then
    COPYSTORY_ARGS+=(-Xswiftc -load-plugin-library -Xswiftc "$COPYSTORY_TEST_PLUGIN")
fi
swift test "${COPYSTORY_ARGS[@]}" "$@"
