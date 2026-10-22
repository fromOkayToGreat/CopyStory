# Development integration provenance and limits

This branch imports the reviewed reconstructed source at pinned local commit
`e3699c1570272f5a45ec464ea6594626058bc131`, then applies the reviewed cumulative
interface/Xcode product patch and companion validation patch. The preserved base
is new reconstruction, not exact installed build7 source. Remote main at the
start was `2af4ff0535af84be570f81f14482971fb27d77b8` (0.3/build4). Root migration
checkout changes and installed1.0/build7 remain separate and untouched.

For publication, the reconstruction snapshot is committed directly above remote
main. Local input manifests, focus-fixture/evidence launch scripts and machine
paths are omitted; pinned local source/evidence remain preserved outside Git.
This retains remote ancestry without pushing private preparation history or an
artifact directory. Product source is retained, followed by a separate reviewed
interface commit and a separate development integration commit.

The ordinary development entry calls the existing AppDelegate and AppModel. Its
compile-time capability groups cover startup, storage, clipboard, observation,
shortcut, login, consent and posting separately. Nondevelopment reconstruction
and offline tests retain closed native gates. The shared NativeRequestAdapter,
request owner/ticket lifecycle and PanelActivationGate are reused. The disabled
legacy PasteCoordinator.paste entry is deliberately not a second delivery path.

Development has a separate bundle/defaults identity and Application Support
folder. It does not open or clean the installed app's data. Capture requires
completed onboarding; login registration is never a startup action. Shortcut
registration and experimental Direct Paste start off, with explicit controls.
Manual Copy works without a recipient, invocation, posting permission or focus
activation. Development app startup itself remains unrun in this milestone.

`IsSecureEventInputEnabled` adds a conservative cancellation signal, not foreign
field verification. The final sink rechecks identity, clipboard, modifiers,
permission and secure input before a fixed-PID pair. No public API makes these
checks/posting atomic; revocation or focus can race and event posting gives no
insertion acknowledgement. A balanced release event is sent once after key-down;
there is no automatic retry. Unsupported controls can ignore a request.

Current automated coverage is selected offline core/store and History/Library/
request/gate suites. It does not execute the historical live platform suites.
The old compatibility test expecting implicit fallback Copy was corrected to the
retired entry's no-effect contract; current explicit Copy has injected History
and Library cases with no invocation/recipient/permission. Older named-pasteboard
LibraryIntegrationTests describe the former monitor/coordinator path and remain
compiled but not accepted or run. They need migration to explicit native fixtures
before calling the entire historical suite current. This milestone does not claim
a full-suite pass. PR CI runs the explicit offline suite and a build only.

Existing reconstruction verifiers remain for the inert configuration; the new
`verify-development.py` checks the ordinary development candidate separately.
No app is executed by the verifier or build script. GUI rendering, capture consent,
real persistence across an app relaunch, Copy, intended insertion, revocation,
secure-input native behavior, login, shortcut collision, archive/export, import
and final platform/accessibility acceptance remain to be observed.

Optional import remains approved required v1 scope and unimplemented, tracked
separately. FRO22/23/26 are not Done based on these changes. Local evidence and the
single next-session checkpoint hold exact build/test results and future-session
brief; they are excluded from the publishable source tree.
