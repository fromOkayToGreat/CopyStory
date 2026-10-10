#!/bin/bash
# Explicit local install only; release/build commands never invoke this script.
set -euo pipefail
COPYSTORY_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
COPYSTORY_DESTINATION="${1:-$HOME/Applications/CopyStory.app}"
if [[ "$COPYSTORY_DESTINATION" != /* || "$COPYSTORY_DESTINATION" != *.app || -L "$COPYSTORY_DESTINATION" ]]; then
    echo "Usage: $0 [/absolute/path/CopyStory.app] (no symlink destination)" >&2
    exit 1
fi
if pgrep -x CopyStory >/dev/null; then
    echo "Quit CopyStory before installing a new build." >&2
    exit 1
fi
"$COPYSTORY_ROOT/scripts/build.sh"
mkdir -p "$(dirname "$COPYSTORY_DESTINATION")"
COPYSTORY_INSTALL_STAGE="$(mktemp -d "$(dirname "$COPYSTORY_DESTINATION")/.copystory-install.XXXXXX")"
COPYSTORY_BACKUP="$COPYSTORY_INSTALL_STAGE/Previous.app"
COPYSTORY_REPLACED=false
copystory_install_cleanup() {
    if [[ "$COPYSTORY_REPLACED" != true && -e "$COPYSTORY_BACKUP" && ! -e "$COPYSTORY_DESTINATION" ]]; then
        mv "$COPYSTORY_BACKUP" "$COPYSTORY_DESTINATION"
    fi
    if [[ -e "$COPYSTORY_BACKUP" && "$COPYSTORY_REPLACED" != true ]]; then
        echo "Previous app preserved for recovery: $COPYSTORY_BACKUP" >&2
    else
        rm -rf "$COPYSTORY_INSTALL_STAGE"
    fi
}
trap copystory_install_cleanup EXIT
# Verify a complete replacement first; never merge new files into an old bundle.
ditto "$COPYSTORY_ROOT/.build/CopyStory.app" "$COPYSTORY_INSTALL_STAGE/CopyStory.app"
"$COPYSTORY_ROOT/scripts/verify-package.sh" "$COPYSTORY_INSTALL_STAGE/CopyStory.app"
if pgrep -x CopyStory >/dev/null; then
    echo "CopyStory started during preparation. Quit it and retry." >&2
    exit 1
fi
if [[ -e "$COPYSTORY_DESTINATION" ]]; then
    [[ -d "$COPYSTORY_DESTINATION" ]] || { echo "Destination is not an app directory." >&2; exit 1; }
    mv "$COPYSTORY_DESTINATION" "$COPYSTORY_BACKUP"
fi
mv "$COPYSTORY_INSTALL_STAGE/CopyStory.app" "$COPYSTORY_DESTINATION"
if ! codesign --verify --deep --strict "$COPYSTORY_DESTINATION"; then
    mv "$COPYSTORY_DESTINATION" "$COPYSTORY_INSTALL_STAGE/Failed.app"
    echo "Installation verification failed; restoring the previous app." >&2
    exit 1
fi
COPYSTORY_REPLACED=true
echo "Installed: $COPYSTORY_DESTINATION"
echo "Open it in Finder to begin. Clipboard history and settings were not modified."
