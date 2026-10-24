# Development milestone: accepted signed build4

This is a personal development-use checkpoint, not production release approval.
The installed version 1.0.0/build4 remains bound to clean source
`0c5a65b21d8b990361103726f71e3124c66381d1`. This publication adds only
documentation above that source; it does not describe a newly built app.

## Included implementation

- Session resignation cancels pending History and Library Direct Paste through
  the existing sticky cancellation path, with no retry.
- Explicit Apple Development signing configuration and static update verifier:
  exact identity/team/source/build, sandbox-only entitlements, hardened runtime,
  increasing build number, two-way designated requirements and ZIP inventory.
- Bounded, in-memory Preferences readiness diagnostic: initial and next normal
  refresh samples, five-second deadline, dismissal/close cleanup, no extra polling,
  permission requests, event posting, clipboard/history reads or persisted report.

The six original commits are preserved: `4af59268`, `c4d22b16`, `5e256837`,
`fcec33a3`, `f19a0f12`, `0c5a65b2`. Product code is unchanged by publication.
The preparation-time status in DEVELOPMENT_SIGNING.md and the source-review
receipt in READINESS_CHECK_REVIEW.md are historical; later evidence follows.

## Evidence and attribution

| Evidence | Result and limit |
| --- | --- |
| Recorded independent static build/install verification | Build4 clean source above, strict signature and frozen inventory passed; exact approved Apple Development identity/team matched; build3 and build4 satisfied each other's static requirements; ZIP/source checks passed. Static continuity does not prove OS permission retention. |
| Recorded offline model/injected tests | 182 selected Swift tests passed: 122 platform tests in 9 suites and 60 core tests in 5 suites, including 3 readiness tests (179 prior plus 3). No native clipboard/GUI/shortcut suites selected. |
| Recorded compile and independent source review | Unsigned development compile passed; independent review verified corrections and reported no remaining blocking findings. See READINESS_CHECK_REVIEW.md for exact implementation and content-set digest. |
| Native signals displayed by the app | Owner-provided screenshot was inspected by the coordinating agent after explicitly authorized exact-row reauthorization. Build4 identity/canonical-match/gates were verified; AX trust, posting preflight and displayed readiness were true, opt-in false, initial to next refresh completed. No new native read was performed for this publication. |
| Owner-reported actual insertion | One scoped History Direct Paste and one literal Library Direct Paste into blank TextEdit passed. Insertion was reported by the owner, not directly observed by an agent. Direct Paste OFF restoration and app left running were owner-reported. |
| Historical owner acceptance | Core startup/capture/History Copy/Library Copy/restart passed on build3; this is not a full build4 core-suite rerun. |

The canonical testing checkpoint and release handoff remain private local
records. Raw screenshots, device logs, clipboard/history content, backup
manifests/sidecars, signing material and internal operational notes are excluded
from publication. No private records are copied into this repository.

## Remaining gates

- Original authorization failure cause is unknown. No stale-permission or sandbox
  diagnosis is established. Real permission retention on a future signed update
  remains unverified; build4 is the positive baseline.
- FRO22 is not Done. Bounded risk disposition and final protected/unsupported
  destination acceptance remain pending; native revocation evidence is limited.
  TextEdit literal success does not establish other targets, secure/protected
  fields, permission loss, focus races, expiry or duplicate prevention broadly.
- Production startup/consent integration for FRO23/FRO25 remains unimplemented.
  Login, broader platform/accessibility and distribution gates remain open.
- No production archive, TestFlight or submission ran. No public release,
  notarization or App Store acceptance is implied.

This publication performs no local app control, build/signing, installation or
permission changes. Existing data and rollback generations remain local and
preserved. No storage schema or recovery behavior changes here; app rollback does
not automatically restore data or OS grants. Main requires separate review and
merge approval.
