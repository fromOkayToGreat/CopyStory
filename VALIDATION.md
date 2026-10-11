# Validation status — 0.3.0 development

Historical automated baseline prepared October 10, 2026. Updated October 11, 2026. Public source is available; the app binary is not yet
a notarized public release. This document distinguishes automated evidence
from remaining distribution acceptance.

## Environment

Local preparation uses Apple silicon, Apple Swift 6.4, Command Line Tools, and
a macOS 27 SDK. The minimum supported OS is macOS 26; testing on that OS and
on physical Intel hardware remains required. The build targets arm64 + x86_64.

## Completed evidence

- Original 0.2.0 source and prior clear-history race/hardening changes preserved.
  Production history, preferences, installed app, permissions, and login setting
  were not used as destructive test fixtures.
- Sparkle 2.10.0 pinned in Package.swift/Package.resolved. Its full upstream
  license and component notices are included.
- Pre-publication source review and common secret/private-artifact/path scanner
  passed. No production database, clipboard payload, signing private key,
  notarization credential, personal path, or unrelated audit log is published.
  This is a scoped review, not a comprehensive security certification.
- A dedicated Ed25519 update key was generated into macOS Keychain. Only its
  public key is in source. An official Sparkle-signed synthetic feed passed
  independent public-key verification; a same-length content change failed
  signature verification. No private key was exported.

- `./scripts/test.sh`: **64 test definitions passed** (38 platform/model/update/
  shutdown definitions and 26 core definitions). Parameterized cases additionally
  cover hostile URLs/builds and shutdown save/clear/pin/delete/limit actions.
- An intermittent pre-existing retention test was traced to substring fixture
  lookup matching both “old pinned” and “old unpinned”; equal timestamps made
  the chosen row depend on random UUID order. Exact fixture matching fixed it;
  30 isolated repetitions and the full suite then passed. Production retention
  behavior was unchanged.

- `python3 scripts/test-release.py`: **13 release-boundary tests passed**,
  covering signed feed/archive acceptance, tampering, wrong keys, unsigned or
  duplicate signatures, invalid lengths, unsafe configuration, ZIP traversal,
  symlink ancestors, duplicate entries, and case/Unicode path aliases.
- Independent integration review found and verified fixes for shutdown mutation
  coverage, ZIP extraction checks, numeric build bounds, and exact checksums.
  It found no further concrete blocker in the reviewed implementation.

- Package negative checks reject public distribution of development/ad-hoc
  bundles, an unmarked library-validation exception, and an unconfigured strict
  ad-hoc build. The latter cannot load Sparkle on this Mac; explicit development
  mode uses a host-only exception and disables updates. Public builds keep full
  library validation and require Developer ID.

- Final `COPYSTORY_DEVELOPMENT=1 ./scripts/build.sh`: universal arm64/x86_64
  bundle passed architecture/minimum-OS, plist, framework, path, license,
  nested hardened-runtime, entitlement, and strict code-signature checks.
- Packaged `--verify-package-runtime`: passed on Apple silicon, explicitly
  reporting development mode with updates disabled. It does not create an
  application delegate, open history/preferences, or make an update request.
- No Rosetta installation was available; Intel runtime validation remains open.

GitHub [CI runs](https://github.com/fromOkayToGreat/CopyStory/actions/workflows/ci.yml)
record the exact commit, hosted toolchain, test results, universal packaging,
and safe runtime smoke outcome. CI never opens the normal history or publishes
ad-hoc artifacts. Its status must pass on the release commit.

## Pending public-binary gates

Developer ID signing and notarization are now available. The normal QA A→B
update was reported successful by the maintainer. Production 0.3.0/build 4 was
signed, notarized, stapled and locally verified on October 11 from merged commit
`b1b00faf1a493a2106f6b94610c67a8395ef88b6`. No production release was published.

The [dated acceptance record](docs/RELEASE_ACCEPTANCE_2026-10-11.md) supersedes
older credential and rehearsal status. It records 86 passing Swift tests,
exact-commit CI, production hashes, user-reported results, and open gates.
Key backup is unconfirmed; live fault recovery and full platform/accessibility/
privacy acceptance remain incomplete. Local Gatekeeper assessment does not prove
fresh browser-download acceptance or production hosted-byte verification.

The [release runbook](docs/RELEASING.md) defines the credential setup and required
checks: tampering/downgrade rejection through the real updater, interruption
and low-space recovery, data preservation, both hardware families, macOS 26,
opt-in behavior, and network privacy observation. The full
[manual checklist](docs/MANUAL_TESTING.md) also covers runtime permissions,
login/lock/session behavior, visual accessibility, and performance.

## Existing behavior and limits

The previous local 0.2.0 build had 51 passing test definitions; actual direct
paste into TextEdit was confirmed by its user. That does not substitute for
revalidating the new packaged release and its updater. Old local validation
logs are retained outside this public repository.

Local history remains plaintext and there is no app lock. App exclusions,
confidential markers, and expiration reduce retention but do not isolate data
from another process running as the user. Unmarked secrets can enter history.
See [PRIVACY](docs/PRIVACY.md) and [remaining encryption design](docs/HARDENING.md).
