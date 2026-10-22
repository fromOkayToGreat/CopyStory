# Manual acceptance for the development candidate

This plan is preparation only. Do not install or launch until the exact candidate,
identity/hash, session scope and stop condition have been reviewed and Francisco
explicitly confirms launch. Build and model evidence are not native acceptance.
Use synthetic text/images and a designated destination. Never use private clipboard
history as a fixture or change permissions without separate scope authorization.

## First bounded session — proposed, not started

**Outcome:** establish ordinary startup, separate store, consent boundary, basic
History/Library Copy and persistence. Then, only if separately approved and safe,
one intended-app Direct Paste attempt. No external form submission.

**Time:** 10–15 minutes for the basic session, plus 5–10 minutes for an explicitly
approved paste/consent case. Stop at the agreed bound; no blind retries.

1. Verify the built bundle's hash, source SHA, configuration and separate
   `com.copystory.development` identity. Confirm the installed app/data are preserved.
   Arrange which app owns capture during the session; avoid two recorders and
   leave the development global shortcut off initially.
2. After explicit launch, confirm **CS Dev** and fresh onboarding. Close onboarding;
   verify no recording starts. Reopen onboarding and choose **Start remembering**
   only when recording is approved. Clipboard read permission is a separate step;
   a prompt is not a grant. Login remains off and untouched.
3. Copy one agreed synthetic text in the designated external app. Open from CS Dev
   → Open CopyStory. Verify one row, selection/search behavior, Copy, pin and Escape.
   Observe the actual clipboard only in this authorized session.
4. Create a synthetic Library template with one variable, save/open/render, and
   Copy. Confirm history admission only when recording is eligible; verify Copy
   keeps the form usable and clearing unpinned history does not clear Library.
5. Quit the exact development app and explicitly relaunch only within the approved
   session. Verify synthetic History pin/content and Library defaults persist.
6. If the separate paste case is approved: explain experimental current-focus
   semantics and residual races, opt in, request event-posting access if authorized,
   and verify actual availability. Invoke from the designated external app and
   choose one Paste. Observe which control received content. “Paste requested”
   is not proof of insertion; if nothing appears, stop and use explicit Copy.
7. Quit the exact owned process. Record outcome, evidence and limitations against
   the artifact. Do not delete any history or alter permission settings as cleanup.

```text
Verify exact candidate → explicit launch → onboarding/no recording on close
  → approved capture → History Copy → Library Copy → quit/relaunch persistence
  → separately approved one Paste case → observe destination → quit/checkpoint
                        ↓ unexpected or bound reached
                   stop, preserve evidence, no retry
```

**Stop:** unexpected identity or data sharing, existing history appearing, shortcut
collision, unapproved permission/login action, unexpected focus/input, duplicate
posting, unsafe/protected destination, missing UI, crash or time bound. Stop owned
processes and save the exact blocker. Do not switch accounts on the everyday Mac.

## Further acceptance, still required

- Native denied/undetermined/granted/revoked posting and clipboard-read consent,
  revocation while pending, secure input, unsupported/noneditable/image targets,
  cancellation, held modifiers, app termination/switch, Spaces/sleep, clipboard
  replacement and expiry. No retarget, retries, confirmed-insertion or atomicity
  claims. Check explicit Copy independently after refusal.
- Current focus within two fields/windows of the same intended app; no promise
  to restore an originally focused field. Test every advertised keyboard/mouse/
  VoiceOver explicit Paste action. Selection/editor Return must not post.
- History and Library storage failures and lifecycle, clear/save ordering, image
  data, exclusions/markers, pause/lock, corrupt/newer/locked/unwritable stores.
  Destructive fault injection requires disposable data/environment.
- Shortcut registration conflict/custom shortcut/relaunch; disabled shortcut must
  remain disabled. Login fresh off, explicit opt-in, requires approval, actual
  login launch, disable/revoke/relaunch without silent re-registration on suitable
  hardware/environment.
- Optional selected empty-store import/recovery per the approved scope. This
  feature remains required and unimplemented, not waived by fresh development.
- macOS26.0, current26.x and supported27.x on arm64, keyboard-only/VoiceOver,
  Reduce Transparency/Motion, privacy resources/effective sandbox, final signed
  archive/export/TestFlight acceptance. FRO22/23/26 remain separate gates.
