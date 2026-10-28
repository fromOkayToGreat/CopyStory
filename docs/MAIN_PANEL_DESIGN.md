# Main Panel glass implementation candidate

Approved MagicPath project `465978621903917056`, component `465982269497151488`, revision **`465982269497151489`**. Do not follow a moving latest revision.

Preferred panel: **540 × 716 points**, radius 26. `MainPanelDesign.frame(in:)` clamps size and origin to the visible screen, including the existing vertical bias. Header uses the existing packaged App Store icon at 50 points; title 21 semibold, tagline 13. Content inset 20, search height 46, rows minimum 70 with 8-point gaps, 44-point native type/image previews, 15-point content and 13-point metadata. Footer remains outside the scrolling list.

`HistoryView` and its row views retain actual model bindings, search, filters, selection, context actions, pause/menu commands and History/Library access. Library retains real prompt controls; no prototype Library behavior or row-chevron navigation was introduced. The existing menu-bar icon asset is unchanged. Lifecycle, paste routing, clipboard capture and permissions are unchanged.

The native `NSGlassEffectView` supplies platform material. SwiftUI overlays supply borders, selection and control surfaces. Material appearance varies with OS, backdrop, appearance and accessibility settings; browser CSS is not pixel-identical. Dark styling and opaque Reduce Transparency fallback are native adaptations requiring visual acceptance. The preview-only environment override exercises the fallback without changing system preferences.

## Reproduction and evidence

Use full Xcode via `DEVELOPER_DIR`, then run `scripts/test-development.sh`. Run `scripts/design/render-panel.sh` with a fresh absolute output directory to produce isolated native fixtures and a separate preview app. Read the script before use. The renderer links inert testable objects, asserts disabled integration gates, uses temporary sample stores/defaults, and never calls AppModel.start or AppDelegate. Interactive mode opens only its own preview window. Batch cacheDisplay images verify geometry, not faithful window-server material.

Candidate validation: 205 offline tests passed (145 platform, 60 core); development and unsigned production builds passed static verification. No production app launch, installation or release occurred. Evidence is retained separately in the workspace under output/design/native-glass-review and the adjacent native-glass-production-review/native-glass-development-review folders.

## Remaining acceptance

Independent code review and owner visual agreement are pending. Live production Option–V/open-close lifecycle, actual paste/copy, recording, VoiceOver and OS-wide accessibility setting integration were not run. Fixture navigation/reattachment and offline routing tests do not replace those checks. Run remaining production acceptance later in an explicitly approved isolated session. Commit and draft PR only after agreement; TestFlight follows separately.
