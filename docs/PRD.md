> Historical product requirements for the first local release. Public distribution
> and opt-in updates are now specified in [UPDATES.md](UPDATES.md) and
> [RELEASING.md](RELEASING.md). A requirement here is not a claim of validation.

# CopyStory — Product Requirements Document

**Status:** Ready for implementation planning

**Platform:** macOS Tahoe 26 and later

**Product:** Personal, open-source clipboard history app

## 1. Product purpose

CopyStory remembers copied text and images so the user can find and paste them again without interrupting their work.

The app should feel like a native macOS utility: quiet in the menu bar, fast to open from the keyboard, and visually consistent with Tahoe’s Liquid Glass design.

## 2. Target user and use cases

The primary user works across terminals, code editors, browsers, documents, and chat apps.

Core use cases:

- Recover a command, link, or paragraph copied earlier.
- Paste several previously copied items without returning to their original apps.
- Find and reuse a screenshot or image.
- Pin frequently used snippets.
- Retain clipboard history after quitting the app or restarting the Mac.

## 3. Product principles

- **Fast access:** Opening, searching, and selecting should feel immediate.
- **Native interaction:** Use familiar macOS controls, keyboard behavior, and system appearance.
- **Local ownership:** Clipboard contents remain on the Mac.
- **Generous, bounded history:** History feels extensive while storage stays controlled.
- **Predictable behavior:** Recording, retention, and pasting states are visible and understandable.

## 4. Confirmed requirements

| Area | Requirement |
|---|---|
| Name | CopyStory |
| Appearance | Native macOS Tahoe Liquid Glass |
| Default shortcut | **Option–V (⌥V)** |
| Content | Text and images |
| Persistence | Save history across app and Mac restarts |
| Selection behavior | Paste directly into the previously active app |
| App coverage | Capture from all apps |
| Startup | Launch at login |
| Storage | Local only |
| Default retention | 1,000 items or 500 MB |
| Supporting controls | Search, pin, pause, delete, clear history |

## 5. Scope

The first release includes a menu-bar app, persistent text and image history, search, direct pasting, keyboard navigation, pinning, retention limits, preferences, and onboarding.

The first release excludes:

- Cloud sync and accounts.
- Files, folders, audio, and video.
- OCR and searching text inside images.
- AI features.
- Multiple-item batch pasting.
- Separate rich-text or HTML history.
- Cross-platform clients.

Copied images represented by clipboard image data are supported. Copying an image file in Finder does not require file-history support.

## 6. Clipboard capture

### Supported content

**Text**

- Preserve Unicode, line breaks, tabs, and whitespace.
- Store plain text without rich formatting.
- Do not modify commands or code snippets.

**Images**

- Capture images exposed through supported clipboard image formats.
- Preserve dimensions and transparency where supported.
- Generate thumbnails for history browsing.
- Preserve animation only if explicitly added in a later release.

If one clipboard event contains both text and image representations, capture it as one image item with associated text when available. Avoid producing duplicate entries from the same copy operation.

### Recording behavior

- Observe clipboard changes while CopyStory is running.
- Capture changes within one second under normal conditions.
- Ignore empty or unsupported clipboard content.
- Record the capture time and source app when available.
- Deduplicate identical content. A repeated copy moves the existing item to the top.
- Ignore clipboard changes created by CopyStory itself.
- Pause capture while the Mac is locked.
- Skip items marked confidential, transient, or automatically generated.
- Record from all apps without a default app exclusion list.

A user copying an unmarked password or API key may still create a history item. Onboarding must explain this plainly.

## 7. History and persistence

### Storage

- Save history locally across app exits, crashes, and Mac restarts.
- Keep content in the user’s Application Support directory.
- Store image files separately from searchable metadata.
- Restrict history files to the current user.
- Do not log clipboard contents.
- Use atomic writes or transactions to avoid partial records.
- Recover gracefully from missing or damaged records.

Application-level encryption is outside the first-release scope. CopyStory must describe local persistence accurately without presenting it as encrypted storage.

### Retention

Default limits:

- **1,000 items total.**
- **500 MB of history storage**, including images and thumbnails.

Remove the oldest unpinned items when either limit is exceeded. Pinning protects an item from automatic removal.

Pinned items count toward both limits. If pinned content alone fills the available capacity, stop saving new items and show a clear explanation with options to unpin items or increase the limit.

Reject an individual item that exceeds the configured storage budget. Do not evict the entire history to accommodate it.

### User controls

- Pin or unpin an item.
- Delete an individual item.
- Clear unpinned history.
- Clear all history, including pinned items, with confirmation.
- Adjust item and storage limits in preferences.

Deleting content must remove its stored payload and thumbnail. The app must not claim forensic secure erasure.

## 8. History interface

### Opening and closing

- Open through **⌥V** or the menu-bar icon.
- Remember the app and window active before opening.
- Focus the search field immediately.
- Close with Escape or by clicking outside.
- Repeating the shortcut toggles the panel.
- Opening through the menu bar must retain the previous foreground app as the paste destination.

### Layout

Use a compact floating panel with:

- Search field.
- History list, newest first.
- Text previews or image thumbnails.
- Pin indicator.
- Capture time and source app when available.
- Visible recording state.
- Access to preferences and history controls.

Pinned items should be easy to find through a dedicated filter without hiding recent history.

Long text uses a truncated preview with a full-content preview available. Image previews must preserve aspect ratio.

### Keyboard interaction

| Input | Action |
|---|---|
| ⌥V | Open or close history |
| Up / Down | Move selection |
| Return | Paste selected item |
| Escape | Close without pasting |
| ⌘C | Copy selected item without automatic pasting |
| Context menu | Pin, unpin, delete, or inspect item |

Typing searches immediately. Selection should remain stable as results update.

### Empty states

Provide distinct states for:

- No history yet.
- No matching search results.
- Recording paused.
- Storage capacity filled by pinned items.
- Missing permission for direct pasting.

## 9. Search

- Search text content and available source-app names.
- Match text case-insensitively.
- Support partial matches.
- Filter text, images, or pinned items.
- Do not require an exact phrase.
- Keep images discoverable by source app and capture time.
- Clearly indicate that image text is not searchable in the first release.

Search must avoid loading full image payloads or every record into the interface.

## 10. Direct pasting

Selecting an item should:

1. Place its content on the system clipboard.
2. Close the history panel.
3. Restore focus to the previously active app.
4. Request a standard paste action once that app is active.

Direct pasting requires Accessibility permission.

### Reliability and fallback

- Preserve focus to the prior window when possible.
- Avoid sending the paste command until the destination app is active.
- Prevent repeated selection from triggering duplicate pastes.
- Support both text and image clipboard payloads.
- If the destination app has closed or focus restoration fails, leave the item copied and display brief feedback.
- If permission is unavailable, copy the item and explain that the user can paste manually.
- Do not claim that pasting succeeded merely because a keyboard event was sent.
- Do not retry automatically in ways that could paste content into the wrong app.

Manual copy remains available at all times.

## 11. Visual design

### Appearance

- Use native Tahoe Liquid Glass materials and system controls where appropriate.
- Follow system light and dark appearance.
- Use the system font, standard spacing, and native focus indicators.
- Keep clipboard content readable over changing backgrounds.
- Provide a restrained, recognizable menu-bar icon.
- Avoid unnecessary animations or decorative effects.

### Accessibility

- Honor Reduce Transparency and Reduce Motion.
- Maintain readable contrast in light and dark modes.
- Support full keyboard operation.
- Give VoiceOver meaningful labels for items and actions.
- Describe image items using source app, timestamp, and dimensions when no descriptive text exists.
- Do not rely solely on color to communicate recording or selection state.

## 12. Onboarding and permissions

First launch should briefly explain:

- What CopyStory records.
- That history remains saved locally across restarts.
- That ordinary copied secrets can enter history.
- The default shortcut.
- How to pause or clear history.
- Why Accessibility permission is needed.

Provide a direct path to the appropriate macOS settings pane for Accessibility permission and show whether access has been granted.

Request no Full Disk Access, microphone, camera, or screen-recording permissions.

Enable launch at login through macOS-supported registration. If macOS requires user action or blocks registration, show the actual state and how to resolve it.

Recording and manual copy should work while Accessibility permission is pending.

## 13. Preferences

| Setting | Default |
|---|---|
| Global shortcut | ⌥V |
| Launch at login | Enabled |
| Maximum history items | 1,000 |
| Maximum history storage | 500 MB |
| Appearance | Follow system |
| Recording | Enabled |
| Respect confidential clipboard markers | Enabled |

Additional preferences:

- Current storage usage.
- Accessibility permission status.
- Clear-history controls.
- App version and link to source code.

Detect shortcut-registration failures and let the user choose another shortcut. Do not silently replace another app’s shortcut.

## 14. Privacy and security requirements

- No accounts, analytics, advertisements, or cloud synchronization.
- No network requests in the first release.
- No clipboard contents in diagnostic logs.
- No execution of copied content.
- Treat copied text and image data as untrusted input.
- Decode images with system frameworks and enforce resource limits.
- Store content only within the app’s designated storage location.
- Respect confidential clipboard markers.
- Provide a conspicuous pause control.
- Document local history access risks and retention behavior.

All-app capture does not override the requirement to respect confidential markers.

## 15. Technical direction

Recommended implementation:

- **Swift and SwiftUI** for the application and preferences.
- **AppKit** for menu-bar integration, clipboard access, panel behavior, and app activation.
- **SQLite or another transactional local store** for metadata and text.
- Separate image payloads and thumbnail cache.
- A supported global-hotkey mechanism that avoids requesting broad keyboard-monitoring access.
- macOS login-item registration.
- Accessibility APIs and standard paste-event synthesis for direct pasting.

Keep third-party dependencies minimal and document their licenses.

Organize clipboard capture, storage, retention, search, and paste coordination separately so each can be verified independently.

## 16. Performance targets

On the target Mac with the default history limits:

| Behavior | Target |
|---|---|
| Clipboard capture | Within 1 second |
| Panel opening | Within 200 ms after warm startup |
| Search response | Within 100 ms for typical text queries |
| Idle behavior | No sustained CPU activity; use low-frequency clipboard observation |
| Image browsing | Load thumbnails lazily without blocking interaction |
| Storage | Remain within configured limits after pruning completes |

Measure these targets during implementation. Avoid retaining full-resolution image payloads in memory unnecessarily.

## 17. Acceptance criteria

The first release is ready when:

- Text and supported images are captured reliably.
- History survives app and Mac restarts.
- Identical items are deduplicated.
- Text whitespace and image dimensions/transparency are preserved where supported.
- ⌥V opens history and focuses search.
- Keyboard search and navigation work.
- Selecting an item pastes into the previous app when permission and destination allow it.
- Manual-copy fallback works without Accessibility permission.
- Pinning, deletion, pause, and clear controls behave as described.
- Retention removes the oldest unpinned items and preserves pinned items.
- Confidential markers and lock-state capture restrictions are respected.
- CopyStory’s own clipboard writes do not create new entries.
- Login startup works and accurately reflects macOS approval state.
- Liquid Glass styling remains readable with accessibility settings enabled.
- No clipboard contents are transmitted or written to logs.
- Malformed or oversized content cannot crash the app or bypass storage limits.

## 18. Validation plan

Verify with representative workflows across a browser, Terminal, a code editor, a document editor, and an image-capable app.

Include:

- Unicode, multiline code, large text, screenshots, and transparent images.
- Repeated copies and rapid clipboard changes.
- Restart, quit, crash recovery, sleep, and lock/unlock.
- Missing or revoked Accessibility permission.
- Closed destination apps and unsuccessful focus restoration.
- Shortcut conflicts.
- Retention limits and histories filled with pinned items.
- Corrupt or missing image records.
- Light mode, dark mode, reduced transparency, keyboard-only use, and VoiceOver.

## 19. Delivery milestones

1. **Capture and storage:** Text/image capture, deduplication, persistence, and retention.
2. **History interface:** Menu-bar panel, search, previews, keyboard navigation, and pinning.
3. **Paste integration:** Shortcut, focus restoration, Accessibility onboarding, and fallback.
4. **Daily-use readiness:** Login startup, preferences, accessibility, performance, and recovery checks.

## 20. Deliverables

- Runnable CopyStory `.app` for the user’s Mac.
- Complete source code under an open-source license; **MIT** is the proposed default.
- Build and installation instructions.
- README covering shortcuts, permissions, storage, privacy, and limitations.
- Validation results and known issues.

The first build can be installed locally. Public distribution should include signing and notarization before release.