# App Store 2.4.5 remediation — 2026-11-11

## Rejection and source evidence

App Review rejected macOS 1.0.0 build 22 for requesting Accessibility access for
non-accessibility automation, and required removal of such features. This is
Apple's App Review guideline, not WCAG's identically numbered success criterion.
[Review submission](https://appstoreconnect.apple.com/apps/6826654255/distribution/reviewsubmissions/details/0d406473-84dd-4955-b0c8-43afb77c7bf1).
[Current official guidelines](https://developer.apple.com/app-store/review/guidelines/#hardware-compatibility).

The installed App Store/TestFlight package's Info.plist identifies build 22,
Production, clean source `43bfafce3b728fa339de66c81ebdbc87e35f61ff`.
The freshly fetched remote main matched this SHA. The dirty root checkout and
nested old clone were preserved; remediation uses an isolated branch/worktree.

The rejected binary imports `CGRequestPostEventAccess`,
`CGPreflightPostEventAccess`, `CGEventCreateKeyboardEvent`, and `CGEventPostToPid`.
Source trace: Preferences exposes experimental Direct Paste plus an explicit
"Request event-posting access" button; PasteCoordinator requests consent;
NativePastePlatform creates and posts a Command–V pair to the captured external
PID. Default-off does not remove this App Store functionality. The History setup
banner and onboarding also direct users toward it. This is concrete evidence of
the offending behavior. Apple did not name Direct Paste or disclose the exact
reviewer interaction, so the precise interaction remains unverified.

## Product change and audit

Production is copy-only, regardless of a stale saved `directPasteEnabled=true`.
History Return/double-click and Library Command–Return copy. Context menus,
footer hints, onboarding, Preferences and VoiceOver actions describe Copy.
Copy does not activate a destination or synthesize input. Users select their
destination and press Command–V themselves; the panel does not auto-switch them.
This is the material convenience tradeoff.

History capture, storage, search, images, pins, Library/templates/variables,
favorites, manual Copy, configurable Carbon global shortcut (Option–C default),
login choice, and native VoiceOver labels/traits/actions remain. No store/schema
migration or deletion is introduced. Existing stale paste opt-in is ignored,
without resetting shortcut choices, consent, or other preferences.

Production compile gates disable permission/posting, and preprocessor exclusion
removes the actual permission APIs and synthetic-event implementation even from
unoptimized builds. Development/prototype behavior remains separate and is not
App Store acceptance evidence. SandboxProbe's AX queries now have an explicit
non-production guard, and Production excludes both probe and readiness source
files. The project generator already omitted SandboxProbe from ordinary app
builds; its old APP_STORE guard alone was insufficient defense if added later.

Source audit found no other Accessibility automation, event taps, AppleScript or
shell automation in normal app sources. Native local NSEvent keyboard/mouse monitors handle the app's own UI;
a global mouse-click monitor dismisses the panel on outside clicks (no global
keyboard monitoring or Accessibility permission request); Carbon RegisterEventHotKey implements the
shortcut without Accessibility permission. SwiftUI accessibility labels,
custom Copy/pin/favorite actions, reduce-motion and reduce-transparency support
remain. App Store entitlements remain sandbox plus user-selected read-only files;
there is no automation or Accessibility entitlement. No updater is included.

## Regression and release enforcement

- `scripts/test-development.sh`: existing offline synthetic regression suites.
- `scripts/test-production-copy-only.sh`: actual Production compile selection;
  injected clipboard, focus and posting sinks; temporary stores/preferences.
  Covers stale opt-in, repeated History/Library actions without a destination or
  permission, interrupted load and explicit retry, clipboard failure/recovery,
  no activation/posting, preserved History and default shortcut.
- CI runs both the offline suites and production copy-only tests/build.
- `scripts/verify-app-store-automation.py APP`: scans undefined imports in every
  Mach-O, including nested helpers/frameworks, rejecting AX automation, event
  posting/taps/creation and permission-request/preflight APIs. It rejects the
  old build 22 binary, which provides a real negative control.
- A generated Xcode build phase runs this check on every Production build/archive.
  `verify-production.py` also requires closed permission/posting gates and the
  same binary check. Run the standalone verifier again on the final exported app;
  a later packaging/re-signing/export step is outside a build-phase guarantee.

## Acceptance limits and remaining manual QA

No reviewer reply, upload, resubmission, merge, release or installation is part
of this fix. A build0 unsigned package is not an allocated App Store release.
App Review makes the final acceptance decision.

Before submission, use the final signed/exported artifact on supported macOS
versions (26 and 27) and representative Apple silicon hardware. Verify:

1. Fresh onboarding, Preferences, reopening, quit/relaunch: no Accessibility
   prompt, setup call-to-action or Direct Paste control. Check an upgrade with a
   previously enabled paste preference and existing TCC grant, plus a clean test
   account without such grant. No TCC reset is needed for this fix.
2. Option–C and custom shortcuts; Return/double-click/context Copy; text and
   image copy; switch to a separate app and manually Command–V. Repeat after
   Escape, search changes, sleep and interruptions. Clipboard denial should
   produce truthful feedback and recover on a subsequent explicit action.
3. Library variables/defaults, Command–Return Copy, favorites, search and pins;
   no history loss, unintended duplicate History replay or preference reset.
4. VoiceOver navigation, row Copy/pin actions, selected state, focus order,
   keyboard-only use, reduce motion/transparency. The ordinary Edit > Paste
   menu still pastes into CopyStory's own editable fields; it is not external
   input automation and should remain.
5. Final export: run the automation verifier, inspect signature/sandbox
   entitlements and provenance, and update any listing/review notes/screenshots
   that promise automatic/direct paste. Do not claim insertion automation.

Actual validation results and artifact digests are recorded in the implementation
PR/task evidence; manual native QA is not implied by synthetic/static passes.

## Local validation observed

On the macOS 27 / Xcode 27.2 host, the existing offline run passed 166 platform
and 63 core tests. Production-specific tests passed 3 test functions (including
both History/Library parameter cases). An unsigned arm64 Production build passed
package/resource/privacy/architecture checks and the binary API gate; the old
build 22 failed that gate on `CGEventCreateKeyboardEvent`, as expected. Initial
sandbox cache restrictions required rerunning Xcode/SwiftPM with approved cache
access. An early production-gate assertion caught an incomplete constant edit;
the constants were corrected and the production suite passed on rerun.

Native runtime/VoiceOver tests, Apple distribution signing/export and App Review
acceptance remain unrun. No installed app was stopped or restarted, and no real
clipboard content was used in the synthetic suites. The final clean-source
archive, executable digest and exact command results are recorded with the task
and PR so they can be matched to the commit, rather than editing this source
again after building it.
