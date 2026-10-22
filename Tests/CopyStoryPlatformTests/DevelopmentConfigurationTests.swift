import Foundation
import Testing
@testable import CopyStoryCore
@testable import CopyStory

struct DevelopmentConfigurationTests {
    @Test func nilDevelopmentSuiteReportsPreferenceConstructionWithoutFallback() throws {
        var requestedSuites: [String] = []
        var failures: [StartupFailure] = []
        do {
            let _: (Int, UserDefaults?) = try StartupStorage.prepare(history: { 1 }, preferences: {
                try StartupStorage.preferences(development: true, demo: false, makeSuite: {
                    requestedSuites.append($0); return nil
                })
            }, reportFailure: { failures.append($0) })
            Issue.record("Expected failed suite construction")
        } catch let error as CocoaError { #expect(error.code == .fileReadUnknown) }
        #expect(requestedSuites == [DevelopmentConfiguration.bundleID])
        #expect(failures.count == 1 && failures.first?.stage == .preferencesConstruction)
        #expect(failures.first?.domain == .cocoa && failures.first?.code == CocoaError.fileReadUnknown.rawValue)
        for (development, demo) in [(false, false), (true, true)] {
            let preferences = try StartupStorage.preferences(development: development, demo: demo, makeSuite: { _ in
                Issue.record("Should not construct development preferences"); return nil
            })
            #expect(preferences == nil)
        }
    }

    @Test func startupPreferenceFailureIsDistinctAndPreservesOriginalError() throws {
        let original = NSError(domain: NSCocoaErrorDomain, code: 256, userInfo: [
            NSLocalizedDescriptionKey: "private preference description", NSFilePathErrorKey: "/private/preferences"])
        var calls: [String] = []
        var failures: [StartupFailure] = []
        do {
            let _: (Int, Int) = try StartupStorage.prepare(history: { calls.append("history"); return 1 }, preferences: {
                calls.append("preferences"); throw original
            }, reportFailure: { failures.append($0) })
            Issue.record("Expected preference failure")
        } catch { #expect(error as NSError === original) }
        #expect(calls == ["history", "preferences"])
        #expect(failures.count == 1)
        #expect(failures.first?.stage == .preferencesConstruction)
        #expect(failures.first?.summary == "stage=preferencesConstruction category=system domain=NSCocoaErrorDomain code=256")
    }

    @Test(arguments: [StartupStage.historyRecoveryQuery, .historyRecoveryTransaction, .historyRecoveryEnumeration])
    func startupRecoveryFailureStopsBeforePreferenceConstruction(stage: StartupStage) throws {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("CopyStory-Startup-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let original = NSError(domain: NSPOSIXErrorDomain, code: 13)
        var constructedPreferences = false
        var failures: [StartupFailure] = []
        let diagnostic = HistoryInitializationDiagnostics(reportFailure: { failures.append($0) }, beforeStage: {
            if $0 == stage { throw original }
        })
        do {
            let _: (HistoryStore, Int) = try StartupStorage.prepare(history: {
                try HistoryStore(directory: root, initialization: diagnostic)
            }, preferences: { constructedPreferences = true; return 1 }, reportFailure: { failures.append($0) })
            Issue.record("Expected post-schema recovery failure")
        } catch { #expect(error as NSError === original) }
        #expect(!constructedPreferences)
        #expect(failures.count == 1 && failures.first?.stage == stage)
    }

    @Test func startupSuccessReportsNoFailure() throws {
        var failures: [StartupFailure] = []
        let result = try StartupStorage.prepare(history: { 1 }, preferences: { 2 }, reportFailure: { failures.append($0) })
        #expect(result.0 == 1 && result.1 == 2 && failures.isEmpty)
    }

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
