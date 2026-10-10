# Privacy, storage, and security boundaries

CopyStory retains a local history of clipboard text and supported images. That
history is useful precisely because it outlives the system clipboard and app
restarts. Consider every saved item a file on your Mac, not a temporary buffer.

## What is recorded

Supported copy events may contain plain text, an image, or an image with
associated text. The store also keeps a timestamp, available source-app name
and bundle identifier, dimensions, a thumbnail, and pinned state. Source-app
identity is best effort, inferred at capture time.

The app records while running, after onboarding. It skips unsupported/empty
content, its own clipboard writes, paused periods, and locked-session capture.
It does not backfill clipboard contents from before recording began. Polling
can miss clipboard values replaced between observations.

By default, clipboard types that mark content confidential, transient, or
automatically generated are skipped. This relies on the producing app marking
its data. There is no secret detector: an ordinary copied password, token,
private message, or key can be saved if unmarked. Turning off confidential
marker protection allows those marked secrets to be retained too. Transient,
automatically generated, and CopyStory-owned writes remain excluded.

App exclusions are checked before clipboard content is read or images are
decoded. Apple Passwords is excluded by default; Preferences can add or remove
apps. Changing the list invalidates pending image work, and queued saves check
the current exclusion list. This uses the frontmost app at observation time,
not authenticated producer identity. Browser extensions and background apps
can evade source attribution. Existing history is not deleted by exclusions.

Pause before copying sensitive material. Pausing leaves previous history in
place. Delete unwanted history separately. Quitting stops capture but also
retains history for the next launch.

## Permissions

Accessibility allows CopyStory to restore a destination window where possible
and request the standard paste keyboard action. It is not required to save
history or copy a selected item back to the system clipboard. CopyStory checks
the permission, original window and original focused element before requesting
paste. Missing or changed identities cause manual-copy fallback. The destination app
decides whether and where to insert it.
These checks narrow accidental destination changes; macOS does not provide an
atomic focus-check-and-paste operation, so a final scheduling race remains.

macOS clipboard-read access is separate. The OS can ask before allowing
programmatic reads or deny them according to the per-app setting; the
[`NSPasteboard.accessBehavior` API](https://developer.apple.com/documentation/appkit/nspasteboard/accessbehavior-swift.property)
reports that policy. A blocked read cannot be bypassed by granting Accessibility.

Launch at login uses macOS Service Management. Registration can require a user
decision before the app is eligible to run; approval can also be revoked. The
app reports the system state rather than treating registration alone as proof
of startup. See Apple's
[`SMAppService.Status.requiresApproval`](https://developer.apple.com/documentation/servicemanagement/smappservice/status-swift.enum/requiresapproval).

The app does not need Full Disk Access, microphone, camera, screen recording,
or broad keyboard-monitoring permissions for its implemented features.

## Where data lives

The normal history root is `~/Library/Application Support/CopyStory/`:

```text
CopyStory/
├── history.sqlite          text, metadata, search data
├── .store-lock             single-process store lock
└── Images/
    ├── <UUID>.image        saved image payload
    └── <UUID>.thumb.png    browsing thumbnail
```

SQLite may also create a temporary transaction journal in the history root.
Preferences use macOS UserDefaults under the app's bundle
identifier, `com.copystory.app`.

The app restricts history directories to owner access and files to owner read/
write. These permissions help separate different local user accounts. They do
not isolate history from software running as the same user, privileged software,
or backups with access to the files.

**There is no application-level encryption.** The app does not hold an
encryption key, claim end-to-end encryption, or guarantee secrecy against
someone with access to your logged-in account. Disk encryption and backup
protection are macOS/user-managed choices, outside CopyStory's implementation.

CopyStory does not upload history, synchronize with a server, run analytics,
fetch remote image content, or execute copied commands. When you request a manual update check or opt into automatic checks, Sparkle
connects over HTTPS to the project release feed on GitHub. Update downloads use
GitHub release assets and its delivery infrastructure. GitHub receives standard
network metadata such as IP address, request timing, and updater/app version
headers. No clipboard contents, source-app history, or history identifiers are
attached to those requests. Sparkle system profiling is disabled. Automatic
checks and downloads start off and can be changed in Preferences. Developer
preview mode disables updates. Opening the source link launches your browser.
See [update trust and controls](UPDATES.md). CopyStory's own clipboard writes use
`NSPasteboard.ContentsOptions.currentHostOnly` to disable Universal Clipboard
propagation for those writes. Other apps' clipboard writes, operating-system
services, and backups are outside this claim.

## Retention and deletion

The initial budget is 1,000 records and 500,000,000 bytes (500 decimal MB).
Both limits include pinned content. Oldest unpinned items are the candidates
for automatic removal. An individual item that cannot fit the budget is
rejected before existing history is evicted to accommodate it.

Pins protect content from automatic removal. If you reduce a limit below the
amount occupied by pins, those pins remain. New items cannot be saved until
you free capacity or increase the limit. The configured limit therefore does
not authorize deleting pinned material.

The byte limit is a limit on settled history storage. It includes the SQLite
database, indexes, duplicated searchable text, image payloads, and thumbnails.
Reported total usage reads the database and image-file sizes; pinned byte usage
is an estimate that includes a proportional share of database space. The
implementation uses full auto-vacuum and a delete-mode rollback journal.
Transient journals, filesystem
allocation overhead, preferences, app binaries, and source files are outside
that settled history accounting.

Atomic file replacement and database transactions may temporarily need extra
working space. A disk with no spare capacity can still cause a save to fail.

Deleting an image removes its payload and thumbnail along with its record.
Clear unpinned history retains pinned records. Clear all includes pins and asks
for confirmation. Clearing history does not clear the current system clipboard,
delete another app's pasted copy, or remove a system/cloud backup of the history
folder. Deleted bytes may remain recoverable in filesystem snapshots or disk
media. **Deletion is not forensic secure erasure.**

Optional expiration removes unpinned text, metadata, image payloads and
thumbnails older than 1, 7, 30 or 90 days. It uses the most recent capture time;
copying the same item again refreshes its age. Pins are always preserved.
Cleanup runs on startup, before capture, and once per minute while running.
A delayed capture already older than the active cutoff is rejected. Expiration
is off until explicitly applied and cannot undo deletion or erase backups.

## Untrusted data and failure handling

Clipboard data is untrusted input. Images are decoded using system frameworks
with limits on encoded size and pixel dimensions. Invalid and oversized data
is rejected; larger overall history limits do not remove per-item resource
caps. Plain text is stored as data and is not evaluated as a command or program.

The store uses SQL parameters for clipboard text, database transactions for
record changes, and atomic file writes. Image filenames come from validated
record UUIDs. Existing store files must be owned by the current user and must
not be symlinks or multiply linked files; store-directory ancestors must be
directories. These checks are defenses against accidental/unsafe paths, not
isolation from a malicious process already running as your user.

At startup, the store checks database integrity, removes records whose image
payloads are missing or invalid, regenerates absent/damaged thumbnails when
the payload is usable, and removes unreferenced image files. A damaged database
or unsupported schema prevents opening history; the app reports a startup
failure rather than silently replacing it with an empty store. A process lock
prevents two CopyStory processes from opening the same history concurrently.
Recovery behavior is covered by the automated tests and
[manual test plan](MANUAL_TESTING.md); consult
[the validation report](../VALIDATION.md) for results actually observed.

Diagnostic messages describe failure categories and do not include clipboard
contents. Do not attach your real history database or payloads to a bug report.
Prefer a reproduction with synthetic text/images, the macOS and app versions,
permission state, and a description of the failed action.

## Capture resource limits

These limits use decimal bytes and apply even when preferences allow a larger
history budget:

| Input | Cap |
| --- | --- |
| Plain text | 32,000,000 UTF-8 bytes |
| Encoded input image / normalized output image | 100,000,000 bytes each |
| Image dimensions | 16,384 pixels per side; 32,000,000 pixels total |
| Stored thumbnail | 320-pixel longest edge; 1,000,000 encoded bytes |

The capture path recognizes PNG, TIFF, JPEG, HEIC, GIF, BMP, and WebP clipboard
types when ImageIO can decode them. It normalizes the first frame to PNG and
applies orientation. Transparency is retained where supported; animation,
original compression, and all original image metadata are not preserved.

Clipboard providers can allocate data while fulfilling a read before CopyStory
can check the returned byte count. These caps bound accepted data and decoding;
they are not a guarantee of a fixed process memory ceiling. Image decoding runs
outside the main UI actor. A 0.5-second polling interval observes clipboard
changes, with a small timer tolerance.

Lock handling combines screen-lock notifications, session activation, sleep/
wake events, and a session-state snapshot. Some screen-lock signals are not
documented as public notification constants; real lock/unlock testing remains
part of acceptance and should be repeated on supported macOS releases.

## Distribution

The [public repository](https://github.com/fromOkayToGreat/CopyStory) contains
MIT-licensed source, an issue tracker, tests, and release tooling. Explicit development builds
are ad-hoc signed with a development-only library-validation exception and
updates disabled; public app downloads require Developer ID signing, full
library validation, and notarization. No notarized public binary is claimed before the
[release gates](RELEASING.md) pass. App bundles include license notices and a
link to source; they do not include developer source paths or history data.

The signed update feed is configured for the project's GitHub releases. Until
the first verified release exists, that feed may be unavailable. The updater
fails without installing anything; the app does not silently switch sources.
