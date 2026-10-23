# App Store migration and sandbox feasibility

Started October 11, 2026 from main `2af4ff0535af84be570f81f14482971fb27d77b8`.
Preserved remote tag: `baseline/direct-distribution-0.3.0`. Migration branch:
`codex/app-store-migration`. The prior signed candidates and their local evidence
remain intact; the tag is not a public app release.

October 13 scope update: free pricing and intended-application current-focus
direct paste are approved in the [roadmap](APP_STORE_ROADMAP_2026-10-13.md).
The earlier manual-only product option below is superseded. Original-field AX
restoration remains historical feasibility evidence, not the new store contract.
See the [CS-01 release scope and QA matrix](APP_STORE_RELEASE_SCOPE_2026-10-13.md)
for the product decisions approved by Francisco on October 13 and unrun
final-artifact acceptance criteria.

## Plan and issue dependencies

- [#8](https://github.com/fromOkayToGreat/CopyStory/issues/8): sandbox feasibility
  and automatic-paste compatibility first; review the findings and product scope.
- [#6](https://github.com/fromOkayToGreat/CopyStory/issues/6): accept the sandboxed
  build's platforms, clipboard behavior, permissions, privacy and accessibility.
- [#5](https://github.com/fromOkayToGreat/CopyStory/issues/5): App Store identity,
  signing/provisioning/archive, App Store Connect/TestFlight and submission.
- [#4](https://github.com/fromOkayToGreat/CopyStory/issues/4): deferred direct-channel
  Sparkle failure/recovery work. It does not gate a store build without Sparkle.

The production Sparkle key remains untouched. Its backup is a direct-channel
continuity safeguard, not an App Store submission prerequisite. No submission,
publication, installation replacement or migration of real data is authorized by
this feasibility build. Second-account testing stays paused; destructive fault
injection requires a disposable snapshot-capable VM.

## Build boundary

This is a transitional compile configuration, not a commitment to maintaining two
shipping channels. Default SwiftPM builds still use the preserved direct-channel
configuration so baseline checks remain runnable. `COPYSTORY_APP_STORE=1` compiles
without any Sparkle package dependency. The store configuration uses an inert
UpdateService while native menus/preferences omit update controls. Once store
scope is settled, retire the legacy path deliberately rather than deleting its
evidence during feasibility.

Use the helper scripts instead of setting the flag directly at the repository
root. SwiftPM removes Package.resolved when the manifest has no dependencies;
the helpers prepare an ignored source copy and separate scratch directories so
the original lockfile and existing release artifacts remain unchanged. Run the
helpers sequentially because they refresh the same generated source copy.

```sh
scripts/test-app-store-feasibility.sh
scripts/build-app-store-feasibility.sh
python3 scripts/probe-app-store-feasibility.py
open -n '.build/app-store-feasibility/CopyStory Sandbox.app' --args --demo
```

The default signature is ad-hoc for CI/local testing. To test a Developer ID
signature, set COPYSTORY_SIGNING_IDENTITY to an existing identity; no signing keys
are exported. Developer ID signing here is not App Store distribution signing.

The generated bundle is universal and uses only `com.apple.security.app-sandbox`.
It has no network, automation, temporary-exception or library-validation-bypass
entitlements. The verifier rejects unexpected entitlements, a production bundle
identity, Sparkle linkage/framework/configuration, or missing architectures.

Identity: `com.copystory.sandbox-feasibility`; output:
`.build/app-store-feasibility/CopyStory Sandbox.app`. Only `--demo`,
`--sandbox-probe`, and the package runtime check are supported. Ordinary launch
exits before an app delegate is created. Demo mode uses temporary synthetic data
and disables clipboard writes, capture, hotkey and login registration. This is
intentionally not a daily-use or App Store submission build.

## Local evidence — macOS 27.0.1 (26A434), Apple silicon

- Universal sandbox package built and strict signature verification passed with
  Developer ID team MBA354NC7J. No Sparkle linked, embedded or configured.
- All 87 Swift tests passed in both compile configurations (50 platform/model,
  37 core), including the new preview-hotkey isolation regression test. These tests are not themselves sandbox runtime evidence.
- 13 legacy release tests and 3 rehearsal-isolation tests passed.
- The signed sandbox executable separately wrote and reopened synthetic history
  and a prompt with a variable default. Clearing the probe history preserved its
  library. Both process invocations passed.
- FileManager's Application Support URL resolved inside the probe's container;
  reading an existing synthetic file outside that container failed with a
  permission error. The probe never opens production history.
- Named-pasteboard text capture using ClipboardMonitor passed. No general
  clipboard was read or changed. General-clipboard permission and image capture
  in the sandbox remain interactive acceptance items.
- Registration/unregistration of an uncommon global shortcut passed. This is not
  proof that the normal shortcut opens the panel in every desktop/session state.
- Ordinary launch without the explicit demo/probe arguments was rejected.
- Native demo History/Library navigation and Preferences were inspected; no
  updater controls or Accessibility setup buttons remained. The first demo
  attempted the normal hotkey and hit the existing app's registration; the
  feasibility preview now explicitly skips shortcut registration/changes.

Local logs: `.build/app-store-feasibility/` (build.log, store-tests.log,
baseline-tests.log, probe-results.log, probe-write.log, probe-read.log).
The probe leaves only uniquely named synthetic stores inside its own container.

## Automatic paste: current implementation blocked in the sandbox

The existing implementation uses AXUIElement to remember and restore another
app's focused window/field and then posts a single Command-V pair to the verified
process. Removing those identity checks to get an event through would weaken the
existing paste safety behavior and is not an acceptable shortcut.

Apple's [sandbox guidance](https://developer.apple.com/documentation/security/protecting-user-data-with-app-sandbox)
lists use of accessibility APIs in assistive apps among incompatible activities.
This makes the existing cross-app focus implementation a store compatibility
blocker to resolve. [Review guideline 2.4.5](https://developer.apple.com/app-store/review/guidelines/#hardware-compatibility)
also requires sandboxing and App Store updates, so the store bundle cannot use
the existing Sparkle updater.

The sandbox probe queried only the Accessibility API result code; it did not
read focused content, request permissions, or post key events. AXIsProcessTrusted
returned true, while the focused-application query returned -25204
(kAXErrorCannotComplete). An unsandboxed Swift control returned the same result.
Therefore this runtime result does **not** isolate a sandbox denial and cannot
prove that granting permission would solve the issue. Trust status alone does
not prove cross-app AX access or successful insertion.

A stronger controlled comparison used the included synthetic AXFixture window.
The unsandboxed AXControl read both AXFocusedWindow and AXFocusedUIElement
successfully (result 0). The signed sandbox executable queried the same fixture
PID and both returned -25204, with trust reported true. This isolates a failure
of the current cross-app focus path in the tested sandbox environment. The
existing paste coordinator requires those identities, so it cannot safely reach
its event-posting step. No event was posted, and no insertion is claimed.

Reproduce with `scripts/build-ax-fixture.sh`, launch the generated AX Fixture app
and focus its synthetic text field, then run
`swift scripts/sandbox/AXControl.swift TARGET_PID`. For the sandbox comparison,
add `--ax-target-pid TARGET_PID` to the normal `--sandbox-probe --probe-run UUID
--outside-fixture PATH` invocation, using a fresh UUID and the synthetic outside
fixture created by the probe script. These queries return statuses only. Quit
the fixture afterward. Local results: ax-target-control.log and
ax-target-sandbox.log under the feasibility log directory.

No automatic paste succeeded in this pass. Before promising it for the store,
validate a documented, review-compatible path in a suitable controlled UI session
using an isolated synthetic target. Do not add private entitlements, weaken
sandboxing, ship an external helper requirement or bypass focus checks. If no
supported path works, obtain the maintainer's product decision on Copy followed
by manual Command-V for the first store release. The prototype UI identifies
paste as under evaluation and does not offer Accessibility setup as a proven fix.

## Remaining migration and submission work

- Choose final App Store identity and signing/provisioning/archive workflow. The
  selected local toolchain is Command Line Tools; full Xcode archive setup and
  App Store Connect validation are not established by this SwiftPM probe.
- Design and test existing history/library migration or user-selected import
  into the sandbox container, including preferences. Never silently erase/reset
  existing data or run two app copies against the same store.
- Decide automatic-paste scope after the investigation above; reconcile history,
  library forms, shortcuts, onboarding and help with the chosen behavior.
- Verify actual general-pasteboard text/images, interactive hotkey, Copy/manual
  paste, launch-at-login consent and real login launch on suitable hardware.
- Complete VoiceOver, Reduce Transparency, network/privacy observation, Intel
  and minimum-macOS runtime coverage (or explicitly narrow support).
- Prepare app icon/screenshots, support/privacy URLs, App Store privacy answers,
  review notes, TestFlight and App Store submission acceptance. Never imply
  sandboxed data is encrypted merely because it is in a container.

Issues stay open until their actual acceptance and product decisions are complete.
