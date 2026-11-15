# Direct Paste TestFlight beta

Francisco requested TestFlight testing with Direct Paste after owner-observed
History and literal Library insertions passed in the isolated local test app.
This beta intentionally retains the user-triggered paste workflow while Apple
clarification is pending. No App Store submission or public release is authorized.

`CopyStoryTestFlight` archives the `TestFlight` configuration with
`APP_STORE COPYSTORY_PRODUCTION COPYSTORY_TESTFLIGHT_DIRECT_PASTE`. The extra flag
requires that exact product family and rejects development/reconstruction flags.
The beta uses `com.copystory.app`, marketing1.0.0, arm64/minimum macOS26.0, sandbox,
no updater, approved icon and privacy manifest. Runtime validation requires both
production and TestFlight markers and rejects ordinary Production metadata.
Direct Paste remains explicit opt-in and reuses the existing fixed-PID,
permission, secure-input, focus, expiry and cancellation safeguards. No permission
reset or automatic grant is introduced. Native diagnostics remain excluded.

The separate `Production` configuration remains copy-only and its full automation
API exclusion audit is unchanged. The beta has its own import audit: required
posting/preflight APIs must be present; AX field manipulation, input taps, global
posting and unexpected helpers are refused. Changing the configuration must never
silently turn the beta into a copy-only app.

## Preparation and acceptance

- `scripts/build-testflight-unsigned.sh /fresh/output` compiles and statically
  inspects a build0 preparation only. It never launches or installs the app.
- `scripts/test-testflight-automation.py` exercises the import policy offline.
- `ProductionConfigurationTests` covers cross-channel metadata rejection.
- `scripts/TestFlightConfigurationCheck.swift` is a pure CLI check compiled with
  the actual beta flags plus AppDistribution/UpdateService and CopyStoryCore. It
  constructs no application, stores, clipboard readers or permission requests.
- `scripts/verify-testflight.py APP --revision SHA --build N --team TEAM
  --identity PUBLIC_CERT_SHA1` checks the signed artifact, signature/profile,
  exact metadata, entitlements, resources, architecture and beta import policy.
  `--unsigned` accepts only linker-signed preparation and implies no runtime pass.

Use a clean committed source tree and an unused build number verified in App Store
Connect including pending/failed uploads. Archive/export with the approved Apple
Distribution and Mac Installer Distribution identities, matching profile and team.
Keep exact commands, source archive, logs, hashes and export/package checks locally.
The internal beta export should set `testFlightInternalTestingOnly=true`,
`manageAppVersionAndBuildNumber=false` and manual signing. No external tester
invitation, App Review submission or public release is part of this workflow.

A TestFlight beta uses the same identity/container as the installed production
app. Separate-test-app native results do not establish production-container,
Apple-signing or permission continuity. Never install or launch the archive as
part of build/export/upload; coordinate any later TestFlight install/launch,
data preservation and exact candidate acceptance separately. Do not use personal
history as a fixture. The isolated sample app remains closed and its saved
Direct Paste opt-in may still be ON, per Francisco's clarification.

The existing App Store2.4.5 rejection is not resolved by uploading this beta.
TestFlight processing or internal availability must not be described as App Store
approval. Preserve the Apple clarification thread and the copy-only production
path while evaluating the intended feature honestly.
