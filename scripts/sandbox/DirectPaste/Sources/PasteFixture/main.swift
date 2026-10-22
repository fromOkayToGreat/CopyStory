import AppKit

// Command-V deliberately reads ONLY the named test board. This instrumented
// fixture proves routing/insertion in itself, not standard general-board paste.
final class SyntheticTextView: NSTextView {
    var didPaste: ((SyntheticTextView) -> Void)?
    var controlID = ""
    override func paste(_ sender: Any?) { didPaste?(self) }
}

final class Fixture: NSObject, NSApplicationDelegate {
    let run: String
    let role: String
    let board: NSPasteboard
    let logURL: URL
    var windows: [NSWindow] = []
    var views: [SyntheticTextView] = []
    var insertions = 0
    var monitor: Any?
    var focusObservers: [NSObjectProtocol] = []
    init(run: String, role: String) {
        self.run = run; self.role = role
        board = NSPasteboard(name: .init("com.copystory.paste-experiment.\(run)"))
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PasteExperiment/\(run)", isDirectory: true)
        try! FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        logURL = root.appendingPathComponent("events.jsonl")
        super.init()
    }
    func record(_ name: String, _ details: [String: Any] = [:]) {
        var value = details; value["event"] = name; value["run"] = run; value["role"] = role
        value["uptime"] = ProcessInfo.processInfo.systemUptime
        value["pid"] = ProcessInfo.processInfo.processIdentifier
        if let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) {
            if !FileManager.default.fileExists(atPath: logURL.path) { FileManager.default.createFile(atPath: logURL.path, contents: nil) }
            if let h = try? FileHandle(forWritingTo: logURL) {
                h.seekToEndOfFile(); h.write(data); h.write(Data([10])); try? h.close()
            }
            print(String(decoding: data, as: UTF8.self)); fflush(stdout)
        }
    }
    func applicationDidFinishLaunching(_ note: Notification) {
        NSApp.setActivationPolicy(.regular)
        let menu = NSMenu(); let root = NSMenuItem(); let actions = NSMenu()
        for (title, action, key) in [("Quit synthetic fixture", #selector(NSApplication.terminate(_:)), "q"),
                                     ("Open prototype (fixture bridge)", #selector(openPrototype), "h"),
                                     ("Paste from test board", #selector(manualPaste), "v")] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.target = key == "q" ? NSApp : self; actions.addItem(item)
        }
        root.submenu = actions; menu.addItem(root); NSApp.mainMenu = menu
        for w in 0..<2 { makeWindow(w) }
        for name in [NSApplication.didBecomeActiveNotification, NSApplication.didResignActiveNotification,
                     NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification] {
            focusObservers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                guard let self else { return }
                self.record("focusChanged", ["notification": note.name.rawValue,
                                             "frontmostPID": NSWorkspace.shared.frontmostApplication?.processIdentifier ?? -1,
                                             "appActive": NSApp.isActive, "keyWindow": NSApp.keyWindow?.title ?? "",
                                             "control": (NSApp.keyWindow?.firstResponder as? SyntheticTextView)?.controlID ?? ""])
            })
        }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            guard let self, event.keyCode == 9, event.modifierFlags.contains(.command) else { return event }
            self.record(event.type == .keyDown ? "commandVDown" : "commandVUp",
                        ["token": event.cgEvent?.getIntegerValueField(.eventSourceUserData) ?? 0,
                         "window": event.window?.title ?? "", "repeat": event.isARepeat])
            if event.type == .keyDown {
                // Consume locally even for unsupported responders: never invoke
                // a stock paste handler that could read the daily general board.
                self.manualPaste(nil)
            }
            return nil
        }
        windows[0].makeKeyAndOrderFront(nil); windows[0].makeFirstResponder(views[0])
        NSApp.activate(ignoringOtherApps: true)
        record("launched", ["log": logURL.path, "generalPasteboardUsed": false])
    }
    func makeWindow(_ number: Int) {
        let window = NSWindow(contentRect: NSRect(x: 70 + 60 * number, y: 150 + 90 * number, width: 440, height: 330),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "CS Synthetic \(role) · window \(number + 1)"
        window.isReleasedWhenClosed = false
        let content = window.contentView!
        for f in 0..<2 {
            let scroll = NSScrollView(frame: NSRect(x: 15, y: 170 - 130 * f, width: 410, height: 115))
            let text = SyntheticTextView(frame: scroll.bounds)
            text.controlID = "window\(number + 1).field\(f + 1)"
            text.string = "Synthetic \(role) \(text.controlID)\n"
            text.isRichText = true; text.isEditable = true
            text.setAccessibilityLabel("\(role) \(text.controlID)")
            text.didPaste = { [weak self] view in self?.insert(view) }
            scroll.documentView = text; scroll.hasVerticalScroller = true
            content.addSubview(scroll); views.append(text)
        }
        let fallback = NSButton(title: "Manual test-board paste", target: self, action: #selector(manualPaste))
        fallback.frame = NSRect(x: 15, y: 8, width: 205, height: 26); content.addSubview(fallback)
        let unsupported = NSButton(title: "Unsupported destination", target: self, action: #selector(unsupported))
        unsupported.frame = NSRect(x: 225, y: 8, width: 205, height: 26); content.addSubview(unsupported)
        let open = NSButton(title: "Open lab (fixture bridge)", target: self, action: #selector(openPrototype))
        open.frame = NSRect(x: 15, y: 293, width: 260, height: 26); content.addSubview(open)
        let activate = NSButton(title: "Activate only", target: self, action: #selector(activateOnly))
        activate.frame = NSRect(x: 280, y: 293, width: 140, height: 26); content.addSubview(activate)
        let replace = NSButton(title: "Replace test board", target: self, action: #selector(replaceBoard))
        replace.frame = NSRect(x: 225, y: 145, width: 190, height: 25); content.addSubview(replace)
        windows.append(window); window.orderFront(nil)
    }
    @objc func unsupported(_ sender: Any?) {
        if let button = sender as? NSButton { button.window?.makeFirstResponder(button) }
        record("unsupportedSelected")
    }
    @objc func openPrototype(_ sender: Any?) {
        record("fixtureBridgeInvoked")
        // AX button activation need not activate this app. The cooperative
        // harness deliberately activates itself; it never restores another app.
        if let button = sender as? NSButton { button.window?.makeKeyAndOrderFront(nil) }
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [self] in
            record("fixtureBridgeReady", ["frontmostPID": NSWorkspace.shared.frontmostApplication?.processIdentifier ?? -1])
            DistributedNotificationCenter.default().postNotificationName(
                .init("com.copystory.paste-experiment.invoke"), object: run, userInfo: nil, deliverImmediately: true)
        }
    }
    @objc func activateOnly(_ sender: Any?) {
        if let button = sender as? NSButton { button.window?.makeKeyAndOrderFront(nil) }
        NSApp.activate(ignoringOtherApps: true)
        record("activationRequested", ["frontmostPID": NSWorkspace.shared.frontmostApplication?.processIdentifier ?? -1,
                                       "appActive": NSApp.isActive, "keyWindow": NSApp.keyWindow?.title ?? "",
                                       "control": (NSApp.keyWindow?.firstResponder as? SyntheticTextView)?.controlID ?? ""])
    }
    @objc func replaceBoard(_ sender: Any?) {
        board.clearContents()
        let written = board.setString("Intervening synthetic fixture copy", forType: .string)
        record("testBoardReplaced", ["written": written, "changeCount": board.changeCount])
    }
    @objc func manualPaste(_ sender: Any?) {
        let window = (sender as? NSView)?.window ?? NSApp.currentEvent?.window ?? NSApp.keyWindow
        guard let view = window?.firstResponder as? SyntheticTextView else {
            record("unsupportedPasteRefused"); return
        }
        insert(view)
    }
    func insert(_ view: SyntheticTextView) {
        if let text = board.string(forType: .string) {
            view.insertText(text, replacementRange: view.selectedRange()); insertions += 1
            record("textInserted", ["control": view.controlID, "payload": text, "result": view.string,
                                    "insertionCount": insertions, "changeCount": board.changeCount])
        } else if let png = board.data(forType: .png), let image = NSImage(data: png) {
            let attachment = NSTextAttachment(); attachment.image = image
            let location = view.selectedRange().location
            view.textStorage?.insert(NSAttributedString(attachment: attachment), at: location)
            insertions += 1
            record("imageInserted", ["control": view.controlID, "pngBase64": png.base64EncodedString(),
                                     "width": image.size.width, "height": image.size.height,
                                     "insertionCount": insertions, "changeCount": board.changeCount])
            // Inspect the attachment retrieved from the actual text storage,
            // not just the incoming board bytes. Export only synthetic pixels
            // to this run's log; never read the general clipboard or real data.
            if let stored = view.textStorage?.attribute(.attachment, at: location, effectiveRange: nil) as? NSTextAttachment,
               let tiff = stored.image?.tiffRepresentation,
               let bitmap = NSBitmapImageRep(data: tiff),
               let storedPNG = bitmap.representation(using: .png, properties: [:]) {
                record("imageAttachmentInspected", ["control": view.controlID, "location": location,
                    "storedPNGBase64": storedPNG.base64EncodedString(),
                    "pixelWidth": bitmap.pixelsWide, "pixelHeight": bitmap.pixelsHigh,
                    "insertionCount": insertions, "changeCount": board.changeCount])
            } else {
                record("imageAttachmentInspectionFailed", ["control": view.controlID, "location": location])
            }
        } else { record("unsupportedPayloadRefused") }
    }
}

guard let i = CommandLine.arguments.firstIndex(of: "--run"), CommandLine.arguments.indices.contains(i + 1),
      let uuid = UUID(uuidString: CommandLine.arguments[i + 1]),
      let role = Bundle.main.object(forInfoDictionaryKey: "PasteFixtureRole") as? String else {
    fatalError("Requires fixture bundle and --run UUID")
}
let fixture = Fixture(run: uuid.uuidString, role: role)
NSApplication.shared.delegate = fixture
NSApplication.shared.run()
