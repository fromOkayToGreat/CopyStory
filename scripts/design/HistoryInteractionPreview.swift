// Inert native UI fixture. Compile against the testable reconstruction objects.
// No AppDelegate, start(), clipboard, global shortcut, login or permission paths.
import AppKit
import SwiftUI
import CopyStoryCore
@testable import CopyStory

private struct FixtureControls: View {
    let model: AppModel
    var body: some View {
        HStack {
            Text("Isolated sample data").font(.caption)
            Button("Reveal sample action") { model.revealedHistoryID = model.items.first?.id }
            Button("Close QA") { NSApp.terminate(nil) }
        }.padding(12)
    }
}

@main struct HistoryInteractionPreview {
    @MainActor static func main() {
        let app = NSApplication.shared
        Task { @MainActor in
            do { try await run() }
            catch { fputs("Fixture setup failed\n", stderr); app.terminate(nil) }
        }
        app.run()
    }

    @MainActor static func run() async throws {
        precondition(!NativeIntegrationGates.appLaunchEnabled && !NativeIntegrationGates.clipboardEnabled &&
            !NativeIntegrationGates.observationEnabled && !NativeIntegrationGates.postingConsentEnabled && !NativeIntegrationGates.shortcutEnabled)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("CopyStory-Interaction-QA-\(UUID())")
        let suite = "com.copystory.interaction-qa.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        let store = try HistoryStore(directory: root)
        let model = AppModel(store: store, demo: false, preferenceStore: defaults)
        model.accessibilityGranted = true // View-only fixture; no OS access requested.
        model.onboardingComplete = true // Never starts recording.
        for index in 1...24 {
            _ = try await store.capture(CapturePayload(text: index == 1 ? "Notes for the next release" : "Sample history item \(index) — neutral text for interaction checks",
                sourceApp: "Sample", capturedAt: Date().addingTimeInterval(Double(-index * 120))), limits: .init())
        }
        if let library = model.library.store {
            try await library.create(LibraryEntry(title: "Sample summary", template: "Summarize {{text}} clearly.", variables: [TemplateVariable(name: "text")]))
        }
        await model.refresh()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 810),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "CopyStory Mouse QA — r3 sample content"
        window.isReleasedWhenClosed = false
        let backing = NSView(frame: NSRect(x: 0, y: 0, width: 620, height: 810))
        let glass = NSGlassEffectView(frame: NSRect(x: 40, y: 70, width: 540, height: 716))
        glass.cornerRadius = MainPanelDesign.radius
        glass.contentView = HistoryHostingView(rootView: HistoryView(model: model))
        glass.wantsLayer = true
        glass.layer?.cornerRadius = MainPanelDesign.radius
        glass.layer?.masksToBounds = true
        backing.addSubview(glass)
        let controls = NSHostingView(rootView: FixtureControls(model: model))
        controls.frame = NSRect(x: 20, y: 8, width: 580, height: 44)
        backing.addSubview(controls)
        window.contentView = backing
        var menuDepth = 0
        let observers = [(NSMenu.didBeginTrackingNotification, 1), (NSMenu.didEndTrackingNotification, -1)].map { name, delta in
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { _ in menuDepth = max(0, menuDepth + delta) }
        }
        let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard window.isKeyWindow, window.attachedSheet == nil, menuDepth == 0 else { return event }
            if model.handleHistoryDeletionKey(event, responder: window.firstResponder) { return nil }
            if model.library.section == .history {
                if event.keyCode == 125 { model.moveSelection(1); return nil }
                if event.keyCode == 126 { model.moveSelection(-1); return nil }
            }
            return event
        }
        let close = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { _ in NSApp.terminate(nil) }
        let cleanup = NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { _ in
            UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        NSApp.applicationIconImage = NSImage(contentsOf: Bundle.main.url(forResource: "CopyStory", withExtension: "icns")!)
        NSApp.setActivationPolicy(.accessory)
        window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate()
        // Retain local fixture state while its run loop handles only this window.
        while window.isVisible { try await Task.sleep(for: .seconds(1)) }
        if let monitor { NSEvent.removeMonitor(monitor) }
        for token in observers + [close, cleanup] { NotificationCenter.default.removeObserver(token) }
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: root)
        NSApp.terminate(nil)
    }
}
