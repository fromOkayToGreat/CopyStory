import Foundation
import Testing
import CopyStoryCore
@testable import CopyStory

struct DevelopmentConfigurationTests {
    @Test @MainActor func onboardingGuardsInjectedRecordingEffectAndPersistsOnlyExplicitConsent() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("CopyStory-Consent-\(UUID().uuidString)")
        let suite = "CopyStory.Consent.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        var starts = 0
        let model = AppModel(store: try HistoryStore(directory: root), demo: false,
            preferenceStore: defaults, developmentDefaults: true, recordingStarter: { starts += 1 })
        defer { model.stop() }
        #expect(!model.onboardingComplete && !model.shortcutEnabled && !model.directPasteEnabled)
        model.startRecording()
        #expect(starts == 0 && !defaults.bool(forKey: "onboardingComplete"))
        // Closing onboarding has no consent/model callback. Retrying a start
        // without finishOnboarding must still produce no recording effect.
        model.startRecording()
        #expect(starts == 0)
        model.finishOnboarding(launchAtLogin: false)
        #expect(starts == 1 && model.onboardingComplete && defaults.bool(forKey: "onboardingComplete"))
        #expect(!model.loginEnabled && !model.shortcutEnabled && !model.directPasteEnabled)
        _ = model.prepareForTermination()
        model.startRecording()
        #expect(starts == 1)
    }
    @Test @MainActor func previewNeverStartsInjectedRecordingEffect() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("CopyStory-PreviewConsent-\(UUID().uuidString)")
        let suite = "CopyStory.PreviewConsent.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        var starts = 0
        let model = AppModel(store: try HistoryStore(directory: root), demo: true,
            preferenceStore: defaults, developmentDefaults: true, recordingStarter: { starts += 1 })
        model.startRecording(); model.finishOnboarding(launchAtLogin: false)
        #expect(starts == 0)
        model.stop()
    }
    @Test func separateStoreAndPackageIdentityAreRequired() {
        let support = URL(fileURLWithPath: "/synthetic/Application Support", isDirectory: true)
        #expect(DevelopmentConfiguration.storeDirectory(applicationSupport: support, development: true).lastPathComponent == "CopyStory Development")
        #expect(DevelopmentConfiguration.storeDirectory(applicationSupport: support, development: false).lastPathComponent == "CopyStory")
        let valid: [String: Any] = ["CFBundleIdentifier": "com.copystory.development",
            "CopyStoryDevelopmentBuild": true, "CopyStorySourceRevision": String(repeating: "a", count: 40),
            "CopyStorySourceDirty": "clean", "CopyStoryBuildConfiguration": "Debug"]
        #expect(DevelopmentConfiguration.validates(info: valid))
        for (key, value): (String, Any) in [
            ("CFBundleIdentifier", "com.copystory.app"), ("CopyStoryDevelopmentBuild", false),
            ("CopyStorySourceRevision", "$(COPYSTORY_SOURCE_REVISION)"), ("CopyStorySourceDirty", "unknown"),
            ("CopyStoryBuildConfiguration", "Release"), ("SUFeedURL", "https://example.invalid"),
            ("CopyStoryNativeSourceOnly", true), ("CopyStorySandboxFeasibility", true)] {
            var info = valid; info[key] = value
            #expect(!DevelopmentConfiguration.validates(info: info))
        }
    }
}
