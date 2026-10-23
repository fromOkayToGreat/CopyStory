import AppKit
import ApplicationServices
import Dispatch
import ImageIO
import Testing
import UniformTypeIdentifiers
import CopyStoryCore
@testable import CopyStory

@Suite(.serialized)
struct HardeningTests {
    @Test func expirationRemovesOldTextAndImageFilesButPreservesPinsAndBoundary() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try HistoryStore(directory: directory)
        let cutoff = Date(timeIntervalSince1970: 1_000_000)
        let png = try image()
        try await add("expired text", at: cutoff.addingTimeInterval(-1), to: store)
        try await add("expired image", at: cutoff.addingTimeInterval(-1), image: png, to: store)
        try await add("pinned image", at: cutoff.addingTimeInterval(-1), image: png, pinned: true, to: store)
        try await add("boundary", at: cutoff, to: store)
        try await add("fresh", at: cutoff.addingTimeInterval(1), to: store)
        #expect(try await store.expireUnpinned(before: cutoff) == 2)
        let rows = try await store.search(query: "", filter: .all)
        #expect(Set(rows.map(\.preview)) == Set(["pinned image", "boundary", "fresh"]))
        let pin = try #require(rows.first { $0.isPinned })
        #expect(try await store.payload(id: pin.id).imageData != nil)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.appendingPathComponent("Images").path).count == 2)
        #expect(try await store.expireUnpinned(before: cutoff) == 0)
    }

    @Test func invalidExpirationDoesNotDeleteData() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try HistoryStore(directory: directory)
        try await add("keep", at: Date(timeIntervalSince1970: 1), to: store)
        for timestamp in [Double.nan, Double.infinity, -Double.infinity] {
            do {
                _ = try await store.expireUnpinned(before: Date(timeIntervalSince1970: timestamp))
                Issue.record("A non-finite expiration boundary must be rejected.")
            } catch HistoryStoreError.invalidLimits {} catch { Issue.record("Unexpected error: \(error)") }
        }
        #expect(try await store.stats().count == 1)
    }

    @MainActor
    @Test func retentionRejectsDelayedOldCapturesAndKeepsNewCopies() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try HistoryStore(directory: directory)
        let (defaults, suite) = preferences()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(7, forKey: "retentionDays")
        let now = Date()
        let old = now.addingTimeInterval(-8 * 86_400)
        try await add("old unpinned", at: old, to: store)
        try await add("old pinned", at: old, pinned: true, to: store)
        let model = AppModel(store: store, demo: true, preferenceStore: defaults)
        await model.expireHistory(now: now).value
        await model.save(CapturePayload(text: "late expired capture", capturedAt: old)).value
        await model.save(CapturePayload(text: "new capture")).value
        let retained = try await store.search(query: "", filter: .all)
        #expect(Set(retained.map(\.preview)) == Set(["old pinned", "new capture"]), "limits=\(model.maxItems)/\(model.maxMB), retention=\(model.retentionDays), status=\(model.statusMessage ?? "none")")
        model.applyRetention(days: 0)
        await model.save(CapturePayload(text: "retention disabled", capturedAt: old)).value
        #expect(try await store.stats().count == 3)
        #expect(defaults.integer(forKey: "retentionDays") == 0)
        model.applyRetention(days: -1)
        #expect(model.retentionDays == 0)
    }

    @MainActor
    @Test func queuedCaptureRechecksAppExclusion() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try HistoryStore(directory: directory)
        let (defaults, suite) = preferences()
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppModel(store: store, demo: true, preferenceStore: defaults)
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        model.monitor = ClipboardMonitor(onCapture: { _ in }, onStatus: { _ in }, pasteboard: board)
        let pending = model.save(CapturePayload(text: "private", sourceBundleID: "test.private"))
        model.setExcludedApps(["test.private"])
        await pending.value
        #expect(try await store.stats().count == 0)
        #expect(defaults.stringArray(forKey: "excludedAppBundleIDs") == ["test.private"])
        model.setExcludedApps([])
        await model.save(CapturePayload(text: "allowed", sourceBundleID: "test.private")).value
        #expect(try await store.stats().count == 1)
    }

    @MainActor
    @Test func exclusionsSkipTextAndImagesBeforeDecoding() throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        var source = ClipboardSource(name: "Private app", bundleID: "test.private")
        var captures: [CapturePayload] = []
        let monitor = ClipboardMonitor(onCapture: { captures.append($0) }, onStatus: { _ in }, pasteboard: board,
                                       sourceApplication: { source }, normalizeImage: { _ in
            Issue.record("An excluded app's image must not reach decoding.")
            return .failure(.invalidOrTooLarge)
        })
        monitor.excludedBundleIDs = ["test.private"]
        monitor.start()
        defer { monitor.stop() }
        try #require(!monitor.isLocked)
        try write("excluded", image: Data([1, 2, 3]), to: board)
        monitor.poll()
        #expect(captures.isEmpty)
        #expect(!monitor.isDecoding)
        source = ClipboardSource(name: "Allowed app", bundleID: "test.allowed")
        try write("allowed", to: board)
        monitor.poll()
        #expect(captures.count == 1)
        #expect(captures.first?.sourceBundleID == "test.allowed")
    }

    @MainActor
    @Test func changingExclusionsInvalidatesPendingImage() async throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let entered = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        defer { release.signal() }
        var captures: [CapturePayload] = []
        let monitor = ClipboardMonitor(onCapture: { captures.append($0) }, onStatus: { _ in }, pasteboard: board,
                                       sourceApplication: { ClipboardSource(name: "Private app", bundleID: "test.private") },
                                       normalizeImage: { data in
            entered.signal()
            #expect(release.wait(timeout: .now() + 5) == .success)
            return ImageNormalizer.normalize(data)
        })
        monitor.start()
        defer { monitor.stop() }
        try #require(!monitor.isLocked)
        try write("pending private image", image: image(), to: board)
        monitor.poll()
        let started = await Task.detached { entered.wait(timeout: .now() + 2) == .success }.value
        try #require(started)
        monitor.excludedBundleIDs = ["test.private"]
        release.signal()
        try await waitUntil { !monitor.isDecoding }
        #expect(captures.isEmpty)
        monitor.excludedBundleIDs = []
        monitor.poll()
        #expect(captures.isEmpty)
        try write("fresh allowed copy", to: board)
        monitor.poll()
        #expect(captures.count == 1)
    }

    @MainActor
    @Test(arguments: [false, true])
    func dismissedCopyCannotWriteOrReportLateErrors(missingPayload: Bool) async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try HistoryStore(directory: directory)
        try await add("copy fixture", at: Date(), to: store)
        let (defaults, suite) = preferences()
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppModel(store: store, demo: false, preferenceStore: defaults)
        await model.refresh()
        let selected = try #require(model.selectedID)
        if missingPayload { try await store.delete(id: selected) }
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        try write("untouched", to: board)
        model.monitor = ClipboardMonitor(onCapture: { _ in }, onStatus: { _ in }, pasteboard: board)
        let release = DispatchSemaphore(value: 0)
        defer { release.signal() }
        var blocker: Task<Void, Never>?
        await withCheckedContinuation { (entered: CheckedContinuation<Void, Never>) in
            blocker = Task.detached {
                await store.blockForHardeningTest(entered: { entered.resume() }, release: release)
            }
        }
        model.copySelected()
        await Task.yield()
        model.cancelPendingSelection()
        release.signal()
        await blocker?.value
        try await waitUntil { !model.busy }
        #expect(board.string(forType: .string) == "untouched")
        #expect(model.statusMessage == nil)
        if !missingPayload {
            model.copySelected()
            try await waitUntil { !model.busy }
            #expect(board.string(forType: .string) == "copy fixture")
            #expect(model.statusMessage == "Copied. Press ⌘V wherever you need it.")
        }
    }

    @MainActor
    @Test func previewStorageLinkUsesActualTemporaryStore() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try HistoryStore(directory: directory)
        let model = AppModel(store: store, demo: true)
        #expect(model.storageDirectory == directory.standardizedFileURL)
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("CopyStory-Hardening-\(UUID().uuidString)")
    }
    private func preferences() -> (UserDefaults, String) {
        let name = "com.copystory.test.\(UUID().uuidString)"
        return (UserDefaults(suiteName: name)!, name)
    }
    private func add(_ text: String, at date: Date, image: Data? = nil, pinned: Bool = false, to store: HistoryStore) async throws {
        #expect(try await store.capture(CapturePayload(text: text, imageData: image, capturedAt: date), limits: HistoryLimits()) == .saved)
        if pinned {
            // Search is intentionally partial: "old pinned" also matches
            // "old unpinned". Select the exact fixture before pinning it.
            let row = try #require(try await store.search(query: text, filter: .all).first(where: { $0.preview == text }))
            try await store.setPinned(id: row.id, pinned: true)
        }
    }
    @MainActor private func write(_ text: String, image: Data? = nil, to board: NSPasteboard) throws {
        let item = NSPasteboardItem()
        #expect(item.setString(text, forType: .string))
        if let image { #expect(item.setData(image, forType: .png)) }
        board.clearContents()
        try #require(board.writeObjects([item]))
    }
    private func image() throws -> Data {
        let context = try #require(CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 16,
                                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.4, green: 0.3, blue: 0.2, alpha: 0.5))
        context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try #require(context.makeImage()), nil)
        try #require(CGImageDestinationFinalize(destination))
        return data as Data
    }
    @MainActor private func waitUntil(_ predicate: @MainActor () -> Bool) async throws {
        for _ in 0..<400 {
            if predicate() { return }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        try #require(predicate())
    }
}

private extension HistoryStore {
    func blockForHardeningTest(entered: @Sendable () -> Void, release: DispatchSemaphore) {
        entered()
        #expect(release.wait(timeout: .now() + 5) == .success)
    }
}
