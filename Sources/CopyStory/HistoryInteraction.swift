import AppKit
import SwiftUI

/// Shared by the real panel and inert fixtures. Never consumes editing commands.
enum HistoryDeletionKeys {
    enum Action: Equatable { case delete, undo, consumeRepeat }
    static func action(keyCode: UInt16, characters: String?, modifiers: NSEvent.ModifierFlags, repeating: Bool,
                       history: Bool, editable: Bool, searching: Bool, busy: Bool,
                       selected: Bool, canUndo: Bool) -> Action? {
        guard history, !editable, !searching, !busy else { return nil }
        let flags = modifiers.intersection([.command, .control, .option, .shift, .function])
        if keyCode == 51, flags.isEmpty || flags == .command, selected {
            return repeating ? .consumeRepeat : .delete
        }
        if characters?.lowercased() == "z", flags == .command, canUndo {
            return repeating ? .consumeRepeat : .undo
        }
        return nil
    }
    @MainActor static func isEditing(_ responder: NSResponder?) -> Bool {
        // Include custom text input clients, not just the standard field editor.
        responder is NSTextInputClient || (responder as? NSTextField)?.isEditable == true
    }
}

extension AppModel {
    @MainActor @discardableResult
    func handleHistoryDeletionKey(_ event: NSEvent, responder: NSResponder?) -> Bool {
        guard let action = HistoryDeletionKeys.action(keyCode: event.keyCode, characters: event.charactersIgnoringModifiers, modifiers: event.modifierFlags,
            repeating: event.isARepeat, history: library.section == .history,
            editable: HistoryDeletionKeys.isEditing(responder), searching: isSearching,
            busy: historyDeletionBusy, selected: selectedItem != nil, canUndo: historyDeletion != nil) else { return false }
        switch action {
        case .delete: if let item = selectedItem { delete(item) }
        case .undo: undoHistoryDeletion()
        case .consumeRepeat: break
        }
        return true
    }
}

/// Pointer translations use screen-view coordinates (left is negative), unlike
/// device scroll deltas. This policy only reveals/closes; it never deletes.
enum HistoryMouseDrag {
    static let actionWidth: CGFloat = 90
    static func horizontal(_ translation: CGSize, threshold: CGFloat) -> Bool {
        abs(translation.width) >= threshold && abs(translation.width) > abs(translation.height) * 1.5
    }
    static func offset(translation: CGSize, revealed: Bool) -> CGFloat {
        let resting: CGFloat = revealed ? -actionWidth : 0
        guard horizontal(translation, threshold: 8) else { return resting }
        return min(0, max(-actionWidth, resting + translation.width))
    }
    static func destination(translation: CGSize, revealed: Bool) -> Bool? {
        guard horizontal(translation, threshold: 32) else { return nil }
        if translation.width < 0 { return true }
        return revealed ? false : nil // No action on right-drag from a closed row.
    }
}

/// A gesture can reveal/close an action, but cannot delete. Lock vertical intent
/// for the entire gesture so diagonal scrolling never becomes a destructive swipe.
struct HistorySwipeIntent {
    enum Axis { case pending, horizontal, vertical }
    private(set) var axis: Axis = .pending
    private var x: CGFloat = 0
    private var y: CGFloat = 0
    mutating func reset() { self = Self() }
    mutating func update(dx: CGFloat, dy: CGFloat) -> Bool? {
        x += dx; y += dy
        if axis == .pending, max(abs(x), abs(y)) >= 8 {
            axis = abs(x) > abs(y) * 1.5 ? .horizontal : .vertical
        }
        guard axis == .horizontal, abs(x) >= 32 else { return nil }
        return x > 0 // Device direction: left reveals; right only dismisses.
    }
}

/// Gesture ownership ends on finger-up even when no momentum follows. Only an
/// explicitly phased momentum sequence can inherit suppression from that swipe.
struct HistorySwipeSession {
    struct Result: Equatable {
        var consume = false
        var reveal: Bool? = nil
    }
    private var intent = HistorySwipeIntent()
    private(set) var tracking = false
    private(set) var suppressMomentum = false
    mutating func reset() { self = Self() }
    mutating func handle(dx: CGFloat, dy: CGFloat, invertedFromDevice: Bool,
                         phase: NSEvent.Phase, momentumPhase: NSEvent.Phase) -> Result {
        if phase.contains(.began) { reset(); tracking = true }
        if !momentumPhase.isEmpty {
            let consume = suppressMomentum
            if momentumPhase.contains(.ended) || momentumPhase.contains(.cancelled) { reset() }
            return Result(consume: consume)
        }
        // Mouse wheels/unphased input never inherit a completed swipe. A new
        // possible gesture also clears a pending momentum latch before beginning.
        if phase.isEmpty || phase.contains(.mayBegin) { reset(); return Result() }
        guard tracking else { return Result() }
        if phase.contains(.cancelled) {
            let consume = intent.axis == .horizontal
            reset()
            return Result(consume: consume)
        }
        if phase.contains(.ended) {
            let consume = intent.axis == .horizontal
            tracking = false
            suppressMomentum = consume
            intent.reset()
            return Result(consume: consume)
        }
        // NSEvent inverts scrolling deltas for Natural Scrolling. Undo that
        // inversion to keep physical left/right gestures independent of settings.
        let direction: CGFloat = invertedFromDevice ? -1 : 1
        let reveal = intent.update(dx: dx * direction, dy: dy * direction)
        return Result(consume: intent.axis == .horizontal, reveal: reveal)
    }
}

/// SwiftUI's general swipe-action container needs macOS 27. This narrow bridge
/// preserves the existing macOS 26 ScrollView geometry and vertical scrolling.
struct HistoryRowSwipeInput: NSViewRepresentable {
    var enabled: Bool
    var reveal: (Bool) -> Void
    func makeNSView(context: Context) -> InputView { InputView() }
    func updateNSView(_ view: InputView, context: Context) {
        view.enabled = enabled
        view.reveal = reveal
    }
    static func dismantleNSView(_ view: InputView, coordinator: ()) { view.removeMonitor() }

    final class InputView: NSView {
        var enabled = true
        var reveal: (Bool) -> Void = { _ in }
        private var monitor: Any?
        private var session = HistorySwipeSession()
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            removeMonitor()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self else { return event }
                return self.handle(event)
            }
        }
        func removeMonitor() {
            if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
            session.reset()
        }
        deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
        private func handle(_ event: NSEvent) -> NSEvent? {
            guard enabled, let window, event.window === window, window.isKeyWindow,
                  window.attachedSheet == nil, !isHiddenOrHasHiddenAncestor,
                  visibleRect.contains(convert(event.locationInWindow, from: nil)),
                  event.hasPreciseScrollingDeltas,
                  event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty else {
                session.reset(); return event
            }
            let result = session.handle(dx: event.scrollingDeltaX, dy: event.scrollingDeltaY,
                invertedFromDevice: event.isDirectionInvertedFromDevice,
                phase: event.phase, momentumPhase: event.momentumPhase)
            if let open = result.reveal { reveal(open) }
            return result.consume ? nil : event
        }
    }
}
