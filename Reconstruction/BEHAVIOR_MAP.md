# Milestone-one behavior/change map

Reference:7305c69 plus verified86-file preserved overlay. Original native History/Library UI/storage retained. This is NEW reconstruction, not source7 recovery.

| Area | Surviving implementation | Milestone-one change / unknown |
| --- | --- | --- |
| Invocation | Command-Shift-H/menu opens existing panel; original activating behavior and AX destination restoration | Preserve UI for compilation. No runtime invocation tests. Future nonactivating destination adapter needs separate review. |
| Explicit Copy/Paste | Copy writes payload; Paste coordinator writes then attempts AX restoration/event posting; Library passes admission callback | All configurations use a disabled coordinator that sends no events, performs no AX or activation/permission work. Explicit Paste returns unavailable feedback before clipboard write. Explicit Copy remains existing behavior, unrun. This is an incomplete engineering build, not approved manual-only release scope. |
| Cancellation | Historical coordinator had bounded checks but no reconstructed app/Space gate | Automatic delivery entirely disabled. No claims of restored FRO22 guarantees. |
| History admission | Existing monitor/model and Library onClipboardWrite callback | Keep existing source. Disabled Paste does not call write/admission/close callbacks. Copy/admission semantics unrun, future adapter review required. |
| Permission feedback | Original AX trust/request and feasibility explanation | Disabled coordinator reports false and never requests/opens settings; no permission repair. Shipping-reconstruction UI should state automatic paste unavailable; do not imply granting permission enables it. |
| Library dismissal | Existing LibraryViews/forms/editor and AppDelegate dismissal behavior | Reuse unchanged; lost FRO30 lifecycle fix not recovered or reimplemented. Explicitly open later milestone. |
| Login/import/privacy | Approved default-off login and optional selected import; final manifest/API audit unresolved | No login setting mutation or import/privacy implementation added. Ordinary launch must remain disabled for this compile-only milestone to prevent unreviewed recording/login. |

Missing chain:FRO23 review.patch → integrated build5 → permission-feedback.patch(build6) → fro30-library-paste.patch(build7). Exact patch/source manifests remain missing. Current milestone reconstructs only target/config/resource build inputs and a hard delivery-off adapter. No release-date/build-number allocation or acceptance relaxation.

Historical pasteRequiresBothOriginalWindowAndField test was moved verbatim to LEGACY_AX_TEST.swift.txt because its removed AX adapter type is intentionally absent. It is not a supported current-focus or disabled-adapter test. New disabled policy tests cover the milestone behavior; no AX restoration acceptance claimed. Other legacy platform suites are compiled but not executed under the no-live-clipboard scope.
