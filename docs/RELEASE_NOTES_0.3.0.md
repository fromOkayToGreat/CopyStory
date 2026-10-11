# CopyStory 0.3.0 — draft release notes

Unpublished. These notes accompany a local candidate, not an available download.
Publication requires review of the [acceptance record](RELEASE_ACCEPTANCE_2026-10-11.md)
and explicit maintainer approval. Resolve or explicitly accept its outstanding
limitations before using these notes for a public release.

CopyStory adds a local prompt library with reusable variables, dropdown choices,
saved defaults, favorites, search, preview, Copy and Paste. Saved prompts persist
independently of history retention and clearing. CopyStory never submits prompts
to an AI service.

This version also adds signed Sparkle updates. Automatic checks and downloads
start off; enable them in Preferences → Updates or check manually. Clipboard
history stays local. Update requests contact GitHub and its asset delivery
services; live network acceptance remains outstanding.

## System requirements and coverage

The package targets macOS 26+ on Apple silicon and Intel. Automated runtime
checks passed on Apple silicon/macOS 27.0.1 locally and 26.6.2 in CI. Intel,
macOS 26.0, full VoiceOver/Reduce Transparency, login and permission transitions,
and live update failure/recovery acceptance remain incomplete. Universal
compilation does not establish runtime acceptance. See the linked matrix.

## Install after a verified release is published

Download the verified ZIP from the official CopyStory GitHub release. Quit the
existing app, extract the ZIP, and place CopyStory.app at the stable installation
location you choose. Avoid running multiple copies against the same data.
Open through Finder and grant Accessibility to that exact app for direct paste.
Manual Copy/Command–V remains available without automatic paste permission.
Version 0.2.0 predates the updater and requires this one manual installation.

An app replacement should preserve the separate Application Support data and
preferences. History remains in `~/Library/Application Support/CopyStory/`, with
saved prompts under `Library/library.sqlite`. Keep those files when reinstalling.
If an update fails to launch, quit remaining copies and reinstall a verified
notarized version without clearing history. Do not downgrade across schema
changes. Automatic recovery from post-install crashes has not been established.

History is plaintext on disk, with user-only file permissions. Unmarked secrets
can enter history; pause recording before copying sensitive material. Exclusions
and clipboard markers reduce capture but are not a credential vault. See
[privacy details](PRIVACY.md) and [update recovery](UPDATES.md).
