# Security policy

CopyStory is pre-1.0 software. Security fixes target the current main branch
and latest published release; older builds do not have a separate support term.
Public notarized binaries remain gated on the [release criteria](docs/RELEASING.md).

## Reporting a vulnerability

Use [GitHub private vulnerability reporting](https://github.com/fromOkayToGreat/CopyStory/security/advisories/new).
Include affected versions, a synthetic reproduction, expected/actual behavior,
and impact. If private reporting is unavailable, open a minimal issue asking
for a private contact route without exploit details or sensitive attachments.
There is no guaranteed response time or bounty program.

Never submit clipboard databases, private messages, passwords, signing keys,
notarization credentials, or real captured payloads. Redact paths and identifying
details from logs. For ordinary bugs use the issue template.

## Security boundaries

- Local clipboard history is plaintext, protected with owner file permissions.
  There is no app lock or protection from another process running as the user.
- Unmarked secrets can enter history. Exclusions use best-effort foreground-app
  attribution; confidential marker checks are not a secret detector.
- Pins are protected from retention. Deletion is not forensic secure erasure.
- Direct paste checks destination focus, with manual copy as fallback. macOS
  cannot make the final focus check and synthetic paste atomic.
- Updates require signed metadata and signed archives. The update key is a
  separate trust mechanism from Apple Developer ID signing/notarization.

See [PRIVACY](docs/PRIVACY.md), [HARDENING](docs/HARDENING.md), and
[UPDATES](docs/UPDATES.md) for limitations and recovery.
