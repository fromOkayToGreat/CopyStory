import AppKit
import Carbon
import CopyStoryCore

// No environment variable, preference, launch argument or permission can change
// these source-only barriers. Runtime work requires a separately reviewed patch.
enum NativeIntegrationGates {
    static let appLaunchEnabled = false
    static let platformAccessEnabled = false
    static let realPostingEnabled = false
}

@MainActor
struct NativePasteEnvironment {
    typealias Request = HistoryRequestSimulation
    let ownPID: Int32
    var capture: () -> Request.Snapshot?
    var snapshot: (_ captured: Request.Identity?, _ presented: Bool) -> Request.Snapshot
    var write: (HistoryRecordingSinks.Payload) -> Int?
    var activate: (Request.Identity) -> Bool
    var postPair: (Request.Identity, Int) -> Request.PairResult
    var observe: (@escaping @MainActor (HistoryRecordingObservation) -> Void) -> (() -> Void)
    var captureState: () -> HistoryRequestRecordingDependencies.CaptureState
    var wait: () async -> Void

    // Construction is inert. Each OS closure is independently hard-gated.
    static func system(writer: @escaping (HistoryRecordingSinks.Payload) -> Int?,
                       captureState: @escaping () -> HistoryRequestRecordingDependencies.CaptureState) -> Self {
        Self(ownPID: ProcessInfo.processInfo.processIdentifier,
            capture: {
                guard NativeIntegrationGates.platformAccessEnabled else { return nil }
                return NativePastePlatform.snapshot(captured: nil, presented: false)
            }, snapshot: { identity, presented in
                guard NativeIntegrationGates.platformAccessEnabled else {
                    return .init(now: .nan, frontmost: nil, destinationAlive: false, permission: .unknown)
                }
                return NativePastePlatform.snapshot(captured: identity, presented: presented)
            }, write: { payload in
                guard NativeIntegrationGates.platformAccessEnabled else { return nil }
                return writer(payload)
            }, activate: { identity in NativePastePlatform.activate(identity) },
            postPair: { NativePastePlatform.postPair($0, boardVersion: $1) },
            observe: { NativePastePlatform.observe($0) }, captureState: {
                guard NativeIntegrationGates.platformAccessEnabled else { return .init(isRecording: false) }
                return captureState()
            }, wait: { try? await Task.sleep(nanoseconds: 10_000_000) })
    }
}

@MainActor
private enum NativePastePlatform {
    typealias Request = HistoryRequestSimulation
    static func identity(_ app: NSRunningApplication?) -> Request.Identity? {
        guard let app, !app.isTerminated, let bundle = app.bundleIdentifier,
              let path = app.bundleURL?.standardizedFileURL.path,
              let launch = app.launchDate?.timeIntervalSince1970 else { return nil }
        return .init(pid: app.processIdentifier, bundleID: bundle, bundlePath: path, launchTime: launch)
    }
    static func permission() -> Request.Permission {
        guard NativeIntegrationGates.platformAccessEnabled else { return .unknown }
        // false is unavailable/undetermined, not proof of an explicit denial.
        return CGPreflightPostEventAccess() ? .available : .unknown
    }
    static func snapshot(captured: Request.Identity?, presented: Bool) -> Request.Snapshot {
        guard NativeIntegrationGates.platformAccessEnabled else {
            return .init(now: .nan, frontmost: nil, destinationAlive: false, permission: .unknown)
        }
        let front = identity(NSWorkspace.shared.frontmostApplication)
        let alive = captured.map { identity(NSRunningApplication(processIdentifier: $0.pid)) == $0 } ?? false
        let flags = CGEventSource.flagsState(.combinedSessionState)
        let held = flags.intersection([.maskCommand, .maskShift, .maskControl, .maskAlternate]).rawValue != 0
        return .init(now: ProcessInfo.processInfo.systemUptime, frontmost: front,
            destinationAlive: alive, permission: permission(), modifiersReleased: !held,
            boardVersion: NSPasteboard.general.changeCount, presentationOwnsFocus: presented)
    }
    static func activate(_ target: Request.Identity) -> Bool {
        guard NativeIntegrationGates.platformAccessEnabled,
              let app = NSRunningApplication(processIdentifier: target.pid), identity(app) == target else { return false }
        return app.activate(options: [])
    }
    static func postPair(_ target: Request.Identity, boardVersion: Int) -> Request.PairResult {
        // Barrier is before permission lookup, event creation and both posts.
        guard NativeIntegrationGates.realPostingEnabled,
              NativeIntegrationGates.platformAccessEnabled else { return .blocked(.deliveryDisabled) }
        guard permission() == .available else { return .blocked(.permissionUnknown) }
        guard identity(NSRunningApplication(processIdentifier: target.pid)) == target,
              identity(NSWorkspace.shared.frontmostApplication) == target else { return .blocked(.identityChanged) }
        guard let source = CGEventSource(stateID: .privateState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false) else {
            return .blocked(.eventCreationFailed)
        }
        down.flags = .maskCommand; up.flags = .maskCommand
        down.setIntegerValueField(.keyboardEventAutorepeat, value: 0)
        up.setIntegerValueField(.keyboardEventAutorepeat, value: 0)
        guard NSPasteboard.general.changeCount == boardVersion else { return .blocked(.boardChanged) }
        guard CGEventSource.flagsState(.combinedSessionState).intersection([.maskCommand, .maskShift, .maskControl, .maskAlternate]).rawValue == 0 else { return .blocked(.modifiersHeld) }
        // Fixed captured PID only, one balanced pair, no retarget/retry. Both
        // posting calls return Void: neither proves delivery or insertion.
        // OS preflight can be stale; this is NOT FRO22 revocation acceptance.
        down.postToPid(target.pid); up.postToPid(target.pid)
        return .requested
    }
    static func observe(_ handler: @escaping @MainActor (HistoryRecordingObservation) -> Void) -> (() -> Void) {
        guard NativeIntegrationGates.platformAccessEnabled else { return {} }
        let center = NSWorkspace.shared.notificationCenter
        let names: [(Notification.Name, @MainActor (Notification) -> HistoryRecordingObservation)] = [
            (NSWorkspace.didActivateApplicationNotification, { .activated(identity($0.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)) }),
            (NSWorkspace.didTerminateApplicationNotification, { note in
                // A terminated NSRunningApplication may fail the live identity
                // check. PID-only identity must not match an unrelated launch.
                guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                      let bundle = app.bundleIdentifier, let path = app.bundleURL?.standardizedFileURL.path,
                      let launch = app.launchDate?.timeIntervalSince1970 else { return .spaceChanged }
                return .terminated(.init(pid: app.processIdentifier, bundleID: bundle, bundlePath: path, launchTime: launch))
            }),
            (NSWorkspace.activeSpaceDidChangeNotification, { _ in .spaceChanged }),
            (NSWorkspace.willSleepNotification, { _ in .sleep })
        ]
        let tokens = names.map { name, value in
            center.addObserver(forName: name, object: nil, queue: .main) { note in
                MainActor.assumeIsolated { handler(value(note)) }
            }
        }
        return { tokens.forEach(center.removeObserver) }
    }
}

@MainActor
final class NativeRequestAdapter {
    typealias Request = HistoryRequestSimulation
    let environment: NativePasteEnvironment
    private var captured: Request.Identity?
    private var presented = false
    private var lastWriteVersion: Int?
    private var removeObservers: (() -> Void)?
    var onObservation: ((HistoryRecordingObservation, Request.Ticket) -> Void)?
    lazy var requests = Request(ownPID: environment.ownPID, effects: .init(
        write: { [weak self] payload, _ in
            guard let self else { return nil }
            let version = self.environment.write(payload); self.lastWriteVersion = version; return version
        }, pair: { [weak self] _, identity in
            guard let self, let version = self.lastWriteVersion else { return .blocked(.boardChanged) }
            return self.environment.postPair(identity, version)
        }),
        snapshot: { [weak self] in
            guard let self else { return .init(now: .nan, frontmost: nil, permission: .unknown) }
            return self.environment.snapshot(self.captured, self.presented)
        })
    init(environment: NativePasteEnvironment) { self.environment = environment }
    func capture() -> Request.Snapshot? {
        removeObservers?(); removeObservers = nil; presented = false; lastWriteVersion = nil
        let observation = environment.capture()
        captured = observation?.frontmost
        return observation
    }
    func invocationOpened(_ ticket: Request.Ticket) {
        guard ticket == requests.currentTicket else { return }
        removeObservers?()
        removeObservers = environment.observe { [weak self] observation in
            guard let self, ticket == self.requests.currentTicket else { return }
            // Activating CopyStory is expected ONLY while its captured menu or panel
            // owns presentation. Third-app activation stays sticky-cancelled.
            if case .activated(let identity) = observation,
               self.presented, identity?.pid == self.environment.ownPID { return }
            self.onObservation?(observation, ticket)
        }
    }
    func presentationOpened(_ ticket: Request.Ticket) {
        guard ticket == requests.currentTicket else { return }; presented = true
    }
    func presentationHidden(_ ticket: Request.Ticket) {
        guard ticket == requests.currentTicket else { return }; presented = false
    }
    func stop() { removeObservers?(); removeObservers = nil; presented = false }
    func beforeWrite(_ ticket: Request.Ticket) async -> Request.Reason? {
        for _ in 0..<75 {
            guard ticket == requests.currentTicket, !Task.isCancelled else { return .cancelled }
            if environment.snapshot(captured, presented).modifiersReleased { return nil }
            await environment.wait()
        }
        return .modifiersHeld
    }
    func restore(_ ticket: Request.Ticket) async -> Request.Reason? {
        guard ticket == requests.currentTicket, !Task.isCancelled, let captured else { return .cancelled }
        let initial = environment.snapshot(captured, presented)
        guard ticket == requests.currentTicket, !Task.isCancelled else { return .cancelled }
        guard initial.destinationAlive else { return .destinationUnavailable }
        guard initial.permission == .available else { return initial.permission == .denied ? .permissionDenied : .permissionUnknown }
        guard initial.boardVersion == lastWriteVersion else { return .boardChanged }
        guard initial.frontmost == captured || initial.frontmost?.pid == environment.ownPID else { return .identityChanged }
        guard environment.activate(captured) else { return .activationFailed }
        for _ in 0..<75 {
            guard ticket == requests.currentTicket, !Task.isCancelled else { return .cancelled }
            let value = environment.snapshot(captured, presented)
            if value.frontmost == captured && value.modifiersReleased { return nil }
            if value.frontmost != captured && value.frontmost?.pid != environment.ownPID { return .identityChanged }
            if !value.destinationAlive { return .destinationUnavailable }
            if value.permission != .available { return value.permission == .denied ? .permissionDenied : .permissionUnknown }
            await environment.wait()
        }
        return .activationFailed
    }
    var dependencies: HistoryRequestRecordingDependencies {
        .init(requests: requests, mode: .native,
            captureObservation: { [weak self] in self?.capture() ?? .init(now: .nan, frontmost: nil, permission: .unknown) },
            captureState: environment.captureState,
            beforeWrite: { [weak self] ticket in
                guard let self else { return .cancelled }; return await self.beforeWrite(ticket)
            },
            prepareDestination: { [weak self] ticket in
                guard let self else { return .cancelled }; return await self.restore(ticket)
            })
    }
}
