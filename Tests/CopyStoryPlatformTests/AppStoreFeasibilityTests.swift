import Foundation
import Testing
import CopyStoryCore
@testable import CopyStory

@Suite struct AppStoreFeasibilityTests {
    @MainActor @Test func sandboxPreviewDoesNotRegisterOrChangeGlobalShortcut() throws {
        guard AppDistribution.isAppStore else { return }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let suite = "test.copystory.sandbox-preview.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppModel(store: try HistoryStore(directory: directory), demo: true, preferenceStore: defaults)
        let original = (model.shortcutCode, model.shortcutModifiers, model.shortcutLabel)
        model.registerHotkey()
        // This would reach platform validation and report an invalid shortcut if
        // the preview were allowed to attempt registration.
        model.changeShortcut(code: .max, modifiers: 0, label: "Invalid probe shortcut")
        #expect(model.shortcutError == nil)
        #expect(model.shortcutCode == original.0)
        #expect(model.shortcutModifiers == original.1)
        #expect(model.shortcutLabel == original.2)
        #expect(defaults.persistentDomain(forName: suite)?["shortcutCode"] == nil)
    }
}
