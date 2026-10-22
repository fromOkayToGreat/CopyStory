import Foundation

enum AppDistribution {
    #if APP_STORE
    static let isAppStore = true
    #else
    static let isAppStore = false
    #endif
}


/// A separate identity/container lets development start empty without opening,
/// migrating or removing the installed app's history or preferences.
enum DevelopmentConfiguration {
    #if COPYSTORY_DEVELOPMENT
    static let enabled = true
    #else
    static let enabled = false
    #endif
    static let bundleID = "com.copystory.development"
    static let storeFolder = "CopyStory Development"
    static var defaultShortcutEnabled: Bool { !enabled }
    static func storeDirectory(applicationSupport: URL, development: Bool = enabled) -> URL {
        applicationSupport.appendingPathComponent(development ? storeFolder : "CopyStory", isDirectory: true)
    }
    static func validates(info: [String: Any]) -> Bool {
        guard info["CFBundleIdentifier"] as? String == bundleID,
              info["CopyStoryDevelopmentBuild"] as? Bool == true,
              let revision = info["CopyStorySourceRevision"] as? String,
              revision.range(of: "^[0-9a-f]{40}$", options: .regularExpression) != nil,
              let dirty = info["CopyStorySourceDirty"] as? String,
              ["clean", "dirty"].contains(dirty),
              info["CopyStoryBuildConfiguration"] as? String == "Debug",
              info["CopyStoryNativeSourceOnly"] == nil,
              info["CopyStorySandboxFeasibility"] == nil,
              !info.keys.contains(where: { $0.hasPrefix("SU") }) else { return false }
        return true
    }

}
