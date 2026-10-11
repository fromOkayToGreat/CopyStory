# Release acceptance — October 11, 2026

**Status: local production candidate verified; publication blocked.** No public
production release, release tag, installed-app replacement, account switching,
permission changes, or destructive fault testing was performed in this pass.
All three tracking issues remain open. This record supersedes earlier claims
that Apple credentials are missing or the normal QA update is still unattempted.

## Issue order and scope

1. [#4: failure acceptance](https://github.com/fromOkayToGreat/CopyStory/issues/4)
   was reviewed first. Its current body explicitly defers the work to the next
   version. Existing evidence was reconciled and safe automated checks rerun.
   Live failure cases remain deferred, not passed. Second-account testing is
   paused because fast user switching freezes the current Mac. Low disk,
   interrupted replacement and failed relaunch require a disposable VM with
   snapshots. Do not use the everyday Mac or real history as fixtures.
2. [#6: platform acceptance](https://github.com/fromOkayToGreat/CopyStory/issues/6)
   was assessed next because its results constrain #5. Available automated and
   user-reported evidence is recorded below. Suitable isolated hardware/manual
   sessions are still needed; no support limitation has been accepted on the
   maintainer's behalf.
3. [#5: production candidate](https://github.com/fromOkayToGreat/CopyStory/issues/5)
   was staged from the current merged production commit. Staging is complete for
   that commit; release acceptance and publication remain incomplete.

## Source and automated evidence

Candidate: **0.3.0, build 4**, source
`b1b00faf1a493a2106f6b94610c67a8395ef88b6` (merged PR #3).
The checkout was clean at staging. The production bundle is `com.copystory.app`,
with the production latest-release feed and existing production Sparkle key.
No QA identity, feed, or key was substituted.

| Check | Actual evidence |
|---|---|
| Local environment | Apple silicon arm64; macOS 27.0.1 (26A434) |
| Isolated Swift tests | 86 passed: 49 platform/model, 37 core |
| Release/signature tests | 13 passed |
| Rehearsal-isolation tests | 3 passed |
| Exact-commit CI | [Run 38166225197](https://github.com/fromOkayToGreat/CopyStory/actions/runs/38166225197), success on the candidate commit |
| CI runtime environment | Apple silicon; macOS 26.6.2 (25G83), Swift 6.3.3; 86 tests and development package runtime smoke passed |
| Production package | arm64 + x86_64; minimum deployment target 26.0; public package verifier passed |
| Developer ID | Valid Application identity; team MBA354NC7J; strict nested signatures and hardened runtime verified |
| Production notarization | Accepted; submission `7c375e6a-cecb-4aaa-914b-80d0e512c8dd` |
| Staple and local Gatekeeper | Passed, including bundle extracted from final ZIP |
| Production archive/feed | Sparkle signatures, independent public-key checks, manifest and SHA-256 verification passed |
| Production runtime smoke | Passed: packaged runtime and signed update configuration verified; no app delegate/history opened |
| Production hosting | NOT RUN; no production release published |
| Key backup | Owner answered “Not yet / not confirmed”; no private key retrieved or exported |

Local artifacts: `.build/releases/v0.3.0/`. Logs and refreshed QA hosting evidence:
`.build/acceptance-2026-10-11/`. Notarization result: `.build/notary-result.json`.
These ignored files are local evidence, not attachments distributed in this PR.

| Artifact | SHA-256 |
|---|---|
| `CopyStory-0.3.0.zip` | `04d7cc2fba642268f5e76a809fce99fa7f6e6b5652d1be33a8be05df8eaef374` |
| `appcast.xml` | `d234d018a3a2c91e1839f31309bda816d59bf94812ba715deea29eae049b6f50` |

The candidate is pinned to the commit above. If main changes before publication,
including merging these documentation changes, preserve this stage and rebuild
from the final merged commit in a separate clean checkout. Run exact-commit
checks again and record new hashes; do not silently relabel this candidate.

## Normal QA update and failure coverage (#4)

QA A: source `6460d796b16f48e459718bbb5d2871c984ddc952`, version 0.0.1/build 1.
QA B: source `33344366d3263db7b7b38ef7b8fe43218244f3be`, version 0.0.2/build 2.
Both original notarization results are Accepted. Fresh stage verification passed
for both, including stapling, Gatekeeper, archive/feed signatures and checksums.
Anonymous HTTPS retrieval of both QA ZIPs and the fixed rehearsal feed again
matched the saved staged hashes on October 11. This is QA hosting evidence only.

The maintainer reported a real Sparkle A→B update, preserved history/pins and
direct paste. The maintainer also confirmed prompt persistence, variables and
dropdowns, library direct paste and independence from clearing history. These
reports supersede the earlier handoff files' “NOT RUN” normal-update status.
They do not establish every image, exclusion, retention, login or consent case.
The old QA home path was absent during this pass; no account was recreated and
no ownership or installed-app repair was attempted. The existing production
0.2.0 app retained its identity and passed strict signature verification.

| Failure case | Current status |
|---|---|
| Modified/unsigned feed | Automated signature boundary coverage passed; live updater rejection NOT RUN |
| Modified/wrong-key/truncated archive | Automated boundary coverage passed; live updater rejection NOT RUN |
| Equal/older version | Policy coverage passed; live replay/reinstallation check NOT RUN |
| Unavailable feed/interrupted download | Live error, retry and preserved-state checks NOT RUN |
| Pending writes during update | Automated shutdown ordering coverage passed; live update case NOT RUN |
| Low disk/interrupted replacement/failed relaunch | NOT RUN; disposable snapshot-capable VM required |

The issue's next-version deferral is recorded, but no broader release waiver is
inferred. Before publication, the maintainer must explicitly accept any deferred
release limitation. Recovery remains verified-app reinstallation while keeping
history and library data. There is no proven automatic post-launch rollback.

## Platform, permissions, privacy and accessibility (#6)

The declared minimum is still macOS 26 and the package is universal. The project
has not established full runtime support on every declared system. Documentation
now makes these limits explicit; it does not turn untested behavior into a pass.

| Area | Evidence and outstanding work |
|---|---|
| Apple silicon | Local automated checks on 27.0.1 and CI checks on 26.6.2; full final-candidate UI acceptance outstanding |
| Intel | Cross-compilation/package verification only; runtime NOT RUN |
| Minimum macOS 26.0 | CI used 26.6.2, not 26.0; native minimum-version session outstanding |
| Hotkey/capture/manual copy/paste | Automated model/named-pasteboard coverage and prior QA user reports; final production interactive matrix outstanding |
| Launch at login | Registration, actual login launch and revoke behavior not freshly verified; do not log out/switch accounts on this Mac |
| Accessibility permission | Prior QA direct-paste report; final candidate denied/granted/revoked permission matrix outstanding |
| Update consent | Plist defaults off; production configuration verified; live default/toggle/persistence acceptance outstanding |
| Network privacy | Source sets system profiling off and contains no clipboard upload path; live traffic observation NOT RUN, so no observed-payload claim |
| VoiceOver | Prior label inspection only; complete spoken-navigation session NOT RUN |
| Reduce Transparency | Full visual acceptance NOT RUN |

Use synthetic data on suitable alternative hardware/VMs for the remaining
sessions. Record exact hardware, OS, build, action and actual result. Follow
[MANUAL_TESTING.md](MANUAL_TESTING.md); label model tests, source inspection,
user reports and direct observations separately.

## Publication blockers and handoff (#5)

- Confirm an owner-managed encrypted/offline backup of the production update
  key. The owner performs backup directly; do not put secret material in a chat,
  source tree or evidence file.
- Complete the open acceptance matrix or obtain explicit, specific maintainer
  acceptance of release limitations, including #4's deferred cases.
- After any further merges, stage and verify the final main commit, preserving
  this evidence. Exact-commit CI and tests must pass.
- Review [draft release notes](RELEASE_NOTES_0.3.0.md), install/recovery guidance,
  and support limitations; obtain explicit approval for public publication.
- Only after that approval, use the publication workflow to verify draft-hosted
  bytes before promotion, then verify the public feed. Production hosted bytes
  and fresh browser-download Gatekeeper acceptance remain unverified today.

Do not close #4, #5 or #6 based solely on this evidence update.
