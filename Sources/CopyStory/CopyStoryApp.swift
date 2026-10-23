import AppKit
import SwiftUI
import Carbon
import CopyStoryCore
import OSLog

final class HistoryPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

// Observe natural layout only. No forced layout/display, timer or retry.
final class HistoryHostingView: NSHostingView<HistoryView> {
    var afterNaturalLayout: (@MainActor () -> Void)?
    override func layout() {
        super.layout()
        afterNaturalLayout?()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var model: AppModel!
    private var historyDiagnostics: HistoryPresentationDiagnostics
    private func traceHistory(_ event: HistoryPresentationDiagnostics.Event, _ reason: HistoryPresentationDiagnostics.Reason = .none,
                              ticket: HistoryRequestSimulation.Ticket? = nil, generation: UUID? = nil, valid: Bool? = nil) {
        historyDiagnostics.emit(event, reason, active: recordingHistoryOnly ? nil : NSApp.isActive,
            visible: historyPresentationVisible, key: recordingHistoryOnly ? nil : panel?.isKeyWindow == true,
            pending: panelActivation?.isPending == true, menuDepth: menuTrackingDepth, menuOwned: contextMenuTicket != nil,
            ticketMatches: ticket.map { $0 == model?.recordingInvocationTicket },
            generationMatches: generation.map { $0 == contextMenuGeneration }, valid: valid,
            requestGeneration: (ticket ?? recordingHistoryTicket ?? contextMenuTicket)?.generation)
    }
    private var statusItem: NSStatusItem!
    private var panel: HistoryPanel!
    private weak var historyHost: HistoryHostingView?
    private struct GeometryPlacement {
        let screen: NSScreen
        let selection: HistoryPresentationDiagnostics.Geometry.Selection
        let visibleFrame: CGRect
        let requested: CGRect
        let generation: Int?
    }
    private var geometryPlacement: GeometryPlacement?
    private var geometryLayoutBudget = HistoryPresentationDiagnostics.LayoutBudget()
    private func traceHistoryGeometry(_ phase: HistoryPresentationDiagnostics.Geometry.Phase) {
        guard !recordingHistoryOnly, let panel, let placement = geometryPlacement,
              placement.generation == recordingHistoryTicket?.generation else { return }
        historyDiagnostics.emitGeometry(requestGeneration: placement.generation) { [self] in
            @MainActor func viewGeometry(_ view: NSView?) -> HistoryPresentationDiagnostics.ViewGeometry? {
                guard let view else { return nil }
                return .init(frame: view.frame, bounds: view.bounds, hidden: view.isHiddenOrHasHiddenAncestor,
                    attachedToPanel: view.window === panel, alpha: view.alphaValue,
                    needsLayout: view.needsLayout, ambiguousLayout: view.hasAmbiguousLayout)
            }
            let screens = NSScreen.screens
            let glass = panel.contentView as? NSGlassEffectView
            return .init(phase: phase, selection: placement.selection, screenCount: screens.count,
                screenOrdinal: screens.firstIndex { $0 === placement.screen }, targetVisible: placement.visibleFrame,
                requested: placement.requested, actual: panel.frame, contentLayout: panel.contentLayoutRect,
                intersectsAnyScreen: screens.contains { $0.visibleFrame.intersects(panel.frame) },
                screenMatchesTarget: panel.screen === placement.screen, onActiveSpace: panel.isOnActiveSpace,
                occlusionVisible: panel.occlusionState.contains(.visible), windowVisible: panel.isVisible,
                windowOpaque: panel.isOpaque, windowAlpha: panel.alphaValue,
                glass: viewGeometry(glass), host: viewGeometry(historyHost),
                hostIsGlassContent: glass.flatMap { glass in historyHost.map { glass.contentView === $0 } })
        }
    }
    private var preferences: NSWindow?
    private var onboarding: NSWindow?
    private var previewWindows: [NSWindow] = []
    private var eventMonitor: Any?
    private var menuObservers: [NSObjectProtocol] = []
    private var menuTrackingDepth = 0
    private var outsideMonitor: Any?
    private var feedback: NSPanel?
    private var feedbackTask: Task<Void, Never>?
    private var feedbackSubscription: Any?
    private var demoDirectory: URL?
    private var updates: UpdateService!
    private var panelActivation: PanelActivationGate?
    private var activationObserver: NSObjectProtocol?
    private var terminationPending = false
    private var quitAfterLibrarySave = false

    // Offline initializer: exercises existing entry points without NSApplication,
    // windows/status items, native observation, monitoring or shortcut setup.
    private var recordingHistoryOnly = false
    private(set) var recordingHistoryVisible = false {
        didSet {
            #if FOCUS_IDENTITY_CHECK
            if oldValue != recordingHistoryVisible { focusIdentityHooks?.visibility(recordingHistoryVisible, recordingHistoryTicket) }
            #endif
        }
    }
    #if FOCUS_IDENTITY_CHECK
    private var focusIdentityHooks: FocusIdentityCheckHooks?
    func configureFocusIdentityCheck(_ hooks: FocusIdentityCheckHooks) {
        precondition(recordingHistoryOnly)
        focusIdentityHooks = hooks
    }
    func attachFocusIdentityStatusItem(_ item: NSStatusItem) {
        precondition(recordingHistoryOnly && focusIdentityHooks != nil)
        statusItem = item
        item.button?.title = "CS Focus Check"
        item.button?.toolTip = "Focus/identity only — no clipboard or paste"
        item.button?.target = self
        item.button?.action = #selector(statusClicked)
        item.button?.sendAction(on: [.rightMouseUp])
    }
    #endif
    private func traceFocusIdentity(_ phase: String, ticket: HistoryRequestSimulation.Ticket) {
        #if FOCUS_IDENTITY_CHECK
        focusIdentityHooks?.trace(phase, ticket)
        #endif
    }
    private var contextMenuOpenRequested = false
    private var contextMenuTicket: HistoryRequestSimulation.Ticket?
    private var recordingHistoryTicket: HistoryRequestSimulation.Ticket?
    override init() { historyDiagnostics = .system(); super.init() }
    init(historyRecordingModel: AppModel) {
        model = historyRecordingModel; recordingHistoryOnly = true
        historyDiagnostics = .init()
        super.init()
        model.hideLibraryAfterRecordedWrite = { [weak self] ticket in self?.hideHistoryForPaste(ticket: ticket) }
    }
    func configureHistoryDiagnostics(_ diagnostics: HistoryPresentationDiagnostics) {
        precondition(recordingHistoryOnly)
        historyDiagnostics = diagnostics
        model.historyDiagnostics = diagnostics
        model.pasteCoordinator.nativeAdapter.historyDiagnostics = diagnostics
    }
    func observeHistoryRecording(_ observation: HistoryRecordingObservation,
                                ticket: HistoryRequestSimulation.Ticket? = nil) {
        guard recordingHistoryOnly, let capture = ticket ?? recordingHistoryTicket,
              capture == model.recordingInvocationTicket else { return }
        model.historyRecordingObserved(observation, ticket: capture)
        if case .stopped = observation { recordingHistoryVisible = false }
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !recordingHistoryOnly, NativeIntegrationGates.appLaunchEnabled, NativeIntegrationGates.storageEnabled else { return }
        let demo = ProcessInfo.processInfo.arguments.contains("--demo")
        var startupFailure: StartupFailure?
        let reportFailure: (StartupFailure) -> Void = { startupFailure = $0 }
        do {
            let directory: URL
            if demo {
                directory = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("CopyStory-Preview-\(UUID().uuidString)")
                demoDirectory = directory
            } else {
                directory = DevelopmentConfiguration.storeDirectory(applicationSupport: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0])
            }
            let (store, preferences): (HistoryStore, UserDefaults?) = try StartupStorage.prepare(history: {
                try HistoryStore(directory: directory, reportInitializationFailure: reportFailure)
            }, preferences: {
                StartupStorage.preferences(development: DevelopmentConfiguration.enabled, demo: demo)
            }, reportFailure: reportFailure)
            model = AppModel(store: store, demo: demo, preferenceStore: preferences)
            updates = UpdateService(demo: demo)
            model.togglePanel = { [weak self] in self?.toggleHistory() }
            model.closePanel = { [weak self] in self?.closeHistory() }
            model.historyDiagnostics = historyDiagnostics
            model.pasteCoordinator.nativeAdapter.historyDiagnostics = historyDiagnostics
            model.hideLibraryAfterRecordedWrite = { [weak self] ticket in self?.hideHistoryForPaste(ticket: ticket) }
            model.openPreferences = { [weak self] in self?.showPreferences() }
            model.inspectItem = { [weak self] item in self?.showPreview(item) }
            createStatusItem()
            createMainMenu()
            createHistoryPanel()
            installKeyboardHandling()
            feedbackSubscription = model.$statusMessage.sink { [weak self] message in
                guard let self, let message, self.panel?.isVisible == false, self.preferences?.isVisible != true else { return }
                self.showFeedback(message)
            }
            model.start()
            if demo {
                Task {
                    await seedDemo(store)
                    await model.refresh()
                    model.selectedID = model.items.first?.id
                    toggleHistory()
                }
            } else if !model.onboardingComplete { showOnboarding() }
        } catch {
            let failure = startupFailure ?? StartupFailure(stage: .startup, error: error)
            Logger(subsystem: DevelopmentConfiguration.enabled ? DevelopmentConfiguration.bundleID : "com.copystory.app",
                   category: "startup").error("Startup failed: \(failure.summary, privacy: .public)")
            let alert = NSAlert()
            alert.messageText = "CopyStory couldn’t open its local history"
            alert.informativeText = "Check that your Application Support folder is writable and has free space. Your existing history has not been replaced.\n\nDiagnostic: \(failure.summary)"
            alert.alertStyle = .critical
            alert.runModal()
            NSApp.terminate(nil)
        }
    }

    private func createMainMenu() {
        let menu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: "CopyStory")
        appMenu.addItem(withTitle: "Preferences…", action: #selector(settingsFromMenu), keyEquivalent: ",").target = self
        if !AppDistribution.isAppStore { appMenu.addItem(withTitle: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "").target = self }
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit CopyStory", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu; menu.addItem(appItem)
        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit; menu.addItem(editItem)
        let windowItem = NSMenuItem()
        let window = NSMenu(title: "Window")
        window.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowItem.submenu = window; menu.addItem(windowItem)
        NSApp.mainMenu = menu
        NSApp.windowsMenu = window
    }

    private func createStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "square.on.square", accessibilityDescription: "CopyStory clipboard history")
            image?.isTemplate = true
            button.image = image
            button.target = self
            button.action = #selector(statusClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = DevelopmentConfiguration.enabled ? "CopyStory Development · separate local history" : "CopyStory · \(model.shortcutLabel)"
            if DevelopmentConfiguration.enabled {
                button.image = nil
                button.title = "CS Dev"
                statusItem.length = NSStatusItem.variableLength
            }
        }
    }


    private var historyPresentationVisible: Bool {
        recordingHistoryOnly ? recordingHistoryVisible : panel?.isVisible == true
    }
    private func isOwnedStatusButtonEvent(_ event: NSEvent) -> Bool {
        guard let button = statusItem?.button, let window = button.window,
              window.windowNumber > 0, event.windowNumber == window.windowNumber else { return false }
        return button.bounds.contains(button.convert(event.locationInWindow, from: nil))
    }
    @objc private func statusClicked() {
        traceHistory(.statusBegin)
        defer { traceHistory(.statusEnd) }
        // Every status-item invocation uses genuine native menu selection.
        // Left/right and accessibility actions have no direct-Open fallback.
        trackContextMenuInvocation { ticket in
            guard let generation = contextMenuGeneration else { return }
            let menu = NSMenu()
            #if FOCUS_IDENTITY_CHECK
            let openTitle = "Open focus panel"
            #else
            let openTitle = "Open CopyStory"
            #endif
            let open = menu.addItem(withTitle: openTitle, action: #selector(openFromMenu(_:)), keyEquivalent: "")
            open.representedObject = ContextMenuCommand(ticket: ticket, generation: generation)
            let hide = menu.addItem(withTitle: "Hide History", action: #selector(hideFromMenu(_:)), keyEquivalent: "")
            hide.representedObject = ContextMenuCommand(ticket: ticket, generation: generation)
            #if !FOCUS_IDENTITY_CHECK
            menu.addItem(withTitle: model.paused ? "Resume recording" : "Pause recording", action: #selector(togglePause), keyEquivalent: "")
            menu.addItem(withTitle: "Preferences…", action: #selector(settingsFromMenu), keyEquivalent: ",")
            if !AppDistribution.isAppStore { menu.addItem(withTitle: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "") }
            #endif
            menu.addItem(.separator())
            #if FOCUS_IDENTITY_CHECK
            let quitTitle = "Quit focus check"
            #else
            let quitTitle = "Quit CopyStory"
            #endif
            menu.addItem(withTitle: quitTitle, action: #selector(quitFromMenu), keyEquivalent: "q")
            for item in menu.items { item.target = self }
            #if FOCUS_IDENTITY_CHECK
            guard focusIdentityHooks?.beforePop(menu, ticket) == true else { return }
            #endif
            if let button = statusItem.button { menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.minY), in: button) }
        }
    }
    private struct ContextMenuCommand {
        let ticket: HistoryRequestSimulation.Ticket
        let generation: UUID
    }
    private var contextMenuGeneration: UUID?
    private var contextMenuRetainsPresentation = false
    private var contextMenuHideRequested = false
    var currentContextMenuGeneration: UUID? { contextMenuGeneration }

    // Existing Open action is deferred until native tracking returns. A visible
    // or pending presentation keeps its capture; menu identity is separate.
    @discardableResult
    func trackContextMenuInvocation(_ tracking: (HistoryRequestSimulation.Ticket) -> Void) -> HistoryRequestSimulation.Ticket? {
        guard let ticket = beginContextMenuInvocation(), let generation = contextMenuGeneration else { return nil }
        traceHistory(.trackingBegin, ticket: ticket, generation: generation)
        traceFocusIdentity("trackingEntered", ticket: ticket)
        defer {
            traceHistory(.trackingReturned, ticket: ticket, generation: generation)
            traceFocusIdentity("trackingReturned", ticket: ticket)
            finishContextMenuInvocation(ticket: ticket, generation: generation)
            traceFocusIdentity("trackingCompleted", ticket: ticket)
        }
        tracking(ticket)
        return ticket
    }
    @objc private func openFromMenu(_ sender: NSMenuItem) {
        guard let command = sender.representedObject as? ContextMenuCommand else { traceHistory(.openGuard, .noCommand); return }
        openContextMenuInvocation(ticket: command.ticket, generation: command.generation)
    }
    @objc private func hideFromMenu(_ sender: NSMenuItem) {
        guard let command = sender.representedObject as? ContextMenuCommand else { return }
        hideContextMenuInvocation(ticket: command.ticket, generation: command.generation)
    }
    @discardableResult
    func beginContextMenuInvocation() -> HistoryRequestSimulation.Ticket? {
        traceHistory(.menuBegin)
        cancelContextMenuInvocation()
        guard model.canRecordHistoryInvocation else { traceHistory(.openGuard, .lifecycle); return nil }
        let retains = (historyPresentationVisible || panelActivation?.isPending == true) &&
            recordingHistoryTicket == model.recordingInvocationTicket &&
            recordingHistoryTicket.map { model.canPresentInvocation($0) } == true
        if !retains {
            cancelHistoryPanelActivation(reason: .menuReplacement)
            model.pasteCoordinator.rememberDestination()
        }
        guard model.canRecordHistoryInvocation, let ticket = model.recordingInvocationTicket else { traceHistory(.openGuard, .missingTicket); return nil }
        contextMenuTicket = ticket; contextMenuGeneration = UUID()
        contextMenuRetainsPresentation = retains
        contextMenuOpenRequested = false; contextMenuHideRequested = false
        // The menu takes over existing focus intent. Its cancel must not allow
        // that old focus attempt to resurrect a panel auto-hidden in tracking.
        if retains && panelActivation?.isFocusingExistingPresentation == true { cancelHistoryPanelActivation(reason: .focusTransfer) }
        if !retains { model.requestPresentationOpened(ticket) }
        traceHistory(.menuOwned, ticket: ticket, generation: contextMenuGeneration)
        traceFocusIdentity("menuOwned", ticket: ticket)
        return ticket
    }
    func cancelContextMenuInvocation() {
        traceHistory(.menuCancelled, ticket: contextMenuTicket, generation: contextMenuGeneration)
        if let ticket = contextMenuTicket, ticket == model.recordingInvocationTicket,
           !contextMenuRetainsPresentation || (!historyPresentationVisible && panelActivation?.isPending != true) {
            model.historyRecordingDismissed(ticket: ticket)
            model.requestPresentationHidden(ticket)
        }
        contextMenuTicket = nil; contextMenuGeneration = nil
        contextMenuOpenRequested = false; contextMenuHideRequested = false
        contextMenuRetainsPresentation = false
    }
    func openContextMenuInvocation(ticket: HistoryRequestSimulation.Ticket, generation: UUID) {
        traceHistory(.openReceived, ticket: ticket, generation: generation)
        guard ticket == contextMenuTicket else { traceHistory(.openGuard, .ticketMismatch, ticket: ticket, generation: generation); return }
        guard generation == contextMenuGeneration else { traceHistory(.openGuard, .generationMismatch, ticket: ticket, generation: generation); return }
        guard ticket == model.recordingInvocationTicket else { traceHistory(.openGuard, .ticketMismatch, ticket: ticket, generation: generation); return }
        guard model.canPresentInvocation(ticket) else { traceHistory(.openGuard, .invalidRequest, ticket: ticket, generation: generation, valid: false); return }
        traceHistory(.openGuard, .accepted, ticket: ticket, generation: generation, valid: true)
        contextMenuOpenRequested = true; contextMenuHideRequested = false
        traceFocusIdentity("openChoice", ticket: ticket)
    }
    func hideContextMenuInvocation(ticket: HistoryRequestSimulation.Ticket, generation: UUID) {
        guard ticket == contextMenuTicket, generation == contextMenuGeneration,
              ticket == model.recordingInvocationTicket else { return }
        contextMenuHideRequested = true; contextMenuOpenRequested = false
    }
    func finishContextMenuInvocation(ticket: HistoryRequestSimulation.Ticket, generation: UUID) {
        traceHistory(.finishMenu, ticket: ticket, generation: generation)
        guard ticket == contextMenuTicket else { traceHistory(.finishMenu, .ticketMismatch, ticket: ticket, generation: generation); return }
        guard generation == contextMenuGeneration else { traceHistory(.finishMenu, .generationMismatch, ticket: ticket, generation: generation); return }
        let open = contextMenuOpenRequested, hide = contextMenuHideRequested
        let retains = contextMenuRetainsPresentation
        contextMenuTicket = nil; contextMenuGeneration = nil
        contextMenuOpenRequested = false; contextMenuHideRequested = false; contextMenuRetainsPresentation = false
        guard ticket == model.recordingInvocationTicket else { traceHistory(.finishMenu, .ticketMismatch, ticket: ticket); return } // Old menu cannot dismiss a newer request.
        if hide {
            traceHistory(.finishMenu, .hideChoice, ticket: ticket)
            if !retains { model.historyRecordingDismissed(ticket: ticket); model.requestPresentationHidden(ticket) }
            hideHistoryRequested()
            return
        }
        guard open, model.canPresentInvocation(ticket) else {
            traceHistory(.finishMenu, open ? .invalidRequest : .noOpenChoice, ticket: ticket)
            if !retains || (!historyPresentationVisible && panelActivation?.isPending != true) {
                model.historyRecordingDismissed(ticket: ticket); model.requestPresentationHidden(ticket)
            }
            historyPanelActivationChanged()
            traceFocusIdentity("menuCancelled", ticket: ticket)
            return
        }
        traceHistory(.finishMenu, .accepted, ticket: ticket)
        traceFocusIdentity("panelPermitted", ticket: ticket)
        openHistory(capturedInvocation: ticket)
        historyPanelActivationChanged()
    }
    func hideHistoryRequested() { closeHistory(reason: "explicitHide") }
    @objc private func togglePause() { model.paused.toggle() }
    @objc private func settingsFromMenu() { showPreferences() }
    @objc private func quitFromMenu() { NSApp.terminate(nil) }
    @objc private func checkForUpdates() { updates.checkForUpdates() }

    private func createHistoryPanel() {
        panel = HistoryPanel(contentRect: NSRect(x: 0, y: 0, width: 540, height: 640), styleMask: [.borderless, .fullSizeContentView], backing: .buffered, defer: false)
        panel.title = "CopyStory History"
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.delegate = self
        let host = HistoryHostingView(rootView: HistoryView(model: model))
        historyHost = host
        host.afterNaturalLayout = { [weak self] in
            guard let self, self.geometryLayoutBudget.consume() else { return }
            self.traceHistoryGeometry(.hostLayout)
        }
        let glass = NSGlassEffectView()
        glass.cornerRadius = 18
        glass.contentView = host
        panel.contentView = glass
    }


    private func nativePanelActivation() -> PanelActivationGate {
        if let panelActivation { return panelActivation }
        let environment = PanelActivationEnvironment(
            now: { ProcessInfo.processInfo.systemUptime },
            isActive: { NSApp.isActive },
            isTrackingMenu: { [weak self] in (self?.menuTrackingDepth ?? 0) > 0 || self?.contextMenuTicket != nil },
            requestActivation: { NSApp.activate() },
            present: { [weak self] in
                guard let self, NSApp.isActive, !self.terminationPending else { return false }
                self.traceHistory(.orderFrontBefore)
                self.traceHistoryGeometry(.beforeOrder)
                self.panel.makeKeyAndOrderFront(nil)
                self.traceHistory(.orderFrontAfter)
                self.traceHistoryGeometry(.afterOrder)
                return NSApp.isActive && self.panel.isVisible && self.panel.isKeyWindow
            },
            hide: { [weak self] in self?.traceHistory(.hide, .gateFailure); self?.panel?.orderOut(nil) },
            scheduleTimeout: { seconds, action in
                let timer = Timer(timeInterval: seconds, repeats: false) { _ in MainActor.assumeIsolated { action() } }
                RunLoop.main.add(timer, forMode: .common)
                return { timer.invalidate() }
            })
        let gate = PanelActivationGate(environment: environment, diagnostics: historyDiagnostics)
        panelActivation = gate
        return gate
    }
    func beginHistoryPanelActivation(ticket: HistoryRequestSimulation.Ticket, focusingExisting: Bool = false) {
        let gate = nativePanelActivation()
        gate.begin(valid: { [weak self] in
            guard let self else { return false }
            let valid = !self.terminationPending && ticket == self.recordingHistoryTicket &&
                ticket == self.model.recordingInvocationTicket && self.model.canPresentInvocation(ticket)
            self.traceHistory(.presentationGuard, valid ? .accepted : .invalidRequest, ticket: ticket, valid: valid)
            return valid
        }, preservingExistingPresentation: focusingExisting, diagnosticGeneration: ticket.generation, completion: { [weak self] result in
            guard let self else { return }
            guard ticket == self.recordingHistoryTicket, ticket == self.model.recordingInvocationTicket else { return }
            if result == .presented {
                self.model.focusRequest = UUID()
                if self.outsideMonitor == nil {
                    self.outsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                        Task { @MainActor in self?.closeHistory() }
                    }
                }
            } else if !focusingExisting || (!self.historyPresentationVisible && self.contextMenuTicket != ticket) {
                self.model.historyRecordingDismissed(ticket: ticket)
                self.model.requestPresentationHidden(ticket)
            } // Retain focus capture only while the existing window or exact menu still owns it.
        })
    }
    func cancelHistoryPanelActivation(reason: HistoryPresentationDiagnostics.Reason = .cancelled) { traceHistory(.cancelActivation, reason); panelActivation?.cancel() }
    func historyPanelActivationChanged() { panelActivation?.activationOrMenuChanged() }

    // Keyboard shortcut retains its explicit toggle behavior. Status-item and
    // menu Open commands call openHistory, never this toggle entry.
    func toggleHistory(capturedInvocation: HistoryRequestSimulation.Ticket? = nil) {
        guard model.canRecordHistoryInvocation else { return }
        if let capturedInvocation, capturedInvocation != model.recordingInvocationTicket { return }
        if historyPresentationVisible || panelActivation?.isPending == true { closeHistory(); return }
        openHistory(capturedInvocation: capturedInvocation)
    }
    func openHistory(capturedInvocation: HistoryRequestSimulation.Ticket? = nil) {
        traceHistory(.presentationBegin, ticket: capturedInvocation)
        guard model.canRecordHistoryInvocation else { traceHistory(.presentationGuard, .lifecycle); return }
        if let capturedInvocation, capturedInvocation != model.recordingInvocationTicket { traceHistory(.presentationGuard, .ticketMismatch, ticket: capturedInvocation); return }
        if historyPresentationVisible {
            guard let ticket = recordingHistoryTicket, ticket == model.recordingInvocationTicket,
                  model.canPresentInvocation(ticket) else { traceHistory(.presentationGuard, .invalidRequest); return }
            traceHistory(.presentationGuard, .existing, ticket: ticket)
            if recordingHistoryOnly { model.focusRequest = UUID(); return }
            if panelActivation?.isPending != true { beginHistoryPanelActivation(ticket: ticket, focusingExisting: true) }
            return // Never replace a destination merely to focus existing history.
        }
        if panelActivation?.isPending == true { traceHistory(.presentationGuard, .coalesced); return } // Coalesce Open; no deadline reset.
        if recordingHistoryOnly {
            if capturedInvocation == nil { model.pasteCoordinator.rememberDestination() }
            guard model.canRecordHistoryInvocation else { return }
            recordingHistoryTicket = model.recordingInvocationTicket
            if let ticket = recordingHistoryTicket { model.requestPresentationOpened(ticket) }
            recordingHistoryVisible = true
            return
        }
        if !model.onboardingComplete { traceHistory(.presentationGuard, .onboarding); showOnboarding(); return }
        if capturedInvocation == nil { model.pasteCoordinator.rememberDestination() }
        geometryPlacement = nil
        geometryLayoutBudget = .init()
        recordingHistoryTicket = model.recordingInvocationTicket
        if let ticket = recordingHistoryTicket { model.requestPresentationOpened(ticket) }
        model.library.resetScreen()
        model.selectSection(.history)
        model.query = ""; model.filter = .all
        let pointerScreen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }
        let mainScreen = pointerScreen == nil ? NSScreen.main : nil
        let screen = pointerScreen ?? mainScreen ?? NSScreen.screens[0]
        let selection: HistoryPresentationDiagnostics.Geometry.Selection = pointerScreen != nil ? .pointer : mainScreen != nil ? .main : .first
        let frame = screen.visibleFrame
        let size = NSSize(width: min(540, frame.width - 30), height: min(650, frame.height - 36))
        let requested = NSRect(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2 + 30, width: size.width, height: size.height)
        geometryPlacement = GeometryPlacement(screen: screen, selection: selection, visibleFrame: frame, requested: requested, generation: recordingHistoryTicket?.generation)
        geometryLayoutBudget.begin()
        panel.setFrame(requested, display: true)
        traceHistoryGeometry(.placement)
        guard let ticket = recordingHistoryTicket else { traceHistory(.presentationGuard, .missingTicket); return }
        beginHistoryPanelActivation(ticket: ticket)
    }

    func closeHistory(reason: String = "explicitClose") {
        traceHistory(.closeRequested, HistoryPresentationDiagnostics.Reason(rawValue: reason) ?? .explicitClose)
        cancelContextMenuInvocation()
        cancelHistoryPanelActivation(reason: HistoryPresentationDiagnostics.Reason(rawValue: reason) ?? .explicitClose)
        if recordingHistoryOnly {
            let ticket = recordingHistoryTicket
            model.library.requestDismiss { [weak self] in
                guard let self, ticket == self.recordingHistoryTicket,
                      ticket == self.model.recordingInvocationTicket else { return }
                self.model.historyRecordingDismissed(ticket: ticket)
                if let ticket { self.model.requestPresentationHidden(ticket) }
                self.model.library.resetScreen()
                self.recordingHistoryVisible = false
            }
            return
        }
        guard !terminationPending else { return }
        model.library.requestDismiss { [weak self] in self?.hideHistory(reason: reason) }
    }

    // Paste-owned hide and user dismissal share presentation bookkeeping but
    // only user dismissal invalidates the captured request.
    func hideHistoryForPaste(ticket: HistoryRequestSimulation.Ticket) {
        traceHistory(.hideRequested, .paste, ticket: ticket)
        guard ticket == recordingHistoryTicket, ticket == model.recordingInvocationTicket else { return }
        cancelHistoryPanelActivation(reason: .paste)
        model.library.resetScreen(preservingRequest: true)
        model.requestPresentationHidden(ticket)
        if recordingHistoryOnly { recordingHistoryVisible = false; return }
        guard NativeIntegrationGates.appLaunchEnabled else { return }
        traceHistory(.hide, .paste, ticket: ticket)
        panel?.orderOut(nil)
        if let outsideMonitor { NSEvent.removeMonitor(outsideMonitor); self.outsideMonitor = nil }
    }
    private func hideHistory(reason: String = "directHide") {
        cancelHistoryPanelActivation(reason: HistoryPresentationDiagnostics.Reason(rawValue: reason) ?? .directHide)
        model.historyRecordingDismissed(ticket: recordingHistoryTicket)
        if let ticket = recordingHistoryTicket { model.requestPresentationHidden(ticket) }
        model.library.resetScreen()
        model?.cancelPendingSelection()
        traceHistory(.hide, HistoryPresentationDiagnostics.Reason(rawValue: reason) ?? .directHide)
        panel?.orderOut(nil)
        if let outsideMonitor { NSEvent.removeMonitor(outsideMonitor); self.outsideMonitor = nil }
    }

    func historyDidResignActive() {
        traceHistory(.resignedActive)
        // Existing capture belongs only to this exact menu lifetime, not the
        // next click. Dirty/saving editors stay visible; explicit Hide requests
        // their existing discard guard after tracking returns.
        if contextMenuRetainsPresentation, contextMenuGeneration != nil,
           let ticket = contextMenuTicket, ticket == recordingHistoryTicket,
           ticket == model.recordingInvocationTicket, model.canPresentInvocation(ticket) {
            guard historyPresentationVisible, !model.library.isDirty, !model.library.saving else { return }
            if recordingHistoryOnly { recordingHistoryVisible = false }
            else {
                guard panel.attachedSheet == nil else { return }
                traceHistory(.hide, .resignActive)
                panel.orderOut(nil)
            }
            return
        }
        cancelHistoryPanelActivation(reason: .resignActive)
        guard historyPresentationVisible else { return }
        if !recordingHistoryOnly, panel.attachedSheet != nil { return }
        closeHistory(reason: "resignActive")
    }
    func applicationDidResignActive(_ notification: Notification) {
        historyDidResignActive()
    }

    private func installKeyboardHandling() {
        activationObserver = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: NSApp, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.traceHistory(.becameActive); self?.historyPanelActivationChanged() }
        }
        for (name, delta) in [(NSMenu.didBeginTrackingNotification, 1), (NSMenu.didEndTrackingNotification, -1)] {
            menuObservers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.menuTrackingDepth = max(0, self.menuTrackingDepth + delta)
                    self.traceHistory(.menuDepthChanged)
                    self.historyPanelActivationChanged()
                }
            })
        }
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self else { return event }
            if self.model.registeringShortcut && self.preferences?.isKeyWindow == true {
                if event.keyCode == 53 { self.model.registeringShortcut = false; return nil }
                let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                guard flags.contains(.command) || flags.contains(.control) || flags.contains(.option) else { NSSound.beep(); return nil }
                var modifiers: UInt32 = 0
                var label = ""
                if flags.contains(.control) { modifiers |= UInt32(controlKey); label += "⌃" }
                if flags.contains(.option) { modifiers |= UInt32(optionKey); label += "⌥" }
                if flags.contains(.shift) { modifiers |= UInt32(shiftKey); label += "⇧" }
                if flags.contains(.command) { modifiers |= UInt32(cmdKey); label += "⌘" }
                let key = event.charactersIgnoringModifiers?.uppercased() ?? ""
                guard !key.isEmpty, !key.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { NSSound.beep(); return nil }
                self.model.changeShortcut(code: UInt32(event.keyCode), modifiers: modifiers, label: label + key)
                return nil
            }
            // Carbon consumes system hotkeys. Also handle responder-delivered
            // key events when a CopyStory window itself is active.
            let shortcutFlags = event.modifierFlags.intersection([.command, .shift, .option, .control])
            var carbonFlags: UInt32 = 0
            if shortcutFlags.contains(.command) { carbonFlags |= UInt32(cmdKey) }
            if shortcutFlags.contains(.shift) { carbonFlags |= UInt32(shiftKey) }
            if shortcutFlags.contains(.option) { carbonFlags |= UInt32(optionKey) }
            if shortcutFlags.contains(.control) { carbonFlags |= UInt32(controlKey) }
            if UInt32(event.keyCode) == self.model.shortcutCode && carbonFlags == self.model.shortcutModifiers {
                self.toggleHistory(); return nil
            }
            guard self.panel.isKeyWindow, self.panel.attachedSheet == nil, self.menuTrackingDepth == 0 else { return event }
            let library = self.model.library
            if event.keyCode == 53 {
                if library.section == .library && library.screen != .browse { self.model.cancelPendingSelection(); library.back() }
                else { self.closeHistory() }
                return nil
            }
            if library.section == .library {
                if library.screen != .browse {
                    if event.modifierFlags.contains(.command) {
                        if event.keyCode == 36 && self.model.handleLibraryCommandReturn() { return nil }
                        if event.charactersIgnoringModifiers?.lowercased() == "s" && library.screen == .editor { library.saveDraft(); return nil }
                    }
                    return event
                }
                if event.keyCode == 125 { library.moveSelection(1); return nil }
                if event.keyCode == 126 { library.moveSelection(-1); return nil }
                if event.keyCode == 36 || event.keyCode == 76 {
                    if let entry = library.selected { library.open(entry) }
                    return nil
                }
                if event.modifierFlags.contains(.command) {
                    if event.charactersIgnoringModifiers?.lowercased() == "n" { library.edit(); return nil }
                    if event.charactersIgnoringModifiers?.lowercased() == "e", let entry = library.selected { library.edit(entry); return nil }
                    if event.keyCode == 51 { library.pendingDelete = library.selected; return nil }
                }
                return event
            }
            if event.keyCode == 125 { self.model.moveSelection(1); return nil }
            if event.keyCode == 126 { self.model.moveSelection(-1); return nil }
            if event.keyCode == 36 || event.keyCode == 76 { self.model.pasteSelected(); return nil }
            if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers?.lowercased() == "c" {
                self.model.copySelected(); return nil
            }
            if event.modifierFlags.contains(.command), let item = self.model.selectedItem {
                if event.charactersIgnoringModifiers?.lowercased() == "p" { self.model.togglePin(item); return nil }
                if event.charactersIgnoringModifiers?.lowercased() == "i" { self.showPreview(item); return nil }
                if event.keyCode == 51 { self.model.delete(item); return nil }
            }
            if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "," { self.showPreferences(); return nil }
            return event
        }
    }

    private func showPreferences() {
        closeHistory()
        if preferences == nil {
            preferences = makeWindow(title: "CopyStory Preferences", content: PreferencesView(model: model, updates: updates), size: NSSize(width: 570, height: 720))
        }
        model.accessibilityGranted = PasteCoordinator.accessibilityGranted
        model.loginStatus = LoginService.statusText
        model.loginEnabled = LoginService.isRegistered
        NSApp.activate()
        preferences?.center()
        preferences?.makeKeyAndOrderFront(nil)
    }

    private func showOnboarding() {
        if onboarding == nil {
            onboarding = makeWindow(title: "Welcome to CopyStory", content: OnboardingView(model: model, onFinish: { [weak self] login, changed in
                guard let self else { return }
                self.onboarding?.close()
                self.model.finishOnboarding(launchAtLogin: login, loginWasChanged: changed)
            }), size: NSSize(width: 580, height: 720))
        }
        NSApp.activate()
        onboarding?.center()
        onboarding?.makeKeyAndOrderFront(nil)
    }

    private func showPreview(_ item: HistoryItem) {
        closeHistory()
        let window = makeWindow(title: "CopyStory — Item Preview", content: InspectView(item: item, store: model.store), size: NSSize(width: 760, height: 560))
        window.styleMask.insert(.resizable)
        previewWindows.removeAll { !$0.isVisible }
        previewWindows.append(window)
        NSApp.activate()
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow<Content: View>(title: String, content: Content, size: NSSize) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = title
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: content)
        return window
    }

    private func showFeedback(_ message: String) {
        feedbackTask?.cancel()
        feedback?.orderOut(nil)
        let toast = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 390, height: 74), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        toast.level = .floating
        toast.isOpaque = false
        toast.backgroundColor = .clear
        toast.ignoresMouseEvents = true
        toast.isReleasedWhenClosed = false
        toast.contentView = NSHostingView(rootView: Label(message, systemImage: "square.on.square").font(.callout).padding(18).frame(width: 390).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14)))
        if let screen = NSScreen.main {
            toast.setFrameOrigin(NSPoint(x: screen.visibleFrame.midX - 195, y: screen.visibleFrame.minY + 50))
        }
        toast.orderFrontRegardless()
        feedback = toast
        feedbackTask = Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            if !Task.isCancelled { toast.orderOut(nil) }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard model != nil else { return true }
        if !flag { openHistory() }
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        cancelHistoryPanelActivation(reason: .termination)
        guard let model else { return .terminateNow }
        if model.library.saving {
            if !quitAfterLibrarySave {
                quitAfterLibrarySave = true
                Task {
                    await model.library.waitForPendingWrites()
                    quitAfterLibrarySave = false
                    NSApp.terminate(nil)
                }
            }
            // Re-enter after saving: a failed write must still offer to keep the draft.
            return .terminateCancel
        }
        if model.library.isDirty {
            model.library.requestDismiss { NSApp.terminate(nil) }
            traceHistory(.orderFrontBefore, .termination)
            panel.makeKeyAndOrderFront(nil)
            traceHistory(.orderFrontAfter, .termination)
            return .terminateCancel
        }
        if !terminationPending {
            terminationPending = true
            let drain = model.prepareForTermination()
            Task {
                await drain.value
                sender.reply(toApplicationShouldTerminate: true)
            }
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        cancelHistoryPanelActivation(reason: .termination)
        if let activationObserver { NotificationCenter.default.removeObserver(activationObserver); self.activationObserver = nil }
        model?.stop()
        for observer in menuObservers { NotificationCenter.default.removeObserver(observer) }
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
        if let outsideMonitor { NSEvent.removeMonitor(outsideMonitor) }
        if let demoDirectory { try? FileManager.default.removeItem(at: demoDirectory) }
    }

    private func seedDemo(_ store: HistoryStore) async {
        let fixtures: [(String, String, TimeInterval)] = [
            ("The best ideas deserve a second copy.", "Notes", -1800),
            ("git switch -c feature/something-good\nswift test", "Terminal", -720),
            ("https://developer.apple.com/design/", "Safari", -540),
            ("A small reminder: leave room for the unexpected.\nNext steps → sketch, build, try it.", "Notes", -180),
            ("let ideas = history.filter { $0.isWorthKeeping }", "Code", -60)
        ]
        for fixture in fixtures {
            _ = try? await store.capture(CapturePayload(text: fixture.0, imageData: nil, thumbnailData: nil, pixelWidth: nil, pixelHeight: nil, sourceApp: fixture.1, sourceBundleID: nil, capturedAt: Date().addingTimeInterval(fixture.2)), limits: model.limits)
        }
        if let context = CGContext(data: nil, width: 640, height: 360, bitsPerComponent: 8, bytesPerRow: 2560, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
            context.setFillColor(CGColor(red: 0.12, green: 0.25, blue: 0.5, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 640, height: 360))
            context.setFillColor(CGColor(red: 0.47, green: 0.73, blue: 0.91, alpha: 1))
            context.fillEllipse(in: CGRect(x: 210, y: 30, width: 380, height: 380))
            context.setFillColor(CGColor(red: 0.72, green: 0.62, blue: 0.89, alpha: 0.85))
            context.fillEllipse(in: CGRect(x: -60, y: -100, width: 450, height: 450))
            if let image = context.makeImage(), let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) {
                _ = try? await store.capture(CapturePayload(imageData: data, sourceApp: "Preview", capturedAt: Date().addingTimeInterval(-120)), limits: model.limits)
            }
        }
        if let first = try? await store.search(query: "best ideas", filter: .all, limit: 1, offset: 0).first { try? await store.setPinned(id: first.id, pinned: true) }
    }
}

extension AppDelegate: NSMenuItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(checkForUpdates) { return updates?.canCheckForUpdates == true }
        return true
    }
}
