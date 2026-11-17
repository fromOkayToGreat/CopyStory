// Pure configuration assertions only. No NSApplication, stores, clipboard or permissions.
import Foundation
import CopyStoryCore

@main struct TestFlightConfigurationCheck {
    static func main() {
        precondition(ProductionConfiguration.testFlight)
        precondition(AppDistribution.directPasteAvailable)
        precondition(!DevelopmentConfiguration.enabled && !DevelopmentConfiguration.directPasteTest)
        precondition(DevelopmentConfiguration.preferenceDefaults(development: false)["directPasteEnabled"] as? Bool == false)
        precondition(DevelopmentConfiguration.storeDirectory(applicationSupport: URL(fileURLWithPath: "/synthetic"), development: false).lastPathComponent == "CopyStory")
        var beta: [String: Any] = ["CFBundleIdentifier": "com.copystory.app", "CFBundleName": "CopyStory",
            "CFBundleDisplayName": "CopyStory", "CFBundleShortVersionString": "1.0.0", "CFBundleVersion": "23",
            "CopyStoryProductionBuild": true, "CopyStoryTestFlightBuild": true,
            "CopyStoryBuildConfiguration": "TestFlight", "CopyStorySourceRevision": String(repeating: "a", count: 40),
            "CopyStorySourceDirty": "clean"]
        precondition(ProductionConfiguration.validates(info: beta))
        beta["CopyStoryBuildConfiguration"] = "Production"
        beta.removeValue(forKey: "CopyStoryTestFlightBuild")
        precondition(!ProductionConfiguration.validates(info: beta))
        print("PASS: actual TestFlight flags enable Direct Paste, keep opt-in OFF, use store identity, and reject Production metadata; no native effects")
    }
}
