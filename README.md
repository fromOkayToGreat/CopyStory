# CopyStory

App Store migration is in progress. See
[sandbox feasibility and the migration plan](docs/APP_STORE_MIGRATION.md).
The existing direct-download release documentation below is retained as baseline evidence.

[![Build and verify](https://github.com/fromOkayToGreat/CopyStory/actions/workflows/ci.yml/badge.svg)](https://github.com/fromOkayToGreat/CopyStory/actions/workflows/ci.yml)

CopyStory is a native, local clipboard history utility for macOS 26 and later.
It lives in the menu bar and remembers plain text and supported images for
searching, pinning, copying, and reuse in the previously active app.

CopyStory is [open source on GitHub](https://github.com/fromOkayToGreat/CopyStory)
under the [MIT license](LICENSE). The current development version is **0.3.0**.
Public, notarized app downloads are not available yet; the source can be built
locally. Follow [Releases](https://github.com/fromOkayToGreat/CopyStory/releases)
for future verified downloads. See [validation results](VALIDATION.md) and
[release acceptance](docs/RELEASING.md) for completed checks and remaining gates.

## Build and run

Requirements: macOS 26 or later, Xcode or Command Line Tools with a macOS 26+
SDK, Swift 6, Git, and Python 3 for packaging checks. The UI follows native
macOS Liquid Glass. Swift Package Manager downloads the pinned Sparkle updater;
SQLite and Apple frameworks come from macOS.

```sh
git clone https://github.com/fromOkayToGreat/CopyStory.git
cd CopyStory
./scripts/test.sh
COPYSTORY_DEVELOPMENT=1 ./scripts/build.sh
```

The build script creates `.build/CopyStory.app` and prints its path. Development mode uses an ad-hoc signature and a deliberate **development-only
library-validation exception** so Sparkle can load locally. Updates are disabled
in these builds. Public builds require Developer ID, full library validation,
and notarization; the release verifier rejects development bundles. See
[the release runbook](docs/RELEASING.md).

To install a local build explicitly, quit CopyStory first, then run:

```sh
COPYSTORY_DEVELOPMENT=1 ./scripts/install.sh
open "$HOME/Applications/CopyStory.app"
```

An absolute destination may be supplied to the installer. It does not grant
macOS permissions. Rebuilding an ad-hoc app can require renewing Accessibility
permission for that exact copy. Use a stable installation location for launch
at login. Do not run multiple copies against the same history.

For a preview, run `open -n .build/CopyStory.app --args --demo`. Preview mode uses a temporary
synthetic history and disables capture, clipboard writes, login registration,
and updates. Tests use named pasteboards, temporary stores, and isolated
preferences. They do not clear the installed app's history.

## Updates

**Automatic checks and downloads start off.** In Preferences → Updates, choose
whether to check automatically and whether to download/install automatically,
or select **Check for Updates…** for a one-time check. Until the first signed
release is published, checks may report that the release feed is unavailable.
The installed 0.2.0 app predates this updater and needs one manual installation
of the first verified updater-enabled release.

[Sparkle](https://sparkle-project.org/) handles update UI, downloads, signature
verification, replacement, and relaunch. The app requires a signed HTTPS feed,
verifies signed archives before extraction, and rejects older or equal builds.
A failed check does not clear history or change capture preferences. Update
checks contact GitHub; clipboard contents are never sent. See
[update trust and recovery](docs/UPDATES.md).

## First launch

Onboarding explains local retention, the keyboard shortcut, and ordinary
copied secrets. Recording begins after onboarding is completed. Launch at login
is selected by default in onboarding; its actual registration/approval state
appears in preferences.

Grant Accessibility permission to CopyStory if you want automatic pasting. Use
the app's Accessibility settings action, then enable the installed CopyStory
in macOS settings. Recording and manual copy remain available without this
permission. macOS may separately request clipboard-reading access; if denied,
recording cannot read the general clipboard. These permissions serve different
purposes.

CopyStory does not request Full Disk Access, microphone, camera, screen
recording, or broad keyboard-monitoring access.

## Everyday use

| Action | Control |
| --- | --- |
| Open or toggle history | **Command–Shift–H** or menu-bar icon |
| Search | Type in the search field |
| Move selected item | Up / Down |
| Request paste into previous app | Return, double-click, or context menu → Paste |
| Copy selected item without automatic paste | Command–C |
| Close without pasting | Escape or click outside |
| Pin / unpin selected item | Command–P or context menu |
| Inspect selected item | Command–I or context menu |
| Delete selected item | Command–Delete or context menu |
| Pause recording | Visible pause control |

Search uses case-insensitive partial matches in stored text, source-app names,
and indexed dates. Use the Text, Images, or Pinned filter to narrow the list.
Image contents are not OCR-searchable. Text is stored without rich formatting; whitespace,
line breaks, and Unicode are retained. The full-content preview shows text
beyond the truncated list preview.

CopyStory places a chosen item's payload on the system clipboard, closes the
panel, restores the prior destination where possible, and requests one standard
paste only after that app becomes active and the original window and focused
element are verified again. If either identity is unavailable or changes,
CopyStory falls back to manual copy. A sent paste request does not prove
that the destination inserted the content. If permission or focus restoration
is unavailable, the item stays copied for manual **Command–V**. The destination
must accept the payload type.

Preferences include the global shortcut, launch-at-login status, history
limits, optional age expiration, app exclusions, marker protection, Accessibility status, storage usage, clear-history
controls, version, updates, and a link to the public source repository.

## Prompt library

Switch to **Library** in the same panel to find reusable text snippets and prompts.
Search matches titles and full template text; favorites appear first. **New prompt**
(or **Command–N** in Library) opens the editor. History items containing text offer
**Save to Library…** in their context menu; the saved template is independent of history.

Use `{{topic}}` placeholders to create fields automatically. Each field can be
multiline text or a dropdown with one option per line and a saved default.
Repeated names share one field; names are case-sensitive. Escape a literal
placeholder as `\{{name}}`. Templates only substitute text; they execute no code.

Return or double-click opens the prompt's form and completed-text preview. Fill
all fields, then choose **Copy** (keeps the form open) or **Paste / Command–Return**.
Every new use starts with saved defaults. Changes in the form do not edit them;
use **Edit…** or **Command–E** in Library to change the saved template.

Completed prompts enter ordinary history after successful clipboard writes while
recording is active, subject to the current exclusions, retention, and capacity.
Identical output is deduplicated. A failed direct paste keeps the completed text
copied for manual pasting. CopyStory never submits a prompt to an AI service.

Saved prompts stay until explicitly deleted. Favorites, templates, defaults, and
options persist locally in `Library/library.sqlite`, independently of history's
storage budget and expiration. Clearing history does not clear the library.
There is no cloud sync, text expansion outside CopyStory, or credential storage.

## Storage and privacy

History is saved under:

```text
~/Library/Application Support/CopyStory/
```

Text and metadata are stored in SQLite; images and thumbnails use separate
files. History persists across quitting and restarting. Preferences use macOS
UserDefaults for the `com.copystory.app` bundle. The history folder and files
are restricted to the current user, but **the contents are not encrypted by
CopyStory**. Software running as that user, an administrator, or a backup with
access to the data may be able to read it.

Preferences can expire unpinned history after 1, 7, 30, or 90 days. Existing
installations keep indefinite retention until a period is explicitly applied.
Pins never expire. Expiration runs at startup, each capture, and every minute
while the app is running. Applying a period can immediately remove old items.

App exclusions skip future clipboard captures while a listed app is frontmost;
Apple Passwords is excluded by default. Add other apps in Preferences. App
attribution is best effort: a password-manager browser extension appears as
its browser, and background producers may not be identifiable. Exclusions do
not delete previously captured items or replace pausing before copying secrets.

CopyStory has no account, analytics, or cloud sync. Optional update checks and
downloads connect to GitHub using Sparkle; history remains on this Mac.
It does not execute copied text or log clipboard contents. CopyStory's own
clipboard writes disable Universal Clipboard propagation. Clipboard writes by
other apps and system backups are outside CopyStory's control.

Confidential, transient, and automatically generated clipboard markers are
respected by default. **Unmarked passwords, tokens, and other secrets can still
enter history.** Pause before copying material you do not want retained, and
delete unwanted saved items. Pausing stops new capture; it does not delete
existing history. See [privacy and storage details](docs/PRIVACY.md).

The defaults are **1,000 items** and **500 MB** (500,000,000 bytes). Oldest
unpinned entries are removed when a limit is exceeded. Pins count toward both
limits and are protected from automatic removal. If protected items leave no
capacity, unpin/delete items or increase the limit. An individual item too
large for the budget is rejected without evicting the existing history.
Preferences allow 1–100,000 items and 10–50,000 MB; lowering a limit can remove
old unpinned history after you confirm the change.

Deleting an item removes its saved image payload and thumbnail. Clear
unpinned history preserves pins; clear all requires confirmation. Deletion
does not promise forensic secure erasure or removal from backups or the system
clipboard.

## Limitations

- Runtime acceptance is incomplete. Local checks used Apple silicon/macOS
  27.0.1; CI ran isolated tests and package smoke checks on Apple silicon/macOS
  26.6.2. Intel and macOS 26.0 runtime behavior, full VoiceOver/Reduce
  Transparency acceptance, login behavior and network observation remain
  unverified. A universal build does not establish those results. See the
  [dated acceptance record](docs/RELEASE_ACCEPTANCE_2026-10-11.md).

- Clipboard polling can miss intermediate values copied very rapidly. It does
  not import content that was already on the clipboard before capture starts.
- Source-app attribution is best effort; the general clipboard does not supply
  a reliable originating-app identity for every item.
- Files/folders, audio/video, separate HTML/rich-text history, image OCR,
  animation, batch pasting, accounts, and sync are outside this release.
- Only supported clipboard image data is captured. A Finder file reference
  alone is not image-file history.
- System focus rules, Spaces, secure fields, and the destination app may limit
  direct pasting. Manual copy remains the fallback.
- Image and text resource caps may reject an item even if the overall history
  budget has room. See [privacy and storage details](docs/PRIVACY.md).
- A local ad-hoc build still needs user-granted permissions and real login
  testing. Public distribution needs an appropriate signing/notarization flow.

## Troubleshooting and removal

If the shortcut is unavailable, open via the menu bar and choose another
shortcut in preferences. If recording stops, check pause state, capacity,
clipboard permission, and any status message. If automatic paste fails, check
Accessibility for the exact installed copy and try manual Command–V.

To uninstall, disable launch at login in preferences, quit CopyStory, then move
the installed app to Trash. History is retained separately. If you also want to
remove it, clear all history first, or remove the `CopyStory` Application
Support folder after quitting. Do not remove that folder while the app is
running. System backups may retain earlier copies.

## Source layout

- `Sources/CopyStoryCore`: storage, search, deduplication, and retention.
- `Sources/CopyStory`: native UI, capture, hotkey, paste, and login integration.
- `Sources/CSQLite`: system SQLite module bridge.
- `Tests/CopyStoryCoreTests`: isolated core tests using synthetic data.
- `Tests/CopyStoryPlatformTests`: named-pasteboard, hotkey, image, and model tests.
- `scripts`: local build, automated test runner, and optional installation.

Sparkle is pinned to 2.10.0. Its complete license and bundled component notices
are included in [ThirdPartyNotices](ThirdPartyNotices/README.md) and the packaged
app. Apple platform frameworks and system SQLite retain their respective terms.
See [CONTRIBUTING](CONTRIBUTING.md) and [SECURITY](SECURITY.md) before filing a report.
