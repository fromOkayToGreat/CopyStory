# Public release runbook

Source is public under MIT. **No notarized public app release is claimed yet.**
The 0.3.0 implementation and release tooling must pass the gates below before
the first app download is published. Local ad-hoc builds and CI artifacts are
for development; they are not a substitute for a verified public release.

## Distribution prerequisites

Users can download a Mac app from GitHub or a website without the Mac App Store.
The normal trusted direct-download path is Developer ID signing and Apple
notarization. Apple lists Developer Program membership at USD 99 per year,
or local currency where available; membership includes distribution benefits.
See Apple's [enrollment guidance](https://developer.apple.com/help/account/membership/program-enrollment)
and [account comparison](https://developer.apple.com/help/account/basics/about-your-developer-account).
No purchase or enrollment is performed by these scripts.

The release maintainer needs:

1. A Developer ID Application certificate **and its private key** installed in
   Keychain. Confirm it appears in `security find-identity -v -p codesigning`.
   A downloaded certificate without its private key is insufficient.
2. A working notarization Keychain profile, for example `CopyStory-notary`,
   configured directly with `xcrun notarytool store-credentials`. Apple documents
   [the notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow).
   Do not put passwords, API private keys, or certificate exports in this repo.
3. Access to the Sparkle update key under Keychain account
   `com.copystory.app.sparkle`, plus an owner-managed encrypted/offline backup.
   `Config/Info.plist` contains only its public key. The existing key has been
   created; do not generate a replacement or export it casually.
4. A GitHub account with release access to `fromOkayToGreat/CopyStory`, using
   `gh auth login` if needed. Signing credentials stay out of pull-request CI.

Apple credentials are currently unavailable on the preparation machine. The
repository, updater code, unit tests, and local packaging can proceed without
them. Signing, notarization, and the real signed upgrade rehearsal cannot.

## Versioning and source

`Config/Info.plist` is the version source: semantic `CFBundleShortVersionString`
and a positive, strictly increasing integer `CFBundleVersion`. Development
0.3.0 is build 4. Never reuse a published version or build, including for a
hotfix; do not overwrite old release assets.

Update CHANGELOG, review dependency changes/licenses, run tests, commit all
changes, and push main. The manifest records the exact Git commit. Publication
requires that commit to match remote main, then tags it as `vVERSION`.
The first release needs `--first-release`; later releases verify the signed
feeds of all existing stable releases and require a larger build number.

## Local validation

Run from a clean clone on macOS with Swift 6 and a macOS 26+ SDK:

```sh
swift package resolve
./scripts/test.sh
python3 scripts/test-release.py
python3 scripts/check-source-hygiene.py
COPYSTORY_DEVELOPMENT=1 ./scripts/build.sh
./scripts/verify-package.sh .build/CopyStory.app
.build/CopyStory.app/Contents/MacOS/CopyStory --verify-package-runtime
```

Ad-hoc signing cannot satisfy Sparkle's hardened library validation on this
Mac. The explicit `COPYSTORY_DEVELOPMENT=1` mode adds only the development
host's library-validation exception and marks the bundle as development. Its
updater is disabled. This follows Sparkle's [development guidance](https://sparkle-project.org/documentation/).
The public release script rejects this flag and marker; it requires Developer
ID with library validation intact. Do not distribute development bundles.

The build compiles arm64 and x86_64, embeds the pinned Sparkle framework with
symlinks intact, signs nested code inside-out, and verifies the final bundle.
The package includes license notices and excludes source/build/private data.
Public checks additionally require Developer ID, one signing team, secure
timestamps, no weakening entitlements, notarization staple, and Gatekeeper.

CI runs on a macOS runner with read-only repository permissions. It uses pinned
action commits, tests and validates local packages without release secrets.
Do not upload unnotarized app artifacts as a public release.

## Stage and verify a release

After the credential setup and source checks, run:

```sh
export COPYSTORY_SIGNING_IDENTITY='Developer ID Application: YOUR NAME (TEAMID)'
export COPYSTORY_NOTARY_PROFILE='CopyStory-notary'
./scripts/release.sh --first-release
```

Omit `--first-release` after the first public stable release. The identity and
profile names above are references, not secret values. macOS may ask permission
for Sparkle's official signing tool to access its Keychain item.

This builds the universal app, submits an archive to Apple, requires an
`Accepted` result, staples and assesses the app, then repackages the stapled
bundle. Sparkle signs the final archive and feed. Public-key verification checks
the signatures without exporting the private key. The pipeline extracts and
re-verifies the archive's bundle identity/version, embedded config, architecture,
signing, notarization, and checksums before staging it at
`.build/releases/vVERSION/`.

The stage contains the ZIP, `appcast.xml`, `SHA256SUMS`, and
`release-manifest.json`. Keep the notarization result as private release evidence;
do not publish credential metadata. A failed/interrupted run never creates a
public release. Inspect existing stages before retrying; the script refuses to
overwrite them. Build staging is disposable, but never delete the only copy of
release evidence or any user's history to make a retry succeed.

## Required acceptance before publication

Record actual results with OS/hardware, app build, and observed behavior in
`VALIDATION.md` or a release-specific validation document. A checkbox here is
a requirement, not evidence of success.

- [ ] Full isolated Swift tests, release-policy/signature tests, source hygiene,
  and CI pass on the exact release commit.
- [ ] Universal package validates; run on both supported hardware families and
  macOS 26, including native UI, hotkey, capture, manual copy, and direct paste.
- [ ] Developer ID signatures, timestamp, hardened runtime, Apple notarization,
  staple, and fresh download Gatekeeper assessment pass.
- [ ] In a disposable account, install signed build A and update to signed B
  through Sparkle. Synthetic text/images/pins, exclusions, retention, login and
  Accessibility behavior, and update consent remain correct after relaunch.
- [ ] Tampered/unsigned feed, modified/wrong-key/truncated archive, older/equal
  build, unavailable feed, and unsupported configuration fail safely.
- [ ] Interrupted download, low disk space, quit while writes are pending,
  interrupted replacement, and failed relaunch have documented recovery results.
- [ ] Automatic checks/downloads default off; enabling/disabling them and manual
  checks work. Network observation shows no clipboard/history content sent.
- [ ] Remaining [manual acceptance](MANUAL_TESTING.md) is completed or a specific
  limitation is explicitly accepted and documented for the release.

Use [the isolated rehearsal setup](UPDATE_REHEARSAL.md) to prepare A/B snapshots.
The first signed end-to-end rehearsal needs two disposable test builds and a
separately signed test feed/identity. Never weaken the production feed/key
policy or use the installed user's production history as the fixture. Review
the test configuration separately and do not publish test artifacts on the
stable channel. A production release should also be rehearsed in a clean test
account before promotion.

## Publish reviewed assets

Write release notes that include minimum macOS, installation steps, changes,
privacy limitations, and actual validation. Then run:

```sh
./scripts/publish-release.sh /absolute/path/to/.build/releases/v0.3.0 /absolute/path/to/release-notes.md --first-release
```

The helper revalidates the staged assets and release history, checks remote
main, pushes the version tag, creates a draft release, uploads assets, downloads
them for verification, and only then publishes it as latest. It checks that the
public stable feed serves the same signed bytes. It refuses replacement of an
existing release; an interrupted upload may leave a recoverable draft/tag.
Inspect and repair or remove only that failed draft after review before retrying.

Never edit a signed appcast in place; regenerate and re-sign after any change.
GitHub's latest-release redirect can change, but the signed bytes remain the
trust boundary. Preserve every published signed feed for release-history checks.

For a bad shipped version, publish a higher-build fix. Sparkle is not a
post-install crash rollback system. Users can reinstall a verified app while
preserving the separate history folder. See [UPDATES.md](UPDATES.md) for key loss,
replay limits, and interruption recovery.
