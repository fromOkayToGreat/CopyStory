import AppKit
import SwiftUI
import Testing
@testable import CopyStory

struct PromptTextEditorTests {
    @Test @MainActor func nativeTextEditingUpdatesBindingAndExposesLabel() throws {
        var value = "gravity"
        let host = NSHostingView(rootView: PromptTextEditor(text: Binding(get: { value }, set: { value = $0 }), label: "topic")
            .frame(width: 300, height: 100))
        host.frame = NSRect(x: 0, y: 0, width: 300, height: 100)
        host.layoutSubtreeIfNeeded()
        func textView(in view: NSView) -> NSTextView? {
            if let text = view as? NSTextView { return text }
            return view.subviews.lazy.compactMap { textView(in: $0) }.first
        }
        let editor = try #require(textView(in: host))
        #expect(editor.accessibilityLabel() == "topic")
        editor.setSelectedRange(NSRange(location: 0, length: editor.string.utf16.count))
        editor.insertText("Café", replacementRange: editor.selectedRange())
        editor.insertNewline(nil)
        editor.insertText("日本語", replacementRange: editor.selectedRange())
        #expect(value == "Café\n日本語")
        #expect(!editor.isRichText && !editor.isAutomaticQuoteSubstitutionEnabled)
        let disabled = NSHostingView(rootView: PromptTextEditor(text: .constant("saving"), label: "disabled field")
            .frame(width: 300, height: 100).disabled(true))
        disabled.frame = NSRect(x: 0, y: 0, width: 300, height: 100)
        disabled.layoutSubtreeIfNeeded()
        #expect(try #require(textView(in: disabled)).isEditable == false)
    }
}
