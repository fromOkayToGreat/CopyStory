import Foundation
#if COPYSTORY_DEVELOPMENT
import OSLog
#endif

// Closed schema: no payload, foreign identity, path, title or error string can
// enter this sink. Relative uptime and local sequence numbers correlate events.
@MainActor final class HistoryPresentationDiagnostics {
    enum Event: String, CaseIterable {
        case statusBegin, statusEnd, trackingBegin, trackingReturned, menuBegin, menuOwned, menuCancelled
        case openReceived, openGuard, finishMenu, presentationBegin, presentationGuard
        case activationRequested, becameActive, resignedActive, menuDepthChanged
        case orderFrontBefore, orderFrontAfter, hide, cancelActivation, gateBegin, gateWait, gateResult
        case requestObservation, requestDismissed, closeRequested, hideRequested, ignoredOwnActivation, geometry
    }
    enum Reason: String, CaseIterable {
        case none, accepted, lifecycle, ticketMismatch, generationMismatch, invalidRequest
        case noCommand, hideChoice, noOpenChoice, existing, coalesced, onboarding, missingTicket
        case inactive, trackingMenu, presented, cancelled, timedOut, invalidClock, presentationUnverified
        case reentrantCleanup, gateFailure, explicitClose, explicitHide, directHide, resignActive, paste
        case activated, spaceChanged, terminated, sleep, stopped, menuReplacement, focusTransfer, termination
    }
    // Numeric-only geometry, quantized to tenths of a point. Reject nonfinite
    // or out-of-range values rather than logging arbitrary descriptions.
    struct Rectangle: Equatable {
        let x, y, width, height: Int
        init?(_ rect: CGRect, relativeTo origin: CGPoint = .zero) {
            let values = [rect.origin.x - origin.x, rect.origin.y - origin.y, rect.size.width, rect.size.height]
            guard values.allSatisfy({ $0.isFinite && abs($0) <= 131_072 }) else { return nil }
            let numbers = values.map { Int(($0 * 10).rounded()) }
            x = numbers[0]; y = numbers[1]; width = numbers[2]; height = numbers[3]
        }
        var line: String { "\(x),\(y),\(width),\(height)" }
    }
    nonisolated static func alphaPermille(_ alpha: CGFloat) -> Int? {
        guard alpha.isFinite, (0...1).contains(alpha) else { return nil }
        return Int((alpha * 1000).rounded())
    }
    struct ViewGeometry: Equatable {
        let frame, bounds: Rectangle?
        let hidden, attachedToPanel, positiveBounds, needsLayout, ambiguousLayout: Bool
        let alpha: Int?
        init(frame: CGRect, bounds: CGRect, hidden: Bool, attachedToPanel: Bool,
             alpha: CGFloat, needsLayout: Bool, ambiguousLayout: Bool) {
            self.frame = Rectangle(frame); self.bounds = Rectangle(bounds)
            self.hidden = hidden; self.attachedToPanel = attachedToPanel
            positiveBounds = bounds.width.isFinite && bounds.height.isFinite && bounds.width > 0 && bounds.height > 0
            self.alpha = HistoryPresentationDiagnostics.alphaPermille(alpha)
            self.needsLayout = needsLayout; self.ambiguousLayout = ambiguousLayout
        }
        var line: String {
            "\(frame?.line ?? "unsampled"),\(bounds?.line ?? "unsampled"),\(hidden),\(attachedToPanel),\(positiveBounds),\(alpha.map(String.init) ?? "unsampled"),\(needsLayout),\(ambiguousLayout)"
        }
    }
    struct Geometry: Equatable {
        enum Phase: String, CaseIterable { case placement, beforeOrder, afterOrder, hostLayout }
        enum Selection: String, CaseIterable { case pointer, main, first }
        let phase: Phase
        let selection: Selection
        let screenCount, screenOrdinal: Int?
        let targetVisible, requested, actual, contentLayout: Rectangle?
        let intersectsTarget, containedInTarget: Bool?
        let intersectsAnyScreen: Bool?
        let screenMatchesTarget: Bool
        let hostIsGlassContent: Bool?
        let onActiveSpace, occlusionVisible, windowVisible, windowOpaque: Bool
        let windowAlpha: Int?
        let glass, host: ViewGeometry?
        init(phase: Phase, selection: Selection, screenCount: Int, screenOrdinal: Int?,
             targetVisible: CGRect, requested: CGRect, actual: CGRect, contentLayout: CGRect,
             intersectsAnyScreen: Bool, screenMatchesTarget: Bool, onActiveSpace: Bool,
             occlusionVisible: Bool, windowVisible: Bool, windowOpaque: Bool, windowAlpha: CGFloat, glass: ViewGeometry?, host: ViewGeometry?, hostIsGlassContent: Bool?) {
            self.phase = phase; self.selection = selection
            self.screenCount = (0...64).contains(screenCount) ? screenCount : nil
            self.screenOrdinal = screenOrdinal.flatMap { (0..<64).contains($0) ? $0 : nil }
            self.targetVisible = Rectangle(targetVisible, relativeTo: targetVisible.origin)
            self.requested = Rectangle(requested, relativeTo: targetVisible.origin)
            self.actual = Rectangle(actual, relativeTo: targetVisible.origin)
            self.contentLayout = Rectangle(contentLayout)
            intersectsTarget = self.targetVisible != nil && self.actual != nil ? targetVisible.intersects(actual) : nil
            containedInTarget = self.targetVisible != nil && self.actual != nil ? targetVisible.contains(actual) : nil
            self.intersectsAnyScreen = self.actual == nil ? nil : intersectsAnyScreen; self.screenMatchesTarget = screenMatchesTarget
            self.onActiveSpace = onActiveSpace; self.occlusionVisible = occlusionVisible
            self.windowVisible = windowVisible; self.windowOpaque = windowOpaque
            self.windowAlpha = HistoryPresentationDiagnostics.alphaPermille(windowAlpha)
            self.glass = glass; self.host = host; self.hostIsGlassContent = hostIsGlassContent
        }
        var line: String {
            "geometry=sampled geometryPhase=\(phase.rawValue) screenSelection=\(selection.rawValue) screenCount=\(screenCount.map(String.init) ?? "unsampled") screenOrdinal=\(screenOrdinal.map(String.init) ?? "unsampled") targetVisibleTenths=\(targetVisible?.line ?? "unsampled") requestedTenths=\(requested?.line ?? "unsampled") actualTenths=\(actual?.line ?? "unsampled") contentLayoutTenths=\(contentLayout?.line ?? "unsampled") intersectsTarget=\(intersectsTarget.map(String.init) ?? "unsampled") containedInTarget=\(containedInTarget.map(String.init) ?? "unsampled") intersectsAnyScreen=\(intersectsAnyScreen.map(String.init) ?? "unsampled") screenMatchesTarget=\(screenMatchesTarget) onActiveSpace=\(onActiveSpace) occlusionVisible=\(occlusionVisible) windowVisible=\(windowVisible) windowOpaque=\(windowOpaque) windowAlphaPermille=\(windowAlpha.map(String.init) ?? "unsampled") glassGeometry=\(glass?.line ?? "unsampled") hostGeometry=\(host?.line ?? "unsampled") hostIsGlassContent=\(hostIsGlassContent.map(String.init) ?? "unsampled")"
        }
    }
    // No scheduling: two naturally occurring hosting layouts per fresh Open.
    struct LayoutBudget {
        private(set) var remaining = 0
        mutating func begin() { remaining = 2 }
        mutating func consume() -> Bool {
            guard remaining > 0 else { return false }
            remaining -= 1; return true
        }
    }
    struct Record: Equatable {
        let event: Event
        let reason: Reason
        let elapsed: TimeInterval
        let sequence: UInt64
        let requestGeneration: Int?
        let active: Bool?
        let visible: Bool?
        let key: Bool?
        let pending: Bool?
        let menuDepth: Int?
        let presentationOwned: Bool?
        let menuOwned: Bool?
        let ticketMatches: Bool?
        let generationMatches: Bool?
        let valid: Bool?
        let geometry: Geometry?
        private func value<T>(_ value: T?) -> String { value.map { String(describing: $0) } ?? "unsampled" }
        var line: String {
            if let geometry {
                // Keep the complete geometry record below 1 KiB. Unrelated state
                // is sampled by the adjacent ordinary presentation records.
                return "event=\(event.rawValue) reason=\(reason.rawValue) elapsed=\(elapsed) sequence=\(sequence) requestGeneration=\(value(requestGeneration)) \(geometry.line)"
            }
            return "event=\(event.rawValue) reason=\(reason.rawValue) elapsed=\(elapsed) sequence=\(sequence) requestGeneration=\(value(requestGeneration)) active=\(value(active)) visible=\(value(visible)) key=\(value(key)) pending=\(value(pending)) menuDepth=\(value(menuDepth)) presentationOwned=\(value(presentationOwned)) menuOwned=\(value(menuOwned)) ticketMatches=\(value(ticketMatches)) generationMatches=\(value(generationMatches)) valid=\(value(valid)) \(geometry?.line ?? "geometry=unsampled")"
        }
    }
    private let sink: ((Record) -> Void)?
    private let now: () -> TimeInterval
    private var origin: TimeInterval?
    private var sequence: UInt64 = 0
    // Default is inert, including no clock read. Native app opts in explicitly.
    init(now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }, sink: ((Record) -> Void)? = nil) {
        self.now = now; self.sink = sink
    }
    static func system() -> HistoryPresentationDiagnostics {
        #if COPYSTORY_DEVELOPMENT
        let logger = Logger(subsystem: DevelopmentConfiguration.bundleID, category: "historyPresentation")
        return HistoryPresentationDiagnostics(sink: { record in logger.notice("\(record.line, privacy: .public)") })
        #else
        return HistoryPresentationDiagnostics() // No logging, clock or geometry sampling.
        #endif
    }
    func emit(_ event: Event, _ reason: Reason = .none, active: Bool? = nil, visible: Bool? = nil,
              key: Bool? = nil, pending: Bool? = nil, menuDepth: Int? = nil, presentationOwned: Bool? = nil, menuOwned: Bool? = nil,
              ticketMatches: Bool? = nil, generationMatches: Bool? = nil, valid: Bool? = nil, requestGeneration: Int? = nil, geometry: Geometry? = nil) {
        guard let sink else { return }
        let instant = now()
        if origin == nil, instant.isFinite { origin = instant }
        let delta = instant - (origin ?? instant)
        let elapsed = delta.isFinite && delta >= 0 ? delta : 0
        sequence &+= 1
        sink(Record(event: event, reason: reason, elapsed: elapsed, sequence: sequence, requestGeneration: requestGeneration,
                    active: active, visible: visible, key: key, pending: pending, menuDepth: menuDepth,
                    presentationOwned: presentationOwned, menuOwned: menuOwned, ticketMatches: ticketMatches, generationMatches: generationMatches, valid: valid, geometry: geometry))
    }
    func emitGeometry(requestGeneration: Int?, snapshot: @MainActor () -> Geometry) {
        guard sink != nil else { return } // Inert sinks do not sample native state.
        emit(.geometry, requestGeneration: requestGeneration, geometry: snapshot())
    }
}

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
        var diagnosticGeneration: Int?
        init(start: TimeInterval, valid: @escaping () -> Bool, preservesExistingPresentation: Bool, completion: @escaping (Result) -> Void) {
            self.preservesExistingPresentation = preservesExistingPresentation
            self.start = start; deadline = start + PanelActivationGate.maximumSeconds
            self.valid = valid; self.completion = completion
        }
    }
    private let environment: PanelActivationEnvironment
    private let diagnostics: HistoryPresentationDiagnostics
    private var request: Request?
    private var latestID: UUID?
    var isPending: Bool { request != nil }
    var isFocusingExistingPresentation: Bool { request?.preservesExistingPresentation == true }
    init(environment: PanelActivationEnvironment, diagnostics: HistoryPresentationDiagnostics? = nil) {
        self.environment = environment; self.diagnostics = diagnostics ?? .init()
    }
    func begin(valid: @escaping () -> Bool, preservingExistingPresentation: Bool = false, diagnosticGeneration: Int? = nil, completion: @escaping (Result) -> Void) {
        diagnostics.emit(.gateBegin, requestGeneration: diagnosticGeneration)
        cancel()
        let now = environment.now()
        guard now.isFinite, (now + Self.maximumSeconds).isFinite else {
            diagnostics.emit(.gateResult, .invalidClock, requestGeneration: diagnosticGeneration)
            if !preservingExistingPresentation { diagnostics.emit(.hide, .invalidClock, requestGeneration: diagnosticGeneration); environment.hide() }
            completion(.invalidClock); return
        }
        let next = Request(start: now, valid: valid, preservesExistingPresentation: preservingExistingPresentation, completion: completion)
        next.diagnosticGeneration = diagnosticGeneration
        request = next; latestID = next.id
        armDeadline(next, after: Self.maximumSeconds)
        guard request?.id == next.id else { return }
        guard valid() else { finish(next, .invalidRequest); return }
        if !environment.isActive() {
            diagnostics.emit(.activationRequested, requestGeneration: next.diagnosticGeneration)
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
        diagnostics.emit(.gateResult, .cancelled, requestGeneration: current.diagnosticGeneration)
        if !current.preservesExistingPresentation { diagnostics.emit(.hide, .cancelled, requestGeneration: current.diagnosticGeneration); environment.hide() }
        current.completion(.cancelled)
    }
    private func finish(_ current: Request, _ result: Result) {
        guard request?.id == current.id else { return }
        request = nil
        current.cancelTimeout?()
        diagnostics.emit(.gateResult, result.diagnosticReason, requestGeneration: current.diagnosticGeneration)
        if result != .presented && !current.preservesExistingPresentation { diagnostics.emit(.hide, .gateFailure, requestGeneration: current.diagnosticGeneration); environment.hide() }
        current.completion(result)
    }
    private func advance(id: UUID) {
        guard let current = request, current.id == id, !current.presenting else { return }
        let now = environment.now()
        guard now.isFinite, now >= current.start else { finish(current, .invalidClock); return }
        guard now < current.deadline else { finish(current, .timedOut); return }
        guard current.valid() else { finish(current, .invalidRequest); return }
        guard environment.isActive() else { diagnostics.emit(.gateWait, .inactive, requestGeneration: current.diagnosticGeneration); return }
        guard !environment.isTrackingMenu() else { diagnostics.emit(.gateWait, .trackingMenu, requestGeneration: current.diagnosticGeneration); return }
        current.presenting = true
        let verified = environment.present()
        current.presenting = false
        // A native ordering call can reenter cancellation via delegate callbacks.
        guard request?.id == current.id else {
            if latestID == current.id && !current.preservesExistingPresentation { diagnostics.emit(.hide, .reentrantCleanup, requestGeneration: current.diagnosticGeneration); environment.hide() }
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

private extension PanelActivationGate.Result {
    var diagnosticReason: HistoryPresentationDiagnostics.Reason {
        switch self {
        case .presented: return .presented
        case .cancelled: return .cancelled
        case .timedOut: return .timedOut
        case .invalidRequest: return .invalidRequest
        case .invalidClock: return .invalidClock
        case .presentationUnverified: return .presentationUnverified
        }
    }
}
