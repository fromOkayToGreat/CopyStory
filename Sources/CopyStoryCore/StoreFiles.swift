import Foundation
import Darwin

/// Shared filesystem admission and owner-only permissions for local stores.
enum StoreFiles {
    static func exists(_ url: URL) -> Bool { var info = Darwin.stat(); return lstat(url.path, &info) == 0 }
    static func regularFileSize(_ url: URL) throws -> Int64 {
        var info = Darwin.stat()
        guard lstat(url.path, &info) == 0 else { throw HistoryStoreError.storageUnavailable }
        guard (info.st_mode & S_IFMT) == S_IFREG, info.st_nlink == 1, info.st_uid == getuid() else { throw HistoryStoreError.unsafeFile }
        return info.st_size
    }
    static func ownerOnly(_ url: URL) throws {
        _ = try regularFileSize(url)
        guard chmod(url.path, S_IRUSR | S_IWUSR) == 0 else { throw HistoryStoreError.storageUnavailable }
    }
    static func prepareDirectory(_ url: URL) throws {
        var ancestor = url
        while ancestor.path != "/" {
            // Inspect the link itself; only type and owner are used for path admission.
            if let attributes = try? FileManager.default.attributesOfItem(atPath: ancestor.path),
               attributes[.type] as? FileAttributeType != .typeDirectory {
                // Foundation intentionally presents /private/var as /var even
                // after resolvingSymlinksInPath. Accept only these root-owned
                // macOS aliases, never a user-controlled ancestor symlink.
                let systemAlias = ["/var": "private/var", "/tmp": "private/tmp"][ancestor.path]
                let target = try? FileManager.default.destinationOfSymbolicLink(atPath: ancestor.path)
                guard (attributes[.ownerAccountID] as? NSNumber)?.uint64Value == 0,
                      let systemAlias, target == systemAlias || target == "/" + systemAlias else {
                    throw HistoryStoreError.invalidDirectory
                }
            }
            ancestor.deleteLastPathComponent()
        }
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        var info = Darwin.stat()
        guard lstat(url.path, &info) == 0, (info.st_mode & S_IFMT) == S_IFDIR, info.st_uid == getuid(),
              chmod(url.path, S_IRWXU) == 0 else { throw HistoryStoreError.invalidDirectory }
    }
}
