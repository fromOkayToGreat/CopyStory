# Option + V shortcut migration

The product default is **Option + V (⌥V)**: physical ANSI V key code 9,
Carbon `optionKey` (2048). Production enables it by default; development keeps
its existing default-off policy. Preferences still supports custom bindings.

## Preference handling

Before the Option–V default changes, `DevelopmentConfiguration.preferenceDefaults` registered
key code 4, modifiers 768 and label `⇧⌘H` as fallback values. Startup did not
persist these values. `AppModel.changeShortcut` saved `shortcutCode`,
`shortcutModifiers` and `shortcutLabel` when a user selected a binding.
No origin/version flag distinguished a saved default from a custom choice.

- No saved binding fields: use ⌥V without writing a migration record. The old
  automatic ⌘⇧H binding is never registered in this process.
- Any saved binding fields: preserve them. Missing fields use the old fallback
  values rather than creating a hybrid binding with the new default. Invalid
  numeric values fail registration instead of trapping or silently replacing a
  saved preference. The shortcut-enabled preference is preserved independently.
- A saved ⌘⇧H is ambiguous. The least destructive behavior is to retain it;
  it may be a deliberate choice. Preferences describes the new default and lets
  that user explicitly choose ⌥V. Do not claim every existing user's old binding
  has been removed. This is a documented migration limitation.

PR #15 introduced the shared Carbon-backed `DefaultShortcut` constants and
selected-shortcut onboarding. Those constants, onboarding, default/relaunch tests
and documentation updates are retained. The resolver uses those same constants
for a fresh binding. Fallback binding fields now live outside the UserDefaults registration domain,
so repeated model loads continue to recognize the absence of saved fields.
No production user preferences were inspected or changed for implementation.

## Registration and behavior

Carbon registration remains exclusive. Repeating the same registration is
idempotent. A successful replacement releases only this owner's old handle;
a collision retains the existing binding and saved selection. Startup failure
reports that the shortcut could not register and offers the menu or Preferences.
There is no automatic alternate binding or claimed registration success.
Disablement and shutdown release owned resources. Responder-delivered events
match only an enabled, successfully registered shortcut; disabled/unavailable
bindings cannot swallow typing inside CopyStory. Menu/tooltip state follows the
current binding and registration state. The Open menu action remains available.

Panel toggle, navigation, Escape, selection and Direct Paste paths are retained.
Option + V normally types √ on a US layout and Calculator uses it for square
root; the owner accepted these tradeoffs. Other applications or system contexts
can conflict or prevent delivery. Successful registration is not proof of panel
invocation or paste insertion in every context. Protected/noneditable targets,
secure input, permissions, held modifiers and focus changes retain existing
Direct Paste restrictions. No broader reliability claim is made.

PR #15’s current shortcut annotations in release scope and reconstruction notes
are retained. Historical test evidence retains its original shortcuts. The sandbox DirectPaste prototype's `--shortcut default`
still denotes its historical Command–Shift–H fixture, not the current app default.

## Proposed live check (not run)

Estimate: 15–20 minutes after separate approval, using an explicitly identified
candidate and synthetic data in an isolated test identity/account. Do not run
this alongside the installed production recorder or change its preferences.
Prepare/verify identity and ownership first; request no permission changes
without approval. Register ⌥V only when the designated test session owns it.

| App | Bounded check |
| --- | --- |
| Finder | ⌥V opens once with search focused; repeating closes; default ⌘⇧H no longer opens; menu Open still works. |
| Safari | In an ordinary editable scratch field, invoke, search/select with arrows, Escape to dismiss, then invoke and Copy. If separately approved/available, one Direct Paste and observe exactly one insertion in the intended field. Never submit. |
| TextEdit | Synthetic plain text: toggle, search/arrows, Return/Copy under existing semantics; one separately approved Direct Paste after releasing modifiers. Observe destination and single insertion. |
| ChatGPT | Synthetic unsent composer draft: open/dismiss, navigate/select/Copy; one separately approved Direct Paste only if focus/permission checks permit. Observe one insertion; never submit. |

Also check Preferences custom binding → relaunch retention → disabled binding
passes typing through. Use a controlled second test owner to test collision only
if explicitly approved; do not take over another application's binding. Record
registration and physical-key invocation separately. Keep historical evidence.

Stop immediately on collision, wrong identity, unexpected capture/data, permission
prompt outside approval, missing panel, unexpected focus, unintended/duplicate
insertion, protected/unsupported target, crash, or the 20-minute bound. Preserve
failure evidence; do not retry, retarget, or change production/TCC/history to
complete the matrix. “Paste requested” alone is not insertion evidence.
