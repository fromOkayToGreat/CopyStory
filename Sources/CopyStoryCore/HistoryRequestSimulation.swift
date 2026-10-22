// Shared request lifecycle. No AppKit, clipboard, event, permission, focus,
// login or settings API lives here. The original initializer retains concrete
// recording sinks; the source-only native adapter injects audited effects.
public final class HistoryRecordingSinks {
    public enum Payload: Equatable { case text(String), image([UInt8]), textAndImage(String, [UInt8]) }
    public enum Key: Equatable { case down, up }
    public enum Record: Equatable {
        case writeAttempt(Int, Payload), writeSucceeded(Int, Int), writeFailed(Int)
        case admissionOpportunity(Int), dismissalIntent(Int)
        case eventIntent(Int, HistoryRequestSimulation.Identity, Key)
    }
    public private(set) var records: [Record] = []
    public private(set) var boardVersion = 0
    public var writesSucceed = true
    public init() {}
    // Models an intervening external write; no pasteboard is accessed.
    public func replaceBoardForSimulation() { boardVersion += 1 }
    fileprivate func write(_ payload: Payload, token: Int) -> Int? {
        records.append(.writeAttempt(token, payload))
        guard writesSucceed else { records.append(.writeFailed(token)); return nil }
        boardVersion += 1; records.append(.writeSucceeded(token, boardVersion))
        return boardVersion
    }
    fileprivate func admitAndDismiss(token: Int, admissionOpportunity: Bool) {
        // Admission opportunity only, not a real history-store write. Eligibility,
        // deduplication/capture/clear policy remains a later integration concern.
        if admissionOpportunity { records.append(.admissionOpportunity(token)) }
        records.append(.dismissalIntent(token))
    }
    fileprivate func pair(token: Int, identity: HistoryRequestSimulation.Identity) {
        // Concrete in-memory sink only; no callback that can substitute OS input.
        records.append(.eventIntent(token, identity, .down))
        records.append(.eventIntent(token, identity, .up))
    }
}

public final class HistoryRequestSimulation {
    public struct Identity: Equatable {
        public let pid: Int32
        public let bundleID: String
        public let bundlePath: String
        public let launchTime: Double
        public init(pid: Int32, bundleID: String, bundlePath: String, launchTime: Double) {
            self.pid = pid; self.bundleID = bundleID; self.bundlePath = bundlePath; self.launchTime = launchTime
        }
    }
    public enum Permission: Equatable { case available, denied, unknown }
    public struct Snapshot {
        public var now: Double
        public var frontmost: Identity?
        public var destinationAlive: Bool
        public var permission: Permission
        public var modifiersReleased: Bool
        public var boardVersion: Int
        public var presentationOwnsFocus: Bool
        public var secureInput: Bool
        public init(now: Double, frontmost: Identity?, destinationAlive: Bool = true,
                    permission: Permission = .available, modifiersReleased: Bool = true, boardVersion: Int = 0, presentationOwnsFocus: Bool = false, secureInput: Bool = false) {
            self.now = now; self.frontmost = frontmost; self.destinationAlive = destinationAlive
            self.permission = permission; self.modifiersReleased = modifiersReleased; self.boardVersion = boardVersion
            self.presentationOwnsFocus = presentationOwnsFocus
            self.secureInput = secureInput
        }
    }
    public struct Ticket: Equatable { public let generation: Int }
    public enum Action { case selection, search, edit, copy, paste }
    public enum Admission { case opportunity, existingHistoryReplay }
    public enum Cancellation: Equatable { case explicit, activation, termination, space, sleep, selection }
    public enum Reason: String, Equatable {
        case cancelled, consumed, destinationUnavailable, identityChanged, expired
        case boardChanged, permissionDenied, permissionUnknown, modifiersHeld, writeFailed
        case deliveryDisabled, eventCreationFailed, activationFailed, protectedInput
    }
    public enum Outcome: Equatable {
        case ignored, pending(Ticket), rejected(Reason), recordedCopy, recordedPair, requestedPair, stale
    }
    public enum Feedback: Equatable {
        case idle, waiting, copyRecorded, pairRecorded, pairRequested, blocked(Reason)
        public var text: String {
            switch self {
            case .idle: return "Offline History simulation ready; real delivery remains disabled."
            case .waiting: return "Simulated write recorded; awaiting final validation. No real clipboard or events used."
            case .copyRecorded: return "Simulated Copy write recorded. No real clipboard or events used."
            case .pairRecorded: return "Simulated event intent recorded; no real paste or insertion is confirmed."
            case .pairRequested: return "Paste requested; insertion is not confirmed. No automatic retry. Use explicit Copy if needed."
            case .blocked(let reason):
                return "Simulation blocked (\(reason.rawValue)). No real clipboard or events used. Explicit Copy is a separate action."
            }
        }
    }
    public enum PairResult { case recorded, requested, blocked(Reason) }
    // Synchronous effects only. Callers serialize on MainActor. Every callback
    // boundary rechecks generation; event sinks must deliver one fixed-target
    // pair or report failure, never retry/retarget or claim insertion.
    public struct Effects {
        let write: (HistoryRecordingSinks.Payload, Int) -> Int?
        let admissionAndDismissal: (Int, Bool) -> Void
        let pair: (Int, Identity) -> PairResult
        public init(write: @escaping (HistoryRecordingSinks.Payload, Int) -> Int?,
                    admissionAndDismissal: @escaping (Int, Bool) -> Void = { _, _ in },
                    pair: @escaping (Int, Identity) -> PairResult) {
            self.write = write; self.admissionAndDismissal = admissionAndDismissal; self.pair = pair
        }
    }
    private enum Phase { case ready, sampling, waiting, finishing, consumed }
    private struct Pending {
        let ticket: Ticket
        let identity: Identity
        let writeVersion: Int
    }
    private let ownPID: Int32
    private let effects: Effects
    private let snapshot: () -> Snapshot
    private var ticket = Ticket(generation: 0)
    private var captured: Identity?
    private var openedAt: Double = 0
    private var phase: Phase = .consumed
    private var invalidated = false
    private var pending: Pending?
    public private(set) var feedback: Feedback = .idle
    public var currentTicket: Ticket { ticket }
    public var isCancelled: Bool { invalidated }
    public var isPending: Bool { phase == .sampling || phase == .waiting || phase == .finishing }
    public convenience init(ownPID: Int32, sinks: HistoryRecordingSinks, snapshot: @escaping () -> Snapshot) {
        self.init(ownPID: ownPID, effects: Effects(
            write: { sinks.write($0, token: $1) },
            admissionAndDismissal: { sinks.admitAndDismiss(token: $0, admissionOpportunity: $1) },
            pair: { token, identity in sinks.pair(token: token, identity: identity); return .recorded }), snapshot: snapshot)
    }
    public init(ownPID: Int32, effects: Effects, snapshot: @escaping () -> Snapshot) {
        self.ownPID = ownPID; self.effects = effects; self.snapshot = snapshot
    }
    @discardableResult public func abort(_ reason: Reason, ticket expected: Ticket) -> Outcome {
        guard expected == ticket else { return .stale }
        invalidated = true
        return reject(reason)
    }
    @discardableResult public func open(identity: Identity?, now: Double) -> Ticket {
        ticket = Ticket(generation: ticket.generation + 1)
        captured = identity.flatMap {
            $0.pid > 0 && $0.pid != ownPID && !$0.bundleID.isEmpty && !$0.bundlePath.isEmpty &&
                $0.launchTime.isFinite && $0.launchTime >= 0 ? $0 : nil
        }
        openedAt = now; invalidated = false; phase = .ready; pending = nil; feedback = .idle
        return ticket
    }
    public func cancel(_ reason: Cancellation, ticket expected: Ticket) {
        guard expected == ticket else { return }
        invalidated = true
        // Current generation only. Returning to a target never clears this flag.
        feedback = .blocked(.cancelled)
    }
    public func applicationActivated(_ identity: Identity?, ticket expected: Ticket) {
        if identity != captured { cancel(.activation, ticket: expected) }
    }
    public func targetTerminated(_ identity: Identity, ticket expected: Ticket) {
        if identity == captured { cancel(.termination, ticket: expected) }
    }
    public func handle(_ action: Action, payload: HistoryRecordingSinks.Payload, admission: Admission = .opportunity) -> Outcome {
        switch action {
        case .selection, .search, .edit:
            if isPending { cancel(.selection, ticket: ticket) }
            return .ignored
        case .copy:
            guard !isPending else { return .ignored }
            // Explicit Copy is available even after a failed/denied Paste; it
            // cannot schedule a pair and does not infer real history admission.
            let owner = ticket, previous = phase
            phase = .sampling
            let version = effects.write(payload, owner.generation)
            guard owner == ticket, phase == .sampling else { return .stale }
            phase = previous
            guard version != nil else { feedback = .blocked(.writeFailed); return .rejected(.writeFailed) }
            feedback = .copyRecorded; return .recordedCopy
        case .paste: return prepare(payload, admission: admission)
        }
    }
    private func reason(_ state: Snapshot, identity: Identity, version: Int? = nil) -> Reason? {
        if invalidated { return .cancelled }
        if !state.now.isFinite || !openedAt.isFinite || state.now < openedAt || state.now - openedAt >= 30 { return .expired }
        if state.secureInput { return .protectedInput }
        if !state.destinationAlive { return .destinationUnavailable }
        if state.frontmost != identity {
            // Only pre-write may be owned by the actual presented CopyStory
            // panel. Final delivery always requires the captured external app.
            guard version == nil, state.presentationOwnsFocus,
                  state.frontmost?.pid == ownPID else { return .identityChanged }
        }
        if let version, state.boardVersion != version { return .boardChanged }
        switch state.permission {
        case .denied: return .permissionDenied
        case .unknown: return .permissionUnknown
        case .available: break
        }
        if !state.modifiersReleased { return .modifiersHeld }
        return nil
    }
    private func reject(_ reason: Reason) -> Outcome {
        phase = .consumed; pending = nil; feedback = .blocked(reason)
        return .rejected(reason)
    }
    private func prepare(_ payload: HistoryRecordingSinks.Payload, admission: Admission) -> Outcome {
        guard phase == .ready else { return .rejected(.consumed) }
        // Consume BEFORE calling any injected dependency; reentry cannot write twice.
        phase = .sampling
        let owner = ticket
        guard !invalidated else { return reject(.cancelled) }
        guard let identity = captured else { return reject(.destinationUnavailable) }
        let state = snapshot()
        guard ticket == owner, phase == .sampling else { return .stale }
        if let failure = reason(state, identity: identity) { return reject(failure) }
        let version = effects.write(payload, owner.generation)
        guard ticket == owner, phase == .sampling else { return .stale }
        guard !invalidated else { return reject(.cancelled) }
        guard let version else { return reject(.writeFailed) }
        effects.admissionAndDismissal(owner.generation, admission == .opportunity)
        guard ticket == owner, phase == .sampling else { return .stale }
        guard !invalidated else { return reject(.cancelled) }
        pending = Pending(ticket: owner, identity: identity, writeVersion: version)
        phase = .waiting; feedback = .waiting; return .pending(owner)
    }
    public func finish(_ expected: Ticket) -> Outcome {
        guard expected == ticket else { return .stale }
        guard phase == .waiting, let request = pending, request.ticket == expected else {
            return .rejected(.consumed)
        }
        // One final claim, consumed before sampling. Even denied final state
        // cannot retry. Old async completions never clear a new generation.
        phase = .finishing
        let state = snapshot()
        guard expected == ticket, phase == .finishing else { return .stale }
        if let failure = reason(state, identity: request.identity, version: request.writeVersion) { return reject(failure) }
        phase = .consumed; pending = nil
        let result = effects.pair(expected.generation, request.identity)
        guard expected == ticket, phase == .consumed else { return .stale }
        switch result {
        case .recorded: feedback = .pairRecorded; return .recordedPair
        case .requested: feedback = .pairRequested; return .requestedPair
        case .blocked(let failure): return reject(failure)
        }
    }
}
