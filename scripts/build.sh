#!/bin/bash
set -euo pipefail
COPYSTORY_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
COPYSTORY_OUTPUT="$COPYSTORY_ROOT/.build/CopyStory.app"
COPYSTORY_SIGNING_IDENTITY="${COPYSTORY_SIGNING_IDENTITY:--}"
COPYSTORY_DEVELOPMENT="${COPYSTORY_DEVELOPMENT:-0}"
[[ "$COPYSTORY_DEVELOPMENT" == 0 || "$COPYSTORY_DEVELOPMENT" == 1 ]] || { echo "COPYSTORY_DEVELOPMENT must be 0 or 1." >&2; exit 1; }
if [[ "$COPYSTORY_DEVELOPMENT" == 1 && "$COPYSTORY_SIGNING_IDENTITY" != "-" ]]; then
    echo "The development exception is only permitted for ad-hoc local builds." >&2
    exit 1
fi
if [[ "$COPYSTORY_SIGNING_IDENTITY" == "-" && "$COPYSTORY_DEVELOPMENT" != 1 ]]; then
    echo "A strict ad-hoc app cannot load Sparkle under macOS library validation. Set COPYSTORY_SIGNING_IDENTITY to Developer ID, or explicitly use COPYSTORY_DEVELOPMENT=1 for local testing (updater disabled)." >&2
    exit 1
fi
cd "$COPYSTORY_ROOT"
mkdir -p .build/universal

# Explicit per-architecture SwiftPM builds also work with Command Line Tools.
# No development sources or build directory paths are copied into the app.
for COPYSTORY_ARCH in arm64 x86_64; do
    swift build --disable-automatic-resolution -c release --triple "$COPYSTORY_ARCH-apple-macosx26.0" \
        -Xswiftc -file-prefix-map -Xswiftc "$COPYSTORY_ROOT=." \
        -Xswiftc -gnone \
        -Xlinker -rpath -Xlinker @executable_path/../Frameworks
    COPYSTORY_BIN="$(swift build -c release --triple "$COPYSTORY_ARCH-apple-macosx26.0" --show-bin-path)"
    cp "$COPYSTORY_BIN/CopyStory" "$COPYSTORY_ROOT/.build/universal/CopyStory-$COPYSTORY_ARCH"
    lipo "$COPYSTORY_ROOT/.build/universal/CopyStory-$COPYSTORY_ARCH" -verify_arch "$COPYSTORY_ARCH"
done
COPYSTORY_FRAMEWORK="$COPYSTORY_ROOT/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
[[ -d "$COPYSTORY_FRAMEWORK" ]] || { echo "Missing pinned Sparkle framework; run swift package resolve." >&2; exit 1; }
COPYSTORY_STAGE="$(mktemp -d "$COPYSTORY_ROOT/.build/bundle.XXXXXX")"
trap 'rm -rf "$COPYSTORY_STAGE"' EXIT
COPYSTORY_APP="$COPYSTORY_STAGE/CopyStory.app"
mkdir -p "$COPYSTORY_APP/Contents/MacOS" "$COPYSTORY_APP/Contents/Frameworks" "$COPYSTORY_APP/Contents/Resources/Licenses"
lipo -create "$COPYSTORY_ROOT/.build/universal/CopyStory-arm64" \
    "$COPYSTORY_ROOT/.build/universal/CopyStory-x86_64" -output "$COPYSTORY_APP/Contents/MacOS/CopyStory"
strip -S "$COPYSTORY_APP/Contents/MacOS/CopyStory"
cp Config/Info.plist "$COPYSTORY_APP/Contents/Info.plist"
if [[ "$COPYSTORY_DEVELOPMENT" == 1 ]]; then
    /usr/libexec/PlistBuddy -c 'Add CopyStoryDevelopmentBuild bool true' "$COPYSTORY_APP/Contents/Info.plist"
fi
cp LICENSE "$COPYSTORY_APP/Contents/Resources/Licenses/CopyStory-LICENSE"
cp ThirdPartyNotices/Sparkle-LICENSE "$COPYSTORY_APP/Contents/Resources/Licenses/Sparkle-LICENSE"
ditto "$COPYSTORY_FRAMEWORK" "$COPYSTORY_APP/Contents/Frameworks/Sparkle.framework"

# Sign nested code inside-out, retaining Sparkle's entitlements. Do not use
# --deep for signing. Public/default signing retains library validation.
COPYSTORY_SIGN_FLAGS=(--force --options runtime --sign "$COPYSTORY_SIGNING_IDENTITY")
if [[ "$COPYSTORY_SIGNING_IDENTITY" == "-" ]]; then
    COPYSTORY_SIGN_FLAGS+=(--timestamp=none)
else
    COPYSTORY_SIGN_FLAGS+=(--timestamp)
fi
COPYSTORY_EMBEDDED="$COPYSTORY_APP/Contents/Frameworks/Sparkle.framework"
for COPYSTORY_COMPONENT in \
    "$COPYSTORY_EMBEDDED/Versions/B/XPCServices/Downloader.xpc" \
    "$COPYSTORY_EMBEDDED/Versions/B/XPCServices/Installer.xpc" \
    "$COPYSTORY_EMBEDDED/Versions/B/Autoupdate" \
    "$COPYSTORY_EMBEDDED/Versions/B/Updater.app" \
    "$COPYSTORY_EMBEDDED"; do
    codesign "${COPYSTORY_SIGN_FLAGS[@]}" --preserve-metadata=entitlements "$COPYSTORY_COMPONENT"
done
if [[ "$COPYSTORY_DEVELOPMENT" == 1 ]]; then
    codesign "${COPYSTORY_SIGN_FLAGS[@]}" --entitlements Config/Development.entitlements "$COPYSTORY_APP"
else
    codesign "${COPYSTORY_SIGN_FLAGS[@]}" "$COPYSTORY_APP"
fi
"$COPYSTORY_ROOT/scripts/verify-package.sh" "$COPYSTORY_APP"
rm -rf "$COPYSTORY_OUTPUT"
mv "$COPYSTORY_APP" "$COPYSTORY_OUTPUT"
echo "Built universal app: $COPYSTORY_OUTPUT"
if [[ "$COPYSTORY_SIGNING_IDENTITY" == "-" ]]; then
    echo "Local development build only. Use scripts/release.sh for public distribution."
    if [[ "$COPYSTORY_DEVELOPMENT" == 1 ]]; then
        echo "Explicit development exception: library validation disabled; in-app updater disabled."
    fi
fi
