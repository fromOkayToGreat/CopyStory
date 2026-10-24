# Development readiness check — local review receipt

Base: `fcec33a347522a131da8519010e4d0fa16c17316`.
Implementation: `f19a0f121115f8d6eb32b0307811d1c212df2e27`.
Branch: `codex/check-readiness-20261024`.

## Behavior

Development Preferences offers Check readiness. Each click replaces the prior
in-memory report, reads AX trust and event-posting preflight, and records the
existing displayed readiness. Only the next existing two-second timer refresh
may produce a second sample. A five-second deadline, sequence mismatch, intervening
Preferences-open refresh, dismissal, close, or termination stops the pending pair.
There are no retries or new polling loops. A stale initial display remains visible
with its actual refresh age. Repeated clicks cancel the old deadline and use a
fresh generation. Deadline delivery and rendering depend on main-actor scheduling;
a timer arriving after the deadline cannot collect a second native sample.

Both normal display-refresh sites retain their original preflight call; they now
also track sequence and uptime. Paste admission still checks event-posting access
and does not use AX trust. Copy and Paste effect implementations are unchanged.
No permission request, AX tree traversal, event posting, clipboard/history read,
foreign identity/window title, credential access or security change is added.
The identity report uses only this process's public metadata and a canonical-path
boolean (not the path). The report is neither persisted nor logged.

## Independent review

A separate reviewer inspected the full patch, initially identified two P2 issues
(refresh attribution on Preferences-open and retained-window close handling),
then verified both corrections and reported no remaining blocking findings.
It independently bound all eight implementation files to the commit above using
canonical sorted JSON of filename to SHA-256, content-set SHA-256:
`e591c5d7d7911dcdca1e42d9bece67e8fe1f1ddc92b8c308cca5cb66ec49a888`.
This receipt is documentation only and does not alter those files.

## Validation

- Targeted injected ReadinessCheckTests: 3 passed. Checks independent native/UI
  values, refresh sequence and age, no third sample, delayed/backward/mismatched
  refresh, repeated replacement, timeout and dismissal. Native readers are not
  called by these tests.
- Repository scripts/test-development.sh offline selection: 122 platform tests
  in 9 suites and 60 core tests in 5 suites passed (182 total, includes the 3 new
  tests). Existing clipboard/GUI/shortcut native suites were not selected.
- Full development Xcode build: BUILD SUCCEEDED with
  CODE_SIGNING_ALLOWED=NO and CODE_SIGNING_REQUIRED=NO. No signing script used.
- git diff --check and scripts/check-source-hygiene.py passed.

Tests used Xcode, temporary scratch/module caches and
COPYSTORY_SHIPPING_RECONSTRUCTION=1; no network dependencies were required.
The first Swift attempt failed writing the default cache in the restricted
execution context; the supported escalated run with explicit temporary caches
passed. Existing Swift concurrency warnings and an out-of-date iOS Simulator
support warning remain; neither failed these checks. Xcode performed its normal
LaunchServices registration of the staged unsigned product; it was not launched
or installed. The compile artifact labels the reviewed base revision plus dirty
state because implementation was not yet committed at compile time. It is compile
validation only, not a candidate for installation or a clean-identity receipt.

## Limits and next boundary

No signing, installation, app launch, push or merge occurred. Accepted installed
signed build 3 was left untouched. Direct Paste remains OFF by the existing owner
baseline; it was not observed or toggled during this work. No live API signal or
UI acceptance was collected. Window-close/UI behavior has static review and
compile coverage, not a live acceptance result. Future signed deployment and a
single in-app report need their separately coordinated execution step. A report
from new source cannot establish build 3's historical native returns or identify
the unresolved authorization cause. Do not infer stale TCC or sandbox denial.
