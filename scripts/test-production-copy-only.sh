#!/bin/bash
# Actual Production compile selection, synthetic injected effects only. No app launch.
set -euo pipefail
cd "$(dirname "$0")/.."
export COPYSTORY_PRODUCTION_TESTS=1 COPYSTORY_APP_STORE=1
unset COPYSTORY_SHIPPING_RECONSTRUCTION COPYSTORY_LEGACY_UPDATER
swift test --disable-xctest --filter AppStoreCopyOnlyTests "$@"
