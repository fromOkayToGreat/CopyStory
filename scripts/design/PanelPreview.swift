// Native fixture renderer linking only the inert SwiftPM configuration.
// Never starts AppDelegate/AppModel or touches a pasteboard. Interactive mode
// orders a separate sample-data preview window; batch mode renders offscreen.
import AppKit
import SwiftUI
@testable import CopyStoryCore
@testable import CopyStory

final class PreviewBackdrop: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSGradient(colors: [NSColor(red: 0.91, green: 0.77, blue: 0.59, alpha: 1), .darkGray,
                            NSColor(red: 0.80, green: 0.65, blue: 0.48, alpha: 1)])!.draw(in: bounds, angle: -35)
    }
}
@main struct PanelPreview {
    @MainActor static func main() {
        let app = NSApplication.shared
        Task { @MainActor in
            do { try await run(); app.terminate(nil) }
            catch { fputs("Preview failed: \(error)\n", stderr); exit(1) }
        }
        app.run()
    }
    @MainActor static func run() async throws {
        precondition(!NativeIntegrationGates.appLaunchEnabled && !NativeIntegrationGates.clipboardEnabled && !NativeIntegrationGates.observationEnabled && !NativeIntegrationGates.postingConsentEnabled && !NativeIntegrationGates.shortcutEnabled)
        let interactive = CommandLine.arguments.count == 1
        let output = interactive ? Bundle.main.bundleURL.deletingLastPathComponent() : URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let root = output.appendingPathComponent("fixture-\(UUID().uuidString)")
        let suite = "com.copystory.design-fixture.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        let app = NSApplication.shared
        app.setActivationPolicy(interactive ? .accessory : .prohibited)
        app.applicationIconImage = interactive ? NSImage(contentsOf: Bundle.main.url(forResource: "CopyStory", withExtension: "icns")!) : NSImage(contentsOfFile: CommandLine.arguments[2])
        let store = try HistoryStore(directory: root)
        let model = AppModel(store: store, demo: false, preferenceStore: defaults)
        // Fixture readiness only. No system permission is queried or changed.
        model.accessibilityGranted = true
        model.onboardingComplete = true // Fixture status only; start() is never called.
        let texts = ["Notes for the next release", "Make room for the work that matters.", "Summarize this article in three clear points.", "Design references", "https://example.com/ideas"]
        for (i, text) in texts.enumerated() {
            _ = try await store.capture(CapturePayload(text: text, sourceApp: i == 0 ? "Notes" : i == 2 ? "ChatGPT" : "Safari", capturedAt: Date().addingTimeInterval(-Double([240,1080,1920,3600,7200][i]))), limits: HistoryLimits())
        }
        await model.refresh()
        model.selectedID = model.items[3].id
        let initial = model.items
        let window = HistoryPanel(contentRect: NSRect(origin: .zero, size: MainPanelDesign.size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.isOpaque = false; window.backgroundColor = .clear
        var records: [String] = []
        func render(_ name: String, size: NSSize = MainPanelDesign.size, dark: Bool = false, reduce: Bool = false) async throws {
            window.setContentSize(interactive ? NSSize(width: size.width + 80, height: size.height + 120) : size)
            window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            let host = NSHostingView(rootView: HistoryView(model: model)
                .environment(\.colorScheme, dark ? .dark : .light)
                .environment(\.panelTransparencyOverride, reduce ? true : nil))
            let glass = NSGlassEffectView(frame: NSRect(origin: .zero, size: size))
            glass.cornerRadius = MainPanelDesign.radius
            glass.contentView = host
            // Clip the backing surface too; the material radius alone leaves square shadow corners.
            glass.wantsLayer = true
            glass.layer?.cornerRadius = MainPanelDesign.radius
            glass.layer?.masksToBounds = true
            if interactive {
                let backdrop = PreviewBackdrop(frame: NSRect(origin: .zero, size: window.frame.size))
                glass.setFrameOrigin(NSPoint(x: 40, y: 70))
                backdrop.addSubview(glass)
                window.contentView = backdrop
                window.title = "CopyStory Design Preview — isolated sample data"
                window.center(); window.makeKeyAndOrderFront(nil); app.activate()
            } else { window.contentView = glass }
            glass.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(180))
            glass.layoutSubtreeIfNeeded()
            guard let bitmap = glass.bitmapImageRepForCachingDisplay(in: glass.bounds) else { fatalError("Missing bitmap") }
            glass.cacheDisplay(in: glass.bounds, to: bitmap)
            guard let data = bitmap.representation(using: .png, properties: [:]) else { fatalError("Missing PNG") }
            try data.write(to: output.appendingPathComponent(name + ".png"))
            records.append("\(name): \(Int(glass.bounds.width)) × \(Int(glass.bounds.height)) points; native NSHostingView + NSGlassEffectView offscreen render")
        }
        try await render("01-history-light")
        try await render("02-history-dark", dark: true)
        try await render("03-reduced-transparency", reduce: true)
        model.query = "unmatched-fixture-query"; await model.refresh()
        try await render("04-search-empty")
        model.query = "release"; await model.refresh()
        try await render("05-search-match")
        model.query = ""; model.filter = .pinned; await model.refresh()
        try await render("06-pinned-empty")
        model.filter = .all
        _ = try await store.capture(CapturePayload(text: "A longer copied note that deliberately spans multiple lines so we can check the content hierarchy and truncation while keeping the full footer accessible.\nSecond paragraph of neutral sample content.", sourceApp: "Notes"), limits: HistoryLimits())
        await model.refresh(); model.selectedID = model.items.first?.id
        try await render("07-long-selected")
        model.captureMessage = "Sample capture warning: recording needs attention."
        model.capacityBlocked = true; model.accessibilityGranted = false
        try await render("08-status-banners")
        model.captureMessage = nil; model.capacityBlocked = false; model.accessibilityGranted = true
        try await render("09-small-screen", size: MainPanelDesign.frame(in: NSRect(x: 0, y: 0, width: 800, height: 600)).size)
        let blank = HistoryItem(id: "synthetic-blank-preview", kind: .text, preview: "", hasText: true,
            sourceApp: "Notes", sourceBundleID: nil, capturedAt: Date(), isPinned: false,
            byteCount: 1, pixelWidth: nil, pixelHeight: nil)
        model.items = [blank]; model.selectedID = blank.id
        try await render("13-empty-preview-selected")
        let image = NSBitmapImageRep(data: app.applicationIconImage.tiffRepresentation!)!.representation(using: .png, properties: [:])!
        _ = try await store.capture(CapturePayload(imageData: image, thumbnailData: image, pixelWidth: 512, pixelHeight: 512, sourceApp: "Preview"), limits: HistoryLimits())
        model.filter = .images; await model.refresh()
        try await render("14-images-filter")
        model.filter = .all; model.items = initial; model.count = initial.count; model.selectedID = initial[3].id
        if let library = model.library.store {
            try await library.create(LibraryEntry(title: "Concise summary", template: "Summarize this text in three points."))
        }
        model.selectSection(.library); await model.library.refresh()
        try await render("10-library-preserved")
        for _ in 0..<12 {
            model.selectSection(.history); model.selectSection(.library)
        }
        model.selectSection(.history); try await Task.sleep(for: .milliseconds(100)); model.items = initial; model.count = initial.count
        try await render("11-return-to-history")
        // Repeated native window content attach/detach; no window activation.
        for _ in 0..<12 { window.contentView = NSView(); window.setContentSize(MainPanelDesign.size) }
        try await render("12-reattached-history")
        try records.joined(separator: "\n").write(to: output.appendingPathComponent("renders.txt"), atomically: true, encoding: .utf8)
        print("Rendered \(records.count) inert native fixtures. No app delegate, recording, clipboard, permission, login, shortcut or posting effects.")
        if interactive {
            func controls() {
                guard let content = window.contentView else { return }
                let bar = NSHostingView(rootView: HStack(spacing: 8) {
                    ForEach(["Light", "Dark", "Reduced", "Small", "Long", "Library", "Close"], id: \.self) { title in
                        Button(title) {
                            if title == "Close" { NSApp.terminate(nil); return }
                            Task { @MainActor in
                                do {
                                    model.query = ""; model.filter = .all
                                    model.selectSection(title == "Library" ? .library : .history)
                                    await model.refresh()
                                    try await Task.sleep(for: .milliseconds(100)) // settle the 60 ms search debounce
                                    if title != "Long" { model.items = initial; model.count = initial.count }
                                    model.selectedID = title == "Long" ? model.items.first?.id : initial[3].id
                                    try await render("interactive-" + title.lowercased(),
                                        size: title == "Small" ? MainPanelDesign.frame(in: NSRect(x: 0, y: 0, width: 800, height: 600)).size : MainPanelDesign.size,
                                        dark: title == "Dark", reduce: title == "Reduced")
                                    controls()
                                } catch { fputs("Preview control failed: \(error)\n", stderr) }
                            }
                        }.buttonStyle(.bordered)
                    }
                })
                bar.frame = NSRect(x: 20, y: 12, width: window.frame.width - 40, height: 28)
                content.addSubview(bar)
            }
            controls()
            while true { try await Task.sleep(for: .seconds(3600)) }
        }
        window.contentView = nil
    }
}
