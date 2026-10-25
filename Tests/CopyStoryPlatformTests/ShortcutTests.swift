import Carbon
import Foundation
import Testing
import CopyStoryCore
@testable import CopyStory

/// No Carbon calls, app launch, keyboard input, clipboard, consent or login effects.
@MainActor
struct ShortcutTests {
    final class CarbonRecorder {
        var events: [String] = []
        var failInstall = false
        var failRegister = false
        var nextHandle = 1
        var operations: GlobalHotKey.Operations {
            .init(install: { _ in
                self.events.append("install")
                if self.failInstall { throw PlatformServiceError.hotKey(-9878) }
                return EventHandlerRef(bitPattern: 100)!
            }, register: { code, modifiers in
                self.events.append("register:\(code):\(modifiers)")
                if self.failRegister { throw PlatformServiceError.hotKey(-9878) }
                defer { self.nextHandle += 1 }
                return EventHotKeyRef(bitPattern: self.nextHandle)!
            }, unregister: { handle in self.events.append("unregister:\(Int(bitPattern: handle))") },
               removeHandler: { _ in self.events.append("removeHandler") })
        }
        @MainActor func hotkey() -> GlobalHotKey { GlobalHotKey(onTrigger: {}, operations: operations) }
    }
    final class Fixture {
        let suite = "CopyStory.ShortcutTests.\(UUID().uuidString)"
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("CopyStory-ShortcutTests-\(UUID().uuidString)")
        let defaults: UserDefaults
        let carbon = CarbonRecorder()
        private var historyStore: HistoryStore?
        init() throws { defaults = try #require(UserDefaults(suiteName: suite)) }
        @MainActor func model(development: Bool = false, demo: Bool = false) throws -> AppModel {
            if historyStore == nil { historyStore = try HistoryStore(directory: root) }
            return AppModel(store: historyStore!, demo: demo, preferenceStore: defaults,
                developmentDefaults: development, hotkey: carbon.hotkey())
        }
        func cleanup() {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        var saved: [String: Any] { defaults.persistentDomain(forName: suite) ?? [:] }
        func save(_ shortcut: HistoryShortcut) {
            defaults.set(Int(shortcut.code), forKey: "shortcutCode")
            defaults.set(Int(shortcut.modifiers), forKey: "shortcutModifiers")
            defaults.set(shortcut.label, forKey: "shortcutLabel")
        }
    }

    @Test func standardIsPhysicalOptionV() throws {
        #expect(HistoryShortcut.standard.code == UInt32(kVK_ANSI_V))
        #expect(HistoryShortcut.standard.modifiers == UInt32(optionKey))
        #expect(HistoryShortcut.standard.label == "⌥V")
        #expect(HistoryShortcut.legacy.code == UInt32(kVK_ANSI_H))
        #expect(HistoryShortcut.legacy.modifiers == UInt32(cmdKey | shiftKey))
    }

    @Test func freshAndUnsavedLegacyDefaultsResolveToOptionVWithoutWritingPreferences() throws {
        let f = try Fixture(); defer { f.cleanup() }
        // Old production defaults were registered only, never saved by startup.
        #expect(f.saved.isEmpty)
        let model = try f.model(); defer { model.stop() }
        #expect(model.shortcutCode == 9 && model.shortcutModifiers == 2048 && model.shortcutLabel == "⌥V")
        #expect(model.shortcutEnabled)
        #expect(f.saved.isEmpty)
        model.registerHotkey()
        #expect(f.carbon.events == ["install", "register:9:2048"])
        #expect(model.shortcutRegistered && model.shortcutError == nil)
        #expect(!model.handlesShortcut(keyCode: 4, modifiers: 768))
        #expect(model.handlesShortcut(keyCode: 9, modifiers: 2048))
        #expect(!model.handlesShortcut(keyCode: 9, modifiers: 2048 | 256))
    }

    @Test func existingInstallWithoutSavedBindingAndRepeatedModelLoadsUseNewDefault() throws {
        let f = try Fixture(); defer { f.cleanup() }
        f.defaults.set(true, forKey: "onboardingComplete")
        f.defaults.set(true, forKey: "directPasteEnabled")
        for _ in 0..<2 {
            let model = try f.model(); defer { model.stop() }
            #expect(model.onboardingComplete && model.directPasteEnabled)
            #expect(model.shortcutCode == 9 && model.shortcutModifiers == 2048 && model.shortcutLabel == "⌥V")
        }
        #expect(f.saved.count == 2)
        #expect(f.saved["shortcutCode"] == nil && f.saved["shortcutModifiers"] == nil && f.saved["shortcutLabel"] == nil)
    }

    @Test(arguments: [HistoryShortcut.legacy, HistoryShortcut(code: 35, modifiers: 4352, label: "⌃⌘P"), HistoryShortcut.standard])
    func everySavedChoiceIsPreservedOnRepeatedLoads(_ shortcut: HistoryShortcut) throws {
        let f = try Fixture(); defer { f.cleanup() }
        f.save(shortcut)
        for _ in 0..<2 {
            let model = try f.model(); defer { model.stop() }
            #expect(model.shortcutCode == shortcut.code && model.shortcutModifiers == shortcut.modifiers && model.shortcutLabel == shortcut.label)
            model.registerHotkey()
            #expect(model.handlesShortcut(keyCode: shortcut.code, modifiers: shortcut.modifiers))
        }
        #expect(HistoryShortcut.load(from: f.defaults) == shortcut)
        #expect(f.saved.count == 3)
    }

    @Test func partialLegacyRecordKeepsLegacyFallbacksInsteadOfMixingNewDefault() throws {
        let f = try Fixture(); defer { f.cleanup() }
        f.defaults.set(4, forKey: "shortcutCode")
        #expect(HistoryShortcut.load(from: f.defaults) == .legacy)
        #expect(f.saved.count == 1)
        f.defaults.removeObject(forKey: "shortcutCode")
        f.defaults.set(768, forKey: "shortcutModifiers")
        #expect(HistoryShortcut.load(from: f.defaults) == .legacy)
        f.defaults.removeObject(forKey: "shortcutModifiers")
        f.defaults.set("Kept label", forKey: "shortcutLabel")
        #expect(HistoryShortcut.load(from: f.defaults) == .init(code: 4, modifiers: 768, label: "Kept label"))
    }

    @Test func disabledSavedChoiceAndDevelopmentDefaultStayDisabled() throws {
        let f = try Fixture(); defer { f.cleanup() }
        let development = try f.model(development: true); defer { development.stop() }
        development.registerHotkey()
        #expect(!development.shortcutEnabled && development.shortcutLabel == "⌥V")
        #expect(development.shortcutStatusLabel == "Global shortcut off")
        #expect(f.carbon.events.isEmpty)
        f.save(.legacy); f.defaults.set(false, forKey: "shortcutEnabled")
        let production = try f.model(); defer { production.stop() }
        production.registerHotkey()
        #expect(!production.shortcutEnabled && production.shortcutCode == 4)
        #expect(!production.handlesShortcut(keyCode: 4, modifiers: 768))
        #expect(f.carbon.events.isEmpty)
    }

    @Test func customizationPersistsAndSuccessfulReplacementReleasesOldBinding() throws {
        let f = try Fixture(); defer { f.cleanup() }
        f.save(.legacy)
        let model = try f.model(); defer { model.stop() }
        model.registerHotkey()
        model.changeShortcut(code: 9, modifiers: 2048, label: "⌥V")
        #expect(f.carbon.events == ["install", "register:4:768", "register:9:2048", "unregister:1"])
        #expect(HistoryShortcut.load(from: f.defaults) == .standard)
        #expect(!model.handlesShortcut(keyCode: 4, modifiers: 768))
        #expect(model.handlesShortcut(keyCode: 9, modifiers: 2048))
        model.changeShortcut(code: 35, modifiers: 4352, label: "⌃⌘P")
        #expect(f.carbon.events.suffix(2) == ["register:35:4352", "unregister:2"])
        model.stop()
        let reloaded = try f.model(); defer { reloaded.stop() }
        #expect(reloaded.shortcutCode == 35 && reloaded.shortcutModifiers == 4352 && reloaded.shortcutLabel == "⌃⌘P")
    }

    @Test func startupCollisionIsTruthfulHasNoFallbackAndCanRetry() throws {
        let f = try Fixture(); defer { f.cleanup() }
        f.carbon.failRegister = true
        let model = try f.model(); defer { model.stop() }
        model.registerHotkey()
        #expect(!model.shortcutRegistered)
        #expect(model.shortcutStatusLabel == "⌥V unavailable")
        #expect(model.shortcutError?.contains("menu bar") == true)
        #expect(!model.handlesShortcut(keyCode: 9, modifiers: 2048))
        #expect(!model.handlesShortcut(keyCode: 4, modifiers: 768))
        #expect(f.carbon.events == ["install", "register:9:2048"])
        #expect(f.saved.isEmpty)
        f.carbon.failRegister = false
        model.registerHotkey()
        #expect(model.shortcutRegistered && model.shortcutError == nil)
        #expect(f.carbon.events == ["install", "register:9:2048", "register:9:2048"])
    }

    @Test func failedCustomChangeKeepsActualPreviousRegistrationAndPreferences() throws {
        let f = try Fixture(); defer { f.cleanup() }
        f.save(.legacy)
        let model = try f.model(); defer { model.stop() }
        model.registerHotkey()
        f.carbon.failRegister = true
        model.registeringShortcut = true
        model.changeShortcut(code: 9, modifiers: 2048, label: "⌥V")
        #expect(model.shortcutError?.contains("previous shortcut is still selected") == true)
        #expect(!model.registeringShortcut && model.shortcutRegistered)
        #expect(model.handlesShortcut(keyCode: 4, modifiers: 768))
        #expect(!model.handlesShortcut(keyCode: 9, modifiers: 2048))
        #expect(HistoryShortcut.load(from: f.defaults) == .legacy)
        #expect(f.carbon.events == ["install", "register:4:768", "register:9:2048"])
    }

    @Test func disableReenableStopAndSameBindingAreIdempotent() throws {
        let f = try Fixture(); defer { f.cleanup() }
        let model = try f.model(); defer { model.stop() }
        model.registerHotkey(); model.registerHotkey()
        #expect(f.carbon.events == ["install", "register:9:2048"])
        model.setShortcutEnabled(false); model.setShortcutEnabled(false)
        #expect(!model.shortcutRegistered && model.shortcutError == nil)
        #expect(!model.handlesShortcut(keyCode: 9, modifiers: 2048))
        #expect(!f.defaults.bool(forKey: "shortcutEnabled"))
        #expect(f.carbon.events.suffix(2) == ["unregister:1", "removeHandler"])
        model.setShortcutEnabled(true)
        #expect(model.shortcutRegistered && f.defaults.bool(forKey: "shortcutEnabled"))
        #expect(f.carbon.events.suffix(2) == ["install", "register:9:2048"])
        model.stop(); model.stop()
        #expect(!model.shortcutRegistered)
        #expect(f.carbon.events.suffix(2) == ["unregister:2", "removeHandler"])
        #expect(f.carbon.events.count == 8)
    }

    @Test func disabledEditingValidatesAndPersistsWithoutRegistering() throws {
        let f = try Fixture(); defer { f.cleanup() }
        f.defaults.set(false, forKey: "shortcutEnabled")
        let model = try f.model(); defer { model.stop() }
        model.changeShortcut(code: 35, modifiers: 4352, label: "⌃⌘P")
        #expect(f.carbon.events.isEmpty)
        #expect(model.shortcutCode == 35 && !model.shortcutRegistered)
        model.changeShortcut(code: 999, modifiers: 0, label: "Invalid")
        #expect(model.shortcutCode == 35 && model.shortcutError != nil)
        #expect(HistoryShortcut.load(from: f.defaults).code == 35)
    }

    @Test func invalidSavedNumbersDoNotCrashOrSilentlyAcquireNewBinding() throws {
        let f = try Fixture(); defer { f.cleanup() }
        f.defaults.set(-1, forKey: "shortcutCode")
        let model = try f.model(); defer { model.stop() }
        model.registerHotkey()
        #expect(model.shortcutCode == UInt32.max && !model.shortcutRegistered && model.shortcutError != nil)
        #expect(f.carbon.events.isEmpty)
        #expect(f.defaults.integer(forKey: "shortcutCode") == -1)
    }

    @Test func handlerFailureAndTeardownReleaseOnlyOwnedResources() throws {
        let carbon = CarbonRecorder()
        carbon.failInstall = true
        var hotkey: GlobalHotKey? = carbon.hotkey()
        #expect(throws: (any Error).self) { try hotkey?.register(keyCode: 9, modifiers: 2048) }
        #expect(hotkey?.isRegistered == false && carbon.events == ["install"])
        carbon.failInstall = false; carbon.failRegister = true
        #expect(throws: (any Error).self) { try hotkey?.register(keyCode: 9, modifiers: 2048) }
        hotkey = nil
        #expect(carbon.events == ["install", "install", "register:9:2048", "removeHandler"])
        carbon.events = []; carbon.failRegister = false
        hotkey = carbon.hotkey()
        try hotkey?.register(keyCode: 9, modifiers: 2048)
        hotkey = nil
        #expect(carbon.events == ["install", "register:9:2048", "unregister:1", "removeHandler"])
    }

    @Test func appStorePreviewNeverRegistersEvenWithInjectedOperations() throws {
        let f = try Fixture(); defer { f.cleanup() }
        let model = try f.model(demo: true); defer { model.stop() }
        model.registerHotkey()
        model.setShortcutEnabled(true)
        model.changeShortcut(code: 35, modifiers: 4352, label: "⌃⌘P")
        #expect(f.carbon.events.isEmpty && f.saved.isEmpty)
        #expect(model.shortcutLabel == "⌥V")
    }
}
