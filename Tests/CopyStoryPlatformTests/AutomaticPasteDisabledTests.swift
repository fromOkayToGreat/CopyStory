import Testing
@testable import CopyStory
@Suite struct AutomaticPasteDisabledTests {
    @Test func rejectedPasteDoesNotWriteAdmitOrDismiss() {
        var writes = 0; var admissions = 0; var dismissals = 0
        let result = AutomaticPastePolicy.request(write: { writes += 1 },
            admit: { admissions += 1 }, close: { dismissals += 1 })
        #expect(!AutomaticPastePolicy.enabled)
        #expect(writes == 0); #expect(admissions == 0); #expect(dismissals == 0)
        #expect(result.contains("Nothing was copied or sent"))
    }
    @MainActor @Test func disabledPermissionAndDestinationOperationsHaveNoState() {
        let coordinator = PasteCoordinator()
        coordinator.rememberDestination()
        PasteCoordinator.requestAccessibility()
        PasteCoordinator.openAccessibilitySettings()
        #expect(!PasteCoordinator.accessibilityGranted)
        #expect(!coordinator.isPasting)
    }
}
