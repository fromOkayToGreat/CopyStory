# App Store release guidance

This is the current direction for approved v1. Older direct-download, Developer
ID/notarization and Sparkle rehearsal scripts describe historical work and must
not be used to publish this development candidate. A local build is not an Apple
archive/export or runtime acceptance result.

## Scope and identities

Approved production scope: CopyStory, `com.copystory.app`, marketing version1.0.0,
arm64 only, minimum macOS26.0, intended macOS26/27 support after acceptance, free,
no Sparkle, login off by default with explicit opt-in. Direct Paste targets the
intended app's current focus, without an original-field promise. Optional explicit
empty-store import and its all-or-nothing recovery contract remain v1 requirements.
See [approved scope](APP_STORE_RELEASE_SCOPE_2026-10-13.md).

The development configuration uses `com.copystory.development` and its separate
store/preferences. Signed development build4 acceptance is recorded in
[the milestone](DEVELOPMENT_MILESTONE_BUILD4.md); it is not production runtime
acceptance. The [personal development signing workflow](DEVELOPMENT_SIGNING.md)
is separate from App Store distribution. The inert shipping reconstruction and
unsigned production preparation both use build0, an unallocated placeholder.
Verify the next unused store build (at least5) and production account identity
before distribution. Development acceptance does not allocate a store number.

## Unsigned production preparation

`Production` explicitly selects `APP_STORE COPYSTORY_PRODUCTION` on the existing
target; `CopyStoryProduction` selects it for archive. Debug/Release and the
`CopyStoryShipping` scheme remain the guarded reconstruction. Development config
overrides continue to select development behavior. Regenerate the project with
`python3 scripts/generate-shipping-reconstruction.py`; generated files are committed.

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  scripts/build-production-unsigned.sh /tmp/copystory-production-preparation
```

Use a fresh output directory. This build-only script disables Xcode code signing
and never launches or installs the app. Apple’s arm64 linker emits a linker-only
ad-hoc signature: no signing identity, entitlements, sealed bundle resources or
runtime sandbox verification is supplied. The static receipt explicitly records
this limit. Build0 is not for upload. The configuration has sandbox and hardened
runtime build inputs, arm64/minimum26.0, no updater and normal startup through
the existing AppDelegate/AppModel and History/Library request coordinator.
Package identity/configuration/provenance validation precedes NSApplication and
store creation. Incompatible development/reconstruction/focus flags fail compilation.

Production uses the bundle's standard preferences and the sandbox Application
Support `CopyStory` folder. Development uses its separate bundle/container and
`CopyStory Development` folder. No shared suite, import or automatic migration is
introduced. Production excludes readiness reports/AX trust queries and uses an
inert presentation diagnostic sink, including no geometry sampling. Startup
failure reporting retains sanitized categories. Direct Paste stays default OFF,
requests consent only from the explicit button, and reports requests without
claiming insertion. Manual Copy and existing capture/onboarding/login rules remain.

`verify-production.py` is separate from the reconstruction verifier; it checks
production package metadata, architecture/minimum OS, no updater/AX diagnostics,
linker-only signature and the existing sole fixed-PID posting source. Offline tests
remain compiled with inert reconstruction gates, use injected effects/temporary
stores, and do not establish production runtime permission or insertion behavior.

## Reproducible development preparation

Use the commands in [README](../README.md). The build script requires a fresh
absolute output directory and records exact source revision, clean/dirty state,
configuration, version/build, build log, signature check and executable digest.
Retain the whole output locally; do not commit binaries, logs containing private
paths, clipboard contents, signing material or local runtime evidence.

Run static candidate verification without executing it:

```sh
python3 scripts/verify-development.py '/path/to/CopyStory Development.app'
```

These checks prove structure, arm64, no updater linkage, provenance and sandbox
signature. They do not prove effective runtime permissions, successful recording,
intended insertion, safe revocation behavior or final Apple signing/export.

## Remaining release gates

1. FRO22: bounded Direct Paste safety verdict for permission loss, protected and
   unsupported destinations, cancellation, routing limits and truthful fallback.
   No atomic posting or confirmed insertion claim; no automatic retries.
2. FRO23/25: ordinary startup and History/Library consent/action integration on
   the actual candidate, then real Xcode archive/export and correct App Store
   identity, signing, resources/privacy declarations and entitlements review.
3. FRO24: implement and accept optional selected import and recovery without
   deleting source data or merging/replacing a nonempty destination. Fresh
   development data does not waive this requirement.
4. FRO26: exact final artifact on approved macOS versions/hardware, keyboard,
   VoiceOver, capture/storage, denied/granted/revoked permissions, login and
   privacy acceptance. Unit/static/build evidence stays distinct from native QA.
5. FRO28/27: final listing/account details, processed TestFlight acceptance, then
   separately approved submission and publication. Confirm hosted/store identity
   and exact artifact; do not mark issues Done on compile.

Before a hands-on session provide intended outcome, honest time estimate, complete
simple steps, diagram and stop condition together; wait for explicit launch.
Unexpected identity/data sharing, unsafe or duplicate posting, permission changes
outside scope or a time bound stops the session. Preserve evidence and stop owned
processes only. No blind retry or account switching on the everyday Mac.

Merging, release publishing, Apple submission, installation, launch and security
changes require their respective explicit authorization. This runbook performs
none of them and does not claim a release date.
