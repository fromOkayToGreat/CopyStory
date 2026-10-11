# Isolated signed A → B rehearsal

This setup is preparation, not evidence that a signed update has passed. Apple
Developer ID and notarization credentials are needed to exercise installation.
Use a disposable macOS 26 account; use a snapshot-capable VM for failure injection.
Never run interruption or disk-filling tests against your everyday account.

## Isolation and design

`scripts/prepare-update-rehearsal.py` copies the current tracked and unignored
source into ignored `.build/update-rehearsals/NAME/{A,B}` directories. It records
source file hashes, applies narrowly checked transformations, and commits each
snapshot locally so the normal clean-source and release manifest checks work.
These snapshots have no Git remote or CI workflows. Review their source diffs
before signing. If a transformation no longer matches, preparation fails rather
than guessing; preserve the partial directory for diagnosis and use a new name.

Both snapshots use:

- Bundle/preferences identity `com.copystory.rehearsal`.
- History directory `~/Library/Application Support/CopyStory Rehearsal/`.
- Display name `CopyStory Rehearsal`; archive still contains `CopyStory.app` so
  Sparkle can replace the same app name. Install only in the disposable account's
  `~/Applications`, never overwrite `/Applications/CopyStory.app`.
- Separate Keychain signing account `com.copystory.rehearsal.sparkle` and public key.
- A separate GitHub repository with a fixed `rehearsal-feed` release URL.
- A = version 0.0.1/build 1; B = version 0.0.2/build 2.

The production executable gains no runtime test override. The generated policy
retains HTTPS, signatures, increasing builds, and exact repository restrictions.
Only generated release-history lookup is skipped (fixed disposable versions), and
generated install/publish helpers are disabled. Production release validation
rejects the rehearsal marker. The actual Sparkle installer and storage code are
unchanged apart from the history directory. Do not launch alongside production:
the global hotkey and clipboard still belong to the logged-in user.

## Prepare when ready

Run from the main checkout. This does not create a GitHub repository, publish,
install, or launch anything. Create a separate **public disposable** repository
such as `YOUR_OWNER/CopyStory-Update-QA` before the hosted test. GitHub private
release assets require authentication that this updater does not provide.

1. Resolve dependencies and create a separate Sparkle key in login Keychain:

   ```sh
   swift package resolve
   .build/artifacts/sparkle/Sparkle/bin/generate_keys --account com.copystory.rehearsal.sparkle
   ```

   Keep the existing production key unchanged. Copy only the displayed public
   key into the next command. Approve any macOS Keychain prompt yourself.

2. Prepare both source snapshots:

   ```sh
   python3 scripts/prepare-update-rehearsal.py \
     --repository YOUR_OWNER/CopyStory-Update-QA \
     --public-key 'PUBLIC_KEY_FROM_PREVIOUS_STEP' --name run-1
   ```

   Inspect `source-manifest.json`, both plists, `UpdateService.swift`,
   `CopyStoryApp.swift`, and the generated release scripts. Source hashes include
   local edits; the commit alone is not the complete provenance. A run directory
   is never overwritten. Test fixture public keys are not usable signing keys.

3. Once Apple credentials work, stage A and B, one at a time, in their respective
   directories. Use the same Developer ID team for both:

   ```sh
   export COPYSTORY_SIGNING_IDENTITY='Developer ID Application: YOUR NAME (TEAMID)'
   export COPYSTORY_NOTARY_PROFILE='CopyStory-notary'
   unset COPYSTORY_DEVELOPMENT
   cd .build/update-rehearsals/run-1/A
   swift package resolve
   ./scripts/release.sh
   ```

   Repeat from the main checkout for `run-1/B`. Do not edit generated snapshots
   after signing; prepare a new run if configuration changes. Outputs are
   `A/.build/releases/v0.0.1/` and `B/.build/releases/v0.0.2/`.
   Release scripts require Accepted notarization, stapling, Gatekeeper, valid
   archive/feed signatures, checksums, and extracted-bundle checks.
   `COPYSTORY_DEVELOPMENT=1` can smoke-test packaging but disables updates and
   cannot qualify as the A/B rehearsal.

4. In the disposable GitHub repository, create releases tagged `v0.0.1` and
   `v0.0.2` and upload the matching staged ZIP to each. Create a release tagged
   `rehearsal-feed` and upload **B's original signed `appcast.xml`** there.
   The fixed feed works with test prereleases; mark these releases prerelease.
   Use exact filenames and never upload to the production repository. Download
   the uploaded files and compare SHA-256 with the stages before testing.
   The appcast encloses versioned ZIP URLs; moving its signed bytes to the feed
   release does not change those URLs. Do not edit or reformat signed XML.

5. Download A in the test account, extract it to `~/Applications/CopyStory.app`,
   launch through Finder (retain download quarantine), complete onboarding and
   grant Accessibility if testing direct paste. Seed only synthetic text/images,
   pin an item, set exclusions/retention/login preferences. Quit, snapshot the
   test account/VM, relaunch A, then check Preferences → Updates manually.

6. Install B via Sparkle, relaunch, and confirm build 2. Check all synthetic
   history/images/pins, exclusions, retention, login setting and direct paste.
   Verify automatic checks/downloads start off, enabling and disabling them
   works, and network observation contains no clipboard payload. Record actual
   results in the generated `RESULTS.md`; never infer success from CI alone.

## Failure cases and recovery

Restore the A snapshot before each case. Keep pristine signed stages offline.
Change only assets in the disposable repository, and restore originals after
each case. Re-download assets to confirm GitHub is serving the intended bytes.

| Case | Procedure | Expected observation |
|---|---|---|
| Unavailable feed | Temporarily remove the test feed asset | Error; A and history usable |
| Modified feed | Change one byte in a copy of signed XML, upload that copy | Signature failure; no installation |
| Unsigned feed | Remove the signature from a test copy | Rejected; no unsigned fallback |
| Corrupt/truncated ZIP | Replace B's test-hosted ZIP with a damaged copy, retain valid original feed | Download/length/signature rejection; A intact |
| Wrong archive key | Make a feed with a wrong-key archive signature, then sign the feed with the correct rehearsal key | Archive rejected before extraction |
| Equal/older build | On B serve A's original signed feed; on A serve A's feed | No downgrade/reinstallation |
| Interrupted download | Disconnect VM network during download, then reconnect and retry | A usable; subsequent valid update succeeds |
| Low disk | Constrain free space inside disposable VM only | Safe failure, preserved history; retry after freeing space |
| Interrupted replacement | Snapshot VM; interrupt at replacement and record exact timing | Document actual restored/reinstallable state; preserve history |
| Failed relaunch | In a separate test run use a deliberately failing candidate and record recovery | Reinstall verified app preserving history; no automatic rollback claim |
| Pending writes | Capture synthetic data, then accept normal update/quit | Accepted history mutations survive relaunch |

Wrong-key feeds, deliberately failing candidates, and precisely timed installer
faults require additional fixture preparation when signed builds are available;
this script does not manufacture those or claim they passed. Never modify a
signed app bundle in place and mistake that for a valid failing candidate.

For failed launch/replacement, stop test copies and reinstall a pristine verified
app while preserving `CopyStory Rehearsal` history. Do not downgrade across schema
changes. Sparkle is not a general post-install crash rollback system. Keep failure
logs and actual recovery steps with the source manifest, without clipboard data.

After this isolated test passes, rehearse the real production candidate in a clean
account too: test identity success alone does not establish production readiness.
See [RELEASING.md](RELEASING.md) and
[Sparkle publishing guidance](https://sparkle-project.org/documentation/publishing/).

## Preparation verification (2026-10-10)

- 3 isolation/production-boundary tests and 13 release-policy tests passed locally.
- Generated A snapshot built for arm64 and x86_64 and passed package verification.
- Its `--verify-package-runtime` smoke check loaded Sparkle and confirmed that
  updates were disabled in the explicit ad-hoc development package.
- Source hygiene and whitespace checks passed. CI has been configured to run
  the new isolation tests; no remote CI result is claimed for these local edits.
- This check used a public fixture key and `example/CopyStory-QA` without creating
  that repository, generating a private key, installing an app, or accessing user
  history. Do not use the `smoke-1` output for the signed rehearsal.
- Signed A/B staging, hosting, update installation and recovery cases remain
  NOT RUN pending credentials and the separate test key/repository.
