import Foundation

@MainActor struct PanelActivationEnvironment {
    var now: () -> TimeInterval
    var isActive: () -> Bool
    var isTrackingMenu: () -> Bool
    var requestActivation: () -> Void
    // A synchronous native sink: caller verifies own active/visible/key state.
    var present: () -> Bool
    var hide: () -> Void
    var scheduleTimeout: (TimeInterval, @escaping @MainActor () -> Void) -> (() -> Void)
}

// Shared native orchestration; fake clock/state/sinks test the actual gate.
// Activation is an observed own-app state, never inferred from an API call.
@MainActor final class PanelActivationGate {
    static let maximumSeconds: TimeInterval = 2
    enum Result: String { case presented, cancelled, timedOut, invalidRequest, invalidClock, presentationUnverified }
    @MainActor private final class Request {
        let id = UUID()
        let start: TimeInterval
        let deadline: TimeInterval
        let valid: () -> Bool
        let completion: (Result) -> Void
        let preservesExistingPresentation: Bool
        var cancelTimeout: (() -> Void)?
        var presenting = false
        init(start: TimeInterval, valid: @escaping () -> Bool, preservesExistingPresentation: Bool, completion: @escaping (Result) -> Void) {
            self.preservesExistingPresentation = preservesExistingPresentation
            self.start = start; deadline = start + PanelActivationGate.maximumSeconds
            self.valid = valid; self.completion = completion
        }
    }
    private let environment: PanelActivationEnvironment
    private var request: Request?
    private var latestID: UUID?
    var isPending: Bool { request != nil }
    var isFocusingExistingPresentation: Bool { request?.preservesExistingPresentation == true }
    init(environment: PanelActivationEnvironment) { self.environment = environment }
    func begin(valid: @escaping () -> Bool, preservingExistingPresentation: Bool = false, completion: @escaping (Result) -> Void) {
        cancel()
        let now = environment.now()
        guard now.isFinite, (now + Self.maximumSeconds).isFinite else {
            if !preservingExistingPresentation { environment.hide() }
            completion(.invalidClock); return
        }
        let next = Request(start: now, valid: valid, preservesExistingPresentation: preservingExistingPresentation, completion: completion)
        request = next; latestID = next.id
        armDeadline(next, after: Self.maximumSeconds)
        guard request?.id == next.id else { return }
        guard valid() else { finish(next, .invalidRequest); return }
        if !environment.isActive() {
            environment.requestActivation()
        }
        advance(id: next.id)
    }
    func activationOrMenuChanged() {
        if let id = request?.id { advance(id: id) }
    }
    private func armDeadline(_ current: Request, after seconds: TimeInterval) {
        let id = current.id // Do not retain Request through its own timer.
        let cancelTimeout = environment.scheduleTimeout(seconds) { [weak self] in
            guard let self else { return }
            self.advance(id: id)
            guard let pending = self.request, pending.id == id else { return }
            let remaining = pending.deadline - self.environment.now()
            if remaining.isFinite && remaining > 0 { self.armDeadline(pending, after: remaining) }
        }
        if request?.id == id { current.cancelTimeout = cancelTimeout }
        else { cancelTimeout() }
    }
    func cancel() {
        guard let current = request else { return }
        request = nil
        current.cancelTimeout?()
        if !current.preservesExistingPresentation { environment.hide() }
        current.completion(.cancelled)
    }
    private func finish(_ current: Request, _ result: Result) {
        guard request?.id == current.id else { return }
        request = nil
        current.cancelTimeout?()
        if result != .presented && !current.preservesExistingPresentation { environment.hide() }
        current.completion(result)
    }
    private func advance(id: UUID) {
        guard let current = request, current.id == id, !current.presenting else { return }
        let now = environment.now()
        guard now.isFinite, now >= current.start else { finish(current, .invalidClock); return }
        guard now < current.deadline else { finish(current, .timedOut); return }
        guard current.valid() else { finish(current, .invalidRequest); return }
        guard environment.isActive() else { return }
        guard !environment.isTrackingMenu() else { return }
        current.presenting = true
        let verified = environment.present()
        current.presenting = false
        // A native ordering call can reenter cancellation via delegate callbacks.
        guard request?.id == current.id else {
            if latestID == current.id && !current.preservesExistingPresentation { environment.hide() }
            return
        }
        let after = environment.now()
        guard verified, after.isFinite, after >= now, after < current.deadline,
              current.valid(), environment.isActive(), !environment.isTrackingMenu() else {
            finish(current, .presentationUnverified); return
        }
        finish(current, .presented)
    }
}
