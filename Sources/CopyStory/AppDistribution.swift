import Foundation
import CopyStoryCore

/// Shared by ordinary startup and inert failure-path tests. No native effects.
enum StartupStorage {
    static func preferences(development: Bool, demo: Bool,
        makeSuite: (String) -> UserDefaults? = { UserDefaults(suiteName: $0) }) throws -> UserDefaults? {
        guard development && !demo else { return nil }
        guard let isolated = makeSuite(DevelopmentConfiguration.bundleID) else { throw CocoaError(.fileReadUnknown) }
        return isolated
    }

    static func prepare<Store, Preferences>(history: () throws -> Store,
        preferences: () throws -> Preferences, reportFailure: (StartupFailure) -> Void) throws -> (Store, Preferences) {
        let store = try history()
        do { return (store, try preferences()) }
        catch {
            reportFailure(StartupFailure(stage: .preferencesConstruction, error: error))
            throw error
        }
    }
}

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
    static func preferenceDefaults(development: Bool = enabled) -> [String: Any] {
        ["maxItems": 1000, "maxMB": 500, "respectConfidential": true,
         "shortcutCode": 4, "shortcutModifiers": 768, "shortcutLabel": "⇧⌘H",
         "shortcutEnabled": !development, "directPasteEnabled": false]
    }
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
