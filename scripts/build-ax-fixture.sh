#!/bin/bash
# Synthetic target only; does not launch, request permissions or send events.
set -euo pipefail
COPYSTORY_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$COPYSTORY_ROOT"
COPYSTORY_FIXTURE='.build/app-store-feasibility/AX Fixture.app'
mkdir -p "$COPYSTORY_FIXTURE/Contents/MacOS"
swiftc scripts/sandbox/AXFixture.swift -o "$COPYSTORY_FIXTURE/Contents/MacOS/AXFixture"
python3 - "$COPYSTORY_FIXTURE" <<'PY'
import plistlib, pathlib, sys
p = {'CFBundleIdentifier':'com.copystory.ax-fixture', 'CFBundleName':'AX Fixture',
     'CFBundleExecutable':'AXFixture', 'CFBundlePackageType':'APPL'}
(pathlib.Path(sys.argv[1])/'Contents/Info.plist').write_bytes(plistlib.dumps(p))
PY
codesign -s - --force "$COPYSTORY_FIXTURE"
echo "$COPYSTORY_FIXTURE"
