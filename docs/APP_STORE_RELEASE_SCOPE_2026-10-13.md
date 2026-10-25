# App Store release scope — CS-01 / FRO-21

Prepared October 13, 2026. **Status: product decisions approved by Francisco; CS-01 documentation complete.** This is documentation, not implementation or runtime
acceptance. [Live FRO-21](https://linear.app/fromokaytogreat/issue/FRO-21/finalize-supported-platforms-and-release-identity)
was read on this date; it gates FRO-22, FRO-23, FRO-24 and FRO-28.
Related GitHub issues: #8 feasibility, #6 acceptance, #5 submission.

## Approved scope

- Free app; no pricing decision remains open.
- Direct paste is preferred after an explicit user action, into the currently
  focused control of the intended destination application. No originally
  focused field/window verification or restoration is promised.
- Unsupported/protected contexts may fail safely with manual Copy fallback.
  Do not bypass protections or allow unintended cross-app paste. Frontmost PID
  checks alone do not establish safe event delivery or actual insertion.

These decisions are already approved in the roadmap. They remain binding on
every approved context below. Implementing or testing them needs separate scope
authorization; this document supplies neither.

## Verified local baseline

Root: `codex/app-store-migration`, `7305c697d57d6e21a79904e15a1f70f5a6fd7119`.
Before this work, no tracked changes; roadmap and nested `CopyStory/` untracked.
Nested checkout: clean main at `2af4ff0535af84be570f81f14482971fb27d77b8`;
preserved without edits. Remote heads, installed app metadata and signature were
not rechecked here; their dated evidence remains in the roadmap.

`Package.swift` and `Config/Info.plist` declare macOS 26.0. The production plist
names CopyStory, `com.copystory.app`, version 0.3.0/build 4, with menu-bar app
mode. The feasibility bundle uses `com.copystory.sandbox-feasibility`, rejects
ordinary launch and cannot serve as the shipping app. Source uses
`NSGlassEffectView`; lowering the deployment target requires an API/fallback
audit, implementation and acceptance rather than changing the manifest alone.

Historical direct-channel acceptance: arm64 automated runtime on 26.6.2 and
27.0.1, universal package verification, no Intel runtime or exact 26.0 acceptance.
Historical sandbox evidence is narrower and has a later signature discrepancy;
none establishes shipping App Store runtime support.

## Decisions approved October 13, 2026

| Decision | Approved choice | Reason / consequence |
| --- | --- | --- |
| Platform | macOS only for this release; minimum 26.0; support macOS 26 and 27 after final acceptance | Matches existing deployment/API baseline. iOS/iPadOS and older macOS require separate work; future major macOS versions are unverified until tested. |
| Architectures | Apple silicon (arm64) for v1; defer Intel | Intel has compilation evidence only. Narrows runtime QA, but excludes Intel users and requires shipping packaging/listing to agree. Intel is outside this release scope; adding it requires a new owner decision and native runtime acceptance. |
| Invocation | Keep configurable Option–V (⌥V), left-click menu-bar opening and right-click → Open CopyStory; keyboard, mouse and VoiceOver actions | These exist in source; sandbox destination preservation is unproven for each. All advertised paths need their own controlled proof. |
| Launch at login | Retain, default off, explicit opt-in; main app only | Existing SMAppService implementation is suitable to investigate. Actual login launch, approval and revocation remain unrun. |
| Identity | CopyStory; production bundle ID `com.copystory.app`; first store marketing version 1.0.0 | Preserves app identity; does not automatically migrate data or permissions. App ID ownership and App Store Connect record must be verified before this becomes a shipping identity. |
| Build numbering | Next candidate starts at 5 only if no higher number is already allocated/uploaded; increase for each distributable candidate across channels | Existing candidate is build 4. Use a release ledger with version/build/commit/channel/hashes; never silently relabel an old artifact or reuse an uploaded candidate number. |
| Import | Optional “Import from previous CopyStory” at onboarding and later in Preferences; user selects source; copy into an empty destination only | Keeps old data intact; avoids silent migration and an unproven merge policy. Cancel/Skip permits a fresh start. Later import into a nonempty store is refused without changing either store. |

Apple requires build identity metadata and uses bundle ID/version/build to match
uploads. Bundle ID becomes fixed after the first upload; verify the app record
before committing it: [distribution guidance](https://help.apple.com/xcode/mac/current/en.lproj/dev91fe7130a.html),
[CFBundleVersion](https://developer.apple.com/documentation/BundleResources/Information-Property-List/CFBundleVersion).
This policy is approved; it is not evidence that App Store Connect is ready.

### Invocation and accessibility behavior

Single-click selects a history row; Return, double-click or an explicit Paste
action requests paste. Library row activation opens the form; its Paste button
requests paste of the completed prompt. Merely opening/selecting/searching,
editing a form, closing the panel or importing must not send a paste event.
Command–C and Copy remain explicit copy-only actions. Editor Return/arrow/copy
keys retain editing semantics. Rapid activation must not create retries.

At invocation, establish the intended external application for that request;
never reuse a stale last-external-app value when CopyStory is already active.
Menu opening, mouse interaction, form editing and VoiceOver may affect activation
differently. If a path cannot establish/preserve the intended application, use
truthful copy fallback for that operation. Preferences/onboarding/Finder launch
do not establish an external paste destination. Unsupported full-screen/Spaces
or protected destinations fail safely; no undocumented supported-app whitelist
is implied. Two windows/fields in one app test current-focus semantics, not
original-field identity. Cross-app event routing is a release gate.

Require keyboard-only access to history, library/forms, preferences, import and
fallback; visible focus; descriptive VoiceOver labels/actions/selection/error
announcements; readable Reduce Transparency/Reduce Motion alternatives. User
action through assistive technology is an explicit action. In-app accessibility
does not require cross-app AX inspection. Explain PostEvent consent separately
from clipboard-recording consent; asking for permission does not grant it.

### Login behavior

Offer an unchecked opt-in and report system state: enabled, disabled, approval
required or unavailable. Registered/approval-required must not be described as
actively enabled. Login starts the menu-bar app without opening history or
pasting; recording respects completed onboarding, capture consent and saved
pause state. Disabling/revoking must not trigger silent re-registration.
Import cannot transfer system authorization or auto-enable login. No auxiliary
external helper is part of the approved scope. [Apple main app service](https://developer.apple.com/documentation/servicemanagement/smappservice/mainapp)
and [registration](https://developer.apple.com/documentation/servicemanagement/smappservice/register%28%29)
describe user approval; registration success is not proof of actual login launch.

### Import and recovery contract

User chooses the legacy Application Support/CopyStory folder using read-only
user-selected access as needed. Explain that preferences are stored separately;
offer a separate optional selection of a supported legacy preference export/file,
without scanning the user's Library. Data-only import is allowed and clearly
reports preferences not imported. Do not claim an export tool already exists.

Copy all validated history/text/images/pins and library templates, variable
options/defaults/favorites. Preserve IDs, timestamps and content; regenerate
derived search/thumbnail data where appropriate. Import supported preferences
only from an allowlist: limits, retention, marker protection, exclusions, pause
state and shortcut, with validation/conflict handling. Do not import updater
settings, onboarding completion, system permissions or login registration.
Show source/selection/counts/warnings without leaking contents into diagnostics.

Require the legacy app to quit and the source to be quiescent; never open a
shared store for writing or rely on copying a live SQLite main file without
its journals. Validate schema, database integrity, image references, supported
sizes and safe paths; reject newer schema, corrupt/missing required payloads,
symlink/path escapes and unstable sources with an actionable message. Use
all-or-nothing import; do not silently recover only part of the selection. Preserve the source.

Stage outside the active store, then commit history, library, selected
preferences and an import marker as one recoverable generation. Multi-file
atomicity requires an implementation design; separate renames are insufficient.
Cancel, permission loss, low disk or interruption before commit leaves the
previous destination intact. Relaunch detects unfinished work and cleans/retries
staging without exposing partial data. After committed import, a repeated request
is detected and does not duplicate entries. Never offer deletion/reset as an
automatic recovery step. No in-app merge/replace of nonempty data in v1.

Before commit, disclose if imported data conflicts with size/retention settings;
do not silently prune it at import or first relaunch. Permit an explicit adequate
limit/retention choice or cancel. Pins survive; normal future retention/limits
resume only after the user understands the chosen settings.

## QA matrix — approved scope, not test results

All rows below are **UNRUN for the final App Store artifact**. Owner approval
adopts criteria, never waives evidence. Use synthetic fixtures and isolated
sessions, record exact commit/build/OS/hardware/permission/action/observed
insertion and distinguish source, model tests and runtime observations.

| ID | Required evidence / pass criterion |
| --- | --- |
| CS01-OS | Native arm64 sessions on 26.0, a current 26.x patch and supported 27.x; capture, history/library, persistence, invocation and privacy behavior. Exact minimum cannot be inferred from 26.6.2. Intel is excluded from v1; shipping architecture metadata/listing must agree on arm64 only. |
| CS01-ID | Final archive and exported app agree on approved name/ID/minimum/architectures/version/build; correct team/provisioning/signatures; ordinary launch; no probe markers or Sparkle. Record ledger and App Store Connect identity separately. |
| CS01-KEY | Default/custom shortcut, conflict/relaunch/toggle/Escape; arrows/search/Return/Copy; held modifiers and alternate layouts; explicit single paste request with observed intended-app insertion. |
| CS01-MOUSE | Left menu-bar click, right-click Open, history single/double-click/context Paste, library form Paste; outside-dismiss sends nothing; invocation destination unambiguous or truthful fallback. |
| CS01-AX | Keyboard-only and VoiceOver primary tasks, labels/errors/import controls; Reduce Transparency/Motion; each explicit paste action preserves destination semantics or fails safely. No cross-app AX field claim. |
| CS01-ROUTE | Controlled two-window/two-field current-focus cases; app switch/termination, full-screen/Spaces, delayed routing, denied/revoked PostEvent, noneditable/protected/image-incompatible target; cancel safely, no unintended cross-app insertion, no retries; event posted is not proof of insertion. |
| CS01-LOGIN | Fresh default off; opt-in/approval-required/actual login launch; deny/revoke/disable/relaunch; no panel or paste on login, pause/consent respected; no silent re-registration. Separate hardware/VM required; account switching here stays paused. |
| CS01-IMPORT | Skip/cancel/later selection, source denied/active/changed, separate preferences missing/invalid, empty/nonempty destination, history/images/pins and complete library; source byte preservation and no shared writes. |
| CS01-RECOVER | Newer/corrupt schema, missing payloads, unsafe paths, low disk, interrupted staging/commit/relaunch, retry/repeat, preference conflict, retention/capacity conflict; source and prior destination intact, no partial committed state/duplicates/silent pruning. |

## Decision and release gates

Francisco explicitly selected all three recommended options in this chat on
October 13: Apple silicon only/macOS 26–27 with minimum 26.0; the proposed
interaction and default-off login scope; and CopyStory identity/version/build
policy plus optional empty-store all-or-nothing import and recovery criteria.
The decisions above and this QA matrix record that approved scope. CS-01 is
complete as a decision/documentation task.

Account identity availability, next unused build allocation, implementation and
final-artifact runtime acceptance remain downstream verification, not assumed
facts. If an approved feature cannot pass, bring the scope/date decision back to
Francisco; do not silently remove it or claim the release is ready.

Thursday October 15, 2026 (America/Los_Angeles) is the public-release target.
Submission-ready, submitted/in-review and publicly live are separate gates.
This decision document does not establish any of them. No source configuration,
installed app, clipboard/history, account/permission/signing state or nested
checkout was changed. No build, broad test, prototype or runtime probe was run.

## Shortcut decision update · 2026-10-24

The official product default is Option–V (⌥V), as requested by Francisco. This supersedes the earlier default in this scope. Preserve explicit custom shortcuts and the development build’s default-off global-shortcut setting. Historical test records describe the keys actually used at the time.
