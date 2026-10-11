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
    @Published var selectedID: String?
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
    @Published var accessibilityGranted = PasteCoordinator.accessibilityGranted
    @Published var loginStatus = LoginService.statusText
    @Published var loginEnabled = LoginService.isRegistered
    @Published var onboardingComplete: Bool
    @Published var paused: Bool { didSet { defaults.set(paused, forKey: "paused"); monitor.isPaused = paused } }
    @Published var respectConfidential: Bool { didSet { defaults.set(respectConfidential, forKey: "respectConfidential"); monitor.respectConfidential = respectConfidential } }
    @Published var maxItems: Int { didSet { defaults.set(maxItems, forKey: "maxItems") } }
    @Published var maxMB: Int { didSet { defaults.set(maxMB, forKey: "maxMB") } }
    @Published private(set) var retentionDays: Int
    @Published private(set) var excludedAppBundleIDs: [String]
    @Published var shortcutCode: UInt32
    @Published var shortcutModifiers: UInt32
    @Published var shortcutLabel: String
    @Published var registeringShortcut = false
    @Published var isLocked = false
    private var refreshTask: Task<Void, Never>?
    private var feedbackTask: Task<Void, Never>?
    private var requestVersion = 0
    private var pageLimit = 100
    private var selectionGeneration = 0
    // Capture admission and clear requests share invocation order, including
    // work that has not reached the storage actor yet.
    private var captureMutation: Task<Void, Never>?
    private var isTerminating = false
    private var lastRetentionSweep = Date.distantPast
    private var stateTimer: Timer?
    var togglePanel: (() -> Void)?
    var closePanel: (() -> Void)?
    var openPreferences: (() -> Void)?
    var inspectItem: ((HistoryItem) -> Void)?
    lazy var monitor = ClipboardMonitor(onCapture: { [weak self] payload in self?.save(payload) }, onStatus: { [weak self] message in self?.captureMessage = message })
    lazy var hotkey = GlobalHotKey(onTrigger: { [weak self] in self?.togglePanel?() })
    let pasteCoordinator = PasteCoordinator()

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

    init(store: HistoryStore, demo: Bool, preferenceStore: UserDefaults? = nil) {
        self.store = store
        library = LibraryModel(directory: store.directory.appendingPathComponent("Library", isDirectory: true))
        isDemo = demo
        defaults = preferenceStore ?? (demo ? UserDefaults(suiteName: "com.copystory.preview")! : .standard)
        defaults.register(defaults: ["maxItems": 1000, "maxMB": 500, "respectConfidential": true, "shortcutCode": 4, "shortcutModifiers": 768, "shortcutLabel": "⇧⌘H"])
        onboardingComplete = demo || defaults.bool(forKey: "onboardingComplete")
        paused = defaults.bool(forKey: "paused")
        respectConfidential = defaults.bool(forKey: "respectConfidential")
        maxItems = max(1, defaults.integer(forKey: "maxItems"))
        maxMB = max(10, defaults.integer(forKey: "maxMB"))
        let savedRetention = defaults.integer(forKey: "retentionDays")
        retentionDays = Self.retentionOptions.contains(savedRetention) ? savedRetention : 0
        excludedAppBundleIDs = defaults.stringArray(forKey: "excludedAppBundleIDs") ?? ["com.apple.Passwords"]
        shortcutCode = UInt32(defaults.integer(forKey: "shortcutCode"))
        shortcutModifiers = UInt32(defaults.integer(forKey: "shortcutModifiers"))
        shortcutLabel = defaults.string(forKey: "shortcutLabel") ?? "⇧⌘H"
    }

    func start() {
        library.scheduleSearch()
        guard !isTerminating else { return }
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
                self.accessibilityGranted = PasteCoordinator.accessibilityGranted
                self.loginStatus = LoginService.statusText
                self.loginEnabled = LoginService.isRegistered
                self.isLocked = self.monitor.isLocked
                if self.retentionDays > 0, Date().timeIntervalSince(self.lastRetentionSweep) >= 60 {
                    self.expireHistory()
                }
            }
        }
    }

    func startRecording() {
        guard !isTerminating else { return }
        monitor.isPaused = paused
        monitor.respectConfidential = respectConfidential
        monitor.excludedBundleIDs = Set(excludedAppBundleIDs)
        monitor.start()
    }

    func finishOnboarding(launchAtLogin: Bool) {
        onboardingComplete = true
        defaults.set(true, forKey: "onboardingComplete")
        if !isDemo {
            startRecording()
            setLogin(launchAtLogin)
        }
        togglePanel?()
    }

    func registerHotkey() {
        guard !(AppDistribution.isAppStore && isDemo) else { return }
        do { try hotkey.register(keyCode: shortcutCode, modifiers: shortcutModifiers); shortcutError = nil }
        catch { shortcutError = "Couldn’t register \(shortcutLabel). Another app may use it. Choose a different shortcut in preferences." }
    }

    func changeShortcut(code: UInt32, modifiers: UInt32, label: String) {
        guard !(AppDistribution.isAppStore && isDemo) else { return }
        let previous = (shortcutCode, shortcutModifiers, shortcutLabel)
        do {
            try hotkey.register(keyCode: code, modifiers: modifiers)
            shortcutCode = code; shortcutModifiers = modifiers; shortcutLabel = label
            defaults.set(Int(code), forKey: "shortcutCode")
            defaults.set(Int(modifiers), forKey: "shortcutModifiers")
            defaults.set(label, forKey: "shortcutLabel")
            shortcutError = nil
        } catch {
            try? hotkey.register(keyCode: previous.0, modifiers: previous.1)
            shortcutError = "That shortcut is unavailable. Your previous shortcut is still selected. Try another combination."
        }
        registeringShortcut = false
    }

    func setLogin(_ enabled: Bool) {
        guard !isDemo else { showFeedback("Login registration is disabled in preview mode."); return }
        do { try LoginService.setEnabled(enabled) }
        catch { showFeedback("macOS couldn’t update launch at login. Check Login Items in System Settings.") }
        loginStatus = LoginService.statusText
        loginEnabled = LoginService.isRegistered
    }

    @discardableResult
    func save(_ payload: CapturePayload, fromLibrary: Bool = false) -> Task<Void, Never> {
        guard !isTerminating else { return Task {} }
        let previous = captureMutation
        let task = Task {
            await previous?.value
            do {
                if let source = payload.sourceBundleID, excludedAppBundleIDs.contains(source) { return }
                if let cutoff = expirationCutoff(now: Date()) {
                    let removed = try await store.expireUnpinned(before: cutoff)
                    if removed > 0 { requestVersion += 1; cancelPendingSelection() }
                    if payload.capturedAt < cutoff { await refresh(); return }
                }
                let outcome = try await store.capture(payload, limits: limits)
                switch outcome {
                case .saved, .duplicate: capacityBlocked = false
                case .oversized: showFeedback("This item is too large to save. Existing history was kept.")
                case .pinnedCapacity:
                    capacityBlocked = true
                    if fromLibrary { showFeedback("Copied, but history is full. Unpin items or increase its storage limit.") }
                }
                await refresh()
            } catch { showFeedback(fromLibrary ? "Copied, but this completed prompt could not be saved to history." : "Couldn’t save this clipboard item. Your existing history is still available.") }
        }
        captureMutation = task
        return task
    }

    func scheduleRefresh() {
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

    func refresh() async {
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
            items = Array(result.prefix(n))
            isSearching = false
            hasMore = result.count > n
            if !items.contains(where: { $0.id == selectedID }) { selectedID = items.first?.id }
            count = stats.count; pinnedCount = stats.pinnedCount; storageBytes = stats.totalBytes
            capacityBlocked = stats.pinnedCount >= maxItems || capacityBlocked
            if stats.pinnedCount == 0 { capacityBlocked = false }
        } catch { showFeedback("History couldn’t be read. Reopen CopyStory or check the local storage folder.") }
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
    func cancelPendingSelection() { selectionGeneration += 1 }
    func paste(_ item: HistoryItem) {
        guard !busy, !isSearching else { return }
        let generation = selectionGeneration
        busy = true
        Task {
            defer { busy = false }
            do {
                let payload = try await store.payload(id: item.id)
                guard generation == selectionGeneration, !Task.isCancelled else { return }
                if isDemo {
                    showFeedback("Preview mode: pasting is disabled. Open CopyStory normally to use your clipboard.")
                    return
                }
                let result = await pasteCoordinator.paste(using: monitor, payload: payload, closePanel: { [weak self] in self?.closePanel?() })
                showFeedback(result)
            } catch {
                guard generation == selectionGeneration, !Task.isCancelled else { return }
                showFeedback("This item is unavailable. It may have been removed or damaged.")
                await refresh()
            }
        }
    }

    func copySelected() {
        guard let item = selectedItem, !busy, !isSearching else { return }
        let generation = selectionGeneration
        busy = true
        Task {
            defer { busy = false }
            do {
                guard !isDemo else { showFeedback("Preview mode: clipboard writes are disabled."); return }
                let payload = try await store.payload(id: item.id)
                guard generation == selectionGeneration, !Task.isCancelled else { return }
                try monitor.write(payload)
                showFeedback("Copied. Press ⌘V wherever you need it.")
            } catch {
                guard generation == selectionGeneration, !Task.isCancelled else { return }
                showFeedback("Couldn’t copy this item. Its stored content may be unavailable.")
            }
        }
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
    func recordCompletedPrompt(_ payload: CapturePayload) -> Task<Void, Never>? {
        guard !isDemo, !isTerminating, onboardingComplete, monitor.isRecording, !paused, !isLocked, !monitor.isLocked else { return nil }
        return save(payload, fromLibrary: true)
    }

    func usePrompt(copyOnly: Bool) {
        guard !busy, !isTerminating, case .success(let text) = library.rendered else { return }
        guard !isDemo else { showFeedback("Preview mode: clipboard writes are disabled."); return }
        let payload = CapturePayload(text: text, sourceApp: "CopyStory", sourceBundleID: Bundle.main.bundleIdentifier ?? "app.copystory")
        let generation = selectionGeneration
        busy = true
        statusMessage = nil
        Task {
            defer { busy = false }
            guard generation == selectionGeneration, !isTerminating else { return }
            var admission: Task<Void, Never>?
            if copyOnly {
                do {
                    try monitor.write(payload)
                    showFeedback("Copied. Press ⌘V wherever you need it.")
                    admission = recordCompletedPrompt(payload)
                } catch { showFeedback("Couldn’t write this prompt to the clipboard.") }
            } else {
                let result = await pasteCoordinator.paste(using: monitor, payload: payload, closePanel: { [weak self] in self?.closePanel?() }, onClipboardWrite: { [weak self] in
                    admission = self?.recordCompletedPrompt(payload)
                })
                // Save feedback may arrive during focus restoration; do not overwrite it.
                if admission == nil || statusMessage == nil { showFeedback(result) }
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
        monitor.discardPendingCapture()
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
        monitor.excludedBundleIDs = Set(excludedAppBundleIDs)
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

    func stop() { monitor.stop(); hotkey.unregister(); stateTimer?.invalidate() }
}
