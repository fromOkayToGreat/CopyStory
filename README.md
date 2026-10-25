# CopyStory

CopyStory is a native macOS clipboard history and prompt library app. This branch
integrates reconstructed source into an ordinary **development** app. It is not
an exact recovery of the installed 1.0/build7 source and is not release accepted.

The approved v1 target is free, Apple silicon (arm64), macOS 26–27 with minimum
26.0, and Mac App Store distribution. No Sparkle updater is included in the
normal configuration. See [approved scope](docs/APP_STORE_RELEASE_SCOPE_2026-10-13.md)
and [development status](docs/DEVELOPMENT.md).

## Support and privacy

The welcome screen, Preferences → About CopyStory, and menu-bar menu link to the
public [Privacy Policy](https://copystory.app/privacy/) and
[Support](https://copystory.app/support/) pages. Links open in the default browser
only when selected; reading them does not finish onboarding or start recording.
Use these same URLs for the Privacy Policy URL and Support URL in App Store Connect.

## Build and checks

Use a full Xcode installation with the macOS SDK and Swift 6. Select it for each
command with `DEVELOPER_DIR`; changing the system-wide selection is unnecessary.

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer scripts/test-development.sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer scripts/build-development.sh /tmp/copystory-development-candidate
```

The output directory must be fresh. Building never installs or launches the app.
The candidate has a local ad-hoc sandbox signature, version1.0.0/build1 under a
separate development bundle ID. This is not an allocated App Store build number.
Its plist embeds exact source SHA, clean/dirty state and configuration; the output
also contains build/sign logs, static verification and executable SHA256.

For repeatable personal updates, see [development signing](docs/DEVELOPMENT_SIGNING.md).
`Config/DevelopmentSigned.xcconfig` and the plan-only signed-build entry point
are prepared separately. Using a private key, installation and runtime readiness
still need their own approvals. Do not treat an ad-hoc rebuild as a stable update.

The default Swift package excludes Sparkle. `scripts/test-development.sh` selects
offline synthetic suites; the full historical test suite includes AppKit,
named-pasteboard and shortcut tests and is not a safe substitute for that command.
Historical direct-download scripts are retained as references, not the current
App Store packaging or publication workflow.

## Development behavior

- The menu-bar item is **CS Dev**, with the existing History/Library interface.
  Either mouse button opens the native menu; choose **Open CopyStory**. Escape
  closes History. Opening/searching/selecting never requests a paste.
- Identity is `com.copystory.development`. Preferences use current-app standard
  defaults under that separate development identity.
  History uses `CopyStory Development` beneath this app's Application Support
  directory (inside its sandbox container when sandboxed). It does not open,
  migrate, delete or share the production app's store. All copies with the
  development identity share the development store/preferences; candidate paths
  are not data isolation and must not run concurrently.
- A startup failure still stops the app. Its alert and local startup log include
  a fixed stage/category, an allowlisted error domain and an available numeric
  code. Diagnostics exclude paths, SQL, clipboard content, arbitrary error domains
  and localized error descriptions. This reports failures; it does not repair or
  reset a store, and a sandbox warning alone does not identify the cause.
- Recording starts only after **Start remembering** in onboarding, respects saved
  pause state, and skips the clipboard present when recording starts. Closing
  onboarding is not consent. macOS clipboard access remains separate.
- The global shortcut starts off in development to avoid collisions with an
  installed CopyStory. Enable/configure it in Preferences; registration conflicts
  are reported. The official default shortcut is **Option–V (⌥V)**.
  Existing explicit shortcut choices are preserved; users without a saved override
  inherit the new default. Onboarding, Preferences and the menu-bar tooltip show
  the selected shortcut. This default changes when running a build containing it.
- Launch at login starts off and registration changes only after explicit user
  choice. Startup only reads system status; registration/approval-required and
  actively enabled states are described separately.
- History retains text/images/pins/search/limits/retention; Library retains local
  templates, variables/defaults/dropdowns/favorites. Copy explicitly writes the
  selected item or completed prompt without activation or event posting. Replaying
  History does not add another history entry; completed Library output is admitted
  only when recording is eligible. No prompt is submitted to an online service.

## Experimental Direct Paste

Enable it explicitly in Preferences and separately request event-posting access.
Requesting access is not proof that macOS granted it. A false preflight is
reported as unavailable/undetermined, not as a proven denial.

History Return/double-click/context Paste and Library Paste/Command–Return use
one shared request lifecycle. Invocation captures the intended external app;
Paste requests one balanced Command–V pair to that app's current focus. It does
not verify or restore the originally focused field/window. Missing/stale identity,
app switching, termination, Spaces changes, sleep, expiry, cancellation, held
modifiers, clipboard replacement or unavailable permission cancel the request.
There is no automatic retry. Copy remains a separate explicit action.

Secure input reported by macOS blocks posting. This is not a detector for every
protected, noneditable or unsupported foreign control. Such destinations may
ignore the request. Focus, clipboard state, permission checks and posting are
separate OS operations and cannot guarantee atomic delivery. **“Paste requested”
does not confirm insertion.** Check the destination and use Copy if needed.
Permission revocation races and protected-input behavior require a bounded native
safety decision; compile/model passes do not close FRO22.

## Privacy and release status

History stays local, is not encrypted by the app, and may contain unmarked
secrets. Confidential markers and exclusions reduce capture; pause before copying
sensitive material. See [privacy](docs/PRIVACY.md).

Optional explicit empty-store import, including the approved recovery contract,
remains required v1 work. It is not implemented or silently deferred by this
fresh-development-store milestone. Final platform/VoiceOver/consent/login/import,
archive/signing/TestFlight and App Store acceptance remain outstanding.

No installation, app launch, live clipboard/input, permission changes, merge,
release publication or Apple submission is part of the build milestone. Follow
[manual acceptance](docs/MANUAL_TESTING.md) only in a separately approved session
and [App Store release guidance](docs/RELEASING.md) for future distribution.

Licensed under [MIT](LICENSE). Retained legacy updater notices are under
[ThirdPartyNotices](ThirdPartyNotices); Sparkle is not linked into this candidate.
