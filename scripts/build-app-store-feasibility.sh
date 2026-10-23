#!/bin/bash
# Local sandbox feasibility only. No install, notarization, key export or submission.
set -euo pipefail
COPYSTORY_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$COPYSTORY_ROOT"
export COPYSTORY_APP_STORE=1
COPYSTORY_PACKAGE="$(scripts/prepare-app-store-package.sh)"
COPYSTORY_SCRATCH="$COPYSTORY_ROOT/.build/app-store-swift"
COPYSTORY_OUTPUT="$COPYSTORY_ROOT/.build/app-store-feasibility/CopyStory Sandbox.app"
COPYSTORY_SIGNING_IDENTITY="${COPYSTORY_SIGNING_IDENTITY:--}"
mkdir -p .build/app-store-feasibility
for COPYSTORY_ARCH in arm64 x86_64; do
    swift build --package-path "$COPYSTORY_PACKAGE" --scratch-path "$COPYSTORY_SCRATCH" -c release --triple "$COPYSTORY_ARCH-apple-macosx26.0" \
        -Xswiftc -file-prefix-map -Xswiftc "$COPYSTORY_ROOT=." -Xswiftc -gnone
    COPYSTORY_BIN="$(swift build --package-path "$COPYSTORY_PACKAGE" --scratch-path "$COPYSTORY_SCRATCH" -c release --triple "$COPYSTORY_ARCH-apple-macosx26.0" --show-bin-path)"
    cp "$COPYSTORY_BIN/CopyStory" ".build/app-store-feasibility/CopyStory-$COPYSTORY_ARCH"
done
COPYSTORY_TEMP="$(mktemp -d "$COPYSTORY_ROOT/.build/app-store-feasibility/bundle.XXXXXX")"
trap 'rm -rf "$COPYSTORY_TEMP"' EXIT
COPYSTORY_APP="$COPYSTORY_TEMP/CopyStory Sandbox.app"
mkdir -p "$COPYSTORY_APP/Contents/MacOS" "$COPYSTORY_APP/Contents/Resources/Licenses"
lipo -create .build/app-store-feasibility/CopyStory-arm64 .build/app-store-feasibility/CopyStory-x86_64 -output "$COPYSTORY_APP/Contents/MacOS/CopyStory"
cp LICENSE "$COPYSTORY_APP/Contents/Resources/Licenses/CopyStory-LICENSE"
python3 - "$COPYSTORY_APP" <<'PY'
import plistlib,sys,pathlib
p=plistlib.loads(pathlib.Path('Config/Info.plist').read_bytes())
p={k:v for k,v in p.items() if not k.startswith('SU')}
p.update(CFBundleIdentifier='com.copystory.sandbox-feasibility', CFBundleName='CopyStory Sandbox', CFBundleDisplayName='CopyStory Sandbox', CopyStorySandboxFeasibility=True)
(pathlib.Path(sys.argv[1])/'Contents/Info.plist').write_bytes(plistlib.dumps(p))
PY
COPYSTORY_TIMESTAMP=--timestamp
[[ "$COPYSTORY_SIGNING_IDENTITY" != - ]] || COPYSTORY_TIMESTAMP=--timestamp=none
codesign --force --options runtime "$COPYSTORY_TIMESTAMP" --sign "$COPYSTORY_SIGNING_IDENTITY" --entitlements Config/AppStore.entitlements "$COPYSTORY_APP"
python3 scripts/verify-app-store-feasibility.py "$COPYSTORY_APP"
# Replace only the generated feasibility bundle, never installed apps or prior release stages.
rm -rf "$COPYSTORY_OUTPUT"
mv "$COPYSTORY_APP" "$COPYSTORY_OUTPUT"
echo "Sandbox feasibility app: $COPYSTORY_OUTPUT"
echo 'Use --demo or --sandbox-probe. This is not an App Store submission artifact.'
