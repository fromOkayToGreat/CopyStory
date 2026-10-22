#if APP_STORE
import AppKit
import ApplicationServices
import Carbon
import CopyStoryCore

/// Only reachable in the separate, marked feasibility bundle. Never uses the
/// general pasteboard, real stores, permission prompts, login changes or events.
enum SandboxProbe {
    struct Failure: Error { let message: String }
    @MainActor static func run() async throws {
        _ = try UpdateService.verifyPackagedRuntime()
        let args = ProcessInfo.processInfo.arguments
        func value(_ flag: String) throws -> String {
            guard let i = args.firstIndex(of: flag), args.indices.contains(i + 1) else {
                throw Failure(message: "Missing \(flag)")
            }
            return args[i + 1]
        }
        let run = try value("--probe-run")
        guard UUID(uuidString: run) != nil else { throw Failure(message: "Invalid probe run ID") }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        guard support.path.contains("/Library/Containers/com.copystory.sandbox-feasibility/") else {
            throw Failure(message: "Application Support is not inside the probe container")
        }
        let root = support.appendingPathComponent("Probe-\(run)", isDirectory: true)
        let read = args.contains("--probe-read")
        if !read, FileManager.default.fileExists(atPath: root.path) {
            throw Failure(message: "Refusing to overwrite an existing probe")
        }
        if read, !FileManager.default.fileExists(atPath: root.path) {
            throw Failure(message: "Missing prior probe store")
        }
        let history = try HistoryStore(directory: root.appendingPathComponent("History"))
        let library = try LibraryStore(directory: root.appendingPathComponent("Library"))
        if !read {
            _ = try await history.capture(CapturePayload(text: "sandbox synthetic history"), limits: HistoryLimits())
            let entry = LibraryEntry(title: "Sandbox synthetic prompt", template: "Hello {{name}}",
                                     variables: [TemplateVariable(name: "name", defaultValue: "sandbox")])
            try await library.create(entry)
        }
        let rows = try await history.search(query: "sandbox", filter: .all)
        let entries = try await library.search(query: "Sandbox synthetic")
        guard rows.count == 1, entries.count == 1,
              try entries[0].render(values: entries[0].defaultValues) == "Hello sandbox" else {
            throw Failure(message: "Persistence or template rendering mismatch")
        }
        if read {
            try await history.clear(includePinned: true)
            guard try await library.search(query: "Sandbox synthetic").count == 1 else {
                throw Failure(message: "History clear affected library")
            }
        }
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        var captured: [CapturePayload] = []
        let monitor = ClipboardMonitor(onCapture: { captured.append($0) }, onStatus: { _ in },
            pasteboard: board, sourceApplication: { ClipboardSource(name: "Sandbox probe", bundleID: "test.probe") })
        monitor.start()
        defer { monitor.stop() }
        board.clearContents()
        guard board.setString("synthetic named-board capture", forType: .string) else {
            throw Failure(message: "Named pasteboard write failed")
        }
        monitor.poll()
        guard captured.first?.text == "synthetic named-board capture" else {
            throw Failure(message: "Named pasteboard capture failed (session may be locked)")
        }
        // Register an uncommon shortcut and immediately release it. This does not
        // establish that the normal shortcut triggers the UI in an interactive session.
        let hotkey = GlobalHotKey(onTrigger: {})
        try hotkey.register(keyCode: UInt32(kVK_F19), modifiers: UInt32(cmdKey | controlKey | optionKey | shiftKey))
        hotkey.unregister()
        let outside = try value("--outside-fixture")
        var denied = false
        do { _ = try Data(contentsOf: URL(fileURLWithPath: outside)) }
        catch { denied = (error as NSError).domain == NSCocoaErrorDomain && (error as NSError).code == NSFileReadNoPermissionError }
        guard denied else { throw Failure(message: "External synthetic fixture was not denied with a permission error") }
        // Read only the status, never the returned focused application or content.
        // No TCC prompt and no synthetic key events. A failure without TCC consent
        // alone cannot distinguish TCC from sandbox restrictions.
        var focused: CFTypeRef?
        let ax = AXUIElementCopyAttributeValue(AXUIElementCreateSystemWide(), kAXFocusedApplicationAttribute as CFString, &focused)
        var report: [String: Any] = ["phase": read ? "reopen-and-clear" : "write",
            "containerStorage": true, "historyAndLibrary": true, "namedPasteboardCapture": true,
            "hotkeyRegistration": true, "outsideReadDenied": denied,
            "accessibilityTrusted": AXIsProcessTrusted(), "accessibilityQueryResult": ax.rawValue,
            "pasteEventsPosted": false, "automaticPasteVerified": false]
        if args.contains("--ax-target-pid") {
            guard let pid = Int32(try value("--ax-target-pid")), pid > 0 else { throw Failure(message: "Invalid target PID") }
            let target = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(target, 0.5)
            for attribute in [kAXFocusedWindowAttribute, kAXFocusedUIElementAttribute] {
                var element: CFTypeRef?
                report[attribute] = AXUIElementCopyAttributeValue(target, attribute as CFString, &element).rawValue
            }
        }
        let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
#endif
