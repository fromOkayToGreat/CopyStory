#!/bin/bash
set -euo pipefail
COPYSTORY_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
COPYSTORY_DEVELOPER="$(xcode-select -p)"
COPYSTORY_TEST_PLUGIN="$COPYSTORY_DEVELOPER/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib"
cd "$COPYSTORY_ROOT"
if [[ -f "$COPYSTORY_TEST_PLUGIN" ]]; then
    swift test --disable-xctest -Xswiftc -load-plugin-library -Xswiftc "$COPYSTORY_TEST_PLUGIN" "$@"
else
    swift test --disable-xctest "$@"
fi
