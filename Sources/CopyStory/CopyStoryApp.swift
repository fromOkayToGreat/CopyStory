import AppKit
import SwiftUI
import Carbon
import CopyStoryCore

@main
struct CopyStoryMain {
    @MainActor static func main() {
        if ProcessInfo.processInfo.arguments.contains("--verify-package-runtime") {
            do {
                print(try UpdateService.verifyPackagedRuntime())
            } catch {
                fputs("CopyStory runtime verification failed: \(error.localizedDescription)\n", stderr)
                exit(EXIT_FAILURE)
            }
            return
        }
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        application.run()
        withExtendedLifetime(delegate) {}
    }
}

final class HistoryPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var model: AppModel!
    private var statusItem: NSStatusItem!
    private var panel: HistoryPanel!
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
    private var terminationPending = false
    private var quitAfterLibrarySave = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        let demo = ProcessInfo.processInfo.arguments.contains("--demo")
        do {
            let directory: URL
            if demo {
                directory = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("CopyStory-Preview-\(UUID().uuidString)")
                demoDirectory = directory
            } else {
                directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("CopyStory", isDirectory: true)
            }
            let store = try HistoryStore(directory: directory)
            model = AppModel(store: store, demo: demo)
            updates = UpdateService(demo: demo)
            model.togglePanel = { [weak self] in self?.toggleHistory() }
            model.closePanel = { [weak self] in self?.closeHistory() }
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
            let alert = NSAlert()
            alert.messageText = "CopyStory couldn’t open its local history"
            alert.informativeText = "Check that your Application Support folder is writable and has free space. Your existing history has not been replaced."
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
        appMenu.addItem(withTitle: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "").target = self
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
            button.toolTip = "CopyStory · \(model.shortcutLabel)"
        }
    }

    @objc private func statusClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            model.pasteCoordinator.rememberDestination()
            let menu = NSMenu()
            menu.addItem(withTitle: "Open CopyStory", action: #selector(openFromMenu), keyEquivalent: "")
            menu.addItem(withTitle: model.paused ? "Resume recording" : "Pause recording", action: #selector(togglePause), keyEquivalent: "")
            menu.addItem(withTitle: "Preferences…", action: #selector(settingsFromMenu), keyEquivalent: ",")
            menu.addItem(withTitle: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
            menu.addItem(.separator())
            menu.addItem(withTitle: "Quit CopyStory", action: #selector(quitFromMenu), keyEquivalent: "q")
            for item in menu.items { item.target = self }
            if let button = statusItem.button { menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.minY), in: button) }
        } else { toggleHistory() }
    }
    @objc private func openFromMenu() { if !panel.isVisible { toggleHistory() } }
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
        let host = NSHostingView(rootView: HistoryView(model: model))
        let glass = NSGlassEffectView()
        glass.cornerRadius = 18
        glass.contentView = host
        panel.contentView = glass
    }

    func toggleHistory() {
        if !model.onboardingComplete { showOnboarding(); return }
        if panel.isVisible { closeHistory(); return }
        model.pasteCoordinator.rememberDestination()
        model.library.resetScreen()
        model.selectSection(.history)
        model.query = ""
        model.filter = .all
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
        let frame = screen.visibleFrame
        let size = NSSize(width: min(540, frame.width - 30), height: min(650, frame.height - 36))
        panel.setFrame(NSRect(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2 + 30, width: size.width, height: size.height), display: true)
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        model.focusRequest = UUID()
        if outsideMonitor == nil {
            outsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                Task { @MainActor in self?.closeHistory() }
            }
        }
    }

    func closeHistory() {
        guard !terminationPending else { return }
        model.library.requestDismiss { [weak self] in self?.hideHistory() }
    }

    private func hideHistory() {
        model.library.resetScreen()
        model?.cancelPendingSelection()
        panel?.orderOut(nil)
        if let outsideMonitor { NSEvent.removeMonitor(outsideMonitor); self.outsideMonitor = nil }
    }

    func applicationDidResignActive(_ notification: Notification) {
        // Native dropdowns and other controls may temporarily own keyboard focus.
        // Close only when leaving the app, not when opening one of those controls.
        guard panel?.isVisible == true, panel.attachedSheet == nil else { return }
        closeHistory()
    }

    private func installKeyboardHandling() {
        for (name, delta) in [(NSMenu.didBeginTrackingNotification, 1), (NSMenu.didEndTrackingNotification, -1)] {
            menuObservers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.menuTrackingDepth = max(0, self.menuTrackingDepth + delta)
                }
            })
        }
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
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
                        if event.keyCode == 36 && library.screen == .use { self.model.usePrompt(copyOnly: false); return nil }
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
            onboarding = makeWindow(title: "Welcome to CopyStory", content: OnboardingView(model: model, onFinish: { [weak self] login in
                guard let self else { return }
                self.onboarding?.close()
                self.model.finishOnboarding(launchAtLogin: login)
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
        if !flag { toggleHistory() }
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
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
            panel.makeKeyAndOrderFront(nil)
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
