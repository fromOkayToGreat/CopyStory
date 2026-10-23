# Personal development signing and updates

Use one `com.copystory.development` identity and the canonical installed path
`~/Applications/CopyStory Development.app`. Keep accepted builds as immutable
archives. Normal History/Library use is the milestone; retain the reviewed
session-resignation cancellation and existing regression coverage without making
rare session switching the next manual test.

## Status and channels

The signed configuration and tools are prepared. A signed build, private-key use,
installation, launch and permission changes are **not** authorized by this file.
No Apple Development identity was locally visible during preparation. Do not use
the available Developer ID identity as an automatic substitute.

Apple Development is the intended personal development channel. Planned Mac App
Store production remains `com.copystory.app`, using a separate Xcode archive and
App Store export with Apple Distribution or the applicable Mac App Distribution
identity. Developer ID Application is the channel for distribution outside the
store. Development signing does not establish App Store readiness or transfer its
permissions. See Apple's [certificate overview](https://developer.apple.com/help/account/certificates/certificates-overview/)
and [distribution guidance](https://developer.apple.com/documentation/xcode/creating-distribution-signed-code-for-the-mac).

Current sandbox-only entitlements are unrestricted on macOS, so a development
profile is not a blanket prerequisite. Reevaluate if capabilities change;
TestFlight requires a profile. See [TN3125](https://developer.apple.com/documentation/technotes/tn3125-inside-code-signing-provisioning-profiles).
Never use the historical disable-library-validation Development.entitlements for
this path. The signed configuration suppresses debugger entitlement injection
and the audit requires sandbox=true only.

## Preparation without signing

Run `python3 scripts/test-development-signing.py` for mocked policy tests and
`scripts/test-development.sh` for the selected offline Swift suites with a full
Xcode toolchain. Do not substitute the historical full native suite.

`build-signed-development.py` defaults to **plan only**: no build, signing,
keychain query or output-directory creation. It needs explicit team, public
certificate SHA-1, build number, fresh output outside the worktree, and either an
initial-transition declaration or previous accepted signed bundle. For example,
replace these placeholders with reviewed public metadata before using:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
python3 scripts/build-signed-development.py \
  --team TEAM_ID --identity PUBLIC_CERTIFICATE_SHA1 --build 2 \
  --initial-signed-baseline --output /absolute/fresh/output
```

The parser rejects unresolved placeholders. A printed plan is not an accepted
artifact; it may show dirty preparation source. Signing execution requires a
clean committed worktree and an independently approved use of the selected key.
Do not run `--execute-signing` until that action is approved. The execution path
checks public identity type before Xcode, rejects Developer ID/Apple Distribution,
uses manual signing with no automatic provisioning flags, builds once, and audits
exact team/certificate/revision/build, arm64/min26, sandbox/hardened runtime and no
Sparkle. It preserves source archive, build/settings/toolchain logs, a bundle
inventory and ZIP roundtrip verification plus digests. Errors preserve partial
evidence and stop; no install/launch follows. This path remains unexecuted until
a development identity and signing approval are available.

Use a monotonically increasing development build number (2,3,4…). This is a local
ledger decision, not an App Store allocation. Marketing version stays1.0.0 until
deliberately changed. Avoid concurrent build-number allocation. Subsequent updates
supply `--previous` instead of `--initial-signed-baseline`; they must increase the
build and satisfy each other's designated requirements. The initial ad-hoc to
certificate transition is deliberately explicit and needs a new readiness result.
Don't handcraft weaker requirements. [TN3127](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements)
explains continuity and why signing channels differ. Stable signing can reduce
permission churn; it does not guarantee zero permission failures.

## Static audit and acceptance

Historical ad-hoc static inspection remains available:

```sh
python3 scripts/verify-development.py '/path/to/CopyStory Development.app'
```

This default does not constrain the signing channel. Signed acceptance additionally
requires `--signed --expected-team … --expected-identity … --expected-revision …
--expected-build …`, and `--previous …` for update continuity. Certificates here
mean only public certificate metadata: audit extraction uses temporary files,
never reads keychains or private keys. Audit never executes the inspected app or
reads its data. PASS means static evidence only. It rejects dirty provenance,
unexpected fixture markers, extra entitlements, wrong identity/team/channel,
nonincreasing builds and failed requirement checks. Mode/symlink/file hashes allow
comparison after ZIP roundtrip and later installation.

## Promotion, smoke and rollback — separate scopes

No installation script is activated. Before any later promotion, owner quits the
app and verifies no competing same-ID copy. Obtain separate data-preservation
scope for a consistent backup, verify data/schema compatibility, stage the frozen
bundle on the same volume, verify bytes/signature, archive the previous installed
bundle, replace only the canonical path and verify again. Record partial moves
and recovery steps; two renames aren't an atomic transaction. Never patch/resign
after accepting an artifact. Candidate folders and backups share this development
store if launched; a different app location does not isolate data. The sandbox
container and preferences may need special attention on the first signing
transition. Unexpected access failure or apparently empty history stops migration;
never reset or recreate the store automatically.

Manual readiness (2–5min, stop at5) and ordinary synthetic smoke (5–8min, stop at8)
need separate owner coordination. Check startup, menu/search, History capture/Copy,
Library search/edit/Copy, relaunch/persistence. Direct Paste stays OFF by default;
if separately requested, verify readiness first, then one positive History/Library
Paste in a separate scope. Unavailable access or an unexpected prompt stops the
session: no repeated Request/reset/Settings row loop. No real content logging.

Rollback restores the verified last accepted bundle to the canonical path with
the app stopped; leave history/preferences intact. Check backward schema support
first. Retain source history, archives and reasons; don't reset Git or delete
history. An old ad-hoc rollback may require another OS decision. Full protected
input/negative permission/accessibility/macOS26–27/App Store gates remain separate.
