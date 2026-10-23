#if FOCUS_IDENTITY_CHECK
import AppKit
import CopyStoryCore

// Compiled only in the separate QA target; no lifecycle or delivery policy.
@MainActor
struct FocusIdentityCheckHooks {
    let trace: (String, HistoryRequestSimulation.Ticket) -> Void
    let beforePop: (NSMenu, HistoryRequestSimulation.Ticket) -> Bool
    let visibility: (Bool, HistoryRequestSimulation.Ticket?) -> Void
}
#endif
