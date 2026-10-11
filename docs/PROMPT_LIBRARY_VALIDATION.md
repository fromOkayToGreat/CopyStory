# Prompt library validation — 2026-10-10

## Automated checks

`./scripts/test.sh`: 86 tests passed across 11 suites (49 platform/UI-model
tests and 37 core tests). All pre-existing tests remain included.

Coverage includes template syntax, escaping, repeated/case-sensitive variables,
Unicode and multiline rendering, required values, dropdown/default validation,
expanded-output limits, library CRUD/search/favorites/restart, corrupt/future
databases, permissions and process locks, and independent history/library budgets
and deletion. Platform checks cover clipboard-write failure, cancellation,
deduplication, recording policies, full-history import, failed-save draft
retention, dirty dismissal, shutdown draining, rapid favorite changes, and
clipboard-admission/clear ordering. Native editor checks cover accessibility
labels, multiline binding updates, and disabling editing while saving.

`COPYSTORY_DEVELOPMENT=1 ./scripts/build.sh`: universal development app built
and package validation passed. This does not establish public-release readiness.

## Security and release checks — 2026-10-10

Codex Security completed a Standard review of all 67 publishable files in the
working tree, including this feature, with an independent baseline audit,
architecture review, and focused clipboard/library investigation. It found no
reportable vulnerabilities or embedded credentials. The review checked storage
permissions and path admission, bound SQL values, non-executable template
substitution, clipboard privacy and capture ordering, destination checks, and
signed-update/release controls. This is bounded review evidence, not a guarantee
that the app has no vulnerabilities.

The reviewed snapshot was
`codex-security-snapshot/v1:sha256:b96a37a348d607678957a5b56da207460f901b744508dc3d4337dd6e1887bcb6`,
based on `6460d796b16f48e459718bbb5d2871c984ddc952` plus the prompt-library changes.
Only this validation note was expanded after that scan; application and test
sources were unchanged. Generated reports remain in the local security workbench
and are not bundled with the application.

Fresh validation used a disposable source copy, existing pinned dependencies,
synthetic data, named pasteboards and isolated preferences on Apple silicon,
macOS 27.0.1 (26A434), Swift 6.4 and SDK 27.0:

| Check | Observed result |
|---|---|
| Swift suite, automatic dependency resolution disabled | 86 passed: 49 platform, 37 core |
| Release configuration and source hygiene | Passed |
| Release/signature tests | 13 passed |
| Rehearsal-isolation tests | 3 passed |
| Universal development build | Passed: arm64 and x86_64, deployment target macOS 26.0 |
| Strict development package verification | Passed |
| Packaged runtime smoke test | Passed; updater disabled as expected |
| Whitespace/error check | `git diff --check` passed |

The first rehearsal test attempt in the disposable copy lacked a Git HEAD;
creating its local snapshot commit resolved that fixture setup error. No product
code change was required. Toolchain debug-symbol path warnings did not prevent
the build, strict package validation, or runtime loading.

The preceding results describe the October 10 snapshot. The former missing-
identity blocker and draft-PR instruction are superseded: PR #3 was merged as
`b1b00faf1a493a2106f6b94610c67a8395ef88b6`, signing and notarization now work, and the
maintainer reported successful prompt persistence, variables/dropdowns, library
direct paste, and independence from clearing history. Those are user-reported
results, not a new automated destination-insertion check. See the
[October 11 acceptance record](RELEASE_ACCEPTANCE_2026-10-11.md) for production
candidate evidence and remaining publication gates.

## Native UI observations

Used synthetic content in disposable data stores. The normal installed app and
its data were not replaced. Standard demo mode covered navigation, editing,
defaults, dropdowns, preview, favorites, search, and discard confirmation.

A disposable test copy of the app enabled clipboard writes with isolated
preferences/storage, updates and hotkey registration disabled, and external
capture callbacks discarded. Its UI and clipboard/paste implementation came
from the workspace sources. No harness code is part of the shipping app.

Observed:

- Save to Library opened the full history text as an independent editable draft.
- Text defaults and dropdown options/defaults saved successfully.
- Return inserted a newline in a variable field without triggering Paste.
- Changing fields and dropdowns changed the completed preview; reopening loaded
  saved defaults. Copy kept the form open.
- A completed synthetic prompt copied through the live UI pasted exactly into
  TextEdit using Command–V.
- Two different completed outputs appeared once each in the isolated history,
  attributed to CopyStory; saved template defaults remained independent.
- Image-only history exposed no Save to Library action.
- Reopening the panel returned to History.

UI checks found and fixed two native issues: closing the panel on transient
keyboard-focus changes interrupted dropdowns; a custom SwiftUI accessibility
label on selectable preview text could recurse in the AppKit accessibility
bridge. The final flow repeatedly opened and inspected the form without that
crash. Multiline fields now use native text views with native labels, and the
selectable preview uses its normal text accessibility. Clean test-app quit was
also verified after guarding panel teardown during termination.

## Remaining manual acceptance

- The October 10 automated direct-paste attempt did not insert the changed text
  into TextEdit. On October 11 the maintainer separately confirmed library direct
  paste in normal QA use. Keep these observations distinct; recheck the final
  production candidate in a suitable isolated environment.
- Pasting into a real AI composer remains unverified: the test browser was
  redirected into sign-in and stopped at a passkey error. No prompt was submitted.
- Accessibility labels were inspected, but a complete VoiceOver session and
  Reduce Transparency visual check remain manual checklist items.

See [the manual test checklist](MANUAL_TESTING.md#prompt-library) for the steps.
