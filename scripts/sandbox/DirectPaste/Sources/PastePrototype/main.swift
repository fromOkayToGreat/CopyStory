import AppKit
import Carbon
import RoutingCore

// This executable has no production imports, AX APIs, general pasteboard access,
// automatic permission request, login service, history, preferences or network path.
final class ExperimentPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class Experiment: NSObject, NSApplicationDelegate, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
    let run: String
    let board: NSPasteboard
    var gate = PasteGate(ownPID: ProcessInfo.processInfo.processIdentifier)
    var destination: NSRunningApplication?
    var statusItem: NSStatusItem!
    var panel: ExperimentPanel!
    var status = NSTextField(wrappingLabelWithString: "Focus the synthetic target, then invoke the panel.")
    let search = NSTextField(string: "")
    let variable = NSTextField(string: "synthetic topic")
    let table = NSTableView()
    let delay = NSPopUpButton()
    var hotkey: EventHotKeyRef?
    var observers: [NSObjectProtocol] = []
    var statusEventMonitor: Any?
    var writing = false
    var invocationSource = "none"
    var contextMenuOpenChosen = false
    let shortcut: String
    let logURL: URL
    let fixtures: Set<String> = ["com.copystory.paste-fixture.target", "com.copystory.paste-fixture.decoy"]
    func permissionStatus() -> Bool { CGPreflightPostEventAccess() }

    init(run: String) {
        self.run = run
        if let index = CommandLine.arguments.firstIndex(of: "--shortcut") {
            guard CommandLine.arguments.indices.contains(index + 1),
                  ["alternate", "default", "isolated"].contains(CommandLine.arguments[index + 1]) else {
                fatalError("--shortcut requires alternate, default or isolated")
            }
            shortcut = CommandLine.arguments[index + 1]
        } else { shortcut = "alternate" }
        board = NSPasteboard(name: .init("com.copystory.paste-experiment.\(run)"))
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PasteExperiment/\(run)", isDirectory: true)
        try! FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        logURL = root.appendingPathComponent("events.jsonl")
        super.init()
    }
    func record(_ name: String, _ details: [String: Any] = [:]) {
        var value = details
        value["event"] = name; value["uptime"] = ProcessInfo.processInfo.systemUptime
        value["run"] = run; value["pid"] = ProcessInfo.processInfo.processIdentifier
        value["frontmostPID"] = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? -1
        if let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) {
            if !FileManager.default.fileExists(atPath: logURL.path) { FileManager.default.createFile(atPath: logURL.path, contents: nil) }
            if let handle = try? FileHandle(forWritingTo: logURL) {
                handle.seekToEndOfFile(); handle.write(data); handle.write(Data([10])); try? handle.close()
            }
            print(String(decoding: data, as: UTF8.self)); fflush(stdout)
        }
    }
    func applicationDidFinishLaunching(_ note: Notification) {
        NSApp.setActivationPolicy(.accessory)
        makePanel()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "CS Paste Lab"
        statusItem.button?.toolTip = "Synthetic named-pasteboard experiment"
        statusItem.button?.target = self; statusItem.button?.action = #selector(statusClicked)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        // Observe only events delivered to this app's own status window. This
        // does not monitor other apps or cache a previous paste destination.
        statusEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp]) { [weak self] event in
            guard let self, event.window === self.statusItem.button?.window else { return event }
            self.record("statusMouseEvent", self.mouseDetails(event))
            return event
        }
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.didTerminateApplicationNotification,
                     NSWorkspace.willSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                guard let self else { return }
                if name == NSWorkspace.didActivateApplicationNotification,
                   let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
                    self.gate.applicationActivated(app.processIdentifier)
                    self.record("activation", ["activatedPID": app.processIdentifier,
                                               "panelKey": self.panel.isKeyWindow,
                                               "panelVisible": self.panel.isVisible])
                } else if name == NSWorkspace.didTerminateApplicationNotification {
                    if let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                       app.processIdentifier == self.destination?.processIdentifier { self.gate.invalidate() }
                } else { self.gate.invalidate() }
            })
        }
        installHotkey()
        // Cooperative synthetic-fixture entry only. This is not proof of the
        // shipping hotkey/menu paths and is not an external shipping helper.
        observers.append(DistributedNotificationCenter.default().addObserver(
            forName: .init("com.copystory.paste-experiment.invoke"), object: run, queue: .main
        ) { [weak self] _ in self?.invoke(source: "fixtureBridge") })
        record("launched", ["postEventPreflight": permissionStatus(),
                             "board": board.name.rawValue, "log": logURL.path,
                             "bundle": Bundle.main.bundleIdentifier ?? "", "bundlePath": Bundle.main.bundlePath,
                             "parentPID": getppid(), "generalPasteboardUsed": false])
        // Only launch with this flag after the human approves this exact app's
        // PostEvent request. Ordinary launch never prompts or changes permission.
        if CommandLine.arguments.contains("--request-post-event") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in self?.requestPermission() }
        }
        if CommandLine.arguments.contains("--preflight-only") { NSApp.terminate(nil) }
    }
    func installHotkey() {
        let context = Unmanaged.passUnretained(self).toOpaque()
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, ptr in
            guard let ptr else { return noErr }
            Unmanaged<Experiment>.fromOpaque(ptr).takeUnretainedValue().invoke(source: "hotkey")
            return noErr
        }, 1, &type, context, nil)
        // Exclusive registration fails on conflict; never steal/share the
        // installed app's default shortcut or press it after a failed claim.
        let keyCode = shortcut == "isolated" ? kVK_ANSI_P : kVK_ANSI_H
        let modifiers = shortcut == "isolated" ? cmdKey | controlKey | optionKey :
            (shortcut == "default" ? cmdKey | shiftKey : cmdKey | shiftKey | optionKey)
        let label = shortcut == "isolated" ? "Command–Control–Option–P" :
            (shortcut == "default" ? "Command–Shift–H" : "Command–Option–Shift–H")
        let result = RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers),
                                         EventHotKeyID(signature: 0x4353504c, id: 1),
                                         GetApplicationEventTarget(), UInt32(kEventHotKeyExclusive), &hotkey)
        record("hotkeyRegistered", ["status": result,
            "shortcut": label,
            "exclusive": true])
        if result != noErr { status.stringValue = "Shortcut unavailable (\(result)); use CS Paste Lab in the menu bar." }
    }
    func makePanel() {
        panel = ExperimentPanel(contentRect: NSRect(x: 500, y: 300, width: 530, height: 420),
                                styleMask: [.titled, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "CS Paste Lab — SYNTHETIC ONLY"
        panel.isFloatingPanel = true; panel.hidesOnDeactivate = false; panel.level = .floating
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        let title = NSTextField(wrappingLabelWithString: "CS Paste Lab — SYNTHETIC ONLY · named test clipboard · permission requests require approval")
        let permission = NSButton(title: "Request PostEvent (approval required)", target: self, action: #selector(requestPermission))
        let refresh = NSButton(title: "Refresh permission status", target: self, action: #selector(refreshPermission))
        delay.addItems(withTitles: ["Settle: 100 ms", "Settle: 2 s (race fixture)", "Settle: 15 s (manual menu test)"])
        delay.setAccessibilityLabel("Synthetic dispatch settling delay")
        let repeatTest = NSButton(title: "Request twice (repeat test)", target: self, action: #selector(repeatPasteTest))
        let testControls = NSStackView(views: [delay, repeatTest]); testControls.orientation = .horizontal
        search.placeholderString = "Search (Return requests the selected synthetic item)"
        // NSControl's end-editing action can fire on a focus change. Only the
        // explicit Return command is paste; resigning search focus is not.
        search.delegate = self
        variable.placeholderString = "Library variable; Return keeps editing"
        variable.setAccessibilityLabel("Synthetic library topic")
        let column = NSTableColumn(identifier: .init("item")); column.title = "Synthetic history / library"
        table.addTableColumn(column); table.headerView = nil; table.rowHeight = 30
        table.dataSource = self; table.delegate = self; table.target = self; table.doubleAction = #selector(paste)
        table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        let scroll = NSScrollView(); scroll.documentView = table; scroll.hasVerticalScroller = true
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.heightAnchor.constraint(equalToConstant: 105).isActive = true
        let paste = NSButton(title: "Request paste in fixture", target: self, action: #selector(paste))
        let copy = NSButton(title: "Copy to test board", target: self, action: #selector(copyOnly))
        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancel))
        cancel.keyEquivalent = "\u{1b}"
        let buttons = NSStackView(views: [paste, copy, cancel]); buttons.orientation = .horizontal
        let permissionControls = NSStackView(views: [permission, refresh]); permissionControls.orientation = .horizontal
        let stack = NSStackView(views: [title, permissionControls, testControls, search, scroll, variable, buttons, status])
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView!.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: panel.contentView!.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: panel.contentView!.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: panel.contentView!.topAnchor, constant: 16),
            scroll.widthAnchor.constraint(equalTo: stack.widthAnchor), search.widthAnchor.constraint(equalTo: stack.widthAnchor),
            variable.widthAnchor.constraint(equalTo: stack.widthAnchor), status.widthAnchor.constraint(equalTo: stack.widthAnchor)])
    }
    func numberOfRows(in tableView: NSTableView) -> Int { 3 }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        NSTextField(labelWithString: ["History: Unicode / multiline text", "History: 2×2 synthetic image", "Library: rendered topic prompt"][row])
    }
    func tableViewSelectionDidChange(_ note: Notification) {
        if writing { gate.invalidate(); record("selectionChangedDuringRequest") }
    }
    func control(_ control: NSControl, textView: NSTextView, doCommandBy command: Selector) -> Bool {
        guard control === search, command == #selector(NSResponder.insertNewline(_:)) else { return false }
        paste(); return true
    }
    @objc func statusClicked() {
        record("statusClicked", NSApp.currentEvent.map(mouseDetails) ?? ["eventType": "action"])
        guard !writing else { record("menuIgnoredDuringRequest"); return }
        let event = NSApp.currentEvent
        let contextClick = event?.type == .rightMouseUp ||
            (event?.type == .leftMouseUp && event?.modifierFlags.contains(.control) == true)
        if contextClick {
            if panel.isVisible { cancel() }
            captureDestination(source: "menuRight")
            let generation = gate.generation
            contextMenuOpenChosen = false
            let menu = NSMenu()
            for (title, selector) in [("Open synthetic panel", #selector(chooseContextMenuOpen)), ("Quit experiment", #selector(quit))] {
                let item = NSMenuItem(title: title, action: selector, keyEquivalent: ""); item.target = self; menu.addItem(item)
            }
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: 0), in: statusItem.button!)
            // The action runs inside menu tracking. Let AppKit finish restoring
            // menu focus before making the nonactivating panel key. Keep this
            // invocation's capture and sticky cancellation; never recapture an
            // earlier app or invalidate a newer invocation on menu dismissal.
            record("contextMenuClosed", ["openChosen": contextMenuOpenChosen,
                                         "generation": generation])
            guard gate.generation == generation else { return }
            if contextMenuOpenChosen { openCaptured() }
            else { gate.invalidate(); destination = nil; record("contextMenuCancelled") }
        } else { invoke(source: "menuLeft") }
    }
    @objc func chooseContextMenuOpen() {
        contextMenuOpenChosen = true
        record("contextMenuOpenChosen", ["generation": gate.generation])
    }
    func mouseDetails(_ event: NSEvent) -> [String: Any] {
        ["eventType": String(describing: event.type), "eventTimestamp": event.timestamp,
         "buttonNumber": event.buttonNumber, "controlClick": event.modifierFlags.contains(.control),
         "windowNumber": event.windowNumber, "appActive": NSApp.isActive,
         "panelKey": panel.isKeyWindow, "panelVisible": panel.isVisible,
         "statusWindowKey": statusItem.button?.window?.isKeyWindow ?? false]
    }
    func captureDestination(source: String) {
        invocationSource = source
        let front = NSWorkspace.shared.frontmostApplication
        destination = front.flatMap { fixtures.contains($0.bundleIdentifier ?? "") ? $0 : nil }
        gate.open(destination: destination?.processIdentifier, now: ProcessInfo.processInfo.systemUptime)
        record("invoked", ["destinationPID": destination?.processIdentifier ?? -1,
                           "source": source, "generation": gate.generation])
    }
    @objc func openCaptured() {
        panel.makeKeyAndOrderFront(nil); panel.makeFirstResponder(search)
        status.stringValue = "PostEvent preflight: \(CGPreflightPostEventAccess()). Target PID: \(destination?.processIdentifier ?? -1)."
        record("panelOpened", ["panelKey": panel.isKeyWindow, "appActive": NSApp.isActive,
                               "source": invocationSource, "generation": gate.generation])
    }
    func invoke(source: String) {
        record("invocationAction", ["source": source, "panelVisible": panel.isVisible])
        guard !writing else { return }
        if panel.isVisible { cancel(); return }
        captureDestination(source: source); openCaptured()
    }
    func write() -> Bool {
        board.clearContents()
        switch table.selectedRow {
        case 1:
            let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8,
                                      samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                      bytesPerRow: 8, bitsPerPixel: 32)!
            // Deterministic RGBA test vector: avoid named NSColor conversion
            // when constructing the pixels whose fidelity we are measuring.
            guard let pixels = rep.bitmapData else { return false }
            for y in 0..<2 { for x in 0..<2 {
                let offset = y * rep.bytesPerRow + x * 4
                pixels[offset] = x == y ? 255 : 0
                pixels[offset + 1] = 0
                pixels[offset + 2] = 0
                pixels[offset + 3] = x == y ? 255 : 0
            } }
            return board.setData(rep.representation(using: .png, properties: [:])!, forType: .png)
        case 2: return board.setString("Discuss \(variable.stringValue).\nSynthetic library prompt.", forType: .string)
        default: return board.setString("CS synthetic \(run)\nUnicode: café 🧪\ttrailing spaces  ", forType: .string)
        }
    }
    @objc func copyOnly() {
        guard !writing else { return }
        gate.invalidate(); status.stringValue = write() ? "Copied to test board. Use fixture’s Manual test-board paste." : "Test-board write failed."
        record("copyOnly", ["changeCount": board.changeCount])
    }
    @objc func cancel() { gate.invalidate(); panel.orderOut(nil); record("cancelled") }
    @objc func quit() { NSApp.terminate(nil) }
    @objc func refreshPermission() {
        let granted = permissionStatus()
        status.stringValue = "PostEvent preflight: \(granted). \(Bundle.main.bundleIdentifier ?? ""). If just granted, relaunch this exact build before testing."
        record("permissionRefreshed", ["postEventPreflight": granted])
    }
    @objc func requestPermission() {
        // The human must approve this operation first. Activation here is for
        // the permission request only; it invalidates any paste destination.
        gate.invalidate(); NSApp.activate(ignoringOtherApps: true)
        let granted = CGRequestPostEventAccess()
        record("explicitPermissionRequest", ["granted": granted])
        // Both PostEvent and AX appear in the Accessibility permission pane;
        // Privacy_PostEvent did not select a usable pane on this host.
        if !granted, let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            record("permissionSettingsOpened", ["opened": NSWorkspace.shared.open(url)])
        }
    }
    @objc func repeatPasteTest() {
        // Explicit synthetic test control: exercise two delivered requests in
        // the running app even though the first normally hides the panel.
        // Both use the unchanged handler/guards; never create a new capture.
        record("repeatTestStarted", ["generation": gate.generation, "requestCount": 2])
        paste()
        paste()
        record("repeatTestFinished", ["generation": gate.generation])
    }
    @objc func paste() {
        record("explicitPasteAction", ["eventType": NSApp.currentEvent.map { String(describing: $0.type) } ?? "accessibility-or-action"])
        guard !writing else { record("repeatIgnored"); return }
        guard gate.canBegin else { record("consumedActionIgnored"); return }
        writing = true
        guard write() else { gate.invalidate(); writing = false; record("clipboardWriteFailed"); return }
        let writeCount = board.changeCount
        guard let token = gate.begin(writeCount: writeCount) else {
            writing = false; status.stringValue = "Request consumed or test-board write failed. Reopen to choose again."; return
        }
        panel.orderOut(nil)
        // A fixed single settling interval, followed by fresh checks; no retries.
        let settling: Double
        switch delay.indexOfSelectedItem {
        case 1: settling = 2
        case 2: settling = 15 // Human-paced test only; the 30-second gate expiry still applies.
        default: settling = 0.1
        }
        record("settling", ["seconds": settling, "token": token])
        DispatchQueue.main.asyncAfter(deadline: .now() + settling) { [self] in
            let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
            let permission = CGPreflightPostEventAccess()
            let flags = CGEventSource.flagsState(.combinedSessionState)
            let released = flags.intersection([.maskCommand, .maskShift, .maskAlternate, .maskControl]).isEmpty
            let outcome = gate.consume(token: token, now: ProcessInfo.processInfo.systemUptime,
                                       frontmost: front, destinationAlive: destination?.isTerminated == false,
                                       currentWrite: board.changeCount, permission: permission, modifiersReleased: released)
            record("dispatchDecision", ["outcome": outcome.rawValue, "postEventPreflight": permission,
                                         "destinationPID": destination?.processIdentifier ?? -1,
                                         "changeCount": board.changeCount])
            defer { writing = false }
            guard outcome == .dispatch, let destination,
                  getppid() == 1, // Harness evidence must use a LaunchServices launch, not inherited CLI consent.
                  fixtures.contains(destination.bundleIdentifier ?? ""), !destination.isTerminated,
                  NSWorkspace.shared.frontmostApplication?.processIdentifier == destination.processIdentifier,
                  CGPreflightPostEventAccess(), board.changeCount == writeCount,
                  let source = CGEventSource(stateID: .privateState),
                  let down = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true),
                  let up = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false) else {
                status.stringValue = "No event: \(outcome.rawValue). Synthetic payload remains on test board for manual fallback."; return
            }
            down.flags = .maskCommand; up.flags = .maskCommand
            down.setIntegerValueField(.keyboardEventAutorepeat, value: 0)
            down.setIntegerValueField(.eventSourceUserData, value: Int64(token))
            up.setIntegerValueField(.eventSourceUserData, value: Int64(token))
            let delivered = EventDeliveryBoundary.deliver(validate: {
                gate.generation == token && !destination.isTerminated &&
                NSWorkspace.shared.frontmostApplication?.processIdentifier == destination.processIdentifier &&
                board.changeCount == writeCount && CGPreflightPostEventAccess()
            }, post: { event in
                switch event {
                case .down: down.postToPid(destination.processIdentifier)
                case .up: up.postToPid(destination.processIdentifier)
                }
            })
            guard delivered else { record("finalDispatchCancelled"); return }
            record("eventPairPosted", ["token": token, "route": "postToPid", "destinationPID": destination.processIdentifier])
            status.stringValue = "Paste requested; inspect fixture insertion log. No success acknowledgement inferred."
        }
    }
}

guard let i = CommandLine.arguments.firstIndex(of: "--run"), CommandLine.arguments.indices.contains(i + 1),
      let uuid = UUID(uuidString: CommandLine.arguments[i + 1]) else { fatalError("Requires --run UUID") }
let experiment = Experiment(run: uuid.uuidString)
NSApplication.shared.delegate = experiment
NSApplication.shared.run()
