import AppKit
import SwiftUI

/// Native multiline input keeps Return, selection, and accessibility labels in
/// AppKit without SwiftUI label overrides on hosted text views.
struct PromptTextEditor: NSViewRepresentable {
    @Binding var text: String
    let label: String
    var monospaced = false
    var focusOnAppear = false

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .bezelBorder
        let editor = PromptTextView(frame: NSRect(x: 0, y: 0, width: 100, height: 60))
        editor.isEditable = context.environment.isEnabled
        editor.isRichText = false
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.isAutomaticTextReplacementEnabled = false
        editor.isAutomaticSpellingCorrectionEnabled = false
        editor.isHorizontallyResizable = false
        editor.isVerticallyResizable = true
        editor.autoresizingMask = [.width]
        editor.textContainer?.widthTracksTextView = true
        editor.textContainer?.containerSize = NSSize(width: 100, height: CGFloat.greatestFiniteMagnitude)
        editor.textContainerInset = NSSize(width: 6, height: 6)
        editor.font = monospaced ? .monospacedSystemFont(ofSize: 13, weight: .regular) : .systemFont(ofSize: 13)
        editor.textColor = .textColor
        editor.backgroundColor = .textBackgroundColor
        editor.setAccessibilityLabel(label)
        editor.string = text
        editor.delegate = context.coordinator
        editor.focusOnAppear = focusOnAppear
        scroll.documentView = editor
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.text = $text
        guard let editor = scroll.documentView as? NSTextView else { return }
        editor.setAccessibilityLabel(label)
        editor.isEditable = context.environment.isEnabled
        if editor.string != text, !editor.hasMarkedText() {
            let range = editor.selectedRange()
            editor.string = text
            editor.setSelectedRange(NSRange(location: min(range.location, (text as NSString).length), length: 0))
        }
    }
    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        init(text: Binding<String>) { self.text = text }
        func textDidChange(_ notification: Notification) {
            guard let editor = notification.object as? NSTextView else { return }
            text.wrappedValue = editor.string
        }
    }
}

private final class PromptTextView: NSTextView {
    var focusOnAppear = false
    private var focusedInitially = false
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard focusOnAppear, !focusedInitially, window != nil else { return }
        focusedInitially = true
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.window else { return }
            window.makeFirstResponder(self)
        }
    }
}
