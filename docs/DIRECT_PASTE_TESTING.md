# Local Direct Paste Test candidate

This private test channel lets Francisco continue testing Direct Paste with the
current History/Library search and deletion fixes while Apple clarification is
pending. It is not an App Store or TestFlight build. Production remains copy-only;
this change does not restore event posting in the shipping configuration.

## Identity and data boundary

- App: **CopyStory Direct Paste Test**, menu-bar title **CS Paste Test**.
- Bundle ID: `com.copystory.direct-paste-test`, version1.0.0/local build1.
- Separate sandbox container/preferences and `CopyStory Direct Paste Test` store
  folder. It does not import, migrate or reset production/development history.
- Compile selection: `APP_STORE COPYSTORY_DEVELOPMENT COPYSTORY_DIRECT_PASTE_TEST`.
  The test flag fails compilation with production, reconstruction or missing
  development selection. Startup requires the matching test identity and marker.
- Existing Direct Paste permission, target identity, secure input, cancellation,
  expiry and no-retry rules are reused. Independent search, deletion selection
  and confirmation logic are unchanged.
- Direct Paste and the global shortcut start OFF. Direct Paste is available for
  explicit opt-in, rather than silently enabled before consent. Recording starts
  only through the existing onboarding flow. Login registration is disabled in
  this channel, including its native effects.

The existing `CopyStory Development.app` identity is deliberately not reused.
Launching another copy of that app would share its development store and may
change permission continuity. Never install this test bundle over either app.
Subsequent launches of this test identity reuse only its own test data.

## Build and inspect without launch

From a reviewed worktree, with a fresh absolute output outside that worktree:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  scripts/build-direct-paste-test.sh /tmp/copystory-direct-paste-test-candidate
python3 scripts/verify-development.py \
  '/tmp/copystory-direct-paste-test-candidate/Products/Debug/CopyStory Direct Paste Test.app' \
  --direct-paste-test
```

The helper builds once, signs locally ad-hoc with sandbox/hardened runtime and
user-selected read-only file access, and records build/static verification and an
executable digest. It never installs, launches, requests permissions, registers a
shortcut/login item, uploads or accesses clipboard/history. No certificate or
private key is used. The verifier requires the test identity/marker/name,
expected paste API imports, strict signature and no updater. Normal development
verification rejects this test identity and marker. It is not a signed update to
the accepted personal development app and must not use that promotion workflow.

Ad-hoc signing supplies no stable Apple Development identity or Apple approval.
Fresh OS clipboard/event-posting permission may be needed for this distinct app;
existing grants must not be assumed to transfer. Do not re-sign or rebuild the
frozen candidate during a permission session, weaken protections, reset grants or
reauthorize an unrelated installed app. Apple Development signing can be planned
separately if this becomes an ongoing personal-use channel.

## Candidate-specific launch review

Follow `MANUAL_TESTING.md`: review the exact path, executable hash, source revision,
identity, effects, destination and stop condition, then obtain Francisco's explicit
launch confirmation. This document does not authorize launch or permission changes.

Proposed bounded session: 10 minutes, synthetic markers only, blank designated
TextEdit document, no submissions. First verify the new test identity and empty
store; closing onboarding must not start recording. Arrange a single recorder
with the owner before capture, without silently quitting another app. With scoped
clipboard approval, admit synthetic markers and one literal Library prompt.
Verify the recent search/selection behavior. With separately scoped opt-in and
posting permission approval, invoke from the designated destination and try one
History Paste and one Library Paste. Observe actual insertion; a “Paste requested”
status alone is not proof. Finish with Direct Paste OFF and quit only this app.

```text
Exact candidate review → explicit launch → isolated onboarding/store
  → approved synthetic capture → search/deletion checks
  → approved opt-in/permission → one History and one Library Paste → OFF/quit
                         ↓ unexpected state or 10 minutes
                    stop and retain evidence
```

Stop for existing/unexpected data, another recorder/shortcut collision, unexpected
permission prompt or destination, lost permission, duplicate input, crash or the
time limit. No automatic retries, data cleanup, grant reset or app replacement.
The shipping release and any Apple upload/submission remain separate decisions.
