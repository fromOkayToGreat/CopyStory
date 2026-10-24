import AppKit
import SwiftUI
import CopyStoryCore
import UniformTypeIdentifiers

@MainActor
final class AppModel: ObservableObject {
    let store: HistoryStore
    let library: LibraryModel
    let defaults: UserDefaults
    let isDemo: Bool
    @Published var items: [HistoryItem] = []
    @Published var selectedID: String? {
        didSet { if selectedID != oldValue && !historyRequestIsLibrary { cancelHistoryRequest() } }
    }
    @Published var query = "" { didSet { scheduleRefresh(); library.query = query } }
    @Published var filter: HistoryFilter = .all { didSet { scheduleRefresh() } }
    @Published var count = 0
    @Published var pinnedCount = 0
    @Published var storageBytes: Int64 = 0
    @Published var capacityBlocked = false
    @Published var statusMessage: String?
    @Published var captureMessage: String?
    @Published var shortcutError: String?
    @Published var focusRequest = UUID()
    @Published var hasMore = false
    @Published var isSearching = false
    @Published var busy = false
    #if COPYSTORY_DEVELOPMENT
    @Published private(set) var readinessCheck = ReadinessCheck()
    private var readinessTimeout: Task<Void, Never>?
    private var readinessGeneration = UUID()
    private var readinessRefreshSequence: UInt64 = 0
    private var readinessLastRefresh = ProcessInfo.processInfo.systemUptime

    func checkReadiness() {
        readinessTimeout?.cancel()
        let generation = UUID()
        readinessGeneration = generation
        readinessCheck.begin(now: ProcessInfo.processInfo.systemUptime,
            lastRefresh: readinessLastRefresh, sequence: readinessRefreshSequence,
            displayed: accessibilityGranted, optIn: directPasteEnabled, read: ReadinessCheck.nativeSignals)
        readinessTimeout = Task { @MainActor [weak self] in
            do { try await Task.sleep(nanoseconds: 5_000_000_000) } catch { return }
            guard let self, self.readinessGeneration == generation else { return }
            self.readinessCheck.expire()
        }
    }

    func dismissReadinessCheck() {
        readinessGeneration = UUID()
        readinessTimeout?.cancel()
        readinessTimeout = nil
        readinessCheck.dismiss()
    }
    #endif
    @Published var accessibilityGranted = PasteCoordinator.accessibilityGranted
    @Published var loginStatus = "Login status is not queried in source-only integration."
    @Published var loginEnabled = false
    @Published var onboardingComplete: Bool
    @Published var paused: Bool { didSet { defaults.set(paused, forKey: "paused"); if historyRecording == nil && NativeIntegrationGates.clipboardEnabled { monitor.isPaused = paused } } }
    @Published var respectConfidential: Bool { didSet { defaults.set(respectConfidential, forKey: "respectConfidential"); if historyRecording == nil && NativeIntegrationGates.clipboardEnabled { monitor.respectConfidential = respectConfidential } } }
    @Published var maxItems: Int { didSet { defaults.set(maxItems, forKey: "maxItems") } }
    @Published var maxMB: Int { didSet { defaults.set(maxMB, forKey: "maxMB") } }
    @Published private(set) var retentionDays: Int
    @Published private(set) var excludedAppBundleIDs: [String]
    @Published var shortcutCode: UInt32
    @Published var shortcutModifiers: UInt32
    @Published var shortcutLabel: String
    @Published var shortcutEnabled: Bool
    @Published var directPasteEnabled: Bool
    @Published var registeringShortcut = false
    @Published var isLocked = false
    private var refreshTask: Task<Void, Never>?
    private var feedbackTask: Task<Void, Never>?
    private var requestVersion = 0
    private var pageLimit = 100
    private var selectionGeneration = 0
    private var historyRecordingStopped = false
    private var historyRequestIsLibrary = false
    private var historyPasteOwner: UUID?
    private var historyRecordingTicket: HistoryRequestSimulation.Ticket?
    private(set) var historyPasteTask: Task<Void, Never>?
    private let recordingStarter: (@MainActor () -> Void)?
    private let usesInjectedNative: Bool
    private var requestDependencies: HistoryRequestRecordingDependencies { historyRecording ?? pasteCoordinator.dependencies }
    private let historyRecording: HistoryRequestRecordingDependencies?
    // Capture admission and clear requests share invocation order, including
    // work that has not reached the storage actor yet.
    private var captureMutation: Task<Void, Never>?
    private var isTerminating = false
    private var lastRetentionSweep = Date.distantPast
    private var stateTimer: Timer?
    var togglePanel: (() -> Void)?
    var hideLibraryAfterRecordedWrite: ((HistoryRequestSimulation.Ticket) -> Void)?
    var closePanel: (() -> Void)?
    var openPreferences: (() -> Void)?
    var inspectItem: ((HistoryItem) -> Void)?
    lazy var monitor = ClipboardMonitor(onCapture: { [weak self] payload in self?.save(payload) }, onStatus: { [weak self] message in self?.captureMessage = message })
    lazy var hotkey = GlobalHotKey(onTrigger: { [weak self] in self?.togglePanel?() })
    let pasteCoordinator: PasteCoordinator

    var limits: HistoryLimits { HistoryLimits(maxItems: maxItems, maxBytes: Int64(maxMB) * 1_000_000) }
    var selectedItem: HistoryItem? { items.first { $0.id == selectedID } }
    var recordingLabel: String {
        if isDemo { return "Preview mode · sample history" }
        if !onboardingComplete { return "Ready when you are" }
        if isLocked { return "Paused while Mac is locked" }
        if paused { return "Recording paused" }
        if captureMessage != nil { return "Recording needs attention" }
        if capacityBlocked { return "Storage full · pinned items protected" }
        return "Recording"
    }
    var storageLabel: String { ByteCountFormatter.string(fromByteCount: storageBytes, countStyle: .decimal) }
    var storageDirectory: URL { store.directory }
    static let retentionOptions = [0, 1, 7, 30, 90]

    init(store: HistoryStore, demo: Bool, preferenceStore: UserDefaults? = nil,
         historyRecording: HistoryRequestRecordingDependencies? = nil,
         nativeEnvironment: NativePasteEnvironment? = nil,
         developmentDefaults: Bool = DevelopmentConfiguration.enabled,
         recordingStarter: (@MainActor () -> Void)? = nil) {
        self.recordingStarter = recordingStarter
        self.historyRecording = historyRecording
        usesInjectedNative = nativeEnvironment != nil
        pasteCoordinator = PasteCoordinator(environment: nativeEnvironment)
        self.store = store
        library = LibraryModel(directory: store.directory.appendingPathComponent("Library", isDirectory: true))
        isDemo = demo
        defaults = preferenceStore ?? (demo ? UserDefaults(suiteName: "com.copystory.preview")! : .standard)
        defaults.register(defaults: DevelopmentConfiguration.preferenceDefaults(development: developmentDefaults))
        onboardingComplete = demo || defaults.bool(forKey: "onboardingComplete")
        paused = defaults.bool(forKey: "paused")
        shortcutEnabled = defaults.bool(forKey: "shortcutEnabled")
        directPasteEnabled = defaults.bool(forKey: "directPasteEnabled")
        respectConfidential = defaults.bool(forKey: "respectConfidential")
        maxItems = max(1, defaults.integer(forKey: "maxItems"))
        maxMB = max(10, defaults.integer(forKey: "maxMB"))
        let savedRetention = defaults.integer(forKey: "retentionDays")
        retentionDays = Self.retentionOptions.contains(savedRetention) ? savedRetention : 0
        excludedAppBundleIDs = defaults.stringArray(forKey: "excludedAppBundleIDs") ?? ["com.apple.Passwords"]
        shortcutCode = UInt32(defaults.integer(forKey: "shortcutCode"))
        shortcutModifiers = UInt32(defaults.integer(forKey: "shortcutModifiers"))
        shortcutLabel = defaults.string(forKey: "shortcutLabel") ?? "⇧⌘H"
        library.onUseChange = { [weak self] in
            guard let self, self.historyPasteOwner != nil else { return }
            self.cancelPendingSelection()
        }
        pasteCoordinator.recordingCapture = { [weak self] in self?.captureHistoryRecordingInvocation() }
        if historyRecording == nil {
            pasteCoordinator.nativeWriter = { [weak self] value in
                guard NativeIntegrationGates.clipboardEnabled, let self else { return nil }
                let payload: CapturePayload
                switch value {
                case .text(let text): payload = CapturePayload(text: text)
                case .image(let bytes): payload = CapturePayload(imageData: Data(bytes))
                case .textAndImage(let text, let bytes): payload = CapturePayload(text: text, imageData: Data(bytes))
                }
                do { try self.monitor.write(payload); return self.monitor.ownWriteVersion }
                catch { return nil }
            }
            pasteCoordinator.nativeCaptureState = { [weak self] in
                guard NativeIntegrationGates.clipboardEnabled, let self else { return .init(isRecording: false) }
                return .init(isRecording: self.monitor.isRecording, isLocked: self.monitor.isLocked)
            }
            pasteCoordinator.nativeAdapter.onObservation = { [weak self] event, ticket in
                self?.historyRecordingObserved(event, ticket: ticket)
            }
        }
    }

    func start() {
        guard historyRecording == nil, NativeIntegrationGates.storageEnabled else { return }
        library.scheduleSearch()
        guard !isTerminating else { return }
        refreshLoginStatus()
        registerHotkey()
        expireHistory()
        if !isDemo && onboardingComplete { startRecording() }
        enqueueHistoryMutation { [self] in
            do { capacityBlocked = try await store.enforceLimits(limits) }
            catch { showFeedback("Couldn’t apply history limits. Check your storage folder.") }
            await refresh()
        }
        stateTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.refreshPostingReadiness(fromTimer: true)
                self.refreshLoginStatus()
                self.isLocked = self.monitor.isLocked
                if self.retentionDays > 0, Date().timeIntervalSince(self.lastRetentionSweep) >= 60 {
                    self.expireHistory()
                }
            }
        }
    }

    // Used at both existing display refresh sites: opening Preferences and the
    // two-second timer. Only the timer may complete a diagnostic pair.
    func refreshPostingReadiness(fromTimer: Bool = false) {
        accessibilityGranted = PasteCoordinator.accessibilityGranted
        #if COPYSTORY_DEVELOPMENT
        readinessRefreshSequence &+= 1
        readinessLastRefresh = ProcessInfo.processInfo.systemUptime
        if fromTimer {
            readinessCheck.refreshed(now: readinessLastRefresh,
                sequence: readinessRefreshSequence, displayed: accessibilityGranted,
                optIn: directPasteEnabled, read: ReadinessCheck.nativeSignals)
        } else {
            // An intervening UI-open refresh invalidates the expected next tick.
            readinessCheck.expire()
        }
        if readinessCheck.status != .waiting {
            readinessTimeout?.cancel()
            readinessTimeout = nil
        }
        #endif
    }

    func startRecording() {
        guard historyRecording == nil, onboardingComplete, !isDemo, !isTerminating else { return }
        // Offline injection replaces only the recording effect, after the same
        // consent/lifecycle guard. Ordinary startup always uses the native gate.
        if let recordingStarter { recordingStarter(); return }
        guard NativeIntegrationGates.clipboardEnabled else { return }
        monitor.isPaused = paused
        monitor.respectConfidential = respectConfidential
        monitor.excludedBundleIDs = Set(excludedAppBundleIDs)
        monitor.start()
    }

    func finishOnboarding(launchAtLogin: Bool, loginWasChanged: Bool = false) {
        onboardingComplete = true
        defaults.set(true, forKey: "onboardingComplete")
        if !isDemo {
            startRecording()
            if let choice = OnboardingDefaults.registrationChange(selected: launchAtLogin, wasChanged: loginWasChanged) {
                setLogin(choice)
            }
        }
        togglePanel?()
    }

    func registerHotkey() {
        guard historyRecording == nil, NativeIntegrationGates.shortcutEnabled, shortcutEnabled else { return }
        guard !(AppDistribution.isAppStore && isDemo) else { return }
        do { try hotkey.register(keyCode: shortcutCode, modifiers: shortcutModifiers); shortcutError = nil }
        catch { shortcutError = "Couldn’t register \(shortcutLabel). Another app may use it. Choose a different shortcut in preferences." }
    }

    func setShortcutEnabled(_ enabled: Bool) {
        guard NativeIntegrationGates.shortcutEnabled, historyRecording == nil, !isDemo else { return }
        shortcutEnabled = enabled
        defaults.set(enabled, forKey: "shortcutEnabled")
        if enabled { registerHotkey() } else { hotkey.unregister(); shortcutError = nil }
    }

    func setDirectPasteEnabled(_ enabled: Bool) {
        cancelPendingSelection()
        directPasteEnabled = enabled
        defaults.set(enabled, forKey: "directPasteEnabled")
    }

    private func refreshLoginStatus() {
        guard NativeIntegrationGates.loginEnabled else { return }
        loginStatus = LoginService.statusText
        loginEnabled = LoginService.isRegistered
    }

    func changeShortcut(code: UInt32, modifiers: UInt32, label: String) {
        guard NativeIntegrationGates.shortcutEnabled, historyRecording == nil else { return }
        guard !(AppDistribution.isAppStore && isDemo) else { return }
        do {
            if shortcutEnabled { try hotkey.register(keyCode: code, modifiers: modifiers) }
            shortcutCode = code; shortcutModifiers = modifiers; shortcutLabel = label
            defaults.set(Int(code), forKey: "shortcutCode")
            defaults.set(Int(modifiers), forKey: "shortcutModifiers")
            defaults.set(label, forKey: "shortcutLabel")
            shortcutError = nil
        } catch {
            shortcutError = "That shortcut is unavailable. Your previous shortcut is still selected. Try another combination."
        }
        registeringShortcut = false
    }

    func setLogin(_ enabled: Bool) {
        guard !isDemo else { showFeedback("Login registration is disabled in preview mode."); return }
        guard NativeIntegrationGates.loginEnabled else { return }
        do { try LoginService.setEnabled(enabled) }
        catch { showFeedback("macOS couldn’t update launch at login. Check Login Items in System Settings.") }
        refreshLoginStatus()
    }

    @discardableResult
    func save(_ payload: CapturePayload, fromLibrary: Bool = false, feedbackOwner: UUID? = nil) -> Task<Void, Never> {
        guard !isTerminating else { return Task {} }
        let previous = captureMutation
        let task = Task {
            await previous?.value
            @MainActor func feedback(_ message: String) {
                if feedbackOwner == nil || historyPasteOwner == feedbackOwner {
                    let text = historyRecording != nil && fromLibrary ?
                        message.replacingOccurrences(of: "Copied, but", with: "Simulated write recorded, but") : message
                    showFeedback(text)
                }
            }
            do {
                if let source = payload.sourceBundleID, excludedAppBundleIDs.contains(source) { return }
                if let cutoff = expirationCutoff(now: Date()) {
                    let removed = try await store.expireUnpinned(before: cutoff)
                    if removed > 0 { requestVersion += 1; cancelPendingSelection() }
                    if payload.capturedAt < cutoff { await refresh(historyOwner: feedbackOwner); return }
                }
                let outcome = try await store.capture(payload, limits: limits)
                switch outcome {
                case .saved, .duplicate: capacityBlocked = false
                case .oversized: feedback("This item is too large to save. Existing history was kept.")
                case .pinnedCapacity:
                    capacityBlocked = true
                    if fromLibrary { feedback("Copied, but history is full. Unpin items or increase its storage limit.") }
                }
                await refresh(historyOwner: feedbackOwner)
            } catch { feedback(fromLibrary ? "Copied, but this completed prompt could not be saved to history." : "Couldn’t save this clipboard item. Your existing history is still available.") }
        }
        captureMutation = task
        return task
    }

    func scheduleRefresh() {
        cancelHistoryRequest()
        isSearching = true
        pageLimit = 100
        requestVersion += 1
        refreshTask?.cancel()
        refreshTask = Task {
            try? await Task.sleep(nanoseconds: 60_000_000)
            guard !Task.isCancelled else { return }
            await refresh()
        }
    }

    func refresh(historyOwner: UUID? = nil) async {
        if let historyOwner, historyPasteOwner != historyOwner || Task.isCancelled { return }
        let version = requestVersion
        let q = query, f = filter, n = pageLimit
        do {
            var result: [HistoryItem] = []
            while result.count < n + 1 {
                let batchSize = min(1000, n + 1 - result.count)
                let batch = try await store.search(query: q, filter: f, limit: batchSize, offset: result.count)
                result.append(contentsOf: batch)
                if batch.count < batchSize { break }
            }
            let stats = try await store.stats()
            guard version == requestVersion, q == query, f == filter else { return }
            if let historyOwner, historyPasteOwner != historyOwner || Task.isCancelled { return }
            items = Array(result.prefix(n))
            isSearching = false
            hasMore = result.count > n
            if !items.contains(where: { $0.id == selectedID }) { selectedID = items.first?.id }
            count = stats.count; pinnedCount = stats.pinnedCount; storageBytes = stats.totalBytes
            capacityBlocked = stats.pinnedCount >= maxItems || capacityBlocked
            if stats.pinnedCount == 0 { capacityBlocked = false }
        } catch {
            if let historyOwner, historyPasteOwner != historyOwner || Task.isCancelled { return }
            showFeedback("History couldn’t be read. Reopen CopyStory or check the local storage folder.")
        }
    }

    func loadMore() { pageLimit += 100; Task { await refresh() } }
    func moveSelection(_ delta: Int) {
        guard !items.isEmpty else { return }
        let current = items.firstIndex { $0.id == selectedID } ?? 0
        let next = max(0, min(items.count - 1, current + delta))
        selectedID = items[next].id
        if next >= items.count - 3 && hasMore { loadMore() }
    }

    func select(_ item: HistoryItem) { selectedID = item.id }
    func pasteSelected() { guard !isSearching, let item = selectedItem else { return }; paste(item) }
    var historyDiagnostics = HistoryPresentationDiagnostics()
    var canRecordHistoryInvocation: Bool { !historyRecordingStopped && !isTerminating }
    func canPresentInvocation(_ ticket: HistoryRequestSimulation.Ticket) -> Bool {
        canRecordHistoryInvocation && ticket == requestDependencies.requests.currentTicket &&
            !requestDependencies.requests.isCancelled
    }
    var recordingInvocationTicket: HistoryRequestSimulation.Ticket? { requestDependencies.requests.currentTicket }
    private func captureHistoryRecordingInvocation() {
        guard canRecordHistoryInvocation else { return }
        let recording = requestDependencies
        cancelHistoryRequest()
        let previousTicket = recording.requests.currentTicket
        let observation = recording.captureObservation?()
        guard canRecordHistoryInvocation, previousTicket == recording.requests.currentTicket else { return }
        // Missing injected observation fails closed; never read live focus/clock.
        let ticket = recording.requests.open(identity: observation?.frontmost, now: observation?.now ?? .nan)
        if recording.mode == .native { pasteCoordinator.nativeAdapter.invocationOpened(ticket) }
    }
    func historyRecordingDismissed(ticket: HistoryRequestSimulation.Ticket?) {
        let recording = requestDependencies
        guard let ticket, ticket == recording.requests.currentTicket else { return }
        historyDiagnostics.emit(.requestDismissed, .explicitClose, ticketMatches: true, requestGeneration: ticket.generation)
        recording.requests.cancel(.explicit, ticket: ticket)
        cancelPendingSelection()
    }
    func historyRecordingObserved(_ observation: HistoryRecordingObservation,
                                  ticket: HistoryRequestSimulation.Ticket) {
        let recording = requestDependencies
        guard ticket == recording.requests.currentTicket else {
            historyDiagnostics.emit(.requestObservation, .ticketMismatch, ticketMatches: false, requestGeneration: ticket.generation); return
        }
        let reason: HistoryPresentationDiagnostics.Reason
        switch observation {
        case .activated: reason = .activated
        case .spaceChanged: reason = .spaceChanged
        case .terminated: reason = .terminated
        case .sleep: reason = .sleep
        case .stopped: reason = .stopped
        }
        historyDiagnostics.emit(.requestObservation, reason, ticketMatches: true, requestGeneration: ticket.generation)
        switch observation {
        case .activated(let identity): recording.requests.applicationActivated(identity, ticket: ticket)
        case .spaceChanged: recording.requests.cancel(.space, ticket: ticket)
        case .terminated(let identity): recording.requests.targetTerminated(identity, ticket: ticket)
        case .sleep: recording.requests.cancel(.sleep, ticket: ticket)
        case .stopped: stop(); return
        }
        historyDiagnostics.emit(.requestObservation, reason, ticketMatches: true, valid: !recording.requests.isCancelled, requestGeneration: ticket.generation)
        if recording.requests.feedback == .blocked(.cancelled) { cancelHistoryRequest() }
    }
    func cancelPendingSelection() {
        selectionGeneration += 1
        cancelHistoryRequest()
    }
    private func cancelHistoryRequest() {
        guard historyPasteOwner != nil else { return }
        if let ticket = historyRecordingTicket {
            requestDependencies.requests.cancel(.explicit, ticket: ticket)
        }
        historyPasteTask?.cancel()
        historyPasteTask = nil; historyPasteOwner = nil; historyRecordingTicket = nil
        historyRequestIsLibrary = false
        busy = false
    }
    private func allowDirectPaste() -> Bool {
        // Only the explicitly labeled recording-policy harness bypasses this
        // product preference. Injected native effects obey it like the real app.
        guard historyRecording == nil else { return true }
        guard directPasteEnabled else {
            showFeedback("Direct Paste is off. Enable experimental Direct Paste in Preferences, or choose Copy.")
            return false
        }
        return true
    }
    func paste(_ item: HistoryItem) { requestHistory(item, copyOnly: false) }
    private func requestHistory(_ item: HistoryItem, copyOnly: Bool) {
        guard !busy, !isSearching, !isTerminating, !historyRecordingStopped else { return }
        guard copyOnly || allowDirectPaste() else { return }
        let generation = selectionGeneration
        let owner = UUID()
        let recordingTicket: HistoryRequestSimulation.Ticket? = requestDependencies.requests.currentTicket
        historyRequestIsLibrary = false
        historyPasteOwner = owner; historyRecordingTicket = recordingTicket
        busy = true
        historyPasteTask = Task {
            defer {
                // A cancelled payload lookup may complete after a new action.
                // It cannot release that action's busy flag or feedback owner.
                if historyPasteOwner == owner {
                    historyPasteOwner = nil; historyRecordingTicket = nil
                    historyPasteTask = nil; busy = false
                }
            }
            @MainActor func current() -> Bool {
                historyPasteOwner == owner && generation == selectionGeneration &&
                    !Task.isCancelled && !isTerminating
            }
            do {
                let payload: CapturePayload
                if let loader = requestDependencies.loadPayload { payload = try await loader(item.id) }
                else { payload = try await store.payload(id: item.id) }
                guard current() else { return }
                if isDemo && historyRecording == nil && !usesInjectedNative {
                    showFeedback(copyOnly ? "Preview mode: clipboard writes are disabled." : "Preview mode: pasting is disabled. Open CopyStory normally to use your clipboard."); return
                }
                if let ticket = recordingTicket {
                    let recording = requestDependencies
                    guard ticket == recording.requests.currentTicket else { return }
                    let value: HistoryRecordingSinks.Payload
                    if let data = payload.imageData, let text = payload.text { value = .textAndImage(text, Array(data)) }
                    else if let data = payload.imageData { value = .image(Array(data)) }
                    else if let text = payload.text { value = .text(text) }
                    else {
                        recording.requests.cancel(.explicit, ticket: ticket)
                        showFeedback(recording.mode == .recording ? "Simulation blocked: stored payload is unavailable. Nothing was sent." : "Stored payload is unavailable. Nothing was copied or sent."); return
                    }
                    // Replaying an existing History item must never admit a new
                    // History entry. This remains the same reviewed policy;
                    // only its explicit replay admission context differs.
                    if !copyOnly, let failure = await recording.beforeWrite?(ticket) {
                        guard current(), ticket == recording.requests.currentTicket else { return }
                        _ = recording.requests.abort(failure, ticket: ticket)
                        showFeedback(recording.feedback(.blocked(failure))); return
                    }
                    guard current(), ticket == recording.requests.currentTicket else { return }
                    let outcome = recording.requests.handle(copyOnly ? .copy : .paste, payload: value, admission: .existingHistoryReplay)
                    guard current(), ticket == recording.requests.currentTicket else { return }
                    if case .pending(let pending) = outcome {
                        recording.onSuccessfulWrite(payload)
                        guard current(), ticket == recording.requests.currentTicket else { return }
                        if recording.mode == .native { hideLibraryAfterRecordedWrite?(ticket) }
                        guard current(), ticket == recording.requests.currentTicket else { return }
                        await recording.beforeFinish()
                        guard current(), ticket == recording.requests.currentTicket else { return }
                        if let failure = await recording.prepareDestination?(ticket) {
                            guard current(), ticket == recording.requests.currentTicket else { return }
                            _ = recording.requests.abort(failure, ticket: ticket)
                            showFeedback(recording.feedback(.blocked(failure), wrote: true)); return
                        }
                        guard current(), ticket == recording.requests.currentTicket else { return }
                        let completion = recording.requests.finish(pending)
                        guard current(), ticket == recording.requests.currentTicket, completion != .stale else { return }
                        if case .rejected(let reason) = completion {
                            showFeedback(recording.feedback(.blocked(reason), wrote: true))
                        } else { showFeedback(recording.feedback(recording.requests.feedback, wrote: true)) }
                    } else if outcome == .recordedCopy {
                        recording.onSuccessfulWrite(payload)
                        guard current(), ticket == recording.requests.currentTicket else { return }
                        showFeedback(recording.feedback(recording.requests.feedback, wrote: true))
                    } else if case .rejected(let reason) = outcome {
                        showFeedback(recording.feedback(.blocked(reason)))
                    }
                    return
                }
            } catch {
                guard current() else { return }
                if let ticket = recordingTicket {
                    let recording = requestDependencies
                    guard ticket == recording.requests.currentTicket else { return }
                    recording.requests.cancel(.explicit, ticket: ticket)
                }
                showFeedback(historyRecording == nil ? "This item is unavailable. It may have been removed or damaged." :
                    "Simulation blocked: stored payload is unavailable. Nothing was sent.")
                await refresh(historyOwner: owner)
            }
        }
    }

    func copySelected() {
        guard let item = selectedItem else { return }
        requestHistory(item, copyOnly: true)
    }

    func requestPresentationOpened(_ ticket: HistoryRequestSimulation.Ticket) {
        if requestDependencies.mode == .native { pasteCoordinator.nativeAdapter.presentationOpened(ticket) }
    }
    func requestPresentationHidden(_ ticket: HistoryRequestSimulation.Ticket) {
        if requestDependencies.mode == .native { pasteCoordinator.nativeAdapter.presentationHidden(ticket) }
    }

    func selectSection(_ section: PanelSection) {
        cancelPendingSelection()
        library.section = section
        focusRequest = UUID()
    }

    func saveToLibrary(_ item: HistoryItem) {
        guard !busy, !isSearching else { return }
        let generation = selectionGeneration
        busy = true
        Task {
            defer { busy = false }
            do {
                let text = try await store.fullText(id: item.id)
                guard generation == selectionGeneration, !Task.isCancelled else { return }
                guard let text, !text.isEmpty else { showFeedback("This item has no text to save."); return }
                library.edit(text: text)
            } catch { showFeedback("This history item is no longer available.") }
        }
    }

    /// Admit synchronously at the successful clipboard write, before paste can suspend.
    /// This preserves save/clear ordering without enabling monitor self-capture.
    @discardableResult
    func recordCompletedPrompt(_ payload: CapturePayload, feedbackOwner: UUID? = nil) -> Task<Void, Never>? {
        guard !isDemo, !isTerminating, onboardingComplete, !paused, !isLocked else { return nil }
        let state = requestDependencies.captureState()
        guard !historyRecordingStopped, state.isRecording, !state.isLocked else { return nil }
        return save(payload, fromLibrary: true, feedbackOwner: feedbackOwner)
    }

    @discardableResult
    func handleLibraryCommandReturn() -> Bool {
        guard library.section == .library, library.screen == .use else { return false }
        usePrompt(copyOnly: false)
        return true
    }

    func usePrompt(copyOnly: Bool) {
        guard !busy, !isTerminating, !historyRecordingStopped, case .success(let text) = library.rendered else { return }
        if isDemo && historyRecording == nil && !usesInjectedNative {
            showFeedback("Preview mode: clipboard writes are disabled."); return
        }
        guard copyOnly || allowDirectPaste() else { return }
        useRecordedPrompt(text: text, copyOnly: copyOnly, recording: requestDependencies)
    }

    // Uses the same request owner/task and reviewed recording policy as History.
    // The rendered value is frozen synchronously before any reset or suspension.
    private func useRecordedPrompt(text: String, copyOnly: Bool,
                                   recording: HistoryRequestRecordingDependencies) {
        let payload = CapturePayload(text: text, sourceApp: "CopyStory",
            sourceBundleID: Bundle.main.bundleIdentifier ?? "app.copystory")
        let owner = UUID(), generation = selectionGeneration
        let ticket = recording.requests.currentTicket
        historyRequestIsLibrary = true
        historyPasteOwner = owner; historyRecordingTicket = ticket
        busy = true; statusMessage = nil
        historyPasteTask = Task {
            defer {
                if historyPasteOwner == owner {
                    historyPasteOwner = nil; historyRecordingTicket = nil
                    historyPasteTask = nil; historyRequestIsLibrary = false; busy = false
                }
            }
            @MainActor func current() -> Bool {
                historyPasteOwner == owner && generation == selectionGeneration &&
                    ticket == recording.requests.currentTicket && !Task.isCancelled && !isTerminating
            }
            guard current() else { return }
            if !copyOnly, let failure = await recording.beforeWrite?(ticket) {
                guard current() else { return }
                _ = recording.requests.abort(failure, ticket: ticket)
                showFeedback(recording.feedback(.blocked(failure))); return
            }
            guard current() else { return }
            let outcome = recording.requests.handle(copyOnly ? .copy : .paste, payload: .text(text))
            guard current() else { return }
            let wrote: Bool
            switch outcome { case .recordedCopy, .pending: wrote = true; default: wrote = false }
            guard wrote else {
                if case .rejected(let reason) = outcome {
                    showFeedback(recording.feedback(.blocked(reason)))
                }
                return
            }
            // Admission is queued synchronously BEFORE observer/dismissal/await.
            // Already accepted storage writes survive later request cancellation.
            let admission = recordCompletedPrompt(payload, feedbackOwner: owner)
            guard current() else { await admission?.value; return }
            recording.onSuccessfulWrite(payload)
            guard current() else { await admission?.value; return }
            if case .pending(let pending) = outcome {
                library.resetScreen(preservingRequest: true)
                hideLibraryAfterRecordedWrite?(ticket)
                guard current() else { await admission?.value; return }
                await recording.beforeFinish()
                guard current() else { await admission?.value; return }
                if let failure = await recording.prepareDestination?(ticket) {
                    guard current() else { await admission?.value; return }
                    _ = recording.requests.abort(failure, ticket: ticket)
                    if admission == nil || statusMessage == nil { showFeedback(recording.feedback(.blocked(failure), wrote: true)) }
                    await admission?.value; return
                }
                guard current() else { await admission?.value; return }
                let completion = recording.requests.finish(pending)
                guard current(), completion != .stale else { await admission?.value; return }
                // Storage failure may have arrived during the final wait.
                // Preserve its existing feedback priority, as the live form
                // path does, rather than replacing it with simulated intent.
                if admission == nil || statusMessage == nil {
                    if case .rejected(let reason) = completion {
                        showFeedback(recording.feedback(.blocked(reason), wrote: true))
                    } else { showFeedback(recording.feedback(recording.requests.feedback, wrote: true)) }
                }
            } else if admission == nil || statusMessage == nil {
                showFeedback(recording.feedback(recording.requests.feedback, wrote: true))
            }
            await admission?.value
        }
    }

    func togglePin(_ item: HistoryItem) {
        enqueueHistoryMutation { [self] in
            do { try await store.setPinned(id: item.id, pinned: !item.isPinned); capacityBlocked = try await store.enforceLimits(limits); await refresh() }
            catch { showFeedback("Couldn’t update this pin.") }
        }
    }
    func delete(_ item: HistoryItem) {
        enqueueHistoryMutation { [self] in
            do { try await store.delete(id: item.id); capacityBlocked = try await store.enforceLimits(limits); await refresh() }
            catch { showFeedback("Couldn’t delete this item.") }
        }
    }
    @discardableResult
    func clear(includePinned: Bool) -> Task<Void, Never> {
        guard !isTerminating else { return Task {} }
        // Reject decoders started before this request and baseline unpolled
        // clipboard content. Already admitted saves finish before deletion;
        // later saves wait for it, even if the storage actor is busy.
        if historyRecording == nil && NativeIntegrationGates.clipboardEnabled { monitor.discardPendingCapture() }
        let previous = captureMutation
        let task = Task {
            await previous?.value
            do {
                try await store.clear(includePinned: includePinned)
                requestVersion += 1 // Reject refresh snapshots taken before deletion.
                capacityBlocked = false
                await refresh()
                showFeedback(includePinned ? "All history cleared." : "Unpinned history cleared.")
            }
            catch { showFeedback("Couldn’t clear history.") }
        }
        captureMutation = task
        return task
    }
    func applyLimits(items: Int, megabytes: Int) {
        guard !isTerminating else { return }
        maxItems = max(1, min(items, 100_000))
        maxMB = max(10, min(megabytes, 50_000))
        enqueueHistoryMutation { [self] in
            do { capacityBlocked = try await store.enforceLimits(limits); await refresh(); showFeedback("History limits updated.") }
            catch { showFeedback("Couldn’t apply the new limits.") }
        }
    }

    private func expirationCutoff(now: Date) -> Date? {
        retentionDays > 0 ? now.addingTimeInterval(-Double(retentionDays) * 86_400) : nil
    }

    @discardableResult
    func expireHistory(now: Date = Date()) -> Task<Void, Never> {
        guard !isTerminating else { return Task {} }
        lastRetentionSweep = now
        let previous = captureMutation
        let task = Task {
            await previous?.value
            guard let cutoff = expirationCutoff(now: now) else { return }
            do {
                if try await store.expireUnpinned(before: cutoff) > 0 {
                    requestVersion += 1
                    cancelPendingSelection()
                    await refresh()
                }
            } catch { showFeedback("Couldn’t remove expired history. Check the storage folder.") }
        }
        captureMutation = task
        return task
    }

    func applyRetention(days: Int) {
        guard Self.retentionOptions.contains(days) else { return }
        retentionDays = days
        defaults.set(days, forKey: "retentionDays")
        expireHistory()
    }

    func setExcludedApps(_ bundleIDs: [String]) {
        excludedAppBundleIDs = Array(Set(bundleIDs.filter { !$0.isEmpty && $0.utf8.count <= 256 })).sorted()
        defaults.set(excludedAppBundleIDs, forKey: "excludedAppBundleIDs")
        if historyRecording == nil && NativeIntegrationGates.clipboardEnabled { monitor.excludedBundleIDs = Set(excludedAppBundleIDs) }
    }

    func chooseExcludedApps() {
        let picker = NSOpenPanel()
        picker.title = "Exclude apps from clipboard history"
        picker.prompt = "Exclude"
        picker.allowedContentTypes = [.applicationBundle]
        picker.allowsMultipleSelection = true
        picker.canChooseDirectories = false
        picker.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        picker.begin { [weak self] result in
            guard result == .OK, let self else { return }
            self.setExcludedApps(self.excludedAppBundleIDs + picker.urls.compactMap { Bundle(url: $0)?.bundleIdentifier })
        }
    }

    func excludedAppName(_ bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return bundleID }
        return FileManager.default.displayName(atPath: url.path)
    }
    func showFeedback(_ text: String) {
        statusMessage = text
        feedbackTask?.cancel()
        feedbackTask = Task {
            try? await Task.sleep(nanoseconds: 7_000_000_000)
            if !Task.isCancelled { statusMessage = nil }
        }
    }

    /// Stop admission synchronously, then let all accepted storage changes finish
    /// in their existing order before quitting or an updater relaunch.
    func prepareForTermination() -> Task<Void, Never> {
        isTerminating = true
        stop()
        cancelPendingSelection()
        refreshTask?.cancel()
        let pending = captureMutation
        let libraryDrain = library.prepareForTermination()
        return Task { await pending?.value; await libraryDrain.value }
    }

    @discardableResult
    private func enqueueHistoryMutation(_ operation: @escaping @MainActor () async -> Void) -> Task<Void, Never> {
        guard !isTerminating else { return Task {} }
        let previous = captureMutation
        let task = Task { await previous?.value; await operation() }
        captureMutation = task
        return task
    }

    func stop() {
        #if COPYSTORY_DEVELOPMENT
        dismissReadinessCheck()
        #endif
        historyRecordingStopped = true
        requestDependencies.requests.cancel(.explicit, ticket: requestDependencies.requests.currentTicket)
        cancelHistoryRequest()
        if historyRecording == nil { pasteCoordinator.nativeAdapter.stop() }
        guard historyRecording == nil, NativeIntegrationGates.clipboardEnabled else { return }
        monitor.stop(); hotkey.unregister(); stateTimer?.invalidate()
    }
}
