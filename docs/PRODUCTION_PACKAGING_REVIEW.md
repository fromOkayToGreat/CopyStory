# Production resource packaging review

Based on reviewed production commit `a60278d0d92d0ed885cc08baa100a9b008d8cca9`.
Initial packaging head: `01f4ea59693fb54240f7ead8b4f6c83597f84bcd`.
This unit adds resources and a narrow ancestor-metadata API correction; build 0
remains unallocated.

## Icon

`Resources/CopyStory.icns` is the owner's existing cleaned icon, copied without
pixel changes. SHA-256:
`ece54cb1e50576c50c98543e63fc0e3b6a2b3643f6b735e42aa1989b909e4623`.
Native `iconutil` extraction yields all ten macOS representations, from 16 to
1024 raster pixels; decoded RGBA matches the reviewed iconset for each image.
The retained flat artwork includes its original highlights and rounded tile.
`CFBundleIconFile` points to this resource in the production plist.

## Required-reason API audit

Checked the application and in-repository core sources against Apple's current
[API categories and approved reasons](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype)
and [required-reason guidance](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api)
on 2026-10-24. The production Xcode target links CopyStoryCore statically and
uses system SQLite/frameworks; it does not package Sparkle or another third-party
SDK. The legacy SwiftPM Sparkle path is outside this production package.

| Category | Reason | Source evidence and purpose |
| --- | --- | --- |
| UserDefaults | `CA92.1` | `AppModel.swift` initializer and preference setters read/write app-owned onboarding, pause, capacity, retention, exclusions and shortcut/direct-paste settings. `AppDistribution.swift` supplies current-app defaults for development. No MDM, app-group or other-app preferences are requested. |
| SystemBootTime | `35F9.1` | `CopyStoryApp.swift` supplies uptime to `PanelActivationEnvironment`; `PanelActivationGate.swift` measures local activation deadlines. `NativePasteAdapter.swift` supplies uptime to request observations for local request expiry. These clocks enable app timers/elapsed-event decisions; no off-device reporting is implemented. |
| FileTimestamp | `C617.1` | `StoreFiles.swift` calls `lstat` for local store existence, ownership/type/link checks and file sizes; `HistoryStore.swift` uses it during orphan recovery. The API is listed even though timestamp fields are not consumed. The reason covers metadata used to maintain files in the app container. |

Independent review corrected the initial ancestor-coverage interpretation:
`C617.1` does not authorize direct `lstat` access to ancestors outside the app
container. `StoreFiles.prepareDirectory` now obtains ancestor attributes using
[`FileManager.attributesOfItem(atPath:)`](https://developer.apple.com/documentation/foundation/filemanager/attributesofitem(atpath:)),
consuming only `.type` and `.ownerAccountID`. Apple documents that this method
reports the symbolic link itself; no link resolution is added. This Foundation
method and these two keys are not on Apple's current required-reason list;
`.creationDate` and `.modificationDate` are not consumed. This is a change to the
API appropriate for the actual metadata, not a wrapper around the listed call.

The loop still checks the same paths, skips failed metadata lookups as before,
rejects non-directories except the same root-owned fixed `/var` and `/tmp`
symlink targets, and retains the final directory owner/type/permission checks.
The remaining direct `lstat` calls operate on the app store directory/files and
image recovery entries within the container, supporting `C617.1`. No reason was
added for unrelated external files. The icon and manifest bytes are unchanged.

No available-disk-space or active-keyboard required-reason APIs were found in
the production sources. Settled history byte accounting uses local file sizes,
not device free capacity. There is no external SDK in this target whose separate
manifest must be copied. System framework internals are not app SDK declarations.

The manifest contains only `NSPrivacyAccessedAPITypes`. UserDefaults usage is not
proof of collection. Collection/tracking keys and domains are deliberately not
asserted by this bounded API audit; App Store privacy answers remain a separate
release review.

## Packaging and validation

The deterministic Xcode project generator puts both files in Copy Bundle
Resources. Reconstruction/development exclude them through the base xcconfig;
Production explicitly clears that exclusion. Their plists and runtime gates
remain unchanged. SwiftPM has no new resources or dependencies.

`verify-production.py` verifies the processed icon metadata, approved icon hash,
exact manifest categories/reasons, and byte equality of both packaged resources
against source. Source hygiene allows only this exact reviewed binary icon hash.
Validation passed: unsigned production compile/static verification; 185 offline
tests in 15 suites using `scripts/test-development.sh --build-system native`;
unsigned development and reconstruction builds with only `LICENSE` in their
Resources directories and no icon metadata; plist syntax, source hygiene, native
gates, deterministic project regeneration, and whitespace checks. All ten native
ICNS extractions match the reviewed RGBA pixels.

The default SwiftPM build engine initially attempted to sign a generated test
bundle and failed on file-provider metadata. No app signing step ran; the final
offline suite used the native engine, which avoids that test-bundle signing step.
Neither the unsigned bundle nor these checks establish signing, runtime icon
appearance, DirectPaste acceptance, App Store validation or submission approval.

## Independent-review correction verification

After replacing only the ancestor loop's metadata lookup, all 34 existing tests
in HistoryStoreTests and LibraryStoreTests passed using SwiftPM's native engine.
These include owner-only permissions, symlink database/directory admission and
image-recovery target preservation. Unsigned Production, Development and
Reconstruction builds passed again. The production packaging verifier passed;
the icon and manifest remain byte-identical to initial packaging head
`01f4ea59693fb54240f7ead8b4f6c83597f84bcd`. Manifest/plist syntax, source hygiene,
native source gates and whitespace checks passed. No tests or fixtures were
added, and no signing, install, launch, push or PR12 modification was performed
for this correction.
