import Foundation
import Testing
import CopyStoryCore
@testable import CopyStory

struct ProductionConfigurationTests {
    private var valid: [String: Any] {
        ["CFBundleIdentifier": "com.copystory.app", "CFBundleName": "CopyStory",
         "CFBundleDisplayName": "CopyStory", "CFBundleShortVersionString": "1.0.0",
         "CFBundleVersion": "0", "CopyStoryProductionBuild": true,
         "CopyStoryBuildConfiguration": "Production",
         "CopyStorySourceRevision": String(repeating: "a", count: 40), "CopyStorySourceDirty": "clean"]
    }
    @Test func productionPackageRequiresExplicitIdentityConfigurationAndProvenance() {
        #expect(ProductionConfiguration.validates(info: valid))
        for key in valid.keys {
            var info = valid; info.removeValue(forKey: key)
            #expect(!ProductionConfiguration.validates(info: info))
        }
        for (key, value): (String, Any) in [
            ("CFBundleIdentifier", "com.copystory.development"), ("CFBundleName", "CopyStory Development"),
            ("CFBundleShortVersionString", "0.3.0"), ("CFBundleVersion", "$(CURRENT_PROJECT_VERSION)"),
            ("CopyStoryBuildConfiguration", "Release"), ("CopyStoryProductionBuild", false),
            ("CopyStorySourceRevision", "unknown"), ("CopyStorySourceDirty", "unknown"),
            ("SUFeedURL", "https://example.invalid"), ("CopyStoryDevelopmentBuild", false),
            ("CopyStoryEngineeringOnly", true), ("CopyStoryNativeSourceOnly", true),
            ("CopyStorySandboxFeasibility", true), ("CopyStoryProbe", true)] {
            var info = valid; info[key] = value
            #expect(!ProductionConfiguration.validates(info: info))
        }
        var allocated = valid; allocated["CFBundleVersion"] = "5"
        #expect(ProductionConfiguration.validates(info: allocated))
    }
    @Test @MainActor func productionDefaultsKeepRecordingAndPasteExplicitAndStoresSeparate() throws {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("CopyStory-ProductionDefaults-\(UUID().uuidString)")
        let suite = "CopyStory.ProductionDefaults.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        let production = DevelopmentConfiguration.storeDirectory(applicationSupport: root, development: false)
        let development = DevelopmentConfiguration.storeDirectory(applicationSupport: root, development: true)
        #expect(production != development && production.lastPathComponent == "CopyStory")
        var starts = 0
        let model = AppModel(store: try HistoryStore(directory: production), demo: false,
            preferenceStore: defaults, developmentDefaults: false, recordingStarter: { starts += 1 })
        defer { model.stop() }
        #expect(!model.onboardingComplete && !model.directPasteEnabled && !model.loginEnabled)
        #expect(model.shortcutEnabled)
        model.startRecording(); #expect(starts == 0)
        model.finishOnboarding(launchAtLogin: false)
        #expect(starts == 1 && model.onboardingComplete && !model.directPasteEnabled && !model.loginEnabled)
    }
    @Test @MainActor func ordinaryDiagnosticSinkDoesNotSampleGeometryOutsideDevelopment() {
        var sampled = false
        HistoryPresentationDiagnostics.system().emitGeometry(requestGeneration: nil) {
            sampled = true
            preconditionFailure("Inert sink must not sample")
        }
        #expect(!sampled)
    }
}
