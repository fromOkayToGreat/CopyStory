# Proposed next slice: History adapter model with recording sinks

**Specification only; implementation is awaiting forwarded owner approval.** This is a bounded History-only simulation layer. It does not enable actual paste, modify Library lifecycle or restore lost build7 bytes. The current AutomaticPastePolicy and app-entry hard gates remain intact.

## Purpose and inputs

Exercise the History request lifecycle against injected snapshots and recording sinks before considering any OS adapter. Reuse the current History storage/UI and the separately reviewed QA gate/identity/ownership models where appropriate; preserve their provenance and adapt only within a reviewed new change map. Do not import the QA app/fixture framework into shipping UI or transfer its runtime passes.

Inputs are synthetic payload values, explicit action type, request generation, captured intended-application identity (PID/bundle/path/launch identity), liveness/current-frontmost snapshot, clock, own-write count, permission state and modifier-release state. All are supplied by tests. The recording sink stores ordered intentions/results in memory. It cannot call NSPasteboard, CGEvent, AX, NSWorkspace activation/observers, global shortcuts, permission APIs, login services or settings. No OS event sink is implemented, exposed or configurable. No real application focus is queried or changed.

## Behavioral contract for review

| Trigger or state | Expected recording-model behavior |
| --- | --- |
| Open/select/search/navigate/edit | No write, history admission or event intent. Opening creates a fresh generation only when explicitly modelled; no destination inferred from old focus history. |
| Explicit History Paste (Return/double-click/context/accessibility action represented as input) | Consume one request for the current generation; use only its captured launch identity. Production UI remains disconnected/disabled; these are simulated inputs, not native-input acceptance. |
| Explicit Copy | Separate simulated write intent only; never schedule a Paste intent. Merely choosing/opening an item cannot invoke it. Existing real Copy code is not exercised or changed in this slice. |
| Successful simulated write | Record exact synthetic payload once and own-write token/count; record history-admission callback once after successful write. No admission before success and no duplicate admission. This is logical sequencing evidence, not actual clipboard/history acceptance. |
| Failed write | No admission, dismissal-dependent continuation or event intent. Failure consumes the attempt; no implicit retry. |
| Pending cancellation/app switch/termination/Space/sleep/selection change | Sticky invalidation; target return does not rehabilitate the request. Cancelled-before-selection work cannot rewrite. Inject notifications as values only, with no live observers. |
| Final dispatch intent | Require current generation/identity/liveness/foreground/board/permission/released modifiers/expiry; claim once. Freeze one PID for down/up recording intentions. A recording result is not an OS event and cannot be described as an actual posted event. |
| Change after final validation or between down/up | Preserve explicit race characterization; do not claim OS atomicity or actual permission enforcement. Do not retry or redirect a release to another PID. |
| Old completion after new request | Cannot consume, clear busy state, dismiss, overwrite feedback or otherwise mutate the newer generation. Cleanup is owner/token-specific. |
| Feedback | Say simulated/blocked/unconfirmed as appropriate. Never say “Copied,” “Paste requested,” “inserted” or granted merely because a recording sink accepted intent. A future live adapter must separately establish each real operation’s semantics. |

The model can represent a denied permission snapshot and reject it. It does not solve stale in-process permission observations. The existing FRO22 criterion—effective loss while pending, zero source posting, truthful fallback and controlled restoration—remains unchanged. The prior revocation run stays inconclusive. No live permission or protected-input test is part of this slice.

## Proposed verification and review deliverable

Add focused deterministic regressions for explicit-action separation, write/admission ordering, duplicate consumption/no retry, cancellation before/after claim, stale-generation completion, identity change with same PID, final modifier/expiry/permission checks and exact recording order/PID. Inject failures and changes at meaningful boundaries. Retain existing race-characterization limits. Avoid tests that merely assert implementation constants or chase historical test counts.

Compile only and statically confirm the app still early-exits and links no event-posting/AX/permission-request sink. Execute only pure/injected-model and relevant synthetic storage tests, with no GUI/live clipboard. Preserve the layer as local commit plus full source archive and verified Git bundle outside build/temp directories. Return exact source/tree/toolchain/dependency and result hashes for independent review before any broader integration. This specification supplies no elapsed-time forecast.

## Deferred / unknown

- Real nonactivating History invocation/menu/hotkey adapter, native modifier/layout behavior and final current-focus semantics remain unimplemented/unverified.
- Real clipboard writing, admission ordering under capture/clear/exclusions/pause/retention, recipient acknowledgements and runtime safeguards need separate integration/review; synthetic sinks do not close them.
- Library form dismissal/paste lifetime and the lost FRO30 fix are explicitly later. Current source behavior and historical prose cannot supply exact lost code; prepare a separate Library lifecycle specification after the History slice review. Do not route Library through an incomplete History model by accident.
- Login default-on mismatch must be resolved against approved off intent before any launch. Import, privacy manifest/API audit, signing/accounts, platform/VoiceOver QA and release gates remain separate.

No implementation, launch, event, clipboard, permission, signing or release action is authorized by this specification. Parent must forward owner approval before coding this slice.
