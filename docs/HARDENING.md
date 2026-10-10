# CopyStory 0.2.0 security hardening

This release implements the local hardening recommendations from the source
and installed-app audit. The clear-history race fix from 0.1.1 remains in place.

## Implemented controls

- App exclusions before content reads and decoding, invalidation of pending
  images when the list changes, and exclusion checks on queued saves. Apple
  Passwords is initially excluded. Users select additional app bundles in
  Preferences. Attribution remains best effort; browser extensions share the
  browser's identity, and background producers may not be identified correctly.
- Optional age expiration for unpinned history, including image and thumbnail
  files. Available periods are 1, 7, 30 and 90 days; existing data remains under
  indefinite retention until the user applies a period. Pins are preserved.
- Automatic paste requires the remembered app, window and focused element.
  Unknown or changed identities cause manual-copy fallback. A final OS focus
  race remains possible; a requested paste is not delivery confirmation.
- Canceled copy-only selections no longer write the clipboard or emit stale
  success/error feedback after their asynchronous lookup completes.
- The preview's storage-folder link now resolves to its actual temporary store.
- The 0.2.0 packaged builds enabled hardened runtime without exception entitlements.
  The build accepts an explicit signing identity and adds a secure timestamp
  for non-ad-hoc signatures.

## Signing and notarization

The 0.2.0 local build was ad-hoc signed with hardened runtime. That does not
confer publisher identity or notarization. Public release tooling was added in
0.3.0; follow [RELEASING.md](RELEASING.md) for the current commands and signing
gates, and [UPDATES.md](UPDATES.md) for the separate update signature trust.
No Developer ID/notarization success is claimed before those gates pass.

## Encryption and an application lock: remaining design work

The store is still plaintext and there is no application authentication lock.
Neither app exclusions nor expiration protects retained data from software with
existing access to the user's files or backups. This is a disclosed remaining
limitation, not a security property supplied by hardened runtime.

An encrypted-storage release must cover SQLite text, searchable copies, previews,
metadata, journals, image payloads and thumbnails. Encrypting only image files
or adding a lock screen would leave other data readable. Decrypting the database
into a temporary disk file would also undermine the intended protection.

Before migration, define the intended threat model (for example, stolen backups
versus another process in an unlocked session), Keychain key access and user
authentication rules, lock timeout, recovery/export policy, and behavior when
authentication or a key is unavailable. An implementation should use a reviewed
encrypted database format and authenticated encryption for external payloads,
with no plaintext search index or scratch files, and a recoverable migration
that does not discard the only usable history copy. Test locked startup,
interrupted migration, key loss, backup restore, and release-signing changes.
Encryption cannot guarantee secrecy against a fully compromised logged-in session.

This release does not silently introduce such a key/migration policy or claim
to solve it. The narrow controls above are useful independently of that work.

## Verification

`./scripts/test.sh` includes isolated synthetic tests for expiration boundaries,
pins, image-file deletion, invalid timestamps, delayed captures, exclusions
before decoding, changed exclusions during decoding, canceled copy requests,
paste-target identity matching, and preview storage isolation. Existing
clear-history race regressions remain in the suite. Tests use named pasteboards
and temporary stores; they do not clear production history.

Real-app acceptance still needs to cover focus changes between fields/tabs,
Accessibility revocation, lock/unlock and login startup on supported macOS
versions. The focused-element predicate tests do not post keyboard events.
