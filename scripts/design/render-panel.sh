#!/bin/bash
set -euo pipefail
COPYSTORY_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$COPYSTORY_ROOT"
COPYSTORY_OUTPUT="${1:?Pass a fresh absolute fixture output directory}"
[[ "$COPYSTORY_OUTPUT" = /* && ! -e "$COPYSTORY_OUTPUT" ]] || { echo 'Output must be fresh and absolute' >&2; exit 1; }
: "${DEVELOPER_DIR:?Use full Xcode}"
# Builds only inert configuration. No production/development capability flags.
export COPYSTORY_SHIPPING_RECONSTRUCTION=1
scripts/test-development.sh > /tmp/copystory-design-offline-tests.log 2>&1
COPYSTORY_PRODUCTS="$COPYSTORY_ROOT/.build/out/Products/Debug"
COPYSTORY_OBJECTS=(.build/out/Intermediates.noindex/CopyStory.build/Debug/CopyStory-*-testable-t.build/Objects-normal/arm64/*.o)
COPYSTORY_LINK=()
for COPYSTORY_OBJECT in "${COPYSTORY_OBJECTS[@]}"; do
    [[ "$COPYSTORY_OBJECT" == */CopyStoryMain.o ]] || COPYSTORY_LINK+=("$COPYSTORY_OBJECT")
done
mkdir -p "$COPYSTORY_OUTPUT"
xcrun swiftc -parse-as-library -swift-version 5 -target arm64-apple-macosx26.0 \
    -I "$COPYSTORY_PRODUCTS" -I Sources/CSQLite \
    scripts/design/PanelPreview.swift "${COPYSTORY_LINK[@]}" "$COPYSTORY_PRODUCTS/CopyStoryCore.o" \
    -o "$COPYSTORY_OUTPUT/PanelPreview"
"$COPYSTORY_OUTPUT/PanelPreview" "$COPYSTORY_OUTPUT" "$COPYSTORY_ROOT/Resources/CopyStory.icns"
# A separately identified review app launches only this same inert fixture.
COPYSTORY_PREVIEW="$COPYSTORY_OUTPUT/CopyStory Design Preview.app/Contents"
mkdir -p "$COPYSTORY_PREVIEW/MacOS" "$COPYSTORY_PREVIEW/Resources"
cp "$COPYSTORY_OUTPUT/PanelPreview" "$COPYSTORY_PREVIEW/MacOS/PanelPreview"
cp Resources/CopyStory.icns "$COPYSTORY_PREVIEW/Resources/CopyStory.icns"
cat > "$COPYSTORY_PREVIEW/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.copystory.design-preview</string>
<key>CFBundleName</key><string>CopyStory Design Preview</string>
<key>CFBundleExecutable</key><string>PanelPreview</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleIconFile</key><string>CopyStory.icns</string>
<key>LSUIElement</key><true/>
</dict></plist>
PLIST
