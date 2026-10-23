# Free v1 with direct paste: investigation and proposed roadmap

Prepared October 13, 2026, approximately 17:20 UTC, in the actual root project.
Target public release: Thursday October 15. Planning only; no implementation,
interactive paste test, permission/account/signing change, installation, migration,
push, merge, upload, submission, publication, or Linear creation performed.

**Conclusion:** retain free v1 and direct paste as the product goal. Sandbox
compatible event posting is a credible path to investigate, but CopyStory's
existing AX original-field restoration cannot ship unchanged in a sandbox.
A shipping direct-paste implementation, final acceptance, and the App Store
delivery pipeline remain unfinished. The current-focus contract below is approved. Thursday is
a target, not an evidence-backed promise of public availability.

This proposal supersedes the manual-paste/pricing assumptions in
`/tmp/CopyStory-release-scope-and-acceptance-2026-10-13.md`. That document was
unapproved. Free pricing and direct-paste intent are now explicit user decisions;
manual Copy remains an error/permission fallback, not the proposed v1 feature scope.
Follow-up owner approval: free v1 prefers direct paste into the currently focused
control of the intended destination application. Unsupported/protected app cases
may fail safely. Pricing and current-focus semantics are RESOLVED; this follow-up
authorizes documentation only, not implementation or runtime/permission testing.

## Fresh state comparison

| Surface | Observed October 13 | What it establishes |
| --- | --- | --- |
| Installed `/Applications/CopyStory.app` | 0.2.0/build 3; `com.copystory.app`; arm64 only; minimum 26.0; ad-hoc hardened-runtime signature; no Team ID and no entitlement payload reported | User confirms working direct copy/paste today. This is unsandboxed installed behavior, not App Store readiness. No installed-source commit provenance is embedded in inspected metadata. |
| Root repository | `codex/app-store-migration`, `7305c697d57d6e21a79904e15a1f70f5a6fd7119`; no tracked modifications; untracked nested `CopyStory/` | Actual migration source; 21 changed files, 556 insertions/25 deletions relative to main. Preserve the nested checkout. |
| Nested checkout | `CopyStory/`, main `2af4ff0535af84be570f81f14482971fb27d77b8`, clean | Separate checkout, not the installed app or migration candidate. |
| Current GitHub | main `2af4ff0`; migration `7305c69`; only these two branches returned by live API | Both local heads match their current remote counterparts. Remote tracking refs alone were not used as proof. |
| [PR #9](https://github.com/fromOkayToGreat/CopyStory/pull/9) | Open, draft, unmerged, mergeable; base/head match above | Feasibility work only. Latest returned exact-head workflow run [38180763310](https://github.com/fromOkayToGreat/CopyStory/actions/runs/38180763310) is completed/success. |
| Open GitHub issues | [#8 feasibility](https://github.com/fromOkayToGreat/CopyStory/issues/8), [#6 acceptance](https://github.com/fromOkayToGreat/CopyStory/issues/6), [#5 submission](https://github.com/fromOkayToGreat/CopyStory/issues/5), [#4 direct-channel recovery](https://github.com/fromOkayToGreat/CopyStory/issues/4) | Existing useful dependency structure. #8 still offers a pending manual-paste option; reconcile it with the newly confirmed direct-paste goal later. No issues changed here. |
| GitHub releases API | Empty response list | No release objects visible through the authenticated query. This does not establish App Store Connect or storefront status. |
| Local sandbox artifact | Strict signature verification FAILED for arm64; executable SHA-256 `8c419a791e186d7e1636c8b7304bae030d1f36525a990f4b8c0f40a68ed271d7` matches saved evidence | Preserve it for investigation. Matching executable bytes do not prove the whole bundle/signature is intact. Do not use it as a valid shipping or runtime acceptance artifact. |
| Delivery environment | macOS 27.0.1/26A434; selected developer directory `/Library/Developer/CommandLineTools`; no Xcode named in `/Applications` | Full Xcode archive/export workflow remains unestablished; absence from Applications does not rule out other installations. |

Native stack: SwiftPM, Swift/AppKit/SwiftUI, SQLite through CSQLite, Carbon
shortcut registration, and Sparkle 2.10.0 in the direct channel. `Package.swift`
declares macOS 26+ and Swift 6 tools with Swift v5 language mode. No Flutter
migration is required by this project's stack or Apple's store requirements.
SwiftPM can remain useful for shared code/tests; shipping packaging must use
Xcode-provided technologies as required by [guideline 2.4.5](https://developer.apple.com/app-store/review/guidelines/#hardware-compatibility).

Guidance read: global `~/.codex/AGENTS.md`, repository
`CONTRIBUTING.md`, `SECURITY.md`, privacy/release/migration docs, and relevant
conversation backup passages. No root/ancestor AGENTS.md, root `.agents` or
`.codex` directory, or local CopyStory SKILL.md was found in inspected locations.
Second-account switching remains paused; synthetic data only and no real history
or general clipboard access in this investigation.

## Exact implementation gaps

| Location | Current behavior | Required store work |
| --- | --- | --- |
| `PlatformServices.swift:413–564` | `PasteTarget` holds AX window/field; `rememberDestination` reads AX; `paste` writes clipboard, activates/raises/restores through AX, rechecks exact field, then calls `postToPid` once | Design separate sandbox paste coordination without cross-app AX. Preserve generation/cancellation, own-write check, non-reentrancy and no retry. A PID check is not original-field verification. |
| `PlatformServices.swift:443–448`, `AppModel.swift` permission state | Uses AX trust/request APIs | Use PostEvent-specific preflight/request flow for store event posting; investigate denied/revoked behavior. Same System Settings label does not make these privileges interchangeable. |
| `CopyStoryApp.swift:170–213` | Activating borderless panel; `NSApp.activate()` and key-window presentation; global mouse monitor dismisses panel | Prototype whether a public nonactivating NSPanel can support search, keyboard selection, menus and library forms while preserving external app activation. Audit global monitoring's separate privilege needs. This is a hypothesis, not proven destination preservation. |
| `AppModel.swift:244–263,316–345`; History/Library views; Return handling | History and rendered prompts share existing coordinator; Return/double-click/context/accessibility actions invoke paste | Route both through validated store behavior; retain successful prompt history admission and copy fallback. Reconcile every action and label, including keyboard layouts/modifier release. |
| `AppViews.swift:124,323–329,400–407` | Store says paste is under evaluation and hides setup | Replace with accurate PostEvent explanation, optional direct-paste setup, denied/revoked status and explicit destination semantics only after feasibility passes. |
| `CopyStoryApp.swift:18–33`; `UpdateService.swift:209–215` | APP_STORE ordinary launch rejected; runtime verifier insists on probe identity/marker | Add distinct shipping configuration with ordinary launch and final identity. Keep probes/demo isolated; do not simply remove the guard and expose production capture in the probe bundle. |
| `Package.swift`; `AppDistribution.swift`; `UpdateService.swift`; store scripts/verifier | Store conditional dependency removal and inert updater exist; verifier requires feasibility identity | Carry no-Sparkle policy into shipping target and verify final artifact. Do not treat a successful probe verifier as App Store archive validation. |
| `Config/Info.plist`, entitlements and build scripts | Production plist still contains direct-channel update configuration; feasibility script strips it, changes ID and marks probe | Final bundle/version/build, minimal sandbox entitlements, App Store signing/provisioning/archive/export and shipping verifier. No development library-validation bypass, private exception or external unsandboxed helper. |
| `CopyStoryApp.swift:76`; core store/preference paths | Application Support URL moves into container; history, Images, Library and UserDefaults persist separately | Explicit import/data continuity and preference mapping. Sandbox signing does not migrate legacy files automatically. |
| `PlatformServices.swift:170–190` | Undocumented lock notification strings/session dictionary key; global monitor elsewhere | Public API/review audit, with conservative privacy behavior if unsupported signals must change. Source occurrence is a review risk requiring investigation, not proof of rejection. |
| Resources/listing | No PrivacyInfo.xcprivacy found in inspected source inventory; archive/listing not established | Audit required-reason APIs (including preferences/file metadata uses), applicable reasons and manifest inclusion; privacy/support policy, icon/screenshots and review notes. |

## What Apple and Maccy actually establish

[Apple DTS, thread 820594](https://developer.apple.com/forums/thread/820594)
distinguishes PostEvent, ListenEvent and Accessibility: the first two are sandbox
compatible; cross-app UI-state access under Accessibility is not. PostEvent and
Accessibility both appear under Accessibility in Settings. DTS explicitly cannot
guarantee App Review approval. The thread describes a rejection, so compatibility
must not be sold as an approval guarantee.

[Maccy's appstore Clipboard.swift](https://github.com/p0deje/Maccy/blob/appstore/Maccy/Clipboard.swift)
posts Command-V at `.cgSessionEventTap` and its
[appstore entitlements](https://github.com/p0deje/Maccy/blob/appstore/Maccy/Maccy.entitlements)
enable sandboxing. This is implementation precedent, not CopyStory runtime evidence.
That entitlement file also contains user-selected read access and temporary
Mach-lookup exceptions with Sparkle-style names; do not copy its whole entitlement
set or infer it is a minimal no-updater store configuration.

PR #9's controlled AX fixture logs establish that the unsandboxed original-window
and field queries returned 0 and sandbox queries returned -25204. They explicitly
record `pasteEventsPosted=false` and `automaticPasteVerified=false`. They prove
the tested AX-dependent path cannot proceed, not that CGEvent posting fails.

## Proposed direct-paste experiment and product contract

The candidate public API path is explicit user-triggered clipboard write plus a
single Command-V pair via `.cgSessionEventTap`, gated on PostEvent permission.
Apple documents [CGPreflightPostEventAccess](https://developer.apple.com/documentation/coregraphics/cgpreflightposteventaccess())
and [CGRequestPostEventAccess](https://developer.apple.com/documentation/coregraphics/cgrequestposteventaccess());
both declarations were also verified in the local SDK header. No permission API
was executed. Existing `postToPid` is a separate candidate to assess for documented
behavior and sandbox runtime; Maccy's session-event result cannot prove it works.

First prototype public nonactivating panel behavior, preserving the external app
while the user chooses history or fills a prompt. Capture explicit invocation's
destination PID, cancel on observed app activation/termination, timeout, selection
generation changes or clipboard replacement, then close/settle and recheck PID,
permission, cancellation and own-write before one event pair. Do not silently use
an older `lastExternalApp` as user intent when the app is already active. Handle
menu-bar invocation and prompt editing separately if they cannot preserve focus.

**Approved owner contract:** v1 prefers direct paste to the intended destination
application's *currently focused control*. Original window/field restoration or
verification is not promised. Every request must be explicitly user-triggered;
retain cancellation checks, single-request/no-retry behavior and prevent
unintended cross-app paste. Unsupported or protected contexts may fail safely;
do not attempt bypasses. Manual Copy remains a fallback, not a replacement for
preferred direct paste. Frontmost PID cannot detect a
same-app field/window change, and checks plus event posting are not atomic.
Session posting also has a final cross-app scheduling race. Approval of current
focus within the intended app does not approve pasting into another app.
Routing must be investigated and validated against this cross-app safety gate;
PID checks alone do not prove it. If the candidate cannot meet that gate, revise
the supported approach or move the release date. A nonactivating panel may reduce
disturbance but cannot prove field identity. Explain these limits accurately;
do not label the new contract equivalent to the existing original-field guard.

After plan agreement and separate interactive-test authorization, use a separate
signed identity and a synthetic target app with two windows/two fields. The
target itself logs event delivery and exact resulting synthetic text/image,
without cross-app AX queries. Use isolated hardware/VM clipboard/session; never
the daily general clipboard, existing history or account switching on this Mac.

| Controlled test | Acceptance evidence |
| --- | --- |
| Posting denied/granted/revoked; fresh relaunch | No event without permission; clear fallback; granted single request delivers exactly one insertion in the intended controlled context. PostEvent status alone is insufficient. |
| History text/image and rendered library prompt | Exact resulting target payload; no duplicate events; prompt persistence/admission and library/history independence preserved. |
| Shortcut, Return, double-click, menu/accessibility action; library variable/dropdown interaction | Working search/forms and exact destination outcome for every advertised invocation. Explicitly disable unsupported direct-paste contexts rather than claiming parity. |
| Different-app switch, termination, rapid repeat, cancellation, lock/sleep, intervening copy | Cancel on detected invalidation; clipboard error never triggers paste; no retries. Instrument destination and decoy apps, including switches at the final routing boundary: no unintended cross-app insertion. An unsafe route blocks release. |
| Same-app window/field change | Demonstrate insertion into the intended app's currently focused control; this is approved. No original-field identity claim. Unsupported/protected cases fail safely without bypasses. |
| Modifier held/released, supported keyboard layouts, full-screen/Spaces, non-editable/secure targets | No stuck modifier or repeated insertions; unsupported targets fall back or are explicitly documented. No bypass of secure-input policy. |

Do not report successful insertion merely because a CGEvent call returns or
clipboard writing succeeds. Production feedback should say paste was requested
unless the destination provides an actual acknowledgement.

## Reusable work packages for GitHub or Linear

Owners below are proposed roles, not assignment/implementation authorization.
Every package records exact commit/build, evidence links and passed/failed/unrun.

| ID / priority | Work and proposed owner | Depends on | Acceptance / decision gate |
| --- | --- | --- | --- |
| CS-01 / P0 | Finalize supported platforms and release identity — Francisco | This report | Decision/documentation COMPLETE October 13. Free/current-focus contract retained; Francisco approved macOS 26.0 minimum with 26/27 acceptance, arm64 only, shortcut/menu/mouse/VoiceOver scope, default-off login, CopyStory/com.copystory.app/1.0.0 and next unused build ≥5, optional empty-store all-or-nothing import. See release scope/QA matrix. Runtime/account acceptance remains downstream. |
| CS-02 / P0 | Prove sandbox direct paste into the intended application — engineering, Francisco for interactive session | CS-01 test scope + implementation/test instruction | Isolated signed candidate, no AX UI-state access, minimal entitlements; controlled event AND insertion matrix above passes for advertised contexts. Explicit user action, cancellation, no retries and no unintended cross-app insertion; protected/unsupported cases fail safely. Document current-focus limits and App Review risk. Update #8 later. |
| CS-03 / P0 | Shipping target/archive — engineering; Francisco account/signing owner | CS-01; final paste integration depends on CS-02 | Establish full Xcode; final ID, normal launch, store signing/provisioning/export; no Sparkle/probe markers; strict all-architecture signatures and archive validation pass. Rebuild separately and investigate old signature discrepancy. No account/legal changes without authorization. |
| CS-04 / P0 | Explicit legacy data import — engineering, Francisco import UX decision | CS-01; integrate into CS-03 | Synthetic fixtures cover history/images/pins, library/options/defaults/favorites and preferences. User-selected read access only as needed; quiescent source, schema validation, staging/atomic commit, interrupted/corrupt/repeat import recovery; source preserved. Never two app copies sharing one store. |
| CS-05 / P0 | Shipping paste integration and consent/help — engineering | CS-02, CS-03 | Both history and prompts use approved coordinator; all UI/actions agree; PostEvent vs clipboard-read consent separate; clipboard writes/admission/cancellation invariants maintained. Revocation and fallback covered. |
| CS-06 / P0 | Final acceptance and privacy/API audit — engineering/QA, Francisco support decisions | CS-03–05 | Exact-commit full store tests/CI; fresh final-artifact interactive capture allow/deny/revoke, hotkey, persistence/retention/exclusions/lock, paste matrix, VoiceOver/Reduce Transparency, login consent/revoke/actual launch if retained; each declared OS/architecture runtime covered. Required-reason/public API audit and accurate network/privacy evidence. Update #6 later. |
| CS-07 / P0 | Account and listing readiness — Francisco, engineering prepares drafts/assets | CS-01; final assets depend on CS-05/06 | Verify current membership/roles/agreements, app record/ID, appropriate signing assets; free price, availability, age rating/export compliance/trader decisions; working support/privacy URLs, final synthetic screenshots/icon, accurate privacy answers and reviewer instructions. Historical Developer ID/notarization is not store signing proof. |
| CS-08 / P0 | TestFlight/submission/public release — Francisco authorizes; engineering executes later | CS-06 + CS-07 | Exact artifact/listing approval; build processing and TestFlight acceptance; separately authorized submission; App Review approval and release choice; public listing/fresh store installation verified before declaring live. Update #5 later. |
| CS-09 / deferred | Direct-channel Sparkle recovery — existing #4 | Outside store v1 | Remains separate; Sparkle key backup/recovery work does not gate a no-Sparkle store release. Preserve artifacts/keys. |

CS-03 archive setup, CS-04 import design, and CS-07 listing preparation can be
prepared alongside CS-02 after the plan is agreed; final shipping integration
and acceptance depend on proven direct paste. Do not close #8/#6/#5 on a
feasibility merge or a successful compile.

## Evidence status and schedule

October 14 follow-up: [FRO-22 prototype evidence](DIRECT_PASTE_PROTOTYPE_2026-10-14.md)
records the separate signed arm64 harness, 13 passing routing-policy tests and
actual direct named-board text/image/prompt insertion into the intended fixture.
Initial target-only runs had zero decoy delivery. Native shortcut/left/right-menu
tests each inserted once into the freshly captured app: shortcut/left captured
decoy, right captured target; no target-captured request delivered to decoy.
Keyboard/Escape, expiry, open-panel switch cancellation, current-window changes
and one controlled full-screen bridge case were checked. Shipping recipient/
failure feedback, native full-screen/Spaces and final invocation acceptance
remain incomplete. The original ad-hoc consent mismatch was resolved
using a distinct, stably signed CS Paste Probe identity and fixed runtime path.
Controlled clipboard replacement, switch away/back and target termination
cancelled pending requests; changing fields/windows within the intended app
used its current focus. PostEvent-only reset left effective access intact;
separately approved probe-only Accessibility reset/regrant then passed a fresh
denied/no-event, manual fallback and regranted actual-insertion cycle on the
then-current build 3. Build 5 retained effective access with the same signing
requirement; this continuation changed no permission/account setting. FRO-22
stays in progress; shipping integration still requires pending-request
revocation, supported
invocation/platform and ordinary/protected-app acceptance. No daily general
clipboard, installed app or real history was used.

CS-01 decision/documentation is complete in the
[release scope and QA matrix](APP_STORE_RELEASE_SCOPE_2026-10-13.md), based on
live FRO-21, root source inspection and Francisco's explicit approval of all
three proposed decision groups on October 13. Free pricing/current-focus paste
stay approved. All shipping final-artifact QA remains unrun; account identity/build
availability and implementation remain downstream gates.

| Evidence | Status |
| --- | --- |
| Fresh installed metadata, local/remote commit comparison, PR/issues and exact-head CI lookup | Completed read-only; CI result success, not a fresh local test run |
| Saved October 11 Swift tests | 87 per configuration, 13 release and 3 rehearsal tests PASSED historically; see migration doc/logs |
| Prior October 13 restricted-session attempt | 37 core tests PASSED; platform target FAILED with pasteboard write expectation/XPC/Launch Services diagnostics and signal 6; entire suite NOT PASSED. No broad rerun here. See `/tmp/copystory-readiness-store-tests-final.log`. |
| Saved synthetic container/named-pasteboard/hotkey probes | PASSED historically; not general clipboard, real login, shortcut UI or paste insertion acceptance |
| Prior preserved sandbox strict signature | FAILED in the earlier inspected artifact; executable hash matches its saved record, cause unresolved. The separate new prototype bundles pass strict verification. |
| New sandbox direct-paste event/insertion matrix | Local fixture feasibility PASSED: actual text/image/prompt insertion, zero decoy delivery, controlled cancellation and approved denied/regrant cycle. Full shipping invocation/platform/ordinary-app acceptance remains incomplete; see FRO-22 evidence. |
| Shipping archive/import/final platform/listing/TestFlight/store review | UNRUN or not established; historical account sign-in barrier remains unverified here |

Tuesday October 13: current-focus safety contract and CS-01 product scope
approved/documented; start the isolated proof only after implementation/test authorization.
Wednesday October 14: assess CS-02 results before committing to
shipping integration/acceptance; prepare archive/import/listing alongside it.
Thursday October 15: release only if all product/acceptance/account/review gates
actually pass. Otherwise move the date while retaining free/direct-paste scope.
Two days is a high-risk target with the current unresolved dependencies.

Submission-ready means accepted binary/listing and evidence complete; submitted
or in review means Apple has it; live means approved, released and publicly
available. Apple's [release options guidance](https://developer.apple.com/help/app-store-connect/manage-your-apps-availability/select-an-app-store-version-release-option/)
warns availability can take up to 24 hours after manual release. No approval or
processing time can be guaranteed by this roadmap.

Linear would help coordinate the engineering/account/QA dependencies if Francisco
wants one release view. Proposed project: **CopyStory — Free Mac App Store v1**,
with separate milestones **Direct paste proven**, **Submission ready**, and
**Publicly live**, using CS-01–09 as import-ready tasks. Link existing GitHub
issues/PRs instead of creating duplicate independent status records. GitHub's
four existing issues are sufficient if a second tracker adds overhead. No Linear
project or issue was created or inspected in this task.

## Supporting local evidence

- `docs/APP_STORE_MIGRATION.md` and `.build/app-store-feasibility/verification-summary.json`.
- `.build/app-store-feasibility/ax-target-control.log` and `ax-target-sandbox.log`.
- `docs/RELEASE_ACCEPTANCE_2026-10-11.md` for direct-channel provenance; not a store acceptance record.
- `CONTRIBUTING.md` and `docs/PRIVACY.md` for synthetic-data and safety invariants.
- Historical conversation backups remain local and are excluded from source publication.

This new planning document is the only intended repository addition. Existing
tracked source and the nested checkout remain intact; nothing committed/pushed.
