import AppKit
import Dispatch
import ImageIO
import Testing
import UniformTypeIdentifiers
import CopyStoryCore
@testable import CopyStory

/// Only synthetic fixtures, named pasteboards and private temporary stores are used.
@Suite(.serialized)
struct ClearHistoryTests {
    @MainActor
    @Test(arguments: [false, true])
    func pendingImageCannotReturnAfterClear(includePinned: Bool) async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try HistoryStore(directory: directory)
        let image = try makePNG(width: 4)
        let pinnedImage = try makePNG(width: 3)
        try await add(text: "old associated text", image: image, to: store)
        try await add(text: "old text", to: store)
        try await add(text: "pinned image", image: pinnedImage, pinned: true, to: store)
        try await add(text: "pinned text", pinned: true, to: store)
        let model = AppModel(store: store, demo: true)
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let started = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        defer { release.signal() }
        var captureCount = 0
        var lastSave: Task<Void, Never>?
        let monitor = ClipboardMonitor(onCapture: { [weak model] payload in
            captureCount += 1
            lastSave = model?.save(payload)
        }, onStatus: { _ in }, pasteboard: board, normalizeImage: { data in
            started.signal()
            let released = release.wait(timeout: .now() + 5) == .success
            #expect(released, "The test must release normalization within its bounded interval.")
            return ImageNormalizer.normalize(data)
        })
        model.monitor = monitor
        monitor.start()
        defer { monitor.stop() }
        try #require(!monitor.isLocked, "An active, unlocked macOS session is required.")
        try write(text: "old associated text", image: image, to: board)
        monitor.poll()
        let began = await Task.detached { started.wait(timeout: .now() + 2) == .success }.value
        try #require(began)
        try #require(monitor.isDecoding)

        await model.clear(includePinned: includePinned).value
        let retainedCount = includePinned ? 0 : 2
        #expect(model.count == retainedCount)
        #expect(model.statusMessage == (includePinned ? "All history cleared." : "Unpinned history cleared."))
        release.signal()
        try await waitUntil { !monitor.isDecoding }
        await lastSave?.value
        #expect(captureCount == 0, "Neither the pre-clear image nor its associated text may be delivered.")
        #expect(try await store.stats().count == retainedCount)
        #expect(try await store.search(query: "old", filter: .all).isEmpty)
        let imageFiles = try FileManager.default.contentsOfDirectory(atPath: directory.appendingPathComponent("Images").path)
        #expect(imageFiles.count == (includePinned ? 0 : 2), "Deleted payload and thumbnail files must not return.")
        if !includePinned {
            let pins = try await store.search(query: "", filter: .pinned)
            #expect(pins.count == 2)
            let pin = try #require(pins.first { $0.preview == "pinned image" })
            #expect(try await store.payload(id: pin.id).imageData != nil)
        }

        // Clearing does not alter the clipboard or re-record its existing value.
        #expect(board.string(forType: .string) == "old associated text")
        #expect(board.data(forType: .png) == image)
        monitor.poll()
        #expect(!monitor.isDecoding)
        #expect(captureCount == 0)

        // The identical image is eligible again only after a genuinely new copy.
        release.signal()
        try write(text: "fresh associated text", image: image, to: board)
        monitor.poll()
        try await waitUntil { !monitor.isDecoding }
        await lastSave?.value
        #expect(captureCount == 1)
        #expect(try await store.stats().count == retainedCount + 1)
        let fresh = try #require(try await store.search(query: "fresh associated text", filter: .all).first)
        #expect(try await store.payload(id: fresh.id).imageData != nil)
    }

    @MainActor
    @Test(arguments: [false, true])
    func clearOrdersQueuedSavesAndPreservesLaterCopies(includePinned: Bool) async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try HistoryStore(directory: directory)
        try await add(text: "pinned fixture", pinned: true, to: store)
        let model = AppModel(store: store, demo: true)
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        model.monitor = ClipboardMonitor(onCapture: { _ in }, onStatus: { _ in }, pasteboard: board)
        let release = DispatchSemaphore(value: 0)
        defer { release.signal() }
        var blocker: Task<Void, Never>?
        await withCheckedContinuation { (started: CheckedContinuation<Void, Never>) in
            blocker = Task.detached {
                await store.blockForClearTest(started: { started.resume() }, release: release)
            }
        }
        let oldSave = model.save(CapturePayload(text: "old queued text"))
        await Task.yield() // Let a save attempt the occupied storage actor.
        let clear = model.clear(includePinned: includePinned)
        let freshSave = model.save(CapturePayload(text: "fresh queued text"))
        release.signal()
        await blocker?.value
        await oldSave.value
        await clear.value
        await freshSave.value
        let rows = try await store.search(query: "", filter: .all)
        #expect(Set(rows.map(\.preview)) == Set(includePinned ? ["fresh queued text"] : ["pinned fixture", "fresh queued text"]))
    }

    @MainActor
    @Test func clearBaselinesUnpolledTextWithoutStoppingRecording() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try HistoryStore(directory: directory)
        let model = AppModel(store: store, demo: true)
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        var captureCount = 0
        var lastSave: Task<Void, Never>?
        let monitor = ClipboardMonitor(onCapture: { [weak model] payload in
            captureCount += 1
            lastSave = model?.save(payload)
        }, onStatus: { _ in }, pasteboard: board)
        model.monitor = monitor
        monitor.start()
        defer { monitor.stop() }
        try #require(!monitor.isLocked, "An active, unlocked macOS session is required.")
        try write(text: "unpolled old text", to: board)
        await model.clear(includePinned: true).value
        monitor.poll()
        await lastSave?.value
        #expect(captureCount == 0)
        #expect(try await store.stats().count == 0)
        #expect(board.string(forType: .string) == "unpolled old text")
        try write(text: "fresh text", to: board)
        monitor.poll()
        await lastSave?.value
        #expect(captureCount == 1)
        #expect(try await store.search(query: "", filter: .all).map(\.preview) == ["fresh text"])
    }

    @MainActor
    @Test func repeatedClearsDiscardIntermediateCaptures() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try HistoryStore(directory: directory)
        try await add(text: "pinned fixture", pinned: true, to: store)
        let model = AppModel(store: store, demo: true)
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        model.monitor = ClipboardMonitor(onCapture: { _ in }, onStatus: { _ in }, pasteboard: board)
        let old = model.save(CapturePayload(text: "old"))
        let first = model.clear(includePinned: false)
        let between = model.save(CapturePayload(text: "between clears"))
        let second = model.clear(includePinned: true)
        let fresh = model.save(CapturePayload(text: "after both clears"))
        for task in [old, first, between, second, fresh] { await task.value }
        #expect(try await store.search(query: "", filter: .all).map(\.preview) == ["after both clears"])
        #expect(model.count == 1)
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("CopyStory-ClearTests-\(UUID().uuidString)", isDirectory: true)
    }

    private func add(text: String, image: Data? = nil, pinned: Bool = false, to store: HistoryStore) async throws {
        let normalized = try image.map { try ImageNormalizer.normalize($0).get() }
        let payload = CapturePayload(text: text, imageData: normalized?.png, thumbnailData: normalized?.thumbnail,
                                     pixelWidth: normalized?.width, pixelHeight: normalized?.height,
                                     sourceApp: nil, sourceBundleID: nil)
        #expect(try await store.capture(payload, limits: HistoryLimits()) == .saved)
        if pinned {
            let row = try #require(try await store.search(query: text, filter: .all).first)
            try await store.setPinned(id: row.id, pinned: true)
        }
    }

    @MainActor
    private func write(text: String, image: Data? = nil, to board: NSPasteboard) throws {
        let item = NSPasteboardItem()
        #expect(item.setString(text, forType: .string))
        if let image { #expect(item.setData(image, forType: .png)) }
        board.clearContents()
        try #require(board.writeObjects([item]))
    }

    private func makePNG(width: Int) throws -> Data {
        let context = try #require(CGContext(data: nil, width: width, height: 4, bitsPerComponent: 8,
                                            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.5, green: 0.25, blue: 0.75, alpha: 0.5))
        context.fill(CGRect(x: 0, y: 0, width: width, height: 4))
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try #require(context.makeImage()), nil)
        try #require(CGImageDestinationFinalize(destination))
        return data as Data
    }

    @MainActor
    private func waitUntil(_ predicate: @MainActor () -> Bool) async throws {
        for _ in 0..<400 {
            if predicate() { return }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        try #require(predicate(), "Capture did not settle within the bounded test interval.")
    }
}

private extension HistoryStore {
    func blockForClearTest(started: @Sendable () -> Void, release: DispatchSemaphore) {
        started()
        let released = release.wait(timeout: .now() + 5) == .success
        #expect(released)
    }
}
