# Sandbox direct-paste routing experiment (FRO-22)

This separate, dependency-free Swift package builds three arm64/macOS 26+ test
apps. It does not compile or launch the production CopyStory application.
Each app has only `com.apple.security.app-sandbox`; no network, AX query,
automation, temporary exception, login registration or production data access.
Default signing is ad-hoc/hardened runtime. A stable existing signing identity
can be specified explicitly with `COPYSTORY_PROTOTYPE_SIGNER`; this is not App
Store signing. Never weaken the signature or sandbox to obtain a runtime pass.

## Build and policy tests

From the actual repository root:

```sh
scripts/build-direct-paste-prototype.sh
scripts/test.sh --package-path scripts/sandbox/DirectPaste \
  --scratch-path .build/direct-paste-policy-tests --filter PasteGateTests
```

The builder freezes a source copy and creates a fresh `.build/direct-paste-*`
directory each time, preserving previous evidence. It records the base commit,
source hashes, OS, signatures, entitlements and executable hashes in
`source-manifest.json` / `verification.json`. This uncommitted prototype must not
be described as an exact clean-commit release. The root lockfile, existing
feasibility artifacts, installed CopyStory and nested checkout are untouched.

The current probe is **CS Paste Probe**, `com.copystory.paste-probe.fro22`,
internal 0.0.11/build 11 (verified synthetic image pixels and stored-attachment inspection). Its window is **CS Paste Lab — SYNTHETIC ONLY**; the
menu-bar item is **CS Paste Lab**. The tested stable runtime is
`.build/fro22-runtime/CS Paste Probe.app`.
Use an existing Developer ID identity explicitly for consent continuity:

```sh
COPYSTORY_PROTOTYPE_SIGNER='Developer ID Application: Francisco Gramajo (MBA354NC7J)' \
  scripts/build-direct-paste-prototype.sh --stable-runtime
```

`--stable-runtime` creates the fixed runtime only if absent; it refuses to
replace an existing granted/tested bundle and leaves the new build staged.
Preserve old bundles and manifests before a reviewed update. The designated
requirement stayed stable across Developer ID builds 2 → 3 → 4 → 5 → 6 → 7 → 8 → 9 → 10 → 11; fresh
LaunchServices preflight remained true without another grant.
Ad-hoc signing is useful for build checks but changes its consent identity on
rebuild. Do not switch signing modes after granting a tested artifact.

## Fixture-only interactive session

Choose one UUID for the run and launch all three apps from the **same output**
using LaunchServices, with `--run UUID`. Direct CLI execution may inherit the
responsible process's permission and is excluded from event dispatch evidence.
The prototype additionally refuses dispatch unless its parent is launchd.

Both fixtures create two windows with two editable controls each. They override
Command–V to read only the named `com.copystory.paste-experiment.UUID` board,
logging received events and exact resulting synthetic text/image. The decoy
logs the same way, so any unintended decoy delivery is visible. Neither reads,
writes nor snapshots the daily general clipboard. Unsupported responders
consume/refuse the fixture paste rather than call a normal general-board handler.

Use the fixture's **Open lab (fixture bridge)** for a cooperative explicit
invocation that leaves the intended app active. The bridge is a public
distributed notification, test-only; it is not a shipping helper or evidence
that the real shortcut/menu invocation works. The prototype also supplies a
menu-bar entry and selectable test shortcut. Launch the probe with
`--shortcut alternate` (default, Command–Option–Shift–H), `--shortcut default`
(Command–Shift–H), or `--shortcut isolated` (Command–Control–Option–P). All
registrations are exclusive and a conflict displays a menu-bar fallback status.
The default registration failed with -9878 while installed CopyStory held it;
never press that chord after a failed claim. The alternate chord was ambiguous
to the human tester and is not counted as native acceptance; use the distinctly
labeled isolated lab for further controlled checks. CLI selection is experiment
configuration, not shipping shortcut-preference UI. Registration success is
not shortcut runtime acceptance.
Computer Use app-bound key events may not reach Carbon's global hotkey handler;
record physical-hotkey invocation separately.

Invocation logs distinguish `hotkey`, `menuLeft`, `menuRight` and
`fixtureBridge`, with generation and frontmost/captured PID. `invocationAction`
also records toggle attempts while visible. For actual menu-bar acceptance,
physically left-click CS Paste Lab or right-click → Open synthetic panel;
fixture bridge invocation is not equivalent. Capture the target before these
steps, then verify one insertion and zero decoy delivery for explicit Paste.

Build 6 adds `statusMouseEvent` observations restricted to the probe's own
status window, plus event timestamps/button/Control-click state in
`statusClicked`. Fixture `focusChanged` events report active/key-window/current
synthetic-field state. These are diagnostics, not a menu focus fix. They never
cache an earlier app as a replacement destination. Build 5 and its run evidence
are preserved before the stable runtime update.

Build 7 recognizes Control-left-click as a context-menu invocation alongside
right-click. Its Open action records the choice; the panel becomes key only
after `NSMenu.popUp` returns, so it does not compete with menu tracking for
focus. Dismissal without Open invalidates that capture. A pending paste ignores
menu actions, and a newer invocation supersedes the old menu completion. These
changes never restore a prior app or relax the fresh-frontmost dispatch checks.
`contextMenuOpenChosen` → `contextMenuClosed` → `panelOpened` is the expected
Open sequence. Native Control-click, right-click and left-click acceptance
must be recorded independently; build 6's left success did not reproduce or
explain the earlier ChatGPT foreground switch.

Build 7 run `B7589E26-11B5-46AC-AE9F-75D1E6319BFC` passes physical right-menu
and left-menu explicit insertion into the target (tokens 5 and 6), with two
exact insertions and zero decoy activity. Four earlier openings in that run
requested no paste and are recorded separately. Distinct Control-click and the
fallback leftMouseUp+Control branch were not established: the observed right
events report rightMouseUp with buttonNumber 0 and Control absent. Do not infer
hardware gesture from buttonNumber alone. The original focus-switch cause
remains unconfirmed; the report preserves that limitation and shipping no go.

Build 8 adds **Request twice (repeat test)** beside the settling-delay selector.
This explicit synthetic test control calls the same paste handler twice in
sequence without opening another generation. Expect two `explicitPasteAction`
records, one `repeatIgnored`, one board write/settling decision and at most one
pair/insertion. It exercises duplicate delivered actions in the running app;
it does not prove that two physical clicks reach the normal button after the
first click hides the panel. The ordinary paste handler and menu routing are
unchanged. `repeatTestStarted` / `repeatTestFinished` delimit the injected
duplicate action; never present it as two native user clicks.

Build 10 adds `imageAttachmentInspected` after insertion, retrieving the actual
attachment from text storage and exporting its image to PNG for independent
pixel verification. `imageAttachmentInspectionFailed` is not a pass. The first
inspection exposed an all-transparent test source, so build 11 constructs the
known RGBA bytes directly: two opaque red diagonal pixels and two fully transparent
pixels. Run CEC2F0B6 passes exact incoming/stored 2×2 samples with one insertion
and zero decoy activity. Earlier build 10 failure is preserved; previous image
dimension checks did not establish color fidelity. Partial alpha, color profiles,
large images and ordinary-app clipboard behavior are outside this narrow proof.

The bridge activates the fixture itself before notifying the prototype, because
an AX button action may not activate an app. This controlled test step must not
be presented as proof that shipping menu/hotkey interaction preserves focus.

Build 9 adds **Settle: 15 s (manual menu test)** for human-paced menu input.
The normal 100 ms default, existing 2-second option and 30-second capture expiry
remain unchanged, so request promptly after opening. This does not extend the
safety timeout. Run 35B2BD3A verifies two ignored pending-menu clicks and safe
cancellation after ChatGPT became frontmost. Later unchanged-build-9 run
3A3F23ED token 3 passes native-left capture and two ignored pending-menu clicks
with one exact top-field insertion and zero decoy delivery. Its successful
interval followed final plain-text instructions with no further assistant activity;
earlier/later openings and timing deviations are retained in the report.
The earlier build 8 run C266E783 verifies two delivered handler calls with one
exact insertion, not two physical clicks.

For controlled pending-dispatch checks, choose **Settle: 2 s** in the probe.
Use the decoy's **Activate only** to switch apps without opening/toggling the
probe, the target's **Activate only** to switch back, and **Replace test board**
to write an intervening known synthetic value. Logs must show the actual
frontmost change and cancellation; an AX Raise alone is insufficient. Restore
100 ms for ordinary fixture requests. These controls are test instrumentation.

Interactive questions can disturb this experiment: a single-display run with
no CUA calls still observed ChatGPT becoming foreground when the new question
appeared, before the physical menu click. Give the whole focus-sensitive test
sequence before the assistant turn ends; the human must then refocus the target
field after reading it. Do not issue another question or use computer control
until the sequence finishes. A host-induced focus loss proves cancellation,
not failure or success of an uninterrupted ordinary-user paste. See the report's
ABCA805B follow-up for timestamps and limits.

Opening, selecting, editing and Cancel must send no event. Use the explicit
Request paste button, history double-click or Return in search for one request.
Return in the library topic editor retains editing behavior. The payload is a
known Unicode/multiline text, generated 2×2 PNG, or rendered synthetic prompt.
Copy to test board plus the fixture's Manual test-board paste is the fallback.
Logs live only in each test app's container under
`Library/Application Support/PasteExperiment/UUID/events.jsonl`.

The process-specific candidate uses public `CGEvent.postToPid` for exactly one
Command–V down/up pair. It cancels on observed activation away (even away/back),
termination, timeout, explicit cancel or request selection change, and rechecks
permission/frontmost/clipboard/modifiers before dispatch. It does not restore or
verify another app's original field. An event-post log is not insertion proof.
No queued retry exists; failed/consumed requests require a new invocation.

## Permission boundary

Ordinary launch preflights PostEvent without prompting. Only after the user
approves that exact test-app permission, launch with `--request-post-event` to
call `CGRequestPostEventAccess`. Do not substitute AX trust for PostEvent.
The visible Request PostEvent button also requires prior human approval and
invalidates any paste request before activating the test app. If access is
still denied it opens `Privacy_Accessibility`, the shared Settings pane for
PostEvent and Accessibility. On this macOS 27.0.1 host the pane is called
Device Control and Data Access. The old `Privacy_PostEvent` link selected no
usable pane and was corrected. [Apple DTS](https://developer.apple.com/forums/thread/820594)
explains the shared label and sandbox-compatible event-posting APIs; this does
not establish App Review approval or sandbox-compatible cross-app AX queries.

Check `CGPreflightPostEventAccess()` in a fresh launch of the exact signed
bundle, then inspect real target/decoy event and insertion logs. A scoped TCC
record is diagnostic evidence, not a substitute for effective preflight or
actual insertion. On this host an approved PostEvent-only reset left the probe's
separate Accessibility grant intact and effective preflight stayed true after
relaunch. Do not call that a denied/revoked test. Removing that separate grant
also requires explicit approval. Reset only the exact authorized app/service.
After separate approval, resetting the probe's Accessibility record established
false preflight; a denied request posted no events and manual fallback worked.
Approved regrant of the exact stable app via Settings Add restored effective
access after relaunch. The resulting row is Accessibility, with no PostEvent
row; record actual preflight/delivery rather than infer behavior from row names.
Resetting any TCC record, even this test identity, needs user approval. Do not
edit the TCC database, inherit another process's grant, add private entitlements
or disable system protections.

## Recorded full-screen shortcut and menu checks

Unchanged build 11 run `46A73B60-3F3D-4B9A-A050-2659696A7D89` passes one
physical Command–Control–Option–P invocation over a full-screen target. The human
confirmed panel placement and target PID 21729. Generation 2 produced one exact
Unicode/newline/tab/trailing-space insertion in window1.field1; zero decoy events.
Generation 1 observed focus away/back and safely canceled, and is retained.
Full-screen status is setup visual evidence plus human confirmation, not a log
flag.

Separate unchanged-build-11 run `E2F2F5EE-F921-4796-BA1A-59F3791A8FAC`
passes physical left-click on CS Paste Lab over the full-screen target. Human
confirmation plus native menuLeft logs establish generation 1 target capture,
one explicit request, one exact top-field insertion and zero decoy events.
A later generation 2 opened then canceled without another request. The run's
PID was 23822; it is now stopped.

Separate unchanged-build-11 run `A3F250E4-9AE8-4477-A57E-42CB806F2CE0`
passes physical right-click → Open over full-screen target PID 24539. Native
menuRight capture → Open chosen → menu closed → panel opened ordering verified;
one explicit request, one exact top-field insertion, zero decoy events. Human
confirmed full-screen placement and insertion. All three test apps stopped.
The three full-screen paths pass in separate runs, not one uninterrupted session.
Run `1AC54561-0FC4-4B66-A023-93A78A104301` additionally passes fresh isolated
shortcut paste after human-confirmed departure from and return to the full-screen
Space: one exact insertion into target 28309, zero decoy events. The user reported
the transition in chat before refocusing and invoking; Space identity is not logged.
This is a bounded fresh-invocation recovery check, not uninterrupted immediate
recovery or open-panel/pending-paste Spaces cancellation. Those cases and distinct
Control-click remain untested. Test apps are stopped.

Give the complete procedure in ordinary final text, then end the turn. The human
must refocus the target after reading and complete the test before replying.
Do not send interactive question widgets, poll, or operate UI during that interval.
Confirm the current run's PID and settling value; cancel on a mismatch. Never
reuse this run's PID for a new launch.

## Pending paste and Spaces

Run `C01E842C-E082-4105-ACD3-30A705DD7066` passes a bounded second attempt:
native hotkey request with 15-second settling, human-confirmed Space departure,
activation away after 1.790 s, cancellation after 15.725 s and zero additional
paste events/insertion. An earlier request inserted once; the human clarified
that instructions were misread and repeated correctly. Preserve both attempts.
This proves the observed activation-away case, not same-app Space changes,
return-before-dispatch or open-panel-before-request transitions. All test apps
are stopped. The 15-second delay is a test setting; a fresh launch defaults to
100 ms. No permission or normal routing change was made.

## Physical Control-click result

Build 11 run `CF6718CD-6234-449B-9F27-A0D9278D220C` passes human-confirmed
Control-left-click in a normal target window. Actual status event is rightMouseUp
with Control absent; menuRight routing opens after menu closure and delivers
one exact top-field insertion, zero decoy events. The physical gesture is
human-confirmed; this does not exercise the leftMouseUp+Control fallback branch.
Full-screen Control-click remains untested. All test apps are stopped.

## Open-panel Spaces result

Run `361157F5-32AA-4A3F-8632-F34C6D379788` passes human-confirmed Spaces
away/back with the original panel open before requesting paste. Activation away
at2.963s and return at6.316s after capture; request canceled at8.259s, below30s
expiry, despite target again frontmost. Zero posted/received events or insertions.
A later opening sent no request. The earlier interrupted26C1DF1E run is preserved.
This establishes the observed application-activation case, not same-app Spaces
changes. Test apps stopped; build11 unchanged.

## Limits / remaining proof

Named-board insertion in a cooperative fixture is evidence only for that
fixture's routing/handler. Standard general-board paste, ordinary/protected
apps, full shipping History/Library/forms, VoiceOver, keyboard layouts,
remaining full-screen paths/Spaces transitions, macOS 26 and final routing-boundary races require separately
recorded controlled acceptance. The current machine's daily general clipboard
and account switching remain excluded. Session-wide event posting is not
implemented here: its final cross-app race conflicts with the approved safety
gate unless independently resolved. No go decision for shipping follows from
a compile, policy test, permission grant or fixture-only insertion.

See the [October 14 result matrix](../../../docs/DIRECT_PASTE_PROTOTYPE_2026-10-14.md).

Snapshot only a synthetic run's logs with:

```sh
python3 scripts/summarize-direct-paste-run.py .build/fro22-runtime UUID
```

Preserve `runs/UUID/summary.json` and the three JSONL logs along with the tested
build's verification/source manifests. Repeated launches append to that run;
match events by process PID and token rather than assuming tokens are globally
unique across launches. The summarizer does not infer insertion from posting.

## Expanded offline checks (October 14)

`Tools/check-image-roundtrip.py` requires Python with Pillow and a new output
folder. It invokes `Tools/image-roundtrip.swift` to insert/retrieve actual AppKit
text attachments without windows, clipboard or events. Four vectors cover partial
alpha, varied colors, odd widths, 1024×768 pixels and tagged sRGB. All RGBA samples
roundtrip exactly; ICC profile preservation fails in the export path, so the
checker intentionally returns nonzero. This is offline evidence, not live sandbox
paste acceptance. See [routing/image review](../../../docs/FRO22_ROUTING_IMAGE_REVIEW_2026-10-14.md).
The expanded policy suite has17 passing tests; signed build11 and its original
manifest remain preserved with the earlier13-test source snapshot.

### Profile diagnosis and boundary follow-up

The missing embedded ICC is explained for the known sRGB sample: AppKit PNG
encoding substitutes explicit sRGB metadata; attachment and TIFF retain the
original profile. Independent normalized colors match exactly. Strict ICC-byte
preservation still fails, but no color-loss fix is warranted for this sample.
`Tools/diagnose-image-profile.swift` and `Tools/check-profile-equivalence.py`
reproduce the diagnosis. See [follow-up report](../../../docs/FRO22_BOUNDARY_PROFILE_DIAGNOSIS_2026-10-14.md).
The source now shares its final validation/down/up ordering through
EventDeliveryBoundary. Four controlled recording-closure tests expose before/
after-validation races without posting events; all21 tests pass. These are
characterization tests, not OS atomicity acceptance. Stable signed build11 remains
unchanged; new prototype source has not received signed runtime validation.
