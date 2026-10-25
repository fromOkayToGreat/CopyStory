# Menu-bar app mark

The production status button uses an 18-point, transparent AppKit template
image: two offset rounded squares within the app logo's counterclockwise arrow.
The back square omits occluded edges to retain separation at menu-bar size.
AppKit draws the paths at the display backing scale and supplies system tint.
The app icon resource, development status title, action handlers, menus, panel
activation and paste paths are unchanged.

## Offscreen preview and focused checks

From the repository root, with Xcode selected for this command:

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
preview_build="$(mktemp -d /tmp/copystory-status-preview.XXXXXX)"
cp scripts/preview-status-icon.swift "$preview_build/main.swift"
xcrun swiftc -module-cache-path "$preview_build/modules" \
  Sources/CopyStory/StatusItemIcon.swift "$preview_build/main.swift" \
  -o "$preview_build/render"
"$preview_build/render" "$preview_build/output"
```

This checks template/accessibility metadata, size, transparent corners,
monochrome pixels and useful occupied area at 1× and 2×, and writes the raw
transparent rasters plus a light/dark review sheet. The review sheet explicitly
applies synthetic black/white tint; actual status-button tint and selection
remain a runtime review item. The renderer creates no application, windows,
status item or clipboard access.

The local unsigned production build and production verifier passed. The
committed app icon retains SHA-256
`bb3bac3fd1d5e624cd7bda3c32415b3f5312ffbff1ed743b536afc3c2a75d58c`.
The installed TestFlight app was not launched, quit, installed over, or changed.
A new separately reviewed build is required to ship the status icon.
