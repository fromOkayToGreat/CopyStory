import AppKit
import Testing
import CopyStoryCore
@testable import CopyStory

@Suite(.serialized) @MainActor
struct HistoryInteractionTests {
    @Test func mouseDragRequiresDeliberateHorizontalDistance() {
        for translation in [CGSize.zero, CGSize(width: -7, height: 0), CGSize(width: -31, height: 0),
                            CGSize(width: -40, height: 40), CGSize(width: -40, height: 100)] {
            #expect(HistoryMouseDrag.destination(translation: translation, revealed: false) == nil)
        }
        #expect(HistoryMouseDrag.destination(translation: CGSize(width: -32, height: 2), revealed: false) == true)
        #expect(HistoryMouseDrag.destination(translation: CGSize(width: -1000, height: 0), revealed: false) == true)
        // The outcome is a reveal flag only; even an extreme drag cannot delete.
        #expect(HistoryMouseDrag.offset(translation: CGSize(width: -1000, height: 0), revealed: false) == -90)
    }

    @Test func mouseRightDragOnlyClosesAnAlreadyRevealedAction() {
        let right = CGSize(width: 50, height: 2)
        #expect(HistoryMouseDrag.destination(translation: right, revealed: false) == nil)
        #expect(HistoryMouseDrag.offset(translation: right, revealed: false) == 0)
        #expect(HistoryMouseDrag.destination(translation: right, revealed: true) == false)
        #expect(HistoryMouseDrag.offset(translation: right, revealed: true) == -40)
        #expect(HistoryMouseDrag.offset(translation: CGSize(width: 1000, height: 0), revealed: true) == 0)
    }

    @Test func canceledOrReversedMouseDragReturnsToExistingRevealState() {
        // GestureState returns to zero on cancellation; no onEnded action runs.
        for revealed in [false, true] {
            #expect(HistoryMouseDrag.offset(translation: .zero, revealed: revealed) == (revealed ? -90 : 0))
            #expect(HistoryMouseDrag.destination(translation: .zero, revealed: revealed) == nil)
            // Travel can cross a threshold then return before release. Only the
            // final displacement commits, so reversing back cancels the reveal.
            _ = HistoryMouseDrag.offset(translation: CGSize(width: -60, height: 0), revealed: revealed)
            #expect(HistoryMouseDrag.destination(translation: CGSize(width: -3, height: 0), revealed: revealed) == nil)
        }
    }

    @Test func verticalMouseMovementNeverMovesTheRowOrCommitsAnAction() {
        for revealed in [false, true] {
            for y: CGFloat in [-400, -40, 40, 400] {
                let vertical = CGSize(width: 5, height: y)
                #expect(HistoryMouseDrag.offset(translation: vertical, revealed: revealed) == (revealed ? -90 : 0))
                #expect(HistoryMouseDrag.destination(translation: vertical, revealed: revealed) == nil)
            }
        }
    }

    @Test func deletionKeysRespectScopeFocusModifiersSelectionAndRepeat() {
        func action(_ code: UInt16 = 51, characters: String? = nil, flags: NSEvent.ModifierFlags = [], repeatKey: Bool = false,
                    history: Bool = true, editing: Bool = false, searching: Bool = false,
                    busy: Bool = false, selected: Bool = true, undo: Bool = true) -> HistoryDeletionKeys.Action? {
            HistoryDeletionKeys.action(keyCode: code, characters: characters, modifiers: flags, repeating: repeatKey,
                history: history, editable: editing, searching: searching, busy: busy, selected: selected, canUndo: undo)
        }
        #expect(action() == .delete)
        #expect(action(flags: .command) == .delete) // Existing shortcut remains available.
        #expect(action(repeatKey: true) == .consumeRepeat)
        #expect(action(editing: true) == nil)
        #expect(action(history: false) == nil)
        #expect(action(searching: true) == nil)
        #expect(action(busy: true) == nil)
        #expect(action(selected: false) == nil)
        for flags: NSEvent.ModifierFlags in [.option, .control, .shift, [.command, .shift], .function] {
            #expect(action(flags: flags) == nil)
        }
        for code: UInt16 in [36, 76, 8, 125, 126, 117, 53] { #expect(action(code) == nil) }
        #expect(action(6, characters: "z", flags: .command) == .undo)
        #expect(action(6, characters: "z", flags: .command, undo: false) == nil)
        #expect(action(6, characters: "z", flags: .command, editing: true) == nil)
        #expect(HistoryDeletionKeys.isEditing(NSTextView()))
        #expect(HistoryDeletionKeys.isEditing(NSTextField()))
        #expect(!HistoryDeletionKeys.isEditing(NSView()))
        #expect(!HistoryDeletionKeys.isEditing(nil))
    }

    @Test func swipesRequireHorizontalIntentAndOnlyReveal() {
        var swipe = HistorySwipeIntent()
        #expect(swipe.update(dx: 3, dy: 1) == nil)
        #expect(swipe.update(dx: 12, dy: 1) == nil)
        #expect(swipe.update(dx: 20, dy: 0) == true)
        #expect(swipe.axis == .horizontal)
        swipe.reset()
        #expect(swipe.update(dx: -40, dy: 2) == false) // Close only; no right action.
        swipe.reset()
        #expect(swipe.update(dx: -4, dy: -9) == nil)
        #expect(swipe.update(dx: -200, dy: 0) == nil) // Vertical lock survives lateral drift.
        #expect(swipe.axis == .vertical)
        swipe.reset()
        #expect(swipe.update(dx: -10, dy: -10) == nil) // Ambiguous diagonal stays scrolling.
        #expect(swipe.update(dx: -300, dy: 0) == nil)
        swipe.reset()
        #expect(swipe.update(dx: 1000, dy: 0) == true) // Even a full swipe is just reveal.
    }

    @Test func undoUsesLayoutCharacterRatherThanUSKeyPosition() {
        func action(code: UInt16, character: String?, flags: NSEvent.ModifierFlags = .command,
                    editing: Bool = false, history: Bool = true, repeatKey: Bool = false) -> HistoryDeletionKeys.Action? {
            HistoryDeletionKeys.action(keyCode: code, characters: character, modifiers: flags, repeating: repeatKey,
                history: history, editable: editing, searching: false, busy: false, selected: true, canUndo: true)
        }
        #expect(action(code: 16, character: "z") == .undo) // Z at a different physical position.
        #expect(action(code: 16, character: "Z") == .undo) // Caps Lock does not change the equivalent.
        #expect(action(code: 6, character: "y") == nil) // US Z position produces another character.
        #expect(action(code: 6, character: nil) == nil)
        #expect(action(code: 16, character: "z", editing: true) == nil)
        #expect(action(code: 16, character: "z", history: false) == nil)
        #expect(action(code: 16, character: "z", flags: [.command, .shift]) == nil)
        #expect(action(code: 16, character: "z", flags: []) == nil)
        #expect(action(code: 16, character: "z", repeatKey: true) == .consumeRepeat)
    }

    @Test func samePhysicalSwipeHasSameResultWithEitherNaturalScrollingSetting() {
        for inverted in [false, true] {
            let rawSign: CGFloat = inverted ? -1 : 1
            var swipe = HistorySwipeSession()
            #expect(!swipe.handle(dx: 0, dy: 0, invertedFromDevice: inverted, phase: .began, momentumPhase: []).consume)
            let left = swipe.handle(dx: 40 * rawSign, dy: 2 * rawSign, invertedFromDevice: inverted, phase: .changed, momentumPhase: [])
            #expect(left == .init(consume: true, reveal: true))
            _ = swipe.handle(dx: 0, dy: 0, invertedFromDevice: inverted, phase: .ended, momentumPhase: [])
            _ = swipe.handle(dx: 0, dy: 0, invertedFromDevice: inverted, phase: .began, momentumPhase: [])
            let right = swipe.handle(dx: -40 * rawSign, dy: 2 * rawSign, invertedFromDevice: inverted, phase: .changed, momentumPhase: [])
            #expect(right == .init(consume: true, reveal: false))
        }
    }

    @Test func fingerUpWithoutMomentumDoesNotCaptureUnphasedOrNewVerticalInput() {
        var swipe = HistorySwipeSession()
        _ = swipe.handle(dx: 40, dy: 0, invertedFromDevice: false, phase: .began, momentumPhase: [])
        #expect(swipe.tracking)
        let ended = swipe.handle(dx: 0, dy: 0, invertedFromDevice: false, phase: .ended, momentumPhase: [])
        #expect(ended.consume && ended.reveal == nil)
        #expect(!swipe.tracking && swipe.suppressMomentum)
        let wheel = swipe.handle(dx: 100, dy: 100, invertedFromDevice: false, phase: [], momentumPhase: [])
        #expect(wheel == .init())
        #expect(!swipe.tracking && !swipe.suppressMomentum)
        // A missing .began cannot inherit the previous row's horizontal intent.
        #expect(swipe.handle(dx: 100, dy: 0, invertedFromDevice: false, phase: .changed, momentumPhase: []) == .init())
        #expect(swipe.handle(dx: 0, dy: 40, invertedFromDevice: false, phase: .began, momentumPhase: []) == .init())
        #expect(swipe.handle(dx: 100, dy: 0, invertedFromDevice: false, phase: .changed, momentumPhase: []) == .init())
    }

    @Test func momentumSuppressionIsSeparateFromGestureAndEndsOrCancels() {
        var swipe = HistorySwipeSession()
        func event(_ phase: NSEvent.Phase = [], momentum: NSEvent.Phase = [], dx: CGFloat = 0, dy: CGFloat = 0) -> HistorySwipeSession.Result {
            swipe.handle(dx: dx, dy: dy, invertedFromDevice: false, phase: phase, momentumPhase: momentum)
        }
        #expect(event(.began, dx: 40).reveal == true)
        #expect(event(.ended).consume)
        #expect(!swipe.tracking)
        for phase: NSEvent.Phase in [.began, .changed, .ended] {
            #expect(event(momentum: phase, dx: -300) == .init(consume: true)) // Momentum cannot reveal/close.
        }
        #expect(!swipe.tracking && !swipe.suppressMomentum)
        #expect(event(momentum: .changed, dx: 100) == .init())
        _ = event(.began, dx: 40)
        #expect(event(.cancelled).consume)
        #expect(!swipe.tracking && !swipe.suppressMomentum)
        #expect(event(momentum: .began, dx: 40) == .init())
        _ = event(.began, dx: 40); _ = event(.ended)
        #expect(event(.mayBegin) == .init())
        #expect(!swipe.suppressMomentum)
        #expect(event(.began, dy: 40) == .init())
        #expect(event(.ended) == .init())
        #expect(event(momentum: .began, dy: 40) == .init())
        // A new horizontal gesture also starts with fresh direction/thresholds.
        #expect(event(.began, dx: -40).reveal == false)
    }

    @Test func modelDeletionUndoAndClearUseOnlyFixtureStore() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("CopyStory-Interaction-\(UUID())")
        let suite = "CopyStory.Interaction.\(UUID())"
        // Use a named disposable domain; never initialize default app history.
        let preferences = UserDefaults(suiteName: suite)!
        defer { preferences.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        let store = try HistoryStore(directory: root)
        let model = AppModel(store: store, demo: true, preferenceStore: preferences)
        _ = try await store.capture(CapturePayload(text: "First fixture"), limits: .init())
        _ = try await store.capture(CapturePayload(text: "Second fixture"), limits: .init())
        await model.refresh()
        let item = try #require(model.selectedItem)
        let backspace = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: 0, windowNumber: 0, context: nil, characters: "\u{7f}", charactersIgnoringModifiers: "\u{7f}", isARepeat: false, keyCode: 51))
        #expect(!model.handleHistoryDeletionKey(backspace, responder: NSTextView()))
        #expect(!model.handleHistoryDeletionKey(backspace, responder: NSTextField()))
        model.library.section = .library
        #expect(!model.handleHistoryDeletionKey(backspace, responder: NSView()))
        model.library.section = .history
        model.selectedID = nil
        #expect(!model.handleHistoryDeletionKey(backspace, responder: NSView()))
        model.selectedID = item.id
        #expect(try await store.stats().count == 2)
        let task = model.delete(item)
        #expect(model.historyDeletionBusy)
        await model.delete(item).value // Duplicate admission is ignored.
        await task.value
        #expect(model.items.count == 1)
        #expect(model.historyDeletion?.item.id == item.id)
        #expect(!model.historyDeletionBusy)
        await model.undoHistoryDeletion().value
        #expect(model.items.count == 2)
        #expect(model.selectedID == item.id)
        #expect(model.historyDeletion == nil)
        await model.delete(item).value
        let clear = model.clear(includePinned: true)
        let staleUndo = model.undoHistoryDeletion()
        await clear.value
        await staleUndo.value
        #expect(model.historyDeletion == nil)
        await model.undoHistoryDeletion().value
        #expect(try await store.stats().count == 0)
        await model.prepareForTermination().value
    }
}
