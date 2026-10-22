import Foundation
import Testing
@testable import CopyStoryCore
@testable import CopyStory

struct DevelopmentConfigurationTests {
    @Test func developmentSelectsCurrentAppDefaultsProviderOnce() throws {
        let suite = "CopyStory.StartupSelection.\(UUID().uuidString)"
        let sentinel = try #require(UserDefaults(suiteName: suite))
        defer { sentinel.removePersistentDomain(forName: suite) }
        var calls = 0
        var failures: [StartupFailure] = []
        let (_, selected) = try StartupStorage.prepare(history: { 1 }, preferences: {
            StartupStorage.preferences(development: true, demo: false, currentAppDefaults: {
                calls += 1; return sentinel
            })
        }, reportFailure: { failures.append($0) })
        #expect(selected === sentinel && calls == 1 && failures.isEmpty)
    }

    @Test func previewAndNondevelopmentSkipDevelopmentProvider() throws {
        let suite = "CopyStory.UnusedStartupProvider.\(UUID().uuidString)"
        let sentinel = try #require(UserDefaults(suiteName: suite))
        defer { sentinel.removePersistentDomain(forName: suite) }
        var calls = 0
        for (development, demo) in [(false, false), (false, true), (true, true)] {
            let preferences = StartupStorage.preferences(development: development, demo: demo, currentAppDefaults: {
                calls += 1; return sentinel
            })
            #expect(preferences == nil)
        }
        #expect(calls == 0)
    }

    @Test @MainActor func selectedPreferencesKeepOtherDomainConsentAndDefaultsIsolated() throws {
        let suite = "CopyStory.StartupIsolation.\(UUID().uuidString)"
        let otherSuite = "CopyStory.OtherSyntheticApp.\(UUID().uuidString)"
        let selected = try #require(UserDefaults(suiteName: suite))
        let other = try #require(UserDefaults(suiteName: otherSuite))
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("CopyStory-StartupIsolation-\(UUID().uuidString)")
        defer {
            selected.removePersistentDomain(forName: suite)
            other.removePersistentDomain(forName: otherSuite)
            try? FileManager.default.removeItem(at: root)
        }
        for key in ["onboardingComplete", "shortcutEnabled", "directPasteEnabled"] { other.set(true, forKey: key) }
        let preferences = StartupStorage.preferences(development: true, demo: false, currentAppDefaults: { selected })
        var starts = 0
        let model = AppModel(store: try HistoryStore(directory: root), demo: false,
            preferenceStore: preferences, developmentDefaults: true, recordingStarter: { starts += 1 })
        defer { model.stop() }
        #expect(!model.onboardingComplete && !model.shortcutEnabled && !model.directPasteEnabled && !model.loginEnabled)
        model.startRecording()
        #expect(starts == 0 && !selected.bool(forKey: "onboardingComplete"))
        for key in ["onboardingComplete", "shortcutEnabled", "directPasteEnabled"] { #expect(other.bool(forKey: key)) }
        selected.set("development-only", forKey: "syntheticIsolationMarker")
        #expect(other.string(forKey: "syntheticIsolationMarker") == nil)
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
