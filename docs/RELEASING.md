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

The development configuration instead uses `com.copystory.development`, a separate
store/preferences, local ad-hoc sandbox signature and development build1. It is
not install/release accepted and must not replace the existing installed app.
The prepared [signed personal development workflow](DEVELOPMENT_SIGNING.md) is
separate from both this ad-hoc path and App Store distribution. Its configuration
is selected explicitly, and signing has not been activated by preparing it.
The shipping reconstruction target remains an inert build0 reference. Neither
number allocates an App Store build. Before future distribution, verify App Store
Connect identity and the next unused build; the surviving installed build7 does
not establish complete source provenance or an available store number.

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
