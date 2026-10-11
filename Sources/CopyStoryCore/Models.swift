import Foundation

public enum HistoryKind: String, Sendable { case text, image }
public enum HistoryFilter: String, CaseIterable, Sendable { case all, text, images, pinned }

public struct HistoryLimits: Sendable {
    public var maxItems: Int
    public var maxBytes: Int64
    public init(maxItems: Int = 1_000, maxBytes: Int64 = 500_000_000) {
        self.maxItems = maxItems
        self.maxBytes = maxBytes
    }
}

public struct CapturePayload: Sendable {
    public var text: String?
    public var imageData: Data?
    public var thumbnailData: Data?
    public var pixelWidth: Int?
    public var pixelHeight: Int?
    public var sourceApp: String?
    public var sourceBundleID: String?
    public var capturedAt: Date
    public init(text: String? = nil, imageData: Data? = nil, thumbnailData: Data? = nil,
                pixelWidth: Int? = nil, pixelHeight: Int? = nil,
                sourceApp: String? = nil, sourceBundleID: String? = nil, capturedAt: Date = Date()) {
        self.text = text; self.imageData = imageData; self.thumbnailData = thumbnailData
        self.pixelWidth = pixelWidth; self.pixelHeight = pixelHeight
        self.sourceApp = sourceApp; self.sourceBundleID = sourceBundleID; self.capturedAt = capturedAt
    }
}

public struct HistoryItem: Identifiable, Sendable, Equatable {
    public let id: String
    public let kind: HistoryKind
    public let preview: String
    public let hasText: Bool
    public let sourceApp: String?
    public let sourceBundleID: String?
    public let capturedAt: Date
    public let isPinned: Bool
    /// Logical content size; aggregate stats also include actual SQLite storage.
    public let byteCount: Int64
    public let pixelWidth: Int?
    public let pixelHeight: Int?
}

public struct HistoryStats: Sendable {
    public let count: Int
    public let pinnedCount: Int
    /// Actual settled database and payload file bytes. Transient rollback journals are excluded.
    public let totalBytes: Int64
    /// Payload bytes plus a proportional share of database bytes for pinned records.
    public let pinnedBytes: Int64
}

public enum StoreOutcome: Sendable, Equatable { case saved, duplicate, oversized, pinnedCapacity }

public enum HistoryStoreError: LocalizedError {
    case invalidDirectory, unsafeFile, storageUnavailable, database(Int32), unsupportedSchema
    case invalidLimits, emptyPayload, damagedImage, missingItem, alreadyOpen
    public var errorDescription: String? {
        switch self {
        case .invalidDirectory: return "The history folder could not be opened."
        case .unsafeFile: return "A history file has an unsafe path or file type."
        case .storageUnavailable: return "History storage is unavailable. Check available disk space and folder permissions."
        case .database(let code): return "The history database could not complete the operation (SQLite code \(code))."
        case .unsupportedSchema: return "This history was created by a newer version of CopyStory."
        case .invalidLimits: return "History limits must be positive."
        case .emptyPayload: return "The clipboard item is empty or unsupported."
        case .damagedImage: return "This image was missing or damaged and has been removed from history."
        case .missingItem: return "This history item is no longer available."
        case .alreadyOpen: return "Another CopyStory process is already using this history folder."
        }
    }
}
