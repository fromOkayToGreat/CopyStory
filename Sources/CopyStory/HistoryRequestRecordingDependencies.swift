import CopyStoryCore

// Internal initializer injection only; no runtime setting enables this path.
// Recording retains its concrete sinks. The native source adapter uses the same
// lifecycle through its separately gated environment; no runtime opt-in exists.
@MainActor
struct HistoryRequestRecordingDependencies {
    enum Mode { case recording, native }
    let mode: Mode
    let requests: HistoryRequestSimulation
    let captureObservation: (@MainActor () -> HistoryRequestSimulation.Snapshot)?
    let loadPayload: (@MainActor (String) async throws -> CapturePayload)?
    let beforeWrite: (@MainActor (HistoryRequestSimulation.Ticket) async -> HistoryRequestSimulation.Reason?)?
    let prepareDestination: (@MainActor (HistoryRequestSimulation.Ticket) async -> HistoryRequestSimulation.Reason?)?
    let beforeFinish: @MainActor () async -> Void
    // Value injection replaces monitor reads only in the offline path. All
    // ordinary model eligibility (onboarding/demo/pause/lock/exclusion) remains.
    struct CaptureState { var isRecording: Bool; var isLocked: Bool = false }
    let captureState: @MainActor () -> CaptureState
    let onSuccessfulWrite: @MainActor (CapturePayload) -> Void
    init(requests: HistoryRequestSimulation,
         mode: Mode = .recording,
         captureObservation: (@MainActor () -> HistoryRequestSimulation.Snapshot)? = nil,
         loadPayload: (@MainActor (String) async throws -> CapturePayload)? = nil,
         captureState: @escaping @MainActor () -> CaptureState = { .init(isRecording: false) },
         beforeWrite: (@MainActor (HistoryRequestSimulation.Ticket) async -> HistoryRequestSimulation.Reason?)? = nil,
         prepareDestination: (@MainActor (HistoryRequestSimulation.Ticket) async -> HistoryRequestSimulation.Reason?)? = nil,
         beforeFinish: @escaping @MainActor () async -> Void = {},
         onSuccessfulWrite: @escaping @MainActor (CapturePayload) -> Void = { _ in }) {
        self.mode = mode; self.beforeWrite = beforeWrite; self.prepareDestination = prepareDestination
        self.requests = requests; self.captureObservation = captureObservation; self.loadPayload = loadPayload
        self.captureState = captureState
        self.beforeFinish = beforeFinish; self.onSuccessfulWrite = onSuccessfulWrite
    }
    func feedback(_ feedback: HistoryRequestSimulation.Feedback, wrote: Bool = false) -> String {
        guard mode == .native else { return feedback.text }
        switch feedback {
        case .idle: return "Choose an item, then Paste or Copy."
        case .waiting: return "Copied; checking the intended app. No paste is confirmed."
        case .copyRecorded: return "Copied. Press ⌘V in your intended app."
        case .pairRecorded, .pairRequested:
            return "Paste requested in the captured app. The destination controls insertion; no insertion is confirmed. No automatic retry."
        case .blocked(.boardChanged):
            return "The clipboard changed. Paste was not requested. Select the item and use Copy again before pasting."
        case .blocked(.writeFailed):
            return "Couldn’t complete the clipboard write. The clipboard may have changed. Nothing was sent."
        case .blocked(let reason):
            let cause: String
            switch reason {
            case .cancelled: cause = "the request was cancelled"
            case .consumed: cause = "this request was already used"
            case .destinationUnavailable: cause = "the captured app is unavailable"
            case .identityChanged: cause = "the active app changed"
            case .expired: cause = "the request expired"
            case .boardChanged: cause = "the clipboard changed"
            case .permissionDenied, .permissionUnknown: cause = "paste permission is unavailable"
            case .modifiersHeld: cause = "modifier keys are still held"
            case .deliveryDisabled: cause = "native delivery is disabled in this source build"
            case .eventCreationFailed: cause = "the paste event could not be created"
            case .activationFailed: cause = "the captured app did not become active"
            case .protectedInput: cause = "macOS reports secure input"
            case .writeFailed: cause = "the clipboard write failed"
            }
            return wrote ? "Copied. Paste was not requested because \(cause). Press ⌘V manually in your intended app." :
                "Paste was not requested because \(cause). Nothing was copied or sent. Explicit Copy is a separate action."
        }
    }

}

// Injected observations only; no native observer registration is performed.
enum HistoryRecordingObservation {
    case activated(HistoryRequestSimulation.Identity?)
    case spaceChanged
    case terminated(HistoryRequestSimulation.Identity)
    case sleep
    case stopped
}
