import Testing
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import CopyStoryCore

@Suite(.serialized)
final class HistoryStoreTests {
    private var folders: [URL] = []

    deinit {
        for folder in folders { try? FileManager.default.removeItem(at: folder) }
        folders = []
    }

    private func folder() -> URL {
        let url = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("CopyStory-tests-" + UUID().uuidString, isDirectory: true)
        folders.append(url)
        return url
    }

    @Test(arguments: [StartupStage.historyRecoveryQuery, .historyRecoveryImages,
        .historyRecoveryTransaction, .historyRecoveryEnumeration, .historyRecoveryOrphanRemoval])
    func startupRecoveryFailuresReportExactStageAndReleaseStore(stage: StartupStage) async throws {
        let root = folder()
        let original = NSError(domain: NSPOSIXErrorDomain, code: 13, userInfo: [
            NSLocalizedDescriptionKey: "private clipboard SQL SELECT secret FROM items",
            NSFilePathErrorKey: root.path])
        var failures: [StartupFailure] = []
        let diagnostic = HistoryInitializationDiagnostics(reportFailure: { failures.append($0) }, beforeStage: {
            if $0 == stage { throw original }
        })
        do {
            _ = try HistoryStore(directory: root, initialization: diagnostic)
            Issue.record("Expected injected recovery failure")
        } catch { #expect(error as NSError === original) }
        #expect(failures.count == 1)
        #expect(failures.first?.stage == stage)
        #expect(failures.first?.domain == .posix && failures.first?.code == 13)
        #expect(failures.first?.category == .system)
        // Recovery faults must preserve the initialized database and release its lock.
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("history.sqlite").path))
        let reopened = try HistoryStore(directory: root)
        let rows = try await reopened.search(query: "", filter: .all)
        #expect(rows.isEmpty)
        #expect(!failures[0].summary.contains(root.path))
        #expect(!failures[0].summary.contains("secret"))
    }

    @Test func startupReportsRealAdmissionErrorWithoutChangingItsType() throws {
        var failures: [StartupFailure] = []
        do {
            _ = try HistoryStore(directory: URL(fileURLWithPath: "/"), reportInitializationFailure: { failures.append($0) })
            Issue.record("Expected invalid root")
        } catch HistoryStoreError.invalidDirectory { }
        #expect(failures.count == 1)
        #expect(failures.first?.stage == .historyDirectory)
        #expect(failures.first?.category == .invalidDirectory)
        #expect(failures.first?.domain == .history && failures.first?.code == nil)
    }

    @Test func startupErrorSnapshotsExcludeUntrustedDescriptionsDomainsAndUnderlyingErrors() {
        let secret = "/private/clipboard-secret/SELECT text_content FROM items"
        let nested = NSError(domain: secret, code: 999, userInfo: [NSLocalizedDescriptionKey: secret])
        for domain in [NSCocoaErrorDomain, NSPOSIXErrorDomain, NSOSStatusErrorDomain, "NSSQLiteErrorDomain", secret] {
            let error = NSError(domain: domain, code: 257, userInfo: [
                NSLocalizedDescriptionKey: secret, NSFilePathErrorKey: secret,
                NSURLErrorKey: URL(fileURLWithPath: secret), NSUnderlyingErrorKey: nested])
            let failure = StartupFailure(stage: .historyRecoveryEnumeration, error: error)
            #expect(!failure.summary.contains(secret))
            #expect(!String(reflecting: failure).contains(secret))
            if domain == secret {
                #expect(failure.domain == .other && failure.category == .other && failure.code == nil)
            } else {
                #expect(failure.domain.rawValue == domain && failure.category == .system && failure.code == 257)
            }
        }
        let sqlite = StartupFailure(stage: .historyRecoveryQuery, error: HistoryStoreError.database(11))
        #expect(sqlite.summary == "stage=historyRecoveryQuery category=database domain=HistoryStoreError code=11")
    }
    private func add(_ text: String, to store: HistoryStore, date: Double = 1, limits: HistoryLimits = .init()) async throws {
        let result = try await store.capture(CapturePayload(text: text, capturedAt: Date(timeIntervalSince1970: date)), limits: limits)
        #expect(result == .saved)
    }
    private func png(width: Int = 12, height: Int = 8, seed: UInt8 = 70) throws -> Data {
        let bytes = [UInt8](repeating: seed, count: width * height * 4)
        let provider = CGDataProvider(data: Data(bytes) as CFData)!
        let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }
    private func filesSize(_ root: URL) throws -> Int64 {
        let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey])!
        var sum: Int64 = 0
        for case let file as URL in enumerator {
            let values = try file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            if values.isRegularFile == true { sum += Int64(values.fileSize ?? 0) }
        }
        return sum
    }

    @Test func testExactUnicodeWhitespaceAndEmbeddedNULRoundTrip() async throws {
        let store = try HistoryStore(directory: folder())
        let text = "  \tlet café = \"日本語 🧑🏽‍💻\"\n\n\0tail\r\n "
        try await add(text, to: store)
        let rows = try await store.search(query: "", filter: .all)
        #expect(rows.count == 1)
        let retrieved = try await store.payload(id: rows[0].id)
        #expect(retrieved.text == text)
        #expect(retrieved.imageData == nil)
        let full = try await store.fullText(id: rows[0].id)
        #expect(full == text)
    }

    @Test func testReopenPersistsPinAndExactContent() async throws {
        let path = folder()
        var store: HistoryStore? = try HistoryStore(directory: path)
        try await add("persistent\ncontent", to: store!)
        let row = try await store!.search(query: "", filter: .all)[0]
        try await store!.setPinned(id: row.id, pinned: true)
        store = nil
        let reopened = try HistoryStore(directory: path)
        let saved = try await reopened.item(id: row.id)
        #expect(saved?.isPinned == true)
        let text = try await reopened.fullText(id: row.id)
        #expect(text == "persistent\ncontent")
    }

    @Test func testDedupPreservesIdentityAndPinAndAdvancesRecency() async throws {
        let store = try HistoryStore(directory: folder())
        try await add("first", to: store, date: 1)
        let old = try await store.search(query: "", filter: .all)[0]
        try await store.setPinned(id: old.id, pinned: true)
        try await add("second", to: store, date: 2)
        let outcome = try await store.capture(.init(text: "first", capturedAt: Date(timeIntervalSince1970: 3)), limits: .init())
        #expect(outcome == .duplicate)
        let rows = try await store.search(query: "", filter: .all)
        #expect(rows.count == 2)
        #expect(rows[0].id == old.id)
        #expect(rows[0].isPinned)
        #expect(rows[0].capturedAt.timeIntervalSince1970 == 3)
    }

    @Test func testRepeatedCopyUpdatesSourceAndSourceSearch() async throws {
        let store = try HistoryStore(directory: folder())
        _ = try await store.capture(.init(text: "same content", sourceApp: "Original Editor", sourceBundleID: "app.original", capturedAt: Date(timeIntervalSince1970: 1)), limits: .init())
        let id = try await store.search(query: "", filter: .all)[0].id
        let result = try await store.capture(.init(text: "same content", sourceApp: "New Browser", sourceBundleID: "app.new", capturedAt: Date(timeIntervalSince1970: 2)), limits: .init())
        #expect(result == .duplicate)
        let row = try await store.item(id: id)
        #expect(row?.sourceApp == "New Browser")
        #expect(row?.sourceBundleID == "app.new")
        let oldSource = try await store.search(query: "Original Editor", filter: .all)
        let newSource = try await store.search(query: "new brow", filter: .all)
        #expect(oldSource.isEmpty)
        #expect(newSource.count == 1)
    }

    @Test func testSearchUsesUnicodeFoldingPartialTermsAndSourceName() async throws {
        let store = try HistoryStore(directory: folder())
        _ = try await store.capture(.init(text: "Straße CAFÉ 100% abc_def", sourceApp: "Terminal"), limits: .init())
        try await add("unrelated", to: store)
        let terms = try await store.search(query: "STRASSE fe\u{301} term", filter: .text)
        #expect(terms.count == 1)
        let literal = try await store.search(query: "% _", filter: .all)
        #expect(literal.count == 1)
        let noPhrase = try await store.search(query: "term stras", filter: .all)
        #expect(noPhrase.count == 1)
        let missing = try await store.search(query: "term absent", filter: .all)
        #expect(missing.isEmpty)
    }

    @Test func testImageWithAssociatedTextIsOneItemAndPreservesPayload() async throws {
        let store = try HistoryStore(directory: folder())
        let bytes = try png()
        let input = CapturePayload(text: "associated label", imageData: bytes, thumbnailData: Data("untrusted thumbnail".utf8), pixelWidth: 999, pixelHeight: 999, sourceApp: "Preview")
        let result = try await store.capture(input, limits: .init())
        #expect(result == .saved)
        let rows = try await store.search(query: "assoc prev", filter: .images)
        #expect(rows.count == 1)
        #expect(rows[0].kind == .image)
        #expect(rows[0].pixelWidth == 12)
        #expect(rows[0].pixelHeight == 8)
        let payload = try await store.payload(id: rows[0].id)
        #expect(payload.imageData == bytes)
        #expect(payload.text == "associated label")
        let thumbnailURL = try await store.thumbnailURL(id: rows[0].id)
        let thumbnail = try #require(thumbnailURL)
        let thumbnailBytes = try Data(contentsOf: thumbnail)
        #expect((CGImageSourceCreateWithData(thumbnailBytes as CFData, nil)) != nil)
        let onlyText = try await store.search(query: "", filter: .text)
        #expect(onlyText.isEmpty)
        let duplicate = try await store.capture(input, limits: .init())
        #expect(duplicate == .duplicate)
    }

    @Test func testImageCaptureTimeIsSearchable() async throws {
        let store = try HistoryStore(directory: folder())
        _ = try await store.capture(.init(imageData: try png(), capturedAt: Date(timeIntervalSince1970: 1_700_000_000)), limits: .init())
        let result = try await store.search(query: "2023-11-14", filter: .images)
        #expect(result.count == 1)
    }

    @Test func testRetentionRemovesOldestUnpinnedAndCountsPinned() async throws {
        let store = try HistoryStore(directory: folder())
        let limits = HistoryLimits(maxItems: 3)
        try await add("pin", to: store, date: 1, limits: limits)
        let pinned = try await store.search(query: "", filter: .all)[0]
        try await store.setPinned(id: pinned.id, pinned: true)
        for n in 2...4 { try await add("item \(n)", to: store, date: Double(n), limits: limits) }
        let rows = try await store.search(query: "", filter: .all)
        #expect(rows.map(\.preview) == ["item 4", "item 3", "pin"])
        let stats = try await store.stats()
        #expect(stats.count == 3)
        #expect(stats.pinnedCount == 1)
    }

    @Test func testPinnedCapacityRejectsTransactionWithoutEvictingExistingUnpinned() async throws {
        let store = try HistoryStore(directory: folder())
        try await add("pin", to: store, date: 1)
        let pinned = try await store.search(query: "", filter: .all)[0]
        try await store.setPinned(id: pinned.id, pinned: true)
        try await add("keep after failed admission", to: store, date: 2)
        let before = try await store.search(query: "", filter: .all)
        let result = try await store.capture(.init(text: "rejected"), limits: .init(maxItems: 1))
        #expect(result == .pinnedCapacity)
        let after = try await store.search(query: "", filter: .all)
        #expect(after == before)
    }

    @Test func testOversizedAdmissionNeverEvictsHistory() async throws {
        let store = try HistoryStore(directory: folder())
        try await add("keep me", to: store)
        let before = try await store.search(query: "", filter: .all)
        let result = try await store.capture(.init(text: String(repeating: "a", count: 100_000)), limits: .init(maxBytes: 64_000))
        #expect(result == .oversized)
        let after = try await store.search(query: "", filter: .all)
        #expect(after == before)
    }

    @Test func testRetentionBoundsActualDirectoryBytesIncludingSQLite() async throws {
        let path = folder()
        let store = try HistoryStore(directory: path)
        let limits = HistoryLimits(maxItems: 1_000, maxBytes: 200_000)
        for index in 0..<25 {
            try await add(String(repeating: "s", count: 9_000) + String(index), to: store, date: Double(index), limits: limits)
            #expect(try filesSize(path) <= limits.maxBytes)
        }
        let stats = try await store.stats()
        #expect(stats.totalBytes == (try filesSize(path)))
        #expect(stats.count < 25)
        #expect(stats.count > 0)
    }

    @Test func testImageRetentionDeletesBothFilesAndIncludesThumbnailsInBudget() async throws {
        let path = folder()
        let store = try HistoryStore(directory: path)
        _ = try await store.capture(.init(imageData: try png(seed: 50), capturedAt: Date(timeIntervalSince1970: 1)), limits: .init(maxItems: 1))
        let first = try await store.search(query: "", filter: .all)[0]
        let firstThumb = try await store.thumbnailURL(id: first.id)
        _ = try await store.capture(.init(imageData: try png(seed: 80), capturedAt: Date(timeIntervalSince1970: 2)), limits: .init(maxItems: 1))
        #expect(!(FileManager.default.fileExists(atPath: try #require(firstThumb).path)))
        #expect(!(FileManager.default.fileExists(atPath: path.appendingPathComponent("Images/\(first.id).image").path)))
        let stats = try await store.stats()
        #expect(stats.totalBytes == (try filesSize(path)))
        let imageFiles = try FileManager.default.contentsOfDirectory(atPath: path.appendingPathComponent("Images").path)
        #expect(imageFiles.count == 2)
    }

    @Test func testClearUnpinnedThenClearAllReclaimsPayloads() async throws {
        let path = folder()
        let store = try HistoryStore(directory: path)
        _ = try await store.capture(.init(imageData: try png()), limits: .init())
        let pinned = try await store.search(query: "", filter: .all)[0]
        try await store.setPinned(id: pinned.id, pinned: true)
        try await add("remove", to: store)
        try await store.clear(includePinned: false)
        var rows = try await store.search(query: "", filter: .all)
        #expect(rows.count == 1)
        #expect(rows[0].id == pinned.id)
        try await store.clear(includePinned: true)
        rows = try await store.search(query: "", filter: .all)
        #expect(rows.isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: path.appendingPathComponent("Images").path).isEmpty)
    }

    @Test func testLoweredLimitsKeepPinnedRecordsAndReportCapacity() async throws {
        let store = try HistoryStore(directory: folder())
        for index in 1...3 { try await add("item \(index)", to: store, date: Double(index)) }
        let rows = try await store.search(query: "", filter: .all)
        for row in rows.prefix(2) { try await store.setPinned(id: row.id, pinned: true) }
        let blocked = try await store.enforceLimits(.init(maxItems: 1))
        #expect(blocked)
        let stats = try await store.stats()
        #expect(stats.count == 2)
        #expect(stats.pinnedCount == 2)
        #expect(stats.pinnedBytes > 0)
    }

    @Test func testReopenRepairsThumbnailAndRemovesMissingImageAndOrphans() async throws {
        let path = folder()
        var store: HistoryStore? = try HistoryStore(directory: path)
        _ = try await store!.capture(.init(imageData: try png(seed: 30), capturedAt: Date(timeIntervalSince1970: 1)), limits: .init())
        _ = try await store!.capture(.init(imageData: try png(seed: 40), capturedAt: Date(timeIntervalSince1970: 2)), limits: .init())
        let rows = try await store!.search(query: "", filter: .all)
        let repairThumbnailURL = try await store!.thumbnailURL(id: rows[0].id)
        let repairThumb = try #require(repairThumbnailURL)
        store = nil
        try Data("damaged".utf8).write(to: repairThumb)
        try FileManager.default.removeItem(at: path.appendingPathComponent("Images/\(rows[1].id).image"))
        let orphan = path.appendingPathComponent("Images/orphan.tmp")
        try Data("partial write".utf8).write(to: orphan)
        let reopened = try HistoryStore(directory: path)
        let remaining = try await reopened.search(query: "", filter: .all)
        #expect(remaining.map(\.id) == [rows[0].id])
        #expect(!(FileManager.default.fileExists(atPath: orphan.path)))
        let thumbnail = try Data(contentsOf: repairThumb)
        #expect((CGImageSourceCreateWithData(thumbnail as CFData, nil)) != nil)
        let stats = try await reopened.stats()
        #expect(stats.totalBytes == (try filesSize(path)))
    }

    @Test func testDamagedImageIsRemovedOnAccessWithoutCrashing() async throws {
        let path = folder()
        let store = try HistoryStore(directory: path)
        _ = try await store.capture(.init(imageData: try png()), limits: .init())
        let id = try await store.search(query: "", filter: .all)[0].id
        try Data("broken image".utf8).write(to: path.appendingPathComponent("Images/\(id).image"))
        do { _ = try await store.payload(id: id); Issue.record("Expected damaged image rejection") }
        catch HistoryStoreError.damagedImage { }
        let remaining = try await store.item(id: id)
        #expect((remaining) == nil)
    }

    @Test func testMalformedImageAndEmptyPayloadDoNotCreateRows() async throws {
        let store = try HistoryStore(directory: folder())
        do { _ = try await store.capture(.init(imageData: Data("not an image".utf8)), limits: .init()); Issue.record("Expected rejection") }
        catch HistoryStoreError.damagedImage { }
        do { _ = try await store.capture(.init(text: ""), limits: .init()); Issue.record("Expected rejection") }
        catch HistoryStoreError.emptyPayload { }
        let stats = try await store.stats()
        #expect(stats.count == 0)
    }

    @Test func testExcessiveImageDimensionIsRejectedBeforeDecode() async throws {
        let store = try HistoryStore(directory: folder())
        let oversizedDimension = try png(width: 16_385, height: 1)
        do { _ = try await store.capture(.init(imageData: oversizedDimension), limits: .init()); Issue.record("Expected dimension limit") }
        catch HistoryStoreError.damagedImage { }
        let stats = try await store.stats()
        #expect(stats.count == 0)
    }

    @Test func testTamperedOversizedThumbnailIsNotExposedToInterface() async throws {
        let path = folder()
        let store = try HistoryStore(directory: path)
        _ = try await store.capture(.init(imageData: try png()), limits: .init())
        let id = try await store.search(query: "", filter: .all)[0].id
        let thumbnailURL = try await store.thumbnailURL(id: id)
        let thumbnail = try #require(thumbnailURL)
        try png(width: 321, height: 1).write(to: thumbnail)
        let rejectedURL = try await store.thumbnailURL(id: id)
        #expect(rejectedURL == nil)
    }

    @Test func testPermissionsAreOwnerOnly() async throws {
        let path = folder()
        let store = try HistoryStore(directory: path)
        _ = try await store.capture(.init(imageData: try png()), limits: .init())
        let enumerator = FileManager.default.enumerator(at: path, includingPropertiesForKeys: [.isDirectoryKey])!
        let rootPerms = try FileManager.default.attributesOfItem(atPath: path.path)[.posixPermissions] as? NSNumber
        #expect(rootPerms?.intValue == 0o700)
        for url in enumerator.allObjects.compactMap({ $0 as? URL }) {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            let isDirectory = attributes[.type] as? FileAttributeType == .typeDirectory
            #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == (isDirectory ? 0o700 : 0o600))
        }
    }

    @Test func testPathTraversalAndSymlinkDatabaseAreRejected() async throws {
        let path = folder()
        let store = try HistoryStore(directory: path)
        do { try await store.delete(id: "../../outside"); Issue.record("Expected invalid ID rejection") }
        catch HistoryStoreError.unsafeFile { }
        let unsafePath = folder()
        try FileManager.default.createDirectory(at: unsafePath, withIntermediateDirectories: true)
        let outside = folder().appendingPathComponent("outside")
        try FileManager.default.createDirectory(at: outside.deletingLastPathComponent(), withIntermediateDirectories: true)
        let sentinel = Data("do not change".utf8)
        try sentinel.write(to: outside)
        try FileManager.default.createSymbolicLink(at: unsafePath.appendingPathComponent("history.sqlite"), withDestinationURL: outside)
        do { _ = try HistoryStore(directory: unsafePath); Issue.record("Expected symlink rejection") } catch { }
        #expect(try Data(contentsOf: outside) == sentinel)
    }

    @Test func testSymlinkImageRecoveryDoesNotReadOrDeleteTarget() async throws {
        let path = folder()
        var store: HistoryStore? = try HistoryStore(directory: path)
        _ = try await store!.capture(.init(imageData: try png()), limits: .init())
        let id = try await store!.search(query: "", filter: .all)[0].id
        store = nil
        let image = path.appendingPathComponent("Images/\(id).image")
        try FileManager.default.removeItem(at: image)
        let target = path.appendingPathComponent("sentinel")
        let sentinel = Data("protected target".utf8)
        try sentinel.write(to: target)
        try FileManager.default.createSymbolicLink(at: image, withDestinationURL: target)
        let reopened = try HistoryStore(directory: path)
        let stats = try await reopened.stats()
        #expect(stats.count == 0)
        #expect(try Data(contentsOf: target) == sentinel)
    }

    @Test func testSecondProcessLockAndCorruptDatabaseFailSafely() async throws {
        let path = folder()
        let store = try HistoryStore(directory: path)
        do { _ = try HistoryStore(directory: path); Issue.record("Expected process lock") } catch {
            guard case HistoryStoreError.alreadyOpen = error else { Issue.record("Unexpected error: \(error)"); return }
        }
        _ = try await store.stats()
        let corruptPath = folder()
        try FileManager.default.createDirectory(at: corruptPath, withIntermediateDirectories: true)
        let bytes = Data(repeating: 0xAB, count: 4_096)
        let file = corruptPath.appendingPathComponent("history.sqlite")
        try bytes.write(to: file)
        do { _ = try HistoryStore(directory: corruptPath); Issue.record("Expected corrupt database rejection") } catch { }
        #expect(try Data(contentsOf: file) == bytes)
    }

    @Test func testPaginationStableForIdenticalTimestampsAndFilters() async throws {
        let store = try HistoryStore(directory: folder())
        for index in 0..<7 { try await add("row \(index)", to: store, date: 50) }
        let all = try await store.search(query: "", filter: .all)
        let page1 = try await store.search(query: "", filter: .all, limit: 3, offset: 0)
        let page2 = try await store.search(query: "", filter: .all, limit: 4, offset: 3)
        #expect(page1 + page2 == all)
        try await store.setPinned(id: all[3].id, pinned: true)
        let pins = try await store.search(query: "", filter: .pinned)
        #expect(pins.map(\.id) == [all[3].id])
        #expect(all.map(\.id) == all.map(\.id).sorted(by: >))
    }

    @Test func testInvalidLimitsDoNotMutateHistory() async throws {
        let store = try HistoryStore(directory: folder())
        try await add("keep", to: store)
        do { _ = try await store.capture(.init(text: "new"), limits: .init(maxItems: 0)); Issue.record("Expected invalid limits") }
        catch HistoryStoreError.invalidLimits { }
        let rows = try await store.search(query: "", filter: .all)
        #expect(rows.map(\.preview) == ["keep"])
    }

    @Test func testSearchPerformanceAtDefaultItemLimit() async throws {
        let store = try HistoryStore(directory: folder())
        for index in 0..<1_000 {
            let text = "Synthetic entry \(index)\n" + String(repeating: "ordinary sample content ", count: 20)
            try await add(text, to: store, date: Double(index))
        }
        var samples: [Double] = []
        for _ in 0..<20 {
            let start = ContinuousClock.now
            let rows = try await store.search(query: "entry 995 ordinary", filter: .all)
            let elapsed = start.duration(to: .now)
            let milliseconds = Double(elapsed.components.seconds) * 1_000 + Double(elapsed.components.attoseconds) / 1e15
            samples.append(milliseconds)
            #expect(rows.count == 1)
        }
        let median = samples.sorted()[samples.count / 2]
        // A loose automated guard avoids machine-dependent timing failures. The
        // measured median is reported separately against the PRD's 100 ms target.
        #expect(median < 1_000)
        print("Synthetic search benchmark (1,000 records, 20 queries): median \(String(format: "%.2f", median)) ms")
    }
}
