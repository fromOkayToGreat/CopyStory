# Manual acceptance checklist

This is a test plan, not a record of passed tests. Record actual results in
[`../VALIDATION.md`](../VALIDATION.md), including macOS version, machine, app
build, permission state, observed behavior, and any reproduction steps.

Use synthetic content only. Do not copy real passwords, tokens, private
messages, or production data for validation. Tests that lock, log out, alter
permissions, change the system clipboard, or stop the app interrupt normal
work; run them in a controlled test session. Keep the normal history separate
from intentionally damaged test data.

## Capture and representation

- [ ] Launch the app. Verify content copied before launch is not imported.
- [ ] Copy distinct text from a browser, Terminal, code editor, document
  editor, and chat app. Each new supported copy should appear once, within
  one second under normal conditions.
- [ ] Copy Unicode, emoji, combining characters, tabs, leading/trailing
  spaces, blank lines, and multiline code. Paste into a plain-text document
  and compare every character, including trailing whitespace.
- [ ] Copy rich text and confirm the recovered text is plain text.
- [ ] Copy a screenshot and an image with transparency; verify dimensions,
  alpha, orientation, and visible content after pasting into an image editor.
- [ ] Copy an event with image and text representations. Confirm one image
  item and usable associated text, without a second history entry.
- [ ] Copy identical text twice, with other content between copies. Confirm
  the existing item moves to the top without losing its pinned state.
- [ ] Repeat an identical image copy and verify deduplication.
- [ ] Try empty and unsupported clipboard representations. Confirm they
  create no blank rows or errors that prevent subsequent valid captures.
- [ ] Copy several items faster than the polling interval. Record which are
  captured; polling cannot guarantee a history of every intermediate value.
- [ ] Check that capture time and available source-app names are plausible.
  Clipboard polling infers source from the foreground app; switching apps
  during the interval can make attribution approximate.
- [ ] Copy a Finder file reference. Confirm it is not treated as arbitrary
  file history. A genuine supported clipboard image representation may be
  captured as an image.

## Recording, privacy, and session boundaries

- [ ] Pause from the visible control, copy test text, and resume. Confirm the
  text copied while paused is not saved retroactively.
- [ ] Lock the Mac, change the clipboard through a controlled test helper if
  possible, then unlock. Confirm no locked-session content enters history.
- [ ] Sleep and wake the Mac. Confirm capture resumes without duplicate
  entries or replaying stale clipboard content.
- [ ] Supply synthetic clipboard data bearing each confidential, transient,
  and automatically generated marker supported by the implementation.
  Confirm it is skipped while marker protection is enabled.
- [ ] Confirm ordinary unmarked synthetic secret-like text can be captured,
  and onboarding explains this limitation. Do not use a real secret.
- [ ] Copy or paste from CopyStory and confirm its own clipboard writes do
  not produce extra history rows or repeated paste actions.
- [ ] Check the clipboard access denied state, where macOS exposes it.
  Confirm the app explains blocked recording and does not claim permission.
- [ ] Inspect app diagnostic output during synthetic tests. Confirm contents
  do not appear in logs or error messages.
- [ ] Review source and observe the process with an appropriate network
  monitor. Confirm no update checks occur before consent or a manual check, and that
  enabled updates send no clipboard/history data.

## History, search, and keyboard access

- [ ] Open using Command–Shift–H and the menu-bar icon. The search field
  receives focus; the active external app remains the intended destination.
- [ ] Repeat the shortcut to toggle the panel closed. Close with Escape and
  by clicking outside; neither action should alter the clipboard.
- [ ] Navigate with Up/Down, type a query, and press Return. Check that
  selection remains associated with the same item as results update.
- [ ] Use Command–C to copy the selected history item without automatic
  paste. Then paste manually into a document.
- [ ] Search partial words, mixed case, Unicode case variants, source-app
  names, and more than one search term. Check matching behavior and ordering.
- [ ] Exercise All, Text, Images, and Pinned filters. Confirm an image remains
  discoverable using available source/date metadata and that OCR is not
  advertised.
- [ ] Scroll through enough results to exercise pagination/lazy thumbnails.
  Confirm older matching records are reachable and images retain aspect ratio.
- [ ] Open the full-content preview for a long text entry and inspect all
  content. Confirm a truncated list preview does not truncate the payload.
- [ ] Check no-history, no-results, paused, pinned-capacity, and missing-paste-
  permission states independently.
- [ ] Pin, unpin, delete, and inspect entries through available controls and
  context menus, using both keyboard and mouse. Exercise Command–P, Command–I,
  and Command–Delete on the selected history item.

## Direct paste and permissions

- [ ] Deny Accessibility permission. Recording and manual copy must continue;
  selecting a result must leave it copied and explain manual Command–V.
- [ ] Grant Accessibility through the app's settings action. Confirm current
  permission status refreshes without claiming that a request grants access.
- [ ] From each representative app, select a history item and verify exactly
  one paste reaches its previously focused editable field/window.
- [ ] Test two windows of the same app, minimized windows, full-screen apps,
  and multiple Spaces. Record any focus-restoration limitations.
- [ ] Test text in a non-editable destination and images in an app that does
  not accept image paste. Sending Command–V must not be reported as proof of
  insertion.
- [ ] Close the destination while the panel is open. Selecting a result must
  retain the clipboard payload and give manual-paste feedback, without
  injecting into an unrelated app.
- [ ] Switch foreground apps during paste preparation. Verify focus checks
  prevent sending the paste command to an unintended app.
- [ ] Rapidly click or press Return repeatedly. Confirm at most one paste is
  requested per deliberate selection operation.
- [ ] Revoke Accessibility while the app is running. Confirm fallback remains
  usable and no automatic retries send unexpected content.
- [ ] Confirm no Full Disk Access, microphone, camera, screen-recording, or
  broad keyboard-monitoring permission is requested.

## Persistence, retention, and recovery

- [ ] Apply a retention period in a disposable history; old unpinned text and
  image files disappear, pins remain, and a newly copied item is retained.
- [ ] Exclude an app, copy synthetic text and an image there, and confirm no
  new history entry. Remove the exclusion and confirm a new copy is captured.
- [ ] Confirm browser-extension and background-app attribution limits are clear.
- [ ] Change the focused field or tab after opening history; automatic paste
  must fall back to manual copy when the original element cannot be verified.
- [ ] Close history while a copy-only lookup is pending; clipboard and feedback
  must remain unchanged. A subsequent deliberate copy must still work.
- [ ] In preview mode, Open storage folder opens the preview's temporary folder.

- [ ] Quit/relaunch and restart the Mac. Confirm history, pins, exact text,
  image payloads, and relevant preferences persist.
- [ ] Force-quit during a synthetic capture, relaunch, and confirm the store
  remains usable without partially displayed entries.
- [ ] Inspect the history directory and files: owner-only directory/file
  access, image payloads separate from metadata, and no payloads outside the
  designated history directory.
- [ ] Reduce the item limit with a mix of old/new pinned and unpinned items.
  Confirm oldest unpinned entries are removed first and pins survive.
- [ ] Exercise the byte limit with text, images, thumbnails, and many small
  records. Compare the reported usage to actual allocated database, journal,
  payload, and thumbnail files after pruning/checkpointing completes.
- [ ] Fill capacity with pinned items. Confirm new entries stop saving with
  a clear explanation; unpinning or increasing capacity permits new captures.
- [ ] Copy one item larger than the total budget. Confirm rejection preserves
  the pre-existing history rather than evicting it all.
- [ ] Delete an image and verify its payload and thumbnail are removed.
- [ ] Clear unpinned history with pins present, then cancel a clear-all action.
  Confirm pins remain and cancellation removes nothing.
- [ ] Confirm clear-all, including pinned items, removes records and image
  files only after confirmation. Deletion must not promise secure erasure.
- [ ] In an isolated test store, remove a payload/thumbnail, corrupt image
  bytes, and introduce malformed metadata. Relaunch and inspect behavior:
  missing entries should be handled without a crash or lost valid history.
- [ ] Test an unavailable/unwritable storage location and a full disk in a
  disposable environment. Confirm a truthful error and no silent fallback to
  nonpersistent recording.
- [ ] Test truncated image formats, extreme dimensions, decompression-heavy
  images, oversized text, and oversized thumbnails using synthetic fixtures.
  Confirm resource limits and continued responsiveness.

## Preferences, startup, and visual accessibility

- [ ] Verify default shortcut, recording state, marker protection, item limit
  (1,000), storage limit (500 MB, decimal), and system appearance behavior.
- [ ] Choose another shortcut, restart, and verify persistence. Try a shortcut
  already registered by another app; confirm conflict feedback and recovery.
- [ ] Enable launch at login from an installed stable app location, read the
  reported system status, and log out/in. Verify actual launch rather than
  only successful registration.
- [ ] Disable/revoke login approval in macOS settings and confirm the app
  reports the actual disabled/approval-required state.
- [ ] Check current storage usage, app version, source repository action, and
  clear-history controls.
- [ ] Inspect light and dark modes over several backgrounds. Confirm readable
  text, selection, icons, focus indicators, and image aspect ratios.
- [ ] Enable Reduce Transparency and Reduce Motion. Confirm legible opaque
  alternatives and no distracting required animation.
- [ ] Use VoiceOver through history, previews, preferences, and onboarding.
  Confirm useful labels, recording state, selected items, and image dimensions
  and source/time descriptions.
- [ ] Complete primary tasks using the keyboard alone. Check that color is
  never the only signal for recording, selection, or an error.

## Performance measurements

Use 1,000 representative synthetic records with a mixture of text and images.
Measure warm startup separately from first launch and document tools, method,
sample count, median, and worst observed duration.

| Behavior | Target | Record observed result |
| --- | --- | --- |
| Clipboard change to visible history | ≤ 1 second normally | Pending |
| Shortcut to usable warm panel | ≤ 200 ms | Pending |
| Typical text query to updated results | ≤ 100 ms | Pending |
| Idle CPU over several minutes | No sustained activity | Pending |
| Image scrolling | Lazy thumbnails; no blocking full payload loads | Pending |
| Storage after pruning | Within configured limits unless protected pins exceed them | Pending |

Repeat the relevant tests after a fix; do not mark a scenario passed because
an adjacent automated test passed. Keep blocked or unmeasured criteria visible
in the release validation report.
