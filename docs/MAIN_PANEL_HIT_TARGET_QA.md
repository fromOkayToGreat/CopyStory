# Main Panel hit-target regression

The History and Library labels must own their whole existing half-container,
including transparent space around the text. The ellipsis menu label must own
its existing 39-point rounded surface. Apply content shapes inside the control
labels, after their frames; an outer decorative surface alone does not define
the label's interaction region. For the ellipsis, use `.menuStyle(.button)` with
`.buttonStyle(.plain)` and the existing hidden indicator: owner testing showed
that `.borderlessButton` still activated only near the glyph despite the label's
content shape. The proposed style change requires new native runtime validation;
the styled-trigger explanation is an inference, not a proven AppKit root cause.
Do not add overlapping gestures or duplicate
actions, which can change menu/keyboard/accessibility behavior.

Use the isolated `scripts/design/PanelPreview.swift` fixture, never a second live
clipboard recorder. The fixture uses temporary sample history/preferences,
does not start AppModel/AppDelegate, and asserts native integration gates off.
Test only tabs and menu opening/dismissal; do not activate Quit, Clear or Pause.
Start **each** tab-coordinate check from the opposite tab, so a click cannot
appear successful merely because its destination was already selected. Dismiss
the ellipsis menu with Escape before **each** new inside/outside click. Check
Pause state before and after outside-shape clicks. Compare before/after captures
at matching size, appearance and sample state; offline test counts do not prove
pointer hit testing.

| Check | Expected result |
| --- | --- |
| Library: click blank space near left/right edges and top/bottom of its half, then its text | Every click selects Library once and exposes the Library search/filter; selection accessibility trait moves to Library. |
| History: repeat at the same five positions within its half | Every click selects History once and restores History search/filters; selection trait moves to History. |
| Tab boundary and outside | A point inside either half selects only that half; outer padding must not become an overlapping target. |
| Ellipsis: click top/bottom/left/right blank space within the rounded 39-point surface, then the icon | The same Preferences / Clear unpinned history / Quit menu opens each time. Dismiss with Escape between checks. |
| Outside rounded surface | A click outside the visible rounded menu surface must not open it or toggle Pause. |
| Keyboard/accessibility | Existing button/menu roles and labels remain; tab selection and menu activation work through their native accessibility actions and normal keyboard focus. No duplicate controls. |
| Menu-bar commands | Hide History is absent; Open CopyStory, Pause/Resume recording, Preferences and Quit remain in their original order. The non-store update command remains conditional as before. |
| Dismissal regression | Escape, click-away and the configured shortcut keep their existing behavior. Dirty Library edits still require discard confirmation; saving still blocks dismissal. Removing the menu item must not delete or bypass dismissal/request handlers. |
| Appearance/layout | At 540 × 716 and the compact fixture, compare spacing, type, colors, selected backgrounds and control frames; no visual change. Repeat light/dark and reduced-transparency fixture appearances. |

## Validation for the initial patch

205 existing offline tests passed; unsigned Development and Production builds
and static package verification passed. The separate inert preview compiled and rendered; its
accessibility tree retained History/Library buttons, selected trait and History
controls menu button. No new implementation-mirroring unit test was added:
these interaction checks require native UI hit testing, not source-string or
frame-constant assertions.

Initial automated coordinate checks were **UNRUN**: computer control returned
`noWindowsAvailable` on the isolated preview despite successful accessibility
and screenshot reads. Raising that preview did not resolve it. No click result
or complete keyboard/VoiceOver pass is claimed. Keep this checklist open for
review before release; no installed-app test, permission change or build upload
was performed.

Owner subsequently tested the exact frozen first candidate: the wider History
and Library targets PASS, but the ellipsis still requires a click close to its
glyph (FAIL). Thus contentShape alone is not accepted as a menu fix. The current
button-menu-style correction retains the passed tab changes and menu semantics,
and awaits replacement-preview review and the same reset-between-clicks runtime
checks. No offline test count proves that correction works.

## Removed Hide History menu item

The menu-bar command dismisses the entire Main Panel, whether History or Library
is selected. It cancels presentation/pending selection state and orders the
panel out; it does not clear stored items or toggle recording. Recording follows
its existing enabled/paused/permission state. Open CopyStory in the menu-bar menu
or the configured shortcut (default Option–V) shows the panel again. Unsaved
Library edits retain the discard confirmation; dismissal is blocked while a
Library save is in progress. At the owner's request this patch removes only the
menu item's construction. Existing dismissal/request handlers and their tests
remain unchanged; Escape, click-away and shortcut behavior are preserved.

## Corrected menu appearance candidate

The button-menu label explicitly uses a 13-point regular SF Symbol, adaptive
macOS label color and a one-point upward image offset to match the previous
native borderless rendering. Only the image is adjusted; the 39-point frame,
rounded content shape and PanelSurface are unchanged. Native Menu tracking,
actions and accessibility label remain. Offscreen fixture comparisons and
current build identities are recorded in output/design/hit-target-menu-reviewed-review
in the owner checkout. Offscreen dark rendering has pre-existing black text
elsewhere and is not proof of live dark appearance or accessibility contrast.
Owner runtime edge-click acceptance is recorded below; keyboard/accessibility
acceptance remains pending.

## Owner acceptance of corrected candidate

The owner accepted the corrected sample-only preview after being asked to test
blank space inside all four ellipsis edges, dismiss with Escape between clicks,
and verify outside clicks leave the menu closed and Pause unchanged, with the
dots retaining their appearance. Response: “done! yes. this is it!” This records
owner-reported edge/outside/appearance success; it is not an independently
automated pointer test. History/Library full-container targets passed the
earlier owner test.

Tested implementation: frozen patch
`4d1d332a72fe12d4bb6bfe68a9adeeb0b16b4e2ee1acfa5f75231b412d8f1e3d`,
preview executable SHA-256
`879c8b4576e7f958b5bd0c8785297d331e3413402649ead14650d6980e1ce335`.
Only this acceptance documentation changed after that freeze. Final candidate
validation: 205 offline tests passed, Development and unsigned Production
builds/static verification passed, and 14 inert fixture renders completed.

Still unverified: keyboard/VoiceOver activation, live dark/accessibility
appearance, and the real status-menu removal at runtime. The preview has no
status item; Hide History removal is source/package verified. No installed
CopyStory, recording settings, permissions or real clipboard data were changed.
