import Foundation
import CopyStoryCore

#if COPYSTORY_PRODUCTION && (!APP_STORE || COPYSTORY_DEVELOPMENT || SHIPPING_RECONSTRUCTION || FOCUS_IDENTITY_CHECK)
#error("Production requires APP_STORE and excludes development, reconstruction and focus diagnostics")
#endif

/// Shared by ordinary startup and inert failure-path tests. No native effects.
enum StartupStorage {
    static func preferences(development: Bool, demo: Bool,
        currentAppDefaults: () -> UserDefaults = { .standard }) -> UserDefaults? {
        guard development && !demo else { return nil }
        // Package validation establishes the separate development identity before
        // startup. Passing that same identity to init(suiteName:) is invalid.
        return currentAppDefaults()
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


/// Fallbacks stay outside UserDefaults' registration domain so missing saved
/// fields can be recognized without mixing a legacy binding with the new default.
struct HistoryShortcut: Equatable {
    let code: UInt32
    let modifiers: UInt32
    let label: String
    static let standard = Self(code: 9, modifiers: 2048, label: "⌥V")
    static let legacy = Self(code: 4, modifiers: 768, label: "⇧⌘H")

    static func load(from defaults: UserDefaults) -> Self {
        let keys = ["shortcutCode", "shortcutModifiers", "shortcutLabel"]
        guard keys.contains(where: { defaults.object(forKey: $0) != nil }) else { return .standard }
        // Previous releases wrote no provenance. Preserve every saved choice,
        // even an old-default-shaped choice; partial records use legacy fallbacks.
        func number(_ key: String, fallback: UInt32) -> UInt32 {
            guard defaults.object(forKey: key) != nil else { return fallback }
            return UInt32(exactly: defaults.integer(forKey: key)) ?? UInt32.max
        }
        return Self(code: number(keys[0], fallback: legacy.code),
            modifiers: number(keys[1], fallback: legacy.modifiers),
            label: defaults.string(forKey: keys[2]) ?? legacy.label)
    }
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

/// Validated before constructing NSApplication or opening the production store.
/// Build0 permits unsigned preparation; store build allocation is a release gate.
enum ProductionConfiguration {
    static func validates(info: [String: Any]) -> Bool {
        guard info["CFBundleIdentifier"] as? String == "com.copystory.app",
              info["CFBundleName"] as? String == "CopyStory",
              info["CFBundleDisplayName"] as? String == "CopyStory",
              info["CFBundleShortVersionString"] as? String == "1.0.0",
              let build = info["CFBundleVersion"] as? String,
              build == "0" || UpdatePolicy.buildNumber(build) != nil,
              info["CopyStoryProductionBuild"] as? Bool == true,
              info["CopyStoryBuildConfiguration"] as? String == "Production",
              let revision = info["CopyStorySourceRevision"] as? String,
              revision.range(of: "^[0-9a-f]{40}$", options: .regularExpression) != nil,
              let dirty = info["CopyStorySourceDirty"] as? String,
              ["clean", "dirty"].contains(dirty),
              !info.keys.contains(where: {
                  $0.hasPrefix("SU") || $0.contains("Development") ||
                  $0.contains("Engineering") || $0.contains("NativeSourceOnly") ||
                  $0.contains("Feasibility") || $0.contains("Probe")
              }) else { return false }
        return true
    }
}
