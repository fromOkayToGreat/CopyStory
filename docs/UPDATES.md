# Update trust, controls, and recovery

CopyStory uses [Sparkle 2.10.0](https://github.com/sparkle-project/Sparkle/releases/tag/2.10.0),
pinned in the package manifest and lockfile. On October 10, 2026, the upstream
published advisories were reviewed: the latest listed fixes ship in 2.9.6,
before this pin. See [upstream advisories](https://github.com/sparkle-project/Sparkle/security/advisories).
This is a dated dependency check, not a guarantee against future vulnerabilities.
There is no custom executable
downloader or shell-based self-update mechanism.

## User control and privacy

Automatic checks and automatic downloads/installations default to off. Use
Preferences → Updates to opt in, or request a single manual check. Sparkle
persists those settings. Preview mode does not start the updater. Explicit development builds also
disable updates; their library-validation exception is never accepted for
public distribution. A source build without valid release configuration cannot
start update checks.

The release feed is
`https://github.com/fromOkayToGreat/CopyStory/releases/latest/download/appcast.xml`.
Only stable releases belong on this channel. GitHub and its asset delivery
services receive normal request metadata; no clipboard contents or history
metadata is included. Sparkle system profiling and JavaScript release notes
are disabled. See [PRIVACY.md](PRIVACY.md).

Before the first verified binary release, this endpoint may return 404. The
app reports an unavailable feed; it does not fall back to unsigned GitHub API
metadata or install arbitrary assets. Version 0.2.0 has no updater and needs
one manual installation of the first verified release.

## Two separate trust mechanisms

1. **Update authenticity:** the app embeds a public Ed25519 key. The matching
   private key signs the release archive and feed using Sparkle's tools.
   `SURequireSignedFeed` authenticates metadata, and
   `SUVerifyUpdateBeforeExtraction` verifies downloads before extraction.
   `SUSignedFeedFailureExpirationInterval=0` disables the timed fallback from
   failed signed-feed validation. HTTPS adds transport protection; it does
   not replace signatures. SHA-256 sums help compare files but do not establish
   publisher identity.
2. **macOS distribution trust:** Developer ID identifies the publisher and
   notarization is Apple's distribution check. The release pipeline requires
   a secure timestamp, hardened runtime, nested-code verification, notarization,
   stapling, and Gatekeeper assessment. An ad-hoc signature is insufficient.

These settings follow Sparkle's [setup](https://sparkle-project.org/documentation/),
[security customization](https://sparkle-project.org/documentation/customization/),
and [publishing](https://sparkle-project.org/documentation/publishing/) guidance.

The app accepts only strictly newer positive numeric build numbers, expected
HTTPS GitHub release asset URLs, and signed archive metadata. Sparkle performs
the cryptographic validation and app replacement. Serving an old feed cannot
make an installed newer build downgrade. A compromised server can still withhold
updates or replay a previously valid newer feed; signatures cannot prove that
a server has revealed the latest release.

## Keys and publishing

The signing account is `com.copystory.app.sparkle` in the maintainer's macOS login
Keychain. Only the public key belongs in `Config/Info.plist`. Never commit a
private key, Keychain export, certificate private key, app-specific password,
or notarization API key. CI for pull requests has no release credentials.

Back up the update private key through an owner-controlled encrypted/offline
process. A Keychain-only copy can be lost with the Mac. Export is an intentional
owner operation; this repository's workflow does not export it. Do not rotate
the key by simply editing the plist: existing installations trust the old key.
With verify-before-extraction enabled, Sparkle's documented key-rotation path
requires a Developer ID-signed disk image and a feed the installed app still
trusts. Because failed-feed fallback is disabled, losing the old Ed25519 key
prevents authenticating a transition feed. This ZIP pipeline deliberately does
not automate rotation; key loss requires a verified manual reinstall.

Keep the repository owner/name and asset paths stable. A project transfer or
feed migration needs a separately tested signed transition. Do not overwrite
an existing version's release assets; increment both release version and build.

## Failure and interruption

Network errors and invalid signatures abort the update attempt. Retry a check
after connectivity recovers. CopyStory delegates staging/replacement to Sparkle
instead of modifying the running app in place. Sparkle attempts an atomic swap
where supported and restoration of the old app if its fallback replacement
fails. It cannot promise recovery from every power loss or a crash after a
successful install. Shutdown stops capture and waits
for accepted storage mutations before replying to an ordinary quit request.
Force quit or power loss can still interrupt that wait.

An app update does not clear `~/Library/Application Support/CopyStory/` or change
the `com.copystory.app` preferences domain. Database transactions, atomic image
writes, and startup reconciliation remain in place. Do not claim these controls
prove every power-loss scenario: interruption, low-disk-space, relaunch, and
data-preservation acceptance must be exercised with signed builds in a separate
test account before public binary release.

If an installation cannot relaunch, quit remaining copies and reinstall the
latest verified, notarized app from the official release page. Keep the history
folder intact. Do not reset history to troubleshoot an update. Do not downgrade
the app across storage-schema changes. A newer faulty release should be repaired
with a higher-build hotfix, preserving the existing schema where possible.

## Acceptance tests

The automated policy suite covers malformed configuration, older/equal builds,
unexpected URLs, and missing signatures. Packaging checks validate the embedded
configuration and signatures. The [release checklist](RELEASING.md) also requires:

- A real signed A→B update on a disposable account, with synthetic text, image,
  pins, exclusions, retention, and update opt-in choices preserved.
- A tampered feed, corrupted/truncated archive, wrong signing key, and replayed
  older/equal release all rejected; no downgrade or history deletion.
- Interrupted download, unavailable feed, low disk space, interrupted replacement,
  and failed relaunch leave a recoverable installation/history.
- First-launch defaults, opt-in, opt-out, manual checks, cancellation, and no
  clipboard data in network requests.

Passing unit tests is not a substitute for this signed end-to-end rehearsal.
